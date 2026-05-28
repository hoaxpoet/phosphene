// EndedView — Shown when SessionManager.state == .ended.
//
// Per UX_SPEC §3.6 + line 948: "Reflection, not administration. Session
// duration and track count. 'New session' in coral. Should feel like house
// lights coming up gently."
//
// QR.4 (D-091): replaces the U.1 stub with a session-summary card +
// primary "Start another session" CTA + secondary "Open sessions folder".
// `sessionDuration` plumbing is deferred — `SessionManager` does not
// currently track a session-start timestamp, and adding it requires
// session-state changes outside QR.4 scope. Track count is sourced from
// the parent (`ContentView`); duration shows "—" with a TODO follow-up.
//
// GAP H (2026-05-28): when the session that just ended was a local-file
// session, surface a "Play <name> again" CTA between the primary and the
// tertiary. Reads the stashed `lastEndedLocalFileOrigin` from VisualizerEngine.
// Streaming sessions (and the very first launch) skip this CTA.

import AppKit
import Session
import SwiftUI

// MARK: - EndedView

@MainActor
struct EndedView: View {
    static let accessibilityID         = "phosphene.view.ended"
    static let newSessionButtonID      = "phosphene.ended.newSession"
    static let openFolderButtonID      = "phosphene.ended.openFolder"
    static let replayLocalFileButtonID = "phosphene.ended.replayLocalFile"

    let trackCount: Int
    let sessionDuration: TimeInterval?
    let onStartNewSession: () -> Void
    let onOpenSessionsFolder: () -> Void
    /// GAP H: stashed LF origin from the just-ended session, or `nil` when
    /// the ended session was streaming / ad-hoc. Drives the replay CTA.
    var lastLocalFileOrigin: SessionOrigin?
    /// GAP H: invoked when the user taps the replay CTA. Parent dispatches
    /// to the appropriate `LocalFileMenuCommands.openLocal*` method based
    /// on the origin kind.
    var onReplayLocalFile: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(String(localized: "ended.headline"))
                .font(.largeTitle)
                .fontWeight(.thin)
                .foregroundColor(.white)

            VStack(spacing: 6) {
                Text(formattedTrackCount)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.7))
                Text(formattedDuration)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer().frame(height: 8)

            VStack(spacing: 12) {
                Button(String(localized: "ended.cta.newSession")) {
                    onStartNewSession()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .tint(coralAccent)
                .accessibilityIdentifier(Self.newSessionButtonID)

                // GAP H (2026-05-28): LF replay CTA. Renders only when the
                // just-ended session was a local-file session AND a replay
                // closure was wired. Sits between primary (Start another)
                // and tertiary (Open sessions folder).
                if let replayLabel, let onReplayLocalFile {
                    Button {
                        onReplayLocalFile()
                    } label: {
                        Text(verbatim: replayLabel)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.7))
                    .font(.subheadline)
                    .accessibilityIdentifier(Self.replayLocalFileButtonID)
                }

                Button(String(localized: "ended.cta.openFolder")) {
                    onOpenSessionsFolder()
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.5))
                .font(.subheadline)
                .accessibilityIdentifier(Self.openFolderButtonID)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Formatting

    private var formattedTrackCount: String {
        String(format: String(localized: "ended.summary.tracks"), trackCount)
    }

    private var formattedDuration: String {
        guard let seconds = sessionDuration else {
            return String(format: String(localized: "ended.summary.duration"), "—")
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .dropLeading
        let formatted = formatter.string(from: seconds) ?? "—"
        return String(format: String(localized: "ended.summary.duration"), formatted)
    }

    // MARK: - Coral accent

    /// Coral CTA tint per UX_SPEC line 948. Falls back to system accent if the
    /// asset/token is not available — DashboardTokens lives in the renderer module
    /// and is not directly importable from PhospheneApp.
    private var coralAccent: Color {
        Color(red: 0.97, green: 0.45, blue: 0.36)
    }

    // MARK: - GAP H — Replay label

    /// Localized "Play X again" label resolved from the stashed LF origin.
    /// Returns `nil` when no LF replay is offered (streaming-ended sessions
    /// or first launch).
    private var replayLabel: String? {
        guard let origin = lastLocalFileOrigin else { return nil }
        switch origin {
        case .localFile(let url):
            return String(format: String(localized: "ended.cta.replay_named"),
                          url.lastPathComponent)
        case .localFolder(let folder, _):
            return String(format: String(localized: "ended.cta.replay_named"),
                          folder.lastPathComponent)
        case .localPlaylist(let playlist, _):
            return String(format: String(localized: "ended.cta.replay_named"),
                          playlist.lastPathComponent)
        case .localFiles(let urls):
            return String(format: String(localized: "ended.cta.replay_count"),
                          urls.count)
        case .playlist:
            return nil
        }
    }
}

// MARK: - Sessions folder helper

extension EndedView {
    /// Default opener for `~/Documents/phosphene_sessions/`. Creates the directory
    /// if it does not yet exist so Finder always has something to display.
    @MainActor
    static func openSessionsFolder() {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("phosphene_sessions")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(url)
    }
}
