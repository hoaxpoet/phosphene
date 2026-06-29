# Mitosis — reaction–diffusion cell-colony preset

**Status:** Graduating (MITOSIS.1). Throwaway sketch (MITOSIS.0) cleared the §8
go/no-go gate 2026-06-29; Matt locked musical role / cell-look / regime the same
day. Not yet certified — pending the live sync listen, palette curation, and M7.

**Why this preset exists (the sync finding).** Filigree (a physarum/slime-mold
agent network) certified as a *loose energy-accompaniment*, not a beat-synced
preset: three live M7s converged that the trail substrate couples smoothly to the
continuous energy envelope but cannot carry tight event-sync (see
`FILIGREE_DESIGN.md §"sync finding"`). Matt's actual wish — "cells both merge and
divide over playback, fascinating to watch," synced to the music — is
reaction–diffusion's *native* behaviour: RD produces discrete, localized, visible
division events (a spot splits in two) on demand. This is the sync handle physarum
lacked. Do not attempt mitosis on physarum; do not bolt agents onto RD.

---

## 1. Musical role (locked, Matt 2026-06-29)

> *Drum/percussive onsets trigger visible bursts of cell division on the beat (the
> colony buds new cells); sustained energy sets the overall division rate and
> density, shifting the colony between sparse and teeming; cells divide and merge
> across the song.*

The onset→division event is the make-or-break and the reason for the preset — the
discrete, on-beat division the trail-based Filigree couldn't deliver.

### Temporal contract

| Musical feature | Visual behaviour | Timescale |
|---|---|---|
| Drum/percussive onset (`drumsEnergyDev`, +bass) | a burst of new cells buds into open space → reads as mitosis on the beat | per-beat, fast |
| Sustained continuous-energy envelope | division rate (substeps/frame) + density: louder shifts the colony teeming, quieter lets it die back sparse | slow / continuous |
| Structural sparse↔teeming arc | the regime (kill rate `k`) drifts across the death boundary with energy | per-section |

