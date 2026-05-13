// FerrofluidBeatSyncTests — End-to-end beat synchronization verification.
//
// Tests the COMPLETE pipeline: synthetic audio → FFT → MIR pipeline →
// FeatureVector → shader render → visual output.
//
// Uses MULTI-INSTRUMENT synthetic audio (kick + bass synth + snare + hi-hat)
// to exercise all frequency bands simultaneously — single-instrument tests
// miss inter-band interaction that real music produces.
//
// This catches problems that static-feature shader tests miss:
//   - AGC producing out-of-range values when multiple instruments overlap
//   - Smoothing so heavy that beats are invisible
//   - Beat detector missing onsets due to spectral masking
//   - Feature values not mapping to visible shader changes
//   - Mid/treble being drowned out by bass energy

import Metal
import MetalKit
import XCTest
@testable import Audio
@testable import DSP
@testable import Presets
@testable import Renderer
@testable import Shared

final class FerrofluidBeatSyncTests: XCTestCase {

    private var device: MTLDevice!

    override func setUpWithError() throws {
        device = MTLCreateSystemDefaultDevice()
        try XCTSkipIf(device == nil, "No Metal device")
    }

    // MARK: - Multi-Instrument Audio Generation

    /// Generate a multi-instrument pattern at the given BPM.
    /// Returns mono float32 at the specified sample rate.
    ///
    /// Instruments (mimics a typical electronic/pop mix):
    ///   - Kick drum: 80 Hz sine burst, every beat (sub-bass band)
    ///   - Bass synth: 100-150 Hz saw-ish tone, every beat (low-bass band)
    ///   - Snare/clap: broadband noise burst, beats 2 & 4 (mid band)
    ///   - Hi-hat: high-pass noise, every 8th note (treble band)
    ///
    /// This exercises all 6 frequency bands simultaneously, which is critical
    /// for testing AGC normalization and inter-band masking.
    private func generateMultiInstrumentPattern(
        bpm: Float, durationSeconds: Float, sampleRate: Float = 48000
    ) -> (audio: [Float], kickTimes: [Float], snareTimes: [Float]) {
        let totalSamples = Int(durationSeconds * sampleRate)
        var audio = [Float](repeating: 0, count: totalSamples)

        let beatInterval = 60.0 / bpm
        let eighthInterval = beatInterval / 2.0

        var kickTimes = [Float]()
        var snareTimes = [Float]()

        // ── Kick drum: 80 Hz sine, 5ms attack / 60ms decay, every beat ──
        var beatTime: Float = 0
        while beatTime < durationSeconds {
            kickTimes.append(beatTime)
            let kickFreq: Float = 80.0
            let attackSamples = Int(0.005 * sampleRate)
            let decaySamples = Int(0.060 * sampleRate)
            let kickLength = attackSamples + decaySamples
            let startSample = Int(beatTime * sampleRate)

            for i in 0 ..< kickLength {
                let idx = startSample + i
                guard idx < totalSamples else { break }
                let envelope: Float
                if i < attackSamples {
                    envelope = Float(i) / Float(attackSamples)
                } else {
                    let decay = Float(i - attackSamples) / Float(decaySamples)
                    envelope = exp(-5.0 * decay)
                }
                let phase = 2.0 * Float.pi * kickFreq * Float(i) / sampleRate
                audio[idx] += sin(phase) * envelope * 0.7
            }
            beatTime += beatInterval
        }

        // ── Bass synth: ~120 Hz with harmonics, every beat, offset 50ms ──
        beatTime = 0.05  // slight offset from kick (realistic)
        while beatTime < durationSeconds {
            let bassFreq: Float = 120.0
            let bassDuration = Int(0.2 * sampleRate)  // 200ms sustain
            let startSample = Int(beatTime * sampleRate)

            for i in 0 ..< bassDuration {
                let idx = startSample + i
                guard idx < totalSamples else { break }
                let decay = Float(i) / Float(bassDuration)
                let envelope = (1.0 - decay) * 0.4  // softer than kick
                let t = Float(i) / sampleRate
                // Fundamental + 2nd + 3rd harmonic (sawtooth-ish)
                let sig = sin(2.0 * Float.pi * bassFreq * t)
                    + 0.5 * sin(2.0 * Float.pi * bassFreq * 2.0 * t)
                    + 0.25 * sin(2.0 * Float.pi * bassFreq * 3.0 * t)
                audio[idx] += sig * envelope
            }
            beatTime += beatInterval
        }

        // ── Snare/clap: broadband noise burst, beats 2 & 4 ──
        beatTime = beatInterval  // start on beat 2
        var beatNum = 1
        while beatTime < durationSeconds {
            if beatNum % 2 == 1 {  // beats 2, 4, 6, 8...
                snareTimes.append(beatTime)
                let snareDuration = Int(0.08 * sampleRate)  // 80ms
                let startSample = Int(beatTime * sampleRate)

                // Seeded pseudo-random for reproducibility
                var noiseState: UInt32 = UInt32(startSample) ^ 0xDEADBEEF
                for i in 0 ..< snareDuration {
                    let idx = startSample + i
                    guard idx < totalSamples else { break }
                    let decay = Float(i) / Float(snareDuration)
                    let envelope = exp(-3.0 * decay) * 0.5

                    // Simple LCG noise (deterministic)
                    noiseState = noiseState &* 1664525 &+ 1013904223
                    let noise = Float(noiseState) / Float(UInt32.max) * 2.0 - 1.0

                    // Band-pass around 1-4 kHz via simple mix of noise + tone
                    let midTone = sin(2.0 * Float.pi * 2000.0
                                      * Float(i) / sampleRate)
                    audio[idx] += (noise * 0.6 + midTone * 0.4) * envelope
                }
            }
            beatNum += 1
            beatTime += beatInterval
        }

        // ── Hi-hat: high-frequency noise burst, every 8th note ──
        var eighthTime: Float = 0
        var hhState: UInt32 = 0x12345678
        while eighthTime < durationSeconds {
            let hhDuration = Int(0.02 * sampleRate)  // 20ms — short
            let startSample = Int(eighthTime * sampleRate)

            for i in 0 ..< hhDuration {
                let idx = startSample + i
                guard idx < totalSamples else { break }
                let decay = Float(i) / Float(hhDuration)
                let envelope = exp(-6.0 * decay) * 0.25

                hhState = hhState &* 1664525 &+ 1013904223
                let noise = Float(hhState) / Float(UInt32.max) * 2.0 - 1.0

                // High-pass character: add 8-12 kHz sine components
                let t = Float(i) / sampleRate
                let hiTone = sin(2.0 * Float.pi * 8000.0 * t)
                    + 0.7 * sin(2.0 * Float.pi * 12000.0 * t)
                audio[idx] += (noise * 0.3 + hiTone * 0.7) * envelope
            }
            eighthTime += eighthInterval
        }

        return (audio, kickTimes, snareTimes)
    }

