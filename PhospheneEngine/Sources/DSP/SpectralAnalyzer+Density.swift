// SpectralAnalyzer+Density — the DYN.1 / DYN.1b measurements.
//
// Split out to keep `SpectralAnalyzer.swift` inside the 400-line budget. The calibration
// history — three separate ways this was got wrong — is in
// `docs/ENGINE/DYN1_CALIBRATION.md`, and is worth reading before changing any constant here.

import Foundation
import Shared

extension SpectralAnalyzer {

    /// The surge follower: arrives fast so an arrival registers at once, releases slowly so
    /// it holds through a phrase rather than pumping between them. Level smoothing itself is
    /// `LoudnessProfile.levelSmoothingTau` — shared with the offline profile measurement so
    /// the two cannot drift apart.
    ///
    /// DYN.4 — seconds, not per-frame alphas (`LoudnessProfile` §Smoothing time constants).
    /// The prose widths this comment used to quote ("attack ≈ 0.25 s, release τ ≈ 10 s")
    /// were from the retired ~10 Hz rate assumption and never matched the coefficients.
    static let surgeAttackTau: Float = LoudnessProfile.tau(legacyAlpha: 0.35)    // ≈ 0.054 s
    static let surgeReleaseTau: Float = LoudnessProfile.tau(legacyAlpha: 0.010)  // ≈ 2.31 s

    /// FTR.24 — the level-rise accent's three constants.
    ///
    /// `levelFloorSpan` is the trailing window the rise is measured against: long enough
    /// that a note's own attack does not become its own floor, short enough that the floor
    /// is the passage rather than the section.
    ///
    /// ★ THE BAND AND THE RELEASE ARE ONE CALIBRATION, AND DUTY CYCLE IS WHAT THEY CONTROL.
    /// The first pass used 2–6 dB with a 0.35 s release, on the reasoning that the offline
    /// criterion uses a 3 dB threshold and a slow release is easier to see. Measured through
    /// the real consumer on `2026-08-17T12-47-58Z`, that fires **1.47 times a second and is
    /// non-zero 75 % of the time** — so it stops being an accent and becomes a DC LIFT. The
    /// visible cost was precise: the size term's p05 floor rose 46 % (0.281 → 0.409) and its
    /// span fell 25 %, which is the FTR.16 defect Matt rejected as *"you fed the preset
    /// ambien"* arriving by a different route.
    ///
    /// Chasing it with the consumer's gain could not fix it — every weighting traded event
    /// alignment against the floor monotonically, because the accent's DUTY CYCLE, not its
    /// amplitude, is what lifts the floor. 4–12 dB with a 0.20 s release cuts the duty cycle
    /// to 48 % and inverts the trade: event-versus-random specificity goes **1.53× → 3.77×**
    /// (the shipped consumer's numbers) while the span holds within 10 % of untouched.
    ///
    /// A 4 dB floor is also the honest reading of the criterion. A 3 dB rise is where an
    /// event becomes *detectable*; it is not where one becomes worth moving the picture for.
    static let levelFloorSpan: Float = 0.15
    static let levelRiseLowDB: Float = 4.0
    static let levelRiseHighDB: Float = 12.0
    static let levelRiseReleaseTau: Float = 0.20

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
        LoudnessProfile.densityFraction(
            magnitudes: magnitudes, count: count, binResolution: binResolution)
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
    func advanceLevelAndDensity(deltaTime: Float, rawDensity: Float,
                                magnitudes: [Float], count: Int) {
        // PRE-AGC LEVEL by Parseval — the definition lives on `LoudnessProfile` so the live
        // path and DYN.1c's offline profile measure the same quantity on the same scale.
        // Scale confusion here has already cost one review round.
        let levelDB = LoudnessProfile.levelDB(magnitudes: magnitudes, count: count)
        let alpha = LoudnessProfile.emaAlpha(deltaTime: deltaTime,
                                            tau: LoudnessProfile.levelSmoothingTau)
        smoothedLevelDB = alpha * levelDB + (1 - alpha) * smoothedLevelDB

        advanceLevelRise(deltaTime: deltaTime, levelDB: levelDB)

        // DYN.1c: this moment's rank in the track's own loudness distribution when a
        // profile is installed, the fixed band's smoothstep otherwise. Asymmetric follower:
        // arrive fast, leave slowly — a symmetric one pumps between phrases.
        let target = Self.surgeTarget(levelDB: smoothedLevelDB, profile: loudnessProfile)
        let surgeTau = target > surge ? Self.surgeAttackTau : Self.surgeReleaseTau
        let surgeAlpha = LoudnessProfile.emaAlpha(deltaTime: deltaTime, tau: surgeTau)
        surge = surgeAlpha * target + (1 - surgeAlpha) * surge

        // Four legs on one raw fraction: τ0.8 s (branch count), τ9.7 s (`_slow`), τ20 s
        // (section) and τ45 s (the track's true normal). THE SECTION AND NORMAL WIDTHS MUST
        // STAY APART — at DYN.2 they were 0.38 % apart, their ratio was a constant 1.00 and
        // the trunk never moved for a whole session.
        func ema(_ current: Float, tau: Float) -> Float {
            let alpha = LoudnessProfile.emaAlpha(deltaTime: deltaTime, tau: tau)
            return alpha * rawDensity + (1 - alpha) * current
        }
        // FTR.9 — the SECTION RATIO'S OWN SMOOTHING, applied after the rank rather than
        // before it. `sectionDensity` is already a τ20 s leg, yet the RATIO turned 2.88
        // times a second on Matt's `2026-08-11T16-41-39Z`: ranking a slow signal through a
        // quantile table amplifies small wiggles wherever the distribution is dense, so the
        // output is restless even though its input is not. The canopy reads this field for
        // trunk length, thickness and the branch floor — continuous geometry — and this
        // preset's own rule is that anything past ~1 turn/s there "reads as the tree
        // bouncing rather than growing" (Matt, twice: *"the trunk of the tree is moving up
        // and down constantly"*, then *"the motion of the trunk and branches is probably too
        // intense"*).
        //
        // τ 1 s is the least intervention that clears the rule: measured on that session it
        // takes the canopy from **2.75 to 0.57 turns/s** while leaving the span at 0.811
        // against 0.813 — the growth DYN.4 opened up survives intact, only the jitter goes.
        // Downstream of the rank, so it cannot re-break the offline/live distribution match
        // DYN.4 exists to hold.
        let rawSectionRatio = Self.sectionRatio(section: sectionDensity,
                                               liveNormal: densityNormal,
                                               profile: loudnessProfile)
        if sectionRatioSeeded {
            let ratioAlpha = LoudnessProfile.emaAlpha(deltaTime: deltaTime,
                                                     tau: Self.sectionRatioTau)
            smoothedSectionRatio = ratioAlpha * rawSectionRatio
                + (1 - ratioAlpha) * smoothedSectionRatio
        } else {
            smoothedSectionRatio = rawSectionRatio
            sectionRatioSeeded = true
        }

        fastDensity = ema(fastDensity, tau: Self.densityFastTau)
        smoothedDensity = ema(smoothedDensity, tau: Self.densitySlowTau)
        sectionDensity = ema(sectionDensity, tau: Self.densitySectionTau)
        densityNormal = ema(densityNormal, tau: Self.densityNormalTau)
    }