No two visual layers share an audio primitive at the same timescale (D-026, FA #67):
energy → rate+density (one layer, one timescale); onset → division burst (a
separate fast layer).

---

## 2. Three-part bar (cleared)

1. **Iconic subject at fidelity** — Gray–Scott mitosis cells; rendered at fidelity
   in the sketch (discrete glowing cells, dumbbell/rod shapes mid-division). See
   `docs/VISUAL_REFERENCES/mitosis/`.
2. **Clear musical role** — §1, one sentence, specific feature → specific behaviour.
3. **Infrastructure-feasible** — proven in the sketch: runs on the existing
   `ParticleGeometry` per-frame compute + ping-pong + particle-mode draw. No new
   render primitive. Filigree proved the path.

---

## 3. Locked design decisions (Matt 2026-06-29)

- **Name:** Mitosis.
- **Cell look:** abstract glowing cells on dark (NOT membrane-shaded/literal) —
  cleanest figure-ground, strongest in a dark room.
- **Regime:** shifts with the music (loud = teeming dividing field, quiet = sparse
  die-back), not one fixed regime.
- **Palette:** OPEN — its own reference-anchored curation step. Sketch placeholder
  is cyan-on-dark (membrane teal → cyan-white nucleus).

---

## 4. Rendering architecture

- **`MitosisGeometry`** — a `ParticleGeometry` sibling (D-097), modelled
  byte-for-byte on `PhysarumGeometry`'s per-frame-compute contract. Owns two
  ping-pong `rg16Float` state textures (`r`=A, `g`=B) — half the binds of two
  `r16Float`, one filterable sample for display.
- **Per-frame compute** (one encoder): N Gray–Scott react substeps (`mitosis_react`),
  ping-ponging the two textures, with `memoryBarrier(.textures)` between dependent
  substeps — Metal does not serialise consecutive dispatches (cf.
  `FerrofluidParticles.swift` / `PhysarumGeometry.swift`). `~8–18` substeps/frame
  scaled by energy (RD needs many iterations/frame).
- **Draw** — `mitosis_fragment` samples the latest state's B channel and colorizes;
  reuses `fullscreen_vertex` from `Common.metal`. Backdrop = `mitosis_ground_fragment`
  (dark ground, fully covered).
- Sim grid 320×180 (cells large enough to read division; RD is cheap per cell).

## 5. The Gray–Scott model (ported, FA #73)

```
A' = A + (Da·∇²A − A·B² + F·(1 − A))·dt
B' = B + (Db·∇²B + A·B² − (k + F)·B)·dt
```
`Da=1.0, Db=0.5, dt=1.0`; toroidal 3×3 Laplacian `[[.05,.2,.05],[.2,−1,.2],[.05,.2,.05]]`.
Public-domain math, re-implemented in our own MSL. References: Karl Sims
(karlsims.com/rd.html), mrob "Xmorphia" parameter atlas, pmneila jsexp GrayScott.

**★ Load-bearing regime finding (empirical, `test_regimeProbe`).** The canonical
"mitosis" parameters F=0.0367/k=0.0649 **decay to extinction** in this `rg16Float`
discretisation (autonomous spot count → 1). k≈0.063 (the "u-skate" regime)
self-sustains a living field of discrete dividing cells; k climbing toward ~0.0645
dies them back — which *is* the merge↔divide handle. Base regime: **F=0.034,
k=0.063**, with energy shifting `k` across the death boundary
(`killEff = 0.063 + 0.0008 − 0.0026·energy`).

## 6. Audio routing

| Visual layer | Primitive | Timescale | Mechanism |
|---|---|---|---|
| Division rate + density (sparse↔teeming) | smoothed continuous energy (`energyEnv`, Murmuration-style stem/full-mix blend) | slow | scales substeps/frame + shifts `k` across the death boundary |
| Mitosis burst (the synced event) | `drumsEnergyDev` (+ `bassEnergyDev`), fast-attack/slow-release `hitEnv` | per-beat | paints sparse B nuclei into OPEN space → new cells bud on the beat |

**Why onsets paint into open space, not at cell rims:** rim injection floods the
gaps of a packed field and *merges* it (measured Δ-40 in the sketch). Painting B
into empty cells (the canonical interactive-RD seed, pmneila/Karl Sims) nucleates
new cells, is density-independent, and is luminance-bounded → flash-safe.

Cold-start safe: continuous energy + deviation primitives available frame 1; no
beat-phase dependency (the burst keys off `drumsEnergyDev` magnitude, not grid phase).

---

## 7. Sketch go/no-go evidence (MITOSIS.0, all green)

`MitosisSketchRenderTests` (headless):

| Criterion | Result |
|---|---|
| 60 fps @ 1080p | **0.65 ms/frame** (320×180 sim, ≤18 substeps; ~25× under the 16.67 ms budget) |
| Stable, bounded | 276 living cells; finite, clamped [0,1]; no all-on/all-off |
| Divide AND merge | cell count 39 → 286 → 215 across quiet→loud→quiet |
| Onset CAUSES division | onset run +141 cells vs +136 in an identically-seeded no-onset control; `hitEnv` fires on drum hits |
| Flash-safe (D-157) | luma maxΔ 0.002/frame under a 4 Hz onset train |

"Reads as synced on a real track" is the live gate (FA #27) — the sketch proves
the *mechanism*, only listening confirms the *feel*.

---

## 8. Known tuning items / risks (carried into the increment)

- **Onset effect is modest in a packed field** — empty-space nucleation has little
  room when the colony is dense; the on-beat budding reads best in mid-density.
- **"Merge" reads weaker than "divide"** — once the field fills it tends to stay
  full; short quiet phases don't die back fully. Balance the energy→k die-back rate.
- **Palette unlocked** — cyan-on-dark is a placeholder; final grade is a curation
  step with Matt.
- **Live sync unproven** — headless proves pipeline, not feel (FA #27). The live
  listen is the gating real-feel test.

## 9. Phased plan

| ID | Done-when |
|---|---|
| **MITOSIS.0** | Throwaway sketch + §8 go/no-go gate (all green). ✅ |
| **MITOSIS.1** | Graduated to a registered preset: JSON sidecar + `ParticleGeometryRegistry` + `VisualizerEngine` factory/resolve + multi-frame production-path test; wired into the live app. (this) |
| **MITOSIS.2** | Live sync listen on real music (the gating real-feel test, FA #27). |
| **MITOSIS.3** | Palette curation (reference-anchored, Matt's pick). |
| **MITOSIS.4** | Certification — M7, rubric, flash-safety cert (`renderMitosis`), sidecar `certified: true`. |

## 10. Design grounding (descending preference — per checklist)

- **Level 1 (working code reference):** pmneila jsexp GrayScott
  (https://pmneila.github.io/jsexp/grayscott/) — clean implementation; the
  paint-reactant interaction is the onset-burst mechanism. Karl Sims RD tutorial
  (https://www.karlsims.com/rd.html). mrob Xmorphia parameter atlas
  (http://mrob.com/pub/comp/xmorphia/) for the regime map.
- **License:** Gray–Scott is public-domain math; algorithm re-implemented in our own
  MSL, no source copied.
- The abstract cyan grade + the audio coupling are Phosphene-original, empirically
  grounded by the sketch's rendered evidence.

## Module-Map history

`MitosisGeometry.swift`, `Renderer/Shaders/Mitosis.metal`,
`Presets/Shaders/Mitosis.{json,metal}`, `MitosisSketchRenderTests.swift` — created
in the throwaway sketch (MITOSIS.0) and graduated across MITOSIS.1+. Per-file
behaviour: see `docs/ARCHITECTURE.md §Module Map`.
