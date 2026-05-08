# Visual References — Aurora Veil

**Family:** fluid
**Render pipeline:** direct_fragment + mv_warp (single pass `["mv_warp"]`, per D-027)
**Rubric:** lightweight (per D-067(b) — emission-only direct-fragment preset, exempt from M1 detail cascade and M3 material-count requirements)
**Last curated:** 2026-05-08

> **Architectural reminder.** Aurora Veil renders a 2.5D scene: stars + 2–3 layered ribbons + sky gradient inside a single fragment shader, with mv_warp providing temporal accumulation. There is no SDF, no PBR, no mesh shader. The whole point of this preset's catalog role is to be the lowest-barrier authoring example — the canonical Milkdrop pattern (direct fragment + per-vertex feedback warp) which currently has no consumer. References below assume that target.

> **Visual target reframe (D-096, 2026-05-08).** All "must read as ..." acceptance gates below are aesthetic-family bars, not pixel-match contracts. A render that reads as belonging in the same visual conversation as the references — real photographic aurora over dark landscape, green-base/magenta-crown stratification, multi-ribbon depth, biological-not-stylized — passes the gate. A render that reads like the named anti-reference (`09_anti_neon_festival_aurora.jpg`) fails it. Pixel-fidelity to a particular reference image is an explicit non-goal.

## Reference images

Files in this folder, ordered macro → palette → meso → atmosphere → anti-reference. Each name encodes the trait it demonstrates per `../_NAMING_CONVENTION.md`. References should be ≤ 500 KB each; crop and compress before committing.

| File | Annotation (what to learn from this image) |
|---|---|
| `01_macro_curtain_hero_purple_green.jpg` | **Hero image.** Multi-curtain composition with the full color-temperature range visible in one frame: green vertical ribbons sweeping across the upper-left, magenta crown wash on the upper-right, distinct ribbons at varied angles establishing depth. Forest silhouette anchors the composition without dominating. The single most important "must match" frame for color range and multi-ribbon parallax. **Caveat:** the magenta reads slightly post-processed — treat it as the *saturation ceiling* the implementation may approach during peak sections, not the floor for ambient passages. |
| `02_palette_green_to_magenta_stratification.jpg` | **Palette stratification anchor.** Pure-sky frame with no foreground, magenta-on-top / green-on-bottom transition unambiguous. This is the IQ cosine palette anchor: when implementation reviews ask "is the hue map right?", this is the image to put next to the render. **Caveat:** the aurora here is splayed radially rather than as a vertical curtain — use this image for **palette only**, NOT as a shape reference. The §5.2 design specifies vertical curtain ribbons, not radial spreads. |
| `03_meso_curtain_fold_drape.jpg` | **Curtain meso fold structure.** Cleanest demonstration of the wavy "drape" pattern that `f.mid_att_rel` should modulate. The curving sweep across the upper portion shows the meso-scale fold target, and vertical ray striations within the curtain are visible at the right resolution — informs both the fold-modulation term and the per-curtain ray-detail `fbm4` term. Predominantly green, so palette isn't a confounder; the image is specifically about meso shape. |
| `04_atmosphere_multi_curtain_parallax.jpg` | **Multi-curtain depth target.** Multiple distinct ribbons at different angles plus secondary vertical rays — depth ordering between ribbons reads clearly. Pure green so the focus stays on ribbon-count and parallax, not color. Anchors the design's 3-ribbon `depthScale[i] ∈ {1.0, 0.7, 0.5}` decision: deeper ribbons appear dimmer and slightly displaced. The Iceland glacial-lake foreground occupies ~20% of frame — acceptable; the sky still dominates. |
| `09_anti_neon_festival_aurora.jpg` | **NOT this — failure mode: festival visual / neon ribbon shader.** Stage spotlights converging at a center point in saturated magenta-orange-cyan, with crowd silhouettes below. Photographic, real-world, but structurally what a bad aurora shader looks like — kinetic ribbons in pure-saturation palette, no stratification, no biological asymmetry, no green base. If the rendered output reads like this image, the preset is uncertified by definition. Documents both failure modes called out in `AURORA_VEIL_DESIGN.md §6`: "neon ribbon shader" and "festival visual." |

## Mandatory traits (lightweight rubric, per D-067(b))

The lightweight rubric ladder is L1–L4. For Aurora Veil specifically:

