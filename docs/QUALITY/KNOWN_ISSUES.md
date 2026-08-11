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

| ID | Sev | Domain | One-liner |
|---|---|---|---|
| BUG-085 | P1 · HANG.1–2 complete 2026-08-05; remains open | renderer / app.hang | **App intermittently hangs hard in `CAMetalLayer.nextDrawable`; window unresponsive, force-quit required.** The live stack proves a main-thread drawable request blocked at 0 % CPU after healthy frames, but the cause remains unknown; direct render-path leakage, the capture hook, preset-swap skip, inflight semaphore, GPU completion, display sleep, and occlusion have been ruled out. **HANG.1 instrumentation is merged to `main` via PR #37 (`c54a2e7c`)**. HANG.2 completed a full-track control plus a 10 min 36 s Witchlight soak with 34,811/34,811 drawables balanced and no stalls or imbalances, refuting a deterministic per-frame leak but not identifying the intermittent owner. **THE INSTRUMENTED CAPTURE NOW EXISTS (2026-08-05, session `2026-08-05T21-21-03Z`, Fractal Tree / Cherub Rock)** — and every lifecycle counter is BALANCED at the moment of the hang: `drawable=12045/12045`, `unique_presented=6012/6012`, `command_completed=6012/6012`, `failures=0`, `unpresented=0`, one request outstanding (`pending=frame:6013,site:mesh.descriptor`). The app held ZERO drawables and CoreAnimation still would not vend one, which independently confirms HANG.2's soak: there is no app-side leak, and the owner is outside the app. Two captures 98 s apart are byte-identical on those counters — a PERMANENT block, not a long stall. See the detail section. |
| BUG-081 | P2 | app.hang | **3 instances now** (2026-08-03 ×1, 2026-08-04 ×2). | **App beachballed ~78 s into session `2026-08-03T22-54-06Z` and needed a force-quit; no `.ips` exists** (force-quit produces none) and `session.log` ends mid-normal-operation with no fatal. **Evidence-only — no root cause asserted.** What the capture DOES establish: the renderer was healthy to the last frame — steady 60 fps, Fractal Tree at **0.18 ms GPU against a 0.7 ms budget**, no degradation trend across 3756 frames; background ML load rising but modest (`stem_analyzer_ms` 0 → 3.4). **Ruled out by test:** FTR.2's shader overflowing the mesh primitive limit via a bad `branch_count` — no non-finite values in the capture and `branch_count` never exceeds 59 against the 63 ceiling. A frozen UI with a live render loop points away from the preset, but that is inference and BUG-061's rule forbids acting on it. **Same class as BUG-060** (force-quit hang, render loop died, no stack captured, never reproduced) — two instances now, both blocked on the same missing artifact. **Next evidence:** `sample PhospheneApp 10 -file ~/Desktop/phosphene-hang.txt` run DURING the beachball, before force-quitting |
| BUG-086 | P2 · **fix code-complete 2026-08-11, validation incomplete** | dsp.stem / calibration | **Every per-stem feature reaches presets ≈5.4 s behind the audio, on the local-file path, in steady state — while the beat grid beside it is time-aligned to ≈0.3 s.** Root cause is read, not inferred: separation runs on a fixed 10 s chunk (`modelFrameCount = 431` — the exported Open-Unmix model cannot take a shorter one) every **5 s**, and `runPerFrameStemAnalysis` starts its read window **5 s into** that chunk to buy one separation period of runway. So `lag = chunkLength − startOffset ≥ separationPeriod`, exactly. Measured three independent ways, agreeing: 5.4 s on 39 of 40 stem × track pairs. Affects every stem-driven preset, Aurora Veil's `other_energy_dev` anchor included. Diagnosis only — no fix code, per the multi-increment process. Detail: `docs/diagnostics/CHR1_STEM_DECORRELATION_2026-08-11.md` §7b + §8 |
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

### BUG-086 — Per-stem features reach presets ≈5.4 s late; lag is structurally pinned to the separation period (2026-08-11)

Found while measuring driver viability for a plotting preset (CHR.1), where the
lag is disqualifying rather than cosmetic. **Diagnosis increment only — no fix
code.** Full measurement and method: `docs/diagnostics/CHR1_STEM_DECORRELATION_2026-08-11.md`
§7b (evidence) and §8 (root cause + the fix trade).

#### Expected behavior

Per-stem features (`{stem}Energy`, `…EnergyRel`, `…EnergyDev`, onset rate,
centroid, attack ratio, slope) describe the audio the listener is hearing now,
to within roughly the same tolerance as the real-time band features.

#### Actual behavior

They describe audio from **≈5.4 s ago**, steady state, on the local-file path.
The real-time band features (`bass`/`mid`/`treble`) are correct to 0.2–0.4 s, so
a preset reading both gets two clocks that disagree by 5 s.

#### Reproduction steps

Any local-file session ≥ 90 s. Measured on `beat-match-test-session` (16
full-length tracks) and `2026-08-11T01-07-17Z` (*Cherub Rock*).

#### Session artifacts

Three independent measurements, all agreeing, escalating in cleanliness:

1. Tap cross-correlation, cold start (30 s tap): bands peak at −0.30…+0.08 s;
   stems have no peak inside ±3 s, and a single broad unimodal peak at ≈10 s
   (r +0.58) when widened to ±20 s.
2. Tap cross-correlation, steady state (full 2.04 GB tap, four 60 s windows ≥ 90 s
   into a track): control `bass` peaks at **0.20–0.40 s** — alignment confirmed —
   while every stem peaks at **5.61 / 5.81 / 5.61 / 5.61 s**.
3. CSV-internal, no WAV: each stem feature against the time-aligned `bass+mid`
   sum, both at 60 Hz — **5.4 s on 39 of 40 stem × track pairs**, r up to +0.94.

Corroborates TRK.2's independent 5–10 s finding.

