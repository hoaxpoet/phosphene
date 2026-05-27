// MARK: - StemFeatures

/// Per-stem audio features bound to GPU buffer(3).
///
/// 64 floats × 4 bytes = 256 bytes total (MV-3, D-028).
/// Floats 1–16:  4 per stem (energy, band0, band1, beat) — vocals/drums/bass/other.
/// Floats 17–24: MV-1 deviation primitives (2 per stem: EnergyRel, EnergyDev).
/// Floats 25–40: MV-3a rich metadata (4 per stem: onsetRate, centroid, attackRatio, energySlope).
/// Floats 41–42: MV-3c vocal pitch (vocalsPitchHz, vocalsPitchConfidence).
/// Float 43:     V.9 / D-127 drumsEnergyDev 150 ms τ EMA (aurora curtain intensity).
/// Floats 44–64: padding to 256-byte boundary.
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

    /// Vocals onset rate in events/second over a ~0.5s leaky window.
    public var vocalsOnsetRate: Float
    /// Vocals spectral centroid, normalized by Nyquist (0–1).
    public var vocalsCentroid: Float
    /// Vocals attack ratio: fastRMS(50ms) / slowRMS(500ms), clamped 0–3.
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

    /// Estimated vocal pitch in Hz (YIN autocorrelation). 0 = unvoiced/unconfident.
    public var vocalsPitchHz: Float
    /// Confidence of vocalsPitchHz estimate (0–1). < 0.6 → unreliable.
    public var vocalsPitchConfidence: Float

    // --- Float 43: V.9 Session 4.5c / D-127 aurora-reflection drums smoother ---

    /// `drumsEnergyDev` after a CPU-side 150 ms τ EMA. Drives the Ferrofluid
    /// Ocean aurora curtain intensity (matID == 2 sky function). The renderer
    /// updates this in `RenderPipeline.drawWithRayMarch` before the lighting
    /// pass binds StemFeatures at buffer(3). Zero on every other preset.
    public var drumsEnergyDevSmoothed: Float

    /// CSP.3 (2026-05-27) — bass proportion from the pre-playback analysis
    /// of the 30 s preview clip. `bassEnergy / (vocalsEnergy + drumsEnergy +
    /// bassEnergy + otherEnergy)`, ∈ `[0, 1]`. Frozen for the track's
    /// duration: populated once at track-change from the cached
    /// `CachedTrackData.stemFeatures` and **preserved across live per-frame
    /// `setStemFeatures(_:)` updates** (see `RenderPipeline+PresetSwitching`).
    /// Drives the Ferrofluid Ocean spike-height baseline at frame 1.
    ///
    /// **When the `ffoColdStartFixEnabled` UserDefaults toggle is OFF**, the
    /// app layer sets this to 0.25 (the formula's pivot) so the shader-side
    /// baseline contribution collapses to 0 — restoring pre-CSP behaviour
    /// without recompiling.
    ///
    /// Slot reclaimed from `_sfPad2` to preserve byte-identical layout of
    /// fields 1–43.
    public var cachedBassProportion: Float

    // --- Floats 45–64: padding to 256 bytes (20 floats) ---
    // swiftlint:disable identifier_name
    var _sfPad3: Float; var _sfPad4: Float
    var _sfPad5: Float; var _sfPad6: Float; var _sfPad7: Float; var _sfPad8: Float
    var _sfPad9: Float; var _sfPad10: Float; var _sfPad11: Float; var _sfPad12: Float
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
        self.vocalsEnergyRel = 0; self.vocalsEnergyDev = 0
        self.drumsEnergyRel  = 0; self.drumsEnergyDev  = 0
        self.bassEnergyRel   = 0; self.bassEnergyDev   = 0
        self.otherEnergyRel  = 0; self.otherEnergyDev  = 0
        self.vocalsOnsetRate = 0; self.vocalsCentroid = 0
        self.vocalsAttackRatio = 0; self.vocalsEnergySlope = 0
        self.drumsOnsetRate = 0; self.drumsCentroid = 0
        self.drumsAttackRatio = 0; self.drumsEnergySlope = 0
        self.bassOnsetRate = 0; self.bassCentroid = 0
        self.bassAttackRatio = 0; self.bassEnergySlope = 0
        self.otherOnsetRate = 0; self.otherCentroid = 0
        self.otherAttackRatio = 0; self.otherEnergySlope = 0
        self.vocalsPitchHz = 0; self.vocalsPitchConfidence = 0
        self.drumsEnergyDevSmoothed = 0
        self.cachedBassProportion = 0
        self._sfPad3  = 0; self._sfPad4  = 0
        self._sfPad5  = 0; self._sfPad6  = 0; self._sfPad7  = 0; self._sfPad8  = 0
        self._sfPad9  = 0; self._sfPad10 = 0; self._sfPad11 = 0; self._sfPad12 = 0
        self._sfPad13 = 0; self._sfPad14 = 0; self._sfPad15 = 0; self._sfPad16 = 0
        self._sfPad17 = 0; self._sfPad18 = 0; self._sfPad19 = 0; self._sfPad20 = 0
        self._sfPad21 = 0; self._sfPad22 = 0
    }

    /// All-zero stem features — safe default during warmup.
    public static let zero = StemFeatures()
}

