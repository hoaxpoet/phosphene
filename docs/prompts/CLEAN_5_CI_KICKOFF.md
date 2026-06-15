# CLEAN Phase 5 — Kickoff: CI/CD fast gate on GitHub (CLEAN.5.1–5.3, +5.6)

## Decision already taken (Matt, 2026-06-15)

**Runner strategy = "fast gate on GitHub."** Every push/PR runs, on GitHub-hosted runners: a full **build** of app+engine, **swiftlint --strict**, the **doc gates**, the **user-string + sample-rate lint scripts**, and a reliable subset of **GPU/fixture-independent logic tests** — required-green on `main`. The **heavy GPU + licensed-fixture + perf-timing suite stays the manual `Scripts/closeout_evidence.sh` gate** (what we run at increment closeout today). This was chosen over self-hosting on the Mac mini and over running the full suite on GitHub.

**Why not the full suite in CI** (the three constraints that make "just run everything on GitHub" the worst option):
1. **74 test files create a Metal device** (`MTLCreateSystemDefaultDevice()`, throwing `noMetalDevice` on failure — they fail, not skip, without a GPU). GitHub `macos-14` runners are Apple-Silicon and *probably* expose Metal, but it's unproven and VM-headless.
2. **The tempo fixtures are licensed** (`.gitignore:56` — "preview clips are licensed; do not commit"). They can't live in the repo; `fetch_tempo_fixtures.sh` re-pulls them from the iTunes Search API, which is network-flaky and breaks the `sha256(of: love_rehab.m4a) matches` exact-bytes test on any re-encode.
3. **Perf-timing tests flake on shared hardware** — the CLEAN.7.9/7.10/7.11 class (single-sample wall-clock assertions inflate under CI contention).

## Current state (VERIFIED 2026-06-15 — re-check, things drift)

| Aspect | State |
|---|---|
| Existing CI | **None** — `.github/workflows/` does not exist. |
| Build commands | `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` (app+engine) · `swift test --package-path PhospheneEngine` (engine) · `xcodebuild … test` (app). |
| Lint | `swiftlint lint --strict --config .swiftlint.yml`. |
| Scripts 5.3 wires (all EXIST) | `Scripts/check_user_strings.sh` (80 ln), `Scripts/check_sample_rate_literals.sh` (125 ln), `DocIntegrityTests` (`swift test --filter DocIntegrityTests`). |
| Fixtures | `PhospheneEngine/Tests/Fixtures/tempo/` gitignored; `Scripts/fetch_tempo_fixtures.sh` re-pulls 3 clips (love_rehab/so_what/there_there) via iTunes Search API (no credentials). |
| LFS | **492 LFS files** (ML weights `PhospheneEngine/Sources/ML/Weights/**/*.bin` + reference images). A correct build bundles the weights → CI checkout needs `lfs: true`. |
| Signing | App target signs `Apple Development` (team `2LBTN9PB4Z`); **CLEAN.2.5a put hardened-runtime on the Release config only**. CI builds Debug with signing **disabled** (`CODE_SIGNING_ALLOWED=NO`) — it's not shipping an artifact, so HR/signing never bite CI. |
| Closeout Step-4 bug | `closeout_evidence.sh` prints `Executed 0 tests, with 0 failures` for `DocIntegrityTests` because they're **swift-testing**, not XCTest — the XCTest aggregate matches nothing and the parser surfaces the misleading line alongside the real `Test run with 10 tests … passed`. |

## Scope

**In:** CLEAN.5.1 (CI pipeline), 5.2 (fixture bootstrap — CI + local worktrees), 5.3 (wire the lints + DocIntegrity + fix the Step-4 report), 5.6 (reconcile RUNBOOK / release-checklist with the real gate structure). **Out (stretch, later):** 5.4 (build reproducibility / toolchain pin), 5.5 (ML-weight sha256 load gate).

**Explicitly NOT in CI** (stays manual `closeout_evidence.sh`): the 74 GPU/Metal tests, the licensed-fixture tests (BeatThis / tempo / live-drift / identity), and the perf-timing assertions. The loud-on-missing-fixture rule (BeatThisFixturePresenceGate) is **deliberate** and must stay loud **locally** — do not weaken it into a silent skip; CI simply doesn't run those suites.

## The work

### CLEAN.5.1 — GitHub Actions fast-gate workflow
A `.github/workflows/ci.yml` on `push` + `pull_request`, `runs-on: macos-14`, `actions/checkout` with `lfs: true`:
1. **Build** — `xcodebuild build` (app, `CODE_SIGNING_ALLOWED=NO`) + `swift build --package-path PhospheneEngine`. Catches the #1 regression class (compile breaks) with no GPU.
2. **SwiftLint** — `swiftlint lint --strict`.
3. **Logic tests** — the GPU/fixture-independent subset (see the **test-subset decision** below).
4. Make it a **required status check** on `main` (branch protection — Matt does the GitHub-settings click; the workflow existing is the code half).

**Done-when:** workflow green on `main`; required check configured; a deliberately-broken PR (compile error or lint violation) goes red.

