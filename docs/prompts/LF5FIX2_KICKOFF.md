# Claude Code Session Prompt — Increment LF.5.fix.2: Three Post-BUG-021 Cleanups

## Context

BUG-021 (`53986fac`, 2026-05-28) fixed the Next-button MainActor deadlock in `LocalFilePlaybackProvider`. The verification session that confirmed the fix — `~/Documents/phosphene_sessions/2026-05-28T19-42-50Z/session.log` — also surfaced three discrete issues that aren't user-blockers but represent unfinished business worth cleaning up before they accumulate.

None of these are P0/P1. None require a multi-increment diagnose-first sequence. All three are small-scope, well-bounded, fixable in one focused session.

**FU-1 — Noisy no-op `provider.teardown` breadcrumbs.** The BUG-021 fix made `start()` call `stop()` before acquiring the lock so any previous-instance teardown runs lock-free. When there's no previous instance, `stop()` still snapshots all-nil refs and invokes `teardownAVFoundation`, which emits `provider.teardown ENTER` + `provider.teardown EXIT` to session.log with no work between them. Visible at the top of the verification log (line 13-14: initial start), and inside every advance's `audioRouter.start BEGIN/COMPLETE` window (lines 44-45 and 71-72). Pure cosmetic; clutters log diagnostics.

**FU-2 — Stem analyzer continues for ~1 minute after Stop.** Verification log lines 76-90+: after `Stop` fires at 19:43:29 and `provider.teardown` runs to completion, stem separations keep firing at ~5 s cadence until the log ends at 19:44:29. That's 12 separations / ~120 s of audio worth of CPU work after the user has ended the session. The `.ended` Combine observer in `VisualizerEngine.swift` calls `audioRouter.stop()` but does not call `stopStemPipeline()`. The stem analyzer's timer keeps draining whatever's left in its lookahead buffer + processing silence frames.

**FU-3 — `elapsedTrackTime` is session-monotonic, not per-track.** The `Orchestrator: wire active` log line emits an `elapsedTrackTime=` field that should reset on every `caller=trackChange`. Verification log shows it growing monotonically across track boundaries:

- 19:43:01: `elapsedTrackTime=10.9s` (first track, ~10 s in — correct)
- 19:43:13: `elapsedTrackTime=23.0s` (after Next press at ~22 s session-time — should be ~0 s if per-track)
- 19:43:26: `elapsedTrackTime=35.1s` (after Prev press at ~35 s session-time — should be ~0 s if per-track)

Latent bug: no current code consumes the field for segment-duration math, but if a future planner does, it'll be wrong on every track other than the first.

## What LF.5.fix.2 explicitly DOES

