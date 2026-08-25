# The Whitney Program — three visual-music presets after John Whitney Sr.

**Phase ID:** `WHIT`
**Status:** SHAPED, NOT GATED. The `preset-concept` gate is **not yet cleared** — WHIT.0 exists
to clear it. Nothing below is a commitment to build; §10's ladder starts with a throwaway spike
whose deliverable is a verdict.

> **⚠ REVISED 2026-08-19 — the film has now been watched.** Matt supplied a recording of
> *Arabesque* (1975). Watching it contradicted four load-bearing inferences this document had
> drawn from Whitney's source listings: the film is a **line** film not a dot film; the symmetry
> order **holds** while the figure morphs; colour is **compositional** not indexical; and the
> composed frame is a persistent design element the doc had missed entirely. §§1, 2, 5–9 and 11
> below are rewritten against observation. The evidence and the full reconciliation are in
> [`ARABESQUE_FILM_NOTES_2026-08-19.md`](ARABESQUE_FILM_NOTES_2026-08-19.md), which is the
> **primary source** and supersedes this document wherever they disagree.
>
> Net effect: the sibling order is inverted (the closed-curve figure leads, the dot field goes
> last), the render path moves from an unexercised primitive to a proven one, and the fidelity
> risk is materially reduced.

**Working names:** **Rosette** (WHIT.A), **Frieze** (WHIT.B), **Unison** (WHIT.C). Provisional; runners-up in §8.
**Family:** `geometric` (`PresetCategory`), `rubric_profile: "lightweight"` — see §11.1.
**Lineage:** John Whitney Sr. (1917–1995) — *Permutations* (1968), *Arabesque* (1975),
*Matrix I–III* (1971–72), *Moon Drum* (1991); the theory in *Digital Harmony* (1980).
Sibling in lineage to [Ricercar](RICERCAR_DESIGN.md), which cites the Whitneys in its
visual-music ancestry but takes the painterly branch. This program takes the **mathematical**
branch, which is the one Whitney actually worked in.

---

## 0. Why this concept can clear the gate the last three candidates failed

Truchet Loom (D-194), Kinetic Sculpture (D-188) and the six prose pitches of 2026-07-21 all
died the same death: a described vision with no watched moving artifact, or a mechanic whose
motion did not match the still that sold it. The `preset-concept` skill says the concepts that
CERTIFIED were faithful ports of a specific proven moving source — Aurora Veil ← nimitz
(D-185), Nacre / Floret / Glaze ← named butterchurn presets.

Whitney is unusually well-placed against that bar, for four reasons:

1. **The source is not a description — it is published source code.** John Whitney's own
   program listings (`COLUMNBC.BAS`, `COLUMNA.BAS`, `ARABESQUE.BAS`, © 5/25/80, prepared by
   Paul Rother) survive in `github.com/jbum/Whitney-Music-Box-Examples`, alongside a
   self-contained ~60-line HTML5 Canvas port and a Processing port that renders the trails
   version. This is FA #73's "read-and-port the exact reference" in its strongest available
   form: not a Shadertoy we infer from, the artist's own code.
2. **One film has been watched, and it moved the design.** Matt supplied a recording of
   *Arabesque* (1975) on 2026-08-19; the observation notes are in
   [`ARABESQUE_FILM_NOTES_2026-08-19.md`](ARABESQUE_FILM_NOTES_2026-08-19.md). It falsified four
   inferences (see the banner above) — which is the gate working exactly as intended, before any
   code was written. *Permutations* and *Matrix III* remain unwatched (§11.4).
3. **The mechanic and the target look are the same artifact**, which is exactly what Truchet
   failed (D-195). The luminous stroke on black *is* the differential law made visible; there is
   no gap between "the mechanic" and "the reference" for a still to hide. The 2 s-interval
   sequence (`rosette_build.png`) confirms this in motion rather than in stills.
4. **The musical claim is Whitney's own thesis, and Phosphene already computes the signal.**
   *Digital Harmony*'s argument is that visual consonance and musical consonance are the same
   phenomenon — whole-number ratios. TONAL (D-178) shipped a continuous harmonic-state vector
   in 2026-07-10, calibrated over a 1000-track pilot, and today only three presets read it as a
   hue. This program is the first concept that would consume it **as structure**.

**What this section does NOT claim.** It does not claim the concept has passed. Against the
`preset-concept` skill's four artifacts:

| Artifact | Status |
|---|---|
| 1 — a watched moving source | ✅ *Arabesque*, watched 2026-08-19, notes committed |
| 2 — the look verified in motion, not a cherry-picked frame | ✅ two 2 s-interval sequences; the macro sheets alone would have mis-specified it as shot-based |
| 3 — a three-sentence checkable story | ✅ §1 (Music), §2 (Move), §8 WHIT.A (See) |
| 4 — a running look-spike Matt has seen | ❌ **does not exist. That is WHIT.0.** |

---

## 1. Musical role (the one-sentence rule)

> **When the music's harmony settles, the drawn figure tightens into a crisp closed emblem;
> when it moves or turns atonal, the emblem unravels into open arcs — so a chord resolving is
> the moment the drawing snaps into focus.**

The named musical feature is **harmonic consonance and its motion** (`tonalConsonance`,
`tonalPhaseFifths`, `harmonicFlux` — D-178). The named visual behaviour is **the figure closing
and tightening** — the film's own central move, observed across a continuous 30 s passage
(`rosette_build.png`): loose tangle → petals → star inside a ring → **straight-edged pentagon**
→ back out to tangle, all at constant 5-fold symmetry.

**This replaces the original claim** ("the points collapse onto q rays"). The ray-collapse is
real arithmetic (§4) but it is not what *Arabesque* does, and it degrades badly: a point cloud in
the dissonant regime is visual hash, whereas an unravelled line figure is still a drawing. The
revised behaviour keeps the picture legible across the whole harmonic range, which is the
difference between a preset that works on classical and one that works on everything.

