// Murmuration3D.metal — the 3D version of the proven parametric-ellipse flock.
//
// This LIFTS the 40-round 2D Murmuration (Particles.metal) into 3D rather than
// rebuilding it as emergent boids (which failed across many M7 rounds — sparse,
// spraying, off-canvas). The 2D version is superior because it CONTROLS the
// flock's shape: every bird is spring-pulled to a home slot in a morphing
// ellipse, so the mass is dense, coherent and framed by construction. We keep
// that architecture verbatim and add the third dimension + what 3D actually buys:
//
//   • a 3D morphing ELLIPSOID of home slots (depth axis added; the bounded
//     lemniscate centre keeps it framed/on-canvas),
//   • PERSPECTIVE projection + depth fade/size → real volume, birds in front and
//     behind, the mass reads as a solid 3D body,
//   • real BANKING → the rolling dark bands: the drum turning-wave rolls a band of
//     birds that bank together, and a banked bird presents more wing area to the
//     camera → it darkens, so a dark band travels across the mass (the McGill
//     orientation-wave mechanism, for real — not the 2D fake).
//
// The proven audio brain (bass→drift+elongation, drums→turning-wave, other→edge
// flutter + curvature, vocals→density compression) is carried forward to 3D.
// Concatenated into the engine library (alphabetical, after Common.metal); reads
// FeatureVector/StemFeatures by their snake_case MSL names (FA #72). Helper names
// are `m3d_`-prefixed to avoid collisions with Particles.metal.

#include <metal_stdlib>
using namespace metal;

struct M3DParticle {
    packed_float3 position;   // 3D world position (compact units, ~[-0.6,0.6])
    float         life;
    packed_float3 velocity;   // 3D velocity
    float         size;
    packed_float4 color;
    float         seed;       // stable per-bird [0,1]
    float         age;
    float         bank;       // signed banking [-1,1] → wing-area-to-camera darkening
    float         _pad;
};

struct M3DConfig {
    uint  particleCount;
    float drag;
    float camDist;            // perspective camera distance (world units)
    float camPitch;           // downward look angle (rad)
    float time;
    float viewScale;          // screen zoom — fills the frame (perspective shrinks the raw flock)
    float _pad1;
    float _pad2;
};

inline float m3d_hash(float n) { return fract(sin(n) * 43758.5453); }

inline float3 m3d_hash3(float n) {
    return fract(sin(float3(n, n + 1.7, n + 3.3)) * float3(43758.5453, 22578.1459, 19642.3490));
}

// MARK: - Compute: spring the bird to its slot in the 3D morphing ellipsoid

