// FerrofluidOcean.metal — Ferrofluid in a glass dish, music-reactive.
//
// Photorealistic ferrofluid: dark glossy spikes rising from a black liquid
// pool inside a wide shallow glass dish (petri dish form factor).
//
// Reference: eye-level camera looking at the glass from the side.  The glass
// has a thick visible base, clear walls with bright edge highlights, and the
// ferrofluid is clearly contained inside.  Bright background makes the glass
// silhouette readable.
//
// Audio mapping:
//   - Bass → central spike height (PRIMARY)
//   - Mid → ring 1 spike heights (6 spikes)
//   - Treble (sqrt-boosted) → ring 2 spike heights (8 spikes, denser outer ring)
//   - Beat → tip glow + momentary height accent
//
// Performance: SpikeParams precomputed once per pixel, passed to SDF by ref.
// Rendered through PostProcessChain (use_post_process: true).

constant float FO_PI = 3.14159265;
constant float FO_F0 = 0.04;       // ferrofluid Fresnel
constant float FO_GLASS_F0 = 0.04; // glass Fresnel

// ── Glass dish geometry ───────────────────────────────────────────
// Wide shallow dish like a petri dish / watch glass.
// Thick glass base is the defining visual feature.
constant float DISH_INNER_R  = 2.5;   // inner radius of dish cavity
constant float DISH_OUTER_R  = 2.7;   // outer radius (wall thickness 0.2)
constant float DISH_WALL_H   = 0.7;   // wall height above base top
constant float DISH_BASE_Y   = -0.15; // bottom of glass base
constant float DISH_BASE_TOP = 0.0;   // top of glass base (floor of cavity)
constant float DISH_BASE_THICK = 0.15; // base thickness

// Ferrofluid liquid sits on the cavity floor
constant float LIQUID_LEVEL = 0.12;   // resting liquid level above base top

// MARK: - Hash / Noise

