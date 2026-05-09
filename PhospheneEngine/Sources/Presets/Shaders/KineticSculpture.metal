// KineticSculpture.metal — Ray march preset: interlocking 3D lattice.
//
// A periodic lattice of three materials breathes and deforms in sync with
// audio.  Geometry is the primary audio-reactive surface; materials are
// assigned by re-evaluating sub-SDFs at the hit position.
//
// Materials:
//   Brushed Aluminum — thin three-axis bars forming the structural cage.
//   Frosted Glass    — spherical nodes at cell-centre intersections.
//   Liquid Mercury   — fat connectors that smoothly pool into the nodes.
//
// Audio routing (FeatureVector; StemFeatures now available via preamble
// forward-declarations but this preset ships with the FeatureVector
// routing that was validated when it landed — kept to preserve existing
// visual behaviour).  A future revision could switch to stems directly:
//   f.accumulated_audio_time → Z-axis twist deformation phase
//   f.sub_bass + f.bass      → Mercury opSmoothUnion radius (melt / merge)
//   f.beat_bass              → Glass node beat-pulse size accent
//
// Band-to-stem proxies used (could now be replaced with direct stems access):
//   f.sub_bass  ≈ stems.bass_energy   (20–80 Hz; same frequency range)
//   f.beat_bass ≈ stems.drums_beat    (low-frequency onset pulse)
//
// Preamble provides: sdRoundBox, sdSphere, opSmoothUnion, opUnion,
//                    opRepeat (fmod-based — ks_rep below uses round() for
//                    correct handling of negative coordinates).
//
// Pipeline: ray_march → post_process (G-buffer deferred + bloom/ACES)

// ── Lattice constant ─────────────────────────────────────────────────────────

constant float KS_CELL = 2.0f;

// ── Custom helpers (not present in ShaderUtilities) ──────────────────────────

/// Z-axis twist deformation.  ShaderUtilities only provides opTwist (Y-axis).
/// k = twist rate in radians per world-unit of Z.
static inline float3 ks_opTwistZ(float3 p, float k) {
    float ca = cos(k * p.z);
    float sa = sin(k * p.z);
    return float3(p.x * ca - p.y * sa,
                  p.x * sa + p.y * ca,
                  p.z);
}

/// Infinite domain repetition via round() — handles negative coordinates
/// correctly.  opRepeat (fmod-based) returns incorrect results when
/// p + 0.5*c is negative, breaking lattice symmetry behind the camera.
static inline float3 ks_rep(float3 p, float c) {
    return p - c * round(p / c);
}

// ── Material-specific sub-SDFs ───────────────────────────────────────────────
// These combine preamble primitives (sdRoundBox / sdSphere / opSmoothUnion)
// into the three recognisable material shapes.

/// Three axis-aligned rounded bars forming the Brushed Aluminum structural cage.
static inline float ks_sdAluminumBars(float3 p) {
    float dX = sdRoundBox(p, float3(0.88f, 0.065f, 0.065f), 0.012f);
    float dY = sdRoundBox(p, float3(0.065f, 0.88f, 0.065f), 0.012f);
    float dZ = sdRoundBox(p, float3(0.065f, 0.065f, 0.88f), 0.012f);
    return min(min(dX, dY), dZ);
}

/// Frosted Glass sphere at the cell-centre intersection node.
/// pulseMag adds a transient size offset driven by beat_bass (0 at rest).
static inline float ks_sdGlassNode(float3 p, float pulseMag) {
    return sdSphere(p, 0.17f + pulseMag);
}

/// Liquid Mercury connectors: three fat bars smoothly unioned into a central
/// pool.  sminK controls the melt radius — larger = more fluid, bass-driven.
static inline float ks_sdMercury(float3 p, float sminK) {
    float dX    = sdRoundBox(p, float3(0.70f, 0.09f, 0.09f), 0.018f);
    float dY    = sdRoundBox(p, float3(0.09f, 0.70f, 0.09f), 0.018f);
    float dZ    = sdRoundBox(p, float3(0.09f, 0.09f, 0.70f), 0.018f);
    float dBars = min(min(dX, dY), dZ);
    float dPool = sdSphere(p, 0.22f);
    return opSmoothUnion(dBars, dPool, sminK);
}

