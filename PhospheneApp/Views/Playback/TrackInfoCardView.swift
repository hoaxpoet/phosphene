// TrackInfoCardView — Top-left overlay card showing track + preset + orchestrator state.

import SwiftUI

// MARK: - TrackInfoCardView

/// Displays the current track title, artist, active preset name, and orchestrator mode.
///
/// Sits top-leading on `PlaybackChromeView` with a 24 pt inset. Applies
/// `OverlayBackdropStyle` for contrast guarantee.
struct TrackInfoCardView: View {

    static let accessibilityID = "phosphene.playback.trackInfoCard"

    let trackInfo: TrackInfoDisplay?
    let preset: PresetDisplay?
    let orchestratorState: OrchestratorDisplayState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Track title
            Text(trackInfo?.title ?? "—")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            // Artist
            if let artist = trackInfo?.artist, !artist.isEmpty {
                Text(artist)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer().frame(height: 4)

            // Preset name
            if let name = preset?.name {
                Text(name)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .italic()
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }

            // Orchestrator state pill
            orchestratorStatePill
        }
        .padding(12)
        .frame(minWidth: 200, maxWidth: 320, alignment: .leading)
        .overlayBackdrop()
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var orchestratorStatePill: some View {
        let label = orchestratorState.rawValue
        let color: Color = orchestratorState == .planned ? .green.opacity(0.7) : .orange.opacity(0.7)
        Text(label)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}
