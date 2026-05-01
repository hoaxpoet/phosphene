// Arachne.metal — 2D SDF bioluminescent spider-web field (Increment V.7 Session 3).
//
// V.7 Session 3 changes (audio routing audit — D-020/D-026 compliance):
//   §3.1  Audit table — two D-020 violations found and removed; one D-026 violation
//         found and rewritten.
//   §3.2  Strand vibration (vibAmp/vibPhase) removed: web geometry is static (D-020).
//         tRel now equals pRel directly; mv_warp temporal echo (decay=0.92) is the
//         "alive" mechanism per CLAUDE.md Architecture note.
//   §3.3  brightness = 0.12 + f.bass × 0.76 + ... rewritten to deviation form (D-026).
//         New scheme: static tint (silkTint × 0.50) + post-BRDF deviation gain:
//           baseEmissionGain = 1.0 + 0.18 × f.bass_att_rel   (continuous, ±≈0.09)
//           beatAccent       = 0.07 × max(0, drums_energy_dev) (accent, ≤ 0.07)
//         Continuous/beat ratio = 0.18/0.07 ≈ 2.57× — satisfies ≥2× rule (CLAUDE.md).
//         At average energy (bass_att_rel=0): gain=1.0, tint=0.50 — same brightness as
//         prior Sessions at average levels. Silence: gain≈0.82, non-black guaranteed.
//   §3.4  Dust-mote threshold modulated by f.mid_att_rel (slow mid-band breathing):
//           moteThresh = 0.66 − 0.04 × max(0, f.mid_att_rel)  [~1–3% density range]
//
// Architecture: 2D direct fragment — per D-043. No ray march.
// Renders up to `kArachWebs` pool webs (V.7.5 §10.1.1: 4) from ArachneWebGPU buffer in UV space.
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
// V.7 Session 2 changes (materials + atmosphere — this file):
//   ArachneWebResult extended with strandTangent, dropVec, dropRadius for BRDF.
//   mat_silk_thread: Marschner-lite fiber BRDF on every strand (V=T 2D adaptation;
//     R lobe fires for strands aligned with key light, TT fires for anti-parallel).
//     azimuthal_r widened to 0.35 for visible 2D highlight (default 0.18 is for 3D).
//   mat_frosted_glass: dielectric droplet with analytic spherical-cap detail_normal,
//     SSS reduced to 0.04, single sharp glint via pow(NdotR, 64).
//   mat_chitin: spider carapace updated to cookbook call (M3 compliance, D-040).
//   sss_backlit: bioluminescent rim glow on all strands (E4 — fiber SSS).
//   §5.1  2D screen-space mist via fbm8 multiplicative field. No apply_fog (D-029).
//   §5.2  Screen-space dust motes via fbm4, drift via accumulated_audio_time (FA33).
//   §5.3  Warm TT-lobe back-rim cue (V.7.5 §10.1.4 — was cool-blue): backsideCue
//         from R-lobe accumulation, tinted amber per ref 04 annotation.
//   Cascade markers added: // macro, // meso, // micro, // specular (M1 gate).
//
// Clip-space → UV: hub_uv = float2((hub_x+1)/2, (1-hub_y)/2).  webR = radius × 0.5.
//
// Buffer bindings:
//   buffer(0) = FeatureVector      (192 bytes)
//   buffer(3) = StemFeatures       (256 bytes)
//   buffer(6) = ArachneWebGPU[kArachWebs]  (256 bytes at kArachWebs=4 — ArachneState.webBuffer)
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

constant int kArachWebs = 4;  // V.7.5 §10.1.1: pool capped 12→4 (single hero composition)

// ── Web coverage result ───────────────────────────────────────────────────────
// Extended in V.7 Session 2 with per-pixel strand tangent and droplet normal data
// for BRDF evaluation in the fragment.
//
// Two lanes allow different BRDF recipes per strand type (silk) and drop (frosted glass).

