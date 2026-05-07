Execute Increment QR.4 (U.12) — UX dead ends + duplicate `SettingsStore` + dead settings + hardcoded strings.

Authoritative spec: `docs/ENGINEERING_PLAN.md` §Phase QR §Increment QR.4.
Authoritative UX spec: `docs/UX_SPEC.md` (state-to-view mapping §1.4–§1.6, EndedView §3.6 + line 948, ConnectingView §3.2, copy principles §8.5, error taxonomy §8).
Authoritative defect taxonomy: `docs/QUALITY/DEFECT_TAXONOMY.md`.

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. QR.1 (D-079), QR.2 (D-080), QR.3 (D-090) must have landed. Verify with
   `git log --oneline | grep -E '\[QR\.(1|2|3)\]'` — expect at least one
   commit per increment.

2. Confirm QR.4 surface is unstarted: the four new test files listed in
   SCOPE below should NOT yet exist.
   `for f in EndedViewTests ConnectingViewCancelTests \
            SettingsStoreEnvironmentRegressionTests \
            PlaybackChromeIndexBindingTests; do
      find PhospheneApp/Tests PhospheneAppTests Tests -name "${f}.swift" 2>/dev/null; done`
   — expect zero results.

3. Decision-ID numbering: D-090 was the most recent (QR.3). The next
   available is **D-091**. Verify with
   `grep '^## D-0' docs/DECISIONS.md | tail -3`.

