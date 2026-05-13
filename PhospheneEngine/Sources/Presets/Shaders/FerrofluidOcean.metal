// FerrofluidOcean.metal — V.9 Session 1 macro layer.
//
// Macro layer of the V.9 redirect (D-124): a fixed-camera, ocean-portion-scale
// view of a body of liquid whose surface is replaced by ferrofluid material.
// Gerstner swell drives macro body motion (audible up/down/back/forth even at
// silence); Rosensweig spike-field rides on top, emerging from the swell when
// `stems.bass_energy_dev > 0` and collapsing entirely at silence.
//
// Session 1 implements ONLY:
//   1. Gerstner-wave macro displacement field (4 superposed waves; arousal-baseline
//      + drums_energy_dev accent amplitude).
//   2. Rosensweig hex-tile spike-field SDF per SHADER_CRAFT §4.6 (bass_energy_dev
//      → spike height).
//   3. Composition: spike field rides on top of Gerstner base height.
//   4. Placeholder sceneMaterial (matID == 0, single-light Cook-Torrance path).
//
// Sessions 2–5 add material (mat_ferrofluid + thinfilm_rgb), §5.8 stage-rig
// lighting (D-125: slot-9 buffer + matID == 2), domain-warped meso, micro
// detail, and final audio routing per FERROFLUID_OCEAN_CLAUDE_CODE_PROMPTS.md.
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
// SHADER_CRAFT §4.6 recipe. Voronoi-based hex-like cell centres + per-cell jitter
// + per-cell time-animated phase. fieldStrength routed from stems.bass_energy_dev
// (via fo_spike_strength). Session 4 will add §3.4 domain warp for lattice
// defects; Session 1 uses the §4.6 baseline as-is.
//
// Voronoi sampled on world xz (ocean-portion scale). Scale 4.0 from §4.6.
//
// fbm8 jitter at scale 2.0 stays well clear of the lattice-point-degeneracy
// regime (Failed Approach #43 — scales below 1.0 on unit-coord positions kill
// variance) since v.pos at scale 4.0 lives in [0, 0.25]× and the * 2.0 lift
// keeps the noise sample at scale ≥ 0.5; multi-octave fbm8 has many lattice
// crossings per unit so degeneracy does not apply at scale 0.5+ either.

static inline float fo_ferrofluid_field(float3 p, float fieldStrength, float t) {
    if (fieldStrength <= 0.0) return 0.0;
    float2 xz = p.xz;
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

static inline float fo_surface_height(float3 p,
                                      constant FeatureVector& f,
                                      constant StemFeatures& stems) {
    float t      = f.accumulated_audio_time;
    float swell  = fo_gerstner_swell(p.xz, t, fo_swell_scale(f, stems));
    float spikes = fo_ferrofluid_field(p, fo_spike_strength(f, stems), t);
    return swell + spikes;
}

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems) {
    (void)s;
    return p.y - fo_surface_height(p, f, stems);
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
