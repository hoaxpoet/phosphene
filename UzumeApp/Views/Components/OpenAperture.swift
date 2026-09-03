// OpenAperture — the cave, fully open, as a backdrop. (DS.5)
//
// The Ready screens sit on the same aperture the listener watched widen through
// preparation, now at openness 1 and still churning — Ready is the arrival, not a
// different room. Pure backdrop: no accessibility element of its own (the screen on
// top says what is happening), no easing (there is nothing left to ease toward), no
// surge (nothing lands any more). Under reduced motion the timeline is paused and the
// open cave still renders, it just holds still.

import Session
import SwiftUI

// MARK: - OpenAperture

struct OpenAperture: View {
    let character: PreparationCharacter
    let reduceMotion: Bool

    @State private var epoch = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let scene = ApertureScene(
                    openness: 1,
                    character: character,
                    time: timeline.date.timeIntervalSince(epoch)
                )
                scene.draw(in: &context, size: size)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - ApertureScrim

/// Contrast for copy set over the open cave (Matt's M7: a text halo is not contrast —
/// where the spill is bright the words compete with it). Canvas eased in over the lower
/// half of the frame, so whatever the cave is doing, the bottom settles into darkness
/// under the words. Eased, not linear: a straight ramp that begins against the flat
/// white of the mouth reads as a hard line (a Mach band — measured, not guessed), so
/// the slope starts at nothing and steepens only below the mouth. Proportional to the
/// frame, so it holds at any window size. Purely decorative.
struct ApertureScrim: View {
    private static let stops: [Gradient.Stop] = [
        (0.00, 0.00), (0.45, 0.00), (0.55, 0.06), (0.65, 0.22),
        (0.75, 0.50), (0.85, 0.78), (0.93, 0.92), (1.00, 0.96),
    ].map { .init(color: UzumeAppColor.canvas.opacity($0.1), location: $0.0) }

    var body: some View {
        LinearGradient(stops: Self.stops, startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
