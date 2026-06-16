// FlashHarnessSupport — shared drive + luminance primitives for the photosensitivity
// flash-safety gates.
//
// Two gates consume these so they measure on identical terms (kickoff: reuse, don't
// fork): the CLEAN.7.6 single-pass `PhotosensitivityCertificationTests` (FeatureVector
// → one fragment pass) and the CLEAN.7.6c `MultiPassFlashHarnessTests` (the real
// multi-pass / feedback render paths for Lumen Mosaic, Dragon Bloom, Fata Morgana,
// Skein). One worst-case beat train, one matching stem train, one WCAG luminance
// reducer, one set of Harding-gate constants.
//
// The drive is synthetic-but-realistic (feedback_synthetic_audio is about *diagnostic*
// envelopes masquerading as real pipeline noise; this is a deliberate WORST CASE, the
// same rationale the single-pass gate documents): sharp, full-amplitude, impulse-decayed
// accents at a rate comfortably above the Harding 3/s limit, with deviation primitives
// spiking to the measured real p99 (~0.85) — not to an unphysical 1.0.

import Foundation
@testable import Shared

// MARK: - FlashHarnessSupport

enum FlashHarnessSupport {

    // MARK: Gate constants

    static let fps = 60.0
    /// Worst-case accent rate: comfortably above the 3/s Harding limit (so a genuine
    /// full-frame strobe fails with margin) yet low enough that a preset's luminance
    /// smoothing cannot attenuate it away.
    static let accentHz = 4.5
    static let driveSeconds = 3.0
    /// Minimum full-frame luminance range for a render to count as "responded to the
    /// drive". Below this the render was static and the measurement is not valid —
    /// observed responders sit at Δ ≥ 0.010, static renders at Δ = 0.000.
    static let responsiveLumaRange = 0.003

    // MARK: - Worst-case beat train (FeatureVector)

