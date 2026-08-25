# Rosette — design record

**Phase:** WHIT (Whitney program), lead preset (`WHITNEY_PROGRAM.md` §8 WHIT.A)
**Increment sequence:** WHIT.0 (look-spike, done, GO) → WHIT.1a (references, done) →
**WHIT.1b (this document)** → WHIT.1c (authoring) → WHIT.1d (harmony coupling) → WHIT.1e (certify)
**Source:** John Whitney Sr., *Arabesque* (1975) — a direct port of one named film via a measured
closed-form generator, not an uplift of an existing Phosphene or Milkdrop preset.
**References:** [`docs/VISUAL_REFERENCES/rosette/`](../VISUAL_REFERENCES/rosette/README.md) — read
that README before any WHIT.1c work (`PRESET_SESSION_CHECKLIST.md` Part 1 step 1).
**Program doc:** [`WHITNEY_PROGRAM.md`](WHITNEY_PROGRAM.md) carries the shared program rationale
(§§1–9). This document does not repeat it — it cites the relevant section, states whether WHIT.0
validated or revised it, and adds what only a running spike could produce: real film photographs
at the states that matter, the architecture that actually renders correctly, and the bugs a naive
reading of §6 would reproduce.
**Look-spike:** WHIT.0, verdict **GO** (`docs/ENGINEERING_PLAN.md` Phase WHIT / Increment WHIT.0).
**Decisions:** D-217 (full cartouche).
**Status:** design only. No `.metal` file and no JSON sidecar exist under
`PhospheneEngine/Sources/Presets/Shaders/` — WHIT.0's `Rosette.metal` lives at
`PhospheneEngine/Tests/PhospheneEngineTests/Presets/Fixtures/Rosette/`, deliberately unregistered.
WHIT.1c authors the registered version; §6 below is its starting point.

---

## 1. Musical role (validated, not just proposed)

`WHITNEY_PROGRAM.md` §1's one-sentence rule stands unchanged:

> **When the music's harmony settles, the drawn figure tightens into a crisp closed emblem; when
> it moves or turns atonal, the emblem unravels into open arcs — so a chord resolving is the
> moment the drawing snaps into focus.**

What WHIT.0 adds: the figure side of this sentence is no longer a claim about a proposed shader —
it is a rendered, motion-gated fact. The tighten/unravel morph runs on the real `PresetLoader`
compile path and reads as a continuous, legible, non-repeating cycle (§4 below). What WHIT.0 did
**not** touch is the harmony side — no `tonalConsonance` route exists yet (WHIT.1d). The sentence
is validated on the visual half only; the musical half is still a design commitment, not a
measurement.

## 2. Temporal contract — which rows are validated, which are still assertions

`WHITNEY_PROGRAM.md` §2's table is reproduced in full there; it is not restated here. WHIT.0 ran
**zero audio**, so only the rows that don't depend on a harmony route could be exercised:

| Row | Status after WHIT.0 |
|---|---|
| "The morph runs at constant rate... never eased" | **Validated, and revised.** A sine-parameterised clock eased at the tight/loose extremes (motion_gate.sh measured 82/299 near-frozen frames) — a real defect, not a false alarm. Fixed with a triangle-wave clock (constant `\|dA/dt\|` except an instantaneous reversal at each extreme); re-measured at 52/299, and the residual is a property of the curve family's `a→shape` sensitivity, not the clock (see §4). **§9.4's "no easing" requirement is now backed by a measured failure and a measured fix, not just Whitney's stated servo behaviour.** |
| "The figure never leaves the screen... never blanks, resets, restarts" | **Validated by construction.** The geometry fragment repaints every pixel opaque every frame (§6) — there is structurally no path to a blank or frozen frame short of a shader crash. |
| Cold start / vamp / resolution / chord change / modulation / percussion-atonal / silence rows | **Untested — all depend on a harmony route that does not exist yet.** WHIT.1d's first job is exercising each of these against real `tonalConsonance`/`tonalPhaseFifths`/`harmonicFlux` data, not assuming the table is correct because the visual mechanism is proven. |

## 3. Three-part concept bar

