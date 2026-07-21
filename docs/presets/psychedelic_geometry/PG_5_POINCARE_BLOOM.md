# PG.5 — Poincaré Bloom

**One combined doc: Part A is the committed design; Part B is the runnable Claude Code session prompt.** Read `PG_0_OVERVIEW.md §3 (audio contract)` and `§4 (JSON conventions)` alongside this. Working name — rename freely.

> **Fiddliest 2D math in the phase.** The hyperbolic tiling + Möbius flow must be *ported from a published reference* (FA #73) and carries a boundary-stability guard. Build it after Truchet/Mandala have proven the phase's scaffolding (see `PG_0 §6`).

---
---

# PART A — DESIGN

## A0. Identity

- **Name (working):** Poincaré Bloom
- **Family:** `geometric` · **concept_tags:** `["hypnotic","geometric","mosaic"]` · **motion_paradigm:** `direct_time_modulation` (`mosaic`/`hyperbolic` chosen over `kaleidoscope` so the orchestrator's concept-repeat scheduling can tell this apart from PG.1 Mandala Engine)
- **Passes:** `["direct"]` (crisp curved-space tiling; Möbius flow *is* the motion — no feedback)
- **One-line pitch:** A hyperbolic Circle-Limit tiling — shapes nesting and shrinking infinitely toward a boundary circle — that the four separated stems slide, spin, ripple, and tint through itself, so you literally see the band pulled apart across curved space.

## A1. Concept-viability gate (`SHADER_CRAFT.md §2.0`)

**Gate 1 — Musical role (the sentence):**
> *Each separated stem drives a different motion of curved space — the bass slides the whole hyperbolic tiling along a geodesic, the vocal melody spins it about the center, a drum hit ripples a wave from the center out to the boundary, and the 'other' stem tints the tiles — so the listener sees the band pulled apart, each instrument visibly moving its own aspect of the infinitely nested tiling.*

Four specific features (the four stems, with vocal *pitch* specifically) each paired with a specific behaviour (geodesic slide / spin / radial ripple / tint). It passes, and it is the phase's **stem-separated spatial routing** strategy — Phosphene's stem-separation superpower put directly on screen, a music-response idea none of the other four use.

**Gate 2 — Iconic subject deliverable at fidelity:** Reachable. Hyperbolic {p,q} tiling in the Poincaré disk is a solved register — M.C. Escher's *Circle Limit* series is the cultural touchstone, and there are published mathematical treatments (Coxeter) and canonical shader implementations (Vladimir Bulatov, Roice Nelson, multiple Shadertoy examples). It renders as crisp 2D vector art (like Truchet Loom), so photoreal fidelity risk is low. The *math* risk (getting the {p,q} reflection fold and Möbius flow stable) is the real risk — mitigated by porting a reference and a boundary guard, not deriving.

**Gate 3 — Infrastructure-feasible:** Yes. Pure `direct` fragment reading `FeatureVector` + `StemFeatures` (buffer 3). A small slot-6 state buffer holds the accumulated Möbius transform (translation + rotation) and the drum-ripple envelope, integrated CPU-side from the per-stem deltas with a bounded/renormalized guard so the flow never blows past the boundary. No new passes or contract.

## A2. Visual target & the four-scale nested detail cascade

The "shapes inside shapes, shrinking forever" is *intrinsic to hyperbolic space*: in the Poincaré disk, congruent tiles appear to shrink without limit toward the boundary circle — infinite nesting by construction.

1. **Macro.** The bounding **Poincaré disk** with a dominant {p,q} symmetry (e.g. {6,4}, {4,6}, or {3,7}, seeded per track) — a hyperbolic rosette that reads across the room.
2. **Meso.** The **primary tiles near the center** — largest and clearest, where the motif is most legible.
3. **Micro (the nesting).** The **infinitely shrinking tiles toward the boundary** — the same motif at ever-smaller scale packing toward |z| = 1. This is the hyperbolic "shapes inside shapes," and it is free from the geometry.
4. **Breakup.** Edge glow, **chromatic fringe intensifying toward the boundary** (sells the "infinite edge"), per-tile hue, subtle grain. Anti-aliasing toward the boundary matters — the tiles get sub-pixel, so a coverage-based AA + a boundary fade prevents shimmer.

**Mechanic (author's guide — PORT, don't derive; FA #73):** work in the complex plane on the unit disk. Fold an input point into the fundamental domain of a {p,q} triangle group by **repeated inversions across the tiling's mirror circles** (or via the standard hyperbolic reflection-group fold), then draw the motif in the fundamental domain. Apply **Möbius transformations** to the input point before folding to animate the tiling: hyperbolic *translation* (slide along a geodesic — a Möbius map of the disk to itself) and *rotation* (about the center). Port a canonical Poincaré-disk hyperbolic-tiling reference (Bulatov / Nelson / Shadertoy). **Boundary guard:** clamp/renormalize points as |z| → 1 and cap iteration count so the fold terminates; the accumulated Möbius transform is kept bounded (non-cumulative drift — re-anchor toward identity slowly) so a long session never sends the tiling off to the boundary and freezes.

## A3. Motion & 30-second temporal contract

The canvas is transformed by **Möbius flow driven per-stem** — the defining move of this preset. No feedback (curved detail must stay crisp).

- **Bass slides the space (hero channel 1).** `stems.bass_energy_dev` drives a hyperbolic *translation* — the whole tiling slides along a geodesic, tiles flowing out of the boundary on one side and into it on the other. The bass is the *drift of the universe*.
- **Vocals spin the space (hero channel 2).** `stems.vocals_pitch_hz` (gated) drives *rotation* about the center — the melody turns the rosette. Fallback to `stems.vocals_energy_dev` when pitch confidence is low.
- **Drums ripple the space (hero channel 3).** Each `stems.drums_energy_dev` onset launches a **radial wave from center to boundary** — a hyperbolic ripple that briefly swells the tiles it passes, decaying as it reaches the edge. Bounded footprint, steady global luminance (D-157).
- **'Other' tints the space (hero channel 4).** `stems.other_energy_dev` shifts the per-tile hue/tint — the harmonic bed colours the tiling.
- **Over 30 s:** the listener watches the *arrangement decomposed spatially* — bassline as drift, melody as spin, drums as ripples, pads as colour. When the mix is busy, all four channels move independently and the curved space *seethes*; when it's sparse, it drifts quietly. This is the "you can see the stems" preset.

## A4. Audio-routing table (one primitive per layer — FA #67, clean by construction)

| Visual layer | Primitive | Timescale | Role |
|---|---|---|---|
| **Möbius translation (geodesic slide)** | `stems.bass_energy_dev` | continuous | **HERO** — bass drifts the space |
| **Möbius rotation (spin)** | `stems.vocals_pitch_hz` (gate `conf ≥ 0.6`; **fallback** `stems.vocals_energy_dev`) | melodic | **HERO** — vocals spin the space |
| **Radial ripple (center→boundary)** | `stems.drums_energy_dev` | per-onset (bounded, decaying wave) | **HERO** — drums ripple the space |
| **Per-tile hue / tint** | `stems.other_energy_dev` | continuous | **HERO** — 'other' colours the space |
| **Global palette base / warmth** | `f.valence` | slow (non-stem) | colour baseline, not motion |

**Self-check — this is the cleanest table in the phase.** Each of the four stems is an *independent primitive* driving exactly one channel; separation is the entire design goal (the opposite of "fighting itself"). The only shared-timescale risk (bass slide vs other tint, both continuous) is fine because they drive *different visual channels* (motion vs colour) from *different primitives*. Valence is the sole non-stem, slow, colour-only.

**Liveness & warmup:** stems are unavailable for the first ~10 s of a track; apply the `smoothstep(0.02, 0.06, totalStemEnergy)` crossfade (D-019) from a `FeatureVector` proxy set (translation ← `f.bass_dev`, rotation ← time drift, ripple ← `f.beatComposite`, tint ← `f.mid_att_rel`) to true stems as they converge. **Gate `vocals_pitch_hz` at confidence ≥ 0.6** with the `vocals_energy_dev` fallback. Note mid/treble-adjacent stem devs carry smaller amplitude — use a larger gain on the `other` tint.

## A5. Silence state (D-037)

At `totalStemEnergy == 0`: a **slow Möbius drift** of a dim hyperbolic tiling (the accumulated transform eases toward a gentle idle rotation), calm cool palette, chromatic fringe faint at the boundary, non-black. No ripples. "A quiet curved universe turning slowly."

## A6. Palette

Jewel per-tile palette with a two- or three-tile-colour scheme (fundamental-domain sub-regions get different hues so the tiling reads as a coloured rosette, not monochrome), `other_energy_dev` tint on top, valence warm/cool baseline, chromatic fringe toward the boundary. Pale-tone ≤ 30 %.

## A7. Reference sourcing (curate before Part B runs — Matt-owned)

Populate `docs/VISUAL_REFERENCES/poincare_bloom/` and write its `README.md`. Shopping list:

- `01_macro_hyperbolic_diagram.png` — a **public-domain Poincaré-disk {p,q} tiling diagram** (math figure) — the ground-truth geometry (tiles shrinking to the boundary).
- `02_meso_islamic_dome.jpg` — **real photo** of an Islamic muqarnas dome / star-tiling that *approximates* a hyperbolic rosette (the nested-symmetry read, jewel palette).
- `03_micro_kaleidoscope_edge.jpg` — **real photo** of a kaleidoscope or curved mirror tiling showing motifs shrinking toward an edge.
- `04_palette_rose_window.jpg` — **real photo** of a rose window / stained glass for the jewel palette + emissive tile character.
- **Concept + porting references (READ AND PORT — FA #73):** M.C. Escher's *Circle Limit I–IV* as the **named concept touchstone** (cite by name; do **not** ship or reproduce the copyrighted plates — reference only); Coxeter's writing on the Circle Limit geometry; **Vladimir Bulatov** and **Roice Nelson** hyperbolic-tiling/Möbius references; a canonical Poincaré-disk hyperbolic-tiling Shadertoy (cite the ID in the shader header). These define the {p,q} fold + Möbius maps — do not derive them.
- `05_anti_flat_euclidean_AIGEN.jpg` (`_AIGEN` only here) — the failure mode: a *flat Euclidean* tiling where tiles are the same size everywhere (no boundary-nesting → not hyperbolic); also anti: a Möbius flow where tiles blow up / freeze at the boundary (the stability-guard failure).

## A8. Performance & tier

2D `direct` fragment; the per-pixel cost is the fundamental-domain fold (a handful of circle inversions) + Möbius map — modest. Cap the fold iteration count for a flat cost and a stable boundary. Cheap on both tiers. Rubric: **lightweight recommended** (DECISION-NEEDED). Reduced-motion: the Möbius flow slows to the idle drift; the static tiling still reads.

## A9. Fidelity-uplift arc

- **PG.5.1 (Part B, this session) — reviewable v1:** {p,q} Poincaré tiling + all four stem channels (translation/rotation/ripple/tint) + D-019 warmup + silence + palette + boundary guard. The stem-separated hero is fully alive — this preset's concept *is* the four-channel routing, so it ships in v1.
- **PG.5.2 — boundary + polish:** boundary AA + chromatic-fringe polish, deeper motif detail in the fundamental domain, per-tile-colour scheme refinement.
- **PG.5.3 — options:** {p,q} selection per track (seeded), an optional geodesic-grid overlay, and hardening the long-session Möbius stability guard.

## A10. JSON sidecar sketch

```jsonc
{
  "name": "Poincaré Bloom", "family": "geometric",
  "concept_tags": ["hypnotic","geometric","mosaic"], "motion_paradigm": "direct_time_modulation",
  "passes": ["direct"], "duration": 30,
  "stem_affinity": { "bass": "mobius_translation", "vocals": "mobius_rotation", "drums": "radial_ripple", "other": "tile_tint" },
  "certified": false, "rubric_profile": "lightweight",
  "complexity_cost": { "tier1": 0.0, "tier2": 0.0 },
  "visual_density": 0.75, "motion_intensity": 0.6,
  "color_temperature_range": [0.15, 0.9], "fatigue_risk": "medium",
  "transition_affordances": ["crossfade","cut"],
  "section_suitability": ["ambient","buildup","peak","bridge","comedown"]
}
```

---
---

# PART B — SESSION PROMPT (PG.5.1)

## Increment PG.5.1 — Poincaré Bloom scaffold + per-stem Möbius routing (preset increment)

**Objective:** After this session, Phosphene has a new `direct` preset "Poincaré Bloom" that renders a stable hyperbolic {p,q} Poincaré-disk tiling (tiles nesting toward the boundary); the four separated stems each drive one channel — bass → Möbius geodesic translation, vocals(pitch, gated) → Möbius rotation, drums → a decaying radial ripple, other → per-tile tint — with the D-019 FeatureVector-proxy warmup; a slow-drifting dim tiling renders at silence; the Möbius flow is boundary-stable over a long run. Registered, compiling, loading, golden-hashed, perf-profiled. `certified` stays `false`. This is the reviewable v1 of the PG.5 arc in `PG_5_POINCARE_BLOOM.md §A9`.

## 1. Skills to invoke (in order)
- **`preset-session`** — before any `.metal` / sidecar edit. Study the audio hierarchy §Layer 5 (stems) and the D-019 stem-warmup crossfade.
- **`shader-authoring`** — before any GPU code. **FA #73 is central:** port the published Poincaré-disk tiling + Möbius maps; do not derive.
- **`closeout`** — at the end.

## 2. Read-first (exact, ordered)
1. `PG_5_POINCARE_BLOOM.md` (this doc — Part A is the design of record; §A2 mechanic + §A7 porting refs are mandatory).
2. `docs/VISUAL_REFERENCES/poincare_bloom/README.md` and every image; the cited hyperbolic-tiling porting references (Bulatov/Nelson + the Shadertoy DE).
3. `docs/ARCHITECTURE.md §GPU Contract Details` — the direct-pass fragment binding (`buffer(0)=FeatureVector`, `buffer(3)=StemFeatures`) and the `StemFeatures` layout (per-stem `*_energy_dev`, `vocals_pitch_hz`/`vocals_pitch_confidence`).
4. `docs/SHADER_CRAFT.md §14` (esp. §14.1 signal liveness) and `§3` (grain octave floor).
5. `PhospheneEngine/Sources/Presets/Shaders/Plasma.metal` / `Nebula.metal` — reference `direct`-pass fragment presets.
6. `PhospheneEngine/Sources/Presets/Shaders/Murmuration.metal` + `Tests/Presets/MurmurationStemRoutingTests` — the reference for *per-stem routing* + the `smoothstep(0.02,0.06,totalStemEnergy)` warmup pattern (D-019).
7. `PhospheneEngine/Sources/Presets/Nimbus/NimbusState.swift` (or `Skein`) — reference slot-6 CPU-accumulator state (for the bounded Möbius transform + ripple envelope, with a long-accumulator/renormalize guard).

## 3. Pre-flight invariants (a failed check stops the session)
- `git status` clean on `main`; `swift test --package-path PhospheneEngine` green.
- `docs/VISUAL_REFERENCES/poincare_bloom/` populated per `§A7` + `README.md` written (and the Escher plates are *referenced by name only*, not shipped). **If not, curate first (Matt-owned) or stop.**
- `docs/ENGINEERING_PLAN.md` has a Phase PG / PG.5.1 row.
- A fixture with **separable stems** (clear drums/bass/vocals/other) is available for the per-stem routing test; and a fixture to exercise the pre-10 s FeatureVector-proxy warmup.
- Confirm the production preset count for `PresetLoaderCompileFailureTest` to bump by exactly 1.

## 4. Tasks (each has a done-when)
1. **Plan + scaffold.** Add the PG.5.1 row to `ENGINEERING_PLAN.md`. Create `Shaders/PoincareBloom.metal` + `PoincareBloom.json` (sidecar per `§A10`) + register + bump `expectedProductionPresetCount`. **Done-when:** app + engine build; `PresetLoaderCompileFailureTest` passes at the new count; preset loads.
2. **Static hyperbolic tiling (scene fragment).** Port the {p,q} Poincaré-disk fundamental-domain fold (repeated circle inversions, capped iterations) + motif + boundary vignette + jewel palette. No Möbius yet, no audio. **Done-when:** a `RENDER_VISUAL=1` contact sheet shows a crisp hyperbolic rosette with tiles visibly shrinking toward the boundary circle (not a flat Euclidean tiling), non-black, no boundary shimmer.
3. **Möbius flow + boundary guard (slot-6 state).** Add `PoincareBloomState` (slot-6, byte-matched MSL mirror) holding the accumulated Möbius transform (translation + rotation) and the ripple envelope. Integrate transform deltas CPU-side; **renormalize / re-anchor toward identity slowly** so a long run stays bounded. Apply the transform to the input point before the fold. **Done-when:** a multi-frame test driving the live direct-pass path shows the tiling sliding + spinning smoothly and a soak-style long run (≥ a few thousand frames) keeps |transform| bounded (assert a bound; no boundary blow-up/freeze).
4. **Per-stem routing — the four channels (hero).** Wire `§A4`: `bass_energy_dev` → translation, `vocals_pitch_hz` (gate ≥ 0.6, fallback `vocals_energy_dev`) → rotation, `drums_energy_dev` → a decaying radial ripple (center→boundary), `other_energy_dev` → per-tile tint. Apply the D-019 FeatureVector-proxy warmup crossfade. **Done-when:** a multi-frame test on the separable-stems fixture shows each channel responding to its stem independently (e.g. isolate frames where only bass energy is high → translation moves, rotation/ripple/tint ~static); the warmup path routes sensibly in the first 10 s.
5. **Silence state.** Verify `§A5`: slow idle drift, dim, non-black, no ripples. **Done-when:** the silence contact sheet is non-black and shows a slowly-drifting tiling; a `totalStemEnergy == 0` assertion confirms no ripple fires.
6. **Audio routing review.** Deviation/stem primitives + gated pitch only; one primitive per channel; liveness + warmup note in the shader header. **Done-when:** `grep` finds no absolute-threshold pattern; routing matches `§A4`; the D-019 warmup is present.
7. **Performance.** `PresetPerformanceTests` on silence/steady/beat-heavy; record p50/p95/p99; confirm the fold-iteration cap keeps cost flat. **Done-when:** p95 ≤ Tier-2 budget; recorded.
8. **Golden hash — STOP AND REPORT.** Register the golden 3-tuple; do NOT touch other goldens. Produce the M7 contact sheet (include a beat-heavy frame showing a ripple). **Done-when:** new golden passes; then **stop and report** with the contact sheet.
9. **Closeout.** Invoke `closeout`; 8-part report with the verbatim evidence block, the direct-pass dispatch-path statement, the **per-stem firing evidence** (per-channel response isolated on the separable-stems fixture), the boundary-stability bound, and perf numbers.

## 5. Do-NOT
- **Do not first-principles the hyperbolic fold or Möbius maps** (FA #73) — port the cited reference; the math is exact and published.
- **No absolute thresholds** (D-026 / FA #31); **gate `vocals_pitch_hz` at confidence ≥ 0.6** with the `vocals_energy_dev` fallback.
- **No feedback / `mv_warp`** — crisp `direct` only (D-029; feedback would smear the sub-pixel boundary tiles).
- **Do not let the Möbius transform accumulate unbounded** — the re-anchor/renormalize guard is mandatory (the anti-reference is tiles freezing at the boundary).
- **Do not ship or reproduce Escher's copyrighted plates** — reference by name only; the shipped tiling is Phosphene-authored from the {p,q} math.
- Do not route two channels to the same primitive/timescale (FA #67) — the per-stem table is clean by construction (each stem is its own primitive); keep it that way and don't collapse two stems onto one channel.
- Do not flip `certified`; do not regenerate other goldens; do not commit out-of-scope files.
- Do not build the deeper boundary AA / {p,q}-per-track selection here — those are PG.5.2/PG.5.3.

## 6. Verification commands
```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
swift test --package-path PhospheneEngine --filter "PresetLoaderCompileFailureTest|PoincareBloom|PresetRegressionTests"
RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview 2>&1
```

## 7. Commit message templates (small commits; local `main`; push only on Matt's "yes, push")
- `[PG.5.1] Presets: scaffold Poincaré Bloom (direct) + JSON sidecar + registration`
- `[PG.5.1] Poincaré Bloom: port {p,q} Poincaré-disk fundamental-domain fold (ref <Bulatov/shadertoy>)`
- `[PG.5.1] Poincaré Bloom: slot-6 Möbius state + flow + bounded renormalize guard`
- `[PG.5.1] Poincaré Bloom: per-stem routing (bass slide / vocals spin / drums ripple / other tint) + D-019 warmup`
- `[PG.5.1] Poincaré Bloom: silence + golden hash + perf + ENGINEERING_PLAN row`

## 8. Closeout format
Invoke `closeout`; 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions: (a) the direct-pass dispatch path the multi-frame tests exercised; (b) **per-stem firing evidence** — isolate each channel's response on the separable-stems fixture (this is the load-bearing "the stems are visible" claim; cite `stems.csv` columns per the evidence-based-closeout rule); (c) the boundary-stability bound over the long run; (d) perf p50/p95/p99; (e) the M7 contact-sheet path (with a ripple frame); (f) ENGINEERING_PLAN PG.5.1 status.

## 9. DECISION-NEEDED (surface to Matt at review, product-level)
- **Which curved symmetry?** *Options:* **{6,4} / {4,6}** (six- or four-fold, calmer, more legible — recommended) vs **{3,7}** (denser, more "Escher," busier toward the boundary). *Recommendation:* prototype {6,4} and {3,7}, show a frame of each, pick at review. *Default if silent:* {6,4}.
- **How strong is the per-stem separation?** *Options:* **Overt** — each instrument's motion is large and obviously independent (you can name what each stem is doing, recommended for the concept) vs **Woven** — subtler, the channels blend into one flowing field. *Recommendation:* Overt for v1 (the concept is "you can see the stems"); soften later if it reads as chaotic. *Default if silent:* Overt.
- **Rubric profile:** `lightweight` (recommended) vs `full`. *Default:* lightweight.
