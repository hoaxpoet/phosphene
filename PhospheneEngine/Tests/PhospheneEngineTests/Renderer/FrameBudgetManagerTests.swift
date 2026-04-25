// FrameBudgetManagerTests — Pure-state controller tests for the frame budget governor.
//
// All tests use synthetic timing sequences — no real GPU required.
// Covers: steady frames, single spikes, consecutive overruns, hysteresis, recovery,
// floor/ceiling clamping, enabled=false no-op, gpu fallback, reset, tier config,
// Comparable ordering on QualityLevel.

import Testing
@testable import Renderer
@testable import Shared

// MARK: - FrameBudgetManagerTests

struct FrameBudgetManagerTests {

    // Shared tight-budget config: downshifts after 3 overruns at 16 ms target.
    private func makeManager(
        targetMs: Float = 16.0,
        marginMs: Float = 0.5,
        overrunsNeeded: Int = 3,
        recoveryFrames: Int = 180,
        recoveryHeadroomMs: Float = 1.5,
        enabled: Bool = true
    ) -> FrameBudgetManager {
        let cfg = FrameBudgetManager.Configuration(
            targetFrameMs: targetMs,
            overrunMarginMs: marginMs,
            consecutiveOverrunsToDownshift: overrunsNeeded,
            sustainedRecoveryFrames: recoveryFrames,
            sustainedRecoveryHeadroomMs: recoveryHeadroomMs,
            enabled: enabled
        )
        return FrameBudgetManager(configuration: cfg)
    }

    private func observe(_ mgr: FrameBudgetManager, cpuMs: Float, gpuMs: Float? = nil) -> FrameBudgetManager.QualityLevel {
        mgr.observe(.init(cpuFrameMs: cpuMs, gpuFrameMs: gpuMs))
    }

    // MARK: - 1. Steady frames stay at .full

    @Test
    func steadyFrames_staysAtFull() {
        let mgr = makeManager()
        for _ in 0..<600 {
            let level = observe(mgr, cpuMs: 16.0)
            #expect(level == .full)
        }
        #expect(mgr.currentLevel == .full)
    }

    // MARK: - 2. Single spike — no downshift

    @Test
    func singleSpike_noDownshift() {
        let mgr = makeManager()
        _ = observe(mgr, cpuMs: 18.0)
        #expect(mgr.currentLevel == .full)
    }

    // MARK: - 3. Three consecutive overruns trigger noSSGI

    @Test
    func threeConsecutiveOverruns_downshiftsToNoSSGI() {
        let mgr = makeManager()
        _ = observe(mgr, cpuMs: 18.0)
        _ = observe(mgr, cpuMs: 18.0)
        #expect(mgr.currentLevel == .full, "Should not downshift after 2 overruns")
        let level = observe(mgr, cpuMs: 18.0)
        #expect(level == .noSSGI)
        #expect(mgr.currentLevel == .noSSGI)
    }

    // MARK: - 4. Interrupted overrun run resets counter

    @Test
    func interruptedOverrunRun_resetsCounterNoDownshift() {
        let mgr = makeManager()
        _ = observe(mgr, cpuMs: 18.0)
        _ = observe(mgr, cpuMs: 18.0)
        // Recovery frame (14 ms ≤ target − headroom = 14.5) zeros overrun counter.
        _ = observe(mgr, cpuMs: 14.0)
        _ = observe(mgr, cpuMs: 18.0)
        _ = observe(mgr, cpuMs: 18.0)
        // Still only 2 consecutive overruns at this point — no downshift.
        #expect(mgr.currentLevel == .full)
    }

    // MARK: - 5. Successive overruns at noSSGI → noBloom

    @Test
    func threeMoreOverrunsAtNoSSGI_downshiftsToNoBloom() {
        let mgr = makeManager()
        // Downshift to noSSGI.
        for _ in 0..<3 { _ = observe(mgr, cpuMs: 18.0) }
        #expect(mgr.currentLevel == .noSSGI)
        // Downshift to noBloom.
        for _ in 0..<3 { _ = observe(mgr, cpuMs: 18.0) }
        #expect(mgr.currentLevel == .noBloom)
    }

    // MARK: - 6. Floor clamping — stuck at reducedMesh, no further downshift

    @Test
    func overrunsAtFloor_neitherDownshiftsNorCrashes() {
        let mgr = makeManager()
        // Descend to .reducedMesh (5 downshift steps × 3 overruns each = 15 frames).
        for _ in 0..<(5 * 3) { _ = observe(mgr, cpuMs: 18.0) }
        #expect(mgr.currentLevel == .reducedMesh)
        // More overruns at the floor — no crash, level stays .reducedMesh.
        for _ in 0..<10 { _ = observe(mgr, cpuMs: 30.0) }
        #expect(mgr.currentLevel == .reducedMesh)
    }

    // MARK: - 7. Full recovery after 180 consecutive sub-budget frames

