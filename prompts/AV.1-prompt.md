# AV.1 — Aurora Veil single-column raymarch foundation

**Increment ID:** AV.1
**Status:** ⏳ Planned (design pivot + research dossier landed 2026-05-18; this prompt drives implementation)
**Authoritative design:** `docs/presets/AURORA_VEIL_DESIGN.md` (2026-05-18 amendment) + `docs/VISUAL_REFERENCES/aurora_veil/Aurora_Veil_Rendering_Architecture_Contract.md`
**Research dossier (READ FIRST):** `docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md` — load-bearing for the algorithmic recipe, 15-mode failure-mode taxonomy, and 9-question authenticity rubric.
**Reference set:** `docs/VISUAL_REFERENCES/aurora_veil/` (5 references + 1 anti-reference, amended mandatory-traits checklist)
**Engineering plan entry:** `docs/ENGINEERING_PLAN.md` → Phase AV → "Increment AV.1 — Single-ribbon foundation"
**Sibling preset (precedent):** Gossamer — direct-fragment + mv_warp; closest neighbour in the catalog for the mv_warp wiring + JSON sidecar shape

---

## The product change in one paragraph

Phosphene's catalog gains its first "canonical Milkdrop pattern" preset — a direct-fragment shader rendering an aurora over a faintly-starred night sky, wrapped by `mv_warp`'s per-vertex feedback grid for slow temporal compounding. Aurora Veil's role in the catalog is the **ambient ribbon** preset — what plays during quiet listening, low-energy passages, and the comedown after a peak. The visual signature target is real photographic aurora (green base, magenta crown, multi-ribbon depth, vertical ray striations, biological asymmetry), NOT festival-EDM neon. AV.1 lands the **single-column volumetric-raymarch foundation**: per-fragment 50-step march up an implicit vertical column sampling a clean-room MSL reimplementation of nimitz's `tri_noise_2d` (triangular domain-warped noise), per-march-step IQ-cosine palette cycling for Lawlor-Genetti height-curve stratification, running-average vertical smear, sky + sparse stars, mv_warp wired at conservative parameters. **No audio reactivity beyond silence-stable rendering.** Audio routing lands at AV.2; multi-timescale motion enrichment + M7 cert lands at AV.3.

This is Phosphene's lowest-fidelity-bar new preset on the bench. The architectural recipe is now derived from convergent prior art (nimitz Shadertoy + Lawlor & Genetti WSCG 2011 + Wittens NeverSeenTheSky), so the probability of reaching photographic fidelity is higher than the original design's 2D-ribbon approach. Your job is to clean-room reimplement the recipe in Metal MSL, verify silence renders correctly against the named reference images and the 9-question rubric, and ship a buildable green baseline that AV.2 can extend.

---

## Read these first

In this order. **The research dossier is mandatory; the rest of the materials reference it.**

