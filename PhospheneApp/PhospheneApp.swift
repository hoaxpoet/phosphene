import Foundation
import Renderer
import SwiftUI
import os.log

private let lfLogger = Logger(subsystem: "com.phosphene.app", category: "LF1")

/// Phosphene application entry point.
///
/// Creates a single window containing the Metal-backed visualizer.
/// `VisualizerEngine` is the primary long-lived object — it owns the render
/// loop, audio capture, ML pipelines, and the `SessionManager`. `ContentView`
/// routes to the correct top-level view based on `SessionManager.state`.
///
/// `AccessibilityState` (U.9) is a `@StateObject` here so it can observe
/// `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` independently
/// of the settings store. `PhospheneApp.body` wires the two together via `.task`
/// (subscribes to `settingsStore.$reducedMotion`) and `.onChange` (pushes engine
/// flags on state change).
///
/// `spotifyOAuth` (U.11) is a long-lived actor that owns the Spotify OAuth
/// Authorization Code + PKCE token lifecycle. It is created once here and passed
/// to `ConnectorPickerView` via environment injection. The `.onOpenURL` modifier
/// routes `phosphene://spotify-callback` redirects back to the actor.
@main
struct PhospheneApp: App {
    @StateObject private var engine = VisualizerEngine()
    @StateObject private var permissionMonitor = PermissionMonitor()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var accessibilityState = AccessibilityState()

    /// Long-lived Spotify OAuth actor — not `@StateObject` because actors are not
    /// `ObservableObject`; stored as a plain `let` since `PhospheneApp` is `@MainActor`.
    private let spotifyOAuth = SpotifyOAuthTokenProvider.makeLive()

    init() {
        // Migrate legacy UserDefaults keys to the phosphene.settings.* scheme.
        SettingsMigrator.migrate()
        // Prune old session folders according to the persisted retention policy.
        // Read the key directly to avoid a second SettingsStore allocation before @StateObject init.
        let rawPolicy = UserDefaults.standard.string(forKey: "phosphene.settings.diagnostics.sessionRetention")
        let policy = SessionRetentionPolicy(rawValue: rawPolicy ?? "") ?? .lastN10
        SessionRecorderRetentionPolicy.apply(policy: policy)
        // Register Epilogue + Clash Display from the Renderer bundle so the
        // SwiftUI dashboard can resolve them via `.custom(_:size:)`. Falls back
        // silently to system fonts if the TTF/OTF files aren't bundled
        // (DASH.7.1, D-088). Idempotent — safe to call repeatedly.
        _ = DashboardFontLoader.resolveFonts(in: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: SessionStateViewModel(
                    sessionManager: engine.sessionManager,
                    accessibilityState: accessibilityState
                )
            )
            .environmentObject(engine)
            .environmentObject(permissionMonitor)
            .environmentObject(settingsStore)
            .environmentObject(accessibilityState)
            // Inject the OAuth provider so ConnectorPickerView can build SpotifyConnectionViewModel.
            .environment(\.spotifyOAuthProvider, spotifyOAuth)
            // Wire SettingsStore preference → AccessibilityState on every change.
            .task {
                accessibilityState.applyPreference(settingsStore.reducedMotion)
                for await pref in settingsStore.$reducedMotion.values {
                    accessibilityState.applyPreference(pref)
                }
            }
            // Push accessibility flags into the engine whenever state changes.
            .onChange(of: accessibilityState.reduceMotion) { _, reduce in
                engine.applyAccessibility(
                    reduceMotion: reduce,
                    beatAmplitudeScale: accessibilityState.beatAmplitudeScale
                )
            }
            // Push uncertified-presets preference into the engine so reactive mode
            // honours the setting without requiring a SettingsStore dependency in the engine.
            .task {
                engine.applyShowUncertifiedPresets(settingsStore.showUncertifiedPresets)
                for await value in settingsStore.$showUncertifiedPresets.values {
                    engine.applyShowUncertifiedPresets(value)
                }
            }
            // Route phosphene://spotify-callback back to the OAuth actor.
            .onOpenURL { url in
                guard url.scheme == "phosphene", url.host == "spotify-callback" else { return }
                Task { await spotifyOAuth.handleCallback(url: url) }
            }
            // LF.1 / LF.2 — Local-file playback hook. When the
            // `PHOSPHENE_LOCAL_FILE_PLAYBACK` env var points at a readable
            // audio file, bypass the normal IdleView → SessionManager flow
            // and play the file directly via AVAudioEngine. LF.2 (2026-05-27)
            // upgrades the launch path to run offline pre-analysis on the
            // file BEFORE starting audio, so BeatGrid + StemFeatures are
            // installed from frame 0 (no ~10 s live-analyzer warmup gap).
            // Empty / absent / unreadable env var: no log, normal launch
            // proceeds.
            //
            // LF.1.5 — Process-tap autostart hook (dev-only, env-var-gated).
            // When `PHOSPHENE_AUTOSTART_ADHOC=1` is set AND the LF env var is
            // NOT, fire the same code path IdleView's "Start listening now"
            // button uses. Makes the LF-vs-tap A/B reproducible without a
            // manual UI click. LF env var takes precedence.
            .task {
                let env = ProcessInfo.processInfo.environment
                if let raw = env["PHOSPHENE_LOCAL_FILE_PLAYBACK"], !raw.isEmpty {
                    let url = URL(fileURLWithPath: raw)
                    guard FileManager.default.isReadableFile(atPath: url.path) else { return }
                    lfLogger.info("[LF.2] local-file playback mode: \(url.path, privacy: .public)")
                    await engine.prepareAndStartLocalFilePlayback(url: url)
                    return
                }
                if env["PHOSPHENE_AUTOSTART_ADHOC"] == "1" {
                    lfLogger.info("[LF.1.5] autostart ad-hoc session (PHOSPHENE_AUTOSTART_ADHOC=1)")
                    engine.sessionManager.startAdHocSession()
                }
            }
        }
    }
}

// MARK: - EnvironmentKey for SpotifyOAuthTokenProvider

private struct SpotifyOAuthProviderKey: EnvironmentKey {
    static let defaultValue: SpotifyOAuthTokenProvider? = nil
}

extension EnvironmentValues {
    /// The app-level Spotify OAuth token provider, set by `PhospheneApp`.
    var spotifyOAuthProvider: SpotifyOAuthTokenProvider? {
        get { self[SpotifyOAuthProviderKey.self] }
        set { self[SpotifyOAuthProviderKey.self] = newValue }
    }
}
