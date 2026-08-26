# Visual References — Curation Kickoff

This directory holds the fidelity contract for every Phosphene preset. Each
folder is a curated set of reference images plus a README listing per-preset
mandatory traits (rubric per `SHADER_CRAFT.md §12`). Sessions authoring or
uplifting a preset cite these images by filename per `SHADER_CRAFT.md §2.3`.

## To curate a preset

1. Open `<preset>/README.md`. Verify the family classification at the top is correct.
2. Drop 3–5 reference images into the folder, named per `_NAMING_CONVENTION.md`.
   Photographic references preferred over renders. Sources are Matt's choice.
   **≤ 500 KB per image.** Crop and compress before committing.
   **`.gitignore` excludes these rasters by default** (LFS was retired repo-wide
   at CLEAN.5.8 over billing) — force-add each image or it never leaves your
   working copy: `git add -f docs/VISUAL_REFERENCES/<preset>/*.jpg`.
3. Fill in the reference-image table — one sentence per file describing what
   to learn from it.
4. Tick the mandatory / expected / preferred trait checkboxes. Be specific:
   "fbm8 over world position at scale 5.0" is useful; "noise" is not.
5. Add 1–3 anti-reference entries (failure modes specific to this preset).
6. Add audio-routing notes (which deviation primitives drive what).
7. Update `Last curated:` at the top of the README.
8. Run `swift run --package-path PhospheneTools CheckVisualReferences` —
   it should pass with no warnings for this preset.

## Curation order (highest leverage first)

1. **arachne, gossamer** — V.7 / V.8 are the first uplift sessions; their
   references unblock that work.
2. **ferrofluid_ocean** — V.9 is marked "full rebuild" in the engineering
   plan; its references are the input contract for authoring those sessions.
   (**fractal_tree** was here for V.10; that uplift is cancelled and its set
   moved to **goldengrove** — D-212. Fractal Tree now needs a *low-fi /
   graphic* set curated from scratch, an FTR.2 prerequisite.)
3. **volumetric_lithograph** — V.11 is the most-iterated preset; references
   here directly resolve the "lumpy vs mountainous" judgment calls that prior
   sessions had to skip.
4. **glass_brutalist, kinetic_sculpture** — V.12 polish targets.
5. **murmuration, membrane** — current production presets; reference folders
   document the existing aesthetic so future regressions are catchable.
6. **plasma, waveform, nebula, spectral_cartograph** — lightweight folders;
   ~15 minutes each.

## Quality reel

Separate but parallel deliverable. See `../quality_reel_playlist.json` for the
playlist contract; pick three tracks and record per
`RUNBOOK.md → Recording the quality reel`. The reel exercises V.6's fidelity
rubric across mood quadrants and is the primary artefact for "did anything
regress visually?" reviews.

## Directory layout

```
docs/VISUAL_REFERENCES/
  README.md                       ← this file
  _NAMING_CONVENTION.md           ← filename regex and size limit
  _TEMPLATE/
    README.md                     ← full-rubric template (copy for new presets)
    README_LIGHTWEIGHT.md         ← lightweight template (copy for stylized/diagnostic presets)
  arachne/                        ← full rubric
  ferrofluid_ocean/               ← full rubric
  fractal_tree/                   ← lightweight (stylized graphic branch-fan, D-212)
  goldengrove/                    ← full rubric (set transferred from fractal_tree, D-212)
  glass_brutalist/                ← full rubric
  gossamer/                       ← full rubric
  kinetic_sculpture/              ← full rubric
  membrane/                       ← full rubric
  nebula/                         ← lightweight (stylized particle system)
  plasma/                         ← lightweight (demoscene plasma)
  spectral_cartograph/            ← lightweight (diagnostic panel)
  murmuration/                    ← full rubric
  volumetric_lithograph/          ← full rubric
  waveform/                       ← lightweight (stylized 2D)
  phase_md/                       ← empty parent; per-MD-preset folders land in MD.1+
```

Full-rubric presets: 9. Lightweight presets: 4.

## Done when (increment-level)

These criteria close out Increment V.5 entirely. Run
`swift run --package-path PhospheneTools CheckVisualReferences --strict`
to verify.

- [ ] All 9 full-rubric folders have 3–5 reference images force-added
      (`git add -f`, per the gitignore carve-out — LFS was retired at CLEAN.5.8),
      READMEs fully filled in.
- [ ] All 4 lightweight folders have 1–2 reference images, READMEs filled in.
- [ ] Quality reel `docs/quality_reel.mp4` committed via Git LFS;
      `quality_reel_playlist.json` track placeholders replaced with actual choices.
- [ ] `swift run --package-path PhospheneTools CheckVisualReferences --strict`
      passes with zero warnings.
- [ ] Matt's approval round complete; `ENGINEERING_PLAN.md §Increment V.5`
      marked ✅ with landed-date.
