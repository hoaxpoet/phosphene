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
//
// swiftlint:disable file_length
// Crossed the 400-line warning with the BUG-057 install-probe instrumentation
// (per-(re)install device/rate/preflight logging + a first-seconds RMS probe).
// This is temporary diagnostic mass for the cold-tap-silence defect; the fix
// increment will trim or relocate it. Splitting now would obscure the capture
// lifecycle the probe is measuring.

import Foundation
import CoreAudio
import AudioToolbox
import AppKit
import CoreGraphics
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

    /// Sample rate reported by the tap (typically 48kHz). Captured once at tap
    /// install — never mutate from the audio IO callback: an unsynchronized
    /// cross-core write is not guaranteed visible to other threads and produces
    /// rare wrong-tempo sessions (D-079). If a capture-mode switch changes the
    /// rate, tear down and re-init dependent consumers rather than mutating
    /// this in place.
    public private(set) var sampleRate: Float = 48000

    /// Number of audio channels reported by the tap (typically 2).
    public private(set) var channelCount: UInt32 = 2

    // MARK: - Callback

    /// Called on each audio IO callback with interleaved float32 PCM samples.
    /// Parameters: (pointer to samples, sample count, sample rate, channel count).
    /// Called on a real-time audio thread — do not allocate or block.
    public var onAudioBuffer: ((_ samples: UnsafePointer<Float>, _ sampleCount: Int,
                                _ sampleRate: Float, _ channelCount: UInt32) -> Void)?

    /// BUG-057 instrumentation sink — install lifecycle + first-seconds RMS.
    /// See `AudioCapturing.onCaptureDiagnostic`.
    public var onCaptureDiagnostic: ((_ message: String) -> Void)?

    // MARK: - State

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioDeviceID = 0
    private var procID: AudioDeviceIOProcID?
    private var _isCapturing = false
    private var tapUUID = UUID()

    /// The mode the active capture was started with — replayed by
    /// `performReinstall` when the default output device changes (CLEAN.1.5).
    private var currentMode: CaptureMode?

    /// Watches the default output device; on change the tap is reinstalled so the
    /// visualizer keeps receiving audio instead of freezing (CLEAN.1.5 / GAP-1).
    private let deviceMonitor = DefaultOutputDeviceMonitor()

    /// Serial queue for tap reinstall — kept OFF the monitor's listener queue so
    /// teardown/destroy never runs reentrantly from inside the Core Audio callback.
    private let reinstallQueue = DispatchQueue(label: "com.phosphene.audio.tapReinstall")

    private let stateLock = NSLock()

    // MARK: - BUG-057 install-probe state (guarded by stateLock)

    /// Increments on every successful (re)install so each session.log RMS line
    /// is attributable to a specific tap install (cold vs device-change reinstall).
    private var installGeneration = 0
    /// CFAbsoluteTime the current install armed its probe window.
    private var installWallclock: CFAbsoluteTime = 0
    /// CFAbsoluteTime of the last emitted RMS sample (throttles the probe to ~1 Hz).
    private var lastInstallRMSLogTime: CFAbsoluteTime = 0
    /// How long after each install to keep sampling tap RMS into session.log.
    private let installProbeWindowSeconds: CFAbsoluteTime = 10.0

    public var isCapturing: Bool {
        stateLock.withLock { _isCapturing }
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
        currentMode = mode
        stateLock.unlock()

        do {
            let newTapID = try createProcessTap(for: mode)
            readTapFormat(tapID: newTapID)
            let newAggregateID = try createAggregateDevice()
            let newProcID = try createIOProc(aggregateID: newAggregateID)
            try startDevice(aggregateID: newAggregateID, procID: newProcID)

            // CLEAN.1.5 (GAP-1): reinstall the tap when the default output device
            // changes (AirPods connect / monitor unplug) so visuals don't freeze
            // on the now-dead device. The listener fires on the monitor's queue;
            // the actual reinstall is dispatched to `reinstallQueue`.
            deviceMonitor.start { [weak self] in
                // BUG-058: breadcrumb the monitor FIRING (os_log .info isn't persisted,
                // so session.log is the only post-hoc record of whether the
                // default-output-change listener actually delivered).
                self?.onCaptureDiagnostic?("device-change monitor FIRED → scheduling performReinstall")
                self?.reinstallQueue.async { [weak self] in self?.performReinstall() }
            }

            let sr = self.sampleRate
            let ch = self.channelCount
            logger.info("Audio capture started: \(String(describing: mode)), \(sr) Hz, \(ch) ch")
            // BUG-057: the very first call is the cold install; subsequent calls
            // are the router's `.silent`-recovery reinstalls (stopCapture +
            // startCapture). The generation counter + the preceding router
            // "Tap reinstall #N" line disambiguate the two in session.log.
            armInstallProbeAndLog(kind: "install via startCapture")
        } catch {
            stateLock.withLock { _isCapturing = false }
            throw error
        }
    }

    // MARK: - Capture Setup Steps

    private func createProcessTap(for mode: CaptureMode) throws -> AudioObjectID {
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
        return newTapID
    }

    private func createAggregateDevice() throws -> AudioDeviceID {
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
        return newAggregateID
    }

    private func createIOProc(aggregateID: AudioDeviceID) throws -> AudioDeviceIOProcID {
        let callback = self.onAudioBuffer
        let sr = self.sampleRate
        let ch = self.channelCount

        var newProcID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(
            &newProcID, aggregateID, nil
        ) { [weak self] _, inInputData, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: inInputData)
            )
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let floatCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                guard floatCount > 0 else { continue }

                let floatPtr = data.bindMemory(to: Float.self, capacity: floatCount)
                callback?(floatPtr, floatCount, sr, ch)
                self?.probeInstallRMS(floatPtr, floatCount)  // BUG-057
                break  // Process first buffer only (stereo interleaved)
            }
        }

        guard procStatus == noErr, let procID = newProcID else {
            cleanup()
            throw AudioCaptureError.ioProcCreationFailed(procStatus)
        }

        stateLock.withLock { self.procID = procID }
        return procID
    }

    private func startDevice(aggregateID: AudioDeviceID, procID: AudioDeviceIOProcID) throws {
        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            cleanup()
            throw AudioCaptureError.deviceStartFailed(startStatus)
        }
    }

    /// Stop the current audio capture session.
    public func stopCapture() {
        cleanup()
        logger.info("Audio capture stopped")
    }

    // MARK: - Private Helpers

    private func buildTapDescription(for mode: CaptureMode) throws -> CATapDescription {
        switch mode {
        case .systemAudio:
            // Capture all system audio — exclude nothing. This MUST be the
            // exclude-processes variant. The seemingly equivalent
            // `CATapDescription(stereoMixdownOfProcesses: [])` ("mix down these
            // processes", empty list) succeeds but delivers pure silence —
            // discovered the hard way. Do not swap the initializer.
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

    /// Reinstall the tap against the current default output device (CLEAN.1.5 /
    /// GAP-1). Runs on `reinstallQueue` — never the monitor's listener queue — so
    /// the teardown/create calls (incl. `cleanup()` on a create failure, which
    /// removes the listener) never reenter the Core Audio property callback.
    private func performReinstall() {
        let mode: CaptureMode? = stateLock.withLock { _isCapturing ? currentMode : nil }
        guard let mode else {
            // BUG-058: a fired monitor whose reinstall no-ops (capture already torn
            // down) is itself a diagnosis — record it rather than returning silently.
            onCaptureDiagnostic?("performReinstall: SKIPPED (not capturing / no mode)")
            return
        }
        logger.info("Default output device changed — reinstalling tap")
        // BUG-058 step breadcrumbs: os_log .info isn't persisted, so the last
        // session.log line before silence pins exactly which Core Audio call
        // stalls during the device transition (monitor-fired vs teardown vs a
        // specific create call hanging vs a clean success).
        onCaptureDiagnostic?("performReinstall: ENTER → tearing down")
        teardownTapResources()
        onCaptureDiagnostic?("performReinstall: teardown done → createProcessTap")
        do {
            let newTapID = try createProcessTap(for: mode)
            onCaptureDiagnostic?("performReinstall: tap created (\(newTapID)) → readTapFormat + createAggregateDevice")
            readTapFormat(tapID: newTapID)
            let newAggregateID = try createAggregateDevice()
            onCaptureDiagnostic?("performReinstall: aggregate created (\(newAggregateID)) → createIOProc")
            let newProcID = try createIOProc(aggregateID: newAggregateID)
            onCaptureDiagnostic?("performReinstall: IO proc created → startDevice")
            try startDevice(aggregateID: newAggregateID, procID: newProcID)
            logger.info("Tap reinstalled after device change (tap \(newTapID))")
            armInstallProbeAndLog(kind: "reinstall via device-change")  // BUG-057
        } catch {
            // The create steps already tore down + stopped the monitor on failure.
            logger.error("Tap reinstall failed after device change: \(String(describing: error))")
            onCaptureDiagnostic?("reinstall via device-change FAILED: \(String(describing: error))")
        }
    }

    /// Destroy the tap / aggregate / IO-proc without touching the monitor or the
    /// `_isCapturing` flag — the teardown half of `performReinstall`. `cleanup()`
    /// wraps this with monitor-stop + `_isCapturing = false`.
    private func teardownTapResources() {
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
        stateLock.unlock()
    }

    // MARK: - BUG-057 Instrumentation

    /// Log the bound default-output device, tap rate, and Screen-Recording
    /// preflight at a successful (re)install, and (re)arm the first-seconds RMS
    /// probe for a fresh generation. The diagnostic candidates (TCC-not-yet-
    /// effective, DRM-zeroing, cold-bind-before-audio, insufficient reinstall)
    /// are separable from this line + the per-generation RMS samples + the
    /// existing `audio signal → …` transitions, all interleaved in session.log.
    private func armInstallProbeAndLog(kind: String) {
        let deviceID = deviceMonitor.currentDefaultOutputDeviceID()
        let preflight = CGPreflightScreenCaptureAccess()
        let rate = self.sampleRate
        let gen: Int = stateLock.withLock {
            installGeneration += 1
            installWallclock = CFAbsoluteTimeGetCurrent()
            lastInstallRMSLogTime = 0
            return installGeneration
        }
        onCaptureDiagnostic?(
            "\(kind) gen=\(gen) defaultOutputDevice=\(deviceID) rate=\(Int(rate)) Hz "
            + "screenRecordingPreflight=\(preflight)")
    }

    /// For the first `installProbeWindowSeconds` of each install, emit a ~1 Hz
    /// RMS/peak sample tagged with the install generation, so session.log shows
    /// whether THIS tap delivered signal or stayed silent. Called from the RT IO
    /// proc; the uncontended per-buffer stateLock matches `SilenceDetector`'s
    /// existing per-buffer lock in the same call chain.
    /// ponytail: scalar RMS loop runs only at the ~1 Hz emit boundary, not every
    /// buffer — no Accelerate dependency needed for a temporary diagnostic.
    private func probeInstallRMS(_ samples: UnsafePointer<Float>, _ count: Int) {
        guard count > 0 else { return }
        let now = CFAbsoluteTimeGetCurrent()
        var gen = 0
        var wallclock: CFAbsoluteTime = 0
        var shouldLog = false
        stateLock.withLock {
            gen = installGeneration
            wallclock = installWallclock
            let elapsed = now - installWallclock
            if elapsed <= installProbeWindowSeconds, now - lastInstallRMSLogTime >= 1.0 {
                lastInstallRMSLogTime = now
                shouldLog = true
            }
        }
        guard shouldLog else { return }

        var sumSq: Float = 0
        var peak: Float = 0
        for i in 0..<count {
            let sample = samples[i]
            sumSq += sample * sample
            let mag = abs(sample)
            if mag > peak { peak = mag }
        }
        let rms = (sumSq / Float(count)).squareRoot()
        onCaptureDiagnostic?(String(
            format: "tap RMS gen=%d t=+%.1fs rms=%.6f peak=%.6f", gen, now - wallclock, rms, peak))
    }

    private func cleanup() {
        deviceMonitor.stop()
        teardownTapResources()
        stateLock.withLock { _isCapturing = false }
    }

    deinit {
        cleanup()
    }
}
