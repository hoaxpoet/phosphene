# Session prompt — DS.1

## Increment DS.1 — the app adopts UzumeTokens; presentation only

**Type:** UX / infrastructure. First increment of **Phase DS — Design system adoption (First Opening)**. No engine, no shader, no `.metal`, no preset.

**Objective.** After this session the Uzume app has one source of visual truth. A vendored `UzumeTokens.swift`, byte-identical to `uzume-site@03d5478` and drift-checked by a script, sits in the app tree beside an app-only extension file that carries the semantic roles the app needs and the site package does not yet publish. The 27 view files that today hard-code `Color.black`, `Color.white.opacity(…)`, corner radii and ad-hoc spacing consume named roles instead. `OverlayBackdropStyle` becomes `PerformanceBackdrop`, expressed in tokens, with its measured contrast floor unchanged. The app is pinned to dark appearance so every surface resolves to the near-black canvas whatever macOS is set to. **Nothing the user can do changes.** No state machine, publisher, view model, accessibility identifier, copy string, shortcut or test expectation is touched.

This is step 1 of the seven-step migration order in `PHOSPHENE-COMPONENT-CENSUS.md` §Migration order. Steps 2–7 are DS.2–DS.7 and are explicitly out of scope.

## Settled decisions carried into this increment

**Uzume is always dark (Matt, 2026-09-01).** Every screen keeps the near-black canvas regardless of the macOS appearance setting. This follows the identity principle that the frame stays dark so the performance is the only bright thing, and it keeps DS.1 provable: one appearance to review, and the backdrop's existing contrast measurement stays valid.

This **diverges from the design system as published**. The site's SwiftUI package builds its roles on adaptive system colours and `tokens.css` ships a full light palette. The divergence is deliberate, is implemented by pinning the app's appearance rather than by rewriting the vendored roles (task 4), and is recorded as an upstream finding (task 8) so a light-appearance increment stays open as a future choice.

## Skill invocations

- `closeout` at the end (mandatory). §2 is the verbatim `Scripts/closeout_evidence.sh` block.
- **Not** `preset-session`, **not** `shader-authoring` — no GPU code or sidecar is in scope. If a task appears to need one, that is a scope error; stop and report.
- **Not** `defect-handling` — this is not a BUG-* increment.

## Read-first file list

Design system (in the sibling `uzume-site` checkout — read-only from this session, see Do-NOT):

1. `../uzume-site/DesignSystem/SwiftUI/Sources/UzumeDesignSystem/UzumeTokens.swift` — the file to vendor, verbatim. Note that `canvas`, `surface`, `textPrimary`, `textSecondary`, `line` and `accent` are all appearance-adaptive as written; task 4 is what makes them resolve dark.
2. `../uzume-site/tokens.css` — the naming authority for semantic roles, and the source of the literal dark values transcribed in task 3. The Swift file is a subset; role names in the app extension must match this file's `--color-*` / `--space-*` / `--radius-*` vocabulary.
3. `../uzume-site/DesignSystem/SwiftUI/README.md` — the "native controls stay native" rule, and which package types are prototypes rather than migration targets.
4. `../uzume-site/DesignSystem/COMPONENTS.md` — §Source reconciliation (the target-to-source map) and §Native platform controls (tint-only policy for `Button`, `Toggle`, `Picker`, `ProgressView`, `List`/`Form`/`Section`).
5. `../uzume-site/docs/design/PHOSPHENE-COMPONENT-CENSUS.md` — §Token findings, §State ownership rules to preserve, §Migration order (step 1 only).

App (the files being changed):

6. `UzumeApp/Views/Playback/OverlayBackdropStyle.swift` — the contrast contract in its header comment is a measured result, not a preference.
7. `UzumeApp/UzumeApp.swift` — the launch path where the appearance pin lands.
8. `UzumeEngine/Sources/Shared/Dashboard/DashboardTokens.swift` — read to confirm the boundary, **not** to change or extend. It encodes the retired purple/coral direction and a telemetry-dense type scale; it stays where it is and keeps its consumers.
9. `docs/DECISIONS.md` §D-228 — why the app may consume the design system but may not author it.

## Pre-flight invariants

