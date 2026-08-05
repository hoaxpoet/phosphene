# Meniscus — design plan

**Preset:** Meniscus
**Family:** `milkdrop_inspired` (D-105 as amended)
**Inspired by:** `Martin - QBikal - Surface Turbulence IIb`
**Status:** design authored 2026-08-03 (prep seat). No implementation yet.
**Visual references:** [`docs/VISUAL_REFERENCES/meniscus/README.md`](../VISUAL_REFERENCES/meniscus/README.md)
**Increment series:** MEN.1 (design + references) → MEN.2a (spike + wired stub) →
**MEN.2b (faithful base)** → MEN.3 (Phosphene uplift) → MEN.4 (polish + cert)

> **Authoring-seat note.** This document was authored in the prep seat and is settled
> **before** MEN.2a opens, per the `session-prompt-author` invariant. It reaches the repo
> either by Matt committing it directly or via MEN.2a task 0, which commits it
> **verbatim** — either way it is not authored, edited, or restructured by Claude Code
> mid-session. Claude Code *appends* findings to §9 (Session log) and proposes
> amendments in closeout reports.

---

## §1. One-sentence musical role

> **Every drop that strikes the water is an instrument: the drums land on the near
> edge, the bass lands deep at the centre, the vocal lands high and far, and the
> ripples that spread from each impact and interfere with one another are the
> arrangement, drawn as a wake.**

This satisfies the musical-role gate (PRESET_SESSION_CHECKLIST Part 2). It names
specific musical features (per-stem onsets and energies) and a specific visual
behaviour the listener pairs with them (a drop landing at a *nameable place* on the
surface). A listener can point at a ripple and say "that was the snare."

Secondary routes, subordinate by construction:

- **Overall loudness → wave amplitude / surface liveliness.** The whole sheet is
  calmer in quiet passages and choppier in loud ones.
- **Downbeat (cached `BeatGrid`) → camera re-aim.** The viewpoint takes a new heading
  on the bar line. Bounded, per D-157.
- **Mood arousal → camera dolly**, which sweeps the line spacing between the open
  raster (hero) and the dense sheet (excursion). Deliberately *not* a slower smoothing
  of loudness — see the §5 routing table.

---

## §2. Why this preset, and why now

**Catalog gap.** Phosphene has no 3D line-drawing register at all. `Waveform` is a
static spectrum primitive; the entire Milkdrop-inspired family to date (Nacre, Glaze,
Floret, Dragon Bloom, Fata Morgana) lives in the `mv_warp` feedback register. Meniscus
is the first `mesh_animation` member of that family and the first preset in the
catalog whose subject is a *projected surface* rather than a screen-space field.

**Fidelity risk is unusually low, and that matters.** The recent retirements —
Kinetic Sculpture (D-188, "tinker toy"), Glass Brutalist (D-186, 2006-tier concrete),
and the Ferrofluid / Aurora Veil / Drift Motes stalls before them — all failed on the
same axis: a hero *material* that had to look photoreal and didn't. Meniscus has no
hero material. Its entire visual read is geometry plus a one-term slope shading
function. What looks like brushed chrome in reference `03` is an emergent property of
a hundred adjacent slope-shaded lines, not a BRDF. The preset is closer in kind to
Dragon Bloom's strands (certified) than to anything that has stalled.

This is the load-bearing argument for the concept, and it inverts if anyone tries to
author the dense sheet as a material. See §7 risk R2.

**Concept bar (all three cleared).**

1. **Iconic visual subject deliverable at fidelity — YES.** Demonstrable from Dragon
   Bloom: projected per-vertex polylines with HDR glow are already shipping and
   certified. Meniscus needs ~2,000 vertices in one strip where Dragon Bloom needs
   three strands; the arithmetic is comfortable.
2. **Clear musical role — YES.** §1.
3. **Infrastructure-feasible — MOSTLY, with one named unknown.** The geometry draw,
   the sim runtime, and the ground/sky fragment all have precedent. The
   **one-dimensional (sideways-only) line glow** has no existing consumer and is the one
   surface that may need new work. It is scoped as an explicit MEN.2a spike rather than
   assumed, and MEN.2a stops and reports rather than adding engine surface unasked. See
   §7 risk R1.

### Sequencing — faithful base first, uplift second (Matt, 2026-08-03)

**The first draft of this plan got this wrong** and went from a no-audio skeleton
straight to the Phosphene-native stem routing, with no increment in between where the
preset behaves the way the source behaves. Matt corrected it. The corrected sequence
inserts **MEN.2b, the faithful base**, and defers every deviation to MEN.3.

**The project's own record settles it.** All three certified Milkdrop-inspired presets
shipped faithful-base-first: Nacre ("faithful base first (NACRE.2b); the 3 greenlit
uplifts deferred to NACRE.3+", D-171), Floret ("faithful base first (FLORET.2b), then
the M7-driven motion bundle", D-172), Glaze (2b faithful base → .3 base coupling → .5
per-stem uplift → .7 M7 → .8 cert, D-173). The counterexample is Aurora Veil, which
derived rather than ported: five rounds of accretion were deleted and it was **rebuilt
as a faithful port**, and only then certified (AV.7).

**Three concrete reasons it matters here, beyond precedent:**

1. **Without a faithful base there is no oracle.** With one, a Meniscus render can sit
   next to the butterchurn render on the same track and the surface's behaviour can be
   checked directly. Without one, if the surface looks wrong at MEN.3, the sim and the
   routing are both suspect and both get tuned at once — which is the tuning-spiral
   generator this project has been burned by repeatedly.
2. **The source's drop mechanism does load-bearing visual work I was dismissing.** §3
   calls its cepstral placement "inaudible," which is true and is why it gets replaced —
   but it also sets the *distribution*: how many drops per second, how spread out, how
   hard, and the wave sim's damping and stencil were tuned against that distribution.
   The interference structure in reference `07` only appears at a certain drop density.
   The faithful base is how we learn what density the surface needs **before** changing
   what decides the drops.
