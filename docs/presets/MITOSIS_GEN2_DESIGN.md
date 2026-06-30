# Mitosis gen-2 — detailed fluorescence-microscopy cell division

**Status:** 🔨 **SCOPED (2026-06-30).** Sketch look approved by Matt; real increment
not yet built. Sibling of the certified gen-1 (`MITOSIS_DESIGN.md`), NOT an edit of it
(D-097). Kickoff: `MITOSIS_GEN2_KICKOFF.md`. Reference + traits:
`docs/VISUAL_REFERENCES/mitosis/README.md §Gen-2`.

**★ Concept (locked, Matt 2026-06-30).** A small number of **LARGE, procedurally-detailed
dividing cells**, rendered like confocal immunofluorescence microscopy — each cell a
dumbbell mid-cytokinesis with two radial green microtubule asters, a **solid opaque
membrane wall**, a coloured cortical ring, blue chromatin, a magenta spindle midzone, and
vesicle speckles, over a green filament field. The preset lives in the **early-growth /
first-division phase** so the per-cell detail stays legible — it never crowds down to tiny
dots (that is gen-1's job). Music-tied fluorescence palette (gen-1 MITOSIS.5 reuse).

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

- **Name / family:** Mitosis gen-2 (preset id TBD — e.g. "MitosisHD" / "Cytokinesis";
  confirm at graduation). A separate preset + sidecar (D-097).
- **Arc:** few large cells, always — early-division showcase, never crowds to dots.
- **Substrate:** explicit per-cell objects (position, radius, orientation, division phase,
  seed), NOT Gray–Scott.
- **Look:** confocal fluorescence — solid opaque membrane wall, coloured cortical ring,
  green asters, blue chromatin, magenta midzone, vesicle speckles, green filament field.
- **Palette:** music-tied (MITOSIS.5 model — centroid → hue, energy → vividness).

---

## 4. Rendering architecture (grounded in the gen-1 geometry contract)

**`MitosisGen2Geometry`** — a `ParticleGeometry` sibling (like `MitosisGeometry`), but
*without* the RD compute path:

- **State = a small CPU `Cell` array** (`var cells: [Cell]`, cap ~16; the locked arc keeps
  ~3–10 large cells live). `Cell` = `{ pos: SIMD2, radius, axis, phase, phaseRate, seed,
  alive }`.
- **`update(features:stemFeatures:commandBuffer:)`** advances the music envelopes
  (`energyEnv`, `centroidEnv`, `hitEnv`, `huePhase` — port gen-1's `advanceEnvelopes`
  verbatim), then advances the cell model on the CPU:
  - each live cell's `phase += dt * phaseRate * energyPace`;
  - on a `hitEnv` onset, the most-ready cell (highest phase past a threshold) **snaps**:
    its phase completes, and it is replaced by **two daughter cells** (split along its axis,
    radii halved-then-regrow, fresh seeds);
  - a slow population governor keeps the count in the "few large cells" band (cull the
    smallest/oldest when over cap; spawn when energy is up and under floor), giving the
    grow→divide cycle without ever crowding.
  - No compute encoder needed (the RD field is gone); `commandBuffer` goes unused.
- **`render(encoder:features:)`** packs the live cells into a `setFragmentBytes` buffer
  (≤16 cells × 32 B ≈ 512 B, well under the 4 KB limit — no MTLBuffer management, ponytail)
  plus a uniforms struct (time, resolution, energy, centroid, huePhase, hit), and draws the
  fullscreen triangle. The fragment shader (ported from the sketch `Gen2Cell.metal`) loops
  over the cell buffer, composites each cell **over** the background + each other (opaque
  membrane occludes — the sketch's alpha-composite model), then applies the music hue/vividness.
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
| **MITOSIS-G2.1** | Graduate: `MitosisGen2Geometry` (explicit cell list + CPU phase/split/governor) + the ported fragment shader in the engine GPU contract + sidecar (`family: particles`, `certified: false`) + registry/`VisualizerEngine` wiring + `expectedProductionPresetCount++` + headless tests (framerate, cell lifecycle: spawn→advance→snap→two daughters→cull, flash-safe). Playable uncertified via `showUncertifiedPresets`. |
| **MITOSIS-G2.2** | Audio coupling + **live M7**: energy→phase, onset→snap, centroid→palette wired to the live stream; Matt's live look; iterate the cell model + look against his feedback (this is where the aster-character / cell-count / snap-feel tuning lands). |
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