4. Existing surfaces that QR.4 modifies (read these before writing):

   - `PhospheneApp/Views/Ended/EndedView.swift` — currently a 25-LOC
     stub that already uses `String(localized: "ended.headline")` and
     `"ended.subtext"` (the "U.1 stub" header comment is stale; the
     localisation keys exist in `Localizable.strings`). Lacks the
     "Start another session" CTA, session summary text, and any wiring
     to `SessionManager.endSession()`. Per UX_SPEC §1.4 row 6 + line 948:
     "Reflection, not administration. Session duration and track count.
     'New session' in coral. Should feel like house lights coming up
     gently." Keys to add: `ended.summary.tracks`, `ended.summary.duration`,
     `ended.cta.newSession`, `ended.cta.openFolder`.

   - `PhospheneApp/Views/Connecting/ConnectingView.swift` — 24-LOC stub
     with two hardcoded strings: `"Connecting…"` (line 15), `"Reading
     your playlist"` (line 18). No cancel button. Per UX_SPEC §1.4 row 2:
     "Per-connector spinner + cancel". `SessionManager.cancel()` already
     exists; wire it via injected closure for testability.

   - `PhospheneApp/Views/Playback/PlaybackView.swift:50` — currently
     `@StateObject private var settingsStore = SettingsStore()` creates
     a parallel `SettingsStore` instance. The global singleton is
     constructed in `PhospheneApp.swift` and injected via
     `@EnvironmentObject` everywhere else. Phosphene reviewer (2026-05-06)
     flagged: "duplicate that silently swallowed every capture-mode change."
     Replace with `@EnvironmentObject var settingsStore: SettingsStore`.

   - `PhospheneApp/Services/SettingsStore.swift:80` — `includeMilkdropPresets`
     persisted Bool, no consumer. Comment at top of file (line 20):
     "showPerformanceWarnings: Inc 6.2 downstream wiring; flag stored now."
     The wiring has not landed.
   - `PhospheneApp/Services/SettingsStore.swift:54` (`showPerformanceWarnings`
     UserDefaults key) — same shape, no consumer.
   - Both surface in:
     `PhospheneApp/Views/Settings/VisualsSettingsSection.swift:55-61` (Milkdrop)
     `PhospheneApp/Views/Settings/DiagnosticsSettingsSection.swift:49-50` (Perf)
     `PhospheneApp/ViewModels/SettingsViewModel.swift:64,95-97,130-132` (bindings).

   - `PhospheneApp/ViewModels/PlaybackChromeViewModel.swift:222-234` —
     `refreshProgress()` matches the live track against `livePlan.tracks`
     using `title.lowercased() == ... && artist.lowercased() == ...`.
     Covers/remasters/encoding differences break the match. The plan walk
     already knows the index (`PlannedSession.track(at:)`); publish
     `currentTrackIndex: Int?` from `VisualizerEngine` and bind directly.
     Note (`PlaybackChromeViewModel.swift:16-17`):
     "livePlannedSession is @Published. No currentTrackIndex published —
     derived here by matching currentTrack against plan.tracks by title."

   - Hardcoded user-facing strings (8 confirmed sites; spec says 12 — paths
     differ slightly from ENGINEERING_PLAN.md, real paths below):
     - `Views/Connecting/ConnectingView.swift:15,18` (2)
     - `Views/Idle/IdleView.swift:26` ("Phosphene" — keep as `appName`) (1)
     - `Views/Playback/PlaybackView.swift:154,155,157` (end-session
       confirmationDialog: "End session" / "Cancel" / "The visualizer
       session will stop.") (3)
     - `Views/Playback/PlaybackControlsCluster.swift:36` (".help(\"Settings
       (coming soon)\")" — tooltip lie; settings is wired as of U.8)
     - `Views/Playback/PlaybackControlsCluster.swift:47`
       (".help(\"End session (Esc)\")") (2 in this file)
     - `Views/Playback/ListeningBadgeView.swift:36` ("Listening…") (1)
     - `Views/Playback/SessionProgressDotsView.swift:49,56`
       ("Reactive" + "<n> of <m>") (2)
     - `Views/Ready/PlanPreviewView.swift` + `PlanPreviewRowView.swift`
       (path correction — files live in `Ready/`, not `Plan/`. Grep for
       `Text\("` and `.help\("` in those two files for the exact lines.) (3+)

   - `PhospheneApp/Views/Ready/PlanPreviewView.swift` — has a "Modify"
     button currently disabled with empty closure. Hide entirely for v1
     per spec sub-item 6 (V.5 plan-modification work has not landed).

   - `PhospheneApp/VisualizerEngine.swift:54-93` — existing `@Published`
     properties. Add `@Published var currentTrackIndex: Int?` on the
     same actor-isolation pattern (engine is `@MainActor` per
     ContentView wiring). The plan walk in
     `VisualizerEngine+Orchestrator.swift` already computes the index;
     surface it.

5. `default.profraw` and `prompts/*.md` may be present in the repo root.
   Ignore.

6. Active in-progress work on `LiveBeatDriftTracker.swift` /
   `MIRPipeline.swift` etc. lives in BUG-007 / BUG-008 territory and is
   ORTHOGONAL to QR.4. If `git status` shows working-tree modifications
   to those files when QR.4 starts: surface to Matt and stage QR.4-only
   files (the same procedure used for QR.3 — see QR.3 closeout).

────────────────────────────────────────
GOAL
────────────────────────────────────────

Close the user-facing rough edges flagged in the multi-agent App+UX
review and the Phosphene reviewer (2026-05-06). Each is small in
isolation; together they restore the "uninterrupted ambient member of
the band" feel that the architecture promises.

The highest-leverage item is the duplicate `SettingsStore`: it is the
same shape of bug as the silent-skip class QR.3 just closed, but in
*product behaviour* — user toggles a setting, a parallel store accepts
the toggle, the playback-side reconciler observes a different store
that never changed. Catching this with a regression test (assert one
store, assert reconciler reads it) is the load-bearing test gate for
the increment.

────────────────────────────────────────
SCOPE
────────────────────────────────────────

The plan has eight sub-items. Land them in two commit boundaries
(grouping is per-commit; within a commit, sub-items can land in any
internal order). Each sub-item below has a concrete file path, a
concrete change, and concrete assertions to write.

──── COMMIT 1: structural fixes (sub-items 1–4, 6) ────

1. EDIT — `EndedView.swift` (sub-item 1)
   Path: `PhospheneApp/Views/Ended/EndedView.swift`

   Replace the U.1 stub body with a session-summary card per UX_SPEC §3.6
   + line 948. Required surfaces:

   - Headline `String(localized: "ended.headline")` (already exists).
   - Summary block:
     - Track count played: `"<n> tracks"` via new key `ended.summary.tracks`.
     - Session duration: `"<HH:MM>"` via new key `ended.summary.duration`.
   - "Start another session" button (coral, primary CTA — see
     `Color.coral` in DashboardTokens or fallback to `.accentColor`):
     calls injected closure `onStartNewSession`. Wires through
     `PhospheneApp.swift` to `sessionManager.endSession()` (which
     transitions `.ended → .idle`).
   - "Open sessions folder" secondary action: opens
     `~/Documents/phosphene_sessions/` via `NSWorkspace.shared.open(_:)`.

   Inputs (new — make `EndedView` accept):
     ```swift
     let trackCount: Int
     let sessionDuration: TimeInterval
     let onStartNewSession: () -> Void
     let onOpenSessionsFolder: () -> Void
     ```

   Wiring: the parent (`ContentView`) passes these from
   `SessionManager` state. `sessionDuration` = endTime − startTime
   (track in `SessionManager` if not already; if it requires engine
   plumbing > 30 LOC, surface to Matt before expanding scope — a fall-
   back of "—" with a docstring TODO is acceptable to keep the
   increment scoped).

   New `Localizable.strings` keys (English):
   ```
   "ended.headline" = "Session complete";   // already exists; verify wording
   "ended.subtext" = "...";                 // already exists; verify
   "ended.summary.tracks" = "%lld tracks";
   "ended.summary.duration" = "%@";         // formatted via DateComponentsFormatter
   "ended.cta.newSession" = "Start another session";
   "ended.cta.openFolder" = "Open sessions folder";
   ```

   Per UX_SPEC line 948: "'New session' in coral." Style the primary
   CTA accordingly.

2. EDIT — `ConnectingView.swift` (sub-item 2)
   Path: `PhospheneApp/Views/Connecting/ConnectingView.swift`

   Replace the U.1 stub with:
   - Per-connector spinner that takes a `connector: ConnectorType` enum
     param and renders the connector icon + name. (See
     `Services/ConnectorType.swift` — Apple Music / Spotify / Local
     Folder enum already has `title`/`subtitle`/`systemImage`.)
   - Headline: `String(localized: "connecting.headline")`.
   - Subtext: per-connector via switch on `connector` — Apple Music
     → `String(localized: "connecting.appleMusic.subtext")`, Spotify
     → `connecting.spotify.subtext`, Local Folder
     → `connecting.localFolder.subtext`.
   - Cancel button: calls injected `onCancel: () -> Void` closure.
     Localized as `connecting.cta.cancel`.

   `connecting.headline` = `"Connecting"` (no ellipsis — UX_SPEC §8.5
   discourages ambient ellipses on top-level state titles; lower
   subtext can use them).

   Wiring: parent passes `connector` + `onCancel` from
   `SessionManager.cancel()`. Cancel transitions
   `.connecting → .idle` via the existing path.

3. EDIT — `PlaybackView.swift` duplicate `SettingsStore` collapse (sub-item 3)
   Path: `PhospheneApp/Views/Playback/PlaybackView.swift`

   Line 50:
   ```swift
   @StateObject private var settingsStore = SettingsStore()
   ```
   Replace with:
   ```swift
   @EnvironmentObject var settingsStore: SettingsStore
   ```

   Verify `PhospheneApp.swift` passes the global `SettingsStore` via
   `.environmentObject(settingsStore)` somewhere up the view tree (it
   does as of U.8 — confirm `IdleView`, `PlaybackView`, `ContentView`
   all see it). If a parent does not provide the env object, `PlaybackView`
   will crash at runtime — surface immediately and add the missing
   `.environmentObject(...)` at the parent.

   Verify `CaptureModeSwitchCoordinator` (built in `PlaybackView.setup()`)
   subscribes to `settingsStore.captureModeChanged`. With the
   `@StateObject`, it was subscribing to a never-written-to channel.
   With `@EnvironmentObject`, it now sees user toggles.

   Smoke test: launch app, change capture mode in Settings, observe
   `CaptureModeSwitchCoordinator` log line "capture mode changed: X → Y"
   in the engine log. Must fire — pre-fix it didn't.

4. DECIDE-AND-DELETE — Dead settings (sub-item 4)
   Paths:
   - `PhospheneApp/Services/SettingsStore.swift` — properties at lines
     54 (key) + 80 (`includeMilkdropPresets`).
   - `PhospheneApp/ViewModels/SettingsViewModel.swift` — bindings at
     lines 64, 95-97, 130-132.
   - `PhospheneApp/Views/Settings/VisualsSettingsSection.swift:55-61`
     (Milkdrop UI).
   - `PhospheneApp/Views/Settings/DiagnosticsSettingsSection.swift:49-50`
     (Perf warnings UI).
   - `PhospheneApp/Localizable.strings` — keys for both row labels.
   - `PhospheneApp/Services/AccessibilityLabels.swift` — labels for
     both (if any).

   **Decision recipe per property:**

   `showPerformanceWarnings` — comment in `SettingsStore.swift:20`
   says "Inc 6.2 downstream wiring; flag stored now." Phase 6.2 has
   landed (FrameBudgetManager). The wiring never happened. Choose:
     - (a) Wire it: `FrameBudgetManager` already exposes
       `currentLevel` via `dashboardSnapshot`. Add a top-banner toast
       (`PhospheneToast`) when `currentLevel != .full` AND
       `showPerformanceWarnings == true`. Threshold: only fire on
       *transitions* to a degraded level, not every frame; debounce
       30 s per transition.
     - (b) **Delete** (preferred if (a) requires > 50 LOC of toast
       wiring): remove the property, the UI row, the binding, the
       VM property, the Localizable.strings keys, the
       `AccessibilityLabels` entry. Add a one-line `D-091` note in
       DECISIONS.md ("removed; FrameBudgetManager dashboard surfaces
       the same info with no extra UI surface needed").

   `includeMilkdropPresets` — gates Phase MD ingestion which is
   genuinely deferred. **Hide behind `#if DEBUG`** rather than ship
   a permanently-disabled toggle. Keep the property + persistence
   (so user state survives a debug-build round-trip) but the row
   + binding only appear in DEBUG builds.

   Pick the cheaper path for `showPerformanceWarnings` (likely
   delete). Document the choice in D-091 and in the commit message.

5. *(reserved — sub-item 5 in spec is the hardcoded-strings bundle;
   lands in commit 2 alongside the localizable.strings rewrite.)*

6. EDIT — Hide the disabled "Modify" button (sub-item 6)
   Path: `PhospheneApp/Views/Ready/PlanPreviewView.swift`
   (NOT `Views/Plan/...` — the file is in `Ready/` per actual repo layout).

   Find the "Modify" button currently rendered as disabled with empty
   closure. Wrap in `#if false` (or `#if ENABLE_PLAN_MODIFICATION`
   build flag — preferred, mirrors the `LocalFolderConnector` pattern
   from U.3) so it does not appear in the v1 build. Restore wiring
   in V.5 plan-modification work.

──── COMMIT 2: strings + plumbing + tests + docs (sub-items 5, 7, 8 + tests) ────

5. EDIT — Hardcoded strings → `Localizable.strings` (sub-item 5 + 8)

   For each call site below, replace the literal with
   `String(localized: "key")` (or `Text(.localized(...))` per existing
   patterns). Add the corresponding key to
   `PhospheneApp/Localizable.strings` (English, the only locale shipped).

   | File | Line | Current | Key |
   |---|---|---|---|
   | `Views/Connecting/ConnectingView.swift` | 15 | `"Connecting…"` | `connecting.headline` |
   | `Views/Connecting/ConnectingView.swift` | 18 | `"Reading your playlist"` | `connecting.subtext` (default) + per-connector keys (sub-item 2) |
   | `Views/Idle/IdleView.swift` | 26 | `"Phosphene"` | `appName` |
   | `Views/Playback/PlaybackView.swift` | 154 | `"End session"` | `playback.endSession.confirm` |
   | `Views/Playback/PlaybackView.swift` | 155 | `"Cancel"` | `common.cancel` |
   | `Views/Playback/PlaybackView.swift` | 157 | `"The visualizer session will stop."` | `playback.endSession.message` |
   | `Views/Playback/PlaybackControlsCluster.swift` | 36 | `.help("Settings (coming soon)")` | `playback.controls.settings.tooltip` (value: `"Settings"` — drop the lie) |
   | `Views/Playback/PlaybackControlsCluster.swift` | 47 | `.help("End session (Esc)")` | `playback.controls.endSession.tooltip` |
   | `Views/Playback/ListeningBadgeView.swift` | 36 | `"Listening…"` | `playback.listening` |
   | `Views/Playback/SessionProgressDotsView.swift` | 49 | `"Reactive"` | `playback.progress.reactive` |
   | `Views/Playback/SessionProgressDotsView.swift` | 56 | `"\(progress.currentIndex + 1) of \(progress.totalTracks)"` | `playback.progress.position` (format: `"%lld of %lld"`) |
   | `Views/Ready/PlanPreviewView.swift` | (grep `Text\("`) | various | `plan.preview.*` |
   | `Views/Ready/PlanPreviewRowView.swift` | (grep `Text\("`) | various | `plan.preview.row.*` |

   Add localized labels in
   `PhospheneApp/Services/AccessibilityLabels.swift` for any new
   buttons/controls (EndedView CTAs, ConnectingView cancel, hidden
   Modify if it ever returns).

7. PLUMBING — `currentTrackIndex` published from `VisualizerEngine`
   Paths:
   - `PhospheneApp/VisualizerEngine.swift` — add
     `@Published var currentTrackIndex: Int?` near the other
     `@Published` properties at lines 54–93.
   - `PhospheneApp/VisualizerEngine+Orchestrator.swift` — the plan
     walk that produces the next track also knows the index. Set
     `currentTrackIndex = …` on the same `@MainActor` hop that
     updates `currentPresetName`. Set to `nil` on `livePlan = nil`
     and on track change to a track not in the plan.
   - `PhospheneApp/ViewModels/PlaybackChromeViewModel.swift:222-234` —
     replace `refreshProgress()` body that does
     `title.lowercased() == ... && artist.lowercased() == ...`
     matching with direct read from
     `engine.$currentTrackIndex`. Update the head-of-file comment
     (lines 16-17) to say "currentTrackIndex is published by
     VisualizerEngine; no string matching needed."
   - Replace the `Combine` subscription chain accordingly: the chrome
     VM already takes a publisher in its init (`currentTrackPublisher`);
     add a sibling `currentTrackIndexPublisher: AnyPublisher<Int?, Never>`
     and wire from `PlaybackView.setup()` callsite.

   The fix removes ~12 LOC from `refreshProgress` and makes the chrome
   robust to covers/remasters/encoding differences (Failed Approach
   territory — the existing matching silently failed for those cases).

────────────────────────────────────────
TESTS
────────────────────────────────────────

All four new test files live under
`PhospheneApp/PhospheneAppTests/` (or `Tests/PhospheneAppTests/` —
check existing layout via `find PhospheneApp -name "*Tests.swift" |
head -5` before placing). Add to the Xcode project file in all four
sections (PBXBuildFile / PBXFileReference / PBXGroup / PBXSourcesBuildPhase)
per the U.11 learning recorded in CLAUDE.md:
"New app-layer source files must be registered in Xcode project.pbxproj
across all four sections." Verify with
`xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test`
before committing — missing project registration only surfaces at app
build, not at engine `swift test`.

1. NEW — `SettingsStoreEnvironmentRegressionTests.swift`
   **Load-bearing test for the increment.** Catches the duplicate-instance
   bug if it ever recurs. Approach:
   - Construct one `SettingsStore`.
   - Render a SwiftUI view hierarchy via `NSHostingView` that includes
     a stand-in for `PlaybackView`'s `setup()` flow (a small test
     `View` that takes `@EnvironmentObject var settingsStore: SettingsStore`
     and exposes the captureMode value via a binding to a `@Published`
     property).
   - Toggle `captureMode` on the store from the test.
   - Wait for next runloop tick (`RunLoop.current.run(until: Date().advanced(by: 0.05))`).
   - Assert the view-side observer reads the new value.

   Approximate shape (~60 LOC):

   ```swift
   @Suite("SettingsStoreEnvironmentRegression")
   struct SettingsStoreEnvironmentRegressionTests {

       @Test("captureMode toggle on global store propagates to env-object consumer")
       @MainActor
       func test_captureModeChangePropagates() async {
           let store = SettingsStore()
           store.captureMode = .systemAudio

           final class Observer: ObservableObject {
               @Published var observed: CaptureMode = .systemAudio
           }
           let observer = Observer()

           struct Probe: View {
               @EnvironmentObject var store: SettingsStore
               @ObservedObject var observer: Observer
               var body: some View {
                   Color.clear
                       .onAppear { observer.observed = store.captureMode }
                       .onChange(of: store.captureMode) { _, new in observer.observed = new }
               }
           }
           let host = NSHostingView(rootView: Probe(observer: observer)
               .environmentObject(store))
           let window = NSWindow(...)
           window.contentView = host
           // Tick runloop so onAppear fires.
           RunLoop.current.run(until: Date().advanced(by: 0.05))
           store.captureMode = .applicationAudio(bundleID: "com.spotify.client")
           RunLoop.current.run(until: Date().advanced(by: 0.05))
           #expect(observer.observed == .applicationAudio(bundleID: "com.spotify.client"))
       }
   }
   ```

   This test catches the regression where `PlaybackView` instantiated
   its own `SettingsStore`. Pre-fix: the test would still observe the
   global store, but `PlaybackView`'s parallel store would never see
   the change — the test fails at the assertion if `Probe` is replaced
   with a literal `PlaybackView`-shaped wrapper.

   **Important:** to actually catch the regression, the test should
   include a "shadow `@StateObject` SettingsStore" in the probe (the
   pre-fix shape) and assert it does NOT see the change, and the
   `@EnvironmentObject` reader DOES. This is the load-bearing test.

2. NEW — `EndedViewTests.swift`
   - Renders `EndedView` with stub `trackCount=4`, `sessionDuration=180`.
   - Asserts the rendered view contains "4 tracks" or matching localized
     formatted string.
   - Asserts the "Start another session" button's accessibility label
     matches `String(localized: "ended.cta.newSession")`.
   - Asserts tapping the button calls the injected `onStartNewSession`
     closure exactly once.

3. NEW — `ConnectingViewCancelTests.swift`
   - Renders `ConnectingView(connector: .spotify, onCancel: { ... })`.
   - Asserts the rendered view contains the localized
     `connecting.spotify.subtext`.
   - Asserts the cancel button is reachable via accessibility identifier.
   - Asserts tapping it calls the `onCancel` closure exactly once.

4. NEW — `PlaybackChromeIndexBindingTests.swift`
   - Constructs a `PlaybackChromeViewModel` with the new
     `currentTrackIndexPublisher` injection point.
   - Sends `.send(2)` on the publisher.
   - Asserts the chrome VM's `progress.currentIndex == 2` (or whatever
     the published surface is).
   - Sends a track change with a *different title from any plan track*
     — pre-fix this would have left progress stale; post-fix the index
     binding handles it correctly.
   - Asserts no string-matching code path is exercised (drop the
     `title.lowercased()` lines from `refreshProgress` per sub-item 7).

