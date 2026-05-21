# Phase CA Kickoff — Capability Audit — Increment CA.5 (App Layer)

Hand this to a new Claude Code session verbatim. Do not summarise.

## What this phase is

Phase CA — Capability Audit is a multi-increment archaeology of Phosphene's codebase. Each increment audits one subsystem: reads the actual source, traces consumers and producers, cross-references against `CLAUDE.md` / `docs/ARCHITECTURE.md` / `docs/QUALITY/KNOWN_ISSUES.md` / `docs/DECISIONS.md`, and assigns a health verdict to every capability the subsystem exposes.

CA.1 (DSP / MIR) closed 2026-05-20 at [`docs/CAPABILITY_REGISTRY/DSP_MIR.md`](../CAPABILITY_REGISTRY/DSP_MIR.md). Surfaced one runtime production-orphan cluster (per-frame `StructuralAnalyzer` chain), one field-level orphan, boundary-deferred two Session/ files.

CA.2 (ML) closed 2026-05-20 at [`docs/CAPABILITY_REGISTRY/ML.md`](../CAPABILITY_REGISTRY/ML.md). Audited 16 ML files (4,507 LoC), surfaced four cluster-level production-orphan findings, two large built-but-undocumented gaps, BUG-012 instrumentation map. Methodology refinement: pre-grep visibility verification.

CA.3 (Session) closed 2026-05-20 at [`docs/CAPABILITY_REGISTRY/SESSION.md`](../CAPABILITY_REGISTRY/SESSION.md). Audited 22 Session files (~3,425 LoC), resolved all three CA.1/CA.2 boundary-deferred items. Found 1 `stub`, 0 `broken-but-claimed`, 0 `production-orphan`, 2 documented-but-missing + 2 built-but-undocumented in `ARCHITECTURE.md`. Methodology refinement: cross-check kickoff prompt against `KNOWN_ISSUES.md` as Pass 0.

CA.4 (Orchestrator) closed 2026-05-20 at [`docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md`](../CAPABILITY_REGISTRY/ORCHESTRATOR.md). Audited 14 Orchestrator files (~2,950 LoC). Surfaced the load-bearing **broken-but-claimed BUG-015** (`applyLiveUpdate(...)` had zero production call sites — the entire Phase 4.5/4.6 live-adaptation pipeline was dead in production despite the unit tests passing green). BUG-015 was filed, then fixed in commits `b3f1efd9` + `5efc6a90` + `bb5e36ef` (wire + diagnostic + Resolved flag) on 2026-05-21 with the source-presence regression test `OrchestratorWiringRegressionTests.swift` locking the wire's existence. **The CA.4 audit's #1 recommended next subsystem is the App layer**, because (a) it's the largest unaudited surface (~14.8k LoC across 108 Swift files at the time of CA.4's closeout, compared with Orchestrator's 2.95k), (b) the BUG-015 wire site lives there and the audit will close the boundary cleanly with the wire already in place, and (c) the App layer is where every recently-completed user-facing increment (U.x series, QR.4, DSP.3.x runtime parts, BUG-006.2, BUG-007.x runtime, BUG-011 frame-budget governor, BUG-015 wire, BUG-016 surface) has its consumer-side landing.

This kickoff is for **Increment CA.5: the App layer**. It is the fifth audit pass.

## Why App layer next

Six reasons, in priority order:

1. **It's the load-bearing consumer-side surface for every Orchestrator / Session / DSP capability the prior audits documented.** CA.1's `MIRPipeline` is constructed and fed in `PhospheneApp/VisualizerEngine.swift` + `+Audio.swift`. CA.2's `MoodClassifier` + `StemSeparator` + `MLDispatchScheduler` decisions are consumed in `+Audio.swift` / `+Stems.swift`. CA.3's `SessionManager` lifecycle is owned and observed at `VisualizerEngine.init` lines 605–613 + 647–666. CA.4's `DefaultSessionPlanner` / `DefaultLiveAdapter` / `DefaultReactiveOrchestrator` are instantiated at `VisualizerEngine.swift:458/461/464` and driven from `VisualizerEngine+Orchestrator.swift`. The App layer is where every architectural seam from the prior four audits actually fires. Until CA.5, the audit chain only verifies the engine half.

2. **BUG-015 just landed there.** The new wire (`runOrchestratorLiveUpdate(mir:)` + `liveTrackPlanIndex` + `lastClassifiedMood` + the once-per-track diagnostic) sits in `VisualizerEngine+Orchestrator.swift` + `+Capture.swift` + `+Audio.swift`. CA.5 should verify the App-layer wire's shape against the BUG-015 fix's design notes in `RELEASE_NOTES_DEV.md` Update 1–3 — confirm the cooldown machinery is reachable from production, confirm the off-plan skip path is correct, confirm no other App-layer code accidentally calls `applyLiveUpdate` with stale inputs.

3. **BUG-012-i1 instrumentation lives there.** Per CA.2/CA.3/CA.4's read-only-instrumented-files rule, eight files were instrumented for BUG-012's pending diagnosis: `Sources/ML/StemFFT*.swift`, `Sources/ML/StemSeparator.swift`, `Sources/Shared/BUG012Probe.swift`, `Tests/.../BUG012ConcurrencyTest.swift`, and the App-layer files `PhospheneApp/VisualizerEngine.swift` + `PhospheneApp/VisualizerEngine+Stems.swift`. CA.5 reads these but DOES NOT EDIT THEM — same rule as CA.2/CA.3/CA.4. Verify the instrumentation is present and the path is clear for the next BUG-012 reproduction.

4. **The BUG-016 (Lumen Mosaic "not working") App-layer surface needs an inventory pass.** Filed 2026-05-21. The preset's slot-8 fragment-buffer dispatch + the `LumenPatternEngine` tick wiring live in `VisualizerEngine+Presets.swift .lumenMosaic:` branch. The audit should locate the apply path and document which fragment-buffer setter is invoked (`setDirectPresetFragmentBuffer3` per CLAUDE.md / D-LM-buffer-slot-8) without trying to diagnose the bug. The next BUG-016 reproduction is the load-bearing diagnostic step.

