# CLEAN Phase 5 — Kickoff: build reproducibility — pin toolchain + Package.resolved + LFS-present check (CLEAN.5.4, +5.7 SHA-pin)

## Why this is next (and no longer hypothetical)

CLEAN.5.1 stood up the GitHub fast gate — and it took **three runs to go green, every red caused purely by an unpinned tool version differing from the dev box:**

1. **Run #1 (`macos-14`) red** — the runner's newest Xcode was **16.2 / Swift 6.0.3**, whose SDK does **not** mark Metal protocol types (`MTLDevice`/`MTLCommandQueue`/`MTLRenderPipelineState`) `Sendable`; the dev box (Xcode 26.5) does. 18 `non-sendable type 'any MTL…'` errors. Fixed by `runs-on: macos-26`.
2. **Run #2 (`macos-26`) red** — `macos-26` ships **no preinstalled swiftlint**, so the workflow's `|| brew install swiftlint` fallback pulled **latest 0.63.3**, while dev runs **0.63.2**. 0.63.3 stopped flagging `URL(string: <literal>)!` as `force_unwrapping`, turning two `// swiftlint:disable:next force_unwrapping` into `superfluous_disable_command` errors. Worked around in-code (`#require`), but the **version gap is the real defect**.
3. **Run #3 green.**

Both reds are the same class: *"the build/lint behaves differently because the tool version in CI differs from dev."* That is exactly what 5.4 pins. The cost was a half-day of push-iterate-diagnose; pinning makes the toolchain a known, declared quantity so the next contributor (or runner-image bump) doesn't rediscover this.

## Current state (VERIFIED 2026-06-15 — re-check, things drift)

| Aspect | State |
|---|---|
| Xcode (dev) | **26.5** (Build 17F42, Swift 6.3.2), target arm64-apple-macosx26.0. |
| Xcode (CI) | `macos-26` newest = **26.5** (same as dev — good, but unpinned: the workflow's `Select Xcode` step just `sort -V \| tail -1`s `/Applications/Xcode_*.app`, so a future image that adds 26.6/27 silently changes the build compiler). No `.xcode-version` / `.swift-version` file exists. |
| SwiftLint (dev) | **0.63.2**. |
| SwiftLint (CI) | brew-installs **latest each run** (0.63.3 now) — `macos-26` has no preinstall, so the `\|\| brew install swiftlint` fallback always fires. Unpinned + slow (~30 s install/run) + the run-#2 drift source. |
| `Package.resolved` | **Gitignored** (`.gitignore:31`). Exists locally at `PhospheneEngine/Package.resolved`. The 4 SPM deps float on `from:` — `swift-argument-parser ≥1.3.0`, `swift-collections ≥1.1.0`, `swift-numerics ≥1.0.0`, `swift-async-algorithms ≥1.0.0` — so CI resolves transitive versions fresh on every run (not reproducible). |
| LFS | **492 LFS files** (`.gitattributes`): ML weights `PhospheneEngine/Sources/ML/Weights/**/*.bin` + reference images. Weights currently real (2 KB each). CI checkout uses `lfs: true`. **No check that LFS actually smudged** — a pointer-file build would "succeed" and bundle garbage. |
| `actions/checkout` | **@v6** (CLEAN.5.7, Node 24). Pinned to the major tag, **not** a SHA. |

## Scope

**In:** CLEAN.5.4 — declare and enforce a reproducible build environment along four axes (Xcode, SwiftLint, SPM deps, LFS) + fold in **5.7's** SHA-pin of the GitHub Actions. **Out:** the full-suite-in-CI question (Option B — separate, needs the Metal-on-runner spike); the ML-weight `sha256` load gate (that's **CLEAN.5.5**); changing the deployment target (stays macOS 14.0 — this is purely about the *build* toolchain).

## The work

### 5.4a — Pin the Xcode version
Declare the expected Xcode and stop "newest wins." Two viable mechanisms — **recommend the explicit-version-with-fallback:**
- Add a repo-root **`.xcode-version`** file (e.g. `26.5`) as the single source of truth, and have the workflow's `Select Xcode` step select `/Applications/Xcode_$(cat .xcode-version).app` (failing loud if absent) instead of `tail -1`. Document the same version as the dev requirement in `RUNBOOK.md §Preconditions` (currently says "Xcode 16+", now stale — the Metal-`Sendable` SDK is the real floor).
- **Decide pin granularity (a product-ish call, surface it):** exact (`26.5`) = maximally reproducible but breaks when the image rotates the point release; major (`26`) = survives image bumps but allows 26.x compiler drift. Given the run-#1 lesson, recommend exact with a documented "bump here when the image moves" pointer.

**Done-when:** the workflow selects a declared Xcode (not "newest"); a wrong/missing version fails loud with a clear message; `RUNBOOK` Preconditions states the real floor (Xcode 26 SDK for Sendable Metal), not "16+".