5. NEW — `Scripts/check_user_strings.sh`
   Bash script with the same shape as
   `Scripts/check_sample_rate_literals.sh` (D-079, QR.1). Greps:
   ```
   grep -rEn 'Text\("[A-Z]|\.help\("[A-Z]|\.accessibilityLabel\("[A-Z]' \
     PhospheneApp/Views/ \
     | grep -v 'Text(verbatim:' \
     | grep -v 'String(localized:'
   ```
   Pipe through an allowlist of acknowledged debug strings (e.g.
   `DebugOverlayView.swift` and `DashboardOverlayView.swift` may use
   English literals for diagnostic-only surfaces). Fails (exit code
   non-zero) on any hit not in the allowlist.

   Document in `docs/RUNBOOK.md` § (new section) "User-string
   externalisation gate" with the script invocation. Wire into
   any existing CI check script if there is one (`Scripts/lint.sh`
   or similar). If no aggregator exists, leave the script standalone
   — Matt invokes manually before committing UX changes.

────────────────────────────────────────
NON-GOALS (DO NOT IMPLEMENT)
────────────────────────────────────────

- Do NOT add Plan-modification UI (the disabled "Modify" button is
  *hidden*, not re-implemented). V.5 plan-modification work owns this
  surface.
- Do NOT add additional locales. English is the only shipped locale;
  every key just needs an English string. The point is externalisation,
  not translation.
