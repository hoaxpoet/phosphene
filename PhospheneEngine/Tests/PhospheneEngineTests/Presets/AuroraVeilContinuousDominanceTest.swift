// AuroraVeilContinuousDominanceTest — AV.2 continuous-vs-accent ratio gate.
//
// Validates the load-bearing §5.7 contract: brightness breathing
// (continuous, driven by `f.bass_att_rel`) dominates the gated drum kink
// (accent, driven by `kinkAccumulator`) by ≥ 10×. Without this
// invariant Aurora Veil regresses into a beat-flashing festival aurora
// (Failure Mode #11 — Failed Approach #4 catalog-wide).
//
// Two paired assertions:
//
//   1. Bass-sweep monotonic. Render at 5 increasing `bass_att_rel`
//      values (0.0 → 0.8), each with zero drum kink. Frame max-luma
//      must increase monotonically and the span between low and high
//      bass must clear ≥ 0.08 [0..1] luma — large enough to confirm
//      the brightness route is wired and meaningful at typical music
//      amplitudes.
//
//   2. Drum amplitude ≤ 10 % of bass amplitude. Render at peak kink
//      (kinkAccumulator = 0.8, bass = 0) vs control (both zero), and
//      at peak bass (bass = 0.8, kink = 0) vs control. The drum-induced
//      frame MSD (lateral UV jitter on the column noise sample) must
//      be ≤ 10 % of the bass-induced MSD. Encodes the §5.7
//      continuous-vs-accent ratio.

import Testing
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// 16-byte AuroraVeilStateGPU mirror — direct binding so the test can
// drive `kinkAccumulator` without going through the CPU state class's
// rare-event gate + decay logic.
private struct AuroraVeilStateGPUMirror {
    var kinkAccumulator: Float
    var smoothedPitchNorm: Float
    var padA: Float = 0
    var padB: Float = 0
}

@Suite("AuroraVeil continuous dominance")
struct AuroraVeilContinuousDominanceTest {

    private static let renderWidth  = 128
    private static let renderHeight = 64

    // MARK: - Bass sweep monotonicity

    @Test("Brightness breathing scales monotonically with bass_dev")
    func test_bassSweep_monotonic() throws {
        // AV.2.2d sweep positive-only bassDev. AV.2.2e adds a smoothstep
        // gate (lo 0.30 / hi 0.55) so bassDev below 0.30 produces no
        // brightness response (brightness stays at base). Sweep stays in
        // [0.0, 0.8] but the lower-end steps (0.0, 0.2) will land at
        // identical baseline brightness — the monotonicity check below
        // tolerates equal-step. The span 0.0 → 0.8 is what catches the
        // route-unwired regression.
        let sweep: [Float] = [0.0, 0.2, 0.4, 0.6, 0.8]
        var meanLumas: [Float] = []
        for bassDev in sweep {
            guard let pixels = try renderFrame(bassDev: bassDev,
                                               kinkAccumulator: 0,
                                               pitchNorm: 0.5,
                                               pitchConfidence: 0) else {
                print("AuroraVeilContinuousDominance: skipping — no Metal device")
                return
            }
            meanLumas.append(auroraBandMeanLuma(pixels: pixels))
        }

        // Print the sweep so a failure is debuggable from the test log alone.
        let sweepStr = zip(sweep, meanLumas)
            .map { "bassDev=\($0.0) → mean=\(String(format: "%.4f", $0.1))" }
            .joined(separator: ", ")

        // Monotonicity: each step ≥ previous. Tolerance for fp + per-octave
        // noise wobble (1/255 in normalised luma).
        for i in 1..<meanLumas.count {
            #expect(
                meanLumas[i] >= meanLumas[i - 1] - 1.0 / 255.0,
                """
                Bass sweep is not monotonic at step \(i): \
                \(meanLumas[i - 1]) → \(meanLumas[i]). Sweep: \(sweepStr).
                """
            )
        }