// ── Scene SDF ────────────────────────────────────────────────────────────────

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems) {
    // 1. Z-axis twist driven by accumulated audio time (breathes with energy).
    //    Rate 0.06 rad per unit keeps the deformation gentle but perceptible.
    float twistK = f.accumulated_audio_time * 0.06f;
    float3 tp    = ks_opTwistZ(p, twistK);

    // 2. Infinite periodic repetition — cell spacing KS_CELL = 2.0 units.
    float3 pr = ks_rep(tp, KS_CELL);

    // 3. Beat accent: glass nodes briefly swell on bass onset, then decay.
    float pulse = f.beat_bass * 0.055f;

    // 4. Mercury melt radius: continuous bass band (Layer 1 of the audio
    //    data hierarchy) drives the smooth-union baseline; bass deviation
    //    (D-026) adds the kick-onset accent on top. The earlier formula
    //    `sub_bass * 0.28 + bass * 0.10` weighted an unset / unreliable
    //    sub-band (`f.sub_bass`) with an arbitrary 2.8× factor and is now
    //    superseded by the deviation-aware mix below. (QR.1, D-079)
    //    Range:
    //      silence  (bass=0,   bass_dev=0)   → 0.06
    //      steady   (bass=0.5, bass_dev=0)   → 0.14
    //      kick     (bass=0.8, bass_dev=0.6) → 0.218
    //    The accent component is small (0.05·bass_dev) so it stays within
    //    the audio-data-hierarchy "beat ≤ 2× continuous" rule, while still
    //    scaling proportionally across mix densities.
    float sminK = 0.06f + f.bass * 0.16f + f.bass_dev * 0.05f;

    // 5. Evaluate all three material primitives in cell-local space.
    float dAlum  = ks_sdAluminumBars(pr);
    float dGlass = ks_sdGlassNode(pr, pulse);
    float dMerc  = ks_sdMercury(pr, sminK);

    // 6. Liquid metal merges into glass node; aluminum cage stays structural.
    float dLiquid = opSmoothUnion(dMerc, dGlass, sminK * 0.5f);

    return opUnion(dAlum, dLiquid);
}

// ── Scene Material ───────────────────────────────────────────────────────────

void sceneMaterial(float3 p,
                   int matID,
                   constant FeatureVector& f,
                   constant SceneUniforms& s,
                   constant StemFeatures& stems,
                   thread float3& albedo,
                   thread float& roughness,
                   thread float& metallic,
                   thread int& outMatID,
                   constant LumenPatternState& lumen) {
    // outMatID stays at the caller's default (0 = standard dielectric); the
    // lattice's three materials all dispatch through Cook-Torrance.
    (void)outMatID;
    // `lumen` (LM.2 / D-LM-buffer-slot-8) is the trailing slot-8 buffer used
    // by Lumen Mosaic. Non-Lumen presets ignore it.
    (void)lumen;
    // Re-evaluate sub-SDFs at the hit position to determine material.
    // Twist correction is omitted: accumulated_audio_time is unavailable
    // here, but the twist is slow enough that boundary error is imperceptible.
    float3 pr = ks_rep(p, KS_CELL);

    float dAlum  = ks_sdAluminumBars(pr);
    float dGlass = ks_sdGlassNode(pr, 0.0f);
    float dMerc  = ks_sdMercury(pr, 0.10f); // fixed k for stable boundary detection

    if (dGlass <= dAlum && dGlass <= dMerc) {
        // Frosted Glass — ice-blue, moderately rough, low metallic.
        // Drums beat pulse is expressed geometrically (node expansion in sceneSDF).
        // Direct vocal roughness modulation unavailable (StemFeatures not in scope).
        albedo    = float3(0.80f, 0.88f, 0.96f);
        roughness = 0.22f;
        metallic  = 0.04f;
    } else if (dMerc < dAlum) {
        // Liquid Mercury — near-mirror silver, fully metallic.
        // Bass-driven melt geometry is handled in sceneSDF via sminK.
        albedo    = float3(0.80f, 0.80f, 0.82f);
        roughness = 0.04f;
        metallic  = 1.0f;
    } else {
        // Brushed Aluminum — warm mid-grey, high metallic, polished finish.
        // Vocal roughness modulation (spec: vocals_energy → lower roughness)
        // is architecturally unavailable; using a fixed polished value (0.20)
        // that approximates high-vocal reflectivity.
        albedo    = float3(0.71f, 0.72f, 0.76f);
        roughness = 0.20f;
        metallic  = 0.92f;
    }
}
