// DrawableResizeRegressionTests — Verifies that mtkView(_:drawableSizeWillChange:) correctly
// reallocates feedback and warp textures (Increment 7.2, D-061(a)).
//
// Hot-plug display events trigger drawableSizeWillChange when the window reparents onto
// a different display. These tests guard against:
//  · Feedback textures left at the old size (torn frames) — for presets that sample them.
//  · mv_warp textures left at the old size (D-027 feedback smear).
//  · currentDrawableSize stale after reparent.
//
// CLEAN.4.4: the feedback ping-pong is only allocated for presets that actually sample
// it (surface-mode feedback, e.g. Membrane). A non-feedback preset, or a particle-mode
// feedback preset (Murmuration, which draws straight to the drawable), allocates none —
// these tests pin that gate via `setFeedbackParams` / `setParticleGeometry`.

import Testing
import Metal
import MetalKit
@testable import Renderer
@testable import Shared

// MARK: - DrawableResizeRegressionTests

@Suite("DrawableResizeRegression")
@MainActor
struct DrawableResizeRegressionTests {

    private func makePipeline() throws -> (RenderPipeline, MetalContext) {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let fftBuf = ctx.makeSharedBuffer(length: 512 * MemoryLayout<Float>.stride)!
        let wavBuf = ctx.makeSharedBuffer(length: 2048 * MemoryLayout<Float>.stride)!
        let pipeline = try RenderPipeline(
            context: ctx,
            shaderLibrary: lib,
            fftBuffer: fftBuf,
            waveformBuffer: wavBuf
        )
        return (pipeline, ctx)
    }

    @Test("drawableSizeWillChange allocates two feedback textures for a surface-feedback preset")
    func test_drawableSizeWillChange_surfaceFeedback_allocatesTextures() throws {
        let (pipeline, ctx) = try makePipeline()
        let view = MTKView(frame: .zero, device: ctx.device)
        let newSize = CGSize(width: 1920, height: 1080)

        // Surface-mode feedback preset: params set, no particles.
        pipeline.setFeedbackParams(FeedbackParams())
        pipeline.mtkView(view, drawableSizeWillChange: newSize)

        // Two feedback textures (ping-pong) must exist and match the requested size.
        #expect(pipeline.feedbackTextures.count == 2)
        for tex in pipeline.feedbackTextures {
            #expect(tex.width == Int(newSize.width))
            #expect(tex.height == Int(newSize.height))
        }
    }

    // CLEAN.4.4: a non-feedback preset (no params) allocates ZERO feedback textures
    // on resize — the core "no wasted alloc" done-when. RED before the gate (the old
    // handler allocated unconditionally), GREEN after.
    @Test("drawableSizeWillChange allocates no feedback textures for a non-feedback preset")
    func test_drawableSizeWillChange_nonFeedbackPreset_allocatesZeroFeedbackTextures() throws {
        let (pipeline, ctx) = try makePipeline()
        let view = MTKView(frame: .zero, device: ctx.device)

        // No feedback params set — the default state for ~18 of 20 presets.
        pipeline.mtkView(view, drawableSizeWillChange: CGSize(width: 3840, height: 2160))

        #expect(pipeline.feedbackTextures.isEmpty)
    }

    // CLEAN.4.4: a particle-mode feedback preset (Murmuration) draws straight to the
    // drawable and never samples the ping-pong → zero feedback textures even with params.
    @Test("drawableSizeWillChange allocates no feedback textures for a particle-mode preset")
    func test_drawableSizeWillChange_particleMode_allocatesZeroFeedbackTextures() throws {
        let (pipeline, ctx) = try makePipeline()
        let view = MTKView(frame: .zero, device: ctx.device)

        pipeline.setFeedbackParams(FeedbackParams())
        pipeline.setParticleGeometry(NoOpParticleGeometry())
        pipeline.mtkView(view, drawableSizeWillChange: CGSize(width: 3840, height: 2160))

        #expect(pipeline.feedbackTextures.isEmpty)
    }

    // CLEAN.4.4: switching away from a feedback preset (setFeedbackParams(nil)) releases
    // the ping-pong — it must not stay resident (~32 MB @ 4K) for the rest of the session.
    @Test("setFeedbackParams(nil) releases the ping-pong textures")
    func test_setFeedbackParamsNil_releasesPingPong() throws {
        let (pipeline, ctx) = try makePipeline()
        let view = MTKView(frame: .zero, device: ctx.device)

        pipeline.setFeedbackParams(FeedbackParams())
        pipeline.mtkView(view, drawableSizeWillChange: CGSize(width: 1920, height: 1080))
        #expect(pipeline.feedbackTextures.count == 2)

        pipeline.setFeedbackParams(nil)   // switch to a non-feedback preset
        #expect(pipeline.feedbackTextures.isEmpty)
    }

    @Test("drawableSizeWillChange updates mvWarpDrawableSize")
    func test_drawableSizeWillChange_updatesMVWarpDrawableSize() throws {
        let (pipeline, ctx) = try makePipeline()
        let view = MTKView(frame: .zero, device: ctx.device)
        let newSize = CGSize(width: 2560, height: 1440)

        pipeline.mtkView(view, drawableSizeWillChange: newSize)

        #expect(pipeline.mvWarpDrawableSize == newSize)
    }

    @Test("second drawableSizeWillChange replaces textures from the first call")
    func test_drawableSizeWillChange_secondResize_replacesFirst() throws {
        let (pipeline, ctx) = try makePipeline()
        let view = MTKView(frame: .zero, device: ctx.device)
        pipeline.setFeedbackParams(FeedbackParams())   // surface-feedback preset

        // Simulate Retina→non-Retina transition: first a large size, then a smaller one.
        pipeline.mtkView(view, drawableSizeWillChange: CGSize(width: 3840, height: 2160))
        pipeline.mtkView(view, drawableSizeWillChange: CGSize(width: 1920, height: 1080))

        // After the second resize the textures must reflect the final size, not the first.
        #expect(pipeline.feedbackTextures.count == 2)
        for tex in pipeline.feedbackTextures {
            #expect(tex.width  == 1920)
            #expect(tex.height == 1080)
        }
        #expect(pipeline.mvWarpDrawableSize == CGSize(width: 1920, height: 1080))
    }
}

// MARK: - Test Double

/// Minimal no-op `ParticleGeometry` — makes `particleGeometry != nil` so the pipeline
/// reports particle mode. Its compute/render methods are never invoked by the resize
/// path under test (CLEAN.4.4).
private final class NoOpParticleGeometry: ParticleGeometry, @unchecked Sendable {
    var activeParticleFraction: Float = 1.0
    func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {}
    func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {}
}
