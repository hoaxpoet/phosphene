Execute Increment DASH.6 — Overlay wiring + `D` key toggle.

Authoritative spec: docs/ENGINEERING_PLAN.md §Phase DASH §Increment DASH.6.
Authoritative design: .impeccable.md §Aesthetic Direction (Color, Typography),
§State-Specific Design Notes, §Anti-Patterns. Read both before writing
any code.

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. DASH.5 must have landed. Verify with
   `git log --oneline | grep '\[DASH\.5\]'` — expect two commits
   ending with `[DASH.5] docs: ENGINEERING_PLAN, DECISIONS D-085, …`.

2. Confirm DASH.5's API surface is in place:
   `test -f PhospheneEngine/Sources/Renderer/Dashboard/PerfSnapshot.swift && \
    test -f PhospheneEngine/Sources/Renderer/Dashboard/PerfCardBuilder.swift`
   — both files must exist.

3. Confirm DASH.3 + DASH.4 builders are still in place:
   `test -f PhospheneEngine/Sources/Renderer/Dashboard/BeatCardBuilder.swift && \
    test -f PhospheneEngine/Sources/Renderer/Dashboard/StemsCardBuilder.swift`.

4. Decision-ID numbering: D-085 covers DASH.5. The next available number
   is **D-086**. Verify with
   `grep '^## D-0' docs/DECISIONS.md | tail -3`.

5. Existing wiring you will read (do NOT modify the manager classes):

   - `PhospheneApp/VisualizerEngine.swift`
     - `var latestBeatSyncSnapshot: BeatSyncSnapshot = .zero` + `beatSyncLock: NSLock`
       (DSP.3.3) — the BEAT card's input.
     - `var mlDispatchScheduler: MLDispatchScheduler?` — the PERF card's ML input.
     - `var deviceTier: DeviceTier` — for per-tier `targetFrameMs` defaults.
     - `var currentQualityLevel: FrameBudgetManager.QualityLevel` — read-through to
       `pipeline.frameBudgetManager?.currentLevel`.
     - `var currentMLSchedulerState: String` — the existing `DebugOverlayView` ML row.

   - `PhospheneEngine/Sources/Renderer/RenderPipeline.swift`
     - `public var frameBudgetManager: FrameBudgetManager?` — the PERF card's
       FRAME row input. Has `recentMaxFrameMs` / `recentFramesObserved` /
       `currentLevel` / `configuration.targetFrameMs`.
     - `var latestStemFeatures = StemFeatures.zero` + `stemFeaturesLock` —
       the STEMS card's input. Already populated by the stem pipeline.
     - `public var dynamicTextOverlay: DynamicTextOverlay?` and
       `public var textOverlayCallback: ((DynamicTextOverlay, FeatureVector) -> Void)?`
       — existing pattern for "render-thread CPU writes into a shared MTLBuffer
       texture; GPU samples it later in the same command buffer." DASH.6 follows
       the *exact same* pattern for the dashboard layer (see SCOPE).

   - `PhospheneApp/Services/PlaybackShortcutRegistry.swift:317` —
     `debugToggle` shortcut, key `"d"`, calls `onToggleDebug` closure.
     `PhospheneApp/Views/Playback/PlaybackView.swift:46` —
     `@State private var showDebug: Bool = false`.
     `PhospheneApp/Views/Playback/PlaybackView.swift:286` — closure that
     toggles `showDebug`. **DASH.6 reuses this single shortcut and bool**:
     `D` toggles BOTH the new dashboard cards (top-right Metal) AND the
     existing `DebugOverlayView` (bottom-leading SwiftUI). One key, one
     bool, both surfaces appear and disappear together. The dashboard is
     not a *replacement* for `DebugOverlayView` — it is the strict-quality
     "the user-readable instruments" surface, while `DebugOverlayView`
     remains the developer raw-diagnostic surface for fields the cards do
     not show (mood V/A, signal level, MIR diag, spider diagnostics,
     G-buffer mode, REC).

6. `default.profraw` may be present in the repo root. Ignore.

────────────────────────────────────────
GOAL
────────────────────────────────────────

DASH.3, DASH.4, DASH.5 produced three pure-data card builders with
artifacts. DASH.6 is the increment that takes them live: cards rendered
to the actual playback surface, updated every frame from real session
state, toggled by the existing `D` shortcut, with no measurable frame-
budget regression.

