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
