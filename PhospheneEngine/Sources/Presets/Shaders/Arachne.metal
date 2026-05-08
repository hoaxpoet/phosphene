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

// ── V.7.7D: 3D SDF spider anatomy + chitin material (D-094) ──────────────────
//
// Replaces the V.7.5 / V.7.7B/C 2D dark-silhouette overlay with a per-pixel
// ray-marched 3D spider rendered into a screen-space patch around the spider's
// UV anchor. The Spider pillar's "rare reward" semantics are preserved
// (organic trigger + 5-min cooldown — V.7.7D does NOT touch trigger logic);
// the visual fidelity is upgraded so every appearance reads as a real
// orb-weaver: cephalothorax + abdomen + petiole + 8 IK legs + 6 eyes,
// chitin material with biological-strength thin-film iridescence, listening
// pose realised CPU-side via lifted tip[0]/tip[1] (see ArachneState+ListeningPose).
//
// Body-local frame: +x = heading direction, +y = right side (in body frame),
// +z = up (away from web plane). All anatomy dimensions in §6.1 are body-
// local; multiply by `kSpiderScale` to convert to UV.
//
// Ray-march dispatch is gated by a screen-space patch (`kSpiderPatchUV`)
// around the spider's UV position so miss rays do not fire on every pixel.

constant float kSpiderScale  = 0.018;  // body-local unit → UV scale
constant float kSpiderPatchUV = 0.15;  // patch radius around spider UV anchor

// Cephalothorax + abdomen + petiole — returns (distance, materialID 0).
static float2 sd_spider_body(float3 p) {
    // Cephalothorax — ellipsoid 1.0 long × 0.7 wide × 0.5 tall, centred at +x.
    float3 cephP = (p - float3(0.55, 0.0, 0.0)) / float3(0.5, 0.35, 0.25);
    float  cephD = (length(cephP) - 1.0) * 0.25;  // re-multiply by min radius

    // Abdomen — ellipsoid 1.4 long × 1.1 wide × 0.95 tall, centred at -x (rear).
    float3 abdP = (p - float3(-0.7, 0.0, 0.0)) / float3(0.7, 0.55, 0.475);
    float  abdD = (length(abdP) - 1.0) * 0.475;

    // Petiole cut — narrow neck via op_smooth_subtract of a cylindrical region.
    float3 petP = p - float3(-0.05, 0.0, 0.0);
    float  petR = length(petP.yz) - 0.10;
    float  petD = max(petR, abs(petP.x) - 0.15);

    float bodyD = op_smooth_union(cephD, abdD, 0.08);
    bodyD = op_smooth_subtract(bodyD, petD, 0.04);
    return float2(bodyD, 0.0);
}

// Six eye spheres clustered on the front of the cephalothorax — matID 1.
static float2 sd_spider_eyes(float3 p) {
    const float3 kEyeOff[6] = {
        float3(0.95, +0.10, +0.10), float3(0.95, -0.10, +0.10),  // anterior pair
        float3(0.85, +0.18, +0.05), float3(0.85, -0.18, +0.05),  // mid pair
        float3(0.78, +0.10, +0.18), float3(0.78, -0.10, +0.18)   // top pair
    };
    const float kEyeR[6] = { 0.05, 0.05, 0.035, 0.035, 0.030, 0.030 };

    float minD = 1e6;
    for (int i = 0; i < 6; i++) {
        minD = min(minD, length(p - kEyeOff[i]) - kEyeR[i]);
    }
    return float2(minD, 1.0);
}

// Convert UV → body-local 2D (z=0 implicit). Heading is the in-plane angle
// of the spider's heading direction in UV; the convention matches the legacy
// 2D head-offset code: +bodyX = `(cos(heading), -sin(heading))` in UV.
static float2 spider_body_local_xy(float2 uv, float2 spiderUV, float heading) {
    float2 dUV = uv - spiderUV;
    float c = cos(heading);
    float s = sin(heading);
    // Inverse rotation: bodyX = +x_body when uvDir = (cos(h), -sin(h)).
    return float2(c * dUV.x - s * dUV.y, s * dUV.x + c * dUV.y) / kSpiderScale;
}