1. **`docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md`** — desk-research dossier. Read end-to-end. The §1.1 algorithm exposure for `tri_noise_2d` + 50-step march + running-average smear + per-march-step palette is the load-bearing recipe; the §2.2 15-mode failure taxonomy is the anti-pattern list; the §2.3 9-question authenticity rubric is the AV.3 cert gate.
2. **`docs/presets/AURORA_VEIL_DESIGN.md`** — visual intent + trait matrix + amended §5 rendering architecture + §11 open questions. Pay attention to the 2026-05-18 amendment header + §5-LEGACY archive — the pre-amendment §5 is NOT the implementation target.
3. **`docs/VISUAL_REFERENCES/aurora_veil/AURORA_VEIL_README.md`** — per-image annotations on the 5 references + 1 anti-reference. Per-reference caveats matter (ref `02` is palette-only, not a shape reference; ref `09` is the failure mode the rendered output must NOT read as). Amended mandatory-traits checklist (2026-05-18) is the implementer-side acceptance gate.
4. **`docs/VISUAL_REFERENCES/aurora_veil/Aurora_Veil_Rendering_Architecture_Contract.md`** — pass structure, minimum viable Session-1 milestone, blockers, certification fixtures, stop conditions.
5. **`docs/VISUAL_REFERENCES/aurora_veil/0[1-4]*.jpg`** — open in a viewer; spend two minutes per image. The README annotations are your cheat sheet but the images themselves are the visual target.
6. **`docs/VISUAL_REFERENCES/aurora_veil/09_anti_neon_festival_aurora.jpg`** — the anti-reference. If your AV.1 output reads like this image, you have failed.
7. **`PhospheneEngine/Sources/Presets/Shaders/Gossamer.metal`** + **`Gossamer.json`** — closest precedent for direct-fragment + mv_warp. The `mvWarpPerFrame` / `mvWarpPerVertex` function signatures + the JSON sidecar schema are the templates to follow. AV's design doc §10 has the `id` field — Gossamer's actual sidecar uses `name`, not `id`. Match Gossamer's schema verbatim.
8. **`PhospheneEngine/Sources/Presets/PresetLoader+WarpPreamble.swift`** — the `mvWarpPreamble` defines `MVWarpPerFrame` struct + forward declarations. Skim; the two warp functions must match the declared signatures.
9. **`CLAUDE.md`** — top to bottom. Especially: Audio Data Hierarchy (continuous primary, beat accent only), Failed Approach #33 (no free-running `sin(time)` for primary motion — DOES apply to the per-step `sin()` for palette? See §AV-sin below), Failed Approach #58 (musical role articulated upfront), Failed Approach #63 (read references' README; mid-session sanity-check is side-by-side comparison vs named references), Failed Approach #64 (when iterative first-principles fixes aren't converging on a problem with known prior art, stop and do desk research — research is now done; act on it), Failed Approach #65 (do NOT negotiate away components of a working reference implementation under unverified "redundancy" arguments — the four nimitz components are all load-bearing; adopt all four).
10. **`docs/SHADER_CRAFT.md`** — §2 reference-image-first authoring. Aurora Veil is lightweight-rubric per D-067(b) so M1/M3 cascade + material count gates do NOT apply.

You do not need to read the full Phase MV history, the Arachne / Ferrofluid / Lumen Mosaic preset details, or fetch the live nimitz Shadertoy source (the algorithm exposure in the research dossier is sufficient and the Shadertoy source is CC-BY-NC-SA which prevents verbatim use anyway — clean-room reimplementation from the description is the licence-safe path).

---

## What the codebase already does (don't re-implement)

