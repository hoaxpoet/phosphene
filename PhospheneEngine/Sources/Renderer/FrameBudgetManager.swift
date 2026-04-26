// FrameBudgetManager — Per-frame GPU + render-loop timing governor (Increment 6.2).
//
// Monitors per-frame timing and dynamically downshifts visual complexity when
// the budget is exceeded; restores quality after sustained recovery.
//
// The governor is a pure-state controller: no Date.now(), no concurrency primitives.
// The caller (RenderPipeline.draw(in:)) supplies wall-clock timestamps and applies
// the returned QualityLevel. observe(_:) is called from the commandBuffer
// addCompletedHandler → @MainActor hop.
//
// See docs/DECISIONS.md D-057 for rationale on tier budgets, hysteresis asymmetry,
// the OR-gate pattern with a11y, and the QualityCeiling.ultra exemption.

import Foundation
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "FrameBudgetManager")

// MARK: - FrameBudgetManager

/// Per-frame budget governor: detects sustained frame overruns and reduces visual
/// quality one step at a time; restores quality after sustained recovery.
///
/// The governor is a pure stateful controller — all inputs are explicit parameters.
/// Call `observe(_:)` from the `@MainActor` completed-handler hop each frame.
/// Call `reset()` on every preset change.
public final class FrameBudgetManager {

    // MARK: - Configuration

    /// Tuning knobs for the governor. All fields are plain value types — safe to copy.
    public struct Configuration: Sendable {
        /// Target frame time in milliseconds. Downshift triggers when frames exceed
        /// `targetFrameMs + overrunMarginMs` for `consecutiveOverrunsToDownshift` frames.
        public var targetFrameMs: Float
        /// Grace margin added to the target before counting as an overrun (ms).
        public var overrunMarginMs: Float
        /// Number of consecutive overrun samples before downshifting one level.
        public var consecutiveOverrunsToDownshift: Int
        /// Number of consecutive recovery samples before upshifting one level.
        /// Large value (180 ≈ 3 s at 60 fps) prevents oscillation.
        public var sustainedRecoveryFrames: Int
        /// Frame must be this many ms below target to count as a recovery sample.
        public var sustainedRecoveryHeadroomMs: Float
        /// When `false`, `observe(_:)` is a no-op and always returns `.full`.
        /// Set to `false` when `QualityCeiling == .ultra` (recording mode).
        public var enabled: Bool

        public init(
            targetFrameMs: Float = 16.6,
            overrunMarginMs: Float = 0.5,
            consecutiveOverrunsToDownshift: Int = 3,
            sustainedRecoveryFrames: Int = 180,
            sustainedRecoveryHeadroomMs: Float = 1.5,
            enabled: Bool = true
        ) {
            self.targetFrameMs = targetFrameMs
            self.overrunMarginMs = overrunMarginMs
            self.consecutiveOverrunsToDownshift = consecutiveOverrunsToDownshift
            self.sustainedRecoveryFrames = sustainedRecoveryFrames
            self.sustainedRecoveryHeadroomMs = sustainedRecoveryHeadroomMs
            self.enabled = enabled
        }

        // MARK: - Per-Tier Defaults

        /// Tier 1 (M1/M2) defaults — 14 ms target leaves headroom for stem-separation
        /// amortization and Swift overhead on top of 60 Hz rendering.
        /// See D-057(a).
        public static var tier1Default: Configuration {
            Configuration(
                targetFrameMs: 14.0,
                overrunMarginMs: 0.3,
                consecutiveOverrunsToDownshift: 3,
                sustainedRecoveryFrames: 180,
                sustainedRecoveryHeadroomMs: 1.5,
                enabled: true
            )
        }

        /// Tier 2 (M3+) defaults — 16 ms target with standard 0.5 ms overrun margin.
        /// See D-057(a).
        public static var tier2Default: Configuration {
            Configuration(
                targetFrameMs: 16.0,
                overrunMarginMs: 0.5,
                consecutiveOverrunsToDownshift: 3,
                sustainedRecoveryFrames: 180,
                sustainedRecoveryHeadroomMs: 1.5,
                enabled: true
            )
        }
    }

    // MARK: - Quality Levels

