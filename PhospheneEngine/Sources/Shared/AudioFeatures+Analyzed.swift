// AudioFeatures+Analyzed — GPU uniform structs and emotional/structural types.
// FeatureVector and FeedbackParams are uploaded to Metal buffers every frame.
// EmotionalState and StructuralPrediction are CPU-side analysis outputs
// consumed by the Orchestrator for visual decisions.

import Foundation

// MARK: - FeatureVector

/// Packed per-frame audio features for GPU uniform upload.
///
/// This is the primary struct that shaders receive every frame, bound at `buffer(0)`.
/// 52 floats = 208 bytes. Fields follow the
/// audio data hierarchy: continuous energy first, spectral features second, onset pulses
/// third, deviation primitives fourth.
///
/// **ORDER IS THE CONTRACT, and it is stated in exactly three places — none of them here.**
/// This doc comment used to carry a fourth copy of the MSL struct; it had drifted to "48
/// floats = 192 bytes" and listed fields only through 48, i.e. it was wrong by two
/// increments and nothing caught it, because no gate reads prose. Removed at FTR.6 rather
/// than re-synced. The authoritative declarations are:
///
/// - this Swift struct;
/// - `PresetLoader+Preamble.swift` (runtime-compiled preset shaders);
/// - `Renderer/Shaders/Common.metal` (engine-library shaders).
///
/// `CommonLayoutTest` parses the latter two and asserts they agree with each other AND with
/// `MemoryLayout<FeatureVector>.size`, field name by field name. Append only, keep the
/// stride a multiple of 16, and update all three in one commit.

@frozen
public struct FeatureVector: Sendable {

    // --- Layer 1: Continuous energy bands (PRIMARY DRIVER) ---

    /// 3-band instant energy (fast smoothing).
    public var bass: Float
    public var mid: Float
    public var treble: Float

    /// 3-band attenuated energy (heavy smoothing, slow-flowing motion).
    public var bassAtt: Float
    public var midAtt: Float
    public var trebleAtt: Float

    /// 6-band energy (preserves relative differences via total-energy AGC).
    public var subBass: Float
    public var lowBass: Float
    public var lowMid: Float
    public var midHigh: Float
    public var highMid: Float
    public var high: Float

    // --- Layer 4: Onset pulses (ACCENT ONLY) ---

    /// Beat onset pulses, 0–1 with exponential decay.
    public var beatBass: Float
    public var beatMid: Float
    public var beatTreble: Float
    public var beatComposite: Float

    // --- Layer 3: Spectral features ---

    /// Spectral centroid — modulates palette warmth.
    public var spectralCentroid: Float
    /// Continuous spectral flux — rate of timbral change.
    public var spectralFlux: Float

    // --- Emotion (from ML) ---

    /// Valence: -1 (sad/tense) to +1 (happy/relaxed).
    public var valence: Float
    /// Arousal: -1 (calm) to +1 (energetic).
    public var arousal: Float

    // --- Timing ---

    /// Seconds since visualization start.
    public var time: Float
    /// Seconds since last frame.
    public var deltaTime: Float

    // --- Waveform occupancy (float 23) — RECLAIMED from `_pad0` at CHR.3c ---

    /// Spectrum active vs each band's OWN ~20 s level; → 0 at silence. Time-domain derived,
    /// written by `RenderPipeline`. Full rationale: `WaveformOccupancy`.
    public var waveformOccupancy: Float

    // --- Viewport (float 24) ---

    /// Viewport aspect ratio (width / height). Set each frame by the render
    /// pipeline from the drawable size. Shaders use this for aspect-correct
    /// geometric calculations (e.g. rendering circles as actual circles
    /// rather than UV-space ellipses).
    public var aspectRatio: Float

    // --- Accumulated audio time (float 25) ---

    /// Running sum of energy × deltaTime, reset on track change.
    ///
    /// Unlike `time` (wall-clock seconds), this value accumulates faster during
    /// loud passages and slower during quiet ones, producing animation that
    /// "breathes" with the music. Use as an animation phase in shaders.
    public var accumulatedAudioTime: Float

    // --- MV-1: Milkdrop-correct deviation primitives (floats 26–34) ---
    //
    // Populated each frame in MIRPipeline.process(). Provide stable,
    // mix-density-independent primitives for preset shader authoring.
    //
    // Rule (D-026): drive visuals from Rel/Dev, not from absolute f.bass/f.mid.
    // - Use Rel for continuous drivers that should swing negative during quiet
    //   sections: `zoom = baseZoom + 0.1 * f.bassAttRel`
    // - Use Dev for accent/threshold drivers that fire only on loud moments:
    //   `smoothstep(0.0, 0.3, f.bassDev)`
    //
    // Formula: xRel = (x - 0.5) * 2.0  — centered at 0, ~±0.5 typical range
    //          xDev = max(0, xRel)      — positive deviation only

