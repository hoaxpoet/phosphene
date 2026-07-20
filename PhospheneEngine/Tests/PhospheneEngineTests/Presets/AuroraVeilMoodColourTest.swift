// AuroraVeilPitchHueTest — AV.7 mood-colour migration gate.
//
// Validates the AV.7 colour route: as `f.valence` (the track's mood) sweeps
// dark → bright, the rendered curtain's hue migrates *continuously* across the
// IQ palette — warming toward pink at higher mood, cooling to deep green when
// the music darkens. The failure mode this gate catches is "stepwise /
// quantised" migration, where adjacent valence values produce visibly
// discontinuous palette jumps (the palette stuttering rather than flowing with
// the song).
//
// History: this file previously gated the AV.2.h vocal-pitch → hue route
// (`smoothedPitchNorm` bound at slot 6). That route was deleted in the AV.7
// reauthor along with the rest of the three-channel set; the gate was
// re-pointed at the mood route that replaced it rather than dropped, so the
// "continuous, not quantised" contract survives the rewrite.
//
// Hue scalar: `atan2(R - G, B - G)`. Monotonic in the IQ-palette phase shift
// produced by `paletteWarm = valence × 0.5`, because the per-channel `sin()`
// differences (R, G, B at phases -1.15, +1.5, -0.2 relative to the offset)
// preserve quadrant ordering as the offset shifts monotonically.

import Testing
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

private struct AuroraVeilStateGPUMirror {
    var kinkAccumulator: Float
    var smoothedPitchNorm: Float
    var padA: Float = 0
    var padB: Float = 0
}

@Suite("AuroraVeil mood colour")
struct AuroraVeilMoodColourTest {

    private static let renderWidth  = 128
    private static let renderHeight = 64

    // MARK: - Pitch sweep → monotonic + smooth hue migration

    @Test("valence sweep produces continuous mood-colour migration")
    func test_valenceSweep_continuousHueMigration() throws {
        // AV.7 (2026-07-19): the hue route is now mood (`f.valence`), not vocal
        // pitch — the vocal-pitch route was removed with the rest of the AV.2.h
        // three-channel set. valence spans roughly [-0.75, +0.77] on real music
        // (measured, Cherub Rock); the shader maps it to a whole-palette phase
        // shift of ±0.5 rad, warming the curtain toward pink at higher mood and
        // cooling it to deep green when the music darkens.
        let steps = 8
        let sweep: [Float] = (0..<steps).map { -1.0 + 2.0 * Float($0) / Float(steps - 1) }
        var hueScalars: [Float] = []
        for valence in sweep {
            guard let pixels = try renderFrame(valence: valence) else {
                print("AuroraVeilMoodColour: skipping — no Metal device")
                return
            }
            // Find the brightest column at the aurora mid altitude (uv.y=0.5)
            // so the hue sample lives where the IQ palette is fully
            // expressed (away from the envelope's edges).
            let brightCol = findBrightestColumn(pixels: pixels)

            // Average the hue scalar across three altitudes inside the
            // aurora band (the prompt's §5.7 sampling at uv.y=0.4/0.5/0.6).
            // Averaging smooths the per-pixel noise so step-to-step deltas
            // reflect palette migration rather than sampling jitter.
            var sum: Float = 0
            for uy in [Float(0.40), 0.50, 0.60] {
                sum += hueScalar(pixels: pixels, ux: brightCol, uy: uy)
            }
            hueScalars.append(sum / 3.0)
        }

        let sweepStr = zip(sweep, hueScalars)
            .map { "valence=\(String(format: "%.2f", $0.0)) → hue=\(String(format: "%.3f", $0.1))" }
            .joined(separator: ", ")

        // Monotonic across the sweep — tolerance for small fp noise. The hue
        // scalar should move consistently in one direction as valence rises,
        // because paletteWarm is a single additive phase offset applied to the
        // whole IQ palette.
        for i in 1..<hueScalars.count {
            let delta = hueScalars[i] - hueScalars[i - 1]
            #expect(
                delta >= -0.05,
                """
                Valence hue sweep is not monotonic at step \(i): \
                \(hueScalars[i - 1]) → \(hueScalars[i]) (Δ=\(delta)). \
                Sweep: \(sweepStr).
                """
            )
        }

