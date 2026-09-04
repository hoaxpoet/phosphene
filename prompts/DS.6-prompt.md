# Session prompt — DS.6

## Increment DS.6 — the playback chrome, retokenized in place

**Type:** UX. Sixth increment of **Phase DS — Design system adoption (First Opening)**. No preset, no `.metal`, no shader, no engine change. Everything happens in `UzumeApp/Views/Playback/` and, for one preference, `SettingsStore`.

**Objective.** After this session the chrome the Curator sees over a running show — track card, controls cluster, listening badge, progress, local transport, toasts — is drawn entirely from the vendored design system and reorganized as the `PerformanceChrome` component the design system already specifies. It is the same composition, in the same files, made right: no colour outside the tokens, no Phosphene-era palette (`DashboardTokens`) outside the dashboard, no `.teal`/`.green`/`.orange`, nothing on screen that tells the listener what comes next, and — per the design system — a control surface that can go quiet but never become undiscoverable.

**The acceptance bar, from the design system this increment consumes** (`uzume-site/DesignSystem/COMPONENTS.md` §`PerformanceChrome`, `uzume-site/DESIGN.md` §Curator Control Surface):

> "Retokenize and reorganize the existing composition; do not create a second control tree."
> "Always discoverable on the Curator display and absent from separated Viewer output. It contains listening status, Show/Hide Track Information, and End Session; local-file transport appears only because Uzume owns that playback."
> "It may reduce to quiet edge controls after inactivity but cannot become undiscoverable." — **overridden by Matt for the app** (§DECISION-NEEDED 2): the chrome disappears completely after a brief inactivity and returns on mouse movement or a tap.

## Settled decisions carried into this increment

**In place, not parallel.** The census (`uzume-site/docs/design/PHOSPHENE-COMPONENT-CENSUS.md` §Migration order, step 6) and `COMPONENTS.md` §`PerformanceChrome` §Migration both say the package's early `CuratorControlSurface` prototype is **not** the migration target — it omits the existing chrome's state, source capability and notification behaviour. `PlaybackChromeView` and its children are retokenized where they stand. A second tree is the one thing that fails this increment outright.

**The composition that exists is the composition.** `PlaybackChromeView` composes `TrackInfoCardView` (top-leading), `PlaybackControlsCluster` + the background-preparation indicator (top-trailing), `ListeningBadgeView` (top-centre), `LocalFileTransportBar` (bottom-centre, local sessions only), `ToastRegion` (bottom-trailing). `PlaybackChromeViewModel` owns visibility, auto-hide, the listening badge, the current track/preset, and the local-file flags. Keep all of it; change what it is made of.

**Uzume is always dark (D-232); tokens only (DS.1); app-authored components live where they are (DS.2); status semantics are settled (D-234/D-235/D-236/D-237) — `PerformanceToast` already consumes `StatusTone` and is done.** The contrast guarantee is measured, not chosen: `PerformanceBackdrop` (`.ultraThinMaterial` + `UzumeAppColor.Performance.backdropTint` at a measured 45 %) is certified by `PresetContrastCertificationTests`. **Its numbers do not change in this increment.**

**Deferred here by DS.1, explicitly.** `LocalFileTransportBar`'s surface, border and purple glow still come from `DashboardTokens` (`ENGINEERING_PLAN.md` §DS.1: *"migrating the whole component is DS.6"*). Its file header still cites `.impeccable.md` and "coral is action" — Phosphene's palette. `DESIGN.md` §Colors: *violet is the interaction accent; isolated gold is never control chrome.* DS.1 already moved the play/pause disc to violet; DS.6 finishes the bar.

**The surprise model binds the chrome too (D-238).** `COMPONENTS.md` §`TrackInformation`: *"Preserve current-track data; remove future-plan disclosure."* The card may say what is playing now — title, artist, artwork, the preset now on screen. It may not say what comes next or how the session is structured.

**Naming precedent (D-239).** "Show track info" / "Hide track info" is already the app's wording for exactly this affordance on the preparation screen. The design system's "Show/Hide Track Information" is the same control; use the same words.

