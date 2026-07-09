// RicercarFlow.metal — audio-reactive glowing particle flow-field (RICERCAR-FL.10, the Fantasia rebuild).
//
// The lineage is Robert Hodgin's *Magnetosphere* (iTunes visualizer) + the curl-noise glowing-particle
// standard: thousands of particles advected through curl-noise turbulence + audio force fields, each
// carrying an instrument-family colour, deposited as ADDITIVE glowing sprites into an HDR trail texture
// that decays each frame — the deposit-and-fade trail IS the glowing weaving ribbon of light. Tonemapped
// luminous over a deep/dark ground (T&F spirit; RICERCAR_DESIGN §FANTASIA REBUILD).
//
// Why this and not the rejected fluid dye (FL.8) / drawn voices (FL.9): a dye field has an inherent
// ~233 ms accumulation lag and static position; particles are DIRECT and zero-lag — they surge and
// scatter WITH the music. Ported technique, not an invented primitive (CLAUDE.md FA #64/#73).
//
// Per frame (RicercarFlowGeometry drives the passes):
//   1. compute: `ricercar_flow_update` advects every particle (curl noise × flow-speed + homeward pull
//      + beat scatter impulse), wraps toroidally, respawns aged particles at their family band.
//   2. render into trail[next]: draw 1 = `ricercar_flow_decay_fragment` lays down trail[cur] × decay
//      (opaque); draw 2 = `ricercar_flow_point_*` deposits each particle as a soft additive glow sprite.
//   3. display: `ricercar_flow_display_fragment` tonemaps trail[next] → luminous over the deep ground.
//
// VertexOut / fullscreen_vertex come from Common.metal (one combined compilation unit). Do NOT redefine.

#include <metal_stdlib>
using namespace metal;

// MARK: - FlowConfig (mirror of Swift RicercarFlowConfig — 4 uint + 16 float, all 4-byte, no padding)

struct FlowConfig {
    uint  width;
    uint  height;
    uint  particleCount;
    uint  frame;            // per-frame RNG salt
    float dt;               // clamped frame dt (seconds) — envelope integration only; motion is per-frame
    float time;             // accumulated seconds (curl-noise animation clock)
    float flowSpeed;        // curl-noise swirl strength (the coherent texture ON each family's drift)
    float turbulence;       // energy-driven curl-noise spatial frequency
    float decay;            // per-frame trail multiply (the fade → light-trail length)
    float exposure;         // display tonemap gain
    float homePull;         // spring gain toward each family's home band (loose spatial identity)
    // Per-family HYBRID activity env 0..1 (max of the mapped real-time band-stem dev and the instrument-
    // family capture dev) — drives BOTH the family's colour brightness AND its motion vigour (below).
    float famStrings;       //   strings (violet)   ← vocals-stem | strings-section
    float famBrass;         //   brass   (gold)     ← bass-stem   | brass-section
    float famWoodwinds;     //   woodwinds (amber)  ← other-stem  | woodwinds-section
    float famPercussion;    //   percussion (cyan)  ← drums-stem  | percussion-section
    float pointSize;        // base sprite size (px in the trail texture)
    float baseGlow;         // floor deposit so a silent family still faintly drifts
    float energyGlow;       // deposit gain from the global zero-lag energy (louder = brighter light)
    float energy;           // smoothed zero-lag energy 0..~1 (brightness driver)
    float aspect;           // width/height, to keep curl cells round in sample space
    // Per-family GLOBAL drift — each colour follows its OWN shared current (its own direction, turning
    // slowly; its own speed = that family's activity env). So each colour moves DIFFERENTLY, driven by
    // its own separated instrument — smooth, no beat pump (Matt FL.12). Indexed by family 0..3.
    float d0x; float d0y;   // strings
    float d1x; float d1y;   // brass
    float d2x; float d2y;   // woodwinds
    float d3x; float d3y;   // percussion
    // Per-family ARTICULATION 0..1 (FL.14): 0 = legato/sustained → long particle life → long flowing
    // ribbons; 1 = staccato/sharp → short life → frequent respawn → short choppy line segments. Read only
    // at respawn (motion untouched → no herky-jerky, FL.12). Derived from each stem's AttackRatio on the CPU.
    float art0;   // strings   ← vocals-stem AttackRatio
    float art1;   // brass     ← bass-stem   AttackRatio
    float art2;   // woodwinds ← other-stem  AttackRatio
    float art3;   // percussion← drums-stem  AttackRatio
};

