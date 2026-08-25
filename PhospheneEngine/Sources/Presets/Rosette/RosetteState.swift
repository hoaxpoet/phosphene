// RosetteState — Per-preset world state for Rosette (WHIT.1d-2).
//
// The geometry fragment cannot synthesize two things per-frame alone, both because they
// need a value held ACROSS FRAMES (D-219 audit finding, WHIT.1d):
//
//   - a STATEFUL circular smoother for `tonalPhaseFifths` — a raw +/-pi sawtooth
//     (`TonalAnalyzer` emits it RAW; see `CircularPhaseSmoother.swift`, D-209). Reading it
//     straight into a visual channel jumps at the seam — the exact defect measured on
//     Fractal Tree (144 deg/p95 jump per update, Matt's M7: "Color changes feel glitchy,
//     not intentional"). Smooth cos/sin separately, recombine via atan2.
//   - a HOLD-TIMER for `harmonicFlux`-driven symmetry-order stepping, so a step lasts
//     "tens of seconds" (WHITNEY_PROGRAM.md §2's temporal contract) rather than flickering
//     on every chord-change spike (the explicit anti-contract: "the symmetry order must
//     never flicker").
//
// Pattern: GossamerState's minimal shape (one storageModeShared MTLBuffer, tick ->
// writeToGPU, a fixed-stride GPU struct matching the MSL struct byte-for-byte) — Rosette
// needs neither Skein's onset-burst ring nor its per-track palette, so this is much
// smaller than SkeinState.

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.presets", category: "Rosette")

// MARK: - RosetteUniformsGPU

/// GPU mirror — must match `RosetteUniforms` in Rosette.metal byte-for-byte. 16 bytes.
struct RosetteUniformsGPU {
    var smoothedFifths: Float   // circularly-smoothed tonal_phase_fifths, radians (D-209)
    var symmetryN: Float        // current held symmetry order (WHIT.1d-2)
    var pad0: Float
    var pad1: Float
}

// MARK: - RosetteState

/// Owns the circular-phase smoother for `tonalPhaseFifths` and the hold-timer for
/// `harmonicFlux`-driven symmetry-order stepping. The GPU-side buffer is bound at
/// fragment buffer(6) of the Rosette marks-on-top overlay.
///
/// Thread-safe: `tick()` and `rosetteBuffer` can be accessed from any queue.
public final class RosetteState: @unchecked Sendable {

    // MARK: - Constants

    /// Symmetry order sequence Whitney's own films step through (`WHITNEY_PROGRAM.md`
    /// §2: "5-fold -> 6-fold -> 4-fold"). Cycles; index 0 is the base order the film's
    /// `rosette_build.png` passage stays at throughout.
    public static let symmetrySequence: [Float] = [5, 6, 4]

    /// Minimum seconds between symmetry-order steps (`WHITNEY_PROGRAM.md` §2's temporal
    /// contract: "held for tens of seconds at a time; anything that steps it at beat
    /// rate is a defect, not a feature"). 24s is comfortably inside "tens of seconds"
    /// while still stepping more than once across a typical track.
    public static let minHoldSeconds: Float = 24.0

    /// `harmonicFlux` spike threshold. TONAL.2b's calibration (`WHITNEY_PROGRAM.md` §5.2):
    /// p99 = 0.110. `harmonicFlux` is declared `kind: "accent"` — a spikes-at-chord-changes
    /// primitive, not a continuous energy level — so an absolute cutoff near its own
    /// calibrated ceiling is the correct pattern (FA #31 is about drifting CONTINUOUS
    /// energy levels; this is the same reasoning beat-onset thresholds already use).
    public static let fluxStepThreshold: Float = 0.09

    /// Circular-smoother time constant (seconds). Matches `CircularPhaseSmoother`'s own
    /// documented default (D-209 / FTR.30) — a τ this codebase has already measured
    /// removes the jump without erasing real harmonic motion.
    static let fifthsSmoothTau: Float = 3.0

    // MARK: - Public properties

    /// GPU-side uniforms buffer (16 bytes: `RosetteUniformsGPU`). Bound at fragment
    /// buffer(6) by `VisualizerEngine+Presets` via `RenderPipeline.setDirectPresetFragmentBuffer`.
    public let rosetteBuffer: MTLBuffer

