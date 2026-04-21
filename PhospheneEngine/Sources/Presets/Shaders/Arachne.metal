// Arachne.metal — Bioluminescent spider-web field, 3D SDF ray march (Increment 3.5.10).
//
// Replaces mesh-shader preset with a full 3D ray-marched scene for proper
// strand geometry, depth, and lighting. ArachneState / ArachneState+Spider logic
// is unchanged — web pool and spider buffers carry over directly.
//
// Scene: up to 12 webs from pool + 1 permanent anchor web at origin.
// Each web is a flat disc of SDF tubes (radials + spiral), tilted by a seed-
// derived normal so each web has a unique 3D orientation. The spider SDF from
// Increment 3.5.9 is preserved byte-for-byte.
//
// Buffer bindings:
//   buffer(0) = FeatureVector      (192 bytes)
//   buffer(3) = StemFeatures       (256 bytes)
//   buffer(6) = ArachneWebGPU[12]  (768 bytes — ArachneState.webBuffer, raw array)
//   buffer(7) = ArachneSpiderGPU   (80 bytes  — ArachneState.spiderBuffer)
//
// D-026 deviation-first, D-019 warmup, D-037: anchor web guarantees non-black
// even with zeroed pool (acceptance tests run before ArachneState pre-seeds webs).

// ── Structs (byte-match Swift counterparts) ───────────────────────────────────

/// 64 bytes — matches Swift WebGPU in ArachneState.swift.
struct ArachneWebGPU {
    float hub_x, hub_y, radius, depth;
    float rot_angle; uint anchor_count; float spiral_revolutions; uint rng_seed;
    float birth_beat_phase; uint stage; float progress, opacity;
    float birth_hue, birth_sat, birth_brt; uint is_alive;
};

/// 80 bytes — matches Swift ArachneSpiderGPU in ArachneState+Spider.swift.
struct ArachneSpiderGPU {
    float blend, posX, posY, heading;
    float2 tip[8];
};

// ── Constants ─────────────────────────────────────────────────────────────────

constant int   kArachWebs    = 12;
constant int   kArachSpokes  = 12;
constant float kArachCamZ    = -3.0;    // camera Z (world units)
constant float kArachFovTan  = 0.5774;  // tan(30°) → 60° vertical FOV

// ── Geometry helpers ──────────────────────────────────────────────────────────

/// Unsigned integer hash → float [0, 1).
static float arachHash(uint seed) {
    seed = (seed ^ 61u) ^ (seed >> 16u);
    seed *= 9u;
    seed = seed ^ (seed >> 4u);
    seed *= 0x27d4eb2du;
    seed = seed ^ (seed >> 15u);
    return float(seed) * (1.0 / 4294967296.0);
}

/// Angular distance (UV units) from point to the nearest of kArachSpokes radials.
static float arachRadialDist(float2 p, float r) {
    float theta = atan2(p.y, p.x);
    float step  = 2.0 * M_PI_F / float(kArachSpokes);
    float norm  = fract((theta + 2.0 * M_PI_F) / step);
    float fold  = abs(norm - 0.5);
    return fold * step * r;
}

/// Angular distance (UV units) from point to nearest arm of Archimedean spiral.
static float arachSpiralDist(float2 p, float r, float radius, float turns) {
    float theta      = atan2(p.y, p.x);
    float spirAngle  = theta - (r / radius) * turns * 2.0 * M_PI_F;
    float fold       = abs(fract(spirAngle / (2.0 * M_PI_F)) - 0.5);
    return fold * 2.0 * M_PI_F * r;
}