// Leg SDF — 2-segment capsule with analytic outward-bending knee. The CPU
// listening pose is realised by writing a lifted tip into `spider.tip[0]` /
// `spider.tip[1]`; the IK below derives the raised knee organically from the
// lifted tip with no listenLift channel required. tip[i] is in clip-space;
// converted to body-local via clip→UV→body transformation.
static float2 sd_spider_legs(
    float3 p,
    device const ArachneSpiderGPU& spider,
    int    legIdx,
    float2 spiderUV
) {
    // Hip on cephalothorax — 4 per side, alternating left/right, evenly
    // spaced front-to-back (orb-weaver canonical posture per §6.1 / ref 13).
    float legSideF = (legIdx & 1) ? -1.0 : 1.0;
    float legBack  = float(legIdx / 2) * 0.18 + 0.40;
    float3 hipL    = float3(0.55 - legBack, legSideF * 0.30, 0.0);

    // tip[i] is in clip-space; convert to UV then to body-local.
    float2 tipClip = spider.tip[legIdx];
    float2 tipUV   = float2((tipClip.x + 1.0) * 0.5, (1.0 - tipClip.y) * 0.5);
    float2 tipXY   = spider_body_local_xy(tipUV, spiderUV, spider.heading);
    float3 tipL    = float3(tipXY.x, tipXY.y, 0.0);

    // 2-segment IK: femur + tibia, equal length. Knee bends OUTWARD
    // (perpendicular to (tip − hip), away from body centre, biased +z).
    // Magnitude 0.20 tuned for §6.1 visual; see DECISIONS D-094.
    float3 mid     = mix(hipL, tipL, 0.5);
    float3 axis    = tipL - hipL;
    // Guard: when legSide is small but axis is purely along z, cross is zero.
    float3 outward = cross(axis, float3(0.0, 0.0, 1.0));
    float  outLen  = length(outward);
    float3 outN    = (outLen > 1e-5) ? (outward / outLen) : float3(0.0, 1.0, 0.0);
    float3 kneeL   = mid + outN * 0.20 * legSideF + float3(0.0, 0.0, 0.10);

    // Distance to two capsules (femur: hip→knee, tibia: knee→tip).
    float dFemur = sd_capsule(p, hipL,  kneeL, 0.025);
    float dTibia = sd_capsule(p, kneeL, tipL,  0.020);
    return float2(min(dFemur, dTibia), 2.0);
}

// Combined spider SDF. Returns (distance, materialID).
//   matID 0 = body (cephalothorax + abdomen)
//   matID 1 = eye (per-eye specular path)
//   matID 2 = leg
static float2 sd_spider_combined(
    float3 p,
    device const ArachneSpiderGPU& spider,
    float2 spiderUV
) {
    float2 body = sd_spider_body(p);
    float2 eyes = sd_spider_eyes(p);

    // Pick the closer surface; eyes take priority within their hit radius
    // so the per-eye specular path can apply.
    float2 anatomy = (eyes.x < body.x) ? eyes : body;

    for (int i = 0; i < 8; i++) {
        float2 leg = sd_spider_legs(p, spider, i, spiderUV);
        if (leg.x < anatomy.x) anatomy = leg;
    }
    return anatomy;
}

// ── V.7.7B: Staged composition WORLD + COMPOSITE ─────────────────────────────
//
// The legacy monolithic `arachne_fragment` was retired in V.7.7B alongside its
// preceding `// ── Fragment ── …` divider; what remains in this file is the
// staged dispatch path (`arachne_world_fragment` for stage WORLD,
// `arachne_composite_fragment` for stage COMPOSITE). They reuse the
// free-function building blocks above (`drawWorld`, `arachneEvalWeb`,
// `drawBackgroundWeb` etc.), so total LOC drops by ~240 lines vs V.7.7A
// while restoring V.7.5 v5 visual parity on the V.ENGINE.1 staged scaffold.
//
// `drawBackgroundWeb()` stays defined (Snell's-law refractive helper) but is
// not dispatched — V.7.7C will reintroduce it once Snell's-law refraction +
// the proper outer-boundary geometry land. Do NOT call it here.

