# Increment WL.2-g — Witchlight: the ribbon carries no light

**Type:** preset shading (`.metal` only, plus one test). No geometry, no audio routing, no design-doc revision.
**Predecessors:** WL.2-e (backdrop), WL.2-f (bead geometry) — both landed and gated.
**Blocks:** Witchlight certification. This is the last known fidelity gap from Matt's 2026-08-03 M7.

---

## 1. The gap, measured

Matt's M7 verdict was *"it looks nothing like the original preset it was supposed to be based on."* Three defects were found. Two are fixed and gated:

| | source | before | now | gate |
|---|---|---|---|---|
| backdrop mean luma | 10.6 | 31.5 | **13.4** | `WitchlightSkyLuminanceTests` |
| heading turns / trail | — | 0.35–0.55 | **1.81–2.19** | `ResponseBandTests` (QG.5) |

The third is not, and it is now measured rather than felt. Same frame, same scale, Matt's Hummer capture against his render of the source:

| | source | ours |
|---|---|---|
| **ribbon pixels (luma > 120)** | **1.048 %** | **0.119 %** |
| peak luma | 255 | 224 |

**Nine times too little light in the ribbon.** The beads are correctly *sized* and *spaced* after WL.2-f — that is solved, do not revisit it. They simply carry almost no brightness: the source's are bright cores with real bloom halos, ours are hard pinpoints on a thin thread.

**This is a shading problem, not a geometry constant.** Three rounds of geometry nudging (WL.2-e, WL.2-f) moved the spacing and the size correctly and never touched this number. Changing `baseRadius` or `emissionHz` again is the wrong lever and is explicitly out of scope.

## 2. Targets

Both measured on a 760×428 render of the same capture, against `~/mdrender/gallery/martin - witchcraft reloaded.png`:

- **ribbon pixel share (luma > 120): ≥ 0.6 %** — most of the way to the source's 1.048 %, not a demand to match it exactly. The register is "a luminous ribbon", not a pixel-for-pixel copy (D-121 still applies).
- **peak luma ≥ 250** — the bead cores should reach near-white, as `08` shows a real arc core doing.
- **backdrop must not regress**: `WitchlightSkyLuminanceTests` stays green (mean ≤ 22.0, lit ≤ 10 %). Brightening the ribbon must not brighten the field.

## 3. Where to work

`PhospheneEngine/Sources/Renderer/Shaders/Witchlight.metal` — passes 2 and 3 only:

- `witchlight_bead_fragment` — the two-part radial profile. Reference `08` (lightning: near-white core with a distinctly **cooler and wider** violet halo) and `09` (a bright core that does **not** bleach the thin filaments beside it). The current profile reads as a hard dot; the halo is the missing term.
- `witchlight_line_*` — the thread between beads. `01`/`02`: the trail is a *line with sparks on it*, and the line itself glows.
- Age falloff `wl_age_alpha` = `(1−t)^1.6` is **correct and load-bearing** (mandatory trait #2, monotonic). If the tail needs more presence, raise the emissive level, do not flatten the falloff — a non-monotonic tail fails the trait.

## 4. Constraints

- **Do not raise the head flare.** §5's budget (0.00 flashes/s, peak full-frame mean ≤ 0.35, ≥ 900 ms refractory) is measured and green. Headroom analysis: the ribbon at the source's 1.048 % share sitting at full white contributes ~2.7/255 ≈ 0.010 to the frame mean, against a 0.35 ceiling — **the ribbon is not the flash risk and has plenty of room.** The flare is the risk, and it is not in scope.
- **Do not touch** `baseRadius`, `emissionHz`, `curvatureGain`, `trailSeconds`, or the backdrop. All four are solved and three are gated.
- `WitchlightFlashBudgetTests` and `MultiPassFlashHarnessTests` stay green.

## 5. Gate

Extend `WitchlightSkyLuminanceTests` (rename it to cover both halves — it is already the frame-statistics-against-the-source suite) with the two ribbon assertions. Same discipline as QG.5 and QG.1: **the numbers came from a measurement of the source, so if the test goes red, fix the shader — never widen the band.**

The suite renders through `MultiPassRenderHarness` at 640×360 and takes ~1 s, so it is a fast iteration loop, not a 4-minute render. Use it.

## 6. Verify

```bash
swift test --package-path PhospheneEngine --filter "Witchlight|ResponseBand"
RENDER_VISUAL=1 WITCHLIGHT_SESSION=~/Documents/phosphene_sessions/2026-08-03T15-05-43Z \
  swift test --package-path PhospheneEngine --filter WitchlightMotionSequence
Scripts/motion_gate.sh witchlight /tmp/phosphene_visual/<stamp>/2026-08-03T15-05-43Z
```

Then a **side-by-side against the source** at the same frame, which is what Matt actually judges — and which D-121 requires at certification anyway.

## 7. Stop conditions

Bring it to Matt rather than continuing if any of these fire:

- **Two shading passes fail to move the ribbon-pixel share.** That would mean the gap is not in the fragment shading, and the next hypothesis needs stating before more edits. Three geometry rounds already failed to move this number; do not repeat that pattern in the shader.
- **The backdrop gate goes red** to make the ribbon target. That is robbing Peter to pay Paul and means the approach is wrong.
- **The flash budget moves at all.** The ribbon should not affect it; if it does, something is brighter than intended.
- **You find yourself changing a geometry constant.** Out of scope by construction — if it seems necessary, the diagnosis in §1 is wrong and should be re-argued first.

## 8. Not in scope, tracked elsewhere

- §3.4's colour model has the same concentration problem the heading did — bead hue is the *absolute* frozen phase, so a harmonically static track renders a near-monochrome ribbon. A design change and Matt's call; not a shading fix.
- Certification (live M7, `certified: true`, the D-121 side-by-side, `certifiedPresets` membership) follows this increment, not part of it.
