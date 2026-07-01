# Mitosis gen-2 — detailed fluorescence-microscopy cell division

**Status:** 🔨 **G2.2 iter 1 (2026-06-30)** — grow→crowd→dissolve→regrow arc with
non-overlapping cells (reworked from G2.1's rejected capped/cull model); pending Matt's
re-look. Preset **Cytokinesis**, playable uncertified. Sibling of the certified gen-1
(`MITOSIS_DESIGN.md`), NOT an edit of it (D-097).
Kickoff: `MITOSIS_GEN2_KICKOFF.md`. Reference + traits:
`docs/VISUAL_REFERENCES/mitosis/README.md §Gen-2`.

**★ Concept (Matt; arc REVISED at the G2.2 live look, 2026-06-30).** Procedurally-detailed
dividing cells rendered like confocal immunofluorescence microscopy — each cell a dumbbell
mid-cytokinesis with two radial green microtubule asters, a **solid opaque membrane wall**,
a coloured cortical ring, blue chromatin, a magenta spindle midzone, vesicle speckles, over
a green filament field. **Arc (G2.2 live):** the canvas **starts with a few large cells that
divide until much of the screen is crowded**, the cells **never overlap**, then the field
dissolves and regrows — a continuous grow→crowd→dissolve→regrow cycle (the gen-1 arc, with
detailed non-overlapping cells). The early/large divisions are the detail showcase; cells
shrink as the colony packs. Music-tied fluorescence palette (gen-1 MITOSIS.5 reuse).

> **Superseded:** the pre-live G2.1 lock was "few large cells, *always* (never crowds)" with
> a bounded cap + cull governor. Matt's live look (G2.2) rejected it — the cull read as
> "frequent respawning" — and asked for the grow-to-crowded arc above. Do not restore the
> capped/cull model.

---

## 1. Musical role (locked, Matt 2026-06-30)

> *Sustained energy advances each cell through its division phases (louder = cells progress
> faster toward splitting); a drum/percussive onset triggers the actual cytokinesis SNAP —
> a cell that's ready pinches through its furrow and splits into two daughters on the beat;
> the spectral centroid drives the fluorescence palette (MITOSIS.5 reuse).*

The **cytokinesis snap on the onset** is the make-or-break event — with only a few large
cells, the split is a genuinely legible on-beat moment (far stronger than gen-1's dot-splits).

### Temporal contract

| Musical feature | Visual behaviour | Timescale |
|---|---|---|
| Sustained continuous energy (`energyEnv`, PRIMARY) | each cell advances interphase → metaphase → anaphase along its phase clock; louder = faster toward the split | slow / continuous |
| Drum/percussive onset (`drumsEnergyDev` → `hitEnv`) | a cell at/near the ready threshold **snaps** through cytokinesis and splits into two daughters on the beat | per-beat, fast |
| Spectral centroid (`centroidEnv`) | fluorescence palette hue (timbre: dark→teal/violet, bright→orange/pink) | slow |
| Energy | global vividness/saturation | slow |

**Audio Data Hierarchy (continuous primary):** the cell population is sustained by energy,
not by beats — a non-percussive track still grows and divides (energy paces the phase
clock); onsets only *time the snap* of an already-ready cell, so a 0.6 %-onset track
degrades gracefully (the gen-1 MITOSIS.2b lesson — do not make the beat the primary driver
of cell existence). **One primitive per layer (D-026, FA #67):** energy → phase rate;
onset → the snap event; centroid → hue; energy → vividness. The MITOSIS.5 drum glow-pulse
is folded INTO the snap moment (one beat event, reinforcing — not an independent layer that
would compete with the split).

---

## 2. Three-part bar (cleared)

1. **Iconic subject at fidelity** — a detailed dividing cell, **proven in the sketch**
   (`tools/mitosis_gen2_sketch/`, Matt-approved 2026-06-30): dumbbell furrow + two green
   asters + solid membrane wall + coloured cortex + chromatin + midzone, on a filament field.
2. **Clear musical role** — §1, one sentence, specific feature → specific behaviour.
3. **Infrastructure-feasible** — proven in the sketch + grounded in the engine: the
   substrate is an explicit CPU cell list rendered by a fullscreen fragment pass. No new
   render primitive, no compute pass, no GPU-contract additions beyond a `setFragmentBytes`
   cell buffer. Strictly *simpler* than gen-1's RD compute path.

---

## 3. Locked decisions (Matt 2026-06-30)

- **Name / family:** **Cytokinesis** (preset id). A separate preset + sidecar (D-097).
- **Arc (G2.2 live):** start few large cells → **divide until much of the screen is crowded**
  → dissolve → regrow (cycle). Cells **never overlap**. (Supersedes the G2.1 "few large,
  always / capped + cull" model, which read as frequent respawning.)
- **Substrate:** explicit per-cell objects (position, radius, orientation, division phase,
  seed), NOT Gray–Scott. Monotonic growth (divisions only add); a circle-packing relaxation
  keeps cells non-overlapping; radius shrinks with count so the colony fills the screen.
- **Look:** confocal fluorescence — solid opaque membrane wall, coloured cortical ring,
  green asters, blue chromatin, magenta midzone, vesicle speckles, green filament field.
- **Palette:** music-tied (MITOSIS.5 model — centroid → hue, energy → vividness).
- **Music coupling:** the §1 musical role is the TARGET; G2.2 runs the arc **autonomously**
  (energy gently nudges the growth pace) — full coupling (onset→snap etc.) is a later step
  (Matt: "we will *ultimately* attach the behaviour to musical signal").

---

## 4. Rendering architecture (grounded in the gen-1 geometry contract)

**`MitosisGen2Geometry`** — a `ParticleGeometry` sibling (like `MitosisGeometry`), but
*without* the RD compute path:

- **State = a CPU `Cell` array** (`var cells: [Cell]`, hard cap 64; grows from `seedCells`=3
  to `crowdCount`=40). `Cell` = `{ pos: SIMD2, radius, targetRadius, axis, phase, phaseRate,
  seed }`. A `Stage` machine: `.growing → .holding → .dissolving → (reseed) → .growing`.
- **`update(features:stemFeatures:commandBuffer:)`** advances the music envelopes (port of
  gen-1 `advanceEnvelopes` — `energyEnv`/`centroidEnv`/`hitEnv`/`huePhase`), then the cell
  model on the CPU (no compute encoder; `commandBuffer` unused):
  - **radius** lerps toward `packRadius(count, aspect)` — sized so `count` cells fill
    `coverage` (0.60) of the screen → cells shrink as the colony grows (defaults:
    `crowdCount` 64, `divPeriod` 8 s). **★ visible-radius gotcha:** the shader draws a cell
    to only ≈ `poleR` (0.55) × its `radius`, so packing/collision/coverage all use the
    VISIBLE radius (`visibleFraction·radius`) and `radius` is scaled up by 1/0.55 — otherwise
    cells pack ≈ 1.8× their visible size apart and leave large gaps (the G2.2-iter-2 fix for
    "more space to fill"). 0.60 is the max fill that packs provably non-overlapping (0.66+
    forces overlap — circle-packing limit for this dynamic, unequal, dividing field);
  - while `.growing`, each cell's `phase += dt · phaseRate · pace` (pace energy-nudged);
  - **division** (`.growing`): a completed cell (`phase ≥ 1`) splits into **two daughters**
    along its axis — **monotonic, NO culling** — until `count ≥ crowdCount` → `.holding`
    (completed cells then re-cycle in place, no growth); after `holdSeconds` → `.dissolving`
    (radius → 0, cells drop out as they melt) → reseed 3 cells → `.growing`;
  - **non-overlap:** a soft **circle-packing relaxation** (`relax`, O(n²)/iter × 4 iters,
    collision radius inflated by division phase for the dumbbell) pushes overlapping cells
    apart every frame — measured settled overlap ≈ 0.0001 at 40 cells.
- **`render(encoder:features:)`** packs the live cells (≤ 64 × 24 B ≈ 1.5 KB) + a uniforms
  struct (aspect, energy, centroid, huePhase, hit, cellCount, time) via `setFragmentBytes`
  and draws the fullscreen triangle. The fragment (`mitosisgen2_fragment`, ported from the
  sketch) loops the cell buffer, composites each cell **over** the background + earlier cells
  (opaque membrane occludes — alpha-composite), then applies the music hue/vividness.
- **Backdrop:** the green filament field is drawn by the fragment itself (background term),
  or a `mitosisgen2_ground_fragment` like gen-1 — TBD at graduation; the sketch does it in
  one shader, which is the lazy default.

Sim is fully resolution-independent (procedural fragment) — no upscale blur lever to worry
about (unlike gen-1's RD grid). 1080p sketch cost ~4.7 ms/frame with 4 cells; ~3.5× under
the 60 fps budget, with headroom for more cells + finer detail.

## 5. Audio routing (one primitive per layer — D-026, FA #67)

| Visual layer | Primitive | Timescale | Mechanism |
|---|---|---|---|
| Cell phase progression (PRIMARY) | `energyEnv` | slow | `phase += dt·rate·(0.6+0.8·energy)` per cell |
| Cytokinesis SNAP (the event) | `drumsEnergyDev` → `hitEnv` | per-beat | a ready cell completes + splits into two daughters on the onset |
| Population (few large cells) | `energyEnv` | slow | spawn/cull governor inside the locked band; never crowds |
| Fluorescence hue | `centroidEnv` | slow | timbre → palette (MITOSIS.5) |
| Vividness + snap glow accent | `energyEnv` / `hitEnv` | slow / per-beat | energy → saturation; the snap carries a bounded chromatic glow (flash-safe) |

Cold-start: energy/centroid available frame 1; the snap is onset-gated, and a wrong
cold-start beat phase reads as a slightly-mistimed split, not a wrong-beat firing
(the cold-start contract's safe-use case).

## 6. Phased plan

| ID | Done-when |
|---|---|
| **MITOSIS-G2.0** | Throwaway sketch proves the detailed-dividing-cell look at 60 fps; `RENDER_VISUAL=1` contact sheet vs the reference; **Matt approves the look.** ✅ (2026-06-30) |
| **MITOSIS-G2.1** | Graduate. ✅ (2026-06-30) `MitosisGen2Geometry` (CPU `Cell` list + phase/snap/cull governor, no compute) + `mitosisgen2_fragment` (ported, `g2_`-prefixed) + `Cytokinesis.json`/`MitosisGen2.metal` backdrop + `ParticleGeometryRegistry`/`VisualizerEngine` wiring + count 25→26. Tests green: framerate 4.2 ms/frame @1080p; lifecycle (seed 3 → grows to cap 8, bounded; onset-driven 5 > silent control 3 — the snap mechanism); flash-safe maxΔ 0.015. App build SUCCEEDED, lint 0. Playable uncertified via `showUncertifiedPresets`. |
| **MITOSIS-G2.2** | Live-M7 iteration on the cell model. ⏳ pending re-look. **Iter 1 (2026-06-30):** Matt's live look rejected the G2.1 capped/cull model ("frequent respawning … cells should not overlap"). Reworked: monotonic growth few→`crowdCount`=40 (no cull), radius shrinks with count (`packRadius`, 0.62 coverage), a circle-packing `relax` so cells never overlap (settled overlap 0.0001 @ 40), then dissolve→regrow cycle; seed cells fade in (flash-safe reseed). Onset-snap removed (music coupling deferred — Matt: attach to music "ultimately"); arc runs autonomously, energy nudges pace. Tests rewritten (`test_growthArcAndPacking`: grows to crowd, non-overlap, dissolves & regrows); framerate 5.3 ms@1080p, flash-safe 0.014, app build + lint 0. **Iter 2 (2026-07-01):** Matt "more cell division needed; more space left to fill." Root cause of the gaps found — cells were drawn at only 0.55× their packing radius (`visibleFraction` mapping now fixes it so packing = visible size). Tuned denser + more active: `crowdCount` 40→64, `divPeriod` 11→8, `coverage` = 0.60 visible (max that packs non-overlapping). Overlap 0.0000 @ 64, framerate 3 ms, flash 0.026. → pending Matt's re-look. Later: wire the §1 musical role. |
| **MITOSIS-G2.3** | Certify: rubric `certifiedPresets` + `expectedAutomatedGate`, `PhotosensitivityCertificationTests.multiPassMeasured` + a `renderMitosisGen2` multi-pass flash harness, sidecar `certified: true`. First certified explicit-cell preset. |

## 7. Design grounding (descending preference — per checklist)

- **Reference image:** `docs/VISUAL_REFERENCES/mitosis/gen2_cytokinesis_confocal.png`
  (Matt-supplied confocal cytokinesis triple-stain) — the locked look target.
- **Level 1 (rendered evidence):** the approved sketch (`tools/mitosis_gen2_sketch/`) is the
  in-engine proof the form is achievable at fidelity and framerate.
- **Procedural techniques:** smooth-min metaball SDF (Inigo Quilez) for the dumbbell + furrow
  pinch; ridged fbm for the filament field; angular ring-sampled noise for the irregular
  aster fibres; alpha-composite for the occluding membrane. Public-domain math, own MSL.
- The fluorescence grade + the audio coupling are Phosphene-original (MITOSIS.5 lineage).

## 8. Reuse from gen-1 (do not destabilise the certified preset)

- `advanceEnvelopes` (energy/centroid/hit/huePhase smoothing) — port verbatim.
- The MITOSIS.5 colour model (centroid → palette, energy → vividness, drum → bounded glow).
- The certification pattern (rubric flags, `multiPassMeasured`, a `renderMitosisGen2` flash
  harness) — adapt, do not reinvent.
- The registration touchpoints (sidecar, `ParticleGeometryRegistry`, `VisualizerEngine`
  geo/factory/init/resolver, `expectedProductionPresetCount`, a load-degrade guard test) —
  mirror gen-1's MITOSIS.1 exactly.

## 9. The carried lesson (gen-1 arc)

Gen-1 burned three live M7s building a per-beat *churn* before Matt's one-line concept
pointed at the natural growth transient. Gen-2 locked the concept, the reference, and the
look on rendered evidence **before** any engine code (this doc). The remaining risk is the
*cell model feel* (how the split reads on the beat, how many cells, the aster character) —
that is a G2.2 live-M7 tuning question, surfaced as such, not a concept question.
