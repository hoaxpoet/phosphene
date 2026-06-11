// RenderPipeline+AudioDrivers — the CPU-side per-frame audio drivers feeding
// the Ferrofluid Ocean sky and spike field (D-127 / BUG-041 / FBS.S3.2 /
// FBS.S5 / FBS Stage 2).
//
// Every driver here is a PURE, deterministic step function so the flash
// forensics harness (`FerrofluidFlashForensicsTests`) and the real-session
// replay tests run the exact production arithmetic. The per-frame state
// lives on `RenderPipeline` (MainActor ray-march draw path, no locks);
// `drawWithRayMarch` ticks the steps and patches the outputs into the stems
// snapshot bound at fragment buffer(3).

import Foundation

extension RenderPipeline {

    // MARK: - Aurora drums driver (D-127 smoother + BUG-041 track-start warmup)

    /// Seconds for the per-track aurora warmup ramp (BUG-041). Sized from the
    /// measured overswing window: the stem-deviation cold start settles by
    /// ~10 s on every observed track (worst peaks at 2–8 s).
    static let auroraWarmupSeconds: Float = 10.0

    /// Result of one `auroraDriverStep` frame (struct, not tuple — lint).
    struct AuroraDriverState {
        let smoothed: Float
        let warmup01: Float
        let output: Float
    }

    /// One frame of the aurora drums driver (D-127, hardened by BUG-041 and
    /// FBS.S3.2). Pure + deterministic so the real-session replay test runs
    /// the exact production arithmetic.
    ///
    /// FBS.S3.2 (2026-06-10, session `17-50-56Z`): Matt's flagged flash
    /// timestamps all coincide with MID-TRACK stem-deviation bursts (all four
    /// stems spiking 3–30× the track median together — So What hit dev = 35).
    /// The original 150 ms EMA passed those to the sky as 2–3-frame flares.
    /// Two changes:
    ///  - SOFT-KNEE input: `dev / (1 + 0.6·dev)` — small values pass almost
    ///    unchanged (0.3 → 0.25), bursts cap (1.0 → 0.63, 35 → 1.64). The
    ///    aurora still surges on real hits; it cannot be blinded by a burst.
    ///  - ASYMMETRIC response: rise τ 0.45 s (a visible bloom, not a flash —
    ///    max per-frame output step ≈ 0.06 at 60 fps), fall τ 1.2 s (glow
    ///    decays like an afterimage). Replaces the symmetric 150 ms τ.
    /// The BUG-041 per-track quadratic warmup gate is unchanged on top.
    ///
    /// FBS.S5 briefly slowed BOTH τ to 2.7/3.3 s; FBS.S5b (Matt's pick)
    /// reverted the intensity to 0.45/1.2 — the proven flasher was the HUE
    /// route (stays slow, `auroraHueStep` τ 3 s), 0.45/1.2 was measured
    /// flash-safe (S3.2 gates, S4 ablation), and slowing it killed the
    /// per-drum-hit shimmer that carried the openings' rhythm feel. D-158.
    static func auroraDriverStep(
        smoothed: Float,
        warmup01: Float,
        drumsDev: Float,
        dt: Float
    ) -> AuroraDriverState {
        let knee = max(0, drumsDev) / (1.0 + 0.6 * max(0, drumsDev))
        let tau: Float = knee > smoothed ? 0.45 : 1.2
        let alpha = 1.0 - exp(-dt / tau)
        let nextSmoothed = smoothed + alpha * (knee - smoothed)
        let nextWarmup = min(1.0, warmup01 + max(0, dt) / Self.auroraWarmupSeconds)
        // Quadratic ease-in warmup (BUG-041): smallest exactly where the
        // track-start deviation overswing peaks; ~1 once the analyzer has
        // converged.
        let gate = nextWarmup * nextWarmup
        return AuroraDriverState(
            smoothed: nextSmoothed,
            warmup01: nextWarmup,
            output: nextSmoothed * gate)
    }

    // MARK: - Aurora hue driver (FBS.S5, D-158)

    /// EMA time constant for the aurora palette phase. 3τ ≈ 9 s — a hue
    /// transition completes over Matt's directed 8–10 s window.
    static let auroraHueTauSeconds: Float = 3.0

    /// One frame of the aurora hue driver. Pure + deterministic so the flash
    /// forensics harness runs the exact production arithmetic.
    ///
    /// Computes the SAME composite phase target the Ferrofluid Ocean sky
    /// shader (`rm_ferrofluidSky`) used to derive per-pixel from raw stem
    /// fields — perceptual log-scale pitch over 80 Hz–1 kHz, confidence-gated
    /// (smoothstep 0.5→0.7) against the valence fallback — then low-passes it
    /// with a τ ≈ 3 s EMA.
    ///
    /// Why (FBS.S5 forensics, session `2026-06-10T19-13-14Z`): the raw
    /// confidence flapped across the 0.5 gate boundary ~9×/s on real music
    /// (90 crossings in the 10 s So What window), snapping the curtain hue
    /// between the pitch phase and the valence phase — at curtain intensity
    /// 2.5–5.5 reflected across the whole mirror substrate, each snap stepped
    /// the entire frame's luminance. Ablation proof: replicating the pitch
    /// fields took the replica 1 → 13 flash steps (So What 31–41 s) and
    /// 0 → 15 (Lotus 45–51 s); zeroing only those fields restored 1 / 0.
    /// Smoothing the composite target averages gate flapping to a stable
    /// intermediate hue, while a sustained vocal entry glides the hue over
    /// ~9 s — Matt's directed character.
    static func auroraHueStep(
        smoothedPhase: Float,
        pitchHz: Float,
        pitchConfidence: Float,
        valence: Float,
        dt: Float
    ) -> Float {
        // Constants mirror the pre-S5 shader math (rm_ferrofluidSky).
        let refLowHz: Float = 80.0
        let refHighHz: Float = 1000.0
        let maxShift: Float = 0.20
        let hz = min(max(pitchHz, refLowHz), refHighHz)
        let pitchNorm = log2(hz / refLowHz) / log2(refHighHz / refLowHz)
        let pitchPhase = (pitchNorm - 0.5) * 2.0 * maxShift
        let valencePhase = min(max(valence, -1.0), 1.0) * maxShift
        let edge = min(max((pitchConfidence - 0.5) / 0.2, 0.0), 1.0)
        let gate = edge * edge * (3.0 - 2.0 * edge)
        let target = valencePhase + (pitchPhase - valencePhase) * gate
        let alpha = 1.0 - exp(-max(0, dt) / Self.auroraHueTauSeconds)
        return smoothedPhase + alpha * (target - smoothedPhase)
    }

