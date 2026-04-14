// Particles.metal — Murmuration: a flock of starlings as one organism.
//
// Audio routing philosophy (Increment 3.5.2):
//   DRUMS  → Turning waves. A beat fires a directional turn that sweeps
//             across the flock over ~200ms — not simultaneous, like real
//             murmurations. The signature visual: a ripple of direction
//             change propagating through the mass.
//   BASS   → Macro body movement. Drives large sweeping arcs across the
//             sky and shape elongation. Low bass → compact and slow.
//             High bass → elongated ribbons, fast sweeps.
//   OTHER  → Edge flutter and surface shimmer. Periphery birds react
//             3–5× more than core birds (center-to-edge gradient).
//   VOCALS → Density compression. Flock darkens and tightens when
//             vocals enter (the "dark pulse"). Opens up when they exit.
//
// WARMUP FALLBACK: StemFeatures are zero for the first ~10 seconds.
// When totalStemEnergy is near zero, the kernel falls back to the
// full-mix FeatureVector routing (6-band energy) and crossfades to
// stem routing as stems arrive.

struct Particle {
    packed_float3 position;
    float life;
    packed_float3 velocity;
    float size;
    packed_float4 color;
    float seed;
    float age;
    float2 _pad;
};

struct ParticleConfig {
    uint particleCount;
    float decayRate;
    float burstThreshold;
    float burstVelocity;
    float drag;
    float time;
    float _pad0;
    float _pad1;
};

inline float flock_hash(float n) {
    return fract(sin(n) * 43758.5453);
}

// MARK: - Compute Kernel