- Do NOT redesign the `EndedView` summary card beyond what
  UX_SPEC §3.6 + line 948 specifies. "Reflection, not administration"
  — the increment is dead-end-removal, not a UX redesign.
- Do NOT introduce a `PerformanceWarningToastBridge` wiring for
  `showPerformanceWarnings` if it requires > 50 LOC. Delete the
  setting per Decision recipe in sub-item 4. The dashboard PERF card
  already surfaces the information; a separate toast surface is
  redundant.
- Do NOT refactor `PlaybackChromeViewModel` beyond replacing the
  string-match block with the index publisher. The "extract Combine
  pipeline into helper" rewrite is QR.6 territory.
- Do NOT add an "Are you sure?" confirmation to the EndedView
  "Start another session" CTA. The user is in a terminal state;
  starting a new session is the only forward path.
- Do NOT increase `PlaybackView`'s file size beyond the duplicate-store
  delta. Other refactors (e.g. extracting `setup()` body into a
  separate file) are QR.6 territory.

────────────────────────────────────────
DESIGN GUARDRAILS (CLAUDE.md)
────────────────────────────────────────

- **One `SettingsStore`, app-wide.** The new
  `SettingsStoreEnvironmentRegressionTests` is the regression gate.
  CLAUDE.md gains a one-line entry under §UX Contract:
  "There is exactly one `SettingsStore` instance in the app. Consume
  via `@EnvironmentObject`, never re-instantiate via `@StateObject`.
  `SettingsStoreEnvironmentRegressionTests` enforces this."

