// SessionProgressDotsView — Track-list progress dots in the top-right controls cluster.

import SwiftUI

// MARK: - SessionProgressDotsView

/// Renders one dot per planned track. Filled = played, highlighted = current, empty = future.
///
/// Falls back to a single pulsing indicator in reactive mode (no plan).
/// Collapses to a text summary when the track count exceeds 30.
struct SessionProgressDotsView: View {

    static let accessibilityID = "phosphene.playback.progressDots"

    let progress: SessionProgressData
    let reduceMotion: Bool

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        Group {
            if progress.isReactiveMode {
                reactiveDot
            } else if progress.totalTracks > 30 {
                trackCountText
            } else {
                dotRow
            }
        }
        .accessibilityIdentifier(Self.accessibilityID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "a11y.progressDots.label"))
        .accessibilityValue("Track \(max(1, progress.currentIndex + 1)) of \(progress.totalTracks)")
    }

    // MARK: - Subviews

    private var reactiveDot: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.white.opacity(pulseOpacity))
                .frame(width: 10, height: 10)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        pulseOpacity = 0.3
                    }
                }
            Text("Reactive")
                .font(.caption2.weight(.medium).monospaced())
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private var trackCountText: some View {
        Text("\(progress.currentIndex + 1) of \(progress.totalTracks)")
            .font(.caption.monospaced())
            .foregroundColor(.white.opacity(0.7))
    }

    private var dotRow: some View {
        HStack(spacing: 4) {
            ForEach(0..<progress.totalTracks, id: \.self) { idx in
                dotView(for: idx)
            }
        }
    }

    @ViewBuilder
    private func dotView(for index: Int) -> some View {
        let isCurrent = index == progress.currentIndex
        let isPast    = progress.currentIndex >= 0 && index < progress.currentIndex

        Circle()
            .fill(dotColor(isCurrent: isCurrent, isPast: isPast))
            .frame(width: isCurrent ? 8 : 5, height: isCurrent ? 8 : 5)
            .overlay {
                if isCurrent && !reduceMotion {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                        .scaleEffect(pulseOpacity > 0.5 ? 1.3 : 1.0)
                        .opacity(pulseOpacity > 0.5 ? 0 : 0.6)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                pulseOpacity = 0.3
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isCurrent)
    }

    private func dotColor(isCurrent: Bool, isPast: Bool) -> Color {
        if isCurrent { return .white }
        if isPast { return .white.opacity(0.6) }
        return .white.opacity(0.25)
    }
}
