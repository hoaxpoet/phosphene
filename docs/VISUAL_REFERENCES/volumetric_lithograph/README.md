# Visual References — Volumetric Lithograph

**Family:** fluid
**Render pipeline:** `ray_march + post_process` *(mv_warp reverted per D-029 — VL's motion source is the forward camera dolly through audio-swept SDF terrain; stacking mv_warp on top fights it)*
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
| `01_macro_drainage_relief.jpg` | The closest analog to the procedural target output. Ridge networks, dendritic drainage patterns, and bimodal lit-ridge / shadowed-valley separation are MANDATORY traits — terrain must read like this from a high oblique camera. |
| `02_palette_woodblock_flat.jpg` | Hokusai, *Gaifū kaisei* (Red Fuji). Aesthetic anchor: limited tonal vocabulary, hard carved edges, flat color blocks separated by visible "cut paper" boundaries. The peak/valley smoothstep edges (0.50→0.55) and ridge-seam stratum (0.495→0.51) must read this graphically. |
| `03_lighting_morning_rake.jpg` | Caspar David Friedrich, *Der Watzmann*. Directional sidelight on a snow-capped peak above shadowed mid-ground hills. Demonstrates the four-layer detail cascade and how a single key light produces the bimodal contrast story. Foreground rock outcrop is the micro/specular reference. |
| `04_meso_braided_drainage.jpg` | Iceland Þórsmörk aerial. Dendritic braided drainage networks across moss-and-rock topography — what `ridged_mf` warped by `curl_noise` is supposed to produce. Drainage flow as the dominant meso-scale visual feature. |
| `05_meso_snow_in_gullies.jpg` | Aerial mountain with snow patches. Snow accumulating in gully drainage produces the bimodal smoothstep pattern naturally. Upper portion also demonstrates ridge recession into haze (secondary aerial-perspective lesson). |
| `06_atmosphere_aerial_perspective.jpg` | Canyonlands at dusk. Atmospheric haze grading butte silhouettes from foreground darkness through mid-distance to a desaturated horizon, with selective shafts of broken light. The aerial-perspective change called out as transformative in `SHADER_CRAFT.md §10.5.5`. |
| `07_meso_mesa_strata.jpg` *(optional, mesa-variant only)* | Sedona red rock with horizontal sedimentary stratification. Reference for the optional secondary displacement layer (`step(frac(h * 8.0), 0.5) * 0.05`) per §10.5.2. Skip from primary curation unless the geological-theme variant is being authored. |

**Hero reference:** `01_macro_drainage_relief.jpg`. If a render does not read like this image at the macro level, no amount of palette / atmosphere / lighting work will rescue it.

**Anti-reference:** *NOT YET CURATED — sourcing follow-up.* The needed image is a generic soft-fBM lumpy 3D terrain render — the failure mode `SHADER_CRAFT.md §10.5` calls out as "lumpy rather than mountainous." Until sourced, the absence of this image is the hole in the curation set.

## Mandatory traits (per SHADER_CRAFT.md §12.1)

For this preset specifically, the following implementations are mandatory:

- [ ] **Detail cascade:**
  - **macro** = `ridged_mf` heightfield warped by `curl_noise` for drainage flow, viewed via forward camera dolly. *(V.11 target per §10.5.1; current shipped uses `fbm8` heightfield with audio-time-swept third axis.)*
  - **meso** = optional secondary displacement adding mesa terraces (per-variant, §10.5.2); ridge-line seam stratum at smoothstep 0.495→0.51 reads as luminous "cut paper" highlight (shipped in v3, Increment 3.5.4.2).
  - **micro** = triplanar detail normal at 30× scale on steep faces per §8.2 (V.11 target).
  - **specular** = bimodal peak/valley materials. Peaks: `metallic=1, roughness ∈ [0.06, 0.18]`, albedo driven by IQ cosine palette `(0, 0.33, 0.67)` phase shift. Valleys: `albedo=0, roughness=1, metallic=0`. Specular variation via second `fbm8` to avoid uniform chrome (V.11 target per §10.5.4).
- [ ] **Hero noise function(s):** V.11 target — `ridged_mf` + `curl_noise` warp on heightfield, secondary `fbm8` for specular variation. Current shipped: `fbm3D` heightfield with audio-time-swept third axis via `s.sceneParamsA.x`.
- [ ] **Material count and recipes:** Three custom procedural materials (NOT cookbook recipes — VL's bimodal extremes don't fit `SHADER_CRAFT.md §4` cleanly): (1) ultra-matte black valley `albedo=0, roughness=1, metallic=0`; (2) IQ-palette-driven mirror peak `albedo=palette(...), roughness ∈ [0.06, 0.18], metallic=1`; (3) ridge-seam stratum at narrow smoothstep window with low metallic for "cut paper" highlight. Document this exception in V.6 certification — VL is the canonical case for procedural-material certification path.
- [ ] **Audio reactivity (D-026 deviation primitives mandatory):**
  - Continuous terrain amplitude: `f.bass_att + 0.4 × f.mid_att` (attenuated bands; larger features, slower morph). Never raw `f.bass` or `f.mid` — saturated 86% of the time on busy mixes (Increment 3.5.4.1 finding).
  - Selective beat: `pow(f.beat_bass, 1.2) × 1.5` — only strong kicks register.
  - Palette flare on beat: × 1.5 brightness multiplier — peaks push to 2.5× albedo on strong kicks, bloom-visible.
  - Ridge seam strobe: `× (1.4 + beat × 2.0)` — the cut-line itself strobes at up to 3.4× brightness.
  - Coverage shift on beat: 0.03 smoothstep delta (small; geometrically stable).
  - Transient terrain kick in `sceneSDF`: `f.beat_bass × 0.35` added to attenuated baseline amp.
  - D-019 stem warmup `smoothstep(0.02, 0.06, totalStemEnergy)` is the standard pattern, but VL's `sceneSDF` / `sceneMaterial` do **not** have `StemFeatures` in scope (preamble forward-declarations omit it — same as KineticSculpture). VL is FV-only throughout; the warmup applies only at call sites that already have stems.
- [ ] **Silence fallback:** at `totalStemEnergy == 0`, terrain amp falls to FV proxies which AGC-normalize to ~0.5 at silence. Heightfield retains its slow audio-time-swept morph (third noise axis driven by `s.sceneParamsA.x`) — never freezes. No beat flare, no palette pumping. Gated by `SilenceFallbackTests`.
- [ ] **Performance ceiling:** ~5.0 ms p95 at 1080p Tier 2 (M3+) per `SHADER_CRAFT.md §10.5` budget. Must match `complexity_cost.tier2` in `VolumetricLithograph.json`.
- [ ] **Hero reference image:** `01_macro_drainage_relief.jpg`.

## Expected traits (per §12.2 — at least 2 of 4)

- [ ] Triplanar texturing on non-planar surfaces — applicable: yes (V.11 target per §10.5.3 — kills stretched texels on steep faces; not yet shipped).
- [ ] Detail normals — applicable: yes (V.11 target per §10.5.3 — triplanar detail normal at 30× scale).
- [ ] Volumetric fog or aerial perspective — applicable: yes (V.11 target per §10.5.5). Currently `scene_fog: 0` truly disables fog (sky pixels tinted by `scene.lightColor.rgb` via the `sceneParamsB.y > 1e5` sentinel from MV-0). V.11 will add aerial perspective via depth-graded fog `lerp(warm_sky, cool_depth, depth_factor)` — the single most transformative addition.
- [ ] SSS / fiber BRDF / anisotropic specular — applicable: no (no organic or fibrous surfaces; PBR metallic on rock peaks via `cook_torrance` + `fresnel_schlick` is the closest variant and is already in place).

Expected count post-V.11: **3 of 4.** Pre-V.11: 0 of 4 (waiver pending V.11 implementation).

## Strongly preferred traits (per §12.3 — at least 1 of 4)

- [ ] Hero specular highlight visible in ≥60% of frames — applicable: yes. Peak metallic albedo with IQ palette already produces high-frequency specular response on bright peaks; will improve further with V.11 specular variation pass.
- [ ] Parallax occlusion mapping on at least one surface — applicable: no. POM cost is high and the linocut aesthetic does not require depth illusion at the surface scale.
- [ ] Volumetric light shafts or dust motes — applicable: yes (V.11 §10.5.7 optional drifting cloud shadows via screen-space density sampling produce a related effect — cloud shadow patches modulating key light intensity on terrain).
- [ ] Chromatic aberration or thin-film interference — applicable: no. Clashes with the carved-line bimodal aesthetic.

Strongly-preferred count post-V.11: **2 of 4.** Pre-V.11: 1 of 4.

## Anti-references (failure modes specific to this preset)

What a Claude Code session is most likely to produce by accident; what this preset must NOT look like:

- **Lumpy soft-fBM "rolling hills" terrain.** The v1–v3 failure mode. Reads as topographically uninteresting because there is no ridge structure. Cure: use `ridged_mf`, not raw `fbm8`, for the hero heightfield.
- **Sepia / grayscale palette.** The v1 failure mode — pure-grayscale palette read as sepia, not psychedelic. Cure: IQ cosine palette `(0, 0.33, 0.67)` phase shift drives peak albedo with `noise × 0.45 + audioTime × 0.04 + valence × 0.25`.
- **Saturated fog haze across upper third of frame.** The v1 failure mode. Caused by the shared infra fog-fallback bug — `scene_fog: 0` re-used `sceneParamsB.y` default 0, making `fogFactor` saturate to 1.0 for any terrain hit. Fixed in `PresetDescriptor+SceneUniforms.makeSceneUniforms()` (Increment 3.5.4.2). Do not reintroduce.
- **Beat-driven coverage flicker.** The v1 failure mode where `lo -= drumsBeat × 0.18` flickered the peak/valley boundary every frame because beat fallback was saturated. Cure: keep smoothstep window geometrically stable; transients push palette into HDR bloom (palette flare), not coverage geometry.
- **Camera + mv_warp paradigm stacking.** The MV-2 → D-029 failure mode. mv_warp's UV-space accumulator pinned stale pixels to screen positions that no longer matched the re-projected world, producing heavy vertical smear (worst at rest). VL's motion source is camera flight only; mv_warp must NOT be re-added (D-029).
- **Single-band beat keying that misses snare-driven tracks.** The pre-3.5.4 failure mode. VL operates FV-only, and the v3 implementation uses `pow(f.beat_bass, 1.2) × 1.5` deliberately — the kick-only signal produces the desired "ink stamp" cadence; mid/composite would over-trigger on busy percussion. This is a VL-specific exception to CLAUDE.md's `max(beat_bass, beat_mid, beat_composite)` general rule.

## Audio routing notes

Specific audio→visual mappings that must hold (D-026 deviation primitives, D-019 stem warmup):

- Primary terrain amplitude: `f.bass_att + 0.4 × f.mid_att` (attenuated bands per D-026; never raw `f.bass` / `f.mid`).
- Secondary terrain morph: audio-time-swept third axis of the 3D fBM noise via `s.sceneParamsA.x` accumulator — VL's continuous-energy compound motion comes from camera traversal of this evolving field, not from feedback warp.
- Beat fallback: `pow(f.beat_bass, 1.2) × 1.5`. VL-specific exception to `max(beat_*)` general rule (see anti-references).
- Palette: `palette(noise × 0.45 + audioTime × 0.04 + valence × 0.25)` via IQ cosine palette `(0, 0.33, 0.67)` from `ShaderUtilities.metal:576`. On beat, multiplied × 1.5 for HDR bloom flare.
- Ridge seam stratum strobe: `× (1.4 + beat × 2.0)` — third material reads as the brightest stratum during transients.
- Smoothstep coverage shift on beat: 0.03 (small; never the primary beat story).
- D-019 stem warmup: standard pattern applies at call sites that have `StemFeatures`. VL is FV-only inside `sceneSDF` / `sceneMaterial`.

**Removed audio routings (do not resurrect without re-evaluating D-029 paradigm-stacking):**

- ~~`mv_warp` melody zoom breath, valence rotation, decay 0.96~~ — reverted with mv_warp pass per D-029.
- ~~`vl_pitchHueShift()` — `vocalsPitchHz` → IQ palette hue ±0.15~~ — removed with mv_warp; lived inside `mvWarpPerFrame`.
- ~~`beat_phase01 > 0.80` anticipatory pre-beat zoom (`approachFrac × 0.004`)~~ — removed with mv_warp; lived inside `mvWarpPerFrame`.

Any future increment that wants to re-add pitch-driven palette modulation or beat-phase anticipation needs a non-mv_warp implementation path. Pitch hue could move directly into `sceneMaterial` (since `f.vocalsPitchHz` is reachable via `StemFeatures` if the preamble is extended); beat-phase anticipation could move into the camera dolly speed or into the smoothstep window.

## Provenance

Curated by: Matt
Image sources:

- `01_macro_drainage_relief.jpg` — Unsplash (a-chosen-soul) — stylized topographic shaded-relief render
- `02_palette_woodblock_flat.jpg` — Katsushika Hokusai, *Gaifū kaisei* (Red Fuji), c. 1830–32, public domain
- `03_lighting_morning_rake.jpg` — Caspar David Friedrich, *Der Watzmann*, 1824–25, public domain (Alte Nationalgalerie, Berlin)
- `04_meso_braided_drainage.jpg` — Unsplash (Thomas de Luze) — Iceland Þórsmörk aerial
- `05_meso_snow_in_gullies.jpg` — Unsplash (Taiki Ishikawa) — aerial mountain with snow patches
- `06_atmosphere_aerial_perspective.jpg` — Unsplash (Casey Horner) — Canyonlands at dusk
- `07_meso_mesa_strata.jpg` *(optional)* — Unsplash (Valentin Wechsler) — Sedona red rock stratification
- `<NN>_anti_<...>.jpg` — *NOT YET SOURCED.* Need a generic soft-fBM lumpy 3D terrain render to anchor the primary failure mode.

Unsplash images are licensed under the Unsplash License (free for commercial use, no attribution required, but credited above for transparency). Public-domain artworks have no licensing constraint.
