# Capability Registry — App Layer (Views + ViewModels)

**Audit increment:** CA.6
**Date:** 2026-05-21
**Auditor:** Claude (session-driven, read-only)
**Scope:** `PhospheneApp/Views/` (47 files) + `PhospheneApp/ViewModels/` (12 files) — the SwiftUI presentation slice, deferred from CA.5. 59 files / 8,285 LoC.
**Methodology:** Phase CA scoping document — CA.6 kickoff `docs/prompts/PHASE_CA_KICKOFF_CA6_APP_VIEWS_2026-05-21.md`.
**Reads relied on:** `CLAUDE.md`, `docs/ARCHITECTURE.md` (§UI Layer + §Module Map), `docs/CAPABILITY_REGISTRY/APP.md` (CA.5), `docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md` (CA.4), `docs/CAPABILITY_REGISTRY/SESSION.md` (CA.3), `docs/CAPABILITY_REGISTRY/ML.md` (CA.2), `docs/CAPABILITY_REGISTRY/DSP_MIR.md` (CA.1), `docs/QUALITY/KNOWN_ISSUES.md` (BUG-001, BUG-012, BUG-013, BUG-015, BUG-016), `docs/DECISIONS.md` (D-049, D-050, D-052, D-054, D-058, D-061, D-069, D-088, D-089, D-091), `docs/ENGINEERING_PLAN.md` (Phase U + Phase CA + DASH.7), `docs/UX_SPEC.md` (§3, §6.3, §7, §8, §9.4, §9.5), `docs/RELEASE_NOTES_DEV.md` (`[dev-2026-05-21-c]` / `[dev-2026-05-21-d]` / `[dev-2026-05-21-e]` for the timing-margin chip).

---

## Summary

