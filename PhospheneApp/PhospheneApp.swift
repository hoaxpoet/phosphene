import SwiftUI

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
@main
struct PhospheneApp: App {
    @StateObject private var engine = VisualizerEngine()
    @StateObject private var permissionMonitor = PermissionMonitor()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var accessibilityState = AccessibilityState()

    init() {
        // Migrate legacy UserDefaults keys to the phosphene.settings.* scheme.
        SettingsMigrator.migrate()
        // Prune old session folders according to the persisted retention policy.
        // Read the key directly to avoid a second SettingsStore allocation before @StateObject init.
        let rawPolicy = UserDefaults.standard.string(forKey: "phosphene.settings.diagnostics.sessionRetention")
        let policy = SessionRetentionPolicy(rawValue: rawPolicy ?? "") ?? .lastN10
        SessionRecorderRetentionPolicy.apply(policy: policy)
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
        }
    }
}