* **FU-1:** Make `LocalFilePlaybackProvider.stop()` skip the `teardownAVFoundation` call entirely when the lock-protected snapshot reveals all-nil refs. No teardown breadcrumbs land when there's nothing to tear down.
* **FU-2:** Add `stopStemPipeline()` to the `.ended` state observer in `VisualizerEngine.swift` alongside the existing `audioRouter.stop()`. Stem analyzer halts within one tick of session end.
* **FU-3:** Locate where `elapsedTrackTime` is computed (likely in `VisualizerEngine+Orchestrator.swift`'s `runOrchestratorLiveUpdate` or similar wire-active log site). Reset the track-start timestamp inside `resetStemPipeline(caller:)` when the caller is `.trackChange` so subsequent reads emit per-track-elapsed.

## What LF.5.fix.2 explicitly does NOT do

* Change AVFoundation teardown semantics. The BUG-021 fix structure stays. FU-1 only short-circuits the no-op call.
* Refactor the stem analyzer's timer-driven design. FU-2 just adds a stop call.
* Restructure the orchestrator's plan walker or scoring logic. FU-3 is a 1-line reset.
* Re-enable D-LF5-4's `buildPlan()` call for LF. That reactive-mode-only state is by design until the certified catalog grows + the planner's short-segment behaviour is verified safe (see BUG-021 outstanding work in `docs/QUALITY/KNOWN_ISSUES.md`).
* Touch any of the GAP A-H impeccable-session work.
* Address the orchestrator's rapid 3-preset startup burst at session start (`Waveform → Arachne → Aurora Veil → Ferrofluid Ocean` in 2 s). That's the reactive scheduler's normal exploration phase; tunable but out of scope here.

## Required Reading

In dependency order:

1. `CLAUDE.md` — Defect Handling Protocol § (P2/cosmetic threshold for trivial collapse — these three qualify as trivial in aggregate per the < 5-line-each shape).
2. `docs/QUALITY/KNOWN_ISSUES.md` BUG-021 entry — root-cause writeup of the deadlock fix this increment builds on.
3. `~/Documents/phosphene_sessions/2026-05-28T19-42-50Z/session.log` — the verification log that surfaced all three issues. Reference for every claim in the FU descriptions above.
4. `PhospheneEngine/Sources/Audio/LocalFilePlaybackProvider.swift` — focus on the new `stop()` + `teardownAVFoundation` post-BUG-021 (commit `53986fac`).
5. `PhospheneApp/VisualizerEngine.swift` — the `stateCancellable = mgr.$state.sink { … }` observer where `.ended` currently calls `audioRouter.stop()` but not `stopStemPipeline()`.
6. `PhospheneApp/VisualizerEngine+Stems.swift` — confirm `stopStemPipeline()` exists and is safe to call from a MainActor state observer.
7. `PhospheneApp/VisualizerEngine+Orchestrator.swift` — locate the `Orchestrator: wire active` log line and the field it reads for `elapsedTrackTime`.

## Pre-Flight Audit (do this before writing any code)

1. **Confirm FU-1's exact location.** `stop()` in `LocalFilePlaybackProvider.swift` post-BUG-021 looks like:
   ```swift
   public func stop() {
       let oldRefs: TeardownRefs = lock.withLock {
           let refs = TeardownRefs(player: playerNode, engine: engine, observer: configChangeObserver)
           playerNode = nil; engine = nil; audioFile = nil; configChangeObserver = nil
           return refs
       }
       Self.teardownAVFoundation(refs: oldRefs, diagnostic: onDiagnosticEvent)
   }
   ```
   FU-1's change: skip the call when `oldRefs.player == nil && oldRefs.engine == nil && oldRefs.observer == nil`. Either an early-return in `stop()` after the lock block OR a guard at the top of `teardownAVFoundation`. Recommend the former (keeps the helper unconditional + lets the call site decide).

2. **Confirm FU-2's wire site.** Open `PhospheneApp/VisualizerEngine.swift`. Find the `.ended` branch inside the `stateCancellable` sink (post-D-LF5-2). It currently reads:
   ```swift
   if newState == .ended {
       if #available(macOS 14.2, *), let audioRouter = self.router as? AudioInputRouter {
           audioRouter.stop()
       }
       self.isLocalFilePaused = false
   }
   ```
   FU-2's change: add `self.stopStemPipeline()` (or equivalent — verify the exact name) inside the same branch. Order matters: stem pipeline first, then audio router (so the analyzer doesn't process a final partial buffer). Or the other way around — verify by reading `stopStemPipeline`'s implementation.

3. **Confirm `stopStemPipeline()` is safe from MainActor.** Read the function in `VisualizerEngine+Stems.swift`. Verify: it doesn't spin-wait, doesn't take a lock that the audio thread holds, doesn't dispatch synchronously to a queue that's saturated. If it does any of those, the BUG-021 lesson says don't call it on MainActor — wrap in `Task.detached` instead.

4. **Locate FU-3's `elapsedTrackTime` computation.** Search `VisualizerEngine+Orchestrator.swift` for the string `elapsedTrackTime`. The log line lives near the orchestrator's analysis-queue wire (`runOrchestratorLiveUpdate` or `applyLiveUpdate`). The field is likely computed as `Date().timeIntervalSince(someStartTime)`. Find what `someStartTime` is bound to. Likely candidates:
   * Session start timestamp (set once at `startSession` / `startLocalFiles`).
   * Audio router start timestamp.
   * MIR pipeline's accumulated audio time.

   The fix is to (a) introduce a `trackChangeTimestamp` field, (b) update it on every `resetStemPipeline(caller: .trackChange)` call, (c) bind `elapsedTrackTime` to `Date().timeIntervalSince(trackChangeTimestamp ?? sessionStartTimestamp)`.

5. **Decide the trivial-collapse split.** Per CLAUDE.md Defect Protocol, "trivial P1 defects may collapse steps 1-4 into one increment" with Matt's explicit approval. These three are all sub-P1 (cosmetic / latent / minor leak). Matt already approved the collapse by asking for a single follow-up prompt. State this explicitly in the closeout: "LF.5.fix.2 collapses diagnose + fix + validate for FU-1/2/3 per Matt's 2026-05-28 sign-off."

6. **Order of operations.** FU-1 is independent (provider only). FU-2 depends on knowing `stopStemPipeline` exists (~5 s confirmation). FU-3 needs the orchestrator-file audit (longer). Suggest: FU-1 → FU-2 → FU-3, three separate commits within the increment.

