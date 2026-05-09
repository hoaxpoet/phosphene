// LumenPatternEngine — Per-preset world state for the Lumen Mosaic preset (Phase LM).
// swiftlint:disable file_length
//
// File-length is relaxed because the public GPU-contract structs
// (`LumenLightAgent`, `LumenPattern`, `LumenPatternState`), the engine class,
// and the mood-tint / smoothstep math helpers all need to live in the same
// translation unit so the in-place `MemoryLayout<LumenPatternState>.stride
// == 336` assertion in `init?(device:seed:)` and the matching MSL preamble
// stay tightly coupled. Splitting any of them out would increase risk of
// the Swift / MSL byte layouts diverging silently. Same disposition as
// `ArachneState.swift`.
//
// `large_tuple` is disabled where `LumenPatternState` declares its 4-element
// `lights` and `patterns` tuples — the GPU contract is tuples, not arrays,
// because Swift arrays are reference-typed and would put a heap allocation
// in the GPU buffer's mapped path.
//
// LM.2 ships the 4-light audio-driven backlight on top of LM.1's static glass
// panel. The pattern engine is the single source of truth for what the panel
// shows behind the cell field every frame:
//
//   1. Each frame the engine consumes one (FeatureVector, StemFeatures) tick
//      and updates four `LumenLightAgent` slots.
//   2. The state is flushed to a 336-byte UMA `MTLBuffer` (`patternBuffer`).
//   3. RenderPipeline binds the buffer at fragment slot 8 of the ray-march
//      lighting pass; the LumenMosaic shader reads it and computes the
//      cell-quantized backlight per the contract §P.3 / §P.4 recipes.
//
// LM.2 scope: 4 lights (one per stem) + mood-driven palette + beat-locked
// dance + D-019 silence fallback. The pattern slots stay `idle` until LM.4 —
// `activePatternCount` is 0 and `barPatternOffset` is zero. The shader still
// receives the four-pattern array (zeroed) for ABI stability.
//
// Audio routing (CLAUDE.md Layer 1 + Layer 5a/5b primaries):
//   - Light intensity per stem driven by deviation primitives (D-026), with
//     D-019 FeatureVector fallback for the warmup window.
//   - Light position composed from a slow mood-driven Lissajous drift +
//     a `beat_phase01`-locked figure-8 oscillation (contract §P.4 — the dance).
//   - Light color = per-stem base × mood tint, smoothed with a 5 s low-pass.
//
// References:
//   docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md §P.2 / §P.3 / §P.4
//   docs/presets/LUMEN_MOSAIC_DESIGN.md §4.3 / §4.5
//   docs/CLAUDE.md (D-019 silence fallback, D-026 deviation primitives)
//   docs/DECISIONS.md (D-019, D-020, D-026)
//
// Companion: ARACHNE_V8_DESIGN.md §11 (5 s mood low-pass; reference pattern).

import Foundation
import Metal
import simd
import Shared

// MARK: - LumenPatternKind

/// Pattern type identifier. LM.2 only uses `.idle`; the rest land in LM.4 / LM.5.
/// Raw values are written into `LumenPattern.kindRaw` and dispatched by the shader.
public enum LumenPatternKind: Int32, Sendable {
    case idle           = 0
    case radialRipple   = 1
    case sweep          = 2
    case clusterBurst   = 3   // LM.5
    case breathing      = 4   // LM.5
    case noiseDrift     = 5   // LM.5
}

// MARK: - LumenLightAgent (32 bytes)