Continuous energy remains the **primary driver** per CLAUDE.md §Audio Data Hierarchy. Energy
governs presence — how bright, how large, how fast the figure winds. Harmony governs the
*figure*. The distinction matters and §7 keeps it clean: a preset whose only life came from a
20-second harmonic signal would feel unlocked from the music, which is failure mode #1.

---

## 2. Temporal contract (behaviour over time, not a still)

Over a ~45 s scene:

| Window | What happens |
|---|---|
| 0–4 s | Cold start. Consonance's slow centre is unestablished (TONAL.1's characterization finding: tension's 20 s slow-centre cold-starts). The figure enters mid-morph in its **open, loose** state and stays loose. No accents fire. |
| 4 s onward | The morph runs at constant rate. Whitney's motion is servo-driven and never eased (§9.4) — the film shows no ramp-in, no settle, no ease anywhere. |
| On a vamp | Harmony holds → the morph parameter holds → **the figure holds its character.** This is the Nacre round-2 lesson applied structurally (§5.3): if a free clock also drives the morph, the clock wins and the harmony is invisible. |
| On a resolution | Consonance rises → the figure **closes and tightens**: arcs join, the circumscribing ring forms, edges straighten toward the polygon. **This is the preset's headline event.** |
| On a chord change | `harmonicFlux` spikes → the symmetry order **steps** (5-fold → 6-fold → 4-fold). Observed in the film as a discrete change between passages, not a continuous drift. |
| On a modulation | The circle-of-fifths phase migrates → the figure glides along the morph family, over seconds, never jumping. |
| Percussion / noise / atonal | Consonance falls under its gate → the emblem unravels into loose open arcs. **Still a drawing** — this is the graceful-degradation property the line figure has and the dot field does not (§1). |
| Silence | The morph continues at its floor rate; brightness falls to the D-037 non-black floor. The figure never leaves the screen — across a full 30 s passage the film's figure never blanks, resets or restarts. |

**Anti-contract:** the figure must never strobe, and the symmetry order must never flicker.
Consonance is a slow signal. In the film the order holds for tens of seconds at a time; anything
that steps it at beat rate is a defect, not a feature (§9.3, §11.2).

---

## 3. Three-part bar (`PRESET_SESSION_CHECKLIST` Part 2)

| Bar | Verdict | Evidence |
|---|---|---|
| **Iconic visual subject deliverable at fidelity** | **PASS — upgraded 2026-08-19 on the film evidence.** | The subject is a single thin bright closed stroke with soft halation on near-black. No material, no lighting, no detail cascade to fail — the fidelity gaps Matt has flagged before (lumpy-vs-mountainous, chrome-as-putty) live in *rendered surfaces*, and this has none. The thinness worry that kept this at PROVISIONAL is answered by the film itself: its sparsest frames are a single arc on black and they are excellent (`ARABESQUE_FILM_NOTES` §2, character C). **What must be delivered is stroke quality** — bright core, controlled halation, decisive curvature — which is `rgba16Float` + bloom, a shipped capability. |
| **Clear musical role** | **PASS** | §1. Names a specific feature (`tonalConsonance` / `harmonicFlux`) and a specific behaviour (the figure closing and tightening). Not "reacts to energy". |
| **Infrastructure-feasible** | **PASS — verified, not assumed** | Zero engine touch required. §6 cites the file:line evidence for every claim. |

---

## 4. The mechanic — differential dynamics

Whitney called it **incremental drift**, later **differential dynamics**: give element *i* a
rate of change proportional to *i*.

> "if one element were set to move at a given rate, the next element might be moved two times
> that rate. Then the third would move at three times that rate and so on."
> — *Digital Harmony*, p. 38

His own published listing (`COLUMNBC.BAS`) is four lines:

```
A := 360 * STEP * POINT
X := XCENTER + cos(A°) * (POINT/NPOINTS) * RADIUS
Y := YCENTER + sin(A°) * (POINT/NPOINTS) * RADIUS
```

i.e. θᵢ = 2π·i·f(t), rᵢ = R·i/N, with `NPOINTS` = 60 and the cycle fraction f advancing
linearly.

**The structural fact worth internalising.** Eliminating *i* between θᵢ = i·φ and rᵢ = (R/N)i
gives

> **r = R·θ / (N·φ)** — a single Archimedean spiral of pitch R/(Nφ), sampled at N points.

Every figure Whitney's films produce — spirals, stars, roses, scatter — is one Archimedean
spiral whose angular pitch tightens linearly with time, sampled at N points. Nothing else is
happening. That is why the look is coherent across ten minutes of film with no authoring.

**The resonance theorem (the thing this program is built on).** Let f = p/q in lowest terms.
Then θᵢ = 2π·i·p/q takes **exactly q distinct values**, equally spaced by 2π/q, because
gcd(p,q)=1 makes i·p mod q hit every residue. The N points therefore collapse onto **q evenly
spaced rays**, N/q points per ray, radial spacing q·R/N along each ray.

- Small q → few, thick, widely separated arms. Whitney's **consonance**.
- Large q or irrational f → quasi-uniform spread, reads as scatter. Whitney's **dissonance**.

Whitney described exactly this, watching *Permutations*:

> "the points seem to be scattered around in a circular area randomly at one moment. But at
> certain moments they all seem to fall in line to make up some simple rose curve, symmetrical
> figure; sometimes it is a three lobed figure, or ten or four or two lobed figure." … order
> occurs when "all the numerical values of the equation reach some integer or whole number set
> of ratios."

**This was verified empirically during shaping**, not taken on faith: rendering N=48 at
f = 0, 1/2, 1/3, 2/3, 1/4, 1/5, 1/7, 3/8, 1/12 produced exactly 1, 2, 3, 3, 4, 5, 7, 8, 12
rays respectively; f = 0.618 produced phyllotaxis-like scatter with no rays; f ∈ [0.01, 0.05]
produced a clean Archimedean spiral.

---

## 5. The harmony coupling — the design centre

### 5.1 The mapping

Revised 2026-08-19 against the film. The axis that moves is **tightness**, not arm count (F2).