**Ready is the arrival (D-240).** `PlaybackArrivalOverlay` is `PlaybackView` Layer 7 and runs over the chrome on entry to `.playing`. Do not touch it, and do not let the chrome's first-show timer fight the push — the chrome's "visible for 3 s on session start" should start when the arrival has faded, not before.

## Skill invocations

- `closeout` at the end (mandatory). §2 is the verbatim `Scripts/closeout_evidence.sh` block.
- **Not** `preset-session`, **not** `shader-authoring` — no `.metal` file is touched.
- **Not** `defect-handling` unless a genuine defect surfaces mid-session; the retokenization is not a defect.

## Read-first file list

1. `uzume-site/DesignSystem/COMPONENTS.md` — the table row for `PerformanceChrome`, `TrackInformation`, `LocalPlaybackTransport`; then §`PerformanceChrome` (Purpose / Anatomy / Behavior / States / Migration). This is the contract.
2. `uzume-site/DESIGN.md` — §Colors (the accent rule), §Curator Control Surface, §Shared States and Motion (120 / 240 / 480 ms, exponential ease-out; what reduced motion removes).
3. `uzume-site/docs/design/PHOSPHENE-COMPONENT-CENSUS.md` — §Migration order step 6, and the `TrackInfoCardView` / `QualityGradeIndicator` rows.
4. `docs/UX_SPEC.md` §7.1–7.3 (layers, auto-hide, content), §7.10 (reduced motion). §7.2's "0.4 black opacity backdrop" is superseded by the measured 45 % — read `PerformanceBackdrop.swift`'s header for why.
5. `UzumeApp/Views/Playback/PlaybackChromeView.swift` — the composition, and the private `PreparationBackgroundIndicator` with its `Color.teal`.
6. `UzumeApp/Views/Playback/TrackInfoCardView.swift` — the artwork slot, the text column, and `orchestratorStatePill` (`.green` / `.orange`).
7. `UzumeApp/Views/Playback/PlaybackControlsCluster.swift`, `SessionProgressDotsView.swift`, `ListeningBadgeView.swift`, `ToastRegion.swift`, `PerformanceToast.swift`.
8. `UzumeApp/Views/Playback/LocalFileTransportBar.swift` — every `DashboardTokens` reference, the custom glyph shapes (keep them — they exist so the bar does not read as Spotify chrome), the hover states.
9. `UzumeApp/ViewModels/PlaybackChromeViewModel.swift` — `overlayVisible`, the auto-hide timers, `showListeningBadge`, `isLocalFileSession`, `isBackgroundPreparationActive`, `orchestratorState`.
10. `UzumeApp/Views/Playback/PerformanceBackdrop.swift` + `UzumeApp/DesignSystem/UzumeTokens+App.swift` §Over the performance frame — the vocabulary you have for drawing over a live frame, and the note that each number is a measured result.
11. `UzumeApp/Services/SettingsStore.swift` — the `@Published` + `didSet` encode pattern (`uzume.settings.<group>.<key>`); `uzume.settings.visuals.preparationView` from DS.4 is the model for the new preference.
12. `UzumeAppTests/ReviewCaptureHarness.swift` + `+Preparation.swift` + `+Ready.swift` — the capture harness; DS.6 adds a `chrome` set the same way DS.5 added `ready`.
13. `docs/DECISIONS.md` D-232, D-233, D-238, D-239, D-240 — via the §Index, not end to end.

## Pre-flight invariants

Each is a stop condition. A failed check ends the session with a report, not a workaround.

