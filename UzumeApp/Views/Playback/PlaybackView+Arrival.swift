// PlaybackView+Arrival — the camera push through the aperture. (DS.5)
//
// Split from PlaybackView.swift, which was already at the file-length ceiling: both
// pieces here are self-contained on purpose, so PlaybackView only ever needs one line
// to render this layer, with no state or wiring of its own to carry.

import Session
import SwiftUI

// MARK: - Character

/// What Uzume heard, reused from the same publisher DS.4 wired to the App layer — the
/// arrival is the same aperture finishing its arc, so it is coloured by the same
/// character the listener already watched widen. Falls back to a neutral character
/// (e.g. reactive-mode sessions with nothing heard) rather than failing to render.
@MainActor
func arrivalCharacter(from engine: VisualizerEngine) -> PreparationCharacter {
    let profiles = engine.sessionManager.preparationProgress?.trackProfiles.values
    return PreparationCharacter(profiles: profiles.map(Array.init) ?? [])
}

// MARK: - PlaybackArrivalOverlay

/// Owns its own visibility: present from creation, gone once `ArrivalTransitionView`
/// finishes fading itself out. `PlaybackView` never touches this state — MetalView is
/// already live underneath for the entire time this sits on top of it.
struct PlaybackArrivalOverlay: View {
    let engine: VisualizerEngine
    let reduceMotion: Bool

    @State private var isVisible = true

    var body: some View {
        if isVisible {
            ArrivalTransitionView(
                character: arrivalCharacter(from: engine),
                reduceMotion: reduceMotion,
                onComplete: { isVisible = false }
            )
        }
    }
}
