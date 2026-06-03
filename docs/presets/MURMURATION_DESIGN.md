# Murmuration — Design Doc (Phase MM)

**Status:** MM.1 draft for Matt's approval. No flock code until this is approved.
**Author:** Claude (with Matt's direction + reference material, 2026-06-03)
**Supersedes:** the cosmetic Phase SB plan.

---

## 1. Creative intent (the one-sentence musical role)

> **A dense flock of starlings is another instrument in the band: the music is the wind that
> stretches and drifts the whole mass, each beat is a predator-strike that fires a dark
> orientation-wave rolling across the flock, the vocal phrase is the breath that compresses and
> releases it, and the mid-range shimmer is the flutter at the feathered edge.**

Every behaviour below names a specific musical feature and the specific visual response a listener
pairs with it. If a layer can't pass that test it doesn't ship (CLAUDE.md Authoring Discipline; FA
#58/#62).

---

## 2. What the references actually show (signature decomposition)

From `docs/VISUAL_REFERENCES/murmuration/` (the May still set, confirmed current) + the biomechanics
literature. The current implementation fails the first three of these, which is why Phase MM is a
redesign, not a tuning pass.

| Trait | Reference | Current impl |
|---|---|---|
| **Dense, emergent, *amorphous* mass** — morphing comma/ribbon/blob, never an ellipse | `01`, `02`, `03` | ✗ parametric ellipse of fixed home-slots |
| **Core→edge density gradient** — solid dark core fading to a stippled, ghostly, *feathered* edge; sometimes a detached trailing cluster | `03` | ✗ density keyed only to along-axis position |
| **Reads as thousands of birds**, core birds sub-pixel | `01`, `03` | ✗ 5,000 "each bird visible" sprites = the anti-reference (`05_anti_countable_individuals`) |
| **Dusk gradient backdrop** (indigo→lavender→peach→amber, or saturated red-orange peak) | `06_*` | ✓ sky fragment is roughly right (kept, polished in MM.4) |
| **NOT** scattered dots with no shape | `05_anti_dispersed_no_shape` | failure mode if cohesion too weak |

**The biomechanics that explain the *movement* (McGill analysis):**
- Birds interact with their **6–7 nearest (topological) neighbours**, not a fixed metric radius —
  this is what keeps the flock cohesive at any density and gives the scale-free "one organism" feel.
- The travelling **dark bands are *orientation* waves, not density waves**: birds execute coordinated
  rolling manoeuvres ("zigs/zigzags") that turn more wing-surface toward the viewer, darkening a band
  that propagates *faster than the flock itself* (~13.4 vs 10.6 m/s). **This is the single most
  important rendering insight** — beats should fire orientation waves, not bunch birds together.
- Shape stays thin-vertical / elongated-horizontal with roughly constant aspect ratio, and stays
  level during turns.
- Polarisation ≈ 0.96 (very high alignment); the flock sits at a **critical noise point** — too
  little noise = frozen/inertial, too much = incoherent. We will need a tunable noise term.
- Predator response scales: dilution → blackening + wave events → **flash expansion (4–10× faster)**,
  and ~78% of expansions re-cohere without splitting.

---

## 3. Musical contract (the load-bearing table)

One audio primitive per visual layer, one timescale each (FA #67); all deviation primitives (D-026);
continuous drivers 2–4× the beat accents (Audio Data Hierarchy).

| # | Visual layer / behaviour | Audio driver | Timescale | Biological analogue |
|---|---|---|---|---|
| L1 | **Global drift + shape elongation** — the roost attractor translates and stretches; flock becomes comma/ribbon under sustained low end | `bass_att_rel` | slow / continuous — **primary** | "the wind" |
| L2 | **Orientation wave** — a dark band of banking birds rolls across the mass on each beat; direction alternates per beat-epoch | `drums_energy_dev` + beat phase | per-beat — **accent** | predator-strike "wave event" |
| L3 | **Flash expansion + re-cohesion** — strong drum transients/drops briefly blow the mass open, then it re-gathers | `drums_energy_dev` large transients (gated above L2) | per-drop — **rare accent** | high-threat flash expansion |
| L4 | **Edge flutter / shimmer** — topological-edge birds (few neighbours) get extra noise; periphery flickers, core stays solid | `mid_att_rel` | fast | feathered-edge turbulence |
| L5 | **Breathing** — whole-mass cohesion radius tightens (dark pulse) then releases | `vocals_energy_dev` | phrase | blackening / dilution |
| L6 | **Sky warmth** (≤10%, secondary, never competes with the flock) | `spectral_centroid` | slow | dusk light |

**Provisional until Matt's motion clips.** L1–L6 are grounded in biology + the stills. The *exact
feel* of each (how far the comma stretches, how visible a single-beat wave should be, how often a
flash-expansion should fire) is a **temporal contract that only the motion clips can pin down**.
MM.1's remaining step is Matt's notes on specific clip moments (e.g. "the pivot at 0:15 in clip 2");
those refine the magnitudes here before MM.2 freezes them.

### 3.1 Signal coordination — NOT all-at-once (load-bearing)

The six layers are **not** six always-on peers. A real murmuration is mostly calm and highly
coordinated (polarisation ≈ 0.96), drifting and breathing, *punctuated* by discrete events — so the
coordination below is what makes the result faithful, not a compromise against it. Three mechanisms:

1. **Two tiers, not six peers.**
   - **Continuous substrate** — always gently on, but each layer acts on an **orthogonal degree of
     freedom** so they cannot fight: L1 bass → *where + how stretched* (roost-attractor translation
     and shape), L5 vocals → *how tight* (cohesion radius / density breathing), L4 mid → *edge
     shimmer only* (high-frequency noise applied to topological-edge birds, not the core). A real
     flock drifts, breathes, and shimmers at its edge simultaneously the same way.
   - **Punctuated events** — discrete and arbitrated: L2 drum → orientation wave, L3 drop → flash
     expansion. These act on the *same* collective DOF, so they pass through a **single event bus**
     with a refractory period: one event travels at a time, a flash-expansion supersedes an in-flight
     wave, nothing stacks.

2. **Events are beat-quantized; the substrate is free-running.** This is the "rhythmic coordination":
   orientation waves are launched on the beat grid and alternate direction per beat-epoch (the
   natural weaving zigzag); drift/breath flow continuously. The rhythm lives in the event layer only.

3. **The boids substrate is its own low-pass filter.** Momentum + banking limits + 7-neighbour
   coupling mean the flock physically cannot respond instantly or twitch in six directions — every
   injected signal is integrated into one coherent collective motion. (This is *why* boids replaces
   the old ellipse-spring model: the substrate absorbs simultaneous input instead of amplifying it,
   which is also the McGill "critical noise" requirement.)

**Master lever — energy-gated drama.** The entire event layer's amplitude is scaled by overall
energy/arousal (and may key off orchestrator section context). In a calm passage the flock is
essentially pure substrate — drifting and breathing, almost no waves; the predator-strike drama only
emerges as the music intensifies. **This is the single biggest "realistic vs. busy" knob**, tuned
against the motion clips in MM.3. Default bias: err toward calm — under-react rather than over-react.

---

## 4. Technique + grounding (research-first, per CLAUDE.md grounding priority)

**Chosen technique: GPU boids (Reynolds separation / alignment / cohesion) over ~6–7 grid-found
neighbours, plus an audio-driven global roost attractor, plus per-bird banking dynamics, simulated
in 3D and projected to screen.** The cohesive morphing shape and the density gradient are then
*emergent* (they fall out of cohesion + attractor + 3D projection) rather than imposed — which is the
whole point of the redesign.

**Grounding (level 1 — working code references in a comparable visual context):**
- **Robert Hodgin, *Murmuration*** (roberthodgin.com/project/murmuration) — the canonical
  generative-art starling look. GPU compute boids; 40K realtime, **1M flockers at 30+ fps on a modern
  GPU**. Confirms the technique scales far past our needs and *is* the look we're chasing.
- **Rama Hoetzlein, *Flocking*** (ramakarl.com/flocking) — Reynolds' three rules on **seven
  neighbours**, a three-level hierarchy: per-bird flight physics (banking, can't instantly turn →
  overshoot/undulation), group boids, and a **global roosting attractor (a moving guide line)**. This
  three-level structure is exactly our architecture, with the roost attractor as the audio hook.
- **`Flocking-Simulation` (techcentaur)** — concrete 3-zone boids params (separation/alignment/
  cohesion blended by cosine between zones) as an implementation starting point.

**Grounding (level 2 — biology):** the McGill analysis (§2) for topological neighbours,
orientation-vs-density waves, aspect-ratio constancy, the critical-noise requirement, and predator
escape tactics.

**Infrastructure precedent (in-repo):** `PhospheneEngine/Sources/Presets/FerrofluidOcean/
FerrofluidParticles.swift` already runs a GPU **spatial-binning** kernel (bin → sort → neighbour
iterate) for 2,500 particles. Murmuration's neighbour-grid boids is the same pattern at higher count.
No net-new engine *capability* — particles pass already exists (D-029); this is a new conformer.

**Grounding level for the *audio coupling* specifically:** the visual *mechanisms* (orientation
waves, flash expansion, breathing) are biology-grounded; *mapping them to stems* is my design (level
3). Flagged honestly — this is where MM.3 must show per-route firing evidence, not assertion.

---

## 5. Architecture

- **New engine-library shader** `Shaders/MurmurationFlock.metal` with kernels:
  `murmuration_bin` (assign particles to a uniform 3D grid), `murmuration_boids` (the integrator:
  read ~7 grid neighbours → separation/alignment/cohesion + roost attractor + banking + noise →
  integrate), and the render `murmuration_flock_vertex` / `_fragment`. This is the deferred-from-MM.0
  split: the generic `ProceduralGeometry` / `Particles.metal` becomes the flock-specific sibling
  (D-097 "siblings, not subclasses").
- **New conformer** `MurmurationFlockGeometry: ParticleGeometry` (replaces `ProceduralGeometry` as
  Murmuration's geometry; `ProceduralGeometry`/`Particles.metal` retired if no other consumer — grep
  confirms Murmuration is the only one). `ParticleGeometryRegistry.knownPresetNames` stays
  `["Murmuration"]`; `resolveParticleGeometry` returns the new conformer.
- **Particle struct.** The existing 64-byte `Particle` already carries `packed_float3 position`
  (z currently 0) and `velocity` — enough for 3D + banking phase packed into `size`/`age`/`_pad`.
  Target: **no struct-size change** (keeps the D-099 byte-layout discipline; if banking needs a
  dedicated field we extend additively and regen golden hashes, per `project_engine_msl_struct_extension`).
- **Passes** stay `["feedback", "particles"]` (D-029) — the feedback pass is the trail decay, not an
  independent motion source; we may reduce/disable trail so the silhouette stays crisp (decided in MM.4).

---

## 6. Particle count + performance

- **Design target: ~50,000 birds** (3D). Hodgin hits 40K realtime on older hardware and ~1M on a
  modern GPU; grid-neighbour boids at 50K on Apple Silicon is comfortably inside the 60fps@1080p
  budget. Enough that core birds are sub-pixel and the mass reads dense (kills the
  `05_anti_countable_individuals` failure mode).
- The frame-budget governor's `activeParticleFraction` already scales dispatch; `complexity_cost`
  recalibrated in MM.4. Perf is validated empirically in MM.4 (p95 ≤ tier budget), not assumed here.
- Neighbour query cost is the risk; the uniform grid bounds it to a fixed cell neighbourhood. If 50K
  is tight we step down (30K) before sacrificing the grid — density is more important than raw count
  past the "core is sub-pixel" threshold.

---

## 7. Rendering

- **Birds:** small near-black sprites (dusk silhouettes), size/elongation along velocity. Core birds
  ≤1px; the density gradient is *particle concentration*, not per-sprite alpha tricks.
- **Orientation-wave dark bands (L2):** each bird carries a banking phase; brightness/effective sprite
  area is modulated by banking angle so a propagating orientation wave reads as a moving darker band
  (faithful to the McGill mechanism). The wave is injected on-beat and propagates via the
  alignment-coupling that already links neighbours.
- **Density gradient + feathered edge:** emerges from 3D projection + cohesion; edge birds (low
  neighbour count) get the L4 noise so the boundary stipples rather than cutting hard.
- **Sky (MM.4):** keep the dusk gradient direction; migrate the bespoke `sky_hash/noise/fbm` to the
  V.1 Noise utility tree at ≥4 octaves (rubric M1/M2 on the sky surface), palette per `06_*`. The sky
  is the canvas; it must never out-compete the flock.

---

## 8. Fidelity-risk statement (honest, per CLAUDE.md)

- **Technique risk: LOW.** GPU boids + grid + attractor is the proven, well-precedented way to make
  this exact image; the infrastructure exists in-repo.
- **Tuning risk: MEDIUM–HIGH, concentrated in MM.2/MM.3.** Boids at a "critical noise point" is
  famously finicky: too much cohesion → a clumping ball; too little → the `05_anti_dispersed`
  failure; emergent orientation waves require the alignment coupling + banking to be balanced so a
  beat-injected wave actually *propagates* instead of dissipating. Expect several tuning rounds. The
  multi-frame production-pipeline harness (MM.2, mandatory) + per-route firing evidence (MM.3) are how
  we converge instead of guess. The motion clips are what make "right feel" objective.
- **Mitigation:** silence baseline first (a cohesive, density-graded, gently-drifting mass with *no*
  audio) before any coupling. If silence doesn't read as a murmuration, no coupling will save it.

---

## 9. Open questions for Matt

1. **Motion-clip notes** (the one true blocker for finalizing §3 magnitudes): a few specific moments
   to anchor the temporal contract — a drift/stretch you like, a beat-wave you want visible, a
   flash-expansion moment. I can't fetch YouTube; downloaded frames or timestamped notes both work.
2. **Camera framing:** the stills are mixed (from-below `01`, side `02/03`). Single fixed framing, or
   a slow drift? Recommend a slow, near-static wide framing so the *flock's* motion is the motion.
3. **Flash-expansion (L3):** in or out for v1? It's the most dramatic beat response but also the most
   tuning-heavy. Recommend building L1/L2/L4/L5 first and adding L3 once the base reads right.
4. **Trail/feedback:** crisp silhouette (little/no trail) vs a slight motion-trail smear. Recommend
   crisp — the references have no smear.

---

## 10. Increment path (detail in ENGINEERING_PLAN.md Phase MM)

- **MM.1** (this doc) → Matt approval.
- **MM.2** — flock engine + multi-frame harness; silence baseline reads as a dense, cohesive,
  density-graded mass.
- **MM.3** — audio coupling (the §3 table) with per-route firing evidence.
- **MM.4** — sky + render polish + performance (60fps@1080p, rubric M1/M2 on sky).
- **MM.5** — M7 review vs references + clips, certify.
