# Phosphene — Known Issues

Open and recently-resolved defects. Filed using `BUG_REPORT_TEMPLATE.md`. See `DEFECT_TAXONOMY.md` for severity definitions and process.

---

## Open

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

- Diagnose **why** the planner's alphabetical-cycle behaviour kicks in. Read `VisualizerEngine+Orchestrator.swift`'s plan-walker; investigate scoring-tie resolution; check whether the segment duration math collapses with only 2 certified presets.
- Re-enable buildPlan() for LF when the certified catalog reaches ≥ 5 presets AND the plan-walker is verified safe under short-segment plans.
- Identify the precise MainActor hang point from the next session capture's WIRING breadcrumbs.

---

### BUG-020 — Mid-track state reset (track-change callback firing spuriously)

**Severity:** P1 (visible artifact during steady-state playback — reported by Matt CSP.3.5 M7 of session `2026-05-28T18-31-06Z` as "some flickering around 40 s into playback for Love Rehab" after BUG-019 close).
**Domain tag:** `pipeline-wiring`
**Status:** Open — diagnostic instrumentation about to land (PERF-style diagnose-first pattern); root cause not yet identified.
**Introduced:** Unknown; surfaced 2026-05-28 during CSP.3.5 M7 review. Was likely masked by the chronic PERF.3-era flicker before that fix landed.

### Expected behavior

Once a track starts playing, `accumulatedAudioTime`, `valence`, `arousal`, `beatPhase01`, `bassAttRel`, and related per-track accumulators evolve smoothly until the next genuine track-change event. No mid-track state resets.

### Actual behavior

In session `2026-05-28T18-31-06Z`, at session-time 83.728 s (≈ 38 s into Love Rehab playback), the visualizer state resets within a single frame:

| Feature | Frame before (rel=83.711) | Frame after (rel=83.728) |
|---|---:|---:|
| `time` (wall-clock) | 122.28 | 122.30 (monotonic, fine) |
| `accumulatedAudioTime` | 5.8008 | **0.0002** |
| `valence` | 0.006 | **1.000** |
| `arousal` | 0.289 | **0.000** |
| `beatPhase01` | 0.834 | **0.000** |
| `bassAttRel` | -0.912 | -0.995 |