| Whitney's term | Phosphene primitive | Visual consequence |
|---|---|---|
| Consonance | `tonalConsonance` | **how tight and closed the figure is** — loose open tangle ↔ crisp closed emblem with straight edges. The film's central move. |
| Where in the harmonic sweep the figure sits | `tonalPhaseFifths` | **where in the morph family** — which of petals / star / ring / polygon the figure currently reads as |
| Cadence / resolution | `harmonicFlux` | **steps the symmetry order** (5-fold → 6-fold → 4-fold) at a chord change. Discrete, held for tens of seconds — never per-beat. |
| — (not Whitney) | `bassDev` / `midAttRel` | presence: stroke brightness and halation width; the morph's floor rate |

**The colour rule is a separate finding and it is not negotiable to the look (F3).** The figure
is **white / pale lavender**; saturated hue lives in the mirrored frame elements at the edges
(§8, F4). Do **not** apply `hue = 360·(i+1)/N` across the figure — that is the Whitney *Music
Box* convention, not *Arabesque*, and it reads as a modern generative-art demo rather than as the
film. Formula-appendix F8 is retained for the dot field (WHIT.C) only.

`tonalPhaseThirds` and `tonalTension` are deliberately **unrouted at WHIT.1** (FA #67 — one
primitive per layer; Nacre shipped two tonal routes and deferred tension for exactly this
reason). They are candidates for a later uplift, not launch scope.

### 5.2 Calibration — measured, not guessed

TONAL.2b ran the full 1000-track stratified pilot (2.66 M frames, 0 unreadable) and produced
the numbers this coupling must be built against. **Do not map any tonal primitive from [0, 1].**

| Primitive | Analyzer floor | Corpus median | p99 (soft-saturate here) | Genre spread |
|---|---|---|---|---|
| `tonalConsonance` | 0.05 (atonal floor, width 0.03) | 0.117 | **0.32** | classical 0.180 > jazz 0.140 > … > rock 0.108 > hiphop 0.101 |
| `tonalTension` | — | — | **0.163** | classical highest (0.045) |
| `harmonicFlux` | — | — | **0.110** | — |

**Consequence for the coherence mapping.** The usable consonance band is roughly [0.05, 0.32],
and half the corpus sits below 0.117. If coherence is mapped linearly across that band, the
median track spends most of its time near-scattered and the crystallization event never lands
on rock or hip-hop. The mapping must be **shaped so the corpus median lands mid-range**, and
WHIT.1 must state the curve it used and why. This is the single most likely place for the
coupling to read as dead.

### 5.3 The Nacre lesson, applied structurally

TONAL.3 round 1 read to Matt as "not sure if it worked". The session data proved the coupling
was *active* — fifths swept the full range, consonance mean 0.107 above the gate — but
**masked**: `palette = time + offset` let the clock rotate ~13.7 palette cycles per song against
harmony's ±0.5. Round 2 made harmony **set** the position and demoted the clock, and Matt
signed off.

The same trap is available here and is worse, because Whitney's sweep is *natively* a free
linear clock. If the sweep is `f = t/T + harmony`, the clock wins and this is just a pretty
rotating spiral with a tonal tint.

**Therefore: harmony SETS the sweep position; the free clock is demoted to a slow floor drift
that stops when the signal is tonal and restores at silence.** This is a design constraint, not
a tuning knob, and it is the first thing to check if WHIT.1's M7 reads as "not sure if it
worked."

---

## 6. Port plan onto Phosphene — zero engine touch

Every claim below carries its evidence. Verified 2026-08-19 against the working tree.

**Revised 2026-08-19.** The film is a line film (F1), so the lead preset draws a **stroke**, not
a point cloud — which moves it onto the *proven* path and retires this section's one risk item.

| Requirement | Mechanism | Evidence |
|---|---|---|
| **The closed figure, drawn as one continuous stroke** | `marks` block, `"primitive": "line_strip"`, `vertex_count: ~1536`, `instance_count: 1` — **Dragon Bloom's exact shipped configuration** | `DragonBloom.json:19–26` (1536 / 3 / `line_strip`); D-138; the geometry pipeline resolves per-prefix in `PresetLoader.makeSceneGeometryPipeline` |
| The luminous stroke (bright core + halation) | HDR feedback + `PostProcessChain` bloom | `feedback_pixel_format: "rgba16Float"`, SHADER_CRAFT §17 — the "one modern layer" (§11.1), and period-honest: halation is what filming a vector CRT produces |
| The composed frame — mirrored edge arcs (F4) | a second `instance_count` of the same overlay, or a second low-vertex strip | Dragon Bloom already draws 3 instances of its strand overlay; the wings are the same mechanism at low vertex count |
| Canvas behaviour | **canvas-hold or light decay, not long trails** — the film draws the figure complete each frame (F1, notes §4) | Skein's canvas-hold is `SkeinCanvasHoldTest`-proven (Hamming-0 across 130 frames); D-142 |
| **Per-frame, audio-driven trail decay** | `mvWarpPerFrame(constant FeatureVector& f, …)` returns `pf.decay`; the shared warp fragment resolves `decayMul = (chromaticMix > 0) ? 1.0 : in.decay` | `PresetLoader+WarpPreamble.swift:83, 127, 213`; `Skein.metal:771–785` |
| Dot *i* computed entirely in the vertex stage | the overlay vertex signature is `(uint vid [[vertex_id]], constant FeatureVector& f [[buffer(0)]])` — so with `vertex_count: N` and `primitive: "point"`, `vid` **is** the harmonic index *i* and `f` carries the clock and the audio. No per-preset buffer, no CPU geometry, no engine touch. | `Skein.metal:309–320` (`skein_geometry_vertex`); bound by `drawSceneGeometryOverlay` vertex slot 0; Skein.1/Skein.2 path A, D-143 |
| Black ground | `marks.canvas_clear: [0, 0, 0]` (the default) | Skein.ENGINE.1.1, D-143 |
| HDR headroom for bloom | `feedback_pixel_format: "rgba16Float"` | SHADER_CRAFT §17; **safe only for decay-bounded feedback** — ours is (decay ≤ 0.92, §9.2), so it qualifies, unlike the faithful no-decay warps |

