// RayMarchPipelineGovernorIntegrationTests — Tests the OR-gate refactor for
// RayMarchPipeline.reducedMotion (D-054, D-057).
//
// Verifies that a11yReducedMotion and governorSkipsSSGI are independently gated,
// that a11y always wins over governor recovery, and that the public reducedMotion
// computed property correctly reflects the OR of both flags.

import Testing
@testable import Renderer
@testable import Shared

// MARK: - RayMarchPipelineGovernorIntegrationTests

struct RayMarchPipelineGovernorIntegrationTests {

    private func makePipeline() throws -> RayMarchPipeline {
        let ctx = try MetalContext()
        let lib = try Renderer.ShaderLibrary(context: ctx)
        return try RayMarchPipeline(context: ctx, shaderLibrary: lib)
    }

    // MARK: - 1. setA11yReducedMotion preserves existing behavior

    @Test
    func a11yReducedMotionTrue_reducedMotionIsTrue() throws {
        let pipeline = try makePipeline()
        pipeline.setA11yReducedMotion(true)
        #expect(pipeline.reducedMotion == true)
    }

    @Test
    func a11yReducedMotionFalse_governorAlsoFalse_reducedMotionIsFalse() throws {
        let pipeline = try makePipeline()
        pipeline.setA11yReducedMotion(false)
        #expect(pipeline.reducedMotion == false)
    }

    // MARK: - 2. setGovernorSkipsSSGI alone drives reducedMotion

    @Test
    func governorSkipsSSGITrue_reducedMotionIsTrue() throws {
        let pipeline = try makePipeline()
        pipeline.setGovernorSkipsSSGI(true)
        #expect(pipeline.reducedMotion == true)
    }

    @Test
    func governorSkipsSSGIFalse_reducedMotionIsFalse() throws {
        let pipeline = try makePipeline()
        pipeline.setGovernorSkipsSSGI(false)
        #expect(pipeline.reducedMotion == false)
    }

    // MARK: - 3. OR-gate: a11y wins when governor recovers

    @Test
    func a11yTrue_governorRecoveres_reducedMotionStaysTrue() throws {
        let pipeline = try makePipeline()
        pipeline.setA11yReducedMotion(true)
        pipeline.setGovernorSkipsSSGI(true)
        // Governor "recovers" — sets its flag back to false.
        pipeline.setGovernorSkipsSSGI(false)
        // A11y flag is still true — SSGI must remain suppressed.
        #expect(pipeline.reducedMotion == true,
            "A11y wins: governor recovery must not re-enable SSGI when a11y is still active")
    }

    // MARK: - 4. Both false → reducedMotion false

    @Test
    func bothFalse_reducedMotionIsFalse() throws {
        let pipeline = try makePipeline()
        pipeline.setA11yReducedMotion(false)
        pipeline.setGovernorSkipsSSGI(false)
        #expect(pipeline.reducedMotion == false)
    }

    // MARK: - 5. Default state — reducedMotion false (regression guard)

    @Test
    func defaultState_reducedMotionIsFalse() throws {
        let pipeline = try makePipeline()
        // Neither flag set — default must be false to preserve D-054 baseline.
        #expect(pipeline.reducedMotion == false)
    }
}
