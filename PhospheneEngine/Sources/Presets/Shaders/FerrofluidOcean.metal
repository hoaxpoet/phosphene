// FerrofluidOcean.metal — V.9 Session 1–4 layered authoring.
//
// Macro layer of the V.9 redirect (D-124): a fixed-camera, ocean-portion-scale
// view of a body of liquid whose surface is replaced by ferrofluid material.
// Gerstner swell drives macro body motion (audible up/down/back/forth even at
// silence); Rosensweig spike-field rides on top, emerging from the swell when
// `stems.bass_energy_dev > 0` and collapsing entirely at silence.
//
// Session 1 implemented:
//   1. Gerstner-wave macro displacement field (4 superposed waves; arousal-baseline
//      + drums_energy_dev accent amplitude).
//   2. Rosensweig hex-tile spike-field SDF per SHADER_CRAFT §4.6 (bass_energy_dev
//      → spike height).
//   3. Composition: spike field rides on top of Gerstner base height.
//   4. Placeholder sceneMaterial (matID == 0, single-light Cook-Torrance path).
//
// Session 2–3 added: material (mat_ferrofluid + thinfilm_rgb), §5.8 stage-rig
// lighting (D-125: slot-9 buffer + matID == 2 dispatch).
//
// Session 4 (this file) adds the V.9 Phase A material detail layers:
//   - Domain-warped meso turbulence on the spike-field sample position
//     (SHADER_CRAFT §3.4): 2-octave fBM warp at scale 2.0, amplitude 0.15.
//     Phase A holds the strength at the descriptor.mesoStrength baseline;
//     Phase B routes from f.mid_att_rel.
//   - Cassie-Baxter spike-tip droplets composed via op_smooth_union with
//     the height-field swell+spikes SDF: per-cell hemispherical SDF beads
//     at the spike apex points. Phase A holds at descriptor.dropletStrength;
//     Phase B routes from f.bass_att_rel.
//   - Micro normal perturbation lives in the matID == 2 branch of
//     RayMarch.metal (it needs surface-normal access and 3 fBM samples;
//     sceneMaterial would have to pack into the G-buffer to communicate
//     a perturbation, but the matID == 2 branch already has the normal
//     in hand from gbuf1).
//
// Sessions 5 adds: final tuning + M7 cert review + golden-hash regen.
//
// Pipeline: ray_march → post_process. The ray_march preamble forward-declares
// `sceneSDF` and `sceneMaterial` and the renderer's `raymarch_gbuffer_fragment`
// drives them. No custom fragment function here.
//
// Audio data hierarchy compliance (CLAUDE.md):
//   - Continuous: Gerstner amplitude (arousal-baseline) and Rosensweig spike
//                 height (stems.bass_energy_dev) are PRIMARY drivers.
//   - Accents:    drums_energy_dev adds amplitude swing on top of arousal.
//   - No beat-onset rising edges in Session 1.
//   - No absolute-threshold patterns on raw f.bass / stems.bass_energy (D-026).

// MARK: - Constants

constant float FO_TWO_PI = 6.28318530718;

// Crossfade threshold for D-019 silence fallback (FeatureVector proxy → stem
// routing transition). totalStemEnergy < 0.02 → fully on proxies; > 0.06 → fully
// on stems.
constant float FO_STEM_WARMUP_LO = 0.02;
constant float FO_STEM_WARMUP_HI = 0.06;

// MARK: - Audio routing helpers

// D-019 crossfade: proxy ↔ stem.
static inline float fo_stem_warmup_blend(constant StemFeatures& stems) {
    float total = stems.vocals_energy + stems.drums_energy
                + stems.bass_energy   + stems.other_energy;
    return smoothstep(FO_STEM_WARMUP_LO, FO_STEM_WARMUP_HI, total);
}

// Spike-field strength: route from stems.bass_energy_dev (D-026); fall back to
// f.bass_att_rel (smoothed bass deviation, FeatureVector field 32) during stem
// warmup or true silence. At silence, both are ~0 → spike lattice collapses
// per `10_silence_calm_body.jpg`.
static inline float fo_spike_strength(constant FeatureVector& f,
                                      constant StemFeatures& stems) {
    float blend = fo_stem_warmup_blend(stems);
    float proxy = max(0.0, f.bass_att_rel);
    float stem  = max(0.0, stems.bass_energy_dev);
    return mix(proxy, stem, blend);
}

