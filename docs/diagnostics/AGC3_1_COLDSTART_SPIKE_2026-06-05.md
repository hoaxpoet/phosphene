# AGC3.1 — The AGC `f.bass` cold-start band-value spike: measurement (BUG-029)

**Increment:** AGC3.1 (measure). **Date:** 2026-06-05. **No production code change.**
**Status:** evidence produced; brought to Matt for the AGC3.2 decision gate.
**Harness:** [`tools/agc3/measure_coldstart_spike.py`](../../tools/agc3/measure_coldstart_spike.py)
(pure-stdlib, permanent diagnostic; reads the AGC-normalised band values production
*actually shipped* each frame — no re-derivation from FFT, per Failed Approach #27).
**Reference session:** `~/Documents/phosphene_sessions/2026-06-06T01-18-36Z/` — local-file,
5 tracks (Cherub Rock / Alameda / Mingus / two more), 14 771 feature frames.

Run: `python3 tools/agc3/measure_coldstart_spike.py <session_dir> --label LF --stems`

---

## TL;DR

1. **The spike is real and large.** At a track onset preceded by silence, the first
   audible frame's `f.bass` jumps to an **absolute ~3.5–4.0** (steady is ~0.20–0.36) —
   a **11–17× ratio**. Confirmed on 4 of the session's 5 onsets. Matches the filed
   evidence exactly (Cherub Rock 4.003 @ te 1.42; Alameda 3.697 @ te 0.66).
2. **It is gated by the silent pre-roll, not by "session start."** The single onset
   that did *not* spike (track 4, ratio 2.3) had **zero** silent pre-roll — audio
   started on the first frame, so the AGC running average never decayed. Even a
   **one-frame (0.02 s)** gap produced a 4× spike (track 5). The "every track onset"
   claim is **confirmed with a refinement: every onset preceded by any silence gap**,
   which for local-file playback is the common case (4 of 5 here).
3. **The two mechanism modes both fire, and the *inter-track* mode lasts longer.**
   Session-start (frame-0 seed off `1e-6`) recovers in **~0.10 s** because `frameCount=0`
   runs the *fast* warmup rate (0.95). Later onsets, with the AGC already in its slow
   steady-state rate (0.992), spike *longer* — **0.9–1.2 s** — because the running
   average climbs only ~0.8 %/frame back to true. So the per-track recurrence is not
   only present, it is the **worse-feeling** of the two.
4. **Downstream, Ferrofluid Ocean pops to its clamp ceiling.** `fo_spike_strength =
   1.0 + 0.8·clamp(f.bass,0,1)` pins to **1.800** for the spike frames (every spiking
   onset hits `f.bass > 1`), then collapses to **1.16–1.29** as bass settles — a
   **+40–55 % spike-height pop** that drops within 0.1–1.2 s. The exact "pop-and-drop."
5. **The per-stem path does NOT spike** (ratios 0.8–1.4). `StemAnalyzer` holds 4×
   `BandEnergyProcessor` but **resets them per track** (`StemAnalyzer.reset()` →
   `processor.reset()`), re-seeding each stem's AGC from its first audible frame. The
   main-mix `MIRPipeline` processor is the *only* one not reset per track. This both
   explains the asymmetry **and** points at a known-good in-codebase pattern for the fix
   decision (it is Matt's call at AGC3.2, not assumed here).
6. **Coverage gap: streaming path not characterised.** Every recorded multi-track
   session on disk is local-file. The session-start mode is path-independent (frame 0
   off silence is identical); the inter-track mode depends on whether the streaming app
   emits silence between tracks (gapless playback may not). A streaming multi-track
   recording is needed to close this — flagged for Matt.

---

## The mechanism (what the numbers are evidence *of*)

In `BandEnergyProcessor.process(magnitudes:fps:)`
([`PhospheneEngine/Sources/DSP/BandEnergyProcessor.swift`](../../PhospheneEngine/Sources/DSP/BandEnergyProcessor.swift)):

- `totalRawEnergy = raw6.reduce(0, +)` (`:204`); the AGC denominator is an EMA of it:
  `agcRunningAvg = agcRate·agcRunningAvg + (1−agcRate)·totalRawEnergy` (`:210`), with
  `agcRate` = **0.95** for the first 60 frames (`warmupFastFrames`), then **0.992** (`:205`).
- `agcScale = 0.5 / agcRunningAvg` (`:213`) multiplies **every** band (`:216–217`).
- Frame 0 seeds `agcRunningAvg = max(totalRawEnergy, 1e-6)` (`:207–208`).
- `MIRPipeline.reset()` (which would call this processor's `reset()`) is **never called
  per track** (verified `MIR_RESET=0` in the AGC2 work) — so across an inter-track
  silence the denominator simply **decays** toward the silence floor.

Two failure modes follow, both observed:

- **Session start (frame 0 = silence):** seed `1e-6` → `agcScale ≈ 0.5/1e-6` is enormous
  → the first audible frame's bands explode. *But* the fast warmup rate (0.95) pulls the
  denominator up within ~2 frames, so it self-corrects in ~0.10 s (track 1).
- **Every later onset preceded by silence:** during the gap `agcRunningAvg` decays at
  0.992/frame (≈ 1.3 s time-constant). The next onset over-scales — and because the AGC
  is now in *slow* mode, recovery takes **0.9–1.2 s** (tracks 2, 3). Worse-feeling than
  session-start.

The spike is a **global scale** artifact: it inflates whichever bands carry the onset's
raw content (see the per-band table below), not a single band — distinguishing it from a
real kick (which moves `subBass`/`bass` specifically against a *correct* scale).

---

## Evidence table — `f.bass` cold-start spike, per track onset

Session `2026-06-06T01-18-36Z` (LF). `steady` = median active `f.bass` in te ∈ [10, 40] s.
`fo_peak`/`fo_steady` = `1.0 + 0.8·clamp(f.bass,0,1)` at the peak vs steady (the
`cached_bass_proportion` baseline term, ≤ +0.25 and ~constant, is omitted to match the
filed evidence).

| trk | mode | pre-roll s | onset te | **peak f.bass** | steady | **ratio** | spike s | fo_peak | fo_steady |
|----:|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| 1 | session-start | 1.00 | 1.42 | **4.003** | 0.356 | **11.3×** | 0.10 | 1.800 | 1.285 |
| 2 | inter-track | 0.39 | 0.55 | **3.697** | 0.215 | **17.2×** | 0.91 | 1.800 | 1.172 |
| 3 | inter-track | 0.50 | 0.65 | **3.471** | 0.203 | **17.1×** | 1.19 | 1.800 | 1.162 |
| 4 | inter-track | 0.00 | 0.01 | 0.486 | 0.213 | 2.3× | 0.00 | 1.388 | 1.170 |
| 5 | inter-track | 0.02 | 0.02 | 0.874 | 0.220 | 4.0× | 0.00 | 1.699 | 1.176 |

**6-band values at the spike-peak frame** (the global scale inflates whichever bands hold
the onset content — Cherub Rock's opening is a low-bass/low-mid power chord, Alameda's a
sub-bass+bass piano entry):

| trk | subBass | lowBass | lowMid | midHigh | highMid | high |
|----:|--:|--:|--:|--:|--:|--:|
| 1 | 0.127 | **4.385** | **1.760** | 0.273 | 0.302 | 0.036 |
| 2 | **3.985** | **3.989** | 0.485 | 0.316 | 0.193 | 0.161 |
| 3 | **3.158** | **3.766** | 0.511 | 0.061 | 0.047 | 0.030 |
| 4 | 0.452 | 0.527 | 0.045 | 0.009 | 0.003 | 0.001 |
| 5 | 0.620 | 0.928 | 0.131 | 0.063 | 0.053 | 0.026 |

---

## The "every track onset" question — confirmed, with the gating variable named

> **Confirm or refute the "every track onset" claim** (kickoff AGC3.1 step 2).

**Confirmed, refined: the spike fires at every onset preceded by *any* silence gap, and is
absent only when the onset has *no* silent pre-roll.** The magnitude saturates fast — by
~0.4 s of silence it is already near its ceiling (track 2: 0.39 s → 17×), so this is not a
"long-gap-only" artifact; it is "any-gap." For local-file playback an inter-track silence
is the norm (4 of 5 onsets here), so in practice it recurs on essentially every track.

Absolute peak is the *stable* cross-track number (~3.5–4.0); the **ratio varies with the
track's steady level** (a louder track like Cherub Rock has a higher steady, so a smaller
ratio for the same absolute peak). A fix threshold should be set against the **absolute
peak** (and/or the scale), not the ratio.

This **reframes the BUG-025 shelving rationale.** BUG-025 deferred this family as a
"one-time ~2 s session-start flash, not worth a cross-cutting AGC change." The data shows
it is **not one-time**: it recurs per track, and the per-track instances actually *last
longer* (0.9–1.2 s vs 0.10 s) than the session-start one. That re-justifies the work.

---

## Downstream effect — the felt "pop-and-drop"

Ferrofluid Ocean drives spike height from `f.bass` directly
([`FerrofluidOcean.metal`](../../PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.metal)
`fo_spike_strength`, `:175–176`): `return baseline + 0.8 * clamp(f.bass, 0, 1)`. Because the
spike drives `f.bass > 1`, the clamp pins the term to its **max +0.8** for the spike frames:

- Spiking onsets (tracks 1, 2, 3, 5): spike height pops to **1.800** (≈ +0.8 over a ~1.0
  baseline), i.e. **~40–55 % taller** than the settled height (1.16–1.29), then collapses
  within 0.1–1.2 s. A pop, then a drop — exactly the reported artifact.
- Non-spiking onset (track 4): peaks at 1.388 — no pop; the surface simply arrives.

Trajectory excerpt, track 1 (every value is what the shader consumed):

```
te 0.42–1.31  f.bass = 0.000   (silent pre-roll, ~1.6 s)   fo = 1.000   surface flat/static
te 1.42       f.bass = 4.003   (onset spike)               fo = 1.800   POP to ceiling
te 1.52       f.bass = 2.565                                fo = 1.800   still pinned
te 1.87       f.bass = 0.040   (real music gap)             fo = 1.032   DROP
te 2.11       f.bass = 0.497   (settled music)              fo = 1.398   arrived
```

Scope note (kickoff boundary, restated): the pre-roll **staticness** (FFO shows little
motion while `f.bass = 0` during the silent lead-in, since its Gerstner swell is
deliberately slow) is a **separate, preset-level** ambient-motion concern — **not** BUG-029
and not fixable by an AGC change. BUG-029 is the **spike**.

---

## Stem path — measured, and it does NOT spike

| trk | peak bassEnergy | steady | ratio |
|----:|--:|--:|--:|
| 1 | 0.321 | 0.425 | 0.8× |
| 2 | 0.265 | 0.284 | 0.9× |
| 3 | 0.258 | 0.327 | 0.8× |
| 4 | 0.333 | 0.235 | 1.4× |
| 5 | 0.302 | 0.268 | 1.1× |

`StemAnalyzer` runs the **same** `BandEnergyProcessor` per stem (`energyProcessors[0..3]`),
but `StemAnalyzer.reset()` calls `processor.reset()` on each (`StemAnalyzer.swift:355–356`),
which is invoked on track change — so each stem's AGC re-seeds (`frameCount=0`,
`agcRunningAvg = max(firstFrame, 1e-6)`) from its **first audible** frame and never decays
through a silence. The main-mix `MIRPipeline` processor is the only one *not* reset per
track. (BUG-018 / SAR.1's seed-from-first-non-zero handles the orthogonal stem-*deviation*
cold-start; the raw `bassEnergyDev` peaks here are 0.0–0.54, in range — BUG-018 holds.)

**Implication for the fix (for Matt's AGC3.2 call, not decided here):** the per-stem path is
a working, shipped precedent for "reset/re-seed per track so the onset reads against a sane
denominator." Whatever approach is chosen must keep the stem path green (BUG-018).

---

## Capture-path coverage

Characterised: **local-file only.** Every recorded multi-track session currently on disk is
`origin=localFile`. Reasoned expectation for the **streaming (process-tap)** path:

- **Session-start mode is path-independent** — frame 0 off leading silence seeds `1e-6`
  identically, so streaming will show the same session-start spike.
- **Inter-track mode depends on the source app's gap.** A streaming app doing gapless
  playback may emit no silence between tracks → no inter-track spike (like local track 4);
  a pause/resume or a track change with a gap → the same decay → the same spike.

To close this, a streaming multi-track recording (several track changes, including at least
one with an audible gap) is needed. **Flagged for Matt** (kickoff: record fresh sessions on
both paths if absent).

---

## What this evidence sets up for AGC3.2 (decision gate — not decided here)

The fix approach is Matt's call on this evidence, framed in product language (kickoff
§"Decision points for Matt"). The measurements bear on the options as follows — **stated as
inputs to the decision, not as a recommendation pre-empting it**:

- The artifact is **per-track and recurring** (not one-time) and the per-track instances are
  the longer/worse ones → a per-track-aware fix matters, not just a session-start guard.
- A working in-codebase precedent exists (the per-stem reset/re-seed) → option (a)-family
  ("ease the meter in / re-seed at each track start") has a known-good shape and keeps the
  steady-state AGC untouched.
- The spike drives `f.bass` to an **absolute ~3.5–4.0** against a steady ~0.2–0.36 → any
  threshold/ceiling reasoning should key on the **absolute** value or the **scale**, not the
  ratio (which varies with track loudness). And per the hard rules, the fix must bound the
  **scale/seed**, never clamp `f.bass`'s output range (that would cost dynamic range on
  legitimately loud moments).
- The change touches the **shared** loudness meter that feeds every preset and the deviation
  primitives → a catalog M7 on both paths is in scope even though the change is cold-start-only.

---

## Reproduce

```bash
python3 tools/agc3/measure_coldstart_spike.py \
    ~/Documents/phosphene_sessions/2026-06-06T01-18-36Z --label LF --stems
```

Knobs: `--silence-floor` (pre-roll detection), `--onset-window`, `--steady-lo/-hi`,
`--ratio-mult` (spike-duration threshold), `--active-floor`, `--stems`.
