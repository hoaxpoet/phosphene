# Claude Code Session Prompt — Increment UI.1: SwiftUI Snapshot + Interaction Test Infrastructure

## Context

Phosphene's testing strategy has covered engine internals, view-model bindings, and audio/MIR pipelines exhaustively (~1358 engine tests, ~305 app-layer tests at 2026-05-28). It has **not** covered SwiftUI rendering, AppKit menu items, drag-and-drop, hover-reveal, or any behaviour that requires actually-rendered views or user input. Every `PhospheneAppTests/*.swift` file is a `Swift Testing` / `XCTest` unit test against a view model or service — none traverse a SwiftUI view hierarchy, none render a view to PNG, none simulate a button tap.

This gap surfaced concretely during LF.5 + LF.5.fix (commits `30e8a553..f45b7db7`, 2026-05-27 → 2026-05-28). Three classes of defect shipped that would have been caught by basic UI tests:

1. **NSOpenPanel UTI filter rejected every audio fixture as disabled** (LF.5 menu picker; fix commit `e52e31eb`). Picker was sign-off-by-design at the LF.4 AskUserQuestion gate but never exercised live; the first user-facing smoke caught it.
2. **`handleLocalFileReady` skipped `buildPlan()` for LF.5 sessions** (BUG-LF5-4; fix commit `46a9f1c2`). `livePlannedSession` stayed nil for every LF.5 session → orchestrator ran reactive instead of planned mode. A snapshot test asserting "PlaybackChromeView shows the planner's preset" would have caught it; an integration test asserting "the chrome view model sees a non-nil livePlannedSession on .ready" definitely would have.
3. **Transport bar `isLocalFilePaused` glyph + click dispatch** (D-LF5-3). Currently only verifiable by Matt clicking buttons by hand.

UI.1 stands up the missing infrastructure: SwiftUI snapshot tests via `swift-snapshot-testing` + interaction tests via `ViewInspector`. Both libraries run in the existing `PhospheneAppTests` target — no new target needed, no XCUITest flake tax. XCUITest is **deferred** (its own infrastructure increment if/when we need real menu-item / drag-and-drop / file-association testing).

After UI.1 lands, the next increment is an `impeccable`-skill design pass on the file-based user flows (file picker, folder picker, Recents submenu, transport bar, drag-and-drop affordance, error alerts). Sequencing matters: ship snapshot infrastructure first so that design pass can land alongside snapshot tests proving the new visuals don't regress.

See `docs/diagnostics/LF5_FIX_STRUCTURAL_VERIFICATION_2026-05-28.md` for the gap that motivated this increment.

## What UI.1 explicitly DOES

