# Phosphene — Known Issues

Open and recently-resolved defects. Filed using `BUG_REPORT_TEMPLATE.md`. See `DEFECT_TAXONOMY.md` for severity definitions and process.

## Open Index

*(RECON.2 reconciliation pass, 2026-08-03 — the 2026-08-03 production audit found this
index disagreeing with its own entry bodies. Three entries left §Open: **BUG-080**
and **BUG-071** were stamped resolved/closed *in place* while still indexed as open,
and **BUG-041** closed as stale on Matt's call. One entry was added: **BUG-084**,
promoted out of a BUG-041 inline aside so it would survive that closure. **BUG-060
moved the other way** — Matt reported the hang has recurred, which falsifies its
"likely resolved" status. Everything in this table is now open work; nothing in it
is already fixed.)*

| ID | Sev | Domain | One-liner |
|---|---|---|---|
| BUG-084 | P3 | dsp.stem | **`StemAnalyzer` deviation reaches 35 where the primitive's real ceiling is ~3.4** — suspected divide-by-near-zero against a not-yet-converged per-track EMA baseline (the stem-side twin of the BUG-027 / AGC2.4.1 cold-start family). No product impact today: FFO's aurora is defended by the FBS.S3.2 soft knee (35 → 1.64), which is what let BUG-041 close. Filed 2026-08-03 (RECON.2) so it survives that closure — the *input* is wrong even though the output is defended. Unreproduced; fixtures retained |
| BUG-070 | P2 | audio.capture / resource-management | **Fix landed 2026-07-12 (PUB.6), pending live validation** — a FAILED device-change tap reinstall left `_isCapturing=true` with zero callbacks: engine health detectors starved (SignalHealthMonitor.evaluate is sample-driven → deadTap never confirms) and the router's recovery restart blocked at the alreadyCapturing guard; only the app-layer poll-based stall card surfaced it. Fix: the catch now clears `_isCapturing` (recovery unblocked) and keeps the monitor as a diagnostic beacon; the false "create steps stopped the monitor" comment corrected. Residual OPEN half: the 3-queue lifecycle interleave (device-change reinstall vs silence-recovery vs user stop) stays unserialized — static-only evidence; restructuring the G1-validated (12/12) path without a reproduced artifact is the BUG-063 pattern. Existing breadcrumbs (per-step diagnostics + install generation) are the instrumentation; serialize only if a live session shows an interleave |
| BUG-076 | P2 | dsp.beat | **Prep grid is window-position unstable on Bleed (Meshuggah) — a third of 30 s windows give a wrong tempo, and Spotify's preview lands on one.** CORRECTED 2026-07-30 after direct measurement (the original filing inferred a universal 3:2 mis-lock from a single session-log value; that was wrong). Measured across nine 30 s windows of the full track: six read ~115 BPM (correct — matches madmom 115.0, librosa 115.0, drums-stem 115.1), but three read 121.1 / 166.1 / 242.7 — a **2.11× spread**, including non-metrical values. `beatsPerBar` swings 2/3/4 on a 4/4 track and `barConfidence` sits at 0.14–0.64. **Control:** Billie Jean over the same windows is 116.9–117.3 with beatsPerBar 4 and barConfidence 1.00 throughout — so this is dense-transient-specific, not universal, and the existing confidence signal already flags it. The session's 174.6 was the preview excerpt landing in the unstable region. Evidence: `docs/diagnostics/BEATBENCH_BASELINE_2026-07-30.md`; reproduce with `BeatBench --audio <clip> --seconds 30`. Category-4 target for Phase DBN (a sequence decoder over the full activation timeline should not be excerpt-dependent); Phase FT removes the 30 s premise for local files |
| BUG-065 | P3 | dsp.beat | **Live BeatGrid phase drifts off the audible beat over a track** — the cached grid has the right BPM but `LiveBeatDriftTracker` *bounds* the live drift without *tightening* it: drift grows ~11 ms (track start) → **50–70 ms (mid/late-track)**, and **28 % of frames exceed the ~60 ms perceptual window** (evidence: session `2026-06-29T12-43-51Z`, Cherub Rock 171.3 BPM 4/4 — drift-by-10s-window 11/37/49/54/69/66/55/48 ms; lock_state=2 only 67 %-within-60 ms). **Caps how frame-locked beat-driven presets can feel** — the live example is Glaze's GLAZE.7 downbeat push (reads connected but not *tight*; tightest early, loosens as the track plays). NOT a functional break (phase is approximately right). **NEW EVIDENCE — session `2026-07-30T15-39-21Z` (Lumen Mosaic, 80.45 BPM 4/4). Matt: "feels a little laggy, otherwise working as intended." This is the strongest case yet and it is WORSE than the 2026-06-29 baseline:** **50 % of frames exceed the ~60 ms perceptual window** (baseline 28 %), `lock_state == 2` only 63 % of frames, and drift **grows monotonically across the session** — by 10 s window: **0 / 6 / 8 / 52 / 70 / 59 / 68 / 104 / 119 ms**. `grid_bpm` is rock-constant at 80.45, so the BPM is right and it is purely the PHASE slipping. Frame rate is NOT the cause and was ruled out first: p50 59.9 fps, only 0.08 % of frames below 30 fps, and `frame_cpu_ms` p50 actually IMPROVED to 11.06 (from 17.30 on `2026-07-27T16-31-01Z`). The "lag" a listener feels is the visual falling up to ~119 ms behind the audible beat late in the track, not stutter. Confirms the mechanism in the original report — the tracker BOUNDS drift without TIGHTENING it — and strengthens the case for the suggested live re-lock / cached-BPM-error correction. In scope for the beat-sync program (D-202).

