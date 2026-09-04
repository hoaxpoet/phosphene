# Session prompt — DS.2

## Increment DS.2 — `SourceChoice`: one tile component, four affordances

**Type:** UX. Second increment of **Phase DS — Design system adoption (First Opening)**. No engine, no shader, no `.metal`, no preset.

**Objective.** After this session the app has one tile component for choosing a music source. `ConnectorTileView` and the private `LocalSourceActionTile` — two near-identical implementations that encode the same family separately — are replaced by `SourceChoice`, carrying four affordances: navigation, immediate action, unavailable with a reason, and unavailable with a recovery action. Both consumers (`ConnectorPickerView`, `LocalSourceConnectionView`) are migrated to it. Every accessibility identifier survives byte-for-byte and is pinned by a new test. State ownership is untouched: `ConnectorPickerViewModel` still owns `connectorPath`, and `NavigationLink` still lives in the consumer, not the component.

This is step 2 of the seven-step migration order in `PHOSPHENE-COMPONENT-CENSUS.md` §Migration order. It is the first DS increment that changes composition rather than colour, and it is deliberately the smallest such change available.

## Settled decisions carried into this increment

**Uzume is always dark (Matt, 2026-09-01; DS.1).** The appearance pin holds. `SourceChoice` is written against the dark token roles only and must contain no appearance branch.

**Tokens are the only source of presentation values (DS.1).** `SourceChoice` is tokenized from birth — it must never introduce a hard-coded colour, radius or spacing literal, and the DS.1 grep gate stays green throughout.

## Skill invocations

- `closeout` at the end (mandatory). §2 is the verbatim `Scripts/closeout_evidence.sh` block.
- **Not** `preset-session`, **not** `shader-authoring` — no GPU code or sidecar is in scope.
- **Not** `defect-handling` — this is not a BUG-* increment. The stale flag found in task 7 is recorded, not fixed.

## Read-first file list

Design system (sibling `uzume-site` checkout — read-only, see Do-NOT):

1. `../uzume-site/DesignSystem/COMPONENTS.md` — §Native product component extraction › `SourceChoice` (the four variants this increment must deliver), and §Release contract (what every component implementation must demonstrate).
2. `../uzume-site/docs/design/PHOSPHENE-COMPONENT-CENSUS.md` — §Reusable product components (the `ConnectorTileView` + `LocalSourceActionTile` rows), §State ownership rules to preserve, §Migration order step 2.
3. `../uzume-site/docs/design/EXPERIENCE_MODEL.md` — §Add music. Each source names its actual capabilities; a source never promises what it cannot honour.

App (the files being changed):

4. `UzumeApp/Views/ConnectorTileView.swift` — the richer of the two tiles: disabled caption, optional secondary action, accessibility label and hint via `AccessibilityLabels`.
5. `UzumeApp/Views/LocalSourceConnectionView.swift` — the consumer *and* the home of the private `LocalSourceActionTile`, which has a hover state the connector tile lacks and no accessibility hint.
6. `UzumeApp/Views/ConnectorPickerView.swift` — four tile construction sites across three `@ViewBuilder` properties, plus the two connection wrappers whose `@StateObject` lifetimes are load-bearing.
7. `UzumeApp/Services/AccessibilityLabels.swift` — the centralized label/hint lookup the component must keep using.
8. `UzumeApp/ViewModels/ConnectorPickerViewModel.swift` — read to understand what must **not** move into the component: `appleMusicRunning`, the debounced NSWorkspace observers, and `connectorPath`.
9. `UzumeAppTests/DynamicTypeRegressionTests.swift` — the fixed-font ratchet and its file list.
10. `UzumeApp/DesignSystem/UzumeTokens+App.swift` — the roles available to the new component (from DS.1).

## Pre-flight invariants

Each is a stop condition. A failed check ends the session with a report, not a workaround.

- **DS.1 is merged to `main` and its M7 was accepted by Matt.** DS.2 restyles nothing; it assumes the token vocabulary already exists and has been reviewed. Starting before that review lands means the first visual judgement of the tiles happens on an unreviewed palette.
- **`git status` is clean** and the branch is fresh from `main`.
- **`Scripts/closeout_evidence.sh` is ALL GREEN before task 1**, and `Scripts/check_design_token_drift.sh` passes.
- **The DS.1 grep gate returns no output before task 1.** If it does not, DS.1 regressed and this session stops.
- **A D-number is reserved** for the tile consolidation. Mark the date as run-time fill.

