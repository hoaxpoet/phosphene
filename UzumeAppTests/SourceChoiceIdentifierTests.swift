// SourceChoiceIdentifierTests — pins the six source-tile accessibility
// identifiers. (DS.2)
//
// DS.2 consolidated the two former tile implementations into `SourceChoice`
// (D-233). Nothing pinned these strings before, and a consolidation
// is exactly the change that silently renames one: the connector three are built
// by interpolating `ConnectorType.rawValue` onto a prefix, so a rawValue edit
// moves them without touching any view. Following the D-044 / U.1 structural
// pattern — no rendering required.

import Testing
@testable import UzumeApp

// MARK: - SourceChoiceIdentifierTests

@Suite("SourceChoice identifiers")
@MainActor
struct SourceChoiceIdentifierTests {

    // MARK: - Connector tiles (ConnectorPickerView)

    @Test func connectorTilePrefix_isUnchanged() {
        #expect(ConnectorPickerView.tileIDPrefix == "uzume.connector.tile")
    }

    @Test func appleMusicTile_hasExpectedID() {
        #expect(identifier(for: .appleMusic) == "uzume.connector.tile.apple_music")
    }

    @Test func spotifyTile_hasExpectedID() {
        #expect(identifier(for: .spotify) == "uzume.connector.tile.spotify")
    }

    @Test func localFolderTile_hasExpectedID() {
        #expect(identifier(for: .localFolder) == "uzume.connector.tile.local_folder")
    }

    // MARK: - Local source tiles (LocalSourceConnectionView)

    @Test func folderTile_hasExpectedID() {
        #expect(LocalSourceConnectionView.folderTileID == "uzume.lf_source.tile.folder")
    }

    @Test func fileTile_hasExpectedID() {
        #expect(LocalSourceConnectionView.fileTileID == "uzume.lf_source.tile.file")
    }

    @Test func playlistTile_hasExpectedID() {
        #expect(LocalSourceConnectionView.playlistTileID == "uzume.lf_source.tile.playlist")
    }

    // MARK: - Helpers

    /// Rebuilds an identifier exactly as `ConnectorPickerView.tile(for:affordance:)`
    /// does, so a change to either half — the prefix or the rawValue — fails here.
    private func identifier(for type: ConnectorType) -> String {
        "\(ConnectorPickerView.tileIDPrefix).\(type.rawValue)"
    }
}