- [ ] **L1 — Silence fallback.** At `totalStemEnergy == 0`, ribbons remain at base brightness (0.85), folds are static, mv_warp continues to accumulate slow rotation, ribbons drift visually via their warped_fbm center-line motion. Form complexity ≥ 2 at silence (multi-ribbon + stars + sky). Reference `01_macro_curtain_hero_purple_green.jpg` for what the silence-state should evoke even without audio modulation.
- [ ] **L2 — Deviation primitives only (D-026).** Every primary driver uses `*_rel` or `*_dev`. No absolute thresholds. Reject any `smoothstep(0.22, 0.32, f.bass)` style pattern. Verified by `FidelityRubricTests`.
- [ ] **L3 — Performance budget.** p95 ≤ Tier 1 ~4.0 ms / Tier 2 ~1.7 ms (per design §7). Verified by `PresetPerformanceTests` against silence / steady / beat-heavy fixtures.
- [ ] **L4 — Frame match.** Matt M7 review against `01` and `04` for hero composition; against `02` for palette correctness; against `03` for fold structure.

Plus design-doc-specific must-haves (rooted in §3 trait matrix and §5 architecture):

- [ ] **Multi-ribbon composition.** 2–3 layered curtain ribbons with depth-scale dimming (`depthScale[i] ∈ {1.0, 0.7, 0.5}`); verified visually against `04`. A single-ribbon render is a fail — the depth of real aurora is lost.
- [ ] **Vertical color stratification.** Lower portion of each ribbon → green base; upper portion → magenta crown; transition sampled from IQ cosine palette with `t = uv.y + pitchHue`. Verified against `02`.
- [ ] **Vertical ray striations within each curtain.** `fbm4(float2(uv.x * 80 + raysPhase[i], y * 4))` — the fine pillars that read as electron-precipitation columns. Verified visually against `03`.
- [ ] **Stars on dark sky.** Sparse pinpoints from `hash_f01_2(uv * 800) > 0.997`. NOT a procedural noise sky — real aurora night sky is mostly black with sparse stars. Verified visually against `01`.
- [ ] **mv_warp shimmer/echo.** `decay = 0.945`, `baseRot ≈ 0.0008`, `baseZoom ≈ 0.0015`. Curtains leave a faint trail when they shift, not a smear. Reference §5.3 of design doc.
- [ ] **No free-running `sin(time)` motion.** All oscillation must be audio-anchored or mv_warp-driven (CLAUDE.md Arachne tuning rule, applies catalog-wide).

## Expected / strongly preferred traits

Lightweight presets are exempt from §12.2 (expected) and §12.3 (strongly preferred) per D-067(b). The full PBR-oriented traits (triplanar texturing, detail normals, hero specular, POM, thin-film, etc.) are inapplicable to an emission-only direct-fragment shader.

**Optional preferences for Aurora Veil specifically (not gated, not required):**

- Star twinkle modulated by `f.beat_phase01` gated on `vocalsPitchConfidence > 0.5` — adds subtle music-coupled motion to the otherwise-static sky layer. Subtle is the operative word; obvious twinkling reads as decorative.
- Per-frame palette warm/cool shift on `f.valence` — small phase offset on the IQ cosine palette so minor-key passages read cooler, major-key warmer. Implementation can defer this to Session 3 polish.

## Anti-reference — single failure mode

**Failure mode #1 — Festival visual / neon ribbon shader (`09_anti_neon_festival_aurora.jpg`).** The shader produces output that reads as EDM festival lighting rather than aurora photography. Symptoms: pure-saturation pink/cyan/magenta palette with no green base, no vertical stratification, beat-pulsing rather than continuous-driven motion, kinetic ribbons converging to a focal point rather than parallel curtains. The design doc calls out two distinct framings of this failure ("neon ribbon shader" and "festival visual"); both reduce to the same anti-reference.

**Other failure modes (no images, but called out):**

- **Single solid ribbon.** Without 2–3 layered ribbons with parallax, the depth of real aurora is lost. Fails L1 form-complexity gate by reading as flat.
- **Procedural noise sky.** A noise-based sky pattern is wrong — real aurora night sky is mostly black with sparse stars. Hash-thresholded points at low density are correct; `worley_fbm` or similar is not.
- **Free-running `sin(time)` motion.** Per the catalog-wide rule from Arachne tuning. All oscillation must be audio-anchored or mv_warp-driven.
- **Beat-dominant motion.** Continuous energy must be the primary visual driver per CLAUDE.md §Audio Data Hierarchy. Drum-coupled curtain kink is the only beat element, and its amplitude (0.003 UV) is dominated by continuous brightness breathing (0.30) by >10×.
- **mv_warp amplitude > 0.005 UV displacement.** Smears the scene into mush rather than producing the slow-compounding aurora motion. The design's 0.005 cap on `curl_noise` displacement is a hard ceiling.

## Audio routing notes

Specific audio→visual mappings that must hold (per `AURORA_VEIL_DESIGN.md §5.6`):

