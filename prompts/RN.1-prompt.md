# Session prompt — RN.1

## Increment RN.1 — Rename: Phosphene → Uzume (external identity)

**Type:** infrastructure (identity/config/docs; no engine behavior changes).

**Objective.** After this session, the product is named **Uzume** everywhere a user, contributor, or the OS sees a name: app display name, bundle identifier, logger subsystems, custom URL scheme (if any), the Application Support hot-reload path, scripts' repo URLs, and all living documentation. Internal Swift module / target / directory / scheme names (`PhospheneApp`, `PhospheneEngine`, …) are **explicitly out of scope** — that is RN.2 (see DECISION-NEEDED). Frozen history (prompts/, existing DECISIONS entries, dead-ends, diagnostics, archive) is untouched. All suites green; the rename is recorded as a numbered decision.

Name provenance: Matt's decision 2026-08-09 after a five-round naming sprint (Latin vocabulary → Latin coinages → folk/firefly territory, where Hotarugari was provisionally picked → myth research on sound↔light interlocks, which surfaced Ame-no-Uzume — the kami whose planned, drummed performance lured the sun out of the cave — → confirmation pass: domains, US trademark classes, collision ranking all clear). Evidence lives in the naming report and myth-research docs from that session; the D-entry in Task 6 records the decision in-repo. Pronunciation: oo-ZOO-meh.

## Skill invocations

- `closeout` at the end (mandatory).
- No preset/shader/defect skills apply — no `.metal`, no sidecars, no BUG-*.

## Read-first file list

