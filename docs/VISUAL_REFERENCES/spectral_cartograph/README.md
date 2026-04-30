# Visual References — Spectral Cartograph

**Family:** instrument
**Render pipeline:** direct
**Rubric:** lightweight — diagnostic instrumentation panel (not an aesthetic preset; exempt from fidelity rubric)
**Last curated:** <YYYY-MM-DD by Matt>

## Reference images

Files in this folder, numbered in priority order. See `../_NAMING_CONVENTION.md`.
References should be ≤ 500 KB each; crop and compress before committing.

| File | Annotation (what to learn from this image) |
|---|---|
| `01_palette_<...>.jpg` | <one sentence: color / palette requirement> |
| `02_anti_<...>.jpg` | NOT this — <one sentence: failure mode this preset must not produce> |

## Stylization contract

What DOES matter for this preset (substitute for the full rubric):

- [ ] **Color modulation:** <how audio energy must modulate palette, hue, brightness>
- [ ] **Audio coverage:** all four MIR panels must remain readable at all energy levels — TL=FFT spectrum, TR=3-band deviation meters, BL=valence/arousal phase plot, BR=scrolling graphs
- [ ] **Readability at silence:** <what the preset must look like at zero signal>
- [ ] **Readability at peak energy:** <what the preset must look like at maximum signal>

## Anti-references

What this preset must NOT look like:

- <one sentence per failure mode>

## Audio routing notes

- All four panels must use D-026 deviation primitives (`bass_dev`, `mid_dev`, `treb_dev`) for meter display — raw AGC-normalized values would appear artificially constant across mix-density changes.
- <one sentence per mapping>

## Provenance

Curated by: <Matt>
Image sources: <...>
