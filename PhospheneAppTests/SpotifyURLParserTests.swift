// SpotifyURLParserTests — 12 unit tests covering valid and invalid Spotify URLs/URIs.

import Testing
@testable import PhospheneApp

@Suite("SpotifyURLParser")
struct SpotifyURLParserTests {

    // MARK: - Valid playlist URLs

    @Test("canonical HTTPS playlist URL")
    func canonicalHTTPS() {
        let result = SpotifyURLParser.parse("https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M")
        #expect(result == .playlist(id: "37i9dQZF1DXcBWIGoYBM5M"))
    }

    @Test("HTTPS playlist URL with si share token")
    func httpsWithShareToken() {
        let result = SpotifyURLParser.parse("https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc123")
        #expect(result == .playlist(id: "37i9dQZF1DXcBWIGoYBM5M"))
    }

    @Test("spotify: URI scheme")
    func spotifyURIScheme() {
        let result = SpotifyURLParser.parse("spotify:playlist:37i9dQZF1DXcBWIGoYBM5M")
        #expect(result == .playlist(id: "37i9dQZF1DXcBWIGoYBM5M"))
    }

    @Test("leading and trailing whitespace stripped")
    func leadingTrailingWhitespace() {
        let result = SpotifyURLParser.parse("  https://open.spotify.com/playlist/abc123  ")
        #expect(result == .playlist(id: "abc123"))
    }

    @Test("leading @ paste artifact")
    func leadingAtPasteArtifact() {
        let result = SpotifyURLParser.parse("@https://open.spotify.com/playlist/abc123")
        #expect(result == .playlist(id: "abc123"))
    }

    // MARK: - Non-playlist Spotify content (rejected kinds)

    @Test("Spotify track URL → .track")
    func spotifyTrackURL() {
        let result = SpotifyURLParser.parse("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC")
        #expect(result == .track(id: "4uLU6hMCjMI75M1A2tKUQC"))
    }

    @Test("Spotify album URL → .album")
    func spotifyAlbumURL() {
        let result = SpotifyURLParser.parse("https://open.spotify.com/album/6dVIqQ8qmQ5GBnJ9shOYss")
        #expect(result == .album(id: "6dVIqQ8qmQ5GBnJ9shOYss"))
    }

    @Test("Spotify artist URL → .artist")
    func spotifyArtistURL() {
        let result = SpotifyURLParser.parse("https://open.spotify.com/artist/0du5cEVh5yTK9QJze8zA0C")
        #expect(result == .artist(id: "0du5cEVh5yTK9QJze8zA0C"))
    }

    @Test("Spotify podcast show URL → .invalid")
    func spotifyPodcastShowURL() {
        let result = SpotifyURLParser.parse("https://open.spotify.com/show/2mVVjNmBMa")
        #expect(result == .invalid)
    }

    @Test("Spotify podcast episode URL → .invalid")
    func spotifyPodcastEpisodeURL() {
        let result = SpotifyURLParser.parse("https://open.spotify.com/episode/5Xt5705qQGiX6nfMFSBR4V")
        #expect(result == .invalid)
    }

    @Test("garbage string → .invalid")
    func garbageString() {
        let result = SpotifyURLParser.parse("not a url at all!!")
        #expect(result == .invalid)
    }

    @Test("empty string → .invalid")
    func emptyString() {
        let result = SpotifyURLParser.parse("")
        #expect(result == .invalid)
    }
}