- **Continuous primary drivers** (deviation primitives, D-026): ribbon hue along uv.y ← `vocalsPitchNorm` from `SpectralHistoryBuffer[1920..2399]`; brightness breathing ← `f.bass_att_rel` (0.85 + 0.30 × x); fold density ← `f.mid_att_rel` (multiplier on uv.y fold frequency); palette warm/cool shift ← `f.valence`.
- **Beat accents** (deviation primitives, D-026): curtain kink ← `stems.drums_energy_dev` (mv_warp y-displacement amplitude, capped at 0.003 UV); star twinkle ← `f.beat_phase01` gated by `vocalsPitchConfidence > 0.5`.
- **Stem warmup** (D-019): all `stems.*` reads must blend through `smoothstep(0.02, 0.06, totalStemEnergy)` to FeatureVector proxies. The first ~10 s of every track and all of ad-hoc mode must look correct without stems — pre-warmup, hue stratification falls back to fixed (no per-frame pitch offset).
- **Structure stays solid** (D-020): ribbon center-line and width are determined by `warped_fbm` on (y, time, ribbon_index), not by audio. Audio modulates emission, hue, and warp displacement — **not** ribbon position or count. Ribbon count is fixed at 3 (or whatever is set in code constants).
- **Continuous-vs-accent ratio** (Audio Data Hierarchy): brightness-breathing amplitude 0.30 dominates curtain-kink amplitude 0.003 by >10×. Verified by `AuroraVeilContinuousDominanceTest`.

## Outstanding actions

- [ ] **Compress all images to ≤ 500 KB** before final commit. Original Unsplash sizes likely exceed this; crop any wasted edges before compressing.
- [ ] **Verify Getty/Unsplash partnership license terms** for `01_macro_curtain_hero_purple_green.jpg` (Getty Images via Unsplash). Standard Unsplash License may not apply to Getty-partnership content; if license is restrictive, source an equivalent CC-BY or public-domain aurora frame from Wikimedia Commons or NASA APOD. Same caveat as the Arachne ref `19` decision.
- [ ] **Re-validate `Aurora_Veil.json` schema** against an actual existing preset sidecar (e.g. `Gossamer.json`). The JSON template in `AURORA_VEIL_DESIGN.md §10` was drafted before the real schema was confirmed; required fields like `name` (not `id`), `description`, `author`, `duration`, `fragment_function`, `vertex_function`, `beat_source` need to be added; the `feedback` wrapper around `decay` may not exist.
- [ ] **JSON sidecar `complexity_cost.tier1 = 4.0, tier2 = 1.7`** to match the design §7 budget.
- [ ] **Fill in image attributions** in the Provenance section below — Unsplash photo IDs are recorded; full attribution lines need verification before commit.
- [ ] **M7 review pending** until Session 3 (per `AURORA_VEIL_DESIGN.md §9`). `Aurora_Veil.json` `certified` stays `false` until that pass succeeds.
- [ ] **P1 enrichment refs (not blocking implementation):**
  - **Tighter fold-detail close-up.** A frame zoomed into one curtain section showing the meso drape pattern at higher resolution than `03`. Source if Session 2 harness review shows the fold-modulation reads wrong.
  - **Aurora over snow / open horizon.** A frame with low foreground (snow plain or sea horizon) for a comparison composition where the aurora occupies even more of frame than `01`. Source only if Session 1 review shows `01`'s forest silhouette is biasing the implementation.

## Provenance

Curated by: Matt
Curation date: 2026-05-08

Image sources:

- `01_macro_curtain_hero_purple_green.jpg` — Unsplash, photographer credited as "Getty Images" via Unsplash partnership, photo ID `XAV3Dg7d88s`. **Verify license terms before commit** — Getty/Unsplash partnership images may have stricter terms than standard Unsplash License. If license is restrictive, source an equivalent CC-BY or public-domain aurora image.
- `02_palette_green_to_magenta_stratification.jpg` — Unsplash, photographer Neil Mark Thomas, photo ID `2xS1K3AhBKs`. Unsplash License.
- `03_meso_curtain_fold_drape.jpg` — Unsplash, photographer Lucas Marcomini, photo ID `cVBz9q1T_9M`. Unsplash License.
- `04_atmosphere_multi_curtain_parallax.jpg` — Unsplash, photographer V2osk, photo ID `WNS__aBJjl4`. Unsplash License.
- `09_anti_neon_festival_aurora.jpg` — Unsplash, photographer Ben Wicks, photo ID `o7wPTlBgQ98`. Unsplash License. Deliberately included as negative reference (festival photo, not actual aurora).

Unsplash License terms: free for commercial and non-commercial use, no attribution required but recommended. Recording attributions here protects future re-licensing audits.