- **No string literals in user-facing views.** All `Text(...)`,
  `.help(...)`, `.accessibilityLabel(...)` arguments must resolve
  through `Localizable.strings`. `Scripts/check_user_strings.sh`
  enforces this in CI. Acceptable exemptions: debug overlays,
  dashboard diagnostic surfaces (allowlisted in the script).

- **Tooltip lies are bugs.** Tooltips MUST describe what the
  control does *now*, not what it *will* do. Phrasing like "(coming
  soon)" or "(disabled)" on a wired control is forbidden. If a
  control is genuinely not yet wired, hide it (sub-item 6 pattern).

- **State machine uses `currentTrackIndex: Int?`, never string match.**
  The plan walk knows the index by construction; surface the index.
  String matching against title+artist for plan correlation is
  forbidden post-QR.4 — covers, remasters, encoding differences
  break it. Add a CLAUDE.md "What NOT to do" entry.

- **EndedView feels like house lights.** Per UX_SPEC line 948:
  "Reflection, not administration. Should feel like house lights
  coming up gently." Avoid shipping a results dashboard with charts;
  the summary is two lines (track count, duration) + one primary
  CTA + one secondary action. The "ambient member of the band" tone
  carries through to the wind-down.

────────────────────────────────────────
VERIFICATION
────────────────────────────────────────