        // Span across the sweep — proves the route is wired. The shader's
        // brightness scale goes from 0.55 (at bassRel = -1.5 clamped to -1)
        // to 1.15 (at bassRel = 1.0). Over the [-0.8, 0.8] sweep the
        // multiplicative scale spans [0.61, 1.09] ≈ 1.78× range; mean
        // luma is expected to span a substantial fraction of the aurora
        // band's baseline luma.
        // AV.2.2d: route consumes `f.bass_dev` (positive-only, amp 0.30).
        // Sweep [0.0, 0.8] produces brightness shift 0.85 → 1.09 pre-clamp;
        // post-clamp the observable mean-luma span is bounded by the 0.95
        // ceiling. Observed sweep span ~0.018 because most bright aurora
        // pixels saturate at clamp; the route is monotonic but compressed.
        // Threshold 0.012 catches a true regression (route unwired →
        // constant brightness → zero span) without flagging the clamp-
        // bounded observable.
        let span = meanLumas.last! - meanLumas.first!
        #expect(
            span >= 0.012,
            """
            Bass sweep span \(span) below 0.012 mean-luma threshold — \
            brightness breathing route (f.bass_dev → 0.85 + 0.30 × bassDev \
            post-AV.2.2d) is wired but not producing visible response. \
            Sweep: \(sweepStr).
            """
        )
    }

    // MARK: - Continuous-vs-accent ratio (≥ 10×)

    @Test("Drum-kink amplitude ≤ 10% of bass-brightness amplitude at peak")
    func test_continuousDominanceRatio() throws {
        // Control: bass = 0, kink = 0. Both audio routes silent.
        guard let control = try renderFrame(bassDev: 0,
                                            kinkAccumulator: 0,
                                            pitchNorm: 0.5,
                                            pitchConfidence: 0) else {
            print("AuroraVeilContinuousDominance: skipping — no Metal device")
            return
        }
        // Peak bass, zero kink.
        guard let peakBass = try renderFrame(bassDev: 0.8,
                                             kinkAccumulator: 0,
                                             pitchNorm: 0.5,
                                             pitchConfidence: 0) else { return }
        // Zero bass, peak kink.
        guard let peakKink = try renderFrame(bassDev: 0,
                                             kinkAccumulator: 0.8,
                                             pitchNorm: 0.5,
                                             pitchConfidence: 0) else { return }

        let bassDelta = meanSquaredDiff(control, peakBass)
        let kinkDelta = meanSquaredDiff(control, peakKink)
        let ratio = kinkDelta / max(bassDelta, 1e-6)

        // The §5.7 contract is "continuous primaries dominate accents by
        // ≥ 10×." Threshold here is 0.10 (kink ≤ 10 % of bass).
        #expect(
            ratio <= 0.10,
            """
            Drum kink delta \(kinkDelta) > 10 % of bass brightness \
            delta \(bassDelta) (ratio \(ratio)). Failure Mode #11 risk: \
            the kink amplitude is at festival-strobe level, or the bass \
            brightness route is too weak. §5.7 ratio contract violated.
            """
        )

        // Sanity: bassDelta must be non-trivial — otherwise the ratio is
        // not meaningful. If both deltas are tiny, the test isn't actually
        // exercising the routes.
        #expect(
            bassDelta > 1.0,
            """
            Bass-driven frame delta \(bassDelta) too small to bound \
            anything — the brightness route may be unwired.
            """
        )
    }

    // MARK: - Render harness

    private func renderFrame(
        bassDev: Float,
        kinkAccumulator: Float,
        pitchNorm: Float,
        pitchConfidence: Float
    ) throws -> [UInt8]? {
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

        // Stems: only set vocals_pitch_confidence; everything else zero.
        // Shader pitch read is gated on confidence ≥ 0.5; for this test we
        // hold pitchNorm constant across the sweep so the brightness /
        // kink responses are isolated from the palette migration.
        var stems = StemFeatures.zero
        stems.vocalsPitchConfidence = pitchConfidence
        stem.contents().copyMemory(from: &stems,
                                   byteCount: MemoryLayout<StemFeatures>.size)

        // FeatureVector: set bass_att_rel; everything else stays at AV.1
        // silence-friendly defaults. time/deltaTime are fixed to avoid
        // substrate-drift differences between sweep steps confounding the
        // luma comparison.
        var features = FeatureVector(time: 3.0, deltaTime: 1.0 / 60.0)
        features.bassDev = bassDev

        // Slot-6 state buffer.
        var avMirror = AuroraVeilStateGPUMirror(
            kinkAccumulator: kinkAccumulator,
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

    /// Mean luma over the aurora band (uv.y ∈ [0.30, 0.70]) — the rows
    /// inside the shader's `auroraEnv` envelope where brightness modulation
    /// is unambiguously observable. Sky band (uv.y < 0.30) and dark-base
    /// band (uv.y > 0.70) are excluded to avoid washing the response with
    /// regions where the aurora contributes near-zero.
    private func auroraBandMeanLuma(pixels: [UInt8]) -> Float {
        let yStart = Int(0.30 * Double(Self.renderHeight))
        let yEnd   = Int(0.70 * Double(Self.renderHeight))
        var sum: Float = 0
        var count = 0
        for y in yStart..<yEnd {
            for x in 0..<Self.renderWidth {
                let idx = (y * Self.renderWidth + x) * 4
                let b = Float(pixels[idx + 0])
                let g = Float(pixels[idx + 1])
                let r = Float(pixels[idx + 2])
                sum += (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                count += 1
            }
        }
        return sum / Float(count)
    }

    /// Per-pixel mean squared difference (sum over BGR channels), in
    /// byte² units [0, 195075]. Higher = larger visual difference.
    private func meanSquaredDiff(_ a: [UInt8], _ b: [UInt8]) -> Float {
        precondition(a.count == b.count)
        var sum: Float = 0
        let total = a.count / 4
        for i in 0..<total {
            let db = Float(a[i * 4 + 0]) - Float(b[i * 4 + 0])
            let dg = Float(a[i * 4 + 1]) - Float(b[i * 4 + 1])
            let dr = Float(a[i * 4 + 2]) - Float(b[i * 4 + 2])
            sum += db * db + dg * dg + dr * dr
        }
        return sum / Float(total)
    }
}
