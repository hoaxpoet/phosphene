// SettingsTypes — Value types for all PhospheneApp settings (app-layer only).
//
// Engine-facing types (QualityCeiling, PresetCategory) live in PhospheneEngine.
// These types cover capture source, device tier override, motion preference, and retention.

import Foundation

// MARK: - CaptureMode

/// Where PhospheneApp captures audio from.
enum CaptureMode: String, Codable, CaseIterable, Sendable {
    /// System-wide audio mix (all apps). Default.
    case systemAudio
    /// A specific running application selected via SourceAppPicker.
    case specificApp
    /// A local audio file on disk. Coming later — shows informational toast on selection.
    case localFile
}

// MARK: - DeviceTierOverride

/// Lets advanced users force a device tier, overriding hardware detection.
enum DeviceTierOverride: String, Codable, CaseIterable, Sendable {
    /// Use hardware detection. Default.
    case auto
    /// Force M1/M2 tier regardless of actual GPU family.
    case forceTier1
    /// Force M3/M4 tier regardless of actual GPU family.
    case forceTier2
}

// MARK: - ReducedMotionPreference

/// Controls whether feedback warp and beat-pulse animations are suppressed.
enum ReducedMotionPreference: String, Codable, CaseIterable, Sendable {
    /// Mirror the system Accessibility > Reduce Motion toggle. Default.
    case matchSystem
    /// Always suppress warp feedback and cap beat-pulse amplitude.
    case alwaysOn
    /// Always allow full motion regardless of system setting.
    case alwaysOff
}

// MARK: - SessionRetentionPolicy

/// How many session recording folders to keep in ~/Documents/phosphene_sessions/.
enum SessionRetentionPolicy: String, Codable, CaseIterable, Sendable {
    /// Keep the 10 most recent sessions. Default.
    case lastN10
    /// Keep the 25 most recent sessions.
    case lastN25
    /// Keep all sessions (no automatic deletion).
    case keepAll
    /// Delete sessions older than 24 hours.
    case oneDay
    /// Delete sessions older than 7 days.
    case oneWeek
}

// MARK: - SourceAppOverride

/// Identifies a specific application selected as the audio capture source.
struct SourceAppOverride: Codable, Equatable, Hashable, Sendable {
    let bundleIdentifier: String
    let displayName: String
}