This increment produces:

  1. A `DashboardComposer` (`@MainActor`, owns lifecycle of the
     `DashboardTextLayer` + a small alpha-blended composite Metal
     pipeline state) that:
     - takes `BeatSyncSnapshot` + `StemFeatures` + `PerfSnapshot` per frame
       via a single Sendable `update(...)` call;
     - rebuilds card layouts via the three existing builders;
     - paints all three cards into the layer's CGContext (top-down stack:
       BEAT, STEMS, PERF) with `DashboardTokens.Spacing.cardGap` between cards;
     - exposes `composite(into commandBuffer:, drawable:)` so the render
       pipeline can blit the cards into the top-right of the drawable
       AFTER the active preset has finished writing.

  2. A `Spacing.cardGap` token — alias for `Spacing.md` (12 pt). Future-
     proofing for a DASH.6.1 retune; named so call sites read intent.

  3. RenderPipeline wiring: `setDashboardComposer(_:)` setter (mirrors
     `setDynamicTextOverlay` + `setTextOverlayCallback`); call site at
     the tail of `renderFrame` (or each draw path's tail — pick whichever
     is less invasive — see SCOPE) that invokes
     `composer?.composite(into: commandBuffer, drawable: drawable)` when
     dashboard is enabled.

  4. VisualizerEngine wiring: per-frame `assembleSnapshots()` that reads
     `latestBeatSyncSnapshot`, `pipeline.latestStemFeatures`, and
     assembles a `PerfSnapshot` from `frameBudgetManager` + `mlDispatchScheduler`,
     then calls `composer.update(...)`. Hooked into the existing
     `onFrameRendered` chain or directly before the preset draw — see
     SCOPE Decision A.

  5. PlaybackView wiring: `engine.dashboardEnabled = showDebug`
     binding (the `D` key flips both the SwiftUI debug overlay AND the
     dashboard composer).

  6. `DebugOverlayView` deduplication: the rows that the dashboard now
     covers (Tempo / standalone QUALITY block / standalone ML block) are
     deleted from `DebugOverlayView`. Mood, Key, Signal, MIR diag, spider,
     G-buffer, and REC all stay — none of those are in the cards.

────────────────────────────────────────
SCOPE
────────────────────────────────────────

1. NEW FILE — `Spacing.cardGap` token (edit existing tokens file)
   Path: `PhospheneEngine/Sources/Shared/Dashboard/DashboardTokens.swift`

   Add to the `Spacing` struct:
   ```swift
   /// Vertical gap between stacked dashboard cards. Aliased to `md` (12 pt)
   /// in v1; the named token reserves a DASH.6.1 retune slot.
   public static let cardGap: CGFloat = md
   ```

2. NEW FILE — `DashboardComposer.swift`
   Path: `PhospheneEngine/Sources/Renderer/Dashboard/DashboardComposer.swift`

   ```
   /// Owns the per-frame lifecycle of the dashboard cards: layer
   /// allocation, card painting, top-right composite into the drawable.
   ///
   /// `@MainActor` because the SwiftUI / `MTKView` driver is main-actor;
   /// snapshots are taken from main-actor properties on `VisualizerEngine`.
   /// The class is final so the test suite can subclass via composition,
   /// not inheritance.
   ///
   /// Lifecycle:
   ///   1. Init at app startup with a Metal device + the test-bundle resource
   ///      anchor (for `DashboardFontLoader`).
   ///   2. `update(beat:, stems:, perf:)` called once per frame from
   ///      `VisualizerEngine` before the render pass; rebuilds card layouts
   ///      and paints into the layer's CGContext if any input changed.
   ///   3. `composite(into commandBuffer:, drawable:)` called from
   ///      `RenderPipeline.renderFrame` AFTER the preset has finished writing
   ///      to `drawable`; blits the cards via an alpha-blended fullscreen
   ///      pass scoped to a top-right viewport.
   ///   4. `resize(to drawableSize:)` called from
   ///      `RenderPipeline.mtkView(_:drawableSizeWillChange:)` to recompute
   ///      top-right placement.
   ///
   /// The composer has its own `enabled: Bool` flag — when false, both
   /// `update` and `composite` short-circuit cheaply (no MTLBuffer write,
   /// no GPU encoder). Tied to `D` via `VisualizerEngine.dashboardEnabled`.
   @MainActor
   public final class DashboardComposer {

       /// User toggle, bound to the existing `D` shortcut. False = no card
       /// rendering, no GPU work, no CPU rebuilds.
       public var enabled: Bool = false

       public init?(
           device: MTLDevice,
           bundle: Bundle?,
           layerWidth: CGFloat = 320,
           layerHeight: CGFloat = 660
       )

       /// Per-frame snapshot push. Cheap pass-through when `enabled == false`
       /// or when all three snapshots compare equal to the previous frame.
       public func update(
           beat: BeatSyncSnapshot,
           stems: StemFeatures,
           perf: PerfSnapshot
       )

       /// Encode the alpha-blended top-right composite. No-op when
       /// `enabled == false`.
       public func composite(
           into commandBuffer: MTLCommandBuffer,
           drawable: CAMetalDrawable
       )

       /// Recompute top-right placement when the drawable size changes.
       public func resize(to drawableSize: CGSize)
   }
   ```

   Internals (file-private, NOT in the public surface):
   - Owns one `DashboardTextLayer` (320 × 660 — large enough for three
     stacked cards: BEAT ≈ height(4 rows incl. progressBar+singleValue),
     STEMS ≈ height(4 .bar rows), PERF ≈ height(3 mixed rows), plus
     2 × `Spacing.cardGap`. Use `DashboardCardLayout.height` to compute,
     not a hardcoded total).
   - Owns three builders as stored properties (`BeatCardBuilder`,
     `StemsCardBuilder`, `PerfCardBuilder`) — they are `Sendable` zero-
     state structs.
   - Owns one `MTLRenderPipelineState` that samples the layer texture and
     writes RGBA with alpha-blending enabled (src=`.sourceAlpha`, dst=
     `.oneMinusSourceAlpha`, premultiplied is fine). Vertex stage reuses
     the engine's `fullscreen_vertex` (already in `Common.metal`); fragment
     stage is a new tiny `dashboard_composite_fragment` in a new
     `Shaders/Dashboard.metal` file (see SCOPE 3) that samples
     `[[texture(0)]]` with bilinear and outputs the sample.
   - Tracks the last applied `(BeatSyncSnapshot, StemFeatures, PerfSnapshot)`
     so `update()` can short-circuit when all three are equal. Use
     synthesized `Equatable`. (`StemFeatures` already conforms via the
     `@frozen` SIMD structure; if it does NOT conform yet, fall back to
     a conservative `memcmp` over `MemoryLayout<StemFeatures>.size` rather
     than adding a public `Equatable` conformance to a GPU-shared type —
     do NOT introduce `Equatable` on `StemFeatures` in this increment;
     test (b) regression-locks the no-rebuild-on-equal path either way.)
   - Composite viewport: bottom-right of dashboard layer maps to top-right
     of drawable. Use `MTLViewport` with `originX = drawableWidth - layerWidthPx
     - margin`, `originY = margin`, `width = layerWidthPx`, `height = layerHeightPx`,
     where `margin = Spacing.lg` (16 pt) and `layerWidthPx`/`layerHeightPx`
     are the layer's pixel dimensions converted from points via the
     drawable's contentsScale. (NSScreen-aware scaling; do NOT hardcode 2×.)
   - Composite render pass: `loadAction = .load`, `storeAction = .store`,
     drawable as the only colour attachment. Encoder lifecycle is one
     encoder per `composite()` call.
   - Card painting (in `update()`):
     ```
     layer.beginFrame()
     // No backdrop fill — chrome is alpha-blended over the live drawable.
     let renderer = DashboardCardRenderer()
     var cursorY: CGFloat = Spacing.md  // top inset
     for layout in [beatLayout, stemsLayout, perfLayout] {
         renderer.render(
             layout,
             at: CGPoint(x: Spacing.md, y: cursorY),
             on: layer,
             cgContext: layer.graphicsContext
         )
         cursorY += layout.height + Spacing.cardGap
     }
     // Single layer.commit happens inside composite() so the CPU write
     // and the GPU sample are in the same MTLCommandBuffer.
     ```
     Note: `layer.commit(into:)` is called from `composite()`, not
     `update()`. Splitting beginFrame/draw (in update) from commit (in
     composite) keeps the CPU rasterization scheduled with the same
     command buffer that samples the texture — same lifetime guarantee
     as the existing `DynamicTextOverlay` pattern.