5. **The 5 active "P2 / pre-existing flake" classes per CLAUDE.md U.10 / U.11 + memory note `project_test_baseline.md` all sit in App-layer test targets.** `AppleMusicConnectionViewModelTests`, `NetworkRecoveryCoordinatorTests`, `SpotifyConnectionViewModelTests`, `ToastManagerTests.autoDismiss_afterDuration()`, `PlaybackChromeViewModelTests.overlayAutoHides_afterDelay()`, `ReadyViewTimeoutIntegrationTests.*`. These flake under parallel execution per CLAUDE.md U.10 (URLProtocol stub races) + U.11 (`@MainActor` debounce timing margins). CA.5 should audit: (a) whether the `@Suite(.serialized)` annotation is in place on every URLProtocol-stub-using suite per the U.10 rule, (b) whether debounce timing margins match the U.11 baseline (700 ms wait for 300 ms debounce, 250–400 ms wait for connect/login). If any test class still races under parallel execution, that's a `regression` failure-class finding worth documenting (not fixing in CA.5).

6. **Multiple SwiftUI state contracts at risk.** Failed Approach #55 (`@EnvironmentObject SettingsStore`) was the last big App-layer pipeline-wiring bug; QR.4 / D-091 fixed it and shipped the regression test `SettingsStoreEnvironmentRegressionTests`. CA.5 should grep for other potential `@StateObject` re-instantiation foot-guns AND verify the `@Published var currentTrackIndex: Int?` write path is single-sourced (per BUG-015 wire's new `liveTrackPlanIndex` mirror — both fields should reflect the same plan walk).

## Read these first, before doing anything else

1. **`CLAUDE.md`** — the entire file. Especially: the Audio Data Hierarchy (App layer must respect it when threading FeatureVector + StemFeatures + EmotionalState through the render pipeline), Failed Approach #55 (`@EnvironmentObject` SettingsStore), #56 (canonical-identity match — `indexInLivePlan(matching:)` is App-layer), #66 (Ferrofluid mesh G-buffer dispatch parity — App-layer + Engine), and the U.10 / U.11 timing-margin learnings. Also CLAUDE.md "Test in the production-grade rendering pipeline" rule (promoted 2026-05-18 after AV.1/AV.2/AV.2.1 — every preset increment with temporal behaviour needs multi-frame harness coverage in the live dispatch path; the App-layer test surface is where these regressions land).

2. **`docs/CAPABILITY_REGISTRY/DSP_MIR.md`** — CA.1 audit. Read §Findings-by-verdict and §Cross-references. The App-layer consumes `MIRPipeline`, `FeatureVector`, `StructuralPrediction`, `EmotionalState` from CA.1's surfaces; verify the consumption shape matches the docs.

3. **`docs/CAPABILITY_REGISTRY/ML.md`** — CA.2 audit. Read §Cross-references and the §BUG-012 instrumentation map. App-layer consumers: `MoodClassifier.classify(features:)` at `+Audio.swift:289`, `StemSeparator.separate(...)` at `+Stems.swift:151`, `MLDispatchScheduler` decisions in `+Stems.swift`. BUG-012 instrumentation overlap: the two App-layer instrumented files (`VisualizerEngine.swift` + `VisualizerEngine+Stems.swift`) stay read-only.

4. **`docs/CAPABILITY_REGISTRY/SESSION.md`** — CA.3 audit. Read §Boundary-noted and §Follow-up Backlog. App-layer consumes `SessionManager` + `SessionPlan` + `TrackProfile` + `StemCache` + `MetadataPreFetcher` + `SessionPreparer` etc. — verify the consumption shape. CA.3 surfaced no boundary-deferred items; CA.5 should keep that clean.

5. **`docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md`** — CA.4 audit. Read §Resolution-of-CA.1-runtime-production-orphan-re-evaluation (the synthetic-prediction site at `SessionPlanner.swift:317` and CA.1-FU-1's "collapsed into BUG-015" verdict). Read §Follow-up Backlog including CA.4-FU-1 (transitionPolicy dead field — spawned as a separate task chip per Matt's go-ahead 2026-05-21). The BUG-015 finding's full lineage is in §broken-but-claimed.

