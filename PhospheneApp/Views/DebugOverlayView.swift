// DebugOverlayView — Metadata debug overlay showing current track info
// and pre-fetched profile data. Toggle with 'D' key.

import Shared
import SwiftUI

// MARK: - DebugOverlayView

/// Translucent overlay displaying track metadata and pre-fetched profile.
///
/// Shown in the bottom-leading corner. Displays:
/// - Track title, artist, album (from Now Playing)
/// - BPM, key, energy, valence, danceability (from pre-fetched profile)
/// - Metadata source and fetch status
struct DebugOverlayView: View {
    @ObservedObject var engine: VisualizerEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            Text("METADATA DEBUG")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            Divider().background(.white.opacity(0.3))

            // Track info
            if let track = engine.currentTrack {
                label("Title", track.title ?? "—")
                label("Artist", track.artist ?? "—")
                label("Album", track.album ?? "—")
                if let duration = track.duration {
                    label("Duration", formatDuration(duration))
                }
                label("Source", track.source.rawValue)
            } else {
                Text("No track detected")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Pre-fetched profile
            if let profile = engine.preFetchedProfile {
                Divider().background(.white.opacity(0.3))

                Text("PRE-FETCHED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.green.opacity(0.7))

                if let bpm = profile.bpm { label("BPM", String(format: "%.1f", bpm)) }
                if let key = profile.key { label("Key", key) }
                if let energy = profile.energy { label("Energy", String(format: "%.2f", energy)) }
                if let valence = profile.valence { label("Valence", String(format: "%.2f", valence)) }
                if let dance = profile.danceability { label("Dance", String(format: "%.2f", dance)) }
                if !profile.genreTags.isEmpty { label("Genres", profile.genreTags.joined(separator: ", ")) }
            } else if engine.currentTrack != nil {
                Divider().background(.white.opacity(0.3))

                Text("Fetching...")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.7))
            }
        }
        .padding(12)
        .background(.black.opacity(0.6))
        .cornerRadius(8)
        .frame(maxWidth: 280, alignment: .leading)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    private func label(_ key: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(key + ":")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
