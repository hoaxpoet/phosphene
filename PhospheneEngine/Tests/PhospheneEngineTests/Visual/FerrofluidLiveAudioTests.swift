// FerrofluidLiveAudioTests — Live streaming audio diagnostic tests.
//
// These tests capture REAL audio from the system (Spotify, Apple Music, etc.)
// and run it through the full DSP → shader pipeline.  They measure actual
// feature values, beat detection accuracy, and visual response with real music.
//
// HOW TO RUN:
//   1. Start playing music in Spotify, Apple Music, or any audio app
//   2. Run: swift test --package-path PhospheneEngine --filter FerrofluidLiveAudio
//   3. Review the diagnostic output — all feature ranges, beat counts, and
//      frame-to-frame visual change are reported
//
// These tests REQUIRE:
//   - Screen capture permission (for Core Audio taps)
//   - Audio actively playing on the system
//   - macOS 14.2+ (for AudioHardwareCreateProcessTap)
//
// Tests that detect no audio automatically skip (not fail).

import AVFoundation
import Metal
import MetalKit
import XCTest
@testable import Audio
@testable import DSP
@testable import Presets
@testable import Renderer
@testable import Shared

@available(macOS 14.2, *)
final class FerrofluidLiveAudioTests: XCTestCase {

    private var device: MTLDevice!

    override func setUpWithError() throws {
        device = MTLCreateSystemDefaultDevice()
        try XCTSkipIf(device == nil, "No Metal device")
    }

    // MARK: - 1. Live DSP Pipeline Diagnostic

