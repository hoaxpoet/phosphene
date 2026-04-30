# Visual References — Kinetic Sculpture

**Family:** abstract
**Render pipeline:** ray_march + post_process
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
| `01_macro_radiating_strand_lattice.jpg` | Hero macro silhouette: multiple cones of taut radiating members converging on a central spherical hub at architectural scale; the composition KS is ultimately reaching for. Disregard the warm gold tonality — that's lighting, not material directive. (Lippold, *Flight*, 1963.) |
| `02_macro_interlocking_rod_lattice.jpg` | Multi-axial rod interlock: rods at distinct angles passing through and past each other to compose a single readable form. Disregard the architectural lobby context. (Lippold, *Wings of Welcome*, 1980, 424 metal rods.) |
| `03_macro_taut_strand_volume.jpg` | Constructivist tradition: taut linear strands generating curved volumes through tension alone; clean studio ground demonstrates how the form reads against negative space. Disregard the pedestal and acrylic base. (Gabo, Linear Construction series.) |
| `04_micro_brushed_aluminum_streak.jpg` | Anisotropic streak grain running one direction along brushed metal — the trait `mat_brushed_aluminum` (`§4.2`) needs to read as brushed and not painted. Disregard the dark tonality; albedo is set by the recipe at (0.91, 0.92, 0.93). |
| `05_micro_matte_anodized_finish.jpg` | Matte anodized near-white finish matching the recipe albedo of `mat_brushed_aluminum`. Disregard the regular hexagonal perforation pattern — pattern is not a geometric directive for KS. |
| `06_micro_frosted_glass_diffusion.jpg` | Pebbled surface micro-texture and diffuse light transmission per `mat_frosted_glass` (`§4.5`); the soft shape readable through the glass is the SSS-like emission term. Disregard the green color, which comes from the subject behind. |
| `07_specular_environment_reflections.jpg` | Polished chrome reads as chrome only because of the detailed environment it reflects (buildings, sky, pedestrians). The surroundings are mandatory, not decorative — `mat_polished_chrome` (`§4.1`) requires nearby IBL variation to look like anything but flat plastic. |
| `08_specular_anisotropic_chrome_highlights.jpg` | Streaked specular highlights running along curved polished-chrome surfaces — the anisotropic-roughness modulation in `§4.1`. Disregard absolutely the figurative humanoid form; KS is abstract lattice, not figurative. Also disregard the blank-sky background — that's the failure mode of `07_specular_*` shown by counterexample. |
| `09_atmosphere_dust_motes.jpg` | Discrete individuated dust motes within a directional light beam — the V.12 scope's "dust motes in ambient space" requirement. Disregard the rustic barn structure, the cobwebs, and the visible wide volumetric beam itself; only the discrete particles are the trait. |
| `10_specular_chrome_breakup_scratches.jpg` | Random fine scratches as specular breakup overlay on otherwise-flat polished metal — keeps `mat_polished_chrome` from looking liquid-uniform. Tonality and substrate are disregarded. |

Anti-reference slot (`05_anti_*`) intentionally pending: per D-065, the most useful
anti for KS is a v1-baseline frame capture showing the failure modes the V.12 uplift
is correcting (flat materials, no anisotropy, chrome with no surroundings to reflect).
To be added once V.12 ships its first iteration.

## Mandatory traits (per SHADER_CRAFT.md §12.1)

For this preset specifically, the following implementations are mandatory:

- [ ] **Detail cascade:**
  - macro = interlocking lattice silhouette per `01–03` (multi-axial members converging at hubs)
  - meso = per-member variation in length, tilt, cross-section, hub geometry — no two struts identical
  - micro = brushed-aluminum streak grain (`04`), frost surface noise (`06`), chrome specular variation (`10`)
  - specular = anisotropic streak roughness on aluminum, frost-shifted normals on glass, fbm8-modulated roughness on chrome
- [ ] **Hero noise function(s):** `fbm8` (chrome roughness modulation, frost normal perturbation), `warped_fbm` (optional secondary detail) — both from `Shaders/Utilities/Noise/`
- [ ] **Material count and recipes:** `mat_brushed_aluminum` (§4.2) + `mat_frosted_glass` (§4.5) + `mat_polished_chrome` (§4.1) — three distinct materials, all from `Shaders/Utilities/Materials/` (V.3)
- [ ] **Audio reactivity:** preserve validated FeatureVector routing per Inc 3.5.4.8; uses deviation primitives per D-026 (`f.bass_att_rel`, `f.mid_att_rel` for continuous motion). Avoid direct `f.beat_bass` reads — Inc 3.5.4.5 documented cooldown phase-lock issue affects KS. D-019 stem warmup fallback in place.
- [ ] **Silence fallback:** at `totalStemEnergy == 0`, lattice geometry remains fully present and three materials remain visible under three-point lighting per §5.1; chrome continues to pick up IBL ambient breathing. Never goes black or fully static.
- [ ] **Performance ceiling:** `<X.X ms p95 at 1080p Tier 2>` — measure post-V.12 lift and update from `V4_PERF_RESULTS.json`
- [ ] **Hero reference image:** `01_macro_radiating_strand_lattice.jpg`

