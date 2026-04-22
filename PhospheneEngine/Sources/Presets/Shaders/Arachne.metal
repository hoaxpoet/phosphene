// Arachne.metal — 2D SDF bioluminescent spider-web field (Increment 3.5.12).
//
// Architecture: 2D direct fragment — same approach as Gossamer. No ray march.
// Renders up to 12 pool webs from ArachneWebGPU buffer in UV space.
// Per-web: 12 radial spokes (seed-jittered ±30%) + Archimedean spiral + hub rings.
// Spider easter egg: 2D body + 8 leg segments from ArachneSpiderGPU clip-space coords.
//
// Clip-space → UV: hub_uv = float2((hub_x+1)/2, (1-hub_y)/2).  webR = radius × 0.5.
//
// Buffer bindings:
//   buffer(0) = FeatureVector      (192 bytes)
//   buffer(3) = StemFeatures       (256 bytes)
//   buffer(6) = ArachneWebGPU[12]  (768 bytes — ArachneState.webBuffer)
//   buffer(7) = ArachneSpiderGPU   (80 bytes  — ArachneState.spiderBuffer)
//
// D-026 deviation-first, D-019 warmup, D-037: two seed webs guarantee visibility.

// ── GPU structs (byte-match Swift counterparts) ──────────────────────────────

struct ArachneWebGPU {
    float hub_x, hub_y, radius, depth;
    float rot_angle; uint anchor_count; float spiral_revolutions; uint rng_seed;
    float birth_beat_phase; uint stage; float progress, opacity;
    float birth_hue, birth_sat, birth_brt; uint is_alive;
};

struct ArachneSpiderGPU {
    float blend, posX, posY, heading;
    float2 tip[8];
};

// ── Constants ─────────────────────────────────────────────────────────────────

constant int kArachWebs   = 12;
constant int kArachSpokes = 12;

// ── Helpers ───────────────────────────────────────────────────────────────────

static float arachHash(uint seed) {
    seed = (seed ^ 61u) ^ (seed >> 16u);
    seed *= 9u;
    seed ^= (seed >> 4u);
    seed *= 0x27d4eb2du;
    seed ^= (seed >> 15u);
    return float(seed) * (1.0 / 4294967296.0);
}

/// Nearest distance from p to line segment a→b.
static float arachSegDist(float2 p, float2 a, float2 b) {
    float2 ab = b - a, ap = p - a;
    float  t  = saturate(dot(ap, ab) / max(dot(ab, ab), 1e-8));
    return length(ap - ab * t);
}

// ── Per-web 2D evaluation ─────────────────────────────────────────────────────
//
// Returns the strand coverage [0,1] for a single web at pixel uv.
// All distances in UV space. Call for both pool webs and the anchor web.

