// LocalFileTransportBar — LF.5.fix D-LF5-3 hover-revealed music-player controls.
//
// Four buttons (Stop / Prev / Play-Pause / Next) in a centered horizontal row,
// rendered at the bottom-center of `PlaybackChromeView` only when a local-file
// session is active. Visibility piggybacks on the existing chrome overlay
// fade (`viewModel.overlayVisible`) so the transport bar appears on hover and
// auto-hides with the rest of the chrome.
//
// UX-2 carve-out: the streaming path's "no playback controls" invariant
// stands; for LF Phosphene IS the player, so transport is mandatory. UX_SPEC
// §2.1 amended in the LF.5.fix closeout.

import SwiftUI

// MARK: - LocalFileTransportBar

struct LocalFileTransportBar: View {

    static let accessibilityID = "phosphene.playback.lfTransport"

    let isPaused: Bool
    let onStop: () -> Void
    let onPrev: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            transportButton(
                symbol: "stop.fill",
                tooltipKey: "playback.transport.stop.tooltip",
                a11yKey: "playback.transport.stop.a11y",
                action: onStop
            )
            transportButton(
                symbol: "backward.fill",
                tooltipKey: "playback.transport.prev.tooltip",
                a11yKey: "playback.transport.prev.a11y",
                action: onPrev
            )
            transportButton(
                symbol: isPaused ? "play.fill" : "pause.fill",
                tooltipKey: isPaused
                    ? "playback.transport.play.tooltip"
                    : "playback.transport.pause.tooltip",
                a11yKey: isPaused
                    ? "playback.transport.play.a11y"
                    : "playback.transport.pause.a11y",
                action: onPlayPause,
                emphasized: true
            )
            transportButton(
                symbol: "forward.fill",
                tooltipKey: "playback.transport.next.tooltip",
                a11yKey: "playback.transport.next.a11y",
                action: onNext
            )
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.accessibilityID)
    }

    @ViewBuilder
    private func transportButton(
        symbol: String,
        tooltipKey: String.LocalizationValue,
        a11yKey: String.LocalizationValue,
        action: @escaping () -> Void,
        emphasized: Bool = false
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: emphasized ? 22 : 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: emphasized ? 38 : 32, height: emphasized ? 38 : 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(emphasized ? 0.18 : 0.10))
                )
        }
        .buttonStyle(.plain)
        .help(String(localized: tooltipKey))
        .accessibilityLabel(String(localized: a11yKey))
    }
}