Order matters. Each step must pass before proceeding.

1. **Build (engine)**: `swift build --package-path PhospheneEngine`
   — must succeed with zero warnings on touched files. Engine is not
   modified by QR.4, but build is the cheap regression gate.

2. **Build (app)**: `xcodebuild -scheme PhospheneApp -destination
   'platform=macOS' build 2>&1 | tail -3` — must end
   `** BUILD SUCCEEDED **`. The duplicate `SettingsStore` collapse
   only manifests at app build; do this immediately after the
   `@EnvironmentObject` change to catch missing `.environmentObject(...)`
   parents.

3. **Per-suite tests** (run each in isolation first):
   ```
   xcodebuild -scheme PhospheneApp -destination 'platform=macOS' \
     test -only-testing:PhospheneAppTests/SettingsStoreEnvironmentRegression
   xcodebuild -scheme PhospheneApp -destination 'platform=macOS' \
     test -only-testing:PhospheneAppTests/EndedView
   xcodebuild -scheme PhospheneApp -destination 'platform=macOS' \
     test -only-testing:PhospheneAppTests/ConnectingViewCancel
   xcodebuild -scheme PhospheneApp -destination 'platform=macOS' \
     test -only-testing:PhospheneAppTests/PlaybackChromeIndexBinding
   ```
   Each suite must pass.

4. **String-externalisation gate**: `bash Scripts/check_user_strings.sh`
   — zero hits outside the allowlist. Run the script *with the
   pre-fix code* once before sub-item 5 to confirm it would have
   caught the regression (expect ≥ 12 hits). Then run after sub-item
   5 lands (expect 0).

5. **Full app suite**: `xcodebuild -scheme PhospheneApp -destination
   'platform=macOS' test` — full suite green except documented
   pre-existing flakes (`SessionManager.afterPreparation_transitionsToReady`
   family, U.11 `MetadataPreFetcher.fetch_networkTimeout`,
   AppleMusicConnectionViewModel timing-sensitive pair). Any other
   failure is a regression.

6. **Engine suite** (regression gate): `swift test --package-path
   PhospheneEngine` — must remain at 1148 tests passing post-QR.3.
   QR.4 should not touch engine code; if a test fails here, surface
   immediately.

7. **SwiftLint**: `swiftlint lint --strict --config .swiftlint.yml
   --quiet <touched files>` — zero violations. Touched files include
   every file in the modified-files list under SCOPE.

8. **Manual validation (mandatory)**: complete a full session
   end-to-end without ever needing to relaunch the app.
   - Launch app, idle screen.
   - Connect a Spotify playlist (or local folder).
   - Watch preparation progress, hit "Start now" if available.
   - Listen to ≥ 2 tracks while the session plays.
   - Open Settings, toggle capture mode → confirm
     `CaptureModeSwitchCoordinator` log fires (not pre-fix: silent).
   - End session via Esc → confirmation dialog shows localized strings.
   - Confirm → reach `EndedView`.
   - Click "Start another session" → return to `.idle`, ready to
     repeat. **No relaunch required at any point.**

   This is the load-bearing UX validation — automated tests can prove
   the wiring is correct, but only manual flow can prove the dead
   ends are gone.

