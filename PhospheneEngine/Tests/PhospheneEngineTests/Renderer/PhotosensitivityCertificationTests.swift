// PhotosensitivityCertificationTests — enforced flash-safety gate (CLEAN.7.6, GAP-9).
//
// Every CERTIFIED preset is rendered over a synthetic worst-case beat train and
// its rendered full-frame luminance is measured against the Harding / WCAG 2.3.1
// general-flash limit (≤ 3 flashes/s). A preset that exceeds the limit FAILS the
// gate — it is a P1 safety finding to bring to Matt, not a number to tune away
// (CLEAN.7.6 rule; the certified beat-luminance motion was hand-tuned safe).
//
// WHY a synthetic drive (and not a recorded real session): the FBS forensics
// video that the kickoff named as the A/B reference was never committed, and the
// `Fixtures/fbs` CSVs are 3-band energy extracts that carry none of the beat /
// deviation / stem signals that actually cause flashing. The established cert
// gates (PresetContrastCertificationTests, PresetRegressionTests) all drive from
// synthetic FeatureVector fixtures rendered in-test; this gate follows that
// pattern. (Matt's pick, 2026-06-16: synthetic CI gate now; the blind spots
// below fold into the A-next runtime-clamp increment.)
//
// COVERAGE. This lightweight harness drives only the FeatureVector through a single
// fragment pass, so it VALIDLY measures only presets that read their music response
// directly from the FeatureVector in that pass:
//   - Ferrofluid Ocean, Murmuration — measured here, both SAFE.
//   - Nimbus — `.direct` + a CPU follower buffer (slot 6); `renderLuminanceSequence`
//     ticks the real NimbusState, so it is measured here too (CLEAN.7.6b).
// The other four certified presets read their response through multi-pass / feedback
// paths this single-pass harness does not run, so they render static here and are
// measured for real by `MultiPassFlashHarnessTests` (CLEAN.7.6c), which drives the live
// RenderPipeline headless — all four 0–1 flashes/s SAFE (G9 fully enforced, 7/7):
//   - Lumen Mosaic — ray_march + post_process + the 4-light follower (slot 8).
//   - Dragon Bloom, Fata Morgana, Skein — mv_warp FEEDBACK (NOT rayMarch: CLEAN.7.6 /
//     7.6b persistently mislabelled DB+FM as rayMarch; their passes are in fact
//     ["direct","mv_warp"], 0 raymarch loops). Fata Morgana has the bespoke
//     `renderFataMorgana` mirage path.
// This gate SKIPS that set (see `multiPassMeasured`) and FAILS LOUD if a NEW certified
// preset renders static here without joining the multi-pass harness — a static render is
// NEVER asserted "safe" (a vacuous pass, the cardinal sin for a safety gate, CLEAN.0).
//
// FURTHER blind spots (all A-next): full-frame mean only (a sub-region flash <
// 10 % of the mean passes — regional/area-gating is the refinement); no
// saturated-red-flash channel; normal certified regime only (no edge states).

import Testing
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - PhotosensitivityCertificationTests

@Suite("Photosensitivity Certification (Harding / WCAG 2.3.1, CLEAN.7.6)")
struct PhotosensitivityCertificationTests {

    private let renderSize = 64
    // The worst-case drive, the responsiveness threshold, and the WCAG luminance
    // reducer are shared with the multi-pass gate via `FlashHarnessSupport` (one set
    // of terms for both halves — kickoff: reuse, don't fork).

    /// Certified presets whose music response is multi-pass / feedback-driven, so the
    /// single-pass FeatureVector harness renders them static. They are measured for real
    /// by `MultiPassFlashHarnessTests` (CLEAN.7.6c — the faithful headless RenderPipeline
    /// harness), so this single-pass gate SKIPS them. Kept explicit so the gate stays
    /// honest about the division of labour and FAILS LOUD if a NEW certified preset
    /// renders static here without joining the multi-pass harness.
    static let multiPassMeasured: Set<String> = [
        "Lumen Mosaic",   // ray_march + post_process + the 4-light follower (slot 8)
        "Dragon Bloom",   // mv_warp feedback (strands-on-top + per-beat display pulse)
        "Fata Morgana",   // mv_warp feedback (bespoke renderFataMorgana mirage path)
        "Skein",          // mv_warp feedback (cream canvas-hold + per-stem paint + sheen)
        "Nacre",          // mv_warp feedback (bespoke renderNacre; downbeat camera push) — NACRE.4
        "Floret",         // mv_warp feedback (bespoke renderFloret; z² bloom + bass-kick ripple) — FLORET.4
        "Glaze",          // mv_warp feedback (bespoke renderGlaze; spring jelly + downbeat camera push) — GLAZE.8
        "Filigree",       // particles (PhysarumGeometry trail — geometry-driven, black backdrop) — PHYS.5
    ]

