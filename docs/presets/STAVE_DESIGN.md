# Stave — design doc

> ## ⚠ SUPERSEDED BELOW THE LINE — read this banner first (CHR.3b, 2026-08-16)
>
> **Everything in §§1–11 describes the FIRST Stave: two band-driven traces plotting an 8 s
> scrolling window on a beat-ruled field, with the stems tinting the room.** Matt's live M7 on
> 2026-08-16 rejected it — *"deeply boring"*, *"not sure what is being plotted"*, *"what is the
> purpose of the horizontal and vertical grid lines?"*, *"why the starry background — I don't
> think it's necessary"*. He then declined retirement (*"you have to make it work"*) and gave
> the concept it has now:
>
> > **"align the visible light spectrum to the frequency spectrum for this preset."**
>
> ## What Stave is now
>
> The live waveform, split into eight bands, each drawn in the colour of its own frequency —
> 82 Hz at 662 nm deep red through to ~11 kHz at 404 nm violet, one pass across the visible
> band, compressed rather than octave-wrapped. Additive, so a full spectrum sums toward white
> like mixed light. Bands are offset by wavelength so the spectrum separates as a prism
> separates light, and **that separation is driven by how much signal is on screen** — quiet
> converges to a tight ribbon, loud opens to full spectrum.
>
> ## Why the old design failed, mechanically
>
> The preset is `family: waveform` and **never read the waveform**. It plotted EMA-centred band
> energy — an envelope statistic — and every stage removed life: 20 Hz decimation killed
> everything fast, EMA-centring removed level, soft saturation compressed the dynamics, the 8 s
> window smeared what was left. It also had no channel slower than ~0.3 s except the stem tint,
> so it could not tell one part of a song from another: the M7 track had five sections and a
> 4× arousal climb and the preset read none of it.
>
> ## What is gone, and why
>
> | Removed | Reason |
> |---|---|
> | Star sparkles | Matt: not necessary. Non-reactive; existed only because the source render had them. |
> | Static horizontal rules | They existed because the preset is called Stave. A pun is not a design reason. |
> | Beat vertical rules | They scrolled away with the plot, so they never read as a beat. |
> | Beads | Matt: *"beads are not necessary."* |
> | Stem field tint (D-216) | Matt: *"probably unnecessary"* — and **contradictory**: colour now means frequency, and colour cannot mean two things at once. This is D-216's rejected option A arriving on its own merits. |
> | The scrolling 8 s window, time axis, haze, cloud | Went with the plot. |
>
> ## Locked decisions that SURVIVE
>
> L1 (two voices, low against high) survives generalised — the spectrum has eight bands and low
> against high is its two ends. L2 (band-driven, in-time) survives and is now literal: the raw
> signal, every frame. L5's "no autonomous motion" survives as a property rather than a rule —
> a silent buffer draws a flat wave, gated by `silentWaveformIsFlat`. **L3/L4/L6/L7 are retired**
> along with the stems, the rules and the beads.
>
> ## Settled parameters, all from rendered sweeps on real audio (not taste)
>
> | Parameter | Value | Why |
> |---|---|---|
> | band widths | 320, 224, 160, 112, 72, 40, 16, 4 | Not one per octave: even spacing clumped three bands above 3 kHz into a purple mass. Five bands cover 69–550 Hz where the energy is. |
> | `scale` | 1.7 | 0.85 left a thin strip in the middle; 2.8 overflowed into wall-to-wall fringe. |
> | `tilt` | 0.45 | Full compensation made the top bands a dense spiky comb; this leaves the spectrum bass-weighted the way music is. |
> | `spacing` | 0.5 | Weights the spread toward the reds so the bass has room to be a gesture. |
> | `fanMin`/`fanMax` | 0.02 / 0.40 | Driven, not fixed — a fixed fan collapsed Take Five into a static rainbow layer cake. |
> | `levelTau` | 20 s | Long enough that a quiet passage still draws quieter; short enough to settle a track change. The spike used whole-track gains, which production cannot have. |
>
> ## Frame fit (CHR.3e, Matt's M7 2026-08-17 — *"looks good … otherwise, it works for me"*)
>
> First positive M7. One change asked for: *"the camera should zoom out 2-5% so that when there
> is highly energetic music, the waves do not fall outside of the frame"*, then clarified —
> *"I want the waves to cover most of the vertical area of the frame, as they do now. I think a
> zoom of 35-50% is likely excessive."*
>
> **Measured before choosing, and the two halves of the first instruction conflicted.** Peak
> `|y|` across the corpus was **1.53–1.98** against a frame of 1.0, so containing the peaks by
> zoom alone needs 35–50 % — the amount he then ruled out. A literal 4 % zoom moved peak
> 1.83 → 1.75 and overflowing frames 125 → 113 out of 360: essentially nothing.
>
> **Shipped instead: a piecewise soft ceiling at 0.75 NDC, zoom left at 1.0.** Below the knee
> the value passes through untouched; above it the excursion folds into the remaining headroom.
> A plain `tanh` was tried and rejected — it compresses through the origin and shrank
> mid-amplitude by 12 %, quietly reducing the approved look.
>
> | | peak before | after | frames outside frame |
> |---|---|---|---|
> | M7 session | 1.83 | 1.000 | 125/360 → **0** |
> | Carry, loudest | 1.66 | 1.000 | 231/360 → **0** |
> | Bleed | 1.53 | 0.999 | 48/360 → **0** |
> | Clair De Lune | 1.98 | 1.000 | 8/360 → **0** |
> | Take Five | 0.51 | 0.510 | 0 → 0, **unchanged** |
>
> Take Five is the control: it never approached the edge and comes through bit-identical, so
> nothing quiet is touched.
>
> **Also confirmed by that session:** `waveform_occupancy` published live on 2031/2032 frames,
> live range 0.067–0.153 against 0.073–0.124 measured offline — the CHR.3c primitive behaves
> identically in production. It also confirms the fan saturation item below: on Carry The Zero
> the fan sits at 0.377–0.400 of a 0.400 ceiling throughout.
>
> ## Open items carried into CHR.4
>
> 1. **QG.1 cannot gate this preset.** Its only driver is the engine's waveform buffer, which is
>    not a session-recordable primitive, so `audio_routes` is empty and `RouteCoverageTests`
>    has nothing to assert. Declaring routes the code does not read would be worse than
>    declaring none. **This blocks certification** (`certifiedPresetsDeclareAudioRoutes`) and
>    the fix is a routable waveform-derived primitive, which is engine work.
> 2. **The fan saturates on loud material** — Carry The Zero and Bleed both sit at 0.38–0.40 of
>    a 0.40 ceiling, so the spread has no headroom left on dense tracks. Clair De Lune, with
>    real dynamics, swings 0.16–0.40 and uses the range properly.
> 3. **Dispersion is expressive, not optical.** A real prism's separation is fixed by its
>    material and does not breathe with level. Accepted deliberately.
>
> ---