    /// Visual complexity ladder. Each level is strictly a superset of the reductions
    /// applied by all levels above it. The governor steps one level at a time in
    /// both directions. Applied by `RenderPipeline.applyQualityLevel(_:)`.
    public enum QualityLevel: Int, Comparable, Sendable, CaseIterable {
        /// Baseline — all passes and effects at full quality.
        case full = 0
        /// SSGI pass suppressed. First reduction; SSGI is expensive and visually subtle.
        case noSSGI = 1
        /// SSGI off + bloom off. Post-process pass still runs for ACES tone-mapping.
        case noBloom = 2
        /// + ray march step count at 0.75×. Trades SDF precision for throughput.
        case reducedRayMarch = 3
        /// + particle count at 0.5×. Reduces murmuration density.
        case reducedParticles = 4
        /// + mesh density at 0.5×. Lowest quality floor.
        case reducedMesh = 5

        public static func < (lhs: QualityLevel, rhs: QualityLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// Human-readable label for debug overlay and session log.
        public var displayName: String {
            switch self {
            case .full:             return "full"
            case .noSSGI:           return "no-SSGI"
            case .noBloom:          return "no-bloom"
            case .reducedRayMarch:  return "step-0.75"
            case .reducedParticles: return "particles-0.5"
            case .reducedMesh:      return "mesh-0.5"
            }
        }
    }

    // MARK: - Frame Timing Sample

    /// One frame's worth of timing data for the governor.
    public struct FrameTimingSample: Sendable {
        /// Wall-clock duration of the `draw(in:)` body in milliseconds, excluding
        /// the present wait. Measured with `CACurrentMediaTime()` around the draw scope.
        public let cpuFrameMs: Float
        /// GPU start → end time from `MTLCommandBuffer.gpuStartTime/gpuEndTime` in
        /// milliseconds. Nil when unavailable (first frame, or GPU timestamps not yet
        /// populated). The governor falls back to `cpuFrameMs` when nil.
        public let gpuFrameMs: Float?

        public init(cpuFrameMs: Float, gpuFrameMs: Float?) {
            self.cpuFrameMs = cpuFrameMs
            self.gpuFrameMs = gpuFrameMs
        }
    }

    // MARK: - State

    /// Active configuration (read-only after init).
    public let configuration: Configuration

    /// Current quality level. Read from the main actor, where `applyQualityLevel` runs.
    public private(set) var currentLevel: QualityLevel = .full

    private var consecutiveOverruns: Int = 0
    private var consecutiveRecovered: Int = 0

    // MARK: - Rolling Frame Timing Window (FrameTimingProviding — D-059)

    /// Capacity of the rolling window. 30 frames covers the largest `requireCleanFramesCount`
    /// value used by `MLDispatchScheduler` (Tier 1 default). The governor's own hysteresis
    /// logic (3 overruns / 180 recovery) uses the running counters above; this buffer serves
    /// the tighter "is the render clean right now?" signal the ML scheduler needs.
    private static let rollingWindowCapacity = 30
    private var rollingWindow = [Float](repeating: 0, count: rollingWindowCapacity)
    private var rollingWindowHead = 0
    private var rollingWindowCount = 0

    // MARK: - Init

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Convenience init — picks the correct tier configuration and applies the
    /// `QualityCeiling.ultra` exemption (`enabled = false` when ultra). D-057(d).
    public convenience init(deviceTier: DeviceTier, qualityCeilingIsUltra: Bool = false) {
        var cfg = deviceTier == .tier1 ? Configuration.tier1Default : Configuration.tier2Default
        cfg.enabled = !qualityCeilingIsUltra
        self.init(configuration: cfg)
    }

    // MARK: - Observe