6. **`docs/QUALITY/KNOWN_ISSUES.md`** — every Open entry. Especially the freshly-Resolved BUG-015 (the wire's design notes are in the entry's Resolved field — verify the App-layer wire matches), the just-filed BUG-016 (Lumen Mosaic — App-layer surface scoped but symptom uncharacterised), BUG-012 (instrumentation in place — verify), BUG-001 (Money 7/4 stays REACTIVE — may have App-layer findings now that BUG-015's wire is live; document, do not fix), BUG-013 (Soundcharts time_signature absence — `MetadataPreFetcher` consumer is `+Capture.swift:176`), and the "Pre-existing Flakes" section.

7. **`docs/ARCHITECTURE.md`** — sections "App layer" (lines around the `PhospheneApp/` section), "Module Map App/" (the App-layer table within the module map), and the recent CA.1/CA.2/CA.3/CA.4 §Recently Completed entries. Particular attention: the Module Map for App layer is the most likely to have drifted given the multi-month App-layer increment cadence; CA.1 found DSP missing 6 of 20 files, CA.2 missing 9 of 16, CA.3 missing 13 of 22, CA.4 will have similar findings — CA.5 may find the worst drift yet given the App layer's size and rate of change.

8. **`docs/DECISIONS.md`** — grep for D-050 (`PlaybackActionRouter` protocol — concrete `DefaultPlaybackActionRouter` lives in App), D-061 (capture-mode switch grace window; live in `CaptureModeSwitchCoordinator`), D-079 (QR.1 sample-rate plumbing; `updateTapSampleRate` is App-layer), D-080 (QR.2 reactive-mode `liveStemFeatures` — verify `+Orchestrator.swift:273` matches), D-091 (QR.4 single SettingsStore + `currentTrackIndex` — verify `SettingsStoreEnvironmentRegressionTests.swift` is the load-bearing regression gate), D-095 (Arachne `PresetSignaling.presetCompletionEvent` — App-layer subscription lives in `+Presets.swift` `presetCompletionCancellable` at line ~507), D-097 (particle presets are siblings — App-layer `resolveParticleGeometry(forPresetName:)` at `VisualizerEngine.swift:715`), and D-102 (Drift Motes retirement — verify no App-layer references remain to deleted DM symbols).

9. **`docs/ENGINEERING_PLAN.md`** — search for "Phase U" (User-experience increments — most are App-layer), "Phase 6.x" (Session preparation App-layer wiring), "QR.4" (SettingsStore consolidation), "DSP.3.x" (the App-layer L-lock + diagnostic-preset-locked semantics + Spectral Cartograph runtime parts), "BUG-006.2" (App-layer canonical-identity wiring), "BUG-007.x" (LiveDriftTracker App-layer + Spectral Cartograph overlay), "BUG-011" (Tier 2 frame budget — App-layer FrameBudgetManager consumer), "BUG-012-i1" (instrumentation — App-layer files), "BUG-015" (just-landed wire), and the U.x sequence catalog (U.6 PlaybackActionRouter, U.6b live-adaptation keyboard, U.10 Spotify URLProtocol race fix, U.11 Spotify OAuth, U.12 Apple Music connector).

If any of these files do not exist (still a possibility — CA.1 found one such case), record the missing reference as a finding and continue with what does exist.

## Hard rules for this phase

1. **No code changes during the audit.** Findings are documented; fixes are separate increments scheduled after the audit publishes. The only file modifications allowed in CA.5 are the new audit document(s) and minor corrections to load-bearing docs (`ARCHITECTURE.md` / `ENGINEERING_PLAN.md` / `KNOWN_ISSUES.md` / `CLAUDE.md`) that the audit surfaces as drift.

2. **BUG-012-i1 instrumentation files remain read-only.** The eight instrumented files include the two App-layer files in CA.5's scope: `PhospheneApp/VisualizerEngine.swift` + `PhospheneApp/VisualizerEngine+Stems.swift`. **Read freely; do not edit.** If a doc-drift correction would require editing them, surface for Matt's call before landing.

3. **Evidence-based:** every claim cites a file and line. "X exists at `path/file.swift:NNN`" or "X is referenced but file does not exist." No claims unverified by inspection of the actual source.

4. **`production-orphan` verdicts require a cited grep (carried forward from CA.2).** "X has zero consumers" must be backed by the exact grep command run and a summary of its results. The grep should cover `PhospheneApp/`, `PhospheneEngine/Sources/`, and `PhospheneEngine/Tests/` + `PhospheneAppTests/`. Production-orphan claims without a cited grep will be rejected at closeout.

5. **Pre-grep visibility verification (carried forward from CA.3).** When parallelising file reads via Explore agents, do not trust an agent's "this type is public" / "this method is public" reports without cross-checking. After receiving each agent's report, run a single visibility grep:
   ```sh
   grep -nE "^public|^[[:space:]]+public|^internal|^[[:space:]]+internal" PhospheneApp/<file>.swift
   ```
   Reconcile each agent-claimed public against the grep. **App-layer note:** unlike Orchestrator at 2.95k LoC, the App layer's 14.8k LoC across 108 files is BEYOND the tractable direct-read range. Default to Explore agents with the cross-check rule strictly enforced.

6. **Cross-check the kickoff prompt against `KNOWN_ISSUES.md` (Pass 0 — carried forward from CA.4).** As the audit's first step, verify every BUG cited in this kickoff against the actual `KNOWN_ISSUES.md` status. **CA.4 specifically:** BUG-015 was Open during CA.4's planning; CA.5's planning was after BUG-015 closed. Verify the kickoff's "BUG-015 = Resolved as of 2026-05-21" claim. If kickoff and `KNOWN_ISSUES.md` disagree, file the disagreement as Finding #1.

7. **Sub-scope decision required at Pass 0.** The App layer is 14.8k LoC across 108 files — too large for a single CA-increment session. The audit's first deliverable is a decision: **does CA.5 cover the whole App layer in one increment, or split into CA.5 (engine-adapter slice) + CA.6 (Views + ViewModels)?** The recommended split (subject to the auditor's read):
   - **CA.5 scope (this increment):** `VisualizerEngine.swift` + 11 `VisualizerEngine+*` extensions + `Services/` (30 files) + `Permissions/` (3 files) + `Models/` (2 files) + the four top-level files (`ContentView.swift`, `PhospheneApp.swift`, `MusicKitFetcher.swift`, `MetalView.swift` — though MetalView lives under `Views/`). Estimated ~50 files, ~7–8k LoC.
   - **CA.6 scope (deferred):** `Views/` (~80 files across subdirectories — Connecting, Dashboard, Ended, Idle, Onboarding, Playback, Preparation, Ready, Settings + root-level views) + `ViewModels/` (12 files).
   - The split is justified by the architectural layering: Services + the VisualizerEngine adapter are the App-layer's *engine-coupling* surface; Views + ViewModels are the *SwiftUI presentation* surface. The engine-adapter slice is the one CA.5 should audit because it's where the four prior audits' findings actually fire. The presentation slice is where U.x increments shipped UX flows and is its own audit class.
   - **If the auditor disagrees with the split**, document the alternative and proceed under that scope. Do not silently expand CA.5 into all 108 files.

8. **Exhaustive within scope.** Every `public` / `internal` type, every `public` / `internal` method in the chosen scope gets a verdict. Coverage is binary for the scope you commit to, not best-effort.

9. **Stop-and-report criteria** (in addition to the standard `CLAUDE.md` set):
   - Found a `broken-but-claimed` finding that affects production behavior right now (file as `BUG-` entry; surface immediately — the BUG-015 finding in CA.4 is the load-bearing precedent for this rule).
   - The audit's reading of an App-layer code path reveals a plausible BUG-001 root cause (Money 7/4 stays REACTIVE on live path). Document; do not fix.
   - The audit's reading of `VisualizerEngine+Presets.swift .lumenMosaic:` branch reveals a plausible BUG-016 root cause. Document in the audit + cross-link from BUG-016's section. The next BUG-016 reproduction with concrete symptom is still the load-bearing step.
   - Audit scope is growing beyond the chosen sub-scope. Note the boundary crossing; continue within scope; flag as `boundary-noted` or `boundary-deferred` per the CA.3 convention.
   - Discovered an architectural inconsistency between the App layer and the four prior audits' findings (e.g. a Service that constructs its own MIRPipeline instead of injecting one — there was a near-miss of this in BUG-006.2). Surface for Matt.
   - The audit format is producing low-value output. Pause, redesign before continuing.

