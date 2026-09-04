# Session prompt — DS.3

## Increment DS.3 — one severity vocabulary, four interruption levels

**Type:** UX. Third increment of **Phase DS — Design system adoption (First Opening)**. No engine, no shader, no `.metal`, no preset.

**Objective.** After this session the app has a single definition of what "warning" and "danger" look like, and four status placements that share it while keeping their distinct interruption levels. `StatusTone` maps every severity the app can produce onto token roles and SF Symbols. `RecoveryScreen` replaces the near-identical pair `FullScreenErrorView` (which has no consumers at all) and `PreparationFailureView`. `NoticeBanner`, `InlineNotice` and `PerformanceToast` consume the same tone vocabulary in their own placements. Three conflicting severity-to-colour maps become one. State ownership is untouched: `PreparationErrorViewModel` still owns `presentationState`, `LocalFileErrorStore` still owns its auto-clear task, `ToastManager` still owns the queue.

This is step 3 of the seven-step migration order in `PHOSPHENE-COMPONENT-CENSUS.md` §Migration order. It is the largest DS increment before the preparation rebuild, and it is the one that decides what degraded operation looks like everywhere.

## Settled decisions carried into this increment

**Uzume is always dark (Matt, 2026-09-01; DS.1).** Every tone maps to the dark-theme status roles only. No appearance branch.

**Tokens are the only source of presentation values (DS.1).** New components are tokenized from birth; the DS.1 grep gate stays green throughout.

**Components the app authors live in `UzumeApp/Views/Components/` (DS.2).** `UzumeApp/DesignSystem/` holds only the vendored token source and its app extension.

## Skill invocations

- `closeout` at the end (mandatory). §2 is the verbatim `Scripts/closeout_evidence.sh` block.
- **Not** `preset-session`, **not** `shader-authoring`.
- **Not** `defect-handling` — the two dead affordances found in task 8 are recorded, not fixed.

## Read-first file list

Design system (sibling `uzume-site` checkout — read-only, see Do-NOT):

1. `../uzume-site/DesignSystem/COMPONENTS.md` — §Native product component extraction › Status placements (why four components rather than one), §Web patterns › Trust explanation (the rule that status colour may support but never replace text or icon), §Release contract.
2. `../uzume-site/tokens.css` — the `--color-status-*` triples. **Read these before writing any tone.** In dark, warning is bright yellow `#ffd60a` on a deep field `#282400` with a `#8c7600` border. The app's current banner is the inverse: an amber fill with black text. Adopting the tokens flips it, and that flip is the increment's largest visible change.
3. `../uzume-site/docs/design/PHOSPHENE-COMPONENT-CENSUS.md` — §Reusable product components (the five status rows), §Missing responsibilities › shared status semantics, §Migration order step 3.

App (the files being changed):

4. `UzumeEngine/Sources/Shared/UserFacingError+Presentation.swift` — `ErrorSeverity` (info, warning, degradation, fatal) and the `severity` mapping. This enum is the engine's vocabulary and **does not change**; `StatusTone` maps *from* it.
5. `UzumeApp/Models/UzumeToast.swift` — `UzumeToast.Severity` (info, warning, degradation — no fatal), a second and narrower vocabulary.
6. `UzumeApp/Views/FullScreenErrorView.swift` and `UzumeApp/Views/Preparation/PreparationFailureView.swift` — read them side by side. `body`, `icon`, `textBlock`, `actions`, `headline`, `severityIcon` and `severityColor` are duplicated almost verbatim; the only real difference is that one takes CTA keys off the error and the other hard-codes two preparation actions.
7. `UzumeApp/Views/Preparation/TopBannerView.swift` — the 44pt strip. Note it takes no severity at all: every banner is amber regardless of the error.
8. `UzumeApp/LocalFileErrorStore.swift` — the store **and**, from line 94, the `LocalFileErrorBanner` view that lives inside it and fills its pip from `DashboardTokens.Color.coral`.
9. `UzumeApp/Views/Playback/ToastView.swift` and `ToastContainerView.swift` — the third colour map, the max-three stack, the transition, and the VoiceOver announcement on insert.
10. `UzumeApp/Views/Preparation/PreparationProgressView.swift` lines 105–172 — the two construction sites: `.fullScreen` swaps the whole body, `.banner` fills a slot above the header.
11. `UzumeApp/ViewModels/PreparationErrorViewModel.swift` — `presentationState` and the transitions that produce it.
12. `UzumeAppTests/DynamicTypeRegressionTests.swift` — the fixed-font ratchet; three of the files in scope are already on the list.