// Swell amplitude scale per D-124(d): arousal sets the sustained baseline at
// ~70%, drums_energy_dev adds short-period crest emphasis at ~30%.
//
//   silent + neutral arousal  → 0.4 (gentle calm-body breathing)
//   peak arousal + drum hit   → 0.4 + 0.6 + 0.3 = 1.3 (clamped by amplitudes)
//
// Independence with spike height (driven by bass_energy_dev) is load-bearing:
// calm-body-with-spikes and agitated-body-without-spikes must both be reachable.
static inline float fo_swell_scale(constant FeatureVector& f,
                                   constant StemFeatures& stems) {
    float blend = fo_stem_warmup_blend(stems);
    // drums proxy during warmup: beat_bass is a weak surrogate so motion
    // continues to read at silence; deviation primitive takes over once stems land.
    float drumsProxy = f.beat_bass * 0.3;
    float drumsStem  = max(0.0, stems.drums_energy_dev);
    float drums      = mix(drumsProxy, drumsStem, blend);
    return 0.4
         + 0.6 * smoothstep(-0.5, 0.5, f.arousal)
         + 0.3 * drums;
}

// MARK: - Gerstner macro displacement
//
// Preset-level per `mat_ocean` (§4.14) convention. 4 superposed waves; Session 4
// may extend to 6. Time source is `f.accumulated_audio_time` (FeatureVector
// field 25) — energy-weighted clock that breathes with the music (CLAUDE.md
// Failed Approach #33 prohibits free-running sin(time)).
//
// Per-wave parameters: direction, wavelength, base amplitude, speed.

struct FOGerstnerWave {
    float2 dir;        // unit direction in xz
    float wavelength;  // metres between successive crests
    float amplitude;   // base (pre-audio-scale) amplitude
    float speed;       // angular speed scalar applied to t
};

// Wave parameter table — 4 waves at varying scales/directions to break
// periodicity. Lengths span 0.8–4.0; smaller waves carry smaller amplitudes
// per Gerstner steepness convention so the surface stays differentiable.
static inline FOGerstnerWave fo_wave(int i) {
    FOGerstnerWave w;
    switch (i) {
        default:
        case 0:
            w.dir        = normalize(float2(1.0, 0.3));
            w.wavelength = 4.0;
            w.amplitude  = 0.15;
            w.speed      = 0.4;
            break;
        case 1:
            w.dir        = normalize(float2(-0.5, 1.0));
            w.wavelength = 2.5;
            w.amplitude  = 0.10;
            w.speed      = 0.6;
            break;
        case 2:
            w.dir        = normalize(float2(0.8, -0.6));
            w.wavelength = 1.5;
            w.amplitude  = 0.06;
            w.speed      = 0.9;
            break;
        case 3:
            w.dir        = normalize(float2(-0.9, -0.4));
            w.wavelength = 0.8;
            w.amplitude  = 0.03;
            w.speed      = 1.3;
            break;
    }
    return w;
}

// Sum vertical displacement at world xz; t is accumulated_audio_time.
// swellScale multiplies every wave's amplitude uniformly.
static inline float fo_gerstner_swell(float2 xz, float t, float swellScale) {
    float y = 0.0;
    for (int i = 0; i < 4; i++) {
        FOGerstnerWave w = fo_wave(i);
        float k     = FO_TWO_PI / max(w.wavelength, 0.001);
        float phase = dot(w.dir, xz) * k - w.speed * t;
        y += (w.amplitude * swellScale) * cos(phase);
    }
    return y;
}

// MARK: - V.9 Session 4 detail-layer constants
//
// Phase A holds the strength scalars at the descriptor JSON's baseline values
// (see FerrofluidOcean.json — `ferrofluid` block). Phase B replaces these with
// audio-modulated formulas; the MSL constants are kept synchronised with the
// JSON defaults so the Swift-side descriptor and the shader-side render agree
// when the JSON block is absent.
//
// Failed Approach #42/#43 guard: all fbm scales below stay clear of the
// lattice-point-degeneracy regime — fbm4(p * 2.0) reads in the multi-octave
// "many lattice crossings per unit" range where degeneracy does not apply.

constant float FO_MESO_WARP_SCALE        = 2.0;     // fbm sample scale
constant float FO_MESO_WARP_AMPLITUDE    = 0.15;    // displacement amplitude (m)
constant float FO_DROPLET_RADIUS         = 0.04;    // droplet sphere radius (m)
constant float FO_DROPLET_APEX_FRACTION  = 0.6;     // bead-center offset above spike apex (× radius)
constant float FO_SMOOTH_UNION_K         = 0.04;    // smooth_min blend k for droplet/surface composition

