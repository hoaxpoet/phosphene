// MLDispatchScheduler — ML dispatch timing controller (Increment 6.3).
//
// Coordinates MPSGraph stem separation dispatches with render-loop frame timing.
// When recent frames are over budget, the scheduler defers the ML dispatch to a
// lighter render moment rather than letting 142ms of GPU compute land on top of
// an already-strained ray-march+SSGI frame.
//
// Pure-state controller: no Date.now(), no concurrency primitives.
// The caller (VisualizerEngine+Stems) supplies timing state via DispatchContext
// and tracks how long a dispatch has been pending via pendingForMs.
//
// See docs/DECISIONS.md D-059 for rationale on budget signal choice, deferral caps,
// force-dispatch safety valve, and QualityCeiling.ultra exemption.

import Foundation
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "MLDispatchScheduler")

// MARK: - FrameTimingProviding

/// Read-only access to rolling frame timing data.
///
/// Allows the ML scheduler call site to be tested with a stub instead of a real
/// `FrameBudgetManager`. Both types conform. D-059(e).
public protocol FrameTimingProviding {
    /// Worst frame time (ms) across the scheduler's recent rolling window.
    var recentMaxFrameMs: Float { get }
    /// Number of frames observed in the rolling window. May be less than the
    /// full window size at startup — scheduler defers until the window fills.
    var recentFramesObserved: Int { get }
}

// MARK: - MLDispatchScheduler

/// Decides whether a pending MPSGraph stem-separation dispatch should fire now,
/// be deferred, or be force-dispatched past the deferral ceiling.
///
/// Usage: the caller tracks how long the dispatch has been pending (`pendingForMs`).
/// On each retry, call `decide(context:)` with the current timing snapshot and apply
/// the returned `Decision`.
public final class MLDispatchScheduler {

    // MARK: - Configuration

    /// Tuning knobs for the scheduler.
    public struct Configuration: Sendable {
        /// Hard ceiling on deferral (ms). Past this, force-dispatch to prevent stem freeze.
        public var maxDeferralMs: Float
        /// Number of recent frames that must all be within budget before dispatching.
        public var requireCleanFramesCount: Int
        /// When false, always returns `.dispatchNow` (Ultra quality ceiling bypass).
        public var enabled: Bool

        public init(maxDeferralMs: Float, requireCleanFramesCount: Int, enabled: Bool) {
            self.maxDeferralMs = maxDeferralMs
            self.requireCleanFramesCount = requireCleanFramesCount
            self.enabled = enabled
        }

        // MARK: - Per-Tier Defaults

        /// Tier 1 (M1/M2): 2000 ms deferral cap, 30-frame clean window.
        ///
        /// Tighter render budget means jank is more likely; the generous 2000 ms cap
        /// prevents stems lagging beyond user-noticeable without abandoning jank
        /// avoidance entirely. 30 frames ≈ 500 ms at 60 fps of clean rendering
        /// required before dispatching. D-059(b).
        public static var tier1Default: Configuration {
            Configuration(maxDeferralMs: 2000, requireCleanFramesCount: 30, enabled: true)
        }

        /// Tier 2 (M3+): 1500 ms deferral cap, 20-frame clean window.
        ///
        /// More GPU headroom means jank is rarer; tighter cap and shorter window give
        /// faster reaction when it does occur. D-059(b).
        public static var tier2Default: Configuration {
            Configuration(maxDeferralMs: 1500, requireCleanFramesCount: 20, enabled: true)
        }
    }

    // MARK: - Decision

    /// What the caller should do with the pending ML dispatch.
    public enum Decision: Sendable, Equatable {
        /// Recent frames are all clean — dispatch the ML job now.
        case dispatchNow
        /// At least one recent frame was over budget — retry after the given delay (ms).
        case `defer`(retryInMs: Float)
        /// Deferral ceiling reached — dispatch despite jank to prevent stem freeze.
        case forceDispatch
    }

    // MARK: - DispatchContext

    /// Snapshot of frame timing and pending state supplied by the caller each `decide()` call.
    public struct DispatchContext: Sendable {
        /// Worst frame time (ms) across the scheduler's required rolling window.
        public let recentMaxFrameMs: Float
        /// Number of frame samples available in the window. May be less than
        /// `requireCleanFramesCount` at startup — scheduler defers until the window fills.
        public let recentFramesObserved: Int
        /// Per-tier render budget (ms): 14.0 for Tier 1, 16.0 for Tier 2.
        public let currentTierBudgetMs: Float
        /// Wall-clock ms since this dispatch was first requested (caller-tracked).
        public let pendingForMs: Float

        public init(
            recentMaxFrameMs: Float,
            recentFramesObserved: Int,
            currentTierBudgetMs: Float,
            pendingForMs: Float
        ) {
            self.recentMaxFrameMs = recentMaxFrameMs
            self.recentFramesObserved = recentFramesObserved
            self.currentTierBudgetMs = currentTierBudgetMs
            self.pendingForMs = pendingForMs
        }
    }

    // MARK: - State

    /// Active configuration (immutable after init).
    public let configuration: Configuration

    /// The most recent decision returned by `decide(context:)`. Used by the debug overlay.
    public private(set) var lastDecision: Decision?

    // MARK: - Observability

    /// Number of times `decide(context:)` has returned `.forceDispatch` since init.
    /// Read by `SoakTestHarness` to report backstop-firing frequency.
    public private(set) var forceDispatchCount: Int = 0

    // MARK: - Init

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Convenience init — picks the correct tier configuration and applies the
    /// `QualityCeiling.ultra` exemption (`enabled = false` when ultra). D-059(d).
    public convenience init(deviceTier: DeviceTier, qualityCeilingIsUltra: Bool = false) {
        var cfg = deviceTier == .tier1 ? Configuration.tier1Default : Configuration.tier2Default
        cfg.enabled = !qualityCeilingIsUltra
        self.init(configuration: cfg)
    }

    // MARK: - Decide

    /// Evaluate the current context and return a dispatch decision.
    ///
    /// Algorithm — see D-059(a) for rationale on each step:
    /// 1. `!enabled` → `.dispatchNow` (ultra bypass: consistent ML cadence for recording).
    /// 2. `pendingForMs ≥ maxDeferralMs` → `.forceDispatch` (stem freshness beats jank avoidance).
    /// 3. `recentFramesObserved < requireCleanFramesCount` → `.defer(100)` (startup warmup).
    /// 4. `recentMaxFrameMs > currentTierBudgetMs` → `.defer(100)` (jank still in window).
    /// 5. Else → `.dispatchNow` (all required frames within budget).
    @discardableResult
    public func decide(context: DispatchContext) -> Decision {
        let decision: Decision

        if !configuration.enabled {
            decision = .dispatchNow
        } else if context.pendingForMs >= configuration.maxDeferralMs {
            let ms = String(format: "%.0f", context.pendingForMs)
            logger.warning("ML: force-dispatch after \(ms, privacy: .public)ms — ceiling hit, jank ignored")
            forceDispatchCount += 1
            decision = .forceDispatch
        } else if context.recentFramesObserved < configuration.requireCleanFramesCount {
            decision = .defer(retryInMs: 100)
        } else if context.recentMaxFrameMs > context.currentTierBudgetMs {
            decision = .defer(retryInMs: 100)
        } else {
            decision = .dispatchNow
        }

        lastDecision = decision
        return decision
    }
}
