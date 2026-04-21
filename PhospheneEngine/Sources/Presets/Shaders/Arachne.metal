// Arachne.metal — Bioluminescent spider-web mesh shader preset (Increment 3.5.5).
//
// Renders up to 12 spider webs that spin in rhythm with the music.
// Stage order: anchorPulse → radial → spiral → stable → evicting.
// Stage durations are measured in beats (ArachneState.swift), so fast music
// builds faster.
//
// Stem routing (D-019 warmup applied in fragment):
//   drums   → spawn timing only (ArachneState.swift)
//   bass    → strand quiver: propagating sinusoidal wave from hub outward
//   other   → birth color (WebGPU.birth_hue/sat/brt, baked at spawn)
//   vocals  → unused
//
// Object shader: dispatches 12 mesh threadgroups (one per web slot).
// Mesh shader (64 threads per web):
//   Thread 0     : hub cap quad (always visible when alive)
//   Threads 1–8  : anchor dot quads (visible from anchorPulse onward)
//   Threads 9–16 : radial spoke quads (visible from radial onward)
//   Threads 17–56: spiral capture-thread segments (visible from spiral onward)
//   Threads 57–63: idle (no geometry)
//
// MeshVertex packing:
//   position : clip-space
//   normal.x : birth_hue [0, 1]
//   normal.y : dist_from_hub [0, 1]
//   normal.z : web opacity          (strand geometry)
//              web opacity + 10.0   (dot geometry — circular mask sentinel)
//   uv       : (along 0..1, across 0..1) for strands
//              (0..1 corners)           for dots — circular mask via length(uv*2-1)

// MARK: - ArachneSpiderGPU (byte-matches Swift ArachneSpiderGPU in ArachneState+Spider.swift)
//
// 80 bytes: 4 × float (16 B) + 8 × float2 (64 B).
// Bound at fragment buffer(4) when Arachne is the active preset.

struct ArachneSpiderGPU {
    float blend;          // 0 = absent, 1 = fully materialised
    float posX, posY;     // clip-space body centre
    float heading;        // orientation (radians)
    float2 tip[8];        // leg tip positions in clip space
};

// MARK: - ArachneWebGPU (byte-matches Swift WebGPU in ArachneState.swift)

struct ArachneWebGPU {
    // Row 0
    float hub_x, hub_y, radius, depth;
    // Row 1
    float rot_angle;
    uint  anchor_count;
    float spiral_revolutions;
    uint  rng_seed;
    // Row 2
    float birth_beat_phase;
    uint  stage;
    float progress;
    float opacity;
    // Row 3
    float birth_hue, birth_sat, birth_brt;
    uint  is_alive;
};

// MARK: - Payload (object → all 12 mesh threadgroups)

struct ArachnePayload {
    float bass_rel;        // D-026: FV bass deviation (object has no stem access)
    float beat_phase01;    // MV-3b: 0→1 ramp to next predicted beat
    float beats_until_next;
    float aspect_ratio;
    float time;
};

// MARK: - Object Shader

/// Reads FeatureVector at buffer(0), populates shared payload, dispatches 12 mesh threadgroups.
[[object, max_total_threads_per_threadgroup(1)]]
void arachne_object_shader(
    object_data ArachnePayload* payload [[payload]],
    mesh_grid_properties          mgp,
    constant FeatureVector&       features [[buffer(0)]],
    uint tid [[thread_index_in_threadgroup]])
{
    // Dispatch one mesh threadgroup per web slot (12 total, matching ArachneState.maxWebs).
    mgp.set_threadgroups_per_grid(uint3(12, 1, 1));

    if (tid == 0) {
        payload->bass_rel        = features.bass_rel;
        payload->beat_phase01    = features.beat_phase01;
        payload->beats_until_next = features.beats_until_next;
        payload->aspect_ratio    = max(features.aspect_ratio, 0.1f);
        payload->time            = features.time;
    }
}

