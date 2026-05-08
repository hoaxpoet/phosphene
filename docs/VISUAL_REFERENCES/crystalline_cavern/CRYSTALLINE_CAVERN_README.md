# Visual References — Crystalline Cavern

**Family:** organic (per D-038 — geode interiors are crystallographic biology, paired with Glass Brutalist as the natural-vs-engineered counterpart in the catalog)
**Render pipeline:** ray_march + ssgi + post_process + mv_warp (the D-029-preserved combination with no current consumer)
**Rubric:** full (per `CRYSTALLINE_CAVERN_DESIGN.md §8` — Tier-2-primary flagship piece, full §12.1–12.3 ladder)
**Last curated:** 2026-05-08

> **Architectural reminder.** Crystalline Cavern is a static-camera 3D ray-march scene: cavern walls + foreground crystal cluster + floor crystals + hanging tips, lit by the §5.3 bioluminescent recipe with screen-space caustic projection. Per D-020, architecture stays solid — only light, atmosphere, caustics, and a thin mv_warp shimmer respond to audio. The geometry is permanent. References below assume that target.

> **Visual target reframe (D-096).** All "must read as ..." acceptance gates below are aesthetic-family bars, not pixel-match contracts. A render that reads as belonging in the same visual conversation as the references — real photographic geode interior, biological-not-stylized emission, weathered cavern walls, large soft caustic cells — passes the gate. A render that reads like the named anti-reference (`09_anti_videogame_crystal_cave.jpg`) fails it. Pixel-fidelity to a particular reference image is an explicit non-goal. Real-time constraints (Tier 2 ~6.5 ms p95) are inviolable.

## Reference images

Files in this folder, ordered to walk the detail cascade (macro → meso/specular → palette/atmosphere) and close with the anti-reference. Each name encodes the trait it demonstrates per `../_NAMING_CONVENTION.md`. References are ≤ 500 KB each; crop and compress before committing.

