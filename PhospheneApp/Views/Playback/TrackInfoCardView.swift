// TrackInfoCardView — Top-left overlay card showing track + preset + orchestrator state.

import AppKit
import SwiftUI

// MARK: - TrackInfoCardView

/// Displays the current track title, artist, active preset name, and orchestrator mode.
///
/// Sits top-leading on `PlaybackChromeView` with a 24 pt inset. Applies
/// `OverlayBackdropStyle` for contrast guarantee.
///
/// LF.6: adds a leading 48 × 48 pt artwork slot that renders the LF.5
/// persistent-cache artwork bytes when present, or a restrained local-file
/// glyph fallback. The slot is hidden entirely for streaming sessions that
/// have no artwork (text-only chrome unchanged) — once LF.6.streaming wires
/// up streaming-path artwork, the same slot renders for those sessions too.
struct TrackInfoCardView: View {

    static let accessibilityID = "phosphene.playback.trackInfoCard"
    static let artworkSlotID   = "phosphene.playback.trackInfoCard.artwork"

    let trackInfo: TrackInfoDisplay?
    let preset: PresetDisplay?
    let orchestratorState: OrchestratorDisplayState
    /// LF.6: true when the active session is a local-file playback. Drives
    /// whether the artwork slot renders the fallback glyph (LF — distinctive
    /// chrome geometry) or hides entirely (streaming — text-only fallback
    /// matches pre-LF.6 chrome until LF.6.streaming wires URL-fetched art).
    var isLocalFileSession: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showArtworkSlot {
                artworkSlot
            }
            textColumn
        }
        .padding(12)
        .frame(minWidth: 200, maxWidth: 380, alignment: .leading)
        .overlayBackdrop()
        .accessibilityIdentifier(Self.accessibilityID)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            AccessibilityLabels.trackInfoCardLabel(
                title: trackInfo?.title,
                artist: trackInfo?.artist,
                preset: preset?.name
            )
        )
        .accessibilityHint(String(localized: "a11y.trackInfoCard.hint"))
    }

    // MARK: - Subviews

    /// Show the artwork slot whenever we have bytes to render OR the active
    /// session is local-file (where the restrained fallback glyph stands in
    /// for missing embedded artwork). Streaming sessions with no bytes
    /// collapse to the text-only chrome — no out-of-place glyph.
    private var showArtworkSlot: Bool {
        trackInfo?.albumArtData != nil || isLocalFileSession
    }

    @ViewBuilder
    private var artworkSlot: some View {
        Group {
            if let data = trackInfo?.albumArtData,
               let image = AlbumArtworkCache.image(for: data, cacheKey: artworkCacheKey) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                fallbackGlyph
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier(Self.artworkSlotID)
        .accessibilityHidden(true)
    }

    /// Cache key for `AlbumArtworkCache`. `title|artist` is unique enough at
    /// LF.5's content-hashed cache layer (the bytes come from a stable
    /// `local:sha256:` entry); two LF tracks can't collide unless their tags
    /// are byte-identical, which would also mean their visual identity is.
    private var artworkCacheKey: String {
        (trackInfo?.title ?? "") + "|" + (trackInfo?.artist ?? "")
    }

    @ViewBuilder
    private var fallbackGlyph: some View {
        ZStack {
            Color.white.opacity(0.07)
            Image(systemName: "music.note.list")
                .font(.title2)
                .foregroundColor(.white.opacity(0.40))
        }
    }

    @ViewBuilder
    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Track title
            Text(trackInfo?.title ?? "—")
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)

            // Artist
            if let artist = trackInfo?.artist, !artist.isEmpty {
                Text(artist)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer().frame(height: 4)

            // Preset name
            if let name = preset?.name {
                Text(name)
                    .font(.caption2.monospaced())
                    .italic()
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }

            // Orchestrator state pill
            orchestratorStatePill
        }
    }

    @ViewBuilder
    private var orchestratorStatePill: some View {
        let label = orchestratorState.rawValue
        let color: Color = orchestratorState == .planned ? .green.opacity(0.7) : .orange.opacity(0.7)
        Text(label)
            .font(.caption2.weight(.semibold).monospaced())
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}