static float arachneEvalWeb(
    float2 uv,
    float2 hubUV,
    float  webR,       // outer radius in UV
    float  rotAngle,
    float  spirRevs,
    uint   seed,
    uint   stage,
    float  progress,
    float  vibAmp,
    float  vibPhase
) {
    float hubR = webR * 0.10;
    float2 pRel = uv - hubUV;
    float  r    = length(pRel);
    if (r > webR * 1.20) return 0.0;

    float vibEnv = sin(saturate(r / webR) * M_PI_F);
    float2 tang  = r > 0.001 ? float2(-pRel.y, pRel.x) / r : float2(0.0, 1.0);
    float2 tRel  = pRel + tang * (vibEnv * sin(vibPhase) * vibAmp);
    float  rT    = length(tRel);
    float  taper = saturate(rT / webR);
    float  aaW   = 0.0006;

    // Hub concentric rings
    float hubCov = 0.0;
    if (rT < hubR) {
        float hCoord  = rT / hubR * 3.0;
        float hf      = fract(hCoord);
        float hubDist = min(hf, 1.0 - hf) * hubR / 3.0;
        hubCov = smoothstep(0.0010 + aaW, 0.0010 - aaW, hubDist) * 0.65;
    }

    // Radial spokes (alternating-pair reveal during stage 1)
    float baseStep = 2.0 * M_PI_F / float(kArachSpokes);
    int   revOrder[12] = {0, 6, 3, 9, 1, 7, 4, 10, 2, 8, 5, 11};
    int   nVisible = (stage == 0u) ? 0
                   : (stage == 1u) ? clamp(int(progress * float(kArachSpokes)) + 1,
                                           1, kArachSpokes)
                   : kArachSpokes;

    float minSpokeDist = 1e6;
    if (rT > hubR && rT < webR * 1.18) {
        for (int ri = 0; ri < nVisible; ri++) {
            int   i      = revOrder[ri];
            float jitter = (arachHash(seed + uint(i) * 7u) - 0.5) * baseStep * 0.60;
            float spAng  = rotAngle + float(i) * baseStep + jitter;
            float2 d     = float2(cos(spAng), sin(spAng));
            minSpokeDist = min(minSpokeDist, abs(tRel.x * d.y - tRel.y * d.x));
        }
    }

    float anchorFade   = rT > webR ? exp(-(rT - webR) * 8.0) : 1.0;
    float spokeW       = mix(0.0024, 0.0014, taper);
    float spokeHaloSig = max(webR * 0.014, 1e-4);
    float spokeCov     = smoothstep(spokeW + aaW, spokeW - aaW, minSpokeDist) * anchorFade;
    float spokeHalo    = exp(-minSpokeDist * minSpokeDist / (spokeHaloSig * spokeHaloSig))
                        * 0.38 * anchorFade;

    // Archimedean capture spiral
    float spirCov  = 0.0;
    float spirHalo = 0.0;
    float progressR = (stage >= 3u) ? webR
                    : (stage == 2u) ? progress * webR
                    : 0.0;

    if (rT >= hubR && rT <= progressR + spokeW * 2.0) {
        float theta    = atan2(tRel.y, tRel.x);
        float sCoord   = theta - (rT / webR) * spirRevs * 2.0 * M_PI_F;
        float sf       = fract(sCoord / (2.0 * M_PI_F));
        float spirDist = min(sf, 1.0 - sf) * webR / max(spirRevs, 0.1);
        float inZone   = (rT >= hubR && rT <= progressR) ? 1.0 : 0.0;
        float spirW    = 0.0013;
        float spirSig  = max(webR * 0.009, 1e-4);
        spirCov  = smoothstep(spirW + aaW, spirW - aaW, spirDist) * inZone;
        spirHalo = exp(-spirDist * spirDist / (spirSig * spirSig)) * 0.25 * inZone;
    }

    return max(max(spokeCov, spirCov), max(max(spokeHalo, spirHalo), hubCov));
}

// ── Fragment ──────────────────────────────────────────────────────────────────