`WHITNEY_PROGRAM.md` §3 already scored PASS/PASS/PASS before WHIT.0 ran. WHIT.0 strengthens two of
the three with evidence rather than argument:

| Bar | WHITNEY_PROGRAM §3 | WHIT.0 evidence |
|---|---|---|
| Iconic visual subject deliverable at fidelity | PASS (argued from the film's own sparse frames) | **PASS, demonstrated.** A rendered stroke exists, at a quality judged "close, not exact" against a same-scale film crop (§4). |
| Clear musical role | PASS | Unchanged — §1 above. |
| Infrastructure-feasible | PASS (argued from file:line citations) | **PASS, demonstrated.** Ran on the real `PresetLoader` compile path with zero engine source changes; three bugs found were all in the spike's own test harness / shader, none in `PhospheneEngine/Sources/Renderer` or `PhospheneEngine/Sources/Presets/PresetLoader*.swift`. |

## 4. The mechanic

`WHITNEY_PROGRAM.md` §4 documents Whitney's general **differential-dynamics** mechanic (rate ∝
index, collapsing onto resonance rays) — this is the historical/theoretical background for the
*whole* program and is specifically WHIT.C's (Unison, the dot field) generator. **It is not
Rosette's formula.** Rosette uses the closed-curve family named at `WHITNEY_PROGRAM.md` §8
(WHIT.A, formula F13):

> z(t) = e^{it} + a·e^{-i(n-1)t}, n = 5 fixed this phase, `a` the single morph parameter.

### 4.1 Generator verdict (WHIT.0 task 2, CPU sweep — validated, not re-derived here)

A stdlib-only Python sweep at n=5, a ∈ [0, 2.2] (no numpy/PIL available in the session environment
— a hand-rolled PNG rasterizer sufficed) reproduced, **in the observed order, from one scalar**:
circle → rounded-pentagon-ish → cusped 5-star → petals-with-inner-loops → broad petals →
petals-crossing → tangle. This is the bulk of `rosette_build.png`'s observed state family.

**The miss, confirmed twice now — first by the sweep, then by film photography.** The two-term
family never produces a true straight-edged pentagon; it rounds the corners into a Reuleaux-like
bulge at any `a`. `docs/VISUAL_REFERENCES/rosette/05_macro_pentagon_straight_edges.jpg` is now hard
photographic evidence that the film's pentagon state has genuinely flat sides. **This is an
accepted limitation, not an open bug** — task 2's instruction was explicit that a miss is the
finding, and adding a third harmonic term to chase it is a decision for Matt, not a default action,
if a future session is tempted to "fix" it.

### 4.2 Morph clock (revised from a sine to a triangle wave — see §2)

