# WL.2-a — pen-kinematics pre-check: §3.1 as specified draws a line, not a figure

**Date:** 2026-07-31 · **Increment:** WL.2-a · **Verdict:** §3.1's heading model **falsified**; the deviation form adopted (D-209 amendment).

## What this is

`docs/presets/WITCHLIGHT_DESIGN.md` §6 rated the harmonic-state → pen-path mechanism **level 3** (no empirical grounding) and made WL.2's first deliverable a look-spike answering exactly one question: **does the figure read as a drawing?**

This is that check run on the **CPU kinematics only**, in Python, against the four real captures from `WITCHLIGHT_DESIGN.md` §2. The pen and its relaxation genuinely live on the CPU in the shipped design, so the math here is faithful to production; what it **cannot** answer is how the beads *render* or how the figure *moves*. Those stay with the Metal look-spike and `Scripts/motion_gate.sh`.

Script: `tools/wl2_pen_probe.py`. Figures: `WL2A_pen_absolute_vs_deviation.png` (row 1 = as specified, row 2 = deviation form; columns = so_what / there_there / love_rehab / live).

## Result 1 — as specified, every track draws a near-straight line

§3.1(b) specified `θ̇ = clamp(k · φ̄̇, ±ω_max)` with `φ̄` the τ = 1.5 s circular EMA of `tonal_phase_fifths`. On all four captures the pen drew a **near-straight stroke with a gentle bend**. No tangles — and no drawing.

τ is not the lever. Swept across a 10× range:

| capture | τ (s) | R (smoothed) | clamp % | heading travel (turns) |
|---|---|---|---|---|
| so_what | 0.15 | 0.935 | 2.6 | 2.22 |
| so_what | 0.35 | 0.961 | 1.3 | 2.55 |
| so_what | 0.80 | 0.973 | 0.9 | 2.80 |
| so_what | 1.50 | 0.976 | 0.5 | 2.94 |
| love_rehab | 0.15 | 0.464 | 3.2 | 1.83 |
| love_rehab | 0.35 | 0.557 | 3.7 | 1.84 |
| love_rehab | 0.80 | 0.659 | 3.7 | 1.64 |
| love_rehab | 1.50 | 0.803 | 4.0 | 1.47 |

Straight at every τ.

## Why — a structural error in the design, not a tuning miss

`θ̇ = k · φ̄̇` integrates to **`θ = k · φ̄ + c`**: the heading *is* the smoothed phase. And the smoothed phase is strongly **concentrated** — mean resultant length R = 0.94–0.98 on so_what at every τ tested — so it hovers near one angle instead of circulating. A pen that mostly points one direction draws a line. (The "heading travel" column is total |Δθ| including back-and-forth; net progress is near zero, which is why 2–3 "turns" still yields a straight stroke.)

Stated plainly: **§3.1 specified an absolute read of a bounded circular primitive.** That is the same shape as Failed Approach #31 — the rule the codebase already carries against absolute thresholds on AGC-normalised values — committed in a design doc that cites FA #31 two sections later.

## Result 2 — the deviation form (D-026) produces figures

One change: steer from the phase's **excursion from its own slow circular mean** rather than its absolute value.

```
θ̇ = clamp( k · wrap(φ_fast − φ_slow), ±ω_max )     τ_fast = 0.8 s, τ_slow = 8 s
k = 0.85 · ω_max / p95(|wrap(φ_fast − φ_slow)|)     per-track normalised
```

| capture | clamp % | heading travel (turns) | figure |
|---|---|---|---|
| fixturegen-so_what | 0.8 | 2.07 | long rising stroke ending in a tight spiral curl |
| fixturegen-there_there | 3.3 | 2.74 | two-lobed compound figure with a loop |
| fixturegen-love_rehab | 1.1 | 1.87 | broad closed loop with a small hook |
| beat-match-test-session | 0.0 | 2.08 | wide loop with an inner curl |

Four distinct, legible figures. **None is a tangle.** Clamp fractions stay below 4 %, so nothing degenerates to the minimum-radius circle §3.1(b) warned about (the as-specified form hit **49.8 %** clamped on love_rehab at fixed `k = 1`). The ~10× cross-track rate spread from §2.3 disappears, because a per-track-normalised deviation is exactly the construction that removes it — which is why D-026 exists.

**Read the figures, not the scalars.** Once `k` is per-track normalised, neither summary metric separates the two models — heading travel lands at 1.6–2.8 turns and clamp fraction under 4 % for *both*. That is itself informative: the failure is not "too little turning" in aggregate, it is that the absolute model's turning is **oscillation around a preferred heading** rather than net progress, and only the rendered path shows the difference. The scalars are here to rule out degeneration (clamping, pinning), not to prove legibility. Legibility is the reader's call on the sheet (D-064) — the same rule `compare_render.sh` and `motion_gate.sh` operate under.

## What this does and does not settle

**Settles:** the path geometry reads as a figure on real music, across four captures of different character. The level-3 grounding risk on "harmonic state → pen-path geometry" is materially reduced — from *unevidenced* to *evidenced on the CPU math*.

**Does not settle:**
- **How it moves.** Every figure here is a still of a 30 s window. Jitter, pop and freeze are invisible in a still — the Truchet Loom lesson (D-194). The Metal look-spike plus `Scripts/motion_gate.sh` remains a required gate, and the §6 level-3 rating on the *combination* stands until it passes.
- **How it renders.** No beads, no falloff, no core/halo, no ground. Flat lines on black.
- **Whether the figure is the right figure.** "A long curl" is legible; whether it is the drawing Matt wants is an M7 question, not a measurement one.

