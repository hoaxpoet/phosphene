# Phase PG — Psychedelic Geometry — Overview & Shared Conventions

**Status:** Design set, authored 2026-07-20. Awaiting Matt sign-off on the slate, the phase ID, and the per-preset DECISION-NEEDED blocks.
**Author seat:** design/prompt-authoring (not implementation). Every preset here is authored to design here first; Claude Code implements from the per-preset docs.
**What this is:** five Phosphene-native "psychedelic geometry" presets — intricate nested geometry (shapes inside shapes; smaller shapes making larger shapes) whose *motion transforms the canvas*, each visually distinct and each exploring a **different way for music to drive it**. This overview is the map; each preset has its own combined design + session-prompt doc (`PG_1`…`PG_5`).

> **How to use this set with Claude Code.** Feed **one** per-preset doc into a fresh session. Each per-preset doc is self-contained: Part A is the committed design record; Part B is the runnable session prompt that references Part A. This overview is context Matt reads, and it is worth pasting the "Shared audio contract" and "Shared JSON/metadata conventions" sections below into any session as a preamble, but it is not required reading for Claude Code if the per-preset doc is followed.

---

## 1. The slate at a glance

| # | Name (working) | Nested-geometry idea | Motion paradigm (D-029/D-120) | Music-response strategy (the differentiator) | Rubric |
|---|---|---|---|---|---|
| PG.1 | **Mandala Engine** | Radial kaleidoscopic mandala — concentric rings of self-similar motifs via recursive mirror-folding | `mv_warp` (kaleidoscope scene + feedback breathing) | **Continuous energy + structure** — bass swells the radial breath; a new concentric ring *blooms* on the downbeat | lightweight* |
| PG.2 | **Droste Descent** | Infinite log-polar self-similar zoom tunnel — the frame contains a smaller copy of itself, forever | `mv_warp` (the feedback loop *is* the recursion) | **Beat-locked forward travel** — the tunnel pulls inward one ring per beat via the cached BeatGrid | lightweight* |
| PG.3 | **Mandelbox Cathedral** | 3D Kaleidoscopic-IFS / Mandelbox — fold-and-scale builds vast architecture from self-similar copies | `ray_march_static` (camera holds; geometry morphs) | **Harmonic / melodic morph** — sustained bass unfolds deeper nested structure; vocal pitch twists the fold | full |
| PG.4 | ~~**Truchet Loom**~~ ❌ **RETIRED (TLRETIRE.1 / D-194)** — built PG.4.1–4.3, failed first live M7 (square lattice read as a jittering grid, matched none of the flowing-scallop refs, "not psychedelic geometry"). Mechanic (blocky Truchet) ≠ curated refs (flowing op-art). | — | ~~Complexity / density mapping~~ (the music idea may be worth re-vehicling; the Truchet vehicle was wrong) | — |
| PG.5 | **Poincaré Bloom** | Hyperbolic Circle-Limit tiling — shapes nest and shrink infinitely toward a boundary, slid through itself by Möbius flow | `direct_time_modulation` (Möbius flow; crisp curved detail) | **Per-stem spatial routing** — drums / bass / vocals each move a different channel of curved space | lightweight* |

\* Rubric profile for the four 2D presets is a **DECISION-NEEDED** (see §6). `lightweight` is the recommended default (they are stylized 2D, like Plasma/Nebula), but the detail-cascade *principle* — multi-scale nesting, ≥4 octaves of variation, saturated non-pale palettes — still applies. Mandelbox is unambiguously `full`.

**Why these five and not five variations of one idea.** The two axes that matter for a visualizer catalog are *what you see* and *how the music reaches it*. This slate deliberately spreads both:

- **Five distinct geometries**: flat radial mandala / receding log-polar tunnel / volumetric 3D fractal architecture / flat op-art tiling / curved-space (hyperbolic) tiling. No two share a silhouette.
- **Five distinct music-response strategies** — this is the explicit ask ("different ways for music to respond"), and it is the strongest differentiator:
  1. **Continuous + structural** (energy breathes, structure blooms) — PG.1
  2. **Rhythmic lock** (beat = forward motion, anticipatory) — PG.2
  3. **Harmonic/melodic morph** (the *geometry itself* transforms with pitch + sustained bass) — PG.3
  4. **Complexity mapping** (musical busyness = geometric busyness) — PG.4
  5. **Stem-separated spatial routing** (you *see* the separated instruments each moving a different region) — PG.5
- **Motion-paradigm spread** (D-029 says one paradigm per preset): 2 × `mv_warp` (radically different warps — radial breathing vs. log-polar Droste), 1 × `ray_march_static`, 2 × `direct_time_modulation` (radically different geometry — Truchet tiles vs. hyperbolic disk).

None duplicates the existing catalog (verified against the module map: no kaleidoscope, tunnel, Mandelbox/KIFS, Truchet, or hyperbolic preset exists; Lumen Mosaic is Voronoi stained-glass, Volumetric Lithograph is terrain — both distinct).

---

## 2. Design invariants every preset in this set honors

These come straight from the project's authoring rules. Each per-preset doc restates the ones specific to it; this is the shared baseline.

