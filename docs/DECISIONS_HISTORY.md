# Decisions History

This file holds decisions that have been **superseded by amendments** or **whose increment shipped long ago and is no longer cited by an active decision**. Decisions that remain load-bearing — referenced by code, by another active decision, or by an open follow-up — stay in `docs/DECISIONS.md`.

## Why this file exists

`docs/DECISIONS.md` grew to 122 entries (3,396 lines). Several decision chains involve multiple amendments to the same decision (e.g. the DASH series: DASH.2 → DASH.2.1 → DASH.7 → DASH.7.1 → DASH.7.2; the LM series: LM.3 → LM.3.1 → LM.3.2 → LM.4 → LM.4.1 → LM.4.3 → LM.4.4 → LM.4.5 → LM.4.6 → LM.7). The terminal decision in each chain remains load-bearing; the intermediate amendments are institutional memory worth preserving but should not crowd the active-decisions list.

The cut is:

- **Active:** the decision is currently referenced by code, by another active decision, or by an open follow-up.
- **History:** the decision has been superseded by a newer decision, or its increment shipped and nothing currently references it.

Both lists stay fully searchable via `grep`. The active list becomes scannable.

## Population

This file is populated by **DOC.4** (Decisions refactor). It is empty in DOC.1.

Entries land below this divider preserving their original D-NNN number for cross-reference with git history. A one-line "Superseded by:" or "Shipped in:" header on each entry records why it moved.

---

<!-- Entries land here. Format mirrors docs/DECISIONS.md: ## D-NNN header + body. -->

## D-086 — Dashboard composer + single-`D` toggle + per-path composite call sites (Phase DASH.6)

**Status:** Superseded by D-087 (DASH.7 SwiftUI dashboard port). Moved to history 2026-05-13 (DOC.4). The composer-and-Metal-cards architecture this decision documents was retired when D-087 ported the dashboard to SwiftUI.

DASH.3 + DASH.4 + DASH.5 produced three pure builders + a snapshot type. DASH.6 wires them live: a `DashboardComposer` owns layer + builders + composite pipeline state, the existing `D` shortcut drives both the SwiftUI debug overlay and the new Metal cards, and the composite is encoded at the tail of every render path immediately before `commandBuffer.present(drawable)`.

### Decision 1 — `DashboardComposer` class, not free functions on `RenderPipeline`

The composer's lifecycle is cohesive: it owns one `DashboardTextLayer` (the shared MTLBuffer-backed bgra8 canvas), three builder structs, one `MTLRenderPipelineState` (alpha-blended), an `enabled: Bool`, drawable-size state for placement, and the bytewise snapshot-equality cache. Spreading those across free functions on `RenderPipeline` would require multiple parallel `NSLock`s and seven new public-ish entry points; encapsulating in one class makes the `D` toggle a single property change with no fan-out. `RenderPipeline` holds only a weak read via the `setDashboardComposer(_:)` setter; strong ownership lives on `VisualizerEngine`. Pattern mirrors `DynamicTextOverlay` / `RayMarchPipeline`.

### Decision 2 — Decision B (per-path composite call sites) over Decision A (render-loop refactor)

The DASH.6 spec offered two structural choices: (A) centralize commit at the end of `renderFrame` so the dashboard composite always lands on the same command buffer as the preset draw — and (B) add the composite call at the tail of each draw path that currently calls `commandBuffer.present(drawable)` individually. Audit showed `commit()` is already centralized in `draw(in:)`; what is per-path is `present(drawable)`. Centralizing `present` would require moving 10 `commandBuffer.present(drawable)` lines out of 8 draw paths and threading the drawable back to `draw(in:)` (or capturing it once at the top and threading down) — well beyond the spec's ~30-line ceiling for Decision A. Decision B chosen: a single helper `RenderPipeline.compositeDashboard(commandBuffer:view:)` is added (snapshots the composer under lock, calls `composite` if non-nil) and 10 sites × 1 line of insertion immediately before each `present`. Total impact: ~30 lines including the helper, well under the ceiling. Render-loop refactor (Decision A flavour) deferred to a future increment if multiple consumers want a shared `pre-present` hook.

### Decision 3 — Single `D` shortcut drives BOTH the SwiftUI overlay and the dashboard composer

