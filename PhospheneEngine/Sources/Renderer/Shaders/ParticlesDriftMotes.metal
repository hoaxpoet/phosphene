// ParticlesDriftMotes.metal — Drift Motes compute + sprite shaders (Increment DM.1).
//
// Lives in the engine library as a sibling to Particles.metal. The shared
// `Particle` struct (64 bytes, declared once in Particles.metal) is in scope
// here because ShaderLibrary concatenates every engine .metal source into a
// single MSL translation unit before compilation — see
// `PhospheneEngine/Sources/Renderer/ShaderLibrary.swift` (D-097, DM.1).
// `ParticleConfig` (32 bytes) is similarly shared.
//
// FILENAME NOTE (DM.1): originally drafted as `DriftMotesParticles.metal`,
// but the engine library concatenates `.metal` files in lexicographic order
// inside a single MSL translation unit. `D` < `P`, so a `D`-prefixed filename
// would precede `Particles.metal` and the shared `Particle` struct would not
// yet be in scope. Renaming to `ParticlesDriftMotes.metal` keeps every other
// constraint intact — engine library, no struct duplication, no modification
// to `Particles.metal` (D-020). Documented here and in CLAUDE.md so future
// authors don't reorder the prefix without thinking.
//
// AUDIO COUPLING (post-DM.2):
//   The kernel reads stems and FeatureVector at emission time only. Each
//   particle bakes a hue at respawn that it then carries for life — the
//   field's chromatic texture IS the recent vocal melody. Hue source is
//   selected by the D-019 warmup blend `smoothstep(0.02, 0.06, totalStemEnergy)`:
//     • Cold stems: per-particle hash jitter around warm amber,
//       lightly modulated by `f.mid_att_rel` so the field still moves
//       with the music when stems are zero.
//     • Warm stems: `dm_pitch_hue(vocals_pitch_hz, vocals_pitch_confidence)`
//       (octave-wrapped log mapping, see helper below).
//   Wind/turbulence motion is still audio-independent in DM.2; the
//   emission-rate scaling from `f.mid_att_rel` and the drum dispersion
//   shock from `stems.drums_beat` arrive in DM.3.
//
// CONSTANTS (DriftMotesConfig at buffer(4)):
//   Wind direction, wind magnitude, damping, turbulence amplitude /
//   spatial frequency / time phase, bounds, and life range are bound
//   per frame from the Swift-side `DriftMotesKernelConstants`. Swift
//   is the single source of truth — retuning happens there once. The
//   kernel reads everything from the bound config (no magic numbers).
//
// FORCE FIELD (no flocking — D-097, Failed Approach #57 of CLAUDE.md cues):
//   - Slow downward+leftward base wind: normalize((-1, -0.2, 0)) * 0.3.
//   - Curl-of-fBM turbulence at 4 octaves (≥ SHADER_CRAFT.md noise floor)
//     adds gentle wobble; phase-advance through `time` keeps motion
//     correlated with wall clock without a visible `sin(time)` oscillation
//     (Failed Approach #33 cleared).
//   - Particles recycle on bounds-exit OR age > life: respawn near the
//     top of the shaft volume with the default warm hue; new life picked
//     deterministically from the particle id so the sprite distribution
//     stays well-spread frame to frame.
//
// NEIGHBOR QUERIES: zero. No `for (uint j ...)` loop, no shared-memory
// boid forces, no inter-particle distance reads. Particles are independent.

inline float dm_hash_f01(float n) {
    return fract(sin(n) * 43758.5453);
}