Closeout report cites the audit document, not the audit's findings. The audit document IS the deliverable.

## Scope of CA.5 (recommended; subject to Pass 0 sub-scope decision)

### Files in scope — engine-adapter slice (~50 files, ~7–8k LoC)

**The VisualizerEngine adapter (~3,500 LoC across 12 files):**
```
PhospheneApp/VisualizerEngine.swift                          — ~730 lines — Main owner: Metal context + audio pipeline + ML + render pipeline + orchestrator instantiation + all @Published state. BUG-012-i1 instrumented — read-only.
PhospheneApp/VisualizerEngine+Audio.swift                    — ~460 lines — Audio routing + MIR analysis + mood classification + BUG-015 wire site. Read-only for BUG-012-i1 (no — only VisualizerEngine.swift + +Stems.swift are instrumented; +Audio.swift is freely auditable).
PhospheneApp/VisualizerEngine+Capture.swift                  — ~190 lines — onTrackChange callback + signal-state callback + canonical-identity matcher + BUG-015 liveTrackPlanIndex write.
PhospheneApp/VisualizerEngine+Dashboard.swift                — ~?? lines — DASH.7 dashboard snapshot pump.
PhospheneApp/VisualizerEngine+InitHelpers.swift              — ~?? lines — Static factory methods for loading classifiers + separators + device-tier detection.
PhospheneApp/VisualizerEngine+Orchestrator.swift             — ~510 lines — Plan-building + applyLiveUpdate + applyReactiveUpdate + BUG-015 runOrchestratorLiveUpdate + the once-per-track diagnostic + canonical-identity helper.
PhospheneApp/VisualizerEngine+Presets.swift                  — ~?? lines — applyPreset(...) for every preset family (ray-march / staged / particles / feedback / direct) + preset-signaling subscription + BUG-016 .lumenMosaic: branch lives here.
PhospheneApp/VisualizerEngine+PublicAPI.swift                — ~?? lines — Public surface for keyboard shortcuts + capture mode + capture-mode-switch coordinator interface.
PhospheneApp/VisualizerEngine+Stems.swift                    — ~?? lines — Stem separation timer + StemSampleBuffer feed + BUG-012-i1 instrumented — read-only.
PhospheneApp/VisualizerEngine+TrackIdentityResolution.swift  — ~?? lines — canonicalTrackIdentity(matching:) — D-091 / BUG-006.2 helper.
PhospheneApp/VisualizerEngine+WiringLogs.swift               — ~95 lines — Dual-write log helpers (session.log + os.Logger) — the pattern BUG-015's diagnostic now follows.
PhospheneApp/MetalView.swift                                 — ~?? lines — MTKView NSViewRepresentable wrapper.
```

**Top-level App entry points (~4 files, ~?? LoC):**
```
PhospheneApp/PhospheneApp.swift                              — App entry + global SettingsStore construction (D-091 / Failed Approach #55).
PhospheneApp/ContentView.swift                               — Root view + currentTrackIndexPublisher binding (BUG-015 / D-091).
PhospheneApp/MusicKitFetcher.swift                           — Apple Music connector entry point.
```

**Services (~30 files, ~?? LoC):**
```
PhospheneApp/Services/AccessibilityLabels.swift
PhospheneApp/Services/AccessibilityState.swift
PhospheneApp/Services/CaptureModeReconciler.swift
PhospheneApp/Services/CaptureModeSwitchCoordinator.swift     — D-061 grace window — verify BUG-015 isCaptureModeSwitchGraceActive check
PhospheneApp/Services/DefaultPlaybackActionRouter.swift      — D-050 concrete; consumes Orchestrator protocol
PhospheneApp/Services/DelayProviding.swift
PhospheneApp/Services/DisplayChangeCoordinator.swift
PhospheneApp/Services/DisplayManager.swift
PhospheneApp/Services/FirstAudioDetector.swift
PhospheneApp/Services/FullscreenObserver.swift
PhospheneApp/Services/LiveAdaptationToastBridge.swift        — U.6 Part C — BUG-015 wire's downstream consumer of LiveAdaptation events
PhospheneApp/Services/LocalizedCopy.swift
PhospheneApp/Services/MultiDisplayToastBridge.swift
PhospheneApp/Services/NetworkRecoveryCoordinator.swift
PhospheneApp/Services/OnboardingReset.swift
PhospheneApp/Services/PlaybackErrorBridge.swift
PhospheneApp/Services/PlaybackErrorConditionTracker.swift
PhospheneApp/Services/PlaybackKeyMonitor.swift
PhospheneApp/Services/PlaybackShortcutRegistry.swift
PhospheneApp/Services/PreparationETAEstimator.swift
PhospheneApp/Services/PresetScoringContextProvider.swift     — Canonical builder of PresetScoringContext values consumed by the Orchestrator
PhospheneApp/Services/ReachabilityMonitor.swift
PhospheneApp/Services/SessionRecorderRetentionPolicy.swift
PhospheneApp/Services/SettingsMigrator.swift
PhospheneApp/Services/SettingsStore.swift                    — D-091 / Failed Approach #55 — single instance enforced via SettingsStoreEnvironmentRegressionTests
PhospheneApp/Services/SpotifyKeychainStore.swift             — U.11
PhospheneApp/Services/SpotifyOAuthPlaylistConnector.swift    — U.11
PhospheneApp/Services/SpotifyOAuthTokenProvider.swift        — U.11
PhospheneApp/Services/SpotifyURLKind.swift
PhospheneApp/Services/SpotifyURLParser.swift
```

**Models (~2 files):**
```
PhospheneApp/Models/PhospheneToast.swift                     — Toast value type
PhospheneApp/Models/SettingsTypes.swift                      — CaptureMode, QualityCeiling, etc.
```

**Permissions (~3 files):**
```
PhospheneApp/Permissions/PermissionMonitor.swift
PhospheneApp/Permissions/PhotosensitivityAcknowledgementStore.swift
PhospheneApp/Permissions/ScreenCapturePermissionProvider.swift
```

### Files deferred to CA.6 (out of CA.5 scope)