59 file-level entities audited (~8.3k LoC; kickoff's ~6.9k estimate undercounted by ~20%) across the SwiftUI presentation slice. The slice is the matched consumer side of every engine publisher CA.5 audited; the load-bearing claims the kickoff requires verifying — PlaybackChromeViewModel BUG-015 / D-091 consumer chain, D-091 single-SettingsStore enforcement across the View tree, DASH.7 dashboard surface against D-088 / D-089, U.10 / U.11 timing-margin compliance across the 9 widened test files — all check **clean**. **Zero `broken-but-claimed` findings; zero new BUG entries filed.**

Three small file-internal docstring-vs-code drift findings and the same systemic `ARCHITECTURE.md` Module Map drift CA.1 / CA.2 / CA.3 / CA.4 / CA.5 each surfaced (ViewModels block lists 4 of 12; Views block lists ~20 of 47) — corrected in this increment. One architectural-consistency observation registered as `unverified-claim` (ConnectorPickerView's Apple Music VM creation path differs from the equivalent Spotify OAuth wrapper).

| Verdict | Count | Notes |
|---|---|---|
| `production-active` | 58 | Default verdict. Every public / internal type in scope has a production consumer; documented behaviour matches code. |
| `unverified-claim` | 3 | (1) `DashboardOverlayView.swift:10` file-header comment claims "0.55α" surface tint; code at line 57 uses `.opacity(0.96)` — drift INSIDE the file's own docstring (the ARCHITECTURE.md / CLAUDE.md docs say 0.96α and are correct). (2) `DashboardCardView.swift:5` file-header claims "Clash Display title at 18pt"; code resolves `DashboardTokens.TypeScale.bodyLarge` which is `15` — drift INSIDE the file's own docstring (ARCHITECTURE.md says "Clash Display Medium @ 15pt" and is correct). (3) `ConnectorPickerView.swift:111-115` creates `AppleMusicConnectionViewModel()` inline in the `@ViewBuilder` destination for `.appleMusic`, while the equivalent Spotify path uses an `OAuthSpotifyConnectionWrapper` private struct that owns the VM as `@StateObject`. The Spotify wrapper's docstring (lines 152-160) cites "ViewModel created inline in a `@ViewBuilder` property is destroyed on every body re-evaluation" as the failure mode; the Apple Music path does not apply the same fix. Production impact depends on whether NavigationStack re-evaluates the destination during normal use — likely low because AM has no URL-callback foregrounding scenario, but architecturally inconsistent. Registered as CA.6-FU-3. |
| `broken-but-claimed` | 0 | BUG-015 (the only App-layer-class `broken-but-claimed` finding in scope of the App-layer audit) was filed by CA.4 and Resolved 2026-05-21 — CA.5 verified the engine-adapter side; this audit verifies the View-tree consumer side. |
| `documented-but-missing` | 0 | — |
| `production-orphan` | 0 | No orphans found at file or field level within Views/ + ViewModels/. (CA.5-FU-1's `MultiDisplayToastBridge.coalesceTask` / `pendingEvents` cluster landed 2026-05-21 in commit `688095d4` per kickoff's status-on-entry; the file is in `Services/` and out of CA.6 scope.) |
| `built-but-undocumented` | 2 large | (a) `ARCHITECTURE.md §Module Map PhospheneApp/ViewModels/` block lists **4 of 12** ViewModels (8 missing: `DashboardOverlayViewModel`, `EndSessionConfirmViewModel`, `PlanPreviewViewModel`, `PlaybackChromeViewModel`, `PreparationErrorViewModel`, `PreparationProgressViewModel`, `ReadyViewModel`, `SettingsViewModel`, `ToastManager` — `DashboardOverlayViewModel` lives in `Views/Dashboard/` but is registered under `Views/Dashboard/` block, not `ViewModels/`; recount: 8 from `ViewModels/` proper + correctly-listed `DashboardOverlayViewModel`). (b) `ARCHITECTURE.md §Module Map PhospheneApp/Views/` block lists ~20 of 47 (27 missing — full list in §Cross-references below). Same systemic pattern as CA.1 / CA.2 / CA.3 / CA.4 / CA.5. Plus three minor structural drift items in §UI Layer (lines 220-242): `NoAudioSignalBadge` is named but the file was renamed to `ListeningBadgeView` in U.6 (file-header at `ListeningBadgeView.swift:3` confirms); the keyboard-shortcut list omits `Shift+→` / `Shift+←` (force-immediate nudge per U.6b), `Z` (undo), `M` (mood-lock), `Esc` (end session), `Shift+?` (shortcut help); `DashboardOverlayView` (DASH.7 surface; PlaybackView Layer 6) is not mentioned in the §UI Layer paragraph at all. |
| `stub` | 0 | — |
| `dead` | 0 | — |
| `boundary-noted` | 5 | App-View ↔ App-Service (PlaybackView's 9 `@State` services audited from the View side; CA.5 already audited the Service classes); App-View ↔ VisualizerEngine (publisher-injection pattern via `engine.$xxx.eraseToAnyPublisher()` from ContentView); ViewModel ↔ SessionManager (SessionStateViewModel, PlaybackChromeViewModel, ReadyViewModel, etc. subscribe to `sessionManager.$state` or methods); ViewModel ↔ SettingsStore (read via `@ObservedObject SettingsViewModel`, never via direct `@StateObject SettingsStore`); ViewModel ↔ DSP (DashboardOverlayViewModel ingests `DashboardSnapshot` carrying BeatSyncSnapshot / StemFeatures / PerfSnapshot). All boundary verdicts complete; producer-side details documented in the prior four audits. |
| `boundary-deferred` | 0 | — |

**Top findings, ranked.**

1. **PlaybackChromeViewModel BUG-015 / D-091 consumer chain verified clean.** The `currentTrackIndexPublisher` flows producer-to-consumer with no intermediate string-match step: `VisualizerEngine.swift:77` (`@Published var currentTrackIndex: Int?`) → `VisualizerEngine+Capture.swift:152` (writes the plan-resolved index on track change) → `ContentView.swift:85` (`engine.$currentTrackIndex.eraseToAnyPublisher()`) → `PlaybackView.swift:74,90` (relay) → `PlaybackChromeViewModel.swift:121,169-176` (subscribes, assigns to `private var currentTrackIndex: Int?`) → `:242-254` (`refreshProgress()` reads `currentTrackIndex ?? -1` directly into `SessionProgressData`). **No lowercased title+artist string matching anywhere in the chain.** The pre-QR.4 Failed Approach #56 pattern is fully eliminated. PlaybackChromeIndexBindingTests is the regression gate.

2. **D-091 single-SettingsStore enforcement verified clean across the View tree.** Cited grep:
   ```
   $ grep -rnE "@StateObject.*SettingsStore" PhospheneApp PhospheneAppTests
   PhospheneApp/PhospheneApp.swift:25:    @StateObject private var settingsStore = SettingsStore()
   PhospheneApp/Views/Playback/PlaybackView.swift:52:    /// `@StateObject SettingsStore()` here creates a parallel state world —
   PhospheneAppTests/SettingsStoreEnvironmentRegressionTests.swift:42:        @StateObject var shadowStore = SettingsStore(...)
   PhospheneAppTests/SettingsStoreEnvironmentRegressionTests.swift:148: #expect(!src.contains("@StateObject private var settingsStore = SettingsStore()"),
   ```
   ONE legitimate construction at the app entry (`PhospheneApp.swift:25`); ONE consumer via `@EnvironmentObject` at `PlaybackView.swift:55` (the QR.4 correction); the `PlaybackView.swift:52` hit is a comment WARNING against the bad pattern (not actual usage). All Settings sub-sections (`AudioSettingsSection`, `VisualsSettingsSection`, `DiagnosticsSettingsSection`, `AboutSettingsSection`) take `SettingsViewModel` as `@ObservedObject` and never see `SettingsStore` directly. The single-instance + EnvironmentObject + ViewModel-facade topology is the canonical D-091 shape.

3. **DASH.7 dashboard surface verified clean against D-088 / D-089.** Every load-bearing claim in ARCHITECTURE.md `§Module Map Views/Dashboard/` lands in the code:
   - `DashboardOverlayView.swift:49` — `DarkVibrancyView()` as backdrop ✓
   - `DashboardOverlayView.swift:57` — `Color(nsColor: DashboardTokens.Color.surface).opacity(0.96)` ✓ (the file-header comment at line 10 claims "0.55α"; this is a docstring-vs-code drift INSIDE the file — flagged as `unverified-claim` #1)
   - `DashboardOverlayView.swift:61-64` — `RoundedRectangle(cornerRadius: 6).strokeBorder(...).opacity(0.6), lineWidth: 1)` ✓ (1 pt border)
   - `DashboardOverlayView.swift:65` — `.environment(\.colorScheme, .dark)` ✓ (lock)
   - `DashboardOverlayView.swift:44` — `.frame(width: 320, alignment: .leading)` ✓ (panel width)
   - `DarkVibrancyView.swift:14-15` — `NSVisualEffectView` with `.appearance = NSAppearance(named: .vibrantDark)`, `.material = .hudWindow`, `.blendingMode = .withinWindow` ✓
   - `DashboardOverlayViewModel.swift:37` — `static let throttleInterval: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(33)` ✓ (~30 Hz)
   - `DashboardOverlayViewModel.swift:42-54` — Combine pipeline `snapshotPublisher.compactMap { $0 }.throttle(for: .milliseconds(33), scheduler: .main, latest: true).sink { ... }` ✓
   - `DashboardOverlayViewModel.swift:59-61` — `ingestForTest(_:)` test seam bypasses the throttled subscription ✓
   - `DashboardOverlayViewModel.swift:88` — `private let capacity = StemEnergyHistory.capacity` (240 samples per CA.5's reading of `StemEnergyHistory` in the Renderer module)
   - `DashboardRowView.swift` — 4 row variants `.singleValue / .bar / .progressBar / .timeseries` ✓; `.singleValue` inlined per D-089 line 60-76 (label-left + value-right at 13pt mono, replacing the DASH.7 stacked layout); `.progressBar` value column widened to 110pt with `.fixedSize(horizontal: true)` per D-089; no SF Symbols; labels via `DashboardTokens.TypeScale.label` + `labelTracking` (1.5)
   - `DashboardCardView.swift:30-34` — title via `font(.custom(fontResolution.displayFontName, size: DashboardTokens.TypeScale.bodyLarge = 15, relativeTo: .title3))` ✓ (the file-header comment at line 5 claims "18pt"; this is a docstring-vs-code drift INSIDE the file — flagged as `unverified-claim` #2)

4. **U.10 / U.11 timing-margin compliance verified clean across the 9 widened test files** (the `[dev-2026-05-21-c]` + `[dev-2026-05-21-d]` chip widening landed 2026-05-21). Per the U.11 baselines documented in CLAUDE.md ("700 ms wait for 300 ms debounce; 250–400 ms wait for connect/login completions") and U.10 ("URLProtocol-stub tests require `@Suite(.serialized)`"):

   | File | Site (or class) | Pre-chip | Post-chip | U.11 minimum | Verdict |
   |---|---|---|---|---|---|
   | `ToastManagerTests.swift` | `autoDismiss_afterDuration` — 50 ms toast | 400 ms | 1000 ms | ≥ 4× duration | **production-active** (20× the 50 ms duration) |
   | `AppleMusicConnectionViewModelTests.swift` | `noCurrentPlaylist` 2s auto-retry | 500 ms | 1500 ms | ≥ 700 ms (debounce class) | **production-active** |
   | `AppleMusicConnectionViewModelTests.swift` | 4 sibling waits | 50 ms | 300 ms | ≥ 250 ms (connect/login class) | **production-active** |
   | `ReadyViewTimeoutIntegrationTests.swift` | `retry_resetsDetectorAndClearsTimeout` 250 ms FirstAudioDetector timer | 600 ms | 1500 ms | ≥ 4× timer | **production-active** (6× the 250 ms timer) |
   | `ReadyViewModelTests.swift` | 3 sites (siblings discovered in `[dev-2026-05-21-d]`) | 600 ms | 1500 ms | ≥ 4× timer | **production-active** |
   | `PlaybackChromeViewModelTests.swift` | `overlayAutoHides_afterDelay` — InstantDelay-driven 3s timer | 300 ms | 1000 ms | ≥ 700 ms | **production-active** |
   | `SpotifyConnectionViewModelTests.swift` | 16 sites: 300 ms paste-debounce | 700 ms | 1500 ms | ≥ 700 ms | **production-active** (5× the 300 ms debounce; baseline says 700 ms = 2.3× — code uses 5× for additional headroom) |
   | `SpotifyConnectionViewModelTests.swift` | 5 sites: post-connect actor-hop | 250 ms | 700 ms | ≥ 250 ms | **production-active** (700 ms is upper edge of baseline — within bracket) |
   | `SpotifyConnectionViewModelTests.swift` | 4 sites: rate-limit retry | 400 ms | 400 ms | ≥ 250 ms | **production-active** |
   | `NetworkRecoveryCoordinatorTests.swift` | 5 sites: `recoveryDebounceSecs (2.0) + headroom` | +0.1 | +1.0 | ≥ 0.5× debounce | **production-active** (50% headroom on a 2 s debounce — substantial; the U.11 baseline is for 300 ms debounce; this is a different scale) |
   | `LiveAdaptationToastBridgeTests.swift` | 3 sites: 2 s coalescing window | 2600 ms | 4000 ms | ≥ 2× window | **production-active** (2× the 2 s window) |
   | `SpotifyOAuthTokenProviderTests.swift` | not widened (separate test-env clientID injection per `[dev-2026-05-21-d]`) | n/a | n/a | n/a | `@Suite("SpotifyOAuthTokenProvider", .serialized)` at line 99 ✓ U.10 compliant |

   **`@Suite(.serialized)` U.10 audit:** two URLProtocol-stub-using App test suites are present — `SpotifyOAuthTokenProviderTests.swift:99` (`@Suite("SpotifyOAuthTokenProvider", .serialized)`) ✓ and `SpotifyKeychainStoreTests.swift:9` (`@Suite("SpotifyKeychainStore", .serialized)`) ✓ (the latter doesn't use URLProtocol but uses keychain — also benefits from serialization). No other App test suites use URLProtocol stubs (greppable as `URLProtocol` returns only the two Spotify test files plus the `OAuthStubURLProtocol` private class inside SpotifyOAuthTokenProviderTests).

   **Net:** the chip's claim of U.11 compliance holds across all 9 files. No `unverified-claim` margin findings.

5. **The Spotify state machine's three U.11 cases are all wired through the View tree.** `SpotifyConnectionViewModel.SpotifyConnectionState` has 12 cases (the original 9 + U.11's 3 additions: `.requiresLogin`, `.waitingForCallback`, `.authFailure`). `SpotifyConnectionView.swift:70-100` switch is exhaustive against all 12 cases (verified by the Explore agent's per-line reading). The U.11 cases each have a render arm. CLAUDE.md's U.11 learning ("When adding enum cases to a VM's state type, update every `switch` in the corresponding view simultaneously") is satisfied.

6. **MetalView NSViewRepresentable contract verified clean.** `MetalView.swift` (50 LoC, struct conforming to `NSViewRepresentable`) wraps `MTKView` and takes `context: MetalContext` + `pipeline: RenderPipeline` init parameters. The MTKView is configured once in `makeNSView`; `updateNSView` does not re-construct any pipeline state. The full rendering pipeline ownership stays with `VisualizerEngine`; `MetalView` is purely a SwiftUI bridge. (`RenderPipeline` internals are deferred to CA-Renderer.)

7. **DashboardOverlayViewModel ingestForTest test seam present.** Line 59-61: `func ingestForTest(_ snapshot: DashboardSnapshot) { apply(snapshot) }` bypasses the throttled `Combine` subscription so tests can drive deterministic snapshots without 33 ms throttle quantization. Pattern matches the ARCHITECTURE.md `§Module Map Views/Dashboard/` claim.

8. **PlaybackView ownership topology matches CLAUDE.md / ARCHITECTURE.md.** PlaybackView owns: 4 `@StateObject` view models (`chromeVM: PlaybackChromeViewModel`, `toastManager: ToastManager`, `endSessionVM: EndSessionConfirmViewModel`, `dashboardVM: DashboardOverlayViewModel`); 8 `@State` services (`keyMonitor: PlaybackKeyMonitor`, `fullscreenObserver: FullscreenObserver`, `actionRouter: DefaultPlaybackActionRouter?`, `playbackErrorBridge: PlaybackErrorBridge?`, `displayManager: DisplayManager?`, `multiDisplayBridge: MultiDisplayToastBridge?`, `displayChangeCoordinator: DisplayChangeCoordinator?`, `captureModeSwitchCoordinator: CaptureModeSwitchCoordinator?`) + `@State currentRegistry: PlaybackShortcutRegistry?`; 2 `@EnvironmentObject` (`engine: VisualizerEngine`, `settingsStore: SettingsStore`); 4 `@State` UI flags (`showDebug`, `showHelp`, `showPlanPreview`, `showSettings`). Lifecycle: `setup()` at `.onAppear` (line 172, 190-236) wires the action router, fullscreen + display + capture-mode + error coordinators, and installs the key monitor; `teardown()` at `.onDisappear` (line 173, 238-241) uninstalls. CA.5's view of the Service-class lifecycle held; CA.6 confirms the View-side ownership matches.

9. **Six top-level `SessionState` views and the chrome subviews have proper `accessibilityIdentifier` per UX_SPEC §3.** Static IDs declared:
   - `phosphene.view.idle` — IdleView.swift:13 ✓
   - `phosphene.view.connecting` — ConnectingView.swift:17 ✓
   - `phosphene.view.preparing` — PreparationProgressView.swift:24 ✓
   - `phosphene.view.ready` — ReadyView.swift:27 ✓
   - `phosphene.view.playing` — PlaybackView.swift:30 ✓
   - `phosphene.view.ended` — EndedView.swift:21 ✓
   - Plus connector / settings / playback-chrome sub-IDs across all interactive surfaces.

10. **CA.5-FU-2 status (LiveAdaptationToastBridge engine-event docstring)** — **still pending** as of CA.6 entry. The bridge's docstring still claims two observation sources (user actions + engine events) while only user-action acks reach `emitAck()`. CA.6 verifies no further drift but does not propose a fix (it remains a product call awaiting Matt's input). The Apple-side consumers (`DefaultPlaybackActionRouter` 11 sites) all reach `LiveAdaptationToastBridge.emitAck` correctly from the View-tree perspective — the SettingsViewModel binding for `phosphene.settings.visuals.showLiveAdaptationToasts` (`SettingsViewModel.swift:114-117`) flows to the UserDefaults flag the bridge gates emission on.

**Four follow-up items registered in [§Follow-up Backlog](#follow-up-backlog).**

---

## Sub-scope decision

Pass 0 default applied: **no split**. 59 files / 8,285 LoC fits cleanly in one auditor session via the hybrid direct-read + parallel-Explore-agent approach CA.5 validated. Used direct reads for all 12 ViewModels (largest 308 LoC) + 5 Dashboard files + PlaybackView (355 LoC). Used three parallel Explore agents for the remaining 42 Views (≤ 263 LoC each). Visibility verification grep + consumer-tracing grep + D-091 grep ran across the full scope. Total Pass-1 wall-clock: ~5 minutes for 8.3k LoC including grep verification.

The kickoff's `~6.9k LoC` estimate undercounted by ~20% (actual 8,285 LoC) — minor; methodology unaffected.

---

## Pass 0 — Kickoff cross-check vs KNOWN_ISSUES.md

Verified before Pass 1 began:
- **BUG-001** (Money 7/4 stays REACTIVE) — Open ✓ (kickoff claim correct)
- **BUG-012** (MPSGraph EXC_BAD_ACCESS) — Open ✓ (kickoff claim correct; CA.6 does not naturally encounter the 8 instrumented files — none are in `Views/` or `ViewModels/`)
- **BUG-013** (Soundcharts time_signature absence) — Open ✓ (kickoff claim correct)
- **BUG-015** (`applyLiveUpdate` wire) — Resolved 2026-05-21 ✓ (kickoff claim correct; CA.5 verified the producer side; CA.6 verifies the consumer-side chain)
- **BUG-016** (Lumen Mosaic) — Open ✓ (kickoff claim correct; CA.6 does not encounter the apply-path code which is in CA.5 scope)
- **CA.5-FU-2** (LiveAdaptationToastBridge engine-event docstring) — still pending ✓ (kickoff claim correct)
- **CA.5-FU-1** (MultiDisplayToastBridge dead fields) — landed 2026-05-21 in commit `688095d4` ✓ (kickoff status-on-entry claim correct)
- **CA.5-FU-3** (MusicKitFetcher → ITunesSearchFetcher rename) — landed 2026-05-21 in commit `b8952fda` ✓ (kickoff status-on-entry claim correct)

**No kickoff staleness found.** This is the third audit in a row (CA.4, CA.5, CA.6) where Pass 0 returned zero drift; the rule continues to be cheap insurance.

---

## Findings by verdict

### broken-but-claimed (BUG entries filed)

**None filed in this increment.** BUG-015 (the only App-layer-class `broken-but-claimed` finding in scope of the matched presentation slice) was already filed by CA.4, Resolved 2026-05-21, and CA.5 verified the engine-adapter wire shape clean. CA.6 verifies the consumer-side chain clean (see §Verification-of-PlaybackChromeViewModel-BUG-015-D-091-consumer-chain below).

### production-orphan

**None.** Every public / internal type, every public / internal method in scope has at least one production consumer.

Two candidates were investigated and rejected:
- **`AppleMusicConnectionViewModel.cancelRetry()`** — invoked at `AppleMusicConnectionView.swift:33` on `.onDisappear`. Production-active.
- **`ReadyViewModel.planPreviewEnabled`** (`@Published var`, default `true` with a TODO note "U.5.B: flip to true once PlanPreviewView is wired") — consumed at `ReadyView.swift:142` (`.disabled(!viewModel.planPreviewEnabled)`) and `:143` (`.opacity(...)`). Production-active; the property is the gate for the preview-plan CTA and is now `true` by default (so the CTA is always enabled). The TODO comment is stale (the flag DOES work; the gate has long since shipped) but the field is not orphaned.

### unverified-claim

**1. `DashboardOverlayView.swift:10` file-header docstring claims surface tint "0.55α"; code at line 57 uses `.opacity(0.96)`.**

```swift
// Comment block claim:
// + an explicit `surface` tint at 0.55α
// Code at line 57:
Color(nsColor: DashboardTokens.Color.surface).opacity(0.96)
```

The ARCHITECTURE.md `§Module Map Views/Dashboard/` block correctly says "0.96α"; the in-file docstring is stale. Comment block at lines 50-56 BELOW the discrepancy actually re-explains the reasoning for the high opacity ("near-opaque … WCAG AA contrast for body/teal/coral text in the worst case"). The "0.55α" in the file's intro paragraph appears to be a holdover from an early DASH.7 draft. Registered as **CA.6-FU-1**.

**2. `DashboardCardView.swift:5` file-header docstring claims "Clash Display title at 18pt"; code resolves `DashboardTokens.TypeScale.bodyLarge` which is `15`.**

```swift
// Comment claim:
// is now a typographic section — Clash Display title at 18pt, followed
// Code at lines 30-34:
.font(.custom(
    fontResolution.displayFontName,
    size: DashboardTokens.TypeScale.bodyLarge,   // = 15
    relativeTo: .title3
))
```

The ARCHITECTURE.md `§Module Map Views/Dashboard/` block correctly says "Clash Display Medium @ 15pt"; the in-file docstring is stale. Registered as **CA.6-FU-2**.

**3. `ConnectorPickerView.swift:111-115` creates `AppleMusicConnectionViewModel()` inline in the `@ViewBuilder` `destination(for: .appleMusic)`, while the equivalent Spotify path uses an `OAuthSpotifyConnectionWrapper` private struct that owns the VM as `@StateObject` to preserve it across body re-evaluations.**

```swift
// Apple Music side (inline VM creation):
case .appleMusic:
    AppleMusicConnectionView(
        viewModel: AppleMusicConnectionViewModel(),   // ← created inline
        onConnect: onConnect,
        onUseSpotifyInstead: { dismiss() }
    )

// Spotify side (StateObject wrapper preserves VM across re-evals):
private struct OAuthSpotifyConnectionWrapper: View {
    @StateObject private var viewModel: SpotifyConnectionViewModel
    // … see lines 152-160 for the rationale comment …
}
```

The Spotify wrapper's docstring (`ConnectorPickerView.swift:152-160`) cites the failure mode explicitly: *"A ViewModel created inline in a `@ViewBuilder` property is destroyed on every body re-evaluation. … When the user completes the PKCE browser flow and macOS routes `phosphene://spotify-callback` back to the app, SwiftUI triggers a body re-evaluation of ConnectorPickerView."*

The Apple Music side does not have an equivalent URL-callback foregrounding scenario, but other parent body re-evaluations (e.g., `viewModel.appleMusicRunning` changing via the 250 ms-debounced NSWorkspace observer in `ConnectorPickerViewModel`) could still trigger the same defect class — if SwiftUI's `NavigationStack` calls the `navigationDestination(for:)` closure on parent re-evals while the user is on the AppleMusic destination, the inline `AppleMusicConnectionViewModel()` would be re-instantiated. Whether this actually happens in production depends on SwiftUI's NavigationStack behaviour under destination-closure re-eval.

**Production impact: likely low** — Apple Music has no URL-callback scenario, and the AM connection VM's state machine is simpler (no in-flight Task across screens). But the architectural inconsistency is real, and a parent re-eval mid-AM-flow would re-trigger `.idle → .connecting` from scratch and orphan any in-flight 2 s auto-retry Task. Registered as **CA.6-FU-3**.

### documented-but-missing

**None this increment.** Every View / ViewModel that ARCHITECTURE.md / DECISIONS.md / CLAUDE.md / UX_SPEC claims exists was verified against code.

### built-but-undocumented

**1. `ARCHITECTURE.md §Module Map PhospheneApp/Views/` block lists ~20 of 47 files (27 missing).**

**Listed (~20):** `MetalView`, `DebugOverlayView`, `Dashboard/` subblock (5 files: `DashboardOverlayView`, `DashboardCardView`, `DashboardRowView`, `DarkVibrancyView`, `DashboardOverlayViewModel`), `ConnectorType`, `ConnectorTileView`, `ConnectorPickerView`, `AppleMusicConnectionView`, `SpotifyConnectionView`, `Onboarding/PermissionOnboardingView`, `Onboarding/PhotosensitivityNoticeView`, `Idle/IdleView`, `Connecting/ConnectingView`, `Preparation/PreparationProgressView`, `Ready/ReadyView`, `Playback/PlaybackView`, `Ended/EndedView`.

**Missing (27):**
- Root-level (3): `FullScreenErrorView.swift`, `QualityGradeIndicator.swift`, `SettingsView.swift`, `TrackPreparationRow.swift`, `TrackPreparationStatusIcon.swift`.
- `Playback/` (10 of 11 missing, only `PlaybackView` listed): `ListeningBadgeView`, `OverlayBackdropStyle`, `PlaybackChromeView`, `PlaybackControlsCluster`, `SessionProgressDotsView`, `ShortcutHelpOverlayView`, `ToastContainerView`, `ToastView`, `TrackChangeAnimationView`, `TrackInfoCardView`.
- `Preparation/` (2 missing): `PreparationFailureView`, `TopBannerView`.
- `Ready/` (4 missing): `PlanPreviewRowView`, `PlanPreviewTransitionView`, `PlanPreviewView`, `ReadyPulsingBorder`.
- `Settings/` (6 missing): `AboutSettingsSection`, `AudioSettingsSection`, `DiagnosticsSettingsSection`, `PresetCategoryBlocklistPicker`, `SourceAppPicker`, `VisualsSettingsSection`.

**Plus three minor `§UI Layer` paragraph drift items** at ARCHITECTURE.md lines 220-242:
- **`NoAudioSignalBadge` is named** but the file was renamed to `ListeningBadgeView` in U.6. The new file's header (`ListeningBadgeView.swift:3`) explicitly says "Replaces the legacy NoAudioSignalBadge with UX-spec copy and a subtle spinner." `PlaybackChromeView.swift:78` instantiates `ListeningBadgeView`; no `NoAudioSignalBadge` exists in source.
- **Keyboard-shortcut list omits the U.6b additions:** `Shift+→` / `Shift+←` (force-immediate nudge per UX_SPEC §7.4), `Z` (undo last adaptation), `M` (mood-lock), `Esc` (end session with confirm), `Shift+?` (shortcut help). All these are wired in `PlaybackShortcutRegistry` (per CA.5) and the `PlaybackView.buildRegistry(router:)` factory (per this CA.6 reading at lines 248-354).
- **`DashboardOverlayView` (DASH.7 surface; PlaybackView Layer 6) is not mentioned in the §UI Layer paragraph** at all, despite being one of the load-bearing user-facing surfaces. The Module Map's `Views/Dashboard/` sub-block does describe it; the §UI Layer summary is stale relative to DASH.7.

Doc-drift correction applied in this increment.

**2. `ARCHITECTURE.md §Module Map PhospheneApp/ViewModels/` block lists 4 of 12 ViewModels (8 missing).**

**Listed (4):** `SessionStateViewModel`, `ConnectorPickerViewModel`, `AppleMusicConnectionViewModel`, `SpotifyConnectionViewModel`.

**Missing (8):** `EndSessionConfirmViewModel`, `PlanPreviewViewModel`, `PlaybackChromeViewModel`, `PreparationErrorViewModel`, `PreparationProgressViewModel`, `ReadyViewModel`, `SettingsViewModel`, `ToastManager`. Note: `DashboardOverlayViewModel` lives in `Views/Dashboard/` per the actual filesystem layout, and the `Views/Dashboard/` sub-block in ARCHITECTURE.md correctly lists it there; the count above is for `PhospheneApp/ViewModels/` proper.

Doc-drift correction applied in this increment.

### boundary-noted

The audit produced no `boundary-deferred` items. The following App-View-layer boundary surfaces are noted (verdict complete; no future re-audit required):

- **View ↔ App-Service.** PlaybackView owns `CaptureModeSwitchCoordinator`, `DisplayChangeCoordinator`, `NetworkRecoveryCoordinator` (the latter actually owned by `PreparationProgressView`), `FullscreenObserver`, `PlaybackKeyMonitor`, `MultiDisplayToastBridge`, `PlaybackErrorBridge`, `LiveAdaptationToastBridge` as `@State`. CA.5 audited those Service classes; this audit confirmed the View-side instantiation patterns (`@State` is correct because the services are lightweight reference types not requiring `ObservedObject`-style change notification). The lifecycle hooks (`setup()` at `.onAppear` line 190-236; `teardown()` at `.onDisappear` line 238-241) wire and un-wire the services correctly. **Verdict: complete.**

- **View ↔ VisualizerEngine.** `ContentView.swift:85` binds publishers via `engine.$xxx.eraseToAnyPublisher()` (BUG-015 `currentTrackIndex`, livePlannedSession, dashboardSnapshot, audioSignalState, currentPresetName). PlaybackView relays via `init` parameters to `PlaybackChromeViewModel`, `DashboardOverlayViewModel`. ReadyView, EndedView take engine references via constructor. IdleView reads `engine` via `@EnvironmentObject`. The publisher-injection pattern is consistent across the View tree; no view holds a direct strong reference to the engine that isn't an `@EnvironmentObject`. **Verdict: complete.**

- **ViewModel ↔ SessionManager.** `SessionStateViewModel` subscribes to `sessionManager.$state` via `.assign(to: \.state, on: self)` (line 54-57). `PlaybackChromeViewModel` consumes the engine's live track / preset / plan publishers, NOT `sessionManager` directly (the plan publishes via engine). `ReadyViewModel`, `PreparationProgressViewModel`, `PreparationErrorViewModel`, `EndSessionConfirmViewModel` each take `sessionManager` as an init parameter and call methods on it (`sessionManager.endSession()`, `sessionManager.beginPlayback()`, etc.) — no ViewModel re-instantiates `SessionManager` or holds it as a parallel state. CA.3 closed the SessionManager side. **Verdict: complete.**

- **ViewModel ↔ SettingsStore.** The single `SettingsStore` is injected via `@EnvironmentObject` to PlaybackView (and never to other views). `SettingsView` takes `store: SettingsStore` as init parameter, builds `@StateObject SettingsViewModel(store: store)`. All Settings sub-sections (`AboutSettingsSection`, `AudioSettingsSection`, `DiagnosticsSettingsSection`, `VisualsSettingsSection`) bind to `viewModel: SettingsViewModel` as `@ObservedObject`. The two consumers reading SettingsStore directly outside the SettingsView tree are: PhospheneApp.swift (the single-instance owner) + `PlaybackView.swift:184` (`SettingsView(store: settingsStore)` passing the store down). The shape matches D-091 / Failed Approach #55. **Verdict: complete.**

- **ViewModel ↔ DSP / ML (via engine snapshots).** `DashboardOverlayViewModel` subscribes to a `DashboardSnapshot?` publisher (produced by `VisualizerEngine+Dashboard.publishDashboardSnapshot(stems:)` per CA.5's reading). The snapshot carries `BeatSyncSnapshot` (DSP), `StemFeatures` (ML/DSP), `PerfSnapshot` (Renderer). The throttle (33 ms / ~30 Hz) and the in-memory `MutableStemHistory` ring (240 samples per stem) live in the ViewModel; no DSP / ML code is touched by the consumer. CA.1 + CA.2 closed those producer sides. **Verdict: complete.**

### production-active

(See per-file index below. The 58 `production-active` files concentrate by family; per-family rollups follow rather than per-file rows, mirroring CA.3 / CA.4 / CA.5's consolidated form. The three non-`production-active` rows are marked inline.)

---

## Per-file capability index

Consolidation: 58 of 59 files concentrate on `production-active` (with one of those — `ConnectorPickerView` — carrying a co-located `unverified-claim` for its AppleMusic destination path). The per-file index below mirrors CA.3 / CA.4 / CA.5's consolidated form.

### ViewModels/ (12 files, ~2,015 LoC)

#### SessionStateViewModel.swift (65 lines) — `production-active`

`@MainActor final class SessionStateViewModel: ObservableObject`. Bridges `SessionManager.$state` into SwiftUI via Combine `.assign(to: \.state, on: self)`. Also forwards `AccessibilityState.reduceMotion` for ContentView to thread into PlaybackView / ReadyView.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `SessionStateViewModel` class | `production-active` | `PhospheneApp` (constructs once), `ContentView` (consumes `state`) | U.1 |
| `@Published state: SessionState`, `@Published reduceMotion: Bool` | `production-active` | ContentView routing + PlaybackView / ReadyView | — |
| `init(sessionManager:accessibilityState:)` | `production-active` | `PhospheneApp` | U.9 — sources reduce-motion from `AccessibilityState` (CA.5-audited service) |

#### PlaybackChromeViewModel.swift (255 lines) — `production-active`

`@MainActor final class PlaybackChromeViewModel: ObservableObject`. Drives the auto-hiding overlay chrome during `.playing`. **Load-bearing consumer of BUG-015 `currentTrackIndex` publisher + D-091 plan-index propagation.**

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `TrackInfoDisplay`, `PresetDisplay`, `OrchestratorDisplayState`, `SessionProgressData` value types | `production-active` | View layer | U.6 |
| `PlaybackChromeViewModel` class | `production-active` | `PlaybackView.@StateObject` (line 40) | U.6 |
| `@Published currentTrack`, `currentPreset`, `orchestratorState`, `sessionProgress`, `overlayVisible`, `showListeningBadge`, `reduceMotion`, `isBackgroundPreparationActive` | `production-active` | `PlaybackChromeView` + `TrackInfoCardView` + `PlaybackControlsCluster` + `ListeningBadgeView` + `PreparationBackgroundIndicator` (in PlaybackChromeView) | — |
| `init(...)` — 7 publisher-injected parameters | `production-active` | PlaybackView passes engine publishers + accessibility | D-091 / QR.4 |
| `currentTrackIndexPublisher` consumer chain (`init` line 121; subscription line 169-176; refresh line 242-254) | `production-active` | Bound directly to `engine.$currentTrackIndex` via ContentView | **D-091 / Failed Approach #56 compliance** |
| `onActivity()` / `toggleOverlay()` / `scheduleHide()` | `production-active` | PlaybackKeyMonitor, PlaybackChromeView | — |
| `refreshProgress()` (line 242) | `production-active` | Internal subscribers | No lowercased title+artist string match ✓ |
| `delay` (DelayProviding) | `production-active` | `scheduleHide` 3 s | — |

#### DashboardOverlayViewModel.swift (108 lines) — `production-active`

`@MainActor final class DashboardOverlayViewModel: ObservableObject`. Subscribes to engine snapshot publisher, throttles ~30 Hz, maintains stem-energy history, publishes `[DashboardCardLayout]`. **DASH.7 / D-089 surface.** Note: lives in `Views/Dashboard/` per the filesystem layout (not in `ViewModels/`), reflecting the architectural decision to keep dashboard-internal state with its View family.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `DashboardOverlayViewModel` class | `production-active` | `PlaybackView.@StateObject` (line 43, 99-101) | DASH.7 |
| `@Published layouts: [DashboardCardLayout]` | `production-active` | `DashboardOverlayView.viewModel` | — |
| `static throttleInterval: .milliseconds(33)` | `production-active` | Internal Combine throttle | DASH.7 / D-089 (~30 Hz) |
| `init(snapshotPublisher: AnyPublisher<DashboardSnapshot?, Never>)` | `production-active` | PlaybackView | — |
| `ingestForTest(_:)` test seam | `production-active` | DashboardOverlayViewModelTests | DASH.7 |
| `MutableStemHistory` (private struct, 240-sample ring per stem) | `production-active` | Internal | DASH.7 |
| 3 card builders (BeatCardBuilder / StemsCardBuilder / PerfCardBuilder) | `production-active` (defined in Renderer module per CA.5; consumed here) | Internal | — |

#### SpotifyConnectionViewModel.swift (308 lines) — `production-active`

`@MainActor final class SpotifyConnectionViewModel: ObservableObject`. State machine over 12-case `SpotifyConnectionState` enum. 300 ms debounce on text changes. `[2.0s, 5.0s, 15.0s]` rate-limit retry sequence. U.11: 3 new cases (`.requiresLogin`, `.waitingForCallback`, `.authFailure`). PKCE OAuth `loginAction` injected from ConnectorPickerView.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `SpotifyConnectionState` enum (12 cases) | `production-active` | SpotifyConnectionView switch (lines 70-100) | U.11 — exhaustive coverage verified |
| `SpotifyConnectionViewModel` class | `production-active` | `SpotifyConnectionView`, `OAuthSpotifyConnectionWrapper.@StateObject` | U.11 |
| `text`, `state`, `isConnecting` @Published | `production-active` | SpotifyConnectionView | — |
| `init(connector:delayProvider:loginAction:oauthProvider:)` | `production-active` | `OAuthSpotifyConnectionWrapper.init` (line 168-183) | — |
| `connect(startSession:)` / `login(startSession:)` | `production-active` | SpotifyConnectionView Continue / Login buttons | — |
| `observeTextChanges()` + `handleTextChange` + `parseURL` (300 ms debounce) | `production-active` | Internal `text` `$` sink | — |
| `runConnect` / `runLogin` / `applyResult` / `retryAfterRateLimit` | `production-active` | Internal | U.11 |
| `attempt(source:)` → `AttemptResult` | `production-active` | Internal | — |
| `retryDelays = [2.0, 5.0, 15.0]` | `production-active` | `retryAfterRateLimit` | — |

#### AppleMusicConnectionViewModel.swift (152 lines) — `production-active`

`@MainActor final class AppleMusicConnectionViewModel: ObservableObject`. State machine over 7-case `AppleMusicConnectionState` enum. 2 s `delayProvider.sleep` auto-retry on `.noCurrentPlaylist`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `AppleMusicConnectionState` enum (7 cases) | `production-active` | AppleMusicConnectionView switch | U.3 |
| `AppleMusicConnectionViewModel` class | `production-active` | `ConnectorPickerView.destination(for: .appleMusic)` (inline; see `unverified-claim` #3) | U.3 |
| `state` @Published | `production-active` | AppleMusicConnectionView | — |
| `beginConnect()`, `retry()`, `openAppleMusic()`, `openAutomationSettings()` | `production-active` | AppleMusicConnectionView | — |
| `cancelRetry()` | `production-active` | AppleMusicConnectionView `.onDisappear` line 33 | — |
| `performConnect()` / `runConnect()` / `scheduleAutoRetry()` / `userMessage(for:)` | `production-active` | Internal | — |

#### ConnectorPickerViewModel.swift (107 lines) — `production-active`

`@MainActor final class`. NSWorkspace observers for Apple Music launch/terminate (nonisolated(unsafe) per the U.3 pattern). 250 ms debounce.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `ConnectorPickerViewModel` class | `production-active` | `ConnectorPickerView.@StateObject` | U.3 |
| `@Published appleMusicRunning: Bool` | `production-active` | `ConnectorPickerView.appleMusicTile` | — |
| `localFolderEnabled: Bool = false` | `production-active` (gating UI to disabled tile) | `ConnectorPickerView.localFolderTile` | U.3 |
| `setupWorkspaceObservers()` + `scheduleUpdate(running:)` 250 ms debounce | `production-active` | Internal | — |
| `openAppleMusic()` | `production-active` | `ConnectorPickerView.appleMusicTile` (disabled-state secondary action) | — |
| nonisolated(unsafe) `launchObserver` / `terminateObserver` | `production-active` | Used in deinit | U.3 |

#### ReadyViewModel.swift (172 lines) — `production-active`

`@MainActor final class ReadyViewModel: ObservableObject`. Source-aware headline copy + `FirstAudioDetector` ownership + 90 s timeout + plan-publisher subscription.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `ReadyViewModel` class | `production-active` | `ReadyView.@StateObject` (line 34, 57-63) | U.5 |
| `sourceName`, `trackCount`, `estimatedDuration`, `hasDetectedAudio`, `isTimedOut`, `planPreviewEnabled`, `reduceMotion` @Published | `production-active` | `ReadyView` | — |
| `shouldAdvanceToPlaying: PassthroughSubject<Void, Never>` | `production-active` | `ReadyView.onReceive` (line 92-94) → `onBeginPlayback()` | UX_SPEC §6.3 |
| `init(sessionSource:sessionManager:audioSignalStatePublisher:planPublisher:reduceMotion:delayProvider:)` | `production-active` | `ContentView → ReadyView` | — |
| `retry()`, `endSession()` | `production-active` | `ReadyView` timeout overlay | — |
| `subscribeToPlan()` / `subscribeToAudioDetector()` / `scheduleTimeout()` | `production-active` | Internal | — |
| `formattedDuration` extension | `production-active` | `ReadyView` | U.5 — formatter |
| `FirstAudioDetector` (owned) | `production-active` | Internal | UX_SPEC §6.3 (per CA.5) |
| 90 s `Task.sleep(for: .seconds(90))` timeout | `production-active` | `scheduleTimeout` | UX_SPEC §6.4 |

#### PreparationProgressViewModel.swift (205 lines) — `production-active`

`@MainActor final class PreparationProgressViewModel: ObservableObject`. Maintains ordered `[RowData]`, derives counts + aggregate progress, estimates ETAs via `PreparationETAEstimator`, subscribes to progressive-readiness publisher for `canStartNow`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PreparationCounts` (ready/partial/failed/total) | `production-active` | PreparationProgressView | U.4 |
| `RowData: Identifiable` | `production-active` | TrackPreparationRow | — |
| `PreparationProgressViewModel` class | `production-active` | `PreparationProgressView.@StateObject` | U.4 |
| `@Published rows`, `aggregateProgress`, `counts`, `canStartNow`, `readyTrackCount`, `showCancelConfirmation` | `production-active` | PreparationProgressView | — |
| `init(publisher:trackList:progressiveReadinessPublisher:onStartNow:)` | `production-active` | PreparationProgressView | 6.1 |
| `startNow()`, `requestCancel()`, `cancel()` | `production-active` | PreparationProgressView | — |
| `handleStatusUpdate(_:)` + `updateTiming(track:status:now:)` + `preparationStage(for:)` | `production-active` | Internal | — |
| `PreparationETAEstimator` (owned, value type from `Services/`) | `production-active` | Internal | — |

#### PreparationErrorViewModel.swift (173 lines) — `production-active`

`@MainActor final class`. State machine over `PreparationPresentationState` (`.normal / .banner(UserFacingError) / .fullScreen(UserFacingError)`). 5-rule recompute() with priority ordering.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PreparationPresentationState` enum (3 cases) | `production-active` | PreparationProgressView body switch | U.4 |
| `PreparationErrorViewModel` class | `production-active` | `PreparationProgressView.@StateObject` | U.4 |
| `@Published presentationState` | `production-active` | `PreparationProgressView` rendering branch | — |
| `init(statusPublisher:reachability:totalTrackCount:)` | `production-active` | PreparationProgressView | — |
| `handle(statuses:)` / `handleReachability(isOnline:)` / `recompute()` / `startTimer()` | `production-active` | Internal | — |
| Constants: 90 s first-track threshold; 120 s total threshold | `production-active` | `recompute()` | UX_SPEC §5.6 |

#### PlanPreviewViewModel.swift (197 lines) — `production-active`

`@MainActor final class PlanPreviewViewModel: ObservableObject`. Builds `[PlanPreviewRow]` from `PlannedSession` + plan publisher subscription. Manages `manuallyLockedTracks` for D-058 / U.5 Part D regeneration.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `PlanPreviewRow: Identifiable` | `production-active` | `PlanPreviewRowView` | U.5 |
| `TransitionSummary: Equatable` | `production-active` | `PlanPreviewTransitionView` | — |
| `PlanPreviewViewModel` class | `production-active` | `PlanPreviewView.@StateObject` | U.5 |
| `@Published rows`, `manuallyLockedTracks`, `isRegenerating`; `private(set) lockedPresets` | `production-active` | `PlanPreviewView` | — |
| `init(initialPlan:planPublisher:onRegenerate:)` | `production-active` | `PlaybackView.sheet(showPlanPreview:)` + `ReadyView` plan-preview sheet | — |
| `swapPreset(for:to:)`, `resetLock(for:)` | `production-active` | `PlanPreviewRowView` | — |
| `regeneratePlan()` | `production-active` | `PlanPreviewView` Regenerate button (line 115-129) | D-047 / D-058 |
| `previewRow(_:)` | **TODO stub** | `PlanPreviewView` (deferred to U.5b per line 166-167) | Documented as deferred, not orphan |
| `buildRows(from:locked:)` (private) | `production-active` | Internal | — |

#### EndSessionConfirmViewModel.swift (47 lines) — `production-active`

`@MainActor final class`. Esc-triggered confirmation dialog state.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `EndSessionConfirmViewModel` class | `production-active` | `PlaybackView.@StateObject` (line 42, 96-98) | — |
| `@Published isPresented`, `requestEnd()`, `confirm()`, `cancel()` | `production-active` | PlaybackView confirmationDialog (line 155-168) | — |

#### SettingsViewModel.swift (171 lines + `import Metal` at line 172) — `production-active`

`@MainActor final class SettingsViewModel: ObservableObject`. Observable facade over `SettingsStore` — does NOT itself own SettingsStore as `@StateObject`; the `store` is injected via init. About-section system info read via `AboutSectionData.current()` (calls `MTLCreateSystemDefaultDevice().name` for GPU family).

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `AboutSectionData: Sendable` value type | `production-active` | `AboutSettingsSection` | U.8 |
| `SettingsViewModel` class | `production-active` | `SettingsView.@StateObject(wrappedValue: SettingsViewModel(store:))` | U.8 — D-091 compliant (no @StateObject SettingsStore inside) |
| `let store: SettingsStore` (reference, not @StateObject) | `production-active` | Forwarded bindings | D-091 |
| `let about: AboutSectionData` | `production-active` | `AboutSettingsSection` | — |
| `includeMilkdropPresetsDisabled = true` | `production-active` | `VisualsSettingsSection` (DEBUG-gated) | — |
| 10 binding properties (captureMode, sourceAppOverride, deviceTierOverride, qualityCeiling, includeMilkdropPresets, reducedMotion, excludedPresetCategories, showLiveAdaptationToasts, showUncertifiedPresets, sessionRecorderEnabled, sessionRetention) | `production-active` | Audio/Visuals/Diagnostics sub-sections | — |
| `openSessionsFolder()`, `resetOnboarding()`, `copyDebugInfo()` | `production-active` | DiagnosticsSettingsSection, AboutSettingsSection | — |
| `private var sessionsDirectoryURL: URL` | `production-active` | `openSessionsFolder` | — |

#### ToastManager.swift (100 lines) — `production-active`

`@MainActor final class ToastManager: ObservableObject`. FIFO queue, max 3 visible. Per-toast `dismissTasks: [UUID: Task<Void, Never>]` for auto-dismiss. Condition-ID dismissal for `PlaybackErrorBridge`. `dropOldest()` favours non-degradation eviction.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `ToastManager` class | `production-active` | `PlaybackView.@StateObject` (line 41) | U.7 |
| `@Published visibleToasts: [PhospheneToast]` | `production-active` | `ToastContainerView.@ObservedObject` | — |
| `static maxVisible: 3` | `production-active` | Internal queue cap | — |
| `enqueue(_:)`, `dismiss(id:)`, `dismissByCondition(_:)`, `isConditionAsserted(_:)` | `production-active` | `PlaybackErrorBridge` + `MultiDisplayToastBridge` + `LiveAdaptationToastBridge` + `DefaultPlaybackActionRouter.toastBridge?.emitAck` chain (CA.5-scope) | UX_SPEC §9.4 |
| `dropOldest()` (private) | `production-active` | Internal overflow handler | — |

### Views/ (47 files, ~6,270 LoC)

#### Top-level Views (12 files)

##### MetalView.swift (50 lines) — `production-active`

`struct MetalView: NSViewRepresentable`. Wraps `MTKView` with `RenderPipeline` as delegate. Takes `context: MetalContext` + `pipeline: RenderPipeline` from PlaybackView. No re-allocation in `updateNSView`.

##### DebugOverlayView.swift (199 lines) — `production-active`

`struct DebugOverlayView: View`. `@ObservedObject var engine: VisualizerEngine`. Bottom-leading SwiftUI debug overlay surface. Toggle via D key. Per CLAUDE.md / ARCHITECTURE.md, complementary to the top-trailing DashboardOverlayView — both gated on the same `showDebug` @State in PlaybackView (line 47, 145).

##### FullScreenErrorView.swift (129 lines) — `production-active`

`struct FullScreenErrorView: View`. Reusable full-screen error layout per UX_SPEC §9.1 / §9.2. Takes `error: UserFacingError` + primary/secondary actions. Spacing 28; max-width 520.

##### ConnectorPickerView.swift (193 lines) — `production-active` + co-located `unverified-claim` #3

`struct ConnectorPickerView: View`. NavigationStack sheet with three tiles. **Apple Music destination creates VM inline** at line 111-115; Spotify destination uses `private struct OAuthSpotifyConnectionWrapper` with `@StateObject` for VM survival across body re-evals. The architectural asymmetry is the `unverified-claim` finding above. Accessibility IDs: `phosphene.view.connectorPicker`, plus per-tile IDs.

##### ConnectorTileView.swift (72 lines) — `production-active`

`struct ConnectorTileView: View`. Reusable tile: icon + title + subtitle; disabled state with alt caption + optional secondary action. Accessibility ID pattern `phosphene.connector.tile.<type.rawValue>`.

##### ConnectorType.swift (35 lines) — `production-active`

`enum ConnectorType: String, CaseIterable, Codable, Hashable`. 3 cases: `.appleMusic / .spotify / .localFolder`. title/subtitle/systemImage computed properties.

##### AppleMusicConnectionView.swift (174 lines) — `production-active`

`struct AppleMusicConnectionView: View`. `@ObservedObject var viewModel: AppleMusicConnectionViewModel`. Five-state connection view (`.connecting / .noCurrentPlaylist / .notRunning / .permissionDenied / .error`). `.onConnect` fires on `.connected`. `.onDisappear { viewModel.cancelRetry() }` (line 33).

##### SpotifyConnectionView.swift (250 lines) — `production-active`

`struct SpotifyConnectionView: View`. URL paste field + preview card + rejectedKind copy + rate-limit retry indicator + login button. **Exhaustive switch over all 12 `SpotifyConnectionState` cases** at lines 70-100, including U.11's three additions (`.requiresLogin`, `.waitingForCallback`, `.authFailure`). Multiple accessibility IDs.

##### SettingsView.swift (75 lines) — `production-active`

`struct SettingsView: View`. Settings sheet with four sections: Audio / Visuals / Diagnostics / About. `@StateObject private var viewModel: SettingsViewModel` via custom init `init(store: SettingsStore)` (D-091 compliant — store flows through init, not `@StateObject SettingsStore()` inside the View). NavigationSplitView pattern. Width 720 × Height 520.

##### TrackPreparationRow.swift (116 lines) — `production-active`

`struct TrackPreparationRow: View`. Single row in the preparation progress list. Custom accessibility label aggregating title + artist + status + ETA.

##### TrackPreparationStatusIcon.swift (54 lines) — `production-active`

`struct TrackPreparationStatusIcon: View`. Small icon component for `TrackPreparationRow`. `static let size: CGFloat = 28`.

##### QualityGradeIndicator.swift (61 lines) — `production-active`

`struct QualityGradeIndicator: View`. Colored dot + letter code for signal quality. U.9 Part C. Takes `quality: SignalQuality`.

#### Connecting/ (1 file)

##### ConnectingView.swift (90 lines) — `production-active`

`@MainActor struct ConnectingView: View`. `.connecting` state per UX_SPEC §3. Spinner + localized headline + cancel CTA. Accessibility IDs `phosphene.view.connecting` + `phosphene.connecting.cancel`.

#### Dashboard/ (5 files) — DASH.7 + DASH.7.1 + DASH.7.2 surface

##### DashboardOverlayView.swift (73 lines) — `production-active` (file-header docstring drift flagged as `unverified-claim` #1)

`struct DashboardOverlayView: View`. Top-trailing dashboard panel. **DASH.7.2 / D-089 compliance verified line-by-line in §Verification-of-DASH.7-dashboard-surface below.** `.allowsHitTesting(false)` (pure visual overlay).

##### DashboardCardView.swift (47 lines) — `production-active` (file-header docstring drift flagged as `unverified-claim` #2)

`struct DashboardCardView: View`. Per-card typographic section. Resolves fonts once per render via `DashboardFontLoader.resolveFonts(in:)`. Title via `displayFontName` + `TypeScale.bodyLarge` (15). Rows stack with `layout.rowSpacing`.

##### DashboardRowView.swift (293 lines) — `production-active`

`struct DashboardRowView: View`. Switches over the 4 row variants (`.singleValue / .bar / .progressBar / .timeseries`). **DASH.7.2 D-089 inlined `.singleValue`** (label-LEFT, value-RIGHT at 13pt mono, frame height 17) per the spec. `.progressBar` value column width = 110pt with `.fixedSize(horizontal: true)`. No SF Symbols. Sparkline via SwiftUI `Canvas` (filled area + stroked line + centre baseline). `rowLabel(_:)` uses `proseMediumFontName` + `TypeScale.label` + `labelTracking` (1.5). Plus three private struct helpers: `SignedBarView`, `ProgressBarView`, `SparklineView`.

##### DarkVibrancyView.swift (47 lines) — `production-active`

`struct DarkVibrancyView: NSViewRepresentable`. Wraps `NSVisualEffectView` with `.appearance = NSAppearance(named: .vibrantDark)`, `.material = .hudWindow` (overridable; default `.hudWindow`), `.blendingMode = .withinWindow` (overridable; default `.withinWindow`). DASH.7.2 / D-089.

##### DashboardOverlayViewModel.swift (108 lines) — see §ViewModels/ above

(Lives in `Views/Dashboard/` per the architectural decision to keep dashboard-internal state with the View family. Audited under `ViewModels/` section above.)

#### Ended/ (1 file)

##### EndedView.swift (119 lines) — `production-active`

`@MainActor struct EndedView: View`. `.ended` state per UX_SPEC §3. Session-summary card with trackCount + sessionDuration + "New Session" + "Open Sessions Folder" CTAs. Accessibility IDs. `sessionDuration: TimeInterval?` (nil → em-dash placeholder per QR.4). Includes static helper `openSessionsFolder()` with FileManager / NSWorkspace plumbing.

#### Idle/ (1 file)

##### IdleView.swift (85 lines) — `production-active`

`@MainActor struct IdleView: View`. `.idle` state per UX_SPEC §3. Two CTAs: "Connect a playlist" (sheet) + "Start listening now" (ad-hoc). `@EnvironmentObject engine: VisualizerEngine` (D-091 ✓). Photosensitivity notice sheet on first appearance (gated on `PhotosensitivityAcknowledgementStore.isAcknowledged`).

#### Onboarding/ (2 files)

##### PermissionOnboardingView.swift (72 lines) — `production-active`

`struct PermissionOnboardingView: View`. Screen-capture permission explainer + "Open System Settings" CTA. U.2.

##### PhotosensitivityNoticeView.swift (63 lines) — `production-active`

`struct PhotosensitivityNoticeView: View`. One-time photosensitivity sheet. Takes `onAcknowledge: () -> Void`. U.2.

#### Playback/ (11 files)

##### PlaybackView.swift (355 lines) — `production-active`

`@MainActor struct PlaybackView: View`. Six-layer ZStack composition (MetalView / TrackChangeAnimation / PlaybackChromeView / ShortcutHelpOverlay / DebugOverlay / DashboardOverlay). Owns 4 `@StateObject` view models + 8 `@State` services + `@EnvironmentObject` engine + `@EnvironmentObject SettingsStore` (D-091 ✓ — comment block at lines 51-55 enforces). The load-bearing center. Setup wires `LiveAdaptationToastBridge → DefaultPlaybackActionRouter.live(engine:toastBridge:onShowPlanPreview:)`; teardown un-installs the key monitor + detaches fullscreen observer. `buildRegistry(router:)` factory wires all keyboard shortcuts including debug + diagnostic-hold + spider-force toggle (DEBUG only). Sheet presentations for PlanPreviewView + SettingsView.

##### PlaybackChromeView.swift (100 lines) — `production-active`

`struct PlaybackChromeView: View`. Overlay chrome composition. `@ObservedObject var viewModel: PlaybackChromeViewModel`. Composes 5 subviews (TrackInfoCardView, PlaybackControlsCluster, ListeningBadgeView, ToastContainerView, PreparationBackgroundIndicator). Accessibility ID `phosphene.playback.chrome`. Plus private `PreparationBackgroundIndicator` subview (subtle teal dot for 6.1 progressive readiness).

##### ListeningBadgeView.swift (54 lines) — `production-active`

`struct ListeningBadgeView: View`. Top-center badge for sustained silence (≥ 3 s). **Replaces the legacy `NoAudioSignalBadge` per U.6** (file-header line 3 confirms). Respects `reduceMotion` (spinner skipped). Accessibility ID `phosphene.playback.listeningBadge`.

##### OverlayBackdropStyle.swift (39 lines) — `production-active`

`struct OverlayBackdropStyle: ViewModifier`. Shared ≥ 4.5:1 contrast backdrop for overlay text (UX_SPEC §7.2). 10 pt corner radius, 0.45 opacity black tint over `.ultraThinMaterial`. Exposed as `.overlayBackdrop()` View extension.

##### PlaybackControlsCluster.swift (55 lines) — `production-active`

`struct PlaybackControlsCluster: View`. Top-right cluster: SessionProgressDotsView + settings gear + close button. Accessibility ID `phosphene.playback.controlsCluster`.

##### SessionProgressDotsView.swift (101 lines) — `production-active`

`struct SessionProgressDotsView: View`. Track-list progress dots. Three rendering branches: reactive mode (pulsing circle); > 30 tracks (text); else dots grid. Respects `reduceMotion`. Accessibility ID `phosphene.playback.progressDots`.

##### ShortcutHelpOverlayView.swift (123 lines) — `production-active`

`struct ShortcutHelpOverlayView: View`. Full keyboard shortcut reference shown on Shift+?. Categorizes via `ShortcutCategory.allCases`. Accessibility ID `phosphene.playback.shortcutHelp`.

##### ToastContainerView.swift (36 lines) — `production-active`

`struct ToastContainerView: View`. Bottom-trailing stack of up to 3 visible toasts. `@ObservedObject var toastManager: ToastManager`. Posts accessibility announcements for new toasts.

##### ToastView.swift (75 lines) — `production-active`

`struct ToastView: View`. Per-toast cell. Severity accent bar (gray/orange/red). 320 pt max width. UX_SPEC §9.4 surface.

##### TrackChangeAnimationView.swift (95 lines) — `production-active`

`struct TrackChangeAnimationView: View`. Animated center-to-top-left track announcement on boundary. 1.8 s total animation (0.3 s easing + 1.0 s hold + 0.5 s spring). Respects `reduceMotion` (animation collapsed to fade only).

##### TrackInfoCardView.swift (79 lines) — `production-active`

`struct TrackInfoCardView: View`. Top-left card: title + artist + preset name + orchestrator state pill. Pill green (planned) / orange (reactive). Accessibility ID `phosphene.playback.trackInfoCard`.

#### Preparation/ (3 files)

##### PreparationProgressView.swift (263 lines) — `production-active`

`@MainActor struct PreparationProgressView: View`. `.preparing` state per UX_SPEC §3. Three presentation modes (`.normal` / `.banner(error)` / `.fullScreen(error)`) driven by `PreparationErrorViewModel.presentationState`. Owns `@StateObject viewModel: PreparationProgressViewModel`, `@StateObject errorViewModel: PreparationErrorViewModel`, `@State networkRecoveryCoordinator: NetworkRecoveryCoordinator?` (D-061(d,e) — initialized in `.onAppear`). Cancel confirmation dialog when ≥ 1 track is `.ready`.

##### PreparationFailureView.swift (133 lines) — `production-active`

`struct PreparationFailureView: View`. Full-screen replacement when all tracks failed or network offline. Two recovery CTAs: pick playlist (primary) + start reactive (secondary, optional).

##### TopBannerView.swift (67 lines) — `production-active`

`struct TopBannerView: View`. Amber warning strip above the track list for non-blocking preparation errors. UX_SPEC §5.6 / §9.3.

#### Ready/ (5 files)

##### ReadyView.swift (217 lines) — `production-active`

`@MainActor struct ReadyView: View`. `.ready` state per UX_SPEC §3 + §6. `@StateObject viewModel: ReadyViewModel`. Timeout overlay when `viewModel.isTimedOut`. First-audio confirmation via `.onReceive(viewModel.shouldAdvanceToPlaying)` → `onBeginPlayback()`. Background `ReadyBackgroundPresetView` (currently a gradient placeholder; U.5b deferred).

##### PlanPreviewView.swift (145 lines) — `production-active`

`@MainActor struct PlanPreviewView: View`. Sheet from PlaybackView (`?` shortcut) + ReadyView. `@StateObject viewModel: PlanPreviewViewModel`. Regenerate button wired to `viewModel.regeneratePlan()` (line 116). Modify button gated behind `#if ENABLE_PLAN_MODIFICATION` flag.

##### PlanPreviewRowView.swift (111 lines) — `production-active`

`struct PlanPreviewRowView: View`. One track row: number + title + artist + preset + family pill + duration. Preset swap menu (TODO: U.5.C row-tap preview).

##### PlanPreviewTransitionView.swift (48 lines) — `production-active`

`struct PlanPreviewTransitionView: View`. Small connector between two rows showing the transition style.

##### ReadyPulsingBorder.swift (55 lines) — `production-active`

`struct ReadyPulsingBorder: View`. Ambient pulsing border overlay. 2.5 s animation; respects `reduceMotion`.

#### Settings/ (6 files)

##### AboutSettingsSection.swift (47 lines) — `production-active`

`struct AboutSettingsSection: View`. `@ObservedObject var viewModel: SettingsViewModel`. App version / build / macOS / GPU + debug-info copy CTA. Read-only (no SettingsStore mutations).

##### AudioSettingsSection.swift (58 lines) — `production-active`

`struct AudioSettingsSection: View`. Bindings to `viewModel.captureMode`, `viewModel.sourceAppOverride` (conditional). Embeds `SourceAppPicker` when `.specificApp`.

##### DiagnosticsSettingsSection.swift (66 lines) — `production-active`

`struct DiagnosticsSettingsSection: View`. Bindings to `viewModel.sessionRecorderEnabled`, `viewModel.sessionRetention`. Action calls `openSessionsFolder()` + `resetOnboarding()`. Comment at lines 45-47 documents `showPerformanceWarnings` removal in QR.4 / D-091 (the field was never wired to a consumer).

##### VisualsSettingsSection.swift (127 lines) — `production-active`

`struct VisualsSettingsSection: View`. Bindings to `deviceTierOverride`, `qualityCeiling`, `includeMilkdropPresets` (DEBUG-gated), `reducedMotion`, `excludedPresetCategories` (via PresetCategoryBlocklistPicker), `showLiveAdaptationToasts`, `showUncertifiedPresets`.

##### PresetCategoryBlocklistPicker.swift (40 lines) — `production-active`

`struct PresetCategoryBlocklistPicker: View`. `@Binding selection: Set<PresetCategory>`. Reusable picker component; takes binding from VisualsSettingsSection.

##### SourceAppPicker.swift (93 lines) — `production-active`

`struct SourceAppPicker: View`. `@Binding selection: SourceAppOverride?`. Multi-row picker over running apps (`NSRunningApplication.runningApplications()` filtered by `activationPolicy == .regular`). Includes private `RunningAppEntry` Identifiable struct.

---

## Verification of PlaybackChromeViewModel BUG-015 / D-091 consumer chain

The kickoff requires this section. CA.5 verified the engine-side wire + the `@Published currentTrackIndex` publisher. CA.6 verifies the consumer chain end-to-end.

**The full chain matches the BUG-015 Resolved-field design + D-091 / QR.4 plan-index propagation byte-for-byte.** Verified:

1. **Producer:** `VisualizerEngine.swift:77` — `@Published var currentTrackIndex: Int?` declared. Comment at lines 74-76 says: *"QR.4 / D-091 — replaces the lowercased title+artist string match. Bind directly to this publisher."*

2. **Producer-side resolution:** `VisualizerEngine+Capture.swift:152` — `self.currentTrackIndex = resolvedPlanIndex` is set on track change, after `indexInLivePlan(matching:)` resolves the canonical plan index. The MainActor write happens inside the Task that follows the audio-thread resolution per CA.5's reading. The `liveTrackPlanIndex` lock-guarded sibling field (BUG-015) shares the same resolution at line 131 (CA.5 verified).

3. **Publisher binding:** `ContentView.swift:85` — `currentTrackIndexPublisher: engine.$currentTrackIndex.eraseToAnyPublisher()`. Passes the publisher into `PlaybackView.init`.

4. **PlaybackView relay:** `PlaybackView.swift:74` (`currentTrackIndexPublisher: AnyPublisher<Int?, Never> = Just(nil).eraseToAnyPublisher()` parameter with sensible default for unit tests); `:90` (`currentTrackIndexPublisher: currentTrackIndexPublisher` passes through to `PlaybackChromeViewModel.init`).

5. **PlaybackChromeViewModel subscription:** `PlaybackChromeViewModel.swift:121` — `currentTrackIndexPublisher: AnyPublisher<Int?, Never> = Just(nil).eraseToAnyPublisher()` init parameter. `:169-176`:
   ```swift
   currentTrackIndexPublisher
       .receive(on: DispatchQueue.main)
       .sink { [weak self] idx in
           guard let self else { return }
           self.currentTrackIndex = idx
           self.refreshProgress()
       }
       .store(in: &cancellables)
   ```
   The bound value is stored in `private var currentTrackIndex: Int?` (declared line 100) and triggers `refreshProgress()`.

6. **Consumer use:** `PlaybackChromeViewModel.swift:242-254`:
   ```swift
   private func refreshProgress() {
       guard let plan = livePlan, !plan.tracks.isEmpty else {
           sessionProgress = SessionProgressData(
               totalTracks: 0, currentIndex: -1, isReactiveMode: true
           )
           return
       }
       sessionProgress = SessionProgressData(
           totalTracks: plan.tracks.count,
           currentIndex: currentTrackIndex ?? -1,
           isReactiveMode: false
       )
   }
   ```
   The `currentIndex` is read **directly** from `currentTrackIndex` (the publisher-bound value). **No lowercased title+artist string matching anywhere.**

7. **Failed Approach #56 regression check:**
   ```
   $ grep -rnE "lowercased\(\).*title|lowercased\(\).*artist" PhospheneApp/ViewModels PhospheneApp/Views
   (no matches)
   ```
   Zero occurrences. The pre-QR.4 anti-pattern is fully eliminated.

8. **Regression-gate test:** `PhospheneAppTests/PlaybackChromeIndexBindingTests.swift` carries the `test_titleCaseMismatch_doesNotChangeIndex` assertion (per CA.5's reading of the App-test inventory). The gate fires if anyone re-introduces a string-match path that's case-sensitive on title or artist.

9. **Off-plan-track handling:** when `currentTrackIndex == nil` (cover, remaster, encoding-different variant — the canonical-identity resolver returned `nil`), the publisher binds `nil` → `refreshProgress` writes `currentIndex: -1`. The `SessionProgressDotsView` reads `progress.currentIndex` and treats `-1` as "unknown" — no highlighted dot. **The View-tree response to the off-plan path is graceful.**

10. **The kickoff's specific concern** ("`PlaybackChromeViewModel` consumes the BUG-015 `currentTrackIndex` publisher and the `livePlannedSession` publisher — verify the subscription chains are race-free") — verified. Both subscriptions land on `DispatchQueue.main` via `.receive(on:)`. Both write into `@MainActor` properties under SwiftUI's main-actor isolation (the `PlaybackChromeViewModel` class is `@MainActor`). Both trigger `refreshProgress()` synchronously on the main actor. No race surfaces.

**Verdict: PlaybackChromeViewModel BUG-015 / D-091 consumer chain is structurally clean. No App-View-layer regression risk identified.**

---

## Verification of D-091 single-SettingsStore enforcement in View tree

The kickoff requires this section. CA.5 verified the engine-adapter side; CA.6 verifies every View consumes `SettingsStore` correctly.

**Single legitimate construction site:**
```
$ grep -rnE "@StateObject.*SettingsStore" PhospheneApp PhospheneAppTests
PhospheneApp/PhospheneApp.swift:25:    @StateObject private var settingsStore = SettingsStore()
PhospheneApp/Views/Playback/PlaybackView.swift:52:    /// `@StateObject SettingsStore()` here creates a parallel state world —
PhospheneAppTests/SettingsStoreEnvironmentRegressionTests.swift:42:        @StateObject var shadowStore = SettingsStore(...)
PhospheneAppTests/SettingsStoreEnvironmentRegressionTests.swift:148: #expect(!src.contains("@StateObject private var settingsStore = SettingsStore()"), ...
```

- `PhospheneApp.swift:25` — the legitimate single-instance owner.
- `PlaybackView.swift:52` — a comment block WARNING against the bad pattern (not actual usage).
- The two `SettingsStoreEnvironmentRegressionTests.swift` hits are the regression-test shadow probe + the source-presence assertion.

**Production consumers (`@EnvironmentObject SettingsStore`):**
```
$ grep -rnE "@EnvironmentObject.*SettingsStore" PhospheneApp
PhospheneApp/Views/Playback/PlaybackView.swift:55:    @EnvironmentObject private var settingsStore: SettingsStore
```

Only one — `PlaybackView`. That's by design: the rest of the View tree consumes `SettingsStore` indirectly via `SettingsViewModel`. PlaybackView's role is to pass the store to `SettingsView(store: settingsStore)` on the sheet presentation (line 184), and to consume the store directly for the capture-mode-switch coordinator setup (`captureModeSwitchCoordinator: CaptureModeSwitchCoordinator(... settingsStore: settingsStore)` at lines 226-230, which subscribes to `SettingsStore.captureModeChanged` per D-061(b)).

**Indirect consumers via SettingsViewModel:**
```
$ grep -rnE "viewModel: SettingsViewModel|@ObservedObject.*SettingsViewModel" PhospheneApp/Views/Settings PhospheneApp/Views/SettingsView.swift
PhospheneApp/Views/Settings/AboutSettingsSection.swift:9:    @ObservedObject var viewModel: SettingsViewModel
PhospheneApp/Views/Settings/AudioSettingsSection.swift:9:    @ObservedObject var viewModel: SettingsViewModel
PhospheneApp/Views/Settings/DiagnosticsSettingsSection.swift:9:    @ObservedObject var viewModel: SettingsViewModel
PhospheneApp/Views/Settings/VisualsSettingsSection.swift:12:    @ObservedObject var viewModel: SettingsViewModel
PhospheneApp/Views/SettingsView.swift:11:    @StateObject private var viewModel: SettingsViewModel
```

All 4 Settings sub-sections take `SettingsViewModel` as `@ObservedObject` (not owners). `SettingsView` owns the VM via `@StateObject` with a custom init that takes `SettingsStore` and builds the VM:

```swift
// SettingsView.swift:14-19 (paraphrased from Explore agent's reading):
init(store: SettingsStore) {
    _viewModel = StateObject(wrappedValue: SettingsViewModel(store: store))
}
```

The store flows in as init arg (passed from `PlaybackView.sheet { SettingsView(store: settingsStore) }`); never re-instantiated. **D-091 compliant.**

**`SettingsStoreEnvironmentRegressionTests` gate verified intact** — the source-presence assertion at line 148 still reads `PlaybackView.swift` source and asserts the absence of `@StateObject private var settingsStore = SettingsStore()` substring. Anyone who flips PlaybackView back will trip the assertion.

**Verdict: D-091 single-SettingsStore enforcement clean across the entire View tree. No regression. The single-instance + EnvironmentObject + ViewModel-facade topology is the canonical D-091 shape.**

---

## Verification of DASH.7 dashboard surface

The kickoff requires this section. Verified line-by-line against D-088 (DASH.7.1 brand-alignment) + D-089 (DASH.7.2 dark-surface legibility) + ARCHITECTURE.md `§Module Map Views/Dashboard/`:

| D-088 / D-089 claim | File:line | Code | Verdict |
|---|---|---|---|
| Panel uses `DarkVibrancyView` (NSVisualEffectView pinned `.vibrantDark` + `.hudWindow`) as backdrop | `DarkVibrancyView.swift:14-15` | `view.appearance = NSAppearance(named: .vibrantDark)` + `view.material = .hudWindow` (default; overridable) + `view.blendingMode = .withinWindow` (default; overridable) | ✓ |
| Panel has `Color.surface` tint at 0.96α | `DashboardOverlayView.swift:57` | `Color(nsColor: DashboardTokens.Color.surface).opacity(0.96)` | ✓ (the file-header comment at line 10 claims "0.55α" — see `unverified-claim` #1 above; the ARCHITECTURE.md / CLAUDE.md / D-089 claim "0.96α" matches the actual code) |
| Panel has 1 px border stroke (rounded rectangle, cornerRadius 6) | `DashboardOverlayView.swift:61-64` | `RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: DashboardTokens.Color.border).opacity(0.6), lineWidth: 1)` | ✓ |
| Panel locks color scheme to dark | `DashboardOverlayView.swift:65` | `.environment(\.colorScheme, .dark)` | ✓ |
| Panel width 320 pt | `DashboardOverlayView.swift:44` | `.frame(width: 320, alignment: .leading)` | ✓ |
| Panel sits top-trailing | `DashboardOverlayView.swift:67-68` | `.padding(.top, DashboardTokens.Spacing.lg)` + `.padding(.trailing, DashboardTokens.Spacing.lg)` + `.frame(..., alignment: .topTrailing)` | ✓ |
| Panel does not catch hits / not announced to VO | `DashboardOverlayView.swift:69-70` | `.allowsHitTesting(false)` + `.accessibilityHidden(true)` | ✓ |
| Title typography: Clash Display Medium @ 15 pt | `DashboardCardView.swift:30-34` + `DashboardTokens.swift:36` | `.font(.custom(fontResolution.displayFontName, size: TypeScale.bodyLarge, relativeTo: .title3))` with `TypeScale.bodyLarge = 15` | ✓ (the file-header comment at `DashboardCardView.swift:5` claims "18pt" — see `unverified-claim` #2 above) |
| Label typography: Epilogue Medium @ 11pt + 1.5 tracking | `DashboardRowView.swift:163-172` + `DashboardTokens.swift` | `.font(.custom(fontResolution.proseMediumFontName, size: TypeScale.label, relativeTo: .caption))` + `.tracking(DashboardTokens.TypeScale.labelTracking)` (1.5) | ✓ |
| `.singleValue` inlined (label-left, value-right, 13 pt mono, frame 17 pt) | `DashboardRowView.swift:66-76` | `HStack(spacing: 8) { rowLabel(label); Spacer(...); Text(value).font(.system(size: TypeScale.body, weight: .medium, design: .monospaced)) }.frame(height: 17)` | ✓ (D-089 spec) |
| `.progressBar` value column width 110 pt + .fixedSize | `DashboardRowView.swift:118-124` | `.frame(width: 110, alignment: .trailing).lineLimit(1).fixedSize(horizontal: true, vertical: false)` | ✓ (D-089 spec) |
| No SF Symbols — status reads via value text color | Throughout `DashboardRowView.swift` | No `Image(systemName:)` calls in the row variants; status communicated via `valueColor: NSColor` or `fillColor: NSColor` | ✓ (D-088 P1.4) |
| Throttle to ~30 Hz | `DashboardOverlayViewModel.swift:37, 45-49` | `static let throttleInterval = .milliseconds(33)`; `.throttle(for: Self.throttleInterval, scheduler: DispatchQueue.main, latest: true)` | ✓ |
| `ingestForTest(_:)` test seam bypasses throttle | `DashboardOverlayViewModel.swift:59-61` | `func ingestForTest(_ snapshot: DashboardSnapshot) { apply(snapshot) }` | ✓ |
| Stem-energy history ring of 240 samples per stem | `DashboardOverlayViewModel.swift:88, 90-95` | `private let capacity = StemEnergyHistory.capacity` + `Self.push(&drums, value: stems.drumsEnergyRel, capacity: capacity)` | ✓ |
| Transition into view: asymmetric (descend in, fade out) | `PlaybackView.swift:147-150` | `.transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -8)), removal: .opacity))` | ✓ (the parent attaches the transition per D-088 spec) |
| Spring-choreographed toggle | `PlaybackView.swift:321-323` | `withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showDebug.toggle() }` | ✓ |

**Verdict: DASH.7.2 dashboard surface is structurally correct. D-088 / D-089 contract honoured. Two file-header docstring drifts (the "0.55α" and "18pt" claims inside the file's own intro comments) are stale and registered as follow-ups; no code-level regression.**

---

## Verification of U.10 / U.11 timing-margin compliance

The kickoff requires this section. The `[dev-2026-05-21-c]` + `[dev-2026-05-21-d]` test-flake chip widened margins across 9 App-layer test files. CA.6 audits whether each margin matches U.11's documented baseline.

**Baselines (CLAUDE.md U.11):**
- 700 ms wait for 300 ms debounce (2.3× headroom)
- 250–400 ms wait for connect/login async actor-hop completions
- `@Suite(.serialized)` on URLProtocol-stub-using suites (U.10)

**Per-file audit:**

| File | Class | Site (sample) | Pre-chip | Post-chip | U.11 minimum | Verdict |
|---|---|---|---|---|---|---|
| `ToastManagerTests.swift` | toast auto-dismiss | line 36 (50 ms toast) | 400 | 1000 | ≥ 4× duration | ✓ `production-active` (20× the 50 ms duration) |
| `AppleMusicConnectionViewModelTests.swift` | 2 s auto-retry on noCurrentPlaylist | line 44 | 500 | 1500 | ≥ 700 ms | ✓ `production-active` |
| `AppleMusicConnectionViewModelTests.swift` | 4 sibling waits | lines 21, 63, 78, 94 | 50 | 300 | ≥ 250 ms (connect class) | ✓ `production-active` |
| `ReadyViewTimeoutIntegrationTests.swift` | 250 ms FirstAudioDetector timer | line 63 | 600 | 1500 | ≥ 4× timer | ✓ `production-active` (6× the timer) |
| `ReadyViewModelTests.swift` | 3 sibling 250 ms timer waits | lines 108, 116, 129 | 600 | 1500 | ≥ 4× timer | ✓ `production-active` (6× the timer) |
| `PlaybackChromeViewModelTests.swift` | overlayAutoHides 3 s timer (InstantDelay) | line 88 | 300 | 1000 | ≥ 700 ms | ✓ `production-active` |
| `SpotifyConnectionViewModelTests.swift` | 15 sites: 300 ms paste-debounce | line 22 et al. | 700 | 1500 | ≥ 700 ms | ✓ `production-active` (5× the debounce; chip went above the minimum for additional headroom) |
| `SpotifyConnectionViewModelTests.swift` | 5 sites: post-connect actor-hop | line 82 et al. | 250 | 700 | ≥ 250 ms | ✓ `production-active` (upper edge of the 250–400 ms baseline; safe) |
| `SpotifyConnectionViewModelTests.swift` | 4 sites: rate-limit retry | lines 181, 198, 214, 229 | 400 | 400 | ≥ 250 ms | ✓ `production-active` |
| `SpotifyConnectionViewModelTests.swift` | 1 site: 500 ms exhausted-retries wait | line 65 | n/a | 500 | n/a | ✓ `production-active` (waits past the 3 retry delays which sum to 22 s; 500 ms is for the post-error state propagation) |
| `NetworkRecoveryCoordinatorTests.swift` | 5 sites: 2 s debounce + headroom | lines 95, 114, 129, 145, 156, 174 | +0.1 | +1.0 | ≥ 0.5× debounce (50%) | ✓ `production-active` (50% headroom on a 2 s debounce — substantial; the U.11 baseline is for 300 ms debounce; this is a different scale, but the new headroom is proportionally larger than U.11's 2.3× rule of thumb would suggest) |
| `LiveAdaptationToastBridgeTests.swift` | 3 sites: 2 s coalescing window | lines 32, 47, 59 | 2600 | 4000 | ≥ 2× window | ✓ `production-active` (2× the 2 s window) |
| `SpotifyOAuthTokenProviderTests.swift` | not widened (separate test-env clientID injection per `[dev-2026-05-21-d]`) | — | — | — | — | ✓ `@Suite("SpotifyOAuthTokenProvider", .serialized)` at line 99 (U.10 compliant) |

**`@Suite(.serialized)` U.10 audit:**

```
$ grep -rnE "@Suite.*\.serialized|URLProtocol" PhospheneAppTests
PhospheneAppTests/SpotifyKeychainStoreTests.swift:9:@Suite("SpotifyKeychainStore", .serialized)
PhospheneAppTests/SpotifyOAuthTokenProviderTests.swift:18:private final class OAuthStubURLProtocol: URLProtocol {
PhospheneAppTests/SpotifyOAuthTokenProviderTests.swift:99:@Suite("SpotifyOAuthTokenProvider", .serialized)
```

Two suites use `.serialized`. The only `URLProtocol` subclass is `OAuthStubURLProtocol` inside `SpotifyOAuthTokenProviderTests.swift`, gated by the `.serialized` annotation at line 99 ✓. `SpotifyKeychainStoreTests` uses `.serialized` but doesn't have URLProtocol (the annotation is defensive — KeyChain ops via `SecItem*` APIs benefit from serialization too).

**No URLProtocol stub usage outside SpotifyOAuthTokenProviderTests.** No new URLProtocol patterns introduced post-U.11.

**Verdict: U.10 / U.11 timing-margin compliance verified clean. All 9 widened files match or exceed U.11 baselines. The chip's compliance claim holds. No `unverified-claim` margin findings.**

---

## Cross-references

### Updates needed in CLAUDE.md

**None applied in this increment.** The `What NOT To Do` rules + Failed Approaches CLAUDE.md cites that affect the View tree (D-091 Failed Approach #55, BUG-015, BUG-006.2 / Failed Approach #56, U.10 / U.11 timing rules, App-layer Logger pattern) were all verified clean against current code. No durable rule needs editing.

The four App-layer-specific rules from CLAUDE.md `## Code Style` (single SettingsStore, exhaustive switch on VM state, App-layer Logger, @Suite(.serialized) for URLProtocol-stub suites, debounce timing margins under parallel execution, new files in pbxproj across four sections) all hold per CA.6 verification.

### Updates needed in ARCHITECTURE.md

Applied in this increment as doc-only corrections:

1. **§UI Layer paragraph at lines 220-242** — three corrections:
   - `NoAudioSignalBadge` → `ListeningBadgeView` (file renamed in U.6).
   - Keyboard-shortcut list extended: add `Shift+→` / `Shift+←` (force-immediate nudge per UX_SPEC §7.4 / U.6b), `Z` (undo last adaptation), `M` (mood-lock), `Esc` (end session with confirm), `Shift+?` (shortcut help). The pre-CA.6 list (`→ / ← / Space / D / C / R / G`) was the U.6 baseline; QR.4 + U.6b layered the rest.
   - Add `DashboardOverlayView` as PlaybackView Layer 6 (DASH.7).

2. **§Module Map PhospheneApp/Views/ block** extended. The pre-CA.6 block listed ~20 of 47 views with sparse one-liners. The post-CA.6 block lists every view with a one-line behavioural description, mirroring the CA.5 fix for the engine-adapter Module Map block. Sub-blocks added: `Playback/` (11 entries including ListeningBadgeView + chrome subviews + ToastView family + TrackChangeAnimationView + TrackInfoCardView + ShortcutHelpOverlayView), `Preparation/` (3 entries adding `PreparationFailureView` + `TopBannerView`), `Ready/` (5 entries adding `PlanPreviewRowView` + `PlanPreviewTransitionView` + `PlanPreviewView` + `ReadyPulsingBorder`), `Settings/` (6 entries: per-section sub-views + pickers).

3. **§Module Map PhospheneApp/ViewModels/ block** extended. Pre-CA.6: 4 of 12. Post-CA.6: all 12 with one-liners. Added: `EndSessionConfirmViewModel`, `PlanPreviewViewModel`, `PlaybackChromeViewModel`, `PreparationErrorViewModel`, `PreparationProgressViewModel`, `ReadyViewModel`, `SettingsViewModel`, `ToastManager`. Note that `DashboardOverlayViewModel` continues to live under `Views/Dashboard/` per the filesystem layout.

### Updates needed in ENGINEERING_PLAN.md

Applied:

1. **Phase CA section:** register `CA.6 (App-layer, Views + ViewModels presentation slice)` as ✅ Landed under the existing Phase CA block. CA.7 added as Pending with options (CA-Renderer / CA-Audio / CA-Presets).

2. **Recently Completed:** add the CA.6 entry mirroring the CA.5 shape — file count, verdict counts, top findings, doc-drift corrections applied, plus the kickoff-required §Verification sections' verdicts (PlaybackChromeViewModel BUG-015 / D-091 consumer chain ✓ clean; D-091 single-SettingsStore enforcement across View tree ✓ clean; DASH.7 dashboard surface ✓ clean against D-088 / D-089 with two file-internal docstring drifts flagged; U.10 / U.11 timing-margin compliance ✓ clean across all 9 widened test files).

### Updates needed in DECISIONS.md

**No DECISIONS.md edits needed in this increment.** Every cited decision (D-049, D-050, D-052, D-054, D-058, D-061, D-069, D-088, D-089, D-091) was verified against current code with no contradictions. D-088 / D-089 require the file-header docstring corrections to the dashboard files (CA.6-FU-1 + CA.6-FU-2) — the decision content is correct; the Swift source comments are stale.

### Updates needed in source-file comments

Two candidate cleanup items registered as **CA.6-FU-1** and **CA.6-FU-2** (Dashboard file-header docstrings); neither is a behavioural change so each could fold into any future Dashboard-adjacent commit. The third item — **CA.6-FU-3** — is the Apple-Music inline-VM creation consistency question; it's a product call, not a doc edit.

### New BUG entries

**None filed in this increment.** BUG-015 (the only App-layer-class `broken-but-claimed` finding in scope) was filed by CA.4, Resolved 2026-05-21, and CA.5 + CA.6 both verified the wire shape clean.

### KNOWN_ISSUES.md sweep

No retroactive `Resolved` entries identified. No existing Open entries reproduced as no-longer-applicable. BUG-016 remains Open; the kickoff's request for a BUG-016 candidate failure mode at the View-layer level was investigated — see §BUG-016-adjacent-observations below; no new candidate root cause surfaced from the View-tree reading.

### BUG-016 — adjacent observations

The kickoff specifies: *"Any BUG-016-adjacent findings (Lumen Mosaic in the keyboard-cycling code path or the PlaybackView's preset-name observer chain)."*

CA.6 inspected the View-layer keyboard-cycling path:

- `PlaybackShortcutRegistry.swift` (CA.5 scope) wires `Shift+→` / `Shift+←` to `DefaultPlaybackActionRouter.presetNudge(direction:immediate: true)`. The router method (also CA.5 scope) ultimately calls into `VisualizerEngine.applyPresetByID(_:)` which calls `applyPreset(...)`.
- The View-tree's only feedback channel during a preset cycle is `engine.currentPresetName` (`@Published`) → `PlaybackView` → `PlaybackChromeViewModel.currentPresetNamePublisher` → `currentPreset: PresetDisplay?` → `TrackInfoCardView` shows the new preset name.
- DEBUG-only direct preset cycling (`Cmd+]` / `Cmd+[`) lives in `PlaybackView.buildRegistry(router:)` at lines 263-286, and emits a `Preset → <name>` toast on cycle. The toast fires regardless of whether the preset *renders* correctly — so a silent-render Lumen Mosaic regression would NOT be caught by the toast pathway.

**Observation (not a BUG-016 root cause):** there is no View-layer "preset rendered successfully" feedback signal. The toast `Preset → Lumen Mosaic` fires from the cycle action, not from any render success. If `LumenPatternEngine(device:)` returns `nil` (CA.5 surfaced this as a silent failure logged to `os.Logger` only), the user sees the toast saying "Preset → Lumen Mosaic" but the visualizer renders whatever the prior preset state was, or a blank screen.

**Candidate for the next BUG-016 reproduction:** add a `sessionRecorder?.log(...)` line to the `LumenPatternEngine` init-failure branch (recommended in CA.5 §BUG-016-App-layer-surface-inventory). The View tree itself has no instrumentation gap relevant to BUG-016; the diagnostic gap is in `VisualizerEngine+Presets.swift` (CA.5 scope, already inventoried).

CA.6 does not propose a fix. Cross-linked from BUG-016 §Fix scope as the View-layer landing reference.

### BUG-001 — adjacent observations

The kickoff specifies: *"Any BUG-001-adjacent findings (Money 7/4) that future diagnosis should weigh."*

CA.6's View-tree reading produced **no** BUG-001-adjacent findings. BUG-001 is a DSP-layer issue (SpectralCartograph mode label stays REACTIVE on live path for tracks where BeatGrid resolution fails). The View-tree's only consumer of beat-meter state is `DashboardOverlayViewModel.apply(_:)` ingesting `BeatCardLayout` (from the `DashboardSnapshot.beat: BeatSyncSnapshot` field) — purely display, not the diagnostic surface where BUG-001 lives.

---

## Follow-up Backlog

Findings surfaced by CA.6 that are *not* corrected in this audit increment. Each row is a candidate follow-up increment with enough scope to act on cold. Per the kickoff's audit-only discipline, fixes ship as separate increments scheduled whenever Matt prioritises them.

Items are greppable as `CA\.6-FU-\d+`. CA.7 (recommendation: CA-Renderer) is registered as the natural continuation.

| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA.6-FU-1** | Fix `DashboardOverlayView.swift:10` file-header docstring drift. The comment claims "explicit `surface` tint at 0.55α"; the code at line 57 uses `.opacity(0.96)`. ARCHITECTURE.md / CLAUDE.md / D-089 all correctly say "0.96α"; the in-file docstring is the stale one. 2-line edit: rewrite the intro paragraph to match the current 0.96α opacity. Bundle with any future Dashboard-adjacent commit. | File-header docstring matches code; engine + app builds clean; SwiftLint zero violations. | <1 | Ready now |
| **CA.6-FU-2** | Fix `DashboardCardView.swift:5` file-header docstring drift. The comment claims "Clash Display title at 18pt"; the code resolves `DashboardTokens.TypeScale.bodyLarge` which is 15. ARCHITECTURE.md correctly says "Clash Display Medium @ 15pt"; the in-file docstring is the stale one. 1-line edit: change "18pt" → "15pt" (or reference the token directly). Bundle with CA.6-FU-1 (same Dashboard family). | File-header docstring matches code; builds clean. | <1 | Ready now |
| **CA.6-FU-3** | Decide product intent for `ConnectorPickerView.destination(for: .appleMusic)` inline VM creation. Two options: (a) **apply the OAuthSpotifyConnectionWrapper pattern to Apple Music** — extract `private struct AppleMusicConnectionWrapper: View` with `@StateObject viewModel: AppleMusicConnectionViewModel` to preserve the VM across parent body re-evals (consistency with the Spotify side). The wrapper would not need an OAuth provider parameter; it's purely about VM lifetime. ~25 LoC + a test. OR (b) **leave the AppleMusic side as-is and document the reason** — if SwiftUI's NavigationStack does NOT call the destination closure on parent re-evals while a destination is pushed, the Spotify wrapper is defensive over-coding and the Apple Music side is correct. Document the conclusion in a comment block in ConnectorPickerView.swift, or via a regression test (e.g., a snapshot test that asserts AM connection state survives a parent re-eval). The right answer needs a small empirical test of NavigationStack behaviour. ~30 minutes of investigation + either option. | Either (a) the wrapper pattern lands for Apple Music with a regression test, OR (b) a regression test + comment block document that the Spotify wrapper is defensive but Apple Music does not need it. Engine + app builds clean. | <1 | Ready now |
| **CA.6-FU-4** | Update `docs/RUNBOOK.md` (or `docs/diagnostics/` as appropriate) to document the per-class U.11 timing-margin baselines used by the `[dev-2026-05-21-c]` chip. The chip's RELEASE_NOTES_DEV entry has the values (`700 ms wait for 300 ms debounce`, `1500 ms wait for 250 ms timer`, etc.), but they're buried in the release notes. Promoting to RUNBOOK gives future flake-cleanup increments a single-point reference. Captures the implicit "5× the debounce", "6× the timer", "20× the toast duration" patterns the chip applied. Optional but useful for the next time someone widens a timing margin. | RUNBOOK has a §Test Timing Margins section with the per-class baselines. Builds clean; docs SwiftLint clean. | <1 | Ready now (optional) |
| **CA.7** | Next audit pass: **CA-Renderer** (recommended). `PhospheneEngine/Sources/Renderer/` is the largest unaudited engine module (~50+ files, including FrameBudgetManager + RenderPipeline + MLDispatchScheduler + Dashboard renderer + per-pass pipelines). CA.5 boundary-noted it as the App ↔ Renderer surface — slot-6/7/8 buffer wiring, per-preset state class binding, RayMarchPipeline construction in applyPreset. Alternative: CA-Audio (smaller; closes AudioInputRouter + SilenceDetector + InputLevelMonitor + StreamingMetadata + MetadataPreFetcher per CA.3's boundary-noted item). Pick when convenient. | Audit document published under `docs/CAPABILITY_REGISTRY/RENDERER.md` (or `AUDIO.md`); same methodology as CA.1-CA.6; per-file verdicts; doc-drift corrections to ARCHITECTURE.md `§Module Map` blocks. | 1–2 | Pending Matt's scheduling |
| **CA.5-FU-2 status update (carried over from CA.5)** | The LiveAdaptationToastBridge engine-event docstring product call remains pending Matt's input. CA.6 did not re-investigate; the docstring still hedges with "currently wired only for…" and the BUG-015 wire's adaptation events still log to os.Logger / session.log without calling `emitAck()`. Carry forward to next App-adjacent increment. | Either docstring rewrite (option B) or `emitAck` wiring (option A) lands with appropriate test. | <1 | Pending Matt's product call |

**Bundling recommendation.** CA.6-FU-1 + CA.6-FU-2 are both 1-2 line edits in the same `Views/Dashboard/` family — bundle into a single trivial PR. CA.6-FU-3 is a product call (needs Matt's input) plus a small empirical test. CA.6-FU-4 is optional. CA.7 is the natural next audit pass.

**Priority order if Matt picks one this week:** **CA.7 (CA-Renderer)**. The engine-adapter slice is fully audited (CA.5) + matched presentation slice is fully audited (CA.6); the App layer is closed. CA-Renderer is the largest unaudited engine surface and the home of the frame-budget / dispatch-scheduling / per-pass pipeline machinery. CA-Audio is smaller but also a viable next pick.

---

## Approach validation

**What worked.**

- **Direct reads + parallel Explore agents scaled cleanly for ~8.3k LoC.** All 12 ViewModels + 5 Dashboard files + PlaybackView read directly (~3.2k LoC, the load-bearing files). 3 parallel Explore agents covered the remaining 42 Views (~5.1k LoC across 3 batches of ~15 files each). Total Pass-1 wall-clock: ~5 minutes. Same hybrid pattern as CA.5; expanded cleanly to the ~20% larger surface.

- **The U.10 / U.11 timing-margin verification produced a complete per-file table with U.11-baseline comparison for every widened site.** All 9 chip-touched files verified compliant. The kickoff's specific concern (post-chip margins matching U.11) is now answerable with a single grep.

- **The D-091 single-SettingsStore enforcement grep produced confidence in one shot.** Two `@StateObject SettingsStore` hits (one legitimate at app entry, one a comment warning) + one `@EnvironmentObject SettingsStore` hit (the load-bearing PlaybackView consumer) + the test-file shadow probe — all expected; no surprises.

- **The PlaybackChromeViewModel consumer-chain trace produced 10 byte-level confirmations matching the BUG-015 / D-091 design.** The publisher binds in ContentView.swift:85, relays through PlaybackView.swift:74,90, lands in PlaybackChromeViewModel.swift:121,169-176, and is consumed in :242-254 — no lowercased title+artist string matching anywhere. The `grep -rnE "lowercased\(\).*title|lowercased\(\).*artist" PhospheneApp/ViewModels PhospheneApp/Views` returned zero matches.

- **The DASH.7 / D-089 verification produced 16 line-anchored confirmations.** Every DASH.7.2 / D-089 claim (DarkVibrancyView backdrop, 0.96α surface, 1px border, dark colorScheme lock, 320pt width, allowsHitTesting(false), accessibilityHidden(true), 33ms throttle, ingestForTest test seam, 240-sample stem history, .singleValue D-089 inline, .progressBar 110pt+.fixedSize, no SF Symbols, asymmetric transition, spring toggle, dashboard typography 15pt + 11pt + 1.5 tracking) is anchored to a file:line.

- **The Spotify state-machine exhaustive-switch verification caught the U.11 case coverage successfully.** All 12 SpotifyConnectionState cases have switch arms in SpotifyConnectionView (lines 71-99). U.11's three additions (`.requiresLogin`, `.waitingForCallback`, `.authFailure`) verified present. The CLAUDE.md U.11 learning ("update every switch in the corresponding view simultaneously") is satisfied.

**What didn't.**

- **The kickoff's LoC estimate was ~20% low.** Kickoff said ~6.9k; actual is 8,285. Not a methodology problem — the hybrid approach scaled. But future CA kickoff drafters should `wc -l` the scope before quoting LoC.

- **The `unverified-claim` for ConnectorPickerView's Apple Music inline-VM** is harder to convert into a hard verdict than the equivalent field-level orphan findings in CA.4 / CA.5 were. The defect mode depends on SwiftUI internal behaviour (NavigationStack destination closure re-eval semantics under parent body re-eval) that I don't have access to empirical evidence on. The audit captured the architectural inconsistency but couldn't say definitively "this is broken right now." Honest verdict.

- **Two file-internal docstring drifts in DashboardOverlayView + DashboardCardView** had to be flagged separately from the ARCHITECTURE.md doc-drift cluster. These are NOT the systemic ARCHITECTURE.md drift the prior five audits surfaced — they're drifts INSIDE the source files' own intro comments. Different problem class, different fix path (the source comment edit lives with the code, not in ARCHITECTURE.md). Future audits should distinguish "ARCHITECTURE.md drift" from "source-file docstring drift" explicitly.

- **One trivial mis-recount during writeup:** I initially miscounted Views/ at 47 but the Module Map sub-block lists ~20 entries; the `built-but-undocumented` finding's "27 missing" calculation is correct (47 - 20 = 27). Corrected inline.

**Recommended changes for CA.7 (CA-Renderer / CA-Audio).**

1. **`wc -l` the scope before drafting kickoff LoC estimates.** CA.7-kickoff: actually count the files in scope, don't paraphrase from a prior audit's note. Estimate accuracy helps the sub-scope decision.

2. **For CA-Renderer specifically:** the renderer has many auto-generated / build-time files (per-preset shader pipeline-state caches, etc.). Spend extra time in Pass 0 classifying "in scope (Swift source)" vs "out of scope (build artifact)" before the sub-scope decision.

3. **The hybrid direct-read + Explore-agent approach continues to be the right default for ≤ 10k LoC subsystems.** CA.1 + CA.2 + CA.3 + CA.4 + CA.5 + CA.6 each validated this. The cross-check rule on Explore-agent visibility claims continues to be cheap insurance.

4. **The `[<kickoff section>]` verification template (BUG-015 wire shape; D-091 enforcement; DASH.7 surface; U.10/U.11 timing margins)** continues to surface concrete, falsifiable findings. CA.7-kickoff should specify equivalent verification asks for the next subsystem (e.g., for CA-Renderer: G-buffer slot binding contract, frame-budget governor cadence, MLDispatchScheduler deferral caps, per-preset state class slot-binding correctness).

5. **The Pass 0 BUG-status cross-check has now returned zero drift in three consecutive audits (CA.4, CA.5, CA.6).** Keep doing it; it costs 2 minutes and catches stale kickoffs.

The audit format continues to produce actionable findings: 3 small follow-up items (two file-header docstring drifts + one architectural-consistency question), 1 optional doc-promotion (CA.6-FU-4), 1 CA.5-FU-2 carry-forward, plus the four kickoff-required verifications all clean. Recommend continuing the format into CA.7. The App layer is now closed.

---

*End of CA.6 — Capability Registry — App Layer (Views + ViewModels).*
