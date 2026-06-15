# CLEAN Phase 2.4 — Kickoff: macOS entitlement + local threat-model review (GAP-10)

## Where things stand (as of 2026-06-15)

Phase 2's security spine is done and pushed: **CLEAN.2.1** removed the bundled Spotify client secret (PKCE), **CLEAN.2.2** hardened OAuth correctness, **CLEAN.2.3** closed the honest-UI dead controls (origin `7a011f2`). **2.4 is the last Phase-2 item** and the one remaining audit security finding: **GAP-10** (`docs/diagnostics/CODE_AUDIT_2026-06-13.md` line 182 + the **CLEAN.2.4** row ~line 225; the T15 security lane ~line 158 is the sibling, mostly closed by 2.1/2.2).

**This is a REVIEW + DOCUMENT increment, not a code increment.** The audit done-when is *"documented posture: tap PID scope, hardened-runtime/library-validation, notarization; fixes filed"* — produce a security-posture / threat-model document and **file** fixes. Do **not** flip signing/sandbox/hardened-runtime settings as part of this increment (see pitfalls) — those are tested, distribution-coupled changes that get filed, not applied blind.

**Governing context (CLAUDE.md Development Constraints):** macOS only, Mac mini primary dev/deploy target, **on-device only — no cloud, no telemetry**, MIT license, **no public build yet** (`RELEASE_NOTES_DEV.md` preamble). The minimal-exfiltration posture is a *strength* to document, not just a list of gaps.

## Current posture (VERIFIED 2026-06-14 — re-grep, paths/lines drift)

| Aspect | Current state | File |
|---|---|---|
| **App sandbox** | **OFF** — `com.apple.security.app-sandbox = false` is the *only* entitlement declared | `PhospheneApp/PhospheneApp.entitlements` |
| **Hardened runtime** | **Not enabled** — `ENABLE_HARDENED_RUNTIME` absent from the build settings (blocks notarization) | `PhospheneApp.xcodeproj/project.pbxproj` |
| **Code signing** | `CODE_SIGN_IDENTITY = "Apple Development"`, `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = 2LBTN9PB4Z` — dev-signed, **not Developer ID, not notarized** | `project.pbxproj` (~1214–1247) |
| **Library validation** | Not declared (no `com.apple.security.cs.disable-library-validation`) | entitlements |
| **Audio tap scope** | `.systemAudio` = **global tap, excludes nothing** (`CATapDescription(stereoGlobalTapButExcludeProcesses: [])`) → captures *all* system audio; `.application` = single PID (`stereoMixdownOfProcesses:[pid]`) | `PhospheneEngine/Sources/Audio/SystemAudioCapture.swift:278–301` |
| **Permissions (Info.plist)** | `NSScreenCaptureUsageDescription` (the tap is TCC-gated on screen-recording though **no video is captured**), `NSAppleEventsUsageDescription`, `NSAppleMusicUsageDescription`; `SpotifyClientID = $(SPOTIFY_CLIENT_ID)` (no secret — 2.1); `phosphene://` URL scheme (OAuth callback); LF audio/playlist document types | `PhospheneApp/Info.plist` |
| **Secrets at rest** | OAuth tokens in Keychain (2.1/2.2); `SPOTIFY_CLIENT_ID` injected from gitignored `Phosphene.local.xcconfig` | `Phosphene.xcconfig` |

## MANDATORY session setup (before writing the doc)

