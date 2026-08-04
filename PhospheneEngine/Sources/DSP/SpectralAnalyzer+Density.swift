// SpectralAnalyzer+Density — the DYN.1 / DYN.1b measurements.
//
// Split out to keep `SpectralAnalyzer.swift` inside the 400-line budget. The calibration
// history — three separate ways this was got wrong — is in
// `docs/ENGINE/DYN1_CALIBRATION.md`, and is worth reading before changing any constant here.

import Foundation

extension SpectralAnalyzer {

    /// Level smoothing (τ ≈ 3 s) and the surge follower: attack ≈ 0.25 s so an arrival
    /// registers at once, release τ ≈ 10 s so it holds through a phrase rather than
    /// pumping between them.
    static let levelAlpha: Float = 0.030
    static let surgeAttack: Float = 0.35
    static let surgeRelease: Float = 0.010

    /// Band in dB of TOTAL SPECTRAL ENERGY — note the scale, it is NOT RMS dBFS. The
    /// first calibration confused the two and the surge saturated 14 s before the event.
    /// Measured: ≈ −37 dB in an intro, −28…−19 before a guitar arrival, −17…−10 through
    /// a body. Depends on a healthy chain (the assumption `SignalHealthMonitor` enforces);
    /// on a chronically quiet source the surge never fires, which is the right failure.
    static let surgeLowDB: Float = -24
    static let surgeHighDB: Float = -15

    static func smoothstepf(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let ramp = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return ramp * ramp * (3 - 2 * ramp)
    }

    /// Fraction of spectral energy above `densitySplitHz`, from RAW magnitudes.
    ///
    /// Energy is magnitude squared; the ratio is scale-invariant, so any gain applied
    /// upstream cancels. Returns 0 for silence rather than a division artefact.
    func computeDensity(magnitudes: [Float], count: Int) -> Float {
        guard binResolution > 0 else { return 0 }
        let splitBin = min(Int(Self.densitySplitHz / binResolution), count)
        var low: Float = 0
        var high: Float = 0
        for i in 0..<count {
            let energy = magnitudes[i] * magnitudes[i]
            if i < splitBin { low += energy } else { high += energy }
        }
        let total = low + high
        return total > 1e-10 ? high / total : 0
    }
}