    /// Generate a simple single-instrument kick pattern for step response tests.
    private func generateKickPattern(
        bpm: Float, durationSeconds: Float, sampleRate: Float = 48000
    ) -> [Float] {
        let totalSamples = Int(durationSeconds * sampleRate)
        var audio = [Float](repeating: 0, count: totalSamples)
        let beatInterval = 60.0 / bpm
        let kickFreq: Float = 80.0
        let attackSamples = Int(0.005 * sampleRate)
        let decaySamples = Int(0.040 * sampleRate)
        let kickLength = attackSamples + decaySamples

        var beatTime: Float = 0
        while beatTime < durationSeconds {
            let startSample = Int(beatTime * sampleRate)
            for i in 0 ..< kickLength {
                let sampleIdx = startSample + i
                guard sampleIdx < totalSamples else { break }
                let envelope: Float
                if i < attackSamples {
                    envelope = Float(i) / Float(attackSamples)
                } else {
                    let decayProgress = Float(i - attackSamples)
                        / Float(decaySamples)
                    envelope = exp(-4.0 * decayProgress)
                }
                let phase = 2.0 * Float.pi * kickFreq
                    * Float(i) / sampleRate
                audio[sampleIdx] += sin(phase) * envelope * 0.8
            }
            beatTime += beatInterval
        }

        return audio
    }

    // MARK: - Pipeline Helpers

