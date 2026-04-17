// VolumetricLithograph.metal — Psychedelic linocut-inspired terrain landscape.
//
// An infinite, slowly morphing audio-reactive landscape rendered with a
// printmaking aesthetic: bimodal materials separated by a razor-sharp
// ridge-line, with saturated metallic peaks that cycle through a Quilez
// cosine palette over time + valence + spatial position.  Drum onsets
// flare the peak palette into HDR bloom; the ridge-line itself reads as
// a thin emissive seam where the cut goes.
//
// MV-1 (D-026): All FeatureVector fallback drivers converted from
// absolute-threshold form to deviation primitives so they remain
// genre-stable across AGC denominator shifts.  Changes:
//
//   melodyFromFV:  f.mid_att * 15.0  → 0.5 + f.mid_att_rel
//     Before: steady-state ≈ 7.5 (f.mid_att ≈ 0.5 × 15), range [0, 15].
//             Absolute value shifts with mix density — a quiet section of a
//             loud track and a loud section of a quiet track give the same
//             f.mid_att ≈ 0.5, but the acoustic energy differs by 10 dB.
//     After: steady-state = 0.5 (centered), range [0, 1.5] after clamp.
//            mid_att_rel = (mid_att − 0.5) × 2 → 0 when at AGC average,
//            positive when above average, negative below.  Mix-stable.
//
//   bassFromFV:    f.bass_att * 1.2  → 0.3 + f.bass_att_rel * 0.7
//     Before: steady-state ≈ 0.6.  Shifts with AGC denominator.
//     After:  steady-state = 0.3 (a gentle baseline), peaks at ~1.0 on
//             loud bass, drops to 0 in sparse sections.  Deviation-driven.
//
//   melodyHueFromFV: f.mid_att * 5.0 → 0.5 + f.mid_att_rel * 0.5
//     Before: steady-state ≈ 2.5.  Hue phase accumulates toward a fixed
//             region of the palette regardless of relative melodic intensity.
//     After:  steady-state = 0.5.  Above-average melody pushes hue phase
//             up to 1.0; below-average pulls toward 0.  Palette rotation
//             reflects actual melodic lift, not absolute AGC level.
//
//   otherFromFV: sqrt(max(f.mid, 0)) * 1.6 → f.mid_dev * 1.5
//     Before: sqrt(0.5) * 1.6 ≈ 1.13 → clamped 1.0.  Peak roughness was
//             permanently polished even in sparse sections.
//     After:  mid_dev = max(0, mid_rel).  Zero when mid is at AGC average;
//             positive only on above-average melodic energy.  Roughness
//             polish now fires on genuinely active mid moments, not always.
//
// v4.1: StemFeatures now plumbed through the preamble into sceneSDF
// and sceneMaterial (engine-level change: per-preset stem routing à la
// Milkdrop is the long-term aim).  VL upgrades from band-proxy drivers
// to true stem reads with D-019 warmup fallback:
//   - Terrain amp "melody" = stems.other_energy + stems.vocals_energy
//       (fallback f.mid_att × 15)
//   - Terrain amp "bass"   = stems.bass_energy  (fallback f.bass_att × 1.2)
//   - Accent trigger       = smoothstep(stems.drums_beat)
//       (fallback smoothstep(f.spectral_flux))
//   - Peak polish          = stems.other_energy × 3
//       (fallback sqrt(f.mid) × 1.6)
//   - Palette hue melody   = stems.vocals + stems.other
//       (fallback f.mid_att × 5)
// All blended via smoothstep(0.02, 0.06, totalStemEnergy) so the preset
// gracefully handles the first few seconds before the stem separator's
// first chunk completes.
//
// v4 (session 2026-04-16T20-09-44Z — tested on Tea Lights, Lower Dens,
// an acoustic/electric guitar driven track at ~75 BPM with no kick drum):
// previous iterations were all bass-band-centric and totally failed on
// non-percussive music.  v4 redesigns drivers to be genre-agnostic:
//   - sceneSDF audioAmp: melody-primary blend.  f.mid_att (250-4000 Hz)
//     covers guitar/vocals/synths at ×15 (compensates per-band AGC).
//     f.bass_att retained as secondary (×1.2) so bass-driven tracks still
//     get sub-swell.  Weighted 0.75 melody + 0.35 bass.
//   - sceneMaterial accent: f.spectral_flux (any timbral attack — kicks,
//     guitar strums, vocal onsets, piano chord changes) replaces the
//     bass-keyed drumsBeatFB.  smoothstep(0.35, 0.70) based on Tea Lights
//     distribution (mean 0.47, p90 0.69).
//   - Palette phase now adds f.mid_att × 3.0 so colour rotates with
//     melodic phrasing, not only accumulated audio time.
//   - Paired with forward camera dolly (1.8 u/s, enabled in
//     VisualizerEngine+Presets.swift) so scene CHANGE comes from spatial
//     motion, not only vertical pulsing.  Amplitude reduced 1.8 → 1.4
//     because tall peaks look dramatic on horizon but awkward close-up
//     when dollying past.  Flares toned down (×1.5 → ×0.8 peak, ×2.0 →
//     ×1.0 ridge, 0.03 → 0.02 coverage shift) to match ambient motion.
//
// v3.4 (session 2026-04-16T18-56-59Z — Matt flagged "still out of sync,
// and sharper/less smooth"):  Data analysis exposed that v3.3's
// smoothstep(0.22, 0.32, f.bass) missed half the kicks (many Love Rehab
// kicks peak at 0.20-0.23 in f.bass, below the 0.22 threshold), producing
// a phantom 65 BPM rhythm — half the actual 125 BPM kick.  The narrow
// smoothstep range also gave near-binary 0→1 transitions, explaining the
// "sharp" character.  v3.4 switches to f.bass_att (the 0.95-smoothed bass
// band): (a) its local maxima track real kicks at 127 BPM (within 2% of
// target), (b) it's already smooth so no sharpening artefacts, (c) it
// catches every kick via smoothing (no threshold-miss issue).  Single
// smooth driver for both sceneSDF audioAmp and sceneMaterial drumsBeatFB.
//
// v3.3 (session 2026-04-16T18-44-45Z — Matt flagged beat not syncing to
// the driving kick):  Data revealed that f.beat_bass was firing at
// 143 BPM on a 125 BPM track — the 400ms cooldown in the 6-band onset
// detector phase-locks beat_bass to the cooldown itself when the track
// has dense off-kick bass content (like Love Rehab's syncopated
// bassline).  f.bass local-maxima analysis showed the real kick rhythm
// is cleanly readable from the continuous bass energy (508ms intervals,
// matching 125 BPM).  v3.3 switches all beat-aligned drivers to use
// smoothstep(0.22, 0.32, f.bass) instead of f.beat_bass:
//   - Terrain kick in sceneSDF: smoothstep × 0.40 (up from 0.35, since
//     smoothstep has a smoother shape than the sharp beat_bass pulse).
//   - drumsBeatFB in sceneMaterial: direct smoothstep output.
//   - Removed 0.4 * f.mid_att from slowAmp: mid had ~4.6 onsets/sec on
//     Love Rehab (hi-hat/clap), which leaked a non-kick rhythm into
//     terrain amplitude.  bass_att alone tracks the kick.
//
// v3.2 (session 2026-04-16T18-24-43Z — Matt flagged "pulsing faster than
// the beat" and "neutral gray backdrop"):
//   - Peak coverage was ~35% because lo=0.50 sat at the fbm mean.  Raised
//     lo/hi to 0.56/0.60 so peaks are ~15% of the scene — restores the
//     linocut "highlights on mostly-dark paper" feel and quiets the
//     visual field so beat-aligned motion can dominate.
//   - Noise time scale 0.06 → 0.015: high-octave fbm shimmer was drifting
//     fast enough to read as continuous "pulses" that weren't beat-locked.
//     4× slower ties the surface detail down so beat flares stand out.
//   - Palette rotation 0.15 → 0.08: ~one full colour cycle per preset
//     duration at moderate energy (was pulse-rate at 0.15).
//   - Shared RayMarch.metal fix: miss/sky pixels now tinted by
//     scene.lightColor.rgb (matches fog-colour treatment) — no more
//     "neutral gray backdrop" on presets with warm light colour.
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
// Audio routing (v4.1 — StemFeatures available via preamble):
//   s.sceneParamsA.x                        → terrain phase (accumulated audio time)
//   stems.other + stems.vocals / f.mid_att  → primary vertical displacement (melody)
//   stems.bass / f.bass_att                 → secondary vertical displacement
//   stems.drums_beat / f.spectral_flux      → accent (palette flare + ridge strobe)
//   stems.other + stems.vocals / f.mid_att  → palette hue phase (melody → colour)
//   f.valence                               → palette hue offset (mood)
//   stems.other / sqrt(f.mid)               → peak roughness polish
// Where "A / B": A is the stem-accurate driver (used once stems have warmed
// up via smoothstep(0.02, 0.06, totalStemEnergy)); B is the FeatureVector
// fallback used during warmup.  Forward camera dolly (1.8 u/s) configured in
//   PhospheneApp/VisualizerEngine+Presets.swift → RayMarchPipeline.cameraDollySpeed.
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
constant float VL_NOISE_TIME_SCALE = 0.015f; // v3.2: 0.06 → 0.015 so high-octave
                                              // noise shimmer slows to ~1 cycle
                                              // per 20s wallclock; beat-aligned
                                              // motion stops competing with
                                              // continuous surface boil
