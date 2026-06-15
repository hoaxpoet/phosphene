# CLEAN Phase 2.3 — Kickoff: Wire-or-hide dead UI (+ close the localization-gate bypass)

## Where things stand (as of 2026-06-14)

CLEAN.2.2 (Spotify OAuth correctness) landed, was verified by Matt, and is pushed (origin `232b9be`). Phase 2's security spine is done; **2.3 is the honest-UI increment.** The app currently ships several controls that are visible but do nothing (or lie about their state), plus a string-localization gate that only covers half the UI. None of these crash — they're trust/quality defects flagged by the audits (`docs/diagnostics/CODE_AUDIT_2026-06-13.md` **T5** + the Phase-2 **CLEAN.2.3** row; `CODE_AUDIT_2026-06-09.md` Honest-UI bugs).

**Governing rule (codebase doctrine):** a control that isn't wired gets **hidden**. CLAUDE.md handbook index — "tooltips describe what a control does *now* — hide unwired controls behind a build flag"; UX_SPEC §"No playback controls" — "any 'pause' button would be a lie." So the **default remedy for each dead control below is hide/remove**; **wire** is the alternative only where Matt wants the feature visible now and it's cheap.

## MANDATORY session setup (before any code)

1. Be on latest `main` (CLEAN.2.2 = `232b9be` or later).
2. Read: this doc; `CODE_AUDIT_2026-06-13.md` row **CLEAN.2.3** (~line 224) + lane **T5** (~lines 102–104); `CODE_AUDIT_2026-06-09.md` Honest-UI bugs (~lines 164–177); `docs/UX_SPEC.md` §9 copy principles + the honest-copy examples; `CLAUDE.md` §"What NOT To Do" + the UX-contract handbook row.
3. **Cited line numbers are from 2026-06-14 — re-grep, they will have shifted.** Each item names the *symbol*, not just the line.
4. App-layer work: tests run via `xcodebuild -scheme PhospheneApp test` (engine `swift test` won't see them). A NEW test file must be registered in all four `project.pbxproj` sections (`docs/RUNBOOK.md` §Engineering notes).

## The work (suggested 4 sub-increments)

Each: confirm the wire-vs-hide call with Matt (recommendation + default below), implement, add/adjust the regression test, closeout green.

| ID | Dead control | Where (verify by grep) | Recommended default | Done-when |
|---|---|---|---|---|
| **2.3.1** | **"Use Apple Music instead" footer button is a no-op** on the Spotify connect screen. The *reverse* link (`onUseSpotifyInstead`, Apple Music screen) IS wired — so this is an asymmetric dead end. | `ConnectorPickerView.swift:149,223` — both Spotify-view construction paths pass `onUseAppleMusicInstead: { }` | **Wire** — restore symmetry by mirroring how `AppleMusicConnectionWrapper` threads `onUseSpotifyInstead` to navigate the picker. Hide only if Matt doesn't want the cross-link. | The button navigates to the Apple Music connector (or is gone); no `{ }` handler ships. Test asserts the nav/VM action, not an empty closure. |
| **2.3.2** | **Settings "Local file" capture mode lies + no-ops.** Shows "coming in a future update" though LF.4–LF.6 shipped; selecting it returns without touching the router (per **D-052**). | `AudioSettingsSection.swift:41–45` (`settings.audio.local_file.coming_later`); `CaptureModeSwitchCoordinator.swift:86–90` (`if … == .localFile { return }`) | **Remove** the `.localFile` radio option — local-file playback is reached by *opening a file* (LF.5 file-association / recents), so this Settings mode is vestigial. Retire the "coming later" string. **Touches D-052 → update the decision.** | `.localFile` no longer offered as a capture mode (or is genuinely wired to switch source); no false "coming later" copy. `CaptureModeSwitchCoordinatorTests` / `SettingsStoreEnvironmentRegressionTests` updated. |
| **2.3.3** | **"Swap preset" context-menu item is a disabled stub** — `Button(…){}` + `.disabled(true)`, `TODO(U.5.C)` until the U.5b preview loop. Greyed (honest-ish) but still dead weight. | `PlanPreviewRowView.swift:84–86` | **Hide** behind a build flag until U.5b — keep the existing `PlanPreviewViewModel.swapPreset` + `onSwap` plumbing, just don't render the dead button. | The disabled button no longer ships in the context menu; U.5b re-enables via the flag. |
| **2.3.4** | **Localization gate only scans `PhospheneApp/Views/`** — hardcoded user-facing English in ViewModels/ContentView/indirection helpers bypasses it. | `Scripts/check_user_strings.sh:21–23` (`ROOTS`). Verified sites: `SpotifyConnectionViewModel:269,303,305`, `AppleMusicConnectionViewModel:142–151`, `ReadyViewModel:88,162–171`, `ContentView:194–197`, `ConnectorType.swift`, `TrackInfoCardView:135`, `PlanPreviewTransitionView:30–44`, `PreparationProgressView:234–237`, `TrackPreparationRow.swift` | **Widen + externalize** (no wire/hide choice). Add ViewModels + ContentView (+ the indirection helpers) to `ROOTS`; move each caught string into `Localizable.strings`. | `check_user_strings.sh` scans ViewModels/ContentView and **passes**. Largest chunk — land it as its own commit, and consider promoting it to a standalone CLEAN.2.3.4 increment. |

## Decisions for Matt (bring before implementing — product-level: recommendation + default, framed as what the user sees)

- **2.3.1 Apple Music cross-link** — *Recommended: wire* (symmetry; the reverse direction already works). *User-visible:* on the Spotify connect screen, does "Use Apple Music instead" take you to the Apple Music connector, or disappear entirely?
- **2.3.2 Local-file capture mode** — *Recommended: remove the option* (LF is reached by opening a file, not a Settings toggle). *User-visible:* does Settings → Audio still list "Local file" as a capture mode at all?
- **2.3.3 Swap-preset stub** — *Recommended: hide until U.5b.* *User-visible:* is there a greyed-out "Swap preset" item in the plan-preview right-click menu, or nothing until the feature ships?

(2.3.4 has no product choice — it's a gate fix.)

## Rules / pitfalls

- **Honest-UI default is hide, not wire.** Don't expand scope by *building a feature* to justify a control. Wire only what Matt wants live now and that is cheap (2.3.1).
- **"Hide" = remove the control, or gate it behind a build flag.** Near-term feature (swap-preset / U.5b) → prefer a flag and keep the plumbing. Vestigial control (LF capture mode) → prefer removal.
- **D-052 (2.3.2)** is the "`.localFile` shows a coming-later toast, doesn't touch the router" decision — removing the mode supersedes it. Update `DECISIONS.md` (+ its §Index) in the same commit; don't leave the decision dangling (doc-drift gate `DocIntegrityTests` will catch an orphaned D-number).
- **String externalization (2.3.4):** every user string lands in `Localizable.strings` with a key; `check_user_strings.sh` (widened) + `SettingsStoreEnvironmentRegressionTests` are the enforcement — run both.
- **Manual UX walk required.** Honest-UI changes are user-facing chrome: walk the connector picker and the Settings → Audio section end-to-end (Matt, or via the preview harness). Unit tests prove the wiring; only the walk proves the control now reads honestly. Per CLAUDE.md, UX-flow changes don't rely solely on VM unit tests.

## Closeout (per sub-increment)

Standard protocol: `Scripts/closeout_evidence.sh` evidence block (ALL GREEN — annotate the known worktree engine-fixture-absence caveat if you run it from a worktree); mark the AUDIT-2026-06-09 honest-UI items Resolved in `KNOWN_ISSUES.md`; `RELEASE_NOTES_DEV.md` entry; `ENGINEERING_PLAN.md` CLEAN.2.3 row. The `check_user_strings.sh` widening (2.3.4) is itself a permanent gate — its passing IS the regression guard. **Push requires Matt's explicit "yes, push."**