// MARK: - Codable

/// On-disk encoding for `PersistentStemCache` (LF.3, D-130).
///
/// Only the 44 load-bearing fields participate. The internal `_sfPad*`
/// padding floats (slots 45–64) exist for the 256-byte GPU contract and
/// have no semantic content — excluding them keeps the on-disk format
/// stable across any future padding-layout change.
extension StemFeatures: Codable {

    // swiftlint:disable:next nesting
    private enum CodingKeys: String, CodingKey {
        case vocalsEnergy, vocalsBand0, vocalsBand1, vocalsBeat
        case drumsEnergy, drumsBand0, drumsBand1, drumsBeat
        case bassEnergy, bassBand0, bassBand1, bassBeat
        case otherEnergy, otherBand0, otherBand1, otherBeat
        case vocalsEnergyRel, vocalsEnergyDev
        case drumsEnergyRel, drumsEnergyDev
        case bassEnergyRel, bassEnergyDev
        case otherEnergyRel, otherEnergyDev
        case vocalsOnsetRate, vocalsCentroid, vocalsAttackRatio, vocalsEnergySlope
        case drumsOnsetRate, drumsCentroid, drumsAttackRatio, drumsEnergySlope
        case bassOnsetRate, bassCentroid, bassAttackRatio, bassEnergySlope
        case otherOnsetRate, otherCentroid, otherAttackRatio, otherEnergySlope
        case vocalsPitchHz, vocalsPitchConfidence
        case drumsEnergyDevSmoothed
        case cachedBassProportion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        vocalsEnergy = try c.decode(Float.self, forKey: .vocalsEnergy)
        vocalsBand0 = try c.decode(Float.self, forKey: .vocalsBand0)
        vocalsBand1 = try c.decode(Float.self, forKey: .vocalsBand1)
        vocalsBeat = try c.decode(Float.self, forKey: .vocalsBeat)
        drumsEnergy = try c.decode(Float.self, forKey: .drumsEnergy)
        drumsBand0 = try c.decode(Float.self, forKey: .drumsBand0)
        drumsBand1 = try c.decode(Float.self, forKey: .drumsBand1)
        drumsBeat = try c.decode(Float.self, forKey: .drumsBeat)
        bassEnergy = try c.decode(Float.self, forKey: .bassEnergy)
        bassBand0 = try c.decode(Float.self, forKey: .bassBand0)
        bassBand1 = try c.decode(Float.self, forKey: .bassBand1)
        bassBeat = try c.decode(Float.self, forKey: .bassBeat)
        otherEnergy = try c.decode(Float.self, forKey: .otherEnergy)
        otherBand0 = try c.decode(Float.self, forKey: .otherBand0)
        otherBand1 = try c.decode(Float.self, forKey: .otherBand1)
        otherBeat = try c.decode(Float.self, forKey: .otherBeat)
        vocalsEnergyRel = try c.decode(Float.self, forKey: .vocalsEnergyRel)
        vocalsEnergyDev = try c.decode(Float.self, forKey: .vocalsEnergyDev)
        drumsEnergyRel = try c.decode(Float.self, forKey: .drumsEnergyRel)
        drumsEnergyDev = try c.decode(Float.self, forKey: .drumsEnergyDev)
        bassEnergyRel = try c.decode(Float.self, forKey: .bassEnergyRel)
        bassEnergyDev = try c.decode(Float.self, forKey: .bassEnergyDev)
        otherEnergyRel = try c.decode(Float.self, forKey: .otherEnergyRel)
        otherEnergyDev = try c.decode(Float.self, forKey: .otherEnergyDev)
        vocalsOnsetRate = try c.decode(Float.self, forKey: .vocalsOnsetRate)
        vocalsCentroid = try c.decode(Float.self, forKey: .vocalsCentroid)
        vocalsAttackRatio = try c.decode(Float.self, forKey: .vocalsAttackRatio)
        vocalsEnergySlope = try c.decode(Float.self, forKey: .vocalsEnergySlope)
        drumsOnsetRate = try c.decode(Float.self, forKey: .drumsOnsetRate)
        drumsCentroid = try c.decode(Float.self, forKey: .drumsCentroid)
        drumsAttackRatio = try c.decode(Float.self, forKey: .drumsAttackRatio)
        drumsEnergySlope = try c.decode(Float.self, forKey: .drumsEnergySlope)
        bassOnsetRate = try c.decode(Float.self, forKey: .bassOnsetRate)
        bassCentroid = try c.decode(Float.self, forKey: .bassCentroid)
        bassAttackRatio = try c.decode(Float.self, forKey: .bassAttackRatio)
        bassEnergySlope = try c.decode(Float.self, forKey: .bassEnergySlope)
        otherOnsetRate = try c.decode(Float.self, forKey: .otherOnsetRate)
        otherCentroid = try c.decode(Float.self, forKey: .otherCentroid)
        otherAttackRatio = try c.decode(Float.self, forKey: .otherAttackRatio)
        otherEnergySlope = try c.decode(Float.self, forKey: .otherEnergySlope)
        vocalsPitchHz = try c.decode(Float.self, forKey: .vocalsPitchHz)
        vocalsPitchConfidence = try c.decode(Float.self, forKey: .vocalsPitchConfidence)
        drumsEnergyDevSmoothed = try c.decode(Float.self, forKey: .drumsEnergyDevSmoothed)
        cachedBassProportion = try c.decode(Float.self, forKey: .cachedBassProportion)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vocalsEnergy, forKey: .vocalsEnergy)
        try c.encode(vocalsBand0, forKey: .vocalsBand0)
        try c.encode(vocalsBand1, forKey: .vocalsBand1)
        try c.encode(vocalsBeat, forKey: .vocalsBeat)
        try c.encode(drumsEnergy, forKey: .drumsEnergy)
        try c.encode(drumsBand0, forKey: .drumsBand0)
        try c.encode(drumsBand1, forKey: .drumsBand1)
        try c.encode(drumsBeat, forKey: .drumsBeat)
        try c.encode(bassEnergy, forKey: .bassEnergy)
        try c.encode(bassBand0, forKey: .bassBand0)
        try c.encode(bassBand1, forKey: .bassBand1)
        try c.encode(bassBeat, forKey: .bassBeat)
        try c.encode(otherEnergy, forKey: .otherEnergy)
        try c.encode(otherBand0, forKey: .otherBand0)
        try c.encode(otherBand1, forKey: .otherBand1)
        try c.encode(otherBeat, forKey: .otherBeat)
        try c.encode(vocalsEnergyRel, forKey: .vocalsEnergyRel)
        try c.encode(vocalsEnergyDev, forKey: .vocalsEnergyDev)
        try c.encode(drumsEnergyRel, forKey: .drumsEnergyRel)
        try c.encode(drumsEnergyDev, forKey: .drumsEnergyDev)
        try c.encode(bassEnergyRel, forKey: .bassEnergyRel)
        try c.encode(bassEnergyDev, forKey: .bassEnergyDev)
        try c.encode(otherEnergyRel, forKey: .otherEnergyRel)
        try c.encode(otherEnergyDev, forKey: .otherEnergyDev)
        try c.encode(vocalsOnsetRate, forKey: .vocalsOnsetRate)
        try c.encode(vocalsCentroid, forKey: .vocalsCentroid)
        try c.encode(vocalsAttackRatio, forKey: .vocalsAttackRatio)
        try c.encode(vocalsEnergySlope, forKey: .vocalsEnergySlope)
        try c.encode(drumsOnsetRate, forKey: .drumsOnsetRate)
        try c.encode(drumsCentroid, forKey: .drumsCentroid)
        try c.encode(drumsAttackRatio, forKey: .drumsAttackRatio)
        try c.encode(drumsEnergySlope, forKey: .drumsEnergySlope)
        try c.encode(bassOnsetRate, forKey: .bassOnsetRate)
        try c.encode(bassCentroid, forKey: .bassCentroid)
        try c.encode(bassAttackRatio, forKey: .bassAttackRatio)
        try c.encode(bassEnergySlope, forKey: .bassEnergySlope)
        try c.encode(otherOnsetRate, forKey: .otherOnsetRate)
        try c.encode(otherCentroid, forKey: .otherCentroid)
        try c.encode(otherAttackRatio, forKey: .otherAttackRatio)
        try c.encode(otherEnergySlope, forKey: .otherEnergySlope)
        try c.encode(vocalsPitchHz, forKey: .vocalsPitchHz)
        try c.encode(vocalsPitchConfidence, forKey: .vocalsPitchConfidence)
        try c.encode(drumsEnergyDevSmoothed, forKey: .drumsEnergyDevSmoothed)
        try c.encode(cachedBassProportion, forKey: .cachedBassProportion)
    }
}
