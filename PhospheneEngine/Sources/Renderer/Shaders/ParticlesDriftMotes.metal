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
// AUDIO COUPLING (post-DM.3):
//   The kernel reads stems and FeatureVector at emission time AND at
//   integration time:
//     • Emission time (respawn branch):
//       - Hue baked once per particle, selected by the D-019 warmup blend
//         `smoothstep(0.02, 0.06, totalStemEnergy)`. Cold stems use a
//         per-particle hash jitter around warm amber lightly modulated by
//         `f.mid_att_rel`; warm stems use `dm_pitch_hue(vocals_pitch_hz,
//         vocals_pitch_confidence)` (octave-wrapped log mapping).
//       - Lifetime scaled by `1 / (1 + kEmissionRateGain * f.mid_att_rel)`
//         (positive `mid_att_rel` only) so peak melody compresses cycle
//         frequency without changing the 800-particle field density (DM.3).
//     • Integration time (every frame, every particle):
//       - Drum dispersion shock — `smoothstep(0.30, 0.70, stems.drums_beat)`
//         gate × `kDispersionShockGain` × `dt` adds a radial outward
//         velocity impulse in the horizontal plane with a small +Y lift.
//         The beat-detector envelope provides natural decay; damping
//         settles the field back into wind drift between beats (DM.3).
//   Wind/turbulence motion is still audio-independent through DM.3.
//   DM.4 will add `f.bass_att_rel` × wind, valence-tinted backdrop, and
//   anticipatory shaft pulse on `f.beat_phase01`.
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

// DM.3 audio-coupling tuning constants.
// Match the scope and naming of the DM.2.closeout fog constants in
// `DriftMotes.metal` so M7 retuning has one consistent surface area
// across the preset/engine pair.
//
// kEmissionRateGain: lifetime divisor at emission time. With mid_att_rel
// at peak (≈ 0.5 deviation), lifetime = base / (1 + 0.75) = base × 0.57
// — the cycle runs ~1.75× faster, more shimmer, no density change.
constexpr constant float kEmissionRateGain   = 1.5f;
// kDispersionShockGain: per-frame radial impulse magnitude, gated by the
// drums_beat envelope. Tuned against the wind baseline (0.3) so beats
// produce a visible 'lift' without dispersing the field permanently;
// damping (0.97) brings the field back into wind drift between beats.
constexpr constant float kDispersionShockGain = 0.4f;

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

    // DM.3 Task 1 — emission rate scaling. Lifetime divisor at respawn time.
    // Clamp `mid_att_rel` to non-negative so quiet sections do not extend
    // lifetime (the deviation primitive is signed in [-0.5, 0.5]; we use
    // the positive half as a 'melody peaks' driver). Linear in mid_att_rel
    // — D-026-compliant by construction (no smoothstep, no absolute
    // threshold).
    float midRelPositive = max(0.0, features.mid_att_rel);
    float emissionFactor = 1.0 / (1.0 + kEmissionRateGain * midRelPositive);

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
        p.life  = (mc.lifeMin + mc.lifeRange * dm_hash_f01(float(id) * 0.31831))
                  * emissionFactor;
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

    // DM.3 Task 2 — drum dispersion shock. The BeatDetector envelope on
    // `stems.drums_beat` rises on onset and decays over ~200 ms. Smoothstep
    // gates against the noisy tail; on a clear beat we add a radial
    // outward impulse in the horizontal (xz) plane with a small +y lift
    // so beats visually 'lift' the field. VolumetricLithograph uses the
    // same `smoothstep(0.30, 0.70, stems.drums_beat)` gate (D-101); the
    // absolute threshold on the per-stem onset signal is D-026-allowed
    // (D-026 targets FV raw bands, not stem onset envelopes).
    float beatGate = smoothstep(0.30, 0.70, stems.drums_beat);
    if (beatGate > 0.0) {
        float horizLen = sqrt(pos.x * pos.x + pos.z * pos.z);
        float3 outward = (horizLen > 0.001)
            ? float3(pos.x / horizLen, 0.2, pos.z / horizLen)
            : float3(0.0, 1.0, 0.0);
        vel += outward * (beatGate * kDispersionShockGain * dt);
    }

    pos = pos + vel * dt;

    p.position = packed_float3(pos.x, pos.y, pos.z);
    p.velocity = packed_float3(vel.x, vel.y, vel.z);

    // Hold size constant at sprite render time (set at emission).
    if (p.size < 0.5) {
        p.size = 6.0;
    }

    p.age += dt;
    if (p.life <= 0.001) {
        p.life = (mc.lifeMin + mc.lifeRange * dm_hash_f01(float(id) * 0.31831))
                 * emissionFactor;
    }
    particles[id] = p;
}

// MARK: - Vertex Shader

struct MotesVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
    float life;
    // Particle position in the sky fragment's UV convention (top-left origin,
    // y down). Used by the fragment to compute distance to the shaft axis so
    // motes inside the beam glow brighter than motes drifting in the floor
    // fog. Same UV space as `drift_motes_sky_fragment`'s `in.uv`, so the
    // sun-anchor coordinates `(-0.15, 1.20)` match between the two shaders.
    float2 particleUV;
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
    float clipX = p.position.x * scale;
    float clipY = p.position.y * scale;
    out.position = float4(clipX, clipY, 0.0, 1.0);

    // Convert clip space → sky UV space (y flipped to match `fullscreen_vertex`).
    // Particles outside [-1, 1] clip space land outside [0, 1] UV; the fragment
    // discards them at point-size cull, but the shaft math still works on
    // off-screen UVs (sunUV is itself off-screen at -0.15, 1.20).
    out.particleUV = float2(clipX * 0.5 + 0.5, 0.5 - clipY * 0.5);

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

    // ── Shaft-proximity brightness modulation (DM.2) ─────────────────────
    // Sun anchor matches the sky fragment so the per-mote highlight stays
    // congruent with the beam in the backdrop. The shaft axis runs from
    // sunUV through frame centre (0.5, 0.5); brightness peaks on-axis and
    // falls off to a baseline outside the cone, producing the visual
    // reading of "the beam picks out individual motes as they cross it."
    const float2 sunUV    = float2(-0.15, 1.20);
    float2 shaftDir   = normalize(float2(0.5, 0.5) - sunUV);
    float2 toMote     = in.particleUV - sunUV;
    float  alongShaft = dot(toMote, shaftDir);
    float  perpDist   = length(toMote - alongShaft * shaftDir);
    float  shaftLit   = exp(-perpDist * perpDist * 16.0);
    float  brightness = 0.45 + shaftLit * 0.85;

    // Per-particle hue is baked at emission (DM.2 Task 1) and varies across
    // the field — fragment just modulates intensity here.
    float3 rgb = in.color.rgb * 0.55 * brightness;
    return float4(rgb * alpha, alpha);
}
