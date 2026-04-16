// VolumetricLithograph.metal — Psychedelic linocut-inspired terrain landscape.
//
// An infinite, slowly morphing audio-reactive landscape rendered with a
// printmaking aesthetic: bimodal materials separated by a razor-sharp
// ridge-line, with saturated metallic peaks that cycle through a Quilez
// cosine palette over time + valence + spatial position.  Drum onsets
// flare the peak palette into HDR bloom; the ridge-line itself reads as
// a thin emissive seam where the cut goes.
//
// v2 design rationale (session 2026-04-16T16-44-51Z, Love Rehab):
//   - Beat fallback `max(beat_bass, beat_mid, beat_composite)` was
//     saturated 86% of the time → boundary flickered every frame.
//     Replaced with selective `pow(f.beat_bass, 1.5) * 0.7`.
//   - Continuous bands `f.bass + f.mid` stacked with beat shifts
//     produced 3 simultaneously moving drivers → switched to attenuated
//     `f.bassAtt + 0.4 * f.midAtt` for slow-flowing terrain.
//   - "Other" stem proxy `f.treble * 1.4` was effectively 0 in real
//     music → switched to `sqrt(f.mid) * 1.6` (mid covers actual
//     250 Hz–4 kHz "other" range).
//   - Pure-grayscale palette → IQ cosine palette driven by
//     terrain-noise position + audio-time + valence.
//   - scene_fog killed (linocut has no aerial perspective; was
//     producing a foggy band across the upper third of the frame).
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
    // Attenuated bands → slow-flowing peaks rather than boil-on-every-kick.
    float audioAmp   = clamp(f.bass_att + 0.4f * f.mid_att, 0.0f, 1.5f);
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
    // Drum-beat fallback: pow(f.beat_bass, 1.5) so only strong kicks
    // register.  Real music data: f.beat_bass median 0.10, p99 1.0;
    // pow brings the median down to ~0.03, leaving p99 at 1.0 — only
    // genuine transients punch through.
    float drumsBeatFB = clamp(pow(max(f.beat_bass, 0.0f), 1.5f) * 0.7f, 0.0f, 1.0f);

    // "Other" stem proxy: sqrt(f.mid) * 1.6.  f.mid (250 Hz–4 kHz)
    // overlaps the actual "other" stem band almost exactly.  AGC keeps
    // f.mid in roughly [0, 0.08] for real music — sqrt boost lifts the
    // 0.016 mean to ~0.20, producing a useful polish range.
    float otherFB = clamp(sqrt(max(f.mid, 0.0f)) * 1.6f, 0.0f, 1.0f);

    // ── Three-stratum classification ────────────────────────────────────
    //   peakSelect    = matte-valley → polished-peak transition (sharp)
    //   ridgeSelect   = thin emissive seam at the boundary (cut-paper line)
    float peakSelect  = smoothstep(VL_PEAK_LO, VL_PEAK_HI, n);
    float ridgeSelect =
        smoothstep(VL_RIDGE_INNER, (VL_RIDGE_INNER + VL_RIDGE_OUTER) * 0.5f, n)
      * (1.0f - smoothstep((VL_RIDGE_INNER + VL_RIDGE_OUTER) * 0.5f, VL_RIDGE_OUTER, n));

    // ── Psychedelic palette (the headline change) ───────────────────────
    // Phase = local noise × 0.45  (spatial hue variation across terrain)
    //       + audioTime × 0.04     (slow whole-scene cycle)
    //       + valence × 0.25       (mood shifts the palette window)
    float palettePhase = n * 0.45f + audioPhase * 0.04f + f.valence * 0.25f;
    float3 peakHue   = vl_palette(palettePhase);
    float3 valleyHue = vl_palette(palettePhase + 0.5f) * 0.08f; // complementary, deep

    // Beat flare: peaks push into HDR (bloom in post_process amplifies);
    // ACES at composite (RayMarch.metal:352–355) handles the over-bright
    // values gracefully.  Ridge gets the same boost so the seam strobes.
    float beatBoost = 1.0f + drumsBeatFB * 0.6f;
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
    // the same palette but at maximum brightness × beat boost.  Low
    // metallic so it reads as luminous-paint rather than chrome line.
    float3 ridgeAlbedo = peakHue * 1.4f;             // brighter than peak
    float  ridgeRough  = 0.35f;                       // catches a soft halo
    float  ridgeMetal  = 0.10f;                       // mostly dielectric
    albedo    = mix(albedo,    ridgeAlbedo, ridgeSelect);
    roughness = mix(roughness, ridgeRough,  ridgeSelect);
    metallic  = mix(metallic,  ridgeMetal,  ridgeSelect);
}
