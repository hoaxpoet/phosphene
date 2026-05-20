// AuroraVeilState — Per-preset world state for the Aurora Veil mv_warp preset (AV.2).
//
// Maintains two pieces of persistent state that the fragment shader needs
// across frames:
//
//   • `kinkAccumulator` — drum-coupled curtain-kink charge. Rare-event gated
//     through `smoothstep(0.4, 0.7, drumsEnergyDev)` so brief kicks don't
//     fire it; once charged, decays at ~0.93/frame so the visual reads as a
//     1–2 s slow shudder rather than a per-beat strobe (Failure Mode #11
//     mitigation per `AURORA_VEIL_DESIGN.md §5.6` + research §3.2).
//
//   • `smoothedPitchNorm` — 5-frame moving average of `vocalsPitchNorm` =
//     `log2(max(vocalsPitchHz, 80)/80) / 4`. YIN/CREPE pitch estimates can
//     hop between adjacent semitones frame-to-frame; without smoothing the
//     ribbon's palette phase would jitter visibly. Smoothing settles the
//     hue migration to the Sigur-Rós-grade slow melodic walk the preset's
//     §5.7 vocal-pitch route is designed to produce. Confidence-gated: a
//     frame with `vocalsPitchConfidence < 0.5` pushes the neutral 0.5
//     baseline rather than the raw value, so the buffer stays sane through
//     unvoiced sections and silence (`AURORA_VEIL_DESIGN.md §5.8`
//     fallback). The shader applies its own confidence gate on top.
//
// The state buffer is bound at fragment buffer(6) via
// `RenderPipeline.setDirectPresetFragmentBuffer` (the same slot Gossamer
// uses for its wave pool — slot allocation is per-preset, not global). The
// shader reads it as `constant AuroraVeilStateGPU& av [[buffer(6)]]`.
//
// Mirrors the GossamerState pattern (D-019 stem-warmup blend, NSLock for
// audio-thread safety, MTLBuffer with .storageModeShared for UMA, per-frame
// `tick(deltaTime:features:stems:)` flush to GPU).

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.presets", category: "AuroraVeil")

// MARK: - GPU struct

/// GPU-side state — 16 bytes, must match `AuroraVeilStateGPU` in
/// `AuroraVeil.metal` byte-for-byte. Padding fields hold the 16-byte
/// alignment Metal expects for `constant&` buffer reads.
struct AuroraVeilStateGPU {
    var kinkAccumulator: Float       // 0 at silence; rare-event drum charge
    var smoothedPitchNorm: Float     // 0.5 neutral fallback; 0..1 mapped log2(pitch_hz/80)/4
    var padA: Float
    var padB: Float

    static let zero = AuroraVeilStateGPU(
        kinkAccumulator: 0,
        smoothedPitchNorm: 0.5,
        padA: 0,
        padB: 0
    )
}

// MARK: - AuroraVeilState

/// Owns the kink accumulator + pitch-smoothing ring and the GPU buffer for
/// the Aurora Veil preset.
///
/// Thread-safe: `tick()` and `stateBuffer` can be accessed from any queue.
public final class AuroraVeilState: @unchecked Sendable {

    // MARK: - Constants

    /// Per-frame kink decay coefficient at 60 fps (`AURORA_VEIL_DESIGN.md §5.6`).
    /// Re-mapped to the actual frame deltaTime via `pow(0.93, deltaTime × 60)`
    /// so a variable framerate doesn't change the visual shudder timescale.
    private static let kinkDecayPerFrame60: Float = 0.93

    /// Rare-event gate window on `drumsEnergyDev`. AV.2.h.1 (2026-05-20):
    /// tuned 0.9/1.5 → 0.7/1.0 after AV.2.h live-test session showed the
    /// 0.9/1.5 gate fired 0 % of frames on Billie Jean (`drumsEnergyDev`
    /// max was 0.849 — never crossed the 0.9 threshold). The "rare event"
    /// target was overcorrected; on lighter-drum music like Billie Jean
    /// the kink route disappeared entirely. 0.7/1.0 fires ~0.7 % of
    /// frames on Billie Jean (~1 shudder per 2.5 s) and ~2-3 % on
    /// heavy-drum tracks like Outkast — matches the design intent of
    /// "occasional 1-2 s shudder on bigger drum emphasis."
    /// Below 0.7: no charge. 0.7–1.0: smooth ramp. Above 1.0: full.
    private static let kinkChargeLo: Float = 0.7
    private static let kinkChargeHi: Float = 1.0

    /// Pitch-smoothing window length (§5.7 — "5-frame moving average").
    private static let pitchSmoothWindow = 5

    /// Pitch normalisation: `log2(max(hz, 80)/80) / 4` maps E2 ≈ 80 Hz → 0
    /// and ~C7 ≈ 1280 Hz → 1.0 (research §3.3). Re-clamp at the read site
    /// because the smoothing buffer can drift slightly outside [0, 1] when
    /// the source pitch is outside the nominal range.
    private static let pitchHzFloor: Float = 80
    private static let pitchOctaveSpan: Float = 4

    /// Confidence threshold under which we push the neutral 0.5 baseline into
    /// the smoothing buffer rather than the raw normalised pitch. Matches the
    /// shader's own gate so smoother and shader agree on what counts as a
    /// "confident" frame.
    private static let pitchConfidenceGate: Float = 0.5

    /// Neutral mid-palette baseline pushed at silence / low confidence.
    private static let pitchNeutralBaseline: Float = 0.5

    /// D-019 stem-warmup window — match Gossamer / Arachne so the per-stem
    /// reads behave identically across mv_warp presets.
    private static let stemWarmupLow: Float = 0.02
    private static let stemWarmupHigh: Float = 0.06

