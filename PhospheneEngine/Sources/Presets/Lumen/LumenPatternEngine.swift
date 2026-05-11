// LumenPatternEngine — Per-preset world state for the Lumen Mosaic preset (Phase LM).
// swiftlint:disable file_length
//
// File-length is relaxed because the public GPU-contract structs
// (`LumenLightAgent`, `LumenPattern`, `LumenPatternState`), the engine class,
// and the mood-tint / smoothstep math helpers all need to live in the same
// translation unit so the in-place `MemoryLayout<LumenPatternState>.stride
// == 376` assertion in `init?(device:seed:)` and the matching MSL preamble
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
//   2. The state is flushed to a 376-byte UMA `MTLBuffer` (`patternBuffer`).
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

// MARK: - LumenPatternState (376 bytes — LM.3.2)

// swiftlint:disable large_tuple

/// Per-frame snapshot of the entire pattern engine, byte-identical to the
/// matching MSL struct in `LumenMosaic.metal`. Bound at fragment slot 8 of
/// the ray-march lighting pass.
///
/// Layout (LM.3.2): 4 × LumenLightAgent (128 B) + 4 × LumenPattern (192 B)
/// + 6 × Float32 scalars (counts + ambient + valence + arousal + pad0 = 24 B)
/// + 4 × Float32 trackPaletteSeed{A,B,C,D} (16 B)
/// + 4 × Float32 band counters (bass/mid/treble/bar = 16 B)
/// = 376 B. The Swift `MemoryLayout<LumenPatternState>.stride` is asserted
/// to be 376 in `LumenPatternEngineTests.test_lumenPatternState_strideIs376`.
public struct LumenPatternState: Sendable {
    public var lights: (LumenLightAgent, LumenLightAgent, LumenLightAgent, LumenLightAgent)
    public var patterns: (LumenPattern, LumenPattern, LumenPattern, LumenPattern)
    public var activeLightCount: Int32
    public var activePatternCount: Int32
    /// LM.2 D-019 ambient floor magnitude. Retained on the struct for ABI
    /// continuity but unused at LM.3+ — the new design holds cells at their
    /// last vivid colour at silence rather than fading toward an ambient
    /// tint, so `LumenMosaic.metal` ignores this field. Kept zero-initialised
    /// in `LumenPatternEngine.snapshot()`.
    public var ambientFloorIntensity: Float
    /// 5-second low-pass on `f.valence`. Read by `LumenMosaic.metal` to
    /// interpolate palette `a` (offset) and `d` (phase) parameters between
    /// the cool-mood and warm-mood endpoints. (LM.3 / D-LM-d4)
    public var smoothedValence: Float
    /// 5-second low-pass on `f.arousal`. Read by `LumenMosaic.metal` to
    /// interpolate palette `b` (chroma amplitude) and `c` (channel rate)
    /// between subdued-mood and frantic-mood endpoints. (LM.3 / D-LM-d4)
    public var smoothedArousal: Float
    public var pad0: Float
    /// Per-track palette perturbation, derived from a hash of the active
    /// track identity (LM.3 / D-LM-e3). Each component shifts a different
    /// IQ palette parameter by a small amount so that two tracks at the
    /// same mood produce visibly different palette character. Magnitudes
    /// bumped at LM.3.2 (the LM.3 values were too small to produce
    /// visible track-to-track variation).
    public var trackPaletteSeedA: Float
    public var trackPaletteSeedB: Float
    public var trackPaletteSeedC: Float
    public var trackPaletteSeedD: Float
    /// LM.3.2 — band-routed beat counters. Each one increments on
    /// rising-edge of its band's beat onset, scaled by `beatStrength`
    /// (energy modulation). `bassCounter` advances on `f.beatBass`,
    /// `midCounter` on `f.beatMid`, `trebleCounter` on `f.beatTreble`.
    /// `barCounter` advances on `f.barPhase01` wrap (every downbeat in
    /// 4/4) with a fall-back to "every 4 bass beats" when no BeatGrid is
    /// installed and `barPhase01` stays at 0. The shader uses these to
    /// drive team-synchronized cell-colour advances: each cell belongs to
    /// one band team (assigned by hash + per-track seed) and advances
    /// when its team's counter ticks past the team's period boundary.
    public var bassCounter: Float
    public var midCounter: Float
    public var trebleCounter: Float
    public var barCounter: Float

