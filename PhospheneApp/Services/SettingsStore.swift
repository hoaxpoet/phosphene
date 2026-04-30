// SettingsStore — Typed UserDefaults wrapper for all Phosphene settings.
//
// Pre-flight audit findings (U.8, 2026-04-24):
//   1. AudioInputRouter has switchMode(_:) — LIVE-SWITCH PATH wired in CaptureModeReconciler.
//   2. PresetScoringContext extended with excludedFamilies + qualityCeiling (defaults keep
//      existing call sites compiling).
//   3. DeviceTier override implemented in PresetScoringContextProvider (app layer only).
//   4. PresetCategory enum used for blocklist (no PresetFamily in codebase).
//   5. Only phosphene.showLiveAdaptationToasts requires migration; showPerformanceWarnings
//      is new (no old key). SettingsMigrator handles the one migration.
//   6. SessionRecorder gains enabled: Bool param (applies at next session start).
//
// Key scheme: "phosphene.settings.<group>.<key>"
// Apply semantics:
//   - captureMode:              live-switch via CaptureModeReconciler (may hiccup <2s)
//   - excludedPresetCategories, qualityCeiling, deviceTierOverride: next preset transition
//   - sessionRecorderEnabled:   next session start
//   - reducedMotion:            next frame / render tick (read by SessionStateViewModel)
//   - showLiveAdaptationToasts: immediate (LiveAdaptationToastBridge reads on each event)
//   - showPerformanceWarnings:  Inc 6.2 downstream wiring; flag stored now
//   - resetOnboarding:          next app launch

import Combine
import Foundation
import Orchestrator
import Presets

// MARK: - SettingsStore

/// Typed UserDefaults wrapper. All settings accessed here; never raw UserDefaults in views.
///
/// `@Published` properties enable SwiftUI binding via `SettingsViewModel`.
/// Each `didSet` encodes and persists to `UserDefaults`.
@MainActor
final class SettingsStore: ObservableObject {

    // MARK: - UserDefaults Key Scheme

    enum Keys {
        // Audio
        static let captureMode         = "phosphene.settings.audio.captureMode"
        static let sourceAppOverride   = "phosphene.settings.audio.sourceAppOverride"
        // Visuals
        static let deviceTierOverride  = "phosphene.settings.visuals.deviceTierOverride"
        static let qualityCeiling      = "phosphene.settings.visuals.qualityCeiling"
        static let includeMilkdropPresets = "phosphene.settings.visuals.includeMilkdropPresets"
        static let reducedMotion       = "phosphene.settings.visuals.reducedMotion"
        static let excludedPresetCategories = "phosphene.settings.visuals.excludedPresetCategories"
        static let showLiveAdaptationToasts = "phosphene.settings.visuals.showLiveAdaptationToasts"
        static let showUncertifiedPresets   = "phosphene.settings.visuals.showUncertifiedPresets"
        // Diagnostics
        static let sessionRecorderEnabled  = "phosphene.settings.diagnostics.sessionRecorderEnabled"
        static let sessionRetention        = "phosphene.settings.diagnostics.sessionRetention"
        static let showPerformanceWarnings = "phosphene.settings.diagnostics.showPerformanceWarnings"
        // Onboarding (not settings — cleared by resetOnboarding only)
        static let photosensitivityAcknowledged = "phosphene.onboarding.photosensitivityAcknowledged"
    }

    // MARK: - Audio

    @Published var captureMode: CaptureMode = .systemAudio {
        didSet { encode(captureMode, forKey: Keys.captureMode) }
    }

    @Published var sourceAppOverride: SourceAppOverride? {
        didSet { encodeOptional(sourceAppOverride, forKey: Keys.sourceAppOverride) }
    }

    // MARK: - Visuals

    @Published var deviceTierOverride: DeviceTierOverride = .auto {
        didSet { encode(deviceTierOverride, forKey: Keys.deviceTierOverride) }
    }

    @Published var qualityCeiling: QualityCeiling = .auto {
        didSet { encode(qualityCeiling, forKey: Keys.qualityCeiling) }
    }

    /// Always true until Phase MD ships. UI disables the toggle; store persists as-is.
    @Published var includeMilkdropPresets: Bool = true {
        didSet { defaults.set(includeMilkdropPresets, forKey: Keys.includeMilkdropPresets) }
    }

    @Published var reducedMotion: ReducedMotionPreference = .matchSystem {
        didSet { encode(reducedMotion, forKey: Keys.reducedMotion) }
    }

