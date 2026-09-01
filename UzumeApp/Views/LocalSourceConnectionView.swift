// LocalSourceConnectionView — Destination view for the Local Folder tile in
// ConnectorPickerView (GAP A, 2026-05-28). Sibling of AppleMusicConnectionView
// and SpotifyConnectionView; renders inside the picker's NavigationStack.
//
// Uzume reads three shapes of local source — single file, folder, or
// playlist (.m3u / .m3u8). Each gets its own action tile that opens the
// matching NSOpenPanel. The view also teaches the drag-and-drop affordance
// via a quiet footer line (the window-level .onDrop handler accepts files,
// folders, and playlists anywhere on the surface).
//
// Per the .impeccable.md design context:
// - Tiles are deliberately understated (no chevron — these are actions, not
//   navigation into a sub-flow). DS.2 moved them onto the shared
//   `SourceChoice` component; the `.action` affordance is what draws no chevron.
// - Drop hint is typographic, not iconic (no dashed rectangle).
// - Background stays dark; the visualizer is the product, this is supporting
//   chrome that dissolves when the session starts.

import SwiftUI

// MARK: - LocalSourceConnectionView

@MainActor
struct LocalSourceConnectionView: View {

    static let accessibilityID    = "uzume.view.lf_source"
    static let folderTileID       = "uzume.lf_source.tile.folder"
    static let fileTileID         = "uzume.lf_source.tile.file"
    static let playlistTileID     = "uzume.lf_source.tile.playlist"

    @EnvironmentObject private var engine: VisualizerEngine
    @EnvironmentObject private var recentsStore: LocalFileRecentsStore
    @EnvironmentObject private var errorStore: LocalFileErrorStore

    var body: some View {
        ZStack {
            UzumeAppColor.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(minHeight: 24)
                heading
                // GAP F (2026-05-28): inline error banner replaces NSAlert
                // modals for non-destructive LF errors (unsupported format,
                // unreadable, M3U parse failed, empty folder). Auto-clears
                // after 6 s; tap to dismiss.
                if let error = errorStore.lastError {
                    LocalFileErrorBanner(message: error.localizedMessage) {
                        errorStore.clear()
                    }
                    .padding(.top, 12)
                }
                Spacer().frame(height: 28)
                actionTiles
                Spacer()
                dropHint
                Spacer().frame(height: 28)
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle(String(localized: "lf_source.nav.title"))
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Sub-views

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "lf_source.headline"))
                .font(.title.weight(.medium))
                .foregroundColor(UzumeAppColor.textPrimary)
            Text(String(localized: "lf_source.subhead"))
                .font(.callout)
                .foregroundColor(UzumeAppColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionTiles: some View {
        VStack(spacing: 10) {
            SourceChoice(
                systemImage: "folder.fill",
                title: String(localized: "lf_source.tile.folder.title"),
                subtitle: String(localized: "lf_source.tile.folder.subtitle"),
                accessibilityID: Self.folderTileID,
                affordance: .action(openFolderPicker)
            )
            SourceChoice(
                systemImage: "waveform",
                title: String(localized: "lf_source.tile.file.title"),
                subtitle: String(localized: "lf_source.tile.file.subtitle"),
                accessibilityID: Self.fileTileID,
                affordance: .action(openFilePicker)
            )
            SourceChoice(
                systemImage: "music.note.list",
                title: String(localized: "lf_source.tile.playlist.title"),
                subtitle: String(localized: "lf_source.tile.playlist.subtitle"),
                accessibilityID: Self.playlistTileID,
                affordance: .action(openPlaylistPicker)
            )
        }
    }

    private var dropHint: some View {
        Text(String(localized: "lf_source.drop_hint"))
            .font(.caption)
            .foregroundColor(UzumeAppColor.textDisabled)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func openFolderPicker() {
        LocalFileMenuCommands.openLocalFolderPanel(engine: engine, recentsStore: recentsStore)
    }

    private func openFilePicker() {
        LocalFileMenuCommands.openLocalFilePanel(engine: engine, recentsStore: recentsStore)
    }

    private func openPlaylistPicker() {
        LocalFileMenuCommands.openLocalM3UPanel(engine: engine, recentsStore: recentsStore)
    }
}
