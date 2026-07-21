# PG.2 — Droste Descent

**One combined doc: Part A is the committed design; Part B is the runnable Claude Code session prompt.** Read `PG_0_OVERVIEW.md §3 (audio contract)` and `§4 (JSON conventions)` alongside this. Working name — rename freely.

---
---

# PART A — DESIGN

## A0. Identity

- **Name (working):** Droste Descent
- **Family:** `geometric` · **concept_tags:** `["fractal","hypnotic","geometric"]` · **motion_paradigm:** `mv_warp`
- **Passes:** `["mv_warp"]` (log-polar tunnel scene fragment + per-vertex feedback warp)
- **One-line pitch:** An infinite self-similar zoom tunnel — the frame literally contains a smaller copy of itself, forever — that pulls you one ring deeper on every beat.

## A1. Concept-viability gate (`SHADER_CRAFT.md §2.0`)

**Gate 1 — Musical role (the sentence):**
> *The tunnel descends one self-similar ring deeper on every beat — the listener rides the beat as forward travel into an infinitely nested well — while the sustained low end sets how wide the throat opens, so a bass drop pulls the walls back and a bass swell closes them in.*

Two specific features (the beat/tempo grid; the sustained bass envelope) each paired with a specific behaviour (one ring of forward descent per beat; the throat widening/closing). It passes.

**Gate 2 — Iconic subject deliverable at fidelity:** Yes. The log-polar/Droste tunnel is a *solved* register — the Escher "Droste effect" has published conformal-mapping mathematics and multiple canonical Shadertoy implementations. Volumetric Lithograph already demonstrates that Phosphene can render crisp receding geometry with feedback accumulation. We build within the bar: crisp self-similar rings + jewel palette + feedback depth, not photoreal volumetrics.

**Gate 3 — Infrastructure-feasible:** Yes. `mv_warp` is shipped; the log-polar zoom *is* a `mvWarpPerVertex` displacement (the feedback loop generates the infinite recursion). Cached-BeatGrid `beat_phase01` is available from `FeatureVector`. A small slot-6 state buffer holds the descent phase accumulator and cold-start/irregular-track fallback flags. No new passes or contract.

## A2. Visual target & the four-scale nested detail cascade

The "shapes inside shapes" here is *literal and infinite*: the feedback loop samples a scaled copy of the previous frame, so each ring visibly contains the next-smaller ring, ad infinitum (Droste self-similarity). Crispness comes from an **analytic log-radial ring pattern** in the fragment; the feedback adds infinite depth and echo.

1. **Macro.** A centered tunnel with a bright **throat/vanishing point**, concentric rings receding into it, a radial vignette, and an overall slow **twist** (log-spiral). What reads across the room: "I am looking down an endless well."
2. **Meso (self-similar rings, log-spaced radii).** Concentric **N-gon (or star) rings** at logarithmically-spaced radii — `fract(log2(r)·k − descentPhase)` gives repeating rings that scroll inward and are self-similar by construction. Each ring is rotationally offset from the last (the twist).
3. **Micro (per-ring ornament + nested motif).** Each ring band carries an ornament — notches/sub-polygons on its edge and a smaller nested ring-motif inside the band — so a ring is itself a little tunnel. This is the recursion made visible at the mid scale, reinforcing the feedback's infinite recursion at the macro scale.
4. **Specular / breakup.** Emissive ring edges, a bloom halo at the throat, **radial chromatic aberration increasing toward the throat**, subtle grain. Per-ring hue drift so the walls read as a moving spectrum, not a monochrome pipe.