    @Published var excludedPresetCategories: Set<PresetCategory> = [] {
        didSet { encodeSet(excludedPresetCategories, forKey: Keys.excludedPresetCategories) }
    }

    @Published var showLiveAdaptationToasts: Bool = false {
        didSet { defaults.set(showLiveAdaptationToasts, forKey: Keys.showLiveAdaptationToasts) }
    }

    /// When true, uncertified presets appear in session planning (for testing).
    /// Default: false — the Orchestrator only schedules certified presets.
    @Published var showUncertifiedPresets: Bool = false {
        didSet { defaults.set(showUncertifiedPresets, forKey: Keys.showUncertifiedPresets) }
    }

    // MARK: - Diagnostics

    @Published var sessionRecorderEnabled: Bool = true {
        didSet { defaults.set(sessionRecorderEnabled, forKey: Keys.sessionRecorderEnabled) }
    }

    @Published var sessionRetention: SessionRetentionPolicy = .lastN10 {
        didSet { encode(sessionRetention, forKey: Keys.sessionRetention) }
    }

    @Published var showPerformanceWarnings: Bool = false {
        didSet { defaults.set(showPerformanceWarnings, forKey: Keys.showPerformanceWarnings) }
    }

    // MARK: - Events

    /// Published when captureMode or sourceAppOverride changes so CaptureModeReconciler
    /// can react without polling. Distinct from @Published to avoid double-firing.
    let captureModeChanged = PassthroughSubject<Void, Never>()

    // MARK: - Private

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Init

    /// - Parameter defaults: Defaults suite. Use a named suite in tests for isolation.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadAll()
    }

    // MARK: - Onboarding Reset

    /// Clears all onboarding keys, forcing U.2 flows to re-run on next app launch.
    /// Settings values are NOT cleared.
    func resetOnboarding() {
        defaults.removeObject(forKey: Keys.photosensitivityAcknowledged)
    }

    // MARK: - Private Load

    private func loadAll() {
        captureMode = decodeOrDefault(.systemAudio, forKey: Keys.captureMode)
        sourceAppOverride = decodeOptional(SourceAppOverride.self, forKey: Keys.sourceAppOverride)
        deviceTierOverride = decodeOrDefault(.auto, forKey: Keys.deviceTierOverride)
        qualityCeiling = decodeOrDefault(.auto, forKey: Keys.qualityCeiling)
        includeMilkdropPresets = defaults.object(forKey: Keys.includeMilkdropPresets) == nil
            ? true
            : defaults.bool(forKey: Keys.includeMilkdropPresets)
        reducedMotion = decodeOrDefault(.matchSystem, forKey: Keys.reducedMotion)
        excludedPresetCategories = decodeSet(PresetCategory.self, forKey: Keys.excludedPresetCategories)
        showLiveAdaptationToasts = defaults.bool(forKey: Keys.showLiveAdaptationToasts)
        showUncertifiedPresets   = defaults.bool(forKey: Keys.showUncertifiedPresets)
        sessionRecorderEnabled = defaults.object(forKey: Keys.sessionRecorderEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.sessionRecorderEnabled)
        sessionRetention = decodeOrDefault(.lastN10, forKey: Keys.sessionRetention)
        showPerformanceWarnings = defaults.bool(forKey: Keys.showPerformanceWarnings)
    }

    // MARK: - Encode helpers

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
        if key == Keys.captureMode || key == Keys.sourceAppOverride {
            captureModeChanged.send()
        }
    }

    private func encodeOptional<T: Encodable>(_ value: T?, forKey key: String) {
        if let value {
            guard let data = try? encoder.encode(value) else { return }
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        if key == Keys.captureMode || key == Keys.sourceAppOverride {
            captureModeChanged.send()
        }
    }

    private func encodeSet<T: RawRepresentable & Codable>(_ set: Set<T>, forKey key: String) {
        guard let data = try? encoder.encode(Array(set)) else { return }
        defaults.set(data, forKey: key)
    }

    // MARK: - Decode helpers

    private func decodeOrDefault<T: Decodable & RawRepresentable>(
        _ defaultValue: T,
        forKey key: String
    ) -> T where T.RawValue == String {
        guard let data = defaults.data(forKey: key),
              let value = try? decoder.decode(T.self, from: data) else { return defaultValue }
        return value
    }

    private func decodeOptional<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func decodeSet<T: Decodable & Hashable & RawRepresentable>(
        _ type: T.Type,
        forKey key: String
    ) -> Set<T> where T.RawValue == String {
        guard let data = defaults.data(forKey: key),
              let array = try? decoder.decode([T].self, from: data) else { return [] }
        return Set(array)
    }
}
