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

/// Same bit-mixing scheme as `arachHash` but returns the scrambled uint
/// instead of a float. V.7.7C.5.1 (D-100 follow-up) uses this to derive a
/// uniform-random per-segment macro-shape seed from `webs[0].rng_seed`,
/// whose bits 0–27 carry the polygon-anchor packing (V.7.7C.3 — see
/// `ArachneState.packPolygonAnchors`) and would otherwise read as a
/// structured non-uniform value when fed to `arachSpokeCount` etc.
static uint arachHashU32(uint seed) {
    seed = (seed ^ 61u) ^ (seed >> 16u);
    seed *= 9u;
    seed ^= (seed >> 4u);
    seed *= 0x27d4eb2du;
    seed ^= (seed >> 15u);
    return seed;
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

// ── kBranchAnchors[6] — polygon vertex source (V.7.7C.5 / D-100) ─────────────
// Branchlet anchor points consumed by the WEB pillar's polygon-from-anchors
// path: `decodePolygonAnchors(webs[0].rng_seed, ...)` looks up indices in this
// array; `arachneEvalWeb` ray-clips spoke tips against the polygon perimeter
// and renders frame thread polygon edges between adjacent vertices. The §4
// atmospheric reframe (D-100) retired the WORLD-side capsule-twig SDF loop
// that previously also consumed these positions; the constants stay only as
// the polygon source.
//
// MUST stay byte-for-byte in sync with `ArachneState.branchAnchors` in
// `ArachneState.swift`. `ArachneBranchAnchorsTests` regression-locks the sync
// by string-searching this file for the same float pairs.
//
// V.7.7C.5 (D-100) update: positions moved to or just past the visible UV
// border so the WEB threads enter the canvas from outside, matching ref
// `20_macro_backlit_purple_canvas_filling_web.jpg`. All entries lie in the
// off-frame band `[-0.06, 1.06]² \ [0,1]²`. Distribution is asymmetric (no
// two opposing-edge anchors share the same vertical position), so polygons
// drawn from any 4–6-subset still read as irregular per §5.3 / Q14.
constant float2 kBranchAnchors[6] = {
    float2(-0.05, 0.05),  // upper-left, off-canvas
    float2(1.05, 0.02),   // upper-right, off-canvas (slightly higher)
    float2(1.06, 0.52),   // right, off-canvas
    float2(1.04, 0.97),   // lower-right, off-canvas
    float2(-0.04, 0.95),  // lower-left, off-canvas
    float2(-0.06, 0.48)   // left, off-canvas
};

// ── V.7.7C.5: WORLD pillar — atmospheric abstraction (D-100) ─────────────────
//
// Section 4 of `ARACHNE_V8_DESIGN.md` was rewritten 2026-05-09 after Matt's
// 2026-05-08T18-28-16Z manual smoke flagged the V.7.7B–C.4 forest framing as
// "completely devoid of value" / "the lines do not read as branches". The
// six-layer dark close-up forest (deep background + radial mist + V.7.7B
// shaft + uniform dust motes + forest floor + three near-frame branch SDFs +
// §5.9 anchor twigs loop) is retired. What remains is the §4.3 mood palette
// + two atmospheric layers (§4.2):
//   1. Sky band — full-frame `mix(botCol, topCol, ...)` gradient with
//      low-frequency fbm4 modulation; aurora ribbon at high arousal.
//   2. Volumetric atmosphere — beam-anchored fog + 1–2 mood-driven god-ray
//      light shafts + dust motes confined inside the shaft cones.
//
// References (§4.4 cross-walk): mood-palette anchors only. 06 / 16 / 15 / 20
// frame the colour signatures and atmospheric depth; the forest scenes those
// references depict are explicitly NOT the implementation target. The
// retired forest-specific references (02 / 11 / 17 / 18) remain in
// `docs/VISUAL_REFERENCES/arachne/` for V.7.10 cert-review historical
// comparison only.
//
// Audio coupling (§4.2.2):
//   - Shaft engagement gate: `f.mid_att_rel > 0.05` (lowered from V.7.7B's
//     0.10 so shafts engage on lighter music). Plumbed via the new
//     `midAttRel` parameter.
//   - Fog density inside cones: `0.15 + 0.15 × f.mid_att_rel` (range
//     0.15–0.30 — Q7 raised significantly from V.7.7B's 0.02–0.06).
//   - Shaft brightness: `0.30 × valScale` (raised from V.7.7B's
//     `0.06 × val` per Q8). Mood-driven only; no per-beat gain (atmosphere
//     is continuous, not beat-coupled — `base_zoom ≥ 2× beat_zoom` rule).
//   - Aurora ribbon (high arousal): phase-anchored to `accTime` (Failed
//     Approach #33 — drawWorld doesn't carry per-frame `beat_phase01`,
//     `accumulated_audio_time` is the silence-pause-compatible substitute).
//
// drawBackgroundWeb() (dead-reference) calls drawWorld(refractedUV, ...) for
// its Snell's-law refraction sample; it now passes 0.0 for midAttRel since
// dead-reference paths shouldn't drive shaft engagement on synthetic UVs.
//
// UV: (0,0)=top-left, (1,1)=bottom-right.
// moodRow.x = smoothedValence [-1,1], .y = smoothedArousal [-1,1],
// .z = accumulatedAudioTime (passed separately as `accTime`).

static float3 drawWorld(float2 uv, float4 moodRow, float accTime, float midAttRel) {
    float v = clamp(moodRow.x, -1.0, 1.0);
    float a = clamp(moodRow.y, -1.0, 1.0);
    float arousalNorm = saturate(0.5 + 0.5 * a);
    float valenceNorm = saturate(0.5 + 0.5 * v);

    // V.7.7C.5.1 (D-100 follow-up) — §4.3 palette pumped + audio-cycled.
    //
    // Pre-V.7.7C.5.1 spec used satScale 0.25–0.65 / valScale 0.10–0.30. Q10
    // locked this verbatim from the 2026-05-02 spec when the WORLD was the
    // six-layer forest — the muted palette read as "moody atmosphere" with
    // the forest providing compositional richness. V.7.7C.5's atmospheric
    // reframe retired the forest; the bare gradient exposed the muteness as
    // "psych ward" (Matt's 2026-05-08T22-01-07Z smoke).
    //
    // V.7.7C.5.1 pumps both ranges (sat 0.55–0.95, val 0.30–0.70) and adds
    // a slow accumulated_audio_time hue cycle on top of the valence-driven
    // base hue. Cross-preset silence anchor (Q11) keyed on raw mood product
    // so deep-negative mood collapse → black still fires; vivid baseline
    // applies everywhere else.
    //
    // Silence anchor (Q11): pure black when mood signal collapses to deep
    // negative quadrant (a, v both strongly negative). Preserves cross-preset
    // convention (ref 08). Fires when arousalNorm × valenceNorm < 0.05 → both
    // a < ~-0.5 AND v < ~-0.5 simultaneously.
    if (arousalNorm * valenceNorm < 0.05) return float3(0.0);

    // Mood-biased base hues (Q10 axis: cool teal → warm amber by valence).
    float topHueBase = mix(0.62, 0.05, valenceNorm);
    float botHueBase = mix(0.58, 0.08, valenceNorm);

    // Audio-time hue cycle (~25 s period at accTime rate 0.04). ±0.15 hue
    // swing keeps the cycle psychedelic but doesn't dominate the mood
    // mapping. Top/bottom phase-offset by 0.5 cycles so the gradient never
    // collapses to a single hue. Pauses at silence (FA #33 compliance —
    // accTime is the FA-#33-safe substitute when beat_phase01 isn't carried).
    float cycle = accTime * 0.04;
    float topHue = fract(topHueBase + sin(cycle * 6.28318) * 0.15);
    float botHue = fract(botHueBase + cos(cycle * 6.28318 + 3.14159) * 0.15);

    // Pumped saturation/value — vivid even at low arousal.
    float satScale = 0.55 + 0.40 * arousalNorm;  // 0.55–0.95
    float valScale = 0.30 + 0.40 * arousalNorm;  // 0.30–0.70

    float3 topCol  = hsv2rgb(float3(topHue, satScale, valScale * 1.2));
    float3 botCol  = hsv2rgb(float3(botHue, satScale * 0.85, valScale));
    float3 beamCol = hsv2rgb(float3(mix(0.6, 0.08, valenceNorm),
                                      saturate(satScale * 0.7),
                                      valScale * 1.4));

    // ── §4.2.1 Sky band — full frame ──────────────────────────────────────
    // Spec wording is `mix(botCol, topCol, uv.y)` with uv.y measured up; our
    // convention has top at uv.y=0 so we flip the mix factor. Low-frequency
    // fbm4 (~7% amplitude) breaks the perfectly-smooth gradient (Q2 — fills
    // the lower edge that the retired forest floor used to occupy).
    float skyT = 1.0 - uv.y;
    float skyN = fbm4(float3(uv * 1.6, 0.13)) * 0.5 + 0.5;
    float3 col = mix(botCol, topCol, skyT) * (0.93 + 0.14 * skyN);

    // Aurora ribbon — fades in at high arousal (smoothedArousal > 0.6).
    // Two-frequency sin product for ribbon-like horizontal banding,
    // phase-anchored to accTime (FA #33: drawWorld has no beat_phase01).
    // Cap at ~10% brightness lift so the aurora reads as a subtle tell, not
    // a hero element (§4.2.1).
    float arousalGate = smoothstep(0.6, 0.85, a);
    if (arousalGate > 0.001) {
        float ribbonPhase = accTime * 0.18;
        float ribbonA = sin(uv.y * 18.0 + ribbonPhase) * 0.5 + 0.5;
        float ribbonB = sin(uv.y * 7.0  - ribbonPhase * 0.7) * 0.5 + 0.5;
        col += topCol * ribbonA * ribbonB * 0.10 * arousalGate;
    }

    // ── §4.2.2 Volumetric atmosphere — sun anchors + shaft axes ──────────
    // Warm valence (v ≥ 0): primary shaft enters from upper-LEFT at ~30°
    // from vertical; secondary at ~58° engages at higher arousal (a > 0.4).
    // Cool valence (v < 0): mirror to upper-RIGHT.
    bool warmSide = (v >= 0.0);

    // Sun anchors above/outside frame (UV.y < 0 means above the visible top).
    float2 sunUV1 = warmSide ? float2(-0.15, -0.30) : float2(1.15, -0.30);
    float2 sunUV2 = warmSide ? float2(-0.05, -0.40) : float2(1.05, -0.40);

    // Shaft direction unit vectors. Measured from vertical (uv.y down):
    //   30° from vertical → (sin 30°, cos 30°) = (0.500, 0.866)
    //   58° from vertical → (sin 58°, cos 58°) = (0.848, 0.530)
    float2 dir1 = warmSide ? float2(0.5,   0.866) : float2(-0.5,   0.866);
    float2 dir2 = warmSide ? float2(0.848, 0.530) : float2(-0.848, 0.530);

    // Shaft brightness coefficient — §4.2.2 Q8: 0.30 × val (raised from
    // V.7.7B's 0.06 × val so shafts read as the dominant atmospheric light
    // source, not a faint overlay).
    float shaftBrightness = 0.30 * valScale;

    // V.7.7C.5.1 (D-100 follow-up) — engagement gate reformulated from
    // binary to floor-plus-scale. Pre-V.7.7C.5.1 used `smoothstep(0.05,
    // 0.15, midAttRel)` per spec §4.2.2 — engages only when mid is
    // sustained ABOVE AGC running average. On real AGC-warmed playlists
    // (Matt's 2026-05-08T22-01-07Z smoke: 4705-frame Arachne windows,
    // mean midAttRel ≈ -0.5, max never reached 0.05) the shaft never
    // engaged → "no light shaft appreciated".
    //
    // V.7.7C.5.1 floors engagement at 25% always-on (so shafts are always
    // part of the WORLD identity, never structurally invisible) and
    // scales to 100% on positive deviation. Visual: shafts visible at
    // baseline brightness, brightening during melody-rich passages.
    // The 25% floor combined with the 0.30 × valScale brightness
    // coefficient means a silent-music shaft contributes ~0.075 × valScale
    // — perceptible but not dominant.
    float midGate = 0.25 + 0.75 * smoothstep(-0.20, 0.10, midAttRel);

    // Primary shaft: Gaussian falloff perpendicular to axis × 1D axial noise
    // for "discrete shafts inside a cone" reading (§4.2.2 — uniform glow is
    // the wrong reading per spec wording).
    float2 d1     = uv - sunUV1;
    float  along1 = dot(d1, dir1);
    float  perp1  = length(d1 - dir1 * along1);
    const float shW = 0.20;
    float jit1   = fbm4(float3(along1 * 6.0, 0.31, 0.0)) * 0.5 + 0.5;
    float gauss1 = exp(-(perp1 * perp1) / (shW * shW));
    float fade1  = smoothstep(0.05, 0.30, along1) * smoothstep(2.2, 0.7, along1);
    float beam1  = gauss1 * (0.50 + 0.50 * jit1) * fade1;

    // Secondary shaft — engages at higher arousal.
    float arousal2 = smoothstep(0.4, 0.7, a);
    float2 d2vec   = uv - sunUV2;
    float  along2  = dot(d2vec, dir2);
    float  perp2   = length(d2vec - dir2 * along2);
    float jit2   = fbm4(float3(along2 * 7.0, 0.71, 0.0)) * 0.5 + 0.5;
    float gauss2 = exp(-(perp2 * perp2) / (shW * shW));
    float fade2  = smoothstep(0.05, 0.30, along2) * smoothstep(2.2, 0.7, along2);
    float beam2  = gauss2 * (0.50 + 0.50 * jit2) * fade2 * arousal2;

    // Combined beam intensity used as cone-anchor for fog density + dust motes.
    float beamMax = max(beam1, beam2);

    // ── Fog density — beam-anchored ──────────────────────────────────────
    // Inside shaft cones: density 0.15 + 0.15 × midAttRel (range 0.15–0.30).
    // Outside cones: thinner ambient haze at `mix(botCol, topCol, 0.5) × 0.3`.
    // Fog sits BEHIND shafts in composite — fog first, shafts on top (§4.2.2).
    float fogInsideDensity = 0.15 + 0.15 * saturate(midAttRel);
    float3 fogColInside    = mix(botCol, topCol, 0.5) * float3(1.00, 0.85, 0.65);
    float3 fogColAmbient   = mix(botCol, topCol, 0.5) * 0.3;
    float fogConeMix       = saturate(beamMax * 1.6);
    float fogDensity       = mix(0.06, fogInsideDensity, fogConeMix);
    float3 fogCol          = mix(fogColAmbient, fogColInside, fogConeMix);
    col = mix(col, fogCol, saturate(fogDensity));

    // ── Light shafts — additive on top of fog ────────────────────────────
    col += beamCol * (beam1 + beam2) * shaftBrightness * midGate;

    // ── Dust motes — caustic-concentrated inside shaft cones (§4.2.2 Q9) ─
    // Hash-lattice particle field; only rendered inside shaft cones (motes
    // outside have no key light to catch). Phase-anchored to accTime
    // (Failed Approach #33 — accTime pauses at silence; FA-#33 compliant
    // substitute when beat_phase01 isn't carried into drawWorld).
    float2 driftUV = uv * float2(44.0, 22.0)
                   + float2(accTime * 0.06, accTime * 0.03);
    float moteN     = fbm4(float3(driftUV, 0.31)) * 0.5 + 0.5;
    float moteMask  = smoothstep(0.79, 0.85, moteN);
    float moteCone  = saturate(beamMax * 2.5);
    const float moteOpacity = 0.4;
    col += beamCol * moteMask * moteCone * moteOpacity * shaftBrightness * midGate * 4.0;

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
        // V.7.7C.5.1 (D-100 follow-up) — hub coverage 1.20 → 0.70 to match
        // the dimmer silk luminescence (silkTint 0.85 → 0.55, halos halved).
        // V.7.7C.4 had pumped hub to 1.20 + silkTint to 0.85 to compensate
        // for V.7.5's deliberate dim silk; V.7.7C.5's canvas-filling foreground
        // made that bright-pumped silk dominate as toddler-scribble heavy
        // lines (Matt's 2026-05-08T22-01-07Z smoke). V.7.7C.5.1 returns the
        // silk to fine-detail weight without re-creating the V.7.5 muteness
        // problem — backdrop saturation gets the visual lift instead.
        hubCov = smoothstep(0.54, 0.43, raw) * 0.70
               * smoothstep(hubR, hubR * 0.15, rT);  // fade at exact center
        hubCov = saturate(hubCov);
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
    // V.7.7C.5.1 (D-100 follow-up) — line widths halved for canvas-filling
    // scale. At V.7.7C.4 webR=0.22 the silk read balanced; at V.7.7C.5
    // webR=0.55 the polygon scaled 2.5× but lines didn't, producing the
    // "toddler scribble" reading Matt flagged on the 2026-05-08T22-01-07Z
    // smoke. Halving brings strand weight back into proportion with the
    // canvas-filling polygon — lets density read as elaborate detail.
    float spokeW       = mix(0.0010, 0.0006, taper);
    float spokeHaloSig = max(webR * 0.008, 1e-4);
    float spokeCov     = smoothstep(spokeW + aaW, spokeW - aaW, minSpokeDist) * anchorFade;
    float spokeHalo    = exp(-minSpokeDist * minSpokeDist / (spokeHaloSig * spokeHaloSig))
                        * 0.20 * anchorFade;

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
    // V.7.7C.5.1 (D-100 follow-up) — frame thread width halved (matches spoke).
    float frameW    = mix(0.0010, 0.0006, taper);
    float frameFade = rT > webR ? exp(-(rT - webR) * 6.0) : 1.0;
    float frameCov  = smoothstep(frameW + aaW, frameW - aaW, minFrameDist) * frameFade;
    float frameHalo = exp(-minFrameDist * minFrameDist / (spokeHaloSig * spokeHaloSig))
                    * 0.11 * frameFade;

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

    // V.7.7C.5.1 (D-100 follow-up) — spiral chord width halved.
    float spirW   = 0.0007;
    float spirSig = max(webR * 0.005, 1e-4);

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
    // V.7.7C.5.1 (D-100 follow-up) — spiral halo magnitude halved.
    spirHalo = exp(-minChordDist * minChordDist / (spirSig * spirSig)) * 0.13 * inZone;

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
        // V.7.7C.5 (D-100): drawWorld signature gained a `midAttRel` parameter
        // for the §4.2.2 shaft engagement gate / fog density modulation.
        // drawBackgroundWeb is dead-reference code (not dispatched); pass 0.0
        // so a future revival doesn't drive shafts off synthetic refracted UVs.
        float3 bgSeen      = drawWorld(refractedUV, moodRow, accTime, 0.0);

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
    // V.7.7C.5 (D-100): drawWorld now takes f.mid_att_rel for §4.2.2 shaft
    // engagement gate + fog-density modulation. The atmospheric reframe
    // gives shafts the dominant visual weight (`0.30 × val`) so the gate
    // matters — silence/ambient passages collapse the shaft contribution
    // smoothly back to the fog ambient floor.
    float3 col = drawWorld(in.uv, moodRow, moodRow.z, f.mid_att_rel);
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
    // V.7.7C.5 (D-100, Q15): hub UV moved from the V.7.5/V.7.7C.4 anchor
    // (0.42, 0.40) to canvas centre (0.5, 0.5) and webR bumped from 0.22 to
    // 0.55 so the polygon spans most of the visible UV (Q15 target: ~70–85%
    // of canvas area). Combined with the off-frame `kBranchAnchors[6]`
    // positions (D-100 / Q14), the foreground hero web reads as anchored to
    // implied off-frame structures — silk threads enter the canvas from
    // outside, matching ref `20_macro_backlit_purple_canvas_filling_web.jpg`.
    // The seedInitial hub_x/hub_y on webs[0] are still intentionally ignored
    // for this slot (the hardcoded UV is what M7 reviews against), but the
    // `ArachneState.seedInitialWebs()` hub_x/hub_y/radius mirror is updated
    // to (0.0, 0.0, 1.10) so CPU/GPU state stays internally consistent.
    //
    // Per-chord drop accretion + anchor-blob discs at polygon vertices +
    // background-web migration crossfade visual are deferred (see D-095).
    {
        // V.7.7C.5.1 (D-100 follow-up) — per-segment macro-shape variation.
        //
        // Pre-V.7.7C.5.1 the foreground hero web had `ancSeed = 1984u` hardcoded,
        // so spoke count, aspect, sag, hub jitter, and per-spoke angular jitter
        // were identical every Arachne instance — Matt's 2026-05-08T22-01-07Z
        // smoke flagged this as "should the preset draw the SAME web in the SAME
        // position EVERY time?". The polygon vertex *selection* already varied
        // per segment (`ArachneState.reset()` Fisher-Yates), but macro shape
        // was locked.
        //
        // Fix: derive `ancSeed` from `webs[0].rng_seed`, which `ArachneState`
        // refreshes on each preset bind via `lcg(&rng)`. The lower 28 bits of
        // `rng_seed` carry the polygon-anchor packing (V.7.7C.3 — see
        // `packPolygonAnchors`), so a uint hash scrambles the structured bits
        // back into a uniform-random seed for the macro-shape helpers.
        //
        // FUTURE OPTIONS (deferred from V.7.7C.5.1):
        //   - Option B: per-track determinism. Plumb a track-identity hash into
        //     `ArachneState.reset(trackSeed:)` so the same track always gets
        //     the same web. Adds Swift wiring + a Renderer hook on track change.
        //   - Option C: track + session-counter perturbation. Per-track base
        //     seed gives identity; LCG step per-replay gives variant on Nth
        //     listen. Variety + association.
        // Documented in DECISIONS.md D-100 carry-forward + ENGINEERING_PLAN
        // V.7.7C.5.2 stub.
        uint   ancSeed = arachHashU32(webs[0].rng_seed ^ 0xCA51u);
        float2 ancHub  = float2(0.5, 0.5) + arachHubJitter(ancSeed);

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

        // V.7.7C.5 / D-100 (Q15): webR bumped 0.22 → 0.55 so the foreground
        // hero polygon fills the canvas. With `webR × 1.20 = 0.66`, the
        // per-pixel early-exit envelope around the hub at (0.5, 0.5) covers
        // most of the visible UV (only the ~5% corner regions outside the
        // off-frame polygon are excluded — and those are where the polygon
        // doesn't reach anyway).
        ArachneWebResult wr = arachneEvalWeb(
            vibUV, ancHub, 0.55, 0.30, 6.0, ancSeed,
            fgStage, fgProgress,
            arachSpokeCount(ancSeed), arachAspect(ancSeed),
            arachAspectAngle(ancSeed), arachKSag(ancSeed),
            fgPolyCount, fgPoly
        );

        float newStrandD   = op_blend(strandPseudo, 1.0 - wr.strandCov, 0.012);
        float newStrandCov = 1.0 - newStrandD;
        float delta        = max(0.0, newStrandCov - prevStrandCov);

        if (delta > 0.001) {
            // V.7.7C.4 / D-095 follow-up — palette enrichment.
            //
            // Pre-V.7.7C.4 the silk was deliberately faint per V.7.5 §10.1.3
            // ("drops carry 80% of visual"). Matt's 2026-05-08T18-28-16Z
            // smoke flagged the result as "color far too subtle ... no
            // visual excitement to such a slow-moving preset". V.7.7C.4
            // bumps silkTint 0.60 → 0.85, broadens hue across the mood-
            // driven palette (valence: teal → amber), couples vocal pitch
            // into hue when stem confidence ≥ 0.35 (Gossamer-style), and
            // adds a per-beat global emission pulse (the hybrid audio
            // coupling — Fix C — that keeps the build pace TIME-driven
            // while making the visible silk respond to beats).
            float2 tang2D = wr.strandTangent;

            // Mood-driven hue base: valence shifts teal (cool, 0.55) →
            // amber (warm, 0.10) along the §4.3 forest palette axis.
            float v       = clamp(moodRow.x, -1.0, 1.0);
            float moodHue = mix(0.55, 0.10, saturate(0.5 + 0.5 * v));

            // Vocal-pitch coupling — when the YIN tracker has confidence,
            // bake a hue from log2-pitch around A3 (220 Hz). Same shape
            // as Gossamer waves; mixed in by confidence.
            float vConf   = saturate(stems.vocals_pitch_confidence);
            float vHz     = max(stems.vocals_pitch_hz, 60.0);
            float vocHue  = fract(log2(vHz / 220.0) * 0.35 + 0.55);
            float hueBase = mix(moodHue, vocHue, vConf * 0.6);

            // Wider hueDrift for visible motion across the cycle.
            float3 silkBase = hsv2rgb(float3(fract(hueBase + hueDrift * 0.20),
                                              0.55, 0.85));

            // Axial highlight fires when kL grazes strand at shallow angle.
            // V.7.7C.5.1 (D-100 follow-up) — coefficient 0.6 → 0.3 to match
            // the lighter overall silk weight (line widths halved, silkTint
            // 0.85 → 0.55). The grazing-angle accent stays present but
            // doesn't dominate the strand colour.
            float axial = 1.0 + 0.3 * smoothstep(0.35, 0.05, abs(dot(tang2D, kL.xy)));

            // Per-beat global emission pulse (V.7.7C.4 Fix C). Visual
            // beat coupling without driving the build clock from beats —
            // the chord laydown still uses audio-modulated TIME (D-095
            // Decision 2 preserved), but every beat flashes the visible
            // silk so the user perceives the connection.
            //
            // V.7.7C.5 (D-100) recalibration: coefficient dropped 0.06 →
            // 0.025 to compensate for the canvas-filling foreground
            // (`webR` 0.22 → 0.55, hub at canvas centre). PresetAcceptance
            // D-037 invariant 3 (beat response ≤ 2× continuous + 1.0)
            // measures MSE across the whole frame; the V.7.7C.4 silk
            // covered ~5% of pixels and 0.06 sat just under the 1.0 floor
            // (test fixtures have `bass_att_rel = 0` so threshold
            // collapses to ≤ 1.0 MSE/pixel). At canvas-filling scale
            // ~30% of pixels respond, so the same coefficient produces
            // ~6× the MSE (1.78 measured at 0.06 in V.7.7C.5). Using
            // k² scaling, 0.025 keeps roughly the V.7.7C.4 ~3× headroom
            // (predicted MSE ≈ 0.31 vs ceiling 1.0). Per-silk-pixel lift
            // drops from 6 % → 2.5 %, but the screen-integrated pulse
            // grows ~2.5× because the silk surface is bigger — closer
            // to Matt's "less subtle" V.7.7C.4 directive once the
            // canvas-filling foreground lands.
            //
            // The CPU-side rising-edge spiral chord advance (Fix C in
            // ArachneState.advanceSpiralPhase) provides the second
            // beat-coupling channel without affecting per-pixel MSE.
            float beatPulse = max(f.beat_bass, f.beat_composite);
            float emGain    = baseEmissionGain + beatAccent + beatPulse * 0.025;

            // V.7.7C.5.1 (D-100 follow-up): silkTint 0.85 → 0.55, ambient
            // tint factor 0.40 → 0.20. Pulls silk back to fine-detail weight
            // so the elaborate canvas-filling polygon reads as detail, not
            // toddler-scribble. Matt's 2026-05-08T22-01-07Z smoke: "lines and
            // luminescence on them do not need to be so heavy". Compensated
            // by re-saturating the §4.3 backdrop palette so the visual
            // weight shifts to the WORLD pillar.
            float3 silk_col = silkBase * 0.55 * axial * emGain;
            silk_col *= kLightCol;
            silk_col += silkBase * kAmbCol * 0.20;
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

