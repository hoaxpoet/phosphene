// SystemAudioCapture — System audio capture via Core Audio taps (macOS 14.2+).
// Captures the system audio mix or a specific application's audio output
// as PCM float32 stereo at 48kHz using AudioHardwareCreateProcessTap.
//
// Core Audio taps are purpose-built for audio tapping and work reliably
// on macOS 14.2+. ScreenCaptureKit was tried first but fails to deliver
// audio callbacks on macOS 15+/26 despite video frames arriving.
//
// This is Phosphene's primary audio input. Local file playback exists
// only as a testing/offline fallback.

import Foundation
import CoreAudio
import AudioToolbox
import AppKit
import os.log

private let logger = Logger(subsystem: "com.phosphene.audio", category: "SystemAudioCapture")

// MARK: - AudioCaptureError

public enum AudioCaptureError: Error, Sendable {
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case alreadyCapturing
    case notCapturing
    case applicationNotFound(String)
    case processLookupFailed(String)
}

// MARK: - CaptureMode

/// Describes what audio to capture.
public enum CaptureMode: Sendable, Equatable {
    /// Capture the entire system audio mix (all applications).
    case systemAudio
    /// Capture audio from a specific running application by bundle identifier.
    case application(bundleIdentifier: String)
}

// MARK: - RunningApplication

/// A lightweight description of a running application that produces audio.
public struct RunningApplication: Sendable, Identifiable {
    public let id: String  // bundle identifier
    public let name: String
    public let processID: pid_t

    public init(id: String, name: String, processID: pid_t) {
        self.id = id
        self.name = name
        self.processID = processID
    }
}

// MARK: - SystemAudioCapture

/// Captures system or per-app audio via Core Audio process taps.
///
/// Usage:
/// ```swift
/// let capture = SystemAudioCapture()
/// capture.onAudioBuffer = { samples, sampleRate, channelCount in
///     // samples: UnsafePointer<Float>, interleaved stereo float32
/// }
/// try capture.startCapture(mode: .systemAudio)
/// // ...
/// capture.stopCapture()
/// ```
@available(macOS 14.2, *)
public final class SystemAudioCapture: AudioCapturing, @unchecked Sendable {

    // MARK: - Init

    public init() {}

    // MARK: - Configuration

    /// Sample rate reported by the tap (typically 48kHz).
    public private(set) var sampleRate: Float = 48000

    /// Number of audio channels reported by the tap (typically 2).
    public private(set) var channelCount: UInt32 = 2

    // MARK: - Callback

    /// Called on each audio IO callback with interleaved float32 PCM samples.
    /// Parameters: (pointer to samples, sample count, sample rate, channel count).
    /// Called on a real-time audio thread — do not allocate or block.
    public var onAudioBuffer: ((_ samples: UnsafePointer<Float>, _ sampleCount: Int,
                                _ sampleRate: Float, _ channelCount: UInt32) -> Void)?

    // MARK: - State

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioDeviceID = 0
    private var procID: AudioDeviceIOProcID?
    private var _isCapturing = false
    private var tapUUID = UUID()

    private let stateLock = NSLock()

    public var isCapturing: Bool {
        stateLock.withLock { _isCapturing }
    }

    // MARK: - Enumeration