────────────────────────────────────────
DOCUMENTATION OBLIGATIONS
────────────────────────────────────────

After verification passes:

1. **`docs/ENGINEERING_PLAN.md`** — Phase QR §Increment QR.4:
   flip status to ✅ with the date. Update the "Done when"
   checklist (seven boxes — all should now be checked, with the
   manual-validation box ticked by Matt). Add a one-line
   implementation summary noting the 4 view edits + duplicate-store
   collapse + 8+ string externalisations + `currentTrackIndex`
   plumbing + 4 new test files + 1 new lint script.

2. **`docs/DECISIONS.md`** — append D-091 covering:
   - Why `@EnvironmentObject` is the *only* allowed `SettingsStore`
     consumption pattern (the silent-toggle-swallowing bug, the
     regression test that locks it).
   - Decision recipe for `showPerformanceWarnings` (delete vs wire)
     with the chosen path and rationale.
   - Decision to hide `includeMilkdropPresets` behind `#if DEBUG`
     rather than ship a permanently-disabled toggle.
   - Decision to publish `currentTrackIndex: Int?` from the engine
     vs derive it via title-string matching (covers / remasters
     / encoding differences). Cross-link the new "What NOT to do"
     entry in CLAUDE.md.
   - Decision to hide the disabled "Modify" button via build flag
     vs shipping it disabled (deferred to V.5).

3. **`docs/RELEASE_NOTES_DEV.md`** — append `[dev-YYYY-MM-DD-X] QR.4
   — UX dead ends + duplicate SettingsStore + dead settings + hardcoded
   strings` entry. List the file changes by sub-item, the manual-
   validation result, the test count delta.

4. **`docs/UX_SPEC.md`**:
   - Confirm EndedView and ConnectingView copy match the spec.
     If the spec is silent on a string the increment localises,
     add a row.
   - Update §1.4 EndedView row if the implementation deviates from
     "Open sessions folder" wording.

5. **`docs/QUALITY/KNOWN_ISSUES.md`**:
   - No new issues introduced.
   - If `showPerformanceWarnings` is *deleted* vs wired, no
     KNOWN_ISSUES entry needed (it's a setting that was never
     consumed).

6. **`CLAUDE.md`**:
   - §Module Map: update `Views/Ended/EndedView.swift` description
     from "U.1 stub" to its post-QR.4 shape.
     Update `Views/Connecting/ConnectingView.swift` similarly.
   - §UX Contract: add the one-line "There is exactly one
     `SettingsStore`..." rule.
   - §What NOT To Do: add "Do not match the live track against
     `livePlan.tracks` via lowercased title+artist string. Use
     `VisualizerEngine.currentTrackIndex` (Int?, published)."
   - §Code Style: add "User-facing strings in `PhospheneApp/Views/`
     MUST resolve through `Localizable.strings`. Verified by
     `Scripts/check_user_strings.sh`."
   - §Failed Approaches: add #55 — "Re-instantiating `SettingsStore`
     via `@StateObject` in a child view. Same shape as Failed
     Approach #16 (parallel-state world that user inputs never
     reach), but the bug surface is settings rather than chrome.
     Discovered by Phosphene reviewer 2026-05-06; resolved in
     QR.4 / D-091. `SettingsStoreEnvironmentRegressionTests` enforces."

────────────────────────────────────────
COMMITS
────────────────────────────────────────

Two commits, in this order. Each must pass tests at the commit
boundary.

1. `[QR.4] App: dead-end views + SettingsStore env collapse + dead
   settings cleanup` — sub-items 1, 2, 3, 4, 6.
   - EndedView + ConnectingView reimplementations.
   - `PlaybackView.swift` `@EnvironmentObject` collapse.
   - Dead-settings deletion or wiring per Decision recipe.
   - Plan Preview "Modify" button hidden.

2. `[QR.4] App: localizable strings + currentTrackIndex plumbing +
   tests + docs (D-091)` — sub-items 5, 7, 8 + 4 new test files +
   `Scripts/check_user_strings.sh` + all docs.

   The docs update can ride in commit 2 because the doc updates
   reference the full surface of the increment.

Local commits to `main` only. Do NOT push to remote without explicit
"yes, push" approval.

────────────────────────────────────────
RISKS & STOP CONDITIONS
────────────────────────────────────────

- **`@EnvironmentObject` env not provided at the parent.**
  The `@StateObject → @EnvironmentObject` swap will crash at runtime
  if any parent of `PlaybackView` does not provide
  `.environmentObject(settingsStore)`. Audit by:
  ```
  grep -rn '\.environmentObject\(' PhospheneApp/
  ```
  Confirm the chain: `PhospheneApp.swift` (root) → `ContentView` →
  `PlaybackView`. If `PlaybackView` is ever rendered directly outside
  this chain (e.g. in a `.sheet` or preview), add the env object at
  that callsite.