/// One audio-driven light agent. Sampled by the LumenMosaic shader at the
/// cell-centre uv per contract §P.3.
///
/// Layout: 8 × Float32 = 32 bytes, byte-identical to the matching MSL struct.
/// Individual `Float` fields are used in place of `SIMD3<Float>` because Swift
/// pads `SIMD3<Float>` to 16 bytes (alignment); explicit fields keep the stride
/// at 32 without language-level surprises.
public struct LumenLightAgent: Sendable, Equatable {
    /// Panel-face uv x (-1..1 across the visible frame).
    public var positionX: Float
    /// Panel-face uv y (-1..1 across the visible frame).
    public var positionY: Float
    /// Notional depth into the back-plane. Adds to r² in the falloff so deeper
    /// agents read as "softer / further away" (contract §4.3). 0 = at panel.
    public var positionZ: Float
    /// Falloff coefficient `k` in `falloff = intensity / (1 + r² × k)`. Larger
    /// values give a more peaked agent (small footprint); smaller values
    /// produce a broader, softer wash. Default 6.0 → half-falloff at r ≈ 0.41.
    public var attenuationRadius: Float
    public var colorR: Float
    public var colorG: Float
    public var colorB: Float
    /// Final per-frame agent intensity (linear, ≥ 0). Carries the audio energy.
    public var intensity: Float

    public init(
        positionX: Float = 0, positionY: Float = 0, positionZ: Float = 0,
        attenuationRadius: Float = 6.0,
        colorR: Float = 1, colorG: Float = 1, colorB: Float = 1,
        intensity: Float = 0
    ) {
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.attenuationRadius = attenuationRadius
        self.colorR = colorR
        self.colorG = colorG
        self.colorB = colorB
        self.intensity = intensity
    }

    /// Convenience accessor for the panel-face xy + depth-spread z position.
    public var position: SIMD3<Float> {
        get { SIMD3(positionX, positionY, positionZ) }
        set { positionX = newValue.x; positionY = newValue.y; positionZ = newValue.z }
    }

    /// Convenience accessor for the rgb color.
    public var color: SIMD3<Float> {
        get { SIMD3(colorR, colorG, colorB) }
        set { colorR = newValue.x; colorG = newValue.y; colorB = newValue.z }
    }

    public static let zero = LumenLightAgent()
}

// MARK: - LumenPattern (48 bytes)

/// One active pattern. LM.2 leaves all four pattern slots zeroed (`activePatternCount = 0`).
/// LM.4 promotes the slots to live `radialRipple` / `sweep` instances.
///
/// Layout: 12 × Float32 = 48 bytes. `kindRaw` is `Int32` (same width as `Float`).
public struct LumenPattern: Sendable, Equatable {
    public var originX: Float
    public var originY: Float
    public var directionX: Float
    public var directionY: Float
    public var colorR: Float
    public var colorG: Float
    public var colorB: Float
    public var phase: Float
    public var intensity: Float
    public var startTime: Float
    public var duration: Float
    public var kindRaw: Int32

    public init(
        originX: Float = 0, originY: Float = 0,
        directionX: Float = 0, directionY: Float = 0,
        colorR: Float = 0, colorG: Float = 0, colorB: Float = 0,
        phase: Float = 0,
        intensity: Float = 0, startTime: Float = 0, duration: Float = 0,
        kindRaw: Int32 = 0
    ) {
        self.originX = originX; self.originY = originY
        self.directionX = directionX; self.directionY = directionY
        self.colorR = colorR; self.colorG = colorG; self.colorB = colorB
        self.phase = phase
        self.intensity = intensity
        self.startTime = startTime
        self.duration = duration
        self.kindRaw = kindRaw
    }

    public var kind: LumenPatternKind {
        LumenPatternKind(rawValue: kindRaw) ?? .idle
    }

    public static let idle = LumenPattern()
}

// MARK: - LumenPatternState (336 bytes)

// swiftlint:disable large_tuple