Each of these is a stop condition. A failed check ends the session with a report, not a workaround.

- **Phase RN is closed.** The rename increments are merged to `main` and no `RN.*` branch is outstanding. DS.1 branches from a `main` that already carries the final names; starting it mid-rename guarantees a conflicted sweep.
- **`git status` is clean** and the branch is fresh from `main`.
- **`Scripts/closeout_evidence.sh` is ALL GREEN before task 1.** A red baseline makes the post-change battery unreadable.
- **`../uzume-site` exists as a sibling checkout, at commit `03d5478` or later, with `DesignSystem/SwiftUI/Sources/UzumeDesignSystem/UzumeTokens.swift` present.** Absent → stop; the vendored copy must have a provable origin.
- **Two D-numbers are reserved** — one for the vendored token source (task 2), one for the always-dark appearance (task 4). Mark the dates as run-time fill.

## Numbered tasks

1. **Take the before-state screenshots, in both system appearances.** Set macOS to Dark, capture every routed state at the app's default window size, then set macOS to Light and capture the same set. States: permission onboarding, photosensitivity notice, idle/source picker, each of the three connector flows, connecting, preparation (active + a failure), ready, playback chrome (track info shown and hidden, toast visible, local transport visible), shortcut help, ended, and all four settings sections. Store under `docs/reviews/DS.1/before/dark/` and `docs/reviews/DS.1/before/light/`.
   **Done-when:** every state above has a PNG in both sets, and any state you could not reach is named in the working notes with the reason. The Light set is the evidence for what task 4 changes — capture it before touching anything.

2. **Vendor the token source.** Copy `UzumeTokens.swift` to `UzumeApp/DesignSystem/UzumeTokens.swift` **byte-identical to upstream except for a prepended provenance header comment** naming the source repo, path, commit `03d5478`, and the SHA-256 of the upstream file. Add `Scripts/check_design_token_drift.sh`: it recomputes the upstream SHA-256 when a sibling `uzume-site` checkout is present and fails on mismatch; when the sibling is absent it prints `SKIP` and exits 0, so fresh clones and CI stay green. Record the mechanism and its cost (manual re-sync) as the first reserved D-number in `docs/DECISIONS.md`.
   **Done-when:** the vendored file differs from upstream only by the header block; `Scripts/check_design_token_drift.sh` passes locally and returns `SKIP`/0 when `../uzume-site` is renamed away; the decision row exists.

3. **Write the app-only role extension.** `UzumeApp/DesignSystem/UzumeTokens+App.swift` carries the semantic roles the app needs that the site package does not yet publish — at minimum `surfaceRaised`, `surfaceSelected`, `lineSubtle`, `textTertiary`, `textDisabled`, `onAccent`, `focus`, `scrim`, and the foreground/background/border triples for warning, danger, success and info. Every value is transcribed from `tokens.css`'s **dark-theme (`:root`) block** — literal values, since the app never renders the light palette — and **each carries the `--color-*` name it came from in a trailing comment.** The vendored file is never edited to add these.
   **Done-when:** every role used anywhere in task 6 resolves to this file or the vendored one; a reviewer can trace any app colour back to a `tokens.css` line by grep.

4. **Pin the app to dark appearance.** Set the application's appearance to `.darkAqua` at launch in `UzumeApp.swift`. Do it this way, not by overriding the vendored file's roles: the pin makes the adaptive system colours in the vendored tokens resolve to their dark values *and* carries native macOS controls — `Toggle`, `Picker`, `Form`, sheets, the Settings window — along with them, which a role override cannot do without redrawing controls the design system says to leave native. Record the always-dark decision, its rationale, and the deliberate divergence from the published tokens as the second reserved D-number.
   **Done-when:** with macOS set to Light, every state captured in task 1's Light set renders identically to its Dark counterpart; the Settings window and every native control are dark; the decision row exists and names the divergence.
   **This is the one deliberate visible change in DS.1.** Everything else in this increment is a like-for-like swap. Say so plainly in the closeout.