One cognitive model, no per-surface UX. Cards (top-right Metal, "instruments") and `DebugOverlayView` (bottom-leading SwiftUI, "raw diagnostics") are complementary surfaces, not alternatives. The user reaching for `D` wants either both or neither — splitting the toggle would force them to learn which surface answers which question. `PlaybackView`'s existing `onToggleDebug` closure flips `showDebug` (SwiftUI overlay visibility) and now also writes `engine.dashboardEnabled = showDebug` (Metal cards). `DebugOverlayView` is deduplicated of metrics that the cards now show (Tempo, standalone QUALITY, standalone ML); the rest (MOOD V/A, Key, SIGNAL block, MIR diag, SPIDER, G-buffer, REC) remain because the cards do not show them.

### Decision 4 — No `Equatable` on `StemFeatures` or `BeatSyncSnapshot`

The composer's rebuild-skip path needs to check whether the previous frame's snapshots match the current frame's — but `StemFeatures` is a `@frozen` GPU-shared SIMD-aligned struct (broadening conformance is a separate decision per D-085) and `BeatSyncSnapshot` is a Sendable instrumentation value type (doesn't otherwise warrant an Equatable conformance for engine code). Adding Equatable to either would broaden public API beyond what one internal cache needs. The composer instead implements a private generic `bytewiseEqual<T>` using `withUnsafeBytes` + `memcmp`. `PerfSnapshot` already conforms to `Equatable` (D-085) and uses the synthesized `==`. Test (b) regression-locks the rebuild-skip behaviour against equal snapshots.

### Decision 5 — Premultiplied alpha discipline in the composite pipeline

The layer's CGContext is configured with `kCGBitmapByteOrder32Little | premultipliedFirst`, so glyph + chrome pixels arrive in the texture as premultiplied sRGB. The composite pipeline state therefore configures blending as `src = .one`, `dst = .oneMinusSourceAlpha` (rather than `.sourceAlpha` / `.oneMinusSourceAlpha`). Using `.sourceAlpha` would double-multiply the source RGB by its own alpha and produce a visible black halo at card edges where chrome alpha drops. Verified by reading `DashboardTextLayer.makeResources` before finalizing the descriptor.

### Decision 6 — Per-frame snapshot rebuild cost is acceptable (CGContext text drawing on M-series is sub-millisecond)

The DASH.5 prompt allowed builder-level computation per frame because the alternative (caching layouts at preset-switch time and patching individual rows on update) is much more code for a sub-1% perf win. DASH.6 keeps the same model: `update()` rebuilds all three layouts and repaints the entire layer when any snapshot differs from the previous frame. Steady-state BAR sustain (no snapshot change) hits the bytewise-equality fast path and skips repaint entirely. Engine soak data + on-device measurement remain follow-ups, but the test suite (1130 engine tests, 130 suites) showed no measurable build-time regression from the per-frame rebuild path.

### Decision 7 — DASH.6.1 amendment slot for any per-card position / margin / order / colour tuning

Live D-toggle review on real music is the acceptance artifact (no static PNG). If Matt's eyeball flags any per-card visual issue (chrome misplaced, cards stacked outside the drawable, spacing wrong, top-right margin off, font fallback ugly), DASH.6.1 is the amendment slot. The DASH.6 closeout is the structural delivery (composer + wiring + dedup + tests + docs); v1 visual tuning lives in 6.1. Same pattern as DASH.4.1 / DASH.5.1.

### Tests

After DASH.6: **45 dashboard tests pass** (12 DASH.1 + 6 DASH.2.1 + 6 BeatCardBuilder + 3 progress-bar + 6 StemsCardBuilder + 6 PerfCardBuilder + 6 DashboardComposer). Full engine suite green: 1130 tests / 130 suites. 0 SwiftLint violations on touched files; xcodebuild app build clean.

### Files changed

New: `PhospheneEngine/Sources/Renderer/Dashboard/DashboardComposer.swift`, `PhospheneEngine/Sources/Renderer/Shaders/Dashboard.metal`, `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/DashboardComposerTests.swift`. Edited: `PhospheneEngine/Sources/Shared/Dashboard/DashboardTokens.swift` (`Spacing.cardGap`), `PhospheneEngine/Sources/Renderer/RenderPipeline.swift` (composer setter + `hasDashboardComposer` + `compositeDashboard` helper + resize forward), every `RenderPipeline+*.swift` draw-path file (composite call before each `present`), `PhospheneApp/VisualizerEngine.swift` (composer property + `dashboardEnabled`), `PhospheneApp/VisualizerEngine+InitHelpers.swift` (composer alloc + `assemblePerfSnapshot` + per-frame snapshot push wired onto `onFrameRendered`), `PhospheneApp/Views/Playback/PlaybackView.swift` (`D` toggle writes `engine.dashboardEnabled`), `PhospheneApp/Views/DebugOverlayView.swift` (Tempo / QUALITY / ML rows removed).