#### Test-subset decision (the one real design choice inside 5.1)
The engine + app test targets interleave pure-logic and GPU/fixture tests. Two viable mechanisms — **recommend starting lean, widen empirically:**
- **Option A (lean allow-list, recommended for v1):** run an explicit `swift test --filter` allow-list of known GPU/fixture-free suites (OAuth, concurrency-probe, DSP-pure, metadata, DocIntegrity, …) + the doc gate. Rock-solid, ~3–5 min, zero per-test changes. Under-covers (new pure-logic suites must be added to the list — document this in the workflow).
- **Option B (broad skip-list, evaluate as follow-up):** run the full suite on `macos-14` and CI-gate-skip only the fixture suites + perf tests (a small set, not 74 files), via a shared `try skipInCI("reason")` helper that throws `XCTSkip`/swift-testing-skip **only when `ProcessInfo…["CI"]=="true"`** (preserves loud-local-failure). More coverage, but depends on GitHub-M1 Metal being present + non-flaky — prove that empirically before relying on it.

First implementing session: land Option A to get a reliable required-check fast; spike Option B (does `macos-14` have a Metal device? do the GPU suites pass there?) and report before committing to it.

### CLEAN.5.2 — Fixture bootstrap (local worktrees + CI)
- **Local worktrees (the part that bit us today):** a helper — `Scripts/bootstrap_fixtures.sh` or a check in `closeout_evidence.sh` — that, when `PhospheneEngine/Tests/Fixtures/tempo/` is empty, restores it: **prefer `cp` from the primary checkout** (`/Users/…/phosphene/PhospheneEngine/Tests/Fixtures/tempo/*`, byte-identical → passes the sha256 test) and fall back to `fetch_tempo_fixtures.sh`. **Done-when:** a fresh worktree's engine suite is green without a manual copy step.
- **CI:** the fast gate doesn't run fixture tests (per scope), so CI needs no fixtures. If Option B is later adopted, fixtures are CI-skipped, not fetched. (Note in the brief, not built.)

### CLEAN.5.3 — Wire the existing gates + fix Step-4 reporting
- Add `Scripts/check_user_strings.sh` and `Scripts/check_sample_rate_literals.sh` as CI steps (both are standalone shell scripts today, run only ad-hoc).
- Add `swift test --filter DocIntegrityTests` as a CI step (it's in `closeout_evidence.sh` but not enforced on push/PR).
- **Fix `closeout_evidence.sh` Step-4:** prefer the swift-testing summary (`Test run with N tests … passed`) over the XCTest aggregate (`Executed 0 tests`) when the latter is zero, so the block stops printing a misleading "0 tests." Keep the honesty contract (no invented counts).

### CLEAN.5.6 — Doc reconcile
Update `docs/RUNBOOK.md` (and any release checklist) so the documented gate structure matches the real one: the CI fast gate (what's enforced on push/PR) vs the manual `closeout_evidence.sh` full gate (GPU + fixtures + perf). State plainly which checks are automated and which stay manual.

## Rules / pitfalls
- **Disable signing in CI** (`CODE_SIGNING_ALLOWED=NO` or `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`) — there's no Developer cert in the CI keychain and CI isn't shipping an artifact. Don't import signing certs into CI for a build-only gate.
- **`lfs: true` on checkout** — the build bundles the ML weights; LFS-pointer files would produce a broken bundle. Watch LFS bandwidth (492 files); cache where possible.
- **Don't weaken the loud-on-missing-fixture rule locally** — CI-gated skips must check `CI==true`, never resource-absence (resource-absence must still fail loud on a dev box, per CLEAN.0 / the no-silent-skip rule).
- **No secrets in CI for the fast gate** — it needs none (no Spotify client ID, no signing). Keep it that way; if Option B ever fetches fixtures, the iTunes API needs no auth either.
- **Warnings-as-errors is per-target via `Phosphene.xcconfig`** — do NOT add `-warnings-as-errors` on the CI command line (conflicts with the SPM deps' `-suppress-warnings`, per `CLAUDE.md`).
- **Match the macOS image to the deployment target** — `macos-14` (Sonoma; deployment target is 14.0+).

## Closeout (per CLAUDE.md Increment Completion Protocol)
- `Scripts/closeout_evidence.sh` block (run from the **primary checkout** or a fixture-bootstrapped worktree so engine Step 1 is green, per CLEAN.5.2 / [[project_worktree_engine_fixtures_absent]]). The CI run itself is additional evidence — link the green Actions run.
- Not visually verifiable — state so.
- Update `docs/ENGINEERING_PLAN.md` (CLEAN.5.1/5.2/5.3/5.6 rows → done), `docs/diagnostics/CODE_AUDIT_2026-06-13.md` Part C Phase 5 rows, `docs/RELEASE_NOTES_DEV.md`, and `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` only if a certification/harness capability changes (it doesn't — note N/A).
- Prefer small commits (workflow; bootstrap script; lint-wiring; Step-4 fix; doc reconcile). **Push requires Matt's "yes, push."**
