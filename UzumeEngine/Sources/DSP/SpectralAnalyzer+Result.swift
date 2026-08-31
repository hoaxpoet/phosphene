// SpectralAnalyzer+Result — the per-frame output type and what each field is FOR.
//
// Split out at FTR.24 for the reason `SpectralAnalyzer+Density.swift` was: the parent file
// sits against the 400-line budget, and the field documentation is the part that grows. It
// grows because these fields are the audio contract every preset routes against, and each
// one that was added without its measured rationale has cost a review round — the DYN.1
// density comment and the FTR.24 level-rise comment both exist to stop a future increment
// re-deriving a number that has already been paid for. Calibration history:
// `docs/ENGINE/DYN1_CALIBRATION.md`.

import Foundation

extension SpectralAnalyzer {

    /// Spectral analysis output for a single frame.
    public struct Result: Sendable {
        /// Weighted mean frequency in Hz. 0 for silence.
        public var centroid: Float
        /// Frequency below which 85% of spectral energy lies, in Hz. 0 for silence.
        public var rolloff: Float
        /// Half-wave rectified spectral difference from previous frame. 0 on first frame.
        public var flux: Float
        /// EMA-smoothed centroid in Hz.
        public var smoothedCentroid: Float
        /// EMA-smoothed rolloff in Hz.
        public var smoothedRolloff: Float
        /// EMA-smoothed flux.
        public var smoothedFlux: Float
        /// DYN.1 — fraction of spectral energy above `densitySplitHz`, 0…1, EMA-smoothed
        /// to τ ≈ 6 s. Deliberately NOT the raw per-frame value, which turns 5.59 times a
        /// second and reads on screen as jitter.
        ///
        /// The ONE quantity in the pipeline that survives normalisation, because it is
        /// computed here from the raw magnitudes — before `MIRPipeline`'s total-energy
        /// AGC and before `BandDeviationTracker`'s per-band EMA. A scalar gain anywhere
        /// upstream scales every bin equally and cancels in the ratio.
        ///
        /// WHY THIS AND NOT A LEVEL. Measured on session `2026-08-04T14-58-10Z`
        /// (Cherub Rock): RMS is flat at −14 dBFS from 24 s to the end of the track —
        /// the master is limited, so there is no level change to detect. What moves when
        /// the distorted guitar enters is spectral density: this fraction runs 0.084–0.10
        /// through the verse and rises to 0.14–0.22 from ~75 s. Distortion adds harmonics,
        /// not amplitude, and that is what a listener hears as "it got louder".
        public var density: Float
        /// Slow EMA of `density` (τ ≈ 8 s). Lets a consumer read "denser than this
        /// track's normal" rather than an absolute, without rolling its own state.
        public var smoothedDensity: Float
        /// DYN.2b — SECTION RATIO: τ20 s density over the track's true τ45 s normal.
        /// A ratio, not a density: ~1.0 means "as dense as this track usually is".
        public var sectionRatio: Float
        /// DYN.1b — SECTION SURGE, 0…1. Rises fast when the mix arrives, and HOLDS.
        ///
        /// The field for "the tree shoots up when the distorted guitar enters" — which
        /// Matt defines concretely as the trunk elongating and the next level of branches
        /// appearing. Both are STEPS that persist, and nothing else here can express one:
        /// every other field is instantaneous or averaged, so a preset can only scale it.
        /// An asymmetric follower turns an arrival into something a visual can sit on.
        ///
        /// Driven by pre-AGC LEVEL, not spectral shape. Measured on `2026-08-04T19-20-32Z`
        /// at the guitar entry, a level surge separates the pre-guitar passage from the
        /// arrival **20.4×** (0.048 → 0.981) while turning only 0.58 times a second. Shape
        /// cannot: the clean intro is BRIGHTER (HF 0.22) than the pre-guitar passage
        /// (HF 0.03), so it confuses a bright quiet intro with a loud arrival.
        ///
        /// The reasoning that earlier ruled level out was wrong in a specific way: the
        /// BODY of a limited master is flat, so level looked useless — but the intro→body
        /// transition is 26 dB. Limiting flattens the body, not the arrival.
        ///
        /// DYN.1c — with a per-track `LoudnessProfile` installed (local files only) the
        /// target is this moment's RANK in that track's own loudness distribution, not a
        /// fixed absolute band that saturates and can never rise again. See LoudnessProfile.
        public var surge: Float

        /// FTR.24 — LEVEL RISE, 0…1. The TRANSIENT sibling of `surge`: a fast rise in
        /// pre-AGC level against its own 0.15 s trailing floor, instant attack, 0.20 s
        /// release. `surge` answers "how loud is this passage for this track"; this answers
        /// "did something just LAND".
        ///
        /// It exists because nothing else here marks an audible event, which was measured
        /// rather than assumed against 49 audible events on `2026-08-17T12-47-58Z`
        /// (event-versus-random specificity, > 3 dB rise in the 50 ms RMS envelope of the
        /// tap): `surge` **0.25×** — it moves DOWN when the ear notices, because it ranks a
        /// 0.76 s follower and a limited master dips in rank as a band arrives; `beatMid`
        /// 0.83×, below chance, since the `beat*` fields are pulse CLOCKS; `spectralFlux`
        /// 1.50×, fast but firing as often between events as on them; `bassDev` 1.75×, the
        /// best of the deviation primitives and still band-limited. Seven M7 rejections of
        /// "the tree grows and shrinks with no clear connection to the music" were that
        /// first number.
        ///
        /// ⚠ This field is the same detector the criterion uses, so it is a DEFINITION of
        /// "audible event" rather than a proxy validated against one — the one claim here
        /// that cannot be independently checked. What DOES generalise, on four tracks chosen
        /// offline for different production: solo piano 4.1×, classical guitar 6.8×, Seven
        /// Nation Army 20.5×, dense limited electronica (Autechre) **1.2× — near chance**,
        /// which is the FTR.15 limiter mechanism at transient scale. Fire rate stays
        /// 0.6–1.4/s on all of them and silence produces nothing, so a consumer needs no
        /// gate. Full evidence: `docs/diagnostics/FTR15_SIZE_READS_LEVEL_2026-08-13.md` §9.
        public var levelRise: Float
    }
}
