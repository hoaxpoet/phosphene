# Phosphene — Known Issues

Open and recently-resolved defects. Filed using `BUG_REPORT_TEMPLATE.md`. See `DEFECT_TAXONOMY.md` for severity definitions and process.

## Open Index

| ID | Sev | Domain | One-liner |
|---|---|---|---|
| AUDIT-2026-06-09 | P2/P3 | audit backlog | Full-codebase audit findings not individually filed |
| BUG-050 | P2 | resource-management / perf | Always-on session recorder ~doubles per-frame CPU (encode stacked on render) |
| BUG-034 | P1 | renderer / test-isolation | Ray-march fixtures render at 32 steps vs live 128 (`sceneParamsB.z` double-booked) |
| BUG-035 | P2 | dsp.structure | NoveltyDetector re-detects boundaries ~4-5× after similarity ring wraps |
| BUG-036 | P2 | audio.capture / performance | Heap allocations on the real-time audio thread (three sites) |
| BUG-037 | P2 | preset.fidelity | Arachne spiral chord-count contract inconsistent; build pops at ~45 % |
| BUG-042 | P2 | dsp.structure | Structural sections still ~1.5 s; analyzer geometry is note-scale |
| BUG-043 | P2 | pipeline-wiring | Mid-playback 9.6 s analysis stall froze visuals, then lurched |
| BUG-041 | P2 | dsp.stem / preset.fidelity | FFO aurora flashes at track start (stem-deviation cold-start overswing) |
| BUG-038 | P1 | renderer / dsp.beat | Ray-march light intensity flickers 7-9 steps/sec (BUG-019 residual) |
| BUG-039 | P2 | resource-management | Session video silently stops appending; recorder stays "running" |
| BUG-040 | P2 | dsp.structure | Live-edge boundary every ~4 detect intervals; structure signal unusable |
| BUG-029 | P3 | dsp.beat | AGC `f.bass` cold-start spike pops presets at every track onset |
| BUG-028 | P2 | dsp.beat | Beat-grid live phase imperfect on ~half of tracks |
| BUG-027 | P2 | dsp.beat | Positive band deviations near-dead for non-dominant bands |
| BUG-025 | P3 | dsp.beat | AGC running average poisoned by post-`active` startup transient |
| BUG-026 | P2 | session.ux | No warning when tap signal level is structurally insufficient |
| BUG-014 | P3 | preset.fidelity | Lumen Mosaic panel aggregate uniform across tracks |
| BUG-012 | P1 | ml | MPSGraph EXC_BAD_ACCESS in StemFFTEngine under sustained force-dispatch |
| BUG-013 | P2 | dsp.beat | No `time_signature` source; meter wrong on some odd-meter tracks |
| BUG-001 | P2 | dsp.beat | Money 7/4 stays REACTIVE on live path |
| BUG-005 | P3 | session.ux | Spotify `preview_url` returns null for some tracks |


---

## Open

---

### AUDIT-2026-06-09 — Full-codebase audit backlog (P2/P3 findings not individually filed)

**Status:** Open — index entry. The 2026-06-09 six-agent full-codebase audit (~92k lines, all findings verified at file:line, cross-checked against this tracker and CLAUDE.md FAs) produced 6 P1s, 17 P2s, ~40 P3s. The P1s and three highest-impact P2s are filed individually below (BUG-030 … BUG-037). Everything else lives in **[`docs/diagnostics/CODE_AUDIT_2026-06-09.md`](../diagnostics/CODE_AUDIT_2026-06-09.md)** — treat that document as the evidence record when picking up any item. Remaining P2s in brief (full detail + fix shapes in the audit doc):

- **Reactive orchestrator can select a hard-excluded preset** at session start — `PresetScorer.rank()` never filters despite its doc-comment; reactive nil-current path takes `ranked.first` unconditionally (`PresetScorer.swift:67-80`, `ReactiveOrchestrator.swift:208-227`).
- **Zero-duration track → unscored `catalog.first` fallback** bypassing every exclusion gate, can install a diagnostic preset (D-074 violation) (`SessionPlanner+Segments.swift:109-129`).
- **Mood-override cooldown never reset** across repeat plays/sessions — override effectively permanently dead from a track's second play (`LiveAdapter.swift:180-385`).
- **Unbounded in-memory StemCache** (~7 MB/track, no eviction; disk sibling has a 500 MB LRU cap) (`StemCache.swift:76`).
- **OAuth correctness (re-entrant `login()` leak, refresh double-spend, P3 hardening)** — ✅ **RESOLVED 2026-06-14 (CLEAN.2.2, commit `13cec8b`, integrated `a6f1288`).** Matt's live check passed: Spotify playlist loaded with no problems on the integrated `main` build — the refresh path exercised end-to-end against real Spotify, no regression. The fresh-login `state` guard is unit-test-proven + standard OAuth on unchanged callback routing (accepted without a forced interactive login per Matt 2026-06-14, since a silent refresh does not hit the consent round-trip). `SpotifyOAuthTokenProvider`: a second `login()` while one was pending overwrote `pendingContinuation` (orphaning the first caller until the 5-min timeout) + armed a stray timeout against the wrong attempt → now coalesces concurrent logins onto one in-flight attempt (`pendingContinuations` array; `finishLogin()` cancels the timeout on every resume path); concurrent `acquire()` each fired their own silent refresh, double-spending the rotating refresh token → now dedups onto a single in-flight `refreshTask`; + P3s (OAuth `state` CSRF/replay guard, form-body percent-encoding of `+ & = /` that `.urlQueryAllowed` leaked, Keychain-save failures logged not swallowed, callback `scheme == phosphene` + host validation). `SpotifyOAuthTokenProviderTests` green (4 new regressions).
- ✅ **RESOLVED (CLEAN.2.1, 2026-06-14)** — Spotify client secret baked into the built Info.plist. Removed `SpotifyClientSecret` from `Info.plist` + `Phosphene.xcconfig` and deleted its only consumer, the D-068 client-credentials `DefaultSpotifyTokenProvider`. The production flow already used OAuth Authorization Code + PKCE (`SpotifyOAuthTokenProvider`), which needs no secret; no build-bundled secret remains. OAuth login E2E confirmed by Matt 2026-06-14 on the integrated `main` build (no regression). See `RELEASE_NOTES_DEV.md [dev-2026-06-14-d]`.
- ✅ **RESOLVED (CLEAN.2.3, 2026-06-14)** — honest-UI dead controls (audit T5), each Matt's product call. **2.3.1:** the "Use Apple Music instead" no-op `{ }` cross-link (+ its dismiss-only mirror) now drive a real `NavigationStack` switch via `ConnectorPickerViewModel.switchConnector(to:)` (wire). **2.3.2:** the `.localFile` "coming later" capture mode (lying + no-op) removed — enum case, picker row, false string, and the now-unreachable reconciler/coordinator branches (remove; supersedes the `.localFile` branch of D-052). **2.3.3:** the disabled "Swap preset" context-menu stub hidden behind `#if ENABLE_PRESET_SWAP` until U.5b (hide). Commits `7800b72` / `d40cfad` / `6e983c8`. `RELEASE_NOTES_DEV.md [dev-2026-06-14-f]`.
- ✅ **RESOLVED (CLEAN.2.3.4, 2026-06-14)** — localization gate only scanned `PhospheneApp/Views/`. `check_user_strings.sh` ROOTS widened to `PhospheneApp/ViewModels` + `ContentView.swift`, pattern extended with a connection-state `.error("…")` arm (`logger.error` excluded); the bypassing copy (Spotify/AppleMusic error strings, ConnectorType tiles, ReadyViewModel duration/source, ContentView fallback, PreparationProgressView subtitle, PlanPreviewTransitionView labels) externalized to `Localizable.strings`. Gate header documents its honest scope limit (literal-prefix matcher — lowercase/interpolated fragments still rely on review). Commit `46d836b`.

