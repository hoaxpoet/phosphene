# Phosphene — Known Issues History

Resolved entries rotated out of [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) §Resolved (recent) by `Scripts/rotate_docs.sh` (DOC.6) once their resolution is older than 14 days. Moves are verbatim, newest-first; BUG numbers stay searchable here, and the `DocIntegrityTests` BUG-continuity gate spans both files.

---

### BUG-023 — Folder pick race during in-flight prep produces wrong-folder playback + parallel preps + mid-track restart (LF.5, 2026-05-28)

> **RESOLVED 2026-05-28** — Three sub-symptoms (A / B / C) of one upstream concurrency cluster; landed as the three-commit LF.5.fix.3 increment (`0596b8ea` → `ef15d90d` → `1839d3e3`). Multi-increment process per CLAUDE.md §Defect Handling Protocol: instrumentation (already on disk from BUG-021's WIRING breadcrumbs) → diagnosis → fix B → fix A → fix C.

**Severity:** P1 (audible mis-playback: folder A's analysis drove playback against folder B's URL queue; active playback torn down mid-track without user input).
**Domain tag:** `pipeline-wiring` (cross-layer state-machine race).
**Failure class:** `concurrency` (cancel-then-restart race + supersession-flag clobber + duplicate consumer fire).
**Introduced:** LF.5 (`e9443e9f`, 2026-05-28) — the `startLocalFiles(at:origin:)` API. LF.4's single-file path had the same concurrency primitives but the user-flow never reached the "two picks in flight" state.

### Expected behavior

1. Picking a new folder while a previous folder's prep is still running cancels the previous prep silently. No transition to `.ready`, no playback start, no torn-down player.
2. The new folder's prep runs exactly once (no parallel runs that race on the persistent stem cache).
3. If a duplicate `.ready` emission somehow reaches `handleLocalFileReady` for the URL we're already playing, the consumer no-ops instead of tearing down and restarting from frame 0.

### Actual behavior

In session `~/Documents/phosphene_sessions/2026-05-28T20-57-46Z/session.log`:

- **A — Cancelled prep transitioned to .ready.** Line 14 logs `prepareLocalFiles DONE cached=2 failed=0 total=200` (folder A cancelled 2/200 in). Line 19 logs `SessionManager.startLocalFiles→ready count=2`. Line 15-20 then fires `handleLocalFileReady` for folder A's first track ("Can't Leave the Night") against folder B's URL queue (already in `currentSource` from B's `_beginMultiFileTransition`).
- **B — Two parallel preps of folder B.** Lines 43-49 and 52-66 show two interleaved runs of folder B's 5-file queue. Run X started at 20:59:34, Run Y at 21:00:22 (~48 s gap). Files 1-3 of Run Y hit `persistentDisk` because Run X had written them; files 1, 4, 5 raced on fresh analysis. Two `prepareLocalFiles DONE cached=5` events (21:01:48 + 21:02:14) and two `_completeLocalFilesReady` calls (21:01:49 + 21:02:14) followed.
- **C — Mid-track restart.** Line 78-94 (21:02:14): SZ2 was playing (started 21:01:49). The second `_completeLocalFilesReady` fired, transitioned `.playing → .ready`, the state observer re-ran `handleLocalFileReady`, ran `provider.teardown` (lines 83-92), and restarted audio router with mode `.localFilePlayback(SZ2)` from frame 0. No user input prompted the restart.

### Reproduction steps

1. Launch app.
2. `File → Open Local Folder`, pick a large folder (50+ tracks). Preparation begins (sequential per-file).
3. Within ~10-30 s (BEFORE the first folder's prep completes), click `File → Open Local Folder` again and pick a different, smaller folder (5 tracks).
4. (Captured session also included a Stop between picks — that's what kicked state into `.ended` and bypassed `cancel()`. Symptoms B + C reproduce without the Stop on the simpler reproducer too; the Stop just makes the parallel-prep window wider.)

### Session artifacts

- `~/Documents/phosphene_sessions/2026-05-28T20-57-46Z/session.log` lines 3-94 (the WIRING breadcrumbs from BUG-006.1 + LF.5.fix.2-FU1/FU3 are sufficient — no new instrumentation needed for diagnosis).

### Root cause

Three contributing factors at different layers:

1. **`_beginMultiFileTransition` resets `cancellationRequested = false`** ([SessionManager.swift:423](PhospheneEngine/Sources/Session/SessionManager.swift)). The older `startLocalFiles(A)` was suspended on `await preparer.prepareLocalFiles`. When B's `startLocalFiles` runs `cancel()` then `_beginMultiFileTransition(B)`, the flag toggles `true → false` between A's suspension and A's resume. The post-await guard `if cancellationRequested` evaluated `false` for A, so A proceeded into `_completeLocalFilesReady` with its cancelled-prep partial result.

2. **`cancel()` is guarded on `state != .idle && state != .ended`** ([SessionManager.swift:383](PhospheneEngine/Sources/Session/SessionManager.swift)). When the user pressed Stop between the two folder picks, state transitioned to `.ended`. The second `startLocalFiles(B)` saw `state == .ended`, skipped `cancel()`, and never told the preparer to cancel the first folder B's still-running prep task — so two `prepareLocalFiles` ran in parallel.

3. **`preparationTask = nil` at end of every `prepareLocalFiles` return** ([SessionPreparer.swift:269](PhospheneEngine/Sources/Session/SessionPreparer.swift)). An older call resolving out-of-order would clobber a newer task's reference, making the newer task untrackable for any subsequent cancellation.

Symptom A is direct from (1). Symptom B is direct from (2) + (3). Symptom C is the consumer-side fallout of two `_completeLocalFilesReady` calls reaching the `state` observer for the same session.

### Fix

Three commits within LF.5.fix.3:

- **`[LF.5.fix.3-B]` SessionPreparer: cancel previous prep at API boundary** (`0596b8ea`). `prepareLocalFiles` and `prepare(tracks:)` prefix the body with `preparationTask?.cancel()` (catches the `.ended`-bypass leftover). Removed the `preparationTask = nil` at exit (so an older call resolving out-of-order can't drop the newer task's reference). `cancelPreparation()` now nils the field explicitly. **Note:** The `prepare(tracks:)` change was reverted during testing (the `preparationTask = nil` exit was load-bearing for the streaming `replacesActiveStreamingSession` tests); only `prepareLocalFiles` carries the new pattern. LF-specific scope.

- **`[LF.5.fix.3-A]` SessionManager: gen-counter gate on .ready transition** (`ef15d90d`). New `localFileSessionGen: UInt64` field, monotonic. `startLocalFiles` increments + captures `myGen` before `_beginMultiFileTransition`; the post-await guard bails when `localFileSessionGen != myGen`. Replaces the broken `cancellationRequested` post-await check (kept as a secondary check for explicit `cancel()` calls).

- **`[LF.5.fix.3-C]` VisualizerEngine: handleLocalFileReady URL idempotency** (`1839d3e3`). New `lastStartedLocalFilePlaybackURL: URL?` field on `VisualizerEngine`. The guard at the start of `handleLocalFileReady` checks if the new `source.localFileURL` matches the marker and no-ops if so. The marker commits on successful `audioRouter.start` and clears on `.preparing` (new session) + `.ended` (teardown) in the state observer. Defense-in-depth per Matt's kickoff decision (URL match only).

### Verification

- **Automated.**
  - `swift test --package-path PhospheneEngine --filter "startLocalFiles_supersededCall_doesNotTransitionToReady|startLocalFiles_secondCall_cancelsFirstInFlight_evenAfterEndSession"` — both new tests pass. Engine suite 1359/1359 (1 known MemoryReporter flake unrelated).
  - `xcodebuild -scheme PhospheneApp test` — 160 app tests pass including the new `HandleLocalFileReadyIdempotencyRegression` suite (3 source-presence assertions).
  - Bug A test uses `Task.detached`-wrapped stub delegate to mirror production's uninterruptible per-file work and deterministically sequence A's resume AFTER B's `.ready` transition — that's the sequencing trick that lets the assertion discriminate.
- **Manual.** Reproducer above. Expected post-fix:
  - Picking the second folder cancels the first prep silently (no `.ready` transition for folder A, no playback of folder A's tracks).
  - Folder B preps exactly once (no duplicate `prepareLocalFile #N of 5` events in the new session.log).
  - Folder B transitions to `.ready` exactly once. If the user re-picks the same folder, the same-origin re-entry guard already short-circuits upstream of the new gen + URL idempotency layers.

### Out of scope

- LF.5.fix.2-FU2 stem-pipeline cancellation (already shipped + validated in the same captured session log).
- The cousin-bug `mir.elapsedSeconds` reset at LF playback start (already shipped as LF.5.fix.2-FU4 / FU-5).
- Recents persistence / file-association.
- Multi-file drag-and-drop semantics.
- The streaming-path `prepare(tracks:)` has the same nil-at-exit race in theory; out of scope for this LF-focused increment. File separately if observed.

### Resolved

`0596b8ea` (Bug B fix), `ef15d90d` (Bug A fix), `1839d3e3` (Bug C fix). 2026-05-28.

---

### BUG-022 — Session video.mp4 unreadable after force-quit / crash (missing moov atom) (2026-05-28)

> **RESOLVED 2026-05-28** — Trivial P2; collapsed diagnose-and-fix into a single increment per `CLAUDE.md §Defect Handling Protocol`.

**Severity:** P2 (no functional defect in playback or analysis; only post-hoc diagnostic evidence — `ffmpeg signalstats`, frame extraction, AVURLAsset reads — is broken).
**Domain tag:** `resource-management`.
**Failure class:** `resource-management` (writer index never written when teardown doesn't reach `finishWriting`).
**Introduced:** Original `SessionRecorder` design; surfaced now because BUG-021 (force-quit reproducer) made the failure visible at high frequency.

### Expected behavior

Every session directory's `video.mp4` is readable by ffprobe / ffmpeg / QuickTime — independent of how the session ended (clean Cmd+Q, "End session" button, force-quit, crash, signal kill). The M7 evidence pipeline (`ffmpeg signalstats` brightness oscillation counts, frame extraction for visual review) works against every session video.

### Actual behavior

`AVAssetWriter` writes mdat (sample data) progressively but only writes moov (the index) when `finishWriting(completionHandler:)` runs. `SessionRecorder.finish()` is reachable from two call sites: `deinit` (never fires when the process is killed by signal) and `NSApplication.willTerminateNotification` (fires only on clean Cmd+Q-style termination). Force-quit, `kill -9`, and crashes all skip `finish()`, so the resulting `video.mp4` is mdat-only and cannot be parsed by any standard tool: `ffprobe -v error -show_entries format=duration ...` returns `moov atom not found ... Invalid data found when processing input`.

### Reproduction steps

1. Launch Phosphene; let it record some frames.
2. Force-quit the app (Activity Monitor → Force Quit, or `kill -9 $(pgrep PhospheneApp)`).
3. `ffprobe ~/Documents/phosphene_sessions/<latest>/video.mp4` → `moov atom not found`.

### Session artifacts

Across `~/Documents/phosphene_sessions/2026-05-28*`:
- 3 sessions (`18-31-06Z`, `18-59-47Z`, `19-21-18Z`) ended cleanly — all 3 have `SessionRecorder finished` in `session.log` AND a valid moov.
- 5 sessions (`17-44-10Z`, `17-50-42Z`, `19-04-51Z`, `19-26-13Z`, `19-35-13Z`) ended abnormally (BUG-021 force-quits or earlier hangs) — none have the finish-marker AND none have a moov. Perfect 1-to-1 correlation.
- The named reproducer in the BUG-022 prompt (`2026-05-28T19-04-51Z`) is the BUG-021 force-quit session; the moov-missing state is a downstream effect of the unrelated freeze-and-force-quit, not a bug in the session itself.

### Root cause

`SessionRecorder+Video.swift:setupVideoWriter` initialized the `AVAssetWriter` with no `movieFragmentInterval`, so the writer accumulated all sample tables in memory and intended to write them in a single moov at the end of writing. When the process terminates without `finishWriting`, the writer's intended final moov is never written. The on-disk file ends with the last appended mdat.

This is a single-cause defect with no architectural risk:
- The recorder is app-lifetime, not session-lifetime — `SessionManager.endSession()` correctly does not call `finish()`.
- The clean Cmd+Q path is already wired (`VisualizerEngine+InitHelpers.swift:149-157`).
- The bug is purely "what does the on-disk file look like before `finish()` is called?"

### Fix

`SessionRecorder+Video.swift:setupVideoWriter` now sets `writer.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 1)` immediately after `AVAssetWriter` init. With this property non-zero, AVAssetWriter writes:

1. An initial `moov` atom with metadata (no sample tables) immediately at `startWriting()` time.
2. `mdat` boxes for media data, as before.
3. A `moof` (movie fragment) box every 5 s, indexing the preceding mdat data.

Up to the last fragment boundary is always recoverable. Clean Cmd+Q still calls `finishWriting` via the `willTerminate` observer and produces a final moov as before (the file is fragmented MP4 either way — still fully readable by ffprobe / ffmpeg / QuickTime / AVURLAsset).

Worst-case data loss on abnormal termination: up to the most recent 5 s of recorded video (≤ 2.5 MB at the 4 Mbps target bitrate, 30 fps cap).

### Verification

- Engine test suite filtered to `SessionRecorderTests` (19 tests) passes after the change — the existing `test_recordFrame_withCaptureTexture_producesReadableVideo` still validates the clean-finish path.
- Manual matrix (post-fix): launch a session, write ≥ 10 s of frames, then test each termination path:
  - Cmd+Q → `ffprobe` reads duration ✓ (already worked pre-fix; regression check)
  - `kill -9` → `ffprobe` reads duration ✓ (was broken pre-fix; the fix's contract)
  - "End session" button + Cmd+Q → `ffprobe` reads duration ✓
  - Real session under app workload (BUG-021-style flow) → next captured session validates this in practice.
- Resulting MP4s remain compatible with the M7 evidence pipeline (`ffmpeg signalstats`, frame extraction) per the AVAssetWriter fragmented-MP4 contract.

### Out of scope

- **Recovering existing damaged files.** The 5 affected sessions on Matt's disk (`2026-05-28T17-44-10Z`, `17-50-42Z`, `19-04-51Z`, `19-26-13Z`, `19-35-13Z`) remain unrecoverable without an external tool like `untrunc`/`mp4recover`. Per the BUG-022 prompt, retroactive recovery is explicitly out of scope. Their `features.csv` / `session.log` / `stems.csv` / `raw_tap.wav` remain intact.
- **Calling `finish()` from `SessionManager.endSession()`.** The recorder is app-lifetime, not session-lifetime. Forcing finalization on session-end would require restarting the writer for the next session, with no benefit (the running file is already crash-recoverable via the fragment interval).
- **Changing codec, bitrate, or video resolution.** Per BUG-022 prompt scope.

### Resolved

Commit pending Matt's sign-off. (Working tree was originally dirty with an unrelated BUG-020.fix edit; that has since been committed as `e9443e9f`, so the BUG-022 change is now in a clean-commit state — three files: `SessionRecorder+Video.swift`, `KNOWN_ISSUES.md`, `RELEASE_NOTES_DEV.md`.)

---

### BUG-021 — Next button froze the app + orchestrator cycled every preset alphabetically (LF.5, 2026-05-28)

> **RESOLVED 2026-05-28** — root cause identified via two-stage diagnostic; structural fix landed.
>
> **Round-1 diagnostic** (`2ab70ced`) localized the hang to `audioRouter.stop()`. **Round-2** (`8d8576f2`) instrumented every sub-step inside `LocalFilePlaybackProvider._stopLocked`. Session `2026-05-28T19-35-13Z` ended at `provider._stopLocked player.stop BEGIN` — `AVAudioPlayerNode.stop()` was the blocking call.
>
> **Root cause:** ABBA deadlock between the provider's NSLock and AVFoundation's render thread. `stop()` was wrapped in `lock.withLock { _stopLocked() }`. Inside, `player.stop()` blocks waiting for the render thread to drain. The render thread was running a `scheduleFile` completion callback that itself acquires the same lock to check whether the captured player is still active. NSLock is non-recursive — MainActor held the lock → callback blocked on it → `player.stop()` waited for callback → MainActor waited forever.
>
> **Fix:** snapshot AVFoundation refs + nil-out the fields under the lock, release the lock, then call `player.stop()` / `removeTap` / `engine.stop()` outside the lock. When the completion callback runs during teardown, its `playerNode === player` check fails (we nil-ed it under the lock already) and the callback bails out without recursing. New `teardownAVFoundation(refs:diagnostic:)` static helper holds the post-lock teardown sequence. `start()` calls `stop()` before acquiring the lock so the previous-instance teardown also runs lock-free.
>
> **Companion problem also resolved.** The GAP D revert (round-1 commit) was the right call for the orchestrator cycling. Session 2026-05-28T19-35-13Z shows `mode=reactive, planIdx=0` and no alphabetical-cycle bug.

**Severity:** P1 (UX-blocker — required force-quit). Resolved.
**Domain tag:** `concurrency` + `pipeline-wiring`.
**Session:** `2026-05-28T19-04-51Z`. 2-track folder ([2014] - Can't Leave the Night - Sustain).

### Expected behavior

Pressing Next on the transport bar advances to the next track within ~50 ms (LF.4 baseline). Session log shows `BEAT_GRID_INSTALL caller=trackChange` for the new track + `raw tap capture started` shortly after. Orchestrator in planned mode follows the planner's per-track segment assignments — typically 2-4 preset transitions per track.

### Actual behavior

1. **Freeze on Next button press.** Beachball; force-quit required. Last log entry: `stem separation 22` then nothing. No advance breadcrumbs.
2. **Orchestrator cycling through every preset alphabetically.** ~25 preset transitions in 2 minutes, one every ~5 s, following alphabetical order: Waveform → Arachne → Aurora Veil → Ferrofluid Ocean → Fractal Tree → Glass Brutalist → Gossamer → Kinetic Sculpture → Lumen Mosaic → Membrane → Murmuration → Nebula → Plasma → Spectral Cartograph → Staged Sandbox → Volumetric Lithograph → loop. Not the planner's variety output; a systematic walk through the catalog.

### Reproduction steps

1. macOS 26.4.1, Phosphene HEAD with D-LF5-4 buildPlan() call present in handleLocalFileReady.
2. File → Open Local Folder → pick a 2+ track folder.
3. Let it play for ~90 s. Observe preset transitions every ~5 s in alphabetical order.
4. Press Next on the transport bar.
5. Beachball; app unresponsive. Force-quit.

### Session artifacts

- `~/Documents/phosphene_sessions/2026-05-28T19-04-51Z/session.log` — shows the preset cycling AND the abrupt log end at 19:08:36 with no advance breadcrumbs (matches MainActor hang).
- Orchestrator wire line: `mode=session, planIdx=0, elapsedTrackTime=105.4s` — planned mode engaged (per D-LF5-1 + D-LF5-4 wire) but elapsedTrackTime 105.4 s after 3 s of playback is suspicious.

### Suspected failure class

Hypothesized chain (not yet verified):
1. D-LF5-4's buildPlan() call produces a pathological plan when the certified catalog has only 2 presets (FerrofluidOcean + LumenMosaic) — the plan-walker resorts to walking the full catalog alphabetically when scoring ties are common.
2. Each preset transition runs `applyPreset` on MainActor (GPU pipeline rebuild). Cumulative load is significant.
3. When user presses Next, `advanceLocalFileQueue` runs on MainActor. If the orchestrator's plan-walker enters a tight loop after the `liveTrackPlanIndex = nextIdx` write, MainActor never gets back to finishing the advance. Hang.

### Mitigation landed (this commit)

- **Revert D-LF5-4's buildPlan() call** in `handleLocalFileReady`. LF sessions return to the pre-D-LF5-4 reactive-orchestrator behaviour: no multi-preset variety per song, but no cycling-through-alphabet bug either. The D-LF5-1 `liveTrackPlanIndex` write stays — the orchestrator just won't have a livePlannedSession to consult.
- **Diagnostic** added to `advanceLocalFileQueue`: synchronous `sessionRecorder?.log("WIRING: advanceLocalFileQueue …")` lines at each step (ENTER / audioRouter.stop BEGIN/COMPLETE / resetStemPipeline COMPLETE / orchestratorLock COMPLETE / audioRouter.start BEGIN/COMPLETE / EXIT). If the freeze recurs after this commit, the last logged step identifies the hanging call.

### Verification criteria

- 5 successive Next presses on a 3-track folder complete in < 200 ms each.
- session.log shows 3 `BEAT_GRID_INSTALL caller=trackChange` lines + 3 `raw tap capture started` lines.
- Preset transitions ≤ 3 per minute on average (reactive scheduler's normal cadence).
- WIRING breadcrumbs for advanceLocalFileQueue land at all steps without any gap > 200 ms between consecutive steps.

### Outstanding work

- Diagnose **why** the planner's alphabetical-cycle behaviour kicks in. Read `VisualizerEngine+Orchestrator.swift`'s plan-walker; investigate scoring-tie resolution; check whether the segment duration math collapses with only 2 certified presets. **Still open.**
- Re-enable buildPlan() for LF when the certified catalog reaches ≥ 5 presets AND the plan-walker is verified safe under short-segment plans. **Still open** (deferred pending catalog growth).
- ~~Identify the precise MainActor hang point from the next session capture's WIRING breadcrumbs.~~ Resolved in `53986fac` (lock-free AVFoundation teardown).
- ~~Stem-separation-after-stop CPU work~~ — verification session `2026-05-28T19-42-50Z` exposed ~12 stem separations / ~60-120 s of CPU work after Stop. Resolved by LF.5.fix.2-FU2 (stem timer cancelled in `.ended` state observer).
- ~~`elapsedTrackTime` session-monotonic across LF track changes~~ — verification session `2026-05-28T19-42-50Z` showed the orchestrator wire-active log line's `elapsedTrackTime=` growing 10.9 s → 23.0 s → 35.1 s across Next/Prev presses. Same root cause silently wrong-shaped `fv.trackElapsedS` (FFO cold-start), `featureStability` ramp-up, and recording `playbackTime` for the LF advance path. Resolved by LF.5.fix.2-FU3 (LF advance fires `mir.reset()` + `pipeline.resetAccumulatedAudioTime()` to mirror the streaming track-change callback).
- ~~`elapsedTrackTime` carries session-prep accumulation into LF playback start~~ — session `2026-05-28T20-36-17Z` showed the first `Orchestrator: wire active` line emitting `elapsedTrackTime=440.1s` after 3 s of actual playback. **Two-mover root cause**, mis-diagnosed at FU-4:
  - First mover (FU-4, commit `9f83c471`): `MIRPipeline.elapsedSeconds` is `+= deltaTime`-d every frame and not reset on LF startup. FU-4 added `mirPipeline.reset()` + `pipeline.resetAccumulatedAudioTime()` immediately before `audioRouter.start(mode:.localFilePlayback(url))` in `handleLocalFileReady`, mirroring FU-3's placement.
  - Second mover (FU-5, this commit): `VisualizerEngine.lastAnalysisTime` is initialized at `setupAudioRouting` time (engine init, [VisualizerEngine+Audio.swift:28](PhospheneApp/VisualizerEngine+Audio.swift:28)) and only updated inside `processAnalysisFrame`. With a 91 s prep window before the first audio frame, `dt = now - lastAnalysisTime ≈ 91 s` on that first frame, and that huge `dt` flows into `mir.process(deltaTime:)` at [MIRPipeline.swift:235](PhospheneEngine/Sources/DSP/MIRPipeline.swift:235) — re-adding the prep gap on a SINGLE frame, immediately after FU-4's `mirPipeline.reset()` zeroed it. Verification session `2026-05-28T21-08-33Z` showed `elapsedTrackTime=94.3s` (91 s prep gap + 3 s real playback) — FU-4 alone was insufficient. FU-5 closes the second mover by setting `lastAnalysisTime = CFAbsoluteTimeGetCurrent()` at the same instant. FU-3 (advance) didn't expose this because audio was flowing right up to `audioRouter.stop()`, so `lastAnalysisTime` was already recent.
- ~~Noisy no-op `provider.teardown ENTER`/`EXIT` breadcrumbs at every session start + advance~~. Resolved by LF.5.fix.2-FU1 (`LocalFilePlaybackProvider.stop()` skips the teardown helper when the lock-protected snapshot is all-nil).

---

### BUG-016 — Lumen Mosaic "not working" in 2026-05-21 reactive-mode sessions

**Severity:** P2 (visible degradation on one production preset; not session-blocking — Matt cycled past it in both 2026-05-21 sessions and the remaining catalog rendered correctly).
**Domain tag:** preset.fidelity
**Status:** **Resolved 2026-05-26.** Matt characterised the symptom: "black-and-white panel, no color, no motion." Code review root-caused as Candidate 1 variant (LM.4.7 zeroed-palette path, but with `LumenPatternEngine` init succeeding — not the `device.makeBuffer` failure mode CA-Presets-FU-4 was instrumented for). Fix: load the per-song palette at preset-activate, not just on track-change. Trivial-collapse increment (Matt's explicit approval, 2026-05-26). Commit pending.
**Introduced:** 2026-05-18 (LM.4.7, commit `6eef536c`). Pre-LM.4.7 the cell colour was procedural (no payload required); LM.4.7 made the shader's `lm_cell_palette` lookup depend on `lumen.palette[0..11]` populated via `setPalette(_:)`. The orchestrator-side hook (`refreshLumenPaletteForTrack` in `VisualizerEngine+Stems.swift`) was wired to fire from `resetStemPipeline` — which only fires on track change. Switching to Lumen Mosaic via `Shift+→` mid-track left the engine at its zero-initialised default palette until the next track-change event.
**Resolved:** 2026-05-26 — `VisualizerEngine+Presets.swift` LM branch now calls `refreshLumenPaletteForTrack` immediately after `LumenPatternEngine` instantiation, gated on the most-recently-resolved `TrackIdentity` (new property `lastResolvedTrackIdentity` on `VisualizerEngine`, set by the track-change handler in `VisualizerEngine+Capture.swift`). Commit pending.

---

### Expected behavior

Lumen Mosaic renders a 4-light pattern engine driving a cell-mosaic surface with per-beat cell-colour dance per the CLAUDE.md "Visual Quality Floor / Authoring Discipline" notes (preset has strong drums + vocals stem affinity; cell-depth gradient via albedo per the Failed Approach #23 scope clarification; pale-tone-share ≤ 0.30 per LM.9). Selecting Lumen Mosaic via `Shift+→` in either reactive or session-mode playback should produce the certified visual.

### Actual behavior

Matt's report: "Lumen Mosaic was not working." Symptom not characterized further. Candidate failure modes the investigation should distinguish on the next reproduction:

1. **Black or blank screen.** Suggests a Metal pipeline state failure — empty draw, missing texture binding, or shader compilation error caught only at runtime. Look in `~/Library/Logs/DiagnosticReports/` and the unified log for Metal errors near the preset switch.
2. **Stuck on a previous preset's image.** Suggests the preset apply path failed silently — `applyPreset` returned without binding the new pipeline state. Look in `session.log` for the `preset → Lumen Mosaic` line followed by zero subsequent rendering activity.
3. **Visual artifacts (corrupted geometry, garbled colours, frame-rate stutter).** Suggests a shader or buffer-binding bug. Check fragment-slot bindings, particularly slot 8 (LM.2 / D-LM-buffer-slot-8 — the 336-byte `LumenPatternEngine` UMA buffer).
4. **No audio response.** Suggests the per-frame tick or stem-affinity routing is broken. The preset's audio coupling lives in `LumenPatternEngine` (App layer) flushing state to slot 8.
5. **Pale-dominant ground (LM.9 regression).** Aggregate pale-cell share > 0.30 — would mean LM.9's cert gate isn't enforcing post-LM.4.7. Visually the panel reads as cream-dominated rather than vivid.

The prior 2026-05-21T13-58-07Z session.log shows Lumen Mosaic was active for ~11 s (lines 36–38 of that capture: `[13:59:22Z] preset → Lumen Mosaic` → `[13:59:33Z] preset → Membrane`) with no error/warning lines emitted in that window — consistent with "rendered something, but not what was expected" rather than "crashed or produced no frames."

### Reproduction steps

1. Build and launch the app: `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` then run from Xcode or `open` the built bundle.
2. Grant screen-capture permission if prompted.
3. Start music playback (Spotify, Apple Music, or any system audio source).
4. Cycle to Lumen Mosaic via `Shift+→` (8 presses from the default Waveform per the 2026-05-21 capture order: Arachne → Aurora Veil → Ferrofluid Ocean → Fractal Tree → Glass Brutalist → Gossamer → Kinetic Sculpture → Lumen Mosaic).
5. Observe: characterize the symptom against the 5 candidates above. Capture a screenshot or short video.
6. End the session normally so `session.log`, `features.csv`, `stems.csv`, `video.mp4` are all written.

**Minimum reproducer:** any music source, any track. Lumen Mosaic's failure is preset-level and should reproduce regardless of audio content. The "any track" claim needs verification — the 2026-05-21T13-58-07Z capture was Led Zeppelin "Black Dog"; whether the symptom is track-correlated or universal is part of the open diagnosis.

---

### Session artifacts

**Session directory:** `~/Documents/phosphene_sessions/2026-05-21T13-58-07Z/` (Lumen Mosaic was active from 13:59:22Z to 13:59:33Z — ~11 s of frames are buried in `video.mp4` at that timestamp range).

Additional artifacts needed on next reproduction:

- A still screenshot of the broken state (most diagnostic; the existing video has the frames but a fresh screenshot at known wall-clock is faster).
- `session.log` from a session where the user holds on Lumen Mosaic for ≥ 30 s rather than cycling past in 11 s.
- The unified-log Metal-related lines around the preset switch:
  ```
  log show --predicate 'subsystem == "com.phosphene" OR subsystem CONTAINS "Metal"' --info --last 5m
  ```

```log
[2026-05-21T13:59:22Z] preset → Lumen Mosaic     ← switch happened
[2026-05-21T13:59:26Z] stem separation 10 ...    ← +4s, stem pipeline still firing
[2026-05-21T13:59:31Z] stem separation 11 ...    ← +9s, no errors
[2026-05-21T13:59:33Z] preset → Membrane         ← Matt cycled away
```

No error or warning lines in the 11-second Lumen Mosaic window.

---

### Suspected failure class

`pipeline-wiring` OR `render-state` OR `regression` — cannot narrow without symptom characterization. The session.log silence rules out a crash; rules in: silent shader failure, wrong buffer binding, palette-library regression from LM.4.7, or a recent unintentional change to the LumenPatternEngine tick.

**Evidence for this class:** the failure is preset-specific (other presets in the cycle rendered correctly per the same session.log), Metal pipeline state binding is per-preset, and Lumen Mosaic's slot-8 fragment buffer dispatch is unique in the catalog.

---

### Verification criteria

When this defect is resolved, the following must all pass:

- [ ] Matt confirms Lumen Mosaic renders correctly in a reactive-mode session ≥ 30 s of held-on time.
- [ ] Visual matches the LM.7 reference frames in `docs/VISUAL_REFERENCES/LumenMosaic/` (if a curated reference set exists — needs verification during the diagnosis).
- [ ] Pale-tone-share ≤ 0.30 maintained per LM.9.
- [ ] `PresetVisualReviewTests` or equivalent harness still produces a recognizable Lumen Mosaic render (if such a harness exists for this preset; if not, that's a separate gap to file).

**Manual validation required:** Yes — preset.fidelity per CLAUDE.md's Defect Handling Protocol. Automated golden-hash regression is insufficient; Matt's M7-style review is the load-bearing check.

---

### Fix scope

Unknown until symptom is characterized. Candidate scopes by failure class:

- *Pipeline wiring:* small (≤ 20 LOC) — buffer binding, slot ordering, or tick closure registration in `VisualizerEngine+Presets.swift` (`applyPreset .lumenMosaic:` branch).
- *Shader / render-state:* medium — `LumenMosaic.metal` regression, possibly tied to a recent shader-library change.
- *Palette-library regression (LM.4.7):* small-to-medium — depends on which palette and which mood-mapping broke.

Filed before the diagnosis per CLAUDE.md "evidence-before-implementation" so future-Matt + future-Claude know this is open and unresolved rather than buried in chat.

### Related

CLAUDE.md §Visual Quality Floor (pale-tone-share rule per D-LM-cream-rescission); `docs/SHADER_CRAFT.md §12.1` (Lumen Mosaic cert gates); D-LM-buffer-slot-8 (slot 8 fragment-buffer reservation); D-LM-palette-library (LM.4.7 curated palettes); D-LM-cream-rescission (the rescinded categorical anti-cream rule). BUG-014 (Resolved via LM.4.7 — verify no orchestrator-side scoring path encodes the pre-LM.4.7 palette assumption; this BUG-016 is a separate observed failure post-LM.4.7).

---

### Addendum (CA-Presets, 2026-05-21)

The Presets-Swift capability audit ([`docs/CAPABILITY_REGISTRY/PRESETS.md`](../CAPABILITY_REGISTRY/PRESETS.md)) read `LumenPatternEngine.swift` + `LumenMosaicPaletteLibrary.swift` end-to-end and characterised one Swift-side candidate root cause for the symptom:

**LumenPatternEngine.init? silently fails on `device.makeBuffer` failure.** At `LumenPatternEngine.swift:580-585`:

```swift
public init?(device: MTLDevice, seed: UInt64 = 0) {
    let bufSize = MemoryLayout<LumenPatternState>.stride  // 568 bytes
    guard let buf = device.makeBuffer(length: bufSize, options: .storageModeShared) else {
        return nil   // ← silent — no os.Logger, no sessionRecorder
    }
    ...
}
```

The init returns nil with **no logging from the Presets-module-internal side**. The App-side construction at `VisualizerEngine+Presets.swift:423-433` catches the nil and logs via `logger.error(...)` to category `"com.phosphene.app"` — but that line does NOT reach `session.log` (which is the engine-module `Logging.session` channel).

**Mapping CA-Presets findings to the 5 candidate failure modes above:**

| Candidate | CA-Presets verdict |
|---|---|
| 1. Black/blank screen | **PLAUSIBLE.** If `device.makeBuffer(568 bytes, .storageModeShared)` fails (memory pressure, GPU-device disconnect, etc.), `lumenPatternEngine` stays nil → App-side falls through without binding slot 8 → `LumenMosaic.metal` reads zeroed `LumenPatternState` → renders against the LM.4.7 zeroed-palette path. **Verifiable on next reproduction:** check session.log for an `os.Logger.error("LumenPatternState: failed to allocate state")` line near the preset switch (it would be in the unified log via `log show --predicate 'subsystem CONTAINS "com.phosphene"'`, but NOT in session.log without the FU-4 instrumentation fix). |
| 2. Stuck on previous preset | Out of Presets-Swift scope (App-layer `applyPreset` switch logic). |
| 3. Visual artifacts | Out of Presets-Swift scope (`LumenMosaic.metal` shader). |
| 4. No audio response | **PLAUSIBLE.** `LumenPatternEngine._tick` updates band counters only on `f.beatPhase01` wraps (from > 0.85 to < 0.15). **No FFT fallback** (documented at `LumenPatternEngine.swift:895-898` as a known LM.4.3 limitation). If `f.beatPhase01` stays at 0 (reactive mode pre-grid, or silence), no counters advance and the panel reads static. **Verifiable on next reproduction:** check features.csv for `beat_phase01` values across the affected window. If identically 0 → Mode 4 confirmed → known reactive-mode limitation. |
| 5. Pale-dominant LM.9 regression | Verifiable via offline color analysis of `LumenMosaicPaletteLibrary.all` 18 palettes against the ≤ 0.30 pale-share gate. **Note:** the pale-share ceiling is NOT enforced as a FidelityRubric automated item — it is M7-manual-only. |

**Recommended diagnostic upgrade (filed as CA-Presets-FU-4):** add `Logging.session?.log("LumenPatternEngine init failed: device.makeBuffer returned nil for \(bufSize) bytes")` to the App-side construction failure branch at `VisualizerEngine+Presets.swift:433` (additive — keep the `logger.error` line). Closes the silent-init-failure diagnosis gap for the next reproduction.

**No code changes landed in this addendum** — the audit is read-only; fixes wait for Matt's reproduction + scope authorisation.

---

### Addendum (CA-Presets-FU-4 instrumentation landed, 2026-05-21)

The diagnostic upgrade recommended above shipped as CA-Presets-FU-4 (commit `cb8cb0bb`). Two corrections to the previous addendum's recipe were applied:

1. **Channel routing.** The previous addendum proposed `Logging.session?.log(...)` for the App-side site. That is structurally wrong: `Logging.session` is an `os.Logger` (not Optional, not a `SessionRecorder`), so it does NOT write to the on-disk `session.log` file. The on-disk file is owned by `SessionRecorder.log(_:)`. The shipped instrumentation covers BOTH channels:
   - **App-side** (`VisualizerEngine+Presets.swift:172-186`): `sessionRecorder?.log(...)` writes to the on-disk `session.log` file (greppable without `log show` invocation).
   - **Engine-internal** (`LumenPatternEngine.swift:583-595`): `Logging.session.error(...)` writes to the unified log under category `"session"` (captures even from App-side caller variants that don't have `SessionRecorder` in scope).

2. **Site line numbers.** The previous addendum cited `VisualizerEngine+Presets.swift:423-433` as the App-side LumenMosaic construction site. Those lines belong to the AuroraVeil branch. The actual LumenMosaic site is at lines 165-187 (the `if desc.name == "Lumen Mosaic"` block inside `applyPreset .rayMarch`).

**Retrieval predicates for the next reproduction:**

```bash
# On-disk session.log (App-side SessionRecorder write)
grep "LumenPatternEngine: failed to allocate slot-8 buffer" \
  ~/Documents/phosphene_sessions/<ts>/session.log

# Unified log (engine-internal Logging.session.error write)
log show --predicate 'subsystem == "com.phosphene" AND category == "session"' \
  --info --last 30m | grep "LumenPatternEngine init failed"
```

**BUG-016 stays Open.** Instrumentation is not a fix. The next reproduction should:
1. Reproduce the failure (Lumen Mosaic visible degradation in a reactive-mode session).
2. Check both predicates above. If either fires, Candidate 1 (Black/blank screen via silent `device.makeBuffer` nil) is confirmed and the fix scope is "make `LumenPatternState` allocation more robust" or "investigate why `.storageModeShared` is failing at 568 bytes on Matt's hardware."
3. If neither predicate fires, the failure is one of the other 4 candidate modes (stuck-on-previous, visual artifacts, no-audio-response, or pale-dominant LM.9 regression) — proceed with the per-candidate diagnosis path.

---

### Addendum (Resolution, 2026-05-26)

Matt characterised the symptom on 2026-05-26: "black-and-white panel, no color, no motion." Code review traced this to a Candidate-1 *variant* — the LM.4.7 zeroed-palette path *with `LumenPatternEngine` init succeeding* — distinct from the silent `device.makeBuffer` failure mode the CA-Presets-FU-4 instrumentation was looking for.

**Concrete failure path.**

1. User starts a session; a track is playing; some other preset is active.
2. `resetStemPipeline → refreshLumenPaletteForTrack` runs at track-change, but is no-op because `lumenPatternEngine == nil` (LM isn't yet the active preset).
3. User cycles to Lumen Mosaic via `Shift+→`. `applyPreset .rayMarch` branch instantiates `LumenPatternEngine(device:)` — init succeeds, no `device.makeBuffer` failure. The palette is the all-zero default from the `LumenPatternState` initializer (`LumenPatternEngine.swift:305-312`).
4. `setPalette(_:)` has no call site between LM activation and the next track change. The palette stays all-zero until that next track-change fires `resetStemPipeline`.
5. The shader's `lm_cell_palette` lookup (`LumenMosaic.metal:539-578`) returns `(0,0,0)` for every cell. The cell-boundary frost halo (`LumenMosaic.metal:775-779`) mixes `cell_hue (=0)` toward `float3(1.0f)` at boundaries. Visual reading: a black Voronoi grid with white frost halos at cell edges — Matt's "black-and-white panel."
6. Motion is internally present (`bassCounter`/`midCounter`/`trebleCounter` advance on each beat; `lm_cell_palette`'s palette index walks deterministically), but every palette slot resolves to the same colour (black), so the visual reading is "no motion."

**Why the CA-Presets-FU-4 instrumentation didn't fire.** That instrumentation guards the `init? returns nil` path. The actual failure path has init returning a valid engine — only the palette payload is the zero default. No log line is produced because nothing is wrong from the engine's POV; the failure is the *absence* of a `setPalette` call from the app-side activation path.

**Fix landed (2026-05-26).**

- New `var lastResolvedTrackIdentity: TrackIdentity?` on `VisualizerEngine` (`VisualizerEngine.swift`), set by the track-change handler in `VisualizerEngine+Capture.swift` after `canonicalTrackIdentity(matching:)` resolves the identity. Internal-only (not `@Published`); view models continue to bind to `currentTrack` / `currentTrackIndex`.
- `refreshLumenPaletteForTrack(identity:lumenEngine:)` in `VisualizerEngine+Stems.swift` promoted from `private` to `internal` (default) so `applyPreset` in `VisualizerEngine+Presets.swift` can call it.
- `VisualizerEngine+Presets.swift` LM branch (lines 163-186) now calls `refreshLumenPaletteForTrack` immediately after `LumenPatternEngine` instantiation, gated on `lastResolvedTrackIdentity`. When the user activates LM mid-track, the palette is populated from the same library + mood-bias path that runs at track-change.

**Regression coverage.** New `LumenPalettePayloadTests` suite (`PhospheneEngine/Tests/PhospheneEngineTests/Presets/LumenPatternEngineTests.swift`) — two contract tests:

- `test_freshEngine_paletteIsAllZero` — documents the BUG-016 trap. A future change that seeds the engine with a non-zero default palette will trip this test, at which point the app-side `refreshLumenPaletteForTrack` call in `applyPreset` becomes redundant and can be removed.
- `test_setPalette_populatesAllTwelveSlots` — locks the `setPalette → snapshot.palette` contract that the app-side fix relies on.

**Verification criteria.**

- [x] **Automated:** engine test suite (1267 tests, 162 suites) passes; new `LumenPalettePayloadTests` suite passes (2 / 2). App test suite passes aside from 5 pre-existing parallel-execution timing flakes (`AppleMusicConnectionViewModelTests` ×4 + `ToastManagerTests/autoDismiss_afterDuration`) — all 5 pass in isolation, none touch LM code paths.
- [x] **Manual (Matt):** Lumen Mosaic renders the certified vivid stained-glass visual when activated via `Shift+→` mid-track in a reactive-mode session ≥ 30 s held-on time. Per-beat palette dance is visible. No black-and-white-grid symptom. **Confirmed 2026-05-26** ("It works"). Black-and-white-grid symptom gone on mid-track switch.

**Manual validation is the load-bearing gate** per CLAUDE.md's Defect Handling Protocol for `preset.fidelity` domain. The new contract tests document the trap but cannot prove the visual symptom is gone — only Matt's M7-style review can.

**Trivial-collapse approval.** Matt explicitly approved the trivial-collapse single-increment process on 2026-05-26 (the standard P1/P2 protocol is five separate increments). Justification: < 30 LOC of behavior change, root cause obvious from code review, no architectural risk (additive call to an existing function with an existing identity).

---