/// 3D SDF of a single spider web lying in a tilted plane.
/// Returns distance to the nearest strand surface (tube extruded from 2D web SDF).
static float sdWebElement(
    float3 p,
    float3 center,
    float  rotAngle,
    float  radius,
    float  spiralTurns,
    float  tubeRadius,
    float  vibAmp,
    float  vibPhase,
    uint   seedTilt,
    uint   stage,
    float  progress
) {
    // Derive a unique tilt for this web from its spawn seed.
    float tx = (arachHash(seedTilt    ) - 0.5) * 0.30;
    float ty = (arachHash(seedTilt + 7) - 0.5) * 0.22;
    float3 wZ = normalize(float3(tx, ty, -1.0));
    float3 wX = normalize(cross(float3(0, 1, 0), wZ));
    float3 wY = cross(wZ, wX);

    float3 dp     = p - center;
    float  lZ     = dot(dp, wZ);
    float  lX     = dot(dp, wX);
    float  lY     = dot(dp, wY);

    // Apply in-plane rotation.
    float ca = cos(rotAngle), sa = sin(rotAngle);
    float2 pLocal = float2(lX * ca + lY * sa, -lX * sa + lY * ca);
    float  r      = length(pLocal);

    // Hub sphere — always present once the web is alive.
    float hubSDF = length(dp) - 0.020;

    // No strands outside the rim or at the hub cap origin.
    if (r < 0.001 || r > radius * 1.03) return hubSDF;

    // Radial spokes (stage >= 1: radial, spiral, stable, evicting).
    float minStrand = 1e6;
    if (stage >= 1u) {
        float rDist    = arachRadialDist(pLocal, r);
        // Beat-phase-locked transverse vibration plucks the radials.
        float vibR     = sin(r * 20.0 - vibPhase) * vibAmp;
        float rDistVib = abs(rDist + vibR);
        minStrand = length(float2(max(rDistVib - tubeRadius, 0.0), lZ)) - tubeRadius;
    }

    // Spiral capture threads (stage >= 2: spiral, stable, evicting).
    if (stage >= 2u) {
        float progressR = (stage == 2u) ? (progress * radius) : radius;
        if (r <= progressR + 0.01) {
            float sDist    = arachSpiralDist(pLocal, r, radius, spiralTurns);
            float vibS     = sin(r * 15.0 - vibPhase + 1.2) * vibAmp * 0.65;
            float sDistVib = abs(sDist + vibS);
            float spirTube = tubeRadius * 0.60;
            float spirSDF  = length(float2(max(sDistVib - spirTube, 0.0), lZ)) - spirTube;
            minStrand = min(minStrand, spirSDF);
        }
    }

    return min(hubSDF, minStrand);
}

// ── Spider SDF (Increment 3.5.9, preserved) ───────────────────────────────────

static float spOpSmoothUnion(float d1, float d2, float k) {
    float h = saturate(0.5 + 0.5 * (d2 - d1) / k);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}

static float spSdCapsule(float3 p, float3 a, float3 b, float r) {
    float3 ab = b - a, ap = p - a;
    float  t  = saturate(dot(ap, ab) / max(dot(ab, ab), 1e-8));
    return length(ap - ab * t) - r;
}

static float spSdEllipsoid(float3 p, float3 r) {
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / max(k1, 1e-8);
}

static float sdSpiderLocal(float3 lp, float2 tipLocal[8]) {
    float abdomen = spSdEllipsoid(lp - float3(0, 0,  0.06), float3(0.085, 0.080, 0.105));
    float head    = spSdEllipsoid(lp - float3(0, 0, -0.04), float3(0.048, 0.043, 0.048));
    float body    = spOpSmoothUnion(abdomen, head, 0.025);
    float3 hips[8] = {
        float3(-0.05, -0.03, 0.00), float3(-0.05,  0.03, 0.00),
        float3(-0.02, -0.06, 0.00), float3(-0.02,  0.06, 0.00),
        float3( 0.02, -0.06, 0.00), float3( 0.02,  0.06, 0.00),
        float3( 0.05, -0.03, 0.00), float3( 0.05,  0.03, 0.00),
    };
    float legs = 1e6;
    for (int i = 0; i < 8; i++) {
        float3 tip  = float3(tipLocal[i].x, tipLocal[i].y, 0.0);
        float3 hip  = hips[i];
        float3 knee = (hip + tip) * 0.5 + float3(0, 0, 0.07);
        legs = min(legs, min(spSdCapsule(lp, hip, knee, 0.013),
                             spSdCapsule(lp, knee, tip, 0.010)));
    }
    return min(body, legs);
}