**D-037 (silence-non-black) — satisfied, but state why.** Ricercar had to decay its feedback
field toward a *light* ground because `prev × decay` toward black fails silence-non-black at
rest. That reasoning does **not** transfer here: Whitney's sweep never stops, so the dots are
re-drawn every frame regardless of audio and the frame is never black. The black canvas is
legitimate — but a downstream session reading only the Ricercar precedent will flag it, so the
design doc must say this out loud and the silence test must assert a non-black frame at zero
input.

**Paradigm:** `mv_warp`. The multi-frame harness template to copy-adapt is
`AuroraVeilMVWarpAccumulationTest` (QG.4, D-182) — **written or extended before any shader
work**, per `PRESET_SESSION_CHECKLIST` Part 2.

**The `"point"` risk is deferred, not resolved.** No shipped preset uses `"point"`; the plumbing
is present on all three surfaces (`PresetDescriptor.swift:135`, `VisualizerEngine+Presets.swift:22`,
`MultiPassRenderHarness.swift:690`) but "present" is not "exercised" (cf. RMENV.2/.3 — supported
with zero consumers until D-213 scheduled them for deletion). Because the lead preset is now a
line figure, **this risk moves to WHIT.C** and does not gate the program. When the dot field is
built, two specifics must be verified rather than assumed: that the vertex stage can write a
usable `[[point_size]]` range, and that `[[point_coord]]` yields a soft round dot rather than a
hard square. If either fails the fallback is instanced quads — a different `marks` block, not a
different concept.

---

## 7. Audio-routing table (FA #67 audit — one primitive per layer)

Proposed `audio_routes` manifest for WHIT.1 (Unison). **Audit before declaring** — QG.1: a
declared route the code doesn't read is as wrong as an unread route left undeclared.

| `route` | `primitive` | `kind` | What a viewer sees |
|---|---|---|---|
| `figure_tightness` | `tonalConsonance` | continuous | the emblem closing and straightening vs unravelling into open arcs |
| `morph_position` | `tonalPhaseFifths` | continuous | which member of the family is on screen — petals / star / ring / polygon |
| `symmetry_order_step` | `harmonicFlux` | accent | the arm count stepping at a chord change |
| `stroke_presence` | `bassDev` | continuous | stroke brightness and halation swelling with the music |
| `morph_floor_rate` | `midAttRel` | continuous | how fast the figure keeps changing when harmony is holding |

Five routes, five distinct primitives, no double-drive. Deviation primitives throughout — never
absolute thresholds on AGC-normalised values (FA #31, D-026).

**Known coverage risk.** `harmonicFlux` may under-develop on 30 s preview fixtures, which is
exactly what forced Nacre to defer `tonalTension` at TONAL.3. If `RouteCoverageTests` shows it
red, that is a **fixture-breadth defect to file in `KNOWN_ISSUES.md`, not a floor to tune**
(QG.1: a red route is the gate working).

---

## 8. The three siblings

D-097 is explicit: **siblings, not subclasses.** These are three different Whitney mechanisms,
not one engine with three configs. Nothing shared is extracted until a second preset needs it
and has shipped — and "reusable infrastructure" is never a defence for keeping code
(CLAUDE.md §Authoring Discipline).

### WHIT.A — **Rosette** (the morphing emblem) — **build first**

*Runners-up: Cartouche, Emblem, Quatrefoil.*

**The film's headline image** (`ARABESQUE_FILM_NOTES` §2, character A; evidence
`rosette_build.png`). A single closed luminous curve with n-fold symmetry, morphing continuously
through tangle → petals → star-in-a-ring → straight-edged polygon → back out. Thin bright
white-to-pale-lavender stroke, soft halation, near-black ground with a faint blue-violet
vignette, and **mirrored coloured arcs at the left and right frame edges** carrying the hue.

**Promoted from last to first.** The original draft had this as WHIT.C and flagged it as the
sibling most likely to fail its own gate, on the theory that stills would look like ordinary star
polygons. **The film falsifies that.** The stills are beautiful *and* the motion is the morph —
so the Truchet failure shape (D-194/D-195, where a still sold a look the motion did not deliver)
does not apply here. It is also the sibling that lands on the proven `line_strip` path (§6) and
the one whose dissonant-regime behaviour stays legible (§1).

Closed-curve form: F13 (Fourier/epicycle, `z(t) = Σ aₖe^{i(kω₀t+φₖ)}`) generates exactly this
family — a small number of harmonic terms whose relative amplitudes and phases carry the morph,
with the dominant term setting the symmetry order.

### WHIT.B — **Frieze** (the tiled ornamental band)

*Runners-up: Meander, Cartouche, Fret.*

The modulo-wrap section of `ARABESQUE.BAS`, correctly characterised at last (`FILM_NOTES` §2,
character B; evidence `dot_band.png`). A horizontally repeating band of ~5 identical cells, each
holding vertical ellipses and rings built from **dotted / beaded curves** in saturated yellow,
orange, magenta, cyan and white. Layered — faint dotted background lattice, mid-layer outlines,
bright foreground rings with bloom. Occupies the middle ~60 % of frame height; top and bottom
stay dark. Across the sequence the cells **breathe** (tall thin ellipses widening toward circles)
and the repeat phase drifts horizontally.

⚠ **The original description of this sibling was wrong.** The doc said "the circle shears into
diagonal strands, wraps, and periodically reforms into a circle." That is what the arithmetic
does; what the *screen* shows is an ornamental **frieze** — a border repeat, which is Whitney's
stated Islamic-ornament motivation showing up directly. Build toward the frieze, not the shear.

Still port from the Pascal, not the Processing: `whitney_arabesque.pde` writes
`cos(a*deg) * ratio` where the original has `COS(A*DEG) * RADIUS`.

