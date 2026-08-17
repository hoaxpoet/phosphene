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

    /// FTR.24a — the level-rise constants, RECALIBRATED after the field shipped with a
    /// 22× rate dependence that its first test suite could not see.
    ///
    /// ★★★ THE DEFECT, because it generalises past this field. The first version measured the
    /// rise against a trailing MINIMUM over 0.15 s. A minimum over a time window is NOT a
    /// rate-invariant statistic: the higher the analysis rate, the more frames that window
    /// spans, the noisier each frame's level is (a shorter hop is a shorter RMS window), and so
    /// the deeper the minimum digs. On identical audio the field fired **0.04/s at 15.8 Hz and
    /// 0.89/s at 59.4 Hz** — 22× — which means near-dead on local files (BUG-087: ~10–16 Hz)
    /// and hyperactive on the tap (~51–59 Hz). The consumer that shipped with it doubled its
    /// travel and Matt rejected it on sight: *"herky-jerky … looks defective."*
    ///
    /// `LevelRiseTests` had a rate-invariance test and it PASSED, because it asked only whether
    /// a synthetic +12 dB step still fires at 10 Hz and 51 Hz. A step that large saturates the
    /// band at any rate. **A rate-invariance test must compare a DISTRIBUTION on real material
    /// (fire rate, duty cycle, mean), not whether one enormous input survives.**
    ///
    /// The fix is a statistic with no sample-count term: a FIXED-LAG difference — level now
    /// minus level `levelRiseLagSeconds` ago — on a level pre-smoothed with a short fixed τ so
    /// per-frame noise stops scaling with the hop. Measured on the same audio, that holds the
    /// two real paths to within 12 % (15.8 Hz 0.35/s vs 59.4 Hz 0.41/s, mean 0.098 vs 0.109).
    ///
    /// `levelPreSmoothTau` is deliberately 40 ms — long enough to normalise across rates, and
    /// ~19× shorter than the `levelSmoothingTau` (0.76 s) whose transient-erasing is the entire
    /// reason this field exists. The band widened to 2–7 dB because the lag difference is a
    /// smaller number than a rise off a minimum.
    static let levelPreSmoothTau: Float = 0.040
    static let levelRiseLagSeconds: Float = 0.15
    static let levelRiseLowDB: Float = 2.0
    static let levelRiseHighDB: Float = 7.0
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

    /// FTR.24a — advance the level-rise accent for one frame.
    ///
    /// Measured on the raw `levelDB` through a SHORT fixed pre-smoothing, never on
    /// `smoothedLevelDB` (τ 0.76 s), which is the follower that erases the transient this field
    /// exists to catch. The rise is a FIXED-LAG difference; see the constants above for why a
    /// trailing minimum was wrong and what it cost.
    func advanceLevelRise(deltaTime: Float, levelDB: Float) {
        // Pre-smooth first: per-frame level noise scales with the hop, and every statistic
        // taken downstream of it inherits that scaling unless it is damped in TIME.
        let preAlpha = LoudnessProfile.emaAlpha(deltaTime: deltaTime, tau: Self.levelPreSmoothTau)
        if preSmoothedLevelDB <= -119 {
            preSmoothedLevelDB = levelDB          // exact seed, no ramp from -120
        } else {
            preSmoothedLevelDB += (levelDB - preSmoothedLevelDB) * preAlpha
        }

        // The ring holds the pre-smoothed level so the lag lookup is a fixed DURATION, not a
        // fixed number of samples — the analysis rate varies ~4× between paths (BUG-087).
        let lagFrames = max(1, Int((Self.levelRiseLagSeconds / max(deltaTime, 1e-4)).rounded()))
        let laggedDB = recentLevelDB.count > lagFrames
            ? recentLevelDB[recentLevelDB.count - lagFrames - 1]
            : (recentLevelDB.first ?? preSmoothedLevelDB)
        recentLevelDB.append(preSmoothedLevelDB)
        if recentLevelDB.count > lagFrames + 2 {
            recentLevelDB.removeFirst(recentLevelDB.count - (lagFrames + 2))
        }

        let riseDB = preSmoothedLevelDB - laggedDB
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
