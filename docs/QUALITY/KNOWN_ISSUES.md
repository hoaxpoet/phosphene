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

*(Merge note, RECON.9, 2026-08-03 — `origin/main` moved 12 commits while this pass was
in flight and landed three defects of its own. **BUG-081** (app beachball, genuinely open)
joins the table below; **BUG-082** and **BUG-083** were already resolved when they landed,
so they went straight to §Resolved under the convention above rather than being indexed as
open. That parallel session hit the same number collision from the other side — its notes
record a 080 → 082 renumber — and this branch renumbered its own new entry to **BUG-084**
for the same reason. BUG-081 and BUG-060 are the same hang class; they are cross-linked.)*

*(Progress pass, 2026-08-07 — **two entries left §Open, both fully resolved**: **BUG-079**
(release-config test build; the DBN.2 budget it was hiding measures 17.9 ms in release against a
50 ms plan figure) and **BUG-078** (the `AVAudioPlayerNode` teardown trap — root-caused as a
concurrent-`start()` overwrite, fixed in `f68efb67`/PR #62, closed on Matt's live local-file
session `2026-08-07T19-10-25Z`). Nothing else changed state. The working order for what remains
is in [`ENGINEERING_PLAN.md`](../ENGINEERING_PLAN.md) §Immediate Next Increments item 5 —
**sorted by whether the work is doable, not by severity label**, because most of the remaining
P1/P2 headline items are blocked on an artifact that only a live failure can produce and cost
nothing while they wait. The one method note worth carrying: BUG-078 sat for a week on "nobody
has captured the trap" while 25 matching `.ips` reports sat in
`~/Library/Logs/DiagnosticReports/`. **Before filing another sighting of an intermittent crash,
read the crash reports already on disk.**)*