constant constexpr sampler arachne_world_sampler(filter::linear,
                                                  address::clamp_to_edge);

// ── WORLD stage ───────────────────────────────────────────────────────────────
//
// Renders the six-layer dark close-up forest backdrop into a per-stage
// .rgba16Float offscreen texture (sampled by COMPOSITE at [[texture(13)]]).
// Reads `webs[0].row4` for the mood palette state broadcast by
// ArachneState._tick(); buffer(6) is bound by RenderPipeline+Staged.encodeStage
// (V.7.7B engine fix) and by the visual-review harness.

fragment float4 arachne_world_fragment(
    VertexOut                   in   [[stage_in]],
    constant FeatureVector&     f    [[buffer(0)]],
    device const ArachneWebGPU* webs [[buffer(6)]]
) {
    float4 moodRow = webs[0].row4;  // x=smoothedValence, y=smoothedArousal, z=accTime
    float3 col = drawWorld(in.uv, moodRow, moodRow.z);
    return float4(col, 1.0);
}

// ── COMPOSITE stage ───────────────────────────────────────────────────────────
//
// Samples the WORLD texture for the backdrop, then walks the active web pool
// and overlays foreground silk strands, adhesive droplets, and the spider
// silhouette. Mist + dust mote layers apply to the foreground only (matching
// the legacy fragment's webColor-only modulation).
//
// Mechanically lifted from the V.7.5 v5 / V.7.7-redo / V.7.8 monolithic
// `arachne_fragment` (deleted in V.7.7B): the only divergence is that
// `bgColor = drawWorld(...)` becomes `bgColor = worldTex.sample(...)`. Every
// other line (web walk, spider, mist, motes, final compose) is byte-identical
// to the retired implementation.

