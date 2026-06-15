# CLEAN Phase 2.5 — Kickoff: enable hardened runtime + Developer ID signing + notarization (GAP-10 fix)

## Where things stand (as of 2026-06-15)

CLEAN.2.4 **documented** the security posture (`docs/SECURITY_POSTURE.md`) and **filed this increment as the fix** for the hardened-runtime / notarization half of audit **GAP-10**. The relevant reading is `SECURITY_POSTURE.md` **§3** (hardened runtime + notarization — the posture + the filed-fix rationale), plus **§1** (the system-audio tap) and **§4** (library validation).

**Matt's decision (CLEAN.2.4, 2026-06-15): eventual distribution is on the roadmap** → this is **near-term**, not indefinitely deferred. Phase 2 is otherwise complete (2.1–2.4 + the 2.3.x follow-ups on origin/main); this is the one filed Phase-2 follow-up that touches the build/signing pipeline.

**THIS IS A BUILD/SIGNING INCREMENT — NOT doc-only.** Unlike 2.4 (which deliberately did *not* flip settings), 2.5 is exactly the increment where the flips happen. The 2.4 rule "do not flip security build settings blind" is now being undertaken **deliberately, with a build + a real run behind every change.** Enabling hardened runtime can break the audio tap or the Apple Events bridge; switching to Developer ID + notarization can break signing — each needs a build **and a real run on the Mac mini** (tap installs and delivers audio, music apps reachable, Gatekeeper accepts a notarized build).

**Governing context (CLAUDE.md Development Constraints):** macOS only, Mac mini primary dev/deploy target, **on-device only / no telemetry**, MIT license, **no public build yet** — so the *distribution* this unblocks is "a notarized build you can hand to someone," not an App Store submission.

## Current posture (VERIFIED 2026-06-15 — re-grep, paths/lines drift)

| Aspect | Current state | File |
|---|---|---|
| **Hardened runtime** | **OFF** — `ENABLE_HARDENED_RUNTIME` absent from the build settings (0 hits) | `PhospheneApp.xcodeproj/project.pbxproj` |
| **Code signing** | `CODE_SIGN_IDENTITY = "Apple Development"`, `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = 2LBTN9PB4Z` — **dev-signed, NOT Developer ID, NOT notarized** | `project.pbxproj` (~1191–1220) |
| **Entitlements** | only `com.apple.security.app-sandbox = false` declared | `PhospheneApp/PhospheneApp.entitlements` |
| **Library validation** | not declared (it is **on by default** once hardened runtime is enabled — keep it on; see §4) | entitlements |
| **Bundle ID** | `com.phosphene.app` (app), `com.phosphene.app.tests` (tests) | `project.pbxproj` |
| **The tap** | global Core Audio process tap (`AudioHardwareCreateProcessTap`), **TCC-gated on screen-recording** (no entitlement) | `PhospheneEngine/Sources/Audio/SystemAudioCapture.swift` |
| **Apple Events** | `NSAppleEventsUsageDescription` declared; the music-app now-playing metadata bridge uses Apple Events | `PhospheneApp/Info.plist` |

## MANDATORY session setup

