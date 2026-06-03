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

## 2.1 Motion analysis — from Matt's clips (2026-06-03)

Four 1074×604 clips in `tools/murmuration_reference/` (git-ignored; FOX Weather / stock footage —
**not** committed to the reference library for licensing reasons). Frames sampled with ffmpeg at the
timestamps Matt flagged. Findings (frame citations are `clipNN_tSSS`):

**Shape vocabulary** — the flock continuously cycles through a small set of forms:
- Rounded dense ovoid / blob — the at-rest archetype (`clip01_t014`, `clip02_t003`).
- **Comma / teardrop**: dense head, tapering trailing wisp — the directional-motion form
  (`clip02_t027`, `clip01_t080`).
- **Thin wide level sheet**: elongated horizontal, thin vertical, hugging the roost — the McGill
  aspect-ratio constancy made visible (`clip01_t038`, `clip04_t100`).
- **Curl / hook**: a sharp collective pivot (`clip02_t082`).
- **Split + re-cohere**: the mass sheds a detached trailing sub-cluster that streams below and then
  rejoins (`clip02_t074`, `clip02_t078`).

**Timescales (this is the load-bearing finding for the contract):**
- **Major shape change** (blob → comma → blob) takes **~5–12 s**. Shape is NOT a per-beat response —
  it tracks the *sustained* low end. → confirms **L1 = bass, slow/continuous**.
- **Internal density/orientation bands** — visible dark streaks rippling *across* the body — traverse
  the mass in **~1–2 s** (`clip01_t014`, `clip01_t080`, `clip03_t095`). This is exactly the
  orientation-wave signature. → confirms **L2 = per-beat wave**, traversal ~0.5–1.5 s.
- **Whole-mass breathing** (large `clip02_t003` → tight `clip02_t019`) over **phrase scale (~4–8 s)**.
  → confirms **L5 = vocals**.
- **Edge** is *always* feathered/stippled, periphery sparser than core, in every non-settling frame.
  → confirms **L4 edge flutter** + the density-gradient rendering requirement (§7).
- **Drift** across frame is slow and continuous; the **camera is effectively static** in the good
  examples — the *flock* is the motion (confirms §9 framing decision).

**Density:** a continuous textured field of thousands of sub-pixel dots; dense core, stippled
feathered edge; never countable individuals **except** when settling/dispersing (`clip02_t086`,
`clip04_t100`) — that dispersed state is the documented anti-reference, i.e. the state to leave
quickly, not rest in.

**Palette range** observed: bright-blue daylight → saturated orange-red dusk (`clip01_t080`, matches
`06_palette_saturated_peak`) → cool blue dusk (`clip01_t038`) → misty grey (`clip03`). Birds read as
near-black silhouettes across all of them.

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

### 3.2 CARRY FORWARD the original Murmuration's audio coupling (binding — Matt 2026-06-03)

The pre-MM `Particles.metal` (the original 5K-ellipse flock) was a parametric ellipse, **but its
audio coupling was advanced and had days of tuning in it.** MM.3 **ports and adapts those proven
mappings onto the boids substrate — it does NOT reinvent them from scratch** (doing so was the
"starting over" / deja-vu mistake Matt flagged). The boids substrate (MM.2) is the genuinely-new
piece; the audio *brain* is carried forward. Specifically, lift from the original:

- **Drum turning-wave propagation** → this IS L2. The original's mechanic: `beatEpoch = floor(t·2.5)`
  with per-epoch alternating `propDir`; a wave front `waveFront = 1 − beatPulse` sweeps a bird-flock
  coordinate; a triangular bump `waveInfluence = max(0, 1 − |waveFront − birdCoord|/waveWidth)`
  applies a **perpendicular** turning force. Port this as a banking/turn impulse propagating across a
  flock-axis coordinate so the dark orientation band rolls across the mass. Don't redesign it.
- **Bass → macro drift + shape elongation** (L1): the original drove `halfLength/halfWidth` + drift
  from `rhythm`. On boids: bass displaces the roost target (drift) and elongates cohesion
  anisotropically (comma/ribbon).