    /// Feed one frame's timing sample into the governor.
    ///
    /// Returns the (possibly unchanged) current quality level. Call from the
    /// `@MainActor` completed-handler hop — the one-frame lag is intentional;
    /// you cannot react to a frame before it finishes. See D-057(b).
    ///
    /// When `configuration.enabled == false`, returns `.full` immediately as a no-op.
    @discardableResult
    public func observe(_ sample: FrameTimingSample) -> QualityLevel {
        // Use whichever path actually pinned the frame.
        let effectiveMs = max(sample.cpuFrameMs, sample.gpuFrameMs ?? 0)

        // Always record to the rolling window regardless of enabled flag — the ML
        // dispatch scheduler reads this even when the governor is in bypass mode.
        rollingWindow[rollingWindowHead] = effectiveMs
        rollingWindowHead = (rollingWindowHead + 1) % Self.rollingWindowCapacity
        if rollingWindowCount < Self.rollingWindowCapacity {
            rollingWindowCount += 1
        }

        guard configuration.enabled else { return .full }

        let overrunThreshold   = configuration.targetFrameMs + configuration.overrunMarginMs
        let recoveryThreshold  = configuration.targetFrameMs - configuration.sustainedRecoveryHeadroomMs
        let previousLevel      = currentLevel

        if effectiveMs > overrunThreshold {
            consecutiveOverruns += 1
            consecutiveRecovered = 0
            if consecutiveOverruns >= configuration.consecutiveOverrunsToDownshift,
               let nextLevel = QualityLevel(rawValue: currentLevel.rawValue + 1) {
                currentLevel = nextLevel
                consecutiveOverruns = 0
                let ms = String(format: "%.1f", effectiveMs)
                let msg = "\(previousLevel.displayName) → \(nextLevel.displayName) (\(ms)ms)"
                logger.info("quality: \(msg, privacy: .public)")
            }
        } else if effectiveMs <= recoveryThreshold {
            consecutiveRecovered += 1
            consecutiveOverruns = 0
            if consecutiveRecovered >= configuration.sustainedRecoveryFrames,
               let prevLevel = QualityLevel(rawValue: currentLevel.rawValue - 1) {
                currentLevel = prevLevel
                consecutiveRecovered = 0
                let frames = configuration.sustainedRecoveryFrames
                let msg2 = "\(previousLevel.displayName) → \(prevLevel.displayName) (after \(frames) frames)"
                logger.info("quality: \(msg2, privacy: .public)")
            }
        } else {
            // Within hysteresis band — zero both counters, keep level.
            consecutiveOverruns = 0
            consecutiveRecovered = 0
        }

        return currentLevel
    }

    // MARK: - Reset

    /// Reset the governor to `.full` immediately.
    ///
    /// Call on every preset change — a new preset has unknown cost characteristics;
    /// start optimistic and let the controller find the right level. D-057(e).
    public func reset() {
        let was = currentLevel
        currentLevel = .full
        consecutiveOverruns = 0
        consecutiveRecovered = 0
        // Rolling window is intentionally NOT cleared on reset — the ML scheduler needs
        // the real recent frame history. Resetting it would cause a false "startup warmup"
        // defer on every preset change while the buffer refills.
        if was != .full {
            logger.info("quality: reset to full (preset change from \(was.displayName, privacy: .public))")
        }
    }

    /// Clear only the rolling frame-timing window, leaving `currentLevel` intact.
    ///
    /// Use after a display hot-plug or window reparent: the next ~30 frames will be
    /// transient as AppKit resizes the drawable, so we don't want those samples
    /// polluting the ML scheduler's "is render clean right now?" signal.
    /// `currentLevel` is preserved — the governor already chose it for this preset. D-061(a).
    public func resetRecentFrameBuffer() {
        rollingWindow = [Float](repeating: 0, count: Self.rollingWindowCapacity)
        rollingWindowHead = 0
        rollingWindowCount = 0
        logger.info("quality: rolling window cleared (display event)")
    }
}

// MARK: - FrameTimingProviding

extension FrameBudgetManager: FrameTimingProviding {
    /// Worst frame time (ms) in the rolling window. Returns 0 when no frames observed yet.
    public var recentMaxFrameMs: Float {
        guard rollingWindowCount > 0 else { return 0 }
        if rollingWindowCount < Self.rollingWindowCapacity {
            return rollingWindow.prefix(rollingWindowCount).max() ?? 0
        }
        return rollingWindow.max() ?? 0
    }

    /// Number of valid samples in the rolling window (0 … rollingWindowCapacity).
    public var recentFramesObserved: Int {
        rollingWindowCount
    }
}
