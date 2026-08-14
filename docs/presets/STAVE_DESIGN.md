# Stave — design doc

**Increment:** written at **CHR.1.3** (2026-08-14), the design-doc half of CHR.1 that its
task-4 hard stop correctly withheld until the driver was settled and gated.
**Status:** authoritative input for **CHR.3**. Not yet reviewed by Matt — §10 is the list
of things he has to answer before CHR.3 should start.
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
| L1 | **Two traces**, rhythm vs melodic. Not four. | CHR.1 measurement, Matt |
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

**Recommendation: (c)**, because it needs no bar-position knowledge and the beat-sync
program has repeatedly shown bar inference to be the expensive part. (a) and (b) both
depend on a quantity the corpus says is unreliable.

## 6. Audio routing — one primitive per layer (D-026, FA #67)

| Visual layer | Primitive | Timescale | Status |
|---|---|---|---|
| Rhythm trace height | `subBass + lowBass`, EMA-centred | ~0.3 s | measured live at CHR.2 |
| Melodic trace height | `midHigh + highMid + high`, EMA-centred | ~0.3 s | measured; **needs per-trace gain** |
| Vertical rules | cached `BeatGrid` beat times | in-time | measured, 0 ms median |
| Field tint | `drums+bass` vs `vocals+other` (stems) | ~3.0 s | **D-216** |
| Bead size / sparkle | *unassigned* — see §10 Q3 | — | open |

No layer shares a primitive with another, and no two share a timescale.

**Per-trace gain is a requirement, not a tuning knob.** Melodic std is **4.4–17.5×** below
rhythm across the corpus; at a shared gain the melodic trace is a flat line. CHR.2 used
fixed gains deliberately, to test whether one pair survives the excursion span — it does
not (Dance Yrself Clean clips off frame). CHR.3 must choose:

- **running per-trace normaliser** — both traces always legible; **cost:** loud and quiet
  passages look the same, so the plot stops reporting absolute level; or
- **fixed gain + soft saturation** — level survives, extremes compress rather than clip.

**Recommendation: fixed gain + soft saturation**, tuned against p99 not 1.0 (deviation
primitives spike to ~3× on real music). It keeps "the music got louder" readable, which is
half of what a plot is for.

## 7. Design grounding (descending preference, per the checklist)

| Mechanism | Grounding | Level |
|---|---|---|
| Beaded trace on a ruled field | `Martin - charisma`, rendered and curated at CHR.1.3 | **1** — working reference |
| CPU history ring → `ParticleGeometry` | `WitchlightStroke` / `WitchlightPath`, shipped and certified | **1** |
| Band-driven position, EMA-centred | `BandDeviationTracker` (D-146), and CHR.2's live renders | **1** |
| Beat-ruled verticals from `BeatGrid` | CHR.2 measured against `grid_bpm` on four captures | **1** |
| Stem-driven field tint | **3 — no empirical grounding.** D-216 reasons that a 3.0 s lag is invisible on a slow surface. That is an argument, not a measurement; nothing has rendered it. | **3** ⚠ |

⚠ **Surfaced per the checklist rather than resolved:** the field tint is the one
load-bearing mechanism at grounding level 3. It is also the mechanism D-216 just moved the
whole stem story onto. **The cheapest way to de-risk it is to render the tint alone against
a capture before building the rest of CHR.3** — a half-day, and it answers "can a viewer
read the stem balance at all when it is this slow and this diffuse?" If the answer is no,
option A from D-216 (drop stems entirely) becomes live again and CHR.3 should know that
before it builds a field pass around them.

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

## 10. Open decisions for Matt

**Q1 — Is the curated reference set right?** `docs/VISUAL_REFERENCES/stave/README.md` is my
reading of the source render, unconfirmed. Every trait CHR.3 builds to comes from it.

**Q2 — Trace count.** Two is what CHR.1's measurement supports as separable. The source
runs 4–8, which is denser and more source-like but reintroduces the collapse CHR.1
measured. Two is the recommendation; it is also a thinner picture than the source.

**Q3 — What drives bead size and sparkle?** §6 leaves them unassigned deliberately, because
every fast primitive is already spoken for and FA #67 forbids doubling up. Options: leave
them non-reactive (texture only), or spend the one remaining fast primitive
(`spectralFlux` / `beatComposite`) on sparkle density.

**Q4 — Should CHR.3 open with the field-tint spike (§7)?** It is the only grounding-level-3
mechanism and it carries the entire post-D-216 stem story. Recommendation: yes.

**Q5 — The source-JSON commit question** in the reference README's §Provenance — Nacre
commits its butterchurn source JSON, this set does not. Ambiguous under D-116 bullet 4,
which names `.milk` specifically.