```
PhospheneApp/Views/ (~80 files across Connecting/, Dashboard/, Ended/, Idle/, Onboarding/, Playback/, Preparation/, Ready/, Settings/ subdirectories + ~15 root-level views like DebugOverlayView.swift, FullScreenErrorView.swift, etc.)
PhospheneApp/ViewModels/ (12 files: AppleMusicConnectionViewModel, ConnectorPickerViewModel, EndSessionConfirmViewModel, PlanPreviewViewModel, PlaybackChromeViewModel, PreparationErrorViewModel, PreparationProgressViewModel, ReadyViewModel, SessionStateViewModel, SettingsViewModel, SpotifyConnectionViewModel, ToastManager)
```

### Boundary surfaces (in scope, with annotation)

- **App ↔ Orchestrator.** App-layer adapter (`VisualizerEngine+Orchestrator.swift`) is the consumer of `DefaultSessionPlanner` + `DefaultLiveAdapter` + `DefaultReactiveOrchestrator`. CA.4 audited the engine side; CA.5 verifies the App-side consumption shape. Particularly: the BUG-015 wire path (`runOrchestratorLiveUpdate(mir:)` → `applyLiveUpdate(...)` → `applyReactiveUpdate(...)`) — confirm the per-track cooldown machinery is reachable; confirm the off-plan skip path; confirm the `lastClassifiedMood` defaults to `.neutral` until the first mood frame fires.

- **App ↔ Session.** `SessionManager` is constructed at `VisualizerEngine.swift:605-613` and its `$state` publisher feeds `buildPlan()` at line 648; `$progressiveReadinessLevel` feeds `extendPlan()` at line 657. `StemCache` is wired to `SessionManager.cache` at line 619. `MetadataPreFetcher` is constructed at line 602. Per CA.3, the Session side is clean; CA.5 verifies the App-side consumers.

- **App ↔ DSP / MIR.** `MIRPipeline` is owned at `VisualizerEngine.swift:583`. `BeatDetector`, `FFTProcessor`, `AudioBuffer` are owned across the engine. Per CA.1, the DSP side has the per-frame `StructuralAnalyzer` chain running unconditionally; with BUG-015's wire landing, the runtime consumer is now `runOrchestratorLiveUpdate`. CA.5 verifies the App-side consumption is the only consumer (no other code path reads `mirPipeline.latestStructuralPrediction` from the App layer).

- **App ↔ ML.** `MoodClassifier` constructed at `VisualizerEngine.swift:547` and consumed at `+Audio.swift:289`. `StemSeparator` loaded at `VisualizerEngine.swift:575` and consumed at `+Stems.swift:151`. `StemAnalyzer` constructed at `:546`. `MLDispatchScheduler` constructed at `:629` and consumed at `+Stems.swift`. Per CA.2, the ML side has BUG-012 instrumentation in place; CA.5 verifies the App-side dispatch path matches CA.2's audit findings.

- **App ↔ Renderer.** `RenderPipeline` constructed at `VisualizerEngine.swift:561`. `FrameBudgetManager` at `:628`. `MetalContext`, `ShaderLibrary`, `PresetLoader` all owned at `:577-582`. The per-preset state classes (`ArachneState`, `GossamerState`, `AuroraVeilState`, `LumenPatternEngine`, `FerrofluidParticles`, `FerrofluidMesh`) live in `PhospheneApp/VisualizerEngine.swift` lines 116–163 — these are App-layer types that conform to Engine-side protocols. CA.5 audits the App-side declarations; the per-preset rendering details remain CA-Renderer scope.

- **App ↔ Audio.** `AudioInputRouter` (macOS 14.2+; stored as `Any` to avoid availability propagation per `VisualizerEngine.swift:196`) is constructed at `+Audio.swift:24-26`. Its callbacks (`onAudioSamples`, `onSignalStateChanged`, `onTrackChange`) are built at `+Audio.swift:74-110` + `+Capture.swift`. CA.5 verifies the audio-thread → analysis-queue → MainActor handoff is correct (cross-core visibility per D-079 / QR.1).

### Explicit exclusions (will be audited in later CA increments)

- `PhospheneApp/Views/` — defer to CA.6.
- `PhospheneApp/ViewModels/` — defer to CA.6. **Exception:** `Services/PresetScoringContextProvider.swift` lives in Services/ (audit-in-scope) but is consumed by view models; the view-model-side consumption stays in CA.6.
- `PhospheneEngine/Sources/Renderer/` — deferred (CA-Renderer).
- `PhospheneEngine/Sources/Audio/` — deferred (CA-Audio).
- `PhospheneEngine/Sources/Presets/` (per-preset Metal shaders + state) — deferred (CA-Presets).
- `PhospheneEngine/Sources/Shared/` — deferred.
- `PhospheneAppTests/` — read freely for test discriminators, but audit verdicts apply to production code, not tests.

If something in the boundary surfaces seems important enough that the audit's value is reduced without it, note the gap and continue. Do not expand scope.

## Methodology

The methodology is the same as CA.4 with one addition (the sub-scope decision in Pass 0, new in CA.5).

### Pass 0 — Kickoff cross-check + sub-scope decision (CA.5-specific)

Before reading any source file:

1. **BUG cross-check.** Verify every BUG cited in this kickoff against `docs/QUALITY/KNOWN_ISSUES.md`:
   - BUG-015 — should be Resolved 2026-05-21 (commits b3f1efd9 + 5efc6a90 + bb5e36ef).
   - BUG-016 — should be Open, P2, preset.fidelity (filed 2026-05-21).
   - BUG-012 — should be Open with instrumentation in place.
   - BUG-001 — should still be Open.
   - BUG-013 — verify status.

   If any kickoff claim disagrees with `KNOWN_ISSUES.md`, the audit's first finding is the kickoff staleness.

2. **Sub-scope decision.** Confirm or override the recommended split:
   - **Recommended:** CA.5 = engine-adapter slice (~50 files), CA.6 = Views + ViewModels (~92 files).
   - **Alternative 1:** Whole App layer in CA.5 — explicitly multi-session; the audit document is the deliverable; intermediate session boundaries are acceptable.
   - **Alternative 2:** Re-split — e.g. CA.5 = Services + Permissions + Models only (~35 files); CA.5b = VisualizerEngine + extensions (~12 files); CA.6 = Views + ViewModels.

   Whichever scope is chosen, **state it explicitly** in the audit doc's §Scope section before Pass 1 begins. Do not silently scope-creep.

