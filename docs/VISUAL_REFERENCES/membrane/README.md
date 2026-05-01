# Membrane — Visual References

**Family:** `fluid` &nbsp;·&nbsp; **Passes (current):** `feedback` &nbsp;·&nbsp; **Passes (uplift target):** `mv_warp` &nbsp;·&nbsp; **Rubric:** full (per D-064(a))
**Last curated:** 2026-05-01
**Curation role:** Uplift contract. Membrane is currently a production preset on the legacy thin-feedback path; this folder defines the fidelity target for a future uplift session that raises Membrane to V.6 certification.

---

## Preset summary

Membrane today is the only Phosphene preset still using the thin global feedback render path (`feedback` pass; not `mv_warp`). Each frame samples the previous frame through a single uniform zoom and rotation, then alpha-composites the new scene at decay ≈ 0.955. Motion compounds across many frames, but the per-frame transform is paradigm-thin: identical for every pixel in the frame. Compared to a per-vertex warp mesh, the result is closer to "simple pulsation" than "compound organic motion" (per `MILKDROP_ARCHITECTURE.md §4`).

The aesthetic target is an organic, breathing, painterly fluid surface — meditative, full-bleed, continuous. Continuous energy dominates; beats are accents only (per `CLAUDE.md → Audio Data Hierarchy`, Layer 1 vs Layer 4). The references in this folder describe what that surface should *look like* after uplift; the rubric and routing sections describe what it must *be* mechanically.

---

## Recommended uplift path: migrate from `feedback` to `mv_warp`

The reference target this folder describes — wet, in-progress, full-bleed evolution with regional flow differentiation — cannot be reached on the thin-feedback path. Single global zoom+rot warps every pixel identically; the references show different regions of the frame moving in different directions. Achieving that requires per-vertex feedback (`mv_warp`, MV-2, D-027), which warps each grid vertex independently from preset-authored `mvWarpPerFrame()` and `mvWarpPerVertex()` Metal functions.

Migration is paradigm-legal under D-029: Membrane has no camera and no particle system, so swapping `feedback` for `mv_warp` is a clean paradigm change of the same kind Starburst made in MV-2. Cost is ~0.6 ms (per `SHADER_CRAFT.md §9.1`) — negligible.

After migration:
- `passes: ["feedback"]` → `passes: ["mv_warp"]` in the JSON sidecar.
- `base_zoom`, `base_rot`, `decay` parameters move from `FeedbackParams` semantics into `mvWarpPerFrame()` baseline values; per-vertex equations modulate spatially per `MILKDROP_ARCHITECTURE.md §3c`.
- The thin global transform in `Common.metal:107–156` is retired; Membrane gets its own `Membrane.metal` with per-vertex authoring.
- Decay range stays 0.95–0.97 (long trails — Membrane is meditative, not snappy).

Staying on `feedback` is a documented alternative if the migration is judged out of scope. In that case the rubric ceiling is ~9/15 and certification will require a fluid-family adaptation entry in DECISIONS.md analogous to D-064(b).

---

## Reference images

