# CLEAN.7.6b Stage 1b — Kickoff: faithful multi-pass headless flash-safety harness ([GAP-9], no M7)

> **This is the continuation of CLEAN.7.6b after Stage 1 landed.** Stage 1 (commit `278dee5`, [dev-2026-06-16-h]) added **Nimbus** to the photosensitivity gate by ticking its `.direct` follower state in the existing single-pass harness → **G9 is now 3/7** (Ferrofluid Ocean + Murmuration + Nimbus, all 0 flashes/s SAFE). Stage 1b closes the remaining **4/7** — the presets that render *static* in the single-pass harness because their music response arrives through multi-pass rendering. **Measurement only — NO M7** (no look change). Stage 2 (the runtime luminance clamp) is the separate `[M7]` increment and is unaffected by this work.

## Why this is next
- **G9 is only PARTIALLY ENFORCED (3/7).** `PhotosensitivityCertificationTests` validly measures FFO + Murmuration + Nimbus. The other **4 are tracked in `unmeasurableInHarness`** — *never asserted safe*, fail-loud-on-drift — their flash-safety is **unproven, not proven-safe**:
  - **Lumen Mosaic** — `.rayMarch` + `.postProcess` (multi-pass G-buffer/lighting chain; its `LumenPatternEngine` follower buffer feeds the *lighting* pass, so ticking the follower alone — the Stage-1 trick — is not enough).
  - **Dragon Bloom, Fata Morgana** — `.rayMarch` (multi-pass G-buffer/lighting; Fata Morgana has its own `RenderPipeline+FataMorgana.swift renderFataMorgana(...)` path).
  - **Skein** — `.direct` + `.mvWarp` (Milkdrop-style **feedback** — a warp pass reads the previous frame, a compose pass [`skein_geometry_fragment`] paints on top; the persistent canvas is the flash-relevant signal, so a per-frame-cleared single pass renders it static).
- A safety gate that can't measure 4 of 7 shipping presets is the gap to close. **Expected outcome is informative either way:** all 4 safe → **G9 fully ENFORCED (7/7)**; any over 3 flashes/s → a genuine pre-existing **P1 safety defect** — file it, bring it to Matt, and **do NOT tune it away** (the certified beat-luminance motion was hand-built safe; D-157/D-158).

## What already exists — REUSE, do not reinvent (FA #73)
- **`FlashAnalyzer`** (`Sources/Renderer/FlashAnalyzer.swift`) — the Harding/WCAG 2.3.1 measurement core (≥ 10 % swing, dark-state < 0.80, > 3 flashes/s over a 1 s window). Unchanged — it consumes a full-frame relative-luminance sequence. Both stages use it.
- **`PhotosensitivityCertificationTests`** (`Tests/.../Renderer/`) — the gate scaffold: the worst-case 4.5 Hz beat-train generator (`worstCaseBeatTrain`), the per-pixel sRGB→linear WCAG-luminance helper (`meanRelativeLuminance`), the `unmeasurableInHarness` set, and the **Stage-1 follower pattern** (`renderLuminanceSequence` constructs `NimbusState(device:)`, ticks it per frame, binds its live slot-6 buffer). Extend this; don't fork it. Keep the faithful multi-pass harness in **its own file** (file_length).
- **⭐ THE KEY LEAD — the BUG-034 harness work.** BUG-034 (`### BUG-034` in `KNOWN_ISSUES.md`; "Resolved 2026-06-12" on a worktree branch — **note: its Open-Index row still shows, so confirm whether the fix is on `main`**) built ray-march **harness production-parity** (commits cited in the entry: `9f25584c` baseline coverage → `e2c58905` fix → `5fb2035e` parity → `1a16411e` production-parity). **It already renders ray-march presets headless at the LIVE step count** (the bug was fixtures rendering at 32 steps vs live's 128 via the `sceneParamsB.z` double-book). **Investigate this FIRST** — it is very likely the reusable foundation for the three rayMarch presets here, and rebuilding the rayMarch headless path from scratch is FA-#73-class. If BUG-034's harness/fix is *not* on `main`, integrating or lifting it is a prerequisite (coordinate before duplicating).
- **Existing offscreen render seams** (`RenderPipeline+MVWarpScene.renderSceneToTexture`, `+RayMarch`, `+Staged`, `+FataMorgana`, `+FeedbackDraw`, `+DirectDraw`) — the pipeline already renders to textures for these modes; a headless path composes them, it doesn't rebuild them. **Caveat:** every one currently pulls `view.currentDrawable` (the MTKView), so none is drawable-free today — see the route spike.

## The hard problem + the route (spike FIRST, then commit)
There is **no reusable full-`RenderPipeline` headless harness**, and a prior effort (`Tests/.../Utilities/MaterialRenderHarness.swift`) **explicitly rejected** driving the full ray-march pipeline headless as *"too much scaffolding: MainActor MTLDevice + IBL texture loading + a configured VisualizerEngine."* So budget for real work and pick the route from a short spike:

- **Route A — drive the real `RenderPipeline.draw(in:)` against an offscreen drawable.** `RenderPipeline` is an `MTKViewDelegate`; `draw(in:)` (`RenderPipeline.swift:631`) needs `view.currentDrawable` in every sub-path. Spike: can an offscreen `MTKView` (device set, `framebufferOnly=false`, `isPaused=true`, a drawableSize, no window) vend `currentDrawable` in a headless XCTest, so `draw(in:)` runs **unchanged** to a capturable texture? If yes → maximally faithful (production code path verbatim). If the drawable won't vend headless → Route B.
- **Route B — a headless `renderToTexture(features:size:)` seam on `RenderPipeline`** that runs the same pass chain minus the present, reusing the offscreen seams above. More control, but you must reproduce `draw(in:)`'s dispatch faithfully (don't let it diverge from production — that defeats the measurement).
- **If the BUG-034 harness already solves rayMarch headless rendering, prefer extending IT** over either route for the three rayMarch presets; Skein's `.mvWarp` feedback may still need its own handling.