    /// Bass deviation: (bass − 0.5) × 2.0. Centered at 0; ~±0.5 typical range.
    public var bassRel: Float
    /// Positive bass deviation: max(0, bassRel). Non-zero only on louder-than-average moments.
    public var bassDev: Float
    /// Mid deviation: (mid − 0.5) × 2.0.
    public var midRel: Float
    /// Positive mid deviation: max(0, midRel).
    public var midDev: Float
    /// Treble deviation: (treble − 0.5) × 2.0.
    public var trebRel: Float
    /// Positive treble deviation: max(0, trebRel).
    public var trebDev: Float
    /// Smoothed bass deviation: (bassAtt − 0.5) × 2.0. For slow continuous motion drivers.
    public var bassAttRel: Float
    /// Smoothed mid deviation: (midAtt − 0.5) × 2.0.
    public var midAttRel: Float
    /// Smoothed treble deviation: (trebleAtt − 0.5) × 2.0.
    public var trebAttRel: Float

    // --- MV-3b: Beat phase predictor (floats 35–36, D-028) ---
    //
    // Populated each frame by BeatPredictor in MIRPipeline.process().
    // Enables "anticipatory" preset motion that starts BEFORE the beat lands.
    //
    // beatPhase01:    0 at the last detected beat, linearly rises to 1 at the
    //                 predicted next beat. Resets to 0 if tempo is lost for
    //                 > 3× the estimated period.
    // beatsUntilNext: Fractional beats until the next predicted beat (1 - beatPhase01).

    /// Beat cycle phase: 0 at last beat, rising linearly to 1 at next predicted beat.
    public var beatPhase01: Float
    /// Fractional beats until next predicted beat. 1.0 immediately after a beat.
    public var beatsUntilNext: Float

    // --- Bar phase (floats 37–38) ---

    /// Phrase-level bar phase: 0 at downbeat, linearly rises to 1 at next downbeat.
    /// Always 0 in reactive mode (no BeatGrid installed).
    public var barPhase01: Float
    /// Time-signature numerator (4 for 4/4, 3 for 3/4, 7 for 7/8, etc.).
    /// Defaults to 4 when no BeatGrid is installed.
    public var beatsPerBar: Float

    /// CSP.3 (2026-05-27) — track-relative elapsed seconds; resets to 0 on
    /// `MIRPipeline.reset()` (track change). Shader cold-start crossfades.
    ///
    /// **When the `ffoColdStartFixEnabled` UserDefaults toggle is OFF**,
    /// `MIRPipeline` populates this field with a large value (100.0) so the
    /// shader's `smoothstep(0.5, 14, trackElapsedS)` returns 1.0 — the cold-
    /// start path collapses to the warm path, restoring pre-CSP behaviour
    /// without recompiling.
    ///
    /// Slot reclaimed from `_pad3` to preserve byte-identical layout of
    /// fields 1–38.
    public var trackElapsedS: Float

    /// FBS (D-153, float 40, reclaimed `_pad4`): steady first-note-anchored
    /// pulse phase — 0 at each pulse → 1 at the next; cached-grid tempo,
    /// never drift-corrected (unlike `beatPhase01`); from `BeatPulseClock`.
    public var pulsePhase01: Float
    /// Pulse gate (float 41, reclaimed `_pad5`): 0 before the first note /
    /// in sustained silence, 1 while music plays.
    public var pulseAmp01: Float
    /// D-157 (float 42, reclaimed `_pad6`): completed pulse-cycle count —
    /// seeds the per-beat spatial punch mask.
    public var pulseBeatIndex: Float
    /// D-158 (float 43, reclaimed `_pad7`): regional punch-mask blend —
    /// 0 on the bridge (global heave), ramps 0 → 1 over one 4-beat span
    /// after the handoff. FFO mixes `mix(1.0, mask, blend)` into the punch.
    public var pulseRegionalBlend01: Float

