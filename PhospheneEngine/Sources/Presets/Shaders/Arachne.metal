// Arachne.metal — 2D SDF bioluminescent spider-web field (Increment V.7 Session 3).
//
// V.7 Session 3 changes (audio routing audit — D-020/D-026 compliance):
//   §3.1  Audit table — two D-020 violations found and removed; one D-026 violation
//         found and rewritten.
//   §3.2  Strand vibration (vibAmp/vibPhase) removed: web geometry is static (D-020).
//         tRel now equals pRel directly; mv_warp temporal echo (decay=0.92) is the
//         "alive" mechanism per CLAUDE.md Architecture note.
//   §3.3  brightness = 0.12 + f.bass × 0.76 + ... rewritten to deviation form (D-026).
//         V.7.5 §10.1.3: silkTint factor 0.50 → 0.32 so drops carry the visual focus.
//         New scheme: static tint (silkTint × 0.32) + post-BRDF deviation gain:
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
//   buffer(6) = ArachneWebGPU[kArachWebs]  (320 bytes at kArachWebs=4 — ArachneState.webBuffer)
//   buffer(7) = ArachneSpiderGPU   (80 bytes  — ArachneState.spiderBuffer)
//
// D-026 deviation-first, D-019 warmup, D-037: two seed webs guarantee visibility.

// ── GPU structs (byte-match Swift counterparts) ──────────────────────────────

