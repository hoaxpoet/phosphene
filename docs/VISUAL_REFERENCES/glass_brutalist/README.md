# Visual References — Glass Brutalist

**Family:** geometric
**Render pipeline:** ray_march + ssgi + post_process
**Rubric:** full (gated by V.6 certification)
**Last curated:** 2026-04-30 by Matt

## Reference images

Files in this folder, numbered in priority order. Each name encodes the trait it
demonstrates. Format: `NN_<scale>_<descriptor>.jpg` where `<scale>` is one of
`macro` / `meso` / `micro` / `specular` / `atmosphere` / `lighting` / `palette` / `anti`
and `<descriptor>` is a 2–4 word lowercase_underscored descriptor. See
`../_NAMING_CONVENTION.md`. References should be ≤ 500 KB each; crop and compress
before committing.

| File | Annotation (what to learn from this image) |
|---|---|
| `01_macro_corridor_axis.jpg` | Forward-perspective corridor with eye-level camera; warm raking afternoon light from above; board-form pillars with tie-rod rhythm; deep recession; travertine floor in lit warm tones against cool concrete. Disregard: distant figure, exterior plaza visible at end, exact column spacing. |
| `02_micro_concrete_planks.jpg` | Board-form concrete surface — plank impressions running vertically; tie-rod hole near top; aggregate pitting; weathering streaks; subtle staining. Disregard: rust hue (decorative); exact plank widths. |
| `03_meso_panel_articulation.jpg` | Vertical window-slit rhythm in back room; horizontal plank banding; panel seams between concrete pours. Disregard: circular cutout, mosaic floor, blue-and-gold inlay, stepped detail, Scarpa-specific decorative grammar. |
| `04_specular_pattern_glass_surface.jpg` | Voronoi cellular dimple pattern; hex-tending cell topology with domain defects; sharp inter-cell ridges; smooth domes within cells. Disregard: warm/cool gradient (lighting artefact); exact cell scale (tunable). Drives `mat_pattern_glass` recipe per SHADER_CRAFT.md §4.5b. |
| `05_specular_pattern_glass_panel.jpg` | Glass panel at architectural scale diffuses subject silhouette into a soft, readable shadow; surface glows from transmitted light (SSS approximation in recipe). Disregard: brick wall, ginkgo plant, garden context, metal panel mounts, pyramidal roof. |
| `06_atmosphere_dust_shaft.jpg` | Volumetric light shaft with visible particulate haze inside the beam; hard-edge cone; dust motes catching light; dark surrounding interior; small high aperture as source. Disregard: timber barn structure, cobwebs, specific window shape. |
| `07_lighting_raking_shadow.jpg` | Diagonal raking-shadow gradient across board-form concrete; lit portion shows formwork + tie-rod texture clearly; shadowed portion goes deep cool; sharp shadow edge. Disregard: open-sky composition (preset is interior); exterior framing. |
| `08_anti_clear_office_glass.jpg` | NOT this — clear glass (zero diffusion); copper-toned metal framing; lacquered wood floor; commercial drop-ceiling; sharp reflections without haze; cityscape view; corporate styling. Every property of this image is anti. |

## Mandatory traits (per SHADER_CRAFT.md §12.1)

For this preset specifically, the following implementations are mandatory:

- [ ] **Detail cascade:** macro = corridor perspective + pillar rhythm, meso = panel seams + horizontal plank banding, micro = board-form plank impressions + tie-rod holes + aggregate pitting, specular = pattern-glass cell-edge ridges + concrete grunge-driven roughness variation
- [ ] **Hero noise function(s):** `fbm8` (concrete grunge + height-gradient normals) + `worley_fbm` (concrete aggregate variation) + `voronoi_f1f2` (pattern-glass cells)
- [ ] **Material count and recipes:** `mat_pattern_glass` (§4.5b, fins) + `mat_concrete` (§4.3, walls/pillars/beams/ceiling) + `mat_marble` (floor, travertine-approximating per Salk reference 01) — minimum 3
- [ ] **Audio reactivity:** preset-specific routings only (see Audio routing notes below); D-026 deviation primitives where applicable; no architecture geometry modulation per D-020
- [ ] **Silence fallback:** corridor lit by ambient IBL only; no dust motes; glass fins at neutral X; fog at resting density. D-019 warmup via `smoothstep(0.02, 0.06, totalStemEnergy)` on all stem-driven parameters
- [ ] **Performance ceiling:** ≤ 5.0 ms p95 at 1080p Tier 2 (matches `complexity_cost` JSON sidecar)
- [ ] **Hero reference image:** `04_specular_pattern_glass_surface.jpg` for material fidelity; `01_macro_corridor_axis.jpg` for overall scene read

