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

## 6. Architecture — real 3D swept-tube geometry (WHIT.2b), history below

**Current (WHIT.2b, 2026-08-26).** Rosette is a `ray_march + post_process` preset. The figure and
wing arcs/ellipses are genuine 3D tubes — a Pythagorean SDF wrapping the SAME 2D distance-to-curve
functions the 2D version used (`rosetteCurve`/`rosetteWingDist`/`rosetteWingEllipseDist`,
unchanged), rendered through the engine's shared ray-march / Cook-Torrance PBR / IBL / AO /
screen-space-shadow pipeline (D-021's `sceneSDF`/`sceneMaterial` contract) — the same pipeline
Volumetric Lithograph, Lumen Mosaic, and Ferrofluid Ocean already run on. This replaced the
`direct + mv_warp` fullscreen-fragment overlay described in §6.1-§6.6's original text below (kept
as history — the bugs and lessons in it are durable even though the architecture moved on).

- **Tube SDF.** For a planar curve `C(t)` lying in the z=0 plane, a tube of radius `r` swept
  around it is `sqrt(dist2D(p.xy, C)² + p.z²) - r` — the 2D nearest-point distance and the
  out-of-plane offset combine as a right triangle's hypotenuse. `rosetteFigureTubeSDF` /
  `rosetteWingTubeSDF` / `rosetteWingEllTubeSDF` in `Rosette.metal` are thin wrappers around the
  unchanged 2D distance functions.
- **State.** `RosetteUniforms` (rotation + symmetry-order state, unchanged from WHIT.1d-2/WHIT.2a)
  moved from the old `direct+mv_warp` overlay buffer onto ray-march fragment buffer(6) — see
  `docs/ARCHITECTURE.md` §GPU Contract Details for the full binding history.
- **Camera + lighting.** `scene_camera`/`scene_lights`/`scene_backdrop: "dark"` set up a
  conventional key+fill two-light rig against a near-black void (the `scene_backdrop` field
  decouples background darkness from light intensity — see `docs/ARCHITECTURE.md`'s GPU Contract
  Details for the mechanism). The camera is STATIC — see §6.10 (WHIT.2c) for why the WHIT.2b
  camera orbit was tried and removed.
