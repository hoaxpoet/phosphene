// ConnectorPickerViewModel — Observes Apple Music running state for ConnectorPickerView.
//
// PRE-FLIGHT AUDIT NOTES (U.3):
// - No pre-existing NSWorkspace observers for com.apple.Music; safe to add new ones here.
// - NSWorkspace delivers notifications on its own internal queue (not MainActor).
//   All mutations hop to @MainActor via Task { @MainActor in ... }.
// - Debounce at 250ms suppresses transient running-state flicker during Apple Music launch.
// - localFolderEnabled is false in v1; ENABLE_LOCAL_FOLDER_CONNECTOR compile flag gates it.

import AppKit
import Combine

// MARK: - ConnectorPickerViewModel

@MainActor
final class ConnectorPickerViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var appleMusicRunning: Bool = false

    /// Drives `ConnectorPickerView`'s `NavigationStack`. The tiles push via
    /// `NavigationLink(value:)`; the cross-links ("Use Apple Music instead" /
    /// "Use Spotify instead") call `switchConnector(to:)` to replace the pushed
    /// flow in place (CLEAN.2.3.1 — these were no-op `{ }` handlers before).
    @Published var connectorPath: [ConnectorType] = []

    /// Whether the Local Folder connector tile is enabled.
    let localFolderEnabled: Bool = false

    // MARK: - Private

    // nonisolated(unsafe) allows deinit (nonisolated) to call removeObserver without
    // crossing the @MainActor boundary. These are only written once at init and read once
    // at deinit, so no concurrent access can occur.
    nonisolated(unsafe) private var launchObserver: Any?
    nonisolated(unsafe) private var terminateObserver: Any?
    private var debounceTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        appleMusicRunning = Self.isMusicRunning()
        setupWorkspaceObservers()
    }

    deinit {
        if let obs = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let obs = terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    // MARK: - Actions

    func openAppleMusic() {
        if let url = URL(string: "music://") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Replaces the currently pushed connector flow with `type` — backs the
    /// "Use Apple Music / Spotify instead" cross-links so they actually switch
    /// connectors instead of dismissing or no-op'ing.
    func switchConnector(to type: ConnectorType) {
        connectorPath = [type]
    }

    // MARK: - Private

    private static func isMusicRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter

        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard
                let info = note.userInfo,
                let app  = info[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == "com.apple.Music"
            else { return }
            Task { @MainActor [weak self] in
                self?.scheduleUpdate(running: true)
            }
        }

        terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard
                let info = note.userInfo,
                let app  = info[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == "com.apple.Music"
            else { return }
            Task { @MainActor [weak self] in
                self?.scheduleUpdate(running: false)
            }
        }
    }

    private func scheduleUpdate(running: Bool) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.appleMusicRunning = running
        }
    }
}
