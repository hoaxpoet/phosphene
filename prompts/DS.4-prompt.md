# Session prompt — DS.4

## Increment DS.4 — the preparation screen becomes the overture

**Type:** UX. Fourth increment of **Phase DS — Design system adoption (First Opening)**. No preset, no `.metal`, no shader. Two contained changes outside the view layer — one in `UzumeEngine/Sources/Session/` (task 3) and one in `SettingsStore` (task 4) — both prerequisites, not side quests.

**Objective.** After this session, waiting for a session to prepare is something you watch rather than something you endure, and the listener chooses how. `PreparationProgressView` is rebuilt in place around **two views behind a preference**:

- **Mysterious** (default) — a dark cave whose opening starts shut, cracks to a pinprick on the first track heard, and widens through the engine's readiness stops. The identity's full prism spills out of it in every direction, growing more vibrant as the aperture expands. It never names a track.
- **Detailed** — the track list, rebuilt from `PreparationTrackRow` + `PreparationStatusIndicator`, reporting what Uzume just *heard* for each track: tempo, key, mood, stem balance.

The header and the progress bar are gone from both. `NoticeBanner`, `RecoveryScreen` and the "Start now" / "Cancel" buttons are consumed unchanged.

**The acceptance bar is Matt's own words, and nothing else:**

> "i want people to feel entertained and excited during preparation"

## Settled decisions carried into this increment

**The design is decided, signed off, and committed.** `docs/reviews/DS.4/DESIGN.md` is the contract — read it completely, it is short and it records five falsified executions with the reason each failed. `docs/reviews/DS.4/design-pass.html` is the animated look reference Matt approved ("otherwise i think this is perfect"). **Do not re-open the direction, and do not port the mock** — it is a browser sketch; the built version should be better.

**Both views ship.** Grounded in beta feedback relayed by Matt: *"some people are going to want to know details about the playlist and some are going to prefer mystery. We need to be able to address the desires of both."* Neither is the "advanced" one.

**The concept is the brand's own myth, not a metaphor invented in the session.** `BRAND.md` maps Ama-no-Iwato onto the product directly, and **"Omoikane prepares a plan" is this screen**. If session vocabulary drifts to imagery Matt never used, stop and re-anchor.

**In the mysterious view the track list is hidden** (Matt, 2026-09-02). The cave fills the screen. When tracks fail, a quiet line surfaces the count — *"2 tracks couldn't be prepared"* — and opening the detailed view is how you see which. The mysterious view's whole proposition is that it does not show you the playlist, and the other view exists for people who want that. A nameless per-track strip was the tempting middle and was rejected: it re-enumerates tracks, which is the thing four falsified executions were trying to escape.

**Uzume is always dark (D-232); tokens only (DS.1); app-authored components live in `UzumeApp/Views/Components/` (DS.2); status placements are settled (D-234/D-235/D-237).**

## Skill invocations

- `closeout` at the end (mandatory). §2 is the verbatim `Scripts/closeout_evidence.sh` block.
- **Not** `preset-session`, **not** `shader-authoring` — no `.metal` file is touched.
- **Not** `defect-handling` — DEAD-002 is decided in task 11, not worked as a defect.

## Read-first file list

1. `docs/reviews/DS.4/DESIGN.md` — the contract. First, and completely.
2. `docs/reviews/DS.4/design-pass.html` — open it in a browser, switch views, switch playlists, and watch the mysterious view at **1×** for a full minute. Its `drawFrame` is the look reference.
3. `UzumeApp/Views/Preparation/PreparationProgressView.swift` — the view being rebuilt. `bannerSlot`, `header`, `progressBar`, `trackList`, `bottomBar`, the `.fullScreen` branch, and the `.onAppear` `NetworkRecoveryCoordinator` wiring (D-061(d,e)) which is load-bearing and survives.
4. `UzumeApp/Views/TrackPreparationRow.swift`, `UzumeApp/Views/TrackPreparationStatusIcon.swift` — what the two new row components are extracted from.
5. `UzumeEngine/Sources/Session/TrackPreparationStatus.swift` — `AnalysisStage` + the status cases. Task 3 extends this.
6. `UzumeEngine/Sources/Session/TrackProfile.swift` — `bpm`, `key`, `mood`, `spectralCentroidAvg`, `stemEnergyBalance`, `beatIrregular`. The material both views are made of.
7. `UzumeEngine/Sources/Session/SessionPreparer.swift` — `@Published trackStatuses`, the serial analysis cursor, `prefetchWindow = 4`.
8. `UzumeEngine/Sources/Session/SessionTypes.swift` — `ProgressiveReadinessLevel`, `defaultProgressiveReadinessThreshold = 3`. **The aperture's four stops are these.**
9. `UzumeApp/Services/SettingsStore.swift` — the `@Published` + `didSet` encode pattern and the `uzume.settings.<group>.<key>` scheme. Task 4 follows it exactly.
10. `UzumeEngine/Tests/UzumeEngineTests/Renderer/MitosisSketchRenderTests.swift` §"Criterion 4: flash-safe" — the measured-luminance idiom task 9 must follow. Do not invent a new one.