        // Step-to-step jump < 30 % of total sweep range — encodes the
        // "stepwise hue migration" gate from `prompts/AV.2-prompt.md §4`.
        let totalRange = abs(hueScalars.last! - hueScalars.first!)
        #expect(
            totalRange >= 0.1,
            """
            Valence hue sweep total range \(totalRange) is too small. \
            Either the mood-colour route is unwired or the shader is reading a \
            constant valence. Sweep: \(sweepStr).
            """
        )

        // Step threshold accommodates the IQ palette's natural curvature:
        // the cosine response of each channel to baseOffset isn't linear,
        // so atan2(R-G, B-G) accelerates as baseOffset rotates through the
        // R-channel rising edge near base=0.4. The 0.45 threshold catches
        // *quantisation* (an integer cast or floor in the shader would
        // produce one ~100 % step and zeros elsewhere) without flagging
        // the natural IQ curve (~30–40 % at the steepest step). If a true
        // quantisation regression is introduced, the failing step delta
        // will be ≥ 0.5 × total range.
        let stepThreshold = 0.45 * totalRange
        for i in 1..<hueScalars.count {
            let stepDelta = abs(hueScalars[i] - hueScalars[i - 1])
            #expect(
                stepDelta <= stepThreshold + 1e-4,
                """
                Step \(i) hue delta \(stepDelta) exceeds 45 % of total \
                sweep range (\(stepThreshold)). Hue migration is \
                stepwise / quantised rather than continuous — the \
                mood-colour route is broken. Sweep: \(sweepStr).
                """
            )
        }
    }

    // MARK: - Render harness (mirrors AuroraVeilContinuousDominanceTest)

    private func renderFrame(valence: Float) throws -> [UInt8]? {
        guard let preset = _acceptanceFixture.presets.first(where: {
            $0.descriptor.name == "Aurora Veil"
        }) else {
            return nil
        }
        let ctx = try MetalContext()

        let width = Self.renderWidth
        let height = Self.renderHeight

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat,
            width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = ctx.device.makeTexture(descriptor: texDesc) else { return nil }

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fft  = ctx.makeSharedBuffer(length: 512 * floatStride),
            let wav  = ctx.makeSharedBuffer(length: 2048 * floatStride),
            let stem = ctx.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let hist = ctx.makeSharedBuffer(length: 4096 * floatStride),
            let avState = ctx.makeSharedBuffer(length: MemoryLayout<AuroraVeilStateGPUMirror>.stride)
        else { return nil }

        _ = fft.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 512 * floatStride)
        _ = wav.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 2048 * floatStride)
        _ = hist.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 4096 * floatStride)

        var stems = StemFeatures.zero
        stems.vocalsPitchConfidence = 0
        // Also set vocalsPitchHz to a representative value — the shader
        // doesn't read it directly in AV.2 (consumes the CPU-smoothed
        // value via slot 6), but keeping the stem layer self-consistent
        // helps if a future fix reroutes the read.
        stem.contents().copyMemory(from: &stems,
                                   byteCount: MemoryLayout<StemFeatures>.size)

        var features = FeatureVector(time: 3.0, deltaTime: 1.0 / 60.0)
        // Hold bass/mid/valence at zero so the palette migration is
        // attributable solely to the pitch route.
        features.bassAttRel = 0
        features.midAttRel = 0
        features.valence = valence
        features.arousal = 0.5
        features.barPhase01 = 0.5
        features.pulseAmp01 = 0

        var avMirror = AuroraVeilStateGPUMirror(
            kinkAccumulator: 0,
            smoothedPitchNorm: 0.5
        )
        avState.contents().copyMemory(from: &avMirror,
                                      byteCount: MemoryLayout<AuroraVeilStateGPUMirror>.stride)

        guard let cmd = ctx.commandQueue.makeCommandBuffer() else { return nil }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return nil }

        enc.setRenderPipelineState(preset.pipelineState)
        enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        enc.setFragmentBuffer(fft, offset: 0, index: 1)
        enc.setFragmentBuffer(wav, offset: 0, index: 2)
        enc.setFragmentBuffer(stem, offset: 0, index: 3)
        enc.setFragmentBuffer(hist, offset: 0, index: 5)
        enc.setFragmentBuffer(avState, offset: 0, index: 6)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    // MARK: - Pixel helpers

    /// Returns the uv.x in [0, 1] of the brightest column at the aurora
    /// mid-altitude (uv.y = 0.50). Robust against having the brightness
    /// max in a stars-only sky region (stars are sparse; mid-altitude
    /// sample sits inside the aurora envelope).
    private func findBrightestColumn(pixels: [UInt8]) -> Float {
        let midY = Int(0.50 * Double(Self.renderHeight))
        var bestX = 0
        var bestLuma: Float = -1
        for x in 0..<Self.renderWidth {
            let idx = (midY * Self.renderWidth + x) * 4
            let b = Float(pixels[idx + 0])
            let g = Float(pixels[idx + 1])
            let r = Float(pixels[idx + 2])
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            if luma > bestLuma {
                bestLuma = luma
                bestX = x
            }
        }
        return (Float(bestX) + 0.5) / Float(Self.renderWidth)
    }

    /// `atan2(R - G, B - G)` — a single scalar that monotonically tracks
    /// IQ-palette baseOffset phase shifts. Returns values in (-π, π];
    /// the test's monotonicity check tolerates small fp noise.
    private func hueScalar(pixels: [UInt8], ux: Float, uy: Float) -> Float {
        let x = max(0, min(Self.renderWidth  - 1, Int(ux * Float(Self.renderWidth))))
        let y = max(0, min(Self.renderHeight - 1, Int(uy * Float(Self.renderHeight))))
        let idx = (y * Self.renderWidth + x) * 4
        let b = Float(pixels[idx + 0])
        let g = Float(pixels[idx + 1])
        let r = Float(pixels[idx + 2])
        return atan2(r - g, b - g)
    }
}
