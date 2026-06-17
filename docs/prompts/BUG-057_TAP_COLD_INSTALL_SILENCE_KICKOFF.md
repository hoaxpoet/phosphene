# BUG-057 — Kickoff: cold tap install delivers persistent silence on streaming; only a device-switch reinstall recovers (P1, `audio.capture`)

> **The core streaming-visualization flow is broken on a cold start.** With live Spotify audio the system-audio tap installs (`AudioHardwareCreateProcessTap` → `noErr`, `raw tap capture started` logs) but delivers **permanent silence** — and the only thing that recovers it is a **manual output-device switch**. Filed **BUG-057 (P1)**. This is a **P0/P1 multi-increment defect**: per the Defect Handling Protocol, **instrument first → commit → STOP; then diagnose; then fix; then Matt's manual validation.** Do NOT jump to a blind fix — the create path is already correct, so a guessed fix will likely miss.

## The finding — start here (this is the whole lead)

Across five cold-start sessions on 2026-06-17 / 06-16, the tap was silent for Spotify (`features.csv` mid/treble = exactly 0.0; `signal quality → red: no signal`). In **one** session (`~/Documents/phosphene_sessions/2026-06-17T01-51-11Z/`) the tap was silent for ~75 s, then at the **instant the default output device switched** (rate flipped 48 k → 44.1 k → `performReinstall` fired) it captured **~5.6 s of real music**: `mid` up to **0.527**, `treble` 0.106, `signal quality → green: peak -0 dBFS — OK`, then degraded.

So the audio **is** tappable — the *cold-install* tap is the one that comes up dead, and a **reinstall on a device change recovers it**. The create sequence is identical between the two:

- `SystemAudioCapture.startCapture(mode:)` (`SystemAudioCapture.swift:116`) — the cold install: `createProcessTap → readTapFormat → createAggregateDevice → createIOProc → startDevice`, then `deviceMonitor.start { … performReinstall }`.
- `SystemAudioCapture.performReinstall()` (`:290`) — `teardownTapResources` (`:311`) then the **same** `createProcessTap → … → startDevice`.

Identical create steps ⇒ the divergence is **timing / state**, not code. The reinstall runs *later* (audio flowing, TCC settled, a fresh device-bound tap).

## What's already ruled out — do NOT re-chase these

- **Output routing** — silent on BOTH the Apogee Duet 3 and built-in Mac-mini speakers.
- **Signing** — proper `Apple Development` cert (`matt.deming@gmail.com`, Team `2LBTN9PB4Z`), not ad-hoc.
- **Screen Recording permission** — granted, toggled off/on + relaunched; `NSScreenCaptureUsageDescription` present in Info.plist.
- **Audio actually playing** — audible through the system output.
- **Engine / render path** — local-file playback animates normally (file-direct, bypasses the tap).

## The crux to diagnose (separate these four — the instrumentation exists to tell them apart)

1. **TCC-grant-not-yet-effective on the first tap** — the "granted-but-silent" note in `project_streaming_tap_signal_health` / `SilenceDetector`: `CGPreflightScreenCaptureAccess` passes but macOS silently denies the very first tap right after launch/grant; a later reinstall gets the now-effective grant.
2. **DRM-zeroing** — `SilenceDetector.swift:4`: "Core Audio process taps succeed even when playing DRM-protected content, but macOS silently zeros the audio buffer … the tap appears healthy while delivering silence." Spotify is DRM. BUT the device-switch captured *real Spotify audio*, which argues against *pure persistent* DRM-zeroing — so this is a candidate, not a conclusion.
3. **Cold tap binds before audio flows** and enters a dead state; a reinstall while audio is live works.
4. **The auto-reinstall is insufficient** — `AudioInputRouter+SignalState.swift:13` already has `.silent → scheduleNextReinstall` ("the tap stays alive but delivers permanent silence … recovery is destroy and recreate"). It **did not** recover the cold install. Is it not firing? running out of attempts? too-long delays? Does a **same-device** reinstall stay silent while a **different-device** reinstall succeeds (which is what the evidence shows)?

## What exists — REUSE, do not reinvent (FA #73)

