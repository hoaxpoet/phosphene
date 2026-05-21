# Capability Registry — App Layer (engine-adapter slice)

**Audit increment:** CA.5
**Date:** 2026-05-21
**Auditor:** Claude (session-driven, read-only)
**Scope:** `PhospheneApp/` engine-adapter slice — 49 Swift files, 7,975 LoC. The Views (47 files) + ViewModels (12 files) presentation slice is deferred to CA.6 per the Pass 0 sub-scope decision below.
**Methodology:** Phase CA scoping document — CA.5 kickoff in commit `54357118`.
**Reads relied on:** `CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/CAPABILITY_REGISTRY/DSP_MIR.md` (CA.1), `docs/CAPABILITY_REGISTRY/ML.md` (CA.2), `docs/CAPABILITY_REGISTRY/SESSION.md` (CA.3), `docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md` (CA.4), `docs/DECISIONS.md` (D-046, D-049, D-050, D-052, D-053, D-054, D-057, D-058, D-061, D-069, D-070, D-074, D-079, D-080, D-088, D-091, D-095, D-097, D-LM-buffer-slot-8, D-LM-palette-library), `docs/QUALITY/KNOWN_ISSUES.md` (BUG-001, BUG-005, BUG-006, BUG-011, BUG-012, BUG-013, BUG-015, BUG-016), `docs/ENGINEERING_PLAN.md` (Phase U + Phase QR + Phase CA), `docs/UX_SPEC.md`.

---

## Summary

49 file-level entities audited (~8.0k LoC) across the engine-adapter slice of `PhospheneApp/`. The slice is the consumer-side surface for every Orchestrator / Session / DSP / ML / Renderer capability the prior four audits documented. **Headline finding: the just-landed BUG-015 wire is structurally correct.** The App-layer landing of `runOrchestratorLiveUpdate(mir:)`, the lock-guarded `liveTrackPlanIndex` / `lastClassifiedMood` / `orchestratorWireLoggedThisTrack` fields, the once-per-track diagnostic, the off-plan skip path, and the OrchestratorWiringRegressionTests source-presence regression test all match the BUG-015 Resolved-field design notes byte-for-byte. **Zero `broken-but-claimed` findings; zero new BUG entries filed.**

The audit's substantive content sits in the doc-drift cluster (large; same shape as CA.1 / CA.2 / CA.3 / CA.4 found) and two small field-level findings (a `production-orphan` field cluster in `MultiDisplayToastBridge`; a stale file-header docstring in `LiveAdaptationToastBridge`). One additional non-defect surface observation is captured for BUG-016's open diagnosis without proposing a fix.

| Verdict | Count | Notes |
|---|---|---|
| `production-active` | 48 files | Default verdict. Every App-layer engine-adapter file in scope has at least one production consumer; documented behaviour matches code. |
| `production-orphan` | 1 cluster (field-level) | `MultiDisplayToastBridge.coalesceTask: Task<Void, Never>?` + `MultiDisplayToastBridge.pendingEvents: [String] = []` (`MultiDisplayToastBridge.swift:22–23`). Both fields are declared in service of a documented coalescing intent (`// Coalescing: rapid adds/removes within 0.5s produce one toast.` at line 21), but **no consumer of either field exists**. Cited grep below returns only the declaration sites. The handlers `handleAdded` / `handleRemoved` enqueue toasts unconditionally — no coalescing logic was ever wired. Same shape as CA.4-FU-1's `transitionPolicy` field. Registered as CA.5-FU-1. |
| `unverified-claim` | 1 | `LiveAdaptationToastBridge.swift:6` docstring claims "Two observation sources: user actions via PlaybackActionRouter, engine events (currently wired only for UserDefaults flag check and coalescing logic)." Code only routes user-action acks via `emitAck()`. The BUG-015 wire's engine-event downstream consumer logs to `os.Logger` + `session.log` and does not call `emitAck()`. Honest reading: the docstring hedges with "currently wired only for …" so it does not lie, but a future reader could expect engine-event toasts to fire from this bridge. The audit recommends either wiring engine adaptation events through `emitAck()` (post-BUG-015) or rewriting the docstring. Registered as CA.5-FU-2. |
| `broken-but-claimed` | 0 | BUG-015 (the only `broken-but-claimed` finding in scope of the App-layer audit) is already filed AND Resolved 2026-05-21. CA.5 verifies the resolution; see §Verification-of-BUG-015-wire-shape. |
| `documented-but-missing` | 0 | — |
| `built-but-undocumented` | 2 large | (a) `ARCHITECTURE.md §Module Map PhospheneApp/` block lists 12 of 49 engine-adapter files — **37 absent**. Full list under §Cross-references below. Same systemic pattern as CA.1 (DSP/ 6-of-20), CA.2 (ML/ 9-of-16), CA.3 (Session/ 13-of-22), CA.4 (Orchestrator/ 9-of-14). (b) `ARCHITECTURE.md §Module Map Tests/PhospheneApp/` block is **absent entirely** — 60+ test files exist including the load-bearing regression tests `OrchestratorWiringRegressionTests`, `SettingsStoreEnvironmentRegressionTests`, `PlaybackChromeIndexBindingTests`. |
| `stub` | 0 | — |
| `dead` | 0 | (At the file level. The two dead fields in `MultiDisplayToastBridge` are counted under `production-orphan`.) |
| `boundary-noted` | 7 | App ↔ Orchestrator (BUG-015 wire + `DefaultPlaybackActionRouter` + `PresetScoringContextProvider` + scoring-context builders); App ↔ Session (`SessionManager` + `StemCache` + `MetadataPreFetcher` ownership); App ↔ DSP (`MIRPipeline` construction + per-frame consumer); App ↔ ML (`MoodClassifier` + `StemSeparator` + `MLDispatchScheduler` consumption); App ↔ Renderer (`RenderPipeline` + `FrameBudgetManager` + slot-6/7/8 buffer wiring); App ↔ Audio (`AudioInputRouter` + audio-thread → analysis-queue handoff); App ↔ Presets (per-preset state classes + `setMeshPresetTick` closures + slot-binding contract). All boundary verdicts complete. |
| `boundary-deferred` | 0 (new) | — |

**Top findings, ranked.**

