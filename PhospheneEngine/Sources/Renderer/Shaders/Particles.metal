// Particles.metal — Murmuration: ~1000 starlings as one organism.
//
// COHESION IS KING. Birds stay as a tight mass. The flock has a clear
// shape at all times. Movement comes from the WHOLE FLOCK moving
// together — changing direction, stretching, compressing — not from
// individual birds flying around independently.
//
// Music connection — visible and immediate:
//   The flock's DIRECTION follows the waveform. Rising pitch = flock rises.
//   Bass pushes the flock bodily. Beat makes the flock flinch/compress.
//   The entire mass responds as one organism.

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

kernel void particle_update(
    device Particle* particles [[buffer(0)]],
    constant FeatureVector& features [[buffer(1)]],
    constant ParticleConfig& config [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= config.particleCount) return;

    Particle p = particles[id];
    float dt = features.delta_time;
    float t = features.time;
    float st = t * 0.7;

    float2 pos = float2(p.position.x, p.position.y);
    float2 vel = float2(p.velocity.x, p.velocity.y);

    // ══════════════════════════════════════════════════════════════
    // FLOCK CENTER — the whole mass moves together.
    // Music drives where the center GOES, visibly.
    // ══════════════════════════════════════════════════════════════

    // Baseline drift: gentle sine waves.
    float2 flockCenter = float2(
        sin(st * 0.22) * 0.15 + cos(st * 0.14) * 0.08,
        sin(st * 0.17) * 0.12 + cos(st * 0.11) * 0.06
    );

    // MUSIC DRIVES THE CENTER — using 6-band energy to bypass vocals.
    //
    // Vocals dominate low_mid (250-1kHz) and mid_high (1-4kHz).
    // We deliberately SKIP those bands for movement.
    //
    // sub_bass + low_bass = rhythm section → drives flock body movement.
    // high_mid + high = strings, cymbals, overtones → drives flutter and shape.
    //
    float rhythm = features.sub_bass + features.low_bass;  // Bass guitar, kick drum.
    float strings = features.high_mid + features.high_freq; // Strings, air, shimmer.

    // Rhythm pushes the flock bodily — you see it shift with the bass line.
    float windDir = features.bass_att * 3.0 + st * 0.2;
    flockCenter.x += rhythm * 0.20 * cos(windDir);
    flockCenter.y += rhythm * 0.12 * sin(windDir);
    // Strings lift the flock — high overtones pull it upward.
    flockCenter.y -= strings * 0.12;
    // Spectral centroid still shifts temperature (it spans all bands).
    flockCenter.x += features.spectral_centroid * 0.06;
    flockCenter.y -= features.spectral_centroid * 0.08;

    // ══════════════════════════════════════════════════════════════
    // FLOCK SHAPE — an organic blob, not a line or ring.
    // Each bird has a home offset from center. The offsets define
    // the flock's shape. The shape breathes with the music.
    // ══════════════════════════════════════════════════════════════

    // ── FLOCK SHAPE — elongated, asymmetric, constantly changing ──
    // NOT circular. An irregular elongated form like a real murmuration.
    // The shape pivots, stretches, thins, thickens — never static.

    // Two independent hash values give each bird a position in a unit square.
    float birdU = flock_hash(p.seed * 73.0);   // 0-1, position along length.
    float birdV = flock_hash(p.seed * 137.0);  // 0-1, position across width.

    // Center-heavy along the length (most birds in the middle third).
    float u = (birdU - 0.5) * 2.0;  // -1 to 1
    u = sign(u) * pow(abs(u), 0.7);  // Mild center concentration.
    // Center-heavy across width.
    float v = (birdV - 0.5) * 2.0;
    v = sign(v) * pow(abs(v), 1.5);  // Stronger concentration = thinner.

    // Shape dimensions: long and narrow, like a murmuration.
    // Rhythm (sub-bass + bass) stretches it. Strings widen it.
    float halfLength = 0.30 + 0.10 * rhythm;
    float halfWidth = 0.10 + 0.05 * strings;
    // Beat compresses both.
    halfLength *= (1.0 - features.beat_bass * 0.15);
    halfWidth *= (1.0 - features.beat_bass * 0.1);

    // Width tapers at the ends — thickest in the middle, thin at tips.
    // This creates the organic murmuration silhouette.
    float taperProfile = 1.0 - 0.6 * u * u;  // Parabolic taper.
    float localWidth = halfWidth * taperProfile;

    float2 localPos = float2(u * halfLength, v * localWidth);

    // Curvature: strings drive the bending — fluttering strings
    // make the murmuration ripple and curve.
    float bend = sin(u * 3.14 + st * 0.6) * 0.06
               + sin(u * 6.28 + st * 1.1) * 0.04 * strings;
    // Rhythm also contributes — bass hits push the curve.
    bend *= (0.5 + rhythm * 1.2);
    // Spectral flux adds rapid shape change — timbral shifts ripple through.
    bend += sin(u * 9.42 + st * 2.0) * 0.02 * features.spectral_flux;
    localPos.y += bend;

    // Shape orientation: strings and rhythm steer the rotation.
    // NOT mid_att (which is vocal-dominated).
    float shapeAngle = st * 0.12 + sin(st * 0.18) * 0.5
                     + features.treb_att * 0.5   // Strings steer slowly.
                     + rhythm * 0.3;              // Rhythm nudges.
    shapeAngle += sin(st * (1.0 + features.spectral_flux * 2.5)) * 0.2 * features.spectral_flux;

    float cs = cos(shapeAngle), sn = sin(shapeAngle);
    float2 homeOffset = float2(localPos.x * cs - localPos.y * sn,
                                localPos.x * sn + localPos.y * cs);

    float2 homePos = flockCenter + homeOffset;

    // ══════════════════════════════════════════════════════════════
    // FORCES — STRONG cohesion, gentle individual variation.
    // ══════════════════════════════════════════════════════════════

    float2 toHome = homePos - pos;
    float distFromHome = length(toHome);
    float2 homeDir = distFromHome > 0.001 ? normalize(toHome) : float2(0.0);

    // STRONG spring pull toward home — this keeps the flock TIGHT.
    // Birds close to home barely feel it. Birds far away snap back fast.
    float springForce = 3.0 * distFromHome + 5.0 * distFromHome * distFromHome;
    float2 force = homeDir * springForce;

    // Individual jitter — strings drive the flutter of individual birds.
    float jPhase = p.seed * 100.0 + t * (1.5 + flock_hash(p.seed * 53.0) * 1.5);
    float2 jitter = float2(sin(jPhase), cos(jPhase * 1.3 + p.seed * 30.0));
    force += jitter * (0.06 + strings * 0.20);

    // ══════════════════════════════════════════════════════════════
    // BEAT RESPONSE — flock flinches, then recovers.
    // Not scatter — COMPRESSION. The mass contracts briefly.
    // ══════════════════════════════════════════════════════════════

    // (Already handled via stretchX/stretchY reduction above.
    //  The beat compresses the shape, birds spring toward new home positions.)

    // ══════════════════════════════════════════════════════════════
    // INTEGRATE
    // ══════════════════════════════════════════════════════════════

    vel += force * dt;
    vel *= max(0.0, 1.0 - 3.0 * dt);  // Strong damping — no overshoot.

    float speed = length(vel);
    if (speed > 3.0) vel = normalize(vel) * 3.0;

    pos += vel * dt;

    p.position = packed_float3(pos.x, pos.y, 0.0);
    p.velocity = packed_float3(vel.x, vel.y, 0.0);

    if (p.life < 1.0) p.life = min(p.life + dt * 0.5, 1.0);

    // Color: near-black silhouette.
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

    // Elongated along flight direction.
    float2 vd = in.velDir;
    float2 perp = float2(-vd.y, vd.x);
    float along = dot(pc, vd);
    float across = dot(pc, perp);

    // Simple elongated ellipse — 2.5:1 ratio.
    float dist = sqrt((along * along) / 5.0 + across * across * 2.0);

    if (dist > 1.0) discard_fragment();

    float alpha = (1.0 - smoothstep(0.2, 0.9, dist)) * in.color.a * 0.85;
    float3 birdColor = float3(0.02, 0.02, 0.03);

    return float4(birdColor, alpha);
}