`a(t)` sweeps `[aMin, aMax] = [0.05, 1.80]` via a triangle wave in `t/kRosettePeriod`
(`kRosettePeriod = 30 s`, matching `rosette_build.png`'s own span), **not** a sine — see §2's
table for why. This is a plain clock; WHIT.1d replaces it with `tonalConsonance` setting the sweep
position directly (§5.3's Nacre lesson: a free clock competing with harmony wins, and the coupling
reads as dead).

### 4.3 Size normalisation

The curve is divided by `(1+a)` before scaling to screen space, keeping the figure's overall
footprint roughly constant across the whole morph (matching the film, where the emblem's scale
does not visibly balloon between tight and loose states) rather than letting the raw radius swing
with `a`.

## 5. Harmony coupling — plan only, unbuilt (WHIT.1d)

`WHITNEY_PROGRAM.md` §5.1's mapping table is the design; it is not re-typed here. Nothing in this
section has been exercised — WHIT.0 deliberately ran zero audio so the morph's legibility could be
judged independent of a second (harmony) variable. Two structural rules from §5 carry forward
unchanged and must be re-verified against the real routing once WHIT.1d writes it:

- **Harmony SETS the sweep position; the clock demotes to a slow floor drift** (§5.3) — not
  additive to a free-running clock. This is the exact trap that made Nacre round 1 read as "not
  sure if it worked" despite the coupling being measurably active.
- **Colour stays off the figure** (§5.1, F3) — `tonalPhaseFifths`/`tonalConsonance` never touch the
  central stroke's hue. The figure is white/pale-lavender always; hue lives only in the wing arcs
  (§6.3), which currently drift on an independent plain clock and have no route at all yet.

## 6. Architecture — what actually renders, revised from §6's original proposal

`WHITNEY_PROGRAM.md` §6 proposed porting Dragon Bloom's exact `marks` configuration
(`"primitive": "line_strip"`, `vertex_count: ~1536`, `instance_count: 1`) — a raw hardware line
draw. **WHIT.0 did not build that, and §6 should be read as superseded by this section for
Rosette specifically.** The reason is stated in the program doc's own task 4 language: Metal's
line-primitive rasterization has no antialiasing and no variable width, and Rosette's fidelity is
entirely in the stroke — a raw `line_strip` was judged too likely to alias before ever being tried.

### 6.1 What was built instead: SDF-in-fragment, Skein's pattern

A single **fullscreen-triangle** marks overlay (`vertex_count: 3, instance_count: 1, primitive:
"triangle"` — copying Skein's `skein_geometry_vertex`/`_fragment` shape, not Dragon Bloom's). All
figure math happens per-pixel in the fragment stage:

- `rosette_geometry_vertex` — fullscreen triangle, passes `aspect_ratio` and `time` through to the
  fragment via the interpolated vertex→fragment struct (**not** by re-declaring `FeatureVector` as
  a fragment parameter — see §6.4, bug 2).
- `rosette_geometry_fragment` — computes `aMorph` from the clock (§4.2), runs a coarse-then-bisect
  numerical nearest-point search against the continuous curve function (no closed-form SDF exists
  for a self-intersecting two-term epicycle), converts distance to a bright-core + soft-halo
  intensity via two nested Gaussians, and composites the mirrored wing arcs (§6.3) and a near-black
  vignette ground. Every pixel is written opaque every frame — see §6.2.
- `mvWarpPerFrame` / `mvWarpPerVertex` — identity transform, `decay = 0.15` (light, not
  canvas-hold). Exercises the real `scene → warp → compose(strandsOnTop) → swap` dispatch
  (`RenderPipeline+MVWarp.swift:138`) without actually depending on the decay value (§6.2).

### 6.2 Canvas behaviour: opaque-every-frame, not decay-bounded

`ARABESQUE_FILM_NOTES` §4/§9.4: the film draws the figure complete every frame; the glow is
halation around a stroke, never a decaying comet-tail. Rosette's fragment shader writes **alpha =
1.0 everywhere, every frame** — background and figure alike — so the warp pass's `decay` parameter
has no visible effect (the compose blend always resolves to the current frame regardless of what
came before). This is a stronger, structurally-guaranteed version of "no long trails" than tuning a
low decay value would give: there is no numeric value of `decay` that could reintroduce a trail
under this fragment, short of also making the fragment's alpha non-opaque somewhere.

### 6.3 Wing arcs + ellipses (F4, D-217: full cartouche)

Two mirrored instances' worth of geometry computed in the same fragment: a shallow bowed arc near
each frame edge plus a small ellipse near its lower end, in a slowly hue-drifting colour
independent of the main figure. **D-217 (Matt, 2026-08-25): these ship as part of the base preset,
not an optional extra** — the with/without comparison in WHIT.0's closeout was decisive (without
them the figure reads as a floating diagram; with them it reads as a composed picture).

The wing arc's distance field must use **point-to-segment** distance, not nearest-of-discrete-
samples — see §6.4, bug 3.

### 6.4 Three bugs found live, and why WHIT.1c should read this before re-deriving them

All three were in the WHIT.0 test harness or the shader, never in engine source
(`PhospheneEngine/Sources/Renderer`, `PhospheneEngine/Sources/Presets/PresetLoader*.swift`):