- **mv_warp pass infrastructure** is in place per D-027 (Increment MV-2). The `mvWarpPreamble` declares `MVWarpPerFrame` struct + forward declarations for `mvWarpPerFrame` / `mvWarpPerVertex`; any preset whose JSON includes `"mv_warp"` in `passes` is compiled with that preamble injected. Gossamer is the current consumer.
- **V.1 noise utility tree** (`PhospheneEngine/Sources/Presets/Shaders/Utilities/Noise/`) provides `warped_fbm`, `curl_noise`, `fbm2`, `fbm4`, `fbm8`, `hash_f01_2` — all available via the standard preset preamble. **Note:** `tri_noise_2d` is NOT in the V.1 tree. You will write it as a `static inline` helper inside `AuroraVeil.metal` (clean-room implementation; ~30 lines including the `tri` / `tri2` / `mm2` primitives).
- **V.3 IQ cosine palette** (`PhospheneEngine/Sources/Presets/Shaders/Utilities/Color/Palettes.metal`) provides `palette(t, a, b, c, d)`. **AV.1 does NOT use this directly.** The per-march-step palette in AV.1 is the inline `sin(1.0 - vec3(2.15, -0.5, 1.2) + i * 0.043)` form per the nimitz recipe — equivalent in shape to an IQ cosine palette but evaluated by march-step `i`, not by an external `t` parameter. Keep the inline form; do not refactor to a `palette()` call at AV.1 (cf. Failed Approach #65 — don't subtract from the working recipe).
- **Blue noise sampler** (`Utilities/Noise/BlueNoise.metal`) — usable for per-pixel grain if needed; AV.1 likely doesn't need it.
- **FullScreen vertex shader** (`fullscreen_vertex`) is in the standard preamble.
- **`PresetLoader.presets.count` regression test** asserts `expectedProductionPresetCount == 15`. AV.1 bumps to 16. The test catches Failed Approach #44 silent shader drops.
- **`PresetRegressionTests` golden-hash table** — add Aurora Veil entry across three fixtures.
- **`PresetAcceptanceTests` + `FidelityRubricTests`** — Aurora Veil's JSON declares `rubric_profile: lightweight` which exempts it from M1/M3 cascade gates (D-067(b)).
- **`StemFeatures.vocals_pitch_hz` + `vocals_pitch_confidence`** (MV-3c, floats 41–42) exist in the MSL preamble. AV.2 will read these; AV.1 does not.

---

## What this increment changes

### 1. New shader: `PhospheneEngine/Sources/Presets/Shaders/AuroraVeil.metal`

Single fragment function `aurora_fragment` + the two required `mv_warp` functions (`mvWarpPerFrame` / `mvWarpPerVertex`) + ~30 lines of `tri_noise_2d` clean-room helpers. **Algorithmic source: `AURORA_VEIL_RESEARCH_2026-05-18.md §1.1` — that section's pseudo-code + description is what you reimplement.**

**File header docstring (required):**

```
// AuroraVeil.metal — Direct-fragment + mv_warp ambient ribbon preset.
//
// AV.1 — Single-column volumetric raymarch foundation. Sky + sparse stars +
// one column of triangular-domain-warped noise sampled across 50 march
// steps with per-step IQ-cosine palette cycling (green base → magenta
// crown — the Lawlor-Genetti H(z) height curve) + running-average vertical
// smear. mv_warp wired at conservative parameters (decay 0.945, zoom 0.0015,
// rot 0.0008, disp amplitude 0.005 via curl_noise advection). NO audio
// reactivity at AV.1 — audio routes land at AV.2 per
// AURORA_VEIL_DESIGN.md §5.7.
//
// CLEAN-ROOM MSL reimplementation of the procedural-aurora recipe described in:
//   - nimitz, "Auroras," Shadertoy XtGGRt (2017) — triangular-noise
//     volumetric raymarch + running-average smear + per-march-step palette
//     cycling. ALGORITHM ADOPTED; CC-BY-NC-SA Shadertoy source NOT
//     incorporated. Algorithm is reimplemented from the published
//     descriptions in docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md §1.1
//     + Roy Theunissen's algorithm breakdown (cited there).
//   - Lawlor & Genetti, "Interactive Volume Rendering Aurora on the GPU"
//     (WSCG 2011) — height-curve × 2D flux-map factorization (the per-
//     march-step sin() palette IS the Lawlor H(z) curve).
//
// Authoritative design: docs/presets/AURORA_VEIL_DESIGN.md §5 (amended
//                        2026-05-18).
// Research dossier: docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md.
// Architecture contract: docs/VISUAL_REFERENCES/aurora_veil/
//                        Aurora_Veil_Rendering_Architecture_Contract.md.
// Reference set: docs/VISUAL_REFERENCES/aurora_veil/ (4 must-pass + anti-ref).
//
// Anti-reference: 09_anti_neon_festival_aurora.jpg. The rendered output
// must NOT read like that image — pure-saturation neon, no green base,
// no vertical stratification, kinetic ribbons converging to a focal
// point. If it does, the preset is uncertified by definition.
//
// Rubric profile: lightweight (D-067(b)) — emission-only direct
// fragment, exempt from M1 detail cascade and M3 material count gates.
// L1-L4 ladder applies. 9-question authenticity rubric in
// AURORA_VEIL_RESEARCH_2026-05-18.md §2.3 is the AV.3 cert gate.
```

**`tri_noise_2d` clean-room implementation.** Reproduce the algorithm described in research dossier §1.1 — the named load-bearing elements are (a) triangular waveform `tri()`, (b) 2D triangle noise `tri2()`, (c) five iterations of domain-warped noise with per-octave rotation `mm2(time * spd)`, (d) final return `clamp(1.0 / pow(rz * 29.0, 1.3), 0, 0.55)`. **Do not substitute Perlin / fBM for the triangular noise** (Failure Mode #8 + Failed Approach #65 — the triangular waveform IS what gives aurora its sharp edges; substituting another noise destroys the visual signature). The MSL implementation is straightforward: `static inline float tri(float x)`, `static inline float2 tri2(float2 p)`, `static inline float2x2 mm2(float a)`, `static inline float tri_noise_2d(float2 p, float spd)`. ~30 lines.

**`aurora_fragment` body.** Three layers, back to front, per amended §5.2:

1. **Sky.** `mix(topColor, bottomColor, uv.y)` with `topColor = (0.005, 0.005, 0.02)`, `bottomColor = (0.01, 0.015, 0.04)`. Stars: `hash_f01_2(uv * 800) > 0.997` thresholded pinpoints, brightness varied by a secondary hash.
2. **Aurora raymarch.** 50 steps. At each step `i`, compute polynomial `pt = 0.8 + pow(float(i), 1.4) * 0.002`, sample `rzt = tri_noise_2d(float2(uv.x, pt), 0.06)`, compute `col2 = (sin(1.0 - float3(2.15, -0.5, 1.2) + float(i) * 0.043) * 0.5 + 0.5) * rzt`, update `avgCol = mix(avgCol, float4(col2, rzt), 0.5)`, accumulate `col += avgCol * exp2(-float(i) * 0.065 - 2.5) * smoothstep(0.0, 5.0, float(i))`. Final `col.rgb * 1.8`.
3. **Composite.** `final = sky + col.rgb`. Additive.

**`mvWarpPerFrame`:**

```metal
MVWarpPerFrame mvWarpPerFrame(constant FeatureVector& f,
                              constant StemFeatures&  stems,
                              constant SceneUniforms& s) {
    MVWarpPerFrame pf;
    pf.cx = 0.0; pf.cy = 0.0; pf.dx = 0.0; pf.dy = 0.0;
    pf.sx = 1.0; pf.sy = 1.0; pf.warp = 0.0;
    pf.zoom  = 1.0 + 0.0015;
    pf.rot   = 0.0008;  // AV.1: no valence coupling; that lands at AV.2.
    pf.decay = 0.945;
    pf.q1 = 0.0; pf.q2 = 0.0; pf.q3 = 0.0; pf.q4 = 0.0;
    pf.q5 = 0.0; pf.q6 = 0.0; pf.q7 = 0.0; pf.q8 = 0.0;
    return pf;
}
```

**`mvWarpPerVertex`:**

```metal
float2 mvWarpPerVertex(float2 uv, float rad, float ang,
                       thread const MVWarpPerFrame& pf,
                       constant FeatureVector& f,
                       constant StemFeatures& stems) {
    float2 centre = float2(0.5, 0.5);
    float2 p      = uv - centre;
    float  zoomAmt = 1.0 / max(pf.zoom, 0.001);
    float2 zoomed  = p * zoomAmt + centre;
    // Curl-noise advection for vortical motion character (NeverSeenTheSky
    // motion reference; mimicked at fragment-shader cost via curl_noise).
    float2 disp = curl_noise(float3(uv * 2.0, /* time */ s.audioTime * 0.1)).xy * 0.005;
    return zoomed + disp;
}
```

(`SceneUniforms` is available in mv_warp presets via the preamble; check the existing field name for audio time — likely `sceneParamsA.x`.)

**Audio inputs are ignored at AV.1** (don't reference `f.bass_att_rel` / `stems.*` etc.). The fragment renders a silence-stable scene. Silence rendering must produce a visible, drifting aurora column with sparse stars on a dark sky — the L1 "form complexity ≥ 2 at silence" rubric gate (sky + aurora + stars = 3 visual layers).

### 2. New JSON sidecar: `PhospheneEngine/Sources/Presets/Shaders/AuroraVeil.json`

Match `Gossamer.json`'s schema verbatim. Critical fields:

- `"name": "Aurora Veil"` (matches descriptor; design doc's `"id"` is wrong).
- `"family": "fluid"` (per design §1; if the Swift `PresetCategory` enum rejects, see Open Question §AV-fam).
- `"passes": ["mv_warp"]`.
- `"fragment_function": "aurora_fragment"`.
- `"vertex_function": "fullscreen_vertex"`.
- `"beat_source": "composite"` (AV.1 doesn't read beats but the field is required).
- `"decay": 0.945`.
- `"stem_affinity"`: `{"vocals": "ribbon_hue", "drums": "curtain_kink", "bass": "brightness_breath", "other": null}`. AV.1 doesn't consume these; they're documentation for the AV.2 author.
- `"section_suitability": ["ambient", "comedown", "bridge"]`.
- `"complexity_cost": {"tier1": 4.0, "tier2": 1.7}` per design §7.
- `"certified": false`.
- `"rubric_profile": "lightweight"` — load-bearing for the rubric harness to apply L1-L4 instead of full M1-M3.

### 3. New silence test: `PhospheneEngine/Tests/PhospheneEngineTests/Presets/AuroraVeilSilenceTest.swift`

Render Aurora Veil at the silence fixture (`FeatureVector()` zero-init, `StemFeatures.zero`) and assert:

1. **Non-black output.** Mean luma > a small threshold (e.g. 0.005). Sky gradient + stars + the dimmed-but-present aurora column must produce above-zero output.
2. **Vertically-stratified colour.** Sample the rendered frame at three altitudes (e.g. `y = 0.2`, `y = 0.5`, `y = 0.8`) along a vertical slice in the brightest column-region; assert the hue at low-y is green-dominant (R < G, B < G) and the hue at high-y has more magenta content than at low-y (R or B at high-y > R or B at low-y). This is the Lawlor stratification check.
3. **Form complexity ≥ 2 at silence.** Coarse heuristic: the sky band (top 20 %) has non-zero luma gradient; the aurora region (middle 60 %) has non-zero local max; the bottom 20 % is darker than the middle. Three distinct visual structures present.

Use `MetalContext()` + manual fragment-pipeline dispatch the same way `PresetAcceptanceTests` + `PresetRegressionTests` do. Extract a shared helper if it makes the test cleaner.

### 4. Update preset-count regression: bump `expectedProductionPresetCount` 15 → 16

Single-line change in `PhospheneEngine/Tests/PhospheneEngineTests/Presets/PresetLoaderCompileFailureTest.swift`. Catches Failed Approach #44 silent shader drops.

### 5. Add `PresetRegressionTests` entry for Aurora Veil

Run `UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine --filter "Print golden hashes"`, paste the printed `"Aurora Veil": (steady: ..., beatHeavy: ..., quiet: ...)` line into the `goldenPresetHashes` table. Add a comment block above the entry: "AV.1 — no audio reactivity, so all three hashes are expected to be identical or very close (within 8-bit hamming threshold). Audio-driven drift lands at AV.2."

### 6. Update `PresetVisualReviewTests` argument list to include "Aurora Veil"

The `arguments:` array on `renderPresetVisualReview` (currently `["Arachne", "Gossamer", "Volumetric Lithograph", "Lumen Mosaic"]`) gains `"Aurora Veil"`. The existing 3-fixture flow (silence / mid / beat) is sufficient for AV.1's silence-only verification. Output PNGs land in `/tmp/phosphene_visual/<ISO8601>/Aurora_Veil_{silence,mid,beat}.png`.

---

## Done when

- [ ] `PhospheneEngine/Sources/Presets/Shaders/AuroraVeil.metal` exists with `aurora_fragment` + `mvWarpPerFrame` + `mvWarpPerVertex` + the `tri_noise_2d` clean-room helpers. Compiles cleanly (no silent drops).
- [ ] `PhospheneEngine/Sources/Presets/Shaders/AuroraVeil.json` exists with the full Gossamer-style schema, `rubric_profile: lightweight`, `certified: false`.
- [ ] `PhospheneEngine/Tests/PhospheneEngineTests/Presets/AuroraVeilSilenceTest.swift` passes — non-black, vertically-stratified colour, form complexity ≥ 2.
- [ ] `PresetLoaderCompileFailureTest.expectedProductionPresetCount` updated 15 → 16; test passes (proves Aurora Veil loads, doesn't silent-drop).
- [ ] `PresetRegressionTests` Aurora Veil hash entry pinned across all three fixtures.
- [ ] `PresetVisualReviewTests` argument list includes `"Aurora Veil"`; `RENDER_VISUAL=1 swift test --filter PresetVisualReview` produces the three silence/mid/beat PNGs.
- [ ] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` clean.
- [ ] `swift test --package-path PhospheneEngine` full suite green (modulo pre-existing flakes: `MetadataPreFetcher.fetch_networkTimeout`, occasional `SessionManager` + `ProgressiveReadiness` parallel-execution races).
- [ ] `swiftlint lint --strict --config .swiftlint.yml` — 0 violations on touched files.
- [ ] **Visual silence-frame sanity check (load-bearing).** Open the `Aurora_Veil_silence.png` from `RENDER_VISUAL=1` output and verify side-by-side against the named references. The check is **side-by-side comparison** against named reference images, NOT self-judgment of "looks reasonable" (Failed Approach #63):
  - Against `01_macro_curtain_hero_purple_green.jpg`: does the rendered output read as belonging in the same visual conversation? Multi-column / multi-region vertical structure (even with one column, the noise field's biological asymmetry should produce multiple visible brightness concentrations)? Green-base / magenta-crown stratification visible? Slow drifting motion (between successive frames)?
  - Against `02_palette_green_to_magenta_stratification.jpg`: does the vertical colour gradient run green-base → magenta-crown? Per-march-step palette evaluation should give this physically; if it doesn't, the `sin(...)` palette phase offsets need re-tuning.
  - Against `03_meso_curtain_fold_drape.jpg`: are vertical ray striations visible at finer scale than the overall column envelope? (At AV.1 with one column this may be subtle; at AV.2 with three the parallax + multi-octave noise will make it more pronounced.)
  - Against `09_anti_neon_festival_aurora.jpg` (anti-reference): does the rendered output NOT read like this image? Pure-saturation kinetic neon, no stratification, beat-pulsing, kinetic-ribbons-converging-to-focal-point are all failure modes. If the AV.1 rendered output exhibits any of these, **stop and report** — the recipe is broken or misimplemented.
  - **Check against the 9-question authenticity rubric** (`AURORA_VEIL_RESEARCH_2026-05-18.md §2.3`): AV.1 must pass questions 1 (vertical stratification), 2 (green-dominant), 3 (vertical ray fine structure, ≥ 4 octaves), 5 (additive composite, stars through), 6 (soft top, sharp bottom), 7 (off-axis composition with dark foreground), 8 (brightness gradient within curtain), 9 (no theatrical beams). Question 4 (multi-timescale motion) is partially deferred to AV.3 — substrate drift only is acceptable at AV.1. Document any "NO" answer in the closeout report so AV.2/AV.3 can address.
- [ ] AV.1 entry in `docs/ENGINEERING_PLAN.md` flipped from ⏳ to ✅.
- [ ] AV.1 release-notes entry added to `docs/RELEASE_NOTES_DEV.md`.

**No Matt M7 review is required at AV.1** — that's an AV.3 gate after audio routes land. AV.1's visual check is your own side-by-side against named references + the 9-question rubric.

---

## Verify

Run after each logical step and at the end:

```
swift test --package-path PhospheneEngine --filter "AuroraVeil|PresetLoaderCompileFailure|PresetRegression|PresetAcceptance|FidelityRubric"

RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter "PresetVisualReview" 2>&1 | grep "Aurora Veil"
# Open the three Aurora_Veil_*.png files in /tmp/phosphene_visual/<ISO8601>/
# and confirm the visual silence-frame sanity check + 9-question rubric.

xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build

swiftlint lint --strict --config .swiftlint.yml
```

---

## Out of scope (AV.2 / AV.3 work, do not touch)

- **Audio reactivity.** No `f.bass_att_rel` / `f.mid_att_rel` / `f.valence` / `stems.drums_energy_dev` / `stems.vocals_pitch_hz` references in the shader at AV.1. AV.2 wires the seven audio routes from amended §5.7.
- **Multi-ribbon / multi-column rendering.** AV.1 renders a single implicit column (every fragment marches its own column, but the per-fragment seed is just `uv.x`). AV.2 adds two more offset columns at off-thirds positions (e.g. `uv.x + 0.27`, `uv.x - 0.18`) with depth-scale dimming, drifting at slightly non-parallel velocities.
- **Pitch-hue stratification.** AV.1's palette is the unmodified nimitz `sin(1.0 - vec3(...) + i * 0.043)` form. AV.2 adds `stems.vocals_pitch_hz`-derived phase offset.
- **Sub-second ray flicker + 2–20 s pulsation envelope (multi-timescale motion #2 + #3).** AV.3 deliverables per §5.4.
- **`AuroraVeilContinuousDominanceTest` + `AuroraVeilPitchHueTest`.** AV.2 deliverables.
- **Matt M7 review + cert flip.** AV.3 deliverables.
- **Roy Theunissen abs-of-difference fallback.** Only if `tri_noise_2d` overshoots the perf budget (see §AV-perf below). Don't preemptively fall back.

---

## Open questions to surface (don't decide alone)

### §AV-fam — Family enum value (`fluid` vs `atmospheric`)

If the Swift `PresetCategory` enum rejects `fluid` for Aurora Veil (or if adding a new `atmospheric` category seems cleaner long-term), **stop and ask Matt**. Don't pick unilaterally — family affects the Orchestrator's family-repeat penalty.

### §AV-perf — `tri_noise_2d` performance budget

Tier 1 budget is ~4.0 ms; Tier 2 is ~1.7 ms (per design §7). 50-step march × 5-octave triangular noise per step is the design target. If perf profiling at AV.1 shows the actual cost exceeds budget:

1. **First fallback:** reduce march count 50 → 40. Cheap; modest fidelity loss.
2. **Second fallback:** reduce noise octaves 5 → 4. Some asymmetry loss; still likely acceptable.
3. **Third fallback:** replace `tri_noise_2d` with Roy Theunissen's "difference of two Perlin layers, take `abs()`" approach (research §1.4). Lower fidelity ceiling — caps the preset at "stylized aurora" rather than "photographic." Document the regression in the closeout report; flag for Matt's decision before AV.2.

Don't preemptively optimize. Run the shader as specified, measure, then react if needed.

### §AV-sin — Failed Approach #33 scope for the per-march-step `sin()` palette

The per-march-step palette `sin(1.0 - vec3(2.15, -0.5, 1.2) + i * 0.043)` is `sin()` evaluated at march-step `i`, not at `time`. The `i` argument is a march-loop index, not a temporal accumulator. **This does NOT violate Failed Approach #33** (which prohibits free-running `sin(time)` for primary motion). The palette evaluation is per-fragment-per-frame and produces a static colour-stratification curve; motion comes from `tri_noise_2d`'s time argument + mv_warp accumulation, not from this `sin()`. Document this inline in the shader so future reviewers don't flag it incorrectly.

### §AV-stars-twinkle — Is per-frame `time` allowed for the star twinkle at AV.2?

AV.2 will add subtle star twinkle gated on `f.beat_phase01` + `vocalsPitchConfidence > 0.5`. The twinkle is decorative not primary, so the FA #33 "scope" exemption (decorative texture wrapping is fine; primary motion must be audio-anchored) probably applies. **AV.1 does not need to decide**; flag for AV.2 author.

---

## Stop and report instead of forging ahead when

Per CLAUDE.md Increment Completion Protocol:

- Any test fails that wasn't already a documented flake (`MetadataPreFetcher.fetch_networkTimeout` + occasional `SessionManager` / `ProgressiveReadiness` parallel-execution races).
- The silence test's "vertically-stratified colour" assertion fails — means the per-march-step palette evaluation isn't producing the green-base / magenta-crown gradient. Likely cause: phase offsets in the `sin(1.0 - vec3(2.15, -0.5, 1.2) + i * 0.043)` are off, or `i` is being passed wrong (e.g. as `float(i) / 50.0` instead of `float(i)`).
- The rendered output reads like `09_anti_neon_festival_aurora.jpg` (anti-reference). Likely cause: (a) `tri_noise_2d` substituted with a different noise (Perlin/fBM); (b) running-average smear `mix(..., 0.5)` missing — produces salt-and-pepper instead of ribbons; (c) palette phase offsets producing pink-only (no green base); (d) mv_warp amplitude too high (kinetic smear instead of slow drift).
- 9-question authenticity rubric: ANY question 1, 2, 3, 5, 6, 7, 8, 9 returns NO. (Question 4 deferred to AV.3.)
- Performance regression exceeds Tier-2 budget by ≥ 2× even after the §AV-perf fallback chain. Surface to Matt.
- Family enum value rejection (§AV-fam).
- `tri_noise_2d` reimplementation produces visually wrong output that doesn't match the description even after careful read of research dossier §1.1. Don't iterate blindly — request a paired session with Matt.

The cost of pausing is low. The cost of an increment that silently re-shapes scope is high.

---

## Commit cadence

Per CLAUDE.md commit-cadence rule: multiple small commits within the increment, message format `[AV.1] <component>: <description>`. Suggested commit boundaries:

1. `[AV.1] AuroraVeil.metal: tri_noise_2d clean-room helpers + 50-step raymarch + per-step palette`
2. `[AV.1] AuroraVeil.metal: mvWarpPerFrame/PerVertex with curl_noise advection`
3. `[AV.1] AuroraVeil.json: lightweight rubric sidecar`
4. `[AV.1] AuroraVeilSilenceTest: non-black + stratified colour + form-complexity gate`
5. `[AV.1] PresetLoaderCompileFailure + PresetRegression: register Aurora Veil (count 15→16, golden hash)`
6. `[AV.1] PresetVisualReview: add Aurora Veil to argument list`
7. `[AV.1] ENGINEERING_PLAN + RELEASE_NOTES: AV.1 ✅`

Each commit should leave the repo in a buildable, testable state.

Push to remote only after Matt's explicit "yes, push" in chat. Local main commits stay local until then.

---

## Closeout report (at end of increment)

Per CLAUDE.md Increment Completion Protocol:

1. **Files changed** — concrete paths, new vs edited.
2. **Tests run** — suites, pass/fail counts, pre-existing flakes called out.
3. **Visual harness output** — paths to the three `Aurora_Veil_*.png` files from `RENDER_VISUAL=1` plus a one-sentence assessment of each fixture's frame against the named references AND the 9-question authenticity rubric (mark each Q1–Q9 YES/NO/N/A; document any NO).
4. **Documentation updates** — `ENGINEERING_PLAN.md` AV.1 flip + `RELEASE_NOTES_DEV.md` entry.
5. **Open-question outcomes** — explicit answers (or escalations) for §AV-fam, §AV-perf, §AV-sin, §AV-stars-twinkle.
6. **Engineering plan updates** — flip Increment AV.1 status from ⏳ to ✅.
7. **Known risks and follow-ups** — anything deferred (especially AV.3 multi-timescale motion + AV.2 audio routes).
8. **Git status** — branch, commit hashes, clean tree confirmation.

---

## Project context inherited from CLAUDE.md (read those entries directly; reinforced here)

- **D-026: deviation primitives.** Doesn't apply at AV.1 (no audio routes); applies hard at AV.2.
- **D-019: stem-warmup blend.** Applies at AV.2 — every `stems.*` read must blend through `smoothstep(0.02, 0.06, totalStemEnergy)` to a FeatureVector proxy.
- **Failed Approach #33: no free-running `sin(time)` for primary motion.** See §AV-sin above — the per-march-step `sin(i)` palette is NOT a violation.
- **Failed Approach #44: silent shader drops.** The `expectedProductionPresetCount` test catches these.
- **Failed Approach #58 + #62: musical role articulated before authoring.** Aurora Veil's musical role is articulated in design doc §1 + concept-viability gate clear. AV.1 doesn't have audio reactivity; authoring against a validated concept.
- **Failed Approach #63: read references' README; side-by-side comparison vs self-judgment.** Mid-session visual sanity-check is side-by-side against the named reference images.
- **Failed Approach #64: stop guessing, do desk research.** The research is now done (`AURORA_VEIL_RESEARCH_2026-05-18.md`); the implementation is the act-on-it phase.
- **Failed Approach #65: do NOT negotiate away components of a working reference implementation under unverified "redundancy" arguments.** The four nimitz components (triangular noise, 50-step march, running-average smear, per-step palette) are ALL load-bearing. Do not subtract.
- **Failed Approach #67: one audio primitive per visual layer.** AV.2 concern; flag in design when wiring routes.
- **D-067(b): lightweight rubric profile.** Aurora Veil is emission-only direct-fragment; M1 cascade + M3 material count gates do NOT apply.
- **SwiftLint `file_length: 400` is relaxed for `.metal` files.**
- **Linear-RGB everywhere on the GPU side.**

---

## Why this matters

Aurora Veil is Phosphene's first **lowest-fidelity-bar** new preset since LM.4.7's certification. It's the catalog's planned "ambient ribbon" slot. It's also the **canonical Milkdrop pattern** (direct fragment + mv_warp) which currently has no consumer despite the infrastructure being in place since MV-2 (D-027). Landing AV.1 → AV.2 → AV.3 ships a second M7-certified preset (after Lumen Mosaic), unblocks Crystalline Cavern (Phase CC waits on at least one other M7-certified non-Arachne preset), and demonstrates that the lightweight-rubric path produces shippable presets without the M1/M3 cascade burden.

**The 2026-05-18 architectural pivot from 2D-pixel-ribbon to volumetric-raymarch is what makes this likely to succeed.** Three convergent prior-art references (nimitz, Lawlor-Genetti, Wittens) plus a sourced failure-mode taxonomy mean the implementation is no longer guessing — it's executing a validated recipe with explicit anti-patterns to avoid. The desk research saved us from the iteration tunnel that V.9 Ferrofluid Ocean hit.

Estimated effort for AV.1 alone: one session, ~2-3 hours including the visual sanity check + rubric pass. AV.2 and AV.3 are separate prompts to be authored after AV.1 ships.

Treat the visual silence-frame sanity check + 9-question rubric pass as the load-bearing final gate **for AV.1**. Automated tests prove the shader compiles and produces vertically-stratified colour; they don't prove the column reads as aurora. Side-by-side comparison against the four named references + the rubric is the discriminator.