### Pass 1 — Inventory + verdict assignment

For each file in scope, produce:
- **File summary** — one paragraph: what this file owns, who its primary consumers are.
- **Public / internal surface** — every `public` / `internal` type and every `public` / `internal` method, with brief signatures.
- **Documented features** — comment headers, MARK sections, doc-comments. Quote verbatim where the claim matters.
- **Notable internal types / private members** if load-bearing (e.g. `VisualizerEngine`'s per-preset state fields, `SettingsStore`'s `@Published` properties, `CaptureModeSwitchCoordinator`'s grace-window state machine).
- **File-level constants / tuning values** with names and values (e.g. `featureEmaAlpha`, `orchestratorWireFrameDivisor`, `moodOverrideCooldown`, grace-window durations, debounce timing margins).
- **Any code-level TODOs / FIXMEs / placeholder branches.**

**App layer note on read strategy:** ~50 files at ~150 LoC average is more files than direct reads can handle in a single pass. Default to Explore agents for file batches (10–15 files per agent, grouped by capability family — e.g., "Services/Spotify*", "Services/Display*", "VisualizerEngine+*", etc.). After each agent's report, run the visibility verification grep:
```sh
grep -nE "^public|^[[:space:]]+public|^internal|^[[:space:]]+internal" PhospheneApp/<file>.swift
```

Then for each capability, trace consumers via grep:
```sh
grep -rn "TypeName" PhospheneEngine/Sources PhospheneApp PhospheneAppTests PhospheneEngine/Tests
```
- For functions: `grep -rn "\.functionName(" …` — call sites.
- For protocols: `grep -rn ": ProtocolName" …` — conformances.
- For SwiftUI view types: `grep -rn "TypeName(" …` — instantiation sites.
- For types referenced only in tests: note as test-only (different verdict than production).

Record per capability: production consumers, test consumers, no consumers. For any `production-orphan` candidate, the cited grep command + result count is mandatory.

Cross-reference each capability against the load-bearing docs. Record: claimed in docs (yes/no, citations), doc claim aligned with code (yes/no, divergence noted), documented as planned-but-not-built (yes/no).

**Behaviour validation:** App-layer has a substantial test surface — `PhospheneAppTests/` has 60+ test classes. Key discriminators by domain:
- `SettingsStoreEnvironmentRegressionTests` — D-091 / Failed Approach #55 regression gate.
- `OrchestratorWiringRegressionTests` — BUG-015 regression gate (just landed 2026-05-21).
- `PlaybackChromeIndexBindingTests` — QR.4 / D-091 plan-index propagation.
- `LiveAdaptationToastBridgeTests` — U.6 Part C.
- `DefaultPlaybackActionRouterTests` — D-050 router.
- `CaptureModeSwitchCoordinatorTests` — D-061 grace window.
- `NetworkRecoveryCoordinatorTests` — network restoration.
- `SpotifyConnectionViewModelTests` + `SpotifyKeychainStoreTests` + `SpotifyOAuthTokenProviderTests` — U.11.
- `PresetScoringContextProviderTests` — App ↔ Orchestrator scoring-context bridge.

Use them as the discriminators they are. **Particular attention:** verify each suite that uses URLProtocol stubs has the `@Suite(.serialized)` annotation per CLAUDE.md U.10. Verify debounce timing margins match U.11 (700 ms for 300 ms debounce; 250–400 ms for connect/login).

Assign verdict per capability (definitions carried forward from CA.4):

| Verdict | Meaning |
|---|---|
| `production-active` | Consumed by production code; doc claims match code behavior; behavior validated. |
| `production-orphan` | Consumed nowhere in production code (test consumers only OR no consumers). **Requires cited grep.** |
| `dead` | Confirmed dead — no consumers anywhere; safe to delete. |
| `stub` | Exists as signature; body empty / default / unimplemented. |
| `documented-but-missing` | Docs claim it exists; code does not. |
| `built-but-undocumented` | Code has it; no doc references it. |
| `broken-but-claimed` | Docs claim it works; runtime behavior contradicts. File a `BUG-` entry immediately. |
| `unverified-claim` | Consumed; docs claim correctness; no evidence of correctness. |
| `boundary-noted` | Lives at a subsystem boundary; verdict is complete (no future re-audit obligation). |
| `boundary-deferred` | Lives at a subsystem boundary; full verdict requires the other subsystem's audit. |

### Pass 2 — Doc-drift triangulation

Once verdicts are assigned, scan load-bearing docs for additional drift:
1. Does `ARCHITECTURE.md`'s `PhospheneApp/` module-map block list every file? (Expect significant drift given the App layer's size and rate of change.)
2. Are tuning constants quoted in docs identical to the code's values? (BUG-015's `orchestratorWireFrameDivisor: 30`, `LiveAdapter.moodOverrideCooldown: 30`, U.11's debounce margins, U.6 reactive-cooldown `60.0` seconds, the 15 s reactive listening window, the U.10 grace-window duration.)
3. Does any architectural claim describe a code path that no longer exists? Was retired? Was renamed?
4. Do any decisions in `DECISIONS.md` reference symbols that have moved or been renamed?
5. Does the `§Phase U` log accurately reflect what's pending vs. shipped?
6. Does `CLAUDE.md` accurately describe the App-layer concurrency model (analysis queue, MainActor, audio thread)? Verify the D-079 / QR.1 sample-rate plumbing rule.

Record drift findings as a separate cross-reference section in the audit doc.

### Output structure (template — extends CA.4 with App-layer-specific sections)

Output file: `docs/CAPABILITY_REGISTRY/APP.md`.

