// Arachne.metal — 2D SDF bioluminescent spider-web field (Increment V.7 Session 1).
//
// Architecture: 2D direct fragment — per D-043. No ray march.
// Renders up to 12 pool webs from ArachneWebGPU buffer in UV space.
//
// V.7 Session 1 changes (geometry + meso fidelity):
//   §4.1  Per-web macro variation: hub jitter ±5% UV, elliptical aspect 0.85–1.15,
//         in-plane tilt rotation, spoke count 11–17 — all from rng_seed.
//   §4.2  Meso: per-spoke gravity sag (parabolic, +v direction); spiral micro-wobble
//         via time-invariant fbm4 (spec: 0.003 × fbm4(arcParam×6, seedF, 0)).
//   §4.3  Micro: adhesive droplets on spiral threads only, hash-lattice at 8–12 px
//         spacing, rendered bright white (mat_id 2 reserved for Session 2 silk BRDF).
//   §4.4  Smooth-union accumulation across all web slots using op_blend on
//         pseudo-SDF (1 - coverage), k=0.012 — replaces additive hard max.
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
// Spoke count is now per-web via rng_seed (11–17); kArachSpokes removed in V.7.

constant int kArachWebs = 12;

// ── Web coverage result ───────────────────────────────────────────────────────
// Two lanes allow Session 2 to apply different BRDF recipes to each.

struct ArachneWebResult {
    float strandCov;   // spokes + spiral halo + hub; uses web birthHue/birthSat
    float dropCov;     // adhesive droplets on spiral only; bright-white this session
};

// ── Helpers ───────────────────────────────────────────────────────────────────

static float arachHash(uint seed) {
    seed = (seed ^ 61u) ^ (seed >> 16u);
    seed *= 9u;
    seed ^= (seed >> 4u);
    seed *= 0x27d4eb2du;
    seed ^= (seed >> 15u);
    return float(seed) * (1.0 / 4294967296.0);
}

/// Nearest distance from p to line segment a→b (used by spider legs only).
static float arachSegDist(float2 p, float2 a, float2 b) {
    float2 ab = b - a, ap = p - a;
    float  t  = saturate(dot(ap, ab) / max(dot(ab, ab), 1e-8));
    return length(ap - ab * t);
}

// ── Per-web seed-derived variation ─────────────────────────────────────────────
// All functions are pure/deterministic from rng_seed so shader and Swift diagnostics
// produce identical values (Swift mirrors in ArachneState diagHash/diagSpokeCount/...).

static int    arachSpokeCount(uint seed)  { return 11 + int(arachHash(seed + 0xA1u) * 6.99); }
static float  arachAspect(uint seed)      { return 0.85 + arachHash(seed + 0xB2u) * 0.30; }
static float  arachAspectAngle(uint seed) { return arachHash(seed + 0xC3u) * 2.0 * M_PI_F; }
static float  arachKSag(uint seed)        { return 0.04 + arachHash(seed + 0xD4u) * 0.06; }

// ±5% UV hub jitter applied at the fragment call site (keeps WebGPU layout stable).
static float2 arachHubJitter(uint seed) {
    return float2((arachHash(seed + 0xE5u) - 0.5) * 0.10,
                  (arachHash(seed + 0xF6u) - 0.5) * 0.10);
}

// ── Per-web 2D evaluation ─────────────────────────────────────────────────────
//
// Returns ArachneWebResult{strandCov, dropCov} for a single web at pixel uv.
// All distances in UV space. Call for both pool webs and the anchor web.
//
// New V.7 parameters vs V.3.5.12:
//   spokeCount   — per-seed integer [11, 17] replacing constant kArachSpokes.
//   aspectX      — elliptical squash [0.85, 1.15] along aspectAngle axis.
//   aspectAngle  — in-plane tilt of ellipse axis [0, 2π].
//   kSag         — gravity-sag coefficient [0.04, 0.10]; sag = kSag × length².

