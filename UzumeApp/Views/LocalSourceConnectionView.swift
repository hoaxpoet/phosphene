// LocalSourceConnectionView — Destination view for the Local Folder tile in
// ConnectorPickerView (GAP A, 2026-05-28). Sibling of AppleMusicConnectionView
// and SpotifyConnectionView; renders inside the picker's NavigationStack.
//
// Phosphene reads three shapes of local source — single file, folder, or
// playlist (.m3u / .m3u8). Each gets its own action tile that opens the
// matching NSOpenPanel. The view also teaches the drag-and-drop affordance
// via a quiet footer line (the window-level .onDrop handler accepts files,
// folders, and playlists anywhere on the surface).
//
// Per the .impeccable.md design context:
// - Tiles are deliberately understated (no chevron — these are actions, not
//   navigation into a sub-flow).
// - Drop hint is typographic, not iconic (no dashed rectangle).
// - Background stays dark; the visualizer is the product, this is supporting
//   chrome that dissolves when the session starts.

import SwiftUI

// MARK: - LocalSourceConnectionView

@MainActor
struct LocalSourceConnectionView: View {

    static let accessibilityID    = "phosphene.view.lf_source"
    static let folderTileID       = "phosphene.lf_source.tile.folder"
    static let fileTileID         = "phosphene.lf_source.tile.file"
    static let playlistTileID     = "phosphene.lf_source.tile.playlist"

    @EnvironmentObject private var engine: VisualizerEngine
    @EnvironmentObject private var recentsStore: LocalFileRecentsStore
    @EnvironmentObject private var errorStore: LocalFileErrorStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.white)
            Text(String(localized: "lf_source.subhead"))
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionTiles: some View {
        VStack(spacing: 10) {
            LocalSourceActionTile(
                systemImage: "folder.fill",
                title: String(localized: "lf_source.tile.folder.title"),
                subtitle: String(localized: "lf_source.tile.folder.subtitle"),
                accessibilityID: Self.folderTileID,
                action: openFolderPicker
            )
            LocalSourceActionTile(
                systemImage: "waveform",
                title: String(localized: "lf_source.tile.file.title"),
                subtitle: String(localized: "lf_source.tile.file.subtitle"),
                accessibilityID: Self.fileTileID,
                action: openFilePicker
            )
            LocalSourceActionTile(
                systemImage: "music.note.list",
                title: String(localized: "lf_source.tile.playlist.title"),
                subtitle: String(localized: "lf_source.tile.playlist.subtitle"),
                accessibilityID: Self.playlistTileID,
                action: openPlaylistPicker
            )
        }
    }

    private var dropHint: some View {
        Text(String(localized: "lf_source.drop_hint"))
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.32))
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

// MARK: - LocalSourceActionTile

/// Local action tile — visually consistent with `ConnectorTileView` but
/// without a chevron (these tiles trigger actions, not navigation). Used
/// only inside `LocalSourceConnectionView`; not promoted to a shared
/// component until a second consumer appears.
private struct LocalSourceActionTile: View {

    let systemImage: String
    let title: String
    let subtitle: String
    let accessibilityID: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isHovered ? 0.10 : 0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier(accessibilityID)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title). \(subtitle)"))
    }
}
