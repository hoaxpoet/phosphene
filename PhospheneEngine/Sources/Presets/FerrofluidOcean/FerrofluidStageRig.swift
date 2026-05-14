// FerrofluidStageRig — Per-frame stage-rig state for Ferrofluid Ocean (V.9 Session 3).
//
// First concrete consumer of the `SHADER_CRAFT.md §5.8` recipe per D-125.
// Owns a 208-byte UMA `MTLBuffer` carrying `StageRigState` (Shared), and
// advances per-frame:
//   1. Orbital azimuthal phase     — angular velocity = baseline +
//      smoothstep(-0.5, +0.5, arousal) * arousal-coef (slow at calm; moderately
//      animated at peak energy).
//   2. Per-light hue               — `palette()` IQ cosine driven by
//      accumulated_audio_time × 0.05 + per-light phase offset + pitch-shift
//      (vocals_pitch_hz, confidence-gated; other_energy_dev fallback).
//   3. Per-light intensity         — baseline × (floor + swing ×
//      drums_energy_dev_smoothed), 150 ms exponential smoothing on the
//      deviation primitive per §5.8.
//
// Bound at fragment slot 9 of the ray-march pipeline by
// `RenderPipeline.setDirectPresetFragmentBuffer4`. `raymarch_lighting_fragment`
// (RayMarch.metal) dispatches the matID == 2 branch on Ferrofluid Ocean
// surface pixels and loops over `stageRig.activeLightCount` to accumulate
// Cook-Torrance contributions per beam.
//
// Audio data hierarchy (CLAUDE.md):
//   - Intensity envelope: `stems.drumsEnergyDev` is a deviation primitive
//     (D-026). NEVER `stems.drumsBeat` — beat-strobed intensity is the §5.8
//     anti-pattern + CLAUDE.md Failed Approach #4.
//   - Color pitch-shift: `stems.vocalsPitchHz` (raw Hz). Pitch is not an
//     energy quantity so D-026 normalisation doesn't apply.
//   - Orbital velocity: `arousal` (smoothed via the FeatureVector pipeline);
//     never `*_beat` rising edges.
//
// The §5.8 spec text is illustrative; D-125(e) is the authoritative contract.

import Foundation
import Metal
import simd
import Shared

// MARK: - FerrofluidStageRig

/// First consumer of the §5.8 stage-rig recipe. Owns the slot-9 UMA buffer for
/// Ferrofluid Ocean V.9. Per D-125(f), the generic `StageRigEngine` extraction
/// is deferred to the second consumer — V.9 ships this preset-specific class
/// concrete.
///
/// Thread-safe: `tick(features:stems:dt:)` may be called from any queue. The
/// internal lock guards the per-frame state mutation; the buffer write happens
/// inside the lock so reader (GPU) ↔ writer (CPU) interleave is safe.
public final class FerrofluidStageRig: @unchecked Sendable {

    // MARK: - Configuration (immutable, captured at init)

    private let descriptor: StageRig
    private let lightCount: Int

    // MARK: - GPU Buffer

    /// UMA buffer carrying the current `StageRigState`. Bound at fragment slot
    /// 9 of the ray-march pipeline via
    /// `RenderPipeline.setDirectPresetFragmentBuffer4` while Ferrofluid Ocean
    /// is the active preset. Sized to `MemoryLayout<StageRigState>.stride`
    /// (208 bytes per D-125(c)).
    public let buffer: MTLBuffer

    // MARK: - Per-Frame State

    /// Accumulated orbital phase in radians. Advanced each frame by
    /// `velocity * dt` where velocity = baseline + arousal-modulated coef.
    private var orbitPhase: Float = 0

    /// Smoothed `drums_energy_dev` envelope (150 ms τ per §5.8). Sits at 0
    /// during silence so the per-light intensity decays to the floor.
    private var smoothedDrumsDev: Float = 0

    /// Internal write lock — guards state + buffer flush.
    private let lock = NSLock()

    // MARK: - Init

    /// Construct a stage rig for Ferrofluid Ocean from the JSON-decoded
    /// `stage_rig` block. Returns `nil` if the device cannot allocate the
    /// 208-byte UMA buffer.
    public init?(device: MTLDevice, descriptor: StageRig) {
        self.descriptor = descriptor
        self.lightCount = max(3, min(6, descriptor.lightCount))

        // Sanity: the stride must be the 208-byte value the placeholder
        // buffer in RayMarchPipeline is sized to. If this fires, the
        // `StageRigStateLayoutTests.test_stageRigState_strideIs208`
        // regression test would also trip — but assert here for diagnostic
        // clarity at the call site.
        let stride = MemoryLayout<StageRigState>.stride
        precondition(stride == 208, "StageRigState stride changed (\(stride)) — update placeholder")

        guard let buf = device.makeBuffer(length: stride, options: .storageModeShared) else {
            return nil
        }
        self.buffer = buf

        // Write a zero-initialised state at construction so the buffer is
        // never in an undefined state between init and the first `tick`.
        var initial = StageRigState(activeLightCount: UInt32(self.lightCount))
        memcpy(buf.contents(), &initial, stride)
    }