**Increment:** written at **CHR.1.3** (2026-08-14), the design-doc half of CHR.1 that its
task-4 hard stop correctly withheld until the driver was settled and gated.
**Status:** authoritative input for **CHR.3**. Every open item is decided in §10; nothing
here is waiting on Matt. What comes to him is a render, not a document (§11).
**Preset count:** 28. Nothing registered yet.

**Inputs this doc rests on, in order of authority:**

| Source | What it settles |
|---|---|
| [`DECISIONS.md` D-216](../DECISIONS.md) | Stems come off the traces onto the field. No per-mark instrument identity. |
| [`CHR2_LOOK_SPIKE_2026-08-14.md`](../diagnostics/CHR2_LOOK_SPIKE_2026-08-14.md) | The gate result and every number below. |
| [`CHR1_STEM_DECORRELATION_2026-08-11.md`](../diagnostics/CHR1_STEM_DECORRELATION_2026-08-11.md) | Why two traces and not four. **Read its correction banner.** |
| [`VISUAL_REFERENCES/stave/README.md`](../VISUAL_REFERENCES/stave/README.md) | The look, per-image, with anti-references. |
| [`STAVE_PLAN.md`](STAVE_PLAN.md) | Sequencing. Its §0 predates D-216 — the amendment block wins. |

---

## 1. Musical role (locked by D-216, 2026-08-14)

> **The low end and the top end of the mix are two voices writing across a page that is
> ruled by the beat, in a room the stems tint.**

The specific musical feature and the specific visual behaviour, as the checklist requires:

- **Beat** → the field's vertical rules land on cached `BeatGrid` beats. Measured, not
  aspirational: CHR.2 found median trace-to-beat offset **0 ms** on all four captures, and
  derived gridline rate matching `grid_bpm` exactly (71/71, 97/98, 172/174.6).
- **Low-band energy** (`subBass+lowBass`, EMA-centred) → the rhythm trace's height, now.
- **High-band energy** (`midHigh+highMid+high`, EMA-centred) → the melodic trace's height,
  now. The two are near-independent (r −0.27…+0.27 on 13 of 15 corpus tracks), so they
  read as two voices rather than two copies.