```markdown
# Capability Registry — App Layer

**Audit increment:** CA.5
**Date:** 2026-05-XX
**Auditor:** Claude (session-driven, read-only)
**Scope:** PhospheneApp/ engine-adapter slice (or alternative per Pass 0 decision)
**Methodology:** Phase CA scoping document (CA.5 kickoff).
**Reads relied on:** [list of docs read]

## Summary

[One paragraph: capability counts per verdict, the highest-priority findings, follow-up count, kickoff-vs-KNOWN_ISSUES cross-check result, sub-scope decision.]

[Markdown table of verdict counts.]

## Sub-scope decision

[State the scope chosen at Pass 0 explicitly. If different from this kickoff's recommendation, justify.]

## Findings by verdict

### broken-but-claimed (BUG entries filed)
### documented-but-missing
### unverified-claim
### production-orphan
### dead, stub, built-but-undocumented, boundary-noted, boundary-deferred
### production-active

[Per-finding citations as CA.4 template.]

## Per-file capability index

[One section per file or per family. Consolidation allowed if verdicts heavily concentrate in production-active.]

## Verification of BUG-015 wire shape (CA.5-specific)

[Required section. The BUG-015 wire landed 2026-05-21 in three commits; CA.5 is the first audit pass to verify its App-layer landing. Cite:
- runOrchestratorLiveUpdate(mir:) call site in +Audio.swift
- liveTrackPlanIndex / lastClassifiedMood write sites
- The once-per-track diagnostic latch
- Off-plan skip path
- Cooldown reachability (the 30 s mood-override cooldown in DefaultLiveAdapter)
- The OrchestratorWiringRegressionTests source-presence assertions
State whether the App-layer landing matches the BUG-015 Resolved-field design notes. Any divergence is a real finding.]

## Verification of BUG-012-i1 instrumentation (CA.5-specific)

[Required section. The two App-layer instrumented files (VisualizerEngine.swift + +Stems.swift) are read-only. Verify the BUG012Probe call sites are intact:
- VisualizerEngine.init() / deinit() lifecycle markers
- +Stems.swift timer + scheduler + weak-self resolution + performStemSeparation enter/exit
- StemSampleBuffer.write call site
Confirm the path is clear for the next BUG-012 reproduction; if instrumentation is intact, mark as production-active; if drifted, surface to Matt.]

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
| **CA.5-FU-1** | … | … | … | … |
| **CA.5-FU-2** | … | … | … | … |

[Note: CA.6 (Views + ViewModels) is registered here as the natural continuation if the sub-scope split chose to defer it.]

## Approach validation

[Critique of methodology. What worked? What didn't? Recommended changes for CA.6 / CA-Renderer / CA-Audio / CA-Presets.]
```

## File the artifact + cross-references

Per `CLAUDE.md` increment closeout protocol:
1. The audit document is the primary deliverable.
2. Any `broken-but-claimed` findings get `BUG-XXX` entries in `KNOWN_ISSUES.md` immediately. The next available BUG number is BUG-017 (BUG-016 was filed 2026-05-21).
3. `ENGINEERING_PLAN.md` gets an entry in Recently Completed (CA.5 ✅) plus the CA.5 row in the Phase CA section.
4. `CLAUDE.md` / `ARCHITECTURE.md` drift findings are corrected in this same increment.

**Commit shape (matches CA.1 / CA.2 / CA.3 / CA.4 — two commits, doc-only):**
```
[CA.5] App audit: capability registry + findings
[CA.5] ARCHITECTURE.md / ENGINEERING_PLAN.md / KNOWN_ISSUES.md / CLAUDE.md: doc-drift corrections (if any)
```

## Done-when

CA.5 closes when:

- [ ] `docs/CAPABILITY_REGISTRY/APP.md` published.
- [ ] Sub-scope decision documented explicitly.
- [ ] Every `public` / `internal` capability in the chosen scope has a verdict.
- [ ] Every `production-orphan` verdict cites the grep command used.
- [ ] Every Explore-agent-claimed `public` / `internal` symbol was cross-checked against a visibility grep.
- [ ] Kickoff-vs-`KNOWN_ISSUES.md` cross-check ran as Pass 0 step 1.
- [ ] Every non-`production-active` finding either ships a doc-fix in this increment OR is registered as a `CA.5-FU-N` follow-up.
- [ ] All `broken-but-claimed` findings have BUG entries in `KNOWN_ISSUES.md`.
- [ ] **BUG-015 wire shape verified** in §Verification-of-BUG-015-wire-shape section (CA.5-required).
- [ ] **BUG-012-i1 instrumentation verified** intact in §Verification-of-BUG-012-i1-instrumentation section (CA.5-required).
- [ ] CA.4-FU-1 (transitionPolicy demote) status noted — done independently OR still pending. Does not block CA.5.
- [ ] Drift corrections to load-bearing docs landed.
- [ ] "Approach validation" section produces an honest critique of whether this format should continue into CA.6.
- [ ] All commits land on `main` (local). Push only on Matt's explicit approval.
- [ ] No edits to BUG-012-i1 instrumented files.

## After CA.5 lands

Surface to Matt:
- The audit summary (broken-but-claimed count, documented-but-missing count, production-orphan count, follow-up count).
- The verdict on BUG-015 wire shape — matches design notes or any divergence found.
- The verdict on BUG-012-i1 instrumentation intactness.
- Any BUG-001-adjacent findings (Money 7/4 stays REACTIVE) that future diagnosis should weigh.
- Any BUG-016-adjacent findings (Lumen Mosaic `.lumenMosaic:` branch in `+Presets.swift`).
- The recommended approach changes for CA.6 (if any).
- The recommended next subsystem for CA.6 — likely Views + ViewModels (if the recommended sub-scope split was accepted) OR Renderer / Audio / Presets (if CA.5 covered the whole App layer).

Do not start CA.6 in the same session.

## Failure modes to watch for

Specifically for App-layer-shaped audit work:

1. **Treating `VisualizerEngine` as a black box.** The class is ~730 lines + 11 extensions = the most complex single Swift type in the codebase. Every `@Published`, every `let`, every Combine subscription, every callback construction is per-line-traceable. The audit's job is to verify the implementation matches the load-bearing docs: D-091 (single SettingsStore), QR.1/D-079 (sample-rate plumbing), D-095 (Arachne completion-event subscription), BUG-015 (new wire), D-097 (particle sibling resolution), Failed Approach #55 (no parallel-state worlds).