// 3D value noise — periodic, divergence-free-when-curled.
inline float dm_noise3(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n = i.x + i.y * 57.0 + i.z * 113.0;
    float c000 = dm_hash_f01(n);
    float c100 = dm_hash_f01(n +   1.0);
    float c010 = dm_hash_f01(n +  57.0);
    float c110 = dm_hash_f01(n +  58.0);
    float c001 = dm_hash_f01(n + 113.0);
    float c101 = dm_hash_f01(n + 114.0);
    float c011 = dm_hash_f01(n + 170.0);
    float c111 = dm_hash_f01(n + 171.0);
    float x00 = mix(c000, c100, f.x);
    float x10 = mix(c010, c110, f.x);
    float x01 = mix(c001, c101, f.x);
    float x11 = mix(c011, c111, f.x);
    float y0  = mix(x00,  x10,  f.y);
    float y1  = mix(x01,  x11,  f.y);
    return mix(y0, y1, f.z) * 2.0 - 1.0;
}

// 4-octave fBM — meets the SHADER_CRAFT.md noise-octave floor for any
// non-trivial noise field used as a hero motion driver.
inline float dm_fbm4(float3 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * dm_noise3(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

// Curl noise: curl of three independent fBM scalar fields treated as a
// vector potential F = (N1, N2, N3). The curl operator is divergence-free
// by definition, so the resulting flow neither sources nor sinks particles
// — pairwise distances drift but do not collapse toward attractor points.
// The constant offsets decorrelate the three scalar fields so the y- and
// z-components are not just rotations of the x-component.
inline float3 dm_curl_noise(float3 p) {
    const float eps = 0.05;
    float3 dx = float3(eps, 0.0, 0.0);
    float3 dy = float3(0.0, eps, 0.0);
    float3 dz = float3(0.0, 0.0, eps);

    float3 p1 = p;
    float3 p2 = p + float3(31.416, 47.853, 12.793);
    float3 p3 = p + float3(83.227,  9.345, 56.871);

    // Partial derivatives via central differences.
    float dN1_dy = (dm_fbm4(p1 + dy) - dm_fbm4(p1 - dy)) / (2.0 * eps);
    float dN1_dz = (dm_fbm4(p1 + dz) - dm_fbm4(p1 - dz)) / (2.0 * eps);
    float dN2_dx = (dm_fbm4(p2 + dx) - dm_fbm4(p2 - dx)) / (2.0 * eps);
    float dN2_dz = (dm_fbm4(p2 + dz) - dm_fbm4(p2 - dz)) / (2.0 * eps);
    float dN3_dx = (dm_fbm4(p3 + dx) - dm_fbm4(p3 - dx)) / (2.0 * eps);
    float dN3_dy = (dm_fbm4(p3 + dy) - dm_fbm4(p3 - dy)) / (2.0 * eps);

    // curl(F) = (∂N3/∂y - ∂N2/∂z, ∂N1/∂z - ∂N3/∂x, ∂N2/∂x - ∂N1/∂y).
    return float3(
        dN3_dy - dN2_dz,
        dN1_dz - dN3_dx,
        dN2_dx - dN1_dy
    );
}

// DriftMotesConfig — 64 bytes, mirrors `DriftMotesGeometry.DriftMotesConfig`.
// `packed_float3` keeps the layout dense (no 16-byte vector alignment slack)
// so the Swift mirror can be 16 plain `Float`s without alignment hacks.
struct DriftMotesConfig {
    packed_float3 windDirection;
    float         windMagnitude;
    packed_float3 bounds;
    float         dampingPerFrame;
    float         turbScale;
    float         turbSpatialFreq;
    float         turbTimePhase;
    float         lifeMin;
    float         lifeRange;
    float         _pad0;
    float         _pad1;
    float         _pad2;
};

// dm_pitch_hue — vocal pitch (Hz) → hue ∈ [0, 1] (DM.2, supersedes vl_pitchHueShift).
//
// Octave-wrapping log map: A2 (110 Hz) → 0.0 (red); A3 (220 Hz) → 0.25;
// A4 (440 Hz) → 0.5; A5 (880 Hz) → 0.75; A6 (1760 Hz) → 1.0 (red again).
// The 4-octave span keeps a typical vocal melody (one to two octaves) inside
// a coherent hue arc rather than exhausting the colour wheel.
//
// `confidence` gates against noisy pitch readings: YIN's confidence
// estimate dips below 0.6 on consonants and silence, and the
// `vocalsPitchHz = 0` sentinel flows through here as a fallback regardless.
// Below the 0.3 floor we return the cold-stem amber (0.08) so an
// unvoiced frame doesn't paint a particle a wild colour at emission.
//
// Floor of 80 Hz on the input prevents `log2` going negative on
// male-vocal sub-fundamentals or the 0 sentinel.
inline float dm_pitch_hue(float pitchHz, float confidence) {
    if (confidence < 0.3) {
        return 0.08;
    }
    float safePitch = max(pitchHz, 80.0);
    return fract(log2(safePitch / 110.0) / 4.0);
}

// Deterministic per-particle position near the top of the shaft volume.
// Layout: a wide horizontal slab at y near +bounds.y, scattered in x and z
// so motes feed into the shaft path from above as the wind sweeps down
// and leftward.
inline float3 dm_sample_emission_position(uint id, float t, float3 bounds) {
    float seedA = dm_hash_f01(float(id) * 0.1234567);
    float seedB = dm_hash_f01(float(id) * 0.7654321 + t * 0.013);
    float seedC = dm_hash_f01(float(id) * 1.4142136 + t * 0.027);
    float x = (seedA * 2.0 - 1.0) * bounds.x;
    float y = bounds.y * (0.7 + 0.3 * seedB);
    float z = (seedC * 2.0 - 1.0) * bounds.z * 0.5;
    return float3(x, y, z);
}

// MARK: - Compute Kernel

kernel void motes_update(
    device Particle* particles [[buffer(0)]],
    constant FeatureVector& features [[buffer(1)]],
    constant ParticleConfig& config [[buffer(2)]],
    constant StemFeatures& stems [[buffer(3)]],
    constant DriftMotesConfig& mc [[buffer(4)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= config.particleCount) return;

    Particle p = particles[id];
    float dt = features.delta_time;
    float t  = features.time;

    float3 bounds = float3(mc.bounds);

    // Recycle: out of bounds OR aged out.
    float3 pos = float3(p.position.x, p.position.y, p.position.z);
    bool oob = (abs(pos.x) > bounds.x) ||
               (abs(pos.y) > bounds.y) ||
               (abs(pos.z) > bounds.z);
    bool dead = (p.age > p.life);

    if (oob || dead) {
        pos = dm_sample_emission_position(id, t, bounds);
        // Slow downward drift on respawn — wind takes over from there.
        p.velocity = packed_float3(-0.05, -0.4, 0.0);

        // ── D-019 warmup blend at emission (DM.2) ─────────────────────────
        // Hue source is selected once per born particle and never modified
        // afterward. Cold stems use a per-particle hash + `f.mid_att_rel`
        // proxy so the field has intrinsic chromatic texture and still
        // moves with the music when stems are zero. Warm stems substitute
        // the vocal-pitch mapping. The blend ramps over a tiny stems-energy
        // window so the crossover lands within the first stem updates.
        float totalStemEnergy = stems.drums_energy + stems.bass_energy
                              + stems.other_energy + stems.vocals_energy;
        float blend = smoothstep(0.02, 0.06, totalStemEnergy);

        // Cold-stem fallback. baseAmberHue matches the DM.1 sky.
        // perMoteJitter spreads particles around amber by ±0.05 hue (rgb
        // motion through warm-amber → warm-orange → warm-pink range).
        // musicShift nudges the field's mean hue with melody — D-026
        // deviation form, no absolute thresholds.
        float baseAmberHue   = 0.08;
        float perMoteJitter  = (dm_hash_f01(float(id) * 17.0 + t * 0.013) - 0.5) * 0.10;
        float musicShift     = features.mid_att_rel * 0.04;
        float pitchHueCold   = baseAmberHue + perMoteJitter + musicShift;

        // Warm-stem source. Confidence gate handled inside the helper.
        float pitchHueWarm = dm_pitch_hue(stems.vocals_pitch_hz,
                                          stems.vocals_pitch_confidence);

        float bakedHue = mix(pitchHueCold, pitchHueWarm, blend);
        // Saturation/value calibrated against the DM.1 warm-amber sky so
        // motes read as embers in the shaft, not neon dots.
        float3 rgb = hsv2rgb(float3(bakedHue, 0.55, 0.85));
        p.color = packed_float4(rgb.x, rgb.y, rgb.z, 1.0);

        p.age   = 0.0;
        p.life  = mc.lifeMin + mc.lifeRange * dm_hash_f01(float(id) * 0.31831);
        p.position = packed_float3(pos.x, pos.y, pos.z);
        // Skip integration this frame — fresh particle starts clean next tick.
        particles[id] = p;
        return;
    }

    // Base wind: direction + magnitude from buffer(4). DM.3 will scale
    // magnitude by `f.bass_att_rel` at the Swift side before binding.
    float3 wind = normalize(float3(mc.windDirection)) * mc.windMagnitude;

    // Curl-of-fBM turbulence — 4 octaves per fBM, three fields per curl.
    // Phase-advance via `t * turbTimePhase` keeps the field correlated with
    // wall clock without producing a visible `sin(time)` oscillation
    // (Failed Approach #33).
    float3 turb = dm_curl_noise(pos * mc.turbSpatialFreq +
                                float3(0.0, 0.0, t * mc.turbTimePhase)) * mc.turbScale;

    float3 vel = float3(p.velocity.x, p.velocity.y, p.velocity.z);
    vel = vel * mc.dampingPerFrame + (wind + turb) * dt;
    pos = pos + vel * dt;

    p.position = packed_float3(pos.x, pos.y, pos.z);
    p.velocity = packed_float3(vel.x, vel.y, vel.z);

    // Hold size constant at sprite render time (set at emission).
    if (p.size < 0.5) {
        p.size = 6.0;
    }

    p.age += dt;
    if (p.life <= 0.001) {
        p.life = mc.lifeMin + mc.lifeRange * dm_hash_f01(float(id) * 0.31831);
    }
    particles[id] = p;
}

// MARK: - Vertex Shader

struct MotesVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
    float life;
};

vertex MotesVertexOut motes_vertex(
    uint vid [[vertex_id]],
    constant Particle* particles [[buffer(0)]],
    constant FeatureVector& features [[buffer(1)]]
) {
    Particle p = particles[vid];
    MotesVertexOut out;

    // Mirror Murmuration's clip-space scale until visual review surfaces a need
    // to change it. Drift Motes' BOUNDS.x = 8 → screen edge at scale 0.125
    // would compress the field; 2.2 keeps the wide horizontal slab framed.
    const float scale = 2.2 / 8.0;  // BOUNDS.x = 8 maps to clip edge.
    out.position = float4(p.position.x * scale, p.position.y * scale, 0.0, 1.0);

    // 6-px constant point size in DM.1; Session 3 gates on shaft density.
    out.pointSize = (p.life > 0.0 && p.age < p.life) ? 6.0 : 0.0;
    out.color = float4(p.color);
    out.life = p.life - p.age;
    return out;
}

// MARK: - Fragment Shader

fragment float4 motes_fragment(
    MotesVertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    if (in.life <= 0.0) discard_fragment();

    // Soft Gaussian falloff over [[point_coord]] ∈ [0,1]² → centre 0.5.
    float2 d = pointCoord - 0.5;
    float r2 = dot(d, d);                // 0 at centre, ~0.5 at corner.
    if (r2 > 0.25) discard_fragment();   // Clip outside unit disc.

    // Gaussian falloff (sharp at centre, smooth tail). Brightness baked into
    // alpha so additive blend (one+one, set in pipeline state) doesn't blow
    // out the highlights — each mote contributes a fraction of its hue.
    float alpha = exp(-r2 * 18.0);

    // Particle.color is the default warm hue in DM.1 (Session 2 diversifies).
    // Multiply by a fixed scalar to keep additive contribution gentle.
    float3 rgb = in.color.rgb * 0.55;
    return float4(rgb * alpha, alpha);
}