#### Suspected failure class

`calibration` — a deliberate offset whose cost was never measured, not a coding
error. Every line below does what it says it does.

#### Root cause (read from source, not inferred)

- `VisualizerEngine+Stems.swift:49` — `timer.schedule(deadline: .now() + 10, repeating: 5.0)`: separation every **5 s**.
- `VisualizerEngine+Stems.swift:166` — `stemSampleBuffer.snapshotLatest(seconds: 10, …)`: the chunk is the latest **10 s**, so chunk sample 0 is audio from 10 s ago and the chunk's end is "now".
- `VisualizerEngine+Audio.swift:333` — `let startSample = Int(5.0 * sampleRate)`: the per-frame read window starts **5 s into** the chunk, i.e. at audio already 5 s old, then advances at real time.

So `lag = chunkLength − startOffset`, and the read can only advance for
`chunkLength − startOffset` seconds before clamping at the chunk's end — which
must cover one separation period. Hence:

> **lag ≥ separationPeriod.** The 5 s head start is exactly the runway needed to
> survive one 5 s period. It is not slack.

**Chunk length is not a lever.** `StemSeparator.modelFrameCount = 431` is
commented "Fixed number of STFT frames the model expects" → `requiredMonoSamples
= 440320` ≈ 10 s at 44.1 kHz. Shortening the chunk needs a re-exported model.

#### The fix trade

Reducing lag means reducing the separation period, at one full inference per
period (cost fixed, because the model always consumes 10 s):

| period | resulting lag | inference duty |
|---|---|---|
| 5 s (today) | ≈5 s | ≈2.8 % |
| 2 s | ≈2 s | ≈7.1 % |
| 1 s | ≈1 s | ≈14.2 % |

`startSample` must move to `chunkLength − period` in the same change, or the read
clamps and the features freeze between separations (a stutter, which for a
plotting preset is worse than the lag).

⚠ **The 142 ms inference figure is the code comment at `VisualizerEngine+Stems.swift:211`,
not independently measured** — no session artifact records separation cost, so
the duty column is an estimate. Measuring it is step 1 of any fix increment.
⚠ `MLDispatchScheduler` (D-059) already defers dispatch when frames run over
budget, with a 2 s ceiling. At short periods deferral becomes common, so
worst-case lag is `period + deferral`, not `period`.

#### Verification criteria (written before any fix)

- Automated: the CSV-internal measurement above, as a gate — stem features must
  track the `bass+mid` band sum at a lag below the chosen target on a real
  capture. Reuses recorded sessions, no new fixtures.
- Automated: no regression in `stem_analyzer_ms` / frame budget; `MLDispatchScheduler`
  deferral rate recorded before and after.
- Manual: `dsp.stem` requires observed musical connection. Any change to stem
  timing is felt on every stem-driven preset — Aurora Veil (whose
  `other_energy_dev` route is load-bearing), Skein, Meniscus, FFO — so M7-class
  observation on at least Aurora Veil before it is called fixed.

#### Fix — code-complete 2026-08-11, NOT yet validated

Period 5.0 s → **2.0 s**, and the read start **derived** from it rather than being a
fourth independent literal:

```
stemChunkSeconds            10.0   (pinned to the model, asserted against
                                    StemSeparator.requiredMonoSamples)
stemSeparationPeriodSeconds  2.0   (was 5.0)
stemReadMarginSeconds        0.5   (slack for inference + D-059 deferral)
stemReadStartSeconds         7.5   (derived: chunk − period − margin)
→ nominal latency            2.5 s (was ≈5.4 s measured)
→ inference duty            ≈7 %   (was ≈2.8 %; estimate, see below)
```

Margin is deliberately > 0: clamping is **not** a stale freeze — the window pins to
the chunk's *newest* audio, so latency momentarily collapses toward zero and jumps
back when the next chunk lands, which reads as a glitch rather than a lag.

`STEM_SEPARATION: inference=…ms period=…s duty=…% nominal_latency=…s` now goes to
`session.log` every separation, so the duty estimate above becomes checkable from a
capture — it previously rested on a 142 ms figure that existed only in a code
comment, which is why the pre-fix cost was never verifiable.

`StemSeparationCadenceRegressionTests` (7 tests) asserts the *relationship* rather
than the values — runway ≥ period, margin > 0, latency < 3 s, read start derived,
chunk pinned to the model — so retuning the cadence stays free while re-breaking the
invariant does not.

**The gate was verified to bite, not merely to be green.** Setting the period back
to 5.0 and re-running fails the latency test with
`stemNominalLatencySeconds → 5.5 < 3.0` — so the suite would have caught the pre-fix
configuration. A green assertion that also passes against the defect is worthless;
this one was checked against it.

**Automated verification complete (2026-08-11):**

- `swiftlint --strict` — 0 violations, 503 files
- `xcodebuild build` — succeeded
- Engine suite — **1809/1810**; sole failure is the pre-existing DOC.6 rotation gate,
  identical to the branch point
- App target — **411/411** (404 before this change, plus the 7 new tests; no existing
  test moved). Required quitting a live `PhospheneApp` first — **BUG-072**.

**Measured latency is NOT yet verified, and the constants test does not verify it.**
`StemSeparationCadenceRegressionTests` gates the arithmetic that *produces* 2.5 s; it
cannot observe what the pipeline delivers. `Scripts/measure_stem_latency.py <capture>`
does, from a real session:

```
Scripts/measure_stem_latency.py ~/Documents/phosphene_sessions/<capture>
```

It cross-correlates each stem's `energyRel` against the time-aligned `bass+mid` band
sum (both at ~60 Hz, CSV only — no WAV, whose per-capture sample rate differs and
silently scaled the time axis by 8.8 % in an early version of this measurement),
reports per-stem lag with correlation strength, and PASS/FAILs against a 3.0 s
ceiling. Validated against the pre-fix corpus: 15 of 15 `beat-match-test-session`
segments report **5.4–5.5 s**, matching the original finding. It also detects a
pre-fix capture from the absence of `STEM_SEPARATION` and says so, so a stale capture
cannot be misread as a regression.