## Expected traits (per §12.2 — at least 2 of 4)

- [ ] Triplanar texturing on non-planar surfaces — applicable: yes, on pillars and back wall where world-space UVs would seam
- [ ] Detail normals — applicable: yes, board-form plank impressions on all concrete surfaces (mandatory for M3)
- [ ] Volumetric fog or aerial perspective — applicable: yes, interior haze controlled by `f.treb_att_rel` (scattering) on top of shared-path `f.arousal`-driven fog far
- [ ] SSS / fiber BRDF / anisotropic specular — applicable: yes, approximated internal scattering on pattern-glass fins via `m.emission` term in `mat_pattern_glass`

## Strongly preferred traits (per §12.3 — at least 1 of 4)

- [ ] Hero specular highlight visible in ≥60% of frames — applicable: yes, raking key light on concrete pillars + cell-edge ridges on pattern glass
- [ ] Parallax occlusion mapping on at least one surface — applicable: yes, on concrete walls for plank impression depth
- [ ] Volumetric light shafts or dust motes — applicable: yes, overhead aperture shafts with `f.bass_att_rel`-driven motes
- [ ] Chromatic aberration or thin-film interference — applicable: optional, chromatic fringing at glass-fin silhouette

## Anti-references (failure modes specific to this preset)

What a Claude Code session is most likely to produce by accident; what this preset must NOT look like:

- Smooth Ando-style concrete (uniform, featureless surface) — Glass Brutalist commits to Salk/Scarpa board-form with visible plank impressions, tie-rod holes, and aggregate pitting.
- Clear, transparent glass fins with sharp reflections — fins must read as patterned/diffusing, not see-through office glass (see `08_anti_clear_office_glass.jpg`).
- Light shafts that read as solid cones — without particulate haze inside the beam and without falloff toward the periphery, a "shaft" collapses into untextured geometry. The shaft is volumetric or it isn't a shaft (`06_atmosphere_dust_shaft.jpg` is the contract).
- Wet concrete variant (`mat_wet_stone`) — explicitly out of scope for V.12; keep wet-stone material reserved for other presets.
- Geometry deformation with audio — the corridor architecture has implied permanence; only the glass-fin X-position may shift with bass (D-020).

## Audio routing notes

Three tiers, in order of authority. Rules cite D-026 deviation primitives, D-020 architecture-stays-solid, D-019 stem warmup, and the per-frame ray-march modulation in `ARCHITECTURE.md`.

**Tier 1 — Shared `drawWithRayMarch` path handles automatically.** These run for every ray-march preset and Glass Brutalist must not duplicate them in its fragment shader:

- Key light intensity pulses on `max(beatBass, beatMid, beatComposite)` — corridor brightens on any-band beat onset.
- Light + IBL ambient color tints with `f.valence` — warm amber on positive valence, cold blue on negative.
- Fog far plane modulates with `f.arousal` — calm expands the visible horizon, frantic closes it in.
- Camera dolly advances forward at 2.5 u/s (Glass Brutalist's preset-specific dolly speed; decoupled from `accumulatedAudioTime`).

**Tier 2 — Preset-specific D-020 carve-out.** The single sanctioned geometry parameter:

- Glass-fin X-position offset driven by `f.bass_dev` (positive deviations only). Routed via `SceneUniforms.cameraForward.w` so `sceneSDF` and `sceneMaterial` see the same value (D-021).

**Tier 3 — Preset-specific atmosphere / particle parameters.** Read from `FeatureVector` in the fragment shader; D-019 warmup gate on all stem-derived signals:

- Dust-mote density inside the volumetric shaft: `f.bass_att_rel`.
- Volumetric shaft scattering coefficient (distinct from the shared-path key-light intensity in Tier 1): `f.treb_att_rel`.
- Optional subtle light flicker: `stems.drums_energy_dev` after D-019 warmup, small amplitude, no geometry effect.

**Forbidden** (D-020): any modulation of walls, pillars, beams, floor, or ceiling SDF. Architecture is static.

## Provenance

Curated by: Matt
Image sources: Unsplash (ahmed, annie-spratt ×2, vincent-y-usa, mika-baumeister, tarun-hirapara, getty-images); Wikimedia Commons (Carlo Scarpa / Tomba Brion). Photographic, not AI-generated.
