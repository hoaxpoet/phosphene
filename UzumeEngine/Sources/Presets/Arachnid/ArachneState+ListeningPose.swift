// ArachneState+ListeningPose — V.7.7D listening-pose state machine (D-094).
//
// `ARACHNE_V8_DESIGN.md` §6.3 mandates the spider lift its front legs (legs
// 0+1) when sustained low-attack-ratio bass holds for ≥ 1.5 s, returning to
// rest in ~1 s when the condition relaxes. The state machine lives entirely
// CPU-side: `listenLiftEMA` is consumed by `writeSpiderToGPU()` (defined in
// ArachneState+Spider.swift) to lift `tip[0]` and `tip[1]` in clip-space Y
// before the GPU flush. This preserves the V.7.7B 80-byte
// `ArachneSpiderGPU` contract (slot-7 buffer allocation, see
// ArachneState.swift:204) — adding a `listenLift: Float` field would push
// the struct to 96 bytes and break the existing `spiderBufSize` calculation.
//
// FV mapping: §6.3 specifies `subBass_dev` but `FeatureVector` exposes
// `bassDev` only (CLAUDE.md §Key Types — floats 26–34 cover bass/mid/treb
// rel/dev with no sub-bass split). The sustained-bass character §6.3 is
// targeting is bass-band coherent in practice, so `bassDev > 0.30`
// substitutes directly. D-094 captures the FV-vs-spec mismatch.

import Foundation
import Shared

extension ArachneState {

    // MARK: - Listening Pose Constants (V.7.7D §6.3)

    /// Seconds of sustained low-attack-ratio bass required before the front legs lift.
    static let listenLiftSustainThreshold: Float = 1.5
    /// Smoothing time constant for the listenLift on/off transition (seconds).
    static let listenLiftSmoothTau: Float = 1.0
    /// `bass_dev` threshold (deviation form, ≥ 0). FV has bass_dev but no
    /// subBass_dev, so the §6.3 spec value of 0.30 maps directly here. D-094.
    static let listenLiftBassDevThreshold: Float = 0.30
    /// Upper bound on `bassAttackRatio` distinguishing sustained resonant bass
    /// from transient kick drums (§6.3 spec).
    static let listenLiftAttackRatioCap: Float = 0.55
    /// Body-local scale (UV per body-local unit). Mirrors `kSpiderScale` in
    /// Arachne.metal — must stay in lockstep with the shader constant.
    static let kSpiderScale: Float = 0.018
    /// Tip-lift magnitude in UV (`0.5 × kSpiderScale` per §6.3 / §6.1).
    static let listenLiftTipMagnitudeUV: Float = 0.5 * 0.018

    // MARK: - Update

    /// Advance the listening-pose state machine by one frame.
    ///
    /// Called from `updateSpider` while the state lock is held.
    /// Drives `listenLiftAccumulator` (clamped to the sustain threshold) and
    /// `listenLiftEMA` (smoothed transition toward 0 or 1). The EMA is
    /// consumed by `writeSpiderToGPU()` to lift `tip[0]` / `tip[1]` before
    /// the GPU flush — the shader's IK then derives the raised knee
    /// analytically from the lifted tip without any further state.
    ///
    /// Trigger: `f.bassDev > 0.30 AND stems.bassAttackRatio ∈ (0, 0.55)` held
    /// continuously for ≥ 1.5 s. The attack-ratio gate `(0, 0.55)` is the
    /// same kick-debounce already used by the spider trigger (V.7.5 §10.1.9).
    func updateListeningPose(features: FeatureVector, stems: StemFeatures, dt: Float) {
        let isSustainedLowAttackBass =
            features.bassDev > Self.listenLiftBassDevThreshold &&
            stems.bassAttackRatio > 0.0 &&
            stems.bassAttackRatio < Self.listenLiftAttackRatioCap

        if isSustainedLowAttackBass {
            listenLiftAccumulator = min(Self.listenLiftSustainThreshold,
                                        listenLiftAccumulator + dt)
        } else {
            listenLiftAccumulator = max(0, listenLiftAccumulator - dt)
        }

        let target: Float = (listenLiftAccumulator >= Self.listenLiftSustainThreshold)
            ? 1.0 : 0.0
        let alpha = 1.0 - exp(-dt / Self.listenLiftSmoothTau)
        listenLiftEMA += (target - listenLiftEMA) * alpha
    }
}
