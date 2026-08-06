// SpectralAnalyzer+Density — the DYN.1 / DYN.1b measurements.
//
// Split out to keep `SpectralAnalyzer.swift` inside the 400-line budget. The calibration
// history — three separate ways this was got wrong — is in
// `docs/ENGINE/DYN1_CALIBRATION.md`, and is worth reading before changing any constant here.

import Foundation
import Shared

extension SpectralAnalyzer {

    /// The surge follower: attack ≈ 0.25 s so an arrival registers at once, release
    /// τ ≈ 10 s so it holds through a phrase rather than pumping between them. Level
    /// smoothing itself is `LoudnessProfile.levelSmoothingAlpha` — shared with the
    /// offline profile measurement so the two cannot drift apart.
    static let surgeAttack: Float = 0.35
    static let surgeRelease: Float = 0.010

    /// FALLBACK band in dB of TOTAL SPECTRAL ENERGY — note the scale, it is NOT RMS dBFS.
    /// The first calibration confused the two and the surge saturated 14 s before the
    /// event. Measured: ≈ −37 dB in an intro, −28…−19 before a guitar arrival, −17…−10
    /// through a body. Depends on a healthy chain (the assumption `SignalHealthMonitor`
    /// enforces); on a chronically quiet source the surge never fires, which is the right
    /// failure.
    ///
    /// DYN.1c: used only when no `LoudnessProfile` is installed — i.e. streaming, an
    /// uncached track, or a file whose measured range is too narrow to trust. A fixed band
    /// is calibrated for one song and wrong for the next: on Hummer it pins at 1.00 for
    /// 62 % of the track while later sections are 4 dB louder than the one that saturated
    /// it. `setLoudnessProfile(_:)` replaces it per track.
    static let surgeLowDB: Float = -24
    static let surgeHighDB: Float = -15

    /// DYN.1c — the surge target for one frame: this moment's rank in the CURRENT track's
    /// own loudness distribution when a profile is installed, the fixed band's smoothstep
    /// otherwise. The rank needs no shaping curve — it is already uniform over the track.
    static func surgeTarget(levelDB: Float, profile: LoudnessProfile?) -> Float {
        guard let profile, profile.isUsable else {
            return smoothstepf(surgeLowDB, surgeHighDB, levelDB)
        }
        return profile.rank(ofLevelDB: levelDB)
    }

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

    /// DYN.1c — install this track's loudness distribution as the surge source, `nil` to
    /// revert to the fixed band. Called per track like `MIRPipeline.setBeatGrid`, and
    /// **deliberately not cleared by `reset()`**: the LF path installs and THEN resets, so
    /// clearing here would discard it on the one path that has one (same reason
    /// `BeatPulseClock`'s tempo survives reset — the installer is the sole authority).
    public func setLoudnessProfile(_ profile: LoudnessProfile?) {
        lock.lock()
        defer { lock.unlock() }
        loudnessProfile = profile
    }

    /// Advance the level follower and all four density legs for one frame.
    ///
    /// Extracted from `process(magnitudes:)` at DYN.2b — that function and its file were
    /// both over their caps, and this block is the part that belongs in the density
    /// companion anyway. The stored properties it touches are `internal` for exactly this
    /// reason (same relaxation as `lock` / `loudnessProfile` above).
    func advanceLevelAndDensity(rawDensity: Float, magnitudes: [Float], count: Int) {
        // PRE-AGC LEVEL by Parseval — the definition lives on `LoudnessProfile` so the live
        // path and DYN.1c's offline profile measure the same quantity on the same scale.
        // Scale confusion here has already cost one review round.
        let levelDB = LoudnessProfile.levelDB(magnitudes: magnitudes, count: count)
        let alpha = LoudnessProfile.levelSmoothingAlpha
        smoothedLevelDB = alpha * levelDB + (1 - alpha) * smoothedLevelDB

        // DYN.1c: this moment's rank in the track's own loudness distribution when a
        // profile is installed, the fixed band's smoothstep otherwise. Asymmetric follower:
        // arrive fast, leave slowly — a symmetric one pumps between phrases.
        let target = Self.surgeTarget(levelDB: smoothedLevelDB, profile: loudnessProfile)
        let surgeAlpha = target > surge ? Self.surgeAttack : Self.surgeRelease
        surge = surgeAlpha * target + (1 - surgeAlpha) * surge

        // Four legs on one raw fraction: τ0.8 s (branch count), τ9.7 s (`_slow`), τ20 s
        // (section) and τ45 s (the track's true normal). THE SECTION AND NORMAL WIDTHS MUST
        // STAY APART — at DYN.2 they were 0.38 % apart, their ratio was a constant 1.00 and
        // the trunk never moved for a whole session.
        fastDensity = Self.densityFastAlpha * rawDensity + (1 - Self.densityFastAlpha) * fastDensity
        smoothedDensity = Self.densityAlpha * rawDensity + (1 - Self.densityAlpha) * smoothedDensity
        sectionDensity = Self.densitySectionAlpha * rawDensity
            + (1 - Self.densitySectionAlpha) * sectionDensity
        densityNormal = Self.densityNormalAlpha * rawDensity
            + (1 - Self.densityNormalAlpha) * densityNormal
    }
}
