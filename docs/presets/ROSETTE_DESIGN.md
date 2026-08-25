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
**Decisions:** D-217 (full cartouche), D-218 (maquette landed).
**Status:** registered (WHIT.1c) and harmony-coupled for 3 of 5 proposed routes (WHIT.1d).
`certified: false`, pending Matt's live M7. `tonalPhaseFifths` (rotation) and `harmonicFlux`
(symmetry-order step) are deferred to **WHIT.1d-2** — both need a value held across frames (a
stateful circular smoother; a hold-timer), which Rosette has no infrastructure for yet. §5 below
is current as of WHIT.1d.

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

## 5. Harmony coupling — all 5 routes shipped (WHIT.1d / WHIT.1d-2)

`WHITNEY_PROGRAM.md` §5.1's mapping table proposed five routes. **Three shipped stateless at
WHIT.1d** (§5.1–5.2); **the remaining two shipped at WHIT.1d-2** (§5.3) once `RosetteState`
existed to hold the cross-frame smoother and hold-timer they need. All five green on
`RouteCoverageTests`.

### 5.1 Shipped: `figure_tightness` ← `tonalConsonance`

**Harmony SETS the sweep position; the clock demotes to a floor drift** (§5.3's Nacre-round-1
lesson, honoured structurally, not just documented). Implementation in `Rosette.metal`:

- TONAL.2b's calibration (`WHITNEY_PROGRAM.md` §5.2 — floor 0.05, corpus median 0.117, p99 0.32)
  is applied via a **square-root curve** on the normalised band, not linear/smoothstep: linear
  puts the median at ~0.15 of the tightness range (the exact failure §5.2 warns about);
  `sqrt((0.117−0.05)/(0.32−0.05)) ≈ 0.50` lands it at the range's midpoint.
