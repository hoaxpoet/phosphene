// ArrivalTransitionView — the shell around ArrivalPushScene. (DS.5)
//
// PlaybackView's real Metal render (MetalView) is already live underneath this view from
// the moment playback starts — no cold-start reveal, no fresh mount at the climax. This
// view draws the push, holds the whiteout as the pause, then fades its own opacity out via
// ordinary SwiftUI animation, uncovering the already-running preset rather than cutting to
// it. `onComplete` fires once fully transparent, so the caller can drop the view.
//
// Reduced motion: the timeline pauses (no push, no streaks) and the view sits at a brief,
// still hold before the same fade-out — information here is purely atmospheric, so nothing
// is lost, only the animation.

import Session
import SwiftUI

// MARK: - ArrivalTransitionView

struct ArrivalTransitionView: View {
    static let accessibilityID = "uzume.playing.arrival"

    let character: PreparationCharacter
    let reduceMotion: Bool
    let onComplete: () -> Void

    @State private var startDate = Date()
    @State private var opacity: Double = 1
    @State private var scheduled = false

    private static let pushDuration: Double = 2.7
    private static let holdDuration: Double = 0.52
    private static let revealDuration: Double = 0.6
    private static let reducedMotionHold: Double = 0.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { ctx, size in
                let elapsed = timeline.date.timeIntervalSince(startDate)
                let progress = reduceMotion ? 1.0 : min(1, elapsed / Self.pushDuration)
                let scene = ArrivalPushScene(character: character, time: elapsed, progress: progress)
                scene.draw(in: &ctx, size: size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .opacity(opacity)
        .accessibilityHidden(true)
        .accessibilityIdentifier(Self.accessibilityID)
        .onAppear { schedule() }
    }

    private func schedule() {
        guard !scheduled else { return }
        scheduled = true
        let holdEnd = reduceMotion ? Self.reducedMotionHold : (Self.pushDuration + Self.holdDuration)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(holdEnd))
            withAnimation(.easeOut(duration: Self.revealDuration)) {
                opacity = 0
            }
            try? await Task.sleep(for: .seconds(Self.revealDuration))
            onComplete()
        }
    }
}