    // MARK: - Public Properties

    /// GPU-side state buffer (16 bytes, shared storage).
    ///
    /// Bound at fragment buffer(6) by `VisualizerEngine+Presets.swift` via
    /// `RenderPipeline.setDirectPresetFragmentBuffer`.
    public let stateBuffer: MTLBuffer

    /// Most-recent kink accumulator value (diagnostics).
    public private(set) var kinkAccumulator: Float = 0

    /// Most-recent smoothed-pitch value (diagnostics).
    public private(set) var smoothedPitchNorm: Float = 0.5

    // MARK: - Private State

    private var pitchRing: [Float]
    private var pitchRingHead: Int = 0
    private let lock = NSLock()

    // MARK: - Init

    /// Creates a new AuroraVeilState with a neutral pitch buffer (all 0.5)
    /// and zero kink charge — silence-stable from frame zero per §5.8.
    public init?(device: MTLDevice) {
        let bufferSize = MemoryLayout<AuroraVeilStateGPU>.stride
        guard let buf = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            logger.error("AuroraVeilState: failed to allocate stateBuffer (\(bufferSize) bytes)")
            return nil
        }
        stateBuffer = buf
        pitchRing = Array(repeating: Self.pitchNeutralBaseline, count: Self.pitchSmoothWindow)
        writeToGPU()
    }

    // MARK: - Public API

    /// Tick the accumulator + pitch smoother for one rendered frame and flush
    /// to the GPU buffer.
    ///
    /// Call once per frame from the render-loop tick hook before the scene
    /// draw (mirrors `GossamerState.tick(...)` wiring in
    /// `VisualizerEngine+Presets.swift`).
    public func tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures) {
        lock.withLock { _tick(deltaTime: deltaTime, features: features, stems: stems) }
        writeToGPU()
    }

    /// Reset both accumulators to silence-stable baselines. Call at segment
    /// boundaries to prevent ad-hoc cross-track bleed.
    public func reset() {
        lock.withLock {
            kinkAccumulator = 0
            smoothedPitchNorm = Self.pitchNeutralBaseline
            for i in 0..<pitchRing.count { pitchRing[i] = Self.pitchNeutralBaseline }
            pitchRingHead = 0
        }
        writeToGPU()
    }

    // MARK: - Private: tick

    private func _tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures) {
        // Clamp deltaTime — first frame after preset apply can carry a stale
        // accumulated value and large dt would over-decay the accumulator.
        let dt = min(max(deltaTime, 0.001), 0.1)

        // D-019 warmup mix: pre-stems → FV proxy; post-warmup → stems direct.
        let totalStemEnergy = stems.vocalsEnergy + stems.drumsEnergy
                            + stems.bassEnergy + stems.otherEnergy
        let stemMix = avSmoothstep(Self.stemWarmupLow, Self.stemWarmupHigh, totalStemEnergy)

        // ── Kink accumulator (route 5) ───────────────────────────────────────
        // No FV proxy exists for drums_energy_dev (D-026 deviation primitive
        // is stems-only). Pre-warmup → drumsDev reads as zero → the
        // accumulator decays at 0.93/frame from whatever it was; at silence
        // it stays at 0 by construction. Post-warmup → drumsDev gates through
        // the rare-event smoothstep.
        let drumsDev = stemMix * max(0, stems.drumsEnergyDev)
        let chargeGate = avSmoothstep(Self.kinkChargeLo, Self.kinkChargeHi, drumsDev)
        let chargeNow = drumsDev * chargeGate
        let decay = pow(Self.kinkDecayPerFrame60, dt * 60.0)
        kinkAccumulator = max(kinkAccumulator * decay, chargeNow)

        // ── Pitch smoother (route 1) ─────────────────────────────────────────
        // Push the next ring slot. Low-confidence frames push 0.5 baseline so
        // unvoiced sections don't pull the smoother toward whatever spurious
        // hz value the YIN tracker emitted.
        let nextSample: Float = {
            guard stems.vocalsPitchConfidence >= Self.pitchConfidenceGate,
                  stems.vocalsPitchHz > 0 else {
                return Self.pitchNeutralBaseline
            }
            let hz = max(stems.vocalsPitchHz, Self.pitchHzFloor)
            let norm = log2(hz / Self.pitchHzFloor) / Self.pitchOctaveSpan
            return avClamp(norm, 0, 1)
        }()
        pitchRing[pitchRingHead] = nextSample
        pitchRingHead = (pitchRingHead + 1) % pitchRing.count

        var sum: Float = 0
        for sample in pitchRing { sum += sample }
        smoothedPitchNorm = sum / Float(pitchRing.count)

        // Touch the FV reference so the parameter doesn't trip an unused warning
        // — features is reserved for future routes (e.g. valence-driven pitch
        // smoothing-window length) that may land at AV.3 polish.
        _ = features.time
    }

    // MARK: - Private: GPU write

    private func writeToGPU() {
        var packed = AuroraVeilStateGPU(
            kinkAccumulator: kinkAccumulator,
            smoothedPitchNorm: smoothedPitchNorm,
            padA: 0,
            padB: 0
        )
        stateBuffer.contents().copyMemory(
            from: &packed,
            byteCount: MemoryLayout<AuroraVeilStateGPU>.stride
        )
    }

    // MARK: - Private: math helpers

    private func avSmoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let tt = avClamp((x - edge0) / (edge1 - edge0), 0, 1)
        return tt * tt * (3 - 2 * tt)
    }

    private func avClamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
        min(max(x, lo), hi)
    }
}
