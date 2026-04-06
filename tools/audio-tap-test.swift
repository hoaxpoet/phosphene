// audio-tap-test — Test system audio capture via Core Audio taps (macOS 14.2+).
//
// Core Audio taps are Apple's preferred API for audio-only system capture.
// Unlike ScreenCaptureKit (which is designed for screen+audio recording),
// Core Audio taps are purpose-built for tapping audio output.
//
// Build & run:
//   swiftc tools/audio-tap-test.swift -o tools/audio-tap-test \
//     -framework CoreAudio -framework AudioToolbox -framework AVFoundation -framework Accelerate
//   ./tools/audio-tap-test

import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import Accelerate

// MARK: - Configuration

let captureDuration: TimeInterval = 5.0
let fftSize = 1024
let binCount = fftSize / 2
let log2n = vDSP_Length(log2(Double(fftSize)))

// MARK: - Global State

var gFFTSetup: FFTSetup!
var gWindow = [Float](repeating: 0, count: 1024)
var gMonoBuffer = [Float](repeating: 0, count: 1024)
var gMonoWritePos = 0
var gMonoFilled = false
var gCallbackCount = 0

// MARK: - FFT

func runFFT(sampleRate: Float) {
    var ordered = [Float](repeating: 0, count: fftSize)
    for i in 0..<fftSize {
        ordered[i] = gMonoBuffer[(gMonoWritePos + i) % fftSize]
    }
    vDSP_vmul(ordered, 1, gWindow, 1, &ordered, 1, vDSP_Length(fftSize))

    var realPart = [Float](repeating: 0, count: binCount)
    var imagPart = [Float](repeating: 0, count: binCount)

    ordered.withUnsafeBufferPointer { srcPtr in
        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                srcPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: binCount) { cPtr in
                    vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(binCount))
                }
                vDSP_fft_zrip(gFFTSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                var magnitudes = [Float](repeating: 0, count: binCount)
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(binCount))

                var scale: Float = 2.0 / Float(fftSize)
                vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(binCount))

                var maxMag: Float = 0
                var maxIdx: vDSP_Length = 0
                vDSP_maxvi(magnitudes, 1, &maxMag, &maxIdx, vDSP_Length(binCount))
                let binRes = sampleRate / Float(fftSize)
                let domFreq = Float(maxIdx) * binRes

                let barCount = 32
                let binsPerBar = binCount / barCount
                var bars = [Float](repeating: 0, count: barCount)
                for b in 0..<barCount {
                    var m: Float = 0
                    for j in 0..<binsPerBar {
                        let idx = b * binsPerBar + j
                        if idx < binCount { m = max(m, magnitudes[idx]) }
                    }
                    bars[b] = m
                }

                let gMax = bars.max() ?? 1.0
                let hScale: Float = gMax > 0 ? 1.0 / gMax : 1.0

                print("")
                print(String(format: "  ┌─ FFT Spectrum ── dominant: %.0f Hz @ %.3f ──", domFreq, maxMag))
                for b in 0..<barCount {
                    let freq = Float(b * binsPerBar) * binRes
                    let norm = bars[b] * hScale
                    let w = Int(norm * 40)
                    print(String(format: "  │ %5.0f Hz │%@", freq, String(repeating: "█", count: w)))
                }
                print("  └────────────────────────────────────────────")
                print("")
            }
        }
    }
}

// MARK: - Main

guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
    print("ERROR: Failed to create FFT setup")
    exit(1)
}
gFFTSetup = setup
vDSP_hann_window(&gWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

print("╔═══════════════════════════════════════════════════╗")
print("║  Phosphene Audio Tap Test (Core Audio Taps)      ║")
print("║  Capturing \(Int(captureDuration))s of system audio via process tap   ║")
print("║  Play music in any app before running this.      ║")
print("╚═══════════════════════════════════════════════════╝")
print("")

let osVersion = ProcessInfo.processInfo.operatingSystemVersion
print("macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")

// Step 1: Create a process tap for all system audio.
// An empty process list with isMuted=false captures all system output.
// Use stereoGlobalTapButExcludeProcesses with empty list = capture ALL system audio.
// (stereoMixdownOfProcesses: [] means "mix zero processes" = silence)
var tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
tapDesc.uuid = UUID()
tapDesc.name = "PhospheneAudioTap"

var tapID: AudioObjectID = 0
var status = AudioHardwareCreateProcessTap(tapDesc, &tapID)
guard status == noErr else {
    print("ERROR: AudioHardwareCreateProcessTap failed: \(status)")
    print("This API requires macOS 14.2+. Your macOS version: \(osVersion.majorVersion).\(osVersion.minorVersion)")
    exit(1)
}
print("✓ Process tap created (ID: \(tapID))")

// Step 2: Get the tap's audio format.
var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
var tapFormat = AudioStreamBasicDescription()
var formatAddr = AudioObjectPropertyAddress(
    mSelector: kAudioTapPropertyFormat,
    mScope: kAudioObjectPropertyScopeOutput,
    mElement: kAudioObjectPropertyElementMain
)
status = AudioObjectGetPropertyData(
    tapID,
    &formatAddr,
    0, nil,
    &formatSize,
    &tapFormat
)

if status == noErr {
    print("Tap format: \(tapFormat.mSampleRate) Hz, \(tapFormat.mChannelsPerFrame) ch, \(tapFormat.mBitsPerChannel) bit")
} else {
    print("Warning: Could not read tap format (\(status)), using defaults")
    tapFormat.mSampleRate = 48000
    tapFormat.mChannelsPerFrame = 2
}

// Step 3: Create an aggregate device containing the tap.
let aggDesc: [String: Any] = [
    kAudioAggregateDeviceNameKey as String: "PhospheneAggregate",
    kAudioAggregateDeviceUIDKey as String: "com.phosphene.aggregate.\(UUID().uuidString)",
    kAudioAggregateDeviceIsPrivateKey as String: true,
    kAudioAggregateDeviceTapListKey as String: [[
        kAudioSubTapUIDKey as String: tapDesc.uuid.uuidString
    ]],
    kAudioAggregateDeviceTapAutoStartKey as String: true
]

var aggregateID: AudioDeviceID = 0
status = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggregateID)
guard status == noErr else {
    print("ERROR: AudioHardwareCreateAggregateDevice failed: \(status)")
    AudioHardwareDestroyProcessTap(tapID)
    exit(1)
}
print("✓ Aggregate device created (ID: \(aggregateID))")