2. **Trivial-finding inflation across 50+ files.** Most Services files will be `production-active` with little drama. The depth targets are: `SettingsStore` (consolidation contract per QR.4), `CaptureModeSwitchCoordinator` (grace-window state machine per D-061), `DefaultPlaybackActionRouter` (D-050 concrete), `LiveAdaptationToastBridge` (U.6 Part C — feeds from BUG-015's wire now), `PresetScoringContextProvider` (App ↔ Orchestrator bridge), the U.11 Spotify cluster, and `VisualizerEngine` + its 11 extensions. Smaller files (Helpers, Reconcilers, Monitors) get surface-level `production-active` rows.

3. **SwiftUI state-contract violation patterns.** Look for any `@StateObject` re-instantiation of a type that already exists as `@EnvironmentObject` (Failed Approach #55 / D-091). Look for any `@Published` write from a non-MainActor context without a thread hop (BUG-015's wire is one example done correctly via lock-guarded mirror fields). Look for any Combine subscription not stored in an `AnyCancellable` (potential subscription leak).

4. **App-layer concurrency model verification.** The audio thread, analysis queue, MainActor, and stem queue must all stay correctly partitioned per CLAUDE.md's threading rules. The recent BUG-015 wire shows the pattern: lock-guarded mirror fields for cross-queue reads, NSLock.withLock for synchronization. CA.5 should verify no other App-layer code violates this — particularly any Combine sink that reads `@Published` fields from a background thread.

5. **D-091 single-SettingsStore enforcement.** `SettingsStoreEnvironmentRegressionTests` is the regression gate; CA.5 must verify the test is in place and that no `@StateObject SettingsStore()` pattern exists anywhere outside the test's shadow probe. Re-grep:
   ```sh
   grep -rn "@StateObject.*SettingsStore" PhospheneApp PhospheneAppTests
   ```
   Should return only the shadow probe in the test file.

6. **BUG-015 wire shape.** The wire just landed 2026-05-21 in three commits. CA.5 is the first independent audit pass. Verify by independent re-reading:
   - The `runOrchestratorLiveUpdate(mir:)` call site is reachable from production (not gated behind an obvious dev-only conditional).
   - The cadence (`% 30 == 0`) is hit reliably (the analysis queue's tick rate is ~94 Hz at 48 kHz; ~3 Hz wire firing).
   - The `liveTrackPlanIndex` write in `+Capture.swift` happens before the MainActor task (audio-thread ordering preserved).
   - The `lastClassifiedMood` write in `publishMoodResult` is on the analysis queue.
   - The OrchestratorWiringRegressionTests' two assertions cover the structural shape correctly.

7. **BUG-016 .lumenMosaic branch inventory.** Locate `applyPreset .lumenMosaic:` in `VisualizerEngine+Presets.swift`. Document: which fragment-buffer setter is invoked (`setDirectPresetFragmentBuffer3` per D-LM-buffer-slot-8?), which tick closure is registered, which texture bindings are made. Cross-link to BUG-016. Do not attempt diagnosis.

8. **U.11 OAuth + URLProtocol stub races.** Per CLAUDE.md U.10 / U.11, the URLProtocol-stub-using tests need `@Suite(.serialized)`. Verify the annotation is present on every relevant suite:
   ```sh
   grep -B1 -nA3 "URLProtocol" PhospheneAppTests/Spotify*Tests.swift
   ```
   If any suite lacks the annotation, that's a `regression` finding worth filing.

9. **Citing without verifying.** Same as CA.1/CA.2/CA.3/CA.4's rule. Every claim is evidence-backed with a `file:line` or a `doc:line`.

10. **Producing structure as a substitute for substance.** Headers must be backed by content. Empty buckets should be said-empty, not pretended-incomplete.

11. **Scope creep into CA.6.** When the audit's reading of a Service surfaces a view-model boundary touchpoint, flag it as `boundary-noted` (out of CA.5 scope) and proceed. Do not silently expand into ViewModels.

## Status on entry

- **Branch:** `main`. CA.4 + BUG-015 + BUG-016 have all landed and pushed to `origin/main` as of 2026-05-21. Recent commits:
  - `24152023` `[BUG-016] KNOWN_ISSUES.md: file Lumen Mosaic not-working report`
  - `bb5e36ef` `[BUG-015] KNOWN_ISSUES.md / RELEASE_NOTES_DEV.md: flip Status to Resolved`
  - `5efc6a90` `[BUG-015] Orchestrator: once-per-track wire-active diagnostic to session.log`
  - `b3f1efd9` `[BUG-015] Orchestrator: wire applyLiveUpdate to analysis-queue tick at ~3 Hz`
  - `c97845ad` `[BUG-015] Scoping: kickoff doc for applyLiveUpdate runtime-wire fix`
  - `453b9b3d` `[CA.4] Doc-drift corrections from Orchestrator audit`
  - `faee28a7` `[CA.4] Orchestrator audit: capability registry + findings`
- Local + remote `main` includes CA.0 + CA.1 + CA.2 + CA.3 + CA.4 + BUG-015 fix + BUG-016 filing + BUG-012-i1 instrumentation + Phase CS scoping.
- Working tree clean (`default.profraw` is a documented build artifact).
- **BUG-012 is Open.** BUG-012-i1 instrumentation in place. Step 2 (diagnosis) waits on a reproduction. CA.5's App-layer reads of `VisualizerEngine.swift` + `+Stems.swift` are read-only.
- **BUG-016 is Open.** Lumen Mosaic symptom uncharacterised; awaiting concrete reproduction. CA.5 does not fix; documents the App-layer surface.
- **BUG-001 is Open.** The audit may surface findings relevant to its diagnosis; document, do not fix.
- **CA.4-FU-1 + SwiftLint cleanup** were spawned as separate task chips 2026-05-21 per Matt's go-ahead. Status unknown at CA.5 entry; check `git log --oneline -10` for CA.4-FU-1 landing before assuming the dead `transitionPolicy` field is still in place. Same for SwiftLint baseline (project_swiftlint_baseline.md memory note).
- **No CA.5 code or audit has landed.** This is the kickoff.

## Sign-off

This prompt is the canonical entry point for Increment CA.5. The Phase CA wider scoping (what subsystem comes next, the master `docs/CAPABILITY_REGISTRY.md` index file) continues to be one-increment-at-a-time per the CA.0 scoping decision.

If you find the prompt is wrong or stale during the audit, update the prompt before continuing — do not work against a brief you know to be incorrect.

— Matt + Claude (2026-05-21 design session, post-BUG-015 closeout)