## Pre-flight invariants

Each is a stop condition. A failed check ends the session with a report, not a workaround.

- **DS.2 is merged to `main` and its M7 was accepted by Matt.** DS.3 assumes the `UzumeApp/Views/Components/` convention and the DS.2 identifier-pinning pattern exist.
- **`git status` is clean** and the branch is fresh from `main`.
- **`Scripts/closeout_evidence.sh` is ALL GREEN before task 1**; `Scripts/check_design_token_drift.sh` passes; the DS.1 token gate and the DS.2 identifier gate both return no output.
- **A D-number is reserved** for the status-tone consolidation, and a second for whatever the DECISION-NEEDED settles. Mark dates as run-time fill.

## Numbered tasks

1. **Write down the three colour maps before changing any of them.** Produce a table in the working notes with one row per severity value and one column per surface — full-screen (`FullScreenErrorView`/`PreparationFailureView`), toast (`ToastView`), banner (`TopBannerView`), inline (`LocalFileErrorBanner`) — recording the exact colour and symbol each uses today. The table must make the two conflicts explicit: **`degradation` renders yellow on the full-screen surfaces and red in toasts**, and **the banner ignores severity entirely**. This table is the input to the DECISION-NEEDED and the acceptance evidence for task 3.
   **Done-when:** the table exists, every cell is filled from source rather than assumption, and the two conflicts are stated in a sentence each.

2. **Capture the before-state.** Screenshot every status surface in every tone it can currently reach: the banner (rate-limited, total timeout, slow first track), the inline notice (unsupported format), each toast severity, and the full-screen failure in both its reachable states (`networkOffline`, `allTracksFailedToPrepare`). Record the VoiceOver output for each. Store under `docs/reviews/DS.3/before/`.
   **Done-when:** every reachable state has a capture; any state you could not reach is named with the reason.

3. **Write `StatusTone`.** New file `UzumeApp/Views/Components/StatusTone.swift`: an enum of `info`, `success`, `warning`, `danger`, each exposing foreground, background and border from the `--color-status-*` token triples plus one SF Symbol. Provide exactly two mapping functions — one from `ErrorSeverity`, one from `UzumeToast.Severity` — so every surface derives its tone the same way and no view maps severity to colour inline again. Neither source enum changes.
   **Done-when:** no `.red`, `.orange`, `.yellow`, `.gray` or `DashboardTokens` reference survives in any status surface; a unit test asserts every case of both source enums maps to a tone.

4. **Build `RecoveryScreen` and delete both predecessors.** New file `UzumeApp/Views/Components/RecoveryScreen.swift` carrying the shared blocking layout — dimmed canvas, tone icon, headline, optional body, primary CTA with `.keyboardShortcut(.defaultAction)`, optional secondary. It takes an error plus an explicit action set, so `PreparationProgressView` supplies "Pick another playlist" and "Start reactive mode" while a future caller can supply the error's own CTA keys. Delete `FullScreenErrorView.swift` — **it has no construction site anywhere in the app**, so its deletion removes duplication at zero behavioural risk — and delete `PreparationFailureView.swift`.
   **Done-when:** both files are gone; `PreparationProgressView`'s `.fullScreen` branch renders `RecoveryScreen`; the three preparation-failure identifiers are unchanged; the keyboard default action still fires the primary button.