1. **Unbound `chromaticMix`.** `mvWarp_fragment`'s fragment `buffer(0)`
   (`PresetLoader+WarpPreamble.swift:155`) is `chromaticMix`, a value distinct from the
   vertex-table `FeatureVector` at the same buffer index. Left unbound, it reads undefined GPU
   memory and drives a runaway hue-zoom resample feedback loop — rendered as a concentric-ring
   kaleidoscope swamping the entire frame. Any harness or dispatch code driving the warp pass by
   hand must bind it explicitly (`0.0` = identity, matching `marks.chromatic` in the sidecar).
2. **`FeatureVector` is not readable in the geometry fragment via a re-declared parameter.**
   `drawSceneGeometryOverlay` (`RenderPipeline+SceneGeometry.swift`) binds `FeatureVector`/
   `StemFeatures` at the **vertex** argument table only for the marks pass. A fragment that needs
   per-frame scalars (the clock, eventually audio) must receive them via the interpolated
   vertex→fragment struct (what §6.1 does for `time`/`aspect`) or a dedicated per-preset buffer at
   slot 6 (Skein's `SkeinUniforms` convention) — never by declaring `constant FeatureVector& f
   [[buffer(0)]]` as a fragment parameter and expecting it to inherit the vertex binding. Getting
   this wrong reads as "the clock isn't working" (every frame renders the same fixed mid-morph
   shape), which looks like a math bug and is actually a binding bug.
3. **Wing-arc beading.** A distance-to-nearest-of-N-discrete-sample-points computation (rather than
   nearest-point-on-segment) leaves gaps at the midpoint between samples, rendering as a dashed/
   beaded line instead of a continuous stroke. Fixed with a standard point-to-segment (capsule)
   SDF. The main figure's distance field never had this defect — its bisection refinement evaluates
   the continuous curve function directly, not a fixed sample array — so this is specific to any
   future geometry (like the wings) that samples a curve at discrete points without refinement.

### 6.5 Stroke quality — numbers to tune against, corrected twice

- **Near-black ground.** The render target is `bgra8Unorm_srgb` — the real drawable format
  (`MetalContext.swift:55`). A naive "near-black" linear value (WHIT.0's first attempt, 0.035)
  displays as ~20% grey after the sRGB encode. Current value (0.006) was tuned by eye against the
  encoded output, not against the raw number — any future retune must view the actual rendered
  frame, not reason from the linear constant.
- **Halation width.** WHIT.0 task 1's own estimate from the small evidence-sheet thumbnails
  (halo ≈ 3–5× core width) was too generous. `docs/VISUAL_REFERENCES/rosette/
  06_specular_stroke_core_halo.jpg`, viewed at a proper crop scale, reads closer to **1.5–2×**.
  WHIT.0's shipped render used the thumbnail-derived (too wide) ratio — **WHIT.1c's first tuning
  pass should retune against `06`, not against WHIT.0's numbers.**

### 6.6 Known open engineering risk: the numerical search was never profiled

The coarse-40 + bisect-7 nearest-point search runs per pixel, per frame, for the main figure (plus
a similar per-pixel search for each wing arc). This is not a pattern used anywhere else in this
codebase for a shipped-perf preset, and WHIT.0 never measured it against the 60fps @ 1080p target
(CLAUDE.md's stated performance target). **This is WHIT.1c's first checkpoint, before any other
tuning**: profile it live; if it doesn't clear budget, the fallback options named in WHIT.0's own
task 4 are an SDF-swept triangle-strip ribbon (vertex-stage geometry, no per-pixel search) or a
reduced coarse-sample count with a correspondingly coarser bisection tolerance.

## 7. Audio-routing table (WHIT.1d; audit before declaring)

`WHITNEY_PROGRAM.md` §7's proposed manifest (five routes: `figure_tightness` ← `tonalConsonance`,
`morph_position` ← `tonalPhaseFifths`, `symmetry_order_step` ← `harmonicFlux`, `stroke_presence` ←
`bassDev`, `morph_floor_rate` ← `midAttRel`) is the plan. Not re-typed here; not yet audited
against code, because no code reads any of these yet (QG.1 — a declared route the code doesn't
read is as wrong as an unread route left undeclared). WHIT.1d writes the routes and the manifest
together, then runs `RouteCoverageTests`.

## 8. Grounding audit (`PRESET_SESSION_CHECKLIST` grounding ladder)

| Mechanism | Level | Evidence |
|---|---|---|
| Two-term epicycle generator | **1 — working reference, cited and validated twice** | Whitney's own published theory (`Digital Harmony`, cited at `WHITNEY_PROGRAM.md` §8/§13) names the Fourier/epicycle family (F13); WHIT.0's CPU sweep validated the state-family match; `docs/VISUAL_REFERENCES/rosette/05_macro_pentagon_straight_edges.jpg` is independent photographic confirmation of the one predicted miss. |
| SDF-in-fragment stroke rendering | **1 — working reference, directly copied** | Skein's shipped, certified `skein_geometry_vertex`/`_fragment` pattern, not invented. |
| The combination (numerically-searched epicycle SDF + wing-arc capsule SDF, both inside one `strandsOnTop` fragment) | **1 — validated together**, not just piecewise | WHIT.0 rendered and inspected the actual combination; the three bugs in §6.4 were only found by running the combination, not by reasoning about the pieces separately. |
| Harmony coupling (§5) | **3 — no empirical grounding yet** | Explicitly deferred to WHIT.1d. Flagged here per the checklist's instruction to surface level-3 mechanisms immediately rather than let them arrive at code review. |

## 9. Hard constraints carried forward from `WHITNEY_PROGRAM.md` §9

§9.1 (temporal aliasing bounds N) and §9.2 (trail/legibility trade-off) are **WHIT.C-scoped** (the
dot field), not Rosette's — Rosette has no accumulating trail to bound (§6.2). §9.3 (strobing /
photosensitivity) and §9.4 (no easing, fp32 phase) apply directly:

- **§9.3** is untested — no `PhotosensitivityCertificationTests`/`MultiPassFlashHarnessTests` run
  exists for Rosette yet. WHIT.1c should measure this early, per the program doc's own instruction,
  not defer it to certification.
- **§9.4** is now empirically reinforced, not just theoretically stated — see §2's table and §4.2.

## 10. WHIT.1c authoring checklist

In rough order:

1. Profile the numerical nearest-point search for 60fps @ 1080p (§6.6) before any other work —
   this is the one open question that could force an architecture change.
2. Move/adapt `Rosette.metal` from `PhospheneEngine/Tests/PhospheneEngineTests/Presets/Fixtures/
   Rosette/` into `PhospheneEngine/Sources/Presets/Shaders/Rosette.metal`; author the real JSON
   sidecar (`certified: false`, `family: "geometric"`, `rubric_profile: "lightweight"`, `marks`
   block `triangle`/3/1, `decay: 0.15`, **no** `feedback_pixel_format` override — the WHIT.0
   pixel-format mismatch lesson, §6 of the WHIT.0 closeout).
3. Retune halation against `06_specular_stroke_core_halo.jpg` (§6.5) — do not keep WHIT.0's
   thumbnail-derived value.
4. Adapt `RosetteLookSpikeTests.swift` into the permanent multi-frame harness for this paradigm —
   once Rosette is registered, it can load via `_acceptanceFixture` like
   `AuroraVeilMVWarpAccumulationTest` does, instead of the `watchDirectory` scratch-dir mechanism
   WHIT.0 needed for an unregistered preset.
5. Run the flash/photosensitivity harness early (§9 above), before certification.
6. No audio coupling in WHIT.1c — that is WHIT.1d, per the increment ladder
   (`WHITNEY_PROGRAM.md` §10). A figure moving for two reasons (clock + harmony) at once cannot
   answer whether either one reads on its own; keep them separated by increment, as WHIT.0 kept
   the morph separated from audio.

## 11. Open risks and carried-forward decisions

- **D-217 is resolved** — full cartouche. Do not re-litigate; if a future session questions it,
  that needs new evidence, not a re-ask.
- **The straight-edged-pentagon miss is accepted**, not an open defect (§4.1). Adding a third
  harmonic term is a decision for Matt if ever wanted, not a default fix.
- **Halation and the numerical-search performance budget (§6.5, §6.6) are WHIT.1c's actual open
  work.** Everything else in this document is either validated or explicitly deferred to WHIT.1d.
