// ListeningBadgeView — Top-center badge shown during sustained audio silence (≥3 s).
//
// Replaces the legacy NoAudioSignalBadge with UX-spec copy and a subtle spinner.
// Trigger condition is the same: audioSignalState == .silent (SilenceDetector
// state machine guarantees ≥3 s before entering .silent).

import SwiftUI

// MARK: - ListeningBadgeView

/// Non-intrusive badge visible during sustained audio silence.
///
/// Fades in over 400 ms when `isVisible` flips true; fades out on false.
/// In reduce-motion mode: abrupt show/hide, no spinner.
struct ListeningBadgeView: View {

    static let accessibilityID = "phosphene.playback.listeningBadge"

    let isVisible: Bool
    let reduceMotion: Bool

    @State private var spinnerAngle: Double = 0

    var body: some View {
        HStack(spacing: 6) {
            if !reduceMotion {
                Image(systemName: "arrow.2.circlepath")
                    .font(.caption2)
                    .rotationEffect(.degrees(spinnerAngle))
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            spinnerAngle = 360
                        }
                    }
            }
            Text(String(localized: "playback.listening"))
                .font(.caption.weight(.medium).monospaced())
        }
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlayBackdrop()
        .opacity(isVisible ? 1 : 0)
        .animation(
            reduceMotion ? .none : .easeInOut(duration: 0.4),
            value: isVisible
        )
        .allowsHitTesting(false)
        .accessibilityIdentifier(Self.accessibilityID)
        .accessibilityLabel(String(localized: "a11y.listeningBadge.label"))
        .accessibilityAddTraits(.updatesFrequently)
    }
}
