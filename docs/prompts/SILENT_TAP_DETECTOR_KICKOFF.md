# Kickoff — "Phosphene isn't receiving audio" detector (the BUG-057 / BUG-055 fix; BUG-058-informed)

> **Build the user-facing detector that turns a silent/frozen tap into actionable guidance instead of a silent "ready" flatline.** This is the **fix increment (Defect Protocol step 3)** for the silent-tap family. The *detection signal* and most plumbing already exist — this is largely **wiring + a gate + a UX surface**, not a new subsystem. **FA #73: reuse `PlaybackErrorBridge`; do NOT build a parallel detector.**

## Why this exists (the silent-tap family)

Three filed bugs all present **identically to the user** — the app shows "ready"/playing but the visualizer is silent or frozen, with **no actionable hint**:

- **BUG-057** (diagnosed 2026-06-17): a wedged `coreaudiod` (long uptime) feeds *every* Core Audio process tap pure-zero buffers. **Not a Phosphene code bug** — workaround is `sudo killall coreaudiod` / reboot. RMS ≈ 0 → `SilenceDetector` fires `.silent`.
- **BUG-055** (origin, app.ui/permission): a stale Screen-Recording grant after a dev rebuild — `CGPreflightScreenCaptureAccess()` returns stale-`true` so the gate passes, but macOS silently denies the re-signed binary's tap → pure-zero. The detector is **BUG-055's filed fix** too.
- **BUG-058** (P3, rare): a mid-session output-device swap *occasionally* freezes the tap — `performReinstall` stalls, the IO proc stops, and the render loop coasts on the **last buffer**. RMS stays **nonzero-but-frozen**, so `.silent` does **NOT** fire.

The silence itself is environmental (coreaudiod / TCC / a Core Audio race) — **this increment does not try to fix the silence**, it **detects "no useful audio is reaching the visualizer" and tells the user what to do.** One surface closes the user-facing gap for all three.

## Approved design (Matt, 2026-06-17 — do not re-litigate)

- **Trigger:** a sustained "no useful audio while we should be playing" condition, dwell **~10 s**.
- **Surface:** a **non-blocking overlay card** (more prominent than the existing bottom-right toast, because this is total loss of function) over the (frozen/black) visualizer. Plain-language line + a **fix ladder**:
  1. *Restart audio:* `sudo killall coreaudiod` (the daemon relaunches itself).
  2. *If you just rebuilt the app:* re-grant **Screen & System Audio Recording**, then **quit + relaunch**.
  3. *Check the macOS output device* (Sound → Output).
  - Audience is currently the developer, so the literal command is fine; soften copy before any public build.