| File | Annotation (what to learn from this image) |
|---|---|
| `01_macro_geode_interior_cathedral.jpg` | **Hero image.** Macro view into an opened amethyst geode showing multiple crystal terminations and depth between near and far crystals, full violet palette, the "looking *into* a cathedral" composition the design specifies for the foreground crystal cluster. The single most important "must match" frame for macro composition and termination geometry. The slight studio-light-from-above gives the cathedral feel without faking it. If a session only matches one frame, match this one. |
| `02_meso_crystal_termination_closeup.jpg` | **Termination geometry + internal banding.** Close-up of clustered amethyst showing chevron/Brazil-twin banding visible inside each crystal face — a real and beautiful trait of natural amethyst that stylized renders almost always miss. Anchors two distinct things: the hex-prism terminus geometry that `sd_crystal_cluster` builds, and the internal striation pattern that should subtly read inside `mat_pattern_glass`. **Caveat:** the per-crystal banding is a target for *internal pattern complexity*, not an explicit shader feature — pattern glass cellular voronoi achieves the same visual effect via a different mechanism. |
| `03_specular_water_caustics.jpg` | **Caustic pattern character.** Top-down photograph of a swimming pool surface showing the canonical dappled caustic pattern — bright cells with dark interstitial lines forming a webbed cellular pattern across teal-cyan water. **The phenomenon depicted is what `caustic_pattern()` projects onto cavern stone — same physics (sun through water surface), different substrate.** Use this as the anchor for caustic cell size, shape, and brightness distribution. The cool teal palette aligns with the cavern's bioluminescent ambient. The implementation samples this phenomenon per-fragment via `Volume/Caustics.metal`; this image documents the target the projection must match. |
| `04_micro_wet_limestone_wall.jpg` | **Wet-stone surface character and cellular weathering.** Cool-grey limestone with rough bumpy surface — the cellular weathering pattern is exactly the `worley_fbm` displacement target on cavern walls, and the moisture sheen is the `mat_wet_stone` `wetness=0.4` target. **Caveat:** the dark scoria fragment in the lower-right is unrelated geology; crop or ignore. Use this image for **surface character only** — the cool palette is correct for the cavern's cool bioluminescent ambient, but wall *color* in the rendered scene comes from `mat_wet_stone`'s recipe modulated by valence-tinted IBL, not from this reference. |
| `05_palette_bioluminescent_cave.jpg` | **Bioluminescent emission palette anchor.** Waitomo-style glow-worm cave: bioluminescent cyan-blue pinpricks of *Arachnocampa luminosa* against rough cave rock. This is the literal palette anchor for the design's "biologically muted, not neon" emission spec — discrete cool pinpoint emissions against dark cave context. **Caveat:** the surrounding rock is warm-toned in this image; that's incidental. Use this image for **emission character and density only**, not for ambient palette (cavern ambient is cool blue-purple, not warm orange). The implementation's crystal emission should evoke the *quality* of these glow-worm points: discrete, cool, soft-haloed, not graphic. |
| `06_specular_pattern_glass_closeup.jpg` | **Pattern glass cellular structure.** Architectural pattern glass with hexagonal cellular voronoi pattern and visible refraction showing colored regions through the cells — demonstrates both the cell structure AND the optical behavior `mat_pattern_glass` (V.4, §4.5b) renders. The pebbled hexagonal grid is the cellular voronoi target with the inter-cell ridge that `voronoi_f1f2`'s F2−F1 smoothstep produces. **Caveat:** the saturated color blocks in this reference come from refracted scene content; the cavern's pattern glass crystals will refract dim bioluminescent emission, not high-saturation primaries. Use this image for **cell geometry only**, not palette. |
| `09_anti_videogame_crystal_cave.jpg` | **NOT this — failure mode: stylized video-game crystal cave.** Concept art of a dramatic blue ice/crystal cave interior with saturated palette, theatrical ice-crystal stalactites, ancient temple architecture, atmospheric perspective with character-with-torch silhouette. Photographic-painted concept art for a video game (James Paick / Scribble Pad Studios — watermark visible). If the rendered output reads like this image — high-saturation pure-blue palette, dramatic ice-crystal scale, fantasy architecture, theatrical god-rays — the preset is uncertified by definition. The §10.1 target is *natural geode photography elevated by bioluminescent emission*, not AAA-game crystal cave. |

## Mandatory traits (per SHADER_CRAFT.md §12.1)

For Crystalline Cavern specifically:

