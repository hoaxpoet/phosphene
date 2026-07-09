# Phosphene — Known Issues

Open and recently-resolved defects. Filed using `BUG_REPORT_TEMPLATE.md`. See `DEFECT_TAXONOMY.md` for severity definitions and process.

## Open Index

| ID | Sev | Domain | One-liner |
|---|---|---|---|
| BUG-067 | P3 | preset.fidelity / regression | **main's full battery is red on `PresetContrastCertificationTests`** — Ricercar (FL.5 fluid-dye state on main, light ground) fails the WCAG overlay-contrast gate deterministically on all three fixtures (contrast 3.52 < 4.5; reproduced in isolation, QG.1 pre-flight 2026-07-09). Not environmental and not new: main's Ricercar is superseded by the unmerged `claude/ricercar-rework` branch (FL.10 flow-field, M7-passed 2026-07-08, dark ground). Expected to resolve when the rework merges — verify the contrast suite goes green at that merge before closing; if it does not, this becomes a real FL.10 defect. No code change on main warranted meanwhile |
| BUG-066 | P2 | ml.mood / dsp.mir | **✅ RESOLVED 2026-07-08 (MOOD-FLUX.2, `1d61830`) — Matt signed off on the objective `--mood-ab` before/after (no live M7; an eyeball made no sense for a diffuse scoring change).** The OFFLINE session-prep mood flux input ran **16× hot** (CENSUS.3 measured feat7 mean **8.06** vs scaler **0.25**, z ≈ +38 → saturated on every track). Root cause was NOT the model (correctly trained on live features — the live training CSV flux mean 0.2516 = the scaler): the offline `analyzeMIR.computeFFTMagnitudes` **reimplemented the FFT magnitude formula** differently from the live `FFTProcessor` — `sqrt(power/fftSize)` (=\|FFT\|/32) vs live `\|FFT\|×2/fftSize` (=\|FFT\|/512), a uniform 16×. Flux is the only exposed feature (fed raw to the z-score; bands AGC-normalized, centroid a ratio). `analyzeMIR` sets `TrackProfile.mood` (30 % of the preset scorer) → offline preset selection ran on 9 effective features; the live path was always fine. **Fix:** align the offline formula to live (`zvabs` + `×2/fftSize`). Validated: flux z **+38 → +1.43**, uniform 16× correction (σ=0), 103 mood/MIR/session tests green incl. the classifier golden (unchanged); blast radius benign (mir_bpm 0/40 changed, key harmless). **Objective sign-off** (`--mood-ab`, 80-track sample): before, saturated flux railed arousal high for every track → non-discriminative "happy"; after, arousal spans [−0.87,+0.81], spread ~doubled, **32 % of tracks flip mood quadrant** in the correct direction. Full record: [`BUG-066-diagnosis.md`](../diagnostics/BUG-066-diagnosis.md). Files to §Resolved at next pruning. |
| BUG-065 | P3 | dsp.beat | **Live BeatGrid phase drifts off the audible beat over a track** — the cached grid has the right BPM but `LiveBeatDriftTracker` *bounds* the live drift without *tightening* it: drift grows ~11 ms (track start) → **50–70 ms (mid/late-track)**, and **28 % of frames exceed the ~60 ms perceptual window** (evidence: session `2026-06-29T12-43-51Z`, Cherub Rock 171.3 BPM 4/4 — drift-by-10s-window 11/37/49/54/69/66/55/48 ms; lock_state=2 only 67 %-within-60 ms). **Caps how frame-locked beat-driven presets can feel** — the live example is Glaze's GLAZE.7 downbeat push (reads connected but not *tight*; tightest early, loosens as the track plays). NOT a functional break (phase is approximately right). **Suggested improvement (Matt 2026-06-29):** live re-lock / cached-BPM-error correction so drift holds < ~30 ms across the track. The cold-start *automated phase* premise was retired (CLAUDE.md §Cold-Start), but this is **mid-track drift convergence** — a different surface (the tracker should tighten, not just bound). Logged for a dedicated beat-sync session |
| AUDIT-2026-06-09 | P2/P3 | audit backlog | Full-codebase audit findings not individually filed |
| BUG-064 | P1 | dsp.beat / preset | **✅ RESOLVED 2026-06-29 — Matt live-confirmed (sessions `…T02-29-56Z` "looks good" + `…T12-49-44Z` "much better"; instrument now removed). Files to §Resolved at the next pruning pass.** Lumen froze during local-file playback (correct but static mosaic — cells don't recolour, faint pulse only; Spotify worked). The `LUMEN_DIAG` buffer-binding probe **disproved my initial "stale slot-8" guess**: `boundIsEngine=true` every frame and the bound buffer's bytes tracked the engine state exactly. Real cause: the cell-step **band counters stalled** — they advance on `beatPhase01` wraps detected by `prev > 0.85 && now < 0.15`, but the analyzer publishes `beatPhase01` at ~10 Hz, so on a fast track (171 BPM) it advances in ~0.27 jumps that **skip both narrow windows** (`0.795→0.109` has prev < 0.85; `0.934→0.203` has now > 0.15) → ~5 of ~34 beats register, then none → cells freeze, lights (driven separately) still pulse. **Fix:** detect a wrap as a half-cycle phase **drop** (`prev − now > 0.5`), robust to step size. Regression `test_bug064_largeStepWraps_stillIncrementCounter` (recorded 171-BPM trajectory: old detector 0 wraps, new 4). **Validated live:** counters climb steadily (bass 2→100/151, no stall), `boundBass` tracks, 0 degenerate frames. **Follow-up (LM.5, ✅ live-confirmed 2026-06-29 — session `…T13-43-33Z`, Matt "looks good" on a fresh local track):** the ~10 s static-*lights* warmup (cells animated from frame 1, but the cached-stem snapshot froze the four lights) is fixed — `setStemFeatures(_:live:)` tags the cached snapshot not-live and `LumenPatternEngine.tick(…, stemsLive:)` drives the lights from the FV fallback (Layer 1 continuous energy) until the live analyzer converges. Regressions `test_bug064_notLiveStems_driveFVFallback_notFrozenSnapshot` + `…_liveStems_stillUseStemDirect`. (Known minor: vocals has no FV proxy → that one light stays dark until live stems arrive; left as the D-019 contract.) |
| BUG-063 | P1 | renderer / render-state | **✅ RESOLVED 2026-06-29 — subsumed by BUG-064.** The slot-8 triple-buffer regression was reverted to the known-good single buffer (2026-06-27); the Lumen-freeze it tracked was then root-caused + fixed under BUG-064 (the cell-step wrap detector) and Matt live-confirmed (sessions `…T02-29-56Z` "looks good" + `…T12-49-44Z` "much better"). The `LUMEN_DIAG` instrument this entry kept "for the confirm" has been removed (`17ebfe5`). No separate confirm outstanding. Files to §Resolved at the next pruning pass. Original report below. Matt (session `…T21-14-35Z`): Lumen "worked like a dream before" and is now frozen nearly the whole playback ("moved twice"), with only a faint beat pulse and **no cell-colour change** — "possibly the worst yet." The data proves the regression: `beatPhase01` wraps every beat (grid locked, 171 BPM) and the CPU band counters + light intensities advance, **yet the GPU image is frozen** — a stale slot-8 read. The one change to that path since the known-good Lumen (`cb8cb0b`/the LM.* work) is **`f5ad0e2` (slot-8 triple-buffering)** — built on the *unverified* slot-8-race theory, which Matt's own data had already disproved. The single buffer was UMA-coherent and delivered slot-8 every frame; the 3-slot ring + per-frame rebind does not, so the cells freeze. **Action:** reverted BOTH BUG-063 fix attempts — `f5ad0e2` (triple-buffer regression) and the layered warmup gate (never reached Matt's build) — restoring `LumenPatternEngine` + its tests to the exact known-good `cb8cb0b` state (single `patternBuffer`, bound once); BUG-016 palette test preserved. The `LUMEN_DIAG` instrument stays for the confirm. ✅ engine build + 31 Lumen suites + app build + lint 0. **Pending:** Matt's live confirm Lumen animates like a dream again. **Secondary, deferred:** the frozen-stem-warmup observation (first ~10 s: cached 5a snapshot byte-identical → lights track it; sessions `…T18-37-39Z`/`…T21-14-35Z`) is real but is NOT this regression — re-scope cleanly off the restored baseline if it matters. **Lesson:** the slot-8 "race" was never reproduced; f5ad0e2 fixed a non-problem and created a real one. Fix history: `f5ad0e2` (triple-buffer — the regression, reverted), warmup gate (reverted), instrument `b1af31e`/`39c059a` (kept). |
| BUG-062 | P1 | renderer / regression | **✅ RESOLVED 2026-06-26 (Matt live-confirmed — session `2026-06-26T21-07-18Z`, "all presets appear now"; `6848118`, origin/main). Regression from BUG-061 (`00b0625`).** Nimbus (and Aurora Veil) froze: advancing to it displayed the *previous* preset's last frame, "unfreezing" only when switching to the next/previous preset (session `2026-06-26T20-28-03Z`: `preset → Nimbus` ×4, each bounced to Nebula ~2–4 s later; zero Metal/pipeline errors — a silent non-present, not a crash). **Root cause:** BUG-061 wrapped `renderFrame` in `if willRenderActiveFrame` (`!activePasses.isEmpty`) to skip the transient preset-swap window, on the stated premise "every applied preset has non-empty passes." False — Nimbus + Aurora Veil are direct-fragment presets that ship `"passes": []` → `activePasses` is *permanently* empty → `renderFrame`/`drawDirect` never runs → the drawable is never presented → frozen prior frame. They are the only 2 sidecars with empty passes; every other preset has ≥1 pass, so the freeze is unique to them. Headless render tests call `renderFrame` directly (bypassing `draw(in:)`'s guard), so CI never caught it. **Fix (engine, 1 line):** `PresetDescriptor` decode normalises an explicit empty `passes` array to `[.direct]` — identical to omitting the key (see `renderPassDefaultIsDirect`) — restoring the guard's premise; BUG-061 stays fixed (mid-swap `setActivePasses([])` still yields empty → skip). Render output byte-identical (PresetRegression goldens non-drift; `[.direct]` → same `drawDirect` path). Regression: `renderPassExplicitEmptyArrayNormalisesToDirect` + corpus guard `shippedPresets_neverDecodeToEmptyPasses`. **Manual (required):** Matt's live confirm that Nimbus + Aurora Veil render and animate with no freeze. |
| BUG-061 | P1 | renderer / render-state | **✅ RESOLVED 2026-06-25 (NACRE.2b)** — Nacre crashed on load (session `20-51-58Z`, log ends at `preset → Nacre`; no `.ips`). **Root cause = a preset-apply race (the BUG-060 class).** `applyPreset` (main thread) clears `activePasses` to `[]` then republishes them only at its end, while `draw(in:)` runs on MTKView's display-link thread; a frame in that window sees empty passes + the new preset's already-published direct pipeline → `renderFrame` falls to `drawDirect`, sending the direct pipeline to the 8-bit drawable. 8-bit presets survive (benign stray frame — the intermittent BUG-060); Nacre's `.rgba16Float` direct pipeline → 8-bit drawable is a hard format mismatch (Metal-validation-gated → abort in the Debug build). **Nacre is the deterministic reproducer BUG-060 lacked.** Fix: `draw(in:)` skips the frame while `activePasses` is empty (`willRenderActiveFrame`) — fixes Nacre + the BUG-060 class for all presets. Secondary latent fix: `renderNacreReducedMotion` (the reduced-motion path had the same direct→drawable mismatch; reduce-motion was OFF this session, so NOT the trigger — my initial reduced-motion diagnosis was an unverified assumption, corrected). Regression: `test_emptyActivePasses_skipsRenderFrame` + `test_reducedMotion_…`. Files to §Resolved at the next pruning pass |
| BUG-060 | P3 | renderer / app.hang | One-off app hang (force-quit required): render loop died one frame after a `preset → Gossamer` switch (`22-10-50Z`); NOT reproduced (Gossamer ran 3× clean in `13-57-23Z`); no stack captured. Monitored |
| BUG-059 | P1 | local-file / concurrency | **✅ RESOLVED 2026-06-18** (`a285a22`, integrated to `main`/origin) — concurrent `LocalFilePlaybackProvider` start/stop ABBA deadlock (`player.stop()`'s completion-queue `dispatch_sync` ⇄ inline `scheduleFile()` from the completion handler); fixed by hopping the re-schedule off the completion queue. Automated 11/11 + Matt's live no-hang device-swap validation. (The track restart-on-swap Matt saw is the separate BUG-056.) Files to §Resolved at the next pruning pass |
| BUG-058 | P3 | audio.capture / resource-management | RARE intermittent: a mid-session output-device swap *occasionally* freezes the tap (`performReinstall` doesn't complete; stale-buffer freeze, not silence). G1 device-swap recovery is otherwise robust (validated 12/12, 2026-06-17); the single freeze was un-reproduced — likely a `coreaudiod`-settling transient. Instrumented |
| BUG-057 | P1 | audio.capture | **✅ RESOLVED 2026-06-17 (D-165)** — silent-tap family closed: detector card + reinstall-fix (no rebuild of a working tap on a pause) + card pause-suppression, all validated + pushed. Residual = environmental wedged-`coreaudiod` only (`killall coreaudiod` workaround; not a code bug). Detail entry files to §Resolved at the next pruning pass (`rotate_docs.sh`) |
| BUG-056 | P3 | local-file / audio | Local-file playback restarts the track from the top on an output-device change (AVAudioEngine teardown/restart, no resume-from-position) |
| BUG-055 | P2 | app.ui / permission | Silent system-audio tap after a rebuild: stale Screen-Recording grant; `CGPreflightScreenCaptureAccess` returns stale-`true` → app shows "ready", renders a flatline, no guidance |
| BUG-054 | P3 | dsp.key | Key detection has never been accurate enough to use — 1024-pt FFT can't resolve semitones < 1 kHz, full-mix chroma, no constant-Q. Non-load-bearing today |
| BUG-051 | P3 | local-file / security | m3u entry paths resolved with no extension/traversal guard (bounded: no egress) |
| BUG-050 | P2 | resource-management / perf | **✅ RESOLVED 2026-06-17 (reframed)** — video gate landed (frame loop halved 15.78→~8.1 ms; `video 0 appended`); the "Activity Monitor halves" criterion was a misdiagnosis (the ~2-core cost is live stem separation, not the recorder) — retired |
| BUG-034 | P1 | renderer / test-isolation | **✅ RESOLVED 2026-06-12** — ray-march fixtures rendered at 32 vs live 128 (`sceneParamsB.z` double-booked); single-meaning step multiplier + `StepBudgetParityTests`, goldens regen. Files to §Resolved at next pruning |
| BUG-035 | P2 | dsp.structure | **✅ RESOLVED 2026-06-09** — NoveltyDetector re-detected boundaries ~4-5× after similarity-ring wrap; fixed pre-Skein.5 (residual section-scale geometry tracked as the open BUG-042). Files to §Resolved at next pruning |
| BUG-036 | P2 | audio.capture / performance | Heap allocations on the real-time audio thread (three sites) |
| BUG-037 | P2 | preset.fidelity | ✅ RESOLVED 2026-06-18 — Arachne pop fixed (chord-count single-source + wait_for_completion spans sections); files to §Resolved at next pruning |
| BUG-042 | P2 | dsp.structure | **✅ RESOLVED 2026-06-19** — 2 Hz section-scale decimation + `minNoveltyFloor` 0.02→0.01; live-validated SLTS (5 sections, conf 0.91). Preset-variety follow-ups (reactive scoreGap; LF planning re-enable) tracked under LFPLAN. Files to §Resolved at next pruning |
| BUG-043 | P2 | pipeline-wiring | Mid-playback 9.6 s analysis stall froze visuals, then lurched |
| BUG-041 | P2 | dsp.stem / preset.fidelity | FFO aurora flashes at track start (stem-deviation cold-start overswing) |
| BUG-039 | P2 | resource-management | **✅ RESOLVED 2026-06-18** — silent-stop running-vs-writing invariant + segment-roll recovery (CLEAN.3.6); Matt's live multi-session confirm passed (signature no longer occurs). Files to §Resolved at next pruning |
| BUG-040 | P2 | dsp.structure | **✅ RESOLVED 2026-06-10** — live-edge boundary every ~4 detect intervals; fixed (frozen-clock unfreeze + live-edge guard + absolute novelty floor; residual section-scale geometry tracked as the open BUG-042). Files to §Resolved at next pruning |
| BUG-029 | P3 | dsp.beat | AGC `f.bass` cold-start spike pops presets at every track onset — **AGC3.3 fix PARTIAL (reopened 2026-07-08 after a false close); hard-onset tracks still spike 14.8× (session 2026-07-09T02-04-02Z)** |
| BUG-028 | P2 | dsp.beat | Beat-grid live phase imperfect on ~half of tracks |
| BUG-027 | P2 | dsp.beat | **✅ RESOLVED 2026-06-06 (D-146)** — positive band deviations near-dead for non-dominant bands; fixed via the AGC2 per-band EMA deviation pivot (the system-wide "true 0.5 centre" normalization remains a separate future project, not a reopen). Files to §Resolved at next pruning |
| BUG-025 | P3 | dsp.beat | AGC running average poisoned by post-`active` startup transient |
| BUG-026 | P2 | session.ux | No warning when tap signal level is structurally insufficient |
| BUG-014 | P3 | preset.fidelity | Lumen Mosaic panel aggregate uniform across tracks |
| BUG-013 | P2 | dsp.beat | No `time_signature` source; meter wrong on some odd-meter tracks |
| BUG-001 | P2 | dsp.beat | Money 7/4 stays REACTIVE on live path |
| BUG-005 | P3 | session.ux | Spotify `preview_url` returns null for some tracks |


---

## Open

---

### BUG-067 — Ricercar FL.5 fails the WCAG overlay-contrast gate on main (2026-07-09)

**P3 · preset.fidelity / regression · OPEN (expected to resolve on the Ricercar-rework merge; verify then).** Surfaced by the QG.1 pre-flight full battery.

**Expected:** `PresetContrastCertificationTests` requires white overlay text to clear WCAG 4.5:1 contrast over any preset frame + overlay backdrop.
**Actual:** Ricercar fails deterministically on all three fixtures — contrast **3.52 < 4.5** (`PresetContrastCertificationTests.swift:59/78/97`). Reproduced in isolation, not environmental, not flaky.
**Root cause:** main's Ricercar is the FL.5 fluid-dye state (a **light** warm ground → low contrast under white text). It is superseded by the unmerged `claude/ricercar-rework` branch (FL.10 glowing particle flow-field on a **dark** ground, M7-passed 2026-07-08, "fucking brilliant" — see the ricercar-and-instrument-capture memory). Ricercar is `certified: false`, mid-increment.
**Impact:** the full `swift test` battery is red on main independent of QG.1 (QG.1 touches none of the contrast path). Does not block QG.1.
**Failure class:** pre-existing regression on a superseded preset state.
**Action:** no code change on main warranted — the rework branch replaces this shader. **When `claude/ricercar-rework` merges, re-run `PresetContrastCertificationTests` and confirm it goes green before closing.** If the FL.10 dark-ground shader still fails contrast, this becomes a real FL.10 defect to fix there.

---

### BUG-066 — MoodClassifier flux input ran 16× hot on the offline path; saturated on every track (2026-07-08)

**P2 · ml.mood / dsp.mir · ✅ RESOLVED 2026-07-08 (MOOD-FLUX.2, `1d61830`).** Matt signed off on the objective `--mood-ab` before/after evidence (no live M7 — an eyeball made no sense for a diffuse scoring change). Full record: [`docs/diagnostics/BUG-066-diagnosis.md`](../diagnostics/BUG-066-diagnosis.md).

**Expected:** the MoodClassifier z-scores its 10 inputs against the scaler fit on the **live** pipeline's features (`d586e57` retrained on live-annotated tracks); `spectralFlux` (mean 0.25, std 0.20) should land within a few sigma.
**Actual:** CENSUS.3 (n=993) measured the **offline** flux input mean at **8.06** — z ≈ **+38**; saturated on essentially every track. Band energies and centroid match the scaler within ~20 %.
**Root cause (corrected — NOT a train-vs-inference mismatch):** the model is correctly trained on live features (the live training CSV `~/phosphene_features_annotated.csv` flux mean 0.2516 = the scaler). The offline `SessionPreparer.analyzeMIR.computeFFTMagnitudes` **reimplemented the FFT magnitude formula** differently from the live `Audio/FFTProcessor`: `sqrt(power/fftSize)` = |FFT|/32 vs live `|FFT|×2/fftSize` = |FFT|/512 — a uniform **16×**. Same hop (1024). Flux is fed **raw** into the z-score ([MIRPipeline.swift:66](../../PhospheneEngine/Sources/DSP/MIRPipeline.swift)); bands are AGC-normalized and centroid/chroma are ratios → scale-invariant → they matched. Flux is the only exposed feature (the discriminator; pre/post ratio exactly 16.000, σ=0).
**Impact:** `TrackProfile.mood` (set by `analyzeMIR`) is 30 % of `DefaultPresetScorer` → offline preset selection ran on 9 effective features. The **live** mood path was always correct; no live regression.
**Failure class:** regression / pipeline-wiring (offline path drifted from the live FFT formula).
**Fix (MOOD-FLUX.2):** align the offline formula to live — `vDSP_zvabs` + `×2/fftSize` (in `SessionPreparer+Analysis.swift` + the `CorpusCensusRunner` mirror). **Validated:** flux z **+38 → +1.43**, uniform 16× correction, 103 mood/MIR/session-prep/spectral tests green incl. `MoodClassifierGolden` (classifier untouched — this is a feature-extraction fix); blast radius benign (mir_bpm 0/40 changed; key 6/40 empty→resolved, harmless; centroid ratio-invariant).
**Sign-off (2026-07-08):** the live M7 was retired as unfit for a diffuse scoring change; replaced by the objective `CorpusCensusRunner --mood-ab` before/after (80-track sample) — before, saturated flux railed arousal high for every track → non-discriminative "happy" (Beethoven adagios read euphoric); after, arousal spans [−0.87,+0.81], spread ~doubled, **32 % of tracks flip mood quadrant** in the correct direction (calm tracks read calm). Matt: "bug is resolved."

---

### BUG-065 — Live BeatGrid phase drifts off the audible beat over a track (mid-track drift convergence) (2026-06-29)

P3, `dsp.beat`. (Renumbered from BUG-064 on the GLAZE.8→main merge — BUG-064 was already assigned to the Lumen freeze; this beat-sync bug forked the number on `claude/nice-rubin-9c10c7`.)

**Expected:** the live beat phase stays within the ~60 ms perceptual window across a whole track, so frame-locked beat-driven motion (e.g. Glaze's GLAZE.7 downbeat push) reads tight start-to-finish.

**Actual:** the cached grid has the right BPM, but `LiveBeatDriftTracker` *bounds* the live drift without *tightening* it — drift grows ~11 ms (track start) → 50–70 ms (mid/late-track), with 28 % of frames exceeding ~60 ms. Evidence: session `2026-06-29T12-43-51Z` (Cherub Rock, 171.3 BPM 4/4 — drift-by-10s-window 11/37/49/54/69/66/55/48 ms; `lock_state=2` only 67 %-within-60 ms). NOT a functional break (phase is approximately right); it caps how *tight* beat-locked presets can feel (the live example: GLAZE.7 reads connected but loosens as the track plays).

**Suggested improvement (Matt 2026-06-29):** live re-lock / cached-BPM-error correction so drift holds < ~30 ms across the track. The cold-start *automated phase* premise was retired (CLAUDE.md §Cold-Start), but this is mid-track drift *convergence* — a different surface (the tracker should tighten, not just bound). Logged for a dedicated beat-sync session.

### AUDIT-2026-06-09 — Full-codebase audit backlog (P2/P3 findings not individually filed)

**Status:** Open — index entry. The 2026-06-09 six-agent full-codebase audit (~92k lines, all findings verified at file:line, cross-checked against this tracker and CLAUDE.md FAs) produced 6 P1s, 17 P2s, ~40 P3s. The P1s and three highest-impact P2s are filed individually below (BUG-030 … BUG-037). Everything else lives in **[`docs/diagnostics/CODE_AUDIT_2026-06-09.md`](../diagnostics/CODE_AUDIT_2026-06-09.md)** — treat that document as the evidence record when picking up any item. Remaining P2s in brief (full detail + fix shapes in the audit doc):

- **Reactive orchestrator can select a hard-excluded preset** at session start — `PresetScorer.rank()` never filters despite its doc-comment; reactive nil-current path takes `ranked.first` unconditionally (`PresetScorer.swift:67-80`, `ReactiveOrchestrator.swift:208-227`).
- **Zero-duration track → unscored `catalog.first` fallback** bypassing every exclusion gate, can install a diagnostic preset (D-074 violation) (`SessionPlanner+Segments.swift:109-129`).
- **Mood-override cooldown never reset** across repeat plays/sessions — override effectively permanently dead from a track's second play (`LiveAdapter.swift:180-385`).
- **Unbounded in-memory StemCache** (~7 MB/track, no eviction; disk sibling has a 500 MB LRU cap) (`StemCache.swift:76`).
- **OAuth correctness (re-entrant `login()` leak, refresh double-spend, P3 hardening)** — ✅ **RESOLVED 2026-06-14 (CLEAN.2.2, commit `13cec8b`, integrated `a6f1288`).** Matt's live check passed: Spotify playlist loaded with no problems on the integrated `main` build — the refresh path exercised end-to-end against real Spotify, no regression. The fresh-login `state` guard is unit-test-proven + standard OAuth on unchanged callback routing (accepted without a forced interactive login per Matt 2026-06-14, since a silent refresh does not hit the consent round-trip). `SpotifyOAuthTokenProvider`: a second `login()` while one was pending overwrote `pendingContinuation` (orphaning the first caller until the 5-min timeout) + armed a stray timeout against the wrong attempt → now coalesces concurrent logins onto one in-flight attempt (`pendingContinuations` array; `finishLogin()` cancels the timeout on every resume path); concurrent `acquire()` each fired their own silent refresh, double-spending the rotating refresh token → now dedups onto a single in-flight `refreshTask`; + P3s (OAuth `state` CSRF/replay guard, form-body percent-encoding of `+ & = /` that `.urlQueryAllowed` leaked, Keychain-save failures logged not swallowed, callback `scheme == phosphene` + host validation). `SpotifyOAuthTokenProviderTests` green (4 new regressions).
- ✅ **RESOLVED (CLEAN.2.1, 2026-06-14)** — Spotify client secret baked into the built Info.plist. Removed `SpotifyClientSecret` from `Info.plist` + `Phosphene.xcconfig` and deleted its only consumer, the D-068 client-credentials `DefaultSpotifyTokenProvider`. The production flow already used OAuth Authorization Code + PKCE (`SpotifyOAuthTokenProvider`), which needs no secret; no build-bundled secret remains. OAuth login E2E confirmed by Matt 2026-06-14 on the integrated `main` build (no regression). See `RELEASE_NOTES_DEV.md [dev-2026-06-14-d]`.
- ✅ **RESOLVED (CLEAN.2.3, 2026-06-14)** — honest-UI dead controls (audit T5), each Matt's product call. **2.3.1:** the "Use Apple Music instead" no-op `{ }` cross-link (+ its dismiss-only mirror) now drive a real `NavigationStack` switch via `ConnectorPickerViewModel.switchConnector(to:)` (wire). **2.3.2:** the `.localFile` "coming later" capture mode (lying + no-op) removed — enum case, picker row, false string, and the now-unreachable reconciler/coordinator branches (remove; supersedes the `.localFile` branch of D-052). **2.3.3:** the disabled "Swap preset" context-menu stub hidden behind `#if ENABLE_PRESET_SWAP` until U.5b (hide). Commits `7800b72` / `d40cfad` / `6e983c8`. `RELEASE_NOTES_DEV.md [dev-2026-06-14-f]`.
- ✅ **RESOLVED (CLEAN.4.4, 2026-06-17)** — three renderer over-allocation / cache-key items from audit T7 (the `2026-06-13` audit's restatement of these P3s). (1) **PSO cache key** (`ShaderLibrary` cached by `name` alone, ignoring `pixelFormat`/`supportICB`): **finding = LATENT, not a live bug** — every production caller uses a **unique** name compiled once at init, preset multi-pass PSOs bypass the cache (`PresetLoader` → `device.makeRenderPipelineState`), and `supportICB: true` is test-only, so nothing currently collides; keyed correctly anyway by `PipelineKey(name, pixelFormat.rawValue, supportICB)` so a future name-reuse can't return the wrong-format PSO. (2) **wasted particle-mode warp pass** + (3) **unconditional feedback textures**: both gated to surface-mode feedback presets via `RenderPipeline.activePresetSamplesFeedback` — non-feedback + particle-mode presets allocate zero ping-pong (freed on `setFeedbackParams(nil)`), and particle mode skips the warp. Output-preserving (PresetRegression goldens byte-identical). Gates: `ShaderLibraryTests` +2, `DrawableResizeRegressionTests` +3. `RELEASE_NOTES_DEV.md [dev-2026-06-17-215601]`. (T7's remaining items — sceneTexture aliasing, resize stale-size, ray-march /height NaN, DynamicTextOverlay race — stay open under CLEAN.4.3/4.5.)
- ✅ **RESOLVED (CLEAN.2.3.4, 2026-06-14)** — localization gate only scanned `PhospheneApp/Views/`. `check_user_strings.sh` ROOTS widened to `PhospheneApp/ViewModels` + `ContentView.swift`, pattern extended with a connection-state `.error("…")` arm (`logger.error` excluded); the bypassing copy (Spotify/AppleMusic error strings, ConnectorType tiles, ReadyViewModel duration/source, ContentView fallback, PreparationProgressView subtitle, PlanPreviewTransitionView labels) externalized to `Localizable.strings`. Gate header documents its honest scope limit (literal-prefix matcher — lowercase/interpolated fragments still rely on review). Commit `46d836b`.

P3 categories indexed in the audit doc: ~25 latent bugs (incl. OAuth refresh double-spend + form-encoding gaps [Resolved CLEAN.2.2, see above], PSO cache key, mv_warp buffer(5) omission, PostProcessChain texture aliasing, malformed-sidecar swallowing, Arachne listening-pose FA #57-gate, >2-channel LF corruption, ~94 Hz vs 60 fps chroma hysteresis), ~11 perf items (autocorrelation 2×/frame, drums FFT 2×/frame, mono STFT 2×/track, serial prep pipeline, wasted particle-mode warp pass, unconditional feedback textures), dead code, and 6 in-code doc-drift items.

---

### BUG-064 — Lumen Mosaic freezes during local-file playback (works on Spotify) (2026-06-28)

**P1** · dsp.beat / preset · **✅ RESOLVED 2026-06-29** — Matt live-confirmed on the correct build (sessions `…T02-29-56Z` "looks good" + `…T12-49-44Z` "much better"); the `LUMEN_DIAG` instrument has been removed. Split from BUG-063 after the triple-buffer revert fixed Lumen on Spotify but Matt observed it still frozen on local files (sessions `…T15-32-06Z`, `…T15-50-01Z`, `…T21-04-51Z` + a GPU frame capture).

#### Expected behavior
During local-file playback, Lumen Mosaic animates exactly as on Spotify — the Voronoi cells change colour on the beat and the four lights move with the music.

#### Actual behavior
The mosaic renders correctly but is **static** — cells do not recolour; only a faint per-beat pulse (the separately-driven lights) is visible.

#### Reproduction steps
Play a local audio file, switch to Lumen Mosaic, watch >10 s. Worst on a fast track — session `…T21-04-51Z` is "01 Cherub Rock.mp3" (Smashing Pumpkins, 171 BPM).

#### Root cause
Pinned by the `LUMEN_DIAG` buffer-binding probe (session `…T21-04-51Z`), which **disproved the initial "stale slot-8 GPU read" hypothesis**: `boundIsEngine=true` every frame and `boundBass` tracks `state.bassCounter` exactly — the GPU is bound to the engine's own live buffer and the bytes are fresh. The real cause is upstream in the engine: the cell-step **band counters stall** (`counters=[5 2 1]` frozen after ~12 s). They advance in `LumenPatternEngine.updateBandCounters` on a `beatPhase01` wrap, detected as `prev > 0.85 && now < 0.15`. But the analyzer publishes `beatPhase01` at **~10 Hz**, so on a fast track it advances in **~0.27 jumps** that skip both narrow windows (e.g. `0.795→0.109` has prev < 0.85; `0.934→0.203` has now > 0.15). Only the rare step landing in `prev∈(0.85,0.88)` registers → ~5 of ~34 beats counted, then none. The cells recolour on those counters → frozen; the lights (driven off stems, separately) keep pulsing. (The earlier "litTex 900×600 = low quality" note was a red herring — 900×600 is just the window backing size; render scale is irrelevant.)

#### Failure class
`algorithm` (dsp.beat) — the wrap detector assumed small per-frame phase steps; it is not robust to the analyzer's coarse publish cadence on fast tracks. Not a render/GPU/binding defect.

#### Fix
`updateBandCounters` now detects a wrap as a **half-cycle phase drop** (`prevBeatPhase01 − beatPhase01 > 0.5`, the new `beatWrapDropThreshold`), which catches every wrap regardless of step size and never trips on a forward advance or a small drift-correction. Regression: `test_bug064_largeStepWraps_stillIncrementCounter` drives the recorded 171-BPM trajectory (the old two-window detector counts **0** wraps; the new one counts **4**).

#### Verification criteria
Automated: ✅ `test_bug064_largeStepWraps_stillIncrementCounter` + all 32 Lumen suites + app build + lint 0. Manual (required): Matt confirms the cells recolour on the beat during **local-file** playback (and still on **Spotify** — same code path). Then the `LUMEN_DIAG` instrument is removed.

### BUG-063 — Lumen Mosaic freeze: the slot-8 triple-buffer "fix" was a regression; reverted to known-good (2026-06-26)

**P1** · renderer / render-state · **✅ RESOLVED 2026-06-29 — subsumed by BUG-064.** The triple-buffer regression was reverted (2026-06-27, below); the Lumen freeze was then root-caused + fixed under BUG-064 (cell-step wrap detector) and Matt live-confirmed ("looks good" / "much better"). The `LUMEN_DIAG` instrument this entry kept "for the confirm" is removed (`17ebfe5`); no separate confirm outstanding. Surfaced live by Matt 2026-06-26 after the BUG-062 fix made every preset appear. **Three diagnoses were attempted; the first fix was actively harmful:**
1. **Slot-8 write-during-read race** → fix `f5ad0e2` (triple-buffer the slot-8 buffer). Never reproduced as a race; **this fix is the regression** (see below).
2. **GPU ray-march collapse** (reading the constant ~0.88 ms `frame_gpu_ms`) → wrong: 0.88 ms is *normal* for Lumen's audio-static geometry.
3. **Frozen stem-warmup snapshot** (first ~10 s) → a *real* secondary observation, but NOT the dominant freeze; the warmup gate built for it never reached Matt's build.

**The regression (session `…T21-14-35Z`):** Matt reports Lumen "worked like a dream before" and is now frozen nearly the whole playback (moved twice, faint beat pulse, **no cell-colour change**) — "possibly the worst yet." The data: `beatPhase01` wraps every beat (grid locked 171 BPM), the CPU band counters and light intensities advance — **yet the GPU image is frozen.** The single slot-8 `MTLBuffer` (known-good) was UMA-coherent and delivered the latest state to the GPU every frame; `f5ad0e2`'s 3-slot ring + per-frame rebind does not, so the GPU reads stale slot-8 → cells/lights freeze while a slot-0 (`FeatureVector`) beat term still pulses. The "race" the triple-buffer fixed was never observed; it fixed a non-problem and created a real one.

**Action (2026-06-27):** reverted both BUG-063 fix attempts — `f5ad0e2` (triple-buffer) and the layered warmup gate — restoring `LumenPatternEngine` + its tests to the exact known-good `cb8cb0b` state (single `patternBuffer`, bound once at `applyPreset`, written each `tick()`). BUG-016 palette test preserved; `LUMEN_DIAG` instrument kept for the confirm. ✅ engine build + 31 Lumen suites + app build + lint 0. **Resolution (2026-06-29):** the revert restored known-good Lumen; the residual local-file freeze was root-caused + fixed under **BUG-064** (the cell-step wrap detector missed coarse-cadence beat phases) and Matt live-confirmed it ("looks good" / "much better"), with the frozen-stem-warmup follow-up closed under LM.5. The `LUMEN_DIAG` instrument is removed (`17ebfe5`). BUG-063 closed as subsumed by BUG-064 — no separate confirm outstanding.

#### Expected behavior
Lumen Mosaic renders and animates its lit Voronoi-cell field continuously from the moment it becomes active, like every other certified preset — including the first ~10 s before the live stem analyzer converges.

#### Actual behavior
For the first ~10 s it shows a static (but correct and colourful) mosaic — the four lights and the cell colours do not change — then "unfreezes" the instant the live stem analyzer converges. Switching away earlier (Matt's usual reaction) makes it look like a permanent freeze that "recovers on switch-away." No crash, no UI hang.

#### Reproduction steps
Select Lumen Mosaic within the first ~10 s of a track (e.g. by cycling presets to it) and dwell. Session `2026-06-27T18-37-39Z`: Lumen active from ~18:38:00; the engine intensities are frozen at `[0.25 0.43 0.51 0.36]` for f=30–180 and start tracking audio at f=210 as the live stems arrive.

#### Session artifacts
`stems.csv` (`…T18-37-39Z`): `drumsEnergyRel`/`bassEnergyRel`/`vocalsEnergyRel`/`otherEnergyRel` are byte-identical (`0.24872, 0.43455, 0.51175, 0.35835`) for the first **613 stem-frames (~10 s)**, then vary. `session.log` `LUMEN_DIAG`: the four light intensities equal those frozen stem values **exactly**, frozen f=30–180, then track audio from f=210. Matt's Xcode GPU capture: a fully-composited, correct Voronoi mosaic (1800×1200) at 553 µs — a working render of *static content*, not a broken/black/collapsed one.

#### Failure class
`pipeline-wiring` — the D-019 warmup gate trusts stem *magnitude* (`totalStemEnergy`) as a proxy for stem *liveness*; a loud-but-frozen cached snapshot passes the proxy and is treated as live.

#### Ruled out (with evidence)
- **Slot-8 buffer race** — still froze with the triple-buffer fix (`f5ad0e2`) active; the buffer *contents* (stems) were frozen, not the buffer binding.
- **GPU ray-march collapse** — the GPU capture shows a correct full mosaic; ~0.88 ms is normal for Lumen's audio-static geometry, and the lighting/post passes are non-zero.
- **Headless flash harness** — renders Lumen fine because it drives *varying* synthetic features and never the frozen warmup snapshot; the bug needs the real cached-stem warmup path.
- **Loop / audio / camera / governor / dolly** — frame counter advances, `features.csv` flows, camera/`cam_t`/aspect/FOV constant, `cameraDollySpeed` 0, governor step-mult ≤0.75 (all unrelated to a frozen stem input).

#### Verification criteria (met by the fix, pending live)
Automated: `test_bug063_notLiveStems_driveFVFallback_notFrozenSnapshot` (loud frozen snapshot + `stemsLive:false` + a varying FV → the drums light tracks the FV, Δ>0.3, instead of pinning at the frozen 0.5) and `test_bug063_liveStems_stillUseStemDirect` (the fix does not strand Lumen on the fallback after convergence). Manual (required): Matt dwells on Lumen Mosaic from track start for ≥10 s live with no freeze.

---

### BUG-062 — Nimbus (and Aurora Veil) freeze: direct-fragment presets with `"passes": []` are skipped by the BUG-061 empty-passes guard (regression) (2026-06-26)

**P1** · renderer / regression · **✅ RESOLVED 2026-06-26 — Matt live-confirmed (session `2026-06-26T21-07-18Z`: "all presets appear now"); `6848118` on origin/main.** Introduced by the BUG-061 fix (`00b0625`). Files to §Resolved at the next pruning pass.

#### Expected behavior
Advancing to Nimbus (or Aurora Veil) renders and animates the preset with the music, like every other preset.

#### Actual behavior
Selecting Nimbus leaves the *previous* preset's last frame frozen on screen; Nimbus never displays. It "unfreezes" only on switching to the next/previous preset. No crash, no error. Observed across several of Matt's recent sessions.

#### Reproduction steps
Deterministic: start a session, advance to Nimbus (or Aurora Veil) — the drawable stops updating until you switch away. Session `2026-06-26T20-28-03Z`: `preset → Nimbus` logged 4×, each bounced to Nebula ~2–4 s later.

#### Session artifacts
`session.log` shows the four `preset → Nimbus` transitions with **zero** Metal/pipeline/exception lines — a silent non-present, not a crash. Discriminator: of all sidecars, only `Nimbus.json` and `AuroraVeil.json` ship `"passes": []`; every preset that rendered fine has ≥1 pass.

#### Suspected failure class
`regression` (render-state).

#### Root cause
BUG-061 wrapped the previously-unconditional `renderFrame(...)` in `draw(in:)` with `if willRenderActiveFrame` (`!activePasses.isEmpty`) to skip the transient preset-apply swap window, on the stated premise "every applied preset has non-empty passes." Nimbus and Aurora Veil are direct-fragment presets (`fragment_function` + `"passes": []`); `applyPreset` republishes `setActivePasses(desc.passes)` = `setActivePasses([])`, so their `activePasses` is *permanently* empty → `willRenderActiveFrame` permanently false → `renderFrame`/`drawDirect` never runs → the drawable is never presented. The headless render harnesses call `renderFrame` directly (bypassing `draw(in:)`'s guard), so the regression escaped CI.

#### Fix (2026-06-26)
`PresetDescriptor` decode normalises an explicit empty `passes` array to `[.direct]` — identical to omitting the key (the existing `renderPassDefaultIsDirect` contract). This keeps `activePasses` non-empty for direct presets (restoring the guard's premise) while leaving BUG-061 fully intact (`applyPreset`'s mid-swap `setActivePasses([])` still yields empty → still skipped). Render output byte-identical (`[.direct]` resolves to the same `drawDirect` path; PresetRegression goldens for Nimbus + Aurora Veil non-drift).

#### Verification criteria
Automated: `renderPassExplicitEmptyArrayNormalisesToDirect` (`"passes": []` → `[.direct]`) + corpus guard `shippedPresets_neverDecodeToEmptyPasses` (no sidecar may decode to empty passes — the test that would have caught this); PresetRegression 4/4 (Nimbus + Aurora Veil hashes unchanged); app 388; lint 0. **Manual (required):** Matt's live confirm that Nimbus + Aurora Veil render and animate with no freeze — a render fix is code-complete, not resolved, until live M7.

---

### BUG-061 — Nacre crashes on load: a preset-apply race renders its `.rgba16Float` direct pipeline to the 8-bit drawable (the deterministic BUG-060 reproducer) (2026-06-25)

**Severity:** P1 (hard crash; narrow trigger — the uncertified Nacre preset reachable via the Cmd+] dev cycle / "show uncertified presets", AND a Debug build with Metal validation on).
**Domain tag:** renderer / render-state (concurrency: a preset-apply race surfacing as a render-pipeline attachment-format mismatch).
**Status:** ✅ RESOLVED 2026-06-25 (NACRE.2b). Diagnosed from the code (the `applyPreset` publish ordering + the off-main display-link draw + the per-field locks); the live crash has no `.ips`/stack and is validation-gated, so it is not headless-reproducible.
**Introduced:** NACRE.2b for the deterministic Nacre crash (the `.rgba16Float` feedback opt-in made the latent race fatal); the underlying race is **pre-existing** (= BUG-060, the intermittent Gossamer render-death).
**Resolved:** 2026-06-25, NACRE.2b fix commit (this increment).

**Expected:** switching to any preset (incl. Nacre) renders a frame; never crashes.

**Actual (session `2026-06-25T20-51-58Z`):** Matt cycled presets with Cmd+] (Arachne → … → Murmuration, all fine) and the app crashed exactly at `preset → Nacre`. `applyPreset` (main thread) clears `activePasses` to `[]` (`VisualizerEngine+Presets:117`), publishes the new preset's direct pipeline (`:150`, `nacre_fragment`, `.rgba16Float`), and republishes `activePasses` only at the very end (`:721`). `draw(in:)` runs concurrently on MTKView's CVDisplayLink thread (hence the `pipelineLock`/`passesLock`/`mvWarpLock`). A frame in the `117→721` window reads **empty passes + the new `.rgba16Float` direct pipeline** → `renderFrame`'s pass loop matches nothing → falls to `drawDirect`, which renders that pipeline **to the 8-bit drawable** → attachment-format mismatch → GPU abort (Metal-validation-gated; the Debug build has validation on). 8-bit presets (DB/FM/Gossamer/Murmuration) render their direct fragment harmlessly in that window — a benign stray frame (the intermittent **BUG-060**). Only Nacre's `.rgba16Float` direct pipeline → 8-bit drawable hard-crashes, deterministically.

**★ Diagnosis-process note:** my FIRST diagnosis blamed the reduced-motion path (`drawMVWarpReducedMotion` has the same direct→drawable mismatch). That was an **unverified assumption** — I inferred "reduce motion is on" from the crash path without checking. Matt confirmed Reduce Motion was OFF (Accessibility → Motion), falsifying it. The reduced-motion mismatch is a real *latent* bug (fixed too, secondary) but was NOT this session's trigger. Lesson: do not assert a root cause from an inferred precondition without confirming the precondition.

**Reproduction steps:** Debug build (Metal validation on); Cmd+] to Nacre. Crashes on the first Nacre frame (deterministic). The benign 8-bit form (BUG-060) is intermittent on any preset switch under load.

**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-25T20-51-58Z/` (`session.log` ends at `preset → Nacre`; no `.ips`). `cmd.error` is **nil** for the 16-float→8-bit mismatch without validation (`test_directPipelineToDrawableFormat` — removed; documented here) → the crash needs the Debug validation layer.

**Suspected failure class:** `concurrency` (preset-apply race) surfacing as `render-state` (attachment-format mismatch).

**Fix:** `RenderPipeline.draw(in:)` skips the frame while `activePasses` is empty (`willRenderActiveFrame`) — empty passes only ever exists transiently mid-swap, so skipping is correct (MTKView holds the last frame for the ~ms of the swap). Fixes Nacre's crash **and** the BUG-060 class for every preset. Secondary: `renderNacreReducedMotion` fixes the same mismatch on the (off-this-session) reduced-motion path.

**Verification criteria:**
- [x] Regression: `NacreMVWarpAccumulationTest.test_emptyActivePasses_skipsRenderFrame` (the skip-condition the guard keys on) + `test_reducedMotion_…`; PresetRegression byte-identical; Nacre suite green under `MTL_DEBUG_LAYER=1`.
- [ ] **Manual (Matt):** Cmd+] to Nacre renders without crashing (and watch for BUG-060 non-recurrence on other preset switches).

**Manual validation required:** Yes — the live crash is validation + drawable gated (not headless-reproducible); Matt's live re-test is the confirmation.

---

### BUG-059 — Concurrent `LocalFilePlaybackProvider` start/stop ABBA-deadlocks: `scheduleFile` re-scheduled inline from the completion handler vs `player.stop()` (BUG-021 family) (2026-06-17)

**Severity:** P1 (a hang — the provider's lifecycle thread and AVFoundation's completion-handler queue both wedge permanently; in production this freezes audio/visuals with no recovery).
**Domain tag:** local-file / concurrency (`LocalFilePlaybackProvider.scheduleFileLoop` / `teardownAVFoundation` / `handleConfigurationChange`)
**Status:** **✅ RESOLVED 2026-06-18** — fix `a285a22` (integrated to `main`, origin/main); Matt's live validation 2026-06-18 (session `2026-06-18T13-46-10Z`): several Duet 3 ↔ Mac-mini output-device swaps mid local-file playback, **no hang** every time, Next/Prev clean. Root cause confirmed from a live `sample` of the hung process (stack below). Surfaced 2026-06-17 while de-flaking `concurrentDoubleStart_serializesWithoutDeadlock` (the "load flake" was this deadlock firing intermittently, not a wall-clock budget slip).
**Introduced:** The LF.1 spike — `scheduleFileLoop` re-schedules `scheduleFile()` synchronously from inside the AVAudioPlayerNode completion handler; `handleConfigurationChange` (LF.1, `:414`) added the off-MainActor `stop()+start()` restart that supplies the concurrency. The BUG-021 fix (2026-05-28) moved teardown outside the *provider's* `NSLock`, but this cycle is on AVFoundation's *internal* locks, which that fix does not cover.
**Resolved:** 2026-06-18 — `a285a22` (fix) + Matt's manual no-hang validation (session `2026-06-18T13-46-10Z`). Integrated to `main` (origin/main).

### Expected behavior
Two overlapping start/stop sequences on one provider (e.g. an `AVAudioEngineConfigurationChange` restart racing a track advance) serialize and complete; the provider ends in a clean stopped or playing state. No thread blocks indefinitely.

### Actual behavior
The pair deadlocks permanently. Observed on this machine 2026-06-17: the REVIEW.2 regression test `concurrentDoubleStart_serializesWithoutDeadlock` hung **6 m 15 s** (killed) with its watchdog removed, and **fails at round 0** (watchdog fires at 8.03 s) with the watchdog intact. A **single** sequential `engine.start()` is healthy (`routerChurn_startStopLocalFilePlayback_neverHangs` passes, 4.36 s) — only the **concurrent** path wedges. It is a race, so intermittent: it passed in isolation on other days (~3.6 s) and "failed once after ~9.5 s under the full parallel suite" (2026-06-17) — both are this same deadlock, triggering or not depending on timing.

The circular wait (from `sample` of the hung `swiftpm-testing-helper`, 1508/1508 samples each side — i.e. fully wedged, not slow):
- **Thread A** (`provider.stop()`): `LocalFilePlaybackProvider.stop()` (`:186`) → `teardownAVFoundation` (`:320`) → `-[AVAudioPlayerNode stop]` → `AVAudioPlayerNodeImpl::StopImpl()` → `_dispatch_sync_f_slow` → `__DISPATCH_WAIT_FOR_QUEUE__` → blocked waiting to own the **AVAudioPlayerNode CompletionHandlerQueue** (and `Stop()` holds the engine lock).
- **Thread B** (`AVAudioPlayerNodeImpl.CompletionHandlerQueue`): running our `closure #1 in scheduleFileLoop` (`LocalFilePlaybackProvider.swift:355`) → `-[AVAudioPlayerNode scheduleFile:atTime:completionHandler:]` → `AVAudioNodeImplBase::GetAttachAndEngineLock()` → `std::recursive_mutex::lock()` → `__psynch_mutexwait` — blocked on the **AVAudioEngine attach/engine lock**.

A holds the engine lock + wants the completion queue; B holds the completion queue + wants the engine lock. The provider's own `NSLock` is **not** in the cycle.

### Reproduction steps
1. `swift test --package-path PhospheneEngine --filter concurrentDoubleStart_serializesWithoutDeadlock` (real `LocalFilePlaybackProvider` + `love_rehab.m4a` excerpt; race, so re-run a few times — currently wedges on the first round on the dev Mac mini).
2. To capture the stack: run it, then `pgrep -f "swiftpm-testing-helper.*concurrentDoubleStart" | while read p; do sample "$p" 2 -mayDie > /tmp/s_$p.txt; done`, and read the `CompletionHandlerQueue` + `provider.stop()` threads.
3. Production shape: during local-file playback, fire an `AVAudioEngineConfigurationChange` (switch the default output device / sample rate) — `handleConfigurationChange` (`:414`) runs `stop()+start()` on a global queue, off the MainActor — at the same time as a track advance (`VisualizerEngine+LocalFilePlayback.swift:335`, MainActor `stop()+start()`).

**Minimum reproducer:** the existing `concurrentDoubleStart_serializesWithoutDeadlock` test (real audio, no synthetic — per FA #27).

### Session artifacts
n/a — not a session defect; the artifact is the process stack `sample` above (captured 2026-06-17, not retained; reproducible per step 2). No `features.csv`/`session.log` involvement.

### Suspected failure class
`concurrency`.

**Evidence for this class:** a two-thread circular lock-acquire (AVFoundation completion-handler dispatch queue ⇄ AVAudioEngine attach/engine `recursive_mutex`) visible in the process sample; the single-threaded path does not wedge.

### Verification criteria
Written before the fix (per template). When resolved, all of:
- [x] `concurrentDoubleStart_serializesWithoutDeadlock` passes reliably — **11/11 green (6× isolated + 5× in-suite), ~3.5 s each**, on the same dev Mac mini that wedged on round 0 before the fix. (A fresh `sample` is no longer meaningful — the process no longer hangs; the 6-min-hang → 3.5 s-pass swing on a reliably-wedging machine is the proof the cycle is gone.)
- [x] No regression in the REVIEW.2 siblings: full `SessionLifecycleChurnTests` suite **5/5 green (all 6 tests), ~17 s each** — `routerChurn_…`, `completionCallbackVsStop_…`, `onFileEnded_queueAdvanceChurn_…`, `transportChurn_…`, `deinitWhilePlaying_…` included.
- [x] Full engine `swift test` with no recurrence — closeout 2026-06-17 (`a285a22`): **1512 tests, 0 failures** under full parallel load (the exact condition the original intermittent failure needed); app 388 ✓, swiftlint 0/433, doc gates 10/10 — ALL GREEN.
- [x] **Manual (Matt, 2026-06-18, session `2026-06-18T13-46-10Z`):** several output-device swaps mid local-file playback — **no hang** (every `provider.teardown` reached EXIT; every `player.stop BEGIN → COMPLETE`); **Next/Prev** advance cleanly (`advanceLocalFileQueue EXIT ok=true`); `features.csv` live throughout (60 fps, 200/200 distinct values in the last 200 rows — no freeze). **NB** the swaps were sequential (seconds apart), so the session did **not** reproduce the exact *concurrent* race — the automated test (11/11, reliably wedged pre-fix) is the proof for the race; this session confirms the device-swap path is healthy + un-regressed. The track restarting from the top on a swap is the separate, expected **BUG-056** (device-change restart has no resume-from-position), **not** a BUG-059 regression — `handleConfigurationChange` restarts the engine from position 0 by design.

**Manual validation required:** Yes — session-lifecycle + playback-loop behavior change. Needs a live local-file session; the worktree change must reach the `main` build first (or Matt builds the worktree) before the live test.

### Fix (step 2 — 2026-06-17)
`scheduleFileLoop`'s completion handler no longer re-schedules `scheduleFile()` (or fires `onFileEnded`) **inline** on the AVAudioPlayerNode completion-handler queue. It now hops that work onto a provider-owned serial `rescheduleQueue` and re-checks the `(playerNode, audioFile)` identity under `lock` there before touching the player. The completion handler returns immediately, freeing the completion queue — so a concurrent `stop()` (whose `player.stop()` holds the engine lock and `dispatch_sync`s that queue) is no longer blocked by an inline `scheduleFile()` waiting on the engine lock. The two sides now serialize on the engine lock (mutual exclusion) instead of forming a cycle. `onFileEnded`'s production consumer already re-dispatches to the MainActor (`VisualizerEngine+LocalFilePlayback.swift:161`), so its callback thread change is immaterial; LF.1 single-file looping restarts at a file boundary where a sub-millisecond hop is inaudible. Test-only files untouched; the existing REVIEW.2 watchdog test is the regression net (it reliably reproduced the deadlock pre-fix).

### Fix scope
Contained to `LocalFilePlaybackProvider.scheduleFileLoop`: hop the re-schedule (and the `onFileEnded` advance) **off** the AVAudioPlayerNode completion-handler queue onto a provider-owned serial queue, re-checking `stillActive` under the lock before touching the player. That frees the completion queue immediately, so a concurrent `player.stop()` can no longer find it occupied-and-blocked-on-the-engine-lock. Changes the callback thread and the loop re-schedule timing → not a < 5-line trivial collapse; proper fix increment + regression + manual validation.

### Related
- **BUG-021** — the parent ABBA class (provider `NSLock` vs AVFoundation render/completion thread). This is the same family on AVFoundation's *internal* locks, which the BUG-021 fix did not reach.
- **BUG-056** (local-file restarts from the top on a device change) — same `handleConfigurationChange` restart path; a fix here should be coordinated with any resume-from-position work there.
- **G1 / CLEAN.1.5 / BUG-058** — the device-swap scenario is one production trigger (config change during local-file playback).
- Test: `SessionLifecycleChurnTests.concurrentDoubleStart_serializesWithoutDeadlock` (REVIEW.2). Failed Approach #27 (real audio, not synthetic) — why the test drives the real provider.

---

### BUG-060 — One-off app hang: the render loop died on a `preset → Gossamer` switch; force-quit required; not reproduced (2026-06-18)

**Severity:** P3 (a full app hang requiring force-quit is P1-*impact*, but it was seen once and did not reproduce — Gossamer ran 3× clean the next session; filed as **monitored**, like BUG-058, pending a recurrence with a captured stack).
**Domain tag:** renderer / app.hang (suspected preset-apply or first-frame GPU hang on Gossamer).
**Status:** **LIKELY RESOLVED by NACRE.2b's BUG-061 fix (2026-06-25) — pending non-recurrence.** BUG-061 confirmed the suspected **preset-apply race**: `applyPreset` clears `activePasses` to `[]` then republishes them at its end, while `draw(in:)` runs concurrently on the display-link thread; a frame in that window falls to `drawDirect` with the new preset's direct pipeline. Nacre's `.rgba16Float` pipeline made it a deterministic crash and exposed the mechanism; for an 8-bit preset like Gossamer it's the benign/intermittent stray frame seen here. The `willRenderActiveFrame` guard (skip frames while `activePasses` is empty) removes the stray `drawDirect` for ALL presets. Keep monitored until a few clean Gossamer-switch sessions confirm non-recurrence (the original was a *hang*, not a crash, so a small chance it's a distinct GPU-contention issue remains).
**Introduced:** Unknown (the apply-race predates NACRE.2b).
**Resolved:** Likely 2026-06-25 (NACRE.2b empty-passes guard); confirm by non-recurrence.

**Expected:** switching presets (incl. Gossamer) never hangs the app.

**Actual (session `2026-06-17T22-10-50Z`):** the render loop was healthy — 60 fps, `frame_gpu_ms` 0.13–1.5 ms, no `deltaTime` gap — through the **last recorded frame (9459) at `22:14:01Z`**, which is **one second after `session.log`'s last event, `preset → Gossamer` at `22:14:00Z`**. `features.csv` then stops while the stem-separation / orchestrator threads keep logging for ~30 s more → a **render-path hang** (main or GPU), not an analysis stall (cf. BUG-043, a freeze-then-lurch) and not a tap freeze (cf. BUG-058). Video was OFF (BUG-050), so the recorder's video path is excluded. Matt force-quit from Xcode **without hitting Pause**, so no thread stacks were captured.

**Non-reproduction (session `2026-06-18T13-57-23Z`):** Gossamer was applied **3×** (13:58:35, 14:00:13, 14:00:36) and rendered clean; the session ended with a normal `SessionRecorder finished` shutdown. So the hang is rare/intermittent, not a deterministic Gossamer defect.

**Reproduction steps:** unknown trigger. Lead: a `preset → Gossamer` switch under live load (continuous stem separation running) — possibly transient GPU contention between the stem-separation MPSGraph and Gossamer's first-frame render, or a preset-apply race.

**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-17T22-10-50Z/` (features.csv ends at frame 9459 / `22:14:01Z`; session.log last line `preset → Gossamer`); clean counter-example `2026-06-18T13-57-23Z`.

**Suspected failure class:** `concurrency` or `render-state` (a hang, not a crash).

**Verification criteria (when diagnosable):**
- [ ] **On the next recurrence: hit Pause (⏸) in Xcode BEFORE force-quitting**, and capture the Debug-Navigator thread stacks (main thread + any thread in Metal/MPSGraph) — the one artifact that locates a hang. Add a `Debug → Capture GPU Frame` if a GPU hang is suspected.
- [ ] Root cause identified from a captured stack; regression guard added.

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

### BUG-057 — Cold tap install delivers persistent silence on streaming audio; only a manual output-device switch (tap reinstall) recovers it (2026-06-17)

**Severity:** P1 (the core streaming-visualization flow does not work on a cold start — visuals stay motionless with live Spotify audio — and the only recovery is a manual output-device toggle no user would discover).
**Domain tag:** audio.capture
**Status:** **Resolved 2026-06-17 (Matt) — Phosphene-side complete (D-165).** The silent-tap family is closed: the detector card (`a0a9ded`), the reinstall fix (don't rebuild a working tap on a pause — `6bac999`, validated 3/3 clean pause/resume), and the card pause-suppression (`cf44b1b`, validated) all shipped + validated + pushed. The only residual is the *environmental* wedged-`coreaudiod` (a `killall coreaudiod` / reboot workaround — NOT a Phosphene code bug), which the detector now surfaces with actionable guidance instead of a silent flatline. The original diagnosis below (environmental daemon wedge) stands; the actionable Phosphene-side work is done. (Earlier interim status: "Diagnosed — root cause environmental"; the detector + reinstall-fix arc landed 2026-06-17.)
**Introduced:** Not a Phosphene regression. macOS audio-daemon state degraded over a 15-day `coreaudiod` uptime on a box with heavy virtual-device churn (BlackHole, Teams audio device, Apogee Duet, repeated aggregate-device creation). Earlier healthy sessions (`project_streaming_tap_signal_health`: −6 dBFS) predate the wedge.
**Resolved:** 2026-06-17 (Matt's call to close) — detector + reinstall-fix + card pause-suppression all validated (D-165; commits `a0a9ded` / `6bac999` / `cf44b1b`, on `origin`). The environmental wedged-`coreaudiod` residual is a `killall coreaudiod` / reboot workaround (not a code bug), now surfaced by the card. Full evidence in the §Reinstall fix (steps 1–4) + §Card pause-suppression sections below.

---

### Expected behavior

On a cold start — connect Spotify → load playlist → Phosphene signals ready → user presses play in Spotify — the system-audio tap captures the live output and visuals animate within a few seconds, with no manual intervention. A silent tap should be auto-recovered by the existing `.silent → reinstall` state machine.

### Actual behavior

The tap installs (`AudioHardwareCreateProcessTap` returns `noErr`, `raw tap capture started sr=… Hz` logs) but delivers **persistent silence** — `features.csv` mid/treble = exactly 0.0, `signal quality → red: no signal`, `audio signal → silent`. The existing `.silent → scheduleNextReinstall` recovery does **not** rescue it (silent for the full session in 4 of 5 sessions). The ONLY thing that recovers it is a **manual output-device switch**: in session `2026-06-17T01-51-11Z` the tap was silent for ~75 s, then at the instant the default output device changed (rate flipped 48 k → 44.1 k → `performReinstall`) it captured **~5.6 s of real music** (mid up to 0.527, treble 0.106, `signal quality → green: peak -0 dBFS — OK`). So the audio is tappable; the *cold-install* tap is the one that comes up dead.

Ruled out: output routing (silent on both the Apogee Duet 3 and built-in Mac-mini speakers); signing (proper `Apple Development` cert, Team `2LBTN9PB4Z`, not ad-hoc); Screen Recording permission (granted, toggled off/on + relaunched; `NSScreenCaptureUsageDescription` present); audio actually playing (audible through the Duet 3); the engine/render path (local-file playback animates normally — file-direct, bypasses the tap).

### Reproduction steps

1. Connect Spotify, load a playlist, let Phosphene reach ready.
2. Press play in Spotify (audible through the system output).
3. Observe: visuals motionless; `session.log` shows `raw tap capture started` then `audio signal → silent`; `features.csv` mid/treble = 0.
4. With Phosphene running + audio playing, switch the system output device (System Settings → Sound → Output → another device, then back).
5. Observe: at the switch, the tap reinstalls and motion appears (briefly green / real signal).

**Minimum reproducer:** any DRM streaming source (Spotify) on a cold start. The device-switch recovery is the discriminator.

---

### Session artifacts

**Session directories:** `~/Documents/phosphene_sessions/2026-06-17T01-37-54Z/`, `…01-48-33Z/`, `…01-51-11Z/` (+ `2026-06-16T22-10-16Z`, `22-39-46Z`).

- Silent cold-install sessions: `01-48-33Z` mean mid/treble = 0.0000 over 1658 rows; `01-37-54Z` mid/treble = 0.0000 over 1929 rows; same `signal quality → red: no signal` log line.
- Recovery session `01-51-11Z`: silent rows 0–75.7 s, then signal t=75.8 → 81.4 s (341/2548 rows mid > 0.05, max mid 0.527), `signal quality → green: peak -0 dBFS, treble 2.06% — OK`. (`max bass=29.0` at the switch instant is a reinstall-pop transient — secondary, worth a glance.)

```log
[01:49:06] raw tap capture started sr=48000 Hz ch=2
[01:49:07] signal quality → red: no signal — check output device / app is playing
[01:49:09] audio signal → silent
  --- (01-51-11Z, after a device switch) ---
[01:52:14] audio signal → active
[01:52:26] MIR analysis rate → 44100 Hz (tap 44100 Hz)
[01:52:29] signal quality → green: peak -0 dBFS, treble 2.06% — OK
```

- Code seams (the cold-vs-reinstall divergence):
  - `PhospheneEngine/Sources/Audio/SystemAudioCapture.swift:116` `startCapture` (cold install) and `:290` `performReinstall` run the **identical** create sequence (`createProcessTap → readTapFormat → createAggregateDevice → createIOProc → startDevice`); the only difference is `performReinstall` tears down first (`teardownTapResources` `:311`) and runs later. So the divergence is timing/state, not code.
  - `PhospheneEngine/Sources/Audio/AudioInputRouter+SignalState.swift:13` — the `.silent → scheduleNextReinstall` recovery machine ("the tap stays alive but delivers permanent silence … recovery is destroy and recreate") — present but did not recover the cold install.
  - `PhospheneEngine/Sources/Audio/SilenceDetector.swift:4` — "Core Audio process taps succeed even when playing **DRM-protected content**, but macOS silently zeros the audio buffer … the tap appears healthy while delivering silence." Spotify is DRM; this is the candidate mechanism, but the device-switch capture of real Spotify audio argues against *pure* persistent DRM-zeroing.
  - `PhospheneEngine/Sources/Audio/DefaultOutputDeviceMonitor.swift` — the CLEAN.1.5/G1 monitor whose device-change callback drives the recovering `performReinstall`.

---

### Suspected failure class

**RESOLVED to `resource-management` (external OS daemon state) — see §Diagnosis.** A wedged `coreaudiod` fed every process tap silence; none of the four pre-diagnosis candidates below held (the diagnosis falsified all of them — see §Diagnosis). Retained for the record:

> ~~`pipeline-wiring`~~ — Candidate root causes considered during diagnosis: (a) Screen Recording grant not yet effective on the first tap; (b) DRM-zeroing the cold tap escapes; (c) cold tap binds before audio flows; (d) auto-reinstall delays/attempt-cap or same-device reinstall insufficient. **All four falsified:** a separate granted binary (`audio-tap-test`) was equally silent (kills a + d), on non-DRM audio (kills b), on a freshly-bound tap on two devices (kills c) — until `coreaudiod` was restarted.

---

### Verification criteria

- [ ] Instrumentation (step 1): a session captures, for both cold install and any reinstall, the tap RMS over the first N seconds, whether/when `.silent → reinstall` fires, the device id + rate, and the Screen-Recording preflight state at install — enough to separate the four candidate causes.
- [ ] Manual (the real gate): a **cold start** with live Spotify animates within ~5 s with **no manual device toggle** — `features.csv` mid/treble > 0, `signal quality → green` — across ≥ 2 sessions.
- [ ] No regression: local-file playback still animates; the CLEAN.1.5/G1 device-swap recovery still works (switch output mid-session → stays live).

**Manual validation required:** Yes — the tap path is not SPM-testable (real Core Audio + a DRM streaming source). Listen/look: cold-start Spotify → motion without touching the output device.

---

### Instrumentation (step 1 — landed 2026-06-17, instrument → STOP)

Added to `session.log` (grep `TAP:`) so the four candidates above are separable from ONE real cold-start Spotify session:

- **Per (re)install:** `install via startCapture` / `reinstall via device-change` + `gen=N defaultOutputDevice=<id> rate=<Hz> screenRecordingPreflight=<bool>` (`SystemAudioCapture.armInstallProbeAndLog`). Discriminates same-device vs different-device reinstall (candidate d) and pins the preflight at install (candidate a).
- **First-10 s RMS probe:** `tap RMS gen=N t=+Xs rms=… peak=…` at ~1 Hz from the IO proc (`SystemAudioCapture.probeInstallRMS`) — shows whether THIS tap delivered signal or stayed zero (candidates b, c). Correlate with the existing `audio signal → …` transitions + `signal quality → …` lines.
- **Reinstall scheduler timeline:** the `.silent → reinstall` lines (scheduled/attempt#/skipped/succeeded/failed/exhausted), previously os_log-only (`AudioInputRouter+SignalState`, mirrored via `onAudioCaptureDiagnostic`).

Wired `SystemAudioCapture.onCaptureDiagnostic` → `AudioInputRouter.onAudioCaptureDiagnostic` → `SessionRecorder.log` in `VisualizerEngine+Audio.setupAudioRouting`. New protocol member `AudioCapturing.onCaptureDiagnostic`. No fix code; no behaviour change (FA #73 — reuses the existing reinstall machine + `DefaultOutputDeviceMonitor`). Regression: 2 routing-lock tests in `AudioInputRouterSignalStateTests`. **Diagnose next (step 2):** Matt runs an instrumented cold-start session + a device switch; identify the holding candidate(s) and record the root cause here. Build from the PRIMARY checkout with Screen Recording granted (`project_canonical_app_screenrecording`) — a fresh worktree build re-churns the grant and reproduces *unrelated* silence (don't conflate it with this bug). Commit: see `RELEASE_NOTES_DEV.md [dev-2026-06-17-041554]`.

### Diagnosis (step 2 — 2026-06-17, CONFIRMED: wedged `coreaudiod`)

The instrumented cold-start session (`~/Documents/phosphene_sessions/2026-06-17T13-29-13Z/`) + a standalone cross-check pinned the root cause to **macOS audio-daemon state, not Phosphene**:

1. **Instrumentation (PhospheneApp).** All 4 installs — cold `startCapture` gen=1 + the three `.silent`-recovery reinstalls gen=2/3/4 — logged `defaultOutputDevice=128 rate=48000 screenRecordingPreflight=true`, and the first-10 s RMS probe read `rms=0.000000 peak=0.000000` on **every** one. The `.silent → reinstall` machine fired correctly (attempt #1/#2/#3 → backoff exhausted). `raw_tap.wav` = −inf; `features.csv` 0/7721 rows nonzero. So: the recovery code works; every tap was simply fed silence. No `reinstall via device-change` fired (the manual "source change" was not a macOS *default-output* change — device stayed 128).
2. **Decisive cross-check.** `tools/audio-tap-test` (a **separate binary**, its own `audio_tap` Screen-Recording grant, identical `CATapDescription(stereoGlobalTapButExcludeProcesses:[])`) **also** captured pure-zero — on Spotify (DRM), on `say`/`afplay` (non-DRM, `afplay` confirmed running), on **both** Duet 3 *and* built-in Mac-mini Speakers. ⇒ not app-specific (rules out stale-grant/BUG-055), not DRM, not the device.
3. **The proof.** `coreaudiod` had been up **15 days 20 h** (`ps -o etime`), no orphaned aggregate devices. **`sudo killall coreaudiod` → the same tool immediately captured real audio** (RMS to 0.31 / −10 dB, 47 Hz-dominant music spectrum). Single-variable flip.

The `01-51-11Z` "device-switch recovery" (≈5.6 s then degraded) was a coincidental partial nudge to the same wedged daemon, not a Phosphene fix. **Failure class corrected: `resource-management` (external OS daemon state) — not `pipeline-wiring`.**

### Fix scope

**No Phosphene code fix is needed for the silence itself** — the tap path is correct (it captures the instant `coreaudiod` is healthy). **Workaround: `sudo killall coreaudiod`** (daemon auto-relaunches, ~1 s audio blip) or reboot. The one worthwhile Phosphene-side increment is the **granted-but-silent detector** (shared with BUG-055): when the tap is installed + `screenRecordingPreflight=true` but RMS ≈ 0 for N s while a session is "playing," surface an actionable state ("audio isn't reaching the tap — restart audio with `sudo killall coreaudiod`, check Screen Recording, check output device") instead of a silent "ready" flatline. The step-1 instrumentation's `TAP:` RMS probe is exactly the signal that detector consumes. **Awaiting Matt's go to scope it as the fix increment.** Kickoff: `docs/prompts/BUG-057_TAP_COLD_INSTALL_SILENCE_KICKOFF.md`.

### Fix increment — silent-tap detector landed 2026-06-17 (pending Matt's manual UX validation)

The *detector half* is implemented (this surfaces the silence; it does NOT fix the environmental cause — `sudo killall coreaudiod` remains the cure). `PlaybackErrorBridge` (`PhospheneApp/Services/PlaybackErrorBridge.swift`) now runs a ~1 Hz freshness poll while playing and raises a prominent **`AudioStallOverlayView`** card when *no fresh audio* reaches the visualizer for ~10 s. "Fresh" = the tap frame count is still advancing AND the signal isn't confirmed `.silent`, so it catches **both** failure modes the family presents: **Mode A** (RMS≈0 → `.silent`; wedged `coreaudiod` [this bug] / stale grant [BUG-055]) via `audioSignalState`, and **Mode B** (frozen IO-proc; BUG-058) via `InputLevelMonitor.frameCount` ceasing to advance — Mode B keeps RMS nonzero so `.silent` never fires and an RMS-only detector would miss it. The card carries the fix ladder (`sudo killall coreaudiod`; re-grant Screen & System Audio Recording + relaunch; check the output device) and auto-clears when audio returns; it supersedes the existing 15 s silence toast while up. Gated on `.playing && !paused` (with a freshness baseline reset on gate entry) so it never false-fires pre-play, in `.ready`, on a deliberate local-file pause, or during quiet passages. 8 new gate tests (`PlaybackStallDetectorTests` in `PlaybackErrorBridgeTests`) lock the four false-fire guards + both modes + auto-clear; all green. **Reuses `PlaybackErrorBridge` per FA #73 — no parallel detector, zero engine changes.** Commit: see `RELEASE_NOTES_DEV.md` (`a0a9ded`). **Surface VALIDATED 2026-06-17** — Matt's screenshot confirms the card renders correctly (headline, body, the 3-step fix ladder, the `sudo killall coreaudiod` pill, the auto-clear hint) with the right copy. The gate (no false-fire) and auto-clear are unit-proven (`PlaybackStallDetectorTests`, `test_recovery_clearsCard`); the **live** pause→card→resume→clear cycle can't be demonstrated until the BUG-057 reinstall hang is fixed (today the tap never recovers — see §Validation note + `docs/prompts/BUG-057_TAP_REINSTALL_SILENCE_KICKOFF.md`). **Detector half DONE.**

**Card APPROVED 2026-06-17 (Matt)** as the safety-net surface — copy/paths correct. **Product direction (Matt):** the end-state must NOT make the user touch Terminal or System Settings; the manual fix-ladder is a developer/last-resort fallback, not the fix. The user-friendly answer is the app **self-healing** — the BUG-057 reinstall auto-recovery (scoped; makes the common reinstall-hang recover with zero user action → no card at all) + stable signing (CLEAN.2.5b; removes the re-grant step for end users). No quick fix clears that bar (the Terminal step needs root; deep-linking the Settings panes only speeds the same manual work), so the card ships as-is and the leverage is the self-healing fix. See `feedback_self_healing_over_manual_remediation` (memory).

### Validation note 2026-06-17 — detector verified correct against a real session; BUG-057 reproduced live via a streaming pause

Matt's session `2026-06-17T16-59-43Z` (validating via a Spotify pause) **confirmed the detector is correct** and surfaced a more reproducible BUG-057 trigger than the 15-day `coreaudiod` wedge. Timeline: tap healthy 50 s (`signal quality → green -6 dBFS`, RMS 0.02–0.10) → **pause** → `audio signal → suspect → silent` → the existing `.silent → reinstall` machine fired (`TAP: Tap reinstall scheduled in 3.0s (attempt #1) → starting`) → **the reinstalled tap came up silent** (no `→ active`, no post-reinstall RMS probe, `features.csv` all-zero for the final ~150 s). The card appeared at ~15 s and **correctly stayed up** because audio genuinely never returned — the visualizer had no signal. NOT a detector bug: `InputLevelMonitor.frameCount` is monotonic (its `reset()` is never called in production — only in `InputLevelMonitorTests`), so the freshness poll has no backwards-counter hazard, and `test_recovery_clearsCard` proves the auto-clear path fires when fresh audio resumes.

### Reinstall fix — step 1 (instrument) landed 2026-06-17

Defect Protocol step 1 for the reinstall-comes-up-silent facet (kickoff `docs/prompts/BUG-057_TAP_REINSTALL_SILENCE_KICKOFF.md`). The `.silent → reinstall` path (`AudioInputRouter+SignalState.performTapReinstall` → `SystemAudioCapture.stopCapture()` then `startCapture()`) had **no per-step breadcrumbs** — session `16-59-43Z` logged `Tap reinstall #1 starting` then nothing (no `install via startCapture gen=2`, no `succeeded`/`failed`), so the recreate hung but the stalling call was unknown. Added per-step `session.log` breadcrumbs (via the existing `onCaptureDiagnostic` sink) mirroring the device-change `performReinstall`: `stopCapture: ENTER → cleanup` / `cleanup done`, then `startCapture: ENTER → createProcessTap` / `tap created → …createAggregateDevice` / `aggregate created → createIOProc` / `IO proc created → startDevice` / `startDevice done → start deviceMonitor`. The **last breadcrumb before silence pins the exact hanging Core Audio call**; also instruments the cold install (same `startCapture`). Engine build green, swiftlint 0; no test (breadcrumb-only on the non-SPM-testable capture path — same precedent as BUG-058's instrument step). **Step 2 (diagnose):** Matt runs an instrumented pause→resume streaming session (build from PRIMARY, Screen Recording granted); from the breadcrumbs identify the stalling call + whether the reinstalled tap *hangs* vs *comes up silent*, and reconcile with BUG-058 (likely shared root). No fix code yet. `RELEASE_NOTES_DEV.md [dev-2026-06-17-174055]`.

### Reinstall fix — step 3 (fix) + step 4 (validate) ✅ RESOLVED 2026-06-17

Implements the step-2 conclusion: the `.silent → reinstall` machine no longer rebuilds a tap that was **already delivering** audio (a user pause) — it only reinstalls a tap that **never delivered** (a genuinely broken cold install: stale Screen-Recording grant / wedged daemon). Mechanism:
- `SilenceDetector` gains `hasEverDetectedSignal` (latched on the first non-silent buffer) + `resetSignalHistory()`.
- `AudioInputRouter.start(mode:)` resets the latch each session.
- `AudioInputRouter+SignalState.scheduleNextReinstall` returns early (logs `Tap reinstall SKIPPED — session has had audio … user pause`) when `hasEverDetectedSignal`.

This removes the pause-churn and the dead-tap lottery: a paused source's working tap is left alone and resumes on play; **the silent-tap detector card (which still appears on a > dwell silence) now AUTO-CLEARS on resume** because the tap stays alive (it couldn't in 16-59-43Z — the freeze is fixed). Preserves BUG-055 / wedged-daemon recovery (a never-delivered cold install still reinstalls). **Tradeoff:** a tap that delivered then died *for real* mid-session is treated as a pause and not auto-recovered — rare; the reinstall was unreliable for it anyway, and the card surfaces it. Tests: 3 new in `AudioInputRouterSignalStateTests` (fires-when-never-had-audio / skips-when-had-audio / reset-clears-latch); also fixed a latent `TestClock` unowned-capture crash the new test exposed. Engine build green, swiftlint 0, signal-state + SilenceDetector suites green; full closeout `EVIDENCE: ALL GREEN` (engine 1494 / app 385 / lint 0 / docgates 10, commit `2f533cf`). `RELEASE_NOTES_DEV.md [dev-2026-06-17-180919]`.

**RESOLVED 2026-06-17 (fix commit `6bac999`)** — Matt validated in session `2026-06-17T18-16-41Z`: **3 pause/resume cycles, all recovered cleanly**, each logging `Tap reinstall SKIPPED — … user pause` and **zero reinstall churn** (no `scheduled` / `starting` / `stopCapture:` / `startCapture: ENTER` during the pauses — only the cold `gen=1` install). The **same `gen=1` tap survived all three pauses and resumed** (`audio signal → active` ×3), confirming the one open assumption (a working tap resumes on its own after a pause — previously unobserved because the reinstall always destroyed it first). `features.csv` 6077/10662 rows nonzero, healthy tail. **Remaining (separate) UX question — RESOLVED 2026-06-17 (Matt chose suppress-on-pause; validated):** the detector card used to *appear* on a deliberate > 10 s streaming pause (it keys on silence, not on the rebuild). See §Card pause-suppression below.

### Card pause-suppression — landed 2026-06-17, pending Matt's validation

Suppresses the silent-tap card on a likely **user pause** so it only raises for a genuine break. Mechanism: the engine's `AudioInputRouter.hasEverDetectedSignal` (the same RMS latch the reinstall fix uses, reset per session) is forwarded to `VisualizerEngine.hasEverDetectedAudio` and provided to `PlaybackErrorBridge`. In `evaluateStall`, a tick is treated as a **likely pause** (don't accumulate toward the card) when: callbacks are still advancing **AND** the signal is `.silent` **AND** the session has had real audio. So:
- **Pause** (alive tap reading zeros, was delivering) → suppressed. ✓
- **Broken cold install** (never delivered → `hasEverDetectedSignal` false) → still raises the card. ✓ (BUG-055 / wedge preserved.)
- **Mode B freeze** (frozen IO-proc → callbacks NOT advancing) → still raises the card. ✓ (a real freeze is not a pause.)

Note the engine's "ever had audio" latch is RMS-based (`SilenceDetector`), NOT `audioSignalState` (which defaults `.active` and would falsely mark a broken tap as "had audio"). Files: `AudioInputRouter+SignalState` (public `hasEverDetectedSignal` forwarder), `VisualizerEngine` (`hasEverDetectedAudio`), `PlaybackErrorBridge` (provider + likely-pause gate), `PlaybackView` (wiring). +3 bridge tests (pause suppressed / never-had-audio fires / Mode-B-after-audio fires). App build green, swiftlint 0, bridge suites 18/18. `RELEASE_NOTES_DEV.md [dev-2026-06-17-184040]`. **VALIDATED + RESOLVED 2026-06-17 (Matt):** pause streaming > 10 s → the card no longer appears (confirmed live); the never-had-audio (broken cold install) and Mode-B-freeze cases still raise it (unit-proven); card surface validated earlier by screenshot.

### Reinstall fix — step 2 (diagnose) 2026-06-17: recreate does NOT hang; the `.silent → reinstall` churns pointlessly on a user pause

Instrumented session `2026-06-17T17-45-44Z` (pause→resume ×2, **both recovered**) captured the full per-step trace:
- **The recreate never hangs.** All 4 `.silent → reinstall` attempts ran the complete `stopCapture (ENTER→cleanup→done) → startCapture (createProcessTap→aggregate→IOProc→startDevice→done) → install gen=N → succeeded` sequence in **< 1 s** each. So 16-59-43Z's "starting then silence" was NOT confirmed as a hang (it was pre-instrumentation); same code, intermittent outcome.
- **The reinstalls fire WHILE the source is paused.** On pause, `audio signal → silent` arms the reinstall (+3 s / +10 s / +30 s backoff). Each reinstall "succeeds" but the new tap reads RMS=0 — **because the source is paused, not because the tap is broken.** Recovery (`audio signal → active`) came when the source resumed and the then-current tap delivered (normal ~1–2 s warm-up, same as the cold gen=1 install). Both pauses recovered after 2 attempts, ~13 s.
- **So the pause-reinstall is pointless churn** — it destroys + recreates a tap that would have delivered fine on resume, spinning a "recreate lottery" on every pause. **16-59-43Z is one of those pause-reinstalls landing a created-but-dead tap** (intermittent; could also be a true hang, still un-instrumented-captured — the breadcrumbs will say which next time it fails).

**Leading fix (step 3 — pending Matt's nod on the behaviour, which is the product question he flagged):** stop reinstalling a tap that was **already delivering** audio before it went silent (= a user pause); only reinstall a tap that **never delivered** (= a genuinely broken cold install — BUG-055 stale grant / wedged daemon). The per-generation RMS probe already provides the "did this generation ever deliver" signal, and the gate is unit-testable in `AudioInputRouterSignalStateTests` (MockAudioCapture + SilenceDetector). This removes the churn AND the dead-tap lottery, and means a pause is harmless: the working tap simply resumes on play. (Validates Matt's "should `.silent → reinstall` fire on a user pause?" → no.) The one assumption the fix itself tests: a working tap resumes on its own after a pause — implementing it + Matt's pause/resume validation IS the confirmation (if the tap does NOT self-resume, the fix surfaces that and we add a real recovery instead).

**So a streaming pause is a contaminated way to validate the card** — pausing → sustained silence → `.silent → reinstall` → the recreated tap hits BUG-057 (comes up silent) → audio never recovers → the card can't auto-clear. Two implications: (1) until BUG-057's reinstall-comes-up-silent is fixed, **the card will fire (correctly) on every streaming pause longer than the dwell**, and the only recovery is a manual output-device switch (the known BUG-057 workaround) — a product question for Matt (longer dwell? infer deliberate pause?). (2) Validate the card's *surface* (look/copy/fade) with the new **DEBUG force-toggle (Cmd+Shift+Option+A)** instead — it shows the real `AudioStallOverlayView` on demand, decoupled from the broken tap recovery. Open question worth a separate look: should `.silent → reinstall` fire on a *user pause* at all (it destroys a working tap and the recreate comes up dead)?

### Related

- `project_streaming_tap_signal_health` (the granted-but-silent-tap note; output-routing as the *other* silent-tap cause), CLEAN.1.5 / GAP-1 (G1 device-swap reinstall — the path that DOES recover), D-061 (capture-mode resilience).
- **Sibling: BUG-055** (stale Screen-Recording grant → silent tap) — same silent-tap family, **distinct root cause**: BUG-055 is permission-denied-after-resign (`CGPreflightScreenCaptureAccess` stale-`true`, fixed by re-grant + relaunch); BUG-057 keeps the grant (audio IS on the tapped device) and recovers only on a device-switch reinstall. This bug's `TAP:` instrumentation (per-install preflight state + the device-change reinstall's RMS) is what tells the two apart in one session.
- Renumbered from BUG-056 (2026-06-17): a parallel session filed an unrelated BUG-055/BUG-056 first (origin `82db932`); this work moved to BUG-057 to avoid the collision.
- Surfaced 2026-06-17 during the CLEAN.7.6c canonical-app live-test debugging.

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

### BUG-050 — Always-on session recorder ~doubles per-frame CPU (encode stacked on render); ungated in normal use (2026-06-14)

**Severity:** P2 (no fps/correctness impact — render alone holds ~52 % of the 60 fps frame budget and 60 fps holds; the cost is sustained extra CPU/power/heat, ~2 cores on the Mac mini, for the entire duration of every session).
**Domain tag:** resource-management / performance
**Status:** **✅ RESOLVED 2026-06-17 (`702697d`) — reframed.** The video gate landed (OFF by default; `PHOSPHENE_RECORD_VIDEO=1` to enable) and is validated on two real sessions (`2026-06-17T22-10-50Z`, `2026-06-18T13-57-23Z`): `video 0 appended`, `frame_cpu_ms` **15.78 → ~8.1 ms** — the render loop genuinely halved. **The original "Activity Monitor steady-state CPU halves" criterion was a MISDIAGNOSIS and is retired:** Activity Monitor stayed 89–115% because the dominant cost is the **continuous real-time stem separation** (the Demucs-style MPSGraph model re-running every ~5 s — 28–29× per ~3 min session) + the preset-dependent render, NOT the video. `encode_cpu_ms` (~6 ms, unchanged with video off) is the *Metal command-encode* metric — the 2026-06-14 entry mis-read it as the video-capture cost. The gate is a real, free frame-loop reduction and is kept; the leftover ~2-core cost is the live-stems feature working as designed (acceptable on the plugged-in Mac mini at 60 fps; a separate question only if laptops/battery become a target). (Diagnosed 2026-06-14; "option A" defer reversed by Matt 2026-06-17.) Surfaced when Matt's Activity Monitor read PhospheneApp at ~99–115 % during the BUG-033 validation.
**Introduced:** the SessionRecorder video-capture path; instantiated unconditionally (`VisualizerEngine.swift:785`, `SessionRecorder()` with `enabled: true` default) — no production gate.
**Resolved:** 2026-06-17 (`702697d`, video gate) — reframed: the gate IS the fix (the video tax is gone); the "halve Activity Monitor" criterion was retired as a misdiagnosis (dominant CPU = live stem separation, not the recorder). Validated sessions `22-10-50Z` + `13-57-23Z`.

**Expected:** the diagnostic session recorder adds modest overhead; it should not roughly double the app's CPU in normal use.
**Actual:** the recorder runs every session (ungated). Its per-frame `encode_cpu_ms` (~7–9 ms — drawable→pixel-buffer capture + AVAssetWriter feed) is **additive** to `renderframe_cpu_ms` (~8.6 ms): `frame_cpu_ms` ≈ encode + render ≈ 15.8 ms ≈ a full 60 fps budget → ~1 core for the frame path, plus audio/main threads → Activity Monitor ~99–115 %. Encode is on its own thread, so it does not (much) cost frame rate — render alone is ~52 % budget and 60 fps holds for 98.8 % of frames — the impact is sustained CPU/power/heat. Compounded by BUG-039 (the same recorder's video writer dying + restarting, hitting its 8/8 cap on macOS 26.5 / M2 Pro).
**Reproduction steps:** play any session; Activity Monitor shows PhospheneApp ~99 %+. Confirmed from artifacts: `~/Documents/phosphene_sessions/2026-06-14T17-58-44Z/features.csv` — `frame_cpu_ms` mean 15.78 (encode 7.16 + render 7.10); in the two 30 s windows where the writer was dead between BUG-039 restarts, `encode_cpu_ms` → ~0.6 and total CPU halved to ~9 ms.
**Session artifacts:** `2026-06-14T17-58-44Z/features.csv` (per-frame `frame_cpu_ms` / `encode_cpu_ms` / `renderframe_cpu_ms` breakdown).
**Suspected failure class:** `resource-management`.
**Verification criteria:**
- [x] Recording gated off by default with an explicit per-session enable (`PHOSPHENE_RECORD_VIDEO=1`) — `SessionRecorderTests.test_videoDisabled_noCaptureTexture_csvStillRecords` (video off → nil capture texture, no video.mp4, features.csv still records) + `test_videoEnabled_allocatesCaptureTexture`. CSV/stems unaffected.
- [x] Validated on real sessions (`22-10-50Z`, `13-57-23Z`, Matt): `video 0 appended` across a full session; `frame_cpu_ms` 15.78 → ~8.1 ms (render loop halved); 60 fps held; CSV/stems/raw-tap intact.
- [retired] ~~Activity-Monitor steady-state CPU roughly halves~~ — misdiagnosis (Activity Monitor is stem-separation-dominated, not video; see Status). The *frame-loop* CPU halved, which is what the gate can affect.

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

### BUG-037 — Arachne spiral chord-count contract three-ways inconsistent (CPU 200 / shader 441 / test 104): spiral builds to ~45 % then pops to complete (2026-06-09)

**Severity:** P2 (visible build defect: per-chord reveal gate saturates at 200/441 ≈ 0.45, then the `.stable` snap shows the remaining ~55 % in one frame; build cycle halves to ~62 beats vs the documented ~136, firing `_presetCompletionEvent` early).
**Domain tag:** preset.fidelity (Arachne)
**Status:** **✅ RESOLVED 2026-06-18 — Matt's M7 (session `2026-06-18T14-30-52Z`): the full web draws to completion, then transitions on the completion event, no pop** (two-part root cause — chord-count single-source + `wait_for_completion_event` spanning sections — detailed in the M7 narrative below). Code fix landed CLEAN.3.4 (2026-06-17); automated criterion met. Single source of truth: the CPU's `spiralChordsTotal` (`ArachneState.recomputeSpiralChordTable`) now owns the count — the 200 cap (which sat *below* the legitimate 324–576 product so it always fired) was raised to `maxSpiralChords = 600`, a degenerate-case guard only; `spiralPacked` is published already-normalized (0..1) and the shader reveals by it directly (`saturate(spiral_packed)`), so the hardcoded 441 and the test's 104 are gone. The change is build-phase-temporal (the `.stable` golden is unchanged — the final spider is identical; only the reveal animation differs), so `PresetRegressionTests` stays green with no golden regen. **The manual/visual criterion needs a live M7** (the build reveal animates over the documented ~73 s; the existing RENDER_VISUAL harness only captures an early-build frame, so it cannot demonstrate the spiral reveal — best validated live or via a build-sequence render).

**M7 FAILED 2026-06-18 (Matt, session `2026-06-18T01-21-18Z`) — the pop persisted; the diagnosis was incomplete.** The chord-count normalization is verified *correct* in code (new test `ArachneStateBuildTests.spiralRevealClimbsPastOldCeiling` drives the build and reads the actual `webs[0].spiralPacked` climbing past 0.6 — the stuck-at-0.45 ceiling is gone). But the live pop has a **second, dominant root cause the audit missed**: Arachne's build (~92 s) **outlives its planned segment.** `wait_for_completion_event: true` only sets `maxDuration = .infinity` (`PresetMaxDuration:101`), which fills the current SECTION; `planOneSegment` still bounds the segment at `remainingInSection`, terminated `.sectionBoundary` (`SessionPlanner+Segments:177-192`). Love Rehab's section ≈ 38 s, so the plan-driven boundary cut the build mid-reveal → forced `.stable` snap = the pop. **The cap-raise made it worse** (build 54 s → 92 s, so the cut lands at a lower reveal %). Matt's call (AskUserQuestion 2026-06-18): **make `wait_for_completion_event` truly span sections.** Fix (planner): `planOneSegment` now gives a completion-gated preset a segment spanning its `naturalCycleSeconds` (capped at `trackEnd`); `planSegments` tracks `coveredUntil` so covered sections don't re-emit — the plan boundary lands past the build's completion, the build finishes (reveal → 1.0), and the live completion event drives the transition with no pop. Gate: `SessionPlannerTests.waitForCompletion_segmentSpansSections`; 25 SessionPlanner + 99 orchestrator/integration tests green. Normalization + cap-raise stay (correct once the build completes). **RESOLVED — Matt live-validated 2026-06-18 (session `2026-06-18T14-30-52Z`):** the full web draws to completion, then transitions on the completion event — *no pop*. Arachne ran 14:31:25 → 14:32:08 (~43 s; the live electronic beat density laid the spiral faster than the 118 BPM grid estimate) and ended on the build's completion event, not the section boundary. Known follow-up: the completion event advances via `presetLoader.nextPreset()` (loader cycle), so the preset *after* a completed wait-preset is off-plan — a minor variety deviation, not a pop; flag if it matters.
**Introduced:** post-BUG-011 ranges (`radialCount`/`spiralRevolutions` ∈ [18, 24], `ArachneState._reset()` :1086-1087) made the uncapped chord product 324-576, so the `min(200, …)` cap at `recomputeSpiralChordTable()` (`ArachneState.swift:1005`) **always** fires; the shader normalizes `spiral_packed / 441.0` (`Arachne.metal:1336`); `PresetAcceptanceTests.swift:335` uses a third value (104).
**Resolved:** 2026-06-18 — chord-count single source (`d430d64`) + the `wait_for_completion_event`-spans-sections planner fix (`e6a530d`); Matt live-validated (session `2026-06-18T14-30-52Z`, no pop). The audit's chord-count framing was necessary but not sufficient — the build-outlives-its-section pacing was the dominant cause.

**Expected:** spiral chords reveal continuously outside-in to completion (D-095 per-chord gate), with the documented ~92 s round-8 build cycle.
**Actual:** `fgProgress` saturates at ~0.45 → ~45 % of chords visible, then a one-frame pop to complete; `spiralChordRadii` truncates at radius ≈ 0.27 instead of reaching the 0.05 core.
**Reproduction steps:** run Arachne through a full build cycle (live or `PresetVisualReviewTests` frame phase); watch chord coverage vs `frame_progress`.
**Session artifacts:** `docs/diagnostics/CODE_AUDIT_2026-06-09.md` (Presets P2 section).
**Suspected failure class:** `api-contract` (three uncoordinated constants for one contract) **+ `pipeline-wiring`** (the dominant live cause: `wait_for_completion_event` segments cut at the section boundary).
**Verification criteria:**
- [x] Automated (CLEAN.3.4): the CPU `spiralChordsTotal` is the single source — shader reveals by the CPU-normalized `spiralPacked` (no constant), test fixture aligned. `ArachneStateBuildTests.spiralChordCountHonoursProduct` + `spiralRevealClimbsPastOldCeiling`; the planner span is locked by `SessionPlannerTests.waitForCompletion_segmentSpansSections`.
- [x] Manual/visual (M7, Matt 2026-06-18): the full web draws continuously to the core, then transitions on the completion event — no pop (session `2026-06-18T14-30-52Z`).

---

### BUG-042 — Structural sections are still ~1.5 s on real music: the analyzer's GEOMETRY is note-scale (6.4 s window, 85 ms checkerboard), not section-scale — and post-BUG-040 confidence now endorses the junk (2026-06-10)

**Severity:** P2 (the Skein.5 structure sub-feature and the orchestrator's `StructuralPrediction` consumer act on a boundary every ~1.5 s with confidence 0.85–1.00 — worse than pre-BUG-040, where low confidence at least kept the gates shut).
**Domain tag:** dsp.structure
**Status:** **Fix landed (CLEAN.6.2, 2026-06-19) — code-complete, pending validation.** The analyzer now decimates its ~94 Hz input to one structural frame every 0.5 s (2 Hz) before the similarity matrix, so the fixed frame-denominated geometry is section-scale: 8-frame checkerboard = 4 s, `minPeakDistance` 16 = 8 s minimum section, 600-frame ring = 5 min. BUG-035/040 + AABA regression tests re-expressed and green at the new rate (DSP suite 23/23 + MIRPipeline structural green). **Validation (FA #27 — real audio only):** the 30 s tempo-fixture replay showed no note-scale junk but could NOT show the opposite failure (no real section fits in 30 s). Matt's live **Smells Like Teen Spirit** session (`2026-06-19T14-50-27Z`) did: the section-scale fix was **over-conservative** — **1 boundary in 5 min at confidence 0** → no structural preset-switching (stayed on one preset). Diagnosed by an offline floor sweep of that session's `raw_tap.wav` through the production FFT→MIRPipeline path: `minNoveltyFloor = 0.02` (sized for the noisy *pre*-decimation stream) gated out every real section — the 0.5 s decimation smooths the stream so real-section novelty peaks land at **~0.005–0.02**. **Recalibrated 0.02 → 0.01** (the clean knee): SLTS now yields **9 sections at confidence 0.64** at musically real times (26 s = intro→verse drop, then 46/98/112/124/166/207/228/287); the 3 tempo fixtures stay junk-free (0/0/1 on 30 s); 19 structural unit tests green. **✅ RESOLVED 2026-06-19** — Matt's live re-test (session `2026-06-19T15-48-25Z`, SLTS) confirmed the detector: **5 sections, confidence to 0.91**, at musically real times (start_s 8.5/25.4/47.4/93.2/110.3), and the one orchestrator switch landed *exactly* on section 1→2 — detector + wiring work, BUG-042's Expected is met. Presets didn't *visibly* track sections for two downstream reasons, both separate from this (detector) bug: (1) the reactive orchestrator only switches to a higher-scoring preset (`scoreGap > 0.05`, so it stayed on the best-scoring preset); (2) local-file sessions ran in reactive fallback because `buildPlan()` was disabled (2026-05-28 BUG-021 revert) — itself caused by THIS bug's junk detector inflating `estimatedSectionCount` to ~180 → planner segment-cycling. Both are tracked under the **LFPLAN** increment (LF planning re-enabled `a07b0d1`; `PlannerSectionCountScalingTests` pins the 180→9 link; pending Matt's live playlist validation). 2026-06-11 (BUG-046): the Skein consumer's 10 wall-s boundary-spacing guard stays (harmless after the fix).
**Introduced:** structural — the analyzer's defaults were sized for a different feature rate; at the live ~94 Hz analysis rate the geometry detects note/bar novelty, not sections.
**Resolved:** 2026-06-19 — 2 Hz section-scale decimation (`9779337`) + `minNoveltyFloor` 0.02→0.01 recalibration (`3d2b263`); live-validated SLTS `2026-06-19T15-48-25Z` (5 sections, conf 0.91). Files to §Resolved at next pruning.

**Expected:** musical sections of 15–60 s with confidence that reflects real form.
**Actual (session `2026-06-10T17-39-41Z`, 6 streaming tracks):** boundaries every **1.3–2.5 s** on every track (Love Rehab: 30 in ~50 s), `section_start_s` now sane and durations now CONSISTENT — so duration-consistency-driven confidence climbs to **0.85–1.00** and the Skein conf gate opens on junk (the exact risk noted in the BUG-040 fix rationale).
**Why BUG-040's fixes were insufficient:** all three were real (frozen clock, live-edge dedup escape, no absolute floor) but operate at the wrong SCALE. `maxHistory = 600` frames at ~94 Hz = a **6.4-second** similarity window; `kernelHalfWidth = 8` frames = **85 ms** checkerboard blocks. An 85 ms before/after comparison inside a 6.4 s memory detects fills, chord changes and transients — every one a "boundary." The `minNoveltyFloor = 0.02` was calibrated on a smooth synthetic fixture (junk ≈ 0.0003); real music's frame-to-frame chroma variance puts baseline novelty far above it. The 1.3–2.5 s cadence = peaks admitted as fast as `minPeakDistance` (120 frames ≈ 1.28 s) allows.
**Reproduction steps:** any real track ≥ 1 min; read the section tail columns — index inflates every ~1.5 s with high confidence.
**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-10T17-39-41Z/features.csv` (cols 53–55).
**Suspected failure class:** `calibration` (detector geometry vs feature rate).
**Proposed direction (next increment):** run the STRUCTURAL feature stream at section scale — aggregate the 16-dim feature vector to ~2 Hz (mean over ~0.5 s) before it enters the similarity matrix. The same code then gives: 600-frame ring = **5 minutes** of memory, 8-frame kernel = **4-second** checkerboard blocks, `minPeakDistance` retuned to ~16 (≈ 8 s minimum section). Re-calibrate `minNoveltyFloor` against REAL session feature streams (replayable from raw_tap/preview audio), not synthetic fixtures. The Skein conf-gate thresholds stay; the existing BUG-035/040 regression tests must be re-expressed at the new rate.
**Verification criteria:**
- [~] Automated (real audio): **negative DONE** (3 tempo fixtures junk-free, 0/0/1 on 30 s) **+ positive DONE offline** — after the `minNoveltyFloor` 0.02→0.01 recalibration, the `StructuralSectionScaleReplay` sweep of Matt's SLTS `raw_tap.wav` (`PHOSPHENE_REPLAY_WAV`) finds **9 musically-plausible sections at conf 0.64** (was 1 at conf 0 pre-recalibration). **Live confirm PENDING** (Matt's re-test; calibrated on one track). (`FixtureSessionCaptureGenerator` can't help — it writes stems.csv only, no structural stream.)
- [x] Automated: BUG-035 (ring-wrap dedup) + BUG-040 (edge guard / floor / clock) regression tests green at the new feature rate. **DONE (CLEAN.6.2)** — re-expressed at section scale; the live-edge guard's "evolving material registers nothing" fixture was made monotonic (the pre-fix incommensurate sinusoids had a ~25 s period that is now a legitimate section).
- [ ] Manual: a live session's section columns show 15–60 s sections; confidence high only on genuinely sectional material. *(Pending Matt's live read.)*

---

### BUG-043 — Mid-playback analysis stall: a 9.6 s gap between analysis frames froze the visuals then lurched (2026-06-10)

> **Renumbered from BUG-042** (parallel-session number collision, 2026-06-10): BUG-042 = the structural-section geometry defect, filed earlier the same day. The FBS.S3.2 commit message references the old number.

**Severity:** P2 (a multi-second visual freeze + lurch mid-track; observed once, plus a 40 s gap during the silent prep window of the same session).
**Domain tag:** `pipeline-wiring` (audio-analysis cadence) — possibly BUG-039-adjacent (the video-writer stall instrumented the same week).
**Status:** Open — **monitoring; no recurrence after BUG-036 sites 1 + 2** (2026-06-17, see Validation). Observed once (2026-06-10); not instrumented. Retire after a few more clean sessions (BUG-058 / BUG-012 pattern) or instrument if it recurs.
**Resolved:** —

**Expected:** analysis frames arrive continuously (~60 Hz) for the whole session; `deltaTime` stays ~0.017 s.

**Actual (session `2026-06-10T17-50-56Z`, Love Rehab):** three gaps clustered at te 28.8–29.7 s — `deltaTime` 0.44 s, 0.33 s, then **9.59 s** — with a 50 ms CPU frame. During a gap the renderer keeps drawing the STALE FeatureVector (frozen pulse/features), then everything jumps at once when analysis resumes — Matt's "flashing around 30 s" on this track matches the gap end. The same session's silent prep window had a 40.4 s gap (may be benign idling — undetermined). The track also re-segmented mid-play (a second te-reset ~50 s in — cause undetermined, possibly a user restart).

**Reproduction steps:** unknown trigger — scan any session's `features.csv` for `deltaTime > 0.2` during audible playback.

**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-10T17-50-56Z/features.csv` (Love Rehab segment, te 28.8–29.7).

**Suspected failure class:** `resource-management` or `concurrency` (analysis-queue starvation / tap callback stall). The PERF-era "probably-environmental CPU bump" family is a prior with a similar smell.

**Validation (2026-06-17, session `2026-06-17T20-52-27Z`, after BUG-036 sites 1 + 2):** a full 8-track streaming session showed a rock-steady **60 Hz** analysis cadence — median Δt 0.0167 s, p99 0.0194 s, **worst gap 84 ms** over 25,017 audible frames — vs the 0.44 / 0.33 / **9.59 s** original incident. No freeze-lurch (Matt). The only > 0.2 s Δt gaps were the pre-play startup window (frame 0, silent) and a doorbell lull correctly handled as a user pause (BUG-057 suppression — analysis kept ticking on silence, so no gap). N = 1 for an intermittent defect → not closed; consistent with "fixed/mitigated by BUG-036," monitoring. The deferred BUG-036 site 3 + hand-off rework (the candidate concurrency fix) is **parked** because this came back clean.

**Verification criteria (when fixed):**
- [ ] Instrumentation: a log line whenever inter-analysis-frame dt exceeds 0.25 s during audible playback (with queue depths / tap callback timing).
- [ ] No dt > 0.5 s gaps during audible playback across a full session. — *held across session `20-52-27Z` (max 0.084 s during playback); needs to hold across several more before retirement.*

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

### BUG-039 — Session video stops appending silently a few seconds into some sessions (intermittent; recorder keeps "running") (2026-06-09)

**Severity:** P2 (the session video is the primary M7 review artifact; a truncated video forces CSV-only reconstruction of visual defect reports — it directly degraded the Skein.5 M7 session review).
**Domain tag:** `resource-management` (session recorder / AVAssetWriter)
**Status:** **✅ RESOLVED 2026-06-18 — Matt's live multi-session confirmation passed (the silent-stop signature no longer occurs).** Recovery landed 2026-06-10; the running-vs-actually-writing invariant landed CLEAN.3.6 (2026-06-17). The instrumentation caught the death certificate live in `2026-06-10T17-50-56Z`: the writer left `.writing` **10 s after lock** with `AVFoundationErrorDomain -11800 (AVErrorUnknown)` / underlying `NSOSStatusErrorDomain -16341` — an UNDOCUMENTED OSStatus (Apple forums confirm this -11800+mystery-status class is an intermittent encoder/format session failure; notably this was also the session with the BUG-042 analysis stalls — co-occurrence noted, causality unproven). Since the trigger is undocumented and intermittent, the durable fix is RECOVERY, not decoding: on writer death the partial file is retained (playable to its last 5 s fragment per BUG-022), the recorder **rolls to a new segment file** (`video_2.mp4`, `video_3.mp4`, …) within one frame, and recording resumes — bounded at 8 restarts/session. A session now never loses more than ~one fragment of video per death. Regression-locked by `test_videoWriterDeath_rollsToNewSegment_bothFilesReadable` (kills the live writer the way the field failure does — status leaves `.writing` with the file retained — and asserts both segments exist + the recovery segment is a readable video + the restart is logged). **CLEAN.3.6 (2026-06-17) added the running-vs-actually-writing invariant** (the follow-through the audit flagged): a successful-append counter + last-append frame index drive an invariant check at `finish()` that (a) appends a video-outcome summary to the session-end log line (`video N appended / S segment(s) / R restart(s) / disabled=bool`) so a recorder that kept "running" while the writer silently stopped can never look healthy from the artifacts, and (b) logs a loud `BUG-039 invariant VIOLATED` line when the silent-stop *signature* is present (writer locked, then appends stopped > 300 frames before session end with no death/restart and not disabled — every *explained* stop is excluded). The recovery test was extended to confirm appends resume after the roll (`videoFramesAppended > 0`, no false violation); the pure predicate is unit-tested GPU-free (`test_bug039Invariant_silentStopPredicate`). **Closure confirmed 2026-06-18 (Matt's live multi-session check — the affected-session signature no longer occurs).**
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
**Status:** Open — **AGC3.3 fix is PARTIAL. Reopened 2026-07-08 after a false close.** It handles soft/pre-rolled onsets but NOT immediate hard-onset tracks. Prematurely marked RESOLVED 2026-07-08 (reverted): the close rested on the synthetic `AGC3ColdStartSpikeTests` fixture (FA #27 — synthetic audio doesn't reproduce real behavior) plus ONE real session (`2026-07-08T15-07-53Z`) that happened to have a soft onset (0.06 s pre-roll, 1.27×) — non-representative. **Counter-evidence (session `2026-07-09T02-04-02Z`, track SZ2, live M7):** zero pre-roll, f.bass peaks **3.964 at te=1.28 s → 14.8×** steady (0.267); FFO `fo_spike` **1.80 peak / 1.21 steady** — the pop-and-drop, on code byte-identical to `main`. AGC3.1 measured (2026-06-05); AGC3.2 decided **D-148**; AGC3.3 (`144f824`) implemented seed-from-first-audible + hold-through-sustained-silence in `BandEnergyProcessor`, regression-locked by `AGC3ColdStartSpikeTests` (which passes but is insufficient — see the added criterion below).
**Introduced:** structural — `BandEnergyProcessor`'s total-energy AGC seeds its running average from whatever energy is present at capture start; during the inter-track silence the running average decays toward zero, so the first audio frame of every track explodes the AGC scale before it catches up.
**Resolved:** — (reopened; AGC3.3 is a partial fix)

**Expected:** continuous-energy presets (those reading `f.bass`/`f.mid`/`f.treble` directly) arrive smoothly when a track's audio starts.

**Actual (session `2026-06-06T01-18-36Z`):** at every track onset the first audible frame spikes `f.bass` far above its steady ~0.25 — **Cherub Rock te=1.42 `f.bass`=4.003; Alameda te=0.66 `f.bass`=3.697**. Ferrofluid Ocean (`spikeStrength = 1.0 + 0.8·clamp(f.bass,0,1)`) pops to 1.8× then collapses as bass settles — a "pop-and-drop," not a smooth arrival. During the preceding silent pre-roll `f.bass`=0 so the spikes sit flat/static (only the slow Gerstner swell moves), so the preset reads near-static then jarringly pops.

**Reproduction steps:** play any local-file or streaming session; inspect `features.csv` `bass` at each track's first audible frame — it spikes ~5-15× the steady value for ~1-2 s while the AGC scale catches up.

**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-06T01-18-36Z/features.csv` (Cherub Rock + Alameda startups); **`~/Documents/phosphene_sessions/2026-07-09T02-04-02Z/` (track SZ2 — the hard-onset reproducer the earlier close lacked: 14.8×, `fo_spike` 1.80/1.21).**

**Suspected failure class:** `calibration` — AGC seed/scale on the silence→onset transition. **Reopen hypothesis (unverified — instrument, don't guess):** with ~0 s pre-roll the seed-from-first-audible logic seeds off a near-silent lead-in frame, so the running-average denominator is still too small when the bass slams in ~1 s later.

**Verification criteria (when resolved):**
- [x] **Automated (synthetic fixture — PASSES BUT INSUFFICIENT):** on a silence→onset fixture through the real `MIRPipeline.process`, `f.bass` does not exceed 2× steady. *(`AGC3ColdStartSpikeTests` — 32.6×→<2×, 10.6×→<2×.)* **This green did not catch the real-track spike (FA #27) — the fixture must be extended with an immediate/hard-onset case (0 s pre-roll, energy slam ~1 s in) that reproduces the 14.8× before any re-fix.**
- [ ] **Automated (real-audio, NEW):** replay the SZ2 reproducer (or an equivalent hard-onset clip) through the pipeline; onset `f.bass` ≤ 2× steady.
- [ ] **Manual:** Matt confirms continuous-energy presets (Ferrofluid Ocean) arrive smoothly on a hard-onset track — no pop-and-drop.

**Manual validation required:** Yes — it's a felt visual artifact. **The 2026-07-08 close waived this and was wrong (see Status); do not re-close without a hard-onset real-audio check.**

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
**Resolved:** 2026-06-06 — commits `bf711edf` (AGC2.1 measure), `b1c1d1b7` (D-146 decision), `41d87bf9` + `0d2ddb51` (AGC2.3 fix), `95a16881` (AGC2.4.1 cold-start warmup). On `main` (origin/main).

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

**Resolved 2026-06-16 (CLEAN.7.14)** — `SSGITests.test_ssgi_performance_under1ms_at1080p` made contention-robust (it never entered the table above — it surfaced fresh under the full ~1479-test parallel `swift test` run, the same GPU-heavy parallel load the CLEAN.7.6 flash-safety suite added that exposed this whole flake family). It flaked **two** ways under contention, neither a real regression: (1) an `XCTest measure {}` block benchmarking the 1080p SSGI render **failed on relative standard deviation > 10 %** (XCTest's default bound; ~17.7 % observed) — pure variance; and (2) the real gate computed SSGI overhead as a **5-pair MEAN of (with − without) `Date()` timings**, which folds contention spikes straight into the average. Isolated, all 7 SSGI tests run in ~0.13 s. Per the deterministic-over-budget-widening rule (CLEAN.7.9/7.10/7.11/7.12), the sub-1 ms gate is **kept, not loosened**: the `measure {}` benchmark is removed and overhead is computed from the **minimum of 8 warm samples per path** — contention can only ADD latency to a GPU submit, so each path's min is its clean true-cost floor and `minSSGI − minBase` is the clean overhead estimate, immune to a few starved samples. The SSGI render path is untouched; test-only, no production delta. (The structural twin — the single-sample ICB frame-perf gate `test_gpuDrivenRendering_cpuFrameTimeReduced` — is fixed the same way in **CLEAN.7.13**, consolidated onto this same branch.) See `RELEASE_NOTES_DEV.md [dev-2026-06-16-e]`.

**Resolved 2026-06-16 (CLEAN.7.13)** — `RenderPipelineICBTests.test_gpuDrivenRendering_cpuFrameTimeReduced` made contention-robust (it never entered the table above — it surfaced fresh under the full ~1469-test parallel `swift test` run during the CLEAN.7.12 closeout). Structurally identical to the CLEAN.7.10 flake: a **single-sample `Date()` wall-clock assertion around one warm ICB frame submit** (blit + compute + render), run inside the parallel suite — a saturated GPU/CPU inflates the lone submit past the 2 ms budget (the case-level time was a benign 0.277 s; the *timed inner submit* blew the gate), while isolated it passes in ~0.37 s. Per the deterministic-over-budget-widening rule (proven on CLEAN.7.9, applied to this exact shape on CLEAN.7.10), the 2 ms gate was **kept, not loosened**: the assertion now takes the **minimum of 8 warm samples** — contention can only ADD latency to a GPU submit, so the min is the clean estimate of true cost and is robust to a few starved samples. The `measure {}` variance block is unchanged. The ICB renderer path is untouched; test-only, no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-06-16-d]`.

**Resolved 2026-06-16 (CLEAN.7.12)** — `UMABufferExtendedTests.test_concurrentWriteRead_noDataRace` made deterministic (it never entered the table above — it surfaced fresh under the full ~1479-test parallel `swift test` run during the CLEAN.7.6 flash-safety closeout, which added GPU-heavy parallel tests that raised pool contention). The test dispatched 200 trivially-fast, lock-free blocks (100 writes + 100 reads to a `UMABuffer`) and asserted a **fixed 30 s** `DispatchGroup.wait(timeout:)` returned `.success`; under contention the GCD thread-pool drain latency exceeded the deadline → `.timedOut` (observed 34.9 s), while isolated the whole class runs in 0.048 s. Per the deterministic-over-budget-widening rule (CLEAN.7.9/7.10/7.11), the deadline is **removed, not widened**: the test now `wait()`s with no timeout, returning exactly when the blocks drain — it cannot flake on elapsed time, and a genuine deadlock surfaces as a CI hang (same trade as CLEAN.7.11's `await …?.value`). Added a smoke-level post-condition — each writer wrote a distinct index, so after the barrier `buf[i] == Float(i)` for all i — catching gross corruption / lost writes; true data-race detection still requires TSan (per the file header). Test-only, no production delta (`UMABuffer` untouched). See `RELEASE_NOTES_DEV.md [dev-2026-06-16-c]`.

**Resolved 2026-06-15 (CLEAN.7.11)** — `ToastManagerTests.autoDismiss_afterDuration` removed from the table above. The test enqueued a `duration: 0.05` toast then slept a **fixed** wall-clock window (ratcheted 400 ms → 1000 ms and still flaking — CLEAN.2.3.8 closeout, 2026-06-15) before asserting `visibleToasts.isEmpty`; under @MainActor parallel-suite contention the auto-dismiss continuation could slip past the fixed window. Per the deterministic-over-budget-widening rule (CLEAN.7.9/7.10), the budget is **removed, not widened**: the test now `await`s the actual auto-dismiss `Task` to completion via a new `#if DEBUG` seam `ToastManager.dismissTask(for:)`, so it blocks exactly until the dismissal lands and races no deadline — **this is the fix the row prescribed**. Behavioural intent preserved — a finite-duration toast auto-dismisses; an `.infinity` one schedules no task (early `guard`). Test-only, no production delta (`ToastManager` dismiss logic untouched). See `RELEASE_NOTES_DEV.md [dev-2026-06-15-g]`.

**Resolved 2026-06-14 (CLEAN.7.10)** — `RayIntersectorTests.test_rayTrace_1000Rays_under2ms` made contention-robust (it never entered the table above — it surfaced fresh on the Mac mini during the CLEAN.1 Phase-0 re-confirmation, having passed 1469/1469 on both prior integration closeouts). The failing line was a **single-sample `Date()` wall-clock assertion around one GPU command-buffer submit**, run inside the ~1469-test parallel suite — about the most contention-fragile shape there is: a saturated GPU/CPU inflates any one submit past the 2 ms budget, while isolated the whole class incl. this test runs in 0.42–0.54 s (5/5 green). Per the deterministic-over-budget-widening rule (proven on CLEAN.7.9), the 2 ms gate was **kept, not loosened**: the assertion now takes the **minimum of 8 warm samples** — contention can only ADD latency to a GPU submit, so the min is the clean estimate of true cost and is robust to a few starved samples. The ray-intersector path is untouched by CLEAN.1 (last modified in render increment 3.3); test-only, no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-06-14-a]`.

**Resolved 2026-06-13 (CLEAN.7.9)** — `MetadataPreFetcherTests.fetch_networkTimeout_returnsWithinBudget` removed from the table above. The wall-clock budget — ratcheted 3 s → 8.25 → 15 → 45 s across prior sessions without ever converging (16.1 s / 22.8 s observed under the ~1460-test parallel suite during the CLEAN.1.x closeouts) — was replaced by a deterministic behavioural assertion: the merged profile carries the fast fetcher's `energy` but **not** the slow fetcher's `bpm` (excluded by the 1 s timeout). The outcome depends only on the 1 s-vs-10 s ordering (the 1 s timer's continuation is enqueued ~9 s before the 10 s one — contention delays both, never inverts them), not on measured elapsed time, so it cannot flake under cooperative-pool contention. Renamed `fetch_networkTimeout_returnsFastResultNotSlow`; adversarially proven to trap a timeout that lets the slow result leak (`bpm → 999` fails `== nil`, a ~10 s block not a hang). Test-only; no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-06-13-b]`.

**Resolved in the 2026-06-01 hardening pass** (made deterministic — no longer wall-clock-dependent, removed from the table above): `FirstAudioDetectorTests` (ManualDelay), `AppleMusicConnectionViewModelTests` (bounded-yield state polling; never required Apple Music.app — uses `MockAppleMusicConnector`), `SessionManagerTests` lifecycle suite (`waitForReady` safety deadline 3 s → 15 s). `PreviewResolverTests` carries no wall-clock waits or `URLProtocol` stubs in current source — the earlier "rate-limit timing / `.serialized` applied" note did not match the code and was dropped.

---

## Resolved (recent)

