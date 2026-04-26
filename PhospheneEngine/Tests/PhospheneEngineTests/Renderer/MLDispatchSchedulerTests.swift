// MLDispatchSchedulerTests — Pure-state controller tests for the ML dispatch scheduler.
//
// All tests use synthetic timing values — no real GPU or MPSGraph required.
// Covers: enabled=false bypass, forceDispatch ceiling, startup warmup defer,
// jank-in-window defer, clean-window dispatch, tier configs, rolling window semantics.

import Testing
@testable import Renderer
@testable import Shared

// MARK: - MLDispatchSchedulerTests

struct MLDispatchSchedulerTests {

    // MARK: - Helpers

    private func makeScheduler(
        maxDeferralMs: Float = 2000,
        requireCleanFramesCount: Int = 30,
        enabled: Bool = true
    ) -> MLDispatchScheduler {
        let cfg = MLDispatchScheduler.Configuration(
            maxDeferralMs: maxDeferralMs,
            requireCleanFramesCount: requireCleanFramesCount,
            enabled: enabled
        )
        return MLDispatchScheduler(configuration: cfg)
    }

    private func decide(
        _ sched: MLDispatchScheduler,
        recentMax: Float = 10.0,
        framesObserved: Int = 30,
        budgetMs: Float = 14.0,
        pendingMs: Float = 0
    ) -> MLDispatchScheduler.Decision {
        sched.decide(context: .init(
            recentMaxFrameMs: recentMax,
            recentFramesObserved: framesObserved,
            currentTierBudgetMs: budgetMs,
            pendingForMs: pendingMs
        ))
    }

    // MARK: - 1. enabled=false → .dispatchNow regardless of frame timings

    @Test
    func disabled_alwaysDispatchesNow() {
        let sched = makeScheduler(enabled: false)
        // Even with jank and insufficient frames, disabled scheduler passes through.
        let decision = decide(sched, recentMax: 30.0, framesObserved: 5, budgetMs: 14.0, pendingMs: 0)
        #expect(decision == .dispatchNow)
    }

    @Test
    func disabled_dispatchesNowEvenAtCeiling() {
        let sched = makeScheduler(maxDeferralMs: 500, enabled: false)
        let decision = decide(sched, recentMax: 30.0, framesObserved: 30, budgetMs: 14.0, pendingMs: 600)
        #expect(decision == .dispatchNow)
    }

    // MARK: - 2. pendingForMs >= maxDeferralMs → .forceDispatch even with jank

    @Test
    func ceilingReached_forceDispatch_despiteJank() {
        let sched = makeScheduler(maxDeferralMs: 2000)
        let decision = decide(sched, recentMax: 25.0, framesObserved: 30, budgetMs: 14.0, pendingMs: 2000)
        #expect(decision == .forceDispatch)
    }

    @Test
    func ceilingReachedExactly_forceDispatch() {
        let sched = makeScheduler(maxDeferralMs: 1500)
        let decision = decide(sched, recentMax: 18.0, framesObserved: 30, budgetMs: 16.0, pendingMs: 1500)
        #expect(decision == .forceDispatch)
    }

    // MARK: - 3. recentFramesObserved < requireCleanFramesCount → .defer(100) (startup)

    @Test
    func insufficientFrames_deferWithRetry() {
        let sched = makeScheduler(requireCleanFramesCount: 30)
        // 29 frames observed — one short of the required 30.
        let decision = decide(sched, recentMax: 10.0, framesObserved: 29, budgetMs: 14.0, pendingMs: 0)
        #expect(decision == .defer(retryInMs: 100))
    }

    @Test
    func zeroFrames_deferWithRetry() {
        let sched = makeScheduler(requireCleanFramesCount: 30)
        let decision = decide(sched, recentMax: 0, framesObserved: 0, budgetMs: 14.0, pendingMs: 0)
        #expect(decision == .defer(retryInMs: 100))
    }

    // MARK: - 4. recentMaxFrameMs > currentTierBudgetMs → .defer(100)

