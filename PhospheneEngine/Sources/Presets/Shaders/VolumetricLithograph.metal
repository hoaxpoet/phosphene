// VolumetricLithograph.metal — Tactile linocut-inspired terrain landscape.
//
// A continuously evolving infinite landscape rendered with a stark linocut
// aesthetic: deep ultra-matte black valleys and razor-bright reflective
// peaks. The topography flows with accumulated audio time, peaks swell
// with bass + mid energy, and drum onsets expand the bright-ridge region
// to give a sensation of contrast spiking on transients.
//
// Audio routing (FeatureVector — StemFeatures unavailable in sceneSDF /
// sceneMaterial; preamble forward-declarations do not carry that struct):
//   s.sceneParamsA.x         → terrain phase (accumulated audio time)
//   f.bass + f.mid           → vertical displacement amplitude
//   f.beat_bass / f.beat_mid → ridge contrast / coverage pulse
//   f.beat_composite         → cross-genre fallback for snare-driven tracks
//   f.treble                 → metallic sheen (proxy for "other" stem)
//
// D-019 stem-routing fallback: stems would normally drive drums_beat
// (peak coverage pulse) and other_energy (metallic sheen).  Those struct
// fields are not in scope here, so the implementation uses FeatureVector
// fallbacks directly — equivalent to the smoothstep(0.02, 0.06,
// totalStemEnergy) warmup mix evaluated at totalStemEnergy = 0, which
// selects fallback values exclusively.  See CLAUDE.md failed-approach
// #26 for why we use max(beat_bass, beat_mid, beat_composite) rather
// than beat_bass alone.
//
// Linocut aesthetic — bimodal materials, almost no midtones:
//   Valleys (low noise) → albedo = 0.0, roughness = 1.0, metallic = 0.0
//   Peaks   (high noise) → albedo = 1.0, roughness ≈ 0.06–0.18, metallic = 1.0
//
// Pipeline: ray_march → post_process (G-buffer deferred + bloom/ACES).
// SSGI is intentionally skipped to preserve the harsh, high-contrast
// shadows that define the printmaking aesthetic.
//
// Preamble provides: fbm3D, sdPlane (unused — heightfield SDF is computed
// directly), smoothstep, mix, clamp.

// ── Constants ─────────────────────────────────────────────────────────────

constant float VL_TERRAIN_BASE_Y   = 0.0f;   // resting terrain height (world Y)
constant float VL_NOISE_FREQUENCY  = 0.18f;  // horizontal noise scale (1/world unit)
constant float VL_NOISE_TIME_SCALE = 0.15f;  // noise sweep rate per accumulated-audio second
constant float VL_DISP_SILENT_AMP  = 0.6f;   // baseline so terrain reads in silence
constant float VL_DISP_AUDIO_AMP   = 3.4f;   // additional audio-driven amplitude
constant int   VL_FBM_OCTAVES      = 5;      // matches fbm3D default for visual richness

// SDF Lipschitz scaling.  The heightfield (p.y - h) is not a true Euclidean
// SDF on slopes, so we shrink the step to keep the marcher from overshooting
// steep ridges.  0.6 is conservative enough for the chosen amplitude/freq.
constant float VL_SDF_STEP_SCALE   = 0.6f;

// ── Helpers ───────────────────────────────────────────────────────────────

/// 3D fBm sample at world XZ, swept along the Y noise axis by audio phase.
/// Output is roughly [0, 1] (fbm3D is built from value-noise hashes that
/// return [0, 1]).  Passing audioPhase as the noise Y means topography
/// continuously morphs rather than scrolling in a single direction.
static inline float vl_terrainNoise(float3 worldP, float audioPhase) {
    float3 noiseP = float3(worldP.x * VL_NOISE_FREQUENCY,
                           audioPhase * VL_NOISE_TIME_SCALE,
                           worldP.z * VL_NOISE_FREQUENCY);
    return fbm3D(noiseP, VL_FBM_OCTAVES);
}

/// Heightfield surface height at world XZ.  audioAmp scales the
/// peak-to-trough range so the landscape swells with bass + mid energy.
static inline float vl_heightAt(float3 worldP, float audioPhase, float audioAmp) {
    float n   = vl_terrainNoise(worldP, audioPhase);
    float amp = VL_DISP_SILENT_AMP + audioAmp * VL_DISP_AUDIO_AMP;
    // Centre noise around 0 so the terrain sits on VL_TERRAIN_BASE_Y on average.
    return VL_TERRAIN_BASE_Y + (n - 0.5f) * 2.0f * amp;
}

// ── Scene SDF ─────────────────────────────────────────────────────────────

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s) {
    float audioPhase = s.sceneParamsA.x;                   // accumulated audio time
    float audioAmp   = clamp(f.bass + f.mid, 0.0f, 2.5f);  // peak swell driver
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
    // Recompute the underlying noise sample for material classification.
    // Using the noise t directly (rather than reconstructed height / amp)
    // keeps the boundary stable when audio amplitude changes — peak
    // regions stay where they are spatially, only their elevation flexes.
    float audioPhase = s.sceneParamsA.x;
    float n          = vl_terrainNoise(p, audioPhase);

    // ── D-019 stem-routing fallback (StemFeatures not in scope) ─────────
    // Drum-beat fallback: max across bass/mid/composite onset bands so
    // snare-driven tracks register alongside kick-driven ones (CLAUDE.md
    // failed-approach #26).
    float drumsBeatFB = max(f.beat_bass, max(f.beat_mid, f.beat_composite));

    // "Other" stem fallback: treble is the closest single-band proxy for
    // the 250 Hz–4 kHz overlapping range of the "other" stem.  Boosted
    // 1.4× because real-music treble after AGC sits low (≈0.01–0.05).
    float otherFB = clamp(f.treble * 1.4f, 0.0f, 1.0f);

    // ── Peak/valley classification ─────────────────────────────────────
    // Sharp smoothstep edges deliberately pinched so the boundary reads
    // as a printed line — the linocut signature is the abrupt transition.
    // On beat, the edges shift down (lo = 0.55 → ~0.41, hi = 0.72 → ~0.58)
    // so the bright peak coverage swells across the topography.
    float beatExpand = drumsBeatFB * 0.18f;
    float lo         = 0.55f - beatExpand;
    float hi         = 0.72f - beatExpand;
    float peakSelect = smoothstep(lo, hi, n);

    // ── Bimodal materials ──────────────────────────────────────────────
    // Valley: total absorption.  Albedo 0 means no diffuse bounce and no
    // specular tint; the deferred lighting pass returns nothing here.
    float3 valleyAlbedo = float3(0.0f);
    float  valleyRough  = 1.0f;
    float  valleyMetal  = 0.0f;

    // Peak: pure-white reflective metal.  Roughness sharpens further when
    // "other" stem (treble proxy) energy is high — the more harmonic
    // content present, the more polished the ridges read.
    float3 peakAlbedo = float3(1.0f);
    float  peakRough  = mix(0.18f, 0.06f, otherFB);
    float  peakMetal  = 1.0f;

    albedo    = mix(valleyAlbedo, peakAlbedo, peakSelect);
    roughness = mix(valleyRough,  peakRough,  peakSelect);
    metallic  = mix(valleyMetal,  peakMetal,  peakSelect);
}
