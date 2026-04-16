// VolumetricLithograph.metal — Psychedelic linocut-inspired terrain landscape.
//
// An infinite, slowly morphing audio-reactive landscape rendered with a
// printmaking aesthetic: bimodal materials separated by a razor-sharp
// ridge-line, with saturated metallic peaks that cycle through a Quilez
// cosine palette over time + valence + spatial position.  Drum onsets
// flare the peak palette into HDR bloom; the ridge-line itself reads as
// a thin emissive seam where the cut goes.
//
// v3.1 (session 2026-04-16T17-33-10Z v2 diagnostic) tuned three palette
// parameters that v3 left untouched but the data showed were wrong:
//   - Palette rotation rate 0.04 → 0.15:  over 64s of playback, audioTime
//     accumulated only to 5.0 units so the palette rotated 20% of a cycle
//     total.  0.15 gives one full rotation per ~7s of active audio.
//   - Spatial hue spread 0.45 → 0.9:  peak noise range is [0.55, 1.0], so
//     0.45 contribution capped at 0.20 — all peaks in a frame looked the
//     same hue.  0.9 doubles per-peak variation.
//   - Valley brightness 0.08 → 0.15:  v3 valleys were so dim the
//     valence-tinted IBL ambient dominated and they read as uniform dark
//     brown.  0.15 lets the complementary palette colour register.
//
// v3 design rationale (session 2026-04-16T16-44-51Z + v2 visual review):
//   v2 (palette + calmer motion) over-corrected — beat response was
//   inert on energetic music, and scene_fog=0 actually produced MAX
//   fog due to a bug in the shared `makeSceneUniforms` fallback.  v3:
//   - Fixed shared helper so `scene_fog: 0` truly disables fog.
//   - Rebalanced beat response: `pow(f.beat_bass, 1.2) * 1.5` replaces
//     v2's `pow(1.5) * 0.7`; palette flare × 1.5 (was × 0.6); ridge
//     strobe × (1.4 + beat × 2.0); added 0.03 coverage-expansion shift
//     (v1 was 0.18 which flickered; v2 was 0 which was dead).
//   - Added a small transient kick to terrain amplitude in sceneSDF
//     (`f.beat_bass * 0.35`) so the landscape breathes on kicks.
// v2 changes preserved:
//   - Attenuated bands (`f.bass_att + 0.4 * f.mid_att`) for slow-flowing
//     baseline amplitude (not the primary driver v1 had).
//   - IQ cosine palette from ShaderUtilities.metal:576 drives peak
//     albedo by noise position + audio time + valence.
//   - `sqrt(f.mid) * 1.6` replaces `f.treble * 1.4` for "other" polish.
//
// Audio routing (FeatureVector — StemFeatures unavailable in
// sceneSDF/sceneMaterial; preamble forward-declarations omit it):
//   s.sceneParamsA.x  → terrain phase (accumulated audio time)
//   f.bassAtt+midAtt  → vertical displacement amplitude (slow)
//   f.beat_bass       → palette saturation/brightness flare
//   f.valence         → palette hue offset (mood)
//   f.mid (sqrt-boost)→ peak roughness polish ("other" stem proxy)
//
// D-019 stem-routing fallback: stems are not in scope here, so all
// stem-driven parameters fall back to FeatureVector — equivalent to
// the smoothstep(0.02, 0.06, totalStemEnergy) warmup mix at zero
// stem energy.  See KineticSculpture.metal for the same constraint.
//
// Linocut materials (3 strata):
//   Valley   : palette-tinted ultra-dark   (albedo ≈ palette × 0.08)
//   Ridge    : razor-thin emissive seam    (albedo = 1 × peakHue, low metal)
//   Peak     : saturated polished metal    (albedo = peakHue, metallic = 1)
//
// Pipeline: ray_march → post_process (G-buffer deferred + bloom/ACES).
// SSGI is intentionally skipped to preserve harsh, high-contrast shadows.

// ── Constants ─────────────────────────────────────────────────────────────

constant float VL_TERRAIN_BASE_Y   = 0.0f;   // resting terrain height (world Y)
constant float VL_NOISE_FREQUENCY  = 0.12f;  // larger features than v1 (0.18)
constant float VL_NOISE_TIME_SCALE = 0.06f;  // slower morph than v1 (0.15)
constant float VL_DISP_SILENT_AMP  = 0.6f;   // baseline so terrain reads in silence
constant float VL_DISP_AUDIO_AMP   = 1.8f;   // tamer than v1 (3.4)
constant int   VL_FBM_OCTAVES      = 5;

