// FrameBudgetManagerResetOnPresetChangeTests — Single-purpose integration tests
// verifying that the frame-budget governor resets to .full on preset change.
//
// The governor must start optimistic on each new preset — new presets have
// unknown cost characteristics. D-057(e).

import Testing
import Metal
@testable import Renderer
@testable import Shared

// MARK: - FrameBudgetManagerResetOnPresetChangeTests

struct FrameBudgetManagerResetOnPresetChangeTests {

    // Drive the governor into a degraded state, then trigger the reset path.
    private func makeGovernorAtReducedRayMarch() -> FrameBudgetManager {
        let cfg = FrameBudgetManager.Configuration(
            targetFrameMs: 16.0,
            overrunMarginMs: 0.5,
            consecutiveOverrunsToDownshift: 3,
            sustainedRecoveryFrames: 180,
            sustainedRecoveryHeadroomMs: 1.5,
            enabled: true
        )
        let mgr = FrameBudgetManager(configuration: cfg)
        // Downshift to .reducedRayMarch (3 overruns × 3 levels = 9 overrun frames).
        for _ in 0..<9 { mgr.observe(.init(cpuFrameMs: 25.0, gpuFrameMs: nil)) }
        return mgr
    }

    // MARK: - 1. reset() from .reducedRayMarch → .full immediately

    @Test
    func reset_fromReducedRayMarch_returnsToFull() {
        let mgr = makeGovernorAtReducedRayMarch()
        #expect(mgr.currentLevel == .reducedRayMarch)
        mgr.reset()
        #expect(mgr.currentLevel == .full,
            "reset() must return governor to .full immediately on preset change")
    }

    // MARK: - 2. After reset(), governor starts accumulating fresh

    @Test
    func afterReset_governorAccumulatesFresh() {
        let mgr = makeGovernorAtReducedRayMarch()
        mgr.reset()
        // Only 2 overruns after reset — should NOT downshift (need 3).
        mgr.observe(.init(cpuFrameMs: 25.0, gpuFrameMs: nil))
        mgr.observe(.init(cpuFrameMs: 25.0, gpuFrameMs: nil))
        #expect(mgr.currentLevel == .full,
            "Counter should have been zeroed by reset — 2 overruns must not downshift")
    }

    // MARK: - 3. nil frameBudgetManager on RenderPipeline — preset apply succeeds

    @MainActor
    @Test
    func nilFrameBudgetManager_presetApplyNoCrash() throws {
        let ctx = try MetalContext()
        let lib = try Renderer.ShaderLibrary(context: ctx)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else { return }
        let pipeline = try RenderPipeline(
            context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav
        )
        // Ensure no manager is set — reset call must be a no-op.
        pipeline.frameBudgetManager = nil
        // Calling applyQualityLevel when manager is nil must not crash.
        pipeline.applyQualityLevel(.reducedMesh)
        // All good if we reach here.
    }
}
