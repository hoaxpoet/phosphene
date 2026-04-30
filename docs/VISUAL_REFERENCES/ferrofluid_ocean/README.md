# Visual References — Ferrofluid Ocean

**Family:** fluid
**Render pipeline:** ray_march + post_process
**Rubric:** full (gated by V.6 certification)
**Last curated:** <YYYY-MM-DD by Matt>

> **Stylization caveat for any session reading this folder.** Every photograph
> in this folder was sourced because it teaches a *specific* trait — material
> behavior, scale, lattice character, palette anchor, atmosphere, or lighting
> mechanic. None of them is a faithful rendering of "Ferrofluid Ocean as it
> should appear." Read each image only for the trait its annotation calls out,
> and *actively disregard* every other property of the image — particularly:
> studio gel lighting colors, foreground objects (sea stacks, basalt columns,
> vehicles, lotus veins, foam, beach rocks, lightning bolts, architectural
> skylines, underwater seafloors), and any palette that conflicts with
> §10.3.5's "distant fog cools to dark purple" intent. The preset's hue comes
> from mood-valence-tinted IBL ambient per **D-022**, not from any of these
> photographs. Direct-lit albedo is fixed by §4.6: `float3(0.02, 0.03, 0.05)`.
> Per-image disregard guidance follows the convention promoted to rule level
> in **D-065 §(c)** (`SHADER_CRAFT.md §2.1` step 2).

## Reference images

Files in this folder. Sub-letters (`01b`, `03b`) denote supporting images that
isolate a distinct trait of the same scale tier. Format: `NN_<scale>_<descriptor>.jpg`
where `<scale>` is one of `macro` / `meso` / `micro` / `specular` / `atmosphere` /
`lighting` / `palette` / `anti` and `<descriptor>` is a 2–4 word
lowercase_underscored descriptor. See `../_NAMING_CONVENTION.md`. References
should be ≤ 500 KB each; crop and compress before committing. The folder
exceeds the §2.1 "3–5 references" target under the composite-preset
allowance in **D-065 §(a)** — Ferrofluid Ocean's traits are not contained in
any single photographable subject, and each image isolates a distinct trait.