**Mechanic (author's guide):** the analytic tunnel lives in log-polar space — map `uv` to `(log(r), θ)`, tile in `log(r)` to get self-similar rings, draw the ring/ornament SDFs, map back. The `mvWarpPerVertex` warp applies a **radial zoom toward center by a fixed scale per frame** (plus the twist), so the feedback texture *is* the infinite recursion; the analytic pattern keeps it crisp and controllable (and beat-lockable). Keep this **log-radial** self-similar form here; the *flat quantized-ring mandala* is deliberately PG.1 Mandala Engine, so the two presets stay distinct.

## A3. Motion & 30-second temporal contract

The canvas is transformed by **forward descent locked to the beat**, plus twist and a bass-driven throat.

- **The beat is forward travel (hero).** The descent phase is driven by cached-grid `beat_phase01`, which ramps 0→1 each beat: this yields **continuous inward motion between beats and a clean per-beat cadence** — one ring passes the mouth per beat. Because it rides the analytic ramp (not a raw onset), it is smooth, not jittery, and a small cold-start phase error reads as a small timing offset, not a wrong-beat lurch (the cold-start contract's "use `beat_phase01` where small errors read as small offsets" case).
- **Throat breathes with the bass (hero #2).** `bass_att_rel` sets ring spacing / throat width — a bass drop widens the throat and pulls the walls back (you fall faster into a bigger mouth); a swell closes them in.
- **Twist** accumulates slowly from a mid-band deviation; **wall hue** cycles from spectral centroid.
- **Over 30 s:** the listener is *riding the track's pulse into the screen* — the tempo is the descent rate, the downbeat feels like a landing, the bass shapes the space. This is the beat-lock strategy the phase is exploring, and it is unmistakably different from PG.1's continuous breathing.

**Irregular-track fallback (D-154).** For beat-irregular tracks (or before a grid installs / reactive mode), the descent falls back to a **continuous `arousal`-driven** rate (no hard per-beat step) — a smooth free-fall rather than a lurching one. This is a *selection*, not a simultaneous second driver on the same layer.

## A4. Audio-routing table (one primitive per layer — FA #67)

| Visual layer | Primitive | Timescale | Role |
|---|---|---|---|
| **Descent (log-zoom phase + ring scroll)** | `f.beat_phase01` (cached grid); **fallback** `f.arousal` when no grid / irregular track | per-beat (ramped) | **HERO** — the beat is forward travel |
| **Throat width / ring spacing** | `f.bass_att_rel` | continuous / slow | **HERO #2** — bass drop widens the well |
| **Twist (rotation accumulation)** | `f.mid_att_rel` (larger gain; smaller amplitude post-AGC2) | slow | the log-spiral turn |
| **Wall hue / palette phase** | `f.spectral_centroid` | slow | colour, not motion |
| *(optional secondary)* **newest-ring edge glow** | `f.spectral_flux` | texture | fine life on the leading ring |

**Self-check:** the descent layer holds exactly one *active* primitive at a time (grid → `beat_phase01`; else → `arousal`), so no layer runs two primitives at once. Throat, twist, hue each have their own distinct primitive/timescale. The optional edge-glow is routed to `spectral_flux` (texture timescale) **specifically to avoid a second beat-rate layer competing with the descent** (FA #67) — do not route it to `drums` onset. Four clean layers in v1; edge-glow only if it earns it at M7.

**Liveness:** `beat_phase01` alive with a grid; `arousal`, `bass_att_rel`, `spectral_centroid`, `spectral_flux` reliably alive; `mid_att_rel` alive post-AGC2 with smaller amplitude → use a larger gain and expect a 1–2 s cold-start warmup.

## A5. Silence state (D-037)

At `totalStemEnergy == 0`: a **slow, gentle free-fall** (descent on the low arousal floor), dim tunnel, calm cool palette, a soft non-black throat glow. No hard beat steps (no grid energy). The destination is "drifting down a quiet well," not "tunnel off."

## A6. Palette

IQ cosine `palette()`, jewel-toned, **per-ring hue drift** so the walls are a slow spectrum receding into the throat; centroid drives phase, valence nudges warm/cool. Bright emissive throat; pale-tone share ≤ 30 %. Chromatic aberration intensifying toward the throat sells the depth.

## A7. Reference sourcing (curate before Part B runs — Matt-owned)

Populate `docs/VISUAL_REFERENCES/droste_descent/` and write its `README.md`. Shopping list:

- `01_macro_light_tunnel.jpg` — **real photo** of an LED/mirror light-tunnel or infinity-mirror installation (generic installation, not a specific copyrighted artwork) — the receding-rings-into-a-throat read.
- `02_meso_droste_photo.jpg` — **real photo** exhibiting the Droste effect (a recursive image containing itself) — the self-similar nesting.
- `03_micro_spiral_staircase.jpg` — **real photo** up/down a spiral staircase or nautilus cross-section — the log-spiral twist + per-ring ornament.
- `04_palette_neon_corridor.jpg` — **real photo** of a neon/jewel-lit corridor for the emissive palette + throat glow.
- **Porting references (read before coding, FA #73):** Lenstra & de Smit, *"Escher and the Droste effect"* (the conformal log-polar mathematics); a canonical log-polar / Droste **tunnel Shadertoy** (cite its ID in the shader header); Inigo Quilez's log-polar and 2D-SDF articles.
- `05_anti_flat_rings_AIGEN.jpg` (`_AIGEN` allowed only here) — the failure mode: flat 2D concentric rings scrolling with **no self-similar depth** (a pipe, not a Droste well); also anti: a nauseating high-contrast strobe tunnel.

## A8. Performance & tier

2D fragment + `mv_warp` 3-pass — cheap. Well under the Tier-2 preset ceiling; no SSGI/ray-march. Reduced-motion path skips the accumulator — ensure the analytic tunnel fragment alone still reads as a static tunnel (it should, since the rings are analytic). Rubric: **lightweight recommended** (DECISION-NEEDED).

## A9. Fidelity-uplift arc

- **PG.2.1 (Part B, this session) — reviewable v1:** log-polar tunnel + beat-locked descent (with arousal fallback) + bass throat + twist + hue + silence + palette. Enough for an M7 look.
- **PG.2.2 — depth + nesting:** full conformal Droste twist (Escher log-spiral, not just concentric rings), per-ring ornament + nested ring-motif, chromatic aberration + throat bloom polish.
- **PG.2.3 — beat-lock polish:** D-154 irregular-track detection + graceful fallback tuning; optional `spectral_flux` edge-glow; landing emphasis on `bar_phase01` downbeats.

## A10. JSON sidecar sketch

```jsonc
{
  "name": "Droste Descent", "family": "geometric",
  "concept_tags": ["fractal","hypnotic","geometric"], "motion_paradigm": "mv_warp",
  "passes": ["mv_warp"], "duration": 30,
  "decay": 0.88, "base_zoom": 0.10, "base_rot": 0.02, "beat_zoom": 0.03, "beat_rot": 0.0,
  "beat_source": "bass",
  "certified": false, "rubric_profile": "lightweight",
  "complexity_cost": { "tier1": 0.0, "tier2": 0.0 },
  "visual_density": 0.6, "motion_intensity": 0.8,
  "color_temperature_range": [0.15, 0.9], "fatigue_risk": "high",
  "transition_affordances": ["crossfade","cut"],
  "section_suitability": ["buildup","peak","bridge"]
}
```
(`base_zoom` ≥ 2–4× `beat_zoom` keeps continuous-descent primary over the per-beat step — the Layer-4 rule of thumb. `fatigue_risk: high` because sustained inward motion tires fast; the orchestrator should space it out.)

---
---

# PART B — SESSION PROMPT (PG.2.1)

## Increment PG.2.1 — Droste Descent scaffold + beat-locked descent (preset increment)

**Objective:** After this session, Phosphene has a new `mv_warp` preset "Droste Descent" that renders a crisp self-similar log-polar tunnel; descends one ring inward per beat via cached-grid `beat_phase01` (with an `arousal` free-fall fallback when no grid is installed); widens/closes its throat with the bass envelope; twists slowly; renders a non-black drifting tunnel at silence; and is registered, compiling, loading, and covered by a multi-frame harness test. `certified` stays `false`. This is the reviewable v1 of the PG.2 arc in `PG_2_DROSTE_DESCENT.md §A9`.

## 1. Skills to invoke (in order)
- **`preset-session`** — before any `.metal` / sidecar edit. Pay special attention to the audio-data hierarchy §Layer 4 (beat-locked motion on the cached grid) and the FFO beat-sync pattern (D-153 → D-158).
- **`shader-authoring`** — before any GPU code.
- **`closeout`** — at the end.

## 2. Read-first (exact, ordered)
1. `PG_2_DROSTE_DESCENT.md` (this doc — Part A is the design of record).
2. `docs/VISUAL_REFERENCES/droste_descent/README.md` and every image.
3. `docs/CAPABILITY_REGISTRY/BEAT_SYNC.md §Cold-Start Phase Contract` (what `beat_phase01` can/can't claim at track start) and the FFO beat-sync narrative (D-153 → D-158) — the pattern for beat-locked motion.
4. `docs/ARCHITECTURE.md §GPU Contract Details` and `§Presets` (mv_warp three-pass).
5. `docs/SHADER_CRAFT.md §2.2`, `§3`, `§14` (esp. §14.1 signal liveness).
6. `PhospheneEngine/Sources/Presets/Shaders/VolumetricLithograph.metal` (mv_warp reference) and `PresetLoader+WarpPreamble.swift`.
7. `PhospheneEngine/Sources/Presets/Nimbus/NimbusState.swift` (reference slot-6 state buffer for the descent-phase accumulator + fallback flags).

## 3. Pre-flight invariants (a failed check stops the session)
- `git status` clean on `main`; `swift test --package-path PhospheneEngine` green.
- `docs/VISUAL_REFERENCES/droste_descent/` populated per `§A7` + `README.md` written. **If not, curate first (Matt-owned) or stop** — do not author blind.
- `docs/ENGINEERING_PLAN.md` has a Phase PG / PG.2.1 row (add it in the docs task if absent).
- A test fixture *with a cached BeatGrid* (e.g. Love Rehab 125 BPM) is available for the beat-lock test, and a *no-grid / reactive* fixture is available for the fallback test.
- Confirm the production preset count for `PresetLoaderCompileFailureTest` to bump by exactly 1.

## 4. Tasks (each has a done-when)
1. **Plan + scaffold.** Add the PG.2.1 row to `ENGINEERING_PLAN.md`. Create `Shaders/DrosteDescent.metal` + `DrosteDescent.json` + register + bump `expectedProductionPresetCount`. **Done-when:** app + engine build; `PresetLoaderCompileFailureTest` passes at the new count; preset loads.
2. **Analytic log-polar tunnel (scene fragment).** Implement the crisp tunnel: `uv → (log(r), θ)`, self-similar rings via `fract(log2(r)·k − descentPhase)`, N-gon/star ring SDF + per-ring rotation offset + throat vignette + palette. `descentPhase` is a uniform for now (constant). **Done-when:** a `RENDER_VISUAL=1` contact sheet at a fixed phase shows a crisp centered tunnel of self-similar receding rings with a bright throat, non-black.
3. **Feedback warp = the recursion.** Implement `mvWarpPerFrame`/`mvWarpPerVertex`: radial zoom toward center (fixed scale/frame) + slow twist; decay per sidecar. **Done-when:** the multi-frame harness (adapt `AuroraVeilMVWarpAccumulationTest`) shows infinite inward recursion accumulating over ≥ 60 frames, crisp (no smear), rings visibly containing smaller rings.
4. **Beat-locked descent (slot-6 state).** Add `DrosteDescentState` (slot-6, byte-matched MSL mirror) holding the descent-phase accumulator + a `hasGrid` fallback flag. Drive `descentPhase` from `f.beat_phase01` (ramp 0→1 per beat = one ring inward per beat); when `beats_per_bar == 0` / no grid, drive from `f.arousal` continuous rate instead. **Done-when:** on the *grid* fixture a multi-frame test shows one ring crossing a fixed reference radius per beat (assert ring-crossing count ≈ beat count over the window); on the *no-grid* fixture the descent is smooth and continuous (assert monotonic phase advance, no per-beat step).
5. **Bass throat + twist + hue.** Wire `bass_att_rel` → ring spacing/throat width, `mid_att_rel` → twist rate (larger gain), `spectral_centroid` → palette phase, per `§A4`. **Done-when:** a contact sheet across low vs high bass shows a visibly wider throat / larger ring spacing at bass-drop; shader review confirms the routing matches `§A4`.
6. **Silence state.** Verify `§A5`: slow drift, dim, calm palette, non-black throat. **Done-when:** the silence contact sheet is non-black and shows a slowly-drifting tunnel with no hard steps.
7. **Audio routing review.** Confirm deviation primitives only, one primitive per layer; add the liveness note in the shader header. **Done-when:** `grep` finds no absolute-threshold pattern on raw `f.bass`/`f.mid`; routing matches `§A4`; the descent layer never runs two primitives simultaneously.
8. **Performance.** `PresetPerformanceTests` on silence/steady/beat-heavy; record p50/p95/p99. **Done-when:** p95 ≤ Tier-2 budget; recorded.
9. **Golden hash — STOP AND REPORT.** Register the golden 3-tuple; do NOT touch other presets' goldens. Produce the M7 contact sheet (include one beat-heavy fixture frame). **Done-when:** new golden passes; then **stop and report** with the contact sheet.
10. **Closeout.** Invoke `closeout`; 8-part report with the verbatim evidence block, the dispatch-path statement, the beat-lock firing evidence (ring-crossings-per-beat), and perf numbers.

## 5. Do-NOT
- **No absolute thresholds** (D-026 / FA #31).
- **Descent locks to `beat_phase01` from the cached grid — never raw live onsets** (Layer 4; jitter + feedback = unusable). The `arousal` free-fall is the *only* fallback and is selected, not summed.
- **Do not put a second beat-rate primitive on any layer** (FA #67) — no `drums` onset glow in v1; if an edge accent is wanted it goes on `spectral_flux`.
- **One motion paradigm** (D-029) — `mv_warp` only; no camera, no particles.
- Do not flip `certified`; do not regenerate other goldens; do not commit out-of-scope files.
- Do not author the full conformal-Droste twist or per-ring ornament here — those are PG.2.2.

## 6. Verification commands
```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
swift test --package-path PhospheneEngine --filter "PresetLoaderCompileFailureTest|DrosteDescent|PresetRegressionTests"
RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview 2>&1
```

## 7. Commit message templates (small commits; local `main`; push only on Matt's "yes, push")
- `[PG.2.1] Presets: scaffold Droste Descent (mv_warp) + JSON sidecar + registration`
- `[PG.2.1] Droste Descent: analytic log-polar self-similar tunnel fragment`
- `[PG.2.1] Droste Descent: mvWarpPerFrame/PerVertex radial-zoom recursion + twist (decay 0.88)`
- `[PG.2.1] Droste Descent: slot-6 descent state + beat_phase01 descent + arousal fallback`
- `[PG.2.1] Droste Descent: bass throat + twist + hue + golden hash + perf + ENGINEERING_PLAN row`

## 8. Closeout format
Invoke `closeout`; 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions: (a) dispatch path exercised (`warp → compose → blit`); (b) beat-lock evidence — ring-crossings-per-beat on the grid fixture and monotonic-phase on the no-grid fixture; (c) perf p50/p95/p99; (d) M7 contact-sheet path (incl. a beat-heavy frame); (e) ENGINEERING_PLAN PG.2.1 status.

## 9. DECISION-NEEDED (surface to Matt at review, product-level)
- **Descent feel.** *Options:* **Locked-and-crisp** — one clear ring per beat, reads as riding the pulse (recommended); **Continuous-with-a-nudge** — always falling, the beat just accelerates it briefly (gentler, less "steppy," better on syncopated music). *Recommendation:* Locked-and-crisp on regular tracks, auto-fallback to continuous on irregular ones (D-154). *Default if silent:* that hybrid.
- **Provenance framing.** This tunnel overlaps the Milkdrop register "Travelling backwards in a Tunnel of Light" (a named MD candidate). Keep **Phosphene-native** (recommended — our mechanic is conformal-math + beat-lock, distinct) or reframe as `milkdrop_inspired` (adds `inspired_by` + the D-116/D-121 side-by-side divergence check). *Default if silent:* Phosphene-native.
- **Rubric profile:** `lightweight` (recommended) vs `full`. *Default:* lightweight.