- **Nearest-point search.** `rosetteDist` (the figure's distance-to-curve function) is a dense
  150-segment point-to-segment polyline scan, matching the wing arcs' own long-proven technique —
  see §6.7 for why this replaced the earlier coarse+bisect search, and §6.8 for the performance
  fix required to make a per-ray-march-step search affordable.
- **Material.** The figure stays pale/lavender-white (F3 — colour is not indexical on the figure);
  `bassDev` lifts albedo slightly (an emissive-feeling "catching more light" cue, replacing the 2D
  version's additive Gaussian glow — a genuinely different technique for the same musical role).
  The wings carry the saturated, hue-drifting colour (F4), unchanged in spirit from the 2D version.

### 6.7 WHIT.2b found live: the 2D distance search wasn't smooth enough for ray-march normals

Matt's first look at the converted preset: *"fidelity is poor - lines are really jagged."* The 2D
version's coarse-then-bisect search (BUG-104's fix, §6.6 below) produced a distance field accurate
enough for a flat, unlit fragment but not smooth enough for the ray-march G-buffer's per-pixel
finite-difference normal computation (four tiny `eps=0.001` offset taps) — visible as faceted,
unstable shading. Two structural fixes were tried and failed before switching to systematic
diagnosis (a Quilez-style smooth-min blend across branch candidates; more bisection precision).
The diagnosis that worked: isolating an outer loop with no nearby self-crossing showed the SAME
faceting (ruling out branch-seam theory), and comparing directly against the wing arcs — which
already used a dense point-to-segment polyline scan with no bisection, and rendered perfectly
smooth in the same frame — identified the search technique itself, not branch handling, as the
cause. `rosetteDist` was rewritten to the wing's own proven technique verbatim, at 150 segments
(chosen empirically: 70 and 110 both still showed visible faceting on the same test loop, while
150 and 600 were pixel-identical at the same extreme zoom).

### 6.8 WHIT.2b found live: the dense search needed a bounding-sphere gate to stay in budget

Running the full engine test suite for the first time against the completed conversion (not just
the targeted Rosette test files) surfaced a previously-invisible 150ms/frame regression
(`PresetFrameBudgetTests`: 14.8x the median preset, over the 60ms ceiling) — the dense polyline
search ran on every ray-march step of every pixel, including the ~90% of the 1080p frame that is
empty background far from the small (~0.3-radius) figure. Fixed with a bounding-sphere SDF lower
bound, mathematically exact from the curve's own magnitude identity
(`|z1+a·z2| <= |z1|+a|z2| = 1+a`, divided by the curve's own `(1+a)` normaliser proves the whole
tube lies within a sphere of exactly `kRosetteRadius + tubeRadius`) — applied to both the figure
and the wing tubes (whose own arc endpoints sit at a known fixed radius from a known center).
**A bare `boundD > 0` cutoff is unsound, not just imprecise**: the bounding sphere is TANGENT to
the true surface at specific points (the curve reaches exactly its bounding radius at `t=0`, for
every morph state), so the cheap branch can return a near-zero value there, which the ray-march
loop's relative hit epsilon (`d < 0.001·t`) reads as a genuine surface hit — this rendered a
false, audio-INDEPENDENT sphere silhouette that silently collapsed every aMorph/rotation/symmetry
difference `RosetteRayMarchTests` measures toward zero (caught because those coupling tests
failed, not because the render looked visibly wrong). Fixed with a safety margin (`0.03`, ~15x
the hit epsilon at this scene's camera distance) between the bounding radius and where the cheap
branch is trusted — only a thin shell around the true boundary falls through to the exact search.
Final measured cost: 28ms/frame at 1080p (4.8x the median preset), down from 150ms.

### 6.9 History (pre-WHIT.2b): the 2D `direct + mv_warp` architecture

The subsections below describe the ORIGINAL 2D fullscreen-fragment overlay architecture,
superseded by §6's ray-march conversion above. Kept because the bugs found in it (aspect-ratio
scaling, point-to-segment vs. discrete-sample distance fields, buffer-binding gotchas) are durable
lessons that apply to future preset work even though Rosette itself has moved past this
architecture.

`WHITNEY_PROGRAM.md` §6 proposed porting Dragon Bloom's exact `marks` configuration
(`"primitive": "line_strip"`, `vertex_count: ~1536`, `instance_count: 1`) — a raw hardware line
draw. **WHIT.0 did not build that.** The reason is stated in the program doc's own task 4
language: Metal's line-primitive rasterization has no antialiasing and no variable width, and
Rosette's fidelity is entirely in the stroke — a raw `line_strip` was judged too likely to alias
before ever being tried.

**What was built instead: SDF-in-fragment, Skein's pattern.** A single fullscreen-triangle marks
overlay (copying Skein's `skein_geometry_vertex`/`_fragment` shape, not Dragon Bloom's). All figure
math happened per-pixel in the fragment stage: `rosette_geometry_vertex` passed `aspect_ratio`/
`time` through the interpolated vertex→fragment struct; `rosette_geometry_fragment` computed
`aMorph` from the clock, ran the coarse-then-bisect nearest-point search, converted distance to a
bright-core + soft-halo intensity via two nested Gaussians, and composited the wing arcs + a
near-black vignette ground, writing alpha=1.0 everywhere every frame (a stronger, structurally-
guaranteed version of "no long trails" than tuning the warp pass's `decay` value — no numeric decay
could reintroduce a trail under an always-opaque fragment).

**Wing arcs + ellipses (F4, D-217: full cartouche).** Two mirrored instances computed in the same
fragment: a shallow bowed arc near each frame edge plus a small ellipse near its lower end, in a
slowly hue-drifting colour independent of the main figure. **D-217 (Matt, 2026-08-25): these ship
as part of the base preset, not an optional extra** — the with/without comparison in WHIT.0's
closeout was decisive.

**BUG-103 (found live at WHIT.1d-3, 2026-08-26, 2D-only): wing x-placement had to scale with
aspect.** The wings were tuned only against 16:9-family renders; at Matt's actual window
(1080×1018, aspect 1.061 — nearly square) they rendered entirely off-screen. This bug class no
longer exists post-WHIT.2b: world-space positions in the ray-march pipeline are aspect-independent
by construction (the camera's own FOV/projection handles arbitrary window sizes the same way every
other ray-march preset already does) — there is no aspect-scaling code left to get wrong.

**Three bugs found live at WHIT.1c, in the test harness or shader, never in engine source:**

1. **Unbound `chromaticMix`.** `mvWarp_fragment`'s fragment `buffer(0)` is `chromaticMix`, distinct
   from the vertex-table `FeatureVector` at the same index. Left unbound, it read undefined GPU
   memory and drove a runaway hue-zoom feedback loop. Any harness driving the warp pass by hand
   must bind it explicitly (`0.0` = identity).
2. **`FeatureVector` is not readable in a geometry fragment via a re-declared parameter.**
   `drawSceneGeometryOverlay` binds `FeatureVector`/`StemFeatures` at the vertex argument table
   only. A fragment needing per-frame scalars must receive them via the interpolated
   vertex→fragment struct or a dedicated per-preset buffer — never by re-declaring `constant
   FeatureVector& f [[buffer(0)]]` as a fragment parameter and expecting it to inherit the vertex
   binding. Getting this wrong reads as "the clock isn't working," which looks like a math bug and
   is actually a binding bug.
3. **Wing-arc beading.** A distance-to-nearest-of-N-discrete-sample-points computation (rather than
   nearest-point-on-segment) left gaps at the midpoint between samples, rendering as a dashed/
   beaded line. Fixed with a standard point-to-segment (capsule) SDF — the SAME technique
   `rosetteDist` itself was rewritten to at WHIT.2b (§6.7) once the coarse+bisect search proved
   insufficiently smooth for ray-march normals.

**Stroke quality tuning (2D-specific, superseded by real PBR lighting at WHIT.2b):** near-black
ground tuned by eye against the sRGB-encoded output (0.006 linear, not the naive 0.035); halation
width retuned from an over-generous 3-5x core-width estimate down to 1.5-2x against
`docs/VISUAL_REFERENCES/rosette/06_specular_stroke_core_halo.jpg` at a proper crop scale. Neither
constant carries into the 3D version — WHIT.2b uses real Cook-Torrance lighting, not a hand-tuned
Gaussian glow.

**BUG-104 (found live at WHIT.1d-4, 2026-08-26): the coarse+bisect search had a CORRECTNESS
defect, not just an unmeasured performance one.** Refining from only the single globally-closest
coarse sample locked the search onto whichever curve branch owned that sample and never considered
a different, ultimately-closer branch — once the epicycle self-intersects, several branches can
pass near the same query point. Visible live as literal gaps in the stroke at the tangle state and
small disconnected dots at cusps. Matt: *"Lines do not connect. The motion is all wrong."* Fixed by
finding ALL local minima among the coarse samples and bisect-refining each branch separately. This
fix's CONTINUITY property (no gaps at self-crossings) carried cleanly into the WHIT.2b 3D
conversion and is re-verified there by `test_rosette_curveIsContinuousAtHighA` — but the search
TECHNIQUE itself was later replaced entirely (§6.7) once ray-march normals exposed a smoothness
defect the flat 2D fragment never could.

### 6.10 WHIT.2c: the camera orbit was tried and removed (Matt live: "eliminate the orbit")

Matt's first live look at the completed conversion (jaggedness/perf fixes included): *"I hate it.
It's just a few objects rotating 360 degrees and moving poorly with the music. Movement of the
patterns is minimal and feels completely disconnected from the music. I dislike the rotation and
hate the way the pattern moves."* Diagnosis, from his own attached session
(`features.csv`/`stems.csv`), before any fix was attempted (per the codebase's diagnose-first
discipline):

- **The orbit itself carries zero audio information.** `scene_orbit_speed=0.12` ran at a constant
  rate regardless of the music — the single most visually dominant motion in the frame (it moves
  the ENTIRE composition every frame) had no coupling to anything Matt was hearing. This is very
  likely the direct cause of "moving poorly with the music" / "disconnected from the music" — the
  one thing his eye tracked as "the pattern moving" wasn't reading the song at all.
- **Compounding, found by replaying his actual session through the real render path**: because the
  figure AND both wing arcs all lie flat in the z=0 plane, orbiting the camera around the world
  origin periodically points it near edge-on to the ENTIRE scene at once — not just one element.
  Stills pulled from his session at several timestamps (`SessionReplayHarness`, `REPLAY_SESSION`)
  showed the whole composition flattened to a plain ring plus two thin lines at multiple points
  across the track, even though the underlying curve (verified via the same session's
  `tonal_consonance`/`harmonic_flux` values) was not actually that simple at those moments — the
  orbit was periodically HIDING real geometric complexity behind a bad viewing angle, not just
  failing to add anything.
- A second, independent finding from the same session data — **`tonal_consonance` on this specific
  track averaged 0.071 against the corpus calibration's median of 0.117 and p99 of 0.32, so 84% of
  frames sat below the point where the harmony signal even reaches half-weight against the
  audio-independent floor-drift clock** — was also surfaced but is a SEPARATE, still-open question
  (the tightness calibration's fit to real tracks), not yet decided by Matt and not addressed by
  this fix.

**Decision:** `scene_orbit_speed` removed from `Rosette.json` (reverts to the engine default,
camera-static — the same fixed position `[1.15, 1.0, -1.9]` the earlier jaggedness/perf fixes were
verified against). The generic `scene_orbit_speed` engine feature itself is NOT deleted — it is
cheap, generic camera plumbing (mirrors the already-kept `scene_dolly_speed` pattern), and the
failure mode here was Rosette-specific (an unmodulated rate against a wholly planar scene), not a
defect in the mechanism. A future preset with real out-of-plane geometry, or an audio-modulated
orbit rate, is a different case and can still use it.

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