    @Test
    func jankInWindow_defer() {
        let sched = makeScheduler(requireCleanFramesCount: 30)
        // recentMax 14.1 > budget 14.0 — one over-budget frame in the window.
        let decision = decide(sched, recentMax: 14.1, framesObserved: 30, budgetMs: 14.0, pendingMs: 0)
        #expect(decision == .defer(retryInMs: 100))
    }

    @Test
    func severeJankInWindow_defer() {
        let sched = makeScheduler(requireCleanFramesCount: 20)
        let decision = decide(sched, recentMax: 30.0, framesObserved: 20, budgetMs: 16.0, pendingMs: 100)
        #expect(decision == .defer(retryInMs: 100))
    }

    // MARK: - 5. All required frames clean → .dispatchNow

    @Test
    func allFramesClean_dispatchNow() {
        let sched = makeScheduler(requireCleanFramesCount: 30)
        // recentMax 13.9 < budget 14.0 — clean window.
        let decision = decide(sched, recentMax: 13.9, framesObserved: 30, budgetMs: 14.0, pendingMs: 50)
        #expect(decision == .dispatchNow)
    }

    @Test
    func exactlyAtBudget_dispatchNow() {
        let sched = makeScheduler(requireCleanFramesCount: 20)
        // recentMax == budget — not over, should dispatch.
        let decision = decide(sched, recentMax: 16.0, framesObserved: 20, budgetMs: 16.0, pendingMs: 0)
        #expect(decision == .dispatchNow)
    }

    // MARK: - 6. Tier 1 default config values

    @Test
    func tier1Default_hasCorrectValues() {
        let cfg = MLDispatchScheduler.Configuration.tier1Default
        #expect(cfg.maxDeferralMs == 2000)
        #expect(cfg.requireCleanFramesCount == 30)
        #expect(cfg.enabled == true)
    }

    // MARK: - 7. Tier 2 default config values

    @Test
    func tier2Default_hasCorrectValues() {
        let cfg = MLDispatchScheduler.Configuration.tier2Default
        #expect(cfg.maxDeferralMs == 1500)
        #expect(cfg.requireCleanFramesCount == 20)
        #expect(cfg.enabled == true)
    }

    // MARK: - 8. Sequence: jank frame defers, then slides out → .dispatchNow

    @Test
    func jankSlidesOutOfWindow_eventuallyDispatchNow() {
        // Simulate a rolling window where one bad frame initially causes deferral.
        // Once the window no longer contains that frame, dispatch is allowed.
        let sched = makeScheduler(requireCleanFramesCount: 30)

        // Window still contains the jank frame — defer.
        let defer1 = decide(sched, recentMax: 20.0, framesObserved: 30, budgetMs: 14.0, pendingMs: 100)
        #expect(defer1 == .defer(retryInMs: 100))

        // After the jank slides out of the window, recentMax returns to clean.
        let dispatch = decide(sched, recentMax: 13.0, framesObserved: 30, budgetMs: 14.0, pendingMs: 200)
        #expect(dispatch == .dispatchNow)
    }

    // MARK: - lastDecision tracking

    @Test
    func lastDecision_updatedOnEachCall() {
        let sched = makeScheduler(requireCleanFramesCount: 30)
        #expect(sched.lastDecision == nil)

        _ = decide(sched, recentMax: 20.0, framesObserved: 30, budgetMs: 14.0)
        #expect(sched.lastDecision == .defer(retryInMs: 100))

        _ = decide(sched, recentMax: 10.0, framesObserved: 30, budgetMs: 14.0)
        #expect(sched.lastDecision == .dispatchNow)
    }

    // MARK: - convenienceInit: qualityCeilingIsUltra disables scheduler

    @Test
    func ultraCeiling_setsEnabledFalse() {
        let sched = MLDispatchScheduler(deviceTier: .tier1, qualityCeilingIsUltra: true)
        #expect(sched.configuration.enabled == false)
        // Disabled scheduler dispatches even through jank.
        let decision = decide(sched, recentMax: 30.0, framesObserved: 0, budgetMs: 14.0)
        #expect(decision == .dispatchNow)
    }
}
