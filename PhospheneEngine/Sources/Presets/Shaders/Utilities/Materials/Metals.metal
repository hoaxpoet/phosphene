// Metals.metal — Metallic surface material recipes.
//
// Recipes: mat_polished_chrome, mat_brushed_aluminum, mat_gold, mat_copper,
//          mat_ferrofluid.
//
// All recipes follow the cookbook convention: return MaterialResult; callers
// unpack into the engine's sceneMaterial() out-parameter signature.
// See MaterialResult.metal for the composition pattern.
//
// Reference: SHADER_CRAFT.md §4.1, §4.2, §4.6, §4.10, §4.11
//
// Depends on: Noise tree (fbm8, worley_fbm), Geometry (hex_tile_uv from HexTile).
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// ─── 4.1 Polished chrome ─────────────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.1 (verbatim transcription)

/// Polished chrome: near-mirror metallic surface with subtle streak variation.
///
/// `wp` = world-space position. `n` = world-space surface normal.
///
/// Caller responsibilities: nearby geometry / IBL environment provides visible
/// reflections. Looks flat in a bare scene without environmental variation.
MaterialResult mat_polished_chrome(float3 wp, float3 n) {
    MaterialResult m;
    m.albedo = float3(0.95);
    m.roughness = 0.03;
    m.metallic = 1.0;
    // Anisotropic streak via tangent-aligned roughness modulation
    float streak = fbm8(wp * 40.0);
    m.roughness += 0.04 * streak;   // break up uniformity
    m.normal = n;
    m.emission = float3(0.0);
    return m;
}

// ─── 4.2 Brushed aluminum ────────────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.2 (verbatim transcription)

/// Brushed aluminum: directional streak anisotropy with normal perturbation.
///
/// `brush_dir` = world-space unit vector along the brush direction.
///
/// Caller responsibilities: supply a meaningful brush_dir. For horizontal
/// brushing, float3(1, 0, 0) is typical.
MaterialResult mat_brushed_aluminum(float3 wp, float3 n, float3 brush_dir) {
    MaterialResult m;
    m.albedo = float3(0.91, 0.92, 0.93);
    // Brush streaks: anisotropic roughness along brush_dir
    float streak_coord = dot(wp, brush_dir);
    float streak = fract(streak_coord * 300.0);
    streak = abs(streak - 0.5);   // triangle wave
    m.roughness = 0.18 + 0.08 * streak;  // 0.10–0.26 striped
    m.metallic = 1.0;
    // Detail normal perturbation along brush direction
    float3 perp = normalize(cross(n, brush_dir));
    m.normal = normalize(n + perp * 0.02 * streak);
    m.emission = float3(0.0);
    return m;
}

// ─── 4.10 Gold ───────────────────────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.10 (expanded from paragraph form)
// Expanded from SHADER_CRAFT.md §4.10 paragraph form

/// Gold: warm yellow metallic with fine scratch normal variation.
///
/// Caller responsibilities: none. Exposure should be calibrated for IBL
/// at scene_ambient ≈ 0.06 — gold blows out at ambient > 0.15.
MaterialResult mat_gold(float3 wp, float3 n) {
    MaterialResult m;
    m.albedo   = float3(1.0, 0.78, 0.34);
    m.roughness = 0.15;
    m.metallic  = 1.0;
    // Fine scratch fBM perturbs the normal at 50× scale, amplitude 0.03.
    // Breaks the "liquid gold" look into something with surface history.
    float3 scratch = float3(
        fbm8(wp * 50.0),
        fbm8(wp * 50.0 + float3(7.3, 0.0, 0.0)),
        fbm8(wp * 50.0 + float3(0.0, 3.7, 0.0))
    );
    m.normal   = normalize(n + (scratch - 0.5) * 0.03);
    m.emission = float3(0.0);
    return m;
}

// ─── 4.11 Copper with patina ─────────────────────────────────────────────────
// Source: SHADER_CRAFT.md §4.11 (expanded from paragraph form)
// Expanded from SHADER_CRAFT.md §4.11 paragraph form

