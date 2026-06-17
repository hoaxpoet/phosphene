# CLEAN Phase 7 — Kickoff: photosensitivity flash-safety, the A-next half (CLEAN.7.6b, [GAP-9], [M7])

> **⛔ SUPERSEDED (2026-06-17, D-166) for the runtime-clamp half.** Stage 1 (the faithful headless harness) shipped as CLEAN.7.6b + 7.6c → **G9 7/7 ENFORCED**. Stage 2 (the runtime luminance clamp) was evaluated under CLEAN.7.6d and **NOT pursued** (Matt) — the **certification gate is the photosensitivity enforcement mechanism**. All shipped presets are ≤ 1 flash/s under the worst-case drive, and a *uniform* clamp would be a pipeline-wide reroute of the **8 separate present paths** in `renderFrame` (`RenderPipeline+Draw.swift:126`) — regression risk across every certified preset for a net that never engages on shipped content. **Do not build the clamp from this doc.** See **D-166** (amends D-164) before reopening; reopen only on a new premise (un-certified / user-authored presets, or live arbitrary-source rendering).

> **This is the deferred half of CLEAN.7.6 / D-164.** 7.6 shipped the *measurement* gate (B-now). This is the *faithful coverage + runtime clamp* half (A-next). It has **two stages**; Stage 2 is `[M7]` + golden regen. **Do Stage 1 first** — it tells you whether Stage 2 is fixing a real defect or only adding a forward-looking backstop, and it produces the data needed to tune the clamp without guessing. Surface the Stage-2 decision to Matt *with Stage-1 numbers in hand*, not before.

## Why this is next
- **G9 is only PARTIALLY enforced.** 7.6's `PhotosensitivityCertificationTests` validly measures **2 of 7** certified presets (Ferrofluid Ocean + Murmuration, both flash-safe). The other **5** — Lumen Mosaic, Nimbus, Dragon Bloom, Fata Morgana, Skein — render **static** in the single-pass `FeatureVector`-only harness and are tracked in `unmeasurableInHarness` (never asserted safe; fail-loud-on-drift). Their flash-safety is **unproven**, not proven-safe.
- **The runtime clamp was always the A-next half** (D-164; D-054/U.9 "frame blanking"). It is the only mechanism that protects an *arbitrary live track* or a *pre-certification preset* — the gap a measurement-only gate cannot close.

## What 7.6 already built (reuse — do not reinvent, FA #73)
- **`FlashAnalyzer`** (`Sources/Renderer/FlashAnalyzer.swift`) — pure Harding/WCAG 2.3.1 analyzer on a full-frame relative-luminance sequence (≥10% swing, darker state <0.80, >3 flashes/s over a 1 s window). 8 synthetic self-checks. **This is the measurement core for both stages.**
- **`PhotosensitivityCertificationTests`** (`Tests/.../Renderer/`) — the gate scaffold + the worst-case 4.5 Hz beat-train generator + the per-pixel sRGB→linear WCAG-luminance helper. Extend it; don't fork it.

## Current state — verified seams (2026-06-16; re-check before trusting)

| Thing | Where | Note |
|---|---|---|
| **Real render driver** | `PhospheneApp/Views/MetalView.swift` (NSViewRepresentable → `MTKView`, `view.delegate = pipeline`); `VisualizerEngine.swift:228` | `RenderPipeline` is an `MTKViewDelegate`; `draw(in: MTKView)` needs `view.currentDrawable` — **no headless render-to-texture entry today.** |
| **Per-preset follower state** (the reason 5 render static) | `Sources/Presets/Nimbus/NimbusState.swift`, `Sources/Presets/Lumen/LumenPatternEngine.swift`, AuroraVeil state; orchestrated in `PhospheneApp/VisualizerEngine+Presets.swift` | State logic is in **importable engine targets** (`Presets`); the per-frame *orchestration* is app-layer. Stage 1 must reproduce that orchestration to fill the slot-6/8 buffers `PresetRegressionTests` binds ZEROED. |
| **Existing offscreen render seams** | `RenderPipeline+MVWarpScene.swift renderSceneToTexture(...)`, `RenderPipeline+DirectDraw.swift` (half-res offscreen), `RenderPipeline+Draw.swift` (rayMarch→offscreen, staged per-stage textures) | The pipeline **already renders to textures** for mv_warp/rayMarch/staged. A headless path likely composes these, not rebuilds them. |
| **Clamp site** | `RenderPipeline.swift:631` `draw(in:)`; recorder hook fires `:675` (`onFrameRendered`, `view.currentDrawable`) | The clamp is a final full-screen pass **before `:675`** so the recorded `SessionRecorder` video reflects the clamped output. |
| **OR-flag slot for the clamp** | `RayMarchPipeline.swift:94` | A *third* private suppression flag widening the `reducedMotion` OR — **never assign `reducedMotion` directly** (D-057). The luminance clamp is output-side, distinct from SSGI/motion suppression. |