static float3 calcSpiderNormal(float3 p, float2 tipLocal[8]) {
    float2 e = float2(0.0015, 0.0);
    return normalize(float3(
        sdSpiderLocal(p + float3(e.x,e.y,e.y), tipLocal) - sdSpiderLocal(p - float3(e.x,e.y,e.y), tipLocal),
        sdSpiderLocal(p + float3(e.y,e.x,e.y), tipLocal) - sdSpiderLocal(p - float3(e.y,e.x,e.y), tipLocal),
        sdSpiderLocal(p + float3(e.y,e.y,e.x), tipLocal) - sdSpiderLocal(p - float3(e.y,e.y,e.x), tipLocal)
    ));
}

// ── Scene fragment ─────────────────────────────────────────────────────────────

fragment float4 arachne_fragment(
    VertexOut                   in      [[stage_in]],
    constant FeatureVector&     f       [[buffer(0)]],
    constant float*             fft     [[buffer(1)]],
    constant float*             wave    [[buffer(2)]],
    constant StemFeatures&      stems   [[buffer(3)]],
    constant ArachneWebGPU*     webs    [[buffer(6)]],
    constant ArachneSpiderGPU&  spider  [[buffer(7)]]
) {
    float2 uv  = in.uv;
    float2 ndc = uv * 2.0 - 1.0;

    // D-019 warmup.
    float totalStemEnergy = stems.vocals_energy + stems.drums_energy
                          + stems.bass_energy   + stems.other_energy;
    float stemMix = smoothstep(0.02, 0.06, totalStemEnergy);

    // D-026 audio drivers.
    float bassRel    = mix(f.bass_att_rel, stems.bass_energy_rel, stemMix);
    float tautness   = mix(0.5, 1.0, saturate(0.5 + bassRel * 0.5));

    // Beat-phase vibration: plucks strands once per beat cycle.
    float vibAmp   = max(0.0, bassRel) * 0.007;
    float vibPhase = f.beat_phase01 * 2.0 * M_PI_F;

    // Strand thickness breathes with bass.
    float tubeRadius = 0.0055 + max(0.0, bassRel) * 0.003;

    // Slow hue drift over accumulated song energy.
    float hueDrift = fract(f.accumulated_audio_time * 0.025 + f.mid_att_rel * 0.08);

    // ── Camera ray ────────────────────────────────────────────────────────────
    float aspect  = max(f.aspect_ratio, 0.5);
    float3 camPos = float3(0, 0, kArachCamZ);
    float3 rayDir = normalize(float3(ndc.x * aspect * kArachFovTan,
                                     ndc.y * kArachFovTan, 1.0));

    // ── Ray march ─────────────────────────────────────────────────────────────
    int   hitType    = 0;   // 0=miss 1=strand 2=spider
    float hitT       = 8.0;
    float hitHue     = 0.52;
    float hitSat     = 0.88;
    float hitBrt     = 0.80;
    float hitOpacity = 1.0;

    // Track nearest web SDF for glow: rays that don't hard-intersect still
    // pick up bioluminescent halo from sub-pixel geometry (D-037 inv.4 at any res).
    float minWebDist = 8.0;
    float minWebHue  = 0.52;
    float minWebSat  = 0.88;
    float minWebBrt  = 0.78;

    float t = 0.05;
    for (int step = 0; step < 56 && t < 8.0; step++) {
        float3 pos = camPos + rayDir * t;
        float  dMin = 8.0;

        // ── Permanent anchor web at origin (D-037: visible even with zeroed pool).
        // seedTilt=0 → slight canonical tilt; stage=3 (stable), progress=1.
        float ancD = sdWebElement(pos, float3(0, 0, 0), 0.0, 0.38, 6.5,
                                  tubeRadius, vibAmp * 0.5, vibPhase,
                                  1984u, 3u, 1.0);
        if (ancD < dMin) dMin = ancD;
        if (ancD < minWebDist) {
            minWebDist = ancD;
            minWebHue = 0.52; minWebSat = 0.88; minWebBrt = 0.78 * tautness;
        }
        if (ancD < 0.002) {
            hitType = 1; hitT = t;
            hitHue = 0.52; hitSat = 0.88; hitBrt = 0.78 * tautness; hitOpacity = 0.65;
        }

        // ── Dynamic web pool ─────────────────────────────────────────────────
        for (int i = 0; i < kArachWebs; i++) {
            ArachneWebGPU w = webs[i];
            if (w.is_alive == 0u || w.opacity < 0.02) continue;

            // Map clip-space hub to world space; depth spreads webs in Z.
            float3 wCenter = float3(w.hub_x * 1.25, w.hub_y,
                                    mix(-0.45, 1.10, w.depth));
            float wd = sdWebElement(pos, wCenter, w.rot_angle, w.radius,
                                    w.spiral_revolutions, tubeRadius,
                                    vibAmp, vibPhase, w.rng_seed, w.stage, w.progress);
            if (wd < dMin) dMin = wd;
            if (wd < minWebDist) {
                minWebDist = wd;
                minWebHue  = w.birth_hue;
                minWebSat  = w.birth_sat * 0.90 + 0.08;
                minWebBrt  = w.birth_brt * tautness;
            }
            if (wd < 0.002) {
                hitType = 1; hitT = t;
                hitHue  = w.birth_hue;
                hitSat  = w.birth_sat * 0.90 + 0.08;
                hitBrt  = w.birth_brt * tautness;
                hitOpacity = w.opacity;
            }
        }

        // ── Spider SDF ───────────────────────────────────────────────────────
        if (spider.blend > 0.01) {
            float3 spWorld = float3(spider.posX * 1.25, spider.posY, 0.0);
            float3 dp      = pos - spWorld;
            float  ch = cos(-spider.heading), sh = sin(-spider.heading);
            float3 spLocal = float3(dp.x * ch - dp.y * sh,
                                    dp.x * sh + dp.y * ch, dp.z);
            float2 tipLocal[8];
            for (int k = 0; k < 8; k++) {
                float2 td  = (spider.tip[k] - float2(spider.posX, spider.posY)) * 1.25;
                tipLocal[k] = float2(td.x * ch - td.y * sh, td.x * sh + td.y * ch);
            }
            float spD = sdSpiderLocal(spLocal, tipLocal);
            if (spD < dMin) dMin = spD;
            if (spD < 0.002) { hitType = 2; hitT = t; }
        }

        if (dMin < 0.002) break;
        t += max(dMin * 0.75, 0.003);
    }

    // ── Background (valence/arousal-tinted dark sky) ──────────────────────────
    float  gv     = saturate(f.valence * 0.5 + 0.5);
    float  ga     = saturate(f.arousal * 0.5 + 0.5);
    float3 bgLow  = mix(float3(0.01, 0.01, 0.03), float3(0.02, 0.04, 0.01), ga);
    float3 bgHigh = mix(float3(0.01, 0.02, 0.06), float3(0.04, 0.02, 0.05), ga);
    float3 bgCol  = mix(bgLow, bgHigh, uv.y);
    bgCol         = mix(bgLow, bgCol, gv);

    // ── Shading ───────────────────────────────────────────────────────────────
    float3 color = bgCol;

    // Common audio factors shared by strand and glow shading.
    float bassBoost = 1.0 + max(0.0, bassRel) * 0.55;
    float anticipate = smoothstep(0.75, 1.0, f.beat_phase01) * 0.20;

    if (hitType == 1) {
        // Bioluminescent strand: self-emissive, no external light.
        // Hue drift blended at 15% — colour shifts slowly, identity held.
        float  finalHue = fract(hitHue + hueDrift * 0.15);
        float3 strandCol  = hsv2rgb(float3(finalHue, hitSat,
                                           saturate(hitBrt * bassBoost + anticipate)));
        color = mix(bgCol, strandCol, saturate(hitOpacity));
    } else if (hitType == 0) {
        // Miss: soft bioluminescent glow from nearest strand.
        // exp2 falloff ensures form complexity even for sub-pixel geometry (D-037 inv.4).
        float  glowHue = fract(minWebHue + hueDrift * 0.15);
        float  glowAmt = exp2(-max(minWebDist, 0.0) * 14.0);
        float3 glowCol = hsv2rgb(float3(glowHue, minWebSat,
                                        saturate(minWebBrt * bassBoost + anticipate)));
        color = bgCol + glowCol * glowAmt;

    } else if (hitType == 2 && spider.blend > 0.01) {
        // Spider: PBR chitin (Increment 3.5.9 shading, re-used verbatim).
        float3 spWorld = float3(spider.posX * 1.25, spider.posY, 0.0);
        float3 hitPos  = camPos + rayDir * hitT;
        float3 dp      = hitPos - spWorld;
        float  ch = cos(-spider.heading), sh = sin(-spider.heading);
        float3 spLocal = float3(dp.x * ch - dp.y * sh, dp.x * sh + dp.y * ch, dp.z);
        float2 tipLocal[8];
        for (int k = 0; k < 8; k++) {
            float2 td  = (spider.tip[k] - float2(spider.posX, spider.posY)) * 1.25;
            tipLocal[k] = float2(td.x * ch - td.y * sh, td.x * sh + td.y * ch);
        }
        float3 nrm      = calcSpiderNormal(spLocal, tipLocal);
        float3 lightDir = normalize(float3(0.25, 0.35, -1.0));
        float3 viewDir  = -rayDir;
        float3 halfVec  = normalize(lightDir + viewDir);
        float  nDotL    = max(dot(nrm, lightDir), 0.0);
        float  spec     = pow(max(dot(nrm, halfVec), 0.0), 96.0);
        float  fresnel  = pow(1.0 - max(dot(nrm, viewDir), 0.0), 3.0);
        float  iridHue  = fract(nrm.x * 0.45 + nrm.y * 0.30 + 0.42);
        float3 iridCol  = hsv2rgb(float3(iridHue, 0.88, 1.0));
        float3 chitin   = float3(0.018, 0.020, 0.022);
        color = chitin   * (0.15 + nDotL * 0.55)
              + iridCol  * spec * 2.2
              + iridCol  * fresnel * 0.35
              + bgCol    * fresnel * 0.4;
        color *= spider.blend;
        color += bgCol * (1.0 - spider.blend);
    }

    // D-037 invariant 2: clamp before sRGB encoding.
    color = min(color, float3(0.95));
    return float4(color, 1.0);
}

