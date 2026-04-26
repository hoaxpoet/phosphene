// DrawableResizeRegressionTests — Verifies that mtkView(_:drawableSizeWillChange:) correctly
// reallocates feedback and warp textures (Increment 7.2, D-061(a)).
//
// Hot-plug display events trigger drawableSizeWillChange when the window reparents onto
// a different display. These tests guard against:
//  · Feedback textures left at the old size (torn frames).
//  · mv_warp textures left at the old size (D-027 feedback smear).
//  · currentDrawableSize stale after reparent.

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

    @Test("drawableSizeWillChange allocates two feedback textures at the new size")
    func test_drawableSizeWillChange_allocatesFeedbackTextures() throws {
        let (pipeline, ctx) = try makePipeline()
        let view = MTKView(frame: .zero, device: ctx.device)
        let newSize = CGSize(width: 1920, height: 1080)

        pipeline.mtkView(view, drawableSizeWillChange: newSize)

        // Two feedback textures (ping-pong) must exist and match the requested size.
        #expect(pipeline.feedbackTextures.count == 2)
        for tex in pipeline.feedbackTextures {
            #expect(tex.width == Int(newSize.width))
            #expect(tex.height == Int(newSize.height))
        }
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