    // --- TONAL (D-178, floats 44–48): fifths=hue, consonance gates saturation,
    // tension=distance-from-home, flux=chord-change. Rationale: `Common.metal`. ---
    public var tonalPhaseFifths, tonalPhaseThirds: Float
    public var tonalConsonance, tonalTension, harmonicFlux: Float
    /// DYN.2 float 52 — section-scale density (τ ≈ 10 s). See DYN1_CALIBRATION §DYN.2.
    public var spectralDensity, spectralDensitySlow, spectralSurge: Float
    public var spectralSectionRatio: Float
    /// FTR.24 float 53 — LEVEL RISE, the transient sibling of `spectralSurge`: pre-AGC level
    /// against its own 0.15 s trailing floor, instant attack, 0.20 s release. `spectralSurge`
    /// answers "how loud is this passage"; this answers "did something just LAND". Rationale
    /// and the measured event specificity of every alternative: `SpectralAnalyzer.Result`.
    public var spectralLevelRise: Float
    // Floats 54–56 — PADDING. 53 floats is 212 bytes and a GPU constant buffer must be
    // 16-byte aligned; the same reason floats 51–52 were padding before DYN.1b/DYN.2 claimed
    // them. ORDER IS THE CONTRACT — `Common.metal` must match field-for-field.
    // swiftlint:disable:next identifier_name
    public var _pad54, _pad55, _pad56: Float

    public init(
        bass: Float = 0, mid: Float = 0, treble: Float = 0,
        bassAtt: Float = 0, midAtt: Float = 0, trebleAtt: Float = 0,
        subBass: Float = 0, lowBass: Float = 0, lowMid: Float = 0,
        midHigh: Float = 0, highMid: Float = 0, high: Float = 0,
        beatBass: Float = 0, beatMid: Float = 0, beatTreble: Float = 0,
        beatComposite: Float = 0,
        spectralCentroid: Float = 0, spectralFlux: Float = 0,
        valence: Float = 0, arousal: Float = 0,
        time: Float = 0, deltaTime: Float = 0,
        aspectRatio: Float = 1.777,
        accumulatedAudioTime: Float = 0
    ) {
        self.bass = bass; self.mid = mid; self.treble = treble
        self.bassAtt = bassAtt; self.midAtt = midAtt; self.trebleAtt = trebleAtt
        self.subBass = subBass; self.lowBass = lowBass; self.lowMid = lowMid
        self.midHigh = midHigh; self.highMid = highMid; self.high = high
        self.beatBass = beatBass; self.beatMid = beatMid; self.beatTreble = beatTreble
        self.beatComposite = beatComposite
        self.spectralCentroid = spectralCentroid; self.spectralFlux = spectralFlux
        self.valence = valence; self.arousal = arousal
        self.time = time; self.deltaTime = deltaTime
        self.waveformOccupancy = 0
        self.aspectRatio = aspectRatio
        self.accumulatedAudioTime = accumulatedAudioTime
        // MV-1 deviation primitives — computed by MIRPipeline each frame.
        self.bassRel = 0; self.bassDev = 0
        self.midRel  = 0; self.midDev  = 0
        self.trebRel = 0; self.trebDev = 0
        self.bassAttRel = 0; self.midAttRel = 0; self.trebAttRel = 0
        // MV-3b beat phase — computed by BeatPredictor / LiveBeatDriftTracker each frame.
        self.beatPhase01 = 0; self.beatsUntilNext = 0
        self.barPhase01 = 0; self.beatsPerBar = 4
        // CSP.3 — set per frame by MIRPipeline from `elapsedSeconds`; 100.0 when the
        // ffoColdStartFixEnabled toggle is off. Detail: `Common.metal`.
        self.trackElapsedS = 0
        self.pulsePhase01 = 0; self.pulseAmp01 = 0; self.pulseBeatIndex = 0
        self.pulseRegionalBlend01 = 0
        self.tonalPhaseFifths = 0; self.tonalPhaseThirds = 0; self.tonalConsonance = 0
        self.tonalTension = 0; self.harmonicFlux = 0   // TONAL (D-178), set by TonalAnalyzer
        self.spectralDensity = 0; self.spectralDensitySlow = 0; self.spectralSurge = 0
        self.spectralSectionRatio = 0
        self.spectralLevelRise = 0          // FTR.24, set per frame by SpectralAnalyzer
        self._pad54 = 0; self._pad55 = 0; self._pad56 = 0
    }

    /// All-zero feature vector.
    public static let zero = FeatureVector()
}

// MARK: - FeedbackParams