## Pre-flight invariants

Each is a stop condition. A failed check ends the session with a report, not a workaround.

- **DS.3 is merged to `main`** (PR #188, squashed as `45b002ab`); `git status` clean on a branch fresh from `main`.
- **`Scripts/closeout_evidence.sh` is ALL GREEN before task 1.** In a worktree run `Scripts/link_fixtures.sh` first — gitignored fixtures do not reach worktrees and their absence reads as engine failures.
- **`Scripts/check_design_token_drift.sh` passes**; the DS.1 token gate returns no output.
- **One D-number is reserved** for the preparation-screen design; there is no open decision left in this prompt. Next free is **D-238**; verify against `docs/DECISIONS.md` rather than trusting this line.

## Numbered tasks

1. **Capture the before-state.** Every reachable state of `PreparationProgressView`: early, mid, three-ready (Start now enabled), per-row `previewNotFound`, per-row `stemSeparationFailed`, an active `NoticeBanner`, and the `RecoveryScreen` branch. Record VoiceOver output for each. Store under `docs/reviews/DS.4/before/`. Generalise `UzumeAppTests/DS3StatusCaptureHarness.swift` rather than writing a second harness.
   **Done-when:** every reachable state has a capture; anything unreachable is named with the reason.

2. **Measure the wait before changing it.** A real playlist, not a fixture, and ideally 30+ tracks. Record wall time to first track ready, to three-ready, to fully prepared, and the per-stage split for a representative track.
   **Done-when:** the numbers are in `docs/reviews/DS.4/TIMING.md`. This is task 10's baseline, and it also confirms or corrects the 3–5 minute figure the whole design is paced against.

3. **Publish the profile to the App layer.** The prerequisite. `TrackPreparationStatus` carries only the stage, so the App layer cannot know what Uzume heard — **both** views need it. Extend the engine so the per-track profile reaches `PreparationProgressView`, keeping `SessionPreparer`'s existing `@Published` contract intact. **Its own commit, before any view work.**
   **Done-when:** an App-layer test observes `bpm`, `mood` and `stemEnergyBalance` for a track that reaches `.ready`; existing `SessionPreparer` / `SessionManager` suites pass unchanged.

4. **Add the preference.** `uzume.settings.visuals.preparationView`, following the `SettingsStore` pattern exactly. Default **mysterious**. Surface it in Settings with copy that describes what the listener gets, not what the code does. Changeable at any time, including mid-preparation.
   **Done-when:** the setting persists across launch, `SettingsStoreEnvironmentRegressionTests` passes, and `Scripts/check_user_strings.sh` stays green.

5. **Build `PreparationAperture`** — the mysterious view. New file in `UzumeApp/Views/Components/`. Per §The aperture starts closed and §The colour is the identity's prism in DESIGN.md: shut at rest, pinprick on first track heard, widening through the four readiness stops; ivory opening kept brighter than the spectrum; a continuous full-spectrum prism spilling **in every direction**; vibrancy ramping with the aperture; playlist character driving behaviour, never hue. Prefer SwiftUI `Canvas` + `TimelineView` unless task 10 says otherwise.
   **Done-when:** it renders from real profile data; the aperture is a pure function of readiness; nothing spills while shut; no colour outside the vendored tokens and the documented spectrum.

6. **Build the detailed view.** Extract `PreparationTrackRow` and `PreparationStatusIndicator` into `UzumeApp/Views/Components/`, and make the row report **discoveries** rather than stages once a track is heard — tempo, key, mood, and a compact stem balance. **Still renders per-row `previewNotFound` and `stemSeparationFailed`**, which are `.inlineOnRow` and have nowhere else to go.
   **Done-when:** the row shows the profile for `.ready` tracks and the failure for failed ones; the existing accessible combined label/value contract is preserved.

7. **Rebuild `PreparationProgressView` in place.** The chosen view replaces `header` and `progressBar`. `bannerSlot` keeps its position. `bottomBar` keeps "Start now" and "Cancel" as **buttons** (Matt's explicit call — the aperture may signal readiness, it never becomes the control). The `.onAppear` coordinator wiring and the cancel `confirmationDialog` survive verbatim. **In the mysterious view the list is hidden**; failures surface as a count line that opens the detailed view. Per-row failures may never become *unreachable* — but they are not shown in place there.
   **Done-when:** every existing preparation identifier resolves unchanged; the `.fullScreen` branch still renders `RecoveryScreen`; switching the preference mid-preparation swaps views without disturbing preparation.

8. **Reduced motion and VoiceOver, for both views.** Under `SettingsStore.reducedMotion` the aperture still renders and still widens with readiness — it stops *animating*, it does not disappear. Information must never be motion-dependent. Every fact the aperture conveys (how many heard, that you can start) needs a text equivalent on the accessibility tree; the mysterious view is otherwise **invisible** to VoiceOver.
   **Done-when:** a test asserts the reduced-motion path renders a non-empty aperture; the task 1 VoiceOver rows are matched or improved, never regressed, in **both** views.

9. **Prove it is flash-safe.** [D-157] — bounded max per-frame brightness change, steady global luminance — is this product's real flash gate, and this increment adds a bright expanding light source to a screen that previously had none. Follow the `MitosisSketchRenderTests` §Criterion 4 idiom; report `maxΔ/frame` and luma range across a full preparation including several tracks landing together.
   **Done-when:** the measurement exists and its numbers are in the closeout. **A number you cannot defend is a stop-and-report, not a tuning target.**

10. **Prove it did not slow preparation down.** The GPU is running MPSGraph stem separation during exactly this screen. Re-run task 2's measurement with each view live and compare. **A measurable regression means the animation gets cheaper, not that the measurement gets dropped.**
    **Done-when:** `TIMING.md` carries baseline / mysterious / detailed columns and states the deltas. Any regression beyond noise is a stop-and-report.

11. **Decide DEAD-002.** DS.3 recorded that `NoticeBanner`'s dismiss button has never rendered — `PreparationProgressView` passes no `onDismiss` — and left it for the increment that owns this screen. That is this one. Wire it or delete the affordance; **do not leave it undecided a second time**, and if you wire it, decide what dismissing a still-true condition means.
    **Done-when:** the `KNOWN_ISSUES.md` entry is resolved or closed with reasoning, and `StatusPlacementIdentifierTests` matches whichever was chosen.

12. **HARD STOP — Matt's M7 review.** Retake every capture from task 1 into `docs/reviews/DS.4/after/`, **in both views**, plus a screen recording of a full preparation in the mysterious view — this is a motion design and stills cannot carry it. Assemble `docs/reviews/DS.4/index.html` (self-contained, images inlined, no build step) with before/after per state per view, the timing table, and the flash-safety numbers. **Present, stop, and report.** What Matt is judging is whether the wait is entertaining and exciting, and **whether the mysterious view holds for four minutes** — the claim the whole direction rests on.
    **Done-when:** the page renders offline, every reachable state has a matched pair, and the recording plays.

13. **Verification and closeout.** Run the full battery, then the `closeout` skill. No push without Matt's explicit "yes, push."

## Do NOT

- **Do not expose upcoming content, in either view.** `COMPONENTS.md`: *"Never exposes upcoming content."* The line is **heard vs. will-do** — both views may show what Uzume heard in music the listener already chose; neither may show which preset a track gets, the emotional arc, or what is coming next. **The detailed view is not an exemption.** This is the one rule that, if broken, invalidates the increment.
- **Do not make per-row failures invisible.** `previewNotFound` and `stemSeparationFailed` are `.inlineOnRow`.
- **Do not turn the aperture into a control.** "Start now" and "Cancel" stay buttons.
- **Do not colour the light by mood, or by anything else.** The prism is identity, not data — a mood-tinted cave was tried and rejected. The playlist changes how the light *behaves*.
- **Do not draw a mechanical iris.** The opening is organic and irregular (Matt, 2026-09-02); a pictured aperture contradicts `BRAND.md` and would require editing the brand source of truth.
- **Do not port `design-pass.html`.** Beat it.
- **Do not touch `SessionPreparer`'s preparation logic, analysis order, or `prefetchWindow`.** Task 3 adds publishing only. Making preparation *faster* is a different increment.
- **Do not touch `ToastManager`, `PreparationErrorViewModel`, `NetworkRecoveryCoordinator`, or any DS.3 status component.**
- **Do not change any existing accessibility identifier.** Copy the increment *removes* (`preparation.header.title`, the progress-bar strings) is deleted from `Localizable.strings` in the same commit, and `Scripts/check_user_strings.sh` stays green.
- **Do not reach into `DashboardTokens`**, and **do not introduce an appearance branch** (D-232).
- **Do not write to `../uzume-site`.** Read it, report findings, commit nothing.
- **Do not tune away a flash-safety number.** [D-157]/[D-158] — a failing luminance measurement is a P1 safety finding and goes to Matt.

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build 2>&1
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test 2>&1
swift test --package-path UzumeEngine 2>&1
Scripts/closeout_evidence.sh
Scripts/check_design_token_drift.sh
Scripts/check_user_strings.sh
```

Increment-specific gates.

The old chrome is gone:

```
grep -rn "preparation.header.title" UzumeApp
# expected: no output
```

Per-row failures still render:

```
grep -rn "previewNotFound\|stemSeparationFailed" UzumeApp/Views/Components
# expected: at least one hit in the row component
```

No colour outside the token system:

```
grep -rn "\.red\b\|\.orange\b\|\.yellow\b\|\.gray\b\|DashboardTokens" \
  UzumeApp/Views/Components UzumeApp/Views/Preparation
# expected: no output
```

The DS.1 token gate and the fixed-font ratchet still pass:

```
grep -rn "Color\.black\|Color\.white\|cornerRadius: [0-9]" UzumeApp/Views UzumeApp/ContentView.swift \
  | grep -v "UzumeApp/Views/Dashboard/" \
  | grep -v "UzumeApp/Views/DebugOverlayView.swift" \
  | grep -v "UzumeApp/Views/QualityGradeIndicator.swift"
# expected: no output

grep -rn "system(size:" UzumeApp/Views/Components UzumeApp/Views/Preparation
# expected: no output
```

## Commit message templates

`[DS.4] <component>: <description>` — small commits per logical step:

```
[DS.4] Session: the per-track profile reaches the App layer
[DS.4] Settings: the listener chooses mysterious or detailed preparation
[DS.4] PreparationAperture: the cave opens as Uzume hears the playlist
[DS.4] PreparationTrackRow: the row reports discoveries, not stages
[DS.4] PreparationProgressView: the chosen view replaces the header and progress bar
[DS.4] Accessibility: reduced motion and a text equivalent for the aperture
[DS.4] Tests: flash safety measured across a full preparation
[DS.4] KNOWN_ISSUES: DEAD-002 decided
[DS.4] DECISIONS: D-<run-time fill> the preparation screen as overture
[DS.4] reviews: DS.4 before/after M7 page, timing, and the recording
```

Push only on Matt's explicit "yes, push."

## Closeout format

Invoke the `closeout` skill; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions:

- Output of the increment gates above.
- **The timing table from tasks 2 and 10** — baseline / mysterious / detailed, with deltas stated. The central evidence that the overture did not tax the work it describes.
- **The flash-safety numbers** — `maxΔ/frame` and luma range.
- The VoiceOver rows before and after **for both views**, and the reduced-motion behaviour described.
- Confirmation that the state owners are unmodified: `git diff main -- UzumeApp/ViewModels/PreparationErrorViewModel.swift UzumeApp/ViewModels/ToastManager.swift` returning empty.
- The DEAD-002 decision and its reasoning.
- The M7 page path, the recording, and Matt's verdict against his own words.

## DECISION-NEEDED

**None.** Every product-level question this increment raised was settled during the design pass
(`docs/reviews/DS.4/DESIGN.md` §Matt's brief records each in his own words). The failure-handling
question that stood here — where the track list goes in the mysterious view — was answered
**A** on 2026-09-02 and is now in §Settled decisions.

If a genuinely product-level question appears mid-session — one whose answer changes what the
listener sees or feels, and which cannot be resolved from the design contract — **stop and bring
it to Matt** rather than deciding it quietly. Engineering choices remain Claude's.

## Notes for the next increment

DS.5 is `ReadyView` → `StreamingHandoff`, and it inherits an open question from this one: whether the aperture persists into the ready state as a held image, or whether reaching ready is the moment it finally opens all the way. That is a design decision, not an implementation one — it needs Matt before DS.5 is written, the same way this one did.