kernel void murmuration3d_update(
    device M3DParticle*     particles [[buffer(0)]],
    constant FeatureVector& features  [[buffer(1)]],
    constant M3DConfig&     config    [[buffer(2)]],
    constant StemFeatures&  stems     [[buffer(3)]],
    uint                    id        [[thread_position_in_grid]])
{
    if (id >= config.particleCount) { return; }
    M3DParticle p = particles[id];
    float dt = features.delta_time;
    if (!(dt > 0.0)) { dt = 1.0 / 60.0; }
    dt = min(dt, 1.0 / 30.0);
    float t  = features.time;
    float st = t * 0.7;

    float3 pos = float3(p.position);
    float3 vel = float3(p.velocity);

    // ── Per-bird flock coordinates (stable; seed is constant) ──
    // birdU along the long axis, birdV across, birdW through depth.
    float birdU = m3d_hash(p.seed * 73.0);
    float birdV = m3d_hash(p.seed * 137.0);
    float birdW = m3d_hash(p.seed * 211.0);
    float distFromCenter = length(float3(birdU, birdV, birdW) - 0.5) * 2.0;

    // ── Warmup crossfade: full-mix FeatureVector → stems as they arrive ──
    float totalStem = stems.drums_energy + stems.bass_energy + stems.other_energy + stems.vocals_energy;
    float stemBlend = smoothstep(0.02, 0.06, totalStem);
    float rhythm      = mix(features.sub_bass + features.low_bass, stems.bass_energy,  stemBlend);
    float flutterBase = mix(features.high_mid + features.high_freq, stems.other_energy, stemBlend);
    float beatPulse   = mix(features.beat_bass, stems.drums_beat,   stemBlend);
    float drumEnergy  = mix(features.bass,      stems.drums_energy, stemBlend);
    float vocals      = stems.vocals_energy * stemBlend;

    // ── FLOCK CENTRE — bounded so it never leaves the canvas (proven 2D values,
    // plus a gentle depth drift). Bass adds sweeping arcs.
    float3 flockCenter = float3(
        sin(st * 0.22) * 0.08 + cos(st * 0.14) * 0.04,
        sin(st * 0.17) * 0.06 + cos(st * 0.11) * 0.03,
        sin(st * 0.13) * 0.10 + cos(st * 0.19) * 0.05);
    float windDir = features.bass_att * 3.0 + st * 0.2;
    flockCenter.x += rhythm * 0.10 * cos(windDir);
    flockCenter.y += rhythm * 0.06 * sin(windDir);
    flockCenter.z += rhythm * 0.10 * sin(windDir * 0.7);

    // ── FLOCK SHAPE — a long, tapered ELLIPSOID; thickest at centre. ──
    float u = (birdU - 0.5) * 2.0; u = sign(u) * pow(abs(u), 0.7);   // mild centre concentration
    float v = (birdV - 0.5) * 2.0; v = sign(v) * pow(abs(v), 1.4);
    float w = (birdW - 0.5) * 2.0; w = sign(w) * pow(abs(w), 1.4);

    float halfLength = 0.40 + 0.12 * rhythm;     // tapered comma — elongated like the proven 2D
    float halfWidth  = 0.105 + 0.04 * flutterBase;
    float halfDepth  = 0.085 + 0.03 * flutterBase;
    float densityScale = 1.0 - vocals * 0.22;         // vocals → tighten/darken
    halfLength *= densityScale; halfWidth *= densityScale; halfDepth *= densityScale;
    halfLength *= (1.0 - beatPulse * 0.12);
    halfWidth  *= (1.0 - beatPulse * 0.08);

    float taper = 1.0 - 0.55 * u * u;                 // tapered tips
    float3 localPos = float3(u * halfLength, v * halfWidth * taper, w * halfDepth * taper);

    // Curvature: "other" makes the body ripple/curve (in Y and Z).
    float bend = sin(u * 3.14 + st * 0.6) * 0.06 + sin(u * 6.28 + st * 1.1) * 0.04 * flutterBase;
    bend *= (0.5 + rhythm * 1.2);
    localPos.y += bend;
    localPos.z += sin(u * 4.0 + st * 0.5) * 0.04 * (0.5 + flutterBase);

    // Shape orientation — slow musical rotation (yaw about Y + slight pitch).
    float yaw   = st * 0.12 + sin(st * 0.18) * 0.5 + features.treb_att * 0.4 + rhythm * 0.3;
    float pitch = sin(st * 0.15) * 0.25 + features.spectral_centroid * 0.2;
    float cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch);
    // Rotate localPos by yaw (about Y) then pitch (about X).
    float3 r1 = float3(localPos.x * cy + localPos.z * sy, localPos.y, -localPos.x * sy + localPos.z * cy);
    float3 r2 = float3(r1.x, r1.y * cp - r1.z * sp, r1.y * sp + r1.z * cp);
    float3 homePos = flockCenter + r2;

    // ── TURNING WAVE (drums) — a band banks together; the bank darkens it, so a
    // dark band rolls across the mass (the references' orientation-wave). ──
    float beatEpoch = floor(t * 2.5);
    float propDir   = m3d_hash(beatEpoch) > 0.5 ? 1.0 : -1.0;
    float birdCoord = propDir > 0.0 ? birdU : (1.0 - birdU);
    float waveFront = 1.0 - beatPulse;
    float waveInfluence = max(0.0, 1.0 - abs(waveFront - birdCoord) / 0.22);

    // Heading in the projected XZ plane → a perpendicular turn force.
    float3 headingDir = float3(cy, 0.0, sy);
    float3 perpDir    = float3(-headingDir.z, 0.0, headingDir.x);
    float turnAmp     = drumEnergy * 0.22 * waveInfluence;
    float3 turnForce  = perpDir * turnAmp * propDir;

    // ── FORCES — strong spring to home (dense, no overshoot) + edge flutter ──
    float3 toHome = homePos - pos;
    float distHome = length(toHome);
    float3 force = (distHome > 0.001 ? normalize(toHome) : float3(0.0)) * (3.0 * distHome + 5.0 * distHome * distHome);

    float edgeWeight = mix(0.25, 1.0, distFromCenter);   // periphery flutters ~4× the core
    float3 jit = m3d_hash3(p.seed * 100.0 + t * (1.5 + m3d_hash(p.seed * 53.0) * 1.5)) - 0.5;
    force += jit * (0.10 + flutterBase * 0.30) * edgeWeight;
    force += turnForce;

    // ── INTEGRATE (3D) — strong damping, no overshoot ──
    vel += force * dt;
    vel *= max(0.0, 1.0 - config.drag * dt);
    float speed = length(vel);
    if (speed > 3.0) { vel = normalize(vel) * 3.0; }
    pos += vel * dt;

    // ── BANKING — birds in the turning band bank; also bank into their own turn
    // (lateral velocity vs heading). Smoothed for fluidity. Drives the dark band.
    float lateral = dot(normalize(vel + float3(1e-5)), perpDir);
    float targetBank = clamp(waveInfluence * propDir * 1.0 + lateral * 0.6, -1.0, 1.0);
    p.bank = mix(p.bank, targetBank, clamp(dt * 4.0, 0.0, 1.0));

    p.position = packed_float3(pos);
    p.velocity = packed_float3(vel);
    if (p.life < 1.0) { p.life = min(p.life + dt * 0.5, 1.0); }
    p.size = 3.4 + m3d_hash(p.seed * 37.0) * 2.6;
    p.age += dt;
    particles[id] = p;
}