struct ArachneWebGPU {
    float hub_x, hub_y, radius, depth;
    float rot_angle; uint anchor_count; float spiral_revolutions; uint rng_seed;
    float birth_beat_phase; uint stage; float progress, opacity;
    float birth_hue, birth_sat, birth_brt; uint is_alive;
    // Row 4: global mood — x=smoothedValence, y=smoothedArousal, z=accTime, w=reserved.
    // Written to all slots each frame by ArachneState._tick(). drawWorld() reads webs[0].row4.
    float4 row4;
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

// ── V.7.7: WORLD pillar ───────────────────────────────────────────────────────
// Dark close-up forest atmosphere — camera is inches from the web (refs 01, 06, 08).
// No landscape, no skyline, no horizon bands. Background is near-black deep forest with
// atmospheric mist from above (dawn light through canopy), a narrow light shaft, drifting
// dust motes, organic forest floor at bottom, and substantial bark-textured near-frame
// branches the web anchors to (ref 11, 18).
//
// drawBackgroundWeb() can call drawWorld(refractedUV, ...) for Snell's-law refraction.
// References: 01, 05, 06, 07, 08, 11, 17, 18.
//
// UV: (0,0)=top-left, (1,1)=bottom-right.
// moodRow.x=smoothedValence [-1,1], .y=smoothedArousal [-1,1], .z=accumulatedAudioTime.

static float3 drawWorld(float2 uv, float4 moodRow, float accTime) {
    float v = clamp(moodRow.x, -1.0, 1.0);
    float a = clamp(moodRow.y, -1.0, 1.0);

    float sat = 0.22 + 0.38 * saturate(0.5 + 0.5 * a);
    float val = 0.08 + 0.18 * saturate(0.5 + 0.5 * a);
    if (sat * val < 0.04) return float3(0.0);  // silence anchor (ref 08)

    // §4.3 hue: valence shifts teal (cool/dark, ref 06) → amber (warm/dawn, ref 05).
    float atmHue   = mix(0.60, 0.09, saturate(0.5 + 0.5 * v));
    float3 atmDark = hsv2rgb(float3(atmHue, sat * 0.75, val));
    float3 atmMid  = hsv2rgb(float3(atmHue, sat * 0.45, val * 2.4));  // brighter mist tint

    // Deep background: near-black with subtle fbm tonal variation (refs 06, 08).
    // No horizon — you're inches from the web; background is dark forest depth.
    float deepN = fbm4(float3(uv * 1.8, 0.23)) * 0.5 + 0.5;
    float3 col  = atmDark * (0.07 + deepN * 0.05);

    // Atmospheric mist: radial soft glow from upper portion of frame (refs 05, 06).
    // Dawn light filtering through canopy above the anchor branches — NOT a band.
    float mistR = length(uv - float2(0.50, -0.08));
    float mistN = fbm4(float3(uv * 3.8 + float2(0.18, 0.73), 0.47)) * 0.5 + 0.5;
    float mist  = exp(-mistR * mistR / 0.30) * 0.24 * sat;
    col += atmMid * mist * (0.55 + 0.45 * mistN);

    // Light shaft: narrow diagonal beam from upper-left (ref 07 — beam structure only;
    // warm tone is incidental to that ref; our shaft stays cool-tinted per palette).
    float2 shO = uv - float2(0.16, 0.0);
    float2 shD = normalize(float2(0.20, 1.0));
    float  shT = dot(shO, shD);
    float  shP = length(shO - shT * shD);
    float  shI = exp(-shP * shP / (0.011 * 0.011))
               * smoothstep(0.0, 0.22, shT) * smoothstep(1.15, 0.55, shT)
               * 0.06 * val;
    col += atmMid * 1.6 * shI;

    // Dust motes: accTime-drifted hash field; pauses at silence (anti-FA33).
    float2 driftUV = uv * float2(44.0, 22.0) + float2(accTime * 0.006, accTime * 0.003);
    float moteN = fbm4(float3(driftUV, 0.31)) * 0.5 + 0.5;
    col += atmMid * smoothstep(0.79, 0.85, moteN) * 0.04 * val;

    // Forest floor: organic dark texture at bottom (ref 17 — moss, leaf litter).
    // Smooth fade — no hard edge at any particular y value.
    float floorFade = smoothstep(0.52, 1.0, uv.y);
    float floorN    = fbm4(float3(uv.x * 9.0, uv.y * 14.0, 0.67)) * 0.5 + 0.5;
    col = mix(col, atmDark * (0.05 + floorN * 0.09), floorFade * 0.70);

    // ── Near-frame branches: substantial bark-textured trunks (refs 11, 18) ────
    // Positioned so the web's outermost radials anchor to them (ref 11).
    // Each branch tapers toward its tip; fbm4 gives deeply furrowed bark ridges (ref 18).
    // Cool rim on the upper-lit edge (dawn backlight from above, ref 05).

    // Left branch — upper-left corner → centre-left (primary anchor, thickest trunk).
    {
        float2 ba  = float2(-0.04, 0.06);
        float2 bb  = float2(0.27, 0.56);
        float2 dir = bb - ba;
        float2 pa  = uv - ba;
        float  tc  = saturate(dot(pa, dir) / max(dot(dir, dir), 1e-6));
        float  bd  = length(pa - dir * tc);
        float  br  = mix(0.044, 0.013, tc);  // tapers: thick root, thin tip
        float  cov = smoothstep(br + 0.005, br - 0.005, bd);
        // Bark: along-axis furrowing + cross-axis ridge texture (ref 18).
        float bkA  = fbm4(float3(tc * 9.0 + 0.11, bd * 38.0, 0.13)) * 0.5 + 0.5;
        float bkC  = fbm4(float3(tc * 0.5, bd * 52.0 + 0.44, 0.0)) * 0.5 + 0.5;
        float3 bkC3 = mix(atmDark * 0.22, atmDark * 0.38, bkA * bkC);
        // Faint rim on upper-lit edge from dawn light (ref 05).
        float rim  = smoothstep(br, br + 0.004, bd) * cov;
        bkC3 += atmMid * 0.08 * rim;
        col = mix(col, bkC3, cov);
    }

    // Right branch — upper-right corner → centre-right.
    {
        float2 ba  = float2(1.04, 0.09);
        float2 bb  = float2(0.73, 0.51);
        float2 dir = bb - ba;
        float2 pa  = uv - ba;
        float  tc  = saturate(dot(pa, dir) / max(dot(dir, dir), 1e-6));
        float  bd  = length(pa - dir * tc);
        float  br  = mix(0.034, 0.011, tc);
        float  cov = smoothstep(br + 0.004, br - 0.004, bd);
        float bkA  = fbm4(float3(tc * 8.0 + 0.83, bd * 34.0, 0.27)) * 0.5 + 0.5;
        float bkC  = fbm4(float3(tc * 0.4, bd * 46.0 + 0.91, 0.0)) * 0.5 + 0.5;
        float3 bkC3 = mix(atmDark * 0.19, atmDark * 0.32, bkA * bkC);
        float rim  = smoothstep(br, br + 0.003, bd) * cov;
        bkC3 += atmMid * 0.06 * rim;
        col = mix(col, bkC3, cov);
    }

    // Lower twig — bottom-right, smaller secondary anchor.
    {
        float2 ba  = float2(0.86, 1.04);
        float2 bb  = float2(0.60, 0.70);
        float2 dir = bb - ba;
        float2 pa  = uv - ba;
        float  tc  = saturate(dot(pa, dir) / max(dot(dir, dir), 1e-6));
        float  bd  = length(pa - dir * tc);
        float  br  = mix(0.018, 0.008, tc);
        float  cov = smoothstep(br + 0.002, br - 0.002, bd);
        float bkA  = fbm4(float3(tc * 7.0 + 0.55, bd * 40.0, 0.0)) * 0.5 + 0.5;
        float3 bkC3 = atmDark * (0.17 + 0.13 * bkA);
        col = mix(col, bkC3, cov);
    }

    return col;
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

    // Hub: dense silk knot (§5.4) — overlapping strand noise, NOT concentric rings.
    // Two-scale fbm4 min gives tangled-thread look matching refs 01, 11, 12.
    // Only visible from radial stage (1+): hub forms as radials converge, not before.
    float hubCov = 0.0;
    if (rT < hubR && stage >= 1u) {
        float2 hubN  = tRel / max(hubR, 1e-5) * 4.5;
        float  seedF = float(seed & 0xFFu) * (1.0 / 256.0);
        float hA = fbm4(float3(hubN, seedF)) * 0.5 + 0.5;
        float hB = fbm4(float3(hubN * 2.3 + float2(1.27, 0.74), seedF + 0.5)) * 0.5 + 0.5;
        float raw = min(hA, hB);
        // Threshold at 0.54→0.43: fbm4 remapped to [0,1], gives ~35% strand density.
        hubCov = smoothstep(0.54, 0.43, raw) * 0.80
               * smoothstep(hubR, hubR * 0.15, rT);  // fade at exact center
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

    // Pre-compute ALL spoke tip positions for frame thread polygon.
    // nTips always uses full spokeCount so the frame polygon is available in stage 0
    // (frame phase) BEFORE any radials appear — matching §5.2 biology-correct order.
    int    nTips = min(spokeCount, 17);
    float2 tipPos[17];
    for (int ti = 0; ti < nTips; ti++) {
        int halfNt = spokeCount / 2;
        int revIt  = (ti % 2 == 0) ? (ti / 2) : (ti / 2 + halfNt);
        int it     = revIt % spokeCount;
        float jitT = (arachHash(seed + uint(it) * 7u) - 0.5) * baseStep * 0.44;
        float angT = rotAngle + float(it) * baseStep + jitT;
        tipPos[ti] = webR * float2(cos(angT), sin(angT));
    }

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

    // ── Frame thread polygon — segment-by-segment reveal during stage 0 (§5.2 Frame) ──
    // Stage 0 (frame phase): edges appear one at a time as progress advances 0→1.
    //   Polygon stays OPEN (no closing edge) until all segments are laid.
    // Stages 1+ (radial/spiral/stable/evicting): full polygon always present.
    // This makes the frame polygon appear BEFORE any radials — matching §5.1 step 3
    // biology and §5.2 "Frame 0–3 s" spec (ARACHNE_V8_DESIGN.md).
    int  nFrameSegs;
    bool closeFrame;
    if (stage == 0u) {
        nFrameSegs = clamp(int(progress * float(nTips + 1)), 0, nTips);
        closeFrame = false;
    } else {
        nFrameSegs = nTips;
        closeFrame = true;
    }
    float minFrameDist = 1e6;
    if (nTips >= 2 && rT >= webR * 0.70) {
        for (int fi = 0; fi < nFrameSegs; fi++) {
            int fj = fi + 1;
            if (!closeFrame && fj >= nFrameSegs) continue;  // open polygon during frame stage
            fj = fj % nTips;
            float2 ta = tipPos[fi];
            float2 tb = tipPos[fj];
            float2 ba = tb - ta;
            float2 pa = tRel - ta;
            float  h  = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-8));
            float  fd = length(pa - ba * h);
            minFrameDist = min(minFrameDist, fd);
        }
    }
    float frameW    = mix(0.0022, 0.0013, taper);
    float frameFade = rT > webR ? exp(-(rT - webR) * 6.0) : 1.0;
    float frameCov  = smoothstep(frameW + aaW, frameW - aaW, minFrameDist) * frameFade;
    float frameHalo = exp(-minFrameDist * minFrameDist / (spokeHaloSig * spokeHaloSig))
                    * 0.22 * frameFade;