- **`sessionDuration` plumbing in `EndedView` is non-trivial.**
  `SessionManager` may not currently track a session-start timestamp.
  If adding it requires > 30 LOC of session-state changes, **STOP
  and surface to Matt**. The fallback for v1: omit the duration
  surface, ship just the track count + CTA, file a follow-up issue.

- **Duplicate-store regression test is hard to write hermetically.**
  The test wants to assert that a `@StateObject`-style consumer
  does NOT see changes vs an `@EnvironmentObject` consumer that
  DOES. SwiftUI test infrastructure can be flaky for property-wrapper
  behaviour. If the test cannot be made deterministic in < 2 hours of
  work, the load-bearing assertion (env-object consumer sees the
  change) is sufficient on its own — the rest is documentation.
  STOP and surface to Matt before sinking > 2 hours into the
  parallel-store discriminator.

- **`Scripts/check_user_strings.sh` allowlist is too permissive.**
  If the allowlist ends up including more than ~5 file patterns, the
  gate is decorative. Tighten the script's allowlist or refactor the
  offending files (DebugOverlayView etc.) to use localized strings
  for any user-visible surfaces (developer-only surfaces are
  exempt — DebugOverlayView is gated on `D` shortcut + showDebug).

- **Plan-preview file path mismatch.** The ENGINEERING_PLAN.md spec
  references `Views/Plan/PlanPreviewView.swift`; the actual file is
  `Views/Ready/PlanPreviewView.swift`. Adjust references in the
  prompt's call-site table — verify with
  `find PhospheneApp/Views -name "PlanPreview*.swift"` before
  starting sub-item 5 or 6.

- **STOP and report instead of forging ahead** if:
  - Any pre-QR.4 test breaks (the suite count goes down on a fresh
    run, indicating a regression introduced by the new code).
  - The duplicate-store collapse produces a runtime crash that can't
    be resolved by adding `.environmentObject(...)` at a single
    parent site (indicates a deeper refactor needed).
  - `showPerformanceWarnings` wiring (option (a)) ends up exceeding
    50 LOC — switch to deletion (option (b)).
  - `currentTrackIndex` plumbing requires changes to
    `PlannedSession` or the orchestrator's plan walk beyond a
    single-line index publish.
  - Any localizable.strings key collides with an existing key.
    Surface the collision; do not silently overwrite.

────────────────────────────────────────
REFERENCES
────────────────────────────────────────

- Engineering plan: `docs/ENGINEERING_PLAN.md` §Phase QR §Increment QR.4
- UX spec: `docs/UX_SPEC.md` §1.4 (state-to-view), §3.2 (ConnectingView),
  §3.6 (EndedView), §8 (error taxonomy), §8.5 (copy principles), line 948
  (EndedView feel)
- Quality docs: `docs/QUALITY/DEFECT_TAXONOMY.md`,
  `docs/QUALITY/KNOWN_ISSUES.md`, `docs/QUALITY/BUG_REPORT_TEMPLATE.md`
- Failed Approaches catalogue: `CLAUDE.md` Failed Approaches
  (after QR.4: #55 added — duplicate `SettingsStore` parallel state)
- Existing files (read before writing):
  - `PhospheneApp/Views/Ended/EndedView.swift`
  - `PhospheneApp/Views/Connecting/ConnectingView.swift`
  - `PhospheneApp/Views/Playback/PlaybackView.swift` (line 50)
  - `PhospheneApp/Services/SettingsStore.swift`
  - `PhospheneApp/ViewModels/SettingsViewModel.swift`
  - `PhospheneApp/ViewModels/PlaybackChromeViewModel.swift` (lines 222-234)
  - `PhospheneApp/VisualizerEngine.swift` (lines 54-93 for
    `@Published` placement)
  - `PhospheneApp/VisualizerEngine+Orchestrator.swift` (plan walk
    that produces the index)
  - `PhospheneApp/Views/Settings/VisualsSettingsSection.swift`
  - `PhospheneApp/Views/Settings/DiagnosticsSettingsSection.swift`
  - `PhospheneApp/Views/Ready/PlanPreviewView.swift` + `PlanPreviewRowView.swift`
  - `PhospheneApp/Views/Playback/{PlaybackControlsCluster,ListeningBadgeView,SessionProgressDotsView}.swift`
  - `PhospheneApp/PhospheneApp.swift` (env-object root injection)
  - `PhospheneApp/Localizable.strings` (English)
  - `PhospheneApp/Services/AccessibilityLabels.swift`
  - `PhospheneApp/Services/ConnectorType.swift` (per-connector display)
- Production code touched (engine): none. QR.4 is app-layer only.
- Reference implementations:
  - `Scripts/check_sample_rate_literals.sh` (D-079, QR.1) — pattern
    for `Scripts/check_user_strings.sh`.
  - U.11 `SpotifyKeychainStoreTests` — pattern for app-layer test
    placement + `project.pbxproj` registration across four sections.
- D-046 / D-051 / D-052 / D-053: surrounding U.* context for
  the connector picker, error taxonomy, settings store.
- CLAUDE.md: Increment Completion Protocol, Defect Handling Protocol,
  the UX Contract section.
