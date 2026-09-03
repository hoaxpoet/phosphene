// SettingsStore — Typed UserDefaults wrapper for all Uzume settings.
//
// Key scheme: "uzume.settings.<group>.<key>"
// Apply semantics:
//   - excludedPresetCategories, qualityCeiling, deviceTierOverride: next preset transition
//   - sessionRecorderEnabled:   next session start
//   - reducedMotion:            next frame / render tick (read by SessionStateViewModel)
//   - showLiveAdaptationToasts: immediate (LiveAdaptationToastBridge reads on each event)
//   - preparationView:          immediate, including mid-preparation (PreparationProgressView observes)
//   - showTrackInformation:     immediate (PlaybackChromeView binds to it; the cluster toggles it)
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
        // Visuals
        static let deviceTierOverride  = "uzume.settings.visuals.deviceTierOverride"
        static let qualityCeiling      = "uzume.settings.visuals.qualityCeiling"
        static let reducedMotion       = "uzume.settings.visuals.reducedMotion"
        static let excludedPresetCategories = "uzume.settings.visuals.excludedPresetCategories"
        static let showLiveAdaptationToasts = "uzume.settings.visuals.showLiveAdaptationToasts"
        static let showUncertifiedPresets   = "uzume.settings.visuals.showUncertifiedPresets"
        static let preparationView          = "uzume.settings.visuals.preparationView"
        static let showTrackInformation     = "uzume.settings.visuals.showTrackInformation"
        // Diagnostics
        static let sessionRecorderEnabled  = "uzume.settings.diagnostics.sessionRecorderEnabled"
        static let sessionRetention        = "uzume.settings.diagnostics.sessionRetention"
        // Onboarding (not settings — cleared by resetOnboarding only)
        static let photosensitivityAcknowledged = "uzume.onboarding.photosensitivityAcknowledged"
    }

    // MARK: - Visuals

    @Published var deviceTierOverride: DeviceTierOverride = .auto {
        didSet { encode(deviceTierOverride, forKey: Keys.deviceTierOverride) }
    }

    @Published var qualityCeiling: QualityCeiling = .auto {
        didSet { encode(qualityCeiling, forKey: Keys.qualityCeiling) }
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

    /// How the preparation wait is shown: the cave (default) or the track list. DS.4.
    @Published var preparationView: PreparationViewPreference = .mysterious {
        didSet { encode(preparationView, forKey: Keys.preparationView) }
    }

    /// Whether the track card (title, artist, artwork, the preset on screen) shows
    /// during a session. Default true. Only ever what is playing now (D-238). DS.6.
    @Published var showTrackInformation: Bool = true {
        didSet { defaults.set(showTrackInformation, forKey: Keys.showTrackInformation) }
    }

    // MARK: - Diagnostics

    @Published var sessionRecorderEnabled: Bool = true {
        didSet { defaults.set(sessionRecorderEnabled, forKey: Keys.sessionRecorderEnabled) }
    }

    @Published var sessionRetention: SessionRetentionPolicy = .lastN10 {
        didSet { encode(sessionRetention, forKey: Keys.sessionRetention) }
    }

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
        deviceTierOverride = decodeOrDefault(.auto, forKey: Keys.deviceTierOverride)
        qualityCeiling = decodeOrDefault(.auto, forKey: Keys.qualityCeiling)
        reducedMotion = decodeOrDefault(.matchSystem, forKey: Keys.reducedMotion)
        excludedPresetCategories = decodeSet(PresetCategory.self, forKey: Keys.excludedPresetCategories)
        showLiveAdaptationToasts = defaults.bool(forKey: Keys.showLiveAdaptationToasts)
        showUncertifiedPresets   = defaults.bool(forKey: Keys.showUncertifiedPresets)
        preparationView = decodeOrDefault(.mysterious, forKey: Keys.preparationView)
        showTrackInformation = defaults.object(forKey: Keys.showTrackInformation) == nil
            ? true
            : defaults.bool(forKey: Keys.showTrackInformation)
        sessionRecorderEnabled = defaults.object(forKey: Keys.sessionRecorderEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.sessionRecorderEnabled)
        sessionRetention = decodeOrDefault(.lastN10, forKey: Keys.sessionRetention)
    }

    // MARK: - Encode helpers

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
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

    private func decodeSet<T: Decodable & Hashable & RawRepresentable>(
        _ type: T.Type,
        forKey key: String
    ) -> Set<T> where T.RawValue == String {
        guard let data = defaults.data(forKey: key),
              let array = try? decoder.decode([T].self, from: data) else { return [] }
        return Set(array)
    }
}