/// Per-frame snapshot of the entire pattern engine, byte-identical to the
/// matching MSL struct in `LumenMosaic.metal`. Bound at fragment slot 8 of
/// the ray-march lighting pass.
///
/// Layout: 4 × LumenLightAgent (128 B) + 4 × LumenPattern (192 B) + 4 × Float32
/// (16 B) = 336 B. The Swift `MemoryLayout<LumenPatternState>.stride` is asserted
/// to be 336 in `LumenPatternEngineTests.test_lumenPatternState_strideIs336`.
public struct LumenPatternState: Sendable {
    public var lights: (LumenLightAgent, LumenLightAgent, LumenLightAgent, LumenLightAgent)
    public var patterns: (LumenPattern, LumenPattern, LumenPattern, LumenPattern)
    public var activeLightCount: Int32
    public var activePatternCount: Int32
    public var ambientFloorIntensity: Float
    public var pad0: Float

    public init(
        lights: (LumenLightAgent, LumenLightAgent, LumenLightAgent, LumenLightAgent) =
            (.zero, .zero, .zero, .zero),
        patterns: (LumenPattern, LumenPattern, LumenPattern, LumenPattern) =
            (.idle, .idle, .idle, .idle),
        activeLightCount: Int32 = 0,
        activePatternCount: Int32 = 0,
        ambientFloorIntensity: Float = 0,
        pad0: Float = 0
    ) {
        self.lights = lights
        self.patterns = patterns
        self.activeLightCount = activeLightCount
        self.activePatternCount = activePatternCount
        self.ambientFloorIntensity = ambientFloorIntensity
        self.pad0 = pad0
    }

    /// Indexed light access (read-only). LM.2 has exactly 4 lights.
    public func light(at index: Int) -> LumenLightAgent {
        switch index {
        case 0: return lights.0
        case 1: return lights.1
        case 2: return lights.2
        case 3: return lights.3
        default: return .zero
        }
    }

    /// Indexed pattern access (read-only).
    public func pattern(at index: Int) -> LumenPattern {
        switch index {
        case 0: return patterns.0
        case 1: return patterns.1
        case 2: return patterns.2
        case 3: return patterns.3
        default: return .idle
        }
    }

    public static let zero = LumenPatternState()
}
// swiftlint:enable large_tuple

// MARK: - LumenPatternEngine

/// Owns the four light agents + four (LM.4-future) pattern slots and flushes
/// them to a slot-8 fragment buffer once per frame.
///
/// Thread-safe: `tick(features:stems:)` and `snapshot()` may be called from any
/// queue. `patternBuffer.contents()` is read by the GPU; tick + writeToGPU run
/// while holding the internal lock to keep the contents and the snapshot in sync.
///
/// `tick` is invoked by `RenderPipeline.meshPresetTick` once per rendered frame,
/// before the ray-march pass dispatches.
public final class LumenPatternEngine: @unchecked Sendable {

    // MARK: - Constants (immutable defaults)

    public static let agentCount = 4
    public static let patternCount = 4

    /// Visible-area inset for clamped agent positions. Per contract §P.2.
    public static let agentInset: Float = 0.85

    /// 5 s low-pass time constant for valence/arousal — matches ARACHNE §11.
    public static let moodSmoothingSeconds: Float = 5.0

    /// D-019 stem-warmup smoothstep window. `totalStemEnergy ≥ stemWarmupHigh`
    /// → 100 % stem-direct path; `≤ stemWarmupLow` → 100 % FV fallback path.
    public static let stemWarmupLow: Float  = 0.02
    public static let stemWarmupHigh: Float = 0.06

    /// Silence ambient floor magnitude (fed to the shader as
    /// `LumenPatternState.ambientFloorIntensity`). The shader scales it by the
    /// mood tint so the panel is never pure black at silence (D-019 + D-037
    /// invariant 1 / "non-black at silence"). LM.2 keeps the value matched to
    /// `LumenMosaic.json#lumen_mosaic.ambient_floor_intensity = 0.04` and
    /// LM.1's static-backlight ambient term.
    public static let defaultAmbientFloorIntensity: Float = 0.04

    /// Default falloff coefficient — `1 / (1 + r² × k)` half-falloff at r ≈ √(1/k).
    /// k = 6 → half at r ≈ 0.41 uv, matching the per-stem base spread.
    public static let defaultAttenuationRadius: Float = 6.0