3. NEW FILE — `Dashboard.metal`
   Path: `PhospheneEngine/Sources/Renderer/Shaders/Dashboard.metal`

   Two functions:
   - Reuse `fullscreen_vertex` from `Common.metal` (no need to duplicate)
     — wire it via `vertex_function: "fullscreen_vertex"` in the pipeline
     descriptor. If `Common.metal`'s `fullscreen_vertex` is in a private
     namespace, declare a new `dashboard_composite_vertex` here that
     emits the same `(position, uv)` for vertex IDs 0..2.
   - `fragment float4 dashboard_composite_fragment(...)` — samples
     `texture0` with `clamp_to_zero` + `linear` and returns the sample.
     Alpha blending is configured on the pipeline state, not in the
     shader (the texture itself carries the chrome's pre-multiplied alpha
     directly out of `bgra8Unorm`). Verify: the layer's CGContext is
     already configured for premultiplied sRGB in `DashboardTextLayer` —
     no extra unpremultiply needed in the fragment.

4. EDIT — `RenderPipeline.swift` (lifecycle setter)

   Add (mirroring the `dynamicTextOverlay` pattern):
   ```swift
   var dashboardComposer: DashboardComposer?
   let dashboardComposerLock = NSLock()

   public func setDashboardComposer(_ composer: DashboardComposer?) {
       dashboardComposerLock.withLock { dashboardComposer = composer }
   }
   ```

   Public read-through accessor for tests:
   ```swift
   public var hasDashboardComposer: Bool {
       dashboardComposerLock.withLock { dashboardComposer != nil }
   }
   ```

   In `mtkView(_:drawableSizeWillChange:)`, forward to the composer:
   ```swift
   dashboardComposerLock.withLock { dashboardComposer }?.resize(to: size)
   ```

5. EDIT — `RenderPipeline+Draw.swift` (composite call site)

   At the end of `renderFrame(...)` (or at the tail of each draw-path
   helper that ultimately writes to the drawable — pick the LEAST
   invasive site that runs after the preset has finished writing and
   BEFORE `commandBuffer.present(drawable)` / `commandBuffer.commit()`).

   The single-call-site approach: at the tail of `renderFrame`, after
   all path-specific draw helpers return but before the command buffer
   is committed, snapshot the composer under its lock and call:
   ```swift
   if let composer = dashboardComposerLock.withLock({ dashboardComposer }),
      let drawable = view.currentDrawable {
       composer.composite(into: commandBuffer, drawable: drawable)
   }
   ```

   If the existing draw paths each commit their command buffer
   individually rather than returning to `renderFrame` for a shared
   commit, choose Decision A:

   **Decision A (preferred):** centralize commit at the end of
   `renderFrame` so the dashboard composite always lands on the same
   command buffer as the preset draw. If this requires moving more
   than ~30 lines of code or refactoring how draw paths interact with
   the command buffer, STOP and surface the scope — do NOT silently
   expand DASH.6 into a render-loop refactor.

   **Decision B (fallback):** add the composite call at the tail of
   each draw path helper that currently commits the command buffer.
   Acceptable cost: ~5 sites × 3 lines each. Document in D-086 that
   the dashboard is composited per-path because the engine's draw paths
   own their own command buffers (deferred until a future render-loop
   refactor).

   Document the chosen decision in D-086.