5. **Retone the three non-blocking placements, keeping every placement distinct.** They share `StatusTone` and nothing else — interruption level, lifetime and dismissal stay exactly as they are:
   - `TopBannerView` → `NoticeBanner` (`UzumeApp/Views/Components/NoticeBanner.swift`). Still a 44pt strip above the track list, still non-blocking, still persisting until the view model changes state. It now derives its tone from the error's severity instead of always being amber — which means a `degradation` banner stops looking identical to a `warning` banner.
   - `LocalFileErrorBanner` → `InlineNotice` (`UzumeApp/Views/Components/InlineNotice.swift`), **moved out of `LocalFileErrorStore.swift`**. A view has no business living in a store file, and its coral pip is currently drawn from `DashboardTokens` — the diagnostic palette DS.1 deliberately walled off from consumer UI. Keep the 6-second auto-clear, tap-to-dismiss, and the deliberate absence of a background.
   - `ToastView` → `PerformanceToast`, `ToastContainerView` → `ToastRegion`. Keep the max-three stack, the trailing-move transition, the `AccessibilityNotification.Announcement` on insert, the action button and the dismiss button.
   **Done-when:** all three render from `StatusTone`; `LocalFileErrorStore.swift` contains no `View`; the toast announcement still fires on insert; `ToastManager` is unmodified.

6. **Pin the accessibility identifiers.** Extend the DS.2 pattern with `UzumeAppTests/StatusPlacementIdentifierTests.swift` asserting these resolve exactly:

   ```
   uzume.preparation.topBanner
   uzume.preparation.topBanner.dismiss
   uzume.view.preparationFailure
   uzume.preparationFailure.pickPlaylist
   uzume.preparationFailure.startReactive
   ```

   The identifiers keep their `preparation.*` spelling even though the components are renamed — an identifier is a contract, not a description.
   **Done-when:** the test exists, passes, and fails if any string changes.

7. **Extend the fixed-font ratchet.** `LocalFileErrorStore.swift` is not in `DynamicTypeRegressionTests.viewFiles` and its banner uses `.system(size: 13)` — the same class of gap DS.2 closed for `LocalSourceConnectionView`. Convert it, then update the list: remove the two deleted paths, add `InlineNotice.swift`, `NoticeBanner.swift`, `RecoveryScreen.swift`, `StatusTone.swift`.
   **Done-when:** the list names only files that exist, and the test passes.

8. **Record two dead affordances — do not fix them.** `TopBannerView` accepts an `onDismiss` closure and renders a dismiss button only when it is non-nil, but its single construction site (`PreparationProgressView` line 171) passes none — so the dismiss button and its `uzume.preparation.topBanner.dismiss` identifier have never appeared in a shipped build. Separately, `FullScreenErrorView` was written as a reusable §9.1/§9.2 surface and acquired no consumer. Record both in `docs/QUALITY/KNOWN_ISSUES.md` with evidence. `RecoveryScreen` inherits the second one's absence by deleting it; the banner's dismiss path stays as-is, wired but unused, until someone decides whether a preparation banner should be dismissible.
   **Done-when:** both entries exist and each names the file and line that proves it.

9. **HARD STOP — Matt's M7 review.** Retake every capture from task 2 into `docs/reviews/DS.3/after/`. Assemble `docs/reviews/DS.3/index.html` (self-contained, no build step): before/after per surface per tone, the task-1 colour-map table with a resolved "after" column, and the VoiceOver rows before and after. **Present, stop, and report.** The two things Matt is judging are the banner's inversion from amber-fill/black-text to token warning, and whatever the DECISION-NEEDED settled.
   **Done-when:** the page renders offline and every reachable state has a matched pair.

10. **Upstream findings.** Append to `docs/reviews/DS.3/UPSTREAM-FINDINGS.md`: that the app carries two severity vocabularies the design system does not model, the tone mapping as built, and any `--color-status-*` role that proved unusable at the app's contrast requirements.
    **Done-when:** the file exists and each finding names the app file that motivated it.

11. **Verification and closeout.** Run the full battery below, then the `closeout` skill. No push without Matt's explicit "yes, push."