## Carry-forward

- `WITCHLIGHT_DESIGN.md` §3.1(a)/(b) amended to the deviation form; §2.3 item 3's rate-spread finding now has its resolution named.
- D-209 gains an amendment recording the falsification and the correction.
- Reusable lesson beyond this preset: **a circular primitive needs a deviation treatment for the same reason a band energy does.** `tonal_phase_fifths` is concentrated on real music (R up to 0.98 smoothed); consumers that want *motion* from it must read excursion-from-slow-mean, not absolute phase. Filed into the capability-registry row for the TIV primitives.

---

## Part 2 — the Metal look-spike and the motion verdict

Part 1 settled the *geometry* on CPU math. This is the gate that Part 1 explicitly did **not** discharge: the figure rendered through the production particle path (`MultiPassRenderHarness.renderWitchlight` → `WitchlightStroke.update` → `.render` — the same calls the app makes), as a contiguous 40-second sequence per capture, read as a sequence.

Reproduce:

```
RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter WitchlightMotionSequence
Scripts/motion_gate.sh witchlight /tmp/phosphene_visual/<stamp>/<capture>
```

### Two instrument faults found and fixed before the verdict could be read

Neither is a finding about the preset; both are recorded because the first pass produced an unreadable gate and a future session would otherwise repeat them.

1. **Per-frame bounding-box framing made the camera the dominant motion.** The stroke was normalised to fill the frame every frame, so the pen's own drift rescaled and translated the entire figure continuously. `motion_gate.sh` reported **496 spike frames and 1288 frozen frames on the same sequence** — a contradiction that was entirely the camera. Whole-frame coherence has to hold before any per-trait judgement means anything.
2. **The first fix over-corrected and lost the figure.** A slow-follow camera (τ ≈ 6 s) could not keep up with an unbounded pen walk; by 40 s the stroke was off-screen. The harness's own non-degenerate guard caught it (`lastNonBlack == 0`) rather than a reader noticing black frames.

Resolution: **latch the scale once, track only the centre.** Scale is measured the first time the trail is at full length and then held (predicting it from `speed × trailSeconds` overestimated by ~4×, because a curled stroke covers far less ground than a straight one). The centre tracks at τ ≈ 1 s, fast enough for a pen moving at `baseSpeed`, slow enough that the camera contributes far less frame-to-frame motion than the stroke.

### Motion verdict (reader's call, D-064)

| Capture | Smooth? | On-concept in motion? | Notes |
|---|---|---|---|
| `fixturegen-so_what` | **PASS** | **PASS** | A large loop with a wandering tail; the loop persists and reshapes while the tail sweeps. Reads as a drawing being made. **0 spike frames / 1288.** |
| `fixturegen-there_there` | **PASS** | **PASS** | Compound figure, smooth evolution. Spike cluster at contiguous frames 578–591 — see the emit-rate note below, not a visual jitter. |
| `fixturegen-love_rehab` | **PASS** | **PASS** | Small tight loop joined to a large loop, wandering tail. The most legibly "written" of the four, and the only one with real colour variety. |
| `beat-match-test-session` | **PASS** | **PASS** | Wide loop with an inner curl; smooth across 40 s of a live playlist. |
| Anti-reference `10` (tangled scribble ball) | **does NOT resemble** | — | No capture produced a tangle at any point in any sequence. |
| Anti-reference `11` (uniform glow tube) | n/a | — | Spike draws flat beads with no shading; the trait is untestable until WL.2-b. |

**No jitter, no structure-pop, no strobe, no freeze on any capture.** This discharges the D-209 §6 level-3 rating on the *combination* — the pairing that had no published precedent produces smooth, legible, on-concept motion on four real captures.

**Two caveats on the numbers, so they are not over-read:**

- The script's `frozen frames (~0)` counter reports 100 % on every capture while simultaneously reporting a mean inter-frame magnitude of 0.08–0.12. Those cannot both be true; the counter's absolute threshold is miscalibrated for a sparse near-black frame. The harness's own `mean |Δframe|` (0.0014–0.0021, non-zero and non-degenerate) plus the read sequence are the evidence. Not chased further — it is a script-threshold artifact, and worth a note on `motion_gate.sh` rather than a fix here.
- The spike clusters land on strictly alternating frames (578, 580, 582 …). That is the **34 Hz bead-emission rate beating against the ~43 Hz capture frame rate**: a bead appears on some frames and not others, and on a mostly-black frame one new bead is a large *relative* change. Real but minor; WL.2-b should emit with sub-frame position interpolation rather than snapping to whole frames.

### The finding that is NOT an instrument fault

**§3.4's colour model has the same concentration problem §3.1 had, and it shows.**

A bead's hue is the *absolute* smoothed phase frozen at emission. On `love_rehab` (smoothed R = 0.80) the ribbon carries genuine colour banding — cyan, green, orange, red along its length, exactly the "colour history" the concept promises. On `so_what` (smoothed R = **0.976**) the entire 30-second ribbon is one dark blue-violet: the phase never leaves its preferred angle, so neither does the hue.

This is the same structural error as the heading, in the same section, for the same reason — an absolute read of a concentrated circular primitive — and it was missed when §3.1 was corrected because only the *steering* was being reasoned about. **§3.4 is a design change, not a tuning question, and it is Matt's call**, exactly as the §3.1 amendment was. It is not fixed here.