*Its verification-criteria form was corrected in building it.* This entry originally
specified "an automated gate". The lag is a live-pipeline property of the ML timer,
wallclock advance and `MLDispatchScheduler` deferral — no unit test can synthesize it,
and a synthetic one would be the green-test-measuring-the-wrong-thing trap. The honest
artifact is a measurement over a capture a human supplies.

#### Post-fix captures — two sessions, 2026-08-11 (`23-35-27Z`, `23-44-40Z`)

> **⚠ CORRECTION.** This section first reported "measured lag 5.4 s → 2.9 s, PASS" from
> `23-35-27Z`. **Withdrawn — that was a false pass.** It rested on r 0.42/0.48 with no peak
> behind it, squeaking past a `MIN_R` floor of 0.40 that was too permissive. The floor is
> **0.60** now and both post-fix captures correctly report **INCONCLUSIVE**. The fix's
> *direction* is confirmed (the lag peak moved from a sharp 5.4 s to somewhere in 0–3 s) but
> **post-fix latency is not yet measured**, and the duty numbers below — which are direct log
> readouts, not correlations — are unaffected.

**The tool needs a long capture, and that is not a post-fix phenomenon.** Correlation quality
is a property of the capture, measured across the corpus:

| capture regime | r | shape |
|---|---|---|
| `beat-match-test-session` (88 min, 16 tracks) | **0.70–0.94** | sharp unimodal peak |
| single-track captures, 1–4 min | **0.19–0.48** | flat, no peak |

Both regimes appear in **pre-fix** captures — `2026-08-11T01-07-17Z` (Cherub Rock, 255 s,
pre-fix) reads r 0.19–0.36 — so short-capture weakness is not caused by anything BUG086.1
changed, and is not evidence about the fix either way.

**Two hypotheses for the weak post-fix correlation were tested and both refuted**, recorded
so they are not re-run: (1) *clamping degrades the features* — correlation on clamped vs
unclamped frames is identical (drums 0.388 vs 0.381; bass 0.413 vs 0.368), so clamping costs
timing fidelity nothing measurable; (2) *the reference signal is too flat* — post-fix
reference SD is **higher** than pre-fix (0.118/0.142 vs 0.071/0.115). A third guess was not
made; the honest state is that short captures are below this measurement's resolution.

**What a like-for-like before/after needs:** the same 16-track BeatBench corpus replayed on a
fixed build. That is the only capture that has ever produced a clean number, and reusing it
makes the comparison identical-material rather than a different track at a different length.

Two findings that DO stand, both from direct `session.log` readouts:

| | assumed at BUG086.1 | **measured `23-35-27Z`** | **measured `23-44-40Z`** |
|---|---|---|---|
| inference per separation | 142 ms (a code comment) | **335 ms** median (284–649, n=33) | **478 ms** median (421–596, n=63) |
| inference duty at 2 s period | ≈7 % | **≈20.5 %** | **≈25.6 %** |
| preset-facing lag | 2.5 s nominal | inconclusive | inconclusive |