| File | Cascade slot | What to learn | Actively disregard |
|---|---|---|---|
| `01_macro_meso_color_cells.jpg` | macro + meso (composite) | Whole-frame zoning logic and edge behavior — distinct color cells with hard fluid boundaries against translucent gaps; granulation textures inside cells (the speckled teal and grey-purple zones cover the meso layer); palette variation including near-blacks. The target for "≥3 distinct zones" on a continuous surface. | The literal rainbow saturation. Brand spec (`UX_SPEC.md §18.3`) prohibits this saturation envelope. Use the image for *zoning structure and edge dynamics*; let `04_wet_edge_cell_network.jpg` set the actual palette. |
| `02_continuous_flow_low_energy.jpg` | macro motion / silence-state | Long, slow, billowing whole-frame motion with multiple density gradations from near-opaque to translucent; edge structures show the *direction* of evolution. Single-color, so it teaches motion and density without palette noise. This is what Membrane should look like during a quiet verse — primary silence-fallback target for the rubric. | The white background as a literal backdrop choice. Membrane is full-bleed; the high-key field here is a print-substrate artifact of the photograph, not a directive about luminance baseline. |
| `03_macro_silhouette_evolution.jpg` | macro silhouette | Cleanest macro-silhouette teacher in the set. Reads exactly like an evolving feedback accumulator: large soft-edged form, organic boundaries, micro-tendrils at the leading edge. Monochrome means it teaches *shape behavior* without contaminating the palette discussion. The target for per-vertex warp differentiation — different regions evolving differently within one continuous surface. | Same caveat as `02` regarding the white field. Also: the upward-billowing direction is incidental — the warp accumulator in Membrane has no preferred axis. |
| `04_wet_edge_cell_network.jpg` | meso (cell network) — **hero palette/composition target** | Bullseye match for the brand-coherent uplift target: organic edges, generous negative space (the deep navy field), bubble-cell meso structure, and a translucent warm-on-cool palette aligned with brand tokens (`UX_SPEC.md §18.3` — coral on purple-dark base). The single best palette + composition reference for the post-uplift visual signature. | The bubble-network edges read as crystalline lattice in places — incidental to the moment of capture, not a directive about discrete cell structure. Membrane's cells should be soft-bounded, not hard-bordered. |
| `05_meso_zone_variation.jpg` | meso (zone differentiation) | Best meso-variation reference: pink, yellow-green, deep green, and lichen-spotted grey are four genuinely distinct zones with different surface characters. Painterly (non-fluid) cross-reference proving that "≥3 distinct materials" reads correctly even without PBR — different *zone characters* on a continuous surface. | The dry mineral substrate. This is solid surface, not fluid. Use the image *only* for zone-character reasoning, never for surface mechanics. |

---

## Rubric — Mandatory (7/7 required for certification per V.6)

- [ ] **Detail cascade present.** Reinterpreted for a `mv_warp` Membrane: macro = per-vertex warp differentiation across the frame (`02`, `03`); meso = zone color/density variation in the composite layer (`01`, `04`, `05`); micro = ≥4-octave noise modulation injected into the composite each frame; specular breakup = brief thin-film color shift on energy-peak edges (preferred slot).
- [ ] **Minimum 4 noise octaves.** Use `fbm8` or `warped_fbm` from `Shaders/Utilities/Noise/` (V.1) in the composite-layer color/alpha modulation. Single-octave-fBM fails certification.
- [ ] **Minimum 3 distinct surface zones.** "Materials" reinterprets as visually distinct zones in the feedback field. Reference targets: `01_macro_meso_color_cells.jpg` (multi-zone color logic) and `05_meso_zone_variation.jpg` (zone-character differentiation). Constant-color membrane fails.
- [ ] **Audio-responsive through deviation primitives (D-026).** Use `f.bass_att_rel`, `f.mid_att_rel`, `stems.{vocals,drums,bass,other}_energy_rel`. The current production code's use of absolute `features.mid_att` is grandfathered but **must be migrated** as part of the uplift.
- [ ] **Graceful silence fallback.** At `totalStemEnergy == 0`, Membrane should look like `02_continuous_flow_low_energy.jpg` — non-black, non-static, with form complexity ≥ 2 (Inc 5.2 structural-invariant test). The `mv_warp` accumulator alone should keep the surface evolving slowly even with no audio input.
- [ ] **Performance within tier budget.** `mv_warp` cost is ~0.6 ms (M3 Tier 2). Membrane has no other render cost. p95 frame time at 1080p is not at risk.
- [ ] **Matt-approved reference frame match.** Frame capture compared against `04_wet_edge_cell_network.jpg` (palette/composition) and `01_macro_meso_color_cells.jpg` (zoning); Matt signs off.

## Rubric — Expected (≥2/4 required)