Formula: F7.

### WHIT.C — **Unison** (the differential dot field) — **last, and least evidenced**

*Runners-up: Cadence, Consort, Tine.*

The canonical polar figure: θᵢ = 2π(i+1)·f(t), rᵢ = R(N−i)/N (F2). Points on black, trails from
feedback decay, arm count from the harmony. Port targets `html5/whitney_canvas.html` and
`processing/visuals_only/whitney_blur`.

**Demoted from first to last, and it now carries the program's open risks:** it is the sibling
*Arabesque* gives the least evidence for (this character is most associated with *Permutations*,
which nobody has watched — §11.4); it is the one needing the unexercised `"point"` primitive
(§6); and it is the one the §9.2 trail/legibility conflict actually constrains (§9.2 note).
**Its own concept gate should be *Permutations*, watched, not this document.**

**Convention note if it is built.** Whitney's own listing puts the *fastest* point outermost
(r ∝ i, θ ∝ i); Bumgardner's Music Box inverts it so the **fundamental** is outermost. The Music
Box convention is the musically legible one. Do not mix the two mid-file, and do not import a
line from `IMAGINARY/whitney`, which uses the other one.

---

## 9. Four hard constraints, discovered by running the math

These were derived and then verified numerically during shaping. None of them appear in any
published source; §13's references will not warn you.

**Scope note (2026-08-19).** §9.1 and §9.2 are properties of the **dot field**. With WHIT.C
demoted to last, they constrain that sibling rather than the program's architecture. §9.3 and
§9.4 apply to all three.

### 9.1 Temporal aliasing bounds N

The fastest element advances Δθ = 2πN·Δt/T per frame. Nyquist needs Δθ < π; avoiding visible
counter-rotation needs Δθ < π/2. So:

> **N < T · fps / 4**

At 60 fps with a 180 s cycle, N up to ~2700 is safe. But if the sweep is ever accelerated —
by energy, by tempo, by a flux kick — T falls and the bound bites. **Clamp N against the
instantaneous sweep rate, not against the nominal cycle.**

### 9.2 Trails and resonance legibility are in direct conflict — and the relation is quantified

**Applies to WHIT.C (the dot field) only — see the scope note above.** *Arabesque* does not
operate in this regime at all: the film draws its figure complete every frame and the glow is
**halation around a stroke**, not a decaying comet-tail (`FILM_NOTES` §4). For a line figure the
equivalent question is stroke glow, which is bloom on a bright core — no accumulation buffer,
none of this conflict. The relation below is still true; it simply stopped driving the
architecture when the lead preset changed.

A first trail test at decay 0.80 with a fast sweep **completely destroyed** the 3-armed star:
the accumulation filled the annulus into a featureless disc. Re-running across six decay values
at a slow approach showed the star stays crisp with attractive comet-tails up to decay ≈ 0.65,
softens at 0.80, and blows out to a filled white-cored disc at 0.92.

The governing relation, validated in both regimes:

> **(1 − decay) ≳ q · N · Δf**
>
> where Δf = cycle-fraction advance per frame, N = element count, q = the lowest-order
> resonance you want to stay legible.

Check: crisp case q=3, N=48, Δf=5.1e-4 → RHS 0.073, and blowout appeared exactly at
1−decay = 0.08 (decay 0.92). Smeared case Δf=6.7e-3 → RHS 0.96 ≫ 1−decay = 0.20, total smear.
Both predicted correctly.

**Design consequence, and it is counter-intuitive:** trail length cannot be a constant. When the
sweep speeds up, the trail must **shorten** proportionally, or every consonance event vanishes
at exactly the moment it should read. The instinct "faster music → longer trails" is backwards
here. `mvWarpPerFrame` can compute decay per frame from `FeatureVector`
(`PresetLoader+WarpPreamble.swift:83, 127, 213`; `Skein.metal:771–785`), so this is implementable
without an engine change — but it must be *designed in* from the dot field's first increment, not
discovered at M7.

### 9.3 Strobing peaks at exactly the moment you want

Consonant moments are the moments of maximum spatial coherence, so quantization and
rasterization artefacts peak there. Temporal accumulation is both the historically authentic
look and the fix. **Photosensitivity consequence:** the crystallization event concentrates the
same emitted light into fewer pixels, which is a luminance event. Total emitted luminance must
be held roughly constant across the event — as elements concentrate, dim them.
`PhotosensitivityCertificationTests.multiPassMeasured` + a render function in
`MultiPassFlashHarnessTests` are certification gates for multi-pass presets, and this preset
should be measured **early**, not at certification.

### 9.4 Do not ease, and beware fp32 phase

Whitney's motion is servo-driven at constant rate. Any keyframe easing reads immediately as
wrong. Separately: θᵢ = 2π·i·t/T with T = 180 s and i = 400 puts the argument to `sin` in the
10⁵–10⁶ range by end of cycle; fp32 `sin` loses phase accuracy and the resonances smear. **Keep
the phase wrapped** — accumulate `fract(i·t/T)` and multiply by 2π at the last moment.

**Escaping mechanical repetition without destroying the harmony**, in ascending order of damage:
(a) advance the sweep non-linearly — Whitney himself interpolated `STEP` between `STEPSTART`
and `STEPEND` so no two cycles are identical; (b) put an independent differential on radius as
well as angle — this is literally what his Whitney-Reed **RDTD** (*Radius Differential / Theta
Differential*) system was named for; (c) detune one element by ε, so resonances still occur but
drift slowly in phase — a visual beat-frequency, harmless while ε ≲ 1/(N·cycles).

In this program, **the harmony coupling is the variation** — which is the whole point, and why
(a)–(c) should be held in reserve rather than spent up front.

---

## 10. The increment ladder

Infra lands before dependents and is never bundled. Each rung's deliverable is stated in terms
of what exists afterward that does not now.