6. EDIT — `VisualizerEngine.swift` + `VisualizerEngine+InitHelpers.swift`

   Add stored property:
   ```swift
   var dashboardComposer: DashboardComposer?
   /// Bound to the existing `D` shortcut via PlaybackView's `showDebug`.
   public var dashboardEnabled: Bool {
       get { dashboardComposer?.enabled ?? false }
       set { dashboardComposer?.enabled = newValue }
   }
   ```

   In the existing init helpers, after `pipe` (RenderPipeline) is
   constructed, allocate the composer and wire it:
   ```swift
   if let composer = DashboardComposer(
       device: pipe.metalContext.device,
       bundle: Bundle(for: type(of: self))
   ) {
       self.dashboardComposer = composer
       pipe.setDashboardComposer(composer)
   }
   ```

   Add `assembleAndPushDashboardSnapshots()` helper called from the same
   site that currently writes per-frame state to the pipeline. The
   helper:
   - reads `latestBeatSyncSnapshot` under `beatSyncLock`;
   - reads `pipeline.latestStemFeatures` (use a small public read accessor
     `RenderPipeline.snapshotLatestStemFeatures()` if one doesn't exist —
     it does internally, just expose it as `public func` mirroring the
     existing `setStemFeatures` setter pattern);
   - assembles `PerfSnapshot` from
     - `pipe.frameBudgetManager?.recentMaxFrameMs ?? 0`
     - `pipe.frameBudgetManager?.recentFramesObserved ?? 0`
     - `pipe.frameBudgetManager?.configuration.targetFrameMs ?? 14`
     - `pipe.frameBudgetManager?.currentLevel.rawValue ?? 0`
     - `pipe.frameBudgetManager?.currentLevel.displayName ?? "full"`
     - ML decision code from `mlDispatchScheduler?.lastDecision`:
       `nil → 0`, `.dispatchNow → 1`, `.defer(let ms) → 2`,
       `.forceDispatch → 3`
     - `mlDeferRetryMs` from the `.defer(retryInMs:)` case (else 0)
   - calls `dashboardComposer?.update(beat:..., stems:..., perf:...)`.

   Hook the call site into the existing per-frame path. The simplest
   placement is in the existing `onFrameRendered` closure at
   `VisualizerEngine+InitHelpers.swift` — that closure already runs once
   per rendered frame on `@MainActor`. Add the
   `assembleAndPushDashboardSnapshots()` call there, OR at the head of
   the audio-driven render-tick if `onFrameRendered` runs after the
   command buffer commits (in which case the dashboard would be one
   frame stale; check the existing code path before choosing).

7. EDIT — `PhospheneApp/Views/Playback/PlaybackView.swift`

   In the `setup()` block (or the closest equivalent that already wires
   ViewModels with engine state), add:
   ```swift
   engine.dashboardEnabled = showDebug
   ```

   In the `onChange(of: showDebug)` modifier (or via a watcher pattern
   matching the existing `showDebug` toggles), propagate every change to
   `engine.dashboardEnabled`.

   Note: the SwiftUI `DebugOverlayView` continues to render conditionally
   on `if showDebug` exactly as it does today — DASH.6 does NOT change
   the SwiftUI overlay's visibility behaviour, only its CONTENT (item 8).

8. EDIT — `PhospheneApp/Views/DebugOverlayView.swift`

   Delete only the rows whose information is now in the dashboard
   cards. Specifically:
   - The `label("Tempo", ...)` row inside the "MOOD (LIVE)" section
     (BEAT card already shows BPM).
   - The standalone `QUALITY:` HStack block (PERF card already shows
     QUALITY).
   - The standalone `ML:` HStack block (PERF card already shows ML).
   - The single `Divider().background(.white.opacity(0.3))` immediately
     preceding the deleted QUALITY/ML pair (avoid leaving an orphan
     divider).

   KEEP everything else: track info, pre-fetched profile, MOOD V/A,
   Key, SIGNAL block (peak/rms/sub/mid/treble + reason), raw MIR
   diagnostics, spider trigger, G-buffer mode, REC.

   Do NOT add new content to `DebugOverlayView` in this increment.