// MARK: - FlowParticle (mirror of Swift FlowParticle, 32 bytes — two float4, no alignment trap)

struct FlowParticle {
    float4 posVel;   // pos.xy in [0,1] trail space, vel.xy in fraction/frame
    float4 misc;     // family(0..3 as float), age(s), life(s), seed(0..1)
};

// MARK: - Family identity (colour + home band)

// Emissive family hues, tuned to read LUMINOUS over the deep ground (additive → they can bloom to white).
// Order matches InstrumentFamily.allCases / the Swift palette: strings, brass, woodwinds, percussion.
static inline float3 flow_family_hue(int fam) {
    switch (fam) {
        case 0:  return float3(0.55, 0.45, 1.00);   // strings   — luminous blue-violet
        case 1:  return float3(1.00, 0.78, 0.30);   // brass     — burnished gold
        case 2:  return float3(1.00, 0.52, 0.26);   // woodwinds — warm amber/russet
        default: return float3(0.35, 0.95, 1.00);   // percussion— bright cyan/teal
    }
}

// Loose vertical home for each family so the sections occupy distinct regions (the "voices" read) while
// curl noise still lets them weave and cross. y measured 0 (bottom) → 1 (top) in trail space.
static inline float flow_family_homeY(int fam) {
    switch (fam) {
        case 0:  return 0.42;   // strings   — mid
        case 1:  return 0.24;   // brass     — low
        case 2:  return 0.58;   // woodwinds — upper-mid
        default: return 0.78;   // percussion— high
    }
}

static inline float flow_family_activation(constant FlowConfig& cfg, int fam) {
    switch (fam) {
        case 0:  return cfg.famStrings;
        case 1:  return cfg.famBrass;
        case 2:  return cfg.famWoodwinds;
        default: return cfg.famPercussion;
    }
}

static inline float flow_family_articulation(constant FlowConfig& cfg, int fam) {
    switch (fam) {
        case 0:  return cfg.art0;
        case 1:  return cfg.art1;
        case 2:  return cfg.art2;
        default: return cfg.art3;
    }
}

// FL.14 line character: particle life scales inversely with articulation. Legato/sustained (art→0) gives a
// long life ⇒ each particle traces a long continuous ribbon; staccato/sharp (art→1) gives a short life ⇒
// particles respawn constantly ⇒ the family reads as short, choppy, restless segments. Only the RESPAWN
// cadence changes — per-frame motion is identical either way, so this never reintroduces the FL.12
// herky-jerky (which came from disrupting MOTION). ~16 s legato ≈ the pre-FL.14 seeded life, so the
// no-articulation-signal look (silence / warmup / harness) is unchanged. Life interpolates GEOMETRICALLY
// (life is a timescale) so mid-range articulation already reads choppy — a linear mix left art≈0.5 at ~8 s
// (still flowing); geometric puts art≈0.5 at ~3.5 s. FL.14.1 calibration (first live miss was all-legato).
static constexpr constant float kFlowLegatoLife  = 16.0;   // seconds — long flowing ribbons
static constexpr constant float kFlowStaccatoLife = 0.75;  // seconds — short choppy segments

// MARK: - Hash + curl noise (Bridson 2007 — curl of a scalar noise potential = divergence-free flow)

