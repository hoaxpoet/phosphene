# Kickoff — Tap reinstall comes up silent on a healthy daemon (BUG-057 reinstall facet; likely BUG-058's root)

> **Scope the fix for the *real* silent-tap mechanism the detector surfaced: a tap reinstall hangs / comes up delivering silence mid-recreate, so audio never recovers — reproducible on a HEALTHY `coreaudiod`.** This is a P1 multi-increment fix (Defect Protocol: instrument → diagnose → fix → validate). **It needs Matt's go before step 1 — this doc is the scope, not an execution order.** FA #73: extend the existing reinstall breadcrumbs; do NOT build a new reinstall path.

> **Why this is a priority, not just a correctness bug (Matt, 2026-06-17):** the silent-tap *detector* card (the fallback we shipped) tells the user to run `sudo killall coreaudiod` and toggle System Settings — **not an acceptable end-state for a real user.** This fix is what turns that card from a routine surface into a rare edge case: when the tap self-heals on a pause/stall, the user sees motion resume with **zero Terminal/Settings steps**. So treat this as a user-experience fix. (Half-measures that still end in System Settings — e.g. deep-link buttons on the card — don't meet the bar; see `feedback_self_healing_over_manual_remediation`.)

## Why this exists (the detector earned this)

The silent-tap *detector* (shipped 2026-06-17, `[dev-2026-06-17-161332]`) did its job and exposed that BUG-057 is **not** purely the "wedged 15-day `coreaudiod`" environmental story the original diagnosis settled on. Session `2026-06-17T16-59-43Z` reproduced a silent tap **on a healthy daemon**:

- Cold tap installed and worked **50 s** — `signal quality → green: peak -6 dBFS`, RMS 0.02–0.10, `features.csv` energy flowing. So `coreaudiod` was healthy and the cold install was fine (unlike the wedged-daemon case).
- Matt **paused Spotify** → `audio signal → suspect → silent` → the `.silent → reinstall` recovery fired: `TAP: Tap reinstall scheduled in 3.0s (attempt #1)` → `TAP: Tap reinstall #1 starting (mode: systemAudio)`.
- **Then nothing.** No `Tap reinstall #1 succeeded` / `failed` line (both of which `performTapReinstall` logs), no `→ active`, no post-reinstall green. `features.csv` is **all-zero for the final ~150 s** — audio never came back, even after Matt resumed Spotify. The detector card correctly stayed up (genuinely no signal).

**The tell:** `performTapReinstall` logs `starting`, does the recreate, then logs `succeeded`/`failed`. The session has `starting` and **neither** completion line → **the recreate hung between start and finish.** That is the same shape as BUG-058 (device-swap reinstall stalls; IO proc never resumes) — just a **different trigger** (a `.silent`-recovery reinstall from a pause, vs a `DefaultOutputDeviceMonitor` device-change reinstall).

## What this is / isn't

- **Is:** a tap **reinstall that hangs or comes up silent** mid-recreate (`createProcessTap → readTapFormat → createAggregateDevice → createIOProc → startDevice`), on a healthy daemon, so the visualizer never recovers. Trigger seen: a streaming pause long enough to cross the `.silent` threshold (~3 s).
- **Likely unifies:** BUG-057 (this pause→reinstall facet) **and** BUG-058 (device-swap→reinstall freeze). Two triggers, probably one root: the tap recreate stalls during certain Core-Audio transitions on macOS 26.5. Confirm or split during diagnosis.
- **Isn't:** the wedged-`coreaudiod` story (that was real but separate — `killall coreaudiod` cures *that*, not this; here the daemon is healthy). Isn't the detector (the detector is correct and shipped; this is the underlying recovery it surfaces). Isn't a cold-start-phase problem (FA: do not reopen automated cold-start beat-phase work — unrelated).

## Defect Protocol path (P1 → separate increments)

1. **Instrument** ✅ **LANDED 2026-06-17** (`RELEASE_NOTES_DEV.md [dev-2026-06-17-174055]`; `KNOWN_ISSUES.md` BUG-057 §Reinstall fix — step 1). The `.silent → reinstall` path had only `scheduled` / `starting` / `succeeded` / `failed` breadcrumbs — **missing the per-step depth** BUG-058 added to the *device-change* path. Added per-step `session.log` breadcrumbs (via `onCaptureDiagnostic`) to `SystemAudioCapture.stopCapture` (`ENTER → cleanup` / `cleanup done`) and `startCapture` (`ENTER → createProcessTap` → `tap created` → `aggregate created` → `IO proc created` → `startDevice done`), mirroring `performReinstall`. The existing `armInstallProbeAndLog` already emits the new tap's `gen` + a first-seconds RMS probe at the *end* of `startCapture`, so a tap that *completes but stays silent* (`install via startCapture gen=2` present + RMS=0) is distinguishable from one that *never completes* (no `gen=2` line — the new breadcrumbs name the stalling call). Engine build green, swiftlint 0; no test (non-SPM-testable). Commit landed; **proceed to step 2 on Matt's instrumented session.**
2. **Diagnose** ✅ **DONE 2026-06-17** (instrumented session `17-45-44Z`, pause→resume ×2, both recovered). **Outcome: NOT a hang — (b)/(c).** The recreate completed cleanly every time (< 1 s); the `.silent → reinstall` **fires while the source is paused** and churns the tap pointlessly (each new tap reads RMS=0 because the source is paused, not because it's broken). Recovery comes when the source resumes and the current tap delivers (normal ~1–2 s warm-up). 16-59-43Z is one of these pause-reinstalls landing a **created-but-dead** tap (the breadcrumbs will confirm hang-vs-dead if a non-recovering session is captured, but the fix below doesn't depend on which). Full write-up in `KNOWN_ISSUES.md` BUG-057 §Reinstall fix — step 2.
3. **Fix** — directions, pick per diagnosis:
   - **Don't reinstall on a mere pause.** Gate `.silent → reinstall` (`AudioInputRouter+SignalState.scheduleNextReinstall`) so a *user pause* doesn't destroy a working tap — e.g. require corroborating evidence the tap is actually broken (output device still active / was-ever-audio), or hold off reinstalling while the output device is idle and just resume the existing tap when audio returns. (Pairs with the product question below.)
   - **Make the recreate not hang** — if a `create*`/`startDevice` blocks during the transition, bound it / retry off the hot path / order it so it can't deadlock (shared with BUG-058's fix).
   - **Recover on resume** — if the reinstalled tap is silent until audio flows, detect the first real buffer and re-arm rather than staying dead.
