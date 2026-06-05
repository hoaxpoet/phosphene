// NimbusState — Per-preset world state for the Nimbus volumetric preset.
//
// Nimbus is a `direct` preset whose GPU side is stateless frame-to-frame (the
// body is recomputed every frame). Everything temporal lives here, CPU-side,
// flushed each frame to the buffer the shader reads at fragment buffer(6).
//
// NB.4 (Energy) shipped a single broadband-energy "bloom" follower. The
// 2026-06-05 Atlas (Battles) session showed that model was too subtle and, on
// bass-dominated music, structurally broken: the bloom averaged three bands
// `(bass+mid+treble)`, and with mid/treble near-silent the two dead bands
// vetoed it — the body sat near floor-size all session while the relentless
// 136-BPM beat went unanswered. Matt's call: wrong model — drive from the beat,
// per stem. (Reverses the original "nothing on the beat" premise; see
// NIMBUS_DESIGN §1.3 and DECISIONS.)
//
// NB.5 — the band plays the body. One coherent gaseous mass that HEAVES with
// the full band: each stem pushes a soft, blended bulge of the *single*
// envelope (a star-convex deformation — it cannot fragment into separate
// blobs), driven by a fast-attack/slow-release follower so it puffs on the hit
// and settles. Layers (one audio primitive per layer — FA #67):
//
//   • bloom      — slow overall size/brightness swell ← mean of the four stem
//                  ENERGIES (robust; never floored by a dead band). FV bass
//                  proxy during the ~10 s stem warmup (D-019 blend).
//   • kickPunch  — whole-body inflate + brightness pop ← the onset pulse
//                  `max(beatBass, beatComposite)` (zero-delay, frame 1),
//                  refined toward the drums-stem deviation as it converges. The
//                  hero beat moment; the kick is the spine of the beat.
//   • bassLobe   — heaves the body DOWN  ← bass-stem energy deviation (D-026).
//   • vocalsLobe — flares the body UP    ← lead/"vocals"-stem deviation.
//   • otherLobe  — swells the body SIDE  ← other-stem deviation.
//   • flowPhase  — gas churn phase, advancing faster with bloom + on kicks.
//
// The three directional lobes are stem-only (no FV proxy) so they sit at zero
// until the live stem analyzer converges, then ramp in naturally.
//
// The state buffer is bound at fragment buffer(6) via
// `RenderPipeline.setDirectPresetFragmentBuffer` (orthogonal to noiseVolume at
// *texture* 6). @unchecked Sendable + NSLock for audio-thread safety;
// .storageModeShared MTLBuffer for UMA; per-frame tick(...) flush.

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.presets", category: "Nimbus")

// MARK: - GPU struct

/// GPU-side state — 32 bytes, must match `NimbusStateGPU` in `Nimbus.metal`
/// byte-for-byte. Six load-bearing floats + two pads for 16-byte alignment.
struct NimbusStateGPU {
    var bloom: Float        // slow overall size/brightness swell (0 floor … ~1 peak)
    var flowPhase: Float    // gas churn phase (seconds-equivalent, bloom + kick modulated)
    var kickPunch: Float    // whole-body beat punch (0 … ~1), fast attack / fast settle
    var bassLobe: Float     // downward heave (0 … ~1)
    var vocalsLobe: Float   // upward flare (0 … ~1)
    var otherLobe: Float    // sideways swell (0 … ~1)
    var padA: Float
    var padB: Float

    static let zero = NimbusStateGPU(
        bloom: 0,
        flowPhase: 0,
        kickPunch: 0,
        bassLobe: 0,
        vocalsLobe: 0,
        otherLobe: 0,
        padA: 0,
        padB: 0
    )
}

// MARK: - NimbusState

/// Owns the bloom swell, the four stem beat-followers, and the gas flow-phase
/// accumulator, plus the GPU buffer for the Nimbus preset.
///
/// Thread-safe: `tick()` and `stateBuffer` can be accessed from any queue.
public final class NimbusState: @unchecked Sendable {

    // MARK: - Constants (DESIGN §1.3 / §5.4 — starting points; Matt's eye sets finals)

    /// Slow bloom swell follower (overall size/brightness). Gentle.
    private static let bloomAttackTau: Float = 0.15
    private static let bloomReleaseTau: Float = 0.40

    /// bloom target = meanStemEnergy·gain + offset. Mean stem energy is AGC-
    /// centred at ~0.5 (baseline) → ~0.5 bloom; quiet (0.2) → ~0.08 floor; loud
    /// (0.9) → ~1.06. Never floored by a single dead band (the NB.4 bug).
    private static let bloomGain: Float = 1.40
    private static let bloomOffset: Float = -0.20
    private static let bloomMax: Float = 1.10

    /// Whole-body kick punch follower. SHARP: snaps up on the hit, settles in
    /// ~160 ms so it reads as a punch on a 440 ms (136 BPM) beat, not a smear.
    private static let kickAttackTau: Float = 0.04
    private static let kickReleaseTau: Float = 0.16