static inline float flow_hash21(float2 p) {
    p = fract(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

static inline float flow_vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = flow_hash21(i);
    float b = flow_hash21(i + float2(1.0, 0.0));
    float c = flow_hash21(i + float2(0.0, 1.0));
    float d = flow_hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal scalar potential, slowly drifting in time so the field itself evolves.
static inline float flow_potential(float2 p, float t) {
    float v = 0.0, amp = 0.5, freq = 1.0;
    for (int o = 0; o < 3; ++o) {
        v += amp * flow_vnoise(p * freq + float2(t * 0.10 * freq, -t * 0.07 * freq));
        amp *= 0.5;
        freq *= 2.0;
    }
    return v;
}

// 2D curl of the potential → a divergence-free velocity (swirls, no sources/sinks).
static inline float2 flow_curl(float2 p, float t) {
    const float e = 0.012;
    float dy = flow_potential(p + float2(0.0, e), t) - flow_potential(p - float2(0.0, e), t);
    float dx = flow_potential(p + float2(e, 0.0), t) - flow_potential(p - float2(e, 0.0), t);
    return float2(dy, -dx) / (2.0 * e);
}

// MARK: - Compute: advect every particle

kernel void ricercar_flow_update(device FlowParticle*  particles [[buffer(0)]],
                                 constant FlowConfig&  cfg       [[buffer(1)]],
                                 uint gid [[thread_position_in_grid]]) {
    if (gid >= cfg.particleCount) { return; }
    FlowParticle p = particles[gid];
    float2 pos = p.posVel.xy;
    float2 vel = p.posVel.zw;
    int  fam  = int(round(p.misc.x));
    float age = p.misc.y + cfg.dt;
    float seed = p.misc.w;

    // FL.14 per-family life from articulation (recomputed each frame from the CURRENT smoothed env, so a
    // section turning staccato shortens life immediately — long-lived legato particles respawn NOW instead
    // of waiting out a stale seeded life). Per-particle ±spread via `seed` so respawns stagger (no synced
    // pulse). The seeded p.misc.z is superseded by this and left unread.
    float staccato = flow_family_articulation(cfg, fam);
    float life = kFlowLegatoLife * pow(kFlowStaccatoLife / kFlowLegatoLife, staccato) * (0.6 + 0.8 * seed);

    // SHARED curl-noise swirl — NO per-particle seed offset, so neighbours sample the SAME field and move
    // TOGETHER as coherent currents (the seed offset made every line move in its own random direction →
    // "a bunch of things happening at once", Matt FL.11). Normalised so flowSpeed is the step size (the
    // raw finite-difference gradient is uncontrolled). This is the swirl TEXTURE on top of the drift.
    float2 sp = float2(pos.x * cfg.aspect, pos.y) * (1.5 + cfg.turbulence);
    float2 c = flow_curl(sp, cfg.time);
    float cm = length(c);
    float2 swirl = (cm > 1e-5 ? c / cm : float2(0.0)) * cfg.flowSpeed;

    // PER-FAMILY drift — each colour follows its OWN shared current (its own direction + speed, computed
    // on the CPU from that family's activity). Neighbours in the same family move together (coherent), but
    // each colour moves DIFFERENTLY, driven by its own separated instrument. Smooth (no beat pump).
    float2 drift;
    if      (fam == 0) { drift = float2(cfg.d0x, cfg.d0y); }
    else if (fam == 1) { drift = float2(cfg.d1x, cfg.d1y); }
    else if (fam == 2) { drift = float2(cfg.d2x, cfg.d2y); }
    else               { drift = float2(cfg.d3x, cfg.d3y); }

    // Loose homeward pull toward the family band → colour-band identity without freezing the weave.
    float homeY = flow_family_homeY(fam);
    float2 home = float2(0.0, homeY - pos.y) * cfg.homePull;

    // Integrate: ease velocity toward the shared target, step, then wrap in a domain slightly LARGER than
    // the [0,1] view. Wrapping exactly at the view edge makes every crossing deposit at BOTH seam edges →
    // the visible edges/corners double-accumulate into bright bands (the FL.10 corner hotspot). Wrapping at
    // ±margin puts the seam off-screen (clipped), so the visible edges stay clean.
    float2 target = drift + swirl + home;
    vel = mix(vel, target, 0.18);
    pos += vel;
    const float2 lo = float2(-0.07), span = float2(1.14);
    pos = lo + fract((pos - lo) / span) * span;   // wrap into [-0.07, 1.07); the margin is off-screen

    // Respawn aged particles at their family band (fresh x, small jitter in y) so trails keep renewing
    // and each family stays anchored to its region even as the field carries older particles away.
    if (age > life) {
        float rx = flow_hash21(float2(float(gid) * 0.013, cfg.time + seed));
        float ry = flow_hash21(float2(cfg.time * 1.7 + seed, float(gid) * 0.029));
        pos = float2(rx, clamp(homeY + (ry - 0.5) * 0.22, 0.02, 0.98));
        vel = float2(0.0, 0.0);
        age = 0.0;
    }

    p.posVel = float4(pos, vel);
    p.misc.y = age;
    particles[gid] = p;
}

// MARK: - Render draw 1: decay the previous trail into the current target (opaque, no blend)

fragment float4 ricercar_flow_decay_fragment(VertexOut in [[stage_in]],
                                             constant FlowConfig& cfg [[buffer(0)]],
                                             texture2d<float, access::sample> trail [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear, coord::normalized);
    float3 prev = trail.sample(s, in.uv).rgb;
    return float4(prev * cfg.decay, 1.0);
}

// MARK: - Render draw 2: deposit each particle as a soft additive glow sprite

struct FlowPointOut {
    float4 position [[position]];
    float  pointSize [[point_size]];
    float3 color;
};

vertex FlowPointOut ricercar_flow_point_vertex(uint vid [[vertex_id]],
                                               device const FlowParticle* particles [[buffer(0)]],
                                               constant FlowConfig& cfg [[buffer(1)]]) {
    FlowParticle p = particles[vid];
    float2 pos = p.posVel.xy;
    int fam = int(round(p.misc.x));

    FlowPointOut o;
    // Trail space (0..1) → clip. y up in clip; the display samples with the matching convention.
    o.position = float4(pos.x * 2.0 - 1.0, pos.y * 2.0 - 1.0, 0.0, 1.0);

    // Deposit brightness (kept small — it accumulates ~1/(1−decay)× in the trail): a tiny floor so the
    // flow is never fully dark, + a small shared zero-lag energy floor, + THIS family's own hybrid
    // activity env (so the colour BRIGHTENS when its own instrument plays — the same per-family signal
    // that drives its motion). Smooth, continuous — no beat pump (Matt FL.12).
    float activation = flow_family_activation(cfg, fam);
    float bright = cfg.baseGlow + cfg.energy * cfg.energyGlow * 0.5 + activation * 0.70;
    o.color = flow_family_hue(fam) * bright;
    o.pointSize = cfg.pointSize;
    return o;
}

fragment float4 ricercar_flow_point_fragment(FlowPointOut in [[stage_in]],
                                             float2 pc [[point_coord]]) {
    // Soft radial sprite: a smooth Gaussian-ish falloff (no sharp core) so overlapping deposits blend
    // into continuous smooth ribbons rather than a dotted crosshatch. Additive blend (one/one) in the PSO.
    float d = length(pc - 0.5) * 2.0;          // 0 centre → 1 edge
    float w = smoothstep(1.0, 0.0, d);
    w *= w;                                     // soft shoulder, smooth tail
    return float4(in.color * w, w);
}

// MARK: - Display: tonemap the HDR trail → luminous over the deep ground

fragment float4 ricercar_flow_display_fragment(VertexOut in [[stage_in]],
                                               constant FlowConfig& cfg [[buffer(0)]],
                                               texture2d<float, access::sample> trail [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear, coord::normalized);

    // Cheap wide-tap bloom: a few offset samples widen the halo into a soft glow (the ref-01 light-lines
    // with soft halos), without a separate blur target.
    float2 texel = 1.0 / float2(cfg.width, cfg.height);
    float3 hdr = trail.sample(s, in.uv).rgb;
    float3 bloom = float3(0.0);
    const float2 offs[4] = { float2(3.0, 0.0), float2(-3.0, 0.0), float2(0.0, 3.0), float2(0.0, -3.0) };
    for (int i = 0; i < 4; ++i) { bloom += trail.sample(s, in.uv + offs[i] * texel).rgb; }
    hdr += bloom * 0.4;
    hdr *= cfg.exposure;

    // Filmic-ish tonemap → luminous, saturating gracefully instead of clipping to flat white.
    float3 tone = 1.0 - exp(-hdr);

    // Deep ground: dark indigo with a gentle top-darker vertical gradient (dramatic T&F space).
    float3 groundTop = float3(0.010, 0.012, 0.030);
    float3 groundBot = float3(0.020, 0.022, 0.050);
    float3 ground = mix(groundBot, groundTop, in.uv.y);

    return float4(ground + tone, 1.0);
}
