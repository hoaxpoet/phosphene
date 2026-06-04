# Nimbus — Visual Reference Set & Trait Matrix

> **Status:** Gate 0 (intake) + Gate 1 (trait extraction) for the first **Volumetric**-family preset.
> **Working name:** *Nimbus* — provisional. Rename the folder slug if it changes.
> **Place at:** `docs/VISUAL_REFERENCES/nimbus/`, alongside the eleven numbered image files.
> **Lint:** `swift run --package-path PhospheneTools CheckVisualReferences` (`jpg`|`png`, ≤ 500 KB, `NN_<scale>_<descriptor>` names).

## How to read this set (read before authoring)

None of these images is a faithful rendering of "Nimbus as it should appear." They are sourced smoke, ink, cloud, and iridescence photographs, each chosen to isolate **one** trait. Read each image only for the trait its annotation calls out, and obey the *actively disregard* column — real photography is full of structural cues that read as directives but are not (the descending ink column in `01` is not a directive that the body falls; the one-sided light in `08` is not a directive that the source sits in a corner). This is the Failed Approach #63 / #35 discipline: **do not author a Nimbus session without reading this README cover-to-cover and each annotation, and cite specific reference traits in design comments where they motivate a choice.** Mid-session sanity checks must be side-by-side comparisons against the named images, not self-judgments of "looks reasonable."

## Gate 0 — Intake

| Field | Value |
|---|---|
| Preset name | Nimbus (provisional) |
| Family | Volumetric (first in family) |
| Emotional / musical role | A single luminous gaseous body suspended in a cosmic void — an expressive co-performer that breathes with energy, ignites with light on the beat, and shifts its colour-mood across sections. Shows restraint at silence. |
| Render pipeline | Single-pass 2D direct-fragment volumetric ray-march. Compose `Utilities/Volume/{Clouds, ParticipatingMedia, HenyeyGreenstein}`; density shape from `FBM` + `voronoi_smooth`. **No engine changes — pure preset increment.** |
| Camera | Fixed vantage. No flythrough. |
| Performance target | **Tier 2 (M3+) — supported tier:** 60 fps @ 1920×1080. Full-frame **p95 ≤ 16 ms** (`FrameBudgetManager` Tier 2 threshold); **per-preset GPU ≤ 7 ms** (`SHADER_CRAFT §9.3` Tier 2 ceiling); drops (> 32 ms) ≤ 1 % over a representative 60 s window. Headroom lever: half-res volumetric march + MetalFX Temporal upscale (§9.2). Under-budget degradation rides `reducedRayMarch` (Nimbus has no SSGI / separate bloom pass, so those ladder rungs are no-ops). First implementation phase validates the budget with `MTLCounterSet.timestampGPU` on real Tier 2 silicon (Arachne V.8.1 precedent). **Tier 1 (M1/M2) — excluded:** a single-pass volumetric ray-march exceeds the Tier 1 ceiling (5 ms / preset, **no volumetric clouds**, §9.3). `complexity_cost.tier1` is set above the Tier 1 budget so the Orchestrator drops Nimbus on M1/M2; no degraded Tier 1 fallback in v1 — a march cut to fit 5 ms reads as flat fog, which is the `05_anti_uniform_fog` failure. |
| Known constraints | 2D presets have no depth buffer — self-occlusion and aerial depth are computed inside the march (acceptable). God-rays as a separate composited pass and depth-aware DoF are deferred infrastructure, **out of scope for v1.** |

## Reference manifest — target slots

Three-category annotations per D-065(c): **mandatory** (must show), **decorative** (allowed, not a directive), **actively disregard** (present in the image but must be ignored by sessions reading the folder).