## Expected traits (per §12.2 — at least 2 of 4)

- [ ] Triplanar texturing on non-planar surfaces — applicable: yes, on brushed aluminum lattice members (curved struts) and on chrome surfaces; uses `triplanar_normal` from V.1
- [ ] Detail normals — applicable: yes, for frost surface micro-perturbation (per `mat_frosted_glass`) and brushed-streak normal perturbation (per `mat_brushed_aluminum`)
- [ ] Volumetric fog or aerial perspective — applicable: no, KS is a gallery-interior aesthetic, not outdoor; cool sky tint preserved per MV-0 sentinel for chrome IBL backdrop only
- [ ] SSS / fiber BRDF / anisotropic specular — applicable: yes (mandatory hit) — anisotropic specular on `mat_brushed_aluminum` is core to the material reading as brushed; this is the strongest single fidelity lift in V.12

## Strongly preferred traits (per §12.3 — at least 1 of 4)

- [ ] Hero specular highlight visible in ≥60% of frames — applicable: yes, chrome lattice members will catch the §5.1 warm key light consistently across rotation
- [ ] Parallax occlusion mapping on at least one surface — applicable: no, KS surfaces (chrome, brushed aluminum, frosted glass) are smooth-by-spec; POM would be wasted budget
- [ ] Volumetric light shafts or dust motes — applicable: yes (V.12 scope) — dust motes in ambient space per `09_atmosphere_dust_motes.jpg`
- [ ] Chromatic aberration or thin-film interference — applicable: optional, possibly on frosted-glass rim or chrome edge silhouette; not mandatory

## Anti-references (failure modes specific to this preset)

What a Claude Code session is most likely to produce by accident; what this preset must NOT look like:

- Flat matte gray metal with no anisotropic streak — reads as painted, not brushed (the §4.2 failure mode)
- Polished chrome rendered against a blank or low-detail environment — reads as dull plastic with nothing to reflect (the §4.1 failure mode; `07_specular_environment_reflections.jpg` is the corrective)
- Glass rendered as perfectly smooth and clear — loses the frosted/diffusing character that justifies including glass as one of the three materials (the §4.5 failure mode)
- Regular geometric grid lattice (cube wireframes, evenly-spaced rods) — reads as engineering drawing, not sculpture; per `01–03` the geometry must be irregular, multi-axial, and tension-driven
- Figurative or representational forms (humanoid, animal, recognizable objects) — KS family is `abstract`; figurative reads break the brief

## Audio routing notes

Specific audio→visual mappings that must hold (cite D-026 deviation primitives and D-019 stem warmup):

- KS's existing FeatureVector routing is preserved per Inc 3.5.4.8 (validated, comment-flagged in the shader header). V.12 is a materials-focused uplift and must not re-author audio routing.
- Continuous motion drivers must use deviation primitives (`f.bass_att_rel`, `f.mid_att_rel`) per D-026 — never absolute thresholds.
- Beat-aligned drivers must avoid direct `f.beat_bass` reads to bypass the 400 ms cooldown phase-lock issue documented in Inc 3.5.4.5; prefer `smoothstep` over `f.bass_att`.
- D-019 stem warmup: any new stem reads must include FeatureVector fallback for the first ~60 frames before stem separation completes. KS does not currently route stems and need not start in V.12.

## Provenance

Curated by: Matt
Image sources:
- `01_macro_radiating_strand_lattice.jpg` — Richard Lippold, *Flight* (1963), Pan Am / Met Life Building. From Carter et al, *Richard Lippold: Sculpture*, p. 52. Verify rights before public release.
- `02_macro_interlocking_rod_lattice.jpg` — Richard Lippold, *Wings of Welcome* (1980), Hyatt Regency Milwaukee, 424 metal rods. Verify rights before public release.
- `03_macro_taut_strand_volume.jpg` — Naum Gabo, Linear Construction series (museum accession 1965.015). Verify rights before public release.
- `04, 05, 06, 07, 08, 09, 10` — Unsplash; photographers logan-voss (`04`), declan-sun (`05`), beau-carpenter (`06`), armand-mckenzie (`07`), wang-binghua (`08`), mika-baumeister (`09`), getty-images via Unsplash (`10`). Unsplash License — attribution appreciated, no rights issues.
