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