- **Stem balance** (`drums+bass` vs `vocals+other`) → the field's tint, slowly. A listener
  reads it as *the room is warmer during the chorus*, never as *that mark is a snare*.

**What this role deliberately does NOT claim**, per D-216: that a viewer can tell which
instrument a trace is carrying. That claim was tested at CHR.2 and failed on a measurement.

## 2. Three-part bar

1. **Iconic visual subject deliverable at fidelity** — the subject is a plotted trace on a
   ruled field. It is 2D line/ribbon work with beads and a tinted backdrop; nothing here
   needs a material stack, a G-buffer or a light rig. The nearest shipped comparison is the
   existing `Waveform` scaffold, which clears the geometry trivially. **Cleared, and this
   is the least risky part.**
2. **Clear musical role** — §1. **Cleared.**
3. **Infrastructure-feasible** — CPU history rings → `ParticleGeometry`, the
   `WitchlightStroke` pattern, already demonstrated end-to-end by the CHR.2 spike on real
   captures. No new engine surface, no GPU contract change, no `SpectralHistoryBuffer`
   extension. **Cleared, and demonstrated rather than asserted.**

## 3. Locked decisions

| # | Decision | Source |
|---|---|---|
| L1 | **Two driven traces**, rhythm vs melodic. Not four. Optional non-semantic ghost companions for density (D2). | CHR.1 measurement, Matt |
| L2 | **Position from bands** (~0.3 s), EMA-centred, never absolute AGC values (FA #31) | Matt 2026-08-13 |
| L3 | **Stems tint the field only.** Never a trace's hue, weight or brightness. | **D-216** |
| L4 | **No per-mark instrument identity.** The concept sentence is §1. | **D-216** |
| L5 | **No autonomous motion.** Quiet passages flatline; that is the design. | STAVE_PLAN §CHR.2 |
| L6 | **Vertical rules = beat; horizontal rules = the stave**, static. | this doc, §5 |
| L7 | **Beaded traces, not solid lines.** | reference `02_meso`, anti `05` |

## 4. Rendering architecture

**Paradigm:** `particles` + `feedback` (one paradigm per preset, D-029 — the particle
geometry is the preset; feedback is the field's smear, not a second concept).

```
CPU (ParticleGeometry.update)          GPU
─────────────────────────────          ───────────────────────────────
2 × history ring (audioTime, y)   →    trace pass    ribbon strips, beaded
beat-wrap times → rule list       →    grid pass     verticals + static horizontals
stem pair EMAs → field tint       →    field pass    tint + haze + sparkle
                                       feedback      slow smear behind traces
```

**Carried verbatim from the CHR.2 spike** (`StaveLookSpike.swift`), each already a fixed
defect rather than a thing to rediscover:

- `packed_float4` / `packed_float2` in the MSL vertex struct. A plain `float4` is 16-byte
  aligned and pads the struct to a 48-byte stride against Swift's 28; the traces render as
  large mis-coloured triangles. Magenta in a flat-*white* control was the tell.
- **Alpha blending, not additive.** ~160 near-collinear ribbon quads saturate to white
  under additive long before the trace is legible. (The *sparkles* may still be additive —
  they are sparse.)
- **Plot at ~20 Hz, not per render frame.** The analyser behind these bands updates at
  ~10 Hz (BUG-087: 16.4 Hz local-file, ~51 Hz streaming), so a 60 Hz plot draws duplicate
  points whose segment direction is numerical noise. Pair with the degenerate-segment
  guard in the vertex shader.
- **Plot on `time`, never `accumulatedAudioTime`** — the latter is energy-weighted by
  definition, ~12× slower than wall-clock and music-dependent. It is an animation phase,
  not a clock.
- **Segment-quad expansion**, because `.lineStrip` cannot carry per-sample thickness.

**New at CHR.3** (not in the spike): bead rendering, the haze/atmosphere layer, sparkles,
the field tint, horizontal rules, and the feedback smear.

## 5. The grid, and the one thing CHR.2 flagged as unresolved

Vertical rules are the beat. Horizontal rules are the stave and are static — this is both
source-faithful (`01_macro` shows a field ruled in both axes) and the literal reading of
the preset's name.

**Unresolved: rule density at high tempo.** CHR.2 measured Bleed at **22.9 verticals per
8 s window** (172 bpm) and the render reads as graph paper rather than pulse. Three ways
out, none costed yet:

- **(a)** Rule on the **bar**, not the beat, above a tempo threshold — but `beatsPerBar` is
  **not stable within a track** (Billie Jean reads 4 in one segment, 3 in another), so bar
  inference needs its own evidence first.
- **(b)** Keep every beat but **weight** them — bright on downbeat, faint between. Same
  `beatsPerBar` problem for the downbeat.
- **(c)** Fade rule opacity as a function of measured on-screen density, independent of
  meter. Meter-free, so no new inference needed; purely cosmetic.

**Decided: (c).** It needs no bar-position knowledge, and the beat-sync program has
repeatedly shown bar inference to be the expensive part. (a) and (b) both depend on
`beatsPerBar`, which the corpus says is unreliable within a single track.

## 6. Audio routing — one primitive per layer (D-026, FA #67)

| Visual layer | Primitive | Timescale | Status |
|---|---|---|---|
| Rhythm trace height | `subBass + lowBass`, EMA-centred | ~0.3 s | measured live at CHR.2 |
| Melodic trace height | `midHigh + highMid + high`, EMA-centred | ~0.3 s | measured; **needs per-trace gain** |
| Vertical rules | cached `BeatGrid` beat times | in-time | measured, 0 ms median |
| Field tint | `drums+bass` **raw-energy share** of all four stems, 8 s EMA | ~3.0 s pipeline + 8 s field | **D-216**; drive corrected at CHR.3 |
| Bead size | trace's own local slope — *derived geometry, not an audio primitive* | — | D3 |
| Sparkle | **non-reactive** texture, slow drift | — | D3 |

No layer shares a primitive with another, and no two share a timescale.

**Per-trace gain is a requirement, not a tuning knob.** Melodic std is **4.4–17.5×** below
rhythm across the corpus; at a shared gain the melodic trace is a flat line. CHR.2 used
fixed gains deliberately, to test whether one pair survives the excursion span — it does
not (Dance Yrself Clean clips off frame). CHR.3 must choose:

- **running per-trace normaliser** — both traces always legible; **cost:** loud and quiet
  passages look the same, so the plot stops reporting absolute level; or
- **fixed gain + soft saturation** — level survives, extremes compress rather than clip.

**Decided: fixed gain + soft saturation**, tuned against p99 not 1.0 (deviation primitives
spike to ~3× on real music). It keeps "the music got louder" readable, which is half of what
a plot is for; a running normaliser would make loud and quiet passages look identical.

## 7. Design grounding (descending preference, per the checklist)

| Mechanism | Grounding | Level |
|---|---|---|
| Beaded trace on a ruled field | `Martin - charisma`, rendered and curated at CHR.1.3 | **1** — working reference |
| CPU history ring → `ParticleGeometry` | `WitchlightStroke` / `WitchlightPath`, shipped and certified | **1** |
| Band-driven position, EMA-centred | `BandDeviationTracker` (D-146), and CHR.2's live renders | **1** |
| Beat-ruled verticals from `BeatGrid` | CHR.2 measured against `grid_bpm` on four captures | **1** |
| Stem-driven field tint | **Level 1 as of CHR.3** — rendered and measured, [`CHR3_FIELD_TINT_GATE_2026-08-14.md`](../diagnostics/CHR3_FIELD_TINT_GATE_2026-08-14.md) | **1** ✅ |

✅ **D4 gate answered at CHR.3: the tint is readable, decisively**, on all six captures
tested including two at the actual post-BUG086.1 3.0 s latency. The extreme-section pair is
a deep slate-teal frame against a warm amber one — no ambiguity. D-216 option A does not
become live. **Three corrections the gate forced**, all now reflected above:

1. **The drive is a raw-energy SHARE, not `energyRel`.** `energyRel` is centred on a
   *per-stem* 10 s EMA, so a sustained section self-cancels. Between-section variance
   share (eta²) of the smoothed drive: RATIO **0.26–0.76** vs REL 0.11–0.20, RATIO winning
   on every capture. A share is scale-invariant, so it is not the FA #31 failure — AGC
   drift cancels between numerator and denominator. Mapped through a fixed corpus window
   (centre 0.485, tanh scale 0.035); section means span 0.447–0.526 across three sessions.
2. **The field's own time constant is 8 s.** D-216's 3.0 s is the *stem pipeline's
   latency*, not a prescription for how fast the field moves; the two were conflated. At
   τ = 3 s the field churns inside a single section (within-section sd 0.168); at τ = 8 s
   that halves to 0.092 while the between-section gap only falls 0.59 → 0.55.
3. **The palette follows a hue path, not a linear RGB lerp.** Complementary hues mixed in
   RGB pass through desaturated grey at the midpoint — which is where the tint sits most of
   the time. Reference `03_palette_field_hue_drift.png` drifts around a hue circle
   (teal → violet → orange → green), saturated throughout.

⚠ **Carried forward, not resolved:** on material where the named stems do not exist the
share still moves and still tints (Clair De Lune, solo piano, reads "rhythm-led"). This is
the D-216 false-label mechanism reappearing on the field — but materially weaker, and that
is precisely why D-216 works: the tint makes no per-mark claim, so the viewer reads "the
room changed" (true) rather than "that mark is a snare" (false). L4 still holds.

## 8. Phased plan for CHR.3

1. Field tint spike — grounding-level-3 mechanism first, per §7. Gate: can the stem balance
   be read at all?
2. Registration (`NEW_PRESET_CHECKLIST.md`), sidecar, `ParticleGeometryRegistry` case,
   count 28 → 29, `expectedProductionPresetCount` bumped in the same commit.
3. Beads + trace treatment against reference `02_meso`; per-trace gain per §6.
4. Grid: verticals + static horizontals, density treatment per §5.
5. Atmosphere, sparkle, feedback smear.
6. `audio_routes` manifest + `RouteCoverageTests`; QG.5 response bands; D-157 flash gate
   wired at authoring time, not at certification (the Meniscus lesson).
7. `compare_render.sh` + `motion_gate.sh` before requesting M7.

## 9. Divergence from the source (D-116 bullet 3, D-121)

The rendered output must differ measurably on at least one axis. Stave differs on three:

- **Primary feature stack** — the source's rules are decoration; Stave's verticals are the
  actual beat from a cached `BeatGrid`. Milkdrop has no beat grid and no stems, so this is
  structurally unavailable to the source.
- **Compositional structure** — 4–8 overlapping traces in the source, **2** semantically
  assigned traces in Stave.
- **Dominant motion model** — the source's traces are waveform-driven per-frame geometry;
  Stave's are a scrolling CPU history ring over an 8 s window.

Palette character is the axis Stave does **not** currently diverge on, and it should not be
relied upon.

## 10. Decisions taken here

These were briefly written up as questions for Matt. That was wrong — each one needs
implementation knowledge to answer, which per CLAUDE.md makes it mine. Recorded with
rationale so CHR.3 does not reopen them.

**D1 — The reference set stands as curated.** Five annotated images from a fresh render of
the source, each trait checked against the image it cites (one reading was corrected in the
process: the sparkles are scattered, not nodal). Matt's input on this preset is the
qualitative read of a *render*, at M7 — not validation of my annotations.

**D2 — Two driven traces, plus non-semantic density.** CHR.1 measured that more than two
collapse (65–93 % common mode). But the source's 4–8 traces are not voices either — they
are an undifferentiated cyan *texture*. So: **two semantically driven traces** (rhythm,
melodic) **plus optional ghost companions** that are offset/delayed copies of those same
two, carrying no independent signal. That buys the source's density without asserting
voices the data says do not separate. Ghosts are dimmer and thinner; if they read as extra
voices in review, they come out.

**D3 — Bead size rides the trace's own slope; sparkles are non-reactive.** Bead size from
local trace velocity is a *derived geometric* quantity, not a new audio primitive — it
costs nothing against FA #67 and reads as "the line is moving fast here." Sparkles stay
**non-reactive** texture (constant density, slow drift). The preset already carries four
well-separated audio layers; a fifth route on a diffuse field element is where the
"fighting itself" failure starts, and the remaining fast primitives (`spectralFlux`,
`trebDev`) overlap the melodic trace's own band content.

**D4 — CHR.3 opens with the field-tint spike.** It is the only grounding-level-3 mechanism
(§7) and it carries the whole post-D-216 stem story. If the stem balance cannot be read at
3.0 s on a diffuse surface, that is worth knowing before a field pass is built around it.

**D5 — Commit the source JSON, following the Nacre precedent.** D-116 bullet 4 names
`.milk` files and the pack at its source URL; a butterchurn built-in is MIT-licensed npm
package content, and D-215 requires the sha256 *of the artifact actually read*, which
presumes the artifact is identifiable. `docs/VISUAL_REFERENCES/nacre/` commits
`source_preset.json` and six other shipped inspired-by presets set the same practice.
Consistency across reference sets beats my private conservatism, and a set that diverges
from precedent for unstated reasons is its own hazard.

## 11. What actually comes to Matt

Nothing in this doc. The next thing for him is a **render** — the field-tint spike from D4,
then the CHR.3 look — where the question is the one he is the authority on: *does it read,
and does it feel like the music?*