- `presence = smoothstep(0.02, 0.08, tonalConsonance)` gates the blend between the harmony-set
  position and the clock-driven floor drift — using consonance's own documented analyzer floor
  (0.05, width 0.03) as the "is there tonal content" signal, so no second primitive is needed for
  presence-gating (FA #67 — one primitive per layer would otherwise be at risk here).
- Verified two ways: `RosetteMVWarpAccumulationTest.test_rosette_harmonyCoupling` (consonance
  0.0 vs 0.32 at fixed clock time produces meaningfully different renders); a visual dump at
  floor/median/p99 consonance (`06_specular`-style comparison) shows the p99 render as a visibly
  tighter, more closed figure than the low-consonance renders.

### 5.2 Shipped: `stroke_presence` ← `bassDev`, `morph_floor_rate` ← `midAttRel`

Both continuous, both read fresh every frame, no state. `bassDev` swells stroke brightness/
halation (deviation primitive, D-026 — never an absolute threshold, FA #31). `midAttRel` scales
the floor-drift clock's rate via a bounded multiplicative time-warp — **not** a true per-frame
integral (that needs the same cross-frame state §5.3 below rules out); documented as a reasonable
approximation for a slowly-varying, heavily-smoothed (`*_att_rel`) primitive.

### 5.3 Shipped at WHIT.1d-2: `morph_position` ← `tonalPhaseFifths`, `symmetry_order_step` ← `harmonicFlux`

Both needed a value **held across frames**, which Rosette had no infrastructure for until
WHIT.1d-2 built `RosetteState` (`Presets/Rosette/RosetteState.swift`) — a per-preset Swift state
object following Skein/Gossamer's minimal shape (one `MTLBuffer`, `tick()` flushes a GPU mirror
struct), wired through `VisualizerEngine`/`VisualizerEngine+Presets.swift` (`bindRosetteRuntime`,
`StatefulRuntimeRegistry.knownPresetNames`) — the first WHIT increment to touch the app layer:

- **`tonalPhaseFifths` is a raw ±π sawtooth** (`CircularPhaseSmoother.swift`) that must be smoothed
  through a stateful circular smoother (D-209) before any visual use, or it jumps at the seam —
  documented as the exact defect that hit Fractal Tree (`f.tonalPhaseFifths` read straight into
  hue, 144°/p95 jump, Matt: *"Color changes feel glitchy, not intentional"*). `RosetteState` tracks
  cos/sin separately via EMA (τ=3s) and recombines via `atan2`. The originally proposed mapping
  ("where in the morph family") also collided with `tonalConsonance` on the same single visual DOF
  (`a`) once the generator is a one-scalar epicycle — an FA #67 audit finding from
  `WHITNEY_PROGRAM.md`'s pre-spike design (D-219). **Resolved by mapping the smoothed phase to a
  rotation of the figure only** — the wings stay fixed (`q` is untouched; only the figure's sample
  coordinate `pf` rotates before the distance search), preserving the D-217 frame — a genuinely
  distinct visual channel from tightness.
- **`harmonicFlux` uses a hold-timer**: it "spikes at chord changes" (`kind: accent`), so a discrete
  symmetry-order step driven directly off a per-frame spike would flicker, not hold for "tens of
  seconds" as `WHITNEY_PROGRAM.md` §2 requires. `RosetteState`'s hold-timer (`minHoldSeconds=24s`,
  `fluxStepThreshold=0.09`) steps the epicycle's `n` through Whitney's own sequence (5→6→4) on a
  qualifying spike, never more often than the hold window — honouring the anti-contract ("the
  symmetry order must never flicker").
- `rosetteCurve`/`rosetteDist` took `n` as a third parameter (previously the fixed constant
  `kRosetteN = 5.0`); the `aMin`/`aMax` tightness calibration (task 2's CPU sweep, n=5) is reused
  as-is for the stepped orders — a reasonable approximation, not re-swept per `n`.
- `RosetteUniforms` (Metal struct) / `RosetteUniformsGPU` (Swift mirror, byte-for-byte) travel at
  fragment buffer(6), Skein's per-preset-uniforms convention.
- Found live: `MultiPassRenderHarness`'s `renderMVWarp` case (used by the flash-safety harness,
  separate from `_acceptanceFixture`) only special-cased `SkeinState` binding at buffer(6) — an
  unbound slot reads zeros, collapsing `n` to 0 and degenerating the curve to a fixed unit circle
  regardless of audio input. `rosetteIsFlashSafe` correctly read this as a harness fault ("rendered
  static... the harness is not reaching its real multi-pass response") rather than a false pass;
  fixed by binding `RosetteState` there too (D-220).

### 5.4 Colour stays off the figure (unchanged)

`tonalConsonance`/`tonalPhaseFifths` never touch the central stroke's hue (§5.1, F3) — the figure
is white/pale-lavender always. Hue lives only in the wing arcs (§6.3), which still drift on an
independent plain clock and have no route (a candidate for a later increment, not requested yet).

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

## 7. Audio-routing table — all 5 declared (WHIT.1d / WHIT.1d-2)

`WHITNEY_PROGRAM.md` §7 proposed five routes. **All shipped, audited against code, green on
`RouteCoverageTests`** (206 routes across 22 presets, 0 red):

| `route` | `primitive` | `kind` | Status |
|---|---|---|---|
| `figure_tightness` | `tonalConsonance` | continuous | **Shipped** (§5.1, WHIT.1d) |
| `stroke_presence` | `bassDev` | continuous | **Shipped** (§5.2, WHIT.1d) |
| `morph_floor_rate` | `midAttRel` | continuous | **Shipped** (§5.2, WHIT.1d) |
| `morph_position` | `tonalPhaseFifths` | continuous | **Shipped** (§5.3, WHIT.1d-2) |
| `symmetry_order_step` | `harmonicFlux` | accent | **Shipped** (§5.3, WHIT.1d-2) |

All five declared in `Rosette.json`'s `audio_routes` — QG.1's discipline (a declared route the code
doesn't read is as wrong as an unread route left undeclared) was honoured at each step: WHIT.1d
declared only the three it built, WHIT.1d-2 added the remaining two once `RosetteState` actually
read them.

## 8. Grounding audit (`PRESET_SESSION_CHECKLIST` grounding ladder)

| Mechanism | Level | Evidence |
|---|---|---|
| Two-term epicycle generator | **1 — working reference, cited and validated twice** | Whitney's own published theory (`Digital Harmony`, cited at `WHITNEY_PROGRAM.md` §8/§13) names the Fourier/epicycle family (F13); WHIT.0's CPU sweep validated the state-family match; `docs/VISUAL_REFERENCES/rosette/05_macro_pentagon_straight_edges.jpg` is independent photographic confirmation of the one predicted miss. |
| SDF-in-fragment stroke rendering | **1 — working reference, directly copied** | Skein's shipped, certified `skein_geometry_vertex`/`_fragment` pattern, not invented. |
| The combination (numerically-searched epicycle SDF + wing-arc capsule SDF, both inside one `strandsOnTop` fragment) | **1 — validated together**, not just piecewise | WHIT.0 rendered and inspected the actual combination; the three bugs in §6.4 were only found by running the combination, not by reasoning about the pieces separately. |
| Harmony coupling — consonance/bassDev/midAttRel (§5.1–5.2) | **1 — measured, calibrated, verified** | TONAL.2b's 1000-track calibration grounds the sqrt curve; `RosetteMVWarpAccumulationTest.test_rosette_harmonyCoupling` + a visual dump verify the mapping renders as designed. |
| Harmony coupling — tonalPhaseFifths/harmonicFlux (§5.3) | **1 — measured, verified against the real dispatch path** | `RosetteState`'s circular smoother (D-209 pattern) and hold-timer are direct ports of already-shipped infrastructure (`CircularPhaseSmoother`, Skein's hold-window discipline); `test_rosette_rotationAndSymmetryCoupling` verifies both the rotation and the symmetry-step render as designed through the real geometry-overlay dispatch. Was level 3 at WHIT.1d (D-219); resolved at WHIT.1d-2 (D-220). |

## 9. Hard constraints carried forward from `WHITNEY_PROGRAM.md` §9

§9.1 (temporal aliasing bounds N) and §9.2 (trail/legibility trade-off) are **WHIT.C-scoped** (the
dot field), not Rosette's — Rosette has no accumulating trail to bound (§6.2). §9.3 (strobing /
photosensitivity) and §9.4 (no easing, fp32 phase) apply directly:

- **§9.3 measured at WHIT.1d** (`MultiPassFlashHarnessTests.rosetteIsFlashSafe`, `harmonicMotion:
  true` so `figure_tightness` actually moves during the measurement): 0.00 flashes/s, luma
  0.033–0.037 (Δ0.004) — flash-safe, and by a wide margin. Makes sense structurally: the fragment
  repaints every pixel opaque every frame (§6.2, no accumulation to smooth a spike), and a thin
  bright line on a large near-black field barely moves the frame's mean luminance regardless of
  tightness or brightness swings.
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
- **D-218 is resolved** — Rosette registered, `certified: false`. Halation retuned, numerical
  search profiled clean, three harmony routes shipped and measured flash-safe.
- **The straight-edged-pentagon miss is accepted**, not an open defect (§4.1). Adding a third
  harmonic term is a decision for Matt if ever wanted, not a default fix.
- **D-220 is resolved** — `RosetteState` built, `tonalPhaseFifths` (rotation) and `harmonicFlux`
  (symmetry-order step) both shipped (§5.3). All 5 declared routes green on `RouteCoverageTests`.
- **`complexity_cost.tier2` (M3+) is still an unverified ~0.6x estimate**, not measured on real
  hardware (carried from WHIT.1c).
- **Remaining before certification**: Matt's live M7 review against the curated references
  (`docs/VISUAL_REFERENCES/rosette/`) — the only still-open item on the certification path.