// MARK: - Meso domain warp (Session 4 Phase A)
//
// Two-component 2-octave fBM warp on world xz at scale FO_MESO_WARP_SCALE.
// Cost: 2 × fbm4 = ~8 Perlin evaluations per call; called once per SDF sample
// inside `fo_ferrofluid_field` (early-exited on silence so cost is zero at
// silence). Phase B will multiply the amplitude by an `f.mid_att_rel`-derived
// envelope; the formula `0.5 + 1.5 × max(0, midAttRel)` at midAttRel=0 gives
// 0.5 (a baseline turbulence), at midAttRel=1 gives 2.0 (peak turbulence) —
// the visual reading is "surface gets choppier when mids thicken."
//
// The output range of fbm4 is approximately [-0.7, 0.7]; multiplied by
// FO_MESO_WARP_AMPLITUDE (0.15) and strength (Phase A: 1.0) gives a
// displacement of ±0.105 m on top of the spike sample position. At the §4.6
// hex-cell scale 4.0 (cell spacing 0.25 m), the warp covers ~42% of a cell —
// distinct visual flow without the lattice losing its hex character.

static inline float2 fo_meso_warp(float2 xz, float strength) {
    if (strength <= 0.0) return float2(0.0);
    float2 warpOffset = float2(
        fbm4(float3(xz * FO_MESO_WARP_SCALE,                      0.0)),
        fbm4(float3(xz * FO_MESO_WARP_SCALE + float2(5.2, 1.3),   0.0))
    );
    return warpOffset * FO_MESO_WARP_AMPLITUDE * strength;
}

// MARK: - Rosensweig spike field
//
// SHADER_CRAFT §4.6 recipe. Voronoi-based hex-like cell centres + per-cell jitter
// + per-cell time-animated phase. fieldStrength routed from stems.bass_energy_dev
// (via fo_spike_strength). Session 4 wraps the sample position in the meso
// domain warp (`fo_meso_warp`) so the lattice reads as turbulent flow rather
// than a frozen hex grid.
//
// Voronoi sampled on (warped) world xz at scale 4.0. Per-cell jitter from fbm8
// seeded by cell centre keeps spike heights varied across cells.

static inline float fo_ferrofluid_field(float3 p, float fieldStrength, float t,
                                        float mesoStrength) {
    if (fieldStrength <= 0.0) return 0.0;
    // Phase A meso domain warp: perturb sample position by 2-octave fbm
    // before sampling the Voronoi spike lattice. Visual: turbulent flow on
    // the spike pattern rather than a perfectly-tiled hex grid (§3.4).
    float2 xz = p.xz + fo_meso_warp(p.xz, mesoStrength);
    VoronoiResult v = voronoi_f1f2(xz, 4.0);
    // Per-cell jitter from fBM seeded by cell centre.
    float jitter = fbm8(float3(v.pos * 2.0, 0.0)) * 0.3;
    float d = v.f1 + jitter * 0.05;
    // Conical spike profile with bell-curve falloff (§4.6).
    float spike = exp(-d * d * 40.0);
    // Time-animated per-cell phase: cell hash → unique phase per spike.
    float cellPhase = float(v.id & 0xFFFF) * (FO_TWO_PI / float(0xFFFF));
    spike *= 0.5 + 0.5 * sin(t * 0.8 + cellPhase);
    return spike * fieldStrength * 0.15;
}

// MARK: - Cassie-Baxter spike-tip droplet field (Session 4 Phase A)
//
// Hemispherical SDF beads sitting on top of each tall spike apex. Composed
// into sceneSDF via op_smooth_union with the height-field swell+spikes
// surface; the blend k = FO_SMOOTH_UNION_K (0.04 m) keeps the meeting line
// between bead and spike rounded rather than creased.
//
// Approximations (acceptable at the cell scale of 0.25 m relative to the
// 4–14 m camera distance):
//   - Cell-center xz approximated as `p.xz` (cell width 0.25 m); the
//     resulting horizontal-distance error to the actual cell center is
//     bounded by `v.f1`, which is what we already use.
//   - Apex Y approximated as `swellHere + fieldStrength × 0.15` (the maximum
//     spike apex value from `fo_ferrofluid_field`). Per-cell variation in
//     time-animated phase produces some shorter spikes that won't have a
//     droplet sitting above; in those cells the droplet sphere will float
//     above the actual spike surface (visible as a separate bead) — which
//     is exactly the Cassie-Baxter visual goal at low droplet strength.
//
// Early exit at silence (both `fieldStrength` and `dropletStrength` collapse
// to 0) returns a far-away SDF (1e6), making the smooth_union pass-through
// to the surface SDF. Failed Approach #42/#43 guard: fbm scales match the
// meso-warp recipe so the warped XZ here remains within the warp-coverage
// budget of the spike sample.

