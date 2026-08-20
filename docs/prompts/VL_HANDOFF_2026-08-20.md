# VL performance — handoff (2026-08-20)

Consolidation note: VL work was split across two sessions. This is everything the
rendering-performance session established, so the other session can continue without
re-deriving it. All of it is merged to `main` as of `02ba1d60`.

## The one thing to do next

**Get a live session with VL fullscreen on the current build and read `frame_gpu_ms`.**
PERF.13 (post-process chain now renders at the marcher's scale) shipped *specifically* to be
measured live and has never been. The result forks the work:

- **Drops from ~104 ms toward ~26 ms** → the full-resolution bloom was the missing cost;
  fullscreen becomes viable and VL is close to done.
- **Stays near ~104 ms** → the cost is somewhere neither instrument has looked. **Stop sweeping
  offline** and add per-pass GPU timing in production, the way `RENDER_TARGET` (PERF.1) settled
  the resolution question. Every offline VL number has disagreed with live by 2–4×.

Matt's requirement, verbatim: *"It needs to run fullscreen even if not optimal."* 9.6 fps is not
"runs". He has not set a target fps for fullscreen — worth asking rather than assuming 60.

## State

| where | cost | note |
|---|---|---|
| 900×600 | 6.93 ms | fine |
| 2884×1662 | **104 ms (9.6 fps)** | stable over 8 buckets, no ramp |
| 1080p target | ~budget | `CLAUDE.md` promises 60 fps **at 1080p**, which is met |

`render_scale: 0.5` in `VolumetricLithograph.json`. **Matt M7-approved that look** (*"VL looks
good"*, session `2026-08-20T13-50-18Z`). 0.4 is available and buys ~1.25×, but changes an
approved appearance — do not spend it casually.

## What is already known, so it is not re-derived

- **Cost is ~69 % Perlin noise in `sceneSDF`**, evaluated ~135× per pixel (128 march steps +
  4 normal taps + 3 AO taps). Terrain `fbm3D(_,4)` ≈ 2.7 ms/octave; the `vl_foldDomain` warp
  (2 × `fbm3D(_,3)`) ≈ 10.4 ms. Measured by ablation with a same-session drift control.
- **The marcher is not at fault** — correct sphere-trace early exit (`d < 0.001·t → break`).
- **There is no waste of the BUG-098 kind.** VL-PSY.1 already cut the warp from 112 evaluations
  to 6; octaves went 5 → 4 and **3 was tried and reverted** (below SHADER_CRAFT's floor, "soft
  and airbrushed").
- **`VL_SDF_STEP_SCALE` 0.55 → 0.70** buys 10 % and is **visibly different** (74 % of channels
  differ, 12.3 % beyond 16/255). Product decision, not an optimisation.
- **MetalFX was considered and rejected for now.** Opting in requires a preset-defined
  `scenePrevPosition`; no preset has ever defined one, VL's terrain *morphs* (not representable
  as a position delta), and the failure mode is ghosting. It would also revive MFX.1, which Matt
  decided to delete on 2026-08-03. Matt authorised using it *if needed* — that door is open, but
  the cheap path was taken first at his instruction.

## Traps this work fell into — do not repeat

1. **The harness does not reproduce VL.** 30.6 ms vs 67 ms live at 1080p; 26 ms vs 104 ms live at
   2884×1662 *at the same render scale*. Treat offline VL numbers as ordering, never as absolute.
2. **Short windows straddling a preset switch produce garbage medians.** A 16.44 ms live figure
   was published and later retracted; it came from 89 frames spanning a transition. Sub-6 ms
   readings appear at every segment boundary. **Require a few hundred frames inside one
   resolution and one preset.**
3. **Measure a control in the same breath.** "Octaves 4 → 2 changes nothing" was reported as a
   contradiction; it was a bad reading taken while the machine was busy. Re-run with the baseline
   either side (30.59 → experiment → 30.58) and it vanished.
4. **`deltaTime` is vsync, not headroom. `frame_gpu_ms` is the column.** They disagree by ~80×.

## Related, still open

- **BUG-100** — sustained-4K degradation (frame_cpu 17.4 → 43.6 over 70 s while the app's own
  work stayed flat). `THERMAL_STATE` instrumentation shipped (PERF.9) and has read `nominal` in
  every session since; the degradation has not reproduced. Not VL-specific.
- **BUG-099** — Witchlight at 4K (37 fps against a 1080p promise that is met). Product decision.
- **13 presets remain unmeasured** by the PERF.4 frame-budget gate, including Ricercar and
  Staged Sandbox, which neither harness can reach.
