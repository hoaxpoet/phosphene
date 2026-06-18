# Phosphene — Developer Release Notes

Internal release notes for the `main` branch. Audience: Matt and Claude Code. Each entry covers one session or a logical batch of increments. These notes complement `docs/ENGINEERING_PLAN.md` (authoritative for what's planned) and `docs/QUALITY/KNOWN_ISSUES.md` (authoritative for open defects).

User-visible release notes are not yet in scope (no public build).

Older entries: `RELEASE_NOTES_DEV_YYYY-MM.md` (one file per month).

**Entry ids are `[dev-YYYY-MM-DD-HHMMSS]`** (UTC time-of-day the entry is written — e.g. `date -u +%Y-%m-%d-%H%M%S`). They are unique by construction, so **never hand-assign sequential `-a`/`-b`/`-c` letters** — parallel sessions independently picking the next letter was a recurring merge-renumbering tax (DOC.8). Older `-a/-b/-c` entries are grandfathered; `rotate_docs.sh` / `DocIntegrityTests` key only on the `YYYY-MM-DD` date, so the suffix format is free. This file is also **`merge=union`** (`.gitattributes`): concurrent appends from two sessions auto-combine instead of conflicting — so keep it **prepend-only prose**, never edit an existing entry in place (union would duplicate it).

---

## [dev-2026-06-18-184228] CLEAN.4.7 — peak-RSS leak regression gate (memory soak)

[GAP-16 / G16] `MemoryReporter` (phys_footprint) and the `SoakTestHarness` already *observed* memory growth, but explicitly asserted nothing ("observability only, not a hard gate"). This adds the missing regression gate.

`MemorySoakGateTests` (Diagnostics target) drives the per-frame steady-state paths for a fixed frame count and fails if `phys_footprint` grows past a 25 MB budget after a warmup window:
- FFT→MIR path — 500 warmup + 2.5K soak frames.
- StemAnalyzer path — 200 warmup + 1.2K soak frames (heavier per frame — 4 FFTs + YIN pitch tracking — so a smaller soak).

Both pass green: growth is well under budget, i.e. no leak. A real per-frame leak (whole objects accumulating — KBs/frame) shows as tens of MB over the soak, while allocator noise is a few MB, so the 25 MB budget catches leaks without flaking.

`phys_footprint` is **process-wide**, so the gate is only meaningful run **isolated**: `SOAK_TESTS=1 swift test --filter MemorySoakGate` (~7.7 s, `.serialized`). Under the normal parallel `swift test` / closeout it **early-returns** (skips) — a full-suite run swamps the measurement with other suites' GPU/stem allocations (an initial always-run version recorded a spurious +625 MB). This is the same reason the existing `SoakTestHarness` 5-minute check is `SOAK_TESTS`-gated and "observability only".

Division of labour: the automated gate catches *gross* leaks (the common regression). Slow sub-KB/frame creep and the absolute steady-state + 2-hour growth curve stay the manual `SoakRunner` diagnostic (`Scripts/run_soak_test.sh`) — a device-time measurement that can't run in CI. swiftlint 0.

## [dev-2026-06-18-181837] CLEAN.4.6 — thermal + Low Power Mode adaptation in the frame-budget governor

[GAP-4 / G4 / D-167] The frame-budget governor now responds to thermal pressure and Low Power Mode, closing G4 (previously zero `thermalState`/`lowPowerMode` references). Visual load drops one floor *ahead* of the GPU's own thermal throttle instead of waiting for frames to start dropping, and the user's Low Power Mode choice is respected.

Mechanism — `FrameBudgetManager` gains a `thermalFloor: QualityLevel`; the applied level is `max(currentLevel, thermalFloor)`, independent of the timing hysteresis:
- A rising thermal state pre-empts the downshift (no waiting for the 3 timing-overrun detection).
- Clearing it restores quality immediately — the timing `currentLevel` was never raised, so there's no 180-frame recovery wait.
- The governor stays `ProcessInfo`-free and pure: `VisualizerEngine` observes `thermalStateDidChangeNotification` + `NSProcessInfoPowerStateDidChange`, maps via the pure static `FrameBudgetManager.qualityFloor(thermalState:lowPowerMode:)`, and seeds the floor at FBM creation (in case the app launches already hot / in LPM). The floor takes effect on the next frame.

Mapping (D-167, tunable): thermal serious → no-bloom, critical → step-0.75; Low Power Mode → at least no-SSGI (and never weaker than a stronger thermal floor). The `QualityCeiling.ultra` recording exemption still bypasses the floor.

Verification: 5 new `FrameBudgetManagerTests` — the floor clamps the applied level without altering the timing state; timing can still downshift below the floor; the floor survives `reset()` (thermal is preset-independent); the mapping is correct for each thermal state × LPM combination. Engine + app builds clean, swiftlint 0. Remaining manual gate: actual thermal-induced pre-emption needs device validation under load — the Mac mini's active cooling rarely throttles, so this matters mainly for fanless deployment.

## [dev-2026-06-18-175030] CLEAN.4.5 — NaN/Inf robustness sweep on the audio→GPU path

[GAP-3 / G3] Hardens the two GPU-bound audio structs — FeatureVector (fragment buffer 0) and StemFeatures (buffer 3) — against non-finite values. Both are all-Float, so the tests scan every field via `withUnsafeBytes`.

The sweep split into a latent half and a live half:
- **Latent (the literal done-when):** silence, DC, and cold-start frames already produce no NaN. The spectral features short-circuit at zero sums, and `StemAnalyzer` seeds its fast/slow RMS EMAs at `1e-8` rather than 0, so the 0/0 cases never arise. Confirmed by the new tests — no code change needed there.
- **Live (the real gap):** a NaN or ±Inf in the *input samples* — a corrupted tap at the audio hardware/driver trust boundary — propagated straight through the FFT into both structs every frame (energy bands, centroid, deviation primitives, attack ratios). The epsilon floors can't catch this (`NaN / 1e-8 = NaN`). A full-frame GPU NaN reads as a black/garbage frame, so the blast radius is high even though the trigger is rare.

Fix — sanitize at the FFT entry points (`isFinite ? value : 0`), where audio first enters the GPU-bound pipeline:
- `FFTProcessor.process(samples:)` and `processStereo(interleaved:)` — folded into the existing copy/mix loops (zero extra alloc, preserving the CLEAN.4.1 allocation-free path).
- `StemAnalyzer.computeMagnitudes` — an in-place scrub of the copied window region (it uses a bulk pointer copy).

Output-preserving for finite audio (the guards are pass-through): PresetRegression goldens byte-identical (20 presets × 3 fixtures), no M7. Verification: two new integration tests run real degenerate *audio samples* (silence / DC / cold-start / NaN-input; silent / DC / NaN stems) through the actual FFT→MIR and StemAnalyzer paths (FA #27 — not hand-authored feature vectors) and assert every FeatureVector / StemFeatures field stays finite on every frame; both fail pre-fix on the NaN-input case. swiftlint 0.

Out of scope: `GridOnsetCalibrator.computeMagnitudes` is a third FFT entry, but it runs at preparation time on clean preview audio and produces a one-time CPU calibration offset (not a per-frame GPU uniform) — a follow-up if its path ever needs hardening.

## [dev-2026-06-18-164609] CLEAN.4.3 — renderer texture-lifecycle correctness (aliasing / resize / NaN)

Three latent renderer-correctness fixes from the Phase-4 backlog (audit T7). All output-preserving — the PresetRegression goldens are byte-identical, so despite the `[M7]` tag this needed no golden regen and no visual review (same outcome as CLEAN.4.4's "latent, not live").

- **sceneTexture aliasing + leak (`PostProcessChain`)** — `runBloomAndComposite` fed the ray-march lit texture into the bloom/composite passes by assigning `self.sceneTexture = externalSceneTexture`, but never restored it. A later standalone `.postProcess` preset's `runScenePass` then rendered into the ray-march texture (wrong target), and the chain retained that full-res rgba16f texture after detach. Now the member is saved and `defer`-restored: the passes still read the external texture during the call (identical output), but `sceneTexture` returns to the chain's own texture afterward.
- **resize stale-size (`RenderPipeline.mtkView(drawableSizeWillChange:)`)** — a feedback-texture allocation failure `return`ed out of the whole handler, leaving the post-process, ray-march, and mv_warp textures stranded at the previous size. Now it drops the feedback pair (feedback rendering already guards on empty) and falls through so the other subsystems still resize.
- **ray-march /height NaN (`RenderPipeline+RayMarch`)** — the aspect-ratio uniform guarded `width > 0` but divided by `height`, producing +inf/NaN on a zero-height drawable. Guard the divisor (`height > 0`) instead; identical for any height > 0.

Verification: PresetRegressionTests byte-identical across 20 presets × 3 fixtures (the output-preserving gate); a new `test_runBloomAndComposite_restoresOwnSceneTexture` asserts the member is restored to the chain's own texture, not the external one (PostProcessChainTests 7/7 — it fails pre-fix); DrawableResizeRegression 6/6, RayMarchPipeline + PostProcessBloomGate green. Build clean, swiftlint 0 (PostProcessChain now sits at the 400-line `file_length` ceiling — next addition needs a trim or split). Out of scope: the DynamicTextOverlay in-flight-frame race (unfiled, not confirmed).

## [dev-2026-06-18-161943] CLEAN.4.2 — remove redundant DSP compute (autocorrelation / drums FFT / mono STFT)

Three output-preserving single-compute dedups from the Phase-4 backlog (audit T6 / `CODE_AUDIT_2026-06-09` §Performance):

- **Autocorrelation (`BeatDetector+Tempo`)** — `estimateTempo` swept the lag range twice: `findBestLag` for the peak and `computeAutocorrelationConfidence` for the mean, recomputing identical `vDSP_dotpr` correlations. Merged into one `autocorrelationSweep` (best-lag + mean in a single pass); offset pointers (`base + lag`) replace the ~85 per-lag `Array(linear[...])` slice copies, dropping the per-call heap allocation to zero. Confidence formula unchanged.
- **Drums FFT (`StemAnalyzer`)** — `analyze` discarded `analyzeStem`'s drums magnitudes (`_`) then recomputed the identical `computeMagnitudes(from:)`; now reuses the returned mags. One fewer FFT per analysis frame.
- **Mono STFT (`StemSeparator`)** — for mono input `deinterleave` returns `(audio, audio)`, so `left == right` and the 4096-pt STFT ran twice on identical data. Now reuses the left STFT for the right when `channelCount < 2`. One fewer 431-frame STFT per mono preview separation; stereo unchanged.

Output equivalence is the gate. The merged tempo sweep is numerically identical (same `dotpr` values, same peak, same mean) — 9 `BeatDetector` tempo/onset tests green; the drums/mono mags feed unchanged `StemAnalyzer` assertions; and a new `test_separate_monoReusesStereoStft_outputUnchanged` separates the same signal as mono (ch 1) and stereo-duplicated (ch 2) and asserts every stem sample matches (< 1e-5), with the stereo path as unchanged reference code. Build clean; swiftlint 0 (the 3-tuple return became a small `AutocorrelationSweepResult` struct to satisfy `large_tuple`). Not in scope: NoveltyDetector full-recompute and the SessionPreparer serial-prep prefetch (separate audit items).

## [dev-2026-06-18-143356] BUG-037 RESOLVED — Arachne pop fixed (Matt live-validated)

Matt re-validated the planner-span fix (session `2026-06-18T14-30-52Z`): **the full web draws continuously to the core, then transitions on the completion event — no pop.** Arachne ran ~43 s (14:31:25 → 14:32:08) and ended on the build's `presetCompletionEvent`, not a section boundary (the live electronic beat density laid the ~441-chord spiral faster than the 118 BPM grid estimate). BUG-037 → **Resolved** — both halves were needed: the chord-count single source of truth (so the reveal *can* reach 1.0) **and** `wait_for_completion_event` spanning sections (so the build is *allowed* to finish before a transition). KNOWN_ISSUES BUG-037 Resolved (commits `d430d64` + `e6a530d`); EP CLEAN.3.4 ✅; CODE_AUDIT Part C ✅.

**Process lesson recorded:** the audit's static-analysis framing (three inconsistent constants) was necessary but not sufficient — the dominant cause was a *runtime pacing* interaction (build duration vs section scheduling) invisible to static review and only surfaced by a live M7. A visual/temporal fix isn't done until it's validated live; the green automated tests on the first attempt were real but measured the wrong thing. Docs-only entry.

## [dev-2026-06-18-035306] CLEAN.3.4 M7-followup — wait_for_completion spans sections (the real Arachne pop fix)

Matt's M7 of the chord-count fix **failed** (session `2026-06-18T01-21-18Z`): the spiral pop persisted. The chord-count normalization was verified *correct* (new test `spiralRevealClimbsPastOldCeiling` drives the build and reads the actual `webs[0].spiralPacked` climbing past 0.6 — the stuck-at-0.45 ceiling is gone in code), so the audit's three-constant framing was incomplete.

**The dominant root cause:** Arachne's build (~92 s — frame + radial + the full ~441-chord spiral at 3.24 chords/beat) **outlives its planned segment.** `wait_for_completion_event: true` only sets `maxDuration = .infinity` (`PresetMaxDuration:101`), which fills the current SECTION — but `planOneSegment` still bounds the segment at `remainingInSection` and terminates `.sectionBoundary` (`SessionPlanner+Segments:177-192`). Love Rehab's section ≈ 38 s, so the plan-driven boundary cut the build mid-reveal → forced `.stable` snap = the pop. And the cap-raise (the "restore intended density" pick) *worsened* it: the build went 54 s → 92 s, so the cut lands at a lower reveal %. I own the mis-diagnosis — I shipped a fix that couldn't help and made the symptom worse.

**Fix (Matt's pick: make `wait_for_completion_event` truly span sections).** `planOneSegment` now gives a completion-gated preset a segment spanning its `naturalCycleSeconds` (capped at `trackEnd`) instead of the section boundary; `planSegments` tracks `coveredUntil` so a later section the spanning segment already covers doesn't re-emit. The non-wait path is byte-equivalent (existing segment behaviour unchanged). So the plan boundary now lands *past* the build's completion: the build finishes (reveal → 1.0), the live `presetCompletionEvent` drives the transition, no pop. The normalization + cap-raise stay — they're correct once the build is allowed to complete.

Gate: `SessionPlannerTests.waitForCompletion_segmentSpansSections` (a 90 s-cycle preset gets one ~90 s segment in a 300 s track; plan stays contiguous). 25 SessionPlanner + 99 orchestrator/integration/lifecycle tests green; swiftlint `--strict` 0. **Pending Matt's live re-validation that the pop is gone.** Known follow-up (not a pop): the completion event advances via `presetLoader.nextPreset()` (loader cycle), so the preset *after* a completed wait-preset is off-plan — minor variety deviation, flag if it matters. `KNOWN_ISSUES.md` BUG-037 (M7-failed → planner fix).
## [dev-2026-06-18-135357] BUG-059 (step 4 — validated, RESOLVED) — Matt's live device-swap test: no hang

Matt's manual validation on the integrated `main` build (session `2026-06-18T13-46-10Z`, macOS 26.5, M2 Pro): several Duet 3 ↔ Mac-mini-Speakers output-device swaps mid local-file playback, plus Next/Prev. **No hang.** `session.log` shows every device-swap `provider.teardown` ran ENTER → `player.stop BEGIN/COMPLETE` → `removeTap` → `engine.stop BEGIN/COMPLETE` → EXIT (the BUG-059 deadlock signature — a `player.stop` that never completes — is absent across all ~6 teardowns); `advanceLocalFileQueue` (Next) reached `EXIT ok=true`; `features.csv` is live throughout (6666 frames @ 60 fps, 200/200 distinct values in the last 200 rows — no BUG-058-style freeze); `raw_tap.wav` continuous (39 MB). **BUG-059 RESOLVED** (`a285a22`, integrated to `main` / origin/main).

Scope note: the swaps were sequential (seconds apart), so the session itself did not reproduce the exact *concurrent* race (config-change overlapping a track advance) — the automated `concurrentDoubleStart_serializesWithoutDeadlock` (reliably wedged pre-fix, 11/11 green post-fix) remains the proof for the race; the live session confirms the device-swap path is healthy and un-regressed.

**Separately:** Matt observed the track **restarts from the top** on a device swap. That is the pre-existing, expected **BUG-056** (`handleConfigurationChange` tears down and restarts the engine from position 0 — no resume-from-position, explicitly out of scope for the LF.1 spike), **not** a BUG-059 regression. Filed P3; surfaced to Matt for a prioritization call (a resume-from-position fix is its own increment: capture the play-head frame before teardown, `scheduleSegment` from it after restart).

## [dev-2026-06-18-033402] BUG-059 (step 2 — fix) — re-schedule off the AVAudioPlayerNode completion-handler queue

The fix for the concurrent-start/stop deadlock diagnosed below. `LocalFilePlaybackProvider.scheduleFileLoop`'s completion handler re-scheduled the loop (`scheduleFile()`) — and fired `onFileEnded` — **inline on the AVAudioPlayerNode completion-handler queue**. That re-enters the engine lock while owning the completion queue, so a concurrent `stop()` (whose `player.stop()` holds the engine lock and `dispatch_sync`s that queue) deadlocks against it.

**Change (engine-only, ~1 file):** the completion handler now hops its work onto a new provider-owned serial `rescheduleQueue` and re-checks the `(playerNode, audioFile)` identity under `lock` there before touching the player. The completion handler returns immediately, freeing the completion queue — `stop()`'s `dispatch_sync` can win, and the two sides serialize on the engine lock (mutual exclusion) instead of forming a cycle. `onFileEnded`'s production consumer already hops to the MainActor (`VisualizerEngine+LocalFilePlayback.swift:161`), so its callback-thread change is immaterial; LF.1 single-file looping restarts at a file boundary where a sub-millisecond hop is inaudible.

**Validation.** On the same dev Mac mini that wedged on round 0 pre-fix (a 6m15s hang with the watchdog removed), `concurrentDoubleStart_serializesWithoutDeadlock` is now **11/11 green** (6× isolated + 5× in-suite, ~3.5 s each); the full `SessionLifecycleChurnTests` suite (all 6 tests) is **5/5 green** (~17 s). No production caller relies on the old completion-thread. **Pending Matt's manual validation** (local-file loop has no new gap/glitch; multi-file Next still advances; an output-device swap mid local-file playback no longer hangs — intersects G1 / BUG-056); the worktree change must reach the `main` build first. `KNOWN_ISSUES.md` BUG-059 §Fix; `ENGINEERING_PLAN.md` BUG-059 step 2 ✅. The de-flake task that surfaced this is therefore resolved by **fixing the real deadlock**, not by reworking the test's wall-clock assertion — the watchdog stays (correct, load-bearing hang-detection); the flake was the deadlock.

## [dev-2026-06-18-032705] BUG-059 (step 1 — diagnose) — concurrent local-file start/stop ABBA deadlock; the "session-churn flake" is a real hang

A request to de-flake `SessionLifecycleChurnTests.concurrentDoubleStart_serializesWithoutDeadlock` (REVIEW.2) — reported as a load-induced wall-clock flake — turned out to be a **real, intermittent, production-reachable deadlock**. I started the prescribed fix (remove the watchdog, assert the serialization invariant, mirroring CLEAN.7.12), but the watchdog-free version **hung 6m15s in isolation** instead of the expected ~3.6s, which falsified the "benign flake" premise.

**Diagnosis (no fix code this step, per the P0/P1 protocol).** A process `sample` of the hung test shows a circular wait on AVFoundation's **internal** locks — the provider's own `NSLock` is not involved (so the 2026-05-28 BUG-021 fix, which moved teardown outside that lock, does not cover this):
- the final `provider.stop()` → `[AVAudioPlayerNode stop]` → `StopImpl` holds the engine lock and is blocked in `dispatch_sync` waiting to own the AVAudioPlayerNode **CompletionHandlerQueue**; while
- that queue is running our **`scheduleFileLoop` completion closure ([LocalFilePlaybackProvider.swift:355](../PhospheneEngine/Sources/Audio/LocalFilePlaybackProvider.swift)) which calls `scheduleFile()` inline** and is blocked acquiring the **engine attach/recursive_mutex**.

Root cause in our code: re-scheduling the loop (`scheduleFile`) **synchronously from inside the completion handler**, which deadlocks against a concurrent `stop()`. The single-threaded path is fine (`routerChurn_…` passes, 4.36s); only the concurrent path wedges. It's a race → intermittent (passes in isolation some days, the "~9.5s under load" the report saw was this same deadlock caught by the 8s watchdog). **Production trigger:** `handleConfigurationChange` ([:414](../PhospheneEngine/Sources/Audio/LocalFilePlaybackProvider.swift)) runs `stop()+start()` off the MainActor on an output-device / sample-rate change, racing a track-advance `stop()+start()` — i.e. the **G1 device-swap** scenario (intersects BUG-056 / BUG-058).

**Action.** Reverted the watchdog-removal (it converts a fast 8s labeled failure into a 6-minute silent hang — strictly worse; the watchdog is load-bearing hang-detection for this suite). Filed **BUG-059** (P1, concurrency) in `KNOWN_ISSUES.md` with the stack + verification criteria written before the fix. Matt chose **fix it properly (P1)** over file-and-defer. Step 2 (fix): hop the re-schedule + `onFileEnded` advance off the completion-handler queue onto a provider serial queue. `ENGINEERING_PLAN.md` BUG-059 ⏳.

## [dev-2026-06-17-223835] CLEAN.3.4 — BUG-037 Arachne chord-count single source of truth (code-complete; M7 pending)

Phase-3 `[M7]` stretch item. The Arachne spiral reveal popped at ~45 %: three uncoordinated constants for one contract — CPU `spiralChordsTotal = min(200, radialCount × spiralRevolutions)`, shader `spiral_packed / 441.0`, test `104`. Post-BUG-011 the product is 324–576, so the 200 cap always fired; the CPU laid ≤ 200 chords while the shader normalized by 441, so the reveal gate maxed at 200/441 ≈ 0.45 and `.stable` popped the remaining ~55 % in one frame (halving the build cycle, firing the completion event early).

Matt's pick (`AskUserQuestion`): **restore the intended density/build**, not propagate the truncated cap. Fix — the CPU is the single source of truth:
- `recomputeSpiralChordTable` cap raised `200 → maxSpiralChords = 600` (a degenerate-case guard above the legitimate 576 max — it never truncates a normal build; the old 200 sat *below* the range).
- `spiralPacked` is now published **already-normalized** (`min(1, (index + progress) / spiralChordsTotal)`), so the shader reveals by it directly — `saturate(spiral_packed)`, with the hardcoded `kSpiralChordsTotalCPUDefault = 441` deleted. The shader holds no chord count; the CPU owns it.
- The test fixture's `104` → `1.0` (the normalized reveal fraction; `.stable` ⇒ the shader uses 1.0 regardless).
- **No struct/GPU-contract change** — pre-normalizing reuses the existing `spiral_packed` float (the shader never decoded a chord index from it), so the WebGPU stride stays 96 bytes and the test's raw Row-5 byte-seeding is unchanged. The radial stage's accepted ±drift (`/21.0`, D-095) is intentionally left alone — out of BUG-037's scope.

**Build-phase-temporal change.** The chord count governs the reveal *animation* (how smoothly/over-what-duration the spiral lays in), **not** the final spider's density (`spiralRevolutions` sets that, drawn procedurally). So the `.stable` golden is **unchanged** — `PresetRegressionTests` stays green, no golden regen. The visible change is the build: a smooth reveal to the core over the documented ~73 s cycle instead of the 45 %-then-pop.

Automated lock: `ArachneStateBuildTests.spiralChordCountHonoursProduct` — `spiralChordsTotal == radialCount × spiralRevolutions` (> 200) across seeds, the chord-radii table holds the full count, the guard still bounds it (BUG-037's "uncapped product is honoured" criterion). All 44 Arachne / acceptance / regression tests green; swiftlint `--strict` 0.

**M7 pending (Matt).** The manual/visual criterion — the build reveals continuously to the core with no pop — is **not** verifiable from the existing RENDER_VISUAL harness (it warms only ~0.5 s, an early-build frame; it never reaches the spiral phase). Honest status: **cannot verify the reveal here; pending your M7** (live, or a build-sequence render I can add if you want a static artifact first). `KNOWN_ISSUES.md` BUG-037 (automated ✓, manual M7 ☐). EP §Recently Completed ⏳.

## [dev-2026-06-17-220337] CLEAN.3.8 — disk-full / write-failure graceful degradation (GAP-6)

Sixth Phase-3 increment, and the last of the non-M7 Phase-3 work. GAP-6 (audit-verified: no `volumeAvailableCapacity`/ENOSPC handling). The real risk was `SessionRecorder`: per-frame CSV + log used the **non-throwing `FileHandle.write(_:)`**, which raises an *uncatchable* Objective-C exception on a full disk → the app **crashes** mid-session (and can leave a half-written final row).

Fix (engine-only, in a new `SessionRecorder+DiskGuard` extension):
- **Honest stop.** Every per-frame/log write now goes through `safeWrite(_:to:)` — the *throwing* `write(contentsOf:)` in a do/catch. On failure (disk full), `haltRecording(reason:)` sets `recordingHalted`, logs **once** to the unified log (`os.Logger`, since `session.log` itself may be unwritable), and from then on every write and `recordFrame` early-outs. Result: the recorder stops cleanly with its partial artifacts retained — no crash, no silent corruption, no partial rows.
- **Pre-flight capacity check.** `warnIfLowDiskSpace(at:)` at session start logs a loud warning when `volumeAvailableCapacityForImportantUsage` is below `minFreeBytesForRecording` (200 MB). Recording still proceeds (a short session may fit); the honest-stop covers actual exhaustion. Unknown capacity (query failure) is permissive — never refuse recording because the volume couldn't be read.
- **Caches were already safe** — `PersistentStemCache.store` uses atomic `write(to:options:.atomic)` (no partial-file corruption) and throws, caught at its call site (`VisualizerEngine+LocalFilePlayback`). Verified, untouched.

The disk-guard logic lives in the extension to keep `SessionRecorder` under `type_body_length`. Gates: `test_diskGuard_capacityPredicate` (pure — enough/low/unknown) + `test_diskGuard_haltStopsFurtherWrites` (after `haltRecording`, `recordFrame` writes no further rows and doesn't crash; idempotent). SessionRecorder suite 26/26; engine build green, swiftlint `--strict` 0. The ENOSPC path itself isn't unit-triggerable (can't fill a disk in a test) — verified by routing + the halt-gate test; the predicate + gate are the locked behaviour. Not visually verifiable. `KNOWN_ISSUES.md` untouched (audit GAP, no filed bug). EP §Recently Completed ✅.
## [dev-2026-06-18-142220] BUG-050 VALIDATED + reframed (Resolved); BUG-060 filed (one-off Gossamer hang)

Matt validated the video gate across two real sessions (`2026-06-17T22-10-50Z`, `2026-06-18T13-57-23Z`). **The gate works** — `video 0 appended`, and `frame_cpu_ms` dropped **15.78 → ~8.1 ms** (the render loop genuinely halved). **But the original "Activity Monitor steady-state CPU halves" criterion was a misdiagnosis, now retired:** Activity Monitor stayed 89–115% because the dominant cost is the **continuous real-time stem separation** (the Demucs-style MPSGraph re-running every ~5 s — 28–29× per ~3 min session) + preset-dependent render, **not** the video. The 2026-06-14 entry had mis-read `encode_cpu_ms` (the Metal command-encode metric, ~6 ms, unchanged with video off) as the video-capture cost. The gate is a real, free frame-loop reduction and is **kept**; the leftover ~2-core cost is the live-stems feature working as designed (acceptable on the plugged-in Mac mini at 60 fps; revisit only for laptops/battery — Matt's call). **BUG-050 → Resolved (reframed).** Docs-only entry (validation + tracker reframe; the fix itself shipped `702697d`).

**Filed BUG-060 (P3, monitored):** in `22-10-50Z` the app hung (force-quit required) — the render loop was healthy at 60 fps right up to its last frame (`22:14:01Z`), **one second after `preset → Gossamer`** (`22:14:00Z`), while stem/orchestrator threads kept logging → a render-path hang, not an analysis stall (BUG-043) or tap freeze (BUG-058). **Not reproduced** — Gossamer ran 3× clean in `13-57-23Z` with a normal shutdown. No stack was captured (force-quit without Pause), so it can't be diagnosed yet. Filed monitored, like BUG-058, with the breadcrumb: on the next recurrence, **hit Pause in Xcode before force-quitting** to capture the thread stacks. `KNOWN_ISSUES.md` BUG-050 + BUG-060.

## [dev-2026-06-17-214707] CLEAN.3.6 — SessionRecorder running-vs-actually-writing invariant (BUG-039)

Fifth Phase-3 increment. BUG-039 (session video silently stops appending while the recorder keeps "running") had its **recovery** landed 2026-06-10 — on writer death the partial is retained and recording rolls to `video_N.mp4`, bounded at 8 restarts. What was missing (the audit's "invariant missing") is anything tying *"recorder running"* to *"video actually advancing"*: after the restart budget exhausts, or on any silent stall the death-check doesn't catch, the recorder keeps writing CSV/log while video is dead — and the only signal was a mid-session log line.

Added the invariant. A successful-append counter `videoFramesAppended` + `lastVideoAppendFrameIndex` are the "actually-writing" signal (incremented on each `adaptor.append` success). At `finish()`, `finalizeVideoInvariant()`:
- appends a **video-outcome summary** to the session-end log line — `video N appended / S segment(s) / R restart(s) / disabled=bool` — so a recorder that ran while writing no video can never look healthy from the artifacts; and
- logs a loud **`BUG-039 invariant VIOLATED`** line when the silent-stop *signature* is present: the writer locked, then appends stopped more than `videoSilentStopFrameThreshold` (300 frames ≈ 5 s; the field signature was tens of thousands) before session end, with no writer death/restart and video not disabled. Every *explained* stop (restart, budget-exhausted disable, never-locked) is excluded, so it only fires on the genuinely-silent case.

The predicate `isSilentVideoStop` is pure (unit-tested GPU-free via `test_bug039Invariant_silentStopPredicate` — signature true, every excluded case false); the existing `test_videoWriterDeath_rollsToNewSegment_bothFilesReadable` was extended to **confirm recovery** — `videoFramesAppended > 0` after the roll (appends resumed) and no false violation. The invariant logic lives in the `SessionRecorder+Video` extension to keep the class under `type_body_length`. Engine build green, swiftlint `--strict` 0; SessionRecorder suite green. Not visually verifiable. `KNOWN_ISSUES.md` BUG-039 updated — **closure still pends Matt's live multi-session confirmation** that the affected-session signature no longer occurs (the recovery + invariant are the durable mitigation for an undocumented intermittent AVFoundation encoder failure). EP §Recently Completed ✅.
## [dev-2026-06-17-215658] BUG-050 — gate the always-on recorder's video OFF by default (~2× CPU tax removed)

The diagnostic `SessionRecorder` ran unconditionally and its per-frame video capture (drawable blit → `tex.getBytes` → AVAssetWriter, ~7 ms/frame additive to render) ≈ doubled the app's CPU — ~2 cores of sustained power/heat on every session — for a recording the end user never asked for. No fps cost (encode is off-thread), and ~all the diagnostic value we actually use (BUG-043's `deltaTime` scan, beat-sync columns, stem deviations) lives in the near-free CSV/log/stem artifacts. **Fix (Matt reversed the earlier "option A" defer):** a `videoEnabled` gate, **OFF by default** — `ensureCaptureTexture` returns nil when off, so the caller skips the blit and `recordFrame`'s existing `captureTexture` guard skips the byte-read + encoder, while the CSV/log/stem writes are untouched. Enable per session with `PHOSPHENE_RECORD_VIDEO=1` (e.g. a quality reel); the env-var idiom mirrors `PHOSPHENE_FULL_RAW_TAP`, and the choice is logged to session.log. +2 `SessionRecorderTests` (video off → nil texture + features.csv still records + no video.mp4; video on → texture allocates); the 3 existing video tests now pass `videoEnabled: true`; suite 25/25, swiftlint clean. **NB: quality-reel / video-dependent workflows now need `PHOSPHENE_RECORD_VIDEO=1`.** **Pending Matt's manual validation:** a normal session shows Activity-Monitor CPU roughly halved; 60 fps unaffected. `KNOWN_ISSUES.md` BUG-050.

## [dev-2026-06-17-215659] CLEAN.7.4 — `[GAP-14]` doc-artifact hygiene + close the PNG-blob decision (no rewrite)

Closes GAP-14. The "49 MB un-LFS'd diagnostics PNG blob" turned out already prevention-fixed (DOC.7 added the `docs/diagnostics/**/*.png`+`.jpg` LFS rule and pruned the loose V9 PNGs — 0 PNGs tracked in HEAD); the 49 MB is now purely historical (17 blobs, 35 MiB packed, in old commits). **Decision (Matt): no history rewrite** — purging 35 MiB is ≈ 3% of an LFS-dominated 1.2 GB clone (`.git` is 1.1 GB LFS), not worth a force-push that breaks every parallel session/clone; if a deliberate repo-maintenance freeze ever happens, fold the purge into it. (Aside flagged: a 59 MB `StemSeparator.mlpackage` weight is loose-in-history / not LFS — the real non-LFS lever if repo size ever bites; load-bearing, separate task.) **The rotate_docs half is implemented:** `rotate_docs.sh` §(d) is a report-only hygiene pass over docs/diagnostics + docs/prompts that flags tracked files ≥ 512 KB **not** covered by LFS (the next loose-blob risk) for the manual pruning pass — it never moves or deletes (the script's never-guess contract; whole files have no reliable "spent" signal). Read-only under `--dry-run`, exit code unchanged, red-armed (a staged 586 KB non-LFS file is flagged; clean tree → 0). `CODE_AUDIT_2026-06-13.md` G14 + CLEAN.7.4 → done.
## [dev-2026-06-17-215601] CLEAN.4.4 — renderer over-allocation: gate feedback/warp passes + fix the PSO cache key

Phase-4 (Performance) Stretch increment, renderer-only (parallel-safe — disjoint from the Phase-3 audio work). Two disjoint findings from audit T7; the other four T7 items (sceneTexture aliasing, resize stale-size, ray-march /height NaN, DynamicTextOverlay race) stay out of scope (CLEAN.4.3/4.5).

**(A) PSO cache keyed by name only → full compiled identity.** `ShaderLibrary.renderPipelineState(named:…:pixelFormat:…:supportICB:)` cached in `pipelineStates[name]` — the `name` String alone. But the compiled descriptor varies by `colorAttachments[0].pixelFormat` AND `supportIndirectCommandBuffers`, so two calls with the same name but a different format/ICB would get the **first-cached** PSO back — the wrong pixel format, or an ICB-incompatible PSO used as inherited state in `executeCommandsInBuffer`. Now keyed by a `PipelineKey(name, pixelFormat.rawValue, supportICB)` struct. **Live-vs-latent: latent hardening, not a live bug** — audited every caller: the production callers (`RenderPipeline` waveform/feedback_warp/feedback_blit, `PostProcessChain` bright/blur-h/blur-v/composite) all use **unique names**, each compiled **once** at init; preset multi-pass pipelines **bypass the cache** entirely (`PresetLoader` calls `device.makeRenderPipelineState` directly); `supportICB: true` appears **only in tests**. So nothing currently collides — but the key is now correct if a future caller reuses a name with a different format/ICB. Gate: `ShaderLibraryTests` +2 (same name + different `pixelFormat` ⇒ distinct PSOs; same name + `supportICB` false vs true ⇒ distinct) — RED on the name-only key, GREEN after; the existing same-key-returns-same-instance test still passes.

**(B) Feedback ping-pong + particle-warp allocated/run unconditionally.** The Milkdrop-style feedback ping-pong (`feedbackTextures`, ~32 MB @ 4K) was allocated by `mtkView(_:drawableSizeWillChange:)` on **every** resize regardless of the active preset, and was **never freed** on switch-away — so once any feedback preset (Membrane/Murmuration) had run, the 32 MB stayed resident for the rest of the session. Separately, the particle-mode (Murmuration) warp pass ran **every frame** writing a feedback texture that `drawParticleMode` never sampled (it draws straight to the drawable). **Predicate (the load-bearing decision):** the ping-pong is consumed only by **surface-mode** feedback presets (Membrane: warp → composite → blit). Particle-mode feedback presets (Murmuration) and all non-feedback presets sample nothing. New `RenderPipeline.activePresetSamplesFeedback` (`currentFeedbackParams != nil && particleGeometry == nil`) gates BOTH allocation (the resize handler + the `renderFrame` lazy path) AND the warp pass; `setFeedbackParams(nil)` (every non-feedback switch) frees the pair; particle mode now skips the warp entirely and allocates no ping-pong. Lifecycle preserved: a surface-feedback preset switched in after a resize re-allocates lazily at the current size (the D-061(a) hot-plug no-torn-frames contract holds for the presets that actually sample feedback).

**Verification — output-preserving by design.** Every certified preset's PresetRegression golden hash is **byte-identical** after the change (20 presets × 3 fixtures). The golden harness renders `preset.pipelineState` directly to a 64×64 texture — it never instantiates `RenderPipeline`, never exercises `renderFrame`/`drawWithFeedback`/`drawableSizeWillChange`, and never touches the PSO cache — so goldens are the **safety net** (proving no shared compiled path moved), and the **primary gate** is the alloc-count assertions: `DrawableResizeRegressionTests` +3 (non-feedback preset → 0 ping-pong textures on resize; particle-mode preset → 0; `setFeedbackParams(nil)` releases the pair), plus the 2 updated existing resize tests now set feedback params first (the old tests asserted the wasteful unconditional alloc). Closeout **ALL GREEN**: engine 1511 / app 388 / swiftlint 0-of-432 / doc-gates 10. Not visually verifiable (output-preserving). No M7 (goldens unchanged). Docs: `RENDER_CAPABILITY_REGISTRY.md` (§6 Feedback ping-pong row + §9 new PSO-cache row), `ENGINEERING_PLAN.md` Phase-CLEAN, audit `CLEAN.4.4` row, `KNOWN_ISSUES.md` T7 backlog.

## [dev-2026-06-17-212025] CLEAN.3.5 — StemCache eviction + close diag-log handle + retire dead helpers

Fourth Phase-3 increment (3.4 is Stretch/M7). Three resource/cleanup items from the audit's T4:

1. **StemCache eviction (the bound).** The in-memory streaming `StemCache` — `[TrackIdentity: CachedTrackData]`, ~7 MB/track (4 separated stems × ~10 s), no disk backing — had no eviction and is never `clear()`ed during normal operation, so it grew unbounded across the engine's lifetime under track churn (multi-GB). Added LRU eviction: `init(maxEntries: Int = 64)` (≈450 MB, same order as the on-disk `PersistentStemCache` LRU); an `lruOrder` array bumps recency on `store` + `loadForPlayback` only (the metadata accessors — `stemFeatures`/`trackProfile`/`beatGrid`/`beatIrregular` — are planning-time peeks, not playback, so they don't reorder); `store` evicts the least-recently-used entry past the cap. `init()` → `init(maxEntries: Int = 64)` is source-compatible (`StemCache()` callers unchanged). Streaming preview data has no disk backing, so an evicted track is re-prepared on next demand — acceptable vs unbounded memory.

2. **Diag-log handle closed.** `VisualizerEngine.diagLog` (`~/phosphene_diag.log`) was opened in `setupAudioRouting` (called once per engine at line 850) and never closed → one leaked FD for the engine's lifetime. Now `diagLog?.closeFile()` before reopen (defensive — `openDiagnosticLog` truncates + reopens, so a future re-setup can't dangle a handle) and in `deinit`.

3. **Dead helpers deleted.** `FFTProcessor.printHistogram` (console spectrum dump), `BeatDetector.percentileOfBuffer`, `RayMarchPipeline.depthDebugEnabled` — all verified zero references (incl. tests). `depthDebugEnabled` was a vestigial flag; the depth-debug pass (`runDepthDebugPass` / `depthDebugPipeline`) is gated by `debugGBufferMode`, untouched.

Gate: `StemCacheEvictionTests` (3 GPU-free — LRU evicts the oldest / re-storing a key doesn't grow / `clear` empties). A stale incremental `.o` (`ConcurrencyStressTests` referencing the old `StemCache.init()` symbol) surfaced at link and was resolved by a clean rebuild — a clean checkout (CI / Matt) never hits it. Engine + app build green, swiftlint `--strict` 0. Not visually verifiable. `KNOWN_ISSUES.md` untouched (audit item, no filed bug). EP §Recently Completed ✅.

## [dev-2026-06-17-204433] CLEAN.3.3 — mood-override cooldown survives repeat plays/sessions

Third Phase-3 increment. The per-track mood-override cooldown was **permanently dead from the 2nd play of any track**. `DefaultLiveAdapter` is created once for the engine's lifetime and keeps `lastOverrideTimePerTrack: [TrackIdentity: TimeInterval]`, recording the *per-track-relative* `elapsedTrackTime` at which an override last fired. `cooldownAdaptation` then suppressed if `elapsedTrackTime - last < 30s` — with no lower bound. On a replay (or a new session with the same track), the per-track clock resets to ~0 while `last` still holds the prior play's value (say 20 s), so `0 − 20 = −18 < 30` reads as "cooldown active." It stays active until `elapsedTrackTime` climbs back past `last` (75 s for a 20 s mark + 30 s window + headroom) — which a 30 s preview clip never reaches, so override never fires again after play 1.

Fix (engine-only, root cause): a backwards delta (`sinceOverride < 0`) now means the per-track clock went backwards — a replay or a new session reset it — so the stored timestamp is stale and the cooldown is **not** active (`recordOverride` refreshes it on the next fire). The three existing cooldown semantics (first fires, 2nd-within-30s suppressed, after-30s fires again) are unchanged.

"Report swallowed attempts" was already satisfied: the cooldown suppression returns a `.moodDivergenceDetected` event ("Mood diverging … but cooldown active (Xs / 30s)") that the consumer logs at `VisualizerEngine+Orchestrator.swift:198` — verified, not added (per-frame logging there would be 94 Hz spam). The `lastOverrideTimePerTrack` dict is unbounded by distinct tracks but immaterial (small structs, per-engine-lifetime); deferred to CLEAN.3.5's eviction sweep if it ever matters. Gate: `LiveAdapterTests.moodOverrideCooldown_survivesReplay`; LiveAdapter suite 12/12, swiftlint `--strict` 0. Not visually verifiable. `KNOWN_ISSUES.md` untouched (audit item, no filed bug). EP §Recently Completed ✅.
## [dev-2026-06-17-211442] BUG-036 sites 1 + 2 — VALIDATED in production; remainder + BUG-043 → parked/monitoring

Matt's manual validation of the RT-thread allocation fix (session `2026-06-17T20-52-27Z`, 8-track Spotify): **no audible-glitch regression, no visual stutter, no freeze-lurch.** The objective read backs it — analysis cadence was a rock-steady **60 Hz** through ~7 min of music (median Δt 0.0167 s, p99 0.0194 s, **worst gap 84 ms** over 25,017 audible frames), vs the original BUG-043 incident's 0.44 / 0.33 / **9.59 s**. The doorbell lull at the tail produced *no* Δt gap — the BUG-057 pause-suppression correctly read it as a user pause and analysis kept ticking on silence. **Two decisions (Matt):** (1) **BUG-043 → monitoring, not closed** — N=1 for an intermittent defect; consistent with "mitigated by BUG-036 sites 1+2," retire after a few more clean sessions (BUG-058/012 pattern). (2) **BUG-036 site 3 (raw-tap) + the analysis hand-off → parked** as an accepted low-risk residual — with BUG-043 (the forcing function) not recurring, the bounded-ring + persistent-consumer redesign isn't worth the concurrency risk now; re-open if a stall/glitch ever implicates the remaining allocations. The os-allocator Instruments proof for sites 1+2 is optional given byte-identical output + green tests + this cadence; not pursued. Docs-only entry (validation + tracker closeout). `KNOWN_ISSUES.md` BUG-036 §Progress + BUG-043 §Validation.

## [dev-2026-06-17-203109] CLEAN.3.2 — PresetScorer exclusion contract + zero-duration catalog.first bypass

Second Phase-3 increment. Two ways an **excluded/diagnostic preset could auto-install** despite the D-074 gate, both closed:

1. **Zero-duration `catalog.first` bypass** (`SessionPlanner+Segments.swift`). A zero-duration or section-degenerate track emits no segments in the normal loop and hits the "every track needs ≥1 segment" defensive fallback, which grabbed a raw `catalog.first` — array/alphabetical order, no exclusion filter — so a diagnostic (or a beat-locked preset on an irregular track) sitting first installed anyway. Now selects the best *eligible* preset (`rank().first(where: { $0.1 > 0 })`), degrading only to a categorically-eligible one; never a raw `catalog.first`.

2. **`PresetScorer.rank()` contract drift.** Its doc claimed "excluding zeroed presets," but the impl keeps hard-excluded presets in the output at score 0 (deliberately — `PresetScorerTests.rankStabilityAcrossTiers` inspects the 0 across tiers). The doc was the lie: fixed it to state reality + the **install idiom** every caller must use — `.first(where: { $0.1 > 0 })`, never a bare `.first` or `!isDiagnostic`-only filter (`score > 0` subsumes every exclusion, diagnostics included). Tightened the one caller that used the weaker filter — `ReactiveOrchestrator` (was `.first(where: { !isDiagnostic })`, could elevate a 0-scored non-diagnostic exclusion when all presets are excluded). Audited the other two `rank` callers: `DefaultPlaybackActionRouter` already uses `$0.1 > 0`; `LiveAdapter` mood-override is safe by construction (its `topScore − currentScore > gap` threshold can't be met by a 0 score) — both left unchanged.

Single source of truth: the categorical-eligibility filter (`!isDiagnostic && !(requiresRegularBeat && beatIrregular)`) was inlined in `cheapestFallback`; extracted to `DefaultSessionPlanner.categoricallyEligiblePool(_:onIrregularBeat:)` and shared by both defensive fallbacks so they can't drift. Gates: `SessionPlannerTests.zeroDurationTrack_neverInstallsDiagnostic` + `PresetScorerTests.rankContract_excludedKeptButNotInstallable` (both GPU-free). Orchestrator suites 53/53; swiftlint `--strict` 0. Engine-only, no public API change, not visually verifiable. `KNOWN_ISSUES.md` untouched (audit item, no filed bug). EP §Recently Completed ✅.

## [dev-2026-06-17-200818] CLEAN.3.1 — surface preset init failures (malformed-vs-missing sidecar)

First Phase-3 (P2 quality-hardening) increment. `PresetLoader.loadDescriptor` combined `fileExists` + `try? Data(contentsOf:)` + `try? decode` into one guard, so a sidecar that **existed but was malformed/unreadable** fell into the same `.info("No JSON sidecar…")` branch as a genuinely-absent file — a typo'd sidecar silently degraded the preset to default family/feedback params with no on-disk signal. Split into a new static `decodeSidecar(at:)`: returns `nil` for a missing file (benign — caller logs `.info` + name-only default) and **throws** for present-but-malformed (caller logs `.error` with the real decode error, then degrades to the same name-only default). The name-only default keeps `family = nil` — verified `PresetDescriptor.fallback` sets `family = .waveform`, so swapping to it would have *changed* behaviour; preserved the old `{"name":"X"}` semantics. App-side, `VisualizerEngine+Presets` `.postProcess` replaced `try?`+generic-log with a `do/catch` that surfaces the real `PostProcessError` (parity with the rayMarch path, already loud); fallback = the preset renders its base pass without post-processing (degraded, not black). The other audit-flagged init paths were already loud and verified sufficient: shader compile (`compileStandardShader`/`compileStagedShader` log + return nil → preset skipped, caught by the FA #44 count gate) and `RayMarchPipeline.init` (its call-site `do/catch` already logs the real error). Gate: `PresetLoaderSidecarTests` (3 GPU-free tests — missing→nil / malformed→throws / valid→decodes). Engine `swift test --filter PresetLoader` 16/16, app build green, swiftlint `--strict` 0. Not visually verifiable (loader / error-path hardening). `KNOWN_ISSUES.md` untouched (audit item, no filed bug). EP §Recently Completed ✅.
## [dev-2026-06-17-202354] BUG-036 — kill the RT-thread array allocations (sites 1 + 2; site 3 + hand-off → BUG-043)

The Core Audio IO-proc callback allocated a fresh `[Float]` on every callback of every session — the standing "do not allocate on the real-time audio thread" rule, violated at three audit-named sites and the prime suspect for the BUG-043 stall. This lands the two sites that are RT-thread-local (no cross-thread hand-off), the clean bounded win: **(site 1, `FFTProcessor`)** reuse a pre-allocated `magnitudesScratch`; a new zero-alloc `processStereo(interleaved: UnsafeBufferPointer)` averages L/R straight into the windowed-sample scratch (no `mono` array); the `[Float]` overloads delegate to it through a shared `runFFTCore`, making the file's "per-frame processing is zero-alloc" header true at last. **(site 2, `AudioBuffer`)** new `latestSamples(into:)` fills a caller-owned buffer in place; the callback reuses a pre-allocated `interleavedScratch`. All scratch is touched only on the one RT thread → no lock (cf. D-079's cross-core `tapSampleRate`). **FFT output is byte-identical** — the pointer path is bit-for-bit equal to the array path (new test, incl. short/partial-fill + ring-wrap) and the FFT/Chroma/BeatDetector goldens are unchanged. Closeout **ALL GREEN** (engine 1497 / app 388 / swiftlint 0 of 432 / doc-gates 10). **Deferred — coupled to BUG-043:** site 3 (raw-tap `Data()` + `queue.async`) and the analysis hand-off (`Array(...prefix())` + `analysisQueue.async`) both cross the thread boundary; making them allocation-free safely needs a pre-allocated ring drained by a persistent consumer — an unbounded→bounded cadence/concurrency change that lands on BUG-043's analysis-stall surface, so it sequences with that work, not blind before it. +3 regression tests; no production behaviour change beyond *where* it allocates. **Pending Matt's manual validation** (RT-audio glitches are felt, not unit-tested): a normal streaming session, no audible glitch regression — and the BUG-043 re-test (does the stall still recur after the alloc reduction?). `KNOWN_ISSUES.md` BUG-036 §Progress; audit `CLEAN.4.1`.

## [dev-2026-06-17-193009] silent-tap card pause-suppression — VALIDATED + RESOLVED

Matt validated the suppress-on-pause behaviour: a deliberate > 10 s streaming pause no longer raises the silent-tap card. With the broken-cold-install and Mode-B-freeze cases still firing (unit-proven) and the card surface already screenshot-validated, the BUG-057 card-on-pause UX residual is **Resolved**. This closes the entire silent-tap arc (detect → reinstall fix → card → pause-suppression), all on `origin`, full gate ALL GREEN. Docs-only entry. `KNOWN_ISSUES.md` BUG-057 §Card pause-suppression.

## [dev-2026-06-17-192429] Skein real-audio gates — pin to the deterministic fixture (kill a data-flake)

Two `SkeinCanvasHoldTest` "live tick path" structure gates went red during the BUG-057 closeout — **not a code regression** (Skein code byte-identical to the prior all-green run; `git diff` was audio/app/docs only). Root cause: the harness picks its real-audio input as *whichever live session has the largest `stems.csv`*, and the session Matt recorded to validate the reinstall fix (`2026-06-17T18-16-41Z`, now the largest at 3.8 MB) became the input — its most-stem-dominated 120-frame slice starts with **58 silent frames**, so the test's section boundary landed on a silent frame and production's correct silence gate (`SkeinState.swift:1130`, `stemMix > 0.001`) dropped it → no density pulse / lean / break. A textbook *red-on-data-not-code* flake (the helper's own comment warned about it). Fix (test-only): `recordedSessionsBySize()` now **prefers the deterministic `fixturegen-*` captures** (generated from committed audio fixtures, loud `slice[0]`) over live recordings, with live as a fallback and the skip-when-none path intact — so recording a session can't flip the gates red. Full `SkeinCanvasHold` suite **21/21 green**; swiftlint clean. No production/render change. `feedback_deterministic_tests_over_budget_widening` (deterministic input > machine-state-dependent).
## [dev-2026-06-17-195110] CLEAN.7.6d — photosensitivity runtime clamp evaluated and NOT pursued (D-166)

The deferred "A-next" clamp half of D-164 (CLEAN.7.6d), closed as a **decision increment — no code**. On starting it, two facts surfaced and went to Matt (two AskUserQuestion picks): (1) the **cert gate already enforces the 3/s line on everything we ship** — `PhotosensitivityCertificationTests` is 7/7 ENFORCED under a 4.5 Hz beat + stem drive sharper than real music, all certified presets ≤ 1 flash/s (Dragon Bloom 1.00 worst, a third of the limit); Phosphene ships only certified presets, so shipped content is already covered without a runtime clamp. (2) A *uniform* clamp is **pipeline-wide**, not the "single final pass at `draw(in:)`" D-164 assumed: `renderFrame` (`RenderPipeline+Draw.swift:126`) fans out to **8 terminal paths** each presenting its own drawable — no chokepoint — so a uniform clamp means rerouting all 8 with regression risk across every certified preset, for a net that never visibly engages on shipped content. **Matt's picks:** trip point = the medical limit (3/s); backstop = *cert gate is enough, skip the clamp*. A non-altering live monitor was offered and also declined for now. The **certification gate is the photosensitivity enforcement mechanism**; the `RayMarchPipeline:94` OR-flag slot stays reserved (reopen only on a new premise — un-certified / user-authored presets or live arbitrary-source rendering — with the 8-path cost in hand). New decision **D-166** (amends D-164). Docs: D-166, ENGINEERING_PLAN CLEAN.7.6d, CODE_AUDIT G9 + CLEAN.7.6d (clamp declined), RENDER_CAPABILITY_REGISTRY §9. No code, no tests changed, no golden regen, no M7. Residual A-next (open, unchanged): regional-area / saturated-red-flash channels.

## [dev-2026-06-17-184040] silent-tap card — suppress on a user pause (the BUG-057 UX residual)

Closes the residual UX wart from the reinstall fix: the silent-tap card still *appeared* on a deliberate > 10 s streaming pause (it keys on silence, not on the rebuild), showing alarming "restart audio in Terminal" copy when the user simply paused. Matt's pick: suppress on a likely pause. Mechanism reuses the reinstall fix's RMS latch — `AudioInputRouter.hasEverDetectedSignal` (session-scoped, reset per `start`) is forwarded through `VisualizerEngine.hasEverDetectedAudio` to `PlaybackErrorBridge`, which now treats a tick as a likely pause (no card) when callbacks are still advancing **AND** the signal is `.silent` **AND** the session has had real audio. A genuinely broken cold install (never delivered → latch false) and a frozen IO-proc (Mode B → callbacks not advancing) still raise the card — verified by 2 of the 3 new bridge tests. Important: the latch is RMS-based (`SilenceDetector`), not `audioSignalState` (which defaults `.active` and would falsely mark a broken tap as "had audio"). +3 `PlaybackStallDetectorTests`; app build green, swiftlint `--strict` 0, bridge suites 18/18. **Pending Matt's validation:** pause streaming > 10 s → no card (the DEBUG toggle Cmd+Shift+Option+A still force-shows it for look-checks). `KNOWN_ISSUES.md` BUG-057 §Card pause-suppression.

## [dev-2026-06-17-182334] BUG-057 reinstall fix — VALIDATED + RESOLVED

Matt validated the pause-churn fix (session `2026-06-17T18-16-41Z`): **3 pause/resume cycles, all recovered cleanly**, each logging `Tap reinstall SKIPPED — … user pause` with **zero reinstall churn** (the only tap install in the session is the cold `gen=1`), and the **same `gen=1` tap survived every pause and resumed** (`audio signal → active` ×3) — confirming the working tap self-resumes after a pause (the one assumption the fix rested on). The intermittent freeze (16-59-43Z) is gone; with no churn there's no dead-tap lottery. `KNOWN_ISSUES.md` BUG-057 reinstall facet → **Resolved** (fix `6bac999`). **Residual open UX question (Matt's call, separate):** the detector card still appears on a deliberate > 10 s streaming pause (keys on silence, not the rebuild) — suppress-on-likely-pause (the new `hasEverDetectedSignal` can drive it) / longer dwell / accept. BUG-058 (device-swap reinstall) is a distinct path, untouched, still its own rare P3. Docs-only entry (validation + tracker closeout).

## [dev-2026-06-17-180919] BUG-057 reinstall fix — step 3 (fix): don't rebuild a tap that was working (a pause)

Implements the step-2 diagnosis (instrumented session `17-45-44Z`): the `.silent → reinstall` recovery was churning the tap on every user pause — the tap reads silence because the *source* is paused, not because it's broken — and intermittently that churn lands a created-but-dead tap (the 16-59-43Z freeze). Fix: **only auto-reinstall a tap that never delivered audio** (a genuinely broken cold install — stale Screen-Recording grant / wedged daemon); a tap that *was* delivering and went silent is treated as a pause and left alone (it resumes on play). `SilenceDetector` gains `hasEverDetectedSignal` (latched on the first non-silent buffer) + `resetSignalHistory()`; `AudioInputRouter.start` resets it per session; `scheduleNextReinstall` early-returns (`Tap reinstall SKIPPED — … user pause`) when the session has had audio. Result: no more pause-churn or dead-tap lottery — and because the working tap is left alive, **the silent-tap detector card now auto-clears on resume** (it couldn't in 16-59-43Z; the freeze is fixed). Preserves BUG-055 / wedged-daemon recovery (a never-delivered cold install still reinstalls). Tradeoff: a tap that delivered then died *for real* mid-session (rare) is treated as a pause and not auto-recovered — the card surfaces it. Tests: +3 in `AudioInputRouterSignalStateTests` (never-had-audio fires / had-audio skips / reset clears the latch); also fixed a latent `TestClock` `[unowned self]` crash the new test exposed (its own comment said "capture strongly"). Engine build green, swiftlint `--strict` 0, signal-state + SilenceDetector suites green. **Pending Matt's manual validation** (step 4): pause/resume streaming → clean recovery, no freeze, `session.log` shows `Tap reinstall SKIPPED`, card auto-clears on resume. **Separate UX question for Matt:** the card still appears on a deliberate > 10 s pause (longer dwell / suppress-on-pause / accept). `KNOWN_ISSUES.md` BUG-057 §Reinstall fix step 3.

## [dev-2026-06-17-174055] BUG-057 reinstall fix — step 1 (instrument the `.silent → reinstall` recreate)

Defect Protocol step 1 (instrument → commit → STOP; no fix code) for the reinstall-comes-up-silent facet the detector surfaced (kickoff `docs/prompts/BUG-057_TAP_REINSTALL_SILENCE_KICKOFF.md`). The `.silent → reinstall` recovery (`AudioInputRouter+SignalState.performTapReinstall` → `SystemAudioCapture.stopCapture()` + `startCapture()`) had no per-step breadcrumbs, unlike the device-change `performReinstall` — so session `16-59-43Z` could only show `Tap reinstall #1 starting` then silence (no `gen=2` install line, no `succeeded`/`failed`), pinning the hang only to "somewhere in stopCapture or startCapture." Added per-step `session.log` breadcrumbs (via `onCaptureDiagnostic`) to `stopCapture` (`ENTER → cleanup` / `cleanup done`) and `startCapture` (`ENTER → createProcessTap` → `tap created` → `aggregate created` → `IO proc created` → `startDevice done`), mirroring `performReinstall`. The last breadcrumb before silence will name the exact stalling Core Audio call; also instruments the cold install for free (same `startCapture`). FA #73 — reuses the existing diagnostic sink, no new machinery, no behaviour change. Engine build green, swiftlint `--strict` 0; no unit test (breadcrumb-only on the real Core Audio path, not SPM-testable — same precedent as BUG-058 instrument). **Next (step 2, diagnose):** Matt runs one instrumented pause→resume streaming session (build from PRIMARY with Screen Recording granted); identify the stalling call + hang-vs-silent-recreate, reconcile with BUG-058, document root cause in `KNOWN_ISSUES.md`. No fix until diagnosed.

## [dev-2026-06-17-173204] silent-tap detector — card APPROVED; BUG-055 symptom + BUG-057 detector-half → Resolved

Matt validated the card surface via the DEBUG toggle (screenshot 2026-06-17): headline, body, the 3-step fix ladder, the `sudo killall coreaudiod` pill, and the auto-clear hint all render correctly with the right copy. **Card approved as the safety-net surface.** `KNOWN_ISSUES.md`: BUG-055 symptom (silent flatline, no guidance) → **Resolved** (the detector now surfaces an actionable re-grant step; durable signing CLEAN.2.5b still separate/open); BUG-057 detector-half → **DONE** (live auto-clear pends the reinstall fix). EP bullet ✅.

**Product direction recorded (Matt) — `feedback_self_healing_over_manual_remediation`:** the manual fix-ladder is a *fallback*, not the fix. The end-state must not make the user touch Terminal or System Settings. There is **no quick fix** that clears that bar — the Terminal step needs root (a signed privileged helper, not a button), and deep-linking the Settings panes only speeds the same manual toggling. The user-friendly answer is the app **self-healing** (the scoped BUG-057 reinstall auto-recovery → the common reinstall-hang recovers with zero user action → no card; plus stable signing for the re-grant step). So the leverage is the reinstall fix, not card polish. No code change in this entry (validation + tracker/doc closeout).

## [dev-2026-06-17-171140] silent-tap detector — validation finding + DEBUG force-toggle

Matt's first validation attempt (Spotify-pause, session `2026-06-17T16-59-43Z`) **confirmed the detector is correct** and exposed why the pause-repro is a bad test. The card appeared at ~15 s of silence but **never cleared on resume** — because the pause itself triggered the existing `.silent → reinstall` machine (`TAP: Tap reinstall scheduled … starting`), and the recreated tap came up **silent** (BUG-057's cold-install-silence, reproduced live far more easily than the 15-day `coreaudiod` wedge). `features.csv` is all-zero for the final ~150 s → audio genuinely never returned → the card *correctly* stayed up. Verified it's not a detector bug: `InputLevelMonitor.frameCount` is monotonic in production (`reset()` only ever runs in a unit test), so the freshness poll has no backwards-counter hazard, and `test_recovery_clearsCard` already proves auto-clear fires when fresh audio resumes.

**Consequence:** any real Mode-A trigger (pause, or a genuine stall) routes through `.silent → reinstall → BUG-057`, so the card can't be observed auto-clearing that way. Added a **`#if DEBUG` force-toggle (Cmd+Shift+Option+A)** that shows the real `AudioStallOverlayView` on demand — decoupled from the broken tap recovery — so the surface (look/copy/fade) can be validated. Matches the existing force-spider debug-shortcut pattern; never ships in release (the `@State debugForceStallCard` is OR'd into the card's visibility and is always false in release). `PlaybackShortcutRegistry` (+ `debugToggleAudioStallCard`), `PlaybackView`. App build green, swiftlint `--strict` 0; `PlaybackShortcutRegistryTests` unaffected (the optional closure defaults nil; coverage test uses `subtracting`).

**Product question raised (Matt's call):** until BUG-057's reinstall-comes-up-silent is fixed, the card fires (correctly) on every streaming pause > dwell, recoverable only by a manual output-device switch. Options: longer dwell, infer a deliberate pause, or fix the reinstall. Also worth a look: should `.silent → reinstall` fire on a *user pause* at all? See `KNOWN_ISSUES.md` BUG-057 §Validation note.

## [dev-2026-06-17-161332] BUG-057/055/058 — silent-tap detector (the user-facing fix; pending Matt's manual UX validation)

The whole silent-tap family presents identically to the user — the app shows "playing" but the visualizer is silent or frozen, with **no actionable hint**. This is the **fix increment (Defect Protocol step 3)** for that family: it does not fix the (environmental) silence; it **detects "no useful audio is reaching the visualizer" and tells the user what to do.** One surface closes the user-facing gap for all three bugs.

**The sharp edge — catch BOTH failure modes.** A naive detector keying on `SilenceDetector.silent` (RMS≈0) catches BUG-057 (wedged `coreaudiod`) / BUG-055 (stale Screen-Recording grant) but **misses BUG-058**: a device-swap freezes the tap IO-proc, the render loop coasts on the last buffer, so RMS stays nonzero and `.silent` never fires. So the detector keys on **"no FRESH audio,"** not "silent": a ~1 Hz poll samples whether the tap **frame count is still advancing** (`InputLevelMonitor.frameCount`, Mode B) **AND** the signal isn't confirmed `.silent` (`audioSignalState`, Mode A). `dwell` (~10 s) consecutive not-fresh samples raise the card; it auto-clears the instant fresh audio resumes.

**The gate is the whole point** (the false-positive guard, and the testable core): fires only while `SessionState == .playing && !isLocalFilePaused`, with the freshness baseline reset on gate entry (a full dwell of grace after play/resume). So it never false-fires pre-play, in the `.ready` wait, on a deliberate local-file pause, or during quiet musical passages (callbacks still advancing + not silent = fresh).

**Surface:** a non-blocking center overlay card (`AudioStallOverlayView`) — more prominent than the bottom-right toast because this is total loss of function — with a plain-language line + the fix ladder: (1) `sudo killall coreaudiod`, (2) if you just rebuilt, re-grant **Screen & System Audio Recording** then quit + relaunch, (3) check the macOS output device. Copy is developer-facing for now (literal Terminal command); soften before any public build. The card **supersedes** the existing 15 s `silenceExtended` toast while up (no double-surface).

**Wiring (FA #73 — reuse `PlaybackErrorBridge`, no parallel detector, zero engine changes):** the detector is folded into `PlaybackErrorBridge` (it already watches `audioSignalState` + owns the condition-ID toast machinery). New gate inputs are injected (sessionState, isPaused, a `frameCountProvider` closure reading `engine.inputLevelMonitor`, an injectable tick) so the gate is unit-tested deterministically with **no wall-clock**. `PlaybackView` renders the card layer and wires the bridge in `setup()`. Strings externalized to `Localizable.strings` (string gate green); the literal command renders via `Text(verbatim:)`.

**Deliberately NOT done (flagged for Matt):** no new `UserFacingError` case / `ErrorPresentationMode`. The card is a bespoke Bool-driven overlay, not routed through the generic error→presentation dispatch; an enum case + a presentation mode nothing dispatches on would be ceremony (and would force the `UserFacingErrorTests` 29-case count + every exhaustive switch to churn). If the card should later join the error catalog, that's a small follow-up.

**Files:** new `PhospheneApp/Views/Playback/AudioStallOverlayView.swift` (+ `project.pbxproj` registration); edited `PhospheneApp/Services/PlaybackErrorBridge.swift` (freshness poll + gate + card state + toast supersede), `PhospheneApp/Views/Playback/PlaybackView.swift` (card layer + bridge wiring + sessionState publisher), `PhospheneApp/en.lproj/Localizable.strings` (6 card keys + a11y label), `PhospheneAppTests/PlaybackErrorBridgeTests.swift` (+8 `PlaybackStallDetectorTests`: both modes fire, four false-fire guards hold, auto-clear). App build green; swiftlint `--strict` 0; string gate PASS; PlaybackErrorBridge + stall-detector suites 15/15.

**Pending:** Matt's manual UX validation (mandatory for a UX-flow change; no M7 — it's an error state, not a preset) — card renders/copy correct, appears only on a real stall, auto-dismisses on recovery. `KNOWN_ISSUES.md` `Resolved` fields (BUG-055; BUG-057's detector half) fill in after that pass. To exercise it live: route output to a non-tappable sink (Mode A) or unit-drive the gate; confirm the demo approach with Matt. Build from the PRIMARY checkout (a worktree build re-churns the Screen-Recording grant; worktree Release can't do Spotify — empty client id).

## [dev-2026-06-17-153519] BUG-038 → Resolved — ray-march light-flicker M7 passed

The ray-march light-intensity strobe (BUG-038, the BUG-019 residual: a 7–9 Hz brightness step from the un-smoothed per-frame light uniform) is **resolved by M7**. The EMA fix (`RayMarchPipeline.smoothLightIntensity`, τ ≈ 0.12 s; commit `5c349eb`) had been on `main` with automated validation green but awaited the human visual confirm. Matt's M7 (session `2026-06-17T15-10-28Z`, Ferrofluid Ocean on real audio, ~220 s): **steady lighting, no strobe.**

Data corroboration: the **raw** brightness target in `features.csv` still steps **8.0/sec** — identical to the pre-fix baseline — because `features.csv` records the raw FeatureVector, *upstream* of the in-shader EMA. Yet the rendered output is steady → the EMA suppresses a real, full-load ~8/sec jitter into a steady light uniform (not a calm-input fluke), mean-preserving so brightness still follows the energy swell. Three independent signals triangulate it: human M7, raw-jitter-present-but-render-steady, and the green `test_smoothLightIntensity_suppressesFrameToFrameFlicker`.

`KNOWN_ISSUES.md` BUG-038 → Resolved (removed from the Open Index; closes the BUG-019 flicker lineage). Surfaced during the post-BUG-057 live-test arc (the tap had to be working first to run a fair ray-march M7). Docs-only (the fix shipped earlier).

## [dev-2026-06-17-041554] BUG-057.instrument — cold-tap-install-silence: capture-install diagnostics to session.log

P1 multi-increment **step 1 only** (Defect Protocol: instrument → commit → STOP; no fix code). The streaming cold start installs the system-audio tap (`AudioHardwareCreateProcessTap` → `noErr`) but delivers persistent silence; the only recovery observed is a manual output-device switch, which fires `SystemAudioCapture.performReinstall` and then captures real Spotify audio (BUG-057). Identical create steps cold-vs-reinstall ⇒ the divergence is timing/state. This increment adds the observability to separate the four candidates — (a) TCC grant not yet effective on the first tap, (b) DRM-zeroing, (c) cold tap binds before audio flows, (d) the `.silent → reinstall` recovery is insufficient — from ONE real cold-start session, persisted to `session.log` (os_log rolls off).

**What now lands in `session.log` (prefix `TAP:`):**
- Per (re)install: `install via startCapture` / `reinstall via device-change`, with `gen=N defaultOutputDevice=<id> rate=<Hz> screenRecordingPreflight=<bool>` — separates same-device vs different-device reinstall (candidate d) and pins the preflight state at the moment of install (candidate a).
- A ~1 Hz `tap RMS gen=N t=+Xs rms=… peak=…` probe over the first 10 s of each install (computed in the IO proc; throttled, scalar, window-gated) — shows whether THIS specific tap delivered signal or stayed zero (candidates b, c).
- The `.silent → reinstall` scheduler timeline (`scheduled in …s (attempt #N)` / `skipped` / `succeeded` / `failed` / `backoff exhausted`), previously os_log-only.

**Wiring (FA #73 — reuse, no new machinery):** new protocol member `AudioCapturing.onCaptureDiagnostic`; `SystemAudioCapture` emits the install + RMS lines; `AudioInputRouter` exposes one `onAudioCaptureDiagnostic` (forwards the capture sink + mirrors its own reinstall lines), wired by `VisualizerEngine+Audio.setupAudioRouting` to `SessionRecorder.log`. The existing `.silent → reinstall` machine, `SilenceDetector`, and CLEAN.1.5 `DefaultOutputDeviceMonitor` are untouched. No production behaviour change.

**Files:** `Protocols.swift`, `SystemAudioCapture.swift` (+probe, `import CoreGraphics`, a `file_length` disable for the temporary diagnostic mass), `AudioInputRouter.swift`, `AudioInputRouter+SignalState.swift`, `MockAudioCapture.swift`, `AudioInputRouterSignalStateTests.swift` (+2 routing-lock tests), `VisualizerEngine+Audio.swift`. Engine+app build green; swiftlint `--strict` 0; signal-state suite 13/13. Not visually verifiable (diagnostic logging only); the live tap is not SPM-testable — the diagnosis artifact comes from Matt's instrumented cold-start session (step 2). No `RENDER_CAPABILITY_REGISTRY` change (audio-capture instrumentation).

**Next:** step 2 (diagnose) — Matt runs a cold-start Spotify session + a mid-session device switch (build from the PRIMARY checkout with Screen Recording granted — a fresh worktree build re-churns the grant and reproduces unrelated silence); from `session.log` identify which candidate(s) hold; document the root cause in `KNOWN_ISSUES.md` BUG-057. No fix code until diagnosed.

## [dev-2026-06-16-214242] CLEAN.7.6c — multi-pass flash-safety harness: G9 fully ENFORCED (7/7)

Closes the photosensitivity gate's remaining blind spot. CLEAN.7.6 / 7.6b validly measured only **3/7** certified presets (FFO + Murmuration + Nimbus); the other four read their music response through multi-pass / feedback paths the single-pass FeatureVector harness cannot drive, so they rendered static and were tracked-but-never-asserted-safe. CLEAN.7.6c drives those four through the REAL render paths headless and measures them — **all four 0–1 flashes/s SAFE, so G9 is now fully enforced 7/7.**

**Scoping correction (the kickoff's premise was wrong — verified against the JSON sidecars + the shaders).** CLEAN.7.6 / 7.6b persistently called Dragon Bloom + Fata Morgana "rayMarch multi-pass." They are not: their passes are `["direct","mv_warp"]` (0 raymarch loops) — mv_warp FEEDBACK presets, like Skein. The real split is **1 rayMarch (Lumen Mosaic) + 3 mv_warp feedback (Dragon Bloom, Fata Morgana, Skein)**, not 3 + 1. (Matt also flagged the numbering: this was drafted as "7.6b Stage 1b," but 7.6b is the runtime-clamp increment — renumbered to its own letter **CLEAN.7.6c**; the runtime clamp becomes 7.6d.)

**Route (spike-first; FA #73 — reuse the reference, don't rebuild):**
- **Lumen Mosaic** — extends BUG-034's production-parity ray-march harness: `RayMarchPipeline.render` at the live 128-step budget, post-process chain, the 4-light follower bound at slot 8, ticked per frame, with a real palette loaded (an unloaded palette renders black cells — BUG-016 — which would falsely read static).
- **Fata Morgana** — reuses its already-target-agnostic production method `renderFataMorgana(target:)` (FA #66 — no reimplemented encode path).
- **Dragon Bloom + Skein** — needed one small production seam: `renderMVWarpToTexture` (new `RenderPipeline+MVWarpHeadless.swift`) factors the present out of the mv_warp blit. A pure extract-method — the live `encodeMVWarpBlitPresentSwap` and the headless path now share `encodeMVWarpBlitContent` + `swapMVWarpTextures` verbatim, so they cannot drift. **Behaviour-preserving:** PresetRegression goldens unchanged. **Matt approved the seam** (the only deviation from the kickoff's "test-only" line; no look change, no M7).

**All-7 peak-flashes/s table** (worst-case 4.5 Hz beat + stem train, full-frame WCAG relative luminance, limit 3.0):

| Preset | peak flashes/s | gate |
|---|---|---|
| Ferrofluid Ocean | 0.00 | single-pass |
| Murmuration | 0.00 | single-pass |
| Nimbus | 0.00 | single-pass |
| Lumen Mosaic | 0.00 | multi-pass |
| Dragon Bloom | 1.00 | multi-pass |
| Fata Morgana | 0.50 | multi-pass |
| Skein | 0.00 | multi-pass |

**Files:** new `RenderPipeline+MVWarpHeadless.swift` (the seam + the shared blit-content / swap helpers, moved here so `+MVWarp` stays under `file_length`), new `MultiPassFlashHarnessTests.swift` (the 4) + `FlashHarnessSupport.swift` (the shared worst-case drive + WCAG luminance reducer, factored out of the single-pass gate). `PhotosensitivityCertificationTests` now skips the multi-pass set (`multiPassMeasured`) and still **fails loud** if a NEW certified preset renders static here without joining the multi-pass harness; its header's rayMarch mislabel is corrected. GPU tests — manual-closeout suite, not the CI fast gate. `swiftlint --strict` clean; photosensitivity 6/6 + PresetRegression 4/4 green. Docs: CODE_AUDIT G9 → ENFORCED (7/7) + Part C, RENDER_CAPABILITY_REGISTRY §9 → Supported (7/7), ENGINEERING_PLAN CLEAN.7.6c.

---

## [dev-2026-06-16-203759] BUG-053 RESOLVED — live-MIR sample-rate fix validated on a 44.1 kHz file

Matt's manual validation of CLEAN.3.7-fix (the SPM-untestable live-wiring leg). Session `2026-06-16T20-22-12Z` — Limo Wreck via 44.1 kHz local-file playback — logged `raw tap capture started sr=44100 Hz` then `MIR analysis rate → 44100 Hz (tap 44100 Hz)`: the live MIR adopted the file's real rate instead of the frozen 48 kHz default, end-to-end. The persisted `MIR analysis rate` line (`c68cc74`) was the signal; key estimation stayed out of it (unreliable — BUG-054). **BUG-053 → Resolved** (moved to `KNOWN_ISSUES.md §Resolved`; ENGINEERING_PLAN CLEAN.3.7-fix marked validated). Doc-status only, no code change.

---

## [dev-2026-06-16-202717] DOC.8 — doc-merge safeguards: union-merge the release log + collision-free entry ids

Every git conflict across the CLEAN.3.7 / BUG-053 / CLEAN.7.6b work this session was in two append-only doc logs (this file + ENGINEERING_PLAN §Recently Completed), never in code — two parallel sessions each prepending an entry at the same top-of-file region, plus hand-assigned `-a/-b/-c` ids colliding when sessions independently grabbed the next letter. Matt's pick (the cheap, targeted fixes):

- **`.gitattributes`: `docs/RELEASE_NOTES_DEV.md merge=union`** — the built-in union driver keeps both sides' new entries instead of conflicting. Correct for a prepend-only prose log; documented in `.gitattributes` as SAFE-only-here (no in-place edits / no tables — union would duplicate those, so ENGINEERING_PLAN / KNOWN_ISSUES / CODE_AUDIT deliberately stay normal-merge).
- **Collision-free entry ids `[dev-YYYY-MM-DD-HHMMSS]`** (this entry dogfoods it) — unique by construction, no more hand-renumbering. `rotate_docs.sh` (date-regex) and `DocIntegrityTests` (`YYYY-MM` prefix) key only on the date, so the suffix change is transparent; older `-a/-b/-c` entries are grandfathered. Convention documented in this file's preamble.

Not adopted (Matt may revisit): changelog-fragments (a file per increment) and branch-per-session + PR-gated merge — the structural fixes for the residual ENGINEERING_PLAN/concurrent-`main` conflicts. Test-only/infra; no production code. Verified: `rotate_docs.sh --dry-run` clean, DocIntegrity 10/10.

---

## [dev-2026-06-16-h] CLEAN.7.6b Stage 1 (partial) — flash-safety gate now measures Nimbus (3/7)

CLEAN.7.6 left the photosensitivity gate measuring 2 of 7 certified presets (FFO + Murmuration); the other 5 rendered static in the single-pass `FeatureVector` harness and were tracked in `unmeasurableInHarness` (never asserted safe). Stage 1's goal: faithfully measure the 5 by reproducing their real render paths headless.

**Scoping correction (verified against the code before building):** the 5 are not one problem. Only **Nimbus** is a `.direct` preset whose music response is a CPU follower buffer — cheaply reproducible in the existing single-pass harness. The other 4 need multi-pass headless rendering: **Lumen Mosaic / Dragon Bloom / Fata Morgana** are rayMarch G-buffer chains (Lumen is `.rayMarch`+`.postProcess`, *not* a single-pass follower as first assumed), and **Skein** needs the mvWarp feedback ping-pong. A prior harness effort (`MaterialRenderHarness`) explicitly rejected driving the full pipeline headless as too much scaffolding. **Matt's call: ship Nimbus now, the multi-pass 4 as a separate sub-increment.**

**This increment (Nimbus):** `renderLuminanceSequence` now constructs `NimbusState(device:)` for the Nimbus preset, ticks it per frame with the worst-case drive, and binds its live slot-6 state buffer instead of the zeroed one. `StemFeatures.zero` is correct for the 3 s window — Nimbus's directional stem lobes are gated out by its ~9–13 s cold-start ramp, so the full-frame flash signal is the FeatureVector-driven whole-body kick/bloom, which the beat train drives from frame 1. Nimbus removed from `unmeasurableInHarness`.

**Result:** `Nimbus: MEASURED | 0.00 flashes/s — SAFE | luma 0.009…0.035 (Δ0.026)`. Gate green (20 cases). **G9 coverage 2/7 → 3/7** (FFO, Murmuration, Nimbus all 0 flashes/s SAFE). Test-only, no production delta, no M7. The remaining 4 (rayMarch + feedback) are the **A-next multi-pass headless harness** sub-increment (CLEAN.7.6b Stage 1b), per `docs/prompts/CLEAN_7.6b_PHOTOSENSITIVITY_RUNTIME_KICKOFF.md`. Stage 2 (runtime clamp, `[M7]`) unchanged.

---

## [dev-2026-06-16-e] CLEAN.7.14 — SSGI 1080p perf gate made contention-robust (best-of-N; drop the `measure {}` variance check)

`SSGITests.test_ssgi_performance_under1ms_at1080p` flaked under the full ~1479-test parallel `swift test` run — the GPU-heavy parallel load the CLEAN.7.6 flash-safety suite added is what exposed this whole family (CLEAN.7.12/7.13/7.14). Two flake sources, both contention-driven, neither a real regression: (1) an `XCTest measure {}` block benchmarking the 1080p SSGI render **failed on relative standard deviation > 10 %** (~17.7 % observed under contention — XCTest's default variance bound), and (2) the actual overhead gate averaged **5 paired (with − without) `Date()` timings**, so a contention spike on any one submit inflated the mean. Isolated, the class is 7/7 green in ~0.13 s. Same flake class as CLEAN.7.9/7.10/7.11/7.12 and the structural twin of CLEAN.7.13 (the sibling single-sample ICB frame-perf gate, consolidated onto this same branch). Per the deterministic-over-budget-widening rule, the **sub-1 ms gate is kept, not loosened**: the `measure {}` benchmark is dropped, and overhead is now `minSSGI − minBase` over the **minimum of 8 warm samples per path** — contention can only ADD latency to a GPU submit, never subtract it, so each path's minimum is the clean estimate of its true cost and the difference of the two floors is the clean overhead. Test-only, no production delta (the SSGI render path is untouched). `KNOWN_ISSUES.md §Pre-existing Flakes` carries the resolved note.

**Consolidation note.** This branch (`confident-bohr`) consolidates **both** GPU-perf flake fixes: CLEAN.7.13 (ICB gate — the parallel `peaceful-ishizaka` session's commit `b49905b`, merged in preserving its hash) **+** CLEAN.7.14 (SSGI gate, this session). `peaceful-ishizaka` forked from `main` at CLEAN.7.6; the merge brings 7.13 onto the `main`-based line. The two branches independently used release tag `-c` (7.12 / 7.13) → reconciled here by renumbering **7.13 → `-d`, 7.14 → `-e`** (7.12 keeps `-c` — already on origin/main). `main` fast-forwards to this branch to land both; retire `peaceful-ishizaka` after.

---

## [dev-2026-06-16-d] CLEAN.7.13 — `RenderPipelineICBTests` ICB-frame perf assertion made contention-robust

The structural twin of CLEAN.7.10, surfaced under the full ~1469-test parallel `swift test` during the CLEAN.7.12 closeout. `RenderPipelineICBTests.test_gpuDrivenRendering_cpuFrameTimeReduced` gated one **warm ICB frame** (blit + compute + render) at `< 2 ms` via a **single `Date()` sample** around the submit — the most contention-fragile shape there is. Under the parallel suite a saturated GPU/CPU inflated that lone submit past 2 ms (the case-level wall time was a benign 0.277 s; the *timed inner submit* is what blew the gate); isolated, the test passes in ~0.37 s. Not a real perf regression — a single-sample timing artifact.

- **Fix (copies CLEAN.7.10 verbatim).** Keep the 2 ms gate, drop the flake: assert the **minimum of 8 warm samples** instead of one. Contention can only ADD latency to a GPU submit, never subtract it, so the min across N warm runs is the clean estimate of true cost and is robust to a few starved samples — the gate stays at 2 ms and still traps a real regression. Per Matt's deterministic-over-budget-widening rule (`feedback_deterministic_tests_over_budget_widening`); the threshold is **not** loosened. The `measure {}` variance block (10 iterations, reports average) is unchanged.
- **Scope.** Test-only — the ICB renderer path (`IndirectCommandBufferState`, the blit/compute/render encode helpers) is untouched, no production delta. One file changed: `RenderPipelineICBTests.swift`.

**Verified:** `swift test --filter RenderPipelineICBTests` green in isolation. Same flake class as CLEAN.7.9/7.10/7.11/7.12. `KNOWN_ISSUES §Pre-existing Flakes` (Resolved 2026-06-16) + `ENGINEERING_PLAN.md` (CLEAN.7.13 row). Not visually verifiable.

---

## [dev-2026-06-16-g] CLEAN.3.7-fix — live MIR adopts the actual capture rate (BUG-053)

Matt's call on the 3.7a verdict: **fix it properly.** The live `MIRPipeline` was built at app init (before the tap installs) with the 48 kHz default and `process()` carried no rate, so its sub-analyzers stayed frozen at 48 kHz bin→Hz tables regardless of the real capture rate.

**Fix.** Each rate-sensitive sub-analyzer (`SpectralAnalyzer`/`BandEnergyProcessor`/`ChromaExtractor`/`BeatDetector`) gains an in-place `setSampleRate(_:)` that recomputes its bin→Hz tables under its lock, **preserving running state** (AGC/chroma accumulators, onset history). `MIRPipeline.setSampleRate` (a same-file extension, to keep the class under `type_body_length`) forwards to the four and recomputes its Nyquist. `VisualizerEngine+Audio.processAnalysisFrame` calls it with the captured `tapSampleRate` — on the **analysis queue, off the RT thread** — so it's a **no-op on a 48 kHz tap** (zero behavioural change for the common config) and a recompute on a 44.1 kHz path or device-swap (couples to G1/CLEAN.1.5). Also replaced the **hardcoded 24 kHz mood-centroid divisor** with the live Nyquist: pre-fix the bin over-count and the fixed divisor *cancelled* (so the normalized centroid/mood were ≈ right by accident); fixing the analyzer alone would have reintroduced an ~8.8 % mood error, so the paired change keeps mood ≈ unchanged while making the raw centroid honest.

**Scope of the real-world bug.** Not just rare hardware — **local-file playback of 44.1 kHz files** (a normal feature) fed 44.1 kHz to the live MIR, so every such session mapped chroma/key ~1.5 semitones sharp + bands ~8.8 % low. The *offline* session-prep MIR was already correct (built with the file's rate).

**Gate.** `MIRSampleRateReconfigureTests` (GPU-free, on the CI fast-gate allow-list): raw centroid scales with the rate (48k/44.1k ratio), a fixed spike maps to a different pitch class across rates, a band cutoff lands on a different bin, sub-analyzer tables recompute, defensive no-op/zero-rate guards. The live wiring (VisualizerEngine) isn't SPM-testable (Metal) — that leg is the **manual 44.1 kHz / LF-playback key check** (BUG-053 §Status), same documented limit as `TapSampleRateRegressionTests`.

**Doc reconcile (3.7b).** `Audio/Protocols.swift` (`separate`'s rate is the *separator's* internal 44.1 kHz target, not a pipeline rate); ARCHITECTURE §Audio Analysis Tuning gains a **Sample-rate contract** subsection (per-stage rates) and the centroid/mood/key cross-path notes corrected (centroid/mood ≈ unchanged by the fix; key now correct per path). Default-trap framing: the 48 kHz/44.1 kHz construction defaults stay (tests rely on them) — the live path now actively reconfigures rather than relying on the default; `check_sample_rate_literals.sh` (bans `44100`, untouched) stays green.

Engine + app build green; swiftlint `--strict` 0; analyzer/MIR/stem/DocIntegrity suites green (61 GPU-free). Commits `91a973e` (code+test+CI) + `07bd2aa` (doc reconcile); merged to local `main` `6b23286`. **Validation signal (follow-up `c68cc74`):** the original plan was to eyeball the detected key, but key estimation has *never* tracked accurately (Matt) — and the rate bug shifts keys *sharp*, never flat — so a key letter can't confirm or refute the fix. Instead the live MIR's adopted rate is now persisted to `session.log` (`MIR analysis rate → 44100 Hz`) on the first analysis frame + on any change; that line is the verification (session `2026-06-16T16-52-09Z` predates it but already showed `raw tap … sr=44100 Hz`, so the path ran at the right rate). **BUG-053: fix landed, pending Matt confirming that line** (not yet marked Resolved).

---

## [dev-2026-06-16-f] CLEAN.3.7a — Sample-rate contract trace (GAP-2): live-tap MIR is frozen at 48 kHz (BUG-053)

Diagnosis-only increment (the kickoff's "trace & decide … commit the trace and stop if the fix is non-trivial"). Traced the tap sample rate end-to-end and **refuted the pre-kickoff hypothesis** that the streaming MIR is already rate-aware.

**Finding (BUG-053, P2):** the **live** `MIRPipeline` — the one `processAnalysisFrame` runs every frame — is constructed once at app init with `MIRPipeline()`, i.e. the `sampleRate: Float = 48000` **default** (`VisualizerEngine.swift:740`), and `MIRPipeline.process()` takes **no** sample-rate argument. Its four sub-analyzers (`SpectralAnalyzer`/`BandEnergyProcessor`/`ChromaExtractor`/`BeatDetector`) precompute their bin→Hz tables at init from 48000 and never see the live rate. The FFT's per-call `sampleRate: rate` only populates `FFTResult.binResolution`/`dominantFrequency` *metadata* — the magnitude array handed downstream is rate-independent — so passing the live rate to the FFT does **not** make the MIR rate-aware. The captured `tapSampleRate` is threaded to the **stem** path but never the live MIR.

**Impact (only when tap ≠ 48 kHz):** chroma/key estimate ~1.5 semitones sharp (`12·log2(48000/44100)`), band cutoffs ~8.8 % low; normalized centroid/rolloff cancel out, tempo/flux are rate-independent. **Masked on the common 48 kHz config** (the tap's typical rate + `readTapFormat`'s fallback are both 48 kHz), so silent today — manifests on a 44.1 kHz output device or a device-swap to one (couples to **G1/CLEAN.1.5**). The **offline** session-prep MIR is correct (`SessionPreparer+Analysis.swift:256` passes the file's real rate); the stem/Beat-This! resamples are correct. `check_sample_rate_literals.sh` bans `44100` but not `48000`, so it never caught this.

**Decision:** real (latent) defect → per the Defect Protocol the fix is a **separate increment** (`CLEAN.3.7-fix`), architectural (the MIR is built before the tap installs and holds per-track state), **pending Matt's pick of approach** — re-init-on-rate-change (honors the `SystemAudioCapture.sampleRate:66-71` contract, couples to G1) vs per-call rate threading vs make-the-48k-assumption-explicit-and-loud. 3.7b/c (doc reconcile + default-trap removal + regression gate) fold into that increment.

**Changed:** docs only — `KNOWN_ISSUES.md` (BUG-053 + index), `CODE_AUDIT_2026-06-13.md` (G2 row traced + CLEAN.3.7 backlog split), `ENGINEERING_PLAN.md` (3.7a entry). No production code changed → not visually verifiable; no new tests (the gate ships with the fix). Doc gates + lints green.

---

## [dev-2026-06-16-c] CLEAN.7.12 — `UMABuffer` concurrency test made deterministic

`UMABufferExtendedTests.test_concurrentWriteRead_noDataRace` raced a **fixed 30 s** `DispatchGroup.wait(timeout:)` against 200 trivially-fast concurrent blocks (100 writes + 100 reads). Under the full ~1479-test parallel `swift test` run, GCD thread-pool scheduling latency exceeded the deadline and the wait returned `.timedOut` (observed 34.9 s, CLEAN.7.6 closeout, 2026-06-16); isolated, the whole class runs in 0.048 s. The budget had nothing to do with the work — the blocks are lock-free and cannot deadlock; only pool-drain latency under contention varies.

Per the deterministic-over-budget-widening rule (CLEAN.7.9/7.10/7.11), the deadline is **removed, not widened**: the test now `wait()`s with no timeout — it returns exactly when the 200 blocks drain, however loaded the pool is, so it cannot flake on elapsed time. A genuine deadlock regression surfaces as a CI hang (same trade as CLEAN.7.11's `await …?.value`), not a flaky pass/fail. Added a smoke-level post-condition: each writer wrote a distinct index (`i < 100 < 1024`), so after the barrier `buf[i] == Float(i)` for all i — catching gross corruption / lost writes. True data-race detection still requires TSan, as the file header already notes. Test-only, no production delta (`UMABuffer` untouched). Engine class 12/12 green (0.048 s). `KNOWN_ISSUES §Pre-existing Flakes` + `ENGINEERING_PLAN.md`.

---

## [dev-2026-06-16-b] CLEAN.7.6 — photosensitivity flash-safety: enforced measurement gate (partial), runtime clamp deferred to A-next

G9 was the only open *safety* gap (P1) — flash-safety was per-preset convention (`SHADER_CRAFT` anti-strobe + the FFO anti-references) with **no enforced output-side clamp**; CLEAN.2.5a's hardened-runtime/notarization path made shipping outside the dev box real. This lands the **measurement half** of an enforced Harding/WCAG 2.3.1 invariant (≤ 3 flashes/s); the look-altering runtime clamp is a deliberate A-next follow-up (it would force a golden regen + M7 re-review of every certified preset). `[DEC D-164]`.

**Three Matt decisions (AskUserQuestion), in order:** (1) enforce by **measurement now / runtime clamp A-next** (the staged hybrid, not a clamp bundled now); (2) a **synthetic worst-case drive** for the gate; (3) after the gate exposed a harness limit, **ship the partial gate now, fold the rest into A-next**.

- **Work A — `FlashAnalyzer`** (`Sources/Renderer/FlashAnalyzer.swift`). Pure Harding/WCAG analyzer on a chronological full-frame relative-luminance sequence: hysteresis turning-point extraction (≥ 10 % swing), dark-state < 0.80 gate, peak flashes/s over a 1 s sliding window (a flash = a pair of opposing transitions). 8 synthetic self-checks (`FlashAnalyzerTests`) pin the semantics — steady/ramp safe, 6 Hz strobe unsafe, 2 Hz safe, 2.5/3.5 Hz brackets, dark-ceiling + 10 %-floor gating. **This substitutes for the prompt's intended FBS A/B validation, which is not runnable** — the "373-events" pre/post video was never committed (only 3-band feature CSVs survive); synthetic sequences at known rates prove the detector more precisely than a single real A/B.
- **Work B — `PhotosensitivityCertificationTests`** (sibling of `PresetContrastCertificationTests`). Renders each certified preset over a synthetic worst-case 4.5 Hz beat train (sharp full-amplitude accents + dev spikes over energetic-but-smoothed continuous bands, in the normal certified regime), measures rendered full-frame WCAG relative luminance (per-pixel sRGB→linear LUT), **fails cert at > 3 flashes/s**.
- **The forced-partial finding.** Three kickoff premises were false against the repo (surfaced before building): the FBS A/B video is gone; the `Fixtures/fbs` CSVs are 3-band extracts (no beat/dev/stem) and not `SessionDataLoader`-compatible; `PresetSessionReplay` is an un-importable `executableTarget`. Running the gate then revealed the structural limit: the single-pass `FeatureVector`-only harness validly measures only presets that read music response from the FeatureVector in-shader — **Ferrofluid Ocean (Δ0.010) + Murmuration (Δ0.022), both 0 flashes/s SAFE.** The other five render **static**: Lumen Mosaic + Nimbus (music response via CPU follower-state buffers, slots 6/8, zeroed here), Dragon Bloom + Fata Morgana (rayMarch — need the multi-pass G-buffer/lighting chain), Skein (painterly — needs feedback-texture history). A static render is **never asserted "safe"** (CLEAN.0 — the cardinal sin for a safety gate); the five are tracked in `unmeasurableInHarness` and the gate **fails loud on drift** (a known-static preset that starts responding, a responsive one that regresses to static, or a new certified preset that renders static). Valid coverage for the five **and** the runtime clamp both require the **A-next headless real-`RenderPipeline` harness** (followers ticked + feedback + multi-pass). Further A-next blind spots: regional/area-gating (full-frame mean only), the saturated-red-flash channel.

**Per-preset evidence (4.5 Hz worst-case beat train; full-frame WCAG luminance; limit 3.0):**

| Preset | Status | Peak flashes/s | luma Δ |
|---|---|---|---|
| Ferrofluid Ocean | MEASURED · SAFE | 0.00 | 0.010 |
| Murmuration | MEASURED · SAFE | 0.00 | 0.022 |
| Lumen Mosaic | unmeasurable (static) → A-next | — | 0.000 |
| Nimbus | unmeasurable (static) → A-next | — | 0.000 |
| Dragon Bloom | unmeasurable (static) → A-next | — | 0.000 |
| Fata Morgana | unmeasurable (static) → A-next | — | 0.000 |
| Skein | unmeasurable (static) → A-next | — | 0.000 |

**Verified:** `FlashAnalyzerTests` 8/8 + `PhotosensitivityCertificationTests` green (2 tests — FFO + Murmuration validly SAFE, 5 tracked-unmeasurable, non-empty guard passes); swiftlint `--strict` 0 violations on both new files. Test-only + one new Renderer source; **no production-render delta, not a look change → no M7 needed** (the A-next runtime clamp is the look-altering half and gets its own M7 sitting). Docs: `DECISIONS.md` D-164 (+ Index), `ENGINEERING_PLAN.md` (Recently Completed + U.9 deferral note), `CODE_AUDIT_2026-06-13.md` (G9 Part B + Part C 7.6), `SHADER_CRAFT.md` (anti-strobe → cited enforced invariant), `RENDER_CAPABILITY_REGISTRY.md §9` (new Partial capability). **G9 → PARTIALLY ENFORCED**; the runtime clamp + the 5 static presets are the recommended A-next increment.

---

## [dev-2026-06-16-a] CLEAN.5.5 — ML-weight load-time `sha256` integrity gate (closes Phase 5)

5.4d proved the ML weight `.bin` are **present** (not LFS pointer stubs). 5.5 is the complementary layer — proving they're **correct**. A truncated download, a partial smudge, bit-rot, a wrong-version checkpoint, or a tampered file all pass the present-check and then feed garbage into the stem separator / beat tracker with **no crash** (bad stems / wrong beats, not an error). The load-time `sha256` gate makes that fail loud. Present (5.4d) + correct (5.5) = the weight supply chain is closed. The audit's **G11** is **resolved**.

- **5.5a — beat_this (wire the hashes that already existed).** `Weights/beat_this/manifest.json` already carried 161 per-tensor `sha256` (written by `Scripts/convert_beatthis_weights.py`) — nothing validated them. Added `sha256` to `BeatThisManifest.TensorEntry`; `loadBeatThisTensor` now computes `WeightChecksum.hex` over the already-loaded `Data` and throws a new `BeatThisWeightError.checksumMismatch(key:expected:got:)` on mismatch.
- **5.5b — stem (generate, then validate).** The stem manifest had **no** `sha256`. `tools/add_stem_weight_checksums.py` hashes the **committed** `.bin` (the bytes that ship, already in LFS — **not** a fresh `tools/extract_umx_weights.py` umx extraction, which could produce subtly different bytes) and injects a `sha256` field into each of the 172 entries; the diff is additive (every `"bytes": N` gained a trailing comma + a `sha256` line, no reformatting). `--check` re-verifies. Added `sha256` to `WeightManifest.TensorEntry` + `StemModelWeightError.checksumMismatch(_:expected:got:)` in `loadTensor`, **alongside** (not replacing) the existing `expectedBytes` byte-count guard — the size check stays as the cheaper/clearer error for the common truncation case.
- **Shared helper.** `WeightChecksum.hex/verify` (new `Sources/ML/WeightChecksum.swift`, CryptoKit) — lowercase, no-separator hex matching the manifest digests + `shasum -a 256`. Each loader passes a closure that builds **its own** error type, so the shared helper stays error-agnostic and both near-cap `+Weights.swift` files stay under the 400-line lint cap.
- **MoodClassifier — out of scope.** Its weights are hardcoded `[Float]` literals compiled into the binary (`MoodClassifier+Weights.swift`, generated, "Do not edit manually") — there's no on-disk file to checksum; its integrity is the binary's integrity.
- **5.5c — tests + completeness gate + CI subset.** New **GPU-free** `WeightChecksumTests` (pure `Data` hashing, no MPSGraph/Metal): a known-answer hex pin (`sha256("abc")` / empty) so a future format change (uppercase, separators) can't silently never-match; reject (both error types) + accept; a **completeness gate** — every `.bin` on disk maps to a manifest entry with a non-empty 64-char lowercase-hex `sha256`, for **both** models (catches the real future hole: someone adds a weight file and forgets the hash); and a real-loader happy path (`loadAllStemWeights()` / `BeatThisModel.loadWeights()` both GPU-free). Added the suite's **type name** to the `--filter` allow-list in `.github/workflows/ci.yml` (CI has `lfs: true`; worktrees use `Scripts/bootstrap_fixtures.sh`).

**Verified:** `WeightChecksumTests` 8/8 green (real stem load 0.180 s, beat_this 0.047 s — the one-time hash cost, not per-frame); existing Metal-backed `test_weightsLoad_noThrow` (beat_this) + `test_init_loadsWeights_noThrow` (stem) still green, now also validating every committed byte against its committed digest; `tools/add_stem_weight_checksums.py --check` OK (172/172). **Empirical fail-loud proof:** flipped one byte of `bass_bn1_bias.bin` → the real loader threw `StemModelWeightError.checksumMismatch("bass.bn1.bias", expected: f8fc80d5…, got: c35b08d4…)` (byte auto-restored). swiftlint `--strict` 0 violations on all changed/new Swift. Not visually verifiable. **Phase 5 fully closed** (5.1/5.2/5.3 CI + 5.4 build-repro + 5.6 docs + 5.7 Node + 5.5 weights). Docs: `ENGINEERING_PLAN.md`, `CODE_AUDIT_2026-06-13.md` (Part B G11 + Part C Phase 5). Next queue: G1 (audio output-device-swap manual validation, Matt) + G9 (photosensitivity flash-safety, distribution now real) + Phase 3 P2-hardening.

---

## [dev-2026-06-15-k] CLEAN.5.4 — pin the build toolchain (Xcode + SwiftLint), commit Package.resolved, LFS-present gate, SHA-pin the Actions

The CLEAN.5.1 bring-up took four runs and **every red was "the CI tool version differs from dev"** (`[dev-2026-06-15-j]`). 5.4 makes the toolchain a declared, reproducible quantity along five axes. Locally verified, then **pushed to origin/main `8774e21` (2026-06-16) with fast-gate GREEN on macos-26** — the PR [#2](https://github.com/hoaxpoet/phosphene/pull/2) run + the on-push main run both passed every new step (pinned-Xcode select, LFS gate, pinned-deps build, pinned SwiftLint, SHA-pinned checkout) on a clean-cache runner.

- **5.4a — Xcode pinned.** New repo-root `.xcode-version` (`26.5`) is the single source of truth. The `Select Xcode` step selects `/Applications/Xcode_$(cat .xcode-version).app` **exactly** and **fails loud** (lists what's installed, `exit 1`) if absent — replacing `ls … | sort -V | tail -1` ("newest wins", which silently changes the compiler when the image adds 26.6/27). An image-rotation red means "go bump `.xcode-version`", not a code regression. Granularity = **exact** (kickoff's recommendation; the run-#1 Sendable-Metal lesson is exactly why drift must red).
- **5.4b — SwiftLint pinned.** The step downloads the exact **0.63.2** `portable_swiftlint.zip` (universal binary; asserts `swiftlint version == 0.63.2` before linting) instead of `command -v swiftlint || brew install swiftlint`, which floats to latest — that's how 0.63.3 (which dropped the `URL(string:)!` `force_unwrapping` flag) red-built run #2.
- **5.4c — Package.resolved committed + drift-failing.** Un-gitignored and committed **both** files CI builds from: `PhospheneEngine/Package.resolved` (`swift build`) and `PhospheneApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (`xcodebuild`). Both pin the same four transitive deps — argument-parser **1.7.1**, async-algorithms **1.1.3**, collections **1.4.1**, numerics **1.1.1** (previously floating on `from:`). The build step now passes `-disableAutomaticPackageResolution` (xcodebuild) + `--only-use-versions-from-resolved-file` (swift build): a `Package.swift` dep-graph change not reflected in the resolved file **fails CI** instead of silently resolving to new versions. `.gitignore` keeps the blanket `Package.resolved` ignore + two **anchored** negations (`/PhospheneEngine/…`, `/PhospheneApp.xcodeproj/…`) so `PhospheneTools/` and parallel-worktree copies stay ignored; line 16's `swiftpm/` **directory** exclusion became `swiftpm/*` (git can't re-include a file under an excluded directory; the dir's other contents, e.g. `configuration/`, stay ignored).
- **5.4d — LFS-present gate.** New `Scripts/check_lfs_smudged.sh` (CI step **before** Build; also runnable locally) fails loud if any Git-LFS file is still a pointer — `git lfs ls-files` column 2 is `*` (smudged) / `-` (pointer). A non-smudged checkout would otherwise bundle ~130-byte stubs for the ML weights and "build green" (CLEAN.0 no-silent-skip). 492/492 smudged here.
- **5.4e / 5.7 — Actions SHA-pinned.** `actions/checkout@v6` → `@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6.0.3`, with the bump procedure (`git ls-remote --tags …`) in a comment. Closes the "@major-tag silently moves" supply-chain gap for the one third-party action.

**Locally verified** (worktree `determined-franklin`): `ci.yml` parses (ruby YAML); `check_lfs_smudged.sh` → "all 492 LFS files smudged"; fresh `swift package resolve` **and** `xcodebuild -resolvePackageDependencies` both leave the committed resolved files byte-unchanged (pins are current → the new flags fail *only* on real drift); the actual `xcodebuild -scheme PhospheneApp … -disableAutomaticPackageResolution … build` → **BUILD SUCCEEDED**, reading the committed file. Not visually verifiable; no production Swift touched (workflow + one script + two resolved files + `.gitignore` + `.xcode-version` + docs). **Out of scope:** CLEAN.5.5 (ML-weight `sha256` load gate — last Phase-5 item); deployment target stays macOS 14.0 (this is the *build* toolchain). Docs: `RUNBOOK.md §Preconditions` (stale "Xcode 16+" → 26.5 + SwiftLint 0.63.2 + the SDK-floor reason), `ENGINEERING_PLAN.md`, `CODE_AUDIT_2026-06-13.md` Part C Phase 5.

---

## [dev-2026-06-15-j] CLEAN.5.1 CI green on GitHub (4 runs) + CLEAN.5.7 (checkout@v6)

The fast gate from `[dev-2026-06-15-i]` is now **green on `main`** ([run #4](https://github.com/hoaxpoet/phosphene/actions/runs/27592398557), `86c6532`). It took four runs — **each red was a real CI-vs-dev environment gap, not a flake**, which is exactly what a first CI surfaces:

1. **Run #1 (`macos-14`) red** — 18 errors, all `stored property … has non-sendable type 'any MTLDevice/MTLCommandQueue/MTLRenderPipelineState'`. macos-14 ships Xcode 16.2 / Swift 6.0.3, whose SDK doesn't mark Metal protocol types `Sendable`; dev (26.5) does. **Fix: `runs-on: macos-26`** (GA 2026-02; ships Xcode 26.5 — exact dev match). The build SDK must be Xcode 26; the deployment target stays macOS 14.0 via that SDK (the kickoff's "macos-14 matches 14.0" conflated build-SDK with run-target). Did **not** weaken production `Sendable` annotations.
2. **Run #2 (`macos-26`) red** — `macos-26` has no preinstalled swiftlint, so the `|| brew install swiftlint` fallback pulled latest **0.63.3** vs dev's **0.63.2**; 0.63.3 stopped flagging `URL(string: <literal>)!` as `force_unwrapping`, turning two `// swiftlint:disable:next force_unwrapping` into `superfluous_disable_command` errors. **Fix: remove the force-unwrap** (`try #require(URL(string:))` — version-independent, honors the project `force_unwrapping=error` stance).
3. **Run #3 red** — `PlaylistConnector`'s `appleMusic*` tests throw `.appleMusicNotRunning` on the headless runner (they pass on a dev Mac with Apple Music). "GPU/fixture-free" missed a third axis — **external-app runtime**. **Fix: drop `PlaylistConnector` from the allow-list** (it stays in the manual closeout gate, like the licensed-fixture suites).
4. **Run #4 green** — build, swiftlint, doc gates, 12-filter logic subset (14 suites), and both lint scripts all pass; the Node-20 deprecation annotation is gone.

**CLEAN.5.7** (folded in): `actions/checkout@v4 → @v6` (Node 24; GitHub deprecates Node-20 actions 2026-06-16) — the only Node-based action in the workflow.

**Durable lessons** (now in the workflow comments + `[[project_clean_audit_2026_06_13]]`): the macos image's Xcode determines whether Metal types are `Sendable`; CI tool versions must match dev or pin (→ **CLEAN.5.4**, kickoff drafted at `docs/prompts/CLEAN_5.4_REPRODUCIBILITY_KICKOFF.md`); the CI logic subset must be GPU-, fixture-, **and external-app-runtime-free**; `swift test --filter` matches the **type** name, not the `@Suite("display")` string. **Still pending Matt:** the GitHub branch-protection "required check" toggle (the only part of 5.1's done-when that isn't a code artifact). Not visually verifiable.

---

## [dev-2026-06-15-i] CLEAN.5.1/5.2/5.3/5.6 — CI fast gate on GitHub

First CI for the project: a **fast gate on GitHub-hosted runners** (Matt's strategy, 2026-06-15) — required-green on `main`, with the heavy suites left on the manual `Scripts/closeout_evidence.sh` gate. Code-complete and locally validated; the green-on-GitHub run + required-check toggle need Matt's push.

- **CLEAN.5.1 — `.github/workflows/ci.yml`.** `on: push(main) + pull_request`, `runs-on: macos-14`, `actions/checkout` `lfs: true` (the build bundles the ML weights), `concurrency` cancel-in-progress. Steps: select newest installed Xcode (the project is Swift 6.0 language mode → needs Xcode 16+; toolchain pin is 5.4) → **build** app (`CODE_SIGNING_ALLOWED=NO` — no Developer cert in CI, ships no artifact) + `swift build` engine → **swiftlint --strict** → **DocIntegrityTests** → **logic subset** → **string + sample-rate lints**. The build step alone catches the #1 regression class (compile breaks) with no GPU.
- **Test-subset = Option A (lean allow-list).** 13 explicit GPU/fixture-free suites (~130 logic tests: OAuth/Spotify, concurrency probe, metadata, mood, orchestrator scorer/planner/policy, beat-card builder, user-facing-error, track-prep). **Under-covers by design** — a new pure-logic suite isn't run until added. Option B (full-suite-minus-skip-list) is the follow-up, gated on proving `macos-14` has a working Metal device + the GPU suites pass there. **Gotcha recorded in the workflow:** `swift test --filter` matches the **type name** (`PresetScorerTests`), not the `@Suite("DefaultPresetScorer")` display string — so the filter is `PresetScorer`, not `DefaultPresetScorer`.
- **CLEAN.5.2 — `Scripts/bootstrap_fixtures.sh`.** Restores the gitignored, licensed `PhospheneEngine/Tests/Fixtures/tempo/` into a fresh worktree (the thing that bit a parallel session): prefer a **byte-identical `cp` from the primary checkout** (first entry of `git worktree list`, so the sha256 exact-bytes test passes) → fall back to `fetch_tempo_fixtures.sh`. Idempotent. Validated: copied 8 fixtures into this worktree, after which the full engine suite is green. The CI fast gate runs no fixture tests, so CI needs no fixtures.
- **CLEAN.5.3 — wire the gates + fix closeout Step-4.** `check_user_strings.sh`, `check_sample_rate_literals.sh`, and `DocIntegrityTests` are now CI steps (they were ad-hoc/closeout-only). `closeout_evidence.sh`'s `summary_lines` no longer prints the misleading `Executed 0 tests, with 0 failures` XCTest aggregate for swift-testing-only suites (e.g. DocIntegrityTests) when the real `Test run with N tests … passed` line is present. **Display-only** — the verdict logic still reads `xctest_failure_count` + exit codes directly, so the honesty contract is intact.
- **CLEAN.5.6 — doc reconcile.** `RUNBOOK.md §Gate structure — CI fast gate vs manual closeout` states plainly which checks are automated on push/PR and which stay manual (GPU + licensed fixtures + perf-timing). The worktree-fixtures section now points at `bootstrap_fixtures.sh`.

**Risk flagged for the first run:** the dev machine is on **Xcode 26.5 / Swift 6.3**; CI's `macos-14` ships Xcode 16. The code declares Swift 6.0 language mode + `.macOS(.v14)`, so it's expected to compile on the older toolchain, but the first GitHub run is the proof — if it red-builds on a toolchain mismatch, bump to `macos-15`/`macos-26` or pin (CLEAN.5.4). Out of scope: 5.4 (toolchain pin / Package.resolved / LFS-present check), 5.5 (ML-weight sha256 load gate). Not visually verifiable. No production Swift touched (workflow + script + closeout-reporting fix + docs).

---

## [dev-2026-06-15-h] CLEAN.2.5a — Enable hardened runtime + Apple Events entitlement (GAP-10 fix, HR half; notarization deferred)

Hardened runtime is now **on** for the app target — the deliberate build-settings flip CLEAN.2.4 deferred. Split from CLEAN.2.5: the Developer ID signing + notarization half (2.5b) needs a **paid Apple Developer Program membership the project does not have** (Matt, 2026-06-15), so only the hardened-runtime half landed here.

- **Step 1 — hardened runtime (Release config).** `ENABLE_HARDENED_RUNTIME = YES` on the app target's **Release** build config (`project.pbxproj`). **Debug is left unhardened deliberately:** HR turns on library validation, and a hardened test host refuses to `dlopen` the injected `PhospheneAppTests.xctest` (`… non-platform … different Team IDs`), so HR-on-Debug breaks `xcodebuild test`. HR is a distribution/Release property — Release-only keeps the test suite green and hardens the config that ships + notarizes. Signs with `--options runtime` under the existing "Apple Development" identity. (The first attempt put it in `Phosphene.xcconfig` = both configs; the app-test bundle-load failure forced the Release-only scope — durable learning recorded in `SECURITY_POSTURE.md §3`.)
- **Step 3 — Apple Events entitlement.** Added `com.apple.security.automation.apple-events` to `PhospheneApp/PhospheneApp.entitlements`. HR gates outbound Apple Events, and the `StreamingMetadata` now-playing bridge sends in-process `NSAppleScript` to Apple Music / Spotify — without the entitlement those calls fail under HR.
- **Step 2 — tap.** No change. The global `.systemAudio` tap is TCC-gated (screen-recording), not entitlement-gated, and is expected to survive HR; **no `com.apple.security.cs.*` entitlement was added speculatively** — one is added only if a real run shows the tap break.

**Verified (automated):** Release `xcodebuild build` green; `codesign -dv --verbose=4` on the Release product shows `flags=0x10000(runtime)` + a Runtime Version; `codesign -d --entitlements` shows `com.apple.security.automation.apple-events` on the signed binary; library validation left on (no `disable-library-validation`); the Debug `xcodebuild test` suite stays green (the unhardened host loads the XCTest bundle).

**Manual runtime gates VERIFIED 2026-06-15** (Matt, Mac mini, hardened Release build, session `2026-06-15T22-45-34Z`): (i) launches under HR ✅; (ii) `.systemAudio` tap installs + delivers audio under HR ✅ — signal green @ **−6 dBFS**, 11,425 live-energy frames in `features.csv` (the brief startup red/silent is the documented pre-playback artifact, not a fault); (iii) Apple Events ✅ **accepted** — the now-playing AppleScript poller ran under HR without fault and the entitlement is verified on the binary, but this Spotify-prefetched session didn't independently isolate it (displayed metadata came from the Spotify Web-API plan; per-poll AppleScript results aren't persisted), so accepted as satisfied-by-construction. Spotify connection itself confirmed working on the primary-dir Release build — note the **worktree** build had an empty `SPOTIFY_CLIENT_ID` because the gitignored `Phosphene.local.xcconfig` doesn't reach worktrees, so live tests must build from the primary checkout.

**Deferred — CLEAN.2.5b** (blocked on the paid membership): switch to `Developer ID Application` signing, notarize (`xcrun notarytool submit --wait` + `xcrun stapler staple`), and Gatekeeper-test on a clean account. GAP-10 is therefore **half-landed, not fully closed**. Two-line production diff (xcconfig + entitlements); no Swift source touched. `SECURITY_POSTURE.md` §3/§4 + summary row 3 + `CODE_AUDIT_2026-06-13.md` G10/Part C updated.

---

## [dev-2026-06-15-g] CLEAN.7.11 — `ToastManager` auto-dismiss test made deterministic (await the task, not a sleep budget)

`ToastManagerTests.autoDismiss_afterDuration` — filed as a flake in CLEAN.2.3.8 (`7558ca0`) with this exact fix prescribed — is now deterministic. It enqueued a `duration: 0.05` s toast, slept a **fixed 1000 ms** (already ratcheted up from 400 ms), then asserted `visibleToasts.isEmpty`; under @MainActor parallel-suite contention the auto-dismiss continuation could slip past that fixed window. Same flake class as CLEAN.7.9/7.10. Per the deterministic-over-budget-widening rule the budget is **removed, not widened**: `ToastManager` gains a `#if DEBUG` test seam `dismissTask(for:)` exposing the in-flight auto-dismiss `Task`, and the test now `await`s its `.value` — blocking exactly until the real dismissal completes, racing no deadline. Behavioural intent unchanged: a finite-duration toast auto-dismisses; an `.infinity` one schedules no task (early `guard`). Production dismiss logic untouched; test-only. Removed from `KNOWN_ISSUES.md §Pre-existing Flakes`.

---

## [dev-2026-06-15-f] BUG-052 — silence engine-test playback of love_rehab through the device

`swift test` (engine suite) audibly played a choppy `love_rehab.m4a` through the developer's output device. `SessionLifecycleChurnTests` exercises the real `.localFilePlayback` / `LocalFilePlaybackProvider` path (audible *by design* — the LF "open a file" feature), and its rapid start/stop/cancel churn made playback restart from the top repeatedly = choppy. **Fix:** `LocalFilePlaybackProvider.startPlayback` zeroes `engine.mainMixerNode.outputVolume` under XCTest (`NSClassFromString("XCTestCase") != nil`); the analysis tap is on the player node (pre-mixer), so the device goes silent without touching the captured signal or the playback lifecycle. Churn test stays 6/6 green; production audio unchanged. Collapsed P3 (Matt's call). BUG-052 → Resolved.

---

## [dev-2026-06-15-e] BUG-012 retired — MPSGraph EXC_BAD_ACCESS in StemFFTEngine (resolved by inference via CLEAN.1.2)

Retired the long-standing P1 stem-engine crash. BUG-012 was a latent, intermittent `EXC_BAD_ACCESS` in `StemFFTEngine` under sustained force-dispatch, **never deterministically reproduced** — so it's resolved *by inference*, not a reproduced fix. Its candidate root cause (the session-prep path driving the **same** `StemSeparator` unlocked alongside the live `stemQueue`) was closed by **CLEAN.1.2** (the BUG-031 fix: full input→predict→output serialized under one lock, stems returned by value; `da26a3a`).

Retired on convergent evidence: (1) the **CLEAN.1.6 TSan stress harness** — overlapping live+prep `separate()` on one shared `StemSeparator` + rapid session churn — ran **TSan-clean, 0 data races**, directly exercising this crash's race surface; (2) **zero crashes** across Matt's two real validation sessions (`17-22-31Z` + `17-58-44Z`, 2026-06-14), which cover sustained dispatch + prep-during-playback. If a `StemFFTEngine EXC_BAD_ACCESS` ever recurs it reopens under a new BUG number; the `BUG012Probe` diagnostic infra (`Sources/Shared/BUG012Probe.swift`) is retained for that. Moved to KNOWN_ISSUES §Resolved (condensed — the verbose instrumentation appendix stays in git `[BUG-012-i1]` + `ML.md`). Doc-only, no code change. Pushed to `origin/main` 2026-06-15.

---

## [dev-2026-06-15-d] DOC.6.2 — adopt 2.3.6's date-string rotation gate; supersede DOC.6.1's script-align

Resolves the last thread of the `upbeat-haslett` divergence: which of the two opposite DOC.6 fixes wins. DOC.6.1 (on main) had bent `rotate_docs.sh` to the gate's **datetime** cutoff and dropped the ✅/⏳ marker; CLEAN.2.3.6 (`71f050d`, on the now-retired branch) instead rewrote the **gate** to compare calendar-date **strings** + require a marker, mirroring the tool. CLEAN.2.3.8 had kept DOC.6.1 as a tie-break when landing the per-app deletion.

After a robustness review (this session): a **date-string** comparison is day-granular and cannot flake at the sub-day boundary that caused the original false-red; DOC.6.1's **datetime** gate retains that fragility (it only passes because the script was bent to match it). **Matt's call (2026-06-15): adopt 2.3.6's gate.** This **reverses CLEAN.2.3.8's keep-DOC.6.1 resolution** — informed by the robustness data the tie-break lacked.

- Ported `71f050d`'s gate to `DocIntegrityTests` — `rotationCutoffString` (local date-string, byte-for-byte matching `rotate_docs.sh`'s `date -v-14d +%Y-%m-%d` awk `<`) + the extracted `epEntryNeedsRotation(header:bodyLines:cutoff:)` predicate + a deterministic unit test (`engineeringPlanRotationPredicate`, fixed cutoff). **DocIntegrity 10/10** (was 9).
- **Reverted DOC.6.1's `rotate_docs.sh` change** to its original marker-aware / local-date-string form — now aligned with the date-string gate (no `TZ=UTC`, ✅/⏳-required, unparseable-date triage retained).
- Verified: DocIntegrity 10/10 green on origin/main's already-rotated docs; the 3-entry pruning DOC.6.1 performed stands. `upbeat-haslett` retired (its only unique content was this gate). Origin's `SECURITY_POSTURE.md §1` already reflected the per-app deletion (CLEAN.2.3.8); no change needed.

---

## [dev-2026-06-15-c] CLEAN.2.3.8 — Land the per-app-capture deletion onto main + fix quality-hints strings

Matt's manual test of **Settings → Audio Source** found the "Specific app" control broken: a raw `settings.audio.capture_mode.specific_app` label, a non-functional app list (couldn't select, no scrollbar), and a tab-switch-then-it's-selected quirk (the unwired `CaptureModeReconciler`). The `quality_hints` info section below it also rendered raw keys (`title`/`body`).

This is the cross-session divergence flagged in CLEAN.2.4's closeout. The fix already existed: in a parallel session Matt decided to **delete the per-app-capture subsystem** (CLEAN.2.3.5/2.3.6 on `origin/claude/upbeat-haslett-93311c`), but that work was never merged to `main` — which is why his build still showed the broken control. Per Matt's pick (AskUserQuestion: "land the deletion"), this increment brings it to main rather than rebuilding it:

- **Cherry-picked `a9c99ea`** (preserved as `cc1f086`, original attribution) — deletes the `CaptureMode`/`SourceAppOverride` types, `SettingsStore.captureMode`/`sourceAppOverride`, `CaptureModeReconciler` + `CaptureModeSwitchCoordinator` (and with them the D-061(b,c) capture-switch grace window in `VisualizerEngine`/`PlaybackErrorBridge` — the UX_SPEC §9.4 silence threshold is now the constant 15 s), `SourceAppPicker`, the AudioSettingsSection capture-mode picker, 4 `Localizable` keys, 5 `project.pbxproj` registrations, and the dead reconciler/coordinator/SettingsStore tests. App tests **388 → 377**.
- **Ported the 2.3.6 orphan-API removal** (`30689f9`) — `AudioInputRouter.switchMode`, `SystemAudioCapture.switchMode`/`availableApplications`, and the `RunningApplication` struct (all caller-less after 2.3.5). The engine `CaptureMode.application` case itself remains (just no longer reachable).
- **Removed the now-empty Audio settings tab** (Matt's follow-up call). After the capture-source picker was deleted, the Audio tab held only a vestigial `quality_hints` info caption — whose `title`/`body` strings were never even defined (raw on both main *and* the branch) — with no actual controls. Removed `SettingsSection.audio`, `AudioSettingsSection.swift` (+ its 4 `project.pbxproj` registrations), and the now-unused `settings.group.audio` + `quality_hints` strings. The settings sidebar is now Local Files / Visuals / Diagnostics / About. A source picker can be rebuilt if Specific App is ever re-added.
- **Updated `SECURITY_POSTURE.md §1`** — the engine retains an `.application` single-PID tap path in code, but it is no longer user-selectable (production always uses `.systemAudio`).
- **Kept main's DOC.6.1.** Explicitly **dropped the branch's competing `[DOC.6]` change** (`71f050d` gate rewrite + `09270ab` rotation) — resolving the two-parallel-fixes divergence in main's favour (gate authoritative). Took the registry-doc cleanups (ARCHITECTURE / APP.md / AUDIO.md / DECISIONS_HISTORY) so they no longer describe deleted code.

Supersedes **D-052** (full) and **D-061(b,c)**. Resolves the two CLEAN.2.3 out-of-scope findings (`CaptureModeReconciler` unwired; `specific_app` key mismatch). CLEAN.2.4 / CLEAN.2.3.7 work preserved intact. App tests 377 (retry-green), swiftlint clean, doc gates 9/9; the engine block shows only the pre-existing `SkeinCanvasHold` (BUG-049) + a `ToastManager.autoDismiss` timing flake — both confirmed unrelated to this change (zero shared symbols; app code byte-identical to the prior 377-green run). Pushed to `origin/main` 2026-06-15.

---

## [dev-2026-06-15-b] CLEAN.2.3.7 — Connector cross-link discoverability + affordance polish

Follow-up to CLEAN.2.3.1, surfaced by Matt's manual walk of the now-wired "Use [other service] instead" cross-links. The walk found they don't read as tappable, and that the two connectors handle them inconsistently — exactly the kind of thing a view-model test can't catch.

Root cause (verified in source):
- **Spotify** (`SpotifyConnectionView`) — the "Use Apple Music instead" footer renders in *every* state (it's unconditional), but at `white @ 40 % opacity`. 40 % opacity is this app's *disabled* visual convention (e.g. `ReadyView`'s preview-plan button dims to `0.4` when disabled), so a fully-functional link read as greyed-out / absent.
- **Apple Music** (`AppleMusicConnectionView`) — worse: "Use Spotify instead" existed *only* in the error state. On the normal "Start a playlist… checking every 2 s" screen there was no cross-link at all, so you couldn't jump to Spotify except via the back arrow.

Fix (Matt's pick: **bordered secondary** — the app's existing `.buttonStyle(.bordered)` convention, used by ConnectingView/ReadyView/etc.):
- Both cross-links now use `.buttonStyle(.bordered)` and render as an **unconditional footer** in every state of both connection screens, placed consistently at the bottom.
- Apple Music's error-only copy was removed (the footer now covers the error state too).
- Added `accessibilityIdentifier`s to both.

`switchConnector` / NavigationStack wiring is unchanged — this is the CLEAN.2.3.1 *action* made visible, not a behaviour change. View-only (declarative layout/style, no logic), so no new automated test; the 388 app tests are the regression gate and final placement/contrast is a visual check on the build. Switching is also still available via the back chevron → picker tiles. App build + 388 tests green, swiftlint clean. Pushed to `origin/main` 2026-06-15.

---

## [dev-2026-06-15-a] CLEAN.2.4 — macOS entitlement / local threat-model review (GAP-10); closes Phase 2

The last Phase-2 item and the remaining audit security finding (GAP-10). **Review + document increment — no security build settings were flipped** (enabling hardened runtime / the sandbox / Developer ID can break the audio tap, the Apple Events bridge, or signing; each needs a build + a real run, so they are filed, not applied blind). Produced **`docs/SECURITY_POSTURE.md`**: the verified security posture + a local threat model across seven surfaces, each with verified-state / threat / decision-or-filed-fix. Doc-only — no production code changed, not visually verifiable, no tests added.

Every posture claim was re-verified against source (2026-06-15):
- **Sandbox off** — `PhospheneApp.entitlements` declares only `app-sandbox = false`. Incompatible with the global Core Audio tap + Apple Events + arbitrary file-open; partial sandboxing not viable → documented, no fix.
- **Hardened runtime + notarization absent** — `ENABLE_HARDENED_RUNTIME` not present anywhere (pbxproj/entitlements/xcconfig); signing is `Apple Development` (dev-signed, **not** Developer ID, not notarized). Blocks Gatekeeper-clean distribution.
- **Tap scope** — `.systemAudio` = global tap excluding nothing; `.application` = single PID. TCC-gated on screen-recording; **audio-only, no screen pixels**. `SessionRecorder` records the app's **own Metal output** to `~/Documents/phosphene_sessions/` (local, no network) — so the `NSScreenCaptureUsageDescription` "No video is recorded" claim is honest about *screen* capture.
- **OAuth callback** — `handleCallback` validates scheme + host + `state` (CSRF/replay) + nil-pending rejection (CLEAN.2.2); `.onOpenURL` double-checks scheme/host → mitigated, no fix.
- **Library validation** — not declared; links Apple frameworks + SPM static libs only → not required (keep on under hardened runtime).
- **m3u / local-file** — parser is defensive (BOM/UTF-8/readability/throw), but resolves arbitrary absolute/relative paths with no extension/traversal guard. Consequence bounded by the no-egress local-file path → P3 defense-in-depth.
- **Secrets + no-telemetry** — OAuth tokens in Keychain; only the public client ID checked in (empty `Phosphene.xcconfig`); no telemetry/cloud; tap audio + recordings never uploaded. Documented as the headline posture strength.

**Decision (Matt, 2026-06-15): eventual distribution is on the roadmap.** This keeps 2.4 a review increment but makes hardened-runtime + notarization a **near-term filed follow-up** rather than indefinitely deferred:
- **CLEAN.2.5** (filed) — enable hardened runtime + Developer ID + notarization; verify the tap installs under it, Apple Events reach the music apps, Gatekeeper accepts the notarized build, library validation stays on. Its own increment (signing pipeline + real Gatekeeper/tap test).
- **BUG-051** (filed, P3) — m3u entry input-validation hardening (extension allow-list + path canonicalization). Low value given no-egress; tracked.

GAP-10 marked **reviewed** in `CODE_AUDIT_2026-06-13.md` (Part B G10 + Part C); `SECURITY_POSTURE.md` referenced from `RUNBOOK.md`; **not** added to the CLAUDE.md handbook index (D-161 budget ratchet). **Phase 2 (Spotify secret → OAuth → honest-UI → entitlement review) complete.** Pushed to `origin/main` 2026-06-15 (`1c5d899`). (Closeout fully green after restoring the worktree's gitignored licensed tempo fixtures from the main checkout per RUNBOOK §Worktree setup — environmental, no code change.)

---

## [dev-2026-06-14-g] DOC.6.1 — rotate_docs.sh ↔ DocIntegrityTests rotation-boundary fix + due pruning pass

The DOC.6 rotation gate (`DocIntegrityTests.engineeringPlanRotationGate`) was RED on `main` — it flagged three 2026-06-01 `ENGINEERING_PLAN.md` §Recently Completed entries as overdue for rotation, but `Scripts/rotate_docs.sh --dry-run` said "nothing to move," so the gate's prescribed remedy was a no-op. Pre-existing calendar pruning debt (CLAUDE.md "every 10th increment / 2 weeks") compounded by a gate↔script boundary inconsistency; surfaced by CLEAN.2.3's `closeout_evidence.sh`.

Aligned `rotate_docs.sh` to the gate (the gate is authoritative for the rotation contract):
- **local-vs-UTC.** The gate parses header dates in UTC and compares against `Date()`; the script computed its 14-day cutoff in local time. At 23:15 CDT (= 04:15 next-day UTC) the local cutoff (`2026-05-31`) sat a day behind the gate's UTC cutoff (`2026-06-01`), excluding the 06-01 entries. `TODAY`/`CUTOFF` are now `TZ=UTC` (this also brings `CUR_MONTH` into line with the UTC-parsed release-notes budget gate).
- **strict-vs-inclusive + marker.** The gate flags any bodied entry dated 14+ days ago regardless of ✅/⏳; the script's move predicate required `dated < cutoff` (strict — excludes the exact-14-day boundary) *and* a ✅/⏳ marker. One flagged entry (`Mid-Spike-1 fix`) carried no marker, so a date-only fix would have left the gate red. The predicate is now marker-agnostic and inclusive (`dated <= cutoff`), matching the gate; the unparseable-date triage report (the one case that genuinely needs a human) is retained.

Then ran the now-due pruning pass: `rotate_docs.sh` moved the three entry bodies (Dragon Bloom Spike 1, Mid-Spike-1 fix, LF.6.streaming) verbatim to `ENGINEERING_PLAN_HISTORY.md`, leaving header-only stubs; KNOWN_ISSUES §Resolved + monthly release-notes rotations were already current. `Mid-Spike-1 re-tune` (2026-06-02) correctly stayed full (the inclusive boundary did not over-rotate the not-yet-14-day entry). Verified: `swift test --package-path PhospheneEngine --filter DocIntegrityTests` 9/9 green (rotation gate passes), a second `--dry-run` is a no-op (idempotency intact), and a verbatim spot-check confirms moved-not-lost (`kWaveTargetRMS` / `StreamingArtworkURLResolver.swift` now resolve only in the history file). Script + docs only — no production code touched. Not pushed (awaits "yes, push").

---

## [dev-2026-06-14-f] CLEAN.2.3 — Wire-or-hide dead UI + close the localization-gate bypass (honest-UI increment)

Third Phase 2 increment: the honest-UI pass (audit T5 / AUDIT-2026-06-09). Four sub-increments, each gated on Matt's product call (wire vs hide), committed separately. Build + 388 app tests green, swiftlint clean, `check_user_strings.sh` green. Not pushed (awaits "yes, push").

- **CLEAN.2.3.1 — "Use Apple Music instead" cross-link wired.** The footer on the Spotify connect screen shipped a no-op `{ }` handler; its mirror ("Use Spotify instead") only *dismissed* the picker rather than switching. Both now drive a real switch through a bound `NavigationStack` path on `ConnectorPickerViewModel` (`connectorPath` + `switchConnector(to:)`) — tapping either takes you to the other connector. Regression test asserts the VM nav action, not an empty closure. Matt's call: **wire** (restore symmetry). Commit `7800b72`.
- **CLEAN.2.3.2 — Settings `.localFile` capture mode removed.** The "Audio source → Local file" radio said "coming in a future update" and no-op'd on selection, though local playback shipped months ago (reached by *opening a file*, LF.4–LF.6). Removed `CaptureMode.localFile` (enum case, picker row, false "coming later" string) and the now-unreachable `CaptureModeReconciler` / `CaptureModeSwitchCoordinator` branches. Decode is migration-safe (`decodeOrDefault(.systemAudio, …)` swallows a persisted `"localFile"`). Distinct from `InputMode.localFile(URL)` (the SoakTestHarness diagnostic path) — that is untouched. Supersedes the `.localFile` branch of **D-052** (annotated in `DECISIONS_HISTORY.md`); fixed the stale `.localFile` "coming later" descriptions in `ARCHITECTURE.md` + `APP.md`. Matt's call: **remove**. Commit `d40cfad`.
- **CLEAN.2.3.3 — "Swap preset" stub hidden.** The plan-preview row context menu shipped a greyed `Button(){}.disabled(true)` "Swap preset" that does nothing until U.5b's preview loop. Gated behind `#if ENABLE_PRESET_SWAP` (mirrors the existing `ENABLE_PLAN_MODIFICATION`-hidden Modify button); the `swapPreset` / `onSwap` plumbing is kept intact (already covered by `PlanPreviewViewModelTests`). Matt's call: **hide** behind a flag. Commit `6e983c8`.
- **CLEAN.2.3.4 — localization gate widened.** `check_user_strings.sh` only scanned `PhospheneApp/Views/`, so user-facing copy in ViewModels/ContentView/indirection helpers bypassed it. Widened ROOTS to `ViewModels` + `ContentView.swift`, added a connection-state `.error("…")` arm (with a `logger.error` exclusion so log lines aren't false positives), and externalized the bypassing copy: Spotify/AppleMusic error strings (reusing existing `connector.*.error.*` keys where text matched), `ConnectorType` tiles, `ReadyViewModel` duration/source-name, the `ContentView` preparation fallback, the `PreparationProgressView` streaming subtitle (singular/plural preserved), and the `PlanPreviewTransitionView` labels — ~22 new `Localizable` keys. The gate header now documents its honest scope limit: it is a literal-prefix matcher (SwiftUI text modifiers + `.error("…")`); lowercase and string-interpolated fragments still rely on review. Commit `46d836b`.

**Two out-of-scope findings surfaced while reading (filed, not fixed in this increment):**
- **`CaptureModeReconciler` appears unwired in production.** It is never constructed anywhere in `PhospheneApp` (only comments + the test harness reference it), yet `CAPABILITY_REGISTRY/APP.md` listed it `production-active`, owned by `PlaybackView`. Either the live capture-mode-switch path (changing "Audio source" in Settings → `AudioInputRouter.switchMode`) is not wired, or the registry is stale. After 2.3.2 the class only handles `.systemAudio` / `.specificApp`. Recommend a follow-up to wire it (if mid-session capture-mode switching should work) or delete it + correct the registry.
- **`settings.audio.capture_mode.specific_app` key mismatch.** `AudioSettingsSection` references that key, but `Localizable.strings` defines `settings.audio.capture_mode.app` (no `.specific_app`) — so the "Specific app" radio likely renders its raw key string. Pre-existing (a rename that didn't propagate), unrelated to the dead-`localFile` removal. One-line fix (point the view at `.app`, the existing key).

---

## [dev-2026-06-14-e] CLEAN.2.2 — Spotify OAuth correctness (login re-entrancy, refresh double-spend, P3 hardening)

Second Phase 2 increment, hardening the correctness of the sole remaining Spotify auth path — `SpotifyOAuthTokenProvider` (app layer, Authorization Code + PKCE, client ID only; CLEAN.2.1 deleted the last client-secret path). **None of these blocked login**, but all three were real latent defects on the live user-facing flow.

- **CLEAN.2.2.1 — re-entrant `login()` leak + stray timeout.** `login()` stored a single `pendingContinuation` and armed a `timeoutTask`. A second `login()` while one was pending **overwrote** `pendingContinuation` — orphaning the first caller (it hung until the 5-min timeout) — and armed a **second stray timeout** that could later fire against the wrong attempt. This is reachable from the UI: `SpotifyConnectionViewModel.login()` does `connectTask?.cancel()` then starts a new login Task, but cancelling the VM task does **not** resume the provider's `CheckedContinuation`, so a re-tap yields two overlapping `provider.login()` calls with the first still pending. **Fix:** concurrent logins now **coalesce** onto one in-flight attempt — `pendingContinuations: [CheckedContinuation]`, only the first opens the browser + arms the timeout, and a new `finishLogin(_:)` cancels the timeout and resumes *every* coalesced continuation on all paths (success, denied, state-mismatch, exchange-failure, timeout). Coalesce (not reject) because a spurious "auth failed" mid-login would be user-visible while the one real browser flow is still open.
- **CLEAN.2.2.2 — refresh double-spend.** `acquire()`'s silent refresh fired independently per concurrent caller; since Spotify **rotates** refresh tokens, the 2nd+ refresh sent an already-invalidated token → spurious `.spotifyAuthFailure` and a needless forced re-login. **Fix:** concurrent `acquire()` calls now dedup onto a single in-flight `refreshTask` (the shape the deleted `DefaultSpotifyTokenProvider` used, ported into the OAuth actor). The dedup is guaranteed by construction, not timing: `acquire()` sets `refreshTask` synchronously before its first suspension, so a concurrent caller always observes it; `runSilentRefresh` clears it via `defer` on the actor, which is also cancellation-safe.
- **CLEAN.2.2.3 — P3 hardening.** (a) OAuth **`state`** CSRF/replay guard — a random `state` is generated in `login()`, sent in the authorize URL, and verified in `handleCallback`. (b) **Form-body encoding** — replaced `.urlQueryAllowed` (which leaves `+ & = /` intact, corrupting auth codes / tokens that contain them) with RFC-3986 unreserved-set percent-encoding. (c) **Keychain** save failures are now logged, not swallowed by `try?` (the access token still works the session; only the next cold start is affected — login is not failed over a Keychain hiccup). (d) Callback validation now checks **`scheme == "phosphene"`** in addition to host.

**Tests** (`PhospheneAppTests/SpotifyOAuthTokenProviderTests`, all green): overlapping-login coalesce (one browser, both callers resume — watchdog-raced so the pre-fix actor fails fast instead of hanging), concurrent-acquire single-refresh (request counter == 1), `state` round-trip (success now echoes state from the authorize URL) + mismatch rejection, form-encoding (`%2B %2F %3D %26`). Provider/connector contracts unchanged (`SpotifyTokenProviding`, `SpotifyOAuthLoginProviding`). Commit `13cec8b`.

**Resolved 2026-06-14.** Matt verified on the integrated `main` build (`a6f1288`): Spotify playlist loaded, no problems — the refresh path exercised end-to-end against real Spotify with no regression, confirming 2.2.2 (dedup) / 2.2.3b (form-encoding) / 2.2.3c (Keychain) on the live API. The fresh-login path (2.2.1 re-entrancy, 2.2.3a `state` guard) rests on the unit regressions + standard OAuth on unchanged callback routing — accepted as Resolved without forcing an interactive login: a silent refresh does not exercise the consent round-trip, and that routing is unchanged from the CLEAN.2.1 build Matt already logged in on. `KNOWN_ISSUES` AUDIT-2026-06-09 OAuth items flipped to Resolved. Not pushed (awaits "yes, push"). Remaining Phase 2: CLEAN.2.3 (wire-or-hide dead UI), 2.4 (entitlement review).

---

## [dev-2026-06-14-c] BUG-033 RESOLVED + BUG-050 filed (recorder ≈ doubles CPU — the 99% Matt saw)

Matt validated BUG-033 via Activity Monitor: toggling the debug overlay produces the expected CPU swing (dashboard work present only while the overlay is shown) — the `@Published`→`CurrentValueSubject` decoupling + skip-when-hidden working as designed; the VM retain-cycle half was already unit-proven. **BUG-033 → §Resolved** (fix `f95d645`, integrated `da26a3a`).

The check also showed PhospheneApp at ~99–115% CPU. Per-frame artifact analysis (`2026-06-14T17-58-44Z/features.csv`) traced that to the **always-on session recorder**, not BUG-033: `frame_cpu_ms` mean 15.78 = `renderframe` ~8.6 + `encode` ~7.2 (additive); when the recorder stalled between BUG-039 video-writer deaths, `encode_cpu_ms` → ~0.6 and total CPU **halved to ~9 ms**. Encode is on its own thread, so 60 fps holds (render alone ~52% budget, 98.8% of frames <20 ms) — the cost is sustained CPU/power/heat (~2 cores on the mini), not frame rate. Filed as **BUG-050** (P2, resource-management). Per Matt's call (option A), recording stays on while the session artifacts are in active use; the proper fix (cheaper/off-thread per-frame capture, or default-off gating) is deferred.

**Phase-1 manual gates:** BUG-031/032/033 all Resolved; only **G1** (mid-session output-device swap) remains, pending Matt's reconfigured session this week.

---

## [dev-2026-06-14-d] CLEAN.2.1 — Spotify client secret removed from the build (PKCE Authorization Code is the sole flow)

The bundled `SpotifyClientSecret` (`PhospheneApp/Info.plist:13`, resolved from `Phosphene.xcconfig`'s `$(SPOTIFY_CLIENT_SECRET)`) was the audit's standing distribution-blocker (`KNOWN_ISSUES` AUDIT-2026-06-09) — a secret embedded in a native app is extractable from any shipped binary, and the Authorization Code + PKCE flow a public client uses doesn't need one. Investigation confirmed the secret was read **only** by the engine-side client-credentials path (`DefaultSpotifyTokenProvider`, D-068), never by the user login: `SpotifyOAuthTokenProvider` (D-069) exchanges `client_id` + `code_verifier` with no secret, and `ConnectorPickerView` injects *that* provider into the playlist connector. The client-credentials path was never wired to the Spotify UI, and the RUNBOOK setup never instructed setting a secret (so `makeLive()` already fell through to the `MissingCredentials` sentinel) — i.e. removal is **zero user-facing change**. **Fix:** deleted `SpotifyClientSecret` from `Info.plist` + the `Phosphene.xcconfig` template; removed the `DefaultSpotifyTokenProvider` actor (the secret's only consumer) and simplified `SpotifyWebAPIConnector.makeLive()` to always back with `MissingCredentialsTokenProvider` (the no-arg `PlaylistConnector()` default used by non-Spotify sources — Apple Music / local files unaffected); the `SpotifyTokenProviding` protocol + sentinel stay, with `SpotifyOAuthTokenProvider` (PKCE) the sole token source. Tests: `SpotifyTokenProviderTests` pruned to the sentinel case; the client-credentials `SpotifyIntegrationTests` (public-playlist, `SPOTIFY_INTEGRATION_TESTS=1`) removed — OAuth has no headless replacement. **Credential handling going forward:** a developer needs only `SPOTIFY_CLIENT_ID` in the gitignored `Phosphene.local.xcconfig` — no secret to paste, bundle, or rotate (it was never committed — the tracked xcconfig held an empty placeholder — and no public build shipped). The separate Audio-layer `SpotifyFetcher` (env-var client-credentials, search-only `duration`) was **removed as an immediate follow-up** (2026-06-14, Matt's call): never active in normal runs (its `SPOTIFY_CLIENT_ID`/`SPOTIFY_CLIENT_SECRET` env vars are never set), it returned only redundant `duration`, and its deletion (file + the lone `buildFetcherList()` call site; no tests referenced it) eliminates `SPOTIFY_CLIENT_SECRET` from the codebase **entirely**. Engine builds + 25 Spotify/PlaylistConnector tests green; app `xcodebuild build` **SUCCEEDED**. **Manual E2E confirmed (Matt, 2026-06-14): Spotify login → playlist loads on the integrated `main` build** — OAuth path intact, no regression. Docs: `CAPABILITY_REGISTRY/SESSION.md` + `ARCHITECTURE.md` registries updated (D-068 provider retired), RUNBOOK dual-connector gotcha, `KNOWN_ISSUES` resolved. First Phase 2 increment; CLEAN.2.2 (OAuth correctness), 2.3 (wire-or-hide dead UI), 2.4 (entitlement review) remain.
---

## [dev-2026-06-14-b] BUG-031 + BUG-032 RESOLVED — manual validation via two real sessions

Matt ran validation sessions on the integrated `da26a3a` build. **Session `17-58-44Z` (streaming):** Spotify playback reacted to music — 96.7% of 16,310 recorded frames carried audio; per-stem deviation live (drums/bass/vocals each range >1.5 mid-stream); 2 streaming track-changes + 4 source loads (Spotify → local folder → two single files), each reaching `→ready` with its OWN correct plan; no orphan-hijack, no premature ready, no crash. **Session `17-22-31Z` (local):** stems felt connected across 3 local track-changes. Together these clear the manual gates for **BUG-031** (per-caller stems, connected, no stall/deadlock) and **BUG-032** (lifecycle: cancel→restart + source switches, no hijack) — both moved to `KNOWN_ISSUES.md §Resolved` (fixes `1447612` / `4762114`, integrated `da26a3a`).

A first session (`17-22-31Z` streaming leg) showed dead streaming visuals; analysis traced it to **environmental output routing** — audio went to a silent BT output, so the system tap captured silence (local files are immune, analyzed file-direct). Confirmed three ways: streaming worked with audio present here, the streaming→local transition worked, and the dead session's own log shows `audio signal → silent`. No Phosphene transition bug, and the existing signal-quality indicator (BUG-026's domain) did fire `red: no signal — check output device`.

**Still open (not closed):** **G1/CLEAN.1.5** output-device swap (needs a mid-session swap between two *working* devices — Matt reconfiguring this week) and **BUG-033** app-layer CPU/leaks (needs an Instruments pass). **BUG-012** (MPSGraph crash): zero crashes across both long sessions — retirement candidate, not yet retired. **BUG-039** (video-writer death) hit its 8/8 restart cap this session — active on macOS 26.5 / M2 Pro, flagged for a separate look.

---

## [dev-2026-06-14-a] CLEAN.7.10 — RayIntersector 1000-ray perf assertion made contention-robust (best-of-N)

`RayIntersectorTests.test_rayTrace_1000Rays_under2ms` flaked on the Mac mini during the CLEAN.1 Phase-0 closeout re-run (it had passed 1469/1469 on both integration closeouts; isolated it is 5/5 green, the whole class running in 0.42–0.54 s). Root cause: a **single-sample `Date()` wall-clock assertion around one GPU command-buffer submit**, run inside the ~1469-test parallel suite — a saturated GPU/CPU inflates any one submit past the 2 ms budget. Same flake class as CLEAN.7.9, worse shape (a GPU round-trip is more jitter-prone than a timeout race). Per the deterministic-over-budget-widening rule, the 2 ms gate is **kept, not loosened**: the assertion now takes the **minimum of 8 warm `intersect` samples** — contention can only ADD latency to a submit, never subtract it, so the minimum is the clean estimate of true GPU cost and is robust to a few starved samples. The `measure {}` variance-tracking block above it is unchanged. The ray-intersector path is untouched by CLEAN.1 (last modified in render increment 3.3); test-only, no production delta. (Same Phase-0 session: the TSan stress harness ran **CLEAN — 0 data races** on the Mac mini, dynamically validating the BUG-031/032 fixes.) `KNOWN_ISSUES.md §Pre-existing Flakes` carries the resolved note.

---

## [dev-2026-06-14] CLEAN Phase 1 integrated to `main` + pushed to origin (`da26a3a`)

The committed June Phase-1 scope (CLEAN.1.1–1.7: BUG-031/032 concurrency family, BUG-033 app-layer leaks, G1 device route-change, G7 TSan harness, G8 E2E lifecycle test) is merged from the worktree branch to `main` and pushed to origin as **`da26a3a`** (Matt-authorised push). The branch was merged *into* (not rebased onto) `main` to preserve the many commit hashes cited across the docs; origin had advanced in the interim, so the merge also pulled in **CLEAN.7.9** (the `MetadataPreFetcher` network-timeout flake made deterministic) and **DOC.7** (diagnostics PNG hygiene + LFS rule). Conflict resolution took CLEAN.7.9's deterministic `MetadataPreFetcherTests` wholesale — **this supersedes and removes the 45 s wall-clock band-aid** the CLEAN.1.x closeouts had applied to that same test (deterministic behavioural assertion over budget-widening, per standing guidance) — and combined the two branches' ENGINEERING_PLAN Phase-CLEAN bullets. Final pre-push closeout at `da26a3a` **ALL GREEN**: engine 1469 tests (1 known issue — the pre-existing MemoryReporter `withKnownIssue`, not a failure), app 384, swiftlint 0 of 435, doc-gates 9/9. The four P1 fixes (BUG-031/032/033 + G1) are now **integrated**; the only remaining gate before they flip to Resolved is **Matt's manual validation** — real connect→play→track-change→end→restart concurrency session, Instruments before/after (main-thread CPU + leaked-VM count), and a mid-session output-device swap.

---

## [dev-2026-06-13-f] CLEAN.1.7 — GAP-8: end-to-end session-lifecycle integration test (completes June Phase 1)

New `Integration/SessionLifecycleE2ETests` drives a real `SessionManager` + `SessionPreparer` (fast fakes — no GPU/network) through the entire session lifecycle in one test: connect → prepare → ready → play → track-change → end → restart, plus a cancel-mid-prepare terminal path. Track-change is exercised the way the engine does it — `cache.loadForPlayback(nextTrack)` returns the prepared stems/profile on a boundary. The restart leg uses a *different* playlist and asserts the new session's plan is installed intact, which structurally catches the BUG-032 orphan-hijack class as part of the full cycle (previously only per-VM unit tests and beat-grid wiring tests existed — nothing drove the whole path the orphan lives on). This is the last item in the committed **June Phase-1 scope (CLEAN.1.1–1.7): BUG-031/032 concurrency family, BUG-033 app-layer, G1 device route-change, G7 TSan, G8 E2E** — all landed on the worktree branch. The P1 bug-fixes (031/032/033 + G1) remain **fix-implemented, not Resolved**: they await Matt's manual validations (real concurrency session, Instruments before/after, mid-session device swap) and integration of the branch to `main`. Closeout ALL GREEN.

---

## [dev-2026-06-13-e] CLEAN.1.5 — GAP-1: audio output-device route-change no longer freezes visuals

The system audio tap (`SystemAudioCapture`, a global Core Audio process tap in a private aggregate device) had **no** listener for `kAudioHardwarePropertyDefaultOutputDevice` — so the single most common mid-session event (AirPods connect, monitor unplug, DAC swap) left the tap bound to the now-dead device and the visualizer silently froze. New `DefaultOutputDeviceMonitor` registers a permission-free system-property listener; on a change, `SystemAudioCapture` reinstalls the tap (`performReinstall`: teardown + re-create tap/aggregate/IO-proc against the new default output, replaying the stored `currentMode`). The reinstall is dispatched to a dedicated `reinstallQueue` rather than run from inside the Core Audio listener callback, so the teardown/destroy calls (incl. `cleanup()`, which removes the listener on a create failure) never reenter the property callback. `cleanup()` was split into `teardownTapResources()` (tap only) + monitor-stop + flag-clear. **Tests:** `DefaultOutputDeviceMonitorTests` (5 — registration succeeds without TCC permission, idempotent start, clean/​repeatable stop, restart-after-stop, stable device-ID read) — the listener mechanism is headless-testable; the actual reinstall on a real device swap is **manual validation pending** (no API to change the default output from a unit test). Closeout ALL GREEN.

---

## [dev-2026-06-13-d] CLEAN.1.4 — BUG-033 fixed: dashboard snapshot decoupled off the 60 Hz tree invalidation; ViewModel retain cycles broken

The app-layer P1 (independent of the concurrency family). **(1) 60 Hz whole-tree invalidation:** the per-rendered-frame dashboard snapshot was `@Published` on `VisualizerEngine`, which is `@EnvironmentObject` across the tree — so every frame fired `objectWillChange` and re-evaluated the App body + `ContentView.playbackView` + the whole `PlaybackView` diff at ~60 Hz throughout playback. It now flows through a dedicated `CurrentValueSubject` (`dashboardSnapshotSubject`) that only `DashboardOverlayViewModel` subscribes to (and throttles to ~30 Hz), so the engine no longer invalidates the tree per frame; `publishDashboardSnapshot` also skips entirely when the overlay is hidden (the default — PlaybackView pushes its local `showDebug` into `engine.dashboardOverlayVisible`). **(2) ViewModel leaks:** `SessionStateViewModel` and `PlaybackChromeViewModel` used `assign(to: \.x, on: self)` with the cancellable stored on `self.cancellables` — `Subscribers.Assign` retains its target → retain cycle → the VMs never deallocated (`PlaybackChromeViewModel.deinit`, which cancels `hideTask`, never ran). Both are now `sink { [weak self] }`. **Tests:** `deallocates_noRetainCycle` weak-ref-nils-after-teardown regression tests in both VM suites (red pre-fix, green post-fix). **Deferred:** the audit's third factor (PhospheneApp re-constructing the VM per scene-body eval) is neutralised by the above — the leak is closed, body evals are now rare, and `ContentView` already `@StateObject`s the VM (discards later instances, which now dealloc); the construct-once `@StateObject` conversion is a deferred micro-optimisation (highest-risk SwiftUI-init change, least remaining benefit). **Fix-implemented, not Resolved** — needs Matt's manual Instruments before/after (main-thread CPU drop; zero leaked VMs) + integration to main. Closeout ALL GREEN.

---

## [dev-2026-06-13-c] CLEAN.1.6 — TSan + concurrency stress harness (GAP-7): BUG-031/032 fixes validated race-free

Dynamic concurrency validation for the BUG-031/032 fixes — static review can't prove the absence of races; ThreadSanitizer can. New `Scripts/tsan_stress.sh` runs the concurrency + session-lifecycle stress/regression tests under `swift test --sanitize=thread`, and a new `ConcurrencyStressTests` (env-gated `PHOSPHENE_STRESS=1`, opt-in so the normal closeout stays light) hammers the two race surfaces: (1) overlapping live + prep `separate()` on one shared `StemSeparator` (BUG-031), and (2) rapid session start → end/cancel churn with preparation in flight (BUG-032). **Result: TSAN CLEAN — 0 data races** across the harness + the existing concurrency/lifecycle regression tests — proving CLEAN.1.2/1.3 removed the races rather than moving them. Notable: TSan builds and runs cleanly against the real Metal/MPSGraph `StemSeparator` with no framework false positives, so no suppressions file is needed. Always-on regression coverage stays in `StemSeparatorConcurrencyTests` + `SessionLifecycleGenerationTests` + `SessionRecoverySingleFlightTests`; this harness is the on-demand TSan layer. KNOWN_ISSUES BUG-031/032 TSan-validation boxes checked (manual-validation + integration-to-main still gate Resolved). Closeout ALL GREEN.

---

## [dev-2026-06-13-b] CLEAN.1.2 + 1.3 — BUG-031/032 concurrency family fixed (lock + return-by-value; session-generation guard)

The fix unit for the session+stem concurrency family (strategy **A**, Matt-approved). **CLEAN.1.2 (BUG-031):** `StemSeparator.separate()` now holds `lock` across the entire input→predict→output critical section on the single shared instance (only `StemModelEngine.predict()` was locked before), and returns stems **by value** via `StemSeparationResult.stemWaveforms` — the two callers (`VisualizerEngine+Stems`, `SessionPreparer+Analysis`) read the result, never the shared `stemBuffers`. Together these close both halves of the race (the internal predict-buffer interleave and the caller-side shared-buffer read). `stemBuffers` is retained only as a diagnostic/test accessor; the CLEAN.1.1 ownership probe now sits inside the lock as a regression sentinel; the Step-6 output read + `buildResult` live in `StemSeparator+ModelIO.swift` for the length budget. **CLEAN.1.3 (BUG-032):** added a per-instance `streamingSessionGen` (twin of the LF path's `localFileSessionGen`) — the prep-completion closure bails when a newer boundary advanced it, so an orphaned task can't hijack the next session; `endSession()` now cancels the prep task + status subscription (mirrors `cancel()`); `resumeFailedNetworkTracks` awaits the in-flight loop before starting recovery (single-flight — no second `_runPreparation` over the shared separator); both `startSession` variants mutate the published source only after the state guard. **Tests:** `StemSeparatorConcurrencyTests` (threshold-free silence-vs-loud cross-caller discriminator on one shared instance), `SessionLifecycleGenerationTests` (end-then-restart guard + rejected-startSession source order), `SessionRecoverySingleFlightTests` (probe `maxRunPreparationInFlight == 1`). Fallout from the by-value return: three inline test doubles (`StubStemSeparator`, `StubSeparator`, `InstantStemSeparator`) updated to mirror their pre-filled buffers into `stemWaveforms`. Closeout ALL GREEN. **Both bugs are fix-implemented but NOT yet Resolved — they need Matt's manual concurrency/lifecycle validation (real connect→play→track-change→end→restart session) + integration to main.** Plausibly retires BUG-012 (MPSGraph crash) — to be confirmed by the manual session + crash-watch.

---

## [dev-2026-06-13-a] CLEAN.1.1 — BUG-031/032 concurrency family instrumented + root cause confirmed (commit & stop)

First Phase-1 increment: the **instrumentation + diagnosis** step of the P1 multi-increment protocol for the session+stem concurrency family (no fix code — fix is CLEAN.1.2/1.3). **Confirmed one root cause** spanning both bugs: `VisualizerEngine.swift:737` builds a single `StemSeparator` and shares it between the live `stemQueue` path (`:771`) and the session-prep path (`:784` → `SessionPreparer`, driven from a `Task.detached`), and `separate()` runs its input-buffer write and output-buffer read **outside** the only lock (`StemModelEngine.predict()`), so two concurrent calls interleave and one returns the other's stems (**BUG-031**); separately, `endSession()` orphans the prep task (no cancel, unlike `cancel()`), `resumeFailedNetworkTracks` spawns a second `_runPreparation` loop over that same separator, and both `startSession` variants mutate the published source before the state guard (**BUG-032**). New `ConcurrencyAuditProbe` (`Sources/Shared/ConcurrencyAuditProbe.swift`, log category `concurrency-audit`, pure observability — mirrors `BUG012Probe`) exposes all of it at runtime: `[BUG-031][ALARM]` on concurrent `separate()` + input-ownership clobber; `[BUG-032][ALARM]` on stale/orphaned prep completion (a session-generation counter, *logged only* — the guard is the 1.3 fix), double `_runPreparation` loop, and orphaning `endSession()`. The Step-6 output-read loop moved to `StemSeparator+ModelIO.swift` to hold the file/function length budget after instrumentation. `ConcurrencyAuditProbeTests` (XCTest, 9 green, no GPU) proves the probe detects each modeled race; the live red→green regression tests land with the fixes. Root cause + instrumentation map documented in KNOWN_ISSUES BUG-031/032; BUG-012 cross-referenced as a candidate retiree. Closeout ALL GREEN. **Next: bring Matt the CLEAN.1.2 lock-strategy decision (extend the lock over input→predict→output vs. per-path separator instance) before implementing.**

---

## [dev-2026-06-13] CLEAN.0 — 2026-06-13 full-system audit landed; baseline reconciled; BUG-030 integrated to main

A 17-lane multi-agent audit of the codebase + docs (134 verified findings across stability / performance / capability / process, plus 16 verified coverage gaps the lanes missed) landed at [`docs/diagnostics/CODE_AUDIT_2026-06-13.md`](diagnostics/CODE_AUDIT_2026-06-13.md), with a phased **CLEAN** backlog (Phases 0–8). Approved June-30 scope (Matt): Phases 0, 1, 2, 5 + elevated gaps G1 (audio device route-change), G2 (sample-rate contract), G7/G8 (TSan + E2E lifecycle tests), G9 (photosensitivity clamp); Phases 3–4 stretch; 6 / bulk-7 / 8 after June. **Phase 0 baseline reconcile:** `main` confirmed green — the 13 fresh-worktree engine-test failures were *all* the single gitignored tempo fixture `love_rehab.m4a` (failing loud per the no-silent-skip rule, not a regression), restored via `Scripts/fetch_tempo_fixtures.sh`; this validated CLEAN.5.2 (fresh-worktree fixtures) and the CLEAN.5.3 pipe-masks-`swift test`-exit-code closeout-honesty gap live. **BUG-030** dup-track-crash fix integrated to main — `ba4e1cae`, cherry-pick of the stranded `679363a9` from `claude/dreamy-bell-23528b` — see KNOWN_ISSUES §Resolved.
---

## [dev-2026-06-13-a] DOC.7 — `docs/diagnostics` image-artifact hygiene; preventive LFS rule

`docs/diagnostics/V9_session_4_5b_phase1/` was 29 plain-blob PNGs (~49 MB — almost the entire 50 MB `docs/diagnostics` tree), spent side-by-side fixture renders from the Ferrofluid Ocean Phase-1 session Matt closed on 2026-05-14 ("ready to call this a pass"). A repo sweep found them referenced only in history docs (`ENGINEERING_PLAN_HISTORY.md`, the archived `RELEASE_NOTES_DEV_2026-05.md`) — no active doc, no Swift/test/script, no `DocIntegrityTests` budget. Matt's pick was prune + preventive rule: the 29 PNGs are `git rm`'d (≈49 MB off every working-tree checkout and worktree; still in history at `7dc41106..8862d6f2`, restorable via `git show`/`git checkout`), a tombstone `README.md` at the old path keeps the two history-doc references resolvable, and `.gitattributes` now LFS-tracks `docs/diagnostics/**/*.{png,jpg}` (both direct and nested forms) so future contact sheets never bloat the pack as plain blobs. Asset + docs only, zero code delta. **Caveat surfaced for follow-up:** the blobs persist in `.git` history, so a fresh *clone* is unchanged until a `git filter-repo` rewrite + force-push — a separate, approval-gated operation, not done here.
---

## [dev-2026-06-13-b] CLEAN.7.9 — `MetadataPreFetcher` network-timeout flake made deterministic (test-infra)

The `MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget` wall-clock flake — long-tracked in `KNOWN_ISSUES.md §Pre-existing Flakes`, resurfaced at 16.1 s / 22.8 s during the CLEAN.1.x closeouts — is rewritten deterministic. Root cause: it timed a 1 s-timeout-vs-10 s-slow-fetcher race and asserted `elapsed < budget`, but under the ~1460-test parallel suite the cooperative thread pool delays the continuations resuming inside `prefetch`, so the *measured* wall-clock balloons even though the timeout itself fires correctly; the budget had ratcheted 3 s → 8.25 → 15 → 45 s across prior sessions without ever converging (a band-aid, never a fix). The replacement drops elapsed-time entirely and asserts behaviour: the merged profile carries the fast fetcher's `energy: 0.5` but **not** the slow fetcher's `bpm: 999` (excluded by the 1 s timeout). That outcome depends only on the 1 s-vs-10 s ordering — the 1 s timer's continuation is enqueued ~9 s before the 10 s one, and contention delays both without inverting them — so it cannot flake under pool contention. Renamed `fetch_networkTimeout_returnsFastResultNotSlow`. Proven non-vacuous by an adversarial A/B: widening the timeout to 30 s (so the slow result leaks through) trapped on the headline assertion (`profile?.bpm → 999.0` fails `== nil`, a ~10 s block — not a hang) and reverted clean to green. Test-only, zero production delta — the `MetadataPreFetcher` source is untouched; a broken timeout still fails the test. Removed from `KNOWN_ISSUES.md §Pre-existing Flakes`; the `DEFECT_TAXONOMY.md` P2 example and the `CAPABILITY_REGISTRY/AUDIO.md` CA-Audio note updated to the resolved state. Early-pulled from Phase 7 (test-infra); decoupled from the BUG-031/032 CLEAN.1 concurrency work it surfaced alongside. Full `MetadataPreFetcher` suite 10/10 green (the rewritten test 1.06 s in isolation).
---

## [dev-2026-06-12-a] DOC.6 — doc rotation mechanized; budgets gated (D-162)

The pruning-pass prose convention converted to mechanism per D-161 rule 3 (it had not executed since mid-May; measured 2026-06-12: EP 660 KB at ~53 % completed-work narrative, KNOWN_ISSUES 386 KB at 71 % resolved-history, release notes 696 KB unrotated). New `Scripts/rotate_docs.sh` performs the three rotations deterministically and idempotently (verbatim moves; unparseable entries reported, never guessed); first run + manual triage + closed-phase rotation brought EP to ~414 KB, KNOWN_ISSUES to ~143 KB, and this file to current-month-only. DECISIONS gained §Index, KNOWN_ISSUES gained §Open Index; DocIntegrityTests gained five gates (EP narrative age, §Resolved ≤ 50 KB, pre-current-month release notes ≤ 50 KB, index completeness ×2 — all canary-proven red-then-green) and the BUG-continuity gate now spans KNOWN_ISSUES_HISTORY.md; `closeout_evidence.sh` runs the doc gates as Step 4. CLAUDE.md: pruning section mechanized, doc-reading discipline rule, release-notes prepend-only rule (net token-negative, 6,909 est.).

---

## [dev-2026-06-12] BUG-034 closed — D-057 step multiplier owns `sceneParamsB.z`; ray-march fixtures march the live 128-step budget; visual harness now production-parity

The A6 audit finding: `makeSceneUniforms()` packed `sceneAmbient` into `sceneParamsB.z`, which the G-buffer preamble reads as the D-057 frame-budget step multiplier — every ray-march fixture (golden hashes, RENDER_VISUAL contact sheets, certification evidence) rendered at 32 steps vs live's 128. Fix: the multiplier owns the slot end-to-end (`makeSceneUniforms()` + `SceneUniforms()` default it to 1.0; live per-frame writes unchanged — D-057 adaptive semantics untouched); `scene_ambient` removed as dead config (slot audit proved no shader on any path ever consumed it); the packing contract is now a slot-map table at the `SceneUniforms` definition, pinned by `StepBudgetParityTests` (parity derived through both code paths + default guard, A/B-proven red on the pre-fix packing). Matt's M7-lite review of the first before/after pairs flagged the deeper FA #66 gap — the deferred ray-march visual harness bound none of noise textures / IBL / SSGI / post-process / Ferrofluid height field — so the harness was upgraded to production-parity bindings (approved scope extension; all five ray-march presets now render representative contact sheets, with a `RENDER_STEP_MULT` A/B hook). Goldens regenerated on approval: Kinetic Sculpture (lattice resolves deeper) + Volumetric Lithograph (terrain reaches the true horizon, the "sky holes" were budget exhaustion); Glass Brutalist within tolerance (kept); Lumen Mosaic byte-identical (converges inside 32 steps). Certified presets: Lumen Mosaic provably unaffected; Ferrofluid Ocean accepted as live-path-unchanged (Matt, 2026-06-12) — no re-certification.

---

## [dev-2026-06-11-i] BUG-049 closed — armed-path validation via fixture-generated real captures; `FixtureSessionCaptureGenerator` added

The dev-2026-06-11-h fix shipped with its armed path unvalidated (no real capture left on the machine). New `FixtureSessionCaptureGenerator` (engine test target, env-gated `PHOSPHENE_GEN_SESSION_DIR`, skips in normal runs) closes that dependency permanently: it replays the vendored tempo fixtures (`love_rehab` / `so_what` / `there_there`, 30 s) through the production pipeline — ffmpeg decode → `StemSeparator` (MPSGraph, 10 s chunks) → `StemAnalyzer` per 1024-sample hop → `SessionRecorder.csvRow` — and writes real stems.csv session captures (FA #27-compliant: real music, production chain, nothing hand-authored; ~7 s for all three). With the three `fixturegen-*` captures placed in `~/Documents/phosphene_sessions` (left in place; regenerate any time), the colour-freeze gate ARMED (`picked fixturegen-so_what`, bass→drums switch) and SkeinCanvasHold ran 21/21 green alongside the recorder stubs; the adversarial A/B (freeze deliberately broken in `skeinLineLookupAt` — every τ takes the latest breakpoint colour, the literal Skein.4.1 defect) turned the gate RED on its headline assertion (PRE-switch X=0 Y=61) and reverted clean to green (X=61 Y=0); the empty-session-dir leg skips loudly and stays green. All BUG-049 verification criteria met; KNOWN_ISSUES banner updated to RESOLVED.

---

## [dev-2026-06-11-h] BUG-049 — Skein colour-freeze gate: feasibility-aware switch selection; session-set content can no longer red the suite

The colour-freeze cert gate picked its dominant-stem switch on decisiveness alone and only discovered at sampling time that the switch was un-sample-able (windows < 3·dτ inside the pour's reign / probe extent) — `Issue.record` red on data, not code, whenever a new capture changed the pick (the 19:49 closeout battery hit exactly this). Fix (test-infrastructure only, commit `a6899893`): a CPU-only dry run (`switchSampleInfeasibility`, exact tick replay — no GPU dependence) now vets every candidate during selection, falling back in decisiveness order to the most decisive switch that is ALSO sample-able; the in-run guard remains as a dry-run/live parity safety net. No-candidate session sets (e.g. all header-only stubs) skip LOUDLY instead of recording an Issue, and the Skein.3 real-stem routing gate gained the same scan-all fallback (it hard-depended on the single largest session — red when that's a 602-byte stub). Colour-freeze assertions unchanged. **Armed-path validation pending:** the only real capture (`2026-06-11T13-10-42Z`) vanished from `~/Documents/phosphene_sessions` before the fix session — the next real listening session should show `[skein_colorfreeze] picked …` and green; see the BUG-049 banner in KNOWN_ISSUES.

---

## [dev-2026-06-11-g] REVIEW.3 + BUG-048 — closeout evidence script; canonical app-test invocation un-broken

**REVIEW.3:** `Scripts/closeout_evidence.sh` replaces hand-transcribed closeout test claims (the CSP.3.4 false-green class) with a script-generated evidence block pasted verbatim — header (timestamp/host/commit/tree), per-step verbatim tool summaries + exit codes + failing-test identifiers, `EVIDENCE: ALL GREEN` / `FAILURES PRESENT` verdict; byte-identical copy at `~/.phosphene/last_closeout_evidence.md` for paste-diff verification. Canary-verified un-greenwashable (deliberate failing test surfaced verbatim, then deleted). CLAUDE.md closeout item 2 now requires the block.

**BUG-048 (found by the script's first three runs):** the app scheme's test action had included the engine test bundle since U.1; under xcodebuild's runner context it fails on environment, not code (ffmpeg subprocess + repo file reads denied, audio tests insta-fail, only ~440/1439 tests load) — so the canonical `xcodebuild test` was permanently red in every terminal. Fixed by removing the engine bundle from the test action (engine suite's canonical runner stays `swift test`); `xcodebuild test` now runs the app suite only — 382 green, `** TEST SUCCEEDED **`. Regression-locked by `SchemeTestActionRegressionTests`.

---

## [dev-2026-06-11-f] REVIEW.1 + REVIEW.2 — transcript-mining audit + session-lifecycle churn regression net

**REVIEW.1 (audit-only):** all 108 retained session transcripts (2026-05-08 → 2026-06-11) mined for correction patterns. Headlines: adjusted correction load ~5 % of human turns, flat-to-falling (NOT rising); genuine corrections 86 % live-runtime defects (app-lifecycle hangs, fixture/live parity) — zero reference-skip/spec-drift classifications in the reviewed set (with stated under-sampling caveats); the heaviest preset sessions burned 85 %+ of output tokens before any visual artifact. Findings + rule-usage table (the RB.1 input) live OUTSIDE the repo at `~/phosphene_session_mining/REVIEW1_FINDINGS.md` (private conversation content; public repo). Repo footprint: ENGINEERING_PLAN rows only.

**REVIEW.2 (Matt's option-1 pick):** `SessionLifecycleChurnTests` — six serialized engine tests churning the REAL AVFoundation path (router start/stop at varied dwells, completion-callback-vs-stop on a looping 0.25 s real-music excerpt = the exact BUG-021 ABBA surface, onFileEnded queue advances, transport-hammer vs stop/start, deinit-while-playing, concurrent double-start), each step under a 5 s detached-thread watchdog so a hang recurrence fails with a named step instead of beachballing the suite. All 6 green; full engine suite 1439 tests with one parallel-load timing squeeze on the SoakTestHarness cancel bound (green in isolation, 0.7 s vs 15 s bound — widen if it recurs).

---

## [dev-2026-06-11-e] FBS.S5d — BUG-047: the aurora palette-march root cause (orbit speed × elapsed-TOTAL) found and fixed

Matt's read of `2026-06-11T13-10-42Z`: Stage 2 works as designed, but "the aurora is shifting very quickly for So What… the color of the ocean was changing every 1-2 seconds… it marches through the palette." Two wrong attributions burned in-session (mood-tint; curtain-contrast — an R−B-metric artifact; Matt's pushback corrected both) before the per-frame azimuth trajectory exposed the real defect: **the curtain orbit multiplied arousal-speed into the entire elapsed audio-time total**, so every per-second mood wobble retroactively rescaled history — the palette teleported across colour stops second-by-second, worse the longer the track played. Fix: integrate (`auroraOrbitStep`, `azimuth += speed × Δtime`; `StemFeatures.auroraOrbitAzimuth` float 47); round-61's tuned pace preserved verbatim. **Pixel proof:** per-second hue swing on So What 56–80 s: **94.7° → 3.3°** (legacy vs integrated arm); Love Rehab calm-and-alive at 4.9°. New wrap-aware hue-angle metric in the forensics harness (the R−B metric's green↔purple blindness is what misled the session). `AuroraOrbitDriverTests` ×3. Engine suite green (documented ProgressiveReadiness flake only — passes isolated), app build OK, lint 0. **Awaiting Matt's live read.** The option-2 brightness-split from earlier in the session is PARKED — re-evaluate only if the aurora still feels restless after this fix.

---

## [dev-2026-06-11-d] DOC.4.1 — doc referential-integrity gate (the D-155 corruption class is now test-caught)

Follow-up to the DOC.4 integrity finds, at Matt's "address ASAP". A full-history damage sweep (every doc-touching commit since DOC.3) confirmed **D-155 was the only real casualty** — every other header disappearance was a legitimate relocation or the D-147→D-148 renumber. The durable fix is `DocIntegrityTests` (3 gates, ~0.25 s, in the engine suite every increment runs): D-number continuity + uniqueness across DECISIONS/HISTORY (amendment-header convention respected), BUG continuity + uniqueness in KNOWN_ISSUES (dotted sub-entries excluded, BUG-10 allowlisted), and citation resolution for every `D-###`/`FA #` across CLAUDE.md, sources, tests, and the docs tree. A/B-validated against simulated D-155-deletion and D-086-duplication — both trip with messages that name the fix. A parallel session that eats a neighbouring entry now fails the battery instead of surviving until someone greps.

---

## [dev-2026-06-11-c] DOC.4 — pruning pass (first since the 2026-05-13 refactor) + two doc-integrity finds

The four protocol passes, four weeks / 775 commits overdue. CLAUDE.md 542 → 494 lines; nothing deleted — everything moved with provenance and the gap tables extended, every surviving `FA #` / `D-###` cross-reference grep-verified to resolve.

- **Failed Approaches:** CoreML gotchas #14/#20 → graveyard (CoreML unused per D-009, verified); shader-craft gotchas #34–#38/#40 → SHADER_CRAFT §13 (most were already duplicated there verbatim — §13 is now canonical). ~50 entries deliberately KEPT, incl. the beat-detection dead-ends the queued D-145 beat-sync project will need.
- **Decisions:** a mechanical citation graph (921 files + memory + open issues) showed 154/165 entries still cited — the old ~60-active estimate was wrong, so the cut is the verified subset: D-013/D-031/D-046 (shipped + uncited), D-120 (reverted; lessons live as FA #59/#60), and a D-086 dedupe (it sat in BOTH files since the original half-landed move). The Phase-MD-bloc REVISIT banner that DOC.0 planned finally landed, updated with the since-arrived empirical evidence.
- **CLAUDE.md sections:** Cold-Start Phase Contract condensed to the operative contract (full history → BEAT_SYNC.md addendum); the 11 Arachne-specific do-nots → ARACHNE_V8_DESIGN.md; Module-Map per-preset histories (Arachne, LumenMosaic) split to their design docs per borderline-call B.
- **Integrity finds, both pre-existing:** the parallel FBS.S5c commit (`5ac5ad90`) had accidentally deleted the entire **D-155** entry while editing the adjacent D-154 amendment — restored verbatim from `5ac5ad90~1`; and **D-145** was number-reserved at the NB renumbering, cited everywhere, but never actually written — retroactive stub filed.
- **Reported for the next pass (Matt's call):** the deeper ~30-entry decisions cut needs a rule that narrative/provenance citations don't count as keep-signals; without it the citation graph correctly keeps nearly everything.
- Battery green post-pass (engine 1430/1430, app tests succeeded, lint 0 — docs-only; zero test movement).

---

## [dev-2026-06-11-b] Skein.6 — ✅ CERTIFIED (Matt M7 PASS) + BUG-046 fixed pre-flip

**Matt's M7 verdict (session `2026-06-11T01-56-22Z`, streaming audit catalog): "It looks great. Ready to certify."** The ≥5-track + local-file bar was met cumulatively with the 2026-06-10 approved sessions (incl. the BUG-044 wipe verify). `certified: true` flipped; Skein is the **first `painterly`-family certified preset** (D-159). Full battery green post-flip: engine 1430/1430, app build + tests, SwiftLint strict 0.

**BUG-046, found in the pre-flip session review and fixed at Matt's direction ("If anything looks concerning, let's fix it before we certify").** The session's features.csv falsified the cert premise "Skein's structure sub-feature is conf-gated to zero on BUG-042's junk": on busy streaming material the parked note-scale detector defect fires boundaries every ~1.7 s **at confidence 0.78–0.95** — the gate wide open — so the flurry pulse ran permanently re-armed (≈1.6–2.2× the Matt-tuned spatter rate) and boundary-forced pours chopped at ~1–1.7 s (the rejected "lines too short" character), on streaming only (local files keep the detector quiet → the tuned look). Matt's pick of three presented options: a **10 wall-second boundary-spacing guard** (`SkeinState.minSectionSpacingS`; wall, not painter τ — τ runs 1.5–2× wall on busy music). Real section changes (15–60 s apart) pass untouched; harmless after the eventual BUG-042 detector fix. A/B-validated gate `test_structure_boundarySpacingGuard`: machine-gun replay 16→4 pour breaks / 1650→1250 spawns (both asserts trip without the guard); the sparse real boundary still lands. BUG-042 itself stays open/parked.

**Soak verdict (completing the entry below):** the 2-hour canvas soak PASSES — byte-perfect RGBA hold (0 px) across the settled 89-minute silence window; painting resumes; never-white holds; 8-bit confirmed, no 16-bit fallback. Run 1 surfaced two harness assumption bugs (baseline taken before the designed EMA silence-settle; an "unreachable corner" that flicks legitimately reach at soak scale) — fixed in the harness, documented in the test.

**Next:** the pruning pass (overdue since DOC.3 2026-05-13) is the next increment.

---

## [dev-2026-06-10-g] Skein.6 — certification gates landed (D-159); awaiting Matt's M7 *(slug repaired from a parallel-session `-f` collision)*

All automated cert gates for Skein are in, green, and calibrated against the approved sessions; no behavioural or tuning change (the 5.4 look is untouched). `certified` stays `false` until Matt's M7 verdict (≥5 streaming tracks + a local file, from the main build).

- **Coverage bound — Matt's decision.** Measured through the live dispatch path on the approved sessions: the painting reaches ~80 % of the canvas at 43 s and plateaus ≈ 87–90 % on a full track (live-video cross-check confirms parity). Matt chose to keep the approved density; §5.7's pre-implementation "ends 60–80 %" band is retired for **never-solid / never-near-empty** (`test_cert_coverageBound`, 180 s real-stem run @ 600×400 — coverage fraction is resolution-dependent via the droplet AA radius floor: same run reads 94.7 % at 200×200 vs 80.2 % at 900×600; any future coverage number must state its render size).
- **Determinism (§5.7 headline)** formalised as dHash ≤ 8 across two same-seed live-path runs (byte-identity stays the stronger assert); full-track evidence: 2×10,800 frames, pixel-diff 0, hamming 0. **Seed ratified as FNV-1a `title|artist`** — the design doc's SHA-256 wording amended (D-159), not the code: rewiring would silently change every approved painting.
- **§5.5 soak** = `test_cert_soak_twoHourCanvasHold` (`SKEIN_SOAK=1`): 432,000 frames (2 simulated hours) through the live mv_warp path — 15 min real stems / 90 min silence (whole-canvas RGBA byte-identity) / 15 min real stems. The generic `SoakTestHarness` is the headless audio-path harness and cannot observe the canvas; the gate runs pixels instead.
- **Golden dHash entry** for Skein in `PresetRegressionTests` (three fixtures identical — static ground, the Nimbus pattern).
- **`family: "painterly"`** + the `PresetCategory.painterly` case (the D-142(c) deferred engine touch; blast radius audited: enum + displayName + count test + sidecar, UI iterates `allCases`). **`rubric_profile: lightweight` ratified** (D-064 precedent; the L2 heuristic false-negative — CPU-side deviation routing — documented in `FidelityRubricTests`).
- Doc write-backs: `SKEIN_DESIGN.md §1/§5.7` amendments, skein README rubric-tension resolution + seed wording, `SKEIN_PLAN.md` rows, D-159.
- **Pruning-pass cadence has fired** (no pass since the 2026-05-13 DOC.3 refactor): the pruning pass is the next increment after cert.

---

## [dev-2026-06-11-b] FBS.S6 — Stage 2 lands: punch height follows passage loudness (D-160)

The last designed piece of the FBS kickoff. The beat-punch (and the opening heave) now scale with how loud the passage actually is: So What's bass+piano intro punches at ~40 % height, the band sections at full; tracks that open hot (Love Rehab, Pyramid) keep full height from the start; true silence still produces nothing (existing gate). The beat keeps the timing — energy sets ONLY the size (kickoff §Stage 2 rule). Signal = smoothed total stem energy (measured to survive the AGC; the band-energy sum is flat across So What's whole arc). One measured course-correction during the build: a fast-rise envelope peak-followed jazz's bursty stems (intro read 0.67 instead of 0.40) — symmetric τ 2.5 s tracks the passage mean. Gates: real-fixture replay + live-path pixel A/B (quiet 20.6 vs loud 48.7 luma punch effect) + forensics `punch-height` arm (quiet-intro flash steps 3 → 1 vs fixed height). Engine 1430/0, app build OK, lint 0. **Awaiting Matt's live read** (the "how gentle is gentle" floor is his dial).

---

## [dev-2026-06-11] FBS.S5c — Matt's S5b read: "Looks great"; the FFO beat-irregularity ban RETIRED (D-154 amendment)

S5b validated live (session `2026-06-11T01-56-22Z`, FFO + Skein testing; FFO scope here). Early handoffs measured working: Love Rehab 9.8 s, So What 8.7 s, **Pyramid Song 6.1 s** — and that's the headline: **the live tracker LOCKED on Pyramid at 5.4 s**, the ban's canonical catch, and Matt ruled *"Remove the FFO ban for Pyramid Song - it looks and moves great!"* Offered retire-vs-soften; Matt picked **retire entirely**: `requires_regular_beat` removed from FFO's sidecar (no production preset declares it now); the mechanism + the `beatIrregular` signal stay for diagnostics/future presets; `test_realFFOSidecar_doesNotDeclareRequiresRegularBeat` pins the retirement. The flag's failure mode is now understood: it condemned tracks where the *drums-stem estimate* disagreed with the grid — but on Pyramid the 70 BPM grid FFO actually uses was right. Engine 1429/0, app build OK, lint 0.

---

## [dev-2026-06-10-f] FBS.S5b — Matt's read: hue fix CONFIRMED (79 → 13 events); residual = the global heave itself; his pick C+A built (D-158 amendment)

Matt's live read of `2026-06-10T20-26-37Z`: flashing "mostly gone," heave visible, **but the opening 10 s lost the sync feeling**. Census + ablation on the new session (which carries the new pulse diagnostic columns): the 13 residual events = 2 track-change cuts + 3 unreproducible one-frame blips (suspected video-encode) + the rest **the global bridge heave itself** (pulse OFF → 0; aurora/hue/light → unchanged) — the flashing and the unpolished-opening feel are ONE mechanism. Diagnosed → 3 options + recommendation → Matt picked **C + A**:

- **C:** aurora intensity τ back to 0.45/1.2 s (the per-drum-hit shimmer returns — it was flash-safe all along; the HUE stays slow at τ 3 s, which was the actual flasher).
- **A:** early handoff — a LOCKED drift tracker opens the handoff window at 4 s (`handoffEarliestS`) instead of 10; unlocked keeps 10 s. On the read session all five tracks locked at te 7.0–8.5 s → punches arrive ~2–3 s sooner, shrinking the loosely-synced heave window.

Gates: `test_earlyHandoff_firesSoonAfter4s_whenTrackerLocked` (real-session replay); forensics re-renders flash-neutral post-revert. Engine 1429/0, app build OK, lint 0. **Awaiting Matt's next live read.**

---

## [dev-2026-06-10-e] FBS.S5 — the flash hunt closes (the hue route, proven then fixed) + Matt's three S4 directives (D-158, BUG-045)

**The proof first (the S5 rule: pixels, not input correlation).** The S4 replica-gap finding resolved exactly as hypothesized: adding the never-replicated `vocalsPitchHz`/`vocalsPitchConfidence` fields to the flash-forensics harness made the replica reproduce the remaining flashes (So What 31–41: 1 → 13 steps; Lotus 45–51: 0 → 15), and the new `aurora-hue` ablation arm (zeroing only those two fields) killed them (1 / 0). Mechanism in the recorded data: pitch confidence flaps across the hue gate ~9×/s, snapping the aurora hue between palette stops across the whole mirrored sky. Filed + resolved as **BUG-045**.

**Matt's three directives (S4 read), implemented:**
1. **Aurora transitions slow to 8–10 s** — hue now computed CPU-side (`auroraHueStep`, τ ≈ 3 s EMA → `StemFeatures.auroraPalettePhase` float 45) which kills the strobe by design; intensity rise/fall τ 0.45/1.2 → 2.7/3.3 s (a slow swell following the drum-energy arc). The Matt-tuned orbit hue rotation (~8–12 s between stops) is untouched.
2. **Bridge heave back to GLOBAL** — `BeatPulseClock.regionalBlend01` (FV float 43): 0 on the bridge (whole-ocean heave, visible again), ramping to 1 over one 4-beat span post-handoff.
3. **Regional punches stay** post-handoff (D-157 unchanged in steady state).

**Acceptance:** four windows of `2026-06-10T19-13-14Z` re-rendered → 1/0/1/0 flash steps with localized punch motion preserved (blocks ~45–63); live-path A/B: bridge punch |δ| 25.3 luma at the heave, 0.0 at rest. New gates: `AuroraHueDriverTests` (3), `test_regionalBlend_zeroOnBridge_rampsToOneAfterHandoff` (real-session replay). `features.csv` gains trailing `pulse_beat_index`/`pulse_regional_blend01`. Engine suite + app build + lint per the closeout. **Awaiting Matt's live read.** Queued behind it: Stage 2 energy-scaled punch heights (So What intro), BUG-043 instrumentation, the dev=35 anomaly.

---

## [dev-2026-06-10-d] Skein.5.4 — two painting techniques: pour drips vs independent flicks (✅ Matt eyeball-gate APPROVED ×3 sessions; merged to local main `befb406b` 2026-06-10)

**Round-2 (Matt's live read, session `2026-06-10T19-28-50Z`):** spatter rate −41 % (`onsetRefractory` 0.14 → 0.26; "slow the speed of spatters by 40–50 %", confirmed as rate not size) and new pour lines start +13 % more often (`minPourTau` 3.0 → 2.65). Early fill at 5 s: 37 % → 25 % of canvas. The same listen surfaced **BUG-044** (local-file next/prev/EOF never wiped the Skein canvas — the §1.5 wipe was wired only on the streaming path since Skein.3; trivial-collapsed P2): the per-track preset reset (Nimbus settle + Skein wipe/reseed) is now the shared `resetPerTrackPresetState()` called from BOTH track-change paths, regression-locked by `TrackChangePresetResetRegressionTests`, with a `WIRING:` breadcrumb per LF advance for session-artifact verification.

Matt's craft distinction, built to the approved spec: the pour and the flick are different techniques. The pour now sheds round ragged **drips** close beside the line at a rate and weight that follow the pour's volume (heavy pour ≈ a drop every 1–3 s, thin filament ≈ none), in the pour's colour. The **flick** fires exactly when today's spray fired (emission timing unchanged; nothing beat-locked) but lands anywhere on the canvas at least 0.20 from the painter, with its own throw angle, and real Pollock anatomy: a lobed impact blot, one-to-three flung tapering threads ending in terminal droplets, and a power-law satellite halo (~20:1 big-to-dust — the old confetti is now the dust tail) with radial teardrop stretch. Hit strength scales everything. No GPU-struct change (`sharpness < 0` marks a drip; magnitude rides `burst.size`). New live-path gates prove flick independence (≥ 0.18 from the painter), drip-volume response (busy ≫ calm), and drip proximity (≤ 0.03 of the line). Three gate adjustments, all Matt-approved in-session: the no-rings bar 13 → 16 (bigger smooth blot interiors legitimately raise the proxy; the 27.6 defect signature still rejected with margin), the colour-freeze probe moved to switch+28 frames (end-of-run probing was contaminated by legitimate flick overpaint of the old line), and the mood-vigour gate re-aimed at the mechanisms (painter clock + mark count + coverage direction). Full battery green (documented fixture-absent set only). Known observation for the gate: coverage runs ~2.2× faster than the confetti baseline (85 % of canvas at 23 s of busy music).

---

## [dev-2026-06-10-c] Skein.5.3b — per-palette canvas grounds + the re-curated library (D-155 amendment)

Matt rejected round 1 (invented hue sets, too similar, fixed beige ground). The redo: every palette is anchored on a named work and carries its OWN canvas ground — light and dark. **Final Matt-curated library: fathom (Full Fathom Five, cream) · poles (Blue Poles, dark indigo + ultramarine/orange/bone/aluminum) · nocturne (all-cool night slate + silver/ultramarine/ice-cyan/cold-violet) · ember (Rothko Four Darks in Red, maroon-black + crimson/orange/parchment/mauve).** Round-2 cut autumn/convergence — multiple pale-ground palettes collapse into one impression (the ground dominates the gestalt). Ground plumbing is end-to-end (state → GPU paint-mask tail → canvas wipe + resize re-clear via a gated override, inert for every other preset); the role grammar generalises to "drums = the starkest ink against the ground". Gates ground-aware; full battery green.

---

## [dev-2026-06-10-b] Skein.5.3 — curated palette library, per-track (D-155)

Matt's enhancement: palette variety like Lumen Mosaic's profiles. Five curated palettes (fathom — the shipped default — plus nocturne, jewel, inkpop, electric; terra was cut at curation), every one holding the same role grammar (drums = darkest ink, bass = deep weight, vocals = warm lead, other = contrast accent) so the painting reads identically in any palette. Each track deterministically paints in its own palette — the same identity hash that seeds the trajectory picks the colours, so "same song → same painting" now includes the inks, and a playlist rotates the library naturally. Library mode engages only on the live path; every test fixture stays pinned to its explicit palette. Curation gates: pairwise display separability (incl. vs the cream ground) across the full mood-tint swing, pale ceiling, role grammar, picker determinism. Contact sheets: `/tmp/skein_pour_diag/<stamp>/skein_palette_candidates.png` (the same real-stem painting per entry).

---

## [dev-2026-06-10] BUG-040 — structural sections actually work now (frozen clock + live-edge peak + relative-only threshold)

**Fix increment (P2, single increment per protocol — evidence pre-filed in BUG-040 from session `2026-06-10T03-09-20Z`'s new section columns).** Three compounding causes, each A/B-proven:

1. **Frozen clock:** the live analysis loop hardwires `time: 0` into `MIRPipeline.process`, so the structural analyzer's clock never advanced — boundary timestamps were `0 − age ≈ −0.3 s` (the exact observed range), durations were noise, confidence pinned ≤ 0.30. The analyzer now clocks from the pipeline's own track-relative `elapsedSeconds`. The new live-caller-shape test fails pre-fix with `sectionStartTime → −0.3167`.
2. **Live-edge peak:** on real music the checkerboard novelty response peaks at the newest window position; its absolute index advances with the stream and escaped the BUG-035-fixed dedup every ~4 detect calls (the ~1.3–1.6 s junk cadence). Detection is now restricted to the interior region (≥ `minPeakDistance` after-context) — a true boundary registers once, ~2 s late.
3. **Relative-only threshold:** mean + 1.5σ admits noise-scale peaks on smooth material (measured: junk ~0.0003 vs real boundary ~0.43). An absolute floor (`minNoveltyFloor = 0.02`) is ANDed in.

Consequence: the Skein.5 structure sub-feature (section flurry + region lean, conf-gated) and the orchestrator's `StructuralPrediction` consumer receive a sane signal for the first time. Gates: evolving-music zero-boundary (pre-fix 5 junk), live-caller timestamps, analyzer-layer plausibility; all 16 pre-existing structure tests + AABA golden unchanged-green. Remaining manual criterion: next real session's section columns show multi-second sections with climbing confidence.

---

## [dev-2026-06-09-c] Skein.5.1/5.2 — never-white painter + structural CSV columns + BUG-039 video instrumentation

Matt's Skein.5 M7 follow-ups, in priority order:

1. **Skein.5.1 — the painter never pours white (D-152 amendment).** The Skein.1-era white-baseline breakpoint baked a permanent tail-length white squiggle at every track start (different per track via the seed). The ring now starts EMPTY (no line until a pour commits); the first commit waits a ¼ s settle (colour from smoothed evidence, not one frame's argmax) and retro-colours the pre-commit tail — the first stroke appears already in the lead stem's colour; the painter clock pauses at true silence (wetness-pause semantics). The "white line at silence" invariant is deliberately retired; gates inverted (`!hasWhiteTexel`, silence `painted == 0`); pour gates re-driven on CALM real stems.
2. **Skein.5.2 — structural columns in features.csv.** `section_index,section_start_s,section_confidence` appended (append-only invariant); published from the per-frame MIR site that feeds `setStructuralPrediction`, so sessions now carry the exact signal the Skein.5 structural bias consumes — the structure layer and the BUG-035 manual criterion become artifact-verifiable. SessionRecorderTests offsets shifted by the new tail; round-trip + default gates added.
3. **BUG-039 filed + instrumented — session video stalls silently.** `22-35-09Z` froze at 5.0 s and `17-14-25Z` at 15 s (of ~10/~6 min) with zero log lines: every stall path was silent and the `append` result ignored. All paths now log throttled counters with `writer.status`/`writer.error`; a failed writer logs once, loudly, and no longer deletes the partial file. Root-cause fix follows the first instrumented affected session.

---

## [dev-2026-06-10-fbs-s4] FBS.S4 — regional beat punch (D-157): the strobe is gone from the math, the rhythm stays

**Increment:** FBS.S4, Matt's option B. **Status:** gates green; awaiting Matt's live read. Each beat, smoothly-bounded regions (~⅓ of the spike field, re-drawn per beat via the new `pulse_beat_index` FV float 42) punch instead of the whole field. Acceptance on the convicting So What window: whole-frame flash steps 69 → 1, localized punch motion preserved (block deltas ~65 vs ~22 ambient), no white-pixel regression (punch cap 1.62 → 1.55 for Lipschitz margin). Live-path A/B: global footprint 28 → 8.7 luma, rest-window 0.

## [dev-2026-06-10-bug039] BUG-039 — video writer death diagnosed live (-11800/-16341) + segment-rolling recovery; flash forensics harness

**Increment:** BUG-039 diagnosis+fix (Matt's call: the session video is the PRIMARY visual-defect evidence — fix the recorder before further flash theorizing). **Status:** recovery landed, gates green; confirmation = the next live session records full-length video (possibly in segments).

- The Skein.5.2 instrumentation caught the death live (`17-50-56Z`): writer left `.writing` 10 s after lock, `AVFoundation -11800` / undocumented `OSStatus -16341` (intermittent encoder-session failure class per Apple forums; co-occurred with the BUG-042 analysis stalls). Undocumented + intermittent ⇒ the durable fix is recovery: dead partial retained, recorder rolls to `video_N.mp4` within a frame, ≤ 8 restarts/session. Regression test simulates the field failure (status leaves `.writing`, file retained) and asserts both segments readable + the restart logged.
- **New diagnostic:** `FerrofluidFlashForensicsTests` — env-gated (`PHOSPHENE_SESSION_DIR` + `PHOSPHENE_FLASH_WINDOW`) offline re-render of a real session window through the live FFO dispatch with the CPU-side modulation replicated; measures the RENDERED PIXELS per frame (mean/p99 luma, near-white fraction, localized block deltas). First run on the Lotus 2–9 s window reproduced measurable localized luma events in the pixels. Secondary tool to the (now fixed) session video.
- Process note recorded: flash attributions to date were input-correlation, not pixel measurement — root-causing continues on REAL video from the next session (ffmpeg signalstats, the BUG-019 method) + the forensics harness for attribution A/Bs.

## [dev-2026-06-10-fbs-s3.2] FBS.S3.2 — the flashing was the aurora reacting to MID-TRACK stem-deviation bursts (soft-knee + bloom-rate response); BUG-043 filed (9.6 s analysis stall; renumbered from BUG-042 — number collision)

**Increment:** FBS.S3.2, from Matt's timestamped live read of session `2026-06-10T17-50-56Z` (Money now syncs ✓ — the S3.1 handoff fix confirmed live; flashing persisted with exact times). **Status:** gates green; awaiting Matt's read. The S3.1 punch-attack attribution was WRONG (falsified by Lotus ~5 s / So What ~7 s flashes during the BRIDGE, pre-handoff); the timestamps converge on a single cause: **all-stem deviation bursts (3–30×, So What dev = 35) reaching the aurora through 150 ms smoothing** — mid-track, outside BUG-041's track-start warmup scope.

- Aurora driver hardened (`auroraDriverStep`): soft-knee input caps bursts (35 → 1.64) while passing musical values; asymmetric response (rise τ 0.45 s — a bloom, never a flash; fall τ 1.2 s); warmup gate retained. Gates: max per-frame output step ≤ 0.08 across the full So What series; legacy-driver red arm keeps the defect visible in the fixtures.
- **BUG-042 filed:** Love Rehab's ~30 s flash was ALSO a real 9.6 s analysis-frame gap (visuals freeze on stale features, then lurch) — separate defect, instrumentation next.
- Matt's other reads recorded: Money syncs (drifts a little — the live tracker's character); So What "too energetic until piano/bass" → Stage 2 energy-scaled punch heights is the designed answer, proposed next.

## [dev-2026-06-10-fbs-s3.1] FBS.S3.1 — Money's handoff was structurally impossible (fixed: envelope-floor swap); the per-beat punch attack was the flashing (fixed: 100 ms attack)

**Increment:** FBS.S3.1, from Matt's live read of session `2026-06-10T17-21-49Z` ("transition works reasonably well… Love Rehab seamless, clearly synchronized; Money never moved over; flashing not fixed"). **Status:** gates green; awaiting Matt's next live read. **Decision:** D-156 amendment.

- **Money:** the swap required both phases in a narrow rest window — but bridge and live phase share one tempo source, so their offset is frozen: the coincidence fires every cycle or NEVER (Money: 0 eligible frames in 63 s; the other tracks drew lucky offsets). Now: both ENVELOPES < 0.15 — the bridge's low span sweeps > 1 full live cycle, so the swap is guaranteed within one bridge cycle, seam bounded by the floor. Money-replay regression test (red under the old condition).
- **Flashing:** the punch attack spanned 0.08 of a beat ≈ 37 ms ≈ 1–2 frames — a near-single-frame spike-height/reflection step, 8–10× per minute on every handed-off track and ZERO on bridge-only Money (the track without a flashing complaint — the controlled comparison). Attack → 0.20 of the cycle (~100 ms): a punch, not a strobe. The BUG-041 aurora warmup stays; the next look adjudicates the attribution.

## [dev-2026-06-10-fbs-s3] FBS.S2.1/S2.2/S3 — planner-fallback exclusion hole closed; aurora track-start flash fixed (BUG-041); the pulse hands off invisibly to the live beat (D-156)

**Increments:** FBS.S2.1 (fallback fix), FBS.S2.2 (BUG-041), FBS.S3 (handoff). **Status:** all gates green; **awaiting Matt's live read** (the energetic steady state + no aurora flash + Pyramid exclusion in an auto-rotating session). **Decisions:** D-156; BUG-041 in KNOWN_ISSUES (fix landed, pending M7).

- **S2.1:** Matt's "verify the exclusion with your own test" caught a real hole — `SessionPlanner.cheapestFallback` ignored hard exclusions (and could schedule a diagnostic preset, a pre-existing D-074 violation). The fallback now relaxes only soft exclusions; locked by the end-to-end planner test that was red before the fix.
- **S2.2:** the aurora's drums driver gets a per-track quadratic warmup (0→1 over 10 s) — the stem-deviation cold-start overswing (measured 1.2–3.3× on exactly the tracks Matt flagged) no longer reaches the GPU at flash scale; steady state byte-identical. Real-session replay tests through the production arithmetic.
- **S3:** after 10 s the spike pulse swaps from the slow 4-beat bridge onto the live drift tracker's per-beat phase — only at a frame where both phases sit in the punch envelope's rest window, so the envelope is zero across the swap (invisible seam by construction). Per-track reset re-opens on the bridge; reactive/no-grid keeps the bridge. Proven on the recorded Love Rehab session (handoff timing, rest-window swap, post-handoff phase identity, envelope-continuity, pre-handoff bridge period — all asserted). Known risk stated: the steady state inherits the live tracker's phase quality.

## [dev-2026-06-10-fbs-s2] FBS.S2 — beat-irregular tracks never see FFO; the pulse becomes a slow 4-beat heave (D-154)

**Increment:** FBS.S2 (Matt's course-correction after the Stage-1 live verdict — session `2026-06-10T03-02-32Z`, addendum in `FBS_STAGE0_FINDINGS_2026-06-09.md`). **Status:** built, gates green; **awaiting Matt's live read.** **Decision:** D-154.

### The verdict it responds to

Stage 1's whole-track per-beat punch read as a robotic metronome on a streaming playlist (gapless switches make every mid-playlist anchor musically meaningless), and Pyramid Song — rubato — regressed. Matt's corrections: the pulse was always the COLD-START bridge, not the whole-track driver; tracks without a steady beat should **never see FFO at all**; a **slow pulse** is the iteration-one answer; improve incrementally.

### What changed

- **Beat-regularity hard exclusion at the preset picker.** `assessBeatIrregularity` (octave-folded full-mix-vs-drums grid BPM disagreement > 10 % OR bar confidence < 0.2 ⇒ irregular; MIR estimator deliberately not consulted — it disagrees 8–11 % even on solid-beat tracks). Calibrated on the real 38-track cache: kept ≤ 9.2 % fold (Love Rehab 0.7, There There 0.4, Money 0.6, Cherub 9.2); excluded ≥ 11.3 % (Pyramid 17.4, SZ2 11.3, Mingus 49). Plumbed as `TrackProfile.beatIrregular` (optional; old profiles decode unchanged) + `PresetDescriptor.requiresRegularBeat` (`requires_regular_beat: true` on FerrofluidOcean.json) + the scorer's `beat_irregular` hard exclusion. Reaches planner, plan-regenerate, reactive (`evaluate(currentTrackBeatIrregular:)`, resolved at track change in `resetStemPipeline` — also evicts FFO if active when the gate fires), and mood-override repatch. Manual selection unaffected. nil = permissive.
- **Slow pulse:** `BeatPulseClock.pulseBeats = 4` — one heave per four beats (~2 s at 120 BPM). Phase error reads as swell character at a musical rate, not a wrong beat claim; sub-1 % tempo error smears phase 4× slower. Fixed 4 beats (not the unreliable detected meter).

### Known gaps (stated)

Swing feel is invisible to the gate (So What: estimators agree 135.5/135.5, conf 1.0 — needs a different signal, future iteration). The Mingus track is excluded (49 % fold) though Matt rated old-FFO best on it — flagged for his read. The 10 % threshold sits in a thin observed gap (9.2 vs 11.3).

### Verification

`BeatRegularityExclusionTests` (real catalog values; planner + reactive exclusion; FFO sidecar flag). `BeatPulseClockTests` at the 4-beat period (anchor 2 ms vs PCM, zero wander, motion gates green). `FerrofluidPulseLivePathTests` with the slow pulse: punch |δ| = 31.1 luma / rest 0.0 through the live dispatch. Scorer/planner/golden-session/regression suites green; full suite shows only the documented wall-clock flakes (SoakTestHarness, MetadataPreFetcher — both pass isolated). SwiftLint `--strict` clean; app `BUILD SUCCEEDED`.

## [dev-2026-06-09-fbs-s1] FBS Stage 1 — FFO spikes punch on a steady, first-note-anchored, cached-tempo beat pulse (D-153)

**Increment:** FBS Stage 1 (kickoff `docs/prompts/FFO_BEAT_SYNC_KICKOFF.md`; Stage 0 findings `docs/diagnostics/FBS_STAGE0_FINDINGS_2026-06-09.md`). **Status:** built + measured green; **STOPPED at the Stage-1 gate — awaiting Matt's read on a live session** (validation = measurement; a fresh session with the new `pulse_phase01`/`pulse_amp01` features.csv columns is the acceptance artifact). **Decision:** D-153.

### What changed

- **New engine primitive `BeatPulseClock`** (`Sources/DSP/`): anchors at the track's first NOTE (silence→sound, 3-frame confirm, backdated — Matt's correction over first-hit), ticks at the cached BeatGrid tempo (the trustworthy half of the grid, ~1 % err), and is **never drift-corrected** — deliberately independent of `LiveBeatDriftTracker` (50–90 ms wander over the opening, Stage 0). `pulseAmp01` gates: 0 before the first note / across > 0.5 s sustained silence.
- **`FeatureVector` floats 40–41** (`pulsePhase01`/`pulseAmp01`, reclaimed `_pad4`/`_pad5` — byte-identical layout for fields 1–39, no size migration, both MSL mirrors updated). Wired in `MIRPipeline` (`setBeatGrid` ×2 = tempo authority; `reset()` clears the anchor per track; `buildFeatureVector` writes per frame). Logged as trailing `features.csv` columns.
- **FFO spike driver replaced:** `fo_spike_strength` Layer 2 drops `0.8·clamp(f.bass)` (the "frozen spikes" root cause + the residual post-BUG-038 sparkle) for a punch envelope on the pulse (rise 8 % of the beat, decay by 85 %, rest; headroom-capped ≤ 1.62 under the CSP.3.5 Lipschitz `/6` ceiling). Baseline + swell untouched; FA #67 one-primitive-per-layer holds.

### Measured proof (real sessions, live dispatch path)

- **Anchor:** ~2 ms from the PCM-measured first note (Cherub Rock, cross-clock wallclock↔raw-tap; gate ±60 ms). SZ2's session has bunched startup wallclocks (18.3 s stall) — cross-clock unverifiable there, documented; its gate is anchor == first sustained-audible frame.
- **Steadiness:** every pulse interval == the grid period (≤ 5 ms interpolation tolerance), cumulative drift ~0 over the opening — vs the live tracker's 50–90 ms wander on the same sessions.
- **Motion:** envelope std **0.198 on the frozen streaming Lotus Flower session** (old term: 0.044) — consistent across material (Cherub 0.212, SZ2 0.182; the old term varied 0.044–0.191).
- **Live pipeline (FA #66):** `FerrofluidPulseLivePathTests` renders 110 continuous frames of the real Lotus session through FFO's actual dispatch (SDF G-buffer → deferred lighting → bloom + ACES, pipeline built once), paired A/B per frame: **punch-window |δ| = 29.3 luma units, rest-window |δ| = 0.0** — the spike field changes strongly AT the beats and not at all between them.
- Suites: `BeatPulseClockTests` 9/9 (real-session fixtures under `Tests/Fixtures/fbs/`), recorder column gates, `PresetRegressionTests` goldens unchanged, full engine suite green modulo the documented pre-existing set (7 × `love_rehab.m4a` fixture-absence + Skein colour-freeze). SwiftLint `--strict` clean; app `BUILD SUCCEEDED`.

### Known limitations (stated up front)

Mid-playlist gapless segues anchor at the track-change instant (no silence boundary → best-effort, not a musical "one"). The anchored phase is perceptually-convincing, not provably the downbeat — FA #69's structural limit stands. The `ffoColdStartFixEnabled` off-arm no longer restores the historical `f.bass` spike drive.

## [dev-2026-06-09-flicker] BUG-038 — temporally smooth ray-march light intensity (kill the BUG-019 flicker residual)

**Increment:** FBS pre-step (a clean, non-flickering FFO baseline before the Ferrofluid Beat-Sync pulse work — Matt's call 2026-06-09). **Status:** fix landed, automated validation green; **awaiting Matt's M7** (visual confirm the strobe is gone). Local worktree branch `claude/intelligent-shirley-1ce3b4` — **not yet on `main`/Matt's build.** **Defect:** `KNOWN_ISSUES.md` BUG-038 (continuation of BUG-019). **Evidence:** sessions `2026-06-09T21-23-07Z` (streaming) + `21-19-14Z` (clean local); `tools/fbs/` analysis.

### The defect

`applyAudioModulation` (`RenderPipeline+RayMarch.swift`, preset-agnostic for **all** ray-march presets) set scene light intensity = `base × (1 + f.bass·0.4 + beatAccent·0.15)` **every frame with no temporal smoothing**. On real sessions the beat-onset term `beatAccent = max(beatBass, beatMid, beatComposite)` fires on **96–98 % of frames** — a near-constant jitter, *not* clean beats — and `f.bass` is noisy, so the whole scene's brightness **stepped 7–9 perceptible times/sec** (a constant strobe). This is the residual BUG-019 left behind: PERF.3 cut the worst of it (`0.4 + beatPulse·2.6` → the current formula, 76→53–60 oscillation events) but kept a beat term and added no smoothing. Present on clean-signal Cherub (~7/sec) too, so it is **not** a weak-signal artifact. Matt has reported this "since FFO existed"; it blocks fair evaluation of FFO and any beat-sync work.

### The fix

Temporally smooth the light multiplier with an EMA before writing the uniform — `RayMarchPipeline.smoothLightIntensity(previous:target:dt:tau:)`, τ ≈ 0.12 s. Measured on the real `intensityMul` series across all 4 sessions: perceptible steps drop **~8/sec → ~0** while the slower musical brightness swell is preserved (surviving variation 0.02–0.08). The PERF.3 formula is **unchanged — only low-passed**; the beat term's 97 %-firing jitter becomes a harmless near-constant offset. **Mean-preserving + preset-agnostic → no certified-preset (Nimbus) regression.** First frame after a preset load / stall (`dt ≤ 0`) returns the target verbatim → no startup brightness lag, and single-frame golden hashes are unchanged.

### Tests / verification

- **New pure-function gates** (`RayMarchPipelineTests`): `test_smoothLightIntensity_suppressesFrameToFrameFlicker` (synthetic jittery target mimicking the 97 %-firing beat + bass noise → smoothed < 5 steps / 600 frames, raw > 400, still tracks the swell) and `_firstFrameHasNoLag` (`dt ≤ 0` → target verbatim). Both green.
- **Regression:** `PresetRegressionTests` golden hashes **unchanged**; `RayMarchPipelineTests` (12), `FerrofluidOceanVisualTests`, `SceneUniformsTests`, `MatIDDispatch`, `PresetAcceptanceTests` all green. SwiftLint `--strict` clean on the 3 changed files.
- **Full engine suite:** 8 pre-existing failures, **all verified independent of this change** (re-confirmed with the change stashed): 7 = the documented `love_rehab.m4a` fixture-absence cluster (LFS tempo fixtures not fetched in this worktree — `Scripts/fetch_tempo_fixtures.sh`), 1 = a **pre-existing Skein.4.1 colour-freeze regression** (`SkeinCanvasHoldTest.swift:548`, fails without this change too — flagged separately, out of scope).
- **Pending:** Matt M7 — FFO and other ray-march presets show steady lighting (no strobe) through a continuous-playback session. **Requires the fix to reach his build** (integrate to local `main`, or build the branch) per `feedback_worktree_changes_reach_build`. *(Cross-note: the "pre-existing Skein.4.1 colour-freeze regression" this entry flags is resolved by the `[dev-2026-06-09-b]` entry below — the gate was session-fragile, red on new session data, not code.)*

---

## [dev-2026-06-09-b] Skein.5 — mood + structure + anticipation + painter-locus (D-152; pending Matt M7)

The §1.3/§1.5 musicality layer on Skein's working look — no new visual subject. Four sub-features, each placed so the lossless canvas-hold invariants survive (full rationale in D-152, craft in `SHADER_CRAFT.md §18.10`):

- **Mood** — valence/arousal EMA-smoothed in `SkeinState` (FA #25); the palette is warm/cool-tinted + saturated **at lay time and frozen** into breakpoints/bursts, so the held canvas archives the song's emotional arc. Arousal quickens the painter (×0.7–1.3), shortens the splatter refractory, and slightly widens the pour. Measured: warmth(R−B) 106.4 vs 81.4 across ±0.8 valence, +24 % coverage with +arousal, pale share 0.003.
- **Structure** — consumes the ENGINE.3/D-151 signal (post-BUG-035): a confident section boundary fires a density flurry (spawns 88→144 on identical tiled audio), a fresh displaced pour, and a bounded region lean (≤ 0.085 UV) routed through the per-pour breakpoint offsets; `sectionIndex mod 5` slots make repeated sections revisit the same patch. Confidence-gated to **exactly zero** below smoothstep(0.25, 0.55) — ambient material keeps the pure allover read.
- **Anticipation** — τ-speed wind-up into each beat + a 90 ms flick at the wrap (`beatPhase01`, FA #33; wind-up mean 0.649 / flick 1.627). τ-warping keeps tail samples ON the trajectory curve — no smear by construction; exactly 1.0 at silence.
- **Painter locus** — display-only in `skein_comp_fragment` (the geometry overlay would bake it permanently), via a new gated blit-stage buffer-1 binding (registry row added); glow + occlusion shadow ring; build-flagged **OFF** by default.

Also: the Skein.4.1 colour-freeze gate now scans all recorded sessions for the most decisive switch pair (it went red on new session data, not code). All prior Skein gates green; DB/FM + PresetRegression byte-identical; loader count intact; full engine 1419 tests (7 known love_rehab fixture-absent only); app build + SwiftLint `--strict` clean.

---

## [dev-2026-06-09] BUG-035 — NoveltyDetector ring-wrap boundary dedup (structural signal repaired for Skein.5)

**Fix increment (P2, single increment per protocol — evidence pre-documented in `docs/diagnostics/CODE_AUDIT_2026-06-09.md`).**

- **`NoveltyDetector`** stored detected boundaries by *logical* ring index; once `SelfSimilarityMatrix` filled (600 frames), logical indices slide ~30 per `detect()` call, so the dedup window (120 frames) re-admitted the same physical boundary every ~4 calls — ~4-5 near-equal-timestamp duplicates per real boundary, collapsing `StructuralAnalyzer` section durations toward 0, inflating `sectionIndex` ~5×, and structurally depressing `confidence` (the exact signal Skein.ENGINE.3 / D-151 wired live for Skein.5).
- **Fix:** `SelfSimilarityMatrix` now exposes `totalFrameCount` (monotonic frames-added counter); `NoveltyDetector` stores and dedups boundaries in **absolute frame index** space (`Boundary.frameIndex` is now absolute, not logical). Timestamps were already slide-compensated and are unchanged.
- **Related (same audit finding):** `MIRPipeline.latestStructuralPrediction` was the only published property written outside the lock — the write at the `updateStructuralAnalysis` site now goes under `lock` like every other CPU-side property.
- **Tests:** `noveltyDetect_ringWrap_boundaryRegistersOnce` + `structuralAnalyzer_ringWrap_boundaryRegistersOnce` (production 600-frame geometry). Both A/B-proven: pre-fix they fail with 3 and 2 duplicate registrations respectively (identical timestamps — the audit's predicted signature); post-fix exactly 1. Existing `SkeinStructureSignalTests` and the AABA golden regression stay green.

---

## [dev-2026-06-06-b] AGC3 — BUG-029: ease the AGC `f.bass` meter in at each track start (cold-start spike fix)

**Increment:** AGC3.1 (measure) → AGC3.2 (decide, D-148) → AGC3.3 (fix). **Status:** fix landed; automated validation green; **awaiting Matt's catalog M7 (AGC3.4 manual gate)** before close (AGC3.5). Local `main`, not pushed. **Decision:** `docs/DECISIONS.md` D-148. **Evidence:** `docs/diagnostics/AGC3_1_COLDSTART_SPIKE_2026-06-05.md`.

### The defect

At every track onset preceded by silence, `BandEnergyProcessor`'s total-energy AGC denominator (`agcRunningAvg`, *not* reset per track) had decayed toward zero across the inter-track silence — or seeded at `1e-6` off the session-start pre-roll — so the first audible frame over-scaled and `f.bass` spiked to an absolute **~3.5–4.0** (steady ~0.25 = **11–17×**). Continuous-energy presets reading `f.bass` directly (Ferrofluid Ocean's `1.0 + 0.8·clamp(f.bass,0,1)`) **popped to their clamp ceiling then collapsed** — a "pop-and-drop," not a smooth arrival. AGC3.1 measured it on a real 5-track LF session (`tools/agc3/measure_coldstart_spike.py`): the spike is **per-track** (refutes the BUG-025 "one-time flash" shelving premise), gated by the silent pre-roll, and the inter-track instances last *longer* (0.9–1.2 s) than session-start (0.10 s). The per-stem path does *not* spike (it resets per track).

### The fix (D-148 — Matt chose "ease the meter in per track")

Two cold-start/silence-only changes in `BandEnergyProcessor`:
- **Seed-from-first-audible** — defer the AGC seed until the first frame with energy (don't seed `1e-6` off leading silence). Mirrors `StemAnalyzer` / SAR.1 / `BandDeviationTracker`.
- **Hold-through-*sustained*-silence** — after 30 consecutive near-silent frames (relative threshold, ~0.5 s; an inter-track gap, not a between-beat dip) hold the running average instead of decaying it toward zero, so the next onset doesn't divide by a tiny denominator. The *sustained* gate is load-bearing: brief within-track gaps in sparse music keep decaying exactly as before (caught when a single-step hold shifted `FerrofluidBeatSyncTests`' sparse synthetic pattern).

**Steady-state is byte-identical** for continuous audible input (frame-0 energy > 1e-6, no sustained sub-2 % run) — same seed, same EMA, same rate schedule — so the AGC's mix-density-stability response (D-026) is untouched. The change affects only the immediate post-silence ease-in.

### Tests / verification

- **New live-path regression gate** `AGC3ColdStartSpikeTests` (FA #66 — through the real `MIRPipeline.process`): session-start spike **32.6× → < 2×**, inter-track **10.6× → < 2×**, plus a **byte-identical steady-state lock** (continuous-audible `f.bass` matches the captured pre-fix values to 1e-6).
- Full engine suite green except the **pre-existing** `love_rehab.m4a` fixture-absence cluster (7) + the MemoryReporter env-flake (1) — verified identical with the fix stashed. **BUG-018** stem cold-start gate green. **No `PresetRegressionTests` golden drift** (fixtures bypass the live AGC). SwiftLint `--strict` clean; app build `BUILD SUCCEEDED`.
- **Pending:** Matt M7 on continuous-energy presets, both paths (Ferrofluid Ocean first — the pop-and-drop must be gone and the onset smooth, with no mid-track regression). Streaming path not yet characterised (no streaming multi-track session on disk at AGC3.1).

### Commits

`[AGC3.1]` measure (`ea2326e0`) · `[AGC3.2]` D-148 · `[AGC3.3]` fix + live-path gate.

---

## [dev-2026-06-06] AGC2 — BUG-027: per-band EMA deviation pivot (mid/treble `*Dev` alive again) + cold-start warmup

**Increment:** AGC2.1 → 2.5 (measure → decide D-146 → fix → validate → close) + AGC2.4.1 (cold-start sub-fix). **Status:** Resolved 2026-06-06 (local `main`, not pushed). **Decision:** `docs/DECISIONS.md` D-146. **Evidence:** `docs/diagnostics/AGC2_1_DEVIATION_CENTRING_2026-06-05.md`.

### What landed

The FeatureVector band deviation primitives (`bassDev`/`midDev`/`trebDev` + the `*AttRel` family) were derived against a **fixed 0.5 pivot**, but the AGC normalises the *total* 6-band energy to 0.5 — so each band centres well below 0.5 and `midDev`/`trebDev` fired **~0 % on all music** (measured AGC2.1, both capture paths, including genuinely mid-rich and treble-rich tracks). The entire positive mid/treble "above-average" channel was dead catalog-wide.

**Fix (D-146, the b+c-split):** a new `BandDeviationTracker` (`Sources/DSP`) replaces the fixed pivot with a **per-band running-average pivot** — each band's `*Rel`/`*Dev` is measured against the band's own recent average, mirroring `StemAnalyzer`'s per-stem EMA (already healthy). The total-energy AGC is untouched, so raw `f.bass/mid/treble` and the cross-band relative-energy info are unchanged. Stems needed no engine change (their deviation path was already EMA-based); the raw-`{stem}Energy`-centre is handled per-consumer (Nimbus, D-144 r1.6) + documented.

Replaying the fix over a real session, the long-dead routes wake up: Alameda (mid-rich) `mid_dev` 0 → 59 %, Mingus (treble-rich) `treb_dev` 0 → 63 %; `bass_dev` 2-8 % → 40-60 %. Affected presets: Spectral Cartograph, Volumetric Lithograph, Gossamer, Dragon Bloom, Arachne, Aurora Veil, Kinetic Sculpture. **Ferrofluid Ocean is NOT affected** (it reads `f.bass`/`arousal`, no deviation primitives).

### Cold-start sub-fix (AGC2.4.1)

The first M7 exposed a hole: the per-band EMA seeded from the session-start AGC spike (bass = 3.69 off the initial silence) and — since `MIRPipeline.reset()` is never called per track — stayed poisoned ~3-4 minutes, suppressing all band `*Dev` early. Fixed with a two-speed warmup (fast decay converges through the spike in ~1-2 s) + a value ceiling. **A live-path test now reproduces and guards it** (`bandDeviation_recoversFromColdStart_liveMIRPipeline`) — closing the FA #66 test/prod parity gap that let the hole ship.

### Tests / verification

- `RelDevTests`: the fixed-0.5 formula pin retired → `BandDeviationTracker` unit tests + the BUG-027 firing gate (recorded fixture: old 7.2 %, new 41 %) + the live-path cold-start test. 10/10 green; existing 8 unregressed.
- Full engine suite green (modulo the pre-existing gitignored `love_rehab` fixture); app build `BUILD SUCCEEDED`; SwiftLint `--strict` clean; **no `PresetRegressionTests` golden drift** (fixtures bypass the live derivation).
- M7 catalog cycle (`2026-06-06T01-18-36Z`): deviation presets read well; the one flagged issue (Ferrofluid Ocean startup) was diagnosed out of scope → **BUG-029**.

### Durable

- `SHADER_CRAFT.md §14.1` softened — `f.*_dev` works again (per-band EMA), with the mid/treble-amplitude + cold-start caveats.
- Diagnostics: `tools/agc2/measure_deviation_centring.py`, `tools/agc2/prototype_pivot_formula.py`.
- Filed **BUG-029** — the AGC `f.bass` cold-start spike (pops/drops continuous-energy presets at every track onset; out of AGC2 scope).

### Commits

`bf711edf` (AGC2.1) · `b1c1d1b7` (D-146) · `41d87bf9` + `0d2ddb51` (AGC2.3) · `95a16881` (AGC2.4.1). Local `main`, not pushed.

---

## [dev-2026-06-04] MM — Murmuration: 3D rebuild + global-envelope musicality, CERTIFIED

**Increment:** MM.6 (rebuild) + MM.5 (cert). **Status:** Shipped + certified 2026-06-04. **Design:** `docs/presets/MURMURATION_DESIGN.md` §13–§14.

### What landed

**Murmuration is now a certified 3D preset** — a dense starling flock against a dusk sky that churns internally, wheels as a comma, drifts across the sky, rolls dark bands through itself, and responds to the music's energy. This was the goal of the whole Phase MM uplift ("I have always wanted a 3D version of this preset").

### The road here (5 live-review rounds, each headless-verified before the next look)

1. **Pivot (`9056dc48`):** the emergent Flock2 rebuild failed Matt's M7 review **seven times** (spray → frozen → dead blob → off-canvas). Retired it. The premise that failed: pure emergence holds a framed dense mass on its own — it doesn't. Lifted the **proven 40-round 2D controlled-ellipse flock** (`Particles.metal`) into 3D instead: `Murmuration3D.metal` + `Murmuration3DGeometry` (a D-097 `ParticleGeometry` sibling). Dense + framed *by construction*.
2. **Worm → murmuration (`9b37d359`):** the motion read as a worm — an `sin(u·π+st)` curvature wave travelling down the long axis (the snake-spine primitive) over a static interior. Replaced with a wheeling comma (C↔S) + **internal churn** (coherent flow through the volume — the boil) + continuous rolling bands. +20% speed.
3. **Traverse (`75d39eaf`):** it churned but moved in place. Camera back (`camDist` 2.6→3.2, `viewScale` 2.1→1.3) + a slow dominant end-to-end sweep.
4. **Musicality (`cd67944a`):** the routes were 10–20% deltas buried under a pure-time motion clock — the disconnect. Drove the **global envelope** instead (per `feedback_global_coupling_emergent_substrate` + the Audio Data Hierarchy): smoothed CPU-side envelopes — `energyEnv` → a vigor-paced morph clock + swell + traverse range (PRIMARY); `beatEnv` → a beat-gated agitation/banking wave (ACCENT); `vocalEnv` → density. Gains sized to measured driver ranges.
5. **Certification (`8f313bdc` + `69df2f93`):** `certified: true`, `rubric_profile: lightweight`, accurate description; both cert ground-truth sets synced (`FidelityRubricTests` + `PresetDescriptorRubricFieldsTests`); `MurmurationRoutes.swift` firing specs re-derived against the shipped coupling. Deliberately **no `stem_affinity`** — Murmuration is energy-driven, not stem-specific.

### Durable learnings (in CLAUDE.md / design doc)

- A faithfully-ported **emergent** reference can be the wrong tool when the product needs direct **control** — use the reference for character, a controlled substrate for the guarantee (design §13, CLAUDE.md regime bullet).
- An elongated mass needs **internal** motion (churn + bands rolling *through* it) to read as a flock — bending the whole body is worm motion (§13.3).
- On a preset with strong autonomous motion, audio coupling only **reads** if it drives that motion's **global envelope** (vigor/size/range), not if it adds small deltas on a fixed clock (§13.5).

### Verification

Engine **1377** green, app build clean, swiftlint --strict **0**; FidelityRubric / Golden / routing gates pass. Headless harness `Murmuration3DRenderTests` (`test_framed` = framed-across-traverse + real sweep under energy; `test_musicality` = louder → bigger + more banding than silence; `test_render` = silence/audio/burst contact sheets). **Review pass** on session `2026-06-04T16-44-08Z` (8554 frames): GPU **0.75 ms** mean, **zero NaN/inf**, framing holds live. Certified by Matt across the review rounds.

---

## [dev-2026-06-03] FM — Fata Morgana: faithful butterchurn mirage port + bar-sway stem uplift, CERTIFIED

**Increment:** FM.0 + FM.L1 + FM.L2. **Status:** Shipped + certified 2026-06-03. **Decision:** D-139.

### What landed

A new **certified** preset — **Fata Morgana**, a mirage (starfield night sky, glowing cycling horizon, reflective rippling neon floor). It's the second faithful butterchurn port after Dragon Bloom: the render loop (`warp → blur → shapes-on-top → comp → swap`) is replicated wholesale from the source (FA #70), then uplifted with stem separation — **three neon spectra (drums/bass/vocals) sway over the water in time with the bars.**

### How it works

- **Faithful substrate:** custom feedback warp (blur-driven swirl + lattice, self-decaying), procedural mirage comp (perspective floor + horizon glow + water reflection + point-wrap starfield, display-only), and a moderate blur1. `zoom=1.05` (from `pixel_eqs`) forms the concentric rings via the shapes' zoom-feedback.
- **Stem uplift:** 3 spectra (one per instrument, down from the source's 11-blob crowd) share a phase-offset `cos(π·swayClock)` horizontal sway — `swayClock` advances +1 per musical bar, drums/vocals anti-phase + bass weaving so the frame stays balanced and they turn on each downbeat. Brightness: one gentle pulse per grid beat + per-stem `_energy_dev` identity.

### Fidelity fixes worth remembering (durable)

- **sRGB round-trip** (FA #71): the comp output is sRGB-decoded before the `.bgra8Unorm_srgb` drawable write so an sRGB-naive source shader's values map to the intended display blacks (the comp was washing out otherwise).
- **Glow clock magnitude** (FA #71): the horizon-glow `slow_roam_sin` has a ~21-min period; a fresh render sat in its pale opening quarter. Phase-seeded (+400 s) + per-session jitter → warm, spectrum-cycling horizon, different hue each session.
- **MSL snake_case fields** (FA #72): `f.beat_phase01` / `st.drums_energy_dev` in `.metal`, never the Swift camelCase — the camelCase silently fails to compile and the preset is dropped (count 18→17, caught by `PresetLoaderCompileFailureTest`).

### Verification

1374 engine tests pass; swiftlint --strict 0/420; app builds. **Certified** by Matt's live M7 across the movement-tuning sessions (closing `2026-06-03T17-08-42Z`, Billie Jean) — reviewed full-video frames + clean session.log. Cert ground-truth sets updated in `FidelityRubricTests` + `PresetDescriptorRubricFieldsTests`. Other mv_warp presets byte-identical (PresetRegression).

---

## [dev-2026-06-01-b] LF.6.streaming — Streaming-path artwork resolver + fetcher + cache + wire

**Increment:** LF.6.streaming. **Status:** Shipped 2026-06-01.

### What landed

Every Spotify / Apple Music / tap-path track-change now resolves and fetches album artwork and publishes it through the same `currentTrackArtworkData` channel LF.6 (D-133) established for the LF path. The streaming chrome with resolvable artwork is pixel-identical to the LF chrome with resolvable artwork; non-resolvable tracks fall back to the LF.6 `music.note.list` glyph.

### How it works

Three new subsystems shipped as siblings (one engine, two app, plus an engine-extension on the app side):

- **`StreamingArtworkURLResolver`** (engine) — modelled on `PreviewResolver`. Spotify-first: `TrackIdentity.spotifyArtworkURL` (new resolution-hint field, populated by `SpotifyWebAPIConnector` from `album.images[0].url`) short-circuits without any network call. iTunes Search fallback: by `<artist> <title>`, parses `artworkUrl100`, rewrites `100x100bb` → `600x600bb`. Per-session in-memory cache de-duplicates.
- **`StreamingArtworkFetcher`** (app) — `StreamingArtworkFetching` protocol + URLSession-backed default with a 5 s request timeout. Throws on non-2xx / network failure; caller catches and publishes nil so the chrome falls back to the glyph.
- **`StreamingArtworkDiskCache`** (app) — actor at `~/Library/Caches/com.phosphene.app/streaming-artwork/`. SHA-256-keyed `.bin` files; LRU eviction by `contentModificationDate`; atomic writes; 100 MB cap (~1,200 cached tracks at typical Spotify CDN size).
- **`StreamingArtworkPublisher`** (app, in `VisualizerEngine+StreamingArtwork.swift`) — owns the in-flight fetch `Task<Void, Never>?` so a rapid A → B track-change cancels A cleanly. Every publish gated on `!Task.isCancelled`. Composes the resolver → disk-cache → fetcher → persist → publish chain.

The `+Capture.swift` track-change callback now resolves the canonical `TrackIdentity` BEFORE the MainActor block so the publisher sees the full identity (with `spotifyArtworkURL` hint). MainActor block publishes `currentTrack` + nil-artwork on the same tick (LF.6 title-first-then-artwork invariant) then kicks the publisher; resolved bytes land on a later tick — chrome's existing opacity-animate-in covers the gap.

### Decisions (Matt-approved Pre-Flight Audit)

D-134 records the full rationale. Summary: (a) cache location `~/Library/Caches/`; (b) cache size cap 100 MB; (c) source order Spotify + iTunes Search; (d) in-flight cancel-on-track-change yes.

### Verification

- Engine 1367 / 1367 ✓ (LF.6 baseline 1361 + 6 `StreamingArtworkURLResolverTests`).
- App 379 / 379 ✓ on isolated re-run; first parallel run flaked on `SessionManagerTests` state-transition assertions, second run passed clean — matches the pre-existing timing-race flake pattern (memory `project_test_baseline.md`). `SessionManagerTests` passes 11 / 11 in isolation via `swift test --filter SessionManagerTests`.
- 7 disk-cache tests + 5 fetcher tests + 6 publishing tests + 6 resolver tests + 1 fixture-extension test all pass.
- SwiftLint `--strict` clean on every touched file.
- `Scripts/check_user_strings.sh` exit 0 / `Scripts/check_sample_rate_literals.sh` exit 0.
- 4 PBX sections updated in `project.pbxproj` for each new app source / test file.

### Manual smoke (Matt-driven, pending)

Visual contract to verify on a real Mac mini session:

1. Spotify session — artwork renders within ~1 s of every track change.
2. Apple Music session — artwork renders for tracks iTunes Search finds (most mainstream); less-mainstream tracks fall back to the glyph, no crash.
3. Rapid `next next next`-track — chrome never flashes a previous track's artwork; final state matches the final track.
4. Offline — restart a previously-played streaming session in airplane mode; cached artwork still renders (disk cache hit).
5. Disk cap — `~/Library/Caches/com.phosphene.app/streaming-artwork/` does not exceed 100 MB after extended use.

### Follow-up

Potential `LF.6.streaming.2` if Apple Music subscribers report the iTunes Search fallback misses too often. MusicKit-native artwork would land highest-res for that path but requires MusicKit token plumbing not currently in the music-library scope.

---

## [dev-2026-06-01-a] LF.6.fix.1 — Clear stale LF artwork on streaming track-change + session start (BUG-024)

**Increment:** LF.6.fix.1. **Status:** Resolved 2026-06-01. Trivial-collapsed P1 per CLAUDE.md §Defect Handling Protocol.

### What happened

Manual smoke of LF.6 (Matt-driven, 2026-06-01) surfaced a clear regression: after running an LF session with embedded artwork, every streaming track in the next Spotify session rendered the LF artwork in the chrome's thumbnail slot. The screenshots showed Radiohead's "There, There" and Chaim's "Love Rehab" both displaying The Cure's Kiss Me cover.

### Root cause

`engine.currentTrackArtworkData` is the `@Published` LF.6 added for chrome consumption. The LF write sites (`handleLocalFileReady` + `advanceLocalFileQueue`, via `applyLocalFileTrackState`) correctly publish bytes-or-nil per track. The streaming track-change callback at [VisualizerEngine+Capture.swift:189-202](PhospheneApp/VisualizerEngine+Capture.swift:189-202) writes `currentTrack` for every streaming track but never touched `currentTrackArtworkData`. The `@Published` retained the LF bytes indefinitely; `TrackInfoCardView.showArtworkSlot` evaluated `(albumArtData != nil) || isLocalFileSession` → `true` (stale bytes) → rendered the wrong art.

This violates the LF.6 kickoff's Critical Invariant: *"Streaming-path behaviour is byte-identical to pre-LF.6. `engine.currentTrack` continues to be set by `makeTrackChangeCallback` for streaming, `currentTrackArtworkData` stays `nil` on streaming sessions."*

### The fix — one commit

**`[LF.6.fix.1]`** — three small changes:

- **`PhospheneApp/VisualizerEngine+Capture.swift:190`** — the streaming track-change callback writes `self.currentTrackArtworkData = nil` alongside `self.currentTrack = event.current`, back-to-back in the same MainActor block. The pairing mirrors the LF write sites and honours the kickoff invariant (title-first then artwork-second so chrome consumers see one tick).
- **`PhospheneApp/VisualizerEngine.swift:807`** — the `.connecting` state observer clears `currentTrackArtworkData = nil` alongside `currentSessionPlanSeed = nil`. Defense-in-depth at session boundaries; covers ad-hoc / reactive entry paths that may not fire a track-change callback immediately.
- **`PhospheneAppTests/PlaybackChromeArtworkBindingTests.swift`** — new regression test "LF → streaming transition: artwork-nil emission clears prior LF bytes". Asserts the view-model's `CombineLatest` binding correctly observes a nil artwork emission after a prior LF bytes emission. Pairs with the four existing binding tests in the suite (now 6 total).

### Verification

- Engine: 1360 / 1360 ✓.
- App: 361 / 361 ✓ (LF.6 baseline 360 + 1 BUG-024 regression test).
- SwiftLint `--strict` clean on all touched files.

Manual re-test pending Matt's confirmation: re-run Test 4 from the LF.6 smoke (LF session → end → Spotify playlist). Expected: streaming chrome reverts to text-only (slot hidden entirely, no artwork tile, no fallback glyph), matching pre-LF.6 streaming chrome.

### Follow-up

The deeper "it would be nice if the actual album art appeared for streaming tracks" remains scoped to `LF.6.streaming` (kickoff on disk at `docs/prompts/LF6STREAMING_KICKOFF.md`). LF.6.fix.1 restores correct behaviour against the LF.6 invariant; LF.6.streaming will replace the hidden-slot state with network-fetched artwork via the same `currentTrackArtworkData` publisher.

---