| ID | Deliverable | Gate |
|---|---|---|
| **WHIT.0** | **Look spike, throwaway.** The closed-curve figure ported minimally to a running `line_strip` overlay on the mv_warp marks-on-top path; `motion_gate.sh` run; the morph and the stroke quality answered with frames. **No sidecar, no registration, preset count unchanged.** | Matt's go / re-scope. The verdict is the deliverable; the code may be discarded. Prompt: `docs/prompts/WHIT0_LOOK_SPIKE.md` |
| **WHIT.1a** | Reference set curated: `docs/VISUAL_REFERENCES/rosette/` per `_NAMING_CONVENTION.md`, cropped from the *Arabesque* recording (the `_incoming/frames/` sheets are the raw material), with provenance rows. Lightweight template. | `CheckVisualReferences --strict` clean. **Blocks WHIT.1b** — D-064, references locked before authoring. |
| **WHIT.1b** | Design doc `docs/presets/ROSETTE_DESIGN.md` + the multi-frame harness adapted from `AuroraVeilMVWarpAccumulationTest`, green, **before any shader work**. | Harness proves the live scene → warp → compose → swap path is reachable from a test. |
| **WHIT.1c** | Rosette lands in-repo: `.metal` + sidecar, `certified: false`, faithful base — the morphing figure, the white stroke, the coloured frame elements. **No audio coupling yet.** | `compare_render.sh` verdict table + `motion_gate.sh` verdict, both written into the transcript. |
| **WHIT.1d** | The harmony coupling (§5) + HDR bloom on the stroke. Route manifest declared after auditing the code. | `RouteCoverageTests` green on all five routes, or a filed defect. Flash measured. |
| **WHIT.1e** | Rosette certification: Matt's live M7 on real music, `certified: true`, rubric row, flash harness row, `OrchestratorCertifiedFilterTests`. | Matt. Two M7 rounds max before re-scope (the **PHYS escalation rule**; D-102 precedent, in `DECISIONS_HISTORY.md`). |
| **WHIT.2** | **Frieze**, as its own concept-gate → design → build → certify ladder. Scoped only after WHIT.1e. | — |
| **WHIT.3** | **Unison**, same — and its concept gate is *Permutations* watched, not this document (§8). First to cut if the program runs long. | — |

**Sequencing note.** WHIT.2 is not scoped in this document on purpose. Scoping it now would be a
strategy commitment drafted without empirical input from the work it governs — which
CLAUDE.md §Authoring Discipline names as a stop-and-surface trigger. What Unison's M7 teaches
about whether the harmony coupling *reads* determines whether the siblings are worth building
at all.

---

## 11. Risks and honest constraints

### 11.1 The fidelity floor does not fit, and that is a decision, not an oversight

Whitney's look is austere by design: coloured dots on black, no materials, no lighting, no
noise octaves. `SHADER_CRAFT`'s full rubric — detail cascade, ≥4 noise octaves, ≥3 materials,
pale-tone ≤ 30 % — cannot be met and should not be attempted. The sidecar declares
`rubric_profile: "lightweight"`, the 4-item ladder used by Plasma, Waveform, Nebula and
SpectralCartograph, and `docs/VISUAL_REFERENCES/unison/` copies `README_LIGHTWEIGHT.md`.

Matt's call (2026-08-19): **faithful core, one modern layer.** The modern layer is **HDR bloom
on the accumulation buffer** (`feedback_pixel_format: "rgba16Float"` + `PostProcessChain`),
which is period-honest as well as modern — filming a vector CRT is what produced Whitney's
halation in the first place — plus optional subtle grain on the composite. Explicitly
subordinate: if the bloom starts carrying the image, it has gone too far.

**The thinness worry is largely answered by the film (2026-08-19).** *Arabesque*'s sparsest
frames are a single glowing arc on black, and they are excellent (`FILM_NOTES` §2, character C).
Sparseness was Whitney's repeated choice, not a budget he was stuck with. What makes those frames
work is **stroke quality** — bright core, controlled halation, decisive curvature — plus the
composed frame (F4). Those are the two things WHIT.0 must actually prove; "add more elements" is
the wrong response to a thin-looking spike and would move the preset away from the reference.

### 11.2 The harmony signal has known defects, inherited

`ChromaExtractor` floors at `minFrequency = 500 Hz` (≈B4) by design — 46.875 Hz bin spacing
causes systematic pitch-class bias below that. Consequences carried into this program:
root/bass-line harmony is **invisible** to TIV, and the CENSUS.3 35 % F#-minor bias may bias
`tonalPhaseFifths`'s absolute offset. TONAL's own argument is that *relationships* (modulation
Δ, flux) survive a systematic per-PC bias even where absolute key does not — and relationships
are what this program consumes. **Unproven, and flagged as the primary validation risk**, same
as it was for TONAL.

### 11.3 Beat-irregular and reactive-mode tracks

This preset does not read the beat grid at all, so `requires_regular_beat` stays `false` and
D-154 does not apply. That is a genuine advantage over the beat-locked presets — but it also
means the preset has **no rhythmic accent whatsoever** unless §7's energy routes carry it. Watch
for "beautiful but floaty" at M7.

### 11.4 What nobody has verified

Updated 2026-08-19. Stated plainly so no downstream session inherits it as fact.

**Resolved**

- *Arabesque* has been watched end to end and reconciled against this document
  (`ARABESQUE_FILM_NOTES_2026-08-19.md`). Four inferences were falsified; the design changed.
- The `"point"`-primitive risk no longer gates the program — it moves to WHIT.C (§6).

**Still open**

- ***Permutations* (1968) and *Matrix III* (1972) are still unwatched.** The dot-field character
  is most associated with *Permutations*, so **WHIT.C cannot open without it.** Both are on
  archive.org (§13) and both are now the cheap next step, since the extraction workflow exists.
- **Colour fidelity of the source recording.** It is a YouTube capture of a 1975 film — two
  unknown encode chains. Stroke width, composition and motion are trustworthy; exact chroma is
  not. Curate WHIT.1a's references accordingly and do not eyedropper a palette from these frames.