    // MARK: - Gate

    @Test("Certified preset is flash-safe under a worst-case beat train (single-pass set)",
          arguments: _acceptanceFixture.presets)
    func certifiedPresetIsFlashSafe(_ preset: PresetLoader.LoadedPreset) throws {
        // Gate covers the certified, shipping set. Mesh-shader presets cannot
        // drawPrimitives in this harness and are skipped (same as the other gates).
        guard preset.descriptor.certified else { return }
        guard !preset.descriptor.passes.contains(.meshShader) else { return }
        let name = preset.descriptor.name
        // The multi-pass / feedback presets are measured for real by
        // `MultiPassFlashHarnessTests`; this single-pass harness cannot reach their
        // response, so it does not (and must not) assert anything about them.
        guard !Self.multiPassMeasured.contains(name) else { return }

        let ctx = try MetalContext()
        let drive = FlashHarnessSupport.worstCaseBeatTrain()
        let luma = try renderLuminanceSequence(preset: preset, features: drive, context: ctx)
        let report = FlashAnalyzer.analyze(relativeLuminance: luma, fps: FlashHarnessSupport.fps)

        let lo = luma.min() ?? 0, hi = luma.max() ?? 0
        let range = hi - lo
        let responded = range >= FlashHarnessSupport.responsiveLumaRange
        let mean = luma.reduce(0, +) / Double(max(luma.count, 1))

        // Evidence line (closeout per-preset table). This gate's measured output is its
        // visual evidence; printed for every preset it measures.
        print(String(
            format: "[flash-safety] %@: %@ | peak %.2f flashes/s (%d transitions) — %@ | luma %.3f…%.3f (Δ%.3f, mean %.3f) [limit 3.0]",
            name, responded ? "MEASURED" : "UNMEASURED(static)",
            report.peakFlashesPerSecond, report.transitionCount,
            report.isSafe ? "SAFE" : "UNSAFE", lo, hi, range, mean))

        // A static render here means a NEW certified preset reads its response through a
        // path this single-pass harness can't drive — it must join the multi-pass harness,
        // not be silently passed (the CLEAN.0 vacuous-pass rule). Fail loud.
        #expect(
            responded,
            """
            '\(name)' rendered static (Δ\(String(format: "%.3f", range))) under the flash drive but is not in \
            `multiPassMeasured` — this single-pass FeatureVector harness cannot validly flash-gate it. \
            Add it to `MultiPassFlashHarnessTests` (and `multiPassMeasured`); do not let it pass unmeasured.
            """
        )
        // Validly measured → real Harding/WCAG safety assertion.
        #expect(
            report.isSafe,
            """
            '\(name)' peaks at \(String(format: "%.2f", report.peakFlashesPerSecond)) \
            flashes/s (limit 3) under a \(String(format: "%.1f", FlashHarnessSupport.accentHz)) Hz worst-case beat train \
            — exceeds Harding/WCAG 2.3.1. P1 safety finding: bring to Matt, do not tune away.
            """
        )
    }

    /// Guards against a vacuous pass: if the Shaders bundle fails to load, the
    /// parameterized gate above would run zero certified cases and silently pass.
    @Test("Certified preset set is non-empty (gate is not vacuous)")
    func certifiedSetIsPresent() {
        let certified = _acceptanceFixture.presets.filter { $0.descriptor.certified }
        #expect(!certified.isEmpty, "No certified presets loaded — Shaders bundle missing? The flash gate would pass vacuously.")
    }

    // MARK: - Rendering

    /// Render `features` frame-by-frame (feedback-less, cleared each frame) and
    /// return the per-frame WCAG relative luminance (linear-light, Rec. 709).
    private func renderLuminanceSequence(
        preset: PresetLoader.LoadedPreset,
        features: [FeatureVector],
        context ctx: MetalContext
    ) throws -> [Double] {
        let size = renderSize
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: size, height: size, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = ctx.device.makeTexture(descriptor: texDesc) else {
            throw FlashGateError.textureAllocationFailed
        }
        let floatStride = MemoryLayout<Float>.stride
        guard
            let fft  = ctx.makeSharedBuffer(length: 512 * floatStride),
            let wav  = ctx.makeSharedBuffer(length: 2048 * floatStride),
            let stem = ctx.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let hist = ctx.makeSharedBuffer(length: 4096 * floatStride),
            let slot = ctx.makeSharedBuffer(length: 1024)
        else { throw FlashGateError.bufferAllocationFailed }
        _ = stem.contents().initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<StemFeatures>.size)
        _ = hist.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 4096 * floatStride)
        _ = slot.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 1024)

        var scene: MTLBuffer?
        if preset.descriptor.passes.contains(.rayMarch),
           let buf = ctx.makeSharedBuffer(length: MemoryLayout<SceneUniforms>.size) {
            var su = preset.descriptor.makeSceneUniforms()
            buf.contents().copyMemory(from: &su, byteCount: MemoryLayout<SceneUniforms>.size)
            scene = buf
        }

        // CLEAN.7.6b Stage 1: Nimbus is a `.direct` preset whose music response
        // is computed by a CPU follower engine and fed to the shader at fragment
        // buffer 6 — zeroed in the single-pass harness, so it otherwise renders
        // static. Reproduce the engine: construct it, tick it per frame (in the
        // loop below), and bind its live buffer. `StemFeatures.zero` is correct
        // for the 3 s window — Nimbus's directional stem lobes are gated out by
        // its ~9-13 s cold-start ramp, so the FULL-FRAME flash signal is the
        // FeatureVector-driven whole-body kick/bloom, which the worst-case beat
        // train drives from frame 1.
        let nimbusState: NimbusState? =
            preset.descriptor.name == "Nimbus" ? NimbusState(device: ctx.device) : nil

        var luma: [Double] = []
        luma.reserveCapacity(features.count)
        var pixels = [UInt8](repeating: 0, count: size * size * 4)

        for frameIndex in features.indices {
            var fv = features[frameIndex]
            guard let cmdBuf = ctx.commandQueue.makeCommandBuffer() else {
                throw FlashGateError.commandBufferFailed
            }
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture     = texture
            rpd.colorAttachments[0].loadAction  = .clear   // feedback-less (documented limit)
            rpd.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            rpd.colorAttachments[0].storeAction = .store
            guard let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
                throw FlashGateError.encoderCreationFailed
            }
            enc.setRenderPipelineState(preset.pipelineState)
            enc.setFragmentBytes(&fv, length: MemoryLayout<FeatureVector>.size, index: 0)
            enc.setFragmentBuffer(fft,  offset: 0, index: 1)
            enc.setFragmentBuffer(wav,  offset: 0, index: 2)
            enc.setFragmentBuffer(stem, offset: 0, index: 3)
            if let sceneBuf = scene { enc.setFragmentBuffer(sceneBuf, offset: 0, index: 4) }
            enc.setFragmentBuffer(hist, offset: 0, index: 5)
            // Follower-state presets (Nimbus): tick the real engine with this
            // frame's drive and bind its live state buffer at slot 6, so the
            // pass reads the genuine per-frame response instead of a zeroed slot.
            if let ns = nimbusState {
                ns.tick(deltaTime: fv.deltaTime, features: fv, stems: .zero)
                enc.setFragmentBuffer(ns.stateBuffer, offset: 0, index: 6)
            } else {
                enc.setFragmentBuffer(slot, offset: 0, index: 6)
            }
            enc.setFragmentBuffer(slot, offset: 0, index: 7)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            guard cmdBuf.status == .completed else { throw FlashGateError.renderFailed }
            texture.getBytes(&pixels, bytesPerRow: size * 4,
                             from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
            luma.append(FlashHarnessSupport.meanRelativeLuminance(pixels))
        }
        return luma
    }

    private enum FlashGateError: Error {
        case textureAllocationFailed
        case bufferAllocationFailed
        case commandBufferFailed
        case encoderCreationFailed
        case renderFailed
    }
}