    /// FTR.24 — advance the level-rise accent for one frame.
    ///
    /// Measured on the RAW `levelDB` deliberately. Every existing level consumer reads
    /// `smoothedLevelDB` (τ 0.76 s), and that follower is exactly what erases a transient:
    /// `spectral_surge` is built on it and scores 0.25× event specificity, i.e. worse than
    /// chance. A 0.15 s trailing floor on the unsmoothed value recovers the 3 dB rises a
    /// listener hears as "something landed".
    ///
    /// The floor is a MINIMUM, not a mean — a mean is dragged up by the very rise being
    /// detected, which halves the measured height of every accent after the first.
    func advanceLevelRise(deltaTime: Float, levelDB: Float) {
        let floorDB = recentLevelDB.min() ?? levelDB
        let riseDB = levelDB - floorDB

        // The ring is bounded by TIME, not by frame count: the analysis rate varies by a
        // factor of five between paths (BUG-087 — local files ~10–16 Hz, streaming ~51 Hz),
        // so a fixed sample count would be a 0.04 s window on one path and 0.2 s on the
        // other. Same reason every other constant here is in seconds (DYN.4).
        let span = max(2, Int((Self.levelFloorSpan / max(deltaTime, 1e-4)).rounded()))
        recentLevelDB.append(levelDB)
        if recentLevelDB.count > span {
            recentLevelDB.removeFirst(recentLevelDB.count - span)
        }

        let target = Self.smoothstepf(Self.levelRiseLowDB, Self.levelRiseHighDB, riseDB)
        if target > levelRise {
            levelRise = target          // instantaneous attack — a rise is news at once
        } else {
            let releaseAlpha = LoudnessProfile.emaAlpha(deltaTime: deltaTime,
                                                       tau: Self.levelRiseReleaseTau)
            levelRise += (target - levelRise) * releaseAlpha
        }
    }

    /// DYN.2c — section density against the track's normal.
    ///
    /// Prefers the profile's OFFLINE normal (measured over the full decode at preparation)
    /// and falls back to the live τ45 s EMA only when there is no profile — i.e. streaming,
    /// where no full decode exists. DYN.2b used the live leg unconditionally and the ratio
    /// spanned 1.00…1.17 across a whole song, because a τ45 s EMA seeded to the section leg
    /// starts at exactly 1.00 and needs 90–135 s to separate from it.
    static func sectionRatio(section: Float, liveNormal: Float, profile: LoudnessProfile?) -> Float {
        // Ranked against the track's own density distribution, measured offline: uniform
        // over the track by construction, so the consumer needs no fitted edges. Expressed
        // on the same 0…2 scale the ratio used, so the shader's mapping still reads
        // "1.0 = this track's normal".
        if let profile, profile.isUsable, let rank = profile.densityRank(of: section) {
            return rank * 2
        }
        return liveNormal > 1e-4 ? section / liveNormal : 1
    }
}