- Whether *Arabesque*'s three on-screen characters are three programs or one program under
  different parameter sets is not determinable from the film.
- **Shadertoy was unreachable** during shaping (egress 403 + target 403). Several plausible IDs
  surfaced from a search index and are deliberately omitted from §13 rather than cited unverified.
- **whitneymusicbox.org is probably dead** — the site describes the animation as "programmed in
  Processing", i.e. a Java applet. Use the HTML5 file from the GitHub repo, which is plain
  Canvas 2D.
- Per-film generator specifics for *Matrix I/II/III* are **not documented** in any accessible
  source; the differential-law assumption for those films is inference.

---

## 12. DECISION-NEEDED

Revised 2026-08-19 — the old #1 ("how many dots?") is obsolete now that the lead preset draws a
stroke rather than a point cloud.

**#1 — How ornate should the frame be?**

*Arabesque* never shows a bare figure. There is always a border — mirrored coloured arcs at the
left and right edges, sometimes top and bottom too, each carrying a small ellipse. It is most of
what separates "a picture" from "a parametric plot," and it is the cheapest thing in the program
to build.

- **A — full cartouche.** Mirrored arcs left and right, carrying the saturated hue, animated on
  their own slower clock. Closest to the film. The frame becomes part of the composition.
- **B — figure only.** Just the central emblem on black. Cleaner, more modern, more obviously
  Phosphene's own. Risks reading as a plot rather than as a drawing.
- **C — cartouche that responds.** The frame elements carry the harmony colour while the central
  figure carries the shape, so the two halves of the coupling are visually separated.

**Recommendation: A for WHIT.0, and evaluate C at WHIT.1d.** Prove the film's composition first;
earn the extra coupling afterwards. **Default if no reply: A.**

---

**#2 — What happens when the music is unharmonic?**

Half the corpus sits below the consonance median (§5.2); on a hip-hop or noise-rock track this
preset spends most of its time in the loose regime.

**This got materially less risky.** The old answer was "a point cloud scatters into hash." The
new answer is "the emblem unravels into loose open arcs" — which is still a drawing, and which
*Arabesque* itself spends a lot of screen time on. The remaining question is only whether the
loose state carries a whole track.

- **A — loose is the honest answer.** The figure stays open and wandering. Truthful to the signal
  and defensible on the film's evidence.
- **B — floor the tightness.** Below the gate the figure still periodically closes on a slow
  internal clock, so every track gets emblem moments — just unearned ones.
- **C — hand the drive to energy below the gate.** When harmony goes quiet, band energy takes
  over the tightness, so a beat-driven track gets a beat-driven figure and a harmonic track gets
  a harmonic one.

**Recommendation: C**, unchanged. It keeps the honest coupling where the signal exists and lets
the Orchestrator schedule this on any track rather than only at the classical and jazz end.
**Default if no reply: C.**

---

**#3 — Preset names.**

Now **Rosette** / **Frieze** / **Unison**. Rosette is the rose curve and the rosette window —
accurate to what is on screen. Frieze is the ornamental border repeat, which is exactly what the
modulo-wrap section reads as, and it fits the Phosphene one-evocative-word register (Skein,
Nacre, Floret, Glaze, Stave, Meniscus). Runners-up: **Meander**, **Cartouche**, **Fret** for
Frieze; **Emblem**, **Quatrefoil** for Rosette.

*Arabesque* is no longer proposed as a preset name — it is the film, and using it for one sibling
would misattribute the other two, which come from the same film.

**Recommendation: keep all three. Default if no reply: keep, and settle at WHIT.1a.**

---

## 13. References

**Whitney's own code and words** *(the port sources — FA #73)*