// MARK: - Mesh Shader Geometry

/// Web-slot layout (one per mesh threadgroup, 64 threads each):
///   Thread 0    : hub cap quad        verts [0..3],    indices [0..5]
///   Thread 1–8  : anchor dot i-1      verts [4+i*4..], indices [6+i*6..]
///   Thread 9–16 : spoke j=lid-9       verts [36+j*4..],indices [54+j*6..]
///   Thread 17–56: spiral seg k=lid-17 verts [68+k*4..],indices [102+k*6..]
///   Thread 57–63: idle (return early)
/// Max total: 228 vertices, 114 triangles (2 per quad slot × 57 active threads).

typedef mesh<MeshVertex, MeshPrimitive, 228, 114, topology::triangle> ArachneMesh;

// Per-anchor position: independent deterministic formula, no sequential LCG state.
static inline float2 anchor_pos(ArachneWebGPU web, uint idx) {
    uint s = web.rng_seed ^ (idx * 2246822519u + 1234567u);
    s = s * 1664525u + 1013904223u;
    float jitter = (float(s >> 8) / float(1 << 24) - 0.5f) * 0.55f;  // ±0.275 rad
    float angle = web.rot_angle
                + float(idx) * (2.0f * M_PI_F / float(web.anchor_count))
                + jitter;
    return float2(web.hub_x + cos(angle) * web.radius,
                  web.hub_y + sin(angle) * web.radius);
}

// Write off-screen (clipped) quad for idle/inactive slots.
static inline void write_offscreen(thread ArachneMesh& m, uint bv, uint bi) {
    MeshVertex dead;
    dead.position = float4(2.0f, 2.0f, 0.0f, 1.0f);
    dead.uv       = float2(0, 0);
    dead.normal   = float3(0, 0, 0);
    dead.clipXY   = float2(2.0f, 2.0f);
    m.set_vertex(bv + 0u, dead); m.set_vertex(bv + 1u, dead);
    m.set_vertex(bv + 2u, dead); m.set_vertex(bv + 3u, dead);
    for (uint k = 0u; k < 6u; k++) m.set_index(bi + k, bv);
}

// Write a segment quad (p0→p1, half-widths w0→w1, aspect-corrected X).
// normal.z encodes opacity (+10 for dot circular-mask sentinel).
static inline void write_quad(
    thread ArachneMesh& m, uint bv, uint bi,
    float2 p0, float2 p1, float w0, float w1, float aspect,
    float hue, float d0, float d1, float normalZ)
{
    float2 seg = p1 - p0;
    float len  = length(seg);
    float2 dir = len > 1e-5f ? (seg / len) : float2(0, 1);
    float2 perp = float2(-dir.y, dir.x);
    float2 ap0 = float2(perp.x / aspect, perp.y) * w0;
    float2 ap1 = float2(perp.x / aspect, perp.y) * w1;

    // v0 (p0 + perp), v1 (p0 - perp), v2 (p1 + perp), v3 (p1 - perp)
    MeshVertex v;
    v.normal = float3(hue, d0, normalZ);
    v.position = float4(p0 + ap0, 0, 1); v.clipXY = p0 + ap0; v.uv = float2(0, 0); m.set_vertex(bv + 0u, v);
    v.position = float4(p0 - ap0, 0, 1); v.clipXY = p0 - ap0; v.uv = float2(0, 1); m.set_vertex(bv + 1u, v);
    v.normal.y = d1;
    v.position = float4(p1 + ap1, 0, 1); v.clipXY = p1 + ap1; v.uv = float2(1, 0); m.set_vertex(bv + 2u, v);
    v.position = float4(p1 - ap1, 0, 1); v.clipXY = p1 - ap1; v.uv = float2(1, 1); m.set_vertex(bv + 3u, v);

    m.set_index(bi + 0u, bv + 0u); m.set_index(bi + 1u, bv + 2u); m.set_index(bi + 2u, bv + 1u);
    m.set_index(bi + 3u, bv + 1u); m.set_index(bi + 4u, bv + 2u); m.set_index(bi + 5u, bv + 3u);
}

