// MLDispatchSchedulerWiringTests — Integration between MLDispatchScheduler and the
// rolling window exposed by FrameBudgetManager (Increment 6.3).
//
// Uses a stub FrameTimingProvider and the real FrameBudgetManager (fed synthetic
// timing samples) to verify the two systems share a single rolling buffer as the
// source of truth for "is the render clean right now?".

import Testing
@testable import Renderer
@testable import Shared

// MARK: - StubFrameTimingProvider

/// A minimal conforming type used in place of FrameBudgetManager for wiring tests
/// that need deterministic control over the rolling window values. D-059(e).
private struct StubFrameTimingProvider: FrameTimingProviding {
    var recentMaxFrameMs: Float
    var recentFramesObserved: Int
    /// BUG-106. Defaults to 0 so every pre-existing case keeps judging against the tier
    /// floor, exactly as it did before the budget became median-derived.
    var recentMedianFrameMs: Float = 0
}

// MARK: - MLDispatchSchedulerWiringTests

struct MLDispatchSchedulerWiringTests {

    // MARK: - Helpers

    private func makeManager(targetMs: Float = 14.0) -> FrameBudgetManager {
        FrameBudgetManager(configuration: .init(
            targetFrameMs: targetMs,
            overrunMarginMs: 0.3,
            consecutiveOverrunsToDownshift: 3,
            sustainedRecoveryFrames: 180,
            sustainedRecoveryHeadroomMs: 1.5,
            enabled: true
        ))
    }

    private func feed(_ mgr: FrameBudgetManager, cpuMs: Float, count: Int) {
        for _ in 0..<count {
            mgr.observe(.init(cpuFrameMs: cpuMs, gpuFrameMs: nil))
        }
    }

    private func makeScheduler(requireCount: Int = 30) -> MLDispatchScheduler {
        MLDispatchScheduler(configuration: .init(
            maxDeferralMs: 2000,
            requireCleanFramesCount: requireCount,
            enabled: true
        ))
    }

    private func decide(
        _ sched: MLDispatchScheduler,
        provider: FrameTimingProviding,
        budgetMs: Float = 14.0,
        pendingMs: Float = 0
    ) -> MLDispatchScheduler.Decision {
        sched.decide(context: .init(
            recentMaxFrameMs: provider.recentMaxFrameMs,
            recentFramesObserved: provider.recentFramesObserved,
            currentTierBudgetMs: budgetMs,
            pendingForMs: pendingMs
        ))
    }

    // MARK: - 1. After 30 clean frames on Tier 1, decide() returns .dispatchNow

    @Test
    func thirtyCleanFrames_dispatchNow() {
        let mgr = makeManager(targetMs: 14.0)
        let sched = makeScheduler(requireCount: 30)
        // Feed 30 frames well under budget.
        feed(mgr, cpuMs: 12.0, count: 30)
        #expect(mgr.recentFramesObserved == 30)
        #expect(mgr.recentMaxFrameMs <= 14.0)
        let decision = decide(sched, provider: mgr, budgetMs: 14.0)
        #expect(decision == .dispatchNow)
    }

    // MARK: - 2. One jank frame at position 15 → .defer

    @Test
    func jankAtPosition15_defer() {
        let mgr = makeManager(targetMs: 14.0)
        let sched = makeScheduler(requireCount: 30)
        // 14 clean frames, then one jank, then 15 more clean.
        feed(mgr, cpuMs: 12.0, count: 14)
        feed(mgr, cpuMs: 18.0, count: 1)   // jank at position 15
        feed(mgr, cpuMs: 12.0, count: 15)
        #expect(mgr.recentFramesObserved == 30)
        // recentMax should reflect the 18ms jank frame still in the window.
        #expect(mgr.recentMaxFrameMs > 14.0)
        let decision = decide(sched, provider: mgr, budgetMs: 14.0)
        #expect(decision == .defer(retryInMs: 100))
    }

    // MARK: - 3. Jank slides out after 30 more clean frames → .dispatchNow

    @Test
    func jankSlidesOut_dispatchNow() {
        let mgr = makeManager(targetMs: 14.0)
        let sched = makeScheduler(requireCount: 30)
        // Inject one jank frame, then fill the 30-frame window with clean frames.
        feed(mgr, cpuMs: 18.0, count: 1)
        feed(mgr, cpuMs: 12.0, count: 30)  // jank pushed out of window
        #expect(mgr.recentFramesObserved == 30)
        // After 30 clean frames the jank has been displaced from the rolling window.
        #expect(mgr.recentMaxFrameMs <= 14.0)
        let decision = decide(sched, provider: mgr, budgetMs: 14.0)
        #expect(decision == .dispatchNow)
    }

    // MARK: - 4. FrameBudgetManager is the single source of truth (no duplicate state)