fragment float4 arachne_fragment(
    VertexOut                   in      [[stage_in]],
    constant FeatureVector&     f       [[buffer(0)]],
    constant float*             fft     [[buffer(1)]],
    constant float*             wave    [[buffer(2)]],
    constant StemFeatures&      stems   [[buffer(3)]],
    constant ArachneWebGPU*     webs    [[buffer(6)]],
    constant ArachneSpiderGPU&  spider  [[buffer(7)]]
) {
    float2 uv = in.uv;

    // D-019 warmup
    float totalStemEnergy = stems.vocals_energy + stems.drums_energy
                          + stems.bass_energy   + stems.other_energy;
    float stemMix = smoothstep(0.02, 0.06, totalStemEnergy);

    // D-026 audio drivers
    float bassRel   = mix(f.bass_att_rel, stems.bass_energy_rel, stemMix);
    float beatPulse = max(f.beat_bass, max(f.beat_mid, f.beat_composite));
    float beatFlash = beatPulse * 0.28;
    float vibAmp    = max(0.0, bassRel) * 0.009;
    float vibPhase  = f.beat_phase01 * 2.0 * M_PI_F;
    float bassBoost = 1.0 + max(0.0, bassRel) * 0.50;
    float hueDrift  = fract(f.accumulated_audio_time * 0.025 + f.mid_att_rel * 0.08);

    // D-037 inv.3: silence (f.bass=0) → 0.12, steady (f.bass=0.5) → 0.50, distinct.
    float brightness = 0.12 + f.bass * 0.76 + bassRel * 0.12;

    // Accumulate all web contributions additively
    float3 accumColor = float3(0.0);

    // ── Permanent anchor web (D-037: always present; seed=1984u, hub upper-centre)
    {
        float  cov  = arachneEvalWeb(uv, float2(0.42, 0.40), 0.22, 0.30,
                                     6.0, 1984u, 3u, 1.0, vibAmp * 0.7, vibPhase);
        float  brt  = saturate(brightness * bassBoost + beatFlash);
        float3 col  = hsv2rgb(float3(fract(0.52 + hueDrift * 0.10), 0.88, brt));
        accumColor += cov * col;
    }

    // ── Pool webs ─────────────────────────────────────────────────────────────
    for (int wi = 0; wi < kArachWebs; wi++) {
        ArachneWebGPU w = webs[wi];
        if (w.is_alive == 0u || w.opacity < 0.015) continue;

        float2 hubUV = float2((w.hub_x + 1.0) * 0.5, (1.0 - w.hub_y) * 0.5);
        float  webR  = w.radius * 0.5;   // clip-space radius → UV radius

        float cov = arachneEvalWeb(uv, hubUV, webR, w.rot_angle, w.spiral_revolutions,
                                   w.rng_seed, w.stage, w.progress, vibAmp, vibPhase);
        if (cov < 0.005) continue;

        float finalHue = fract(w.birth_hue + hueDrift * 0.12);
        float brt      = saturate(brightness * bassBoost + beatFlash);
        float3 wCol    = hsv2rgb(float3(finalHue, w.birth_sat * 0.90 + 0.06, brt));
        accumColor    += cov * wCol * w.opacity;
    }

    // ── Spider (2D — clip-space → UV, Y-flipped) ──────────────────────────────
    if (spider.blend > 0.01) {
        float2 spUV  = float2((spider.posX + 1.0) * 0.5, (1.0 - spider.posY) * 0.5);
        float2 spRel = uv - spUV;

        // Abdomen + head
        float2 headOff = float2(cos(spider.heading), -sin(spider.heading)) * 0.016;
        float  bodyD   = length(spRel) - 0.018;
        float  headD   = length(spRel - headOff) - 0.011;
        float  bodyCov = max(smoothstep(0.003, -0.001, bodyD),
                             smoothstep(0.002, -0.001, headD));

        // Iridescent chitin rim: hue varies with angle around body
        float  rimD    = 1.0 - smoothstep(0.013, 0.019, length(spRel));  // outer shell
        float  rimHue  = fract(atan2(spRel.y, spRel.x) / (2.0 * M_PI_F) + 0.40 + hueDrift);
        float3 rimCol  = hsv2rgb(float3(rimHue, 0.88, 1.0)) * rimD * bodyCov * 1.5;

        // 8 legs: thin segments from body centre to each tip
        float legMinDist = 1e6;
        for (int k = 0; k < 8; k++) {
            float2 tipUV = float2((spider.tip[k].x + 1.0) * 0.5,
                                  (1.0 - spider.tip[k].y) * 0.5);
            legMinDist   = min(legMinDist, arachSegDist(uv, spUV, tipUV));
        }
        float legCov = smoothstep(0.0045, 0.001, legMinDist);

        float3 chitin    = float3(0.018, 0.020, 0.025);
        float3 spiderCol = chitin * bodyCov + rimCol
                         + float3(0.025, 0.090, 0.110) * legCov;
        float  spiderMask = max(bodyCov, legCov * 0.65);
        accumColor = mix(accumColor, spiderCol, spider.blend * spiderMask);
    }

    // ── Background (valence/arousal-tinted near-black) ─────────────────────────
    float  gv    = saturate(f.valence * 0.5 + 0.5);
    float  ga    = saturate(f.arousal * 0.5 + 0.5);
    float3 bgLow  = mix(float3(0.004, 0.004, 0.018), float3(0.008, 0.014, 0.006), ga);
    float3 bgHigh = mix(float3(0.005, 0.009, 0.040), float3(0.015, 0.009, 0.024), ga);
    float3 bgCol  = mix(bgLow, bgHigh, uv.y * gv);

    float3 color = accumColor + bgCol;
    color = min(color, float3(0.95));
    return float4(color, 1.0);
}

// ── MV-Warp functions ─────────────────────────────────────────────────────────
// decay 0.92: short echo smears thread halos into bioluminescent trails.

MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    pf.cx = 0.0; pf.cy = 0.0;
    pf.dx = 0.0; pf.dy = 0.0;
    pf.sx = 1.0; pf.sy = 1.0;
    pf.warp = 0.0;

    pf.zoom  = 1.0 + f.bass_att_rel * 0.007 + f.mid_att_rel * 0.004;
    pf.rot   = f.mid_att_rel * 0.002;
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
    float  zoomAmt = 1.0 / max(pf.zoom, 0.001);
    float2 zoomed  = p * zoomAmt + centre;
    float  wobble  = (pf.q1 * 0.010 + pf.q2 * 0.006) * rad;
    return zoomed + p * wobble;
}
