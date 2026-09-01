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
    static let accessibilityID         = "uzume.view.ended"
    static let newSessionButtonID      = "uzume.ended.newSession"
    static let openFolderButtonID      = "uzume.ended.openFolder"
    static let replayLocalFileButtonID = "uzume.ended.replayLocalFile"

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
                .foregroundColor(UzumeAppColor.textPrimary)

            VStack(spacing: 6) {
                Text(formattedTrackCount)
                    .font(.body)
                    .foregroundColor(UzumeAppColor.textSecondary)
                Text(formattedDuration)
                    .font(.body)
                    .foregroundColor(UzumeAppColor.textTertiary)
            }

            Spacer().frame(height: 8)

            VStack(spacing: 12) {
                Button(String(localized: "ended.cta.newSession")) {
                    onStartNewSession()
                }
                .buttonStyle(.borderedProminent)
                .uzumeTint()
                .keyboardShortcut(.defaultAction)
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
                    .foregroundColor(UzumeAppColor.textSecondary)
                    .font(.subheadline)
                    .accessibilityIdentifier(Self.replayLocalFileButtonID)
                }

                Button(String(localized: "ended.cta.openFolder")) {
                    onOpenSessionsFolder()
                }
                .buttonStyle(.plain)
                .foregroundColor(UzumeAppColor.textTertiary)
                .font(.subheadline)
                .accessibilityIdentifier(Self.openFolderButtonID)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UzumeAppColor.canvas)
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
    /// Default opener for `~/Documents/uzume_sessions/`. Creates the directory
    /// if it does not yet exist so Finder always has something to display.
    @MainActor
    static func openSessionsFolder() {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("uzume_sessions")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(url)
    }
}