*(Audit pass, 2026-08-26 — §Open was carrying **twelve entries whose own bodies said they were
fixed**: BUG-086, BUG-089, BUG-090, BUG-092, BUG-093, BUG-094, BUG-095, BUG-096, BUG-097,
BUG-098, BUG-099, BUG-101. All twelve verified against the tree (fix commit on `main`, and for
the preset entries the sidecar/shader source) and moved out. Six went to §Resolved; the six with
the oldest resolutions were **rotated early** to `KNOWN_ISSUES_HISTORY.md` — verbatim, the same
move `Scripts/rotate_docs.sh` makes at 14 days — because moving all twelve into §Resolved would
have put it at 90 KB against its 50 KB DOC.6 budget. §Open is now 20 entries, and every one of
them is unfinished work. One factual correction landed in place: **BUG-088**'s "three undeclared
reads" are not reads — see the entry.)*

| ID | Sev | Domain | One-liner |
|---|---|---|---|
| BUG-106 | P2 · **FIXED + LIVE-CONFIRMED 2026-08-26 (BUG106.1)** — `ml_forced=0` across a 25 ms/frame 4K session; only the felt half (Matt's eye on stem timing / new stutter) is outstanding | ml.dispatch / calibration | **`MLDispatchScheduler`'s budget is a hardcoded 14/16 ms with no resolution term, so at 4K the gate can never open.** `recentMaxFrameMs` is the WORST frame of the window and 4K's median was 17.6 ms in BUG-100's own session, so every stem dispatch defers to the 1.5–2.0 s ceiling and force-fires — against a 2.0 s stem period. Jank avoidance never happens and stems run ~a period late at 4K. ⚠ **Not** BUG-100's mechanism: the PERF.15 VL session was flat across 172 s at 4K while permanently over the same budget. Needs Matt's call between "stems on time" and "jank-free" at 4K. |
| BUG-103 | P2 · open; intermittently kills the whole parallel engine suite (the regression gate) | audio.playback / test-infrastructure | **The parallel engine suite dies with an uncaught NSException from `-[AVAudioPlayerNode play]` — console: `com.apple.coreaudio.avfaudio: 'player did not see an IO cycle'` — thrown inside `LocalFilePlaybackProvider._startLocked()` on a racing-start test thread.** `play()` reports this state as an Objective-C exception, not a Swift error; the crashing tests drive `provider.start()` from raw `Thread.detachNewThread` threads (`try?` cannot catch an NSException), so the exception unwinds off the thread and aborts the entire test process — SIGABRT, no failing test line, same suite-level presentation as BUG-078. **Fourteen `.ips` on 2026-08-25 alone (11:19–17:05), every one the identical stack:** `_startLocked()` → `-[AVAudioPlayerNode play]` → `AVAudioPlayerNodeImpl::StartImpl` → `NSException`; throwers span `LocalFilePlaybackStartRaceTests.rescheduleRacingTeardown…` (11), `SessionLifecycleChurnTests.concurrentDoubleStart…` (2), and `SessionLifecycleChurnTests.completionCallbackVsStop…` (1). **Passes in isolation** (`swift test --filter SessionLifecycleChurn`), fires only under full-suite parallel load — and it is **pre-existing, baseline-verified at merge `8cbf936a` twice** (RECON.14's check, plus a first-hand clean-worktree run at that commit while filing; found at RECON.14 while running closeout evidence). NOT the BUG-078 trap: that was `StopImpl`/dealloc `dispatch_sync` on `CommandQueue` (SIGTRAP); this is `StartImpl` at play-time (SIGABRT). Same family — AVAudioPlayerNode lifecycle under parallel scheduler load. The throw site is the SHIPPED local-file start path (and `resume()` carries a second, unproven `play()` site), so the app-facing form would be a hard crash — P2 by BUG-078's rationale. Detail below |
| BUG-102 | **P1** · open, blocks the beat-sync benchmark | test.groundtruth / dsp.beat | **BeatBench's reference for `money` and `bleed` is at a metrical level Matt does not trust, and the repo already contradicts itself about it.** Both carry `status: metrical_review` — the GT.2 pipeline's own unresolved-disagreement flag — and on both, BOTH independent reference annotators say the TAPS are the octave-off side: librosa and madmom each report *"reference is double the tapped pulse (×2.01)"* for money and *"reference is half the tapped pulse (×0.51)"* for bleed. `money.groundtruth.json`'s own `meter_note` says *"beats tapped at HALF the bar pulse"*. **Matt, 2026-08-19: "I would not trust my tapping on these tracks, especially Bleed."** ⚠ **The contradiction is already committed:** BUG-076's body states bleed's ~115 BPM is *"correct — matches madmom 115.0, librosa 115.0, drums-stem 115.1"* — a THIRD independent source — while `bleed.groundtruth.json` says the truth is 226.72 and BeatBench scores bleed F 0.61 / CMLt 0.03 against that. **Consequence: every number scored against these two references is untrustworthy at the metrical level**, which is most of suite 2 and *all* of suite 4 (bleed is its only track). Not a code defect and NOT fixable by editing the JSON (`beatbench` skill: ground truth changes only through tap + reconcile). Needs re-annotation or arbitration. Evidence: `docs/diagnostics/FT31_METRICAL_LEVEL_2026-08-19.md`. *(Filed as BUG-101 on 2026-08-19 and renumbered to BUG-102 at merge — a parallel session took 101 for the Volumetric Lithograph perf defect the same day.)* |
| BUG-100 | P2 · evidence-only; **3rd non-reproduction 2026-08-26 with instruments in — GPU-working-set hypothesis FALSIFIED (4 % of budget, flat)**; one untried reproduction left (a Stave-containing 4K session); **not a preset defect** | app.performance / sustained-load | **The app degrades under sustained 4K rendering, and it is the machine or the frame loop, not the preset that happens to be on screen.** Matt's Stave M7 (`2026-08-19T17-01-15Z`) reported *"performance slowed over time, which led to some choppiness"*. Measured over a contiguous 70 s at 3840×2160: `frame_cpu_ms` **17.4 → 43.6** and `frame_gpu_ms` **2.9 → 11.7**, while the app's OWN CPU work stayed flat — `encode_cpu_ms` 12.9 → 15.2, `renderframe_cpu_ms` 9.8 → 11.0. Same work, less delivered. **Three hypotheses were falsified before filing:** (a) Stave accumulating — an offline soak of 1920 frames at 4K is flat at 22.3 ms with no drift; (b) the dispersion fan opening over the track — `waveformOccupancy` is flat at 0.081–0.095 across the whole segment, r(GPU, occupancy) = **−0.11**; (c) preset-specific — the degradation **persists into the next preset** (Witchlight `frame_cpu` 24.4 at 4K, against Stave's own 17.4 early) and partially recovers after a 2.16 MP interlude. ⚠ **A second finding sits inside this one:** `encode_cpu_ms` is **15–16 ms at 4K** — essentially the entire 60 fps budget spent on CPU encode before any GPU work — and it scales with resolution (9.1 ms at 2.07 MP). CPU encode should not scale with pixel count; that is worth its own look and is probably the more tractable half. Thermal throttling of the Mac mini under sustained 4K is the leading remaining explanation for the rest, and cannot be confirmed from the recordings — it needs `powermetrics` or equivalent alongside a session |
| BUG-091 | **P1** · instrumentation landed 2026-08-17; awaiting one reproduction | app.session / pipeline-wiring | **A single local file is selected, preparation succeeds, and NO PLAYBACK EVER STARTS — the session runs with every audio field exactly 0.0.** Matt, 2026-08-17. Measured on `2026-08-17T17-19-19Z`: 1262 frames over 84 s of render clock, and `playback_time_s` / `track_elapsed_s` / `accumulatedAudioTime` / `bass` / `mid` / `treble` / `pulse_amp01` / `beatPhase01` each hold **exactly one distinct value, 0.0**, for the whole session. Preparation is healthy — stem-cache hit, BeatGrid installed (94.1 BPM, 47 beats), plan built. **The discriminator is a diff against the working local-file session 1.5 h earlier (`16-19-13Z`, same file, same OS build):** the working run logs `WIRING: provider.start INSTANCE` and an AVAudioEngine node tap (`TAP_BUFFER: requested=1024 delivered=4410 → 10 Hz`) and NO process tap; the failed run has an identical preparation sequence with `provider.start` **absent**, an unexplained 8 s gap, and then `TAP: startCapture → createProcessTap` — the SYSTEM-AUDIO path — installed twice. `resetStemPipeline caller=other` has exactly one call site (`handleLocalFileReady`), so that function ran and cleared all three of its guards, then never reached the router start. **Root cause NOT asserted** (BUG-061's rule): the strongest candidate is the `catch` around `audioRouter.start(mode:.localFilePlayback)`, which logs to `os_log` only and calls `endSession()` → `currentSource = nil` → `startAudio()`'s LF.4 guard misses → the tap is installed and `stopInternal()` tears the provider down. **Unconfirmable from the artifacts: the app's `lfLogger` output is not retained** (`log show --predicate 'subsystem == "com.phosphene.app"'` over the window returns zero lines), which is itself the reason an 84 s silent session left no trace of its cause. Instrumentation for exactly that is now in (see below). Detail below |
| BUG-085 | P1 · HANG.1–2 complete 2026-08-05; remains open | renderer / app.hang | **App intermittently hangs hard in `CAMetalLayer.nextDrawable`; window unresponsive, force-quit required.** The live stack proves a main-thread drawable request blocked at 0 % CPU after healthy frames, but the cause remains unknown; direct render-path leakage, the capture hook, preset-swap skip, inflight semaphore, GPU completion, display sleep, and occlusion have been ruled out. **HANG.1 instrumentation is merged to `main` via PR #37 (`c54a2e7c`)**. HANG.2 completed a full-track control plus a 10 min 36 s Witchlight soak with 34,811/34,811 drawables balanced and no stalls or imbalances, refuting a deterministic per-frame leak but not identifying the intermittent owner. **THE INSTRUMENTED CAPTURE NOW EXISTS (2026-08-05, session `2026-08-05T21-21-03Z`, Fractal Tree / Cherub Rock)** — and every lifecycle counter is BALANCED at the moment of the hang: `drawable=12045/12045`, `unique_presented=6012/6012`, `command_completed=6012/6012`, `failures=0`, `unpresented=0`, one request outstanding (`pending=frame:6013,site:mesh.descriptor`). The app held ZERO drawables and CoreAnimation still would not vend one, which independently confirms HANG.2's soak: there is no app-side leak, and the owner is outside the app. Two captures 98 s apart are byte-identical on those counters — a PERMANENT block, not a long stall. See the detail section. |
| BUG-081 | P2 | app.hang | **3 instances now** (2026-08-03 ×1, 2026-08-04 ×2). | **App beachballed ~78 s into session `2026-08-03T22-54-06Z` and needed a force-quit; no `.ips` exists** (force-quit produces none) and `session.log` ends mid-normal-operation with no fatal. **Evidence-only — no root cause asserted.** What the capture DOES establish: the renderer was healthy to the last frame — steady 60 fps, Fractal Tree at **0.18 ms GPU against a 0.7 ms budget**, no degradation trend across 3756 frames; background ML load rising but modest (`stem_analyzer_ms` 0 → 3.4). **Ruled out by test:** FTR.2's shader overflowing the mesh primitive limit via a bad `branch_count` — no non-finite values in the capture and `branch_count` never exceeds 59 against the 63 ceiling. A frozen UI with a live render loop points away from the preset, but that is inference and BUG-061's rule forbids acting on it. **Same class as BUG-060** (force-quit hang, render loop died, no stack captured, never reproduced) — two instances now, both blocked on the same missing artifact. **Next evidence:** `sample PhospheneApp 10 -file ~/Desktop/phosphene-hang.txt` run DURING the beachball, before force-quitting |
| BUG-087 | P2 · **partial fix 2026-08-13 (10 → 16.4 Hz); ≥40 Hz NOT met — audio arrival rate is the ceiling, not slicing** | audio.capture / calibration | **Local-file playback runs the whole MIR chain at 10 Hz where streaming runs it at 51 Hz — a 5.1× rate loss on the primary development session type.** `LocalFilePlaybackProvider` asks for `installTap(bufferSize: 1024)` (≈47 Hz) and AVAudioEngine ignores it, delivering **0.1-second** buffers instead — 4414 frames measured at 44.1 kHz, 4808/4810 at 48 kHz. `processAnalysisFrame` runs once per audio callback with no time gate, so the callback rate *is* the analysis rate: every `FeatureVector` field — bands, deviation primitives, `beatPhase01`, centroid, flux, mood inputs — updates at 10 Hz on local files. Proven a fixed *duration* rather than a frame count by the rate-independence discriminator (both sample rates land on 0.1 s). This is the same 10 Hz the FTR program hit from the preset side. Diagnosis only — no fix code. Detail below |
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
| BUG-036 | P2 | audio.capture / performance | Heap allocations on the real-time audio thread (three sites) |
| BUG-028 | P2 | dsp.beat | Beat-grid live phase imperfect on ~half of tracks |
| BUG-077 | P3 | dsp.beat / api-contract | **`BeatGridResolver.snapToBeats` diverges from the Beat This! reference post-processor** — the reference moves *every* downbeat prediction to the closest beat unconditionally; we discard any candidate beyond `snapFrames = 2` (40 ms). Found at DBN.1 while auditing the resolver against the paper. **Currently harmless and NOT the cause of the low downbeat F** — measured, 100 % of candidates survive the gate (median distance 0.0 ms), so nothing is being discarded today (the real cause is a near-degenerate downbeat *stream*, see `docs/design/DBN_DECODER_SPEC.md` §2.1). Filed because it is a genuine spec-fidelity divergence of the D-077 class that will bite the moment downbeat timing loosens — e.g. on a track whose downbeat peaks sit a frame or two off the beat. Fix is one comparison; do it in DBN.3 when the resolver is being touched anyway, not as a standalone change |


---

## Open

---

### BUG-106 — FIXED (BUG106.1): the ML dispatch gate compared against a hardcoded 14/16 ms, so at 4K it could never open (2026-08-26)

**Status: fixed 2026-08-26, pending one live 4K confirmation.** Matt chose **(a) stems on time**
the same day. The budget now follows the session's own median frame time with the tier constant
as a floor — `max(floorMs, median × 1.5)`, `MLDispatchScheduler.budgetMs`. 1080p is unchanged
(median ≈ 8 ms → the floor wins, so the gate behaves exactly as it did at the only resolution it
ever worked at); a steady 25 ms 4K session now budgets 37.5 ms and dispatches instead of
deferring; a 60 ms spike inside that same session still defers. The threshold is now a deviation
from what this session delivers rather than an absolute millisecond count — the same correction
the audio side made for deviation primitives (D-026 / FA #31).

**Original status: root-caused statically, fix was a product decision.**
Found while working BUG-100; filed separately because it is a defect on its own terms whether or
not it turns out to be part of that entry's degradation.

**Expected.** `MLDispatchScheduler` (D-059) holds the ~142 ms MPSGraph stem separation until
recent frames are inside the render budget, so ML inference does not land on a frame that is
already struggling. Deferral is the exception; a clean window is the norm.

**Actual, at any 4K render target.** The gate is inoperative — it can only ever defer, then
force-dispatch. The chain is static and each link is in the tree today:

1. `VisualizerEngine+Stems.swift:192` — `let budgetMs: Float = self.deviceTier == .tier1 ? 14.0 : 16.0`. **A constant. No resolution term.**
2. `MLDispatchScheduler.decide` requires **every** frame in a 20–30 frame window to be ≤ that budget.
3. The number it compares is `FrameBudgetManager.recentMaxFrameMs` — the **worst** frame in the window, itself `max(cpuFrameMs, gpuFrameMs)` (`FrameBudgetManager.swift:207`).
4. At 3840×2160 the *median* frame in BUG-100's own session was **17.6 ms rising to 44.9 ms** — so the worst frame in any window is never ≤ 16 ms.

⇒ every dispatch defers in 100 ms steps until `pendingForMs` crosses the ceiling
(2000 ms tier 1 / 1500 ms tier 2), then force-fires anyway. **Against a 2.0 s stem period**
(`stemSeparationPeriodSeconds`), so deferral consumes 75–100 % of the period: the next dispatch
is requested at about the moment the previous one is forced. The jank avoidance never happens,
and every stem update at 4K is roughly one whole period later than designed — which compounds
with **BUG-086**'s structural stem latency rather than replacing it.

**Reproduction.** Static; no session needed. Any 4K fullscreen session is the live form — with
the BUG100.1 instrument in, `GPU_PRESSURE … ml_forced=N` climbing by ~one per 2 s is this defect
running.

**Suspected failure class:** `calibration` — a threshold that was correct for the only resolution
the app had when it was written, and was never made a function of the target it describes.

**⚠ What this does NOT explain, stated up front.** It is tempting to hand this to BUG-100 as the
mechanism. **One recorded session refutes that on its own:** the PERF.15 Volumetric Lithograph
run held **flat across 172 s at 4K with p50 ≈ 31 ms** — permanently over the same 16 ms budget,
so forced dispatch was happening there too, and nothing degraded. Forced ML dispatch is therefore
**not sufficient** to produce BUG-100's ramp. Treat the two as separate until a session with
`ml_forced` recorded says otherwise. (This is the BUG-090 failure shape: a mechanism that
predicts the direction of an effect is not an explanation of its magnitude.)

**The fix is a product decision, not an engineering one.** At 4K the app cannot have both:

- **(a) Stems on time** — scale the budget to the real frame target (the vsync interval, or the measured median), so the gate opens normally at 4K. Stem-driven visuals stay current; the 142 ms inference lands on frames that are already over budget, so 4K may show occasional stutter.
- **(b) Jank-free** — keep the fixed budget. 4K stays smoother, and every stem-driven behaviour stays a beat behind — which is what happens today, undocumented.
- **(c) Resolution-aware policy** — (a) below some pixel count, (b) above it.

Recommendation was **(a)**, and **Matt chose (a) on 2026-08-26**. One correction made during
implementation: deriving the budget from the *display's refresh interval* — what the
recommendation actually said — would not have worked. At 60 Hz that interval is 16.7 ms, so a
4K session at 17–45 ms still never clears it and the gate stays shut. The budget has to follow
what the renderer actually delivers at this resolution, which is why the shipped form is
`max(tierFloor, sessionMedian × 1.5)`.

**Verification criteria (written before the fix).**
- [x] A live 4K session logs `ml_forced` **flat** (normal dispatch) after the fix, where before it climbed ~one per 2 s. **CONFIRMED — session `2026-08-26T22-04-58Z`:** 3840×2160, Witchlight, 82 s in one preset at one resolution, `frame_cpu_ms` p50 **25.1–25.8 ms** throughout — i.e. permanently over the old 16 ms constant, the exact condition that used to shut the gate. Every one of the 10 `GPU_PRESSURE` lines reads `ml_forced=0 ml_last=dispatchNow`. The gate was genuinely exercised: `STEM_SEPARATION` fired every 2.0 s at 270–474 ms inference across the whole session, and all four stem energies are non-zero on all 6,545 frames.
- [x] A 1080p session is unchanged — the tier floor decides there, proven by `budget_at1080p_isUnchangedByTheFloor` (median 8 ms → budget stays 14/16, and an 18 ms frame still defers).
- [x] Unit: a 4K-shaped history (median 25 ms, worst 27) returns `.dispatchNow` under the derived budget, and the same window against the old 16 ms constant still returns `.defer` — the case proves it bites. A genuinely janky 4K window (worst 60 ms) defers. `budget_atFourK_steadySessionDispatchesInsteadOfDeferring`, `budget_atFourK_genuineJankStillDefers`.
- [x] The median is robust to one hitch (a mean would raise the bar the next dispatch is judged against): 29 × 25 ms + one 200 ms hitch → median 25.0, max 200. `recentMedianFrameMs_isRobustToASingleHitch`.
- [ ] Manual (musical feel): stem-driven presets at 4K read *with* the music rather than behind it, and Matt's eye on whether any new stutter is acceptable. ⏳

**Related:** BUG-100 (found during it, NOT established as its cause — see above), BUG-086 (stem
latency, compounds), D-059 (the scheduler's rationale), BUG-090 (the reasoning trap this entry
declines).
### BUG-103 — Parallel engine suite dies on an uncaught NSException from `AVAudioPlayerNode.play()`: 'player did not see an IO cycle' (2026-08-25)

**Severity:** P2 · **Domain tag:** audio.playback / test-infrastructure · **Status:** Open — diagnosed to the throw site from on-disk crash reports; the AVFAudio-internal trigger condition is a hypothesis. No fix code (evidence-before-implementation).
**Introduced:** Pre-existing — reproduces at merge `8cbf936a` with no other changes, verified twice independently on 2026-08-25: the RECON.14 baseline check, and a first-hand full-suite run in a clean worktree at that exact commit while filing this entry (crash at 17:00, `.ips` `…-170015`). First *filed* here; the class was previously visible only as BUG-078's SIGTRAP sibling.

P2 by BUG-078's rationale: only ever observed killing the *test* process, but the throw site is the shipped local-file start path — `LocalFilePlaybackProvider._startLocked()` — so the app-facing form would be a hard crash during local-file playback start. Process impact is real even at P2: it takes down the whole parallel suite run (the regression gate) intermittently, presenting as a suite-level abort with **no failing test line**.

#### Expected behavior

`swift test --package-path PhospheneEngine` completes; a provider `start()` that cannot begin playback surfaces as a thrown Swift error (which the racing tests already tolerate via `try?`), never as process death.

#### Actual behavior

The test process dies with SIGABRT (`abort() called`) from an uncaught Objective-C NSException. Console output at the kill shows `com.apple.coreaudio.avfaudio: 'player did not see an IO cycle'`. Intermittent, but frequent under full-suite parallelism on 2026-08-25: **fourteen `.ips` reports in one day** (11:19–17:05), across repeated RECON.14 closeout runs, two baseline checks, and the BUG103.0 evidence run. Passes in isolation (`swift test --filter SessionLifecycleChurn` — clean). **Both manifestations can occur in one run:** the BUG103.0 evidence run (17:02–17:05) failed `completionCallbackVsStop_abbaShape` on its 5 s watchdog at a `provider.start` step AND then died — its swift-testing helper (procLaunch 17:03:31) aborted at 17:05:15 with the same `StartImpl` stack, thrower `rescheduleRacingTeardown…` (`.ips` `…-170525`, the fourteenth). RECON.14's "crashed **or failed**" phrasing covers both faces of the same stall; the evidence script's extracted summary line came from the XCTest half and shows how the kill hides behind a passing-looking count (the BUG-078 exit-code-without-failure lesson again).

#### The mechanism, read from the stack (established)

All twelve reports carry the **identical** `lastExceptionBacktrace`:

```
+[NSException exceptionWithName:reason:userInfo:]
AVAudioPlayerNodeImpl::StartImpl(AVAudioTime*)
-[AVAudioPlayerNode play]
LocalFilePlaybackProvider._startLocked()          ← LocalFilePlaybackProvider.swift:327
closure #1 in LocalFilePlaybackProvider.start()   (inside lock.withLock)
LocalFilePlaybackProvider.start()
closure … in <racing-start test>
__NSThread__block_start__                          ← raw detached thread
```

Three facts compose into the process kill:

1. `_startLocked()` runs `try engine.start()` then `player.play()`. `engine.start()` failures are Swift-catchable; **`play()` reports failure as an ObjC NSException** — AVFAudio's `StartImpl` guard for a player asked to start when the engine has not completed an IO cycle.
2. The crashing tests drive `provider.start()` from **raw `Thread.detachNewThread` threads** with `try?` — which catches Swift errors only. No frame on a raw thread can catch an NSException.
3. An NSException unwinding off a pthread with no handler terminates the process. Hence SIGABRT with zero test failures recorded — the BUG-078 presentation (exit-code-without-failure), different signal.

**Which test the runner names is not load-bearing.** The 11/2/1 split (`rescheduleRacingTeardown_neverArmsACommandOnAReleasedNode` / `concurrentDoubleStart_serializesWithoutDeadlock` / `completionCallbackVsStop_abbaShape`) reflects which racing-start test's thread threw; RECON.14's console tails additionally attributed crashes to `transportChurn_…`, `completionCallbackVsStop_…`, and `onFileEnded_…` while they were in flight in the parallel set. The authoritative attribution is the `.ips` exception backtrace, and it is `_startLocked()` in all fourteen retained reports — the churn tests included: the 17:00 report's thrower is `completionCallbackVsStop_abbaShape`'s watchdogged thread.

**The first-hand reproduction adds a sequencing observation (one run — treat as observed-once, not the mechanism).** In the 17:00 crash, `completionCallbackVsStop_abbaShape` first FAILED its 5 s watchdog on `provider.start cycle 4` ("main-thread-hang class … stuck thread is leaked"), the suite moved on (`onFileEnded_queueAdvanceChurn` had started, per the console), and THEN the process died with the exception thrown from that test's watchdogged `provider.start` thread. So in this instance the sequence was: `start()` stalls > 5 s under load → the watchdog abandons and leaks the thread → the leaked thread eventually reaches `player.play()` on an engine that never began cycling → uncaught NSException. The stall-then-throw shape favors candidate (a) below (IO-thread starvation), and means the watchdog's deliberate thread-leak policy — correct for reporting hangs — leaves a live thread positioned to kill the process minutes later.

#### What is NOT established

- **Why the engine has not seen an IO cycle at `play()` time.** Two candidate shapes, not separated: (a) under a CPU-saturated parallel run, `engine.start()` returns while the HAL IO thread is starved and has not yet rendered a cycle; (b) the engine is stopped out from under the provider between `engine.start()` and `play()` (device contention / config change from the many concurrent AVAudioEngine instances other suites create). Isolation-pass vs parallel-fail is consistent with both.
- **Whether `resume()` (`LocalFilePlaybackProvider.swift:251`) ever fires this.** It is the only other `play()` site and `transportChurn` hammers it from detached threads, but no retained report shows it. Same class; unproven.
- **Provenance of the individual `.ips`:** report paths are anonymized (`/Users/USER/Documents/*/PhospheneEnginePackageTests`), so the reports cannot distinguish which checkout ran. The RECON.14 session's runs and its baseline check at `8cbf936a` are the provenance.

#### Reproduction

1. `swift test --package-path PhospheneEngine` (full parallel suite; tempo fixtures present — in a worktree run `Scripts/link_fixtures.sh` first).
2. Intermittent; on 2026-08-25 it fired in most closeout attempts. On a kill, `~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-*.ips` gains a report whose `lastExceptionBacktrace` names `StartImpl`.
3. Control: `swift test --filter SessionLifecycleChurn` passes clean.

**Minimum reproducer:** none deterministic yet — needs full-suite load (the BUG-078 lesson repeats: the churn/race tests enter the window; parallel load springs it).

#### Session artifacts

`~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-2026-08-25-{111953,114756,115256,151059,155635,160241,160558,160917,161743,162300,162849,164635,170015}.ips` — all SIGABRT, all the `StartImpl` exception backtrace. The `170015` report is the first-hand baseline reproduction (worktree at `8cbf936a`, fixtures linked); its console carried the full first-throw stack and the reason string verbatim: `*** Terminating app due to uncaught exception 'com.apple.coreaudio.avfaudio', reason: 'player did not see an IO cycle.'` (n/a for features.csv etc. — no session surface.)

#### Suspected failure class

`api-contract` — a shipped code path calls an AVFoundation API whose failure mode is an ObjC exception Swift cannot catch, from contexts (raw test threads; in-app, the MainActor) where an escape is fatal. The *trigger* is parallel-test load (`test-isolation`-shaped), but serializing tests would only hide the contract gap; the class that fits the defect is the contract.

#### Verification criteria (written before any fix)

- [ ] Automated: full parallel engine suite, 5 consecutive runs, exit 0, `~/Library/Logs/DiagnosticReports` gains no `swiftpm-testing-helper` `.ips`. (Same lottery caveat as BUG-078: the streak is supporting evidence, not the load-bearing signal.)
- [ ] Automated: a deterministic gate proving the start path cannot abort the process when the engine is not cycling at `play()` time — e.g. a test that forces the engine-not-running state at the `play()` call and asserts `start()` throws a Swift error (or recovers) rather than dying. Per the deterministic-over-budget-widening rule, the fix must not be "retry with sleeps."
- [ ] Manual: none required for the test-process defect. If the fix touches the shipped start path, one app-level local-file session with start / Next-churn / quit (the BUG-078 manual shape).

#### Fix scope

Contained to `LocalFilePlaybackProvider`'s start path, but the design needs care: any guard must respect the BUG-021 lock constraints (no AVFoundation teardown under the provider lock) and must not reintroduce the BUG-078 windows. Candidate directions, undesigned: check `engine.isRunning` after `engine.start()` and surface a Swift error; or bridge the `play()` call through an ObjC exception catcher so the failure is reportable. Test-side serialization of audio-hardware suites is a mitigation, not a fix — the contract gap ships.

#### Related

- BUG-078 (same family — AVAudioPlayerNode lifecycle under parallel scheduler load; different throw site, different signal, resolved 2026-08-10)
- BUG-021 / BUG-059 (the lock-ordering constraints any fix must preserve)
- `SessionLifecycleChurnTests`, `LocalFilePlaybackStartRaceTests` (the racing-start tests that enter the window)
- RECON.14 (found while running its closeout evidence; not introduced by it)

---

### BUG-102 — BeatBench's reference for money and bleed is at an untrusted metrical level (2026-08-19)

**Status: open. Not a code defect — a ground-truth defect that caps what the beat-sync
program can measure. Cannot be fixed by editing the JSON.**

Found while running FT.3.1, which existed to detect a wrong *grid* metrical level on exactly
these two tracks. The label set did not survive contact with its own ground truth.

**What the ground truth says about itself.** Both tracks carry `status: metrical_review` — the
GT.2 pipeline's flag for an unresolved metrical disagreement — against `confirmed` for
billie_jean, solsbury_hill and take_five. On both, *both* independent reference annotators
agree the taps are the octave-off side:

| track | status | tap BPM | librosa | madmom | Phosphene grid |
|---|---|---|---|---|---|
| money | `metrical_review` | 60.97 | METRICAL — "reference is double the tapped pulse (×2.01)" | METRICAL ×2.01 | 116.19 (×1.91) |
| bleed | `metrical_review` | 226.72 | METRICAL — "reference is half the tapped pulse (×0.51)" | METRICAL ×0.51 | 115.00 (×0.51) |

`money.groundtruth.json`'s own `meter_note` reads *"ratio 3.54 — beats tapped at HALF the bar
pulse, so the bar is 7"*. On bleed, Phosphene's 115.00 sits between the backends' 114.80 and
115.38.

**Matt, 2026-08-19:** *"I would not trust my tapping on these tracks, especially Bleed."*

**The repo already contradicts itself, and nobody had noticed.** BUG-076's body — filed against
bleed, still open — states that bleed's ~115 BPM reading is **"correct — matches madmom 115.0,
librosa 115.0, drums-stem 115.1"**. That is a *third* independent source at 115. Meanwhile
`bleed.groundtruth.json` asserts 226.72 and `BEATBENCH_BASELINE_2026-07-30.md` scores bleed at
F 0.61 / CMLt 0.03 / AMLt 0.84 against it. Both statements are live in the repo and they cannot
both be right.

**What this contaminates.** Anything scored against these two references at the metrical level:

- **BeatBench suites 2 and 4.** money is one of five suite-2 tracks; **bleed is the only suite-4
  track**, so suite 4's entire score rests on an untrusted reference. D-205 ratified `AMLt ≥ 0.80`
  for suite 4 against exactly that number.
- **`AMLt − CMLt` as a "wrong grid level" signal.** It measures grid-vs-tap *disagreement* and is
  silent about which side is wrong. D-210's evidence table reads the gap as the grid being wrong;
  that reading is not established. D-210's *decision* (decline the bar, keep the beat) does not
  depend on it and stands.
- **FT.3's phase result** (money 0 %, bleed 16 %) was scored against these downbeat taps, so
  FT.3's "phase 3/6" headline needs a recheck once the level is settled — as do the FT.3 tasks 4–6
  bar-correctness labels and the 1.24 decline threshold derived from them.
- **D-208 / MDL.1's bleed judgment** ("BPM doubles 115.00 → 259.43, meter 4 ✓ → 2 ✗") used the
  tap-derived truth. 259.43 is not a clean octave of either candidate (2.25× of 115, 1.14× of 227),
  so the *conclusion* likely survives — but it has not been re-derived and should not be quoted as
  settled until it is.

**What it does NOT contaminate.** billie_jean, solsbury_hill and take_five are `confirmed` with
gap 0.00, so suite-1 F 0.97 and the tracks FT.3 got right are unaffected.

**Fix path — re-annotation, not an edit.** The `beatbench` skill is explicit that ground truth
changes only through the tap + reconcile pipeline; hand-editing the JSON destroys provenance.
Either re-tap both tracks (`TapCapture --calibrate`, both passes) with the metrical level chosen
deliberately, or arbitrate them to the backends' level through `reconcile.py` and record the
arbitration. Until then, **suite-4 numbers and any money/bleed metrical claim should be quoted
with this caveat**. solsbury_hill's separate ground-truth inconsistency (`meter_from_taps: 7`
with downbeat taps ~12 tapped beats apart, flagged at FT.3 tasks 1–3) is still open and would
be worth settling in the same pass.
### BUG-100 — Sustained 4K rendering degrades the whole app, not the preset on screen (2026-08-19)

**Status: evidence-only. Not a preset defect — three preset-side hypotheses were falsified
before filing.**

Matt's Stave M7 (`2026-08-19T17-01-15Z`): *"performance slowed over time, which led to some
choppiness."* Measured over a contiguous 70 s window at 3840×2160:

| t | frame_cpu | frame_gpu | encode_cpu | renderframe_cpu |
|---|---|---|---|---|
| 32 s | 17.6 ms | 3.6 ms | 13.9 ms | 9.8 ms |
| 62 s | 19.7 ms | 3.9 ms | 15.5 ms | 12.0 ms |
| 77 s | 37.4 ms | 6.8 ms | 16.2 ms | 12.6 ms |
| 92 s | 44.9 ms | 12.9 ms | 15.2 ms | 11.0 ms |

**The app's own CPU work is flat.** `encode_cpu_ms` and `renderframe_cpu_ms` barely move while
total frame time rises 2.5× and GPU time 3.6×. The app is doing the same work and getting less
back.

**Falsified before filing:**

1. **Stave accumulates something.** An offline soak — 1920 frames at 3840×2160 through the real
   multi-pass path — is flat at 22.3 ms with no drift across eight blocks.
2. **The dispersion fan opens over the track**, raising overdraw. `waveformOccupancy` is flat at
   0.081–0.095 across the entire segment and **r(GPU, occupancy) = −0.11**.
3. **It is preset-specific.** It is not: the degradation persists into the next preset
   (Witchlight reads `frame_cpu` 24.4 ms at 4K, against Stave's own 17.4 ms early in the same
   session) and partially recovers after a 2.16 MP interlude.

⚠ **A "second finding" was filed here and is RETRACTED — the metric did not mean what its name
says.** The entry originally claimed `encode_cpu_ms` was CPU work scaling with pixel count
(9.1 ms at 2.07 MP → 16.4 ms at 8.29 MP) and called it "the more tractable half".

**It is not CPU work.** `encode_cpu_ms` is wall-clock from `draw()` entry to `commit()`
(`RenderPipeline.swift:752…822`), and `view.currentDrawable`
(`DrawableLifecycleProbe.swift:256`) is called *inside* that window. `currentDrawable` **blocks**
until CoreAnimation frees a drawable, so when the GPU is slower — which at 4K it is — the block
is longer and the "CPU" number rises with it. The inflight semaphore is correctly excluded
(waited at line 743, before `cpuDrawStart`), which is probably why the drawable wait was assumed
excluded too. It is not.

So there is **no separate CPU-encode defect**, and no fix to make there. At 4K the app is simply
saturated: GPU 12.9 ms plus presentation waits, with `frame_cpu` (44.9 ms) measuring
draw-start → completion and therefore carrying queue latency for a pipeline that cannot keep up.

⚠ **Third time in one day** that a metric was read as its name rather than its definition —
after `deltaTime` (vsync, not headroom) and the harness milliseconds (readback included). The
rule that keeps holding: **read what the number is computed from before concluding anything from
its trend.**

⚠ **FIRST INSTRUMENTED SESSION (2026-08-19T22-45-50Z): thermal stayed `nominal`, and the
degradation did not reproduce.** `THERMAL_STATE state=nominal low_power=false active_cpus=10`
logged once and never changed, and Witchlight held **6.77 → 6.22 ms across 60 s at 4K — flat**,
in a window comparable to the one where Stave degraded 2.9 → 11.7 ms. So this session supports
neither the thermal hypothesis nor a general sustained-4K decay. ⚠ It does not refute them
either: the degrading session ran a different preset mix, and one non-reproduction is not a
falsification. **What it does establish is that the instrument works and reports cleanly**, so
the next session that DOES degrade will carry the answer. Keep BUG-100 open pending that.

**⚠ SECOND INDEPENDENT NON-REPRODUCTION, 2026-08-20 (PERF.15).** Session
`2026-08-20T16-38-27Z`: **Volumetric Lithograph — the most expensive preset in the roster — flat
across 172 s at 3840×2160 fullscreen**, `frame_gpu_ms` p50 30.92…31.28 over seven consecutive
buckets, thermal `nominal` with no state change, 6,815 frames. Same reading as the Witchlight
non-reproduction above: it does not falsify this entry, but two clean runs on two different presets
at 4K make the general "sustained 4K decays" form less likely.

⚠ **One contrary signal in the same window, and it is worth re-reading rather than filing:** the
`2026-08-20T15-53-59Z` session shows VL rising ~175 → ~295 ms across its final two buckets — a real
within-session degradation. **That is also the session whose 175 ms baseline PERF.15 disputes by
5.6×**, so its trend should be re-derived once that conflict is settled; a ramp measured on a
baseline that may be misattributed is not yet evidence for this entry.

**⚠ THIRD NON-REPRODUCTION, AND THE FIRST WITH THE INSTRUMENTS IN — session
`2026-08-26T22-04-58Z` (2026-08-26).** 3840×2160, Witchlight, 82 s inside one preset at one
resolution (4,929 frames, well past the few-hundred-frame floor the PERF program set after a
16.44 ms figure was published off 89 frames spanning a transition):

| t (s) | frames | `frame_cpu` p50 | `frame_cpu` p90 | `frame_gpu` p50 | `frame_gpu` p90 |
|---|---|---|---|---|---|
| 20 | 120 | 25.12 | 28.33 | 11.44 | 11.50 |
| 40 | 597 | 25.25 | 28.66 | 11.43 | 11.54 |
| 60 | 600 | 25.55 | 28.67 | 11.46 | 11.53 |
| 80 | 600 | 25.45 | 28.66 | 11.45 | 11.52 |
| 100 | 600 | 25.80 | 28.65 | 11.43 | 11.50 |

**Flat.** `frame_cpu` p50 moves +2.7 % across 80 s and `frame_gpu` p50 does not move at all,
against the 2.5×/3.6× this entry was filed for over a comparable 70 s window. Thermal `nominal`,
no state change.

**★ The GPU-working-set hypothesis is FALSIFIED, not merely unobserved.** All ten `GPU_PRESSURE`
lines read `alloc_mb=489 budget_mb=12124 used_pct=4.0` — dead flat, and **4 % of budget**. At 4K
this app is nowhere near the eviction threshold, so pressure cannot be the mechanism on this
machine at this resolution. That was the leading un-measured candidate; it is now dead.

**The ML half is moot as well**: `ml_forced=0 ml_last=dispatchNow` throughout, because BUG-106
was fixed in the same session's build. (It was already refuted as a mechanism by PERF.15's VL
run.)

**Where that leaves this entry.** One observed degradation (Stave M7, `2026-08-19T17-01-15Z`,
artifacts since aged out of retention) against **three** clean 4K sessions — Witchlight twice,
Volumetric Lithograph once — with both named mechanisms now measured and excluded. The one
uncontrolled difference left is the **preset mix**: every clean session ran Witchlight or VL, and
the only degrading one had **Stave** in it. That is not "Stave is slow" — the original session
showed the degradation *persisting into* Witchlight after leaving Stave, which is what made it
look whole-app. It means a session that CONTAINS Stave is the reproduction that has never been
retried. **Next attempt: 4K fullscreen, Stave for ~90 s, then switch to Witchlight and hold.**
If that is also flat, this entry should close as unreproducible with a note that its instruments
stay in place.

**Instrumented 2026-08-26 (BUG100.1) — the two dimensions nothing was recording.** Thermal came
back `nominal` on both non-reproducing sessions, which rules that out for *those* and leaves the
degrading one unexplained. Sessions now also log, on the same low-rate heartbeat bucket as
`DRAWABLE_LIFECYCLE`:

```
GPU_PRESSURE alloc_mb=… budget_mb=… used_pct=… ml_forced=… ml_last=…
```

- **`alloc_mb` / `budget_mb`** — this process's Metal allocation against
  `recommendedMaxWorkingSetSize`. At 4K every render target is 4× its 1080p size; if the working
  set approaches the budget the driver evicts, which is slow **globally**, survives a preset
  switch (the targets stay big) and recovers when a smaller target frees memory. That is
  precisely this entry's signature — whole-app, cross-preset, partial recovery after the 2.16 MP
  interlude — and it has never been measured. A ratio climbing through a degrading session
  confirms it; a flat ratio rules it out.
- **`ml_forced`** — `MLDispatchScheduler.forceDispatchCount`. Filed separately as **BUG-106**:
  the gate's budget is a hardcoded 14/16 ms, so at 4K it can only defer-then-force. ⚠ **This is
  not offered as this entry's mechanism** — the PERF.15 VL session was flat across 172 s at 4K
  while permanently over that same budget, so forced dispatch is not sufficient to degrade. The
  counter is here so the next degrading session can implicate or clear it with one grep instead
  of an argument.

**What is needed now is one reproduction on the instrumented build:** a fullscreen 4K session of
about two minutes on a preset mix that has degraded before (Stave → Witchlight was the original).
Both candidate mechanisms are then decided by three lines of log.

**Instrumented 2026-08-19 (PERF.9).** Sessions now log
`THERMAL_STATE state=… low_power=… active_cpus=…` whenever it changes, plus once at the start so
an unchanging session still records its state.

⚠ **NOT `powermetrics`, which is what was asked for.** It refuses to run unprivileged —
*"powermetrics must be invoked as the superuser"*, verified — so the app cannot sample it, and
shipping a privileged helper to read one counter is not proportionate.
`ProcessInfo.thermalState` is the supported unprivileged primitive for exactly this question:
the OS's own view of whether it is shedding performance for heat. It is coarse (nominal / fair /
serious / critical), and coarse is enough here — **`nominal` throughout a degrading session
falsifies the thermal hypothesis just as usefully as `serious` confirms it**, and either outcome
closes the open half of this entry.

---

### BUG-091 — A single local file selected: preparation succeeds, playback never starts, every audio field is exactly zero (2026-08-17)

**Status: instrumentation increment landed. Root cause NOT asserted — one reproduction with the
new breadcrumbs will name the branch.**

**Expected.** Selecting one local file plays it: `LocalFilePlaybackProvider` starts via
`audioRouter.start(mode: .localFilePlayback(url))`, the AVAudioEngine node tap feeds the chain
(BUG-087: ~10–16 Hz on this path), `playback_time_s` advances, and no Core Audio **process** tap
is installed.

**Actual** (`2026-08-17T17-19-19Z`, *03- Carry The Zero.flac*): 1262 frames / 84 s of render
clock, and every audio-derived field holds **exactly one distinct value, 0.0**:

| field | distinct values | value |
|---|---|---|
| `playback_time_s`, `track_elapsed_s`, `accumulatedAudioTime` | 1 | 0.0 |
| `bass`, `mid`, `treble`, `pulse_amp01`, `beatPhase01`, `spectral_level_rise` | 1 | 0.0 |
| `time` (render clock) | 1262 | advances normally |

So this is not a frozen playback clock with audio flowing, nor a stalled renderer: **no audio
samples ever reached the analysis chain.**

**The discriminator — a working session 1.5 h earlier, same file, same OS build (26.5.1 / 25F80).**

| | `16-19-13Z` (works) | `17-19-19Z` (fails) |
|---|---|---|
| preparation, BeatGrid, plan | identical | identical |
| `WIRING: provider.start INSTANCE` | **present** | **ABSENT** |
| `TAP_BUFFER: requested=1024 delivered=4410 (10 Hz)` — AVAudioEngine node tap | present | absent |
| `TAP: startCapture → createProcessTap` — system-audio path | **absent** | **present, twice** |
| gap between preparation and `→ready` | none (same second) | **8 s** |
| `playback_time_s` span | 0.1 → 34.1 s | 0.0 → 0.0 |

**What that pins down.** `resetStemPipeline(caller: .other)` has exactly ONE call site —
`handleLocalFileReady()` — and it appears in the failed log. So that function ran, cleared all
three of its guards (LF source, URL present, not a duplicate `.ready`), reached `buildPlan()`, and
then never got to the router start.

**Candidate mechanism, deliberately NOT asserted as root cause** (BUG-061: do not infer a cause
from "the path requires X, so X held"): the `catch` around
`audioRouter.start(mode: .localFilePlayback(url))` logs via `lfLogger.error` only, then calls
`sessionManager.endSession()`, which sets `currentSource = nil`. With no local-file source,
`startAudio()`'s LF.4 guard — whose own comment warns that `start(.systemAudio)` would
`stopInternal()` the provider — no longer fires, so the process tap is installed and any provider
is torn down. That chain reproduces every observation, including the two tap installs and the
silence, but the first link is unverified.

**Why it could not be verified from the capture, which is a defect in its own right.** Every
branch in `handleLocalFileReady()` that can end in silence returns without writing to
`session.log`, and its failure path logs only to `os_log` — which is not retained here: a
`log show --last 4h --predicate 'subsystem BEGINSWITH "com.phosphene"'` over the failure window
returns **zero lines**. An 84-second silent session left no evidence of its own cause.

**Instrumentation added (this increment, no fix):**
- every early return in `handleLocalFileReady()` names itself in `session.log`, with the actual
  `currentSource`, `isLocalFile` and URL;
- the `router as? AudioInputRouter` cast — which silently gated the *entire* start — is now a
  logged `guard`;
- the LF start failure writes the error text and the `→ endSession` consequence to `session.log`;
- `startAudio()` logs which path it took **and what `currentSource` was** when it chose the tap;

**⚠ A sixth breadcrumb was attempted in `AudioInputRouter.start(mode:)` and ABANDONED — twice
over, for two independent reasons worth recording.** (1) It first read `activeMode` to report
"replacing=<previous mode>". `activeMode` takes the router's `NSLock`, `start()` is reachable from
the file-ended completion path that already holds it, and NSLock is not recursive — **all three
`SessionLifecycleChurnTests` watchdogs timed out at 5 s. A LOG LINE caused a hang-class failure,
and the churn suite is the only reason it did not ship.** Never take a lock in `start()`.
(2) The lock-free version was then dropped as well: `AudioInputRouter.swift` sits at **exactly**
its 400-line lint cap, so any addition needs a file split, and the line was redundant anyway —
`startAudio()`'s new breadcrumb plus the existing `TAP: startCapture` lines already identify the
mode. If a future increment does need it there, split the file rather than trimming a comment.

**Verification criteria (written before any fix):**
1. Automated: a regression test that drives `handleLocalFileReady()` with a local-file source and
   asserts the router ends in `.localFilePlayback` mode — and that a subsequent `startAudio()`
   does NOT replace it with `.systemAudio`.
2. Manual (required — this is a UX-flow and audio-path defect): select a single local file, confirm
   audible playback, and confirm the capture shows `provider.start INSTANCE`, a `TAP_BUFFER` node-tap
   line, no `createProcessTap`, and `playback_time_s` advancing.

---

### BUG-085 — Main thread hangs in `CAMetalLayer.nextDrawable` ~3.6 min into a session (2026-08-04)

**P1 · renderer / app.hang / resource-management.**

**Expected.** The app renders continuously for the length of a session; the window stays responsive.

**Actual.** ~3.6 minutes in, the app freezes hard — no rendering, no UI response, force-quit required. Matt has now hit this repeatedly ("froze again").

**Evidence — a stack, at last.** Matt left the frozen app running instead of force-quitting, so `sample 42392 5` captured it live. **100 % of 4250 samples on a single stack, 0.0 % CPU:**

```
RenderPipeline.draw(in:) → renderFrame → drawWithFeedback → drawParticleMode
  → MTKView.currentRenderPassDescriptor → MTKView.currentDrawable
  → CAMetalLayer nextDrawable → CAMetalLayerPrivateNextDrawableLocked
  → _dispatch_semaphore_wait_slow → semaphore_timedwait_trap
```

Every other thread is idle — audio, caulk, CVDisplayLink all in normal waits. **No thread holds a Metal command buffer, waits on `waitUntilCompleted`, or blocks on a mutex.** So this is not a GPU hang and not a cross-thread deadlock: the drawable pool is exhausted and nothing is returning drawables to it. Because the main thread never returns to the run loop, the window is dead rather than merely frozen mid-frame.

**Reproduction.** Not deterministic yet. Observed on session `2026-08-04T17-49-50Z` (Witchlight, "Hummer"), 12,911 frames ≈ 3.6 min. Frame timings were **steady right up to the final frame** — `frame_cpu_ms` p50 20.80, `frame_gpu_ms` p50 10.62 across the last 50 — with no upward drift. An abrupt stop after healthy frames is the signature of pool exhaustion (leak N drawables, run fine until the pool empties, then block forever), not of a progressive stall.

**Probably not a new defect, and probably not Witchlight's.** The ~3.6 min timing matches the **unreproduced "~3.7 min crash"** logged against Volumetric Lithograph certification, and BUG-060 is a one-off hang filed with "no stack captured". All three are plausibly one bug. Nothing in the stack is preset-specific below `drawParticleMode`, which every `particles` preset shares.

**Already ruled out.**
- `drawParticleMode` leaking directly — it acquires and unconditionally `present`s on every path.
- The inflight semaphore — the hang is *past* `context.inflightSemaphore.wait()`, so a slot was available.
- A GPU hang or a stuck completion handler — no thread is waiting on either.

**Failure class.** `resource-management` (a finite pool acquired without a guaranteed release path).

**Suspected direction, NOT yet confirmed.** Something acquires a drawable outside the committed command buffer's lifetime, or retains `drawable.texture` past presentation. The session-recording hook in `draw(in:)` reads `view.currentDrawable` a second time and hands `drawable.texture` to a consumer, which is the shape of thing that would do it — but that is a hypothesis, and three hypotheses have already died on this preset today. It gets confirmed against an artifact before any fix.

**Investigation so far (2026-08-04) — leading hypothesis, still UNPROVEN.**

Ruled out by inspection after the stack: the capture hook does not retain the drawable (it blits into a separate texture inside the same command buffer, and with video recording off — as this session's log confirms — `ensureCaptureTexture` returns nil so it does nothing at all); the `willRenderActiveFrame` preset-swap skip still commits its command buffer, so skipped frames do not leak; and **display sleep is excluded** — `pmset -g log` shows `coreaudiod` held `PreventUserIdleDisplaySleep` for the full 33 minutes spanning the freeze.

**What that leaves, and it is a real gap regardless of this hang:** the app has **no occlusion handling of any kind**. `MetalView.swift` sets `view.isPaused = false` and nothing anywhere observes `NSApplication.occlusionState`, `windowDidMiniaturize`, or window visibility. Rendering therefore continues into a layer that may not be composited — and a `CAMetalLayer` whose window is minimised or fully occluded stops recycling drawables, which makes `nextDrawable` block exactly as observed. It fits every measured fact: hard block, 0 % CPU, nothing else holding, healthy frames right up to the stop.

**REFUTED 2026-08-04 — do not spend time here again.** Matt ran the repro and left the instance alive; sampled at **7 min 11 s elapsed**, twice past the ~3.6 min mark, with every `PhospheneApp` window reporting `onScreen=false` via `CGWindowList`. The app was **not hung**: 0 of 4145 main-thread samples in `nextDrawable`, 49 % CPU, session still live (stem separation running). The control is the decisive part — **the draw loop was entirely absent** (0 samples in `RenderPipeline.draw`, `MTKView draw`, `drawParticleMode`, `currentDrawable`). When the window is not composited macOS stops the draws rather than letting them block, so rendering-into-an-uncomposited-layer is not a state this app can reach, and occlusion cannot be the cause. The missing occlusion handling is still a (minor) gap, but it is **not** this bug.

**Pre-HANG.1 conclusion (2026-08-04).** The original capture stands unexplained: main thread hard-blocked in `nextDrawable` at 0 % CPU with every other thread idle, ~3.6 min in, after frames that were healthy to the last one. Drawables are being retained by something that is not the render path, not the capture hook, not the preset-swap skip, not the inflight semaphore, and not window state. At that point there was no current hypothesis; the next step was instrumentation that counts drawables acquired against command buffers completed, rather than another guess.

**Status 2026-08-05 — HANG.1 + HANG.2 COMPLETE; BUG-085 remains OPEN.** Instrumentation merged to
`main` through PR #37 (source `f81c36cb`, merge `c54a2e7c`); the required `fast-gate` passed.
HANG.1 gathered no reproduction and made no diagnosis or fix claim. Every
drawable-facing render path now routes its existing `currentRenderPassDescriptor`,
`currentDrawable`, and `present` calls through `DrawableLifecycleProbe`, which correlates the
request site and unique drawable identity with its command buffer's commit and completion.
An independent watchdog writes a balance heartbeat to `session.log` every 600 completions,
logs command-buffer failures or completed frames with unpresented acquisitions immediately,
and emits `DRAWABLE_LIFECYCLE STALL` after a request remains pending for 500 ms. The watchdog
does not depend on the blocked render/main thread, so the next reproduction will identify the
exact request site and the last known acquired/presented/completed balance. State-machine tests
cover balanced duplicate lookups, pending-site/age capture, and failed unpresented completion.
`Scripts/capture_hang.sh` now extracts the lifecycle lines explicitly.

**HANG.2 non-reproduction control (2026-08-05).** Two visible Witchlight/local-file runs
completed cleanly: a full 6 min 50 s Hummer control (24,866 frames) and a 10 min 36 s soak
through two track transitions (35,297 frames at the final snapshot). Both passed the original
~3.6-minute / 12,911-frame failure point. The final durable lifecycle heartbeat balanced
34,811 unique acquisitions with 34,811 presentations, with zero command-buffer failures,
unpresented acquisitions, stalls, or imbalances; process memory remained stable. This refutes
a deterministic per-frame drawable leak and a fixed ~3.6-minute exhaustion time. It does not
identify the intermittent owner and does not justify a render change. Full evidence:
`docs/diagnostics/BUG085_HANG2_SOAK_2026-08-05.md`. On the next live freeze, leave the process
running and execute `Scripts/capture_hang.sh` before force-quit.

**The original note, kept for the record:**

**It was NOT confirmed, and was not fixed on that basis** (the BUG-063/064 rule: no fix for an unreproduced hypothesis). Reproduction was attempted and could not be completed headlessly — the render loop only runs with an active session, and `osascript` lacks assistive access on this machine, so the window could not be driven from a script.

**Next reproduction.** Do not schedule another identical soak: HANG.2 established the clean
control. If the app freezes during ordinary use, leave it running and execute
`Scripts/capture_hang.sh` before force-quit; the capture includes the last 20
`DRAWABLE_LIFECYCLE` records, the blocked request site, and acquired/presented/committed/completed
balances. Do not repeat the occlusion experiment; that hypothesis is refuted above.

**`Scripts/capture_hang.sh` added** so the next freeze is captured in one command instead of improvised: stack, process state (0 % CPU distinguishes a block from a spin), window occlusion state, power-event log, and the session tail. **Run it BEFORE force-quitting** — a force-quit destroys the only evidence, which is why BUG-060 sat unactionable for months.

**Phase verification.** HANG.1 automated criteria are complete: lifecycle state-machine tests
cover balanced duplicate lookups, pending request site/age, and failed unpresented completion;
the app suite, renderer golden hashes, strict lint, documentation gates, and CI `fast-gate`
passed. HANG.2's ≥10-minute particle-preset soak and full-track manual run are complete; both
were clean non-reproductions. The minimised-window check is retired because the occlusion
hypothesis was experimentally refuted. BUG-085 remains open pending a frozen instrumented
capture.

---

**2026-08-05 — THE FROZEN INSTRUMENTED CAPTURE, at last.** Session `2026-08-05T21-21-03Z`
(Fractal Tree on Cherub Rock, local file). Matt left the app frozen; two independent runs of
`Scripts/capture_hang.sh` 98 s apart are preserved at
`~/Documents/phosphene_sessions/_freeze_captures/bug085_20260805T224531Z/` and
`…T224709Z/`.

**The stack is the same block, at a different site.** `drawWithMeshShader` →
`instrumentedRenderPassDescriptor` → `currentRenderPassDescriptor` → `currentDrawable` →
`nextDrawable` → `semaphore_timedwait_trap`, 100 % of samples, 0 % CPU. The 2026-08-04
capture blocked in `drawParticleMode`; this one in the MESH path. **The hang is not
preset-path-specific** — it is whichever path happens to ask for the drawable.

**What the instrumentation proves, and it is the important part.** The final heartbeat before
the freeze:

```
DRAWABLE_LIFECYCLE heartbeat frames=6013 descriptor=5905/5906 drawable=12045/12045
  unique_presented=6012/6012 command_completed=6012/6012 failures=0 unpresented=0
  pending=frame:6013,site:mesh.descriptor,age_ms:8
```

Every pair balances. **The app was holding ZERO drawables when `nextDrawable` blocked
forever.** That is not starvation-by-leak; CoreAnimation declined to vend a drawable to a
client that owed it nothing. HANG.2's 34,811/34,811 soak said the same thing from the
negative side; this says it from inside an actual freeze. **Direct app-side leakage is now
refuted twice, by independent methods — stop looking there.**

**Permanent, not slow.** The two captures 98 s apart report the identical frame (6013), site,
counters and `age_ms:8`. The `age_ms` is frozen because the heartbeat writer itself never ran
again — the render thread never took another step in 98 seconds.

**Only the render thread died.** `session.log` continues past the hang: stem separations 18
and 19 logged at 22:43:52 and 22:43:57, `SIGNAL_HEALTH` steady at −0.5 dBFS, `deadTap=false`.
Audio, ML and the analysis queues all ran on normally. Any hypothesis requiring a
process-wide stall (priority inversion on a shared lock, GPU device loss) is inconsistent
with this.

**Occlusion again NOT supported, and beware the tool.** `window_state.txt` shows the render
window (13229) `onScreen=true`, `alpha=1.0`, `901x633`, **COMPOSITED**. The other eight
windows it flags are `1920x30` and `1080x30` — menu-bar windows for secondary displays.
`capture_hang.sh` labelled every one of them "this is the BUG-085 occlusion condition",
which reads as confirmation of a hypothesis that was already refuted. (Label fixed in the
same increment as this note.)

**No display event.** `power.txt` has no display-sleep, wake, or reconfiguration entry
anywhere near the freeze; the only traffic is `coreaudiod` assertion churn five minutes
earlier.

**One lead, explicitly NOT a finding.** The stall began at 22:43:51, ~1 s before stem
separation #18. Stem separation is MPSGraph GPU work on a 5 s timer, so GPU contention
starving the compositor is mechanically plausible — but 17 prior separations in the same
session ran through cleanly, so this is a hypothesis to test, not a cause. A test would
suppress stem separation for a full session and see whether the freeze class survives;
BUG-061's rule forbids acting on it before that.

**What is now excluded:** app-side drawable leakage (twice), occlusion, display sleep,
preset-path specificity, and any process-wide stall. **What remains:** why CoreAnimation
withholds a drawable from a client holding none.

---

### BUG-070 — Failed tap reinstall leaves untruthful capture state; engine detectors starved (2026-07-12)

**P2 · audio.capture / resource-management.** From the 2026-07-11 ultra review (concurrency + audio dimensions); root cause verified in code at PUB.6.

**Expected:** after a failed device-change reinstall, the capture object's state reflects reality (not capturing), engine-side health classification can still fire, and a recovery restart can proceed.
**Actual (pre-fix):** `performReinstall`'s catch did nothing — its comment claimed "the create steps already tore down + stopped the monitor on failure," which was false on both counts. End state: `_isCapturing=true`, monitor running, zero IO callbacks → `SignalHealthMonitor.evaluate` (sample-driven, `ingest` window boundaries) never runs so `deadTap` never confirms; the router's `.silent` recovery is likewise callback-starved; `startCapture` recovery blocked by the alreadyCapturing guard. Only the app-layer Mode-B stall card (1 Hz poll on the tap frame count, ~10 s dwell) surfaced it — detection existed, engine truth and recovery did not.
**Fix (landed, PUB.6):** catch clears `_isCapturing` (unblocks stopCapture+startCapture recovery), monitor deliberately left running as a diagnostic beacon (later fires land in the SKIP branch and breadcrumb), comment corrected.
**Verification criteria:** automated — engine builds; audio suites green (a real failed reinstall cannot be staged headless: Core Audio create-step failures need a live device transition). Manual (pending): a live device-swap session confirming normal reinstalls still work (the G1 12/12 behaviour), and — if a reinstall failure can be provoked — the stall card appears AND a subsequent session restart recovers cleanly.
**Residual (documented, deliberately open):** the 3-queue lifecycle interleave (device-change reinstall vs silence-recovery reinstall vs user stop) is real but static-only evidence; the per-step breadcrumbs + install-generation probes are the instrumentation. Serialize ONLY on a reproduced interleave artifact — restructuring the G1-live-validated path on theory is the BUG-063 class.

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

### BUG-081 — App beachballs during session preparation; no crash report produced (2026-08-03)

**P2 · unclassified · OPEN — evidence only, root cause NOT established.** Reported by Matt from session `2026-08-03T22-54-06Z`; had to force-quit.

**Expected.** The app stays responsive throughout playlist preparation.

**Actual.** The UI froze/beachballed ~78 s into the session and required force-quit. Because it was force-quit rather than crashed, **no `.ips` exists** — the user and system DiagnosticReports directories contain no PhospheneApp report at all, and `session.log` ends mid-normal-operation at `22:55:24` with no fatal, assertion, or error line.

**What the artifacts DO establish — the renderer was healthy to the last frame.** From `features.csv` (3756 frames, ending t=82.1 s), by sixth of the session:

| segment | frame_cpu_ms | frame_gpu_ms | deltaTime |
|---|---|---|---|
| 1/6 | 11.51 | 2.91 | 47.8 ms (startup) |
| 4/6 | 1.53 | 0.15 | 16.7 ms |
| 6/6 | 6.84 | 0.18 | 16.7 ms |

Steady 60 fps, Fractal Tree costing **0.18 ms GPU against its 0.7 ms Tier 2 budget**, no degradation trend. Background load was rising but modest (`stem_analyzer_ms` 0 → 3.4, `mir_pipeline_ms` 0.84 → 2.09); `session.log` shows stem separation 10 in progress.

**Ruled out.** FTR.2's mesh shader overflowing the primitive limit via a bad `branch_count` — the hypothesis was tested and **falsified**: no non-finite values in the capture, and derived `branch_count` never exceeds 59 against the 63 ceiling. (A grep appearing to show `nan` was matching "co**nan**ce" in `tonal_consonance`.)

**Not yet established.** Everything else. A frozen UI with a healthy render loop points away from the preset and toward the main thread or the preparation pipeline, but that is an inference, not evidence — do not act on it (BUG-061 rule).

**Sub-finding, FIXED 2026-08-04 (`17ac02fc`): a crashed session left an unreadable `raw_tap.wav`.** The stub header declares a `data` size of 0 and the real sizes were patched in only on the 30 s cap or a graceful `finish()` — so every standard reader saw an empty file. Session `2026-08-04T20-23-15Z` had **28.8 MB of intact float samples behind a header claiming zero bytes**, making the capture useless for diagnosing the crash that produced it. `patchRawTapHeader` now also runs about once per second of audio. **NOT gated by a test:** `RawTapHeaderRecoveryTests` could not be made to run (constructing a recorder and abandoning it mid-capture either crashed the test process with signal 5 or produced no file); the fix reuses the existing patch routine and `test_rawTapCapture_persistsAfterDurationCap` still passes, but there is no regression guard. Worth a second attempt with fresh context.

**Next evidence needed — the one thing that would settle it.** A `sample` of the process while it is hung, which captures the blocked main-thread stack:

```
sample PhospheneApp 10 -file ~/Desktop/phosphene-hang.txt
```

Run it *during* the beachball, before force-quitting. Without a blocked stack there is no way to distinguish a deadlock from a GPU stall from a preparation-pipeline wedge.

**Note.** Signal health was `critical` (−24 dBFS) for the session's first ~50 s before reaching green; unlikely to be related but recorded because the session is otherwise the only artifact.

---

### BUG-087 — Local-file playback analyses at 10 Hz where streaming analyses at 51 Hz (AVAudioEngine ignores the tap `bufferSize`) (2026-08-11)

Found while chasing a `beatPhase01` discrepancy across captures. **Diagnosis increment
only — no fix code.**

#### Expected behavior

The MIR chain analyses at a comparable rate whichever way audio arrives.
`LocalFilePlaybackProvider` requests `installTap(onBus: 0, bufferSize: 1024, …)`, which at
44.1–48 kHz is ≈43–47 Hz.

#### Actual behavior

**Local-file playback analyses at 10.0 Hz. Streaming analyses at 51.1 Hz.** A 5.1× rate
loss, on the session type used for essentially all development and all preset work.

#### Reproduction steps

Any local-file session vs any streaming session. Measured across the whole capture corpus
(10 local-file captures, 1 streaming).

#### Session artifacts

`beatPhase01` advance rate × the CSV's own frame rate gives the analysis rate directly:

| capture | path | audio Hz | analysis Hz | implied buffer |
|---|---|---|---|---|
| `2026-08-11T01-07-17Z` | local | 44 100 | 9.99 | **4414 frames** |
| `2026-08-11T23-52-49Z` | local | 48 000 | 9.98 | **4808 frames** |
| `2026-08-11T23-44-40Z` | local | 48 000 | 9.98 | **4810 frames** |
| `beat-match-test-session` | streaming | 48 000 | **51.11** | **939 frames** |

All ten local-file captures read 15.2–16.8 % (16.7 % on eight of ten). The streaming capture
reads 85.4 %.

**The discriminator that makes this a diagnosis and not a correlation:** if the tap delivered
a fixed *frame count*, the analysis rate would differ between the 44.1 kHz and 48 kHz
captures. It does not — 4414 frames at 44.1 kHz and 4808 at 48 kHz are both **exactly 0.1 s**.
The buffer is duration-based, so the `bufferSize: 1024` request is being ignored, not merely
rounded. The streaming path's 939 frames ≈ the 1024 the system tap actually honours.

⚠ **Path and date are perfectly confounded in the corpus** (the sole streaming capture is
2026-07-27; every local-file capture is 2026-08-07 or later), so the *captures alone* cannot
separate "local-file path" from "something regressed in August". The code and the
rate-independence discriminator are what settle it, plus the streaming capture's
`TAP: startCapture: ENTER → createProcessTap` lines, which no local-file capture has — they
are genuinely different audio sources, not the same source at two dates.

#### Suspected failure class

`calibration` — intent (1024 frames) versus reality (~4800), unverified at the boundary.
`api-contract` secondarily: AVFoundation treats `installTap`'s `bufferSize` as a hint, and
nothing here checks what was actually delivered.

#### Root cause (read from source)

- `PhospheneEngine/Sources/Audio/LocalFilePlaybackProvider.swift:292` —
  `player.installTap(onBus: 0, bufferSize: 1024, format: tapFormat)`. AVAudioEngine honours
  this loosely and delivers ~0.1 s buffers on macOS.
- `PhospheneApp/VisualizerEngine+Audio.swift` `processAnalysisFrame` — invoked once per audio
  callback via `analysisQueue.async`, with **no time-based gate**, and it derives
  `effectiveFps = 1 / dt` from the callback interval. So the callback rate *is* the analysis
  rate, and `dt` correctly reports 0.1 s; nothing is lying, the rate is simply low.
- `handleTapBuffer` is **not** at fault: it resizes `interleavedScratch` when a buffer exceeds
  the 1024-frame allocation, so no samples are dropped. Checked, because a scratch sized 1024
  against a 4800-frame buffer would have been the more serious bug.

#### Impact

Every `FeatureVector` consumer on the local-file path sees 10 Hz: bands, the D-026 deviation
primitives, `beatPhase01`, centroid, flux, and the mood classifier's inputs. This is the same
10 Hz the FTR program discovered from the preset side and carried as a preset-authoring fact;
it is a pipeline property, and it is path-specific.

**For a beat-ruled scrolling preset (Stave / the CHR series) it is a design input**, not a
footnote: gridlines and trace samples would arrive in 100 ms steps on the path that preset
would mostly run on.

**A lead was recorded here and is now REFUTED (2026-08-12).** It read: this may also explain
BUG-086's local-file stem/band correlation of r 0.19–0.46 against streaming's 0.70–0.94, since
stems and bands would be sampled on different clocks. Both halves failed. Stems and bands are
on the **same** clock within a path (streaming `beatPhase01` 85.4 % / stems 97.1 %; local
16.7 % / 14.6–16.0 %), so the proposed mechanism does not exist. And step-holding the streaming
capture's series down to 10 Hz — injecting this defect into strong-r data — barely changes the
result (r 0.788→0.783 … 0.937→0.938, 5.4 s lag intact). **10 Hz does not explain BUG-086's weak
correlation**, and this fix should not be expected to improve it. Kept as a record so the lead
is not re-run; detail in BUG-086's refuted-hypothesis list.

#### Verification criteria (written before any fix)

- Automated: assert the delivered buffer's `frameLength` against what was requested at the
  `installTap` boundary, so an ignored hint fails loudly instead of silently costing 5× rate.
- Automated: an analysis-rate floor measured from a real capture, the same shape as
  `Scripts/measure_stem_latency.py` — `beatPhase01` advance × CSV fps ≥ target.
- Manual: any fix raises the update rate of every deviation primitive on the local-file path,
  which is felt on every preset. M7-class observation required; a 5× change in feature update
  rate is not a silent change.

#### Fix attempted — PARTIAL, and the remedy was wrong (BUG087.2/.3, 2026-08-13)

**Measured on capture `2026-08-13T13-15-36Z`: 10.0 Hz → 16.4 Hz. The ≥ 40 Hz done-when is
NOT met**, and not for a tuning reason.

**What landed and works.** `BUG087.2` moved the analysis time base off wall-clock onto the
audio each callback carried (`frames / rate`) — behaviour-neutral, verified by the full suite
moving **zero** existing expectations, and a prerequisite for producing several analysis
frames per callback. `BUG087.3` slices each delivered buffer into 1024-frame pieces.

**Why it falls short.** Slicing raised the *computation* rate to ~47 Hz but not the rate a
preset observes. All five slices of a buffer complete within microseconds — they process
already-buffered audio, not audio arriving in real time — so the render loop samples ~1.6 of
them as distinct values and supersedes the rest. The gap distribution is bimodal and
unambiguous: **39 % of value changes are 1 render frame apart, 55 % are 5–6 frames
(84–101 ms) apart.** A burst against a 100 ms arrival period.

> **The binding constraint is how often audio ARRIVES, not how finely it is sliced.** A preset
> cannot observe more distinct values per second than buffers are delivered, when every slice
> of a buffer lands at the same instant.

**Kept anyway (Matt's call):** effective rate 10 → 16.4 Hz (+64 %), and fresher values — the
last slice reflects the newest 1024 samples rather than a position inside a 4410-frame buffer,
a latency gain even where the rate did not move. Cost: ~5× the per-callback allocation on the
audio thread, landing at ~47/s — the rate the system-tap path has always run at.

**The remaining route is smaller buffers from AVAudioEngine** — manual rendering mode, an
`AUAudioUnit` render block with a smaller `maximumFramesPerSlice`, or tapping a different
node. BUG087.1 measured that a plain `installTap(bufferSize:)` request is ignored. **Filed as
its own increment, not a follow-on commit. BUG-087 stays OPEN.**

⚠ A regression test here asserted `hz >= 40` from slice count and **passed**, while the live
capture measured 16.4 Hz — it was measuring the computation rate and calling it the delivered
rate. Renamed and re-scoped, because a green tick against a refuted claim is worse than no
test.

#### Related

**⇄ BUG-086** — same subsystem boundary, independent cause. The lead that this entry might
explain BUG-086's weak local-file correlation is **refuted** (see Impact). A fix here should
still re-run `Scripts/measure_stem_latency.py` on a local-file capture before and after — not
because the correlation is expected to improve, but so the claim is checked rather than assumed.

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

**⇄ Same class as BUG-081 — two instances, one missing artifact (linked at RECON.9, 2026-08-03).** A parallel session independently filed **BUG-081** for a beachball ~78 s into session `2026-08-03T22-54-06Z` that also needed a force-quit and also produced no crash report, and reached the *same* conclusion this entry did, separately: force-quit yields no `.ips`, so the artifact must be taken **during** the hang via `sample`. Two sessions converging on that from different evidence is worth more than either alone. **Treat BUG-060 and BUG-081 as one investigation** — differences to keep in view: BUG-081's capture shows the renderer *healthy to the last frame* (steady 60 fps, Fractal Tree 0.18 ms GPU against a 0.7 ms budget, no degradation across 3756 frames) with background ML load rising, which points at a frozen **UI/main thread** rather than a dead render loop; BUG-060's original capture showed the render loop itself stopping one frame after a preset switch. Those may be one bug or two. **Whichever recurs first, capture the sample** — it resolves both. Do not assert a shared root cause before then (BUG-061's rule).

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

### BUG-094 — Meniscus clamps `arousal` to 0…1 when its contract is −1…+1, and a beat-locked region goes dead on calm material (2026-08-17)

**Status: ✅ CLOSED 2026-08-24.** The fix WAS applied — in the very commit that wrote the
paragraphs below claiming otherwise. `f94860b6` (2026-08-17, filed as BUG-091 before an ID
renumbering to BUG-094) both replaced the clamp with `arousal01` in `MeniscusStemDrops.swift` and
`MeniscusCamera.swift`, AND added this entry's "Probe reverted, not committed" text — a
same-commit self-contradiction, not a later drift. It survived unnoticed through the renumbering
and seven days of production use. **Matt, asked directly on 2026-08-24 after Ricercar work
surfaced the discrepancy: *"I'm fine with what I've already been seeing."*** That is the M7 this
entry was blocked on — after the fact, but real. Certified Meniscus (MEN.5, 2026-08-05) has run
with this behaviour, unreviewed, since 2026-08-17; his sign-off closes the gap retroactively.

**The defect, as it read until 2026-08-17.** `MeniscusStemDrops.swift:219` computed the MEN.4a musical-arc lift as:

```swift
let lift = max(0, min(features.arousal, 1))
```

`arousal`'s declared contract is **−1 (calm) to +1 (energetic)** (`AudioFeatures+Analyzed.swift`).
This clamps rather than maps, so the entire calm half of the primitive is discarded — every
negative frame reads as identical to "not calm at all".

**What it costs.** On `so_what` (Miles Davis, quiet modal jazz) today's mood output runs
−0.393…+0.519 with **35 % of frames negative**. Those all collapse to zero, `arcEnvelope`
(τ 6 s) sits low, `density = 0.35·arcEnvelope + 0.65·arrangement` never rises, and the
backbeat-gated **vocals region places 0 drops across the entire track** — which
`MeniscusStemDropsTests` correctly calls a dead route, since those three regions are beat-locked
and absolute.

**Why it stayed hidden.** MEN.4a was calibrated on a single capture where arousal never went
negative — its own comment records the range as *"arousal 0.19 → 0.52 → 0.27"* — so the clamp
never engaged. And the committed QG.1 fixtures bottom out at −0.077, roughly 0 % negative. The
defect only surfaced when BUG-090's regenerated fixtures carried today's mood output, after
DYN.6.2/DYN.7 refit the classifier.

**The fix, applied in `f94860b6` (2026-08-17).** The clamp became a map:

```swift
let lift = features.arousal01   // (arousal + 1) * 0.5, i.e. (clamp(arousal,-1,1)+1)*0.5
```

took so_what's vocals region **0 → 24 drops** and turned the whole Meniscus suite green
(14 tests / 9 suites), with the other two tracks unaffected in kind — this is the evidence the
same commit measured before committing it.

**Why this ran seven days without Matt's eye, when the process says it needs one.** The commit
that applied the fix reasoned correctly that it makes a **certified** preset place more drops on
calm material — a visible change, and therefore a product call plus an M7, not a test fix — and
then applied the fix anyway while writing text saying it hadn't. Nobody caught the contradiction
until the Ricercar certification work re-read this entry on 2026-08-24 and checked the source
against it. Matt's *"I'm fine with what I've already been seeing"* is the M7, arriving after the
fact rather than before it.

**The sweep found a SECOND site, in the same preset — also fixed in `f94860b6`.**
`MeniscusCamera.swift:106` did the identical thing to its own envelope:

```swift
arousalEnvelope += (max(0, min(features.arousal, 1)) - arousalEnvelope) * …   // fixed: arousal01
```

Meniscus discarded the calm half of `arousal` twice — once for drop density, once for camera
motion (the dolly no longer pins at the hero distance through a calm passage). Both sites carry
the same fix.

**The codebase already has the correct idiom, two files away.** The orchestrator maps the same
primitive properly:

```swift
SessionPlanner.swift:327    let energy       = max(0, min(1, 0.5 + 0.4 * profile.mood.arousal))
PresetScorer.swift:277-279  let targetTemp   = max(0, min(1, 0.5 + 0.4 * valence))
                            let targetDensity = max(0, min(1, 0.5 + 0.4 * arousal))
```

`0.5 + 0.4 · x` centres the bipolar range on 0.5 and keeps both halves. That is the shape the
Meniscus sites should have used.

⚠ **Also checked and NOT affected.** `RayMarchPipeline+MetalFX.swift:183–184` writes
`max(0, valence)` / `max(0, -valence)` — that is a deliberate split of a bipolar signal into two
unipolar channels (warm and cool), which loses nothing. And the deviation family (`*Dev`) is
`max(0, *Rel)` **by definition**, not by accident. No MSL-side instances. The rule is not
"`max(0, …)` is wrong" — it is "clamping a bipolar primitive to one side of zero throws away
half of it".

---


### BUG-101 — Volumetric Lithograph is expensive by construction, not by waste (2026-08-19)

**Status: ✅ CLOSED 2026-08-20.** Fixed by rendering fewer pixels, not by cutting detail;
M7-approved (*"VL looks good"*, `2026-08-20T13-50-18Z`). **Fullscreen closes at 56 fps delivered,
live, WITH the marched-pixel cap in place** (Matt's final call, PERF.16: *"I would rather keep
60 fps"* — session `2026-08-20T18-17-43Z`, p50 15.88 ms, 5.3 % of frames below the vsync floor,
real headroom) — well past the *"run fullscreen even if not optimal"* bar this entry was opened
against (9.6 fps). The harness-vs-live gap flagged below is also answered: that live session with
the cap in place is the "one live session" the extrapolation asked for, and it landed above the
extrapolated ~30 fps. Full arc (uncap → cost-model dispute → cap kept) in the update chain below.

Matt's requirement was *"it needs to run fullscreen even if not optimal"* — **32 fps is running**
where 9.6 fps was not, so the fullscreen half closes against the stated bar. It is **not** 60 fps at
4K, and whether that matters is a product call he has not been asked to make. PERF.14 (now on `main`)
reduces it further by capping marched pixels, ⚠ **but its key datapoint conflicts with this
measurement by 5.6×, and the conflict is UNEXPLAINED — a proposed mechanism was checked and
falsified. See PERF.15 for what is established and the one-session discriminator.**

> **Update PERF.16 (2026-08-20) — fullscreen closes, and the cost model behind the cap does not
> survive.** Two things landed after the status line above was written. **(1)** PERF.15's live
> capture `2026-08-20T16-38-27Z` measured VL fullscreen at 3840×2160 with `render_scale=0.50`
> **in the log** at **31.16 / 32.30 ms p50/p90 → 32 fps**, flat across seven 10 s buckets,
> thermal nominal, 0.45 % of frames near the floor. Against Matt's stated bar — *"run fullscreen
> even if not optimal"* — 9.6 → 32 fps clears it, so **the fullscreen half of this entry closes**.
> **(2)** PERF.14 had meanwhile capped marched pixels at 1536×864 on the finding that ray-march
> cost is a *step*: 175 ms at 0.5 and ≤ 15 ms at 0.4 at 4K. That is 5.6× from PERF.15's reading of
> the same nominal configuration. **PERF.16 settled it offline** with a marched-pixel sweep
> (`RayMarchCostCurveTests`, readback off, thermal-controlled, reproduced): the curve is smooth
> and mildly **sub**linear — every neighbour pair's cost-ratio is 0.92–1.02× its area-ratio, and
> across the disputed band cost rises **1.49× for 1.56× the area** where PERF.14 reports 11.7×.
> The harness reads **28.19 ms** at the same 2.07 MP marched that PERF.15 measured live at
> **31.16 ms** — 10 % apart, which corroborates the live reading and leaves 175 ms unexplained at
> any scale interpretation. **⚠ Open, and Matt's:** the cap is still active, so VL marches
> 1536×864 at 4K where 1920×1080 measures ~31 ms live. It is buying softness on a falsified
> model. Removing it is a one-line change to a certified preset's fullscreen sharpness. Full
> reasoning: `ENGINEERING_PLAN.md` §Increment PERF.16.
>
> **Matt's call, same day: remove the cap.** `RenderPipeline.marchScale` now returns the
> declared scale clamped to [0.4, 1.0] and nothing else, so VL marches 1920×1080 at 4K —
> the configuration measured live at 31.16 ms — instead of 1536×864. `marchedPixelBudget`
> is gone. ⚠ **Pending Matt's live M7:** the expected read is sharper at fullscreen at
> ~32 fps. If the frame rate does not hold there, this entry reopens rather than the cap
> returning by default.
>
> ⚠ **CORRECTION, same day — the cap was NOT buying softness for nothing, and I told Matt it
> was.** He ran the fullscreen M7 on session `2026-08-20T18-17-43Z`, which — verified by binary,
> not assumed — ran the **capped** build: the session started 18:17:45Z, the cap-removal merge
> landed 18:22:04Z, and the running binary (atime 13:17:47 local) was built from the primary
> checkout at `f2f2b15f`, whose source still contains `marchedPixelBudget`. **Capped VL at 4K
> fullscreen: p50 15.88 ms, p90 20.87 ms, 56 fps delivered over 165 s, with 5.3 % of frames
> below the 15.3 ms vsync floor** — real headroom, not a floored reading. Against PERF.15's
> uncapped 31.16 ms / 32 fps, **the cap is worth roughly double the frame rate at 4K.** The
> recommendation to remove it was made without that number and is retracted as stated; the
> decision is a genuine trade — 1920×1080 marched at ~32 fps, or 1536×864 at ~60 — and Matt has
> now seen only the second one. **Reverting is one commit.**
>
> ⚠ **And a caveat on PERF.16's curve.** The two live points (≤15.88 at 1.33 MP, 31.16 at
> 2.07 MP) give **~2× cost for 1.56× area** where the harness gave 1.49×. That does not restore
> PERF.14's 11.7× step — the finding that there is no cliff stands — but **live is steeper than
> the harness in this band, so the harness curve understates the 4K penalty.** Do not use it to
> predict an absolute 4K cost without a live check.
>
> ✅ **DECIDED (Matt, 2026-08-20): *"I would rather keep 60 fps."*** The cap is restored;
> `marchScale(declared:width:height:)` and `marchedPixelBudget` are back, and VL marches
> 1536×864 at 4K. **The fullscreen half of BUG-101 closes at 56 fps delivered**, well past the
> *"run fullscreen even if not optimal"* bar. VL is softer at fullscreen than it could be, by
> choice. The doc comment at the call site was rewritten so the budget is justified by the
> measured 2× frame-rate difference rather than by PERF.14's falsified step — the next reader
> must not re-derive the step model from a surviving cap.

Matt's call was to render VL below display resolution. Shipped as `render_scale: 0.5` in
`VolumetricLithograph.json` → `PresetDescriptor.rayMarchRenderScale` → `RayMarchPipeline`: G-buffer
and lighting allocate at half linear scale and the composite pass upscales for free, post-process
staying at full resolution. No MetalFX, no motion vectors, no extra pass.

★ **The upscale is free because a linear-sampled pass already existed** — the same observation two
sessions reached independently while building this in parallel (see PERF.12). Rendered side by side
at 1080p the two builds are nearly indistinguishable; a 3× crop shows a slightly softer contour
edge.

| harness, 24-frame drive | before | after |
|---|---|---|
| 1920×1080 | 31.9 ms | **13.4–15.4 ms** |
| 3840×2160 | 111.5 ms | **14.8 ms** |

⚠ **THOSE ARE HARNESS FIGURES AND THE LIVE COST IS HIGHER.** The first instrumented session
(PERF.10, `2026-08-19T22-45-50Z`) measured the *uncapped* VL at **269.89 ms at 4K — 3.5 fps**, and
**32.56 ms per marched megapixel**, against this harness's 111.5 ms: the harness is **2.4× low** on
this preset because its 24-frame drive starts the terrain flight from a standing start, which is the
cheapest part of it. Taking the live ms/MP, a 0.92 MP cap predicts roughly **30 ms ≈ 30 fps, not
60**. So the cap is a large, real improvement that probably does **not** reach the target live.
**Do not tighten it against this extrapolation** — that is calibrating to a measurement of the build
before the fix. One live session with the cap in place makes the number real; it is the same
instrument that settles BUG-100.

**Original analysis retained — it is still correct about where the cost is:**

★★ **AND IT IS THE ONE PRESET THAT MISSES THE PRODUCT'S STATED TARGET (PERF.12, 2026-08-19).**
The roster measured at three resolutions with the harness readback removed — so these are GPU cost,
not instrument cost (see BUG-099):

| resolution | Volumetric Lithograph | next most expensive | presets within 16.7 ms |
|---|---|---|---|
| 1920×1080 | **31.9 ms ≈ 31 fps** | Stave 11.2 ms | 19 of 20 |
| 2560×1440 | 54.9 ms (readback on) | — | — |
| 3840×2160 | **111.5 ms ≈ 9 fps** | Cytokinesis 18.4 ms | 18 of 20 |

`CLAUDE.md` promises **60 fps at 1080p**, and VL is at roughly half that — **3.5× the budget, and
2.8× the next most expensive preset at the same resolution.** Every other covered preset fits.
This is no longer "expensive by construction" as a curiosity; it is the only measured breach of the
stated target in the covered roster, in a **certified** preset.

⚠ **And the frame-budget gate cannot catch it.** `PresetFrameBudgetTests` asserts a RATIO — no
preset above 8× the median — which VL passes at 5.9×. Its header documents an `absoluteCeilingMs`
as "a second, deliberately loose net", but **that constant appears exactly once in the file, in
that comment: it was never implemented.** So nothing in the suite checks the 60 fps promise in
milliseconds, which is why a preset at 31 fps at 1080p is green.

**Both of those are Matt's calls** — adding the absolute net would ship red until VL is decided,
and every lever on VL changes what it looks like (below).

Matt: *"troubleshoot VL"*, after the PERF.4 gate flagged it at **5.2× the median preset**.

**Where the cost is.** `sceneSDF` is evaluated ~135× per pixel — 128 march steps plus 4
tetrahedral normal taps and 3 AO taps — and carries ~10 Perlin evaluations each:

| term | evaluations | measured |
|---|---|---|
| terrain `fbm3D(_, VL_FBM_OCTAVES=4)` | 4 | ~2.7 ms/octave (4 → 1: **30.59 → 22.55 ms**) |
| `vl_foldDomain` warp, 2 × `fbm3D(_,3)` | 6 | **~10.4 ms** (removed: 32.07 → 21.64 ms) |

Together ~69 % of the frame. A same-session drift check re-measured the baseline at 30.58 ms
against 30.59 — the rig is stable, and an **earlier contradictory reading** (octaves 4 → 2
showing no change) was simply a bad measurement taken while the machine was busy.

**The marcher is not at fault.** It sphere-traces with a correct early exit
(`d < 0.001 · t → break`) and a `t < farPlane` bound, so rays that hit leave early rather than
burning the full 128 steps.

⚠ **Both noise terms are already twice-optimised, and the code says so.** VL-PSY.1 cut the warp
from `warped_fbm` (112 evaluations; 1120 ms/frame at the time) down to 6, and took octaves 5 → 4.
**3 octaves was tried and reverted** — below SHADER_CRAFT's ≥4-octave floor the render "went soft
and airbrushed", a quality regression traded for ~1 ms. There is no multiply-by-zero waste of the
BUG-098 kind here; this is what the preset costs to draw.

**The one remaining lever, and why it is not mine to pull.** `VL_SDF_STEP_SCALE` is 0.55 (itself
already re-reasoned up from 0.35, which was "buying safety at ~1.6× the frame time"). Raising it
marches further per step:

| step scale | frame time | vs 0.55, pixel-diffed |
|---|---|---|
| 0.55 | 31.8 ms | — |
| 0.70 | 28.6 ms (−10 %) | 74 % of channels differ, 12.3 % beyond 16/255, mean 9.4 |
| 0.80 | 26.9 ms (−16 %) | 74 % differ, **48.8 %** beyond 16/255, mean 14.3 |

Unlike the Witchlight bloom (max delta 2/255, invisible), this is a visible change to a certified
preset. Whether the render still reads correctly at 0.70 is Matt's judgement, not a measurement.

⚠ **No trustworthy live figure exists for VL.** The single 4K session that carried it reported a
median of 16.44 ms — but from **89 frames with a p90 of 101.73 ms**, a short sample spanning a
preset transition, and that session has since been evicted by retention (BUG-082). The harness
figure (30.6–31.2 ms at 1080p, five runs across two days) is the reliable one, and it does not
reconcile with 16.44 ms at four times the pixels. A fresh session with VL held on screen would
settle it.

---


### BUG-099 — Witchlight reaches ~30 fps at 4K after the 8.2× fix; closing the rest is a product decision (2026-08-19)

**Status: ⚠ PREMISE RE-MEASURED 2026-08-19 (PERF.12). The 4K shortfall was largely the
measuring instrument, not the preset.**

★★ **`MultiPassRenderHarness` reads every rendered frame back to the CPU — ~8 MB per frame at
1080p and ~33 MB at 3840×2160 — and production never does.** That cost scales with PIXELS, not with
what the preset draws, so it lands on the 4K column far harder than the 1080p one and a resolution
sweep that includes it measures the harness as much as the roster. Measured with
`FRAME_BUDGET_NO_READBACK=1`, the same 20 presets in the same run shape:

| | readback ON | readback OFF | readback cost |
|---|---|---|---|
| **Witchlight at 4K** | 18.6 ms | **8.4 ms** | 10.2 ms |
| median preset at 4K | — | — | **11.4 ms** |
| median preset at 1080p | — | — | 3.0 ms |
| **presets within 16.7 ms at 4K** | **6 of 20** | **18 of 20** | — |

So Witchlight holds 60 fps at 4K on GPU cost with room to spare, and **neither route this entry
proposed is needed** — not the star-layer cut, not extending the half-res path to
feedback/particles. Both were sized against a number that was 2.2× too high.

⚠ **This does NOT explain what Matt saw.** He reported real 4K choppiness, and BUG-100 measured it
degrading over 70 s while the app's own CPU work stayed flat — a *drift over minutes*, which a
24-frame cost measurement cannot see and shader cost does not explain. **BUG-100 is the live
question and its thermal instrumentation settles it; this entry is about steady-state cost only.**

⚠ **Caveats on the readback-off numbers.** They still `waitUntilCompleted` per frame, so they are a
serialised GPU-cost measurement rather than a production frame time (production overlaps CPU and
GPU), and they are a 24-frame sample that cannot show thermal drift. They are a fair proxy for "how
expensive is this preset's frame" and nothing more.

**FOURTH TIME IN ONE DAY** that a performance metric did not mean what its name suggested — after
`deltaTime` (vsync, not headroom), the harness milliseconds in general, and `encode_cpu_ms` (which
includes a blocking drawable wait). The rule keeps holding: **read what the number is computed from
before concluding anything from its trend.** Here the specific error was reusing a harness built for
*comparing* presets to answer an *absolute* question about one.

**Original analysis, retained — its component breakdown is still correct, its conclusion is not:**

BUG-098 took Witchlight from 273.88 ms to an extrapolated ~27 ms at 3840×2160 (**10.2× measured
in the harness, 151.3 → 14.9 ms back to back**). That **meets the stated target with large
headroom** — `CLAUDE.md` promises 60 fps *at 1080p*, and 1800×1200 extrapolates to ~6 ms — but a
4K panel still runs at about 37 fps.

**Why there is no third shader fix.** After PERF.2/PERF.3 the remaining 4K cost is balanced
rather than dominated:

| component | 4K cost |
|---|---|
| beads / particles / feedback | 5.8 ms |
| three star layers | 5.3 ms |
| bloom | 2.1 ms |

Nothing here is waste of the kind BUG-098 found (noise multiplied by zero, or octaves that never
reached the image). Halving any of these means removing something the preset draws.

**Two routes, both visible to the user — which is why this is Matt's:**

1. **Drop or cheapen a star layer.** The three-layer parallax is a documented WL.2 feature — the
   near layer crossing frame in ~4 minutes and outpacing the far ones ~13:1 is what gives the
   backdrop its depth. Removing one takes ~1.8 ms and some of that read. ⚠ A micro-optimisation
   was tried here and **rejected as worthless**: reordering the star layer so the `bright < 0.68`
   early-out precedes the `jitter` hash (which is discarded for 68 % of cells, three times per
   pixel) measured **14.9 → 14.9 ms** — the Metal compiler already sinks the dead hash. Recorded
   so nobody spends the increment on it.
2. **Render Witchlight below full drawable resolution.** ⚠ **CORRECTION (checked, 2026-08-19):
   `setDirectRenderScale` CANNOT be used here.** Its half-res path lives in `drawDirect`
   (`RenderPipeline+Draw.swift:309`) and Witchlight's passes are `["feedback", "particles"]`,
   while Nimbus — the preset that uses it — has `passes: []`, i.e. the direct-fragment path.
   Applying this to Witchlight means **extending the half-res render to the feedback/particles
   path first**, which is engine work, not a per-preset config change. Worth noting the trade is
   milder than it sounds at 4K: 0.7× of 3840×2160 is 2688×1512, still sharper than the 1920×1080
   the target promises. The risk is concentrated in the starfield, which is sub-pixel to ~2 px by
   design (WL.2-e) and would alias rather than merely soften.

⚠ **Context for the decision: Witchlight is an outlier, not a symptom.** In the same 4K session
the next most expensive preset measured was Volumetric Lithograph at 16.44 ms, and the rest sat
at 3.27–4.94 ms. Six of seven measured presets hold 59–60 fps at 4K unaided.

⚠ **Also unresolved and cheaper to act on:** the app renders 1920×1080 while idle and drops to
**900×600** one second after a session starts. Every performance judgement made before
2026-08-19 — including two Witchlight sign-offs — was at 0.54 MP, a quarter of the target. That
default deserves its own decision.

---


### BUG-088 — RESOLVED (BUG088.1): Aurora Veil's "undeclared reads" were dead computation, and a silence gate is not a driver (2026-08-12, resolved 2026-08-26)

**Status: ✅ RESOLVED 2026-08-26.** The diagnosis below is kept in full because the correction
matters more than the fix: a capture said three primitives were live in the session, and that was
read as "the preset reads them." It does not. `AuroraVeil.metal` reads exactly the five fields its
sidecar declares; `AuroraVeilState` computed the other three into a buffer AV.7 stopped reading.

**Fix.** Deleted, not re-wired: `AuroraVeilState.swift`, the `AuroraVeilStateGPU` struct and
`[[buffer(6)]]` parameter in `AuroraVeil.metal`, the app-side property + `bindAuroraVeilRuntime`
wiring, the slot-6 bind in three test harnesses, and
`PresetSessionReplay/AuroraVeilRoutes.swift` (a second manifest for the same three deleted
routes — `--preset aurora_veil` no longer resolves). Recurrence guard: a new
`AudioRoute.Kind.gate` with its own floor (peak ≥ 0.9 on every fixture — the only failure a gate
has is never opening), and the three misdeclared `pulseAmp01` routes reclassified (Aurora Veil
`star_beat_twinkle`, Fractal Tree `silence_gate`, Ferrofluid Ocean `spike_punch_gate`).

**Verification.**
- [x] The manifest matches what the code reads — verified field-by-field against the shader source, not a capture.
- [x] `kind` distinguishes a gate from a driver — `Kind.gate`, documented in SHADER_CRAFT §17 and D-180's manifest line.
- [x] Gate arm proven to bite: floor raised to 1.5 → all three gate routes red at peak 1.00; restored → **201 routes / 21 presets / 0 red**.
- [x] No pixel moved: Aurora Veil's `PresetRegressionTests` golden hashes unchanged (steady / beat-heavy / quiet).
- [x] Engine suite + `xcodebuild -scheme PhospheneApp build` green.
- **No M7 required** — nothing rendered changes; the deleted state never reached a pixel.

**The withdrawn criterion, kept as the lesson.** "RouteCoverageTests sees `drumsEnergyDev` for
Aurora Veil after the fix" would have declared a route with no consumer and gated a value nothing
reads. A liveness capture tells you a primitive is alive in the SESSION; only the source tells
you the preset reads it. `Scripts/check_route_liveness.py` answers the first question — the
second one needs a grep.

---


**Diagnosis only, no fix.** Found because BUG-086's `dsp.stem` manual gate was aimed at
Aurora Veil and returned nothing — for a reason that had nothing to do with BUG-086.

#### How the wrong preset got picked (the process failure, recorded first)

The gate was aimed here on a stale note calling `other_energy_dev` Aurora Veil's
"song-defining anchor, never drop it." **Git contradicts it**: added at `e7cd6e3a`
(AV.2.2f), dropped at `e305839a` (AV.2.h, "drop 5 routes"), and **AV.7 / D-185 reauthored
the preset as a nimitz *Auroras* port onto mood envelopes rather than deviation
primitives** — deliberately, for a GENTLE preset. Aurora Veil declares **no stem route at
all**, so no stem-latency change could ever have shown up in it. A human review was spent
on a question a CSV could have answered first. `Scripts/check_route_liveness.py` exists so
that does not recur: **run it before aiming any manual review at a preset.**

#### Expected behavior

A preset's `audio_routes` manifest enumerates the primitives it reads, with a `kind` that
describes how each is used. QG.1 / D-180 route coverage depends on it being accurate.

#### Actual behavior — measured on capture `2026-08-12T19-57-29Z`

| route | declared | verdict | detail |
|---|---|---|---|
| `star_beat_twinkle` / `barPhase01` | ✅ accent | **ALIVE** | range 901 / 1000 |
| `star_beat_twinkle` / `pulseAmp01` | ✅ **continuous** | **DEAD** | pinned 1.000, p5–p95 range **0.000** |
| `veil_breathe` / `arousal` | ✅ | ALIVE | range 0.178 |
| `veil_breathe` / `bassAttRel` | ✅ | ALIVE | range 0.287, near-entirely negative |
| `mood_colour` / `valence` | ✅ | ALIVE | range 0.453 |
| `drumsEnergyDev` | ❌ **undeclared** | ALIVE | 61 % nonzero, p95 0.997 |
| `vocalsPitchHz` | ❌ **undeclared** | SPARSE | **0.1 % nonzero** |
| `vocalsPitchConfidence` | ❌ **undeclared** | SPARSE | **0.1 % nonzero** |

**`pulseAmp01` is not misbehaving.** The shader uses it as a silence gate, and a gate
pinned at 1.000 through music is exactly right. The defect is the **declaration**:
`kind: continuous` reads as a driver, and WL.1 already measured this primitive as a silence
gate with no dynamic range and ruled it out as a hero driver. That lesson did not propagate
into this manifest.

**The real gaps** are the three undeclared reads. `drumsEnergyDev` is Aurora Veil's only
live stem input and QG.1 cannot see it; the vocals-pitch pair is garnish at 0.1 % — WL.1
measured the same primitive at 4.5 % and called it garnish there too.

#### Suspected failure class

`documentation-drift` primarily (manifest vs code), `calibration` secondarily (a primitive
declared as a driver that cannot drive).

#### Matt's M7, and what it does and does not mean

> *"I don't really see how the preset responds to music beyond the flickering of the stars
> once per bar. The veil is just aurora-ing."* (2026-08-12)

The measurement explains it precisely: **only `barPhase01` has large dynamic range.**
Everything else is a slow narrow mood envelope (0.18–0.45) or effectively dead. The bar
flicker he sees *is* `star_beat_twinkle` working.

**Whether that is a defect or the design is Matt's call, not a measurement.** AV.7 / D-185
chose mood envelopes over deviation primitives for a GENTLE preset and Matt certified it on
2026-07-19. "Reads as uncoupled" may be the intended register. What is objectively wrong is
the manifest. Flagged, not resolved.

#### ⚠ CORRECTION 2026-08-26 (audit pass) — the "three undeclared reads" are not reads

Read against the source rather than the capture: **`AuroraVeil.metal` reads exactly five audio
fields** — `arousal`, `bar_phase`, `bass_att_rel`, `pulse_amp`, `valence` — which is precisely
what the sidecar declares. There is no undeclared shader read. `drumsEnergyDev`,
`vocalsPitchHz` and `vocalsPitchConfidence` are consumed by **`AuroraVeilState.swift`**, which
still computes a kink charge and a smoothed pitch and flushes them to buffer(6) — and AV.7
stopped reading that buffer (`AuroraVeil.metal` header: *"still flushes buffer(6) — also unused
now; left in place to avoid loader churn"*). They are **dead computation on the per-frame path**,
not coupling QG.1 is blind to.

**This inverts the fix.** Declaring `drumsEnergyDev` in the manifest — the third verification
criterion below — would declare a route that reaches nothing, and `RouteCoverageTests` would
then gate a value with no consumer. The correct fix is deletion: drop the dead stem/pitch reads
from `AuroraVeilState` (or the state object, if nothing survives), and fix `pulseAmp01`'s `kind`
so a silence gate stops reading as a driver. That is a small increment, not a preset increment —
no M7, no re-certification, because no rendered pixel changes.

#### Verification criteria (before any fix)

- The manifest matches what the code reads — ideally mechanized, since a hand-maintained
  list drifted here on a certified preset.
- `kind` distinguishes a **gate** from a **driver**, so a silence gate cannot be declared as
  continuous coupling again.
- ~~`RouteCoverageTests` sees `drumsEnergyDev` for Aurora Veil after the fix.~~ **Withdrawn by the 2026-08-26 correction above** — the shader never reads it; the route would be fictional. Replace with: no live-path code computes a primitive no consumer reads.
- If Matt decides the coupling itself is too weak, that is a **separate** preset increment
  with its own M7 — not a manifest fix.

#### Related

**⇄ BUG-086** — this is why that entry's `dsp.stem` gate is still owed. Re-aimed at
**Skein**, verified first: 20 of 28 routes ALIVE, **all eight stem-deviation routes alive**
(`painter_speed` and `flick_trigger` on all four stems, ranges 0.60–1.39), zero DEAD.
### BUG-104 — RESOLVED (WHIT.1d-4): Rosette's curve had visible gaps — the nearest-point search locked onto the wrong branch (2026-08-26)

**Severity:** P1
**Domain tag:** preset.fidelity / sdf-geometry
**Status:** Resolved
**Introduced:** WHIT.0 (`rosetteDist`'s coarse-then-bisect search, 2026-08-25)
**Resolved:** WHIT.1d-4 (2026-08-26)

**Expected behavior.** The two-term epicycle renders as a single continuous closed stroke at
every point in the morph (`a` from 0.05 to 1.80), matching the validated state family
(circle/cusped-star/petals/petals-with-loops/tangle, `ROSETTE_DESIGN.md` §4.1).

**Actual behavior.** After BUG-105's wing fix, Matt's next live look reported: *"Still too
basic... Still broken."* Asked directly what "still broken" meant: *"Lines do not connect. The
motion is all wrong."* Rendered diagnostic stills (`test_rosette_visualDump`,
`ROSETTE_MVWARP_DIAG=1`) confirmed it directly: the tangle state (a=1.80) showed clear gaps
cutting into the stroke at multiple points around the loops; the cusped-star state (a=0.30)
showed small disconnected artifact dots near the cusps.

**Reproduction steps.** Render Rosette's geometry-overlay fragment at `a=1.80` (time =
`kRosettePeriod/2`) at any resolution and inspect the stroke for gaps.

**Minimum reproducer:** `test_rosette_curveIsContinuousAtHighA`
(`RosetteMVWarpAccumulationTest.swift`), or `ROSETTE_MVWARP_DIAG=1`'s `tangle_a180` still.

**Session artifacts.** Diagnostic PNGs generated via the existing env-gated visual-dump test
(not a live session — reproduced directly and deterministically from the shader, no audio
involved). Quantified with a bright-pixel-coverage script against the pre-fix and post-fix
`tangle_a180` stills: **5.92% of the 1920×1080 frame lit before the fix, 6.96% after** — a
17.5% increase in stroke coverage from filling in the gaps, measured, not estimated.

**Suspected failure class:** sdf-geometry.

**Evidence for this class:** `rosetteDist`'s coarse-then-bisect nearest-point search tracked
only the SINGLE globally-closest raw coarse sample, then bisect-refined locally around it. A
self-intersecting curve (which the two-term epicycle becomes at higher `a`, per its own design
doc) can have several distinct branches passing near the same query point; refining from only
one seed locks the search onto whichever branch happened to own the marginally-closest coarse
sample and never considers a different, ultimately-closer branch. Where the wrong branch was
selected, the reported distance was too large, so pixels that should render as stroke rendered
as background — a literal gap. Verified the mechanism directly: temporarily reducing the fix's
`kRosetteMaxBranchCandidates` from 3 to 1 (collapsing it back to old single-branch behavior)
reproduced the exact pre-fix measurement (0.0592) bit-for-bit.

**Verification criteria:**
- [x] New regression guard `test_rosette_curveIsContinuousAtHighA` passes (bright-pixel
      coverage at the tangle state > 0.063, comfortably between the measured broken value
      0.0592 and fixed value 0.0696).
- [x] Confirmed the guard actually bites: temporarily set `kRosetteMaxBranchCandidates = 1`,
      confirmed the test fails reproducing the exact pre-fix number, then restored the fix.
- [x] Visually confirmed via regenerated diagnostic stills: tangle state fully continuous
      (5 clean overlapping loops, no gaps); cusped-star state's remaining small loops at the
      cusps confirmed as REAL curve geometry, not an artifact — the two-term epicycle's second
      term amplitude (`4a` at n=5) exceeds 1 for any `a > 0.25`, so a=0.30 is mathematically
      past the exact-cusp threshold and small self-tangent loops are an expected feature of
      that state, matching `ROSETTE_DESIGN.md`'s own "cusped-star" naming.
- [x] Full existing Rosette suite, `swiftlint --strict`, and the full engine suite (1898
      tests) re-run clean.

**Manual validation required:** Yes — Matt's next live look confirms the curve now reads as
one continuous, correctly-formed stroke through the full morph. Not yet performed as of this
fix landing.

**Fix scope.** Contained to `rosetteDist`: find ALL local minima among the coarse samples
(not just the single global-best raw value, done via a small fixed-size top-3 candidate list),
bisect-refine each candidate branch separately, take the overall closest result. No change to
`rosetteCurve`, the wing arcs, audio routing, or any other function. Cost: coarse phase
unchanged (still 40 samples); refinement now runs on up to 3 candidate branches instead of 1
(worst case ~1.8× the curve evaluations of the old search, most pixels far fewer since most
query points have only one nearby branch) — comfortably within the pass's existing 5.8ms
budget headroom (16.67ms @ 60fps target). Trivial single-increment collapse (root cause
confirmed by direct rendering + a bit-exact revert/restore test, contained to one function, no
architectural risk) — same-session, Matt actively testing live.

**Related:** Increment WHIT.1d-4. Adjacent finding, not itself a defect: `ROSETTE_DESIGN.md`
§6.6 already flagged the coarse-then-bisect search as an unprofiled *performance* risk; this is
the same search's *correctness* failure mode, found live rather than by review.

---

### BUG-105 — RESOLVED (WHIT.1d-3): Rosette's wing cartouche rendered fully off-screen on a real window (2026-08-26)

**Severity:** P2
**Domain tag:** preset.fidelity / renderer
**Status:** Resolved
**Introduced:** WHIT.0 (wing arcs added, 2026-08-25)
**Resolved:** WHIT.1d-3 (2026-08-26)
**Note (2026-08-26):** originally filed as BUG-103; renumbered to BUG-105 when a concurrent
session's unrelated BUG-103 (AVAudioPlayerNode NSException) merged to main first, creating a
duplicate. Content unchanged. Rosette itself is retired (D-224) — this entry is historical.

**Expected behavior.** Rosette's mirrored coloured wing arcs + small ellipses (D-217, "full
cartouche") render near the frame edges on every real window size, as they do in every recorded
test (960×540 / 1920×1080).

**Actual behavior.** On Matt's first live look at Rosette (`2026-08-26T12-58-21Z`, Cherub Rock),
the wings did not render at all — Matt: *"Looks completely broken. A star shape with a broken line
pattern, no additional ornamentation."*

**Reproduction steps.** Run Rosette in the live app at a near-square window (any window with
aspect ratio ≲ 1.2 reproduces it; Matt's session measured exactly 1080×1018, aspect 1.061). Observe
that only the bare epicycle stroke renders — no wing arcs, no ellipses, at any point in the morph.

**Minimum reproducer:** `test_rosette_wingsVisibleAtNearSquareAspect`
(`RosetteMVWarpAccumulationTest.swift`) at 1080×1018.

**Session artifacts.** Session directory: `~/Documents/phosphene_sessions/2026-08-26T12-58-21Z/`.
`session.log`: `RENDER_TARGET width=1080 height=1018 megapixels=1.10 render_scale=1.00`, set before
Rosette became active and unchanged for the rest of the session. `features.csv`: checked first to
rule out a routing failure — `tonal_consonance` (mean 0.076, actively varying), `tonal_phase_fifths`
(full ±π sweep), `harmonic_flux` (peaks just over the 0.09 step-threshold), `bassDev` (mean 0.082,
max 1.665) — all alive and in-range for the whole session. The routing was never the problem.

**Suspected failure class:** sdf-geometry.

**Evidence for this class:** `rosetteWingArc`/`rosetteWingEllipseDist` (`Rosette.metal`) placed the
wings at a hardcoded absolute `x≈0.62–0.67` in the fragment's aspect-scaled coordinate space, where
visible `q.x` spans `±0.5·aspect`. At aspect 1.061 (Matt's window) that visible range is `±0.53` —
strictly inside the wings' hardcoded position, so they render fully off-screen on every frame,
unconditionally. Every test, visual-dump, and flash-safety measurement this program has ever run
used a 16:9-family aspect (1.78, `±0.89` visible), where the wings sit comfortably inside frame —
nobody had ever rendered Rosette at a square or narrow window, so this was invisible to the whole
suite by construction.

**Verification criteria:**
- [x] New regression guard `test_rosette_wingsVisibleAtNearSquareAspect` passes at 1080×1018.
- [x] Confirmed the guard actually bites: temporarily reverted the fix in-place, confirmed the
      test fails (max luma 12/255, background-only) against the pre-fix code, then restored the
      fix and confirmed it passes.
- [x] Full existing Rosette suite (`test_rosette_multiFrameNonDegenerate`,
      `test_rosette_harmonyCoupling`, `test_rosette_rotationAndSymmetryCoupling`,
      `rosetteIsFlashSafe`, `RouteCoverageTests`) re-run clean at the 16:9 reference aspect — the
      scale factor is exactly 1.0 there, so the approved D-217 look is bit-for-bit reproduced.
- [x] `swiftlint --strict` clean; full engine suite (1898 tests) clean.

**Manual validation required:** Yes — Matt's next live look confirms the cartouche is visible on
his actual window. Not yet performed as of this fix landing.

**Fix scope.** Contained: `rosetteWingArc`/`rosetteWingDist`/`rosetteWingEllipseDist` gained an
`aspect` parameter; x-placement scales by `aspect / kRosetteReferenceAspect` (16:9). No change to
`y` placement (already aspect-independent), the figure geometry, or any audio routing. Trivial
single-increment collapse (root cause obvious from the session log + math, <20 lines, no
architectural risk) — approved by Matt in the same session ("yes, fix the aspect-ratio bug").

**Related:** Decision D-217 (the cartouche this bug silently defeated); Increment WHIT.1d-3.

---

