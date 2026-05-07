// SettingsViewModel — Observable facade over SettingsStore for the Settings sheet.
//
// Views bind to SettingsViewModel, not directly to SettingsStore, for testability.
// Exposes Binding<T> adapters, disabled-state flags, and non-setting actions.

import AppKit
import Combine
import Foundation
import Orchestrator
import Presets
import Shared
import SwiftUI

// MARK: - AboutSectionData

/// Read-only system info for the About tab.
struct AboutSectionData: Sendable {
    let appVersion: String
    let buildNumber: String
    let macOSVersion: String
    let gpuFamily: String

    static func current() -> AboutSectionData {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let gpu = MTLCreateSystemDefaultDevice()?.name ?? "Unknown GPU"
        return AboutSectionData(
            appVersion: version,
            buildNumber: build,
            macOSVersion: os,
            gpuFamily: gpu
        )
    }

    /// Plaintext summary suitable for copying to the clipboard.
    var debugInfo: String {
        """
        Phosphene \(appVersion) (\(buildNumber))
        macOS: \(macOSVersion)
        GPU: \(gpuFamily)
        """
    }
}

// MARK: - SettingsViewModel

/// Observable facade over SettingsStore. Owns no persistent state itself.
@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Store reference

    let store: SettingsStore

    // MARK: - About

    let about: AboutSectionData

    // MARK: - Disabled-state flags (dormant features)

    /// True until Phase MD (Milkdrop ingestion) ships. UI shows the toggle but disables it.
    let includeMilkdropPresetsDisabled: Bool = true

    // MARK: - Init

    init(store: SettingsStore, about: AboutSectionData = .current()) {
        self.store = store
        self.about = about
    }

    // MARK: - Bindings (forwarded to store)

    var captureMode: CaptureMode {
        get { store.captureMode }
        set { store.captureMode = newValue }
    }

    var sourceAppOverride: SourceAppOverride? {
        get { store.sourceAppOverride }
        set { store.sourceAppOverride = newValue }
    }

    var deviceTierOverride: DeviceTierOverride {
        get { store.deviceTierOverride }
        set { store.deviceTierOverride = newValue }
    }

    var qualityCeiling: QualityCeiling {
        get { store.qualityCeiling }
        set { store.qualityCeiling = newValue }
    }

    #if DEBUG
    /// QR.4 / D-091: persistence retained so DEBUG users round-trip their state,
    /// but the UI surface is gated on `#if DEBUG` until Phase MD ships.
    var includeMilkdropPresets: Bool {
        get { store.includeMilkdropPresets }
        set { store.includeMilkdropPresets = newValue }
    }
    #endif

    var reducedMotion: ReducedMotionPreference {
        get { store.reducedMotion }
        set { store.reducedMotion = newValue }
    }

    var excludedPresetCategories: Set<PresetCategory> {
        get { store.excludedPresetCategories }
        set { store.excludedPresetCategories = newValue }
    }

    var showLiveAdaptationToasts: Bool {
        get { store.showLiveAdaptationToasts }
        set { store.showLiveAdaptationToasts = newValue }
    }

    var showUncertifiedPresets: Bool {
        get { store.showUncertifiedPresets }
        set { store.showUncertifiedPresets = newValue }
    }

    var sessionRecorderEnabled: Bool {
        get { store.sessionRecorderEnabled }
        set { store.sessionRecorderEnabled = newValue }
    }

    var sessionRetention: SessionRetentionPolicy {
        get { store.sessionRetention }
        set { store.sessionRetention = newValue }
    }

    // showPerformanceWarnings was deleted in QR.4 / D-091. The dashboard PERF
    // card already surfaces frame-budget overruns; a separate toast was redundant.

    // MARK: - Actions

    /// Opens ~/Documents/phosphene_sessions/ in Finder.
    func openSessionsFolder() {
        let sessions = sessionsDirectoryURL
        // Create directory if it doesn't exist so Finder has something to open.
        let fm = FileManager.default
        if !fm.fileExists(atPath: sessions.path) {
            try? fm.createDirectory(at: sessions, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(sessions)
    }

    /// Clears all onboarding state. Takes effect on next app launch.
    func resetOnboarding() {
        store.resetOnboarding()
    }

    /// Copies system debug info (no audio data) to the pasteboard.
    func copyDebugInfo() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(about.debugInfo, forType: .string)
    }

    // MARK: - Private

    private var sessionsDirectoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("phosphene_sessions")
    }
}

// MARK: - Metal import

import Metal