static ArachneWebResult arachneEvalWeb(
    float2 uv,
    float2 hubUV,
    float  webR,
    float  rotAngle,
    float  spirRevs,
    uint   seed,
    uint   stage,
    float  progress,
    float  vibAmp,
    float  vibPhase,
    int    spokeCount,
    float  aspectX,
    float  aspectAngle,
    float  kSag
) {
    ArachneWebResult result;
    result.strandCov = 0.0;
    result.dropCov   = 0.0;

    // ── §4.1 Elliptical squash: 2D tilt in UV plane (NOT 3D tilt — D-043) ────
    // Transforms pRel into a squashed frame; rest of evaluation uses squashed coords.
    float2 pRel0  = uv - hubUV;
    float2 sqDir  = float2(cos(aspectAngle), sin(aspectAngle));
    float2 sqPerp = float2(-sqDir.y, sqDir.x);
    float2 pLocal = float2(dot(pRel0, sqDir), dot(pRel0, sqPerp));
    pLocal *= float2(aspectX, 1.0 / aspectX);
    float2 pRel = pLocal.x * sqDir + pLocal.y * sqPerp;

    float r = length(pRel);
    if (r > webR * 1.20) return result;

    // Vibration offset (beat-phase-locked, from outer scope vibAmp/vibPhase)
    float vibEnv = sin(saturate(r / webR) * M_PI_F);
    float2 tang  = r > 0.001 ? float2(-pRel.y, pRel.x) / r : float2(0.0, 1.0);
    float2 tRel  = pRel + tang * (vibEnv * sin(vibPhase) * vibAmp);
    float  rT    = length(tRel);
    float  taper = saturate(rT / webR);
    float  aaW   = 0.0006;
    float  hubR  = webR * 0.10;

    // Hub concentric rings (unchanged from V.3.5.12)
    float hubCov = 0.0;
    if (rT < hubR) {
        float hCoord  = rT / hubR * 3.0;
        float hf      = fract(hCoord);
        float hubDist = min(hf, 1.0 - hf) * hubR / 3.0;
        hubCov = smoothstep(0.0010 + aaW, 0.0010 - aaW, hubDist) * 0.65;
    }

    // ── §4.1 Variable spoke count + §4.2 Gravity sag ─────────────────────────
    float baseStep = 2.0 * M_PI_F / float(spokeCount);
    int   nVisible = (stage == 0u) ? 0
                   : (stage == 1u) ? clamp(int(progress * float(spokeCount)) + 1,
                                           1, spokeCount)
                   : spokeCount;

    // Gravity sag: parabolic, +v direction (downward in UV), per-web kSag.
    // sagAmount = kSag × spokeLen²; max sag at midpoint = sagAmount.
    float spokeLen  = webR - hubR;
    float sagAmount = kSag * spokeLen * spokeLen;

    float minSpokeDist = 1e6;
    if (rT > hubR && rT < webR * 1.18) {
        for (int ri = 0; ri < nVisible; ri++) {
            // Alternating-pair reveal: even ri → front-half spokes, odd → back-half.
            // Maximises angular coverage at each reveal step for any spoke count.
            int halfN = spokeCount / 2;
            int revI  = (ri % 2 == 0) ? (ri / 2) : (ri / 2 + halfN);
            int i = revI % spokeCount;

            // ±22% angular jitter per (seed, spoke_index) — deterministic (D-041)
            float jitter = (arachHash(seed + uint(i) * 7u) - 0.5) * baseStep * 0.44;
            float spAng  = rotAngle + float(i) * baseStep + jitter;
            float2 d     = float2(cos(spAng), sin(spAng));

            // Segment distance with parabolic gravity sag (+v = downward).
            // Projects tRel onto spoke direction to get parameter tProj ∈ [0,1],
            // then finds the sagged spoke point and measures Euclidean distance.
            float tProj  = saturate(dot(tRel, d) / max(webR, 1e-5));
            float sagDisp = sagAmount * 4.0 * tProj * (1.0 - tProj);
            float2 spokePt = tProj * webR * d + float2(0.0, sagDisp);
            float  spDist  = length(tRel - spokePt);
            minSpokeDist = min(minSpokeDist, spDist);
        }
    }

    float anchorFade   = rT > webR ? exp(-(rT - webR) * 8.0) : 1.0;
    float spokeW       = mix(0.0024, 0.0014, taper);
    float spokeHaloSig = max(webR * 0.014, 1e-4);
    float spokeCov     = smoothstep(spokeW + aaW, spokeW - aaW, minSpokeDist) * anchorFade;
    float spokeHalo    = exp(-minSpokeDist * minSpokeDist / (spokeHaloSig * spokeHaloSig))
                        * 0.38 * anchorFade;

    // ── §4.2 Archimedean spiral + micro-wobble + §4.3 adhesive droplets ───────
    float spirCov  = 0.0;
    float spirHalo = 0.0;
    float dropCovLocal = 0.0;
    float progressR = (stage >= 3u) ? webR
                    : (stage == 2u) ? progress * webR
                    : 0.0;

    if (rT >= hubR && rT <= progressR + spokeW * 2.0) {
        float theta  = atan2(tRel.y, tRel.x);
        float sCoord = theta - (rT / webR) * spirRevs * 2.0 * M_PI_F;

        // §4.2 Time-invariant micro-wobble: 0.003 × fbm4(arcParam×6×spirRevs, seedF, 0)
        // No `time` term — webs do not sway (per spec; motion added in future session if any).
        float arcParam  = rT / max(webR, 1e-5);
        float seedF     = float(seed) * 2.3283064e-10;  // seed / 2^32 → [0,1)
        float wobbleAng = (0.003 / max(rT, 0.001))
                        * fbm4(float3(arcParam * 6.0 * spirRevs, seedF * 113.7, 0.0));
        sCoord += wobbleAng;

        float sf      = fract(sCoord / (2.0 * M_PI_F));
        float spirDist = min(sf, 1.0 - sf) * webR / max(spirRevs, 0.1);
        float inZone   = (rT >= hubR && rT <= progressR) ? 1.0 : 0.0;
        float spirW    = 0.0013;
        float spirSig  = max(webR * 0.009, 1e-4);
        spirCov  = smoothstep(spirW + aaW, spirW - aaW, spirDist) * inZone;
        spirHalo = exp(-spirDist * spirDist / (spirSig * spirSig)) * 0.25 * inZone;

        // §4.3 Adhesive droplets on spiral threads only (radial spokes are glue-free
        // per silk biology). Gated on spirDist < dropRadius + small margin so the
        // inner loop only runs for pixels very close to the spiral strand.
        float dropRadius = 0.0035;   // ≈ 3.8 px at 1080p
        if (inZone > 0.0 && spirDist < dropRadius + 0.0005) {
            // Per-web spacing derived from seed: 8–12 px at 1080p = 0.0074–0.0111 UV.
            float spacingUV  = 0.0074 + arachHash(seed + 0x1337u) * 0.0037;
            float dropsPerRev = max(3.0, 2.0 * M_PI_F * rT / spacingUV);
            float dTheta     = 2.0 * M_PI_F / dropsPerRev;

            // Nearest drop index along current winding
            float thetaN  = fract(theta / (2.0 * M_PI_F));
            int   dropBase = int(thetaN * dropsPerRev);

            // Enumerate ±2 drops around current angular position
            for (int di = dropBase - 2; di <= dropBase + 2; di++) {
                float dropAngle = float(di) * dTheta;
                // Hash-lattice jitter: ±25% of spacing along tangent (organic spacing)
                uint  dKey  = seed * 1024u + uint((di + 4096) & 0xFFFF);
                dropAngle  += (arachHash(dKey) - 0.5) * 0.5 * dTheta;
                float2 dropPos = float2(cos(dropAngle), sin(dropAngle)) * rT;
                float  dist    = length(tRel - dropPos);
                if (dist < dropRadius + 0.0005) {
                    dropCovLocal = max(dropCovLocal,
                        smoothstep(dropRadius + 0.0003, dropRadius - 0.0003, dist));
                }
            }
        }
    }

    result.strandCov = max(max(spokeCov, spirCov), max(max(spokeHalo, spirHalo), hubCov));
    result.dropCov   = dropCovLocal;
    return result;
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

    // ── §4.4 Smooth-union coverage accumulation ───────────────────────────────
    // pseudo-SDF: d = 1 − coverage.  op_blend(d1, d2, k) = smooth-min → smooth-max
    // of coverage values with blend radius k = 0.012 UV (softens web-on-web seams).
    // Spider overlay is NOT included in the union (D-040).
    float strandPseudo = 1.0;   // current combined strand pseudo-SDF
    float dropPseudo   = 1.0;   // current combined droplet pseudo-SDF
    float3 strandColor = float3(0.0);
    float  prevStrandCov = 0.0; // running smooth-max coverage

    // ── Permanent anchor web (D-037: always visible; seed=1984u, hub upper-centre)
    {
        uint   ancSeed = 1984u;
        float2 ancHub  = float2(0.42, 0.40) + arachHubJitter(ancSeed);
        ArachneWebResult wr = arachneEvalWeb(
            uv, ancHub, 0.22, 0.30, 6.0, ancSeed,
            3u, 1.0, vibAmp * 0.7, vibPhase,
            arachSpokeCount(ancSeed), arachAspect(ancSeed),
            arachAspectAngle(ancSeed), arachKSag(ancSeed)
        );

        float newStrandD   = op_blend(strandPseudo, 1.0 - wr.strandCov, 0.012);
        float newStrandCov = 1.0 - newStrandD;
        float delta        = max(0.0, newStrandCov - prevStrandCov);
        float brt          = saturate(brightness * bassBoost + beatFlash);
        float3 col         = hsv2rgb(float3(fract(0.52 + hueDrift * 0.10), 0.88, brt));
        strandColor   += col * delta;
        strandPseudo   = newStrandD;
        prevStrandCov  = newStrandCov;

        dropPseudo = op_blend(dropPseudo, 1.0 - wr.dropCov, 0.012);
    }

    // ── Pool webs ─────────────────────────────────────────────────────────────
    for (int wi = 0; wi < kArachWebs; wi++) {
        ArachneWebGPU w = webs[wi];
        if (w.is_alive == 0u || w.opacity < 0.015) continue;

        float2 hubUV = float2((w.hub_x + 1.0) * 0.5, (1.0 - w.hub_y) * 0.5)
                     + arachHubJitter(w.rng_seed);
        float  webR  = w.radius * 0.5;

        ArachneWebResult wr = arachneEvalWeb(
            uv, hubUV, webR, w.rot_angle, w.spiral_revolutions,
            w.rng_seed, w.stage, w.progress, vibAmp, vibPhase,
            arachSpokeCount(w.rng_seed), arachAspect(w.rng_seed),
            arachAspectAngle(w.rng_seed), arachKSag(w.rng_seed)
        );

        float scaledStrand = wr.strandCov * w.opacity;
        float scaledDrop   = wr.dropCov   * w.opacity;
        if (scaledStrand < 0.003 && scaledDrop < 0.003) continue;

        float newStrandD   = op_blend(strandPseudo, 1.0 - scaledStrand, 0.012);
        float newStrandCov = 1.0 - newStrandD;
        float delta        = max(0.0, newStrandCov - prevStrandCov);

        float finalHue = fract(w.birth_hue + hueDrift * 0.12);
        float brt      = saturate(brightness * bassBoost + beatFlash);
        float3 wCol    = hsv2rgb(float3(finalHue, w.birth_sat * 0.90 + 0.06, brt));
        strandColor   += wCol * delta;
        strandPseudo   = newStrandD;
        prevStrandCov  = newStrandCov;

        dropPseudo = op_blend(dropPseudo, 1.0 - scaledDrop, 0.012);
    }

    // Droplets: bright blue-white per §4.3 (mat_id 2 reserved for Session 2 BRDF)
    float3 dropColor  = float3(0.95, 0.97, 1.0) * (1.0 - dropPseudo);
    float3 accumColor = strandColor + dropColor;

    // ── Spider (2D — clip-space → UV, Y-flipped; D-040 overlay; not in smooth-union)
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
        float  rimD    = 1.0 - smoothstep(0.013, 0.019, length(spRel));
        float  rimHue  = fract(atan2(spRel.y, spRel.x) / (2.0 * M_PI_F) + 0.40 + hueDrift);
        float3 rimCol  = hsv2rgb(float3(rimHue, 0.88, 1.0)) * rimD * bodyCov * 1.5;

        // 8 legs
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
