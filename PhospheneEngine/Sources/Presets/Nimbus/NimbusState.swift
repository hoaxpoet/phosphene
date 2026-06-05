// NimbusState — Per-preset world state for the Nimbus volumetric preset (NB.4).
//
// Nimbus is a `direct` preset: a single-pass volumetric ray-march whose GPU
// side is stateless frame-to-frame (the body is recomputed every frame). The
// only thing that persists across frames is a pair of CPU-side scalars — the
// Energy "bloom" and the gas "flow phase" — flushed each frame to a 16-byte
// buffer the shader reads at fragment buffer(6).
//
// NB.4 (Energy / Breath) is the hero coupling of the whole preset (DESIGN
// §1.3). One signal, three visual readings of the same physical event:
//
//   • `bloom` — a fast-attack / slow-release envelope follower over the
//     broadband energy deviation `(bass_att_rel + mid_att_rel + treb_att_rel)/3`
//     (D-026 deviation primitives — NEVER absolute energy thresholds, FA #31).
//     The asymmetric follower gives the gas momentum: it blooms quickly on a
//     swell and settles slowly afterward (never snaps). `bloom` drives the
//     body's size, luminosity, and flow rate in the shader so the three move
//     as ONE event (DESIGN §5.4 — one primitive per layer, FA #67).
//
//   • `flowPhase` — churn time accumulated at a bloom-modulated rate. The
//     shader advects the noise domain by this phase instead of raw wall-clock
//     `features.time`, so the gas flows faster with energy and eases to its
//     slowest drift (but never freezes) at the silence floor (DESIGN §5.2).
//     Accumulated in `Double` (CLAUDE.md long-accumulator rule — a `Float +=`
//     drifts/stalls over a long session) and flushed as `Float` each frame.
//
// NO beat field is read (DESIGN §1.3, FA #4 / FA #33) and NO mood (valence /
// arousal → colour + agitation is NB.6). Energy is the only driver here.
//
// The state buffer is bound at fragment buffer(6) via
// `RenderPipeline.setDirectPresetFragmentBuffer` (the same slot Aurora Veil /
// Gossamer use — per-preset, not global; orthogonal to the noiseVolume bound
// at *texture* 6). The shader reads it as `constant NimbusStateGPU& nb
// [[buffer(6)]]`.
//
// Mirrors the AuroraVeilState pattern (@unchecked Sendable + NSLock for
// audio-thread safety, MTLBuffer with .storageModeShared for UMA, per-frame
// `tick(deltaTime:features:stems:)` flush to GPU).

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.presets", category: "Nimbus")

// MARK: - GPU struct

/// GPU-side state — 16 bytes, must match `NimbusStateGPU` in `Nimbus.metal`
/// byte-for-byte. Padding fields hold the 16-byte alignment Metal expects for
/// `constant&` buffer reads.
struct NimbusStateGPU {
    var bloom: Float        // 0 at the silence floor; ~0.5 baseline; ~1 at peak
    var flowPhase: Float    // gas churn phase (seconds-equivalent, bloom-modulated)
    var padA: Float
    var padB: Float

    static let zero = NimbusStateGPU(bloom: 0, flowPhase: 0, padA: 0, padB: 0)
}

// MARK: - NimbusState

/// Owns the Energy bloom follower + gas flow-phase accumulator and the GPU
/// buffer for the Nimbus preset.
///
/// Thread-safe: `tick()` and `stateBuffer` can be accessed from any queue.
public final class NimbusState: @unchecked Sendable {

    // MARK: - Constants (DESIGN §1.3 / §5.4 — starting points; Matt's eye sets finals)

    /// Bloom follower attack time constant. Fast (~150 ms) so the gas blooms
    /// quickly on a swell — gas-like momentum (DESIGN §1.3).
    private static let bloomAttackTau: Float = 0.15

    /// Bloom follower release time constant. Slow (~400 ms) so the gas settles
    /// with momentum after a swell rather than snapping back (DESIGN §1.3).
    private static let bloomReleaseTau: Float = 0.40

    /// Linear map from the broadband energy deviation `(bass_att_rel +
    /// mid_att_rel + treb_att_rel)/3` to the bloom target. The deviation band is
    /// centred at 0 at the track's own AGC baseline, reaches −1 at true silence
    /// (bands hit 0 → `AttRel = (0 − 0.5)·2 = −1`), and rises positive on
    /// above-average swells. `target = rawEnergy·gain + offset`:
    ///   • silence  (−1) → ~0    (the floor)
    ///   • baseline ( 0) → ~0.5  (resting active body)
    ///   • swell    (+1) → ~1.05 (full bloom)
    private static let bloomGain: Float = 0.55
    private static let bloomOffset: Float = 0.50

