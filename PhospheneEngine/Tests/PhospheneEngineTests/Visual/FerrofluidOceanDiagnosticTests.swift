// FerrofluidOceanDiagnosticTests — Comprehensive diagnostic testing for the
// Ferrofluid Ocean preset.  Tests actual audio→visual response, not just
// "does it compile and render."
//
// Five diagnostic categories:
//   1. Audio Proportionality: Do spike heights track bass/mid/treble values?
//   2. Beat Response: Does the visual output change on beat onset frames?
//   3. Per-Spike Variation: Do different 6-band values produce different heights?
//   4. Background Visibility: Is the background visible (not jet black)?
//   5. Performance: Can the shader hit 60fps at 1080p?

import Metal
import MetalKit
import XCTest
@testable import Presets
@testable import Renderer
@testable import Shared

final class FerrofluidOceanDiagnosticTests: XCTestCase {

    private var device: MTLDevice!
    private var loader: PresetLoader!
    private var context: MetalContext!
    private var shaderLib: ShaderLibrary!

    override func setUpWithError() throws {
        device = MTLCreateSystemDefaultDevice()
        try XCTSkipIf(device == nil, "No Metal device")
        loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
        context = try MetalContext()
        shaderLib = try ShaderLibrary(context: context)
    }

    // MARK: - Render Helper

    /// Renders the ferrofluid preset at the given size with specific audio features.
    /// Returns the rgba16Float scene texture (pre-tonemapped HDR) for analysis.
    private func renderScene(
        width: Int, height: Int,
        features: FeatureVector,
        stems: StemFeatures = StemFeatures()
    ) throws -> MTLTexture {
        let preset = try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" })
        let chain = try PostProcessChain(context: context, shaderLibrary: shaderLib)
        chain.allocateTextures(width: width, height: height)

        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: width, height: height,
            mipmapped: false)
        outputDesc.usage = [.renderTarget, .shaderRead]
        outputDesc.storageMode = .shared
        let outputTexture = try XCTUnwrap(device.makeTexture(descriptor: outputDesc))

        let fftBuf = try XCTUnwrap(device.makeBuffer(
            length: 512 * MemoryLayout<Float>.size, options: .storageModeShared))
        let wavBuf = try XCTUnwrap(device.makeBuffer(
            length: 2048 * MemoryLayout<Float>.size, options: .storageModeShared))

