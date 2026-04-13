// AudioFeatures+Analyzed — GPU uniform structs and emotional/structural types.
// FeatureVector and FeedbackParams are uploaded to Metal buffers every frame.
// EmotionalState and StructuralPrediction are CPU-side analysis outputs
// consumed by the Orchestrator for visual decisions.

import Foundation

// MARK: - FeatureVector

/// Packed per-frame audio features for GPU uniform upload.
///
/// This is the primary struct that shaders receive every frame.
/// 32 floats = 128 bytes, naturally 16-byte aligned.
/// Fields follow the audio data hierarchy: continuous energy first,
/// spectral features second, onset pulses third.
///
/// The matching MSL struct:
/// ```metal
/// struct FeatureVector {
///     float bass, mid, treble;
///     float bass_att, mid_att, treb_att;
///     float sub_bass, low_bass, low_mid, mid_high, high_mid, high;
///     float beat_bass, beat_mid, beat_treble, beat_composite;
///     float spectral_centroid, spectral_flux;
///     float valence, arousal;
///     float time, delta_time;
///     float _pad0, aspect_ratio;
///     float accumulated_audio_time;
///     float _pad1, _pad2, _pad3, _pad4, _pad5, _pad6, _pad7;
/// };
/// ```
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

    // --- Padding (float 23) ---
    // swiftlint:disable:next identifier_name
    public var _pad0: Float

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

    // --- Padding to 128 bytes (floats 26–32) ---
    // swiftlint:disable identifier_name
    var _pad1: Float
    var _pad2: Float
    var _pad3: Float
    var _pad4: Float
    var _pad5: Float
    var _pad6: Float
    var _pad7: Float
    // swiftlint:enable identifier_name

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
        self._pad0 = 0
        self.aspectRatio = aspectRatio
        self.accumulatedAudioTime = accumulatedAudioTime
        self._pad1 = 0; self._pad2 = 0; self._pad3 = 0; self._pad4 = 0
        self._pad5 = 0; self._pad6 = 0; self._pad7 = 0
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
public struct EmotionalState: Sendable, Equatable {

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

// MARK: - StemFeatures

/// Per-stem audio features bound to GPU buffer(3).
///
/// 16 floats × 4 bytes = 64 bytes total. 4 floats per stem:
/// energy, two band slots (stem-specific), beat pulse (only non-zero for drums today).
///
/// Band slot semantics:
/// - **vocals**: band0 = presence (1–4 kHz), band1 = air (4–8 kHz)
/// - **drums**:  band0 = sub_bass (20–80 Hz), band1 = mid_high (1–4 kHz)
/// - **bass**:   band0 = sub_bass (20–80 Hz), band1 = low_bass (80–250 Hz)
/// - **other**:  band0 = low_mid (250 Hz–1 kHz), band1 = high_mid (4–8 kHz)
///
/// The matching MSL struct:
/// ```metal
/// struct StemFeatures {
///     float vocals_energy;   float vocals_band0;
///     float vocals_band1;    float vocals_beat;
///     float drums_energy;    float drums_band0;
///     float drums_band1;     float drums_beat;
///     float bass_energy;     float bass_band0;
///     float bass_band1;      float bass_beat;
///     float other_energy;    float other_band0;
///     float other_band1;     float other_beat;
/// };
/// ```
@frozen
public struct StemFeatures: Sendable {

    /// Vocals: total energy across all vocal bands.
    public var vocalsEnergy: Float
    /// Vocals band 0: presence (1–4 kHz).
    public var vocalsBand0: Float
    /// Vocals band 1: air (4–8 kHz).
    public var vocalsBand1: Float
    /// Vocals beat pulse (reserved — currently always 0).
    public var vocalsBeat: Float

    /// Drums: total energy across all drum bands.
    public var drumsEnergy: Float
    /// Drums band 0: sub bass (20–80 Hz).
    public var drumsBand0: Float
    /// Drums band 1: mid high (1–4 kHz, snare crack).
    public var drumsBand1: Float
    /// Drums beat pulse from BeatDetector.
    public var drumsBeat: Float

    /// Bass: total energy across bass bands.
    public var bassEnergy: Float
    /// Bass band 0: sub bass (20–80 Hz).
    public var bassBand0: Float
    /// Bass band 1: low bass (80–250 Hz).
    public var bassBand1: Float
    /// Bass beat pulse (reserved — currently always 0).
    public var bassBeat: Float

    /// Other: total energy across remaining instruments.
    public var otherEnergy: Float
    /// Other band 0: low mid (250 Hz–1 kHz).
    public var otherBand0: Float
    /// Other band 1: high mid (4–8 kHz).
    public var otherBand1: Float
    /// Other beat pulse (reserved — currently always 0).
    public var otherBeat: Float

    public init(
        vocalsEnergy: Float = 0, vocalsBand0: Float = 0,
        vocalsBand1: Float = 0, vocalsBeat: Float = 0,
        drumsEnergy: Float = 0, drumsBand0: Float = 0,
        drumsBand1: Float = 0, drumsBeat: Float = 0,
        bassEnergy: Float = 0, bassBand0: Float = 0,
        bassBand1: Float = 0, bassBeat: Float = 0,
        otherEnergy: Float = 0, otherBand0: Float = 0,
        otherBand1: Float = 0, otherBeat: Float = 0
    ) {
        self.vocalsEnergy = vocalsEnergy; self.vocalsBand0 = vocalsBand0
        self.vocalsBand1 = vocalsBand1; self.vocalsBeat = vocalsBeat
        self.drumsEnergy = drumsEnergy; self.drumsBand0 = drumsBand0
        self.drumsBand1 = drumsBand1; self.drumsBeat = drumsBeat
        self.bassEnergy = bassEnergy; self.bassBand0 = bassBand0
        self.bassBand1 = bassBand1; self.bassBeat = bassBeat
        self.otherEnergy = otherEnergy; self.otherBand0 = otherBand0
        self.otherBand1 = otherBand1; self.otherBeat = otherBeat
    }

    /// All-zero stem features — safe default during warmup.
    public static let zero = StemFeatures()
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
