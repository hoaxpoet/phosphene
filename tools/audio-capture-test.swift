// audio-capture-test — Standalone test for the Increment 1.3 audio pipeline.
//
// Captures 5 seconds of system audio via ScreenCaptureKit, prints per-frame
// RMS levels and a text FFT histogram to the console.
//
// Build & run:
//   swiftc tools/audio-capture-test.swift -o tools/audio-capture-test \
//     -framework ScreenCaptureKit -framework CoreMedia -framework Accelerate
//   ./tools/audio-capture-test
//
// Or just: swift tools/audio-capture-test.swift
//
// Start playing music in any app before running.

import Foundation
import ScreenCaptureKit
import CoreMedia
import Accelerate

// MARK: - Configuration

let captureDuration: TimeInterval = 5.0
let sampleRate: Float = 48000
let fftSize = 1024
let binCount = fftSize / 2
let log2n = vDSP_Length(log2(Double(fftSize)))

// MARK: - Global State

var gFFTSetup: FFTSetup!
var gWindow = [Float](repeating: 0, count: 1024)
var gMonoBuffer = [Float](repeating: 0, count: 1024)
var gMonoWritePos = 0
var gMonoFilled = false
var gFrameCount = 0
var gVideoFrameCount = 0

// MARK: - Capture Delegate

class CaptureHandler: NSObject, SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .screen {
            gVideoFrameCount += 1
            if gVideoFrameCount == 1 {
                print("  (video frames arriving — screen capture permission is working)")
            }
            return
        }
        guard type == .audio else { return }

        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        let abuf = audioBufferList.mBuffers
        guard let data = abuf.mData else { return }

        let sampleCount = Int(abuf.mDataByteSize) / MemoryLayout<Float>.size
        guard sampleCount > 0 else { return }

        let floatPtr = data.bindMemory(to: Float.self, capacity: sampleCount)

        // Compute RMS.
        var rms: Float = 0
        for i in 0..<sampleCount {
            rms += floatPtr[i] * floatPtr[i]
        }
        rms = sqrtf(rms / Float(sampleCount))

        // Mix stereo to mono → ring buffer.
        let channels = Int(abuf.mNumberChannels)
        let frames = sampleCount / max(channels, 1)
        for i in 0..<frames {
            var mono: Float = 0
            if channels >= 2 {
                mono = (floatPtr[i * 2] + floatPtr[i * 2 + 1]) * 0.5
            } else {
                mono = floatPtr[i]
            }
            gMonoBuffer[gMonoWritePos] = mono
            gMonoWritePos = (gMonoWritePos + 1) % fftSize
            if gMonoWritePos == 0 { gMonoFilled = true }
        }

        gFrameCount += 1

        // Print RMS bar.
        let rmsDB = rms > 0 ? 20 * log10f(rms) : -120
        let barLen = max(0, Int((rmsDB + 60) * 0.8))
        let bar = String(repeating: "█", count: min(barLen, 48))
        print(String(format: "Frame %4d | RMS: %.4f (%+6.1f dB) |%@", gFrameCount, rms, rmsDB, bar))

        // Run FFT every 4th callback when buffer is full.
        if gMonoFilled && gFrameCount % 4 == 0 {
            runFFT()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("ERROR: Stream stopped: \(error.localizedDescription)")
    }
}

// MARK: - FFT

func runFFT() {
    // Reorder ring buffer: oldest first.
    var ordered = [Float](repeating: 0, count: fftSize)
    for i in 0..<fftSize {
        ordered[i] = gMonoBuffer[(gMonoWritePos + i) % fftSize]
    }

    // Apply Hann window.
    vDSP_vmul(ordered, 1, gWindow, 1, &ordered, 1, vDSP_Length(fftSize))

    // Split complex FFT.
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

                // Dominant frequency.
                var maxMag: Float = 0
                var maxIdx: vDSP_Length = 0
                vDSP_maxvi(magnitudes, 1, &maxMag, &maxIdx, vDSP_Length(binCount))
                let binRes = sampleRate / Float(fftSize)
                let domFreq = Float(maxIdx) * binRes

                // Histogram.
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
print("║  Phosphene Audio Capture Test (Increment 1.3)    ║")
print("║  Capturing \(Int(captureDuration))s of system audio at 48kHz stereo    ║")
print("║  Play music in any app before running this.      ║")
print("╚═══════════════════════════════════════════════════╝")
print("")

let handler = CaptureHandler()
let semaphore = DispatchSemaphore(value: 0)

Task {
    do {
        // Check macOS version.
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        print("macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")

        // On macOS 15+, we can check permission status before attempting capture.
        if #available(macOS 15.0, *) {
            // SCShareableContent.requestAccess is available on macOS 15+
            print("Checking screen capture authorization...")
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            print("ERROR getting shareable content: \(error)")
            print("")
            print("This usually means screen capture permission is not granted.")
            print("Go to: System Settings → Privacy & Security → Screen & System Audio Recording")
            print("Add Terminal (or your terminal app) to the list and enable it.")
            semaphore.signal()
            return
        }

        guard let display = content.displays.first else {
            print("ERROR: No display found")
            semaphore.signal()
            return
        }

        print("Display: \(display.width)×\(display.height)")
        print("Total apps: \(content.applications.count)")
        print("Total windows: \(content.windows.count)")

        let audioApps = content.applications.filter { app in
            let id = app.bundleIdentifier
            return id.contains("Music") || id.contains("Spotify") || id.contains("Tidal")
                || id.contains("YouTube") || id.contains("Chrome") || id.contains("Firefox")
                || id.contains("Safari") || id.contains("VLC")
        }
        if !audioApps.isEmpty {
            print("Detected audio apps: \(audioApps.map { "\($0.applicationName) (\($0.bundleIdentifier))" }.joined(separator: ", "))")
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        // Need reasonable video settings — some macOS versions won't deliver
        // audio callbacks unless video is also flowing.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.sampleRate = 48000
        config.channelCount = 2

        let stream = SCStream(filter: filter, configuration: config, delegate: handler)

        // Add BOTH screen and audio outputs — on some macOS versions,
        // audio callbacks only fire if a screen output handler is also registered.
        try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try stream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        print("")
        print("Starting capture... (you may see a permission prompt)")
        print("")

        try await stream.startCapture()

        print("✓ Capture started. Listening for \(Int(captureDuration)) seconds...")
        print("")

        try await Task.sleep(for: .seconds(captureDuration))
        try await stream.stopCapture()

        print("")
        print("═══════════════════════════════════════════════════")
        print("  Capture complete. \(gFrameCount) audio callbacks, \(gVideoFrameCount) video frames received.")
        if gFrameCount == 0 {
            print("  ⚠ No audio frames received.")
            if gVideoFrameCount > 0 {
                print("  Video frames ARE arriving, so screen capture permission is working.")
                print("  The issue is audio-specific. Possible causes:")
                print("    - No audio is actually playing (is music running?)")
                print("    - On macOS 15+, 'Screen & System Audio Recording' must be enabled")
                print("      (not just 'Screen Recording')")
                print("    - Try toggling the permission off and on in System Settings")
            } else {
                print("  No video frames either — screen capture permission may not be granted.")
                print("    - System Settings → Privacy & Security → Screen & System Audio Recording")
                print("    - Add your terminal app and enable it")
                print("    - You may need to restart the terminal after granting permission")
            }
        } else {
            print("  ✓ Audio pipeline is working.")
        }
        print("═══════════════════════════════════════════════════")
    } catch {
        print("ERROR: \(error)")
    }

    semaphore.signal()
}

semaphore.wait()
vDSP_destroy_fftsetup(gFFTSetup)