1. **BUG-015 wire shape verified clean.** All seven design notes from the Resolved field land in code byte-for-byte: (a) `runOrchestratorLiveUpdate(mir:)` declared at `VisualizerEngine+Orchestrator.swift:287`; (b) called from `VisualizerEngine+Audio.swift:184` at the end of `processAnalysisFrame`; (c) cadence gate `analysisFrameCount % Self.orchestratorWireFrameDivisor == 0` with `orchestratorWireFrameDivisor: Int = 30`; (d) off-plan skip path `if snapshot.hasPlan, snapshot.trackIndex == nil { return }`; (e) `liveTrackPlanIndex` written in `VisualizerEngine+Capture.swift:131` under `orchestratorLock`; (f) `lastClassifiedMood` written in `VisualizerEngine+Audio.swift:432` (`publishMoodResult`) under `orchestratorLock`; (g) `orchestratorWireLoggedThisTrack` reset on track change at `VisualizerEngine+Capture.swift:137`. The once-per-track diagnostic at `VisualizerEngine+Orchestrator.swift:323–331` dual-writes to `sessionRecorder?.log(msg)` AND `logger.info("\(msg)")`. The regression test `PhospheneAppTests/OrchestratorWiringRegressionTests.swift` asserts source-presence via two `@Test` methods that strip comments first (so doc-comment mentions don't satisfy the assertion).

2. **BUG-012-i1 instrumentation intact** in both App-layer instrumented files. `VisualizerEngine.swift:709` (`init`) and `VisualizerEngine.swift:718` (`deinit`) both call `BUG012Probe.recordVisualizerEngineInit()` / `recordVisualizerEngineDeinit()`. `VisualizerEngine+Stems.swift` carries the lifecycle probes at all expected sites (timer entry, no-scheduler path, defer path, `performStemSeparation` enter/exit, `separator.separate` CALL/RETURN, dispatch-ID allocation). 48 `BUG012Probe` references total across the 8 instrumented files; no edits made in this audit per CA.5 Hard Rules.

3. **`MultiDisplayToastBridge.coalesceTask` + `pendingEvents` field-level production-orphan.** Cited grep:
   ```
   $ grep -rn "pendingEvents\|coalesceTask" PhospheneApp/Services/MultiDisplayToastBridge.swift PhospheneAppTests
   PhospheneApp/Services/MultiDisplayToastBridge.swift:22:    private var coalesceTask: Task<Void, Never>?
   PhospheneApp/Services/MultiDisplayToastBridge.swift:23:    private var pendingEvents: [String] = []
   ```
   Only the declaration sites. The line-21 comment "Coalescing: rapid adds/removes within 0.5s produce one toast" describes a behaviour the code does not implement. Registered as CA.5-FU-1.

4. **`LiveAdaptationToastBridge` engine-event path absent at runtime.** The file's top docstring at line 6 claims "engine events (currently wired only for UserDefaults flag check and coalescing logic)." The BUG-015 wire's downstream consumer (`applyLiveUpdate(...)` at `VisualizerEngine+Orchestrator.swift:167`) emits adaptation events via `logger.info(...)` only (line 195) and never calls `emitAck()`. Cited grep:
   ```
   $ grep -rn "emitAck\|toastBridge\." PhospheneApp --include="*.swift"
   PhospheneApp/Services/DefaultPlaybackActionRouter.swift:250: toastBridge?.emitAck("Boosted \(familyName)")
   PhospheneApp/Services/DefaultPlaybackActionRouter.swift:275: toastBridge?.emitAck("Not quite hitting the mark? Try ⌘R to re-plan.")
   …
   PhospheneApp/Services/LiveAdaptationToastBridge.swift:62:    func emitAck(_ message: String) {
   ```
   All 11 `emitAck` call sites live in `DefaultPlaybackActionRouter.swift` (user-action acks). The docstring hedges with "currently wired only for…" so it does not lie, but the gap is undocumented in `ARCHITECTURE.md` or `DECISIONS.md`. Registered as CA.5-FU-2.

5. **ARCHITECTURE.md doc drift cluster.**
   - **§Module Map PhospheneApp/ block** lists `ContentView`, `PhospheneApp`, `VisualizerEngine`, `VisualizerEngine+Audio`, `VisualizerEngine+Stems`, `VisualizerEngine+Presets`, plus 3 `Permissions/` entries (complete) plus 6 `Services/` entries — but 24 `Services/` files and 7 `VisualizerEngine+*` extensions are absent. The 2 `Models/` files (`PhospheneToast.swift`, `SettingsTypes.swift`) have no module-map entries. `MusicKitFetcher.swift` is not listed. Full list of 37 missing entries in §Cross-references.
   - **§Module Map Tests/PhospheneApp/ block** is **absent**. The Tests/ block has entries for Audio / DSP / ML / Renderer / Session / Orchestrator but not App. 60+ App-test files exist.
   - **§UI Layer line 224** says `SessionStateViewModel` "Lives in `PhospheneApp/ViewModels/`." Correct, but the surrounding paragraph claims it's the bridge for `SessionManager.state` only — it also surfaces `reduceMotion` from `accessibilityState` via the `init(sessionManager:accessibilityState:)` signature used at `PhospheneApp.swift:50–53`. Minor description refinement; not blocking.

6. **`MusicKitFetcher.swift` filename drift.** File contains `ITunesSearchFetcher` class with explicit top-comment `// ITunesSearchFetcher — Free, unauthenticated iTunes Search API for genre + duration. No developer account, no tokens, no MusicKit authorization needed.` The filename is misleading. Recommend renaming the file to `ITunesSearchFetcher.swift` to match its contents. Registered as CA.5-FU-3.

7. **BUG-016 App-layer surface inventory (open diagnosis aid; no fix attempted).** Lumen Mosaic's apply path lives **inside** `case .rayMarch:` in `VisualizerEngine+Presets.swift:166–178` — gated on `if desc.name == "Lumen Mosaic"`, not a separate `.lumenMosaic:` case (the kickoff used loose phrasing). The path:
   - Constructs `LumenPatternEngine(device: context.device)` (init can return `nil`; failure logs to `os.Logger` but produces no Lumen-specific session.log line).
   - Binds `engine.patternBuffer` via `pipeline.setDirectPresetFragmentBuffer3(...)` — slot 8 per CLAUDE.md GPU Contract / D-LM-buffer-slot-8 ✓.
   - Wires per-frame tick via `pipeline.setMeshPresetTick { [weak engine] features, stems in engine?.tick(features: features, stems: stems) }`.
   - The per-track palette refresh runs in `VisualizerEngine+Stems.swift:518–567` via `refreshLumenPaletteForTrack(...)` which reads `stemCache?.trackProfile(for: identity)?.mood` (falls back to `(0,0)` mood-space centre when uncached) and calls `LumenMosaicPaletteLibrary.selectPalette(...)`.
   - Reset on preset switch sets `lumenPatternEngine = nil` at line 61 and `pipeline.setDirectPresetFragmentBuffer3(nil)` at line 69.

   **No regression test exercises the Lumen Mosaic App-layer apply path end-to-end** — `LumenPatternEngineTests` covers the GPU struct stride (`568` bytes) only. The audit observes this gap without proposing a fix; the gap is a candidate diagnostic step for BUG-016 once the failure mode is characterised. **Cross-link from BUG-016 to this section.**

8. **`D-091 / Failed Approach #55` enforcement verified clean.** Cited grep:
   ```
   $ grep -rnE "@StateObject.*SettingsStore" PhospheneApp PhospheneAppTests
   PhospheneApp/PhospheneApp.swift:25:    @StateObject private var settingsStore = SettingsStore()
   PhospheneApp/Views/Playback/PlaybackView.swift:52: /// `@StateObject SettingsStore()` here creates a parallel state world —
   PhospheneAppTests/SettingsStoreEnvironmentRegressionTests.swift:42:        @StateObject var shadowStore = SettingsStore(...)
   PhospheneAppTests/SettingsStoreEnvironmentRegressionTests.swift:148: #expect(!src.contains("@StateObject private var settingsStore = SettingsStore()"),
   ```
   One legitimate construction in `PhospheneApp.swift:25` (the app-entry single-instance store, per D-091). All other hits are: comments warning against the bad pattern (`PlaybackView.swift:52`), or the regression-test's shadow probe + source-presence assertion. No production code re-introduces the dead pattern.

9. **`@Suite(.serialized)` annotation present** on the only URLProtocol-stub-using App test (`PhospheneAppTests/SpotifyOAuthTokenProviderTests.swift:98 — @Suite("SpotifyOAuthTokenProvider", .serialized)`). U.10 rule satisfied.

10. **SwiftLint baseline:** zero warnings in `PhospheneApp/` (18 warnings remain in `PhospheneEngine/`: `Presets/FerrofluidOcean/FerrofluidMesh.swift`, `Presets/SpectralCartographText.swift`, `Shared/SessionRecorder.swift` — all out of CA.5 scope). App-layer is SwiftLint-clean. The unrelated pending SwiftLint cleanup chip is engine-side, not App.

**Three follow-up items registered in [§Follow-up Backlog](#follow-up-backlog).** Plus one CA.6 hand-off (Views + ViewModels — the deferred half of the App layer).

---

## Sub-scope decision

Pass 0 confirmed the kickoff's recommended split. The chosen scope:

- **CA.5 (this increment):** Engine-adapter slice — 49 files / 7,975 LoC. Top-level files (14: `VisualizerEngine` + 11 extensions + `ContentView` + `PhospheneApp` + `MusicKitFetcher`), `Services/` (30), `Permissions/` (3), `Models/` (2).
- **CA.6 (deferred):** Views + ViewModels presentation slice — 59 files / 6,889 LoC. `Views/` (47 across `Connecting/`, `Dashboard/`, `Ended/`, `Idle/`, `Onboarding/`, `Playback/`, `Preparation/`, `Ready/`, `Settings/` + root-level views including `MetalView.swift`) + `ViewModels/` (12).

The split is justified by architectural layering: `Services/` + `VisualizerEngine` are the engine-coupling surface where the four prior audits' findings actually fire (BUG-015 wire, `DefaultPlaybackActionRouter` per D-050, `PresetScoringContextProvider` per Orchestrator scoring, `CaptureModeSwitchCoordinator` per D-061, etc.). `Views/` + `ViewModels/` is the SwiftUI presentation surface where U.x increments shipped UX flows and is its own audit class. **No silent scope-creep occurred.**

The kickoff prompt said "MetalView.swift — though MetalView lives under Views/" and listed it under both top-level and Views/ scopes. CA.5 follows the actual filesystem location: `MetalView.swift` is under `PhospheneApp/Views/MetalView.swift` and is deferred to CA.6 along with the rest of `Views/`.

---

## Findings by verdict

### broken-but-claimed (BUG entries filed)

**None filed in this increment.** BUG-015 (the only App-layer-class `broken-but-claimed` finding in scope) was already filed by CA.4 and Resolved on 2026-05-21 before CA.5 began. The wire shape is verified clean in §Verification-of-BUG-015-wire-shape below.

### production-orphan

**1. `MultiDisplayToastBridge.coalesceTask` + `pendingEvents` — declared, never read or written.**

```
$ grep -rn "pendingEvents\|coalesceTask" PhospheneApp/Services/MultiDisplayToastBridge.swift PhospheneAppTests PhospheneApp --include="*.swift"
PhospheneApp/Services/MultiDisplayToastBridge.swift:22:    private var coalesceTask: Task<Void, Never>?
PhospheneApp/Services/MultiDisplayToastBridge.swift:23:    private var pendingEvents: [String] = []
```

Two field declarations, zero consumers across the App layer and App tests. The file-internal logic (`handleAdded` at line 39, `handleRemoved` at line 56) enqueues toasts unconditionally; neither field is touched. The line-21 comment `// Coalescing: rapid adds/removes within 0.5s produce one toast.` documents an intent the code does not implement.

Same shape as CA.4-FU-1's `DefaultLiveAdapter.transitionPolicy`: a field captured in the constructor (here at declaration default value) that no subsequent code reads. Either the coalescing should be implemented (matching the stated intent) or both fields + the comment should be removed. The choice is a product call — display hot-plug events arrive at human-scale cadence on Macs (seconds, not milliseconds), so the practical risk of unbatched toasts during a single hot-plug is low; the intent is documented but possibly not load-bearing. Registered as CA.5-FU-1.

### unverified-claim

**1. `LiveAdaptationToastBridge.swift:1–14` docstring claims engine-event observation source that has no production-wired consumer.**

```swift
// LiveAdaptationToastBridge — Emits ack toasts for engine adaptation events + user actions.
…
// Two observation sources:
//   1. User actions via PlaybackActionRouter (post-U.6b)
//   2. Engine events (currently wired only for UserDefaults flag check and coalescing logic)
```

The implementation has one public emission method, `emitAck(_:)` at line 62. All 11 production call sites of `emitAck` live in `DefaultPlaybackActionRouter` (cited grep above). The BUG-015 wire's engine-side adaptation events (`applyLiveUpdate(...)` at `VisualizerEngine+Orchestrator.swift:167`) log via `logger.info(...)` at line 195 only — no `emitAck` invocation.

The "currently wired only for…" hedge avoids the claim being a hard lie, but the docstring leaves a future reader believing engine adaptation events should reach this bridge. Either decision is fine:

- **Option A** (engine adaptation toasts ARE intended): wire the `applyLiveUpdate` adaptation-event loop at `VisualizerEngine+Orchestrator.swift:189–197` to call `toastBridge?.emitAck(event.message)` for `.boundaryRescheduled` / `.moodDivergenceDetected` / `.presetOverrideTriggered` events. The UserDefaults flag at `LiveAdaptationToastBridge.swift:31` already gates emission.
- **Option B** (engine adaptation toasts are NOT intended; user-action acks are the only purpose): rewrite the docstring to drop the "engine events" line and rename or expand `emitAck` documentation to make clear only user-action acks reach this surface.

The audit recommends surfacing this to Matt as a product call (it is a UX question, not a correctness defect). Registered as CA.5-FU-2.

### documented-but-missing

**None this increment.** Every App-layer capability that load-bearing docs claim to exist was verified against code.

### dead

**None.** Every public, internal, or fileprivate symbol in scope has at least one live consumer, with the exception of the two `MultiDisplayToastBridge` fields counted under `production-orphan` above.

### stub

**None.** No `#if`-gated public types or empty bodies in scope.

### built-but-undocumented

**1. `ARCHITECTURE.md §Module Map PhospheneApp/` block lists 12 of 49 engine-adapter files; 37 missing.**

**Listed (12):** `ContentView`, `PhospheneApp`, `VisualizerEngine`, `VisualizerEngine+Audio`, `VisualizerEngine+Stems`, `VisualizerEngine+Presets`, `Permissions/ScreenCapturePermissionProvider`, `Permissions/PermissionMonitor`, `Permissions/PhotosensitivityAcknowledgementStore`, `Services/DelayProviding`, `Services/SpotifyURLKind`, `Services/SpotifyURLParser`, `Services/DisplayChangeCoordinator`, `Services/CaptureModeSwitchCoordinator`, `Services/NetworkRecoveryCoordinator`. (Counted 15; recount: yes, 6 Services entries — the audit's earlier "6 Services" count was correct. Including ContentView + PhospheneApp + VisualizerEngine + 3 extensions + 3 Permissions + 6 Services = **15 listed**, not 12. Recount accepted; total still 49 − 15 = **34 missing**.)

**Missing (34):**

VisualizerEngine extensions (7):
- `VisualizerEngine+Capture.swift` — Recording + capture + signal-state callback + onTrackChange callback + BUG-015 `liveTrackPlanIndex` write + `orchestratorWireLoggedThisTrack` reset.
- `VisualizerEngine+Orchestrator.swift` — Plan-building (`buildPlan` / `extendPlan` / `regeneratePlan` / `_buildPlan(seed:)`) + plan queries (`currentPreset(at:)` / `currentTransition(at:)`) + Live Adaptation (`applyLiveUpdate` / `applyReactiveUpdate`) + **BUG-015 wire** (`runOrchestratorLiveUpdate(mir:)`, `orchestratorWireFrameDivisor: 30`, `OrchestratorWireSnapshot` snapshot struct, once-per-track diagnostic at line 323) + U.6b router support (`extendCurrentPreset`, `applyPresetByID`, `restoreLivePlan`, `buildScoringContext`, `currentTrackIndexInPlan`, `indexInLivePlan(matching:)`, `currentTrackProfile`).
- `VisualizerEngine+Dashboard.swift` — DASH.7 `publishDashboardSnapshot(stems:)` + `assemblePerfSnapshot(pipeline:)` per-frame pump.
- `VisualizerEngine+InitHelpers.swift` — Private init helpers: `setupCaptureHook` (SessionRecorder blit), `setupDashboardSnapshotPump`, `setupBackgroundTextures` (TextureManager + IBLManager), `makeSessionManager` (factory), `setupTerminationObserver`, `detectDeviceTier` (DeviceTier inference). Plus the `NullStemSeparator` fallback class.
- `VisualizerEngine+PublicAPI.swift` — `startAudio` (permission gate + screen-capture poll), `applyAccessibility(reduceMotion:beatAmplitudeScale:)` (U.9 / D-054), `applyShowUncertifiedPresets(_:)`, `toggleDebugOverlay`, `toggleForceSpider` (DEBUG-only), `showPresetName(_:)`.
- `VisualizerEngine+TrackIdentityResolution.swift` — `canonicalTrackIdentity(matching:)` (BUG-006.2 cause-2 fix / D-091 plan-index resolution).
- `VisualizerEngine+WiringLogs.swift` — BUG-006.1 instrumentation: `logWiringBuildPlanEnter` / `logWiringBuildPlanEarlyReturn` / `logWiringBuildPlanDone` / `logWiringBuildPlanFailed` / `logWiringResetStemPipelineEnter` / `logTrackChangeObserved` / `logWiringStemCacheLookup`. Plus the `ResetStemPipelineCaller` enum (`.preFire / .trackChange / .other`).

Top-level files (1):
- `MusicKitFetcher.swift` — Actually contains `ITunesSearchFetcher` (file name drift — see CA.5-FU-3).

Services/ (24):
- `AccessibilityLabels.swift` — Centralised VoiceOver labels under `"a11y.*"` keys.
- `AccessibilityState.swift` — `@MainActor ObservableObject`; combines system `NSWorkspace.accessibilityDisplayShouldReduceMotion` with `ReducedMotionPreference` from `SettingsStore`. Publishes `reduceMotion`, `beatAmplitudeScale: Float`. Per-frame gating queries `shouldExecuteMVWarp(presetEnabled:)` / `shouldExecuteSSGI`. U.9 / D-054.
- `CaptureModeReconciler.swift` — Routes `SettingsStore.captureMode` changes to `AudioInputRouter.switchMode(_:)` per D-052 live-switch path.
- `DefaultPlaybackActionRouter.swift` — Concrete `PlaybackActionRouter` per D-050 / U.6b. `AdaptationFields` snapshot type. 7 router methods (`moreLikeThis` / `lessLikeThis` / `reshuffleUpcoming` / `presetNudge(_:immediate:)` / `rePlanSession` / `undoLastAdaptation` / `toggleMoodLock`). Family-boost cap `0.3`, family-exclusion window `600s`, ambient-hint window `90s`, override ceiling `8s`, undo capacity `8`. Static `live(engine:toastBridge:onShowPlanPreview:)` factory captures weak engine references.
- `DisplayManager.swift` — `@MainActor ObservableObject` for screen tracking + window-move with fullscreen-quirk handling. Publishes `allScreens`, `currentScreen`, `primaryScreen`. `attach(to:)`, `moveToSecondaryDisplay()`, `moveToPrimaryDisplay()`. Plus `onScreensAdded` / `onScreensRemoved` callbacks consumed by `MultiDisplayToastBridge`.
- `FirstAudioDetector.swift` — `@MainActor ObservableObject`; subscribes to `AudioSignalState` publisher; sets `hasDetectedAudio` after ≥ 250 ms sustained `.active` state. Per UX_SPEC §6.3.
- `FullscreenObserver.swift` — `@MainActor ObservableObject` wrapping `NSWindow.didEnterFullScreenNotification` / `didExitFullScreenNotification`; publishes `isFullscreen: Bool`.
- `LiveAdaptationToastBridge.swift` — User-action ack toast bridge; `emitAck(_:)` gated on `phosphene.settings.visuals.showLiveAdaptationToasts` UserDefaults; 2 s coalescing window. (See `unverified-claim` finding above.)
- `LocalizedCopy.swift` — `UserFacingError` → localized string resolver. Jargon deny-list enforcement (`containsJargon(_:)`) per UX_SPEC §9.5.
- `MultiDisplayToastBridge.swift` — `DisplayManager.onScreensAdded/Removed` → `ToastManager` queue. Info toast on screen-added; warning toast + auto-move on current-screen-removed. (See `production-orphan` finding above for dead `coalesceTask`/`pendingEvents` fields.)
- `NetworkRecoveryCoordinator.swift` — `@MainActor`; wires `ReachabilityMonitor.isOnlinePublisher` to `SessionManager.resumeFailedNetworkTracks()`; 2 s additional debounce on top of monitor's 1 s (3 s total); max 3 attempts per session; `.preparing` state guard. D-061(d,e).
- `OnboardingReset.swift` — Static UserDefaults-key reset utility. Keys: `"phosphene.onboarding.photosensitivityAcknowledged"`.
- `PlaybackErrorBridge.swift` — Routes UX_SPEC §9.4 audio-signal errors to `ToastManager` with condition-ID semantics. `silenceToastThresholdSeconds: 15`, `silenceToastGraceWindowThresholdSeconds: 20` (raised by `CaptureModeSwitchCoordinator` during grace windows per D-061(b)).
- `PlaybackErrorConditionTracker.swift` — Lightweight register of asserted condition IDs. `assert` / `clear` / `isAsserted` / `reset`.
- `PlaybackKeyMonitor.swift` — `NSEvent.addLocalMonitorForEvents` install/uninstall for in-session keyboard shortcuts. Routes via `PlaybackShortcutRegistry`.
- `PlaybackShortcutRegistry.swift` — Declarative shortcut catalog. `ShortcutCategory` enum (`.playback / .liveAdaptation / .developer`). `PlaybackShortcut(id:key:modifiers:label:category:action:)`. Wires Shift+→ / Shift+← (presetNudge), `+` / `-` (moreLikeThis / lessLikeThis), `R` (reshuffle), `Z` (undo), `M` (mood-lock), plus diagnostic shortcuts (beat-phase / audio-latency / bar-phase / spider / preset cycling).
- `PreparationETAEstimator.swift` — Rolling EMA over per-stage durations (resolving / downloading / stemSeparation / caching). `minSamplesRequired: 3`, `emaAlpha: 0.3`.
- `PresetScoringContextProvider.swift` — Canonical builder of `PresetScoringContext` for Orchestrator scoring calls. Resolves `DeviceTierOverride` (`.auto`/`.forceTier1`/`.forceTier2`) against detected hardware tier. U.8 Part C.
- `ReachabilityMonitor.swift` — `NWPathMonitor` wrapper with 1 s debounce. `ReachabilityPublishing` protocol + `StubReachabilityMonitor` test-double pair.
- `SessionRecorderRetentionPolicy.swift` — Session-folder pruning. `SessionRetentionPolicy` enum: `.keepAll / .lastN10 / .lastN25 / .oneDay / .oneWeek`. 60 s active-session guard prevents deletion of in-progress folders. `defaultSessionsDir` returns `~/Documents/phosphene_sessions/`.
- `SettingsMigrator.swift` — One-shot UserDefaults key migration on app launch. One mapping today: `"phosphene.showLiveAdaptationToasts"` → `"phosphene.settings.visuals.showLiveAdaptationToasts"`.
- `SettingsStore.swift` — `@MainActor final class SettingsStore: ObservableObject`. **One app-wide instance** per D-091 / Failed Approach #55 (`SettingsStoreEnvironmentRegressionTests` is the regression gate). 11 `@Published` fields covering capture mode, device-tier override, quality ceiling, Milkdrop inclusion, reduced motion, excluded preset categories, show-live-adaptation-toasts, show-uncertified-presets, session-recorder-enabled, session-retention. `captureModeChanged: PassthroughSubject<Void, Never>` event for audio-related changes consumed by `CaptureModeReconciler` + `CaptureModeSwitchCoordinator`.
- `SpotifyKeychainStore.swift` — `SpotifyKeychainStoring` protocol + concrete `SpotifyKeychainStore` using `SecItem*` APIs. Default service `"com.phosphene.spotify"`, default account `"refresh_token"`. U.11.
- `SpotifyOAuthPlaylistConnector.swift` — `PlaylistConnecting` wrapper that remaps `spotifyLoginRequired` to `spotifyPlaylistInaccessible` when the user is authenticated. U.11.
- `SpotifyOAuthTokenProvider.swift` — `public actor SpotifyOAuthTokenProvider: SpotifyTokenProviding, SpotifyOAuthLoginProviding`. PKCE auth-code OAuth flow. `expiryMarginSeconds: 300`, `loginTimeoutSeconds: 300`, redirect URI `"phosphene://spotify-callback"`. U.11 / D-069.

Models/ (2):
- `PhospheneToast.swift` — Toast value type. `Severity` enum (`.info / .warning / .degradation`). `Source` enum (`.signalState / .liveAdaptationAck / .displayChange / .degradation / .generic`). `ToastAction { label: String, handler: @MainActor @Sendable () -> Void }`. Default duration `4 s`; `TimeInterval.infinity` for manual-dismiss-only.
- `SettingsTypes.swift` — App-layer settings value-type enums: `CaptureMode` (`.systemAudio / .specificApp / .localFile`), `DeviceTierOverride` (`.auto / .forceTier1 / .forceTier2`), `ReducedMotionPreference` (`.matchSystem / .alwaysOn / .alwaysOff`), `SessionRetentionPolicy` (5 cases). `SourceAppOverride` struct.

Doc-drift correction applied in this increment.

**2. `ARCHITECTURE.md §Module Map Tests/PhospheneApp/` block is absent entirely.**

`PhospheneAppTests/` exists with 60+ test files. The Tests/ section of the Module Map has entries for `Audio/`, `DSP/`, `ML/`, `Renderer/`, `Session/`, and (post-CA.4) `Orchestrator/` — but not `PhospheneApp/`. Notable App-layer test files:

- **`OrchestratorWiringRegressionTests.swift`** — BUG-015 source-presence regression gate.
- **`SettingsStoreEnvironmentRegressionTests.swift`** — D-091 / Failed Approach #55 regression gate (three assertions: `@EnvironmentObject` consumer sees changes; `@StateObject SettingsStore()` shadow does NOT see changes; `PlaybackView.swift` source must not contain the bad declaration).
- **`PlaybackChromeIndexBindingTests.swift`** — D-091 / QR.4 plan-index propagation (`title-case mismatch must not change index`).
- **`DefaultPlaybackActionRouterTests.swift`** — D-050 / U.6b router contract.
- **`CaptureModeSwitchCoordinatorTests.swift`** — D-061 grace-window timing.
- **`NetworkRecoveryCoordinatorTests.swift`** — D-061(d,e) recovery cap + debounce.
- **`SpotifyConnectionViewModelTests.swift`** + **`SpotifyKeychainStoreTests.swift`** + **`SpotifyOAuthTokenProviderTests.swift`** — U.11 cluster (the OAuth test suite carries `@Suite("SpotifyOAuthTokenProvider", .serialized)` per U.10 URLProtocol-stub rule).
- **`PresetScoringContextProviderTests.swift`** — App ↔ Orchestrator scoring-context bridge.
- **`LiveAdaptationToastBridgeTests.swift`** — U.6 Part C ack toast bridge.
- **`AppleMusicConnectionViewModelTests.swift`** — U.3 connector state machine.
- **`PlaybackErrorBridgeTests.swift`** + **`PlaybackErrorConditionTrackerTests.swift`** — UX_SPEC §9.4 silence-error routing.
- **`SessionRecorderRetentionPolicyTests.swift`** — Pruning policy invariants.
- **`SettingsMigratorTests.swift`** — Legacy UserDefaults migration round-trip.
- Plus the per-VM tests `PlaybackChromeViewModelTests`, `ToastManagerTests`, `ReadyViewTimeoutIntegrationTests`, etc. (CA.6 will inventory the VM-side tests).

Doc-drift correction applied in this increment.

### boundary-noted

The audit produced no `boundary-deferred` items. The following App-layer boundary surfaces are noted (verdict complete; no future re-audit required):

- **App ↔ Orchestrator.** `DefaultSessionPlanner` + `DefaultLiveAdapter` + `DefaultReactiveOrchestrator` instantiated at `VisualizerEngine.swift:458 / 461 / 464`. `DefaultPlaybackActionRouter` concrete lives in `PhospheneApp/Services/`. `PresetScoringContextProvider` builds `PresetScoringContext` for the Orchestrator scorer. The **BUG-015 wire** (`runOrchestratorLiveUpdate(mir:)` calling `applyLiveUpdate(...)` at ~3 Hz) is the load-bearing post-2026-05-21 surface; verified clean in §Verification-of-BUG-015-wire-shape. CA.4 closed the Orchestrator side; CA.5 closes the App side. Boundary verdict: **complete**.

- **App ↔ Session.** `SessionManager` constructed at `VisualizerEngine.swift:644` via `Self.makeSessionManager(...)` factory (`+InitHelpers.swift:99`). `StemCache` wired eagerly at `VisualizerEngine.swift:658` (`self.stemCache = self.sessionManager.cache` — BUG-006.2 fix). `MetadataPreFetcher` constructed at `VisualizerEngine.swift:641` and shared between `SessionPreparer` and the runtime track-change callback (Round 26 metadata-meter override). `stateCancellable` subscribes to `sessionManager.$state` and triggers `buildPlan()` on `.ready` (`VisualizerEngine.swift:687–692`); `readinessCancellable` subscribes to `$progressiveReadinessLevel` and triggers `extendPlan()` (`VisualizerEngine.swift:696–705`). Per CA.3 the Session side is clean. Boundary verdict: **complete**.

- **App ↔ DSP / MIR.** `MIRPipeline()` constructed at `VisualizerEngine.swift:622`; `audioOutputLatencyMs: 50.0` set at `:627` per BUG-007.6 default. Per-frame consumer is `processAnalysisFrame` at `VisualizerEngine+Audio.swift:135` which calls `mir.process(magnitudes:fps:time:deltaTime:)` and threads the result through `pipeline.setFeatures(fv)`, `pipeline.updateFeedbackBeatValue(from: fv)`, `updateSpectralCartographBeatGrid`, the per-frame stem analyzer, `runLiveBeatAnalysisIfNeeded`, the mood classifier, and finally `runOrchestratorLiveUpdate(mir:)`. CA.1's per-frame `StructuralAnalyzer` chain now has a runtime consumer (via the BUG-015 wire reading `mir.latestStructuralPrediction` at `VisualizerEngine+Orchestrator.swift:336`) — **CA.1-FU-1's CPU-saving gate option (a) is no longer the cleanest path**; the per-frame chain is genuinely consumed now. CA.1-FU-1 closure question is now product (keep gate-to-prep-time + sentinel, or feed runtime predictions through) — surfaced to Matt below. Boundary verdict: **complete**.

- **App ↔ ML.** `MoodClassifier` loaded via `Self.loadMoodClassifier()` at `VisualizerEngine.swift:586` and consumed at `VisualizerEngine+Audio.swift:289` (`mood.classify(features:)`). `StemSeparator` loaded via `Self.loadStemSeparator(device:)` at `:614`. `StemAnalyzer(sampleRate: StemSeparator.modelSampleRate)` constructed at `:585`. `MLDispatchScheduler` constructed at `VisualizerEngine.swift:668` with tier-dependent budget (`14ms` Tier 1, `16ms` Tier 2 — `VisualizerEngine+Stems.swift:113`); consumed in `runStemSeparation()` decision at `+Stems.swift:121`. Boundary verdict: **complete** (CA.2's read of the ML side already validated this consumption shape).

- **App ↔ Renderer.** `RenderPipeline` constructed at `VisualizerEngine.swift:600`. `FrameBudgetManager` and `MLDispatchScheduler` constructed at `:667 / :668` reading `QualityCeiling` from `UserDefaults` at `:662–665`. `RayMarchPipeline` constructed per-preset in `applyPreset` (`VisualizerEngine+Presets.swift:115`) and stored in `currentRayMarchPipeline` so `debugGBufferMode` toggles can push directly (`VisualizerEngine.swift:107–109`). Per-preset state classes (`ArachneState` + `GossamerState` + `AuroraVeilState` + `LumenPatternEngine` + `FerrofluidParticles` + `FerrofluidMesh` + `DynamicTextOverlay`) bind to slots 6 / 7 / 8 via `setDirectPresetFragmentBuffer` / `setDirectPresetFragmentBuffer2` / `setDirectPresetFragmentBuffer3` per CLAUDE.md GPU Contract. Per-frame tick closures wired via `setMeshPresetTick`. Boundary verdict: **complete**.

- **App ↔ Audio.** `AudioInputRouter` constructed at `VisualizerEngine+Audio.swift:26` (stored as `Any?` to avoid availability propagation per `VisualizerEngine.swift:196`). Three callbacks wired: `onAudioSamples` at `+Audio.swift:30` runs on the audio thread (writes `audioBuffer`, captures `tapSampleRate` via `updateTapSampleRate(_:)` per D-079 / QR.1, feeds `stemSampleBuffer`, runs FFT, dispatches to `analysisQueue.async`); `onSignalStateChanged` at `+Audio.swift:31` hops to MainActor for `@Published` updates; `onTrackChange` at `+Audio.swift:39` resolves `liveTrackPlanIndex` and `orchestratorLock`-guards the BUG-015 wire inputs before hopping to MainActor for SwiftUI consumers. **Cross-core visibility** for `tapSampleRate` is enforced via `tapSampleRateLock: NSLock` (`VisualizerEngine.swift:243`); the `_tapSampleRate` mutation goes through `updateTapSampleRate(_:)` which `withLock`s the write. CLAUDE.md D-079 / QR.1 rule satisfied. Boundary verdict: **complete**.

- **App ↔ Presets.** Per-preset state classes (`ArachneState`, `GossamerState`, `AuroraVeilState`, `LumenPatternEngine`, `FerrofluidParticles`, `FerrofluidMesh`, `DynamicTextOverlay`) live in `PhospheneEngine/Sources/Presets/` but are instantiated and owned in `VisualizerEngine.swift` (lines 119–163). The siblings-not-subclasses pattern per D-097 is enforced via `resolveParticleGeometry(forPresetName:)` at `VisualizerEngine.swift:754` (currently maps `"Murmuration"` → `murmurationGeometry`; unknown names return nil). The `wirePresetCompletionSubscription()` at `VisualizerEngine+Presets.swift:500` and `presetCompletionCancellable` storage (`VisualizerEngine.swift:536`) implement the V.7.6.2 / D-095 `PresetSignaling` subscription path. **Reset on preset switch** clears every per-preset field + every pipeline binding at the top of `applyPreset` (`+Presets.swift:48–80`) before the new preset configures its passes. The BUG-016 Lumen Mosaic apply path lives inside `case .rayMarch:` gated on `desc.name == "Lumen Mosaic"` at `+Presets.swift:166–178`. Boundary verdict: **complete** (the per-preset state classes themselves are CA-Presets scope and not audited here).

### production-active

(See per-file index below. The 48 `production-active` files concentrate by family; per-family rollups follow rather than per-file rows, mirroring CA.3 / CA.4's consolidated form. Non-`production-active` aspects are visually marked in their respective rows.)

---

## Per-file capability index

Consolidation: 48 of 49 files concentrate on `production-active`; the per-file index below mirrors CA.3 / CA.4's consolidated form. The two notable non-`production-active` rows (`MultiDisplayToastBridge` field-level orphan; `LiveAdaptationToastBridge` unverified-claim docstring) are marked inline.

### VisualizerEngine.swift (773 lines) — `production-active` + BUG-012-i1 instrumented (read-only)

The engine's primary owner type: a `final class VisualizerEngine: ObservableObject, @unchecked Sendable` constructed once at app launch by `PhospheneApp.swift:23` via `@StateObject private var engine = VisualizerEngine()`. Owns the audio capture → FFT → analysis → MIR → mood → stem → render pipeline. ~30 `@Published` fields driving SwiftUI consumers. NSLock-guarded shared state (`tapSampleRateLock`, `orchestratorLock`, `stemsStateLock`, `beatSyncLock`). All Orchestrator-side handles (sessionPlanner, liveAdapter, reactiveOrchestrator, livePlan, livePlannedSession) instantiated here. BUG-015 wire inputs (`liveTrackPlanIndex`, `lastClassifiedMood`, `orchestratorWireLoggedThisTrack`) declared here under `orchestratorLock`.

| Capability | Verdict | Consumers (prod / test) | Doc-cited |
|---|---|---|---|
| `MIRDiagnostics` struct (12 fields) | `production-active` | Debug overlay; published via `@Published var mirDiag` | Internal |
| `VisualizerEngine` class | `production-active` | App-wide via `@StateObject` / `@EnvironmentObject` | D-091 |
| BUG-015 wire fields (`liveTrackPlanIndex`, `lastClassifiedMood`, `orchestratorWireLoggedThisTrack`) | `production-active` | `runOrchestratorLiveUpdate(mir:)`; `makeTrackChangeCallback` | BUG-015 Resolved entry |
| `tapSampleRate` + `updateTapSampleRate(_:)` (NSLock-guarded) | `production-active` | Audio callback; stem queue; analysis queue | D-079 / QR.1 |
| `orchestratorLock` + `livePlan` + `livePlannedSession` | `production-active` | All Orchestrator entry points | D-035 / D-091 |
| `currentTrackIndex: @Published Int?` | `production-active` | `PlaybackChromeViewModel` (bound via publisher in ContentView) | D-091 |
| `arachneState`, `gossamerState`, `auroraVeilState`, `lumenPatternEngine`, `ferrofluidParticles`, `ferrofluidMesh`, `spectralCartographOverlay`, `currentRayMarchPipeline`, `murmurationGeometry` | `production-active` | `applyPreset` set/clear; per-frame tick closures | Per-preset increments |
| `presetCompletionCancellable` + `currentSegmentStartTime` + `presetCompletionAdvanceCount` | `production-active` | `wirePresetCompletionSubscription`; `handlePresetCompletionEvent` | D-095 / V.7.6.2 |
| `captureModeSwitchGraceWindowEndsAt` + `isCaptureModeSwitchGraceActive` (CaptureModeSwitchEngineInterface conformance) | `production-active` | `CaptureModeSwitchCoordinator`; `applyLiveUpdate` suppression | D-061(b) |
| `diagnosticPresetLocked: Bool` | `production-active` | `applyLiveUpdate` mood-override suppression; `handlePresetCompletionEvent` | DSP.3.1 + V.7.7C.4 |
| BUG-012 probes (`init` line 709, `deinit` line 718) | **read-only — instrumented** | BUG012Probe | BUG-012-i1 |
| `featureEmaAlpha: Float = 0.01` (10-second EMA, ~7s effective window @ 94 Hz) | `production-active` | `accumulateMoodFeatures` | Mood classifier inputs |

VisualizerEngine.swift is one of the two App-layer **BUG-012-i1-instrumented files**. CA.5 audited the file freely but did NOT edit it per CA.5 Hard Rules.

### VisualizerEngine+Audio.swift (461 lines) — `production-active`

Owns audio routing, MIR analysis, mood classification, and per-frame stem analysis. **BUG-015 wire callsite at line 184.** Implements the audio-thread / analysis-queue / MainActor partitioning per CLAUDE.md concurrency model.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `setupAudioRouting(audioBuffer:fftProcessor:) -> AudioInputRouter` | `production-active` | `VisualizerEngine.init` (macOS 14.2+) | — |
| `makeAudioSampleCallback(buf:fft:)` | `production-active` | `setupAudioRouting` | Audio thread; writes buffer, calls `updateTapSampleRate(_:)`, dispatches to analysisQueue |
| `processAnalysisFrame(magnitudes:)` | `production-active` | `makeAudioSampleCallback` (analysisQueue) | Threads `fv` through pipeline, runs per-frame stem analysis, live BeatThis trigger, mood classifier, **BUG-015 wire** |
| `runPerFrameStemAnalysis(fps:)` | `production-active` | `processAnalysisFrame` | Slides 1024-sample window through latest separated stems; D-079 / QR.1 sample-rate plumbing |
| `accumulateMoodFeatures(fv:mir:)` | `production-active` | `processAnalysisFrame` | EMA-accumulate 10 features (alpha=0.01) |
| `runMoodClassifier(mood:fv:mir:magnitudes:)` | `production-active` | `processAnalysisFrame` | Calls `MoodClassifier.classify`; writes capture row at 10% sampling; diag log at 60% |
| `makeDiagnostics(fv:mir:magnitudes:) -> MIRDiagnostics` | `production-active` | `runMoodClassifier` | Debug overlay diag |
| `updateSpectralCartographBeatGrid(mir:fv:)` | `production-active` | `processAnalysisFrame` | DSP.3.1 SpectralCartograph overlay buffer + BeatSyncSnapshot |
| `writeDiagnosticLine(state:mir:)` | `production-active` | `runMoodClassifier` (analysisFrameCount % 60 == 0) | `~/phosphene_diag.log` |
| `publishMoodResult(state:diag:stability:mir:)` | `production-active` | `runMoodClassifier` | **BUG-015: writes `lastClassifiedMood` under `orchestratorLock` at line 432** |
| `runOrchestratorLiveUpdate(mir:)` call at line 184 | `production-active` | `processAnalysisFrame` | **BUG-015 wire entry** |
| `static func buildFetcherList()` | `production-active` | `setupAudioRouting`; `VisualizerEngine.init` | iTunes + MusicBrainz + (Soundcharts / Spotify if env vars) |

### VisualizerEngine+Capture.swift (208 lines) — `production-active`

Recording + capture file management + audio signal-state callback + **BUG-015 track-change callback** that resolves the live track's plan index. Implements BUG-006.2 canonical-identity cache lookup (cause 2).

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `toggleRecording()`, `startCapture()`, `stopCapture()`, `writeCaptureRow(...)`, `toggleCapture()` | `production-active` | Keyboard shortcut `R` (toggleRecording); `C` (toggleCapture) | MIR feature CSV path (manual) |
| `makeSignalStateCallback()` | `production-active` | `setupAudioRouting` | Audio signal-state → MainActor + session.log |
| `makeTrackChangeCallback(fetcher:)` | `production-active` | `setupAudioRouting` | **BUG-015: resolves `liveTrackPlanIndex` + resets `orchestratorWireLoggedThisTrack` under `orchestratorLock`** before MainActor hop |
| Canonical identity lookup (`canonicalTrackIdentity(matching:)` consumed at line 166) | `production-active` | `makeTrackChangeCallback` | BUG-006.2 cause 2 fix |
| `kickoffPreFetch(for:fetcher:)` | `production-active` | `makeTrackChangeCallback` | Round 25/26 metadata-driven `beatsPerBar` override |

### VisualizerEngine+Orchestrator.swift (550 lines) — `production-active`

The App-layer adapter for the Orchestrator. Plan building (`buildPlan` / `extendPlan` / `_buildPlan(seed:)`), plan queries (`currentPreset(at:)` / `currentTransition(at:)`), live adaptation (`applyLiveUpdate` / `applyReactiveUpdate`), **BUG-015 wire** (`runOrchestratorLiveUpdate(mir:)` + `OrchestratorWireSnapshot` + once-per-track diagnostic at lines 305–331), plan regeneration (`regeneratePlan`), U.6b router support, plan-index resolution (`indexInLivePlan(matching:)`).

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `buildPlan()` | `production-active` | `stateCancellable.sink` on `.ready` (line 687) | D-091 seed |
| `extendPlan()` | `production-active` | `readinessCancellable.sink` (line 696) | D-091 progressive readiness |
| `_buildPlan(seed:)` | `production-active` | `buildPlan` + `extendPlan` | BUG-006.1 WIRING logs |
| `currentPreset(at:)`, `currentTransition(at:)` | `production-active` | Render pipeline; ViewModels | `orchestratorLock` guarded |
| `applyLiveUpdate(trackIndex:elapsedTrackTime:boundary:mood:)` | `production-active` | `runOrchestratorLiveUpdate(mir:)` | BUG-015 declaration site; D-080 cooldown via `liveAdapter.adapt(...)` |
| Mood-override suppression (`isCaptureModeSwitchGraceActive` / `diagnosticPresetLocked` / `activePresetWaitsForCompletion`) at lines 219–242 | `production-active` | `applyLiveUpdate` | D-061(b), DSP.3.1, V.7.6.2 |
| **`orchestratorWireFrameDivisor: Int = 30`** (cadence constant, line 263) | `production-active` | `runOrchestratorLiveUpdate(mir:)` | BUG-015: ~3 Hz @ 94 Hz analysis queue |
| **`runOrchestratorLiveUpdate(mir:)`** (line 287) | `production-active` | `processAnalysisFrame` | **BUG-015 wire — verified clean below** |
| **Once-per-track diagnostic** (lines 305–331) | `production-active` | `runOrchestratorLiveUpdate(mir:)` | BUG-015 — dual-writes session.log + os.Logger |
| `OrchestratorWireSnapshot` (private struct, line 345) | `production-active` | `runOrchestratorLiveUpdate(mir:)` | BUG-015 single-acquisition snapshot |
| `applyReactiveUpdate(boundary:mood:)` (line 360) | `production-active` | `applyLiveUpdate` (livePlan == nil branch) | D-036 / D-080: 60s `lastReactiveSwitchTime` cooldown; live `StemFeatures` after 10s convergence |
| `regeneratePlan(lockedTracks:lockedPresets:)` | `production-active` | `PlanPreviewViewModel.regeneratePlan` | D-047 seeded regen |
| `extendCurrentPreset(by:)` / `applyPresetByID(_:)` / `restoreLivePlan(_:)` | `production-active` | U.6b router (`DefaultPlaybackActionRouter`) | D-058 |
| `buildScoringContext(adaptationFields:)` | `production-active` | `DefaultPlaybackActionRouter.getScoringContext` closure | — |
| `currentTrackIndexInPlan()`, `indexInLivePlan(matching:)`, `currentTrackProfile()` | `production-active` | `makeTrackChangeCallback`; ViewModels | D-091 plan-index |

### VisualizerEngine+Stems.swift (583 lines) — `production-active` + BUG-012-i1 instrumented (read-only)

Background stem separation pipeline + live Beat This! analysis + BUG-007.9 hybrid runtime recalibration + LM.4.7 per-track palette refresh. **The second App-layer BUG-012-i1-instrumented file.** Probes at runStemSeparation timer-entry, MainActor self=nil check, stemQueue.async self=nil check (3 sites), performStemSeparation enter/exit, separator.separate CALL/RETURN, dispatch-ID allocation.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `static loadStemSeparator(device:) -> StemSeparator?` | `production-active` | `VisualizerEngine.init` | Logs on failure |
| `startStemPipeline()` / `stopStemPipeline()` | `production-active` | `startAudio` (PublicAPI) | 5 s cadence, 10 s warmup |
| `runStemSeparation()` (line 76) | `production-active` | DispatchSourceTimer fire | BUG-012 instrumented; MLDispatchScheduler gate |
| `performStemSeparation()` (line 155) | `production-active` | `runStemSeparation` | BUG-012 instrumented; D-079 sample-rate plumbing |
| `runtimeRecalibrationIfDue()` | `production-active` | `performStemSeparation` | BUG-007.9 one-shot per-track |
| `runLiveBeatAnalysisIfNeeded()` (line 321) | `production-active` | `processAnalysisFrame` | 10 s + 20 s retry; halvingOctaveCorrected at >175 BPM |
| `performLiveBeatInference(mono:sampleRate:bufferStartTime:attemptNum:)` (line 384) | `production-active` | `runLiveBeatAnalysisIfNeeded` | DSP.3.5 / 3.6 |
| `resetStemPipeline(for:caller:)` (line 451) | `production-active` | `_buildPlan`; track-change callback | BUG-006.1 source-tagged WIRING logs; LM.4.7 palette refresh |
| `refreshLumenPaletteForTrack(identity:lumenEngine:)` (line 537) | `production-active` | `resetStemPipeline` | LM.4.7 / D-LM-palette-library |
| `lumenTrackSeedHash(for:)` (line 574) | `production-active` | `refreshLumenPaletteForTrack` | FNV-1a 64-bit |
| `silenceRMSThreshold: Float = 1e-6` (line 65) | `production-active` | `performStemSeparation` | Silence skip gate |
| `runtimeRecalibrationWindowSeconds: Double = 12.0` (line 240) | `production-active` | `runtimeRecalibrationIfDue` | BUG-007.9 |
| `runtimeRecalibrationMinMatchedOnsets: Int = 8` (line 245) | `production-active` | `runtimeRecalibrationIfDue` | EMA settle |
| `liveBeatMinSeconds: Double = 10.0` (line 300) | `production-active` | `runLiveBeatAnalysisIfNeeded` | DSP.3.5 |
| `liveBeatRetrySeconds: Double = 20.0` (line 305) | `production-active` | `runLiveBeatAnalysisIfNeeded` | DSP.3.5 — Pyramid Song / Money 7/4 |
| `liveBeatMaxAttempts: Int = 2` (line 308) | `production-active` | `runLiveBeatAnalysisIfNeeded` | DSP.3.5 |

CA.5 audited the file freely but did NOT edit it per CA.5 Hard Rules.

### VisualizerEngine+Presets.swift (581 lines) — `production-active`

`applyPreset(_:)` — the single owner of every preset-switch transition. Resets every per-preset field + pipeline binding before configuring the new preset's passes. Per-pass case statements: `.meshShader`, `.postProcess`, `.rayMarch`, `.feedback`, `.particles`, `.icb`, `.ssgi`, `.mvWarp`, `.staged`, `.direct`. **BUG-016 Lumen Mosaic apply branch at lines 166–178.** AuroraVeilState allocation OUTSIDE the switch (AV.2.2b — passes: [] for Aurora Veil). V.7.6.2 / D-095 `wirePresetCompletionSubscription()` per applyPreset. D-LM-buffer-slot-8 enforcement.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `nextPreset()`, `previousPreset()` | `production-active` | Keyboard shortcuts; reactive-mode selection | — |
| `applyPreset(_:)` (line 44) | `production-active` | All preset switches | Per-pass switch; reset-then-configure |
| `makeSceneUniforms(from:)` | `production-active` | `case .rayMarch:` | Delegates to `PresetDescriptor.makeSceneUniforms()` |
| `wirePresetCompletionSubscription()` (line 500) | `production-active` | End of `applyPreset` | V.7.6.2 / D-095 |
| `activePresetSignaling()` (line 524) | `production-active` | `wirePresetCompletionSubscription` | Currently returns `arachneState` only |
| `handlePresetCompletionEvent()` (line 567) | `production-active` | `presetCompletionCancellable.sink` | `diagnosticPresetLocked` + `minSegmentDuration` gate per V.7.7C.4 |
| `makeFerrofluidMeshEncoder(mesh:)` (line 534) | `production-active` (currently retired) | Currently unused — mesh path disabled at round 57 | Preserved for future re-enable per CLAUDE.md Failed Approach #66 |
| **Lumen Mosaic .rayMarch branch (lines 166–178)** | `production-active` | `applyPreset .rayMarch` | **BUG-016 surface — see §Verification-of-BUG-016 below** |
| Ferrofluid Ocean `setRayMarchPresetHeightTexture` binding | `production-active` | `applyPreset .rayMarch` | V.9 Session 4.5c round 57 SDF path restored |
| `setMeshGBufferEncoder(nil)` reset on every applyPreset (line 72) | `production-active` | `applyPreset` reset block | Failed Approach #66 (fixture/live G-buffer parity) |

### VisualizerEngine+Dashboard.swift (51 lines) — `production-active`

DASH.7 per-frame snapshot pump. `publishDashboardSnapshot(stems:)` writes `dashboardSnapshot: DashboardSnapshot?` from MainActor; the dashboard overlay view model subscribes via Combine and throttles to ~30 Hz (per CA-Renderer / Views audit later).

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `publishDashboardSnapshot(stems:)` | `production-active` | `setupDashboardSnapshotPump` (InitHelpers) | DASH.7 |
| `assemblePerfSnapshot(pipeline:)` | `production-active` | `publishDashboardSnapshot` | FrameBudgetManager + MLDispatchScheduler state |

### VisualizerEngine+InitHelpers.swift (171 lines) — `production-active`

Static factory methods called from `init`. Includes `NullStemSeparator` fallback for missing Open-Unmix weights.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `setupCaptureHook(pipe:ctx:)` | `production-active` | `init` | SessionRecorder blit + onFrameTimingObserved |
| `setupDashboardSnapshotPump(pipe:)` | `production-active` | `init` | Chains previous `onFrameRendered`; DASH.7 |
| `setupBackgroundTextures(pipe:ctx:lib:)` | `production-active` | `init` | TextureManager + IBLManager userInitiated async |
| `makeSessionManager(sep:analyzer:classifier:device:sessionRecorder:metadataFetcher:)` | `production-active` | `init` | Round 26 shared MetadataPreFetcher |
| `setupTerminationObserver()` | `production-active` | `init` | NSApplication.willTerminate → recorder.finish() |
| `detectDeviceTier(device:)` | `production-active` | `init`, `_buildPlan`, `regeneratePlan`, etc. | M3/M4 → tier2; else tier1 |
| `NullStemSeparator` (private final class) | `production-active` | `makeSessionManager` fallback | StemSeparating; always throws modelNotFound |

### VisualizerEngine+PublicAPI.swift (126 lines) — `production-active`

`startAudio()` + permission polling + accessibility forwarding (D-054) + uncertified-presets forwarding + `showPresetName(_:)` (2 s display + fade).

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `startAudio()` | `production-active` | `PlaybackView.onAppear` | Permission gate per CLAUDE.md Failed Approach #22 |
| `pollForScreenCapturePermission()` (private) | `production-active` | `startAudio` fallback | 2 s poll loop |
| `startAudioCapture()` (private) | `production-active` | `startAudio`, poll loop | macOS 14.2+ AudioInputRouter.start |
| `applyAccessibility(reduceMotion:beatAmplitudeScale:)` | `production-active` | `PhospheneApp.onChange` of `accessibilityState.reduceMotion` | U.9 / D-054 |
| `applyShowUncertifiedPresets(_:)` | `production-active` | `PhospheneApp.task` on `settingsStore.$showUncertifiedPresets` | — |
| `toggleDebugOverlay()` | `production-active` | Keyboard shortcut `D` | — |
| `toggleForceSpider() -> Bool` (DEBUG-only) | `production-active` | Keyboard shortcut (developer cycle) | Arachne easter egg |
| `showPresetName(_:)` | `production-active` | `applyPreset`, `nextPreset`, `previousPreset`, `applyPresetByID`, `regeneratePlan` consumers | 2 s + 0.5 s fade |

### VisualizerEngine+TrackIdentityResolution.swift (41 lines) — `production-active`

BUG-006.2 cause 2 fix. `canonicalTrackIdentity(matching:)` resolves a partial title+artist `TrackIdentity` against `livePlan` via `PlannedSession.canonicalIdentity(matchingTitle:artist:)`. Returns nil for ad-hoc / reactive sessions and for ambiguous matches.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `canonicalTrackIdentity(matching:)` | `production-active` | `+Capture.swift:166` track-change callback | BUG-006.2 / D-091 |

### VisualizerEngine+WiringLogs.swift (93 lines) — `production-active`

BUG-006.1 instrumentation. Dual-write pattern: each helper logs once to `sessionRecorder?.log` AND once via `os.Logger`. The pattern that BUG-015's once-per-track diagnostic now follows.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `ResetStemPipelineCaller` enum (`.preFire / .trackChange / .other`) | `production-active` | `resetStemPipeline(for:caller:)` | BUG-006.1 disambiguator |
| `logWiringBuildPlanEnter`, `logWiringBuildPlanEarlyReturn`, `logWiringBuildPlanDone`, `logWiringBuildPlanFailed` | `production-active` | `_buildPlan` | BUG-006.1 |
| `logWiringResetStemPipelineEnter(title:caller:)` | `production-active` | `resetStemPipeline` | BUG-006.1 |
| `logTrackChangeObserved(event:identity:)` | `production-active` | `makeTrackChangeCallback` | BUG-006.1 |
| `logWiringStemCacheLookup(identity:)` | `production-active` | `resetStemPipeline` | BUG-006.1 |

### PhospheneApp.swift (104 lines) — `production-active`

`@main` App entry. **One** `SettingsStore` instance per D-091 / Failed Approach #55. Constructs `engine`, `permissionMonitor`, `accessibilityState` as `@StateObject`; constructs `spotifyOAuth = SpotifyOAuthTokenProvider.makeLive()` as `let`. Wires `SettingsStore.reducedMotion` → `AccessibilityState.applyPreference` via `.task` Combine subscription; wires `accessibilityState.reduceMotion` → `engine.applyAccessibility` via `.onChange`. Routes `phosphene://spotify-callback` to OAuth actor via `.onOpenURL`. `init()` runs `SettingsMigrator.migrate()`, `SessionRecorderRetentionPolicy.apply(policy:)`, and `DashboardFontLoader.resolveFonts(in:)`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PhospheneApp: App` | `production-active` | macOS app entry | D-091 |
| `@StateObject` `engine`, `permissionMonitor`, `settingsStore`, `accessibilityState` | `production-active` | Environment injection | Failed Approach #55 (single SettingsStore) |
| `spotifyOAuth: SpotifyOAuthTokenProvider` (private let, not `@StateObject` per actor non-ObservableObject) | `production-active` | `ConnectorPickerView` via environment + `.onOpenURL` | U.11 / D-069 |
| `SpotifyOAuthProviderKey: EnvironmentKey` + `EnvironmentValues.spotifyOAuthProvider` | `production-active` | `ConnectorPickerView` | U.11 |
| `init()` migration + retention + font load | `production-active` | App launch | QR.4 |

### ContentView.swift (140 lines) — `production-active`

Routing: outer permission gate (`PermissionMonitor.isScreenCaptureGranted`) → inner `SessionState` switch. Six top-level views per UX_SPEC. **BUG-015 publisher binding at line 85: `currentTrackIndexPublisher: engine.$currentTrackIndex.eraseToAnyPublisher()`**. Plan publisher at lines 87 + 103. Reduce-motion publisher at line 88. Dashboard snapshot publisher at line 91.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `ContentView: View` | `production-active` | `PhospheneApp.body` | UX_SPEC §3 |
| Permission gate | `production-active` | Outer ViewBuilder | UX_SPEC §3.1 |
| Six SessionState branches | `production-active` | `viewModel.state` switch | UX_SPEC §3 |
| `currentTrackIndexPublisher` (line 85) | `production-active` | `PlaybackView` | D-091 / BUG-006.2 / BUG-015 SwiftUI side |

### MusicKitFetcher.swift (80 lines) — `production-active` + filename drift (CA.5-FU-3)

**File contents:** `ITunesSearchFetcher: MetadataFetching, @unchecked Sendable`. iTunes Search API only — no MusicKit dependency. Top comment explicitly says: "ITunesSearchFetcher — Free, unauthenticated iTunes Search API for genre + duration. No developer account, no tokens, no MusicKit authorization needed."

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `ITunesSearchFetcher` final class | `production-active` | `VisualizerEngine+Audio.buildFetcherList()` | Always-active fetcher per CA.3 §App ↔ Audio boundary |
| Filename | **drift** | — | Recommend rename to `ITunesSearchFetcher.swift` per CA.5-FU-3 |

### Services/ (30 files, ~3,920 LoC)

#### SettingsStore.swift (212 lines) — `production-active`

The **single** app-wide `@MainActor final class SettingsStore: ObservableObject` per D-091 / Failed Approach #55. 11 `@Published` fields. `captureModeChanged: PassthroughSubject<Void, Never>` for audio-related changes. Generic encode / decode helpers for JSON-codec Codable values. `Keys` enum carries all UserDefaults keys.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `SettingsStore` (single instance) | `production-active` | App-wide via `@EnvironmentObject` | D-091; `SettingsStoreEnvironmentRegressionTests` |
| `@Published captureMode`, `sourceAppOverride`, `deviceTierOverride`, `qualityCeiling`, `includeMilkdropPresets`, `reducedMotion`, `excludedPresetCategories`, `showLiveAdaptationToasts`, `showUncertifiedPresets`, `sessionRecorderEnabled`, `sessionRetention` | `production-active` | `SettingsViewModel`, `CaptureModeReconciler`, `CaptureModeSwitchCoordinator`, `LiveAdaptationToastBridge`, `PhospheneApp.task` chains | U.8 |
| `captureModeChanged: PassthroughSubject<Void, Never>` | `production-active` | `CaptureModeReconciler`, `CaptureModeSwitchCoordinator` | D-052 / D-061 |
| `resetOnboarding()` | `production-active` | `SettingsViewModel` | — |
| `Keys` enum | `production-active` | Internal | UserDefaults keys |

#### DefaultPlaybackActionRouter.swift (517 lines) — `production-active`

Concrete `PlaybackActionRouter` per D-050 / U.6b. **All 7 protocol methods implemented + a static factory at line 488 (`live(engine:toastBridge:onShowPlanPreview:)`) that captures weak engine references for production wiring.** `AdaptationFields: Sendable` snapshot type returned by `adaptationFields(at:)`. Holds user-driven adaptation preference state (`familyBoosts`, `temporaryFamilyExclusions`, `sessionExcludedPresets`, `adaptationHistory` with capacity 8) separate from `VisualizerEngine.livePlan`. Tuning constants: family-boost cap 0.3 (idempotent max); family-exclusion window 600 s; ambient-hint window 90 s; override ceiling 8 s; undo capacity 8. Subscribes to `sessionManager.$state` to reset preferences on session start/end.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `AdaptationFields` struct | `production-active` | `VisualizerEngine.buildScoringContext` | — |
| `DefaultPlaybackActionRouter` | `production-active` | `PlaybackView.onAppear` (`PlaybackKeyMonitor.install`) | D-050 / U.6b |
| `moreLikeThis()` | `production-active` | Keyboard `+` | Family-boost 0.3 max + 30s extend + ack |
| `lessLikeThis()` | `production-active` | Keyboard `-` | 10-min family exclude + session preset exclude + 8s ceiling |
| `reshuffleUpcoming()` | `production-active` | Keyboard `R` | Lock past + reshuffle rest |
| `presetNudge(_:immediate:)` | `production-active` | Keyboard `→` / `←` / Shift+→ / Shift+← | D-074 diagnostic-aware; scorer-driven or alphabetical |
| `rePlanSession()` | `production-active` | Keyboard `⌘R` | Reshuffle all + preview |
| `undoLastAdaptation()` | `production-active` | Keyboard `Z` | Pop adaptationHistory; preserves preferences per D-058(b) |
| `toggleMoodLock()` (`@Published isMoodLocked: Bool`) | `production-active` | Keyboard `M`; ViewModels | — |
| `static live(engine:toastBridge:onShowPlanPreview:) -> DefaultPlaybackActionRouter` | `production-active` | `PlaybackView` | Wires weak engine refs |

#### PlaybackShortcutRegistry.swift (365 lines) — `production-active`

Declarative keyboard shortcut catalog. `ShortcutCategory` enum + `PlaybackShortcut: Identifiable` struct. Built at `PlaybackView.onAppear`. Consumed by `PlaybackKeyMonitor` for event routing and `ShortcutHelpOverlayView` for the help table. Includes optional developer shortcuts for BUG-007.4 bar-phase cycling, BUG-007.6 audio-latency tweak, Arachne spider easter egg toggle, preset debug cycling.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `ShortcutCategory` enum (`.playback / .liveAdaptation / .developer`) | `production-active` | Help overlay grouping | — |
| `PlaybackShortcut` struct | `production-active` | `PlaybackKeyMonitor.handle(event:)` | `matches(event:)` API |
| `PlaybackShortcutRegistry.shortcuts: [PlaybackShortcut]` | `production-active` | `PlaybackKeyMonitor`, help overlay | — |
| `shortcut(withID id:)` lookup | `production-active` | Help overlay | — |
| All seven router methods wired (lines 246, 280, 288, 296, 304, 312, 320, 328, 336, 344) | `production-active` | Per shortcut | U.6b complete |

#### CaptureModeSwitchCoordinator.swift (125 lines) — `production-active`

D-061(b,c) grace window. `@MainActor final class` owned by `PlaybackView` as `@State`. Subscribes to `SettingsStore.captureModeChanged`. On every non-`.localFile` mode switch: sets `VisualizerEngine.captureModeSwitchGraceWindowEndsAt = Date() + 5s` and raises `PlaybackErrorBridge.effectiveThresholdSeconds = 20` (from 15). After 5 s a `Task` calls `closeGraceWindow()` which restores both values. Consecutive `openGraceWindow()` calls cancel the prior task. `.localFile` mode gets no grace window. `CaptureModeSwitchEngineInterface` protocol provides the testability seam.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `CaptureModeSwitchEngineInterface: AnyObject` protocol | `production-active` | `VisualizerEngine` conforms via stub extension; test mocks | D-061(b) |
| `CaptureModeSwitchCoordinator` | `production-active` | `PlaybackView.@State` | — |
| `openGraceWindow()` / `closeGraceWindow()` / `handleModeChange()` | `production-active` | Internal + `SettingsStore.captureModeChanged` | — |
| `isGraceWindowActive` (read by tests) | `production-active` | `CaptureModeSwitchCoordinatorTests` | — |
| `graceWindowSeconds: TimeInterval = 5` | `production-active` | Internal | D-061(b) |

#### CaptureModeReconciler.swift (96 lines) — `production-active`

Live-switch path per D-052. Subscribes to `SettingsStore.captureModeChanged` and routes to `AudioInputRouter.switchMode(_:)`. `.systemAudio` → `.systemAudio`; `.specificApp` → `.application(bundleIdentifier:)`; `.localFile` → "coming later" info toast (no router call yet).

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `CaptureModeReconciler` | `production-active` | `PlaybackView` | D-052 |
| `reconcile()` | `production-active` | Internal subscriber | — |

#### LiveAdaptationToastBridge.swift (80 lines) — `production-active` + `unverified-claim` docstring

User-action ack toast bridge per U.6 Part C. `emitAck(_:)` gated on `phosphene.settings.visuals.showLiveAdaptationToasts` UserDefaults (default true for new installs). 2-second coalescing window. **Docstring drift:** see `unverified-claim` finding above — engine-event observation source mentioned in docstring is not wired in practice.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `LiveAdaptationToastBridge` | `production-active` | `DefaultPlaybackActionRouter` (11 call sites) | U.6 Part C |
| `emitAck(_:)` | `production-active` | All `DefaultPlaybackActionRouter` action methods | UserDefaults-gated + coalescing |
| Docstring at lines 1–14 | **`unverified-claim`** | — | CA.5-FU-2 |

#### MultiDisplayToastBridge.swift (82 lines) — `production-active` + field-level `production-orphan`

Wires `DisplayManager.onScreensAdded/Removed` to `ToastManager`. Screen added → info toast with "Move Phosphene there" action. Current-screen removed → warning toast + auto-move to primary. **Dead fields:** `coalesceTask: Task<Void, Never>?` and `pendingEvents: [String] = []` at lines 22–23 — declared but never read or written. See `production-orphan` finding above.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `MultiDisplayToastBridge` | `production-active` | `PlaybackView` | — |
| `coalesceTask`, `pendingEvents` fields | **`production-orphan`** | None | CA.5-FU-1 |

#### PlaybackErrorBridge.swift (122 lines) — `production-active`

UX_SPEC §9.4 audio-signal silence-error routing to `ToastManager` with condition-ID semantics. `silenceToastThresholdSeconds: 15` (raised to `silenceToastGraceWindowThresholdSeconds: 20` during capture-mode switch grace windows per D-061(b)). Replaces the older `SilenceToastBridge` which fired at 30 s without condition ID.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PlaybackErrorBridge` | `production-active` | `PlaybackView` | UX_SPEC §9.4 |
| `effectiveThresholdSeconds` (mutable; raised by `CaptureModeSwitchCoordinator`) | `production-active` | Self | D-061(b) |
| Constants `silenceToastThresholdSeconds`, `silenceToastGraceWindowThresholdSeconds` | `production-active` | Internal | UX_SPEC §9.4 |

#### PlaybackErrorConditionTracker.swift (45 lines) — `production-active`

Lightweight register of currently-asserted condition IDs. `assert(_:)` / `clear(_:)` / `isAsserted(_:)` / `reset()`. `PlaybackErrorBridge` calls assert/clear on condition lifecycle; tests call `isAsserted` without spinning up full `ToastManager`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PlaybackErrorConditionTracker` | `production-active` | `PlaybackErrorBridge` + tests | — |

#### NetworkRecoveryCoordinator.swift (122 lines) — `production-active`

D-061(d,e) network recovery. Subscribes to `ReachabilityMonitor.isOnlinePublisher`. On `false → true`, waits an additional 2 s (composing to 3 s total with monitor's 1 s debounce) then calls `SessionManager.resumeFailedNetworkTracks()`. Guards: `.preparing` state only; max 3 recovery attempts per session.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `NetworkRecoveryCoordinator` | `production-active` | `PreparationProgressView.@State` | D-061(d,e) |
| `recoveryDebounceSecs: 2`, `maxRecoveryAttempts: 3` | `production-active` | Internal | D-061(d,e) |

#### PresetScoringContextProvider.swift (58 lines) — `production-active`

Canonical builder of `PresetScoringContext` consumed by the Orchestrator (`DefaultPlaybackActionRouter.getScoringContext` closure wires to it). Resolves `DeviceTierOverride` (`.auto / .forceTier1 / .forceTier2`) against detected hardware tier. U.8 Part C.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PresetScoringContextProvider` | `production-active` | `DefaultPlaybackActionRouter`, ViewModels | U.8 |
| `effectiveTier`, `build(...)` | `production-active` | Internal | — |

#### PreparationETAEstimator.swift (97 lines) — `production-active`

Rolling EMA over per-stage durations (resolving / downloading / stemSeparation / caching). Value type (struct). Returns `nil` until `minSamplesRequired: 3` completions recorded. `emaAlpha: 0.3`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PreparationStage`, `StageCompletion`, `PreparationETAEstimator` | `production-active` | `PreparationProgressViewModel` (CA.6 scope) | — |

#### SpotifyOAuthTokenProvider.swift (393 lines) — `production-active`

U.11. `public actor SpotifyOAuthTokenProvider: SpotifyTokenProviding, SpotifyOAuthLoginProviding`. PKCE auth-code OAuth flow. `expiryMarginSeconds: 300`, `loginTimeoutSeconds: 300`, redirect URI `phosphene://spotify-callback`. Scopes `playlist-read-private playlist-read-collaborative`. `makeLive(urlSession:)` factory used by `PhospheneApp`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `SpotifyOAuthLoginProviding` protocol | `production-active` | `SpotifyConnectionViewModel` | U.11 |
| `SpotifyOAuthTokenProvider` actor | `production-active` | `PhospheneApp`, `ConnectorPickerView`, `SpotifyOAuthPlaylistConnector` | U.11 / D-069 |
| `acquire() / login() / handleCallback / logout / isAuthenticated / invalidate` | `production-active` | Connectors + view models | U.11 |

#### SpotifyOAuthPlaylistConnector.swift (44 lines) — `production-active`

Wraps a `PlaylistConnector` and remaps 403 (`spotifyLoginRequired`) to `spotifyPlaylistInaccessible` when the user is authenticated. U.11.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `SpotifyOAuthPlaylistConnector: PlaylistConnecting` | `production-active` | `ConnectorPickerView` (CA.6 scope) | U.11 |

#### SpotifyKeychainStore.swift (117 lines) — `production-active`

`SpotifyKeychainStoring: Sendable` protocol + concrete `SpotifyKeychainStore: @unchecked Sendable`. SecItem-backed refresh-token persistence. Default service `"com.phosphene.spotify"`, default account `"refresh_token"`. U.11.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `SpotifyKeychainStoring` protocol | `production-active` | `SpotifyOAuthTokenProvider` | U.11 |
| `SpotifyKeychainStore` | `production-active` | `SpotifyOAuthTokenProvider.makeLive()` | U.11 |

#### SpotifyURLParser.swift (69 lines) + SpotifyURLKind.swift (17 lines) — `production-active`

`SpotifyURLKind: Equatable` enum (`.playlist(id:) / .track / .album / .artist / .invalid`). `SpotifyURLParser` enum with static `parse(_:)` — handles HTTPS URLs (country subdomains, share tokens), `spotify:` URI scheme, common paste artifacts. Rejects podcast/show/episode types.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `SpotifyURLKind` | `production-active` | `SpotifyConnectionViewModel` | — |
| `SpotifyURLParser.parse(_:)` | `production-active` | `SpotifyConnectionViewModel` | — |

#### DisplayManager.swift (154 lines) — `production-active`

`@MainActor final class DisplayManager: ObservableObject`. NSScreen tracking + window-move coordination across multiple displays. Handles fullscreen quirk (exit → move → re-enter for cross-screen fullscreen) with 3 s timeout.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `DisplayManager` | `production-active` | `PlaybackView.@State`, `DisplayChangeCoordinator`, `MultiDisplayToastBridge` | D-061(a) |
| `attach(to:)`, `moveToSecondaryDisplay()`, `moveToPrimaryDisplay()` | `production-active` | UI shortcuts; `MultiDisplayToastBridge` action | — |
| `onScreensAdded`, `onScreensRemoved` callbacks | `production-active` | `MultiDisplayToastBridge` | — |

#### DisplayChangeCoordinator.swift (133 lines) — `production-active`

D-061(a). Subscribes independently to `DisplayManager.$allScreens` and `.$currentScreen` via Combine. On screen add/remove/move, clears `FrameBudgetManager`'s rolling frame buffer (transient post-reparent frames don't poison ML scheduler's "clean right now?" signal). Does NOT modify session state, live plan, or preset ID.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `DisplayChangeCoordinator` | `production-active` | `PlaybackView.@State` | D-061(a) |
| `Event` enum (`.screenAdded / .screenRemoved(wasActive:) / .windowMovedToScreen`) | `production-active` | Tests | — |
| `lastEvent`, `lastEventAt` | `production-active` | Tests | — |

#### FullscreenObserver.swift (75 lines) — `production-active`

`@MainActor final class FullscreenObserver: ObservableObject`. Wraps `NSWindow.didEnterFullScreenNotification` / `didExitFullScreenNotification`. Published `isFullscreen: Bool`. Used by `DisplayManager.moveWindow(to:)` to handle the fullscreen quirk.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `FullscreenObserver` | `production-active` | `DisplayManager`, view models | — |

#### AccessibilityState.swift (119 lines) — `production-active`

`@MainActor final class AccessibilityState: ObservableObject`. Combines `NSWorkspace.accessibilityDisplayShouldReduceMotion` (system flag) with in-app `ReducedMotionPreference` from `SettingsStore` into a single `reduceMotion: Bool`. Distributes to engine via `VisualizerEngine.applyAccessibility(_:)`. Per-frame gating queries `shouldExecuteMVWarp(presetEnabled:)`, `shouldExecuteSSGI`. Beat-pulse amplitude clamped to 0.5 in reduced-motion mode, 1.0 otherwise. U.9 / D-054.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `AccessibilityState` | `production-active` | `PhospheneApp.@StateObject`; `ContentView`; per-frame render decisions | U.9 / D-054 |
| `@Published reduceMotion`, `beatAmplitudeScale`, `systemReduceMotion` | `production-active` | `engine.applyAccessibility`, view models | — |
| `shouldExecuteMVWarp`, `shouldExecuteSSGI` | `production-active` | Render gating | D-054 |
| Beat amplitude constants 0.5 / 1.0 | `production-active` | Internal | U.9 |

#### AccessibilityLabels.swift (65 lines) — `production-active`

Centralised VoiceOver label/hint lookup. Resolves localized strings from `Localizable.strings` under `"a11y.*"` key namespace. Factory methods for connector tiles, track info cards, toasts.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `AccessibilityLabels` static enum | `production-active` | Views (CA.6 scope) | U.9 |

#### LocalizedCopy.swift (153 lines) — `production-active`

App-layer bridge from `UserFacingError` enum to localized user-facing strings. `LocalizedCopy.string(for:)` / `bodyString(for:)` / `cta(_:)` / `containsJargon(_:)`. Jargon deny-list (11 forbidden terms: MPSGraph, FFT, IRQ, DRM, NSURLError, sandbox, G-buffer, SSGI, MIR, StemCache, AudioHardware) enforces UX_SPEC §9.5.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `LocalizedCopy` enum | `production-active` | Views + ViewModels (CA.6 scope), tests | UX_SPEC §9.5 |
| `jargonDenyList` | `production-active` | `containsJargon` | UX_SPEC §9.5 |

#### ReachabilityMonitor.swift (93 lines) — `production-active`

`@MainActor protocol ReachabilityPublishing: AnyObject` + concrete `ReachabilityMonitor: ObservableObject, ReachabilityPublishing` + test-double `StubReachabilityMonitor`. 1 s debounce on `NWPathMonitor` to avoid flapping.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `ReachabilityPublishing` protocol | `production-active` | `NetworkRecoveryCoordinator`, tests | — |
| `ReachabilityMonitor` concrete | `production-active` | `PhospheneApp` / `PreparationProgressView` | — |
| `StubReachabilityMonitor` | `production-active` | Tests | — |

#### PlaybackKeyMonitor.swift (64 lines) — `production-active`

`@MainActor final class`. Installs `NSEvent.addLocalMonitorForEvents` for in-session keyboard shortcuts. Lives only during `.playing` state.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PlaybackKeyMonitor` | `production-active` | `PlaybackView.onAppear / onDisappear` | — |
| `install(registry:)`, `uninstall()`, `handle(event:registry:)` | `production-active` | Internal | — |

#### FirstAudioDetector.swift (90 lines) — `production-active`

`@MainActor final class: ObservableObject`. Monitors `AudioSignalState` and fires `hasDetectedAudio` (latch) once audio is sustained for ≥ 250 ms. Implements UX_SPEC §6.3 survival rules: `.suspect` does not cancel; `.silent`/`.recovering` cancel; second `.active` does not restart.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `FirstAudioDetector` | `production-active` | `ReadyViewModel` (CA.6 scope) | UX_SPEC §6.3 |
| `@Published hasDetectedAudio: Bool` | `production-active` | `ReadyViewModel` | — |
| 250 ms confirmation timer | `production-active` | Internal | UX_SPEC §6.3 |

#### DelayProviding.swift (28 lines) — `production-active`

`DelayProviding: Sendable` protocol. `RealDelay` (production) + `InstantDelay` (test). Testability seam for retry-loop tests.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `DelayProviding`, `RealDelay`, `InstantDelay` | `production-active` | `FirstAudioDetector`, `AppleMusicConnectionViewModel`, `SpotifyConnectionViewModel` (CA.6 scope) | — |

#### OnboardingReset.swift (20 lines) — `production-active`

Static UserDefaults-key reset. Currently the only key is `"phosphene.onboarding.photosensitivityAcknowledged"`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `OnboardingReset.resetAllOnboardingState(in:)` | `production-active` | `SettingsViewModel` (CA.6 scope) | — |

#### SettingsMigrator.swift (52 lines) — `production-active`

One-shot UserDefaults key migration on app launch. One mapping today: `"phosphene.showLiveAdaptationToasts"` → `"phosphene.settings.visuals.showLiveAdaptationToasts"`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `SettingsMigrator.migrate(in:)` | `production-active` | `PhospheneApp.init` | — |

#### SessionRecorderRetentionPolicy.swift (143 lines) — `production-active`

Session-folder pruning at app launch. 60 s active-session guard. Supports `.keepAll / .lastN10 / .lastN25 / .oneDay / .oneWeek` policies.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `SessionRecorderRetentionPolicy.apply(policy:sessionsDir:now:wallClock:)` | `production-active` | `PhospheneApp.init` | — |
| 60 s active guard, 10 / 25 limits, 86_400 / 604_800 s cutoffs | `production-active` | Internal | — |

### Permissions/ (3 files)

#### PermissionMonitor.swift (54 lines) — `production-active`

`@MainActor final class: ObservableObject`. `@Published isScreenCaptureGranted: Bool`. Reads permission on init via `provider.isGranted()`; refreshes on `NSApplication.didBecomeActiveNotification`. Owned by `PhospheneApp` as `@StateObject`; injected as `@EnvironmentObject`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PermissionMonitor` | `production-active` | `PhospheneApp.@StateObject`; `ContentView.@EnvironmentObject` | — |
| `refresh()` | `production-active` | NotificationCenter sink | — |

#### PhotosensitivityAcknowledgementStore.swift (40 lines) — `production-active`

UserDefaults-backed photosensitivity acknowledgement. Key `"phosphene.onboarding.photosensitivityAcknowledged"`. Injectable defaults suite for tests.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PhotosensitivityAcknowledgementStore` | `production-active` | `PhotosensitivityNoticeView` (CA.6 scope) | U.2 |
| `isAcknowledged`, `markAcknowledged()` | `production-active` | View | U.2 |

#### ScreenCapturePermissionProvider.swift (21 lines) — `production-active`

`ScreenCapturePermissionProviding: Sendable` protocol + `SystemScreenCapturePermissionProvider` concrete. `isGranted() -> Bool` backed by `CGPreflightScreenCaptureAccess()`. Never prompts (no `CGRequestScreenCaptureAccess` in this file).

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `ScreenCapturePermissionProviding` | `production-active` | `PermissionMonitor`, tests | — |
| `SystemScreenCapturePermissionProvider` | `production-active` | `PermissionMonitor` default | — |

### Models/ (2 files)

#### PhospheneToast.swift (78 lines) — `production-active`

`PhospheneToast: Identifiable, Equatable, Sendable` value type. `Severity` (`.info / .warning / .degradation`), `Source` (`.signalState / .liveAdaptationAck / .displayChange / .degradation / .generic`), `ToastAction { label: String, handler: @MainActor @Sendable () -> Void }`. Default duration 4 s; `TimeInterval.infinity` for manual-dismiss-only.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PhospheneToast` + nested types | `production-active` | All toast emit sites; `ToastManager` (CA.6 scope) | — |

#### SettingsTypes.swift (66 lines) — `production-active`

App-layer settings value-type enums + `SourceAppOverride` struct.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `CaptureMode`, `DeviceTierOverride`, `ReducedMotionPreference`, `SessionRetentionPolicy` | `production-active` | `SettingsStore`, view models | — |
| `SourceAppOverride: Codable, Equatable, Hashable, Sendable` | `production-active` | `SettingsStore.sourceAppOverride` | — |

---

## Verification of BUG-015 wire shape (CA.5-specific)

The kickoff requires this section. BUG-015 was filed by CA.4 on 2026-05-20 and Resolved on 2026-05-21 in three commits (`b3f1efd9`, `5efc6a90`, `bb5e36ef`). CA.5 is the first independent audit pass to read the wire from the App-layer side.

**The wire shape matches the BUG-015 Resolved-field design notes byte-for-byte.** Verified:

1. **`runOrchestratorLiveUpdate(mir:)` declared at `VisualizerEngine+Orchestrator.swift:287`** — internal func; takes `mir: MIRPipeline` parameter; reads `mir.elapsedSeconds` and `mir.latestStructuralPrediction`.

2. **Called from `VisualizerEngine+Audio.swift:184`** — at the end of `processAnalysisFrame`, after `runMoodClassifier` (so `lastClassifiedMood` is fresh on every wire tick). Comment block at lines 178–183 explains the gate-after-mood ordering (mood is allowed to lag — defaults to `.neutral` until first classification at ~3 s).

3. **Cadence gate `analysisFrameCount % Self.orchestratorWireFrameDivisor == 0` at line 288** — `orchestratorWireFrameDivisor: Int = 30` declared at line 263. At ~94 Hz analysis queue → ~3.1 Hz wire firing. Compatible with the 30 s per-track mood-override cooldown enforced by `DefaultLiveAdapter.cooldownAdaptation(...)` per D-080 rule 3 (CA.4-verified at `LiveAdapter.swift:362-381`).

4. **Off-plan skip path at lines 298–303:** `if snapshot.hasPlan, snapshot.trackIndex == nil { return }`. The comment explains this is the correct behaviour — when `livePlan != nil` but the live track has no plan index (cover / remaster / encoding-different variant), neither session-mode patching nor reactive-mode behaviour applies; skip silently and resume on next track change.

5. **`liveTrackPlanIndex: Int?` written in `VisualizerEngine+Capture.swift:131`** under `orchestratorLock`. The resolution happens before the MainActor task at line 129 (`let resolvedPlanIndex = self.indexInLivePlan(matching: event.current)`), so the orchestrator wire sees the new index on the next analysis tick (~3 Hz), not on the next MainActor frame. Field declared at `VisualizerEngine.swift:505`, guarded by `orchestratorLock`.

6. **`lastClassifiedMood: EmotionalState` written in `VisualizerEngine+Audio.swift:432`** (`publishMoodResult`) under `orchestratorLock`. Field declared at `VisualizerEngine.swift:513` with default `.neutral` (so the wire is well-defined before the first mood frame fires). Same lock that guards `livePlan` and `liveTrackPlanIndex` so a single `orchestratorLock.withLock` acquisition snapshots the full input set for `applyLiveUpdate(...)`.

7. **`orchestratorWireLoggedThisTrack: Bool` reset on track change at `VisualizerEngine+Capture.swift:137`** under `orchestratorLock`. Field declared at `VisualizerEngine.swift:529`. Comment block at lines 515–528 documents the latch pattern (once-per-track diagnostic, dual-write pattern matching `VisualizerEngine+WiringLogs.swift`).

8. **Once-per-track diagnostic at `VisualizerEngine+Orchestrator.swift:305–331`** — emits one `Orchestrator: wire active (mode=… planIdx=… elapsedTrackTime=…s)` line via both `sessionRecorder?.log(msg)` AND `logger.info("\(msg)")` the first time the wire reaches `applyLiveUpdate(...)` on each track. Latch logic at lines 318–322 uses `orchestratorLock.withLock` to test-and-set atomically. Closes the BUG-015 doc-vs-runtime validation gap noted in the Resolved field (existing Orchestrator `logger.info(...)` lines never reach `session.log`).

9. **The 30 s mood-override cooldown is preserved** — the wire calls `applyLiveUpdate(...)` which calls `liveAdapter.adapt(...)` which calls `cooldownAdaptation(...)` per D-080. CA.4 verified the cooldown at `LiveAdapter.swift:362–381`. CA.5 verified the wire does not bypass it; the path is straight through.

10. **The regression test `PhospheneAppTests/OrchestratorWiringRegressionTests.swift` is present and load-bearing.** Two `@Test` methods:
    - `test_visualizerEngineAudio_wiresOrchestratorLiveUpdate` — reads `VisualizerEngine+Audio.swift`, strips comments, asserts the file contains either `applyLiveUpdate(` or `runOrchestratorLiveUpdate(`. Either spelling is sufficient evidence that the wire reaches the live-adaptation pipeline; if both names disappear, the wire is dead again and the test fails.
    - `test_appLayer_hasProductionCallSiteForApplyLiveUpdate` — enumerates `PhospheneApp/` Swift files, strips comments, counts files containing `applyLiveUpdate(`. Subtracts the declaration site (`VisualizerEngine+Orchestrator.swift`). If zero remain, BUG-015 has regressed.

   The test strips line + block comments before counting so doc-comment mentions don't satisfy the assertion (the CA.4 grep found four doc-comment references in unrelated files; this regression test must not be fooled by the same).

**Verification criterion #2 from the BUG-015 entry** confirms the wire fires in production: Matt's session capture `~/Documents/phosphene_sessions/2026-05-21T14-19-32Z/session.log` shows two `Orchestrator: wire active` lines (one pre-first-track-change at 8.2 s elapsed, one post-track-change at 0.0 s elapsed proving the per-track latch reset). 7,519 frames + 23 stem dumps in that session confirm the full audio path was alive.

**Verdict: BUG-015 wire shape is structurally correct. No App-layer regression risk identified.**

---

## Verification of BUG-012-i1 instrumentation (CA.5-specific)

The kickoff requires this section. Per CA.5 Hard Rules the eight BUG-012-i1 instrumented files are **read-only**. CA.5 read them freely; no edits made.

**BUG-012-i1 probe call sites verified intact across all eight instrumented files.** 48 references total via `grep -rn "BUG012Probe" PhospheneEngine/Sources PhospheneApp PhospheneEngine/Tests --include="*.swift"`. Breakdown:

| File | Probe sites | Status |
|---|---|---|
| `PhospheneEngine/Sources/Shared/BUG012Probe.swift` | The probe module itself | `production-active` |
| `PhospheneEngine/Sources/ML/StemFFT.swift` | Dispatch-ID allocation; in-flight counters; lock-await / lock-release log lines | Intact |
| `PhospheneEngine/Sources/ML/StemFFT+GPU.swift` | `runForwardGraph()` — the documented EXC_BAD_ACCESS crash site | Intact |
| `PhospheneEngine/Sources/ML/StemSeparator.swift` | UMA buffer-write lock-guard probes | Intact |
| `PhospheneEngine/Sources/Renderer/MLDispatchScheduler.swift` | Line 190 — `BUG012Probe.log(...)` for scheduler decision tracking | Intact (extra file beyond the kickoff's explicit list; consistent with the broader BUG-012-i1 instrumentation tranche) |
| `PhospheneEngine/Tests/PhospheneEngineTests/ML/BUG012ConcurrencyTest.swift` | The concurrency test exercising the suspected race surface | Intact |
| **`PhospheneApp/VisualizerEngine.swift`** | Line 709 `BUG012Probe.recordVisualizerEngineInit()`; line 718 (`deinit`) `BUG012Probe.recordVisualizerEngineDeinit()` | Intact |
| **`PhospheneApp/VisualizerEngine+Stems.swift`** | `runStemSeparation` timer entry (line 89); MainActor self=nil notice (line 96); no-scheduler queue (line 102); stemQueue.async self=nil notices (lines 104, 129, 139); `performStemSeparation` enter (line 157); separator.separate CALL (line 185) / RETURN (line 193); exit-with-outcome at multiple sites (`warmup-skip`, `silence-skip`, `ok`, `threw`, `no-separator`) | Intact |

The path is clear for the next BUG-012 reproduction. No edits were applied to instrumented files in this audit per Hard Rules.

CA.2's audit observation stands: BUG-012 step 2 (diagnosis) blocks on a fresh reproduction. CA.5's read of every BUG-012-instrumented App-layer code path produced no new candidate root cause beyond what CA.2 already documented.

---

## BUG-016 App-layer surface inventory (open diagnosis aid)

The kickoff requires inventory of the Lumen Mosaic apply path without proposing a fix. The next BUG-016 reproduction with concrete symptom is the load-bearing diagnostic step. CA.5 documents the App-layer surface and the candidate failure modes the inventory makes more / less likely.

**The apply path lives inside `case .rayMarch:` in `VisualizerEngine+Presets.swift:166-178`**, NOT a separate `.lumenMosaic:` case (the kickoff used loose phrasing). The exact code:

```swift
if desc.name == "Lumen Mosaic" {
    if let engine = LumenPatternEngine(device: context.device) {
        lumenPatternEngine = engine
        pipeline.setDirectPresetFragmentBuffer3(engine.patternBuffer)
        pipeline.setMeshPresetTick { [weak engine] features, stems in
            engine?.tick(features: features, stems: stems)
        }
    } else {
        logger.error(
            "LumenPatternEngine: failed to allocate slot-8 buffer for preset '\(desc.name)'"
        )
    }
}
```

Plus the per-track palette refresh in `VisualizerEngine+Stems.swift:518-567` (`resetStemPipeline(...)` → `refreshLumenPaletteForTrack(...)`).

**Inventory observations relative to the BUG-016 candidate failure modes** (per KNOWN_ISSUES.md §Actual behavior):

- **Slot-8 binding is correct.** `pipeline.setDirectPresetFragmentBuffer3(engine.patternBuffer)` binds slot 8 per CLAUDE.md GPU Contract / D-LM-buffer-slot-8. Reset on preset switch clears the binding to `nil` at `+Presets.swift:69` so no stale slot-8 buffer from a previous Lumen Mosaic activation leaks across preset switches. Conclusion: **failure mode #3 (visual artifacts due to slot-8 binding bug) is less likely** from this inventory alone, but not ruled out — a binding race could still occur if `LumenPatternEngine` deallocates between binding and draw call.
- **Init can return `nil`.** `LumenPatternEngine(device: context.device)` returns `LumenPatternEngine?`. Failure logs to `os.Logger` only — no `session.log` entry — so silent init failure produces "rendered something, but not what was expected" (the most-consistent reading of Matt's `2026-05-21T13-58-07Z` capture per KNOWN_ISSUES.md line 35). Recommend adding a `sessionRecorder?.log(...)` line on the failure branch so the next BUG-016 reproduction can confirm/rule out init failure from session.log alone.
- **Per-frame tick uses `[weak engine]`.** If `lumenPatternEngine` is overwritten between binding and draw (e.g. by a concurrent preset switch), the closure's weak capture goes nil, the tick becomes a no-op, and slot 8 freezes at the last-flushed state. The audit observes the field assignment at `+Presets.swift:168` happens on MainActor inside `applyPreset`, and all consumers (`resetStemPipeline` via `refreshLumenPaletteForTrack`) also run on MainActor. No cross-actor write detected.
- **No App-layer regression test exercises the Lumen Mosaic apply path end-to-end.** `LumenPatternEngineTests` covers the GPU struct stride (`568` bytes per `LumenPatternState.stride`) only. Adding an integration test that constructs `VisualizerEngine` → calls `applyPreset(loader.preset(named: "Lumen Mosaic"))` → asserts `lumenPatternEngine != nil` and `pipeline.directPresetFragmentBuffer3 != nil` would catch silent init failure and binding regression. **This is a CA.6-or-followup question, not a CA.5 fix.**

**Verdict:** the App-layer Lumen Mosaic plumbing is structurally sound. The inventory does NOT reveal a root cause. The most-instructive next step for BUG-016 diagnosis is the concrete reproduction with symptom characterised (per the KNOWN_ISSUES.md verification-criteria #1). After the symptom is known, the App-layer suspects narrow to: (a) silent init failure (recommend log-line addition); (b) slot-8 binding race (low probability per inventory); (c) per-frame tick capture chain (low probability per inventory); (d) palette refresh on track change reading stale `stemCache` (possible — the `stemCache?.trackProfile(for: identity)?.mood` lookup falls back to mood-centre `(0,0)` when missing, biasing palette selection toward neutral-quadrant anchors).

Cross-linked from BUG-016 §Fix scope as the App-layer landing reference.

---

## Cross-references

### Updates needed in CLAUDE.md

No edits to CLAUDE.md applied in this increment. The `What NOT To Do` rules referencing the App layer are all current:

- The "Do not call `applyLiveUpdate` (mood-override path) without a per-track cooldown" rule — verified the cooldown is preserved by the BUG-015 wire (see §Verification-of-BUG-015-wire-shape rule 9 above).
- The "Do not instantiate a second `SettingsStore`" rule — verified clean (see Top Finding 8 above; `SettingsStoreEnvironmentRegressionTests` is the regression gate).
- The "Do not match plan entries against the live track via lowercased title+artist string" rule — verified BUG-006.2 fix is in place at `+Capture.swift:166` via `canonicalTrackIdentity(matching:)`; `currentTrackIndex` is published via the plan walker (`indexInLivePlan(matching:)`).
- The "Do not assume the test fixture render path exercises the same GPU dispatch path the live app uses" rule (Failed Approach #66) — verified the live Ferrofluid Ocean path is reset on every applyPreset (`+Presets.swift:72 — setMeshGBufferEncoder(nil)`) so the SDF path is the live path post-round-57.
- The "Do not write the literal `44100`" rule (D-079) — App-layer reads `tapSampleRate` via the NSLock-guarded property at `VisualizerEngine.swift:253–255`; the only literals in `VisualizerEngine+Stems.swift` (`StemSeparator.modelSampleRate` at line 214) and `VisualizerEngine.swift:233` (`StemSampleBuffer(sampleRate: Double(StemSeparator.modelSampleRate), ...)`) reference the model constant, not the tap.
- The "App-layer services use `Logger(subsystem:category:)` directly, not `Logging.session`" rule (U.11) — verified across all audited files. Every App-layer file uses `private let logger = Logger(subsystem: "com.phosphene.app", category: "...")`.
- The "URLProtocol stub tests require `@Suite(.serialized)`" rule (U.10) — verified the only URLProtocol-stub-using App test (`SpotifyOAuthTokenProviderTests.swift:98`) has the annotation.

### Updates needed in ARCHITECTURE.md

Applied in this increment as doc-only corrections:

1. **§Module Map PhospheneApp/** block extended. The pre-CA.5 block listed 15 of 49 engine-adapter files. The post-CA.5 block lists every file with a one-line behavioural description, mirroring the CA.4 fix for the Orchestrator block. Categories: top-level files (14), `Services/` (30), `Permissions/` (3), `Models/` (2). The `Views/` and `ViewModels/` sub-blocks are flagged in the audit doc as CA.6 scope.

2. **§Module Map Tests/PhospheneApp/** block added. Lists the load-bearing regression / contract tests: `OrchestratorWiringRegressionTests`, `SettingsStoreEnvironmentRegressionTests`, `PlaybackChromeIndexBindingTests`, `DefaultPlaybackActionRouterTests`, `CaptureModeSwitchCoordinatorTests`, `NetworkRecoveryCoordinatorTests`, `SpotifyConnectionViewModelTests`, `SpotifyKeychainStoreTests`, `SpotifyOAuthTokenProviderTests`, `PresetScoringContextProviderTests`, `LiveAdaptationToastBridgeTests`, `AppleMusicConnectionViewModelTests`, `PlaybackErrorBridgeTests`, `PlaybackErrorConditionTrackerTests`, `SessionRecorderRetentionPolicyTests`, `SettingsMigratorTests`. The CA.6 audit will inventory VM-side test files.

3. **§UI Layer** — minor: `SessionStateViewModel` description (line 224) extended to note that it also surfaces `reduceMotion` from `accessibilityState`, matching the actual constructor signature `init(sessionManager:accessibilityState:)`. Not blocking — clarification only.

No other ARCHITECTURE.md changes needed.

### Updates needed in ENGINEERING_PLAN.md

Applied:

1. **Phase CA section:** register `CA.5 (App-layer, engine-adapter slice)` as ✅ Landed under the existing Phase CA block. CA.6 added as Pending.
2. **Recently Completed:** add the CA.5 entry mirroring the CA.1 / CA.2 / CA.3 / CA.4 shape — file count, verdict counts, top findings, doc-drift corrections applied, plus the BUG-015 wire-shape verification + BUG-012-i1 instrumentation-intactness verification outcomes.

### Updates needed in DECISIONS.md

No DECISIONS.md edits needed in this increment. Every cited decision (D-046, D-049, D-050, D-052, D-053, D-054, D-057, D-058, D-061, D-069, D-070, D-074, D-079, D-080, D-088, D-091, D-095, D-097, D-LM-buffer-slot-8, D-LM-palette-library) was verified against current code with no contradictions.

### Updates needed in source-file comments

None applied in this increment. Two candidate cleanup items registered as CA.5-FU-2 (LiveAdaptationToastBridge docstring) and CA.5-FU-3 (MusicKitFetcher → ITunesSearchFetcher file rename); neither is a behavioural change so each could fold into any future App-layer-adjacent commit.

### New BUG entries

**None filed in this increment.** BUG-015 (the only App-layer-class `broken-but-claimed` finding in scope) was filed by CA.4 and Resolved 2026-05-21. CA.5 verified the resolution; no new defect filings needed.

### KNOWN_ISSUES.md sweep

No retroactive `Resolved` entries identified. No existing Open entries reproduced as no-longer-applicable.

---

## Follow-up Backlog

Findings surfaced by CA.5 that are *not* corrected in this audit increment. Each row is a candidate follow-up increment with enough scope to act on cold. Per the kickoff's audit-only discipline, fixes ship as separate increments scheduled whenever Matt prioritises them.

Items are greppable as `CA\.5-FU-\d+`. CA.6 (Views + ViewModels) is registered here as the natural continuation since the kickoff's recommended sub-scope split deferred it.

| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA.5-FU-1** | Decide the fate of `MultiDisplayToastBridge.coalesceTask` + `pendingEvents` field-level production-orphans (`MultiDisplayToastBridge.swift:22–23`). Two options: (a) **implement the coalescing** (handler appends to `pendingEvents`; a Task fires after 0.5 s and enqueues one toast with N-message summary; cancels and restarts on each new event) — matches the line-21 comment intent; (b) **delete both fields** and the line-21 comment — display hot-plug events arrive at human-scale cadence on Macs so the practical risk of un-batched toasts is low. Option (b) is a < 5-line change; option (a) needs ~30 lines + a test. Bundle with any future App-layer commit. | The field-level orphan is closed: either fields are consumed by working coalescing logic with a test, OR fields + comment are removed. Engine + app builds clean; SwiftLint zero violations. | <1 | Ready now |
| **CA.5-FU-2** | ✅ **Closed 2026-05-21** (Matt picked **option (b)** — stay invisible). Engine-driven adaptations intentionally do NOT toast — the visual change itself is the user-visible feedback per UX_SPEC §7.4 ("on keystroke"). Toast surface is reserved for user-initiated playback-action acknowledgements. Docstring at `LiveAdaptationToastBridge.swift:1-14` + class-level doc at `:22-26` rewritten to drop the "engine events" observation source and clarify `emitAck(_:)` is for user-action acks only. No behavioural change. | Closed. | <1 | ✅ Resolved 2026-05-21 |
| **CA.5-FU-3** | Rename `PhospheneApp/MusicKitFetcher.swift` to `PhospheneApp/ITunesSearchFetcher.swift` so the filename matches the contained `ITunesSearchFetcher` class. The file's top comment already states explicitly that there is no MusicKit dependency. Also: update the four pbxproj sections (`PBXBuildFile`, `PBXFileReference`, `PBXGroup`, `PBXSourcesBuildPhase`) per the U.11 learning. Verify `xcodebuild -scheme PhospheneApp build` passes. | File renamed; pbxproj updated; engine + app builds clean; SwiftLint zero violations. ARCHITECTURE.md Module Map updated to reflect the new filename. | <1 | Ready now |
| **CA.5-FU-4 (== CA.6)** | ✅ **Closed 2026-05-21.** CA.6 audit landed as [`docs/CAPABILITY_REGISTRY/APP_VIEWS.md`](APP_VIEWS.md) (commits `8afaddbd` audit doc + `bd2e9ae3` ARCHITECTURE.md / ENGINEERING_PLAN.md drift corrections). 59 files / 8,285 LoC; 58 of 59 `production-active`; zero `broken-but-claimed`; three small follow-ups (CA.6-FU-1/2/3) all closed same-day 2026-05-21. Four kickoff-required verifications all clean (PlaybackChromeViewModel BUG-015 / D-091 consumer chain; D-091 single-SettingsStore enforcement; DASH.7 dashboard surface against D-088/D-089; U.10/U.11 timing-margin compliance). The App layer is now fully closed. | Closed. | 1–2 | ✅ Resolved 2026-05-21 |
| **CA.1-FU-1 status update (now superseded by BUG-015 fix's actual shape)** | The BUG-015 fix routes `liveBoundary` from `mirPipeline.latestStructuralPrediction` (option (b) from CA.1's framing, NOT option (a) as CA.4 recommended). The per-frame `StructuralAnalyzer` chain in `MIRPipeline.process` now has a runtime consumer — the audio-callback gate-to-prep-time fix is no longer the right action. CA.1-FU-1 should close as `superseded`. The wire is doing what option (b) intended. | CA.1-FU-1 closed in `docs/CAPABILITY_REGISTRY/DSP_MIR.md §Follow-up Backlog` and `docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md §Follow-up Backlog`. No code change required. | <1 | Ready now (doc-only update to two prior audit docs) |

**Bundling recommendation.** CA.5-FU-1 + CA.5-FU-3 are < 1 session combined and would not bloat any commit. CA.5-FU-2 is a product call and should be surfaced to Matt before scheduling work. CA.5-FU-4 (= CA.6) is the natural next-priority audit increment. The CA.1-FU-1 supersede update is a 2-line doc edit and folds into the next CA-adjacent commit.

**Priority order if Matt picks one this week:** **CA.5-FU-4 (CA.6)**. The Views + ViewModels presentation slice is the largest unaudited surface in the codebase by file count (59 files) and the home of the U.10 / U.11 flake cluster. The audit format continues to produce findings; finishing the App layer closes a significant scope before CA-Renderer / CA-Audio / CA-Presets.

---

## Approach validation

**What worked.**

- **Direct reads + parallel Explore agents both scaled.** The engine-adapter core (12 `VisualizerEngine+*` extensions + `PhospheneApp.swift` + `ContentView.swift` + `MusicKitFetcher.swift` = 15 files, ~4,200 LoC, including the biggest single file at 773 lines) was read directly with no token overflow issues. The 30 `Services/` + 5 `Permissions/` + `Models/` files (~3,800 LoC) were batched across three parallel Explore agents; each agent took ~1 minute and produced complete per-file reports. **Total Pass 1 wall-clock: ~3 minutes** for ~8k LoC. CA.3 + CA.4's "direct reads scale to ≤ 5k LoC" rule expanded cleanly to ~8k with the agent supplement.

- **Pass 0 BUG-status cross-check still cheap insurance.** Every BUG cited in the CA.5 kickoff (BUG-015 Resolved, BUG-016 Open, BUG-012 Open, BUG-001 Open, BUG-013 Open) matched `KNOWN_ISSUES.md` verbatim. No stale citation found. The Pass 0 step took ~2 minutes and would have surfaced any drift before the audit committed scope.

- **The cited-grep rule for production-orphan claims fired once and produced the audit's most-confident field-level finding.** `MultiDisplayToastBridge.coalesceTask` + `pendingEvents` — grep returned exactly two declaration sites and zero consumers across the App layer and App tests. Same shape as CA.4-FU-1's `transitionPolicy`. Falsifiable without auditor interpretation.

- **The visibility-verification grep caught one Explore agent over-assertion.** The agent's report on `SpotifyOAuthTokenProvider.swift` claimed `public protocol SpotifyOAuthLoginProviding: AnyObject, Sendable` — verified against `grep -nE "^public|^[[:space:]]+public" file` which confirmed the visibility (10 public symbols total, 1 protocol, 1 actor, 8 methods). All other audited public claims verified clean. The rule from CA.2 / CA.3 / CA.4 — visibility-verify before trusting an agent's report — held.

- **The BUG-015 wire-shape verification (the kickoff's specifically-requested section) produced 10 concrete byte-level confirmations.** Each design note from the Resolved field has a matching code citation. The regression test's two `@Test` methods are load-bearing for any future regression. The audit's confidence that BUG-015 is correctly fixed is high.

- **The BUG-016 App-layer inventory was bounded and useful.** The audit did not attempt diagnosis but produced four narrower-than-five candidate failure modes for the next reproduction to discriminate, plus one concrete recommendation (add `sessionRecorder?.log(...)` on the `LumenPatternEngine` init-failure branch). Future BUG-016 work has a clearer launch pad.

**What didn't.**

- **The kickoff's loose phrasing on "applyPreset .lumenMosaic:"** was misleading. Lumen Mosaic is gated by `if desc.name == "Lumen Mosaic"` inside `case .rayMarch:`, not by a separate `.lumenMosaic:` switch case. The audit caught the difference but a future kickoff should be more precise about whether a finding lives in a switch case or inside one. Same shape as CA.3's "kickoff prompt staleness" observation, but at the *phrasing* level rather than the *fact* level.

- **The kickoff's "8 instrumented files" claim** was slightly off — there are actually 8 files (`StemFFT.swift`, `StemFFT+GPU.swift`, `StemFFT+CPU.swift` via inheritance, `StemSeparator.swift`, `BUG012Probe.swift`, `BUG012ConcurrencyTest.swift`, `VisualizerEngine.swift`, `VisualizerEngine+Stems.swift`) **plus** `MLDispatchScheduler.swift` (one BUG012Probe call at line 190 outside the audit's documented set). The kickoff didn't list MLDispatchScheduler explicitly. The audit treated it as instrumented anyway (read-only) since it's clearly part of the same BUG-012-i1 tranche. Minor — the rule is "don't edit instrumented files" and `MLDispatchScheduler.swift` is engine-side (out of CA.5 edit scope already).

- **Sub-scope decision wording.** The kickoff said the engine-adapter slice is "~50 files" but actual count is 49 (it lists MetalView.swift twice — once at root, once noting it's in Views/; the latter is correct). Minor.

- **One trivial mis-step:** Early in Pass 2 I read the count "Listed (12)" but recounted to find it's actually 15 files listed in the pre-CA.5 ARCHITECTURE.md `§Module Map PhospheneApp/` block (not 12 as I'd initially written). Corrected inline; the post-CA.5 block lists all 49.

**Recommended changes for CA.6.**

1. **Default to direct reads for ≤ 5k-LoC subsystems; parallel Explore agents work cleanly for 5–10k LoC with cross-check.** CA.5's hybrid (15 files direct + 35 files via 3 parallel agents) worked. CA.6 (~6.9k LoC across 59 files) sits in the same band — use the hybrid; cross-check every agent's claimed public symbols.
2. **Cross-check the kickoff prompt against `KNOWN_ISSUES.md` as Pass 0 (continuing rule).** CA.3 found drift; CA.4 + CA.5 found none. The cost is ~2 minutes; the value when drift is present is much higher.
3. **For CA.6, declare which App-layer state types are explicitly in / out of scope** (e.g. SwiftUI `@State` and `@StateObject` declarations inside Views vs. the ObservableObject `@MainActor` classes inside ViewModels). The U.10 / U.11 flake cluster is a known dimension where ARCHITECTURE.md drift might already exist.
4. **Recommended next subsystem for CA.6:** **App Views + ViewModels** (the deferred half of CA.5). Mid-priority. After CA.6 ships, three remaining unaudited engine subsystems are CA-Renderer, CA-Audio, CA-Presets. Order TBD per the audit-driven priority rule.

The audit format continues to produce actionable findings: 2 small follow-up items (one field-level orphan, one docstring-vs-code gap), 1 source-naming cleanup, 1 CA.6 hand-off, 1 CA.1-FU-1 supersede update, plus the BUG-015 wire-shape verification + BUG-012-i1 instrumentation-intactness verification both clean. Recommend continuing into CA.6 with the methodology refinements above; minor consolidations as noted.

---

*End of CA.5 — Capability Registry — App Layer (engine-adapter slice).*