    /// Directional stem-lobe followers. A touch slower than the kick so they
    /// read as heaves, not flickers.
    private static let lobeAttackTau: Float = 0.06
    private static let lobeReleaseTau: Float = 0.28

    /// smoothstep window on the stem energy deviations (D-026) → a clean [0,1]
    /// per-stem hit signal. **NB.5 recalibration:** the Atlas live session showed
    /// the deviations sit at ~0.3–0.4 mean and cross 0.8 on only **1–3 % of
    /// frames** — so the old [0.30, 1.10] window meant the lobes essentially
    /// never fired ("uniform, no direction"). [0.12, 0.55] fires on the real
    /// distribution: gentle at typical activity, full on the more-prominent hits.
    private static let devThreshLo: Float = 0.12
    private static let devThreshHi: Float = 0.55

    /// Cold-start convergence window (seconds since track start). Below
    /// `stemConvergeLo` the model is fully on the live FeatureVector beat (the
    /// cached stems are a constant snapshot and can't drive per-beat motion);
    /// above `stemConvergeHi` it is fully on the live per-frame stems. The
    /// crossfade spans the live-stem-analyzer convergence (~CSP 14 s window).
    private static let stemConvergeLo: Float = 9.0
    private static let stemConvergeHi: Float = 13.0

    /// Gas flow speed at the silence floor (bloom 0) and at full bloom (bloom 1),
    /// as a multiple of the NB.3 wall-clock drift rate; plus a per-kick churn
    /// boost so the gas roils on the beat.
    private static let flowFloor: Float = 0.50
    private static let flowPeak: Float = 1.75
    private static let flowKickBoost: Float = 1.00

    // MARK: - Public Properties

    /// GPU-side state buffer (32 bytes, shared storage). Bound at fragment
    /// buffer(6) by `VisualizerEngine+Presets.swift`.
    public let stateBuffer: MTLBuffer

    /// Most-recent follower values (diagnostics / the DESIGN §5.6 trace).
    public private(set) var bloom: Float = 0
    public private(set) var kickPunch: Float = 0
    public private(set) var bassLobe: Float = 0
    public private(set) var vocalsLobe: Float = 0
    public private(set) var otherLobe: Float = 0
    public private(set) var flowPhase: Float = 0

    // MARK: - Private State

    /// Flow phase in `Double` so a long session doesn't drift (long-accumulator
    /// rule). Flushed to `Float` each frame.
    private var flowPhaseAccum: Double = 0

    /// Seconds since track start (reset by `reset()`), in `Double`. Drives the
    /// cold-start gate — see `stemConvergeLo/Hi`. Self-tracked rather than read
    /// from `features.trackElapsedS` so it does not depend on the FFO cold-start
    /// UserDefaults toggle (which can pin that field to 100).
    private var trackTime: Double = 0
    private let lock = NSLock()

    // MARK: - Init

