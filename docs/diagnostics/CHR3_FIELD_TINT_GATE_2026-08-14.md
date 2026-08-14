# CHR.3 task 1 — the field-tint gate (D4), answered (2026-08-14)

**Question, as `STAVE_DESIGN.md` §7 / D4 posed it:** can a viewer see the field change when
the stem balance changes, at 3.0 s latency and diffuse?

**Answer: YES — readable, decisively, on every capture tested.** The tint is not a subtle
effect that needs hunting for; it is an unmistakable cool↔warm swing of the whole frame.
CHR.3 proceeds. D-216 option A (drop stems entirely) does **not** become live.

But the gate did not pass on the drive the spike started with, and it forced two
corrections that are written back into `STAVE_DESIGN.md` in the same increment.

---

## 1. The drive is a raw-energy SHARE, not `energyRel`

`STAVE_DESIGN.md` §6 and the reference README both name the tint drive as
"`drums+bass` vs `vocals+other` (stems)" without saying **which** stem primitive. CHR.2's
spike used `energyRel`. Measured before rendering, that is the wrong choice, for a
mechanical reason:

`StemAnalyzer` computes `energyRel = (energy − runningAvg) × 2` against a **per-stem** EMA
with τ ≈ 10 s. A sustained drum-led section therefore drives *its own* running average up
and pushes `drumsEnergyRel` back toward zero — the balance self-cancels on exactly the
timescale a field tint lives at. (This is the same τ-relaxation reasoning recorded in
`StemAnalyzer.swift` for the Slint outro, applied to a difference rather than a level.)

Two candidate drives, each smoothed 3 s and decomposed over 20 s sections:

- **REL** = `mean(drumsEnergyRel, bassEnergyRel) − mean(vocalsEnergyRel, otherEnergyRel)`
- **RATIO** = `(drumsEnergy + bassEnergy) / (all four raw energies)`

| capture | chain | REL eta² | REL d | **RATIO eta²** | **RATIO d** |
|---|---|---|---|---|---|
| Bohemian Rhapsody (pre-BUG086.1) | — | 0.185 | 1.82 | **0.560** | **3.98** |
| Clair De Lune (pre-BUG086.1) | — | 0.117 | 1.46 | **0.309** | **2.92** |
| Around the World (post-fix) | degraded | 0.194 | 2.12 | **0.445** | **3.41** |
| Stayin' Alive (post-fix) | degraded | 0.135 | 1.75 | **0.280** | **2.97** |
| Billie Jean (post-fix) | degraded | 0.176 | 1.73 | **0.256** | 1.77 |
| Carry The Zero (local) | **clean** | 0.740 | 4.55 | **0.763** | **5.00** |
| Seven Nation Army (local) | **clean** | 0.636 | 3.14 | **0.644** | 3.11 |

`eta²` = between-section variance / total variance of the smoothed drive; `d` = Cohen's d
between the two most-separated 20 s sections. **RATIO wins on every capture**, by 1.5–3× on
eta². REL's 0.11–0.20 says the deviation difference wobbles inside a section nearly as much
as it moves between sections — it cannot carry section identity, which is the whole job.

**RATIO is not the FA #31 failure.** FA #31 forbids absolute thresholds on AGC-normalised
values, because AGC's denominator moves with mix density. A *share* is scale-invariant:
multiply every stem by any gain and the ratio is unchanged, so AGC drift cancels between
numerator and denominator. What the share is measured against is a **fixed corpus window**
(centre 0.485, tanh scale 0.035) rather than a per-track normaliser, and the seven captures
justify it — section means span 0.447–0.526 and centre near 0.485 across three separate
sessions and two capture paths.

⚠ Caveat on the two clean rows: those sessions are 102–114 s, so only 5 sections each.
With so few groups eta² is upward-biased and the clean-vs-degraded gap is **not** evidence
that chain health drives the result. They are included as clean-chain corroboration that
the effect exists on a healthy chain, not as a comparison.

## 2. The field's own time constant is 8 s, not 3 s