    /// Reset per-frame state.
    ///
    /// **Currently test-only at V.9:** production always allocates a fresh
    /// instance on preset apply via `VisualizerEngine+Presets.applyPreset`, so
    /// `reset()` is never called from the engine. Kept for future use if a
    /// session demands in-place state reset (e.g. on dolly camera change
    /// where the rig must reset orbital phase without re-allocating the
    /// slot-9 buffer).
    public func reset() {
        lock.withLock {
            orbitPhase = 0
            smoothedDrumsDev = 0
            var zeroed = StageRigState(activeLightCount: UInt32(lightCount))
            memcpy(buffer.contents(), &zeroed, MemoryLayout<StageRigState>.stride)
        }
    }

    // MARK: - Per-Frame Tick

    /// Advance one frame of stage-rig state and flush to the slot-9 UMA buffer.
    ///
    /// - Parameters:
    ///   - features: current frame's FeatureVector (accumulated_audio_time +
    ///     arousal + (optionally) deltaTime when caller does not supply `dt`).
    ///   - stems: current frame's StemFeatures (drumsEnergyDev for intensity;
    ///     vocalsPitchHz + vocalsPitchConfidence + otherEnergyDev for hue).
    ///   - dt: per-frame delta time in seconds. When negative or non-finite,
    ///     falls back to `features.deltaTime` for backwards compatibility with
    ///     callers that don't have an independent dt source.
    public func tick(features: FeatureVector, stems: StemFeatures, dt: TimeInterval) {
        let effectiveDt: Float
        if dt.isFinite && dt >= 0 {
            effectiveDt = Float(dt)
        } else {
            effectiveDt = max(0, features.deltaTime)
        }
        lock.withLock {
            advance(features: features, stems: stems, dt: effectiveDt)
            flushToGPU()
        }
    }

    // MARK: - Test Seam

    /// Snapshot the current state. Returns a deep copy. Public for tests +
    /// diagnostic dumps; not part of the rendering hot path.
    public func snapshot() -> StageRigState {
        lock.withLock {
            let ptr = buffer.contents().bindMemory(to: StageRigState.self, capacity: 1)
            return ptr[0]
        }
    }

    /// Read-only access to the current smoothed drums envelope. Used by
    /// diagnostic tests to verify the 150 ms smoothing converges from 0 →
    /// `drums_energy_dev` after a few time constants. Not part of the GPU
    /// contract.
    public var debugSmoothedDrumsDev: Float {
        lock.withLock { smoothedDrumsDev }
    }

    /// Read-only access to the current orbital phase (radians). For tests
    /// that verify arousal modulates angular velocity.
    public var debugOrbitPhase: Float {
        lock.withLock { orbitPhase }
    }

    // MARK: - Private: state advancement

