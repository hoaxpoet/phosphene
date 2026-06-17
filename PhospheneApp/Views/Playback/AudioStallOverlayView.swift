// AudioStallOverlayView — Prominent center card shown when no fresh audio is
// reaching the visualizer while playing (the silent-tap family: BUG-057/055/058).
//
// More prominent than the bottom-right toast because this is a total loss of
// function. Non-blocking (click-through) — it overlays the frozen/black
// visualizer and auto-clears when audio returns; the parent drives `isVisible`
// from PlaybackErrorBridge's stall detector. Copy is developer-facing for now
// (a literal Terminal command); soften before any public build.

import SwiftUI

// MARK: - AudioStallOverlayView

/// Center overlay card with a plain-language explanation and a fix ladder for
/// the "Phosphene isn't receiving audio" condition. Fades in/out on `isVisible`.
struct AudioStallOverlayView: View {

    static let accessibilityID = "phosphene.playback.audioStallCard"

    let isVisible: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "speaker.slash.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                Text(String(localized: "playback.audioStall.headline"))
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            Text(String(localized: "playback.audioStall.body"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                stepRow(number: 1,
                        text: String(localized: "playback.audioStall.step1"),
                        command: "sudo killall coreaudiod")
                stepRow(number: 2, text: String(localized: "playback.audioStall.step2"))
                stepRow(number: 3, text: String(localized: "playback.audioStall.step3"))
            }

            Text(String(localized: "playback.audioStall.autoClearHint"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(24)
        .frame(maxWidth: 460, alignment: .leading)
        .overlayBackdrop()
        .opacity(isVisible ? 1 : 0)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.4), value: isVisible)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Self.accessibilityID)
        .accessibilityLabel(String(localized: "a11y.audioStallCard.label"))
        .accessibilityHidden(!isVisible)
    }

    // MARK: - Step row

    /// One numbered step. When `command` is non-nil it is rendered verbatim in a
    /// monospaced pill (a literal Terminal command — not localizable copy).
    @ViewBuilder
    private func stepRow(number: Int, text: String, command: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(verbatim: "\(number)")
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(0.85), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                if let command {
                    Text(verbatim: command)
                        .font(.callout.monospaced())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Spacer(minLength: 0)
        }
    }
}