9. NEW TEST FILE — `DashboardComposerTests.swift`
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/DashboardComposerTests.swift`

   Six `@Test` functions in `@Suite("DashboardComposer")`:

   a. **`init_returnsNonNil_whenMetalAvailable`**: construct with a
      real `MTLCreateSystemDefaultDevice()`; assert the optional init
      succeeded. Skip via `withKnownIssue` when no device.

   b. **`update_idempotent_whenSnapshotsUnchanged`**: call `update`
      with the same trio twice; capture the layer's texture's first 32
      bytes via `getBytes` after each call (or compare a checksum field
      the composer exposes for testing — e.g., an internal
      `frameRebuildCount: Int` marked `internal` so tests can read it).
      Assert the second `update` does NOT increment the rebuild count.

   c. **`update_rebuilds_whenAnyInputChanges`**: three sub-assertions —
      change only `beat` → rebuild fires; change only `stems` → rebuild
      fires; change only `perf` → rebuild fires.

   d. **`composite_withDisabledComposer_isNoOp`**: set
      `composer.enabled = false`, call `composite(into:drawable:)`
      where `drawable` is a stub `CAMetalDrawable` (use a 1×1
      offscreen `MTLTexture` wrapped via `MockMetalDrawable` if
      `CAMetalDrawable` cannot be constructed in tests — see
      `RenderPipelineICBTests` for the existing pattern). Assert no
      encoder is created (e.g., command buffer's `encoderCount` after
      composite equals 0).

   e. **`update_thenComposite_producesNonZeroAlphaInTopRight`**: feed
      a non-trivial PerfSnapshot (the `forcedDispatch` fixture from
      `PerfCardBuilderTests`), commit a real command buffer onto an
      offscreen 1920×1080 `.bgra8Unorm` texture (treat as the drawable
      surrogate), wait for completion, read back a pixel from the
      top-right card region (e.g. (1700, 100)). Assert non-zero alpha
      (>0). Skip via `withKnownIssue` without Metal.

   f. **`resize_recomputesPlacement`**: call `resize(to: CGSize(width: 3840, height: 2160))`,
      then composite onto a 3840×2160 surrogate, read back a pixel
      from the top-right region (e.g. (3700, 100)). Assert non-zero
      alpha. Regression-locks the contentsScale-aware placement.

   Add Metal helpers locally in the test file (file-independence
   convention): `makeOffscreenDrawable(device:width:height:)` returning
   `(MTLTexture, drawable: protocol stub)`. Reuse `writeTextureToPNG`
   from `Tests/.../TestHelpers/TextureToPNG.swift` if writing a debug
   artifact — but DASH.6 does NOT require an artifact; the M7 review
   is the live D-toggle eyeball, not a static PNG.

10. ARTIFACT (optional)
    DASH.6 does NOT require a static PNG artifact. The acceptance
    artifact is **the live D-toggle on real music** (see VERIFICATION
    step 7). Optionally, test (e) may save
    `.build/dash1_artifacts/dashboard_composite_active.png` for
    review against the BEAT/STEMS/PERF artifacts — but if doing so
    increases test runtime above 0.5 s, drop the artifact write.

────────────────────────────────────────
NON-GOALS (DO NOT IMPLEMENT)
────────────────────────────────────────

- Do NOT add a fourth card (MOOD, METADATA, SIGNAL). DASH.6 wires
  exactly the three cards that exist.
- Do NOT change card visual design (chrome, typography, colours, row
  heights, fill geometry). Any visual tuning surfaced by the live
  D-toggle review is DASH.6.1 amendment scope.
- Do NOT introduce per-card visibility toggles (BEAT-only mode,
  PERF-only mode, etc.). One `D` shortcut, three cards always.
- Do NOT animate card show/hide. `D` is binary; transitions are out
  of scope and would conflict with .impeccable's "no animation" rule.
- Do NOT relocate `DebugOverlayView` (e.g. move SwiftUI overlay
  somewhere else to make room for the cards). The cards live top-right
  via Metal; the SwiftUI overlay stays bottom-leading. They do not
  collide.
- Do NOT add any new public API to `RenderPipeline` beyond
  `setDashboardComposer(_:)` + `hasDashboardComposer`. Anything more
  is scope creep.
- Do NOT add `Equatable` conformance to `StemFeatures`. It's a GPU-
  shared `@frozen` SIMD struct; broadening conformance is a separate
  decision. The rebuild-skip path may use `memcmp` over
  `MemoryLayout<StemFeatures>.size` privately inside the composer.
- Do NOT add a render-loop refactor. If centralizing the command-
  buffer commit inside `renderFrame` (Decision A) requires more than
  ~30 lines of structural change, take Decision B (per-path composite
  call sites) and note the deferred refactor in D-086.
- Do NOT change the `DashboardTextLayer` API. The existing
  `beginFrame()` / `commit(into:)` / `graphicsContext` surface is
  exactly what the composer needs.
- Do NOT introduce a `dashboardComposer` accessor on `RenderPipeline`
  — `setDashboardComposer(_:)` plus `hasDashboardComposer: Bool` for
  tests is sufficient. Hold the strong reference on `VisualizerEngine`,
  not on `RenderPipeline` (RenderPipeline takes a weak read via the
  setter).

────────────────────────────────────────
DESIGN GUARDRAILS (.impeccable.md)
────────────────────────────────────────

- **Stable absence-of-information.** When `dashboardEnabled == false`,
  the overlay is gone. When enabled but data is starting (zero stems,
  no BeatGrid, no frame observations), every card's "no info" state
  has already been designed in DASH.3/4/5 (REACTIVE / zero bars / FRAME
  `—`). Trust those decisions — DASH.6 just lights them up.

- **Top-right corner placement.** The .impeccable dashboard reference
  imagery places HUD elements top-right, balanced against bottom-left
  status. `DebugOverlayView` is bottom-leading; cards are top-trailing.
  No collision, balanced composition.

- **Margin 16 pt.** `Spacing.lg` from the layer's outer edge to the
  drawable's top and right edges. Same on both sides.

- **No pulse / no flash / no animation.** The dashboard is a stable
  surface. Update happens in place; cards never tween between
  states.

- **No backdrop blur / no shadow.** The chrome's 0.92α already
  separates cards from the active visual. Adding an extra blur or
  shadow layer would double-encode separation and waste fill rate.
  (.impeccable purposeful-glassmorphism exception is exactly the
  chrome's 0.92α and nothing more.)

- **One eye, one read.** Cards stack in priority order: BEAT first
  (the user's primary "is the music tracking?" check), STEMS second
  (the "are the visuals coupled to the right stems?" check), PERF
  last (the developer / device-tier check). Do not re-order on
  device tier or user role; the order is global.

────────────────────────────────────────
VERIFICATION
────────────────────────────────────────

Order matters. Each step must pass before proceeding.

1. **Build (engine)**: `swift build --package-path PhospheneEngine`
   — must succeed with zero warnings on touched files.

2. **Build (app)**: `xcodebuild -scheme PhospheneApp -destination \
   'platform=macOS' build 2>&1 | tail -3` — must end
   `** BUILD SUCCEEDED **`.

3. **Test (focused)**: `swift test --package-path PhospheneEngine \
   --filter "DashboardComposer|BeatCardBuilder|StemsCardBuilder|\
   PerfCardBuilder|DashboardCardRenderer|DashboardTextLayer|\
   DashboardTokens|DashboardFontLoader"` — all 45 tests pass
   (12 DASH.1 + 6 DASH.2.1 + 6 BeatCardBuilder + 3 ProgressBar +
   6 StemsCardBuilder + 6 PerfCardBuilder + 6 DashboardComposer).

4. **Test (full)**: `swift test --package-path PhospheneEngine` —
   full suite green except the documented pre-existing flakes (see
   DASH.4/DASH.5 release notes — `MetadataPreFetcher` network-
   timeout, `MemoryReporter.residentBytes` env-dependent, the two
   GPU-perf parallel-run flakes). Any other failure is a regression.

5. **SwiftLint**: `swiftlint lint --strict --config .swiftlint.yml \
   --quiet PhospheneEngine/Sources/Renderer/Dashboard/ \
   PhospheneEngine/Sources/Renderer/Shaders/Dashboard.metal \
   PhospheneEngine/Sources/Shared/Dashboard/ \
   PhospheneEngine/Tests/PhospheneEngineTests/Renderer/ \
   PhospheneApp/Views/DebugOverlayView.swift \
   PhospheneApp/Views/Playback/PlaybackView.swift \
   PhospheneApp/VisualizerEngine.swift \
   PhospheneApp/VisualizerEngine+InitHelpers.swift` — zero
   violations on touched files.

6. **Frame-budget regression** (semi-manual). Run the soak harness
   for 60 seconds with dashboard ON and 60 seconds with it OFF:
   ```
   SOAK_TESTS=1 swift test --package-path PhospheneEngine \
     --filter SoakTestHarnessTests
   ```
   Compare p50 / p95 / p99 frame times across the two runs. P95
   delta must be < 0.5 ms on the dev Mac mini (Tier 2). Document
   the numbers in the closeout report. If the delta exceeds 0.5 ms,
   STOP — diagnose before committing.

7. **Live D-toggle review** (manual, user-driven; required). On a
   real music session (e.g. Love Rehab via Spotify-prepared, where
   BeatGrid + drift tracker are exercised):
   - Start the session, press `D`. All three cards appear top-right.
     SwiftUI overlay appears bottom-leading.
   - BEAT card: MODE cycles REACTIVE → LOCKING → LOCKED as the drift
     tracker engages. BPM matches the prepared grid value (~125).
     BAR row's beat-in-bar counter advances 1 / 4 → 2 / 4 → 3 / 4 →
     4 / 4 in tempo. BEAT row's progress bar fills and resets each
     beat.
   - STEMS card: bar fills track the kick (DRUMS pushes right on each
     downbeat), bass fills (BASS row), and vocals/other.
   - PERF card: FRAME shows live frame time (sub-budget on M3+,
     ~5–9 ms typical), QUALITY reads `full` in green, ML cycles
     READY ↔ WAIT during stem-pipeline activity.
   - Press `D` again. All three cards disappear, SwiftUI overlay
     disappears.
   - Confirm the SwiftUI overlay no longer shows Tempo / standalone
     QUALITY / standalone ML rows (those are now exclusively in the
     PERF / BEAT cards).
   - If any card reads as broken (chrome misplaced, card text
     unreadable, cards overlap, top-right margin wrong), surface the
     observation; do NOT unilaterally retune — that's DASH.6.1 scope.

────────────────────────────────────────
DOCUMENTATION OBLIGATIONS
────────────────────────────────────────

After verification passes:

1. **`docs/ENGINEERING_PLAN.md`** — Phase DASH §Increment DASH.6:
   flip status to ✅ with the date. Update the "Done when" checklist.
   Add a one-line implementation summary noting `DashboardComposer`,
   the `Spacing.cardGap` token, the per-frame snapshot assembly path,
   and the `DebugOverlayView` deduplication.

2. **`docs/DECISIONS.md`** — append D-086 covering:
   - Why a `DashboardComposer` (not a free function on `RenderPipeline`):
     lifecycle coupling between layer + builders + composite pipeline +
     enabled flag is cohesive; encapsulating in one class makes the
     `D`-toggle a single property change with no fan-out.
   - Decision A (centralized commit) vs Decision B (per-path composite
     call sites). Document the chosen one with the LOC delta.
   - Why per-frame snapshot rebuild is acceptable cost (CGContext text
     drawing is sub-millisecond on M-series; rebuild-skip on equal
     snapshots covers steady-state BAR sustain).
   - Why a single `D` toggle drives BOTH the SwiftUI overlay and the
     dashboard composer: one cognitive model, no per-surface UX. Cards
     and SwiftUI debug overlay are complementary surfaces (instruments
     vs raw diagnostics), not alternatives.
   - Why `Equatable` is NOT added to `StemFeatures` — broadening
     conformance on a `@frozen` SIMD GPU-shared type is a separate
     decision; the composer's rebuild-skip uses private `memcmp`.
   - Why no fourth card (mood / metadata / signal): DASH.6 wires what
     exists; new cards belong to a future increment with their own
     scope. Mood is conspicuously not a card v1 — Matt's eyeball at
     the live D-toggle will decide whether MOOD belongs in the
     dashboard or remains a SwiftUI debug-overlay concern.
   - The DASH.6.1 amendment slot for any per-card position / margin /
     order / colour tuning surfaced by Matt's eyeball.

3. **`docs/RELEASE_NOTES_DEV.md`** — append `[dev-YYYY-MM-DD-X] DASH.6
   — Overlay wiring + D toggle` entry covering files added/edited,
   tests added, what's intentionally NOT in this increment (no fourth
   card, no animation, no per-card toggle, no render-loop refactor),
   decision IDs, test-suite count delta (39 → 45 dashboard tests),
   p50/p95/p99 frame-budget numbers.

4. **`CLAUDE.md` Module Map** — under `Renderer/Dashboard/`, add:
   - `DashboardComposer` — `@MainActor` lifecycle owner of the
     dashboard's `DashboardTextLayer` + three card builders (BEAT,
     STEMS, PERF) + alpha-blended top-right composite pipeline.
     Per-frame `update(beat:stems:perf:)` rebuilds card layouts (skips
     when all three snapshots equal previous frame); `composite(into:
     drawable:)` blits via `loadAction = .load` at the tail of
     `renderFrame`. `enabled: Bool` bound to `D` shortcut via
     `VisualizerEngine.dashboardEnabled` — same toggle drives both
     dashboard and SwiftUI debug overlay. DASH.6, D-086.

   Update the existing `DebugOverlayView` Module Map entry (if there
   is one — check `PhospheneApp/Views/`) to note the dashboard-card
   deduplication: Tempo / standalone QUALITY / standalone ML rows
   removed; mood / signal / MIR diag / spider / G-buffer / REC remain.

────────────────────────────────────────
COMMITS
────────────────────────────────────────

Two commits, in this order. Each must pass tests at the commit boundary.

1. `[DASH.6] dashboard: wire DashboardComposer + D-toggle + dedup DebugOverlayView`
   — `DashboardComposer.swift` + `Dashboard.metal` + `DashboardTokens.swift`
   (cardGap addition) + `RenderPipeline.swift` + `RenderPipeline+Draw.swift`
   + `VisualizerEngine.swift` + `VisualizerEngine+InitHelpers.swift` +
   `PlaybackView.swift` + `DebugOverlayView.swift` +
   `DashboardComposerTests.swift`. All in one commit because the
   dashboard composer cannot land usefully without the wiring; splitting
   leaves an unused class on `main`.

2. `[DASH.6] docs: ENGINEERING_PLAN, DECISIONS D-086, release note,
   CLAUDE.md module map`
   — docs only.

Local commits to `main` only. Do NOT push to remote without explicit
"yes, push" approval.

────────────────────────────────────────
RISKS & STOP CONDITIONS
────────────────────────────────────────

- **Premultiplied vs straight alpha.** `DashboardTextLayer` uses
  `bgra8Unorm` and a sRGB CGContext that produces premultiplied alpha
  by convention. The composite pipeline must be configured for
  premultiplied source: `sourceRGBBlendFactor = .one`,
  `destinationRGBBlendFactor = .oneMinusSourceAlpha` (NOT
  `.sourceAlpha` — that would double-multiply). Verify by reading
  `DashboardTextLayer.swift` for the bitmap context flags before
  finalizing the pipeline state. If chrome shows a black halo at
  card edges, premultiplication is wrong.

- **Composite call site landing AFTER drawable present.** If the
  composite encoder is created after `commandBuffer.present(drawable)`
  has been recorded, GPU validation fires and the dashboard is not
  visible. The composite pass MUST be encoded before any present /
  commit call in the chosen draw path.

- **Snapshot data races.** `latestBeatSyncSnapshot` is read on
  `@MainActor` under `beatSyncLock`; `latestStemFeatures` is read
  on the render thread under `stemFeaturesLock`. The composer's
  `update(...)` runs on `@MainActor`. Use the engine's existing
  read accessors; do NOT bypass the locks.

- **Drawable lifetime.** `CAMetalDrawable` is valid only between
  `currentDrawable` access and `present`. The composite call must
  fall inside that window. If `composer.composite(...)` is called
  with a stale drawable, GPU validation fires.

- **DebugOverlayView dedup over-deletion.** The `Tempo` row is
  inside the "MOOD (LIVE)" section but is the only row coming from
  `engine.estimatedTempo`. Delete only the `if let bpm = …` block,
  not the whole MOOD section. Mood V/A and Key stay.

- **`D` toggling under audio-driven render-tick.** `engine.dashboardEnabled`
  flips on `@MainActor`. The composer reads `enabled` on the render
  thread inside `composite(...)`. Use the existing
  `dashboardComposerLock` pattern OR ensure the `enabled` property
  itself is `nonisolated(unsafe)` (the existing pattern for cross-
  actor flags in `VisualizerEngine`). Whichever you choose, cover
  with test (d).

- **STOP and report instead of forging ahead** if:
  - Any DASH.1 / DASH.2 / DASH.3 / DASH.4 / DASH.5 test breaks (39
    must remain green). DASH.6 must not regress prior increments.
  - SwiftLint introduces violations on touched files.
  - Frame-budget delta exceeds 0.5 ms p95 (STOP — diagnose; do not
    ship a regression to land the toggle).
  - The chosen draw-path call site requires a render-loop refactor
    (Decision A scope blow-up) — fall back to Decision B and
    document.
  - Live D-toggle eyeball shows a card visibly broken (text
    unreadable, chrome misplaced, cards stacked outside the drawable,
    composite pixels misaligned by ≥1 pt). That's a DASH.6 bug, not
    a DASH.6.1 amendment — fix before committing.

────────────────────────────────────────
REFERENCES
────────────────────────────────────────

- DASH.5 builder + snapshot (most recent canonical pattern):
  `PhospheneEngine/Sources/Renderer/Dashboard/PerfCardBuilder.swift`
  `PhospheneEngine/Sources/Renderer/Dashboard/PerfSnapshot.swift`
- DASH.4 + DASH.3 builders:
  `PhospheneEngine/Sources/Renderer/Dashboard/StemsCardBuilder.swift`
  `PhospheneEngine/Sources/Renderer/Dashboard/BeatCardBuilder.swift`
- DASH.2 layout + renderer:
  `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift`
  `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer.swift`
  `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer+ProgressBar.swift`
- DASH.1 text layer + tokens:
  `PhospheneEngine/Sources/Renderer/Dashboard/DashboardTextLayer.swift`
  `PhospheneEngine/Sources/Renderer/Dashboard/DashboardFontLoader.swift`
  `PhospheneEngine/Sources/Shared/Dashboard/DashboardTokens.swift`
- Existing layer + render-thread CPU-write pattern (the canonical
  precedent for this increment):
  `DynamicTextOverlay` + `RenderPipeline.textOverlayCallback` —
  see `RenderPipeline+Draw.swift:297-315` and the `DynamicTextOverlay`
  class.
- Render pipeline + draw paths:
  `PhospheneEngine/Sources/Renderer/RenderPipeline.swift`
  `PhospheneEngine/Sources/Renderer/RenderPipeline+Draw.swift`
- Visualizer engine + per-frame snapshot ownership:
  `PhospheneApp/VisualizerEngine.swift`
  `PhospheneApp/VisualizerEngine+InitHelpers.swift`
- D-key shortcut + showDebug binding:
  `PhospheneApp/Services/PlaybackShortcutRegistry.swift:317`
  `PhospheneApp/Views/Playback/PlaybackView.swift:46, :286`
- SwiftUI debug overlay (deduplication target):
  `PhospheneApp/Views/DebugOverlayView.swift`
- FrameBudgetManager (PERF FRAME row source):
  `PhospheneEngine/Sources/Renderer/FrameBudgetManager.swift`
- MLDispatchScheduler (PERF ML row source):
  `PhospheneEngine/Sources/Renderer/MLDispatchScheduler.swift`
- BeatSyncSnapshot (BEAT card source) + lock:
  `PhospheneEngine/Sources/Shared/BeatSyncSnapshot.swift`
  `PhospheneApp/VisualizerEngine.swift` (`latestBeatSyncSnapshot`,
  `beatSyncLock`)
- Soak harness (frame-budget regression check):
  `PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/SoakTestHarnessTests.swift`
- D-082, D-082.1, D-083, D-084, D-085: dashboard layout engine +
  .impeccable redesign + BEAT + STEMS + PERF card bindings
- CLAUDE.md: Increment Completion Protocol, Visual Quality Floor,
  What NOT To Do, FrameBudgetManager / MLDispatchScheduler entries
  in the Module Map
- Design context: `.impeccable.md` (Color section, State-Specific
  Design Notes, Anti-Patterns)