**1. Inference is 2.4–3.4× the assumed cost, so duty is 20–26 %, not ≈7 %.** This is exactly
the caveat this entry flagged — the 142 ms figure existed only in a code comment with no
artifact behind it, and it was wrong. Note the second capture is *higher* than the first
(478 ms vs 335 ms median, and its **minimum** 421 ms exceeds the first capture's median), so
inference cost is variable across material or system load, not a single constant.

**It is nonetheless sustainable, on the engine's own signal.** 33 separations over a 65 s
span against 33 expected, and 63 over 124 s in the second capture — both at the nominal 2 s
cadence: `MLDispatchScheduler` (D-059) is absorbing the
load with jitter, not falling behind. Frame-pacing comparison against pre-fix captures is
**inconclusive and should not be quoted** — the pre- and post-fix sessions ran different
presets (`frame_gpu_ms` p50 0.15–0.21 vs 6.71), so the difference is preset-confounded, not
attributable to the cadence. `deltaTime > 20 ms` is 3.51 % post-fix against a pre-fix range
of 1.75–3.88 %, i.e. inside the existing spread.

**2. The 0.5 s read margin is too small — the read window clamps on ~25 % of cycles.**
Separation-to-separation gaps measured 0/1/2/3/4 s (×2/6/16/5/3). Runway is
`period + margin` = 2.5 s, so the 3 s and 4 s gaps — 8 of 32 cycles — overrun it by 0.5–1.5 s
and the window pins at the chunk's newest audio until the next chunk lands. Worst-case
inference alone does it too: 2.0 + 0.649 = 2.649 s > 2.5 s.

**The margin was sized against the wrong quantity.** It was set to absorb inference time;
the binding constraint is *deferral-induced gap jitter*, which reaches 4 s.

**Recommendation: do not re-tune now — and this is now tested, not assumed.** The earlier
version of this paragraph argued clamping was probably imperceptible. It was then measured
directly: correlation on clamped frames matches unclamped frames (drums 0.388 vs 0.381; bass
0.413 vs 0.368), so clamping costs timing fidelity nothing detectable. It also costs no extra
latency — pinning to the newest audio makes latency momentarily *better*. Covering a 4 s gap needs `margin ≥ 2.0 s`, i.e.
**4.0 s nominal latency** — paying 1.1 s of permanent latency to remove a discontinuity that
no shipping preset can currently show, since every stem consumer today drives slow envelopes
where a sub-second freeze is imperceptible. **It becomes a real decision the moment a
stem-plotting preset ships** (Stave is exactly that), and it is recorded here so that
session does not rediscover it.

**Outstanding before this is Resolved:**

1. **Post-fix latency is still unmeasured.** Both post-fix captures are INCONCLUSIVE under
   the corrected `MIN_R = 0.60`. **Replay the 16-track BeatBench corpus on a fixed build** —
   identical material to the pre-fix 5.4 s baseline, and the only capture regime that has
   produced r 0.70–0.94. A 1–4 minute single track is below this measurement's resolution.
2. **The `dsp.stem` manual gate.** Stem timing is felt on every stem-driven preset;
   Aurora Veil (`other_energy_dev` load-bearing), Skein, Meniscus and FFO all shift.
   Needs M7-class observation on at least Aurora Veil. No automated test substitutes.

#### Related

**⇄ BUG-084** is the other open `dsp.stem` calibration defect (deviation reaching
35 against a ~3.4 ceiling). Same subsystem, independent causes; a fix increment
touching `StemAnalyzer` timing should check it has not disturbed BUG-084's
fixtures.

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

### BUG-078 — Engine test process traps in `AVAudioPlayerNode` teardown: `dispatch_sync` on an already-owned queue (2026-07-30)

**P2 · audio.playback / concurrency · RESOLVED 2026-08-10 (BUG078.3) — second, independent route to the same trap closed; measured 10 crashes / 14 runs before, 0 / 30 after. Reopened 2026-08-10 after BUG078.1 (2026-08-07, `f68efb67` / PR #62) closed only the first route.** Found at DBN.1 while running the closeout evidence; **pre-existing, not introduced by that increment**. P2 rather than P1 because it has only been observed taking down the *test* process — but the code path is shipped local-file playback, so the app-facing impact would be a hard crash.

#### Resolution (2026-08-10, BUG078.3) — the reschedule path, not the overwrite

**Root cause, with a stack this time.** Captured under `lldb` (`-k "thread backtrace all"`; macOS wrote no `.ips` for any occurrence). Faulting thread, queue `CommandQueue`:

```
__DISPATCH_WAIT_FOR_QUEUE__  ←  brk (libdispatch deadlock detector)
_dispatch_sync_f_slow
AVAudioPlayerNodeImpl::StopImpl() → AVAudioNodeImplBase::Stop()
~AVAudioPlayerNodeImpl → -[AVAudioNode dealloc]
_Block_release → ~AVAEBlock<…AVAudioPlayerNodeCompletionCallbackType…>
~Command → ~FileCommand → FileCommand::Perform(CommandQueue&)
CommandQueue::PerformWork(bool)
```

Concurrently: one thread inside `-[AVAudioEngine mainMixerNode]` (a second engine being built) and one blocked in `start()` → `stop()` on the provider's `NSLock`.

**The mechanism.** `scheduleFileLoop`'s reschedule path checked `playerNode === player` under `lock`, **released the lock**, and only then called `player.scheduleFile`. A `stop()` landing in that window nils the fields and runs `player.stop()` — so the command was armed on a node the provider had already released. AVFAudio's own `AVAEBlock` wrapper retains the node inside the queued command (our closure captures everything `weak`, so it is AVFAudio's retain, not ours), making that command the node's **last strong reference**. Its destruction on the node's own `CommandQueue` ran `-[AVAudioNode dealloc]` there, whose `Stop()` `dispatch_sync`s into the queue it is already running on. libdispatch traps.

**Why BUG078.1 did not catch it, and why its gate stayed green.** BUG078.1 closed the *overwrite* route — an instance orphaned while running. This is a different route to the identical trap: the instance **is** torn down correctly, and a command outlives the teardown. That is exactly why `concurrentStart_neverOrphansARunningInstance` kept passing while the process still trapped: adopted == torn down was never the violated invariant. **A green invariant gate is only evidence about the invariant it states.**

**Instrumented proof of the window** (temporary probe counting re-arms issued on a non-current player, 14 runs): **every run that recorded a stale schedule crashed (8/8); no clean run recorded one (0/4).** The two crashes with zero recorded hits are consistent with the probe under-counting — it had the same check-then-act window it was measuring.

**Fix.** `scheduleFileLoop` becomes `_scheduleFileLoopLocked`, called with `lock` held, so the identity check and the re-arm are one critical section. Both orderings are then safe, because `stop()` / `start()` swap the fields under that same lock *before* the AVFoundation teardown runs: the re-arm either wins the lock and arms while the node is still ours (the teardown's subsequent `player.stop()` drains it), or it sees the swap and bails. No new ABBA against BUG-021 — `scheduleFile` only enqueues, the teardown's `player.stop()` still runs outside the lock, and the completion handler still hops off the callback queue before touching the lock (BUG-059).

**Verification against the criteria filed at BUG078.2:**
- [x] **0 crashes in 30 runs** of `swift test --filter concurrentDoubleStart`, against **10 in 14** on the same filter before. The orphan gate stays green.
- [ ] **A fast deterministic gate that fails on the surviving race — NOT achieved, and not claimed.** `rescheduleRacingTeardown_neverArmsACommandOnAReleasedNode` was built for this and **does not reproduce the trap**: 0 traps in 6 runs against the faithful pre-fix ordering (an earlier stop-vs-start shape: 0 in 5). The crash needs the accumulated load of the full churn suite — the same conclusion the BUG078.1 authors reached for the first route. The test is retained because it asserts the guard *fires*, proving the window is entered, but a green result there is **not** evidence the race is closed. The load-bearing signal is the 14-run/30-run before-after above.
- [x] **A stack for the failing path** — captured above.
- [ ] Manual app-level start/stop churn walk — not run; no musical-feel or visual surface, and the shipped risk is a hard crash rather than a behavioural change.

**Honest residual.** The fix is justified by a captured stack, a measured window, and a 0/30-vs-10/14 before-after — not by a gate that goes red on demand. If this trap is seen again, do not assume this route: capture a stack first, as this round did.

#### Recurrence (2026-08-10, DOC.7 closeout evidence) — REOPENS this entry

**The fix is present and the trap still fires.** `f68efb67` is an ancestor of the tree under test (`git merge-base --is-ancestor` → true) and `LocalFilePlaybackProvider` carries the snapshot-under-lock change and its BUG-078 comments. The process still dies with `EXC_BREAKPOINT` / `SIGTRAP` (`exited with unexpected signal code 5`).

**Reproduction rate, measured not anecdotal.** 20 consecutive runs of `swift test --filter 'LocalFilePlaybackProvider|SessionLifecycleChurn|concurrentDoubleStart'`: **4 crashed (iterations 8, 12, 16, 18) — 20 %.** Every one signal 5. First seen in a full-suite closeout run at 2026-08-10 08:43, which did not reproduce on the immediate re-run (1809 tests green) — the 4/20 loop is what pinned it.

**Where it fires.** In all four, the five preceding tests pass and the process dies during **`concurrentDoubleStart_serializesWithoutDeadlock()`** — the same test the pre-fix `.ips` reports named, and the exact race BUG078.1 targeted. The crash is at teardown, after assertions have passed, so it presents as a suite-level exit 1 with **no failing test line**, which is how it hid inside an otherwise-green run.

**What is NOT established.**
- **No stack for a post-fix occurrence.** macOS wrote no new `.ips` for any of the four (the newest report on disk is 2026-08-08 08:51:57, and the 2026-08-03 file's mtime is merely being touched). Without one, the *mechanism* of the surviving race is unknown — do not assume it is the same overwrite the fix closed.
- **The 2026-08-08 report is not evidence of a post-fix failure.** Its signature is identical (`__DISPATCH_WAIT_FOR_QUEUE__` → `_dispatch_sync_f_slow` → `AVAudioPlayerNodeImpl::StopImpl()` → `~AVAudioPlayerNodeImpl` → `-[AVAudioNode dealloc]` ← `_Block_release`, naming `concurrentDoubleStart_serializesWithoutDeadlock` / `_startLocked()` / `stop()`), but it carries no worktree path, and on 2026-08-08 most worktrees did not yet have the fix. Treat it as consistent-with, not proof-of.
- **Whether the entry's deterministic adopted-vs-torn-down gate still passes.** Not re-run here.

**Suspected failure class:** `concurrency` (unchanged). The fix demonstrably narrowed the window — the entry records a 1-in-3 full-suite rate before it, against 4/20 on a targeted filter now — but did not close it.

**Verification criteria (written before any fix, per the defect protocol).**
- [ ] Automated: the 20-iteration loop above runs **0/20** crashes; and the entry's adopted-vs-torn-down gate stays equal over its 24 racing double-starts.
- [ ] Automated: a regression gate that fails on the *surviving* race specifically, in seconds rather than by lottery — the BUG078.1 gate did this for the overwrite and must be extended, not trusted, since it passes today while the trap still fires.
- [ ] Artifact: one `.ips` from a post-fix crash, with the faulting thread and both racing threads. **Without a stack this is a guess** — the 2026-08-07 round already overturned one confident hypothesis (the completion-block retain) that a stack disproved.
- [ ] Manual: none required — no musical-feel or visual surface. The shipped-path risk is a hard crash in local-file playback, so an app-level start/stop churn walk is worth one pass once a fix exists.

**Evidence:** `/tmp/BUG078_recurrence_2026-08-10_evidence.txt` (the closeout run that first showed it); per-iteration logs `/tmp/rep_{8,12,16,18}.log`. Both are scratch paths and will not survive — re-run the loop rather than relying on them.

**Why it was not fixed in the increment that found it.** DOC.7 was a doc-gate change (shell script + doc test + markdown) and cannot reach audio playback; the protocol's evidence-before-implementation rule applies, and there is no stack yet. Filed, not fixed.

**ROOT CAUSE (2026-08-07) — a concurrent-`start()` overwrite, not the completion block.** `start()` calls `stop()` *before* taking the lock (BUG-021, so AVFoundation teardown never runs under the provider's `NSLock`). Two racing `start()` calls therefore interleave as: thread B's `stop()` snapshots nothing → thread A's `_startLocked()` adopts engine/player #1 and starts playing → thread B's `_startLocked()` **overwrites the fields with #2**. Instance #1 is orphaned *while running*: never stopped, never detached, observer never removed. Its last strong reference is the one AVFAudio holds inside the pending `scheduleFile` completion block, so the node is finally released on its own `CommandQueue`, where `-[AVAudioNode dealloc]` → `Stop()` → `dispatch_sync` re-enters the queue it is already running on. `_startLocked`'s comment asserting "the fields below are guaranteed nil" was the false premise; it is corrected in place.

**Measured, not inferred.** A new deterministic gate counts adopted instances against teardowns over 24 racing double-starts: **pre-fix 48 adopted / 25 torn down — 23 running engines orphaned**; post-fix the counts are equal. It fails in ~3 seconds instead of the 1-in-3 full-suite lottery.

**Fix.** `start()` snapshots the existing refs under the lock (a pointer copy — no AVFoundation calls, so BUG-021's constraint holds), then tears them down after unlocking with a strong reference held across `player.stop()`, which drains the node's command queue before the final release. The orphan leak is closed by the same change.

**Two corrections to this entry's earlier text, both worth keeping.**
1. **The leading hypothesis was wrong.** The strong `self` materialised by `guard let self` in `scheduleFileLoop` is not the mechanism. The crash stack has **no Swift frames** between `_Block_release` and `-[AVAudioNode dealloc]` — the object released there is the node itself, retained by AVFAudio's own wrapper block. Every capture in our completion block is `weak` and none was ever implicated.
2. **"Nobody has captured the trap itself" was not true.** `~/Library/Logs/DiagnosticReports/` held **25 matching `.ips` reports**, 19 of them naming `concurrentDoubleStart_serializesWithoutDeadlock` on a live thread, plus the two racing threads (`_startLocked()` on one, `stop()` on the other) that make the overwrite visible. The evidence had been on disk since 2026-07-26; what was missing was reading it, not capturing it.

**Sighting history, collapsed at close.** Four further sightings were recorded between 2026-08-03 and 2026-08-04 (RECON closeout, RECON.11) across different trees, each documenting the same thing: **nonzero exit with `0 failures (0 unexpected)` and no per-test failure line**, the raw tail sitting on the `LocalFilePlaybackProvider` concurrency cases, and the immediately following run passing clean. Rate over that audit: **~2 trips in 6 full-suite runs**. Two notes that outlived the diagnosis: the signature to look for is **exit-code-without-failure, not a red test** (an extractor that only reports failing assertions shows nothing), and it fires on an unmodified tree during docs-only work, so it needs no particular code state. The per-sighting paragraphs are dropped here because they existed to narrow an unknown cause; the cause is known.

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

**Verification status (BUG078.1) — ALL CRITERIA MET.** Regression gate met in a stronger form than specified: `LocalFilePlaybackStartRaceTests.concurrentStart_neverOrphansARunningInstance` asserts the orphan count deterministically rather than waiting for a timing-dependent trap (red before the fix at 23/48, green after). `SessionLifecycleChurnTests` 6/6 green. Full-suite ×5 no-`.ips` criterion met — 5 consecutive runs, 1794 tests / 270 suites each, all passing, `~/Library/Logs/DiagnosticReports` unchanged at 28 `.ips` throughout. Read honestly: against the ~1-in-3 observed trip rate, 5 clean runs alone would happen by luck ~13 % of the time, so the load-bearing evidence is the deterministic orphan count (23 → 0), not the streak.

**Manual criterion met — Matt, session `2026-08-07T19-10-25Z`, 5 local files.** Start, pause/resume, natural track end, single Next, rapid Next, and quit all passed; `CHAIN_HEALTH: verdict=clean reasons=[]`, drawable lifecycle balanced (4815/4815), no hang and no crash. The session is the artifact, not the impression: the provider's breadcrumbs give **19 `provider.start INSTANCE` against 18 `provider.teardown ENTER`** in the exact strict alternation `I(EXI)*` — every instance the session adopted was torn down before the next was adopted, and the unpaired 19th is the one still playing when the log ends (`deinit`'s teardown passes `diagnostic: nil`, so it never emits a breadcrumb). **Zero orphans on a real session, including two rapid-Next bursts** (3 starts inside 19:14:56, 5 inside 19:15:02).

**One honest limit on what the live session proves.** Every teardown in it is ordered `ENTER → EXIT → INSTANCE` — the *pre-lock* `stop()` path. The BUG078.1 stale-teardown path would print `INSTANCE → ENTER`, and it never fired, because the app's transport drives `start()` from the MainActor and therefore serialises it. So the live run establishes **no regression on the shipped path** and confirms the orphan invariant in production; it does **not** exercise the concurrent-`start()` race itself. That race is only reachable from a multi-threaded caller — which is why the trap has only ever been seen in the test process — and the deterministic gate is what covers it. Both statements are needed; neither alone closes this.

**Out of scope for DBN.1** (which is a docs/spec increment). Filed and reported, not fixed.

---

---

---

### BUG-079 — `swift test -c release` does not build, so release-only performance budgets are unverifiable (2026-07-30)

**P3 · build / test-isolation · RESOLVED 2026-08-07 (BUG079.1).** Found at DBN.2 when trying to measure a release-only budget; **pre-existing**, unrelated to that increment.

**Resolution.** Dropped the `#if DEBUG` around `ArachneState.forceActivateForTest(at:)` (the second of the two fix shapes below — the smaller one, guarding the call sites, would have silently dropped the Arachne render coverage from release runs). The doc comment now says why it is ungated so it is not re-added. `DSPPerformanceTests.test_beatActivationDecoder_30sWindow_performance` asserts the plan's real **50 ms budget in release** and keeps the 4000 ms regression ceiling in debug.

**The budget is now measured and it is met: 17.9 ms** for a 30 s window (M2 Pro, release), against 1403 ms in debug — a **78×** config gap, which is why the debug figure was never informative. No design change needed.

**One correction to the original filing:** `swift test -c release` alone still does not work, and that is not a defect — `@testable import` requires testability, which release builds do not enable by default. The working invocation is:

```bash
swift test -c release -Xswiftc -enable-testing --package-path PhospheneEngine
```

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

### BUG-082 — Session retention keeps 6, not 10: fixture folders occupy the slots permanently (2026-08-03)

> **Renumbered 080 → 082 at merge.** Filed as BUG-080 against a tree where 079 was the highest; a parallel session landed a *different* BUG-080 (gitignored-asset propagation) on `main` first, and `DocIntegrityTests` gates BUG-number uniqueness. **The commits on this branch are titled `[BUG-080]` — they mean this entry.** Its sibling was filed as BUG-081 and hit the SAME collision one merge later (a parallel `main` BUG-081, an unrelated beachball), so it is now **BUG-083**; its commits are titled `[BUG-081]`.

**P2 · app.diagnostics / algorithm · RESOLVED 2026-08-03.**

**Resolution.** `sessionFolders` now filters to directories whose name parses as a session timestamp, so a non-session directory is neither counted against the limit nor a deletion candidate. `dateFromFolderName` was rewritten as a strict whole-string `DateFormatter` match — the previous character-substitution routine did `index(startIndex, offsetBy: 10)` unconditionally and traps on any shorter name, which was unreachable while only the age-based arms called it but becomes reachable the moment every directory is parsed (a folder named `old/` would have crashed app launch). Regression tests in `SessionRecorderRetentionPolicyTests`: `lastN10_nonSessionFoldersNeitherCountedNorDeleted` (12 sessions + the 4 real fixture folders → exactly the 2 oldest sessions deleted, fixtures untouched), `oneWeek_doesNotDeleteNonSessionFolders`, `shortAndOddFolderNamesDoNotTrap`. **The regression test was confirmed to fail before the fix** — it reported 6 surviving sessions against the expected 10, reproducing the defect exactly.

**Expected.** With the default `lastN10` retention, the ten most recent *session recordings* survive; older ones are pruned.

**Actual.** Six survive. `SessionRecorderRetentionPolicy.sessionFolders` enumerates every directory under `~/Documents/phosphene_sessions/` and sorts `$0.name > $1.name` on the stated assumption that "ISO timestamps sort lexicographically" — but the directory also holds permanent non-session folders, and in ASCII letters sort above digits. Verified against the live directory:

```
 1 fixturegen-there_there        <- not a session
 2 fixturegen-so_what            <- not a session
 3 fixturegen-love_rehab         <- not a session
 4 beat-match-test-session       <- not a session
 5 2026-08-03T21-07-43Z          <- newest real folder is only rank 5
...
11 2026-08-03T19-49-56Z          <- deleted next
```

`lastN10` does `Array(folders.dropFirst(10))`, so the four fixture folders permanently consume four retention slots **and can never be pruned themselves** (they are always in the kept prefix). Effective session retention is `10 - <number of named folders>` = 6 today, and it shrinks further as fixture folders are added.

**Reproduction.** `ls -d ~/Documents/phosphene_sessions/*/ | sort -r` — any folder not named `YYYY-MM-DDTHH-MM-SSZ` appears above every real session.

**Impact.** Real captures are deleted well before the user's setting says. Observed live on 2026-08-03: session `2026-08-03T15-05-43Z` was evicted **while it was being used** as the input for Witchlight motion-sequence renders, forcing a re-render against a different capture. Compounds with BUG-081, which manufactures folders that consume the same slots.

**Failure class.** `algorithm` — an ordering assumption ("every directory here is a timestamp") that the directory's actual contents violate.

**Fix (not implemented).** Filter `sessionFolders` to entries whose name parses as an ISO timestamp. `dateFromFolderName` already exists in the same file and the `oneDay`/`oneWeek` arms already rely on it; only the `lastN` arms skip the check. One-line filter plus a regression test that plants a named folder among timestamped ones and asserts it is neither counted nor deleted.

**Verification criteria (written before the fix).** (1) Automated: a `SessionRecorderRetentionPolicyTests` case with 4 named folders + 12 timestamped ones under `lastN10` deletes exactly the 2 oldest *timestamped* folders and leaves all named folders untouched. (2) Manual: with 10+ real sessions on disk, launch the app and confirm the count of timestamped folders afterwards is 10, not 6.

---

### BUG-083 — A session folder is written on every engine construction, including test runs (2026-08-03)

**P2 · app.diagnostics / test-isolation / resource-management · RESOLVED 2026-08-03.**

**Resolution.** `SessionRecorder.init` no longer touches the filesystem — it computes paths only. Directory creation, CSV headers, the startup banner and the disk-space pre-flight moved into `materializeIfNeeded()`, called on the serial queue from the first actual write. Every disk-touching entry point is guarded: frame rows, `log`/`writeLogLine`, the raw-tap WAV (`createFile` does not create intermediate directories), the stem dump (`withIntermediateDirectories` would otherwise conjure the directory with no headers), and the video writer. `finish()` early-outs when nothing was ever written, so it cannot materialize the empty folder the fix exists to prevent. The banner uses `writeLogLine` rather than `log` so it stays the first line of `session.log` instead of being enqueued behind the row that triggered materialization. Regression tests in `SessionRecorderTests`: `test_construction_writesNothingToDisk`, `test_finishWithoutWriting_leavesNoDirectory`, `test_firstLogWrite_materializesDirectoryWithHeadersAndBanner`. Two pre-existing tests asserted the old init-time contract and were updated, not weakened — `test_init_createsSessionDirectoryWithCSVsAndLog` became `test_firstWrite_createsSessionDirectoryWithCSVsAndLog`, keeping every assertion and moving them one write later. **Verified end-to-end:** the full app test suite now leaves the session directory listing byte-identical, where before it added a folder and evicted one.

**Expected.** A folder appears under `~/Documents/phosphene_sessions/` when a session is *recorded*. Running the test suite writes nothing to the user's Documents directory.

**Actual.** `VisualizerEngine.swift:942` constructs `SessionRecorder()` unconditionally, and `SessionRecorder.init` creates the directory, writes both CSV headers and the three-line startup banner immediately. Any `VisualizerEngine` construction therefore leaves a folder behind whether or not a session ever starts — including every `xcodebuild -scheme PhospheneApp test` run, and every app launch the user closes without recording.

**Reproduction (performed).** Count folders, run `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test`, count again: `2026-08-03T21-07-43Z` appears with a header-only `features.csv` (1 line, 0 data rows) and a `session.log` containing only the banner — no `WIRING:`, no `preset →`, no `SIGNAL_HEALTH`. Four of the six empty folders present on 2026-08-03 match `xcodebuild` app-test completion times to within 3 s (19-49-56Z, 20-01-18Z, 20-12-53Z, 21-00-25Z).

**Impact.** Two, and the second is the damaging one:
1. Test-isolation violation — the test suite writes into the user's `~/Documents/`.
2. The junk folders **consume retention slots**, so running the test suite (or launching the app a few times without recording) silently evicts real captures. With BUG-080 also in play the usable window is 6, so ~6 test runs are enough to destroy every real session on disk. This is what made a real capture disappear mid-analysis on 2026-08-03.

**Diagnostic confusion it caused.** These folders are indistinguishable at a glance from a session where audio capture failed, and were initially misread as six failed M7 attempts (a silent-tap symptom, BUG-055/BUG-057 class). They are not — they are empty by construction.

**Failure class.** `resource-management` (eager side-effecting allocation in an initializer) with a `test-isolation` consequence.

**Fix (not implemented).** Create the directory lazily on the first row write, or behind an explicit `startRecording()` that the session lifecycle calls — so an engine that never records leaves nothing behind. Either way the recorder stops side-effecting from `init`.

**Verification criteria (written before the fix).** (1) Automated: constructing a `SessionRecorder` (or a `VisualizerEngine`) and never writing a row creates no directory; writing one row creates it with headers intact. (2) Manual: note the folder count, run the full app test suite, confirm the count is unchanged.

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

**Follow-up CLOSED 2026-08-04 (RECON.13) — the shared manifest, and a correction to this entry's own claims.**

`Scripts/fixtures.manifest` is now the single source of truth for which gitignored files a default `swift test` requires, read by three consumers that previously disagreed: `link_fixtures.sh --verify`, `bootstrap_fixtures.sh`'s no-op guard, and the Swift gate (renamed `FixtureManifestPresenceGate`, was `BeatThisFixturePresenceGate`, which had hardcoded one filename). **The bug the duplication was actually hiding was a granularity mismatch, not just drift:** the shell side asked "is the directory non-empty" while the Swift side asked "does this specific file exist". A tempo tree holding **1 of 3** clips satisfied both shell checks and still failed the tests they exist to protect. Verified by removing one clip: `--verify` and `bootstrap_fixtures.sh` both previously reported success, and now both fail naming the exact missing path. Adding a fixture is a one-line manifest edit rather than a two-file edit someone can half-finish.

**Correction — the "3 of ≥8 fixtures" claim in this entry and in RUNBOOK §Worktree setup was WRONG.** The 2026-08-03 audit reported that `fetch_tempo_fixtures.sh` retrieved 3 tracks against a suite needing "at least eight", naming `pyramid_song`, `yyz`, `clair_de_lune`, `money`, `if_i_were_with_her_now`. Measured directly at RECON.13: the default-required set **is** those three (`love_rehab`, `so_what`, `there_there`), and the fetch script covers all of them. The claim conflated **three separate fixture systems** — (1) tempo clips, gitignored, required, gated here; (2) **BeatBench**'s 17 tracks, which live *outside the repo* at `BEATBENCH_FIXTURES_DIR` under their own sha256 gate and are env-gated; (3) **diagnostic-harness audio** like `pyramid_song.m4a`, whose only consumer is `RicercarFluidVideoHarness`, a suite with "env-gated" in its own name. `BeatGridResolverTests` never referenced `pyramid_song` at all. *Root cause of the bad claim: a name-frequency grep across the test tree, with the hits attributed to the wrong system and never opened. Same failure shape as the RECON.1 fixture deletion — a count treated as evidence.* The RUNBOOK now carries the three-system table instead.

**Still open, tracked separately.** The **third instance** — `docs/VISUAL_REFERENCES` and `docs/diagnostics` empty in the primary — is not fixed by `2b36c34d`; the script now only warns about it. It is **not a regression to be undone**: the images were untracked on purpose at LFS.2 to stop the LFS bill and must stay out of history. What is owed is a decision about the *on-disk* half — re-curate locally (billing-neutral, `.gitignore:101-108` still excludes them) or retire the image-linking half and make the READMEs the authority. See the corrected THIRD INSTANCE note above.


**THIRD INSTANCE, found by the fix's own `--verify` (2026-08-03) — and it is a different kind of finding from Gaps A and B.** `docs/VISUAL_REFERENCES` and `docs/diagnostics` report **0 gitignored files in the primary**.

**CORRECTED 2026-08-03 (Matt).** The first draft of this note read as though the images had gone missing. They did not. **They were deliberately untracked at LFS.2 / PUB.2 to stop the Git-LFS bill** — the "stop the bleeding" change recorded in `PUBLISHING.md` §1 and `RUNBOOK.md` — and the LFS.3 history rewrite then removed them from reachable history. Verified here: **zero image blobs across all 2,348 reachable commits**, and `git lfs` is no longer installed on this machine. So their absence *from git* is correct, intended, and must stay that way.

**What is actually defective is the half of the system nobody updated to match.** D-211 extended `link_fixtures.sh` to propagate these images precisely *because* they are gitignored — the design is: images live on disk, never in history, and travel worktree-to-worktree by symlink. LFS.2 removed them from git and nothing re-established the on-disk copies or reassigned that job to a human. `.gitignore:101-108` still excludes every `.jpg/.jpeg/.png/.gif` under both trees, so **local on-disk copies are billing-neutral** — the machinery is correct and costs nothing; the larder is simply empty. The consequence D-211 named, *"silently degrades preset work rather than failing,"* has therefore been the standing condition everywhere rather than a worktree-only risk, and `docs/VISUAL_REFERENCES/<preset>/` holds READMEs describing images nobody can see.

**Restore path.** Not recoverable from the repo — re-curation from the sources each README cites is the only route back. Left `required=no` because promoting it would fail every run today, but it now warns loudly on every invocation.

**Open decision (narrower than first stated).** Either keep the `required=no` warning and re-curate locally when a preset session needs images, or drop both trees from the manifest entirely and rewrite the preset-session checklist's "look at the images" step to point at the READMEs as the authority. Not urgent, and **not** a reason to put images back under version control. Bears on FTR.2's reference curation, which per D-212 wants a low-fidelity set rather than the painterly one that left with Goldengrove.


**Related.** D-211 (the images half of this same gap, and the worktree-propagation reasoning), PUB.2 (weights → Release asset), QR.3 (`BeatThisFixturePresenceGate` — the gate that caught Gap B), D-212 process note (one worktree per session), BUG-078 (the concurrency intermittent the cascade failures may mask), BUG-079 (the other build-level gate that cannot currently run).

---