## Stage 1 — faithful headless flash harness (measurement; NO M7)
**Goal:** validly measure the 5 static presets by reproducing their *real* rendered luminance over the worst-case beat train, then move them from `unmeasurableInHarness` to real `#expect(report.isSafe)` assertions.

- **Drive the real pass chain headless.** Two candidate routes (pick after a spike): (a) construct an offscreen `MTKView` / a fake `CAMetalDrawable` wrapping an `MTLTexture` so `RenderPipeline.draw(in:)` runs **unchanged** to a capturable texture; or (b) add a headless `renderToTexture(features:size:)` seam to `RenderPipeline` that runs the same pass chain (reusing the existing offscreen seams) minus the drawable present. Prefer (b) if (a)'s drawable faking is brittle.
- **Tick the per-preset followers** (Nimbus/Lumen/AuroraVeil state) to populate the slot-6/8 buffers, reproducing `VisualizerEngine+Presets` orchestration. Confirm where each state buffer is computed before assuming it is trivially liftable.
- **Run N sequential frames** so the **feedback** chain (Skein, feedback-zoom presets) accumulates as in production.
- **Output:** the per-preset peak-flashes/s table for all 7. **Expected outcome is informative either way** — all safe → the invariant is locked across the whole certified set; any over-threshold → a genuine pre-existing P1 safety defect (file it, bring to Matt, do **not** tune away — D-157/D-158 motion was hand-built safe).
- **Fail loud** (the 7.6 lesson): a preset the harness still cannot drive must be *reported as unmeasured*, never silently passed.

## Stage 2 — output-side runtime luminance clamp (`[M7]` + golden regen)
**Only after Stage 1.** A final full-screen temporal slew-limiter at `draw(in:)` (before the `:675` recorder hook) that caps the per-frame large-area luminance delta below the >3/s rate — **transparent below the danger band** so already-safe presets are visually untouched.
- Gate it behind the OR-flag pattern at `RayMarchPipeline:94` (third flag, widen the OR — never `reducedMotion` directly).
- **It will move goldens** → regenerate `PresetRegressionTests` hashes + an **M7 re-review of every certified preset** with Matt. Its **own** M7 sitting — do not bundle.
- **Decision for Matt (bring with Stage-1 data):** the transparency band / aggressiveness — framed in product terms ("how hard must a flash be before the clamp engages; the trade-off is X visible softening on preset Y"), grounded in the Stage-1 per-preset numbers, not guessed. If Stage 1 finds all 7 safe, Stage 2 is a pure forward-looking guarantee (live tracks / future presets), not a fix — a lower-pressure M7.

## Rules / pitfalls
- **Measure output luminance, not audio drivers** (carry from 7.6).
- **Do not flatten the intended look.** The clamp must be transparent for the hand-tuned FFO regional-punch / slow-hue motion (D-157/D-158). Stage 1 is what tells you what "already-safe" looks like numerically.
- **Reuse `FlashAnalyzer` + the existing offscreen seams** — rebuilding the pipeline headless from scratch is FA-#73-class.
- **Clamp before the recorder hook** so `SessionRecorder` video matches what's shown.
- **Fail loud** — a clamp that can't initialize refuses; it does not silently pass (CLEAN.0).
- **`file_length`** — the faithful harness in its own file; don't bloat `PhotosensitivityCertificationTests`.

## Closeout
- **Stage 1:** the all-7 per-preset peak-flashes/s table (that *is* the visual evidence); flip the 5 out of `unmeasurableInHarness`; `closeout_evidence.sh` block; update `CODE_AUDIT` G9 (→ ENFORCED if all safe) + `RENDER_CAPABILITY_REGISTRY §9` (Partial → Supported). No M7.
- **Stage 2:** Matt's M7 re-review of every certified preset + golden regen; a new **D-#** amending D-164 with the clamp design + the transparency-band pick; `SHADER_CRAFT` clamp note; release notes. **Push requires Matt's "yes, push."**

## References
D-164 (the measurement half + the partial-coverage finding), D-054/U.9 (the original deferral), D-157/D-158 (FFO regional-punch / hue-route fixes the clamp must not flatten), D-057 (the OR-gate flag discipline), FA #73 (reuse the reference, don't rebuild), `docs/prompts/CLEAN_7.6_PHOTOSENSITIVITY_KICKOFF.md` (the B-now kickoff), `RELEASE_NOTES_DEV [dev-2026-06-16-b]`.
