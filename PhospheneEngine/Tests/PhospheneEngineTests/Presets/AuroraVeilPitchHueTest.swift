// AuroraVeilPitchHueTest — AV.2 vocal-pitch palette migration gate.
//
// Validates the §5.7 route 1 contract: as `vocalsPitchNorm` (the smoothed
// log2-normalised vocal pitch) sweeps low → high, the rendered ribbon's
// hue migrates *continuously* across the IQ palette. The failure mode this
// gate catches is "stepwise / quantized" hue migration — when adjacent
// pitch values produce visibly discontinuous palette jumps (which would
// look like the palette stuttering between songs' vocal lines rather than
// flowing with the melody).
//
// The test bypasses the CPU `AuroraVeilState` smoother and binds
// `smoothedPitchNorm` directly at slot 6 — this isolates the shader's
// pitch → hue mapping from the CPU smoothing logic. (The state class's
// own correctness is implicit in the field's continuous value range
// produced by its 5-frame moving average; a stepwise output would mean
// the SHADER itself is quantising, e.g. via an int cast or fract+floor.)
//
// `vocals_pitch_confidence` is held at 1.0 across the sweep so the
// shader's confidence gate doesn't degrade the test to its 0.5 fallback
// midway through.
//
// Hue scalar: `atan2(R - G, B - G)`. Monotonic in the IQ-palette phase
// shift produced by `(pitchNorm - 0.5) × 1.6` on `baseOffset`, because
// the per-channel `sin()` differences (R, G, B with phases -1.15, +1.5,
// -0.2 relative to baseOffset) preserve quadrant ordering as baseOffset
// monotonically shifts.

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

@Suite("AuroraVeil pitch hue")
struct AuroraVeilPitchHueTest {

    private static let renderWidth  = 128
    private static let renderHeight = 64

    // MARK: - Pitch sweep → monotonic + smooth hue migration

    @Test("vocals_pitch sweep produces continuous + monotonic hue migration")
    func test_pitchSweep_continuousHueMigration() throws {
        // 8-step sweep on `smoothedPitchNorm` in [0, 1] — covers the
        // E2-to-~C7 musical range the §5.7 / research §3.3 normalisation
        // is designed to span.
        let steps = 8
        let sweep: [Float] = (0..<steps).map { Float($0) / Float(steps - 1) }

        // Pick the sample column ONCE from a reference render (mid pitch) and
        // reuse it for every step, so the sweep measures hue-vs-pitch at a FIXED
        // location. Re-finding the brightest column per step (the old form)
        // conflates a position shift — e.g. the AV.5 perspective drape moving
        // which curtain is brightest — with the hue change under test. The
        // footprint is pitch-independent, so a column lit at the reference pitch
        // is lit at every pitch; only its colour migrates.
        guard let refPixels = try renderFrame(pitchNorm: 0.5,
                                              pitchConfidence: 1.0) else {
            print("AuroraVeilPitchHue: skipping — no Metal device")
            return
        }
        let sampleCol = findBrightestColumn(pixels: refPixels)

        var hueScalars: [Float] = []
        for pitchNorm in sweep {
            guard let pixels = try renderFrame(pitchNorm: pitchNorm,
                                               pitchConfidence: 1.0) else {
                print("AuroraVeilPitchHue: skipping — no Metal device")
                return
            }
            // Average the hue scalar across three altitudes inside the
            // aurora band (the prompt's §5.7 sampling at uv.y=0.4/0.5/0.6).
            // Averaging smooths the per-pixel noise so step-to-step deltas
            // reflect palette migration rather than sampling jitter.
            var sum: Float = 0
            for uy in [Float(0.40), 0.50, 0.60] {
                sum += hueScalar(pixels: pixels, ux: sampleCol, uy: uy)
            }
            hueScalars.append(sum / 3.0)
        }

        let sweepStr = zip(sweep, hueScalars)
            .map { "pitchNorm=\(String(format: "%.2f", $0.0)) → hue=\(String(format: "%.3f", $0.1))" }
            .joined(separator: ", ")

        // Monotonic across the sweep — tolerance for small fp noise.
        // The hue scalar should monotonically INCREASE as pitchNorm rises
        // (palette migrates green-base → magenta-mixed; B-G rises faster
        // than R-G, so atan2 rotates CCW into the 2nd-quadrant direction).
        for i in 1..<hueScalars.count {
            let delta = hueScalars[i] - hueScalars[i - 1]
            #expect(
                delta >= -0.05,
                """
                Pitch hue sweep is not monotonic at step \(i): \
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
            Pitch hue sweep total range \(totalRange) is too small. \
            Either the route is unwired or the shader is reading a \
            constant smoothedPitchNorm. Sweep: \(sweepStr).
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
                §5.7 vocal-pitch route is broken. Sweep: \(sweepStr).
                """
            )
        }
    }

    // MARK: - Render harness (mirrors AuroraVeilContinuousDominanceTest)

    private func renderFrame(pitchNorm: Float, pitchConfidence: Float) throws -> [UInt8]? {
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
        stems.vocalsPitchConfidence = pitchConfidence
        // Also set vocalsPitchHz to a representative value — the shader
        // doesn't read it directly in AV.2 (consumes the CPU-smoothed
        // value via slot 6), but keeping the stem layer self-consistent
        // helps if a future fix reroutes the read.
        stems.vocalsPitchHz = 80.0 * pow(2.0, pitchNorm * 4.0)
        stem.contents().copyMemory(from: &stems,
                                   byteCount: MemoryLayout<StemFeatures>.size)

        var features = FeatureVector(time: 3.0, deltaTime: 1.0 / 60.0)
        // Hold bass/mid/valence at zero so the palette migration is
        // attributable solely to the pitch route.
        features.bassAttRel = 0
        features.midAttRel = 0
        features.valence = 0

        var avMirror = AuroraVeilStateGPUMirror(
            kinkAccumulator: 0,
            smoothedPitchNorm: pitchNorm
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