    // MARK: - Punch energy driver (FBS Stage 2)

    /// EMA time constant for the passage-loudness envelope that scales the
    /// FFO beat-punch height. SYMMETRIC by measurement: an asymmetric
    /// fast-rise variant (0.8 s up / 2.5 s down) acted as a peak-follower on
    /// sparse jazz — So What's intro stem sum is BURSTY (median 0.22,
    /// p90 1.28), so riding bursts up fast put the "quiet" intro at height
    /// 0.67 instead of ~0.40 and collapsed the band/intro ratio to 1.5×.
    /// Symmetric 2.5 s tracks the passage MEAN (intro 0.40 / band 0.99,
    /// ratio 2.5× on the fixture). Loudness transitions complete in ~7 s;
    /// per-hit drama stays the aurora drums driver's job (0.45 s rise).
    static let punchEnergyTau: Float = 2.5

    /// One frame of the FBS Stage 2 punch-energy envelope. Pure +
    /// deterministic so the forensics harness replays the exact arithmetic.
    ///
    /// Input is the TOTAL stem energy (drums + bass + vocals + other — the
    /// same sum the FFO sky's live gate reads). Measured on real sessions
    /// (`2026-06-11T01-56-22Z`), it is the signal that survives the AGC:
    /// So What's bass+piano intro reads 0.33–0.35 vs 0.8–1.5 once the band
    /// enters (4× separation), Love Rehab / Pyramid open at 1.1+ (no false
    /// quiet on strong openings), while the AGC'd FeatureVector band sum is
    /// flat ~0.25 across all of it (Failed Approach #31's prediction).
    ///
    /// The output is the smoothed loudness itself; the height MAPPING
    /// (smoothstep + floor) lives in the shader next to the punch code
    /// (`fo_spike_strength`) — kickoff §Stage 2: energy sets SIZE only,
    /// the beat keeps the timing.
    static func punchEnergyStep(
        smoothed: Float,
        totalStemEnergy: Float,
        dt: Float
    ) -> Float {
        let target = max(0, totalStemEnergy)
        let alpha = 1.0 - exp(-max(0, dt) / Self.punchEnergyTau)
        return smoothed + alpha * (target - smoothed)
    }

    // MARK: - Aurora orbit driver (BUG-047)

    /// Base curtain revolution period in accumulated-audio-time seconds —
    /// round 61's Matt-tuned value, moved verbatim from `rm_ferrofluidSky`
    /// (`kCurtainBaseRevolutionSeconds`). At the typical ~7 % wall-clock
    /// rate of `accumulated_audio_time`, a palette half-cycle spans ~30 s.
    static let auroraOrbitBaseRevolutionS: Float = 2.5

    /// One frame of the aurora orbit (BUG-047). Pure + deterministic for
    /// the forensics replica.
    ///
    /// The shader used to compute `azimuth = arousalSpeed × accumulatedTime`
    /// — the speed factor multiplied the ENTIRE elapsed total, so any
    /// arousal movement retroactively rescaled history: per-second mood
    /// wobble on jazz teleported the curtain azimuth ±2+ radians/s and the
    /// palette marched green→pink→purple second-by-second (Matt's So What
    /// read, session `2026-06-11T13-10-42Z`; measured palette-t jumps of
    /// 0.2–0.3/s vs the designed ≤0.03/s). The error grows with elapsed
    /// time — openings looked fine, minute-two thrashed. The fix is the
    /// design comment's actual meaning: arousal scales the orbit SPEED, so
    /// integrate `speed × Δtime` per frame.
    ///
    /// `aatDelta` ≤ 0 (track-change reset of the accumulator) advances
    /// nothing — the orbit simply continues from where it was.
    static func auroraOrbitStep(
        azimuth: Float,
        aatDelta: Float,
        arousal: Float
    ) -> Float {
        // arousalSpeed = mix(0.5, 1.0, smoothstep(-1, 1, arousal)) — verbatim
        // from the pre-fix shader.
        let x = min(max((arousal + 1.0) / 2.0, 0.0), 1.0)
        let speed = 0.5 + 0.5 * (x * x * (3.0 - 2.0 * x))
        let angular = 2.0 * Float.pi / Self.auroraOrbitBaseRevolutionS
        return azimuth + max(0, aatDelta) * speed * angular
    }
}