    /// Capture 10 seconds of live system audio and process through
    /// FFT → MIR pipeline.  Reports all feature value ranges, beat counts,
    /// and 6-band energy distribution.  Saves raw audio as WAV for replay.
    func testLiveDSPPipeline() throws {
        let capture = SystemAudioCapture()
        let fftProcessor = try FFTProcessor(device: device)
        let mirPipeline = MIRPipeline()
        let fps: Float = 60
        let captureDuration: TimeInterval = 10.0

        // Audio accumulation buffer (thread-safe via lock)
        let lock = NSLock()
        var capturedSamples = [Float]()
        capturedSamples.reserveCapacity(Int(48000 * 2 * captureDuration))

        capture.onAudioBuffer = { samples, sampleCount, _, _ in
            // Copy from real-time thread — minimal work
            let buffer = Array(UnsafeBufferPointer(
                start: samples, count: sampleCount))
            lock.withLock {
                capturedSamples.append(contentsOf: buffer)
            }
        }

        // Start capture
        do {
            try capture.startCapture(mode: .systemAudio)
        } catch {
            throw XCTSkip("Cannot start audio capture: \(error). "
                          + "Grant screen capture permission in System Settings.")
        }

        // Wait for audio
        Thread.sleep(forTimeInterval: captureDuration)
        capture.stopCapture()

        var samples = [Float]()
        lock.withLock { samples = capturedSamples }

        // Check we got audio (not silence)
        let rms = sqrt(samples.map { $0 * $0 }
            .reduce(0, +) / max(Float(samples.count), 1))
        if rms < 0.001 {
            throw XCTSkip("No audio detected (RMS=\(rms)). "
                          + "Play music before running this test.")
        }

        // Save WAV for replay/debugging
        let wavURL = saveAsWAV(
            samples: samples, sampleRate: 48000, channels: 2,
            name: "live_capture")

        // Convert interleaved stereo to mono for FFT
        let monoSamples = stereoToMono(samples)

        // Process through pipeline frame by frame
        let fftSize = FFTProcessor.fftSize
        let hopSize = Int(48000.0 / fps)
        let frameCount = monoSamples.count / hopSize

        var features = [FeatureVector]()
        var sampleOffset = 0
        var time: Float = 0

        for _ in 0 ..< frameCount {
            var frameSamples = [Float](repeating: 0, count: fftSize)
            let start = max(0, sampleOffset)
            let end = min(start + fftSize, monoSamples.count)
            let count = end - start
            if count > 0 {
                for i in 0 ..< count {
                    frameSamples[fftSize - count + i] = monoSamples[start + i]
                }
            }

            fftProcessor.process(samples: frameSamples, sampleRate: 48000)

            var magnitudes = [Float](repeating: 0, count: 512)
            for i in 0 ..< 512 {
                magnitudes[i] = fftProcessor.magnitudeBuffer[i]
            }

            let fv = mirPipeline.process(
                magnitudes: magnitudes, fps: fps,
                time: time, deltaTime: 1.0 / fps)
            features.append(fv)

            sampleOffset += hopSize
            time += 1.0 / fps
        }

        // ── Report ────────────────────────────────────────────────────
        let warmup = min(120, frameCount / 2)  // 2s or half, whichever smaller
        guard frameCount > warmup else {
            throw XCTSkip("Not enough audio captured (\(frameCount) frames)")
        }

        let stable = Array(features[warmup...])

        func stats(_ vals: [Float]) -> (
            min: Float, max: Float, mean: Float, range: Float
        ) {
            let mn = vals.min() ?? 0
            let mx = vals.max() ?? 0
            let avg = vals.reduce(0, +) / max(Float(vals.count), 1)
            return (mn, mx, avg, mx - mn)
        }

        let bassS = stats(stable.map(\.bass))
        let midS = stats(stable.map(\.mid))
        let trebleS = stats(stable.map(\.treble))
        let subBassS = stats(stable.map(\.subBass))
        let lowBassS = stats(stable.map(\.lowBass))
        let lowMidS = stats(stable.map(\.lowMid))
        let midHighS = stats(stable.map(\.midHigh))
        let highMidS = stats(stable.map(\.highMid))
        let highS = stats(stable.map(\.high))
        let beatBassS = stats(stable.map(\.beatBass))
        let beatMidS = stats(stable.map(\.beatMid))
        let beatTrebleS = stats(stable.map(\.beatTreble))
        let fluxS = stats(stable.map(\.spectralFlux))
        let centroidS = stats(stable.map(\.spectralCentroid))

        // Count beat onsets
        func countOnsets(_ values: [Float]) -> Int {
            var count = 0
            for i in 0 ..< values.count {
                if values[i] > 0.3
                    && (i == 0 || values[i - 1] <= 0.3) {
                    count += 1
                }
            }
            return count
        }
        let bassOnsets = countOnsets(stable.map(\.beatBass))
        let midOnsets = countOnsets(stable.map(\.beatMid))
        let trebleOnsets = countOnsets(stable.map(\.beatTreble))

        let sep = String(repeating: "=", count: 78)
        let dash = String(repeating: "-", count: 78)
        print("\n\(sep)")
        print("LIVE AUDIO DSP PIPELINE DIAGNOSTIC")
        print(sep)
        print("  Captured: \(String(format: "%.1f", Float(samples.count) / 96000))s"
              + " stereo 48kHz, RMS=\(String(format: "%.4f", rms))")
        print("  Frames: \(frameCount) total, \(warmup) warmup skipped")
        if let url = wavURL {
            print("  WAV saved: \(url.path)")
        }
        print("")

        print("  3-BAND ENERGY (shader primary drivers):")
        print(dash)
        printStat("  bass", bassS)
        printStat("  mid", midS)
        printStat("  treble", trebleS)
        print("")

        print("  6-BAND ENERGY (per-spike variation):")
        print(dash)
        printStat("  sub_bass", subBassS)
        printStat("  low_bass", lowBassS)
        printStat("  low_mid", lowMidS)
        printStat("  mid_high", midHighS)
        printStat("  high_mid", highMidS)
        printStat("  high", highS)
        print("")

        print("  BEAT DETECTION (onset counts in "
              + "\(String(format: "%.1f", Float(stable.count) / fps))s):")
        print(dash)
        print("    beat_bass:   \(bassOnsets) onsets")
        print("    beat_mid:    \(midOnsets) onsets")
        print("    beat_treble: \(trebleOnsets) onsets")
        printStat("  beat_bass values", beatBassS)
        printStat("  beat_mid values", beatMidS)
        printStat("  beat_treble values", beatTrebleS)
        print("")

        print("  SPECTRAL FEATURES:")
        print(dash)
        printStat("  spectralFlux", fluxS)
        printStat("  spectralCentroid", centroidS)
        print("")

        // ── Shader spike height predictions ──────────────────────────
        let spikeCenter = 0.2 + bassS.max * 2.0 + beatBassS.max * 0.5
        let spikeR1 = 0.08 + midS.max * 2.0 + beatMidS.max * 0.3
        let spikeR2 = 0.05 + trebleS.max * 1.4 + beatTrebleS.max * 0.15

        print("  PREDICTED SPIKE HEIGHTS (from shader formula):")
        print(dash)
        print("    Center spike max: \(fmt(spikeCenter)) "
              + "(bass=\(fmt(bassS.max)) × 2.0 + beat=\(fmt(beatBassS.max))"
              + " × 0.5)")
        print("    Ring 1 spike max: \(fmt(spikeR1)) "
              + "(mid=\(fmt(midS.max)) × 2.0 + beat=\(fmt(beatMidS.max))"
              + " × 0.3)")
        print("    Ring 2 spike max: \(fmt(spikeR2)) "
              + "(treble=\(fmt(trebleS.max)) × 1.4 + beat=\(fmt(beatTrebleS.max))"
              + " × 0.15)")
        print("    Minimum visible spike height: ~0.3")
        print("    Good response: center>1.0, ring1>0.5, ring2>0.3")
        print(sep + "\n")

        // ── Assertions ────────────────────────────────────────────────
        // These are soft assertions — they warn about problems but don't
        // fail the test because real music varies enormously by genre.

        // Audio should have been captured
        XCTAssertGreaterThan(frameCount, 120,
            "Too few frames captured (\(frameCount))")

        // Bass should have meaningful range
        XCTAssertGreaterThan(bassS.range, 0.01,
            "Bass range \(bassS.range) too small — audio may be too quiet")

        // At least one band should detect beats
        let totalOnsets = bassOnsets + midOnsets + trebleOnsets
        XCTAssertGreaterThan(totalOnsets, 0,
            "No beat onsets detected — track may be ambient/droning")
    }

