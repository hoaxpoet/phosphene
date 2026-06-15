# Phosphene — Security Posture & Local Threat Model

> CLEAN.2.4 / audit GAP-10 (`docs/diagnostics/CODE_AUDIT_2026-06-13.md` Part B G10, Part C row).
> Review + document increment — **no security build settings were flipped here**; fixes are filed, not applied blind (each needs a build + real run). Posture below verified against source 2026-06-15.
>
> **Update (CLEAN.2.5a, 2026-06-15):** the hardened-runtime half of GAP-10 is now applied — `ENABLE_HARDENED_RUNTIME=YES` + the `com.apple.security.automation.apple-events` entitlement (§3, §4, summary row 3 updated). Developer ID signing + notarization (CLEAN.2.5b) remain deferred — **blocked on a paid Apple Developer Program membership**.

## What this is

The security posture and a local threat model for Phosphene. It states, for each surface, the **verified current state**, the **threat/rationale**, and the **decision or filed follow-up**. It is the reference for "is surface X a problem, and what did we decide about it."

## Governing context (CLAUDE.md §Development Constraints)

Phosphene is **macOS-only**, single-user, **on-device only — no cloud, no telemetry**, MIT-licensed. The Mac mini is the primary dev/deploy target. There is **no public build yet** (`RELEASE_NOTES_DEV.md` preamble).

**Distribution intent (Matt, 2026-06-15):** *eventual distribution is on the roadmap* (sharing a notarized build / a possible public release). This does not change what 2.4 does — it still only documents and files — but it makes hardened-runtime + notarization (§3) a **near-term filed follow-up (CLEAN.2.5)** rather than indefinitely deferred. The actual enablement is its own increment because it touches the signing pipeline and needs a real Gatekeeper + tap test.

**The exfiltration posture is the headline strength.** No telemetry, no analytics, no cloud sync; on-device ML; the only outbound network is to Spotify / Apple Music / the iTunes lookup API for *metadata the user asked us to fetch*. Audio is tapped but never uploaded. Session recordings are written to local disk only. For a privacy-sensitive surface (a system-wide audio tap) the data simply has nowhere to go.

## Summary (verified 2026-06-15)

| # | Aspect | Current state | Verdict |
|---|---|---|---|
| 1 | System-audio tap | `.systemAudio` = global tap, excludes nothing (production always uses this); `.application` = single-PID path retained in engine code but not user-selectable (CLEAN.2.3.5). TCC-gated on screen-recording; audio-only, no screen pixels. | Document — core mechanism, consent-gated. |
| 2 | App sandbox | **Off** — `app-sandbox = false` is the only entitlement. | Document — incompatible with the tap; partial sandbox not viable. |
| 3 | Hardened runtime + notarization | **Hardened runtime ON** (CLEAN.2.5a — `ENABLE_HARDENED_RUNTIME=YES` on the app target **Release** config; Debug left unhardened so XCTest injection works; signs `-o runtime`; `automation.apple-events` entitlement added). Still dev-signed ("Apple Development"), **not yet Developer ID / notarized**. | **CLEAN.2.5a done + verified** (HR; runtime gates verified 2026-06-15 — tap green @ −6 dBFS under HR, Apple-Events entitlement accepted); **CLEAN.2.5b deferred** — Developer ID + notarization, blocked on a paid Apple Developer Program membership. |
| 4 | Library validation | Not declared. Links Apple frameworks + SPM static libs only. | Document — not required; keep ON under hardened runtime. |
| 5 | `phosphene://` OAuth callback | scheme + host + `state` (CSRF/replay) + nil-pending rejection; double-checked at `.onOpenURL`. | Document — mitigated (CLEAN.2.2). |
| 6 | Local-file open path | Defensive m3u parser + AVFoundation decoders; arbitrary resolved paths, no traversal guard. | Document; **filed: BUG-051 P3** (defense-in-depth). |
| 7 | Secrets at rest + no-telemetry | OAuth tokens in Keychain; only the public client ID is checked in; no telemetry. | Document — posture strength. |

---

## 1. Global system-audio tap

