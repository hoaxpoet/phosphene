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
        guard configuration.enabled else { return .full }

        // Use whichever path actually pinned the frame.
        let effectiveMs = max(sample.cpuFrameMs, sample.gpuFrameMs ?? 0)

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
        if was != .full {
            logger.info("quality: reset to full (preset change from \(was.displayName, privacy: .public))")
        }
    }
}