    /// Creates a new NimbusState at the silence floor (all followers 0) —
    /// silence-stable from frame zero.
    public init?(device: MTLDevice) {
        let bufferSize = MemoryLayout<NimbusStateGPU>.stride
        guard let buf = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            logger.error("NimbusState: failed to allocate stateBuffer (\(bufferSize) bytes)")
            return nil
        }
        stateBuffer = buf
        writeToGPU()
    }

    // MARK: - Public API

    /// Tick all followers + the flow-phase accumulator for one rendered frame
    /// and flush to the GPU buffer. Call once per frame from the render-loop
    /// tick hook before the scene draw.
    public func tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures) {
        lock.withLock { _tick(deltaTime: deltaTime, features: features, stems: stems) }
        writeToGPU()
    }

    /// Reset all followers + flow phase to the silence floor. Call at track
    /// change / segment boundaries so the body settles into the new track
    /// rather than carrying the prior state across the cut (DESIGN §1.5).
    public func reset() {
        lock.withLock {
            bloom = 0; kickPunch = 0
            bassLobe = 0; vocalsLobe = 0; otherLobe = 0
            flowPhase = 0
            flowPhaseAccum = 0
            trackTime = 0   // restart the cold-start gate for the new track
        }
        writeToGPU()
    }

    // MARK: - Private: tick

    private func _tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures) {
        // Clamp dt — the first frame after preset apply can carry a stale value.
        let dt = min(max(deltaTime, 0.001), 0.1)

        // ── Cold-start gate (NB.5 fix) — TIME-based, not energy-based ────────
        // On a cache-hit track the stems are a CONSTANT snapshot for ~10 s
        // (drumsEnergy etc. frozen), and they carry energy — so the old
        // energy-based warmup gate (smoothstep(totalStemEnergy)) flipped onto
        // them IMMEDIATELY and froze the kick / lobes / bloom (the live
        // "didn't move for ~20 s"). Gate on time-since-track-start instead:
        // drive from the live FeatureVector beat (pulses from frame 1) until
        // the live per-frame stem analyzer has actually converged (~9–13 s),
        // then cross to the stems. trackTime resets on reset() (track change).
        trackTime += Double(dt)
        let stemMix = nbSmoothstep(Self.stemConvergeLo, Self.stemConvergeHi, Float(trackTime))
        let totalStemEnergy = stems.drumsEnergy + stems.bassEnergy
                            + stems.vocalsEnergy + stems.otherEnergy

        // ── Slow bloom swell (overall size/brightness) ───────────────────────
        // Mean of the four stem energies (AGC-centred ~0.5; never floored by one
        // dead band). FV bass proxy during warmup (reliable from frame 1).
        let meanStemEnergy = totalStemEnergy / 4.0
        let bloomProxy = nbClamp(0.5 + 0.5 * features.bassAttRel, 0, 1)
        let bloomDrive = nbMix(bloomProxy, meanStemEnergy, stemMix)
        let bloomTarget = nbClamp(bloomDrive * Self.bloomGain + Self.bloomOffset, 0, Self.bloomMax)
        bloom = follow(bloom, bloomTarget, dt, Self.bloomAttackTau, Self.bloomReleaseTau)

        // ── Whole-body kick punch — the hero beat moment ─────────────────────
        // Onset pulse (zero-delay, frame 1) blended toward the drums-stem hit
        // signal as stems converge. max(beatBass, beatComposite) covers both
        // kick- and snare-driven tracks (FA #26).
        let fvBeat = max(features.beatBass, features.beatComposite)
        let drumsHit = nbSmoothstep(Self.devThreshLo, Self.devThreshHi, stems.drumsEnergyDev)
        let kickSignal = nbMix(fvBeat, drumsHit, stemMix)
        kickPunch = follow(kickPunch, kickSignal, dt, Self.kickAttackTau, Self.kickReleaseTau)

        // ── Directional stem lobes ───────────────────────────────────────────
        // Gated by stemMix so they ramp in only once the LIVE stems vary (not
        // frozen on the constant cached snapshot during cold-start). The
        // recalibrated [devThreshLo, devThreshHi] window fires on the real
        // deviation distribution (~0.3–0.4 mean, rarely past 0.8) — the old
        // [0.30, 1.10] crossed on only 1–3 % of frames, so the lobes never fired.
        let bassTarget = nbSmoothstep(Self.devThreshLo, Self.devThreshHi, stems.bassEnergyDev) * stemMix
        bassLobe = follow(bassLobe, bassTarget, dt, Self.lobeAttackTau, Self.lobeReleaseTau)
        let vocalsTarget = nbSmoothstep(Self.devThreshLo, Self.devThreshHi, stems.vocalsEnergyDev) * stemMix
        vocalsLobe = follow(vocalsLobe, vocalsTarget, dt, Self.lobeAttackTau, Self.lobeReleaseTau)
        let otherTarget = nbSmoothstep(Self.devThreshLo, Self.devThreshHi, stems.otherEnergyDev) * stemMix
        otherLobe = follow(otherLobe, otherTarget, dt, Self.lobeAttackTau, Self.lobeReleaseTau)

        // ── Flow phase: churn at a bloom-modulated rate, surging on kicks ────
        let bloomForFlow = nbClamp(bloom, 0, 1)
        let flowSpeed = Self.flowFloor + (Self.flowPeak - Self.flowFloor) * bloomForFlow
                      + Self.flowKickBoost * kickPunch
        flowPhaseAccum += Double(dt) * Double(flowSpeed)
        flowPhase = Float(flowPhaseAccum)
    }

    // MARK: - Private: follower + math helpers

    /// Asymmetric one-pole follower: fast attack, slow release, framerate-
    /// independent via `1 − exp(−dt/τ)`.
    private func follow(_ current: Float, _ target: Float, _ dt: Float,
                        _ attackTau: Float, _ releaseTau: Float) -> Float {
        let tau = target > current ? attackTau : releaseTau
        let coeff = 1.0 - exp(-dt / tau)
        return current + (target - current) * coeff
    }

    private func nbSmoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let tt = nbClamp((x - edge0) / (edge1 - edge0), 0, 1)
        return tt * tt * (3 - 2 * tt)
    }

    private func nbClamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
        min(max(x, lo), hi)
    }

    private func nbMix(_ lhs: Float, _ rhs: Float, _ mixT: Float) -> Float {
        lhs + (rhs - lhs) * mixT
    }

    // MARK: - Private: GPU write

    private func writeToGPU() {
        var packed = NimbusStateGPU(
            bloom: bloom,
            flowPhase: flowPhase,
            kickPunch: kickPunch,
            bassLobe: bassLobe,
            vocalsLobe: vocalsLobe,
            otherLobe: otherLobe,
            padA: 0,
            padB: 0
        )
        stateBuffer.contents().copyMemory(
            from: &packed,
            byteCount: MemoryLayout<NimbusStateGPU>.stride
        )
    }
}