## Numbered tasks

1. **Record the current behaviour before changing it.** For all six tiles — the three connector tiles (Apple Music enabled, Apple Music disabled with its "Open Apple Music" recovery button, Spotify, Local files) and the three local action tiles (folder, file, playlist) — capture a screenshot in default and hover state, and record the VoiceOver output (label, then hint, or its absence) verbatim in the working notes. Store screenshots under `docs/reviews/DS.2/before/`.
   **Done-when:** every tile has a default and hover capture; the VoiceOver table has six rows and is explicit about which tiles currently announce no hint. This table is the acceptance evidence for task 4 and the input to the DECISION-NEEDED below.

2. **Write `SourceChoice`.** New file `UzumeApp/Views/Components/SourceChoice.swift`. It takes a display model — SF Symbol name, title, subtitle, accessibility identifier — and an affordance:

   ```swift
   enum Affordance {
       case navigation                                       // consumer wraps in NavigationLink
       case action(() -> Void)                               // opens a panel
       case unavailable(reason: String, recovery: Recovery?)  // Recovery = (label, action)
   }
   ```

   **The component never constructs a `NavigationLink`.** The navigation variant renders a chevron and the pressed/hover treatment; the consumer wraps it, so `ConnectorPickerViewModel` keeps sole ownership of `connectorPath`. Interactive variants (`navigation`, `action`) share one hover treatment — this deliberately *adds* hover feedback to the connector tiles, which lack it today, and is the increment's one intentional visual change. The `unavailable` variant has no hover and no chevron. Presentation values come from tokens only; no `.system(size:)` — semantic font styles only, since the new file joins the ratchet in task 6.
   **Done-when:** the file compiles, contains no colour/radius/spacing literal and no `.system(size:`, and the four affordances are exercised by SwiftUI previews.

3. **Migrate `ConnectorPickerView`.** Replace all four `ConnectorTileView` constructions. The enabled Apple Music, Spotify and Local files tiles become `NavigationLink(value:) { SourceChoice(…, affordance: .navigation) }`; the disabled Apple Music tile becomes `.unavailable(reason:recovery:)` carrying the existing caption and "Open Apple Music" button wired to `viewModel.openAppleMusic()`. `ConnectorType` keeps owning title, subtitle and symbol — that is product content, not presentation, and does not move into the component. Delete `ConnectorTileView.swift`.
   **Done-when:** `ConnectorTileView` no longer exists anywhere in the tree; the picker's three `@ViewBuilder` tile properties still read as three tiles; the `AppleMusicConnectionWrapper` and `OAuthSpotifyConnectionWrapper` `@StateObject` declarations are untouched.

4. **Migrate `LocalSourceConnectionView` and delete `LocalSourceActionTile`.** The three action tiles become `SourceChoice(…, affordance: .action(openFolderPicker))` and friends, keeping their exact identifiers. The heading, the inline `LocalFileErrorBanner`, and the typographic drop hint stay exactly as they are — they belong to DS.3 and DS.4.
   **Done-when:** the private struct is gone; the three panels still open; the drop-hint footer is unchanged.

5. **Pin the accessibility identifiers.** New test file `UzumeAppTests/SourceChoiceIdentifierTests.swift`, following the `PlaybackViewIdentifierTests` pattern, asserting all six identifiers resolve to exactly their current strings:

   ```
   uzume.connector.tile.apple_music
   uzume.connector.tile.spotify
   uzume.connector.tile.local_folder
   uzume.lf_source.tile.folder
   uzume.lf_source.tile.file
   uzume.lf_source.tile.playlist
   ```

   Nothing today pins these; a consolidation is exactly the change that silently breaks them.
   **Done-when:** the test exists, passes, and fails if any identifier string is altered.

6. **Extend the fixed-font ratchet.** `LocalSourceConnectionView.swift` is **not** in `DynamicTypeRegressionTests.viewFiles` and contains three `.system(size:)` calls (lines 68, 71, 106) — a gap the ratchet was written to close. Convert those three to semantic styles and add both `UzumeApp/Views/LocalSourceConnectionView.swift` and `UzumeApp/Views/Components/SourceChoice.swift` to the list.
   **Done-when:** the list contains both paths and `DynamicTypeRegressionTests` passes.