/// Copper with verdigris patina: warm copper on peaks, teal patina in crevices.
///
/// Caller responsibilities: provide an ambient occlusion value in `ao` ∈ [0, 1].
/// AO = 0 means fully occluded (crevice → more patina);
/// AO = 1 means fully exposed (peak → clean copper).
/// If AO is unavailable, pass 0.5 for a mid-blend.
MaterialResult mat_copper(float3 wp, float3 n, float ao) {
    MaterialResult m;

    // Base copper (exposed peaks)
    float3 copper_albedo  = float3(0.95, 0.60, 0.36);
    float  copper_rough   = 0.25;
    float  copper_metal   = 1.0;

    // Verdigris patina (crevices, aged surfaces)
    float3 patina_albedo  = float3(0.15, 0.55, 0.45);
    float  patina_rough   = 0.70;
    float  patina_metal   = 0.0;

    // Patina lives in Worley-driven pits; AO shifts it toward crevices.
    // worley_fbm mixes fbm8 (~[-1,1]) and Worley F1 (~[0,0.4]) with weight 0.35;
    // effective range ~[-0.65, 0.79]. Threshold at 0.1–0.3 captures upper ~30%.
    float w = worley_fbm(wp * 2.0);
    float patina_mask = smoothstep(0.10, 0.30, w);
    patina_mask *= (1.0 - ao);   // more patina in occluded regions

    m.albedo    = mix(copper_albedo, patina_albedo, patina_mask);
    m.roughness = mix(copper_rough,  patina_rough,  patina_mask);
    m.metallic  = mix(copper_metal,  patina_metal,  patina_mask);
    m.normal    = n;
    m.emission  = float3(0.0);
    return m;
}

// ─── 4.6 Ferrofluid (Rosensweig spikes) ─────────────────────────────────────
// Source: SHADER_CRAFT.md §4.6 (verbatim transcription — material portion)

/// Ferrofluid material: near-black oil-based fluid with near-mirror metallic response.
///
/// Caller responsibilities:
///   - `field_strength` ∈ [0, 1]: magnetic field strength. Route from
///     `stems.bass_energy_dev` for bass-driven spike height in the preset's SDF.
///   - The SDF helper `ferrofluid_field(p, field_strength, t)` and
///     `sdf_ferrofluid(p, field_strength, t)` are defined below for reference
///     but are preset-level SDF concerns, not part of this material function.
///
/// See SHADER_CRAFT.md §4.6 for the full SDF recipe.
MaterialResult mat_ferrofluid(float3 wp, float3 n) {
    MaterialResult m;
    // Deep black with hint of blue in highlights (magnetic fluid is oil-based, dark)
    m.albedo    = float3(0.02, 0.03, 0.05);
    m.roughness = 0.08;   // near-mirror
    m.metallic  = 1.0;    // F0 behaves metallic
    // Anisotropy along flow direction: if we have one
    m.normal    = n;
    m.emission  = float3(0.0);
    return m;
}

// ─── Ferrofluid SDF helpers (preset-level, companion to mat_ferrofluid) ──────
// Source: SHADER_CRAFT.md §4.6 (verbatim transcription — SDF portion)
// These helpers are documented here for presets building a Ferrofluid scene.
// They are SDF primitives, not material functions. Presets call them from sceneSDF().

/// Hexagonal spike height field for ferrofluid Rosensweig instability.
///
/// `field_strength` = caller-supplied magnetic intensity (route from bass_energy_dev).
/// `t`              = accumulated audio time (from FeatureVector.accumulated_audio_time).
static inline float ferrofluid_field(float3 p, float field_strength, float t) {
    // Voronoi close-pack of spike centres with noise-driven defects.
    float2 xz = p.xz;
    VoronoiResult v = voronoi_f1f2(xz, 4.0);
    // Per-cell jitter from fBM seeded by cell centre.
    float jitter = fbm8(float3(v.pos * 2.0, 0.0)) * 0.3;
    float d = v.f1 + jitter * 0.05;
    // Conical spike profile with bell-curve falloff.
    float spike = exp(-d * d * 40.0);
    // Time-animated per-cell phase from cell hash.
    float cellPhase = float(v.id & 0xFFFF) * (6.283185 / float(0xFFFF));
    spike *= 0.5 + 0.5 * sin(t * 0.8 + cellPhase);
    return spike * field_strength * 0.15;
}

/// Signed-distance function for the ferrofluid surface.
/// `p.y` relative to base plane; negative below the surface.
static inline float sdf_ferrofluid(float3 p, float field_strength, float t) {
    float base_y = 0.0;
    float spikes  = ferrofluid_field(p, field_strength, t);
    return p.y - (base_y + spikes);
}