    public init(
        lights: (LumenLightAgent, LumenLightAgent, LumenLightAgent, LumenLightAgent) =
            (.zero, .zero, .zero, .zero),
        patterns: (LumenPattern, LumenPattern, LumenPattern, LumenPattern) =
            (.idle, .idle, .idle, .idle),
        activeLightCount: Int32 = 0,
        activePatternCount: Int32 = 0,
        ambientFloorIntensity: Float = 0,
        smoothedValence: Float = 0,
        smoothedArousal: Float = 0,
        pad0: Float = 0,
        trackPaletteSeedA: Float = 0,
        trackPaletteSeedB: Float = 0,
        trackPaletteSeedC: Float = 0,
        trackPaletteSeedD: Float = 0,
        bassCounter: Float = 0,
        midCounter: Float = 0,
        trebleCounter: Float = 0,
        barCounter: Float = 0
    ) {
        self.lights = lights
        self.patterns = patterns
        self.activeLightCount = activeLightCount
        self.activePatternCount = activePatternCount
        self.ambientFloorIntensity = ambientFloorIntensity
        self.smoothedValence = smoothedValence
        self.smoothedArousal = smoothedArousal
        self.pad0 = pad0
        self.trackPaletteSeedA = trackPaletteSeedA
        self.trackPaletteSeedB = trackPaletteSeedB
        self.trackPaletteSeedC = trackPaletteSeedC
        self.trackPaletteSeedD = trackPaletteSeedD
        self.bassCounter = bassCounter
        self.midCounter = midCounter
        self.trebleCounter = trebleCounter
        self.barCounter = barCounter
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

/// Owns the four light agents + the LM.4.3 cell-dance band counters
/// (the LM.4 pattern-spawn pool was retired at LM.4.4) and flushes the
/// resulting state to a slot-8 fragment buffer once per frame.
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
    /// LM.3.1 sharpened from LM.2's 6.0 → 12.0 (half at r ≈ 0.29 instead
    /// of 0.41) to produce more spotlit backlight character. With softer
    /// falloff, cells equidistant from multiple agents read brighter than
    /// cells under a single agent (geometric overlap), which inverted the
    /// "light from behind" intuition. Sharper falloff makes each agent's
    /// lobe distinct.
    public static let defaultAttenuationRadius: Float = 12.0

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

    // MARK: - LM.4.3 — BeatGrid-driven trigger state
    //
    // **LM.4.3 supersedes the LM.3.2 FFT-band-driven triggers.** The
    // first two M7 reviews on real-music sessions (Matt 2026-05-11,
    // sessions `2026-05-11T15-15-46Z` + `2026-05-11T15-56-41Z`) made
    // the failure mode conclusive: `f.beatBass / beatMid / beatTreble`
    // are FFT bass/mid/treble onset detectors that fire on ~any
    // spectral transient, not on actual kick / snare / hi-hat events.
    // Real-music measurement showed each detector firing at ~2.4
    // events/sec independent of tempo — Pyramid Song (70 BPM, ~1.17
    // kicks/sec) and Love Rehab (118 BPM, ~1.97 kicks/sec) both
    // produced 2.42 bass-band rising edges/sec. The LM.3.2 dance was
    // therefore stepping ~2.4× faster than the song's actual beat
    // regardless of tempo, and the LM.4 onset-spawned ripples were
    // firing at the same rate — Matt's "this still seems like a LOT
    // of ripples" + "color does not really follow the music" feedback.
    //
    // LM.4.3 replaces the FFT triggers with **BeatGrid-derived beat
    // crossings**: `f.beatPhase01` wraps from near-1.0 to near-0.0 on
    // each grid beat (DSP.2 S7 LiveBeatDriftTracker when the grid is
    // locked; MV-3b BeatPredictor in reactive mode pre-grid). The
    // three team counters (`bassCounter / midCounter / trebleCounter`)
    // tick at grid-aligned multiples — every beat, every 2 beats,
    // every 4 beats — giving a clean rhythmic hierarchy correlated to
    // the song's actual tempo. `barCounter` ticks on `f.barPhase01`
    // wraps (downbeats, also from the grid). The every-4-bass-beats
    // fallback is retired (it was driven by the FFT noise we just
    // removed).
    //
    // The LM.3.2 "team" semantics (bass/mid/treble corresponding to
    // FFT bands) is reinterpreted as "team" = "rate of palette
    // advancement": bass-team cells step on every beat (fastest), mid-
    // team cells step on every 2 beats, treble-team cells step on
    // every 4 beats. Cell-team assignment is unchanged shader-side
    // (hash-derived 30/35/25/10 split with the static team).
    //
    // Beat wrap detection thresholds: `prev > beatWrapHigh && now < beatWrapLow`.
    // Wider band than 0.5/0.5 to handle drift-tracker jitter at lock
    // boundaries without spurious double-fires; the band must be at
    // least ~10% wide on each side or fast-rendering tracks can clip a
    // wrap on a single ~16 ms tick.
    private static let beatWrapHigh: Float = 0.85
    private static let beatWrapLow: Float  = 0.15

    private var prevBeatPhase01: Float = 0

    /// Counts grid beats since `midCounter` last advanced. When it
    /// reaches 2, advance `midCounter` and reset. Similarly for treble
    /// at 4.
    private var gridBeatsSinceMidStep: Int = 0
    private var gridBeatsSinceTrebleStep: Int = 0

    // MARK: - LM.4.4 — Pattern engine retired
    //
    // **LM.4.4 deleted the entire pattern-spawn engine.** Matt's third
    // M7 review (session `2026-05-11T17-02-17Z`) confirmed the LM.4.3
    // beat-sync foundation works but flagged the ripple/sweep accent
    // layer as "barely noticeable ... what value is it really adding?".
    // The honest answer: at execution-time-feasible boost levels the
    // spatial wavefront was invisible against the simultaneous bar
    // pulse (both events fire on the downbeat; the panel-wide pulse
    // dominates the local +20% Gaussian band by sheer area). Pushing
    // the wavefront brighter risked re-introducing the LM.4.1-resolved
    // bleach-out.
    //
    // LM.4.4 keeps the LM.3.2 cell-color dance (now driven by LM.4.3
    // grid-wrap counters) + the bar pulse as the entire visual story.
    // The `LumenPattern` / `LumenPatternKind` / `LumenLightAgent`
    // structs and the `state.patterns` tuple stay in `LumenPatternState`
    // for **GPU ABI continuity** — the shader's preamble still declares
    // the slot-8 buffer layout, and any future LM.5+ work (continuous
    // pattern fields like breathing / noiseDrift, NOT transient bursts)
    // could rebind to the same slots without a struct-version bump.
    // The `patterns` tuple and `activePatternCount` are now permanently
    // zeroed; `barCounter` no longer advances (it had no consumer
    // outside the deleted pattern-spawn path).

    // MARK: - Init

    public init?(device: MTLDevice, seed: UInt64 = 0) {
        _ = seed   // reserved for LM.4 deterministic pattern seeding.

        let bufSize = MemoryLayout<LumenPatternState>.stride
        guard let buf = device.makeBuffer(length: bufSize, options: .storageModeShared) else {
            return nil
        }
        self.patternBuffer = buf
        self.basePositions = Self.agentBasePositions

        // Seed agents with their base positions, raw per-stem base colours
        // (no mood tint — the cream-pull baseline was retired at LM.3 because
        // it produced muted output regardless of mood input), and zero
        // intensity. The `colorR/G/B` fields are kept on the struct for ABI
        // continuity but are unused by `LumenMosaic.metal` at LM.3 (cell
        // colour comes from `palette()` keyed on cell hash, not from agent
        // colour). Patterns stay `.idle`.
        var initial = LumenPatternState(
            activeLightCount: Int32(Self.agentCount),
            activePatternCount: 0,
            ambientFloorIntensity: 0   // LM.3: floor moves to a shader-side constant
        )
        initial.lights = (
            Self.makeAgent(at: 0, position: Self.agentBasePositions[0]),
            Self.makeAgent(at: 1, position: Self.agentBasePositions[1]),
            Self.makeAgent(at: 2, position: Self.agentBasePositions[2]),
            Self.makeAgent(at: 3, position: Self.agentBasePositions[3])
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
            state.lights = (
                Self.makeAgent(at: 0, position: basePositions[0]),
                Self.makeAgent(at: 1, position: basePositions[1]),
                Self.makeAgent(at: 2, position: basePositions[2]),
                Self.makeAgent(at: 3, position: basePositions[3])
            )
            state.smoothedValence = 0
            state.smoothedArousal = 0
            // Per-track palette seed is not cleared on reset() — it persists
            // until `setTrackSeed(_:)` is called with a new track. (Reset is
            // called on preset re-apply, not on track change.)
            resetBeatTrackingState()
        }
        writeToGPU()
    }

    /// Internal: zero the cell-dance band counters + LM.4.3 grid wrap-edge
    /// state. Called from `reset()` (preset re-apply) AND from
    /// `setTrackSeed(_:)` (track change). The counters must restart from
    /// 0 on each track so the shader's `floor(counter / period)` cell-
    /// step doesn't carry over.
    ///
    /// `state.patterns` and `state.activePatternCount` stay zeroed (the
    /// LM.4 pattern-spawn engine was deleted at LM.4.4) — they're
    /// zeroed here defensively so any future reset path that lands
    /// after a pattern-engine resurrection wouldn't carry stale data
    /// either. `barCounter` is zeroed for the same belt-and-braces
    /// reason: no live consumer, but a clean reset of the entire
    /// GPU struct field set is cheap.
    /// Caller must hold `lock`.
    private func resetBeatTrackingState() {
        state.bassCounter = 0
        state.midCounter = 0
        state.trebleCounter = 0
        state.barCounter = 0
        prevBeatPhase01 = 0
        gridBeatsSinceMidStep = 0
        gridBeatsSinceTrebleStep = 0
        // Pattern-engine GPU contract — stays zeroed at LM.4.4.
        state.patterns = (.idle, .idle, .idle, .idle)
        state.activePatternCount = 0
    }

    // MARK: - Track palette seed (LM.3 / D-LM-e3)

    /// Set the per-track palette perturbation. Call once per track change so
    /// that two tracks at the same mood produce visibly different palette
    /// character. The seed is a deterministic 4-component perturbation
    /// derived from a hash of the track identity (typically `title + artist`),
    /// scaled into perturbation magnitudes appropriate for each IQ palette
    /// parameter:
    ///
    /// | Component | Perturbs | Magnitude |
    /// |---|---|---|
    /// | seed.x | palette `a` (offset)         | ±0.05 (subtle baseline shift) |
    /// | seed.y | palette `b` (chroma swing)   | ±0.05 (subtle saturation shift) |
    /// | seed.z | palette `c` (channel rate)   | ±0.10 (small cycle-rate shift) |
    /// | seed.w | palette `d` (phase / family) | ±0.20 (larger hue family shift) |
    ///
    /// Each component is expected in `[-1, +1]`; `LumenMosaic.metal` scales
    /// by the appropriate magnitude internally. Pass `.zero` for "no
    /// perturbation" (e.g. test fixtures where you want the baseline mood
    /// palette without per-track variation).
    public func setTrackSeed(_ seed: SIMD4<Float>) {
        lock.withLock {
            state.trackPaletteSeedA = max(-1, min(1, seed.x))
            state.trackPaletteSeedB = max(-1, min(1, seed.y))
            state.trackPaletteSeedC = max(-1, min(1, seed.z))
            state.trackPaletteSeedD = max(-1, min(1, seed.w))
            // LM.3.2 — track change zeros the band counters so the new
            // track's cell-step starts at 0 (otherwise old counter values
            // would carry over and a cell would jump to a far-off palette
            // index on the very first beat of the new track).
            resetBeatTrackingState()
        }
        writeToGPU()
    }

    /// Convenience — derive the seed from a 64-bit hash and call
    /// `setTrackSeed`. The four components are pulled from the four 16-bit
    /// halves of the hash, mapped to `[-1, +1]`.
    public func setTrackSeed(fromHash hash: UInt64) {
        let h0 = Float(Int16(bitPattern: UInt16(hash & 0xFFFF))) / 32768.0
        let h1 = Float(Int16(bitPattern: UInt16((hash >> 16) & 0xFFFF))) / 32768.0
        let h2 = Float(Int16(bitPattern: UInt16((hash >> 32) & 0xFFFF))) / 32768.0
        let h3 = Float(Int16(bitPattern: UInt16((hash >> 48) & 0xFFFF))) / 32768.0
        setTrackSeed(SIMD4<Float>(h0, h1, h2, h3))
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
        // 1 so a long first-tick deltaTime cannot overshoot the input. The
        // smoothed values are written to the GPU state so `LumenMosaic.metal`
        // can interpolate palette parameters with them (LM.3 / D-LM-d4).
        let alpha = min(dt / Self.moodSmoothingSeconds, 1.0)
        smoothedValence += (features.valence - smoothedValence) * alpha
        smoothedArousal += (features.arousal - smoothedArousal) * alpha

        // D-019 warmup mix.
        let totalStemEnergy =
            stems.drumsEnergy + stems.bassEnergy +
            stems.vocalsEnergy + stems.otherEnergy
        let stemMix = lumenSmoothstep(Self.stemWarmupLow, Self.stemWarmupHigh, totalStemEnergy)

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

        // Update each agent. LM.3 retired the cream-baseline mood tint that
        // multiplied the per-stem base colour — agents now write their raw
        // base colour for ABI continuity, but `colorR/G/B` is unused by the
        // LM.3 `sceneMaterial` (cell colour comes from `palette()` keyed on
        // cell hash, not from agents). Agents drive cell INTENSITY only.
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
                colorR: baseColor.x,
                colorG: baseColor.y,
                colorB: baseColor.z,
                intensity: max(0, intensity)
            )
        }

