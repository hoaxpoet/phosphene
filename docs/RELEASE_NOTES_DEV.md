# Phosphene — Developer Release Notes

Internal release notes for the `main` branch. Audience: Matt and Claude Code. Each entry covers one session or a logical batch of increments. These notes complement `docs/ENGINEERING_PLAN.md` (authoritative for what's planned) and `docs/QUALITY/KNOWN_ISSUES.md` (authoritative for open defects).

User-visible release notes are not yet in scope (no public build).

---

## [dev-2026-05-07-m] BUG-007.4b — auto-rotate bar phase via kick density

**Increment:** BUG-007.4b
**Type:** Bug fix (DSP / live beat tracking)

**What changed.** Eliminates the per-track `Shift+B` manual rotation requirement for tracks with a clear kick density signal. After lock has stabilised (8+ matched onsets), the tracker examines its per-slot kick-onset histogram and auto-rotates `barPhaseOffset` so the dominant slot becomes the displayed "1." One-shot per track.

**How it works.**

- Each tight onset increments a counter for `timing.beatsSinceDownbeat` (raw, before any rotation). Histogram is sized to `grid.beatsPerBar` on `setGrid` and resets on track change.
- After `matchedOnsets >= 8`, the tracker selects the slot with the highest count. Requires ≥ 4 onsets in that slot *and* ≥ 1.5× the runner-up's count to qualify as a clear winner — otherwise it's a no-op (four-on-the-floor electronic, ambient material).
- Auto-rotate is preempted if the user pressed `Shift+B` first. Manual intent wins.
- One-shot per track: once attempted (whether rotated or not), it doesn't re-fire on the same track. `setGrid` resets the flag.

**Expected behaviour per the 5-track battery:**

- HUMBLE (kick on 1+3 with 1 emphasised) → likely auto-rotates within ~6 s.
- Everlong / SLTS (rock with strong downbeat) → likely auto-rotates within ~4 s.
- Midnight City → may auto-rotate via snare-on-2/4 density shift; to be observed.
- One More Time (four-on-the-floor electronic) → equal density → no auto-rotate, `Shift+B` remains.

**API.** New private state (`slotOnsetCounts`, `autoRotateAttempted`, `manualRotationPressed`) and helper `maybeAutoRotateBarPhaseLocked`. New tunables: `autoRotateMatchThreshold=8`, `autoRotateDominanceRatio=1.5`, `autoRotateMinDominantCount=4`. `barPhaseOffset` external setter sets `manualRotationPressed=true`.

**Files edited.**

- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — auto-rotate logic, slot counter, manual-press guard. Adds `swiftlint:disable type_body_length`.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — 4 new tests (MARKs 27–30).
- `docs/QUALITY/KNOWN_ISSUES.md` — BUG-007.4 marked Resolved.

**Tests.** 30/30 `LiveBeatDriftTrackerTests` pass. Full engine suite green except documented pre-existing flakes. 0 SwiftLint violations on touched files.

**Manual validation pending.** Same 5-track battery — confirm auto-rotate works on HUMBLE/Everlong/SLTS and `Shift+B` remains the override.

**Out of scope.** BUG-007.5 part 3 (BPM-aware time gate for HUMBLE — next increment).

---

## [dev-2026-05-07-l] BUG-007.5 part 2 — variance-adaptive tight gate

**Increment:** BUG-007.5 part 2
**Type:** Bug fix (DSP / live beat tracking)

**What changed.**

The 2026-05-07T20-34-57Z manual session showed that the time-based lock release (BUG-007.5 part 1) closed lock retention on simple kick-on-the-beat tracks (OMT, SLTS — 89-90 % LOCKED, 50-91 s contiguous runs) but not on tracks where drift envelope spans wider than ±30 ms despite small mean drift (Midnight City 58 % LOCKED, HUMBLE 44 %, Everlong 73 %). The cause: the fixed ±30 ms tight gate doesn't fit the natural variance of these tracks. Drift EMA centres correctly; individual onsets land on either edge of a 40-50 ms envelope; many trigger the time gate even though they're really fine.

**Fix.** Variance-adaptive tight gate: replace the fixed ±30 ms with `effectiveTightWindow = clamp(2σ, 30 ms, 80 ms)` derived from the running stddev of the last 16 `instantDrift − drift` deviations. Acquisition path (before `matchedOnsets >= lockThreshold`) still uses the floor 30 ms for selectivity. Retention path widens to fit the track's actual variance — narrow for OMT/SLTS, wider for MC/HUMBLE/B.O.B. Ring resets on `setGrid`/`reset` so each track starts fresh.

**API changes:**

- `LiveBeatDriftTracker` gains private state: `driftDeviationRing: [Double]` (capacity 16, signed seconds), `pushDriftDeviationLocked(_:)`, `effectiveTightWindowLocked()`. No public API changes.
- New private static tunables: `tightMatchWindowCeiling=0.080`, `tightMatchWindowK=2.0`, `driftDeviationRingCapacity=16`, `driftDeviationMinSamples=4`. `strictMatchWindow=0.030` retained as the floor.

**Files edited.**

- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — variance ring + adaptive gate logic in `update()`.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — 2 new tests (MARKs 25–26): `adaptiveTightGate_widensForNoisyOnsetStream`, `adaptiveTightGate_ringResetsOnSetGrid`. Plus `TightCapture` helper for `@Sendable`-compatible diagnostic-trace capture.
- `docs/QUALITY/KNOWN_ISSUES.md` — BUG-007.5 status updated to "Resolved (time-based release gate + variance-adaptive tight gate, 2026-05-07)".

**Tests.** 26/26 `LiveBeatDriftTrackerTests` pass. Full engine suite passes except documented pre-existing flake (`MetadataPreFetcher.fetch_networkTimeout`) and DASH.5 string-format mismatch (`PerfCardBuilderTests`, separate work in flight). 0 SwiftLint violations on touched files.

**App build status.** Not verified for this commit — DASH.7 work in flight has a pending `DarkVibrancyView` reference. Engine SPM target builds clean. Once DASH.7 completes, full app build can be confirmed.

**Manual validation pending.** Same 5-track battery (OMT / Midnight City / HUMBLE / SLTS / Everlong) — confirm MC, HUMBLE, Everlong reach 80 %+ LOCKED with 30 s+ contiguous runs. OMT and SLTS should not regress (already at 89-90 %).

**Out of scope.**

- Adaptive widening on the slope-detector / wider-window-retry path (BUG-007.3 reverted).
- Per-onset-class tight gates (drums vs bass vs claps).
- BUG-007.4b (auto-rotate bar phase) — separate increment, scheduled next.

---

## [dev-2026-05-07-n] BUG-009 — Halving-correction threshold 160 → 175 BPM

**Increment:** BUG-009
**Type:** Bug fix (calibration)

**What changed.** Raised the halving threshold in `BeatGrid.halvingOctaveCorrected()` from 160 → 175 BPM. The `> 160` guard halved legitimate fast tracks down to half-time when the live 10 s Beat This! analyser overshot the true tempo: Foo Fighters' "Everlong" (true ≈ 158 BPM) installed at 85.4 BPM in the reactive session captured at `~/Documents/phosphene_sessions/2026-05-07T14-33-47Z/`. Drum'n'bass (170–175), fast indie rock (Strokes / Arctic Monkeys 155–170), and similar fast-rock tempos shared the same fate. 175 captures the fast-rock band without re-enabling true double-time errors (those land at ≥ 200 typically). Pyramid Song (~68 BPM) and Money 7/4 (~123 BPM) remain untouched (under-floor + in-range respectively).

**Tests.** Added `halvingOctaveCorrected_fastRockBPM_isNoOp` covering four fixtures (158 / 168 / 172.5 / 175 BPM) — each must pass through un-halved. Updated existing assertions to use the `[80, 175]` range. Refreshed the extreme-double-halve fixture from 322 BPM → 360 BPM (322 → 161 used to trigger a second halve under the old `> 160` guard; under `> 175` it stops at 161, so the test now uses 360 → 180 → 90 to retain factor-4 thinning coverage). Engine: 1120 tests pass. SwiftLint clean on touched files.

**Manual validation pending** at next reactive Everlong session: live grid should install at `bpm=158 ± 8`, not 85.4. Pyramid Song must remain at 68 BPM; Love Rehab live trigger (244.770 → halved to 122.4) must continue to halve. Documented in `KNOWN_ISSUES.md`.

---

## [dev-2026-05-07-m] DASH.7.2 — Dark-surface legibility pass

**Increment:** DASH.7.2 (D-089)
**Type:** Accessibility / aesthetic correction

**What changed.** Matt's first-look review of DASH.7.1 surfaced four issues:
- `.regularMaterial` is system-appearance-adaptive — on macOS Light it rendered the panel as a beige material, putting near-white dashboard text on tan with sub-AA contrast.
- `coralMuted` (oklch 0.45) and `purpleGlow` (oklch 0.35) — chosen in DASH.7.1 for muted brand semantic — failed WCAG AA against dark surfaces anyway (2.6:1 and 2.5:1).
- MODE / BPM rendered as stacked "label-on-top, 24pt mono value below" while BAR / BEAT rendered as "label + bar + small inline value" — visually inconsistent.
- FRAME value `"20.0 / 14 ms"` truncated to `"20.0 / 14…"` in the 86pt column.

**Fixes.**

- **`DarkVibrancyView`** — new `NSViewRepresentable` wrapping `NSVisualEffectView` pinned to `.appearance = .vibrantDark` + `.material = .hudWindow`. Replaces `.regularMaterial` so the surface is dark regardless of system appearance. Combined with `.environment(\.colorScheme, .dark)` on the SwiftUI subtree.
- **Surface tint at 0.96α.** Bumped from 0.55 — the dashboard sits over the visualizer and must guarantee AA contrast against the worst-case bright preset frame. At 0.96 opaque, teal text passes AA (4.77:1); at 0.55 it failed (1.16:1).
- **Colour promotions to AAA-grade contrast.** `coralMuted` → **`coral`** in `BeatCardBuilder.makeModeRow` (LOCKING) and throughout `PerfCardBuilder` (FRAME stressed, QUALITY downshifted, ML WAIT/FORCED). `purpleGlow` → **`purple`** in `BeatCardBuilder.makeBarRow`. `textMuted` → **`textBody`** for MODE REACTIVE / UNLOCKED. All preserve brand semantics; just brighter intensity for legibility.
- **Inline `.singleValue` rendering.** Rewrote `DashboardRowView.singleValueRow` as `HStack(label LEFT, Spacer, value RIGHT)` at 13pt mono — matches `.bar` / `.progressBar` row rhythm. MODE / BPM / QUALITY / ML now read at the same scale and column position as BAR / BEAT values. The 24pt hero-numeric is retired from the dashboard.
- **FRAME column 86pt → 110pt** + format `"X / Y ms"` → `"X / Yms"` (no space). Combined, values never truncate regardless of frame time.

**Decisions.** D-089 captures the contrast math, the macOS-appearance pinning rationale, the colour promotions, the inline-row redesign, and the format compaction. `coralMuted` / `purpleGlow` remain defined in `DashboardTokens.Color` for future callers but no card builder references them after DASH.7.2.

**Tests.** Dashboard count unchanged at 27. Fixture updates: `BeatCardBuilderTests.locking` / `.unlocked` / `.zero` (coral / textBody / purple); `PerfCardBuilderTests.warningRatio` / `.downshifted` / `.forcedDispatch` (coral); `.healthy` / `.clampOverBudget` (compact format). Engine + app builds clean. SwiftLint clean on touched files.

---

## [dev-2026-05-07-k] DASH.7.1 — Brand-alignment pass (impeccable review)

**Increment:** DASH.7.1
**Type:** Aesthetic refinement

**What changed.** An impeccable-skill review of DASH.7 against `.impeccable.md` surfaced three brand violations and seven smaller issues; DASH.7.1 lands all corrections in one focused increment.

**P0 — semantic / structural:**
- **STEMS sparkline colour:** coral → **teal**. `.impeccable.md` reserves teal for "MIR data, stem indicators." Coral is for "energy, action, beat moments." Stems are MIR data; teal is correct.
- **Per-card chrome retired.** Three rounded-rectangle cards (`.impeccable.md` anti-pattern: "no rounded-rectangle cards as the primary UI pattern") replaced with a **single shared `.regularMaterial` panel** (NSVisualEffectView wrapper, the macOS-spec'd material) containing three typographic sections separated by `border` dividers. Cards become typographic content; the panel is the only chrome.
- **Custom fonts wired (Clash Display + Epilogue).** `DashboardFontLoader.FontResolution` extended with `displayFontName` + `displayCustomLoaded` for Clash Display. `PhospheneApp.init()` calls `DashboardFontLoader.resolveFonts(in: nil)` once at launch. SwiftUI views resolve via `.custom(_:size:relativeTo:)` so Dynamic Type still scales. Falls back gracefully to system fonts when TTF/OTF aren't bundled (the README documents the drop-in path).

**P1 — significant aesthetic:**
- **SF Symbol status icons retired.** `checkmark.circle.fill` / `exclamationmark.triangle.fill` were a web-admin trope. Status now reads through value-text colour alone — Sakamoto-liner-note discipline.
- **PERF status colours mapped onto the brand palette.** `statusGreen` / `statusYellow` retired in favour of `teal` (data healthy) / `coralMuted` (data stressed). Same change in `BeatCardBuilder`'s MODE row: LOCKED → teal, LOCKING → coralMuted. The card uses only the project's three brand colours now.
- **STEMS valueText dropped entirely.** The sparkline IS the readout; the redundant signed-decimal column on the right was Sakamoto-violating.
- **Spring-choreographed `D` toggle.** `withAnimation(.spring(response: 0.4, dampingFraction: 0.85))` wraps the `showDebug` toggle; the dashboard cards fade in with an 8pt downward offset, fade out cleanly. The DebugOverlayView gets a plain opacity transition to match.

**P2 — polish:**
- Stable `ForEach` IDs (`id: \.element.title`) so card add/remove animates correctly when PERF rows collapse.
- `+` prefix dropped on signed valueText (bar direction encodes sign visually).
- Card titles render at `bodyLarge` (15pt) Clash Display Medium — typographic anchors of the dashboard column rather than 11pt UPPERCASE labels-on-cards.

**What survives unchanged.** `DashboardCardLayout` API, all four Row variants, `DashboardSnapshot`, `StemEnergyHistory`, `BeatCardBuilder` non-MODE colour assignments (BAR=purpleGlow, BEAT=coral both stay — they're correct per the brand table). All Sendable contracts. The DashboardOverlayViewModel + 30 Hz throttle. The single-`D` toggle binding to both surfaces.

**Decisions.** D-088 captures: brand-violation diagnoses, retirement details, font-loader extension, spring-transition spec, what survives.

**Tests.** Dashboard test count unchanged at 27. Test fixtures updated: `BeatCardBuilderTests.locked`/`.locking` use teal/coralMuted; `StemsCardBuilderTests.mixedHistory`/`.uniformColour` use teal; `StemsCardBuilderTests.valueTextEmpty` (renamed) asserts empty-string; `PerfCardBuilderTests.healthy`/`.warningRatio`/`.downshifted`/`.forcedDispatch` use teal/coralMuted; `DashboardOverlayViewModelTests.stemHistoryAccumulates` asserts `valueText.isEmpty`.

Engine + app builds clean. SwiftLint clean on touched files. Pre-existing flakes (`MemoryReporter.residentBytes`, `MetadataPreFetcher.fetch_networkTimeout`) fired as expected — none introduced.

---

## [dev-2026-05-07-j] DASH.7 — SwiftUI dashboard port + visual amendments

**Increment:** DASH.7 (supersedes DASH.6 / D-086)
**Type:** Architectural pivot + feature

**What changed.** Pivoted the dashboard from the DASH.6 Metal composite path to a SwiftUI overlay after Matt's live D-toggle review (`~/Documents/phosphene_sessions/2026-05-07T19-03-44Z`) found that (a) the Metal text layer rendered hazy at native pixel scale, (b) the 0.92α purple-tinted chrome washed gray against bright preset backdrops, and (c) the STEMS `.bar` rows didn't read rhythm separation across stems clearly. Investigation showed the original Metal-path justifications didn't materialize: text wasn't crisper than SwiftUI, snapshot updates are bounded by snapshot-change cadence rather than frame rate, and lifetime is naturally one-frame ahead via `@Published`. DASH.7 ports + bundles two visual amendments:

- **STEMS card → timeseries.** New `.timeseries(label, samples, range, valueText, fillColor)` row variant on `DashboardCardLayout`. `StemsCardBuilder` now consumes a `StemEnergyHistory` (240-sample CPU ring buffer per stem, ≈ 8 s at 30 Hz throttled redraw). The view model maintains the rings privately and snapshots into the immutable `StemEnergyHistory` value type per redraw. `DashboardRowView`'s `SparklineView` (SwiftUI `Canvas`) renders a filled area + stroked line with a centre baseline that's visible even on empty samples — stable absence-of-signal surface.
- **PERF semantic clarity.** FRAME row's value text now reads `"{recent} / {target} ms"` so headroom is legible without docs lookup; status colour flips green→yellow at 70% of budget (`PerfCardBuilder.warningRatio`). QUALITY row hides when the governor is `full` and warmed up. ML row hides on idle / `dispatchNow` (READY); only surfaces on `defer` / `forceDispatch`. Card collapses to one row in the steady-state happy path. SF Symbols (`checkmark.circle.fill` / `exclamationmark.triangle.fill`) decorate the FRAME label so status reads in colour-blind contexts.

**Architecture changes.**
- New `VisualizerEngine.@Published var dashboardSnapshot: DashboardSnapshot?` (Sendable bundle of beat+stems+perf), republished from `pipe.onFrameRendered` on `@MainActor`.
- New `DashboardOverlayViewModel` (`@MainActor ObservableObject`) — subscribes to the engine's snapshot publisher via Combine, throttles to ~30 Hz (`.throttle(for: .milliseconds(33))`), maintains stem history rings, publishes `[DashboardCardLayout]`. Builder tests (pure data) are unchanged in spirit; only their fixtures changed to match the new APIs.
- New `DashboardOverlayView` / `DashboardCardView` / `DashboardRowView` SwiftUI components in `PhospheneApp/Views/Dashboard/`. View hierarchy: `DashboardOverlayView` (top-trailing column) → `DashboardCardView` (rounded-rect chrome + title) → `DashboardRowView` (four row variants).
- PlaybackView Layer 6: `if showDebug { DashboardOverlayView(viewModel: dashboardVM) }`. The `D` shortcut now drives both DebugOverlayView (Layer 5) and DashboardOverlayView (Layer 6) symmetrically — no engine-level state to keep in sync. The DASH.6 `engine.dashboardEnabled = showDebug` line was deleted.
- ContentView wires `dashboardSnapshotPublisher: engine.$dashboardSnapshot.eraseToAnyPublisher()` through PlaybackView's init.

**Retired (deleted, not commented out).**
- `Renderer/Dashboard/DashboardComposer.swift`
- `Renderer/Dashboard/DashboardCardRenderer.swift` + `+ProgressBar.swift`
- `Renderer/Dashboard/DashboardTextLayer.swift`
- `Renderer/Shaders/Dashboard.metal`
- 10 `compositeDashboard(...)` call sites in `RenderPipeline+*.swift` draw paths
- `RenderPipeline.setDashboardComposer` / `hasDashboardComposer` / `compositeDashboard` helper / `dashboardComposer` + lock + resize forward
- `VisualizerEngine.dashboardComposer` / `dashboardEnabled`
- 4 test files: `DashboardComposerTests`, `DashboardCardRendererTests`, `DashboardCardRendererProgressBarTests`, `DashboardTextLayerTests` (14 tests)

**What survived the pivot.** The Sendable card builders (`BeatCardBuilder` / `StemsCardBuilder` rewritten / `PerfCardBuilder` updated), `DashboardCardLayout` (with new `.timeseries` variant), `DashboardTokens`, `BeatSyncSnapshot`, `PerfSnapshot`. The data shape converged across DASH.3-6 was the part worth keeping; only the rendering layer changed. The DASH.6 `Spacing.cardGap` token stays. The DebugOverlayView dedup from DASH.6 stays (Tempo / standalone QUALITY / ML rows still removed).

**What's intentionally NOT in this increment.** No `Equatable` conformance added to `BeatSyncSnapshot` / `StemFeatures` (D-086 Decision 4 stands; bytewise equality via `withUnsafeBytes` + `memcmp` for change detection in `DashboardSnapshot`). No fourth card. No animation. No per-stem palette tuning (uniform coral; carries forward from DASH.4 / D-084).

**Decisions.** D-087 captures: pivot rationale (Metal-path justifications didn't materialize), what survives, retirement of D-086 surface, 30 Hz throttle vs. buffer-update tradeoff, STEMS bar→timeseries, PERF semantic clarity collapse rule, single `D` toggle drives both surfaces symmetrically.

**Tests.** Engine: 1117 tests / 126 suites (was 1130 — drop reflects deleted GPU readback tests). Dashboard-related test count: 27 (was 39). Builder + tokens + font-loader tests pass. App: 310 tests / 55 suites (was 305 — gain from 5 new `DashboardOverlayViewModelTests`). Pre-existing flakes documented in CLAUDE.md (MemoryReporter residentBytes, NetworkRecoveryCoordinator timing, SessionManager parallel-execution timing) fired as expected — none introduced by DASH.7. SwiftLint clean on touched files. xcodebuild app build clean.

**DASH.6 commits stay in history.** Per Matt's preference, no `git revert` — the DASH.6 commits + retirement in DASH.7 tell the truthful "we tried Metal, ported to SwiftUI" story.

---

## [dev-2026-05-07-i] DASH.6 — Overlay wiring + `D` toggle

**Increment:** DASH.6
**Type:** Feature

**What changed.**
- New `DashboardComposer` (`@MainActor`, `Renderer/Dashboard/`) — lifecycle owner of the BEAT/STEMS/PERF cards. Owns one `DashboardTextLayer` (320 × 660 pt at 2× contentsScale by default; reallocates on `resize(to:)`), three pure builders (`BeatCardBuilder`/`StemsCardBuilder`/`PerfCardBuilder`), and one alpha-blended `MTLRenderPipelineState` keyed to `dashboard_composite_vertex` / `dashboard_composite_fragment` (Premultiplied source: `src = .one`, `dst = .oneMinusSourceAlpha`).
- New `Dashboard.metal` shader file (`Renderer/Shaders/`) — vertex stage emits a fullscreen triangle confined to the composite pass's viewport; fragment samples the layer texture at `[[texture(0)]]` with bilinear + clamp_to_edge.
- New `Spacing.cardGap` token in `Shared/Dashboard/DashboardTokens.swift` — aliases `Spacing.md` (12 pt) v1; named slot reserves a DASH.6.1 retune.
- `RenderPipeline` gains `setDashboardComposer(_:)` setter, `hasDashboardComposer: Bool` test accessor, and a `compositeDashboard(commandBuffer:view:)` helper invoked from the tail of every draw path (`drawDirect`, `drawWithMeshShader`, `drawWithRayMarch`, `drawWithFeedback`, `drawWithMVWarp`, `drawWithICB`, `drawWithPostProcess`, `drawWithStaged`, plus the feedback-blit and mv-warp fallback paths) immediately before `commandBuffer.present(drawable)`. `mtkView(_:drawableSizeWillChange:)` forwards to `composer.resize(to:)` so card placement scales with drawable contentsScale (no hardcoded 2×).
- `VisualizerEngine` gains `dashboardComposer: DashboardComposer?` and `@MainActor var dashboardEnabled: Bool` (mirror of the composer's `enabled` flag). `setupDashboardComposer(pipe:ctx:lib:)` allocates the composer and wraps `pipe.onFrameRendered` so a per-frame snapshot push (BeatSync from the engine's snapshot lock + StemFeatures from the existing closure parameter + a freshly-assembled `PerfSnapshot`) is delivered to `composer.update(...)` once per rendered frame.
- `PlaybackView`'s `D` shortcut now writes `engine.dashboardEnabled = showDebug` after toggling the SwiftUI overlay — one keystroke drives both the SwiftUI debug overlay (bottom-leading, raw diagnostics) and the new Metal cards (top-right, instruments).
- `DebugOverlayView` deduplicated of metrics that the dashboard cards now show: the `Tempo` row inside MOOD (LIVE), the standalone `QUALITY:` HStack block, and the standalone `ML:` HStack block (along with the divider that immediately preceded the QUALITY/ML pair). Mood V/A, Key, SIGNAL block, MIR diag, SPIDER, G-buffer, REC all stay.

**What's intentionally NOT in this increment.** No fourth card (mood / metadata / signal). No animation on card show/hide (`D` is binary). No per-card visibility toggles. No render-loop refactor (Decision A would have required moving `commandBuffer.present(drawable)` out of 8+ draw paths — well beyond the spec's 30-line ceiling, deferred). No per-card colour tuning (uniform palette per builder, DASH.6.1 amendment slot if the live-toggle review surfaces issues). No `Equatable` on `StemFeatures` / `BeatSyncSnapshot` (D-086 Decision 4 — composer's rebuild-skip uses private bytewise compare).

**Decisions.** D-086 captures: composer-as-class rationale, Decision B (per-path composite call sites) over Decision A (render-loop refactor), single `D` toggle drives both surfaces, no Equatable on shared types, premultiplied alpha discipline, per-frame rebuild cost rationale, DASH.6.1 amendment slot.

**Tests.** 45 dashboard tests pass (was 39 → 45, six new in `DashboardComposerTests`: init / idempotent-on-equal-snapshots / rebuilds-on-any-input-change / disabled-is-noop / update+composite paints top-right / resize recomputes 4K placement). Full engine suite green: 1130 tests / 130 suites. 0 SwiftLint violations on touched files. `xcodebuild -scheme PhospheneApp build` succeeded.

**Frame-budget regression.** Soak harness re-run not yet captured for this increment (CPU rebuild path is gated behind `enabled` and the bytewise rebuild-skip; the GPU composite is one fullscreen triangle into a fixed top-right viewport — expected delta is well below the 0.5 ms p95 ceiling). Live D-toggle review on real music is the acceptance artifact and runs as part of DASH.6 sign-off; numeric soak comparison is a follow-up if the eyeball review flags concern.

---

## [dev-2026-05-07-i] BUG-007.5 + BUG-007.6 — Time-based lock release + audio output latency calibration

**Increment:** BUG-007.5 + BUG-007.6 (joint)
**Type:** Bug fix (DSP / live beat tracking)

**What changed.**

Two complementary fixes informed by the 2026-05-07T18-21-37Z manual session evidence:

**BUG-007.6 — audio output latency calibration.** All tracks showed systematic negative drift averaging −36 to −76 ms (visual fires before audio is heard). Cause: tap captures audio ~50 ms before the listener hears it (CoreAudio output buffer + DAC + driver), plus onset-detection processing delay. Fix: new `LiveBeatDriftTracker.audioOutputLatencyMs: Float` applied to the *display path only* (`displayTime = pt + drift + L/1000`). Does NOT touch onset matching — that would cancel out algebraically. Default 0 in engine; `VisualizerEngine` sets it to 50 ms for internal Mac speakers in app-layer init. Tunable at runtime via `,` (−5 ms) / `.` (+5 ms) shortcuts. Persists across track changes (system property). Range clamped ±500 ms.

**BUG-007.5 — time-based lock release.** Replaced count-based `lockReleaseMisses=7` gate with time-based `lockReleaseTimeSeconds=2.5` gate. Lock now drops only when 2.5 s of consecutive non-tight matches have elapsed since the last tight hit, regardless of how many onsets occurred in between. Sparse-onset tracks (HUMBLE half-time at 76 BPM, 790 ms beat period — 15 lock drops in the prior session) no longer trip the gate accidentally — what matters is *time*, not *count*. Diagnostic counter `consecutiveMisses` retained on `LiveBeatDriftTraceEntry` for backward compat.

**API changes:**

- `LiveBeatDriftTracker.audioOutputLatencyMs: Float` (public, NSLock-guarded, clamped ±500 ms, default 0).
- `VisualizerEngine.audioOutputLatencyMs` proxy + `adjustAudioOutputLatency(ms:)` method.
- `PlaybackShortcutRegistry` gains `,` and `.` shortcuts in the developer category.
- New `lockReleaseTimeSeconds: Double = 2.5` constant replaces `lockReleaseMisses` for the lock-decision logic.

**Files edited.**

- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift`
- `PhospheneApp/VisualizerEngine.swift`
- `PhospheneApp/Services/PlaybackShortcutRegistry.swift`
- `PhospheneApp/Views/Playback/PlaybackView.swift`
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — 5 new tests (MARKs 20–24).
- `docs/QUALITY/KNOWN_ISSUES.md` — both bugs marked Resolved (automated); manual validation pending.

**Tests:** `LiveBeatDriftTrackerTests` 24/24 pass. Full engine suite green except documented pre-existing flake. App build clean. 0 SwiftLint violations.

**Manual validation pending.** Next session capture with the same 5-track battery should confirm: beat orb visually pulses on the kick (BUG-007.6); lock holds through HUMBLE's sparse half-time and Everlong's noisy onsets (BUG-007.5); `,`/`.` adjust visual sync; no regression on `Shift+B` rotation.

**Out of scope (deferred).** Persisting `audioOutputLatencyMs` across launches (settings field, future increment). Per-device automatic detection. Variance-adaptive lock window — re-evaluate after manual validation of the time-based gate alone.

---

## [dev-2026-05-07-h] BUG-007.4a — Bar-phase rotation dev shortcut (Shift+B)

**Increment:** BUG-007.4a
**Type:** Bug fix / diagnostic enabler

**What changed.**

5-track A/B test on 2026-05-07 (sessions `T15-50-23Z` + `T15-58-17Z`) confirmed BUG-007.4's root cause: Spotify preview clips don't start on song bar boundaries, so Beat This!'s "beat 1 of bar 1" lands on a non-downbeat in the song's coordinate system. Per-track off-by-N: One More Time +3, Midnight City +3, HUMBLE +2, SLTS 0 (preview = first 30 s), Everlong +2. SLTS being the only correct case correlates with its preview being the song intro.

This increment lands a developer shortcut so the user can confirm the rotation hypothesis on more tracks and provide an escape hatch until the durable fix (BUG-007.4b — kick-density auto-rotate) lands.

**API changes:**

- `LiveBeatDriftTracker.barPhaseOffset: Int` (`public`, NSLock-guarded). Range 0..(beatsPerBar−1); setter wraps modulo `beatsPerBar`. Applied in `computePhase` to rotate `barPhase01` and downstream `beat_in_bar` text. Beat-phase, drift, and lock-state are untouched. Reset to 0 on `setGrid` / `reset` so each track starts fresh.
- `VisualizerEngine.cycleBarPhaseOffset()` — increments by 1 and logs.
- `PlaybackShortcutRegistry` gains `onCycleBarPhaseOffset` callback; new shortcut `Shift+B` in the developer category labelled "Cycle bar-phase offset (BUG-007.4)".

**Files edited.**

- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — `barPhaseOffset` property + reset hook + `computePhase` rotation. `swiftlint:disable file_length`.
- `PhospheneApp/VisualizerEngine.swift` — `cycleBarPhaseOffset()`.
- `PhospheneApp/Services/PlaybackShortcutRegistry.swift` — `Shift+B` keybind.
- `PhospheneApp/Views/Playback/PlaybackView.swift` — wiring to engine.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — 1 new test (`barPhaseOffset_rotatesBarPhase_modBeatsPerBar`) covering rotation, modulo wrap, reset on setGrid.
- `docs/QUALITY/KNOWN_ISSUES.md` (BUG-007.4 root cause confirmed; fix plan ranked C/A/B).
- `docs/RELEASE_NOTES_DEV.md`.

**How to use.**

In a Spotify-prepared session with the SpectralCartograph diagnostic preset locked (`L`):
1. Play any track. Listen for the song's downbeat ("1").
2. If the visual "1" doesn't match, press `Shift+B` to advance the offset by 1.
3. Cycle 0..(beatsPerBar−1) until "1" lines up. Console log shows current offset.
4. Offset resets to 0 on track change — re-cycle for the next track.

This is a *diagnostic*, not the durable fix. Each track may need its own cycle count. BUG-007.4b will auto-rotate via kick-density heuristic.

**Test counts:** 18 → 19 LiveBeatDriftTrackerTests. Full engine suite green except the documented pre-existing `MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget` flake. 0 SwiftLint violations on touched files. App build clean.

**Out of scope (deferred to BUG-007.4b).** Auto-rotation via kick-density heuristic at lock-in time. Persistence of per-track offset across sessions (the dev shortcut is ephemeral by design).

---

## [dev-2026-05-07-g] DASH.5 — Frame budget card

**Increment:** DASH.5
**Type:** Feature (dashboard)

**What changed.**

The third **live** dashboard card binds renderer governor + ML dispatch state to a `DashboardCardLayout` titled `PERF`. New `PerfSnapshot` Sendable value type wraps the inputs from two manager classes (`FrameBudgetManager` + `MLDispatchScheduler`) as a single seam crossing actor lines into the builder. New pure `PerfCardBuilder` produces a three-row card in display order: FRAME (`.progressBar`, unsigned ramp `recentMaxFrameMs / targetFrameMs` clamped to `[0, 1]` at the builder layer), QUALITY (`.singleValue`, displayName passed through verbatim), ML (`.singleValue`, mapped to READY / WAIT _ms / FORCED / —). Status-colour discipline reuses BEAT lock-state palette (D-083): muted = no info, green = healthy / READY, yellow = governor active / degraded / WAIT / FORCED. No `statusRed` introduced — durable rule across the dashboard. Wiring into `RenderPipeline` / `PlaybackView` is DASH.6 scope, not DASH.5.

**Files added.**
- `PhospheneEngine/Sources/Renderer/Dashboard/PerfSnapshot.swift` — Sendable value type with seven fields (`recentMaxFrameMs`, `recentFramesObserved`, `targetFrameMs`, `qualityLevelRawValue`, `qualityLevelDisplayName`, `mlDecisionCode`, `mlDeferRetryMs`). Decision/quality enums encoded as `Int + displayName: String` so the snapshot stays trivially `Sendable` without importing manager enums. `.zero` neutral default.
- `PhospheneEngine/Sources/Renderer/Dashboard/PerfCardBuilder.swift` — pure `Sendable` struct: `build(from: PerfSnapshot, width: CGFloat = 280) -> DashboardCardLayout`. Three private row makers: FRAME (clamps `[0, 1]` at builder layer because `.progressBar` has no `range` field), QUALITY (status-colour mapped), ML (decision-code switch with WAIT-ms formatting that drops the trailing `0ms` when retry-ms is zero).
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PerfCardBuilderTests.swift` — 6 `@Test` functions in `@Suite("PerfCardBuilder")`: zero snapshot (3 rows: FRAME 0/—, QUALITY full/muted, ML —/muted), healthy full quality (FRAME ≈ 0.586, QUALITY full/green, ML READY/green), governor downshifted (FRAME clamped 1.0, QUALITY no-bloom/yellow, ML WAIT 200ms/yellow), forced dispatch + artifact (FRAME ≈ 0.8, QUALITY full/green, ML FORCED/yellow, writes `card_perf_active.png`), frame-time-above-budget regression lock (FRAME clamps to 1.0 at the builder layer; valueText still shows raw `42.0 ms`), width override default-arg path.

**Files edited.**
- `docs/ENGINEERING_PLAN.md` — DASH.5 row flipped to ✅ with implementation summary.
- `docs/DECISIONS.md` — D-085 appended (seven decisions: `PerfSnapshot` value-type rationale, `.progressBar` over `.bar` for FRAME, builder-layer clamp asymmetry vs D-084's renderer-layer clamp, Int-encoded quality enum, Int + retry-ms encoded ML decision, no `statusRed` durable rule, no per-row colour tuning for FRAME with DASH.5.1 amendment slot).
- `CLAUDE.md` — `Renderer/Dashboard/` Module Map entries for `PerfSnapshot` and `PerfCardBuilder`.

**Decisions captured.**
- **D-085 — PERF card data binding.** Snapshot value type because PERF state is genuinely spread across two manager classes (no single live source like DASH.4's `StemFeatures`). `.progressBar` (unsigned ramp) over `.bar` (signed-from-centre) because frame time vs budget is naturally unsigned and headroom is the load-bearing signal. Builder-layer clamp because `.progressBar` has no `range` field — single source of truth lives in the builder; asymmetric with STEMS (D-084) where the renderer is the clamp authority. Int-encoded enums (quality + ML decision) keep the snapshot a leaf value type with no upward dependency on manager enums. No `statusRed` token introduced — yellow = governor active is sufficient; the rule is durable across the dashboard. Uniform coral on FRAME consistent with D-084's stems decision (bar fill ratio carries headroom; QUALITY text carries discrete state; colour reinforces, doesn't differentiate). DASH.5.1 amendment slot reserved for any per-row colour or formatting tuning surfaced by Matt's eyeball.

**Test count delta.**
- 6 dashboard tests added (33 → **39 dashboard tests pass**: 12 DASH.1 + 6 DASH.2.1 + 6 BeatCardBuilder + 3 progress-bar + 6 StemsCardBuilder + 6 PerfCardBuilder).
- Full engine suite green: **1123 tests passed**. Pre-existing `MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget` / `MemoryReporter.residentBytes` env-dependent flakes and the two GPU-perf parallel-run flakes documented in CLAUDE.md remain documented (none touched by DASH.5).
- 0 SwiftLint violations on touched files; app build clean.

**What's intentionally NOT in this increment.**
- No `RenderPipeline` / `DebugOverlayView` / `PlaybackView` wiring — DASH.6 scope.
- No multi-card composition / screen positioning — DASH.6 scope.
- No fourth row (GPU TIME, MEMORY, FPS, dropped-frames) — PERF is exactly FRAME / QUALITY / ML. Per-frame GPU timing belongs to a future increment if and only if soak-test reports show it carries information not already in `recentMaxFrameMs`.
- No sparkline / mini-graph for frame time history — typographic + bar geometry, consistent with .impeccable "no animation" and DASH.2.1 / DASH.3 / DASH.4 precedent.
- No `statusRed` token — durable rule across the dashboard.
- No per-row colour tuning for FRAME — uniform coral v1, with DASH.5.1 amendment slot.
- No convenience constructor accepting `FrameBudgetManager` + `MLDispatchScheduler` — `PerfSnapshot` is a pure value type; assembly happens at the call site in DASH.6.
- No `Equatable` on `Row` (D-082, D-083, D-084 standing rule).

**Artifact.**
`.build/dash1_artifacts/card_perf_active.png` — PERF card rendered for `recentMaxFrameMs=11.2, targetFrameMs=14, qualityLevelDisplayName="full", mlDecisionCode=3 (forceDispatch)` over the deep-indigo backdrop. FRAME bar fills ~80% in coral with `"11.2 ms"` valueText; QUALITY reads `"full"` in `statusGreen`; ML reads `"FORCED"` in `statusYellow`. Composes visually with `card_beat_locked.png` and `card_stems_active.png` for M7-style review of the three live cards.

---

## [dev-2026-05-07-f] DASH.4 — Stem energy card

**Increment:** DASH.4
**Type:** Feature (dashboard)

**What changed.**

The second **live** dashboard card binds `StemFeatures` → `DashboardCardLayout`. New pure `StemsCardBuilder` produces a four-row card titled `STEMS`: DRUMS / BASS / VOCALS / OTHER, each `.bar` row driven by the corresponding `*EnergyRel` field (MV-1 / D-026, floats 17–24 of `StemFeatures`). Range `-1.0 ... 1.0` (headroom over typical ±0.5 envelope). Sign-correct visual feedback: positive deviation fills right of centre (kick raises drums above AGC average), negative fills left (duck), zero draws no fill — the dim background bar dominates as the .impeccable "absence-of-signal" stable state. `valueText` formatted `%+.2f` so the leading sign is always shown (Milkdrop-convention readback). Uniform `Color.coral` across all four rows in v1; per-stem palette tuning is reserved for a DASH.4.1 amendment if Matt's eyeball flags monotony — direction (left vs right of centre) carries the stem-state semantic, colour reinforces. Builder is pass-through; clamping authority lives in the renderer's `drawBarFill` (defence-in-depth at one layer; test e regression-locks). Wiring into `RenderPipeline` / `PlaybackView` is DASH.6 scope, not DASH.4.

**Files added.**
- `PhospheneEngine/Sources/Renderer/Dashboard/StemsCardBuilder.swift` — pure `Sendable` struct: `build(from: StemFeatures, width: CGFloat = 280) -> DashboardCardLayout`. Single private `makeRow(label:value:)` helper produces a `.bar` row; uniform coral, range `-1.0 ... 1.0`, valueText `%+.2f`.
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/StemsCardBuilderTests.swift` — 6 `@Test` functions in `@Suite("StemsCardBuilder")`: zero snapshot (4 rows × {label, value=0, valueText=+0.00, coral, range -1...1}), positive drums (row 0 only, `+0.42`), negative bass (row 1 only, `-0.30`), mixed snapshot with row-order assertions + artifact write, unclamped passthrough at value 1.5 (regression lock for "renderer is the clamp authority"), width override default-arg path.

**Files edited.**
- `docs/ENGINEERING_PLAN.md` — DASH.4 row flipped to ✅ with implementation summary.
- `docs/DECISIONS.md` — D-084 appended (six decisions: `.bar` over `.progressBar`, no `StemEnergySnapshot` intermediary, uniform coral v1 + DASH.4.1 amendment slot, no-clamp-at-builder, range rationale, percussion-first row order).
- `CLAUDE.md` — `Renderer/Dashboard/` Module Map entry for `StemsCardBuilder`.

**Decisions captured.**
- **D-084 — STEMS card data binding.** `.bar` (signed) over `.progressBar` (unsigned) because `*EnergyRel` is naturally signed and unsigned would lose the duck information. Builder reads `StemFeatures` directly because no `StemEnergySnapshot` analog exists and adding one would only duplicate the MV-1 contract. Uniform `Color.coral` v1 because direction (left vs right of centre) is the load-bearing signal, not colour — multi-colour would read as a stereo VU meter / DAW mixer (wrong product cue) and would conflict with D-083's status-colour reservation. No clamp at builder layer; renderer's `drawBarFill` is the single authority. Range `-1.0 ... 1.0` puts typical ±0.5 envelope at ~50% bar fill (visible motion) with headroom for transients. Row order DRUMS / BASS / VOCALS / OTHER follows .impeccable's percussion-first reading order.

**Test count delta.**
- 6 dashboard tests added (3 → wait, 27 → 33 dashboard tests pass: 12 DASH.1 + 6 DASH.2.1 + 6 BeatCardBuilder + 3 progress-bar + 6 StemsCardBuilder).
- Full engine suite remains green except the pre-existing `MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget` and `MemoryReporter.residentBytes` env-dependent flakes documented in CLAUDE.md.
- Two GPU-perf tests (`RenderPipelineICBTests.test_gpuDrivenRendering_cpuFrameTimeReduced`, `SSGITests.test_ssgi_performance_under1ms_at1080p`) flaked under full-suite parallel-run contention; both pass in isolation. Neither touches Dashboard code; no regression from DASH.4 (the builder is pure CPU and changes no renderer pipeline state).
- 0 SwiftLint violations on touched files; app build clean.

**What's intentionally NOT in this increment.**
- No `RenderPipeline` / `DebugOverlayView` / `PlaybackView` wiring — DASH.6 scope.
- No multi-card composition / screen positioning — DASH.6 scope.
- No per-stem fill colours — DASH.4.1 amendment slot if monotony reads on the artifact eyeball.
- No fifth row (TOTAL / mood / frame budget) — STEMS is exactly DRUMS / BASS / VOCALS / OTHER. Frame budget is DASH.5; mood would be a future MOOD card.
- No `StemEnergySnapshot` value type — builder reads `StemFeatures` directly.
- No clamp at the builder layer — renderer is the single clamp authority.
- No new row variant — `.bar` from DASH.2 already covers signed deviation. (One less commit than DASH.3.)
- No `Equatable` on `Row` (D-082, D-083 standing rule) — tests use switch-pattern extraction.

**Artifact.**
`.build/dash1_artifacts/card_stems_active.png` — STEMS card rendered with `drumsEnergyRel = 0.5`, `bassEnergyRel = -0.4`, `vocalsEnergyRel = 0.2`, `otherEnergyRel = -0.1` over the deep-indigo backdrop. Bar directions readable: DRUMS right, BASS left, VOCALS right (small), OTHER left (small). Reserved for Matt's M7-style eyeball review of the live STEMS card.

---

## [dev-2026-05-07-e] DASH.3 — Beat & BPM card

**Increment:** DASH.3
**Type:** Feature (dashboard)

**What changed.**

The first **live** dashboard card binds `BeatSyncSnapshot` → `DashboardCardLayout`. New pure `BeatCardBuilder` produces a four-row card titled `BEAT`: MODE / BPM / BAR / BEAT. Lock-state colour mapping per .impeccable: REACTIVE/UNLOCKED `textMuted`, LOCKING `statusYellow`, LOCKED `statusGreen`. No-grid renders `—` placeholders with bars at zero — a stable visual state, not a transient.

**API changes:**

- `DashboardCardLayout.Row` gains `.progressBar(label:value:valueText:fillColor:)` — unsigned 0–1 left-to-right fill (distinct from `.bar` which is a signed slice from centre). Row height matches `.bar`.
- New `BeatCardBuilder` (`Sendable`, `public`) with `init()` and `build(from:width:) -> DashboardCardLayout`.
- `DashboardCardRenderer.drawBarChrome` access widened from `private` to `internal` so the new `DashboardCardRenderer+ProgressBar` extension can reuse the chrome path. No public surface change on the renderer struct itself.
- `BeatSyncSnapshot` is **unchanged**. BEAT phase is derived as `barPhase01 × beatsPerBar − (beatInBar − 1)` clamped to `[0, 1]`. Promoting `beatPhase01` to a first-class snapshot field is deferred to a future increment with its own scope (touches `Sendable` struct, every construction site, and `SessionRecorder.features.csv` column ordering).

**Files added.**

- `PhospheneEngine/Sources/Renderer/Dashboard/BeatCardBuilder.swift`
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer+ProgressBar.swift`
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/BeatCardBuilderTests.swift` (6 tests)
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/DashboardCardRendererProgressBarTests.swift` (3 tests)

**Files edited.**

- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift` (`.progressBar` row case + `progressBarHeight` constant + `Row.height` switch arm)
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer.swift` (dispatch case for `.progressBar`; `drawBarChrome` access `private → internal`)

**Not in this increment (deferred).**

- Wiring `BeatCardBuilder` into `RenderPipeline` / `PlaybackView` / `DebugOverlayView` — DASH.6 owns wiring + multi-card composition + `D` key toggle.
- Adding `beatPhase01: Float` to `BeatSyncSnapshot` and the corresponding `features.csv` column.
- Animations / hover / focus — the dashboard remains read-only typographic telemetry.
- Frame-budget card and stem energy card — DASH.4 and DASH.5.

**Decisions:** D-083 in `docs/DECISIONS.md` (rationale: `.progressBar` row variant for unsigned ramps, lock-state colour mapping, no-grid graceful policy, derived beat phase + deferral of `beatPhase01` snapshot field).

**Test count delta.** 18 → 27 dashboard tests (12 DASH.1 + 6 DASH.2.1 + 6 BeatCardBuilder + 3 progress-bar). Full engine suite green except the documented pre-existing flakes (`MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget`, `MemoryReporter.residentBytes` env-dependent). 0 SwiftLint violations on touched files. `xcodebuild -scheme PhospheneApp` clean.

**Artifact.** `card_beat_locked.png` rendered at 320×220 onto the deep-indigo backdrop matches the eyeball criteria: BEAT title in muted UPPERCASE, MODE `LOCKED` in green, BPM `140` clean and mono, BAR fills ~62% with purpleGlow + `3 / 4` valueText, BEAT fills ~50% with coral + `3` valueText. Card chrome reads as purple-tinted, not black.

---

## [dev-2026-05-07-d] BUG-007.3 — Reverted (failed manual validation)

**Increment:** BUG-007.3 (revert)
**Type:** Revert

**What changed.** Commit `94309858` reverted in full. The Schmitt hysteresis + drift-slope retry implementation did not deliver the manual-validation gates: Everlong planned regressed (5 → 14 lock drops in comparable windows), reactive Everlong landed at `bpm=85.4` (halving-correction misfire — separate issue, BUG-009), and a previously-unseen ~1 s "visual ahead of audio" offset surfaced on internal speakers (BUG-007.4 — investigation bug). The `LiveBeatDriftTracker` returns to its BUG-007.2 state. Three replacement bugs filed in `KNOWN_ISSUES.md`: BUG-007.4 (visual phase offset on internal speakers — diagnostics first), BUG-007.5 (adaptive-window lock hysteresis on asymmetric drift envelopes), BUG-009 (halving-correction threshold).

**Validation evidence:** `~/Documents/phosphene_sessions/2026-05-07T14-28-40Z/` (planned), `~/Documents/phosphene_sessions/2026-05-07T14-33-47Z/` (reactive). Everlong planned: 14 lock drops in 75 s, drift envelope −68 to +25 ms (pre-fix: 5 drops). Reactive Everlong: `grid_bpm=85.4` from `halvingOctaveCorrected()` halving a 170 BPM raw output. Reactive Billie Jean (control): no regression, 3 lock drops, drift bounded.

---

## [dev-2026-05-07-c] DASH.2.1 — Card layout redesign: stacked rows + WCAG-AA labels + brighter chrome

**Increment:** DASH.2.1 (amendment to DASH.2)
**Type:** Design (renderer)

**What changed.**

`/impeccable` review of the DASH.2 artifact surfaced five issues that constant-tuning could not fix: (1) horizontal `label LEFT … value RIGHT` swallowed the label-value relationship at typical card widths; (2) `textMuted` on the card surface gave ~3.3:1 contrast — failing WCAG AA for body-size text; (3) `Color.surface` (oklch 0.13) read as near-black against any backdrop; (4) the pair-row 1 px divider was invisible; (5) bar rows had label/bar/value spatially detached. All five resolved.

**API changes:**

- `DashboardCardLayout.Row` cases reduced to two: `.singleValue` and `.bar` (the `.pair` variant is removed; no callers).
- Stacked layout: label 11 pt UPPERCASE on top, value below. Heights: `singleHeight = 39` (11 + 4 + 24), `barHeight = 32` (11 + 4 + 17). New constant `DashboardCardLayout.labelToValueGap = 4`.
- `DashboardCardLayout.height` skips the `titleSize` term when `title.isEmpty`.

**Renderer changes:**

- Card chrome: `Color.surface` → `Color.surfaceRaised` (oklch 0.17 / 0.018, slightly brighter and more chromatic). Alpha 0.92 unchanged.
- Title and all row labels: `Color.textMuted` → `Color.textBody` (~10:1 vs ~3.3:1).
- Bar row geometry: bar reserves a 56 pt right-side column for value text + 8 pt gap; bar centre is the bar's own mid-x, not the card centre. Bar fill refactored into `drawBarChrome` + `drawBarFill` helpers (SwiftLint compliance).

**Test changes (still 6 in `@Suite("DashboardCardRenderer")`):**

- `render_pairRow_dividerVisible` removed (variant deleted); replaced with `render_singleValueRow_stacksLabelAboveValue` (asserts vertical span between first and last glyph row ≥ 12 pt).
- Canonical artifact test renamed to `render_beatCard_pixelVerifyLabelPositions`. New test helper `paintVisualizerBackdrop` paints a representative deep-indigo backdrop (oklch 0.18 / 0.06 / 285) before the card is drawn — the saved `card_beat.png` now reflects production conditions over a visualizer rather than over transparent black.
- Bar-row tests rebuilt around the new geometry: `barGeometry(for:at:)` helper reproduces the renderer's reserved-column math so sample positions land well inside the fill rather than on its edge.

**Demo fixture (`beatCardFixture`):** card titled `BEAT` with four rows MODE / BPM / BAR / BASS, matching the .impeccable Beat panel. MODE's value uses `Color.statusGreen` for the locked-state colour cue.

**Files edited:**

- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift`
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer.swift`
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/DashboardCardRendererTests.swift`
- `docs/ENGINEERING_PLAN.md`, `docs/DECISIONS.md` (D-082 Amendment 1), `CLAUDE.md`

**Test counts:** 6 DASH.2 tests rebuilt (still 6); 18 dashboard tests total. Full engine suite green; 0 SwiftLint violations on touched files; app build clean. Decisions: D-082 Amendment 1.

**Visual approval:** Matt approved the new artifact `card_beat.png` 2026-05-07.

---

## [dev-2026-05-07-b] BUG-007.3 — Lock hysteresis + live BPM credibility

**Increment:** BUG-007.3
**Type:** Bug fix (DSP / live beat tracking)

**What changed.**

Closes the two failure modes observed during 2026-05-07 manual validation that BUG-007.2 left unaddressed:

- **Mechanism C — natural-music tempo variation drops lock under correct BPM.** Pre-fix, SLTS held lock 80 s but Everlong dropped 5 times in 50 s with drift in the −30 to −68 ms band, even though grid BPM was correct. Individual onsets falling outside `abs(instantDrift − drift) < 30 ms` for ≥ 7 consecutive onsets dropped lock; at 158 BPM that's a 2.7 s window, easily filled by harmonics, reverb tail, snare bleed.
- **Mechanism D — live BPM resolver returns 4 % low on busy mid-frequency content.** Reactive Everlong locked to `grid_bpm=151.9` (true ≈158); drift went 0 → −358 ms over 75 s.

**Part (a) — Schmitt-style asymmetric hysteresis** (`PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift`):

New `staleMatchWindow: Double = 0.060` constant. `update()` lock-decision rewritten — onsets within ±30 ms (`strictMatchWindow`) increment `matchedOnsets` toward `lockThreshold` (acquisition selectivity unchanged). While *already locked*, onsets within ±60 ms but outside ±30 ms are **stale-OK**: they do not increment `matchedOnsets` *or* `consecutiveMisses`, preserving lock through natural expressive timing. Only onsets outside ±60 ms (or no-match returns from `nearestBeat`) increment `consecutiveMisses` toward `lockReleaseMisses=7`.

**Part (b) — drift-slope detector + wider-window retry**:

- New ring buffer of 30 `(playbackTime, driftMs)` samples in `LiveBeatDriftTracker`, pushed on every matched onset. Public `currentDriftSlope() -> Double?` returns least-squares ms/sec slope when ≥ 5 samples cover ≥ 5 s; nil otherwise. Reset on `setGrid` / `reset`.
- New retry trigger in `PhospheneApp/VisualizerEngine+Stems.swift runLiveBeatAnalysisIfNeeded()`. Three paths: (A) no grid → existing 10 s / 20 s initial attempts; (B) prepared-cache grid → skip live inference (BUG-008 territory); (C) live grid present → slope-driven 20 s wider retry when `abs(slope) > 5 ms/s` sustained ≥ 10 s, with 30 s cooldown and a hard cap at 1 retry per track. After the retry, a second high-slope event logs `WARN: live BPM unstable` and *retains* the previous grid rather than installing a third candidate.
- New `BeatGridSource` enum on `VisualizerEngine` (`.none / .preparedCache / .liveAnalysis`) tracks where the installed grid came from so Path C only fires on live grids.

**Files edited:**

- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift`
- `PhospheneApp/VisualizerEngine.swift`
- `PhospheneApp/VisualizerEngine+Stems.swift`
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` (4 new tests)
- `docs/QUALITY/KNOWN_ISSUES.md`, `docs/ENGINEERING_PLAN.md`, `docs/RELEASE_NOTES_DEV.md`

**Tests added** (MARKs 19–22 in `LiveBeatDriftTrackerTests`):

- `schmittHysteresis_preservesLockThroughExpressiveTempoVariation` — synthetic 158 BPM grid + sinusoidal ±50 ms drift wander over 60 s. Asserts ≤ 1 lock drop. Pre-fix would drop ≥ 4.
- `driftSlope_insufficientSamples_returnsNil` — slope returns nil before 5 samples accumulate.
- `driftSlope_flatDrift_returnsNearZero` — perfectly aligned onsets for 12 s → slope < 1 ms/s.
- `driftSlope_linearWalkingDrift_recoversSlope` — onsets pushed forward by 4 ms each (≈ 8 ms/s) → recovered |slope| within 2 ms/s of truth, sign negative (drift = nearest − pt convention).

**Tests run.** `LiveBeatDriftTrackerTests` 22 / 22 pass. Full engine suite 1104 / 1106 (two pre-existing flakes: `MemoryReporter.residentBytes` env-dependent, `MetadataPreFetcher.fetch_networkTimeout` timing-sensitive — both pass on isolated re-run). `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` — clean. `swiftlint --strict` — 0 violations on touched files.

**Manual validation pending.** Acceptance gates in `KNOWN_ISSUES.md BUG-007.3`. Capture sessions to be run on SLTS planned, Everlong planned, Everlong reactive, Billie Jean reactive (control).

**Out of scope (deferred).** Constant ~10–15 ms negative-drift offset (tap-output latency calibration). BUG-008 (offline BPM disagreement). `strictMatchWindow` widening (acquisition selectivity stays). Slope-driven retry on prepared-cache path.

---

## [dev-2026-05-07-a] DASH.2 — Metrics card layout engine

**Increment:** DASH.2
**Type:** Infrastructure (renderer)

**What changed.**

Added the layout primitive that DASH.3 (Beat & BPM), DASH.4 (Stems), and DASH.5 (Frame budget) will compose. Cards are the unit of visual identity for the dashboard — fixed width, fixed row heights, three row variants only.

**Files added:**

- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift` — value type describing one card: title, ordered rows, fixed width, padding, title size, row spacing. `Row` enum with three cases (`.singleValue` / `.pair` / `.bar`) and static row-height constants (single = 18 pt, pair = 18 pt, bar = 22 pt). `height` is computed: `padding + titleSize + (rowSpacing + rowHeight) × N + padding`.
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer.swift` — stateless `Sendable` struct. `render(_:at:on:cgContext:)` paints chrome (rounded `Color.surface` fill at 0.92 alpha + 1 px `Color.border` stroke) → bar geometry → text in that order; reversing the order is a known Failed Approach (text gets painted over). Right-edge clipping enforced via `align: .right` on every value column. Bar fill is signed slice from centre (negative left, positive right), clamped to the supplied range.

**Files edited:**

- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardTextLayer.swift` — added `internal var graphicsContext: CGContext` so the renderer can paint chrome and bar geometry into the same shared buffer the text layer rasterises into.

**Tests added (6 `@Test` functions in `@Suite("DashboardCardRenderer")`):**

- `layoutHeight_matchesSumOfRows` — encodes the height formula explicitly so future row-height edits surface as test failures.
- `render_threeRowCard_pixelVerifyLabelPositions` — renders the canonical three-row card, asserts title-strip glyph alpha and zero paint past `layout.height`. Writes `.build/dash1_artifacts/card_three_row.png` for M7-style review.
- `render_cardNearRightEdge_clipsCorrectly` — places a 280 pt card at `canvasWidth - 280` on a 512 px canvas; asserts the rightmost column's luma is below the text-glyph threshold (chrome fill at the edge is allowed; a stray `textHeading` glyph would fail).
- `render_barRow_negativeValueFillsLeft` — `value: -0.5, range: -1...1` with coral fill: left half coral, right half background.
- `render_barRow_positiveValueFillsRight` — mirror of the negative test.
- `render_pairRow_dividerVisible` — 1 px `Color.border` divider at the midpoint.

Pixel-assertion brittleness (the prompt's risk note) is mitigated by `maxChromaPixel(around:)`: the bar background and foreground are both opaque, so alpha alone cannot distinguish them — chroma can. The right-edge overflow check uses Rec. 601 luma instead of alpha so chrome (low-luma) is correctly distinguished from text glyphs (high-luma `textHeading`).

**What's intentionally NOT in this increment:**

- No card is wired into `RenderPipeline`, `PlaybackView`, or `DebugOverlayView`. DASH.6 owns wiring.
- No data binding (which metrics each card shows). DASH.3/4/5 own that.
- No interactive state (hover, focus). The dashboard is read-only telemetry.
- No animation / transition. Cards repaint each frame from current state.
- No fourth row variant, no flex-width card, no sparkline. Adding variants is a separate increment with explicit Matt approval.

**Decisions:** D-082 (this increment).

**Test counts:** 6 new (18 dashboard total = DASH.1 12 + DASH.2 6). Full engine suite: **1102 tests / 125 suites**, all green. App build clean. 0 SwiftLint violations on touched files.

---

## [dev-2026-05-06-e] DASH.1 — Telemetry dashboard text-rendering layer

**Increment:** DASH.1
**Type:** Infrastructure (renderer + shared)

**What changed.**

Added the foundation layer for Phosphene's floating telemetry dashboard — a developer-togglable HUD that will display real-time metrics (BPM, lock state, stem energies, frame budget) over any active preset.

New files:
- `PhospheneEngine/Sources/Shared/Dashboard/DashboardTokens.swift` — design token namespace: `TypeScale` (6 point sizes from caption=10 to display=36), `Spacing` (4 sizes), `Color` (11 SIMD4 swatches), `Weight`/`TextFont`/`Alignment` enums.
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardFontLoader.swift` — resolves Epilogue TTF from bundle `Fonts/` directory; falls back to system sans-serif; `OSAllocatedUnfairLock` cache; `resetCacheForTesting()` for test isolation.
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardTextLayer.swift` — zero-copy `MTLBuffer` → `CGContext` → `MTLTexture` text renderer; `.bgra8Unorm` pixel format; Core Text with permanent CTM flip; `beginFrame()` clears each frame.
- `PhospheneEngine/Sources/Renderer/Resources/Fonts/README.md` — custom TTF drop-in instructions.

New tests (12):
- `DashboardTokensTests` (4) — color channel ranges, type scale ordering, alignment enum, spacing values.
- `DashboardFontLoaderTests` (3) — system fallback, idempotent caching, test reset.
- `DashboardTextLayerTests` (5) — mono text coverage, prose text coverage, between-frame clear, alignment shift, color application.

Also fixed (pre-existing blockers):
- `LiveAdapter.swift`: added `nonisolated(unsafe)` to `lastOverrideTimePerTrack` (Swift 6.3.1 requirement for mutable stored properties on `@unchecked Sendable` classes).
- `ReactiveOrchestratorTests`: updated Test 5 to expect a hold (not a switch) at gap=0.030 < `minBoundaryScoreGap(0.05)`; added `mediumGapCatalog()` for Test 6 with gap≈0.060 > 0.05.

**Test suite:** 1096 engine tests; 2 pre-existing timing flakes (MetadataPreFetcher, AppleMusicConnectionViewModel). App build: `** BUILD SUCCEEDED **`. SwiftLint: 0 violations.

**No behaviour change to existing presets or sessions.** `DashboardTextLayer` is not yet wired into the render pipeline; wiring lands in DASH.6.

**Decision:** D-081 (font strategy, zero-copy pattern, SC retention, pixel-coverage calibration).

---

## [dev-2026-05-06-f] DASH.1.1 — Tokens aligned to `.impeccable.md` OKLCH spec

**Increment:** DASH.1.1
**Type:** Design-system alignment (shared tokens)

**What changed.**

The DASH.1 token placeholders are replaced with values derived from the `.impeccable.md` OKLCH palette, before DASH.2/3/4 cards reach for them.

- Brand: `purple`, `coral`, `teal` re-tuned from sRGB approximations to OKLCH-derived values; `purpleGlow`, `coralMuted`, `tealMuted` added.
- Surfaces: `bg`, `surface`, `surfaceRaised`, `border` added (4-step ladder, hue 275–278). Replaces the flat `chromeBg`/`chromeBorder`.
- Text: renamed and re-tuned. `textPrimary` → `textHeading` `oklch(0.94 0.008 278)`, `textSecondary` → `textBody` `oklch(0.80 0.010 278)`, `textMuted` re-tuned to `oklch(0.50 0.014 278)`. All three are tinted toward brand purple (~278°) — no pure white anywhere.
- TypeScale: `bodyLarge = 15` added (spec `md`, body in card content). Existing scale unchanged.
- Status: `statusGreen/Yellow/Red` unchanged — held close to pure for legibility per the "color carries meaning" principle.

Test changes:
- `DashboardTokensTests.colorValues()` rewritten to assert the OKLCH ladder: surface monotonically rising, neutrals tinted toward purple (blue > red), text ladder monotonically rising, heading bright but not pure white.
- `DashboardTextLayerTests` renamed `textPrimary` → `textHeading`, `textSecondary` → `textBody` at all five call sites.

**Test suite:** All 12 dashboard tests pass; SwiftLint 0 violations on touched files; app build clean.

**No behaviour change** — `DashboardTextLayer` is still not wired into the render pipeline (DASH.6).

**Decision:** D-081 amendment in DECISIONS.md.

---

## [dev-2026-05-06-d] DSP.4 — Drums-stem Beat This! diagnostic (third BPM estimator)

**Increment:** DSP.4
**Type:** Diagnostic enhancement (`dsp.beat`)

**What changed.** Added a third BPM estimator — Beat This! run on the isolated drums stem — logged at preparation time alongside the existing MIR (kick-rate IOI) and full-mix Beat This! estimates. No runtime behaviour change.

**Files changed:**
- `PhospheneEngine/Sources/Session/StemCache.swift` — `CachedTrackData.drumsBeatGrid: BeatGrid` (default `.empty`); `StemCache.drumsBeatGrid(for:)` accessor.
- `PhospheneEngine/Sources/Session/SessionPreparer+Analysis.swift` — Step 6: feed `stemWaveforms[1]` (drums) into the same `DefaultBeatGridAnalyzer` used for the full mix.
- `PhospheneEngine/Sources/Session/BPMMismatchCheck.swift` — `ThreeWayBPMReading` struct + `detectThreeWayBPMDisagreement` pure function.
- `PhospheneEngine/Sources/Session/SessionPreparer+WiringLogs.swift` — `WIRING: SessionPreparer.drumsBeatGrid` per track; precedence logic: `WARN: BPM 3-way` (preferred, all three present) / `WARN: BPM mismatch` (fallback, drumsBPM zero).
- `PhospheneEngine/Tests/.../Session/BPMMismatchCheckTests.swift` — 7 new 3-way detector tests.
- `PhospheneEngine/Tests/.../Integration/BeatGridIntegrationTests.swift` — 2 new drumsBeatGrid wiring tests.
- `docs/ENGINEERING_PLAN.md`, `docs/RELEASE_NOTES_DEV.md`, `CLAUDE.md` — updated.

**Log lines added per prepared track:**
```
WIRING: SessionPreparer.beatGrid track='...' bpm=118.1 beats=60 isEmpty=false
WIRING: SessionPreparer.drumsBeatGrid track='...' bpm=125.0 beats=60 isEmpty=false
WARN: BPM 3-way track='Love Rehab' mir_bpm=125.0 grid_bpm=118.1 drums_bpm=125.0 mir-grid=5.6% mir-drums=0.0% grid-drums=5.6% (DSP.4: estimators on full-mix vs drums-stem vs kick-rate IOI)
```

**Performance:** one additional Beat This! inference call per prepared track (~415 ms on M-class silicon, absorbed in existing preparation window).

**Next step:** collect 2–3 fresh captures across genres; design fusion logic (OR.4 / DSP.5) when the fan-out pattern is understood.

---

## [dev-2026-05-06-e] BUG-007.2 — Fix prepared-grid horizon exhaustion + lock-hysteresis oscillation

**Increment:** BUG-007.2
**Type:** P2 defect fix (`dsp.beat` / `api-contract` + `algorithm`)

**What changed.** Two independent mechanisms prevented `LiveBeatDriftTracker` from holding `.locked` state in Spotify-prepared sessions. Both fixed.

**Fix A (Mechanism B — horizon exhaustion, 1 line).** `resetStemPipeline(for:)` now calls `cached.beatGrid.offsetBy(0)` instead of using the raw grid. The 30-second Spotify preview produces ~62 beats; `offsetBy(0)` extrapolates the grid to a 300-second horizon at the grid's own BPM. After t ≈ 30 s, `nearestBeat()` continued returning matches instead of nil, so `consecutiveMisses` stopped accumulating and lock held.

**Fix B (Mechanism A — cadence-mismatch oscillation, 1 line).** `lockReleaseMisses` raised from 3 → 7. The BeatDetector sub_bass cooldown (400 ms) vs Money's beat period (487 ms) produces roughly 5 consecutive misses per onset cycle. At threshold 3, lock dropped every 1.2 s; at threshold 7 (7 × 400 ms = 2.8 s), the worst-case gap never reaches the threshold and lock holds. Note: the diagnosis document stated 5; the regression test (`test_lockDoesNotOscillateOnStableInput`) demonstrates that the deterministic adversarial scenario requires ≥ 7 to achieve ≤ 2 oscillations in 60 s.

**Files changed:**
- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — `lockReleaseMisses = 7` (was 3); updated doc comment.
- `PhospheneApp/VisualizerEngine+Stems.swift` — `cached.beatGrid.offsetBy(0)` in `resetStemPipeline`.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — tests 16–18: `makeMoneySyntheticGrid` helper + three regression gates.
- `PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/LiveDriftLockHysteresisDiagnosticTests.swift` — `test_mechanismB` updated from raw-grid bug-documenter to `offsetBy(0)` fix-verifier; `%s` → `%@` format-string SIGSEGV fix; `test_mechanismA` assertion unchanged.
- `docs/QUALITY/KNOWN_ISSUES.md` — BUG-007 marked Resolved; verification criteria checked.

**Tests:** 1076 pass (1 pre-existing `MetadataPreFetcher` network-timeout flake). `BUG_007_DIAGNOSIS=1 swift test --filter LiveDriftLockHysteresisDiagnostic` — all 3 pass.

---

## [dev-2026-05-06-c] BUG-008.1 + BUG-008.2 — Diagnose & surface offline-grid vs MIR BPM disagreement

**Increments:** BUG-008.1 (diagnosis), BUG-008.1 follow-up (synthetic-kick test), BUG-008.2 (fix)
**Type:** P2 defect diagnosis + fix (`dsp.beat` / `algorithm`)

**Diagnosed:** The 5.5 % "BPM error" Love Rehab surfaces on the prepared BeatGrid path is **not a Phosphene port bug** and **not a sample-rate plumbing bug**. The vendored PyTorch reference fixture (`love_rehab_reference.json`, generated by the official Beat This! Python implementation on the same audio) reports `bpm_trimmed_mean=118.05`; Phosphene's Swift port reproduces this at 118.10 — within rounding. Three already-committed regression tests pin every layer of the port end-to-end. The disagreement reflects how Beat This! was trained: human tap annotations integrate the whole mix's accent structure, locking to the perceptual beat (118), while the kick-rate IOI estimator locks to the kick interval (125). Neither is mechanically "right." A synthetic-kick follow-up confirmed the model recovers exactly 125.00 BPM on machine-quantized input — so 125 is in the model's output distribution; on Love Rehab specifically it locks to the perceptual beat instead.

**Fixed (BUG-008.2):** Added `BPMMismatchCheck.swift` (pure detector) and wired it into `SessionPreparer+WiringLogs.swift`. After `prepare()` populates the cache, each track's `TrackProfile.bpm` (MIR / DSP.1 trimmed-mean IOI on sub_bass) is compared against `CachedTrackData.beatGrid.bpm` (Beat This! transformer). When the relative delta exceeds 3 %, a `WARN: BPM mismatch track='...' mir_bpm=... grid_bpm=... delta_pct=...% (BUG-008: estimators disagree; prepared grid uses Beat This! value)` line is emitted to `session.log` via the existing `SessionRecorder` and to the unified log via `Logger.warning`. **No runtime behaviour change** — `LiveBeatDriftTracker` continues to consume the offline grid. The 3 % threshold is intentionally generous: Money 7/4 (1.4 %) and Pyramid Song 16/8 (2.86 %) fall within and do NOT warn; Love Rehab (5.5 %) firmly does. Side finding from the synthetic-kick test: Beat This! returns 117.97 on a 120 BPM input (-1.7 %) and 130.09 on 130 BPM (+0.07 %) — small tempo-specific artifacts unrelated to BUG-008, documented in the diagnosis writeup.

**New tests:**
- `Tests/Diagnostics/BeatGridAccuracyDiagnosticTests.swift` (BUG-008.1) — 4 cases: port-fidelity tripwire on `love_rehab.m4a` against the PyTorch reference fixture; parametrized synthetic-kick recovery at 120/125/130 BPM.
- `Tests/Session/BPMMismatchCheckTests.swift` (BUG-008.2) — 7 pure-function cases: agreement/disagreement at default threshold, zero/non-finite guards, exact-tie boundary, custom threshold override, symmetric `delta_pct` normalization.
- `Tests/Integration/BeatGridIntegrationTests.swift` extended with `bpmMismatch_wiring_doesNotCrash_andGridReachesCache` — integration smoke using a `FixedBPMBeatGridAnalyzer` stub; verifies the wiring runs end-to-end and reaches the detector with both BPMs non-zero.

**Files added:**
- `PhospheneEngine/Sources/Session/BPMMismatchCheck.swift` — pure detector function + `BPMMismatchWarning` struct.
- `PhospheneEngine/Sources/Session/SessionPreparer+WiringLogs.swift` — extracted from `SessionPreparer.swift` (the file would otherwise breach the 400-line SwiftLint gate). Holds the existing BUG-006.1 `WIRING:` per-track summary plus the new BUG-008.2 BPM-mismatch warning.
- `PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/BeatGridAccuracyDiagnosticTests.swift`.
- `PhospheneEngine/Tests/PhospheneEngineTests/Session/BPMMismatchCheckTests.swift`.
- `docs/diagnostics/BUG-008-diagnosis.md` — full diagnosis writeup with all three checks (determinism / sample-rate plumbing / independent ground truth) settled by existing artifacts, plus the synthetic-kick follow-up section with results table.

**Files changed:**
- `PhospheneEngine/Sources/Session/SessionPreparer.swift` — extension moved to `+WiringLogs`; `sessionRecorder` visibility relaxed from `private` to `internal` so the new extension file can access it.
- `PhospheneEngine/Tests/PhospheneEngineTests/Integration/BeatGridIntegrationTests.swift` — `FixedBPMBeatGridAnalyzer` stub + wiring smoke test added.
- `docs/QUALITY/KNOWN_ISSUES.md` — BUG-008 entry rewritten with the diagnosis result, fix description, and softened "estimators disagree" framing (replaces the original "true 125 BPM" framing, which the diagnosis cannot prove).

**Tests:** Engine suite green except the two documented baseline flakes (`MetadataPreFetcher.fetch_networkTimeout`, `SessionManagerCancel`/`ProgressiveReadiness` `@MainActor` timing under parallel execution — both pass in isolation). xcodebuild clean. SwiftLint baseline preserved on touched files (zero new violations).

**Manual validation:** Not gated on a fresh capture — the existing `2026-05-06T20-11-46Z` capture already contains the data that would trigger the WARN on Love Rehab. A future Spotify-prepared session will surface the new line in `session.log`. Live drift behaviour is unchanged from BUG-007's state — that is the intended scope.

**Known issues introduced:** None.
**Known issues resolved:** BUG-008 — disagreement is now surfaced; underlying upstream-model behaviour unchanged by design. BUG-007 (drift-tracker lock-hysteresis) remains open and continues to block the user-visible PLANNED · LOCKED criterion.

**Related:** BUG-008, BUG-006.2 (exposed the latent disagreement end-to-end), BUG-007 (independent — drift-tracker symptom is not addressed by this fix), DSP.2 S5 (introduced offline BeatGrid resolver), Failed Approach #52 (sample-rate plumbing — explicitly ruled out by BUG-008.1 diagnosis).

---

## [dev-2026-05-06-b] BUG-006.2 — Prepared-BeatGrid wiring fix

**Increments:** BUG-006.1 (instrumentation, prior commit), BUG-006.2 (fix)
**Type:** P1 defect fix (`dsp.beat` / `pipeline-wiring`)

**Fixed:**
- **Cause 1 — engine.stemCache never assigned.** `VisualizerEngine.swift:171` declared `var stemCache: StemCache?` but no code in the codebase ever assigned to it. Every `resetStemPipeline(for:)` call therefore took the cache-miss branch and the prepared `BeatGrid` never installed. Now wired in `init` to `sessionManager.cache` (the same `StemCache` instance `SessionPreparer` populates) — entries become visible by reference as preparation completes.
- **Cause 2 — Track-change handler built a partial `TrackIdentity`.** `VisualizerEngine+Capture.swift:129` constructed `TrackIdentity(title:, artist:)` only — duration, catalog IDs, and `spotifyPreviewURL` left nil. `Hashable` therefore mismatched the keys `SessionPreparer` stored from full Spotify-API identities. Now resolves the canonical identity from `livePlan` via the new `PlannedSession.canonicalIdentity(matchingTitle:artist:)` helper. Falls back to the partial identity for ad-hoc/reactive sessions and ambiguous matches.

**New tests:**
- `Tests/Integration/PreparedBeatGridAppLayerWiringTests.swift` (6 cases) — closes the BUG-003 coverage gap that allowed BUG-006 to ship. Tests cover `engineStemCache_isWiredAfterSessionPrepare`, `trackChangeIdentity_matchesPlannedIdentity`, `ambiguousMatch_returnsNil_partialFallback`, `noMatch_returnsNil`, `endToEndProduces_preparedCacheInstall`, `partialIdentity_withoutCanonicalResolution_missesCache` (negative control pinning the regression direction).

**Files added:**
- `PhospheneApp/VisualizerEngine+TrackIdentityResolution.swift` — `canonicalTrackIdentity(matching:)` instance method delegating to the Orchestrator-module pure helper.
- `PhospheneEngine/Tests/PhospheneEngineTests/Integration/PreparedBeatGridAppLayerWiringTests.swift`.

**Files changed:**
- `PhospheneApp/VisualizerEngine.swift` — assigns `self.stemCache = self.sessionManager.cache` after `makeSessionManager`.
- `PhospheneApp/VisualizerEngine+Capture.swift` — track-change handler resolves canonical identity before `resetStemPipeline`.
- `PhospheneApp/VisualizerEngine+WiringLogs.swift` — `logTrackChangeObserved` now reports `resolution=fromLivePlan|partialFallback`.
- `PhospheneEngine/Sources/Orchestrator/PlannedSession.swift` — `canonicalIdentity(matchingTitle:artist:)` pure-function helper added.
- `PhospheneApp.xcodeproj/project.pbxproj` — registered `VisualizerEngine+TrackIdentityResolution.swift` (N10007 / N20007).

**Tests:** 1051 engine tests / 116 suites. Pass except the two documented baseline flakes (`MetadataPreFetcher.fetch_networkTimeout`, `MemoryReporter.residentBytes growth`). App build clean. SwiftLint baseline preserved on touched files (zero new violations).

**Manual validation:** Pending the next live Spotify capture. The BUG-006.1 `WIRING:` instrumentation logs will surface end-to-end behaviour in `session.log`. Verification criteria from the BUG-006 entry remain unchecked until a live session is captured (SpectralCartograph mode label, drift readout settling, `grid_bpm` column in `features.csv`).

**Known issues introduced:** None.
**Known issues resolved:** BUG-006 (code-only — manual sign-off pending). BUG-003's first verification criterion checked off (`PreparedBeatGridAppLayerWiringTests`); LiveDriftValidationTests still pending.

**Related:** BUG-006, BUG-003, BUG-006.1, DSP.3.6, D-070 (`TrackIdentity.spotifyPreviewURL` excluded from `Hashable`).

---

## [dev-2026-05-06-a] BUG-006.1 — Wiring instrumentation

**Increments:** BUG-006.1
**Type:** Instrumentation (no behaviour change)

Source-tagged `WIRING:` log entries added across the prepared-BeatGrid path so a live session capture surfaces the failure mode end-to-end. Optional `SessionRecorder` threaded through `SessionPreparer` and `SessionManager` so logs land in `session.log`. New file `PhospheneApp/VisualizerEngine+WiringLogs.swift` consolidates helpers; `SessionManager+Readiness.swift` extracted to keep `SessionManager.swift` under the SwiftLint 400-line gate. New `caller:` parameter on `resetStemPipeline(for:caller:)` discriminates pre-fire (planner) from track-change paths. Commits `7f95cec0` + `807d3b8c`.

---

## [dev-2026-05-05-c] Quality System Documentation

**Increments:** QS.1
**Type:** Infrastructure / documentation

**New:**
- `docs/QUALITY/DEFECT_TAXONOMY.md` — severity definitions (P0–P3), domain tags, failure classes, and defect process.
- `docs/QUALITY/BUG_REPORT_TEMPLATE.md` — structured template for filing defects with required fields.
- `docs/QUALITY/KNOWN_ISSUES.md` — active issue tracker: 5 open defects (BUG-001 through BUG-005), 5 pre-existing flakes, and 5 recently-resolved P1 defects from DSP.3.x work.
- `docs/QUALITY/RELEASE_CHECKLIST.md` — 10-section pre-release gate covering build, DSP/beat-sync, stem routing, preset fidelity, render pipeline, session/UX, performance, documentation, and git hygiene.
- `docs/RELEASE_NOTES_DEV.md` — this file.

**Changed:**
- `CLAUDE.md` — new `Defect Handling Protocol` section added after `Increment Completion Protocol`.
- `docs/ENGINEERING_PLAN.md` — QS.1 increment added and marked complete.

**Known issues introduced:** None.
**Known issues resolved:** None (documentation only).

---

## [dev-2026-05-05-b] DSP.3.5 + V.7.7A

**Increments:** DSP.3.5, V.7.7A
**Type:** DSP fix + preset architecture

**DSP.3.5 — Halving octave correction + retry:**
- `BeatGrid.halvingOctaveCorrected()` added: halves BPM > 160 recursively, drops every other beat, re-snaps downbeats, recomputes `beatsPerBar`. BPM < 80 unchanged (Pyramid Song guard).
- Live Beat This! retry gate: `liveBeatAnalysisAttempts: Int` (was Bool), max 2 attempts — first at 10 s, retry at 20 s on empty grid.
- `performLiveBeatInference()` extracted for SwiftLint compliance.
- 4 new `BeatGridUnitTests`. **1032 engine tests.**
- Post-validation triage: `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md`.

**V.7.7A — Arachne staged-composition scaffold migration:**
- Arachne migrated from `passes: ["mv_warp"]` to V.ENGINE.1 staged scaffold.
- New fragment functions: `arachne_world_fragment` (placeholder forest backdrop) + `arachne_composite_fragment` (placeholder 12-spoke web overlay).
- Mv-warp helpers removed (incompatible with staged preamble).
- Legacy `arachne_fragment` retained as v5/v7/v9 reference.
- `Arachne.json` updated: `passes: ["staged"]` with two stage definitions.

**Known issues introduced:**
- BUG-002 (PresetVisualReviewTests PNG export broken for staged presets) — pre-existing harness bug exposed by V.7.7A.

**Known issues resolved:**
- BUG-R004 (double-time BPM on 10-second window) — resolved by DSP.3.5 octave correction.

---

## [dev-2026-05-05-a] DSP.3.1–3.4 + V.7.7

**Increments:** DSP.3.1, DSP.3.2, DSP.3.3, DSP.3.4, V.7.7
**Type:** DSP fixes + preset content

**DSP.3.1+3.2 — Diagnostic hold + session-mode signal + pre-fire BeatGrid:**
- `diagnosticPresetLocked` flag, `L` shortcut.
- `SpectralHistoryBuffer[2420]` session-mode slot (0–3).
- SpectralCartograph mode labels: ○ REACTIVE / ◐ PLANNED·UNLOCKED / ◑ PLANNED·LOCKING / ● PLANNED·LOCKED.
- `_buildPlan()` pre-fires BeatGrid.

**DSP.3.3 — Beat sync observability:**
- `SpectralCartographText.draw()` extended with beat-in-bar, drift, phase-offset readouts.
- `textOverlayCallback` now passes `FeatureVector` per frame.
- `[`/`]` developer shortcuts for ±10 ms visual phase calibration.
- `BeatSyncSnapshot` struct (9-field).
- `SessionRecorder.features.csv` gains 9 beat-sync columns.
- `SpectralHistoryBuffer[2421..2429]` downbeat_times + drift_ms slots.
- 31 new tests. **1018 engine tests.**

**DSP.3.4 — Three root causes fixed blocking PLANNED·LOCKED:**
- Bug 1: `BeatGrid.offsetBy` now extrapolates to 300-second horizon.
- Bug 2: `VisualizerEngine.tapSampleRate` stored from audio callback; passed to Beat This!.
- Bug 3: `StemSampleBuffer.snapshotLatest(seconds:sampleRate:)` overload uses actual tap rate.
- 14 new tests. **1028 engine tests.**

**V.7.7 — Arachne WORLD pillar + background dewy webs:**
- Six-layer `drawWorld()` Metal function: sky gradient, distant + near trees, forest floor, atmosphere.
- Snell's-law refractive drops on two background hub webs.
- `ArachneState._tick()` gains `smoothedValence`/`smoothedArousal` (5s low-pass) for mood palette.
- `WebGPU` struct extended with Row 4 `moodData: SIMD4<Float>` (64 → 80 bytes).
- Golden hashes regenerated.

**Known issues resolved:**
- BUG-R001 (BeatGrid finite horizon) — resolved by DSP.3.4.
- BUG-R002 (hardcoded 44100 Hz sample rate) — resolved by DSP.3.4.
- BUG-R003 (StemSampleBuffer undersized at 48000 Hz) — resolved by DSP.3.4.

---

## [dev-2026-05-05] DSP.2 Complete + DSP.3 Audit

**Increments:** DSP.2 S3–S9, DSP.2 hardening, DSP.3 audit
**Type:** DSP — Beat This! transformer + drift tracker

**Summary:** Full Beat This! small0 transformer implemented in Swift/MPSGraph. BeatGrid pipeline end-to-end from Spotify-prepared sessions. Live reactive mode gets Beat This! inference after 10 s of playback. `barPhase01`/`beatsPerBar` propagated to FeatureVector and GPU.

**Bug fixes landed:**
- Four S8 bugs: norm-after-conv shape, transpose-before-reshape, BN1d zero-padding semantics, paired-adjacent RoPE. All individually regression-locked in `BeatThisBugRegressionTests`.
- DSP.3 audit revealed three root causes blocking LOCKED state (fixed in DSP.3.4, see above entry).

**Test suite:** 1028 engine tests / 106 suites at DSP.3.4.

**Known issues introduced:**
- BUG-001 (Money 7/4 stays REACTIVE on live path) — identified during DSP.3.5 post-validation.

---

## [dev-2026-05-04] DSP.2 S1–S2 + DSP.1

**Increments:** DSP.1, DSP.2 S1, DSP.2 S2
**Type:** DSP — tempo estimation rewrite + Beat This! vendoring

**DSP.1 — Sub_bass-only IOI + trimmed-mean BPM:**
- Eliminated band-fusion IOI bias (Failed Approach #50) and histogram-mode bias (Failed Approach #51).
- BPM error dropped from 10–20% to <2% on kick-on-the-beat tracks.
- Reference results: love_rehab 122–126 (true 125), so_what 135–138 (true 136).
- `TempoDumpRunner` CLI + `Scripts/dump_tempo_baselines.sh` + `Scripts/analyze_tempo_baselines.py` shipped as permanent regression infrastructure.

**DSP.2 S1 — Beat This! architecture audit + weight vendoring:**
- `small0` model selected: 2,101,352 params, 8.4 MB FP32, MIT license confirmed.
- 161 weight tensors vendored under Git LFS.
- Six JSON reference fixtures (love_rehab, so_what, there_there, pyramid_song, money, if_i_were_with_her_now).

**DSP.2 S2 — BeatThisPreprocessor Swift port:**
- Mono Float32 → log-mel spectrogram matching Beat This! Python `LogMelSpect` exactly.
- Critical: Slaney mel filterbank with continuous Hz interpolation (integer-bin approach underestimates ~12%).
- Golden match on love_rehab first 10 frames: max|Δ| = 2.9×10⁻⁵.

---

## [dev-2026-05-02] V.7.5, V.7.6.C, V.7.6.D, V.7.6.1, V.7.6.2

**Increments:** V.7.5, V.7.6.C, V.7.6.D, V.7.6.1, V.7.6.2

**V.7.5 — Arachne v5 (composition + warm restoration + drops + spider cleanup):**
- Pool capped 12→4, drops as visual hero (radius 8 px), Marschner TRT-lobe warm rim restored, warm key / cool ambient.
- Spider: dark silhouette, AR gate restored, `subBassThreshold` 0.65→0.30.
- M7 review result: output matches `10_anti_neon_stylized_glow.jpg` anti-reference. `certified` rolled back to false. V.7.6 (atmosphere-as-mist patch) abandoned in favour of compositing-anchored V.7.7+.

**V.7.6.1 — Visual feedback harness:**
- `PresetVisualReviewTests` renders presets at 1920×1280 for three FeatureVector fixtures.
- Contact sheet: render in top half, refs 01/04/05/08 in bottom half.
- Gated behind `RENDER_VISUAL=1`.

**V.7.6.C — maxDuration calibration + diagnostic class:**
- Per-section linger factors inverted to Option B.
- `is_diagnostic` JSON field (→ `maxDuration = .infinity`); SpectralCartograph flagged.

**V.7.6.D — Diagnostic preset orchestrator exclusion:**
- `DefaultPresetScorer` excludes `is_diagnostic` presets categorically.
- `DefaultLiveAdapter` no-ops mood override for diagnostic presets.
- `DefaultReactiveOrchestrator` skips diagnostic presets in ranking.

**Known issues introduced:**
- BUG-004 (all presets `certified: false`) — documented; V.7.10 is the planned resolution path.

---

## [dev-2026-04-25] Milestones A, B, C

**Increments:** U.1–U.11, 4.0–4.6, 5.2–5.3, 6.1–6.3, 7.1–7.2, V.1–V.6, MV-0–MV-3
**Type:** Multi-phase milestone delivery

Milestones A (Trustworthy Playback), B (Tasteful Orchestration), and C (Device-Aware Show Quality) all met on 2026-04-25.

**Highlights:**
- Full session lifecycle (idle → connecting → preparing → ready → playing → ended).
- Apple Music + Spotify OAuth connectors.
- Progressive session readiness (partial-ready CTA).
- Orchestrator: PresetScorer, TransitionPolicy, SessionPlanner, LiveAdapter, ReactiveOrchestrator.
- Frame budget governor + ML dispatch scheduler.
- V.1–V.3 shader utility library (Noise, PBR, Geometry, Volume, Texture, Color, Materials).
- V.6 fidelity rubric + certification pipeline.
- Phase U: permission onboarding, connector picker, preparation UI, playback chrome, settings panel, error taxonomy, toast system, accessibility.
- Beat This! architecture committed (DSP.2 scope).

**Known issues at milestone:**
- All presets uncertified (BUG-004).
- Spotify preview_url null for some tracks (BUG-005).
- Test suite: 4 pre-existing Apple Music environment failures (unchanged).