5. **`PerformanceBackdrop`.** Rename `OverlayBackdropStyle` to `PerformanceBackdrop` and express it in tokens — but **keep the measured numbers**. The current backdrop is `.ultraThinMaterial` plus 45% black at radius 10, and that pair is what produces the ≥4.5:1 floor for white text over an arbitrary preset frame. `--color-scrim` is 72% black and is **not** a drop-in substitute; substituting it changes the measured result. If the token vocabulary cannot express 45%, add a named app role for it in task 3's file rather than moving the number. Sweep every `overlayBackdrop()` call site.
   **Done-when:** the modifier and its helper are renamed with no remaining references to the old names; the numeric values are unchanged; the header comment still states the contrast contract and now names the token roles carrying it.

6. **Retokenize the 27 view files.** Replace hard-coded `Color.black`, `Color.white`, `.opacity(…)` chains on those, literal `cornerRadius:` values and ad-hoc spacing numbers with roles from tasks 2–3. Work file by file, committing in small batches. **Native controls keep their native styling** — tint primary actions with the accent, leave `Button`, `Toggle`, `Picker`, `ProgressView`, `List`/`Form`/`Section` and the destructive treatment alone (COMPONENTS.md §Native platform controls).
   **Done-when:** the grep gate in Verification returns no hits outside the exempt paths, and each commit builds and lints clean on its own.

7. **HARD STOP — Matt's M7 visual review.** Retake every screenshot from task 1, in both system appearances, into `docs/reviews/DS.1/after/dark/` and `docs/reviews/DS.1/after/light/`. Assemble a single self-contained review page (`docs/reviews/DS.1/index.html`, no build step) with two sections: **before/after in Dark** paired state by state, and **Light before → Light after** showing what the appearance pin changed. Note under each pair what changed and why. **Present, stop, and report.** Do not proceed to task 8 until Matt has looked. If he redirects, the redirect is the work; do not self-correct a visual direction he has not seen.
   **Done-when:** the review page renders offline; every task-1 state has a matched pair in both sections; the after/dark and after/light images for each state are visually identical.

8. **Findings back to the design system — as a report, not a commit.** Write `docs/reviews/DS.1/UPSTREAM-FINDINGS.md`: the always-dark divergence stated first (what the app does instead of the published adaptive roles, and what the site would need to publish if light appearance is ever adopted), then every role the app needed that the site package lacks, every place `tokens.css` and the Swift package disagree, and any component contract the app cannot satisfy as written. This file is the input to a future `uzume-site` increment.
   **Done-when:** the file exists and each finding names the app file that motivated it.

9. **Verification and closeout.** Run the full battery below, then the `closeout` skill. No push without Matt's explicit "yes, push."

## Do NOT

- **Do not change behaviour.** No state machine, publisher wiring, view model, `@StateObject` ownership, environment injection, accessibility identifier, accessibility label, copy string, keyboard shortcut, or test expectation. If retokenizing a file seems to require one of these, that is a finding for a later DS increment — write it down and leave the file alone. (`PHOSPHENE-COMPONENT-CENSUS.md` §State ownership rules to preserve.) The appearance pin in task 4 is the single sanctioned exception and changes no logic.
- **Do not implement light appearance, a theme toggle, or a user-facing appearance preference.** Matt settled this on 2026-09-01: Uzume is always dark. A `SettingsStore` key, an `@AppStorage` flag, or a "follow system" branch is out of scope and would need its own review.
- **Do not edit the vendored `UzumeTokens.swift` to hard-code dark values.** The pin is what resolves them. Editing the file breaks the drift check and the provenance claim in one move.
- **Do not remove `PlanPreviewView`, `PlanPreviewRowView`, `PlanPreviewTransitionView`, `ReadyPulsingBorder`, or `TrackChangeAnimationView`.** The census marks them for removal on the surprise-model argument; that is a product change and belongs to DS.5, with its own tests to update.
- **Do not touch `DashboardTokens`, `DashboardOverlayView`, `DashboardCardView`, `DashboardRowView`, `DebugOverlayView`, or `QualityGradeIndicator`.** Developer instrumentation is a separate system by the census's own finding; it keeps its dense scale and its retired palette until a diagnostics increment says otherwise. These paths are exempt from the grep gate.
- **Do not adopt `CuratorControlSurface`, `StreamingHandoff`, `PreparationStage`, `PerformancePreflight`, or `UzumeSystemNotice` from the site package.** The package README calls them prototypes and sketches; `CuratorControlSurface` is explicitly not the migration target. DS.1 adopts tokens only.
- **Do not add `DesignSystem/SwiftUI` as a Swift package dependency** — no local path reference, no git dependency. The vendored-copy mechanism is chosen precisely so a fresh clone and CI never need a second repo present.
- **Do not write to `../uzume-site`.** D-228 makes it the brand and design-system source of truth; this session reads it and reports findings. No commits, no edits, no "small fix while I'm here."
- **Do not redraw native macOS controls.** Tint and compose; do not rebuild standard control behaviour (COMPONENTS.md).
- **Do not restyle past the token swap.** Reflowing a layout, changing a hierarchy, or "while I'm in here" improvements are DS.2+ and unreviewable inside a mechanical sweep.

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