    /// Stem agent ordering (matches contract §P.2 base-position table).
    /// Index 0 = drums, 1 = bass, 2 = vocals, 3 = other.
    public static let agentBasePositions: [SIMD2<Float>] = [
        SIMD2(-0.45, +0.35),  // 0 drums  (upper-left)
        SIMD2( 0.00, -0.40),  // 1 bass   (centre-low)
        SIMD2( 0.00, +0.05),  // 2 vocals (centre-mid)
        SIMD2(+0.45, +0.30),  // 3 other  (upper-right)
    ]

    /// Per-agent Lissajous frequencies. Picked so the four agents do not
    /// cycle in unison; the values are the smallest set that keeps each
    /// pair's relative phase irrational across a typical session.
    public static let agentDriftFrequencies: [SIMD2<Float>] = [
        SIMD2(1.0, 1.3),
        SIMD2(0.7, 0.9),
        SIMD2(1.2, 0.6),
        SIMD2(0.9, 1.4),
    ]

    /// Per-stem drift radius (uv units). Vocals + other roam slightly wider
    /// than drums; bass anchors near the bottom-centre with the tightest
    /// radius. From contract §P.4.
    public static let agentDriftRadii: [Float] = [0.25, 0.20, 0.30, 0.30]

    /// Per-agent beat-phase offset (radians). Drums lead, bass / vocals /
    /// other follow at quarter-cycle increments — the four agents trace a
    /// rolling wave across the panel as `beat_phase01` advances. Contract §P.4.
    public static let agentBeatPhaseOffsets: [Float] = [
        0,
        .pi / 2,
        .pi,
        3 * .pi / 2,
    ]

    /// Per-stem base color. Multiplied by `mood_tint(valence, arousal)` each
    /// frame. From design doc §4.5 ("Light agents" table).
    public static let agentBaseColors: [SIMD3<Float>] = [
        SIMD3(1.0, 0.4, 0.2),   // drums  warm orange-red
        SIMD3(0.8, 0.2, 0.1),   // bass   deep red
        SIMD3(1.0, 0.7, 0.5),   // vocals peach / cream
        SIMD3(0.3, 0.7, 0.9),   // other  cool teal
    ]

    /// Drift-speed range, lerp(low, high, (arousal+1)/2). Calm at low
    /// arousal, faster at high arousal.
    public static let driftSpeedLow: Float  = 0.05
    public static let driftSpeedHigh: Float = 0.20

    /// Beat-locked dance amplitude. Per contract §P.4:
    /// `0.04 + 0.10 × arousal` clamped to [0.04, 0.14] for arousal ∈ [0, 1].
    public static let danceAmplitudeBase: Float  = 0.04
    public static let danceAmplitudeGain: Float  = 0.10
    public static let danceAmplitudeMax: Float   = 0.14

    // MARK: - Public API

    /// UMA buffer carrying the current `LumenPatternState`. Bound at fragment
    /// slot 8 of the ray-march lighting pass via
    /// `RenderPipeline.setDirectPresetFragmentBuffer3` while LumenMosaic is
    /// the active preset; null otherwise.
    public let patternBuffer: MTLBuffer

    /// Smoothed valence (5 s low-pass). Read-only — published for diagnostics.
    public private(set) var smoothedValence: Float = 0

    /// Smoothed arousal (5 s low-pass). Read-only — published for diagnostics.
    public private(set) var smoothedArousal: Float = 0

    /// Wall-clock seconds since this engine was instantiated. Drives the
    /// drift-Lissajous phase. Reset to 0 on `reset()`.
    public private(set) var elapsedTime: Float = 0

    // MARK: - Private state

    private var state: LumenPatternState
    private let lock = NSLock()

    /// Per-instance base positions — copied from the static defaults at init,
    /// but exposed via an internal setter so test fixtures can verify the
    /// inset clamp by pushing a base position outside the visible-area inset.
    private var basePositions: [SIMD2<Float>]