- [ ] ~~Triplanar texturing on non-planar surfaces~~ — **N/A** (2D feedback, no surface normals).
- [ ] **Detail normals (adapted reading).** Per-vertex warp displacement perturbed by a higher-frequency noise sample at each grid vertex — gives composite-layer normal-map-equivalent variation. Achievable on `mv_warp`.
- [ ] **Volumetric fog or aerial perspective (adapted reading).** Alpha falloff at zone boundaries plus a soft additive bloom on bright peaks. Reads as atmospheric depth on a 2D surface. Cite `04_wet_edge_cell_network.jpg`'s deep-navy negative-space falloff.
- [ ] **SSS / fiber BRDF / anisotropic specular (adapted reading).** Translucent zone-on-zone alpha blending in the composite, with a back-light-equivalent boost to brighter zones. Reads SSS-adjacent. Cite the warm-on-cool layered translucency in `04`.

Realistic Expected score on the uplift path: **2–3 of 4**. Two require explicit Matt arbitration on the adapted-reading interpretation; the certification pass should record that arbitration as a folder-level note before V.6 sign-off.

## Rubric — Strongly preferred (≥1/4 required)

- [ ] ~~Hero specular highlight ≥60% of frames~~ — **N/A** for non-PBR feedback.
- [ ] ~~Parallax occlusion mapping~~ — **N/A**.
- [ ] **Volumetric light shafts or dust motes (adapted).** Composite-layer bloom on energy-peak zones, with sparse high-frequency dither acting as motes. Achievable.
- [ ] **Chromatic aberration or thin-film interference.** Brief soap-film color shifts on bright-zone edges during energy peaks — the natural specular-cascade analog for Membrane. Cite `01_macro_meso_color_cells.jpg`'s edge-color shifts. The cleanest path to passing this slot.

Realistic Preferred score on the uplift path: **1–2 of 4**.

## Score expectation

Adapted-rubric uplift target: **10–12 / 15** (7 mandatory + 2–3 expected adapted + 1–2 preferred). Above the 10/15 certification threshold. The folder-level Matt arbitration on Expected adapted-readings is a prerequisite for V.6 certification sign-off.

---

## Anti-references

Per D-065(c), each annotation states (1) the failure mode, (2) why it's tempting, and (3) what to actively disregard.

| File | Failure mode | Why it's tempting | Actively disregard |
|---|---|---|---|
| `anti_01_resolved_symmetric_pattern.jpg` | Resolved/symmetric finished marbling — the dried artifact, not the wet moment. | Visually rich; surface looks "fluid"; readable cell structure. | *Every* trait. Membrane lives in the in-between/evolving state, not the resolved-and-fixed one. The all-over uniform tile structure teaches mechanical repetition, which is the opposite of feedback-loop accumulation. Authoring sessions that read this as a structural directive will produce a tiled-surface preset, not Membrane. |
| `anti_02_oversaturated_specular.jpg` | Thin-film specular at full demoscene saturation, edge-to-edge rainbow. | Captures iridescence well; superficially aligns with Membrane's specular-slot target. | The saturation envelope and the all-over coverage. Specular peaks in Membrane should be *brief and localized* — moments, not the baseline. Pushed this far, the image becomes Plasma-family (`hypnotic`) territory and violates `UX_SPEC.md §18.2` ("not AI-product glow aesthetics, not neon scan lines"). |
| `anti_03_discrete_sphere_macro.jpg` | A single isolated soap bubble against soft background. | Beautiful thin-film, exactly the colors we want. | The discrete-sphere macro composition. Membrane is a *continuous full-bleed surface*, never a render of discrete objects. Authoring sessions that read "soap bubble" as a directive will produce a bubble preset, not a Membrane frame. |

---

## Audio routing — uplift target

All routings below assume D-026 compliance from the first commit of the uplift session. The current production code's grandfathered `features.mid_att` use is retired in the uplift — there is no migration window where mixed routing is acceptable.