7. **Record the stale flag — do not fix it.** `ConnectorPickerViewModel.localFolderEnabled` is hard-coded `false` with a comment claiming the Local Folder tile is gated in v1, and `ConnectorPickerViewModelTests` asserts that `false`. The view has enabled the tile unconditionally since GAP A (2026-05-28). The property is dead and the comment is a false claim about the shipped build. Record it in `docs/QUALITY/KNOWN_ISSUES.md` with the evidence above. Do not delete the property, the comment or the test in this session.
   **Done-when:** the entry exists and names both the property and the test that pins it.

8. **HARD STOP — Matt's M7 visual and VoiceOver review.** Retake every capture from task 1 into `docs/reviews/DS.2/after/`, and re-record the six VoiceOver rows. Assemble `docs/reviews/DS.2/index.html` (self-contained, no build step): before/after per tile in default and hover state, plus the VoiceOver table with before and after columns. **Present, stop, and report.** Do not proceed to task 9 until Matt has looked. The hover change on connector tiles and whatever the DECISION-NEEDED settles are the two things he is being asked to judge.
   **Done-when:** the page renders offline and every tile has a matched pair in both states.

9. **Upstream findings.** Append to `docs/reviews/DS.2/UPSTREAM-FINDINGS.md`: the `SourceChoice` API as built, where it diverges from `COMPONENTS.md`'s description, and which parts of §Release contract this increment could not demonstrate (localization expansion and increased contrast in particular, if untested). This is input to a future `uzume-site` increment.
   **Done-when:** the file exists and each finding names the app file that motivated it.

10. **Verification and closeout.** Run the full battery below, then the `closeout` skill. No push without Matt's explicit "yes, push."

## Do NOT

- **Do not move state into the component.** No `@StateObject`, no `@EnvironmentObject`, no `NavigationLink`, no store access inside `SourceChoice`. It receives a display model, an affordance and closures. `connectorPath`, `appleMusicRunning` and the debounced NSWorkspace observers stay in `ConnectorPickerViewModel`; the two connection wrappers keep their `@StateObject` lifetimes exactly (CA.6-FU-3 exists because rebuilding those view models orphans in-flight OAuth and auto-retry Tasks).
- **Do not change any accessibility identifier**, including the constant names that carry them. Task 5 pins them precisely so a later refactor cannot drift.
- **Do not change existing user-facing copy.** `connector.type.*`, `lf_source.tile.*`, `connector.picker.*` and the drop hint are untouched. The only strings this increment may add are the `a11y.*` hints, and only if the DECISION-NEEDED resolves that way.
- **Do not restyle the surrounding screens.** The picker's heading, footer, toolbar and background, and the local view's heading, error banner and drop hint keep the DS.1 treatment. Tiles only.
- **Do not fix `localFolderEnabled`.** Task 7 records it. Deleting a property whose `false` a test asserts is a behaviour change wearing a cleanup costume, and it belongs with the connector-capability work, not here.
- **Do not touch `ConnectorType`.** Title, subtitle and symbol are product content and stay on the enum.
- **Do not touch `AppleMusicConnectionView`, `SpotifyConnectionView`, or the connection state machines.** Those are DS.3's consolidation.
- **Do not put `SourceChoice` in `UzumeApp/DesignSystem/`.** That directory holds the vendored token source and its app extension; a component authored here is app-owned until `uzume-site` adopts it (D-228). It goes in `UzumeApp/Views/Components/`.
- **Do not write to `../uzume-site`.** Read it, report findings, commit nothing.
- **Do not introduce an appearance branch.** DS.1 pinned the app dark; `.aqua`, `prefers-color-scheme` and `colorScheme == .light` stay absent.

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

Both old tiles are gone, and no construction site survives:

```
grep -rn "ConnectorTileView\|LocalSourceActionTile" UzumeApp UzumeAppTests
# expected: no output
```

All six identifiers still appear in the source, spelled exactly as before:

```
for id in uzume.connector.tile.apple_music uzume.connector.tile.spotify uzume.connector.tile.local_folder \
          uzume.lf_source.tile.folder uzume.lf_source.tile.file uzume.lf_source.tile.playlist; do
  grep -rq "$id" UzumeApp || echo "MISSING: $id"
done
# expected: no output
```