    // ── Chord-segment capture spiral — outside-in construction (V.7.8) ──────────
    // Replaces Archimedean SDF. Each "ring" k is a polygon of N chord segments
    // connecting attachment points on consecutive spoke radials. Spider constructs
    // from outer ring inward (ring 0 is outermost, revealed first during stage 2).
    //
    // Proportional (geometric) spacing: r_k = r_outer × alpha^k so the inter-ring
    // radial gap scales with r — tighter near hub, wider near frame — matching the
    // biological observation that the spider pays out thread at roughly constant rate
    // while spiralling, so angular step is constant and radial step ∝ current radius.
    //
    // Free zone: no capture silk within r_inner = hubR × 1.8 (only radials inside).
    // References: ARACHNE_V8_DESIGN.md §5.5; biology refs 01, 03, 12.
    float spirCov      = 0.0;
    float spirHalo     = 0.0;
    float dropCovLocal = 0.0;
    float2 spirTangent2D = float2(1.0, 0.0);
    float bestDropDist = 1e6;
    float2 bestDropVec = float2(0.0, 0.0);
    float minChordDist = 1e6;
    float dropRadius   = 0.008;  // ≈ 8.6 px at 1080p (V.7.5 §10.1.3 — visual hero)
    result.dropRadius  = dropRadius;

