# Visual References — Naming Convention

Every reference image filename must match:

```
NN_<scale>_<descriptor>.<ext>
```

Where:
- `NN` = two-digit ordinal (01–99). Lower = higher priority for the curation session.
- `<scale>` ∈ {`macro`, `meso`, `micro`, `specular`, `atmosphere`, `lighting`, `palette`, `anti`}
  - `macro` — SDF silhouette / mesh envelope / overall composition (unit scale)
  - `meso` — variation ridges, per-instance jitter, surface-level shape (∼0.1–0.3 unit scale)
  - `micro` — surface grain, normal detail, texture (∼0.01–0.03 unit scale)
  - `specular` — specular highlight, glint pattern, material finish (pixel to sub-pixel)
  - `atmosphere` — fog, aerial perspective, volumetric light, sky
  - `lighting` — light placement, shadow behaviour, ambient vs direct ratio
  - `palette` — color temperature, hue distribution, palette shape (for 2D / stylized presets)
  - `anti` — a "NOT this" example; a failure mode the preset must not produce
- `<descriptor>` = lowercase_underscored, 2–4 words naming the specific visual trait shown
- `<ext>` = `jpg` for photographic references; `png` for renders or line art with sharp edges

## Size limit

References MUST be ≤ 500 KB each. Crop and compress before committing.
At 1080p JPEG q85 that is roughly a 960×540 crop. Full-frame 1080p JPEG q85
runs ≈ 250–400 KB — that is fine. Do not commit uncompressed PNGs.

## Examples (from SHADER_CRAFT.md §2.3 precedent)

```
01_macro_web_geometry.jpg          — silk threads ≈1.5 px at 1080p
02_meso_per_strand_variation.jpg   — no two strands identical in tension/sag
03_micro_adhesive_droplet.jpg      — drops 8–12 px apart on spiral threads
04_specular_fiber_highlight.jpg    — narrow axial specular along each strand
05_anti_reference.jpg              — NOT this: flat cylindrical tubes
```

## Validation

The lint check (`swift run --package-path PhospheneTools CheckVisualReferences`)
validates that every image in every preset folder matches this regex:

```
^[0-9]{2}_(macro|meso|micro|specular|atmosphere|lighting|palette|anti)_[a-z0-9_]+\.(jpg|png)$
```
