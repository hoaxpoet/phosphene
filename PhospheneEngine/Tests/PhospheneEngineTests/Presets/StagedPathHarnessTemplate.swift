// StagedPathHarnessTemplate — reference multi-frame harness for the `staged`
// paradigm (QG.4, Task 2). Copy-adapt this for any new staged-composition preset.
//
// Dispatch path exercised (the same one `RenderPipeline.drawWithStaged` runs, minus
// the MTKView present): for each non-final stage, render into its named offscreen
// texture; then the final stage renders sampling the earlier stages at texture(13)+.
// Every stage goes through the PRODUCTION `encodeStage` encoder, so the per-preset
// fragment buffers land on their real slots — slot 6 / slot 7 / slot 8 (Arachne:
// web pool at 6, spider GPU at 7; Lumen-style follower at 8).
//
//   subject: Arachne  —  world (rgba16Float) → composite (drawable, samples world)
//
// Metric: each stage's output is non-degenerate (non-constant + non-NaN) at silence,
// and the final composite's 64-bit dHash matches a golden. The golden is what makes a
// mis-bound slot detectable — a wrong slot-6/7 binding changes the composite and trips
// the Hamming gate (A/B validated in QG.4: temporarily binding the spider buffer to
// slot 6 flipped the test RED, then restored).
//
// GPU test — env-gated `HARNESS_TEMPLATES=1`, NOT in the default parallel run.

import Testing
import Foundation
import Metal
import simd
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - StagedPathHarnessTemplate

@Suite("Staged path harness template (env-gated, QG.4)")
@MainActor
struct StagedPathHarnessTemplate {

    private static let width = 256
    private static let height = 256
    private static let frameCount = 60
    private static let subjectName = "Arachne"

    /// Golden dHash of the final composite on the last silence frame. 0 ⇒ bootstrap
    /// (print + pass). Hardware-specific (D-039): Apple Silicon, macOS 14+.
    private static let goldenCompositeHash: UInt64 = 0x0F0F070703818100

    @Test("staged dispatch (world → composite) is non-degenerate and matches golden")
    func stagedPath_nonDegenerate() throws {
        guard HarnessTemplateCore.isEnabled else {
            print("StagedPathHarnessTemplate: HARNESS_TEMPLATES not set, skipping")
            return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == Self.subjectName }) else {
            throw HarnessError.presetNotFound(Self.subjectName)
        }
        guard !preset.descriptor.passes.contains(.meshShader) else {
            print("StagedPathHarnessTemplate: \(Self.subjectName) is mesh-shader — cannot drive via drawPrimitives")
            return
        }
        guard !preset.stages.isEmpty else {
            throw HarnessError.setupFailed("\(Self.subjectName) has no staged stages")
        }

        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib,
                                          fftBuffer: buffers.fft, waveformBuffer: buffers.waveform)

        // Arachne's world-state → slot 6 (web pool) + slot 7 (spider). Mirror the app:
        // reset() seeds the polygon anchors; a short silence warmup settles the pool.
        guard let state = ArachneState(device: ctx.device, seed: 42) else {
            throw HarnessError.setupFailed("ArachneState allocation")
        }
        state.reset()
        for i in 0..<30 { state.tick(features: HarnessTemplateCore.silenceFeature(frame: i), stems: .zero) }
        pipeline.setDirectPresetFragmentBuffer(state.webBuffer)     // slot 6
        pipeline.setDirectPresetFragmentBuffer2(state.spiderBuffer) // slot 7

        // Build the production stage specs + our own readable capture textures.
        // Non-final stages: rgba16Float (the format their pipelines were compiled for).
        // Final stage: the drawable format.
        var stageTextures: [String: MTLTexture] = [:]
        var specs: [StagedStageSpec] = []
        for stage in preset.stages {
            let format: MTLPixelFormat = stage.writesToDrawable ? ctx.pixelFormat : .rgba16Float
            stageTextures[stage.name] = try HarnessTemplateCore.makeCaptureTexture(
                ctx, width: Self.width, height: Self.height, pixelFormat: format)
            specs.append(StagedStageSpec(name: stage.name, pipelineState: stage.pipelineState,
                                         samples: stage.samples, writesToDrawable: stage.writesToDrawable))
        }
        guard let finalSpec = specs.last, finalSpec.writesToDrawable,
              let finalTex = stageTextures[finalSpec.name] else {
            throw HarnessError.setupFailed("staged final stage must write to drawable")
        }

        for i in 0..<Self.frameCount {
            var features = HarnessTemplateCore.silenceFeature(frame: i)
            state.tick(features: features, stems: .zero)
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw HarnessError.commandBufferFailed }
            for spec in specs {
                guard let target = stageTextures[spec.name] else { continue }
                let desc = MTLRenderPassDescriptor()
                desc.colorAttachments[0].texture = target
                desc.colorAttachments[0].loadAction = .clear
                desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                desc.colorAttachments[0].storeAction = .store
                guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else {
                    throw HarnessError.encoderCreationFailed
                }
                pipeline.encodeStage(stage: spec, encoder: enc, features: &features,
                                     stemFeatures: .zero, textures: stageTextures)
                enc.endEncoding()
            }
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw HarnessError.renderFailed }
        }

        // ── Per-stage non-degeneracy (final frame) ──
        for stage in preset.stages where !stage.writesToDrawable {
            let bytes = HarnessTemplateCore.readHalf(stageTextures[stage.name]!, width: Self.width, height: Self.height)
            let s = HarnessTemplateCore.halfStats(bytes)
            #expect(!s.hasNaN, "staged stage '\(stage.name)' produced NaN")
            #expect(s.nonConstant, "staged stage '\(stage.name)' is constant (degenerate) at silence")
            #expect(s.maxMagnitude > 0, "staged stage '\(stage.name)' wrote no signal")
        }
        let composite = HarnessTemplateCore.readBGRA(finalTex, width: Self.width, height: Self.height)
        #expect(HarnessTemplateCore.isNonConstant(composite), "staged composite is constant (degenerate) at silence")
        let hash = HarnessTemplateCore.dHash(composite, width: Self.width, height: Self.height)

        print(String(format: "[staged-template] %@: composite dHash 0x%016llX | meanLuma %.4f maxLuma %.4f",
                     Self.subjectName, hash, HarnessTemplateCore.meanLuma(composite), HarnessTemplateCore.maxLuma(composite)))

        if Self.goldenCompositeHash == 0 {
            print("[staged-template] bootstrap — no golden set; paste 0x\(String(hash, radix: 16, uppercase: true))")
            return
        }
        let hd = HarnessTemplateCore.hamming(hash, Self.goldenCompositeHash)
        #expect(hd <= 8, """
            staged composite hash drifted \(hd) bits from golden — a mis-bound stage slot or \
            a broken stage walk. got=0x\(String(hash, radix: 16, uppercase: true)) \
            golden=0x\(String(Self.goldenCompositeHash, radix: 16, uppercase: true))
            """)
    }
}