The DS.1 token gate still passes, and the new component obeys it:

```
grep -rn "Color\.black\|Color\.white\|cornerRadius: [0-9]" UzumeApp/Views UzumeApp/ContentView.swift \
  | grep -v "UzumeApp/Views/Dashboard/" \
  | grep -v "UzumeApp/Views/DebugOverlayView.swift" \
  | grep -v "UzumeApp/Views/QualityGradeIndicator.swift"
# expected: no output

grep -rn "system(size:" UzumeApp/Views/Components/SourceChoice.swift UzumeApp/Views/LocalSourceConnectionView.swift
# expected: no output
```

No appearance branch was introduced:

```
grep -rn "prefers-color-scheme\|NSAppearance(named: \.aqua)\|colorScheme == \.light" UzumeApp
# expected: no output
```

## Commit message templates

`[DS.2] <component>: <description>` — small commits per logical step:

```
[DS.2] SourceChoice: one tile component with navigation, action, and unavailable affordances
[DS.2] ConnectorPickerView: migrate four tile sites to SourceChoice; delete ConnectorTileView
[DS.2] LocalSourceConnectionView: migrate three action tiles; delete LocalSourceActionTile
[DS.2] Tests: pin the six source-tile accessibility identifiers
[DS.2] Tests: LocalSourceConnectionView joins the fixed-font ratchet
[DS.2] KNOWN_ISSUES: localFolderEnabled is dead and its comment claims a gate that is not there
[DS.2] DECISIONS: D-<run-time fill> SourceChoice consolidation
[DS.2] reviews: DS.2 before/after M7 page and upstream findings
```

Push only on Matt's explicit "yes, push."

## Closeout format

Invoke the `closeout` skill; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions:

- Output of all four increment gates above (each empty).
- The six-row VoiceOver table, before and after, as the accessibility evidence.
- Confirmation that `ConnectorPickerViewModel` is unmodified, as `git diff main -- UzumeApp/ViewModels/ConnectorPickerViewModel.swift` returning empty.
- The two files deleted and the two files added, with line counts, against the census's claim that these were near-duplicate implementations.
- The M7 review page path and Matt's verdict on the hover change.

## DECISION-NEEDED

**Should the local-source tiles start announcing a VoiceOver hint, like the connector tiles already do?**

The two tile families have the same accessible label shape — "Title. Subtitle." — but only the connector tiles add a hint: "Connect using this source" when enabled, "Not available" when disabled. The local folder/file/playlist tiles announce nothing after their label. A blind user moving through the source flow therefore gets guidance on the first screen and silence on the second. Consolidating the two tiles into one component forces a choice about which behaviour the component carries.

- **A — Every interactive tile gets a hint appropriate to what it does.** Navigation tiles keep "Connect using this source"; action tiles gain something like "Opens a file chooser"; unavailable tiles keep their reason. Adds two or three `a11y.*` strings. VoiceOver users hear consistent guidance across both screens, and the difference between "this pushes you forward" and "this opens a macOS panel" becomes audible — which is real information, since those two behave quite differently.
- **B — Preserve exactly what ships today.** Hints stay on connector tiles only; local tiles stay silent. `SourceChoice` carries an optional hint that two of its five uses leave empty. Zero change to what any user hears, and no new strings — but the inconsistency is now baked into a shared component, where it is harder to notice and easier to copy forward.
- **C — Drop hints everywhere.** One label shape, no hints, relying on native button semantics to convey actionability. Consistent and the least code, but it removes information from the connector tiles that someone deliberately added in U.9.

**Recommendation: A.** The tiles genuinely do two different things, and the consolidation is the cheapest moment this decision will ever be available — after it, adding hints means touching a shared component and re-reviewing every consumer.

**Default if no reply: A**, with the exact hint wording captured in task 1's VoiceOver table and shown to Matt at the task 8 hard stop rather than settled silently.

## Notes for the next increment

DS.3 is the status and recovery consolidation — `TopBannerView`, `LocalFileErrorBanner`, `ToastView`, `FullScreenErrorView` and `PreparationFailureView` share severity semantics while keeping four distinct interruption levels. It is a larger surface than DS.2 and should be prompted only after DS.2's M7 is accepted.
