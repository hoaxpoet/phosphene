# WL.2 heading models, head-to-head — two parallel increments, one steering term

**Date:** 2026-07-31 · **Verdict:** the deviation form draws figures; the single-EMA-rate form draws near-straight lines on every capture, under both parameterisations, in stills and in motion.

## Why this exists

Two WL.2 increments were authored in parallel off the same WL.1 base (`f9b590b6`), neither aware of the other:

| | A | B |
|---|---|---|
| Branch | `claude/witchlight-authoring` | `claude/witchlight-preset-authoring-1a6d37` |
| Steering | `θ̇ = clamp(k · wrap(φ_fast − φ_slow), ±ω_max)`, `k` per-track normalised | `θ̇ = clamp(k · dφ̄/dt, ±ω_max)` off one EMA, `k` fixed at 1.10 |
| Constants | speed 0.12 frame-heights/s, R_min 0.08 → ω_max **1.5 rad/s** | speed 0.10 world units/s, R_min 0.16 → ω_max **0.625 rad/s** (same 8 %-of-frame-height bound) |
| Also has | the falsification evidence, the probe tool, the motion harness | the fidelity work — sky fragment, flare, turn detection, hue steps, flash budget, CREDITS, golden hash |

They overlap on 13 file paths. This document settles only the **steering term**; it says nothing about the rest of B's work, which is largely complementary.

**Author's note on bias:** A is this session's work. Everything below was therefore run with B's own constants where B's constants exist, and B's own metric (`headingMonotonicity`) is reported alongside — including where it favours B.

## Test 1 — CPU kinematics, each with its own branch's constants

`tools/wl2_pen_probe.py`, 40 s per capture, identical advance / relaxation / emission / raster; only the steer differs.

| Capture | Model | Clamped | Heading turns | Monotonicity |
|---|---|---|---|---|
| so_what | **A** | 1.8 % | 2.06 | 0.820 |
| so_what | **B** | 30.2 % | 2.03 | 0.065 |
| there_there | **A** | 0.9 % | 2.77 | 0.093 |
| there_there | **B** | 14.1 % | 1.74 | 0.030 |
| love_rehab | **A** | 0.0 % | 1.87 | 0.586 |
| love_rehab | **B** | **77.5 %** | 3.09 | 0.047 |
| live playlist | **A** | 0.0 % | 2.67 | 0.887 |
| live playlist | **B** | 38.7 % | 2.75 | 0.067 |

**On the scalars alone, each model looks bad by the other's metric** — and this is the most useful thing in the comparison:

- By **A's** criterion (clamp fraction; §3.1b says >80 % degenerates to a circle) B is in trouble: 30–78 % saturated, `love_rehab` a hair off the threshold.
- By **B's** criterion (`headingMonotonicity` — near 1 means the pen turned one way the whole time, near 0 means it reversed, "which is a figure") **A** looks worse: 0.82 and 0.89 on two captures against B's uniform 0.03–0.07.

**B's metric reads the wrong way for this failure, and that is worth recording.** A heading that reverses constantly at maximum rate produces a *straight line with high-frequency wobble* — tiny net displacement, many reversals, monotonicity ≈ 0. The metric cannot distinguish "reverses because the harmony turned" from "reverses because it is slamming between clamp rails." The high clamp fraction is the tell that separates them, and the rendered path is the arbiter. Neither scalar decides this alone.

## Test 2 — the images

Rendered from the same probe. **A: four distinct legible figures** — a stroke ending in a spiral curl; a two-lobed compound figure; a broad closed loop with a hook; a crossing double loop. **B: four near-straight lines with gentle bends** on every capture.

## Test 3 — through the production Metal path, in motion

B's steering was ported into `WitchlightStroke` behind `WitchlightHeadingModel.singleEMARate` and rendered through the **identical** harness, shader, framing and gate as A — 40 s per capture, four captures, `Scripts/motion_gate.sh`.

**The result holds in motion: B draws near-straight lines on all four captures.**

Two things to be precise about:

1. **The Metal A/B ran B's formula with A's `ω_max` (1.5 rad/s), not B's (0.625).** That is the *more generous* setting for B — a higher clamp ceiling means less saturation — and it still produced straight lines. Combined with Test 1, which used B's own tighter constants, **B fails under both parameterisations.** The conclusion does not rest on a constants choice.
2. **B is perfectly smooth.** `motion_gate.sh` reports **0 spike frames** on both captures checked, mean magnitude 0.03–0.11. B fails on **legibility**, not on jitter — so a motion gate read only for smoothness would pass it. That is a real limitation of the gate worth remembering.

## Verdict and what it does and does not settle

**Settles:** the single-EMA-rate steer does not produce a legible figure on real music, under either branch's constants, in stills or in motion. The mechanism is the one already recorded in the D-209 amendment — `θ̇ = k·dφ̄/dt` integrates to `θ = k·φ̄ + c`, so the heading is bounded by a primitive measured to be strongly concentrated (R = 0.94–0.98 smoothed on `so_what`).

**Does not settle:** anything about the rest of branch B. Its sky fragment, bounded head flare, turn detection, hue-step-on-turn, flash-budget tests, golden hash and CREDITS row are complementary to A and are the WL.2-b/-c work A has not done. B's `headingMonotonicity` and `phaseTravel` counters are also worth keeping as diagnostics — with the caveat above about what monotonicity cannot see.

**Recommended reconciliation (Matt's call):** keep B as the base for its fidelity work; replace its steer with the deviation form; carry A's diagnostics, probe tool, D-209 amendment and motion harness across. Neither branch is on `main`, and neither carries the other's D-209 text, so the decision record has to be reconciled in the same pass.