constant float VL_DISP_SILENT_AMP  = 0.6f;   // baseline so terrain reads in silence
constant float VL_DISP_AUDIO_AMP   = 1.4f;   // v4: 1.8 → 1.4 to pair with forward
                                              //      dolly — tall peaks awkward when
                                              //      flying past close-up
constant int   VL_FBM_OCTAVES      = 5;

// SDF Lipschitz scaling: heightfield is not Euclidean on slopes.
constant float VL_SDF_STEP_SCALE   = 0.6f;

// Linocut edge windows — v3.2 narrowed peak coverage from ~35% (v3/v3.1
// had lo=0.50, right at the fbm mean, so half the terrain was "peaks")
// to ~15% (lo=0.56, above the mean, so peaks read as highlights on a
// mostly-dark canvas — the linocut "ink on paper" relationship).
constant float VL_PEAK_LO          = 0.56f;  // valley → peak transition start
constant float VL_PEAK_HI          = 0.60f;  // valley → peak transition end
constant float VL_RIDGE_INNER      = 0.555f; // ridgeline lower edge
constant float VL_RIDGE_OUTER      = 0.565f; // ridgeline upper edge

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
               constant SceneUniforms& s,
               constant StemFeatures& stems) {
    float audioPhase = s.sceneParamsA.x;                            // accumulated audio time

    // v4.1: true stem-driven melody, with D-019 warmup fallback to
    // FeatureVector proxies.  StemFeatures now plumbed through the
    // preamble so sceneSDF can read stems directly.
    //
    //   Melody (primary, weight 0.75):
    //     stems.other_energy + stems.vocals_energy — "other" is the
    //     catch-all for melodic instruments (guitar, synth, piano) and
    //     vocals carry lyrical phrasing.  Together they track the song's
    //     melodic motion directly.  Fallback f.mid_att × 15 (250-4000 Hz
    //     covers the same timbral range post-AGC-boost).
    //
    //   Bass (secondary, weight 0.35):
    //     stems.bass_energy — isolated bass stem (kick + bassline).
    //     Fallback f.bass_att × 1.2.
    //
    // Warmup blend: smoothstep(0.02, 0.06, totalStemEnergy) interpolates
    // from FeatureVector fallbacks (mix == 0) to stem direct (mix == 1).
    float totalStemEnergy = stems.vocals_energy + stems.drums_energy
                          + stems.bass_energy   + stems.other_energy;
    float stemMix = smoothstep(0.02f, 0.06f, totalStemEnergy);

    float melodyFromStems = clamp((stems.other_energy + stems.vocals_energy) * 1.6f,
                                   0.0f, 1.5f);
    float melodyFromFV    = clamp(0.5f + f.mid_att_rel, 0.0f, 1.5f);  // MV-1: deviation, not absolute
    float melody          = mix(melodyFromFV, melodyFromStems, stemMix);

    float bassFromStems = clamp(stems.bass_energy * 2.0f, 0.0f, 1.0f);
    float bassFromFV    = clamp(0.3f + f.bass_att_rel * 0.7f, 0.0f, 1.0f);  // MV-1: deviation, not absolute
    float bass          = mix(bassFromFV, bassFromStems, stemMix);

    float audioAmp = clamp(melody * 0.75f + bass * 0.35f, 0.0f, 2.0f);
    float h = vl_heightAt(p, audioPhase, audioAmp);
    return (p.y - h) * VL_SDF_STEP_SCALE;
}