// SDF Lipschitz scaling: heightfield is not Euclidean on slopes.
constant float VL_SDF_STEP_SCALE   = 0.6f;

// Linocut edge windows.  Tighter than v1 (0.55, 0.72) — sharper boundary.
constant float VL_PEAK_LO          = 0.50f;  // valley → peak transition start
constant float VL_PEAK_HI          = 0.55f;  // valley → peak transition end
constant float VL_RIDGE_INNER      = 0.495f; // ridgeline lower edge
constant float VL_RIDGE_OUTER      = 0.51f;  // ridgeline upper edge

// ── Helpers ───────────────────────────────────────────────────────────────

/// 3D fBm sample [0,1] at world XZ, swept by audio phase along Y noise axis.
static inline float vl_terrainNoise(float3 worldP, float audioPhase) {
    float3 noiseP = float3(worldP.x * VL_NOISE_FREQUENCY,
                           audioPhase * VL_NOISE_TIME_SCALE,
                           worldP.z * VL_NOISE_FREQUENCY);
    return fbm3D(noiseP, VL_FBM_OCTAVES);
}

/// Heightfield surface height at world XZ.
static inline float vl_heightAt(float3 worldP, float audioPhase, float audioAmp) {
    float n   = vl_terrainNoise(worldP, audioPhase);
    float amp = VL_DISP_SILENT_AMP + audioAmp * VL_DISP_AUDIO_AMP;
    return VL_TERRAIN_BASE_Y + (n - 0.5f) * 2.0f * amp;
}

/// Inigo Quilez cosine-palette tint for the given phase.  Cyan → magenta →
/// yellow rotation via the standard (0, 1/3, 2/3) phase-shift triad.
static inline float3 vl_palette(float t) {
    return palette(t,
                   float3(0.50f, 0.50f, 0.50f),   // base midtone
                   float3(0.50f, 0.50f, 0.50f),   // amplitude
                   float3(1.00f, 1.00f, 1.00f),   // 1 cycle per t-unit
                   float3(0.00f, 0.33f, 0.67f));  // RGB phase shift
}

// ── Scene SDF ─────────────────────────────────────────────────────────────

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s) {
    float audioPhase = s.sceneParamsA.x;                            // accumulated audio time
    // Slow base: attenuated bands → slow-flowing peaks, not frame-by-frame boil.
    float slowAmp    = clamp(f.bass_att + 0.4f * f.mid_att, 0.0f, 1.5f);
    // Transient kick: adds a short vertical punch on each bass onset (accent, not primary).
    float kick       = clamp(f.beat_bass, 0.0f, 1.0f) * 0.35f;
    float audioAmp   = clamp(slowAmp + kick, 0.0f, 2.0f);
    float h          = vl_heightAt(p, audioPhase, audioAmp);
    return (p.y - h) * VL_SDF_STEP_SCALE;
}

// ── Scene Material ────────────────────────────────────────────────────────