    /// Lists running applications (by inspecting NSRunningApplication).
    public static func availableApplications() -> [RunningApplication] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier,
                  !bundleID.isEmpty,
                  app.activationPolicy == .regular else { return nil }
            return RunningApplication(
                id: bundleID,
                name: app.localizedName ?? bundleID,
                processID: app.processIdentifier
            )
        }
    }

    // MARK: - Capture

    /// Start capturing audio.
    ///
    /// - Parameter mode: System-wide or app-specific capture.
    public func startCapture(mode: CaptureMode = .systemAudio) throws {
        stateLock.lock()
        guard !_isCapturing else {
            stateLock.unlock()
            throw AudioCaptureError.alreadyCapturing
        }
        _isCapturing = true
        stateLock.unlock()

        do {
            // Step 1: Create the process tap.
            tapUUID = UUID()
            let tapDesc = try buildTapDescription(for: mode)

            var newTapID: AudioObjectID = 0
            let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &newTapID)
            guard tapStatus == noErr else {
                stateLock.withLock { _isCapturing = false }
                throw AudioCaptureError.tapCreationFailed(tapStatus)
            }

            stateLock.withLock { self.tapID = newTapID }
            logger.info("Process tap created (ID: \(newTapID))")

            // Step 2: Read the tap's audio format.
            readTapFormat(tapID: newTapID)

            // Step 3: Create aggregate device containing the tap.
            let aggDesc: [String: Any] = [
                kAudioAggregateDeviceNameKey as String: "PhospheneAggregate",
                kAudioAggregateDeviceUIDKey as String: "com.phosphene.aggregate.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey as String: true,
                kAudioAggregateDeviceTapListKey as String: [[
                    kAudioSubTapUIDKey as String: tapUUID.uuidString
                ]],
                kAudioAggregateDeviceTapAutoStartKey as String: true
            ]

            var newAggregateID: AudioDeviceID = 0
            let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newAggregateID)
            guard aggStatus == noErr else {
                cleanup()
                throw AudioCaptureError.aggregateDeviceCreationFailed(aggStatus)
            }

            stateLock.withLock { self.aggregateID = newAggregateID }
            logger.info("Aggregate device created (ID: \(newAggregateID))")

            // Step 4: Set up IO proc.
            let callback = self.onAudioBuffer
            let sr = self.sampleRate
            let ch = self.channelCount

            var newProcID: AudioDeviceIOProcID?
            let procStatus = AudioDeviceCreateIOProcIDWithBlock(
                &newProcID, newAggregateID, nil
            ) { _, inInputData, _, _, _ in
                let buffers = UnsafeMutableAudioBufferListPointer(
                    UnsafeMutablePointer(mutating: inInputData)
                )
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    let floatCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    guard floatCount > 0 else { continue }

                    let floatPtr = data.bindMemory(to: Float.self, capacity: floatCount)
                    callback?(floatPtr, floatCount, sr, ch)
                    break  // Process first buffer only (stereo interleaved)
                }
            }

            guard procStatus == noErr else {
                cleanup()
                throw AudioCaptureError.ioProcCreationFailed(procStatus)
            }

            stateLock.withLock { self.procID = newProcID }

            // Step 5: Start capture.
            let startStatus = AudioDeviceStart(newAggregateID, newProcID)
            guard startStatus == noErr else {
                cleanup()
                throw AudioCaptureError.deviceStartFailed(startStatus)
            }

            logger.info("Audio capture started: \(String(describing: mode)), \(sr) Hz, \(ch) ch")

        } catch {
            stateLock.withLock { _isCapturing = false }
            throw error
        }
    }

    /// Stop the current audio capture session.
    public func stopCapture() {
        cleanup()
        logger.info("Audio capture stopped")
    }

    /// Switch capture mode. Stops current capture and starts new one.
    public func switchMode(_ mode: CaptureMode) throws {
        if isCapturing {
            stopCapture()
        }
        try startCapture(mode: mode)
    }

    // MARK: - Private Helpers

    private func buildTapDescription(for mode: CaptureMode) throws -> CATapDescription {
        switch mode {
        case .systemAudio:
            // Capture all system audio — exclude nothing.
            let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            desc.uuid = tapUUID
            desc.name = "PhospheneSystemTap"
            return desc

        case .application(let bundleIdentifier):
            // Find the process ID for the target application.
            guard let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleIdentifier
            }) else {
                throw AudioCaptureError.applicationNotFound(bundleIdentifier)
            }

            let desc = CATapDescription(stereoMixdownOfProcesses: [AudioObjectID(app.processIdentifier)])
            desc.uuid = tapUUID
            desc.name = "PhospheneAppTap-\(bundleIdentifier)"
            return desc
        }
    }

    private func readTapFormat(tapID: AudioObjectID) {
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var format = AudioStreamBasicDescription()
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(tapID, &addr, 0, nil, &formatSize, &format)
        if status == noErr {
            sampleRate = Float(format.mSampleRate)
            channelCount = format.mChannelsPerFrame
            logger.info("Tap format: \(format.mSampleRate) Hz, \(format.mChannelsPerFrame) ch, \(format.mBitsPerChannel) bit")
        } else {
            logger.warning("Could not read tap format (\(status)), using defaults (48kHz stereo)")
        }
    }

    private func cleanup() {
        stateLock.lock()
        let agg = aggregateID
        let tap = tapID
        let proc = procID

        if agg != 0 {
            AudioDeviceStop(agg, proc)
            if let proc {
                AudioDeviceDestroyIOProcID(agg, proc)
            }
            AudioHardwareDestroyAggregateDevice(agg)
        }
        if tap != 0 {
            AudioHardwareDestroyProcessTap(tap)
        }

        aggregateID = 0
        tapID = 0
        procID = nil
        _isCapturing = false
        stateLock.unlock()
    }

    deinit {
        cleanup()
    }
}