    // MARK: - 2. Live Visual Rendering Diagnostic

    /// Capture live audio, render each frame through the ferrofluid shader,
    /// and measure visual responsiveness (frame-to-frame MAD, luminance range).
    func testLiveVisualResponse() throws {
        let capture = SystemAudioCapture()
        let fftProcessor = try FFTProcessor(device: device)
        let mirPipeline = MIRPipeline()
        let loader = PresetLoader(
            device: device, pixelFormat: .bgra8Unorm_srgb)
        let preset = try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" })
        let context = try MetalContext()
        let shaderLib = try ShaderLibrary(context: context)
        let chain = try PostProcessChain(
            context: context, shaderLibrary: shaderLib)

        let renderW = 320, renderH = 180
        chain.allocateTextures(width: renderW, height: renderH)

        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: renderW, height: renderH,
            mipmapped: false)
        outputDesc.usage = [.renderTarget, .shaderRead]
        outputDesc.storageMode = .shared
        let outputTexture = try XCTUnwrap(
            device.makeTexture(descriptor: outputDesc))
        let fftBuf = try XCTUnwrap(device.makeBuffer(
            length: 512 * MemoryLayout<Float>.size,
            options: .storageModeShared))
        let wavBuf = try XCTUnwrap(device.makeBuffer(
            length: 2048 * MemoryLayout<Float>.size,
            options: .storageModeShared))

        let fps: Float = 60
        let captureDuration: TimeInterval = 8.0

        // Capture audio
        let lock = NSLock()
        var capturedSamples = [Float]()
        capturedSamples.reserveCapacity(Int(48000 * 2 * captureDuration))

        capture.onAudioBuffer = { samples, sampleCount, _, _ in
            let buffer = Array(UnsafeBufferPointer(
                start: samples, count: sampleCount))
            lock.withLock { capturedSamples.append(contentsOf: buffer) }
        }

        do {
            try capture.startCapture(mode: .systemAudio)
        } catch {
            throw XCTSkip("Cannot start audio capture: \(error)")
        }

        Thread.sleep(forTimeInterval: captureDuration)
        capture.stopCapture()

        var samples = [Float]()
        lock.withLock { samples = capturedSamples }

        let rms = sqrt(samples.map { $0 * $0 }
            .reduce(0, +) / max(Float(samples.count), 1))
        if rms < 0.001 {
            throw XCTSkip("No audio detected (RMS=\(rms)). Play music first.")
        }

        let monoSamples = stereoToMono(samples)

        // Process and render
        let fftSize = FFTProcessor.fftSize
        let hopSize = Int(48000.0 / fps)
        let frameCount = min(monoSamples.count / hopSize, Int(captureDuration * Double(fps)))
        let warmup = min(120, frameCount / 2)

        var frameLuminances = [Float]()
        var frameDiffs = [Float]()
        var prevPixels: [UInt16]?
        var renderTimes = [Double]()

        var sampleOffset = 0
        var time: Float = 0