| File | Mandatory — trust these | Decorative | Actively disregard |
|---|---|---|---|
| `01_macro_coherent_body.jpg` | One coherent luminous body: a dense, brighter **core** falling off to soft wispy edges; cool-pole colour on a **true black void**; clear negative space framing the mass; lobed interior that reads as volume / interiority. | Exact turquoise hue (palette is set by `06_*`); the specific lobe arrangement. | The vertical **descending-column** framing — Nimbus's body is suspended and roughly centred, not a falling plume. Ink-in-water cues: refractive shimmer, the faint dripping thread, any tank edge. The downward motion direction. *This is ink, read for form and core-to-edge falloff, not as a literal liquid.* |
| `02_meso_billow_and_filament.jpg` | Mid-scale internal structure: rounded **billows and density lobes**; nested density with self-occlusion (nearer lobes shadow those behind → depth); soft cellular boundaries between billows. | Overall billow count / arrangement. | The teal-tan colour cast (palette from `06_*`). The frame-filling crop with no void — **this image teaches scale and internal structure only**, not composition. Any reading as an upright cumulus. |
| `03_micro_wisp_feathering.jpg` | Fine periphery **feathering** — edges fraying into delicate tendrils, never a hard cutoff; curl / vortex detail at the wisp tips; thin filaments dissolving into void. | The near-monochrome white (colour from `06_*`). | The single rising-ribbon composition and its thin stem — **this image teaches edge texture at the periphery**, not overall body shape. Do not read "one thin ribbon" as the macro form. |
| `08_lighting_internal_glow.jpg` **(HERO)** | A light source **within / behind** the medium: forward-scatter brightening toward the source, a silver-lining rim on near edges, a soft halo bleeding outward, falloff from a lit region into shadowed void. Glow **earned by scattering through the medium**, not a bloom sticker. | The cool blue tone (palette from `06_*`). | The **one-sided composition** — the body runs off the right edge and the source sits upper-right; Nimbus's glow is internal and centred, so do not read "light enters from one corner" as the layout. Any lens flare. The source disk itself (the *scattering behaviour* is the trait, not the lamp). |
| `08_lighting_self_shadow.jpg` *(optional)* | A dense volume with **front-to-back self-shadowing** — lit upper surfaces, shadowed undersides and cores — so the body reads as genuinely 3D; occlusion between billow masses. | — | The desaturated storm-grey (palette from `06_*`). The literal storm-cloud / sky reading. The frame-filling crop. Surface-shading cues — the body is gas, not a lit solid. |
| `06_palette_cool_baseline.jpg` **(authored swatch — see Provenance)** | **Low pole.** Hue family deep, desaturated indigo / violet at low saturation and low luminosity — the calm, low-valence / low-energy resting mood, and the colour the body collapses toward at the silence floor. | — | The smooth radial form — this is a colour chip, not a shape or composition reference. |
| `06_palette_warm_peak.jpg` **(authored swatch — see Provenance)** | **High pole.** Warm-white → gold → amber ramp at high luminosity and moderate-high saturation — the ignited, high-valence / high-energy peak. The faint cool accent is for contrast only. | — | The smooth gradient form. Do not read the faint cyan edge as a mandated second colour. |

## Mandatory-traits checklist (a session must produce all of these)

- A **single** coherent body, roughly centred, with clear void / negative space around it — never multiple bodies, scattered dust, or a frame-filling soup.
- A **denser, brighter core** with soft, feathered edges dispersing into the void.
- Internal **billow + lobe + filament** structure with visible depth / self-occlusion.
- Glow that is **internal forward-scatter** (silver rim + halo earned in the march), not a post bloom.
- Colour confined to the **cool ↔ warm valence axis** between the two `06_*` poles — never full-spectrum.
- At the **silence floor**, a dim held breath with faint residual haze — *not* pure black (clears the silence-non-black invariant).

## Anti-references (failure modes — every trait is anti)

Per D-065(b), an anti-reference has **no partial-trust read**: the whole image is the thing to avoid. All four below are real photographs, so the `_AIGEN` carve-out and its replacement-plan requirement do not apply.

- `05_anti_uniform_fog.jpg` — flat, uniform, structureless grey haze with no density variation, no core, no void. The dead-soup collapse. *(The treeline / horizon is incidental scene, not part of the lesson.)*
- `05_anti_solid_surface.jpg` — gas reading as a hard, opaque, carved **cotton-ball** surface; translucency and interiority lost. *(Blue sky incidental.)*
- `05_anti_literal_sky.jpg` — daytime blue sky with horizon-implying cumulus; breaks the cosmic void. Nimbus is a body suspended in dark space, never a sky.
- `05_anti_oilslick_rainbow.jpg` — over-saturated, full-spectrum rainbow iridescence. The palette must stay on the cool↔warm axis, never every hue at once.

## Gate 1 — Trait matrix