### 5.4b — Pin the SwiftLint version
Stop `brew install`-ing latest. Pin CI to the dev version (or deliberately bump both to one chosen version — **align dev + CI on a single number**). Mechanisms, lightest first:
- Download the exact release binary in the step (`https://github.com/realm/SwiftLint/releases/download/<ver>/portable_swiftlint.zip`) — deterministic, no brew, fast.
- Or the `realm/SwiftLint` action with a version input.
- Or a pinned brew formula (awkward for old versions).

Whatever's chosen: **one declared version, used by CI; documented as the dev version too.** Note the run-#2 in-code `#require` fix already removed the offending disables — but a future swiftlint bump will drift again until this lands.

**Done-when:** CI runs a declared SwiftLint version (no `brew install swiftlint` of latest); the version is documented as the contributor requirement; bumping is a one-line, intentional change.

### 5.4c — Commit `Package.resolved` + fail on drift
Un-gitignore `PhospheneEngine/Package.resolved` and commit it (standard for an app, not a library — pins transitive dep versions). Make CI resolution **fail on drift** rather than silently re-resolve (`xcodebuild -disableAutomaticPackageResolution` with the resolved file present, and the `swift build` equivalent — verify the exact flags for the toolchain).

**Done-when:** `Package.resolved` is tracked + committed; a dep-graph change that isn't reflected in it fails CI rather than silently resolving to new versions.

### 5.4d — LFS-present fast check
A check — local + CI, run **before** the build — that fails loud if any LFS-tracked file is still a pointer (LFS didn't smudge). Cheap forms: assert a known weight's size is > the ~130 B pointer size, or `git lfs status` / `git lfs ls-files --size` shows objects present. Must **fail loud** (no silent skip — CLEAN.0 / no-silent-skip rule); a pointer-file build bundles garbage and "passes."

**Done-when:** a checkout with un-smudged LFS fails fast with a clear message, before wasting a full build.

### 5.4e — SHA-pin the Actions (folds in 5.7)
`actions/checkout@v6` → pin to the v6.0.x **commit SHA** (with a `# v6.0.x` comment) for supply-chain reproducibility. Document the bump procedure. This closes the "@major-tag silently moves" gap for the one third-party action in the workflow.

**Done-when:** every `uses:` is SHA-pinned with a version comment; bumping is intentional.

## Rules / pitfalls
- **The dev box and CI must agree on Xcode AND SwiftLint** — that agreement *is* the increment. Pin to what dev runs (Xcode 26.5, SwiftLint 0.63.2), or deliberately bump both together to a chosen newer version. Don't pin one side only.
- **Don't pin so tight that routine image rotation reds CI** — if you pin `Xcode_26.5` exactly and `macos-26` later drops it, CI breaks on an unrelated push. Document the version + the one-line bump location; treat an image-rotation red as "go bump the pin," not a code regression.
- **`brew install <tool>` always gets latest** — that's the trap that bit run #2. Any tool CI needs must be version-declared, not latest-installed.
- **LFS check fails LOUD** — never a silent skip (CLEAN.0). Resource-absence still fails on a dev box.
- **Committing `Package.resolved`** pins transitive deps; make sure *both* `xcodebuild` and `swift build` honor it (don't let one silently re-resolve).
- **Deployment target is not in scope** — it stays macOS 14.0 (pbxproj / `Package.swift`). 5.4 is about the *build SDK/toolchain*, which is a different axis (the brief that conflated them is what caused run #1).
- **Warnings-as-errors stays in `Phosphene.xcconfig`** — do not add it to the CI command line (per `CLAUDE.md`).

## Closeout (per CLAUDE.md Increment Completion Protocol)
- `Scripts/closeout_evidence.sh` block (from the primary checkout or a fixture-bootstrapped worktree). Link the green CI run as additional evidence.
- Not visually verifiable — state so.
- Update `docs/ENGINEERING_PLAN.md` (CLEAN.5.4 row → done; 5.7 → folded), `docs/diagnostics/CODE_AUDIT_2026-06-13.md` Part C Phase 5 rows, `docs/RELEASE_NOTES_DEV.md`, and `RUNBOOK.md §Preconditions` (the stale "Xcode 16+"). `RENDER_CAPABILITY_REGISTRY.md` — N/A (no certification/harness capability changes).
- Prefer small commits (Xcode pin; SwiftLint pin; Package.resolved; LFS check; Actions SHA-pin). **Push requires Matt's "yes, push."**

## After this
CLEAN.5.5 (ML-weight `sha256` load gate) is the last Phase 5 item. Then Phase 5 is fully closed and the elevated gaps (G1 device-swap, G9 flash-safety) / Phase 3 P2-hardening are the queue.
