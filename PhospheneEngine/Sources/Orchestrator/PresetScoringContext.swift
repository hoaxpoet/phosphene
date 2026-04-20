// PresetScoringContext — Immutable snapshot of session state passed to the PresetScorer.
// All time arithmetic goes through elapsedSessionTime; no Date.now() inside the scorer.

import Foundation
import Shared
import Presets

// MARK: - PresetHistoryEntry

/// A record of one preset appearance within the current session.
///
/// Used by `DefaultPresetScorer` to compute family-repeat and fatigue penalties.
/// `startTime` and `endTime` are monotonic seconds from session start —
/// they match `PresetScoringContext.elapsedSessionTime`.
public struct PresetHistoryEntry: Sendable, Hashable {
    /// Stable preset identifier — matches `PresetDescriptor.id`.
    public let presetID: String
    /// Aesthetic family of the preset that appeared.
    public let family: PresetCategory
    /// Session-relative time when the preset became active.
    public let startTime: TimeInterval
    /// Session-relative time when the preset was dismissed.
    public let endTime: TimeInterval

    public init(
        presetID: String,
        family: PresetCategory,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) {
        self.presetID = presetID
        self.family = family
        self.startTime = startTime
        self.endTime = endTime
    }
}

// MARK: - PresetScoringContext

/// Immutable snapshot of session state consumed by `PresetScoring` implementations.
///
/// Callers construct a fresh context each time they invoke the scorer — contexts
/// are cheap value types and are never mutated after creation.
///
/// ## Determinism guarantee
/// Every field is a value type or `Sendable` value. No closures, no Date access,
/// no random seeds. The same context produces the same scores across calls.
public struct PresetScoringContext: Sendable {

    // MARK: - Fields

    /// The active device tier — used to select the correct `ComplexityCost` field.
    public let deviceTier: DeviceTier

    /// Frame budget in milliseconds. Defaults to `deviceTier.frameBudgetMs`.
    ///
    /// Override for testing or when the device reports a non-standard display refresh rate.
    public let frameBudgetMs: Float

    /// Session history ordered oldest-first, most-recent last.
    ///
    /// The scorer looks backward through this list to compute fatigue cooldowns.
    /// Callers should trim this to a reasonable window (e.g. 20 entries) before
    /// passing it in; the scorer does not truncate it.
    public let recentHistory: [PresetHistoryEntry]

    /// The currently playing preset, or nil if no preset is active yet.
    ///
    /// A preset matching this descriptor's `id` is excluded from scoring as a
    /// transition candidate (you can't transition to what's already playing).
    public let currentPreset: PresetDescriptor?

    /// Monotonic clock in seconds since the session started.
    ///
    /// Used to compute fatigue cooldown gaps (`elapsedSessionTime - entry.endTime`).
    /// Never read `Date.now()` inside the scorer — use this field.
    public let elapsedSessionTime: TimeInterval

    /// The detected or predicted musical section, or nil if unknown.
    ///
    /// Nil means "no section context available" — sectionSuitability scores 1.0 (full credit).
    public let currentSection: SongSection?

    // MARK: - Init

    public init(
        deviceTier: DeviceTier,
        frameBudgetMs: Float? = nil,
        recentHistory: [PresetHistoryEntry] = [],
        currentPreset: PresetDescriptor? = nil,
        elapsedSessionTime: TimeInterval = 0,
        currentSection: SongSection? = nil
    ) {
        self.deviceTier = deviceTier
        self.frameBudgetMs = frameBudgetMs ?? deviceTier.frameBudgetMs
        self.recentHistory = recentHistory
        self.currentPreset = currentPreset
        self.elapsedSessionTime = elapsedSessionTime
        self.currentSection = currentSection
    }

    // MARK: - Factory

    /// Minimal starting context for a new session on the given device.
    public static func initial(deviceTier: DeviceTier) -> PresetScoringContext {
        PresetScoringContext(deviceTier: deviceTier)
    }
}