1. **Confirm the prerequisites with Matt FIRST (see Decision).** This increment is **BLOCKED at steps 4–6 without an Apple Developer Program membership + notarization credentials** — do not start the signing/notarization work until they're confirmed. (Steps 1–3, hardened-runtime-only, *can* proceed independently — see the Decision's "split" option.)
2. Be on latest `main`. Read: this doc; `docs/SECURITY_POSTURE.md` §3 (+ §1 tap, §4 library validation, §2 why sandbox stays off); `PhospheneApp/PhospheneApp.entitlements`; the `project.pbxproj` signing region; `PhospheneApp/Phosphene.xcconfig` (the per-target warnings-as-errors pattern — mirror it if scoping HR to the app target); `CLAUDE.md` §Development Constraints; `docs/RUNBOOK.md` tap-install troubleshooting (Failed Approaches #21/#22 at the `SystemAudioCapture` tap-install comment).
3. **Re-verify the posture table** — every row is one grep/read; paths/lines have drifted since 2026-06-15.

## The work — flip the settings, then VERIFY each on a real run

| # | Step | Detail | Verify (real run, Mac mini) |
|---|---|---|---|
| 1 | **Enable hardened runtime** | `ENABLE_HARDENED_RUNTIME = YES` for the app target (mirror the `Phosphene.xcconfig` per-target scoping so it doesn't propagate to SPM deps). | App **builds AND launches** under HR. |
| 2 | **Tap under hardened runtime** | The global process tap is TCC-gated, not entitlement-gated — it *should* survive HR. Add a `com.apple.security.cs.*` entitlement **only if a real run shows it break** (don't add speculatively). | Tap installs + delivers audio in a real playback session; visuals react. |
| 3 | **Apple Events bridge** | HR gates **outbound Apple Events** behind `com.apple.security.automation.apple-events`. Add that entitlement (the app already declares `NSAppleEventsUsageDescription`) and confirm the now-playing metadata bridge still resolves. | Apple Music **and** Spotify now-playing metadata still resolves during a session. |
| 4 | **Developer ID signing** | Switch `CODE_SIGN_IDENTITY` `Apple Development` → `Developer ID Application` (needs a Developer ID cert under team `2LBTN9PB4Z`). Consider `CODE_SIGN_STYLE = Manual` for a release config. | A Release build signs with the Developer ID identity; `codesign -dv --verbose=4` shows it. |
| 5 | **Notarize** | `xcrun notarytool submit … --wait` then `xcrun stapler staple`. Needs an App Store Connect API key (preferred) or an app-specific password. | notarytool returns `Accepted`; staple succeeds. |
| 6 | **Gatekeeper test** | The stapled build launches on a **clean machine / fresh user** with no "unidentified developer" block. | `spctl --assess --type execute -vv` passes **and** a real first-launch on a clean account is clean. |
| 7 | **Library validation** | Leave **ON** (do NOT add `disable-library-validation` — Phosphene links Apple frameworks + SPM **static** libs only, loads no third-party dylibs). | Build + run pass with it on. |

## Decision for Matt (BLOCKING — confirm before starting steps 4–6)

- **Apple Developer Program membership + notarization credentials.** Developer ID signing and notarization require the **paid ($99/yr) Apple Developer Program** (not a free account) and a notarization credential (an App Store Connect API key, or an app-specific password). Team `2LBTN9PB4Z` is configured for *dev* signing — **confirm it's a full membership and that the Developer ID cert + notarization credential exist or can be created.** Without these, steps 4–6 cannot run.
- **Timing / split.** Two product-level options: *(a) do it all now* (you're about to share a build); or *(b) split* — land + verify the **hardened-runtime half (steps 1–3) now** to de-risk the "does the tap survive HR?" question early and cheaply, and defer the **Developer-ID + notarization half (steps 4–6)** until a build is actually about to leave the Mac mini. *Recommended default: (b) split* — steps 1–3 are the real engineering risk (the tap/Apple-Events behaviour) and need no Apple credentials; steps 4–6 are mechanical once the cert + notarization key exist. *User-visible framing:* "do you want me to prove the audio tap still works under the security hardening now, and leave the notarized-build packaging for when you're actually handing it to someone?"

## Rules / pitfalls

- **Build + real-run every change** — the whole reason this is filed separately from 2.4. A green build is necessary but not sufficient: the tap, the Apple Events bridge, and Gatekeeper acceptance are all **runtime** behaviours that only a real session on the Mac mini proves. These are **manual gates**, like CLEAN.1.5's G1.
- **No speculative entitlements.** Hardened runtime needs *no* extra entitlement for most apps; add a `com.apple.security.cs.*` only when a real run proves a specific break. Every entitlement added weakens the binary — the minimal-exfiltration posture documented in `SECURITY_POSTURE.md` is a strength to preserve.
- **Keep library validation ON.** Never add `disable-library-validation`.
- **Do NOT enable the App Sandbox** — separate concern, incompatible with the global tap (`SECURITY_POSTURE.md` §2). HR ≠ sandbox.
- **Never check a secret into a tracked file** (`Phosphene.xcconfig` holds only the public client ID; CLEAN.2.1). Notarization credentials live outside the repo (Keychain / a gitignored profile / CI secret), never committed.
- **The Gatekeeper test needs a real machine** — `spctl --assess` is a proxy, not a substitute for a clean-account first launch.

## Closeout

- `Scripts/closeout_evidence.sh` evidence block. **State the manual verification results explicitly** (tap installs under HR; Apple Music + Spotify metadata reachable; notarization `Accepted`; Gatekeeper clean on a fresh account) — these are manual gates, like G1; the automated suite does not cover them.
- Update **`docs/SECURITY_POSTURE.md` §3** (flip "neither enabled" → enabled + notarized; update summary-table **row 3**) and **§4** if any `cs.*` entitlement was added.
- Mark **CLEAN.2.5 done** in `docs/diagnostics/CODE_AUDIT_2026-06-13.md` (Part C Phase 2 row) and close GAP-10 fully (2.4 marked it *reviewed*; 2.5 marks the fix *shipped*).
- `docs/ENGINEERING_PLAN.md` CLEAN.2.5 row; `docs/RELEASE_NOTES_DEV.md` entry.
- **Push requires Matt's explicit "yes, push."**