[[mesh, max_total_threads_per_threadgroup(64)]]
void arachne_mesh_shader(
    object_data const ArachnePayload& payload [[payload]],
    ArachneMesh m,
    device const ArachneWebGPU* webs [[buffer(1)]],
    uint  lid  [[thread_index_in_threadgroup]],
    uint3 tgid [[threadgroup_position_in_grid]])
{
    uint webIdx = tgid.x;
    ArachneWebGPU web = webs[webIdx];

    // Thread 0 sets primitive count; all others rely on this to be correct.
    if (lid == 0u) {
        m.set_primitive_count(web.is_alive != 0u ? 114u : 0u);
    }

    // Dead slots: write nothing (primitive_count=0 means no rasterization).
    if (web.is_alive == 0u) return;

    float aspect  = payload.aspect_ratio;
    float hue     = web.birth_hue;
    float opacity = web.opacity;
    uint  stage   = web.stage;
    uint  ac      = web.anchor_count;
    float2 hub    = float2(web.hub_x, web.hub_y);

    // MV-3b beat anticipation (stronger the closer we get to the next beat).
    float anticipation = smoothstep(0.75f, 1.0f, payload.beat_phase01);
    float bassBoost    = max(0.0f, payload.bass_rel) * 0.10f;

    // ── Thread 0: hub cap ──────────────────────────────────────────────────────
    if (lid == 0u) {
        float r = 0.018f * (1.0f + anticipation * 0.55f + bassBoost);
        // anchorPulse: pulse with beat anticipation only — no free-running oscillation.
        if (stage == 0u) r *= 1.0f + anticipation * 0.9f;
        // Segment along Y, width = r → visually circular (aspect-corrected)
        float2 p0 = float2(hub.x, hub.y - r);
        float2 p1 = float2(hub.x, hub.y + r);
        write_quad(m, 0u, 0u, p0, p1, r, r, aspect, hue, 0.0f, 0.0f, opacity + 10.0f);
        return;
    }

    // ── Threads 1–8: anchor dots — suppressed (write offscreen) ──────────────
    // Anchor dots were confusing; anchors remain as radial spoke endpoints only.
    if (lid <= 8u) {
        uint ai = lid - 1u;
        write_offscreen(m, 4u + ai * 4u, 6u + ai * 6u);
        return;
    }

    // ── Threads 9–16: radial spokes ────────────────────────────────────────────
    if (lid <= 16u) {
        uint si = lid - 9u;
        uint bv = 36u + si * 4u;
        uint bi = 54u + si * 6u;

        bool active = (si < ac) && (stage >= 1u);
        // During radial stage, spokes appear one-by-one as progress advances.
        if (active && stage == 1u) {
            float threshold = float(si) / float(ac);
            active = web.progress >= threshold;
        }

        if (!active) { write_offscreen(m, bv, bi); return; }

        float2 aPos = anchor_pos(web, si);
        // Taper: 0.005 at hub, 0.0015 at anchor.
        write_quad(m, bv, bi, hub, aPos, 0.005f, 0.0015f, aspect, hue, 0.0f, 0.85f, opacity);
        return;
    }

    // ── Threads 17–56: spiral capture-thread segments ─────────────────────────
    if (lid <= 56u) {
        uint segIdx = lid - 17u;
        uint bv = 68u + segIdx * 4u;
        uint bi = 102u + segIdx * 6u;

        bool active = (stage >= 2u);
        // During spiral stage, segments appear sequentially as progress advances.
        if (active && stage == 2u) {
            active = web.progress >= (float(segIdx) / 40.0f);
        }

        if (!active) { write_offscreen(m, bv, bi); return; }

        // Spiral: winds from hub to outer radius over spiral_revolutions turns.
        float t0 = float(segIdx) / 40.0f;
        float t1 = float(segIdx + 1u) / 40.0f;

        float a0 = web.rot_angle + t0 * web.spiral_revolutions * (2.0f * M_PI_F);
        float a1 = web.rot_angle + t1 * web.spiral_revolutions * (2.0f * M_PI_F);

        float2 pos0 = hub + float2(cos(a0), sin(a0)) * (web.radius * t0);
        float2 pos1 = hub + float2(cos(a1), sin(a1)) * (web.radius * t1);

        // Strand tapers outward: thick near hub, fine at edge.
        float w0 = mix(0.0040f, 0.0010f, t0);
        float w1 = mix(0.0040f, 0.0010f, t1);

        write_quad(m, bv, bi, pos0, pos1, w0, w1, aspect, hue, t0, t1, opacity);
        return;
    }

    // Threads 57–63: no geometry (slots already counted in prim_count=114 but
    // those index slots are outside the 0..113 range we wrote — unreachable).
}

