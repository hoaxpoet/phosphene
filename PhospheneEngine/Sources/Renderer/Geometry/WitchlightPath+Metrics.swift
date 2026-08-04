// WitchlightPath+Metrics.swift — the QG.5 seam.
//
// Split out of `WitchlightPath.swift` at WL.2-i: adding `penSpeedSwing` pushed that file to
// 401 lines against the 400-line lint. The metrics are a natural seam — they are read by
// gates, never by the render path — so they move together rather than the rationale for
// them being trimmed to fit.

import Foundation
import Shared

// MARK: - AudioResponseMetrics (QG.5)

extension WitchlightPath {

    /// Turns of pen heading per trail window — the quantity that decides whether the
    /// stroke reads as a figure or as an arc.
    ///
    /// Normalised per trail window rather than reported as a raw total, because fixtures
    /// differ in length and a raw total would make the band depend on fixture duration
    /// instead of on the preset. Measured from the WL.2-a probe renders: legible figures
    /// landed at 1.9–2.8 turns; the shipped fixed gain produces 0.20–0.73 and draws an
    /// arc on every fixture.
    public func responseMetric(_ name: String) -> Double? {
        switch name {
        case "headingTurnsPerTrail":
            guard elapsedSeconds > 0.01 else { return nil }
            let perSecond = Double(headingTravel) / elapsedSeconds
            return perSecond * Double(tuning.trailSeconds) / (2 * .pi)
        case "penSpeedSwing":
            // Ratio of fastest to slowest pen speed. Reported as a RATIO, not a delta, so
            // the band is independent of `baseSpeed` — a later change to how fast the pen
            // travels must not silently move this gate.
            //
            // Exists because Matt's second M7 ("the same choices about movement") landed on
            // an UNGATED route: of Witchlight's eight audio routes only `headingTurnsPerTrail`
            // carried a QG.5 band, so a speed layer realising a 13 % swing shipped green.
            // That is precisely the failure QG.5 was built for, one route over.
            guard speedMax > 0, speedMin < .greatestFiniteMagnitude, speedMin > 1e-6 else { return nil }
            return Double(speedMax / speedMin)
        default:
            return nil
        }
    }
}
