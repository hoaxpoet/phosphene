// PreparationAperture — the mysterious preparation view: a cave whose opening starts
// shut and widens as Uzume hears the playlist. (DS.4 / D-238)
//
// BRAND.md, First Opening: "darkness is the condition, the opening is the event, and
// color is the consequence." Ama-no-Iwato: Omoikane prepares a plan — that is this
// screen. One opening, no per-track marks; a track landing surges the light, it does
// not leave a mark. The opening tracks the engine's four readiness stops, not the
// fraction complete, so eight tracks and forty are the same object.
//
// Three parts, kept apart so the middle one is testable without a run loop:
//   - `ApertureStop`          how open the cave is: a pure function of readiness.
//   - `PreparationCharacter`  what the playlist changes: rate, edge, definition, waver —
//                             never hue. Derived only from what has been heard.
//   - `ApertureScene`         the drawing, as a function of (openness, character, time)
//                             — in ApertureScene.swift.
// `PreparationAperture` is the SwiftUI shell: a TimelineView-driven Canvas that eases
// between stops and swells on each track heard. Under reduced motion the timeline is
// paused and the easing is skipped — the cave still renders and still widens with
// readiness; it simply does not animate between states.

import Session
import Shared
import SwiftUI

// MARK: - ApertureStop

/// How open the cave is, as a pure function of readiness.
///
/// The four engine stops are the four sizes; within a stop the opening grows with the
/// fraction heard so the image keeps developing across a four-minute wait. Shut until
/// the first track is heard; fully open only when nothing is left to prepare.
enum ApertureStop {
    /// The pinprick the first heard track cracks the cave to.
    static let pinprick = 0.10

    static func openness(level: ProgressiveReadinessLevel, heard: Int, total: Int) -> Double {
        guard heard > 0, total > 0 else { return 0 }
        let fraction = Double(heard) / Double(total)
        switch level {
        case .preparing:
            return pinprick + 0.06 * min(1, Double(heard - 1) / 2)
        case .readyForFirstTracks:
            let start = Double(defaultProgressiveReadinessThreshold) / Double(total)
            return 0.42 + 0.24 * unit((fraction - start) / max(0.001, 0.5 - start))
        case .partiallyPlanned:
            return 0.72 + 0.20 * unit((fraction - 0.5) / 0.5)
        case .fullyPrepared:
            return 1
        case .reactiveFallback:
            return 0
        }
    }

    private static func unit(_ x: Double) -> Double { min(1, max(0, x)) }
}

// MARK: - PreparationCharacter

/// What the playlist changes about the light — its behaviour, never its colour.
///
/// Every property derives from the profiles of tracks already heard, so the image
/// becomes more specific as more of the playlist is heard. Defaults describe a cave
/// that has heard nothing yet.
struct PreparationCharacter: Equatable {
    /// How many tracks contributed.
    var heard = 0
    /// Circular variance of mood angle, 0 (uniform) … 1 (spread): churn speed.
    var moodSpread = 0.0
    /// Average tempo relative to 110 BPM: the rate everything moves at.
    var rate = 1.0
    /// Edge and contrast of the shafts, from average spectral centroid.
    var crisp = 0.58
    /// Ray definition, from the drums' share of stem energy.
    var beat = 0.4
    /// Smooth wash, from the vocals' share.
    var wash = 0.35
    /// Width of the mouth, from the bass share.
    var heavy = 0.3
    /// How much the mouth wavers, from the fraction of beat-irregular tracks.
    var jitter = 0.0
    /// Overall level of stem energy.
    var energy = 0.5

    /// Deepening of the image with the number heard — saturates around seven tracks.
    var depth: Double { 1 - exp(-Double(heard) / 7) }

    init() {}