    /// Per-frame state mutation. Caller holds `lock`.
    private func advance(features: FeatureVector, stems: StemFeatures, dt: Float) {
        // 1. Orbital velocity. `smoothstep(-0.5, +0.5, arousal)` maps the
        //    central arousal band into [0, 1]; extremes saturate. The baseline
        //    is the silent-state angular velocity (slow rotation continues
        //    even at silence per §5.8 silence-state semantics).
        let arousal = max(-1, min(1, features.arousal))
        let smoothArousal = Self.smoothstep(-0.5, 0.5, arousal)
        let velocity = descriptor.orbitSpeedBaseline +
                       smoothArousal * descriptor.orbitSpeedArousalCoef
        orbitPhase = (orbitPhase + velocity * dt).truncatingRemainder(dividingBy: 2 * .pi)
        // Keep `orbitPhase` non-negative for predictable `cos/sin` symmetry
        // — `truncatingRemainder` preserves the sign of the dividend.
        if orbitPhase < 0 { orbitPhase += 2 * .pi }

        // 2. Drums envelope. 150 ms τ exponential smoothing on the deviation
        //    primitive `stems.drumsEnergyDev`. The α formulation uses the
        //    discrete-time exponential RC approximation `α = dt / τ` clamped
        //    to [0, 1] so a long first-tick `dt` cannot overshoot the input.
        let tauSeconds = max(descriptor.intensitySmoothingTauMs * 0.001, 0.001)
        let alpha = min(dt / tauSeconds, 1.0)
        let drumsDev = max(0, stems.drumsEnergyDev)
        smoothedDrumsDev += (drumsDev - smoothedDrumsDev) * alpha

        // 3. Per-light state. Position from orbital phase + per-light
        //    azimuth; color from palette() at audio_time-driven phase + per-
        //    light offset + pitch shift; intensity from smoothed envelope.
        let audioTime = features.accumulatedAudioTime
        let pitchShift = Self.computePitchShift(stems: stems)
        let perLightIntensity = descriptor.intensityBaseline *
            (descriptor.intensityFloorCoef +
             descriptor.intensitySwingCoef * smoothedDrumsDev)

        var state = StageRigState(activeLightCount: UInt32(lightCount))
        for i in 0 ..< lightCount {
            let azimuthOffset = (Float(i) / Float(lightCount)) * 2 * .pi
            let azimuth = orbitPhase + azimuthOffset
            let position = SIMD3<Float>(
                descriptor.orbitRadius * cos(azimuth),
                descriptor.orbitAltitude,
                descriptor.orbitRadius * sin(azimuth)
            )
            let phaseOffset = i < descriptor.palettePhaseOffsets.count
                ? descriptor.palettePhaseOffsets[i]
                : Float(i) / Float(lightCount)
            let paletteT = audioTime * 0.05 + phaseOffset + pitchShift
            let color = Self.paletteIQ(paletteT)
            state.setLight(at: i, StageRigLight(
                positionAndIntensity: SIMD4(position.x, position.y, position.z, perLightIntensity),
                color: SIMD4(color.x, color.y, color.z, 0)
            ))
        }

        // Update the in-buffer state. `bindMemory` is safe here because
        // `MTLBuffer.contents()` is page-aligned and `StageRigState` is
        // `@frozen` with a guaranteed 208-byte stride.
        let ptr = buffer.contents().bindMemory(to: StageRigState.self, capacity: 1)
        ptr[0] = state
    }

    /// Flush is a no-op on UMA storage — the per-frame write inside `advance`
    /// already lands in the GPU-visible memory. The method is kept as a
    /// semantic anchor (mirrors `LumenPatternEngine.writeToGPU`) in case
    /// future buffer modes (e.g. private storage with explicit blit) are
    /// introduced.
    private func flushToGPU() {
        // No-op for `.storageModeShared`. Reserved for future buffer modes.
    }

    // MARK: - Private: math helpers

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let span = max(edge1 - edge0, 1e-6)
        let unit = max(0, min(1, (value - edge0) / span))
        return unit * unit * (3 - 2 * unit)
    }

    /// Inigo Quilez cosine palette tuned for the §5.8 beam aesthetic: rotating
    /// jewel tones across the warm/cool axes. Matches `palette_neon` from
    /// `Utilities/Color/Palettes.metal` (the catalog's high-saturation neon
    /// preset) so the Swift / Metal hue rotation is visually consistent —
    /// the GPU side could in principle compute the same palette at
    /// per-pixel cost, but baking the palette evaluation CPU-side lets a
    /// single buffer write carry the result to all surface pixels.
    private static func paletteIQ(_ phase: Float) -> SIMD3<Float> {
        // Match `palette_neon`: a = 0.5, b = 0.5, c = 1.0, d = (0.0, 0.33, 0.67).
        // Single-letter coefficients are the IQ palette convention; the
        // longer names below preserve the Metal/MSL helper's name parity at
        // the cost of a small readability shift.
        let bias = SIMD3<Float>(0.5, 0.5, 0.5)
        let amplitude = SIMD3<Float>(0.5, 0.5, 0.5)
        let frequency = SIMD3<Float>(1.0, 1.0, 1.0)
        let phaseOffset = SIMD3<Float>(0.0, 0.33, 0.67)
        let twoPi: Float = 6.28318530718
        let arg = frequency * phase + phaseOffset
        return SIMD3<Float>(
            bias.x + amplitude.x * cos(twoPi * arg.x),
            bias.y + amplitude.y * cos(twoPi * arg.y),
            bias.z + amplitude.z * cos(twoPi * arg.z)
        )
    }

    /// Pitch-shift contribution to palette phase per §5.8.
    /// - Vocals confidence ≥ 0.6 → log-perceptual mapping of vocals_pitch_hz
    ///   across [80 Hz, 1 kHz], scaled to ±0.2 of palette phase.
    /// - Below 0.6 (instrumental passages, sparse vocals) → fallback to
    ///   `stems.otherEnergyDev × 0.15` (harmonic-content density).
    private static func computePitchShift(stems: StemFeatures) -> Float {
        if stems.vocalsPitchConfidence >= 0.6 {
            let pitch = max(stems.vocalsPitchHz, 80.0)
            let logRatio = log2f(pitch / 80.0) / log2f(1000.0 / 80.0)
            return logRatio * 0.2
        }
        return max(0, stems.otherEnergyDev) * 0.15
    }
}