## Do NOT

- **Do not collapse the four placements into one component.** `COMPONENTS.md` is explicit: they share tone and icon rules but stay separate because interruption, lifetime and action behaviour differ. A banner that persists, an inline notice that clears itself after six seconds, a toast that queues three deep and announces itself, and a screen that blocks are four different products. Sharing `StatusTone` is the whole of the sharing.
- **Do not change `ErrorSeverity` or `UzumeToast.Severity`.** `ErrorSeverity` is engine-owned in `Shared`; `StatusTone` maps from both rather than replacing either. Unifying the two source enums is a larger change with engine reach and is not this increment.
- **Do not change the severity assigned to any error.** `UserFacingError.severity` is untouched. This increment changes what a severity *looks like*, never which severity an error *has*.
- **Do not change existing user-facing copy.** `LocalizedCopy`, the CTA keys, the banner messages and the toast strings are untouched.
- **Do not change any accessibility identifier**, including where the component name no longer matches it.
- **Do not fix the two dead affordances.** Task 8 records them. Wiring a dismiss button that has never shipped is a behaviour change; deleting the identifier breaks the contract task 6 just pinned.
- **Do not touch `ToastManager`, `LocalFileErrorStore`'s store logic, `PreparationErrorViewModel`, or `NetworkRecoveryCoordinator`.** Queueing, coalescing, the 6-second clear task and the state transitions all stay. Only the views move.
- **Do not touch `AudioStallOverlayView`.** It is a fifth blocking surface with its own responsibility and a copy rewrite pending; it belongs to the playback-chrome work in DS.6.
- **Do not rebuild `PreparationProgressView`.** Its `.fullScreen` and `.banner` branches get new component names and nothing else. The stage rebuild is DS.4.
- **Do not reach into `DashboardTokens` from any consumer surface**, and do not modify it. Moving `InlineNotice` off the coral pip is the point; extending the diagnostic palette is not.
- **Do not write to `../uzume-site`.** Read it, report findings, commit nothing.
- **Do not introduce an appearance branch.**

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build 2>&1
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test 2>&1
swift test --package-path UzumeEngine 2>&1
Scripts/closeout_evidence.sh
Scripts/check_design_token_drift.sh
```

Increment-specific gates.

The predecessors are gone and no construction site survives:

```
grep -rn "FullScreenErrorView\|PreparationFailureView\|TopBannerView\|LocalFileErrorBanner\|ToastView\|ToastContainerView" UzumeApp UzumeAppTests
# expected: no output
```

No status surface maps severity to a colour inline any more:

```
grep -rn "\.red\b\|\.orange\b\|\.yellow\b\|\.gray\b\|DashboardTokens" \
  UzumeApp/Views/Components UzumeApp/LocalFileErrorStore.swift UzumeApp/Views/Preparation UzumeApp/Views/Playback \
  | grep -v "UzumeApp/Views/Playback/LocalFileTransportBar.swift"
# expected: no output  (LocalFileTransportBar's DashboardTokens use is DS.6's problem)
```

`LocalFileErrorStore.swift` is a store again:

```
grep -n "struct .*: View" UzumeApp/LocalFileErrorStore.swift
# expected: no output
```

The five identifiers still appear, spelled exactly as before:

```
for id in uzume.preparation.topBanner uzume.preparation.topBanner.dismiss \
          uzume.view.preparationFailure uzume.preparationFailure.pickPlaylist uzume.preparationFailure.startReactive; do
  grep -rq "$id" UzumeApp || echo "MISSING: $id"
done
# expected: no output
```

The DS.1 token gate and the fixed-font ratchet still pass:

```
grep -rn "Color\.black\|Color\.white\|cornerRadius: [0-9]" UzumeApp/Views UzumeApp/ContentView.swift \
  | grep -v "UzumeApp/Views/Dashboard/" \
  | grep -v "UzumeApp/Views/DebugOverlayView.swift" \
  | grep -v "UzumeApp/Views/QualityGradeIndicator.swift"
