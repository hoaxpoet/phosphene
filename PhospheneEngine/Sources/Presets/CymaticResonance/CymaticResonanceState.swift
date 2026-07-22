// CymaticResonanceState — Per-preset world state for the Cymatic Resonance preset.
//
// Cymatic Resonance is a `direct` + `post_process` preset whose GPU side is
// stateless frame-to-frame (the plate figure is recomputed every frame). The
// only temporal quantities — the EMA-smoothed mode-ladder position and the
// bass-drop snap envelope — live here, CPU-side, flushed each frame to the
// buffer the shader reads at fragment buffer(6). (CR.1; the slot-6 direct-state
// pattern is Nimbus / Aurora Veil; see docs/presets/psychedelic_geometry/
// PG_CR_CYMATIC_RESONANCE.md Part A.)
//
// Audio routing (one primitive per layer — FA #67):
//   • ladderPos ← spectral_centroid (EMA-smoothed, slow)  — HERO: which figure
//   • snap      ← bass_dev (deviation, D-026, event)       — snap-to-simple
//   • warmup    ← total stem energy (D-019 warmup gate)    — silence → dim
// Distinct primitives, distinct timescales; deviation/centroid only, never an
// absolute threshold on an AGC-normalized value (FA #31).

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.presets", category: "CymaticResonance")

// MARK: - GPU struct

/// GPU-side state — 16 bytes, must match `CymaticStateGPU` in
/// `CymaticResonance.metal` byte-for-byte.
struct CymaticStateGPU {
    /// Continuous mode-ladder position in [0, kLadderCount-1]. `floor` selects
    /// the low mode of the active crossfade pair, `fract` is the blend.
    var ladderPos: Float
    /// Excitation / brightness gate in [0,1]: `smoothstep(0.02,0.06,totalStemEnergy)`
    /// (D-019). 0 in sustained silence → the plate rests dim (non-black via the
    /// shader's emissive floor, D-037).
    var warmup: Float
    /// Bass-drop snap envelope in [0,1]. Fast attack on a `bass_dev` spike, slow
    /// release; folded into `ladderPos` already (kept for diagnostics + a subtle
    /// shader brightness kick on the restructure).
    var snap: Float
    /// Reserved (16-byte stride).
    var pad0: Float

    static let zero = CymaticStateGPU(ladderPos: 0, warmup: 0, snap: 0, pad0: 0)
}

// MARK: - CymaticResonanceState

/// Owns the centroid EMA → mode-ladder follower and the bass-drop snap envelope,
/// plus the GPU buffer for the Cymatic Resonance preset.
///
/// Thread-safe: `tick()` and `stateBuffer` can be accessed from any queue.
public final class CymaticResonanceState: @unchecked Sendable {

    // MARK: - Tunables (CR.1 starting points; Matt's M7 sets finals)

    /// Number of ladder modes (the fixed low→high complexity ladder in the shader:
    /// the same-parity (m,m+2) family (1,3)(2,4)…(11,13) — see the shader's kLadder
    /// note for why same-parity, CR.1 concept-gate correction #5).
    static let ladderCount: Int = 11

    /// Spectral-centroid EMA time constant — smooths the noisy per-frame centroid
    /// into a stable brightness read before it drives the ladder.
    private static let centroidTau: Float = 0.5
    /// Mode-ladder follower — the figure MORPHS between adjacent clean figures at
    /// this rate (slow, so transitions read as a bloom, not a pop).
    private static let ladderTau: Float = 0.8
    /// Excitation/warmup gate smoothing.
    private static let warmupTau: Float = 0.2

    /// `bass_dev` window for the snap trigger. Deviation primitives spike to ~3× on
    /// real music (p99 ≈ 0.85) — a strong bass hit crosses this window (never an
    /// absolute AGC threshold, FA #31 / [[project_deviation_primitive_real_range]]).
    private static let snapLo: Float = 0.45
    private static let snapHi: Float = 0.85
    /// Snap envelope: fast attack (the drop is instant), slow release (the figure
    /// climbs back up the ladder over ~0.6 s).
    private static let snapAttackTau: Float = 0.03
    private static let snapReleaseTau: Float = 0.55
    /// How hard a full snap yanks the ladder toward the simple fundamental (0 = no
    /// yank, 1 = all the way to mode (1,2)).
    private static let snapDepth: Float = 0.90

    /// Below this smoothed total-stem-energy the ladder target collapses to the
    /// fundamental (A5 — silence holds (1,2) regardless of a stale centroid).
    private static let silenceEnergyLo: Float = 0.0
    private static let silenceEnergyHi: Float = 0.04

    // MARK: - Public

    /// GPU-side state buffer (16 bytes, shared storage). Bound at fragment
    /// buffer(6) by `VisualizerEngine+Presets.swift`.
    public let stateBuffer: MTLBuffer

