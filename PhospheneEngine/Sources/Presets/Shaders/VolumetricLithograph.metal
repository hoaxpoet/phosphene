// VolumetricLithograph.metal — Psychedelic linocut-inspired terrain landscape.
//
// An infinite, slowly morphing audio-reactive landscape rendered with a
// printmaking aesthetic: bimodal materials separated by a razor-sharp
// ridge-line, with saturated metallic peaks that cycle through a Quilez
// cosine palette over time + valence + spatial position.  Drum onsets
// flare the peak palette into HDR bloom; the ridge-line itself reads as
// a thin emissive seam where the cut goes.
//
// v9 — Explicit per-stem routing: drums→pulse, vocals→depth (2026-04-17,
//   session 2026-04-17T22-42-15Z).  Matt's observations on bad guy:
//
//     "The best synchronization is with the darker valleys, which move
//      deeper with Billie Eilish's voice.  The pulsing terrain is a bit
//      too overstimulated and could probably react to just the kick."
//
//   Data analysis of the session confirmed:
//     • Vocals leads the song's dynamic envelope (avg 0.37, highest
//       variance 0.023) — its coincidental contribution through
//       intensity was what produced the "valleys move with voice" read.
//     • Only `stems.drums_beat` has a live beat signal (per-stem beat
//       detector architecture — other stems' `_beat` fields stay 0).
//     • `f.beat_composite` (v8.2's pulse source) fires on vocal
//       transients, mid-band attacks AND kicks — the overstimulation.
//
//   v9 mapping (explicit):
//     Kick pulse (peak lift):  max(stems.drums_beat, f.beat_bass × 0.8),
//                              thresholded smoothstep(0.20, 0.70).
//                              Restricted to kick-character signals;
//                              f.beat_bass fallback covers bass-driven
//                              tracks (Slint) where drums stem is empty.
//     Vocal depth:             stems.vocals_energy (fast-follow) →
//                              adds VL_VOCAL_DEPTH_BOOST × swell to
//                              audioAmp.  Deeper valleys with vocal
//                              phrasing, intentional rather than
//                              accidental.  FV fallback: f.mid_att_rel.
//     Continuous intensity:    coact + log(1+density) + 0.25·(AR-1)
//                              (retained for section-scale swell).
//     Palette hue:              unchanged (energy-weighted stem mean).
//     Peak polish:              unchanged (onset density).
//     Bass sustain:             REMOVED from peak lift (user: "just the
//                              kick").  Bass now contributes only via
//                              coactivation and density in intensity.
//
// v8.2 — Sync-drift fixes: thresholded beat pulse + bass sustain + beefier
//   FV fallback (2026-04-17, session 2026-04-17T22-29-43Z).  Matt's
//   observation on bad guy was a specific pattern: "not synced at start,
//   synced at 5-6s, drifts out, re-syncs approaching chorus."  Data
//   confirmed three causes:
//
//   (1) f.beat_composite is noisy during active music — values span
//       0.22 to 1.00 across frames within a single bar.  Using the raw
//       value as the pulse amplitude meant weak detector reads (0.3-0.5)
//       produced subtle bumps that didn't carry sync; only the full
//       pulses (0.9-1.0) were visible.  v8.2 thresholds via
//       smoothstep(0.30, 0.85) so only real hits register, and the
//       peak lift constant is increased to compensate.
//
//   (2) Sustained 808/sub-bass verses (bad guy 0:04-0:21) have few
//       rising-edge onsets — the detector sees a held bass note as
//       one flux spike, not a rhythm.  Added a separate `bassSustain`
//       term driven by f.bass_att (IIR-smoothed bass band) that feeds
//       into the same peak-lift path.  Keeps terrain visibly alive
//       during sustained bass-forward sections even between discrete
//       onsets.
//
//   (3) Pre-stem FV fallback was structurally weaker than post-stem
//       intensity (max ~1.1 vs max ~2.5), producing a visible
//       response-strength jump at ~10s when stems arrived.  FV path
//       now scales band deviations more aggressively and adds a
//       continuous bass_att floor, matching post-stem range.
//
// v8 — Asymmetric peak-lift beat pulse + wider depth range (2026-04-17).
//   Matt feedback on v7: the linear `audioAmp += beatPulse × 0.6` added
//   the pulse to the *entire* terrain amplitude, which multiplies both
//   sides of the (n − 0.5) midpoint — so peaks lift AND valleys drop on
//   each onset, in equal measure.  That reads as the whole terrain
//   vertically stretching (a breathing squish) rather than as rhythmic
//   motion.  Visually subtle, not what a "pulse" should feel like.
//
//   v8 splits the pulse out of `audioAmp` and applies it only to the
//   above-midpoint region in `vl_heightAt`:
//
//     peakLift = beatPulse × max(0, n − 0.5) × 2 × VL_BEAT_PEAK_LIFT
//     h       = base + peakLift
//
//   Asymmetric: valleys stay at their continuous-intensity floor while
//   peaks reach *up* on each onset and relax back (beat_composite decays
//   ~200 ms to 0.1).  Reads as "tall peaks reaching toward the sky on
//   every beat" rather than "whole terrain squishing."
//
//   Also widens the continuous depth range to make intensity differences
//   dramatic rather than subtle:
//     VL_DISP_SILENT_AMP  0.6 → 0.4  (lower resting floor)
//     VL_DISP_AUDIO_AMP   1.4 → 2.2  (steeper intensity response)
//     Silent terrain: peaks at ~0.4 units.  Dense section: peaks at ~5.
//     10× depth swing between silent and dense; clearly perceptible.
//
//   Reference tracks for future testing (modern loud-mastered, peaks
//   within 1 dB of full scale): Billie Eilish "bad guy", Taylor Swift
//   "Anti-Hero", The Weeknd "Blinding Lights", Dua Lipa "Levitating",
//   Post Malone "Sunflower".  Dynamic-range references (still loud-
//   mastered on streaming but with wider quiet-to-loud internal range):
//   Steely Dan "Aja", Pink Floyd "Time".
//
// v7 — Beat-synced terrain pulse via `f.beat_composite` (2026-04-17,
//   session 2026-04-17T20-16-31Z).  Matt observed that Slint's "Good
//   Morning, Captain" is bass-and-guitar-driven (no kick propelling
//   the verse), so a drum-centric rhythm driver gets the synchronization
//   wrong.  v7 replaces the drum-stem beat + stem-specific intensity
//   with `f.beat_composite` — the 6-band full-mix onset detector's
//   union signal, which fires on whichever band is currently rhythmic:
//   kick (sub_bass/low_bass), bass guitar pluck (low_bass), guitar
//   strum (low_mid), vocal attack (mid_high), cymbal (high).  Every
//   band has proper cooldowns so it doesn't flood on dense passages.
//
//   Changes:
//     audioAmp += f.beat_composite × 0.6  — terrain now visibly pulses
//       on each onset in addition to the continuous intensity swell.
//       Base:beat ratio ≈ 2.5:1 (CLAUDE.md guideline 2-4×).
//     accent = smoothstep(f.beat_composite)  — peak flare + ridge
//       strobe now fire on any rhythmic band, not only the drum stem.
//
//   The intensity driver (coact + density + attack) is retained for
//   the slow section-energy swell; it just no longer has to carry the
//   rhythm signal as well.
//
// v6.2 — Calibration tighten (see diff history):
//   • Coactivation thresholds [0.12, 0.30] → [0.28, 0.50].  Stem
//     separator leaks cross-material, so "active" requires genuine
//     above-baseline energy.  Sparse verses now score coact 0-1.
//   • Density log-compressed (log(1+density)) and baseline subtracted
//     so intensity truly floors at 0 in sparse sections.
//
// v6.1 — Recalibration + rhythm decoupling (2026-04-17, session
//   2026-04-17T19-31-46Z).  The v6 prototype shipped with two latent
//   issues surfaced on Slint "Good Morning, Captain":
//
//   (a) Onset rates were 20-25/sec across all stems (should be 1-8/sec),
//       saturating `density` and pinning intensity at clamp 2.5 for
//       the whole song — amp was effectively constant.  Root cause was
//       a missing rising-edge gate in the StemAnalyzer onset detector:
//       each sustained above-threshold signal registered 3-5 onsets per
//       hit.  Fixed at the source with rising-edge + 100ms refractory.
//
//   (b) Accent fired on `attack_ratio` across all four stems, so bass
//       onsets (often syncopated against the drum pattern) produced
//       extra off-beat flashes that read as arhythmic.  v6.1 locks the
//       accent to `drums_beat` only (which already has proper per-band
//       cooldowns from the drum-stem BeatDetector), with FV spectral-
//       flux fallback during stem warmup.
//
//   Intensity constants recalibrated for realistic post-fix rates:
//     intensity = 0.25·coact + 0.40·density + 0.20·(attack-1)
//
// v6 — Density/rate/attack drivers (2026-04-17, session 2026-04-17T18-28-01Z).
// v5 depended on per-stem deviation (`*_energy_dev`) to drive terrain amp.
// Diagnostic showed this failed on Slint — Good Morning, Captain: the
// screamed-vocal outro is ~4× louder acoustically than the bass-only
// verse, but post-AGC normalised energies were 0.45 vs 0.20 (≈2.3×), and
// dev values dropped back near zero during the sustained outro as the
// per-stem EMA (decay 0.995, τ≈2s) caught up to the new loudness.  The
// visualiser read the outro and the verse as the same intensity.
//
// v6 pivots to three primitives that survive per-stem AGC because they
// measure the *structure* of activity rather than its amplitude:
//
//   1. Coactivation count — how many stems are simultaneously active
//      (soft count via smoothstep on raw energies).  Verse has 1
//      active stem; outro has all 4.  AGC compresses amplitude but
//      cannot make a silent stem appear active.
//
//   2. Onset rate (MV-3a, events/sec, ~0.5s leaky integrator) — how
//      fast onsets are firing.  Outro has dense kicks + strummed
//      guitar onsets at ~3-5 events/sec; verse has sparse plucks.
//      Rate is unaffected by AGC gain.
//
//   3. Attack ratio (MV-3a, fastRMS(50ms)/slowRMS(500ms), clamped [0,3])
//      — how transient the sharpest stem currently is.  Screamed
//      vocals and hard drum hits have ratio ≫ 1; sustained pads ~1.
//      A fast-over-slow RMS ratio is gain-invariant by construction.
//
// Combined: intensity = 0.30·coact + 0.50·density + 0.25·(attack−1)
//
// Rough target ranges:
//   Silence          → 0
//   Solo-bass verse  → coact≈1, dens≈0.3, attack≈1.2  →  ~0.6
//   Full-band verse  → coact≈2.5, dens≈0.6, attack≈1.5 →  ~1.2
//   Dense outro      → coact≈4, dens≈1.2, attack≈2.5  →  ~2.2
//
// Hue driver: energy-weighted mean across per-stem hue positions (bass
// warm, drums violet, vocals teal, other yellow).  v5 used dev-weighted
// but that collapsed numerically when all devs decayed; energy-weighted
// blends stems by current mix contribution, which is what "dominant
// stem shifts palette" should measure anyway.
//
// Accent: max(drums_beat, smoothstep(attack−1)) — fires on any stem's
// sharp transient, not only the drum-stem onset detector.
//
// MV-1 FV fallbacks retained for warmup (smoothstep(0.02, 0.06, total)).
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
// Audio routing (v9.2 — clean per-stem / per-element mapping):
//   s.sceneParamsA.x                                          → terrain phase
//   0.30·coact + 0.50·log(1+density) + 0.25·(AR-1)            → section intensity
//   stems.vocals_energy × 0.7 (+ intensity)                   → continuous depth amp
//   max(stems.drums_beat,
//       smoothstep(1.3, 2.0, stems.drums_attack_ratio)
//         × smoothstep(0.08, 0.22, stems.drums_energy))       → kick-only peak lift
//                                                             (DRUM STEM ONLY; no bass)
//   features.bass                                             → camera dolly speed
//                                                             (separate path in RayMarch)
//   kickPulse (same drum-stem-only source)                    → accent (peak flare + ridge + coverage)
//   energy-weighted stem-hue mean                             → palette hue phase
//   f.valence                                                 → palette hue offset (mood)
//   onset-density + 0.25·attack                               → peak roughness polish
// FV fallbacks (pre-stem warmup):
//   0.3 + f.bass_att_rel·1.2 + f.mid_att_rel·1.4 + f.bass_att·0.6 → continuous amp
//   f.mid_att_rel + 0.2                                           → vocal swell proxy
//   (no FV fallback for kickPulse — landmasses silent during stem warmup;
//    track start has ~10s of no-pulse before stems arrive.  Acceptable
//    trade for removing bass-overload when stems are live.)
// Camera dolly base: 1.8 u/s (VisualizerEngine+Presets.swift).  Modulated
// per-frame by (0.5 + features.bass × 1.1) in RenderPipeline+RayMarch.swift.
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
constant float VL_DISP_SILENT_AMP  = 0.5f;   // v8.1: 0.4 → 0.5; closer to v4 resting depth
                                              //       (Matt: v8 was "way too hot")