struct ArachneWebResult {
    float strandCov;      // spokes + spiral halo + hub coverage [0,1]
    float dropCov;        // adhesive droplets on spiral only [0,1]
    float2 strandTangent; // tangent of the dominant (closest) strand in UV plane
    float2 dropVec;       // vector from closest drop center to pixel (tRel space ≈ UV)
    float dropRadius;     // radius of the closest droplet
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
// V.7.5 §10.1.2: range widened [0.04, 0.10] → [0.06, 0.14] so longer radials
// visibly droop. Gravity-direction weighting applied per-spoke at the call site.
static float  arachKSag(uint seed)        { return 0.06 + arachHash(seed + 0xD4u) * 0.08; }

// ±5% UV hub jitter applied at the fragment call site (keeps WebGPU layout stable).
static float2 arachHubJitter(uint seed) {
    return float2((arachHash(seed + 0xE5u) - 0.5) * 0.10,
                  (arachHash(seed + 0xF6u) - 0.5) * 0.10);
}

// ── Per-web 2D evaluation ─────────────────────────────────────────────────────
//
// Returns ArachneWebResult for a single web at pixel uv.
// All distances in UV space. Call for both pool webs and the anchor web.
//
// Session 2 additions vs Session 1:
//   strandTangent: tangent of the dominant (closest) strand, used for Marschner BRDF.
//   dropVec + dropRadius: closest droplet normal data for mat_frosted_glass.
//
// V.7 Session 1 parameters:
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
    int    spokeCount,
    float  aspectX,
    float  aspectAngle,
    float  kSag
) {
    ArachneWebResult result;
    result.strandCov    = 0.0;
    result.dropCov      = 0.0;
    result.strandTangent = float2(1.0, 0.0); // default: horizontal (hub fallback)
    result.dropVec      = float2(0.0, 0.0);
    result.dropRadius   = 0.0035;

    // ── §4.1 macro: web silhouette + elliptical per-web variation ─────────────
    // Transforms pRel into a squashed frame; rest of evaluation uses squashed coords.
    float2 pRel0  = uv - hubUV;
    float2 sqDir  = float2(cos(aspectAngle), sin(aspectAngle));
    float2 sqPerp = float2(-sqDir.y, sqDir.x);
    float2 pLocal = float2(dot(pRel0, sqDir), dot(pRel0, sqPerp));
    pLocal *= float2(aspectX, 1.0 / aspectX);
    float2 pRel = pLocal.x * sqDir + pLocal.y * sqPerp;

    float r = length(pRel);
    if (r > webR * 1.20) return result;

    // Geometry is static — no audio-driven position offsets (D-020).
    // mv_warp temporal echo (decay=0.92) provides the "alive" motion.
    float2 tRel = pRel;
    float  rT   = r;
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
        // Hub tangent is degenerate — keep default (1,0)
    }

    // ── §4.2 meso: per-spoke gravity sag + variable spoke count ─────────────
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
    float2 bestSpokeTangent2D = float2(1.0, 0.0); // tangent of closest spoke
    if (rT > hubR && rT < webR * 1.18) {
        for (int ri = 0; ri < nVisible; ri++) {
            // Alternating-pair reveal: maximises angular coverage per reveal step.
            int halfN = spokeCount / 2;
            int revI  = (ri % 2 == 0) ? (ri / 2) : (ri / 2 + halfN);
            int i = revI % spokeCount;

            // ±22% angular jitter per (seed, spoke_index) — deterministic (D-041)
            float jitter = (arachHash(seed + uint(i) * 7u) - 0.5) * baseStep * 0.44;
            float spAng  = rotAngle + float(i) * baseStep + jitter;
            float2 d     = float2(cos(spAng), sin(spAng));

            // Segment distance with parabolic gravity sag (+v = downward).
            // V.7.5 §10.1.2: gravity-direction weighting. sin(spAng) is positive
            // for downward-pointing spokes (UV +Y is down), so max(0, sin) zeroes
            // out the upward half (no sag against gravity). 0.4 floor preserves
            // some droop on horizontal spokes — they still hang slightly.
            float tProj      = saturate(dot(tRel, d) / max(webR, 1e-5));
            float gravityW   = mix(0.4, 1.0, max(0.0, sin(spAng)));
            float sagDisp    = sagAmount * 4.0 * tProj * (1.0 - tProj) * gravityW;
            float2 spokePt   = tProj * webR * d + float2(0.0, sagDisp);
            float  spDist  = length(tRel - spokePt);
            if (spDist < minSpokeDist) {
                minSpokeDist     = spDist;
                bestSpokeTangent2D = d; // spoke direction = tangent
            }
        }
    }

    float anchorFade   = rT > webR ? exp(-(rT - webR) * 8.0) : 1.0;
    float spokeW       = mix(0.0024, 0.0014, taper);
    float spokeHaloSig = max(webR * 0.014, 1e-4);
    float spokeCov     = smoothstep(spokeW + aaW, spokeW - aaW, minSpokeDist) * anchorFade;
    float spokeHalo    = exp(-minSpokeDist * minSpokeDist / (spokeHaloSig * spokeHaloSig))
                        * 0.38 * anchorFade;

    // ── §4.2 Archimedean spiral + micro-wobble ─────────────────────────────
    // §4.3 micro: adhesive droplets on spiral threads, hash-lattice (8–12 px spacing)
    float spirCov      = 0.0;
    float spirHalo     = 0.0;
    float dropCovLocal = 0.0;
    float spirDist     = 1e6;
    float theta        = 0.0;
    float2 spirTangent2D = float2(1.0, 0.0); // tangent of closest spiral point
    float bestDropDist = 1e6;
    float2 bestDropVec = float2(0.0, 0.0);

    float progressR = (stage >= 3u) ? webR
                    : (stage == 2u) ? progress * webR
                    : 0.0;

    if (rT >= hubR && rT <= progressR + spokeW * 2.0) {
        theta  = atan2(tRel.y, tRel.x);
        float sCoord = theta - (rT / webR) * spirRevs * 2.0 * M_PI_F;

        // §4.2 meso: time-invariant micro-wobble (0.003/rT × fbm4 — no time term)
        float arcParam  = rT / max(webR, 1e-5);
        float seedF     = float(seed) * 2.3283064e-10;  // seed / 2^32 → [0,1)
        float wobbleAng = (0.003 / max(rT, 0.001))
                        * fbm4(float3(arcParam * 6.0 * spirRevs, seedF * 113.7, 0.0));
        sCoord += wobbleAng;

        float sf      = fract(sCoord / (2.0 * M_PI_F));
        spirDist = min(sf, 1.0 - sf) * webR / max(spirRevs, 0.1);
        // Spiral tangent: angular direction at the closest point on the arc.
        spirTangent2D = float2(-sin(theta), cos(theta));

        float inZone   = (rT >= hubR && rT <= progressR) ? 1.0 : 0.0;
        float spirW    = 0.0013;
        float spirSig  = max(webR * 0.009, 1e-4);
        spirCov  = smoothstep(spirW + aaW, spirW - aaW, spirDist) * inZone;
        spirHalo = exp(-spirDist * spirDist / (spirSig * spirSig)) * 0.25 * inZone;

        // §4.3 micro: adhesive droplets — spiral threads only (radial spokes are glue-free
        // per silk biology). Only evaluate for pixels close to the spiral strand.
        float dropRadius = 0.0035; // ≈ 3.8 px at 1080p
        result.dropRadius = dropRadius;

        if (inZone > 0.0 && spirDist < dropRadius + 0.0005) {
            // Per-web spacing derived from seed: 8–12 px at 1080p = 0.0074–0.0111 UV.
            float spacingUV   = 0.0074 + arachHash(seed + 0x1337u) * 0.0037;
            float dropsPerRev = max(3.0, 2.0 * M_PI_F * rT / spacingUV);
            float dTheta      = 2.0 * M_PI_F / dropsPerRev;

            float thetaN   = fract(theta / (2.0 * M_PI_F));
            int   dropBase = int(thetaN * dropsPerRev);

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
                    // Track closest drop center for spherical-cap detail_normal
                    if (dist < bestDropDist) {
                        bestDropDist = dist;
                        bestDropVec  = tRel - dropPos; // pixel − drop_center in tRel space
                    }
                }
            }
        }
    }

    // ── §4.4 Dominant strand tangent (spoke or spiral) ────────────────────────
    // Chose whichever strand type the pixel is closest to, for BRDF lift in fragment.
    // Hub pixels use default tangent (strandTangent initialized to (1,0) above).
    if (rT >= hubR * 1.5) {
        result.strandTangent = (minSpokeDist <= spirDist && minSpokeDist < 1e5)
                                ? bestSpokeTangent2D
                                : spirTangent2D;
    }
    result.dropVec = bestDropVec;

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

    // D-026 audio drivers — deviation-form only (Session 3 D-026/D-020 audit)
    float hueDrift = fract(f.accumulated_audio_time * 0.025 + f.mid_att_rel * 0.08);

    // Strand emission gain: continuous driver ≥ 2× beat accent (CLAUDE.md rule of thumb).
    //   ratio = 0.18 / 0.07 ≈ 2.57× — satisfies requirement.
    // baseEmissionGain is FeatureVector-based so D-019 warmup is implicit.
    // beatAccent: drums_energy_dev is naturally 0 at silence (no drum energy).
    float baseEmissionGain = 1.0 + 0.18 * f.bass_att_rel;  // ±≈0.09 around 1.0
    float beatAccent = 0.07 * max(0.0, stems.drums_energy_dev);  // positive-only accent

    // ── §4.1 macro: synthetic lighting vectors for 2D-to-3D BRDF lift (§3) ──
    // kL: key light direction (fixed, warm upper-right) for consistent directional cue.
    // kV: z-forward viewer (screen-space 2D convention). dot(T,kV)=0 for T in xy.
    // kBioL: bioluminescent light from behind the screen for SSS rim glow (E4).
    //
    // 2D Marschner adaptation: V_silk = T (fiber tangent) rather than kV.
    // When V=T, the R lobe fires for strands aligned with kL (theta_h→0 when T‖L),
    // and the TT lobe fires for anti-parallel strands. Different orientations glow
    // differently — producing the axial-streak directionality of 04_specular_silk_fiber_highlight.jpg.
    const float3 kL      = normalize(float3(0.45, 0.65, 0.30));
    const float3 kV      = float3(0.0, 0.0, 1.0);
    const float3 kBioL   = normalize(float3(0.0, 0.0, -1.0));
    // V.7.5 §10.1.4: TT-lobe warm rim (back-lit silk per ref 04). Shared by
    // anchor + pool silk material sites and by the §5.3 backsideCue blend.
    const float3 kWarmTT = float3(1.00, 0.78, 0.45);
    // V.7.5 §10.1.6: warm directional key + cool ambient fill (ref 05).
    // Cool ambient prevents the off-rim threads from going pure-warm and
    // reading as cyberpunk-orange (the §10.1.6 caveat).
    const float3 kLightCol = float3(1.00, 0.85, 0.65);
    const float3 kAmbCol   = float3(0.55, 0.65, 0.85) * 0.15;

    // SSS bioluminescent rim constant: evaluated once per fragment, shared by all strands.
    // N = screen normal (0,0,1), L = behind screen (0,0,-1), V = kV.
    // sss_backlit result ≈ 0.052 — subtle uniform rim on all strands (E4 gate).
    float kSSSRim = sss_backlit(float3(0.0, 0.0, 1.0), kBioL, kV, 0.25, 0.2);

    // ── §4.4 Smooth-union strand accumulation ─────────────────────────────────
    float strandPseudo  = 1.0;
    float prevStrandCov = 0.0;
    float3 strandColor  = float3(0.0);
    float3 dropColorAccum = float3(0.0); // per-web drop material accumulator (replaces dropPseudo)

    // §5.3 R-lobe + coverage accumulators for warm TT-lobe backsideCue (V.7.5 §10.1.4)
    float strandCovTotal = 0.0;
    float rLobeTotal     = 0.0;

    // ── Permanent anchor web (D-037: always visible; seed=1984u, hub upper-centre)
    {
        uint   ancSeed = 1984u;
        float2 ancHub  = float2(0.42, 0.40) + arachHubJitter(ancSeed);
        ArachneWebResult wr = arachneEvalWeb(
            uv, ancHub, 0.22, 0.30, 6.0, ancSeed,
            3u, 1.0,
            arachSpokeCount(ancSeed), arachAspect(ancSeed),
            arachAspectAngle(ancSeed), arachKSag(ancSeed)
        );

        float newStrandD   = op_blend(strandPseudo, 1.0 - wr.strandCov, 0.012);
        float newStrandCov = 1.0 - newStrandD;
        float delta        = max(0.0, newStrandCov - prevStrandCov);

        if (delta > 0.001) {
            // §4.3 specular: silk Marschner-lite per-strand (mat_silk_thread, M3+E4)
            float2 tang2D = wr.strandTangent;
            float3 T      = normalize(float3(tang2D, 0.0));
            float3 N_fib  = float3(-tang2D.y, tang2D.x, 0.0);

            // 2D-adapted V: view along fiber axis so R lobe fires for L-aligned strands
            float3 V_silk = T;

            // §3.3 Cool-warm tint with rim modulation
            float3 silkBase = hsv2rgb(float3(fract(0.52 + hueDrift * 0.10), 0.55, 1.00));
            // V.7.5 §10.1.4: warm TT-lobe replaces cool-blue rim (ref 04 mandatory).
            float rimT = saturate(1.0 - abs(dot(T, kL)));
            float3 silkTint = mix(silkBase, kWarmTT, rimT * 0.45);

            // mat_silk_thread: Marschner-lite fiber BRDF (§3)
            // azimuthal_r=0.35: wider than 3D default (0.18) for 2D V=T adaptation.
            // Static base tint — D-026 deviation gain applied post-BRDF (see below).
            FiberParams fp;
            fp.fiber_tangent = T;
            fp.fiber_normal  = N_fib;
            fp.azimuthal_r   = 0.35;
            fp.azimuthal_tt  = 0.55;
            fp.absorption    = 0.10;
            fp.tint          = silkTint * 0.50;  // static base — gain applied after BRDF
            MaterialResult silk = mat_silk_thread(float3(uv, 0.0), fp, kL, V_silk);
            silk.emission = min(silk.emission, float3(1.6)); // HDR cap

            // Bioluminescent SSS rim (E4 — static; gain applied below with strand emission)
            silk.emission += silkTint * kSSSRim * 0.40;

            // detail_normal: analytic fiber cross-section normal (E2 gate)
            float3 detail_normal = N_fib;
            silk.emission *= (0.88 + 0.12 * abs(detail_normal.x));

            // D-026 deviation emission gain (replaces brightness × bassBoost, D-020 safe)
            float emGain = baseEmissionGain + beatAccent;
            silk.emission *= emGain;
            // V.7.5 §10.1.6: warm key tint + cool ambient fill (ref 05).
            silk.emission *= kLightCol;
            silk.emission += silk.albedo * kAmbCol;

            // Hub fallback: tangent undefined → clamp to base bioluminescent glow
            float tangStrength = saturate(length(tang2D) * 8.0);
            silk.emission = mix(silkTint * 0.22 * emGain, silk.emission, tangStrength);

            strandColor  += silk.emission * delta;
            strandPseudo  = newStrandD;
            prevStrandCov = newStrandCov;

            // §5.3 R-lobe accumulation for backsideCue
            float TdotL   = dot(T, kL);
            float thetaHR = acos(clamp((TdotL + 1.0) * 0.5, 0.0, 1.0)); // V=T → theta_o=0
            float rLobe   = exp(-thetaHR * thetaHR / (2.0 * 0.35 * 0.35));
            rLobeTotal    += rLobe * delta;
            strandCovTotal += delta;
        } else {
            strandPseudo  = op_blend(strandPseudo, 1.0 - wr.strandCov, 0.012);
            prevStrandCov = 1.0 - strandPseudo;
        }

        // §4.3 micro: adhesive droplets — mat_frosted_glass with analytic detail_normal
        if (wr.dropCov > 0.01) {
            float2 d2   = wr.dropVec; // vector from drop center to pixel in tRel space
            float r_norm = length(d2) / max(wr.dropRadius, 1e-5);
            float h      = sqrt(max(0.0, 1.0 - r_norm * r_norm));
            // §4.3 micro: droplet spherical-cap detail_normal (analytic)
            float3 detail_normal = normalize(float3(d2 / max(wr.dropRadius, 1e-5), h));
            MaterialResult glass = mat_frosted_glass(float3(uv, 0.0), detail_normal);
            glass.emission = glass.albedo * 0.04; // reduce SSS: 0.15 → 0.04 (dielectric, not glowing)
            // Mirror glint: single bright point per droplet, distinct from silk's axial sheen
            float3 Rdrop = reflect(-kL, detail_normal);
            float spec   = pow(saturate(dot(Rdrop, kV)), 64.0);
            float3 glintAdd = float3(0.95, 0.97, 1.00) * spec * 1.4;
            dropColorAccum += (glass.emission + glintAdd) * wr.dropCov;
        }
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
            w.rng_seed, w.stage, w.progress,
            arachSpokeCount(w.rng_seed), arachAspect(w.rng_seed),
            arachAspectAngle(w.rng_seed), arachKSag(w.rng_seed)
        );

        float scaledStrand = wr.strandCov * w.opacity;
        float scaledDrop   = wr.dropCov   * w.opacity;
        if (scaledStrand < 0.003 && scaledDrop < 0.003) continue;

        float newStrandD   = op_blend(strandPseudo, 1.0 - scaledStrand, 0.012);
        float newStrandCov = 1.0 - newStrandD;
        float delta        = max(0.0, newStrandCov - prevStrandCov);

        if (delta > 0.001) {
            // §4.3 specular: silk Marschner-lite for pool web strands
            float2 tang2D   = wr.strandTangent;
            float3 T        = normalize(float3(tang2D, 0.0));
            float3 N_fib    = float3(-tang2D.y, tang2D.x, 0.0);
            float3 V_silk   = T;

            // Per-web cool-warm tint using birth_hue (D-026 hue drift modulation)
            float finalHue  = fract(w.birth_hue + hueDrift * 0.12);
            float3 silkBase = hsv2rgb(float3(finalHue, 0.55, 1.00));
            // V.7.5 §10.1.4: warm TT-lobe replaces cool-blue rim (ref 04 mandatory).
            float rimT      = saturate(1.0 - abs(dot(T, kL)));
            float3 silkTint = mix(silkBase, kWarmTT, rimT * 0.45);

            FiberParams fp;
            fp.fiber_tangent = T;
            fp.fiber_normal  = N_fib;
            fp.azimuthal_r   = 0.35;
            fp.azimuthal_tt  = 0.55;
            fp.absorption    = 0.10;
            fp.tint          = silkTint * 0.50 * w.opacity;  // static base with opacity
            MaterialResult silk = mat_silk_thread(float3(uv, 0.0), fp, kL, V_silk);
            silk.emission = min(silk.emission, float3(1.6));

            silk.emission += silkTint * kSSSRim * 0.40 * w.opacity;

            float3 detail_normal = N_fib;
            silk.emission *= (0.88 + 0.12 * abs(detail_normal.x));

            // D-026 deviation emission gain (same global gain for all pool webs)
            float emGain = baseEmissionGain + beatAccent;
            silk.emission *= emGain;
            // V.7.5 §10.1.6: warm key tint + cool ambient fill (ref 05).
            silk.emission *= kLightCol;
            silk.emission += silk.albedo * kAmbCol;

            float tangStrength = saturate(length(tang2D) * 8.0);
            silk.emission = mix(silkTint * 0.22 * emGain * w.opacity,
                                silk.emission, tangStrength);

            strandColor    += silk.emission * delta;
            strandPseudo    = newStrandD;
            prevStrandCov   = newStrandCov;

            float TdotL   = dot(T, kL);
            float thetaHR = acos(clamp((TdotL + 1.0) * 0.5, 0.0, 1.0));
            float rLobe   = exp(-thetaHR * thetaHR / (2.0 * 0.35 * 0.35));
            rLobeTotal    += rLobe * delta;
            strandCovTotal += delta;
        } else {
            strandPseudo  = op_blend(strandPseudo, 1.0 - scaledStrand, 0.012);
            prevStrandCov = 1.0 - strandPseudo;
        }

        // §4.3 micro: adhesive droplets via mat_frosted_glass
        if (scaledDrop > 0.01) {
            float2 d2    = wr.dropVec;
            float r_norm = length(d2) / max(wr.dropRadius, 1e-5);
            float h      = sqrt(max(0.0, 1.0 - r_norm * r_norm));
            float3 detail_normal = normalize(float3(d2 / max(wr.dropRadius, 1e-5), h));
            MaterialResult glass = mat_frosted_glass(float3(uv, 0.0), detail_normal);
            glass.emission = glass.albedo * 0.04;
            float3 Rdrop  = reflect(-kL, detail_normal);
            float spec    = pow(saturate(dot(Rdrop, kV)), 64.0);
            float3 glintAdd = float3(0.95, 0.97, 1.00) * spec * 1.4;
            dropColorAccum += (glass.emission + glintAdd) * scaledDrop;
        }
    }

    // §5.3 Cool-blue rim back-light cue ─────────────────────────────────────
    // Back-face of strands (R-lobe minimal) catch the bioluminescent back-light
    // as a cool-blue rim, simulating photon scatter through the silk structure.
    float backsideCue = strandCovTotal * saturate(1.0 - rLobeTotal);

    // ── Spider (2D — clip-space → UV, Y-flipped; D-040 overlay; not in smooth-union)
    float3 spiderContrib = float3(0.0);
    float  spiderMaskOut = 0.0;
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

        // mat_chitin: bioluminescent carapace (M3 — replaces inline near-black float3)
        // VdotH ≈ bodyCov (body coverage proxies grazing incidence), NdotV = bodyCov,
        // thickness_nm = 280 (blue-spectrum chitin, per D-040 reference).
        MaterialResult chitinMat = mat_chitin(float3(spRel, 0.0),
                                              float3(0.0, 0.0, 1.0),
                                              bodyCov * 0.7, bodyCov, 280.0);
        float3 chitin    = chitinMat.albedo;
        float3 spiderCol = chitin * bodyCov + rimCol
                         + float3(0.025, 0.090, 0.110) * legCov;
        spiderMaskOut    = max(bodyCov, legCov * 0.65);
        spiderContrib    = spiderCol;
    }

    // ── Background (valence/arousal-tinted near-black) ─────────────────────────
    float  gv    = saturate(f.valence * 0.5 + 0.5);
    float  ga    = saturate(f.arousal * 0.5 + 0.5);
    float3 bgLow  = mix(float3(0.004, 0.004, 0.018), float3(0.008, 0.014, 0.006), ga);
    float3 bgHigh = mix(float3(0.005, 0.009, 0.040), float3(0.015, 0.009, 0.024), ga);
    float3 bgCol  = mix(bgLow, bgHigh, uv.y * gv);

    // ── §5.3 Cool-blue rim back-light + combine strands ───────────────────────
    float3 webColor = strandColor + dropColorAccum;
    // V.7.5 §10.1.4: warm back-rim cue (was cool-blue 0.40,0.62,0.95).
    webColor += float3(0.95, 0.70, 0.45) * backsideCue * 0.20;

    // Spider overlay
    if (spider.blend > 0.01) {
        webColor = mix(webColor, spiderContrib, spider.blend * spiderMaskOut);
    }

    // ── §5.1 2D screen-space mist (replaces depth-based apply_fog, D-029) ────
    // fbm8 mist field: multiplicative haze (0.85–1.0 range). No time component —
    // atmosphere is static. fbm8 octave count also reinforces M2 ≥4-octave gate.
    float mistNoise = fbm8(float3(uv * 4.0, 0.0)) * 0.5 + 0.5;
    float mist      = mix(0.85, 1.0, mistNoise);
    webColor       *= mist;

    // ── §5.2 Screen-space dust motes (Approach B, D-029) ─────────────────────
    // fbm4 at high frequency with drift via accumulated_audio_time.
    // Motes pause when audio pauses (anti-FA33: no free-running sin/time motion).
    // Density ≈ 3% of background pixels at silence (threshold tuned for HDR levels).
    float2 driftUV  = uv + float2(0.020, 0.013) * f.accumulated_audio_time * 0.05;
    float moteNoise  = fbm4(float3(driftUV * 80.0, 0.0));
    // f.mid_att_rel: slow mid-band breathing raises density when melody is present (D-026).
    float moteThresh = 0.66 - 0.04 * max(0.0, f.mid_att_rel);  // 0.66 (silence) → 0.62 (loud)
    float mote       = smoothstep(moteThresh - 0.04, moteThresh, moteNoise);
    float3 moteColor = float3(0.70, 0.85, 1.00) * 0.35;
    webColor        += moteColor * mote;

    float3 color = webColor + bgCol;
    color = min(color, float3(0.95));
    return float4(color, 1.0);
}

// ── MV-Warp functions ─────────────────────────────────────────────────────────
// decay 0.92: short echo smears thread halos into bioluminescent trails. (D-041)

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