    init(profiles: [TrackProfile]) {
        guard !profiles.isEmpty else { return }
        heard = profiles.count
        let count = Double(profiles.count)

        // Mood spread: 1 − resultant length of the mood angles (circular variance),
        // so a varied playlist churns and a uniform one drifts. An average hue was
        // tried and rejected — it converges every playlist on the same colour.
        var sumX = 0.0, sumY = 0.0
        var bpmSum = 0.0, bpmCount = 0.0, centroidSum = 0.0
        var drums = 0.0, vocals = 0.0, bass = 0.0, other = 0.0, irregular = 0.0
        for profile in profiles {
            let angle = atan2(Double(profile.mood.arousal), Double(profile.mood.valence))
            sumX += cos(angle); sumY += sin(angle)
            if let bpm = profile.bpm, bpm > 0 { bpmSum += Double(bpm); bpmCount += 1 }
            centroidSum += Double(profile.spectralCentroidAvg)
            let balance = profile.stemEnergyBalance
            drums += Double(balance.drumsEnergy); vocals += Double(balance.vocalsEnergy)
            bass += Double(balance.bassEnergy); other += Double(balance.otherEnergy)
            if profile.beatIrregular == true { irregular += 1 }
        }
        moodSpread = 1 - min(1, hypot(sumX / count, sumY / count))
        rate = bpmCount > 0 ? (bpmSum / bpmCount) / 110 : 1
        crisp = 0.30 + 0.70 * min(1, centroidSum / count)
        let total = max(0.001, drums + vocals + bass + other)
        beat = drums / total
        wash = vocals / total
        heavy = bass / total
        energy = min(1, total / count)
        jitter = 0.25 * irregular / count
    }
}

// MARK: - ApertureMotion

/// The two motions the shell adds on top of the stateless scene, as pure functions of
/// elapsed time so a test can step them: easing between stops, and the swell when a
/// track lands. Both are slow and additive — a new track is a swell, never a flash.
enum ApertureMotion {
    /// Time constant of the approach to a new stop.
    static let easeSeconds = 2.8
    /// Duration of the swell from a heard track.
    static let surgeSeconds = 2.4

    /// Exponential approach from `from` to `to`, `elapsed` seconds after the change.
    static func eased(from: Double, to: Double, elapsed: Double) -> Double {
        guard elapsed >= 0, elapsed.isFinite else { return to }
        return to + (from - to) * exp(-elapsed / easeSeconds)
    }

    /// A smooth bump: up over the first third, down over the rest. 0 outside.
    static func surge(elapsed: Double) -> Double {
        let unit = elapsed / surgeSeconds
        guard unit >= 0, unit < 1 else { return 0 }
        return unit < 0.33
            ? 0.5 - 0.5 * cos(.pi * unit / 0.33)
            : 0.5 + 0.5 * cos(.pi * (unit - 0.33) / 0.67)
    }
}

// MARK: - PreparationAperture

/// The mysterious view. Renders from real profile data; the opening is a pure function
/// of readiness; nothing spills while shut.
struct PreparationAperture: View {
    static let accessibilityID = "uzume.preparing.aperture"

    /// Target openness from `ApertureStop`.
    let openness: Double
    let character: PreparationCharacter
    let heard: Int
    let total: Int
    let canStart: Bool
    /// Effective reduce-motion state (system flag combined with the in-app preference).
    let reduceMotion: Bool

    @State private var easeFrom: Double = 0
    @State private var easeStart = Date.distantPast
    @State private var surgeStart = Date.distantPast
    @State private var epoch = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let now = timeline.date
                var scene = ApertureScene(
                    openness: currentOpenness(at: now),
                    character: character,
                    time: now.timeIntervalSince(epoch)
                )
                scene.surge = reduceMotion ? 0 : ApertureMotion.surge(elapsed: now.timeIntervalSince(surgeStart))
                scene.draw(in: &context, size: size)
            }
        }
        .onChange(of: openness) { old, _ in
            easeFrom = reduceMotion ? openness : currentOpenness(from: old, at: Date())
            easeStart = Date()
        }
        .onChange(of: heard) { old, new in
            if new > old { surgeStart = Date() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(Self.accessibilityID)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    // MARK: Motion

    /// Under reduced motion the opening is at its target at all times: it still
    /// widens with readiness, it just does not animate there.
    private func currentOpenness(at date: Date) -> Double {
        reduceMotion ? openness : currentOpenness(from: easeFrom, at: date)
    }

    private func currentOpenness(from: Double, at date: Date) -> Double {
        ApertureMotion.eased(from: from, to: openness, elapsed: date.timeIntervalSince(easeStart))
    }

    // MARK: Accessibility — every fact the light conveys, as text

    /// "Preparing. 4 of 40 tracks heard."
    var accessibilityLabel: String {
        Self.accessibilityLabel(heard: heard, total: total)
    }

    /// "You can start now" once the first tracks are ready; empty before.
    var accessibilityValue: String {
        canStart ? String(localized: "a11y.preparing.aperture.can_start") : ""
    }

    static func accessibilityLabel(heard: Int, total: Int) -> String {
        String(format: String(localized: "a11y.preparing.aperture.label"), heard, total)
    }
}
