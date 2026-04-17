// AudioFeatures+Analyzed — GPU uniform structs and emotional/structural types.
// FeatureVector and FeedbackParams are uploaded to Metal buffers every frame.
// EmotionalState and StructuralPrediction are CPU-side analysis outputs
// consumed by the Orchestrator for visual decisions.

import Foundation

// MARK: - FeatureVector

/// Packed per-frame audio features for GPU uniform upload.
///
/// This is the primary struct that shaders receive every frame.
/// 48 floats = 192 bytes, naturally 16-byte aligned.
/// Fields follow the audio data hierarchy: continuous energy first,
/// spectral features second, onset pulses third, deviation primitives fourth.
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
///     // MV-1 deviation primitives (floats 26–34)
///     float bass_rel, bass_dev;
///     float mid_rel,  mid_dev;
///     float treb_rel, treb_dev;
///     float bass_att_rel, mid_att_rel, treb_att_rel;
///     // MV-3b beat phase (floats 35–36)
///     float beat_phase01, beats_until_next;
///     // Padding to 192 bytes (floats 37–48)
///     float _pad1, _pad2, _pad3, _pad4, _pad5, _pad6, _pad7,
///           _pad8, _pad9, _pad10, _pad11, _pad12;
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

    // --- Padding to 192 bytes (48 floats total — floats 37–48) ---
    // swiftlint:disable identifier_name
    var _pad1: Float
    var _pad2: Float
    var _pad3: Float
    var _pad4: Float
    var _pad5: Float
    var _pad6: Float
    var _pad7: Float
    var _pad8: Float
    var _pad9: Float
    var _pad10: Float
    var _pad11: Float
    var _pad12: Float
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
        // MV-1 deviation primitives — computed by MIRPipeline each frame.
        self.bassRel = 0; self.bassDev = 0
        self.midRel  = 0; self.midDev  = 0
        self.trebRel = 0; self.trebDev = 0
        self.bassAttRel = 0; self.midAttRel = 0; self.trebAttRel = 0
        // MV-3b beat phase — computed by BeatPredictor each frame.
        self.beatPhase01 = 0; self.beatsUntilNext = 0
        // Padding
        self._pad1 = 0; self._pad2 = 0; self._pad3 = 0; self._pad4 = 0
        self._pad5 = 0; self._pad6 = 0; self._pad7 = 0; self._pad8 = 0
        self._pad9 = 0; self._pad10 = 0; self._pad11 = 0; self._pad12 = 0
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
/// 64 floats × 4 bytes = 256 bytes total (MV-3, D-028).
/// Floats 1–16:  4 per stem (energy, band0, band1, beat) — vocals/drums/bass/other.
/// Floats 17–24: MV-1 deviation primitives (2 per stem: EnergyRel, EnergyDev).
/// Floats 25–40: MV-3a rich metadata (4 per stem: onsetRate, centroid, attackRatio, energySlope).
/// Floats 41–42: MV-3c vocal pitch (vocalsPitchHz, vocalsPitchConfidence).
/// Floats 43–64: padding to 256-byte boundary.
///
/// Band slot semantics:
/// - **vocals**: band0 = presence (1–4 kHz), band1 = air (4–8 kHz)
/// - **drums**:  band0 = sub_bass (20–80 Hz), band1 = mid_high (1–4 kHz)
/// - **bass**:   band0 = sub_bass (20–80 Hz), band1 = low_bass (80–250 Hz)
/// - **other**:  band0 = low_mid (250 Hz–1 kHz), band1 = high_mid (4–8 kHz)
///
/// Deviation semantics (MV-1, D-026):
/// - `xEnergyRel = (xEnergy - runningAvg) * 2.0` — centered at 0
/// - `xEnergyDev = max(0, xEnergyRel)` — positive deviation only
///
/// The matching MSL struct: see PresetLoader+Preamble.swift StemFeatures (64 floats).
@frozen
public struct StemFeatures: Sendable, Equatable {

    // --- Floats 1–16: per-stem energy/band/beat ---

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

    // --- Floats 17–24: MV-1 per-stem deviation primitives ---
    // Populated each frame in StemAnalyzer.analyze().
    // Center is a per-stem EMA running average (decay ≈ 0.995).
    // Formula: xEnergyRel = (xEnergy - runningAvg) * 2.0
    //          xEnergyDev = max(0, xEnergyRel)

    /// Vocals energy deviation: (vocalsEnergy − EMA) × 2.0.
    public var vocalsEnergyRel: Float
    /// Positive vocals energy deviation: max(0, vocalsEnergyRel).
    public var vocalsEnergyDev: Float
    /// Drums energy deviation: (drumsEnergy − EMA) × 2.0.
    public var drumsEnergyRel: Float
    /// Positive drums energy deviation: max(0, drumsEnergyRel).
    public var drumsEnergyDev: Float
    /// Bass energy deviation: (bassEnergy − EMA) × 2.0.
    public var bassEnergyRel: Float
    /// Positive bass energy deviation: max(0, bassEnergyRel).
    public var bassEnergyDev: Float
    /// Other energy deviation: (otherEnergy − EMA) × 2.0.
    public var otherEnergyRel: Float
    /// Positive other energy deviation: max(0, otherEnergyRel).
    public var otherEnergyDev: Float