    int   N_RINGS = max(2, int(spirRevs + 0.5));
    float r_outer = webR * 0.95;
    float r_inner = hubR * 1.8;  // free zone inner boundary

    // logAlpha: r_k = r_outer × exp(k × logAlpha). alpha < 1 so radii decrease inward.
    float logAlpha = (N_RINGS > 1)
                   ? log(r_inner / max(r_outer, 1e-5)) / float(N_RINGS - 1)
                   : 0.0;

    // Precompute spoke directions and gravity weights for all visible spokes.
    // Reused across all N_RINGS ring iterations to avoid redundant trig.
    int   nSpk = min(nVisible, 17);
    float2 sdDir[17];
    float  sdGrav[17];
    for (int si = 0; si < nSpk; si++) {
        float jitS = (arachHash(seed + uint(si) * 7u) - 0.5) * baseStep * 0.44;
        float angS = rotAngle + float(si) * baseStep + jitS;
        sdDir[si]  = float2(cos(angS), sin(angS));
        sdGrav[si] = mix(0.4, 1.0, max(0.0, sin(angS)));
    }

    float spirW   = 0.0013;
    float spirSig = max(webR * 0.009, 1e-4);

    if (rT >= r_inner * 0.78 && rT <= r_outer + spirW * 2.0 && nSpk >= 2) {
        for (int k = 0; k < N_RINGS; k++) {
            // Outside-in: ring 0 is outermost (first placed by spider).
            float ringR = r_outer * exp(logAlpha * float(k));

            // Stage gating: outer rings appear first — ring k visible once
            // progress passes k/N_RINGS. At stage ≥ 3 all rings are stable.
            bool kVis = (stage >= 3u) ||
                        (stage == 2u && float(k) / float(N_RINGS) <= progress);
            if (!kVis) continue;

            // Radius early exit: skip this ring if pixel is too far away.
            // Max chord distance from ring circle ≈ ringR × baseStep (half arc length).
            float ringGuard = ringR * baseStep * 1.3 + spirW;
            if (rT < ringR - ringGuard || rT > ringR + ringGuard) continue;

            // Parabolic sag at this ring radius (same formula as spoke SDF).
            float tProjR  = ringR / webR;
            float sagScale = sagAmount * 4.0 * tProjR * (1.0 - tProjR);

            // Per-ring drop spacing (slight per-ring variation for organic feel).
            float spacingUV = 0.0037 + arachHash(seed + 0x1337u + uint(k) * 31u) * 0.0019;

            for (int si = 0; si < nSpk; si++) {
                // Sequential spoke order — adjacent si/sj pairs form polygon edges.
                int sj = (si + 1) % spokeCount;
                if (sj >= nSpk) continue;  // guard for partial-reveal stages

                float2 pI = ringR * sdDir[si] + float2(0.0, sagScale * sdGrav[si]);
                float2 pJ = ringR * sdDir[sj] + float2(0.0, sagScale * sdGrav[sj]);

                float2 seg  = pJ - pI;
                float  segL = length(seg);
                float2 ptV  = tRel - pI;
                float  ht   = saturate(dot(ptV, seg) / max(dot(seg, seg), 1e-8));
                float  cd   = length(tRel - (pI + seg * ht));

                if (cd < minChordDist) {
                    minChordDist = cd;
                    spirTangent2D = (segL > 1e-6) ? normalize(seg) : float2(1.0, 0.0);
                }

                // Adhesive droplets: 5 candidates near the closest point on chord.
                // Parametric placement avoids O(numDrops) iteration (O(5) instead).
                if (cd < dropRadius + 0.0008) {
                    float spacingT = spacingUV / max(segL, 1e-5);
                    float dropBase = round(ht / max(spacingT, 1e-5)) * spacingT;
                    for (int di = -2; di <= 2; di++) {
                        float dt = dropBase + float(di) * spacingT;
                        int   dIdx = int(dt / max(spacingT, 1e-5) + 0.5) + 4096;
                        uint  dKey = seed * 2048u + uint(k * 200 + si * 17 + (dIdx & 0xFF));
                        dt += (arachHash(dKey) - 0.5) * spacingT * 0.5;
                        dt = saturate(dt);
                        float2 dropPos = pI + seg * dt;
                        float  dist    = length(tRel - dropPos);
                        if (dist < dropRadius + 0.0005) {
                            dropCovLocal = max(dropCovLocal,
                                smoothstep(dropRadius + 0.0003, dropRadius - 0.0003, dist));
                            if (dist < bestDropDist) {
                                bestDropDist = dist;
                                bestDropVec  = tRel - dropPos;
                            }
                        }
                    }
                }
            }
        }
    }