| Trait | Target |
|---|---|
| **Macro composition** | Single coherent luminous body, centred, surrounded by void; bright core, dispersing wispy edges; clear negative space. |
| **Meso structure** | Billows + lobes + filaments + soft cellular voids (`voronoi_smooth`); nested density with depth / occlusion. |
| **Micro detail** | Feathered, fraying edges; turbulent wisp texture; fine shimmer surface (driven by the high band). |
| **Material** | N/A — gaseous participating medium. "Material" here = scattering response (single-scatter albedo + phase anisotropy); see Lighting. |
| **Lighting** | Internal source(s); strong forward scatter → silver rim + halo; self-shadowing; glow **earned in the march**, not a bloom sticker. |
| **Motion** | Fixed camera. Slow internal evolution at rest; energy-driven mass swell; beat-locked light bloom / decay; slow mood-driven palette + turbulence drift; discrete section reorganisation. Laminar (low arousal) ↔ churning (high). |
| **Audio-reactive** | Four orthogonal channels, separated by timescale — below. |
| **Failure modes** | Uniform fog; solid / opaque look; over-saturation / clipping; literal sky; multiple bodies / scattered dust; pure-black-at-silence. |
| **Anti-reference warnings** | The `05_anti_*` slots above. |

### Audio-reactive channels (the four kept)

1. **Breath of the body** *(continuous / slow)* — broadband attenuated energy, via deviation primitives (D-026), → mass density + luminosity. Coarse band → bulk; high band → edge shimmer. **Silence floor:** energy → 0 collapses the body to a dim held breath with a faint residual haze.
2. **Pulse of light** *(transient / fast)* — composite beat onset → a single internal ember flare (bloom + decay); the forward-scatter rim is the tell. Optional: substitute the drum-stem onset when stems are warm (D-019). Accent only.
3. **Mood of the section** *(section-length / very slow)* — valence → palette temperature; arousal → turbulence character. Smoothed in preset state — **never** written through `setFeatures` (Failed Approach #25).
4. **Turn of the page** *(rare / discrete)* — a predicted section boundary → one reorganisation event (new core, palette shift, turbulence step).

**Cut for v1** (reactive but chaotic or off-axis): per-stem role assignment (fractures the one body), vocals-pitch → hue, spectral-centroid as its own channel, anticipatory beat-phase breathing, camera / time drift.

## Provenance & compliance

Sources (Unsplash, free-to-use / no attribution required; recorded here for provenance and re-sourcing):

| Slot file | Source |
|---|---|
| `01_macro_coherent_body.jpg` | Bilal O. — `2W0AZVlVm3U` |
| `02_meso_billow_and_filament.jpg` | George C. — `ICVFDQcUw6o` |
| `03_micro_wisp_feathering.jpg` | Thomas Stephan — `bVlz5gv18Qk` |
| `08_lighting_internal_glow.jpg` | SJ Objio — `s-aktnfUOjs` |
| `08_lighting_self_shadow.jpg` | Anandu Vinod — `pbxwxwfI0B4` |
| `05_anti_uniform_fog.jpg` | Mykola Kolya Korzh — `ii_impaRM3M` |
| `05_anti_solid_surface.jpg` | Robert Koorenny — `hYUECF9ZX04` |
| `05_anti_literal_sky.jpg` | Getty Images (via Unsplash) — `aSidViLxHpQ` |
| `05_anti_oilslick_rainbow.jpg` | Daniel Olah — `pCcGpVsOHoo` |
| `06_palette_cool_baseline.jpg` | **Authored** — procedural radial gradient (Pillow), not a photograph or in-engine capture. |
| `06_palette_warm_peak.jpg` | **Authored** — procedural radial gradient (Pillow). |

> **Palette-slot provenance — resolved (D-139).** D-065(b) requires real photography or controlled in-engine capture for non-anti slots, including `06_palette_*`. The two palette files are authored procedural gradients, retained here by scoped exception **D-139**: a palette slot's job is to fix the colour-mood target (hue / saturation / luminosity), and a clean authored swatch isolates that target without smuggling a specific medium's form into a slot whose only job is colour — the right tool for these two slots specifically. The exception is Nimbus-`06_palette_*`-only; D-065(b) real-photography / in-engine-capture remains mandatory for every other slot and preset. `CheckVisualReferences` is unaffected (it enforces filename / size / format, not provenance).

## What this set is *not* authority on

The cosmic framing is an aesthetic target, not an astrophysics claim. Where a reference is a smoke, ink, or cloud photo, trust the **form, glow, and colour relationships** its annotation names; actively disregard the source medium's incidental cues — refraction, tank edges, sky/horizon context, motion direction, and any scale cue implying a literal place. This is the D-065(c) discipline; the more frames a folder accumulates, the more confounders a session ingests without these explicit disregards.
