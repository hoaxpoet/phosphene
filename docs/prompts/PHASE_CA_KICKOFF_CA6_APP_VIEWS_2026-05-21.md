# Phase CA Kickoff — Capability Audit — Increment CA.6 (App Views + ViewModels)

Hand this to a new Claude Code session verbatim. Do not summarise.

## What this phase is

Phase CA — Capability Audit is a multi-increment archaeology of Phosphene's codebase. Each increment audits one subsystem: reads the actual source, traces consumers and producers, cross-references against `CLAUDE.md` / `docs/ARCHITECTURE.md` / `docs/QUALITY/KNOWN_ISSUES.md` / `docs/DECISIONS.md`, and assigns a health verdict to every capability the subsystem exposes.

CA.1 (DSP / MIR) closed 2026-05-20 at `../CAPABILITY_REGISTRY/DSP_MIR.md`. Surfaced one runtime production-orphan cluster (per-frame StructuralAnalyzer chain), one field-level orphan, boundary-deferred two Session/ files.

CA.2 (ML) closed 2026-05-20 at `../CAPABILITY_REGISTRY/ML.md`. Audited 16 ML files (4,507 LoC), surfaced four cluster-level production-orphan findings, two large built-but-undocumented gaps, BUG-012 instrumentation map. Methodology refinement: pre-grep visibility verification.

CA.3 (Session) closed 2026-05-20 at `../CAPABILITY_REGISTRY/SESSION.md`. Audited 22 Session files (~3,425 LoC), resolved all three CA.1/CA.2 boundary-deferred items. Found 1 stub, 0 broken-but-claimed, 0 production-orphan, 2 documented-but-missing + 2 built-but-undocumented in ARCHITECTURE.md. Methodology refinement: cross-check kickoff prompt against KNOWN_ISSUES.md as Pass 0.

CA.4 (Orchestrator) closed 2026-05-20 at `../CAPABILITY_REGISTRY/ORCHESTRATOR.md`. Audited 14 Orchestrator files (~2,950 LoC). Surfaced the load-bearing broken-but-claimed BUG-015 (`applyLiveUpdate(...)` had zero production call sites — the entire Phase 4.5/4.6 live-adaptation pipeline was dead in production despite the unit tests passing green). BUG-015 was filed, then fixed 2026-05-21 in commits `b3f1efd9` + `5efc6a90` + `bb5e36ef` (wire + diagnostic + Resolved flag) with the source-presence regression test `OrchestratorWiringRegressionTests.swift` locking the wire's existence.

CA.5 (App layer — engine-adapter slice) closed 2026-05-21 at `../CAPABILITY_REGISTRY/APP.md`. Audited 49 App-layer files (~7,975 LoC) covering the engine-coupling surface: `VisualizerEngine` + 11 extensions, `ContentView`, `PhospheneApp`, `ITunesSearchFetcher` (post-CA.5-FU-3 rename), `Services/` × 30, `Permissions/` × 3, `Models/` × 2. Verified BUG-015 wire shape clean (10 byte-level confirmations of the Resolved-field design notes). Verified BUG-012-i1 instrumentation intact across all 8 instrumented files. Surfaced 1 field-level production-orphan (CA.5-FU-1 — `MultiDisplayToastBridge.coalesceTask` + `pendingEvents`; landed 2026-05-21), 1 unverified-claim (CA.5-FU-2 — `LiveAdaptationToastBridge` engine-event observation docstring; product call still pending), 1 file-naming drift (CA.5-FU-3 — `MusicKitFetcher.swift` → `ITunesSearchFetcher.swift`; landed 2026-05-21), and 2 large `built-but-undocumented` (ARCHITECTURE.md PhospheneApp/ block + Tests/PhospheneApp/ block — both corrected in CA.5). CA.5 explicitly deferred Views/ + ViewModels/ to **CA.6**.

This kickoff is for Increment CA.6: the App Views + ViewModels presentation slice. It is the **sixth** audit pass.

## Why App Views + ViewModels next

Six reasons, in priority order:

1. **CA.5 closed the engine-adapter side; CA.6 closes the matched presentation side.** Every `@Published` field declared in `VisualizerEngine.swift` and consumed elsewhere (`currentTrackIndex`, `livePlannedSession`, `dashboardSnapshot`, `audioSignalState`, `currentPresetName`, `currentTrack`, `mirDiag`, `currentMood`, `estimatedKey`, `estimatedTempo`) is wired through publishers into Views/ViewModels. The BUG-015 wire's downstream consumer chain — `engine.$currentTrackIndex.eraseToAnyPublisher()` at `ContentView.swift:85` → `PlaybackChromeViewModel` — runs entirely through the CA.6 surface. CA.5 audited the producer side; CA.6 audits the consumer side and closes the boundary.

2. **Largest unaudited surface in the codebase by file count.** 59 files (47 `Views/` + 12 `ViewModels/`), ~6.9k LoC. After CA.6 lands, the remaining unaudited engine modules are CA-Renderer (`PhospheneEngine/Sources/Renderer/`), CA-Audio (`PhospheneEngine/Sources/Audio/`), and CA-Presets (`PhospheneEngine/Sources/Presets/` per-preset state types) — all engine-side. App is fully closed.

3. **The U.10 / U.11 pre-existing-flake cluster has just been widened.** A parallel `[test-flake]` task chip landed 7 widening edits across `AppleMusicConnectionViewModelTests`, `LiveAdaptationToastBridgeTests`, `NetworkRecoveryCoordinatorTests`, `PlaybackChromeViewModelTests`, `ReadyViewModelTests`, `ReadyViewTimeoutIntegrationTests`, `SpotifyConnectionViewModelTests`, `SpotifyOAuthTokenProviderTests`, `ToastManagerTests`. Per CLAUDE.md U.10/U.11 + `project_test_baseline.md` memory note, the rule is "700 ms wait for 300 ms debounce; 250–400 ms wait for connect/login completions." CA.6 audits: (a) whether the post-chip margins **match U.11's baseline** (the chip's commits explicitly cite that baseline; verify each widened value is ≥ the documented minimum); (b) whether `@Suite(.serialized)` is in place on every URLProtocol-stub-using suite (only one App-layer suite had URLProtocol stubs per CA.5: `SpotifyOAuthTokenProviderTests` — verify other VM tests don't reintroduce the pattern unguarded). Any widening below the U.11 minimum is a `unverified-claim` finding (the chip claimed compliance with U.11 but the margin doesn't match). Any margin that should have been widened but wasn't is a `production-orphan` finding (the documented timing rule has no enforcing test).

