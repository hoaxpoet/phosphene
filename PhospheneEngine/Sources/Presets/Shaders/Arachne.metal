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
//   buffer(6) = ArachneWebGPU[kArachWebs]  (384 bytes at kArachWebs=4 — ArachneState.webBuffer; V.7.7C.2: 320→384 via Row 5)
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
    // Row 5 (V.7.7C.2 / D-095): foreground BuildState packed for Commit 3 reads.
    // build_stage:    WebStage.rawValue of the foreground build cycle.
    // frame_progress: 0..1 within the frame phase.
    // radial_packed:  radialIndex + radialProgress (whole = current radial, fract = within).
    // spiral_packed:  spiralChordIndex + spiralChordProgress.
    // Background webs (slots 1..2) zero this row — no progressive build.
    // Layout: 4 individual floats, NOT a float4, to match Swift's WebGPU struct
    // byte-for-byte. The fragment shader does NOT read this row in Commit 2;
    // existing reads of rows 0–4 must remain byte-offset preserved.
    float build_stage;
    float frame_progress;
    float radial_packed;
    float spiral_packed;
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

// ── V.7.7C.2 §5.9 anchor twigs — single source of truth ─────────────────────
// Branchlet anchor points consumed by both WORLD (renders dark capsule SDFs at
// these positions) and the WEB pillar (frame polygon vertices terminate on
// these positions in Sub-item 3). Coordinate space: UV [0..1].
//
// MUST stay byte-for-byte in sync with `ArachneState.branchAnchors` in
// `ArachneState.swift`. `ArachneBranchAnchorsTests` regression-locks the sync
// by string-searching this file for the same float pairs.
//
// Positions chosen to give an irregular distribution near the screen edges
// (avoiding the corners — anchors deep in corners read as forced).
constant float2 kBranchAnchors[6] = {
    float2(0.18, 0.22),  // upper-left
    float2(0.82, 0.18),  // upper-right (slightly higher)
    float2(0.92, 0.55),  // right-mid
    float2(0.78, 0.84),  // lower-right
    float2(0.20, 0.78),  // lower-left
    float2(0.10, 0.50)   // left-mid
};

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

    // ── V.7.7C.2 §5.9: branchlet anchor twigs ─────────────────────────────────
    // Six small dark line segments at kBranchAnchors[i], each 0.05 UV long and
    // pointing roughly inward (toward screen centre). The WEB pillar's frame
    // polygon (Sub-item 3) terminates on these positions, so the twigs need to
    // read as small dark line segments the polygon vertices clearly attach to.
    // Slightly warmer tint than the trunk silhouettes — warmer = "closer to the
    // web", per ref 11. Same line-segment SDF pattern as the trunks above.
    for (int i = 0; i < 6; i++) {
        float2 ba  = kBranchAnchors[i];
        float2 inward = normalize(float2(0.5) - ba);
        float2 bb  = ba + inward * 0.05;
        float2 dir = bb - ba;
        float2 pa  = uv - ba;
        float  tc  = saturate(dot(pa, dir) / max(dot(dir, dir), 1e-6));
        float  bd  = length(pa - dir * tc);
        float  br  = mix(0.005, 0.002, tc);  // tapers root → tip
        float  cov = smoothstep(br + 0.0015, br - 0.0015, bd);
        float3 twigCol = mix(atmDark, atmMid, 0.15) * 0.5;
        col = mix(col, twigCol, cov * 0.8);
    }

    return col;
}

// ── V.7.7C.3 / D-095 — polygon-from-branchAnchors helpers ────────────────────
//
// Decode the polygon anchor indices packed by `ArachneState.packPolygonAnchors`
// into `webs[0].rng_seed`. Layout: bits [0..3] = count (0–6), bits [4..7] =
// anchors[0], bits [8..11] = anchors[1], …, bits [24..27] = anchors[5]. Bits
// [28..31] reserved.
//
// Returns the count (0–6); fills `outPoly` (in UV space, 6 entries — unused
// slots are zeroed). Count=0 signals "no polygon — fall back to circular
// spoke tips" so V.7.5 callers (e.g., `drawBackgroundWeb`) keep working.
static int decodePolygonAnchors(uint packed, thread float2 *outPoly) {
    int count = int(packed & 0xFu);
    if (count <= 0 || count > 6) {
        for (int i = 0; i < 6; i++) outPoly[i] = float2(0.0);
        return 0;
    }
    for (int i = 0; i < 6; i++) {
        if (i < count) {
            int idx = int((packed >> (4u + uint(i) * 4u)) & 0xFu);
            if (idx < 0) idx = 0;
            if (idx > 5) idx = 5;
            outPoly[i] = kBranchAnchors[idx];
        } else {
            outPoly[i] = float2(0.0);
        }
    }
    return count;
}