- **"Other"/mid → edge-weighted flutter** (L4): original weighted flutter by `distFromCenter`
  (periphery ≈4× core). On boids: weight by inverse `neighborCount` (already computed).
- **Vocals → density compression / "dark pulse"** (L5): original `densityScale = 1 − vocals·0.22`.
  On boids: tighten cohesion/separation radius → breathing.
- **Warmup stem-blend** (D-019): `smoothstep(0.02, 0.06, totalStemEnergy)` crossfade from full-mix
  FeatureVector routing to stem routing. Keep it.
- **Cross-genre beat coverage** (FA #26): key the beat off `max(beatBass, beatMid, beatComposite)`,
  not `beatBass` alone.

All of the above must become **deviation primitives** (D-026) where the original used raw energy —
that conversion is the one place MM.3 *improves* on the original rather than porting it verbatim.

**Magnitudes (derived from the §2.1 clip analysis; final values tuned in MM.3):**
- **L1 bass** → roost-attractor drift + elongation, smoothed over **~4–8 s** (matches the 5–12 s
  observed shape-change cadence); comma head:tail aspect up to **~3:1** at sustained high bass.
- **L2 drums** → one orientation (banking) wave per beat, traversing the mass in **~0.5–1.5 s**,
  direction alternating per beat-epoch (the observed weaving).
- **L3 drop** (deferred per §9) → split/flash that sheds **~10–20%** as a trailing cluster, re-cohering
  over **~2–4 s**.
- **L4 mid** → edge-bird noise, fast (sub-second), amplitude weighted by inverse neighbour-count.
- **L5 vocals** → cohesion-radius breathing **±~20–30%** over **~4–8 s** (phrase).
- **L6 spectral_centroid** → sky warmth ≤10%, slow.

These are starting magnitudes grounded in the footage; MM.3 dials final feel against live sessions +
Matt's review, with the clips as the yardstick. Default bias: under-react (§3.1).

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
  independent motion source. **Decided (Matt 2026-06-03): crisp** — trail decay set near-off so the
  silhouette stays sharp (references have no smear).

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

## 9. Resolved decisions (Matt, 2026-06-03)

1. **Camera framing → static, wide.** Fixed wide framing; the *flock's* motion is the only motion.
   No camera drift. (Affects §7 — projection is a fixed orthographic/wide-perspective view.)
2. **Flash-expansion (L3) → deferred.** Build L1/L2/L4/L5 first; add L3 once the base reads right
   (MM.3 builds the substrate + orientation wave; L3 is a follow-on step, not v1 of the coupling).
3. **Trail/feedback → crisp.** Minimal/no motion-trail smear; the references have none. The
   `feedback` pass is kept in `passes` for paradigm-legality (D-029) but its decay is set so the
   silhouette stays crisp (effectively near-off).

### 9.1 Motion-clip handling — DONE (2026-06-03)

Matt supplied four clips in `tools/murmuration_reference/` with timestamped notes; frames were
extracted (ffmpeg) at the flagged moments and analyzed — see **§2.1**. The §3 magnitudes are now
grounded in that footage. Final feel is still dialed in MM.3 against live sessions + Matt's review,
with the clips as the yardstick (and for the M7 gate in MM.5), per the Fata Morgana live-tuning
precedent. The raw clips/frames stay git-ignored (licensed stock); the committed artifact is the
§2.1 written breakdown.

---

## 10. Increment path (detail in ENGINEERING_PLAN.md Phase MM)

- **MM.1** (this doc) → Matt approval.
- **MM.2** — flock engine + multi-frame harness; silence baseline reads as a dense, cohesive,
  density-graded mass.
- **MM.3** — audio coupling: substrate (L1 bass / L5 vocals / L4 mid) + L2 orientation wave first,
  with per-route firing evidence + energy-gating; **L3 flash-expansion deferred** to a follow-on step
  once the base reads right.
- **MM.4** — sky + render polish + performance (60fps@1080p, rubric M1/M2 on sky).
- **MM.5** — M7 review vs references + clips, certify.