float fo_hash(float n) { return fract(sin(n) * 43758.5453); }
float fo_hash2(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// MARK: - Utility

float fo_smin(float a, float b, float k) {
    float h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// MARK: - SDF Primitives

float fo_sdRoundCone(float3 p, float r1, float r2, float h) {
    float2 q = float2(length(p.xz), p.y);
    float b = (r1 - r2) / h;
    float a = sqrt(max(1.0 - b * b, 0.001));
    float k = dot(q, float2(-b, a));
    if (k < 0.0) return length(q) - r1;
    if (k > a * h) return length(q - float2(0.0, h)) - r2;
    return dot(q, float2(a, b)) - r1;
}

// MARK: - Precomputed Spike Geometry

struct SpikeParams {
    float centerH, centerBase, centerSminK;
    float r1H[6], r1Base[6];
    float r2H[8], r2Base[8];
    float ring1R, ring2R;
    float liquidY;  // actual liquid surface Y
};

// MARK: - Scene SDF

float fo_scene(float3 p, thread const SpikeParams& sp) {
    float r = length(p.xz);

    // Liquid pool: flat surface at liquidY, fills inside the dish
    float liquidTop = p.y - sp.liquidY;
    float liquidInside = r - (DISH_INNER_R - 0.05);
    float liquidBelow = -(p.y - DISH_BASE_TOP);
    float liquid = max(max(liquidTop, liquidInside), liquidBelow);
    float d = liquid;

    // Spatial culling: skip spike evaluation if we're far from the dish.
    // Spikes live within ring2R + some height margin. Points well outside
    // can only see the liquid pool surface, so return early.
    float spikeMaxR = sp.ring2R + 0.6;
    if (r > spikeMaxR || p.y < DISH_BASE_Y - 0.1 || p.y > sp.liquidY + 3.5) {
        return d;
    }

    // Central spike rising from liquid surface
    float3 sBase = float3(0, sp.liquidY, 0);
    d = fo_smin(d,
        fo_sdRoundCone(p - sBase, sp.centerBase, 0.005, sp.centerH),
        sp.centerSminK);

    // Ring 1: 6 spikes
    if (r < sp.ring1R + 0.8) {
        for (int i = 0; i < 6; i++) {
            float angle = float(i) / 6.0 * 2.0 * FO_PI;
            float3 offset = float3(cos(angle) * sp.ring1R, 0,
                                   sin(angle) * sp.ring1R);
            float3 q = p - (sBase + offset);
            // Lean outward slightly
            q.xz -= normalize(offset.xz) * q.y * 0.08;
            d = fo_smin(d,
                fo_sdRoundCone(q, sp.r1Base[i], 0.004, sp.r1H[i]),
                0.15);
        }
    }

    // Ring 2: 8 spikes (offset from ring 1)
    if (r < sp.ring2R + 0.6 && r > sp.ring2R - 1.5) {
        for (int i = 0; i < 8; i++) {
            float angle = float(i) / 8.0 * 2.0 * FO_PI + FO_PI / 6.0;
            float3 offset = float3(cos(angle) * sp.ring2R, 0,
                                   sin(angle) * sp.ring2R);
            float3 q = p - (sBase + offset);
            q.xz -= normalize(offset.xz) * q.y * 0.12;
            d = fo_smin(d,
                fo_sdRoundCone(q, sp.r2Base[i], 0.003, sp.r2H[i]),
                0.12);
        }
    }

    return d;
}

// MARK: - Normal

float3 fo_normal(float3 p, thread const SpikeParams& sp) {
    float eps = 0.001;
    float d = fo_scene(p, sp);
    return normalize(float3(
        fo_scene(p + float3(eps, 0, 0), sp) - d,
        fo_scene(p + float3(0, eps, 0), sp) - d,
        fo_scene(p + float3(0, 0, eps), sp) - d
    ));
}

// MARK: - Ray March

float fo_march(float3 ro, float3 rd, thread const SpikeParams& sp) {
    float t = 0.0;
    for (int i = 0; i < 100; i++) {
        float3 p = ro + rd * t;
        float d = fo_scene(p, sp);
        if (d < 0.0005) return t;
        t += d * 0.8;
        if (t > 25.0) break;
    }
    return -1.0;
}

// MARK: - Ambient Occlusion

float fo_ao(float3 p, float3 n, thread const SpikeParams& sp) {
    float occ = 0.0;
    float sca = 1.0;
    for (int i = 0; i < 3; i++) {
        float h = 0.02 + 0.14 * float(i) / 2.0;
        float d = fo_scene(p + n * h, sp);
        occ += (h - d) * sca;
        sca *= 0.7;
    }
    return saturate(1.0 - 2.5 * occ);
}

// MARK: - Glass Dish (analytical intersection)
//
// The dish is: outer cylinder (walls) + thick base disc + rim annulus.
// Camera is at eye level so the thick glass base is the most prominent
// glass feature — it defines the dish silhouette.

struct GlassHit {
    float t;
    float3 normal;
    bool hit;
    bool isBase;
    bool isRim;
    bool isInnerWall;
};

GlassHit fo_glassDish(float3 ro, float3 rd) {
    GlassHit best;
    best.t = 1e6;
    best.hit = false;
    best.isBase = false;
    best.isRim = false;
    best.isInnerWall = false;

    float a = rd.x * rd.x + rd.z * rd.z;
    float b = 2.0 * (ro.x * rd.x + ro.z * rd.z);

    // ── Outer cylinder wall ───────────────────────────────────────
    float cOut = ro.x * ro.x + ro.z * ro.z - DISH_OUTER_R * DISH_OUTER_R;
    float discOut = b * b - 4.0 * a * cOut;
    if (discOut >= 0.0) {
        float sqD = sqrt(discOut);
        float t0 = (-b - sqD) / (2.0 * a);
        float t1 = (-b + sqD) / (2.0 * a);

        for (int s = 0; s < 2; s++) {
            float tc = (s == 0) ? t0 : t1;
            if (tc > 0.01 && tc < best.t) {
                float yh = ro.y + rd.y * tc;
                if (yh >= DISH_BASE_Y && yh <= DISH_BASE_TOP + DISH_WALL_H) {
                    float3 p = ro + rd * tc;
                    best.t = tc;
                    best.normal = normalize(float3(p.x, 0, p.z))
                                * (s == 0 ? 1.0 : -1.0);
                    best.hit = true;
                    best.isBase = false;
                    best.isRim = false;
                    best.isInnerWall = false;
                }
            }
        }
    }

    // ── Inner cylinder wall (inside of dish cavity) ───────────────
    float cIn = ro.x * ro.x + ro.z * ro.z - DISH_INNER_R * DISH_INNER_R;
    float discIn = b * b - 4.0 * a * cIn;
    if (discIn >= 0.0) {
        float sqD = sqrt(discIn);
        float t0 = (-b - sqD) / (2.0 * a);
        float t1 = (-b + sqD) / (2.0 * a);

        for (int s = 0; s < 2; s++) {
            float tc = (s == 0) ? t0 : t1;
            if (tc > 0.01 && tc < best.t) {
                float yh = ro.y + rd.y * tc;
                // Inner wall only exists above base top, within wall height
                if (yh >= DISH_BASE_TOP && yh <= DISH_BASE_TOP + DISH_WALL_H) {
                    float3 p = ro + rd * tc;
                    best.t = tc;
                    best.normal = -normalize(float3(p.x, 0, p.z))
                                * (s == 0 ? 1.0 : -1.0);
                    best.hit = true;
                    best.isBase = false;
                    best.isRim = false;
                    best.isInnerWall = true;
                }
            }
        }
    }

    // ── Base bottom (underside of thick glass base) ───────────────
    if (abs(rd.y) > 0.0001) {
        float tBot = (DISH_BASE_Y - ro.y) / rd.y;
        if (tBot > 0.01 && tBot < best.t) {
            float3 p = ro + rd * tBot;
            if (length(p.xz) <= DISH_OUTER_R) {
                best.t = tBot;
                best.normal = float3(0, -1, 0);
                best.hit = true;
                best.isBase = true;
                best.isRim = false;
                best.isInnerWall = false;
            }
        }

        // Base top (inside the cavity — glass floor where liquid sits)
        float tTop = (DISH_BASE_TOP - ro.y) / rd.y;
        if (tTop > 0.01 && tTop < best.t) {
            float3 p = ro + rd * tTop;
            float r = length(p.xz);
            // Only the annular area between inner wall and outer wall
            if (r > DISH_INNER_R && r <= DISH_OUTER_R) {
                best.t = tTop;
                best.normal = float3(0, 1, 0);
                best.hit = true;
                best.isBase = true;
                best.isRim = false;
                best.isInnerWall = false;
            }
        }
    }

    // ── Rim (top annular edge of the wall) ────────────────────────
    if (abs(rd.y) > 0.0001) {
        float tRim = (DISH_BASE_TOP + DISH_WALL_H - ro.y) / rd.y;
        if (tRim > 0.01 && tRim < best.t) {
            float3 p = ro + rd * tRim;
            float r = length(p.xz);
            if (r >= DISH_INNER_R && r <= DISH_OUTER_R) {
                best.t = tRim;
                best.normal = float3(0, 1, 0);
                best.hit = true;
                best.isBase = false;
                best.isRim = true;
                best.isInnerWall = false;
            }
        }
    }

    return best;
}

// MARK: - Glass Crack Pattern

float fo_crackPattern(float2 p, float energy) {
    float2 sp2 = p * 3.0;
    float2 ip = floor(sp2);
    float2 fp = fract(sp2);
    float minD1 = 1.0, minD2 = 1.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 nb = float2(float(i), float(j));
            float2 cc = float2(
                fo_hash2(ip + nb),
                fo_hash2(ip + nb + float2(37.0, 91.0)));
            float d = length(nb + cc - fp);
            if (d < minD1) { minD2 = minD1; minD1 = d; }
            else if (d < minD2) { minD2 = d; }
        }
    }
    float edge = minD2 - minD1;
    float w = mix(0.001, 0.06, saturate(energy));
    return (1.0 - smoothstep(0.0, w, edge)) * smoothstep(0.5, 0.8, energy);
}