* **Add `swift-snapshot-testing`** ([point-free](https://github.com/pointfreeco/swift-snapshot-testing)) as an SPM dependency on the `PhospheneAppTests` target. PNG snapshot strategy; per-test baselines committed to the repo under `PhospheneAppTests/__Snapshots__/`.
* **Add `ViewInspector`** ([nalexn/ViewInspector](https://github.com/nalexn/ViewInspector)) as an SPM dependency on the same target. Used for traversing rendered SwiftUI view hierarchies + simulating button taps so action dispatch can be asserted.
* **Snapshot test coverage** for ~5 representative views and ~12 view states. Initial set:
  - `PlaybackChromeView` — 4 states: (a) streaming-playing, (b) streaming with listening-badge visible, (c) LF-playing with transport bar visible, (d) LF-paused with transport bar's play glyph visible.
  - `LocalFileTransportBar` — 2 states: paused, playing.
  - `IdleView` — 1 state (post-permission, before any session).
  - `EndedView` — 1 state (with track count + duration).
  - `PreparationProgressView` — 3 states: all-queued, mid-progress (3 of 8 ready), all-ready-with-Start-now-CTA.
  - Optional: `PermissionOnboardingView` — 1 state (pre-permission).
* **Interaction tests** via `ViewInspector` for action dispatch surfaces that aren't otherwise covered:
  - `LocalFileTransportBar`: each of 4 buttons (Stop / Prev / Play-Pause / Next) fires its callback when tapped programmatically.
  - `PlaybackChromeView`: the End-Session button fires its callback; the LF transport bar's callbacks pass through to engine when the chrome's `isLocalFileSession=true`.
  - `EndedView`: "Start new session" + "Open sessions folder" buttons fire their callbacks.
  - Optional: any Recents-submenu item that's accessible via the SwiftUI hierarchy.
* **CLAUDE.md discipline rule.** Add to the Code Style or a new Test Discipline section: "New SwiftUI views ship with a snapshot test + an interaction test in PhospheneAppTests. PRs that add or materially modify a view in `PhospheneApp/Views/` without snapshot coverage are blocked at lint time."
* **`docs/TESTING.md`** — new short doc covering: how to re-record a snapshot baseline (env var convention), how to interpret PNG diffs, how to add a new snapshot test, how to add a new interaction test, when to use which.
* **`Scripts/check_ui_test_coverage.sh`** (lint-time gate). Greps `PhospheneApp/Views/` for SwiftUI views (`struct ... : View`) and asserts each has at least one `__Snapshots__` baseline OR an explicit allowlist entry. Failing the script blocks commit.

## What UI.1 explicitly does NOT do

* **XCUITest target.** macOS XCUITest is flakier than iOS (window focus, screen capture permission interactions, fullscreen). Deferred until the snapshot+interaction layer has settled. File a follow-up increment if there's demand for real-input testing of menus / drag-drop / file-association.
* **`open -a Phosphene file.m4a` testing.** Requires LaunchServices + XCUITest. Same defer.
* **Real-NSEvent hover / click tests.** Snapshot tests render views in a synthetic context; real hover behaviour (window focus, NSApp.keyWindow) is not exercised. Same defer.
* **Drag-and-drop pasteboard tests.** Requires AppKit drag pasteboard simulation; same defer.
* **Visual regression CI pipeline.** Snapshot tests run in the existing `xcodebuild test` lane; no separate CI change at UI.1 scope. If snapshot baselines drift on different machines (GPU driver, system font version), tighten precision in a follow-up.
* **Snapshot variants per localization.** English-only baseline at UI.1 scope. Localization tests are a separate concern.
* **Snapshot variants per appearance mode.** Phosphene is always-dark; no light-mode chrome exists.
* **Snapshot variants per accessibility category.** Dynamic Type + Reduce-Motion variants are valuable but expand the baseline count 3-5×. Pick a single "default" mode (no reduce-motion, standard Dynamic Type) for UI.1; add variant coverage in a follow-up if specific bugs surface.
* **Conversion of existing view-model tests to interaction tests.** UI.1 is additive only — every existing `*ViewModelTests.swift` file stays. Interaction tests cover what view-model tests can't (rendered button → callback dispatch).
* **100% view coverage.** Initial baseline covers 5 representative views. Coverage expands as part of normal preset/feature work going forward.
* **PR-comment integration for visual diffs.** Some snapshot libraries integrate with GitHub PR comments to show PNG diffs inline. Out of scope here; the failing test surfaces the diff path in the test output.
* **Snapshot tests for engine-side `Renderer` output.** The Metal render pipeline is verified by `PresetRegressionTests` (golden hash) at the engine layer; UI.1 covers only SwiftUI chrome.

## Required Reading

Before any code, read in this order:

1. `CLAUDE.md` — testing discipline, SwiftLint rules, the "Code Style" + "What NOT To Do" sections. Pay attention to: `function_body_length` warnings (60 lines), `file_length` warnings (400 lines), `force_unwrapping` error level, the externalised-strings rule.
2. `docs/diagnostics/LF5_FIX_STRUCTURAL_VERIFICATION_2026-05-28.md` — the gap that motivated this increment.
3. `PhospheneAppTests/PlaybackChromeViewModelTests.swift` — current view-model test pattern (Swift Testing-based; how publishers are injected; how `@MainActor` is handled).
4. `PhospheneAppTests/EndSessionConfirmViewModelTests.swift` — another view-model test for comparison.
5. `PhospheneApp/Views/Playback/PlaybackChromeView.swift` — the most state-rich view (4-region ZStack, LF transport carve-out). Will be the most test-covered.
6. `PhospheneApp/Views/Playback/LocalFileTransportBar.swift` — new in LF.5.fix; simplest view to write tests against first.
7. [swift-snapshot-testing README](https://github.com/pointfreeco/swift-snapshot-testing) — strategy API, recording mode, precision tolerance.
8. [ViewInspector README](https://github.com/nalexn/ViewInspector) — Swift 6 concurrency support, button tap simulation, environment injection.

Then audit:

* `PhospheneApp.xcodeproj/project.pbxproj` — find the `XCRemoteSwiftPackageReference` and `XCSwiftPackageProductDependency` entries for any existing SPM deps (likely none on the app target — engine uses SPM via `PhospheneEngine/Package.swift`, but the app target consumes them via project file references). Verify the pattern before adding new ones.
* `PhospheneApp/Views/` — count distinct SwiftUI view files. Cross-reference against the UI.1 initial snapshot set to confirm coverage gaps are surfaceable.
* `PhospheneAppTests/` — confirm the convention of one test file per system-under-test (`AccessibilityStateTests.swift`, `EndedViewTests.swift`, etc.). UI.1 follows the same convention: per-view snapshot file under `PhospheneAppTests/Snapshots/`, per-view interaction file under `PhospheneAppTests/Interactions/`.

## Pre-Flight Audit (do this before writing any code)

1. **SPM dependency location.** The PhospheneApp Xcode project doesn't currently consume any SPM packages directly; PhospheneEngine consumes its own via `Package.swift`. Two options:
   * **A: Add `swift-snapshot-testing` + `ViewInspector` to `PhospheneApp.xcodeproj` via Xcode's Package Dependencies UI.** This writes the `XCRemoteSwiftPackageReference` + `XCSwiftPackageProductDependency` entries automatically. Cleanest path; requires Xcode interaction (not pure CLI).
   * **B: Add them to `PhospheneEngine/Package.swift` as test-only dependencies and re-export via a test-helper target.** Avoids pbxproj surgery but creates an odd coupling (engine package owns app-test deps).
   * Recommendation: **Option A**, scripted via direct pbxproj editing if you're comfortable with the file format; otherwise document the manual Xcode steps in the closeout.

2. **Snapshot library variant.** `swift-snapshot-testing` has multiple strategies:
   * `.image` — PNG snapshot, default for SwiftUI.
   * `.image(perceptualPrecision:)` — tolerates minor pixel differences; useful for cross-machine reproducibility.
   * `.recursiveDescription` — text description of the view hierarchy; brittle to SwiftUI internal changes.
   * Recommendation: `.image(perceptualPrecision: 0.98)` — PNG snapshots with a small tolerance for GPU/font driver variation. Tune up to 0.99 if false positives appear; tune down to 0.95 if real regressions slip through.

3. **Snapshot baseline storage + commit policy.**
   * Default location: `__Snapshots__/<TestSuiteName>/<testName>.<size>.png` under the test file's directory.
   * Commit baselines into the repo so CI / Matt's machine / Claude's worktree all share the same source-of-truth.
   * Expected total size: ~10-30 PNGs at ~10-50 KB each = ~500 KB to 1.5 MB. Acceptable; well below the `.f32` stem files already in the repo.

4. **Re-record mode discoverability.** Snapshot libraries support a "record" mode that overwrites baselines instead of comparing. The library reads either an env var or a per-call parameter. Document the env var convention (`SNAPSHOT_RECORD=1` is conventional) in `docs/TESTING.md`.

5. **View construction in tests.** Many Phosphene views require complex dependency injection (publishers, environment objects, etc.). Two patterns:
   * **A: Build a "preview" factory per view** that returns the view configured for a specific state. Mirror SwiftUI Preview blocks.
   * **B: Inline construction per snapshot test.** Each test builds the view with the right publishers / state inline.
   * Recommendation: **Option A** for views with complex deps (PlaybackChromeView, PreparationProgressView); **Option B** for simple views (LocalFileTransportBar, EndedView).

6. **`@MainActor` in tests.** Most SwiftUI rendering must happen on the main actor. Confirm the snapshot library handles this correctly (the modern `swift-snapshot-testing` does). If issues surface, wrap each test in `@MainActor` or use the library's `@MainActor`-friendly assertion APIs.

7. **CI / `xcodebuild test` integration.** Snapshot tests run in the existing `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test` lane. No CI changes needed at UI.1 scope. Verify in the closeout that the existing test commands still pass with UI.1 baselines committed.

8. **CLAUDE.md discipline-rule wording.** The rule should be enforceable, not aspirational. Concrete proposal:

   > **Every SwiftUI view in `PhospheneApp/Views/` ships with at least one snapshot test under `PhospheneAppTests/Snapshots/<View>Snapshots.swift`.** `Scripts/check_ui_test_coverage.sh` enforces at lint time — every `struct ... : View` declaration in `PhospheneApp/Views/` must have a matching snapshot file or an explicit allowlist entry (`UI_TEST_ALLOWLIST.txt` with a justification comment per entry, kept short). PRs that add or materially modify a view without coverage fail the gate.

   Soft-launch the script: warn-only for the first pass while baselines are still being established. Hard-fail mode lands once the initial 5-view baseline is in.

9. **Initial test scope vs eventual coverage.** UI.1 ships 5 views with snapshot coverage + 3 views with interaction tests. Eventual coverage target is every view in `PhospheneApp/Views/`. The script's allowlist starts with every existing view NOT in the initial set, and entries get removed as future increments add coverage. Document this convention.

10. **pbxproj UUID prefix for new test files.** Per the LF.5 / LF.4 convention, test target UUIDs use the L-prefix (`L10043`+ at last allocation). Allocate `L10044`-`L10050` (or wherever the current next slot is) for new snapshot + interaction test files. Verify by `grep -oE 'L1[0-9]+' PhospheneApp.xcodeproj/project.pbxproj | sort -u | tail -5` before allocating.

Write up the audit findings (under ~250 words) before starting Task 1.

## Task Breakdown

### Task 1 — SPM dependencies + project integration

Add `swift-snapshot-testing` (point-free, version ≥ 1.18.0) and `ViewInspector` (nalexn, Swift 6 compatible release) to `PhospheneApp.xcodeproj`'s package dependencies, linked to the `PhospheneAppTests` target. Verify `swift package resolve` (or `xcodebuild -resolvePackageDependencies`) produces a clean `Package.resolved`. Commit `Package.resolved`.

Done when: `import SnapshotTesting` and `import ViewInspector` compile in a stub test file inside `PhospheneAppTests/`.

### Task 2 — Snapshot test infrastructure

Create `PhospheneAppTests/Snapshots/PhospheneSnapshotTests.swift` with shared helpers:
- A `MainActor`-safe `snapshotAssert(view:size:precision:record:)` helper that wraps `assertSnapshot(...)` with the project's chosen precision (audit Q2).
- A default canvas size for chrome views (likely 1280×800 — matches the app's typical window size).
- A `record` toggle that reads `SNAPSHOT_RECORD=1` from the environment.
- A document-comment block at top describing the conventions and pointing at `docs/TESTING.md`.

Done when: a sample snapshot test inside `PhospheneSnapshotTests.swift` records and asserts a trivial view (e.g. `Text("hello").frame(width: 100, height: 50)`) — proves the toolchain works.

### Task 3 — Snapshot tests for the LF.5.fix views (highest-leverage coverage)

These are the views the LF.5.fix work touched — proving snapshot coverage works on them first ensures the infrastructure addresses the specific gap that motivated UI.1.

* `PhospheneAppTests/Snapshots/LocalFileTransportBarSnapshots.swift` — 2 states: `isPaused=false` (pause glyph), `isPaused=true` (play glyph).
* `PhospheneAppTests/Snapshots/PlaybackChromeViewSnapshots.swift` — 4 states:
  - Streaming session, audio active.
  - Streaming session, listening-badge visible.
  - LF session, playing, transport bar at bottom-center.
  - LF session, paused, transport bar shows play glyph.

Done when: 6 PNG baselines exist under `__Snapshots__/`; `swift test --filter SnapshotTests` (or the xcodebuild equivalent) passes.

### Task 4 — Snapshot tests for the remaining initial set

* `PhospheneAppTests/Snapshots/IdleViewSnapshots.swift` — 1 state.
* `PhospheneAppTests/Snapshots/EndedViewSnapshots.swift` — 1 state.
* `PhospheneAppTests/Snapshots/PreparationProgressViewSnapshots.swift` — 3 states: all-queued, mid-progress (3 of 8 ready), all-ready-with-CTA.
* Optional stretch: `PermissionOnboardingViewSnapshots.swift` — 1 state.

Done when: ~6 more PNG baselines exist; full snapshot suite passes.

### Task 5 — Interaction tests via ViewInspector

Where snapshot tests verify the right visuals appear for a given state, interaction tests verify the right callbacks fire when the right element is tapped.

* `PhospheneAppTests/Interactions/LocalFileTransportBarInteractions.swift` — 4 tests: each of the 4 buttons invokes its respective callback when programmatically tapped.
* `PhospheneAppTests/Interactions/PlaybackChromeInteractions.swift` — End Session button fires; LF transport callbacks dispatch through chrome to the engine-side callbacks.
* `PhospheneAppTests/Interactions/EndedViewInteractions.swift` — "Start new session" + "Open sessions folder" buttons fire.

Done when: ~8-10 interaction tests pass; each asserts on a per-callback boolean or counter that was set by the simulated tap.

### Task 6 — Coverage-enforcement script + CLAUDE.md rule

* `Scripts/check_ui_test_coverage.sh` — greps `PhospheneApp/Views/` for `struct ... : View`, cross-references against `PhospheneAppTests/Snapshots/`. Soft-launch (warn-only) initially; documented to hard-fail once the baseline set is in.
* `PhospheneAppTests/UI_TEST_ALLOWLIST.txt` — explicit allowlist with one-line justification per entry. Populate with every view NOT covered in the UI.1 initial set; entries get removed as future increments add coverage.
* CLAUDE.md update — new "UI Test Discipline" subsection under "Code Style" with the rule wording from audit Q8.

Done when: the script runs clean (warn mode) against the current source tree.

### Task 7 — Documentation

* `docs/TESTING.md` (new) — UI testing handbook:
  - How to write a snapshot test (pattern + example).
  - How to re-record a baseline (`SNAPSHOT_RECORD=1 xcodebuild ...`).
  - How to interpret PNG diffs.
  - How to write an interaction test.
  - When to use snapshot vs interaction vs view-model test.
  - The coverage rule + allowlist conventions.
* `docs/DECISIONS.md` — new D-entry for UI.1 (snapshot + ViewInspector choice + soft-launch enforcement).
* `docs/ENGINEERING_PLAN.md` — UI.1 entry above the most-recent increment.
* `docs/RELEASE_NOTES_DEV.md` — `[dev-YYYY-MM-DD-X]` entry.
* `docs/QUALITY/KNOWN_ISSUES.md` — update BUG-LF5-2 and BUG-LF5-3 entries to note that the gap they revealed is now covered (or partially covered) by UI.1 infrastructure.

### Task 8 — Closeout

Run the full Phosphene regression suite + the new UI tests + the localized-strings gate + the new UI-coverage script. Verify nothing previously green is now red. Capture latency-of-test-run numbers in the closeout (snapshot tests add ~1-3 s per baseline; the suite should still complete in under a minute).

## Critical Invariants

* All existing engine tests stay green. Pass count ≥ 1358 (LF.5 + LF.5.fix baseline).
* All existing PhospheneApp tests stay green. Pass count ≥ 305.
* SwiftLint `--strict` stays clean on every touched file.
* `Scripts/check_user_strings.sh` exit 0.
* `Scripts/check_sample_rate_literals.sh` exit 0.
* `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' -configuration Release build` exit 0.
* `Package.resolved` is committed.
* Snapshot baselines are committed (PNG files under `__Snapshots__/`).
* No code changes outside `PhospheneAppTests/`, the project file, and documentation. Views and view models should not need modification for UI.1.
* The coverage script runs in warn-only mode at UI.1 commit; hard-fail mode is a follow-up.
* New SwiftUI views in PhospheneApp/Views/ (if any are added concurrently with UI.1) have at least snapshot coverage by UI.1 closeout.
* `default.profraw` and other coverage artifacts stay out of commits.
* PBXProj UUID allocations from `L10044+` (verify before commit); the file uses the 4-section pattern (`PBXBuildFile`, `PBXFileReference`, `PBXGroup`, `PBXSourcesBuildPhase`) for new test files.

## Verification Commands

```sh
# Resolve packages (verifies SPM deps load cleanly)
xcodebuild -resolvePackageDependencies -project PhospheneApp.xcodeproj

# Full app test suite (snapshot + interaction + existing)
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test 2>&1 | tail -20

# Subset: just the new snapshot tests
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test \
  -only-testing:PhospheneAppTests/LocalFileTransportBarSnapshots \
  -only-testing:PhospheneAppTests/PlaybackChromeViewSnapshots

# Subset: just the new interaction tests
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test \
  -only-testing:PhospheneAppTests/LocalFileTransportBarInteractions

# Engine regression
swift test --package-path PhospheneEngine 2>&1 | tail -5

# Coverage script
Scripts/check_ui_test_coverage.sh ; echo "EXIT=$?"

# Strings gate
Scripts/check_user_strings.sh ; echo "EXIT=$?"

# Sample-rate gate
Scripts/check_sample_rate_literals.sh ; echo "EXIT=$?"

# Release build
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' -configuration Release build 2>&1 | tail -3

# Lint touched files
swiftlint lint --strict --config .swiftlint.yml \
  PhospheneAppTests/Snapshots/PhospheneSnapshotTests.swift \
  PhospheneAppTests/Snapshots/LocalFileTransportBarSnapshots.swift \
  PhospheneAppTests/Snapshots/PlaybackChromeViewSnapshots.swift \
  PhospheneAppTests/Snapshots/IdleViewSnapshots.swift \
  PhospheneAppTests/Snapshots/EndedViewSnapshots.swift \
  PhospheneAppTests/Snapshots/PreparationProgressViewSnapshots.swift \
  PhospheneAppTests/Interactions/LocalFileTransportBarInteractions.swift \
  PhospheneAppTests/Interactions/PlaybackChromeInteractions.swift \
  PhospheneAppTests/Interactions/EndedViewInteractions.swift

# Baseline existence sanity check
find PhospheneAppTests/Snapshots/__Snapshots__ -name "*.png" | wc -l
# expect ≥ 12 for the initial UI.1 set
```

## Commit Cadence

1. `[UI.1] deps: swift-snapshot-testing + ViewInspector via SPM` — Package.resolved + project file + smoke import test file.
2. `[UI.1] infrastructure: PhospheneSnapshotTests base class + snapshot helper`
3. `[UI.1] snapshots: LocalFileTransportBar (2 states)`
4. `[UI.1] snapshots: PlaybackChromeView (4 states)`
5. `[UI.1] snapshots: IdleView / EndedView / PreparationProgressView (5 states)`
6. `[UI.1] interaction: LocalFileTransportBar button dispatch (4 tests)`
7. `[UI.1] interaction: PlaybackChrome + EndedView button dispatch`
8. `[UI.1] scripts: check_ui_test_coverage.sh + UI_TEST_ALLOWLIST.txt`
9. `[UI.1] docs: TESTING.md + DECISIONS D-entry + ENGINEERING_PLAN + RELEASE_NOTES + KNOWN_ISSUES + CLAUDE.md rule`

Prefer fine-grained commits. The CSP.* / LF.* / PERF.* parallel workstreams are likely to keep landing commits on `main`; coordinate via `git pull --rebase` between commits.

## Documentation Updates

* `docs/TESTING.md` — new handbook (Task 7).
* `docs/DECISIONS.md` — new D-entry (next number is whatever `grep '## D-0' docs/DECISIONS.md | tail -1` shows + 1).
* `docs/ENGINEERING_PLAN.md` — UI.1 entry above the most-recent increment.
* `docs/RELEASE_NOTES_DEV.md` — `[dev-YYYY-MM-DD-X]` entry.
* `docs/QUALITY/KNOWN_ISSUES.md` — append "UI.1 closes gap" notes to BUG-LF5-2 + BUG-LF5-3 (the LF.5.fix entries whose verification was deferred for lack of UI testing infrastructure).
* `CLAUDE.md` — new "UI Test Discipline" subsection.

## Overall Done-When Gate

* `xcodebuild test` runs the full app suite including ≥ 12 snapshot tests + ≥ 8 interaction tests, all green.
* `find PhospheneAppTests/Snapshots/__Snapshots__ -name "*.png" | wc -l` ≥ 12.
* `Scripts/check_ui_test_coverage.sh` exit 0 (warn-only mode acceptable for this increment).
* `Package.resolved` is committed with `swift-snapshot-testing` + `ViewInspector` versions pinned.
* `docs/TESTING.md` exists and reads as a useful handbook for adding a new snapshot test.
* CLAUDE.md has the UI test discipline rule.
* The LF.5.fix gap that motivated this increment has at least one snapshot test that would catch a regression of the same defect class:
  - At least one snapshot test asserts `PlaybackChromeView` shows the transport bar with the right glyph for `isLocalFilePaused=true/false` — would catch a future "transport bar doesn't render" or "glyph is wrong" regression.
  - At least one interaction test asserts a `LocalFileTransportBar` button click invokes the right engine method — would catch a future "Stop button doesn't actually stop" regression.
* Closeout report produced per CLAUDE.md "Increment Completion Protocol."

## Out of Scope (Do Not Do)

* XCUITest target.
* Real-input testing (NSEvent, NSAccessibility automation, window focus).
* File-association testing via `open -a Phosphene file.m4a`.
* Drag-and-drop pasteboard simulation tests.
* Visual regression CI integration.
* Per-locale snapshot variants.
* Per-appearance-mode snapshot variants (Phosphene is always dark).
* Per-Dynamic-Type-category snapshot variants.
* Conversion of existing view-model tests to interaction tests.
* 100% view coverage in this increment; 5 representative views is the starting set.
* Snapshot tests for the engine-side Renderer or any `.metal` shader.
* PR-comment integration showing PNG diffs inline.
* Soft-launch → hard-fail switch of the coverage script (do that in a follow-up after the allowlist drains).

## Stuck-State Guidance

* **ViewInspector + Swift 6 strict concurrency.** Some older ViewInspector releases use `@unchecked Sendable` patterns that the strict-concurrency compiler flags as warnings/errors. Pin to a release that explicitly supports Swift 6 (check the changelog / GitHub Releases page). If no such release exists yet, the fallback is to relax `SWIFT_STRICT_CONCURRENCY = complete` in `PhospheneAppTests` target's build settings only — but flag this as a temporary measure and add a follow-up task to drop the relaxation once a Swift-6-ready release is available.
* **Snapshot precision tolerance.** PNG diffs can fail spuriously across machines (different GPU drivers, system font versions, anti-aliasing). Start at `perceptualPrecision: 0.98`; tune up if false positives outnumber real failures, down if a real visual regression slips through.
* **macOS-specific SwiftUI rendering.** Some views render differently when not in a real NSWindow context (e.g. `NSAppearance`, `NSAnimationContext`). Snapshot library's default `hostingController(view:)` wrapper handles most cases but may need explicit `NSColor.controlBackgroundColor` overrides. If a snapshot looks wrong in test but right in the live app, the absence-of-window context is usually the cause.
* **pbxproj XCRemoteSwiftPackageReference syntax.** Hand-editing the pbxproj for SPM deps is fiddly. If you can't get it right by hand, open the project in Xcode, add the deps via the UI, save, and commit the resulting file. Document the manual step in the closeout.
* **`ViewInspector.inspect()` traversal errors.** ViewInspector's view-tree introspection is brittle to SwiftUI internals; if `find()` calls fail across SwiftUI versions, anchor on accessibility identifiers rather than structural paths.
* **Baseline drift on Matt's machine vs Claude's worktree.** If a snapshot test passes when Claude runs it but fails for Matt, the cause is usually GPU driver / font-version variation. Increase the precision tolerance OR commit a per-machine baseline override (last resort; messy).
* **Coverage script over-flags.** If `Scripts/check_ui_test_coverage.sh` warns about views that genuinely don't need snapshot coverage (e.g. a one-off composition that's only ever embedded inside another tested view), add them to `UI_TEST_ALLOWLIST.txt` with a justification.
* **Test runtime explodes.** If snapshot tests add > 30 s to the suite, profile which baselines are slow (probably the largest canvas sizes) and either shrink them or split into a `--filter SnapshotTests`-gated lane.
* **Conflict with PERF.* / CSP.* parallel work on main.** Rebase frequently. The new test files are isolated from any other work, so conflicts should be limited to pbxproj (where parallel L-prefix UUID allocations could collide) and possibly Package.resolved.