    // --- Floats 25–40: MV-3a per-stem rich metadata (D-028) ---
    // Populated each frame in StemAnalyzer.analyze().

    /// Vocals onset rate in events/second over a ~0.5s leaky window.
    public var vocalsOnsetRate: Float
    /// Vocals spectral centroid, normalized by Nyquist (0–1).
    public var vocalsCentroid: Float
    /// Vocals attack ratio: fastRMS(50ms) / slowRMS(500ms), clamped 0–3.
    /// High → plucked/transient; low → sustained/pad.
    public var vocalsAttackRatio: Float
    /// Vocals energy slope: derivative of attenuated energy, FPS-independent.
    public var vocalsEnergySlope: Float

    /// Drums onset rate in events/second over a ~0.5s leaky window.
    public var drumsOnsetRate: Float
    /// Drums spectral centroid, normalized by Nyquist (0–1).
    public var drumsCentroid: Float
    /// Drums attack ratio: fastRMS(50ms) / slowRMS(500ms), clamped 0–3.
    public var drumsAttackRatio: Float
    /// Drums energy slope: derivative of attenuated energy, FPS-independent.
    public var drumsEnergySlope: Float

    /// Bass onset rate in events/second over a ~0.5s leaky window.
    public var bassOnsetRate: Float
    /// Bass spectral centroid, normalized by Nyquist (0–1).
    public var bassCentroid: Float
    /// Bass attack ratio: fastRMS(50ms) / slowRMS(500ms), clamped 0–3.
    public var bassAttackRatio: Float
    /// Bass energy slope: derivative of attenuated energy, FPS-independent.
    public var bassEnergySlope: Float

    /// Other onset rate in events/second over a ~0.5s leaky window.
    public var otherOnsetRate: Float
    /// Other spectral centroid, normalized by Nyquist (0–1).
    public var otherCentroid: Float
    /// Other attack ratio: fastRMS(50ms) / slowRMS(500ms), clamped 0–3.
    public var otherAttackRatio: Float
    /// Other energy slope: derivative of attenuated energy, FPS-independent.
    public var otherEnergySlope: Float

    // --- Floats 41–42: MV-3c vocal pitch tracking (D-028) ---
    // Populated each frame in StemAnalyzer.analyze() via PitchTracker (YIN).
    // 0 Hz = unvoiced or low confidence.

    /// Estimated vocal pitch in Hz (YIN autocorrelation). 0 = unvoiced/unconfident.
    public var vocalsPitchHz: Float
    /// Confidence of vocalsPitchHz estimate (0–1). < 0.6 → unreliable.
    public var vocalsPitchConfidence: Float

    // --- Floats 43–64: padding to 256 bytes (22 floats) ---
    // swiftlint:disable identifier_name
    var _sfPad1:  Float; var _sfPad2:  Float; var _sfPad3:  Float; var _sfPad4:  Float
    var _sfPad5:  Float; var _sfPad6:  Float; var _sfPad7:  Float; var _sfPad8:  Float
    var _sfPad9:  Float; var _sfPad10: Float; var _sfPad11: Float; var _sfPad12: Float
    var _sfPad13: Float; var _sfPad14: Float; var _sfPad15: Float; var _sfPad16: Float
    var _sfPad17: Float; var _sfPad18: Float; var _sfPad19: Float; var _sfPad20: Float
    var _sfPad21: Float; var _sfPad22: Float
    // swiftlint:enable identifier_name

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
        // MV-1 deviation primitives — computed by StemAnalyzer each frame.
        self.vocalsEnergyRel = 0; self.vocalsEnergyDev = 0
        self.drumsEnergyRel  = 0; self.drumsEnergyDev  = 0
        self.bassEnergyRel   = 0; self.bassEnergyDev   = 0
        self.otherEnergyRel  = 0; self.otherEnergyDev  = 0
        // MV-3a rich metadata — computed by StemAnalyzer each frame.
        self.vocalsOnsetRate = 0; self.vocalsCentroid = 0
        self.vocalsAttackRatio = 0; self.vocalsEnergySlope = 0
        self.drumsOnsetRate = 0; self.drumsCentroid = 0
        self.drumsAttackRatio = 0; self.drumsEnergySlope = 0
        self.bassOnsetRate = 0; self.bassCentroid = 0
        self.bassAttackRatio = 0; self.bassEnergySlope = 0
        self.otherOnsetRate = 0; self.otherCentroid = 0
        self.otherAttackRatio = 0; self.otherEnergySlope = 0
        // MV-3c vocal pitch — computed by StemAnalyzer via PitchTracker.
        self.vocalsPitchHz = 0; self.vocalsPitchConfidence = 0
        // Padding
        self._sfPad1  = 0; self._sfPad2  = 0; self._sfPad3  = 0; self._sfPad4  = 0
        self._sfPad5  = 0; self._sfPad6  = 0; self._sfPad7  = 0; self._sfPad8  = 0
        self._sfPad9  = 0; self._sfPad10 = 0; self._sfPad11 = 0; self._sfPad12 = 0
        self._sfPad13 = 0; self._sfPad14 = 0; self._sfPad15 = 0; self._sfPad16 = 0
        self._sfPad17 = 0; self._sfPad18 = 0; self._sfPad19 = 0; self._sfPad20 = 0
        self._sfPad21 = 0; self._sfPad22 = 0
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