The pattern matches a track-change event firing (`mir.reset()` + `pipeline.resetAccumulatedAudioTime()` synchronously at `VisualizerEngine+Capture.swift:154-155`), but **the session log shows NO track-change event at that moment** — only "stem separation 6" at 18:32:30 (which doesn't touch these fields). The next logged track-change is Money at session-time 122 s.

The session-recorder log line for track-change is inside an async `Task { @MainActor }` block (lines 140-153 of the same file); the `mir.reset()` + `resetAccumulatedAudioTime()` fire synchronously OUTSIDE that task. This asymmetry means a spurious callback invocation can reset state without producing a corresponding log line, if the MainActor task is dropped/deferred/superseded.

Matt's perceptual symptom — flicker at 40 s into Love Rehab — maps directly: the visual state lurches because every state that drives FFO's appearance (mood tint, accumulated time for Gerstner waves, beat phase) snaps to defaults/extremes in one frame.

### Reproduction steps

1. Build PhospheneApp current main.
2. Start an LF playback session with love_rehab.m4a (the M7 session's source).
3. Play the file continuously past 40 s.
4. Observe: visible visual lurch around 38–40 s into playback. `features.csv` shows the multi-field reset at the same wall-clock moment.

**Minimum reproducer:** any track ≥ 40 s long played continuously without manual intervention. Whether it's content-specific or session-uptime-driven not yet determined.

### Session artifacts

- **Primary:** `~/Documents/phosphene_sessions/2026-05-28T18-31-06Z/features.csv` — columns 22 / 19 / 20 / 23 / 26 show the reset pattern at frame ~5000.
- **Session log:** `~/Documents/phosphene_sessions/2026-05-28T18-31-06Z/session.log` — notable for the ABSENCE of a track-change line at 18:32:29.

### Suspected failure class

`pipeline-wiring`. Working hypotheses, none confirmed:

1. **Track-change publisher re-emits same-track event.** The publisher chain (Spotify metadata polling? LF playback metadata refresh? `AudioInputRouter` mode switch?) emits a `TrackChangeEvent` where `current` matches the actually-still-playing track. The callback fires its destructive reset regardless of whether the title changed.
2. **A second publisher is also fanning out track-change events.** LF.5 added file-association + Recents — if one of those paths emits its own track-change event for a same-file re-open, the callback fires.
3. **An orchestrator-driven re-evaluation triggers the callback.** Less likely given how the callback is wired, but worth ruling out.
4. **A timer-driven metadata-fetcher periodic refresh.** `MetadataPreFetcher` may be re-emitting on a fetch completion.

### Verification criteria

When this defect is resolved, the following must all pass:

- [ ] Automated: `features.csv` from a 60 s continuous-playback session shows no mid-track reset of `accumulatedAudioTime`, `valence`, `arousal`, `beatPhase01`.
- [ ] Manual: Matt's FFO M7 on a continuous-playback session of ≥ 60 s on any track reports no mid-track flickering/lurching.

**Manual validation required:** Yes. Perceptual confirmation required.

### Fix scope

Unknown until diagnose step lands. Multi-increment per the P1 defect protocol:

1. **Diagnostic instrumentation (BUG-020.diag)** — add synchronous log line at the top of the `makeTrackChangeCallback` callback so EVERY invocation is captured with `current` + `previous` + timestamp, regardless of whether the @MainActor task runs. Capture a session; identify the spurious caller.
2. **Diagnosis (BUG-020.cause)** — read the captured log; identify the publisher + caller chain producing the spurious event. Document root cause in this entry.
3. **Fix (BUG-020.fix)** — either eliminate the spurious publisher emission, or guard the callback's reset behind a same-track-identity short-circuit, depending on where the bug is.

### Related

- BUG-019 closeout (`[dev-2026-05-28-i]`) — this bug was masked by PERF.3-era brightness flicker before that fix landed; surfaced once the brightness residual stabilised.
- `[dev-2026-05-28-j]` LF.5 — added LF.5 multi-file playback path, a candidate source of spurious events.
- CLAUDE.md "What NOT To Do": "Do not match plan entries against the live track via lowercased title+artist string." That rule is about *plan walks*, not track-change events, but the underlying lesson (don't trust title+artist for identity) may apply if the publisher chain is using imprecise matching.

---

### BUG-LF5-1 — Orchestrator stayed REACTIVE for LF.5 multi-file sessions

> **RESOLVED 2026-05-28** — commit `488afc1e` (`[LF.5.fix] D-LF5-1 + D-LF5-2`). Mirrored `makeTrackChangeCallback`'s orchestrator wire in `handleLocalFileReady` (planIdx=0) and `advanceLocalFileQueue` (planIdx=nextIdx).

**Severity:** P1. **Domain tag:** `pipeline-wiring`.
**Expected:** With an N-track `SessionPlan`, the orchestrator runs in planned mode and applies a per-track preset on each `currentTrackIndex` change.
**Actual:** Folder session `2026-05-28T17-06-08Z` log line 33: `Orchestrator: wire active (mode=reactive, planIdx=—, elapsedTrackTime=55.1s)`. Zero preset changes at the 8 track boundaries; the 4 preset transitions logged at 17:07:06–07 were autonomous reactive picks.
**Root cause:** Streaming wires the orchestrator via `makeTrackChangeCallback` (`VisualizerEngine+Capture.swift:129`), which sets `liveTrackPlanIndex` under `orchestratorLock` so the analysis-queue `runOrchestratorLiveUpdate` can see the plan. LF.5's `handleLocalFileReady` + `advanceLocalFileQueue` updated the published `currentTrackIndex` but never wrote `liveTrackPlanIndex` — analysis queue saw `nil` → stayed reactive.
**Verification:** next folder session log should emit `Orchestrator: wire active (mode=planned, planIdx=0)` immediately after the first BeatGrid install + `planIdx=N` on each subsequent track change.

---

### BUG-LF5-2 — End Session did not stop LF audio playback

> **RESOLVED 2026-05-28** — commit `488afc1e` (`[LF.5.fix] D-LF5-1 + D-LF5-2`). Extended the `sessionManager.$state` `.sink` in `VisualizerEngine` init to call `audioRouter.stop()` on `.ended`.

**Severity:** P1. **Domain tag:** `pipeline-wiring`.
**Expected:** Clicking "End session" on `PlaybackView` chrome (or the new transport-bar Stop button) stops local-file audio. Phosphene IS the player for LF sessions.
**Actual:** SessionManager transitioned to `.ended`, ContentView routed to EndedView, but audio kept playing because `LocalFilePlaybackProvider`'s `AVAudioEngine` was never torn down.
**Root cause:** `SessionManager.endSession()` only clears `currentSource` + flips state. The streaming-path equivalent is fine because Spotify/Apple Music owns playback there; for LF Phosphene owns playback and needs an explicit teardown.
**Verification:** session log after clicking End Session should show no further `stem separation N` lines (router stopped → no audio frames → no analysis ticks).

---

### BUG-LF5-3 — No music-player transport controls for LF sessions

> **RESOLVED 2026-05-28** — commit `fe09a594` (`[LF.5.fix] D-LF5-3`). Hover-revealed Stop / Prev / Play-Pause / Next transport bar at the bottom-center of `PlaybackView` for `currentSource?.isLocalFile == true`. UX-2 amended in `UX_SPEC.md §7.3` + §10 to carve out the LF carve-out.

---

### BUG-LF5-4 — LF.5 sessions never built the multi-segment PlannedSession

> **RESOLVED 2026-05-28** — commit `46a9f1c2` (`[LF.5.fix] D-LF5-4`). Surfaced by Matt's follow-up to D-LF5-1 closeout: "what happened to multiple presets per song?" One-line fix — call `buildPlan()` from `handleLocalFileReady` after the cache install + before the orchestrator wire.

**Severity:** P1. **Domain tag:** `pipeline-wiring`. **Companion to:** BUG-LF5-1 (which by itself was necessary but not sufficient — orchestrator could not run planned mode without a `livePlannedSession` to consult).
**Expected:** Multi-preset-per-song behaviour per `feedback_multi_preset_per_song.md` — the planner picks the best *set* of presets per track with intra-track segment boundaries placed where the music supports transitions.
**Actual (pre-fix):** `livePlannedSession == nil` for every LF.5 session; orchestrator had nothing to consult. Even after D-LF5-1's `liveTrackPlanIndex` writes landed, planned mode could not engage. Behaviour at the user surface: at best one autonomous-reactive preset per track-change boundary; in practice the reactive scheduler drifted on its own cadence (~7 s) ignoring boundaries entirely.
**Root cause:** VisualizerEngine's `.ready` observer branches on `currentSource?.isLocalFile` — streaming calls `buildPlan()`, LF calls `handleLocalFileReady()`. `handleLocalFileReady` installed BeatGrid + started audio but never called `buildPlan()`. The branching split was structural to LF.4's original wire-up and inherited by LF.5 without re-examination.
**Verification:** session log should show `Orchestrator: wire active (mode=planned, planIdx=0)` immediately after the first BeatGrid install and emit multiple `preset → <name>` lines within each track's playback window (matching the segmentation `SessionPlanner.plan(...)` generated for that track-and-trackProfile pair).

**Severity:** P2 (UX-spec gap rather than a code defect).
**Expected (Matt 2026-05-28):** Music-player UX with pause/skip/stop/forward/back when the user hovers during LF playback.
**Actual (pre-fix):** PlaybackView chrome had only "End session," which itself was broken (BUG-LF5-2). No way to pause, skip, or step back.
**Fix scope:** new `LocalFilePlaybackProvider.pause()` / `resume()` + `AudioInputRouter` shims + `VisualizerEngine.{togglePauseLocalFile, skipToNext/PreviousLocalFileTrack, stopLocalFilePlayback}` + `advanceLocalFileQueue(direction:)` extension + `LocalFileTransportBar` SwiftUI view + chrome wiring + 10 localized strings.
**Verification:** manual smoke — hover over playing window, transport bar appears centered at bottom; clicking Stop returns to IdleView with audio stopped; Prev at index 0 is a no-op; Play/Pause toggles audio without losing playhead; Next advances or transitions to EndedView at queue end.

---

### BUG-019 — Beat-dominant light intensity + spike-strength dead zone caused visible flicker on FFO

> **RESOLVED 2026-05-28** — Matt M7 verdict "Better" on session `2026-05-28T13-50-23Z` (CSP.3.4 build). Four-fix chain (PERF.3 + CSP.3.2 + CSP.3.3 + CSP.3.4) addressed the visible flicker / inactivity / artifact symptoms Matt has reported "since FFO existed." The originally-filed CPU-bump pattern (a separate phenomenon observed in two sessions) is characterized as probably-environmental and not actively pursued unless it returns with a clear non-environmental signal. Each fix went through its own M7 in succession; the chain is detailed under "Fix scope" below.

> **AMENDED 2026-05-28 — root cause re-characterized.** Initial filing described BUG-019 as "CPU frame time degrades after ~60 s of session uptime." That CPU bump pattern was observed in two sessions (`2026-05-27T21-12-48Z`, `2026-05-27T21-48-28Z`) but PERF.2-pass instrumentation (capture `2026-05-27T22-49-42Z`) ruled out the audio analysis pipeline AND the per-ray-march-sub-pass dispatch as the source. The CPU bump appears to be probably-environmental (system-level memory pressure / GPU contention) and intermittent. Meanwhile the **consistent visible perceptual symptom Matt has reported "since FFO existed"** — flickering, lag, brief hangs, coming out of sync — was caught by ffmpeg signalstats on `2026-05-27T22-49-42Z`'s rendered video.mp4: 76 brightness-oscillation events across 200 s, each aligned with a beat-detector firing. Root cause: `applyAudioModulation` in `RenderPipeline+RayMarch.swift` had `intensityMul = 0.4 + beatPulse * 2.6` — beat 6.5× the baseline, direct violation of CLAUDE.md Failed Approach #4 ("beat is accent, never primary"). Every beat fired a 2.1× single-frame brightness multiplier swing. Fix landed as PERF.3 (`RELEASE_NOTES_DEV.md [dev-2026-05-28-e]`); M7 pending.

**Severity:** P1 (load-bearing for "FFO doesn't flicker" — Matt's quality bar across multiple iterations; the symptom blocked the SAR.1 / CSP.3 / CSP.3.1 M7s).
**Domain tag:** `perf` → amended to `renderer` (per-frame lighting content, not timing).
**Status:** **Resolved 2026-05-28** against Matt's CSP.3.4 M7 ("Better") on session `2026-05-28T13-50-23Z`. Brightness oscillation count stabilised at 53–60 events across post-fix sessions (vs 76 pre-fix). Visible spike-tip artifacts gone. Continuous spike-height modulation throughout each track. PERF.3 brightness fix unchanged across the CSP.3.x iterations.
**Introduced:** The `applyAudioModulation` formula has existed since the deferred ray-march path was first added — predates any of the recent preset work. The bug is structural to the engine's preset-agnostic lighting modulation. Matt's "this has existed for as long as FFO has existed" is consistent — FFO surfaces this most loudly because of its dark-substrate-with-mirror-reflections character.
**Resolved:** 2026-05-28. Four-fix chain: PERF.3 (commit `f0627c19`) + CSP.3.2 (`acf357dd`) + CSP.3.3 (`21874a13`) + CSP.3.4 (`62704e16`). See "Fix scope" below for the full sequence.

### Expected behavior

CPU frame time stays under the 60 fps budget of 16.67 ms for the full duration of a session. p95 sits comfortably under tier budget; no sustained over-budget windows during steady-state playback. No visible flickering / artifacts / hangs.

### Actual behavior

CPU frame time roughly doubles around 60–68 seconds of session uptime and remains elevated for the rest of the session. GPU frame time is stable throughout — the bottleneck is purely CPU, not the render pipeline.

**M7 session evidence — `2026-05-27T21-12-48Z` (post-SAR.1, tap path, FFO preset, Billie Jean → Superstition):**

| Window (session-time) | CPU avg | CPU max | GPU avg | GPU max |
|---|---:|---:|---:|---:|
| 0–60 s | 10–12 ms | 16–18 ms | 8–10 ms | 14–15 ms |
| 66–90 s | **22–24 ms** | **28–30 ms** | 8–10 ms | 14–15 ms |

At 22–24 ms per frame, roughly 1 in 3 frames misses the 16.67 ms deadline. Matt's perceptual report: "Screen flickers and it looks like there are visual artifacts for a split second while the screen temporarily hangs. Looks like a performance bug — like the visualizer is overloaded." Matt's timing estimate ("around 25 s through end of playback") aligns with ~15 s into Superstition (the second track) where session-time hits 68 s — i.e. the symptom appears in the second track because the trigger window happens to fall inside it.

Within the elevated window the per-frame trace shows a periodic ~250 ms sawtooth (~4 Hz), suggesting one or more subsystems doing burst work on that cadence rather than per-frame steady cost.

**Pre-SAR.1 reference — `2026-05-27T19-52-42Z` (pre-fix, tap path, same general track set):**

| Window (session-time) | CPU avg | CPU max |
|---|---:|---:|
| 0–50 s | 13.7 ms | 17–18 ms |
| 60–90 s | **17–18 ms** | **30.6 ms (60–70 s window); one 103.9 ms spike at 70–80 s** |

Same shape, less severe in averages but with a much worse one-off spike. The two sessions confirm the pattern is pre-existing rather than introduced by SAR.1.

**LF-path sessions (`2026-05-27T19-44-25Z`, `2026-05-27T19-47-18Z`) ran at 1.3–1.4 ms CPU avg throughout** — local-file playback bypasses the process tap path and shows none of this degradation. The bottleneck lives in the tap-path live-analysis pipeline, not in any shared component.

### Reproduction steps

1. Build PhospheneApp (current `main`, post-SAR.1 — the bug pre-dates SAR.1 so any recent build will reproduce).
2. Start an ad-hoc tap-path session (Spotify prepared playlist, FFO preset).
3. Play tracks continuously past the 60 s session-uptime mark.
4. Observe: visible flickering / brief hangs from ~60 s session-time onwards; `features.csv` `frame_cpu_ms` column doubles from ~10 ms to ~22 ms in the same window.

**Minimum reproducer:** any tap-path session that runs continuously past ~60–70 s. Track content does not appear to matter; the trigger correlates with session uptime, not track-specific audio.

### Session artifacts

- **Primary:** `~/Documents/phosphene_sessions/2026-05-27T21-12-48Z/features.csv` — columns 36 (`frame_cpu_ms`) and 37 (`frame_gpu_ms`) show the doubling at frame ~4080 (session-time 67–68 s).
- **Pre-SAR.1 reference:** `~/Documents/phosphene_sessions/2026-05-27T19-52-42Z/features.csv` — same shape, slightly milder.
- **LF-path counter-example:** `~/Documents/phosphene_sessions/2026-05-27T19-44-25Z/features.csv` and `~/Documents/phosphene_sessions/2026-05-27T19-47-18Z/features.csv` — sustained 1.3–1.4 ms CPU throughout, ruling out shared (renderer / GPU / common-DSP) components.

### Suspected failure class

`resource-management` (most likely) or `algorithm`. Working hypotheses, none confirmed:

1. **Accumulating state in the tap-path live-analysis pipeline.** The stem separator runs every 5 s; the live stem analyzer feeds the analyzer per frame. Some component may be accumulating bookkeeping (lists, ring buffers, EMA state) that gets walked or copied on every frame, with cost that grows over session uptime.
2. **A code-path that engages after a track-elapsed-time gate.** Live stems converge ~13–15 s into a track (the CSP.3 timeline). If the live path has heavier per-frame cost than the cached path, and live stems coming online during the *second* track (after ~60 s session-time) coincides with the trigger window, the bump would land where it does. Doesn't explain why the same gate didn't fire 15 s into the first track at session-time ~22 s where CPU was still ~11 ms.
3. **Cross-track state-reset incompleteness.** A buffer / accumulator / EMA owned by an analysis component isn't being cleared on track change and is paying a cost that's a function of how much data it has seen so far.
4. **Thermal throttling.** Apple Silicon performance cores can throttle if sustained CPU load pushes thermal headroom; the M7 session was the second of several runs that afternoon. Doesn't fully explain why GPU stays flat (thermal usually affects both).

The ~4 Hz / 250 ms sawtooth visible in the per-frame CPU trace is a discriminator — something is firing on that period after the trigger, and identifying it would likely identify the subsystem.

**Evidence for `resource-management`:** the same shape appears in multiple independent sessions, the trigger is session-uptime-driven not audio-content-driven, and the LF path (which bypasses some analysis components) is completely unaffected.

### Verification criteria

When this defect is resolved, the following must all pass:

- [ ] Automated: `FrameTimingReporter` p95 ≤ tier budget (Tier 2 budget 16.67 ms at 60 fps) over a 90 s continuous tap-path session.
- [ ] Automated: 2-hour `SoakTestHarness` run shows no monotonic CPU-time growth past tier budget.
- [ ] Domain artifact: `features.csv` from a 90 s tap-path session shows `frame_cpu_ms` distribution with no second-half doubling vs first-half.
- [ ] Manual: Matt's FFO M7 (or any other certified preset M7) — no perceived flickering / hangs / artifacts throughout a continuous-playback session of ≥ 90 s.

**Manual validation required:** Yes. The defect surfaced as a perceptual report; closing it requires a perceptual confirmation, not just a green automated gate.

### Fix scope

Unknown — needs the instrumentation increment first. **Multi-increment** per the P1 defect protocol:

1. **Instrumentation (PERF.1) ✅ 2026-05-28** — five new `features.csv` columns. See `RELEASE_NOTES_DEV.md [dev-2026-05-28-b]`.
2. **Diagnosis (PERF.2) ✅ 2026-05-28** — analysis pipeline ruled out.
3. **Instrumentation extension (PERF.2-render) ✅ 2026-05-28** — `encode_cpu_ms` + `renderframe_cpu_ms`. See `[dev-2026-05-28-c]`.
4. **Diagnosis (PERF.2-render) ✅ 2026-05-28** — bump localised to `renderFrame()` pass dispatch.
5. **Instrumentation extension (PERF.2-pass) ✅ 2026-05-28** — four sub-pass columns. See `[dev-2026-05-28-d]`.
6. **Diagnosis (PERF.2-pass) ✅ 2026-05-28** — session `2026-05-27T22-49-42Z`: all four sub-passes flat across a Matt-confirmed flicker session. **CPU bump pattern is NOT in our render-path code.** The chronic perceptual flicker, separately diagnosed via ffmpeg signalstats on the same session's video.mp4, traces to the beat-dominant `applyAudioModulation` formula.
7. **Fix (PERF.3) ✅ 2026-05-28** — `intensityMul` formula restructured: `1.0 + bass * 0.4 + beatAccent * 0.15` (was `0.4 + beatPulse * 2.6`). Single-frame brightness swing reduced 14×. See `[dev-2026-05-28-e]`.
8. **Validation (PERF.3 M7) ✅ 2026-05-28 — partial-pass** — Matt's session `2026-05-28T03-10-29Z`: brightness flicker reduced ("Love Rehab looked great for about a minute") + `ffmpeg signalstats` count dropped 76 → 57 events (25 %). New visible issue surfaced — "inactivity from the spikes" — root-caused to `stems.bass_energy_dev` averaging 0.05–0.10 in warm state, making CSP.3.1's `+0.35 × bass_energy_dev` term effectively zero. PERF.3 had been masking this with its own brightness flicker.
9. **Fix (CSP.3.2) ✅ 2026-05-28** — `fo_spike_strength` dropped the warm-state crossfade to `stems.bass_energy_dev`; uses `f.bass` (AGC-normalised continuous Layer 1) for the whole track. Same shape as PERF.3 — continuous primitive primary, no deviation-primitive dead zones — applied to spike geometry. See `[dev-2026-05-28-f]`.
10. **Validation (CSP.3.2 M7) ✅ 2026-05-28 — partial-pass** — session `2026-05-28T13-20-21Z`: irregular behavior gone (confirmed by Matt) and continuous modulation throughout track (confirmed by data), but magnitude too small. The 0.35 coefficient (inherited from pre-CSP.3.2) was tuned against the deviation primitive's pre-SAR.1 saturation; for `f.bass`'s actual distribution (85 % of frames < 0.3), 0.35 produces < 11 % modulation — below perception.
11. **Fix (CSP.3.3) ✅ 2026-05-28** — coefficient bump 0.35 → 0.8. Typical modulation 17 %, peaks 40 %. See `[dev-2026-05-28-g]`.
12. **Validation (CSP.3.3 M7) ✅ 2026-05-28 — partial-pass** — session `2026-05-28T13-31-47Z`: "spike subtlety has been addressed sufficiently" + irregular behavior gone — but gray-tip artifacts on heavy bass hits in Money + flickering around 38 s into Love Rehab. Diagnosed as Lipschitz overshoot: post-CSP.3.3 spike strengths (1.25–2.05) produce effective gradients (4.6–7.5) exceeding the `/4` divisor's safe ceiling (4).
13. **Fix (CSP.3.4) ✅ 2026-05-28** — Lipschitz divisor `/4` → `/10`. See `[dev-2026-05-28-h]`.
14. **Validation (CSP.3.4 M7) ✅ 2026-05-28** — session `2026-05-28T13-50-23Z`: Matt verdict "Better." Brightness oscillation events 60 (within the post-PERF.3 band of 53–60 — fix unchanged). Gray-tip artifacts and 38 s Love Rehab flicker gone. Spike-height magnitude preserved from CSP.3.3. BUG-019 closed against the original symptom.
15. **Post-close regression — CSP.3.4 side effects** — Matt M7 of session `2026-05-28T17-50-42Z` (LF playback, love_rehab.m4a) reported "white artifacts at spike tips close to camera + white substrate patches in the far-left corner." Diagnosed: CSP.3.4's `/10` divisor made each ray-march step 60 % smaller than `/4`; the 128-step iteration cap (`PresetLoader+Preamble.swift:418`, unchanged) was exhausted on rays at oblique view angles → fell to "Sky / miss" path → FFO's matID == 2 mirror paradigm rendered procedural sky as white. Also breached the 60 fps CPU budget (17.14 ms avg vs 16.67 ms ceiling).
16. **Fix (CSP.3.5) ⚠ doc-only 2026-05-28** — commit `eaaadd9b` claimed divisor `/10` → `/6` but rewrote only the comment block; the operative `return (p.y - surfaceY) / 10.0;` line was unchanged. Surfaced by `PresetAcceptanceTests.test_readableForm_atSteadyEnergy` reproducibly failing on Ferrofluid Ocean across the CSP.3.4→CSP.3.5.1 interval (`formComplexity → 1`, every pixel rendering as sky/miss because `/10` starves the hardcoded 128-step march budget at the rubric fixture). The trade-off analysis (covers all typical playback: Money 1.36, LR ≤ 1.30, M7 session 1.52; rare `f.bass ≥ 1.0` peaks may produce brief gray-tip flicker) stands and applies to CSP.3.5.1. See `[dev-2026-05-28-n]` (with AMENDED note).
17. **Validation (CSP.3.5 M7) — superseded** — Matt did not M7 `/6` against the CSP.3.5 build because `/10` was still operative. The M7 protocol (white artifacts gone, CPU back under budget, spike magnitude preserved from CSP.3.3, PERF.3 brightness fix preserved) applies to CSP.3.5.1.
18. **Fix completion (CSP.3.5.1) ✅ 2026-05-28** — apply the intended `/6` to the operative line. Single-line shader change + amended `[dev-2026-05-28-h]` + `[dev-2026-05-28-n]` for the wrong test-count claims, + this step. Trivial-P1 collapse per CLAUDE.md Defect Handling Protocol (< 5 lines, root cause obvious from `git show eaaadd9b` + existing CSP.3.5 comment block, no architectural risk). Engine: 1358 / 1358 tests pass; `PresetAcceptanceTests.test_readableForm_atSteadyEnergy` now passes for FFO. See `[dev-2026-05-28-o]`.
19. **Validation (CSP.3.5.1 M7) ✅ 2026-05-28** — session `2026-05-28T19-04-51Z` (preset-rotation tap-path session cycling through all 16 production presets; FFO appeared in multiple short windows starting `19:06:59Z`). Matt verdict: "M7 review looks good. white artifacts are gone, performance looks good." `features.csv` cpu_mean 13.39 ms (under 16.67 ms budget; down from `/10` build's 17.14 ms). PERF.3 brightness fix preservation relies on Matt's perceptual verdict — `ffmpeg signalstats` corroborator unavailable because `video.mp4` is missing a `moov` atom (separate concern, follow-up task spawned). **BUG-019 resolution confirmed against the operative `/6` build.** See `[dev-2026-05-28-p]`.

### Disposition

The bug as filed described two phenomena conflated under one symptom: (a) **chronic visible flicker** on every FFO playback session, and (b) the **sustained CPU bump** observed in two specific sessions. PERF.2-pass empirically separated them: (a) is in our `applyAudioModulation` lighting formula and is fixed by PERF.3; (b) is not in our per-pass dispatch and appears probably-environmental (other ray-march presets show the same pattern intermittently; one session even self-recovered with a 96 ms hitch). Closing the bug against (a) once M7 confirms; (b) characterized but not actively pursued unless it returns with a clear non-environmental signal.

### Related

- Increment: SAR.1 — surfaced this bug because SAR.1's math-layer fix landed cleanly while Matt's M7 verdict was "no different" visually; investigation traced the residual symptom to CPU pressure rather than to the deviation primitives SAR.1 touched.
- Phase CSP — **paused** until BUG-019 is at least diagnosed. No point tuning FFO's cold-start consumer at the shader layer while ~30 % of frames are missing their deadline.
- Capability: `CAPABILITY_REGISTRY/PERFORMANCE.md` (if/when this defect is closed, the entry there gets the validation evidence).

---

### BUG-017 — Cold-start visual beat carries a per-track phase offset (preview-clip phase used as track phase)

> **AMENDED 2026-05-26 — BSAudit.3.impl was reverted on 2026-05-25 evening.** Commits `33cd57e9` / `6758a617` / `002b5f2b` / `35305b5e` backed out the impl runtime after Choice A's "doc-only closeout" (`438edbbb`, same day, earlier). The diagnostic tooling (`--accent-window-pass-rate` verifier mode, the 4 new SelfTest checks, the diagnostic findings doc, the historical baseline doc) was retained per Matt's "yes, keep the tools" sign-off. Production is the pre-impl baseline; the resolution against the accepted structural limit still holds, but the runtime architecture described below as "production" is no longer in the code. The text below preserves the BSAudit.3.impl narrative as historical record; see CLAUDE.md §Cold-Start Phase Contract for the current production state. See `docs/RELEASE_NOTES_DEV.md` `[dev-2026-05-26-b]` for the revert narrative.

**Severity:** P1 (load-bearing product claim — "beat-synced from frame 1 of every track", Matt's Phase CS bar 2026-05-20. CS.1 empirical verification: 7 of 10 tracks fail the ±50 ms bar. Not session-blocking — the session plays and the BUG-007.9 runtime recalibration partially corrects after ~15 s — so not P0.)
**Domain tag:** `dsp.beat`
**Status:** **Resolved 2026-05-25 (closed against accepted structural limit — see addendum 2026-05-25 below; AMENDED 2026-05-26 to reflect that the BSAudit.3.impl runtime described as "production" in the resolution was itself reverted same-day).** Six fix-class iterations (CS.1 → CS.1.y.1 → CS.1.y.2 → CS.1.y.2-redo r1 → r2 → BSAudit.3.impl) exhausted the available short-window automated signals for cold-start beat-phase derivation; the BSAudit.3.diag.1 root-cause dive empirically falsified the premise that the audible beat phase can be recovered from the first ~3 s of live tap audio (CLAUDE.md Failed Approach #69). Matt's Choice A decision 2026-05-25 accepted the ±60 ms / 3 s perceptual sync sub-goal as structurally unachievable; the initial closeout retained BSAudit.3.impl as production, but the runtime was reverted the same evening (`33cd57e9` / `6758a617` / `002b5f2b` / `35305b5e`), leaving only the diagnostic tooling in place. Production is the pre-impl baseline; the structural limit holds independent of the runtime in place.
**Introduced:** Pre-CS.1. The cold-start grid-install path (`VisualizerEngine+Stems.swift:485`, `cached.beatGrid.offsetBy(0)`) and the preview-only `GridOnsetCalibrator` (`GridOnsetCalibrator.swift:13`) predate this filing — part of the BUG-007.x cold-start infrastructure series. The preview-vs-track phase gap was never closed; CS.1's verification harness surfaced it empirically 2026-05-22.
**Resolved:** 2026-05-25, against accepted structural limit. Initial closeout architecture: commits `efaf8cb4..30d032ea` (BSAudit.3.impl.1/.2/.3 — BPM prior install + broadband-peak phase acquisition + confidence-gated accents + `GridOnsetCalibrator` retirement). **The impl runtime was reverted 2026-05-25 evening** (`33cd57e9` / `6758a617` / `002b5f2b` / `35305b5e`); production reverted to the pre-impl baseline (`GridOnsetCalibrator` reinstated, no `accentConfidence` field, no BPM-prior phase acquisition, ungated beat accents). Diagnostic infrastructure retained: `515f9b89` (validate.1 — `--accent-window-pass-rate` verifier mode), `cf83037c` (validate.2 — historical baseline), `346f7487` (BSAudit.3.diag.1 — per-track diagnostic + root-cause findings). Closeout: addendum 2026-05-25 below + [`docs/diagnostics/BSAUDIT_3_VALIDATE_3_DIAG_2026-05-25.md`](../diagnostics/BSAUDIT_3_VALIDATE_3_DIAG_2026-05-25.md) + CLAUDE.md §Cold-Start Phase Contract + Failed Approach #69.

### Expected behavior

Per Matt's Phase CS bar (`docs/COLD_START_SYNC_DESIGN_2026-05-20.md` §3): from frame 1 of every track, the visual beat (`beatPhase01` wrap) lands within ±50 ms of the audible beat; ≥ 90 % of beats in the first 10 s within tolerance; ≥ 90 % of tracks passing.

### Actual behavior

CS.1's `ColdStartVerifier` harness, run on the full-session capture `2026-05-22T16-57-36Z` (10 tracks; Beat This! one-beat-per-beat audible reference; clock offset pinned via the precise raw-tap-start timestamp added to `SessionRecorder` in CS.1):

**3 of 10 tracks pass; 7 fail.** Per-track median visual-vs-audible offset over the first 10 s:

| Track | Median Δ | Within ±50 ms | Verdict |
|---|---|---|---|
| Around the World | +28 ms | 95 % | pass |
| Get Lucky | +17 ms | 90 % | pass |
| Royals | +8 ms | 93 % | pass |
| Billie Jean | +69 ms | 10 % | fail |
| Seven Nation Army | +93 ms | 35 % | fail |
| Superstition | −28 ms | 44 % | fail |
| Everlong | −66 ms | 23 % | fail |
| B.O.B. | +10 ms | 73 % | fail |
| HUMBLE. | +338 ms | 0 % | fail |
| Money | −128 ms | 0 % | fail |

The offset is a **per-track systematic phase error, not jitter** — within each track the per-beat deltas are tight (HUMBLE: every beat +320 to +364 ms, MAD ~15 ms). The errors span −128 to +338 ms, all within ±½-beat of the track tempo. HUMBLE (76 BPM, 790 ms period) is ~0.43 beat off.

### Reproduction steps

1. Rebuild + launch the app (CS.1's `SessionRecorder` precise raw-tap-start change in tree).
2. Set `PHOSPHENE_FULL_RAW_TAP=1` in the Xcode scheme; play a ~10-track Spotify-prepared playlist.
3. `swift run ColdStartVerifier --session <dir>` (from `PhospheneEngine/`).
4. Observe: < 90 % of tracks pass the ±50 ms / 90 % bar; per-track median offsets span > 400 ms.

**Minimum reproducer:** any Spotify-prepared playlist. The defect is structural — the cold-start grid phase is set from the preview clip on every track.

### Session artifacts

- Session: `~/Documents/phosphene_sessions/2026-05-22T16-57-36Z/`
- Evidence pack: `<session>/cold_start_report.md` (full per-track table, failure dives, clock offsets).

### Suspected failure class

`calibration`. The cold-start beat grid is not calibrated to the track's actual start phase.

**Root cause (CS.1.x diagnosis — code-level evidence):**

1. **`VisualizerEngine+Stems.swift:485`** installs the cold-start grid as `cached.beatGrid.offsetBy(0)`. `cached.beatGrid` is Beat This! run on the **30-second Spotify preview clip**. `.offsetBy(0)` uses the preview clip's timeline as the track's timeline verbatim. But the preview is an arbitrary 30 s excerpt — its position in the full track is unknown — so the grid's beat phase, applied from track t=0, is off by the preview clip's arbitrary phase offset, folding to ±½-beat per track.
2. **`GridOnsetCalibrator`** (the `initialDriftMs` seed) runs on the **preview audio** (`GridOnsetCalibrator.swift:13`). It measures the Beat This!-vs-onset-detector latency *within the preview* — it never sees the live track start, so it structurally cannot measure or correct the preview-vs-track phase error. This is why the frame-1 `drift_ms` seed is small (±60 ms) while the real offset is 60–338 ms — they are different quantities.
3. The **live drift tracker** corrects small continuous drift via an EMA — it does not make a gross ½-beat phase jump (HUMBLE stays +338 ms even post-"lock").
4. The **BUG-007.9 runtime recalibration** (`VisualizerEngine+Stems.swift` `recalibrateGridFromTapAudio`) re-calibrates against live tap audio — but only after ~15 s of buffered tap audio (outside the 10 s cold-start window), and its `GridOnsetCalibrator` has a ±200 ms `maxMatchWindow` (`GridOnsetCalibrator.swift:41`) that silently returns 0 (no correction) when the true offset exceeds 200 ms — so it cannot fix the worst cases even later.

The 3 passing tracks are tracks whose preview clip happened to start near a beat boundary (small phase error).

### Verification criteria (write before the fix)

- [ ] Automated: `ColdStartVerifier` on a fresh full-session capture reports ≥ 90 % of tracks passing the ±50 ms / 90 % bar.
- [ ] Manual: Matt's M7 perceptual review on a real listening-party playlist confirms the visuals are beat-synced from frame 1.
- [ ] Regression: the BUG-007.x lock state machine and steady-state tracking are preserved — the fix adds a cold-start phase acquisition and must not destabilise the steady-state tracker.

### Fix scope

Multi-increment (P1). The fix must give the cold-start the **track-start phase**, whose only source is the live tap audio from frame 1. Direction:

- A cold-start phase acquisition: in the first ~1–2 s of playback, phase-lock the grid (correct tempo, wrong phase) to the first live sub-bass onsets — a gross phase correction up front — rather than trusting the preview clip's phase and waiting for the 15 s recalibration.
- Widen or remove the ±200 ms `maxMatchWindow` cap so gross corrections are not discarded.
- Touches the cold-start grid-install path (`VisualizerEngine+Stems.swift`) and `LiveBeatDriftTracker`. Design before code — the change interacts with the BUG-007.x lock state machine.

To be scoped as a follow-up increment; not started in this diagnosis increment.

> **Superseded (2026-05-22).** The "phase-lock to the first live sub-bass onsets" direction above was implemented in CS.1.y.2, failed validation, and was reverted — the sub-bass onset detector is not a beat-phase reference. See the CS.1.y.2 addendum below for the failure analysis and the Beat This!-based replacement direction.

### Related

CS.1 (verification harness — `ColdStartVerifier`); the Phase CS kickoff + `docs/COLD_START_SYNC_DESIGN_2026-05-20.md`; the BUG-007.x cold-start infrastructure series (BUG-007.6 latency, BUG-007.8 `setGrid(_:initialDriftMs:)`, BUG-007.9 hybrid runtime recalibration); `GridOnsetCalibrator`; D-019 (stem warmup blend); CLAUDE.md "Cold-Start Phase Contract".

### Addendum (CS.1.y.2 — fix attempt failed validation, reverted, 2026-05-22)

CS.1.y.2 implemented an in-tracker **cold-start phase acquisition** (commit `dbcc018d`): collect the first live sub-bass onsets, take the circular mean of their nearest-beat residuals, and — on a confident cluster (resultant `R ≥ 0.95`) — apply a one-shot gross `drift` correction. The engine suite was green (1272 tests). CS.1.y.3 validation **failed** and the commit was **reverted** (`f71b0456`).

**Validation result.** `ColdStartVerifier` on capture `2026-05-22T19-03-59Z` (post-fix build): **0 / 10 tracks pass — worse than CS.1's 3 / 10.** The three tracks that passed pre-fix (Around the World +28 → +129 ms, Get Lucky +17 → +198 ms, Royals +8 → +316 ms) all regressed by 100–300 ms.

**Root cause — the onset-based fix direction is unsound.** The fix phase-locks the grid to the first live sub-bass onsets, on the premise (CS.1.y.1 / the §Fix scope bullet 1 above) that those onsets pin the *beat* phase. They do not. The sub-bass onset detector fires on sub-bass *events* (bass notes, 808s, synth bass), and on syncopated tracks those are **off-beat** — verified per-track: Billie Jean's syncopated bassline → onsets −226 ms off the beat; Royals → +316 ms; Get Lucky → +198 ms. The cold-start aligned the visual onto the onset phase (`visual = liveOnset`, a direct algebraic consequence of `drift = mean(cachedGridBeat − liveOnset)`), i.e. onto the bassline, not the beat. The error is dead-steady across the whole 10 s window (MAD ~10 ms — not warmup, not jitter), and both signs / 500 ms spread rule out detector processing latency. Because the off-beat clusters are *tight*, they pass the `R ≥ 0.95` confidence gate — **the gate measures cluster tightness, not whether the cluster is on the beat**, and a syncopated bassline produces a tight, confident, wrong cluster. No threshold tuning fixes this; the signal (sub-bass onsets) is structurally not a beat-phase reference. The fix also specifically *destroyed* the tracks that worked: it overrides the (sometimes-fine) preview-calibration seed with the (always-off-beat-on-syncopated-tracks) live-onset measurement.

The baseline tolerates off-beat onsets only because the steady-state EMA's ±50 ms onset-match window *hard-rejects* them — it trusts the cached grid and uses onsets as weak confirmation. That same ±50 ms window is also exactly why the baseline cannot make the gross correction BUG-017 needs; the two are inseparable in the current architecture.

**New fix direction (CS.1.y.2-redo, to be designed with Matt).** The only reliable track-start *beat*-phase source is Beat This! itself — not the sub-bass onset detector. (`ColdStartVerifier`'s own ground-truth reference is Beat This! re-run on the tap audio, and those beat times are clean.) The direction: run Beat This! on the first few seconds of live tap audio and correct the cached grid's phase from it — both sides Beat This!, no onset-vs-beat confusion. `performLiveBeatInference` (`VisualizerEngine+Stems.swift`) already runs Beat This! on live tap at 10 s. **Open question / load-bearing pre-work:** whether Beat This! produces an accurate *phase* on a short (~4–6 s) window, and whether that window fits Matt's "~3 s" budget — to be answered by an offline measurement increment before any code (the cached grid already supplies a reliable tempo; only phase is needed).

**Verification criteria #1/#2 (above) unchanged.** The verification-criteria checkboxes remain the close gate for whatever CS.1.y.2-redo lands.

### Addendum (CS.1.y re-diagnosis — short-window Beat This! found unusable, 2026-05-22)

The CS.1.y.2-redo step-1 measurement (offline; `ColdStartVerifier --rediagnose`, commit `b27226d3`) tested the open question above: can Beat This! on a short (3/4/5 s) window of live tap audio reproduce the beat *phase* of full-window Beat This! (the verifier's audible-beat reference)? It cannot.

- **Capture `2026-05-22T16-57-36Z`: 3/10 tracks viable** (≤ 30 ms, R ≥ 0.90) at every window length. **Capture `2026-05-22T19-03-59Z`: 1–2/10.**
- **Non-reproducible across captures.** The same track recorded twice gives different short-window phase: Everlong is clean (R 0.98, ±6 ms) in the first capture and **unstable** (±211 ms swing across 3/4/5 s) in the second; Around the World, Seven Nation Army flip likewise. Only Royals is viable in both. A fix built on a signal that is not reproducible per track would behave differently every session.
- **HUMBLE**: short-window phase is garbage and wildly unstable (−202 / −161 / +269 ms across 3/4/5 s).
- **Money**: Beat This! finds **no beats at all** in the first 3/4/5 s — its intro is the looped cash-register/coin SFX, so there is no beat in the cold-start window to sync to (structurally unfixable).
- **B.O.B.**: short-window Beat This! returns degenerate/empty grids (0–3 beats).

**Root cause:** the existing `DefaultBeatGridAnalyzer.analyzeBeatGrid` bundles Beat This! inference with `BeatGridResolver`'s tempo estimation, and short windows degrade tempo (Failed Approaches #50/#51). Small changes in window length flip the output (Superstition's resultant collapses 0.95 → 0.26 → 0.19 as the window *grows*). A measurement caveat: the harness uses `analyzeBeatGrid`, so it cannot isolate whether Beat This!'s raw beat-activation output (before the resolver) is more stable than the full pipeline — but beat *count* itself flips across window lengths, which points at the transformer's activations, not just the resolver.

**Where this leaves BUG-017.** Three signal sources have now been tried and exhausted: live sub-bass onsets (CS.1.y.2 — off-beat, reverted), short-window Beat This! (this re-diagnosis — erratic, non-reproducible), and the cached grid alone (CS.1 baseline — 3/10 pass). None achieves the bar (≥ 90 % within ±50 ms from frame 1, ≤ 5 s budget). The only reliable beat reference is full-window (~15–25 s) Beat This!, which by definition is not available inside the cold-start window. **The bar as specified is not achievable under the streaming-only constraint with the tools available.** That is a product-level finding, and it was put to Matt.

**Decision (2026-05-22).** Matt's call: do not chase fast (≤ 5 s) phase acquisition. Cold-start uses the cached grid as-is from frame 1 — which CS.1 showed is *approximately* right already (8/10 tracks within ±130 ms). Then, at ~15–20 s, run full-window live Beat This! on the tap audio and phase-correct the cached grid to it (a one-time snap to exact). Product claim: "approximately synced immediately, locked within ~20 s." The fix (**CS.1.y.2-redo**) supersedes the onset-based and short-window directions; it is closely related to the existing `performLiveBeatInference` live-Beat This! path (currently runs only when no grid is installed) and to BUG-007.9 runtime recalibration (currently `GridOnsetCalibrator`-based — the unreliable onset tool). To be designed design-first before any code.

### Addendum (CS.1.y.2-redo redo.1 + redo.2 — implementation landed, awaiting validation, 2026-05-22)

The CS.1.y.2-redo design surfaced to Matt before code; snap = instant snap (Matt-ratified). Implemented in two halves:

**redo.1 (Step 1 window-length measurement) ✅.** Extended `ColdStartVerifier --rediagnose` to take `--rediagnose-windows` (default `3,4,5` preserved). Ran on both captures with `10,15,20`. Result: **at 15 s, phase reproducibly ≤ 8 ms across both captures on every track including HUMBLE and Money; at 20 s, ≤ 6 ms.** Decisive vs the 3/4/5 s re-diagnosis (1-3/10). Reports written to `<capture>/cold_start_rediagnosis_10-15-20.md`. **W = 15 s ratified** by Matt. The bundled "viable" verdict (8-9/10) folded a strict R ≥ 0.90 gate that's tempo-jitter-sensitive — the *raw phase* (what the fix needs) is 10/10 within ±30 ms at 15-20 s. The redo.2 confidence gate is loose by design.

**redo.2 (implementation) ✅.** No new architecture — the fix swaps the *measurement tool* inside BUG-007.9's `runtimeRecalibrationIfDue`. Specifics:

- **Engine** — new `LiveBeatDriftTracker.applyColdStartPhaseCorrection(liveGrid:)` computes the circular-mean phase residual between the installed cached grid and a passed-in live Beat This! grid; gates with degenerate-only guards (≥ 8 live beats, live BPM within ±15 % of cached BPM) plus a loose R floor (0.5); applies via the existing drift-set path (no grid reinstall, no lock-state reset). `applyCalibration` refactored to share `setDriftLocked` with the new method.
- **Engine tests** — `LiveBeatDriftTrackerColdStartPhaseTests.swift` adds 8 contracts including the load-bearing **lock state, matchedOnsets, and drift-EMA ring are preserved across the correction** check (the BUG-007.x regression guard).
- **App** — `runtimeRecalibrationIfDue` reworked: snapshot 15 s of tap audio, run `DefaultBeatGridAnalyzer.analyzeBeatGrid`, shift to track-relative time, call the new engine method. **Dropped the `matchedOnsetCount ≥ 8` gate** that would never open on ½-beat-off tracks (the exact failure case BUG-017 is about — onsets can't match a wrong grid within ±50 ms). `stemSampleBuffer.maxSeconds` 15 → 18 (15 s window on a 48 kHz tap needs ~16.5 s of model-rate capacity; cost ~0.6 MB). `GridOnsetCalibrator` retained only for its prep-time `gridOnsetOffsetMs` seed.
- **Verifier** — new `--window-start-s` option for measuring the post-snap window (redo.3 needs `--window-start-s 20`).

Verification:
- Engine suite: **1273 / 1273 pass** (1265 baseline + 8 new cold-start tests).
- App build clean; project-wide `swiftlint --strict`: 0 violations across 380 files.
- `ColdStartVerifier --self-test`: PASS (7/7).

**Pending — redo.3 (validation).** Matt: produce a fresh full-session capture with `PHOSPHENE_FULL_RAW_TAP=1` on the post-fix build. Then `ColdStartVerifier --session <capture> --window-start-s 20` should show ≥ 90 % within ±50 ms in the post-snap window. Then M7 perceptual review with attention on HUMBLE and Money (the verifier-circularity tracks). On M7 pass: BUG-017 flips to Resolved with the commit hash; ENGINEERING_PLAN CS.1.y to ✅; `RELEASE_NOTES_DEV.md [dev-2026-05-22-d]` records closeout.

### Addendum (CS.1.y.2-redo redo.3 round 1 failed and round-1 fix did not converge — implementation reverted 2026-05-24)

Three validation captures across 2026-05-22 → 2026-05-24 established that the CS.1.y.2-redo fix does **not** converge perceptually. **Reverted 2026-05-24.** What stays in tree: the `ColdStartVerifier --rediagnose-windows` + `--window-start-s` diagnostic tooling (commit `976a78b3`). What was reverted: the engine `applyColdStartPhaseCorrection` method + 8 regression tests; the app `runtimeRecalibrationIfDue` rework + `stemSampleBuffer` 15 → 18 bump; the live-grid extrapolation follow-up fix.

**Evidence chain:**

| Capture | Outcome |
|---|---|
| `2026-05-23T02-17-24Z` (round 1) | Engine bug — fix passed default `horizon: 300` to `BeatGrid.offsetBy` for the live grid, inflating residuals over the 300 s extrapolation. 3/10 tracks applied with `matched=600+` (should be ~30) and inflated drifts. Fixed in `1e77fdf6` (`horizon: 0`). |
| `2026-05-23T02-39-54Z` (round 2 post-fix) | Engine signatures clean (`matched ≈ 21-39`, R high). Verifier post-snap window: 4/7 PASS, 3/7 FAIL + 3 DEGENERATE. **Two regressions on previously-passing tracks**: Get Lucky (95 % PASS pre-snap → 0 % FAIL post-snap; R=0.99 confident wrong measurement); Seven Nation Army (failing → worse). The CS.1.y.2 R-gate failure (Failed Approach #68) reappearing in Beat-This!-vs-Beat-This! form: tight cluster, wrong phase. |
| `2026-05-24T15-07-31Z` (round 3) | Matt's M7: "drift very much real across tracks"; "rarely snaps to the beat and does not follow downbeat." Cross-capture non-reproducibility confirmed on multiple tracks (Billie Jean -6/+79; SNA +88/-160; Get Lucky -109/-7; Everlong +44/-116; Superstition -181/+63 across captures). Pre-snap baseline also degraded: 1/10 PASS vs CS.1's 3/10. EMA drift bouncing 200-300 ms within steady-state tracks; HUMBLE only 43 % locked post-snap. |

**Root finding.** Beat This! on a 15 s tap is reproducible *within* a capture against a 25 s reference *on the same slice* (what redo.1 measured) — but is NOT reproducible *across* captures or *across* slice positions for several tracks. The "non-reproducibility across captures" failure mode that killed the 3-5 s windows in the original CS.1.y re-diagnosis is alive at 15 s on a subset of tracks. redo.1 made a measurement that did not cover the production case (the production case is "Beat This!@first-15-s-of-tap" compared to whatever the user perceives later, not "Beat This!@15 s of slice A vs Beat This!@25 s of the same slice").

**Also surfaced:** the pre-fix "approx now" baseline itself degraded across captures using identical cached grids — either `gridOnsetOffsetMs` seeding is non-deterministic across preps (the prep-time `GridOnsetCalibrator` is still onset-based — Failed Approach #68's root cause that we left in place at prep time), or the verifier's clock-offset estimate is noise-coupled, or there's an unrelated regression. The "approximately within ±130 ms" claim CS.1 made (and that the 2026-05-22 product-direction decision relied on) does not hold across captures.

**Pattern.** CS.1 → CS.1.y.1 → CS.1.y.2 → CS.1.y re-diag → CS.1.y.2-redo redo.1 → redo.2 → redo.3 round 1 fix → round 2 fix = **five fix increments on the same defect without perceptual convergence.** This is the Drift-Motes pattern (Failed Approach #58) at infrastructure scope. Per CLAUDE.md "stop and report instead of forging ahead" and "iteration converges only when each step integrates feedback into the model" — the model is wrong upstream, more fixes won't help.

**Status.** **BUG-017 stays Open** but its scope is now broader than the original cold-start grid-phase offset: the broader symptom is "beat-sync infrastructure is not perceptually aligned across the catalog" (Matt 2026-05-24). To be addressed by a beat-sync audit increment (analogous to Phase CA's DSP audit but scoped to the beat-sync wiring specifically — `GridOnsetCalibrator` prep-time seeding, `LiveBeatDriftTracker` EMA behaviour under wrong-phase grids, verifier clock-offset sensitivity, and whether the broader perceptual drift comes from one root cause or several). **No fix code until the audit produces a per-component verdict with empirical grounding.**

**Audit kickoff prompt:** `docs/prompts/BEAT_SYNC_AUDIT_KICKOFF.md` (next session).

### Addendum (Beat-Sync Audit deliverable, BSAudit, 2026-05-24)

The audit published as [`docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`](../CAPABILITY_REGISTRY/BEAT_SYNC.md). Read-only; no fix code. Per-component verdicts with empirical grounding from the four reference captures (`2026-05-22T16-57-36Z`, `2026-05-22T19-03-59Z`, `2026-05-23T02-39-54Z`, `2026-05-24T15-07-31Z`).

**Refined symptom statement.** The "beat-sync infrastructure is not perceptually aligned across the catalog" symptom (Matt 2026-05-24) decomposes into **two distinct defect classes acting simultaneously**:

1. **Systematic per-track phase offset on syncopated tracks** (BUG-017's original framing). The cold-start install path `cached.beatGrid.offsetBy(0)` treats preview-clip timeline as track timeline; the `gridOnsetOffsetMs` seed (sub-bass-onset-based, prep-time — Failed Approach #68 still live in production at prep time) cannot measure preview-vs-track phase. Result: 7/10 tracks in cap1 carry per-track phase offsets ≤ ½-beat at the track's tempo (HUMBLE +338 ms; Money −128 ms). Static defect — same value every capture.
2. **Cross-capture variability of the verification reference** (new finding). Beat This! on a 25 s slice of live tap audio produces *different beat positions* on 5-6 of 10 tracks across captures of the same Spotify previews — the dominant finding behind the cap1→cap4 baseline degradation (3/10 PASS → 1/10 PASS) and the cap3→cap4 snap-drift divergence (≥85 ms on 6/10 tracks with the same fix). The CS.1.y.2-redo cycle's verifier-passing→M7-failing pattern is explained: verifier and M7 disagreed because the verifier's reference moved across captures. The redo.1 "10/10 viable at 15 s" measurement validated within-slice reproducibility, not the production case (cross-capture). Beat This!-on-tap is fine as a within-capture reference but is not a stable physical reference across captures.

**Ranked root-cause hypotheses (full evidence in [`BEAT_SYNC.md`](../CAPABILITY_REGISTRY/BEAT_SYNC.md) §Ranked):**

| Rank | Hypothesis | Drives cross-capture variability | Drives systematic offset on syncopated tracks |
|---|---|---|---|
| 1 | Beat This!-on-tap not cross-capture reproducible (Component 5b) | **Dominant** | Small |
| 2 | Sub-bass onsets used as beat-phase reference in 3 places (Components 6, 1b, 3, 5a) | Small (<50 ms) | **Dominant** (per-track 100s of ms) |
| 3 | Cold-start install: preview-time as track-time (Components 1a/2) | None (static) | **Dominant** (BUG-017's original static defect) |
| 4 | Verifier clock-offset noise (Component 5a) | Small (±50-150 ms, bounded by `searchRadiusS`) | Small |
| 5 | `gridOnsetOffsetMs` non-determinism (Component 1b) | Small (≤30 ms on 3/10 tracks) | None |

**Per-component fix scope sketches** (none authorized for implementation; Matt sign-off required):

- **Component 1b** — Delete `GridOnsetCalibrator` from prep, or reframe its output as detection-latency only (not beat-phase). Removes one of three production uses of sub-bass onsets as a phase reference.
- **Component 2** — Document the structural limitation honestly: "approximately beat-synced from frame 1; exact phase recovered within ~20 s" (already the 2026-05-22 product-direction decision). Optionally add a `coldStart` lock-state distinction so presets don't accent-pulse on a known-suspect grid.
- **Component 3** — *Do not change.* The EMA does its designed job correctly; CS.1.y.2 and CS.1.y.2-redo both failed because they tried to extend it past its design envelope.
- **Component 5a** — One-line instrumentation: log `coarseS` + `offsetS - coarseS` per track in `ColdStartVerifier`; re-run on existing captures; close Hypothesis 4 with measurement.
- **Component 5b** — *Research-only.* Find or build a cross-capture-stable reference (full-tap Beat This! window, or human-tap ground truth). **Load-bearing pre-work for any future BUG-017 closeout** — no fix can claim convergence while the verification infrastructure cannot judge it reliably.
- **Component 6** — *Do not change the detector.* Retire its use as a phase reference at the call sites (Components 1b, 3, 5a); CLAUDE.md Failed Approach #68 generalizes from "the runtime fix" to "any use as a phase primitive."

**Open empirical questions surfaced as gaps** (not blocking this audit; would require small instrumentation increments):
- Q1 follow-up: re-run `GridOnsetCalibrator` cross-capture on archived preview audio to confirm whether the 11-30 ms seed variation on 3/10 tracks comes from preview-byte differences or from a hidden non-determinism in the calibrator.
- Q5: instrument verifier clock-offset refinement to characterise per-capture noise (≤1 hour instrumentation).
- Q6 follow-up: per-track sub-bass-onset-distance distribution against full-window Beat This! ground truth (1-2 hour offline analysis), if/when a stable ground truth exists.

**BUG-017 stays Open** with the refined symptom statement above. The next step is **Matt sign-off on direction** for the BSAudit-FU-* follow-up backlog ([`BEAT_SYNC.md`](../CAPABILITY_REGISTRY/BEAT_SYNC.md) §Follow-up Backlog) — not another fix increment. **No new fix code until a Component 5b cross-capture-stable reference exists or a Component 2-style honest-limitation product framing is documented.**

### Addendum (BSAudit.2 — Path A falsified, 2026-05-24)

The BSAudit follow-up BSAudit-FU-5 split into Path A (Beat This!-on-tap reproducibility) and Path B (human-tap ground truth). BSAudit.2 implemented Path A as two `ColdStartVerifier` modes and ran them on the four reference captures. **Path A is empirically falsified — no 25 s slice configuration of Beat This!-on-tap is reproducible.** Full evidence in [`BEAT_SYNC.md` Addendum — BSAudit.2 (Path A) findings](../CAPABILITY_REGISTRY/BEAT_SYNC.md#addendum--bsaudit2-path-a-findings-2026-05-24).

**Findings.**
- **Within-capture position sensitivity:** for the same audio in the same capture, Beat This! on a 25 s slice produces different beat positions when the slice start moves by 10 s. 7 of 10 tracks fail by 100-410 ms phase spread across positions. Two qualitative behaviours: monotonic phase drift (Beat This! mis-estimating period — Get Lucky, Royals) and erratic large jumps (Beat This! locking to different metric interpretations — Billie Jean, Around the World).
- **Cross-capture instability:** 10 of 10 tracks differ by 100-322 ms in same-position 25 s Beat This! across the 4 captures. Even tracks that are within-capture-stable (Seven Nation Army, Everlong, HUMBLE) are cross-capture-unstable — HUMBLE within-capture-stable to ≤ 25 ms but cap4 reads −322 ms different from cap1 at the same playback-time.

**Implication.** A longer/stitched window cannot rescue this — Beat This! produces conflicting metric interpretations the model itself cannot reconcile. Path A is closed.

**Path B (human-tap reference) is now load-bearing** for any future BUG-017 fix-claim that depends on automated verification. The product-strategy fork is now:
1. **Build Path B** (small CLI + ~4 min of Matt's taps for the 10-track catalog + ~1 session of tooling). Unblocks future fix-claims with a stable ground truth.
2. **Accept the structural limit and document** (2026-05-22 "approximately synced immediately, locked within ~20 s" position becomes the canonical answer; recast `ColdStartVerifier` as within-capture-only).

The audit does not pick between these. Matt's call.

### Addendum (BSAudit.3 design + impl, 2026-05-24)

Matt picked **a third path** between BSAudit's options: a design-first re-architecture. [`docs/BPM_ANCHORED_PHASE_ACQUISITION_DESIGN_2026-05-24.md`](../BPM_ANCHORED_PHASE_ACQUISITION_DESIGN_2026-05-24.md) drops the "trust cached grid phase" + "snap to live Beat This! @ 15 s" approaches entirely; replaces them with **BPM-prior + broadband-peak phase acquisition + confidence-gated accents**. The premise: never claim phase at frame 1; anchor on the first broadband flux peak; accumulate confidence via an EMA against the BPM prior's predictions; only fire accents at amplitude proportional to confidence. Three sub-commits shipped 2026-05-24 (`efaf8cb4`, `13d0f456`, `30d032ea` — see `RELEASE_NOTES_DEV.md` `[dev-2026-05-24-d]`). `GridOnsetCalibrator` retired entirely (Failed Approach #68 root cause removed from prep). Validation deferred to BSAudit.3.validate.

### Addendum (BSAudit.3.validate.1 + .2 — diagnostic infrastructure + historical baseline, 2026-05-25)

`[BSAudit.3.validate.1]` (`515f9b89`) added a new verifier mode `--accent-window-pass-rate` per the architecture's design §8 + §12: for each audible beat (Beat This! on raw_tap), did a `beatComposite` rising-edge fire within ±60 ms? Per-track verdict PASS-firing | PASS-degraded | FAIL; aggregate gate ≥ 90 % of catalog. CSV schema gained `accent_confidence` column. ColdStartVerifier --self-test went from 7/7 to 11/11.

`[BSAudit.3.validate.2]` (`cf83037c`) ran the new mode against the 3 available pre-impl reference captures (cap1 = `2026-05-22T16-57-36Z` was missing from disk; cap2/3/4 still present). All 30 pre-impl track samples landed PASS-firing at ≥ 95 % — the OLD architecture's raw un-gated `beatComposite` fired on every per-band onset, trivially covering each audible beat by accident of pop/rock kick-on-beat behaviour. See [`docs/diagnostics/BSAUDIT_3_HISTORICAL_BASELINE_2026-05-25.md`](../diagnostics/BSAUDIT_3_HISTORICAL_BASELINE_2026-05-25.md).

### Addendum (BSAudit.3.diag.1 — fresh-capture diagnostic + Failed Approach #69, 2026-05-25)

Matt produced a fresh post-impl capture at `~/Documents/phosphene_sessions/2026-05-25T15-20-49Z/` (same 10-track playlist, `PHOSPHENE_FULL_RAW_TAP=1`). The verifier ran against it: aggregate **FAIL — 40 % of 10 tracks pass** (2 PASS-firing, 2 PASS-degraded, 6 FAIL). `[BSAudit.3.diag.1]` (`346f7487`) extended the verifier with a per-track diagnostic block (first broadband peak time + residual, first accent fire + residual, confidence/lock-state timings, per-fire residual distribution) and produced the root-cause findings at [`docs/diagnostics/BSAUDIT_3_VALIDATE_3_DIAG_2026-05-25.md`](../diagnostics/BSAUDIT_3_VALIDATE_3_DIAG_2026-05-25.md).

**Root cause (three structural findings, all empirically grounded):**

1. **Broadband-flux-as-phase-anchor is unsound.** 5 of 10 tracks anchored > 100 ms off the nearest audible beat (Billie Jean −212, ATW −231, SNA −291, Royals −516, B.O.B. −309). Consistently negative residuals indicate broadband flux fires on *pre-beat* content (pad swells, vocal entries, hi-hat lead-ins) — same shape as Failed Approach #68 at the broadband layer.
2. **Confidence accumulator does NOT back-pressure off-anchor lock.** HUMBLE (anchor −68 ms) reached confidence 0.9; Billie Jean (anchor −212 ms) reached 1.0. Design §9.1 mitigation falsified: periodic broadband content at quarter-note rates reinforces *any* phase that matches the period, not just on-beat. The accumulator can't distinguish "actually-on-beat reinforcement" from "any-periodic-content-at-the-period reinforcement."
3. **Verifier metric is gameable by accent over-firing.** Billie Jean: 25+ accent fires in 10 s vs 19 audible beats; per-fire median |residual| = 109 ms; metric still reads 95 % PASS-firing. "Any accent within ±60 ms of each beat" is trivially satisfied by accent over-firing.

This is **Failed Approach #58 iteration #6 territory at infrastructure scope** — six iterations on the same defect (CS.1 → CS.1.y.2 → CS.1.y re-diag → CS.1.y.2-redo r1+r2 → BSAudit.3.impl), each with a different mechanism, none converging on > 70 % of catalog. The common thread the iterations did not change is the upstream premise: *"there is some automated signal in the first ~3 s of tap audio that reliably tells us the audible beat phase of a novel track."* Six attempts empirically falsified that premise. **CLAUDE.md Failed Approach #69** captures the pattern; **CLAUDE.md §Cold-Start Phase Contract** captures the achievable contract.

### Resolution (Matt's Choice A decision, 2026-05-25)

**BUG-017 resolves against an accepted structural limit, not a fix.** Matt's framing of the decision:

> *"give up the marketing claim 'synced from frame 1,' accept 'musical from frame 1.' That's a smaller concession than it sounds because nobody's marketing copy depended on the stronger claim."*

The production cold-start architecture was retained as BSAudit.3.impl in this closeout. **AMENDED 2026-05-26:** the BSAudit.3.impl runtime was reverted on 2026-05-25 evening (`33cd57e9` / `6758a617` / `002b5f2b` / `35305b5e`); production is the pre-impl baseline (cached BeatGrid install via `MIRPipeline.setBeatGrid`, `LiveBeatDriftTracker` pre-impl form, `GridOnsetCalibrator` reinstated, no `accentConfidence` field, ungated beat accents). What's retired: the original Phase CS bar ("±50 ms / 90 % from frame 1"). The structural limit holds independent of the runtime in place. The architecture's actual contract is what CLAUDE.md §Cold-Start Phase Contract documents (rewritten 2026-05-26 to describe the post-revert state).

Future work in this space requires a fundamentally different premise (human-tap reference per BSAudit-FU-5 Path B, full-track local-file analysis, manual per-track calibration UX) — not another short-window signal. See Failed Approach #69's discriminator.

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

### BUG-015 — `applyLiveUpdate(...)` has zero production call sites; Orchestrator live-adaptation pipeline is dead at runtime

**Severity:** P1 (load-bearing product claim — "the AI Orchestrator has planned the entire visual session and adapts as the music unfolds" per CLAUDE.md top — the adaptation half does not run).
**Domain tag:** `pipeline-wiring`
**Status:** **Resolved 2026-05-21.** The App-layer wire is in place (`runOrchestratorLiveUpdate(mir:)` calls `applyLiveUpdate(...)` from the analysis-queue tick at ~3 Hz; sources `liveBoundary` from `mirPipeline.latestStructuralPrediction`); the regression test (`OrchestratorWiringRegressionTests.swift`) passes; the Orchestrator engine suite (including the three QR.2 / D-080 cooldown tests) stays green. Verification criterion #2 confirmed by Matt's `2026-05-21T14-19-32Z` session capture: `session.log` shows two `Orchestrator: wire active` lines (one at 8.2 s pre-first-track-change in warmup state, one at 0.0 s elapsed on the new track after `mir.reset()`), proving the wire fires AND the per-track diagnostic latch resets correctly on track change.
**Introduced:** Surfaced 2026-05-20 by [CA.4 Orchestrator audit](../CAPABILITY_REGISTRY/ORCHESTRATOR.md). The root condition pre-dates this filing; `git log -p PhospheneApp/VisualizerEngine+Audio.swift -- *applyLiveUpdate*` will narrow when (or whether) the call site was ever added. Phase 4.5 (Live Adaptation) and 4.6 (Ad-Hoc Reactive Mode) both shipped ✅ at the Orchestrator-module surface (LiveAdapter / ReactiveOrchestrator implementations + unit tests + the `applyLiveUpdate(...)` entry point method); the App-layer audio-callback invocation of `applyLiveUpdate(...)` was never wired until 2026-05-21.
**Resolved:** 2026-05-21 in three commits:
- `b3f1efd9` — wire: `runOrchestratorLiveUpdate(mir:)` + regression test `OrchestratorWiringRegressionTests.swift` + lock-guarded `liveTrackPlanIndex` / `lastClassifiedMood` fields + pbxproj registration.
- `5efc6a90` — once-per-track `Orchestrator: wire active` diagnostic dual-writing to `session.log` (via `SessionRecorder.log`) and the unified log (via `os.Logger`). Closes the verification-criterion-#2 doc-vs-runtime gap (existing Orchestrator log lines never reached `session.log`).
- `<commit 3 hash>` — Status flip + RELEASE_NOTES_DEV.md final entry.

Validation evidence (Matt's `~/Documents/phosphene_sessions/2026-05-21T14-19-32Z/session.log` lines 6 and 11):

```
[2026-05-21T14:19:40Z] Orchestrator: wire active (mode=reactive, planIdx=—, elapsedTrackTime=8.2s)
[2026-05-21T14:19:41Z] Orchestrator: wire active (mode=reactive, planIdx=—, elapsedTrackTime=0.0s)
```

7 519 frames / 23 stem dumps in that session confirm the full audio path is alive; the once-per-track latch is verified (exactly one diagnostic line per track, no per-frame noise).

**Expected behavior.** During session-mode playback: planned transitions reschedule against live structural boundaries when the deviation exceeds 5 s; mood overrides fire mid-track when measured valence/arousal diverges from pre-analyzed mood by > 0.4 (with the 30 s per-track cooldown enforced by `DefaultLiveAdapter.cooldownAdaptation(...)` per D-080 rule 3); the L diagnostic-hold / capture-mode grace window / `wait_for_completion_event` suppression machinery actually has something to suppress. During ad-hoc playback after the 15 s listening window: `DefaultReactiveOrchestrator.evaluate(...)` returns preset suggestions; the 60 s reactive cooldown in `VisualizerEngine+Orchestrator` rate-limits them; switches land at structural boundaries or score-gap thresholds per D-036.

**Actual behavior.** Neither path runs. `liveAdapter.adapt(...)` and `reactiveOrchestrator.evaluate(...)` are exercised only by unit tests. The session-log shows no `Orchestrator:`, `LiveAdapter:`, or `Reactive` log lines from the live-adaptation event family across any real-music capture.

**Reproduction steps.**

1. Run any session (Spotify-prepared or ad-hoc) for ≥ 30 seconds.
2. Open `~/Documents/phosphene_sessions/<ts>/session.log`.
3. Observe: no `LiveAdapter: boundary rescheduled`, `LiveAdapter: preset override`, or `Reactive [...]: '...' replaces` lines.
4. Confirm absence via grep:
   ```
   $ grep -rn "applyLiveUpdate" PhospheneApp PhospheneEngine --include="*.swift"
   ```
   Returns 1 declaration (`VisualizerEngine+Orchestrator.swift:166`), 4 doc-comment / commentary references in unrelated files, 1 test reference. **Zero actual invocations.**

**Minimum reproducer.** Any session. The bug is structural — no audio-driven path invokes `applyLiveUpdate(...)`.

**Session artifacts.** Any `session.log` from a recent capture (the log family that's missing is the load-bearing artifact — its absence is the symptom).

**Suspected failure class.** `pipeline-wiring` per `docs/QUALITY/DEFECT_TAXONOMY.md`. The Orchestrator-module surface is complete and correct; the App-layer invocation site was never added (or was removed during a refactor — likely candidates: `VisualizerEngine+Audio.swift` analysis-queue tick, or a Combine sink on the MIR feature publisher).

**Verification criteria (write before the fix).**

- [ ] Automated: a new integration test exercises a 30 s reactive session against synthetic FeatureVectors (or a recorded capture) and asserts at least one `reactiveOrchestrator.evaluate(...)` invocation happens after the 15 s listening window. Test fixture: any real-music preview clip; or the SoakTestHarness localFile mode driving 30 s of audio.
- [ ] Manual: a real-music session capture's `session.log` shows at least one entry from the `Orchestrator:` `LiveAdapter:` or `Reactive` log-line family during a > 1 minute playback. (Today: zero such lines.)
- [ ] Regression: the 30 s per-track mood-override cooldown enforced by `DefaultLiveAdapter.cooldownAdaptation(...)` (verified at `LiveAdapter.swift:362-381` per CA.4) is preserved post-fix — the fix MUST NOT bypass the cooldown machinery. A test that fires N consecutive mood-divergence events at < 30 s intervals on the same track asserts ≤ 1 override is applied.

**Fix scope.** Multi-increment per the CLAUDE.md Defect Handling Protocol (this is P1, not P0; the trivial-collapse exemption requires Matt's explicit approval and the fix is unlikely to be < 5 lines).

1. **Instrumentation (this BUG entry establishes the read; no separate instrumentation increment needed — the grep evidence is reproducible from any source checkout).**
2. **Diagnosis** — locate the intended call site. Two candidate sites surfaced by the audit:
   - (a) `VisualizerEngine+Audio.swift` analysis-queue tick at a 1–10 Hz cadence (per-track cooldown is already enforced inside `DefaultLiveAdapter`; the cadence just needs to be low enough that the cooldown's 30 s window dominates).
   - (b) A Combine sink on `MIRPipeline`'s feature publisher (lower-frequency, naturally bound to feature updates).
3. **Fix** — implement the chosen wire. The `boundary` argument should source from either `pipeline.latestStructuralPrediction` (real per-frame; would also resolve CA.1-FU-1 option (b)) or `StructuralPrediction.none` sentinel (simpler; pairs with CA.1-FU-1 option (a) gating the per-frame chain to prep-time only).
4. **Validation** — run the verification criteria above; produce a session-log capture showing the live-adaptation event family is firing.
5. **Release notes** — update `RELEASE_NOTES_DEV.md`; mark Resolved in this entry with the commit hash.

**Related.** CA.4 audit deliverable (this filing); CA.1-FU-1 (re-scoped — see [`docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md` §Resolution-of-CA.1-runtime-production-orphan-re-evaluation](../CAPABILITY_REGISTRY/ORCHESTRATOR.md)); CA.4-FU-1 (demote dead `DefaultLiveAdapter.transitionPolicy` field; natural to bundle with the BUG-015 fix); D-035 (live adaptation design — implementation faithful, wiring absent); D-036 (reactive orchestrator design — same); D-080 (QR.2 mood-override cooldown + reactive `liveStemFeatures` wiring — both unreachable until BUG-015 lands); BUG-001 (`Money 7/4 stays REACTIVE on live path` — different concept; BUG-001's "REACTIVE" refers to the SpectralCartograph mode label / DSP-side lock state, NOT the Orchestrator's reactive mode).

**Why P1 not P0.** P0 is "session-blocking" per the taxonomy; the product still plays sessions and the static plan does work (`DefaultSessionPlanner.plan(...)` and the canonical-identity wiring at `VisualizerEngine+Capture.swift:131` per BUG-006.2 are both reachable). What's broken is the adaptation half — the product runs as a static playlist with no live response to detected boundaries or mood shifts. That's a significant degradation of the product's stated value but not a session-blocker.

**Notes on existing tests.** The audit's grep confirmed that `LiveAdapterTests`, `ReactiveOrchestratorTests`, `DiagnosticHoldTests`, and the other 13 Orchestrator test files exercise `liveAdapter.adapt(...)` / `reactiveOrchestrator.evaluate(...)` directly with fabricated inputs. The tests pass. They do not catch BUG-015 because they bypass the App-layer entry point. The verification criterion #1 above closes that test/prod gap.

---

### BUG-011 — Arachne over Tier 2 frame budget at the median

**Severity:** P2 (visible degradation under specific conditions: Arachne active on Tier 2 hardware. Median frame already at the FrameBudgetManager downshift threshold; 53% of frames over budget. Not a session-blocker — drop rate at the 32 ms threshold is 1.46%, so most frames complete inside one refresh — but the visual will feel laggy when Arachne is selected, and the governor will downshift quality more aggressively than intended.)
**Domain tag:** perf
**Status:** **Resolved 2026-05-12 (closure commit pending) — closed against relaxed drops-only criteria after the 37,821-frame production re-capture confirmed p95 = 15.303 ms (1.3 ms over the 14 ms gate, definitively not noise) but drops at 0.02 % (400× under the 8 % target).** The L1+L2+L3 worst-case-spike tuning (2026-05-10) plus the L5 cheap-cleanup tranche (2026-05-12) reduced p95 from 26.607 → 15.303 ms (−11 ms) and drops from 1.46 % → 0.02 % (73× reduction). The remaining 1.3 ms p95 gap is structural always-on cost on M2 Pro; closing it would require L5.1 WORLD half-rate refresh (1-2 sessions of engineering for ~1.5-2 ms savings that the drops data says aren't user-perceptible). Matt's 2026-05-12 closure decision: accept p95 = 15.3 ms on M2 Pro as a known limitation of borderline Tier 2 hardware, close on the drops result. See "2026-05-12 closure rationale" section below.
**Introduced:** Surfaced 2026-05-08 by DM.3a per-frame perf capture in session `2026-05-08T22-01-07Z`. Likely accumulated across the V.7.7B → V.7.7C → V.7.7D → V.7.7C.5 sequence of staged-composition + 3D-spider + atmospheric-reframe additions. No single increment "introduced" it; the cost grew incrementally and was never measured against the full-pipeline budget until now.
**Resolved:** 2026-05-12 against relaxed drops-only criteria. Closure commit follows this doc edit.

---

### Expected behavior

Arachne running on Tier 2 hardware (M3+, or M2 Pro at the lower end) should hold p95 frame_gpu_ms ≤ 14 ms — the FrameBudgetManager Tier 2 downshift threshold. p50 should sit well under that (target ≤ 8 ms, the 50% headroom over 16.6 ms refresh), with drops (frames > 32 ms) under 8% over a 60 s representative window.

### Actual behavior

Measured on M2 Pro under real Spotify-prepared playback (Love Rehab / So What / Limit To Your Love), Arachne window of 4,579 frames (~77 s):

- p50 = **14.120 ms** (already at the downshift threshold at the median)
- p95 = **26.607 ms**
- p99 = **32.743 ms** (right at the drop threshold)
- max = 36.072 ms
- 52.98% of frames over 14 ms
- 1.46% drops (> 32 ms)

Drift Motes in the same session sat at p50 = 1.225 / p95 = 1.321 / drops = 0.39% — proving the measurement infrastructure and the rest of the pipeline are healthy. The cost is concentrated in Arachne specifically.

### Reproduction steps

1. Build the app: `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`
2. Start an ad-hoc session with a real playlist (Spotify-prepared works; reference fixtures: Love Rehab and So What).
3. Pin Arachne via `⌘[`/`⌘]` and hold `L` (diagnostic-preset-locked).
4. Run for ≥ 60 s.
5. End the session.
6. Parse `~/Documents/phosphene_sessions/<timestamp>/features.csv` — `frame_gpu_ms` column gives per-frame GPU timing; compute p50 / p95 / p99 and drop count (`frame_gpu_ms > 32`).

**Minimum reproducer:** any track with non-trivial bass + mid energy on Tier 2 hardware. The cost is composition-driven (canvas-filling silk + 3D SDF spider + Snell's-law refraction + 12 Hz vibration UV jitter), not audio-content-driven, so any moderately energetic track should reproduce.

---

### Session artifacts

**Session directory:** `~/Documents/phosphene_sessions/2026-05-08T22-01-07Z/`

**Hardware:** Apple M2 Pro (Mac mini), macOS 26.4.1.

**features.csv** has the new DM.3a `frame_cpu_ms` / `frame_gpu_ms` columns populated for 12,804 of 12,805 frames (1 cold-start row). Per-preset filtering by `time` window vs `session.log` preset transitions:

| window (engine-time s) | preset | frames | p50 | p95 | p99 | max | >14ms | >32ms |
|---|---|---|---|---|---|---|---|---|
| 80…205 + 243…246 + 284…end | Drift Motes | 8,132 | 1.225 | 1.321 | 23.894 | 37.967 | 1.45% | 0.39% |
| 79…80 + 205…243 + 246…284 | Arachne | 4,579 | 14.120 | 26.607 | 32.743 | 36.072 | 52.98% | 1.46% |

```log
[2026-05-08T22:02:24Z] preset → Waveform
[2026-05-08T22:02:26Z] preset → Arachne
[2026-05-08T22:02:27Z] preset → Drift Motes
[2026-05-08T22:04:32Z] preset → Arachne
[2026-05-08T22:05:10Z] preset → Drift Motes
[2026-05-08T22:05:13Z] preset → Arachne
[2026-05-08T22:05:51Z] preset → Drift Motes
```

---

### Suspected failure class

`render-state` (cumulative cost across staged-composition layers; not a single bug, but the architectural envelope of the V.7.7C.5 atmospheric reframe + V.7.7D 3D spider + V.7.7C Snell's-law drops is heavier than the 1.6 ms Tier 2 budget allows on lower-tier silicon).

**Evidence for this class:** Composition-driven cost (independent of audio content); reproduces consistently in a 4,579-frame window with p50 already at the downshift threshold; not localised to any single shader function (the COMPOSITE fragment runs ray-marched 3D SDF + drop refraction + per-pixel vibration UV jitter, all unconditionally).

---

### Diagnosis notes

The most expensive blocks in `arachne_composite_fragment`, in rough cost order:

1. **3D SDF ray-march of the spider** (V.7.7D) — 32-step adaptive sphere trace + tetrahedron-trick normal estimation, gated to a 0.15 UV patch around the spider's UV anchor. Patch gate keeps cost off-frame, but the patch is always present (spider is always rendered). Even outside listening pose, the body + 8 IK legs evaluate per-pixel inside the patch.
2. **Snell's-law drop refraction** (V.7.7C) — `worldTex.sample(refractedUV)` per drop pixel; sample count scales with drop coverage. After V.7.7C.5's canvas-filling foreground, drop coverage is much larger than V.7.7C measured at.
3. **Polygon-aware spoke clipping + chord-spiral evaluation** (V.7.7C.3) — `arachneEvalWeb` ray-clips spoke tips against the polygon perimeter and evaluates the segment SDF for each chord. Cost scales with chord count (`progress × N_RINGS × nSpk`).
4. **WORLD sampling + ambient + rim** (V.7.7B/C.5) — single `worldTex.sample` plus the V.7.7C.5 §4.2 fog/shaft contribution. Comparatively cheap.
5. **12 Hz vibration UV jitter** (V.7.7D §8.2) — coherent 8×8 phase quantization via `hash_f01_2`; cheap per-pixel.

Likely candidates for the first tuning lever:
- **Reduce ray-march step count** on the spider (32 → 24, or adaptive based on patch coverage).
- **Skip drop refraction outside a smaller drop coverage gate** — refraction sampling for fully-occluded drops is wasted work.
- **Defer spider ray-march when listening-pose blend is < 0.05** AND spider state is `.idle` — the spider visually contributes nothing in those frames.
- **DeviceTier-aware fallback path** — accept that V.7.7C.5's full feature set is a Tier-2-and-up target; downshift the spider to 2D silhouette on Tier 1 (this is what V.7.5 originally shipped pre-V.7.7D).

---

### 2026-05-10 tuning pass (L1 + L2 + L3 landed)

Three shader-side levers pulled in three separate commits, each with golden-hash + visual + test verification at each step. SOAK kernel-cost benchmark added in the fourth commit as the in-tree regression gate.

| commit | lever | change | rationale |
|---|---|---|---|
| `082164c7` | **L1** spider ray-march steps | `maxSteps = 32 → 24` (Arachne.metal:~1640) | Worst-case loop reduction for miss-rays inside the 0.15 UV spider patch (~226×226 px @ 1080p ≈ 51k pixels). On-hit rays unaffected (sphere trace early-exits at hitEps). |
| `1643ee24` | **L2** drop refraction coverage gate | `wr.dropCov > 0.01 → > 0.5` (both anchor + dead-pool sites) | Skips the per-pixel `worldTex.sample(refractedUV)` + smoothstep+pow chain on the anti-aliased rim band of every drop. Drops render with a clean visible core; rim pixels fall through to the silk-strand colour underneath. |
| `96b2c288` | **L3** spider dispatch gate | `spider.blend > 0.01 → > 0.05` (dispatch site only, not overlay mix) | Skips the patch ray-march during the spider's fade-in/fade-out tail (blend ramping below 5 % opacity is below perceptual threshold). `listenLiftEMA` not plumbed to GPU per D-094, so gate uses `spider.blend` alone — listening pose triggers via the existing path with at most a 1-frame lag. |
| `bd213856` | **SOAK gate** | `shortRunArachneComposite` benchmark added | Kernel-only SOAK_TESTS=1 benchmark. Renders COMPOSITE fragment to 1920×1080 offscreen with spider forced ON (worst case). p95 ≤ 16 ms loose gate. |

**SOAK measurement on M2 Pro (this session, post-L1+L2+L3, spider forced ON every frame):**

```
┌─ ArachneCompositeKernelCost [Tier 2, 1920×1080, spider forced ON] ─
│ frames=1800  mean=12.903ms
│ p50=12.724ms  p95=14.458ms  p99=15.169ms
│ kernel overruns (>14ms)=172 of 1800
└────────────────────────────────────────────────
```

Run-to-run variance ≈ 0.1 ms (two runs: p95 = 14.578 / 14.458). The 16 ms SOAK gate sits ~10 % above the worst-case fixture and well below the pre-tuning ~26 ms baseline a lever-revert would restore.

**Calibration finding worth preserving:** Arachne is fragment-only (no compute pre-pass), so kernel ≈ full-pipeline — there's a small (~0.5–1 ms) overhead from the WORLD pass + drawable presentation + triple-buffering coordination, but the dominant cost is the fragment shader. The initial 5 ms SOAK gate suggested by the BUG-011 prompt was anchored on a kernel:full-pipeline ratio borrowed from a compute-heavy preset (since retired — D-102) and was rebased to 16 ms based on the in-session measurement.

**Why "Open" not "Resolved":** the SOAK forces spider ON every frame (worst case); production has spider idle ~75 % of the time, so real-music p95 will land lower. But the SOAK kernel measurement also doesn't include WORLD pass + drawable cost. Net production p95 is *probably* below 14 ms on M2 Pro but the closure gate is the actual production capture per Verification criteria below — see the DM.3 perf-capture procedure.

L4 (DeviceTier-aware fallback) explicitly NOT pulled — the prompt requires Matt's call before introducing a Tier-1 silhouette fallback. If Matt's real-music capture shows post-L1+L2+L3 p95 still > 14 ms on M2 Pro, L4 is the next escalation; otherwise L4 is unnecessary and the current state closes BUG-011.

---

### 2026-05-12 round-8 follow-up (BEHAVIOURAL, not perf)

The four items from Matt's session `2026-05-11T23-18-42Z` directive landed in three commits on `main` 2026-05-12 (`ceb35340`, `0756a9ef`, `04855e26`; pushed). They share the BUG-011 ID for convenience because the source prompt was titled BUG-011, but they are **operationally distinct from the perf tuning above**: none of them touches frame-budget headroom. The original perf closure gate (Matt's M2 Pro real-music perf capture) is unchanged. See `docs/RELEASE_NOTES_DEV.md` `[dev-2026-05-12-c]` for the full landed-work narrative; the summary lives here so a future session inspecting this entry sees the complete picture.

| Item | Description | Commit |
|---|---|---|
| **4** | 8 % build speedup. `ArachneBuildState.frameDurationSeconds 3.0 → 2.775`; `radialDurationSeconds 1.5 → 1.389`; new `spiralChordsPerBeat = 3.24` advance rate via `spiralChordAccumulator: Float` (fractional residual). Median build cycle ~100 s → ~92 s. | `ceb35340` |
| **1** | Silent-state build pause. New `stemEnergySilenceThreshold = 0.02`; `advanceBuildState` zeros `effectiveDt` when sum of four AGC-normalised stem energies < 0.02. Arachne no longer constructs during prep / silence / source-app paused. Two new gate-regression tests. | `0756a9ef` |
| **3** | Completion-gated transitions. New `PresetDescriptor.waitForCompletionEvent: Bool` (JSON `wait_for_completion_event`, default false). When true, `maxDuration(forSection:)` returns `.infinity` and `applyLiveUpdate` strips mood-derived overrides. Arachne JSON flips on. Existing `wirePresetCompletionSubscription` path delivers the transition trigger. Section-boundary cap unchanged (known limitation). | `04855e26` |
| **2** | "Spokes-below-orb" diagnosis (no code). Frame-extraction from session `T23-18-42Z` `video.mp4` showed every Arachne window in that session caught the build mid-radial-phase. Round-7's geometry was fine; the windows were too short for the build to reach `.stable`. Item 3 structurally resolves this. | (no commit) |

**Why this is "follow-up" not "closure":** the round-8 commits address user-facing problems Matt observed in production (web building during silence; orchestrator transitioning Arachne at ~50 s ignoring the round-7 `duration: 150` bump; build too slow; partial-radial frames misread as a geometry bug). They do not touch the Tier 2 frame-budget headroom that defines BUG-011 the **perf** issue. The perf closure gate documented in Verification criteria below — Matt's M2 Pro real-music perf capture — is still the load-bearing close condition. Round-8 does have one upstream effect on perf measurement: with `wait_for_completion_event: true`, Arachne windows are now ≥ 92 s instead of 47-64 s. When Matt runs the perf capture, that means each Arachne window will contain more frames and produce more statistically stable p50/p95 numbers (the previous numbers from 4,579-frame windows were already statistically reasonable; the new windows will be cleaner).

---

### 2026-05-12 production capture (post-round-8, post-L1+L2+L3)

**Session:** `~/Documents/phosphene_sessions/2026-05-12T18-19-31Z`
**Hardware:** Apple M2 Pro (Mac mini), macOS 26.4.1.
**Build:** post-round-8 `7b5b1f43` (CLAUDE.md doc commit; all three round-8 code commits in tree).
**Procedure:** Followed BUG-011 Reproduction steps. Spotify-prepared playlist; `L` engaged at session start; `⌘[`/`⌘]` cycled to Arachne; `wait_for_completion_event: true` + `diagnosticPresetLocked` kept Arachne pinned for the full session window after the initial Waveform → Arachne transition at engine time 3 s. No mid-session preset changes.

| metric | this capture | post-tuning target | pre-tuning baseline (2026-05-08) | Δ from baseline |
|---|---|---|---|---|
| Frames | 14,152 (≈ 7.9 min) | ≥ 60 s | 4,579 (≈ 77 s) | 3.1× sample |
| **p50** | 13.649 ms | ≤ 8 ms | 14.120 ms | −0.5 ms (essentially unchanged) |
| **p95** | **16.068 ms** ← over budget by 2 ms | **≤ 14 ms** | 26.607 ms | **−10.5 ms** |
| p99 | 29.602 ms | — | 32.743 ms | −3.1 ms |
| max | 57.106 ms | — | 36.072 ms | +21 ms (long tail; see note below) |
| > 14 ms | 5,775 / 14,152 (40.8 %) | — | 52.98 % | −12 pp |
| drops (> 32 ms) | 94 / 14,152 (**0.7 %**) | ≤ 8 % | 1.46 % | comfortably under target |

**Diagnosis:** L1+L2+L3 worked where they were aimed — p95 dropped 10.5 ms, drops halved. Each lever attacked a worst-case spike (spider ray-march max-steps; drop refraction coverage gate; spider dispatch blend threshold). What didn't move is the **median** — 14.120 → 13.649 ms is within run-to-run variance. The post-tuning bottleneck is therefore **always-on per-frame cost**, not worst-case tails. p50 = 13.6 ms means most frames pay ≈ 14 ms of GPU time *before* any conditional work fires:

- WORLD pass (sky gradient + ambient fog + 1-2 god-rays + dust motes — always rendered into the offscreen WORLD texture every frame)
- COMPOSITE always-on work — silk strand SDF evaluation per pixel, chord segment evaluation, polygon ray-clip, mood palette lookup, 12 Hz vibration UV jitter applied to every pixel of the frame
- Drop accumulator pool loop fires per pixel even when the per-pixel drop coverage is below threshold

The p99 (29.6 ms) and max (57.1 ms) tails are heavier than the pre-tuning capture because the new capture is 3× longer (more chance to hit GC / scheduler / OS background spikes) and because the post-round-8 build cycle is ~92 s — long enough that the COMPOSITE pass evaluates the full ~441-chord spiral at peak, where pre-round-8 windows truncated before the spiral phase peaked. Neither tail crosses the 8 % drop threshold — drops are at 0.7 %, well under.

**This is not a closure under the existing criteria** (p95 ≤ 14 ms, p50 ≤ 8 ms both fail). Drops alone (0.7 % ≤ 8 %) would pass.

---

### 2026-05-12 L5 cheap-cleanup tranche (SOAK kernel: p95 14.458 → 12.557 ms)

**Trigger.** Matt asked whether drop-related processing could be retired given that dewdrops were removed in commit `3f6126e0`. Investigation surfaced three categories of dead per-pixel work still running:

1. **`ArachneBuildState.spiralChordBirthTimes: [Float]`** — CPU-side array allocated, cleared, and `.append()`-ed every rising-edge beat × N chord advances. Originally tracked per-chord ages for drop-accretion timing; with drops retired, never read in production. Only consumer was the `dropAccretionAgesChordsCorrectly` test (also retired with the field). Cheap on its own (CPU array operation per beat) but pure dead weight.
2. **`ArachneWebResult.strandTangent` field + tangent-decision logic** — `arachneEvalWeb` computed `result.strandTangent = (closer-of-spoke-vs-chord) ? bestSpokeTangent2D : spirTangent2D` per pixel, then both consumer sites in `arachne_composite_fragment` read it into `tang2D` and immediately `(void)tang2D;`-cast it. The tangent was a Marschner BRDF input demoted in V.7.9; both call sites had been carrying the dead-store since. **Per-pixel dead work.**
3. **Dust-mote `fbm4` early-out** — `drawWorld()` computed `fbm4(driftUV, 0.31)` per pixel, then multiplied by `moteCone = saturate(beamMax * 2.5)`. For pixels outside any shaft cone (`beamMax < ~0.004`, typically ~70-80 % of frame at usual mood values), the multiplier collapsed to ~0 but the 4-octave Perlin call had already happened. Gated the block on `if (beamMax > 0.01)`.

**SOAK kernel-cost benchmark measurement (M2 Pro, 1920×1080, spider forced ON, 1800 frames):**

| metric | pre-cleanup (2026-05-10 baseline) | post-cleanup (this session) | Δ |
|---|---|---|---|
| p50 | 12.724 ms | 11.313 ms | **−1.4 ms** |
| p95 | 14.458 ms | 12.557 ms | **−1.9 ms** |
| p99 | 15.169 ms | 13.178 ms | −2.0 ms |
| mean | 12.903 ms | 11.444 ms | −1.5 ms |
| kernel overruns (>14 ms) | 172 / 1800 (9.6 %) | **1 / 1800 (0.06 %)** | −171 frames |

Run-to-run variance ≈ 0.1 ms (the SOAK gate is 16 ms p95; post-cleanup p95 sits 3.4 ms inside the gate).

**Projection to production p95.** The first production capture (2026-05-12T18-19-31Z) measured p95 = 16.068 ms in real-music conditions; SOAK measured p95 = 14.458 ms in worst-case-spider conditions before this cleanup. The SOAK ↔ production gap was ~+1.6 ms (production runs longer with more OS-scheduler interference) at the previous baseline. Applying the same gap to post-cleanup SOAK (12.557 ms) projects **production p95 ≈ 14.1 ms** — basically at the 14 ms target, within run-to-run noise. **Final closure requires Matt's re-capture** on real music to confirm.

**No visual regression.** Items 1 + 2 are pure dead-code removal; item 3 is an early-out gate at a threshold (`beamMax > 0.01`) where the masked contribution is already ~0 — semantics-preserving up to floating-point. All 43 targeted Arachne tests green; all golden hashes unchanged. App build clean. SwiftLint 0 violations on touched files.

---

### 2026-05-12 production re-capture (post-cheap-cleanup)

**Session:** `~/Documents/phosphene_sessions/2026-05-12T20-30-28Z`
**Hardware:** Apple M2 Pro (Mac mini), macOS 26.4.1.
**Build:** `ef74ce69` (L5 cheap-cleanup tranche).
**Procedure:** Same as the prior production capture, but 21 minutes of pinned Arachne (`L` + `⌘[`/`⌘]`, single Waveform → Arachne transition at 4 s, 37,821 frames). Sample size is 2.7× the prior capture — variance hypothesis can be definitively ruled out.

| metric | re-capture (37,821 frames) | prior production (14,152 frames) | SOAK projection | gap from target |
|---|---|---|---|---|
| p50 | 13.708 ms | 13.649 ms | — | structurally above 8 ms target |
| **p95** | **15.303 ms** | 16.068 ms | ~14.1 ms | 1.3 ms over 14 ms gate |
| p99 | 17.462 ms | 29.602 ms | — | dramatic tail improvement |
| max | 34.457 ms | 57.106 ms | — | dramatic tail improvement |
| > 14 ms | 40.8 % | 40.8 % | — | unchanged |
| **drops (>32 ms)** | **0.02 % (8 / 37,821)** | 0.7 % | — | **400× under 8 % target** |

**SOAK over-projected by ~1.2 ms.** Projected production p95 was ~14.1 ms; measured 15.303 ms. Reasons: (a) the dust-mote `fbm4` early-out lives in `drawWorld()` (WORLD pass) but the SOAK harness `shortRunArachneComposite` runs the COMPOSITE fragment only, so item 3's saving was never reflected in SOAK; (b) SOAK runs spider-forced-ON every frame which over-represents the strand-tangent retirement's win (production has spider idle ~75 % of the time); (c) production has WORLD pass + drawable presentation + OS-scheduler overhead (~+1.6-2.8 ms SOAK ↔ production gap depending on the run). The cleanup tranche helped production by ~0.8 ms (16.068 → 15.303 ms) — real but smaller than SOAK's −1.9 ms suggested.

**Tail spikes essentially eliminated.** p99 dropped 29.602 → 17.462 ms (−12 ms); max dropped 57.106 → 34.457 ms (−23 ms); drops fell 73× (1.46 % → 0.02 %). The L1+L2+L3 worst-case-spike levers compounded with the L5 cheap-cleanup to produce a much smoother frame-time distribution.

**21-minute Arachne window incidentally validated round-8 work.** Orchestrator transitioned Waveform → Arachne at 4 s and never left Arachne for the rest of the session. `wait_for_completion_event: true` + `L`-locked behaving exactly as designed across 21 minutes of continuous playback. No spurious mood-overrides, no spurious section-boundary transitions.

---

### 2026-05-12 closure rationale (Matt's decision: Option 2 — Accept with drops-only criteria)

**Closure path chosen.** Matt 2026-05-12: "path 2" (Accept). BUG-011 closes against relaxed drops-only criteria; the p95 ≤ 14 ms and p50 ≤ 8 ms gates are NOT met but the drops gate (≤ 8 %) is met overwhelmingly (0.02 %, 400× under target).

**Rationale.** The drops result is the user-perceptible metric — a frame > 32 ms is dropped by the compositor and visible as judder. p95 = 15.303 ms means 5 % of frames sit ~1-2 ms above the design budget, but they still complete within ~16-17 ms (at or within one refresh window). The `FrameBudgetManager`'s 14 ms downshift threshold was originally calibrated against the 60 fps refresh budget assuming downshift would prevent visible drops; in practice we're hitting essentially zero drops at p95 = 15.3 ms on M2 Pro. The 14 ms threshold is more aggressive than the actual visual impact requires for this preset/hardware combination.

**Architecture-contract context.** The architecture contract specifies M3+ as Tier 2; M2 Pro is borderline (M2 Pro is "Tier 1.5" in practice — Apple Silicon M2-family with Pro / Max variants that have more cores but the same per-core compute envelope as base M2). Accepting "p95 = 15.3 ms on borderline silicon" is consistent with the contract's spirit. The p95 ≤ 14 ms target stays as the design goal for actual Tier 2 (M3+) hardware; M2 Pro is documented as a known limitation.

**Known limitation to track going forward:** Arachne running on M2 Pro will trip the `FrameBudgetManager` p95 > 14 ms threshold ~5 % of the time, which means the governor may downshift quality more aggressively than designed (potentially toggling off SSGI etc. mid-segment when other presets are active near Arachne windows). This is acceptable on borderline hardware; M3+ silicon should not see this behaviour. **If a future preset addition or shader change eats into the headroom and produces visible drops on M3+ too, L5.1 (WORLD half-rate refresh) is the next escalation** — the cheap-cleanup tranche already retired the structural redundancies the L5 framing was scoped to address, so L5.1 (half-rate WORLD cache) is the only remaining un-pulled lever.

**What's NOT in scope for closure.** L5.1, L4 (M2 Pro → Tier 1 for Arachne), and M3+ measurement are all deferred. They become candidates for a new BUG-XXX entry if Arachne perf regresses on actual Tier 2 silicon in the future, or if a future preset increment eats meaningfully into Arachne's M2 Pro headroom.

**V.7.10 Arachne cert review unblocked.** The cert-review increment had been gated on BUG-011 closure; closure removes the gate. V.7.10 is now eligible to run when Matt schedules it.

---

### ~~Escalation options (Matt to decide)~~ — settled 2026-05-12

**Closure decision: Option 2 (Accept).** Sections below kept for historical reference; the three paths were live until Matt's 2026-05-12 closure decision. If a future regression reopens the perf gap and the cheap-cleanup tranche isn't enough on its own, L5.1 (WORLD half-rate refresh) is the recommended next move.

#### Option A — L5: attack always-on cost (cheap-cleanup tranche LANDED 2026-05-12; LIKELY ALREADY CLOSED)

**Update 2026-05-12.** Cheap-cleanup tranche landed before either of the larger sub-levers below was needed (see "2026-05-12 L5 cheap-cleanup tranche" section above). SOAK kernel p95 dropped 14.458 → 12.557 ms (−1.9 ms); projected production p95 ≈ 14.1 ms — at the gate, within run-to-run noise. **Awaiting Matt's M2 Pro re-capture** to confirm closure. If the re-capture closes p95 ≤ 14 ms, BUG-011 closes and L5.1 / L5.2 below are NOT needed.

If the re-capture still misses p95 ≤ 14 ms (within run-to-run noise: anywhere 13.5–14.5 ms is effectively at the gate), the larger candidate sub-levers remain:

- **L5.1 WORLD pass cached refresh.** Render WORLD at 30 fps (every other frame) and sample the cached texture in between. The WORLD content is mostly slow-moving (sky gradient + ambient fog + god-rays driven by `f.mid_att_rel`); only the dust-mote field moves at audio rate, and that's now early-out-gated by the cheap-cleanup tranche. Estimated saving: 1.5–2 ms on COMPOSITE-only frames. Risk: visible shimmer if cache invalidation logic is wrong on mood transitions; needs tested fallback.
- **L5.2 Drop pool early-out.** **Retired** — the drop pool itself was removed in commit `3f6126e0` (drops retired during web construction); no per-pixel loop remains to prune. The "drop pool" referenced in earlier L5 framing no longer exists; the cheap-cleanup tranche found and removed the last per-pixel residue.

Scope for L5.1 if needed: 1-2 sessions for design + implementation + golden-hash regen + manual smoke. Would need a new `D-XXX` decision entry ("Arachne WORLD half-rate refresh, Tier 2 always-on cost reduction") before implementation.

#### Option B — L4: reclassify M2 Pro as Tier 1 for Arachne specifically

The architecture contract specifies M3+ as Tier 2; M2 Pro is borderline. L4 as originally scoped is "Tier 1 gets the V.7.5 silhouette spider." Re-classifying M2 Pro as Tier 1 for Arachne would:

- Restore V.7.5's 2D silhouette spider on M2 Pro (V.7.7D's 3D SDF spider only on M3+).
- Probably bring M2 Pro p95 well under 14 ms (the spider ray-march is the biggest worst-case cost, even after L1's max-steps reduction).
- Cost: Matt loses V.7.7D on dev hardware permanently; other M2 Pro users likewise.
- Doesn't help users on M3+ silicon (they're already over the bar).
- Needs a new `D-XXX` ("Arachne SPIDER tier-gating: M2 Pro on V.7.5 silhouette; M3+ on V.7.7D 3D SDF").

Scope: 0.5 session. Cheap, but accepts the limitation rather than fixing it.

#### Option C — accept p95 = 16 ms and close with relaxed criteria

Revise the closure criteria to drops-only:

- drops (> 32 ms) ≤ 8 % — **currently 0.7 %, passes**.
- Drop p95 ≤ 14 ms and p50 ≤ 8 ms from the criteria list (or document them as "Tier 2 aspirational targets, M2 Pro is borderline").

Justification: drops are the user-perceptible metric (frame skipped, judder visible). 16 ms p95 means most "over budget" frames still complete within ~16-17 ms — at the edge of one refresh window but rarely dropped by the compositor.

Risk: `FrameBudgetManager` will still downshift quality more aggressively than designed when Arachne is active on M2 Pro (the downshift threshold is 14 ms in the manager's hysteresis logic, not 32 ms). Visible side-effect: SSGI may toggle off mid-segment, etc. Acceptable on borderline silicon; not great on actual Tier 2.

Scope: 1 commit (criteria update + KNOWN_ISSUES status flip + release note). Closes BUG-011 today.

#### Carry-forward (whichever option Matt picks)

- V.7.10 Arachne cert review is unblocked once BUG-011 closes, regardless of which path closes it.
- An M3+ measurement is still a valuable data point under any option — would confirm whether the current state is "M2 Pro is below spec" (M3+ comfortably under p95 = 14 ms) or "Tier 2 budget itself needs revision" (M3+ also over). Cheap to acquire next time the dev environment lines up.

---

### Verification criteria

- [x] Automated: `shortRunArachneComposite` SOAK benchmark added to `SoakTestHarnessTests` (commit `bd213856`). Kernel-only SOAK_TESTS=1 benchmark. SOAK_TESTS=1 gated; loose 16 ms p95 kernel-only gate on M2 Pro at 1920×1080 with spider forced ON. Post-cheap-cleanup p95 sits at 12.557 ms (3.4 ms inside gate).
- [x] **Closed against relaxed drops-only criteria 2026-05-12.** M2 Pro real-music re-capture in session `2026-05-12T20-30-28Z` (37,821 frames, ~21 min of pinned Arachne): drops (>32 ms) = **0.02 %** passes the 8 % gate by 400× margin. p95 = 15.303 ms and p50 = 13.708 ms remain above their respective design targets (14 ms / 8 ms) — documented as known limitations of borderline Tier 2 hardware (M2 Pro is below the architecture contract's M3+ Tier 2 spec). See "2026-05-12 closure rationale" section above.
- [ ] Manual (deferred, not closure-blocking): re-run on M3+ to confirm budget holds at full feature set on actual Tier 2 silicon. Would clarify whether M2 Pro's 15.3 ms p95 is "M2 Pro below spec" (expected — M3+ comfortably under 14 ms) or "Tier 2 budget needs revision" (M3+ also above). If a future M3+ measurement shows p95 > 14 ms there, reopen with a new BUG-XXX entry.
- [x] Manual: Matt confirmed Arachne fidelity unchanged via the 21-minute pinned re-capture session (`2026-05-12T20-30-28Z`). The L1/L2/L3 + L5 cheap-cleanup changes are individually low-risk by construction; the cumulative visual at real-music scale matches the V.7.7C.5 reference set without observed regression.

### Related

- V.7.10 cert review — explicitly gated on this. Cert can't sign off on a preset over budget on its target hardware tier.
- V.7.7C.5 (D-100) — atmospheric reframe just landed; cost growth from V.7.7C.4 baseline likely contributes here, but the bulk of the 14-ms p50 is the V.7.7D spider + V.7.7C drops, both of which predate V.7.7C.5.
- DM.3a (this session's measurement infrastructure made the breach visible).
- **L5 escalation path** (always-on cost reduction — WORLD pass half-rate refresh + drop-pool spatial pruning) — documented above; needs a new `D-XXX` entry before implementation.
- **L4 escalation path** (DeviceTier-aware fallback to V.7.5 2D silhouette spider on Tier 1, plus reclassifying M2 Pro as Tier 1 for Arachne) — documented above; needs a new `D-XXX` entry before implementation.

---

### BUG-014 — Lumen Mosaic panel aggregate uniform across tracks (LM.4.6 limitation superseded by LM.4.7 palette library)

**Severity:** P3 (visible but accepted at cert time; impact is "every Lumen Mosaic session feels statistically similar at the panel level" rather than a hard quality regression — Matt accepted the trade-off at LM.4.6 with the verdict *"Working. It's close enough. I'm giving up the fight on colors,"* and the 2026-05-17 palette exploration converged on a structural fix.)
**Domain tag:** preset.fidelity
**Status:** Resolved by Increment LM.4.7 (pending Matt M7 review on real-music multi-track session per the Done-when criterion in `docs/ENGINEERING_PLAN.md`).
**Introduced:** Documented as a known trade-off at LM.4.6 (`c0f9ccf3`, 2026-05-12) — the shader file header, the ENGINEERING_PLAN Increment LM.4.6 "Honest math caveat" section, and the D-LM-7 amendment all explicitly call it out. LM.7 (`888bb856`-following commits, 2026-05-12) mitigated it at the aggregate-mean level via the per-track chromatic-projected tint (D-LM-7); the palette-character-per-session gap remained.
**Resolved:** 2026-05-18, LM.4.7 implementation (commit pending). `lm_cell_palette` rewritten to palette-table lookup over a per-song 12-colour drawn palette. The Orchestrator selects one of 18 hand-authored palettes per song via mood-biased Gaussian-over-distance draw with anti-repeat exclusion of the last `kAntiRepeatWindow = 3` drawn palettes (widened from N=1 same day after Matt's M7 session showed within-quadrant clustering — see D-LM-palette-library amendment + release-note `[dev-2026-05-18-b]`). New `LumenMosaicPaletteLibrary.swift` holds the catalogue + `selectPalette(...)` algorithm; new slot-8 ABI fields carry the 12-entry palette payload; `LumenPaletteSpectrumTests` regression-locks the six LM.4.7 contract suites (palette membership, selection determinism, anti-repeat over the full recent-window, mood-weighted distribution shape, LM.9 pale-tone-share ≤ 0.30 for all 18 palettes, scripted track-sequence reproducibility). LM.7's chromatic-projection tint (`kTintMagnitude` + raw-tint vector) retired with this increment.

### Expected behavior

Different songs should produce visibly distinct **palette character** at the panel level — a track drawing Cathedral Lights should read as light-through-stained-glass, a track drawing Refn Glow as warm-neon-shadow, a track drawing Glacier as frozen-blue-on-snow. Within a song, every cell can still be any colour the palette's 12 entries allow; across songs, the listener perceives the palette changing at track boundaries.

### Actual behavior (LM.4.6 + LM.7 baseline)

The cell-colour generator (`lm_cell_palette`) samples uniformly from the full RGB cube on every track, with LM.7's per-track tint sliding the sampling window by `±0.20` per channel along the chromatic plane. At ~30 visible cells per panel, law-of-large-numbers convergence makes the **aggregate distribution shape** (mean, hue histogram, saturation distribution) statistically identical across tracks except for the chromatic-plane offset. The aggregate-mean offset gives each track a faintly distinct **tint** but does not give it a distinct **palette character** — every panel still looks like a sample from the same uniform RGB cube with a small chromatic shift.

### Reproduction steps

1. Run a multi-track Lumen Mosaic session against the LM.4.6 + LM.7 baseline (any commit between `c0f9ccf3` / `888bb856` and the LM.4.7 implementation commit).
2. Compare 3–4 panel screenshots taken at the same beat phase across 3–4 different tracks.
3. Observe: the panels are distinguishable (different specific colours per cell, slight chromatic-mean offset) but the overall **palette identity** does not vary — each panel reads as "a random sample from the same uniform-RGB distribution."

The contact-sheet output of `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview` makes the failure mode visible across the 9-fixture set.

### Suspected failure class

`algorithm` — the cell-colour generator's sampling distribution shape is track-invariant by construction. LM.7's tint mitigates the **mean** of the distribution but not the **shape**. The fix is a structural replacement of the cell-colour source — palette-library-driven per-cell sampling with per-session palette selection — not a tuning pass on the existing generator.

### Verification criteria

- Automated: `LumenPaletteSpectrumTests` asserts palette membership (every cell colour matches one of the 12 palette entries to within float epsilon) per LM.4.7's rewritten test suite; per-song selection determinism (same `(track ID, previous-palette)` → same drawn palette); immediate-repeat exclusion (consecutive tracks cannot share a palette).
- Manual: Matt M7 review on a real-music multi-track session — each song's palette reads as its named character (e.g. a track drawing Cathedral Lights reads as stained-glass; a track drawing Refn Glow reads as warm-neon-shadow) at the panel level, distinct from neighbouring tracks' palettes; the palette change at track boundaries is visible.
- Mechanical: the LM.9 pale-tone-share gate (≤ 0.30; per D-LM-cream-rescission) passes for all 18 palettes — Cathedral Lights specifically must pass at its ~17 % nominal share (2 of 12 palette entries pale under the rule's linear-RGB definition; see D-LM-cream-rescission Erratum).

### Related

- D-LM-palette-library (this session) — the 18-palette library is the structural fix.
- D-LM-cream-rescission (this session) — the anti-cream rule rescission is what makes pale-rich palettes (Cathedral Lights, Cycladic, Ming Porcelain) shippable inside the library.
- LM.4.6 + LM.7 entries in `docs/ENGINEERING_PLAN.md` (Phase LM, both ✅ 2026-05-12) — the prior shape and its documented trade-off.
- LM.4.7 entry in `docs/ENGINEERING_PLAN.md` (Phase LM, ⏳) — the implementation increment.

---

### BUG-012 — MPSGraph EXC_BAD_ACCESS in StemFFTEngine during sustained force-dispatch

**Severity:** P1 (process-fatal crash; surfaced under sustained jank — ML dispatch scheduler hitting the 2100 ms ceiling and force-firing repeatedly. Not reproducible on every session but observed at least once at 2026-05-15T17:54Z.)
**Domain tag:** ml
**Status:** Open
**Introduced:** Unknown; surfaced 2026-05-15. Stack frames are all in code that predates the V.9 Session 4.5c ferrofluid work — none of the rounds 16-26 commits touched StemFFTEngine, MPSGraph, or live stem separation. Suspect a latent race that requires specific timing patterns to surface.
**Resolved:** —

---

### Expected behavior

`StemFFTEngine.runForwardGraph()` completes its MPSGraph dispatch on every call, returning the forward STFT real + imag outputs to `StemSeparator.stft(mono:)`. No nil-pointer dereference, no process termination.

### Actual behavior

`EXC_BAD_ACCESS (code=1, address=0x8)` at `MPSGraph.run(withMTLCommandQueue:feeds:targetOperations:resultsDictionary:)`, called from `StemFFTEngine.runForwardGraph()`. Address 0x8 is "offset 8 from nil" — typical signature of accessing a member on a nil object reference. The session that captured the crash (`~/Documents/phosphene_sessions/2026-05-15T17-54-49Z/`) shows clean shutdown in session.log (`SessionRecorder finished (7140 frames, 15 stem dumps)`) — the crash fired after the session-recorder finalised, during continued playback or teardown.

Stack:

```
Thread 71 — com.phosphene.stemSeparator queue
0  MPSGraphOSLog
6  -[MPSGraph runWithMTLCommandQueue:feeds:targetOperations:resultsDictionary:]
7  StemFFTEngine.runForwardGraph()
8  StemFFTEngine.gpuForward(mono:)
9  StemFFTEngine.forward(mono:)
10 StemSeparator.stft(mono:)
11 StemSeparator.separate(audio:channelCount:sampleRate:)
12 VisualizerEngine.performStemSeparation()
13 closure #2 in closure #1 in VisualizerEngine.runStemSeparation()
```

Preceding session.log lines show repeated `ML: force-dispatch after 2100ms — ceiling hit, jank ignored` messages — the ML dispatch scheduler force-firing because the previous separation exceeded the 2100 ms ceiling.

### Reproduction steps

1. Start a session with a Spotify-prepared playlist.
2. Run playback for ≥ 3 minutes (Love Rehab + Money has reproduced once at 2026-05-15T17:54Z).
3. Observe sustained `force-dispatch after >2100ms` messages in session.log indicating ML scheduler backpressure.
4. The crash may fire mid-playback or during teardown — not deterministic.

**Minimum reproducer:** unknown — single observed occurrence so far. Suspected trigger: high concurrent load on the stem separator queue (multiple in-flight separations + force-dispatch races) on Tier 2 hardware.

---

### Session artifacts

**Session directory:** `~/Documents/phosphene_sessions/2026-05-15T17-54-49Z/`

**Hardware:** Apple M2 Pro (Mac mini), macOS 26.4.1.

**Xcode screenshot (manually captured):** EXC_BAD_ACCESS dialog at the MPSGraph.run call site, Thread 71 — com.phosphene.stemSeparator queue.

session.log tail at the time of the crash:

```log
[2026-05-15T17:57:27Z] stem separation 14 (440320 samples) track=Money → 0014_Money
SessionRecorder finished (7140 frames, 15 stem dumps)
```

(Crash fired after this line — outside the session-recorder's captured range.)

---

### Suspected failure class

`concurrency` — race between the ML dispatch scheduler's force-dispatch path and a stem separator's in-flight buffer / graph reference. Address 0x8 = nil-pointer offset → a held reference was concurrently freed.

**Evidence for this class:** The force-dispatch messages preceding the crash indicate sustained backpressure. The ML scheduler force-fires a NEW dispatch while a PRIOR dispatch may still be holding buffers. If teardown of the prior dispatch races with the new one's setup, you get a nil-pointer access at MPSGraph.run.

---

### Verification criteria

When this defect is resolved:

- [ ] Sustained 5+ minutes of stem-separation-heavy playback with multiple force-dispatch events does not crash.
- [ ] An instrumented capture shows MPSGraph buffer lifetimes are properly scoped to one dispatch (no overlapping references).
- [ ] If concurrency is confirmed: a regression test exercises the force-dispatch path with deliberately racing setup/teardown.

**Manual validation required:** Yes — multi-minute capture on Tier 2 hardware under sustained load.

---

### Fix scope

Investigation: 2-4 hours (instrument MPSGraph buffer lifetimes, audit force-dispatch path for concurrent buffer access). Fix: depends on findings — could be a single missing lock or a larger refactor of the dispatch scheduler's concurrent semantics.

### 2026-05-20 race-surface analysis (no fix; instrumentation only)

A dispatch-path analysis was completed against the one observed crash. Findings:

- `stemQueue` (`com.phosphene.stemSeparator`) is a serial `DispatchQueue` (utility QoS). The 5 s `DispatchSourceTimer`, the MainActor scheduler-decide hop, and the `stemQueue.async { performStemSeparation() }` re-entry all enqueue onto the same serial queue. By construction `performStemSeparation` cannot be concurrent with itself.
- `StemFFTEngine` holds its `MPSGraph`, `commandQueue`, and `MTLBuffer`s as `let` members. `StemSeparator` holds the engine via `private let fftEngine`. `VisualizerEngine` holds the separator via `let stemSeparator: StemSeparator?`. Strong references — the engine's resources cannot be torn down while a `performStemSeparation` call is in flight unless `VisualizerEngine` itself is being deallocated.
- `StemFFTEngine.forward(mono:)` acquires an internal `NSLock` before entering `gpuForward → runForwardGraph`. Concurrent callers (if they ever existed) would block, not race.
- The `MLDispatchScheduler` is pure-state. It does not mutate any cross-thread resource on `forceDispatch`; the caller is the one that submits the new dispatch.
- The crash fired *after* `SessionRecorder finished` in `session.log`. That correlates with teardown — the surviving hypothesis is a teardown race during a MainActor scheduler hop where `[weak self]` resolves non-nil at the boundary and the engine deinitialises while a `stemQueue.async` is enqueued.

What we *don't* know and the next reproduction must capture: (a) whether `[weak self]` was nil at the MainActor or stemQueue hop, (b) whether the engine was actively being deinit'd, (c) whether MPSGraph buffer addresses were valid immediately before the call, (d) where the 2100 ms force-dispatch ceiling fired *relative to* the dispatching that crashed, (e) whether two `performStemSeparation` calls were somehow in flight despite the serial-queue contract.

**Instrumentation installed (`[BUG-012-i1]`, 2026-05-20).** Pure-observability additions across `PhospheneEngine/Sources/Shared/`, `Sources/ML/`, `Sources/Renderer/`, and `PhospheneApp/`:

- `Logging.bug012` (new os.Logger category `com.phosphene/bug012`).
- `BUG012Probe` namespace (`Sources/Shared/BUG012Probe.swift`) with: monotonic dispatch-ID generator, in-flight counters for `stem dispatch` and `fft forward` / `fft inverse` with `.notice`-level **ALARM** logs if any counter exceeds 1, lifecycle counters for `StemFFTEngine` / `StemSeparator` / `VisualizerEngine` init+deinit, free-form `log()` / `notice()` helpers tagged `[BUG-012]`.
- `StemFFTEngine.init/deinit/forward/inverse` — lifecycle + in-flight + lock-acquire/release events.
- `StemFFTEngine.runForwardGraph/runInverseGraph` — buffer-address + storage-mode dump immediately before `MPSGraph.run`; matching post-call line.
- `StemSeparator.init/deinit/separate` — lifecycle + ENTER/EXIT log per call.
- `MLDispatchScheduler.decide` — log every decision (was only `.forceDispatch`).
- `VisualizerEngine.init/deinit` — lifecycle markers.
- `VisualizerEngine+Stems.runStemSeparation` — timer-fire log, MainActor `self?` resolution, scheduler decision, queued performStemSeparation, weak-self resolution at each `stemQueue.async` re-entry (logs explicitly if `self == nil`).
- `VisualizerEngine+Stems.performStemSeparation` — `enterStemDispatch` / `exitStemDispatch` with outcome label (`ok` / `threw` / `warmup-skip` / `silence-skip` / `no-separator`); the separator.separate call is wrapped in `.notice`-level CALL/RETURN log lines.

Regression test: `BUG012ConcurrencyTest` (4 threads × 3 forwards on one engine) regression-locks the engine's thread-safety contract. The test does not reproduce the crash today; it fires if a future change exposes `StemFFTEngine.forward` to genuinely concurrent callers (a stricter contract than the dispatch path requires, hence safer).

**Centralised instrumentation reading-aid:** the complete per-line BUG-012-i1 probe map (every `BUG012Probe` call site labelled with its dispatch-ID semantics and severity) is published as part of the CA.2 ML capability audit at [`docs/CAPABILITY_REGISTRY/ML.md §BUG-012 instrumentation map`](../CAPABILITY_REGISTRY/ML.md#bug-012-instrumentation-map). The CA.2 audit's read of every BUG-012-adjacent code path (2026-05-20) did not edit any instrumented file and surfaced no new candidate root cause beyond the race-surface analysis above. One small diagnostic enrichment is suggested for the next instrumentation tranche — `CA.2-FU-2` in the audit's Follow-up Backlog.

**How to read the next reproduction:**
```
log show --predicate 'subsystem == "com.phosphene" AND category == "bug012"' --info --last 30m | grep '[BUG-012]'
```
- Look for the last `[BUG-012] MPSGraph.run forward CALL id=N input=...` before the crash. The buffer-address line tells you whether the buffers were the expected ones.
- Look for any `[BUG-012][ALARM]` lines. Any alarm at all is diagnostic gold — it means a serial-queue or lock contract was violated.
- Look for `[BUG-012] VisualizerEngine deinit` near the crash. Presence = teardown race; absence = steady-state crash.
- Look for `[BUG-012] stemQueue.async self=nil` lines. Presence = the engine was already nil when stemQueue picked the closure up.

### Related

Out of scope for V.9 Session 4.5c ferrofluid preset work (none of rounds 16-26 touched StemFFTEngine or MPSGraph). Filed for a future dedicated investigation. Step 1 (instrumentation) landed 2026-05-20 as increment `[BUG-012-i1]`; step 2 (diagnosis from instrumented reproduction) and step 3 (fix) follow.

---

### BUG-013 — Soundcharts does not expose `time_signature`; ML meter detection wrong on some odd-meter tracks

**Severity:** P2 (visual artifact on a subset of odd-meter tracks. Bar-locked motion presets (Ferrofluid Ocean) cycle at the wrong rate on tracks where the ML meter detector guesses wrong AND the metadata source can't override. Current production playlist only surfaces this on Pink Floyd's Money 7/4 → cycles at 5.85 s/cycle on Ferrofluid Ocean instead of the intended 20.5 s/cycle. Visual still reads as "ocean swell" per Matt's 2026-05-15T17-54-49Z review.)
**Domain tag:** dsp.beat
**Status:** Open
**Introduced:** Surfaced 2026-05-15 during Ferrofluid Ocean Round 25-26 metadata-override implementation.
**Resolved:** —

---

### Expected behavior

When `MetadataPreFetcher` returns a profile for a track, `PreFetchedTrackProfile.timeSignature` carries the track's time-signature numerator (3 for 3/4, 4 for 4/4, 7 for 7/4, etc.). `SessionPreparer.analyzePreview` overrides `BeatGrid.beatsPerBar` with this value before caching. Downstream consumers (FerrofluidMesh vertex shader's bar-locked wave cycling) use the correct meter.

### Actual behavior

`PreFetchedTrackProfile.timeSignature` is always nil in production. Soundcharts (the only metadata source in production that exposes audio features) does not return `time_signature` in its API response — verified by adding the decode field and observing zero hits in session.log (no `Using pre-fetched time signature: N/X` lines for any of Love Rehab, So What, There There, Pyramid Song, Money).

Result: `BeatGrid.beatsPerBar` retains the ML-detected value. For Money (actual 7/4), the ML detector classifies as `meter=2/X` — wave cycle is `6 × 60 × 2 / 123 = 5.85 s` instead of the intended `6 × 60 × 7 / 123 = 20.5 s`.

### Reproduction steps

1. Build app: `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`
2. Start a Spotify-prepared session including Money by Pink Floyd.
3. Switch to Ferrofluid Ocean preset.
4. Observe wave cycle period during Money playback (~5.85 s, not the intended 20.5 s).
5. `grep "time signature" session.log` returns no matches.
6. `grep "BeatGrid installed" session.log` shows `meter=2/X` for Money.

**Minimum reproducer:** any Spotify-prepared session containing Money (or Pyramid Song's 16/8, or any other odd-meter track where the ML detector guesses wrong).

---

### Session artifacts

**Session directory:** `~/Documents/phosphene_sessions/2026-05-15T17-54-49Z/`

```log
[2026-05-15T17:57:01Z] BeatGrid installed: source=preparedCache, track='Money', bpm=123.2, beats=62, meter=2/X
```

No `Using pre-fetched time signature` lines exist in the file.

---

### Suspected failure class

`api-contract` — Soundcharts' audio-features endpoint doesn't expose `time_signature` (or strips it from the Spotify upstream they proxy). The Phosphene-side override mechanism is wired correctly (Round 26); it has no value to consume.

**Evidence for this class:** Decoder was added with `CodingKeys: time_signature` mapping; field stays nil on every track. ML override path fires (Round 25 / 26 code paths) but with nil input → no-op.

---

### Verification criteria

When this defect is resolved:

- [ ] `session.log` includes `Using pre-fetched time signature: N/X` lines for tracks where the value is known.
- [ ] Money's installed BeatGrid logs `meter=7/X`, not `meter=2/X`.
- [ ] Ferrofluid Ocean wave cycle on Money matches the intended `6 × 60 × 7 / 123 = 20.5 s` period.

**Manual validation required:** Yes — visual confirmation that Money's wave rolls at the calmer 20.5 s cadence.

---

### Fix scope

Three potential paths:

1. **Path B — per-track hardcoded overrides.** Maintain a small JSON config mapping `spotifyID → timeSignature` for known-tricky tracks. Works for the few odd-meter tracks Matt's playlists actually contain; doesn't scale. ~40 lines + manual curation.

2. **Add a different metadata source that exposes `time_signature`.** Spotify's `/audio-features` had the field but was deprecated for most apps in late 2024. AudD or AcousticBrainz might. Each new fetcher = ~150-300 lines of integration.

3. **Improve ML meter detection on odd-meter tracks.** Out of scope for Phosphene application code — would require either retraining Beat This! or post-processing the downbeat probabilities with a meter-specific search.

Current status: deferred. The Round 26 visual review accepted Money's 5.85 s cycle as "smooth and synced — solid." Revisit if/when a future playlist surfaces an odd-meter track where the visual reads wrong.

### Related

V.9 Session 4.5c Rounds 25-26 (metadata-override wiring), Round 21-24 (Gerstner bar-locked motion), BUG-001 (Money 7/4 live-path detection failure — different code path, related cause).

---

### BUG-001 — Money 7/4 stays REACTIVE on live path

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** Open
**Introduced:** DSP.3.5 (identified; pre-existing limitation of the 10-second live window)
**Resolved:** —

**Expected behavior:** After 20 seconds of playback (two retry attempts), Beat This! produces a usable BeatGrid for Money 7/4 and `lock_state` advances past UNLOCKED.

**Actual behavior:** Beat This! returns an empty grid on both the 10-second and 20-second attempts. The session stays in REACTIVE mode throughout. `grid_bpm=0` in `features.csv`.

**Reproduction steps:**
1. Start an ad-hoc reactive session (no Spotify preparation).
2. Play "Money" by Pink Floyd in Apple Music.
3. Switch to SpectralCartograph preset and observe mode label.
4. Observe "○ REACTIVE" for the full track.

**Minimum reproducer:** "Money" by Pink Floyd, ad-hoc reactive session.

**Session artifacts:**
- `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md` — contains the evidence and analysis.

**Suspected failure class:** calibration
**Evidence:** 10-second window at 120 BPM gives ~20 beats, which is insufficient for confident downbeat estimation on 7/4 irregular meter. The retry at 20 seconds sees the same 10-second snapshot (not a longer window), so it does not help. The 30-second Spotify-prepared path gives ~61 beats and reliably detects the meter.

**Verification criteria:**
- [ ] Connecting a Spotify playlist that includes "Money" results in a prepared BeatGrid with `beats_per_bar=7` in `KNOWN_ISSUES.md` test notes.
- [ ] Manual: beat grid ticks in SpectralCartograph align to perceived quarter notes.

**Fix scope:** The durable fix is not to tune the live path — it is to use a Spotify-prepared session. The live path (10-second window) is below the beat-count floor for irregular-meter tracks by construction. See `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md` for the evidence. A potential improvement (not yet planned) would be to extend the live-path snapshot to 20–30 seconds on the retry, but this carries a 1.5–2× memory cost per attempt.

**Related:** DSP.3.5, D-077

---

### BUG-005 — Spotify `preview_url` returns null for some tracks

**Severity:** P3
**Domain tag:** session.ux
**Status:** Open
**Introduced:** U.11 (discovered during integration testing)
**Resolved:** —

**Expected behavior:** `PreviewResolver` finds a 30-second preview for every track in a Spotify playlist and preparation completes for all tracks.

**Actual behavior:** Rights-restricted or region-locked tracks return `null` for `preview_url` from Spotify's `/items` endpoint. These tracks fall through to iTunes Search API, which also returns no preview for some of them. Affected tracks show `TrackPreparationStatus.noPreviewURL` in `PreparationProgressView`.

**Minimum reproducer:** Any playlist containing tracks by Mclusky, or region-restricted regional-exclusives.

**Session artifacts:** `session.log` `noPreviewURL` entries.

**Suspected failure class:** api-contract (external API limitation, not a Phosphene bug)

**Verification criteria:**
- [ ] `PreparationProgressView` shows a clear "No preview available" status for affected tracks rather than a spinner or error.
- [ ] Session proceeds to `.ready` state even when some tracks have no preview.

**Fix scope:** UX copy improvement only. The underlying limitation (no preview URL from either Spotify or iTunes) is not fixable by Phosphene. See Failed Approach #47.

**Related:** U.11, D-070, Failed Approach #47

---

## Pre-existing Flakes (non-blocking, test infrastructure only)

These test failures are pre-existing, environment-dependent, and do not indicate behavioral regressions. They are tracked here for completeness.

| Test | Condition | Workaround |
|---|---|---|
| `MetadataPreFetcherTests.fetch_networkTimeout_returnsWithinBudget` | Intermittent network call timing variance under load | Run in isolation: `swift test --filter fetch_networkTimeout_returnsWithinBudget` |
| `MemoryReporterTests` growth assertions | `phys_footprint` variance across system memory pressure states | Run with other apps quit; or skip with `SKIP_MEMORY_TESTS=1` |
| `AppleMusicConnectionViewModelTests` (4 tests) | Requires Apple Music.app to be installed and reachable; CI-only failure | Run on dev machine with Apple Music installed |
| `PreviewResolverTests` timing tests | Rate-limit timing sensitive under parallel test execution | `@Suite(.serialized)` applied; still flakes under peak system load |

---

## Resolved (recent)

### BUG-018 — Stem deviation primitives systematically exceed declared `[0, 1]` ceiling during cold-start

**Severity:** P1 (load-bearing for "preset doesn't look broken" product claim — affects all stem-consuming presets on every track change for ~30 seconds).
**Domain tag:** dsp.stem
**Status:** **Resolved 2026-05-28** — manual M7 outstanding (Matt's gate).
**Introduced:** Pre-existing. The deviation EMA was added with `stemRunningAvg: [Float] = [0, 0, 0, 0]` (zero-initialised, re-zeroed on `reset()`) and the formula `dev = (energy − runningAvg) × 2.0`. The first post-reset frame has always emitted `2 × energy` instead of 0; bug surfaced explicitly during the CSP.3 → CSP.3.1 dive 2026-05-27 when Matt observed FFO spike heights pinning to the shader's clamp ceiling during cold-start.
**Resolved:** 2026-05-28 — SAR.1. Self-seed each `stemRunningAvg[i]` from the first post-reset frame where stem `i` has non-zero energy. See `RELEASE_NOTES_DEV.md [dev-2026-05-28-a]`.

### Expected behavior

`vocalsEnergyDev`, `drumsEnergyDev`, `bassEnergyDev`, `otherEnergyDev` stay within their declared `[0, 1]` range across the session, including immediately after every track change. Rare extreme single-frame transients can exceed 1.0 (the 10-second EMA can't react that fast), but there is no chronic out-of-range pattern across cold-start windows.

### Actual behavior

Every track change produces a ramp from 0 → 8 → 16 → 27 → 38 across ~60 ms at the live-stems handoff, then a ~30-second slow decay back into range. All four stems exhibit the pattern. Pre-fix cross-session scan across 7 recent sessions (2026-05-27, 87,194 total frames):

| Session | bassMax | drumsMax | vocalsMax | otherMax |
|---|---:|---:|---:|---:|
| 2026-05-27T16-09-47Z | 7.44 | 6.68 | 8.52 | 7.11 |
| 2026-05-27T19-38-32Z | 4.81 | 2.79 | 3.87 | 3.12 |
| 2026-05-27T19-44-25Z | 2.09 | 2.33 | 3.00 | 2.00 |
| 2026-05-27T19-47-18Z | 28.07 | 28.65 | 26.31 | 27.05 |
| 2026-05-27T19-52-42Z | 37.69 | 37.28 | 38.68 | 40.85 |
| 2026-05-27T20-29-39Z | 0.75 | 0.64 | 2.63 | 1.05 |
| 2026-05-27T20-32-45Z | 0.76 | 0.68 | 2.69 | 1.03 |

Affected presets (consumers of `*_energy_dev`): Ferrofluid Ocean spike heights, Lumen Mosaic cell colors, Aurora Veil brightness route, Volumetric Lithograph terrain pulse, Membrane kick shockwave. Visual symptom: presets read clamp-saturated input for the first ~30 seconds of each track, producing "stuck on max" behaviour (FFO spike pinning, LM color saturation, etc.). Misattributed to per-preset cold-start design failures during the CSP.2 dive.

### Reproduction steps

1. Play any track in any session-recording-enabled run.
2. Inspect `stems.csv` columns `bassEnergyDev`, `drumsEnergyDev`, `vocalsEnergyDev`, `otherEnergyDev`.
3. Observe: 2–4 % of rows have values > 1.0; max value across a session typically 5–40× the declared ceiling; concentrated in the first ~30 seconds of each track (live-stems convergence window).

**Minimum reproducer:** any captured session. The bug is structural and reproduces on every track change.

### Session artifacts

- **Primary evidence:** `~/Documents/phosphene_sessions/2026-05-27T19-52-42Z/stems.csv` — rows 844–849 show the cold-start ramp 0 → 7.81 → 16.05 → 27.18 → 37.69 across ~60 ms. 185 of 5270 frames (3.51 %) have `bassEnergyDev > 1.0`.
- **Cross-session evidence:** 7-session sweep above. Pattern is structural.
- `features.csv` is not load-bearing here — the deviation primitives are in `stems.csv`. `session.log` shows no anomaly (the EMA math is silent).

### Suspected failure class

`algorithm`. The deviation EMA's running-average initialisation is incompatible with its formula. The two pieces interact correctly in steady state but the first post-reset frame has no defined energy reference, so the formula reduces to `2 × energy` for any non-zero input. Same failure shape as MV-1's authoring intent (D-026: "deviation primitives drive primary motion") presumes the primitives respect their declared range; the analyzer-layer bug invalidates that for ~30 seconds out of every track.

**Evidence for this class:** the math is locally consistent (decay = 0.9989, blend = 0.0011, formula matches the docstring) but the initial-condition handling is wrong. Not a concurrency, sample-rate, or pipeline-wiring failure — the code does exactly what it says, just with the wrong starting state.

### Verification criteria

- [x] Automated: `StemAnalyzerDeviationSeedingTests` suite — 4 tests covering first-frame deviation = 0, steady state stays in `[0, 1]`, `reset()` re-arms the seed, per-stem seeding is independent. All pass.
- [x] Pre-fix cross-session range check (above) confirms the chronic pattern across multiple sessions; documented in `RELEASE_NOTES_DEV.md [dev-2026-05-28-a]`.
- [ ] **Manual M7:** Matt re-runs the FFO A/B with the `ffoColdStartFixEnabled` toggle. Expected: the 18–30 s "preset stops moving / flickering colors" symptom disappears; CSP.3.1 cold-start motion remains. Fresh session `stems.csv` shows no chronic out-of-range deviation rows (≤ rare single-frame transients only).
- [x] Regression: the long-EMA-time-constant rationale (2026-04-17 Slint outro diagnosis) is preserved — the decay constant 0.9989 is unchanged.

**Manual validation required:** Yes. Subjective gate: the visual response should feel "continuously alive" through the cold-start window on stem-consuming presets, not "saturated then settling."

### Fix scope

Contained. Four lines in `updateEMAsAndComputeDeviations` (StemAnalyzer.swift:259-262) plus docstring updates. No preset shader changes; no engine-wide architecture changes. Steady-state behaviour unchanged. Trivial P1 collapse (per `DEFECT_TAXONOMY.md` — small change, root cause obvious from the empirical artifact, no architectural risk).

### Related

- Increment: SAR.1 (single increment, trivial P1 collapse approved by direct prompt scope).
- Failed Approach: this is the analyzer-layer twin of Failed Approach #31 (absolute thresholds on AGC-normalised energy) — same root pattern (assumes a steady-state reference that doesn't exist on cold-start) at the deviation-primitive layer.
- Decision: D-026 (deviation primitives drive primary motion). SAR.1 makes D-026's design contract empirically true for the first 30 seconds of each track.
- Phase: Phase CSP can resume after SAR.1.

---

### Sweep note (2026-05-12)

The 11 entries below were moved from the Open section to here as part of a quality-docs audit. Each was already marked `Status: Resolved` (or `Status: Closed — attempt reverted`, for BUG-007.3) in its body but had not been physically relocated. No content changes — entries are byte-identical to the originals; only their position in the document changed. Sort order is by resolution date (newest first within the 11), then back into the existing Resolved chronology.

---

### BUG-007.9 — Hybrid runtime recalibration

**Severity:** P2 (visible on tracks where prep-time calibration over-shoots).
**Domain tag:** dsp.beat
**Status:** **Resolved 2026-05-07** — manual validation pending.
**Introduced:** Surfaced by manual validation of BUG-007.8 in session `2026-05-07T22-51-36Z`. Of 8 tracks tested, 5 improved, 1 stable, 2 regressed (Around the World drift went from −28 → +101 ms; Levitating from −50 → +56 ms). Cause: prep-time calibrator measures onset timing on **preview MP3** (22 050 Hz, ~96 kbps, non-overlapping FFT = 46 ms resolution) but live tracker fires onsets on **tap audio** (48 000 Hz, full quality, overlapping FFT). When encodings diverge enough, prep bias points wrong way.

**Resolved:** 2026-05-07. Runtime recalibration pass: after stem separation completes (≥10 s of tap audio buffered) AND lock has stabilised (`matchedOnsetCount >= 8`), replay the latest 12 s of tap audio through the same `GridOnsetCalibrator` and override the prep-time bias via new `LiveBeatDriftTracker.applyCalibration(driftMs:)`. One-shot per track. Runtime calibration uses the audio the listener actually hears.

**Expected behavior:** All 8 tracks from session `T22-51-36Z` show drift near zero by ~15 s. Tracks that regressed under BUG-007.8 (Around the World, Levitating) recover; tracks that worked stay correct.

**Diagnosis notes:**
- Same calibration algorithm, different audio sources. Runtime always wins because it measures against played audio.
- Prep-time bias still useful for the first ~15 s before runtime fires.
- If runtime calibrator returns 0 (silent intro, no onsets), prep-time bias retained; `runtimeRecalibrationDone` set true regardless to avoid retry storms.
- Stem-separation cadence (5 s) drives the trigger. Recalibration fires on the first stem-sep callback that meets all gates.
- BUG-007.6 `audioOutputLatencyMs` orthogonal.

**Verification criteria:**
- [x] Automated: `LiveBeatDriftTrackerTests` MARKs 39–41 — applyCalibration overrides drift, clamps to ±500 ms, currentGrid + matchedOnsetCount accessors.
- [ ] Manual: drift averages near zero within 15 s of lock on all 8 tracks (especially Around the World, Levitating).
- [ ] Manual: no regression on tracks that worked pre-7.9.
- [ ] Manual: `BUG-007.9: runtime recalibration fired` log line in `session.log` once per track.

**Related:** BUG-007.8 (prep-time calibration — kept as initial bias). BUG-007.6 (display shift — orthogonal). BUG-010 (stem-separation audit — separate).

---

### BUG-007.8 — Per-track grid-vs-onset offset calibration

**Severity:** P1 (visible — visual fires off the beat by track-specific amounts up to ±100 ms; the dominant residual sync issue after BUG-007.4/5/6 landed).
**Domain tag:** dsp.beat
**Status:** **Resolved 2026-05-07** — manual validation pending.
**Introduced:** Pre-existing in all prior code; surfaced by session `2026-05-07T22-00-00Z` running an 8-track bass-forward playlist (Billie Jean / AOBTD / Seven Nation Army / Around the World / Get Lucky / Superstition / Levitating / bad guy). Drift averages spanned −95 to +96 ms across the playlist — a 191 ms range. The fixed `audioOutputLatencyMs = 50` constant from BUG-007.6 only compensated one direction; positive-drift tracks were over-corrected, negative-drift tracks under-corrected.

**Resolved:** 2026-05-07. New `GridOnsetCalibrator` runs at preparation time alongside `BeatGridAnalyzer`, replaying the preview audio through the live `BeatDetector` offline and computing the median `(gridBeat − onsetTime)` offset. Stored on `CachedTrackData.gridOnsetOffsetMs`. Applied at playback-time `setBeatGrid` as the EMA's initial drift bias. The drift tracker still runs at runtime to fine-tune if conditions differ; calibration just gives it a correct starting point per track.

**Expected behavior:** Visual orb fires on the kick the listener hears, regardless of track-specific differences in Beat This! grid timing vs sub-bass onset detector latency. Drift EMA converges near zero rather than chasing ±100 ms offsets.

**Actual behavior (pre-fix):**
- Drift varies ±95 ms per track on bass-forward playlists.
- Fixed `audioOutputLatencyMs = 50` correction works for some tracks (negative-drift), fails on others (positive-drift).
- User reports visual sync wandering across tracks even when lock state holds.

**Reproduction steps:**
1. Spotify-prepared session with mixed-genre playlist (rock + pop + hip-hop).
2. Watch SpectralCartograph drift readout per track.
3. Pre-fix: drift averages vary widely (Billie Jean −77 ms, bad guy +96 ms, AOBTD −95 ms).
4. Visual orb sync varies track-to-track.

**Suspected failure class:** `algorithm` (variable per-track offset between grid timing and onset detector — runtime EMA chases instead of preparation-time calibrating).

**Diagnosis notes:**
- Beat This! is calibrated on broadband perceptual beat; sub-bass onset detector fires on kick spectral peak in the 20–80 Hz band. The two timestamps for "the beat" can differ by track-specific amounts (10–150 ms).
- Sources of variability: kick attack envelope shapes, sub-bass leakage from synth pads / bass guitar, Beat This!'s training-data biases, our onset detector's FFT-window centring.
- Runtime drift EMA does eventually converge to the right offset, but takes ~4 onsets (~2 s) at 120 BPM. During that time the visual is off. Pre-loading the EMA to the calibrated value fixes this.
- This is a *systemic* fix — not patching a symptom. Replaces the BUG-007.6 `audioOutputLatencyMs = 50` heuristic with per-track measured values. The BUG-007.6 constant is retained as a fallback for live-analysis tracks (no preparation-time calibration available).

**Verification criteria:**
- [x] Automated: `GridOnsetCalibratorTests` (5 tests) — empty grid, insufficient samples, silence, aligned kicks, offset kicks.
- [x] Automated: `LiveBeatDriftTrackerTests` MARKs 36–38 — initialDriftMs seeds EMA, clamps to ±500 ms, backward-compat single-arg setGrid defaults to 0.
- [ ] Manual: replay the 8-track bass-forward playlist from session `T22-00-00Z`; drift averages near ±20 ms (down from ±100 ms).
- [ ] Manual: visual orb fires on the kick the listener hears across all tracks.

**Related:** BUG-007.4/5/6 (orthogonal — patch other symptoms). BUG-008 (offline BPM disagreement — also addresses Beat This! limitations but at the BPM level, not timing).

---

### BUG-007.4 — Beat-counter "1" misaligned with song's actual downbeat on prepared-cache tracks

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** **Resolved 2026-05-07** — BUG-007.4a (manual `Shift+B`) + BUG-007.4b (single-dominant auto-rotate) + BUG-007.4c (kick-on-1+3 alternating pattern auto-rotate) landed. Manual validation pending.
**Introduced:** Reported 2026-05-07 from manual validation captures (`2026-05-07T14-28-40Z/` and prior). User-observed: when watching the SpectralCartograph beat-in-bar counter and listening to SLTS / Everlong (Spotify-prepared), the visual "1" does not land on the song's actual perceived downbeat — it lands on what feels like beat 2 or beat 3 of the bar.
**Resolved:** 2026-05-07 — two-step fix.

- **BUG-007.4a (`Shift+B` manual rotation, landed earlier today)**: developer-only keybind that cycles `barPhaseOffset` 0..(beatsPerBar−1). Resets on track change. Confirmed in session `T18-21-37Z` that rotation works as designed.
- **BUG-007.4b (auto-rotate via kick density)**: after `matchedOnsets >= 8` (lock has stabilised), the tracker examines per-slot kick-onset histogram in `slotOnsetCounts` and rotates `_barPhaseOffset` so the dominant slot (where kicks land most often) becomes the displayed "1". One-shot per track. Suppressed if user pressed `Shift+B` first (manual intent wins). No-op if no clear winner — leading slot must have ≥ 4 onsets *and* ≥ 1.5× the runner-up's count. Four-on-the-floor electronic (OMT) has equal kick density on all slots → no rotation, manual `Shift+B` remains the fallback. Tracks with kick on a single dominant slot auto-rotate within 4–8 seconds of lock acquisition.

- **BUG-007.4c (kick-on-1+3 alternating pattern, 2026-05-07)**: BUG-007.4b's 1.5× ratio gate rejected the most common rock/hip-hop pattern — kick on 1 *and* 3 with similar densities. Session `T21-35-22Z` showed the user still pressing `Shift+B` "a bunch" because counts ended up like `[4, 0, 4, 0]` (top:runner = 1.0). BUG-007.4c adds a second detection path: if top and runner-up are within 1.25× of each other AND the other slots sum to ≤ 20 % of the top, the alternating pattern is recognised and the slot matching `firstTightOnsetRawSlot` (typically the song's downbeat — first kick after track start) wins the tiebreak. Falls back to dominant if first-onset doesn't match either leader.

Variance ring + slot histogram + auto-rotate flags + first-onset-slot all reset on `setGrid` so each track starts fresh.

**Confirmed root cause (2026-05-07, after 5-track diagnostic A/B):** Spotify preview URLs return a 30-second clip from somewhere in the song — *often the chorus, not the first 30 seconds*. Beat This! analyzes the clip, builds a grid, and labels the first beat in the clip as "beat 1 of bar 1." That beat in the clip is typically beat 2, 3, or 4 of the original song's bar. When playback starts from the song's beginning and we install the grid with `offsetBy(0)`, the clip's "beat 1" maps to playback time 0 — but the song's actual beat 1 of bar 1 is at playback time 0. The two don't agree. Result: bar-phase rotation per track, depending on where in the bar Spotify's clip happens to begin.

This is **not** a flaw in Beat This!'s downbeat detection — Beat This! is correctly identifying the bar phase *of the clip*. The mismatch is between the clip's coordinate system and the live-playback song coordinate system.

**5-track A/B evidence (sessions `2026-05-07T15-50-23Z` + `2026-05-07T15-58-17Z`):**

| Track | Visual "1" lands on song's | Off by | Spotify preview likely from |
|---|---|---|---|
| One More Time (Daft Punk) | beat 4 | +3 | chorus mid-bar |
| Midnight City (M83) | beat 4 | +3 | chorus mid-bar |
| HUMBLE. (Kendrick) | beat 3 | +2 | chorus / verse mid-bar |
| SLTS (Nirvana) | beat 1 ✓ | 0 | first 30 s (intro) |
| Everlong (Foo Fighters) | beat 3 | +2 | chorus / verse mid-bar |

The varying off-by-N (0, 2, 3) per track rules out a constant pipeline rotation bug. SLTS being the only one that worked correlates with SLTS's preview being the song intro (less commercial tracks tend to preview from start; popular dance/pop tracks preview from chorus).

**Expected behavior:** On a 4/4 prepared-cache track, the SpectralCartograph beat-in-bar counter shows "1" exactly when the song's bar starts (the kick drum + accent that listeners hear as the downbeat). For SLTS, that's the kick on the strong beat after each pickup. For Everlong, the same. `is_downbeat=1` rows in `features.csv` should land at song-relative times that match the ear's perception.

**Actual behavior:** User reports visual "1" lands 2–3 beats away from the audio's perceived "1" on at least SLTS and Everlong (planned, prepared cache, drift CSV near zero). Drift `mean ≈ +2.5 ms` on SLTS and lock state holds steady — beat-phase alignment is correct. Bar-phase / downbeat selection appears to be the variable.

**Reproduction steps:**
1. Spotify-prepared session containing SLTS + Everlong.
2. Switch to SpectralCartograph (`Shift+→`); press `L` to lock the diagnostic preset.
3. Play SLTS. Watch the beat-in-bar text readout and the BR-panel BAR-φ row.
4. Listen for the song's perceived downbeats and count along.
5. Observe whether "1" on the visual matches the ear's "1".

**Minimum reproducer:** Any Spotify-prepared session on a 4/4 rock track where the user can mentally count beats. SLTS, Everlong are confirmed. May not affect electronic / four-on-the-floor tracks where every beat is a downbeat-feel.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-07T14-28-40Z/features.csv` — SLTS first observed `is_downbeat=1` at `playback_time=42.96` (during locked window). Earlier downbeats during locking phase. BPM=117.6 → bar period 2.04 s. Observed downbeat distribution across 4 beat-in-bar values is roughly uniform (1461 / 1462 / 1412 / 1442 frames each), consistent with the meter being identified correctly but the *rotation* (which beat is "1") possibly off.
- `2026-05-07T14-33-47Z/features.csv` — reactive Everlong got `meter=2/X` from a half-time grid (`bpm=85.4`) — that's BUG-009, separate from this bug.

**Confirmed failure class:** `calibration` (Spotify clip start-position not on song bar boundary; Beat This! is correctly identifying bar phase *of the clip*, but the clip's bar phase doesn't equal the song's bar phase from start).

**Fix scope (three options, ranked by leverage):**

**(C) — Developer rotation shortcut (FIRST: ship as BUG-007.4a, ~1 hour).** Add `Shift+B` to `PlaybackShortcutRegistry` to cycle `barPhaseOffset` between 0..N-1 (where N = `beatsPerBar`). Apply offset when computing `beat_in_bar` and `barPhase01` for the SpectralCartograph readouts. Does not fix anything automatically — but lets the user confirm the rotation hypothesis in seconds (cycle Shift+B until "1" lands on the audio's downbeat) and provides an escape hatch for the long-tail tracks the auto-fix won't catch. Cheap, fully reversible.

**(A) — Auto-rotate via kick-density heuristic (durable fix; BUG-007.4b, ~80 LOC + tests).** After the grid is installed and the drift tracker has 8+ matched onsets, examine which of the N beat-in-bar slots has the highest kick energy on average. That slot is the actual song downbeat. Rotate `beat_in_bar` numbering accordingly. Doesn't require Spotify metadata; works on prepared and live grids equally; converges in ~5–10 seconds. Beat This! identifies *meter* (correctly); the heuristic identifies *which beat in that meter is "1"*.

**(B) — Pre-rotate at preparation time (alternative to A).** Run the kick-density heuristic on the cached 30-second preview audio at preparation time, before the grid is stored in `StemCache`. Faster lock-in (no live convergence period), but requires re-running an onset detector on the cached audio. Higher complexity; defer unless (A)'s convergence delay is unacceptable.

**Recommended sequence:** (C) first to confirm theory in <1 hour. Then (A) as the durable fix. (B) deferred unless needed. **Both (C) and (A) landed 2026-05-07.**

**Out of scope:**
- Reactive-mode downbeat detection — different code path; live grids will benefit from (A) automatically since the same heuristic applies post-install.
- Time-displacement (visual ahead of / behind audio in absolute time). Drift CSV shows beats are aligned. This bug is about *which* beat gets labelled "1", not about *when* beats fire.
- Asking Spotify for clip-start-time-in-song metadata — not exposed by their API.

**Verification criteria:**
- [ ] (C) lands: `Shift+B` cycles bar-phase offset; visual "1" can be aligned to song's "1" on all 5 test tracks within 0..3 presses. Toast/log confirms current offset.
- [ ] (A) lands: visual "1" lands on song's "1" automatically within 10 s of lock-in on OMT, Midnight City, HUMBLE, SLTS, Everlong. No regression on SLTS.
- [ ] On a fully ambient / non-metric track (no obvious kick density per slot): system gracefully holds the Beat This! choice rather than picking a random slot.

**Related:** BUG-008 (offline BPM disagreement — orthogonal), BUG-007 / 007.2 (lock hysteresis — orthogonal), BUG-007.3 (reverted, `78ade5aa`), BUG-007.5 (separately confirmed by Everlong "pulse slightly off" observation in 2026-05-07T15-58-17Z).

---

### BUG-007.6 — Tap-vs-output audio latency calibration

**Severity:** P2 (visible — visual fires before audio is heard, persistent across all tracks).
**Domain tag:** dsp.beat
**Status:** **Resolved (calibration constant + dev shortcut landed 2026-05-07)** — manual validation pending.
**Introduced:** Pre-existing in all prior code; surfaced by the 2026-05-07 5-track A/B (sessions `T15-50-23Z`, `T15-58-17Z`, `T18-21-37Z`) which showed systematic negative drift averaging −36 to −76 ms on every prepared-cache track regardless of BPM. Pattern: tap captures audio L ms before the listener hears it (CoreAudio output buffer + DAC + driver). The tracker's drift converges to roughly −L; the visual orb fires at `pt + drift = pt − L`, before the audio reaches the speaker. User-perceived as "beat in SC feels a little bit faster than the song's actual beat."
**Resolved:** 2026-05-07. New `LiveBeatDriftTracker.audioOutputLatencyMs: Float` (default 0 in engine, set to 50 ms in `VisualizerEngine` app-layer init for internal Mac speakers). Applied to the *display path only* — `displayTime = pt + drift + (audioOutputLatencyMs + visualPhaseOffsetMs) / 1000`. Does NOT touch onset matching or drift estimation: those use unmodified `playbackTime` so the matching path is unchanged. Tunable at runtime via `,` (−5 ms) and `.` (+5 ms) developer shortcuts. Persists across track changes (it's a system property, not a per-track property).

**Expected behavior:** With `audioOutputLatencyMs` calibrated to the platform's actual tap-to-speaker delay, the visual orb pulses in sync with the kick the listener hears.

**Actual behavior (pre-fix):** Visual leads audio by ~50 ms on internal Mac speakers (typical CoreAudio output buffer). Up to several hundred ms on Bluetooth/AirPlay output devices.

**Reproduction steps:**
1. Spotify-prepared session, internal Mac speakers, any track that locks reliably (SLTS, OMT).
2. Watch the SpectralCartograph beat orb while listening.
3. Pre-fix: orb pulses just before each audible kick.

**Confirmed failure class:** `calibration`.

**Diagnosis notes:**
- Tap captures pre-output-buffer audio. The audio then takes ~10–50 ms (internal Mac speaker), 100–300 ms (Bluetooth), 500–1500 ms (AirPlay) to reach the listener's ears.
- Onset detection in our pipeline also has some processing delay (~50 ms FFT-window center bias). The combined effect of *output latency* + *detection delay* is what the user perceives. The single calibration constant `audioOutputLatencyMs` collapses both into one knob.
- Applying compensation to *matching* (shifting `pt` before grid lookup) cancels itself out on the display side — `pt + drift` is invariant under shifts of `pt`. So compensation must go on display.
- The diagnostic drift readout in SpectralCartograph remains at its raw negative value (e.g. −50 ms) — that's accurate; it represents detection delay, not perceptual sync. Visual sync is fixed by display-side compensation.

**Verification criteria:**
- [x] Automated: drift convergence is identical with `audioOutputLatencyMs=0` and `audioOutputLatencyMs=50` on the same input (matching path unaffected). Verified by `audioOutputLatencyMs_shiftsDisplayNotMatching`.
- [x] Automated: at the same playback time, `beatPhase01` differs by L/period between latency=0 and latency=L. Verified by the same test.
- [x] Automated: setter clamps to ±500 ms. Verified by `audioOutputLatencyMs_setter_clampsToRange`.
- [x] Automated: persists across `setGrid` and `reset` (system property). Verified by `audioOutputLatencyMs_persistsAcrossSetGrid`.
- [ ] Manual: SpectralCartograph beat orb pulses in audible sync with kick on SLTS, OMT, Midnight City, HUMBLE, Everlong using internal Mac speakers and the default 50 ms calibration.
- [ ] Manual: `,` / `.` shortcuts adjust visual sync ±5 ms per press; user can dial in a per-output-device offset within 1–2 minutes.

**Out of scope:**
- Persisting `audioOutputLatencyMs` across app launches (currently resets on cold start). Will be a settings-panel field in a future increment.
- Per-output-device automatic detection (Bluetooth vs internal). Future increment if needed.
- Variance-adaptive lock-window logic — that's BUG-007.5.

**Related:** BUG-007.3 (reverted), BUG-007.4 (orthogonal — bar phase rotation), BUG-007.5 (orthogonal — lock-release timing), the existing `visualPhaseOffsetMs` (`[`/`]` shortcut, ±10 ms) which is now additive with this constant on the display path.

---

### BUG-007.5 — Lock hysteresis for asymmetric drift envelopes

**Severity:** P3 (cosmetic — visual flicker between LOCKED and LOCKING; doesn't affect beat-phase)
**Domain tag:** dsp.beat
**Status:** **Resolved (parts 1 + 2 + 3, 2026-05-07)** — manual validation pending.
**Introduced:** Surfaced 2026-05-07. Pre-exists BUG-007.3 (the reverted attempt). The fixed-window Schmitt hysteresis (`staleMatchWindow=0.060` in commit `94309858`) attempted this and failed because the "right" stale window depends on the drift variance, which differs by track.
**Resolved:** 2026-05-07 — Two-part fix.

**Part 1 (time-based release gate)**: Replaced the count-based `lockReleaseMisses=7` gate with a *time-based* `lockReleaseTimeSeconds=2.5` gate. Lock now drops when 2.5 s of consecutive non-tight matches have elapsed since the last tight hit, regardless of how many onsets occurred in between. Sparse-onset tracks (HUMBLE half-time at 76 BPM = 790 ms beat period) no longer trip the gate accidentally — what matters is the elapsed time, not the count. Diagnostic counter `consecutiveMisses` retained on `LiveBeatDriftTraceEntry` for backward compat.

**Part 2 (variance-adaptive tight gate)**: Replaced the fixed ±30 ms tight-match window during the *retention* phase (after lock acquired) with an adaptive `effectiveTightWindow = clamp(2σ, 30 ms, 80 ms)` derived from the running stddev of the last 16 `instantDrift − drift` values. Acquisition path still uses the fixed 30 ms floor for selectivity. This closes the remaining lock-flicker on tracks where drift envelope is wider than ±30 ms despite small EMA bias (Midnight City: drift envelope ±20 ms with σ ≈ 12 ms → adaptive window ≈ 24 ms; HUMBLE: σ ≈ 25 ms → adaptive window ≈ 50 ms; B.O.B. polyrhythmic noise: σ ≈ 40 ms → adaptive window clamped at ceiling 80 ms).

Variance ring resets on `setGrid` / `reset` so each track starts fresh at the floor.

**Part 3 (BPM-aware time gate, landed same day)**: replaced the fixed 2.5 s `lockReleaseTimeSeconds` with `effectiveLockReleaseSeconds = max(2.5 s, 4 × medianBeatPeriod)`. At 120+ BPM the gate stays at the 2.5 s floor (4 × 0.5 = 2.0 s, below floor). At HUMBLE half-time (76 BPM, 790 ms period) the gate scales to 3.16 s — accommodates 4 consecutive sparse non-tight events without dropping lock. At 60 BPM (period 1.0 s) the gate reaches 4.0 s. This closes the failure mode where HUMBLE drops lock every ~5 seconds despite small per-onset deviations from the EMA — the issue was sparse onsets accumulating to 2.5 s before a tight match arrived.

**Expected behavior:** Once `lock_state` reaches LOCKED on a track with correct grid BPM, it stays there for the duration of the song unless the input goes silent or the BPM is genuinely wrong. Lock should not flicker due to per-onset noise within ±60 ms of the EMA.

**Actual behavior (on Everlong planned, prepared, BPM=157.8):** Drift envelope spans −68 to +25 ms with EMA settling at −41 ms. Many individual onsets fall 50–80 ms from the EMA — outside the fixed ±60 ms gate that BUG-007.3 attempted. Lock drops 14 times in 75 s (sessions `2026-05-07T14-28-40Z`). On SLTS planned (drift envelope ~ ±50 ms with EMA near zero) the same fixed gate worked: only 2 drops in 105 s. The variance is the variable; a one-size-fits-all stale window doesn't fit both.

**Reproduction steps:** Play Everlong from a Spotify-prepared session, watch the SpectralCartograph mode label flicker between `● PLANNED · LOCKED` and `◑ PLANNED · LOCKING` while the beat orb continues to pulse on the kick (beat-phase alignment is fine; only the lock indicator flickers).

**Minimum reproducer:** Any rock track with a dense, slightly-rushed snare-and-cymbal pattern at 150+ BPM. Everlong is the gold reference.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-07T14-28-40Z/features.csv` — Everlong rows at BPM=157.8: 14 lock drops, drift min/max −68 / +25, drift mean −41 ms.

**Suspected failure class:** `algorithm`.

**Diagnosis notes:**
- BUG-007.3's premise that ±60 ms covers natural tempo variation was correct on SLTS but wrong on Everlong. SLTS's drift std-dev over a 10 s window is roughly half Everlong's.
- Adaptive approach: track the running std-dev of `instantDrift` over the last N onsets. Define `staleMatchWindow = clamp(K × stddev, 30 ms, 120 ms)`. K ≈ 2 sigma. This auto-widens for noisy material and stays tight for clean material.
- Alternative: track per-onset variance via Welford's algorithm (no allocation, lock-friendly).

**Verification criteria:**
- [ ] On Everlong planned: ≤ 1 lock drop in 50 s of continuous playback.
- [ ] On SLTS planned: no regression — still ≤ 2 drops in 100 s.
- [ ] On Billie Jean reactive (control): no regression.
- [ ] Automated regression test: synthetic input with 60 ms-stddev jitter at 158 BPM should hold lock for 60 s with ≤ 1 drop.

**Fix scope (~30 LOC + tests):**
1. Add a small running-variance accumulator on per-onset `instantDrift` values to `LiveBeatDriftTracker` (Welford's online variance, ring of last 16 onsets).
2. Compute `staleMatchWindow = clamp(2.0 × stddev, 30 ms, 120 ms)` per onset.
3. Apply the same Schmitt branching as BUG-007.3's Part (a), but with the dynamic gate.

**Out of scope:**
- Replacing `strictMatchWindow` (acquisition selectivity unchanged).
- Touching the slope-detector / wider-window-retry idea from BUG-007.3 Part (b). That belongs to a *future* increment if BUG-009 doesn't subsume it.

**Related:** BUG-007.3 (reverted attempt — fixed gate). BUG-007.4 (downbeat alignment — orthogonal).

---

### BUG-009 — Halving-correction threshold (160 BPM) too aggressive; halves legitimate fast tempos

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** **Resolved 2026-05-07** — threshold raised 160 → 175 in `BeatGrid.halvingOctaveCorrected()`. New regression test `halvingOctaveCorrected_fastRockBPM_isNoOp` covers four fixtures (158 / 168 / 172.5 / 175 BPM) and confirms each passes through unchanged. Existing tests updated for the new boundary; the extreme-double-halve fixture moved from 322 → 360 BPM to retain factor-4 thinning coverage. **Manual validation pending** — next reactive Everlong session should install at `bpm=158 ± 8` (not the pre-fix 85.4 half-time alias).
**Introduced:** DSP.3.5 (2026-05-05). `BeatGrid.halvingOctaveCorrected()` halves any BPM > 160 to the nearest sub-160 value. Threshold chosen at 160 because most pop / rock / electronic music falls below it. Surfaced 2026-05-07 when reactive Everlong (true ≈158 BPM) received a Beat This! raw output > 160, triggering halving down to 85.4 BPM — visibly wrong.

**Expected behavior:** A track with true tempo in [160, 200] BPM (drum'n'bass, fast metal, jungle, fast electronic, "Everlong"-class rock) gets a grid at its true tempo, not the half-time alias. Halving should fire only when the raw analyser output is more than ~10–15 % above the genuine perceptual tempo — i.e. for true double-time errors.

**Actual behavior:** Threshold is fixed at 160 BPM. Beat This! `small0` outputs ranging 165–180 on tracks with true tempo near 158 (off by < 15 %) get halved unconditionally. Result: half-time grid; visual orb pulses at half rate; bar-phase wrong; user listens to a song at 158 BPM but sees animation at 85.

**Reproduction steps:**
1. Reactive (ad-hoc) session, no Spotify preparation.
2. Play Everlong (Foo Fighters).
3. Wait for live grid install at ~10 s.
4. Read `session.log`: `BeatGrid installed: source=liveAnalysis, ..., bpm=85.4, beats=443, meter=2/X`.

**Minimum reproducer:** Any track with true BPM in roughly [160, 175] played in a reactive session. Everlong is the canonical case.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-07T14-33-47Z/session.log` — `bpm=85.4, beats=443, meter=2/X` on Everlong reactive. True ~158 BPM.

**Suspected failure class:** `calibration`.

**Diagnosis notes:**
- 160 BPM is below typical drum'n'bass (170–175), fast metal (180+), and fast indie rock (Foo Fighters, Strokes, Arctic Monkeys typically 155–170). The threshold was chosen for a 30 s offline window where Beat This! is more accurate; the live 10 s window is noisier and pushes more legitimate tracks above 160.
- Two candidate fixes:
  - (a) Raise threshold to 175 (or 180). Captures most fast-rock without re-enabling true-double-time errors. Risk: doesn't catch an actual 90 BPM track that Beat This! reports as 180.
  - (b) Use BPM confidence from the grid output (number of beats supporting the BPM, drift slope, etc.) rather than a hard threshold. Heavier; would land in a follow-up.
- Pyramid Song (true ≈68 BPM) must stay un-corrected — already protected by BPM > 160 condition. (a) preserves this.

**Verification criteria:**
- [ ] On Everlong reactive: live grid installs at `bpm=158 ± 8` (within ±5 %).
- [ ] On Pyramid Song (true 68 BPM): grid stays at 68 BPM, not 136.
- [ ] On Money 7/4 (~123 BPM): no regression.
- [ ] On a confirmed-double-time test track (synthetic 80 BPM that triggers Beat This! to output 160+): halving still fires. Find or synthesize a fixture for this.

**Fix scope (likely ~5 LOC + test):** raise threshold to 175 in `BeatGrid.halvingOctaveCorrected()`. Add regression test on a 158 BPM input that confirms no halving fires (currently halves; post-fix doesn't).

**Out of scope:**
- BPM-confidence-aware correction (option b above). Defer to future work if option (a) leaves residual bad cases.
- Doubling correction for sub-80 BPM tracks (already disabled by design — Pyramid Song would break).

**Related:** DSP.3.5 (introduced halving correction); BUG-008 (offline BPM disagreement — orthogonal). BUG-007.3 (reverted; surfaced this issue but didn't address it).

---

### BUG-007.3 — Lock hysteresis still oscillates on drift-prone tracks; live BPM resolver fragile on busy mid-frequency content

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** Closed (attempt reverted — see commit `78ade5aa`). Replaced by BUG-007.4 + BUG-007.5 + BUG-009.
**Introduced:** Surfaced 2026-05-07 during manual validation of two sessions captured post-QR.2 (`~/Documents/phosphene_sessions/2026-05-07T13-27-14Z/` planned, `~/Documents/phosphene_sessions/2026-05-07T13-30-46Z/` reactive). Predates QR.2 (QR.2 did not change drift-tracker semantics). BUG-007.2 widened `lockReleaseMisses` 3 → 7, which closed the 30 s freeze + the 400 ms/487 ms adversarial scenario but left two additional failure modes.
**Reverted:** 2026-05-07. The Schmitt hysteresis (Part a) + drift-slope retry (Part b) implementation in commit `94309858` was reverted in commit `78ade5aa` after manual validation evidence (`2026-05-07T14-28-40Z` + `T14-33-47Z`) showed Everlong planned regressed (14 lock drops vs 5 pre-fix). The fix's premise — that wider stale-OK retention would close natural-tempo-variation drops — held on SLTS but not on Everlong, where the drift envelope is asymmetric around its EMA (−68 to +25 ms with avg −41 ms) and many onsets land outside ±60 ms of the EMA. Net: the fix improved one track and worsened another. User also observed downbeat misalignment ("1" not on song's downbeat) which drift CSV cannot rule in or out — beat phase was correct (drift ≈ 0 on SLTS) but bar-phase / downbeat selection may be wrong. Three follow-up bugs scoped (BUG-007.4 / 007.5 / 009).

**Expected behavior:** On any track where the offline/live BPM is within ±1 % of true tempo, `lock_state` reaches `2` (LOCKED) and stays there for the duration of the track, with `drift_ms` settling into a band whose `stddev` over a 10 s window is below ~25 ms. On busy mid-frequency tracks (rock, power chords) where the live 10 s window is insufficient, the system either widens its analysis window or surfaces a warning, but does not silently lock to a 4 % wrong BPM.

**Actual behavior:** Two distinct mechanisms.

- **Mechanism C — natural-music tempo variation drops lock under correct BPM.** Smells Like Teen Spirit (planned, prepared cache, `grid_bpm=117.6`, true ≈117) held lock for 80 s straight but `drift_ms` walked from +15 → −90 over 90 s. Everlong (planned, prepared, `grid_bpm=157.8`) dropped lock 5 times in 50 s with drift in the −30 to −68 ms band, even though BPM was correct. The drops were caused by individual onsets falling outside `abs(instantDrift − drift) < strictMatchWindow=30 ms` for ≥ 7 consecutive onsets. At ≈158 BPM that is a 2.7 s window, and noisy onsets (harmonics, reverb tail, snare bleed) cluster easily. The 30 ms tight-match gate is too strict for the natural micro-timing variation of real performances.

- **Mechanism D — live BPM resolver returns 4 % low on busy mid-frequency content.** Reactive Everlong gave `grid_bpm=151.9` (true ≈158, 3.86 % low). Drift went from 0 → −358 ms over 75 s — roughly one full beat. Billie Jean (synth pop, kick on the beat) gave `grid_bpm=117.1` (true ≈117) and drift stayed bounded ±90 ms. The 10 s live window at busy power-chord-guitar onset density does not give Beat This! enough evidence to nail the BPM within 1 %.

**Reproduction steps:**
1. Start a Spotify-prepared session containing Smells Like Teen Spirit and Everlong.
2. Play SLTS → Everlong while Phosphene runs.
3. Observe: `lock_state` reaches 2 on both, but Everlong drops 5+ times; both walk negative drift.
4. Then start an ad-hoc (reactive) session and play Everlong.
5. Observe: `grid_bpm=151.9`, drift goes to −358 ms by ~75 s.

**Minimum reproducer:**
- Mechanism C: any prepared-cache session on a track with natural human tempo variation > 0.3 % over 60 s. SLTS, Everlong, and most rock/indie material qualify.
- Mechanism D: any reactive session on Everlong (or comparable busy mid-frequency content). Quiet-intro tracks (SLTS) recover via the 20 s retry path; high-onset-density tracks do not.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-07T13-27-14Z/features.csv` — SLTS held LOCKED 4806 frames (80 s); Everlong dropped 5 times. Drift slopes documented in chat analysis 2026-05-07.
- `~/Documents/phosphene_sessions/2026-05-07T13-30-46Z/features.csv` — Reactive Everlong drift 0 → −358 ms over 75 s; reactive Billie Jean drift bounded ±90 ms (control case).

**Confirmed failure class:** `algorithm` (Mechanism C — over-strict tight-match gate without asymmetric hysteresis) + `calibration` (Mechanism D — 10 s live window insufficient for busy mid-freq onset density).

**Diagnosis notes:**
- Mechanism C is *not* solved by raising `lockReleaseMisses` further. With the gate already at 7, raising it to 12 just delays inevitable drops on tracks with > 7-onset stretches of natural micro-timing variation. The fix is asymmetric hysteresis: keep the 30 ms gate for *entering* lock (selectivity), use a wider gate (e.g. 60 ms) for *staying* locked (stickiness). This is the standard Schmitt-trigger pattern.
- Mechanism D cannot be solved by lock hysteresis at all — the BPM itself is wrong. The fix is at the resolver layer: wider live window (10 s → 20 s) on retry, and a drift-slope detector that re-triggers live analysis when sustained drift slope exceeds a threshold for ≥ 10 s.
- Drift sign is consistently negative across all tracks, suggesting a small constant tap-output latency contribution (~10–15 ms) on top of any BPM error. Not addressed by this bug — would be a separate calibration constant if pursued.

**Verification criteria:**
- [ ] On SLTS planned (prepared cache, BPM=117.6): `lock_state == 2` for ≥ 95 % of frames after first lock; `stddev(drift_ms over 10 s window) < 25 ms`.
- [ ] On Everlong planned (prepared cache, BPM=157.8): ≤ 1 lock drop in 50 s of continuous playback.
- [ ] On Everlong reactive: either grid BPM converges to within ±1 % of 158 within 30 s of playback (via wider retry window), or `WARN: live BPM credibility low` is logged and the system stays in LOCKING rather than locking to a wrong grid.
- [ ] On Billie Jean reactive (control): no regression — drift stays bounded ±90 ms, lock holds.
- [ ] Automated: a deterministic regression test in `LiveBeatDriftTrackerTests` simulating an outlier-onset stream within a 30 ms-EMA-correct grid demonstrates Mechanism C is closed (≤ 1 lock drop per 60 s of synthetic input where current code drops ≥ 4).
- [ ] Manual: drift readout in SpectralCartograph stays close to zero on SLTS and Everlong (planned). Beat orb pulse sits exactly on the kick across both tracks.

**Fix scope (BUG-007.3 — one increment, two parts):**

**Part (a) — Asymmetric Schmitt-style hysteresis (small, ~15 LOC + tests).** In `LiveBeatDriftTracker.swift`:

```swift
// New constant:
private static let staleMatchWindow: Double = 0.060   // ±60 ms — once locked, stay locked

// In update(), replace the single isTight gate with:
let isTight = abs(instantDrift - drift) < Self.strictMatchWindow
let isStaleOK = abs(instantDrift - drift) < Self.staleMatchWindow
let alreadyLocked = (matchedOnsets >= Self.lockThreshold) && (consecutiveMisses < Self.lockReleaseMisses)

if isTight {
    matchedOnsets = min(matchedOnsets + 1, Int.max - 1)
    consecutiveMisses = 0
} else if alreadyLocked && isStaleOK {
    // While locked, a "stale-OK" onset doesn't increment matchedOnsets but
    // also doesn't increment consecutiveMisses — preserves lock under natural
    // tempo variation without making lock easier to acquire initially.
    // matchedOnsets unchanged
} else {
    consecutiveMisses += 1
}
```

This keeps lock-acquisition selectivity (still need 4 ±30 ms hits) but raises lock-retention stickiness to ±60 ms.

**Part (b) — Live-BPM credibility gate + retry with wider window (medium, ~50 LOC + tests).** Two pieces:

1. **Drift-slope detector** in `LiveBeatDriftTracker`: maintain a small ring of `(playbackTime, drift)` samples (~30 entries, ~3 s at 10 Hz onset rate). Expose `currentDriftSlope() -> Double?` returning ms/sec when ≥ 5 samples cover ≥ 5 s; nil otherwise. Called from `MIRPipeline.buildFeatureVector` once per frame; result published on a new `latestDriftSlope` property.

2. **Retry trigger** in `VisualizerEngine+Stems.runLiveBeatAnalysisIfNeeded()`: in addition to the existing two-attempt schedule (10 s, 20 s on empty grid), add a third condition — if `liveDriftTracker.hasGrid && abs(currentDriftSlope) > 5.0 ms/sec` sustained for ≥ 10 s, and at least 30 s have passed since the last attempt, trigger a re-analysis with a 20 s window (vs the standard 10 s). Cap retries at 3 per track. Log `WARN: live BPM credibility low (slope=Xms/s) — retrying with 20 s window`.

If the wider window also produces an out-of-band BPM estimate (slope still > 5 ms/sec after the retry), log `WARN: live BPM unstable on this track` and *retain the previous grid* rather than installing a new wrong one — better to keep visuals close-but-drifting than to thrash through three different wrong grids.

**Out of scope for this increment:**
- Fixing the consistent ~10–15 ms negative-drift offset (likely tap-output latency calibration). Tracked separately if pursued.
- Replacing the offline Beat This! resolver (BUG-008 — independent).
- Changes to `strictMatchWindow` itself. Selectivity at acquisition time stays at ±30 ms.

**Estimated effort:** 1 day. Part (a) is ~half a day including the deterministic regression test; part (b) is ~half a day including the 20 s window retry path and the slope-detector unit test.

**Related:** BUG-007.2 (resolved upstream — covers Mechanism A + B; this bug covers Mechanisms C + D), BUG-008 (offline BPM disagreement — independent), DSP.3.4 (sample-rate fix on live path), DSP.3.5 (octave correction + retry — already established the multi-attempt pattern this fix extends), QR.1 (touched the file but did not change lock semantics).

---

### BUG-003 — DSP.3.6 / DSP.3.7 tests not yet implemented

**Severity:** P3
**Domain tag:** dsp.beat
**Status:** Resolved
**Introduced:** DSP.3 planning (gap in coverage)
**Resolved:** 2026-05-07 by QR.3 (`LiveDriftValidationTests.swift` lands the DSP.3.7 surface; DSP.3.6 was previously closed by `PreparedBeatGridAppLayerWiringTests`, BUG-006.2).

**Expected behavior:** App-layer wiring integration test verifies the full chain `SessionPreparer.prepare() → StemCache.store() → resetStemPipeline(for:) → mirPipeline.liveDriftTracker.hasGrid == true`. Live drift validation replay test verifies LOCKED within 5 s, drift < 50 ms, and beat phase zero-crossings within ±30 ms on Love Rehab.

**Actual behavior:** These tests do not exist. The wiring is tested indirectly via DSP.2 S6 integration tests, but the app-layer chain from session preparation through to drift tracker activation is not explicitly asserted.

**Minimum reproducer:** Review `docs/ENGINEERING_PLAN.md` DSP.3.6 and DSP.3.7 status.

**Session artifacts:** n/a

**Suspected failure class:** documentation-drift (gap in test coverage, not a behavioral bug)

**Verification criteria:**
- [x] DSP.3.6 test file exists and passes: `swift test --filter BeatGridAppLayerWiringTests` — landed as `PreparedBeatGridAppLayerWiringTests` (BUG-006.2, 2026-05-06). Six cases, all pass.
- [x] DSP.3.7 test file exists and passes: `swift test --filter LiveDriftValidation` — landed as `LiveDriftValidationTests` (QR.3, 2026-05-07). Drives the production tracker against love_rehab.m4a; observed lock at 6.55 s, max drift 14 ms, alignment 90 %.

**Fix scope:** Two new test files in `Tests/Integration/`. No production code changes anticipated. Both landed.

**Related:** DSP.3.6, DSP.3.7, QR.3, D-090.

### BUG-006 — Spotify-prepared session does not install prepared BeatGrid (falls through to liveAnalysis)

**Severity:** P1
**Domain tag:** dsp.beat
**Status:** Resolved (wiring — downstream BUG-007 / BUG-008 prevent full LOCKED but the prepared-grid path itself is wired correctly end-to-end)
**Introduced:** Unknown — first observed during QR.1 manual validation 2026-05-06; predates QR.1 (QR.1 did not touch the prepared-grid wiring path).
**Resolved:** 2026-05-06 (BUG-006.2, wiring path validated end-to-end via session capture `2026-05-06T20-11-46Z`. Two downstream issues — BUG-007 lock-hysteresis, BUG-008 offline BPM accuracy — prevent SpectralCartograph from reaching `● PLANNED · LOCKED` but are independent of BUG-006 and tracked separately).

**Expected behavior:** When a Spotify playlist is loaded and `SessionPreparer` completes preparation, each track's `CachedTrackData.beatGrid` is non-empty. On track change in playback, `resetStemPipeline(for: identity)` finds the cache entry and emits `BEAT_GRID_INSTALL: source=preparedCache, track=…, bpm=…, beats=…` to `session.log`. SpectralCartograph displays `◐ PLANNED · UNLOCKED` immediately on first audio, then advances to `● PLANNED · LOCKED` within the first bar or two.

**Actual behavior:** SpectralCartograph mode label stays at `○ REACTIVE` for the entire opening of the track. `session.log` contains zero `source=preparedCache` install entries. Eventually `BEAT_GRID_INSTALL: source=liveAnalysis` fires once the live Beat This! trigger reaches its 10 s window — but only because the prepared cache returned nil and the live fallback was permitted. The mode label only advances past `REACTIVE` after the live grid lands.

**Reproduction steps:**
1. Launch Phosphene fresh.
2. Connect a Spotify playlist that includes Love Rehab (Chaim).
3. Wait for `.ready`. Press play in Spotify.
4. Press `Shift+→` to advance to Spectral Cartograph.
5. Watch the mode label and `~/Documents/phosphene_sessions/<latest>/session.log`.

**Minimum reproducer:** Any Spotify playlist on a fresh launch.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-06T14-14-22Z/session.log` — zero `source=preparedCache` entries; first `source=liveAnalysis` entry at `14:16:58Z` for Pyramid Song (~2 minutes after `track → Love Rehab`).
- `features.csv` from the same session — `lock_state` and `grid_bpm` columns presumably zero throughout the early playback window.

**Suspected failure class:** `pipeline-wiring`

**Evidence:**
- `VisualizerEngine+InitHelpers.swift:85–98` correctly wires `DefaultBeatGridAnalyzer` into `SessionPreparer`.
- `VisualizerEngine+Stems.swift:354 resetStemPipeline(for:)` correctly checks `stemCache?.loadForPlayback(track: identity)` and logs both branches (`source=preparedCache` on hit, `source=none` on miss).
- The session log shows neither branch fired for Love Rehab, which means `resetStemPipeline(for:)` was not called for the track *or* the `stemCache` was nil at the call site.
- DSP.3.1/3.2 added a pre-fire call to `resetStemPipeline(for: plan.tracks.first?.track)` at the end of `_buildPlan()` (D-078). If `_buildPlan()` did not run, this pre-fire never happened. Hypothesis: planned-session path is not being entered when Spotify playlist preparation completes, falling through to ad-hoc reactive behaviour despite the user thinking they used the playlist flow.

**Verification criteria:**
- [x] Loading a known-prepared Spotify playlist produces at least one `BEAT_GRID_INSTALL: source=preparedCache` entry in `session.log` per track played. **Confirmed in capture `2026-05-06T20-11-46Z`** — 6 tracks prepared with non-empty grids; 2 tracks played (Love Rehab, Money) and both produced `source=preparedCache` install lines on track-change.
- [ ] On Love Rehab specifically: SpectralCartograph mode label transitions `◐ PLANNED · UNLOCKED → ● PLANNED · LOCKED` within 5 s of audio. **Blocked by BUG-008** (Love Rehab prepared grid is 5.5% slow → drift accumulates beyond search window) and **BUG-007** (lock hysteresis fails even with correct drift).
- [x] `features.csv` `grid_bpm` column non-zero from frame 1 of the track. **Confirmed**: Love Rehab `grid_bpm=118.126`, Money `grid_bpm=123.232` — non-zero from frame 1 in `2026-05-06T20-11-46Z` capture. Accuracy issue tracked separately as BUG-008.
- [ ] Manual: drift readout (Δ) settles near zero (±20 ms) within the first bar. **Blocked by BUG-007 + BUG-008.**
- [x] Six new automated regression tests in `PreparedBeatGridAppLayerWiringTests` close the BUG-003 coverage gap that let this ship.

**Resolution (BUG-006.2, 2026-05-06):** Two coordinated fixes. **(Cause 1)** `engine.stemCache` is now wired to `sessionManager.cache` in `VisualizerEngine.init` immediately after `makeSessionManager` returns. Both references point to the same `StemCache` instance — `SessionPreparer` writes fill the cache as preparation completes; the engine reads them on track-change without any explicit hand-off. The field had been declared at `VisualizerEngine.swift:171` since the original session-preparation work but was never assigned anywhere, so `resetStemPipeline(for:)` always took the cache-miss branch. **(Cause 2)** `VisualizerEngine+Capture.swift` now resolves the canonical `TrackIdentity` from `livePlan` via the new `PlannedSession.canonicalIdentity(matchingTitle:artist:)` helper. Streaming metadata (Apple Music / Spotify Now Playing AppleScript) only carries title+artist; the planner stored full identities (duration + spotifyID + spotifyPreviewURL hint). The pure-function helper in the Orchestrator module is testable from `PhospheneEngineTests`. Falls back to the partial identity when `livePlan` is nil (preserving ad-hoc reactive behaviour) or when more than one planned track shares the same title+artist pair (preserves conservative behaviour over the wrong cache hit).

New tests: `PreparedBeatGridAppLayerWiringTests` (6 cases) — `engineStemCache_isWiredAfterSessionPrepare`, `trackChangeIdentity_matchesPlannedIdentity`, `ambiguousMatch_returnsNil_partialFallback`, `noMatch_returnsNil`, `endToEndProduces_preparedCacheInstall`, `partialIdentity_withoutCanonicalResolution_missesCache` (negative control pinning the regression direction). All pass. Full engine suite green modulo two documented pre-existing flakes (`MetadataPreFetcher.fetch_networkTimeout`, `MemoryReporter.residentBytes growth`).

The `WIRING:` instrumentation from BUG-006.1 stays in place — it costs nothing at runtime, validates the fix in any session capture, and will catch future regressions. Removal deferred to QR.5 cleanup once the fix has stabilized across multiple sessions.

**Related:** DSP.3.1, DSP.3.2, DSP.3.6, D-078, BUG-003 (test-coverage gap closed by `PreparedBeatGridAppLayerWiringTests`), BUG-006.1 (instrumentation), BUG-006.2 (this fix), BUG-007 + BUG-008 (downstream issues exposed but not caused by the fix). Commits: BUG-006.1 instrumentation `7f95cec0` + `807d3b8c`; BUG-006.2 fix `982bf93d` + docs `d56acd89`. Manual validation capture: `~/Documents/phosphene_sessions/2026-05-06T20-11-46Z/`.

---

### BUG-007 — LiveBeatDriftTracker loses lock under stable real-music input (LOCKING ↔ LOCKED oscillation)

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** Resolved (BUG-007.2, 2026-05-06)
**Introduced:** Unknown — first observed during QR.1 manual validation 2026-05-06; predates QR.1 (QR.1 did not change drift-tracker lock semantics — only widened `playbackTime` to `Double`).
**Resolved:** 2026-05-06 (BUG-007.2). Fix A: `mirPipeline.setBeatGrid(cached.beatGrid.offsetBy(0))` in `VisualizerEngine+Stems.swift resetStemPipeline(for:)` — eliminates Mechanism B (horizon exhaustion) on all prepared-cache sessions. Fix B: `lockReleaseMisses = 7` (was 3) in `LiveBeatDriftTracker.swift` — eliminates Mechanism A oscillation on cadence-mismatch input; note the implemented value is 7, not the 5 in the diagnosis document, because the deterministic 400 ms/487 ms adversarial test scenario produces exactly-5 consecutive miss runs that trip the threshold at 5 (7 × 400 ms = 2.8 s hysteresis window; well within spec intent). Diagnostic test `test_mechanismB` updated from raw-grid bug-documenter to extrapolated-grid fix-verifier (test setup changed; `#expect` assertion unchanged). Three regression gates in `LiveBeatDriftTrackerTests` (tests 16–18).

**Expected behavior:** Once `LiveBeatDriftTracker.computeLockState()` returns `.locked` (after `matchedOnsets ≥ lockThreshold`), the tracker remains `.locked` for the duration of the track unless the input has gone genuinely silent for ≥ 2 × medianBeatPeriod. Onset-time drift settles into a band ±30 ms wide (the `strictMatchWindow`) and stays there.

**Actual behavior:** Two independent mechanisms prevent lock from holding:

- **Mechanism B (primary — plateau/freeze after ~30 s):** The prepared-cache install path (`resetStemPipeline(for:)`) calls `mirPipeline.setBeatGrid(cached.beatGrid)` without `offsetBy()`. The prepared grid covers only the 30-second Spotify preview. Once `playbackTime` exceeds ~30 s, `nearestBeat()` returns nil for all subsequent onsets. `consecutiveMisses` reaches `lockReleaseMisses=3` after 3 × 400 ms = 1.2 s, lock drops to `.locking`, and never recovers. Drift EMA freezes at its last-update value permanently.

- **Mechanism A (secondary — oscillation in 0..30 s window):** Sub_bass BeatDetector cooldown is 400 ms; Money's beat period is 487 ms. These cadences produce a ~71 % miss rate (44 of 62 onsets in the session capture). With `lockReleaseMisses=3`, 3 consecutive misses (~1.2 s) drop lock; the next hit (~400 ms later) re-acquires. Net: lock oscillates at ~1–2 s frequency throughout the 30-second live window.

**Reproduction steps:**
1. Start a Spotify-prepared session for a playlist containing Money (Pink Floyd).
2. Play Money in Spotify while Phosphene is running.
3. Switch to Spectral Cartograph (`Shift+→`).
4. Observe mode label: oscillates `◑ PLANNED · LOCKING` ↔ `● PLANNED · LOCKED` in 0..30 s, then drops permanently to `◑` after ~30 s.

**Minimum reproducer:** Any Spotify-prepared session where `playbackTime > 30 s`. The 30-second Spotify preview always produces a grid of ~30 s coverage; without `offsetBy()`, every track freezes at ~30 s.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-06T20-11-46Z/` — Money 7/4, prepared grid bpm=123.2.
  - 62 onsets, 18 hits (71 % miss rate).
  - Last match: t=29.8121 s, drift=+14.396 ms.
  - Lock dropped to LOCKING: t=31.0949 s (frame 5459), drift frozen at +14.396 ms permanently.
- Diagnosis document: `docs/diagnostics/BUG-007-diagnosis.md`.
- Diagnostic test suite: `PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/LiveDriftLockHysteresisDiagnosticTests.swift` (gated: `BUG_007_DIAGNOSIS=1`).

**Confirmed failure class:** `api-contract` (BUG-R001 fix applied to live Beat This! path in DSP.3.4 but not to the prepared-cache path) + `algorithm` (lock-hysteresis `lockReleaseMisses=3` too small for 71 % miss-rate input).

**Diagnosis notes:**
- The plateau at −90.490 ms on Love Rehab is the same Mechanism B. Love Rehab's plateau is negative (BUG-008: grid BPM 5.5 % too slow → drift walks negative) rather than positive, but the freeze mechanism is identical.
- Check 2 (sensitivity sweep): widening `strictMatchWindow` from 30 ms to 50 ms would make ~83 %→100 % of the 18 hits count as tight, but does NOT reduce the 71 % nil-return miss rate. Not the fix.
- Check 3 (decay path): inter-onset gap 400 ms < 2 × 487 ms = 974 ms decay threshold → decay path never fires. Not the cause of the plateau.

**Verification criteria:**
- [ ] Once `lock_state` reaches `2` (locked) on a stable track, it stays at `2` for ≥ 30 s of continuous playback at the same tempo. (**Manual validation pending — blocked by BUG-008 on Love Rehab; automated gate passes.**)
- [ ] `drift_ms` values in `features.csv` settle into a ±30 ms band and the standard deviation over a 10-s window is < 15 ms. (**Blocked by BUG-008 on Love Rehab; independent of this fix.**)
- [ ] Manual: orb pulse sits exactly on the kick (not "mostly in time"), and the BR-panel beat-phase tick lines up with the beat orb's flash.
- [x] `BUG_007_DIAGNOSIS=1 swift test --filter test_mechanismB` prints a lock_state of `2` at t=40 s — **passes** (was: `1`).
- [x] `BUG_007_DIAGNOSIS=1 swift test --filter test_mechanismA` prints ≤ 2 oscillations in 60 s — **passes with 0 oscillations** (was: multiple per minute).
- [x] `swift test --filter LiveBeatDriftTrackerTests` — all 18 tests pass.

**Fix scope (BUG-007.2 — one increment):**

Fix A (primary, 1 line — eliminates Mechanism B entirely):
```swift
// In VisualizerEngine+Stems.swift resetStemPipeline(for:), prepared-cache branch:
mirPipeline.setBeatGrid(cached.beatGrid.offsetBy(0))   // was: no offsetBy()
```

Fix B (secondary, 1 line — eliminates Mechanism A oscillation):
```swift
// In LiveBeatDriftTracker.swift:
private static let lockReleaseMisses: Int = 7   // was: 3
```
Note: the diagnosis document stated 5; the implemented value is 7. The deterministic 400 ms/487 ms adversarial regression test produces exactly 5 consecutive miss runs that trip a threshold of 5 on every other cycle; 7 clears the worst-case gap (7 × 400 ms = 2.8 s hysteresis, in line with the spec intent of "multiple non-detections required").

Fix A closes the primary issue on all tracks (prepared-cache sessions, playback > 30 s). Fix B eliminates oscillation on any cadence-mismatch scenario. Both shipped in one increment. Widening `strictMatchWindow` is explicitly NOT needed.

**Related:** DSP.2 S7, DSP.3.4 (fixed the same issue on live path — prepared-cache path missed), D-077, D-079 (touched file but did not change lock semantics), BUG-008 (Love Rehab has an additional BPM-offset symptom on top of this bug). Commits: BUG-007.1 diagnosis `f616bdb1`; BUG-007.2 fix `4fc58bdf` + SwiftLint cleanup `3a5c9a86`.

---

### BUG-008 — Offline BeatGrid disagrees with MIR BPM estimator on some tracks

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** Resolved (BUG-008.2, 2026-05-06) — disagreement is now logged at preparation time. Underlying upstream-model behaviour unchanged by design; neither estimator is mechanically "right" per BUG-008.1 diagnosis.
**Introduced:** Surfaced by BUG-006.2 fix on 2026-05-06; predates BUG-006.2 (the offline analyzer has been producing this output since DSP.2 S5 landed — was previously masked because `engine.stemCache` was never assigned, so the prepared grid was never actually used at runtime). Diagnosis (BUG-008.1) traces the disagreement to genuine musical interpretation differences between the two estimators, *not* to any Phosphene code path.
**Resolved:** 2026-05-06 (BUG-008.2 — `BPMMismatchCheck.swift` + wiring in `SessionPreparer+WiringLogs.swift`. Disagreement now surfaces as a `WARN: BPM mismatch` line in `session.log` whenever the offline grid and MIR estimator differ by more than 3 %. No runtime behaviour change — `LiveBeatDriftTracker` continues to consume the offline grid).

**Expected behavior:** Two BPM estimators run during preparation — `TrackProfile.bpm` (MIR / DSP.1 trimmed-mean IOI on sub_bass kicks) and `CachedTrackData.beatGrid.bpm` (Beat This! transformer). When they disagree by more than 3 %, the disagreement is surfaced in `session.log` so future per-track judgment can be informed by data rather than tags. Phosphene does not assert which estimator is "correct"; both are valid interpretations of the same audio.

**Actual behavior (pre-BUG-008.2):** The disagreement was silent. Love Rehab specifically reports MIR=125.0 / grid=118.1 (5.5 % delta), Beat This! locks to the perceptual beat (broader-spectrum accent integration, what the model was trained to predict on human tap annotations) while the kick-rate IOI estimator locks to the kick interval. Money 7/4 (1.4 %) and Pyramid Song 16/8 (2.86 %) fell within the threshold and would not warn. The `LiveBeatDriftTracker` consumes the offline grid; on Love Rehab specifically this drives `drift_ms` linearly negative against the live tap (which corresponds to the kick rate), pegging at the −90 ms search-window edge by 31 s. **That secondary symptom is BUG-007** — independent and not addressed by this fix.

**Reproduction steps:**
1. Connect a Spotify playlist that includes Love Rehab (Chaim).
2. Wait for `.ready`. Inspect `WIRING: SessionPreparer.beatGrid track='Love Rehab'` in `session.log`.
3. Confirm `bpm=118.1` (or thereabouts — re-check determinism on repeated preparations).
4. Play the track. Observe `features.csv`: `grid_bpm` column reads `118.126`, `drift_ms` walks negative, lock_state never reaches 2 stably.

**Minimum reproducer:** Any Spotify preparation of Love Rehab with the post-BUG-006.2 wiring active.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-06T20-11-46Z/session.log` lines 5–10 — all six tracks' offline BPMs:
  - Blue in Green (true ~70 swing): bpm=56.1
  - Love Rehab (true 125): **bpm=118.1**
  - Mountains: bpm=96.1
  - Pyramid Song (true ~68): bpm=70.0
  - Money (true ~120 in 7/4): bpm=123.2
  - If I Were with Her Now: bpm=103.7
- `features.csv` from the same session — Love Rehab `drift_ms` column walks −20 → −90 → plateau at −90.490 by frame 2398 (31 s in).

**Suspected failure class:** `algorithm` (Beat This! accuracy on this audio file). **Confirmed by BUG-008.1 diagnosis** — `calibration` and `pipeline-wiring` are ruled out.

**Diagnosis (BUG-008.1, 2026-05-06):** See `docs/diagnostics/BUG-008-diagnosis.md` for the full writeup. Summary:

- The vendored PyTorch reference fixture `Tests/PhospheneEngineTests/Fixtures/beat_this_reference/love_rehab_reference.json` was generated by running the official Beat This! Python implementation (commit `9d787b97`) on the same `love_rehab.m4a` audio file. It reports `bpm_trimmed_mean = 118.05` — **the upstream model itself produces 118 BPM on this audio.** The fixture's `description` field already used the qualifier "**~**125 BPM" — the fixture author knew the model was producing 118.
- The Phosphene Swift port returns 118.10 BPM (within rounding of the upstream).
- Three already-committed regression tests (`BeatThisPreprocessorTests.test_loveRehab_goldenMatch` at 1e-3 tolerance on the spectrogram, `BeatThisModelTests.test_loveRehab_endToEnd_producesBeats` on layer-by-layer activations, `BeatGridResolverGoldenTests.test_bpm_withinTolerance` at ±0.5 BPM) prove the entire port chain is faithful to the PyTorch reference end-to-end.
- The preprocessor's spectrogram match against the Python reference at `max|Δ| ≈ 3e-5` is dispositive evidence that AVAudioConverter resampling is correct — any ratio drift would fail that gate.
- DSP.1 baseline data (`docs/diagnostics/DSP.1-baseline-love_rehab.txt`) shows two of three independent estimators on the same audio agree with Beat This!: autocorrelation produces 117.45 BPM stable, and only the kick-only sub_bass IOI trimmed-mean produces 124–129. The kick is on every quarter note in this track; the broader-spectrum detectors are seeing accent structure that places the perceptual beat 2.5 % wider than the kick interval. **This is a model-level disagreement about what "the beat" is, not a Phosphene bug.**

**Diagnostic test added:** `Tests/PhospheneEngineTests/Diagnostics/BeatGridAccuracyDiagnosticTests.swift` — two tests:
- `test_loveRehab_portMatchesPyTorchReference_notMetadataTag` runs `DefaultBeatGridAnalyzer` end-to-end on the vendored fixture and asserts the produced BPM matches the PyTorch reference (118.05 ± 0.5) and is NOT within ±3 BPM of the metadata-tag tempo (125). Permanent tripwire on port-fidelity to upstream.
- `test_synthesizedKick_modelRecoversKnownBPM` (parametrized at 120/125/130 BPM) feeds a synthetic 60 Hz exponentially-decaying kick on every quarter note through the full analyzer at 44.1 kHz native (resamples to 22.05 kHz internally). **Result: 125.0 BPM input → 125.00 BPM produced exactly; 130.0 → 130.09 (essentially exact); 120.0 → 117.97 (-1.7 %, small tempo-specific artifact).** This conclusively settles that the model is *capable* of returning 125 BPM at this tempo on machine-quantized input — so the 118 it produces on Love Rehab reflects the track's actual perceptual-beat structure, not an accuracy ceiling. Both tests pass today; the printed numbers are the deliverable.

**Verification criteria:**
- [x] `DefaultBeatGridAnalyzer` BPM matches the upstream PyTorch reference within ±0.5 BPM. **Confirmed** by `BeatGridAccuracyDiagnosticTests` (passing).
- [x] Phosphene preprocessing chain pinned to upstream reference at 1e-3 spectrogram tolerance. **Confirmed** by existing `BeatThisPreprocessorTests.test_loveRehab_goldenMatch`.
- [x] Phosphene model output pinned to upstream reference at layer-by-layer tolerance. **Confirmed** by existing `BeatThisLayerMatchTests` + `BeatThisBugRegressionTests`.
- [x] Beat This! is accurate at 125 BPM on machine-quantized input. **Confirmed** by `test_synthesizedKick_modelRecoversKnownBPM` (125.0 BPM input → 125.00 produced exactly). The 118 BPM on Love Rehab reflects the track's perceptual-beat structure, not a model accuracy ceiling.
- [x] Disagreement between MIR and offline-grid BPM is surfaced in `session.log` when delta > 3 %. **Confirmed** by `BPMMismatchCheckTests` (7 pure-function tests) and `bpmMismatch_wiring_doesNotCrash_andGridReachesCache` (integration smoke).
- [ ] `drift_ms` stays inside ±30 ms for the duration of a 60-second segment on Love Rehab. **Tracked under BUG-007** — the drift-tracker lock-hysteresis bug is independent of which BPM is "correct" and must be closed first before this can be re-evaluated meaningfully.

**Fix proposal (BUG-008.2 scope):** The fix is *not* a port-fix. Three options in increasing scope:

1. **Documentation + verification gate (recommended for BUG-008.2).** Add a smoke-test on the reference fixture set that prints the offline BPM alongside the metadata-tag BPM for each track. When they disagree by > 3 %, log a `WARN` to `session.log`. No runtime behaviour change. Surfaces the upstream-model failure mode without acting on it.
2. **Cross-validation layer.** Run a second, independent BPM estimator (Phosphene's existing DSP.1 trimmed-mean IOI on sub_bass) over the preview audio at preparation time. When the two estimators disagree by > 3 % AND the IOI estimator's confidence is high, prefer the IOI estimate. Adds ~5 ms per track and a knob (the agreement threshold). Does not fix the structural problem (still one BPM for the whole track).
3. **Drift tracker re-estimates BPM.** Modify `LiveBeatDriftTracker` so accumulated drift over N consecutive beats triggers a beat-period re-estimate from the live onset stream. Structurally correct but a non-trivial change to S7 invariants. Should not be folded into BUG-008; track separately.

Recommended for BUG-008.2: option (1) only. Defer (2)/(3) until **BUG-007** (lock-hysteresis) is closed — drift behaviour is hard to reason about on top of a separate lock bug. With BUG-007 closed and option (1) active, manual validation on Love Rehab will tell us whether the upstream-model BPM is "wrong enough that lock fails" or "merely qualitatively different from the metadata tag in a way that doesn't affect lock."

**Related:** BUG-006.2 (exposed this latent issue end-to-end), DSP.2 S5 (introduced offline BeatGrid resolver), BUG-007 (compounds with — even a perfectly accurate grid wouldn't lock cleanly while BUG-007 is open), Failed Approach #52 (sample-rate plumbing — explicitly ruled out by this diagnosis; the 22050 Hz literal in `BeatThisPreprocessor` is the model's training rate, correctly allowlisted).

---

---

---

### BUG-004 — All production presets have `certified: false`

**Severity:** P3
**Domain tag:** preset.fidelity
**Status:** Resolved
**Introduced:** V.6 (certification pipeline introduced; no presets had passed M7 yet)
**Resolved:** 2026-05-12 — Phase LM (Lumen Mosaic cert flip at LM.7) + BUG-004 closure increment (this commit)

**Root cause:** Quality bar — not a code defect. The certification rubric (V.6 / D-067) and orchestrator filter (`includeUncertifiedPresets: false` default) were correct; no preset had yet survived a Matt M7 visual review against its curated reference set.

**Fix:** Two-part landing.

1. **Cert flip (Phase LM, LM.7 — 2026-05-12).** Lumen Mosaic's LM.4.6 + LM.6 + LM.7 final shape (pure uniform random RGB per cell + cell-depth gradient + per-track chromatic-projected RGB tint) cleared the rubric with **10.5 / 15** (mandatory 7/7 + expected 2.5/4 + preferred 1/4). Matt M7 sign-off recorded against real-music session `2026-05-12T17-15-14Z`: *"Fix has achieved the desired effect — each track now has a visually distinct color palette ... I think we can move to certify this preset."* `LumenMosaic.json` flipped to `"certified": true`. `"Lumen Mosaic"` added to `FidelityRubricTests.certifiedPresets`. Phosphene's **first production certified preset** — Milestone D progresses to **1 / 22+**.
2. **Closure verification (BUG-004 commit, this session).** Three follow-up items addressed:
   - **`GoldenSessionTests.makeRealCatalog()` expanded 11 → 15 production presets.** Pre-closure the fixture was a stale subset that didn't include Lumen Mosaic, Arachne, Gossamer, or Staged Sandbox. Now mirrors every production sidecar. Spectral Cartograph + Staged Sandbox carry `isDiagnostic: true` per D-074 so the orchestrator excludes them categorically. Session C track 5 moved Plasma → Ferrofluid Ocean post-expansion (Plasma's high `fatigue_risk` cooldown extends past track 5's start; FO is the next-best high-energy candidate). Sessions A + B unchanged.
   - **Session D added** — a single-track 180 s fixture with BPM=75 / valence=0.0 / arousal=+0.30 (LM-favourable mood profile). New test `sessionD_lumenMosaicWinsFirstSegment` regression-locks LM winning track 0 / segment 0 under that mood; scoring trace documents LM at total ≈ 0.868 vs Gossamer 0.830 / Arachne 0.818 / Plasma 0.796 / GB 0.787. Demonstrates the cert is end-to-end exercised, not just structurally present.
   - **MatIDDispatch test fixture stale-constant fix.** `MatIDDispatchTests.kLumenEmissionGain` updated 4.0 → 1.0 to match the LM.3.2 round-4 emission-gain reduction (2026-05-10). All 3 MatIDDispatch tests now pass.

**Verification criteria:**
- [x] **Manual:** Matt M7 review approved Lumen Mosaic at LM.7 (session `2026-05-12T17-15-14Z`).
- [x] **Automated:** `GoldenSessionTests` (13 tests, including Session D) passes with at least one certified preset (Lumen Mosaic) producing non-zero orchestrator selections under a plausible mood profile.

**Carry-forward:**
- Phosphene now runs with one certified preset by default. The orchestrator no longer requires `includeUncertifiedPresets: true` for sessions to produce non-empty plans, but the catalog still has 14 uncertified production presets. Watch for over-/under-selection of Lumen Mosaic in real-use sessions — that would indicate a scoring-rebalance follow-up (QR.2-class), not a cert-flip defect.
- Next cert candidates per CLAUDE.md ordering: Arachne V.7.10 (blocked on V.7.7C.5.2 manual smoke + V.7.7C.6 spider movement + BUG-011 perf capture); Aurora Veil (Phase AV — design + references ready, sequenced behind Arachne).

**Related:** V.6, V.7.10, D-067 (cert pipeline), LM.7 sign-off in `docs/presets/LUMEN_MOSAIC_DESIGN.md §10`, D-074 (diagnostic exclusion).

---

### BUG-R001 — BeatGrid finite horizon caused PLANNED·LOCKED never reached

**Severity:** P1
**Domain tag:** dsp.beat
**Status:** Resolved
**Introduced:** DSP.2 S7 (BeatGrid first used without horizon extrapolation)
**Resolved:** DSP.3.4 — commit `7033ad09`

**Root cause:** `BeatGrid.offsetBy` only shifted the ~10 recorded beats. Past the last beat, `computePhase` clamped `beatPhase01=1.0` permanently and `nearestBeat` returned nil → `consecutiveMisses` incremented every onset → `matchedOnsets` never reached `lockThreshold=4`. Diagnostic evidence: session `2026-05-05T21-13-05Z` showed 12,509 frames in LOCKING, 0 in LOCKED.

**Fix:** `offsetBy(seconds:horizon:)` now appends extrapolated beats at `period=60/bpm` up to a 300-second horizon.

---

### BUG-R002 — Hardcoded 44100 Hz sample rate in Beat This! call

**Severity:** P1
**Domain tag:** dsp.beat
**Status:** Resolved
**Introduced:** DSP.2 S9 (live Beat This! trigger)
**Resolved:** DSP.3.4 — commit `7033ad09` (Beat This! site only)
**Generalized:** QR.1 (D-079) — every remaining live-tap consumer threaded; literal `44100` CI-banned via `Scripts/check_sample_rate_literals.sh`; `tapSampleRate` now NSLock-guarded for cross-core visibility.

**Root cause:** `runLiveBeatAnalysisIfNeeded` passed `sampleRate: 44100` to `analyzeBeatGrid` regardless of actual tap rate (48000 Hz). The mel spectrogram covered the wrong time range; BPM resolved as ~216 instead of ~125. The QR.1 multi-agent review (Architect H1; Audio+DSP D1; ML #1+#2) found four more live-tap consumers with the same bug pattern (stem separator dispatch, per-frame stem analysis sample rate, StemSampleBuffer init, StemAnalyzer init default).

**Fix:** DSP.3.4 fixed the Beat This! call site. QR.1 closes the bug class by threading `tapSampleRate` through every live-tap consumer in `PhospheneApp`, NSLock-guarding the field, allowlisting legitimate `44100` literals (StemSeparator.modelSampleRate, BeatThisPreprocessor.sourceSampleRate, default-arg boilerplate), and adding `Scripts/check_sample_rate_literals.sh` to fail loud on any future regression.

---

### BUG-R003 — StemSampleBuffer snapshot undersized at 48000 Hz

**Severity:** P1
**Domain tag:** dsp.beat
**Status:** Resolved
**Introduced:** DSP.2 S9
**Resolved:** DSP.3.4 — commit `7033ad09` (Beat This! call site only)
**Generalized:** QR.1 (D-079) — added `rms(seconds:sampleRate:)` overload; both rate-aware overloads now used at every consumer; covered by `TapSampleRateRegressionTests` so the buffer never silently falls back to its stored default again.

**Root cause:** `snapshotLatest(seconds:)` computed sample count using stored 44100 Hz init rate — a 10-second request retrieved only 9.19 s of real audio. DSP.3.4 added the rate-aware `snapshotLatest(seconds:sampleRate:)` overload but only used it at the Beat This! call site; `performStemSeparation` still used the no-rate overload.

**Fix:** DSP.3.4 added the rate-aware snapshot overload. QR.1 added a matching `rms(seconds:sampleRate:)` overload, threaded both through `performStemSeparation`, and added `TapSampleRateRegressionTests` proving the rate-aware paths return the correct sample count on a 48 kHz tap regardless of buffer init rate.

---

### BUG-R004 — Live Beat This! returns double-time BPM on short window

**Severity:** P1
**Domain tag:** dsp.beat
**Status:** Resolved
**Introduced:** DSP.2 S9 (live Beat This! trigger — no octave correction)
**Resolved:** DSP.3.5 — commit `eac2e140`

**Root cause:** 10-second window at 125 BPM gives ~20 beats. Beat This! correctly detected the density but measured the doubled onset pattern, returning 244.770 BPM.

**Fix:** `BeatGrid.halvingOctaveCorrected()` halves BPM > 160 and drops every other beat recursively; applied before `offsetBy()`.

---

### BUG-R005 — IOI band fusion and histogram-mode picking biased tempo high

**Severity:** P1
**Domain tag:** dsp.beat
**Status:** Resolved
**Introduced:** Original `BeatDetector` implementation
**Resolved:** DSP.1 — commit `bbad760f`

**Root cause:** Two independent bugs: (a) `recordOnsetTimestamps` fused sub_bass + low_bass onset events, producing frame-aliased alternating 18/19-frame IOIs for a true 441 ms beat; (b) histogram-mode BPM picking used integer-rounded buckets with non-uniform widths in period space, biasing toward faster BPMs. See Failed Approaches #50 and #51.

**Fix:** Single-band sourcing from `result.onsets[0]` only; replaced histogram-mode with trimmed-mean IOI in `computeRobustBPM`.

---

### BUG-R006 — Sample-rate plumbing audit (QR.1)

**Severity:** P1
**Domain tag:** dsp.audio
**Status:** Resolved
**Introduced:** Multi-source — DSP.2 S9 added new sites; DSP.3.4 fixed only the Beat This! call site, leaving four other live-tap consumers using the literal `44100`.
**Resolved:** QR.1 — D-079, commits `(see git log [QR.1])`.

**Root cause:** Failed Approach #52: five `PhospheneApp` sites consumed live tap audio at the literal `sampleRate: 44100`. On a 48 kHz tap (the macOS Audio MIDI Setup default) every site silently produced wrong-rate data — stems were 8.8 % time-stretched and pitch-shifted before separation, biasing every downstream stem-feature analysis. Compound with `tapSampleRate` mutated from the audio thread without a synchronization barrier — cross-core visibility for an unsynchronized 8-byte field is not guaranteed on Apple Silicon, producing wrong-tempo grids ~1-in-1000 sessions invisible in tests.

**Fix:** (1) Captured `tapSampleRate` once per tap install through an NSLock-guarded accessor (`updateTapSampleRate(_:)` writer, `tapSampleRate` reader). (2) Threaded `tapSampleRate` through every live-tap consumer (`performStemSeparation` snapshot/rms/separate, live Beat This! snapshot — already DSP.3.4-fixed). (3) Replaced literal `44100` in non-tap-consuming code with `StemSeparator.modelSampleRate`. (4) Added `Scripts/check_sample_rate_literals.sh` to fail loud on any future regression. (5) Added `TapSampleRateRegressionTests` covering the rate-aware `StemSampleBuffer` API.

**Verification:** `swift test --filter TapSampleRateRegression` passes. `bash Scripts/check_sample_rate_literals.sh` exits 0.

---

### BUG-R007 — Tempo octave correction policy split between halving-only and halving+doubling

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** Resolved
**Introduced:** Original `BeatDetector+Tempo.swift` implementation
**Resolved:** QR.1 — D-079, commits `(see git log [QR.1])`.

**Root cause:** `BeatGrid.halvingOctaveCorrected()` (DSP.3.5) is halving-only by design — Pyramid Song genuinely runs at ~68 BPM and any track in [40, 80) BPM must survive. But `BeatDetector+Tempo.computeRobustBPM` and `BeatDetector+Tempo.estimateTempo` retained `if bpm < 80 { bpm *= 2 }` branches that doubled any sub-80 estimate to 150. The split policy meant a track resolving to 70 BPM via the IOI path got reported as 140 BPM in `instantBPM`/`estimatedTempo` while the prepared-grid path (when available) stayed correct at 70.

**Fix:** Deleted the sub-80 doubling branch in both `computeRobustBPM` and `estimateTempo`. Halving (`bpm > 160 → /2`) preserved. Added `tempo_75BPMKick_returnsNear75_notDoubled` and `tempo_68BPMKick_pyramidSongPreservedNotDoubled` to `BeatDetectorTests`.

**Verification:** `swift test --filter "tempo_75BPM|tempo_68BPM"` passes.

---

### BUG-R008 — `MIRPipeline.elapsedSeconds` Float-precision long-session drift

**Severity:** P3
**Domain tag:** dsp.audio
**Status:** Resolved
**Introduced:** Original `MIRPipeline` implementation
**Resolved:** QR.1 — D-079, commits `(see git log [QR.1])`.

**Root cause:** `elapsedSeconds: Float` was incremented by `+= deltaTime` every frame. After 30 minutes of accumulation, ULP ≈ 240 µs — smaller than the ±30 ms tight-match window in `LiveBeatDriftTracker` but a guaranteed monotonic drift over hours of listening. Pre-existing, never observed in production because session lengths in test fixtures are < 1 minute.

**Fix:** `elapsedSeconds` (and `lastOnsetRateTime` / `lastRecordTime`) promoted to `Double`. Consumers cast to `Float` once at the FeatureVector / CSV write site. `LiveBeatDriftTracker.update(playbackTime:)` parameter widened to `Double`. New `elapsedSeconds_typeIsDouble` and `elapsedSeconds_accumulatesAsDouble_isMoreAccurateThanFloat` tests in `MIRPipelineUnitTests`.

**Verification:** `swift test --filter elapsedSeconds_` passes.

---

### BUG-R009 — KineticSculpture sminK violated D-026 (raw AGC-energy thresholding)

**Severity:** P3
**Domain tag:** preset.fidelity
**Status:** Resolved
**Introduced:** Original `KineticSculpture.metal` implementation
**Resolved:** QR.1 — D-079, commits `(see git log [QR.1])`.

**Root cause:** Mercury melt smooth-union radius read `0.06 + f.sub_bass * 0.28 + f.bass * 0.10` — raw AGC-normalized energy with an arbitrary 2.8× weight on a sub-band that is rarely populated in real tracks. Failed Approach #31 / D-026.

**Fix:** Replaced with `0.06 + f.bass * 0.16 + f.bass_dev * 0.05` — continuous bass band (Layer 1) drives the baseline; bass deviation adds the per-onset accent. Stays within the "beat ≤ 2× continuous" rule from `PresetAcceptanceTests`. Golden hashes regenerated; original steady/quiet hashes unchanged within dHash tolerance, beatHeavy shifted slightly (deviation now contributes a small `+0.06` to sminK).

**Verification:** `swift test --filter "PresetAcceptance|PresetRegression"` passes.

---

### BUG-R010 — PitchTracker `vocalsPitchConfidence` structurally 0 due to live-path zero-padding (PT.1 retroactive)

**Severity:** P1 (visible — Aurora Veil's vocals-pitch route had 0% firing across every session for ~5 months; same root cause would have affected any future vocals-pitch preset).
**Domain tag:** dsp.pitch
**Status:** Resolved
**Introduced:** Original `PitchTracker.swift` implementation (MV-3c, D-028, 2026-04-17).
**Resolved:** PT.1, 2026-05-19 (logged in `docs/ENGINEERING_PLAN.md` `[PT.1]` block + Aurora Veil AV.2 closeout narrative). **Retroactive `Resolved` entry filed by Phase CA.1 audit on 2026-05-20** per CLAUDE.md Defect Handling Protocol obligation that every fix increment update `KNOWN_ISSUES.md`. The PT.1 increment shipped without a `BUG-` entry — this row closes that gap.

**Root cause:** The live caller (`StemAnalyzer`) passes 1024-sample windows to `PitchTracker.process(_:)`. The pre-fix implementation copied the input into the first half of an internal 2048-sample buffer and zero-padded the second half. The YIN difference function is `d[τ] = vDSP_dotpr(x[0..1024], x[τ..τ+1024])` — with the second half all zeros, the cross-correlation was structurally zero for every τ, the CMNDF never dipped below the 0.15 threshold, `findMinimum` always returned -1, and the method always returned `(hz: 0, confidence: 0)`.

**Why it survived ~5 months undetected.** `PitchTrackerTests` passes full 2048-sample windows directly to `process`, so the test never exercised the live-incremental code path. Same test/prod parity failure mode that the Aurora Veil AV.1 / AV.2 / AV.2.1 cascade hit (CLAUDE.md: "Test in the production-grade rendering pipeline. No shortcuts"). Pre-PT.1 closeouts that asserted Aurora Veil's vocals-pitch route was working were citing self-judgment, not measured route-firing rates — the diagnostic infrastructure to verify the claim (now `PresetSessionReplay` / SR.1) did not exist.

**Fix:** `PitchTracker.swift` rewritten to (a) maintain a 2048-sample ring buffer via `appendToRingBuffer(_:)` (lines 178–212), (b) track `samplesAccumulated` and only run YIN once it reaches `windowSize` (guard at lines 137–139), (c) shift the ring left and append for sub-window inputs. Live 1024-sample inputs now accumulate across two consecutive calls before YIN runs, instead of being zero-padded.

**Expected behavior:** On real vocals input, `vocalsPitchConfidence > 0.5` fires at a non-trivial rate (~20–25 % of frames per Aurora Veil session data). On silence, returns `(0, 0)` correctly.

**Actual behavior post-fix:** `ENGINEERING_PLAN.md:3858` records "Route 1 vocals melody → hue ... 23.28 % (was 0 % pre-PT.1)" — measured from `features.csv` across a real Aurora Veil session.

**Verification criteria:**
- [x] Source-level: ring-buffer fill guard at `PitchTracker.swift:137-139`; incremental append at `:178-212`.
- [x] Empirical: Route-firing rate ≥ 5 % on a real vocals-bearing track (Aurora Veil session log).
- [ ] **Test-surface gap (acknowledged):** existing `PitchTrackerTests` still pass full 2048-sample windows directly. A live-incremental-path regression test that exercises the 1024-sample append behavior end-to-end has not yet been written. Filing as follow-up work; not a blocker for this entry's `Resolved` status because empirical evidence from production replay covers the gap.

**Confirmed failure class:** `pipeline-wiring` (zero-padding instead of accumulating across calls).

**Related:** D-028 (MV-3c PitchTracker design), AV.2.h Three-Channel curation (Aurora Veil — Route 1 = vocals_pitch hue), CLAUDE.md Failed Approach "diagnostic infrastructure precedes fidelity claims" (this bug is the canonical example).

---

### QR.2 — Stem-affinity scoring AGC saturation + reactive-mode TrackProfile adversarial penalty

**Severity:** P2 (orchestrator correctness; affected every Spotify/Apple Music session)
**Domain tag:** orchestrator
**Status:** Resolved
**Introduced:** Increment 4.1 (PresetScorer original implementation)
**Resolved:** QR.2 (D-080) — 2026-05-06.

**Root cause (Issue #1):** `stemAffinitySubScore` accumulated raw AGC-normalized energies across declared affinities (`clamp(sum(stemEnergy[i]))`) and clamped to [0,1]. AGC centers each energy field at ~0.5; any preset declaring 2+ stems trivially saturated at ~1.0 on most music. Two presets with disjoint affinities ("drums" vs "vocals") both scored ~1.0 on a track where only drums were active. The 25% stem-affinity weight did no discriminative work.

**Root cause (Issue #2):** `DefaultReactiveOrchestrator` built scoring contexts with `TrackProfile.empty`, whose `stemEnergyBalance == StemFeatures.zero`. Under the deviation formula, zero balance → devSum = 0 → score = 0 for ALL stem-affinity-bearing presets. Neutral presets (no affinities declared) scored 0.5 always. The most musically-engaged catalog members were adversarially penalized in the most common use case (reactive ad-hoc listening since U.3). Failed Approach #54.

**Fix:** `stemAffinitySubScore` rewritten to use `stemEnergyDev[stem]` (deviation primitives, D-026/MV-1) and compute `mean(max(0, dev))` over declared stems. Zero-balance guard returns neutral 0.5 when `stemEnergyBalance == .zero`. `DefaultLiveAdapter` converted to class with 30 s per-track mood-override cooldown. Boundary-switch gate tightened with `minBoundaryScoreGap = 0.05`. `cutEnergyThreshold` raised 0.7 → 0.85. `recentHistory` capped at 50. Live `StemFeatures` wired into reactive mode after 10 s. D-080.

**Consequence for planned sessions:** Pre-analyzed `TrackProfile.stemEnergyBalance` has dev≈0 (EMA converged over 30-second preview); stem affinity is neutral (0.5) for all presets in planned-session scoring. Golden session sequences updated in `GoldenSessionTests.swift` — VL no longer wins on a stem bonus.

**Verification:** `swift test --filter StemAffinityScoring && swift test --filter GoldenSession && swift test --filter LiveAdapter` — all pass. 1084 total engine tests, 1 pre-existing flake (MetadataPreFetcher network timeout).

---

### BUG-002 — PresetVisualReviewTests PNG export broken for staged presets

**Severity:** P2
**Domain tag:** preset.fidelity
**Status:** Resolved
**Introduced:** V.7.7A (staged-composition scaffold)
**Resolved:** 2026-05-07 by QR.3 (commit on `[QR.3] tests: integration / connector / ML golden + docs`).

**Note:** Moved from Open section to Resolved section by `[V.7.7B prep]` 2026-05-07 — entry was already marked Resolved but physically remained in Open, the documentation drift the V.7.7B prep prompt corrected.

**Expected behavior:** `RENDER_VISUAL=1 swift test --filter PresetVisualReviewTests` produces per-stage PNG contact sheets for Arachne (and any other staged preset) under `/tmp/phosphene_visual/<timestamp>/`.

**Actual behavior:** The export throws `cgImageFailed` for any staged preset's PNG output. Non-staged presets are unaffected.

**Reproduction steps:**
1. `RENDER_VISUAL=1 swift test --filter PresetVisualReviewTests`
2. Observe `cgImageFailed` error for Arachne (staged); other presets export normally.

**Minimum reproducer:** Any staged preset under `RENDER_VISUAL=1`.

**Session artifacts:** Console output from the test run.

**Suspected failure class:** pipeline-wiring
**Evidence:** `PresetVisualReviewTests.makeBGRAPipeline` calls `Bundle.module.url(forResource: "Shaders")` from the test target bundle (which has no Shaders resource). Staged presets require the `arachne_world_fragment` and `arachne_composite_fragment` functions which live in `Bundle(for: PresetLoader.self)`. The source lookup fails before the pipeline is built.

**Verification criteria:**
- [x] `RENDER_VISUAL=1 swift test --filter PresetVisualReviewTests` produces at least one PNG per stage for Arachne without `cgImageFailed` — verified at QR.3 land time, 16 PNGs across 5 preset cases (Arachne / Gossamer / Volumetric Lithograph non-staged + Staged Sandbox + Arachne staged).
- [x] Per-stage tiles emitted: `Arachne_silence_world.png`, `Arachne_silence_composite.png`, etc.

**Fix scope:** Initial plan was `Bundle(for: PresetLoader.self)` but that does not work in SPM (library targets statically link into the test executable, so `Bundle(for:)` resolves to the test bundle, not the Presets bundle). Resolved by adding `public static var PresetLoader.bundledShadersURL: URL?` that returns `Bundle.module.url(forResource: "Shaders", ...)` from inside the Presets module (where `Bundle.module` resolves correctly), and pointing `makeBGRAPipeline` at it.

**Related:** V.7.7A, D-072, D-090.
