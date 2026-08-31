// AccentWindowDiagnostic — BSAudit.3.diag per-track root-cause indicators.
//
// The `--accent-window-pass-rate` verdict says *what* happened on each
// track (PASS-firing / PASS-degraded / FAIL). The validate.3 stop-and-report
// post-mortem needed *why* so root-cause hypotheses could be ranked per
// track instead of speculated about. This block extends every track result
// with the smallest set of signals that distinguish the design's failure
// modes (design §9.1–§9.4):
//
//   * first broadband peak time + its residual to the nearest audible beat
//     → §9.1 "first peak isn't a beat"
//   * first accent fire (rising edge of gated beatComposite > threshold)
//     + its residual                                       → "what the
//       listener would see first when the system claims sync"
//   * accent_confidence ≥ 0.30 + lock_state == 2 timestamps
//     → state-machine telemetry
//   * per-fire residual distribution
//     → distribution shape distinguishes wrong-phase (tight cluster at
//       non-zero) from wrong-period (wide spread) from locked (cluster near 0)
//
// Pure functions of features.csv frames + Beat This! audible beats — no
// re-analysis, no new audio reads. Lives in its own file to keep
// `AccentWindowPassRate.swift` under SwiftLint's file-length cap.

import Foundation

struct AccentWindowDiagnostic {
    /// First frame in the window where `accent_confidence > 0` — the first
    /// broadband-peak anchor that fired (design §6.3 / §9.1). nil = no peak
    /// reached the detector in the measurement window.
    let firstPeakPlaybackS: Double?
    /// Residual (ms) between the first broadband peak and the nearest
    /// audible beat. Positive = peak fired LATER than the audible beat.
    /// nil iff `firstPeakPlaybackS` is nil or no audible beats present.
    let firstPeakResidualMs: Double?
    /// First frame in the window where `beatComposite > accentThreshold`
    /// crosses upward — the first VISIBLE accent post-gating.
    let firstAccentFirePlaybackS: Double?
    /// Residual (ms) of the first accent fire vs the nearest audible beat.
    let firstAccentResidualMs: Double?
    /// First playback time where `lock_state == 2` (locked) in the window.
    let lockReachedPlaybackS: Double?
    /// Playback time where `accent_confidence` first crosses 0.30 (the
    /// pass-degraded ceiling) — the moment the system started claiming sync.
    let confidenceCrossed30PlaybackS: Double?
    /// Residuals (ms) for every accent fire in the window. The DISTRIBUTION
    /// shape is the most diagnostic single signal: clustered near 0 = locked
    /// correctly; tight cluster at non-zero = wrong phase by that amount;
    /// wide spread = wrong period or unstable phase.
    let accentResidualsMs: [Double]
    /// Median absolute residual across all accent fires (ms).
    let medianAbsAccentResidualMs: Double?
}

enum AccentWindowDiagnostics {

    /// Compute the per-track diagnostic from the windowed features.csv frames
    /// and the windowed Beat This! audible-beat list. Pure function — no
    /// Beat This! re-runs.
    static func compute(
        audible: [Double],
        frames: [FeatureFrame],
        config: AccentWindowConfig
    ) -> AccentWindowDiagnostic {
        let firstPeak = frames.first { $0.accentConfidence > 0 }?.playbackTimeS
        let conf30 = frames.first { $0.accentConfidence >= 0.30 }?.playbackTimeS
        let locked = frames.first { $0.lockState == 2 }?.playbackTimeS
        let firstAccent = firstAccentRisingEdge(frames: frames, config: config)
        let residuals = accentFireResiduals(
            frames: frames, audible: audible, config: config)
        let medianAbsRes: Double? = residuals.isEmpty
            ? nil
            : ColdStartAnalysis.median(residuals.map(abs))
        return AccentWindowDiagnostic(
            firstPeakPlaybackS: firstPeak,
            firstPeakResidualMs: firstPeak.flatMap { residualMs(of: $0, vs: audible) },
            firstAccentFirePlaybackS: firstAccent,
            firstAccentResidualMs: firstAccent.flatMap { residualMs(of: $0, vs: audible) },
            lockReachedPlaybackS: locked,
            confidenceCrossed30PlaybackS: conf30,
            accentResidualsMs: residuals,
            medianAbsAccentResidualMs: medianAbsRes)
    }

    /// Diagnostic block for the degenerate path (no audible beats, no grid).
    static func empty() -> AccentWindowDiagnostic {
        AccentWindowDiagnostic(
            firstPeakPlaybackS: nil,
            firstPeakResidualMs: nil,
            firstAccentFirePlaybackS: nil,
            firstAccentResidualMs: nil,
            lockReachedPlaybackS: nil,
            confidenceCrossed30PlaybackS: nil,
            accentResidualsMs: [],
            medianAbsAccentResidualMs: nil)
    }

    /// First rising-edge crossing of `beatComposite > accentThreshold` —
    /// the first VISIBLE accent post-gating, the moment the listener would
    /// see the system claim it's on the beat.
    private static func firstAccentRisingEdge(
        frames: [FeatureFrame], config: AccentWindowConfig
    ) -> Double? {
        var previousAbove = false
        for frame in frames {
            let above = frame.beatComposite > config.accentThreshold
            if above && !previousAbove { return frame.playbackTimeS }
            previousAbove = above
        }
        return nil
    }

    /// One residual (ms) per rising-edge accent fire in the window — each
    /// fire's playback time minus the nearest audible beat. Positive = accent
    /// fired LATER than the audible beat.
    private static func accentFireResiduals(
        frames: [FeatureFrame],
        audible: [Double],
        config: AccentWindowConfig
    ) -> [Double] {
        guard !audible.isEmpty else { return [] }
        var previousAbove = false
        var residuals: [Double] = []
        for frame in frames {
            let above = frame.beatComposite > config.accentThreshold
            if above && !previousAbove,
               let nearest = ColdStartAnalysis.nearestValue(to: frame.playbackTimeS, in: audible) {
                residuals.append((frame.playbackTimeS - nearest) * 1000.0)
            }
            previousAbove = above
        }
        return residuals
    }

    /// (playback time − nearest audible beat) in ms. nil if `audible` empty.
    private static func residualMs(of pt: Double, vs audible: [Double]) -> Double? {
        guard let nearest = ColdStartAnalysis.nearestValue(to: pt, in: audible) else {
            return nil
        }
        return (pt - nearest) * 1000.0
    }
}