4. **Multiple load-bearing regression-locked patterns live in Views + ViewModels.** `SettingsStoreEnvironmentRegressionTests` (D-091 / Failed Approach #55) asserts `PlaybackView.swift` source must NEVER declare `@StateObject SettingsStore()` — verify the file source still complies. `PlaybackChromeIndexBindingTests` (D-091 / QR.4) asserts title-case mismatches do not change `currentTrackIndex` — verify `PlaybackChromeViewModel`'s subscription chain still propagates the engine's `currentTrackIndex` publisher cleanly. `OrchestratorWiringRegressionTests` (BUG-015 / CA.4 closure) asserts the App-layer wire exists — already verified in CA.5; CA.6 verifies the consumer chains it feeds.

5. **Dashboard/ subfamily is its own load-bearing UX surface (DASH.7 / D-088 / D-089).** Five files: `DashboardOverlayView.swift` (top-trailing single panel; DASH.7.2 `DarkVibrancyView` + 0.96α surface + 1px border + `.environment(\.colorScheme, .dark)` lock per D-089), `DashboardCardView.swift` (Clash Display Medium @ 15pt or system semibold fallback), `DashboardRowView.swift` (4 row variants: `.singleValue` / `.bar` / `.progressBar` / `.timeseries`; DASH.7.2 inlined `.singleValue` row rhythm per D-089), `DarkVibrancyView.swift` (NSViewRepresentable wrapping NSVisualEffectView), `DashboardOverlayViewModel.swift` (`@MainActor ObservableObject` subscribes to `engine.$dashboardSnapshot` and throttles via `.throttle(for: .milliseconds(33))` for ~30 Hz). DASH.7 / DASH.7.1 / DASH.7.2 are recent (Late April / May 2026); ARCHITECTURE.md Module Map Views/Dashboard/ block already lists them but the audit should verify each file's declared visibility, the throttle constant, and the `ingestForTest(_:)` test-seam pattern.

6. **The view tree is where every U.x increment landed user-facing work.** ContentView's six SessionState branches (`.idle` / `.connecting` / `.preparing` / `.ready` / `.playing` / `.ended`) per UX_SPEC §3 map one view per state. PlaybackView (`.playing`) is the load-bearing center — hosts MetalView (NSViewRepresentable for MTKView), preset-name badge, NoAudioSignalBadge, DebugOverlayView, DashboardOverlayView, keyboard shortcuts (`→`/`←`/Space, `D`, `C`, `R`, `G`, plus U.6b live-adaptation shortcuts and the developer keys per `PlaybackShortcutRegistry`). PlaybackView owns `CaptureModeSwitchCoordinator`, `DisplayChangeCoordinator`, `NetworkRecoveryCoordinator`, `FullscreenObserver`, `PlaybackKeyMonitor`, `MultiDisplayToastBridge`, `PlaybackErrorBridge`, `LiveAdaptationToastBridge` as `@State`. CA.5 audited those Service classes; CA.6 audits the View that owns them.

## Read these first, before doing anything else

1. **CLAUDE.md** — the entire file. Especially: the **Audio Data Hierarchy** (View-layer must respect it when surfacing FeatureVector / StemFeatures / EmotionalState into the debug overlay and dashboard), **Failed Approach #55** (`@EnvironmentObject SettingsStore`; verify `PlaybackView` still uses `@EnvironmentObject` not `@StateObject`), **Failed Approach #56** (canonical-identity match; verify `PlaybackChromeViewModel` consumes the `currentTrackIndex` publisher, not a lowercased title+artist string match), and the **U.10 / U.11** timing-margin learnings (700 ms for 300 ms debounce; 250–400 ms for connect/login).

2. **docs/CAPABILITY_REGISTRY/APP.md** — CA.5 audit. Read §Findings-by-verdict, §Boundary-noted (App ↔ everything else), §Per-file-capability-index for `ContentView.swift` + `PhospheneApp.swift` + `Services/`, and §Verification-of-BUG-015-wire-shape. The App-layer adapter (engine-adapter slice) was audited in CA.5; CA.6 is the matched presentation-slice audit.

3. **docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md** — CA.4 audit. Read §boundary-noted "Orchestrator ↔ App" entry. `DefaultPlaybackActionRouter` is App-layer-concrete; its consumers are `PlaybackView` + `PlaybackKeyMonitor` + `PlaybackShortcutRegistry`. CA.4 closed the Orchestrator-internal side; CA.5 closed the Service-side; CA.6 closes the View-side keyboard wiring.

4. **docs/CAPABILITY_REGISTRY/SESSION.md** — CA.3 audit. Read §Boundary-noted "Session ↔ App". `SessionManager` is `@MainActor ObservableObject` observed by `SessionStateViewModel`, `PlaybackChromeViewModel`, `PreparationProgressViewModel`, `EndSessionConfirmViewModel`, `ReadyViewModel`; six concrete views switch on `SessionState`. Verify the App-side observation patterns match what CA.3 documented.

5. **docs/CAPABILITY_REGISTRY/DSP_MIR.md** — CA.1 audit. Read §Cross-references for the consumer chain into Views. `MIRDiagnostics` is published by `VisualizerEngine.mirDiag` — consumed by `DebugOverlayView`. `BeatSyncSnapshot` is published via `dashboardSnapshot.beat` — consumed by `DashboardOverlayViewModel`.

6. **docs/CAPABILITY_REGISTRY/ML.md** — CA.2 audit. Read §Cross-references. `EmotionalState` (`currentMood`) and `StemFeatures` (`dashboardSnapshot.stems`) flow into the dashboard surface.

7. **docs/QUALITY/KNOWN_ISSUES.md** — every Open entry. Especially:
   - **BUG-016** (Lumen Mosaic — Open; the CA.5 audit recorded the App-layer inventory but the failure mode is not yet characterised — `PlaybackView`'s keyboard cycle is where Matt observed the failure during `Shift+→` cycling).
   - **BUG-012** (instrumentation in place — CA.6 must not edit the 2 App-layer instrumented files: `VisualizerEngine.swift` + `VisualizerEngine+Stems.swift` are in `PhospheneApp/`, not in `PhospheneApp/Views/` or `PhospheneApp/ViewModels/`, so CA.6 will not naturally encounter them).
   - **BUG-001** (Money 7/4 stays REACTIVE — verify if any ViewModel-level finding is relevant; document, do not fix).
   - **BUG-013** (Soundcharts time_signature absence — App-layer consumer is in `VisualizerEngine+Capture.kickoffPreFetch`, CA.5-scope, but the UI surface for displaying meter lives in `PlaybackChromeView` or similar).
   - **Pre-existing Flakes** section — load-bearing for the CA.6 audit's special-attention items.

8. **docs/ARCHITECTURE.md** — sections **§UI Layer** (lines 220–242), **§Module Map PhospheneApp/Views/** (the post-CA.5 block lists ~22 of 47 Views — drift expected), **§Module Map PhospheneApp/ViewModels/** (lists 4 of 12 — drift expected), and **§Module Map Views/Dashboard/** (DASH.7 / DASH.7.1 / DASH.7.2 — likely complete because the dashboard work shipped recently). Particular attention: the Views/ + ViewModels/ blocks are the **most likely to have drifted** given the App layer's size and the U.x increment cadence; CA.5 found 34 of 49 engine-adapter files missing — expect similar drift here.

9. **docs/DECISIONS.md** — grep for **D-049** (UX shortcut spec deviation; `?` → `Shift+?` for help), **D-050** (PlaybackActionRouter protocol; concrete is App-layer per CA.5), **D-052** (CaptureModeReconciler live-switch path), **D-054** (in-shader reduced-motion gating; App-layer push via `VisualizerEngine.applyAccessibility`), **D-061** (long-session resilience: DisplayChangeCoordinator / CaptureModeSwitchCoordinator / NetworkRecoveryCoordinator — all `@State`-owned by PlaybackView or PreparationProgressView), **D-069** (Spotify OAuth two-decision split — Decision 2 = App-layer concrete), **D-088** + **D-089** (Dashboard typography + dark vibrancy lock per DASH.7.1 / DASH.7.2), **D-091** (single `SettingsStore` + `currentTrackIndex` publisher per QR.4 — both are App-layer consumer-side contracts).

10. **docs/ENGINEERING_PLAN.md** — search for **"Phase U"** (User-experience increments — almost every U.x increment landed view + view-model code; verify the View block in ARCHITECTURE.md keeps up), **"Increment U.6"** (in-session chrome; PlaybackChromeViewModel + chrome overlays), **"Increment U.6b"** (Live adaptation keyboard shortcut semantics; DefaultPlaybackActionRouter consumers), **"Increment U.7"** (Error taxonomy + toast system; ToastManager + LocalizedCopy + UserFacingError), **"Increment U.8"** (Settings panel; SettingsViewModel + per-section sub-views), **"Increment U.9"** (Accessibility pass; AccessibilityState + AccessibilityLabels), **"Increment U.10"** (Spotify URLProtocol race fix; SpotifyConnectionViewModel test serialisation), **"Increment U.11"** (Spotify OAuth; SpotifyConnectionViewModel state machine + AppleMusicConnectionViewModel parallel), **"Increment U.12"** (= QR.4 — UX dead ends; SettingsStore consolidation + PlaybackChromeViewModel index binding), **"DASH.7"** (Dashboard SwiftUI overlay).

11. **docs/UX_SPEC.md** — canonical UX contract. Read **§3** (six top-level views, one per SessionState), **§6.3** (FirstAudioDetector survival rules — ReadyViewModel consumer), **§7** (in-session chrome + keyboard shortcuts), **§8** (settings panel structure), **§9** (error taxonomy + toast system), **§9.4** (audio-signal silence routing — PlaybackErrorBridge consumer in PlaybackView), **§9.5** (jargon deny-list — LocalizedCopy enforcer). The UX_SPEC is load-bearing for verifying view contracts.

If any of these files do not exist, record the missing reference as a finding and continue with what does exist.

## Hard rules for this phase

1. **No code changes during the audit.** Findings are documented; fixes are separate increments scheduled after the audit publishes. The only file modifications allowed in CA.6 are the new audit document and minor corrections to load-bearing docs (ARCHITECTURE.md / ENGINEERING_PLAN.md / KNOWN_ISSUES.md / CLAUDE.md) that the audit surfaces as drift.

2. **BUG-012-i1 instrumentation files remain read-only.** The eight instrumented files include the two App-layer files **already out of CA.6 scope** (`VisualizerEngine.swift` + `VisualizerEngine+Stems.swift` are in `PhospheneApp/`, not in `Views/` or `ViewModels/`). CA.6 will not naturally encounter them. If a doc-drift correction would require editing one of them, surface for Matt's call before landing.

3. **Evidence-based:** every claim cites a file and line. "X exists at `path/file.swift:NNN`" or "X is referenced but file does not exist." No claims unverified by inspection of the actual source.

4. **`production-orphan` verdicts require a cited grep** (carried forward from CA.2). "X has zero consumers" must be backed by the exact grep command run and a summary of its results. The grep should cover `PhospheneApp/`, `PhospheneEngine/Sources/`, and `PhospheneEngine/Tests/` + `PhospheneAppTests/`. Production-orphan claims without a cited grep will be rejected at closeout.

5. **Pre-grep visibility verification** (carried forward from CA.3 + CA.5). When parallelising file reads via Explore agents, do not trust an agent's "this type is public" / "this method is internal" reports without cross-checking. After receiving each agent's report, run a single visibility grep:

   ```
   grep -nE "^public|^[[:space:]]+public|^internal|^[[:space:]]+internal" PhospheneApp/Views/<file>.swift
   grep -nE "^public|^[[:space:]]+public|^internal|^[[:space:]]+internal" PhospheneApp/ViewModels/<file>.swift
   ```

   Reconcile each agent-claimed public against the grep. CA.6 note: 59 files / 6.9k LoC is **smaller than CA.5's engine-adapter slice** (49 files / 8k LoC); a hybrid direct-read + Explore agent approach is the right default. Direct-read the largest files (`PlaybackView.swift`, `PlaybackChromeViewModel.swift`, `SettingsViewModel.swift`, `DashboardOverlayViewModel.swift`, `SpotifyConnectionViewModel.swift`) and any file > 200 lines; batch the rest across 2–3 parallel Explore agents.

6. **Cross-check the kickoff prompt against `KNOWN_ISSUES.md` as Pass 0** (carried forward from CA.3 + CA.4 + CA.5). Verify every BUG cited in this kickoff against actual status:
   - **BUG-001** — should still be Open (no diagnostic work since CA.5).
   - **BUG-012** — should still be Open (instrumentation in place).
   - **BUG-013** — should still be Open.
   - **BUG-016** — should still be Open (Lumen Mosaic; CA.5 inventoried the App-layer surface but no reproduction yet).
   - **CA.5-FU-2** (LiveAdaptationToastBridge engine-event docstring) — should still be pending (product call awaiting Matt's input).

   If any kickoff claim disagrees with `KNOWN_ISSUES.md`, the audit's first finding is the kickoff staleness.

7. **Sub-scope decision optional but document the choice.** CA.6's 59 files / 6.9k LoC fits in one increment for a single auditor session, so the default is **no sub-scope split**. If the auditor judges that Views/ (47) + ViewModels/ (12) should be split into CA.6a + CA.6b (e.g., based on token budget or session length constraints), document the split in the audit doc's §Scope section before Pass 1 begins. **Do not silently scope-creep.**

8. **Exhaustive within scope.** Every public / internal type, every public / internal method in the chosen scope gets a verdict. Coverage is binary for the scope you commit to, not best-effort.

9. **Stop-and-report criteria** (in addition to the standard CLAUDE.md set):

   - Found a `broken-but-claimed` finding that affects production behavior right now (file as BUG-XXX entry; surface immediately — BUG-015 in CA.4 is the load-bearing precedent).
   - The audit's reading of a ViewModel reveals a plausible BUG-001 (Money 7/4) or BUG-016 (Lumen Mosaic) root cause. Document; do not fix. Cross-link from the BUG entry.
   - The audit reveals a SwiftUI state-contract violation matching Failed Approach #55 (parallel-state-world pattern). File immediately.
   - The audit reveals a flake-class regression beyond the U.10 / U.11 pre-existing set. Document; do not fix.
   - Audit scope is growing beyond the chosen scope. Note the boundary crossing; continue within scope; flag as `boundary-noted` or `boundary-deferred` per the CA.3 convention.
   - Discovered an architectural inconsistency between the View tree and the four prior audits' findings (e.g., a ViewModel that constructs its own `MIRPipeline` instead of injecting the engine's). Surface for Matt.
   - The audit format is producing low-value output. Pause, redesign before continuing.

10. **Closeout report cites the audit document, not the audit's findings.** The audit document IS the deliverable.

## Scope of CA.6

### Files in scope — App Views + ViewModels (~59 files, ~6,889 LoC)

**PhospheneApp/Views/** — 47 files across 9 subdirectories + root-level:

Root-level Views (~15 files):
- `MetalView.swift` — NSViewRepresentable wrapping MTKView.
- `DebugOverlayView.swift` — Developer debug overlay (`D` key). Bottom-leading SwiftUI surface; raw MIR diagnostics complementary to the top-trailing dashboard cards.
- `FullScreenErrorView.swift`, `NoAudioSignalBadge.swift`, `ShortcutHelpOverlayView.swift`, plus per-state and shared widget views.

Connecting/ (1 file):
- `ConnectingView.swift` — `.connecting` state per UX_SPEC §3; per-connector spinner + cancel CTA. QR.4 / U.3.

Dashboard/ (5 files) — DASH.7 / D-088 / D-089 surface:
- `DashboardOverlayView.swift` — Top-trailing single panel; `DarkVibrancyView` + `Color.surface` tint @ 0.96α + 1 px border stroke + `.environment(\.colorScheme, .dark)` lock.
- `DashboardCardView.swift` — Per-card typographic section; Clash Display Medium @ 15 pt (or system semibold fallback).
- `DashboardRowView.swift` — 4 row variants (`.singleValue` / `.bar` / `.progressBar` / `.timeseries`); inlined `.singleValue` per D-089.
- `DarkVibrancyView.swift` — NSViewRepresentable wrapping NSVisualEffectView (`.vibrantDark` + `.hudWindow`).
- Plus one helper / state file.

Ended/ (1 file):
- `EndedView.swift` — `.ended` state; trackCount + sessionDuration + onStartNewSession + onOpenSessionsFolder. QR.4 / U.5c follow-up.

Idle/ (1 file):
- `IdleView.swift` — `.idle` state; Connect-a-playlist sheet CTA + Start-listening-now ad-hoc CTA. U.3.

Onboarding/ (2 files):
- `PermissionOnboardingView.swift` — Screen-capture permission explainer + "Open System Settings" CTA. U.2.
- `PhotosensitivityNoticeView.swift` — One-time photosensitivity sheet on IdleView first appearance. U.2.

Playback/ (~6 files):
- `PlaybackView.swift` — `.playing` state; the load-bearing center. Full-bleed MetalView + preset badge + NoAudioSignalBadge + DebugOverlayView + DashboardOverlayView + keyboard shortcuts. Owns CaptureModeSwitchCoordinator, DisplayChangeCoordinator, NetworkRecoveryCoordinator, FullscreenObserver, PlaybackKeyMonitor, MultiDisplayToastBridge, PlaybackErrorBridge, LiveAdaptationToastBridge as `@State`. Failed Approach #55 regression-locked here (D-091 / `SettingsStoreEnvironmentRegressionTests`).
- `PlaybackChromeView.swift` (or similar — the in-session chrome surface that PlaybackChromeViewModel drives).
- `PlanPreviewView.swift` — Plan-preview overlay (`⌘P` or similar). U.6b.
- `ShortcutHelpOverlayView.swift` — Keyboard-shortcut help table. UX_SPEC §7.7.
- Plus chrome subviews and badges.

Preparation/ (1 file):
- `PreparationProgressView.swift` — `.preparing` state; per-track status + partial-ready CTA. U.4.

Ready/ (1 file):
- `ReadyView.swift` — `.ready` state; "Press play in your music app" + first-audio autodetect. U.5.

Settings/ (~10 files) — U.8 panel:
- `SettingsView.swift` — Top-level settings sheet.
- Per-section sub-views (Audio / Visuals / Diagnostics / Onboarding / Spotify) — likely 5–8 sub-views.
- `SourceAppPicker.swift` — `.specificApp` capture-mode source app picker.

ConnectorPicker (3 files):
- `ConnectorType.swift` (enum) — `.appleMusic / .spotify / .localFolder`.
- `ConnectorTileView.swift` — Reusable tile.
- `ConnectorPickerView.swift` — NavigationStack in sheet; three tiles.
- `AppleMusicConnectionView.swift`, `SpotifyConnectionView.swift` — per-connector connection flows.

**PhospheneApp/ViewModels/** — 12 files:

- `SessionStateViewModel.swift` — `@MainActor ObservableObject` bridging `SessionManager.state` into SwiftUI. Also surfaces `reduceMotion` from `accessibilityState`.
- `ConnectorPickerViewModel.swift` — `@MainActor ObservableObject`; NSWorkspace observers (`nonisolated(unsafe)`) for Apple Music launch/terminate; **250 ms debounce**. U.3.
- `AppleMusicConnectionViewModel.swift` — State machine (`.idle / .connecting / .noCurrentPlaylist / .notRunning / .permissionDenied / .error / .connected`); 2 s auto-retry via `DelayProviding`. U.3.
- `SpotifyConnectionViewModel.swift` — State machine (`.empty / .parsing / .preview / .rejectedKind / .invalid / .rateLimited / .notFound / .error`); **300 ms debounce**; `[2s, 5s, 15s]` rate-limit retry sequence. U.3 + U.11.
- `PreparationErrorViewModel.swift` — Network reachability error surface during `.preparing`. U.4.
- `PreparationProgressViewModel.swift` — Per-track preparation status + ETA via PreparationETAEstimator. U.4.
- `ReadyViewModel.swift` — First-audio detection via FirstAudioDetector. U.5.
- `EndSessionConfirmViewModel.swift` — End-session confirmation flow.
- `PlanPreviewViewModel.swift` — Plan-preview state + `regeneratePlan(lockedTracks:lockedPresets:)` closure consumer. U.6b.
- `PlaybackChromeViewModel.swift` — In-session chrome state. **D-091 / QR.4**: subscribes to engine's `currentTrackIndex` publisher (no lowercased title+artist string match per Failed Approach #56). Subscribes to `livePlannedSession` publisher. Has `overlayAutoHides_afterDelay()` test that flakes under parallel execution per U.11.
- `SettingsViewModel.swift` — Settings panel state; consumes SettingsStore + PresetScoringContextProvider. U.8.
- `ToastManager.swift` — Toast queue manager. Up to 3 visible simultaneously. `autoDismiss_afterDuration()` test that flakes under parallel execution per U.11.

### Boundary surfaces (in scope, with annotation)

- **View ↔ App-Service.** PlaybackView owns CaptureModeSwitchCoordinator, DisplayChangeCoordinator, NetworkRecoveryCoordinator, FullscreenObserver, PlaybackKeyMonitor, MultiDisplayToastBridge, PlaybackErrorBridge, LiveAdaptationToastBridge as `@State`. PreparationProgressView owns NetworkRecoveryCoordinator. CA.5 audited the Service classes; CA.6 audits the View-side ownership patterns (lifecycle, init args, weak refs).

- **ViewModel ↔ VisualizerEngine.** PlaybackChromeViewModel binds to multiple engine publishers via `Publisher.eraseToAnyPublisher()` arguments passed from ContentView. DashboardOverlayViewModel binds to `engine.$dashboardSnapshot`. SettingsViewModel reads SettingsStore + writes through PresetScoringContextProvider. SessionStateViewModel binds to `sessionManager.$state` + `accessibilityState`. CA.5 audited the engine-side publishers; CA.6 audits the consumer-side subscription chains.

- **ViewModel ↔ ViewModel.** SessionStateViewModel feeds the routing layer; PlaybackChromeViewModel + DashboardOverlayViewModel run during `.playing`; ReadyViewModel only during `.ready`; PreparationProgressViewModel + PreparationErrorViewModel during `.preparing`. Verify no ViewModel illegally outlives its state.

- **ViewModel ↔ SettingsStore.** Multiple ViewModels read SettingsStore via `@EnvironmentObject` (per D-091; Failed Approach #55 regression-locked). Verify no `@StateObject SettingsStore()` reintroductions.

- **View ↔ Engine.** ContentView injects `engine` as `@EnvironmentObject`; PlaybackView, ReadyView, EndedView read it. MetalView is the NSViewRepresentable for the MTKView the engine renders into. Verify `engine.startAudio()` is called on PlaybackView appear, not earlier (per `VisualizerEngine+PublicAPI.startAudio`).

- **View ↔ UX_SPEC.** Each of the six top-level views has an `accessibilityIdentifier` per UX_SPEC §3 (e.g., `phosphene.view.playing`). Verify presence on each.

- **View ↔ AccessibilityLabels.** Connector tiles + track info cards + toasts use `AccessibilityLabels.*` factory methods per U.9. Verify VoiceOver label coverage.

### Explicit exclusions (out of CA.6 scope)

- **`PhospheneApp/` engine-adapter slice** — CA.5 covered all 49 files (top-level + Services + Permissions + Models).
- **`PhospheneEngine/Sources/Renderer/`** — CA-Renderer (later).
- **`PhospheneEngine/Sources/Audio/`** — CA-Audio (later).
- **`PhospheneEngine/Sources/Presets/`** per-preset Metal shaders + state — CA-Presets (later).
- **`PhospheneEngine/Sources/Shared/`** — deferred.
- **`PhospheneAppTests/`** — read freely for test discriminators, but audit verdicts apply to production code, not tests.

If something in the boundary surfaces seems important enough that the audit's value is reduced without it, note the gap and continue. Do not expand scope.

## Methodology

The methodology is the same as CA.5 with no new additions — the format is stable. Quick recap:

### Pass 0 — Kickoff cross-check + sub-scope decision

Before reading any source file:

1. **BUG cross-check.** Verify every BUG cited in this kickoff against `docs/QUALITY/KNOWN_ISSUES.md` (BUG-001, BUG-012, BUG-013, BUG-016 — all should be Open; CA.5-FU-2 should still be pending). If any kickoff claim disagrees, file the disagreement as Finding #1.

2. **Sub-scope decision.** Default: no sub-scope split (59 files / 6.9k LoC fits cleanly). State the chosen scope explicitly in the audit doc's §Scope section before Pass 1 begins.

3. **Verify CA.5-FU-2 + CA.1-FU-1 supersede status.** CA.5 left two follow-ups pending: CA.5-FU-2 (LiveAdaptationToastBridge engine-event docstring product call) and the CA.1-FU-1 supersede doc-edit. If either has landed since CA.5 closed, note in the audit doc.

### Pass 1 — Inventory + verdict assignment

For each file in scope, produce:

1. **File summary** — one paragraph: what this file owns; the kind of work it does.
2. **Public / internal surface** — every public / internal type and every public / internal method, with brief signatures.
3. **Documented features** — comment headers, MARK sections, doc-comments. Quote verbatim where the claim matters.
4. **Notable internal types / private members** if load-bearing (e.g., `@Published` properties, `@State` storage, Combine subscriptions).
5. **File-level constants / tuning values** with names and values (e.g., `debounce: TimeInterval = 0.3`, `autoDismissDuration: TimeInterval = 4`, retry-sequence arrays).
6. **Any code-level TODOs / FIXMEs / placeholder branches.**

**Read strategy:** 59 files at ~115 LoC average is approachable. Direct-read the **largest files** (estimate: `PlaybackView.swift` ~300+ lines; `PlaybackChromeViewModel.swift` ~200+ lines; `SettingsViewModel.swift` ~200+ lines; `DashboardOverlayViewModel.swift` ~150 lines; `SpotifyConnectionViewModel.swift` ~150 lines; `AppleMusicConnectionViewModel.swift` ~120 lines). Batch the rest across 2–3 parallel Explore agents (e.g., "Views/Settings + Views/Onboarding + Views/Idle + Views/Connecting", "Views/Playback + Views/Dashboard chrome", "Views root-level + Views/Ended + Views/Ready + Views/Preparation").

After each agent's report, run the visibility verification grep:

```
grep -nE "^public|^[[:space:]]+public|^internal|^[[:space:]]+internal" PhospheneApp/Views/<file>.swift
grep -nE "^public|^[[:space:]]+public|^internal|^[[:space:]]+internal" PhospheneApp/ViewModels/<file>.swift
```

Then for each capability, **trace consumers via grep**:
- `grep -rn "TypeName" PhospheneApp PhospheneAppTests PhospheneEngine/Sources PhospheneEngine/Tests` — type usage.
- `grep -rn "\.functionName(" …` — call sites.
- `grep -rn ": ProtocolName" …` — conformances.
- For SwiftUI view types: `grep -rn "TypeName(" …` — instantiation sites.
- For types referenced only in tests: note as test-only (different verdict than production).

Record per capability: production consumers, test consumers, no consumers. For any `production-orphan` candidate, the **cited grep command + result count is mandatory**.

**Cross-reference each capability against the load-bearing docs.** Record: claimed in docs (yes/no, citations), doc claim aligned with code (yes/no, divergence noted), documented as planned-but-not-built (yes/no).

**Behaviour validation:** App-layer has a substantial test surface. Key discriminators by domain:

- `PlaybackChromeIndexBindingTests` — D-091 / QR.4 plan-index propagation.
- `LiveAdaptationToastBridgeTests` — U.6 Part C.
- `DefaultPlaybackActionRouterTests` — D-050 / U.6b.
- `CaptureModeSwitchCoordinatorTests` — D-061 grace window.
- `NetworkRecoveryCoordinatorTests` — Network restoration.
- `SpotifyConnectionViewModelTests` — U.10 / U.11.
- `AppleMusicConnectionViewModelTests` — U.3 / U.11.
- `ToastManagerTests` — U.7 error taxonomy.
- `PreparationProgressViewModelTests` — U.4.
- `SettingsViewModelTests` — U.8.
- `ReadyViewTimeoutIntegrationTests` — U.5.

Use them as the discriminators they are. **Particular attention**: verify each suite that uses URLProtocol stubs has the `@Suite(.serialized)` annotation per CLAUDE.md U.10. Verify debounce timing margins match U.11 (700 ms for 300 ms debounce; 250–400 ms for connect/login).

**Assign verdict per capability** (definitions carried forward from CA.5):

| Verdict | Meaning |
|---|---|
| `production-active` | Consumed by production code; doc claims match code behavior; behavior validated. |
| `production-orphan` | Consumed nowhere in production code (test consumers only OR no consumers). Requires cited grep. |
| `dead` | Confirmed dead — no consumers anywhere; safe to delete. |
| `stub` | Exists as signature; body empty / default / unimplemented. |
| `documented-but-missing` | Docs claim it exists; code does not. |
| `built-but-undocumented` | Code has it; no doc references it. |
| `broken-but-claimed` | Docs claim it works; runtime behavior contradicts. File a BUG-XXX entry immediately. |
| `unverified-claim` | Consumed; docs claim correctness; no evidence of correctness. |
| `boundary-noted` | Lives at a subsystem boundary; verdict is complete (no future re-audit obligation). |
| `boundary-deferred` | Lives at a subsystem boundary; full verdict requires the other subsystem's audit. |

### Pass 2 — Doc-drift triangulation

Once verdicts are assigned, scan load-bearing docs for additional drift:

- Does **ARCHITECTURE.md §UI Layer** (lines 220–242) accurately describe the current view tree?
- Does **ARCHITECTURE.md §Module Map PhospheneApp/Views/** block list every file?
- Does **ARCHITECTURE.md §Module Map PhospheneApp/ViewModels/** block list every file? (Pre-CA.6: 4 of 12.)
- Are tuning constants quoted in docs identical to the code's values? (Debounce constants per U.11, retry sequences, autoDismiss durations, throttle interval `33ms`, etc.)
- Does any architectural claim describe a view path that no longer exists? Was retired? Was renamed?
- Do any decisions in DECISIONS.md reference view-type names that have moved or been renamed?
- Does CLAUDE.md accurately describe the SwiftUI state-contract rules? (D-091 / Failed Approach #55 enforcement.)

Record drift findings as a separate cross-reference section in the audit doc.

## Output structure (template — extends CA.5 with View-layer-specific sections)

Output file: `docs/CAPABILITY_REGISTRY/APP_VIEWS.md` (matching the CA.5-FU-4 registered ID — alternative: append to `APP.md` as a §CA.6 Appendix if the auditor's read suggests the two halves of the App layer are inseparable).

```
# Capability Registry — App Layer (Views + ViewModels)

**Audit increment:** CA.6
**Date:** 2026-05-XX
**Auditor:** Claude (session-driven, read-only)
**Scope:** PhospheneApp/Views/ + PhospheneApp/ViewModels/ (presentation slice; the engine-adapter slice was covered by CA.5)
**Methodology:** Phase CA scoping document (CA.6 kickoff).
**Reads relied on:** [list of docs read]

## Summary
[One paragraph: capability counts per verdict, the highest-priority findings, follow-up count, kickoff-vs-KNOWN_ISSUES cross-check result.]
[Markdown table of verdict counts.]

## Sub-scope decision
[State the scope chosen at Pass 0 explicitly. If different from this kickoff's recommendation (default = no split), justify.]

## Findings by verdict
### broken-but-claimed (BUG entries filed)
### documented-but-missing
### unverified-claim
### production-orphan
### dead, stub, built-but-undocumented, boundary-noted, boundary-deferred
### production-active
[Per-finding citations as CA.5 template.]

## Per-file capability index
[One section per file or per family. Consolidation allowed if verdicts heavily concentrate in production-active.]

## Verification of PlaybackChromeViewModel BUG-015 / D-091 consumer chain (CA.6-specific)
[Required section. CA.5 verified the engine-side wire + the @Published currentTrackIndex publisher. CA.6 verifies the consumer chain:
- PlaybackChromeViewModel subscribes to currentTrackIndexPublisher passed from ContentView
- The subscription chain does not introduce its own lowercased title+artist string match (Failed Approach #56 regression check)
- PlaybackChromeIndexBindingTests' three assertions still hold against current code
State whether the consumer chain matches the D-091 design notes byte-for-byte. Any divergence is a real finding.]

## Verification of D-091 single-SettingsStore enforcement in View tree (CA.6-specific)
[Required section. CA.5 verified the engine-adapter side. CA.6 verifies every View consumes SettingsStore via @EnvironmentObject (not @StateObject), per Failed Approach #55 / D-091. SettingsStoreEnvironmentRegressionTests' source-presence assertion on PlaybackView.swift is the regression gate; verify it still holds.]

## Verification of DASH.7 dashboard surface (CA.6-specific)
[Required section. Verify:
- DashboardOverlayViewModel subscribes to engine.$dashboardSnapshot with .throttle(for: .milliseconds(33))
- ingestForTest(_:) test seam bypasses the throttled subscription correctly
- DASH.7.2 dark-vibrancy lock per D-089 is in place (DarkVibrancyView is the panel backdrop; 0.96α surface tint; 1px border stroke; .environment(\.colorScheme, .dark))
- Clash Display Medium 15pt + Epilogue Medium 11pt typography per D-088 with system-font fallback]

## Verification of U.10 / U.11 timing-margin compliance (CA.6-specific)
[Required section. The post-2026-05-21 `[test-flake]` task chip widened timing margins across 9 App-layer test files. CA.6 audits whether each widened margin matches U.11's documented baseline:
- 700 ms wait for 300 ms debounce
- 250–400 ms wait for connect/login async actor-hop completions
- @Suite(.serialized) on URLProtocol-stub-using suites per U.10

For each of the 9 files (AppleMusicConnectionViewModelTests, LiveAdaptationToastBridgeTests, NetworkRecoveryCoordinatorTests, PlaybackChromeViewModelTests, ReadyViewModelTests, ReadyViewTimeoutIntegrationTests, SpotifyConnectionViewModelTests, SpotifyOAuthTokenProviderTests, ToastManagerTests), document: (a) the pre-chip margin value, (b) the post-chip margin value, (c) the U.11-documented minimum, (d) verdict — `production-active` if post-chip ≥ minimum, `unverified-claim` if post-chip < minimum but the chip claimed compliance, `production-orphan` if a margin that should have been widened wasn't. Document, do not fix.]

## Cross-references
### Updates needed in CLAUDE.md
### Updates needed in ARCHITECTURE.md
### Updates needed in ENGINEERING_PLAN.md
### Updates needed in DECISIONS.md
### New BUG entries
### KNOWN_ISSUES.md sweep

## Follow-up Backlog
| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA.6-FU-1** | … | … | … | … |
| **CA.6-FU-2** | … | … | … | … |

## Approach validation
[Critique of methodology. What worked? What didn't? Recommended changes for CA-Renderer / CA-Audio / CA-Presets.]
```

## File the artifact + cross-references

Per CLAUDE.md increment closeout protocol:

- The audit document is the primary deliverable.
- Any `broken-but-claimed` findings get **BUG-XXX entries in `KNOWN_ISSUES.md` immediately**. The next available BUG number is **BUG-017** (BUG-016 was filed 2026-05-21; nothing filed since).
- `ENGINEERING_PLAN.md` gets an entry in **Recently Completed** (CA.6 ✅) plus the **CA.6 row** in the Phase CA section.
- `CLAUDE.md` / `ARCHITECTURE.md` drift findings are corrected in this same increment.

Commit shape (matches CA.1 / CA.2 / CA.3 / CA.4 / CA.5 — two commits, doc-only):

- `[CA.6] App Views audit: capability registry + findings`
- `[CA.6] ARCHITECTURE.md / ENGINEERING_PLAN.md / CLAUDE.md: doc-drift corrections from App Views audit` (if any)

## Done-when

CA.6 closes when:

- [ ] `docs/CAPABILITY_REGISTRY/APP_VIEWS.md` published (or APP.md §CA.6 Appendix if the auditor chose that route).
- [ ] Sub-scope decision documented explicitly (default: no split).
- [ ] Every public / internal capability in the chosen scope has a verdict.
- [ ] Every `production-orphan` verdict cites the grep command used.
- [ ] Every Explore-agent-claimed public / internal symbol was cross-checked against a visibility grep.
- [ ] Kickoff-vs-KNOWN_ISSUES.md cross-check ran as Pass 0 step 1.
- [ ] Every non-`production-active` finding either ships a doc-fix in this increment OR is registered as a CA.6-FU-N follow-up.
- [ ] All `broken-but-claimed` findings have BUG entries in `KNOWN_ISSUES.md`.
- [ ] PlaybackChromeViewModel BUG-015 / D-091 consumer chain verified in §Verification-of-PlaybackChromeViewModel-consumer-chain section (CA.6-required).
- [ ] D-091 single-SettingsStore enforcement verified in §Verification-of-D-091-enforcement section (CA.6-required).
- [ ] DASH.7 dashboard surface verified in §Verification-of-DASH.7-surface section (CA.6-required).
- [ ] U.10 / U.11 timing-margin compliance verified in §Verification-of-U.10-U.11-compliance section (CA.6-required).
- [ ] Drift corrections to load-bearing docs landed.
- [ ] "Approach validation" section produces an honest critique of whether this format should continue into CA-Renderer / CA-Audio / CA-Presets.
- [ ] All commits land on `main` (local). Push only on Matt's explicit approval.
- [ ] No edits to BUG-012-i1 instrumented files (trivially satisfied — none are in CA.6 scope).

## After CA.6 lands

Surface to Matt:

- The audit summary (broken-but-claimed count, documented-but-missing count, production-orphan count, follow-up count).
- The verdict on the PlaybackChromeViewModel BUG-015 / D-091 consumer chain — matches design notes or any divergence found.
- The verdict on D-091 single-SettingsStore enforcement across the View tree.
- The verdict on the DASH.7 dashboard surface against D-088 / D-089.
- The verdict on U.10 / U.11 timing-margin compliance across the five active pre-existing flakes — any that need the `@Suite(.serialized)` annotation or wider timing margins.
- Any BUG-001-adjacent findings (Money 7/4 stays REACTIVE) that future diagnosis should weigh.
- Any BUG-016-adjacent findings (Lumen Mosaic in the keyboard-cycling code path or the PlaybackView's preset-name observer chain).
- Any new CA.6-FU items registered.
- The recommended next subsystem for CA.7 — likely **CA-Renderer** (the largest unaudited engine module, ~50+ files, including the FrameBudgetManager + RenderPipeline + MLDispatchScheduler cluster CA.5 boundary-noted). Alternative: CA-Audio (smaller; closes the AudioInputRouter + SilenceDetector + StreamingMetadata + MetadataPreFetcher surface CA.3 already touched).

Do not start CA.7 in the same session.

## Failure modes to watch for

Specifically for View-layer-shaped audit work:

1. **Treating PlaybackView as a black box.** PlaybackView is the load-bearing center of the `.playing` state and owns 8 `@State` services. Every keyboard-shortcut registration, every Combine subscription, every observer wiring is per-line-traceable. The audit's job is to verify the implementation matches the load-bearing docs: D-061 (long-session resilience coordinators), D-091 (single SettingsStore + EnvironmentObject only), D-050 / U.6b (PlaybackActionRouter wiring), Failed Approach #55 (no `@StateObject SettingsStore()`).

2. **Trivial-finding inflation across 59 files.** Most subviews will be `production-active` with little drama. The depth targets are: **PlaybackView** (load-bearing chrome owner), **PlaybackChromeViewModel** (D-091 / QR.4 plan-index consumer), **SettingsViewModel** + **SettingsView** subsections (U.8 + D-091 consolidation contract), **DashboardOverlayViewModel** + Dashboard/ family (DASH.7 / D-088 / D-089), **SpotifyConnectionViewModel** + **AppleMusicConnectionViewModel** (U.3 / U.10 / U.11), **ToastManager** (U.7 / U.6 Part C condition-ID semantics), **ConnectorPickerViewModel** (NSWorkspace observer pattern), **MetalView** (NSViewRepresentable contract). Smaller files (per-state container views, single-purpose connector tiles, badges) get surface-level `production-active` rows.

3. **SwiftUI state-contract violation patterns.** Re-grep for `@StateObject.*SettingsStore` per CA.5 (should return only `PhospheneApp.swift:25` + regression-test references). Look for any `@StateObject` re-instantiation of any other engine type that should be `@EnvironmentObject` (Failed Approach #55-shaped). Look for any `@Published` write from a non-MainActor context inside a ViewModel (potential threading violation — most ViewModels are `@MainActor`). Look for any Combine subscription not stored in an `AnyCancellable` (potential subscription leak).

4. **U.10 / U.11 timing-margin verification (post-flake-chip).** The 2026-05-21 `[test-flake]` task chip widened margins across 9 App-layer test files. Verify the new margins against U.11:
   - **Does the suite use URLProtocol stubs?** If yes, verify `@Suite(.serialized)` annotation.
   - **Does the suite wait on a debounce?** Verify wait ≥ 700 ms for 300 ms debounce, 250–400 ms for connect/login completions.
   - **Does the suite use `Task.sleep`?** Verify the sleep is via `DelayProviding` (testability seam), not hardcoded `try? await Task.sleep(for: .seconds(0.x))`.

   File any widened margin that's still below the U.11 minimum as `unverified-claim` (the chip claimed compliance but the margin doesn't match). File any margin that should have been widened but wasn't as `production-orphan` (the rule has no enforcing test). Document, do not re-widen.

5. **D-091 currentTrackIndex consumer chain.** CA.5 verified the producer side. CA.6 must verify:
   - `PlaybackChromeViewModel` subscribes to the `currentTrackIndexPublisher` argument passed from `ContentView.playbackView` (line 85 of post-CA.5 ContentView.swift).
   - The subscription stores its result in a `@Published` field (or maintains its own observable state) — NOT in a derived computed property doing lowercased string matching.
   - `PlaybackChromeIndexBindingTests.test_titleCaseMismatch_doesNotChangeIndex` is the load-bearing regression gate; verify it still passes against current code.

6. **MetalView NSViewRepresentable contract.** MetalView wraps MTKView. The `RenderPipeline` was constructed in `VisualizerEngine.init` per CA.5. MetalView's job is purely to host the MTKView for the engine's rendering — verify the NSViewRepresentable's `makeNSView` / `updateNSView` don't accidentally re-construct any pipeline state on view updates (that would re-allocate on every redraw — performance regression).

7. **DASH.7 throttle constant verification.** `DashboardOverlayViewModel` uses `.throttle(for: .milliseconds(33))` per ARCHITECTURE.md §UI Layer line 398. Verify the literal `33` is the current value. Any drift to a different value would change the dashboard refresh rate from ~30 Hz to whatever the new value implies.

8. **DASH.7.2 dark-vibrancy lock verification.** Per D-089 + ARCHITECTURE.md §Module Map Views/Dashboard/ block, the dashboard panel must:
   - Use `DarkVibrancyView` (NSViewRepresentable wrapping `NSVisualEffectView` with `.vibrantDark` + `.hudWindow`) as the backdrop.
   - Apply `Color.surface` tint at **0.96α**.
   - Have a **1 px `border` stroke**.
   - Lock `.environment(\.colorScheme, .dark)`.
   
   Verify every one of these is present in `DashboardOverlayView.swift`. Any single one missing is a `unverified-claim` finding.

9. **Citing without verifying.** Same as CA.1–CA.5's rule. Every claim is evidence-backed with a file:line or a doc:line.

10. **Producing structure as a substitute for substance.** Headers must be backed by content. Empty buckets should be said-empty, not pretended-incomplete.

11. **Scope creep into App-engine-adapter slice (CA.5 territory).** When the audit's reading of a View surfaces an engine-side touchpoint (e.g., a publisher signature change), flag as `boundary-noted` (CA.5 already audited) and proceed. Do not silently expand back into Services/ or Permissions/ or Models/.

12. **Scope creep into engine modules (CA-Renderer / CA-Audio / CA-Presets territory).** MetalView wraps MTKView — but the MTKView's rendering pipeline is CA-Renderer scope. If the audit's reading of MetalView surfaces a Renderer-internal touchpoint, flag as `boundary-deferred` to CA-Renderer.

## Status on entry

- **Branch:** `main`. CA.0 + CA.1 + CA.2 + CA.3 + CA.4 + CA.5 + CA.5-FU-1 + CA.5-FU-3 + BUG-015 fix + BUG-016 filing + a parallel `[lint]` SwiftLint baseline restoration chip + a parallel `[test-flake]` U.10/U.11 timing-margin widening chip have all landed and pushed to `origin/main` as of 2026-05-21. Recent commits (most-recent first):
  ```
  f2cc75ab [test-flake] RELEASE_NOTES_DEV: log the engine fixture restore + cancel widening
  76e250dc [docs] RUNBOOK: document worktree fixture-restore step
  ca6afb4b [test-flake] SessionManagerCancelTests: widen 3s → 10s polling deadline
  da2691ad [test-env] RELEASE_NOTES_DEV: log the Spotify clientID + ReadyViewModel cleanup
  7f5b13ff [test-flake] ReadyViewModelTests: widen 600ms → 1500ms (3 siblings)
  0f26302f [test-env] SpotifyOAuthTokenProvider: inject clientID for tests
  c8fbba2e [test-flake] RELEASE_NOTES_DEV: log the parallel-execution flake cleanup
  b9838ee3 [test-flake] App: widen 7 files of parallel-execution timing budgets
  3814c422 [test-flake] Engine: widen 4 timing budgets, mark MemoryReporter intermittent
  7936296c [lint] FerrofluidMesh: address init disable TODO — extract 4 helpers
  cfbbc505 [lint] RELEASE_NOTES_DEV: log the 18→0 baseline restoration
  b3d748f3 [lint] SessionRecorder: split recordStemSeparation to +Stems extension
  f575f8ac [lint] SpectralCartographText: function_parameter_count disables
  71e0e526 [lint] FerrofluidMesh: mechanical formatting + init disables
  b8952fda [CA.5-FU-3] Rename MusicKitFetcher.swift → ITunesSearchFetcher.swift
  688095d4 [CA.5-FU-1] MultiDisplayToastBridge: delete dead coalesceTask + pendingEvents fields
  b2c3f63e [CA.5] ARCHITECTURE.md / ENGINEERING_PLAN.md: doc-drift corrections from App audit
  7cc1fe76 [CA.5] App audit: capability registry + findings
  ```
  Local + remote `main` are in sync. Working tree clean apart from documented `default.profraw` build artifact.
- **SwiftLint baseline: 0 violations across the entire codebase** (was 18 at CA.5 closeout — the `[lint]` chip cleared the engine-side warnings in `FerrofluidMesh.swift`, `SpectralCartographText.swift`, and `SessionRecorder.swift`). Any violation in active source paths is a regression per `project_swiftlint_baseline.md` memory note. CA.6 should remain at 0.
- **9 App-layer test files have widened timing margins** per the 2026-05-21 `[test-flake]` chip (see commit `b9838ee3` + `7f5b13ff` + `ca6afb4b`). The chip claimed compliance with U.11's documented baseline. CA.6's required §Verification-of-U.10-U.11-compliance section audits whether each widened margin actually matches U.11.
- **`SessionRecorder+Stems.swift` is new** (post-`[lint]` chip; commit `b3d748f3`). The split moved `recordStemSeparation` out of `SessionRecorder.swift` to satisfy the `file_length` rule. The file lives in `PhospheneEngine/Sources/Shared/` — engine-side, NOT in CA.6 scope. Note in passing.
- **BUG-012** is Open. BUG-012-i1 instrumentation in place. Step 2 (diagnosis) waits on a reproduction. CA.6 does NOT naturally encounter the 8 instrumented files (none are in `PhospheneApp/Views/` or `PhospheneApp/ViewModels/`).
- **BUG-016** is Open. Lumen Mosaic symptom uncharacterised; awaiting concrete reproduction. CA.6 may surface an additional candidate failure mode at the View-layer level (e.g., `PlaybackView`'s keyboard cycling, the preset-name banner subscriber). Document; do not fix.
- **BUG-001** is Open. The audit may surface ViewModel findings relevant to its diagnosis; document, do not fix.
- **CA.5-FU-2** (LiveAdaptationToastBridge engine-event docstring) — pending Matt's product call. CA.6 will encounter the bridge's consumers via `DefaultPlaybackActionRouter`; verify nothing changed.
- **CA.1-FU-1 supersede update** — 2-line doc edit; still pending. CA.6 should NOT do this edit (out of scope) but can note it in the audit's §Follow-up Backlog as "ready to land — bundle with next CA-adjacent commit."
- **No CA.6 code or audit has landed.** This is the kickoff.

## Sign-off

This prompt is the canonical entry point for Increment CA.6. The Phase CA wider scoping (what subsystem comes next after CA.6, the master `docs/CAPABILITY_REGISTRY.md` index file) continues to be one-increment-at-a-time per the CA.0 scoping decision.

If you find the prompt is wrong or stale during the audit, update the prompt before continuing — do not work against a brief you know to be incorrect.

— Matt + Claude (2026-05-21 design session, post-CA.5 closeout)