    @Test
    func recentMaxAndObservedComeFromSameBuffer() {
        let mgr = makeManager(targetMs: 16.0)
        // Initial state: no observations.
        #expect(mgr.recentFramesObserved == 0)
        #expect(mgr.recentMaxFrameMs == 0)

        // After 10 frames, both properties reflect the same underlying buffer.
        feed(mgr, cpuMs: 13.0, count: 9)
        feed(mgr, cpuMs: 15.5, count: 1)  // worst frame at position 9 (0-indexed)
        #expect(mgr.recentFramesObserved == 10)
        // Max should be 15.5 (the single worst frame in the 10-frame window).
        #expect(abs(mgr.recentMaxFrameMs - 15.5) < 0.01)

        // Feed 30 more frames — the circular buffer rolls the jank frame out.
        // After 40 total frames the window (last 30) covers positions 10-39, all clean.
        feed(mgr, cpuMs: 12.0, count: 30)
        // Count saturates at capacity (30).
        #expect(mgr.recentFramesObserved == 30)
        // The 15.5ms frame (position 9 of 40 total) is no longer in the window.
        #expect(mgr.recentMaxFrameMs <= 13.0)
    }

    // MARK: - StubFrameTimingProvider: conformance sanity

    @Test
    func stubProvider_conformsToProtocol() {
        let stub = StubFrameTimingProvider(recentMaxFrameMs: 18.0, recentFramesObserved: 30)
        let sched = makeScheduler(requireCount: 30)
        // Stub reports a jank frame → defer.
        let decision = decide(sched, provider: stub, budgetMs: 14.0)
        #expect(decision == .defer(retryInMs: 100))

        // Swap stub to clean values → dispatchNow.
        let cleanStub = StubFrameTimingProvider(recentMaxFrameMs: 12.0, recentFramesObserved: 30)
        let dispatch = decide(sched, provider: cleanStub, budgetMs: 14.0)
        #expect(dispatch == .dispatchNow)
    }

    // MARK: - BUG-106: the budget follows the session, not a constant

    /// At 4K the render never fits a 14/16 ms constant, so the gate could only defer to its
    /// ceiling and force-fire — every stem update a full 2 s period late for no jank saved.
    /// A steady 4K session must now read as clean.
    @Test
    func budget_atFourK_steadySessionDispatchesInsteadOfDeferring() {
        let sched = makeScheduler(requireCount: 30)
        // A steady 4K session: median 25 ms, worst frame 27 — normal for the resolution.
        let steady4K = StubFrameTimingProvider(
            recentMaxFrameMs: 27.0, recentFramesObserved: 30, recentMedianFrameMs: 25.0
        )
        let budget = MLDispatchScheduler.budgetMs(
            floorMs: 16.0, recentMedianFrameMs: steady4K.recentMedianFrameMs
        )
        #expect(abs(budget - 37.5) < 0.01)
        #expect(decide(sched, provider: steady4K, budgetMs: budget) == .dispatchNow)

        // The old constant is what made this impossible — proves the case bites.
        #expect(decide(sched, provider: steady4K, budgetMs: 16.0) == .defer(retryInMs: 100))
    }

    /// The change must not become "never defer": a spike inside the SAME 4K session — the
    /// thing the gate exists to catch — still defers.
    @Test
    func budget_atFourK_genuineJankStillDefers() {
        let sched = makeScheduler(requireCount: 30)
        let janky4K = StubFrameTimingProvider(
            recentMaxFrameMs: 60.0, recentFramesObserved: 30, recentMedianFrameMs: 25.0
        )
        let budget = MLDispatchScheduler.budgetMs(
            floorMs: 16.0, recentMedianFrameMs: janky4K.recentMedianFrameMs
        )
        #expect(decide(sched, provider: janky4K, budgetMs: budget) == .defer(retryInMs: 100))
    }

    /// 1080p behaviour is unchanged: the floor wins there, so the same windows decide the
    /// same way they did before the budget became median-derived.
    @Test
    func budget_at1080p_isUnchangedByTheFloor() {
        // Typical 1080p median (8 ms) x 1.5 = 12 ms, under both tier floors.
        #expect(MLDispatchScheduler.budgetMs(floorMs: 14.0, recentMedianFrameMs: 8.0) == 14.0)
        #expect(MLDispatchScheduler.budgetMs(floorMs: 16.0, recentMedianFrameMs: 8.0) == 16.0)
        // A cold window (no frames observed) also falls back to the floor.
        #expect(MLDispatchScheduler.budgetMs(floorMs: 16.0, recentMedianFrameMs: 0) == 16.0)

        let sched = makeScheduler(requireCount: 30)
        let janky1080p = StubFrameTimingProvider(
            recentMaxFrameMs: 18.0, recentFramesObserved: 30, recentMedianFrameMs: 8.0
        )
        let budget = MLDispatchScheduler.budgetMs(
            floorMs: 16.0, recentMedianFrameMs: janky1080p.recentMedianFrameMs
        )
        #expect(decide(sched, provider: janky1080p, budgetMs: budget) == .defer(retryInMs: 100))
    }

    /// The median is taken over the same window the max comes from, and one hitch must not
    /// raise the bar the next dispatch is judged against (which a mean would).
    @Test
    func recentMedianFrameMs_isRobustToASingleHitch() {
        let mgr = makeManager()
        feed(mgr, cpuMs: 25.0, count: 29)
        feed(mgr, cpuMs: 200.0, count: 1)
        #expect(abs(mgr.recentMedianFrameMs - 25.0) < 0.01)
        #expect(abs(mgr.recentMaxFrameMs - 200.0) < 0.01)
        // Cold: no samples yet → 0, so the floor decides.
        #expect(makeManager().recentMedianFrameMs == 0)
    }
}