    // MARK: - Init

    public init?(device: MTLDevice, seed: UInt64 = 0) {
        _ = seed   // reserved for LM.4 deterministic pattern seeding.

        let bufSize = MemoryLayout<LumenPatternState>.stride
        guard let buf = device.makeBuffer(length: bufSize, options: .storageModeShared) else {
            return nil
        }
        self.patternBuffer = buf
        self.basePositions = Self.agentBasePositions

        // Seed agents with their base positions, base colours scaled by the
        // neutral-mood tint, and zero intensity. Patterns stay `.idle`.
        var initial = LumenPatternState(
            activeLightCount: Int32(Self.agentCount),
            activePatternCount: 0,
            ambientFloorIntensity: Self.defaultAmbientFloorIntensity
        )
        let neutralTint = lumenMoodTint(valence: 0, arousal: 0)
        initial.lights = (
            Self.makeAgent(at: 0, position: Self.agentBasePositions[0], tintedBase: neutralTint),
            Self.makeAgent(at: 1, position: Self.agentBasePositions[1], tintedBase: neutralTint),
            Self.makeAgent(at: 2, position: Self.agentBasePositions[2], tintedBase: neutralTint),
            Self.makeAgent(at: 3, position: Self.agentBasePositions[3], tintedBase: neutralTint)
        )
        self.state = initial
        writeToGPU()
    }

    /// Advance one rendered frame and flush the resulting state to GPU.
    public func tick(features: FeatureVector, stems: StemFeatures) {
        lock.withLock { _tick(features: features, stems: stems) }
        writeToGPU()
    }

    /// Snapshot the current state value. Returns a deep copy.
    public func snapshot() -> LumenPatternState {
        lock.withLock { state }
    }

    /// Reset the engine to its initial state (used on preset re-apply).
    public func reset() {
        lock.withLock {
            elapsedTime = 0
            smoothedValence = 0
            smoothedArousal = 0
            let neutralTint = lumenMoodTint(valence: 0, arousal: 0)
            state.lights = (
                Self.makeAgent(at: 0, position: basePositions[0], tintedBase: neutralTint),
                Self.makeAgent(at: 1, position: basePositions[1], tintedBase: neutralTint),
                Self.makeAgent(at: 2, position: basePositions[2], tintedBase: neutralTint),
                Self.makeAgent(at: 3, position: basePositions[3], tintedBase: neutralTint)
            )
        }
        writeToGPU()
    }

    // MARK: - Test seam

    /// Override the runtime base position of a single agent. Internal-only —
    /// the public API reads `basePositions` from the static default. Tests
    /// use this seam to push an agent's base outside the inset and verify
    /// the clamp keeps the rendered position within ±`agentInset`.
    func setAgentBasePositionForTesting(_ index: Int, _ position: SIMD2<Float>) {
        guard index >= 0 && index < Self.agentCount else { return }
        lock.withLock { basePositions[index] = position }
    }

    // MARK: - Private: tick (called while holding lock)