        state.lights = (agents[0], agents[1], agents[2], agents[3])
        state.activeLightCount = Int32(Self.agentCount)
        state.ambientFloorIntensity = 0   // LM.3: silence floor lives in the shader.
        state.smoothedValence = smoothedValence
        state.smoothedArousal = smoothedArousal
        // trackPaletteSeedA/B/C/D are written by setTrackSeed(_:) on track
        // change — _tick must NOT clear them.

        // LM.3.2 band counters + LM.4 pattern pool advancement extracted
        // for SwiftLint function_body_length compliance. Inside, the
        // helper captures the pre-call counter values to detect rising
        // edges, runs `updateBandCounters`, then forwards the edges to
        // `updatePatterns`.
        advancePatternEngine(features: features, dt: dt)
    }

    /// LM.4.4 — single entry point for the LM.3.2 cell-dance band-counter
    /// update. The LM.4 pattern-pool advance was deleted at LM.4.4; the
    /// engine now only maintains the bass/mid/treble counters that the
    /// shader's `lm_cell_palette` reads to drive the per-cell beat-step
    /// dance. `dt` is unused here — kept on the call site for parity
    /// with `_tick`'s signature in case future increments reintroduce
    /// time-dependent advancement.
    private func advancePatternEngine(features: FeatureVector, dt: Float) {
        _ = dt
        updateBandCounters(features: features)
    }

    /// LM.4.4 — advance the three cell-dance band counters on BeatGrid-
    /// derived beat crossings. Caller must hold `lock`. Reads the
    /// `prevBeatPhase01` wrap-edge state from `self`; writes into
    /// `state.bassCounter / midCounter / trebleCounter` and updates
    /// the `gridBeatsSince*Step` phase counters used for mid / treble
    /// subdivision.
    ///
    /// `barCounter` no longer advances — its only consumer (the LM.4
    /// pattern-spawn trigger) was deleted at LM.4.4. The field stays
    /// in `LumenPatternState` for GPU ABI continuity.
    ///
    /// Trigger source: `f.beatPhase01` wraps from `> beatWrapHigh` to
    /// `< beatWrapLow` (each grid beat). The phase comes from the
    /// `LiveBeatDriftTracker` when the grid is locked, or the
    /// `BeatPredictor` fallback in reactive mode pre-grid. It stays
    /// at 0 in pure silence / before any beat detection has converged
    /// — in that case no counters tick and the panel is visually
    /// static (no FFT fallback path; documented in the LM.4.3
    /// engineering-plan entry as a known limitation).
    ///
    /// Counter rates (all advances are uniform `+1.0`, no energy
    /// modulation — the rhythmic regularity carries the music sync,
    /// not loudness variation):
    ///   - `bassCounter`:    every grid beat (every wrap)
    ///   - `midCounter`:     every 2 grid beats
    ///   - `trebleCounter`:  every 4 grid beats
    ///
    /// Note: the "bass / mid / treble" labels are a rate semantic,
    /// not an FFT-band semantic. Cells assigned to the bass team step
    /// fastest, treble team steps slowest. The LM.3.2 team-percentage
    /// split (30/35/25/10) is preserved on the shader side.
    private func updateBandCounters(features: FeatureVector) {
        let beatWrapped = (prevBeatPhase01 > Self.beatWrapHigh)
            && (features.beatPhase01 < Self.beatWrapLow)

        if beatWrapped {
            state.bassCounter += 1
            gridBeatsSinceMidStep += 1
            gridBeatsSinceTrebleStep += 1
            if gridBeatsSinceMidStep >= 2 {
                state.midCounter += 1
                gridBeatsSinceMidStep = 0
            }
            if gridBeatsSinceTrebleStep >= 4 {
                state.trebleCounter += 1
                gridBeatsSinceTrebleStep = 0
            }
        }

        prevBeatPhase01 = features.beatPhase01
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
        position: SIMD2<Float>
    ) -> LumenLightAgent {
        // Raw per-stem base colour — no mood tint (LM.3 retired the cream-
        // baseline mood multiplication that produced muted output). The
        // colour fields are unused by `LumenMosaic.metal` at LM.3 (cell
        // colour comes from `palette()` keyed on cell hash, not from agents)
        // but stay on the struct for ABI continuity with future LM.5+ work
        // that may revisit per-stem hue affinity.
        let baseColor = agentBaseColors[index]
        return LumenLightAgent(
            positionX: position.x,
            positionY: position.y,
            positionZ: 0,
            attenuationRadius: defaultAttenuationRadius,
            colorR: baseColor.x,
            colorG: baseColor.y,
            colorB: baseColor.z,
            intensity: 0
        )
    }
}

// MARK: - Math helpers (file-private)

private func lumenSmoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
    let unit = max(0, min(1, (value - edge0) / max(edge1 - edge0, 1e-6)))
    return unit * unit * (3 - 2 * unit)
}

private func lumenMix(_ from: Float, _ to: Float, t blend: Float) -> Float {
    from + (to - from) * blend
}