        for frame in 0 ..< frameCount {
            // FFT + MIR
            var frameSamples = [Float](repeating: 0, count: fftSize)
            let start = max(0, sampleOffset)
            let end = min(start + fftSize, monoSamples.count)
            let count = end - start
            if count > 0 {
                for i in 0 ..< count {
                    frameSamples[fftSize - count + i] = monoSamples[start + i]
                }
            }

            fftProcessor.process(samples: frameSamples, sampleRate: 48000)
            var magnitudes = [Float](repeating: 0, count: 512)
            for i in 0 ..< 512 {
                magnitudes[i] = fftProcessor.magnitudeBuffer[i]
            }

            var fv = mirPipeline.process(
                magnitudes: magnitudes, fps: fps,
                time: time, deltaTime: 1.0 / fps)
            fv.aspectRatio = Float(renderW) / Float(renderH)

            // Render every 4th frame after warmup
            if frame >= warmup && frame % 4 == 0 {
                let renderStart = CFAbsoluteTimeGetCurrent()
                guard let cmd = context.commandQueue.makeCommandBuffer()
                else { continue }
                let stems = StemFeatures()
                chain.render(
                    scenePipelineState: preset.pipelineState,
                    features: &fv, fftBuffer: fftBuf,
                    waveformBuffer: wavBuf, stemFeatures: stems,
                    outputTexture: outputTexture, commandBuffer: cmd)
                cmd.commit()
                cmd.waitUntilCompleted()
                renderTimes.append(CFAbsoluteTimeGetCurrent() - renderStart)

                if let scene = chain.sceneTexture {
                    let w = scene.width, h = scene.height
                    var raw16 = [UInt16](repeating: 0, count: w * h * 4)
                    scene.getBytes(
                        &raw16,
                        bytesPerRow: w * 4 * MemoryLayout<UInt16>.size,
                        from: MTLRegionMake2D(0, 0, w, h),
                        mipmapLevel: 0)

                    var totalLum: Float = 0
                    for i in 0 ..< (w * h) {
                        let idx = i * 4
                        let r = halfToFloat(raw16[idx])
                        let g = halfToFloat(raw16[idx + 1])
                        let b = halfToFloat(raw16[idx + 2])
                        totalLum += 0.2126 * r + 0.7152 * g + 0.0722 * b
                    }
                    frameLuminances.append(totalLum)

                    if let prev = prevPixels {
                        var diff: Float = 0
                        for i in 0 ..< (w * h) {
                            let idx = i * 4
                            diff += abs(halfToFloat(raw16[idx])
                                        - halfToFloat(prev[idx]))
                            diff += abs(halfToFloat(raw16[idx + 1])
                                        - halfToFloat(prev[idx + 1]))
                            diff += abs(halfToFloat(raw16[idx + 2])
                                        - halfToFloat(prev[idx + 2]))
                        }
                        frameDiffs.append(diff / Float(w * h))
                    }
                    prevPixels = raw16
                }
            }

            sampleOffset += hopSize
            time += 1.0 / fps
        }

        // ── Report ────────────────────────────────────────────────────
        let lumMin = frameLuminances.min() ?? 0
        let lumMax = frameLuminances.max() ?? 0
        let lumRange = lumMax - lumMin
        let diffMean = frameDiffs.isEmpty ? Float(0) :
            frameDiffs.reduce(0, +) / Float(frameDiffs.count)
        let diffMax = frameDiffs.max() ?? 0
        let ratio = diffMax / max(diffMean, 0.0001)

        let avgRenderMs = renderTimes.isEmpty ? 0 :
            (renderTimes.reduce(0, +) / Double(renderTimes.count)) * 1000
        let maxRenderMs = (renderTimes.max() ?? 0) * 1000

        let sep = String(repeating: "=", count: 70)
        print("\n\(sep)")
        print("LIVE VISUAL RESPONSE DIAGNOSTIC")
        print(sep)
        print("  Audio: \(String(format: "%.1f", Float(samples.count) / 96000))s"
              + " stereo, RMS=\(fmt(rms))")
        print("  Rendered \(frameLuminances.count) frames at "
              + "\(renderW)×\(renderH)")
        print("")
        print("  VISUAL DYNAMICS:")
        print("    Luminance range: \(fmt(lumRange))")
        print("    Frame-to-frame MAD — mean: \(fmt(diffMean)), "
              + "max: \(fmt(diffMax))")
        print("    Max/mean ratio: \(fmt(ratio))x "
              + "(>1.5 = beats cause visual spikes)")
        print("")
        print("  RENDER PERFORMANCE:")
        print("    Avg: \(String(format: "%.2f", avgRenderMs)) ms")
        print("    Max: \(String(format: "%.2f", maxRenderMs)) ms")
        print("    Budget: 16.67 ms (60fps)")
        print("")

        // Classify the result
        if lumRange < 5.0 {
            print("  VERDICT: POOR — visual output barely changes with audio")
        } else if ratio < 1.5 {
            print("  VERDICT: FLAT — visual changes don't concentrate at beats")
        } else if lumRange > 100 && ratio > 2.0 {
            print("  VERDICT: GOOD — strong dynamic response with beat sync")
        } else {
            print("  VERDICT: MODERATE — some audio response, may need tuning")
        }
        print(sep + "\n")