/// Per-frame feedback parameters for Milkdrop-style render loop.
///
/// Populated from `PresetDescriptor` and the current `FeatureVector` each frame.
/// The matching MSL struct:
/// ```metal
/// struct FeedbackParams {
///     float decay, base_zoom, base_rot;
///     float beat_zoom, beat_rot, beat_sensitivity;
///     float beat_value, _pad0;
/// };
/// ```
@frozen
public struct FeedbackParams: Sendable {
    /// Feedback decay per frame. 0.85 = short trails, 0.95 = long trails.
    public var decay: Float
    /// Continuous energy zoom (primary driver). Bass-driven.
    public var baseZoom: Float
    /// Continuous energy rotation (primary driver). Mid-driven.
    public var baseRot: Float
    /// Beat accent zoom (secondary).
    public var beatZoom: Float
    /// Beat accent rotation (secondary).
    public var beatRot: Float
    /// Beat pulse multiplier. 0 = ignore beats, up to 3.0.
    public var beatSensitivity: Float
    /// Pre-selected beat pulse value (from beatSource: bass/mid/treble/composite).
    public var beatValue: Float
    // Padding to 32 bytes (8 × Float).
    // swiftlint:disable:next identifier_name
    public var _pad0: Float

    public init(
        decay: Float = 0.955,
        baseZoom: Float = 0.12,
        baseRot: Float = 0.03,
        beatZoom: Float = 0.03,
        beatRot: Float = 0.01,
        beatSensitivity: Float = 1.0,
        beatValue: Float = 0
    ) {
        self.decay = decay
        self.baseZoom = baseZoom
        self.baseRot = baseRot
        self.beatZoom = beatZoom
        self.beatRot = beatRot
        self.beatSensitivity = beatSensitivity
        self.beatValue = beatValue
        self._pad0 = 0
    }
}

// MARK: - EmotionalQuadrant

/// Quadrant in the valence-arousal circumplex model.
///
/// Maps to Russell's circumplex: valence (positive/negative) × arousal (high/low).
public enum EmotionalQuadrant: String, Sendable, Equatable, Codable {
    /// High valence, high arousal (e.g., euphoric dance track).
    case happy
    /// Low valence, low arousal (e.g., slow minor-key ballad).
    case sad
    /// Low valence, high arousal (e.g., aggressive distorted riff).
    case tense
    /// High valence, low arousal (e.g., gentle acoustic lullaby).
    case calm
}

// MARK: - EmotionalState

/// Continuous emotional coordinates from the mood classifier.
///
/// Maps to Russell's circumplex model of affect:
/// - Valence: -1 (negative/sad) to +1 (positive/happy)
/// - Arousal: -1 (calm/relaxed) to +1 (energetic/excited)
public struct EmotionalState: Sendable, Equatable, Codable {

    /// Emotional valence: -1 (sad/tense) to +1 (happy/calm).
    public var valence: Float

    /// Emotional arousal: -1 (calm) to +1 (energetic).
    public var arousal: Float

    /// The quadrant this emotional state falls in.
    public var quadrant: EmotionalQuadrant {
        switch (valence >= 0, arousal >= 0) {
        case (true, true):   return .happy
        case (false, false): return .sad
        case (false, true):  return .tense
        case (true, false):  return .calm
        }
    }

    public init(valence: Float = 0, arousal: Float = 0) {
        self.valence = valence
        self.arousal = arousal
    }

    /// Neutral emotional state (origin of the circumplex).
    public static let neutral = EmotionalState()
}

// MARK: - StructuralPrediction

/// Progressive structural analysis prediction.
///
/// CPU-only — not uploaded to GPU buffers. Provides section-level
/// anticipation for the Orchestrator to trigger transitions ahead
/// of musical boundaries.
@frozen
public struct StructuralPrediction: Sendable, Equatable {

    /// Current section number (0-based). Increments at each detected boundary.
    public var sectionIndex: UInt32

    /// Timestamp (seconds since capture start) when the current section began.
    public var sectionStartTime: Float

    /// Predicted timestamp of the next section boundary.
    public var predictedNextBoundary: Float

    /// Confidence of the prediction, 0–1. Low for ambient/random material,
    /// high for repetitive ABAB patterns.
    public var confidence: Float

    public init(
        sectionIndex: UInt32 = 0,
        sectionStartTime: Float = 0,
        predictedNextBoundary: Float = 0,
        confidence: Float = 0
    ) {
        self.sectionIndex = sectionIndex
        self.sectionStartTime = sectionStartTime
        self.predictedNextBoundary = predictedNextBoundary
        self.confidence = confidence
    }

    /// No prediction available.
    public static let none = StructuralPrediction()
}