Write up the audit findings (under ~150 words) before starting FU-1.

## Task Breakdown

### Task FU-1 — Skip teardown breadcrumbs when there's nothing to tear down

Single-file change in `PhospheneEngine/Sources/Audio/LocalFilePlaybackProvider.swift`. Either:

* **Option A (recommended):** in `stop()`, check the snapshot for all-nil before invoking `teardownAVFoundation`. Skip the helper call entirely.
* **Option B:** in `teardownAVFoundation`, early-return after the entry breadcrumb if all refs are nil. (Less clean — still emits one breadcrumb pair.)

Verification:
* Build clean. Lint clean.
* Run engine suite (`swift test --package-path PhospheneEngine --filter AudioInputRouterSignalStateTests`) — 11/11 pass.
* Visual check: the initial `start()` no longer emits `provider.teardown ENTER` + `provider.teardown EXIT` at session start in session.log.

Commit: `[LF.5.fix.2-FU1] LocalFilePlaybackProvider: skip teardown breadcrumbs on no-op`.

### Task FU-2 — Stop stem analyzer on session end

Verify `stopStemPipeline()` exists in `VisualizerEngine+Stems.swift` and is MainActor-safe to call. If it's not safe, wrap in `Task.detached { @MainActor in … }` or whatever the existing call sites use.

Add the call to the `.ended` branch in `VisualizerEngine.swift`'s `stateCancellable` sink. Order matters — verify the right ordering (probably stop stems before stop audio router so the analyzer doesn't process a final partial buffer; reverse if you find the analyzer prefers the router-already-stopped state).

Verification:
* Build clean. Lint clean.
* Engine suite still passes.
* Manual smoke: open a folder, press Stop, observe session.log. Expected: `provider.teardown EXIT` followed within 1-2 s by the *last* `stem separation N` line. No more separations after that.

Commit: `[LF.5.fix.2-FU2] VisualizerEngine: stop stem pipeline on .ended state`.

### Task FU-3 — Reset elapsedTrackTime on track change

Audit `VisualizerEngine+Orchestrator.swift` to find:
* The `Orchestrator: wire active` log emission site.
* What field is read for `elapsedTrackTime`.
* Where to inject a track-change timestamp reset.

Add a `private var trackChangeTimestamp: Date?` field (or similar; match existing naming conventions). Reset it inside `resetStemPipeline(caller:)` when the caller is `.trackChange`. Compute `elapsedTrackTime` from this field if non-nil, fall back to the existing session-start basis otherwise.

Verification:
* Build clean. Lint clean.
* Engine suite still passes.
* Manual smoke: open a 3-track folder, let track 1 play 20 s, press Next, observe the next `Orchestrator: wire active` log line. Expected: `elapsedTrackTime` resets close to 0 on the new track.

Commit: `[LF.5.fix.2-FU3] Orchestrator: reset elapsedTrackTime on .trackChange`.

### Task Closeout — Docs

* `docs/QUALITY/KNOWN_ISSUES.md` — Update the BUG-021 entry's outstanding-work block:
  - Strike through "Re-enable buildPlan() for LF when the certified catalog reaches ≥ 5 presets" (still open).
  - Strike through "Identify the precise MainActor hang point" (resolved in 53986fac).
  - Strike through "Stem-separation-after-stop CPU work" — note it's resolved by LF.5.fix.2-FU2.
  - Strike through "elapsedTrackTime monotonic" — note it's resolved by LF.5.fix.2-FU3.
* `docs/RELEASE_NOTES_DEV.md` — `[dev-YYYY-MM-DD-X] LF.5.fix.2 — three post-BUG-021 cleanups` entry summarizing FU-1/2/3.
* `docs/ENGINEERING_PLAN.md` — LF.5.fix.2 entry above LF.5.fix.
* Likely no `docs/DECISIONS.md` entry — these are bug fixes, not architectural decisions.

Commit: `[LF.5.fix.2] docs: KNOWN_ISSUES strike-throughs + RELEASE_NOTES + ENGINEERING_PLAN`.

## Critical Invariants

* All existing engine tests stay green. Pass count ≥ 1358.
* All existing app tests stay green. Pass count ≥ 305.
* SwiftLint `--strict` clean on every touched file.
* `Scripts/check_user_strings.sh` exit 0.
* `Scripts/check_sample_rate_literals.sh` exit 0.
* No new app-layer source files (all three FUs land in existing files).
* No pbxproj surgery needed.
* BUG-021 fix structure stays intact. FU-1 only short-circuits the no-op path; the lock-free teardown semantics are unchanged.

## Verification Commands