// MARK: - Environment (club lighting: spots, strobes, disco ball scatter)

float3 fo_environment(float3 rd, float time, float bass, float mid,
                      float treble, float beat, float vocalsE, float drumsE) {
    // Dark club backdrop — darkness makes colored lights pop
    float3 env = float3(0.03, 0.02, 0.05);

    // Subtle vertical gradient for depth
    float sky = smoothstep(-0.5, 1.0, rd.y);
    env += float3(0.02, 0.02, 0.04) * sky;

    // ── Colored spotlights — WIDE beams, vivid saturated colors ────
    // Lower exponents (2-3) = broader wash; higher intensity multipliers

    // Magenta/pink spot — vocals-reactive, sweeps left-right
    float3 s1Dir = normalize(float3(
        sin(time * 0.15) * 0.8, 0.3, cos(time * 0.12) * 0.5));
    float s1 = pow(saturate(dot(rd, s1Dir)), 2.5);
    env += float3(1.0, 0.05, 0.5) * s1 * (0.5 + vocalsE * 4.0);

    // Electric blue spot — mid-reactive, orbits slowly
    float3 s2Dir = normalize(float3(
        cos(time * 0.1 + 2.0) * 0.7, 0.25,
        sin(time * 0.13 + 1.0) * 0.8));
    float s2 = pow(saturate(dot(rd, s2Dir)), 2.5);
    env += float3(0.05, 0.3, 1.0) * s2 * (0.5 + mid * 5.0);

    // Hot amber/orange spot — bass-reactive, pulsing
    float3 s3Dir = normalize(float3(
        sin(time * 0.08 + 4.0) * 0.6, 0.4,
        cos(time * 0.09 + 3.0) * 0.7));
    float s3 = pow(saturate(dot(rd, s3Dir)), 2.0);
    env += float3(1.0, 0.35, 0.02) * s3 * (0.4 + bass * 4.0);

    // Emerald green spot — treble-reactive, from below-right
    float3 s4Dir = normalize(float3(0.6, -0.3, 0.5));
    float s4 = pow(saturate(dot(rd, s4Dir)), 3.0);
    env += float3(0.02, 0.8, 0.3) * s4 * (0.3 + treble * 10.0);

    // Deep purple spot — opposite side, slow sweep
    float3 s5Dir = normalize(float3(
        -sin(time * 0.07) * 0.5, 0.5, -cos(time * 0.11) * 0.6));
    float s5 = pow(saturate(dot(rd, s5Dir)), 3.0);
    env += float3(0.4, 0.05, 0.8) * s5 * (0.4 + bass * 2.0);

    // ── Disco ball scatter — larger, brighter flecks ──────────────
    float3 scatterDir = rd;
    float ca = cos(time * 0.6);
    float sa = sin(time * 0.6);
    scatterDir.xz = float2(scatterDir.x * ca - scatterDir.z * sa,
                            scatterDir.x * sa + scatterDir.z * ca);

    float2 angles = float2(atan2(scatterDir.z, scatterDir.x),
                           asin(clamp(scatterDir.y, -1.0, 1.0)));
    // Larger dots (lower grid density, wider smoothstep)
    float2 grid1 = fract(angles * float2(4.0, 3.0) + time * float2(0.2, 0.15));
    float dot1 = smoothstep(0.12, 0.0, length(grid1 - 0.5));
    float2 grid2 = fract(angles * float2(6.0, 4.0) - time * float2(0.15, 0.25));
    float dot2 = smoothstep(0.08, 0.0, length(grid2 - 0.5));

    float hue = fract(angles.x * 0.3 + time * 0.08);
    float3 scatterCol = float3(
        0.5 + 0.5 * sin(hue * 6.28),
        0.5 + 0.5 * sin(hue * 6.28 + 2.09),
        0.5 + 0.5 * sin(hue * 6.28 + 4.19));
    float scatterI = (dot1 * 1.5 + dot2) * (0.3 + drumsE * 2.0 + beat * 1.0);
    env += scatterCol * scatterI;

    // ── Overhead panel for specular on liquid ──────────────────────
    float overhead = pow(saturate(rd.y), 2.0);
    env += float3(0.12, 0.12, 0.18) * overhead;

    // ── Strobe flash on beat ──────────────────────────────────────
    float strobe = pow(beat, 1.5);
    env += float3(1.2, 1.2, 1.5) * strobe;           // white flash
    env += float3(0.3, 0.1, 0.6) * beat;              // purple afterglow

    // Bass breathe on overall scene
    env *= 0.8 + bass * 0.5;

    return env;
}

