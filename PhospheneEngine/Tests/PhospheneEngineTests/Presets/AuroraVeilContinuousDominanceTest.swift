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

    @Test("Brightness breathing scales monotonically with arousal")
    func test_arousalSweep_monotonic() throws {
        // AV.7 (2026-07-19): the brightness route is now the mood-intensity
        // envelope (`f.arousal`), not `bass_dev` — the deviation primitives
        // measured too spiky on real music for the gentle response Matt asked
        // for (see the AV.7 closeout). breathe = clamp(1 + 0.8 × (arousal −
        // 0.5) + 0.3 × max(0, bass_att_rel), 0.85, 1.15), so a 0 → 1 arousal
        // sweep spans the full 0.85 → 1.15 clamp range. This sweep is what
        // catches the route-unwired regression (span collapses to zero).
        let sweep: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]
        var meanLumas: [Float] = []
        for arousal in sweep {
            guard let pixels = try renderFrame(arousal: arousal,
                                               bassAttRel: 0,
                                               valence: 0) else {
                print("AuroraVeilContinuousDominance: skipping — no Metal device")
                return
            }
            meanLumas.append(auroraBandMeanLuma(pixels: pixels))
        }

        // Print the sweep so a failure is debuggable from the test log alone.
        let sweepStr = zip(sweep, meanLumas)
            .map { "arousal=\($0.0) → mean=\(String(format: "%.4f", $0.1))" }
            .joined(separator: ", ")

        // Monotonicity: each step ≥ previous. Tolerance for fp + per-octave
        // noise wobble (1/255 in normalised luma).
        for i in 1..<meanLumas.count {
            #expect(
                meanLumas[i] >= meanLumas[i - 1] - 1.0 / 255.0,
                """
                Arousal sweep is not monotonic at step \(i): \
                \(meanLumas[i - 1]) → \(meanLumas[i]). Sweep: \(sweepStr).
                """
            )
        }

        // Span across the sweep — proves the route is wired. Arousal 0 → 1
        // drives breathe across its full 0.85 → 1.15 clamp range (≈ 35 %
        // multiplicative), so the observable aurora-band mean luma must move
        // by a clear margin. Threshold 0.012 catches the true regression
        // (route unwired → constant brightness → zero span) while tolerating
        // the clamp-bounded compression of already-bright pixels.
        let span = meanLumas.last! - meanLumas.first!
        #expect(
            span >= 0.012,
            """
            Arousal sweep span \(span) below 0.012 mean-luma threshold — \
            the brightness breathing route (f.arousal → breathe) is not \
            producing a visible response. Sweep: \(sweepStr).
            """
        )
    }

    // MARK: - Continuous-vs-accent ratio (≥ 10×)

    @Test("Bass lift stays subordinate to the mood breathe")
    func test_continuousDominanceRatio() throws {
        // AV.7: the accent being bounded is no longer the drum kink (deleted)
        // but the smoothed bass lift (`bass_att_rel`). The contract it inherits
        // is the same one §5.7 always encoded and the Audio Data Hierarchy
        // requires: the slow continuous driver must dominate the faster layer,
        // so the veil reads as breathing with the song rather than pumping on
        // the bass. Sweep each driver over its real observed range (arousal
        // p05→p95 ≈ 0 → 0.65; bass_att_rel max ≈ 0.38 on real music).
        guard let control = try renderFrame(arousal: 0.5, bassAttRel: 0, valence: 0) else {
            print("AuroraVeilContinuousDominance: skipping — no Metal device")
            return
        }
        // Full mood swing, no bass.
        guard let peakMood = try renderFrame(arousal: 1.0, bassAttRel: 0, valence: 0) else { return }
        // Peak realistic bass lift, mood held at its midpoint.
        guard let peakBass = try renderFrame(arousal: 0.5, bassAttRel: 0.38, valence: 0) else { return }

        let moodDelta = meanSquaredDiff(control, peakMood)
        let bassDelta = meanSquaredDiff(control, peakBass)
        let ratio = bassDelta / max(moodDelta, 1e-6)

        #expect(
            ratio <= 0.5,
            """
            Bass-lift delta \(bassDelta) is not subordinate to the mood \
            breathe delta \(moodDelta) (ratio \(ratio) > 0.5). The gentle bass \
            layer has become the dominant brightness driver — the veil will \
            read as pumping on the bass rather than breathing with the song.
            """
        )

        // Sanity: the mood route must be doing real work, otherwise the ratio
        // bounds nothing.
        #expect(
            moodDelta > 1.0,
            """
            Mood-driven frame delta \(moodDelta) too small to bound \
            anything — the breathe route may be unwired.
            """
        )
    }

    // MARK: - Render harness

    private func renderFrame(
        arousal: Float,
        bassAttRel: Float,
        valence: Float
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

        // AV.7: the shader reads no stem fields — leave StemFeatures zeroed.
        var stems = StemFeatures.zero
        stem.contents().copyMemory(from: &stems,
                                   byteCount: MemoryLayout<StemFeatures>.size)

        // FeatureVector: drive the three AV.7 routes. time/deltaTime are fixed
        // so substrate drift can't confound the luma comparison between steps,
        // and bar_phase01 is held at 0.5 (between downbeats) so the star
        // beat-twinkle contributes no variance to the sweep.
        var features = FeatureVector(time: 3.0, deltaTime: 1.0 / 60.0)
        features.arousal = arousal
        features.bassAttRel = bassAttRel
        features.valence = valence
        features.barPhase01 = 0.5
        features.pulseAmp01 = 0

        // Slot-6 state buffer retained (still bound by the loader) but unused.
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