The 3.0 s figure in D-216 is the **stem pipeline's latency**. It is not a prescription for
how fast the field itself should move, and the two were being conflated. Rendered at
τ = 3 s the field visibly churns *inside* a single section — the contiguous within-section
sequence on Around the World swings grey → strong amber → grey across ~20 s.

| field τ | between-section gap | within-section sd | verdict |
|---|---|---|---|
| 3.0 s | 0.59 | **0.168** | churns; the section identity is there but so is a lot of noise |
| 8.0 s | 0.55 | **0.092** | holds a colour family; the section change still reads |

τ = 8 s halves the within-section wobble while costing 7 % of the between-section gap.
**Decided: field τ = 8 s.** This is an implementation choice (CLAUDE.md: engineering
choices are Claude's), recorded here rather than taken to Matt.

## 3. The palette must follow a hue path, not a linear RGB lerp

The spike mixed `cool → warm` with a straight RGB `mix()`. Complementary hues interpolated
that way pass through **desaturated grey** at the midpoint, and since the tint sits near
its midpoint most of the time, the most common state of the field is a grey wash. Visible
in the tau-3 within-section sheet, frames 6–7.

The source does not do this: reference `03_palette_field_hue_drift.png` shows the field
drifting **teal → violet/magenta → warm orange → green** — around a hue circle, saturated
throughout. The production field pass follows a hue path with saturation held up.
This is a spike defect, not a concept defect; it does not affect the gate answer.

## 4. What the frames show

Frames under `/tmp/phosphene_visual/stave_tint/` (not committed — `.gitignore` excludes
diagnostics imagery, same policy as CHR.2 §3). Regenerate:

```
STAVE_TINT_SESSION=<session-or-slice-dir> \
STAVE_TINT_OUT=/tmp/phosphene_visual/stave_tint/<slug> \
STAVE_TINT_SEQ_OUT=/tmp/phosphene_visual/stave_tint/seq_<slug> \
STAVE_TINT_TAU=8.0 \
  swift test --package-path PhospheneEngine --filter StaveFieldTintSpike
```

Slices come from the CHR.2 slicer, rewritten this increment
(`CHR2_LOOK_SPIKE §9.1`). ⚠ **It must write LF, not CRLF** — Swift treats `"\r\n"` as a
single `Character`, so `split(whereSeparator: { $0 == "\n" || $0 == "\r" })` does not split
a CRLF file at all and `StaveReplay` parses zero frames. The first slice run hit exactly
this and read as "no data" rather than as a line-ending fault.

- **The extreme pair** (most melodic-led 20 s section vs most rhythm-led, same capture):
  on all four multi-section captures this is a deep slate-teal frame against a warm amber
  one. There is no ambiguity — the two are different rooms.
- **The full-track strip** (16 frames evenly across the track): Bohemian Rhapsody runs
  teal → amber → grey → blue → tan → blue, obviously varying, and the amber block lands on
  the opening three sections.
- **Motion gate** on the τ = 8 s within-section sequence: mean/stdev 0.14/0.06, **0 spikes
  / 119**. It reports 119/119 "frozen", which is correct and expected — this is the tint
  **alone**, a near-static gradient, with the traces deliberately absent. That reading is
  not transferable to the finished preset and the task-7 motion gate re-runs on the
  full render.

## 5. One honest qualification, carried forward rather than resolved

On material where the named stems do not exist, the share still moves and still tints.
Clair De Lune is solo piano and its tint sits high ("rhythm-led") for most of the track —
the separator is putting the piano's low register into the bass/drums pair. Bohemian
Rhapsody's a cappella opening likewise reads rhythm-led.

This is the same false-label mechanism D-216 found fatal on the traces, appearing on the
field. **It is materially weaker here, and that is the reason D-216 works:** the tint makes
no per-mark claim, so a viewer reads "the room changed" — which is true — rather than
"that mark is a snare", which was false. The preset asserts nothing about instruments, per
L4. Recorded so the next reader does not rediscover it and mistake it for a new defect.
