// LocalFileCountdownView — the local-file Ready: three beats over the open cave, then
// the show. (DS.5 / D-240)
//
// Matt: "Local files get a 3-2-1 countdown before transitioning into playback."
// Uzume is the one about to press play here, so there is no waiting room, no app name
// and no timeout — nothing external can fail to arrive. The countdown runs over
// silence: `onBegin` is what starts the local-file audio router and advances the
// session to `.playing` (VisualizerEngine.handleLocalFileReady), where
// PlaybackArrivalOverlay runs the same camera push the streaming path gets.
//
// Accessibility: each number is announced, and the numeral carries its own label,
// so VoiceOver hears the count rather than a changing digit. Reduced motion keeps
// the count (it is information) and drops only the numeral's roll.

import AppKit
import Session
import SwiftUI

// MARK: - LocalFileCountdownView

struct LocalFileCountdownView: View {
    static let accessibilityID      = "uzume.view.ready.countdown"
    static let countID              = "uzume.ready.countdown"
    static let endSessionButtonID   = "uzume.ready.countdown.endSession"

    static let beats = [3, 2, 1]
    static let beatSeconds: Double = 1

    let character: PreparationCharacter
    let reduceMotion: Bool
    let onBegin: () -> Void
    let onEndSession: () -> Void

    @State private var remaining = beats[0]

    var body: some View {
        ZStack {
            UzumeAppColor.canvas.ignoresSafeArea()
            OpenAperture(character: character, reduceMotion: reduceMotion)
                .ignoresSafeArea()

            // After the count the cave holds alone until the engine has the audio up and
            // the push begins (a few seconds on a cold preset) — a "1" left standing over
            // that gap read as stuck.
            if remaining > 0 {
                GeometryReader { geo in
                    // Sized to the frame, like the cave it sits in, not to Dynamic Type: this is
                    // a display element, not text to read. A scaled .largeTitle rasterises blurry.
                    let side = min(geo.size.width, geo.size.height)
                    Text(verbatim: "\(remaining)")
                        .font(Font(NSFont.systemFont(ofSize: side * 0.36, weight: .thin)))
                        .foregroundColor(UzumeAppColor.ivory)
                        .shadow(color: UzumeAppColor.canvas.opacity(0.9), radius: 4)
                        .shadow(color: UzumeAppColor.canvas.opacity(0.7), radius: 28)
                        .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                        .accessibilityLabel(Self.accessibilityLabel(remaining))
                        .accessibilityIdentifier(Self.countID)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }

            VStack {
                Spacer()
                Button(String(localized: "ready.end_session_button"), action: onEndSession)
                    .buttonStyle(.bordered)
                    .foregroundColor(UzumeAppColor.textSecondary)
                    .accessibilityIdentifier(Self.endSessionButtonID)
                    .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(Self.accessibilityID)
        .task { await count() }
    }

    /// "Starting in 3"
    static func accessibilityLabel(_ remaining: Int) -> String {
        String(format: String(localized: "a11y.ready.countdown"), remaining)
    }

    /// Ends in `onBegin` unless the view goes away first (End session), in which case
    /// the task is cancelled and nothing starts.
    private func count() async {
        for beat in Self.beats {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { remaining = beat }
            AccessibilityNotification.Announcement(Self.accessibilityLabel(beat)).post()
            try? await Task.sleep(for: .seconds(Self.beatSeconds))
            if Task.isCancelled { return }
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { remaining = 0 }
        onBegin()
    }
}