3. **The decode in §3 is unverified.** It was read from the source file without running
   it. NACRE.2b's single most valuable output was three corrected source-decode errors
   that were only findable by building the faithful base and looking at it (FA #73).
   Expect the same here, and give it somewhere to land.

**Why the extra increment is cheap in this case.** Only the drop-placement function is
thrown away at MEN.3. The wave sim, the projection, the serpentine strip, the slope
shading, the ground and sky, and the camera all carry forward unchanged. The discarded
piece is the smallest one, and it is the one whose behaviour we most need to observe.

**What this does NOT change.** The divergence axis (§5) is still the feature stack, and
it is still declared before implementation — it is now *delivered* at MEN.3 and
*demonstrated* at M7 against the faithful base rather than asserted. And D-116 bullet 1
still holds throughout: "faithful base" means reproducing the source's **behaviour**,
written from first principles. No equations are transcribed at any increment.

---

## §3. Source decode

Decoded from the butterchurn JSON at `~/mdrender/builtins/` on 2026-08-03. Prose only
— no equations transcribed (D-116 bullet 1). **Correcting three things a casual read
gets wrong**, in the FA #73 tradition:

**The preset has no feedback at all.** Its warp shader returns black unconditionally,
which wipes the accumulation buffer every frame. `decay`, `echo_*`, `warpscale`,
`zoom` and the rest of the feedback base values are present in the file but inert — a
custom comp shader also bypasses the fixed-function gamma/echo stage. Everything on
screen is drawn fresh each frame. **Do not build this on `mv_warp`.** The visible
trailing in the render is the sideways dilation in the comp, not accumulation.

**The surface is a CPU-side simulation, not a shader.** The per-frame equation block
runs a 45×45 height field with a standard two-buffer wave-propagation step (neighbour
average, minus previous height, times a damping factor) on a torus. Roughly 2,000
cells, stepped once per frame on the CPU. The per-pixel equations are three constants
and do nothing.

**The drawn geometry is one continuous polyline, not a stack of separate lines.**
Rows are traversed in alternating directions (serpentine / boustrophedon), so the path
snakes across the whole grid and joins at the margins — which is exactly what produces
the rounded turnaround caps visible in reference `07`. It is split across four
Milkdrop "custom waves" only because a wave caps at 512 samples; conceptually it is
one strip of ~2,025 vertices. Each vertex carries screen position (from a hand-rolled
3×3 rotation plus perspective divide), an alpha from a **slope** term (the difference
between the current height and a one-sample-lagged smoothed height), and a colour from
**height** (deep → warm, crest → cool).

**Drop placement comes from a cepstrum-like transform, and it is inaudible.** The
source takes the FFT spectrum, runs a 30-bin DFT *over the spectrum*, and treats the
real and imaginary parts of each bin as an (x, y) position on the grid; the bin's
magnitude sets the impact force, applied over a 3×3 stencil. This is a genuinely
elegant piece of engineering — harmonic spacing in the spectrum determines where drops
land — but no listener can perceive the mapping. **This is the mechanism Meniscus
replaces**, and replacing it is the D-121 divergence axis (§5).

**Camera.** Three Euler angles integrate from velocities that are re-randomised on
detected beats (at `bindex % 4 == 0`, `% 4 == 2`, `% 6 == 2` — so three independent
axes on three different bar-relative cadences), smoothed by a factor that itself scales
with volume, so the re-aim is snappier when the music is loud. Camera distance
oscillates on a slow sine, which is what sweeps between the open raster and the dense
sheet. The source's beat detector is the classic Milkdrop idiom: `bass+mid+treb`
against a slow running average with a 200 ms refractory — an absolute-ratio threshold
that Phosphene replaces with deviation primitives per D-026 / FA #31.

**Composite.** Three layers over the drawn lines: (a) a max-dilation along screen-space
X only, whose radius scales with camera proximity — that one-dimensionality is why the
raster stays open in Y while reading soft in X; (b) a perspective-projected ground plane sampled
from a noise texture, with a horizon whose tilt follows the camera angles; (c) a sky
wash and a lateral glare term, both tinted from the camera's Euler angles, and a global
brightness gate driven by volume.

---

## §4. Temporal contract

Reference images are still moments; this is what changes over time.

**This table describes the SHIPPED contract — MEN.3 onward.** At MEN.2b the temporal
contract is the *source's*: drop placement from the spectrum transform, camera re-aim on
the source's own beat cadence, sine dolly, and no designed silence state beyond whatever
D-037 minimally requires. The table below is what MEN.3 replaces it with, and the delta
between the two is what M7 judges.

| Timescale | What the listener sees | Driver |
|---|---|---|
| **Silence / cold start** | A slow standing swell — the sheet breathes with long-wavelength, near-still motion. Sky and ground stay lit. Never black. (Matt's call, 2026-08-03.) | Autonomous, audio-independent. D-037. |
| **Per onset (~100 ms)** | A narrow, tall spike stands up where that stem's region is, then collapses into an expanding ring. | Per-stem onset / deviation. §5. |
| **Per beat / bar** | The camera takes a new heading. Bounded angular step; luminance steady across the change. | Cached `BeatGrid` bar phase. D-157 / D-158. |
| **Seconds (~2–8 s)** | Ripple systems from separate impacts overlap and interfere, producing the chevron structure in reference `07`. | Emergent from the sim. |
| **~20–40 s cycle** | Camera dollies, sweeping line spacing between the open raster (resting) and the dense sheet (peak). | Mood `arousal` (§5). |
| **Track change** | Surface resets to the standing-swell state; camera returns to the resting attitude. | `reset()` on track change, per the `CymaticSandGeometry` precedent. |

**Cold-start contract.** Per the retired-phase-derivation rule, ungated beat accents
fire wrong-phase at track start. Meniscus's beat consumer is the camera re-aim, which
is low-stakes if wrong-phase (a heading change on the wrong beat still reads as
motion, not as an error). **No cold-start suppression is required.** State this
explicitly so nobody adds one.

---

## §5. Divergence axis (D-121 / D-116) — declared before implementation

**Axis: primary feature stack.** Declared here, before implementation. **Delivered at
MEN.3**, not before — MEN.2b deliberately reproduces the source's feature stack so that
the divergence has something to be measured against (§2 Sequencing). At M7 the
divergence is *demonstrated* — faithful-base render, shipped render, and source render
side by side — rather than asserted, which is a stronger D-121 position than the
original plan could have reached.

The source places drops from a cepstral transform of the full-mix spectrum — a
mechanism with no perceptible connection to what the listener hears. Meniscus places
drops from **stem separation**: each separated instrument owns a region of the water
surface and strikes it on its own onsets. This is a different feature stack end to end
(Open-Unmix HQ stems + deviation primitives vs. a hand-rolled DFT-of-FFT), it produces
visibly different behaviour (impacts cluster by instrument rather than wandering with
harmonic content), and it is the thing that makes Meniscus a Phosphene preset rather
than a reproduction.

**Region layout (proposal — MEN.3 authoring choice, and explicitly provisional).** The
faithful base will show what drop density and spread the surface needs to produce
readable interference (§2 reason 2). If the stem-region scheme starves it — four sources
firing on their own onsets may be far sparser than the source's continuous spectral
placement — the recovery is to keep stems deciding *character* and let a
faithful-derived process keep the base drop rate up. Decide that against the MEN.2b
oracle, not in advance.

| Stem | Region | Impact character |
|---|---|---|
| `drums` | Near edge, spread laterally | Sharp, narrow, high — the punctuation |
| `bass` | Deep centre | Broad, low, slow-decaying — a heave rather than a spike |
| `vocals` | Far and high | Narrow, sustained, brightest colour |
| `other` | Wide, low-amplitude scatter | Texture; keeps the field from ever being fully still |

**FA #67 check — one primitive per visual layer:**

| Visual layer | Audio primitive | Timescale |
|---|---|---|
| Drop impacts | per-stem onset (`drums_beat` class for drums; per-stem deviation elsewhere) | event, ~100 ms |
| Surface liveliness / wave amplitude | overall loudness envelope | ~1 s |
| Camera heading re-aim | cached `BeatGrid` bar phase | bar |
| Camera dolly / line spacing | mood `arousal` | ~20–40 s |
| Palette temperature | height (geometric), *not* audio | n/a |

No two rows share a primitive and no two share a timescale.

**Why `arousal` and not a slow loudness envelope for the dolly.** A slower smoothing of
loudness is *the same primitive*, and two visual layers reading one primitive at two
smoothings is precisely the FA #67 failure — the surface would get choppier and the
camera would pull in at the same moments, so the music would drive one perceptual
change through two channels and the frame would read as overreacting. Mood arousal is a
genuinely independent wide-window signal, and the AV.7 finding (D-185) is that mood
envelopes are the right driver for slow, gentle response where deviation primitives
measure too spiky. Note that arousal at cold start is EMA-attenuated, so the dolly
should start at the hero (open-raster) distance and move from there, never the reverse.

**Palette is deliberately not audio-coupled.** Height already carries it, and adding a
second audio channel to colour is exactly the Ferrofluid rounds 56–65 failure.

**Secondary divergences, not claimed but worth having:** the source's absolute-ratio
beat detector is replaced by deviation primitives (D-026, mandatory anyway); the
source's black silence state is replaced by the standing swell (D-037, mandatory
anyway). Neither is claimed as the certification divergence — mandatory compliance is
not divergence.

---

## §6. Open authoring decisions

Deliberately left open. Each is a Claude Code call at the increment named, **except**
where marked as Matt's.

- **Palette (MEN.3).** The source is white-on-teal with a warm-deep / cool-crest hue
  ramp. The concept — deep is warm, crest is cool — is worth keeping; the specific
  colours are open, and non-source references should be curated before this is locked
  (see the reference README's "What this set is missing").
- **Grid resolution.** 45×45 ≈ 2,000 vertices is the source's figure and is chosen for
  a 2001-era CPU. Phosphene can afford considerably more, but the undersampling
  visible in reference `07` is partly *why* the lines read as discrete. Raise it, but
  measure the point at which the raster stops reading as a raster.
- **Sim on CPU or GPU (settled at MEN.2a task 1c).** The wave step is trivially parallel
  and belongs on the GPU; the source ran it on the CPU only because Milkdrop had nowhere
  else. Claude Code's call, made in the MEN.2a spike alongside the glow decision because
  the two constrain each other. Precedents: `CymaticSandGeometry` (compute) vs the
  CPU-side `MitosisGen2Geometry`.
- **Whether the dense-sheet excursion is reachable at all in v1.** If bounding the
  dolly to the hero register simplifies MEN.2a/2b materially, ship the hero register
  alone and add the excursion at MEN.3.

---

## §7. Risks — surfaced before code, per the design-grounding rule

**R1 — One-dimensional line glow has no existing consumer. (Grounding level 1; medium
risk.)** The sideways-only spread is what keeps the raster open in Y while soft in X.
Phosphene's post-process chain has bloom, which is isotropic and will close the gaps
(reference README anti-reference 5). Grounding is level 1 (working code reference — the
source's own comp stage, decoded above, plus the standard separable-dilation form). It
is nonetheless the one pass surface without a Phosphene precedent, so **MEN.2a spikes it
and chooses, at task 1, before any shader work begins.**

Two things are open and must be decided from a render, not from reasoning: **which
axis** the spread follows (screen-space X, as the source does, or the line's local
tangent — these diverge under camera rotation because rows are traversed serpentine),
and **where** it happens (a post stage, a staged dilation stage, or built into the line
geometry as stretched quads). The second determines whether new engine surface is
needed at all.

**R2 — Someone authors the dense sheet as a material. (High impact, low probability,
must stay low.)** Reference `03` looks like brushed chrome. It is not a material and
must never be authored as one. This is the failure path that retired Kinetic Sculpture
and Glass Brutalist and stalled Ferrofluid. The mitigation is written into the
reference README as anti-reference 3 and into the MEN.2a prompt's Do-NOT section; if a
session proposes a BRDF, an environment map, or SSGI for this preset, that is the
escalation trigger.

**R3 — Stem-region legibility is unproven. (Grounding level 3 — the design doc's
assertion only. Surfaced explicitly.)** No published demo maps separated stems to
spatial regions of a simulated water surface. The individual pieces are grounded (stem
separation ships; ripple sims are textbook; the region idea is trivial) but *the
combination* is not, and per the design-grounding rule a combination needs grounding
for the combination itself. **There is no empirical grounding for stem-region
legibility.** It is only assessable in motion against real music at M7. If it fails
there, the fallback is a single shared impact region with per-stem *character* rather
than per-stem *place* — which preserves the divergence claim but weakens it.

**R7 — The faithful base must not ship as the final preset. (Process risk, low
probability, high cost if it happens.)** MEN.2b will produce something that looks good —
the source is a good preset. The temptation at that point is to certify it and move on.
That would fail D-121: a Meniscus that reproduces the source's feature stack has no
divergence axis and cannot certify. MEN.2b's own closeout should state plainly that the
preset is **not shippable as-is** and name what MEN.3 must change. Conversely, if MEN.3's
uplift genuinely fails at M7, the answer is a different uplift — not shipping the base.

**R6 — The standing-swell silence state has no empirical grounding. (Grounding level
3. Surfaced explicitly.)** The source has no silence state at all — it renders black
(anti-reference `06`), which is why this is a Phosphene invention rather than an
inherited behaviour. There is no reference image for it in the curated set and no
published demo to point at. **There is no empirical grounding for the standing-swell
silence state.** It is judged from a rendered contact sheet only. The failure mode is
that a swell slow enough to read as "calm" also reads as "frozen"; the recovery is more
spatial variation at the same temporal rate, not a faster swell.

**R4 — Vertex count vs. line legibility interact.** Raising grid resolution to make the
surface smoother directly closes the raster gaps that make the preset distinctive.
These two quality axes pull against each other; expect the resolution decision to be
made from a contact sheet, not from reasoning.

**R5 — The source's charm partly depends on the drop mechanism we are removing.** The
cepstral placement produces wandering, unpredictable drop positions that the
stem-region scheme will make more orderly. Orderly may read as mechanical. Mitigation:
jitter within each region, and let `other` scatter widely.

---

## §8. Sidecar shape (target)

Not binding on implementation; recorded so the metadata decisions are visible up front.

- `family`: `milkdrop_inspired`
- `motion_paradigm`: `mesh_animation` (D-120) — **not** `feedback_warp`. Single
  paradigm, per D-029. No feedback layer is added on top at any point.
- `concept_tags`: `waveform`, `geometric` (+ a new tag if the controlled vocab needs
  one for the surface/contour register — reuse over invention, D-120)
- `inspired_by`: `{ milkdrop_filename, original_artist, pack, sha256 }` per D-111 as
  amended. The `.milk`/JSON source is **not** committed (D-116 bullet 4); the SHA-256
  is the provenance record.
- `rubric_profile`: full
- `certified`: `false` until Matt's M7
- `docs/CREDITS.md`: extend the Milkdrop-inspired attribution table.

---

## §9. Session log

*(Appended by Claude Code at each increment closeout.)*

### MEN.2b — oracle stood up, and four corrections to §3 (2026-08-03)

Per the `reference-port` skill, the cross-check was built **before** any port code. The
source was rendered through the existing butterchurn harness
(`tools/milkdrop-render/render-gif.js`) driven by the **same audio Matt was listening to**
— 12 s extracted from `raw_tap.wav` of session `2026-08-03T20-05-13Z`, Smashing Pumpkins,
"Hummer". Reproduce with `Scripts/render_meniscus_oracle.sh`. Nothing from the source is
committed (D-116 bullet 4); the render output lives at `~/mdrender/men2b/`.

**§3 was decoded by reading the source without running it, and four things are wrong or
badly understated.** This is the NACRE.2b pattern the plan predicted (§2 reason 3).

1. **The palette is a BEHAVIOUR, not a choice — and it is the source's most dominant
   visual property.** §6 files palette as "an open authoring decision (MEN.3)" and the
   reference README says "Do NOT trust: the palette. Near-monochrome white-on-teal is the
   source's choice." Both are wrong. Measured off the oracle, the sky hue sweeps
   **continuously and monotonically at roughly 40°/second**: 303° magenta → 294° → 282°
   → 269° → 254° → 233° → 208° → 176° teal across ~3.2 s, at a steady saturation of
   0.6–0.8. The teal of the curated stills is one instant of a continuous rotation. §3
   already said the sky is "tinted from the camera's Euler angles" — what it missed is
   that the angles integrate continuously, so the tint *never settles*, and a still frame
   cannot show it. **There is no fixed palette to choose at MEN.3.** Confirmed
   mechanically: the comp shader contains only one `sin` and takes its colour from `q1`–`q6`
   computed in the frame equations, i.e. the hue arrives pre-computed from the camera state.

2. **The surface is FLAT with one localized ripple system, essentially always.** §4's
   temporal contract implies drops are punctuation on a calm field; the oracle shows the
   calm field is the *default state* and the concentrated central ripple is the subject in
   every frame after cold start. T4 is not one trait among six — it is the preset.

3. **The camera tumbles far harder than "three Euler angles integrating from velocities"
   conveys.** Within 4 s the plate goes edge-on → steeply tilted → near face-on, rotates
   through most of a turn, and the distance oscillation swings it from a small floating
   rhombus to filling the frame and back. The plate is a *floating object of varying size*
   for most of the cycle, not a frame-filling plate — reference `01`/`02` are the wide end
   of a large excursion, not the resting register.

4. **`decay = 0.5` and the echo base values are inert, confirmed at the shader level.**
   The warp shader body returns `vec3(0,0,0)` unconditionally. §3 asserted this from a
   read; it is now verified from the artifact.

### MEN.4c — the surface had no continuous driver at all (2026-08-05)

Matt, tenth round, on the MEN.4b cut: **"feels less tethered to the music now, just fewer
and more random drops."**

**Cutting density made it WORSE, which is what finally ruled density out** — and pointed at
something that had been true since MEN.2a and that I had never checked.

**During music the surface had NO continuous audio-driven motion.** The swell — its only
continuous element — was gated off as volume rose (MEN.3d, `swellGate = 1 − volume × 6`),
so the sheet was 100 % discrete drop events. That inverts CLAUDE.md's single most important
design rule:

> *"visuals driven primarily by continuous energy feel locked to the music; visuals driven
> primarily by raw live beat detections feel out of sync. Continuous energy is the DEFAULT
> PRIMARY DRIVER."*

**Ten rounds went into the SECONDARY driver** — drop timing, now a median 6 ms from the
beat — **while the primary one was switched off.** "Not tethered" is the exact phrase that
rule predicts.

**Two fixes, both found by looking rather than by a metric.**

1. **The excitation goes INTO the sim, not onto the display.** The MEN.2a swell was added
   at draw time and never entered the field, so it could neither move the simulation nor
   INTERFERE with the drops — §1's *"ripples that spread from each impact and interfere
   with one another"* was never actually happening. Measured with a display-only swell, the
   surface's own RMS correlated **r=+0.136** with the music.
2. **A `tanh` soft ceiling.** The first render showed spears tearing off the sheet:
   continuous forcing is *resonant* by nature — the same spatial pattern added every frame
   pumps fixed antinodes without bound. The ceiling bends only the extremes, leaving ripple
   shape untouched. Peak **4.196 → 1.242**.

**A metric I stopped trusting mid-calibration.** The tether correlation reads 0.136 at one
window length and 0.316 at another *for the same configuration*. It is a diagnostic, not
something to tune against — so the drive was chosen from amplitude evidence and the render,
not by pushing a number over a bar I had invented.

`MeniscusSurface.swift` was split at this increment (`+Simulation`) purely for size; the
doc-integrity gate caught the missing Module Map row immediately.

### MEN.4b — fewer drops, each one meaning something (2026-08-05)

Matt, ninth round, on the MEN.4a build: **"Drops appear to follow the drums, not exactly
but closely. feels busy / arbitrary."** He added that he did not understand the
mechanical-vs-arbitrary distinction I had asked him to make — **that question was badly
framed and the fault is mine**, asking him to translate my uncertainty into a diagnosis in
my own vocabulary. What he volunteered instead was more useful than an answer to it.

**"Follows the drums" is the sync reading for the first time in nine rounds.** That is the
part to protect, and it is what the grid-timed beat drop delivers.

**"Busy" was arithmetic, not taste.** Per bar at full density the MEN.4a pattern placed:

```
drums 4 · bass 1 · vocals 2 · other 8      = 15 drops/bar
```

**The offbeat scatter alone was 53 % of every drop** — and it is the widest random spread
on the sheet (±0.42), landing *between* the beats. More than half of what a viewer saw
corresponded to nothing audible. That is "arbitrary", precisely.

He also said **"too much activity" in round one**, and eight rounds of adding layers
followed. Hearing the same complaint twice and continuing to add is the failure worth
recording here.

**Cut to 7 drops/bar.** `other` moves from every offbeat (8/bar) to once per bar, and the
backbeat answer is held back until the arrangement is genuinely full (0.5 → 0.65).

```
density   4.7–5.2  →  2.7–3.7 impacts/s
`other`   54 drops →  11 drops
sync      unchanged: median 6 ms from the beat, 99–100 % within 60 ms
arc       1.52x / 2.69x sparse-to-full (MEN.4a's response survives the cut)
```

**One gate narrowed, deliberately.** `everyStemFires` required all four regions on every
track. That encoded MEN.3's retired instrument-identity claim and it now *contradicts*
MEN.4a: the `other` texture is gated to the top of the arc, so on sparse material
(`so_what`) it should stay silent — a track that never fills out must not get the busiest
layer. The three beat-locked regions remain absolute; `other` is reported, not required.

### MEN.4a — the visual follows the music's ARC, not just its beat (2026-08-05)

Matt, after eight rounds of beat-timing work: **"Music is more than just beat, remember."**

**That is the diagnosis those rounds never reached.** Meniscus was rhythmically accurate
and structurally deaf: the same drop density, the same placement pattern and the same
character on every beat from the first bar to the last. **Perfect timing on an unchanging
pattern is still a metronome**, and no amount of ±ms work can fix a visual that ignores the
music's shape.

Measured on `2026-08-05T15-06-31Z` (Hummer, 92 s), the music moves a great deal:

```
arousal     0.19 → 0.52 → 0.44 → 0.43 → 0.43 → 0.35 → 0.27     (3x swing)
valence     0.31 → −0.35 → 0.27 → −0.14 → 0.71 → 0.72          (sign flips twice)
stems       all four rise to a peak at 30–45 s, then fall away entirely
brightness  0.16 → 0.13 → 0.10 → 0.10 → 0.02 → 0.00
```

Against all of that the preset varied **only overall amplitude and camera distance**.

**The build.** How much of the pattern plays is now a function of the arrangement and the
mood arc: a sparse intro gets the downbeat spine only; every beat joins once the
arrangement fills; the backbeat answer arrives above half; the offbeat scatter is the top
of the arc — the last thing to arrive and the first to go. **A build now FILLS IN rather
than merely growing louder.**

**The stems come back, for the job they can actually do.** MEN.3f proved they are useless
for event timing (5.2 s stale) and MEN.3h removed them entirely. But "how full is the
arrangement right now" is a *section-scale* question, and section scale is exactly the
timescale a 5.2 s lag does not spoil. Using a signal at its own timescale rather than
against it is the whole lesson of MEN.3f, applied in the other direction.

```
[meniscus-arc] there_there: drops/frame — sparsest third 0.0932 · fullest third 0.1352 (1.45x)
[meniscus-arc] love_rehab:  drops/frame — sparsest third 0.0559 · fullest third 0.1329 (2.38x)
```

**A real bug the gates caught.** Appending the downbeat's bass region before the drums
broke an unstated contract — `lastSites` is emitted in ascending region order and every
diagnostic attributes sites by walking `lastPerRegion` alongside it, so every drop was
silently mis-attributed. The region-ordering gate failed immediately (bass mean row 0.81
where it should be 0.48). `firing.sort()` restores it, and the contract is now written down.

### MEN.3h — nothing may strike the water at silence (2026-08-05)

Matt, eighth round: **"drops are still falling at silence. drops do not match the beat or
melody."**

**He is right and it was structural, not a tuning miss. Nothing in MEN.3g's firing path
consulted current loudness.** The grid keeps ticking through a quiet passage; the dynamics
term carried a 0.5 floor so every grid event still landed; `intensity` floors at
`stemIntensityFloor`; and the only presence gate read STEMS, which lag ~5.2 s and therefore
cannot close on a silence that started less than five seconds ago. Measured on
`2026-08-05T15-06-31Z` (Hummer — a slow build with a sparse intro): **the band level is
exactly 0.0000 on more than 25 % of frames**, and drops rained through all of it.

**And that is also most of "drops do not match the beat", because the grid was CORRECT
here.** Verified two independent ways on this capture:

```
tempo   grid 80.45 BPM against 80.43 derived from the tap audio   (0.02 % error)
phase   ColdStartVerifier re-diagnosis: +8 ms at 30 s, 45 s, 60 s — viable at every window
```

So the drops that landed on the beat were landing within 8 ms of it. What made the preset
read as unrelated to the music was the *other* drops — a steady 80 BPM patter continuing
through every silent passage, on a track where those passages are a quarter of the running
time. Silence was drowning the signal.

**The fix.** A fast band-level envelope (~0.12 s, no floor) gates all firing: it opens on
the first note of a phrase and closes within a beat of the music stopping. The dynamics
floor is gone, so quiet passages now produce genuinely small drops. D-037 is untouched —
that rule governs what the SCREEN shows at silence (the backdrop still renders), not
whether the water is being struck when nothing is playing.

**The stem path is now gone entirely.** With region choice coming from the bar (MEN.3g) and
gating from current loudness, no stem signal remains in the firing path — so the 5.2 s
staleness cannot reach the surface by any route. `MeniscusStemDropsTests`' old
stem-presence gate is retired in favour of `MeniscusSilenceGateTests`, which asserts the
stronger property it could not: **loud, stale stems plus a ticking grid must still place
nothing once the audio stops.**

```
[meniscus-silence] drops while playing: 37 · drops at silence: 0
density 5.4–6.2 impacts/s · sync median 6 ms · modulation 44 % · audio share 60 %
```

**Not addressed, and it never was: melody.** No drop has ever tracked pitch or melodic
contour, and this design does not claim to. If melodic response is wanted it is a new
route, not a fix.

### MEN.3g — every drop is grid-timed, and the per-instrument claim is retired (2026-08-05)

Matt, seventh round: **"still doesn't read as synced with the music."**

**The conclusion seven rounds were converging on, stated plainly: the only part of this
preset that EVER measured as synced was the part taking its timing from the cached
BeatGrid.** Grid-timed drops landed a median 6 ms from the beat in every round from MEN.3c
onward. Every failure was a drop driven from a live audio signal, and each candidate died
to a measurement rather than an opinion:

| Signal | Current? | Per-instrument? | Usable for events? |
|---|---|---|---|
| Separated stems | ✗ **5.2 s stale** | ✓ | no (MEN.3f) |
| `beatComposite` / `beatBass|Mid|Treble` | ✓ | ✓ | no — **saturated** |
| Band deviations (D-026) | ✓ | partly | no — **too sparse** |

- **Stems** lag 5.2 s (MEN.3f). Section-scale by design.
- **The per-band beat pulses saturate.** On `2026-08-05T14-09-24Z`, `beatComposite` is
  exactly 1.000 on **59 % of frames**, in runs up to 36 frames (600 ms). They are onset
  pulses re-triggered faster than they decay, sampled at the 10 Hz MIR rate — the same
  stair-step behind MEN.3c's lag. **Not a scaling bug**; they work as built. A drive pinned
  high is a metronome, which is exactly what Matt watched.
- **Band deviations** are correctly event-shaped but cannot carry the surface: ~40 % of
  beats produced a drop against a 55 % bar, and audio's share of surface motion collapsed
  to 17 % against a 50 % bar. Treble is effectively silent (mid p50 0.029, treble p50
  0.004), so the `other` region got 1–3 drops per 30 s and drums/bass became one signal.

**The build.** All timing comes from the grid. **The BAR supplies the spatial pattern** —
drums mark every beat, the bass heave arrives on the downbeat, vocals answer on the
backbeat, `other` scatters on the offbeat subdivisions — which is what keeps a fully
quantised surface from reading as a metronome. Force still comes from live audio (bass
deviation + the loudness envelope), so dynamics stay current even though timing does not
derive from the moment. Stems keep only the presence gate.

**What this gives up, and it is a real re-scope Matt approved.** §1's claim that "a listener
can point at a ripple and say *that was the snare*" is **retired**. §7 R3 flagged that
legibility as having no empirical grounding, and seven live viewings never produced it. The
regions are now spatial variety keyed to bar position, not instrument identity.

```
density      5.2–6.0 impacts/s   (drums 57–66 · bass 14–16 · vocals 28–33 · other 55–64)
sync         median 6 ms from the beat · 99–100 % within 60 ms
modulation   44–50 %
audio share  66 %
stem lag     timing identical with stems fresh and 5.2 s stale
```

Best state on every measure so far. Whether it READS as synced is Matt's call — that is the
one thing no gate here has ever been able to settle.

### MEN.3f — the drops were driven by a signal 5.2 seconds stale (2026-08-05)

Matt, sixth round: **"Motion of the drops does not align with or follow the music."**

Cross-correlating each stem against the full-mix bass band from his own capture
(`2026-08-05T13-17-18Z`, Cherub Rock — a local file, so the grid is full-track and correct
and cannot be the explanation):

```
drums  +5.25 s (r=0.550)    bass  +5.25 s (r=0.563)
vocals +5.08 s (r=0.562)    other +5.25 s (r=0.583)
the same data at lag 0:  r=0.363
```

**Every stem lags the music by about 5.2 seconds, and this is by design.**
`VisualizerEngine+Audio.swift`: *"Features carry ~5-10s of latency (we're always analyzing
audio that's already been heard), which is acceptable because musical sections persist
longer than that."* Live stem features answer *what kind of passage is this*. They are a
section-scale signal and cannot carry event timing.

MEN.3 built the entire drop system on them. Live, that meant vocals and `other`
(onset-driven, ~40 % of all drops) fired **five seconds after** the note that caused them,
and every drop's force described music that had already gone past. **Five rounds of ±100 ms
timing work all happened downstream of a 5,250 ms staleness.**

Every offline gate passed throughout because fixtures feed stems in sync with the audio —
the latency exists only on the live path. Same shape as MEN.3e's hardcoded damping, an
order of magnitude more costly.

**The rewiring.** Each signal now does what it is for. Real-time per-band beat channels
decide WHEN a drop lands and HOW HARD (`beatComposite` → drums, `beatBass` → bass,
`beatMid` → vocals, `beatTreble` → other). Stems decide only WHETHER a region is alive in
this passage, on a 2.5 s envelope — the section-scale question 5 s of lag does not harm.
A region whose instrument is silent places nothing, which is what keeps the sheet's
geography meaning something now that the events come from the full mix.

**Two drivers were tried and measured dead before the third worked**, both the same lesson —
*check what the fixture actually carries*:
- `midDev`/`trebDev` are not recorded in the route-coverage fixtures at all (only
  `bassDev` is), so they fed constant zero and killed two regions outright.
- Deriving deviations from `bass`/`mid`/`treble` fails on the real values — measured on
  `there_there`, **mid p50 0.038, treble p50 0.001**. The bands never approach the 0.5
  centre the deviation formula subtracts. GLAZE.8's finding restated: *bands are a track's
  quietest channels.*
- `beatBass`/`beatMid`/`beatTreble` carry the range (p50 0.09–0.34, p90 0.77–1.00).

**The regression gate that would have caught this on day one.** `MeniscusStemLagTests`
drives the drop system with the stems delayed 312 frames, the way the live path delays
them, and asserts the timing is *indifferent* to it:

```
there_there   median beat error — fresh stems 6 ms · stems 5.2 s late 6 ms
love_rehab    median beat error — fresh stems 6 ms · stems 5.2 s late 6 ms
force/loudness correlation moves by ≤ 0.01 under the same lag
```

A first draft of that gate had no teeth — it measured percussion only, which takes its
timing from the grid and would have passed with a fully stale drive. It now asserts the two
things the lag actually broke: the non-grid regions, and drop force.

**The rule worth keeping: before driving anything from a signal, check what timescale that
signal is FOR.** The answer here was written in a comment directly above the function that
produces it.

### MEN.3e — the surface never rested, so there was nothing to read as a beat (2026-08-04)

Matt, fifth round: **"the activity needs to be synced to music, that is the core trouble."**

MEN.3d had put the audio in charge of the amplitude (share 1 % → 72 %) and MEN.3c had the
visible peak 19 ms from the beat. Both true, and the preset still did not read as synced.
The missing measurement was not WHEN the drops land but **whether anything changes between
them.** `MeniscusPulseTests` folds surface slope energy onto 12 bins of `beatPhase01` and
reports peak-to-trough over mean:

```
love_rehab   peak 93.7  trough 82.0   MODULATION DEPTH 13 %
there_there  peak 86.9  trough 74.9   MODULATION DEPTH 15 %
```

A 13 % swing is not a pulse. **Ripple lifetime (~550 ms at the source's damping) exceeded
the beat period (350 ms at 171 BPM)**, so every ripple was still ringing when the next two
arrived. The surface was permanently, uniformly agitated: correct onsets, correct
amplitude, no rhythm. **Rhythm needs REST as much as it needs onsets**, and nothing in the
timing or amplitude work could supply it.

`damping` is the lever. Swept on `there_there`:

```
1.00 -> 15 %   0.97 -> 22 %   0.93 -> 29 %   0.88 -> 48 %   0.82 -> 76 %
```

Shipped **0.88** (48 % / 54 %). This is a deliberate divergence from the source, and the
reason is structural rather than taste: the source's damping suits a continuous cepstral
drop stream where sustained agitation IS the look, while ours is beat-locked punctuation
that has to resolve between hits.

**The trade this buys, which is Matt's to accept or reject.** Shorter ripples interfere
less, and interference is what §1 asks for — "the ripples … interfere with one another …
drawn as a wake" — and what gives reference `07` its chevron structure. Grid coverage per
frame fell 55 % → 21 %. The preset reads more rhythmic and less like a wake.

**One more instrumentation failure, and the worst kind.** The damping change silently took
peak surface displacement **0.18 → 0.008** — a nearly flat plate — while every gate stayed
green, because `MeniscusAudioShareTests` held a HARDCODED COPY of the old damping and was
measuring physics the preset no longer ran. Force and damping are coupled (a faster decay
eats the energy each drop deposits) and must be swept together. Re-swept at 0.88:
25 → 24 %, 150 → 76 %, 400 → 90 %. Force is now **100**, restoring peak 0.186 at 66 %
share. The sync gate's rise time is likewise no longer a constant — it is measured from the
configuration, so the same drift cannot recur. The rise moved 583 ms → 133 ms, which
happens to make Matt's chosen 120 ms lead nearly exact (median error 19 ms → 6 ms).

**The rule this leaves behind: a harness that duplicates a production constant will
eventually measure a version of the system that no longer exists, and it will do it
silently and while passing.** Derive from the configuration or share the code path.

### MEN.3d — the music was causing 1 % of what was on screen (2026-08-04)

Matt, fourth round on the same complaint: "no different from before … the entire preset
feels unmatched to the music, like it's just a movie playing with background music."

That last sentence is the finding, and it is literal. Measured
(`MeniscusAudioShareTests`): **audio-driven surface amplitude 0.0001 against 0.0540 from
autonomous motion — the music caused ~0 % of the surface.** The MEN.2a placeholder swell
was 540x everything the audio path did.

**So four rounds of drop-TIMING work were on the wrong axis entirely.** The drops were
firing in the right regions (vocals 0.19 / bass 0.48 / drums 0.81), at the right density
(4–7 impacts/s), and after MEN.3c with their visible peak 19 ms from the beat at 97–100 %
inside the perceptual window. All of it correct, all of it inaudible under a placeholder.
Every one of those measurements was true and none of them measured the thing that was
wrong, because I never asked what share of the motion the audio owned.

**Two causes, both mine.**

1. **The placeholder swell was never removed.** The MEN.2a prompt said "a placeholder to
   satisfy D-037 … keep it cheap and keep it removable" — I carried it through MEN.2b and
   MEN.3 unchanged, at full amplitude, during music. It now fades out as loudness rises, so
   it does what §4 actually specifies (the silence row) and nothing more. Share 1 % → still
   1 %, because of cause 2.
2. **Drop force was ~100x too low to BE the surface.** Swept against audio share:
   1 → 1 %, 8 → 35 %, 25 → 72 %, 60 → 88 %. Set to 25, which puts peak displacement at
   0.18 — the same magnitude the swell used to occupy, so the surface moves about as much
   as before but the MUSIC is now what moves it.

**The open question, and it is Matt's.** At force 25 the plate is visibly busier than the
calm register of MEN.3b, which is close to his ROUND-ONE complaint ("too much activity").
Connection and calm trade directly here: more audio share means more surface motion. The
lever is one number and the measured curve is above. Rendering before deciding, rather than
choosing for him, is the point — the last four rounds show how expensive a wrong guess is.

**Process note worth keeping.** Every round I measured something real, and for four rounds
running the thing I measured was not the thing that was broken. The check that would have
caught it on day one — "what fraction of the motion does the audio cause?" — is trivial,
and is now a standing gate.

### MEN.3c — the lag was the medium, not the timing (2026-08-04)

Matt after MEN.3b: still "a lag and it's significant enough where the music does not read
as synced". I had two theories and **both were falsified by measurement before any code was
written** — he asked for the measurement first, and it saved an increment spent on a fix
worth zero milliseconds.

**Theory 1 — the grid is late (BUG-065).** Measured against his own `raw_tap.wav`, aligned
to the CSV by cross-correlating the audio envelope against recorded loudness (r=0.83): the
grid's signed offset to audio onsets is **median −8 ms** — centred, not late. Drift across
30 s is −23 → +38 ms, BUG-065's ramp visible but modest.

**Theory 2 — the 10 Hz stair-step quantises firing.** `beatPhase01` really is a stair-step
held ~100 ms (3.5 updates per beat at 171 BPM against a 60 fps renderer), so this looked
decisive. It is not: firing on the wrap edge scores |median| 42 ms / 67 % within 60 ms, and
perfect interpolation scores 45 ms / 64 %. **No improvement.**

**The actual cause is the medium.** A drop is an impulse into a wave field and the ripple
has to GROW: measured on the shipped sim (`MeniscusRippleRiseTests`), the visible slope
response is **14 % after one frame, ~30 % at 67 ms, ~50 % at 167 ms, peaking at 583 ms**.
The eye tracks the ring forming, not the impact, so a perfectly-timed drop still reads
late. No preset that flashes or zooms has this problem; one that ripples does.

**Fix: fire AHEAD of the beat** so the visible event lands on it. 120 ms (Matt's call).
This is the one thing the cached grid buys that a live detector never could — it knows
where the next beat *will* be.

| | before | after |
|---|---|---|
| VISIBLE ripple peak vs beat (median) | ~140 ms late | **19 ms** |
| within the 60 ms window | — | **97–100 %** |
| beats that get a drum drop | 76 % | **100 %** |

The coverage number is the stair-step's *real* damage: edge detection found 55 edges against
72 beats, a 24 % miss that reads as erratic rather than late. A local phase clock running
between the 10 Hz samples catches all of them.

**My MEN.3b sync gate was circular** and I should have caught it. It derived "grid beat
times" from `beatPhase01` wraps and then measured drops against those same wraps — my code
scored against itself, reading median 0 ms while the render visibly lagged. It now compares
the VISIBLE event (impulse + measured perceptual rise) against the grid.

**A second test premise was wrong and is replaced, not relaxed.** Per-drop force vs loudness
went NEGATIVE (−0.18) once percussion moved onto the grid. Force is `stem deviation ×
intensity`, and deviation is self-normalising, so in a loud passage each hit sits *less* far
above its own mean — the two factors legitimately oppose and their product says nothing. It
now asserts the intensity multiplier itself (r=+0.98), with surface amplitude carrying §5's
loudness row at r=+0.999.

**Camera rows wired (§5).** Dolly ← mood arousal, spanning 1.70–2.98 world units and opening
at the hero distance per §5's cold-start note. Re-aim ← bar line rather than the live beat
detector, which FA #67 now requires: with drops on per-stem onsets, a camera re-aiming on
beats would put two visual layers on one primitive at one timescale.

### MEN.3b — sync and intensity, both measured before and after (2026-08-04)

Matt's live read of MEN.3: camera and rotation good, drops look good, but "not in sync
with the music" and "nothing tied to the intensity of the music, so the drops look the
same regardless of whether the music is quiet / loud". Both were measurable on his session
and both were real.

| | before | after |
|---|---|---|
| percussion drop → nearest grid beat (median) | 200 ms | **0 ms** |
| within the ~60 ms perceptual window | 8–10 % | **97–98 %** |
| surface amplitude vs loudness (Spearman) | r = +0.004 | **r = +0.999** |

**Sync — the audio hierarchy's central rule, and Meniscus was on the wrong side of it.**
Drops fired on threshold crossings of a smoothed per-stem deviation: a live onset detector.
CLAUDE.md is explicit that "visuals driven primarily by raw live beat detections feel out
of sync" and that beat-locked motion is valid only on the **cached BeatGrid**
(D-153→D-158). Drums and bass now take their TIMING from the grid while the stem still
supplies WHETHER and HOW HARD — a beat with no drums on it places nothing. Vocals and
`other` stay onset-driven deliberately: §5 gives them "sustained" and "texture" characters
a grid would make robotic. Falls back to onset-driven if no grid beat arrives for 2 s, so
reactive mode degrades rather than going silent. Bounded 3×3 footprint, no global luminance
change — D-157 satisfied.

**Intensity — deviation primitives cannot carry it, by construction.** A deviation says how
far a stem sits above its OWN running mean, so a quiet snare and a loud one produce nearly
the same value. That is exactly what makes them AGC-safe (D-026 / FA #31) and exactly why
they are dynamics-blind. The fix is not to abandon them but to add §5's SEPARATE loudness
row, which was specified from the start and never implemented.

**It also had to go on the right layer.** Scaling per-drop force barely moved the needle
(r=0.13) because per-hit deviation variance swamps it. §5's actual wording is "wave
amplitude / surface liveliness — the whole sheet is calmer in quiet passages and choppier
in loud ones", so the envelope now scales the SURFACE amplitude. Silence floor raised to
0.35 after the first value (0.22) scaled the swell to 7.7e-5/frame against the harness's
8e-5 frozen floor — technically alive, perceptually stalling, against §4's "the sheet
breathes … never black".

**Three measurement errors of mine, worth recording because they nearly hid a working
fix.** (1) A quartile-ratio intensity gate partly measures the TRACK — there_there is
consistently loud and has little dynamic range — so correlation replaced it. (2) I switched
to Spearman on a hypothesis that the intensity clamp was depressing Pearson; Spearman came
back LOWER, falsifying it, and I should have stopped hunting for a statistic that passed.
(3) The actual fault: the harness sampled intensity only every 15th frame while applying a
per-frame smoothing constant, turning a 0.35 s envelope into an effective 5 s one. Sampling
every frame took r from 0.51 to 0.999. The route had been correct throughout.

### MEN.3 — the divergence: stem-region placement (2026-08-04)

Matt's live viewing of the faithful base: "not moving with the music in a clearly
understandable manner — it looks random and is too much." That is not a defect in the
port. §3 says of the source's mechanism "no listener can perceive the mapping", so a
faithful port of an inaudible placement reads as random BY CONSTRUCTION. MEN.2b's job was
to establish the distribution the wave sim needs and to prove that point with evidence
rather than argument; both are done, and this is the replacement §5 declared up front.

**The claim is now measured, not asserted.** `MeniscusStemDropsTests` drives the committed
real-music fixtures and holds three properties:

| | so_what | there_there | love_rehab |
|---|---|---|---|
| all four regions fire | yes | yes | yes |
| mean row v — vocals / bass / drums | — | 0.19 / 0.47 / 0.81 | 0.19 / 0.49 / 0.82 |
| impacts per second | 4.7 | 4.2 | 7.5 |

The ordering is §5's layout exactly (vocals far, bass centre, drums near), and the density
sits inside the range MEN.2b measured — which is precisely what §2 reason 2 said the
faithful base was for: making that a NUMBER before changing what decides the drops.

**A harness defect surfaced first, and it is the more transferable finding.** Vocals and
`other` measured ZERO impacts across all three tracks. The routes were fine;
`WitchlightFixtureDrive` mapped only `drumsEnergyDev` and `bassEnergyDev` and silently
zeroed the rest, so any preset reading the other two stems would look dead. The fixtures
have carried those columns all along. The drive now maps all four deviations plus the four
per-stem beat pulses — a fix that benefits every future stem-driven preset, not just this
one. Checking the drive's mapping before diagnosing the preset is the rule that caught it.

**Blur was a units error, not taste.** Matt: "a blurry object". The spread was an absolute
NDC value, which says nothing about whether neighbouring rows merge — at the resting camera
the rows sit ~0.014 NDC apart while the spread was 0.033, more than twice the gap, so every
line bled into both neighbours. It is now a FRACTION OF PROJECTED ROW SPACING, which is
scale-free across camera distance and grid resolution and therefore also survives the §6
resolution decision that is still open.

**Two metrics had to be corrected, both mine.** The `disturbed %` figure thresholds against
the field's own peak, so a uniformly LOW field reads as 79 % disturbed while being calmer
in absolute terms (rms 0.105 -> 0.056) — read absolute rms alongside it. And the harness's
footprint floor was a fraction of frame area, which silently encoded how THICK the lines
are; narrowing the spread tripped it at 1562 px on a good render. It is now an absolute
presence floor, because presence is the question it asks.

**STILL OPEN — the camera.** Matt: "I'm also not understanding the camera moving in and
out — is the camera motion tied to musical signal too?" **The dolly is not**: it is a free
19 s sine, ported faithfully from the source, and nothing about it responds to audio. The
tumble IS beat-driven but re-aims only ~45x/minute with each axis every ~5.4 s, so it drifts
more than it articulates. §5's own routing table already specifies the fix (dolly -> mood
`arousal`, re-aim -> cached `BeatGrid` bar phase), and FA #67 now REQUIRES it: with drops on
per-stem onsets, the camera sharing an event-timescale primitive puts two visual layers on
one primitive. Not changed here — it is a product call about what the camera should mean.

### MEN.2b — drops: force law read from the source, then calibrated (2026-08-03)

Four rounds of guessing the force scale missed the drop rate by more than 100x (297-522,
713-838, 9.7-569, 1800 /s against a legible ~0.5-240). Matt's call: read the constant from
the source file. Doing so replaced guesses with the actual law, and corrected **five**
things at once — the earlier attempts were not near-misses on a scale factor, they were
the wrong construction:

| | my guesses | the source |
|---|---|---|
| spectrum conditioning | none, or a normaliser I invented | **AGC: subtract the spectrum mean, divide by a TEMPORALLY SMOOTHED energy level** |
| transform output | used instantaneously | **accumulated per bin with `dec_f = 0.8^(30/fps)`** |
| bins stamped | all 30 | **`flen/2` = 15, starting at index 1** |
| force law | `magnitude x gain` | **`amp = 3(cx²+cy²)`, gated `above(amp, 0.02)`, force ∝ `sqrt(amp)`** |
| stencil weights | 1.0 / 0.8 / 0.5 | **`1/(1+dx²+dy²)`** — 1, 1/2, 1/3 |
| position | a tanh squash I invented | **plain modulo wrap** |

The AGC is the headline: it is why the source is loudness-independent WITHOUT being
scale-free, and its absence is what made raw magnitude track-dependent (9.7 /s on quiet
jazz, 569 /s on loud electronic) while my per-frame across-bin normaliser went scale-free
and fired everything. It also resolves the FA #31 question cleanly — the source AGCs the
SPECTRUM ITSELF, so its `above(amp, 0.02)` is a threshold on normalised transform output,
not on AGC'd band energy. The rule never applied.

Also corrected: the AGC statistics run over `reg01` = 126 taps while the transform uses
`flen` = 30. Using 30 for both makes the level ~2x too small.

**CALIBRATED AND ENABLED (2026-08-03).** Two things had to be measured, and one of them
turned out to be a defect in the measurement rather than the code.

**1. The units conversion.** Every source constant is in Milkdrop's spectrum units;
`FFTProcessor`'s magnitudes have a different scale, so the `600` in the level update does
not transfer. `amp` scales as 1/level², so the multiplier follows in closed form from where
`amp` actually sits against the source's 0.02 gate. `MeniscusCalibrationProbe` measures it:
7.4x / 16.7x / 24.9x for so_what / there_there / love_rehab. The 3.4x spread is the MUSIC
differing — a spectrally busier track should place more drops — so `dropSpectrumScale` takes
a middle value (10) rather than flattening them.

**2. The rate metric was the defect.** Gating on stamp events read 513-840 /s and looked
like anti-reference 8. It was counting the same ripple repeatedly: at 611 stamps/s
love_rehab has only **39 distinct sites**, each sustained ~15 frames. Gating on new-site
ONSETS gives **1.1 / 22.3 / 39.0 per second** across sparse jazz, rock and dense electronic —
all legible, and the spread reads as musical differentiation. Four rounds of "the port is
wrong" were partly four rounds of the wrong instrument.

**3. Localisation is a property of DAMPING, not impact strength.** With drops enabled the
whole plate churned — anti-reference 4. Sweeping drop force changed amplitude but left 63-84 %
of the grid disturbed at every setting, because ripples crossed the torus before dying. The
cause was MEN.2a's guessed `damping = 0.995` (1/e over ~200 frames); the source damps with
the same `dec_med` it uses elsewhere, ~0.97 at 60 fps (~33 frames). Applying it drops the
disturbed fraction to **28 %** — "at any moment most of the surface is quiet and one or two
regions are actively rippling", which is T4 stated exactly.

`dropsEnabled` now defaults **true**, and `MeniscusMultiFrameRenderTest` gained a real-music
drive (`MENISCUS_TRACK=<fixture>`) because at silence there is no spectrum and the ported
behaviour is invisible.

**Not filed as a numbered BUG, deliberately.** BUG-080 is held by the unmerged
`claude/bug080-worktree-weights` branch and BUG-081 by the FTR.2 session (Matt,
2026-08-03) — neither is visible in this tree, so `DocIntegrityTests` rejects the hole
either way, and with two sessions consuming numbers concurrently a third collision is
likely. Claim a number at merge time; this section is the record until then.

**What this means for the increment series.** The MEN.2a stub reproduces the raster and
the slope shading and essentially nothing else: it has a fixed hue where the source
rotates, a bounded heading where the source tumbles, a frame-filling plate where the
source floats one, and a uniformly agitated surface where the source is flat with a
localized disturbance. The gap is not tuning distance.

---

## §10. References

- [`docs/VISUAL_REFERENCES/meniscus/README.md`](../VISUAL_REFERENCES/meniscus/README.md)
- [`docs/PRESET_SESSION_CHECKLIST.md`](../PRESET_SESSION_CHECKLIST.md)
- [`docs/MILKDROP_STRATEGY.md`](../MILKDROP_STRATEGY.md) §12 — the inspired-by framing
- `docs/presets/NACRE_PLAN.md`, `FLORET_PLAN.md`, `GLAZE_PLAN.md` — the three prior
  Milkdrop-inspired plans; Meniscus deliberately departs from their `mv_warp` register
- D-105 / D-111 / D-116 / D-120 / D-121 (inspired-by posture, provenance, discipline
  rule, taxonomy, divergence rule); D-026 / FA #31 (deviation primitives); D-029
  (one paradigm); D-037 (silence never black); D-097 (siblings, not subclasses);
  D-157 / D-158 (flash-safe beat motion); D-186 / D-188 (the material-fidelity
  retirements this preset is designed to avoid)
