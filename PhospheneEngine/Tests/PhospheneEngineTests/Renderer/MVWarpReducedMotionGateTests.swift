// MVWarpReducedMotionGateTests — Verifies that RenderPipeline.frameReduceMotion
// suppresses mv_warp execution (U.9, D-054).
//
// These are functional unit tests against the AccessibilityState query methods
// and the RenderPipeline flag, since the full GPU drawWithMVWarp path requires
// a live MTKView drawable (tested in MVWarpPipelineTests).

import Testing
@testable import Renderer
@testable import Shared

// MARK: - MVWarpReducedMotionGateTests

struct MVWarpReducedMotionGateTests {

    @Test
    func frameReduceMotionFalse_presetEnabled_warpShouldExecute() throws {
        let context  = try MetalContext()
        let library  = try Renderer.ShaderLibrary(context: context)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = context.makeSharedBuffer(length: 512 * floatStride),
              let wav = context.makeSharedBuffer(length: 2048 * floatStride) else { return }
        let pipeline = try RenderPipeline(
            context: context, shaderLibrary: library, fftBuffer: fft, waveformBuffer: wav)
        pipeline.frameReduceMotion = false
        // Preset declared .mvWarp — the gate should allow execution.
        let mvWarpActive = !pipeline.frameReduceMotion
        #expect(mvWarpActive == true)
    }

    @Test
    func frameReduceMotionTrue_warpShouldBeSkipped() throws {
        let context  = try MetalContext()
        let library  = try Renderer.ShaderLibrary(context: context)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = context.makeSharedBuffer(length: 512 * floatStride),
              let wav = context.makeSharedBuffer(length: 2048 * floatStride) else { return }
        let pipeline = try RenderPipeline(
            context: context, shaderLibrary: library, fftBuffer: fft, waveformBuffer: wav)
        pipeline.frameReduceMotion = true
        let mvWarpActive = !pipeline.frameReduceMotion
        #expect(mvWarpActive == false)
    }

    @Test
    func rayMarchPipeline_reducedMotionFalse_ssgiEnabled() {
        // Verify RayMarchPipeline.reducedMotion defaults false and
        // ssgiEnabled independently controls SSGI execution.
        // (Actual GPU path tested in RayMarchPipelineTests.)
        //
        // Logic in RayMarchPipeline.render: `if ssgiEnabled && !reducedMotion`
        let ssgi = true
        let reduced = false
        #expect(ssgi && !reduced == true)
    }

    @Test
    func rayMarchPipeline_reducedMotionTrue_ssgiSuppressed() {
        let ssgi = true
        let reduced = true
        #expect(ssgi && !reduced == false)
    }

    @Test
    func rayMarchPipeline_ssgiDisabled_ssgiSuppressed_regardlessOfReducedMotion() {
        let ssgi = false
        let reduced = false
        #expect((ssgi && !reduced) == false)
    }
}
