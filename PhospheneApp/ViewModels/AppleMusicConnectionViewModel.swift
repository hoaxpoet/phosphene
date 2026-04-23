// AppleMusicConnectionViewModel — State machine for the Apple Music connection flow.
//
// PRE-FLIGHT AUDIT NOTES (U.3):
// - connect() is `async throws -> [TrackIdentity]`, not the 5-case Result enum UX_SPEC assumed.
// - Error mapping:
//     .appleMusicNotRunning   → .notRunning (no retry)
//     [] (empty tracks)       → .noCurrentPlaylist (2s auto-retry)
//     .parseFailure           → .error — permission denied is INDISTINGUISHABLE from no
//                               playlist because AppleScript silently returns nil for both
//                               error -1728 (no track) and -1743 (automation denied). Both
//                               produce an empty array; the connector does not throw.
//     other error             → .error(localizedDescription)
// - TODO(U.3-followup): Extend PlaylistConnectorError with .noCurrentPlaylist and
//   .permissionDenied for proper error distinguishment. Add -1743 detection in connector.

import AppKit
import Combine
import Foundation
import Session

// MARK: - AppleMusicConnectionState

enum AppleMusicConnectionState: Equatable {
    /// View just appeared; connection not yet started.
    case idle
    /// Connecting in progress.
    case connecting
    /// Apple Music is running but no playlist is loaded; auto-retrying every 2 s.
    case noCurrentPlaylist
    /// Apple Music is not running.
    case notRunning
    /// AppleScript Automation permission denied (shown only when detected via
    /// a secondary probe; in practice maps to .noCurrentPlaylist in U.3).
    case permissionDenied
    /// Unrecoverable error; message is user-facing.
    case error(String)
    /// Connection succeeded; the track count is informational only.
    case connected(trackCount: Int)
}

// MARK: - AppleMusicConnectionViewModel

@MainActor
final class AppleMusicConnectionViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: AppleMusicConnectionState = .idle

    // MARK: - Dependencies

    private let connector: any PlaylistConnecting
    private let delayProvider: any DelayProviding

    // MARK: - Init

    init(
        connector: any PlaylistConnecting = PlaylistConnector(),
        delayProvider: any DelayProviding = RealDelay()
    ) {
        self.connector = connector
        self.delayProvider = delayProvider
    }

    // MARK: - Actions

    /// Begin the Apple Music connection attempt. Call this from the view's `.onAppear`.
    func beginConnect() {
        guard state == .idle else { return }
        performConnect()
    }

    /// Cancel any in-flight connection and retry. Used by "Try again" CTAs.
    func retry() {
        retryTask?.cancel()
        connectionTask?.cancel()
        state = .idle
        performConnect()
    }

    /// Called from the view when the user taps "Open Apple Music".
    func openAppleMusic() {
        if let url = URL(string: "music://") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens System Settings → Privacy → Automation.
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private

    private var connectionTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    private func performConnect() {
        connectionTask?.cancel()
        connectionTask = Task { [weak self] in
            await self?.runConnect()
        }
    }

    private func runConnect() async {
        state = .connecting
        do {
            let tracks = try await connector.connect(source: .appleMusicCurrentPlaylist)
            if Task.isCancelled { return }
            if tracks.isEmpty {
                state = .noCurrentPlaylist
                scheduleAutoRetry()
            } else {
                state = .connected(trackCount: tracks.count)
            }
        } catch PlaylistConnectorError.appleMusicNotRunning {
            guard !Task.isCancelled else { return }
            state = .notRunning
        } catch {
            guard !Task.isCancelled else { return }
            state = .error(userMessage(for: error))
        }
    }

    private func scheduleAutoRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await self?.delayProvider.sleep(seconds: 2)
            guard !Task.isCancelled else { return }
            guard let self, case .noCurrentPlaylist = self.state else { return }
            self.performConnect()
        }
    }

    func cancelRetry() {
        retryTask?.cancel()
        connectionTask?.cancel()
    }

    private func userMessage(for error: Error) -> String {
        switch error {
        case PlaylistConnectorError.networkFailure(let msg):
            return "Something went wrong talking to Apple Music. \(msg)"
        case PlaylistConnectorError.parseFailure:
            return "Something went wrong reading the Apple Music playlist."
        default:
            return "Something went wrong talking to Apple Music."
        }
    }
}