    /// Process a single frame through FFT + MIR pipeline.
    private func processFrame(
        audio: [Float], sampleOffset: Int,
        fftProcessor: FFTProcessor, mirPipeline: MIRPipeline,
        fps: Float, time: Float
    ) -> FeatureVector {
        let fftSize = FFTProcessor.fftSize  // 1024
        let hopSize = Int(48000.0 / fps)
        var frameSamples = [Float](repeating: 0, count: fftSize)

        let start = max(0, sampleOffset - fftSize + hopSize)
        let copyCount = min(fftSize, audio.count - start)
        if start >= 0 && start + copyCount <= audio.count {
            for i in 0 ..< copyCount {
                frameSamples[fftSize - copyCount + i] = audio[start + i]
            }
        }

        fftProcessor.process(samples: frameSamples, sampleRate: 48000)

        var magnitudes = [Float](repeating: 0, count: 512)
        for i in 0 ..< 512 {
            magnitudes[i] = fftProcessor.magnitudeBuffer[i]
        }

        return mirPipeline.process(
            magnitudes: magnitudes, fps: fps,
            time: time, deltaTime: 1.0 / fps)
    }

    // MARK: - 1. Multi-Instrument DSP Pipeline Test

    /// Feed a 120 BPM multi-instrument pattern (kick + bass + snare + hi-hat)
    /// through FFT → MIR pipeline.  Verify that ALL frequency bands respond
    /// and that beat detection works despite spectral masking from overlapping
    /// instruments.
    func testMultiInstrumentDSPPipeline() throws {
        let fftProcessor = try FFTProcessor(device: device)
        let mirPipeline = MIRPipeline()

        let bpm: Float = 120
        let fps: Float = 60
        let duration: Float = 8.0
        let (audio, kickTimes, _) = generateMultiInstrumentPattern(
            bpm: bpm, durationSeconds: duration)

        let hopSize = Int(48000.0 / fps)
        let frameCount = Int(duration * fps)

        var bassValues = [Float]()
        var midValues = [Float]()
        var trebleValues = [Float]()
        var beatBassValues = [Float]()
        var beatMidValues = [Float]()
        var beatTrebleValues = [Float]()
        var subBassValues = [Float]()
        var lowBassValues = [Float]()
        var lowMidValues = [Float]()
        var midHighValues = [Float]()
        var highMidValues = [Float]()
        var highValues = [Float]()

        var sampleOffset = 0
        var time: Float = 0

        for _ in 0 ..< frameCount {
            let fv = processFrame(
                audio: audio, sampleOffset: sampleOffset,
                fftProcessor: fftProcessor, mirPipeline: mirPipeline,
                fps: fps, time: time)

            bassValues.append(fv.bass)
            midValues.append(fv.mid)
            trebleValues.append(fv.treble)
            beatBassValues.append(fv.beatBass)
            beatMidValues.append(fv.beatMid)
            beatTrebleValues.append(fv.beatTreble)
            subBassValues.append(fv.subBass)
            lowBassValues.append(fv.lowBass)
            lowMidValues.append(fv.lowMid)
            midHighValues.append(fv.midHigh)
            highMidValues.append(fv.highMid)
            highValues.append(fv.high)

            sampleOffset += hopSize
            time += 1.0 / fps
        }

        // ── Analysis (skip 120 frames AGC warmup) ────────────────────
        let warmup = 120
        let stable = warmup ..< frameCount

        let bassRange = (bassValues[stable].max() ?? 0)
            - (bassValues[stable].min() ?? 0)
        let midRange = (midValues[stable].max() ?? 0)
            - (midValues[stable].min() ?? 0)
        let trebleRange = (trebleValues[stable].max() ?? 0)
            - (trebleValues[stable].min() ?? 0)

        // Count beat onsets (first frame above 0.3 in each burst)
        func countOnsets(_ values: [Float], from: Int) -> Int {
            var count = 0
            for i in from ..< values.count {
                if values[i] > 0.3
                    && (i == from || values[i - 1] <= 0.3)
                {
                    count += 1
                }
            }
            return count
        }

        let bassOnsets = countOnsets(beatBassValues, from: warmup)
        let midOnsets = countOnsets(beatMidValues, from: warmup)
        let trebleOnsets = countOnsets(beatTrebleValues, from: warmup)

        print("\n" + String(repeating: "=", count: 76))
        print("MULTI-INSTRUMENT DSP PIPELINE (120 BPM: kick+bass+snare+hihat)")
        print(String(repeating: "=", count: 76))
        print("  Duration: \(Int(duration))s, \(frameCount) frames, "
              + "\(warmup) warmup skipped")
        print("")
        print("  3-band energy ranges (after warmup):")
        print("    bass:   [\(fmt(bassValues[stable].min())), "
              + "\(fmt(bassValues[stable].max()))]  range=\(fmt(bassRange))")
        print("    mid:    [\(fmt(midValues[stable].min())), "
              + "\(fmt(midValues[stable].max()))]  range=\(fmt(midRange))")
        print("    treble: [\(fmt(trebleValues[stable].min())), "
              + "\(fmt(trebleValues[stable].max()))]  range=\(fmt(trebleRange))")
        print("")
        print("  6-band peak values (after warmup):")
        print("    sub_bass: \(fmt(subBassValues[stable].max()))")
        print("    low_bass: \(fmt(lowBassValues[stable].max()))")
        print("    low_mid:  \(fmt(lowMidValues[stable].max()))")
        print("    mid_high: \(fmt(midHighValues[stable].max()))")
        print("    high_mid: \(fmt(highMidValues[stable].max()))")
        print("    high:     \(fmt(highValues[stable].max()))")
        print("")
        print("  Beat onset count (after warmup):")
        print("    beat_bass:   \(bassOnsets)")
        print("    beat_mid:    \(midOnsets)")
        print("    beat_treble: \(trebleOnsets)")
        print("  Expected: ~\(Int((duration - Float(warmup) / fps) * bpm / 60))"
              + " beats per band (exact count varies by cooldown)")
        print(String(repeating: "=", count: 76) + "\n")

        // ── Assertions ────────────────────────────────────────────────

        // All 3 bands should have meaningful dynamic range (not all zero)
        XCTAssertGreaterThan(bassRange, 0.03,
            "Bass energy range \(bassRange) too small — "
            + "kick drum not registering")
        XCTAssertGreaterThan(midRange, 0.01,
            "Mid energy range \(midRange) too small — "
            + "snare not registering in mid band")
        XCTAssertGreaterThan(trebleRange, 0.003,
            "Treble range \(trebleRange) too small — "
            + "hi-hat not registering in treble band")

        // All 3 bands should produce values in a shader-usable range
        XCTAssertGreaterThan(bassValues[stable].max() ?? 0, 0.1,
            "Bass max too low — AGC suppressing signal")
        XCTAssertLessThan(bassValues[stable].max() ?? 0, 1.5,
            "Bass max exceeds expected range — AGC overflow")
        XCTAssertGreaterThan(midValues[stable].max() ?? 0, 0.05,
            "Mid max too low — snare/clap not producing mid energy")
        XCTAssertGreaterThan(trebleValues[stable].max() ?? 0, 0.005,
            "Treble max too low — hi-hat not reaching treble")

        // Beat detection should fire in at least the bass band
        XCTAssertGreaterThan(bassOnsets, 3,
            "Only \(bassOnsets) bass onsets — "
            + "kick drum beat detection failing")

        // 6-band: at least sub-bass and low-bass should be non-trivial
        XCTAssertGreaterThan(subBassValues[stable].max() ?? 0, 0.01,
            "Sub-bass never exceeded 0.01 — 80 Hz kick not registering")
        XCTAssertGreaterThan(lowBassValues[stable].max() ?? 0, 0.01,
            "Low-bass never exceeded 0.01 — bass synth not registering")
    }