void sceneMaterial(float3 p,
                   int matID,
                   constant FeatureVector& f,
                   constant SceneUniforms& s,
                   thread float3& albedo,
                   thread float& roughness,
                   thread float& metallic) {
    float audioPhase = s.sceneParamsA.x;
    float n          = vl_terrainNoise(p, audioPhase); // [0,1]

    // ── D-019 stem-routing fallback (StemFeatures not in scope) ─────────
    // Drum-beat fallback: pow(f.beat_bass, 1.2) × 1.5 gives a responsive
    // curve — at beat_bass=0.5 → 0.65; at 0.7 → saturates to 1.0. v2's
    // pow(1.5) × 0.7 was too conservative; real-music p90 of 0.66 only
    // produced a 0.37 boost which was visually inert on energetic music.
    float drumsBeatFB = clamp(pow(max(f.beat_bass, 0.0f), 1.2f) * 1.5f, 0.0f, 1.0f);

    // "Other" stem proxy: sqrt(f.mid) * 1.6.  f.mid (250 Hz–4 kHz)
    // overlaps the actual "other" stem band almost exactly.  AGC keeps
    // f.mid in roughly [0, 0.08] for real music — sqrt boost lifts the
    // 0.016 mean to ~0.20, producing a useful polish range.
    float otherFB = clamp(sqrt(max(f.mid, 0.0f)) * 1.6f, 0.0f, 1.0f);

    // ── Three-stratum classification ────────────────────────────────────
    //   peakSelect    = matte-valley → polished-peak transition (sharp)
    //   ridgeSelect   = thin emissive seam at the boundary (cut-paper line)
    //
    // Beat adds a small coverage shift (−0.03 window displacement) so
    // peaks briefly expand across the terrain on kicks — much less than
    // v1's 0.18 shift (which caused the boundary to flicker every frame).
    float beatShift   = drumsBeatFB * 0.03f;
    float peakSelect  = smoothstep(VL_PEAK_LO - beatShift,
                                    VL_PEAK_HI - beatShift, n);
    float ridgeSelect =
        smoothstep(VL_RIDGE_INNER - beatShift,
                    (VL_RIDGE_INNER + VL_RIDGE_OUTER) * 0.5f - beatShift, n)
      * (1.0f - smoothstep((VL_RIDGE_INNER + VL_RIDGE_OUTER) * 0.5f - beatShift,
                            VL_RIDGE_OUTER - beatShift, n));

    // ── Psychedelic palette (the headline change) ───────────────────────
    // Phase = local noise × 0.9  (wide spatial hue variation across peaks;
    //                              v3 had 0.45 which clamped peak variation
    //                              to ~20% of a cycle — all peaks looked
    //                              the same colour in a single frame)
    //       + audioTime × 0.15   (full cycle every ~7s of active audio;
    //                              v3 had 0.04 which only rotated 20% of
    //                              a cycle over 64s — visually static)
    //       + valence × 0.25     (mood shifts the palette window —
    //                              unchanged, gives per-track hue identity)
    float palettePhase = n * 0.9f + audioPhase * 0.15f + f.valence * 0.25f;
    float3 peakHue   = vl_palette(palettePhase);
    // Valley brightness × 0.15 (v3 had × 0.08 which the valence-tinted
    // IBL ambient drowned out — valleys read as uniform dark brown).
    float3 valleyHue = vl_palette(palettePhase + 0.5f) * 0.15f;

    // Beat flare: peaks push into HDR (bloom in post_process amplifies);
    // ACES at composite (RayMarch.metal:352–355) handles the over-bright
    // values gracefully.  v2 used 0.6 which was too timid for energetic
    // music — ACES squashed the boost back into SDR before bloom.  1.5
    // gives a clearly visible flare (up to 2.5× peak albedo at full beat).
    float beatBoost = 1.0f + drumsBeatFB * 1.5f;
    peakHue *= beatBoost;

    // ── Stratum materials ──────────────────────────────────────────────
    // Valley: palette-tinted near-black, pure dielectric, fully rough.
    float3 valleyAlbedo = valleyHue;
    float  valleyRough  = 1.0f;
    float  valleyMetal  = 0.0f;

    // Peak: saturated polished metal.  "other" stem polishes roughness.
    // Albedo IS F0 for metals (RayMarch.metal:239) — saturated colors
    // produce saturated reflections off the IBL prefilter.
    float3 peakAlbedo = peakHue;
    float  peakRough  = mix(0.20f, 0.08f, otherFB);
    float  peakMetal  = 1.0f;

    // Mix valley → peak first (smooth bimodal base).
    albedo    = mix(valleyAlbedo, peakAlbedo, peakSelect);
    roughness = mix(valleyRough,  peakRough,  peakSelect);
    metallic  = mix(valleyMetal,  peakMetal,  peakSelect);

    // Ridgeline: overlay a thin dielectric seam at the cut, tinted by
    // the same palette at high brightness with an additional beat strobe
    // so the cut-line itself pulses visibly at every kick.  Low metallic
    // reads as luminous-paint rather than chrome line; low roughness
    // keeps the seam tight.
    float  ridgeStrobe = 1.4f + drumsBeatFB * 2.0f;
    float3 ridgeAlbedo = peakHue * ridgeStrobe;       // very bright on beat
    float  ridgeRough  = 0.30f;
    float  ridgeMetal  = 0.10f;
    albedo    = mix(albedo,    ridgeAlbedo, ridgeSelect);
    roughness = mix(roughness, ridgeRough,  ridgeSelect);
    metallic  = mix(metallic,  ridgeMetal,  ridgeSelect);
}
