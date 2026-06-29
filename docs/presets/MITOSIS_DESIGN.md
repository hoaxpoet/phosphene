# Mitosis — reaction–diffusion cell-colony preset

**Status:** ✅ **CERTIFIED 2026-06-29 (MITOSIS.2c — "psychedelic cell division")**, Matt's
M7 sign-off. Flash-safe (0.00 flashes/s, real `renderMitosis` multi-pass harness).

**★ Shipped concept (the FINAL design — supersedes the §5/§6 "churn" history below).**
*Psychedelic cell division.* A Gray–Scott reaction–diffusion colony: a few cells divide
into many until the field is **crowded** (cells touching, ~25–35 s), then the colony
**dissolves** back to a few cells and **regrows** — a continuous birth→crowd→dissolve
cycle paced by the music's energy. Rendered as **fluorescence microscopy** — magenta
nuclei + electric cyan/green membranes (the B-gradient) glowing on black, at a 640×360
sim (sharp). The **psychedelic hue is tied to the music**: a phase that accumulates
energy-paced + a spectral-centroid bias + a travelling spatial wave. Regime F=0.0260,
k=0.0600 (dense-fill discrete cells); LOW substeps (2–5) pace the slow growth; a high-k
pulse dissolves; a cluster reseed gives the "few cells" to regrow from. **Key arc:** the
natural GS growth transient (few→crowded) IS the division — earlier work fought it.

**★★ Design dead-end (MITOSIS.2 / .2b — kept below as history).** Three live M7s were
spent building a *per-beat churn* (onset-driven, then grid-driven k-oscillation, anti-
freeze) before Matt's "psychedelic cell division" vision reframed it as the slow GROWTH
arc. The churn was over-engineering — suppressing the very transient that was the answer.
The §5/§6 sections below document that dead-end; the shipped design is the summary above.

---

**(historical) Why this preset exists — the sync finding.** Filigree (a physarum/slime-mold
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
self-sustains a living field of discrete dividing cells. Base regime: **F=0.034,
k=0.0655** (death-leaning; lower k writhes into a connected worm labyrinth).

**★★ MITOSIS.2 correction (the live-M7 fix — load-bearing).** The first cut shifted
`k` *gently* with energy and "painted nuclei into open space" on onsets. Matt's live
M7: *"after the initial cell division to form a regular grid, it slows down
immensely… division but not a combination of division and merging."* Diagnosed from
the session (`2026-06-29T19-44-15Z`): the audio was rich (drum onsets in **58.9 %** of
frames, steady ~0.4 energy) — the failure was the substrate. A direct probe
(`test_regimeProbeDynamic`) found the load-bearing fact: **every constant-parameter
Gray–Scott regime FREEZES** to a static attractor (end-activity ≈ 0). The "mitosis"
is the *transient*; the music must keep the field out of equilibrium.

**★★★ MITOSIS.2b correction (the 2nd live-M7 fix — load-bearing).** The MITOSIS.2 cut
drove the churn off *drum onsets* (`hitEnv`). 2nd live M7: *"complete failure… deep
sea dive."* The track (`2026-06-29T20-21-43Z`) had drum onsets in **0.6 %** of frames
(vs 58.9 % on the first) — a non-percussive track — so the onset-driven field collapsed
to a few sparse cells. Two errors: (1) I made the *beat* the primary driver of whether
cells exist (inverting the Audio Data Hierarchy — continuous energy is the default
primary, beats are accents); (2) the survival floor seeded *isolated* cells, which die
at the death-base before they can establish. The fix:

## 6. Audio routing (MITOSIS.2b)

| Visual layer | Primitive | Timescale | Mechanism |
|---|---|---|---|
| Divide↔merge RHYTHM (the sync, PRIMARY) | **continuous cached-grid `beatPhase01`** | per-beat | a shallow per-beat `k`-dip pulse (`(1−beatPhase01)²`) → division on the beat; base `k` culls between (merge). The grid advances on **every** track (percussive or not), so the field churns robustly regardless of drum density. |
| Density (sparse↔teeming) | smoothed `energyEnv` → **cluster-reseed RATE** | slow | energy ramps how many establishing clusters seed/sec → loud teems, quiet thins. Base `k` stays FIXED in the discrete band (lowering it for density pushed loud into worms). |
| Vigour | `energyEnv` → substeps/frame | slow | louder = faster churn. |
| Division accent | `drumsEnergyDev` → `hitEnv` | per-beat | actual drum hits add a small extra `k`-dip — an accent on percussive tracks, absent (harmlessly) on ambient ones. |

`killEff = 0.0655 − (0.0042 + 0.001·energy)·(1−beatPhase01)² − 0.004·hitEnv`. Base `k`
is FIXED at 0.0655 (always discrete cells); only the brief per-beat pulse dips lower
(too short to worm-ify). **Survival = the cluster reseed:** a ~2 px disk at a per-frame
hashed centre, music-energy-gated — *clusters establish where isolated cells die*, so the
field survives at any energy/onset density and never permanently dies (dead Gray–Scott
can't revive: no B → no A·B² reaction). Silence → no reseed → calm fade (no Drift-Motes).
Seed = **3 cells** (Matt: "start with a couple of cells").

Cold-start: `beatPhase01` is available frame 1; a wrong cold-start phase reads as a small
divide/merge offset, not a wrong-beat firing (the cold-start contract's safe-use case).

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

## 8. Known tuning items / risks

- **Live re-confirm pending** — MITOSIS.2's churn fix is code-complete and proven
  headless (never freezes, divides+merges, discrete cells, flash-safe); only Matt's
  ears/eyes confirm it reads right on a real track ([[feedback_visual_fix_needs_live_m7]]).
- **Very-early sparse phase shows hollow rings** — isolated cells grow as rings before
  dividing (natural RD); transient (first ~1–2 s). Acceptable but watch in live.
- **Palette unlocked** — cyan-on-dark is a placeholder; final grade is a curation
  step with Matt (MITOSIS.3).

## 9. Phased plan

| ID | Done-when |
|---|---|
| **MITOSIS.0** | Throwaway sketch + §8 go/no-go gate (all green). ✅ |
| **MITOSIS.1** | Graduated to a registered preset; wired into the live app. ✅ |
| **MITOSIS.2** | Live → ❌ fill-then-freeze → onset-driven k-oscillation churn (constant-GS-freezes finding). |
| **MITOSIS.2b** | Live → ❌ "deep sea dive" (onset-driven collapsed on a 0.6%-onset track) → grid-driven churn. Still wrong concept (per-beat churn). |
| **MITOSIS.2c** | Live → "much too fast/blurry" → Matt's vision **"psychedelic cell division"**: reconceived as a slow GROWTH cycle (few→crowded→dissolve→regrow) + fluorescence colour + music-tied hue; packed denser (cells touching). **Matt's M7 sign-off → ✅ CERTIFIED** (rubric `certifiedPresets`/`expectedAutomatedGate` false, `multiPassMeasured` + `renderMitosis` flash harness 0.00 flashes/s, `certified: true`). |
| **MITOSIS gen-2** | (future, post-cert) A detailed/"realistic" version — per-cell procedural detail (spindle asters, cleavage furrow, chromatin) over the RD/agent layer. Reference image locked. A different renderer; a fresh increment. |
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