// MARK: - PBR

float fo_D_GGX(float NdH, float roughness) {
    float a2 = roughness * roughness;
    a2 *= a2;
    float d = NdH * NdH * (a2 - 1.0) + 1.0;
    return a2 / (FO_PI * d * d + 1e-7);
}

float fo_G_Smith(float NdV, float NdL, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return (NdV / (NdV * (1.0 - k) + k)) * (NdL / (NdL * (1.0 - k) + k));
}

float fo_F_Schlick(float cosTheta, float f0) {
    return f0 + (1.0 - f0) * pow(saturate(1.0 - cosTheta), 5.0);
}

float3 fo_specular(float3 N, float3 V, float3 L, float3 lightCol,
                   float roughness, float f0) {
    float3 H = normalize(L + V);
    float NdH = max(dot(N, H), 0.0);
    float NdL = max(dot(N, L), 0.0);
    float NdV = max(dot(N, V), 0.001);
    float HdV = max(dot(H, V), 0.0);
    float D = fo_D_GGX(NdH, roughness);
    float G = fo_G_Smith(NdV, NdL, roughness);
    float F = fo_F_Schlick(HdV, f0);
    return float3(D * G * F / (4.0 * NdV * NdL + 0.001)) * lightCol * NdL;
}

// MARK: - Fragment