    private func _tick(features: FeatureVector, stems: StemFeatures) {
        let dt = max(features.deltaTime, 0)
        elapsedTime += dt

        // 5 s low-pass on mood. dt / τ is the RC fraction per frame; clamp to
        // 1 so a long first-tick deltaTime cannot overshoot the input.
        let alpha = min(dt / Self.moodSmoothingSeconds, 1.0)
        smoothedValence += (features.valence - smoothedValence) * alpha
        smoothedArousal += (features.arousal - smoothedArousal) * alpha

        // D-019 warmup mix.
        let totalStemEnergy =
            stems.drumsEnergy + stems.bassEnergy +
            stems.vocalsEnergy + stems.otherEnergy
        let stemMix = lumenSmoothstep(Self.stemWarmupLow, Self.stemWarmupHigh, totalStemEnergy)

        // Mood tint, computed once and applied to all four agents.
        let moodTintColor = lumenMoodTint(valence: smoothedValence, arousal: smoothedArousal)

        // Drift-speed map. (smoothedArousal + 1) / 2 maps arousal ∈ [-1, +1]
        // into [0, 1] for the lerp. Uses the smoothed arousal so the drift
        // Lissajous does not abruptly speed up on a transient arousal spike
        // — the slow Lissajous wander is a mood-scale parameter (ARACHNE §11
        // smoothing pattern).
        let arousalNorm = max(0, min(1, (smoothedArousal + 1) * 0.5))
        let driftSpeed = Self.driftSpeedLow +
                         (Self.driftSpeedHigh - Self.driftSpeedLow) * arousalNorm

        // Beat-locked dance amplitude. Spec is `0.04 + 0.10 × f.arousal`
        // clamped to [0.04, 0.14] for arousal ∈ [0, 1]. Negative arousal
        // floors to 0.04 (the dance never disappears entirely).
        //
        // Reads raw `features.arousal` per contract §P.4 — the dance is the
        // moment-to-moment expression of arousal, not a slow palette swing.
        // (Color and drift speed are smoothed; the dance's amplitude is not.)
        let danceAmplitude = max(
            Self.danceAmplitudeBase,
            min(Self.danceAmplitudeMax,
                Self.danceAmplitudeBase +
                Self.danceAmplitudeGain * features.arousal)
        )
        let beatPhaseRad = features.beatPhase01 * 2 * .pi

        // Update each agent.
        let agents: [LumenLightAgent] = (0..<Self.agentCount).map { i in
            let basePos     = basePositions[i]
            let driftFreq   = Self.agentDriftFrequencies[i]
            let driftRadius = Self.agentDriftRadii[i]
            let beatOffset  = Self.agentBeatPhaseOffsets[i]
            let baseColor   = Self.agentBaseColors[i]

            // Slow mood-driven Lissajous drift around the agent's base position.
            let driftPhase = elapsedTime * driftSpeed
            let drift = SIMD2<Float>(
                cos(driftPhase * driftFreq.x) * driftRadius,
                sin(driftPhase * driftFreq.y) * driftRadius
            )

            // Beat-locked figure-8 oscillation (contract §P.4). 2× vertical
            // frequency relative to horizontal, half amplitude on the
            // vertical axis — produces a flat figure-8 trace.
            let beatLocked = SIMD2<Float>(
                cos(beatPhaseRad + beatOffset) * danceAmplitude,
                sin(beatPhaseRad * 2 + beatOffset) * danceAmplitude * 0.5
            )

            // LM.4 will add `barPatternOffset` here.
            var pos = basePos + drift + beatLocked
            pos.x = max(-Self.agentInset, min(Self.agentInset, pos.x))
            pos.y = max(-Self.agentInset, min(Self.agentInset, pos.y))

            // Color: per-stem base × mood tint. Mood tint is in [0, ~1.05]
            // per channel; a slight overshoot at warm peaks is preserved as
            // pre-tone-map HDR signal.
            let color = baseColor * moodTintColor

            // Intensity: stem-direct primary with FV fallback (D-019).
            let intensity = computeIntensity(agentIndex: i,
                                             features: features,
                                             stems: stems,
                                             stemMix: stemMix)

            return LumenLightAgent(
                positionX: pos.x,
                positionY: pos.y,
                positionZ: 0,
                attenuationRadius: Self.defaultAttenuationRadius,
                colorR: color.x,
                colorG: color.y,
                colorB: color.z,
                intensity: max(0, intensity)
            )
        }

        state.lights = (agents[0], agents[1], agents[2], agents[3])
        state.activeLightCount = Int32(Self.agentCount)
        state.activePatternCount = 0   // LM.4 promotes to ≥ 0 active patterns.
        state.ambientFloorIntensity = Self.defaultAmbientFloorIntensity
        // Patterns stay `.idle` (initial-zero) for LM.2.
    }