kernel void particle_update(
    device Particle* particles [[buffer(0)]],
    constant FeatureVector& features [[buffer(1)]],
    constant ParticleConfig& config [[buffer(2)]],
    constant StemFeatures& stems [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= config.particleCount) return;

    Particle p = particles[id];
    float dt = features.delta_time;
    float t = features.time;
    float st = t * 0.7;

    float2 pos = float2(p.position.x, p.position.y);
    float2 vel = float2(p.velocity.x, p.velocity.y);

    // ── Per-bird flock coordinates ─────────────────────────────────────
    // Each bird has a stable position within the flock (seed is constant).
    // birdU: position along the long axis (0=leading tip, 1=trailing tip).
    // birdV: position across the short axis.
    // distFromCenter: 0=interior core, 1=outermost edge.
    float birdU = flock_hash(p.seed * 73.0);
    float birdV = flock_hash(p.seed * 137.0);
    float distFromCenter = abs(birdU - 0.5) * 2.0;

    // ── Warmup detection + smooth crossfade ────────────────────────────
    // StemFeatures are all-zero for the first ~10s after track start.
    // Detect warmup by total stem energy. Crossfade from full-mix
    // FeatureVector routing (stemBlend=0) to stem routing (stemBlend=1).
    float totalStemEnergy = stems.drums_energy + stems.bass_energy
                          + stems.other_energy + stems.vocals_energy;
    float stemBlend = smoothstep(0.02, 0.06, totalStemEnergy);

    // ── Full-mix fallback (FeatureVector — same as previous implementation) ──
    float fm_rhythm  = features.sub_bass + features.low_bass;
    float fm_strings = features.high_mid + features.high_freq;
    float fm_beat    = features.beat_bass;
    float fm_energy  = features.bass;

    // ── Stem-driven values ─────────────────────────────────────────────
    // Bass energy → macro body movement and shape (replaces fm_rhythm).
    // Drums energy + beat → turning wave propagation.
    // Other energy + bands → edge-weighted surface flutter.
    // Vocals energy → density compression (the "dark pulse").

    // ── Blended audio values ───────────────────────────────────────────
    float rhythm      = mix(fm_rhythm,  stems.bass_energy,  stemBlend);
    float flutterBase = mix(fm_strings, stems.other_energy, stemBlend);
    float beatPulse   = mix(fm_beat,    stems.drums_beat,   stemBlend);
    float drumEnergy  = mix(fm_energy,  stems.drums_energy, stemBlend);
    float vocals      = stems.vocals_energy * stemBlend;

    // ── FLOCK CENTER ───────────────────────────────────────────────────
    // Bass drives large sweeping arcs across the sky.
    // Baseline: gentle lemniscate drift.
    float2 flockCenter = float2(
        sin(st * 0.22) * 0.15 + cos(st * 0.14) * 0.08,
        sin(st * 0.17) * 0.12 + cos(st * 0.11) * 0.06
    );

    float windDir = features.bass_att * 3.0 + st * 0.2;
    flockCenter.x += rhythm * 0.20 * cos(windDir);
    flockCenter.y += rhythm * 0.12 * sin(windDir);
    flockCenter.y -= features.spectral_centroid * 0.08;
    flockCenter.x += features.spectral_centroid * 0.06;

    // ── FLOCK SHAPE ────────────────────────────────────────────────────
    // Long, narrow, organic silhouette — thickest at center, tapered at tips.

    float u = (birdU - 0.5) * 2.0;
    u = sign(u) * pow(abs(u), 0.7);   // Mild center concentration.
    float v = (birdV - 0.5) * 2.0;
    v = sign(v) * pow(abs(v), 1.5);   // Stronger concentration = thinner.

    float halfLength = 0.30 + 0.10 * rhythm;
    float halfWidth  = 0.10 + 0.05 * flutterBase;

    // Vocals → density compression: 0–22% tighter when singer is present.
    // This is the "dark pulse" — flock tightens and darkens as vocals enter.
    float densityScale = 1.0 - vocals * 0.22;
    halfLength *= densityScale;
    halfWidth  *= densityScale;

    // Beat compresses briefly on onset.
    halfLength *= (1.0 - beatPulse * 0.15);
    halfWidth  *= (1.0 - beatPulse * 0.10);

    float taperProfile = 1.0 - 0.6 * u * u;
    float localWidth   = halfWidth * taperProfile;
    float2 localPos    = float2(u * halfLength, v * localWidth);

    // Curvature: "other" (strings/synths/guitar) makes the flock ripple and curve.
    float bend = sin(u * 3.14 + st * 0.6) * 0.06
               + sin(u * 6.28 + st * 1.1) * 0.04 * flutterBase;
    bend *= (0.5 + rhythm * 1.2);
    bend += sin(u * 9.42 + st * 2.0) * 0.02 * features.spectral_flux;
    localPos.y += bend;

    // Shape orientation: slow rotation driven by music.
    float shapeAngle = st * 0.12 + sin(st * 0.18) * 0.5
                     + features.treb_att * 0.5
                     + rhythm * 0.3;
    shapeAngle += sin(st * (1.0 + features.spectral_flux * 2.5)) * 0.2
                * features.spectral_flux;

    float cs = cos(shapeAngle), sn = sin(shapeAngle);
    float2 homeOffset = float2(localPos.x * cs - localPos.y * sn,
                                localPos.x * sn + localPos.y * cs);
    float2 homePos = flockCenter + homeOffset;

    // ── TURNING WAVE (drums → coordinated directional turn) ────────────
    //
    // When drums_beat fires, the flock doesn't turn simultaneously.
    // Instead, a directional turn propagates as a wave across the flock
    // over the ~200ms beat decay period, exactly like real murmurations.
    //
    // drums_beat decays from 1→0 after a beat. Using (1 - beatPulse) as
    // the wave front: 0.0 = just fired, 1.0 = fully swept across the flock.
    //
    // Propagation direction alternates per beat epoch so successive beats
    // sweep from varying directions, creating the characteristic weaving.

    float beatEpoch = floor(t * 2.5);   // New epoch ~2.5× per second.
    float propDir   = flock_hash(beatEpoch) > 0.5 ? 1.0 : -1.0;

    // birdFlockCoord: 0→1 in the direction the wave travels.
    float birdFlockCoord = propDir > 0.0 ? birdU : (1.0 - birdU);

    // Wave front sweeps from 0→1 as the beat pulse decays.
    float waveFront = 1.0 - beatPulse;

    // Smooth triangular bump centered at waveFront.
    // Peak when waveFront == birdFlockCoord; falls off over waveWidth on each side.
    float waveWidth    = 0.20;
    float distToWave   = abs(waveFront - birdFlockCoord);
    float waveInfluence = max(0.0, 1.0 - distToWave / waveWidth);

    // Turning force: perpendicular to flock heading.
    // Interior and edge birds both receive this force — the wave is structural.
    float2 headingDir   = float2(cos(shapeAngle), sin(shapeAngle));
    float2 perpDir      = float2(-headingDir.y, headingDir.x);
    float turnAmplitude = drumEnergy * 0.22 * waveInfluence;
    float2 turnForce    = perpDir * turnAmplitude * propDir;

    // ── FORCES ─────────────────────────────────────────────────────────

    float2 toHome      = homePos - pos;
    float distFromHome = length(toHome);
    float2 homeDir     = distFromHome > 0.001 ? normalize(toHome) : float2(0.0);

    // Strong spring pull: close birds barely feel it; distant birds snap back.
    float springMagnitude = 3.0 * distFromHome + 5.0 * distFromHome * distFromHome;
    float2 force = homeDir * springMagnitude;

    // Edge-weighted flutter: "other" energy drives surface shimmer.
    // Periphery birds (distFromCenter→1) respond 4× more than core birds.
    // This creates the visible shimmer/texture gradient of a real murmuration.
    float edgeWeight  = mix(0.25, 1.0, distFromCenter);
    float flutterSpeed = 1.5 + flock_hash(p.seed * 53.0) * 1.5;
    float jPhase = p.seed * 100.0 + t * flutterSpeed;
    float2 jitter = float2(sin(jPhase), cos(jPhase * 1.3 + p.seed * 30.0));
    force += jitter * (0.06 + flutterBase * 0.20) * edgeWeight;

    // Add turning wave force.
    force += turnForce;

    // ── INTEGRATE ──────────────────────────────────────────────────────

    vel += force * dt;
    vel *= max(0.0, 1.0 - 3.0 * dt);   // Strong damping — no overshoot.

    float speed = length(vel);
    if (speed > 3.0) vel = normalize(vel) * 3.0;

    pos += vel * dt;

    p.position = packed_float3(pos.x, pos.y, 0.0);
    p.velocity = packed_float3(vel.x, vel.y, 0.0);

    if (p.life < 1.0) p.life = min(p.life + dt * 0.5, 1.0);

    // Color: near-black silhouette. Spectral centroid modulates hue slightly.
    float warmth = features.spectral_centroid;
    float h = mix(0.6, 0.08, warmth);
    float3 rgb = hsv2rgb(float3(fract(h + t * 0.002), 0.15, 0.06));
    p.color = packed_float4(rgb.x, rgb.y, rgb.z, min(p.life, 1.0));

    p.size = 4.0 + flock_hash(p.seed * 37.0) * 3.0;
    p.age += dt;
    particles[id] = p;
}