```sh
# After each FU commit
swift test --package-path PhospheneEngine --filter "AudioInputRouterSignalStateTests|SessionManagerLocalFile" 2>&1 | tail -5
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1 | tail -3
swiftlint lint --strict --config .swiftlint.yml <touched files>
Scripts/check_user_strings.sh

# Full regression at closeout
swift test --package-path PhospheneEngine 2>&1 | tail -5
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1 | tail -3

# Manual smoke (Matt)
# 1. Launch Debug build, open Local Folder, 2-track fixture.
# 2. Verify session.log: no provider.teardown breadcrumbs at session start.
# 3. Press Next. Verify advance breadcrumbs land within < 200 ms.
# 4. After advance, observe orchestrator wire log: elapsedTrackTime resets near 0.
# 5. Press Stop. Verify last stem separation line within 1-2 s of provider.teardown EXIT.
```

## Commit Cadence

1. `[LF.5.fix.2-FU1] LocalFilePlaybackProvider: skip teardown breadcrumbs on no-op`
2. `[LF.5.fix.2-FU2] VisualizerEngine: stop stem pipeline on .ended state`
3. `[LF.5.fix.2-FU3] Orchestrator: reset elapsedTrackTime on .trackChange`
4. `[LF.5.fix.2] docs: KNOWN_ISSUES strike-throughs + RELEASE_NOTES + ENGINEERING_PLAN`

Prefer this order (independent → dependent). If FU-3's audit reveals the field is named differently or computed somewhere unexpected, surface the gap to Matt before guessing.

## Overall Done-When Gate

* `git log --oneline -5` shows the four LF.5.fix.2 commits.
* Engine + app test suites green; pass counts at-or-above baseline.
* SwiftLint + strings gates clean.
* Manual smoke (Matt-driven) confirms all three behaviours:
  - No noisy teardown breadcrumbs at session start.
  - Stem separations stop within 1-2 s of `Stop`.
  - `elapsedTrackTime` resets near 0 on every track change.
* KNOWN_ISSUES BUG-021 entry updated with strike-throughs for the two FUs that close it out.
* RELEASE_NOTES_DEV.md has the LF.5.fix.2 entry.
* Closeout report per CLAUDE.md "Increment Completion Protocol."

## Out of Scope (Do Not Do)

* Re-enable D-LF5-4's `buildPlan()` for LF. Still locked until certified catalog ≥ 5 + plan-walker verified safe under short segments.
* Refactor the stem analyzer's timer-driven architecture. FU-2 is a single stop call, not a structural change.
* Refactor the orchestrator's reactive scheduler. FU-3 is a single timestamp reset, not a behavior change.
* New UI work. The impeccable-session GAP A-H surface is finalized for this round.
* UI testing infrastructure (UI.1 kickoff at `docs/prompts/UI1_KICKOFF.md`) — still its own increment.
* Album-art display, drag-to-reorder, gapless segue, smart-playlists — all still LF.6+.

## Stuck-State Guidance

* **`stopStemPipeline()` doesn't exist or is private.** Search neighbouring engine files for the actual name (`stopStemAnalysis`, `tearDownStemPipeline`, etc.). If the function genuinely doesn't exist, FU-2 grows into a new method that cancels the stem timer + clears the lookahead buffer. Surface to Matt if this turns out non-trivial — could be deferred without losing FU-1/FU-3.

* **`elapsedTrackTime` is consumed by code, not just logged.** If the FU-3 audit reveals a consumer (`SessionPlanner.plan(...)`, `runOrchestratorLiveUpdate`, etc.), the per-track-reset semantic might break that consumer's existing expectations. Surface to Matt before landing — could need a separate `elapsedSessionTime` field for the consumers that genuinely want session-monotonic time.

* **The `.ended` observer interacts badly with the stem analyzer stop.** If `stopStemPipeline` synchronously waits for the stem worker thread, calling it from the MainActor state observer could starve the worker. BUG-021's lesson: don't call synchronous teardown from MainActor without verifying the worker thread doesn't need MainActor to release. If unsure, wrap in `Task.detached`.

* **Test/prod parity gap.** If a test stubs out the stem pipeline or the orchestrator timestamp logic, ensure your fix exercises the live path too. FU-2 in particular touches the engine init's Combine wiring which most tests bypass.

* **All three FUs land green but Matt can't reproduce the fix.** Verify on the Debug build at `~/Library/Developer/Xcode/DerivedData/PhospheneApp-cngkdwcjwuuqgbfrcioserxgammt/Build/Products/Debug/PhospheneApp.app`. Re-run `xcodebuild build` if uncertain.