    /// Per-agent intensity using deviation primitives, with D-019 FV fallback
    /// during the stem warmup window.
    ///
    /// Mappings (contract §P.4 / design doc §4.5):
    /// - drums  → `stems.drumsEnergyRel`     fallback `f.beatBass × 0.6 + f.beatMid × 0.4`
    /// - bass   → `stems.bassEnergyRel`      fallback `f.bassDev × 0.6`
    /// - vocals → `stems.vocalsEnergyDev`    fallback `0`
    /// - other  → `stems.otherEnergyRel`     fallback `f.treble × 1.4`
    ///
    /// `stems.<x>EnergyRel` is the (energy − running-average) × 2 deviation
    /// (D-026). It is allowed to sit slightly above 1.0 on loud transients;
    /// the final value is clamped at the call site by `max(0, …)`.
    private func computeIntensity(
        agentIndex: Int,
        features: FeatureVector,
        stems: StemFeatures,
        stemMix: Float
    ) -> Float {
        let stemDirect: Float
        let fvFallback: Float
        switch agentIndex {
        case 0: // drums
            stemDirect = max(0, stems.drumsEnergyRel)
            fvFallback = features.beatBass * 0.6 + features.beatMid * 0.4
        case 1: // bass
            stemDirect = max(0, stems.bassEnergyRel)
            fvFallback = features.bassDev * 0.6
        case 2: // vocals
            stemDirect = max(0, stems.vocalsEnergyDev)
            fvFallback = 0
        case 3: // other
            stemDirect = max(0, stems.otherEnergyRel)
            fvFallback = features.treble * 1.4
        default:
            return 0
        }
        return lumenMix(fvFallback, stemDirect, t: stemMix)
    }

    // MARK: - Private: GPU flush

    private func writeToGPU() {
        let stateCopy = lock.withLock { state }
        let ptr = patternBuffer.contents().bindMemory(to: LumenPatternState.self, capacity: 1)
        ptr[0] = stateCopy
    }

    // MARK: - Private: helpers

    private static func makeAgent(
        at index: Int,
        position: SIMD2<Float>,
        tintedBase: SIMD3<Float>
    ) -> LumenLightAgent {
        let baseColor = agentBaseColors[index]
        let color = baseColor * tintedBase
        return LumenLightAgent(
            positionX: position.x,
            positionY: position.y,
            positionZ: 0,
            attenuationRadius: defaultAttenuationRadius,
            colorR: color.x,
            colorG: color.y,
            colorB: color.z,
            intensity: 0
        )
    }
}

// MARK: - Math helpers (file-private)

/// Mood tint: maps valence/arousal to a smooth warm/cool axis crossed with a
/// saturation axis. Centred at neutral cream (valence=0, arousal=0). Mirrors
/// `lm_mood_tint` in `LumenMosaic.metal` so the CPU-baked agent colour and the
/// shader's silence-ambient term agree.
private func lumenMoodTint(valence: Float, arousal: Float) -> SIMD3<Float> {
    let warm = max(0, min(1, valence * 0.5 + 0.5))
    let sat  = max(0, min(1, arousal * 0.4 + 0.4))
    let cool       = SIMD3<Float>(0.60, 0.75, 1.00)
    let warmColour = SIMD3<Float>(1.00, 0.65, 0.40)
    let hue = lumenMix(cool, warmColour, t: warm)
    let cream = SIMD3<Float>(1.00, 0.95, 0.85)
    return lumenMix(cream, hue, t: sat)
}

private func lumenSmoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
    let unit = max(0, min(1, (value - edge0) / max(edge1 - edge0, 1e-6)))
    return unit * unit * (3 - 2 * unit)
}

private func lumenMix(_ from: Float, _ to: Float, t blend: Float) -> Float {
    from + (to - from) * blend
}

private func lumenMix(_ from: SIMD3<Float>, _ to: SIMD3<Float>, t blend: Float) -> SIMD3<Float> {
    from + (to - from) * blend
}