// MARK: - Vertex Shader

struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
    float life;
    float2 velDir;
};

vertex ParticleVertexOut particle_vertex(
    uint vid [[vertex_id]],
    constant Particle* particles [[buffer(0)]],
    constant FeatureVector& features [[buffer(1)]]
) {
    Particle p = particles[vid];
    ParticleVertexOut out;

    float scale = 2.2;
    out.position = float4(float2(p.position.x, p.position.y) * scale, 0.0, 1.0);
    out.pointSize = p.life > 0.0 ? max(p.size, 1.0) : 0.0;

    float2 vel = float2(p.velocity.x, p.velocity.y);
    float speed = length(vel);
    out.velDir = speed > 0.01 ? vel / speed : float2(1.0, 0.0);

    out.color = float4(p.color);
    out.life = p.life;
    return out;
}

// MARK: - Fragment Shader

fragment float4 particle_fragment(
    ParticleVertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    if (in.life <= 0.0) discard_fragment();

    float2 pc = (pointCoord - 0.5) * 2.0;

    // Elongated along flight direction — 2.5:1 ratio.
    float2 vd = in.velDir;
    float2 perp = float2(-vd.y, vd.x);
    float along = dot(pc, vd);
    float across = dot(pc, perp);

    float dist = sqrt((along * along) / 5.0 + across * across * 2.0);

    if (dist > 1.0) discard_fragment();

    float alpha = (1.0 - smoothstep(0.2, 0.9, dist)) * in.color.a * 0.85;
    float3 birdColor = float3(0.02, 0.02, 0.03);

    return float4(birdColor, alpha);
}