- **Auto-clear** the card when audio returns.
- **Reuse `PlaybackErrorBridge`** (it already watches `audioSignalState`, fires a condition-bound `silenceExtended` toast at 15 s, and auto-clears via `ToastManager.dismissByCondition`). **Gate it on `SessionState.playing`** + a first-audio guard. **Let the card supersede the existing 15 s `silenceExtended` toast while playing** (don't show both — avoid a card-before-toast double-surface).

## CRITICAL — catch BOTH failure modes (this is the design's sharp edge)

A naive detector keying on `SilenceDetector.silent` (RMS ≈ 0) catches BUG-057/055 but **misses BUG-058**: the device-swap freeze leaves a **frozen non-zero buffer**, so RMS isn't ≈ 0 and `.silent` never fires. The detector must catch **"no FRESH audio"**, not just "silent":

- **Mode A (RMS ≈ 0):** `SilenceDetector` → `.silent`. Covers BUG-057 / BUG-055.
- **Mode B (frozen / IO-proc-stopped):** the **tap IO-proc callbacks stop advancing** — `InputLevelMonitor.frameCount` (or a tap-callback counter) stops increasing, and the analyzed features go constant. RMS stays nonzero. Covers BUG-058.

So gate on: **`SessionState == .playing`** AND **(we've seen real audio at least once this session OR play started > dwell ago)** AND **(`.silent` for ≥ dwell OR no fresh tap callbacks for ≥ dwell)**. Auto-clear when fresh, non-silent audio resumes.

**Do NOT false-fire** pre-play, in the `.ready` wait, or during quiet musical passages — these legitimately read low/zero RMS (documented: startup/quiet "red: no signal" is normal). The gate (especially the `.playing` + first-audio guard) is the whole point, and it's the **testable core**.

## Integration map (verify file:line against current code — these are starting points, not gospel)

- `audioSignalState` (`AudioSignalState`: active/suspect/silent/recovering) — `@Published` on `VisualizerEngine` (`PhospheneApp/VisualizerEngine.swift`), set in `VisualizerEngine+Capture.swift` `makeSignalStateCallback`. Consumers today: `PlaybackChromeViewModel` (`showListeningBadge = state == .silent` → `ListeningBadgeView`), `PlaybackErrorBridge` (the 15 s toast), `FirstAudioDetector`.
- **`PlaybackErrorBridge`** (`PhospheneApp/Services/PlaybackErrorBridge.swift`) — **the reuse target.** `.silent` → 15 s → `silenceExtended` toast (conditionID, `.infinity`, auto-clear on `.active`/`.recovering`). Extend it with the `.playing` gate + the "no fresh audio" signal + the card.
- `SessionState` enum (`PhospheneEngine/Sources/Session/SessionTypes.swift`): idle/connecting/preparing/ready/**playing**/ended. `@Published` on `SessionStateViewModel.state`.
- `FirstAudioDetector` (`PhospheneApp/Services/FirstAudioDetector.swift`) — `hasDetectedAudio` latches on ≥ 250 ms sustained `.active`. The "seen real audio once" signal; reuse/extend (today it only gates `.ready → .playing` in `ReadyViewModel`).
- `InputLevelMonitor` (`PhospheneEngine/Sources/Audio/InputLevelMonitor.swift`) — `frameCount` / `currentSnapshot()` (peak/RMS/quality). **Not exposed to the UI today** — expose a `@Published` snapshot (or a "fresh callbacks" counter) for the Mode-B signal.
- `UserFacingError` (`PhospheneEngine/Sources/Shared/UserFacingError.swift`) + `UserFacingError+Presentation.swift` (presentation modes; `.bottomRightToast`). Add a case + a more-prominent presentation for the card.
- `ToastManager` (`PhospheneApp/ViewModels/ToastManager.swift`) — `conditionID` assert/`dismissByCondition` is the auto-clear pattern.
- `PlaybackView` ZStack (`PhospheneApp/Views/Playback/PlaybackView.swift`) + `PlaybackChromeView` — where to insert the card layer.
- **The BUG-057/058 instrumentation already exists and is the signal source:** `AudioCapturing.onCaptureDiagnostic` → `AudioInputRouter.onAudioCaptureDiagnostic` → `SessionRecorder.log` emits `TAP:` lines (per-install device/rate/preflight + a ~1 Hz RMS probe + `performReinstall` breadcrumbs). The RMS-probe / callback cadence is the "fresh audio" basis.

**Likely-missing (add):** the "no fresh audio while playing" signal (IO-proc callback count not advancing); the `.playing` gate into the bridge; the card view + a `@Published` flag (e.g. on `PlaybackChromeViewModel`); the `UserFacingError` case/copy.

## Tests

- **Unit-test the GATE** (the false-positive guard is what to lock down):
  - fires on `[playing + sustained no-fresh-audio ≥ dwell]`;
  - does NOT fire on `[pre-play / .ready / brief dip / quiet-then-recover]`;
  - catches **both** Mode A (RMS ≈ 0) and Mode B (frozen / no fresh callbacks);
  - auto-clears on recovery.
- The bridge timing is already injectable for unit tests (see `PlaybackErrorBridge` init publishers) — follow that pattern.
- **Manual UX validation (mandatory — UX-flow change):** Matt confirms the card renders correctly, has the right copy, appears only on a real stall (not pre-play/quiet), and auto-dismisses on recovery. **No M7** (it's an error-state, not a preset).

## Closeout (Increment + Defect Protocol)

- `KNOWN_ISSUES.md`: BUG-057 + BUG-055 + BUG-058 — record the detector as the shared fix; fill `Resolved` (BUG-055; BUG-057's *detector* half) + commit hash **after Matt's manual validation**. BUG-058 stays its own (rare freeze) but note the detector now surfaces it.
- `RELEASE_NOTES_DEV.md` (prepend; `[dev-YYYY-MM-DD-HHMMSS]`) — fix-increment obligation.
- `docs/ENGINEERING_PLAN.md` entry.
- `Scripts/closeout_evidence.sh` block (engine fixtures absent in worktrees → `Scripts/bootstrap_fixtures.sh` first; the lone Skein BUG-049 / tempo-fixture failures are environmental — see `project_worktree_engine_fixtures_absent`).
- Commit `[BUG-057]`/`[BUG-055]` format, small commits; **push requires Matt's explicit "yes, push."**

## Build / run notes

- Build the canonical app from the **PRIMARY checkout** with Screen Recording granted (`project_canonical_app_screenrecording`); a fresh worktree build re-churns the grant.
- To exercise the detector live you can deliberately induce a stall: `sudo killall coreaudiod` won't reproduce it now (healthy), but you can simulate Mode A by routing output to a non-tappable sink, or unit-drive the gate. Confirm with Matt how he wants to demo it.
- Current `origin/main` has: BUG-057 diagnosis, BUG-058 instrumentation + breadcrumbs, G1 validated. Read `KNOWN_ISSUES.md` BUG-057 §Diagnosis + BUG-058 §Update and memory `project_streaming_tap_signal_health` for the full context before starting.