constant float VL_DISP_AUDIO_AMP   = 1.3f;   // v8.1: 2.2 → 1.3; back down close to v4's 1.4
                                              //       so peak heights don't run away.
                                              //       Dense section: 0.5 + 2×1.3 = 3.1 units,
                                              //       matching v4's ~3.4 max.  Silent: 0.5.
                                              //       Still a 6× depth swing intensity-driven.
constant float VL_BEAT_PEAK_LIFT   = 0.9f;   // v8.2: 0.5 → 0.9.  v9: unchanged magnitude,
                                              //       but the source is now drums-stem-only
                                              //       (see kickPulse in sceneSDF).
constant float VL_VOCAL_DEPTH_BOOST = 0.7f;  // v9: NEW — vocals_energy contribution to the
                                              //       continuous-depth amp.  Matt's observation
                                              //       on bad guy: "darker valleys moving deeper
                                              //       with Billie's voice is the BEST sync."
                                              //       Data confirmed vocals carries the song's
                                              //       dynamic envelope (avg 0.37, highest
                                              //       variance 0.023).  This routes vocals
                                              //       stem energy into the amp driver so the
                                              //       effect is intentional and explicit, not
                                              //       an accident of stem-summed intensity.
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
///
/// v9 peak-lift: asymmetric, driven SOLELY by `kickPulse` (drums-stem beat +
/// bass-band-flux fallback).  Matt's v8.2 observation: sustained-bass +
/// beat-composite pulses together were "overstimulated" — the visual
/// pulsed on vocal transients, mid-band attacks, AND kicks.  v9 restricts
/// the peak-lift source to kick-character onsets only.  Bass-stem-derived
/// motion now contributes to `audioAmp` (depth), not to peak lift.
static inline float vl_heightAt(float3 worldP, float audioPhase,
                                 float audioAmp, float kickPulse) {
    float n    = vl_terrainNoise(worldP, audioPhase);
    float amp  = VL_DISP_SILENT_AMP + audioAmp * VL_DISP_AUDIO_AMP;
    float base = (n - 0.5f) * 2.0f * amp;
    float nAbove = max(0.0f, n - 0.5f) * 2.0f;
    float peakLift = nAbove * kickPulse * VL_BEAT_PEAK_LIFT;
    return VL_TERRAIN_BASE_Y + base + peakLift;
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
               constant StemFeatures& stems,
               texture2d<float> ferrofluidHeight) {
    (void)ferrofluidHeight;  // V.9 Session 4.5b slot-10; Ferrofluid Ocean only.
    float audioPhase = s.sceneParamsA.x;                            // accumulated audio time

    // v9.3: section-intensity driver REMOVED from audioAmp path.
    // Matt's requirement (session 22-52-30Z → 23-22-40Z): "landmasses
    // should be COMPLETELY STILL and ONLY respond to the clicks/snaps"
    // during bass-only playback.  The old intensity =
    //   0.30·coact + 0.50·log(1+density) + 0.25·(attackN−1)
    // included bass-stem coactivation and bass onsets, which made
    // landmass DEPTH animate with the bassline even when `kickPulse`
    // was silent.  v9.3 removes it entirely from audioAmp — continuous
    // depth is now driven EXCLUSIVELY by `vocalSwell` (vocals stem).
    // Landmasses are truly still when only bass is playing.
    //
    // Section-level energy dynamics (quiet intro → loud chorus) now
    // emerge from vocalSwell itself (vocals are present across all
    // sections in bad guy) and from palette shifts / camera pace.

    // v9.2 rhythmic driver: kickPulse from DRUM-STEM ONLY.  Matt's v9.1
    // feedback: "landmasses are currently pulsing with the bass, which
    // should only be controlling the speed of the camera... when the
    // snaps come in, they are not registering because the bass already
    // overloads the pulsing landmasses."
    //
    // v9.1 included `f.beat_bass × 0.8` as a fallback "for non-drums
    // tracks."  On bad guy, that fallback fires on every 808 bass note
    // → landmasses pulse continuously at bass rate → distinct snap
    // events produce no visible DELTA against the already-saturated
    // baseline.  Removing the bass fallback so the pulse is silent
    // between snaps and fires cleanly on each percussion hit.
    //
    //   • stems.drums_beat         — kicks (when BeatDetector isn't
    //                                threshold-saturated)
    //   • stems.drums_attack_ratio — snaps/claps/snares (gated by
    //                                drums_energy so vocal transients
    //                                can't leak into the pulse)
    //
    // Bass now exclusively drives camera dolly speed (see
    // RenderPipeline+RayMarch.swift).  Non-drum-only tracks (e.g. Slint
    // bass-guitar-driven) will land with silent landmass pulses — we'll
    // add an adaptive per-track routing in the Orchestrator phase.
    float drumsActive    = smoothstep(0.08f, 0.22f, stems.drums_energy);
    float drumsTransient = smoothstep(1.3f, 2.0f, stems.drums_attack_ratio)
                         * drumsActive;
    float kickRaw   = max(stems.drums_beat, drumsTransient);
    float kickPulse = smoothstep(0.20f, 0.70f, kickRaw);

    // D-019 warmup: FeatureVector fallback until stems produce first chunk.
    float totalStemEnergy = stems.vocals_energy + stems.drums_energy
                          + stems.bass_energy   + stems.other_energy;
    float stemMix = smoothstep(0.02f, 0.06f, totalStemEnergy);

    // v9.3: audioAmp = vocalSwell ONLY.  No FV bass terms.  No intensity
    // term.  Continuous terrain depth responds exclusively to vocals.
    // During bass-only sections the vocals stem is silent (or near-
    // silent for whispered intros) and audioAmp floors at 0 — terrain
    // sits at VL_DISP_SILENT_AMP resting depth, no audio-driven motion.
    //
    // FV fallback during stem warmup uses f.mid_att_rel as a vocals
    // proxy (most vocal fundamentals + harmonics sit in the mid band).
    // Pre-stem bass contributions removed — otherwise the first 10
    // seconds of a track with active bass would still drive landmass
    // depth before the vocals stem came online.
    float vocalSwellFromStems = clamp(stems.vocals_energy - 0.1f, 0.0f, 1.2f);
    float vocalSwellFromFV    = clamp(f.mid_att_rel, 0.0f, 1.2f);
    float vocalSwell          = mix(vocalSwellFromFV, vocalSwellFromStems, stemMix);

    float audioAmp = vocalSwell * VL_VOCAL_DEPTH_BOOST;

    // v9: peak lift is kick-only (no bass sustain).
    float h = vl_heightAt(p, audioPhase, audioAmp, kickPulse);
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
                   thread float& metallic,
                   thread int& outMatID,
                   constant LumenPatternState& lumen) {
    // outMatID stays at the caller's default (0 = standard dielectric); VL
    // ships through the existing Cook-Torrance dielectric path.
    (void)outMatID;
    // `lumen` (LM.2 / D-LM-buffer-slot-8) is the trailing slot-8 buffer used
    // by Lumen Mosaic. Non-Lumen presets ignore it.
    (void)lumen;
    float audioPhase = s.sceneParamsA.x;
    float n          = vl_terrainNoise(p, audioPhase); // [0,1]

    // v9.4: accent = drum-stem-only kickPulse.  The prior accent path
    // used `f.beat_composite` (6-band full-mix onset composite), which
    // fires on EVERY bass note.  Downstream, accentFB drives beatShift
    // (peak/valley threshold modulation → peak coverage expands on
    // each hit → "landmasses animate") and accentBoost (peak albedo
    // brightness).  That's the bass-driven landmass pulsing Matt has
    // been observing for four iterations.  Rerouting accentFB to the
    // same drums-stem-only kickPulse used in sceneSDF means peak
    // coverage/brightness respond ONLY to drum hits (kicks + snaps
    // via attack-ratio), and bass-only sections leave the landmass
    // material stable.
    //
    // kickPulse is recomputed here (duplicate of sceneSDF) because
    // sceneSDF and sceneMaterial are separate entry points called from
    // different fragment-path contexts and don't share locals.
    float drumsActive    = smoothstep(0.08f, 0.22f, stems.drums_energy);
    float drumsTransient = smoothstep(1.3f, 2.0f, stems.drums_attack_ratio)
                         * drumsActive;
    float kickRaw   = max(stems.drums_beat, drumsTransient);
    float kickPulse = smoothstep(0.20f, 0.70f, kickRaw);

    // accentStemMix retained for the peak-polish FV/stem crossfade below.
    float totalAccentStem = stems.vocals_energy + stems.drums_energy
                          + stems.bass_energy   + stems.other_energy;
    float accentStemMix = smoothstep(0.02f, 0.06f, totalAccentStem);

    float accentFB = kickPulse;

    // v6.1: peak polish from onset density (drums-dominant, matching
    // the intensity driver's weighting).  Polishes when the groove is
    // busy; sparse verses stay matte.
    float densityLocal = stems.drums_onset_rate  * 0.20f
                       + stems.bass_onset_rate   * 0.06f
                       + stems.vocals_onset_rate * 0.06f
                       + stems.other_onset_rate  * 0.06f;
    float otherFromStems = clamp(densityLocal * 0.6f, 0.0f, 1.0f);
    float otherFromFV    = clamp(f.mid_dev * 1.5f, 0.0f, 1.0f);
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
    // Phase = local noise × 0.9       (spatial hue spread across peaks)
    //       + audioTime × 0.08        (baseline cycle)
    //       + stemHue   × 0.6         (mix composition shifts hue)
    //       + valence   × 0.25        (per-track mood identity)
    //
    // v6 stemHue: energy-weighted mean of per-stem hue positions.
    //   bass   → 0.00 (warm red/orange)
    //   drums  → 0.25 (violet)
    //   vocals → 0.50 (teal/green)
    //   other  → 0.75 (yellow)
    // Raw energy (not dev) so the weighting stays numerically stable
    // when all devs decay.  The hue tracks who's currently in the mix
    // rather than who's spiking above AGC baseline.
    float wBass   = stems.bass_energy;
    float wDrums  = stems.drums_energy;
    float wVocals = stems.vocals_energy;
    float wOther  = stems.other_energy;
    float wTotal  = wBass + wDrums + wVocals + wOther + 1e-3f;
    float stemHueFromStems = (wBass   * 0.00f
                            + wDrums  * 0.25f
                            + wVocals * 0.50f
                            + wOther  * 0.75f) / wTotal;
    float stemHueFromFV    = 0.5f + f.mid_att_rel * 0.5f;
    float stemHue          = mix(stemHueFromFV, stemHueFromStems, accentStemMix);
    float palettePhase = n * 0.9f
                       + audioPhase * 0.08f
                       + stemHue * 0.6f
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
