// FerrofluidOcean.metal — V.9 Session 1–4.5 layered authoring.
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
// Session 4 added three material detail layers (Cassie-Baxter droplets, meso
// domain warp, matID == 2 micro-normal). Session 4 M7 review (2026-05-13)
// rejected all three as decoration without load-bearing musical role per
// Failed Approach #62. Session 4.5 Phase 0 (this revision) reverts all three;
// the surface returns to pure-mirror substrate with Gerstner swell + Rosensweig
// spikes only. The matID == 2 thin-film thickness modulation from Session 4
// Phase B is preserved (subtle, in-vision, was not flagged at M7).
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

// MARK: - Rosensweig spike field
//
// SHADER_CRAFT §4.6 recipe. fieldStrength routed from stems.bass_energy_dev
// (via fo_spike_strength). Session 4.5 rescue: meso domain warp dropped per
// Failed Approach #62; per-cell temporal sin oscillation dropped (Failed
// Approach #33 echo — free-running sin adds motion the music isn't driving;
// the t parameter is consequently absent from this function).
//
// **Session 4.5 final geometry — smooth Voronoi (after desk research).**
// History: I iterated six times on this function trying to eliminate a
// per-cell "dot pattern" in the rendered surface. Each fix was a guess that
// got tested and falsified. Matt eventually pointed out that ferrofluid
// rendering is a solved problem and I should do desk research instead of
// guessing. The desk research found Robert Leitl's audio-reactive WebGL
// ferrofluid project — the closest published reference to Phosphene's use
// case — which builds its height field from Inigo Quilez's **smooth
// Voronoi**. Smooth Voronoi blends distances to all neighbor cells via
// exponential weighting, producing a C¹-continuous height field with no
// boundary normal flips. That's the structural fix for the dot pattern,
// which was rooted in the hard `min()` discontinuity at every cell edge
// in regular Voronoi.
//
// **Session 4.5b Phase 1 (V.9 particle-motion increment): texture-backed.**
// The geometric source moved from inline `voronoi_smooth` to a sample of
// the 512×512 r16Float height texture baked by `ferrofluid_height_bake`
// (`Renderer/Shaders/FerrofluidParticles.metal`). Phase 1 places 2048
// particles at the XZ coordinates a `voronoi_smooth` cell-center pass
// would emit (rectangular int-cell grid + per-cell `voronoi_cell_offset`
// hash; mirrored CPU-side in `FerrofluidParticles.swift`), so the baked
// texture's spike topology is the structural equivalent of the Phase A
// inline path. Phase 2 will add SPH-lite particle motion + audio forces
// so the peaks drift, cluster, and scatter with the music; the sampling
// path here is unchanged across both phases.
//
// References (full set):
//   - Robert Leitl, Ferrofluid Web Experiment:
//     https://robert-leitl.medium.com/ferrofluid-7fd5cb55bc8d
//   - Inigo Quilez, Smooth Voronoi:
//     https://iquilezles.org/articles/smoothvoronoi/
//   - Inigo Quilez, polynomial smooth-min:
//     https://iquilezles.org/articles/smin/
//   - Rosensweig instability video (geometry reference):
//     https://www.youtube.com/watch?v=39oyuJLQt_E
//   - User-supplied still references (hex-pack pointed pyramids)
//
// Texture mapping: the height texture covers the world-XZ rectangle
// [worldOriginX, worldOriginX + worldSpan] × [worldOriginZ, worldOriginZ +
// worldSpan] = [-10, 10] × [-8, 12]. The Phase A inline math is preserved
// as `fo_ferrofluid_field_inline` (below) for diagnostic use; production
// sceneSDF samples via `fo_ferrofluid_field_sampled`.

// World-XZ patch constants — kept in sync with
// `FerrofluidParticles.swift::worldOriginX/Z/Span` via
// `FerrofluidParticlesTests.test_swiftMetalConstantsMatch`.
constant float FO_HEIGHT_WORLD_ORIGIN_X = -10.0;
constant float FO_HEIGHT_WORLD_ORIGIN_Z =  -8.0;
constant float FO_HEIGHT_WORLD_SPAN     =  20.0;

static inline float fo_ferrofluid_field_sampled(float3 p,
                                                float fieldStrength,
                                                texture2d<float> heightTex,
                                                sampler heightSamp) {
    if (fieldStrength <= 0.0) return 0.0;
    // World XZ → UV. Outside [0, 1] the sampler's clamp-to-zero address
    // mode (declared in the preamble's `kFerrofluidHeightSampler`)
    // returns 0 → spike lattice terminates cleanly at the patch edge.
    float u = (p.x - FO_HEIGHT_WORLD_ORIGIN_X) / FO_HEIGHT_WORLD_SPAN;
    float v = (p.z - FO_HEIGHT_WORLD_ORIGIN_Z) / FO_HEIGHT_WORLD_SPAN;
    float spike = heightTex.sample(heightSamp, float2(u, v)).r;
    return spike * fieldStrength * 0.15;
}

// Phase A inline fallback. Retained for diagnostic comparison + the case
// where no height texture is bound (`heightTex.get_width() == 1` ⇒ the
// 1×1 placeholder, returns 0 ⇒ no spikes). Not called from sceneSDF
// today; future increments may A/B between paths via a feature flag.
static inline float fo_ferrofluid_field_inline(float3 p, float fieldStrength) {
    if (fieldStrength <= 0.0) return 0.0;
    constexpr float kVoronoiScale   = 4.0;
    constexpr float kVoronoiSmoothK = 32.0;
    constexpr float kSpikeRadius    = 0.6;
    float smoothD = voronoi_smooth(p.xz, kVoronoiScale, kVoronoiSmoothK);
    float spike   = max(0.0, 1.0 - smoothD / kSpikeRadius);
    return spike * fieldStrength * 0.15;
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

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems,
               texture2d<float> ferrofluidHeight) {
    (void)s;
    float t        = f.accumulated_audio_time;
    float swell    = fo_gerstner_swell(p.xz, t, fo_swell_scale(f, stems));
    float spikes   = fo_ferrofluid_field_sampled(p,
                                                 fo_spike_strength(f, stems),
                                                 ferrofluidHeight,
                                                 kFerrofluidHeightSampler);
    float surfaceY = swell + spikes;
    return p.y - surfaceY;
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
    albedo    = float3(0.02, 0.03, 0.05);  // §4.6 ferrofluid base
    roughness = 0.08;                       // near-mirror
    metallic  = 1.0;
    outMatID  = 2;                          // §5.8 stage-rig dispatch (D-125)
}