1. `docs/RUNBOOK.md` §Spotify connector setup — whether the PKCE redirect URI embeds a custom URL scheme or the bundle ID (determines Task 2's connector surface).
2. `docs/RUNBOOK.md` §Engineering notes — pbxproj four-section discipline (needed only if a config-file edit forces a project-file touch; RN.1 renames no files).
3. `PhospheneApp/Phosphene.xcconfig` — bundle ID / product settings; note warnings-as-errors is set here, do not disturb it.
4. `PhospheneEngine/Sources/Shared/Logging.swift` (locate exactly via `grep -rn "com.phosphene" --include="*.swift"`) — the engine logger subsystem(s) and the `Logging.session` convention.
5. `Scripts/fetch_weights.sh` and `Scripts/closeout_evidence.sh` — hardcoded `hoaxpoet/phosphene` URLs.
6. `docs/PUBLISHING.md` — maintainer cutover runbook; the repo-rename and weights-release-asset steps interact with Task 4.
7. `docs/UX_SPEC.md` §9.5 copy principles — governs any user-facing string edits in Task 3.

## Pre-flight invariants

- Matt has registered **uzume.io** (his confirmation in chat is the check). Not registered → stop; the name must be owned before it appears in a public repo. (uzume.com and uzume.app are both third-party — an active taiko ensemble and a parked registration respectively — deliberately NOT part of this plan; both are on watch/backorder.)
- Matt has renamed the GitHub repo to **hoaxpoet/uzume** (Settings → rename; GitHub auto-redirects old URLs, so nothing breaks in the window before this session). `git ls-remote origin` resolves. Not renamed → stop and ask; Task 4's URL updates would otherwise point at 404s.
- `main` checked out, clean tree, in sync with origin. Dirty or diverged → stop.
- `Scripts/test_fast.sh` green before any edit (baseline). Red → stop.
- ML weights release asset still downloads via `Scripts/fetch_weights.sh` against the renamed repo (redirect check). Fails → stop and report; the cutover in `docs/PUBLISHING.md` needs Matt before the sweep proceeds.

## Numbered tasks

1. **Inventory every occurrence of the old name.** `grep -rni --binary-files=without-match "phosphene" .` (excluding `.git`, `.build`) and separately `grep -rn "com\.phosphene"`. Classify each hit into: (a) OS-facing identifiers — bundle ID, logger subsystems, URL scheme, Application Support path; (b) user-visible strings; (c) repo URLs in scripts/docs; (d) living docs (README, CONTRIBUTING, CLAUDE.md, docs/ current sections, `.claude/skills/`); (e) frozen history — `prompts/`, `docs/prompts/`, existing `docs/DECISIONS.md` entries, `docs/HISTORICAL_DEAD_ENDS.md`, `docs/diagnostics/`, `archive/`, historical `ENGINEERING_PLAN.md` phase entries; (f) file/directory/target/module names (RN.2 scope — record, don't touch). **Done-when:** the classified inventory (category → file:line list) exists in session notes; categories (e) and (f) are explicitly marked no-touch.

2. **OS-facing identifiers.** Bundle ID `com.phosphene.app` → **`io.uzume.mac`** (reverse-DNS of the owned domain uzume.io; `com.uzume.*` and `app.uzume.*` are deliberately avoided because uzume.com and uzume.app both belong to third parties) — in the xcconfig/project settings, wherever PRODUCT_BUNDLE_IDENTIFIER lives. Logger subsystems `com.phosphene.*` → `io.uzume.*` (app-layer instantiations and `Shared/Logging.swift`; keep the `Logging.session`-is-engine-internal convention intact). Custom URL scheme per the RUNBOOK reading (if the Spotify PKCE redirect embeds one, rename it and update the RUNBOOK's registration instructions in the same commit). Application Support path `~/Library/Application Support/Phosphene/` → `.../Uzume/` — **clean break, no migration shim** (pre-beta, no users; dev machines move their hot-reload presets by hand — note this in RUNBOOK troubleshooting). **Done-when:** app + engine build; `grep -rn "com\.phosphene" --include="*.swift" --include="*.plist" --include="*.xcconfig" .` returns zero; `grep -rn "Application Support/Phosphene"` returns zero outside frozen history.

3. **User-visible name + icon.** Display/product name → **Uzume** (Info.plist keys / build settings as the project structures them — keep the `PhospheneApp` scheme and target names untouched, RN.2). Install the app icon produced by BRAND.1 (see that increment's closeout handoff note for the master's path; if BRAND.1 has not closed, stop — it is a pre-flight dependency of this task). Sweep externalized user-facing strings for "Phosphene"; `Scripts/check_user_strings.sh` stays green. The ScreenCaptureKit permission-prompt usage string must carry the new name — it is the single scariest dialog in onboarding and must not show a stale brand. **Done-when:** app builds; `Scripts/check_user_strings.sh` passes; a launched debug build shows "Uzume" in menu bar and About (manual check recorded at closeout).

4. **Scripts and repo URLs.** `hoaxpoet/phosphene` → `hoaxpoet/uzume` in `Scripts/fetch_weights.sh`, `Scripts/closeout_evidence.sh`, README badges/clone instructions, CONTRIBUTING, and any CI workflow files under `.github/`. **Done-when:** `Scripts/fetch_weights.sh` completes against the renamed repo; `grep -rn "hoaxpoet/phosphene"` returns zero outside frozen history.

5. **Living-docs sweep.** Categories (c)+(d) from the inventory: README, CONTRIBUTING, CLAUDE.md, current docs/ sections, `.claude/skills/` — product name, log-stream predicates (`subsystem == "io.uzume.presets"`), and the `tccutil` recovery line, which during the transition should reset **both** old and new IDs (`com.phosphene.app` grant is orphaned by the bundle-ID change; that's expected, document it once in RUNBOOK). CLAUDE.md edits respect the 7,000-token cap — this is a same-mass word swap, but run the `DocIntegrityTests` gate before committing. Frozen history stays frozen. **Done-when:** `swift test --package-path PhospheneEngine --filter DocIntegrityTests` green; the residual audit (verification section) shows only classified-allowed occurrences.

6. **Decision record + plan entries.** New `D-###` in `docs/DECISIONS.md` (next free number at session time — run-time fill, DOC.6 precedent): the rename, the naming-sprint evidence in one paragraph (collisions that killed Phosphene: same-platform OSS app + domain landscape; the five-round path to Uzume; what the confirmation pass showed — no software/music-class trademark, known neighbors ranked, uzume.io registered after uzume.app turned out parked), the bundle-ID rationale (`io.uzume.mac`, avoiding the third-party uzume.com and uzume.app namespaces), and the clean-break call from Task 2. `ENGINEERING_PLAN.md`: new `## Phase RN — Rename (Phosphene → Uzume)` header + RN.1 increment entry, RN.2 queued. `docs/RELEASE_NOTES_DEV.md` entry (`[dev-YYYY-MM-DD-HHMMSS]` UTC id — never hand-letter). **Done-when:** all three files updated; full suite green.

7. **Full verification battery, then stop.** Run the verification commands below, produce the residual-occurrence audit, and **stop and report** — no push. Publishing the rename (push + PR + Matt's repo-settings pass per `docs/PUBLISHING.md`) is Matt's explicit go, separate from this session's completion.

## Do NOT

- Do **not** rename files, directories, targets, modules, or the `PhospheneApp` scheme — no `project.pbxproj` restructuring. That is RN.2, its own increment (pbxproj churn isolated per the four-section discipline, RUNBOOK §Engineering notes).
- Do **not** touch `prompts/`, `docs/prompts/`, existing `docs/DECISIONS.md` entries, `docs/HISTORICAL_DEAD_ENDS.md`, `docs/diagnostics/`, `archive/`, or historical ENGINEERING_PLAN entries — history is frozen at its session date (prompts/README.md doctrine).
- Do **not** touch presets: no `.metal`, no `.json` sidecars, no `docs/VISUAL_REFERENCES/`.
- Do **not** add myth-themed UX copy, taglines, or vocabulary — no Iwato references, no "Pythagoras" onboarding persona, no "Omoikane" orchestrator codename in code or docs. The rename is mechanical; brand voice and persona work are their own future increments.
- Do **not** build an Application Support migration shim (clean break decided; recorded in the D-entry).
- Do **not** change the Milkdrop/projectM attribution posture or `docs/CREDITS.md` semantics — name swap only where the product name appears.
- Do **not** push. Local commits only until Matt's explicit "yes, push"; then branch + PR, never direct to `main` (fast-gate is the required check; the bypass line is a stop signal).

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test 2>&1
swift test --package-path PhospheneEngine 2>&1
swift test --package-path PhospheneEngine --filter DocIntegrityTests 2>&1
Scripts/check_user_strings.sh
```

Residual audit (attach output to closeout §2 evidence):

```
grep -rni --binary-files=without-match "phosphene" \
  --exclude-dir=.git --exclude-dir=.build . \
  | grep -vE "^(\./)?(prompts/|docs/prompts/|docs/diagnostics/|archive/|docs/HISTORICAL_DEAD_ENDS)" \
  | grep -v "docs/DECISIONS.md" | grep -v "docs/ENGINEERING_PLAN.md"
```

Expected: only category-(f) path/module occurrences (RN.2 scope) and any explicitly-allowed lines from the Task-1 inventory; every surviving line must appear in the closeout with its classification. Known-environment note: ~21 tempo-fixture tests need `Scripts/bootstrap_fixtures.sh` on a fresh clone; unrelated to this increment.

## Commit message templates

Small commits, one per logical step; local-only until Matt's explicit "yes, push":

```
[RN.1] Config: bundle ID + logger subsystems com.phosphene → io.uzume
[RN.1] App: display name Uzume; user-string sweep; permission-prompt copy
[RN.1] Scripts: repo URLs hoaxpoet/phosphene → hoaxpoet/uzume
[RN.1] Docs: living-docs sweep (README, CONTRIBUTING, CLAUDE.md, skills, RUNBOOK)
[RN.1] Docs: D-### rename decision + Phase RN plan entries + release notes
```

## Closeout format

Invoke the `closeout` skill; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions: (1) the Task-1 classified inventory; (2) the residual-audit output with per-line classification; (3) manual validation — launched build shows Uzume in menu bar + About; Screen Recording re-granted against `io.uzume.mac` (`tccutil reset ScreenCapture` on both old and new IDs first) and the tap captures audio; hot-reload directory `~/Library/Application Support/Uzume/Presets/` created on first launch and a drop-in preset hot-loads.

## DECISION-NEEDED

**Question:** After RN.1, should the code tree itself also be renamed (RN.2), or does "Phosphene" persist as an internal codename?

- **Option A — full internal rename (RN.2, before public beta).** A contributor cloning the repo sees Uzume everywhere: `UzumeEngine/`, `UzumeApp/`, matching scheme and test names. One-time churn in a follow-up increment; every doc path reference updates with it; `git log` history keeps the old names (harmless).
- **Option B — keep internal names indefinitely.** Contributors meet "Phosphene" in every file path, module import, and build command while the product is called Uzume — a permanent "why is it called that inside?" speed bump on exactly the audience the public repo courts, in exchange for never paying the rename churn.

**Recommendation:** Option A, queued as RN.2 immediately after RN.1 closes — pre-audience is the only cheap moment, same logic that justified the product rename itself.

**Default-if-no-reply:** Option A (RN.2 queued in the plan by Task 6; scheduled when Matt picks it up).