        var feat = features
        let cmdBuf = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
        chain.render(
            scenePipelineState: preset.pipelineState,
            features: &feat, fftBuffer: fftBuf, waveformBuffer: wavBuf,
            stemFeatures: stems, outputTexture: outputTexture,
            commandBuffer: cmdBuf)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        return try XCTUnwrap(chain.sceneTexture)
    }

    // MARK: - Pixel Analysis Helpers

    /// Compute the vertical extent of non-background pixels (spike region).
    /// Returns (topRow, bottomRow, spikePixelCount) in the scene texture.
    /// Background is defined as luminance < threshold.
    private func measureSpikeExtent(
        texture: MTLTexture, bgThreshold: Float = 0.05
    ) -> (topRow: Int, bottomRow: Int, spikePixelCount: Int) {
        let w = texture.width
        let h = texture.height
        let raw16 = readHalfPixels(texture)

        var topRow = h
        var bottomRow = 0
        var spikeCount = 0

        for row in 0 ..< h {
            for col in 0 ..< w {
                let idx = (row * w + col) * 4
                let r = halfToFloat(raw16[idx])
                let g = halfToFloat(raw16[idx + 1])
                let b = halfToFloat(raw16[idx + 2])
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                if lum > bgThreshold {
                    topRow = min(topRow, row)
                    bottomRow = max(bottomRow, row)
                    spikeCount += 1
                }
            }
        }
        return (topRow, bottomRow, spikeCount)
    }

    /// Compute mean luminance in a region of the texture.
    private func meanLuminance(
        texture: MTLTexture,
        rowRange: ClosedRange<Int>,
        colRange: ClosedRange<Int>
    ) -> Float {
        let w = texture.width
        let raw16 = readHalfPixels(texture)
        var sum: Double = 0
        var count = 0

        for row in rowRange {
            for col in colRange {
                let idx = (row * w + col) * 4
                let r = halfToFloat(raw16[idx])
                let g = halfToFloat(raw16[idx + 1])
                let b = halfToFloat(raw16[idx + 2])
                sum += Double(0.2126 * r + 0.7152 * g + 0.0722 * b)
                count += 1
            }
        }
        return count > 0 ? Float(sum / Double(count)) : 0
    }

    /// Count pixels above a luminance threshold in the full texture.
    private func countBrightPixels(
        texture: MTLTexture, threshold: Float
    ) -> Int {
        let w = texture.width
        let h = texture.height
        let raw16 = readHalfPixels(texture)
        var count = 0
        for row in 0 ..< h {
            for col in 0 ..< w {
                let idx = (row * w + col) * 4
                let r = halfToFloat(raw16[idx])
                let g = halfToFloat(raw16[idx + 1])
                let b = halfToFloat(raw16[idx + 2])
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                if lum > threshold { count += 1 }
            }
        }
        return count
    }

    /// Compute mean absolute pixel-wise difference between two textures.
    /// This directly measures "how much does the visual change."
    private func meanAbsDifference(
        textureA: MTLTexture, textureB: MTLTexture
    ) -> Float {
        let w = textureA.width
        let h = textureA.height
        let rawA = readHalfPixels(textureA)
        let rawB = readHalfPixels(textureB)
        var totalDiff: Double = 0
        let pixelCount = w * h
        for i in 0 ..< pixelCount {
            let idx = i * 4
            let rA = halfToFloat(rawA[idx])
            let gA = halfToFloat(rawA[idx + 1])
            let bA = halfToFloat(rawA[idx + 2])
            let rB = halfToFloat(rawB[idx])
            let gB = halfToFloat(rawB[idx + 1])
            let bB = halfToFloat(rawB[idx + 2])
            totalDiff += Double(abs(rA - rB) + abs(gA - gB) + abs(bA - bB))
        }
        return Float(totalDiff / Double(pixelCount))
    }

    /// Compute total luminance sum of the full texture.
    private func totalLuminance(texture: MTLTexture) -> Float {
        let w = texture.width
        let h = texture.height
        let raw16 = readHalfPixels(texture)
        var total: Double = 0
        for i in 0 ..< (w * h) {
            let idx = i * 4
            let r = halfToFloat(raw16[idx])
            let g = halfToFloat(raw16[idx + 1])
            let b = halfToFloat(raw16[idx + 2])
            total += Double(0.2126 * r + 0.7152 * g + 0.0722 * b)
        }
        return Float(total)
    }

    private func readHalfPixels(_ texture: MTLTexture) -> [UInt16] {
        let w = texture.width
        let h = texture.height
        var raw16 = [UInt16](repeating: 0, count: w * h * 4)
        texture.getBytes(
            &raw16, bytesPerRow: w * 4 * MemoryLayout<UInt16>.size,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return raw16
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
        } else {
            return signF * (1.0 + Float(mantissa) / 1024.0)
                * pow(2.0, Float(exponent) - 15.0)
        }
    }

    // MARK: - Feature Helpers

    private func makeFeatures(
        time: Float = 10.0, bass: Float = 0, mid: Float = 0,
        treble: Float = 0, beatBass: Float = 0,
        subBass: Float = 0, lowBass: Float = 0, lowMid: Float = 0,
        midHigh: Float = 0, highMid: Float = 0, highFreq: Float = 0,
        flux: Float = 0, aspect: Float = 1.778
    ) -> FeatureVector {
        FeatureVector(
            bass: bass, mid: mid, treble: treble,
            bassAtt: bass * 0.7, midAtt: mid * 0.7, trebleAtt: treble * 0.7,
            subBass: subBass > 0 ? subBass : bass * 0.8,
            lowBass: lowBass > 0 ? lowBass : bass * 0.6,
            lowMid: lowMid > 0 ? lowMid : mid * 0.5,
            midHigh: midHigh > 0 ? midHigh : mid * 0.3,
            highMid: highMid > 0 ? highMid : treble * 0.5,
            high: highFreq > 0 ? highFreq : treble * 0.3,
            beatBass: beatBass, beatMid: 0, beatTreble: 0,
            beatComposite: beatBass * 0.5,
            spectralCentroid: 0.4, spectralFlux: flux,
            valence: 0, arousal: bass,
            time: time, deltaTime: 1.0 / 60.0,
            aspectRatio: aspect)
    }

    // MARK: - 1. Audio Proportionality Tests
    //
    // Uses mean absolute pixel difference (MAD) and total luminance to measure
    // visual response.  MAD directly measures "how much does the image change
    // when the audio changes."  Threshold-based pixel counting is unreliable
    // because taller dark spikes replace bright background pixels.

    /// Bass=0 vs bass=0.8: visual output should change substantially.
    func testBassProportionality() throws {
        let size = 512

        let texSilent = try renderScene(
            width: size, height: size,
            features: makeFeatures(bass: 0, mid: 0, treble: 0))
        let texBass = try renderScene(
            width: size, height: size,
            features: makeFeatures(bass: 0.8, mid: 0, treble: 0))

        let mad = meanAbsDifference(textureA: texSilent, textureB: texBass)
        let lumSilent = totalLuminance(texture: texSilent)
        let lumBass = totalLuminance(texture: texBass)

        print("\n=== BASS PROPORTIONALITY ===")
        print("  Silent → bass=0.8 MAD: \(String(format: "%.4f", mad))")
        print("  Luminance sum — silent: \(String(format: "%.1f", lumSilent))"
              + ", bass=0.8: \(String(format: "%.1f", lumBass))")
        print("  Luminance ratio: "
              + "\(String(format: "%.2f", lumBass / max(lumSilent, 0.001)))x")
        print("  MAD > 0.01 → visible change")
        print("============================\n")

        XCTAssertGreaterThan(mad, 0.01,
            "Bass=0→0.8 should produce visible change (MAD=\(mad))")
        // Note: with a bright background, taller dark spikes may REDUCE total
        // luminance.  The MAD test above is the correct measure of visual change.
        XCTAssertNotEqual(lumBass, lumSilent, accuracy: 1.0,
            "Bass=0.8 should change total luminance vs silence")
    }

    /// Mid=0 vs mid=0.8: ring 1 spikes should change the image.
    func testMidProportionality() throws {
        let size = 512

        let texLow = try renderScene(
            width: size, height: size,
            features: makeFeatures(bass: 0.3, mid: 0, treble: 0))
        let texHigh = try renderScene(
            width: size, height: size,
            features: makeFeatures(bass: 0.3, mid: 0.8, treble: 0))

        let mad = meanAbsDifference(textureA: texLow, textureB: texHigh)
        let lumLow = totalLuminance(texture: texLow)
        let lumHigh = totalLuminance(texture: texHigh)

        print("\n=== MID PROPORTIONALITY ===")
        print("  Mid 0→0.8 MAD: \(String(format: "%.4f", mad))")
        print("  Luminance sum — mid=0: \(String(format: "%.1f", lumLow))"
              + ", mid=0.8: \(String(format: "%.1f", lumHigh))")
        print("  MAD > 0.005 → visible change")
        print("===========================\n")

        XCTAssertGreaterThan(mad, 0.005,
            "Mid=0→0.8 should produce visible change (MAD=\(mad))")
    }

    // MARK: - 2. Beat Response Tests

    /// Beat=0 vs beat=0.9: should produce a measurable visual difference
    /// (glow emission + height spike + background flash).
    func testBeatResponse() throws {
        let size = 512

        let texNoBeat = try renderScene(
            width: size, height: size,
            features: makeFeatures(bass: 0.5, mid: 0.4, treble: 0.3))
        let texBeat = try renderScene(
            width: size, height: size,
            features: makeFeatures(
                bass: 0.5, mid: 0.4, treble: 0.3, beatBass: 0.9))

        let mad = meanAbsDifference(textureA: texNoBeat, textureB: texBeat)
        let lumNoBeat = totalLuminance(texture: texNoBeat)
        let lumBeat = totalLuminance(texture: texBeat)

        print("\n=== BEAT RESPONSE ===")
        print("  Beat 0→0.9 MAD: \(String(format: "%.4f", mad))")
        print("  Luminance sum — no beat: \(String(format: "%.1f", lumNoBeat))"
              + ", beat=0.9: \(String(format: "%.1f", lumBeat))")
        print("  Luminance ratio: "
              + "\(String(format: "%.2f", lumBeat / max(lumNoBeat, 0.001)))x")
        print("  MAD > 0.005 → visible beat response")
        print("=====================\n")

        XCTAssertGreaterThan(mad, 0.005,
            "Beat=0→0.9 should produce visible change (MAD=\(mad))")
        XCTAssertGreaterThan(lumBeat, lumNoBeat,
            "Beat should increase total luminance (glow + background flash)")
    }

    // MARK: - 3. Per-Spike Frequency Variation

    /// Varied 6-band values vs uniform: the pixel-wise difference should be
    /// non-trivial, proving each ring 1 spike responds to its own band.
    func testPerSpikeVariation() throws {
        let size = 512

        // Strongly varied: sub_bass/low_bass high, rest low
        let texVaried = try renderScene(
            width: size, height: size,
            features: makeFeatures(
                bass: 0.5, mid: 0.5, treble: 0.3,
                subBass: 0.9, lowBass: 0.8, lowMid: 0.2,
                midHigh: 0.1, highMid: 0.15, highFreq: 0.1))

        // All bands uniform
        let texUniform = try renderScene(
            width: size, height: size,
            features: makeFeatures(
                bass: 0.5, mid: 0.5, treble: 0.3,
                subBass: 0.5, lowBass: 0.5, lowMid: 0.5,
                midHigh: 0.5, highMid: 0.5, highFreq: 0.5))

        let mad = meanAbsDifference(textureA: texVaried, textureB: texUniform)

        print("\n=== PER-SPIKE VARIATION ===")
        print("  Varied vs uniform MAD: \(String(format: "%.4f", mad))")
        print("  MAD > 0.002 → visually distinguishable spike heights")
        print("===========================\n")

        XCTAssertGreaterThan(mad, 0.002,
            "Varied vs uniform 6-band values should produce visible "
            + "difference (MAD=\(mad))")
    }

    // MARK: - 4. Background Visibility

    /// The background should NOT be jet black.  Measure luminance in the top
    /// 20% of the frame (above all spikes — pure background).
    func testBackgroundVisibility() throws {
        let size = 512

        // Moderate audio — representative listening state
        let tex = try renderScene(
            width: size, height: size,
            features: makeFeatures(bass: 0.5, mid: 0.4, treble: 0.3))

        let topRegion = 0...Int(Float(size) * 0.15)
        let fullWidth = 0...(size - 1)
        let bgLum = meanLuminance(
            texture: tex, rowRange: topRegion, colRange: fullWidth)

        // Also measure with high bass (should brighten background)
        let texLoud = try renderScene(
            width: size, height: size,
            features: makeFeatures(bass: 0.8, mid: 0.6, treble: 0.5))
        let bgLumLoud = meanLuminance(
            texture: texLoud, rowRange: topRegion, colRange: fullWidth)

        // And with beat (should flash the background)
        let texBeat = try renderScene(
            width: size, height: size,
            features: makeFeatures(
                bass: 0.5, mid: 0.4, treble: 0.3, beatBass: 0.9))
        let bgLumBeat = meanLuminance(
            texture: texBeat, rowRange: topRegion, colRange: fullWidth)

        print("\n=== BACKGROUND VISIBILITY ===")
        print("  Moderate audio: bg mean luminance = "
              + "\(String(format: "%.4f", bgLum))")
        print("  Loud audio (bass=0.8): bg mean luminance = "
              + "\(String(format: "%.4f", bgLumLoud))")
        print("  Beat flash (beat=0.9): bg mean luminance = "
              + "\(String(format: "%.4f", bgLumBeat))")
        print("  Loud/moderate ratio: "
              + "\(String(format: "%.2f", bgLumLoud / max(bgLum, 0.0001)))x")
        print("  Beat/moderate ratio: "
              + "\(String(format: "%.2f", bgLumBeat / max(bgLum, 0.0001)))x")
        print("")
        print("  Thresholds:")
        print("    bgLum > 0.005 → background is not jet black")
        print("    loud > moderate → background responds to bass")
        print("    beat > moderate → background responds to beats")
        print("=============================\n")

        XCTAssertGreaterThan(
            bgLum, 0.005,
            "Background mean luminance should be > 0.005 "
            + "(got \(bgLum) — background is too dark)")
        XCTAssertGreaterThan(
            bgLumLoud, bgLum,
            "Background should brighten with louder bass")
        XCTAssertGreaterThan(
            bgLumBeat, bgLum,
            "Background should flash brighter on beat onset")
    }

    // MARK: - 5. Performance

    /// Worst-case 1080p frame time must be under 16.67ms (60fps).
    func testRenderPerformance1080p() throws {
        let preset = try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" })
        let chain = try PostProcessChain(context: context, shaderLibrary: shaderLib)
        let width = 1920, height = 1080
        chain.allocateTextures(width: width, height: height)

        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: width, height: height,
            mipmapped: false)
        outputDesc.usage = [.renderTarget, .shaderRead]
        outputDesc.storageMode = .shared
        let outputTexture = try XCTUnwrap(device.makeTexture(descriptor: outputDesc))
        let fftBuf = try XCTUnwrap(device.makeBuffer(
            length: 512 * MemoryLayout<Float>.size, options: .storageModeShared))
        let wavBuf = try XCTUnwrap(device.makeBuffer(
            length: 2048 * MemoryLayout<Float>.size, options: .storageModeShared))

        // Worst case: all spikes fully active
        var features = makeFeatures(
            time: 30.0, bass: 0.8, mid: 0.7, treble: 0.5, beatBass: 0.6)
        let stems = StemFeatures(
            vocalsEnergy: 0.7, vocalsBand0: 0.35, vocalsBand1: 0.21,
            vocalsBeat: 0, drumsEnergy: 0.6, drumsBand0: 0.36,
            drumsBand1: 0.24, drumsBeat: 0.9, bassEnergy: 0.8,
            bassBand0: 0.56, bassBand1: 0.4, bassBeat: 0,
            otherEnergy: 0, otherBand0: 0, otherBand1: 0, otherBeat: 0)

        // Warmup (5 frames)
        for _ in 0 ..< 5 {
            guard let cmd = context.commandQueue.makeCommandBuffer() else { continue }
            chain.render(scenePipelineState: preset.pipelineState,
                         features: &features, fftBuffer: fftBuf,
                         waveformBuffer: wavBuf, stemFeatures: stems,
                         outputTexture: outputTexture, commandBuffer: cmd)
            cmd.commit(); cmd.waitUntilCompleted()
        }

        // Measure 30 frames
        var times: [Double] = []
        for _ in 0 ..< 30 {
            let start = CFAbsoluteTimeGetCurrent()
            guard let cmd = context.commandQueue.makeCommandBuffer() else { continue }
            chain.render(scenePipelineState: preset.pipelineState,
                         features: &features, fftBuffer: fftBuf,
                         waveformBuffer: wavBuf, stemFeatures: stems,
                         outputTexture: outputTexture, commandBuffer: cmd)
            cmd.commit(); cmd.waitUntilCompleted()
            times.append(CFAbsoluteTimeGetCurrent() - start)
        }

        let avgMs = (times.reduce(0, +) / Double(times.count)) * 1000.0
        let maxMs = (times.max() ?? 0) * 1000.0
        let minMs = (times.min() ?? 0) * 1000.0
        let p95 = times.sorted()[Int(Double(times.count) * 0.95)] * 1000.0

        print("\n=== RENDER PERFORMANCE (1080p, worst-case) ===")
        print("  Avg: \(String(format: "%.2f", avgMs)) ms")
        print("  Min: \(String(format: "%.2f", minMs)) ms")
        print("  Max: \(String(format: "%.2f", maxMs)) ms")
        print("  P95: \(String(format: "%.2f", p95)) ms")
        print("  Budget: 16.67 ms (60fps)")
        print("  Headroom: \(String(format: "%.2f", 16.67 - avgMs)) ms")
        print("===============================================\n")

        XCTAssertLessThan(avgMs, 16.67,
                          "Average frame \(String(format: "%.1f", avgMs))ms "
                          + "exceeds 60fps budget")
    }

    // MARK: - 6. Full State Matrix (diagnostic output, no assertions)

    /// Renders all 8 audio states at 1080p and prints a summary table with
    /// surface metrics.  Writes PNGs for visual inspection.
    func testFullHDDiagnosticAllStates() throws {
        let preset = try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" })
        let chain = try PostProcessChain(context: context, shaderLibrary: shaderLib)
        let width = 1920, height = 1080
        chain.allocateTextures(width: width, height: height)

        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: width, height: height,
            mipmapped: false)
        outputDesc.usage = [.renderTarget, .shaderRead]
        outputDesc.storageMode = .shared
        let outputTexture = try XCTUnwrap(device.makeTexture(descriptor: outputDesc))
        let fftBuf = try XCTUnwrap(device.makeBuffer(
            length: 512 * MemoryLayout<Float>.size, options: .storageModeShared))
        let wavBuf = try XCTUnwrap(device.makeBuffer(
            length: 2048 * MemoryLayout<Float>.size, options: .storageModeShared))

        let states: [(String, FeatureVector, StemFeatures)] = [
            ("01_silence",
             makeFeatures(time: 1.0), StemFeatures()),
            ("02_bass_only",
             makeFeatures(time: 5.0, bass: 0.6), StemFeatures()),
            ("03_vocals_enter",
             makeFeatures(time: 15.0, bass: 0.5, mid: 0.5),
             StemFeatures()),
            ("04_full_chorus",
             makeFeatures(time: 30.0, bass: 0.8, mid: 0.7, treble: 0.5,
                          flux: 0.5),
             StemFeatures(
                vocalsEnergy: 0.7, vocalsBand0: 0.35, vocalsBand1: 0.21,
                vocalsBeat: 0, drumsEnergy: 0.6, drumsBand0: 0.36,
                drumsBand1: 0.24, drumsBeat: 0.9, bassEnergy: 0.8,
                bassBand0: 0.56, bassBand1: 0.4, bassBeat: 0,
                otherEnergy: 0, otherBand0: 0, otherBand1: 0, otherBeat: 0)),
            ("05_drum_flash",
             makeFeatures(time: 35.0, bass: 0.5, mid: 0.3, beatBass: 0.8,
                          flux: 0.7),
             StemFeatures(
                vocalsEnergy: 0.3, vocalsBand0: 0.15, vocalsBand1: 0.09,
                vocalsBeat: 0, drumsEnergy: 0.8, drumsBand0: 0.48,
                drumsBand1: 0.32, drumsBeat: 1.0, bassEnergy: 0.5,
                bassBand0: 0.35, bassBand1: 0.25, bassBeat: 0,
                otherEnergy: 0, otherBand0: 0, otherBand1: 0, otherBeat: 0)),
            ("06_ambient_low",
             makeFeatures(time: 45.0, bass: 0.2, mid: 0.15, treble: 0.1),
             StemFeatures()),
            ("07_ultrawide",
             makeFeatures(time: 20.0, bass: 0.6, mid: 0.5, aspect: 2.35),
             StemFeatures()),
            ("08_portrait",
             makeFeatures(time: 20.0, bass: 0.6, mid: 0.5, aspect: 0.5625),
             StemFeatures())
        ]

        let outDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PhospheneFerrofluidOceanDiagnostic")
        try FileManager.default.createDirectory(
            at: outDir, withIntermediateDirectories: true)

        print("\n" + String(repeating: "=", count: 110))
        print("FERROFLUID OCEAN DIAGNOSTIC — 1920×1080")
        print(String(repeating: "=", count: 110))
        let header = "State".padding(toLength: 18, withPad: " ", startingAt: 0)
            + " | Spike px | Top row | Bot row | Height | Bg lum  "
            + "| HDR px   | %black"
        print(header)
        print(String(repeating: "-", count: 110))

        for (name, var features, stems) in states {
            guard let cmdBuf = context.commandQueue.makeCommandBuffer()
            else { continue }
            chain.render(
                scenePipelineState: preset.pipelineState,
                features: &features, fftBuffer: fftBuf,
                waveformBuffer: wavBuf, stemFeatures: stems,
                outputTexture: outputTexture, commandBuffer: cmdBuf)
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()

            // Write PNGs
            let sdrURL = outDir.appendingPathComponent("\(name)_sdr.png")
            writeTextureToPNG(outputTexture, url: sdrURL)
            if let scene = chain.sceneTexture {
                let hdrURL = outDir.appendingPathComponent("\(name)_hdr.png")
                writeTextureToPNG(scene, url: hdrURL)

                // Metrics
                let ext = measureSpikeExtent(texture: scene)
                let spikeH = max(ext.bottomRow - ext.topRow, 0)
                let bgLum = meanLuminance(
                    texture: scene,
                    rowRange: 0...Int(Float(height) * 0.15),
                    colRange: 0...(width - 1))
                let hdrCount = countBrightPixels(texture: scene, threshold: 1.0)
                let raw16 = readHalfPixels(scene)
                var blackCount = 0
                let surfaceStart = Int(Float(height) * 0.4)
                let surfacePx = width * (height - surfaceStart)
                for row in surfaceStart ..< height {
                    for col in 0 ..< width {
                        let idx = (row * width + col) * 4
                        let r = halfToFloat(raw16[idx])
                        let g = halfToFloat(raw16[idx + 1])
                        let b = halfToFloat(raw16[idx + 2])
                        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                        if lum < 0.02 { blackCount += 1 }
                    }
                }
                let pctBlack = Float(blackCount) / Float(surfacePx) * 100

                let line = name.padding(toLength: 18, withPad: " ", startingAt: 0)
                    + " | \(String(format: "%8d", ext.spikePixelCount))"
                    + " | \(String(format: "%7d", ext.topRow))"
                    + " | \(String(format: "%7d", ext.bottomRow))"
                    + " | \(String(format: "%6d", spikeH))"
                    + " | \(String(format: "%7.4f", bgLum))"
                    + " | \(String(format: "%8d", hdrCount))"
                    + " | \(String(format: "%5.1f", pctBlack))%"
                print(line)
            }
        }

        print(String(repeating: "=", count: 110))
        print("\nDiagnostic PNGs: \(outDir.path)")
        print("")
    }
}