        // Assertions
        XCTAssertGreaterThan(frameLuminances.count, 10,
            "Too few rendered frames")
        XCTAssertGreaterThan(lumRange, 1.0,
            "Visual output barely changes — shader not responding to audio")
    }

    // MARK: - 3. Live Audio Capture → WAV Fixture

    /// Captures 10s of live audio and saves it as a reusable WAV test fixture.
    /// Run this once per genre to build a library of real audio test clips.
    func testCaptureAudioFixture() throws {
        let capture = SystemAudioCapture()
        let captureDuration: TimeInterval = 10.0

        let lock = NSLock()
        var capturedSamples = [Float]()
        capturedSamples.reserveCapacity(Int(48000 * 2 * captureDuration))

        capture.onAudioBuffer = { samples, sampleCount, _, _ in
            let buffer = Array(UnsafeBufferPointer(
                start: samples, count: sampleCount))
            lock.withLock { capturedSamples.append(contentsOf: buffer) }
        }

        do {
            try capture.startCapture(mode: .systemAudio)
        } catch {
            throw XCTSkip("Cannot start capture: \(error)")
        }

        Thread.sleep(forTimeInterval: captureDuration)
        capture.stopCapture()

        var samples = [Float]()
        lock.withLock { samples = capturedSamples }

        let rms = sqrt(samples.map { $0 * $0 }
            .reduce(0, +) / max(Float(samples.count), 1))
        if rms < 0.001 {
            throw XCTSkip("No audio detected. Play music first.")
        }

        let url = saveAsWAV(
            samples: samples, sampleRate: 48000, channels: 2,
            name: "fixture_\(dateStamp())")

        print("\n" + String(repeating: "=", count: 70))
        print("AUDIO FIXTURE CAPTURED")
        print(String(repeating: "=", count: 70))
        print("  Duration: \(String(format: "%.1f", Float(samples.count) / 96000))s")
        print("  RMS: \(String(format: "%.4f", rms))")
        if let url = url {
            print("  Saved to: \(url.path)")
            print("")
            print("  To replay in tests, copy this file to the test fixtures")
            print("  directory and load with AVAudioFile.")
        }
        print(String(repeating: "=", count: 70) + "\n")
    }

    // MARK: - Audio Utilities

    private func stereoToMono(_ interleaved: [Float]) -> [Float] {
        let frameCount = interleaved.count / 2
        var mono = [Float](repeating: 0, count: frameCount)
        for i in 0 ..< frameCount {
            mono[i] = (interleaved[i * 2] + interleaved[i * 2 + 1]) * 0.5
        }
        return mono
    }

    @discardableResult
    private func saveAsWAV(
        samples: [Float], sampleRate: Float, channels: Int, name: String
    ) -> URL? {
        let outDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PhospheneLiveAudio")
        try? FileManager.default.createDirectory(
            at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("\(name).wav")

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels),
            interleaved: true)

        guard let format = format,
              let file = try? AVAudioFile(
                forWriting: url, settings: format.settings)
        else { return nil }

        let frameCount = samples.count / channels
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount))
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        if let channelData = buffer.floatChannelData {
            // For interleaved format, channel 0 has all data
            samples.withUnsafeBufferPointer { src in
                channelData[0].update(from: src.baseAddress!, count: samples.count)
            }
        }

        try? file.write(from: buffer)
        return url
    }

    private func dateStamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        return df.string(from: Date())
    }

    private func fmt(_ value: Float?) -> String {
        guard let v = value else { return "nil" }
        return String(format: "%.4f", v)
    }

    private func printStat(
        _ label: String,
        _ s: (min: Float, max: Float, mean: Float, range: Float)
    ) {
        let padded = label.padding(toLength: 22, withPad: " ", startingAt: 0)
        print("\(padded)  min=\(fmt(s.min))  max=\(fmt(s.max))  "
              + "mean=\(fmt(s.mean))  range=\(fmt(s.range))")
    }

    private func halfToFloat(_ half: UInt16) -> Float {
        let sign     = (half >> 15) & 0x1
        let exponent = (half >> 10) & 0x1F
        let mantissa = half & 0x3FF
        let signF: Float = sign == 1 ? -1.0 : 1.0
        if exponent == 0 {
            return signF * Float(mantissa) / 1024.0 * pow(2.0, -14.0)
        } else if exponent == 31 {
            return mantissa == 0 ? (signF * .infinity) : .nan
        }
        return signF * (1.0 + Float(mantissa) / 1024.0)
            * pow(2.0, Float(exponent) - 15.0)
    }
}