**Current posture (verified — `PhospheneEngine/Sources/Audio/SystemAudioCapture.swift` `buildTapDescription`).** Two modes:
- `.systemAudio` → `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` — a **global tap that excludes nothing**, i.e. it captures the entire system audio mix (every app). (The empty-exclude variant is load-bearing — the seemingly-equivalent `stereoMixdownOfProcesses: []` delivers silence; see the code comment + Failed Approaches #21/#22 at the tap-install site / `docs/RUNBOOK.md`.)
- `.application(bundleID)` → `CATapDescription(stereoMixdownOfProcesses: [pid])` — narrows to a **single process**. This case remains in the engine, but is **not currently user-selectable**: the Settings per-app picker and the `switchMode`/`availableApplications` plumbing were removed as inert (CLEAN.2.3.5/2.3.6), so production always uses `.systemAudio`.

The tap is **TCC-gated**: macOS requires the user to grant screen-recording permission before `AudioHardwareCreateProcessTap` will install. That grant is the consent boundary.

**`NSScreenCaptureUsageDescription` honesty (verified).** The string reads *"Phosphene captures system audio to generate real-time music visualizations. No video is recorded."* This is honest: the screen-recording permission is purely the OS gate for the **audio** tap — **no screen pixels are ever read**. `SessionRecorder` (`PhospheneEngine/Sources/Shared/SessionRecorder+Video.swift`) does write video, but it encodes the app's **own rendered Metal texture** (`appendVideoFrame(from tex: MTLTexture …)`) — Phosphene's generated visuals, not the user's screen — to local disk (`~/Documents/phosphene_sessions/<stamp>/`, `SessionRecorder.swift:210-238`). "No video is recorded" is true of *screen/user content*; the only video recorded is Phosphene's own output, on-device.

**Threat / rationale.** A global audio tap is a real privacy surface: while active it can observe audio from any app. Mitigations: (a) the OS consent gate (user must explicitly grant screen-recording); (b) **audio-only** — no screen content; (c) **no exfiltration** — tapped audio is analyzed on-device and never uploaded (see §7); (d) the engine retains an `.application` (single-PID) tap path in code, though it is not currently user-selectable (CLEAN.2.3.5).

**Decision.** Document — no fix. The global tap is the product's core mechanism and is consent-gated. No change.

## 2. App sandbox = off

**Current posture (verified — `PhospheneApp/PhospheneApp.entitlements`).** `com.apple.security.app-sandbox = false` is the **only** entitlement declared.

**Threat / rationale.** An un-sandboxed app has the user's full file/IPC reach; a compromise (e.g. via a decoder bug, §6) is not contained by the sandbox. But the App Sandbox is **fundamentally incompatible** with Phosphene's three core mechanisms:
- the **global Core Audio process tap** needs to see all processes' audio — the sandbox cannot grant that;
- **Apple Events** to arbitrary music apps (Apple Music / Spotify, for now-playing metadata) need per-target temporary-exception entitlements the sandbox discourages;
- **arbitrary local-file open** (LF.4–LF.6: any `.m4a/.mp3/.flac/.m3u` the user picks) works today via direct paths; under the sandbox it would require user-selected-file scope + security-scoped bookmarks throughout.

**Partial sandboxing?** Not viable as a quick win: the global tap alone defeats it, and the file/Apple-Events paths would each need a non-trivial rework for marginal benefit on a single-user local app. Revisit only if a future model drops the global tap.

**Decision.** Document the rationale. **No follow-up filed** (partial sandboxing does not look viable). If distribution hardening (§3) later wants defense-in-depth, the tradeoff can be re-opened then.

## 3. Hardened runtime + notarization

**Current posture (CLEAN.2.5a, 2026-06-15 — `PhospheneApp.xcodeproj/project.pbxproj` + `PhospheneApp/PhospheneApp.entitlements`).** Hardened runtime is **ON for the app target's Release config** — `ENABLE_HARDENED_RUNTIME = YES` (verified: `codesign -dv` on the Release product shows `flags=0x10000(runtime)`, `Runtime Version` present). **The Debug config is deliberately left unhardened.** HR enables library validation, and a hardened *test host* refuses to `dlopen` the injected `PhospheneAppTests.xctest` bundle — `mapping process and mapped file (non-platform) have different Team IDs` — so HR-on-Debug breaks `xcodebuild test`. HR is a distribution/Release property; scoping it to Release keeps the test suite green and hardens the config that actually ships + notarizes. (Durable learning: the first attempt set HR in `Phosphene.xcconfig`, which applies to both configs, and the app-test bundle-load failure forced the Release-only scope.) The outbound-Apple-Events entitlement `com.apple.security.automation.apple-events` was added (entitlements apply to both configs) — the `StreamingMetadata` now-playing bridge (`NSAppleScript` → Apple Music / Spotify) needs it under HR. Signing is still `CODE_SIGN_IDENTITY = "Apple Development"` / `Automatic` / team `2LBTN9PB4Z` — **dev-signed, not yet Developer ID, not yet notarized** (the deferred CLEAN.2.5b half); the dev-signed Release build still carries `get-task-allow` (auto-injected for development certs — it drops out under Developer ID signing in 2.5b, which notarization requires). No `com.apple.security.cs.*` entitlement was added — the tap is TCC-gated and expected to survive HR; one is added only if a real run shows a break.

**Threat / rationale.** Without the hardened runtime + a Developer ID signature + notarization, a build cannot pass Gatekeeper cleanly on a machine other than the dev machine — it blocks the distribution Matt now has on the roadmap. Enabling the hardened runtime is **not** a one-line flip: it restricts code-injection/JIT/loading and **may break the audio tap or the Apple Events bridge**, so it needs a real run (tap still installs, music apps still reachable) plus a Gatekeeper test of a notarized artifact.

**Decision — CLEAN.2.5 SPLIT (Matt, 2026-06-15).** Split because Developer ID signing + notarization require a **paid Apple Developer Program membership** the project does not currently have.
- **CLEAN.2.5a (done + verified, this increment):** enable the hardened runtime (Release config) + add the Apple Events entitlement; Release build + sign verified green (`-o runtime`, entitlement present on the binary); Debug `xcodebuild test` suite stays green. **Manual runtime gates VERIFIED 2026-06-15** (Matt, Mac mini, hardened Release build, session `2026-06-15T22-45-34Z`): (i) launches under HR ✅; (ii) `.systemAudio` tap installs + delivers audio under HR ✅ — green @ **−6 dBFS**, 11,425 live-energy frames in `features.csv` (the brief startup "red/silent" is the documented pre-playback artifact, not a fault); (iii) Apple Events ✅ **accepted** — the now-playing AppleScript poller ran under HR without fault and the entitlement is verified on the binary, but this Spotify-prefetched session did not independently isolate it (displayed metadata came from the Spotify Web-API plan; per-poll AppleScript results aren't persisted), so it's accepted as satisfied-by-construction per Matt's call. Spotify connection also confirmed working on the primary-dir build (the worktree build had an empty `SPOTIFY_CLIENT_ID` — gitignored `Phosphene.local.xcconfig` absent in worktrees).
- **CLEAN.2.5b (deferred, blocked on paid membership):** switch `CODE_SIGN_IDENTITY` → `Developer ID Application`, notarize (`xcrun notarytool submit --wait` + `xcrun stapler staple`), and Gatekeeper-test on a clean machine/account (`spctl --assess` + a real first launch). Mechanical once the cert + notarization key exist. Keep library validation **on** (§4).

## 4. Library validation

**Current posture (verified — entitlements + pbxproj).** No `com.apple.security.cs.disable-library-validation` declared. Phosphene links Apple frameworks (Metal, AVFoundation, Accelerate, MPSGraph, MusicKit, …) and SPM **static** libraries — it does **not** load third-party or unsigned dylibs at runtime.

**Threat / rationale.** `disable-library-validation` is only needed when an app loads code signed by a different team (plugins, unsigned dylibs); disabling it weakens the binary. Phosphene loads none, so it should never disable it.

**Decision.** Document — **not required, no fix**. Verified under hardened runtime (CLEAN.2.5a): library validation is on by default and was **left on** — no `disable-library-validation` declared, confirmed on the signed binary (`codesign -d --entitlements`).

## 5. `phosphene://` OAuth callback

**Current posture (verified — `PhospheneApp/Services/SpotifyOAuthTokenProvider.swift` `handleCallback`, `PhospheneApp/PhospheneApp.swift:104` `.onOpenURL`).** The custom URL scheme `phosphene://spotify-callback` is the OAuth redirect target. The callback is validated at two layers:
- `.onOpenURL` dispatches only when `url.scheme == "phosphene"` **and** `url.host == "spotify-callback"`;
- `handleCallback` re-checks scheme + host, then enforces the **`state` CSRF/replay guard** — the returned `state` must equal the `pendingState` sent in the authorize URL; a nil `pendingState` (no login in flight) is rejected as possible CSRF/replay (CLEAN.2.2.3a). Missing-code / denied-auth paths fail closed.

**Threat / rationale.** Custom URL schemes can be invoked by any app, so a callback handler is an injection surface: a malicious `phosphene://spotify-callback?code=…` could try to inject an auth code or replay an old one. The `state` round-trip + nil-pending rejection close the CSRF/replay class; PKCE (CLEAN.2.1) means an injected code is useless without the matching verifier.

**Decision.** Document — **mitigated by CLEAN.2.2**. No gap found, no fix filed.

## 6. Local-file open path

**Current posture (verified — `PhospheneEngine/Sources/Session/M3UParser.swift`, `PhospheneApp/PhospheneApp.swift:215` `dispatchFileURL`, `LocalFilePlaybackProvider`).** Opening a file (Finder double-click / `open -a` / drag / Recents) routes by extension to the local-file or m3u or folder entry point. The `.m3u`/`.m3u8` parser is **defensive**: maps the file (`mappedIfSafe`), strips a UTF-8 BOM, decodes UTF-8 or **throws** `malformedUTF8`, normalizes CRLF, skips comments, resolves each entry, **readability-checks** each (`isReadableFile`), silently skips unreadable entries, and **throws** `noEntriesResolved` if none resolve. Audio bytes are decoded by **AVFoundation** (`AVAudioFile`), Apple's framework decoders.

**Threat / rationale.** Two surfaces: (a) **malformed media** fed to AVFoundation decoders (mp3/m4a/flac) — the standard audio-decoder attack surface, mitigated by Apple's hardened decoders and the fact that the file came from the user's own disk; (b) **arbitrary path resolution in `.m3u` entries** — `M3UParser.resolveURL` resolves `file://`, absolute (`/…`), and relative paths with **no path-traversal / extension guard**, so a hostile playlist could name `/Users/you/.ssh/id_rsa` or `../../etc/passwd`.

The **consequence is bounded**, which is why this is P3 not higher: a resolved non-audio path passes `isReadableFile`, is handed to AVFoundation, and **fails to decode** — it is never read back to the attacker. Critically, the local-file path has **no network egress** (§7), so even a successfully-opened file's contents have nowhere to go. The realized harm in the current architecture is ≈ nil; the value of fixing it is defense-in-depth, more relevant once builds are shared (§distribution).

**Decision — FILED: BUG-051 (P3, defense-in-depth).** Add an extension allow-list + path canonicalization to resolved `.m3u` entries (reject entries that don't resolve to an allowed audio extension under an expected root). Low value given the no-egress mitigation; tracked so it isn't lost.

## 7. Secrets at rest + no-telemetry

**Current posture (verified — `PhospheneApp/Services/SpotifyOAuthTokenProvider.swift`, `PhospheneApp/Phosphene.xcconfig`, `PhospheneApp/Info.plist`).**
- **OAuth tokens** (Spotify access + rotating refresh) live in the **Keychain** (CLEAN.2.1/2.2). Keychain save failures are logged, not swallowed (CLEAN.2.2.3c).
- **No client secret anywhere** — PKCE uses only the public `SPOTIFY_CLIENT_ID`, injected from the **gitignored** `Phosphene.local.xcconfig`; the checked-in `Phosphene.xcconfig` holds an empty value and a comment forbidding a real one (CLEAN.2.1's whole point — do not regress).
- **No telemetry / no cloud.** On-device ML; the only outbound traffic is user-initiated metadata fetches (Spotify / Apple Music / iTunes lookup). Tapped audio and session recordings (`~/Documents/phosphene_sessions/`) are **never uploaded** — `SessionRecorder` has no `URLSession`/network path (verified).

**Threat / rationale.** Token theft (Keychain is the right at-rest store, ACL-scoped to the app); secret leakage from a shipped binary (eliminated — none is embedded); and data exfiltration (structurally minimal — there is no telemetry channel for tap audio or recordings to escape through).

**Decision.** Document — **posture strength, no fix**. The invariant to protect: never check a secret into `Phosphene.xcconfig`; never add a telemetry/upload path for tap audio or session recordings.

---

## Filed follow-ups

| ID | Sev | What | Why filed, not applied here |
|---|---|---|---|
| **CLEAN.2.5a** | — | **Done (2026-06-15)** — hardened runtime enabled (app-target-scoped) + `automation.apple-events` entitlement; build + sign verified (`-o runtime`). Runtime gates (tap + Apple Events under HR) pending Matt's Mac-mini run. | The deliberate flip 2.4 deferred — applied here with a build behind it (§3). |
| **CLEAN.2.5b** | — | Developer ID signing + notarization + Gatekeeper test; keep library validation on. | **Deferred — blocked on a paid Apple Developer Program membership.** Mechanical once the cert + notarization key exist (§3). |
| **BUG-051** | P3 | m3u entry input validation: extension allow-list + path canonicalization on resolved playlist entries. | Defense-in-depth; consequence is bounded by the no-egress local-file path (§6). Low value, tracked so it isn't lost. |

No fix was filed for §2 (partial sandbox — not viable), §4 (library validation — not required), §5 (OAuth — mitigated), §1/§7 (core mechanism / posture strength).

## How each claim was verified (2026-06-15)

- Sandbox / entitlements — read `PhospheneApp/PhospheneApp.entitlements` (only `app-sandbox = false`).
- Hardened runtime / signing — `grep` for `ENABLE_HARDENED_RUNTIME` / `disable-library-validation` across pbxproj + entitlements + xcconfig (zero hits); read signing keys in `project.pbxproj`.
- Tap scope — read `SystemAudioCapture.buildTapDescription`.
- Recorder honesty — read `SessionRecorder+Video.swift` (`MTLTexture` source) + `SessionRecorder.swift` output dir; confirmed no network in `SessionRecorder*.swift`.
- OAuth callback — read `SpotifyOAuthTokenProvider.handleCallback` + `PhospheneApp.swift` `.onOpenURL`.
- Local-file path — read `M3UParser.swift` + `dispatchFileURL`.
- Secrets — read `Phosphene.xcconfig` (empty client ID, no secret) + `Info.plist`.