| File | Annotation (what to learn — and what to disregard) |
|---|---|
| `01_macro_horizon_dark_coast.jpg` | **Trust:** the horizon line; the dark-fluid expanse extending past frame; the brooding atmospheric mood; the sense of scope. This is what the §10.3 "Ocean" silhouette must *feel* like. **Disregard:** the basalt columns, sea stack, beach foreground rocks (the preset has *no* land features); the relatively bright sky (preset's distant fog is darker and cooler per §10.3.5 — see `07_*`). |
| `01b_macro_mirror_horizon.jpg` | **Trust:** the IBL-mirroring mechanic at landscape scale — every polished surface reflecting a tiny piece of sky per §10.3.5. The horizon-as-perfect-mirror reading is the strongest in the folder. **Disregard:** the bright daylight palette (opposite of preset intent); the vehicle, umbrella, and figures (obviously not preset content). |
| `02_meso_lattice_defects.jpg` | **Trust:** hexagonal close-pack of spike centers *with visible domain-warp defects* — no two spikes identical in spacing or tilt. Drives the §10.3.2 requirement that the lattice be domain-warped per §3.4 rather than perfectly regular. **Disregard:** the red + blue studio gel lighting; D-022 mood-tinted IBL provides hue, not gels. |
| `03_micro_spike_surface.jpg` | **Trust:** surface-scale grain along a single spike ridge; near-mirror metal between micro-features. This is the §10.3.3 `fbm8 × 15.0` normal perturbation reference. (This is a tight crop of the same source as `04_*` — same lighting setup, same stylization caveat.) **Disregard:** the purple gel. |
| `03b_micro_droplet_beading.jpg` | **Trust ONLY:** the Cassie-Baxter droplet beading on a hydrophobic surface. The bead-on-tip geometry, the surface-tension-dominated shape, the way droplets sit *on* rather than spreading. Drives the §10.3.3 "micro-droplets at spike tips on high amplitude" requirement. **Aggressively disregard:** the radial vein pattern emanating from the leaf center is **NOT** a directive about spike arrangement — spike-center distribution is hex-tile-with-defects per §4.6 and `02_meso_*`, never radial-from-a-hub. Also disregard: the green color, the leaf substrate, the leaf shape. |
| `04_specular_razor_highlights.jpg` | **Trust:** razor-sharp, near-mirror specular highlights running along each spike ridge; pitch-black troughs; the §4.6 `roughness = 0.08, metallic = 1.0` material character. **Hero reference frame** — the single most important match. **Disregard:** the purple gel (note: the *atmospheric* purple of §10.3.5 fog is in a similar family by coincidence, but this purple is direct-lit gel, not fog). |
| `05_anti_chrome_blob_AIGEN.jpg` | NOT this. Generic smooth-chrome blob with no Rosensweig spike character. The single most likely Claude Code shortcut: skipping the §4.6 hex-tile spike field and rendering a wavy reflective surface instead. *Every* trait of this image is anti — material is too uniform, surface too smooth, no detail cascade, no spike topology. **Note:** This image is AI-generated under the **D-065 §(b)** carve-out for the anti-reference slot. See Provenance for the replacement plan. |
| `06_palette_dark_metallic.jpg` | **Trust ONLY:** the lower-frame dark grit as a base palette / value swatch — the deep blue-black with cool undertone that anchors `mat_ferrofluid`'s `albedo = float3(0.02, 0.03, 0.05)`. **Aggressively disregard:** any white foam visible in the frame is **NOT** representative of any part of the preset's between-spike base — that surface is mirror-metal per §4.6, *not* foam-capped water. (Recommended: crop the foam out entirely before committing.) |
| `07_atmosphere_dark_purple_fog.jpg` | **Trust:** the deep purple-to-near-black gradient as a static atmospheric tint; atmosphere as material, sitting uniformly across the frame rather than originating from a discrete light source. This is the §10.3.5 "distant fog cools to dark purple" anchor — the closest available real-photograph reference for "purple fog as a static scene property." **Aggressively disregard:** the source image is from a thunderstorm; any sense of *active weather* (lightning, dramatic flicker, rolling cloud movement) is **NOT** what the §10.3.5 fog does. Fog is static volumetric tint, not a dynamic phenomenon. The lightning thread in the upper-left of the source is cropped out before commit; if any trace remains, ignore it. |
| `08_lighting_warm_key_dark_metal.jpg` | **Trust:** warm city-light reflections wrapping near-mirror dark metal at dusk. This is the closest real-photograph available for the §10.3.6 lighting recipe — *minimal direct lighting + strong IBL + one warm key* — applied to an actual near-black polished surface. The way the warm reflections curve across the surface (anisotropic-along-tangent, not isotropic) is also useful evidence for the §10.3.4 specular character. **Aggressively disregard:** the literal Chicago skyline reflected in the surface is **NOT** a directive about preset IBL content — the preset's IBL cubemap is a *sky environment* per §10.3.5/§10.3.6, not a city. Also disregard: anything specific to the sculpture's bean silhouette (not a directive about preset shape); the people and ground reflections at the bottom of the frame. **IP note:** the depicted sculpture is Anish Kapoor, *Cloud Gate* (2006), Millennium Park, Chicago — referenced for the IBL-on-dark-metal lighting mechanic only, never as an aesthetic target or basis for preset geometry. |
| `09_lighting_caustic_underglow_cyan.jpg` | **Trust:** the cyan tint of light filtered through a denser medium; the geometry of light shafts bending and softening as they traverse depth; the brightness gradient (brighter near the source-side surface, deeper cyan as the light attenuates). This drives the §10.3.6 "caustic underlighting from below surface (faint cyan) suggests depth" requirement and the §12.1 third material recipe. **Aggressively disregard:** the literal "looking up through water at sky" framing is **NOT** what the preset does — the preset is not underwater. Read this image as "light filtering up through the spike base from below, illuminating the underside of the lattice," not "camera positioned under the surface looking outward." Also disregard: any sense of bubbles, particulates, or organic matter in the water; the bright sun disc at the top of the frame (the preset has no such direct-light source). |

## Mandatory traits (per SHADER_CRAFT.md §12.1)

For this preset specifically, the following implementations are mandatory:

- [ ] **Detail cascade:**
  - **macro** = hex-tile spike lattice (`hex_tile` from `Utilities/Geometry`) with `spike_height ∝ stems.bass_energy_dev` per §4.6 + §10.3.1; the *scope* of the lattice extends to a horizon, not a contained dish (see `01_*` and `01b_*`)
  - **meso** = domain-warped spike-center positions via `warped_fbm` per §3.4 + §10.3.2; flow velocity driven by `stems.drums_beat` rising edges (see `02_*`)
  - **micro** = `fbm8(p * 15.0)` normal perturbation at amplitude `0.02`; hash-lattice micro-droplets at spike tips on high amplitude per §10.3.3 (see `03_*` for surface grain, `03b_*` for tip droplet behavior)
  - **specular** = `mat_ferrofluid` from §4.6 with anisotropic roughness aligned to spike axis per §10.3.4 (see `04_*`, hero reference; cross-check anisotropic-along-tangent character against `08_*`)
- [ ] **Hero noise function(s):** `fbm8` (8-octave, ≥ rubric minimum), `warped_fbm` (domain-warp for lattice defects), and a hash-lattice for micro-droplet placement. All from `Shaders/Utilities/Noise/` (V.1).
- [ ] **Material count and recipes:** `mat_ferrofluid` (§4.6, primary spike material) + `mat_ocean` (§4.14, between-spike fluid base reading deep absorption) + thin-film/caustic underlighting layer per §10.3.6 (faint cyan from below, suggests depth — see `09_*` for caustic geometry). All from `Shaders/Utilities/Materials/` (V.3). Plasma-family exemption does **not** apply; full 3-material requirement holds.
- [ ] **Audio reactivity (D-026 deviation primitives only):**
  - `stems.bass_energy_dev` → spike height (Rosensweig field strength)
  - `stems.drums_beat` → beat-surface ripple + lattice flow velocity (rising edges)
  - `stems.vocals_energy_dev` → surface tension / spike sharpness (lower tension = blunter)
  - `stems.other_energy_dev` → rotational flow direction
  - **No absolute-threshold patterns** (`f.bass > 0.22`, etc.) per D-026 — these are explicitly disallowed. FeatureVector fallbacks below.
- [ ] **Silence fallback (D-019 warmup):** at `totalStemEnergy == 0` the preset must still render. Crossfade via `smoothstep(0.02, 0.06, totalStemEnergy)` from FeatureVector proxies (`f.bass_att_rel` for spike height, `f.beat_bass` for ripple, `f.mid_att_rel` for surface tension, `f.treb_att_rel` for flow direction) to true stem routing. At true silence: lattice settles to a low-amplitude breathing height (~10% of nominal); IBL sky reflection still visible; distant purple fog still present (see `07_*`). **Non-black, non-static** at the lower bound.
- [ ] **Performance ceiling:** **6.0 ms p95 at 1080p Tier 2** (matches §10.3 budget and `complexity_cost.tier2 = 6.0` in JSON sidecar). Tier 1 cost TBD — IBL cubemap dominates and may force a half-res reflection pass on M1/M2.
- [ ] **Hero reference image:** `04_specular_razor_highlights.jpg`. The single most-important match: spike-ridge highlights must be narrow and near-mirror; troughs must read pitch-black; albedo must be nearly zero on the surface itself with all visible color coming from reflection + IBL.

## Expected traits (per §12.2 — at least 2 of 4)

- [ ] **Triplanar texturing on non-planar surfaces** — applicable: yes. Spike surfaces are strongly non-planar; uniplanar would stretch the micro-detail noise on near-vertical spike walls. Use `triplanar_normal` from `Utilities/PBR/Triplanar.metal` for the §10.3.3 surface-scale detail.
- [ ] **Detail normals** — applicable: yes. Combine the macro spike-shape normal with the §10.3.3 `fbm8(p * 15.0)` micro-detail normal via `combine_normals_udn` from `Utilities/PBR/DetailNormals.metal`. Without this the spikes look injection-molded.
- [ ] **Volumetric fog or aerial perspective** — applicable: yes. §10.3.5 specifies "distant fog cools to dark purple." Use `scene_fog` set against the §10.3 atmosphere intent (see `07_*` for the static-tint character — fog is *material*, not phenomenon); tint via D-022 mood-valence so negative valence biases the fog cooler/deeper-purple.
- [ ] **SSS / fiber BRDF / anisotropic specular** — applicable: yes. §10.3.4 calls for anisotropic reflection aligned with spike axes. The spike's tangent direction (radial outward from spike center) becomes the anisotropy axis. This is the third material's "personality" beyond the base `mat_ferrofluid`. (See `08_*` for how warm key light wrapping a curved near-mirror dark metal renders an anisotropic-along-tangent highlight rather than an isotropic blob.)

All four expected traits apply. Target ≥ 3 of 4 implemented for headroom against the rubric.

## Strongly preferred traits (per §12.3 — at least 1 of 4)

- [ ] **Hero specular highlight visible in ≥60% of frames** — applicable: yes. The §4.6 material at `roughness = 0.08` produces near-mirror highlights, and the warm key from §10.3.6 is positioned specifically to put a highlight on every spike tip from the camera angle (see `08_*` for the warm-key-on-dark-metal mechanic at landscape scale). This should be free given the lighting recipe.
- [ ] **Parallax occlusion mapping** — applicable: no. POM is for surface-displacement on flat-ish surfaces (bark, concrete walls). The spike lattice already provides 3D displacement via the SDF; layering POM on top would compound cost without visible benefit at this material's roughness.
- [ ] **Volumetric light shafts or dust motes** — applicable: optional. Could add faint above-surface dust motes as atmospheric texture, but the scene is intentionally minimal-direct-light — light shafts read poorly in IBL-dominated lighting. Defer unless the scene otherwise reads empty.
- [ ] **Chromatic aberration or thin-film interference** — applicable: yes. Thin-film interference on the spike surface (per §4.18 bioluminescent-chitin recipe but tuned for cool tones) gives the highlights a faint blue-to-cyan iridescent shift across viewing angle, which is the "hint of blue in highlights" called out in the §4.6 material comment. Worth the ~0.3 ms.

Target: implement hero specular (free) + thin-film interference. Skip POM and light shafts.

## Anti-references (failure modes specific to this preset)

What a Claude Code session is most likely to produce by accident; what this preset must NOT look like:

- **Generic chrome metaballs / smooth reflective blobs** with no spike character. The single most likely failure mode if the session shortcut to writing a Beer's-law or simple-displacement surface instead of implementing the §4.6 hex-tile spike field. See `05_anti_chrome_blob_AIGEN.jpg`.
- **Perfectly regular hexagonal lattice.** Skipping the §3.4 domain warp on spike centers produces a math-pattern look rather than a magnetic-fluid look. The defects in `02_meso_lattice_defects.jpg` are not optional.
- **Radial / hub-and-spoke spike arrangement.** A specific risk if the session over-reads the lotus-leaf vein structure in `03b_*`. Spike centers are hex-tile-distributed, not radial. The lotus is in the folder *only* for the droplet behavior at micro scale.
- **Foam-capped water as the between-spike base.** A specific risk if the session over-reads the upper portion of `06_*`, or pattern-matches generic "ocean" imagery. The §4.6 between-spike surface is *mirror-metal*, not water with surf.
- **Active weather effects in the fog.** A specific risk if the session over-reads `07_*` and reproduces lightning, dramatic flicker, or rolling cloud movement. The §10.3.5 fog is a static atmospheric tint — tone, not phenomenon.
- **Architectural reflections in the IBL.** A specific risk if the session over-reads `08_*` and renders a Chicago-style skyline or any other architectural environment in the IBL cubemap. The preset's IBL is a *sky environment* per §10.3.5/§10.3.6 — clouds, sky gradient, atmospheric haze, nothing built. Cloud Gate's reflection of architecture is an artifact of its location, not a directive.
- **Underwater scene framing.** A specific risk if the session over-reads `09_*` and constructs a literal underwater or sub-surface camera perspective. The caustic underlighting is read as light filtering *up* through the base of the spike lattice from below, contributing emission to the third material — not as a viewpoint or scene framing.
- **Soft / diffuse highlights.** Anything above `roughness = 0.15` reads as plastic. The §4.6 `roughness = 0.08` is non-negotiable for the "razor-sharp" character. See `04_specular_razor_highlights.jpg`.
- **Saturated direct-lit color.** The preset is not red, not purple, not any color in albedo. All visible color comes from IBL reflection + D-022 mood-tint on ambient. Direct albedo is `float3(0.02, 0.03, 0.05)`. The colored gels in `02_*` and `04_*` are studio photography, not palette directives.
- **Single-octave fBM in the spike field.** Failed Approach §35. The §4.6 `fbm8` jitter is the floor; lower octave counts produce visibly procedural lattice spacing.
- **Beat-driven primary motion.** Per `CLAUDE.md §Audio Data Hierarchy`, beat onsets are accents only; continuous energy (`*_energy_dev`) is the primary driver. A preset where spike height pumps only on `drums_beat` rising edges fails the "feels locked to the music" test.

## Audio routing notes

Specific audio→visual mappings that must hold (cite D-026 deviation primitives and D-019 stem warmup):

- **Spike height ← `stems.bass_energy_dev`** (continuous, primary). Fallback: `f.bass_att_rel`. Crossfade via `smoothstep(0.02, 0.06, totalStemEnergy)`. This is the Rosensweig "field strength" parameter; it must respond to bass envelope, not bass beats.
- **Beat-surface ripple ← rising edges of `stems.drums_beat`**. Fallback: `max(f.beat_bass, f.beat_mid)` (failed approach #26 — single-band keying misses snare-driven tracks). Ripple is an *accent* added on top of the continuous lattice motion, not the primary driver.
- **Spike sharpness / surface tension ← `stems.vocals_energy_dev`**. Fallback: `f.mid_att_rel`. Lower vocal energy → lower surface tension → blunter, broader spike profiles. Higher vocal energy → sharper, narrower spikes.
- **Rotational flow direction ← `stems.other_energy_dev`** (accumulated as a slow rotation of the domain-warp seed offset). Fallback: `f.treb_att_rel`. Slow drift, not jittery.
- **Distant fog hue ← D-022 mood valence**. Negative valence → deeper purple, cooler. Positive valence → warmer purple drifting toward magenta. Fog tint multiplies IBL ambient per `RayMarch.metal` `iblAmbient *= scene.lightColor.rgb`, so the shift is visible across the whole scene, not just direct-lit pixels. (See `07_*` for the static atmospheric character — fog is *material*, not phenomenon.)
- **Caustic underlighting (faint cyan) ← `f.spectral_centroid` (normalized 0–1)**. Brighter timbres → caustic shifts up the visible spectrum; darker timbres → caustic recedes toward deep blue. Treat as an emissive contribution from below the surface, suggesting depth per §10.3.6. (See `09_*` for caustic geometry — light filtering up through a denser medium, not a viewpoint.)

## Provenance

Curated by: Matt

Image sources:

- `01_macro_horizon_dark_coast.jpg` — Christopher La Rocca via Unsplash (`HCXpWtBcBIQ`). Reynisfjara, Iceland. Unsplash License.
- `01b_macro_mirror_horizon.jpg` — Matheus Oliveira via Unsplash (`NiooDGT-Zlk`). Salar de Uyuni, Bolivia. Unsplash License.
- `02_meso_lattice_defects.jpg` — Étienne Desclides via Unsplash (`N2vnFIujxJg`). Studio ferrofluid macro. Unsplash License.
- `03_micro_spike_surface.jpg` — Robert Stump via Unsplash (`9maYGqtWAnU`), tight crop. Same source as `04_*`. Unsplash License.
- `03b_micro_droplet_beading.jpg` — Clément Falize via Unsplash (`oOgPgMqTL8A`). Lotus leaf macro. Unsplash License.
- `04_specular_razor_highlights.jpg` — Robert Stump via Unsplash (`9maYGqtWAnU`), full frame. Unsplash License.
- `05_anti_chrome_blob_AIGEN.jpg` — **AI-generated** (Gemini / Imagen). Retained as the anti-reference under the **D-065 §(b)** carve-out for AI-generated anti-references in the `05_anti_*` slot, applicable when (a) the depicted failure mode is non-photographable and (b) sourcing a real-photograph or in-engine v1-baseline alternative is impractical. Both conditions hold here: a smooth-chrome-blob aesthetic is non-photographable as a *failure of ferrofluid* (real ferrofluid is never smooth, by definition), and no V.9 v1-baseline frame capture is available pre-implementation. **Replacement plan (per D-065 carve-out requirement):** this image will be replaced with a v1-baseline frame capture of the existing "HDR post-process chain over simple surface" implementation per §10.3 once it ships, before V.6 certification. All other images in this folder are real photographs.
- `06_palette_dark_metallic.jpg` — Amith K via Unsplash (`qWaeRQa43RA`). Black sand beach, lower-half crop only. Unsplash License.
- `07_atmosphere_dark_purple_fog.jpg` — Nathan Anderson via Unsplash (`f98cBlcpy8k`). Stormcloud at night. Cropped to remove the lightning thread visible in the upper-left of the source. Unsplash License.
- `08_lighting_warm_key_dark_metal.jpg` — Rafael Garcin via Unsplash (`ybxLZYR9tWU`). Subject: Anish Kapoor, *Cloud Gate* (2006), Millennium Park, Chicago. **IP note:** the photograph is licensed under the Unsplash License, but the depicted artwork remains © Anish Kapoor / Kapoor Studio. The image is referenced for its IBL-on-dark-metal lighting mechanic only — never as an aesthetic target, basis for preset geometry, or stylistic reference. The preset's silhouette is the §4.6 Rosensweig spike lattice, not a smooth bean. If session output begins to resemble *Cloud Gate*, that is itself a failure mode (over-reading geometric cues from `08_*`).
- `09_lighting_caustic_underglow_cyan.jpg` — Michael Worden via Unsplash (`a4Mj0QXXaOk`). Underwater view looking up at the sun through the water surface. Unsplash License.

All Unsplash photographs are CC0-equivalent under the Unsplash License (free for commercial use, no attribution required); attributions provided as courtesy.
