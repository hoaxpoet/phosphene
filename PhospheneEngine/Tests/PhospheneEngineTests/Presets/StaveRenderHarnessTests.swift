// StaveRenderHarnessTests — Stave's production-path multi-frame harness (CHR.3).
//
// The checklist obligation, not an optional extra: "every preset increment that depends on
// temporal behaviour must include a test running the same dispatch path the live app uses."
// Stave's whole subject is an 8 s scrolling history ring, so a single `preset.pipelineState`
// draw shows a frame with no trace in it at all — the exact class of test that let three
// Aurora Veil increments ship green while smearing live.
//
// Dispatch path exercised — `RenderPipeline.drawParticleMode`, verbatim in structure:
// ONE render encoder per frame, cleared, with the preset's own `pipelineState` drawing the
// field triangle (features at 0, fft at 1, waveform at 2, stems at 3, spectral history at 5)
// and then `ParticleGeometry.render` drawing into the SAME encoder. There is no feedback
// accumulator on this path — particle mode clears every frame — which is why the trace's
// smear is the history ring's own age-faded tail rather than an accumulator.
//
// Two entry points:
//   * `staveParticlePath_silenceIsStableAndNonBlack` — default suite, silence, D-037 floor
//     plus the L5 "quiet passages flatline" property. No env gate: it is cheap and it is the
//     regression that matters.
//   * `renderStaveSequence` — env-gated on a real capture, the frames a human reads:
//       STAVE_RENDER_SESSION=<session-or-slice-dir> STAVE_RENDER_OUT=/tmp/... \
//       swift test --package-path PhospheneEngine --filter StaveRenderHarness

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("StaveRenderHarness")
@MainActor
struct StaveRenderHarnessTests {

    private static let presetName = "Stave"

    // MARK: - Shared frame driver

    /// One frame of the production particle-mode path. Returns the drawable-format pixels.
    private static func renderFrame(
        ctx: MetalContext,
        preset: PresetLoader.LoadedPreset,
        geometry: StaveTrace,
        buffers: HarnessTemplateCore.SilenceBuffers,
        texture: MTLTexture,
        features: inout FeatureVector,
        stems: StemFeatures,
        width: Int,
        height: Int
    ) throws -> [UInt8] {
        guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
            throw HarnessError.commandBufferFailed
        }
        // The CPU tick goes through the protocol's own `update` seam — the same call
        // `RenderPipeline.renderFrame` makes — so the harness cannot drift from production
        // by ticking some private method instead.
        geometry.update(features: features, stemFeatures: stems, commandBuffer: cmd)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = cmd.makeRenderCommandEncoder(descriptor: pass) else {
            throw HarnessError.renderFailed
        }
        encoder.setRenderPipelineState(preset.pipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        encoder.setFragmentBuffer(buffers.fft, offset: 0, index: 1)
        encoder.setFragmentBuffer(buffers.waveform, offset: 0, index: 2)
        var stemCopy = stems
        encoder.setFragmentBytes(&stemCopy, length: MemoryLayout<StemFeatures>.size, index: 3)
        encoder.setFragmentBuffer(buffers.history, offset: 0, index: 5)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        geometry.render(encoder: encoder, features: features)
        encoder.endEncoding()

        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { throw HarnessError.renderFailed }
        return HarnessTemplateCore.readBGRA(texture, width: width, height: height)
    }