static inline float fo_droplet_sdf(float3 p,
                                   float fieldStrength,
                                   float dropletStrength,
                                   float mesoStrength,
                                   float swellHere) {
    if (dropletStrength <= 0.0 || fieldStrength <= 0.0) return 1e6;
    // Same xz-warp as the spike field — droplets co-locate with warped spikes.
    float2 xz = p.xz + fo_meso_warp(p.xz, mesoStrength);
    VoronoiResult v = voronoi_f1f2(xz, 4.0);
    // Max spike apex value for this cell strength (per fo_ferrofluid_field).
    float apexHeight = fieldStrength * 0.15;
    float apexY = swellHere + apexHeight;
    // Hemispherical bead sits proud of the apex by ~half a radius.
    float radius = FO_DROPLET_RADIUS * dropletStrength;
    float centerY = apexY + radius * FO_DROPLET_APEX_FRACTION;
    // Horizontal distance to cell center ≈ v.f1; vertical to bead center.
    float dxz = v.f1;
    float dy  = p.y - centerY;
    return sqrt(dxz * dxz + dy * dy) - radius;
}

// MARK: - sceneSDF
//
// Composes Gerstner swell (base height) with Rosensweig spike field (riding on
// top). Returns signed distance to the surface from world point p.
//
// Independence contract (D-124(d)): swell amplitude (arousal + drums) and
// spike height (bass) are routed from disjoint primitives. Both states —
// calm-body-with-spikes and agitated-body-without-spikes — are reachable.
//
// Surface is opaque; everything below is solid. No transmission, no walls,
// no contained dish — the surface extends to the camera's far plane.

// Phase A: hardcoded baseline strengths matching the FerrofluidOcean.json
// `ferrofluid` block defaults. Phase B will replace these with audio-modulated
// formulas (`mid_att_rel`-derived for meso; `bass_att_rel`-derived for droplet).
// Keeping these as `static inline` lets the optimiser fold them into call sites
// at Phase A cost; Phase B will swap them for parameterised inputs.

static inline float fo_meso_strength_phaseA() { return 1.0; }
static inline float fo_droplet_strength_phaseA() { return 1.0; }

static inline float fo_surface_height(float3 p,
                                      constant FeatureVector& f,
                                      constant StemFeatures& stems,
                                      thread float& outSwellOnly) {
    float t      = f.accumulated_audio_time;
    float swell  = fo_gerstner_swell(p.xz, t, fo_swell_scale(f, stems));
    float spikes = fo_ferrofluid_field(p, fo_spike_strength(f, stems), t,
                                       fo_meso_strength_phaseA());
    outSwellOnly = swell;
    return swell + spikes;
}

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems) {
    (void)s;
    // Surface (swell + meso-warped spikes) as a height-field SDF.
    float swellOnly = 0.0;
    float surfaceY  = fo_surface_height(p, f, stems, swellOnly);
    float surfaceSdf = p.y - surfaceY;

    // Cassie-Baxter droplet 3D SDF blended via op_smooth_union. At silence
    // (fieldStrength = 0) the droplet SDF returns 1e6 and the smooth_union
    // collapses to the surface SDF (silence-state semantics: no beads on a
    // calm body). Phase A holds the droplet strength at the JSON baseline.
    float dropletSdf = fo_droplet_sdf(p,
                                      fo_spike_strength(f, stems),
                                      fo_droplet_strength_phaseA(),
                                      fo_meso_strength_phaseA(),
                                      swellOnly);
    return op_smooth_union(surfaceSdf, dropletSdf, FO_SMOOTH_UNION_K);
}

// MARK: - sceneMaterial (Session 3: §5.8 stage-rig dispatch via matID == 2)
//
// Pitch-black near-mirror substrate per §4.6 ferrofluid baseline. The
// per-light Cook-Torrance evaluation + wavelength-dependent thin-film F0
// are computed in the matID == 2 branch of `raymarch_lighting_fragment`
// (RayMarch.metal) — that branch has access to the view vector, surface
// normal, AND the slot-9 stage-rig buffer (D-125) which sceneMaterial does
// not. The role of this function is to declare the material *kind* (albedo,
// roughness, metallic + matID dispatch) so the lighting pass can apply the
// right BRDF.
//
// Session 3 switches outMatID from 3 → 2 per the V.9 Session 3 prompt; the
// matID == 3 single-light thin-film branch is retained in RayMarch.metal as
// a fallback for future presets that want the iridescent material without
// the multi-light rig. The thin-film F0 helper (`rm_thinfilm_rgb`) is shared
// between the matID == 2 and matID == 3 branches.

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
    (void)p; (void)matID; (void)f; (void)s; (void)stems; (void)lumen;
    // TODO(V.9 Session 4): audio-modulated thin-film thickness (deviation
    // primitives per D-026) + domain-warped meso detail + micro normal
    // perturbation + Cassie-Baxter spike-tip droplets. All routed through
    // D-026 deviation primitives; no absolute-threshold patterns.
    albedo    = float3(0.02, 0.03, 0.05);  // §4.6 ferrofluid base
    roughness = 0.08;                       // near-mirror
    metallic  = 1.0;
    outMatID  = 2;                          // §5.8 stage-rig dispatch (D-125)
}