- [`github.com/jbum/Whitney-Music-Box-Examples`](https://github.com/jbum/Whitney-Music-Box-Examples)
  — `basic/COLUMNBC.BAS`, `basic/COLUMNA.BAS`, `basic/ARABESQUE.BAS` (Whitney's own listings,
  © 5/25/80, prepared by Paul Rother, transcribed 2011); `html5/whitney_canvas.html` (**the
  primary port target**); `processing/visuals_only/whitney_blur/` (**the trails version**);
  `processing/visuals_only/whitney_2/` (400 points — ⚠ its stills are prettier than its motion,
  see below)
- [John Whitney, *Digital Harmony* (1980), full text](https://archive.org/stream/DigitalHarmony_201611/Digital%20Harmony_djvu.txt)
- [John Whitney, "Notes on Permutations", *Film Culture* 53-55 (1972)](https://www.centerforvisualmusic.org/WhitneyNotesPerm.htm)

**The primary source — watched**

- ***Arabesque* (1975)** — Matt's screen recording, 2026-08-19, 6:19 @ 1970x1470/60 fps.
  Observation notes: [`ARABESQUE_FILM_NOTES_2026-08-19.md`](ARABESQUE_FILM_NOTES_2026-08-19.md).
  Evidence frames: `docs/VISUAL_REFERENCES/_incoming/frames/` - `sheet_1.png`, `sheet_2.png`
  (10 s macro sweep), `rosette_build.png` (2 s, the morph), `dot_band.png` (2 s, the frieze).
  WARNING: the 1.5 GB `.mov` sits in `_incoming/` and must be **gitignored or LFS'd**, never
  committed to git directly (LFS.2/LFS.3, D-211 - reference and diagnostic images left git for
  exactly this reason).

**The other films** *(existence + runtime verified; on-screen motion NOT verified - §11.4)*

- *Permutations* (1968), 7:54 — `archive.org/details/john-whitney-permutations-1968`
- *Matrix III* (1972), 10:34 — `archive.org/details/john-whitney-matrix-iii-1972`
- *Moon Drum* (1991) — `archive.org/details/JohnWhitneyMoonDrum1991` (⚠ page runtime of 99 min
  is suspect; the film is normally cited at ~23 min — likely a compilation or bad metadata)
- *Arabesque* (1975), 7 min — `alternativeprojections.com/films/arabesque/` (info page only,
  not a viewable copy)

**Secondary implementations**

- [`github.com/IMAGINARY/whitney`](https://github.com/IMAGINARY/whitney) — ES6 + paper.js museum
  exhibit; `?showLines=1` is the **WHIT.C reference**. Uses Whitney's original
  fastest-point-outermost convention (§8).
- [Jim Bumgardner, "The Whitney Music Box", Bridges 2009](https://archive.bridgesmathart.org/2009/bridges2009-303.pdf)
  · [author's copy](https://jbum.com/papers/whitney_paper.pdf)
- [`github.com/keijiro/KinoSlitscan`](https://github.com/keijiro/KinoSlitscan) — the readable
  slit-scan implementation, if *Catalog*'s slit-scan ever becomes a fourth sibling. Its lesson
  is the cost model: ~300 MiB VRAM at 1080p for frame history, mitigated by YCgCo packing.

**Motion-vs-still flags** *(the Truchet check, D-195)*

- `whitney_blur` — motion is the whole point; a still is just a smear. **Safe anchor.**
- `whitney_2` — ⚠ **still is prettier than the motion.** The `len *= sin(a·timer)` modulation
  makes gorgeous frozen frames but the animation pulses in a way that fights the harmonic
  reading. Do not anchor on it.
- `IMAGINARY ?showLines=1` — motion-dependent; stills are ordinary star polygons (§8).
- Music Box var. 0 — motion-dependent, **and the audio is load-bearing**: muted, it reads as a
  rotating rainbow spiral. Worth knowing, because Phosphene supplies different audio.

**Biography / theory**

- [William Moritz, "Digital Harmony: The Life of John Whitney"](https://www.awn.com/mag/issue2.5/2.5pages/2.5moritzwhitney.html)
- [Volker Straebel, "As unified, bi-sensorially, as the sound film can be" (PDF)](https://www2.users.ak.tu-berlin.de/akgroup/ak_pub/2009/Straebel%202009_Whitney%20Brothers.pdf)
  — the 12-pendulum optical-sound system behind *Five Film Exercises*; the whole-number-ratio
  idea reached Whitney through **sound** first
- [Wikipedia: John Whitney (animator)](https://en.wikipedia.org/wiki/John_Whitney_\(animator\))
- Bill Alves, "Digital Harmony of Sound and Light", *Computer Music Journal* 29:4 (2005) —
  **paywalled, not retrieved.** The one remaining primary source that would sharpen §5.

**Engine grounding (in-repo)**

- `docs/TONAL_ANALYSIS_SCOPING.md` §4 (signal definitions), §7 (the Nacre consumption thesis +
  measured saturation targets) — D-178
- `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` §6 (mv_warp marks-on-top, canvas-hold, per-preset
  canvas clear)
- `docs/presets/SKEIN_DESIGN.md` — the marks-on-top overlay pattern with no engine touch
- `docs/presets/NACRE_PLAN.md` §13 — the TONAL.3 masked-coupling lesson (§5.3)
- `docs/SHADER_CRAFT.md` §17 (sidecar schema), §17.1 (`audio_routes`)
- `docs/PRESET_SESSION_CHECKLIST.md` Parts 1–2
- CLAUDE.md §Audio Data Hierarchy; FA #31, #64, #65, #67, #73

---

## Formula appendix

**F1 — Canonical polar Whitney figure** (`COLUMNBC`)
θᵢ(t) = 2π·i·f(t), rᵢ = R·i/N, i = 1…N; x = cx + rᵢcos θᵢ, y = cy + rᵢsin θᵢ

**F2 — Music Box convention** (fundamental outermost — **ship this one**, §8)
θᵢ(t) = 2π(i+1)·f(t), rᵢ = R(N−i)/N, i = 0…N−1. Dot *i* completes (i+1) revolutions per cycle.

**F3 — Sampled-spiral identity** r = R·θ / (N·φ) — Archimedean, pitch R/(Nφ)

**F4 — Resonance condition** at f = p/q lowest terms: q rays spaced 2π/q; N/q points per ray;
radial spacing q·R/N

**F5 — Ensemble period** ωᵢ = kᵢω₀ → T = 2π / (ω₀ · gcd{kᵢ}). For kᵢ = i, T = 2π/ω₀.

**F6 — Detuned variant** ωᵢ = i·ω₀(1 + εᵢ): no exact return; near-resonances at the
continued-fraction convergents. Harmless while ε ≲ 1/(N·cycles).

**F7 — Arabesque shear-wrap** (`ARABESQUE.BAS`, §8)
Aᵢ = −90° + 360°·i/N; Rm = 3R
xᵢ = ((R cos Aᵢ + i·f(t)·Rm) + Rm/2) mod Rm − Rm/2 + cx;  yᵢ = cy + R sin Aᵢ

**F8 — Colour / size** (Music Box)
hueᵢ = 360·(i+1)/N; satᵢ = min(1, Δtᵢ/1000 ms); lumᵢ = max(0.5, 1 − Δtᵢ/1000 ms);
sizeᵢ = max(minRad + (maxRad−minRad)(1 − (i+1)/N), base + 6 − 6·Δtᵢ/500 ms),
where Δtᵢ = time since dot *i* last crossed 0°

**F9 — Zero-crossing trigger** an element "sounds" when ⌊θᵢ/2π⌋ increments

**F10 — Aliasing bound** N < T·fps / 2 (hard Nyquist); N < T·fps / 4 (practical) — §9.1

**F11 — Trail/legibility bound** (1 − decay) ≳ q·N·Δf — §9.2

**F12 — Phyllotaxis** (the maximally dissonant fixed point) θᵢ = i·137.50776°, rᵢ = c√i

**F13 — Fourier / epicycle** (closed-curve form, if WHIT.C wants curves not polygons)
z(t) = Σₖ aₖ e^{i(kω₀t + φₖ)}

---

*Authored 2026-08-19 in the shaping seat. D-numbers for this program are unassigned — fill at
commit (DOC.6 precedent). This document is design, not commitment: WHIT.0 decides whether any
of it gets built.*