    /// A synthetic drive that maximally exercises the beat-accent / deviation pathway
    /// (the FBS "beat-punch" flash class) at `accentHz`: sharp, full-amplitude,
    /// impulse-decayed accents over energetic-but-smoothed continuous bands, in the
    /// normal certified regime.
    static func worstCaseBeatTrain(
        accentHz: Double = accentHz,
        seconds: Double = driveSeconds,
        fps: Double = fps
    ) -> [FeatureVector] {
        let count = Int(seconds * fps)
        let period = fps / accentHz          // frames per accent
        let barLen = period * 4
        var out: [FeatureVector] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let t = Float(Double(i) / fps)
            let phase = Double(i).truncatingRemainder(dividingBy: period) / period   // 0…1 within a beat
            let env = Float(exp(-phase * 6.0))    // 1.0 at onset → impulse decay before next beat

            // Continuous bands: energetic, only mildly beat-coupled — real AGC'd
            // bands are smoothed and do not strobe. The sharp signal lives in the
            // accents and deviation spikes below.
            let cont = 0.55 + 0.15 * env
            var fv = FeatureVector(
                bass: cont, mid: cont * 0.95, treble: cont * 0.9,
                bassAtt: 0.55 + 0.08 * env, midAtt: 0.52 + 0.08 * env, trebleAtt: 0.5 + 0.08 * env,
                subBass: cont, lowBass: cont, lowMid: cont * 0.95,
                midHigh: cont * 0.9, highMid: cont * 0.9, high: cont * 0.85,
                beatBass: env, beatMid: env, beatTreble: env, beatComposite: env,
                spectralCentroid: 0.5 + 0.3 * env, spectralFlux: env,
                valence: 0.2, arousal: 0.85,
                time: t, deltaTime: Float(1.0 / fps),
                accumulatedAudioTime: t * 0.6)

            // Deviation primitives: mild continuous Rel + sharp positive Dev spikes to
            // the real p99 (~0.85) — the accent/threshold flash pathway.
            let contRel = (cont - 0.5) * 2.0
            fv.bassRel = contRel; fv.midRel = contRel; fv.trebRel = contRel
            fv.bassDev = env * 0.85; fv.midDev = env * 0.85; fv.trebDev = env * 0.85
            fv.bassAttRel = contRel * 0.7; fv.midAttRel = contRel * 0.7; fv.trebAttRel = contRel * 0.7

            // Phase signals: normal progression through beats / bars / pulses.
            fv.beatPhase01 = Float(phase); fv.beatsUntilNext = Float(1.0 - phase)
            fv.barPhase01 = Float(Double(i).truncatingRemainder(dividingBy: barLen) / barLen)
            fv.beatsPerBar = 4
            fv.pulsePhase01 = Float(phase); fv.pulseAmp01 = 1.0
            fv.pulseBeatIndex = Float(Int(Double(i) / period))
            fv.pulseRegionalBlend01 = 1.0    // certified regional regime (FBS fix engaged)
            fv.trackElapsedS = t             // warm — past any cold-start crossfade
            out.append(fv)
        }
        return out
    }

    // MARK: - Worst-case stem train (StemFeatures)

    /// The stem-side analogue of `worstCaseBeatTrain`, row-aligned with it. The
    /// multi-pass presets read their music response through stems (Skein's per-stem
    /// paint onsets, Fata Morgana's stem-sized mirage shapes, Dragon Bloom's
    /// stem-driven strands), so a faithful worst case must spike the stems too —
    /// otherwise those layers render near-static and the measurement under-reads.
    ///
    /// Calibrated identically to the FeatureVector train: per-beat energy +
    /// impulse-decayed accent, deviation primitives (D-026) to the real p99 (~0.85),
    /// beat = the onset envelope. All four stems (drums/bass/vocals/other) fire in
    /// unison — the maximal-coincident-onset case.
    static func worstCaseStemTrain(
        accentHz: Double = accentHz,
        seconds: Double = driveSeconds,
        fps: Double = fps
    ) -> [StemFeatures] {
        let count = Int(seconds * fps)
        let period = fps / accentHz
        var out: [StemFeatures] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let phase = Double(i).truncatingRemainder(dividingBy: period) / period
            let env = Float(exp(-phase * 6.0))
            let energy = 0.55 + 0.15 * env
            let rel = (energy - 0.5) * 2.0
            let dev = env * 0.85

            var s = StemFeatures.zero
            s.drumsEnergy = energy;  s.bassEnergy = energy
            s.vocalsEnergy = energy; s.otherEnergy = energy
            s.drumsEnergyRel = rel;  s.bassEnergyRel = rel
            s.vocalsEnergyRel = rel; s.otherEnergyRel = rel
            s.drumsEnergyDev = dev;  s.bassEnergyDev = dev
            s.vocalsEnergyDev = dev; s.otherEnergyDev = dev
            s.drumsBeat = env;  s.bassBeat = env
            s.vocalsBeat = env; s.otherBeat = env
            out.append(s)
        }
        return out
    }

    // MARK: - WCAG relative luminance

    /// Mean WCAG relative luminance (linear-light, Rec. 709) of a BGRA8 buffer.
    /// Per-pixel sRGB → linear via a 256-entry LUT (linearise THEN average — the
    /// correct order for luminance, unlike a gamma-encoded mean).
    static func meanRelativeLuminance(_ bgra: [UInt8]) -> Double {
        let pixelCount = bgra.count / 4
        guard pixelCount > 0 else { return 0 }
        var sum = 0.0
        var i = 0
        while i < bgra.count {
            let bLin = srgbToLinear[Int(bgra[i])]
            let gLin = srgbToLinear[Int(bgra[i + 1])]
            let rLin = srgbToLinear[Int(bgra[i + 2])]
            sum += 0.2126 * rLin + 0.7152 * gLin + 0.0722 * bLin
            i += 4
        }
        return sum / Double(pixelCount)
    }

    /// sRGB byte (0…255) → linear relative-luminance component (0…1).
    private static let srgbToLinear: [Double] = (0..<256).map { byte in
        let c = Double(byte) / 255.0
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
}