fragment float4 ferrofluid_ocean_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& features [[buffer(0)]],
    constant float* fftMagnitudes [[buffer(1)]],
    constant float* waveformData [[buffer(2)]],
    constant StemFeatures& stems [[buffer(3)]]
) {
    float2 uv = in.uv;
    float asp = features.aspect_ratio;
    float time = features.time;

    // ── Audio ─────────────────────────────────────────────────────
    float bass = max(features.bass, stems.bass_energy);
    float mid = max(features.mid, stems.vocals_energy);
    float treble = max(features.treble, stems.drums_energy * 0.5);
    float beat = max(features.beat_bass, stems.drums_beat);
    float vocalsE = stems.vocals_energy;
    float drumsE = stems.drums_energy;

    // Treble boost: real music treble maxes at ~0.01–0.02 after AGC.
    // sqrt(0.01)*3 = 0.30, sqrt(0.02)*3 = 0.42
    float trebleBoosted = sqrt(max(treble, 0.0)) * 3.0;

    // Crack energy
    float crackEnergy = smoothstep(1.5, 3.5, bass + mid * 2.0 + beat * 3.0);

    float bands[6] = {
        features.sub_bass, features.low_bass, features.low_mid,
        features.mid_high, features.high_mid, features.high_freq
    };

    // ── Precompute spike geometry ─────────────────────────────────
    // Ferrofluid spikes must be SHARP and DISTINCT — tall narrow cones
    // with tight smin blending so each spike is individually visible.
    // Even in silence, spikes should be present (ferrofluid always has texture).
    SpikeParams sp;
    sp.ring1R = 0.65 + bass * 0.08;
    sp.ring2R = 1.2 + bass * 0.1;
    sp.liquidY = DISH_BASE_TOP + LIQUID_LEVEL + bass * 0.02;

    // Central spike (bass)
    sp.centerH = 0.15 + bass * 1.8 + beat * 0.4;
    sp.centerBase = 0.16 + bass * 0.1;
    sp.centerSminK = 0.18 + bass * 0.06;

    // Ring 1 (mid)
    for (int i = 0; i < 6; i++) {
        float variation = 0.5 + bands[i];
        float drive = mid * variation;
        sp.r1H[i] = 0.06 + drive * 1.6 + beat * 0.25;
        sp.r1Base[i] = 0.10 + drive * 0.06;
    }

    // Ring 2 (treble boosted) — 8 spikes for denser pattern
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float bandPos = fi / 8.0 * 6.0;
        int bIdx = int(bandPos) % 6;
        int bNext = (bIdx + 1) % 6;
        float bandE = mix(bands[bIdx], bands[bNext], fract(bandPos));
        float variation = 0.5 + bandE;
        float drive = trebleBoosted * variation;
        sp.r2H[i] = 0.04 + drive * 1.2 + beat * 0.12;
        sp.r2Base[i] = 0.07 + drive * 0.04;
    }

    // ── Camera: eye level, looking from the side ──────────────────
    // Matches reference: horizontal view, slightly above dish center
    float3 ro = float3(0.0, 0.35, 6.5);
    float3 target = float3(0.0, 0.15, 0.0);
    float3 fwd = normalize(target - ro);
    float3 right = normalize(cross(fwd, float3(0, 1, 0)));
    float3 up = cross(right, fwd);
    float2 screen = (uv - 0.5) * float2(asp, -1.0);
    float3 rd = normalize(screen.x * right + screen.y * up + 2.5 * fwd);

    // ── Lighting ──────────────────────────────────────────────────
    float3 keyDir = normalize(float3(0.2, 1.0, 0.5));
    float3 keyLight = float3(1.0, 0.98, 0.95) * 6.0;
    float3 fillDir = normalize(float3(-0.6, 0.6, -0.3));
    float3 fillLight = float3(0.7, 0.72, 0.85) * 2.5;
    float3 rimDir = normalize(float3(-0.4, 0.3, -0.9));
    float3 rimBase = mix(float3(0.3, 0.2, 0.6), float3(0.15, 0.35, 0.5),
                         sin(time * 0.15) * 0.5 + 0.5);
    float3 rimLight = rimBase * (3.0 + beat * 4.0);

    // ── Background ────────────────────────────────────────────────
    float3 color = fo_environment(rd, time, bass, mid, treble, beat, vocalsE, drumsE);

    // ── Glass dish ────────────────────────────────────────────────
    GlassHit glass = fo_glassDish(ro, rd);

    // ── Ray march ferrofluid ──────────────────────────────────────
    float t = fo_march(ro, rd, sp);

    bool fluidHit = (t > 0.0);
    bool glassFirst = glass.hit && (!fluidHit || glass.t < t);
    bool fluidFirst = fluidHit && (!glass.hit || t < glass.t);

    // ── Shade ferrofluid ──────────────────────────────────────────
    float3 fluidColor = float3(0.0);
    if (fluidHit) {
        float3 hp = ro + rd * t;
        float3 N = fo_normal(hp, sp);
        float3 V = -rd;
        float NdV = max(dot(N, V), 0.001);

        // Very low roughness — mirror-like glossy black
        float roughness = 0.03;
        float F = fo_F_Schlick(NdV, FO_F0);
        float3 envRefl = fo_environment(reflect(rd, N), time, bass, mid, treble, beat, vocalsE, drumsE);

        float3 spec = fo_specular(N, V, keyDir, keyLight, roughness, FO_F0)
                    + fo_specular(N, V, fillDir, fillLight, roughness, FO_F0)
                    + fo_specular(N, V, rimDir, rimLight, roughness, FO_F0);

        float ao = fo_ao(hp, N, sp);

        float3 diffuse = float3(0.003, 0.003, 0.005);
        float3 ambient = diffuse * fo_environment(N, time, bass, mid, treble, beat, vocalsE, drumsE) * 0.2;
        float3 reflection = envRefl * F;

        fluidColor = (ambient + reflection + spec) * ao;

        // Beat glow on spike tips
        if (beat > 0.1) {
            float beatI = smoothstep(0.1, 0.6, beat);
            float maxH = 0.3 + bass * 2.5 + mid * 2.0;
            float tipGlow = smoothstep(0.1, 0.5, hp.y / max(maxH, 0.3));
            float hue = time * 0.2;
            float3 gc = float3(
                0.3 + 0.2 * sin(hue),
                0.15 + 0.15 * sin(hue + 2.1),
                0.8 + 0.2 * sin(hue + 4.2));
            fluidColor += gc * beatI * tipGlow * 3.0;
        }

        // Flux edge flash
        float flux = features.spectral_flux;
        if (flux > 0.25) {
            float edge = pow(1.0 - NdV, 3.0);
            fluidColor += float3(0.1, 0.15, 0.3) * smoothstep(0.25, 0.7, flux)
                        * edge * 2.0;
        }
    }

    // ── Shade glass with refraction ──────────────────────────────
    // Real glass is visible because it REFRACTS light — the view through
    // glass is distorted/shifted. Without refraction, glass is invisible.
    if (glass.hit && glassFirst) {
        float3 gp = ro + rd * glass.t;
        float3 gn = glass.normal;
        float gNdV = abs(dot(gn, -rd));
        float fresnel = fo_F_Schlick(gNdV, FO_GLASS_F0);

        // ── Reflected component ──────────────────────────────────
        float3 reflDir = reflect(rd, gn);
        float3 reflColor = fo_environment(reflDir, time, bass, mid,
                                          treble, beat, vocalsE, drumsE);

        // ── Refracted component (view through glass) ─────────────
        // IOR of glass ≈ 1.5. Refract entering, then exiting.
        float eta_enter = 1.0 / 1.5;  // air → glass (IOR 1.5)
        float3 refr1 = refract(rd, gn, eta_enter);

        float3 refractedColor = float3(0.0);
        if (length(refr1) > 0.001) {
            // Travel through glass wall, find exit surface
            // For walls: enter outer → exit inner (or vice versa)
            // For base: enter bottom → exit top
            float3 entryPt = gp + refr1 * 0.01;
            GlassHit exitHit = fo_glassDish(entryPt, refr1);

            float3 exitDir = rd; // fallback: undeviated
            if (exitHit.hit && exitHit.t < 2.0) {
                // Refract exiting glass → air
                float3 exitNormal = exitHit.normal;
                // Normal should point INTO glass (from exit surface)
                // Flip if needed so it faces the refracted ray
                if (dot(exitNormal, refr1) > 0.0) exitNormal = -exitNormal;
                float3 refr2 = refract(refr1, -exitNormal, 1.5);
                if (length(refr2) > 0.001) {
                    exitDir = refr2;
                } else {
                    // Total internal reflection
                    exitDir = reflect(refr1, -exitNormal);
                }
            } else {
                exitDir = refr1; // thin geometry, pass through
            }

            // March refracted ray to see if it hits ferrofluid inside dish
            float3 exitPt = exitHit.hit ? entryPt + refr1 * exitHit.t : gp;
            float tRefract = fo_march(exitPt + exitDir * 0.02, exitDir, sp);
            if (tRefract > 0.0) {
                // Ferrofluid visible through glass — shade it
                float3 hp2 = exitPt + exitDir * (tRefract + 0.02);
                float3 N2 = fo_normal(hp2, sp);
                float3 V2 = -exitDir;
                float F2 = fo_F_Schlick(max(dot(N2, V2), 0.001), FO_F0);
                float3 envRefl2 = fo_environment(reflect(exitDir, N2), time,
                    bass, mid, treble, beat, vocalsE, drumsE);
                float3 spec2 = fo_specular(N2, V2, keyDir, keyLight, 0.03, FO_F0);
                refractedColor = envRefl2 * F2 + spec2;
            } else {
                // See environment through glass (distorted)
                refractedColor = fo_environment(exitDir, time, bass, mid,
                    treble, beat, vocalsE, drumsE);
            }

            // Glass absorption: slight green tint, thicker = more color
            float thickness = exitHit.hit ? exitHit.t : 0.2;
            float3 absorption = exp(-float3(0.8, 0.2, 0.6) * thickness * 0.5);
            refractedColor *= absorption;
        } else {
            // Total internal reflection at entry
            fresnel = 1.0;
            refractedColor = float3(0.0);
        }

        // ── Specular highlights (define glass edges) ─────────────
        float3 gH1 = normalize(keyDir + (-rd));
        float gSpec1 = pow(max(dot(gn, gH1), 0.0), 128.0)
                     * max(dot(gn, keyDir), 0.0) * 5.0;
        float3 gH2 = normalize(fillDir + (-rd));
        float gSpec2 = pow(max(dot(gn, gH2), 0.0), 64.0)
                     * max(dot(gn, fillDir), 0.0) * 2.0;

        // Rim catch light
        float rimCatch = pow(1.0 - gNdV, 2.5);

        // ── Compose glass: Fresnel blend reflected + refracted ───
        float3 glassColor = mix(refractedColor, reflColor, fresnel);
        glassColor += float3(1.0) * gSpec1;
        glassColor += float3(0.8, 0.85, 1.0) * gSpec2;
        glassColor += float3(0.5, 0.55, 0.65) * rimCatch * 0.6;

        if (glass.isRim) {
            float topCatch = pow(saturate(dot(gn, keyDir)), 1.5);
            glassColor += float3(0.8, 0.8, 1.0) * topCatch;
            glassColor += float3(0.12, 0.12, 0.16);
        }

        if (glass.isBase) {
            glassColor += float3(0.06, 0.08, 0.07);
        }

        // ── Cracks from high energy ──────────────────────────────
        if (crackEnergy > 0.0) {
            float2 crackUV;
            if (glass.isRim || glass.isBase) {
                crackUV = gp.xz / DISH_OUTER_R;
            } else {
                crackUV = float2(atan2(gp.z, gp.x) / FO_PI,
                    (gp.y - DISH_BASE_Y) / (DISH_WALL_H + DISH_BASE_THICK));
            }
            float crack = fo_crackPattern(crackUV * 2.0, crackEnergy);
            float3 envC = fo_environment(gn, time, bass, mid,
                                         treble, beat, vocalsE, drumsE);
            float3 crackColor = mix(float3(0.5, 0.6, 0.8), envC * 2.0, 0.3);
            glassColor += crackColor * crack * crackEnergy * 4.0;
        }

        color = glassColor;

    } else if (glass.hit && fluidFirst) {
        // Fluid in front of glass — just add subtle glass rim highlight
        color = fluidColor;
        float gNdV2 = abs(dot(glass.normal, -rd));
        float rimCatch2 = pow(1.0 - gNdV2, 3.0);
        color += float3(0.3, 0.35, 0.4) * rimCatch2 * 0.2;
    } else if (fluidFirst) {
        color = fluidColor;
    }

    // Vignette
    float2 vc = uv - 0.5;
    color *= 1.0 - dot(vc, vc) * 0.4;

    color = min(color, 25.0);
    return float4(color, 1.0);
}