- **Concept-viability gate cleared before authoring (`SHADER_CRAFT.md §2.0`).** Each doc opens with the three gates: (1) a one-sentence **musical role** naming a specific musical feature *and* a specific paired visual behaviour; (2) **iconic subject deliverable at fidelity** (a comparable past preset or a cited published reference); (3) **infrastructure-feasible** (no render passes or GPU contracts Phosphene lacks). "Vibe with the music" is not a musical role.
- **Deviation primitives, never absolute thresholds (D-026 / FA #31).** Drive from `f.bass_rel`/`f.bass_dev`, `stems.*_energy_dev`, etc. Patterns like `smoothstep(0.22, 0.32, f.bass)` fail across tracks and sections. See §3.
- **One primitive per visual layer at one timescale (FA #67).** Each doc carries a `(visual layer × audio primitive × timescale)` table and self-checks it. Routing the same beat-rate primitive into two layers reads as the visual "fighting itself."
- **Signal liveness (`preset-session` skill §14.1).** Drive motion only from primitives that actually vary on real music. `f.bass_rel` (signed) is the best continuous driver; `f.spectral_flux` and the beat fields are reliably alive across genres; `f.mid`/`f.treble` *absolute* values are near-dead on bass-dominant music; `f.*_dev` works post-AGC2 but mid/treble `*_dev` carry smaller amplitude (use larger gain) and have a 1–2 s cold-start warmup; `vocals_pitch_confidence` must be gated (≥ 0.6) with a fallback.
- **Silence must never render black (D-037).** Each doc defines a non-black, alive-but-calm silence state (`totalStemEnergy == 0`).
- **One rendering paradigm per preset (D-029).** No stacking `mv_warp` on a moving camera or a particle system. `mv_warp` is compatible with direct-fragment presets and static-camera ray-march scenes only.
- **Reference-first authoring (D-064 / D-065 / `PRESET_SESSION_CHECKLIST.md`).** Visual references are locked *before* the session prompt runs. Because these geometries are abstract, §5 below and each doc's "Reference sourcing" section give a concrete shopping list. Curation is Matt-owned and is a pre-flight gate in every session prompt.
- **Desk-research / port-the-reference discipline (FA #64 / #65 / #73).** For the fractal, tunnel, and hyperbolic mechanics there are canonical published implementations (Quilez, Syntopia/Knighty, Escher). The docs cite them as porting targets and instruct Claude Code to **read and port** rather than derive from first principles. This is the single biggest quality lever for the harder presets.

---

## 3. Shared audio contract (cheat sheet)

Paste this into any implementing session as a preamble; it saves the author from re-deriving what is safe to route.

**Where the data lives (preset fragment shaders).** Bind per the canonical fragment layout in `ARCHITECTURE.md §GPU Contract Details` (the authoritative, corrected contract) and confirm against a reference preset before writing bindings:

| Slot | Content | Notes |
|---|---|---|
| `buffer(0)` | `FeatureVector` (192 B, 48 floats) | all fragment encoders — declare `constant FeatureVector& f [[buffer(0)]]` |
| `buffer(1)` | FFT magnitudes (512 floats) | spectrum texture data |
| `buffer(2)` | waveform samples | oscilloscope data |
| `buffer(3)` | `StemFeatures` (256 B, 64 floats) | per-stem energy/dev/rich-metadata/pitch |
| `buffer(4)` | `SceneUniforms` (128 B) | **ray-march G-buffer/lighting/SSGI only** (PG.3) |
| `buffer(5)` | `SpectralHistory` (16 KB) | **true `direct`-pass only** — 8 s trails of valence/arousal/beat_phase01/bass_dev/bar_phase01 + cached BeatGrid metadata. **PG.4/PG.5 (`direct`) can read it. PG.1/PG.2 are `mv_warp`** — their scene fragment is bound via the mv_warp scene pass, which does *not* bind slot 5, so they must read beat fields from `FeatureVector` `buffer(0)` (`f.beat_phase01`/`f.bar_phase01` live there) and not assume SpectralHistory is present. |
| `buffer(6/7/8)` | per-preset state buffers | `setDirectPresetFragmentBuffer{,2,3}`; references: NimbusState (slot 6, direct), Gossamer/Arachne (6/7), LumenPatternEngine (slot 8, ray-march) |

**Primitives worth routing (and their liveness verdict):**

| Primitive | What it is | Liveness | Good for |
|---|---|---|---|
| `f.bass_rel` (signed), `f.bass_att_rel` | deviation of bass from its running average, recentre with `(x+0.5)` | **alive, best continuous driver** | breathing, zoom, radial scale |
| `f.bass_dev` / `f.mid_dev` / `f.treb_dev` | positive-only deviation (post-AGC2) | alive; mid/treble smaller amplitude (bigger gain) + 1–2 s warmup | accents, gated brightening |
| `f.spectral_flux` | broadband change rate | **alive across genres** | texture motion, density, complexity |
| `f.spectral_centroid` | brightness/normalized | alive | hue temperature, fine-detail level |
| `f.beat_phase01`, `f.bar_phase01`, `f.beats_per_bar` | analytic phase from cached BeatGrid (0→1) | alive when a grid is installed; **phase may be wrong at track cold-start** | beat-locked motion, downbeat blooms (PG.1/PG.2) |
| `f.beatBass/beatMid/beatTreble/beatComposite` | onset pulses (±80 ms jitter) | alive as accents only | bounded per-beat flashes; never primary motion |
| `f.valence`, `f.arousal` | mood (−1…1), ~0.7 s smoothed | alive, slow | palette temperature, agitation, density baseline |
| `f.accumulated_audio_time` | energy-weighted clock | monotonic | slow palette drift, phase advance |
| `stems.{drums,bass,vocals,other}_energy_dev/rel` | per-stem deviation | alive; use `smoothstep(0.02,0.06,totalStemEnergy)` warmup crossfade (D-019) | per-stem spatial/hue routing (PG.5), per-layer accents |
| `stems.vocals_pitch_hz`, `vocals_pitch_confidence` | YIN pitch (PT.1 fixed) | alive **only when confidence ≥ 0.6** | melodic hue/twist (PG.3) with fallback |
| `stems.drums_energy_dev_smoothed` | 150 ms-τ EMA | alive | non-strobing drum envelope |

**Hard rules:**
- **Continuous energy is the primary driver; beats are accents.** Rule of thumb: `base_zoom`/`base_rot` should be 2–4× larger than `beat_zoom`/`beat_rot`.
- **Beat-locked motion (PG.2, and PG.1's downbeat bloom) uses the cached `BeatGrid`** (`beat_phase01`/`bar_phase01`), never raw live onsets. Bounded spatial footprint per beat + steady global luminance (D-157); beat-irregular tracks are excluded from strictly beat-locked motion (D-154). The FFO beat-sync work (D-153 → D-158) is the pattern to follow.
- **Cold-start:** grid *phase* can be wrong in the first ~3 s of a track. Presets that key motion to the beat implement their own cold-start suppression (a time-since-track-start envelope) so a wrong-phase track doesn't fire wrong-beat motion hard. `beat_phase01`/`bar_phase01` are not gated by the engine — use them where a small phase error reads as a small offset, not a wrong-beat jump.

---

## 4. Shared JSON / metadata conventions

Every preset ships a `<Name>.json` sidecar (schema: `SHADER_CRAFT.md §17`). Common fields for this set:

```jsonc
{
  "name": "Mandala Engine",
  "family": "geometric",                // Phosphene-native; NOT milkdrop_inspired (see below)
  "concept_tags": ["kaleidoscope", "hypnotic", "geometric"],  // D-120 controlled vocab
  "motion_paradigm": "mv_warp",         // D-120: one of the 8 paradigms
  "passes": ["mv_warp"],                // or ["ray_march","ssgi","post_process"] for PG.3
  "duration": 30,
  "certified": false,                   // flipped only after Matt M7
  "rubric_profile": "lightweight",      // "full" for PG.3; DECISION-NEEDED for the 2D four
  "complexity_cost": { "tier1": 0.0, "tier2": 0.0 },  // measure at implementation time
  "visual_density": 0.6, "motion_intensity": 0.6,
  "color_temperature_range": [0.2, 0.9],
  "fatigue_risk": "medium",
  "transition_affordances": ["crossfade", "cut"],
  "section_suitability": ["ambient", "buildup", "peak", "bridge"]
}
```

Notes:
- **Provenance = Phosphene-native.** These are original designs, not ports, so **no `inspired_by` block** and the substantial-similarity discipline (D-116/D-121) does not apply. They contribute to the Phosphene-native side of the catalog (D-119 brand identity keeps a distinctive native minority; psychedelic geometry is squarely in that wheelhouse). If Matt would rather frame any of them as `milkdrop_inspired` (e.g. Droste ↔ EvilJim "Travelling backwards in a Tunnel of Light"), that flips `family`, adds `inspired_by`, and imposes the D-116/D-121 side-by-side divergence check — flagged per-preset where relevant.
- **`concept_tags` / `motion_paradigm` (D-120).** Included on every sidecar so the orchestrator's concept-repeat and paradigm-repeat diversity scheduling works. Confirm the field is still live in the sidecar schema at implementation time (the taxonomy has moved between docs); if the schema has dropped it, omit and note it.
- **`family`.** All four 2D presets can use `family: "geometric"`; Mandelbox Cathedral fits `geometric` too (or `fractal` if the catalog prefers). The `concept_tags` carry the finer distinction.

---

## 5. Reference discipline for abstract geometry

Phosphene's reference rule (D-064/D-065) assumes photographable subjects; these geometries are largely abstract, which is the wrinkle you flagged. The approach across this set (per your choice): **a per-preset shopping list of real-world photographic references where they genuinely exist, plus cited published shader/art references as porting anchors, plus an anti-reference.**

- **Real photography exists for more of this than it seems:** actual kaleidoscope photographs (PG.1), Islamic/Moorish geometric tilework and rose windows (PG.1/PG.5), moiré in overlaid mesh/silk (PG.4), light-tunnel and infinity-mirror installations (PG.2), gothic fan-vaulting and fractal-like natural forms (PG.3). These anchor palette, contrast, and "does it read as a real thing."
- **Published shader/fractal references are the fidelity anchor** and, per FA #73, the thing to *port* rather than re-derive. Each doc cites specific targets (Inigo Quilez articles, Syntopia/Knighty Mandelbox writeups, canonical Shadertoy kaleidoscope/KIFS/Truchet/hyperbolic examples, M.C. Escher's *Circle Limit* plates). Claude Code reads them before writing.
- **Anti-reference (`05_anti_*`).** Each doc names the failure mode to avoid (e.g. "flat clipart symmetry with no depth," "neon screensaver strobe," "muddy over-blended feedback smear"). AI-generated imagery is permitted **only** in the anti-reference slot (D-065).
- **Curation is a pre-flight gate.** Every session prompt's pre-flight requires `docs/VISUAL_REFERENCES/<preset>/` populated per the doc's shopping list with a written `README.md` (mandatory-traits + anti-references) before Task 1. If not curated, the session curates first (Matt-owned) or stops.

---

## 6. Cross-cutting decisions for Matt

These apply to the whole set; per-preset docs carry their own additional DECISION-NEEDED blocks.

1. **Phase ID + engineering-plan rows.** This set is proposed as **Phase PG** (Psychedelic Geometry), increments PG.1–PG.5 (each preset may span sub-increments PG.N.1 scaffold → PG.N.k cert). `ENGINEERING_PLAN.md` must gain the phase and one row per increment before the first session runs (mandatory per `CLAUDE.md` Increment Completion Protocol). *Recommendation:* adopt "PG" unless you want them folded into an existing phase. *Default if silent:* proceed as Phase PG.
2. **Rubric profile for the four 2D presets.** `lightweight` (detail-cascade/material-count waived, like Plasma/Nebula/SpectralCartograph) vs `full`. *Recommendation:* `lightweight` for PG.1/PG.2/PG.4/PG.5, `full` for PG.3 — but hold every one to the multi-octave / non-pale / nested-detail bar regardless. *Default if silent:* lightweight for the four, full for PG.3.
3. **Build order.** ⚠ **PG.4 Truchet Loom was built first and RETIRED at first live M7 (D-194)** — the "lowest-risk, well-trodden 2D prior art" framing produced a mechanically-clean but craft-thin result Matt rejected ("not psychedelic geometry"), the second PG preset to die this way after Kinetic Sculpture. **Re-examine the phase's "simple 2D mechanic proves a routing strategy" premise before building the remaining four** — Matt's bar is complex/meticulous craft, not cheap-and-deliverable ([[feedback_craft_bar_depth_not_cheap]]). Remaining (unbuilt): PG.1 Mandala, PG.2 Droste, PG.5 Poincaré, PG.3 Mandelbox.
4. **Provenance framing (per preset).** Keep all five Phosphene-native (recommended), or reframe Droste (and/or Mandala) as `milkdrop_inspired`. *Default if silent:* all Phosphene-native.
5. **Names.** Working names throughout; the catalog favours evocative single-concept names (Arachne, Nimbus, Skein). Rename freely at sign-off.

---

## 7. What each per-preset doc contains

Each `PG_N_*.md` is one file with two parts:

- **Part A — Design** (the committed design record): concept + identity; the three concept gates; visual target & the four-scale nested detail cascade; motion & 30-second temporal contract; the audio-routing table with the one-primitive-per-layer self-check; silence state; palette; reference-sourcing shopping list; performance/tier notes; JSON sidecar sketch; and the fidelity-uplift arc (what v1 delivers vs later increments).
- **Part B — Session prompt** (runnable, 10-section per the `session-prompt-author` structure): header + objective; skill invocations; read-first list; pre-flight invariants (incl. the reference gate); numbered tasks with done-when; do-NOT; verification commands; commit templates; closeout format; DECISION-NEEDED block.

Part B's first session is scoped to a **reviewable v1**: macro geometry + core canvas-transforming motion + the hero audio coupling + silence state + palette — enough for an M7 look. Fidelity uplifts (materials, micro-detail, secondary routing, atmosphere) are listed in Part A and become follow-up increments, per the coarse-to-fine order in `SHADER_CRAFT.md §2.2`.
