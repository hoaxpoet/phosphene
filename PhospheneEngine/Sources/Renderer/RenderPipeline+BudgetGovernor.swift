// RenderPipeline+BudgetGovernor — Quality-level gate application (D-057).
//
// Translates FrameBudgetManager.QualityLevel into scalar attenuation across
// five subsystems. The governor never modifies activePasses — it only
// attenuates work within existing passes.

import Metal
import Shared

extension RenderPipeline {

    // MARK: - Quality Level Application

    /// Apply a governor quality level to all five subsystem gates.
    ///
    /// Each level is a strict superset of reductions from the level above it.
    /// Called from the @MainActor completed-handler hop — one frame behind the
    /// measured frame.
    @MainActor
    func applyQualityLevel(_ level: FrameBudgetManager.QualityLevel) {
        let ssgiOff = level >= .noSSGI
        rayMarchLock.withLock { rayMarchPipeline }?.setGovernorSkipsSSGI(ssgiOff)

        let bloomOff = level >= .noBloom
        postProcessLock.withLock { postProcessChain }?.bloomEnabled = !bloomOff

        let stepMult: Float = level >= .reducedRayMarch ? 0.75 : 1.0
        rayMarchLock.withLock { rayMarchPipeline }?.stepCountMultiplier = stepMult

        let particleFraction: Float = level >= .reducedParticles ? 0.5 : 1.0
        particleLock.withLock { particleGeometry }?.activeParticleFraction = particleFraction

        // No-op on M1/M2 vertex fallback — D-057(e).
        let meshDensity: Float = level >= .reducedMesh ? 0.5 : 1.0
        meshLock.withLock { meshGenerator }?.densityMultiplier = meshDensity
    }
}