- [ ] **Detail cascade:**
  - macro = cavern interior bounded by 3–5 large wall planes meeting at oblique angles, foreground cluster of 4–5 hexagonal-prism crystals at frame center (~1.5 units tall), floor with secondary smaller crystals jutting up; reference `01_macro_geode_interior_cathedral.jpg` and `02_meso_crystal_termination_closeup.jpg`
  - meso = cavern walls displaced via `worley_fbm(p * 0.6) * 0.08` for cellular cavity texture (geode-rind look); per-instance hash-driven scale/rotation/position jitter on each hex-prism in the cluster (CLAUDE.md Failed Approach #44 explicit avoidance); reference `04_micro_wet_limestone_wall.jpg` for the wall cellular character
  - micro = `triplanar_detail_normal` on cavern walls (kills smooth shading); per-face `fbm8` brightness variation on crystals (pixel-scale grain); hex tiling for floor cellular crystallisation
  - specular = per-face `fbm8` roughness variation on chrome formations and pattern glass (Failed Approach #38 — "CGI plastic" avoidance); anisotropic streaks on chrome accents
- [ ] **Hero noise functions:** `fbm8` (8 octaves, well above the §12.1 ≥4 floor) for per-face variation and dust density; `worley_fbm` (5 octaves) for wall cellular displacement; `ridged_mf` for floor crystal terminations.
- [ ] **Material count and recipes (≥ 3 — design uses 4):**
  - `mat_pattern_glass` (foreground crystal cluster) — voronoi cellular pattern per `06_specular_pattern_glass_closeup.jpg`, NOT fbm-frost (V.4 §4.5b, D-067(b) — pattern variant explicitly chosen over frost)
  - `mat_wet_stone` at `wetness=0.4` (cavern walls) and `wetness=0.55` (floor base) — V.3 cookbook with triplanar normal per `04_micro_wet_limestone_wall.jpg`
  - `mat_polished_chrome` (sparse metallic floor accents with anisotropic streaks) — V.3 cookbook
  - `mat_frosted_glass` (hanging tips / crystal cluster crowns) — V.3 cookbook, milky-cloudy character at hanging-tip terminations
- [ ] **Audio reactivity (D-026 deviation primitives only):**
  - IBL ambient strength + key light intensity ← `f.bass_att_rel` (continuous primary, multiplier `0.85 + 0.30 × x`)
  - Caustic flash brightness ← `stems.drums_energy_dev` (accent, gated below 2× continuous per design §5.6)
  - Caustic refraction angle (UV scale modulation) ← `stems.vocalsPitchNorm` from SpectralHistoryBuffer (continuous, gated by `vocalsPitchConfidence > 0.4`)
  - IBL palette warm/cool tint ← `f.valence` (D-022 path — IBL ambient multiplied by `lightColor.rgb` so tint propagates across all surfaces, not only direct-lit)
  - mv_warp shimmer amplitude ← `f.mid_att_rel` (continuous)
  - Mid-pulse caustic offset ← `f.beat_phase01` anticipatory drift (`approachFrac × 0.005`)
  - **No absolute thresholds.** Reject any `smoothstep(0.22, 0.32, f.bass)` style pattern (D-026).
  - **Continuous-vs-accent ratio:** base caustic intensity 0.4 dominates the `+1.5 × drums_energy_dev` burst (max ~0.5 → 0.75 burst → 0.4/0.75 confirms continuous primary per CLAUDE.md §Audio Data Hierarchy).
- [ ] **Silence fallback (D-019, D-020):** at `totalStemEnergy == 0`, IBL at base ambient, crystals emit at base level (`base_emission = 0.15`), key light at base intensity, caustics at base brightness with very slow drift, mv_warp continues to accumulate shimmer. Cavern is alive but quiet. Form complexity at silence: ≥ 4 (cavern walls + crystal cluster + floor + light shaft + dust motes). All `stems.*` reads blend through `smoothstep(0.02, 0.06, totalStemEnergy)` to FeatureVector proxies — `vocalsPitchNorm` falls back to `f.bass_dev * 0.3 + 0.5` pre-warmup so caustic refraction angle has a defined value.
- [ ] **Performance ceiling:** Tier 2 ~6.5 ms p95 / Tier 1 ~4.85 ms p95 (per design §7 budget; ray-march G-buffer + SSGI dominate cost). `complexity_cost: {tier1: 5.0, tier2: 6.5}` in JSON sidecar.
- [ ] **Hero reference image:** `01_macro_geode_interior_cathedral.jpg`. If a session only matches one frame, match this one.

## Expected traits (per §12.2 — at least 2 of 4)

- [ ] **Triplanar texturing on non-planar surfaces** — applicable. `triplanar_detail_normal` on cavern walls per design §5.3; uniplanar would stretch on the oblique cavity planes. Mandatory for the wet-stone surface character per `04_micro_wet_limestone_wall.jpg`.
- [ ] **Detail normals** — applicable. Triplanar detail normals on stone (above) plus per-face fbm8 normal perturbation on pattern-glass crystals. Reference `04_micro_wet_limestone_wall.jpg` for the surface micro-relief target.
- [ ] **Volumetric fog or aerial perspective** — applicable. `vol_density_height_fog` ground fog at `floorY = -0.5`, falloff 0.4 (mostly visible as ground mist); volumetric light shafts via `ls_radial_step_uv` with sun UV at (0.7, 0.95); faint dust mote field via `vol_sample` accumulating along view ray, density `vol_density_fbm(p, 1.5, 3)`. Mote field visible mainly inside shaft volume.
- [ ] **SSS / fiber BRDF / anisotropic specular** — applicable. SSS approximation in `mat_frosted_glass` (emission-based internal-scatter approximation, V.3 recipe) on hanging tips; anisotropic streaks on chrome floor accents.

**Score target:** 4/4 expected. All four traits are exercised by the design.

## Strongly preferred traits (per §12.3 — at least 1 of 4)

- [ ] **Hero specular highlight in ≥ 60% of frames** — applicable. Polished-chrome floor accents and pattern-glass cluster crystals carry mirror highlights from the warm key light + IBL through most camera framings. Verify against `02_meso_crystal_termination_closeup.jpg` for highlight character on faceted crystal surfaces.
- [ ] **Parallax occlusion mapping** — deferred. Recipe estimates POM at ~1.0 ms; current Tier 2 budget shows ~0.5 ms of headroom. Open question §11.3 in design doc: add only if Session 4 review shows walls reading flat. Otherwise skip.
- [ ] **Volumetric light shafts or dust motes** — applicable and required. Both shafts and motes are in the design (§5.4 atmosphere). Reference `03_specular_water_caustics.jpg` is the pattern reference; cell scale and brightness distribution should match.
- [ ] **Chromatic aberration / thin-film interference** — open question §11.5. A single crystal in the foreground cluster could carry a `thinfilm_rgb`-tinted iridescent inclusion, adding ~0.1 ms and pushing rubric score from 14 to 15. Defer to Session 4 polish if budget allows; not gated.

**Score target:** 2/4 strongly preferred (hero specular, light shafts + dust motes). Potential 3/4 with thin-film inclusion.

**Total rubric ceiling:** 14/15 with all mandatory + 4/4 expected + 2/4 strongly preferred. Potential 15/15 with thin-film addition. Comfortably exceeds 10/15 minimum.

## Anti-reference — single failure mode

**Failure mode #1 — Stylized video-game crystal cave (`09_anti_videogame_crystal_cave.jpg`).** The shader produces output that reads as AAA-game concept art rather than natural geode photography. Symptoms: pure-saturation electric blue or cyan palette with no biological warmth in emission; theatrical god-rays converging on a focal point; ice-crystal stalactites at fantasy scale; ancient temple architecture or scaffolding props; high-contrast volumetrics with painted-light qualities. The §10.1 target is *natural geode photography elevated by bioluminescent emission*, not concept art. The bioluminescent glow-worm cave (`05`) anchors the correct emission interpretation; this image shows the easy wrong one. Note: this is the only anti-reference in the curated set; the original design doc cited two (video-game crystal + Tron neon), but the video-game-crystal-cave failure mode subsumes the Tron-neon failure mode for this preset (both reduce to "saturated stylized palette without biological grounding").

**Other failure modes (no images, but called out):**

- **Procedural box prisms.** SDF crystals with no per-instance variation read as cloned. Hash-driven per-instance scale, rotation, and position jitter is mandatory (CLAUDE.md Failed Approach #44).
- **CGI plastic.** Constant roughness on chrome / pattern glass. Roughness must vary spatially via `fbm8` (Failed Approach #38).
- **Tron neon caustics.** Caustic colors must be tinted from valence-modulated light, not high-saturation primaries. Caustic intensity gates by `surface_lighting` so caustics only appear on lit surfaces.
- **Smeared mv_warp.** Amplitude > 0.003 will fight the static scene and produce ghosting (D-029 lesson). Keep amplitude < 0.003. The design's `0.002 * curl_noise` displacement is the target; `0.003` is the hard ceiling.
- **Beat-dominant caustic flash.** Drums burst > 2× base caustic intensity violates the audio hierarchy (CLAUDE.md §Audio Data Hierarchy). Verified by `CrystallineCavernCausticBeatRatioTest`.
- **Dead silence.** At zero audio, nothing moves. Caustic drift and mv_warp shimmer must continue. Verified by `CrystallineCavernSilenceTest`.
- **Geometric perfection.** Real geodes are weathered. Walls without `worley_fbm` displacement read as solid-modeled CAD output.
- **Free-running `sin(time)` motion.** Per the catalog-wide rule from Arachne tuning. All oscillation must be audio-anchored or mv_warp-driven. Caustic drift uses `time * 0.3 + valence * 0.5` which is acceptable (low-frequency phase advance, not visible oscillation).

## Audio routing notes

Specific audio→visual mappings that must hold (per `CRYSTALLINE_CAVERN_DESIGN.md §5.6`):

- **Continuous primary drivers** (deviation primitives, D-026): IBL ambient strength + key light intensity ← `f.bass_att_rel`; caustic refraction angle ← `stems.vocalsPitchNorm` (gated by `vocalsPitchConfidence > 0.4`); IBL palette warm/cool tint ← `f.valence` (D-022 path: `iblAmbient *= scene.lightColor.rgb`); mv_warp shimmer amplitude ← `f.mid_att_rel`; crystal emission breath ← `f.bass_att_rel + valence`.
- **Beat accents** (deviation primitives, D-026): caustic flash brightness ← `stems.drums_energy_dev` (caustic brightness `+1.5 × x` over base 0.4); mid-pulse caustic offset ← `f.beat_phase01` anticipatory drift (`approachFrac × 0.005`).
- **Stem warmup** (D-019): all `stems.*` reads must blend through `smoothstep(0.02, 0.06, totalStemEnergy)` to FeatureVector proxies. The first ~10 s of every track and all of ad-hoc mode must look correct without stems — pre-warmup, caustic flash falls back to `f.bass_dev * 0.4`; `vocalsPitchNorm` falls back to a fixed mid-band value.
- **Structure stays solid** (D-020): cavern walls, crystal cluster positions, floor crystal positions, and hanging tip positions are all hash-seeded constants. Audio modulates emission, IBL tint, caustics, mv_warp shimmer, and key light intensity — **not** geometry. Camera is fixed (`scene_camera.position = (0.0, 0.6, 3.5)`, `target = (0.0, 0.4, 0.0)`, `fov = 45`).
- **mv_warp on static camera** (D-029): the warp adds shimmer over the lit frame, not motion design. `baseRot = 0.0004`, `baseZoom = 0.0008`, `decay = 0.94`. Per-vertex displacement `0.002 * curl_noise(uv * 3.0, time * 0.15)`; amplitude scaled by `(0.5 + 0.5 * f.mid_att_rel)`. Goal: make highlights "live" between frames, not smear the scene.
- **Continuous-vs-accent ratio** (Audio Data Hierarchy): base caustic intensity 0.4 dominates `+1.5 × drums_energy_dev` burst by definition (max burst → 0.4/0.75 = 0.53 continuous fraction). Verified by `CrystallineCavernCausticBeatRatioTest` (peak caustic luma ≤ 2× steady caustic luma).

## Outstanding actions

- [ ] **Verify family enum.** Design §1 references `architectural` as the family choice. `PresetCategory.swift` enum (per the prior conversation's findings) does not contain `architectural` — the enum members are `waveform, fractal, geometric, particles, hypnotic, supernova, reaction, drawing, dancer, transition, abstract, fluid, instrument, organic`. **Set `family: "organic"`** in the JSON sidecar (D-038's crystal-growth clause covers this; pairs naturally with Glass Brutalist as the natural-vs-engineered counterpart). Update `CRYSTALLINE_CAVERN_DESIGN.md §1.13` to reflect this.
- [ ] **Re-validate `CrystallineCavern.json` schema** against `Gossamer.json` (the actual existing schema). Required fields per the prior conversation's findings: `name` (not `id`), `description`, `author`, `duration`, `fragment_function`, `vertex_function`, `beat_source`, top-level `decay` (not nested `feedback` wrapper). The JSON template in `CRYSTALLINE_CAVERN_DESIGN.md §10` was drafted before the real schema was confirmed; regenerate during Session 1.
- [ ] **Caustic utility production-readiness.** `Volume/Caustics.metal` exists from V.2 (D-055) but no current preset consumes it. Validate output during Session 3 against `03_specular_water_caustics.jpg` for cell scale, brightness distribution, and drift speed. Open question §11.2 in design doc — fall back to `fbm8` overlay if utility output is unworkable.
- [ ] **POM evaluation for cavern walls.** Open question §11.3 — recipe estimates POM at ~1.0 ms; current Tier 2 budget shows ~0.5 ms of headroom. Add in Session 4 polish only if visual review shows walls reading flat. Defer until first Matt review pass.
- [ ] **Tier 1 acceptable-degradation check.** SSGI off + caustic samples halved + raymarch steps 48 are the proposed Tier 1 path (design §7). If Tier 1 visual feels markedly inferior at Session 4 review, gate the entire preset Tier 2-only via the orchestrator's tier-cost exclusion (open question §11.4).
- [ ] **Thin-film inclusion (P4 polish).** Open question §11.5 — single crystal in cluster gets a `thinfilm_rgb`-tinted iridescent inclusion, ~0.1 ms cost, pushes rubric 14 → 15. Add in Session 4 polish if budget allows; not gated.
- [ ] **License audit on `09_anti_videogame_crystal_cave.jpg`.** James Paick / Scribble Pad Studios concept art with visible watermark. Concept-art use as a documented anti-reference in a private design document falls under fair-use commentary, but if the visual references folder is ever published or shared externally, source a watermark-free alternative (Diablo III gameplay screenshot, Skyrim Blackreach, etc.) before that publication.
- [ ] **M7 review pending** until Session 4 (per `CRYSTALLINE_CAVERN_DESIGN.md §9`). `CrystallineCavern.json` `certified` stays `false` until that pass succeeds.

## Provenance

Curated by: Matt
Curation date: 2026-05-08

Image sources:

- `01_macro_geode_interior_cathedral.jpg` — Unsplash, photographer Daniel Olah, photo ID `ON0jlgkd8R0`. Unsplash License.
- `02_meso_crystal_termination_closeup.jpg` — Unsplash, photographer Calvin Chai, photo ID `-Of-1FQHiA4`. Unsplash License.
- `03_specular_water_caustics.jpg` — Photograph by Jake Hicks. **License pending verification.** Image sourced from a publicly-available preview (`caustic-light-swimming-pool-by-jake-hicks-3-800x534.webp`); confirm rights for internal-documentation use before publication. If license is restrictive, source an equivalent CC-BY caustic frame from Wikimedia Commons or generate from `Volume/Caustics.metal` itself once the utility is validated in Session 3.
- `04_micro_wet_limestone_wall.jpg` — Unsplash, photographer Kelsey Todd, photo ID `3uZ1pVbCBKQ`. Unsplash License.
- `05_palette_bioluminescent_cave.jpg` — Unsplash, photographer Nicole Geri, photo ID `OEZBV8OizGc`. Unsplash License. Waitomo-style glow-worm cave.
- `06_specular_pattern_glass_closeup.jpg` — Unsplash, photographer Jake Nackos, photo ID `2UZK92eh9tM`. Unsplash License.
- `09_anti_videogame_crystal_cave.jpg` — Concept art by James Paick / Scribble Pad Studios. **License: documented anti-reference under fair-use commentary.** Watermark visible and retained; full attribution recorded here. If the visual-references folder is ever published externally, source a watermark-free alternative before that publication.

Unsplash License terms: free for commercial and non-commercial use, no attribution required but recommended. Recording attributions here protects future re-licensing audits.