P3 categories indexed in the audit doc: ~25 latent bugs (incl. OAuth refresh double-spend + form-encoding gaps [Resolved CLEAN.2.2, see above], PSO cache key, mv_warp buffer(5) omission, PostProcessChain texture aliasing, malformed-sidecar swallowing, Arachne listening-pose FA #57-gate, >2-channel LF corruption, ~94 Hz vs 60 fps chroma hysteresis), ~11 perf items (autocorrelation 2×/frame, drums FFT 2×/frame, mono STFT 2×/track, serial prep pipeline, wasted particle-mode warp pass, unconditional feedback textures), dead code, and 6 in-code doc-drift items.

---

### BUG-050 — Always-on session recorder ~doubles per-frame CPU (encode stacked on render); ungated in normal use (2026-06-14)

**Severity:** P2 (no fps/correctness impact — render alone holds ~52 % of the 60 fps frame budget and 60 fps holds; the cost is sustained extra CPU/power/heat, ~2 cores on the Mac mini, for the entire duration of every session).
**Domain tag:** resource-management / performance
**Status:** Open — **diagnosed 2026-06-14 from session artifacts; no fix yet (Matt's option A: keep recording on while in active use, fix the per-frame capture/encode properly when prioritized).** Surfaced when Matt's Activity Monitor read PhospheneApp at ~99–115 % during the BUG-033 validation.
**Introduced:** the SessionRecorder video-capture path; instantiated unconditionally (`VisualizerEngine.swift:785`, `SessionRecorder()` with `enabled: true` default) — no production gate.
**Resolved:** —

**Expected:** the diagnostic session recorder adds modest overhead; it should not roughly double the app's CPU in normal use.
**Actual:** the recorder runs every session (ungated). Its per-frame `encode_cpu_ms` (~7–9 ms — drawable→pixel-buffer capture + AVAssetWriter feed) is **additive** to `renderframe_cpu_ms` (~8.6 ms): `frame_cpu_ms` ≈ encode + render ≈ 15.8 ms ≈ a full 60 fps budget → ~1 core for the frame path, plus audio/main threads → Activity Monitor ~99–115 %. Encode is on its own thread, so it does not (much) cost frame rate — render alone is ~52 % budget and 60 fps holds for 98.8 % of frames — the impact is sustained CPU/power/heat. Compounded by BUG-039 (the same recorder's video writer dying + restarting, hitting its 8/8 cap on macOS 26.5 / M2 Pro).
**Reproduction steps:** play any session; Activity Monitor shows PhospheneApp ~99 %+. Confirmed from artifacts: `~/Documents/phosphene_sessions/2026-06-14T17-58-44Z/features.csv` — `frame_cpu_ms` mean 15.78 (encode 7.16 + render 7.10); in the two 30 s windows where the writer was dead between BUG-039 restarts, `encode_cpu_ms` → ~0.6 and total CPU halved to ~9 ms.
**Session artifacts:** `2026-06-14T17-58-44Z/features.csv` (per-frame `frame_cpu_ms` / `encode_cpu_ms` / `renderframe_cpu_ms` breakdown).
**Suspected failure class:** `resource-management`.
**Verification criteria (for the eventual fix):**
- [ ] Either the per-frame capture/encode is moved fully off the render-adjacent path / made cheaper (throttled or lower-cost pixel capture) so total `frame_cpu_ms` ≈ `renderframe_cpu_ms`, OR recording is gated off by default with an explicit per-session enable.
- [ ] Activity Monitor steady-state CPU in normal use roughly halves vs the current ~99 %.
- [ ] 60 fps unaffected; the session-artifact recordings (features.csv / stems.csv / video) remain available when recording is enabled.

---

### BUG-034 — `sceneParamsB.z` double-booked (ambient vs D-057 step multiplier): every ray-march fixture renders at 32 steps vs live's 128 (2026-06-09)

**Severity:** P1 (test/prod parity, FA #66 class — golden hashes, RENDER_VISUAL contact sheets, and certification evidence for every ray-march preset are generated at 1/4 the live step budget).
**Domain tag:** renderer / preset.fidelity / test-isolation
**Status:** **Resolved 2026-06-12** — `[BUG-034]` increment on the worktree branch (commits: harness baseline coverage `9f25584c` → fix `e2c58905` → parity tests `5fb2035e` → harness production-parity `1a16411e` → golden regen + docs).
**Introduced:** D-057 frame-budget multiplier was packed into the slot `PresetDescriptor+SceneUniforms` already used for `sceneAmbient`.
**Resolved:** 2026-06-12. `sceneParamsB.z` is single-meaning: the D-057 step multiplier, defaulted to 1.0 by `makeSceneUniforms()` and `SceneUniforms()` so fixtures march the live 128-step budget by construction (no slot move needed — Task 1 audit found `.w` is SSGI's radius override, not free, and ambient had no consumer anywhere). Slot-map contract documented at the `SceneUniforms` definition. The M7-lite review also exposed that the deferred ray-march visual harness bound none of noise/IBL/SSGI/post-process/height-texture — upgraded to production-parity bindings (Matt-approved scope extension, mirrors the FerrofluidOceanVisualTests round-56/57 pattern). Certified presets: Lumen Mosaic provably unaffected (byte-identical pairs); Ferrofluid Ocean — Matt accepted live-path-unchanged (2026-06-12), no re-certification.

**Expected:** fixtures march the same step budget the live app uses.
**Actual:** `makeSceneUniforms()` (`PresetDescriptor+SceneUniforms.swift:99`) packs `sceneAmbient` (default 0.1) into `sceneParamsB.z`; the G-buffer preamble (`PresetLoader+Preamble.swift:417`) reads `.z` as the D-057 step multiplier: `clamp(0.1, 0.25, 1.0) = 0.25` → `maxMarchSteps = 32`. The live path overwrites `.z = 1.0` per frame (`RenderPipeline+RayMarch.swift:118`) → 128 steps. `PresetAcceptanceTests`, `PresetVisualReviewTests`, `PresetRegressionTests`, and `PresetContrastCertificationTests` all bind raw `makeSceneUniforms()` output. Corollary: the `scene_ambient` JSON sidecar field never reaches any shader on the live path — dead config + doc drift in `PresetDescriptor`.
**Reproduction steps:** render any ray-march preset via the fixture helper and via the live path; compare step counts (or diff a contact-sheet frame against a live capture at identical inputs).
**Session artifacts:** `docs/diagnostics/CODE_AUDIT_2026-06-09.md` §A6; before/after pairs `/tmp/phosphene_visual/BUG-034_pairs/` (M7-lite reviewed by Matt 2026-06-12); FBS pulse-gate A/B frames `/tmp/phosphene_visual/fbs_pulse/`.
**Fallout (resolved in-increment, Matt-approved):** `FerrofluidPulseLivePathTests` (FBS D-153/D-160 gate) had thresholds calibrated against the pre-fix 32-step render — its S1 region-MEAN measure only registered the punch because false sky broke the D-157 steady-global-luminance contract. Recalibrated at the production budget: S1 switched to the paired per-pixel |δ| measure (punch 2.46 vs rest exactly 0.0; floor 1.0), S2 loud/quiet ratio floor 1.8× → 1.2× (measured 1.38×; the height scaling itself is Matt-validated live, D-160). `FBS_PULSE_DUMP=1` now dumps the measured frames for eyeball verification.
**Suspected failure class:** `test-isolation` (FA #66 class) + `api-contract` (slot double-booking).
**Verification criteria:**
- [x] Automated: fixture and live path march identical step budgets by construction — `StepBudgetParityTests` (parity 128 == 128 derived through both code paths; default-1.0 guard). A/B-proven: temporary revert of the packing line turns both red (32 ≠ 128).
- [x] Golden-hash regen across all ray-march presets with before/after contact sheets — pairs reviewed by Matt (M7-lite, 2026-06-12) on the production-parity harness; KS + VL regenerated (10–13 bit drift), Glass Brutalist within tolerance (kept), Lumen Mosaic byte-identical, Ferrofluid golden already retired (D-124).
- [x] `scene_ambient` — **removed as dead config** (Task 1(b): no shader on any path consumed it; every `ambient` term in Metal is sky/IBL-derived). Removed from schema, `PresetDescriptor`, all five sidecars, SHADER_CRAFT §17 + prose, `Metals.metal` comment. A future ambient control starts at the design seat with a D-### and a consumer.

---

### BUG-035 — NoveltyDetector re-detects every section boundary ~4-5× after the similarity ring wraps; structural prediction (D-151 consumer) degraded (2026-06-09)

**Severity:** P2 (corrupts `StructuralAnalyzer` section durations / `predictedNextBoundary` / section confidence — the exact signal Skein.ENGINE.3 just wired live for Skein.5).
**Domain tag:** dsp.structure
**Status:** **Resolved 2026-06-09** — fixed as the `[BUG-035]` increment immediately before Skein.5 (single-increment P2 fix; evidence pre-documented in the audit doc).
**Introduced:** structural — `detectedBoundaries` stores logical ring indices that go stale as the ring slides.
**Resolved:** 2026-06-09, `[BUG-035]` commit on local main. `SelfSimilarityMatrix.totalFrameCount` (monotonic frames-added counter) + `NoveltyDetector` stores/dedups in **absolute** frame-index space (`Boundary.frameIndex` is now absolute); `MIRPipeline.latestStructuralPrediction` write moved under the lock. A/B-proven: `noveltyDetect_ringWrap_boundaryRegistersOnce` (pre-fix 3 dups, identical timestamps) + `structuralAnalyzer_ringWrap_boundaryRegistersOnce` (production 600-frame geometry, pre-fix 2 dups); post-fix exactly 1 each. `SkeinStructureSignalTests` + AABA golden regression green. Manual criterion (features.csv section plausibility on a real session) folds into Skein.5's M7 session review.

**Expected:** each real musical section boundary registers once.
**Actual:** `SelfSimilarityMatrix` logical indices slide ~30 per `detect()` call once `storedCount == maxHistory` (`SelfSimilarityMatrix.swift:198-203`); `NoveltyDetector.swift:217`'s `tooCloseToExisting` compares fresh indices against the stale stored ones, so the same boundary passes the dedup again every ~1.3 s (~94 Hz analysis rate) — ~4-5 near-equal-timestamp duplicates per real boundary (`timestampForFrame` compensates for the slide, so duplicates carry ~equal timestamps). `StructuralAnalyzer.registerBoundary` appends unconditionally → section durations collapse toward 0, `avgDuration`/`predictedNextBoundary` garbage, `sectionIndex` inflates ~5×, confidence structurally depressed.
**Related:** `MIRPipeline.swift:277` — `latestStructuralPrediction` is the only published property written outside the lock (move under the lock in the same increment; class is `@unchecked Sendable`).
**Reproduction steps:** run any track past `maxHistory` frames; log `registerBoundary` calls — clusters of ~equal timestamps appear per real boundary.
**Session artifacts:** `docs/diagnostics/CODE_AUDIT_2026-06-09.md` (Audio/DSP P2 section).
**Suspected failure class:** `algorithm` (stale-index dedup).
**Verification criteria:**
- [x] Automated: each detected boundary registers exactly once across the ring slide (absolute frame counter dedup) — `noveltyDetect_ringWrap_boundaryRegistersOnce` + `structuralAnalyzer_ringWrap_boundaryRegistersOnce`, both A/B-proven against pre-fix source.
- [x] Automated: `latestStructuralPrediction` write moved under the lock (`SkeinStructureSignalTests` green).
- [ ] Manual: section indices/durations from a real session's `features.csv` are musically plausible (no sub-second "sections") — **evaluated 2026-06-10 (session `03-09-20Z`, the first with the Skein.5.2 columns): NOT plausible — but via a DIFFERENT mechanism than BUG-035** (a live-edge peak registered anew every ~4 detect intervals, not the same boundary re-admitted by ring slide; the BUG-035 A/B regression tests stay green). Criterion superseded by **BUG-040**.

---

### BUG-036 — Heap allocations on the real-time Core Audio thread at three sites (FFTProcessor, AudioBuffer.latestSamples, SessionRecorder raw tap) (2026-06-09)

**Severity:** P2 (violates the standing "do not allocate in the Core Audio IO proc callback" rule on every callback of every session; priority-inversion / glitch risk under memory pressure rather than observed breakage).
**Domain tag:** audio.capture / performance
**Status:** Open — audit finding.
**Introduced:** structural — predates the rule's enforcement attention; the "zero-alloc" header comments in both DSP files are currently false.
**Resolved:** —

**Expected:** the IO-proc path allocates nothing (CLAUDE.md What-NOT-To-Do).
**Actual (all three verified on the IO-proc call path via `VisualizerEngine+Audio.makeAudioSampleCallback`):**
1. `FFTProcessor.swift:149,193` — `process()` allocates a fresh `magnitudes` array per call; `processStereo` allocates a fresh `mono` array (called at `VisualizerEngine+Audio.swift:114`).
2. `AudioBuffer.swift:148` — `latestSamples` does 2048 per-element ring reads (`UMARingBuffer.read(at:)` precondition + modulo each) + an allocating `append` loop **under the same NSLock the write path takes**, per callback (`VisualizerEngine+Audio.swift:111`). RMS over the same samples is also computed 3× per callback (AudioBuffer `:179`, SilenceDetector `:106`, InputLevelMonitor `:185`).
3. `SessionRecorder+RawTap.swift:28` — `Data(bytes:count:)` copy + `queue.async` closure allocation per callback for the first 30 s of every session (entire session under `PHOSPHENE_FULL_RAW_TAP=1`).
Related P3 (same rule, rarer path): `AudioInputRouter+SignalState.swift:45` — tap-reinstall scheduling (locks, `DispatchWorkItem` alloc, os_log interpolation) runs on the RT thread on silence transitions.
**Session artifacts:** `docs/diagnostics/CODE_AUDIT_2026-06-09.md` (Audio/DSP P2 section).
**Suspected failure class:** `resource-management` (RT-safety).
**Verification criteria:**
- [ ] Automated: allocation-free assertions or code-shape tests on the three sites (pre-allocated members / `latestSamples(into:)` segment-memcpy variant / pre-allocated ring for raw-tap).
- [ ] Manual: a full session with the os allocator instrumented shows zero mallocs attributable to the IO-proc path.

---

### BUG-037 — Arachne spiral chord-count contract three-ways inconsistent (CPU 200 / shader 441 / test 104): spiral builds to ~45 % then pops to complete (2026-06-09)

**Severity:** P2 (visible build defect: per-chord reveal gate saturates at 200/441 ≈ 0.45, then the `.stable` snap shows the remaining ~55 % in one frame; build cycle halves to ~62 beats vs the documented ~136, firing `_presetCompletionEvent` early).
**Domain tag:** preset.fidelity (Arachne)
**Status:** Open — audit finding.
**Introduced:** post-BUG-011 ranges (`radialCount`/`spiralRevolutions` ∈ [18, 24], `ArachneState._reset()` :1086-1087) made the uncapped chord product 324-576, so the `min(200, …)` cap at `recomputeSpiralChordTable()` (`ArachneState.swift:1005`) **always** fires; the shader normalizes `spiral_packed / 441.0` (`Arachne.metal:1336`); `PresetAcceptanceTests.swift:335` uses a third value (104).
**Resolved:** —

**Expected:** spiral chords reveal continuously outside-in to completion (D-095 per-chord gate), with the documented ~92 s round-8 build cycle.
**Actual:** `fgProgress` saturates at ~0.45 → ~45 % of chords visible, then a one-frame pop to complete; `spiralChordRadii` truncates at radius ≈ 0.27 instead of reaching the 0.05 core.
**Reproduction steps:** run Arachne through a full build cycle (live or `PresetVisualReviewTests` frame phase); watch chord coverage vs `frame_progress`.
**Session artifacts:** `docs/diagnostics/CODE_AUDIT_2026-06-09.md` (Presets P2 section).
**Suspected failure class:** `api-contract` (three uncoordinated constants for one contract).
**Verification criteria:**
- [ ] Automated: one shared constant (or CPU-published total) consumed by CPU table, shader normalization, and tests; test asserts the uncapped product is honoured (or the cap is propagated).
- [ ] Manual/visual: contact-sheet build sequence shows continuous chord reveal to the core with no completion pop.

---

### BUG-042 — Structural sections are still ~1.5 s on real music: the analyzer's GEOMETRY is note-scale (6.4 s window, 85 ms checkerboard), not section-scale — and post-BUG-040 confidence now endorses the junk (2026-06-10)

**Severity:** P2 (the Skein.5 structure sub-feature and the orchestrator's `StructuralPrediction` consumer act on a boundary every ~1.5 s with confidence 0.85–1.00 — worse than pre-BUG-040, where low confidence at least kept the gates shut).
**Domain tag:** dsp.structure
**Status:** Open — verified from session artifacts (the Skein.5.2 columns doing their job again). **2026-06-11 (BUG-046):** the Skein consumer is now guarded against the junk (10 wall-s boundary spacing in `SkeinState`, landed pre-certification); the orchestrator's `StructuralPrediction` consumer still rides it — fixing the detector geometry remains this bug's scope.
**Introduced:** structural — the analyzer's defaults were sized for a different feature rate; at the live ~94 Hz analysis rate the geometry detects note/bar novelty, not sections.
**Resolved:** —

**Expected:** musical sections of 15–60 s with confidence that reflects real form.
**Actual (session `2026-06-10T17-39-41Z`, 6 streaming tracks):** boundaries every **1.3–2.5 s** on every track (Love Rehab: 30 in ~50 s), `section_start_s` now sane and durations now CONSISTENT — so duration-consistency-driven confidence climbs to **0.85–1.00** and the Skein conf gate opens on junk (the exact risk noted in the BUG-040 fix rationale).
**Why BUG-040's fixes were insufficient:** all three were real (frozen clock, live-edge dedup escape, no absolute floor) but operate at the wrong SCALE. `maxHistory = 600` frames at ~94 Hz = a **6.4-second** similarity window; `kernelHalfWidth = 8` frames = **85 ms** checkerboard blocks. An 85 ms before/after comparison inside a 6.4 s memory detects fills, chord changes and transients — every one a "boundary." The `minNoveltyFloor = 0.02` was calibrated on a smooth synthetic fixture (junk ≈ 0.0003); real music's frame-to-frame chroma variance puts baseline novelty far above it. The 1.3–2.5 s cadence = peaks admitted as fast as `minPeakDistance` (120 frames ≈ 1.28 s) allows.
**Reproduction steps:** any real track ≥ 1 min; read the section tail columns — index inflates every ~1.5 s with high confidence.
**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-10T17-39-41Z/features.csv` (cols 53–55).
**Suspected failure class:** `calibration` (detector geometry vs feature rate).
**Proposed direction (next increment):** run the STRUCTURAL feature stream at section scale — aggregate the 16-dim feature vector to ~2 Hz (mean over ~0.5 s) before it enters the similarity matrix. The same code then gives: 600-frame ring = **5 minutes** of memory, 8-frame kernel = **4-second** checkerboard blocks, `minPeakDistance` retuned to ~16 (≈ 8 s minimum section). Re-calibrate `minNoveltyFloor` against REAL session feature streams (replayable from raw_tap/preview audio), not synthetic fixtures. The Skein conf-gate thresholds stay; the existing BUG-035/040 regression tests must be re-expressed at the new rate.
**Verification criteria (before any fix):**
- [ ] Automated: a real-audio-derived feature stream (fixture from a recorded session) yields plausible section counts (1–6 per 3–5 min track) with multi-second-to-minute durations.
- [ ] Automated: BUG-035 (ring-wrap dedup) + BUG-040 (edge guard / floor / clock) regression tests green at the new feature rate.
- [ ] Manual: a live session's section columns show 15–60 s sections; confidence high only on genuinely sectional material.

---

### BUG-043 — Mid-playback analysis stall: a 9.6 s gap between analysis frames froze the visuals then lurched (2026-06-10)

> **Renumbered from BUG-042** (parallel-session number collision, 2026-06-10): BUG-042 = the structural-section geometry defect, filed earlier the same day. The FBS.S3.2 commit message references the old number.

**Severity:** P2 (a multi-second visual freeze + lurch mid-track; observed once, plus a 40 s gap during the silent prep window of the same session).
**Domain tag:** `pipeline-wiring` (audio-analysis cadence) — possibly BUG-039-adjacent (the video-writer stall instrumented the same week).
**Status:** Open — observed + filed; not yet instrumented/diagnosed.
**Resolved:** —

**Expected:** analysis frames arrive continuously (~60 Hz) for the whole session; `deltaTime` stays ~0.017 s.

**Actual (session `2026-06-10T17-50-56Z`, Love Rehab):** three gaps clustered at te 28.8–29.7 s — `deltaTime` 0.44 s, 0.33 s, then **9.59 s** — with a 50 ms CPU frame. During a gap the renderer keeps drawing the STALE FeatureVector (frozen pulse/features), then everything jumps at once when analysis resumes — Matt's "flashing around 30 s" on this track matches the gap end. The same session's silent prep window had a 40.4 s gap (may be benign idling — undetermined). The track also re-segmented mid-play (a second te-reset ~50 s in — cause undetermined, possibly a user restart).

**Reproduction steps:** unknown trigger — scan any session's `features.csv` for `deltaTime > 0.2` during audible playback.

**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-10T17-50-56Z/features.csv` (Love Rehab segment, te 28.8–29.7).

**Suspected failure class:** `resource-management` or `concurrency` (analysis-queue starvation / tap callback stall). The PERF-era "probably-environmental CPU bump" family is a prior with a similar smell.

**Verification criteria (when fixed):**
- [ ] Instrumentation: a log line whenever inter-analysis-frame dt exceeds 0.25 s during audible playback (with queue depths / tap callback timing).
- [ ] No dt > 0.5 s gaps during audible playback across a full session.

**Manual validation required:** Only if reproducible.

**Related:** BUG-039 (video-writer stall instrumentation), the PERF.2 "CPU bump" characterization (probably-environmental), FBS (a gap freezes the pulse and every other feature — any preset lurches at gap end).

### BUG-041 — FFO aurora flashes at track start: the drums-stem deviation driver overswings 1.2–3.3× during the per-track analyzer cold start (2026-06-10)

**Severity:** P2 (visible flashing in the first ~10 s of affected tracks on FFO; Matt flagged it on So What, There, There, and Lotus Flower in session `2026-06-10T14-55-32Z`). Same cold-start-deviation family as BUG-027/AGC2.4.1 (fixed for the FeatureVector band devs) — this is the STEM-side twin reaching the GPU through the aurora.
**Domain tag:** `dsp.stem` (deviation cold start) + `preset.fidelity` (FFO aurora intensity).
**Status:** **Fix landed 2026-06-10 (FBS.S2.2), then EXTENDED same day (FBS.S3.2)** after Matt's next read showed flashing at MID-TRACK timestamps too (session `17-50-56Z`: every flagged time coincides with an all-stem deviation burst, 3–30× track median — So What reached dev = 35). The track-start warmup was correct but insufficient in scope: the driver's response itself is now flash-proof — soft-knee input (`dev/(1+0.6·dev)`: musical values pass, bursts cap — 35 → 1.64) + asymmetric response (rise τ 0.45 s = a bloom, fall τ 1.2 s = afterimage), warmup gate retained. Gates: max per-frame output step ≤ 0.08 across the full So What series incl. the 35× burst; legacy-driver red arm proves the fixtures carry the defect. **Awaiting Matt's M7.** *(Note: dev = 35 is itself anomalous — deviation primitives normally max ~3.4; a StemAnalyzer EMA divide-by-tiny is suspected upstream and worth its own look. The soft knee defends the aurora regardless.)*
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

### BUG-038 — Ray-march light-intensity flickers 7–9 steps/sec (BUG-019 residual: beat-onset brightness term fires ~97% of frames) (2026-06-09)

**Severity:** P1 (chronic visible artifact across all ray-march presets; the symptom Matt has reported "since FFO existed" — a strobe that blocks fair evaluation of FFO and any beat-sync work). Continuation of **BUG-019** (PERF.3 reduced it 76→53–60 oscillation events but did not eliminate it).
**Domain tag:** `renderer` (light-intensity modulation) + `dsp.beat` (beat-onset signals near-constant).
**Status:** **Fix landed (FBS pre-step), automated validation green; awaiting Matt's M7** (visual confirm the flicker is gone). Local worktree branch — **not yet on `main`/his build** (see Related).
**Introduced:** structural — `applyAudioModulation` (`RenderPipeline+RayMarch.swift`, preset-agnostic for all ray-march presets) set light intensity = `base × (1 + f.bass·0.4 + beatAccent·0.15)` *per frame with no temporal smoothing*. `beatAccent = max(beatBass, beatMid, beatComposite)` fires on ~97% of frames on real sessions (a near-constant jitter, not clean beats), and `f.bass` is noisy → the whole scene's brightness steps frame-to-frame.
**Resolved:** — (code fixed; pending M7)

**Expected:** scene brightness is steady, brightening/dimming smoothly with the music's energy — no per-frame stepping/strobe.

**Actual (sessions `2026-06-09T21-23-07Z` streaming + `21-19-14Z` clean local):** the light multiplier takes a perceptible single-frame step (|Δ| > 0.05) **7–9 times/sec on every streaming track and ~7/sec on clean-signal Cherub**; the beat-onset term fires on **96–98% of frames** (near-constant, not on beats). Visible as a constant light flicker (Matt flagged it on Lotus Flower and "some other tracks"). Present on clean signal too → not a weak-signal artifact.

**Reproduction steps:** play any session; per frame compute `1 + clamp(bass)·0.4 + clamp(max(beatBass,beatMid,beatComposite))·0.15` from `features.csv`; count frames with frame-to-frame |Δ| > 0.05 → ~8/sec. (`tools/fbs/` brightness analysis.)

**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-09T21-23-07Z/features.csv` (all 6 streaming tracks), `21-19-14Z/features.csv` (Cherub clean). Beat-term firing rate 96–98%.

**Suspected failure class:** `render-state` (no temporal smoothing on a per-frame light uniform) compounded by `algorithm` (beat-onset signals near-constant, so they add jitter not beats).

**Fix (FBS pre-step):** temporally smooth the light multiplier with an EMA (`RayMarchPipeline.smoothLightIntensity`, τ ≈ 0.12 s) before writing the light uniform. Drops perceptible steps **~8/sec → ~0** (verified on all 4 sessions) while preserving the slower musical brightness swell. **Mean-preserving + preset-agnostic → no certified-preset (Nimbus) regression**; the PERF.3 formula is unchanged, only low-passed. First frame after preset-load/stall (`dt ≤ 0`) returns the target verbatim → no startup lag and single-frame golden hashes unchanged.

**Verification criteria:**
- [x] **Automated (pure-function):** `RayMarchPipelineTests.test_smoothLightIntensity_suppressesFrameToFrameFlicker` — synthetic jittery target (mimics the 97%-firing beat + bass noise) → smoothed output < 5 steps over 600 frames (raw > 400), still tracks the slow swell. `_firstFrameHasNoLag` covers `dt ≤ 0`.
- [x] **Regression:** `PresetRegressionTests` golden hashes unchanged (single-frame, dt=0 = target = pre-fix value); full ray-march/FFO/acceptance suites green.
- [ ] **Manual (M7):** Matt confirms FFO (and other ray-march presets) no longer flicker — steady lighting through a continuous-playback session. *Requires the fix to reach his build (see Related).*

**Manual validation required:** Yes — it's a felt visual artifact; only a human can confirm the strobe is gone.

**Related:**
- **BUG-019** — the original beat-dominant-brightness flicker (`0.4 + beatPulse·2.6`); PERF.3 fixed the worst of it but left this residual (still had a beat term + no smoothing). This is its continuation.
- **FBS** (Ferrofluid Beat Sync) — done as the pre-step so FFO has a steady baseline to evaluate the new beat pulse against (Matt's call, 2026-06-09). The noisy beat-onset signals are also *why* FBS times its pulse off the steady tempo grid, not these signals.
- **Worktree → build:** the fix is on branch `claude/intelligent-shirley-1ce3b4`; Matt's build runs `main`. Must integrate to local `main` (or have him build the branch) before the M7 — else he tests stranded old code (`feedback_worktree_changes_reach_build`).

---

### BUG-039 — Session video stops appending silently a few seconds into some sessions (intermittent; recorder keeps "running") (2026-06-09)

**Severity:** P2 (the session video is the primary M7 review artifact; a truncated video forces CSV-only reconstruction of visual defect reports — it directly degraded the Skein.5 M7 session review).
**Domain tag:** `resource-management` (session recorder / AVAssetWriter)
**Status:** **Diagnosed + recovery landed 2026-06-10 (FBS session); awaiting confirmation on the next live session.** The instrumentation caught the death certificate live in `2026-06-10T17-50-56Z`: the writer left `.writing` **10 s after lock** with `AVFoundationErrorDomain -11800 (AVErrorUnknown)` / underlying `NSOSStatusErrorDomain -16341` — an UNDOCUMENTED OSStatus (Apple forums confirm this -11800+mystery-status class is an intermittent encoder/format session failure; notably this was also the session with the BUG-042 analysis stalls — co-occurrence noted, causality unproven). Since the trigger is undocumented and intermittent, the durable fix is RECOVERY, not decoding: on writer death the partial file is retained (playable to its last 5 s fragment per BUG-022), the recorder **rolls to a new segment file** (`video_2.mp4`, `video_3.mp4`, …) within one frame, and recording resumes — bounded at 8 restarts/session. A session now never loses more than ~one fragment of video per death. Regression-locked by `test_videoWriterDeath_rollsToNewSegment_bothFilesReadable` (kills the live writer the way the field failure does — status leaves `.writing` with the file retained — and asserts both segments exist + the recovery segment is a readable video + the restart is logged).
**Introduced:** unknown — intermittent; possibly long-standing (older sessions are mostly long-form, but `17-14-25Z` truncated at 15 s).
**Resolved:** —

**Expected:** `video.mp4` covers the whole session (BUG-022 fragmented MP4: at minimum up to the last 5 s fragment at abnormal exit).
**Actual:** intermittent early freeze with the recorder otherwise healthy: `2026-06-09T22-35-09Z` video froze at **120 frames / 5.005 s** (file mtime = session start + ~1 min) while features.csv/stems.csv/log ran the full ~10 min; `17-14-25Z` froze at **15.0 s** of a ~6 min session. Other same-day sessions are long (`21-23-07Z` 294.6 s, `13-06-15Z` 393.3 s). No `video frame skipped` / relock / error lines in any affected log — the writer locked (`video writer locked to 900x600 after 30 stable frames`) and then appends stopped through one of the SILENT paths.
**Reproduction steps:** not yet reproducible on demand (intermittent). Affected-session signature: `video.mp4` duration ≪ session length + zero video log lines after the lock line.
**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-09T22-35-09Z` (5.005 s of ~10 min), `17-14-25Z` (15.0 s of ~6 min); compare `21-23-07Z`/`13-06-15Z` (long).
**Suspected failure class:** `resource-management`. Candidate silent paths (all at `SessionRecorder+Video.swift` pre-instrumentation): (a) `videoInput.isReadyForMoreMediaData == false` persisting (typically means the writer stopped consuming — e.g. `status == .failed`); (b) `adaptor.append(...)` returning `false` with the result IGNORED (a failed append usually moves the writer to `.failed` permanently); (c) pixel-buffer pool exhaustion. A `.failed` writer was never detected anywhere — video stayed dead for the rest of the session with zero log output.

**Instrumentation landed (this increment — root-cause fix follows the next affected session):**
- Writer status checked per frame: a non-`.writing` writer logs ONE loud line with `writer.error` and stops attempting appends — **without deleting the partial file** (the fragmented MP4 keeps everything up to the last 5 s fragment).
- `isReadyForMoreMediaData == false`, pool failures, and `append == false` each log throttled counters with `writer.status` + `writer.error`.

**Verification criteria:**
- [ ] Diagnosis: the next affected session's `session.log` names the failing path + `writer.error` (instrumentation criterion).
- [ ] Fix (subsequent increment): a full-length session video after the root-cause fix; affected-session signature no longer occurs across a multi-session week.
- [ ] Partial-file retention: an affected session still yields a playable partial `video.mp4` (no deletion on failure).

**Observation log:** `2026-06-10T03-09-20Z` (first session WITH the instrumentation): full-length video (333.6 s of a 335 s session), no stall — the defect did not fire. Still awaiting the first instrumented affected session.

---

### BUG-040 — NoveltyDetector registers a live-edge boundary every ~4 detect intervals on real music: sections of ~1.3–1.6 s, negative `section_start_s`, confidence pinned low (2026-06-10)

**Severity:** P2 (the structural signal D-151 delivers to Skein.5 is unusable on real music — every track reads as 20–35 "sections"; the Skein.5 confidence gate (smoothstep 0.25→0.55) correctly suppresses the visual bias, so the painting is unharmed, but the structure sub-feature is effectively INERT. Discovered the first day the Skein.5.2 columns existed — the instrumentation did its job.)
**Domain tag:** dsp.structure
**Status:** **Resolved 2026-06-10** (`[BUG-040]` fix increment — single-increment P2 per protocol; evidence was pre-filed).
**Introduced:** structural — distinct from BUG-035 (which is fixed and stays fixed: its mechanism was the SAME physical boundary re-admitted as the ring slid; this is a NEW boundary registered near the live edge over and over).
**Resolved:** 2026-06-10, `[BUG-040]` commit on local main. THREE compounding causes, all fixed:
1. **The frozen clock (the dominant cause of the timestamp/confidence symptoms):** the live analysis loop hardwires `time: 0` into `MIRPipeline.process` (`VisualizerEngine+Audio.processAnalysisFrame` — fv.time is populated separately), so the structural analyzer's clock never advanced: timestamps = `0 − age ≈ −0.3 s` (the exact observed −0.13…−0.77 range), durations were ±0.x noise, confidence pinned. Fix: `updateStructuralAnalysis` now clocks the analyzer from the pipeline's own track-relative `elapsedSeconds` (which resets exactly when `structuralAnalyzer.reset()` fires), never from the caller's `time` parameter.
2. **The live-edge peak:** on constantly-evolving real music the checkerboard response forms a local max at the newest valid window position; its ABSOLUTE index advances with the stream and escaped the (BUG-035-fixed) dedup every ~4 detect calls. Fix: edge guard — detection is restricted to the interior region (≥ `minPeakDistance` frames of after-context); a true boundary registers exactly once, ~2 s late (negligible at section timescale).
3. **The relative-only threshold:** mean + 1.5σ admits noise-scale "peaks" on smooth material (measured junk scores ~0.0003 vs ~0.43 for a real A→B boundary — three orders of magnitude apart). Fix: an absolute novelty floor (`minNoveltyFloor = 0.02`, ~66× the junk / ~20× under a real boundary) ANDed with the adaptive threshold.

**Expected:** a ~45–55 s pop track registers 1–4 section boundaries with multi-second durations and confidence that climbs on regular material.
**Actual (session `2026-06-10T03-09-20Z`, 6 streaming tracks, the audit catalog):** every track registers a boundary every **~1.3–1.6 s** (Love Rehab: 33 "sections"; Lotus Flower: 36) — the cadence ≈ **4 × the 30-frame detect interval**, exactly the spacing at which a peak whose ABSOLUTE index advances with the stream escapes the 120-frame dedup window. `section_start_s` is **negative** (−0.13…−0.77) essentially always — the registered timestamps sit "just before now," consistent with a peak at the newest edge of the novelty window plus a timestamp/fps skew. `section_confidence` is structurally pinned ≤ 0.30 (sub-second duration variance ⇒ near-zero duration consistency; brief 0.70/0.90 spikes on two tracks).
**Reproduction steps:** play any real track ≥ 1 min; read the `section_index`/`section_start_s`/`section_confidence` tail columns (Skein.5.2) — index inflates every ~1.5 s.
**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-10T03-09-20Z/features.csv` (cols 53–55).
**Suspected failure class:** `algorithm`. Working hypothesis (UNVERIFIED — needs a diagnosis increment): on real, constantly-evolving music the checkerboard novelty response forms a local maximum at/near the NEWEST valid window position (the after-block holds the freshest, most-different content). That edge peak's absolute index advances ~30 per detect call, so the BUG-035 absolute-index dedup (correct for stationary content peaks) re-admits it every 4th call. A true boundary should only register once it is INTERIOR to the window — i.e. peaks within ~`minPeakDistance` of the newest edge need an edge guard (register only after the peak survives with full bilateral context). The negative timestamps additionally suggest a `currentTime`/`fps` estimation skew in `timestampForFrame` worth auditing in the same diagnosis.
**Verification criteria (written before any fix):**
- [x] Automated: `structuralAnalyzer_evolvingMusicNoBoundary_registersNothing` (production geometry, 3000 continuously-drifting frames) — A/B-proven: pre-fix 5 junk boundaries, post-fix 0. All existing A→B fixtures + the AABA golden still register their boundaries exactly once.
- [x] Automated: `mirPipeline_structuralPrediction_liveCallerShape_timestampsNonNegative` replicates the live caller's `time: 0` shape end-to-end — A/B-proven: pre-fix `sectionStartTime → −0.3167` (the exact session signature), post-fix positive and within the fed span. Plus `structuralAnalyzer_boundaryTimestamps_nonNegativeAndPlausible` at the analyzer layer.
- [ ] Manual: a real session's section columns show multi-second sections and confidence that climbs on verse/chorus material — Matt's next session (the Skein.5.2 columns make it a one-awk check).

---

### BUG-029 — AGC `f.bass` cold-start spike pops/drops continuous-energy presets at every track onset (2026-06-06)

**Severity:** P3 (cosmetic startup artifact, ~1-2 s at each track onset; not a crash). Re-rate to P2 if judged to materially hurt the per-track first impression.
**Domain tag:** dsp.beat (AGC cold-start) — same family as BUG-025.
**Status:** Open — **fix landed (AGC3.3), automated validation green; awaiting Matt's catalog M7 (AGC3.4) before close.** AGC3.1 measured (2026-06-05); AGC3.2 decided **D-148** ("ease the meter in per track" — Matt's call); AGC3.3 implemented seed-from-first-audible + hold-through-sustained-silence in `BandEnergyProcessor`, regression-locked by `AGC3ColdStartSpikeTests` (live-path, FA #66). Filed at Matt's request 2026-06-06 after the AGC2.4 re-M7. AGC3.1 evidence subsection below.
**Introduced:** structural — `BandEnergyProcessor`'s total-energy AGC seeds its running average from whatever energy is present at capture start; during the inter-track silence the running average decays toward zero, so the first audio frame of every track explodes the AGC scale before it catches up.
**Resolved:** —

**Expected:** continuous-energy presets (those reading `f.bass`/`f.mid`/`f.treble` directly) arrive smoothly when a track's audio starts.

**Actual (session `2026-06-06T01-18-36Z`):** at every track onset the first audible frame spikes `f.bass` far above its steady ~0.25 — **Cherub Rock te=1.42 `f.bass`=4.003; Alameda te=0.66 `f.bass`=3.697**. Ferrofluid Ocean (`spikeStrength = 1.0 + 0.8·clamp(f.bass,0,1)`) pops to 1.8× then collapses as bass settles — a "pop-and-drop," not a smooth arrival. During the preceding silent pre-roll `f.bass`=0 so the spikes sit flat/static (only the slow Gerstner swell moves), so the preset reads near-static then jarringly pops.

**Reproduction steps:** play any local-file or streaming session; inspect `features.csv` `bass` at each track's first audible frame — it spikes ~5-15× the steady value for ~1-2 s while the AGC scale catches up.

**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-06T01-18-36Z/features.csv` (Cherub Rock + Alameda startups).

**Suspected failure class:** `calibration` — AGC seed/scale on the silence→onset transition.

**Verification criteria (when resolved):**
- [x] **Automated (live-path):** on a silence→onset fixture through the real `MIRPipeline.process`, `f.bass` does not exceed 2× its steady value. *(`AGC3ColdStartSpikeTests` — session-start 32.6×→<2×, inter-track 10.6×→<2×; plus a byte-identical steady-state lock. FA #66 live-path, not isolation.)*
- [ ] **Manual:** Matt confirms continuous-energy presets (Ferrofluid Ocean) arrive smoothly at track onset — no pop-and-drop. *(AGC3.4 catalog M7, both paths — pending.)*

**Manual validation required:** Yes — it's a felt visual artifact.

**Related:**
- BUG-025 — the AGC cold-start transient (shelved as P3); same AGC-seed family, re-surfaced via its effect on `f.bass`-driven presets.
- BUG-027 / AGC2 — the deviation fix; its cold-start warmup (AGC2.4.1) is a *separate* mechanism inside `BandDeviationTracker` and does **not** touch `f.bass`. FFO reads `f.bass` directly, so AGC2 does not help it — hence this separate filing. Highest-leverage fix smooths the AGC seed/scale at the source (broad benefit: every `f.bass` consumer).

### AGC3.1 evidence (2026-06-05)

Measured from the reference session `2026-06-06T01-18-36Z` (LF, 5 tracks) with the permanent
diagnostic [`tools/agc3/measure_coldstart_spike.py`](../../tools/agc3/measure_coldstart_spike.py).
Full write-up: [`docs/diagnostics/AGC3_1_COLDSTART_SPIKE_2026-06-05.md`](../diagnostics/AGC3_1_COLDSTART_SPIKE_2026-06-05.md).

| trk | mode | pre-roll s | **peak f.bass** | steady | **ratio** | spike s | fo_peak→steady |
|----:|:--|--:|--:|--:|--:|--:|:--|
| 1 | session-start | 1.00 | **4.003** | 0.356 | 11.3× | 0.10 | 1.800 → 1.285 |
| 2 | inter-track | 0.39 | **3.697** | 0.215 | 17.2× | 0.91 | 1.800 → 1.172 |
| 3 | inter-track | 0.50 | **3.471** | 0.203 | 17.1× | 1.19 | 1.800 → 1.162 |
| 4 | inter-track | 0.00 | 0.486 | 0.213 | 2.3× | 0.00 | 1.388 → 1.170 |
| 5 | inter-track | 0.02 | 0.874 | 0.220 | 4.0× | 0.00 | 1.699 → 1.176 |

Four findings sharpen the filed entry:

1. **"Every track onset" → confirmed, refined: every onset preceded by *any* silence gap.**
   The one non-spiking onset (track 4) had **zero** pre-roll; even a one-frame (0.02 s) gap
   spiked 4× (track 5). Magnitude saturates by ~0.4 s of silence. For LF playback an
   inter-track gap is the norm → recurs on essentially every track. Absolute peak (~3.5–4.0)
   is the stable cross-track number; the ratio varies with track loudness (set any fix
   threshold against the absolute value/scale, not the ratio).
2. **Both modes fire; the inter-track mode is the *worse* one.** Session-start (frame-0 seed
   off `1e-6`) self-corrects in ~0.10 s via the fast warmup rate (0.95). Later onsets, with
   the AGC in its slow steady-state rate (0.992), spike **0.9–1.2 s**. This refutes the
   BUG-025 "one-time ~2 s flash" shelving premise — it is per-track and the per-track
   instances last longer than the session-start one.
3. **Downstream pop-and-drop confirmed.** `fo_spike_strength` pins to its **1.800** clamp
   ceiling on every spiking onset (f.bass > 1) then collapses to 1.16–1.29 — a **+40–55 %
   spike-height pop** that drops within 0.1–1.2 s.
4. **The per-stem path does NOT spike** (ratios 0.8–1.4). `StemAnalyzer` runs the same
   `BandEnergyProcessor` per stem but **resets them per track** (`StemAnalyzer.reset()` →
   `processor.reset()`), re-seeding each stem's AGC from its first audible frame. Only the
   main-mix `MIRPipeline` processor is not reset per track — that asymmetry is the spike's
   immediate cause, and the per-stem reset/re-seed is a shipped in-codebase precedent the
   AGC3.2 fix decision can draw on (must keep BUG-018 green).

**Coverage gap:** characterised on **local-file only** — every recorded multi-track session
on disk is `origin=localFile`. The session-start mode is path-independent; the inter-track
mode depends on whether the streaming app emits silence between tracks. A streaming
multi-track recording is needed to close this (flagged for Matt).

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

### BUG-027 — Positive deviation primitives (`bassDev`/`midDev`/`trebDev`) structurally near-dead for any band that isn't dominant (2026-06-02)

**Severity:** P2 (silently weakens the canonical D-026 Layer-2 "above-average" motion driver for every preset that consumes the positive deviation primitives, on every capture path — not a crash, but a load-bearing-design-doesn't-do-what-it-says issue).
**Domain tag:** dsp.beat (deviation-primitive derivation)
**Status:** **Resolved 2026-06-06 (AGC2.1 → 2.5).** Matt chose the (b)+(c)-split at the AGC2.2 gate (**D-146**): a per-band EMA pivot on the FeatureVector band deviation (mirror the stem path) + document the stem-energy offset. Implemented in AGC2.3 (`BandDeviationTracker`); a cold-start warmup was added in AGC2.4.1 after the M7 exposed a session-start hole. See the **Resolution** block below. Surfaced during the BUG-025 A/B correction. **Re-confirmed 2026-06-05 (Nimbus NB.10 r1.6):** the same wrong "centres at 0.5" assumption mis-calibrated Nimbus's `bloom` (stem-energy = 3 AGC bands summed, centres ~0.30 not 0.5 → tiny bodies on normal music). Nimbus was fixed with a local recalibration, but this is the second preset bitten by the system-wide root cause — a normalisation fix here (make the AGC produce a true 0.5 centre per band/stem) would let every preset calibrate against a real 0.5 and is the proper permanent fix. Candidate for its own project (cf. the beat-grid D-145 pattern).
**Introduced:** D-026 / MV-1 (the deviation-primitive design). The fixed 0.5 pivot has always assumed each band's AGC-normalised value centres at 0.5; it doesn't.
**Resolved:** 2026-06-06 — commits `bf711edf` (AGC2.1 measure), `b1c1d1b7` (D-146 decision), `41d87bf9` + `0d2ddb51` (AGC2.3 fix), `95a16881` (AGC2.4.1 cold-start warmup). Local `main` (not pushed).

### Expected behavior

Per CLAUDE.md §Audio Data Hierarchy Layer 2 and D-026, the deviation primitives are "the primary above-average motion driver." `bassDev` should fire (be meaningfully positive) when the bass is above its own running average — i.e. reasonably often on real music (intuitively 30–50 % of frames on a bass-driven track), so presets driving motion from `bassDev` get a lively signal.

### Actual behavior

`bassDev = max(0, (bass − 0.5) × 2)` fires only when the AGC-normalised `bass` output exceeds 0.5. But `bass` is normalised by `agcScale = 0.5 / agcRunningAvg`, where `agcRunningAvg` tracks **total 6-band energy**, not per-band energy (`BandEnergyProcessor.swift:204`, `totalRawEnergy = raw6.reduce(0, +)`). So an individual band's output centres at `0.5 × (that band's fraction of total energy)`. A band that is, say, half the total energy centres at 0.25 → its `*Dev` only fires on a > +2σ excursion → almost never.

Measured (frames downstream of clean AGC resets, both capture paths):

```
                bass mean   bassRel mean   bassDev fires
LF (Atlas)        0.254       −0.49          2.9 %
Spotify           0.222       −0.55          1.5 %
```

`bassDev` firing on < 3 % of frames means any preset relying on it for primary motion gets a near-dead signal — independent of capture path. The *signed* `bassRel` (stddev ≈ 0.21 on both paths) carries the real information; the positive-only `*Dev` clamp throws most of it away.

### Reproduction steps

1. Capture any session (LF or streaming) on bass-dominant or spectrally-uneven music.
2. Inspect `features.csv`: `bassDev` column is 0 on the large majority of frames; `bassRel` is mostly negative.
3. Confirm the same on an LF session — this is not capture-path-specific.

**Minimum reproducer:** any session; the Atlas-LF (`2026-06-01T22-37-01Z`) and Spotify (`2026-06-02T01-12-51Z`) sessions both demonstrate it.

### Session artifacts

`~/Documents/phosphene_sessions/2026-06-01T22-37-01Z/` (LF) and `~/Documents/phosphene_sessions/2026-06-02T01-12-51Z/` (Spotify). 6-band means on the Spotify session: `subBass 0.234, lowBass 0.232, lowMid 0.029, midHigh 0.003, highMid 0.001, high 0.001` — energy concentrated in bass, so total-energy normalisation pushes every individual band's output (and thus its `*Dev`) low.

### Suspected failure class

`calibration` — the 0.5 pivot in the deviation formula assumes per-band centring that the total-energy AGC does not produce.

### Verification criteria

When resolved:
- [x] **Automated:** on a recorded bass-dominant fixture, the chosen "above-average bass" primitive fires on ≥ 20 % of frames. *(`RelDevTests.bandDeviation_firesAboveOwnAverage_onRecordedBass`: the old fixed-0.5 pivot fires 7.2 %, the new per-band EMA fires 41 % on the recorded Atlas fixture.)*
- [x] **Automated:** existing deviation-primitive contract tests (`RelDevTests`) still pass or are updated with the new semantics. *(The fixed-0.5 formula pin was deliberately retired → `BandDeviationTracker` unit tests + the cold-start live-path test; 10/10 green, SwiftLint `--strict` clean.)*
- [x] **Manual:** Matt confirms presets that consume the above-average-bass primitive read as appropriately reactive across multiple tracks. *(M7 catalog cycle, session `2026-06-06T01-18-36Z` — deviation presets read well. The one flagged issue, Ferrofluid Ocean's startup, was diagnosed **out of scope**: FFO reads `f.bass`/`arousal`, no deviation primitives; its root is the AGC `f.bass` cold-start spike, filed as **BUG-029**.)*

**Manual validation required:** Yes — affects the deviation-consuming presets (Arachne, Aurora Veil, Dragon Bloom, Gossamer, Kinetic Sculpture, Spectral Cartograph, Volumetric Lithograph). Done at the M7 catalog cycle.

### Fix scope

**Not yet scoped; needs a design decision, not a quick patch.** Candidate directions (each affects all 8 deviation-consuming presets + their golden hashes, so this is a real increment with M7 across the catalog, NOT a trivial fix):
- (a) **Per-band running average** — give each band its own AGC EMA so `bandDev` centres on that band's own average. Cleanest semantically; changes the AGC's whole character; invalidates golden hashes.
- (b) **Recenter the deviation pivot per-band** — derive each band's typical fraction-of-total and pivot the deviation there instead of at 0.5. Less invasive than (a).
- (c) **Document `*Dev` as "rare strong-transient only" and steer preset authors to signed `*Rel`** — no engine change; the Dragon Bloom 2026-06-02 re-tune already does this (uses signed `bass_rel`, not `bass_dev`). Lowest risk; makes the limitation explicit rather than fixing it.

Recommend deciding between (a/b/c) with Matt before any implementation — this is the structural issue the BUG-025 misdiagnosis was pointing at, and it deserves a deliberate call, not a rushed fix.

### AGC2.1 evidence refresh (2026-06-05)

The two sessions named under "Session artifacts" above (`2026-06-01T22-37-01Z`,
`2026-06-02T01-12-51Z`) **no longer exist on disk**; AGC2.1 re-measured on 4 current sessions
across both paths and 4 spectral classes. Harness: `tools/agc2/measure_deviation_centring.py`.
Full tables: [`docs/diagnostics/AGC2_1_DEVIATION_CENTRING_2026-06-05.md`](../diagnostics/AGC2_1_DEVIATION_CENTRING_2026-06-05.md).

Three findings sharpen the original entry:

1. **Manifestation A is broader than the bass-only headline.** `bassDev` fires 2–8 % of active
   frames, but **`midDev`/`trebDev` fire ~0 % on every session, both paths — including a genuinely
   mid-rich acoustic track (Elliott Smith, mid p50 0.07) and a treble-rich jazz track (Mingus, mid
   p50 0.10, cymbals/horns).** The mid band's centre rises with spectral focus but never approaches
   0.5, so the entire positive mid/treble deviation channel is dead catalog-wide. Structural (total-
   energy AGC pins non-bass bands below 0.5 regardless of genre), not genre-correlated.
2. **Manifestation B splits.** Raw `{stem}Energy` centres ~0.25–0.45 (≠ 0.5) and bites consumers
   that read it directly (Nimbus bloom). But `{stem}EnergyDev` fires **56–77 %** — the stem
   deviation path uses a **per-stem EMA pivot** (`StemAnalyzer.swift:277-298`), not the fixed 0.5,
   so it self-centres and is **already healthy**. Only the raw-energy-0.5 assumption needs handling.
3. **The working pattern already ships in-codebase**: the stem path (per-element EMA pivot, alive)
   vs the band path (fixed-0.5 pivot, dead) sit side by side. Fixing A = bringing the band path in
   line with the stem path. This is the (b)-leaning evidence; the call is Matt's at AGC2.2.

### Resolution (AGC2.1 → 2.5, 2026-06-06)

**Decision (D-146):** the (b)+(c)-split. The fixed-0.5 pivot in `MIRPipeline.buildFeatureVector` was replaced with a **per-band running-average pivot** (`BandDeviationTracker`, mirroring `StemAnalyzer`'s per-stem EMA): each band's `*Rel`/`*Dev` is now measured against the band's own recent average. The total-energy AGC is untouched (raw `f.bass/mid/treble` and cross-band info unchanged). Stems needed no engine change — the stem deviation path was already EMA-based and healthy; the raw-`{stem}Energy`-centre is handled per-consumer (Nimbus already recalibrated, D-144 r1.6) and documented.

**Additive form** chosen over scale-free `x/ema−1` (AGC2.3 prototype) — preserves the `[-1,1]`-ish `*Rel` convention and avoids unbounded spikes. Mid/treble `*Dev` are quieter than `bassDev` in absolute terms (those bands are quiet post-AGC) — an authoring note, see SHADER_CRAFT §14.1.

**No golden-hash drift** — `PresetRegressionTests` feed hand-built FeatureVectors, bypassing the live derivation; the *live* runtime values change (catalog M7 validated that).

**Cold-start sub-fix (AGC2.4.1):** the AGC2.4 M7 (`2026-06-05T23-57-14Z`) exposed a hole — the per-band EMA seeded from the session-start AGC spike (bass = 3.69 off the initial silence) and, since `MIRPipeline.reset()` is never called per track, stayed poisoned ~3-4 min, suppressing all band `*Dev` early. Fixed with a two-speed warmup (fast decay converges through the spike in ~1-2 s) + a value ceiling. A **live-path** test (`bandDeviation_recoversFromColdStart_liveMIRPipeline`) now reproduces and guards it — closing the FA #66 parity gap that let the hole ship. (Replaying the fix over the M7 session: the early tracks recover, e.g. Alameda mid 0 → 59 %, Mingus treble 0 → 63 %.)

**Out of scope, filed separately:** the AGC `f.bass` cold-start spike itself (**BUG-029**) — it pops/drops continuous-energy presets (Ferrofluid Ocean) at every track onset; it's a `BandEnergyProcessor` AGC issue, not a deviation issue, and AGC2's warmup is a separate mechanism that does not touch `f.bass`.

### Related

- Decision: D-026 (deviation primitives) — the design this refines; D-146 (the AGC2.2 fix-scope decision).
- BUG-025 — the misdiagnosis that surfaced this; corrected 2026-06-02.
- BUG-029 — the AGC `f.bass` cold-start spike, filed out of AGC2 scope.
- Increment: Dragon Bloom 2026-06-02 re-tune (direction (c) applied at preset scope — proof the signed-`*Rel`-not-`*Dev` workaround works).
- Failed Approach: #31 (absolute thresholds on AGC-normalised energy) — same family; #66 (test/prod parity gap — the cold-start hole's lesson).

---

### BUG-025 — AGC running-average poisoned by post-`active` startup transient on Spotify process-tap (2026-06-01)

> **CORRECTED 2026-06-02 — root cause was misdiagnosed; severity downgraded P2 → P3.** A LF↔Spotify A/B (sessions `2026-06-01T22-37-01Z` Atlas-LF vs `2026-06-02T01-12-51Z` Spotify) during the AGC.1 scoping step disproved the original "session-wide starvation" claim below. Two facts the original entry got wrong:
> 1. **The transient is one-time, ~2 s, at the very first audio onset only.** Subsequent track changes call `reset()` and re-initialise the AGC cleanly from the first audio-playing frame — they show gentle ramps, no transient. So the transient does NOT poison the whole session; it affects ~2 s once at session start.
> 2. **The session-wide `bassDev ≈ 0` starvation is STRUCTURAL, not caused by the transient, and is identical on LF.** Measured in transient-free segments downstream of clean track-change resets: `bassDev` fires on 1.5 % of Spotify frames and **2.9 % of the LF session that "danced."** The deviation primitive `bassDev = max(0, (bass−0.5)×2)` fires only when the bass band exceeds the *total-energy* AGC average — structurally rare for bass-dominant music on any capture path (6-band means: `subBass 0.23, lowBass 0.23, lowMid 0.03, rest ≈ 0`). It is the fixed-0.5-pivot interacting with total-energy normalisation, not an AGC mis-convergence.
>
> **What's actually real here:** a genuine but minor cold-start visual flash in the first ~2 s of a fresh session's first onset. That's the only defect; it's cosmetic, hence P3. The "muted on Spotify" symptom that motivated this entry was (a) raw-waveform amplitude gap, fixed in Dragon Bloom commit `cffefe65`, and (b) the structural `bassDev` limitation that affects LF equally — addressed at the preset level by the 2026-06-02 Dragon Bloom re-tune (route to signals alive on both paths: signed `bass_rel`, `spectralFlux`, beat — not `bassDev`/`mid_att_rel` which are structurally dead on bass-dominant music). The AGC.1 transient-rejection fix (kickoff `docs/prompts/AGC1_KICKOFF.md`) is **shelved** — it would fix only the 2 s flash, which is not worth a cross-cutting AGC change touching 8 presets. **The structural deviation-pivot limitation is the real latent issue and is filed separately as BUG-027.**

**Severity:** ~~P2~~ → **P3** (cosmetic ~2 s cold-start flash at the very first onset of a fresh session; not session-wide; does not affect track changes).
**Domain tag:** dsp.beat (AGC convergence)
**Status:** Open — diagnosed, root cause corrected, fix shelved as not-worth-the-blast-radius. See BUG-027 for the real latent issue.
**Introduced:** AGC EMA's interaction with a long silent pre-playback period (the AGC runs during silence, floors its average + burns its warmup window, then over-scales the first ~2 s of real audio). First measurement-grade observation: Dragon Bloom Spike 1 debug session `~/Documents/phosphene_sessions/2026-06-01T22-57-10Z`.
**Resolved:** —

> *The original investigation record below is preserved verbatim. Read it as the data that LED to the corrected diagnosis above — its "Actual behavior" section's "entire rest of the session" claim is the part the A/B disproved.*

### Expected behavior

When the process-tap goes from `silent` → `active` (audio first reaches the AGC after Spotify starts playing), the per-band AGC running averages should converge to a value reflecting steady-state playback within a small number of seconds. Steady-state `bassRel ≈ 0` (bass equals running average) and the deviation primitives `bassDev` / `midDev` should fire on real transients across most of the session.

### Actual behavior

The first 5–10 frames after `audio signal → active` show extreme transient amplitude spikes (`bass` values 50× the eventual steady-state value — see Session artifacts). These spikes appear to be FFT cold-start or buffer-fill transients, NOT real audio content, but they enter the AGC EMA with the same weight as legitimate signal. The EMA running average gets pulled up high by them and decays only over the EMA's time constant — meaning **the entire rest of the session sees an artificially inflated running average**. Symptoms over the remaining session:

- `bassRel` is structurally negative across nearly all post-startup frames (observed range −0.42 to −0.89 in the reference session).
- `bassDev = max(0, bassRel)` therefore fires (≥ 0.05) on only ≈ 1.6 % of frames — instead of the expected ≈ 30–50 % on a normal music track.
- Deviation-driven preset routing (D-026: `bassDev` / `midDev` as the primary "above-average" motion driver) is effectively dead for the session.
- AGC's intended inter-track normalisation does not engage — the "is this above the running average" question reads as "no" on almost every frame.

### Reproduction steps

1. Run Phosphene against a Spotify tap session. Any modern Spotify playlist with a mix of loud and quiet sections works; the Dragon Bloom debug session used Son Lux *Flickers* + Wild Beasts *Wanderlust* + other tracks.
2. Wait for `audio signal → active` in `session.log`.
3. Inspect `features.csv` `bass` column: rows in the first ~10 frames after `active` show values 5–50× the median; the median itself is well below 0.5.
4. Inspect `bassRel` across the rest of the session: predominantly negative.
5. Inspect `bassDev`: zero on > 98 % of frames.

**Minimum reproducer:** any Spotify-tap session captured after the `active` transition. The transient amplitudes vary per session but the AGC-pulling behavior is reproducible.

---

### Session artifacts

**Session directory:** `~/Documents/phosphene_sessions/2026-06-01T22-57-10Z/`

Selected `features.csv` rows showing the startup transient (frames 253–262, immediately after `audio signal → active` at 22:58:47Z):

```
frame  wallclock      bass       mid       treble  beatBass  spectralFlux
253    ...527.39      2.308      0.310     0.221   0.893     1.000
254    ...527.41      5.331      0.432     0.320   0.692     1.000
255    ...527.43      6.412      0.480     0.337   0.542     1.000
256    ...527.44      6.629      0.477     0.338   0.480     1.000
257    ...527.46      6.601      0.468     0.325   0.374     1.000
258    ...527.48      6.377      0.461     0.317   0.334     1.000
259    ...527.49      5.869      0.433     0.298   0.259     1.000
260    ...527.51      5.782      0.420     0.287   0.231     1.000
261    ...527.53      7.730      0.686     0.252   0.179     1.000
262    ...527.54      11.010     1.051     0.246   0.159     1.000
```

Statistical summary across the remaining 3 792 post-active frames:

```
bass mean   = 0.225    bass max     = 12.822    pct(bass > 0.5)    =  1.8 %
mid  mean   = 0.059    mid  max     =  1.051    pct(mid  > 0.2)    =  5.5 %
trbl mean   = 0.025    trbl max     =  0.600
bassDev fires (≥ 0.05): 1.6 % of frames
beatComposite mean = 0.600  (beat detection unaffected — it operates on flux, not amplitude)
```

`session.log` confirms the transient lands exactly at the `active` transition:

```log
[22:58:43Z] signal quality → red: no signal — check output device / app is playing
[22:58:44Z] audio signal → suspect
[22:58:45Z] audio signal → silent
[22:58:47Z] audio signal → recovering
[22:58:47Z] audio signal → active
[... transient spikes at frames 253–262 follow within ~0.3 s ...]
```

The Spotify in-app volume was at 50 % during this capture, which independently lowers the steady-state per-band values (see BUG-026). The startup-transient → AGC-poisoning interaction is separate from the user-settable level issue: even at correct Spotify volume the cold-start transient would still poison the EMA.

**Confirmation session (Spotify at 100 %, 2026-06-02):** `~/Documents/phosphene_sessions/2026-06-02T01-12-51Z/`. With the Spotify volume cause from BUG-026 resolved, the raw tap level rose by 16 dB (Peak -4.8 dB, RMS -18.4 dB — healthy mastered-audio range; `session.log` confirms `signal quality → green: peak -6 dBFS, treble 0.06% — OK`). The cold-start transient is unchanged: frames 310-321 immediately after `active` show bass = 3.3 → 6.6 → 10.9 → 11.4 → 10.97 → 11.58 → 10.45 → 10.07 → 9.09 → 8.55 → 7.92 → 7.33 (peak 11.58 at frame 315 — same shape and magnitude as the previous session's 11.0 peak at frame 262). The AGC EMA absorbs these and the rest-of-session statistics are essentially identical:

```
bass mean   = 0.260  (was 0.225 at 50 %; 16 dB louder input → only 16 % bump in mean)
bass max    = 11.58  (was 12.82; cold-start spike same magnitude regardless of input level)
bassRel mean = -0.48  (was negative too; EMA poisoned identically)
pct(bassRel in [-0.1, +0.1]) = 2.8 %  (should be ~50 % at AGC convergence)
bassDev fires (≥ 0.05): 1.8 %  (was 1.6 %; deviation routing structurally dead)
post-startup bass distribution:
  < 0.1: 2.8 %   0.1–0.3: 72.0 %   0.3–0.5: 23.6 %   ≥ 0.5: 1.7 %
```

This isolates BUG-025 from BUG-026: even at healthy signal level the AGC starves all deviation-driven routing. The deviation primitives (Layer-2 in the Audio Data Hierarchy, the canonical "above-average" drivers per D-026) are effectively non-functional on every Spotify session that includes the `silent → active` transition.

---

### Suspected failure class

`calibration` — the AGC EMA does not protect itself against startup transients that bypass the "active" signal-detection gate. Possibilities for the spike source: FFT buffer-fill ringing in the first 1–2 windows after `active`; sample-rate-converter ramp at the tap boundary; or process-tap initial buffer carrying stale data from a prior session. Determining which is part of the fix.

**Evidence for this class:** the spikes are present in the AGC-input band energies but the underlying raw waveform amplitudes (per `raw_tap.wav` astats) are smoothly increasing — the spike is amplification by the AGC pipeline, not the source signal. The behavior is reproducible across sessions and lasts the entire session because the EMA decay time is long relative to a session.

---

### Verification criteria

When this defect is resolved, the following must all pass:

- [ ] **Automated:** new test asserting that on a fixture session (recorded `features.csv` + `raw_tap.wav` from a real Spotify session), `pct(bassDev > 0.05)` over the post-active frames exceeds 20 % (sanity floor — most music passes 30–50 %).
- [ ] **Automated:** new test asserting that the AGC EMA running-average state after the `active` transition is bounded by some multiple (TBD: 3×?) of the prior-window median, rejecting transient values above that threshold or warming up the EMA from a clean state.
- [ ] **Domain-specific artifact:** `features.csv` from a fresh Spotify-tap session (any playlist) shows `bassRel` distribution roughly centred on zero across the post-active session, not structurally negative.
- [ ] **Manual:** Matt confirms a deviation-driven preset (Volumetric Lithograph, Aurora Veil, or post-fix Dragon Bloom) reads as appropriately reactive across a multi-track Spotify session — *not* "dim for the whole session."

**Manual validation required:** Yes. The numerical gates above prove the pipeline correction; the manual check proves the preset experience improved.

---

### Fix scope

Contained — the change lives in `MIRPipeline` / the AGC EMA implementation. Candidate approaches: (a) reject samples > N× current running average from the EMA update on the first M frames after `active`; (b) warm up the running average from a clean zero state for the first N frames after `active`, accepting low / no normalisation during that window; (c) add a one-shot "transient suppression" window immediately after `silent` → `active` that gates the AGC from updating until the input settles. Any approach must preserve the existing AGC behavior under steady-state input (regression-locked by the existing acceptance suite).

### Related

- Decision: D-026 (AGC + deviation primitives) — the routing layer that gets starved by this bug.
- Failed Approach: FA #31 (absolute thresholds on AGC-normalized energy) — orthogonal but related family; FA #31 says "don't threshold AGC values," this bug says "AGC itself can mis-converge."
- Increment: Dragon Bloom Spike 1 / Spike 1 fix (`d380ed00` / `cffefe65`, 2026-06-01) — surfaced this bug during root-cause analysis of the "looks like silence on Spotify after 20 s" report.
- BUG-026 — Spotify in-app volume slider not surfaced as a setup warning; compounds the visible severity of BUG-025 on the user's first sessions.

---

### BUG-026 — Quiet-tap-signal UX gap: no warning when input signal level is structurally insufficient (2026-06-01)

**Severity:** P2 (does not affect correctness; degrades the first-session experience for any user whose Spotify in-app volume slider is below 100 % or whose macOS output level is reduced. Cost surfaced when a preset author spent ~3 hours debugging a Spotify-reactivity report whose root cause was a 50 % Spotify volume slider.)
**Domain tag:** session.ux
**Status:** Open — diagnosed.
**Introduced:** Pre-dates session UX work — has been present since the process-tap path was first wired (Phase 1 / 2).
**Resolved:** —

### Expected behavior

When the process tap is delivering audio whose RMS sits at a level too low to drive useful AGC convergence or perceptible preset reactivity (e.g. RMS < −25 dB after the `active` transition), Phosphene should warn the user via a non-blocking chrome toast: *"Input signal is very quiet — check that Spotify volume (in-app slider) is at 100 % and macOS output volume is normal. Phosphene is post-mixer; your hardware monitor knob can be loud while the tap sees a quiet signal."* The toast should fire once per session after the steady-state RMS is established (e.g. 5 s after `active`).

### Actual behavior

The existing `signal quality` detector emits `red: no signal` → `suspect` → `silent` → `recovering` → `active` based on whether ANY signal is present (it gates on something close to absolute-zero). It does not distinguish "active and at normal level" from "active and structurally too quiet." Once the detector reads `active`, the session proceeds as if the signal is healthy. No toast is shown. The user perceives the symptom (presets unreactive) without any pointer to the cause.

Common upstream causes the user could fix if they were told:
- **Spotify in-app volume slider below 100 %** — extremely common because the Apogee / monitor-controller workflow encourages controlling final loudness in hardware. The user can have a loud monitor and a quiet Spotify slider simultaneously and not realise it. (This was the cause Matt hit on 2026-06-01: Spotify slider at 50 %, monitor cranked.)
- **macOS system volume reduced** — relevant when the output device is the built-in DAC (not an external interface with hardware volume).
- **Spotify Normalize Volume = On** — documented in CLAUDE.md FA #30 but no in-app surface for it.
- **Source app is muted at the app level (some apps have per-app volume in macOS Audio MIDI Setup).**

### Reproduction steps

1. Open Spotify; set the in-app volume slider to ≈ 50 %.
2. Start a Phosphene session against a Spotify playlist with the Apogee Duet 3 (or similar external interface) as the output, monitor knob at normal listening level.
3. Audio plays at correct loudness through the monitor. `session.log` shows `audio signal → active`. No warning toast appears.
4. Observe in `features.csv`: `bass` mean stays ≈ 0.22 (well below the ≈ 0.5 AGC convergence target); preset reactivity is visibly diminished.

**Minimum reproducer:** the Dragon Bloom debug session referenced in BUG-025 (`~/Documents/phosphene_sessions/2026-06-01T22-57-10Z`) is one reproducer; any session captured with Spotify slider < 75 % reproduces.

---

### Session artifacts

**Session directory:** `~/Documents/phosphene_sessions/2026-06-01T22-57-10Z/`

`raw_tap.wav` astats summary (compare to typical streaming-mastered audio at peak ≈ −1 dB / RMS ≈ −14 dB):

```
Peak level  dB: −21.5
RMS  level  dB: −34.8
RMS  peak   dB: −29.8
DC offset:   −0.000004   (within float-rounding noise — clean)
NaN / Inf / denormal: 0   (audio data is well-formed)
```

The DC offset and clean numerics confirm the tap path is operating correctly; the level is the issue. `session.log` shows the `signal quality → active` transition fired despite the signal being 20 dB below useful range:

```log
[22:58:47Z] audio signal → recovering
[22:58:47Z] audio signal → active
[... no warning about the level ...]
```

---

### Suspected failure class

`session.ux` — the diagnostic information exists in the pipeline (running RMS is trivially computable from the existing tap-buffer code), but the UX path that would surface it to the user is missing. Adjacent class: `calibration` — the `signal quality` detector's `active` threshold is "non-zero," not "perceptually adequate."

**Evidence for this class:** the underlying tap is delivering well-formed PCM (verified by `raw_tap.wav` astats); the AGC produces valid (though low-amplitude) per-band energies; no pipeline component is broken. Adding the warning is a pure UX addition.

---

### Verification criteria

When this defect is resolved, the following must all pass:

- [ ] **Automated:** unit test on `SignalQualityClassifier` (or wherever the toast fires) verifying that on a synthetic tap input at RMS = −30 dB sustained, the "low input" toast fires within 5 s of `active`.
- [ ] **Automated:** the toast does NOT fire on a normal-level fixture (RMS ≈ −14 dB).
- [ ] **Domain-specific artifact:** `session.log` from a fresh quiet-tap session (Spotify at 50 % volume) contains a log line indicating the warning was emitted, with the measured RMS dB.
- [ ] **Manual:** the toast text reads clearly, references Spotify in-app volume AND macOS output volume, and dismisses cleanly. It does NOT overlap with other chrome elements during the `.connecting` → `.playing` transition.

**Manual validation required:** Yes. UX wording and dismissal behavior are subjective.

---

### Fix scope

Small — extend the existing `SignalQualityClassifier` (or equivalent) with an `activeButTooQuiet` state, surface it through the same chrome toast path that handles other capture warnings. Threshold selection (which RMS level is "too quiet") needs one calibration measurement against a known-good LF session and a known-quiet Spotify session — the −25 dB number above is a draft, not the final tuning. Sits naturally inside a small Phase U / Phase QR follow-up; not blocking any other increment.

### Related

- Failed Approach: FA #30 (Spotify Normalize Volume) — same family of "user setting upstream of Phosphene that affects signal level"; the toast text should mention it.
- Decision: none yet.
- Increment: Dragon Bloom Spike 1 follow-up debug (2026-06-01) — the cost surfaced during that session is the motivation.
- BUG-025 — Compounds with this bug; until BUG-026's toast lands, users have no clue why their input is quiet, and even if their input were a healthy level BUG-025 could still poison the AGC at the `active` transition.

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
**Status:** Open — CLEAN.1.1/1.2 cross-ref (2026-06-13): the original BUG-012 analysis assumed the serial `stemQueue` was the only `separate()` caller; it is not — the session-prep path drove the *same* `StemSeparator` unlocked (diagnosed as **BUG-031**). **CLEAN.1.2 fixed BUG-031**: the full input→predict→output section is now serialized under one lock, so the live + prep paths can no longer drive concurrent MPSGraph work on the shared model buffers — a candidate root cause of this crash. Whether it actually retires BUG-012 needs confirmation from Matt's manual concurrency session + crash-watch; record the outcome here.
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
| `MemoryReporterTests` growth assertions | `phys_footprint` variance across system memory pressure states | Run with other apps quit; or skip with `SKIP_MEMORY_TESTS=1` |

**Resolved 2026-06-14 (CLEAN.7.10)** — `RayIntersectorTests.test_rayTrace_1000Rays_under2ms` made contention-robust (it never entered the table above — it surfaced fresh on the Mac mini during the CLEAN.1 Phase-0 re-confirmation, having passed 1469/1469 on both prior integration closeouts). The failing line was a **single-sample `Date()` wall-clock assertion around one GPU command-buffer submit**, run inside the ~1469-test parallel suite — about the most contention-fragile shape there is: a saturated GPU/CPU inflates any one submit past the 2 ms budget, while isolated the whole class incl. this test runs in 0.42–0.54 s (5/5 green). Per the deterministic-over-budget-widening rule (proven on CLEAN.7.9), the 2 ms gate was **kept, not loosened**: the assertion now takes the **minimum of 8 warm samples** — contention can only ADD latency to a GPU submit, so the min is the clean estimate of true cost and is robust to a few starved samples. The ray-intersector path is untouched by CLEAN.1 (last modified in render increment 3.3); test-only, no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-06-14-a]`.

**Resolved 2026-06-13 (CLEAN.7.9)** — `MetadataPreFetcherTests.fetch_networkTimeout_returnsWithinBudget` removed from the table above. The wall-clock budget — ratcheted 3 s → 8.25 → 15 → 45 s across prior sessions without ever converging (16.1 s / 22.8 s observed under the ~1460-test parallel suite during the CLEAN.1.x closeouts) — was replaced by a deterministic behavioural assertion: the merged profile carries the fast fetcher's `energy` but **not** the slow fetcher's `bpm` (excluded by the 1 s timeout). The outcome depends only on the 1 s-vs-10 s ordering (the 1 s timer's continuation is enqueued ~9 s before the 10 s one — contention delays both, never inverts them), not on measured elapsed time, so it cannot flake under cooperative-pool contention. Renamed `fetch_networkTimeout_returnsFastResultNotSlow`; adversarially proven to trap a timeout that lets the slow result leak (`bpm → 999` fails `== nil`, a ~10 s block not a hang). Test-only; no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-06-13-b]`.

**Resolved in the 2026-06-01 hardening pass** (made deterministic — no longer wall-clock-dependent, removed from the table above): `FirstAudioDetectorTests` (ManualDelay), `AppleMusicConnectionViewModelTests` (bounded-yield state polling; never required Apple Music.app — uses `MockAppleMusicConnector`), `SessionManagerTests` lifecycle suite (`waitForReady` safety deadline 3 s → 15 s). `PreviewResolverTests` carries no wall-clock waits or `URLProtocol` stubs in current source — the earlier "rate-limit timing / `.serialized` applied" note did not match the code and was dropped.

---

## Resolved (recent)

### BUG-033 — App layer: per-frame `@Published dashboardSnapshot` invalidates the whole SwiftUI tree at 60 Hz; `assign(to:on: self)` retain cycles leak view models (2026-06-09)

> **RESOLVED 2026-06-14 — fix `f95d645` ([CLEAN.1.4]); integrated to `main` + pushed as `da26a3a`; manual validation completed (Matt, Activity Monitor overlay-on/off toggle).** (1) The per-frame dashboard snapshot flows through a dedicated `CurrentValueSubject` (`dashboardSnapshotSubject`), **not** `@Published` on the engine — no more 60 Hz whole-tree SwiftUI invalidation; the publish is skipped while the overlay is hidden (the default). (2) Both VMs' `assign(to:on: self)` → `sink { [weak self] }`, breaking the retain cycles (VMs now `deinit`).

**Severity:** P1 (steady main-thread burn for the entire duration of every playback session + unbounded VM leak at frame rate).
**Domain tag:** app.ui / performance / leak
**Status:** Resolved — automated (VM deinit tests) + manual (Matt's overlay-toggle CPU check) criteria met. The high *absolute* CPU Matt observed during the check is a separate finding — the always-on session recorder, filed **BUG-050** — not this defect.
**Introduced:** dashboard snapshot pump (dashboard increment); `assign(to:on:)` subscriptions in VM inits.
**Resolved:** 2026-06-14 — commit `f95d645` ([CLEAN.1.4]: dashboard snapshot off `@Published` → `CurrentValueSubject` + skip-when-hidden; VM `sink { [weak self] }`), integrated to main as `da26a3a`.

**Expected:** hidden diagnostics cost nothing; view models deallocate when their views go away.
**Actual (pre-fix):** the per-frame dashboard snapshot was `@Published` on the `@EnvironmentObject`-wide engine → `objectWillChange` re-evaluated the whole SwiftUI tree at ~60 Hz throughout playback; and both VMs' `assign(to:on:self)` subscriptions retained `self` → the VMs never deallocated (one chrome VM leaked per session).
**Suspected failure class:** `resource-management`.
**Verification criteria:**
- [x] Automated: VM deallocation tests (weak ref nils after teardown) — `SessionStateViewTests.deallocates_noRetainCycle` + `PlaybackChromeViewModelTests.deallocates_noRetainCycle` (red pre-fix via `assign`, green post-fix via `sink [weak self]`).
- [x] Dashboard writes go through a non-`@Published` subject (`dashboardSnapshotSubject`), publish skipped when the overlay is hidden.
- [x] Manual: Matt's Activity Monitor check — toggling the overlay produces the expected CPU swing (the decoupling working); the residual high CPU traced to the separate recorder cost (BUG-050), not this path.

---

### BUG-031 — StemSeparator shared between live pipeline and session preparer with unlocked I/O: cross-path stem corruption (2026-06-09)

> **RESOLVED 2026-06-14 — fix `1447612` ([CLEAN.1.2], strategy A — Matt-approved); integrated to `main` + pushed as `da26a3a`; manual validation completed via Matt's sessions `2026-06-14T17-22-31Z` (local) + `2026-06-14T17-58-44Z` (streaming).** The full input→predict→output critical section on the single shared `StemSeparator` is now atomic under one lock, and stems are returned BY VALUE (`StemSeparationResult.stemWaveforms`) so callers never read the shared `stemBuffers`.

**Severity:** P1 (silent stem corruption → poisoned orchestrator stem-affinity scoring; plausible contributor to the BUG-012 family).
**Domain tag:** dsp.stem / concurrency
**Status:** Resolved — automated (`StemSeparatorConcurrencyTests` + `tsan_stress.sh`) + manual (Matt's two sessions) criteria met.
**Introduced:** progressive readiness (Inc 6.1) made prep-during-playback the normal case; the BUG-012 race analysis only covered the serial `stemQueue`, never the preparer path.
**Resolved:** 2026-06-14 — commit `1447612` ([CLEAN.1.2]: lock the full `separate()` pipeline + return stems by value), integrated to main as `da26a3a`.

**Expected:** stem separation results are isolated per caller.
**Actual (pre-fix):** one shared `StemSeparator`; `separate()` wrote model inputs and read outputs outside the only lock (`predict()`), and both callers read the shared `stemBuffers` unlocked → overlapping live+prep calls interleaved (call A's `predict` consumed call B's input; A then read B's stems).
**Suspected failure class:** `concurrency`.
**Verification criteria:**
- [x] Automated: `StemSeparatorConcurrencyTests.concurrentSeparations_returnPerCallerOwnStems` (threshold-free cross-caller discriminator; A/B-RED by reverting the lock).
- [x] TSan: `Scripts/tsan_stress.sh` (CLEAN.1.6) — overlapping live+prep `separate()` on one shared instance, **0 data races**.
- [x] Manual: Matt's real sessions (`17-22-31Z` local, `17-58-44Z` streaming) — stems feel musically connected; recorded per-stem deviation is live (drums/bass/vocals range >1.5 over a mid-streaming window); no stall/deadlock/crash.

---

### BUG-032 — Streaming session lifecycle: `endSession()` orphans the prep task; stale prep can hijack the next session; recovery spawns a second concurrent prep loop (2026-06-09)

> **RESOLVED 2026-06-14 — fix `4762114` ([CLEAN.1.3]); integrated to `main` + pushed as `da26a3a`; manual validation completed via Matt's sessions `2026-06-14T17-22-31Z` + `2026-06-14T17-58-44Z`.** All three defects fixed: `endSession()` cancels `sessionPreparationTask`/`statusCancellable`; a per-instance `streamingSessionGen` (twin of `localFileSessionGen`) gates the prep-completion closure so an orphan can't mutate the new session; `resumeFailedNetworkTracks` is single-flight; both `startSession` variants mutate the published source only after the state guard.

**Severity:** P1 (next session's plan overwritten with the old playlist + flipped `.ready` prematurely; two `_runPreparation` loops over the single StemSeparator — compounded BUG-031).
**Domain tag:** session.lifecycle / concurrency
**Status:** Resolved — automated (`SessionLifecycleGenerationTests` + `SessionRecoverySingleFlightTests` + `tsan_stress.sh`) + manual (Matt's two sessions) criteria met.
**Introduced:** structural — predates LF.5's generation-guard pattern; the streaming path never got the equivalent.
**Resolved:** 2026-06-14 — commit `4762114` ([CLEAN.1.3]: streaming session-generation guard + lifecycle teardown + single-flight recovery), integrated to main as `da26a3a`.

**Expected:** ending a session cancels its preparation; a new session is unaffected by the old one's in-flight work; recovery resumes within the existing loop.
**Actual (pre-fix):** `endSession()` left the prep task live; the orphan's completion overwrote the next session's `currentPlan`/state; `resumeFailedNetworkTracks` spawned a second `_runPreparation`; `startSession` mutated the published source before the state guard.
**Suspected failure class:** `concurrency` (task lifecycle), `api-contract` (source-before-guard).
**Verification criteria:**
- [x] Automated: `SessionLifecycleGenerationTests` (end→restart orphan guard + rejected-startSession source order) + `SessionRecoverySingleFlightTests` (`maxRunPreparationInFlight == 1`).
- [x] TSan: `Scripts/tsan_stress.sh` (CLEAN.1.6) — rapid start/end/cancel churn with prep in flight, **0 data races**.
- [x] Manual: Matt's real sessions — cancel→restart + four source loads (Spotify → local folder → single files), each reaching `→ready` with its OWN correct plan; no orphan-hijack, no premature ready, no crash.

---

### BUG-030 — Duplicate playlist tracks crash `SessionPreparer.prepare(tracks:)` (2026-06-09)

> **RESOLVED 2026-06-12 (fix commit `ba4e1cae`, a cherry-pick of `679363a9` from the stranded `claude/dreamy-bell-23528b` branch onto main during CLEAN.0 baseline reconciliation)** — trivial P1, collapsed per the BUG-030 kickoff (instrument→diagnose→fix→validate in one increment: < 5 lines of behavioural change, root cause obvious from audit §A2, no architectural risk). **Fix shape (A):** both `trackStatuses` builds switched from `Dictionary(uniqueKeysWithValues:)` to `Dictionary(_:uniquingKeysWith:)` (keep the first `.queued`) — at the streaming build in `prepare(tracks:)` and the LF twin in `prepareLocalFiles(…)`. Contract-faithful: the prepare loop still visits both occurrences (the second is a cheap cache hit), so a twice-listed track yields **two** `cachedTracks` entries → two plan slots, honouring `PlaylistConnecting`'s "duplicates preserve their playlist order." Option (B) (dedupe to one slot) was rejected — it would silently drop a playlist position (a product behaviour change, not a crash fix). Two regression tests in `SessionPreparerTests` were confirmed to **trap** against pre-fix code (`Fatal error: Duplicate values for key`) and pass after; the streaming test pins the two-slot contract so an option-(B) refactor fails the gate loudly. Engine suite green (the only fresh-worktree failures were the unfetched `Tests/Fixtures/tempo` clips, restored via `Scripts/fetch_tempo_fixtures.sh`).

**Severity:** P1 (runtime trap → session preparation crash on ordinary input).
**Domain tag:** session.prep
**Status:** Resolved — fix landed 2026-06-12 (`ba4e1cae`); automated criterion met, manual criterion pending Matt's integrated-build run.
**Introduced:** structural — original `trackStatuses` construction.
**Resolved:** 2026-06-12 — commit `ba4e1cae` (cherry-pick of `679363a9`: fix A, `Dictionary(_:uniquingKeysWith:)` at both the streaming and LF `trackStatuses` builds).

**Expected:** a playlist containing the same track twice prepares normally; `PlaylistConnecting`'s doc (`PlaylistConnector.swift:57`) explicitly promises "Duplicate tracks preserve their playlist order."
**Actual (pre-fix):** `SessionPreparer.swift:183` built `trackStatuses = Dictionary(uniqueKeysWithValues:)`, which **traps at runtime on duplicate keys**. Duplicate tracks yield identical `TrackIdentity` values; same trap on the LF path (`:256`, an M3U listing the same file twice).
**Reproduction steps:** connect a Spotify playlist containing the same track twice; preparation crashed at dictionary construction. Reproduced automatically by the two regression tests (both trapped pre-fix).
**Session artifacts:** `docs/diagnostics/CODE_AUDIT_2026-06-09.md` §A2 (code-level evidence); pre-fix trap captured on both paths.
**Suspected failure class:** `api-contract` (Dictionary uniqueness precondition vs the connector's documented duplicate-preserving contract).
**Verification criteria:**
- [x] Automated: engine test preparing a track list with an exact-duplicate `TrackIdentity` completes without trapping (streaming + LF paths). — **Met** (confirmed trap pre-fix, green post-fix).
- [ ] Manual: a real Spotify playlist with a duplicated track reaches `.ready`. — **Deferred to Matt's integrated build** (the automated gate is the load-bearing crash-fix proof).

---

### BUG-049 — Skein colour-freeze cert gate is session-content-fragile: dominant-stem switch lands beyond the probe canvas extent → deterministic red on data, not code (2026-06-11)

> **RESOLVED 2026-06-11 — fix commit `a6899893`; armed-path validation COMPLETED the same evening via fixture-generated real captures (parallel session).** The "blocked on a real capture" gap below was closed by `FixtureSessionCaptureGenerator` (engine test target, `Diagnostics/`): env-gated, it runs vendored tempo fixtures (`love_rehab` / `so_what` / `there_there`, 30 s each) through the PRODUCTION pipeline — ffmpeg decode → `StemSeparator` (MPSGraph, 10 s chunks) → `StemAnalyzer` per 1024-hop (the `SessionPreparer.warmUpAndAnalyze` framing) → `SessionRecorder.csvRow` — and writes real stems.csv captures (FA #27-compliant; nothing hand-authored). Usage: `PHOSPHENE_GEN_SESSION_DIR="$HOME/Documents/phosphene_sessions" swift test --package-path PhospheneEngine --filter FixtureSessionCaptureGenerator`. **Validation results (2026-06-11 ~21:50–21:57):** criteria 1a/1b — with three `fixturegen-*` captures in the live dir, the gate ARMED (`picked fixturegen-so_what: stemA=2 lead 0.0316, stemB=1 lead 0.0226`) and SkeinCanvasHold ran 21/21 GREEN with 8+ recorder stubs simultaneously present; criterion 2 — with the freeze deliberately broken in `skeinLineLookupAt` (every τ takes the LATEST breakpoint colour, the literal Skein.4.1 recolour defect), the gate went RED on its headline assertion (PRE-switch X=0 Y=61); reverted → green (X=61 Y=0). Empty-dir leg: loud skip, green. The `fixturegen-*` captures stay IN PLACE so the armed path no longer depends on listening-session happenstance (regenerable with the one command; `session.log` records provenance). The original `13-10-42Z`-only criterion was unrunnable as written (capture deleted before any session could validate against it); the fixture-generated set substitutes.
>
> Original fix banner (fix session, same evening): **FIX LANDED 2026-06-11 (commit `a6899893`) — armed-path validation PENDING the next real session capture.** Single fix increment per the P2 process (root cause + verification criteria documented at filing, below; test-infrastructure-only, one test file). Three changes in `SkeinCanvasHoldTest.swift`: (1) the colour-freeze gate applies the line-792 sampling-window feasibility check DURING candidate selection — a CPU-only dry run (`switchSampleInfeasibility`) replays each candidate's tick sequence (tick never reads the GPU back, so it predicts the live run's windows exactly) and the scan walks candidates in decisiveness order, picking the most decisive switch that is ALSO sample-able; the in-run guard stays as a dry-run/live parity safety net. (2) When NO candidate arms (stub-only or otherwise unusable session sets), the gate skips LOUDLY with session/candidate counts + per-candidate rejection reasons — never red on session-set content (criterion 1), never a silent skip. (3) The Skein.3 real-stem routing gate (the same fragility's second face — red whenever the LARGEST session is a 602-byte stub) now scans all sessions for the first with usable frames and likewise skips loudly. The colour-freeze assertions themselves (pre-switch X≫Y, post-switch Y≫X, jump magnitude, new-pour-not-on-old-path) are untouched. **Validation status:** criterion 1's unusable-set arm is met (suite 21/21 green on the current stub-only set; both gates print their skip reasons); criteria 1a/1b (gate ARMS and passes on the real capture set) and 2 (adversarial colour-unfrozen A/B) are BLOCKED — the only real capture (`2026-06-11T13-10-42Z`, 2.98 MB) disappeared from `~/Documents/phosphene_sessions` between the 19:49 filing and the fix session (~21:30); only 11 header-only stubs remain, and the capture is unrecoverable from the fix session's environment (Trash TCC-denied; no quarantine copy, no snapshot). **After the next real listening session, re-run `swift test --package-path PhospheneEngine --filter SkeinCanvasHold`: expect `[skein_colorfreeze] picked …` (armed) and green, then run the criterion-2 A/B. If the parity safety net fires instead, the dry run and the live loop diverged — restore parity, do not widen the windows.**

**Severity:** P2 (the engine suite is red on every full run, so the closeout evidence battery cannot produce ALL GREEN for unrelated increments; no runtime impact).

**Domain tag:** test infrastructure / failure class `test-isolation` (session-content dependence).

**Expected.** The colour-freeze gate ("Line colour is frozen per-segment … — live path", `SkeinCanvasHoldTest.swift:792`) passes on a green tree regardless of which session captures happen to exist in `~/Documents/phosphene_sessions`.

**Actual.** Deterministic failure, identical numbers across 5+ runs: `Switch landed too close to a pour boundary to sample (preLo=7.652855 preHi=8.052645 postLo=8.161678 postHi=5.8849607)`. The selected session's dominant-stem switch sits at τ≈8.05 while the probe canvas only extends to probeTau≈5.88 (`postHi = min(switch+25·dtau, probeTau) < postLo`) — the sampling guard `Issue.record`s instead of skipping to another candidate switch or session.

**Reproduction / artifacts.** `swift test --package-path PhospheneEngine --filter SkeinCanvasHold`, 2026-06-11 evening; session dir contains `2026-06-11T13-10-42Z` (2.98 MB stems.csv — the only non-stub capture) plus five 602-byte stub captures from the day's app/test runs. Fails identically at HEAD (`31bb8307`) and at `4b83b4ef` (whose 19:02 evidence battery ran the same suite GREEN) — the engine-source diff between the green and red runs is EMPTY, proving environment-not-code. Quarantining the post-19:02 stub sessions does NOT clear it; the precise session-set delta between 19:02 and 19:49 could not be reconstructed (a capture present at 19:02 may have since changed or been removed — unverified). Evidence blocks: `~/.phosphene/last_closeout_evidence.md` (19:02 green @ `4b83b4ef`, 19:49 red @ `31bb8307`).

**Suspected failure class:** `test-isolation`, two compounding shapes: (1) app-test/battery runs append stub session captures (602-byte stems.csv) into the live `~/Documents/phosphene_sessions` directory engine tests consume — SessionRecorder runs from launch (D-025, archived); (2) the colour-freeze gate trusts its discovered switch location without verifying it is sampleable within the probe extent, and records an Issue instead of iterating — the exact fragility class the test's own `recordedSessionsBySize()` comment names ("a session-fragile gate goes red on data, not code — the Skein.4.1 `distinctBlobs` lesson").

**Verification criteria (written before any fix):** (1) automated — the gate passes with the `13-10-42Z`-only set, with stub sessions present, and with an empty session dir (skip with a printed reason, never silently); (2) manual/adversarial — the gate still FAILS on a deliberately colour-unfrozen canvas (keep its teeth; A/B per the Skein.4 transient-metric lesson).

**Found by:** the RB.2-2 closeout evidence battery (19:49), diagnosed same evening. Not an RB.2-2 regression (docs-only increment).

### BUG-048 — `xcodebuild test` ran the engine test bundle in a runner context that denies subprocess/audio/file access: ~30 environment-class failures on every run, in every terminal (2026-06-11)

> **RESOLVED 2026-06-11 (commit `e110b1ca`)** — Single fix increment per the P2 process (root cause documented before code; the fix is one scheme edit + one regression gate). Matt picked the fix option in chat ("scope and run the option-1 increment"). Discovered by the REVIEW.3 closeout evidence script on its first three runs — exactly the defect class the script exists to surface.

**Severity:** P2 (the canonical app-test invocation was permanently red, so a true app regression could not have been distinguished from the noise floor; no runtime impact).

**Domain tag:** test infrastructure / failure class `test-isolation`.

**Expected.** `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test` (the canonical app-test invocation, CLAUDE.md + RUNBOOK §Build and Test) exits 0 on a green tree.

**Actual.** Exit 65 on every run. The scheme's test action had included `PhospheneEngineTests` since U.1; under xcodebuild's test-runner context the engine bundle hits environment denials that `swift test` does not: ffmpeg subprocess spawn fails (`Error opening input: Operation not permitted` on fixture decode), the REVIEW.2 audio churn tests die in ~1 ms, `DocIntegrityTests` reads an empty DECISIONS.md (repo file reads denied — `(!dec.isEmpty → false)`), and only ~440 of the engine suite's 1439 tests load at all. The pure app run (382 tests) passed inside the same invocation.

**Reproduction / artifacts.** Three closeout evidence blocks, 2026-06-11: sandboxed shell (12:14), unsandboxed shell (12:21, commit `03b27340`), and Matt's own terminal (18:59, commit `23298c64`) — identical failure signature in all three, ruling out the shell environment. Blocks archived at `~/.phosphene/last_closeout_evidence.md` per run and in the REVIEW.3 session transcript.

**Suspected → confirmed failure class.** `test-isolation` — the tests are correct; the xcodebuild runner context (sandbox/entitlements of the test host) denies the environment they need. Same family as the FA #66 fixture/live parity gap: two runners, two environments, one suite.

**Fix.** Removed the `PhospheneEngineTests` `TestableReference` from `PhospheneApp.xcscheme`'s test action (option 1, Matt's pick over making the engine bundle xcodebuild-compatible — double-running 1439 tests in a broken environment added noise, not coverage). The engine suite's canonical runner remains `swift test --package-path PhospheneEngine`; `xcodebuild test` now means "app tests," which is what the 305/382 baseline always actually measured. Regression-locked by `SchemeTestActionRegressionTests` (engine suite): fails loudly if the engine bundle is re-added to the test action, or if the app test target is ever dropped from it.

**Verification (pre-stated, met).** Automated: `xcodebuild test` exits 0 with `** TEST SUCCEEDED **`, 382 app tests green, no engine-bundle run in the output; the new gate passes; full closeout evidence block at the docs commit. Manual: Matt re-runs `Scripts/closeout_evidence.sh` from his terminal — the app step should now be green (pending his next run).

### BUG-047 — FFO aurora palette MARCHES through its colour stops second-by-second on mood-wobbly tracks: the orbit azimuth multiplied arousal-speed into the ENTIRE elapsed total, retroactively rescaling history (2026-06-11)

> **RESOLVED 2026-06-11 (FBS.S5d)** — found via Matt's So What read ("the color of the ocean was changing every 1-2 seconds… it marches through the palette") after two wrong attributions in-session (mood tint; curtain-vs-base contrast — the latter an R−B metric artifact, see Verification). Trivial-collapse justified: root cause obvious once the per-frame azimuth trajectory was printed (algorithm-class, code contradicts its own design comment), fix < 60 lines across the established driver pattern, no architectural risk.

**Severity:** P2 (character-breaking: the whole ocean visits green/pink/purple second-by-second on affected tracks; violates Matt's directed 8–10 s colour pacing and the round-61 tuned orbit).

**Domain tag:** `preset.fidelity` / failure class `algorithm`.

**Expected.** The aurora curtain's palette position drifts through pink/green/purple at the round-61 pace (~25–37 s per revolution; ≤ ~0.03 palette-t/s), with arousal scaling the orbit SPEED (the round-55 design comment).

**Actual.** `rm_ferrofluidSky` computed `curtainAzimuth = accumulated_audio_time × arousalSpeed(arousal)` — the speed factor multiplied the ENTIRE elapsed total. Any arousal movement retroactively rescaled history: with the mood classifier wobbling per-second on jazz (So What arousal swings ±0.3–0.5/s), the azimuth thrashed ±2+ rad/s and palette-t jumped 0.2–0.3/s across colour stops. The error scales with elapsed accumulated time — track openings looked fine (aat < 1), minute two marched (aat 5–7). Love Rehab's early windows masked it (small aat + steadier mood).

**Reproduction / artifacts.** Session `2026-06-11T13-10-42Z`, So What te 56–80: per-frame azimuth trajectory printed from features.csv (az 12.19 → 10.04 in 1 s; palette zone GREEN→PINK→GREEN→PINK→PURPLE second-by-second); per-second frame-mean hue measured from the video (green +138° → pink −45° → purple −104° within seconds); 12-frame montage confirmed by Matt ("yes, it marches through the palette").

**Fix.** Integrate, don't multiply: `RenderPipeline.auroraOrbitStep` advances `azimuth += arousalSpeed × Δaccumulated-audio-time` per frame (base period 2.5 s verbatim); ships as `StemFeatures.auroraOrbitAzimuth` (float 47); the shader reads it. Track-change resets (negative Δ) advance nothing.

**Verification (pre-stated, met).** Pixel A/B through the forensics replica with a new wrap-aware HUE-ANGLE metric (the prior R−B metric is blind to green↔purple legs — that blindness produced the session's earlier wrong "contrast amplifier" reading): So What 56–80 per-second hue swing **94.7°/s (legacy arm) → 3.3°/s (integrated)**; Love Rehab stays calm-and-alive (4.9°/s). `AuroraOrbitDriverTests`: history-rescale immunity under worst-case wobble at minute-two scale, arousal still scales speed 2×, track-reset holds. Manual: Matt's next live read on So What.

### BUG-046 — Skein's section response rides BUG-042's note-scale junk on streaming material: the confidence gate passes boundaries every ~1.7 s at conf 0.78–0.95 (2026-06-11)

> **RESOLVED 2026-06-11 (Skein.6, pre-certification)** — Trivial-collapsed P2 per CLAUDE.md §Defect Handling Protocol (one guard + one constant + one regression gate; root cause fully evidenced from the M7 session artifacts before any code; Matt picked the fix option in chat — "Add a section-spacing guard"). Found during the Skein.6 M7 session review; fixed before flipping `certified: true` at Matt's direction ("If anything looks concerning, let's fix it before we certify").

**Severity:** P2 (the certified preset's character silently differs by audio source: on busy streaming material the splatter runs ≈1.6–2.2× the Matt-tuned round-2 rate and pours chop at ~1–1.7 s — the rejected D-150 "lines too short" character — while local-file material keeps the tuned behaviour).

**Domain tag:** `preset.fidelity` / failure class `calibration` (a downstream consumer trusting an upstream signal whose failure mode pins the gate's pass condition).

**Expected behavior.** Skein's structure response (flurry pulse + boundary-forced fresh pour + region lean, D-152) fires on real musical section changes — every 15–60 s — and its confidence gate (smoothstep 0.25→0.55) suppresses detector junk. The Skein.6 cert premise was "the structure sub-feature is conf-gated to zero on BUG-042's junk."

**Actual behavior.** BUG-042 (parked: section-detector note-scale geometry) machine-guns boundaries every ~1.7 s on busy streaming material **at confidence 0.78–0.95** — far above the gate top, so the junk flows through at full strength. The cert premise held on the approved local-file sessions only because the detector stays quiet there (conf ≈ 0). Mechanically: the flurry pulse (τ 2.5 s) is re-armed every ~1.7 s → effectively permanent ≈1.6–2.2× spatter-rate boost; `boundaryPourPending` forces pours at the 1.0 τ floor instead of the 2.65 τ min-dwell.

**Reproduction / artifacts.** M7 session `2026-06-11T01-56-22Z` `features.csv` section columns: `section_index` +6 per 10 s sustained (≈1.7 s cadence), `section_confidence` 0.78–0.95, during both Skein windows. Contrast the approved sessions `2026-06-10T19-48-27Z` / `20-05-48Z`: conf 0.0–0.7, boundaries rare. Replay gate: machine-gun structure (boundary/1.67 s @ conf 0.9) on identical tiled single-dominant real stems → 16 pour breaks / 1650 spawns in 30 s vs the sparse control's 2 / 1091 (A/B-validated by reverting the fix).

**Fix (Matt's pick).** `SkeinState.minSectionSpacingS = 10` wall-seconds: a boundary inside the spacing window of the last ACCEPTED boundary is ignored wholesale (`updateSectionBias`). Wall seconds, not painter τ (τ runs 1.5–2× wall on busy music — the first guard draft used τ and leaked ~6 s spacing). Real section changes (≥ 15 s apart) pass untouched; the guard stays harmless after the eventual BUG-042 detector fix. BUG-042 itself remains OPEN and PARKED — this is a consumer-side robustness guard, not the detector fix.

**Verification (pre-stated, met).** Automated: `test_structure_boundarySpacingGuard` — machine-gun replay → 4 breaks / 1250 spawns (≤ 6 / ≤ 1.5× control; unguarded 16 / 1650 trips both asserts), sparse boundary still lands its fresh pour; the existing `test_structure_boundaryBias` (single confident boundary flurries + leans, low-conf exactly zero) stays green. Manual: next streaming Skein listen — pours stay long and spatter stays at the tuned rate on busy material.

### BUG-045 — FFO aurora hue strobes: vocals-pitch confidence flaps across the hue gate ~9×/s, snapping the reflected sky's colour and stepping whole-frame luminance (2026-06-10)

> **RESOLVED 2026-06-10 (FBS.S5, D-158)** — the "remaining flasher" after D-157's regional punches. Diagnosis and fix landed in one session because the fix IS Matt's independently-directed character change ("the aurora color is shifting too quickly… transition over a longer length of time, e.g., 8-10s") — the multi-increment split was honored within the session: forensics-proof commit first (`ef4fb8e0`), fix commit second (`0159c54f`).

**Severity:** P2 (visible whole-frame flashing on FFO mid-track, "prominent on some tracks" — Matt, S4 read of session `2026-06-10T19-13-14Z`).

**Domain tag:** `preset.fidelity` / failure class `calibration` (an ungated per-frame input driving a scene-wide chromatic surface).

**Expected behavior.** The aurora curtain's hue follows the vocal register/mood smoothly; the reflected sky never changes colour at frame rate.

**Actual behavior.** `rm_ferrofluidSky` computed the palette phase per-pixel from raw `vocals_pitch_hz`/`vocals_pitch_confidence`. On real music the confidence crosses the smoothstep(0.5, 0.7) gate ~9×/s (90 crossings in the 10 s So What window), snapping the phase between the pitch path and the valence fallback — up to 0.4 of palette phase, across palette stops (pink↔green↔purple differ ~2× in luma). At curtain intensity 2.5–5.5 mirrored across the whole substrate, each snap stepped the entire frame's mean luminance (video: 72–84-luma flashes).

**Reproduction / artifacts.** `FerrofluidFlashForensicsTests` on session `2026-06-10T19-13-14Z`: replicating the pitch fields took the replica 1 → 13 flash steps (So What seg2 31–41 s) and 0 → 15 (Lotus seg5 45–51 s); the new `PHOSPHENE_FLASH_ABLATE=aurora-hue` arm (zeroing only those two fields) restored 1 / 0 — the route is convicted mechanically, not by input correlation.

**Fix (D-158).** The same composite phase math runs CPU-side (`RenderPipeline.auroraHueStep`, pure fn) behind a τ ≈ 3 s EMA — gate flapping averages to a stable intermediate hue; a sustained vocal entry glides the hue over ~9 s (Matt's directed window). Shipped to the shader as `StemFeatures.auroraPalettePhase` (float 45); the shader reads one smoothed value. Companion (same directive): `auroraDriverStep` intensity τ rise/fall 0.45/1.2 → 2.7/3.3 s.

**Verification (pre-stated, met).** Automated: the four forensics windows re-rendered post-fix → 1/0/1/0 flash steps with localized punch deltas preserved; `AuroraHueDriverTests` pins flap immunity (≤ 0.005/frame under worst-case flapping), the 8–10 s step response, and converged-target fidelity to the pre-S5 shader formula. Manual: **Matt's live read of `2026-06-10T20-26-37Z` CONFIRMS the hue fix** — "some remaining flashing happening, but mostly gone" (census: 79 → 13 events/154 s; zero trace to the hue). The residual cold-start events were ablation-attributed to the global bridge heave (a D-158-amendment design question, not this defect); 3 unreproducible one-frame blips suspected video-encode, parked.

### BUG-044 — Local-file next/prev/EOF never wipes the Skein canvas: one painting accumulates across every track (2026-06-10)

> **RESOLVED 2026-06-10** — Trivial-collapsed P2 per CLAUDE.md §Defect Handling Protocol (root cause obvious from the session log + a one-helper extraction, no architectural risk; collapse stated explicitly here and in the commit). Landed on the Skein.5.4 branch `claude/skein54-splatter`; reaches main with the 5.4 merge.

**Severity:** P2 (preset contract violation: the §1.5 "a new track paints its OWN canvas" / §5.7 "same song → same painting" properties silently break for every local-file session with more than one track; pre-existing on main since Skein.3 — newly observed because 5.4's eyeball-gate listen was the first multi-track LF Skein session).

**Domain tag:** `pipeline-wiring` (the BUG-024 complementary-path class: per-track preset state reset on the streaming path only).

**Expected behavior.** On any track change — streaming metadata callback OR local-file next/prev/natural-EOF advance — an active Skein wipes the canvas to the new track's palette ground and re-seeds the painter from the new track's identity (Skein.3 §1.5 + 5.3b), and an active Nimbus settles (NB.4).

**Actual behavior.** Local-file advances (`advanceLocalFileQueue`) never wiped: the LF.5.fix.2-FU3 "mirror the streaming callback's destructive resets" block predates Skein.3, and the Skein wipe (added 2026-06-05) + Nimbus settle were only ever wired in the streaming callback (`VisualizerEngine+Capture.swift`). The painting accumulated across tracks; the wipe the user saw at the first transition was the preset-APPLY clear, not a track-change wipe.

**Reproduction.** LF session ≥ 2 tracks, Skein active, press next: canvas keeps the previous track's paint. Session `2026-06-10T19-48-27Z` (the evidence artifact): Skein active continuously from 19:51:15; five `resetStemPipeline caller=trackChange` advances (19:51:27 → 19:52:00) with zero wipes; no `preset → Skein` re-apply between them.

**Fix.** Extract the per-track preset-state reset (Nimbus settle + Skein reseed → ground override → `clearMVWarpCanvasToGround`) into the shared `VisualizerEngine.resetPerTrackPresetState()`, called from BOTH paths. On the LF path it runs AFTER `applyLocalFileTrackState` (the Skein reseed derives from `lastResolvedTrackIdentity`, which that helper sets) and logs a `WIRING:` breadcrumb so the next session artifact verifies it.

**Verification criteria (pre-stated).** Automated: `TrackChangePresetResetRegressionTests` — the helper exists once, both call sites invoke it, neither re-inlines the wipe, and the LF call is ordered after the identity apply. Manual: next multi-track LF listen — every next/prev wipes to a fresh ground (the session.log shows `advanceLocalFileQueue resetPerTrackPresetState COMPLETE` per advance).

### BUG-024 — Stale LF artwork bleeds into streaming sessions (LF.6, 2026-06-01)

> **RESOLVED 2026-06-01** — Trivial-collapsed P1 per CLAUDE.md §Defect Handling Protocol (< 5 lines, root cause obvious, no architectural risk). Landed as the one-commit `[LF.6.fix.1]` increment.

**Severity:** P1 (visual mis-attribution: the chrome rendered the wrong album's artwork against every streaming track for the entire post-LF session lifetime).

**Domain tag:** `pipeline-wiring`.

**Expected behavior.** When transitioning from an LF session (with embedded artwork) to a streaming session, `engine.currentTrackArtworkData` becomes `nil`. `TrackInfoCardView.showArtworkSlot` evaluates `(albumArtData != nil) || isLocalFileSession` → `false` for streaming + nil → slot hides entirely. The streaming chrome renders text-only — visually identical to pre-LF.6 streaming chrome. (The LF.6 kickoff's Critical Invariants section: *"Streaming-path behaviour is byte-identical to pre-LF.6. `engine.currentTrack` continues to be set by `makeTrackChangeCallback` for streaming, `currentTrackArtworkData` stays `nil` on streaming sessions."*)

**Actual behavior.** `engine.currentTrackArtworkData` retained the previous LF session's bytes indefinitely. The streaming track-change callback at [VisualizerEngine+Capture.swift:189-202](PhospheneApp/VisualizerEngine+Capture.swift:189-202) wrote `self.currentTrack = event.current` for every streaming track but never touched `currentTrackArtworkData`. The `@Published` retained the LF bytes. `TrackInfoCardView.showArtworkSlot` evaluated `true` (stale bytes) → rendered the wrong art (e.g. The Cure's Kiss Me cover for every Spotify track).

**Reproduction (Matt's manual smoke, 2026-06-01).**
1. Open `02_cure_m4a.m4a` via Open Local File (LF session with MP4 covr atom artwork).
2. End the LF session.
3. Start a Spotify playlist with multiple tracks (e.g. Radiohead "There, There" + Chaim "Love Rehab").
4. Observe: every streaming track's chrome card shows The Cure's Kiss Me cover in the artwork slot, regardless of the actual track's identity.

**Session artifacts.** Three screenshots from Matt's smoke session: Radiohead track + Chaim track both displaying The Cure's artwork. No session.log captured — visual evidence is the load-bearing artifact.

**Suspected failure class.** `pipeline-wiring`. The LF.6-L2 implementation correctly publishes `currentTrackArtworkData` on every LF state-change site (`handleLocalFileReady` + `advanceLocalFileQueue`) via `applyLocalFileTrackState(...)` but doesn't clear the publisher on the streaming or session-boundary paths. The publisher's last value persists across session and source transitions.

**Verification criteria.**
- *Automated:* extend `PlaybackChromeArtworkBindingTests` with a "LF → streaming transition: artwork-nil emission clears prior LF bytes" case.
- *Manual:* re-run Test 4 from the LF.6 smoke (LF session → end → Spotify playlist). Expected: streaming chrome text-only, no artwork tile, no fallback glyph (slot entirely hidden, card geometry matches pre-LF.6).

**Root cause.** Two LF.6 sites write `currentTrack` (LF: `publishLocalFileTrackSurface`; streaming: `makeTrackChangeCallback`). Only the LF site was paired with a `currentTrackArtworkData` write. The streaming site needs the same pairing (writing `nil` to clear the publisher). Additionally, the `.connecting` state-observer is a natural session-boundary clearing point — adding the clear there is defense-in-depth for ad-hoc / reactive paths that may not fire a track-change callback immediately.

**Fix.**
- `[LF.6.fix.1]` ([VisualizerEngine+Capture.swift:190](PhospheneApp/VisualizerEngine+Capture.swift:190)): streaming track-change callback writes `self.currentTrackArtworkData = nil` alongside `self.currentTrack = event.current`, back-to-back in the same MainActor block.
- `[LF.6.fix.1]` ([VisualizerEngine.swift:807](PhospheneApp/VisualizerEngine.swift:807)): `.connecting` state observer clears `currentTrackArtworkData = nil` alongside `currentSessionPlanSeed = nil`.
- `[LF.6.fix.1]` ([PlaybackChromeArtworkBindingTests.swift](PhospheneAppTests/PlaybackChromeArtworkBindingTests.swift)): new "LF → streaming transition" regression test (6 tests in suite total).

**Resolved:** 2026-06-01, commit `45021472`.

---