| Visual parameter | Drive | Rationale |
|---|---|---|
| Per-frame baseline zoom (`mvWarpPerFrame.zoom`) | `f.bass_att_rel + 0.4 · f.mid_att_rel` | Continuous energy primary driver per Layer 1 rule. Coefficient ratio matches VL v2 tuning (ENGINEERING_PLAN.md, Inc 3.5.4.1). |
| Per-frame baseline rotation (`mvWarpPerFrame.rot`) | `f.mid_att_rel · 0.5` + `0.001 · sin(t·0.2)` | Slow drift; mid-band gives melody breath. Tiny `sin(t)` term preserves the meditative non-zero-at-silence floor. |
| Per-vertex zoom modulation | `radial_distance · (0.06 + 0.04 · f.bass_att_rel)` | Edges warp more than center on bass — produces the "breathing" expansion shown in `02_continuous_flow_low_energy.jpg`. |
| Per-vertex rotation modulation | `fbm noise sampled at world position, scale ~0.4 · 0.05` | Different regions rotate slightly differently — produces the regional-flow differentiation shown in `01_macro_meso_color_cells.jpg`. |
| Beat accent zoom (additive) | `pow(f.beat_bass, 1.5) · 0.3` | Selective — only strong kicks register. Per CLAUDE.md failed-approach #4, beat amplitude must stay 2–4× smaller than continuous zoom amplitude. |
| Composite-layer zone color weights | `stems.{vocals,drums,bass,other}_energy_rel` | Per-stem zone modulation gives the four-zone palette logic shown in `01_macro_meso_color_cells.jpg`. |
| Composite-layer noise injection | `fbm8` at scale 5.0 over warped UVs, amplitude `0.05 + 0.03 · f.mid_att_rel` | Mandatory ≥4-octave noise floor. Modulating amplitude on mid-band keeps the surface alive without reading as static texture. |
| Specular thin-film accent (preferred slot) | brief edge-color shift on `f.beat_composite` peaks above ~0.7 of the running max | Rare, localized — not baseline. Cite `01_macro_meso_color_cells.jpg` edge-color shifts. |
| Decay (`mvWarpPerFrame.decay`) | 0.96 (constant) | Long trails for the meditative breathing feel. Lowering toward 0.85 makes Membrane feel mechanical and is a regression. |

---

## Authoring sequence (suggested for the uplift session)

Per `SHADER_CRAFT.md §2.2` coarse-to-fine ordering, adapted for a `mv_warp` Membrane:

1. **Scaffold.** Create `Membrane.metal` with `mvWarpPerFrame()` + `mvWarpPerVertex()` skeletons; flip JSON `passes` to `["mv_warp"]`. Verify identity-warp test still passes (per `MVWarpPipelineTests.swift`).
2. **Macro motion.** Author per-frame zoom + rot from continuous bands; verify against `03_macro_silhouette_evolution.jpg` for whole-frame evolution behavior.
3. **Per-vertex differentiation.** Add radial zoom + fbm-driven rotation modulation; verify regions warp differently against `02_continuous_flow_low_energy.jpg`.
4. **Composite zoning.** Inject per-stem zone color weights into the composite scene fragment; verify multi-zone behavior against `01_macro_meso_color_cells.jpg` and `05_meso_zone_variation.jpg`.
5. **Micro detail.** Add 4-octave noise composite at scale 5.0; verify silence-state form complexity ≥ 2.
6. **Specular accent.** Add thin-film edge color shift on `f.beat_composite` peaks; verify edge behavior against `01_macro_meso_color_cells.jpg`.
7. **Atmosphere.** Composite-layer bloom on bright zones; alpha falloff at zone boundaries.
8. **Audio polish.** Migrate any remaining absolute-threshold patterns to deviation primitives. Verify `RelDevTests.swift` contracts pass.
9. **Matt review.** Frame capture against `04_wet_edge_cell_network.jpg` (palette/composition) and `01_macro_meso_color_cells.jpg` (zoning). No approval → loop back to weakest pass.

---

## Provenance

All five reference images and three anti-references are sourced from Unsplash (Matt's curation, batches 1–3). Source filenames preserved in the project's image-source ledger; renamed for inclusion per `_NAMING_CONVENTION.md`. No AI-generated images in this folder — the D-065 anti-reference AI carve-out was not invoked here because all three failure modes are photographable.

**Note on anti-reference filename pattern:** This folder uses `anti_NN_*` for the three anti-references. The §2.3 canonical exemplar shows a single `05_anti_*.jpg`. Verify against `_NAMING_CONVENTION.md` regex during the lint pass; if rejected, rename to `05_anti_*`, `06_anti_*`, `07_anti_*`.