The other two faithful-rendering requirements (independent of route):
- **Follower orchestration** (Lumen): reproduce `VisualizerEngine+Presets` ticking. `LumenPatternEngine.init?(device:seed:)` + `tick(features:stems:)` → `patternBuffer` bound at fragment buffer **8** (`setDirectPresetFragmentBuffer3`). Confirm at `VisualizerEngine+Presets.swift` + `RenderPipeline+DirectDraw.swift:40`. **But Lumen is rayMarch** — its follower buffer feeds the *lighting* pass, so it needs the rayMarch chain AND the ticked follower together (not the Stage-1 single-pass trick).
- **Skein feedback** (`.mvWarp`): `SkeinState.init?(device:seed:palette:locus:)` + `tick(deltaTime:features:stems:structure:)` → `skeinBuffer` at fragment buffer **6**. The mvWarp loop (`RenderPipeline+MVWarp.swift` / `+FeedbackDraw.swift`) is a ping-pong: pass 0 warps the previous-frame texture, pass 1 (`skein_geometry_fragment`) composites — **frames must NOT be cleared between iterations** (the existing harness sets `loadAction = .clear`, which wipes Skein's persistent canvas). Run N sequential frames feeding each output as the next frame's history texture.

## The work
1. **Spike the route** (above). Commit the spike finding; pick A or B (or "extend BUG-034 harness"). State explicitly which and why.
2. **rayMarch presets** (Lumen, Dragon Bloom, Fata Morgana): render the real multi-pass G-buffer/lighting chain headless at the **LIVE step count** (cross-check BUG-034 / `sceneParamsB.z` — a reduced-step render under-measures the flash). Lumen additionally needs its `LumenPatternEngine` ticked + bound (slot 8).
3. **Skein**: run the mvWarp feedback ping-pong (no per-frame clear; prev-frame as history); tick `SkeinState`, bind `skeinBuffer` (slot 6).
4. **Measure with `FlashAnalyzer`** over the existing worst-case beat train; emit the **all-7 per-preset peak-flashes/s table**; move the 4 from `unmeasurableInHarness` to real `#expect(report.isSafe)` assertions. **Fail loud** — any preset the harness still cannot drive is *reported unmeasured*, never silently passed (the CLEAN.7.6 / CLEAN.0 rule).
5. If any preset measures **> 3 flashes/s**: STOP — file a P1 safety defect with the per-preset numbers, bring it to Matt, do **not** tune the preset to pass.

## Rules / pitfalls
- **Measure output luminance, not audio drivers** (carry from 7.6 / Stage 1).
- **Faithful = the live config.** rayMarch at the live step count (BUG-034), Skein with real feedback history, Lumen with its follower ticked — a degraded render that *happens* to read safe is a false pass.
- **Reuse**: `FlashAnalyzer`, the beat train, the luminance helper, the Stage-1 follower pattern, and — if it exists on main — the BUG-034 rayMarch harness. Rebuilding the pipeline headless from scratch is the FA-#73 trap; the MaterialRenderHarness note is the warning.
- **GPU test** → not on the CI fast-gate; it's a manual-closeout suite test (like the rest of `PhotosensitivityCertificationTests`).
- **`file_length`**: the faithful harness goes in its own file; don't bloat `PhotosensitivityCertificationTests`.
- **No M7** — Stage 1b changes no production render path (test-only) and alters no look. (Stage 2's clamp is the look-altering, M7-gated half.)

## Closeout (per CLAUDE.md Increment Completion Protocol)
- The **all-7 per-preset peak-flashes/s table** is the visual evidence; flip the 4 out of `unmeasurableInHarness` (or report any still-unmeasured, fail-loud).
- `Scripts/closeout_evidence.sh` block.
- If all 7 SAFE: `CODE_AUDIT_2026-06-13.md` G9 → **ENFORCED** (7/7) + Part C; `RENDER_CAPABILITY_REGISTRY.md §9` Partial (3/7) → **Supported**. If any unsafe: file the P1, G9 stays partial pending the fix.
- `RELEASE_NOTES_DEV.md` (use the DOC.8 id format `[dev-YYYY-MM-DD-HHMMSS]`, `date -u +%Y-%m-%d-%H%M%S`); `ENGINEERING_PLAN.md` (CLEAN.7.6b Stage 1b row).
- Small commits; **push requires Matt's "yes, push."**

## References
- `docs/prompts/CLEAN_7.6b_PHOTOSENSITIVITY_RUNTIME_KICKOFF.md` (the parent kickoff — Stage 1 + Stage 2 framing), D-164 (the measurement half + partial-coverage finding), D-157/D-158 (FFO regional-punch / hue motion the measurement must reflect and Stage 2's clamp must not flatten), `KNOWN_ISSUES.md` BUG-034 (ray-march harness parity — the key lead), FA #73 (reuse the reference, don't rebuild), `RELEASE_NOTES_DEV.md [dev-2026-06-16-h]` (Stage 1 / Nimbus).