    /// Most-recent follower values (diagnostics / the closeout embodiment trace).
    public private(set) var ladderPos: Float = 0
    public private(set) var warmup: Float = 0
    public private(set) var snap: Float = 0

    // MARK: - Private state

    private var centroidEMA: Float = 0
    private var ladderSmooth: Float = 0   // pure centroid-driven ladder (snap is a separate overlay)
    private var energyEMA: Float = 0
    private let lock = NSLock()

    // MARK: - Init

    /// Creates a new state at the silence floor (fundamental, dim) — silence-stable
    /// from frame zero.
    public init?(device: MTLDevice) {
        let size = MemoryLayout<CymaticStateGPU>.stride
        guard let buf = device.makeBuffer(length: size, options: .storageModeShared) else {
            logger.error("CymaticResonanceState: failed to allocate stateBuffer (\(size) bytes)")
            return nil
        }
        stateBuffer = buf
        writeToGPU()
    }

    // MARK: - Public API

    /// Advance the ladder follower + snap envelope for one rendered frame and flush
    /// to the GPU buffer. Call once per frame from the render-loop tick hook before
    /// the scene draw.
    public func tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures) {
        lock.withLock { _tick(deltaTime: deltaTime, features: features, stems: stems) }
        writeToGPU()
    }

    /// Reset to the silence floor. Call at track change so the plate settles into
    /// the new track rather than carrying the prior figure across the cut.
    public func reset() {
        lock.withLock {
            centroidEMA = 0; ladderSmooth = 0; energyEMA = 0
            ladderPos = 0; warmup = 0; snap = 0
        }
        writeToGPU()
    }

    // MARK: - Private tick

    private func _tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures) {
        let dt = min(max(deltaTime, 0.001), 0.1)

        // Total stem energy (same construction as Nimbus): drives the D-019 warmup
        // gate. On a cache-hit track the frozen 5a snapshot carries energy so warmup
        // rises immediately; in true silence it is 0 → the plate rests dim.
        let totalStemEnergy = stems.drumsEnergy + stems.bassEnergy
                            + stems.vocalsEnergy + stems.otherEnergy
        energyEMA += (totalStemEnergy - energyEMA) * coeff(dt, Self.warmupTau)

        let warmupTarget = smoothstep(0.02, 0.06, totalStemEnergy)
        warmup += (warmupTarget - warmup) * coeff(dt, Self.warmupTau)

        // HERO — spectral centroid (brightness) → ladder target. Level-independent
        // and reliably alive (§14.1). EMA-smoothed, then collapsed to the fundamental
        // in silence so a stale centroid can't leave a complex figure at rest (A5).
        let centroid = clamp(features.spectralCentroid, 0, 1)
        centroidEMA += (centroid - centroidEMA) * coeff(dt, Self.centroidTau)
        let silenceGate = smoothstep(Self.silenceEnergyLo, Self.silenceEnergyHi, energyEMA)
        let ladderTarget = centroidEMA * Float(Self.ladderCount - 1) * silenceGate
        ladderSmooth += (ladderTarget - ladderSmooth) * coeff(dt, Self.ladderTau)

        // Snap-to-simple — bass_dev spike (event) yanks the ladder DOWN. Asymmetric
        // follower: fast attack, slow release. Kept as a separate overlay so the
        // centroid ladder (ladderSmooth) is never corrupted by the transient.
        let snapDrive = smoothstep(Self.snapLo, Self.snapHi, features.bassDev)
        let snapTau = snapDrive > snap ? Self.snapAttackTau : Self.snapReleaseTau
        snap += (snapDrive - snap) * coeff(dt, snapTau)

        // Derived ladder position: pull toward the fundamental (0) by the snap.
        ladderPos = mixf(ladderSmooth, 0.0, clamp(snap * Self.snapDepth, 0, 1))
    }

    // MARK: - Math helpers

    /// Framerate-independent one-pole coefficient `1 − exp(−dt/τ)`.
    private func coeff(_ dt: Float, _ tau: Float) -> Float { 1.0 - exp(-dt / tau) }

    private func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let tt = clamp((x - e0) / (e1 - e0), 0, 1)
        return tt * tt * (3 - 2 * tt)
    }

    private func clamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float { min(max(x, lo), hi) }
    private func mixf(_ lhs: Float, _ rhs: Float, _ mixT: Float) -> Float { lhs + (rhs - lhs) * mixT }

    // MARK: - GPU write

    private func writeToGPU() {
        var packed = CymaticStateGPU(ladderPos: ladderPos, warmup: warmup, snap: snap, pad0: 0)
        stateBuffer.contents().copyMemory(from: &packed, byteCount: MemoryLayout<CymaticStateGPU>.stride)
    }
}