    /// Soft ceiling on the bloom target. AttRel can occasionally spike past +1
    /// on big drops (the deviation primitives reach ~3× on real music — see
    /// `project_deviation_primitive_real_range`); the clamp soft-saturates so a
    /// huge swell gives a little extra bloom without blowing the body out.
    private static let bloomMax: Float = 1.10

    /// Gas flow speed at the silence floor (bloom 0) and at full bloom (bloom 1),
    /// expressed as a multiple of the NB.3 wall-clock drift rate. floor 0.5 →
    /// the silence drift is HALF the NB.3 speed (slower, per DESIGN §1.5 "eases
    /// to its slowest drift"); peak 1.75 → 3.5× the floor (DESIGN §1.3 churn
    /// rate "~1×→3.5×"). The flow never reaches zero — the gas visibly churns at
    /// all times, including at silence (DESIGN §5.7 "Flow is alive").
    private static let flowFloor: Float = 0.50
    private static let flowPeak: Float = 1.75

    // MARK: - Public Properties

    /// GPU-side state buffer (16 bytes, shared storage).
    ///
    /// Bound at fragment buffer(6) by `VisualizerEngine+Presets.swift` via
    /// `RenderPipeline.setDirectPresetFragmentBuffer`.
    public let stateBuffer: MTLBuffer

    /// Most-recent bloom value (diagnostics / the DESIGN §5.6 bloom scalar trace).
    public private(set) var bloom: Float = 0

    /// Most-recent flow phase (diagnostics).
    public private(set) var flowPhase: Float = 0

    // MARK: - Private State

    /// Flow phase accumulated in `Double` so a long session doesn't drift —
    /// CLAUDE.md long-accumulator rule. Flushed to `Float` each frame.
    private var flowPhaseAccum: Double = 0
    private let lock = NSLock()

    // MARK: - Init

    /// Creates a new NimbusState at the silence floor (bloom 0, flow phase 0) —
    /// silence-stable from frame zero. The body settles UP into the new track's
    /// level over the attack window rather than popping in at full size.
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

    /// Tick the bloom follower + flow-phase accumulator for one rendered frame
    /// and flush to the GPU buffer.
    ///
    /// Call once per frame from the render-loop tick hook before the scene draw
    /// (mirrors `AuroraVeilState.tick(...)` wiring in
    /// `VisualizerEngine+Presets.swift`). `stems` is unused — Nimbus's Energy
    /// driver reads FeatureVector deviation primitives only.
    public func tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures) {
        lock.withLock { _tick(deltaTime: deltaTime, features: features) }
        writeToGPU()
    }

    /// Reset the follower + flow phase to the silence floor. Call at track
    /// change / segment boundaries so the body settles into the new track's
    /// energy rather than carrying the previous track's bloom across the cut
    /// (DESIGN §1.5 — "a brief settle into the new body rather than an instant
    /// pop").
    public func reset() {
        lock.withLock {
            bloom = 0
            flowPhase = 0
            flowPhaseAccum = 0
        }
        writeToGPU()
    }

    // MARK: - Private: tick

    private func _tick(deltaTime: Float, features: FeatureVector) {
        // Clamp deltaTime — the first frame after preset apply can carry a stale
        // accumulated value; a large dt would over-step the follower / phase.
        let dt = min(max(deltaTime, 0.001), 0.1)

        // Broadband energy deviation (D-026): the three smoothed/attenuated band
        // deviations, averaged. Heavily smoothed → NO beat content (FA #4 / #33).
        let rawEnergy = (features.bassAttRel + features.midAttRel + features.trebAttRel) / 3.0

        // Map the deviation band to a [0, bloomMax] target (see bloomGain/offset).
        let target = min(max(rawEnergy * Self.bloomGain + Self.bloomOffset, 0), Self.bloomMax)

        // Asymmetric one-pole follower: fast attack (blooms on a swell), slow
        // release (settles with momentum). Framerate-independent via
        // `1 − exp(−dt/τ)` so a variable frame rate doesn't change the feel.
        let tau = target > bloom ? Self.bloomAttackTau : Self.bloomReleaseTau
        let coeff = 1.0 - exp(-dt / tau)
        bloom += (target - bloom) * coeff

        // Flow phase: churn time at a bloom-modulated rate. floor at silence,
        // up to flowPeak at full bloom. Accumulated in Double, flushed as Float.
        let bloomForFlow = min(max(bloom, 0), 1)
        let flowSpeed = Self.flowFloor + (Self.flowPeak - Self.flowFloor) * bloomForFlow
        flowPhaseAccum += Double(dt) * Double(flowSpeed)
        flowPhase = Float(flowPhaseAccum)
    }

    // MARK: - Private: GPU write

    private func writeToGPU() {
        var packed = NimbusStateGPU(
            bloom: bloom,
            flowPhase: flowPhase,
            padA: 0,
            padB: 0
        )
        stateBuffer.contents().copyMemory(
            from: &packed,
            byteCount: MemoryLayout<NimbusStateGPU>.stride
        )
    }
}