// Ray-polygon perimeter intersection. `origin` and `polyV` share UV space;
// `dir` is unit. Returns hit position relative to origin (hub-local). Falls
// back to `dir × fallbackRadius` if no edge is hit (degenerate case).
static float2 rayPolygonHit(
    float2 origin,
    float2 dir,
    thread const float2 *polyV,
    int polyCount,
    float fallbackRadius
) {
    if (polyCount < 3) return dir * fallbackRadius;
    float bestT = 1e6;
    float2 bestHit = dir * fallbackRadius;
    for (int e = 0; e < polyCount; e++) {
        int e2 = (e + 1) % polyCount;
        float2 a = polyV[e]  - origin;
        float2 b = polyV[e2] - origin;
        float2 ab = b - a;
        float denom = dir.x * ab.y - dir.y * ab.x;
        if (abs(denom) < 1e-6) continue;          // parallel
        float t = (a.x * ab.y - a.y * ab.x) / denom;
        float s = (a.x * dir.y - a.y * dir.x) / denom;
        if (t > 0.0 && s >= 0.0 && s <= 1.0 && t < bestT) {
            bestT = t;
            bestHit = dir * t;
        }
    }
    return bestHit;
}

// Find polygon edge with the largest angular gap around the centroid — the
// "bridge" thread per §5.3. Returns index of the first vertex of that edge.
// Replicates `ArachneState.largestAngularGap` so the shader can render the
// bridge-first stage-0 reveal without an extra round-trip.
static int findBridgeIndex(thread const float2 *polyV, int polyCount) {
    if (polyCount < 2) return 0;
    float2 centroid = float2(0.0);
    for (int i = 0; i < polyCount; i++) centroid += polyV[i];
    centroid /= float(polyCount);
    int bridgeIdx = 0;
    float maxGap = -1.0;
    for (int i = 0; i < polyCount; i++) {
        int next = (i + 1) % polyCount;
        float2 cur = polyV[i]  - centroid;
        float2 nxt = polyV[next] - centroid;
        float aCur = atan2(cur.y, cur.x);
        float aNxt = atan2(nxt.y, nxt.x);
        float gap = aNxt - aCur;
        if (gap < 0.0) gap += 2.0 * M_PI_F;
        if (gap > maxGap) {
            maxGap = gap;
            bridgeIdx = i;
        }
    }
    return bridgeIdx;
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
//
// V.7.7C.3 / D-095 follow-up parameters:
//   polyCount    — 0 to fall back to V.7.5 circular tips; 3–6 to clip spokes
//                  against the irregular `branchAnchors[]` polygon and use
//                  polyV as frame thread vertices.
//   polyV        — polygon vertices in UV space (count entries, rest zero).

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
    float  kSag,
    int                       polyCount,
    thread const float2      *polyV
) {
    ArachneWebResult result;
    result.strandCov    = 0.0;
    result.dropCov      = 0.0;
    result.strandTangent = float2(1.0, 0.0); // default: horizontal (hub fallback)
    result.dropVec      = float2(0.0, 0.0);
    result.dropRadius   = 0.0035;

    // ── §4.1 macro: web silhouette + elliptical per-web variation ─────────────
    // Transforms pRel into a squashed frame; rest of evaluation uses squashed coords.
    //
    // V.7.7C.3 / D-095 follow-up: polygon mode bypasses the squash — the
    // irregular `branchAnchors`-derived polygon already provides per-segment
    // shape variation, so a per-web elliptical squash on top reads as a
    // duplicated source of irregularity. Fall back to V.7.5 squash only when
    // polyCount < 3.
    float2 pRel0  = uv - hubUV;
    float2 pRel;
    if (polyCount >= 3) {
        pRel = pRel0;     // polygon defines silhouette; no squash
    } else {
        float2 sqDir  = float2(cos(aspectAngle), sin(aspectAngle));
        float2 sqPerp = float2(-sqDir.y, sqDir.x);
        float2 pLocal = float2(dot(pRel0, sqDir), dot(pRel0, sqPerp));
        pLocal *= float2(aspectX, 1.0 / aspectX);
        pRel = pLocal.x * sqDir + pLocal.y * sqPerp;
    }

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

    // Pre-compute ALL spoke tip positions in alternating-pair order. Used by
    // the V.7.5 fallback frame polygon block; in V.7.7C.3 polygon mode the
    // frame polygon vertices come from `polyV` instead (see frame block).
    // Either way, spoke tips terminate at the polygon perimeter when
    // polyCount ≥ 3 (`rayPolygonHit`) — this gives radials variable lengths
    // along an irregular silhouette per §5.3.
    int    nTips = min(spokeCount, 17);
    float2 tipPos[17];
    for (int ti = 0; ti < nTips; ti++) {
        int halfNt = spokeCount / 2;
        int revIt  = (ti % 2 == 0) ? (ti / 2) : (ti / 2 + halfNt);
        int it     = revIt % spokeCount;
        float jitT = (arachHash(seed + uint(it) * 7u) - 0.5) * baseStep * 0.44;
        float angT = rotAngle + float(it) * baseStep + jitT;
        float2 dir = float2(cos(angT), sin(angT));
        tipPos[ti] = (polyCount >= 3)
                   ? rayPolygonHit(hubUV, dir, polyV, polyCount, webR)
                   : webR * dir;
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

            // V.7.7C.3: spoke length clipped to polygon perimeter (or webR
            // fallback). Keeps the parabolic sag formulation in V.7.5 form
            // for circular fallback (`tProj × webR × d`); polygon mode
            // parameterises along the actual spoke length (`tProj × spokeTip`).
            float2 spokeTip  = (polyCount >= 3)
                             ? rayPolygonHit(hubUV, d, polyV, polyCount, webR)
                             : webR * d;
            float  spokeLen2 = max(length(spokeTip), 1e-5);
            float  tProj     = saturate(dot(tRel, d) / spokeLen2);
            float  gravityW  = mix(0.4, 1.0, max(0.0, sin(spAng)));
            float  sagDisp   = sagAmount * 4.0 * tProj * (1.0 - tProj) * gravityW;
            float2 spokePt   = tProj * spokeTip + float2(0.0, sagDisp);
            float  spDist    = length(tRel - spokePt);
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

    // ── Frame thread polygon — segment-by-segment reveal during stage 0 ──────
    //
    // V.7.7C.3 / D-095 follow-up: polygon mode replaces the V.7.5 alternating-
    // pair-cross-connections form (which read as a regular oval at full reveal
    // — user feedback on session 2026-05-08T17-01-15Z) with the irregular
    // 4–6-vertex `branchAnchors` polygon §5.3 prescribes. Edges connect
    // adjacent polyV[i] → polyV[(i+1) % polyCount] in angular order; the
    // bridge thread (largest angular gap) reveals first in stage 0, with
    // remaining edges revealed sequentially around the perimeter.
    //
    // V.7.5 fallback path preserved bytewise — still uses tipPos[] in
    // alternating-pair order with sequential edge reveal.
    int  frameVCount;
    int  bridgeIdx;
    float2 frameV[17];
    if (polyCount >= 3) {
        frameVCount = polyCount;
        for (int i = 0; i < polyCount; i++) frameV[i] = polyV[i] - hubUV;  // hub-local
        bridgeIdx = findBridgeIndex(polyV, polyCount);
    } else {
        frameVCount = nTips;
        for (int i = 0; i < nTips; i++) frameV[i] = tipPos[i];              // already hub-local
        bridgeIdx = 0;  // V.7.5 fallback: alternating-pair already places bridge first
    }

    int  nFrameSegs;
    bool closeFrame;
    if (stage == 0u) {
        nFrameSegs = clamp(int(progress * float(frameVCount + 1)), 0, frameVCount);
        closeFrame = false;
    } else {
        nFrameSegs = frameVCount;
        closeFrame = true;
    }
    float minFrameDist = 1e6;
    // V.7.7C.3: lower the radius gate to 0.30 in polygon mode (irregular
    // polygons can have edges close to the hub on short sides). V.7.5
    // fallback keeps the original 0.70 threshold (regular oval).
    float frameRadiusGate = (polyCount >= 3) ? webR * 0.30 : webR * 0.70;
    if (frameVCount >= 2 && rT >= frameRadiusGate) {
        for (int fi = 0; fi < nFrameSegs; fi++) {
            // Bridge-first reveal in polygon mode; sequential in fallback.
            int edgeIdx = (polyCount >= 3)
                        ? ((bridgeIdx + fi) % frameVCount)
                        : fi;
            int fj = (edgeIdx + 1) % frameVCount;
            if (!closeFrame && fi + 1 >= nFrameSegs) continue;  // open polygon during stage 0
            float2 ta = frameV[edgeIdx];
            float2 tb = frameV[fj];
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

    // Precompute spoke directions, gravity weights, and (V.7.7C.3) polygon-
    // clipped spoke tip positions for all visible spokes — reused across all
    // N_RINGS ring iterations to avoid redundant trig + ray-polygon casts.
    int   nSpk = min(nVisible, 17);
    float2 sdDir[17];
    float  sdGrav[17];
    float2 sdTip[17];   // V.7.7C.3 — polygon-clipped tip (or webR × sdDir fallback)
    for (int si = 0; si < nSpk; si++) {
        float jitS = (arachHash(seed + uint(si) * 7u) - 0.5) * baseStep * 0.44;
        float angS = rotAngle + float(si) * baseStep + jitS;
        sdDir[si]  = float2(cos(angS), sin(angS));
        sdGrav[si] = mix(0.4, 1.0, max(0.0, sin(angS)));
        sdTip[si]  = (polyCount >= 3)
                   ? rayPolygonHit(hubUV, sdDir[si], polyV, polyCount, webR)
                   : webR * sdDir[si];
    }

    float spirW   = 0.0013;
    float spirSig = max(webR * 0.009, 1e-4);

    // V.7.7C.3 / D-095 — per-chord visibility gate. Pre-V.7.7C.3 the gate was
    // per-ring (`k / N_RINGS <= progress`) so an entire ring's chord segments
    // (with drops) appeared at once as a complete oval — the user reported
    // "one complete oval after another" on the 2026-05-08T17-01-15Z manual
    // smoke. Per-chord gating reveals one chord segment at a time, sweeping
    // outside-in by ring and clockwise-by-spoke within each ring — the
    // "connections from one spoke to the next" signature §5.6 calls for.
    int totalChordCount = N_RINGS * nSpk;
    int visibleChordCount = (stage >= 3u)
                            ? totalChordCount
                            : ((stage == 2u)
                               ? int(progress * float(totalChordCount))
                               : 0);

    if (rT >= r_inner * 0.78 && rT <= r_outer + spirW * 2.0 && nSpk >= 2 &&
        visibleChordCount > 0) {
        for (int k = 0; k < N_RINGS; k++) {
            // Outside-in: ring 0 is outermost (first placed by spider).
            float ringR = r_outer * exp(logAlpha * float(k));

            // Per-chord visibility (V.7.7C.3): if no chords of this ring are
            // yet visible, skip the entire ring; if all of this ring's chords
            // are visible, fall through to the spoke loop normally; otherwise
            // the inner loop self-bounds via `globalChordIdx`.
            if (k * nSpk >= visibleChordCount) break;

            // V.7.5 fallback (circular rings): radius early exit. In V.7.7C.3
            // polygon mode the chord positions follow the irregular polygon
            // shape (no concentric-ring assumption), so the early exit is
            // skipped — the ~84-chord cost stays well within budget.
            if (polyCount < 3) {
                float ringGuard = ringR * baseStep * 1.3 + spirW;
                if (rT < ringR - ringGuard || rT > ringR + ringGuard) continue;
            }

            // Parabolic sag at this ring radius (same formula as spoke SDF).
            float tProjR  = ringR / webR;
            float sagScale = sagAmount * 4.0 * tProjR * (1.0 - tProjR);

            // Per-ring drop spacing (slight per-ring variation for organic feel).
            float spacingUV = 0.0037 + arachHash(seed + 0x1337u + uint(k) * 31u) * 0.0019;

            // V.7.7C.3 / D-095 follow-up: in polygon mode each chord endpoint
            // is `spokeTip × fracR` (along the polygon-clipped spoke at the
            // current ring fraction). Inner rings naturally inherit the
            // irregular polygon silhouette. V.7.5 fallback retains
            // `pI = ringR × sdDir`.
            float fracR = ringR / r_outer;

            for (int si = 0; si < nSpk; si++) {
                // Per-chord visibility gate (V.7.7C.3).
                int globalChordIdx = k * nSpk + si;
                if (globalChordIdx >= visibleChordCount) break;

                // Sequential spoke order — adjacent si/sj pairs form polygon edges.
                int sj = (si + 1) % spokeCount;
                if (sj >= nSpk) continue;  // guard for partial-reveal stages

                float2 pI, pJ;
                if (polyCount >= 3) {
                    pI = sdTip[si] * fracR + float2(0.0, sagScale * sdGrav[si]);
                    pJ = sdTip[sj] * fracR + float2(0.0, sagScale * sdGrav[sj]);
                } else {
                    pI = ringR * sdDir[si] + float2(0.0, sagScale * sdGrav[si]);
                    pJ = ringR * sdDir[sj] + float2(0.0, sagScale * sdGrav[sj]);
                }

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

    // V.7.7C.3 / D-095 follow-up: drawBackgroundWeb is dead-reference code
    // (not dispatched); pass polyCount=0 so it falls back to the V.7.5
    // circular-spoke-tip path if anyone ever revives it.
    float2 bgPoly[6] = { float2(0.0), float2(0.0), float2(0.0),
                          float2(0.0), float2(0.0), float2(0.0) };
    ArachneWebResult wr = arachneEvalWeb(
        uv, hubUV, webRBg, rotBg, 5.5, seed,
        3u, 1.0,
        arachSpokeCount(seed), arachAspect(seed),
        arachAspectAngle(seed), kSagBg,
        0, bgPoly
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

    // ── Foreground hero web (V.7.7C.2 / D-095): build-aware via webs[0] Row 5 ──
    //
    // V.7.7D and earlier hard-pinned this block at stage=3u, progress=1.0 — the
    // foreground always rendered fully built. V.7.7C.2 retires that for the
    // single-foreground build-cycle signature: the slot reads `webs[0]`'s Row 5
    // BuildState (audio-modulated TIME, ARACHNE_V8_DESIGN.md §5.2 60 s cycle)
    // and the existing arachneEvalWeb / drop blocks render the build-aware
    // composition unchanged — frame polygon at stage 0, alternating-pair
    // radials at stage 1, INWARD chord-segment spiral at stage 2, settle at
    // stage ≥ 3. Hub knot + chord-spiral SDFs are byte-identical to V.7.7D
    // (Failed Approach #34 + §5.4 hub-as-fbm-knot still hold).
    //
    // Row 5 → legacy (stage, progress) mapping:
    //   .frame    (0) → stage=0u, progress=frame_progress
    //   .radial   (1) → stage=1u, progress=radial_packed / radialCount_cpu
    //   .spiral   (2) → stage=2u, progress=spiral_packed / spiralChordsTotal_cpu
    //   ≥ .stable (3) → stage=3u, progress=1.0  (.evicting clamped to .stable)
    //
    // Normalisation constants below mirror CPU defaults (`radialCount = 13`,
    // `spiralRevolutions × radialCount = 8 × 13 = 104`); shader-side
    // `arachSpokeCount(ancSeed)` may differ from CPU's `radialCount` by ±2,
    // which produces a visually negligible ±2-spoke lead/lag at the radial
    // boundary. Acceptable for V.7.7C.2 — see D-095 carry-forward.
    //
    // Hub UV stays at the hardcoded V.7.5 anchor (0.42, 0.40); the seedInitial
    // hub_x/hub_y on webs[0] are intentionally ignored for this slot. The
    // hardcoded values are what M7 reviews against, so retaining them
    // preserves cert-review comparability.
    //
    // Per-chord drop accretion + anchor-blob discs at polygon vertices +
    // background-web migration crossfade visual are deferred (see D-095).
    {
        uint   ancSeed = 1984u;
        float2 ancHub  = float2(0.42, 0.40) + arachHubJitter(ancSeed);

        // V.7.7C.2 / D-095 — derive (stage, progress) from webs[0] Row 5.
        constexpr float kRadialCountCPUDefault = 13.0;
        constexpr float kSpiralChordsTotalCPUDefault = 104.0;
        float buildStageF = clamp(webs[0].build_stage, 0.0, 4.0);
        uint  fgStage;
        float fgProgress;
        if (buildStageF < 0.5) {
            fgStage    = 0u;
            fgProgress = saturate(webs[0].frame_progress);
        } else if (buildStageF < 1.5) {
            fgStage    = 1u;
            fgProgress = saturate(webs[0].radial_packed / kRadialCountCPUDefault);
        } else if (buildStageF < 2.5) {
            fgStage    = 2u;
            fgProgress = saturate(webs[0].spiral_packed / kSpiralChordsTotalCPUDefault);
        } else {
            fgStage    = 3u;
            fgProgress = 1.0;
        }

        // V.7.7C.3 / D-095 follow-up — decode polygon anchors from
        // webs[0].rng_seed (packed by ArachneState.packPolygonAnchors). The
        // resulting polyV[] (UV space) drives polygon-aware spoke clipping +
        // irregular frame thread inside arachneEvalWeb. polyCount=0 falls
        // back to V.7.5 circular tips for safety (e.g., uninitialised state).
        float2 fgPoly[6];
        int    fgPolyCount = decodePolygonAnchors(webs[0].rng_seed, fgPoly);

        ArachneWebResult wr = arachneEvalWeb(
            vibUV, ancHub, 0.22, 0.30, 6.0, ancSeed,
            fgStage, fgProgress,
            arachSpokeCount(ancSeed), arachAspect(ancSeed),
            arachAspectAngle(ancSeed), arachKSag(ancSeed),
            fgPolyCount, fgPoly
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

    // ── V.7.5 pool webs RETIRED (V.7.7C.3 / D-095 follow-up) ─────────────────
    //
    // Pre-V.7.7C.3 the pool loop iterated webs[1..3] (V.7.5 spawn/eviction)
    // as "background depth context". Live LTYL session 2026-05-08T17-01-15Z
    // showed the user perceived this as "full webs flash on and fade away
    // throughout playback ... new webs form over the central web being spun"
    // — the V.7.5 churn competed with the foreground build, not framing it.
    // V.7.7C.3 disables pool web rendering entirely; only the build-aware
    // foreground hero (above) renders. CPU-side V.7.5 spawn/eviction state
    // continues to advance harmlessly (preserved so existing ArachneState
    // unit tests still cover the spawn machinery), but no slot reaches the
    // shader after this commit. The 1–2 saturated background webs spec'd
    // by §5.12 + ArachneBackgroundWeb CPU array remain a V.7.10 follow-up
    // (would require a side buffer at slot 8).
    //
    // The empty loop body is retained as a structural marker for the future
    // §5.12 background-web flush; if you remove it, also remove the loop
    // header.
    for (int wi = 1; wi < 1; wi++) {
        ArachneWebGPU w = webs[wi];
        if (w.is_alive == 0u || w.opacity < 0.015) continue;

        float2 hubUV = float2((w.hub_x + 1.0) * 0.5, (1.0 - w.hub_y) * 0.5)
                     + arachHubJitter(w.rng_seed);
        float  webR  = w.radius * 0.5;

        // V.7.7C.3 / D-095 follow-up: empty-loop call site — polygon mode
        // disabled (polyCount=0) so the dead-reference path stays at V.7.5
        // circular geometry for any future revival.
        float2 poolPoly[6] = { float2(0.0), float2(0.0), float2(0.0),
                                float2(0.0), float2(0.0), float2(0.0) };
        ArachneWebResult wr = arachneEvalWeb(
            vibUV, hubUV, webR, w.rot_angle, w.spiral_revolutions,
            w.rng_seed, w.stage, w.progress,
            arachSpokeCount(w.rng_seed), arachAspect(w.rng_seed),
            arachAspectAngle(w.rng_seed), arachKSag(w.rng_seed),
            0, poolPoly
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

