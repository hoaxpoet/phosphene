# PG.1 — Mandala Engine

**One combined doc: Part A is the committed design; Part B is the runnable Claude Code session prompt.** Read `PG_0_OVERVIEW.md §3 (audio contract)` and `§4 (JSON conventions)` alongside this. Working name — rename freely.

---
---

# PART A — DESIGN

## A0. Identity

- **Name (working):** Mandala Engine
- **Family:** `geometric` · **concept_tags:** `["kaleidoscope","hypnotic","geometric"]` · **motion_paradigm:** `mv_warp`
- **Passes:** `["mv_warp"]` (direct-fragment kaleidoscope scene + per-vertex feedback warp)
- **One-line pitch:** A living radial mandala — concentric rings of self-similar motifs built by recursive mirror-folding — that breathes with the bass and gains a new ring on every downbeat.

## A1. Concept-viability gate (`SHADER_CRAFT.md §2.0`)

**Gate 1 — Musical role (the sentence):**
> *The mandala's radial breath swells and recedes with the sustained bass envelope, and on each downbeat a fresh concentric ring of self-similar motifs blooms outward from the hub and settles into the figure — so the listener pairs the sustained low end with the whole mandala breathing, and the bar boundary with the mandala visibly growing a ring.*

That is two specific features (sustained bass envelope; the downbeat/bar boundary) each paired with a specific, nameable visual behaviour (radial breathing; a ring blooming). It passes.

**Gate 2 — Iconic subject deliverable at fidelity:** Yes. The radial-mandala/kaleidoscope register is (a) demonstrably reachable — Lumen Mosaic already ships a certified vivid backlit pattern-glass panel (proving Phosphene can hold crisp saturated symmetric geometry at fidelity), and (b) a *solved* register in shader literature (polar mirror-fold kaleidoscopes are a canonical Shadertoy form). Fidelity risk is low; this is a good first preset in the phase. We build within the achievable bar: crisp vector-clean symmetry + jewel palette + feedback depth, not photoreal materials.

**Gate 3 — Infrastructure-feasible:** Yes. `mv_warp` is a shipped pass with two production references (Volumetric Lithograph, Gossamer). The per-preset state buffer for bloom rings uses the existing slot-6 mechanism (`setDirectPresetFragmentBuffer`, as NimbusState/GossamerState do). No new passes, no new contract.

## A2. Visual target & the four-scale nested detail cascade

The "shapes inside shapes / smaller shapes making a larger shape" is delivered by a **two-to-three level recursive kaleidoscopic fold**, so nesting is structural, not decorative:

1. **Macro (the whole thing).** A centered mandala disk with a dominant **N-fold rotational symmetry** (N ∈ {6, 8, 12}, seeded per track). Clear hub, radial composition, vignette dissolving to deep indigo (never black) at the frame edge. This is what reads across the room.
2. **Meso (concentric rings, ~0.15–0.35 disk-radius scale).** The disk is banded into **concentric rings**; each ring carries an M-fold motif band (a repeated petal/arc/lens motif around the ring). Adjacent rings are rotationally offset and hue-shifted so the eye reads distinct nested bands.
3. **Micro (the recursion — sub-motifs, ~0.03–0.08 scale).** *This is the load-bearing "shapes inside shapes."* Inside each petal of a ring, a **second mirror-fold** draws a smaller copy of a sub-motif — a petal made of petals. One more fold level where budget allows (a petal of petals of petals). The self-similarity across the three levels is the psychedelic-geometry payload.
4. **Specular / breakup (sub-pixel).** Fine emissive line-work on motif edges, a soft bloom halo, mild **radial chromatic aberration** that grows toward the rim, and low-amplitude grain so the flat vector look gains life. Per-ring palette variation prevents the "uniform saturation = cartoon" failure (FA #45).

Even though this is a 2D preset, the cascade rule holds: multiple distinct spatial frequencies layered, ≥ 4 octaves of variation present (the fold recursion + a low-amplitude `fbm`/`worley` texture wash on the motif interiors supplies the octaves).

**Mechanic (for the author, not a spec to copy verbatim):** work in polar `(r, θ)`. Fold θ into an N-wedge with a mirror (`mod_mirror`-style), producing N-fold symmetry. Quantize `r` into rings (`ring = floor(r * kRings)`; per-ring rotation offset and hue from `ring`). Within a wedge, apply a second mirror fold to draw the petal, and a third scaled fold for the sub-motif. Compose motif SDFs (vesica/lens, arc, dot) with `op_blend`/`op_smooth_union`. Keep rings **linear/quantized** (a flat mandala) — the *log-radial self-similar* variant is deliberately reserved for PG.2 Droste so the two presets don't converge.

## A3. Motion & 30-second temporal contract

The canvas is transformed by **feedback breathing + slow rotation accumulating in the `mv_warp` texture**, punctuated by **downbeat ring blooms**.

- **Continuous (every frame):** `mvWarpPerVertex` applies a gentle radial **zoom breath** (in/out) and a slow global **rotation**. Because motion accumulates in the feedback texture across frames, a 4–6 % zoom on the bass envelope reads as *breathing*, and the slow rotation sums into a soft spiral of echoes. Decay is moderate (~0.88–0.92) — enough trail for depth, not so much it smears to mush (the failure mode; see anti-reference).
- **Per bar (structural):** on each `bar_phase01` wrap, a **bloom ring** is born at the hub and expands to a target radius over ~0.6 s, bright at birth and settling into the standing ring set as it ages. Footprint is bounded to that one ring; global luminance stays steady (D-157) — the mandala *grows*, it does not strobe.
- **Over 30 s:** the palette phase drifts slowly (centroid-driven), rings accrue and recede with the music's structure, and the whole figure breathes with the low end. A listener watching for 30 s sees a mandala that is clearly *listening* — inhaling on the bass, adding a ring on each downbeat.

## A4. Audio-routing table (one primitive per layer — FA #67)

| Visual layer | Primitive | Timescale | Role |
|---|---|---|---|
| **Radial breath (zoom)** | `f.bass_att_rel` (recentred) | continuous / slow | **HERO** — the mandala inhales/exhales with the low end |
| **Global rotation** | `f.arousal` (rate) + `accumulated_audio_time` baseline | very slow | drift; energy adds spin |
| **Downbeat ring bloom** | `f.bar_phase01` wrap (cached BeatGrid) | per-bar / structural | **HERO #2** — a ring is born on the downbeat |
| **Palette phase / hue** | `f.spectral_centroid` | slow | colour temperature, not motion |
| **Motif interior detail intensity** | `f.spectral_flux` | texture | fine surface life (secondary, optional in v1) |

**Self-check:** five layers, five different *audio* primitives at five different timescales. No layer shares a primitive or timescale with another → no "fighting itself." Breath is on the *smoothed* bass envelope (slow), bloom is on the *bar phase* (structural) — deliberately different bass-adjacent signals at different timescales, which is allowed because they are different primitives on different clocks. (`accumulated_audio_time` on the rotation layer is a non-reactive wall-clock providing baseline drift, not a second audio driver — that layer's one audio primitive is `arousal`.)

**Liveness:** `bass_att_rel` and `spectral_flux` are reliably alive; `arousal` is slow but alive; `bar_phase01` is alive when a grid is installed. **Cold-start:** suppress the bloom for the first ~3 s of a track (time-since-track-start envelope, matching the grid-phase cold-start window) so a wrong-phase grid doesn't fire a discrete, visible bloom on the wrong beat; the breath and rotation run from frame 1.

**Symmetry order N** is fixed per track (seeded from the track hash), *not* audio-driven — discrete N changes mid-track are jarring. A section-boundary N-morph (crossfaded) is a possible later coupling; flagged in A9 and the DECISION-NEEDED block.

## A5. Silence state (D-037)

At `totalStemEnergy == 0`: a **slowly rotating, dim mandala at rest radius**, palette at a calm cool default (deep teal→indigo jewel tones), a faint breathing from an arousal/idle floor, vignette to deep indigo (not black). No bloom rings spawn at silence. The destination is "a quiet mandala idling," matching the calm-but-alive silence aesthetic the project favours.

## A6. Palette

IQ cosine `palette()` (V.3 Color tree), jewel-toned, with a **per-ring hue offset** so nested bands read as distinct. Centroid drives the palette phase; valence nudges warm/cool. Keep saturation varied (some near-black valleys, some deep jewel, a *minority* of near-white highlights) — pale-tone share ≤ 30 % (FA #45 / §12.7). Mild radial chromatic aberration toward the rim.

## A7. Reference sourcing (curate before Part B runs — Matt-owned)

Populate `docs/VISUAL_REFERENCES/mandala_engine/` per `docs/VISUAL_REFERENCES/_NAMING_CONVENTION.md` and write its `README.md`. Shopping list:

- `01_macro_kaleidoscope.jpg` — **real photograph** of a kaleidoscope view (the genuine article; sets the "nested rings of folded motifs" read and the depth a photo has that clipart lacks).
- `02_meso_rose_window.jpg` — **real photo** of a gothic rose window or an Islamic/Moorish star-tiling panel (concentric symmetric banding; jewel palette).
- `03_micro_sand_mandala.jpg` — **real photo** of a Tibetan sand mandala or Persian miniature medallion (petal-within-petal recursion — the sub-fold nesting).
- `04_palette_stained_glass.jpg` — **real photo** for the jewel-tone palette + emissive-backlit character.
- **Porting references (read before coding, FA #73):** a canonical polar-mirror-fold kaleidoscope Shadertoy (search "kaleidoscope" / "mandala" — pick one with clean N-fold folding and cite its ID in the shader header); Inigo Quilez's articles on domain repetition and 2D SDFs (for the fold + motif SDFs).
- `05_anti_flat_clipart.jpg` (`_AIGEN` allowed here only) — the failure mode: a flat, bilaterally-symmetric logo/clipart mandala with uniform saturation, no depth, no motion, no nesting. Also anti: over-blended feedback smear (mush).

## A8. Performance & tier

2D direct fragment + `mv_warp` 3-pass — cheap (comparable to the existing feedback presets). Target well under the Tier-2 7 ms preset ceiling; no SSGI, no ray march. Reduced-motion path: `mv_warp` accumulator is skipped (single-frame render) per the engine's a11y gate — ensure the scene fragment alone still reads as a static mandala. Rubric profile: **lightweight recommended** (DECISION-NEEDED).

## A9. Fidelity-uplift arc

- **PG.1.1 (Part B, this session) — reviewable v1:** scaffold + 2-level fold macro/meso mandala + breath + rotation + downbeat bloom + silence + palette. Enough for an M7 look.
- **PG.1.2 — nesting + polish:** third fold level (petal-of-petals-of-petals), chromatic aberration + bloom-halo tuning, per-ring palette variation, motif-interior `fbm`/`worley` texture wash for the octave floor.
- **PG.1.3 — optional structural coupling:** section-boundary symmetry-order morph (crossfaded N change), and/or vocal-pitch hue nudge on the outermost ring. Only if it earns its place at M7.

## A10. JSON sidecar sketch

```jsonc
{
  "name": "Mandala Engine", "family": "geometric",
  "concept_tags": ["kaleidoscope","hypnotic","geometric"], "motion_paradigm": "mv_warp",
  "passes": ["mv_warp"], "duration": 30,
  "decay": 0.90, "base_zoom": 0.06, "base_rot": 0.02, "beat_zoom": 0.0, "beat_rot": 0.0,
  "beat_source": "bass",
  "certified": false, "rubric_profile": "lightweight",
  "complexity_cost": { "tier1": 0.0, "tier2": 0.0 },
  "visual_density": 0.65, "motion_intensity": 0.5,
  "color_temperature_range": [0.2, 0.9], "fatigue_risk": "medium",
  "transition_affordances": ["crossfade","cut"],
  "section_suitability": ["ambient","buildup","peak","bridge"]
}
```
(`beat_zoom`/`beat_rot` at 0 because the downbeat event is a geometry bloom in the fragment, not a global warp pulse — keeps `base` ≥ 2–4× any beat term by construction.)

---
---

# PART B — SESSION PROMPT (PG.1.1)

## Increment PG.1.1 — Mandala Engine scaffold + core motion + hero audio (preset increment)

**Objective:** After this session, Phosphene has a new `mv_warp` preset "Mandala Engine" that renders a centered, N-fold, two-level recursively-folded mandala; breathes radially with the bass envelope and rotates slowly; blooms a concentric ring on each downbeat via cached-BeatGrid `bar_phase01`; renders a non-black idling mandala at silence; and is registered, compiling, loading, and covered by a multi-frame harness test. `certified` stays `false`. This is the reviewable v1 of the PG.1 arc in `PG_1_MANDALA_ENGINE.md §A9`.

## 1. Skills to invoke (in order)
- **`preset-session`** — before opening any `.metal` file or JSON sidecar (mandatory opener).
- **`shader-authoring`** — before writing any MSL / GPU-facing Swift.
- **`closeout`** — at the end, to produce the 8-part report.

## 2. Read-first (exact, ordered)
1. `PG_1_MANDALA_ENGINE.md` (this doc — Part A is the design of record).
2. `docs/VISUAL_REFERENCES/mandala_engine/README.md` and every image in that folder.
3. `docs/ARCHITECTURE.md §GPU Contract Details` (buffer/texture slots; the corrected fragment binding) and `§Presets` (the `mv_warp` three-pass description).
4. `docs/SHADER_CRAFT.md §2.2` (coarse-to-fine order), `§3` (noise recipes), `§14` (authoring cheat sheet + §14.1 signal liveness).
5. `PhospheneEngine/Sources/Presets/Shaders/VolumetricLithograph.metal` — the reference `mv_warp` preset (how `mvWarpPerFrame`/`mvWarpPerVertex` are written).
6. `PhospheneEngine/Sources/Presets/Gossamer/GossamerState.swift` and `Nimbus/NimbusState.swift` — reference per-preset slot-6 state buffers (for the bloom-ring state).
7. `PhospheneEngine/Sources/Presets/PresetLoader+WarpPreamble.swift` — the injected `mvWarp_*` fragments and the `mvWarpPerFrame`/`mvWarpPerVertex` forward declarations you must satisfy.

## 3. Pre-flight invariants (a failed check stops the session)
- `git status` clean on `main`; `swift test --package-path PhospheneEngine` green before any change (regression baseline).
- `docs/VISUAL_REFERENCES/mandala_engine/` is populated per `PG_1 §A7` and its `README.md` is written (mandatory-traits + anti-references). **If not, curate first (Matt-owned) or stop and report** — do not author blind (D-064 / FA #40).
- `docs/ENGINEERING_PLAN.md` has a Phase PG section with a PG.1.1 row (add it in this session's docs task if absent — do not proceed to shader work without the plan row).
- Confirm the current production preset count for `PresetLoaderCompileFailureTest` so you can bump it by exactly 1.

## 4. Tasks (each has a done-when)
1. **Plan + scaffold.** Add the Phase PG / PG.1.1 row to `ENGINEERING_PLAN.md`. Create `Shaders/MandalaEngine.metal` + `MandalaEngine.json` (sidecar per `§A10`) and register per the four-section `project.pbxproj` + `PresetLoader` convention. Bump `expectedProductionPresetCount` by 1. **Done-when:** app + engine build; `PresetLoaderCompileFailureTest` passes at the new count; the preset loads.
2. **Macro + meso mandala (scene fragment).** Implement the kaleidoscope scene fragment: polar coordinates → N-fold mirror fold (N seeded per track) → concentric ring quantization → per-wedge petal SDF → **second mirror fold for the sub-motif** (the two-level nesting). Palette per `§A6`. No audio yet; static figure. **Done-when:** a `RENDER_VISUAL=1` contact sheet at silence shows a centered, N-fold, visibly *nested* mandala (rings of motifs, each motif containing a smaller motif), vignetting to non-black.
3. **Feedback motion.** Implement `mvWarpPerFrame`/`mvWarpPerVertex`: radial zoom breath + slow global rotation; set `decay` per sidecar. **Done-when:** a multi-frame harness driven through the live `warp → compose → blit` loop (adapt `AuroraVeilMVWarpAccumulationTest`) shows breathing/rotational accumulation over ≥ 60 frames with **no vertical/tangential smear** at rest (the anti-reference mush).
4. **Downbeat ring bloom (slot-6 state).** Add a `MandalaEngineState` (`@unchecked Sendable` + `NSLock`, byte-matched MSL mirror) holding recent bloom-ring birth `bar` times; bind at fragment slot 6. On `bar_phase01` wrap, spawn a bloom ring; the fragment draws it with an age envelope (expand → settle), bounded to one ring, steady global luminance. Implement the **cold-start suppression** (no bloom in the first ~3 s of a track, matching the grid-phase cold-start window). **Done-when:** a multi-frame test on a fixture *with* a cached BeatGrid shows exactly one ring bloom per bar wrap, footprint bounded to that ring, and total frame luminance not spiking (assert a luminance-stability metric).
5. **Silence state.** Verify `§A5`: non-black idling mandala, no blooms, calm palette. **Done-when:** the silence contact sheet is non-black and shows a slowly-rotating dim mandala; a `totalStemEnergy == 0` unit assertion confirms no bloom spawns.
6. **Audio routing wiring.** Wire the `§A4` table exactly — deviation primitives only, one primitive per layer. Add a one-paragraph liveness note in the shader header citing which primitives drive which layer and why each is alive. **Done-when:** shader review confirms no absolute-threshold pattern (`grep` for `smoothstep(0.NN` on raw `f.bass`/`f.mid` returns nothing on this file); the routing matches `§A4`.
7. **Performance.** Run `PresetPerformanceTests` (or the standard preset perf harness) on silence / steady / beat-heavy fixtures; record p50/p95/p99. **Done-when:** p95 ≤ Tier-2 preset budget; recorded in the closeout.
8. **Golden hash — STOP AND REPORT.** Register the `PresetRegressionTests` golden-hash 3-tuple for Mandala Engine. **Do not regenerate any other preset's golden.** Produce the v1 `RENDER_VISUAL=1` contact sheet for M7. **Done-when:** the new golden entry exists and tests pass; then **stop and report** with the contact sheet before any further tuning.
9. **Closeout.** Invoke `closeout`; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2, the multi-frame dispatch-path statement (which loop the tests exercised), the perf numbers, and the M7 contact-sheet path.

## 5. Do-NOT
- **No absolute thresholds on AGC-normalized energy** (D-026 / FA #31) — deviation primitives only.
- **The downbeat bloom uses `bar_phase01` from the cached BeatGrid, never raw live onsets** (Layer-4 rule; ±80 ms jitter + feedback would make it unusable).
- **Do not stack a second motion paradigm** (D-029) — no particles, no camera, no ray march. `mv_warp` only.
- Do not route two visual layers to the same primitive/timescale (FA #67) — hold `§A4` exactly.
- Do not flip `certified` to `true` (that is Matt's M7 call).
- Do not regenerate other presets' golden hashes; do not commit files outside this increment's scope.
- Do not author the third fold level, chromatic aberration polish, or section-morph here — those are PG.1.2/PG.1.3.

## 6. Verification commands
```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
swift test --package-path PhospheneEngine --filter "PresetLoaderCompileFailureTest|MandalaEngine|PresetRegressionTests"
RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview 2>&1   # contact sheet
```

## 7. Commit message templates (small commits; local `main` only; push only on Matt's "yes, push")
- `[PG.1.1] Presets: scaffold Mandala Engine (mv_warp) + JSON sidecar + registration`
- `[PG.1.1] Mandala Engine: kaleidoscope scene fragment — N-fold + concentric rings + sub-fold nesting`
- `[PG.1.1] Mandala Engine: mvWarpPerFrame/PerVertex breath + rotation (decay 0.90)`
- `[PG.1.1] Mandala Engine: slot-6 bloom-ring state + bar-phase downbeat bloom + cold-start suppression`
- `[PG.1.1] Mandala Engine: golden hash + perf profile + ENGINEERING_PLAN row`

## 8. Closeout format
Invoke the `closeout` skill; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions: (a) which dispatch path the multi-frame tests exercised (`warp → compose → blit`); (b) the bloom firing evidence (rings-per-bar count from the fixture with a grid) and the luminance-stability metric; (c) perf p50/p95/p99; (d) the M7 contact-sheet path; (e) the ENGINEERING_PLAN PG.1.1 row status.

## 9. DECISION-NEEDED (surface to Matt at review, product-level)
- **Trail length (feedback decay).** How much do the breathing echoes linger? *Options:* **Tight (decay ≈ 0.85)** — crisp, almost no ghost, reads as a solid mandala breathing; **Dreamy (decay ≈ 0.93)** — long spiral echoes, more "psychedelic," risk of smear on busy tracks. *Recommendation:* start Tight-to-mid (0.90); it's the safe read. *Default if silent:* 0.90.
- **Symmetry order over a track.** *Options:* **Fixed per track** (seeded; stable, recommended) vs **morphs at section boundaries** (crossfaded N change — more dynamic, more risk). *Recommendation/default:* fixed per track for v1; revisit as PG.1.3.
- **Rubric profile:** `lightweight` (recommended) vs `full`. *Default if silent:* lightweight.