    /// The currently-held symmetry order. Exposed for diagnostics/tests.
    public var currentSymmetryN: Float {
        lock.withLock { Self.symmetrySequence[symmetryIndex] }
    }

    /// The smoothed `tonalPhaseFifths` value this frame (radians). Exposed for tests.
    public var smoothedFifthsPhase: Float {
        lock.withLock { atan2(fifthsIm, fifthsRe) }
    }

    // MARK: - Private state

    private var fifthsRe: Float = 1
    private var fifthsIm: Float = 0
    private var fifthsSeeded = false
    private var symmetryIndex: Int = 0
    /// Seconds since the last symmetry step. Starts at `minHoldSeconds` so the very
    /// first qualifying spike can step immediately rather than waiting a full hold
    /// window from track start.
    private var timeSinceLastStep: Float = RosetteState.minHoldSeconds

    private let lock = NSLock()

    // MARK: - Init

    public init?(device: MTLDevice) {
        guard let buf = device.makeBuffer(length: MemoryLayout<RosetteUniformsGPU>.stride,
                                          options: .storageModeShared) else {
            logger.error("RosetteState: failed to allocate rosetteBuffer")
            return nil
        }
        rosetteBuffer = buf
        writeToGPU(smoothedFifths: 0, symmetryN: Self.symmetrySequence[0])
    }

    // MARK: - Public API

    /// Update the circular smoother + symmetry hold-timer for one rendered frame, then
    /// flush to the GPU buffer. Call once per frame from the render-loop tick hook before
    /// the overlay draw reads buffer(6).
    public func tick(deltaTime: Float, features: FeatureVector) {
        let snapshot: (smoothedFifths: Float, symmetryN: Float) = lock.withLock {
            let dt = max(deltaTime, 0.001)

            // D-209 circular smoothing: smooth cos/sin separately, recombine via atan2 —
            // never EMA the raw +/-pi sawtooth directly (the seam jump).
            let alpha = 1 - exp(-dt / Self.fifthsSmoothTau)
            let raw = features.tonalPhaseFifths
            let rawRe = cos(raw), rawIm = sin(raw)
            if !fifthsSeeded {
                fifthsRe = rawRe; fifthsIm = rawIm; fifthsSeeded = true
            } else {
                fifthsRe += (rawRe - fifthsRe) * alpha
                fifthsIm += (rawIm - fifthsIm) * alpha
            }

            // Symmetry-order hold-timer: a harmonicFlux spike steps to the next order in
            // the sequence, but only once the current order has held for minHoldSeconds —
            // never per-beat, never per-spike (the anti-contract: "the symmetry order
            // must never flicker").
            timeSinceLastStep += dt
            if features.harmonicFlux > Self.fluxStepThreshold && timeSinceLastStep >= Self.minHoldSeconds {
                symmetryIndex = (symmetryIndex + 1) % Self.symmetrySequence.count
                timeSinceLastStep = 0
            }
            return (atan2(fifthsIm, fifthsRe), Self.symmetrySequence[symmetryIndex])
        }
        writeToGPU(smoothedFifths: snapshot.smoothedFifths, symmetryN: snapshot.symmetryN)
    }

    /// Reset on track change so a new track's fifths phase doesn't glide in from the old
    /// one, and the symmetry order restarts at Whitney's stated base (5-fold).
    public func reset() {
        lock.withLock {
            fifthsRe = 1; fifthsIm = 0; fifthsSeeded = false
            symmetryIndex = 0
            timeSinceLastStep = Self.minHoldSeconds
        }
        writeToGPU(smoothedFifths: 0, symmetryN: Self.symmetrySequence[0])
    }

    // MARK: - Private: GPU write

    private func writeToGPU(smoothedFifths: Float, symmetryN: Float) {
        let gpu = RosetteUniformsGPU(smoothedFifths: smoothedFifths, symmetryN: symmetryN, pad0: 0, pad1: 0)
        rosetteBuffer.contents().bindMemory(to: RosetteUniformsGPU.self, capacity: 1)[0] = gpu
    }
}