No hard-coded presentation values survive outside the exempt diagnostic paths and the token files themselves:

```
grep -rn "Color\.black\|Color\.white\|cornerRadius: [0-9]" UzumeApp/Views UzumeApp/ContentView.swift \
  | grep -v "UzumeApp/Views/Dashboard/" \
  | grep -v "UzumeApp/Views/DebugOverlayView.swift" \
  | grep -v "UzumeApp/Views/QualityGradeIndicator.swift"
# expected: no output
```

The vendored file is untouched apart from its header, and no light-appearance branch was introduced:

```
diff <(tail -n +$(grep -n "^import" UzumeApp/DesignSystem/UzumeTokens.swift | head -1 | cut -d: -f1) UzumeApp/DesignSystem/UzumeTokens.swift) \
     ../uzume-site/DesignSystem/SwiftUI/Sources/UzumeDesignSystem/UzumeTokens.swift
# expected: no output

grep -rn "prefers-color-scheme\|\.aqua\b\|NSAppearance(named: \.aqua)\|colorScheme == \.light" UzumeApp
# expected: no output
```

Drift-check must survive a missing sibling:

```
mv ../uzume-site ../uzume-site.hidden && Scripts/check_design_token_drift.sh; echo "exit=$?"; mv ../uzume-site.hidden ../uzume-site
# expected: SKIP, exit=0
```

Add a regression test asserting the pin holds — `UzumeAppTests/AppearancePinTests.swift`, checking the application's effective appearance is `.darkAqua`. This is the only new test file DS.1 adds.

## Commit message templates

`[DS.1] <component>: <description>` — small commits per logical step:

```
[DS.1] tokens: vendor UzumeTokens from uzume-site@03d5478 with provenance and drift check
[DS.1] tokens: app-only semantic roles transcribed from tokens.css dark block
[DS.1] App: pin the application to dark appearance (D-<run-time fill>)
[DS.1] PerformanceBackdrop: rename and retokenize, measured contrast values unchanged
[DS.1] Views: retokenize the idle and connector surfaces
[DS.1] Views: retokenize the preparation and ready surfaces
[DS.1] Views: retokenize the playback chrome and overlays
[DS.1] Views: retokenize settings, onboarding, and ended
[DS.1] DECISIONS: D-<run-time fill> vendored token source; D-<run-time fill> always-dark appearance
[DS.1] reviews: DS.1 before/after M7 pages and upstream findings
```

Push only on Matt's explicit "yes, push."

## Closeout format

Invoke the `closeout` skill; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions:

- The grep-gate output (empty), the vendored-file diff (empty), the light-branch grep (empty), and the drift-check output in both the present and absent-sibling cases.
- A count of files changed against the 27 named in the census's token finding, with any file deliberately left alone named and justified.
- Confirmation that no existing test was modified, as `git diff --stat main -- UzumeAppTests UzumeEngine/Tests` showing only the added `AppearancePinTests.swift`.
- **The appearance pin stated as the increment's one visible change**, with the Light before/after pairs as its evidence.
- The M7 review page path and Matt's verdict.

## Notes for the next increment

DS.2 is the `SourceChoice` consolidation (`ConnectorTileView` + `LocalSourceActionTile`), per the census's migration order. It is the first increment that touches composition rather than colour, and it should be prompted only after DS.1's M7 is accepted.