// MARK: - Spider SDF (Increment 3.5.9)
//
// Orthographic ray-march from above (ray origin above Z=0 web plane, direction (0,0,-1)).
// Fragment calls sdSpider only when in.clipXY is within bounding radius of the body.

static float spOpSmoothUnion(float d1, float d2, float k) {
    float h = saturate(0.5f + 0.5f * (d2 - d1) / k);
    return mix(d2, d1, h) - k * h * (1.0f - h);
}

static float spSdCapsule(float3 p, float3 a, float3 b, float r) {
    float3 ab = b - a, ap = p - a;
    float  t  = saturate(dot(ap, ab) / max(dot(ab, ab), 1e-8f));
    return length(ap - ab * t) - r;
}

static float spSdEllipsoid(float3 p, float3 r) {
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0f) / max(k1, 1e-8f);
}

// Full spider SDF in local spider space (body centre at origin, heading pre-applied).
static float sdSpiderLocal(float3 lp, float2 tipLocal[8]) {
    // Body: abdomen + cephalothorax, smooth-unioned
    float abdomen = spSdEllipsoid(lp - float3(0.0f, 0.0f,  0.06f), float3(0.085f, 0.080f, 0.105f));
    float head    = spSdEllipsoid(lp - float3(0.0f, 0.0f, -0.04f), float3(0.048f, 0.043f, 0.048f));
    float body    = spOpSmoothUnion(abdomen, head, 0.025f);

    // Hip offsets (local space) — 4 pairs radiating outward
    float3 hips[8] = {
        float3(-0.05f, -0.03f, 0.00f), float3(-0.05f,  0.03f, 0.00f),
        float3(-0.02f, -0.06f, 0.00f), float3(-0.02f,  0.06f, 0.00f),
        float3( 0.02f, -0.06f, 0.00f), float3( 0.02f,  0.06f, 0.00f),
        float3( 0.05f, -0.03f, 0.00f), float3( 0.05f,  0.03f, 0.00f),
    };

    float legs = 1e6f;
    for (int i = 0; i < 8; i++) {
        float3 tip  = float3(tipLocal[i].x, tipLocal[i].y, 0.0f);
        float3 hip  = hips[i];
        // Knee: midpoint + upward arc
        float3 knee = (hip + tip) * 0.5f + float3(0.0f, 0.0f, 0.07f);
        float  seg0 = spSdCapsule(lp, hip,  knee, 0.013f);
        float  seg1 = spSdCapsule(lp, knee, tip,  0.010f);
        legs = min(legs, min(seg0, seg1));
    }
    return min(body, legs);
}

