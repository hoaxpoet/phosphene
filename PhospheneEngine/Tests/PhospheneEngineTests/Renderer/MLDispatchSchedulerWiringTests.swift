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
}