fragment float4 arachne_composite_fragment(
    VertexOut                                in       [[stage_in]],
    constant FeatureVector&                  f        [[buffer(0)]],
    constant StemFeatures&                   stems    [[buffer(3)]],
    device const ArachneWebGPU*              webs     [[buffer(6)]],
    device const ArachneSpiderGPU&           spider   [[buffer(7)]],
    texture2d<float, access::sample>         worldTex [[texture(13)]]
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

    // ── V.7.7D §8.2 whole-scene 12 Hz vibration (D-094) ──────────────────────
    //
    // Per-pixel UV jitter applied BEFORE the web walks. Length-scaling from
    // screen centre approximates §8.2's "tip vibrates more than anchor"
    // anchor-point physics — corners shake more than middle. WORLD sample
    // at the bottom of this fragment intentionally stays on the original
    // `uv` (forest floor + far layers do not shake — §8.2 anchor-vs-tip).
    //
    // Tunables match §8.2 with three CLAUDE.md-mandated divergences (D-094):
    //   1. Continuous amplitude widened 0.0025 → 0.0030 to satisfy the 2×
    //      continuous-vs-accent guideline.
    //   2. Bass-amplitude driver substituted from §8.2's `subBass_dev` to FV
    //      `bass_att_rel` (smoothed/attenuated bass deviation). FV has no
    //      `subBass_dev` split. `bass_att_rel` is the natural Arachne-side
    //      primitive for "sustained bass envelope" (it already drives
    //      `baseEmissionGain` for continuous strand emission) and stays at 0
    //      at AGC-average levels — exactly the audio-data-hierarchy contract
    //      the PresetAcceptance "beat is accent only" test enforces.
    //   3. The §8.2 per-kick spike `0.0015 × beat_bass × 0.4` is set to 0.
    //      With `bass_att_rel` already capturing the sustained bass envelope
    //      (its musical purpose), the additional per-kick term reads as a
    //      Layer-4-as-primary anti-pattern (Audio Hierarchy rule, CLAUDE.md):
    //      in the acceptance test fixture (steady bass_att_rel=0,
    //      beat beat_bass=1.0, bass_att_rel=0) the spike alone fails the 2×
    //      continuous-vs-beat invariant. Continuous-only is also closer to
    //      the §8.2 musical intent — "tremor on sustained bass". The per-kick
    //      character is preserved by the existing `beatAccent` strand
    //      emission term (line ~815 above).
    //
    // Coarse-phase quantization: per-pixel hash produces TV-static; quantizing
    // the random phase to an 8×8 grid gives coherent strand-scale tremor.
    const float kTremorHz = 12.0;
    float bassAmp        = max(f.bass_att_rel, 0.0);
    float ampUV          = 0.0030 * bassAmp * length(uv - float2(0.5, 0.5));
    float coarsePhase    = hash_f01_2(uv * 8.0) * 6.28318530718;
    float tremorPhase    = 2.0 * M_PI_F * kTremorHz * f.accumulated_audio_time;
    float tremorX        = sin(tremorPhase + coarsePhase);
    float tremorY        = sin(tremorPhase + coarsePhase + 1.5708);
    float2 vibOffset     = float2(tremorX, tremorY) * ampUV;
    float2 vibUV         = uv + vibOffset;

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
            vibUV, ancHub, 0.22, 0.30, 6.0, ancSeed,
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

        // V.7.7C §5.8: photographic dewdrop — Snell's-law refraction sampling
        // the WORLD stage texture, fresnel rim, pinpoint specular, dark edge ring.
        // Replaces the V.7.5 mat_frosted_glass + warm-amber emissive recipe.
        // worldTex is the WORLD stage's offscreen output bound at [[texture(13)]];
        // sampling it (vs inline drawWorld()) preserves the staged-composition
        // contract V.ENGINE.1 / D-072 / D-092 established. D-093.
        if (wr.dropCov > 0.01) {
            float2 d2     = wr.dropVec;
            float  rDrop  = wr.dropRadius;
            float  rNorm  = length(d2) / max(rDrop, 1e-5);

            // Spherical-cap normal at the sample point inside the drop.
            float  h      = sqrt(max(0.0, 1.0 - rNorm * rNorm));
            float3 sphN   = normalize(float3(d2 / max(rDrop, 1e-5), h));
            const float3 kViewRay = float3(0.0, 0.0, 1.0);

            // Snell's-law refraction (air n=1.0 → water n=1.33; eta = 0.752).
            // worldSampleScale = 2.5 × rDrop per §5.8 (foreground dewdrop tuning;
            // drawBackgroundWeb's 8× value is for background webs at depth, §5.12).
            float3 refr        = refract(-kViewRay, sphN, 0.752);
            float2 refractedUV = uv + refr.xy * (rDrop * 2.5);
            float3 bgSeen      = worldTex.sample(arachne_world_sampler, refractedUV).rgb;

            // Fresnel rim (Schlick power 5; warm-tint at edge).
            float  fresnel  = pow(1.0 - saturate(sphN.z), 5.0);
            float3 rimTint  = kLightCol * 0.85;
            float3 dropCol  = mix(bgSeen, rimTint, saturate(fresnel * 0.40));

            // Pinpoint specular at the half-vector position on the cap.
            // 2D half-vector projection on the cap. kViewRay.xy = (0, 0) so this
            // collapses to normalize(kL.xy) — the screen-space direction of the key
            // light. specPos sits at 60% of the drop radius along that direction.
            float2 halfDir  = normalize(kL.xy + kViewRay.xy);
            float2 specPos  = halfDir * rDrop * 0.6;
            float  specD    = length(d2 - specPos) / max(rDrop, 1e-5);
            float  specMask = 1.0 - smoothstep(0.0, 0.20, specD);
            dropCol += rimTint * specMask * 1.0;

            // Dark edge ring inside the silhouette (refraction breakdown at grazing angles).
            float  ring1    = smoothstep(0.85, 0.95, rNorm);
            float  ring2    = 1.0 - smoothstep(0.95, 1.0, rNorm);
            float  darkRing = ring1 * ring2;
            dropCol *= (1.0 - darkRing * 0.50);

            // Audio-reactive emission gain — preserves the V.7.5 D-026 modulation shape.
            dropCol *= (baseEmissionGain + beatAccent);

            dropColorAccum += dropCol * wr.dropCov;
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
            vibUV, hubUV, webR, w.rot_angle, w.spiral_revolutions,
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

        // V.7.7C §5.8: photographic dewdrop — same Snell's-law recipe as anchor block.
        // scaledDrop = wr.dropCov × w.opacity preserves V.7.5 fade semantics; older /
        // fading webs contribute proportionally less. D-093.
        if (scaledDrop > 0.01) {
            float2 d2     = wr.dropVec;
            float  rDrop  = wr.dropRadius;
            float  rNorm  = length(d2) / max(rDrop, 1e-5);

            float  h      = sqrt(max(0.0, 1.0 - rNorm * rNorm));
            float3 sphN   = normalize(float3(d2 / max(rDrop, 1e-5), h));
            const float3 kViewRay = float3(0.0, 0.0, 1.0);

            float3 refr        = refract(-kViewRay, sphN, 0.752);
            float2 refractedUV = uv + refr.xy * (rDrop * 2.5);
            float3 bgSeen      = worldTex.sample(arachne_world_sampler, refractedUV).rgb;

            float  fresnel  = pow(1.0 - saturate(sphN.z), 5.0);
            float3 rimTint  = kLightCol * 0.85;
            float3 dropCol  = mix(bgSeen, rimTint, saturate(fresnel * 0.40));

            // 2D half-vector projection on the cap. kViewRay.xy = (0, 0) so this
            // collapses to normalize(kL.xy) — the screen-space direction of the key
            // light. specPos sits at 60% of the drop radius along that direction.
            float2 halfDir  = normalize(kL.xy + kViewRay.xy);
            float2 specPos  = halfDir * rDrop * 0.6;
            float  specD    = length(d2 - specPos) / max(rDrop, 1e-5);
            float  specMask = 1.0 - smoothstep(0.0, 0.20, specD);
            dropCol += rimTint * specMask * 1.0;

            float  ring1    = smoothstep(0.85, 0.95, rNorm);
            float  ring2    = 1.0 - smoothstep(0.95, 1.0, rNorm);
            float  darkRing = ring1 * ring2;
            dropCol *= (1.0 - darkRing * 0.50);

            dropCol *= (baseEmissionGain + beatAccent);

            dropColorAccum += dropCol * scaledDrop;
        }
    }

    // ── V.7.7D Spider — 3D SDF anatomy + chitin material (D-094) ─────────────
    //
    // Replaces the V.7.5 2D dark-silhouette overlay with a per-pixel ray-march
    // through a screen-space patch around the spider's UV anchor. Anatomy is
    // ray-marched in body-local 3D (cephalothorax + abdomen + petiole + 8 IK
    // legs + 6 eyes); the colour is composed from §6.2 chitin recipe (brown-
    // amber base + thin-film iridescence at biological strength + Oren-Nayar
    // hair fuzz + per-eye specular). Spider rides the vibrating web — its
    // anchor UV translates by `(vibUV - uv)` so silk + body shake together.
    float3 spiderContrib = float3(0.0);
    float  spiderMaskOut = 0.0;
    if (spider.blend > 0.01) {
        float2 spUVStatic = float2((spider.posX + 1.0) * 0.5,
                                    (1.0 - spider.posY) * 0.5);
        float2 spUV       = spUVStatic + vibOffset;
        float  patchD     = length(uv - spUV);

        if (patchD < kSpiderPatchUV) {
            // Body-local XY at z=0 plane for the current pixel. Ray march from
            // (bodyXY, +z_high) toward -z to find the spider surface above.
            float2 bodyXY = spider_body_local_xy(uv, spUV, spider.heading);
            float3 ro     = float3(bodyXY.x, bodyXY.y, 5.0);
            float3 rd     = float3(0.0, 0.0, -1.0);

            // Inlined adaptive sphere trace — `ray_march_adaptive` hardcodes
            // sd_sphere; we substitute `sd_spider_combined`.
            float t = 0.0;
            const float tMax = 8.0;
            const int   maxSteps = 32;
            const float hitEps = 0.0008;
            int   matID = -1;
            bool  hitFound = false;
            float lastDist = 1.0;
            for (int sIdx = 0; sIdx < maxSteps && t < tMax; sIdx++) {
                float3 pCur = ro + rd * t;
                float2 sd   = sd_spider_combined(pCur, spider, spUV);
                lastDist    = sd.x;
                if (sd.x < hitEps) {
                    matID    = int(sd.y + 0.5);
                    hitFound = true;
                    break;
                }
                t += max(sd.x, 0.001);
            }

            if (hitFound) {
                float3 hitPos = ro + rd * t;
                // Inlined tetrahedron-trick normal estimation — same SDF substitution.
                const float kNormalEps = 0.0005;
                const float2 kK = float2(1.0, -1.0);
                float3 nMix =
                    kK.xyy * sd_spider_combined(hitPos + kK.xyy * kNormalEps, spider, spUV).x +
                    kK.yyx * sd_spider_combined(hitPos + kK.yyx * kNormalEps, spider, spUV).x +
                    kK.yxy * sd_spider_combined(hitPos + kK.yxy * kNormalEps, spider, spUV).x +
                    kK.xxx * sd_spider_combined(hitPos + kK.xxx * kNormalEps, spider, spUV).x;
                float3 nrm = normalize(nMix);

                if (matID == 1) {
                    // Eye: dark sphere with pinpoint specular when the
                    // half-vector aligns with the eye normal (§6.2).
                    float3 halfV = normalize(kL + kV);
                    float  spec  = (dot(halfV, nrm) > 0.95) ? 1.0 : 0.0;
                    spiderContrib = float3(0.02) + kLightCol * spec;
                    spiderMaskOut = 1.0;
                } else {
                    // Body / leg — chitin recipe at biological-iridescence
                    // strength (blend = 0.15). NEVER call mat_chitin with
                    // its V.3 default 1.0 blend in this path (CLAUDE.md
                    // What NOT To Do — §6.2 anti-reference 10).
                    const float3 baseAlbedo = float3(0.08, 0.05, 0.03);
                    float  hueShift = 0.55 + 0.3 * dot(nrm, kV);
                    float3 thin     = hsv2rgb(float3(fract(hueShift), 0.5, 0.4)) * 0.15;
                    float3 bodyCol  = baseAlbedo + thin;

                    // Hair fuzz — Oren-Nayar-like grazing-angle softening.
                    float fuzz = pow(1.0 - saturate(dot(nrm, kV)), 1.5) * 0.18;
                    bodyCol += fuzz * kLightCol;

                    // Body shadow term — most of the body sits in deep shadow.
                    float NdotL  = max(0.0, dot(nrm, kL));
                    float bodyLit = 0.30 + 0.70 * NdotL;
                    bodyCol *= bodyLit;

                    // Thin warm rim (preserves the V.7.5 silhouette signature).
                    float rim = pow(1.0 - saturate(dot(nrm, kV)), 3.0);
                    bodyCol += kLightCol * rim * 0.55;

                    spiderContrib = bodyCol;
                    spiderMaskOut = 1.0;
                }
            }
        }
    }

    // ── V.7.7B: WORLD backdrop sampled from the WORLD stage's texture ─────────
    // The same drawWorld() six-layer dark close-up forest the legacy fragment
    // computed inline now ships in `arachne_world_fragment` and is sampled
    // here at [[texture(13)]]. drawBackgroundWeb() stays absent (V.7.7C).
    float3 bgColor = worldTex.sample(arachne_world_sampler, uv).rgb;

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