// Step 4: Check aggregate device streams.
var streamSize: UInt32 = 0
var inputStreamAddr = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyStreams,
    mScope: kAudioDevicePropertyScopeInput,
    mElement: kAudioObjectPropertyElementMain
)
AudioObjectGetPropertyDataSize(aggregateID, &inputStreamAddr, 0, nil, &streamSize)
let inputStreamCount = Int(streamSize) / MemoryLayout<AudioStreamID>.size
print("Aggregate device input streams: \(inputStreamCount)")

var outputStreamAddr = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyStreams,
    mScope: kAudioDevicePropertyScopeOutput,
    mElement: kAudioObjectPropertyElementMain
)
AudioObjectGetPropertyDataSize(aggregateID, &outputStreamAddr, 0, nil, &streamSize)
let outputStreamCount = Int(streamSize) / MemoryLayout<AudioStreamID>.size
print("Aggregate device output streams: \(outputStreamCount)")

// Step 5: Set up an IO proc to receive audio callbacks.
let sampleRate = Float(tapFormat.mSampleRate > 0 ? tapFormat.mSampleRate : 48000)
let channels = Int(tapFormat.mChannelsPerFrame > 0 ? tapFormat.mChannelsPerFrame : 2)

var procID: AudioDeviceIOProcID?
status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { inNow, inInputData, inInputTime, outOutputData, inOutputTime in
    // inInputData is UnsafePointer<AudioBufferList>
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))

    for buffer in buffers {
        guard let data = buffer.mData else { continue }
        let floatCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        guard floatCount > 0 else { continue }

        let floatPtr = data.bindMemory(to: Float.self, capacity: floatCount)

        // Compute RMS.
        var rms: Float = 0
        for i in 0..<floatCount {
            rms += floatPtr[i] * floatPtr[i]
        }
        rms = sqrtf(rms / Float(floatCount))

        // Mix to mono → ring buffer.
        let frames = floatCount / max(channels, 1)
        for i in 0..<frames {
            var mono: Float = 0
            if channels >= 2 && i * 2 + 1 < floatCount {
                mono = (floatPtr[i * 2] + floatPtr[i * 2 + 1]) * 0.5
            } else {
                mono = floatPtr[min(i, floatCount - 1)]
            }
            gMonoBuffer[gMonoWritePos] = mono
            gMonoWritePos = (gMonoWritePos + 1) % fftSize
            if gMonoWritePos == 0 { gMonoFilled = true }
        }

        gCallbackCount += 1

        let rmsDB = rms > 0 ? 20 * log10f(rms) : -120
        let barLen = max(0, Int((rmsDB + 60) * 0.8))
        let bar = String(repeating: "█", count: min(barLen, 48))
        print(String(format: "CB %4d | %d samples | RMS: %.4f (%+6.1f dB) |%@",
                      gCallbackCount, floatCount, rms, rmsDB, bar))

        if gMonoFilled && gCallbackCount % 8 == 0 {
            runFFT(sampleRate: sampleRate)
        }

        break // Only process first buffer
    }
}

guard status == noErr else {
    print("ERROR: AudioDeviceCreateIOProcIDWithBlock failed: \(status)")
    AudioHardwareDestroyAggregateDevice(aggregateID)
    AudioHardwareDestroyProcessTap(tapID)
    exit(1)
}

// Step 6: Start capture.
status = AudioDeviceStart(aggregateID, procID)
guard status == noErr else {
    print("ERROR: AudioDeviceStart failed: \(status)")
    AudioHardwareDestroyAggregateDevice(aggregateID)
    AudioHardwareDestroyProcessTap(tapID)
    exit(1)
}
print("✓ Audio capture started. Listening for \(Int(captureDuration)) seconds...")
print("")

// Run for duration.
Thread.sleep(forTimeInterval: captureDuration)

// Cleanup.
AudioDeviceStop(aggregateID, procID)
if let procID = procID {
    AudioDeviceDestroyIOProcID(aggregateID, procID)
}
AudioHardwareDestroyAggregateDevice(aggregateID)
AudioHardwareDestroyProcessTap(tapID)
vDSP_destroy_fftsetup(gFFTSetup)

print("")
print("═══════════════════════════════════════════════════")
print("  Capture complete. \(gCallbackCount) audio callbacks received.")
if gCallbackCount == 0 {
    print("  ⚠ No audio callbacks. Is music playing?")
} else {
    print("  ✓ Core Audio tap pipeline is working.")
}
print("═══════════════════════════════════════════════════")