**Suggested improvement (Matt 2026-06-29):** live re-lock / cached-BPM-error correction so drift holds < ~30 ms across the track. The cold-start *automated phase* premise was retired (CLAUDE.md §Cold-Start), but this is **mid-track drift convergence** — a different surface (the tracker should tighten, not just bound). Logged for a dedicated beat-sync session |
| AUDIT-2026-06-09 | P2/P3 | audit backlog | Full-codebase audit findings not individually filed |
| BUG-060 | P3 | renderer / app.hang | App hang requiring force-quit: render loop died one frame after a `preset → Gossamer` switch (`22-10-50Z`); no stack captured. **RECURRED (Matt, 2026-08-03)** — this falsifies the "likely resolved by NACRE.2b" status, so the preset-apply race is fixed but is **not** the hang mechanism. Needs a `sample`/stack capture on the next occurrence; do not re-run the non-recurrence watch |
| BUG-058 | P3 | audio.capture / resource-management | RARE intermittent: a mid-session output-device swap *occasionally* freezes the tap (`performReinstall` doesn't complete; stale-buffer freeze, not silence). G1 device-swap recovery is otherwise robust (validated 12/12, 2026-06-17); the single freeze was un-reproduced — likely a `coreaudiod`-settling transient. Instrumented |
| BUG-056 | P3 | local-file / audio | Local-file playback restarts the track from the top on an output-device change (AVAudioEngine teardown/restart, no resume-from-position) |
| BUG-055 | P2 | app.ui / permission | Silent system-audio tap after a rebuild: stale Screen-Recording grant; `CGPreflightScreenCaptureAccess` returns stale-`true` → app shows "ready", renders a flatline. **Symptom half RESOLVED 2026-06-17** (`a0a9ded`, silent-tap detector + fix-ladder card) — the app now explains the failure instead of lying. **Durable root still OPEN and externally BLOCKED** on CLEAN.2.5b: a stable signing identity needs a paid Apple Developer membership. Detector half closes on Matt's manual UX validation of the card |
| BUG-054 | P3 | dsp.key | Key detection has never been accurate enough to use — 1024-pt FFT can't resolve semitones < 1 kHz, full-mix chroma, no constant-Q. Non-load-bearing today |
| BUG-051 | P3 | local-file / security | m3u entry paths resolved with no extension/traversal guard (bounded: no egress) |
| BUG-036 | P2 | audio.capture / performance | Heap allocations on the real-time audio thread (three sites) |
| BUG-028 | P2 | dsp.beat | Beat-grid live phase imperfect on ~half of tracks |
| BUG-079 | P3 | build / test-isolation | **`swift test -c release` does not build** — `ArachneState.forceActivateForTest` is `#if DEBUG`-gated in source but its three test-target call sites are not, so the test module fails to compile in release. Pre-existing; found at DBN.2. **Consequence: every release-only performance budget is unverifiable**, including BEAT_SYNC_PROGRAM_PLAN §DBN.2's "< 50 ms for a 30 s activation window" — DBN.2 could only measure debug and its budget test asserts a regression ceiling instead, with the real budget documented as unverified. Fix: guard the call sites, or promote the helper to test-support SPI |
| BUG-078 | P2 | audio.playback / concurrency | **Engine test process traps in `AVAudioPlayerNode` teardown** — `EXC_BREAKPOINT` with libdispatch's "dispatch_sync called on queue already owned by current thread". The `scheduleFile` completion block's release deallocs an `AVAudioNode` on the node's own `CommandQueue`, and `dealloc` → `Stop()` → `dispatch_sync` re-enters that queue. Pre-existing (identical signature in 2026-07-26 crash reports), intermittent, needs full-suite parallelism; passes in isolation. Found at DBN.1, **not caused by it**. P2 not P1 only because it has been seen taking down the test process, not the app — the code path is shipped local-file playback. Leading hypothesis is the strong `self` from `guard let self` in `LocalFilePlaybackProvider.scheduleFileLoop` being released on the completion queue; unproven, next step is a `deinit` breakpoint. BUG-059's off-queue hop does NOT cover this |
| BUG-077 | P3 | dsp.beat / api-contract | **`BeatGridResolver.snapToBeats` diverges from the Beat This! reference post-processor** — the reference moves *every* downbeat prediction to the closest beat unconditionally; we discard any candidate beyond `snapFrames = 2` (40 ms). Found at DBN.1 while auditing the resolver against the paper. **Currently harmless and NOT the cause of the low downbeat F** — measured, 100 % of candidates survive the gate (median distance 0.0 ms), so nothing is being discarded today (the real cause is a near-degenerate downbeat *stream*, see `docs/design/DBN_DECODER_SPEC.md` §2.1). Filed because it is a genuine spec-fidelity divergence of the D-077 class that will bite the moment downbeat timing loosens — e.g. on a track whose downbeat peaks sit a frame or two off the beat. Fix is one comparison; do it in DBN.3 when the resolver is being touched anyway, not as a standalone change |


---

## Open

---



---

### BUG-070 — Failed tap reinstall leaves untruthful capture state; engine detectors starved (2026-07-12)

**P2 · audio.capture / resource-management.** From the 2026-07-11 ultra review (concurrency + audio dimensions); root cause verified in code at PUB.6.

**Expected:** after a failed device-change reinstall, the capture object's state reflects reality (not capturing), engine-side health classification can still fire, and a recovery restart can proceed.
**Actual (pre-fix):** `performReinstall`'s catch did nothing — its comment claimed "the create steps already tore down + stopped the monitor on failure," which was false on both counts. End state: `_isCapturing=true`, monitor running, zero IO callbacks → `SignalHealthMonitor.evaluate` (sample-driven, `ingest` window boundaries) never runs so `deadTap` never confirms; the router's `.silent` recovery is likewise callback-starved; `startCapture` recovery blocked by the alreadyCapturing guard. Only the app-layer Mode-B stall card (1 Hz poll on the tap frame count, ~10 s dwell) surfaced it — detection existed, engine truth and recovery did not.
**Fix (landed, PUB.6):** catch clears `_isCapturing` (unblocks stopCapture+startCapture recovery), monitor deliberately left running as a diagnostic beacon (later fires land in the SKIP branch and breadcrumb), comment corrected.
**Verification criteria:** automated — engine builds; audio suites green (a real failed reinstall cannot be staged headless: Core Audio create-step failures need a live device transition). Manual (pending): a live device-swap session confirming normal reinstalls still work (the G1 12/12 behaviour), and — if a reinstall failure can be provoked — the stall card appears AND a subsequent session restart recovers cleanly.
**Residual (documented, deliberately open):** the 3-queue lifecycle interleave (device-change reinstall vs silence-recovery reinstall vs user stop) is real but static-only evidence; the per-step breadcrumbs + install-generation probes are the instrumentation. Serialize ONLY on a reproduced interleave artifact — restructuring the G1-live-validated path on theory is the BUG-063 class.

---

### BUG-079 — `swift test -c release` does not build, so release-only performance budgets are unverifiable (2026-07-30)

**P3 · build / test-isolation.** Found at DBN.2 when trying to measure a release-only budget; **pre-existing**, unrelated to that increment.

**Expected:** `swift test -c release --package-path PhospheneEngine` builds and runs.

**Actual:** the test target fails to compile in release:

```
error: value of type 'ArachneState' has no member 'forceActivateForTest'
  — SoakTestHarnessTests.swift:294, ArachneSpiderRenderTests.swift:143, :189
```

**Cause.** `ArachneState.forceActivateForTest(at:)` is declared inside `#if DEBUG` (`PhospheneEngine/Sources/Presets/Arachnid/ArachneState+Spider.swift:344-372`), but its three call sites in the test target are not guarded, so they are unresolved in a release build. Debug builds are unaffected, which is why this has gone unnoticed.

**Why it matters beyond tidiness.** It makes **release-only performance budgets unverifiable**. BEAT_SYNC_PROGRAM_PLAN §DBN.2 specifies "< 50 ms for a 30 s activation window on M1" for `BeatActivationDecoder`; that is a release figure, and DBN.2 could only measure debug (1366 ms after optimisation, down from 17,067 ms naive). `DSPPerformanceTests.test_beatActivationDecoder_30sWindow_performance` therefore asserts a *regression* ceiling and documents the real budget as unverified, rather than dividing the debug number by an invented constant. **Any plan gate phrased as a release timing is currently unenforceable.**

**Suspected failure class:** `test-isolation` (a DEBUG-only API reachable from unguarded test code).

**Fix shape:** wrap the three call sites in `#if DEBUG`, or drop the `#if DEBUG` around `forceActivateForTest` and mark it as test-support SPI. The first is smaller; the second is what the rest of the codebase does for `*ForTest` helpers, so check the convention before choosing.

**Verification criteria.** `swift test -c release --package-path PhospheneEngine` builds and the suite passes; the DBN.2 budget test is then re-pointed at the real 50 ms release figure and either passes or forces the design change the spec calls for.

---

### BUG-078 — Engine test process traps in `AVAudioPlayerNode` teardown: `dispatch_sync` on an already-owned queue (2026-07-30)

**P2 · audio.playback / concurrency.** Found at DBN.1 while running the closeout evidence; **pre-existing, not introduced by that increment**. P2 rather than P1 because it has only been observed taking down the *test* process — but the code path is shipped local-file playback, so the app-facing impact would be a hard crash.

**Recurrence observed 2026-08-03 (RECON closeout).** A third data point, recorded because this bug is intermittent and every observation narrows it. A full `swift test` run exited **non-zero with `0 failures (0 unexpected)` and no per-test failure line** — the closeout script's own extractor reported "nonzero exit / failure count with no per-test failure lines extracted". The last suites logging before the exit were the `LocalFilePlaybackProvider` concurrency cases (`completionCallbackVsStop_abbaShape_neverDeadlocks`, `onFileEnded_queueAdvanceChurn_neverHangs`, `transportChurn_concurrentWithStopStart_neverDeadlocks`), which is the `AVAudioPlayerNode` teardown surface this entry describes. **The immediately following full run passed clean** (1737 tests / 250 suites, exit 0), and the run after that was green end-to-end — matching "intermittent, needs full-suite parallelism, passes in isolation". Two practical notes for whoever picks this up: (1) **the signature to look for is exit-code-without-failure, not a red test** — an extractor that only reports failing assertions will show nothing; (2) it reproduced on an otherwise-unmodified tree during a docs-only increment, so it needs no particular code state to fire.

**Expected:** `swift test --package-path PhospheneEngine` completes.

**Actual:** the test process dies with `EXC_BREAKPOINT` / SIGTRAP part-way through the suite, with no failing assertion. libdispatch's own diagnostic names the fault:

> `BUG IN CLIENT OF LIBDISPATCH: dispatch_sync called on queue already owned by current thread`

**Reproduction.** Full engine suite; dies while `concurrentDoubleStart_serializesWithoutDeadlock()` (suite "Session lifecycle churn (REVIEW.2)") is the in-flight test. Reproduced **twice on 2026-07-30** at `0d3d57d2` and `4bf6703d`, and the identical signature appears in two crash reports from **2026-07-26**, so it long predates this session. **Passes in isolation** (`--filter concurrentDoubleStart_serializesWithoutDeadlock`, 1.16 s) — it needs full-suite parallelism, which makes it timing-dependent and intermittent. The suite was green at `5b019f2f` hours earlier; adding one default-skipped test file appears to have perturbed scheduling enough to make it reproduce, which is a symptom of how narrow the window is, not a cause.

**Artifacts.** `~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-2026-07-30-171311.ips` (+ `-171004`, and `-2026-07-26-152850` / `-152102`). Faulting thread is named `CommandQueue`:

```
AVAudioPlayerNodeImpl::CommandQueue::PerformWork
  → FileCommand::Perform → ~FileCommand → ~AVAEBlock → _Block_release
  → -[AVAudioNode dealloc] → ~AVAudioPlayerNodeImpl
  → AVAudioNodeImplBase::Stop() → dispatch_sync   ← same queue it is running on
```

**Suspected failure class:** `concurrency` (object deallocated on a queue whose teardown re-enters that queue synchronously).

**Leading hypothesis — stated as a hypothesis, not a conclusion.** Releasing the `scheduleFile` completion block on the player node's own `CommandQueue` drops the last strong reference to an `AVAudioNode`, so `dealloc` runs *on that queue* and its `Stop()` synchronously re-enters it. In `LocalFilePlaybackProvider.scheduleFileLoop` (`:355-378`) every capture is already `[weak self, weak player, weak file]`, so the block itself does not retain the node — but `guard let self` inside the handler materialises a **strong** provider reference for the body's duration, and that reference is released when the block returns, still on the command queue. If it was the last one, the provider's `deinit` releases `playerNode` there. That is consistent with the stack but **not yet proven** — the next diagnostic step is a `deinit` breakpoint (or an `os_signpost`) on the provider and on the node to confirm which object's release triggers the dealloc, before any fix is designed.

**Note on BUG-059.** That fix hopped *off* the completion queue before re-scheduling, which addressed the lock-reentrancy deadlock. It does not cover this: the async hop returns immediately, but the strong `self` created by `guard let self` is still released on the completion queue afterwards. Same queue, different mechanism — do not assume BUG-059's fix covers it.

**Verification criteria (written before any fix).** Automated: the full engine suite completes 5 consecutive times with no `.ips` generated. Regression: a targeted test that drops the provider's last reference while a `scheduleFile` completion is in flight and asserts no trap. Manual: local-file playback end-to-end — start, seek, track-change, and quit-while-playing — since this is the shipped path.

**Out of scope for DBN.1** (which is a docs/spec increment). Filed and reported, not fixed.

---

### BUG-077 — `BeatGridResolver.snapToBeats` diverges from the Beat This! reference post-processor (2026-07-30)

**P3 · dsp.beat / api-contract.** Found at DBN.1 while auditing the resolver against the paper it implements.

**Expected:** `BeatGridResolver` implements Beat This!'s minimal post-processor. That post-processor's third step is *"move all downbeat predictions to the closest beat prediction"* — unconditional, no distance limit (Foscarin et al., ISMIR 2024).

**Actual:** `snapToBeats` applies `if nearestDist <= maxDistance`, where `maxDistance` comes from `snapFrames = 2` (40 ms at 50 fps). Any downbeat candidate further than 40 ms from the nearest beat is **discarded** rather than snapped.

**Currently harmless, and explicitly NOT the cause of the low downbeat F.** Measured at DBN.1 (`DownbeatStreamDiagnosticTests`): **100 % of downbeat candidates survive the gate** on money, billie_jean and solsbury_hill (median distance to nearest beat 0.0 ms; take_five 94 %). Nothing is being discarded today. The real cause of the 0.13–0.26 downbeat F is a near-degenerate downbeat *stream* — the model emits a confident downbeat on 69–90 % of beats on odd-meter tracks — documented in [`docs/design/DBN_DECODER_SPEC.md`](../design/DBN_DECODER_SPEC.md) §2.1. **This entry exists so a future session does not re-derive the divergence and mistake it for the defect.**

**Why file it anyway:** it is a genuine spec-fidelity divergence of the D-077 class (a paraphrased post-processor silently dropping data the reference keeps), and it becomes live the moment downbeat timing loosens — a track whose downbeat peaks sit two or three frames off the beat would have those downbeats deleted rather than snapped, and `computeMeter` would then divide a decimated set.

**Fix:** one comparison. Do it in **DBN.3**, when the resolver is being touched for the decoder A/B anyway — not as a standalone change, since it alters grid output and would need its own golden regeneration for no current behavioural gain.

**Verification criteria.** Automated: a resolver unit test with a downbeat candidate placed >40 ms from any beat, asserting it is snapped rather than dropped. Regression: `BeatGridResolver` goldens + the BeatBench offline-grid table unchanged on all 9 ground-truthed tracks (the fix should be a no-op on today's fixtures — if it is not, that is itself the finding).

---

### BUG-076 — Prep grid is window-position unstable on Bleed (a third of 30 s windows read wrong) (2026-07-27, CORRECTED 2026-07-30)

**Domain tag:** dsp.beat (grid tempo/meter). **Severity:** P2 — one track, but it is the defining case for category 4 (dense transients) and it demonstrates the program's central premise concretely.
**Status:** **Open — deferred by design, do not fix in isolation.** Owned by the beat-sync program (D-202): Phase DBN should dissolve it (a sequence decoder over the full activation timeline is not excerpt-dependent) and Phase FT removes the 30 s premise for local files. A targeted per-track patch here would be tuning against one fixture. *(Status line added at RECON.2, 2026-08-03 — this was the only §Open entry without one, so its disposition lived in prose and the index row alone.)*
**Resolved:** —

**CORRECTION (2026-07-30).** As first filed this bug claimed the grid "locks to a non-metrical tempo (3:2)" on Bleed, generalising from a single number in a session prep log (`bpm=174.6`) without re-measuring. Direct measurement at GT.3 falsified that: run on the fixture, the grid reads **115.00** — the correct value. The real defect is **sensitivity to which 30 s window is analysed**, which the original filing missed entirely. Recorded rather than quietly rewritten, because the mistake is instructive: a logged value is one sample, not a characterisation.

**Expected:** the prep grid returns the same, musically valid tempo regardless of which excerpt of a track it is given.

**Actual — nine 30 s windows of `bleed.wav`:**

| offset | BPM | beatsPerBar | barConfidence |
|---|---|---|---|
| 0 s | **115.00** ✓ | 4 | 0.50 |
| 30 s | 121.10 ✗ | 2 | 0.59 |
| 60 s | 116.88 ✓ | 2 | 0.62 |
| 90 s | **242.71** ✗ | 3 | 0.32 |
| 120 s | **166.09** ✗ | 3 | 0.45 |
| 150 s | 115.38 ✓ | 3 | 0.14 |
| 180 s | 115.07 ✓ | 2 | 0.48 |
| 210 s | 115.15 ✓ | 4 | 0.60 |
| 240 s | 114.92 ✓ | 2 | 0.64 |

Six of nine correct; three wrong across a **2.11× spread**. Ground truth is unambiguous — Matt's taps 226.7 (2:1 of the pulse), madmom 115.0, librosa 115.0, session drums-stem 115.1. `beatsPerBar` also swings 2/3/4 on a track that is 4/4 throughout.

**Control (matters — it bounds the defect):** Billie Jean over the same offsets reads 116.88 / 117.04 / 117.12 / 117.25 / 117.17, `beatsPerBar` 4 and `barConfidence` **1.00** at every window. So this is not a general instability; it is specific to dense-transient material where the activation function has energy at several subdivisions. Notably `barConfidence` already separates the two cases (0.14–0.64 vs 1.00) — the existing signal knows.

**Why the session logged 174.6:** the prep path analyses the 30 s Spotify preview, a mid-track excerpt, which fell in the unstable region. This is the plan's §2 premise made concrete: a grid built once from one arbitrary 30 s excerpt and extrapolated.

**Reproduction:** `swift run BeatBench --audio ~/phosphene_beatbench_fixtures/bleed.wav --seconds 30` for the whole file, or cut a window with `ffmpeg -ss <offset> -t 30` and pass that. Fixture sha256 in `Tests/Fixtures/beatbench/manifest.json`.

**Suspected failure class:** `algorithm` — `BeatGridResolver` peak-picking a dominant period from Beat This! activations without a sequence model. Palm-muted 16ths put comparable energy at several metrical levels, so the winner depends on the excerpt.

**Verification criteria (written before any fix):**
1. Automated: BeatBench window-sweep over Bleed — ≥ 8/9 windows within 5 % of a valid metrical level of 115.0, spread < 1.1×. Baseline is 6/9 and 2.11×.
2. No regression: suite 1 stays green (DBN.3 hard gate); Billie Jean's window sweep must remain flat.
3. Manual: Matt confirms beat-driven motion reads on-pulse on Bleed.

**Do not fix in isolation.** The fix is the Phase DBN sequence decoder (and Phase FT, which removes the 30 s premise for local files). A per-track heuristic would be the peak-pick patching the program exists to retire.

### BUG-065 — Live BeatGrid phase drifts off the audible beat over a track (mid-track drift convergence) (2026-06-29)

P3, `dsp.beat`. (Renumbered from BUG-064 on the GLAZE.8→main merge — BUG-064 was already assigned to the Lumen freeze; this beat-sync bug forked the number on `claude/nice-rubin-9c10c7`.)

**Expected:** the live beat phase stays within the ~60 ms perceptual window across a whole track, so frame-locked beat-driven motion (e.g. Glaze's GLAZE.7 downbeat push) reads tight start-to-finish.

**Actual:** the cached grid has the right BPM, but `LiveBeatDriftTracker` *bounds* the live drift without *tightening* it — drift grows ~11 ms (track start) → 50–70 ms (mid/late-track), with 28 % of frames exceeding ~60 ms. Evidence: session `2026-06-29T12-43-51Z` (Cherub Rock, 171.3 BPM 4/4 — drift-by-10s-window 11/37/49/54/69/66/55/48 ms; `lock_state=2` only 67 %-within-60 ms). NOT a functional break (phase is approximately right); it caps how *tight* beat-locked presets can feel (the live example: GLAZE.7 reads connected but loosens as the track plays).

**Suggested improvement (Matt 2026-06-29):** live re-lock / cached-BPM-error correction so drift holds < ~30 ms across the track. The cold-start *automated phase* premise was retired (CLAUDE.md §Cold-Start), but this is mid-track drift *convergence* — a different surface (the tracker should tighten, not just bound). Logged for a dedicated beat-sync session.

**Status 2026-07-30 — OPEN. Root cause proven (TRK.1); both attempted fixes stopped at their own gates.**

- **TRK.1 (`07dd3bd9`) proved the mechanism.** The drift is a *ramp*, not noise: linear fit **−1.493 ms/s at R² = 0.844** on session `2026-07-30T15-39-21Z` (Hummer, 80.45 BPM), `grid_bpm` rock-constant ⇒ a **0.149 %** cached-grid period error (0.12 BPM). The legacy tracker is a first-order EMA on phase error — proportional-only, which has zero steady-state error against a step but *constant* error against a ramp. It can bound drift; it can never null it. That is exactly "bounds without tightening". A type-2 (PI) controller was implemented behind `PHOSPHENE_BEAT_PLL` and **failed real-fixture validation** — `LiveDriftValidationTests` (loveRehab) maxAbsDrift **101.5 ms** (limit 50), beat alignment **0.05** (limit 0.80). Default-off. **Strike 1 on the gain-tuning premise; do not retune gains against sub-bass evidence.**
- **TRK.2 stopped at its evidence gate — the drums-stem premise is FALSIFIED.** The proposed fix was to change the *evidence* (drums-stem onsets instead of sub-bass) rather than the gains. Measured on four captures with the production `StemSeparator` + a separate `BeatDetector` instance (D-075), bias-corrected: drums-stem sub_bass onsets landing within ±50 ms of a grid beat vs the full mix — love_rehab **16.9 % vs 42.2 %**, Hummer **11.0 % vs 14.4 %**, `bleed.wav` **22.4 % vs 22.3 %**, billie_jean **25.5 % vs 24.5 %**. Worse on two, a wash on two, *including Bleed* — the category-4 track the whole argument rested on. Best drums band anywhere: +2.5 pp, inside noise. **Larger finding:** across every capture, band and stem, only **~15–25 % of detected onsets land within ±50 ms of a beat** — FA #68 generalises, the spectral onset-detector family is weak beat evidence wherever it runs. **Second, independent blocker:** the live stem path (`VisualizerEngine+Audio.swift` `runPerFrameStemAnalysis`) deliberately carries **5–10 s of latency** with a sawtooth re-anchor every ~5 s, so drums onsets cannot be timestamped correctly by the tracker without a separate design that threads their true tap time through. No production code was changed. Evidence + reproduction: [`docs/diagnostics/TRK2_DRUMS_STEM_EVIDENCE_2026-07-30.md`](../diagnostics/TRK2_DRUMS_STEM_EVIDENCE_2026-07-30.md); instrument: `DrumsOnsetEvidenceTests` (env-gated).
- **Corroborated at scale by the GT.3 live baseline (2026-07-30).** `docs/diagnostics/BEATBENCH_LIVE_BASELINE_2026-07-30.md` measures the drift curve across 15 streamed tracks, and the growth this bug describes is the norm, not one capture: billie_jean 26 → 118 ms, stayin_alive 60 → 285 ms, money 20 → 241 ms, superstition 26 → 94 ms, clair_de_lune 39 → 135 ms by 30 s window. Only giorgio_by_moroder and pyramid_song hold flat. The program's live suite-1 target is **p90 < 30 ms**; the measured p90 is 102 ms on billie_jean and 269 ms on stayin_alive. This is systemic to the frozen single-BPM grid premise.
- **PARKED — Matt 2026-07-30 (D-206): "park the tracker, go DBN next session."** Two evidence sources and one controller topology have now been measured against the same frozen single-BPM grid, and the evidence layer has no headroom left. BUG-065 stays **open and bounded** (the visual falls up to ~119 ms behind late in a track; not a functional break); `PHOSPHENE_BEAT_PLL` stays default-off. Phase TRK is parked and TRK.3 has no content. The defect is now expected to be addressed — if at all — as a side effect of phase **DBN** replacing the frozen single-BPM grid premise, not by further tracker work. **Do not reopen TRK without a changed premise about the *grid*, not the tracker.**


---

### AUDIT-2026-06-09 — Full-codebase audit backlog (P2/P3 findings not individually filed)

**Status:** Open — index entry (P3 backlog only as of PUB.3: all four formerly-open P2 bullets below verified fixed in code, 2026-07-11). The 2026-06-09 six-agent full-codebase audit (~92k lines, all findings verified at file:line, cross-checked against this tracker and CLAUDE.md FAs) produced 6 P1s, 17 P2s, ~40 P3s. The P1s and three highest-impact P2s are filed individually below (BUG-030 … BUG-037). Everything else lives in **[`docs/diagnostics/CODE_AUDIT_2026-06-09.md`](../diagnostics/CODE_AUDIT_2026-06-09.md)** — treat that document as the evidence record when picking up any item. Remaining P2s in brief (full detail + fix shapes in the audit doc):

- ✅ **RESOLVED (CLEAN.3.2, 2026-06-17; re-verified in code at PUB.3)** — reactive orchestrator hard-exclusion filtering now present (`ReactiveOrchestrator.swift:~220`, exclusion-aware selection with the every-preset-excluded edge handled).
- ✅ **RESOLVED (CLEAN.3.3, 2026-06-17; re-verified at PUB.3)** — zero-duration fallback now routes through the scored/excluded path (`SessionPlanner+Segments.swift:~129`).
- ✅ **RESOLVED (CLEAN.3.x, 2026-06-17; re-verified at PUB.3)** — cooldown reset on track/session boundary (`LiveAdapter.swift:~369-378`).
- ✅ **RESOLVED (CLEAN.3.5, 2026-06-17; re-verified in code at PUB.3)** — in-memory StemCache now has an LRU cap (`maxEntries` + touch-on-track-change eviction, `StemCache.swift:~89-101`).
- **OAuth correctness (re-entrant `login()` leak, refresh double-spend, P3 hardening)** — ✅ **RESOLVED 2026-06-14 (CLEAN.2.2, commit `13cec8b`, integrated `a6f1288`).** Matt's live check passed: Spotify playlist loaded with no problems on the integrated `main` build — the refresh path exercised end-to-end against real Spotify, no regression. The fresh-login `state` guard is unit-test-proven + standard OAuth on unchanged callback routing (accepted without a forced interactive login per Matt 2026-06-14, since a silent refresh does not hit the consent round-trip). `SpotifyOAuthTokenProvider`: a second `login()` while one was pending overwrote `pendingContinuation` (orphaning the first caller until the 5-min timeout) + armed a stray timeout against the wrong attempt → now coalesces concurrent logins onto one in-flight attempt (`pendingContinuations` array; `finishLogin()` cancels the timeout on every resume path); concurrent `acquire()` each fired their own silent refresh, double-spending the rotating refresh token → now dedups onto a single in-flight `refreshTask`; + P3s (OAuth `state` CSRF/replay guard, form-body percent-encoding of `+ & = /` that `.urlQueryAllowed` leaked, Keychain-save failures logged not swallowed, callback `scheme == phosphene` + host validation). `SpotifyOAuthTokenProviderTests` green (4 new regressions).
- ✅ **RESOLVED (CLEAN.2.1, 2026-06-14)** — Spotify client secret baked into the built Info.plist. Removed `SpotifyClientSecret` from `Info.plist` + `Phosphene.xcconfig` and deleted its only consumer, the D-068 client-credentials `DefaultSpotifyTokenProvider`. The production flow already used OAuth Authorization Code + PKCE (`SpotifyOAuthTokenProvider`), which needs no secret; no build-bundled secret remains. OAuth login E2E confirmed by Matt 2026-06-14 on the integrated `main` build (no regression). See `RELEASE_NOTES_DEV.md [dev-2026-06-14-d]`.
- ✅ **RESOLVED (CLEAN.2.3, 2026-06-14)** — honest-UI dead controls (audit T5), each Matt's product call. **2.3.1:** the "Use Apple Music instead" no-op `{ }` cross-link (+ its dismiss-only mirror) now drive a real `NavigationStack` switch via `ConnectorPickerViewModel.switchConnector(to:)` (wire). **2.3.2:** the `.localFile` "coming later" capture mode (lying + no-op) removed — enum case, picker row, false string, and the now-unreachable reconciler/coordinator branches (remove; supersedes the `.localFile` branch of D-052). **2.3.3:** the disabled "Swap preset" context-menu stub hidden behind `#if ENABLE_PRESET_SWAP` until U.5b (hide). Commits `7800b72` / `d40cfad` / `6e983c8`. `RELEASE_NOTES_DEV.md [dev-2026-06-14-f]`.
- ✅ **RESOLVED (CLEAN.4.4, 2026-06-17)** — three renderer over-allocation / cache-key items from audit T7 (the `2026-06-13` audit's restatement of these P3s). (1) **PSO cache key** (`ShaderLibrary` cached by `name` alone, ignoring `pixelFormat`/`supportICB`): **finding = LATENT, not a live bug** — every production caller uses a **unique** name compiled once at init, preset multi-pass PSOs bypass the cache (`PresetLoader` → `device.makeRenderPipelineState`), and `supportICB: true` is test-only, so nothing currently collides; keyed correctly anyway by `PipelineKey(name, pixelFormat.rawValue, supportICB)` so a future name-reuse can't return the wrong-format PSO. (2) **wasted particle-mode warp pass** + (3) **unconditional feedback textures**: both gated to surface-mode feedback presets via `RenderPipeline.activePresetSamplesFeedback` — non-feedback + particle-mode presets allocate zero ping-pong (freed on `setFeedbackParams(nil)`), and particle mode skips the warp. Output-preserving (PresetRegression goldens byte-identical). Gates: `ShaderLibraryTests` +2, `DrawableResizeRegressionTests` +3. `RELEASE_NOTES_DEV.md [dev-2026-06-17-215601]`. (T7's remaining items — sceneTexture aliasing, resize stale-size, ray-march /height NaN, DynamicTextOverlay race — **were closed by CLEAN.4.3 and CLEAN.4.5, both completed 2026-06-18**; see `docs/diagnostics/CODE_AUDIT_2026-06-13.md`, where they are marked ✅, and `ENGINEERING_PLAN_HISTORY.md`. *Corrected at RECON.2, 2026-08-03: this line previously read "stay open under CLEAN.4.3/4.5", and since both increments have rotated out of the live plan the pointer was unresolvable from here — it read as open work with no owner.*)
- ✅ **RESOLVED (CLEAN.2.3.4, 2026-06-14)** — localization gate only scanned `PhospheneApp/Views/`. `check_user_strings.sh` ROOTS widened to `PhospheneApp/ViewModels` + `ContentView.swift`, pattern extended with a connection-state `.error("…")` arm (`logger.error` excluded); the bypassing copy (Spotify/AppleMusic error strings, ConnectorType tiles, ReadyViewModel duration/source, ContentView fallback, PreparationProgressView subtitle, PlanPreviewTransitionView labels) externalized to `Localizable.strings`. Gate header documents its honest scope limit (literal-prefix matcher — lowercase/interpolated fragments still rely on review). Commit `46d836b`.

P3 categories indexed in the audit doc: ~25 latent bugs (incl. OAuth refresh double-spend + form-encoding gaps [Resolved CLEAN.2.2, see above], PSO cache key, mv_warp buffer(5) omission, PostProcessChain texture aliasing, malformed-sidecar swallowing, Arachne listening-pose FA #57-gate, >2-channel LF corruption, ~94 Hz vs 60 fps chroma hysteresis), ~11 perf items (autocorrelation 2×/frame, drums FFT 2×/frame, mono STFT 2×/track, serial prep pipeline, wasted particle-mode warp pass, unconditional feedback textures), dead code, and 6 in-code doc-drift items.


---

**GT.3 addendum (2026-07-30) — the ramp is systemic, and one track is 14× worse.** BeatBench session-replay over the 15-track `beat-match-test-session` fits `drift_ms` against time for every track. Each is a linear **ramp**, confirming the TRK root cause (a period error a proportional-only controller can bound but never null) across the whole catalog rather than one capture:

| track | period error | R² | unlocks at | confident-wrong |
|---|---|---|---|---|
| **YYZ** | **+2.070 %** | **0.99** | 47 s | **90.8 %** |
| Dance Yrself Clean | −0.149 % | 0.79 | 58 s | 81.4 % |
| Bohemian Rhapsody | +0.126 % | 0.93 | 0 s | 76.9 % |
| Money | −0.081 % | 0.93 | 122 s | 64.1 % |
| Stayin' Alive | +0.083 % | 0.89 | 48 s | 84.0 % |
| (10 others) | < 0.07 % | — | — | 0–53 % |

**YYZ is the extreme case and it is real, not an artifact** (R² 0.99 over 15,898 frames): a 2.07 % period error accumulates to **4.8 seconds — about 11 beats — by the end of a 266 s track**, while `lock_state == 2` for 92 % of frames. The engine reports "locked" while eleven beats out of phase. Note Dance Yrself Clean's −0.149 % matches the period error TRK measured exactly.

**Two things this reframes.** (1) *Time-to-lock was the wrong metric.* Drift on these tracks starts **inside** the ±70 ms window (YYZ 52.7 ms, Dance Yrself 29.0 ms) and walks out, so "time to lock" reads 0 s and looks healthy; the informative number is **time-to-unlock**, and **13 of 15 tracks leave the window and never return** — only Solsbury Hill and Giorgio stay in. (2) *The suite-1 live target is far off.* Billie Jean's p90 is **102 ms** against a target of < 30 ms.

Evidence: [`BEATBENCH_LIVE_BASELINE_2026-07-30.md`](../diagnostics/BEATBENCH_LIVE_BASELINE_2026-07-30.md). Reproduce: `BeatBench --mode session-replay --session <dir>`.

### BUG-084 — `StemAnalyzer` deviation reaches 35 where the primitive's real ceiling is ~3.4 (suspected EMA divide-by-tiny) (2026-08-03)

**Severity:** P3. No known product impact today — the one consumer that could have been hurt (FFO's aurora intensity) is defended by the FBS.S3.2 soft knee, which caps 35 → 1.64. Filed because the *input* is wrong, not the output: any future consumer that reads a stem deviation without a soft knee inherits the bug, and the value silently poisons any statistic computed over stem deviations.
**Domain tag:** `dsp.stem` (deviation primitive / EMA convergence).
**Status:** **Open — unreproduced, not investigated.** Carried as an inline aside inside BUG-041 from 2026-06-10 until that entry closed as stale (RECON.2, 2026-08-03); filed properly here so it survives its parent's closure. This is the whole reason BUG-041 could be closed safely.
**Introduced:** unknown; present at least since 2026-06-10.
**Resolved:** —

**Expected.** Deviation primitives (`bassDev`/`drumsEnergyDev` and siblings, D-026) express a band's deviation from its own running EMA. Measured against real music they spike to roughly **3× with a p99 near 0.85** — the documented real range, and the basis for the "soft-saturate against p99, never against 1.0" rule (CLAUDE.md FA #73).

**Actual.** Session `2026-06-10T17-50-56Z` (So What) produced `dev = 35` — an order of magnitude past the primitive's observed ceiling, and 3–30× the track median across an all-stem burst.

**Suspected mechanism.** `StemAnalyzer` resets per track and its per-stem EMA re-seeds from near-zero. A deviation computed as a *ratio* against that not-yet-converged baseline divides by a near-zero denominator, so the quotient explodes during the convergence window. This is the same shape as the BUG-027 / AGC2.4.1 cold-start family that was fixed for the FeatureVector band devs; the stem-side twin may simply never have received the equivalent guard.

**Reproduction steps.** Not yet attempted. Start point: replay the `fbs/` fixtures that captured the burst (`stemsum_so_what_2026-06-11T01-56-22Z.csv` and siblings retained in `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/fbs/`) and log the raw pre-soft-knee deviation alongside the EMA denominator through the first ~10 s of a track.

**Suspected failure class:** `numerical` (divide-by-near-zero during EMA convergence).

**Verification criteria:**
- [ ] Raw stem deviation confirmed against the ~3.4 ceiling on the fixtures above, with the EMA denominator logged — i.e. mechanism *observed*, not inferred, per the evidence-before-implementation gate.
- [ ] If confirmed, a floor on the denominator (or the BUG-027-family guard) brings the primitive inside its documented range without changing musical response — the soft knee's output must not measurably move for normal values.
- [ ] No regression in FFO aurora behaviour (the soft knee stays; this fixes the input, not the defence).

**Manual validation required:** No, if the fix leaves the soft-kneed output unchanged for musical values — the automated FBS gates cover the visible surface. Yes if the fix alters aurora response at all.

**Related:** BUG-041 (closed as stale 2026-08-03 — this was its inline aside); BUG-027 / AGC2.4.1 (the FeatureVector-side twin, fixed); CLAUDE.md FA #73 and [[deviation-primitive-real-range]] for the documented real range.

---

### BUG-060 — One-off app hang: the render loop died on a `preset → Gossamer` switch; force-quit required; not reproduced (2026-06-18)

**Severity:** P3 (a full app hang requiring force-quit is P1-*impact*, but it was seen once and did not reproduce — Gossamer ran 3× clean the next session; filed as **monitored**, like BUG-058, pending a recurrence with a captured stack).
**Domain tag:** renderer / app.hang (suspected preset-apply or first-frame GPU hang on Gossamer).
**Status:** **OPEN — RECURRED (Matt, 2026-08-03; RECON.2).** The prior "likely resolved by NACRE.2b" status is **falsified as a complete explanation** and must not be restored without new evidence. Asked directly during the 2026-08-03 production audit whether the force-quit hang had been seen since mid-July, Matt confirmed it had. No session ID, preset, or stack was captured for the recurrence, so the *mechanism* is still undiagnosed — what changed is that the empty-`activePasses` guard is now known to be **insufficient**, which was the exact residual risk the previous status flagged ("the original was a *hang*, not a crash, so a small chance it's a distinct GPU-contention issue remains"). That residual is now the leading hypothesis rather than a footnote.

**What the recurrence changes.** Previously this entry was one clean session away from closing. It is now a live P3 with a *narrowed* hypothesis space: the preset-apply race is fixed and verified (BUG-061 is closed on its own evidence), so whatever hangs the render loop is **not** that race. Do not re-run the "confirm by non-recurrence" plan — it has already returned a negative. The next step is evidence capture, not another monitoring window.

*Prior status, retained for the reasoning trail:* LIKELY RESOLVED by NACRE.2b's BUG-061 fix (2026-06-25), pending non-recurrence. BUG-061 confirmed the suspected **preset-apply race**: `applyPreset` clears `activePasses` to `[]` then republishes them at its end, while `draw(in:)` runs concurrently on the display-link thread; a frame in that window falls to `drawDirect` with the new preset's direct pipeline. Nacre's `.rgba16Float` pipeline made it a deterministic crash and exposed the mechanism; for an 8-bit preset like Gossamer it's the benign/intermittent stray frame seen here. The `willRenderActiveFrame` guard (skip frames while `activePasses` is empty) removes the stray `drawDirect` for ALL presets. Keep monitored until a few clean Gossamer-switch sessions confirm non-recurrence (the original was a *hang*, not a crash, so a small chance it's a distinct GPU-contention issue remains).
**Introduced:** Unknown (the apply-race predates NACRE.2b).
**Resolved:** Not resolved. The 2026-06-25 empty-passes guard fixed a real adjacent defect (BUG-061) but did not stop this hang.

**Expected:** switching presets (incl. Gossamer) never hangs the app.

**Actual (session `2026-06-17T22-10-50Z`):** the render loop was healthy — 60 fps, `frame_gpu_ms` 0.13–1.5 ms, no `deltaTime` gap — through the **last recorded frame (9459) at `22:14:01Z`**, which is **one second after `session.log`'s last event, `preset → Gossamer` at `22:14:00Z`**. `features.csv` then stops while the stem-separation / orchestrator threads keep logging for ~30 s more → a **render-path hang** (main or GPU), not an analysis stall (cf. BUG-043, a freeze-then-lurch) and not a tap freeze (cf. BUG-058). Video was OFF (BUG-050), so the recorder's video path is excluded. Matt force-quit from Xcode **without hitting Pause**, so no thread stacks were captured.

**Non-reproduction (session `2026-06-18T13-57-23Z`):** Gossamer was applied **3×** (13:58:35, 14:00:13, 14:00:36) and rendered clean; the session ended with a normal `SessionRecorder finished` shutdown. So the hang is rare/intermittent, not a deterministic Gossamer defect.

**Reproduction steps:** unknown trigger. Lead: a `preset → Gossamer` switch under live load (continuous stem separation running) — possibly transient GPU contention between the stem-separation MPSGraph and Gossamer's first-frame render, or a preset-apply race.

**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-17T22-10-50Z/` (features.csv ends at frame 9459 / `22:14:01Z`; session.log last line `preset → Gossamer`); clean counter-example `2026-06-18T13-57-23Z`.

**Suspected failure class:** `concurrency` or `render-state` (a hang, not a crash).

**Verification criteria (when diagnosable):**
- [ ] **On the next recurrence, capture a stack BEFORE force-quitting.** A hang produces no crash log, so there is nothing to recover afterwards — the artifact has to be taken while the app is still wedged. Two routes, either is sufficient:
  - **Launched from Xcode:** hit Pause (⏸), then capture the Debug-Navigator thread stacks (main thread + any thread in Metal/MPSGraph). Add `Debug → Capture GPU Frame` if a GPU hang is suspected.
  - **Launched normally (the likely case for a live session):** from Terminal, `sample PhospheneApp 10 -file ~/Desktop/phosphene_hang.txt` — ten seconds of stacks for every thread, no Xcode needed. `spindump` works too but needs sudo. This is the same instrument that diagnosed the BUG-059 deadlock class.
- [ ] Root cause identified from a captured stack; regression guard added.

*Note (RECON.2, 2026-08-03):* the earlier framing of this criterion assumed an Xcode-attached session, which is not how the recurrence was hit. The `sample` route above is the one that will realistically be available.

**Manual validation required:** Yes — a hang is felt, and only a captured stack diagnoses it.


---

### BUG-058 — Mid-session output-device swap freezes the tap: `performReinstall` (CLEAN.1.5 / G1) doesn't recover; visuals freeze on a stale buffer (2026-06-17)

**Severity:** P3 (downgraded from P2 2026-06-17 — see §Update. RARE intermittent: the G1 device-swap recovery is robust in the common case; a freeze was seen once and not reproduced across 12 subsequent swaps).
**Domain tag:** audio.capture / resource-management (`SystemAudioCapture.performReinstall`, `DefaultOutputDeviceMonitor`)
**Status:** Open — **instrumented + largely validated. G1 device-swap recovery confirmed ROBUST (12/12, 2026-06-17).** The single freeze (`14-28-30Z`, un-instrumented build) was NOT reproduced; breadcrumbs remain in place to pin it if it recurs. Distinct from BUG-057: that's a wedged `coreaudiod` feeding *all* taps zero; this is a rare race in the tap recreate during an OS device transition.
**Introduced:** Unknown — CLEAN.1.5 (`DefaultOutputDeviceMonitor → performReinstall`, 2026-06-13) added the device-change recovery, but its G1 manual validation was never performed; this is its first real test, and it fails. Possibly a macOS-26.5 Core Audio behavior (tap recreate during a device transition).
**Resolved:**

### Expected behavior
Switching the macOS default output mid-session (e.g., Duet 3 → Mac mini Speakers) reinstalls the tap against the new device and visuals keep animating (a brief glitch is acceptable) — what CLEAN.1.5 / G1 promises.

### Actual behavior
On the swap the visualizer freezes and never recovers. Session `2026-06-17T14-28-30Z` (instrumented build, healthy coreaudiod): the tap worked ~39 s (RMS 0.06, `signal quality → green`), then at the switch **`raw_tap.wav` stops at exactly 39.1 s while the session ran ~134 s** — the **IO proc stopped firing entirely.** The render loop coasted on the last buffer for ~95 s → `features.csv` tail is **constant nonzero** (`bass=0.16956, mid=0.00565, treble=0.00073`, identical across the final frames) = the Waveform preset shows a frozen flat line. **No `reinstall via device-change` success/FAILED line**, and **no `audio signal → silent`** (the buffer isn't RMS≈0, so `SilenceDetector` stays `.active` → `.silent → reinstall` never arms either). Both recovery paths miss.

### Reproduction steps
1. Cold-start streaming (Spotify); confirm visuals animate.
2. ~20–30 s in: System Settings → Sound → Output → switch device (Duet 3 ↔ Mac mini Speakers).
3. Observe: visuals freeze on the last frame, no recovery; `raw_tap.wav` stops at the switch; `features.csv` tail constant.

### Session artifacts
`~/Documents/phosphene_sessions/2026-06-17T14-28-30Z/` (the failure; `raw_tap.wav` 39.1 s of 134 s, frozen-buffer tail) + `…T14-15-28Z/` (prior run that ended at/before the switch — tap healthy throughout, failure not captured).

### Suspected failure class
`resource-management` / `api-contract` (pending instrumentation). Leading hypothesis: `performReinstall` **fired and ran `teardownTapResources()` (→ the clean IO-proc stop at 39.1 s), but the tap RECREATE stalled/hung** during the device transition (a `createProcessTap` / `createAggregateDevice` / `startDevice` blocking on macOS 26.5), never reaching the success or catch log. Alternative: the `DefaultOutputDeviceMonitor` listener never fired. The os_log lines that would distinguish these are `.info` → not persisted (`log show` empty), hence:

### Instrumentation (step 1 — landed 2026-06-17)
Added `session.log` breadcrumbs (via the existing `onCaptureDiagnostic` sink) the os_log path lacked: the **`DefaultOutputDeviceMonitor` callback firing** (`device-change monitor FIRED`), and **each step of `performReinstall`** (`ENTER → tearing down` / `teardown done` / `tap created` / `aggregate created` / `IO proc created` / success / FAILED / `SKIPPED (not capturing)`). The last breadcrumb before silence pins the exact stall point. No fix code; breadcrumb-only on the non-SPM-testable device-change path.

### Update 2026-06-17 — G1 device-swap recovery validated ROBUST (12/12); freeze un-reproduced

Instrumented re-test (session `2026-06-17T14-54-49Z`): **12 rapid back-and-forth output-device swaps (Duet 3 ↔ Mac mini Speakers), all 12 recovered cleanly** — each logged `device-change monitor FIRED → performReinstall: ENTER → … → reinstall via device-change gen=N` completing in < 1 s, with the new tap immediately recapturing real audio (RMS 0.05–0.49); motion preserved through the last frame; `raw_tap.wav` continuous (67 s). A prior single swap (`2026-06-17T14-49-23Z`) also recovered. Tally: **`monitor FIRED` = 12, reinstall completed = 12, FAILED = 0.** So `DefaultOutputDeviceMonitor → performReinstall` (CLEAN.1.5) is sound — **the G1 manual gate passes.** The one freeze (`14-28-30Z`) ran on the pre-breadcrumb build, minutes after a `sudo killall coreaudiod`, so the leading explanation is a **transient `coreaudiod`-settling race** in the tap recreate, not a systematic defect. Left Open at P3 with the breadcrumbs live: if a freeze recurs, the last `performReinstall:` line before silence pins the stalling Core Audio call.

### Verification criteria
- [x] Instrumentation (step 1): breadcrumbs landed; the happy path is fully captured (session `14-54-49Z`).
- [x] Manual (G1): swap the output device mid-session → visuals stay live, ≥ 2 devices, both directions — **PASSED 12/12 (2026-06-17).**
- [x] No regression: cold-start streaming still animates; BUG-057 workaround unaffected.
- [ ] (Open, low-priority) Reproduce + pin the rare freeze, *if* it recurs.

### Related
- **The open G1 / CLEAN.1.5 manual gate** — this *is* that gate failing. CLEAN.1.5 has unit tests for the monitor mechanism (`DefaultOutputDeviceMonitorTests`) but the live device-swap was never validated.
- BUG-057 (sibling silent-tap; different mechanism — wedged coreaudiod / pure-zero, vs this frozen-buffer / IO-proc-stopped). The planned granted-but-silent **detector** must catch THIS state too (no *fresh* audio / IO-proc-stopped), not just RMS≈0.
  - **Detector landed 2026-06-17** (see BUG-057 §Fix increment): `PlaybackErrorBridge`'s freshness poll catches THIS Mode-B state — `InputLevelMonitor.frameCount` ceasing to advance while `.silent` never fires — and raises the `AudioStallOverlayView` card. This bug stays its own (the rare freeze itself is still un-fixed); the detector just makes the frozen state visible + actionable instead of a silent frozen frame.
- Surfaced 2026-06-17 during the G1 manual test (run right after the BUG-057 coreaudiod fix).


---

### BUG-056 — Local-file playback restarts the track from the top when the macOS output device changes (`LocalFilePlaybackProvider` AVAudioEngine teardown/restart, no resume-from-position) (2026-06-16)

**Severity:** P3 (local-file robustness/UX — no crash, no data loss; a mid-track output swap loses playback position. Annoying, not blocking.)
**Domain tag:** local-file / audio (`LocalFilePlaybackProvider`, AVAudioEngine)
**Suspected failure class:** `resource-management` (the `AVAudioEngineConfigurationChange` handler tears the player down and restarts at frame 0 instead of resuming).
**Status:** Open — observed 2026-06-16; **re-confirmed live 2026-06-18** (session `2026-06-18T13-46-10Z`) during the BUG-059 device-swap validation: several swaps each restarted the track from the top (the engine teardown/restart now always completes cleanly — BUG-059 fixed — so this restart is the remaining, expected behavior). Not yet scheduled — awaiting Matt's prioritization call (resume-from-position is its own increment).
**Resolved:** —

**Expected:** changing the macOS output device during local-file playback continues the track from its current position (a brief audio glitch on the reconfigure is acceptable).
**Actual:** on an output-device change the provider runs a full teardown (`provider.teardown` → removeObserver / player.stop / player.removeTap / engine.stop) and the player restarts from position 0 — the song starts over. The visualizer keeps running; only the audio restarts.
**Reproduction steps:** play a local file; mid-playback change the macOS default output (System Settings → Sound → Output, or ⌥-click the menu-bar volume). The track restarts from the beginning.
**Session artifacts:** `2026-06-16T21-32-50Z` — `session.log` shows `provider.teardown … player.stop … engine.stop` at 21:33:57 and again at 21:34:12 (two output swaps), each followed by a restart from the top.
**Verification criteria (for the fix):**
- [ ] On an `AVAudioEngineConfigurationChange` (output change), the provider reconfigures and **resumes from the saved frame position** rather than restarting at 0.
- [ ] Manual: swap output mid-local-file → playback continues (≤ a small glitch), not a restart.

**Note:** distinct from **G1** (the *system-tap* reinstall on the streaming path — `DefaultOutputDeviceMonitor` / `performReinstall`); local-file uses AVAudioEngine and never engages the tap, so a local-file output-swap does NOT validate G1.


---

### BUG-055 — Silent system-audio tap after a rebuild: `CGPreflightScreenCaptureAccess()` returns stale-`true` (gate passes) but macOS silently denies the re-signed binary's tap → app shows "ready", renders a flatline, no guidance (2026-06-16)

**Severity:** P2 (no crash/data-loss, but a total loss of the core function — no visuals on any streaming / `.systemAudio` session — presented as "ready" with **no actionable feedback**; cost a ~90-minute live-debug session and recurs on every dev rebuild. Not P1: a workaround exists (re-grant + relaunch) and the local-file path is unaffected.)
**Domain tag:** app.ui / permission (TCC "Screen & System Audio Recording") — capture path `SystemAudioCapture` (`AudioHardwareCreateProcessTap`)
**Suspected failure class:** `api-contract` (`CGPreflightScreenCaptureAccess()` returns stale-`true` after a re-signed rebuild — the gate trusts an unreliable preflight) + `pipeline-wiring` (no "granted-but-zero-signal" fallback detection).
**Status:** Symptom RESOLVED 2026-06-17 (detector, validated) — the filed defect (silent flatline reported as "ready," **no guidance**) is addressed: the silent-tap detector surfaces an actionable card with a "re-grant Screen & System Audio Recording, then quit + relaunch" step (Mode A — same validated path; commit `a0a9ded`, surface validated by screenshot). The durable root (stable signing so the grant persists across rebuilds — CLEAN.2.5b) remains open/blocked on no paid Apple membership; end users on a stably-signed build won't hit the re-grant at all. Per Matt, the card is a fallback — the end-state goal is **no** user-facing Terminal/Settings step (self-healing; see BUG-057 §Fix increment + `feedback_self_healing_over_manual_remediation`).
**Resolved:** 2026-06-17 — user-facing symptom via the silent-tap detector (`a0a9ded`). Durable signing recurrence tracked separately as CLEAN.2.5b.

**Expected:** when a live `.systemAudio` session is shown, the tap captures the default output and drives the visuals; if capture is actually denied, the app surfaces an actionable "re-grant Screen Recording" state — never a silent flatline reported as "ready."
**Actual:** after rebuilding the (dev-signed, hardened-runtime) app, streaming sessions render **no motion**. The tap installs cleanly (`raw tap capture started sr=… ch=2`) and `signal quality → red: no signal` fires, but `PermissionMonitor` (→ `CGPreflightScreenCaptureAccess()`, `PhospheneApp/Permissions/`) reports **granted**, so the gate (`ContentView`) lets playback proceed. macOS silently denies the actual `AudioHardwareCreateProcessTap` because the rebuilt binary's code signature no longer matches the prior grant — a **denied process tap returns zeros, not an error** — so the tap delivers pure silence. Reproduced with both the Apogee Duet 3 and the built-in Mac-mini Speakers as default output (audio audibly playing on the tapped device). `tccutil reset ScreenCapture com.phosphene.app` cleared **32 orphaned grants** — one per dev rebuild (the dev signature churns every build; hardened-runtime makes the match strict, but Debug churns too).
**Reproduction steps:** rebuild the app, launch, start a streaming session, play audio to the macOS default output → green UI, zero visuals. `raw_tap.wav` RMS=0.0, `features.csv` bass/mid/treble all 0.0. **Fix:** `tccutil reset ScreenCapture com.phosphene.app` → relaunch → grant "Screen & System Audio Recording" → **quit + relaunch** (the grant applies only on a fresh launch).
**Session artifacts:** `2026-06-16T20-58-31Z` (Apogee Duet default) + `2026-06-16T21-15-42Z` (built-in Speakers default) — both `raw_tap.wav` RMS 0.0, all features 0, log `audio signal → silent`. **Contrast** `2026-06-16T21-32-50Z` (a local file on the *same* broken build): green −1 dBFS + full motion — isolating the fault to the tap/permission, not the audio source (local files are file-direct AVAudioEngine and bypass the Screen-Recording gate per `ContentView` LF.4).
**Suspected failure class:** `api-contract` + `pipeline-wiring` (see above).
**Verification criteria (for the fix):**
- [ ] **Detection:** while a session is "ready"/playing and the tap reads ~0 RMS for > N s, the app transitions to an actionable "Screen Recording may be stale — re-grant" state instead of a silent flatline (wire the existing `signal quality → red: no signal` detector to this). Unit-testable.
- [ ] The gate stops treating `CGPreflightScreenCaptureAccess()` alone as proof of working capture (it is unreliable after a re-sign).
- [ ] **Manual:** after a rebuild with a stale grant, the app guides the user to re-grant rather than showing a dead session.

**Durable fix:** dev-signing re-signs every build, so the grant never persists → this recurs every rebuild; the root fix is **stable signing (Developer ID / notarization — CLEAN.2.5b, blocked on no paid Apple membership)**. Related: G1 (CLEAN.1.5 output-device handling) and the `signal quality → red: no signal` detector (BUG-026 domain). Note: a *separate* silent-tap cause is environmental output-routing (audio playing on a device the tap isn't bound to) — this BUG is the distinct, real defect where audio IS on the tapped device but the permission is silently denied.

**Detector fix increment — landed 2026-06-17 (pending Matt's manual UX validation):** the **Detection** criterion above is satisfied by the shared silent-tap detector (see BUG-057 §Fix increment) — `PlaybackErrorBridge` raises the `AudioStallOverlayView` card on sustained RMS≈0 (Mode A) while playing, with "re-grant Screen & System Audio Recording, then quit + relaunch" in the on-card fix ladder, instead of a silent flatline reported as "ready." The durable signing fix (CLEAN.2.5b) is still separate and still blocked. Mark this bug `Resolved` (the detector half) after Matt's manual UX validation of the card.


---

### BUG-054 — Key detection has never been accurate enough to use in playback (chroma algorithm is fundamentally resolution-limited) (2026-06-16)

**Severity:** P3 (non-load-bearing *today* — `estimatedKey` is a debug/UI display value + a fallback; nothing in orchestration or any preset consumes key, and presets drive from energy/deviation, not key. No fps/crash/playback-correctness impact. Sev would rise to P2 if/when a feature is built to *use* key. Matt may rerank). Filed 2026-06-16 after the BUG-053 work surfaced it (Matt: "key has never been correct for as long as Phosphene has tracked it"). Investigation + fix design done this session; **filed for later, not scheduled.**
**Domain tag:** dsp.key (MIR chroma / key estimation)
**Suspected failure class:** `algorithm` (the chroma front-end is resolution-limited by construction) + `calibration` (full-mix input, no harmonic weighting).
**Status:** Open — design complete, **not scheduled** (Matt's call: track for later). Distinct from BUG-053 (that was the live MIR ignoring the *tap rate*; this is the chroma/key *algorithm* being inaccurate even at the correct rate).
**Resolved:** —

**Expected:** the detected musical key matches the track's actual key on clear tonal material (with a confidence gate so it surfaces only when trustworthy). Realistic ceiling: ~70–85 % exact + ~90 %+ within a fifth/relative — never 100 %.
**Actual:** key is reliably wrong. Black Hole Sun (G major) read **F** in session `2026-06-16T16-52-09Z`. Root causes (`ChromaExtractor.swift`, `SessionPreparer+Analysis.analyzeMIR`):
1. **1024-point FFT → ~43 Hz/bin.** A semitone near middle C is ~15 Hz — *under half a bin* — so C/C♯/D below ~1 kHz fall in the same bins; the analyzer can't resolve which semitone owns the energy in the register where the key lives. The `minFrequency = 500 Hz` floor (`ChromaExtractor.swift:63`) sidesteps the worst of it but then reads key off harmonics ≥ 500 Hz, which smear across pitch classes (overtones land on octave/fifth/major-third).
2. **Linear FFT bins → log pitch is the wrong transform** — the field uses a constant-Q transform (uniform log-frequency resolution).
3. **Full-mix chroma** — drums/percussion (broadband) pollute it; no harmonic/percussive split, even though Phosphene already computes stems.
4. **No harmonic summation / spectral whitening.**
Krumhansl-Schmuckler template matching at the end is fine; the chroma front-end is the bottleneck. The offline per-track pass (`analyzeMIR`) uses the *same* 1024-pt full-mix `ChromaExtractor`, so the cached key is equally wrong. No metadata fallback in normal use: only `SoundchartsFetcher` returns a key (env-gated, off by default); iTunes/MusicBrainz don't carry key; Spotify's audio-features (key) endpoint is deprecated for new apps.

**Reproduction steps:** play any track with a known key (e.g. Black Hole Sun = G); read the `key=` line in `~/phosphene_diag.log` (the MIR's own estimate, not metadata-overridden). It is reliably off, independent of sample rate.
**Session artifacts:** `2026-06-16T16-52-09Z` (Black Hole Sun, true G, read F). A labeled validation set is a prerequisite for the fix (see below).
**Verification criteria (for the eventual fix):**
- [ ] A **labeled ground-truth set** (~15–20 tracks, known keys) added as a test fixture; report **exact-match %** + **within-a-fifth/relative %** before and after.
- [ ] Post-fix exact-match clears an agreed bar (target ~70 %+ exact, ~90 %+ tolerant) on that set.
- [ ] Display/use is **confidence-gated** — a low-confidence estimate shows nothing rather than a wrong key.

**Fix approaches (design from this session; key is a per-track value → spend compute once, offline; exploit Phosphene's stems + offline budget):**
1. **Tier 1 (cheap, partial):** in the offline key pass, feed the **drums-removed / harmonic stem** signal (stems already exist → free HPSS), bump to an **8192-pt FFT** (or add harmonic summation), aggregate over the whole clip; keep Krumhansl. Likely "never right" → right on clear tonal tracks.
2. **Tier 2 (proper):** **constant-Q transform** → harmonic-weighted pitch-class profile (HPCP) + spectral whitening → refined templates (Temperley / Albrecht-Shanahan) over the whole track — the librosa-`chroma_cqt` / essentia-`KeyExtractor` design, built in Accelerate (no Swift MIR lib; on-device constraint). The real fix.
Recommended sequencing: Tier 1 measured against the labeled set first; escalate to Tier 2 only if it doesn't clear the bar. Confidence-gate either way.


---

### BUG-051 — m3u playlist entries resolve to arbitrary paths with no extension/traversal guard (2026-06-15)

**Severity:** P3 (defense-in-depth — the consequence is bounded by the no-egress local-file path; realized harm in the current single-user/no-telemetry architecture is ≈ nil). Filed by CLEAN.2.4 (GAP-10 threat model, `docs/SECURITY_POSTURE.md` §6).
**Domain tag:** local-file / security
**Status:** Open — filed 2026-06-15, not fixed (CLEAN.2.4 is doc-only). Fix is its own small increment.
**Resolved:** —

**Expected:** a `.m3u`/`.m3u8` entry resolves only to a readable **audio** file under an expected root.
**Actual:** `M3UParser.resolveURL` (`PhospheneEngine/Sources/Session/M3UParser.swift:138-147`) resolves `file://`, absolute (`/…`), and relative entries with **no extension filter and no path-traversal guard** — a hostile playlist can name `/Users/you/.ssh/id_rsa` or `../../etc/passwd`. The entry is readability-checked (`isReadableFile`) and handed to AVFoundation, which **fails to decode** a non-audio file; the path is never read back to the attacker, and the local-file path has **no network egress**, so nothing escapes. Bounded, hence P3.
**Reproduction steps:** open a `.m3u` whose body lists a readable non-audio absolute path; observe the entry is resolved + readability-checked before the audio decoder rejects it (no allow-list short-circuits it first).
**Session artifacts:** n/a (static input-validation finding; verified by code read, see `SECURITY_POSTURE.md` §6 + §verification).
**Suspected failure class:** `api-contract` (the parser's resolve contract admits non-audio / out-of-tree paths).
**Verification criteria (for the eventual fix):**
- [ ] Automated: a `.m3u` listing a non-audio extension and a `../`-traversal path resolves to **zero** entries (or throws `noEntriesResolved`); valid audio entries still resolve (extend `M3UParserTests`).
- [ ] Manual: opening a normal `.m3u` of `.m4a/.mp3/.flac` is unaffected.


---

### BUG-036 — Heap allocations on the real-time Core Audio thread at three sites (FFTProcessor, AudioBuffer.latestSamples, SessionRecorder raw tap) (2026-06-09)

**Severity:** P2 (violates the standing "do not allocate in the Core Audio IO proc callback" rule on every callback of every session; priority-inversion / glitch risk under memory pressure rather than observed breakage).
**Domain tag:** audio.capture / performance
**Status:** Open (mostly fixed) — sites 1 + 2 fixed + **validated in production** (2026-06-17, `58a37c0`; session `2026-06-17T20-52-27Z` — no audible glitch, steady 60 Hz cadence, worst gap 84 ms). Site 3 (raw-tap) + the analysis hand-off **parked** as an accepted low-risk residual (re-open the ring rework only if a stall/glitch implicates it — BUG-043 is not recurring; Matt 2026-06-17). See Progress.
**Introduced:** structural — predates the rule's enforcement attention; the "zero-alloc" header comments in both DSP files are currently false.
**Resolved:** — (sites 1 + 2 done; bug stays open until site 3 + the hand-off land)

**Expected:** the IO-proc path allocates nothing (CLAUDE.md What-NOT-To-Do).
**Actual (all three verified on the IO-proc call path via `VisualizerEngine+Audio.makeAudioSampleCallback`):**
1. `FFTProcessor.swift:149,193` — `process()` allocates a fresh `magnitudes` array per call; `processStereo` allocates a fresh `mono` array (called at `VisualizerEngine+Audio.swift:114`).
2. `AudioBuffer.swift:148` — `latestSamples` does 2048 per-element ring reads (`UMARingBuffer.read(at:)` precondition + modulo each) + an allocating `append` loop **under the same NSLock the write path takes**, per callback (`VisualizerEngine+Audio.swift:111`). RMS over the same samples is also computed 3× per callback (AudioBuffer `:179`, SilenceDetector `:106`, InputLevelMonitor `:185`).
3. `SessionRecorder+RawTap.swift:28` — `Data(bytes:count:)` copy + `queue.async` closure allocation per callback for the first 30 s of every session (entire session under `PHOSPHENE_FULL_RAW_TAP=1`).
Related P3 (same rule, rarer path): `AudioInputRouter+SignalState.swift:45` — tap-reinstall scheduling (locks, `DispatchWorkItem` alloc, os_log interpolation) runs on the RT thread on silence transitions.
**Session artifacts:** `docs/diagnostics/CODE_AUDIT_2026-06-09.md` (Audio/DSP P2 section).
**Suspected failure class:** `resource-management` (RT-safety).

**Progress (2026-06-17, `58a37c0`) — sites 1 + 2 landed; site 3 + hand-off deferred to BUG-043.** The three named allocations split into two groups by whether they cross the audio-thread boundary:
- **Sites 1 + 2 (RT-thread-local) — FIXED.** `FFTProcessor` reuses a pre-allocated `magnitudesScratch`; a new zero-alloc `processStereo(interleaved: UnsafeBufferPointer)` mixes L/R straight into the windowed-sample scratch (no `mono` array); the array overloads delegate to it. `AudioBuffer.latestSamples(into:)` fills a caller-owned buffer (the callback reuses a pre-allocated `interleavedScratch`). All scratch is touched only on the single RT thread → no lock needed (cf. D-079's cross-core `tapSampleRate`). FFT output is byte-identical (pointer↔array bit-equivalence test + unchanged FFT/Chroma/BeatDetector goldens).
- **Site 3 (raw-tap `Data()` + `queue.async`) + the analysis hand-off (`Array(...prefix())` + `analysisQueue.async`) — PARKED (accepted low-risk residual).** Both cross the thread boundary. Making them allocation-free safely requires a pre-allocated ring drained by a persistent consumer (the "pre-allocated ring for raw-tap" fix below): an unbounded→bounded hand-off is a cadence/concurrency change that lands directly on **BUG-043**'s analysis-stall surface. The hand-off allocates every callback — a *continuous but low-impact* RT-rule violation — and the fix is a real concurrency redesign. With **BUG-043 not recurring** after sites 1 + 2 (the forcing function is gone), the cost/benefit doesn't justify the rework now (Matt 2026-06-17); re-open if a future stall/glitch implicates the remaining allocations. (Originally deferred to sequence *with* BUG-043 per the `036 → re-test → 043` ordering; the re-test came back clean, so it's parked rather than queued.)

**Verification criteria:**
- [x] Automated (sites 1 + 2): `FFTProcessorTests.fftProcessorStereoPointerMatchesArrayPath` + `…ReuseIsStable`, `AudioBufferTests.audioBufferLatestSamplesIntoMatchesAllocating` — pre-allocated members, pointer path bit-for-bit == array path (incl. short/partial-fill + ring-wrap), scratch reuse stable over 64 calls.
- [x] Manual (sites 1 + 2): no audible-glitch regression + healthy analysis cadence — session `2026-06-17T20-52-27Z` (Matt): median Δt 0.0167 s (60 Hz) over 25,017 audible frames / 8 tracks, worst gap 84 ms, no freeze-lurch. (The stricter os-allocator Instruments proof is optional given byte-identical output + green tests + this cadence — not pursued, Matt's call.)
- [—] Automated (site 3 + hand-off): pre-allocated ring + allocation-free hand-off — PARKED with the remainder (see Progress); not required while BUG-043 stays quiet.


---



---

### BUG-028 — Beat-grid live phase imperfect on ~half of tracks (felt "behind the beat / wrong downbeat") (2026-06-05)

**Severity:** P2 (musical-feel ceiling across every beat-coupled preset; not a crash. Bounds Nimbus's beat axis — see M7 r1 below).
**Domain tag:** dsp.beat (grid phase)
**Status:** Open — diagnosed; elevated to its own project per Matt (**D-145**). Scoping note: `docs/diagnostics/BEAT_GRID_LIVE_PHASE_PROJECT_2026-06-05.md`. **Not to be fixed by per-preset tuning, and not by another short-window live-tap iteration (FA #69 — premise retired).**
**Introduced:** structural — the cached `BeatGrid` is built from the 30 s preview and its phase is cross-capture-unstable on live audio (BSAudit.2; CLAUDE.md §Cold-Start Phase Contract).
**Resolved:** —

**Expected:** beat-coupled visuals land on the audible downbeat across the catalog.
**Actual (Nimbus M7 r1, session `2026-06-05T18-26-37Z`):** grids **lock** (`lock_state`=2 ~84 %) with the **right tempo** (grid-vs-drums BPM < 1 % on most tracks), but live **phase** is imperfect — `drift_ms` ~10–35 ms (mixed sign) and meter assumed simple (Money 7/4 logged `beatsPerBar`=2). Reads as "behind the beat / wrong downbeat" on roughly half the tracks; locks well when phase happens to align (Superstition verse).
**Suspected failure class:** `algorithm` (cached-grid phase derivation) — a *new premise* is required (human-tap reference / full-track local analysis / per-track manual calibration), chosen with Matt in the D-145 design session before any increment.
**Verification criteria:** deferred to the D-145 project.


---

## Known Limitations (external / by-construction — not actionable defects)

Reclassified at PUB.3 (2026-07-11, ultra-review): these are bounded by external
APIs or by-construction constraints, kept for reference so contributors don't
mistake them for open work. BUG-005's UX-copy criterion is the one item that
could close via a small increment.

*Reading note (RECON.2, 2026-08-03):* the three entry **bodies** below still carry
`**Status:** Open` and unchecked verification boxes from before the PUB.3
reclassification. **This section header wins** — they are not counted in the open
defect total and none is scheduled work. The bodies are deliberately left intact
rather than rewritten, because their verification criteria are exactly what would
have to be met *if* an external API ever exposes what they need (a `time_signature`
source for BUG-013 and BUG-001) — rewriting them to "closed" would throw away the
reopening condition. Read `Status: Open` there as "unsolved", not "in the queue".

- **BUG-013** · dsp.beat — no `time_signature` source (Soundcharts doesn't expose it); meter wrong on some odd-meter tracks
- **BUG-001** · dsp.beat — Money 7/4 stays REACTIVE on the live path (odd-meter ceiling)
- **BUG-005** · session.ux — Spotify `preview_url` null for some tracks (API-side; degrade path exists)

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
| `MemoryReporterTests` growth assertions | `phys_footprint` variance across system memory pressure states | Run with other apps quit; or skip with `SKIP_MEMORY_TESTS=1` |
| `PostProcessChainTests.test_fullChain_under2ms_at1080p` | GPU/CPU contention under the full parallel suite inflates a timed submit past the budget | Re-run in isolation to confirm before treating as a regression |
| `RayMarchPipelineTests.test_fullPipeline_under8ms_at1080p` | Same shape as above (wall-clock assertion around a GPU submit) | Re-run in isolation to confirm before treating as a regression |
| `StemSeparationPerformanceTests.test_separate_1SecondAudio_performance` | Same shape; MPSGraph submit under parallel load | Re-run in isolation to confirm before treating as a regression |

*(The three perf rows were added at RECON.2, 2026-08-03. They were declared "confirmed flake" during the BUG-080 investigation but never reached this table — so each run re-litigated them from scratch. **These are the known-flaky *shape*** — a single wall-clock sample around a GPU submit — that CLEAN.7.9→7.14 fixed elsewhere by asserting the **minimum of N warm samples** rather than one sample, or by removing the timing assumption entirely. Per the deterministic-over-budget-widening rule these three should get the same treatment rather than staying in this table; that is a small, well-precedented increment, not a mystery. Until then: a failure here is not evidence of a regression on its own.)*

**Resolved 2026-07-24 (TESTFLAKE.2)** — `SessionLifecycleGenerationTests.endThenRestart_staleOrphanDoesNotMutateNewSession` (never entered the table above — it failed on **every** full run, 3/3, while passing 3/3 in isolation in 2.7 s; the one suite TESTFLAKE.1's sweep missed). The test asserted the orphaned prep's *timing*: two 10 s `waitUntil` wall-clock polls plus a 2.5 s "sleep past 3 × 600 ms of session A's prep" gap. Under parallel load the case stretched to 73–89 s, the polls starved, and the assertions read session A's stale 3-track plan (`tracks.count → 3` vs 2) before session B's was installed. **The generation guard was verified correct first** (a load-only failure can be a real race): `streamingSessionGen`, the post-`await` staleness check, and every `currentPlan`/state write are all `@MainActor`-isolated with **no suspension point between check and act**, so check-then-act is atomic. Per the deterministic-over-budget-widening rule (CLEAN.7.9 → TESTFLAKE.1), the timing assumption is **removed, not widened**: `startSession` already returns with state + plan installed synchronously (so both polls were unnecessary — the tests now `await` it directly), and the 2.5 s sleep is replaced by awaiting session A's **actual** orphaned prep task, captured before `endSession()` drops the handle. The assertion is now the guard's promise — *whenever* the orphan fires, its completion is rejected — not *when* it fires. `SessionReadyWait` gained an `awaitPrepTask(_:)` overload for a captured handle, keeping the 120 s hang-cap race (a slip must not become a hang). Isolated 2.7 s → 0.042 s; green in 4 consecutive full-suite runs. Test-only, no production delta (`SessionManager` untouched). See `RELEASE_NOTES_DEV.md [dev-2026-07-24-164940]`.

**Resolved 2026-06-16 (CLEAN.7.14)** — `SSGITests.test_ssgi_performance_under1ms_at1080p` made contention-robust (it never entered the table above — it surfaced fresh under the full ~1479-test parallel `swift test` run, the same GPU-heavy parallel load the CLEAN.7.6 flash-safety suite added that exposed this whole flake family). It flaked **two** ways under contention, neither a real regression: (1) an `XCTest measure {}` block benchmarking the 1080p SSGI render **failed on relative standard deviation > 10 %** (XCTest's default bound; ~17.7 % observed) — pure variance; and (2) the real gate computed SSGI overhead as a **5-pair MEAN of (with − without) `Date()` timings**, which folds contention spikes straight into the average. Isolated, all 7 SSGI tests run in ~0.13 s. Per the deterministic-over-budget-widening rule (CLEAN.7.9/7.10/7.11/7.12), the sub-1 ms gate is **kept, not loosened**: the `measure {}` benchmark is removed and overhead is computed from the **minimum of 8 warm samples per path** — contention can only ADD latency to a GPU submit, so each path's min is its clean true-cost floor and `minSSGI − minBase` is the clean overhead estimate, immune to a few starved samples. The SSGI render path is untouched; test-only, no production delta. (The structural twin — the single-sample ICB frame-perf gate `test_gpuDrivenRendering_cpuFrameTimeReduced` — is fixed the same way in **CLEAN.7.13**, consolidated onto this same branch.) See `RELEASE_NOTES_DEV.md [dev-2026-06-16-e]`.

**Resolved 2026-06-16 (CLEAN.7.13)** — `RenderPipelineICBTests.test_gpuDrivenRendering_cpuFrameTimeReduced` made contention-robust (it never entered the table above — it surfaced fresh under the full ~1469-test parallel `swift test` run during the CLEAN.7.12 closeout). Structurally identical to the CLEAN.7.10 flake: a **single-sample `Date()` wall-clock assertion around one warm ICB frame submit** (blit + compute + render), run inside the parallel suite — a saturated GPU/CPU inflates the lone submit past the 2 ms budget (the case-level time was a benign 0.277 s; the *timed inner submit* blew the gate), while isolated it passes in ~0.37 s. Per the deterministic-over-budget-widening rule (proven on CLEAN.7.9, applied to this exact shape on CLEAN.7.10), the 2 ms gate was **kept, not loosened**: the assertion now takes the **minimum of 8 warm samples** — contention can only ADD latency to a GPU submit, so the min is the clean estimate of true cost and is robust to a few starved samples. The `measure {}` variance block is unchanged. The ICB renderer path is untouched; test-only, no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-06-16-d]`.

**Resolved 2026-06-16 (CLEAN.7.12)** — `UMABufferExtendedTests.test_concurrentWriteRead_noDataRace` made deterministic (it never entered the table above — it surfaced fresh under the full ~1479-test parallel `swift test` run during the CLEAN.7.6 flash-safety closeout, which added GPU-heavy parallel tests that raised pool contention). The test dispatched 200 trivially-fast, lock-free blocks (100 writes + 100 reads to a `UMABuffer`) and asserted a **fixed 30 s** `DispatchGroup.wait(timeout:)` returned `.success`; under contention the GCD thread-pool drain latency exceeded the deadline → `.timedOut` (observed 34.9 s), while isolated the whole class runs in 0.048 s. Per the deterministic-over-budget-widening rule (CLEAN.7.9/7.10/7.11), the deadline is **removed, not widened**: the test now `wait()`s with no timeout, returning exactly when the blocks drain — it cannot flake on elapsed time, and a genuine deadlock surfaces as a CI hang (same trade as CLEAN.7.11's `await …?.value`). Added a smoke-level post-condition — each writer wrote a distinct index, so after the barrier `buf[i] == Float(i)` for all i — catching gross corruption / lost writes; true data-race detection still requires TSan (per the file header). Test-only, no production delta (`UMABuffer` untouched). See `RELEASE_NOTES_DEV.md [dev-2026-06-16-c]`.

**Resolved 2026-06-15 (CLEAN.7.11)** — `ToastManagerTests.autoDismiss_afterDuration` removed from the table above. The test enqueued a `duration: 0.05` toast then slept a **fixed** wall-clock window (ratcheted 400 ms → 1000 ms and still flaking — CLEAN.2.3.8 closeout, 2026-06-15) before asserting `visibleToasts.isEmpty`; under @MainActor parallel-suite contention the auto-dismiss continuation could slip past the fixed window. Per the deterministic-over-budget-widening rule (CLEAN.7.9/7.10), the budget is **removed, not widened**: the test now `await`s the actual auto-dismiss `Task` to completion via a new `#if DEBUG` seam `ToastManager.dismissTask(for:)`, so it blocks exactly until the dismissal lands and races no deadline — **this is the fix the row prescribed**. Behavioural intent preserved — a finite-duration toast auto-dismisses; an `.infinity` one schedules no task (early `guard`). Test-only, no production delta (`ToastManager` dismiss logic untouched). See `RELEASE_NOTES_DEV.md [dev-2026-06-15-g]`.

**Resolved 2026-06-14 (CLEAN.7.10)** — `RayIntersectorTests.test_rayTrace_1000Rays_under2ms` made contention-robust (it never entered the table above — it surfaced fresh on the Mac mini during the CLEAN.1 Phase-0 re-confirmation, having passed 1469/1469 on both prior integration closeouts). The failing line was a **single-sample `Date()` wall-clock assertion around one GPU command-buffer submit**, run inside the ~1469-test parallel suite — about the most contention-fragile shape there is: a saturated GPU/CPU inflates any one submit past the 2 ms budget, while isolated the whole class incl. this test runs in 0.42–0.54 s (5/5 green). Per the deterministic-over-budget-widening rule (proven on CLEAN.7.9), the 2 ms gate was **kept, not loosened**: the assertion now takes the **minimum of 8 warm samples** — contention can only ADD latency to a GPU submit, so the min is the clean estimate of true cost and is robust to a few starved samples. The ray-intersector path is untouched by CLEAN.1 (last modified in render increment 3.3); test-only, no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-06-14-a]`.

**Resolved 2026-06-13 (CLEAN.7.9)** — `MetadataPreFetcherTests.fetch_networkTimeout_returnsWithinBudget` removed from the table above. The wall-clock budget — ratcheted 3 s → 8.25 → 15 → 45 s across prior sessions without ever converging (16.1 s / 22.8 s observed under the ~1460-test parallel suite during the CLEAN.1.x closeouts) — was replaced by a deterministic behavioural assertion: the merged profile carries the fast fetcher's `energy` but **not** the slow fetcher's `bpm` (excluded by the 1 s timeout). The outcome depends only on the 1 s-vs-10 s ordering (the 1 s timer's continuation is enqueued ~9 s before the 10 s one — contention delays both, never inverts them), not on measured elapsed time, so it cannot flake under cooperative-pool contention. Renamed `fetch_networkTimeout_returnsFastResultNotSlow`; adversarially proven to trap a timeout that lets the slow result leak (`bpm → 999` fails `== nil`, a ~10 s block not a hang). Test-only; no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-06-13-b]`.

**Resolved in the 2026-06-01 hardening pass** (made deterministic — no longer wall-clock-dependent, removed from the table above): `FirstAudioDetectorTests` (ManualDelay), `AppleMusicConnectionViewModelTests` (bounded-yield state polling; never required Apple Music.app — uses `MockAppleMusicConnector`), `SessionManagerTests` lifecycle suite (`waitForReady` safety deadline 3 s → 15 s). `PreviewResolverTests` carries no wall-clock waits or `URLProtocol` stubs in current source — the earlier "rate-limit timing / `.serialized` applied" note did not match the code and was dropped.

---

## Resolved (recent)

*(PUB.3 pruning pass, 2026-07-11: 24 resolved entries moved here from §Open; BUG-013/001/005 reclassified to §Known Limitations. rotate_docs.sh files these to KNOWN_ISSUES_HISTORY.md after 14 days.)*

---

### BUG-080 — Gitignored-asset propagation is broken at two points: fresh worktrees (and `main`) fail the engine suite (2026-08-03)

**P2 · build / test-isolation · RESOLVED 2026-08-03 — fix `2b36c34d`.** Filed P3, **widened to P2** the same day when the second gap surfaced. Found at FTR.1; not caused by it.

*Severity note:* P2 per `DEFECT_TAXONOMY.md` — "works for typical inputs but degrades noticeably for specific conditions." The verification harness passes in the one blessed checkout and fails everywhere else, including a fresh clone. No product impact; downgrade to P3 if the every-new-session tax is judged cosmetic.

**Expected.** `swift test --package-path PhospheneEngine` passes in any checkout prepared per the documented flow — `git worktree add` followed by `Scripts/link_fixtures.sh`.

**Actual.** Exit code 1. Two independent causes, discovered in sequence.

### Gap A — `link_fixtures.sh` does not cover the ML weights

PUB.2 moved the weights out of git (gitignored; shipped as the `ml-weights-v1` Release asset). `link_fixtures.sh` exists to bridge exactly that class of gap — its own header says *"Gitignored-but-needed paths that a fresh worktree would otherwise lack"* — but `linked_rel` covers only:

```
PhospheneEngine/Tests/Fixtures
docs/VISUAL_REFERENCES
docs/diagnostics
```

`PhospheneEngine/Sources/ML/Weights` is absent. The failure has two halves: the trailing filter would also reject the files.

```
| grep -E '^PhospheneEngine/Tests/Fixtures/|\.(jpg|jpeg|png|gif)$'
```

A `.bin` matches neither alternative, so adding the directory alone is insufficient.

| Weights directory | Primary | FTR.1 worktree (before workaround) |
|---|---|---|
| `Sources/ML/Weights/` | 176 | 4 |
| `.../beat_this/` | 162 | 1 |
| `.../panns_mobilenetv1/` | 147 | 1 |

479 gitignored files never arrive. Failures: `StemModelTests` (6), `StemSeparationPerformanceTests` (2), `WeightChecksumTests.test_completeness_{stem,beatThis,panns}` each reporting `onDisk → []`, `PANNsMobileNetV1Tests` `.tensorFileMissing("spectrogram_extractor_stft_conv_real_weight.bin")`, and the loveRehab 118-BPM port test.

### Gap B — the primary checkout is not a complete source

`PhospheneEngine/Tests/Fixtures/tempo/` — three licensed `.m4a` preview clips, gitignored at `.gitignore:63` ("Local audio fixtures for DSP.1 tempo capture (preview clips are licensed)") — **was absent from the primary checkout entirely**. The files existed only inside `.claude/worktrees/men-2a-kickoff-250b81/`, as real 1 MB files, presumably restored there by whichever session needed them.

`link_fixtures.sh` links *from* the primary. It cannot supply what the primary lacks. So:

- no worktree could ever obtain these fixtures, no matter how correctly prepared;
- the primary checkout itself fails the same gate;
- the script reports success (`linked N fixture(s)`) while propagating a hole.

`BeatThisFixturePresenceGate` fired loudly with a path-and-instructions message — **that gate is working exactly as QR.3 designed it**, and it is the only reason this surfaced rather than silently disabling the BeatThis regression surface.

Failures: `BeatThisFixturePresenceGate`, `BeatThisLayerMatch`, `LiveDriftValidation`, `BeatGridAccuracyDiagnostic — BUG-008`, `PreviewAudio content-hash + identity migration`. Several `LocalFilePlaybackProvider` concurrency tests (`routerChurn_…`, `deinitWhilePlaying_…`, `concurrentDoubleStart_…`) also failed at `0.001 s` immediately after tests that hung ~54 s on the missing audio — suspected cascade, not independent, but unconfirmed; BUG-078 is a real intermittent in that same area, so any that survive a green fixture run deserve their own look.

### Root cause, stated generally

`link_fixtures.sh` treats the primary checkout as an authoritative, complete source of gitignored material, and **nothing verifies that assumption**. The primary is simply whichever clone happened to receive the files. There is no manifest of required-but-gitignored paths, no provenance, and no check that the source has them before linking. Gap A is a stale allowlist; Gap B is the missing invariant underneath it.

**Reproduction.**

```
git worktree add .claude/worktrees/<name> -b <branch> main
cd .claude/worktrees/<name>
Scripts/link_fixtures.sh
swift test --package-path PhospheneEngine
```

**Evidence.** Three `Scripts/closeout_evidence.sh` runs, all at commit `935d77d3`, tree clean:

| Run | Failing lines | State |
|---|---|---|
| `2026-08-03T13:54:40-0500` | 81 | before any workaround |
| `2026-08-03T14:06:29-0500` | 81 | after `link_fixtures.sh` — **identical**, which is what proved the script does not cover Gap A |
| `2026-08-03T14:15:24-0500` | 21 | after 479 weight symlinks — XCTest half reports `0 failures`; remainder is Gap B |

Every reduction came from restoring a file. No code changed across any of the three runs.

**Failure class.** `test-isolation`, with a `documentation-drift` component: `link_fixtures.sh`'s header claims to cover the gitignored set and no longer does.

**Impact.** No shipped code path affected. The cost is **misdiagnosis** — a fresh-worktree run reads as a regression in whatever increment is under test, and `closeout_evidence.sh` honestly stamps `EVIDENCE: FAILURES PRESENT`, so a closeout stalls until someone traces it. With one worktree per session now the standing convention (D-212 process note), every new session pays this tax.

**Proposed fix (NOT implemented here — this is the diagnosis increment).**

1. Add `PhospheneEngine/Sources/ML/Weights` to `linked_rel` and widen the grep filter to admit it. (~2 lines; closes Gap A.)
2. **Verify the source before linking.** Check the primary actually holds each required gitignored tree and fail loudly if not, mirroring `BeatThisFixturePresenceGate`'s philosophy — a script that silently propagates a hole is the same failure class the gate was written to kill. (Closes Gap B.)
3. Consider a single manifest of required-but-gitignored paths, consumed by both `link_fixtures.sh` and the presence gates, so the two cannot drift apart again.

Per the Defect Handling Protocol, diagnosis and fix are separate increments unless Matt explicitly approves collapsing them. **Matt approved collapsing them for this defect (2026-08-03, in chat), so the diagnosis, the fix (`2b36c34d`) and the validation below all sit in one increment.**

**Verification criteria (written before the fix).**

1. *Automated:* in a worktree created fresh and prepared with the patched script, `swift test --package-path PhospheneEngine` exits 0, with `WeightChecksumTests.test_completeness_{stem,beatThis,panns}` and the whole `BeatThisFixturePresenceGate` suite green.
2. *Automated:* for every path in `linked_rel`, the count of gitignored files in the primary equals the count of links created in the worktree (479 weights + 3 tempo clips at time of filing).
3. *Automated:* with a required tree deliberately removed from the primary, `link_fixtures.sh` **fails** rather than reporting success — the Gap B regression test.
4. *Manual:* `Scripts/closeout_evidence.sh` in that worktree footers `engine=0` and does not print `EVIDENCE: FAILURES PRESENT`.

**Workaround applied (2026-08-03, not a fix).** 479 weight files symlinked into the FTR.1 worktree with absolute targets into the primary; the three tempo clips copied from the `men-2a-kickoff-250b81` worktree into the primary (restoring the canonical source) and symlinked onward. Both trees now report 72 fixture entries.

**FIX LANDED (2026-08-03, same day, pending validation).** `Scripts/link_fixtures.sh` rewritten around a declarative manifest:

```
<path>|<required>|<match-regex>
  PhospheneEngine/Tests/Fixtures      | yes | .
  PhospheneEngine/Sources/ML/Weights  | yes | .
  docs/VISUAL_REFERENCES              | no  | \.(jpg|jpeg|png|gif)$
  docs/diagnostics                    | no  | \.(jpg|jpeg|png|gif)$
```

- **Gap A closed** — weights are in the manifest, and the match filter is per-path rather than one global grep, so `.bin` passes where it structurally could not before.
- **Gap B closed** — `required=yes` makes an empty source tree a **hard error with a path-and-instructions message**, not a silent skip. The script can no longer report success while propagating a hole.
- **New `--verify` mode** — checks the primary is a complete source and exits non-zero if not, linking nothing. Runnable from the primary itself, so it works as a standalone gate (CI-ready).
- **Missing-on-disk files warn and set a non-zero exit** instead of `continue`-ing in silence (the old line 54).

Verified by hand on the primary at time of writing:

| Check | Result |
|---|---|
| `--verify` on a complete primary | exit 0; reports 3 fixture + 479 weight files |
| **Gap B regression:** required tree hidden, then `--verify` | exit 1, loud error naming the path |
| link mode run from the primary | exit 0, correct no-op |
| `bash -n` syntax check | clean |

**RESOLVED 2026-08-03 — fix commit `2b36c34d`.**

Closing gate: `swift test --package-path PhospheneEngine` run in `.claude/worktrees/ftr1` at commit `935d77d3`, tree clean.

```
Executed 225 tests, with 7 tests skipped and 0 failures (0 unexpected) in 69.842 seconds
✔ Test run with 1732 tests in 246 suites passed after 211.083 seconds.
```

Both halves green — the first fully green engine run on this material. Every failure named in Gap A and Gap B now passes: `WeightChecksumTests.test_completeness_{stem,beatThis,panns}`, `PANNsMobileNetV1Tests`, `StemModelTests`, the whole `BeatThisFixturePresenceGate` suite, `BeatThisLayerMatch`, `LiveDriftValidation`, `BeatGridAccuracyDiagnostic`, and the loveRehab 118-BPM port test.

**The `LocalFilePlaybackProvider` concurrency failures were cascade, as suspected.** `routerChurn_…`, `deinitWhilePlaying_…` and `concurrentDoubleStart_…` all pass once the audio fixtures exist. Nothing is owed to BUG-078 from this filing — it remains open on its own evidence.

**The three perf tests also passed cold**, closing the FTR.1 closeout's §2 caveat. `PostProcessChainTests.test_fullChain_under2ms_at1080p`, `RayMarchPipelineTests.test_fullPipeline_under8ms_at1080p` and `StemSeparationPerformanceTests.test_separate_1SecondAudio_performance` failed at `14:27:48` and passed at `14:15:24` on the identical commit with no code change; they pass here too. Confirmed flake — the timing-sensitivity class `DEFECT_TAXONOMY.md` already names P2 — not a regression.

**Verification criteria, scored honestly against what was actually run.**

| # | Criterion (written before the fix) | Result |
|---|---|---|
| 1 | Fresh worktree prepared with the patched script → suite exits 0 | **Green, with a caveat.** The suite is green, but that worktree ran the *pre-fix* script against an environment repaired by hand — its output still prints the old `link_fixtures: 0 fixture(s) linked` message. What is proven is that a complete environment makes the suite pass, i.e. the diagnosis was right and nothing else was wrong. What is **not** yet proven is that the patched script is what produces that completeness. |
| 2 | Per-path link count in the worktree equals the gitignored count in the primary | Met by hand (479 weights, 3 clips, 72 fixture entries in both trees); not re-measured through the patched script. |
| 3 | Required tree removed from the primary → script **fails** rather than reporting success | **Fully met.** Exercised during the fix: exit 1 with a loud error naming the path. This is the Gap B invariant and it holds. |
| 4 | `closeout_evidence.sh` footers `engine=0`, no `EVIDENCE: FAILURES PRESENT` | Met by the equivalent direct `swift test` run above. |

**Closing on the caveat.** Criteria 1 and 2 close for real at the first worktree created from `main` *after* `2b36c34d` merges — the first genuinely fresh preparation by the patched script. That is a five-minute check, not new work: `git worktree add`, `Scripts/link_fixtures.sh`, compare counts. **Append the result here when it happens**; until then this entry is resolved on a strong-but-indirect validation, and says so.

**Still open, tracked separately.** The **third instance** — `docs/VISUAL_REFERENCES` and `docs/diagnostics` empty in the primary — is not fixed by `2b36c34d`; the script now only warns about it. It is **not a regression to be undone**: the images were untracked on purpose at LFS.2 to stop the LFS bill and must stay out of history. What is owed is a decision about the *on-disk* half — re-curate locally (billing-neutral, `.gitignore:101-108` still excludes them) or retire the image-linking half and make the READMEs the authority. See the corrected THIRD INSTANCE note above.


**THIRD INSTANCE, found by the fix's own `--verify` (2026-08-03) — and it is a different kind of finding from Gaps A and B.** `docs/VISUAL_REFERENCES` and `docs/diagnostics` report **0 gitignored files in the primary**.

**CORRECTED 2026-08-03 (Matt).** The first draft of this note read as though the images had gone missing. They did not. **They were deliberately untracked at LFS.2 / PUB.2 to stop the Git-LFS bill** — the "stop the bleeding" change recorded in `PUBLISHING.md` §1 and `RUNBOOK.md` — and the LFS.3 history rewrite then removed them from reachable history. Verified here: **zero image blobs across all 2,348 reachable commits**, and `git lfs` is no longer installed on this machine. So their absence *from git* is correct, intended, and must stay that way.

**What is actually defective is the half of the system nobody updated to match.** D-211 extended `link_fixtures.sh` to propagate these images precisely *because* they are gitignored — the design is: images live on disk, never in history, and travel worktree-to-worktree by symlink. LFS.2 removed them from git and nothing re-established the on-disk copies or reassigned that job to a human. `.gitignore:101-108` still excludes every `.jpg/.jpeg/.png/.gif` under both trees, so **local on-disk copies are billing-neutral** — the machinery is correct and costs nothing; the larder is simply empty. The consequence D-211 named, *"silently degrades preset work rather than failing,"* has therefore been the standing condition everywhere rather than a worktree-only risk, and `docs/VISUAL_REFERENCES/<preset>/` holds READMEs describing images nobody can see.

**Restore path.** Not recoverable from the repo — re-curation from the sources each README cites is the only route back. Left `required=no` because promoting it would fail every run today, but it now warns loudly on every invocation.

**Open decision (narrower than first stated).** Either keep the `required=no` warning and re-curate locally when a preset session needs images, or drop both trees from the manifest entirely and rewrite the preset-session checklist's "look at the images" step to point at the READMEs as the authority. Not urgent, and **not** a reason to put images back under version control. Bears on FTR.2's reference curation, which per D-212 wants a low-fidelity set rather than the painterly one that left with Goldengrove.


**Related.** D-211 (the images half of this same gap, and the worktree-propagation reasoning), PUB.2 (weights → Release asset), QR.3 (`BeatThisFixturePresenceGate` — the gate that caught Gap B), D-212 process note (one worktree per session), BUG-078 (the concurrency intermittent the cascade failures may mask), BUG-079 (the other build-level gate that cannot currently run).

---

### BUG-071 — Fractal Fly-By: descent direction inverted + severe motion aliasing (2026-07-23)

**P1 · preset.fidelity / sdf-geometry / render-state · CLOSED wontfix — Fractal Fly-By RETIRED (FLY.14, D-201, 2026-07-25).**

**RESOLUTION / ROUND 14 (2026-07-25) — RETIRED after the FLY.13 live M7.** Matt: "deranged movement, very jittery, still passes through walls most of the time." Built the whole-frame temporal-coherence metric that should have existed in round 1: the image changes **~13 % every frame, uniformly**, and frames two apart are *more* different than adjacent ones (ratio 1.12) — the geometry teleports; this is not an aliasing/reprojection artifact AA could fix. Six consecutive frames share almost no structure. Root cause is the core mechanic: a fast scale-zoom through a self-similar Mandelbox reveals entirely new fold structure every frame, so nothing persists for the eye or MetalFX to track. Coherence needs ~3–4× slower travel (already rejected as "boring") and still shimmers; Horsthuis-class results need offline accumulation we can't afford at 7 ms/60 fps. A real, instrument-proven ceiling. Preset + FLY.12/13 corridor steering + the `presetSteer` uniform lane removed; MFX.1 + RMPERF.1 kept as general engine capabilities. Full record: D-201. **Process lesson: measure motion coherence before tuning — the peripheral metrics (jerk, mush %) that agreed with the work were the trap.** Historical rounds below.

**ROUND 13 / FLY.13 (2026-07-25) — STEERING REBUILT (avoid walls), measured on BOTH sessions to kill track-dependence.** Matt (rounds 10–12): "still goes through walls, still responds to some musical signals by jerking the camera side to side… screen blacked out towards the end." His call: "rebuild the steering — avoid walls." FLY.12's chase-the-far-opening law aimed at the distant channel mouth and grazed the near wall it was aimed past, and its EMA gain let a big target jump through in one frame → calm on one track, lurching on another (the "jerking"). Three track-independent guarantees replace it, each measured against BOTH live sessions (`…22-01-51Z`, `…22-42-35Z`) BEFORE Matt sees it: **(1) avoid-near-walls** — measure near-geometry proximity per screen half, ease toward the clearer side, keeping the camera centred rather than scraping. **(2) hard rate-limit** (`corridorMaxStep`, ≤ that offset change per frame) — a velocity cap physically cannot lurch and does not depend on the track; measured lateral-jerk median ~1.0 on both. **(3) density governor** (`presetSteer.z`) — the real "goes through walls" frames are moments where the scale-zoom travel plunges into a region dense in EVERY direction (no channel exists to centre in); measure whole-frame proximity → ease the shader's zoom base toward its open end (`FFB_ZOOM_OPEN`), pulling back to a coarser scale where channels reappear; eliminated all-wall "mush" frames (0 % on both, was periodic). Slowed `FFB_TRAVEL_RATE` 0.45→0.30. Perf p95 4.59 ms. **Honest residual:** robust and track-independent now, but at dense moments the governor's pull-back shifts the character toward "flying over ornate terrain" rather than "down a channel" — not confirmed to land the vision; Matt's live M7 is the gate.

**ROUND 6 (2026-07-24) — THE VALIDATION LOOP WAS THE FOUNDATION PROBLEM.** Matt, twice: "what you are seeing looks a lot nicer than what I was seeing." That is the real defect — **my offline checks did not reproduce the production renderer**, so every look conclusion for five rounds was drawn from a cleaner image than the live one. Divergences found and closed: (1) `renderSingle` built a NEW `RayMarchPipeline` per frame, so MetalFX reset to passthrough every time — every "I rendered frame 0 and it's clean" check **bypassed the TAA path entirely**; validation moved to the persistent-pipeline motion path. (2) The harness rendered at **1920×1080 while Matt watches a ~1067×750 window** — roughly half the pixels, hence far worse aliasing live; harness now defaults to the real window size (`FFB_W`/`FFB_H`), and at that size the tearing/pixel-crawl Matt describes is finally visible offline. (3) `FFB_RADIANS_PER_PIXEL` was a **hardcoded 1080p constant**, so the LOD cutoff kept detail finer than the pixels at any other window size; the engine now publishes the real value per frame in the free `cameraRight.w` lane, computed inside `RayMarchPipeline.render()` so harness and production cannot diverge on it. (4) The FrameBudgetManager can cut march steps at runtime (128→32); reproduced via `FFB_STEPMULT` and confirmed to punch **black holes** where rays exhaust steps — a garbling mechanism the harness never modelled. **STILL NOT CLOSED:** Matt reports the live view is worse than even the corrected offline render, so at least one divergence remains — the prime suspect is `applyAudioModulation` (per-frame fog / light-intensity / valence-tint from real audio), which the harness has never applied. **FLY.6 — the session-replay harness now exists** (`SessionReplayHarness.swift`): it reads a recorded session's own `features.csv` and drives the real `RayMarchPipeline.render` seam frame-by-frame with that track's actual audio, at the real viewport size, with `applyAudioModulation` applied. `applyAudioModulation` was MOVED from `RenderPipeline` onto `RayMarchPipeline` so the harness and production share one implementation — parity by construction rather than by discipline. Validated against Matt's `2026-07-24T14-08-17Z` session: replayed frames measure mean luma **38/255 (~15 %)**, reproducing the "still pretty dark" report from real data instead of synthetic silence. All future look judgements on this preset are made from replay output.

**ROUND 5 (2026-07-24) — round 4 made it WORSE; two follow-on causes.** Matt: "super dark, very garbled at the beginning. less watchable now than before." (a) **The darkness was caused BY the round-4 hue fix.** `ffb_jewel` was `0.50 ± 0.55`, a range of [-0.05, 1.05] — a large part of the palette clamps to BLACK. A fast hue hid that (every region averaged bright+dark); once the hue slowed to track structure, whole regions landed on the dark phase and went dead black. Floor raised to `0.58 ± 0.30` → [0.28, 0.88], never black. (b) **Round 4 fixed only ONE of two hue sites** — the emissive votives were still `trap.z*3.1 + trap.x*2.0`, FASTER than the 1.3 that caused the original speckle, so the recesses kept rainbow-speckling. Slowed to match. (c) Thin-film iridescence DISABLED: view-dependent colour is high-frequency chroma by construction, on exactly the thin ridge geometry that aliases worst; it is a "strongly preferred", not mandatory, trait. Measured at phase 0: mean luma 23.9 → 35.1, dead-black 8.5 % → 2.6 %, chroma noise 2.52 → 1.34. Perf 5.62 ms.

**ROUND 4 — THE FIRST DOMINANT CAUSE (2026-07-24, found by LOOKING at frame 0).** Matt: "a complete garbled mess at the beginning of playback." Rendering the opening frame and viewing it showed rainbow speckle on every edge — **colour-space aliasing**, not geometric. The hue driver was `trap.w * 1.3 + trap.y * 0.6`: orbit-trap values swing wildly between ADJACENT pixels on a fractal, so the cosine palette cycled several times within a few pixels and neighbouring pixels landed on unrelated hues. That is real signal, so **no temporal AA can ever resolve it** — which is why MFX.1 barely helped. Slowing to `0.30 / 0.15` makes colour track STRUCTURE instead of per-pixel; the speckle disappears and surfaces read as coherent jewelled stone. **Why the start of playback is worst:** playback begins at `phase = 0` where `zoom = 1.0` — the widest, most detail-crammed point of the octave (measured spatial-detail density 4.44 at frame 0 vs 2.79 mid-cycle), so the opening frame is the worst-case aliasing frame of the whole cycle. **Diagnostic that isolated it:** freezing the scene (`FFB_STATIC=1`, zero motion — the easiest possible case for TAA) showed TAA-on ≈ TAA-off (1.865 vs 2.028 frame-delta), proving MetalFX was not the lever. Also added a fractal LOD cutoff (stop iterating the DE once a fold is finer than the pixel footprint) — correct and kept, but a minor contributor next to the palette.

**ROUND 3 REGRESSION (2026-07-24, live session `2026-07-24T13-17-57Z`, "VERY glitchy, nearly unwatchable" — WORSE than before).** Cause: **MFX.1's camera jitter accumulated.** `applyJitter` read the LIVE `sceneUniforms.cameraForward`, added the sub-pixel offset, and wrote it back — and nothing resets `cameraForward.xyz` per frame (`applyAudioModulation` only writes `.w`). So each frame jittered the already-jittered vector. Two effects: the camera direction random-walked (~4.5°/min, measured), and — the damaging one — the offset reported to MetalFX (`currentJitter`, the per-frame Halton value) no longer matched the camera's ACTUAL cumulative offset, so the temporal resolve reprojected against a mis-aligned history and **smeared**. Temporal AA with a wrong jitter is worse than none. Fixed by capturing the unjittered basis once and always offsetting from it. **Why the harness missed it:** the probe reassigned `sceneUniforms` from the descriptor every frame, silently resetting the drift — a test/production divergence (FA #66). The harness now updates only the per-frame audio fields, matching `RenderPipeline+RayMarch`, and `test_jitterDoesNotAccumulate` locks it (validated by reintroducing the bug: drift 0.00037 → 0.0089, test fails).

**Expected:** a continuous fall INTO an ever-elaborating fractal cathedral; stable under motion.
**Actual (Matt live M7, session `2026-07-23T19-27-48Z`, Cherub Rock):** "Deeply glitchy. The camera is moving out / away vs. in… at the beginning the music response was chaotic and the preset looked super broken. As the camera moved backward the visuals started to stabilize… the surface looked pixelated but running."

**Artifacts.** `features.csv`: `accumulatedAudioTime` 0 → 8.15 over ~78 s ⇒ descent phase (×0.12) reached only **0.98** — one-way, never wrapped, barely moved. `bassAttRel` mean −0.18 / max 0.33 (fold driver small and safe — not implicated). Repro renders: a phase 0.08 vs 0.90 sweep (`FFB_PHASES` env on `test_descentContactSheet`) shows features **shrinking** as phase advances.

**Root causes.**
1. **Direction inverted** (`sdf-geometry`). `q = (p + c) * zoom` with zoom increasing maps every feature to `p = q₀/zoom − c`, collapsing them toward a vanishing point ⇒ a recede. **Fixed:** `q = (p + c) / zoom`, distance `DE(q) * zoom`. Verified by the same sweep now showing features grow.
2. **The scale descent targeted the fractal's ORIGIN — which is smooth.** A Mandelbox core has no detail at small scales, so falling inward runs out of structure and presses against a featureless wall (the inverted direction accidentally masked this: zooming *out* revealed more folds). **Partially fixed:** `FFB_ZOOM_TARGET` moved to a boundary point where folded detail persists at every scale (same reason a Mandelbrot zoom targets the boundary, never the cardioid middle). Composition improved from "smooth wall" to "canyon between ornate walls."
3. **Severe motion aliasing / moiré — ADDRESSED at MFX.1 (2026-07-23), live re-test pending.** MetalFX Temporal is now wired as an opt-in ray-march capability (`upscale: "metalfx_temporal"` + `render_scale`). Presets supply `scenePrevPosition`; for FD's analytic scale descent the previous-frame position is a closed form, so motion vectors are EXACT. Measured A/B on the identical motion path: **24.6 % less temporal high-frequency energy, and FASTER — p50 5.2 ms vs 6.6 ms full-res** (rendering at 0.65 and reconstructing saves more than the scaler costs). **Cost contract learned:** the scaler runs ~8.5 ms at 1080p if used 1:1, which alone blows the budget — it only pays for itself when it upscales. Residual shimmer remains (24.6 % is a real but partial reduction); whether it is now acceptable is Matt's live call. Original text follows — Full-res Mandelbox detail plus view-dependent thin-film iridescence alias badly under the fall. Mitigations applied (distance detail roll-off, thin-film confined to near ridges + roughened) reduce but do not eliminate it. **This is an infrastructure gap:** §A8 assumed MetalFX Temporal upscale for exactly this anti-aliasing and it is **not wired in this engine** (flagged at FD.1 pre-flight, proceeded anyway). Without temporal AA or supersampling a ray-marched fractal at this detail density will shimmer. Note the whole-frame `motion_gate.sh` spike metric does **not** catch high-frequency shimmer — it passed 0 spikes while the live render shimmered.

**Also open:** the descent rate was far too slow (0.12 → 0.45); the canyon framing shows a bright grey sky-gap where rays miss the bounded object.

**Verification criteria.** Automated: golden + route-coverage + perf ≤ 7 ms. Manual (required): Matt live M7 on a loud track — direction reads as falling IN, and a judgement on whether residual shimmer is acceptable or blocks cert.

**RESOLVED — identity trait (2026-07-23, Matt's call):** the "flying between and through, not falling into" miss is closed by **abandoning the fall and adopting a FLY-THROUGH concept**. A scale traversal converges on a fixed target, so it reads as approaching a place, not dropping through a world — three live tests said so, and the cited reference (Horsthuis) flies through these structures rather than dropping down them. The mechanic is unchanged; the concept moved to match what the geometry is good at. Shipped with it: `scene_backdrop: "dark"` (FLY.1) so the preset is **enclosed** — miss rays render a near-black void instead of the IBL backdrop, decoupled from `environment` so the gallery env still supplies ambient. Also fixed this round: a `fract()` hue discontinuity feeding the cosine palette, which put a rainbow contour seam on every edge and **aliased by construction** (no temporal AA can resolve a hard seam) — a large part of the reported "glitchy".

**Still open:** residual moiré on grazing high-detail surfaces. **Decision needed (Matt):** whether to fund further anti-aliasing capability (wire MetalFX Temporal — a scale-zoom *can* supply motion vectors — or supersample within budget), accept a softer/lower-detail look, or stop the preset.

---

### BUG-041 — FFO aurora flashes at track start: the drums-stem deviation driver overswings 1.2–3.3× during the per-track analyzer cold start (2026-06-10)

**Severity:** P2 (visible flashing in the first ~10 s of affected tracks on FFO; Matt flagged it on So What, There, There, and Lotus Flower in session `2026-06-10T14-55-32Z`). Same cold-start-deviation family as BUG-027/AGC2.4.1 (fixed for the FeatureVector band devs) — this is the STEM-side twin reaching the GPU through the aurora.
**Domain tag:** `dsp.stem` (deviation cold start) + `preset.fidelity` (FFO aurora intensity).
**Status:** **Fix landed 2026-06-10 (FBS.S2.2), then EXTENDED same day (FBS.S3.2)** after Matt's next read showed flashing at MID-TRACK timestamps too (session `17-50-56Z`: every flagged time coincides with an all-stem deviation burst, 3–30× track median — So What reached dev = 35). The track-start warmup was correct but insufficient in scope: the driver's response itself is now flash-proof — soft-knee input (`dev/(1+0.6·dev)`: musical values pass, bursts cap — 35 → 1.64) + asymmetric response (rise τ 0.45 s = a bloom, fall τ 1.2 s = afterimage), warmup gate retained. Gates: max per-frame output step ≤ 0.08 across the full So What series incl. the 35× burst; legacy-driver red arm proves the fixtures carry the defect. **CLOSED as stale 2026-08-03 (RECON.2) — Matt's explicit call during the production audit.** The PUB.3 flag (2026-07-11) proposed close-as-stale and asked for a one-line confirm; that confirm was given. Basis for closing: the automated gates have been green since 2026-06-10 (max per-frame output step ≤ 0.08 across the full So What series including the 35× burst, with the legacy-driver red arm proving the fixtures still carry the defect), the FBS Stage-2 live validation on 2026-06-11 is plausible covering evidence, and — the decisive part — Matt has run many FFO sessions since without the flash recurring. **This is a close-on-absence, not a close-on-proof:** no dedicated M7 was run against a worst-case hard-onset track start. Reopen immediately and without ceremony if the flash is ever seen again; the fixtures and the red-arm gate are still in place to re-measure it.
**Spawned:** the `dev = 35` upstream anomaly noted below is **no longer carried inside this entry** — it is filed as **BUG-084** so it survives this closure. *(Historical note: dev = 35 is anomalous — deviation primitives normally max ~3.4; a StemAnalyzer EMA divide-by-tiny is suspected upstream. The soft knee defends the aurora regardless, which is why closing this entry is safe while BUG-084 stays open.)*
**Introduced:** structural — `StemAnalyzer` resets per track; its per-stem deviation EMA re-seeds and `drumsEnergyDev` overswings during convergence. The aurora consumes it through the D-127 smoother (`auroraDrumsSmoothed`, τ ≈ 150 ms) — fast enough to pass multi-Hz cold-start swings as visible intensity flashes. The Stage-1 spike-driver replacement removed the OTHER flicker source (`f.bass` jitter into spike geometry), making this one prominent.
**Resolved:** —

**Expected:** the aurora arrives smoothly when a track starts.

**Actual (session `2026-06-10T14-55-32Z`, first 10 s of each track, 150 ms-smoothed driver):** flagged tracks — Lotus Flower smoothed peak **2.35**, So What **1.23**, There, There **1.37** (smoothed jitter 0.45–0.91/s); unflagged — Love Rehab peak 0.23, jitter 0.02/s. The flashing maps exactly onto the measured overswing. Steady-state (10–20 s) values are far lower. The pulse, spike strength, and the BUG-038-smoothed light multiplier are all calm in the same windows (measured — they are excluded as causes).

**Reproduction steps:** play the 6-track streaming playlist on FFO; observe the aurora in the first ~10 s of So What / There, There / Lotus Flower; compare `stems.csv` `drumsEnergyDev` early-window values against the 10–20 s window.

**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-10T14-55-32Z/` (`stems.csv` drums columns; the per-track table above).

**Suspected failure class:** `calibration` (deviation cold-start overswing, BUG-027 class) — consumed un-warmed by a brightness layer.

**Fix (FBS.S2.2):** a per-track quadratic warmup gate on the aurora's drums driver (`RenderPipeline.auroraDriverStep` — D-127 smoother × `warmup²`, 0 → 1 over 10 s, reset by the existing `resetAccumulatedAudioTime()` track-change hook). The gate is smallest exactly where the overswing peaks (2–6 s; Lotus's 2.35 spike lands on gate ≈ 0.16) and is ~1 once the analyzer has converged; steady state is byte-identical after 10 s. Measured on the session fixtures: early peaks 2.35/1.37/1.23 → **0.65/0.50/1.10**. Linear was tried and measured insufficient (Lotus still reached 1.23).

**Verification criteria:**
- [x] Automated (real-session replay through the production arithmetic, `AuroraTrackStartWarmupTests`): early-window (0–10 s) driver peak ≤ max(1.0, steady-state peak) on all three flagged tracks, red-arm reproduction of the flash on the two unambiguous ones, steady state byte-identical. *(Criterion AMENDED from the original "≤ 1.5× steady": Lotus's drums settle to ~0 steady — a steady-relative bound is unmeetable; So What's steady runs hot (1.64) so its early window is not anomalous. So What's perceived flashing is partly general drums-dev jitter on sparse jazz — a separate aurora-character question, noted, not chased here.)*
- [ ] Manual: Matt confirms the aurora arrives without flashing on So What / There, There / Lotus Flower track starts.

**Manual validation required:** Yes — felt visual artifact.

**Related:** BUG-027/AGC2.4.1 (the band-dev cold-start warmup — the fix pattern to mirror on the stem side or at the aurora's consumption point), BUG-029/AGC3 (the `f.bass` cold-start spike — same family, different path), D-127 (the aurora smoother), FBS (this became visible once the spike driver stopped flickering).

---

### BUG-075 — Volumetric Lithograph motion: rotary-dial spring-back + dual beat layer (2026-07-24)

**P1 · preset.fidelity / audio-coupling · ✅ RESOLVED 2026-07-24 (VL-PSY.5).**

**Actual (Matt live, session `2026-07-24T22-22-10Z`, Hummer):** "The motion is WEIRD… looks kinda like dialing on a rotary telephone, combined with pulsing on the beat." (He also liked the terrain-over-time morph, and the app crashed after ~3.7 min — see the crash note below, tracked separately.)

**Two causes, both confirmed from the session `features.csv`.**

1. **Rotary dial = the downbeat twist retracted.** VL-PSY.3's downbeat term was a transient envelope (`attack*decay` → rose 0→1→0 each bar), so the fold angle went forward then *returned to baseline* — forward-then-spring-back. Reconstructed angular velocity swung **−8.5 to +22.5 rad/s** with **2.7 % of frames spinning backward**. An accent on a rotation must be a monotonic ratchet (advance and hold), not a displacement that returns.
2. **"Pulsing" = a second, older beat layer left running.** The v9 drum-hit peak-lift (`kickPulse` → terrain height + palette flare + ridge strobe) was still live, firing on drum hits alongside the per-bar rotation twist — two beat-driven layers at different rates, the FA #67 "fighting itself" failure. Matt saw both at once ("dial COMBINED WITH pulsing").

**Fix (VL-PSY.5).** (1) Rotation downbeat is now a **monotonic eased ratchet**: `VL_ROT_KICK · (barsCompleted + stepEase)` off the cached grid's continuous beat position — advances one notch over each bar's first beat and holds, continuous across the bar boundary, can never decrease (reconstructed on the real session: **0 % backward**, angle monotonic). Deliberately **not** gated by `pulse_amp01` — multiplying an accumulated angle by a gate that falls in a quiet section would collapse it backward, the same retraction latent until a track has a quiet bar (a Spotify playlist will). (2) The v9 drum-hit peak-lift is **retired** — `kickPulse` and `accentFB` held at 0 — so the downbeat drives exactly one thing. The `accumulatedAudioTime` terrain morph Matt liked is untouched.

**Verified on the real session** via `SessionReplayHarness` (rows 900–1080, past grid-lock): motion gate **0 spikes, 0 frozen, max 1.68× median**. Goldens byte-identical (the synthetic regression fixtures set no beat position or drum stems, so they cannot see this class of change — real-session replay is the only gate that can, which is why VL-PSY.2/.3 slipped). Perf 10.7 ms p95, unchanged.

**Known residual:** a one-time ~24 rad/s velocity spike at the BeatGrid install (~12 s in, beat index snaps 3→7 = a 1-bar ratchet in one frame). It is a single startup event, not recurring; guarding it needs per-frame state the shader lacks. Logged, not fixed — re-evaluate if it reads as a visible snap in a live session.

---

### BUG-074 — Volumetric Lithograph M7 "a convulsing mess"; music-driven symmetry order (2026-07-24)

**P1 · preset.fidelity / audio-coupling · ✅ RESOLVED 2026-07-24 (VL-PSY.3).**

**Expected:** a psychedelic terrain flight whose geometry folds *with* the music.
**Actual (Matt live, session `2026-07-24T16-24-58Z`, Cherub Rock, chain `clean`, 59.9 fps):** "visual quality is lower and the music response is TERRIBLE, creating a convulsing mess. I dislike the look, but I REALLY dislike the motion."

**Root cause — a category error, not a tuning error.** VL-PSY.1/.2 drove the kaleidoscope's **symmetry order** (`pModPolar`'s repetition count) from audio: the vocal/energy swell moved it and every downbeat snapped it. Reconstructed from the session `features.csv`:

- swell-driven order swung **3.01 → 9.00** once stems were live — six orders;
- single-frame jumps up to **4.8 orders**; 9.6 % of frames changed >0.1 order;
- the beat snap fired **2.67 ×/second** at 171 BPM.

Two structural faults compounded it. (1) **Order is integer-valued.** `angle = 2π/order` only tiles the circle cleanly at whole numbers; at order 3.47 the last wedge does not close. Driving it continuously swept *through malformed geometry* every frame. (2) **Order is the least bounded parameter in the shader** — it re-maps every point in the world, so animating it convulses the whole frame rather than moving a feature.

Two supporting faults from the audio hierarchy. **Per-beat, not per-bar:** the downbeat used `pulse_phase01` directly (every beat) — exactly the D-154 Ferrofluid lesson ("a per-beat punch reads as a robotic metronome"), whose envelope VL-PSY.1 copied while leaving the lesson. **Hierarchy inversion:** the continuous driver `f.mid_att_rel` measured **0.009** on this track, while the dev fold-sweep fixture drove it 0→1 — so the beat accent became the only motion, the failure the audio-data-hierarchy rule exists to prevent. The synthetic fixture is *why this reached M7*; the `SessionReplayHarness` (FLY.6, built for this exact class) would have caught it, and was not used.

**Fix — turn the tube, don't rebuild it.** A physical kaleidoscope is a *fixed* set of mirrors that you rotate. So:

- **Symmetry order FIXED at 6** (whole number, never animated) — the stage.
- Ported hg_sdf **`pR`** (2D rotation) and rotate the domain before the polar fold. Rotation is an **isometry**: preserves distance, adds no Lipschitz cost, cannot open a seam, and every intermediate state is a valid kaleidoscope — smooth by construction, not by tuning.
- Rotation angle = `VL_ROT_BASE·time + VL_ROT_SWELL·accumulatedAudioTime + VL_ROT_KICK·downbeatTwist`. The swell term feeds an **angle** off an already-integrated energy signal, so a noisy per-frame swell mathematically cannot produce a jittery angle. Idle term keeps it turning at silence (D-037) — which incidentally fixes the VL.1 "frozen at silence" finding.
- Downbeat twist gated to **beat 0 of each bar** (`pulse_beat_index mod beats_per_bar`), attack 0.20 (D-157).

**Verified on the real session** via `SessionReplayHarness` (real `features.csv` through the live render seam, real viewport, real dolly): motion gate **0 spikes, 0 frozen, max 1.32× median** — against the VL-PSY.2 signal that swung six orders with 4.8-order single-frame jumps. Rotation speed chosen by Matt from a 3-speed real-audio GIF comparison (0.55 rad/s).

**Fidelity (Matt: "visual quality is lower")** — a real regression from the BUG-073 perf fix. Warp restored 2 → 3 octaves; full restore (4-octave warp + 5 terrain octaves) measured 13.5 ms, over the 12 ms gate, so partially restored at **11.4 ms p95**. Stated as partial, not claimed as whole.

**Follow-up ✅ RESOLVED (VL-PSY.4, 2026-07-24): replay-harness camera-parity gap.** `cameraDollySpeed` defaulted to 0 and was set by the app target (`VisualizerEngine+Presets`), which the engine test target cannot import — so `SessionReplayHarness` rendered every dollying preset with a **static camera**. Harmless for Fractal Fly-By (dolly 0), silently wrong for VL (the flight is its identity). **Fixed** by moving dolly speed into the sidecar: `PresetDescriptor.sceneDollySpeed` (`scene_dolly_speed`, default 0), set to 5.0 in `VolumetricLithograph.json`. `applyPreset` and `SessionReplayHarness` both seed `cameraDollySpeed = descriptor.sceneDollySpeed` — one source of truth; the app-side `switch desc.name` and the `REPLAY_DOLLY` env stopgap are both deleted. Confirmed: VL replays with its forward flight, no env var (session `2026-07-24T22-01-51Z`, 60 frames — terrain flows toward the camera).

---

### BUG-073 — Volumetric Lithograph at 1.0 fps after the VL-PSY.1 rebuild (2026-07-24)

**P1 · preset.performance / renderer · ✅ RESOLVED 2026-07-24 (VL-PSY.2).**

**Expected:** VL renders at the catalog's usual ray-march cost (v9.4 measured 7.6 ms p95 at Matt's window size).
**Actual (Matt live, session `2026-07-24T14-47-41Z`, Cherub Rock):** "the screen is black, waiting for the preset to display… roughly 8 seconds… very choppy and moving much too slow."

**Evidence.** Session `features.csv`, per-preset median `deltaTime` (chain verdict `clean`, so this measures the right thing):

| Preset | Frames | Median dt | FPS |
|---|---|---|---|
| Waveform | 35 | 16.8 ms | 59.5 |
| Staged Sandbox | 140 | 16.7 ms | 59.9 |
| **Volumetric Lithograph** | 46 | **986.6 ms** | **1.0** |

Staged Sandbox held 59.9 fps **in the same window**, through the same real-time stem separation — so this was VL, not the machine and not GPU contention. The "8 seconds of black" and the choppiness are the same fault: at ~1 fps the first frames simply take that long to appear.

**Root cause.** `warped_fbm` is two-level domain warping — **7 × fbm8 ≈ 56 Perlin evaluations per call** — and `Utilities/Noise/DomainWarp.metal`'s own header states: *"Use per-hit or per-vertex only."* VL-PSY.1 called it **twice** inside `vl_foldDomain`, which is reached from `vl_terrainNoise` → `vl_heightAt` → **`sceneSDF`**. `sceneSDF` is evaluated on every march step (~128) plus 4 tetrahedral-normal taps and 3 AO taps — so ~112 × ~135 ≈ **15,000 Perlin evaluations per pixel**. The documentation that would have prevented this was in the file being called.

**Measured (`VLBudgetProbeTests`, M2 Pro, p95):**

| | 1067×750 (Matt's window) | 1920×1080 |
|---|---|---|
| v9.4 baseline | 7.6 ms | 14.7 ms |
| VL-PSY.1 (defect) | **1120.1 ms** | — |
| VL-PSY.2 (fixed) | **9.4 ms** | 21.9 ms |
| Lumen Mosaic control | 0.44 ms | 0.92 ms |

**Fix.** (a) warp → `fbm3D(_, 2)` per component, 4 Perlin evals instead of 112 — the warp's job is a low-frequency displacement to break the mirror tiling's identical cells and never needed octave detail; (b) `VL_SDF_STEP_SCALE` 0.35 → 0.55 — step scale is a direct cost multiplier, and `pModPolar`/`pModMirror2` are **isometries** that add no Lipschitz cost, so only the (now much smaller) warp gradient needed headroom; (c) `VL_FBM_OCTAVES` 5 → 4. Octaves 3 was tried and reverted — below SHADER_CRAFT's ≥4 floor the render went soft and airbrushed, a quality regression for ~1 ms.

**Not fixed, recorded honestly.** VL remains the most expensive preset in the catalog: 21.9 ms p95 at 1080p (≈46 fps) against a 60 fps target. **v9.4 was already 14.7 ms there** — VL has never met the ~5 ms SHADER_CRAFT budget or its own declared `complexity_cost.tier2` of 2.0. The sidecar now carries the measured numbers (22.0 / 30.0) so the Orchestrator schedules against reality, and `VLBudgetProbeTests` gates at 12 ms as a **regression** guard rather than an aspiration that would fail on day one.

**Also fixed (same report, separate cause).** "Moving much too slow" was not purely the frame rate: `VL_NOISE_TIME_SCALE` was 0.015, tuned in v3.2 for the *superseded naturalistic* direction where a slow boil was the point. Against the measured `accumulatedAudioTime` rate (~0.1 units/s) the terrain phase advanced 0.0014/s — visually frozen. Raised 10× to 0.15. Camera dolly 1.8 → 5.0 u/s: at 1.8 the flight crossed a 20-unit fold cell every ~14 s, which reads as hovering, and the flight is VL's identity.

### BUG-072 — app test runner cannot launch while PhospheneApp is running (2026-07-23)

**P1 · build.infrastructure · ✅ RESOLVED 2026-07-23 (BUG072.1).** Not a machine fault and not an Xcode/macOS regression — **a running instance of the app under test blocks the XCTest host launch.**

**Root cause.** `PhospheneApp/Info.plist` sets `LSMultipleInstancesProhibited = true` (added at `[U.11] Spotify: fix OAuth callback single-instance` — the `phosphene://` URL-scheme callback must route to the one running instance). `xcodebuild test` launches the test *host*, which is `PhospheneApp.app` itself, via `IDELaunchServicesLauncher`. When any `com.phosphene.app` process is already running — even one launched from a different DerivedData path — LaunchServices refuses the second instance and the launcher fails with the generic `IDELaunchErrorDomain Code=20` / "The LaunchServices launcher has returned an error". `build` and `build-for-testing` succeed because neither launches anything.

**Why it looked machine-wide.** The stray instance is a *user-session* app, not a build artifact, so it survived across checkouts, worktrees, DerivedData hashes, `lsregister -f -R -trusted`, and bundle delete+rebuild — every remedy aimed at the build products, none at the running process. Unified log for 2026-07-23 shows `PhospheneApp` PID 35320 launched 15:47:07 and last active 18:19:18; **every** `xcodebuild test` inside that window failed at runner launch (16:22:18, 16:27:52, 16:29:58, 16:30:40, 16:31:06, and the 16:47/16:53 runs — `xcresulttool` reports `failedTests: 1, passedTests: 0` for 16:47). Runs after that process exited pass.

**Reproduction (A/B/A, 2026-07-23 20:38–20:44, sdk macosx26.5, Xcode 26.6 / 17F113, macOS 26.5.1 / 25F80).** No app running → `** TEST SUCCEEDED **`, 403 tests in 70 suites, exit 0 — three consecutive runs (primary checkout sandboxed, primary unsandboxed, worktree). `open …/Debug/PhospheneApp.app` (PID 80729) → same command, same checkout, `** TEST FAILED **`, exit 65, verbatim "Could not launch “PhospheneAppTests”", zero tests. Quit the app → `** TEST SUCCEEDED **`, exit 0.

**Remediation (no app-side code change).** Quit PhospheneApp before running the app test suite:

```bash
osascript -e 'tell application "PhospheneApp" to quit'; pkill -x PhospheneApp
```

`LSMultipleInstancesProhibited` is deliberately kept — removing it would break OAuth callback routing (U.11) and would let a test-host instance and a live session contend for the system-audio tap. The repo-side fix is diagnostic, not behavioural: `Scripts/closeout_evidence.sh` Step 2 now detects this exact signature (non-zero exit + "Could not launch “PhospheneAppTests”") and annotates the evidence block — **"BUG-072 — not a test regression. PhospheneApp is running; quit it and re-run."** when a `PhospheneApp` process is live, and **"Runner launch failed with no PhospheneApp running — unlike BUG-072. Investigate."** when it is not. This re-arms the merge gate: a stray app instance can no longer masquerade as a genuine app-test regression, and a launch failure with *no* app running is explicitly flagged as a different, unexplained defect.

**Suspected failure class:** `environment-interaction` (a product Info.plist policy colliding with the test harness's launch mechanism).
**Verification criteria (written before the fix):** (1) the A/B/A above — launching the app flips a passing suite to exit 65 and quitting it flips back; (2) both annotation branches emit the correct line, exercised against a synthetic log with and without a live `PhospheneApp`; (3) `bash -n Scripts/closeout_evidence.sh` clean. All three met.

---

