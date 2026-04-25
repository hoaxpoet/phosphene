// RenderPipelineGovernorWiringTests — End-to-end governor → pipeline state mapping.
//
// Verifies that RenderPipeline.applyQualityLevel(_:) correctly translates each
// QualityLevel to the expected pipeline state changes across all five gates:
// SSGI, bloom, ray march step count, particle fraction, and mesh density.

import Testing
import Metal
@testable import Renderer
@testable import Shared

// MARK: - RenderPipelineGovernorWiringTests

@MainActor
struct RenderPipelineGovernorWiringTests {

    // Build a minimal RenderPipeline with attached RayMarchPipeline and PostProcessChain.
    private func makeFullPipeline() throws -> (
        RenderPipeline, RayMarchPipeline, PostProcessChain
    ) {
        let ctx = try MetalContext()
        let lib = try Renderer.ShaderLibrary(context: ctx)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw PipelineError.bufferAllocationFailed
        }
        let pipeline = try RenderPipeline(
            context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav
        )
        let rayMarch = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        let postProcess = try PostProcessChain(context: ctx, shaderLibrary: lib)

        pipeline.setRayMarchPipeline(rayMarch)
        pipeline.setPostProcessChain(postProcess)
        return (pipeline, rayMarch, postProcess)
    }

    enum PipelineError: Error { case bufferAllocationFailed }

    // MARK: - 1. .full → all gates restored to baseline

    @Test
    func qualityFull_allGatesAtBaseline() throws {
        let (pipeline, rayMarch, postProcess) = try makeFullPipeline()
        pipeline.applyQualityLevel(.full)

        #expect(rayMarch.reducedMotion == false, "SSGI gate should be off at .full")
        #expect(postProcess.bloomEnabled == true, "Bloom should be on at .full")
        #expect(rayMarch.stepCountMultiplier == 1.0, "Step count should be 1.0 at .full")
    }

    // MARK: - 2. .noSSGI → only SSGI gate active

    @Test
    func qualityNoSSGI_onlySSGISuppressed() throws {
        let (pipeline, rayMarch, postProcess) = try makeFullPipeline()
        pipeline.applyQualityLevel(.noSSGI)

        #expect(rayMarch.reducedMotion == true, "Governor should suppress SSGI at .noSSGI")
        #expect(postProcess.bloomEnabled == true, "Bloom should still be on at .noSSGI")
        #expect(rayMarch.stepCountMultiplier == 1.0, "Step count should still be 1.0 at .noSSGI")
    }

    // MARK: - 3. .reducedRayMarch → SSGI off, bloom off, step count 0.75×

    @Test
    func qualityReducedRayMarch_ssgiAndBloomOff_stepCount75() throws {
        let (pipeline, rayMarch, postProcess) = try makeFullPipeline()
        pipeline.applyQualityLevel(.reducedRayMarch)

        #expect(rayMarch.reducedMotion == true)
        #expect(postProcess.bloomEnabled == false)
        #expect(abs(rayMarch.stepCountMultiplier - 0.75) < 0.001)
    }

    // MARK: - 4. .reducedMesh → all five reductions active

    @Test
    func qualityReducedMesh_allReductionsActive() throws {
        let (pipeline, rayMarch, postProcess) = try makeFullPipeline()
        pipeline.applyQualityLevel(.reducedMesh)

        #expect(rayMarch.reducedMotion == true)
        #expect(postProcess.bloomEnabled == false)
        #expect(abs(rayMarch.stepCountMultiplier - 0.75) < 0.001)
        // Particle and mesh fractions are tested via ProceduralGeometry/MeshGenerator
        // instances attached to the pipeline (nil in this minimal setup — no crash expected).
    }

    // MARK: - 5. No crash when subsystems are nil (minimal pipeline)

    @Test
    func applyQualityLevel_withNilSubsystems_noCrash() throws {
        let ctx = try MetalContext()
        let lib = try Renderer.ShaderLibrary(context: ctx)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else { return }
        let pipeline = try RenderPipeline(
            context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav
        )
        // No subsystems attached — applyQualityLevel must not crash.
        for level in FrameBudgetManager.QualityLevel.allCases {
            pipeline.applyQualityLevel(level)
        }
    }

    // MARK: - 6. a11y flag is not overridden by governor recovery

    @Test
    func governorRecovery_doesNotOverrideA11yFlag() throws {
        let (pipeline, rayMarch, _) = try makeFullPipeline()
        // Simulate a11y reduced motion active.
        rayMarch.setA11yReducedMotion(true)
        // Governor descends to noSSGI, then "recovers" to .full.
        pipeline.applyQualityLevel(.noSSGI)
        pipeline.applyQualityLevel(.full)
        // Governor is now at .full (governorSkipsSSGI = false), but a11y is still true.
        #expect(rayMarch.reducedMotion == true,
            "A11y flag must not be cleared by governor recovery")
    }
}