    float inZone = (rT >= r_inner && rT <= r_outer + spirW * 2.0) ? 1.0 : 0.0;
    spirCov  = smoothstep(spirW + aaW, spirW - aaW, minChordDist) * inZone;
    spirHalo = exp(-minChordDist * minChordDist / (spirSig * spirSig)) * 0.25 * inZone;

    // ── §4.4 Dominant strand tangent (spoke or chord) ─────────────────────────
    if (rT >= hubR * 1.5) {
        result.strandTangent = (minSpokeDist <= minChordDist && minSpokeDist < 1e5)
                                ? bestSpokeTangent2D
                                : spirTangent2D;
    }
    result.dropVec = bestDropVec;

    result.strandCov = max(max(max(spokeCov, spirCov), max(spokeHalo, spirHalo)),
                          max(hubCov, max(frameCov, frameHalo)));
    result.dropCov   = dropCovLocal;
    return result;
}

// ── V.7.7: Background dewy web ────────────────────────────────────────────────
// Fully-stable web placed in the forest mid-ground; threads render at 0.12× silk
// brightness so they recede behind the foreground pool webs; drops act as lenses
// onto the WORLD scene via Snell's-law refraction (ARACHNE_V8_DESIGN.md §5.12).
// References: 01_macro_dewy_web_on_dark.jpg, 03_micro_adhesive_droplet.jpg.
//
// NOTE: drawWorld() must be defined above this function in the compilation unit.

