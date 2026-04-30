# Fractal Tree — Visual References

**Purpose:** Reference images for the `Fractal Tree` preset uplift per `SHADER_CRAFT.md §10.4` (Increment V.10). Cited by filename in Claude Code session prompts per `SHADER_CRAFT.md §2.3`.

**Target read:** Painterly tree, seasonal palette (default autumn), bark with POM displacement + lichen patches, translucent leaves with back-lit SSS, golden-hour lighting, wind-driven motion via `curl_noise`.

**Status:** v1.0 — all reference slots populated. Ready for V.10 session prompts.

---

## Image inventory

### `01_macro_silhouette.jpg` — overall crown form
*Source: `kidney-tree_orig.jpg`*

Asymmetric crown with dense terminal branching — fine branches at the perimeter blur into a cloud-mass that anchors the leaf-cluster billboard positions. Asymmetric lean breaks Y-symmetry that would read as procedural (Failed Approach #44).

**Mandatory:** ≥4 generations visible at perimeter; trunk-to-canopy 1:2 vertical; asymmetric crown bias, no mirror symmetry. **Decorative:** specific lean direction.

### `02_macro_branching_params.jpg` — L-system parameter card
*Source: `Fractal-Tree-06.jpg`*

Six-panel parameter sweep: branching angle 15° / 25°, proportional reduction 60% / 65% / 70%. The 25° / 65% panel matches `01_macro_silhouette.jpg`.

**Mandatory:** branching angle ∈ [15°, 25°]; proportional reduction ∈ [0.62, 0.68]. **Decorative:** white background.

### `03_meso_foliage_cluster.jpg` — leaf-cluster shape language
*Source: `lesley-davidson-M8s6ScHN0HA-unsplash.jpg`*

Pinnate fronds on black demonstrating the silhouette template for billboarded leaf clusters at branch tips.

**Mandatory:** pinnate (feather-like) cluster outline; directional rachis; visible specular on leaf surface. **Decorative:** species.

### `04_meso_bark_surface.jpg` — bark POM target
*Source: `loren-king-1oz4QKRWPk0-unsplash.jpg`*

Deep-furrowed bark with vertical fiber ridges and a side band of yellow crustose lichen. The canonical reference for the §4.7 bark recipe.

**Mandatory:** vertical fiber ridges with cross-hatched intermediate cracks; warm reddish-brown core under grey weathered ridges (`base = float3(0.18, 0.11, 0.07)`); flat crustose lichen distribution (Worley + smoothstep mask). **Decorative:** species.

**Anti-traits:** foliose lichens (3D-protruding); smooth bark; heavy moss coverage.

### `05_micro_leaf_venation.jpg` — leaf vein detail
*Source: `vivaan-trivedii-dq7jErOBJbo-unsplash.jpg`*

Hierarchical leaf venation (midrib → secondary → tertiary reticulated network). Calibrates the `vein_mask = smoothstep(0.45, 0.55, fbm8(wp * 12.0))` frequency.

**Mandatory:** ≥3 vein orders visible; vein color one tone lighter than lamina (`vein = float3(0.20, 0.35, 0.12)` vs `base = float3(0.12, 0.25, 0.08)`). **Decorative:** central midrib (recipe approximates texture, not structure).

### `06_specular_backlit_leaf.jpg` — leaf SSS target
*Source: `aris-rovas-vzyRn00d7fw-unsplash.jpg`*

Leaf with strong directional light: lit zone shows warm yellow-green transmission glow with darker vein silhouettes against luminous lamina; unlit zone shows reflected-light comparison in-frame. The §4.8 SSS reference.

**Mandatory:** warm yellow-green transmission tint (`sss_tint = float3(0.6, 0.8, 0.2)`); vein lines visible *through* translucent lamina; sharp lit-edge falloff (`pow(VdotL, 3.0)` shape). **Decorative:** leaf shape.

### `07_micro_lichen_crustose.jpg` — crustose lichen morphology
*Source: `Lecanora-pulicaris-large.jpg`*

Dense field of *Lecanora*-type crustose lichen on bark — the morphology the §4.7 lichen recipe approximates. Foliose *Parmelia* rosette on left edge serves as in-frame negative contrast.

**Mandatory:** flat thallus fused to bark, no lift; irregular non-gridded distribution (matches `worley3d(wp * 0.6)`); fine-scale apothecia within patches (sub-pixel at preset render distance). **Decorative:** apothecia color (single-tone lichen in current recipe; v2 could add two-tone via second Worley sample).

**Anti-traits:** the lifted lobed *Parmelia* on the left edge — what the recipe must NOT produce.

### `08_micro_bark_grain.jpg` — bark detail-normal scale
*Source: `natalia-blauth-taLff7nYoFA-unsplash.jpg`*

Heavy shaggy fissures, dark crevice shadows against tan ridges, no lichen. Drives the `triplanar_detail_normal(wp * 30, 0.04)` call in §4.7 — at preset render distance, this grain becomes the sub-pixel breakup that prevents POM bark from reading flat-with-cracks.

**Mandatory:** vertically-aligned fine fissures at high spatial frequency; dark crevice shadow contrast against ridge highlights. **Decorative:** species; crevice depth (POM handles the macro depth; this layer is normal-scale only).

### `09_lighting_golden_hour.jpg` — §5.6 lighting target
*Source: `shana-van-roosbroek-DVrfQj9Z32w-unsplash.jpg`*

Strong directional warm key from upper-frame, visible bokeh dust motes, back-lit subject with rim glow on upper edges, deep shadow falloff into foreground. The plant subject is incidental — the *lighting* is the slot.

**Mandatory:** warm key light, low angle (sun within 30° of horizon implied by shadow direction); rim/SSS glow on backlit edges; visible airborne particles (dust motes) — the §10.4 atmosphere layer wants these; cool ambient fill in shadow regions. **Decorative:** subject; specific aperture / bokeh character.

### `10_atmosphere_ground_fog.jpg` — atmosphere layer target
*Source: `getty-images-vbog-4jRjA4-unsplash.jpg`*

Single tree in field with dense mist below ~1.5m, clear air above, soft warm sky gradient. The fog gradient (densest at ground, fading by canopy line) matches the exponential-distance × altitude fog the §10.4 atmosphere should produce.

**Mandatory:** altitude-banded fog (dense low, clear high); soft warm sky gradient; tree silhouette emerges cleanly above fog line. **Decorative:** the specific tree species and silhouette.

### `11_palette_autumn.jpg` — default seasonal palette anchor
*Source: `martin-sanchez-EY0rawxI55o-unsplash.jpg`*

Aerial autumn forest showing the full hue distribution: deep green holdouts → yellow-green → orange → red. The IQ-cosine palette for the `autumn` variant should produce this distribution at varying saturation.

**Mandatory:** orange-red dominant, not yellow; per-tree color variation, not uniform palette; some green holdouts mixed in (real autumn is never 100% turned). **Decorative:** specific hue ratios — tune per per-tree LCG seed.

### `11b_palette_autumn_swatch.jpg` — supporting per-leaf color card
*Source: `jenna-anderson-UylXHkdG42s-unsplash.jpg`*

Hand-arranged green → yellow → orange → red leaf swatches. Most useful for tuning per-leaf color variation within a single tree's foliage clusters — the *intra-tree* palette spread, vs `11`'s *inter-tree* spread.

**Mandatory:** smooth hue transitions between adjacent leaves; saturation variation per-leaf, not uniform. **Decorative:** species; arrangement.

### `12_palette_winter.jpg` — winter variant palette
*Source: `ales-krivec-9WXJFrlAG24-unsplash.jpg`*

Pink-violet dawn gradient sky over hoar-frost-coated forest. Closer to the §10.4 brief ("hoar frost preferred over snow") than snow-load alternatives.

**Mandatory:** frost as the dominant surface, not snow weight; cool palette with warm sky accent; thicker aerial perspective than other variants. **Decorative:** species; sky gradient direction.

**Anti-traits:** snow-loaded conifers — winter variant operates on bare deciduous branches, not snow accumulation geometry.

### `13_painterly_target.jpg` — non-photoreal aesthetic anchor (placeholder)
*Source: `adele-cave-q0L-5a9FaEE-unsplash.jpg`*

Intentional camera motion blur producing soft color blocking and vertical compositional rhythm. Stands in for plein-air / late-Impressionist painterly target. Tells the implementation: soft-edged color masses, not crisp PBR realism.

**Mandatory:** soft edges throughout; vertical compositional rhythm matching tree trunks; color blocked rather than detail-rendered. **Decorative:** specific palette (this image is pink/green; the painterly *technique* is the takeaway, not the colors).

**Note:** Placeholder. A true plein-air or late-Impressionist tree painting (Pissarro, Cézanne, contemporary plein-air work) would be a stronger anchor — replace when sourced.

### `14_anti_reference.png` — what NOT to produce
*Source: `symmetric-fractal-tree.png`*

Perfect bilateral symmetry, uniform branch thickness, identical sub-branches at every recursion. Triggers Failed Approach #44.

**Avoidance traits:** mirror symmetry (break via per-branch hash jitter); uniform branch thickness (vary via `fbm8(branch_id)`); identical sub-trees at same depth (vary splay, length, twist per recursion seed).

---

## Cross-references

- `SHADER_CRAFT.md §10.4` — uplift plan
- `SHADER_CRAFT.md §4.7` — bark material recipe
- `SHADER_CRAFT.md §4.8` — translucent leaf material recipe
- `SHADER_CRAFT.md §5.6` — golden-hour lighting recipe
- `SHADER_CRAFT.md §8.3` — POM (parallax occlusion mapping)
- `SHADER_CRAFT.md §13` Failed Approach #44 — per-instance variation rule
- `ENGINEERING_PLAN.md` Increment V.10 — gating criteria
