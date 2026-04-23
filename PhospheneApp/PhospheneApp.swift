import SwiftUI

/// Phosphene application entry point.
///
/// Creates a single window containing the Metal-backed visualizer.
/// `VisualizerEngine` is the primary long-lived object — it owns the render
/// loop, audio capture, ML pipelines, and the `SessionManager`. `ContentView`
/// routes to the correct top-level view based on `SessionManager.state`.
@main
struct PhospheneApp: App {
    @StateObject private var engine = VisualizerEngine()
    @StateObject private var permissionMonitor = PermissionMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: SessionStateViewModel(sessionManager: engine.sessionManager)
            )
            .environmentObject(engine)
            .environmentObject(permissionMonitor)
        }
    }
}