// MARK: - Vertex: perspective projection + depth fade/size + bank darkening

struct M3DVertexOut {
    float4 position [[position]];
    float  pointSize [[point_size]];
    float  alpha;
    float  shade;     // 0 lightest … 1 darkest (near + banked + dense)
    float2 velDir;    // projected heading for the elongated sprite
};

vertex M3DVertexOut murmuration3d_vertex(
    uint                    vid      [[vertex_id]],
    constant M3DParticle*   particles[[buffer(0)]],
    constant M3DConfig&     config   [[buffer(2)]])
{
    M3DParticle p = particles[vid];
    M3DVertexOut out;

    // Static wide camera with a slight downward pitch (shows the 3D volume).
    float cp = cos(config.camPitch), sp = sin(config.camPitch);
    float3 wp = float3(p.position);
    float3 cam = float3(wp.x, wp.y * cp + wp.z * sp, -wp.y * sp + wp.z * cp);

    // Perspective: camera at +camDist looking toward −z. Nearer (larger z) → bigger.
    float zEye = config.camDist - cam.z;
    float persp = config.camDist / max(zEye, 0.05);
    out.position = float4(cam.x * persp * config.viewScale, cam.y * persp * config.viewScale, 0.0, 1.0);

    float depth01 = clamp(cam.z * 0.5 + 0.5, 0.0, 1.0);        // 0 far … 1 near
    float depthFade = 0.55 + 0.45 * depth01;                  // far birds lift toward sky

    out.pointSize = max(p.size * persp, 1.0);

    // Banking darkening: a banked bird shows more wing area to the camera → darker.
    float bankDark = clamp(abs(p.bank) * 1.4, 0.0, 1.0);

    out.shade = clamp(0.45 + 0.35 * depth01 + 0.35 * bankDark, 0.0, 1.0);
    out.alpha = clamp(p.life * depthFade * (0.55 + 0.45 * bankDark), 0.0, 0.95);

    float3 v = float3(p.velocity);
    float3 cv = float3(v.x, v.y * cp + v.z * sp, -v.y * sp + v.z * cp);
    float2 sv = float2(cv.x, cv.y);
    float sl = length(sv);
    out.velDir = sl > 1e-3 ? sv / sl : float2(1.0, 0.0);
    return out;
}

// MARK: - Fragment: elongated near-black bird

fragment float4 murmuration3d_fragment(
    M3DVertexOut in [[stage_in]],
    float2       pc [[point_coord]])
{
    float2 d = (pc - 0.5) * 2.0;
    float2 vd = in.velDir;
    float2 perp = float2(-vd.y, vd.x);
    float along = dot(d, vd), across = dot(d, perp);
    float dist = sqrt(along * along / 4.0 + across * across * 1.8);   // ~2:1 elongated
    if (dist > 1.0) { discard_fragment(); }
    float disk = 1.0 - smoothstep(0.25, 0.95, dist);
    // Near-black silhouette; far/light birds lift toward dusk grey.
    float3 birdColor = mix(float3(0.09, 0.09, 0.12), float3(0.015, 0.015, 0.025), in.shade);
    return float4(birdColor, disk * in.alpha);
}