    @Test
    func sustainedRecovery_upshiftsFromNoSSGIToFull() {
        let mgr = makeManager()
        for _ in 0..<3 { _ = observe(mgr, cpuMs: 18.0) }
        #expect(mgr.currentLevel == .noSSGI)
        // 180 frames at 14 ms (≤ 16.0 − 1.5 = 14.5 ms) triggers upshift.
        for i in 0..<180 {
            let level = observe(mgr, cpuMs: 14.0)
            if i < 179 { #expect(level == .noSSGI, "Should still be noSSGI at frame \(i)") }
        }
        #expect(mgr.currentLevel == .full)
    }

    // MARK: - 8. 179 recovery frames then one bad frame — no upshift

    @Test
    func almostRecovery_oneOvershotFrame_resetsRecoveryCounter() {
        let mgr = makeManager()
        for _ in 0..<3 { _ = observe(mgr, cpuMs: 18.0) }
        #expect(mgr.currentLevel == .noSSGI)
        for _ in 0..<179 { _ = observe(mgr, cpuMs: 14.0) }
        // One frame within hysteresis band zeros recovery counter without upshifting.
        _ = observe(mgr, cpuMs: 16.0)
        #expect(mgr.currentLevel == .noSSGI)
    }

    // MARK: - 9. enabled=false — always returns .full, no state changes

    @Test
    func disabledGovernor_alwaysReturnsFull() {
        let mgr = makeManager(enabled: false)
        for _ in 0..<30 {
            let level = observe(mgr, cpuMs: 30.0)
            #expect(level == .full)
        }
        #expect(mgr.currentLevel == .full)
    }

    // MARK: - 10. gpuFrameMs > cpuFrameMs → governor uses GPU time

    @Test
    func gpuFrameMs_largerThanCpu_governorUsesGPU() {
        let mgr = makeManager()
        // cpu=12 ms would not count as overrun; gpu=18 ms exceeds 16.5 ms threshold.
        _ = observe(mgr, cpuMs: 12.0, gpuMs: 18.0)
        _ = observe(mgr, cpuMs: 12.0, gpuMs: 18.0)
        _ = observe(mgr, cpuMs: 12.0, gpuMs: 18.0)
        #expect(mgr.currentLevel == .noSSGI)
    }

    // MARK: - 11. gpuFrameMs == nil → CPU fallback

    @Test
    func gpuFrameMsNil_fallsBackToCPU() {
        let mgr = makeManager()
        // gpu nil — 18 ms CPU should still count as overrun.
        for _ in 0..<3 { _ = observe(mgr, cpuMs: 18.0, gpuMs: nil) }
        #expect(mgr.currentLevel == .noSSGI)
    }

    // MARK: - 12. reset() from reducedRayMarch → .full, counters zeroed

    @Test
    func reset_fromReducedRayMarch_returnsToFull() {
        let mgr = makeManager()
        for _ in 0..<(3 * 3) { _ = observe(mgr, cpuMs: 18.0) }
        #expect(mgr.currentLevel == .reducedRayMarch)
        mgr.reset()
        #expect(mgr.currentLevel == .full)
        // Verify counters zeroed — one overrun after reset should NOT immediately downshift.
        _ = observe(mgr, cpuMs: 18.0)
        #expect(mgr.currentLevel == .full)
    }

    // MARK: - 13. Tier 1 vs Tier 2 config — tier1 fires after same overrun count

    @Test
    func tier1Default_hasStricterBudget_thanTier2() {
        let t1 = FrameBudgetManager.Configuration.tier1Default
        let t2 = FrameBudgetManager.Configuration.tier2Default
        // Tier 1 target is lower — fires on less overrun.
        #expect(t1.targetFrameMs < t2.targetFrameMs)
        #expect(t1.overrunMarginMs <= t2.overrunMarginMs)
    }

    // MARK: - 14. QualityLevel Comparable ordering

    @Test
    func qualityLevelComparable_ordering() {
        #expect(FrameBudgetManager.QualityLevel.full < .noSSGI)
        #expect(FrameBudgetManager.QualityLevel.noSSGI < .noBloom)
        #expect(FrameBudgetManager.QualityLevel.noBloom < .reducedRayMarch)
        #expect(FrameBudgetManager.QualityLevel.reducedRayMarch < .reducedParticles)
        #expect(FrameBudgetManager.QualityLevel.reducedParticles < .reducedMesh)
        #expect(FrameBudgetManager.QualityLevel.reducedMesh >= .full)
    }

    // MARK: - 15. Hysteresis band — zeroes counters but keeps level

    @Test
    func hysteresisBand_zerosBothCountersKeepsLevel() {
        let mgr = makeManager()
        // Two overruns (counter = 2), then a hysteresis-band frame (16.0 ≤ ms ≤ 16.5 for default).
        _ = observe(mgr, cpuMs: 18.0)
        _ = observe(mgr, cpuMs: 18.0)
        // Hysteresis: 16.0 ms — not an overrun (16.5 threshold), not a recovery (14.5 threshold).
        _ = observe(mgr, cpuMs: 16.0)
        // Counter should have been zeroed — two more overruns still not enough to downshift.
        _ = observe(mgr, cpuMs: 18.0)
        _ = observe(mgr, cpuMs: 18.0)
        #expect(mgr.currentLevel == .full)
    }
}