1. Be on latest `main` (CLEAN.2.3 = `7a011f2` or later). **Heads-up:** the DOC.6 EP-rotation gate is currently RED on `main` (pre-existing 2026-06-01 entries crossed the 14-day boundary; `task_60fa4558`) — if the pruning pass hasn't run yet, `closeout_evidence.sh` will show that one failure; it is **not** yours. Confirm it's the only red.
2. Read: this doc; `CODE_AUDIT_2026-06-13.md` G10 (~182) + T15 (~158); the seven files in the posture table above; `CLAUDE.md` §Development Constraints; `docs/RUNBOOK.md` §Spotify connector setup + the tap-install troubleshooting (Failed Approaches #21/#22 live at the `SystemAudioCapture` tap-install comment; #45–47 at the RUNBOOK Spotify section).
3. **Cited line numbers are from 2026-06-14 — re-grep, they will have shifted.** Each row names the *file/symbol*, not just a line.
4. This is doc-first: no new test file is expected. If a *trivial, tested* fix is applied (e.g. correcting an inaccurate Info.plist usage string), app-layer tests run via `xcodebuild -scheme PhospheneApp test`.

## The work — produce `docs/SECURITY_POSTURE.md` + file fixes

One new doc (suggested `docs/SECURITY_POSTURE.md`, referenced from `RUNBOOK.md` and the `ENGINEERING_PLAN` CLEAN.2.4 row — **not** added to the CLAUDE.md handbook index unless you free equal budget, per the D-161 ratchet). For each area: **state the verified current posture, the threat/rationale, and either the decision or a filed follow-up.**

| # | Area | Document | Likely outcome |
|---|---|---|---|
| 1 | **Global system-audio tap** | That `.systemAudio` captures the entire system mix (all apps), is TCC-gated (user-granted screen-recording permission), is **audio-only / no video**, and that `.application` mode narrows to one PID. The privacy surface + the user's consent gate. | Document (no fix — this is the product's core mechanism); confirm the `NSScreenCaptureUsageDescription` "No video is recorded" claim is honest vs. `SessionRecorder` (it records the *visualizer's* output, not the screen — verify and state plainly). |
| 2 | **App sandbox = off** | Why it's off (the global Core Audio tap + Apple Events to music apps + arbitrary file-open are incompatible with the App Sandbox), and whether *partial* sandboxing buys anything. | Document the rationale; **file** a follow-up only if partial sandboxing looks viable. |
| 3 | **Hardened runtime + notarization** | That neither is enabled, and that this blocks Gatekeeper-clean distribution outside the dev machine. What enabling hardened runtime would require (entitlements for the tap; verify the tap still installs under it). | **File** a CLEAN/BUG item to enable + test hardened runtime and notarize **when distribution is in scope** (gated on Matt's decision below). |
| 4 | **Library validation** | Whether `disable-library-validation` is needed (only if loading third-party/unsigned dylibs — Phosphene links Apple frameworks + SPM static libs, so likely not). | Document "not required"; no fix. |
| 5 | **`phosphene://` OAuth callback** | The URL-scheme attack surface and how CLEAN.2.2 already mitigates it (random `state` CSRF/replay guard, `scheme == phosphene` + host validation in `handleCallback`). | Document as mitigated; file a fix only if a gap is found. |
| 6 | **Local-file open path** | The parsing surface from opening arbitrary `.m4a/.mp3/.flac` + `.m3u/.m3u8` (AVFoundation decoders, the m3u parser) — what validates input, what the failure modes are. | Document; file a fix if input validation is thin. |
| 7 | **Secrets at rest + no-telemetry** | Keychain token storage (2.1/2.2) and the **no-cloud/no-telemetry** posture (minimal data-exfiltration surface). | Document (posture strength). |

## Decision for Matt (bring before writing the "fixes filed" priorities — product-level)

- **Distribution intent.** Does Phosphene stay **personal / dev-only on the Mac mini** for the foreseeable future, or is **eventual distribution** (sharing a notarized build, or a public release) on the roadmap? *Recommended default: personal/dev-only* — which makes hardened-runtime + notarization **documented-and-filed-as-future**, not near-term work, keeping 2.4 a review increment. If distribution is planned, 2.4 still only documents + files; the actual signing/notarization enablement + tap-under-hardened-runtime testing becomes its own follow-up increment (it touches the build/signing pipeline and needs a real Gatekeeper test). *User-visible framing:* "is anyone other than you going to run a downloaded Phosphene build?"

## Rules / pitfalls

- **Do not flip security build settings blind.** Enabling hardened runtime, turning on the sandbox, or switching to Developer ID can break the audio tap, the Apple Events bridge, or signing — each needs a build + a real run (tap installs, music apps reachable, Gatekeeper accepts). This increment **documents and files**; it applies only fixes that are trivial *and* verified (e.g. an inaccurate usage string). Scope creep into "enable hardened runtime" without the distribution decision + testing is the failure mode to avoid.
- **Verify before asserting.** Every posture claim (sandbox state, hardened-runtime flag, signing identity, tap scope) is one grep/read — confirm against the artifact, don't infer. The current-state table above is a starting point, not gospel; re-verify.
- **Never put a secret in a checked-in file** (`Phosphene.xcconfig` holds only the public client ID; the secret-free posture is CLEAN.2.1's whole point — don't regress it).
- **No new always-loaded rules.** Findings go in `docs/SECURITY_POSTURE.md`; do not expand CLAUDE.md (D-161 budget ratchet).

## Closeout

Standard protocol: `Scripts/closeout_evidence.sh` evidence block (annotate the known DOC.6 rotation-gate red + worktree engine-fixture caveat if either fires; **state explicitly that the increment is not visually verifiable and — if no code changed — that no tests were added**). Mark **GAP-10 reviewed** in the audit backlog / `KNOWN_ISSUES.md`; add any filed fixes as new CLEAN/BUG rows. `RELEASE_NOTES_DEV.md` entry; `ENGINEERING_PLAN.md` CLEAN.2.4 row (and note this closes Phase 2). Reference the new `docs/SECURITY_POSTURE.md`. **Push requires Matt's explicit "yes, push."**