# expected: no output

grep -rn "system(size:" UzumeApp/Views/Components UzumeApp/LocalFileErrorStore.swift
# expected: no output
```

## Commit message templates

`[DS.3] <component>: <description>` — small commits per logical step:

```
[DS.3] StatusTone: one severity vocabulary mapped to the token status roles
[DS.3] RecoveryScreen: merge PreparationFailureView with the unused FullScreenErrorView
[DS.3] NoticeBanner: the preparation banner derives tone from severity
[DS.3] InlineNotice: move the local-file banner out of its store and off DashboardTokens
[DS.3] PerformanceToast: toast and region consume StatusTone
[DS.3] Tests: pin the five status-placement identifiers; StatusTone mapping coverage
[DS.3] Tests: LocalFileErrorStore joins the fixed-font ratchet
[DS.3] KNOWN_ISSUES: the banner dismiss button and FullScreenErrorView never shipped
[DS.3] DECISIONS: D-<run-time fill> status tone consolidation; D-<run-time fill> degradation tone
[DS.3] reviews: DS.3 before/after M7 page and upstream findings
```

Push only on Matt's explicit "yes, push."

## Closeout format

Invoke the `closeout` skill; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions:

- Output of all six increment gates above (each empty).
- The task-1 colour-map table with its resolved "after" column — the central evidence that three maps became one.
- The VoiceOver rows before and after for every status surface.
- Confirmation that the state owners are unmodified: `git diff main -- UzumeApp/ViewModels/PreparationErrorViewModel.swift UzumeApp/ViewModels/ToastManager.swift UzumeEngine/Sources/Shared/UserFacingError+Presentation.swift` returning empty.
- Files deleted and added with line counts, against the census's claim that the two full-screen views were an active duplicate.
- The M7 review page path and Matt's verdict on the banner inversion.

## DECISION-NEEDED

**When Uzume is running in degraded mode, does that read as caution or as alarm?**

The app has one severity called `degradation` — Uzume still works, but something is compromised: stem separation failed, a preview is missing, audio has gone undetected. Today it renders two different ways. On a full-screen failure it is yellow, the middle step between amber warning and red fatal. In a toast during a performance it is red, the loudest thing on screen. The same word, two opposite readings, because two people wrote the two maps. `StatusTone` forces one answer.

- **A — Degradation is caution (warning tone).** Amber-family everywhere. Red is reserved for "the session cannot continue without you" — the `fatal` cases: network gone, every track failed. A dropped stem or a missing preview is Uzume telling you it is coping, not failing, and the performance is still running. The visible change is that the "no audio detected" toast stops being red.
- **B — Degradation is alarm (danger tone).** Red everywhere. Matches how the toast behaves today, and treats "you are not seeing what you should be seeing" as serious regardless of whether playback continues. The visible change is that full-screen degraded states go from yellow to red, joining the fatal ones.
- **C — Keep both readings by giving degradation its own tone.** A fifth tone between warning and danger. Honest to the distinction, but it adds a status colour the design system does not publish, so the app would be inventing palette — exactly what DS.1's vendored-token discipline exists to prevent.

**Recommendation: A.** It matches the severity's own definition in the source — "Uzume is operating in degraded mode", which is explicitly not "the session cannot continue" — and it keeps red meaningful. A red toast that appears while the visuals are still playing teaches people to ignore red. The cost is honest: the silence toast becomes less alarming, and if you want silence to shout, that argues for reclassifying `silenceExtended` as fatal rather than for making all degradation red.

**Default if no reply: A**, with the before/after toast pair shown at the task 9 hard stop so the softening is judged on screen rather than in the abstract.

## Notes for the next increment

DS.4 is the preparation-stage rebuild — `PreparationProgressView` rebuilt in place from `PreparationTrackRow`, `PreparationStatusIndicator`, the new `NoticeBanner`, and the performed-light background. It is the first DS increment with a genuinely new visual idea rather than a consolidation, and it needs its own design pass before a prompt is written.