    // MARK: - 2. End-to-End Visual Beat Correlation

    /// Full pipeline → render at low res → measure that frame-to-frame
    /// visual change (MAD) is concentrated at beat onset times.
    /// Uses multi-instrument audio to test realistic inter-band interaction.
    func testVisualBeatCorrelation() throws {
        let fftProcessor = try FFTProcessor(device: device)
        let mirPipeline = MIRPipeline()
        let loader = PresetLoader(
            device: device, pixelFormat: .bgra8Unorm_srgb)
        let preset = try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" })
        // V.9 Session 1 (D-124): Ferrofluid Ocean now declares
        // passes: ["ray_march", "post_process"], so preset.pipelineState is the
        // 3-attachment G-buffer state. PostProcessChain.render expects a
        // single-attachment scene pipeline → output is all-black and the
        // luminance-range assertion below fails by construction. Session 5
        // rewrites this test against the deferred ray-march path
        // (RayMarchPipeline.render) once final lighting lands.
        try XCTSkipIf(preset.descriptor.useRayMarch,
            "Skipped under V.9 redirect: test renders via PostProcessChain, "
            + "incompatible with ray_march preset; rewrite scheduled for Session 5.")
        let context = try MetalContext()
        let shaderLib = try ShaderLibrary(context: context)
        let chain = try PostProcessChain(
            context: context, shaderLibrary: shaderLib)

        let renderW = 256, renderH = 144  // Low res for speed
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

        let bpm: Float = 120
        let fps: Float = 60
        let duration: Float = 6.0
        let (audio, _, _) = generateMultiInstrumentPattern(
            bpm: bpm, durationSeconds: duration)

        let hopSize = Int(48000.0 / fps)
        let frameCount = Int(duration * fps)
        let warmup = 120  // 2s AGC warmup

        var frameLuminances = [Float]()
        var bassValues = [Float]()
        var beatBassValues = [Float]()
        var prevPixels: [UInt16]?
        var frameDiffs = [Float]()

        var sampleOffset = 0
        var time: Float = 0

        for frame in 0 ..< frameCount {
            var fv = processFrame(
                audio: audio, sampleOffset: sampleOffset,
                fftProcessor: fftProcessor, mirPipeline: mirPipeline,
                fps: fps, time: time)
            fv.aspectRatio = Float(renderW) / Float(renderH)

            bassValues.append(fv.bass)
            beatBassValues.append(fv.beatBass)

            // Render every 4th frame after warmup
            if frame >= warmup && frame % 4 == 0 {
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

        // ── Analysis ──────────────────────────────────────────────────
        let lumRange = (frameLuminances.max() ?? 0)
            - (frameLuminances.min() ?? 0)
        let diffMean = frameDiffs.isEmpty ? Float(0) :
            frameDiffs.reduce(0, +) / Float(frameDiffs.count)
        let diffMax = frameDiffs.max() ?? 0

        print("\n" + String(repeating: "=", count: 70))
        print("VISUAL BEAT CORRELATION (120 BPM multi-instrument → render)")
        print(String(repeating: "=", count: 70))
        print("  Rendered \(frameLuminances.count) frames at "
              + "\(renderW)×\(renderH)")
        print("  Frame luminance range: \(fmt(lumRange))")
        print("  Frame-to-frame MAD — mean: \(fmt(diffMean)), "
              + "max: \(fmt(diffMax))")
        let ratio = diffMax / max(diffMean, 0.0001)
        print("  Max/mean ratio: \(fmt(ratio))x "
              + "(>1.5 means beats cause spikes in visual change)")
        print("  Bass range after warmup: "
              + "[\(fmt(bassValues[warmup...].min())), "
              + "\(fmt(bassValues[warmup...].max()))]")
        print(String(repeating: "=", count: 70) + "\n")

        // Luminance should vary with beat pattern
        XCTAssertGreaterThan(lumRange, 10.0,
            "Luminance range \(lumRange) too small — "
            + "visual output not tracking audio")

        // Frame diffs should have spikes larger than average
        if !frameDiffs.isEmpty {
            XCTAssertGreaterThan(ratio, 1.5,
                "Max/mean diff ratio \(ratio) too low — "
                + "visual changes aren't concentrated at beats")
        }
    }

    // MARK: - 3. Smoothing Latency (Step Response)

    /// Measure frames for bass energy to reach 10%/90% of peak after
    /// silence → kick step change.  Directly measures perceived latency.
    func testSmoothingLatency() throws {
        let fftProcessor = try FFTProcessor(device: device)
        let mirPipeline = MIRPipeline()
        let fps: Float = 60

        // Phase 1: 300 frames of silence (AGC warmup)
        let silenceSamples = [Float](repeating: 0, count: 1024)
        for i in 0 ..< 300 {
            fftProcessor.process(samples: silenceSamples, sampleRate: 48000)
            var mags = [Float](repeating: 0, count: 512)
            for j in 0 ..< 512 { mags[j] = fftProcessor.magnitudeBuffer[j] }
            _ = mirPipeline.process(
                magnitudes: mags, fps: fps,
                time: Float(i) / fps, deltaTime: 1.0 / fps)
        }

        // Phase 2: sudden multi-instrument burst — measure response
        let (mixAudio, _, _) = generateMultiInstrumentPattern(
            bpm: 120, durationSeconds: 0.5)
        var bassHistory = [Float]()
        var midHistory = [Float]()
        var trebleHistory = [Float]()
        let transitionFrames = 60

        for frame in 0 ..< transitionFrames {
            let hopSize = Int(48000.0 / fps)
            let start = min(frame * hopSize, mixAudio.count - 1024)
            let end = min(start + 1024, mixAudio.count)
            var frameSamples = [Float](repeating: 0, count: 1024)
            for i in 0 ..< (end - start) {
                frameSamples[i] = mixAudio[start + i]
            }

            fftProcessor.process(
                samples: frameSamples, sampleRate: 48000)
            var mags = [Float](repeating: 0, count: 512)
            for j in 0 ..< 512 { mags[j] = fftProcessor.magnitudeBuffer[j] }

            let fv = mirPipeline.process(
                magnitudes: mags, fps: fps,
                time: Float(300 + frame) / fps,
                deltaTime: 1.0 / fps)
            bassHistory.append(fv.bass)
            midHistory.append(fv.mid)
            trebleHistory.append(fv.treble)
        }

        let peakBass = bassHistory.max() ?? 0
        let peakMid = midHistory.max() ?? 0
        let peakTreble = trebleHistory.max() ?? 0

        let firstBass10 = bassHistory.firstIndex { $0 > peakBass * 0.1 }
        let firstBass90 = bassHistory.firstIndex { $0 > peakBass * 0.9 }
        let firstMid10 = midHistory.firstIndex { $0 > peakMid * 0.1 }

        let lat10Str = firstBass10.map {
            String(format: "%.1f ms", Float($0) / fps * 1000)
        } ?? "never"
        let lat90Str = firstBass90.map {
            String(format: "%.1f ms", Float($0) / fps * 1000)
        } ?? "never"
        let midLat10Str = firstMid10.map {
            String(format: "%.1f ms", Float($0) / fps * 1000)
        } ?? "never"

        print("\n" + String(repeating: "=", count: 70))
        print("SMOOTHING LATENCY (silence → multi-instrument burst)")
        print(String(repeating: "=", count: 70))
        print("  Peak values: bass=\(fmt(peakBass)), mid=\(fmt(peakMid)), "
              + "treble=\(fmt(peakTreble))")
        print("  Bass latency to 10%: \(lat10Str)")
        print("  Bass latency to 90%: \(lat90Str)")
        print("  Mid latency to 10%:  \(midLat10Str)")
        print("  Bass first 10 frames: "
              + "\(bassHistory.prefix(10).map { fmt($0) })")
        print("  Mid first 10 frames:  "
              + "\(midHistory.prefix(10).map { fmt($0) })")
        print(String(repeating: "=", count: 70) + "\n")

        // The kick should produce a non-zero peak
        XCTAssertGreaterThan(peakBass, 0.01,
            "Peak bass \(peakBass) near zero — kick not reaching output")

        // 10% response should happen within 3 frames (50ms)
        if let lat = firstBass10 {
            XCTAssertLessThan(lat, 3,
                "Bass took \(lat) frames to reach 10% — too slow")
        } else {
            XCTFail("Bass never reached 10% of peak")
        }
    }

    // MARK: - 4. Per-Band Independence

    /// Verify that each frequency band responds to its corresponding
    /// instrument and doesn't just mirror bass.  In a realistic mix, the
    /// snare should register in mid, hi-hat in treble, independently of kick.
    func testPerBandIndependence() throws {
        let fftProcessor = try FFTProcessor(device: device)
        let mirPipeline = MIRPipeline()
        let fps: Float = 60
        let duration: Float = 8.0
        let bpm: Float = 120

        let (audio, _, _) = generateMultiInstrumentPattern(
            bpm: bpm, durationSeconds: duration)

        let hopSize = Int(48000.0 / fps)
        let frameCount = Int(duration * fps)
        let warmup = 120

        // Collect per-frame values
        var bassArr = [Float]()
        var midArr = [Float]()
        var trebleArr = [Float]()

        var sampleOffset = 0
        var time: Float = 0

        for _ in 0 ..< frameCount {
            let fv = processFrame(
                audio: audio, sampleOffset: sampleOffset,
                fftProcessor: fftProcessor, mirPipeline: mirPipeline,
                fps: fps, time: time)
            bassArr.append(fv.bass)
            midArr.append(fv.mid)
            trebleArr.append(fv.treble)

            sampleOffset += hopSize
            time += 1.0 / fps
        }

        // Compute correlation coefficients between bands (after warmup)
        let stableBass = Array(bassArr[warmup...])
        let stableMid = Array(midArr[warmup...])
        let stableTreble = Array(trebleArr[warmup...])

        let bassMidCorr = pearsonCorrelation(stableBass, stableMid)
        let bassTrebleCorr = pearsonCorrelation(stableBass, stableTreble)
        let midTrebleCorr = pearsonCorrelation(stableMid, stableTreble)

        print("\n" + String(repeating: "=", count: 70))
        print("PER-BAND INDEPENDENCE (cross-correlation between bands)")
        print(String(repeating: "=", count: 70))
        print("  bass↔mid correlation:    \(fmt(bassMidCorr))")
        print("  bass↔treble correlation: \(fmt(bassTrebleCorr))")
        print("  mid↔treble correlation:  \(fmt(midTrebleCorr))")
        print("  (1.0 = identical, 0.0 = independent, <0.9 = good)")
        print("  If all correlations ≈ 1.0, bands mirror each other")
        print("  and per-spike frequency variation won't work.")
        print(String(repeating: "=", count: 70) + "\n")

        // Bands should NOT be perfectly correlated — they're driven by
        // different instruments.  If correlation is > 0.95, the bands
        // are essentially mirroring each other and per-spike variation
        // in the shader will be invisible.
        XCTAssertLessThan(bassMidCorr, 0.95,
            "Bass and mid are too correlated (\(bassMidCorr)) — "
            + "mid band is just mirroring bass")
        XCTAssertLessThan(bassTrebleCorr, 0.95,
            "Bass and treble too correlated (\(bassTrebleCorr)) — "
            + "treble band just mirroring bass")
    }

    // MARK: - 5. FeatureVector Range Validation

    /// After processing 8s of multi-instrument audio, verify that the
    /// FeatureVector values land in ranges the shader can use.
    /// The shader multiplies bass by 2.0 for spike height, so bass=0.01
    /// → spike height 0.02 → invisible.  This test catches dead-zone values.
    func testFeatureVectorShaderRanges() throws {
        let fftProcessor = try FFTProcessor(device: device)
        let mirPipeline = MIRPipeline()
        let fps: Float = 60
        let duration: Float = 8.0

        let (audio, _, _) = generateMultiInstrumentPattern(
            bpm: 120, durationSeconds: duration)

        let hopSize = Int(48000.0 / fps)
        let frameCount = Int(duration * fps)
        let warmup = 120

        var features = [FeatureVector]()
        var sampleOffset = 0
        var time: Float = 0

        for _ in 0 ..< frameCount {
            let fv = processFrame(
                audio: audio, sampleOffset: sampleOffset,
                fftProcessor: fftProcessor, mirPipeline: mirPipeline,
                fps: fps, time: time)
            features.append(fv)
            sampleOffset += hopSize
            time += 1.0 / fps
        }

        let stable = Array(features[warmup...])

        // Extract ranges for all shader-relevant fields
        struct FieldRange {
            let name: String
            let min: Float
            let max: Float
            let mean: Float
            var range: Float { max - min }
        }

        let fields: [FieldRange] = [
            .init(name: "bass",
                  min: stable.map(\.bass).min()!,
                  max: stable.map(\.bass).max()!,
                  mean: stable.map(\.bass).reduce(0, +) / Float(stable.count)),
            .init(name: "mid",
                  min: stable.map(\.mid).min()!,
                  max: stable.map(\.mid).max()!,
                  mean: stable.map(\.mid).reduce(0, +) / Float(stable.count)),
            .init(name: "treble",
                  min: stable.map(\.treble).min()!,
                  max: stable.map(\.treble).max()!,
                  mean: stable.map(\.treble).reduce(0, +) / Float(stable.count)),
            .init(name: "subBass",
                  min: stable.map(\.subBass).min()!,
                  max: stable.map(\.subBass).max()!,
                  mean: stable.map(\.subBass).reduce(0, +) / Float(stable.count)),
            .init(name: "lowBass",
                  min: stable.map(\.lowBass).min()!,
                  max: stable.map(\.lowBass).max()!,
                  mean: stable.map(\.lowBass).reduce(0, +) / Float(stable.count)),
            .init(name: "beatBass",
                  min: stable.map(\.beatBass).min()!,
                  max: stable.map(\.beatBass).max()!,
                  mean: stable.map(\.beatBass).reduce(0, +) / Float(stable.count)),
            .init(name: "beatMid",
                  min: stable.map(\.beatMid).min()!,
                  max: stable.map(\.beatMid).max()!,
                  mean: stable.map(\.beatMid).reduce(0, +) / Float(stable.count)),
            .init(name: "spectralFlux",
                  min: stable.map(\.spectralFlux).min()!,
                  max: stable.map(\.spectralFlux).max()!,
                  mean: stable.map(\.spectralFlux).reduce(0, +)
                  / Float(stable.count))
        ]

        print("\n" + String(repeating: "=", count: 70))
        print("FEATURE VECTOR SHADER RANGES (multi-instrument, 8s)")
        print(String(repeating: "=", count: 70))
        for f in fields {
            let line = "  \(f.name)".padding(
                toLength: 20, withPad: " ", startingAt: 0)
            print("\(line)  min=\(fmt(f.min))  max=\(fmt(f.max))  "
                  + "mean=\(fmt(f.mean))  range=\(fmt(f.range))")
        }
        print("")
        print("  Shader spike formula: height = 0.2 + bass * 2.0 + beat * 0.5")
        print("  → bass=0.0 → height 0.20 (min visible)")
        print("  → bass=0.5 → height 1.20 (strong)")
        print("  → bass=1.0 → height 2.20 (maximum)")
        print(String(repeating: "=", count: 70) + "\n")

        // Bass should reach at least 0.15 (→ spike height 0.5)
        let bassMax = stable.map(\.bass).max()!
        XCTAssertGreaterThan(bassMax, 0.15,
            "Bass peak \(bassMax) too low for visible spikes "
            + "(need >0.15 → spike height >0.5)")

        // No value should exceed 2.0 (AGC should prevent this)
        for f in fields {
            XCTAssertLessThan(f.max, 2.0,
                "\(f.name) max=\(f.max) exceeds 2.0 — AGC overflow")
        }

        // Bass should have dynamic range > 0.05
        let bassField = fields.first { $0.name == "bass" }!
        XCTAssertGreaterThan(bassField.range, 0.05,
            "Bass dynamic range \(bassField.range) too small — "
            + "spikes will look static")
    }

    // MARK: - Utility

    private func fmt(_ value: Float?) -> String {
        guard let v = value else { return "nil" }
        return String(format: "%.4f", v)
    }

    private func pearsonCorrelation(_ x: [Float], _ y: [Float]) -> Float {
        let n = Float(x.count)
        guard n > 1 else { return 0 }
        let xMean = x.reduce(0, +) / n
        let yMean = y.reduce(0, +) / n
        var num: Float = 0
        var denX: Float = 0
        var denY: Float = 0
        for i in 0 ..< x.count {
            let dx = x[i] - xMean
            let dy = y[i] - yMean
            num += dx * dy
            denX += dx * dx
            denY += dy * dy
        }
        let den = sqrt(denX * denY)
        return den > 0 ? num / den : 0
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