4. **Validate** — pause Spotify > dwell then resume → visuals recover within a few seconds, ≥ 2 sessions, no manual device toggle; `features.csv` energy returns. **This closes the loop with the detector: once recovery works, the BUG-057 detector card will auto-clear on resume — finally observable end-to-end** (today it can't, because the tap never recovers). Also re-run the BUG-058 device-swap manual gate (G1) to confirm a shared fix didn't regress it.

## Reproducer (far easier than the 15-day wedge)

Streaming session (Spotify), confirm motion → **pause ~10–15 s** → resume. Observed: visuals do **not** recover; `session.log` shows `Tap reinstall #1 starting` with no completion line; `features.csv` tail all-zero; the detector card is stuck on (correctly). Build from the **PRIMARY checkout** with Screen Recording granted (`project_canonical_app_screenrecording`); a worktree build re-churns the grant.

## Code seams (verify file:line before editing)

- `PhospheneEngine/Sources/Audio/AudioInputRouter+SignalState.swift` — the `.silent → reinstall` machine: `scheduleNextReinstall()` (:60), `attemptTapReinstall(attemptNumber:)` (:107), `performTapReinstall(captureMode:attemptNumber:)` (:132 — logs `starting` :134, `succeeded` :139, `failed` :142). **The hang is between :134 and :139.**
- `PhospheneEngine/Sources/Audio/SystemAudioCapture.swift` — the recreate steps `performTapReinstall` ultimately drives (`createProcessTap → readTapFormat → createAggregateDevice → createIOProc → startDevice`); the device-change `performReinstall` (:324) already has per-step breadcrumbs (:337–:347) to copy onto the `.silent` path.
- `PhospheneEngine/Sources/Audio/SilenceDetector.swift` — what flips `.silent` (~3 s of sub-floor RMS), i.e. what a pause trips.
- `PhospheneEngine/Sources/Audio/DefaultOutputDeviceMonitor.swift` — the BUG-058 device-change trigger of the *other* reinstall path.

## Product question for Matt (decide before step 3)

Until this is fixed, the detector card fires (correctly) on every streaming pause > dwell, recoverable only by a manual output-device switch. The framing question: **should `.silent → reinstall` fire on a user pause at all?** It destroys a working tap and the recreate comes up dead. Options surfaced in `KNOWN_ISSUES.md` BUG-057 §Validation note: longer detector dwell; infer a deliberate pause and suppress; or fix the reinstall so a pause is harmless (preferred — it's the real fix). This is a behaviour/feel decision, not an implementation one.

## Closeout (when executed)

Per the Increment Completion + Defect protocols: `KNOWN_ISSUES.md` (BUG-057 + reconcile BUG-058 if shared root), `RELEASE_NOTES_DEV.md`, `ENGINEERING_PLAN.md`, `Scripts/closeout_evidence.sh` block; `[BUG-057]`/`[BUG-058]` commits; push requires Matt's explicit "yes, push." Manual validation mandatory (real Core Audio + DRM streaming — not SPM-testable).