// Finite-difference surface normal (6-tap tetrahedron).
static float3 calcSpiderNormal(float3 p, float2 tipLocal[8]) {
    float2 e = float2(0.0015f, 0.0f);
    return normalize(float3(
        sdSpiderLocal(p + float3(e.x,e.y,e.y), tipLocal) - sdSpiderLocal(p - float3(e.x,e.y,e.y), tipLocal),
        sdSpiderLocal(p + float3(e.y,e.x,e.y), tipLocal) - sdSpiderLocal(p - float3(e.y,e.x,e.y), tipLocal),
        sdSpiderLocal(p + float3(e.y,e.y,e.x), tipLocal) - sdSpiderLocal(p - float3(e.y,e.y,e.x), tipLocal)
    ));
}

// MARK: - Fragment Shader

/// Bioluminescent strand/dot rendering with additive blending.
///
/// D-019 warmup: bass quiver blends from features.bass_rel (cold) to
/// stems.bass_energy_rel (warm) as total stem energy crosses 2–6 %.
/// MV-3b: pre-beat anticipation brightens all strands as beat_phase01 → 1.
/// Increment 3.5.9: spider SDF overlay when spiderData->blend > 0.
fragment float4 arachne_fragment(
    MeshVertex                    in         [[stage_in]],
    constant FeatureVector&       features   [[buffer(0)]],
    constant StemFeatures&        stems      [[buffer(3)]],
    constant ArachneSpiderGPU&    spider     [[buffer(4)]])
{
    // Unpack normal: normal.z >= 10 → hub cap (circular mask); else → strand.
    bool  isHub    = in.normal.z >= 10.0f;
    float webOpacity = isHub ? (in.normal.z - 10.0f) : in.normal.z;
    webOpacity = saturate(webOpacity);

    // D-019 warmup: blend FV bass deviation with stems as stem energy warms up.
    float totalStemEnergy = stems.drums_energy + stems.bass_energy
                          + stems.other_energy + stems.vocals_energy;
    float stemMix = smoothstep(0.02f, 0.06f, totalStemEnergy);
    float bassRel = mix(features.bass_rel, stems.bass_energy_rel, stemMix);

    float dist = in.normal.y;  // 0 = hub, 1 = outer edge (strands)

    // Bass quiver: wave phase-locked to beat_phase01 — one propagation per beat.
    float quiver = 0.0f;
    if (!isHub) {
        float quiverAmp = max(0.0f, bassRel) * 0.08f;
        quiver = sin(dist * 12.0f - features.beat_phase01 * (2.0f * M_PI_F)) * quiverAmp * dist;
    }

    // MV-3b: pre-beat surge as beat_phase01 → 1.
    float anticipation = smoothstep(0.75f, 1.0f, features.beat_phase01) * 0.25f;

    // 2-layer bioluminescent glow profile.
    // isHub: circular distance mask. Strands: gaussian cross-section (core + halo).
    float profile;
    if (isHub) {
        float2 centred = in.uv * 2.0f - 1.0f;
        float  dd = length(centred);
        float  core = exp(-dd * dd * 14.0f);
        float  halo = exp(-dd * dd * 2.5f);
        profile = core + halo * 0.45f;
    } else {
        // Normalized cross-section distance from strand centerline: 0=center, 1=edge.
        float cdist = abs(in.uv.y - 0.5f) * 2.0f;
        float core  = exp(-cdist * cdist * 22.0f);   // tight silk thread
        float halo  = exp(-cdist * cdist * 3.8f);    // wide bioluminescent diffusion
        profile = core + halo * 0.45f;

        // Hub fade: strands brighten as they converge at the hub (dist→0).
        float hubFade = exp(-dist * dist * 3.5f);
        profile *= 0.55f + hubFade * 0.45f;
    }

    float hue = in.normal.x;
    float sat  = 0.92f;
    float brt  = 0.15f + quiver + anticipation + (isHub ? 0.75f : 0.60f);
    brt = saturate(brt);

    float3 color = hsv2rgb(float3(fract(hue), sat, brt));
    float  alpha = profile * webOpacity;

    // Spider overlay (Increment 3.5.9) — 3D SDF ray-march when blend > 0.
    if (spider.blend > 0.001f) {
        float2 clipXY    = in.clipXY;
        float2 bodyXY    = float2(spider.posX, spider.posY);
        float  distBody  = length(clipXY - bodyXY);

        // Only ray-march within bounding radius (leg reach + margin).
        if (distBody < 0.48f) {
            // Transform tip positions to local spider space (rotate by -heading).
            float ch = cos(-spider.heading), sh = sin(-spider.heading);
            float2 tipLocal[8];
            for (int i = 0; i < 8; i++) {
                float2 d = spider.tip[i] - bodyXY;
                tipLocal[i] = float2(d.x * ch - d.y * sh, d.x * sh + d.y * ch);
            }

            // Orthographic ray: origin above web plane, looking straight down.
            float3 rayOrig = float3(clipXY.x - bodyXY.x, clipXY.y - bodyXY.y, 1.2f);
            float3 rayDir  = float3(0.0f, 0.0f, -1.0f);

            float  t   = 0.0f;
            bool   hit = false;
            for (int step = 0; step < 64; step++) {
                float d = sdSpiderLocal(rayOrig + t * rayDir, tipLocal);
                if (d < 0.0025f) { hit = true; break; }
                if (t > 1.8f) break;
                t += d;
            }

            if (hit) {
                float3 hitP = rayOrig + t * rayDir;
                float3 nrm  = calcSpiderNormal(hitP, tipLocal);

                // PBR chitin: near-black base, iridescent clearcoat specular.
                float3 lightDir = normalize(float3(0.25f, 0.35f, 1.0f));
                float3 viewDir  = -rayDir;
                float3 halfVec  = normalize(lightDir + viewDir);
                float  nDotL    = max(dot(nrm, lightDir), 0.0f);
                float  spec     = pow(max(dot(nrm, halfVec), 0.0f), 96.0f);
                float  fresnel  = pow(1.0f - max(dot(nrm, viewDir), 0.0f), 3.0f);

                // Iridescent hue: surface-normal-based shift (angle-dependent).
                float  iridHue  = fract(nrm.x * 0.45f + nrm.y * 0.30f + 0.42f);
                float3 iridCol  = hsv2rgb(float3(iridHue, 0.88f, 1.0f));

                float3 chitin   = float3(0.018f, 0.020f, 0.022f);
                float3 spiderCol = chitin * (0.15f + nDotL * 0.55f)
                                 + iridCol * spec * 2.2f
                                 + iridCol * fresnel * 0.35f;

                // Bioluminescent rim: web glow bleeds onto spider silhouette edges.
                spiderCol += color * fresnel * 0.5f;

                float spiderA = spider.blend;
                // Additive composite: spider adds to underlying web color.
                color = color + spiderCol * spiderA;
                alpha = max(alpha, spiderA * saturate(nDotL + spec * 2.0f + fresnel));
            }
        }
    }

    return float4(color * alpha, alpha);
}

// MARK: - Vertex Fallback (M1 / M2)

/// Full-screen triangle with bioluminescent radial glow for pre-apple8 hardware.
/// Simulates a single large stable web centered on screen.
vertex MeshVertex arachne_fallback_vertex(uint vid [[vertex_id]])
{
    float2 uv    = float2(float((vid << 1u) & 2u), float(vid & 2u)) * 0.5f;
    float2 ndcXY = uv * 4.0f - 1.0f;

    MeshVertex out;
    out.position = float4(ndcXY, 0.0f, 1.0f);
    out.clipXY   = ndcXY;

    // Simulate distance-from-hub for the fragment's glow falloff.
    float dist = saturate(length(uv * 2.0f - 1.0f));
    out.normal  = float3(0.55f, dist, 0.85f);  // hue=cyan-blue, dist, opacity
    out.uv      = float2(0.5f, 0.5f);          // centre of strand → fully opaque edge mask
    return out;
}