// ── MV-Warp functions ─────────────────────────────────────────────────────────
// decay 0.92 keeps trails short enough to preserve 3D perspective depth.
// Bass-driven zoom breath + mid-driven slow rotation animate the web field.

MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    pf.cx  = 0.0; pf.cy = 0.0;
    pf.dx  = 0.0; pf.dy = 0.0;
    pf.sx  = 1.0; pf.sy = 1.0;
    pf.warp = 0.0;

    pf.zoom  = 1.0 + f.bass_att_rel * 0.008 + f.mid_att_rel * 0.004;
    pf.rot   = f.mid_att_rel * 0.0025;
    pf.decay = 0.92;

    pf.q1 = f.bass_att_rel;
    pf.q2 = f.mid_att_rel;
    pf.q3 = 0.0; pf.q4 = 0.0;
    pf.q5 = 0.0; pf.q6 = 0.0; pf.q7 = 0.0; pf.q8 = 0.0;
    return pf;
}

float2 mvWarpPerVertex(
    float2 uv, float rad, float ang,
    thread const MVWarpPerFrame& pf,
    constant FeatureVector& f,
    constant StemFeatures& stems
) {
    float2 centre = float2(0.5, 0.5);
    float2 p      = uv - centre;

    float  zoomAmt   = 1.0 / max(pf.zoom, 0.001);
    float2 zoomed    = p * zoomAmt + centre;
    float  wobble    = (pf.q1 * 0.010 + pf.q2 * 0.006) * rad;
    return zoomed + p * wobble;
}
