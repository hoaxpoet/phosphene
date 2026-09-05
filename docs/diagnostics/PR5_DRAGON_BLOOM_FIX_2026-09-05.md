# PR.5 fix — Dragon Bloom's white-out is inverted emptiness, and the invert is the lever

**Date:** 2026-09-05 · **Increment:** PR.5 (Phase PR) · **Matt:** *"Do Dragon Bloom first"*

**Matt's report (2026-09-04 roster review):** *"Washed out, extreme brightness. Reds look gorgeous.
Would like to see the same saturated color across the visible light spectrum"* — clarified as loss of
saturation from overexposure.

PR.5's diagnosis increment falsified the tone-map hypothesis and left two candidate levers unmeasured.
This measures them, on Matt's own album, through the production render path.

---

## 1. First: a real capture of Matt's material, because there wasn't one

PR.5 §4 closed with an honest bound — the harness drove **synthetic** audio (FA #27), and no *Low*
session existed to replay. Two instruments closed that gap, both small:

- `FixtureSessionCaptureGenerator` gained `UZUME_GEN_SESSION_AUDIO`, so it captures **any** audio file
  through the production analysis chain, not just the three vendored tempo fixtures. Two Bowie *Low*
  tracks are now real 1290-frame captures.
- `SessionDrivenMultiPassReplay` gained the `REPLAY_OUT` frame dump its own PR.10 usage block had
  documented and never implemented, plus `REPLAY_W`/`REPLAY_H`. Three numbers are not a perception
  check (D-181); the frames are.

Every measurement below is Dragon Bloom's real `direct + mv_warp` dispatch, driven by real analysis
of *01 — Speed Of Life*.

---

## 2. Baseline: confirmed, and worse than the synthetic harness suggested

| | synthetic (PR.5 §1) | **real *Low* audio** |
|---|---:|---:|
| clipped | 91.4 % | **83.6 %** |
| saturation (bright px) | 0.141 | **0.265** |
| mean luma | 0.929 | **0.909** |

**The trajectory is flat.** Clipped stays between 0.76 and 0.89 across all 30 s. This is not a fill
still developing — the plan describes the fill as a feedback attractor that needs ~20 s
(`DRAGON_BLOOM_PLAN.md` L4 item 3) — it is a field that reaches a blown-out steady state in about
three seconds and stays there. `DRAGON_BLOOM_PLAN.md` named this exact outcome in 2026-06-01:
*"invert-before-fill whited-out."*

---

## 3. A falsified hypothesis, recorded because it was wrong for an instructive reason

`mvWarpPerVertex` breathes the bloom with `clamp(1.0 + 0.06*(f.bass*6.0 - 1.0), 0.97, 1.07)` — an
**absolute threshold (1/6) on the AGC-normalised `f.bass`**, which is exactly the pattern D-026 and
FA #31 ban. On *Low* the median `f.bass` is 0.236, so the term sits at **1.024 median / 1.070 at
p90**: a 2.4–7 % outward push every frame against the source's 0.99951 baseline, whose own comment
says it *"prevents the field draining off-edge / white-collapse."*

That reads like an open-and-shut root cause. **Rendered, it is not.** Converting the route to the
signed deviation primitive `bass_rel` made the picture WORSE:

| | shipping | `bass_rel` breathing |
|---|---:|---:|
| clipped | 0.836 | **0.868** |
| saturation | 0.265 | **0.099** |

The outward push is not draining the field — it is the **conveyor** that carries strand colour out
from the centre before the transfer's B-fade extinguishes it. Slow it down and the colour dies closer
in, so coverage drops. Reverted.

**The FA #31 violation is still real and is still there.** It is filed as a finding, not fixed:
changing it degrades the render, and correctness-on-paper does not outrank what the frame looks like.

---

## 4. What actually works: invert about a warm tint instead of pure white

`bInvert` is literally `1 - c`, so an accumulator pixel near **black** displays near **white**. The
frame is mostly empty accumulator. That is the entire "washed out, extreme brightness" report.

**First attempt — subtract from a deep ember** (`ceiling - c`, ceiling `(0.62, 0.30, 0.10)`). The
numbers looked perfect (clipped 0.000, saturation 0.942, luma 0.487). **The render rejected it:**
every accumulator value above the ceiling crushes to black, which flattened the feathering into
blocks of flat colour and punched a black lozenge through the middle — FA #48 clipart symmetry, the
preset's own named anti-reference. A metric win, not a product win.

**What shipped — tint the inverted value** (`tint * (1 - c)`). Monotonic everywhere, so the feedback
texture survives intact.

| | shipping (`1,1,1`) | **tint `0.95, 0.50, 0.16`** | deeper `0.80, 0.34, 0.10` |
|---|---:|---:|---:|
| clipped | 0.836 | **0.361** | **0.000** |
| saturation | 0.265 | **0.677** | **0.721** |
| mean luma | 0.909 | **0.714** | **0.616** |

`UZUME_MVWARP_INVERT_TINT="1,1,1"` reproduces the shipping arm **exactly** (0.836 / 0.265 / 0.909),
so the A/B is clean and the flag is a true no-op at that value.

Comparison sheet: [`PR5_DRAGON_BLOOM_OPTIONS_2026-09-05.png`](PR5_DRAGON_BLOOM_OPTIONS_2026-09-05.png)
— top-left shipping, top-right the shipped tint, bottom the deeper tint at two frames.

---

## 5. Trait verdict

⚠ **The reference IMAGES for this preset are absent from the repo** — `docs/VISUAL_REFERENCES/dragon_bloom/`
holds only its README (the never-persisted-images problem, fixed for new curation 2026-08-25 but not
reconstructed here; the source `.milk` was removed at PUB.1, so `01_target.png` cannot be regenerated).
These verdicts are therefore against the README's **written** mandatory traits, not a side-by-side.
That is weaker than D-181 asks for and is stated rather than papered over.

| trait | shipping | shipped tint |
|---|---|---|
| Warm fiery palette (red/orange/yellow), green accents | **FAIL** — white/pale-yellow ground | **PARTIAL PASS** — amber/orange ground, warm reds; bloom core still magenta/teal |
| Symmetric bloom silhouette | PASS | PASS (untouched) |
| Rich feedback texture — the feathered flow | PARTIAL — texture only near the core | PARTIAL (unchanged; identical structure) |
| NOT flat mirrored clipart (FA #48 anti-reference) | PASS | PASS — and the rejected ember-subtract arm FAILED this row |
| Matches `01_target.png` | **cannot verify** | **cannot verify** |

---

## 6. What this does NOT fix

- **The bloom's core is magenta/purple/teal, not warm.** Under invert those are the complements of a
  green/red accumulator. The README's palette trait is only partially met and the tint does not
  change it.
- **Coverage.** The bottom two-thirds of the frame carries no feedback texture at all — it is flat
  ground, amber now instead of white. §3 is the evidence that this is a genuine dynamics question
  (fill rate vs. the transfer's B-fade), not a constant to nudge, and it is a bigger increment.
- **The FA #31 breathing route** (§3), still live.
- **Certification.** Dragon Bloom is a certified preset and this changes its look. It needs Matt's
  M7 before the certification means anything again. No live playback has happened.
