// TrackChangeAnimationView — Animated center-to-top-left track announcement on boundary.
//
// On track change: large centered card appears, holds 1s, then slides/scales to the
// top-left position where TrackInfoCardView lives (matchedGeometryEffect). Total: 1.8s.
// In reduce-motion mode: simple opacity fade, no slide.

import SwiftUI

// MARK: - TrackChangeAnimationView

/// Animates track announcements on every track boundary.
///
/// Placed in the same ZStack as `PlaybackChromeView`. The `namespace` must be shared
/// with `TrackInfoCardView` for `matchedGeometryEffect` positioning.
struct TrackChangeAnimationView: View {

    let trackInfo: TrackInfoDisplay?
    let reduceMotion: Bool
    let namespace: Namespace.ID

    @State private var isAnimating: Bool = false
    @State private var phase: AnimPhase = .idle

    // Internal track-change detection
    @State private var lastTitle: String?

    private enum AnimPhase { case idle, center, transitioning }

    var body: some View {
        Group {
            if phase != .idle, let info = trackInfo {
                if phase == .center {
                    centerCard(info: info)
                        .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity,
                                removal: .opacity.combined(with: .scale(scale: 0.85))
                            )
                        )
                }
            }
        }
        .onChange(of: trackInfo?.title) { _, newTitle in
            guard newTitle != nil, newTitle != lastTitle else { return }
            lastTitle = newTitle
            triggerAnimation()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: - Center Card

    private func centerCard(info: TrackInfoDisplay) -> some View {
        VStack(spacing: 6) {
            Text(info.title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            if !info.artist.isEmpty {
                Text(info.artist)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(28)
        .overlayBackdrop()
        .matchedGeometryEffect(id: "trackAnnouncement", in: namespace, isSource: phase == .center)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Animation Trigger

    private func triggerAnimation() {
        guard !isAnimating else { return }
        isAnimating = true

        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.3)) {
            phase = .center
        }

        Task {
            // Hold at center for 1s.
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation(reduceMotion ? .none : .spring(duration: 0.5)) {
                phase = .idle
            }
            try? await Task.sleep(for: .seconds(0.5))
            isAnimating = false
        }
    }
}