- `SystemAudioCapture.swift` — `startCapture` / `performReinstall` / `teardownTapResources` / `createProcessTap` / `buildTapDescription` (`:239`, the `CATapDescription` global-exclude vs process-mixdown).
- `AudioInputRouter+SignalState.swift` — the `.silent → reinstall` state machine + `reinstallDelays` (the recovery that should already cover this).
- `SilenceDetector.swift` — the hysteresis silent/suspect/active detector + the DRM-zeroing documentation.
- `DefaultOutputDeviceMonitor.swift` — the CLEAN.1.5 / GAP-1 monitor whose device-change callback drives the **recovering** `performReinstall`. **This is the path that works — the fix likely makes the cold start behave like it.**

## The work (multi-increment, per the Defect Protocol)

1. **Instrument (commit + STOP).** Add capture of, for both cold install and any reinstall: tap RMS over the first ~10 s, whether/when `.silent → reinstall` fires + the attempt count, the bound device id + rate, and the Screen-Recording preflight state at install — persisted to `session.log` so it is greppable from the artifact (os_log rolls off — see `project_clean_audit` para 30). Enough to separate the four candidates from ONE real Spotify cold-start session. No fix code.
2. **Diagnose.** Matt runs an instrumented cold-start Spotify session (+ a device-switch). From the artifact, identify which candidate(s) hold. Document the root cause in BUG-057. No fix code.
3. **Fix.** Candidate directions once diagnosed (pick from evidence, do not pre-commit): schedule an **initial `performReinstall`** shortly after `startCapture` (or gated on first-audio / on the grant settling); make the `.silent` recovery actually fire **and** recover on cold start (e.g. shorter first delay, or escalate to a device-rebind if same-device reinstall stays silent); or cycle the bound device once on install. Add/extend a regression where testable (the silent-state machine is unit-testable even if the live tap is not).
4. **Validate (the real gate).** Matt's manual session: a **cold start** with live Spotify animates within ~5 s with **NO manual device toggle** — `features.csv` mid/treble > 0, `signal quality → green` — across ≥ 2 sessions. Plus no regression: local-file still animates; the CLEAN.1.5/G1 mid-session device-swap recovery still works.

## Rules / pitfalls

- **Manual validation is mandatory and load-bearing** — the tap path is not SPM-testable (real Core Audio + a DRM streaming source). The instrumentation makes the *diagnosis* artifact-based; the *fix* still needs Matt at normal volume on a real cold start.
- **Test on the canonical app with Screen Recording granted** — build/run from the PRIMARY project (`project_canonical_app_screenrecording`); a fresh worktree build re-churns the path + grant and will reproduce *unrelated* silence. Do not conflate that with this bug.
- **Distinguish DRM-zeroing from cold-install-timing** before fixing — if it is pure DRM-zeroing, no reinstall would ever capture Spotify (but one did), so weight the timing/grant hypotheses; keep DRM as a falsifiable candidate.
- **Don't break what works** — local-file playback and the G1 device-swap reinstall must stay green; the fix should converge the cold start *onto* the working reinstall path, not fork a new one.
- This is **not** a CLEAN.7.6c regression — that work is test-only; this is the live tap-install path on macOS 26.5.

## Closeout (Defect Protocol)

- `KNOWN_ISSUES.md` BUG-057 → `Diagnosed` after step 2, `Resolved` + commit hash after step 4; `RELEASE_NOTES_DEV.md` (`[dev-YYYY-MM-DD-HHMMSS]`).
- `Scripts/closeout_evidence.sh` block; the **manual-validation** result (cold-start Spotify animates, ≥ 2 sessions) is the primary evidence — state it explicitly.
- Small commits; **push requires Matt's "yes, push."**

## References

BUG-057 (`KNOWN_ISSUES.md`); memories `project_streaming_tap_signal_health` (the granted-but-silent + output-routing silent-tap causes) and `project_canonical_app_screenrecording` (build-from-primary + the Screen-Recording grant); CLEAN.1.5 / GAP-1 (`DefaultOutputDeviceMonitor` → `performReinstall`, the recovering path); D-061 (capture-mode resilience); FA #73 (reuse the working path, don't rebuild). Session artifacts: `~/Documents/phosphene_sessions/2026-06-17T01-51-11Z/` (the recovery trace), `…01-48-33Z/` + `…01-37-54Z/` (silent cold installs).