- **DS.5 is merged to `main`** ([#193](https://github.com/hoaxpoet/uzume/pull/193), squashed as `d4fb16ea`); `git status` clean on a branch fresh from `origin/main` — the primary checkout's local `main` was behind at the time of writing, so fetch first.
- **`Scripts/closeout_evidence.sh` is ALL GREEN before task 1.** In a worktree run `Scripts/link_fixtures.sh` first. The two `SpotifyConnectionViewModel` retry-backoff tests flake under full-suite load and pass in isolation — pre-existing, being fixed in a separate session; anything else red is a stop.
- **`Scripts/check_design_token_drift.sh` passes.**
- **`PresetContrastCertificationTests` passes on `main` before any change**, so a later failure is attributable.
- **One D-number is reserved** for the chrome decisions below. Next free is **D-241**; verify against `docs/DECISIONS.md` rather than trusting this line.

## Numbered tasks

1. **Capture the before-state.** Every reachable chrome state, rendered through the harness as a `chrome` capture set: streaming session (card with and without artwork), local-file session (card + transport, playing and paused), listening badge visible, background-preparation indicator visible, one toast per tone, the chrome mid-fade, and the chrome hidden. Record the declared VoiceOver labels and every `uzume.playback.*` identifier. Store under `docs/reviews/DS.6/before/`.
   **Done-when:** every reachable state has a capture; anything unreachable is named with the reason; the identifier list is in `CAPTURES.md`.

2. **Inventory what is off-token.** One table in `docs/reviews/DS.6/CAPTURES.md`: file, line, what it is (`Color.teal`, `.green.opacity`, `DashboardTokens.Color.surfaceRaised`, a hard-coded radius, a fixed font), and which token replaces it. Run the increment gates below against `main` so the table is complete before anything changes.
   **Done-when:** the table exists and the gates' output matches it row for row.

3. **Add the preference.** `uzume.settings.visuals.showTrackInformation`, following `SettingsStore`'s pattern exactly, default per §DECISION-NEEDED (3). Surface it in Settings beside the preparation-view preference, copy describing what the listener gets. **Its own commit.**
   **Done-when:** persists across launch; `SettingsStoreEnvironmentRegressionTests` passes; `Scripts/check_user_strings.sh` green.

4. **Retokenize `TrackInfoCardView`.** The pill loses `.green`/`.orange`; whatever survives §DECISION-NEEDED (1) is drawn in tokens. The card honours the new preference — hidden means the whole card, artwork included, is gone from the tree, not faded. Title, artist, artwork and the current preset stay exactly as they are.
   **Done-when:** no colour literal in the file; `PlaybackChromeArtworkBindingTests` and `PlaybackChromeIndexBindingTests` pass unchanged; `uzume.playback.trackInfoCard` and `.artwork` resolve unchanged.

5. **Retokenize the cluster, the dots, the badge, and the background-preparation indicator.** `PreparationBackgroundIndicator` drops `Color.teal` — it is a status, so it takes its tone from `StatusTone` (D-234) like every other status surface, not a colour of its own. `PlaybackControlsCluster` gains the Show/Hide track info control (the same bordered treatment DS.4a used, or an icon button with that label — decide by what fits a top-trailing cluster, and record it). Settings gear and End session stay.
   **Done-when:** the cluster carries three controls; `uzume.playback.controlsCluster`, `.progressDots`, `.listeningBadge` resolve unchanged; the new control has its own `uzume.playback.toggleTrackInfo` identifier and is pinned by `PlaybackViewIdentifierTests`.

6. **Finish `LocalFileTransportBar`.** Every `DashboardTokens` reference goes; surface, border, glow, glyph fills and hover fills come from `UzumeAppColor` / `UzumeAppColor.Performance` / `UzumeAppRadius`. The header's `.impeccable.md` and "coral is action" narrative is rewritten to the design system's rule (violet is the interaction accent). The custom glyph shapes and the callbacks stay.
   **Done-when:** `grep DashboardTokens` outside `Views/Dashboard/` returns nothing; the bar's hover and paused states render; `uzume.playback.lfTransport` resolves unchanged.

7. **Gone after a brief inactivity, back on any input — Matt's call, decided (§DECISION-NEEDED 2).** The chrome disappears completely after a brief period of inactivity so the listener can focus on the visuals; mouse movement or a tap on the screen brings all of it back (key press and track change as UX_SPEC §7.2 already promises). Keep the two-state model in `PlaybackChromeViewModel`; use the motion durations from `DESIGN.md` §Shared States and Motion (240 ms standard state change, exponential ease-out) instead of the current 500 ms — add app-side motion constants in `UzumeTokens+App.swift` with the same provenance comment style if the vendored tokens do not carry them. First show waits for `PlaybackArrivalOverlay` to finish. This deviates from `COMPONENTS.md`'s "cannot become undiscoverable" — record it in `docs/reviews/DS.6/UPSTREAM-FINDINGS.md` as a product decision for `uzume-site` to adopt, not as a gap.
   **Done-when:** `PlaybackChromeViewModelTests` covers the timings and every restore trigger (mouse, tap, key, track change); nothing remains on screen while hidden; reduced motion crossfades instead of animating.

8. **Reduced motion and VoiceOver.** `DESIGN.md`: reduced motion removes scale, parallax, autoplay, continuous animation; content appears immediately or through a native crossfade. Audit the pulsing progress dot and the listening badge against that. Every control the chrome carries has a label and a hint that says what it does *now* (CLAUDE.md's unmechanized rule: tooltips describe what a control does now).
   **Done-when:** the task 1 VoiceOver rows are matched or improved, never regressed; a test asserts the reduced-motion path renders the chrome without a repeating animation.

9. **Prove contrast held.** `PresetContrastCertificationTests` unchanged and green — the backdrop numbers did not move. If any new surface draws text over the live frame *without* `PerformanceBackdrop` (the quiet edge state is the candidate), extend the certification to it rather than asserting it by eye.
   **Done-when:** `git diff main -- <the certification test file>` is empty or is an extension, and the suite is green.

10. **HARD STOP — Matt's M7 review.** Retake every task 1 capture into `docs/reviews/DS.6/after/`, plus window-only live captures of a real streaming session and a real local-file session (the chrome full, quiet, and restored). `CAPTURES.md` pairs before/after by filename. **Present, stop, and report.** What Matt is judging: does the chrome read as Uzume's and not Phosphene's; is the quiet state discoverable; does the track card say only what is playing now.
    **Done-when:** every reachable state has a matched pair and Matt has seen them.

11. **Verification and closeout.** Run the full battery, then the `closeout` skill. No push without Matt's explicit approval.

## Do NOT

- **Do not create a `CuratorControlSurface` or any second control tree.** The single failing condition of this increment.
- **Do not leave anything on screen after the chrome hides.** No quiet glyph, no edge control — Matt's call. Discoverability is the mouse and the tap.
- **Do not change the numbers in `UzumeAppColor.Performance`** (`backdropTint`, `panelTint`, `toastTint`, `sheetScrim`, the fills). Each is a measured contrast result; changing one re-opens `PresetContrastCertificationTests`.
- **Do not expose upcoming content.** Nothing in the chrome names the next track, the next preset, a transition, or the shape of the plan. Heard-vs-will-do, as in DS.4/DS.5.
- **Do not touch `MetalView`, the `PlaybackView` layer order, `PlaybackArrivalOverlay`, `PlaybackShortcutRegistry`, `DefaultPlaybackActionRouter`, `PlaybackKeyMonitor`, or `ToastManager`.** The chrome is Layer 3; the rest of the stack is not in scope.
- **Do not change any existing `uzume.playback.*` identifier.** `PlaybackViewIdentifierTests` is the ratchet; extend it, never edit it.
- **Do not use `.teal`, `.green`, `.orange`, `.gray`, `Color.black`, `Color.white`, or `DashboardTokens`** in `Views/Playback/`. Gold is never control chrome (DESIGN.md).
- **Do not reach for `.ultraThinMaterial` alone** — always through `PerformanceBackdrop`, which is what was certified.
- **Do not add fixed font sizes** (`.system(size:`); the `DynamicTypeRegressionTests` ratchet lists these files.
- **Do not edit the `Views/Dashboard/` tree or `DashboardTokens` itself** — diagnostic-only chrome, out of scope (census: `QualityGradeIndicator` stays outside product chrome).
- **Do not write to `../uzume-site`.** Read it; report upstream findings in `docs/reviews/DS.6/UPSTREAM-FINDINGS.md` if any.

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

Phosphene's palette is out of the product chrome:

```
grep -rn "DashboardTokens" UzumeApp --include='*.swift' | grep -v "UzumeApp/Views/Dashboard/"
# expected: no output
```

No colour outside the token system in the chrome:

```
grep -rn "\.teal\b\|\.green\b\|\.orange\b\|\.red\b\|\.gray\b\|Color\.black\|Color\.white\|cornerRadius: [0-9]\|impeccable" \
  UzumeApp/Views/Playback
# expected: no output
```

Fixed fonts stay out:

```
grep -rn "system(size:" UzumeApp/Views/Playback
# expected: no output
```

Every pre-existing identifier survives:

```
for id in uzume.playback.chrome uzume.playback.trackInfoCard uzume.playback.trackInfoCard.artwork \
          uzume.playback.controlsCluster uzume.playback.progressDots uzume.playback.listeningBadge \
          uzume.playback.lfTransport uzume.view.playing; do
  grep -rq "\"$id\"" UzumeApp/Views/Playback || echo "MISSING $id"
done
# expected: no output
```

The contrast certification did not move:

```
git diff main --stat -- $(grep -rl "PresetContrastCertification" UzumeAppTests UzumeEngine/Tests | head -1)
# expected: empty, or additions only
```

## Commit message templates

`[DS.6] <component>: <description>` — small commits per logical step:

```
[DS.6] reviews: before-state captures and the off-token inventory
[DS.6] Settings: the listener shows or hides track information
[DS.6] TrackInfoCardView: tokens only, current track only
[DS.6] PlaybackControlsCluster: Show/Hide track info joins Settings and End session
[DS.6] PreparationBackgroundIndicator: a status takes its tone from StatusTone
[DS.6] LocalFileTransportBar: DashboardTokens out, the design system in
[DS.6] PlaybackChromeViewModel: quiet after inactivity, never gone
[DS.6] Accessibility: reduced motion and labels for every control
[DS.6] Tests: contrast certification extended to the quiet state
[DS.6] DECISIONS: D-<run-time fill> the performance chrome
[DS.6] reviews: DS.6 before/after M7 captures
```

Push only on Matt's explicit approval.

## Closeout format

Invoke the `closeout` skill; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions:

- Output of the increment gates above.
- The off-token inventory table with every row marked resolved.
- The identifier list, before and after, with the one addition.
- The VoiceOver rows before and after, and the reduced-motion behaviour described.
- Confirmation that the certification numbers did not move: the `git diff` above.
- The M7 page path and Matt's verdict in his own words.

## DECISION-NEEDED

**All three answered by Matt on 2026-09-03, before the session.** None is open.

1. **The orchestrator state pill on the track card ("Planned" / "Reactive").** **Remove it.** It
   reports the session's structure, which the surprise model treats as the listener's not to
   know; "Adapting" was never wired.
2. **What happens after inactivity.** Matt: *"Chrome should disappear completely after a brief
   period of inactivity so that the user can focus on the visuals. When mouse activity is
   detected or the user taps the screen, the chrome returns."* No quiet edge control. This is a
   deliberate deviation from `COMPONENTS.md`'s "cannot become undiscoverable" — record it as an
   upstream finding for `uzume-site` to adopt (task 7), not as a gap in the app.
3. **Track information — shown by default, persisted** as `uzume.settings.visuals.showTrackInformation`,
   same shape as the preparation-view preference.

If a further product-level question appears mid-session — one whose answer changes what the
listener sees or feels — **stop and bring it to Matt** rather than deciding it quietly.
Engineering choices remain Claude's.

## Notes for the next increment

DS.7 is `PerformancePreflight`, and the census is explicit that it comes **only after its
integration point and settings summary model are defined in the application** (§Migration order,
step 7). That definition is a design pass, not a prompt — it needs Matt before DS.7 is written,
the same way DS.4 and DS.5 did.
