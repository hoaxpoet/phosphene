# Visual References — <Preset Name>

**Family:** <e.g. organic | geometric | abstract | fractal | fluid | particles | hypnotic | waveform | instrument>
**Render pipeline:** <e.g. ray_march | mesh_shader + mv_warp | direct_fragment + mv_warp | feedback | feedback + particles>
**Rubric:** full (gated by V.6 certification)
**Last curated:** <YYYY-MM-DD by Matt>

## Reference images

Files in this folder, numbered in priority order. Each name encodes the trait it
demonstrates. Format: `NN_<scale>_<descriptor>.jpg` where `<scale>` is one of
`macro` / `meso` / `micro` / `specular` / `atmosphere` / `lighting` / `palette` / `anti`
and `<descriptor>` is a 2–4 word lowercase_underscored descriptor. See
`../_NAMING_CONVENTION.md`. References should be ≤ 500 KB each; crop and compress
before committing.

| File | Annotation (what to learn from this image) |
|---|---|
| `01_macro_<...>.jpg` | <one sentence: what the macro silhouette must read as> |
| `02_meso_<...>.jpg` | <one sentence: meso-scale variation requirement> |
| `03_micro_<...>.jpg` | <one sentence: micro / surface-detail requirement> |
| `04_specular_<...>.jpg` | <one sentence: specular / material highlight requirement> |
| `05_anti_<...>.jpg` | NOT this — <one sentence: failure mode this preset must not produce> |

## Mandatory traits (per SHADER_CRAFT.md §12.1)

For this preset specifically, the following implementations are mandatory:

- [ ] **Detail cascade:** macro = `<...>`, meso = `<...>`, micro = `<...>`, specular = `<...>`
- [ ] **Hero noise function(s):** `<e.g. fbm8 + worley_fbm>` (from `Shaders/Utilities/Noise/`)
- [ ] **Material count and recipes:** `<e.g. mat_silk_thread + mat_chitin + bioluminescent_haze>` (from `Shaders/Utilities/Materials/` V.3)
- [ ] **Audio reactivity:** deviation primitives this preset must use (e.g. `f.bass_dev`, `stems.vocals_energy_dev` per D-026)
- [ ] **Silence fallback:** what the preset must look like at `totalStemEnergy == 0` (D-019 warmup)
- [ ] **Performance ceiling:** `<X.X ms p95 at 1080p Tier 2>` (matches `complexity_cost` in JSON sidecar)
- [ ] **Hero reference image:** which file above is the single most important "must match" frame

## Expected traits (per §12.2 — at least 2 of 4)

- [ ] Triplanar texturing on non-planar surfaces — applicable: <yes/no/n/a>, why
- [ ] Detail normals — applicable: <...>
- [ ] Volumetric fog or aerial perspective — applicable: <...>
- [ ] SSS / fiber BRDF / anisotropic specular — applicable: <...>

## Strongly preferred traits (per §12.3 — at least 1 of 4)

- [ ] Hero specular highlight visible in ≥60% of frames — applicable: <...>
- [ ] Parallax occlusion mapping on at least one surface — applicable: <...>
- [ ] Volumetric light shafts or dust motes — applicable: <...>
- [ ] Chromatic aberration or thin-film interference — applicable: <...>

## Anti-references (failure modes specific to this preset)

What a Claude Code session is most likely to produce by accident; what this preset must NOT look like:

- <one sentence per failure mode>

## Audio routing notes

Specific audio→visual mappings that must hold (cite D-026 deviation primitives and D-019 stem warmup):

- <one sentence per mapping>

## Provenance

Curated by: <Matt>
Image sources: <where Matt sourced the reference images, attribution if any>