    private static func makeSubject(_ ctx: MetalContext) throws
        -> (PresetLoader.LoadedPreset, StaveTrace, HarnessTemplateCore.SilenceBuffers) {
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == presetName }) else {
            throw HarnessError.presetNotFound(presetName)
        }
        let geometry = try StaveTrace(device: ctx.device, library: lib.library,
                                      configuration: StaveConfiguration(),
                                      pixelFormat: ctx.pixelFormat)
        return (preset, geometry, try HarnessTemplateCore.makeSilenceBuffers(ctx))
    }

    // MARK: - Silence regression (default suite)

    @Test("particle-path silence: field persists, never black, traces flatline (D-037 / L5)")
    func staveParticlePath_silenceIsStableAndNonBlack() throws {
        let width = 256, height = 256
        let ctx = try MetalContext()
        let (preset, geometry, buffers) = try Self.makeSubject(ctx)
        let texture = try HarnessTemplateCore.makeCaptureTexture(ctx, width: width, height: height)

        var first: [UInt8] = []
        var last: [UInt8] = []
        for i in 0..<90 {
            var features = HarnessTemplateCore.silenceFeature(frame: i)
            features.aspectRatio = Float(width) / Float(height)
            let pixels = try Self.renderFrame(
                ctx: ctx, preset: preset, geometry: geometry, buffers: buffers,
                texture: texture, features: &features, stems: .zero,
                width: width, height: height)
            if i == 0 { first = pixels }
            if i == 89 { last = pixels }
        }

        // D-037: silence renders the field, not black. The floor in `stave_field_fragment`
        // is (0.012, 0.014, 0.022) linear, so every pixel must clear a small non-zero bar.
        let darkest = stride(from: 0, to: last.count, by: 4).map { max(last[$0], max(last[$0 + 1], last[$0 + 2])) }.min() ?? 0
        #expect(darkest > 2, "silence frame has a fully black pixel — D-037 floor breached")

        // The field is structured, not a flat plate (haze, cloud, rules, sparkles).
        #expect(HarnessTemplateCore.isNonConstant(last), "silence frame is a constant colour")

        // L5 — no autonomous TRACE motion. The atmosphere drifts very slowly, so the frame is
        // not frozen, but it must not be churning either: a quiet passage flatlining IS the
        // design, and this is what would catch someone adding ambient motion "so it isn't
        // boring" (the failure this source was chosen to avoid).
        var diff = 0
        for i in stride(from: 0, to: min(first.count, last.count), by: 4) where
            abs(Int(first[i]) - Int(last[i])) > 12 { diff += 1 }
        let churn = Float(diff) / Float(width * height)
        #expect(churn < 0.35, "silence churn \(churn) — the field is animating on its own (L5)")
    }

    // MARK: - Real-capture sequence (env-gated)

    @Test("render a Stave sequence from a recorded session (STAVE_RENDER_SESSION=…)")
    func renderStaveSequence() throws {
        let env = ProcessInfo.processInfo.environment
        guard let sessionPath = env["STAVE_RENDER_SESSION"] else {
            print("[stave] STAVE_RENDER_SESSION not set — skipping")
            return
        }
        let width = Int(env["STAVE_RENDER_W"] ?? "") ?? 1067
        let height = Int(env["STAVE_RENDER_H"] ?? "") ?? 750
        let stride = Int(env["STAVE_RENDER_STRIDE"] ?? "") ?? 3
        let count = Int(env["STAVE_RENDER_COUNT"] ?? "") ?? 180
        let warmup = Int(env["STAVE_RENDER_WARMUP"] ?? "") ?? 1200
        let outDir = URL(fileURLWithPath: env["STAVE_RENDER_OUT"]
                         ?? NSTemporaryDirectory().appending("stave_render"))

        let aspect = Float(width) / Float(height)
        let frames = StaveReplay.load(session: URL(fileURLWithPath: sessionPath), aspect: aspect)
        guard frames.count > warmup else {
            Issue.record("only \(frames.count) frames parsed from \(sessionPath), need > \(warmup)")
            return
        }
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let ctx = try MetalContext()
        let (preset, geometry, buffers) = try Self.makeSubject(ctx)
        let texture = try HarnessTemplateCore.makeCaptureTexture(ctx, width: width, height: height)

        var written = 0
        var tintTrack: [Float] = []
        for (i, frame) in frames.enumerated() {
            var features = frame.features
            // Warm the band EMAs and fill the 8 s window before capturing, then capture every
            // `stride`-th frame so the sequence covers real musical time.
            guard i >= warmup, (i - warmup) % stride == 0, written < count else {
                geometry.advance(features: features, stems: frame.stems)
                continue
            }
            let pixels = try Self.renderFrame(
                ctx: ctx, preset: preset, geometry: geometry, buffers: buffers,
                texture: texture, features: &features, stems: frame.stems,
                width: width, height: height)
            try StaveFieldTintSpike.writePNG(
                bgra: pixels, width: width, height: height,
                to: outDir.appendingPathComponent(String(format: "stave_seq_%04d.png", written)))
            tintTrack.append(geometry.fieldTint)
            written += 1
        }
        let minTint = tintTrack.min() ?? 0
        let maxTint = tintTrack.max() ?? 0
        print("[stave] wrote \(written) frames to \(outDir.path)")
        print("[stave] field tint over the sequence: \(String(format: "%.2f..%.2f", minTint, maxTint))")
        print("[stave] rules on screen at the end: \(Int(geometry.ruleDensity))")
    }
}