static float3 drawBackgroundWeb(
    float2 uv, float2 hubUV, float webRBg,
    uint   seed, float4 moodRow, float accTime
) {
    float kSagBg = 0.14 + arachHash(seed + 0x77u) * 0.04;  // [0.14, 0.18]
    float rotBg  = arachHash(seed + 0x55u) * 2.0 * M_PI_F;

    ArachneWebResult wr = arachneEvalWeb(
        uv, hubUV, webRBg, rotBg, 5.5, seed,
        3u, 1.0,
        arachSpokeCount(seed), arachAspect(seed),
        arachAspectAngle(seed), kSagBg
    );

    float3 result = float3(0.0);

    // Dim threads — cool bioluminescent tint; 0.12 factor keeps them behind foreground.
    if (wr.strandCov > 0.005) {
        float3 bgSilk = hsv2rgb(float3(0.55, 0.55, 0.75));
        result += bgSilk * 0.12 * wr.strandCov;
    }

    // Refractive drops — Snell's law, air (n=1.0) → water (n=1.33), eta = 0.752.
    if (wr.dropCov > 0.01) {
        float  dropR = wr.dropRadius;
        float2 d2    = wr.dropVec / max(dropR, 1e-5);
        float  hh    = sqrt(max(0.0, 1.0 - dot(d2, d2)));
        float3 sphN  = normalize(float3(d2, hh));
        const float3 kViewRay = float3(0.0, 0.0, 1.0);

        // Incident ray is -kViewRay (pointing into screen); dot(sphN, I) = -hh < 0 ✓
        float3 refr        = refract(-kViewRay, sphN, 0.752);
        float2 refractedUV = uv + refr.xy * dropR * 8.0;
        float3 bgSeen      = drawWorld(refractedUV, moodRow, accTime);

        // Fresnel blend: grazing angle → white rim; centre → refracted world image.
        float  cosTheta = abs(dot(sphN, kViewRay));
        float  fresnel  = pow(1.0 - cosTheta, 3.0);
        float3 dropCol  = mix(bgSeen, float3(1.0), fresnel * 0.30);

        // Pinpoint specular glint (ref 03_micro_adhesive_droplet.jpg).
        const float3 kLbg = normalize(float3(0.45, 0.65, 0.30));
        float3 Rdrop = reflect(-kLbg, sphN);
        float  spec  = pow(saturate(dot(Rdrop, kViewRay)), 64.0);
        dropCol += float3(1.0, 0.97, 0.93) * spec * 1.0;

        result += dropCol * wr.dropCov;
    }

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
    // V.7.7: WORLD palette mood state — smoothed in ArachneState._tick() and broadcast
    // to all web slots; drawWorld() + drawBackgroundWeb() read moodRow.x/y for palette.
    float4 moodRow = webs[0].row4;  // x=smoothedValence, y=smoothedArousal, z=accTime

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
    // §5.10 (V.7.9): Marschner-lite BRDF removed. Silk = thin lines + axial highlight.
    // kL used for axial highlight; kV for drop spherical-cap; kLightCol/kAmbCol for tint.
    const float3 kL       = normalize(float3(0.45, 0.65, 0.30));
    const float3 kV       = float3(0.0, 0.0, 1.0);
    const float3 kLightCol = float3(1.00, 0.85, 0.65);
    const float3 kAmbCol   = float3(0.55, 0.65, 0.85) * 0.15;

    // ── §4.4 Smooth-union strand accumulation ─────────────────────────────────
    float strandPseudo  = 1.0;
    float prevStrandCov = 0.0;
    float3 strandColor  = float3(0.0);
    float3 dropColorAccum = float3(0.0); // per-web drop material accumulator (replaces dropPseudo)

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
            // §5.10 (V.7.9): silk as thin lines + axial highlight (Marschner-lite removed).
            // Real silk at Arachne frame scale = faint connective tissue; drops carry 80%.
            float2 tang2D   = wr.strandTangent;
            float3 silkBase = hsv2rgb(float3(fract(0.52 + hueDrift * 0.10), 0.45, 0.80));
            // Axial highlight fires when kL grazes strand at shallow angle (abs dot < 0.35).
            float axial  = 1.0 + 0.6 * smoothstep(0.35, 0.05, abs(dot(tang2D, kL.xy)));
            float emGain = baseEmissionGain + beatAccent;
            float3 silk_col = silkBase * 0.60 * axial * emGain;
            silk_col *= kLightCol;
            silk_col += silkBase * kAmbCol * 0.25;
            strandColor  += silk_col * delta;
            strandPseudo  = newStrandD;
            prevStrandCov = newStrandCov;
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
            // V.7.5 §10.1.3: drops as visual hero. Warm-amber emissive base
            // (was glass.albedo * 0.04, neutral white); warm-white pinpoint
            // specular (was cool white); audio-gain modulated by the same
            // factor as silk so drops swell with the music.
            float3 dropAmber = float3(1.00, 0.78, 0.45);
            glass.emission   = dropAmber * 0.18;
            float3 Rdrop     = reflect(-kL, detail_normal);
            float spec       = pow(saturate(dot(Rdrop, kV)), 64.0);
            float3 glintAdd  = float3(1.00, 0.95, 0.85) * spec * 1.4;
            float3 dropEmission = glass.emission + glintAdd;
            dropEmission    *= (baseEmissionGain + beatAccent);
            dropColorAccum  += dropEmission * wr.dropCov;
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
            // §5.10 (V.7.9): silk as thin lines + axial highlight (Marschner-lite removed)
            float2 tang2D   = wr.strandTangent;
            float  finalHue = fract(w.birth_hue + hueDrift * 0.12);
            float3 silkBase = hsv2rgb(float3(finalHue, 0.45, 0.80));
            float axial  = 1.0 + 0.6 * smoothstep(0.35, 0.05, abs(dot(tang2D, kL.xy)));
            float emGain = baseEmissionGain + beatAccent;
            float3 silk_col = silkBase * 0.60 * w.opacity * axial * emGain;
            silk_col *= kLightCol;
            silk_col += silkBase * kAmbCol * 0.25;
            strandColor    += silk_col * delta;
            strandPseudo    = newStrandD;
            prevStrandCov   = newStrandCov;
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
            // V.7.5 §10.1.3: drops as visual hero — same recipe as anchor block.
            float3 dropAmber = float3(1.00, 0.78, 0.45);
            glass.emission   = dropAmber * 0.18;
            float3 Rdrop     = reflect(-kL, detail_normal);
            float spec       = pow(saturate(dot(Rdrop, kV)), 64.0);
            float3 glintAdd  = float3(1.00, 0.95, 0.85) * spec * 1.4;
            float3 dropEmission = glass.emission + glintAdd;
            dropEmission    *= (baseEmissionGain + beatAccent);
            dropColorAccum  += dropEmission * scaledDrop;
        }
    }

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

        // 8 legs
        float legMinDist = 1e6;
        for (int k = 0; k < 8; k++) {
            float2 tipUV = float2((spider.tip[k].x + 1.0) * 0.5,
                                  (1.0 - spider.tip[k].y) * 0.5);
            legMinDist   = min(legMinDist, arachSegDist(uv, spUV, tipUV));
        }
        float legCov = smoothstep(0.0045, 0.001, legMinDist);

        // V.7.5 §10.1.9: dark silhouette + thin warm rim catching kL through silk.
        // Spider deliberately dark per README §24 ("do not over-render the spider")
        // and ref 05 (backlit atmosphere). mat_chitin reserved for other presets.
        float3 bodyDark    = float3(0.04, 0.03, 0.02);
        float  rimT_local  = saturate(1.0 - bodyCov);          // edge of body silhouette
        float3 rimWarm     = float3(0.85, 0.55, 0.30) * rimT_local * bodyCov;
        float3 spiderCol   = bodyDark * bodyCov + rimWarm
                           + bodyDark * legCov * 0.6;          // legs share body tone
        spiderMaskOut      = max(bodyCov, legCov * 0.65);
        spiderContrib      = spiderCol;
    }

    // ── V.7.7 redo: WORLD pillar — dark close-up forest atmosphere ────────────
    // drawBackgroundWeb() removed — circular drop-patches produced oval artefacts.
    // Background webs reintroduced in V.7.8 after web outer boundary is fixed.
    float3 bgColor = drawWorld(uv, moodRow, moodRow.z);

    // ── Combine strands ────────────────────────────────────────────────────────
    float3 webColor = strandColor + dropColorAccum;

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

    float3 color = webColor + bgColor;
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