// ── Scene Material ────────────────────────────────────────────────────────

void sceneMaterial(float3 p,
                   int matID,
                   constant FeatureVector& f,
                   constant SceneUniforms& s,
                   constant StemFeatures& stems,
                   thread float3& albedo,
                   thread float& roughness,
                   thread float& metallic) {
    float audioPhase = s.sceneParamsA.x;
    float n          = vl_terrainNoise(p, audioPhase); // [0,1]

    // v4.1: accent driver now prefers stems.drums_beat (true drum-stem
    // onset pulse) when stems have warmed up, with D-019 fallback to
    // f.spectral_flux (genre-agnostic full-mix timbral attack).
    //
    // stems.drums_beat is kick/snare-aligned: on Love Rehab it tracks
    // the actual 125 BPM kick cleanly; on Tea Lights (soft percussion)
    // it fires on guitar strums picked up by the drum stem.
    //
    // f.spectral_flux is the fallback because it fires on ANY timbral
    // change — works before stems separation completes on the first chunk.
    float totalAccentStem = stems.vocals_energy + stems.drums_energy
                          + stems.bass_energy   + stems.other_energy;
    float accentStemMix = smoothstep(0.02f, 0.06f, totalAccentStem);
    float accentFromStems = smoothstep(0.30f, 0.70f, stems.drums_beat);
    float accentFromFV    = smoothstep(0.35f, 0.70f, f.spectral_flux);
    float accentFB = mix(accentFromFV, accentFromStems, accentStemMix);

    // v4.1: "other" polish now prefers stems.other_energy directly,
    // with D-019 fallback to the pre-existing sqrt(f.mid) × 1.6 proxy.
    float otherFromStems = clamp(stems.other_energy * 3.0f, 0.0f, 1.0f);
    float otherFromFV    = clamp(f.mid_dev * 1.5f, 0.0f, 1.0f);  // MV-1: deviation, not absolute
    float otherFB        = mix(otherFromFV, otherFromStems, accentStemMix);

    // ── Three-stratum classification ────────────────────────────────────
    //   peakSelect    = matte-valley → polished-peak transition (sharp)
    //   ridgeSelect   = thin emissive seam at the boundary (cut-paper line)
    //
    // Accent adds a small coverage shift (v4: 0.03 → 0.02 for quieter
    // ambient match with forward dolly + melody-driven motion).
    float beatShift   = accentFB * 0.02f;
    float peakSelect  = smoothstep(VL_PEAK_LO - beatShift,
                                    VL_PEAK_HI - beatShift, n);
    float ridgeSelect =
        smoothstep(VL_RIDGE_INNER - beatShift,
                    (VL_RIDGE_INNER + VL_RIDGE_OUTER) * 0.5f - beatShift, n)
      * (1.0f - smoothstep((VL_RIDGE_INNER + VL_RIDGE_OUTER) * 0.5f - beatShift,
                            VL_RIDGE_OUTER - beatShift, n));

    // ── Psychedelic palette ────────────────────────────────────────────
    // Phase = local noise × 0.9        (spatial hue spread across peaks)
    //       + audioTime × 0.08         (baseline cycle — ~1 full rotation
    //                                    per preset duration at moderate energy)
    //       + melodyHue × 0.6          (melody modulates hue; v4.1 uses stems
    //                                    directly with FV fallback)
    //       + valence × 0.25           (per-track mood hue identity)
    float melodyHueFromStems = stems.vocals_energy + stems.other_energy;
    float melodyHueFromFV    = 0.5f + f.mid_att_rel * 0.5f;  // MV-1: deviation, not absolute
    float melodyHue          = mix(melodyHueFromFV, melodyHueFromStems, accentStemMix);
    float palettePhase = n * 0.9f
                       + audioPhase * 0.08f
                       + melodyHue * 0.6f
                       + f.valence * 0.25f;
    float3 peakHue   = vl_palette(palettePhase);
    // Valley brightness × 0.15 (v3 had × 0.08 which the valence-tinted
    // IBL ambient drowned out — valleys read as uniform dark brown).
    float3 valleyHue = vl_palette(palettePhase + 0.5f) * 0.15f;

    // Accent flare: peaks push into HDR (bloom in post_process amplifies);
    // ACES at composite (RayMarch.metal:352–355) handles the over-bright
    // values gracefully.  v4: 1.5 → 0.8 to match softer ambient motion
    // paired with forward dolly + melody-driven terrain.  Peak albedo
    // reaches up to 1.8× at full accent (was 2.5×).
    float accentBoost = 1.0f + accentFB * 0.8f;
    peakHue *= accentBoost;

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
    // the same palette with an additional accent strobe so the cut-line
    // itself pulses on any timbral attack.  Low metallic reads as
    // luminous-paint rather than chrome line; low roughness keeps the
    // seam tight.  v4: strobe × 2.0 → × 1.0 (ridge reaches 2.4×
    // brightness on full accent, was 3.4×) — quieter to match ambient.
    float  ridgeStrobe = 1.4f + accentFB * 1.0f;
    float3 ridgeAlbedo = peakHue * ridgeStrobe;
    float  ridgeRough  = 0.30f;
    float  ridgeMetal  = 0.10f;
    albedo    = mix(albedo,    ridgeAlbedo, ridgeSelect);
    roughness = mix(roughness, ridgeRough,  ridgeSelect);
    metallic  = mix(metallic,  ridgeMetal,  ridgeSelect);
}
