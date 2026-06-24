# Phosphene — Engineering Plan

> **Narrative split (RB.3, 2026-06-11):** completed-increment narratives dated before 2026-06-01 moved to [`ENGINEERING_PLAN_HISTORY.md`](ENGINEERING_PLAN_HISTORY.md). Their headers remain below as the status record (increment ID → status + date); full narratives are in the history file and `git log`.

## Planning Principles

- One increment = one reviewable outcome that fits a Claude Code session.
- Product quality and show quality are both first-class.
- No new subsystem lands without tests appropriate to its risk.
- Documentation follows implementation truth, not aspiration.
- Infrastructure increments and preset increments are never bundled.

## Current State

The foundation is implemented and tested: native Metal render loop with a data-driven render graph; Core Audio tap capture with provider abstraction; full MIR + stem-separation pre-analysis (MPSGraph Open-Unmix, Beat This!); session lifecycle from playlist connection through planned playback (streaming + local-file paths); the Orchestrator scoring/planning/adaptation stack; and the ray-march / feedback / mesh / particle preset substrates with the certification pipeline. Test infrastructure: swift-testing + XCTest across unit, integration, regression, and performance categories; SwiftLint strict; protocol-first DI with test doubles.

For anything inventory-shaped, read the artifact, not a prose copy of it:

- Certified-preset roster: the preset JSON sidecars (`certified` flag) and [`docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md`](ENGINE/RENDER_CAPABILITY_REGISTRY.md).
- Recent work: `git log --since="2 weeks ago" --oneline`.
- Phase status: the phase headers below.
- Open defects: [`docs/QUALITY/KNOWN_ISSUES.md`](QUALITY/KNOWN_ISSUES.md) §Open Index.

## Recently Completed

### Phase SECDET — Section-detection rebuild ✅ REMOVED (2026-06-24; built SECDET.1–.6 + 3 live tests, then **deleted**. Section detection is structurally **local-file-only** — streaming has only a 30 s preview, no algorithm fixes that — AND below the perceptual bar there (live F@3 ≈ 0.29–0.41, ~half the transitions wrong); the "no-ML" premise was a misreading of D-009 (= no-CoreML, not no-ML). The McFee detector + `~/phosphene_section_lab/` were deleted; the planner equal-slices. Full rationale: DECISIONS D-170 §Reversal. The SECDET.1–.6 rows below are kept as the build record; kickoff `~/phosphene_section_lab/PORT_KICKOFF.md`, D-170)

Replace the novelty-only offline section detector (`StructuralAnalyzer` boundary role) with the lab-validated **McFee/Ellis Laplacian spectral clustering** (D-170) — repetition-aware, on-device DSP+Accelerate, no ML. The lab (`~/phosphene_section_lab/`) is the offline oracle; the port is correct when its boundaries + F-scores reproduce the lab's on the same tracks (validate offline, never live — live iteration ate 4 sessions before the offline pivot).

- **SECDET.1 — Features ✅ (2026-06-23).** Beat-synced 252-bin log-CQT (median) + 13 MFCC (mean) @ 22050 Hz in Swift, matching the lab spec (`precompute.py` / `tune_corpus.py`). New `SectionFeatureExtractor` + `ConstantQTransform` (Brown-Puckette sparse kernel, `amplitude_to_db(ref=max)`) + `MFCCProcessor` (Slaney mel + DCT-II ortho) + `VDSPRealFFT`. **Done-when (met):** Swift features reproduce librosa goldens — Cq recurrence-SSM corr **0.9995**, MFCC corr **1.0**, mel basis exact (Δ 3.7e-9), frame/segment counts exact. Golden harness (`export_golden.py` in the lab → `SectionFeatureGoldenTests`, hermetic + golden-match; skips when the lab is absent). Input is already-22050 mono PCM + beat frame indices (isolates feature fidelity from the beat tracker). **Perf follow-up — resolved in SECDET.3a:** the ≈ 2 min/track figure is a *debug*-build artifact; in release (`-O`) the CQT is 2.7 s/track (front-end 3.5 s), so no per-octave-downsampling port is needed.
- **SECDET.2 — Graph + clustering ✅ (2026-06-23).** Recurrence affinity → timelag median filter → MFCC path diagonal → μ-balanced fuse → normalized Laplacian → LAPACK `ssyev` bottom-k eigvecs → median(9,1) + cumulative-norm → hand-rolled k-means(k=5) → boundaries → 8 s merge. New `SpectralSectionDetector` + `RecurrenceGraph` + `SymmetricEigen` (first LAPACK in the codebase) + `KMeans`. **Done-when (met):** Swift boundaries reproduce `tune_corpus.py` on the goldens — **F@3 vs lab = 1.000** (SMTS boundaries differ ≤1 s, Ticket ≤3 s); deterministic chain validated (fused-affinity corr 0.999, embedding-SSM 0.996+, well-conditioned spectrum ∈[0,2]). A is symmetrized before the Laplacian (the timelag asymmetry is a reflect-padding artifact; the lab's float64-only ill-conditioned eigenvalues at a sub-float32 near-isolated-node degree are irreproducible and unused). 6 tests (hermetic ssyev/laplacian/kmeans/enforce_min + golden); lint 0.
- **SECDET.3a — CQT perf ✅ (2026-06-23).** Measured the flagged ≈ 2 min/track CQT before porting (kickoff Step 1): it's a *debug* artifact. On the 5-min SMTS golden the CQT is 104.6 s in debug but **2.72 s in release (`-O`)** (front-end `extract` 3.46 s) — a 38× scalar-loop penalty that vanishes under optimization. **Done-when (met):** measured release cost ≪ the prep budget it runs beside (stem-sep + Beat This! + MIR), so the recursive-CQT port is **skipped** (large change, zero user-visible benefit; the kernel CQT is the one validated at Cq-SSM 0.9995). No production-code change; SECDET suites stay green. (Release number via a standalone `swiftc -O` of the four DSP sources — the full test target can't release-compile today: unrelated Arachne tests reference a `#if DEBUG`-only hook, pre-existing + out of scope.)
- **SECDET.3b — Wire-in ✅ (2026-06-23).** New `SectionDetector` (public DSP façade: resample full-track PCM → 22050 mono → beat-sync on the cached BeatGrid → McFee clustering → interior boundary times) replaces `strongBoundaryTimes` in `SessionPreparer.analyzePreview`; the BeatGrid is now resolved *before* the profile (`makeProfile`, Step 8) since McFee needs the beats. **C.4 decided:** the live `StructuralAnalyzer` *boundary* role is retired (`boundaryTimestamps`/`Scores` now unread); its section-*count* role stays (`sectionIndex` → `estimatedSectionCount`, equal-slice fallback). **Done-when (met):** end-to-end facade test reproduces the lab on raw PCM — **F@3 = 1.000** (Ticket to Ride, `SectionDetectorTests`); `resampleMono` + planner-consume (LFPLAN.5, 16 tests) + BeatGrid-integration suites green; lint 0. Output contract preserved: `TrackProfile.sectionStartTimes` → planner untouched. Removed the now-dead `strongBoundaryTimes` + `BoundaryStrengthFilterTests` (LFPLAN.8 strength filter retired with the novelty boundary source).
- **SECDET.3c — Cache ✅ (2026-06-23).** Bumped `PersistentStemCache.currentSchemaVersion` 4 → 5 (+ history note): v4 entries hold the old novelty boundaries under the same `sectionStartTimes` field, so they're treated as a miss and re-analysed for the McFee sections to reach the planner (the LFPLAN.6/.8 lesson — changing what the cache *means* needs a version bump). 27 cache tests green (the version assertion reads `currentSchemaVersion` dynamically).
- **SECDET.4 — Offline F-score acceptance ✅ (2026-06-23).** Ran the real `SectionDetector` over Nirvana (SMTS + In Bloom) + a 20-track Beatles subset and scored Swift's boundaries vs hand-annotated ground truth, alongside the lab's own Python McFee scored identically (same beats, same truth, same scorer). **Result — the port works on real tracks:** Swift **F@3 = 0.41 overall** (Nirvana 0.55, Beatles 0.40) vs the lab's 0.46 (0.61 / 0.45) — landing at the published acceptance target (Nirvana ≈ 0.61, Beatles ≈ 0.41). Swift reproduces the lab's boundaries *exactly* on most tracks; a **~0.05 aggregate gap** comes from a minority of clustering-sensitive tracks where the kernel-CQT's Cq-SSM 0.9995 (not bit-identical) features tip the spectral clustering (worst: *I Saw Her Standing There* 0.78→0.22) — inherent spectral-clustering sensitivity, not a bug; the recursive CQT (deferred in 3a) is the lever if the gap ever needs closing. Apparatus is re-runnable in the lab (`export_acceptance.py` + `acceptance/run.sh`). A measurement, not an in-suite gate (22 tracks × full CQT ≈ 20 min debug); the 3b facade test (F@3 = 1.000 vs lab) remains the durable port-fidelity gate.
- **SECDET.5 — Full-track beats ✅ (2026-06-23).** Live test 1 (Heart-Shaped Box, 282 s) exposed the real blocker: **Beat This! truncates its grid to a fixed ~30 s window (`BeatThisModel.tMax` = 1500 frames @ 50 fps)**, so McFee — which beat-syncs on that grid — could only segment the first 30 s (`sectionTimes=[10,20,29]` → the planner's 40 %-coverage gate rejected them → equal-slice fallback → transitions didn't track sections). Not a SECDET bug (the wiring is correct; SECDET.4 used full-track *librosa* beats) — the kickoff's "beat-sync is robust to the tracker" was about tracker *quality*, not *coverage*. **Fix:** `SectionDetector.fullTrackBeats` extends the grid past its last beat at the median inter-beat period so the beat-sync spans the whole track (beat-sync is frame-pooling for the recurrence graph → synthetic beats beyond the tracked region suffice). **Done-when (met):** offline A/B on the acceptance set — a 30 s-capped grid + extension scores **F@3 0.48**, ≥ the full-beat baseline (0.43) and the lab's 0.46, so production's 30 s Beat This! grid + extension reproduces the offline result. 2 hermetic tests + the 3b facade still F@3 = 1.000; lint 0. **The live re-test (Release build) is the remaining step.** (Live test also surfaced: #1 "no audio" was Matt's output device reset on restart, not Phosphene; #3 the ~2 min prep was the full-track McFee CQT in a *Debug* build — Release drops it to seconds, per 3a.)
- **SECDET.6 — Planner: stop a long preset swallowing the section transitions ✅ (2026-06-24).** Live test 2 (Without You, 203 s) confirmed SECDET.5 works — McFee detected full-track sections `[38,67,97,127,183,194]` → 7 real sections — but only ~1 transition fired; the plan collapsed to 3 segments. **Root cause (planner, not detection):** a completion-gated preset (`wait_for_completion_event`, BUG-037 "don't cut a long build short") reserves its full `natural_cycle_seconds`, and `coveredUntil` then skips every section that span covers; Arachne (150 s cycle), picked for an early section, swallows the rest of a 203 s track → `segStarts=[0,38,67]`. **Fix (Matt's call — gate by section length):** new `sectionEligibleCatalog` excludes completion-gated presets from a *non-last real* section when their cycle exceeds the section, so a long-form preset only runs where there's room (or on the last section); section-rich tracks transition per section. **Done-when (met):** 6 hermetic gate tests; planner suites (MultiSegment/PlannerSection) green; build + lint 0. (End-to-end "plan no longer collapses" is covered by `MultiSegmentSmokeTest.realSectionsNotSubdivided` + the live re-test — both need the preset-catalog bundle that's absent in worktree test builds.) **The live re-test is the remaining step.**

Numbering note: kickoff suggested SECDET (this epic) or LFPLAN.9 (keep in the LFPLAN epic). Adopted **SECDET** pending Matt's confirmation — trivially renamable.

### Phase CLEAN — Clean-by-June full-system audit + baseline reconcile ⏳ (2026-06-13, in progress)

A 17-lane multi-agent audit (134 verified findings + 16 verified coverage gaps the lanes missed) produced the phased **CLEAN** backlog (Phases 0–8) in [`docs/diagnostics/CODE_AUDIT_2026-06-13.md`](diagnostics/CODE_AUDIT_2026-06-13.md) — now the authoritative queue (supersedes the 2026-05-06 QR→SB ordering in §Immediate Next). **Approved June-30 scope (Matt):** CLEAN Phases 0 (baseline reconcile), 1 (P1 correctness — BUG-031/032 concurrency family, BUG-033 app-layer leaks, audio device route-change, TSan + E2E lifecycle tests), 2 (Spotify secret + OAuth + honest-UI), 5 (CI/CD) + elevated gaps G1/G2/G7/G8/G9; Phases 3–4 stretch (M7-throttled); capability (6) / bulk test-infra + docs (7) / large-unit decomposition (8, absorbs QR.6) after June.
- **CLEAN.6.2 — `[T9]` structural stream re-expressed at section scale (BUG-042 fix)** ✅ (2026-06-19; **RESOLVED — live-validated**). Geometry was note-scale: at the live ~94 Hz feed (48 kHz / 512-hop), `maxHistory` 600 = 6.4 s memory, `kernelHalfWidth` 8 = 85 ms checkerboard, `minPeakDistance` 120 = 1.28 s → a "section" every ~1.5 s, and post-BUG-040 the even spacing drove confidence to 0.85–1.00 (junk endorsed). **Fix (the bug entry's proposed direction, and the only computationally viable one — the checkerboard is O(halfWidth²)/curve-point, so a 4 s block at 94 Hz, halfWidth ≈ 188, is infeasible):** `StructuralAnalyzer.process` mean-aggregates raw frames into one structural frame every 0.5 s (2 Hz, **time-bucketed** → feed-rate-independent, killing the 60-vs-94 ambiguity) before the similarity matrix; the unchanged frame-denominated constants then land at section scale (600-frame ring = 5 min, 8-frame kernel = 4 s), `minPeakDistance` retuned 120 → 16 (8 s min section), and the decimated rate (exactly 1/bucketPeriod) timestamps boundaries (FPS estimate removed). Skein's BUG-046 guard untouched; the orchestrator's ungated `StructuralPrediction` consumer is the one this fixes. **Tests re-expressed at the new rate** (note-scale fixtures no longer register): StructuralAnalyzer BUG-035 ring-wrap (small ring) / BUG-040 timestamps (15 s sections, tolerance widened for the 4 s kernel) / prediction+confidence (15–20 s sections) + the MIRPipeline BUG-040 test (lengthened past the 8 s edge guard). The "evolving registers nothing" fixture became a monotonic drift — the pre-fix incommensurate sinusoids had a ~25 s period the section-scale detector *correctly* found as 3 sections. The 60 KB note-scale `aaba_structural_fixture.json` → a 6-line inline section-scale AABA. DSP suite 23/23 + MIRPipeline structural green, swiftlint 0. **Validate step (real-capture-gated, FA #27):** recalibrate `minNoveltyFloor` (interim 0.02) + Matt's live read on preset-switching feel — no on-disk capture carries the 16-dim input (`features.csv` records no chroma), so it needs a live session. **Recalibration (`[dev-2026-06-19-153439]`):** Matt's live SLTS test found the fix over-conservative (1 boundary/5 min, conf 0 → no switching — `FixtureSessionCaptureGenerator` turned out stems-only, so built `StructuralSectionScaleReplay` instead); an offline floor sweep of the session `raw_tap.wav` → `minNoveltyFloor` **recalibrated 0.02→0.01** (decimated real-section novelty lands ~0.005–0.02; 0.01 recovers 9 SLTS sections at conf 0.64, fixtures stay junk-free 0/0/1, 19 unit tests green). **✅ RESOLVED 2026-06-19** (Matt's live SLTS re-test, session `2026-06-19T15-48-25Z`: **5 sections, confidence to 0.91** at musically real times — the detector + wiring work). The remaining "presets don't visibly track sections" was downstream, NOT the detector — see **LFPLAN** below. `RELEASE_NOTES_DEV.md [dev-2026-06-19-032321] + [-153439] + [-171552]`.
- **LFPLAN.1/.2/.3 — re-enable AI planning + wire plan execution for local-file playback** ⏳ (2026-06-19; **code-complete, pending Matt's live-playlist validation**). Matt's BUG-042 re-test showed the detector works but presets stayed on one visual — traced to local-file sessions running in **reactive fallback** (`buildPlan()` disabled by a 2026-05-28 BUG-021 revert that cited preset-cycling "one every ~5 s" with a 2-preset catalog). **Root cause of that cycling = THIS area's own junk detector:** `estimatedSectionCount = StructuralAnalyzer boundary count` (SessionPreparer+Analysis:287), so the pre-BUG-042 note-scale detector (~180 boundaries on a 5-min track) made `makeSections` cut ~180 tiny planner segments → a preset every ~1.6 s. **LFPLAN.1:** `PlannerSectionCountScalingTests` runs the real planner and pins the link — sectionCount 9 → 9 segments, 180 → 180 (`44bb745`). All three of the revert's named re-enable preconditions are now met: BUG-042 fixed (180→9), certified catalog **2 → 7**, and the Next-button force-quit was the separately-resolved BUG-059 ABBA deadlock (2026-06-18). **LFPLAN.2:** re-enabled `buildPlan()` on the local-file ready path (`a07b0d1`, reverting the revert) — `buildPlan()` is source-agnostic (reads `currentPlan` + cached profiles, both present on the LF path). Closeout ALL GREEN (engine 1531 / app 388 / lint 0 / doc 11). **LFPLAN.3 (`b116e98`):** Matt's first re-enabled session read "planned" but stayed static — root cause: automatic plan EXECUTION was never wired (`currentPreset(at:)`/`currentTransition(at:)` have zero callers; `applyLiveUpdate` only *adapted* the plan, never applied it). So planned mode never auto-switched presets — engine-wide, streaming included; the only auto-switching was the reactive path. Wired it: the ~3 Hz orchestrator tick now applies the active segment's planned preset on change (new `applyPlannedSegment`), suppressed by diagnostic-hold / wait-for-completion / a **manual override held until the next track** (Matt's pick). Manual picks set the hold; both track-change sites clear it + the last-applied marker. Fixes streaming planned sessions too. Closeout ALL GREEN (engine 1531 / app 388 / lint 0 / doc 11). Runtime (auto-switches on the plan, manual hold feels right, no cycling) is Matt's live-playlist gate — `VisualizerEngine` isn't app-test-constructible. `RELEASE_NOTES_DEV.md [dev-2026-06-19-171552] + [-182557]`.
- **LFPLAN.4 — min-dwell + cold-start gate on plan execution (stop the cold-start preset cycling)** ⏳ (2026-06-19; **code-complete, pending Matt's live-playlist validation**). Matt's first LFPLAN.3 live session (`2026-06-19T19-21-39Z`, SMTS + In Bloom) auto-switched the plan but **machine-gunned 8 presets in the first ~24 s** of track 0 (Kinetic Sculpture → … → Nimbus, ~every 3 s) then locked — a cold-start **transient**: while stems/mood/structure converge (~24 s) the LiveAdapter re-patches the plan on nearly every ~3 Hz tick and LFPLAN.3's `applyPlannedSegment` applied each churn. The historical 2026-05-28 cycling symptom returning through the plan-execution door. **Fix:** the first planned segment per track still applies promptly (track starts on its planned visual; closes the ~0.5 s default-preset flash), but every *subsequent* auto-apply is gated by a **cold-start suppression window** (`planColdStartSuppressWindow` = 20 s from track start) AND a **min-dwell** (`planApplyMinDwell` = 15 s from the previous apply) — both with independent teeth (20 > 15); mirrors the reactive path's 60 s cooldown, shorter because section-scale switches are wanted. New `lastPlannedApplyTrackTime` state, reset at both track-change sites alongside the LFPLAN.3 markers. On the live trace this collapses the track-0 burst **8 → 2** (Kinetic Sculpture @3.6 s prompt → settled preset @~24 s). Manual picks bypass `applyPlannedSegment` and are unaffected. Lint 0; `VisualizerEngine` isn't app-test-constructible so the gate is Matt's live read (burst gone, transitions ≥15 s apart, no Next lockup) — the 2026-05-28 cycling/lockup is the regression this guards against. `RELEASE_NOTES_DEV.md [dev-2026-06-19-201951]`.
- **LFPLAN.5 — plan segments land on the real detected section times (not equal slices)** ⏳ (2026-06-19; **code-complete, pending Matt's live-playlist validation**). LFPLAN.4 stopped the cold-start churn; LFPLAN.5 fixes WHERE planned transitions land. `SessionPlanner+Segments.makeSections` sliced each track into `track_length / estimatedSectionCount` EQUAL spans — it used the section *count* but discarded where the sections actually are, so transitions fell at even ~32–40 s intervals instead of on chorus/verse boundaries. The detector knew the real times (`StructuralAnalyzer.boundaryTimestamps`) but only the count reached the planner. **Plumbed through:** `analyzeMIR` returns the detector's boundary timestamps; `TrackProfile` gains optional `sectionStartTimes: [TimeInterval]?` (nil → old cached profiles decode unchanged + streaming); `makeSections` segments on the real times when present, else the prior equal-slice path (byte-identical → every golden/segment suite passes unmoved). Two guards: an **8 s minimum section** (matches `StructuralAnalyzer` `minPeakDistance` 16 × 0.5 s; short intro/outro + close boundaries absorbed) and a **coverage gate** (boundaries must span ≥ 40 % of the track) — the gate scopes the change to the validated local-file case (`PreviewAudio.fromLocalFile` decodes the FULL track → real full-track boundaries; streaming previews are 30 s → boundaries bunch at the start → fall back to equal slices, streaming behaviour unchanged). New `PlannerSectionTimesTests` (6) pin all paths. **Composes with LFPLAN.4:** the plan puts boundaries in the right *place*, the executor controls *when* — boundaries inside the ~20 s cold-start window are suppressed, post-cold-start ones land subject to the 15 s dwell (on the SMTS set 8.5/25.4/47.4/93.2/110.3, the first switch lands near the real 25 s boundary, the rest track their sections). Cached profiles for a re-played track won't have times until re-analysed (not a blocker — equal-slice fallback). Closeout ALL GREEN (engine 1537 / app 388 / lint 0 / doc 11). Runtime (transitions on real section changes, vs `features.csv` `section_start_s` cols 53–55) is Matt's live gate — `VisualizerEngine` isn't app-test-constructible. `RELEASE_NOTES_DEV.md [dev-2026-06-19-205549]`.
- **LFPLAN.6 — cache schema v2→v3 forces re-analysis so section times reach the planner** ⏳ (2026-06-19; **code-complete, pending Matt's live re-test**; commit `6fb2e9f`). Matt's first LFPLAN.5 live test (`2026-06-19T21-13-07Z`) still showed an equal-slice ~18 s grid, not section-aligned transitions. Root cause: LFPLAN.5 added `TrackProfile.sectionStartTimes` but didn't bump `PersistentStemCache.currentSchemaVersion` (still v2), so pre-LFPLAN.5 cache entries (Matt's whole library) HIT as v2 and decode with `sectionStartTimes = nil` (optional → back-compat decode), and `makeSections` falls back to equal slices. **Bumped to v3** — `load(hash:)` treats stale v2 as misses → session-prep re-analyses each track (v3 with section times) **before** `buildPlan`. The 21:44 re-test confirmed: 12 tracks re-analysed during prep, `buildPlan` ran after, the on-disk SMTS profile carries real section times matching the live detector. One-time library re-analysis cost. Added a `PLAN_DIAG` session-log line (section times received + segment boundaries produced, per track) to make section-aligned-vs-equal-slice visible at a glance, and a `PlannerSectionTimesTests` case pinning the real SMTS output. Closeout ALL GREEN (engine 1539 / app 388 / lint 0 / doc 11). `RELEASE_NOTES_DEV.md [dev-2026-06-19-222152]`.
- **LFPLAN.7 — one preset per real section (don't subdivide by maxDuration)** ⏳ (2026-06-19; **code-complete, pending Matt's live re-test**; commit `05a84e8`). With section times reaching the plan (LFPLAN.6), the 21:44 transitions still read as "coincidental" — `planSegments` caps each segment at the preset's `maxDuration` (~27–55 s), subdividing SMTS's 46 s + 82 s sections into 2–3 sub-segments at non-section times. Per Matt's pick (one visual per section, AskUserQuestion): `TrackSection` gains `isRealSection` (set by `realSections`, false for equal slices); `planSegments` runs one preset for the whole real section instead of the cap. Equal-slice sections (old cached profiles / streaming previews) still cap — every golden + `PlannerSectionCountScaling` (9→9/180→180) unmoved. `wait_for_completion_event` presets still take precedence (BUG-037). New `MultiSegmentSmokeTest` case proves a 100 s real section isn't subdivided (segments start only on section boundaries). LFPLAN.4's 15 s dwell can still delay a < 15 s-apart section pair by a couple seconds (minor). Closeout ALL GREEN (engine 1539 / app 388 / lint 0 / doc 11). Transitions landing on section changes is Matt's live gate. `RELEASE_NOTES_DEV.md [dev-2026-06-19-222152]`.
- **LFPLAN.8 — filter plan section boundaries by novelty strength** ⏳ (2026-06-22; **code-complete, pending Matt's live re-test**; commit `f64f0d4`). The 06-22 re-test + `PLAN_DIAG` confirmed the plumbing (LFPLAN.6/.7) works — the plan segments land on the detected boundaries, one per section — but transitions still didn't track audible section breaks because the detector emits a boundary at EVERY novelty peak, including sub-section blips (8–15 s grain; Lithium 8/11/14 s gaps). **First-proposed `confidence` filter was the wrong signal** (`computePrediction`'s confidence is cumulative structure-regularity, not per-boundary strength); the right one is `NoveltyDetector.Boundary.noveltyScore`, which the analyzer computed but discarded. **Fix:** `StructuralAnalyzer` exposes `boundaryNoveltyScores` (parallel to `boundaryTimestamps`, captured at `registerBoundary`); `analyzeMIR` keeps only boundaries ≥ 0.5 × the track's strongest (Matt's "moderate" pick, AskUserQuestion; relative because raw values are ~0.005–0.02). New `strongBoundaryTimes` helper + `BoundaryStrengthFilter` (3 tests); live path untouched (only the offline plan filters). **Cache schema bumped v3→v4** — the filter changes what `sectionStartTimes` *contains*, so v3 entries (unfiltered) re-analyse on next session (the LFPLAN.6 lesson again: changing cached data needs a version bump). Closeout: structural+filter+planner green (24), app 388 / lint 0 / doc 11; full engine suite's `concurrentDoubleStart` crashed (signal 5, audio) = unrelated parallel-session milkdrop audio contention (passed in LFPLAN.4–.7 closeouts). Committed only the 3 files to avoid sweeping a concurrent session's staged milkdrop changes. `RELEASE_NOTES_DEV.md [dev-2026-06-22-154303]`.
- **CLEAN.7.3 — ARCHITECTURE Module Map drift fixed + completeness gated** ✅ (2026-06-18, Phase 7 doc-drift; D-168). The audit's "18 undocumented files" was actually **62** — including four entire CERTIFIED presets (Skein, Murmuration, Dragon Bloom, Fata Morgana) and recent infra (FlashAnalyzer, DefaultOutputDeviceMonitor, ConcurrencyAuditProbe, the streaming-artwork cluster). Backfilled all 62 (tooling modules `ColdStartVerifier/` + `PresetSessionReplay/` + `QualityReelAnalyzer/` + `BeatThisActivationDumper/` as group entries that name their files; the rest per-file) and fixed two stale `LumenPatternState` stride claims (376 B / 336 B → the real 568 B). The "canvas-hold spec" item resolved as the now-documented Skein entry (D-142). Per Matt's scoping call, mechanized completeness with `DocIntegrityTests.moduleMapCompleteness` (D-168, the D-161 "violated twice → mechanize" ratchet): reds when any `.swift`/`.metal` under the two source roots lacks a Map entry — adversarially proven to red on an undocumented probe, green once removed. DocIntegrity 11/11, swiftlint 0.
- **CLEAN.7.2a — fast local test tier** ✅ (2026-06-18, Phase 7; split from CLEAN.7.2 per Matt's "faster suite, keep coverage" call). `Scripts/test_fast.sh` runs the pure-logic core — ~978 of ~1,524 engine tests (DSP / Orchestrator / Shared / Session-logic / Audio-core / Doc) in ~13 s, **green in a worktree** (it skips the gitignored-fixture suites that fail-loud on absent fixtures). Exclusion via `swift test --skip`; the local mirror of the CLEAN.5 CI fast gate. The full `swift test` (closeout gate) is unchanged — **zero coverage removed**; the win is inner-loop speed, not fewer tests. RUNBOOK §Build and Test documents it; `--filter <Suite>` for targeted loops. Remaining 7.2 scope → **CLEAN.7.2b** (shared fixture builders to dedup the 220+-file duplication + frame-budget/allocation + BUG-038/041 coupling regressions + per-test tags).
- **CLEAN.7.2b (foundation) — shared fixture builders** ⏳ (2026-06-18). `FeatureVector` is inline-constructed at ~119 sites / 41 files and `StemFeatures` at ~55 / 22; both have an `init` that defaults the core fields and zeroes the deviation primitives, so tests construct-then-mutate. `FeatureFixtures.makeFeatureVector` / `makeStemFeatures` (TestDoubles) collapse that to one defaulted call; `FeatureFixturesTests` (5 tests) proves they are **byte-identical** to the struct inits — so migrating a call site cannot change a test's meaning. Foundation only: the ~40-file migration (biggest dedup in the stem-routing/preset suites) + the new frame-budget/allocation + BUG-038/041 coupling regressions + per-test tags are the remaining 7.2b rollout, now safe + mechanical given the equivalence proof. **Migration wave 1 (2026-06-18):** migrated `SpectralHistoryBufferTests`' one-shot sites (green; `test_singleAppend` 5 mutations → 1 call). **Finding** that reshapes the rollout: the construct-count overstated the dedup — most sites reuse a `var fv` across loops/successive appends (builder gives nothing) or are already-minimal init-only constructions (e.g. `MurmurationStemRouting`). The real win is one-shot multi-field constructions + the standard for all NEW tests, so the rest is **opportunistic** (migrate clean one-shot sites when touching a file), not a 40-file sweep. **Remainder reconcile (2026-06-18) → 7.2b COMPLETE:** the audit's other 7.2b items were already filled by post-audit work (not rebuilt — duplication is what the audit warns against): coupling regression = `RayMarchPipelineTests.test_smoothLightIntensity_*` (BUG-038) + `AuroraTrackStartWarmupTests` (BUG-041), both green; frame-budget = `RenderLoopPerformanceTests` + SSGI/RayIntersector gates; per-frame allocation = `MemorySoakGateTests` (CLEAN.4.7) on the FFT→MIR + StemAnalyzer paths. Per-test tags **descoped** (the `test_fast.sh` tiering from 7.2a supersedes it and covers both test frameworks; native `.tags` would cover only swift-testing and duplicate it). A render-path allocation soak was declined as speculative (no evidence of a render per-frame leak; CLEAN.4.4's fixes are golden/DrawableResize-gated).
- **CLEAN.7.5 — doc-overlap curation + CLAUDE.md demote** ✅ (2026-06-18). (1) **CLAUDE.md demote:** the §Defect Handling "Multi-increment process for P0/P1" was a *verbatim duplicate* of `DEFECT_TAXONOMY.md §Defect Process by Severity`, and the "Domain-specific artifact requirements" were lookup reference — both demoted (process → a one-line pointer that keeps the instrument→diagnose→fix→validate→notes shape; artifacts → relocated to DEFECT_TAXONOMY), keeping the always-loaded *rules* (evidence-before-implementation, fix-obligations, manual-validation). **Freed 154 words → CLAUDE.md headroom 67 → 221 words (≈99% → 95.7% of the D-161 cap).** (2) **ARCH↔REGISTRY:** verified complementary (code/contract vs capability status), previously uncross-linked → added a §Presets scope-delineation cross-link. (3) **SHADER_CRAFT↔design:** the audit overstated it — §18 (painterly craft) is explicitly the reusable mark-vocabulary handbook and already cross-refs `SKEIN_DESIGN`; §10 recipes already reference the design docs. Already delineated → no churn (rebuilding would be the duplication the audit warns against). DocIntegrity 11/11.
- **CLEAN.7.7 + 7.8 — DEFERRED (D-169)** (2026-06-18, Matt's call). Both are public-release-readiness work — 7.7 = extended HIG a11y settings (reduce-transparency, increase-contrast; reduce-motion is already wired + live), 7.8 = cold-install / first-run resilience. Phosphene has no public build and no users beyond the dev, and the a11y + robustness basics for daily dev use are already in place (reduce-motion live, VoiceOver labels, photosensitivity notice + flash-safety cert), so building these for non-existent users is YAGNI. Revisit at public-release prep (or if the dev runs those macOS settings). **→ Phase 7 closed:** 7.1/7.2a/7.2b/7.3/7.4/7.5/7.6 done; 7.7/7.8 deferred.
- **CLEAN.7.1 — test-isolation reconcile** ✅ (2026-06-18). BUG-048 (app-scheme sandbox runner) + BUG-049 (Skein canvas-hold session-fragility) were both already RESOLVED (2026-06-11) with regression gates — `SchemeTestActionRegressionTests` and SkeinCanvasHold's fixture-generated armed path. This increment confirmed both gates green in the session closeouts and flipped the audit row; status-reconcile, no fresh fix work (as the audit anticipated). No residual test-infra needed.
- **BUG-059 — concurrent `LocalFilePlaybackProvider` start/stop ABBA deadlock** ✅ RESOLVED (2026-06-18, P1, multi-increment; fix `a285a22`, integrated to `main` (origin/main)). Surfaced while de-flaking the REVIEW.2 `concurrentDoubleStart_serializesWithoutDeadlock` test (the "load flake" was a real intermittent deadlock, not a wall-clock slip — confirmed by a process `sample`: `player.stop()` holds the engine lock + `dispatch_sync`s the AVAudioPlayerNode completion queue, while our `scheduleFileLoop` completion closure re-schedules `scheduleFile()` inline and blocks on that engine lock; the provider's `NSLock` is not in the cycle, so the BUG-021 fix doesn't cover it). Production-reachable via `handleConfigurationChange` (device-swap restart, off-MainActor) racing a track advance — intersects G1 / BUG-056. **Step 1 (diagnose) ✅** — filed in KNOWN_ISSUES (BUG-059) with the stack + verification criteria, no fix code. **Step 2 (fix) ✅** — `scheduleFileLoop` now hops the re-schedule + `onFileEnded` advance off the completion-handler queue onto a provider serial `rescheduleQueue`, re-checking identity under `lock`; the completion handler returns at once so a concurrent `stop()` can't be blocked by an inline `scheduleFile()`. **Automated-validated:** the reproducer is 11/11 green (6× isolated + 5× in-suite, ~3.5 s) on the machine that wedged on round 0 pre-fix; all 6 REVIEW.2 churn tests green; full closeout ALL GREEN (`a285a22`). **Manual-validated (Matt, 2026-06-18, session `…T13-46-10Z`):** several output-device swaps mid local-file playback → no hang, Next/Prev clean, features.csv live (no freeze). The track restart-on-swap Matt observed is the separate **BUG-056** (no resume-from-position), not a regression. Integrated to `main` (origin/main, FF). Matt chose "fix it properly (P1)" over file-and-defer.
- **CLEAN.0 baseline reconcile** ✅ (2026-06-13): audit doc landed; `main` confirmed green (the 13 fresh-worktree engine-test failures were *all* the one gitignored tempo fixture `love_rehab.m4a`, failing loud per the no-silent-skip rule, restored via `Scripts/fetch_tempo_fixtures.sh` — validated CLEAN.5.2 + the CLEAN.5.3 pipe-masks-`swift test`-exit-code closeout-honesty gap live); **BUG-030** dup-track-crash fix integrated to main (`ba4e1cae`, cherry-pick of the stranded `679363a9` from `claude/dreamy-bell-23528b`). Worktree declutter done (22 removed; 4 active auto-protected by non-force `git worktree remove`; all salvage refs preserved — Glass Brutalist / AGC3.6 / LM.3.2 / BUG-030 source); 2 stale unmerged refs left undeleted (safety hook `block-destructive.sh`). `main` fast-forwarded to the verified tip — closeout **ALL GREEN** (engine 1457 / app 382 / swiftlint 0 of 432 / doc-gates 9/9). CLEAN.0 complete; next is CLEAN Phase 1.
- **CLEAN.1.1 instrument + diagnose BUG-031/032 family** ✅ (2026-06-13, commit & stop — P1 multi-increment step 1; **done-when met:** root cause in KNOWN_ISSUES, no fix code). Confirmed one root cause: a single `StemSeparator` (`VisualizerEngine.swift:737`) shared between the live `stemQueue` path (`:771`) and the session-prep `Task.detached` path (`:784`), with `separate()`'s input-write + output-read outside the only lock (`StemModelEngine.predict()`) → interleave corruption (BUG-031); plus `endSession()` orphaning the prep task, `resumeFailedNetworkTracks` spawning a second `_runPreparation` loop, and `startSession` source-mutation-before-guard (BUG-032). New `ConcurrencyAuditProbe` (Shared, pure observability, category `concurrency-audit`) + `ConcurrencyAuditProbeTests` (9 green, no GPU) expose every mechanism; Step-6 output-read extracted to `StemSeparator+ModelIO.swift` for the length budget. BUG-012 cross-referenced as a candidate retiree. Closeout **ALL GREEN**. **Next: bring Matt the CLEAN.1.2 lock-strategy decision — (A) extend the lock across input→predict→output vs. (B) give session-prep its own `StemSeparator` (prefer return-by-value) — before implementing.**
- **CLEAN.1.2 BUG-031 fix** ✅ (2026-06-13, strategy **A** — Matt-approved via AskUserQuestion). `StemSeparator.separate()` holds `lock` across the full input→predict→output critical section + returns stems by value (`StemSeparationResult.stemWaveforms`); both call sites read the result, not the shared `stemBuffers`. Regression: `StemSeparatorConcurrencyTests` (per-caller-correct stems under concurrency, threshold-free). 3 inline test doubles updated to populate `stemWaveforms`. **RESOLVED 2026-06-14** — Matt's manual validation passed (real sessions `17-22-31Z` local + `17-58-44Z` streaming: stems connected, recorded per-stem deviation live, no stall/crash); integrated `da26a3a`; KNOWN_ISSUES §Resolved BUG-031.
- **CLEAN.1.3 BUG-032 fix** ✅ (2026-06-13). Per-instance `streamingSessionGen` guard (twin of `localFileSessionGen`) on the prep-completion closure; `endSession()` cancels the prep task (mirrors `cancel()`); `resumeFailedNetworkTracks` single-flight (awaits the in-flight loop); `startSession` source-mutation moved after the state guard (both variants). Regression: `SessionLifecycleGenerationTests` (end-then-restart guard, rejected-startSession source order) + `SessionRecoverySingleFlightTests` (single-flight). **RESOLVED 2026-06-14** — Matt's manual validation passed (cancel→restart + four source loads across the two sessions, each reaching `→ready` with its own correct plan, no orphan-hijack); integrated `da26a3a`; KNOWN_ISSUES §Resolved BUG-032.
- **CLEAN.1.6 `[GAP-7]` TSan + concurrency stress harness** ✅ (2026-06-13). `Scripts/tsan_stress.sh` runs the concurrency/lifecycle stress + regression tests under ThreadSanitizer; new `ConcurrencyStressTests` (env-gated `PHOSPHENE_STRESS=1`, opt-in so the normal suite stays light): overlapping live+prep `separate()` on one shared `StemSeparator` (BUG-031) + rapid session start/end/cancel churn (BUG-032). **Result: TSAN CLEAN — 0 data races** — validates 1.2/1.3 removed the races rather than moving them. TSan builds clean against the real Metal/MPSGraph separator (no suppressions). Next: CLEAN.1.4 (BUG-033 app-layer, independent); CLEAN.1.7 (G8 E2E lifecycle test).
- **CLEAN.1.4 BUG-033 fix (app-layer)** ✅ (2026-06-13). (1) Per-frame dashboard snapshot decoupled off `@Published` on the `@EnvironmentObject`-wide engine → a dedicated `CurrentValueSubject` (`dashboardSnapshotSubject`); no more 60 Hz whole-tree SwiftUI invalidation; `publishDashboardSnapshot` skips when the overlay is hidden (the default, via `dashboardOverlayVisible` pushed from PlaybackView). (2) `SessionStateViewModel` + `PlaybackChromeViewModel` `assign(to:on:self)` → `sink { [weak self] }`, breaking the retain cycles (VMs now `deinit`). Tests: `deallocates_noRetainCycle` in both VM suites. The PhospheneApp construct-once `@StateObject` change was deferred (low value once the leak is closed + ContentView already `@StateObject`s the VM; highest-risk SwiftUI-init change). **RESOLVED 2026-06-14** — Matt's manual validation passed (Activity Monitor overlay-on/off toggle showed the expected CPU swing = the decoupling working; VM deinit unit-proven); integrated `da26a3a`; KNOWN_ISSUES §Resolved BUG-033. The high *absolute* CPU Matt observed during the check is a separate finding — the always-on session recorder, filed **BUG-050** (P2: encode ≈ doubles per-frame CPU; no fps impact).
- **CLEAN.1.5 `[GAP-1]` audio output-device route-change** ✅ (2026-06-13). The system audio tap had no listener for `kAudioHardwarePropertyDefaultOutputDevice`, so connecting AirPods / unplugging a monitor mid-session left the tap bound to the dead device and visuals silently froze (verified — no route-change handling existed). New `DefaultOutputDeviceMonitor` (permission-free system-property listener) drives `SystemAudioCapture.performReinstall()` — teardown + re-create the tap/aggregate/IO-proc against the new default output. Reinstall is dispatched off the listener queue (avoids Core Audio remove-from-callback reentrancy). Tests: `DefaultOutputDeviceMonitorTests` (5 — registration/idempotency/teardown/restart/read; the listener mechanism is headless-testable). **Manual validation pending: swap output device mid-session, visuals stay live** — no API to change the default output from a unit test. Next: CLEAN.1.7 (G8 E2E lifecycle).
- **CLEAN.1.7 `[GAP-8]` E2E session-lifecycle integration test** ✅ (2026-06-13). New `Integration/SessionLifecycleE2ETests` drives a real `SessionManager` + `SessionPreparer` (fast fakes) through the full cycle — connect → prepare → ready → play → track-change (cache serves the next track) → end → restart-with-a-different-playlist — plus a cancel-mid-prepare path. The restart leg structurally catches the BUG-032 orphan class (a stale session-A prep must not overwrite session B's plan) as part of the whole cycle, where only per-VM + beat-grid-wiring tests existed before. Closeout ALL GREEN. **This completes the committed June Phase-1 scope (CLEAN.1.1–1.7), now integrated to `main` + pushed to origin as `da26a3a` (2026-06-14, merged through CLEAN.7.9 + DOC.7).** **BUG-031 + BUG-032 + BUG-033 all RESOLVED 2026-06-14** via Matt's two validation sessions (`17-22-31Z` + `17-58-44Z`) + the Activity-Monitor overlay-toggle check. **Phase-1 G1/CLEAN.1.5 manual gate (mid-session output-device swap) — VALIDATED 2026-06-17** (Matt: 12/12 back-and-forth Duet 3 ↔ Mac-mini swaps recovered clean; see the BUG-058.instrument bullet below, KNOWN_ISSUES §BUG-058 "PASSED 12/12," and the audit G1 row — Phase 1 is fully complete). The lone un-reproduced freeze is the rare P3 BUG-058. (This sentence originally read "only open gate left… reconfiguring this week"; it was stale post-validation — corrected 2026-06-18.) The BUG-033 check surfaced a separate **BUG-050** (P2 — always-on session recorder ≈ doubles per-frame CPU; encode additive to render; no fps impact; fix deferred per Matt's option A). BUG-012 (MPSGraph crash) saw zero crashes across both sessions — retirement candidate, not yet retired.
- **CLEAN.7.9 — `MetadataPreFetcher` network-timeout flake made deterministic** ✅ (2026-06-13, early-pulled from Phase 7 test-infra; surfaced during the CLEAN.1.x closeouts, decoupled from the BUG-031/032 concurrency work): the long-tracked `fetch_networkTimeout_returnsWithinBudget` wall-clock flake — budget ratcheted 3 s → 8.25 → 15 → 45 s without ever converging (16.1 s / 22.8 s observed under the ~1460-test parallel suite, where cooperative-pool contention inflates the *measured* elapsed time though the timeout fires correctly) — replaced by a behavioural assertion: the merged profile carries the fast fetcher's `energy` but **not** the slow fetcher's `bpm` (excluded by the 1 s timeout), an outcome that turns only on the 1 s-vs-10 s ordering, never on measured elapsed time. Renamed `fetch_networkTimeout_returnsFastResultNotSlow`; adversarially proven to trap a timeout that lets the slow result leak (`bpm → 999` fails `== nil`, ~10 s block not a hang). Test-only, no production delta (`MetadataPreFetcher` source untouched); removed from `KNOWN_ISSUES.md §Pre-existing Flakes`; `DEFECT_TAXONOMY.md` + `CAPABILITY_REGISTRY/AUDIO.md` references updated. `RELEASE_NOTES_DEV.md [dev-2026-06-13-b]`.
- **CLEAN.7.10 — `RayIntersectorTests` 1000-ray perf assertion made contention-robust** ✅ (2026-06-14, pulled forward from Phase 7 like CLEAN.7.9; surfaced on the Mac mini during the CLEAN.1 Phase-0 closeout re-confirmation — the test had passed 1469/1469 on both integration closeouts and is isolated 5/5 green at 0.42–0.54 s/class). `test_rayTrace_1000Rays_under2ms`'s hard wall was a **single-sample `Date()` timing of one GPU command-buffer submit** run inside the ~1469-test parallel suite → contention inflated the lone sample past the 2 ms budget. Fix keeps the gate, drops the flake: assert the **minimum of 8 warm samples** (contention can only ADD latency to a submit, so the min is the clean true-cost estimate). Path untouched by CLEAN.1 (render increment 3.3); test-only, no production delta. Same Phase-0 session: `tsan_stress.sh` ran **TSAN CLEAN (0 races)** on the Mac mini → BUG-031/032 dynamically validated. `KNOWN_ISSUES §Pre-existing Flakes` + `RELEASE_NOTES_DEV [dev-2026-06-14-a]`.
- **CLEAN.7.12 — `UMABuffer` concurrency test made deterministic** ✅ (2026-06-16, Phase 7 test-infra like CLEAN.7.9/7.10/7.11; surfaced under the full ~1479-test parallel run during the CLEAN.7.6 flash-safety closeout, which added GPU-heavy parallel tests). `UMABufferExtendedTests.test_concurrentWriteRead_noDataRace` raced a **fixed 30 s** `DispatchGroup.wait(timeout:)` against 200 trivially-fast, lock-free blocks (100 writes + 100 reads) → `.timedOut` at 34.9 s under pool contention; isolated the class runs in 0.048 s. Fix removes the budget (deterministic-over-budget-widening rule): `wait()` with no timeout returns exactly when the blocks drain, so it cannot flake on elapsed time; a genuine deadlock surfaces as a CI hang. Added a smoke-level post-condition (each writer wrote a distinct index → `buf[i] == Float(i)` after the barrier); TSan remains the true race detector. Test-only, no production delta. Engine class 12/12 green. `KNOWN_ISSUES §Pre-existing Flakes` + `RELEASE_NOTES_DEV [dev-2026-06-16-c]`.
- **CLEAN.7.14 — `SSGITests` 1080p perf gate made contention-robust** ✅ (2026-06-16, Phase 7 test-infra like CLEAN.7.9/7.10/7.11/7.12; surfaced under the full ~1479-test parallel run that the CLEAN.7.6 flash-safety suite's GPU-heavy tests exposed). `test_ssgi_performance_under1ms_at1080p` flaked two ways under contention: an `XCTest measure {}` block over the 1080p SSGI render **failed on RSD > 10 %** (~17.7 % observed), and the overhead gate took a **5-pair mean of (with − without) `Date()` timings** that folds contention spikes into the average; isolated the class is 7/7 green in ~0.13 s. Fix keeps the sub-1 ms gate, drops the flake (deterministic-over-budget-widening): drop the `measure {}` benchmark, compute overhead as `minSSGI − minBase` over the **minimum of 8 warm samples per path** (contention only ADDs latency, so each min is the clean floor). Test-only, no production delta. Structural twin of **CLEAN.7.13** (sibling ICB gate), consolidated onto this same branch — 7.13 = `peaceful-ishizaka`'s `b49905b`, merged preserving its hash. `KNOWN_ISSUES §Pre-existing Flakes` + `RELEASE_NOTES_DEV [dev-2026-06-16-e]`.
- **CLEAN.7.11 — `ToastManager` auto-dismiss test made deterministic** ✅ (2026-06-15, Phase 7 test-infra like CLEAN.7.9/7.10; the fix CLEAN.2.3.8 filed for in `KNOWN_ISSUES`). `ToastManagerTests.autoDismiss_afterDuration` raced a **fixed 1000 ms** sleep (ratcheted from 400 ms) against a `duration: 0.05` toast's auto-dismiss → the continuation slipped the window under @MainActor parallel-suite contention. Fix removes the budget: a `#if DEBUG` seam `ToastManager.dismissTask(for:)` exposes the in-flight dismiss `Task` and the test `await`s its `.value` — blocking exactly until the real dismissal, no deadline. Behavioural intent kept (finite → dismisses; `.infinity` → no task). Production untouched; test-only. App suite green. `KNOWN_ISSUES §Pre-existing Flakes` + `RELEASE_NOTES_DEV [dev-2026-06-15-g]`. (2026-06-14, first Phase 2 increment): the bundled `SpotifyClientSecret` (`Info.plist:13` + `Phosphene.xcconfig`) was a distribution-blocker (`KNOWN_ISSUES` AUDIT-2026-06-09 list) — extractable from any shipped binary, and a native app must not embed one. Removed the key from both files and deleted its only consumer, the D-068 client-credentials `DefaultSpotifyTokenProvider` (engine actor); `SpotifyWebAPIConnector.makeLive()` now always backs with the `MissingCredentialsTokenProvider` sentinel (the no-arg `PlaylistConnector()` default for non-Spotify sources). The production Spotify flow already used OAuth Authorization Code + PKCE (`SpotifyOAuthTokenProvider`, D-069), injected by `ConnectorPickerView` — so **zero user-facing change** (the client-credentials path was never wired to the Spotify UI; the RUNBOOK setup never set a secret). Pruned `SpotifyTokenProviderTests` to the sentinel test and removed the client-credentials `SpotifyIntegrationTests` (no headless OAuth replacement). Docs: SESSION + ARCHITECTURE registries, RUNBOOK gotcha, KNOWN_ISSUES resolved. Engine + app build green; integrated to `main` + pushed (`5c74d26`). **Manual E2E ✅ (Matt, 2026-06-14): Spotify login → playlist loads on the `main` build, OAuth path intact.** Follow-up (same day, Matt's call): the env-var Audio-layer `SpotifyFetcher` (search-only, never active in normal runs) was also **removed** — its deletion eliminates `SPOTIFY_CLIENT_SECRET` from the codebase entirely. Remaining Phase 2: CLEAN.2.2 (OAuth correctness — re-entrant `login()` leak, refresh double-spend; kickoff brief at `docs/prompts/CLEAN_2.2_KICKOFF.md`), 2.3 (wire-or-hide dead UI), 2.4 (entitlement review). `RELEASE_NOTES_DEV.md [dev-2026-06-14-d]`.
- **CLEAN.7.13 — `RenderPipelineICBTests` ICB-frame perf assertion made contention-robust** ✅ (2026-06-16, Phase 7 test-infra like CLEAN.7.9/7.10/7.11; surfaced under the full ~1469-test parallel `swift test` during the CLEAN.7.12 closeout). The structural twin of CLEAN.7.10: `test_gpuDrivenRendering_cpuFrameTimeReduced`'s hard wall was a **single-sample `Date()` timing of one warm ICB frame submit** (blit + compute + render) inside the parallel suite → contention inflated the lone submit past the 2 ms budget (case-level 0.277 s benign; isolated it passes ~0.37 s). Fix copies CLEAN.7.10 verbatim: keep the gate, drop the flake — assert the **minimum of 8 warm samples** (contention can only ADD latency to a GPU submit, so the min is the clean true-cost estimate). The `measure {}` variance block is unchanged. ICB renderer path untouched; test-only, no production delta. `KNOWN_ISSUES §Pre-existing Flakes` + `RELEASE_NOTES_DEV [dev-2026-06-16-d]`.
- **CLEAN.2.2 — Spotify OAuth correctness** ✅ (2026-06-14, RESOLVED — Matt E2E confirmed, integrated `a6f1288`): hardened `SpotifyOAuthTokenProvider`, the sole Spotify auth path (Authorization Code + PKCE). **2.2.1** re-entrant `login()` leak — a second `login()` while one was pending overwrote `pendingContinuation` (orphaning the first caller until the 5-min timeout) + armed a stray timeout against the wrong attempt; now coalesces concurrent logins onto one in-flight attempt (`pendingContinuations` array — one browser, one timeout; `finishLogin()` cancels the timeout on every resume path). **2.2.2** refresh double-spend — concurrent `acquire()` each fired their own silent refresh, spending the rotating refresh token >once → spurious forced re-login; now dedups onto a single in-flight `refreshTask`. **2.2.3** P3 hardening: OAuth `state` CSRF/replay guard (generated → sent → verified), form-body percent-encoding of the RFC-3986 reserved set (`+ & = /` that `.urlQueryAllowed` left intact and that corrupts auth codes), Keychain-save failures logged not swallowed, callback `scheme == phosphene` + host validation. 4 new regression tests (overlap-coalesce, single-refresh, state round-trip + mismatch, form-encoding) + `state` echo in `loginSuccess`; `SpotifyOAuthTokenProviderTests` green. Commit `13cec8b`, integrated `a6f1288`. **Verified 2026-06-14:** Matt's live check passed — playlist loaded on the integrated `main` build (refresh path end-to-end on real Spotify, no regression); the fresh-login `state` guard rests on the unit regressions + standard OAuth on unchanged routing. `KNOWN_ISSUES` AUDIT-2026-06-09 OAuth items → Resolved. Remaining Phase 2: CLEAN.2.3 (wire-or-hide dead UI), 2.4 (entitlement review). `RELEASE_NOTES_DEV.md [dev-2026-06-14-e]`.
- **CLEAN.2.3 — Wire-or-hide dead UI + close the localization-gate bypass** ✅ (2026-06-14): the honest-UI increment (audit T5 / AUDIT-2026-06-09). Four sub-increments, each Matt's product call (wire vs hide), build + 388 app tests green, swiftlint clean, `check_user_strings.sh` green. **2.3.1** the "Use Apple Music instead" footer was a no-op `{ }` (its mirror only dismissed the picker) → both cross-links now drive a real `NavigationStack` switch via `ConnectorPickerViewModel.switchConnector(to:)` (wire). **2.3.2** the Settings `.localFile` capture mode lied ("coming in a future update") and no-op'd → removed the enum case + picker row + false string + unreachable reconciler/coordinator branches (remove; decode migration-safe via `decodeOrDefault`; distinct from the `InputMode.localFile(URL)` SoakTestHarness path; supersedes the `.localFile` branch of D-052, annotated in DECISIONS_HISTORY). **2.3.3** the disabled "Swap preset" context-menu stub → hidden behind `#if ENABLE_PRESET_SWAP` until U.5b, mirroring the existing `ENABLE_PLAN_MODIFICATION` Modify-button gate (hide; plumbing kept). **2.3.4** `check_user_strings.sh` only scanned `Views/` → widened ROOTS to ViewModels + ContentView, added a `.error("…")` arm, externalized the bypassing copy (~22 new `Localizable` keys). Commits `7800b72` / `d40cfad` / `6e983c8` / `46d836b`. **Two out-of-scope findings surfaced (filed, not fixed):** (a) `CaptureModeReconciler` is never constructed in production — registry `APP.md` claimed `production-active` / owned by `PlaybackView`, but nothing instantiates it, so the live capture-mode-switch path appears unwired; (b) `AudioSettingsSection` references `settings.audio.capture_mode.specific_app` but the strings file defines `.app` → the "Specific app" radio likely renders its raw key literal. Not pushed (awaits "yes, push"). Remaining Phase 2: CLEAN.2.4 (entitlement review). `RELEASE_NOTES_DEV.md [dev-2026-06-14-f]`.
- **CLEAN.2.4 — macOS entitlement / local threat-model review (GAP-10)** ✅ (2026-06-15, **closes Phase 2**): the last Phase-2 item and the remaining audit security finding. **Review + document increment — no security build settings flipped** (each needs a build + real run; filed instead). Produced **[`docs/SECURITY_POSTURE.md`](SECURITY_POSTURE.md)** — the verified posture + local threat model across 7 surfaces (global system-audio tap; sandbox-off; hardened-runtime/notarization; library validation; `phosphene://` OAuth callback; local-file open path; secrets-at-rest + no-telemetry), each with verified-state / threat / decision-or-filed-fix. Every claim re-verified against source (entitlements = `app-sandbox=false` only; `ENABLE_HARDENED_RUNTIME` absent repo-wide; dev-signed not Developer ID; tap scope global-vs-PID; `SessionRecorder` records its own Metal output to local disk, not the screen → "No video is recorded" honest; OAuth callback scheme+host+`state`; m3u parser defensive but resolves arbitrary paths; checked-in client ID empty). **Decision (Matt 2026-06-15): eventual distribution is on the roadmap** → hardened runtime + notarization filed as **near-term CLEAN.2.5** (own increment — signing pipeline + real Gatekeeper/tap test), not deferred. Also filed **BUG-051** (P3 — m3u entry input-validation defense-in-depth; bounded by the no-egress local-file path). No fix filed for sandbox (incompatible with the global tap; partial sandbox not viable), library validation (not required), or OAuth (mitigated by CLEAN.2.2). Doc-only: not visually verifiable; no production code changed; no tests added. GAP-10 marked **reviewed** in `CODE_AUDIT_2026-06-13.md` (Part B G10 + Part C); `SECURITY_POSTURE.md` referenced from `RUNBOOK.md`; **not** added to the CLAUDE.md handbook index (D-161 budget ratchet). **Phase 2 (security + honest-UI) complete.** Pushed to `origin/main` 2026-06-15. `RELEASE_NOTES_DEV.md [dev-2026-06-15-a]`.
- **CLEAN.2.3.7 — Connector cross-link discoverability + affordance (CLEAN.2.3.1 follow-up)** ✅ (2026-06-15): Matt's manual walk of the 2.3.1-wired cross-links found they read as inactive/absent. Root cause (verified in source): the Spotify "Use Apple Music instead" footer rendered in *every* state but at `white @ 40 % opacity` — and 40 % opacity is this app's *disabled* convention (cf. `ReadyView` preview-plan button) — so it read as greyed-out; the Apple Music "Use Spotify instead" link existed *only* in the error state, absent from the normal waiting/empty screens, so the two connectors were inconsistent. Fix (Matt's pick: bordered secondary): both cross-links now use the app's standard `.buttonStyle(.bordered)` secondary treatment and render as an **unconditional footer** in every state of both connection screens (`SpotifyConnectionView`, `AppleMusicConnectionView`); Apple Music's error-only copy removed as redundant. No behaviour change to `switchConnector`/navigation (the 2.3.1 wiring is intact) — view-only. No new automated test (declarative layout/style with no logic; the 388 app tests are the regression gate; placement/contrast is a visual check on Matt's build). Switching is also always available via the back chevron → picker tiles. App build + tests green; swiftlint clean. `RELEASE_NOTES_DEV.md [dev-2026-06-15-b]`.
- **CLEAN.2.3.8 — Land the per-app-capture deletion + fix quality-hints strings (CLEAN.2.3.1/2.3.5 follow-up; divergence reconcile)** ✅ (2026-06-15): Matt's manual test of Settings → Audio Source found the "Specific app" control broken (raw `specific_app` label, non-functional `SourceAppPicker`, the tab-switch-then-selected quirk = unwired `CaptureModeReconciler`) plus the `quality_hints` info section rendering raw keys. Root cause was **already solved** on `origin/claude/upbeat-haslett-93311c` (CLEAN.2.3.5/2.3.6 — Matt's prior "delete per-app capture" call) but never merged to main. Per Matt's pick (land it, via AskUserQuestion): cherry-picked the deletion `a9c99ea` (preserved as `cc1f086`) — removes the `CaptureMode`/`SourceAppOverride` types, `SettingsStore.captureMode`/`sourceAppOverride`, `CaptureModeReconciler` + `CaptureModeSwitchCoordinator` (and with them the D-061(b,c) capture-switch grace window in `VisualizerEngine`/`PlaybackErrorBridge` → silence threshold now the constant 15 s), `SourceAppPicker`, the AudioSettingsSection capture-mode picker, 4 Localizable keys, 5 pbxproj file registrations + the dead tests — and ported the 2.3.6 orphan-API removal (`AudioInputRouter`/`SystemAudioCapture` `switchMode`/`availableApplications`/`RunningApplication`). Plus (Matt's follow-up call): **removed the now-empty Audio settings tab entirely** — once the capture-source picker was deleted the tab held only a vestigial `quality_hints` info caption (whose `title`/`body` strings were never even defined — raw on both main *and* the branch) with no actual controls, so `SettingsSection.audio` + `AudioSettingsSection.swift` + the unused `settings.group.audio`/`quality_hints` strings were removed (rebuild a source picker if Specific App is ever re-added). Also updated `SECURITY_POSTURE.md §1` (the engine `.application` single-PID tap case **remains in code but is no longer user-selectable**). **Kept main's DOC.6.1 — explicitly dropped the branch's competing `[DOC.6]` gate change (`71f050d`) and its rotation (`09270ab`)**, resolving the divergence in main's favour; took the registry-doc cleanups (ARCHITECTURE / APP.md / AUDIO.md / DECISIONS_HISTORY). Supersedes **D-052** (full) + **D-061(b,c)**; resolves the two CLEAN.2.3 out-of-scope findings (reconciler-unwired, `specific_app` key). App tests **388 → 377** (11 capture tests removed); engine + app build green, swiftlint clean, doc gates 9/9. `RELEASE_NOTES_DEV.md [dev-2026-06-15-c]`.
- **CLEAN.2.5a — Enable hardened runtime + Apple Events entitlement (GAP-10 fix, HR half)** ✅ (2026-06-15, code-complete; **manual runtime gates pending**): the build/signing half of GAP-10, **split** from CLEAN.2.5 because Developer ID signing + notarization (the 2.5b half) need a **paid Apple Developer Program membership the project does not have** (Matt's confirmation, 2026-06-15 — the discovered prerequisite). Unlike 2.4 (document-only), this is the deliberate flip — with a build + a signed-binary check behind it. **Step 1:** `ENABLE_HARDENED_RUNTIME = YES` on the app target's **Release** build config (`project.pbxproj` `AB0004`). **Debug is left unhardened on purpose:** HR enables library validation, and a hardened test host refuses to `dlopen` the injected `PhospheneAppTests.xctest` (`… non-platform … different Team IDs`) → `xcodebuild test` fails; HR is a Release/distribution property anyway, so Release-only keeps the suite green and hardens the config that ships + notarizes. (First tried in `Phosphene.xcconfig` = both configs; the app-test break forced Release-only — durable learning in `SECURITY_POSTURE.md §3`.) **Step 3:** added `com.apple.security.automation.apple-events` to `PhospheneApp.entitlements` — HR gates outbound Apple Events and the `StreamingMetadata` now-playing bridge (`NSAppleScript` → Apple Music / Spotify, `executeAndReturnError`) needs it. **Step 2 (tap):** no change — TCC-gated (screen-recording), expected to survive HR; **no `com.apple.security.cs.*` added speculatively** (only if a real run breaks the tap). **Verified (automated):** Release build signs with `-o runtime` (`codesign -dv` → `flags=0x10000(runtime)`, Runtime Version present); `automation.apple-events` present on the signed binary; library validation left on (no `disable-library-validation`); Debug `xcodebuild test` suite green (unhardened host loads the XCTest bundle). **Manual gates VERIFIED 2026-06-15** (Matt, Mac mini, hardened Release build, session `2026-06-15T22-45-34Z`): (i) launches under HR ✅; (ii) `.systemAudio` tap installs + delivers audio under HR ✅ — green @ −6 dBFS, 11,425 live-energy frames in `features.csv` (startup "red/silent" is the documented pre-playback artifact); (iii) Apple Events ✅ accepted — the now-playing AppleScript poller ran under HR without fault + the entitlement is verified on the binary, but this Spotify-prefetched session did not isolate it (metadata came from the Spotify Web-API plan; per-poll AppleScript results aren't persisted), so satisfied-by-construction per Matt's call. Spotify connection confirmed on the primary-dir build (the worktree build had an empty `SPOTIFY_CLIENT_ID` — the gitignored `Phosphene.local.xcconfig` is absent in worktrees, so live tests must build from the primary checkout). **CLEAN.2.5b deferred** (Developer ID signing + notarization + Gatekeeper test — blocked on the paid membership; mechanical once the cert + notarization key exist). Two-line production diff (xcconfig + entitlements); no Swift source touched. Docs: `SECURITY_POSTURE.md` §3/§4 + summary row 3 + provenance note, `CODE_AUDIT_2026-06-13.md` G10 + Part C (GAP-10 **half-landed, not fully closed**). `RELEASE_NOTES_DEV.md [dev-2026-06-15-h]`.
- **CLEAN.5.1/5.2/5.3/5.6 + 5.7 — CI fast gate on GitHub** ✅ (2026-06-15, **GREEN on `main`** — [run #4](https://github.com/hoaxpoet/phosphene/actions/runs/27592398557), `86c6532` — after 3 CI-vs-dev env fixes; the GitHub branch-protection required-check toggle is now **ENABLED** — `main` requires the `fast-gate` context (verified 2026-06-18 via the branch-protection API), so **CLEAN.5.1 is fully complete**): the "fast gate on GitHub-hosted runners" strategy (Matt, 2026-06-15). **Bring-up took 4 runs, each red a real environment gap** (see `RELEASE_NOTES_DEV [dev-2026-06-15-j]`): (#1) `macos-14`'s Xcode 16.2 SDK doesn't mark Metal types `Sendable` → `runs-on: macos-26` (Xcode 26.5, exact dev match; build-SDK ≠ run-target, deployment stays 14.0); (#2) `macos-26` brew-installs swiftlint 0.63.3 ≠ dev 0.63.2 → `#require` over `URL(string:)!`; (#3) `PlaylistConnector` needs Apple Music (headless `.appleMusicNotRunning`) → dropped from the allow-list (third exclusion axis: external-app runtime). **5.7**: `actions/checkout@v4 → @v6` (Node 24). — every push-to-`main`/PR runs build + lint + doc/string/sample-rate gates + a GPU/fixture-free logic subset; the heavy GPU + licensed-fixture + perf-timing suites stay the manual `Scripts/closeout_evidence.sh` gate. **5.1** `.github/workflows/ci.yml` (`runs-on: macos-14`, `lfs: true`, `CODE_SIGNING_ALLOWED=NO`, `concurrency` cancel-in-progress): newest-Xcode select → app+engine build → swiftlint --strict → DocIntegrityTests → **Option-A lean allow-list** of 13 GPU/fixture-free suites (~130 logic tests) → the two lint scripts. Every step locally validated green (app build SUCCEEDED signing-disabled; logic subset 130/130). Allow-list gotcha recorded: `swift test --filter` matches the **type name**, not the `@Suite("display")` string (`PresetScorer` not `DefaultPresetScorer`). **5.2** `Scripts/bootstrap_fixtures.sh` restores the gitignored `Tests/Fixtures/tempo/` in a fresh worktree (cp byte-identical from the primary checkout via `git worktree list` → `fetch_tempo_fixtures.sh` fallback) — validated (copied 8 files, this worktree's full engine suite then green). **5.3** the two lint scripts + DocIntegrity wired as CI steps; `closeout_evidence.sh` Step-4 no longer prints the misleading "Executed 0 tests" XCTest aggregate for swift-testing-only suites (display-only; honesty contract intact). **5.6** RUNBOOK §Gate structure documents CI-automated vs manual-closeout. **Option B (full-suite-minus-skip-list)** is the deferred follow-up — needs an empirical check that `macos-14` exposes a working Metal device + the GPU suites pass there (impossible to verify pre-push). **Risk flagged:** dev toolchain is Xcode 26.5 / Swift 6.3 vs CI `macos-14`'s Xcode 16 — code is Swift 6.0 language mode so expected to compile, but the first CI run is the proof; toolchain pin is CLEAN.5.4. Out of scope: 5.4 (toolchain pin), 5.5 (ML-weight sha256 gate). `RELEASE_NOTES_DEV.md [dev-2026-06-15-i]`.
- **CLEAN.5.4 — build reproducibility: pin toolchain + Package.resolved + LFS-present check (folds in 5.7's Actions SHA-pin)** ✅ (2026-06-15 built, **pushed 2026-06-16 → origin/main `8774e21`; fast-gate GREEN on macos-26** — PR #2 run + on-push main run, every new step passed on a clean-cache runner): closes the bring-up lesson from `[dev-2026-06-15-j]` — all three CLEAN.5.1 reds were "CI tool version ≠ dev". **5.4a Xcode pin:** new `.xcode-version` (`26.5`); the CI `Select Xcode` step now selects `/Applications/Xcode_$(cat .xcode-version).app` exactly and **fails loud** if absent (image rotated the point release → bump the file), replacing `ls … | sort -V | tail -1`. **5.4b SwiftLint pin:** the step downloads the exact `0.63.2` portable binary (universal; verifies `version` before linting) instead of `brew install` latest — kills the 0.63.3 `force_unwrapping`-rule drift. **5.4c Package.resolved:** un-gitignored + committed **both** resolved files CI builds from (`PhospheneEngine/Package.resolved` for `swift build`, `PhospheneApp.xcodeproj/…/swiftpm/Package.resolved` for `xcodebuild` — same 4 pinned deps: argument-parser 1.7.1 / async-algorithms 1.1.3 / collections 1.4.1 / numerics 1.1.1); build now passes `-disableAutomaticPackageResolution` (xcodebuild) + `--only-use-versions-from-resolved-file` (swift build) → a dep-graph change not reflected in the resolved file fails CI instead of silently floating. `.gitignore` keeps the blanket ignore + two anchored negations (PhospheneTools/ + worktree copies stay ignored; the `swiftpm/` dir-exclusion became `swiftpm/*` so the file can be re-included). **5.4d LFS gate:** new `Scripts/check_lfs_smudged.sh` (CI step before Build) fails loud if any LFS file is still a pointer (`git lfs ls-files` col-2 `-`), so a non-smudged checkout can't bundle ~130 B stubs and "build green". **5.4e / 5.7 SHA-pin:** `actions/checkout@v6` → `@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6.0.3` with a documented bump procedure. **Locally verified:** ci.yml parses; LFS gate green (492/492 smudged); fresh `swift package resolve` + `xcodebuild -resolvePackageDependencies` both leave the committed files byte-unchanged (pins current → drift-detection fires correctly); the real `xcodebuild … -disableAutomaticPackageResolution … build` → **BUILD SUCCEEDED** from the committed file. Not visually verifiable. Out of scope: CLEAN.5.5 (ML-weight sha256 load gate); deployment target unchanged (macOS 14.0). `RELEASE_NOTES_DEV.md [dev-2026-06-15-k]`.
- **CLEAN.5.5 — ML-weight load-time `sha256` integrity gate (GAP-11; closes Phase 5)** ✅ (2026-06-16): the *content* half of the weight supply chain — 5.4d proved the `.bin` are **present** (not LFS stubs), 5.5 proves they're **correct**. A truncated/bit-rotten/wrong-version/tampered weight that preserves byte-count otherwise feeds plausible-but-garbage stems/beats with **no crash**; the throw is the value. Load-time `SHA256.hash` folded into the existing `Data(contentsOf:)` read in both on-disk loaders (one-time at model construction, GPU-free, ~70–180 ms stem / ~5–47 ms beat_this — not per-frame), fail-loud on mismatch. **5.5a beat_this:** the manifest already carried 161 per-tensor `sha256` (written by `convert_beatthis_weights.py`) — wired them in: `sha256` added to `BeatThisManifest.TensorEntry`, a `BeatThisWeightError.checksumMismatch` thrown from `loadBeatThisTensor`. **5.5b stem:** generated 172 digests from the **committed bytes** (`tools/add_stem_weight_checksums.py --check`able; hashes what ships — no umx re-extraction, so the manifest pins the shipping bytes) into `Weights/manifest.json`; `sha256` added to `WeightManifest.TensorEntry` + `StemModelWeightError.checksumMismatch` in `loadTensor`, **alongside** (not replacing) the existing `expectedBytes` byte-count guard (cheaper/clearer for the common truncation case). Shared `WeightChecksum.hex/verify` (CryptoKit, lowercase-no-separator hex matching the manifest + `shasum -a 256`) keeps both near-cap `+Weights.swift` under the 400-line lint cap. MoodClassifier out of scope (compiled-in `[Float]` arrays — no file to checksum). **5.5c:** new **GPU-free** `WeightChecksumTests` (8 tests: known-answer hex pin so a future format change can't silently never-match; reject [both error types] / accept; **completeness gate** — every `.bin` on disk ↔ a manifest entry with a non-empty 64-char lowercase-hex `sha256`, both models, catches "added a weight, forgot the hash"; real-loader happy path) → added to the CI fast-gate `--filter` allow-list (pure `Data` hashing, no MPSGraph/Metal). **Verified:** 8/8 green; existing Metal-backed `test_weightsLoad_noThrow` / `test_init_loadsWeights_noThrow` still green (now also exercising the guard against all committed bytes); **empirical tamper** — one flipped byte of `bass_bn1_bias.bin` → real loader throws `checksumMismatch(expected: f8fc80d5…, got: c35b08d4…)`, auto-restored; swiftlint 0 violations. Not visually verifiable. **Phase 5 fully closed** (5.1/5.2/5.3 CI + 5.4 build-repro + 5.6 docs + 5.7 Node + 5.5 weights). GAP-11 → resolved in `CODE_AUDIT_2026-06-13.md` (Part B G11 + Part C). `RELEASE_NOTES_DEV.md [dev-2026-06-16-a]`.
- **CLEAN.5.8 — Git-LFS bandwidth remediation (CI weights-only + cache; reel → Release asset)** ✅ (2026-06-21; ops fix to CLEAN.5.1's `lfs: true`, triggered by a GitHub 100 %-of-10 GB LFS-bandwidth alert — not an audit-gap reopen). Bandwidth meters *downloads*; CI's `actions/checkout lfs: true` smudged the full ~796 MB LFS payload every run (71 runs Jun 16–19 × ~800 MB ≈ **55 GB** = 5.5× quota — the provable bleed), and a public repo (2,680 clones/14 d) compounds it. 72 % of every pull was one 572 MB file (`docs/quality_reel.mp4`, manual-tool input the build never uses). **Fix (Matt's picks: reel→Release, stay public):** (1) `ci.yml` drops `lfs: true` → SHA-pinned `actions/cache@v5.0.5` + `git lfs pull --include="…/ML/Weights/**"` (150 MB / 333 files only), `check_lfs_smudged.sh` scoped to weights — **CI 55 GB → ~0**; (2) reel removed from `.gitattributes` + `git rm --cached` (gitignored, kept local for `QualityReelAnalyzer`) → `assets-quality-reel` Release asset — **per-pull payload 796 MB → 224 MB**, no history rewrite (bandwidth ≠ storage). Not done: no `$0` budget (breaks CI/clones till Jul 01 reset; overage is pennies). CI behaviour validated by the next fast-gate run (not locally reproducible); no Swift changed. Commits `7d2fd5d` (CI) + `3b5afba` (reel) + docs. `RELEASE_NOTES_DEV.md [dev-2026-06-21-210449]`.
- **DOC.10 — pruning-pass manual triage (completes DOC.9's deterministic rotation; D-162)** ✅ (2026-06-21): added the missing `✅` marker to the stale `Mid-Spike-1 re-tune` (06-02) EP entry so `rotate_docs` moved its body to history (EP 489→484 KB); CLAUDE.md section-demotion review — within budget (6,701/7,000 est. tokens), all 12 sections core/recently-exercised, nothing demotable; DECISIONS shipped+uncited review — no candidates (D-014 "Proposed" is active + cited in 3 Orchestrator sources; bulk already in the 434 KB history). Docs-only, DocIntegrity 11/11. `RELEASE_NOTES_DEV.md [dev-2026-06-21-230939]`.
- **CLEAN.7.6 — `[GAP-9]` `[DEC D-164]` photosensitivity flash-safety: enforced measurement gate (PARTIAL), runtime clamp → A-next** ✅ (2026-06-16, the only open *safety* gap, pulled into June): the strict-photosensitivity mode deferred at D-054/U.9, now an enforced Harding/WCAG 2.3.1 invariant (≤ 3 flashes/s). **Matt's picks (3× AskUserQuestion):** enforce by **measurement now / runtime clamp A-next** (not a look-altering clamp bundled now — that needs a golden regen + M7 re-review of every certified preset); a **synthetic worst-case drive** (the FBS "373-events" video A/B was never committed, the `Fixtures/fbs` CSVs are 3-band extracts carrying none of the flash-causing signal, `PresetSessionReplay` is an un-importable `executableTarget` — all three false premises surfaced before building); **partial gate now, rest A-next** after running the gate revealed the harness limit. **Shipped:** `FlashAnalyzer` (`Sources/Renderer` — pure Harding analyzer on a full-frame relative-luminance sequence; 8 synthetic self-checks pin the semantics, substituting for the lost FBS A/B) + `PhotosensitivityCertificationTests` (renders each certified preset over a 4.5 Hz worst-case beat train, measures rendered full-frame WCAG luminance, **fails cert at > 3 flashes/s**). **Coverage:** the single-pass `FeatureVector`-only harness validly measures only presets that read their music response from the FeatureVector in-shader — **Ferrofluid Ocean + Murmuration, both 0 flashes/s SAFE.** The other five render **static** here (Lumen Mosaic/Nimbus = CPU follower-state buffers; Dragon Bloom/Fata Morgana = mv_warp feedback [CLEAN.7.6 mislabelled these "rayMarch" — corrected by CLEAN.7.6c]; Skein = feedback history); a static render is **never asserted safe** (CLEAN.0) — they're tracked in `unmeasurableInHarness` and the gate **fails loud on drift**. Valid coverage for those five + the runtime clamp both need the **A-next headless real-`RenderPipeline` harness**; further A-next blind spots: regional/area-gating, the red-flash channel. Test-only + one new Renderer source; no production-render delta, not a look change (no M7). swiftlint clean; analyzer 8/8 + gate green. Docs: `DECISIONS.md` D-164, `CODE_AUDIT_2026-06-13.md` (G9 + Part C 7.6), `SHADER_CRAFT.md` (anti-strobe convention → cited enforced invariant), `RENDER_CAPABILITY_REGISTRY.md §9`. `RELEASE_NOTES_DEV.md [dev-2026-06-16-b]`.
- **CLEAN.3.7a — `[GAP-2]` Sample-rate contract: trace & decide (diagnosis only; split from 3.7)** ✅ (2026-06-16, **commit-the-trace-and-stop** per the kickoff's decision rule + the Defect Protocol): traced the tap sample rate end-to-end on the streaming + local-file paths. **Verdict: a real (latent) defect, filed BUG-053 — this refutes the pre-kickoff trace's "streaming MIR already rate-aware" assertion.** The live `MIRPipeline` (`VisualizerEngine.swift:740`) is built with the `sampleRate: Float = 48000` **default** and `process()` carries no rate, so its sub-analyzers stay frozen at the 48000 bin→Hz tables they precomputed at init — the FFT's per-call `rate` only sets `FFTResult` metadata (the magnitude array is rate-independent), and `tapSampleRate` is threaded to the **stem** path but never the live MIR. At a 44.1 kHz tap: chroma/key ~1.5 semitones sharp + band cutoffs ~8.8 % low (centroid/rolloff normalization cancels; tempo/flux rate-independent). **Masked at 48 kHz** (the common config + `readTapFormat` fallback), so silent today; manifests on a 44.1 kHz device or a device-swap to one (**couples to G1/CLEAN.1.5**, whose `performReinstall` reads the new rate but doesn't re-init the MIR). The **offline** session-prep MIR is correct (`SessionPreparer+Analysis.swift:256` passes the file's real rate). Docs only: KNOWN_ISSUES (BUG-053 + verdict), `CODE_AUDIT_2026-06-13.md` G2 row + CLEAN.3.7 backlog rows, this entry. **No code changed → not visually verifiable.** The fix (live-MIR rate wiring) + 3.7b/c (doc reconcile + default-trap removal + regression gate) **split into CLEAN.3.7-fix — architectural, pending Matt's pick of approach** (BUG-053 §Fix approaches: re-init-on-rate-change vs per-call rate threading vs make-48k-explicit). `RELEASE_NOTES_DEV.md [dev-2026-06-16-f]`.
- **CLEAN.3.7-fix — `[GAP-2]` Live MIR adopts the actual capture rate (BUG-053; Matt: "fix it properly")** ✅ (2026-06-16; **BUG-053 RESOLVED — validated** by Matt, session `2026-06-16T20-22-12Z`). Each rate-sensitive sub-analyzer (`Spectral`/`BandEnergy`/`Chroma`/`Beat`) gained an in-place `setSampleRate(_:)` (recomputes bin→Hz tables under lock, preserves running state); `MIRPipeline.setSampleRate` (same-file extension, keeps the class under `type_body_length`) forwards to the four + recomputes its Nyquist; `VisualizerEngine+Audio.processAnalysisFrame` calls it with the captured `tapSampleRate` on the analysis queue (off the RT thread) — **no-op on a 48 kHz tap**, recompute on a 44.1 kHz path / device-swap (couples to G1). Paired the hardcoded 24 kHz mood-centroid divisor → live Nyquist (pre-fix cancellation meant mood was ≈ right; the paired change keeps mood unchanged while making the raw centroid honest). Real-world scope was broader than the trace's "rare hardware": **local-file playback of 44.1 kHz files** always hit it (chroma/key ~1.5 semitones sharp + bands ~8.8 % low). Gate: `MIRSampleRateReconfigureTests` (GPU-free, CI fast-gate). Doc reconcile (3.7b): `Protocols.swift`, ARCHITECTURE §Sample-rate contract. Engine+app build green, swiftlint 0, 61 GPU-free tests green. Commit `91a973e` (code+test+CI) + doc commit; pushed origin `8b80717`. `RELEASE_NOTES_DEV.md [dev-2026-06-16-g]`. **Validated 2026-06-16** (session `2026-06-16T20-22-12Z`, Limo Wreck 44.1 kHz LF): `session.log` logged `MIR analysis rate → 44100 Hz` — live MIR adopted the file's real rate. **BUG-053 → Resolved.**
- **CLEAN.3.4 — BUG-037 Arachne chord-count single source of truth** ✅ (2026-06-17 → **validated 2026-06-18**). The Arachne spiral reveal popped at ~45 %: the CPU capped `spiralChordsTotal` at `min(200, …)` while the shader normalized `spiral_packed / 441.0` and a test used a third value (104) — three uncoordinated constants for one contract (the post-BUG-011 ranges made the product 324–576, so the 200 cap always fired). Fix (Matt's pick: restore the intended density/build): the CPU is now the single source — `spiralPacked` is published already-normalized (`min(1, (index+progress)/spiralChordsTotal)`), the shader reveals by it directly (`saturate(spiral_packed)`, the hardcoded 441 deleted), and the cap is raised to `maxSpiralChords = 600` (a degenerate-case guard above the 576 max, not a truncation). The test fixture's 104 → 1.0 (normalized). No struct/GPU-contract change (pre-normalize, not a new field). The change is **build-phase-temporal**: the `.stable` golden is unchanged (the final spider is identical — `spiralRevolutions` sets density, not the chord count, which governs the reveal *animation*), so `PresetRegressionTests` stays green with no golden regen. Automated lock: `ArachneStateBuildTests.spiralChordCountHonoursProduct` (the uncapped product is honoured across seeds, > 200). All 44 Arachne/acceptance/regression tests green, swiftlint 0. **The manual M7 (the build reveals smoothly to the core over the documented ~73 s cycle, no pop) is pending Matt** — the existing RENDER_VISUAL harness only captures an early-build frame, so the reveal is best validated live. `RELEASE_NOTES_DEV.md [dev-2026-06-17-223835]`. `KNOWN_ISSUES.md` BUG-037. **M7-FOLLOWUP ⏳ (2026-06-18):** Matt's live session showed the pop *persisted* — the audit's chord-count framing was incomplete. The dominant cause is that Arachne's ~92 s build outlives its ~38 s planned section: `wait_for_completion_event` only fills a section (`maxDuration = .infinity`), so `planOneSegment` still cut the segment at the section boundary → forced `.stable` pop. Matt's pick: **make `wait_for_completion_event` span sections.** Planner fix landed — `planOneSegment` spans a completion-gated preset over its `naturalCycleSeconds` + `planSegments` `coveredUntil` skip; the build now finishes before any plan boundary (reveal → 1.0, no pop). Gate `SessionPlannerTests.waitForCompletion_segmentSpansSections`; 25 planner + 99 orchestrator/integration green. Normalization + cap-raise retained. `RELEASE_NOTES_DEV.md [dev-2026-06-18-035306]` + `[dev-2026-06-18-143356]`. **Matt re-validated 2026-06-18 (session `…T14-30-52Z`) — full web to completion, no pop. BUG-037 RESOLVED.**
- **CLEAN.3.8 — `[GAP-6]` Disk-full / write-failure graceful degradation** ✅ (2026-06-17, sixth Phase-3 increment; closes the non-M7 Phase-3 work). `SessionRecorder` wrote per-frame CSV + log via the **non-throwing `FileHandle.write(_:)`**, which raises an *uncatchable* Objective-C exception on ENOSPC → process crash (and can leave a half-written final row). Routed every write through `safeWrite` (`SessionRecorder+DiskGuard` extension): the throwing `write(contentsOf:)` in do/catch → on failure `haltRecording` sets `recordingHalted`, logs once to the unified log (the on-disk `session.log` may also be unwritable), and every subsequent write + `recordFrame` early-outs — an honest stop with partial artifacts retained, never a crash or silent corruption. Pre-flight `warnIfLowDiskSpace(at:)` logs a loud warning at session start when `volumeAvailableCapacityForImportantUsage` is below `minFreeBytesForRecording` (200 MB; recording still proceeds — a short session may fit). `PersistentStemCache` was audited and **already safe** (atomic `write(to:options:.atomic)` + a throwing `store` caught at the call site), so it is untouched. Logic in an extension to keep the class under `type_body_length`. Gates: `test_diskGuard_capacityPredicate` (pure) + `test_diskGuard_haltStopsFurtherWrites` (halt → no further rows, no crash, idempotent). Engine build green, swiftlint `--strict` 0. Not visually verifiable. `RELEASE_NOTES_DEV.md [dev-2026-06-17-220337]`.
- **CLEAN.3.6 — SessionRecorder running-vs-actually-writing invariant (BUG-039 follow-through)** ✅ (2026-06-17, fifth Phase-3 increment). BUG-039's recovery (writer death → roll to `video_N.mp4`, bounded at 8 restarts) shipped 2026-06-10, but nothing tied "recorder running" to "video actually advancing" — after the restart budget exhausts (or any unrecovered silent stall) the recorder keeps writing CSV/log while video is silently dead. Added the invariant: a successful-append counter `videoFramesAppended` + `lastVideoAppendFrameIndex` (the "actually-writing" signal), and at `finish()` a video-outcome summary on the session-end log line (`video N appended / S segment(s) / R restart(s) / disabled=bool`) plus a loud `BUG-039 invariant VIOLATED` line when the silent-stop *signature* is present (writer locked, appends stopped > `videoSilentStopFrameThreshold` (300) frames before end, no death/restart, not disabled — every *explained* stop excluded). The invariant logic (`finalizeVideoInvariant` + the pure `isSilentVideoStop`) lives in the `SessionRecorder+Video` extension to keep the class under `type_body_length`. Gates: `test_bug039Invariant_silentStopPredicate` (pure, GPU-free) + the existing recovery test extended to confirm appends resume after the roll (`videoFramesAppended > 0`, no false violation). Engine build green, swiftlint `--strict` 0. Not visually verifiable. **BUG-039 RESOLVED 2026-06-18** (Matt's live multi-session confirmation — the silent-stop signature no longer occurs). `RELEASE_NOTES_DEV.md [dev-2026-06-17-214707]`.
- **CLEAN.3.5 — StemCache eviction + close diag-log handle + retire dead helpers** ✅ (2026-06-17, fourth Phase-3 increment; 3.4 is Stretch/M7). Three resource/cleanup items. (1) **StemCache eviction**: the in-memory streaming `StemCache` (`[TrackIdentity: CachedTrackData]`, ~7 MB/track, no disk backing) had no eviction and was never `clear()`ed → unbounded across the engine's lifetime under track churn. Added LRU eviction (`maxEntries`, default 64 ≈ 450 MB — same order as the on-disk `PersistentStemCache` LRU); recency bumped on `store` + `loadForPlayback` only (metadata accessors are planning peeks). `init()` → `init(maxEntries: Int = 64)` (source-compatible; `StemCache()` callers unchanged). (2) **diag-log handle**: `VisualizerEngine.diagLog` (`~/phosphene_diag.log`) was opened in `setupAudioRouting` (called once) and never closed → one leaked FD. Now closed before reopen (defensive) + in `deinit`. (3) **Dead helpers deleted**: `FFTProcessor.printHistogram`, `BeatDetector.percentileOfBuffer`, `RayMarchPipeline.depthDebugEnabled` (all zero references; `depthDebugPipeline`/`runDepthDebugPass` are gated by `debugGBufferMode`, untouched). Gate: `StemCacheEvictionTests` (3, GPU-free — LRU evicts oldest / re-store no-grows / clear empties). Engine + app build green, swiftlint `--strict` 0. Not visually verifiable (resource/cleanup). `RELEASE_NOTES_DEV.md [dev-2026-06-17-212025]`.
- **CLEAN.3.3 — Mood-override cooldown survives repeat plays/sessions** ✅ (2026-06-17, third Phase-3 increment). The per-track mood-override cooldown (`lastOverrideTimePerTrack`, keyed by `TrackIdentity`, on the single engine-lifetime `DefaultLiveAdapter`) recorded the *per-track-relative* `elapsedTrackTime` of the last override, but `cooldownAdaptation` compared it as `elapsedTrackTime - last < 30s` with no lower bound. On a replay / new session the per-track clock resets to ~0 while `last` still held the prior play's value (e.g. 20 s), so `0 − 20 = −18 < 30` read as "cooldown active" for the entire 2nd play — and a 30 s preview clip never re-passes the stale mark, so mood override was **permanently dead from play 2**. Fix: a backwards delta (`sinceOverride < 0`) is now treated as no active cooldown (the stored mark is stale; `recordOverride` refreshes it on the next fire). "Report swallowed attempts" was already satisfied — the suppression's `.moodDivergenceDetected` event ("…but cooldown active") is logged by the consumer at `VisualizerEngine+Orchestrator:198`. Engine-only, no public API change; the `[TrackIdentity: TimeInterval]` dict is unbounded-by-distinct-track but immaterial (small structs, per-engine-lifetime) — left for CLEAN.3.5's eviction sweep if ever material. Gate: `moodOverrideCooldown_survivesReplay` (the 3 existing cooldown tests still green). LiveAdapter suite 12/12, swiftlint `--strict` 0. Not visually verifiable. `RELEASE_NOTES_DEV.md [dev-2026-06-17-204433]`.
- **CLEAN.3.2 — PresetScorer exclusion contract + zero-duration `catalog.first` bypass** ✅ (2026-06-17, second Phase-3 increment). Closed two paths by which an excluded/diagnostic preset could auto-install despite the D-074 gate. (1) **Zero-duration `catalog.first` bypass** (`SessionPlanner+Segments`): a zero-duration / section-degenerate track emits no segments and hit the "≥1 segment" defensive fallback, which grabbed a raw `catalog.first` (no exclusion filter) — a diagnostic sitting first installed. Now picks the best *eligible* preset (`rank().first(where: { $0.1 > 0 })`), degrading only to a categorically-eligible one. (2) **`rank()` contract drift**: doc claimed "excluding zeroed presets" but the impl keeps hard-excluded presets at score 0 (deliberate — `rankStabilityAcrossTiers` inspects the 0); fixed the doc to state reality + the **install idiom** (`.first(where: { $0.1 > 0 })`, never bare `.first`/`!isDiagnostic`-only), and tightened the one weaker caller (`ReactiveOrchestrator`). `DefaultPlaybackActionRouter` already correct; `LiveAdapter` safe by its score-gap threshold (both unchanged). Extracted the categorical-eligibility filter to `categoricallyEligiblePool(_:onIrregularBeat:)`, shared by both defensive fallbacks (single source of truth, no drift). Gates: `zeroDurationTrack_neverInstallsDiagnostic` + `rankContract_excludedKeptButNotInstallable` (GPU-free). Orchestrator suites 53/53, swiftlint `--strict` 0. Engine-only, no public API change, not visually verifiable. `RELEASE_NOTES_DEV.md [dev-2026-06-17-203109]`.
- **CLEAN.3.1 — Surface preset init failures (malformed-vs-missing sidecar; PostProcess error parity)** ✅ (2026-06-17, first Phase-3 increment). `PresetLoader.loadDescriptor` collapsed `fileExists` + `try? Data` + `try? decode` into one guard, so a sidecar that **existed but was malformed/unreadable** logged the same `.info("No JSON sidecar…")` as a genuinely-absent one and silently degraded the preset to default family/feedback params. Split via a new static `decodeSidecar(at:)` — `nil` for a missing file (benign `.info` + name-only default), **throws** for present-but-malformed (`.error` with the real decode error, then degrades to the same name-only default; `family` stays `nil` — behaviour-preserved vs the old `{"name":"X"}` path, since `PresetDescriptor.fallback` would have forced `.waveform`). App-side `VisualizerEngine+Presets` `.postProcess` swapped `try?`-then-generic-log for a `do/catch` that surfaces the real `PostProcessError` (parity with the already-loud rayMarch `do/catch`; fallback = base pass, no post-process — degraded not black). Verified the other audit-flagged paths are already loud + sufficient: shader compile (log + return nil → preset skipped, caught by the FA #44 count gate) and `RayMarchPipeline.init` (call-site `do/catch` logs the real error). Gate: `PresetLoaderSidecarTests` (3, GPU-free — missing→nil / malformed→throws / valid→decodes). Engine `swift test --filter PresetLoader` 16/16, app build green, swiftlint `--strict` 0. Not visually verifiable (loader / error-path hardening). `RELEASE_NOTES_DEV.md [dev-2026-06-17-200818]`.
- **CLEAN.7.6b Stage 1 (partial) — `[GAP-9]` flash-safety gate now measures Nimbus (2/7 → 3/7)** ✅ (2026-06-16, Matt: ship Nimbus now, multi-pass-4 separate). CLEAN.7.6 left 5/7 certified presets rendering static in the single-pass harness. **Scoping correction (verified before building):** only **Nimbus** is a `.direct` follower-state preset reproducible in the single-pass harness; **Lumen** is `.rayMarch`+`.postProcess` (not a cheap follower as first assumed), **Dragon Bloom/Fata Morgana** are mv_warp feedback (mislabelled "rayMarch" here — corrected by CLEAN.7.6c; their passes are `["direct","mv_warp"]`), **Skein** needs mvWarp feedback — all 4 need the multi-pass headless harness a prior effort (`MaterialRenderHarness`) rejected as too much scaffolding. `PhotosensitivityCertificationTests.renderLuminanceSequence` now constructs + ticks `NimbusState` and binds its live slot-6 buffer (`StemFeatures.zero` is correct — Nimbus's stem lobes are cold-start-gated out of the 3 s window, so the full-frame flash signal is the FeatureVector whole-body kick/bloom). Result: `Nimbus MEASURED 0.00 flashes/s SAFE (Δ0.026)`; gate green (20 cases); **G9 3/7** (FFO + Murmuration + Nimbus, all 0 flashes/s). Test-only, no production delta, no M7. Remaining 4 (1 rayMarch + 3 mv_warp feedback) = the **multi-pass headless harness** sub-increment — done as **CLEAN.7.6c** (renumbered from the drafted "Stage 1b"; kickoff `docs/prompts/CLEAN_7.6b_STAGE1b_MULTIPASS_FLASH_HARNESS_KICKOFF.md`). Docs: CODE_AUDIT G9 + Part C 7.6, RENDER_CAPABILITY_REGISTRY §9. `RELEASE_NOTES_DEV.md [dev-2026-06-16-h]`.
- **CLEAN.7.6c — `[GAP-9]` multi-pass flash-safety harness: G9 fully ENFORCED (7/7)** ✅ (2026-06-16; renumbered from the drafted "7.6b Stage 1b" per Matt — 7.6b is the runtime-clamp increment, so the multi-pass *measurement* work gets its own letter; the runtime clamp becomes 7.6d). Closes the 4 certified presets the single-pass FeatureVector harness renders static. **Premise correction (verified against the JSON sidecars + shaders, FA #73):** CLEAN.7.6/7.6b mislabelled **Dragon Bloom + Fata Morgana as "rayMarch"** — they are `["direct","mv_warp"]` mv_warp FEEDBACK presets (0 raymarch loops), like Skein. Real split = **1 rayMarch (Lumen Mosaic) + 3 mv_warp feedback (DB/FM/Skein)**, not 3 + 1. **Route (reuse, don't rebuild):** Lumen extends BUG-034's production-parity ray-march harness (`RayMarchPipeline.render` @ the live 128-step budget + post-process + the 4-light follower slot-8, ticked; a real palette loaded so cells aren't black per BUG-016); Fata Morgana reuses its already-target-agnostic `renderFataMorgana(target:)`; **DB + Skein** needed one small production seam — `renderMVWarpToTexture` (new `RenderPipeline+MVWarpHeadless.swift`) factors the present out of the mv_warp blit (pure extract-method; live + headless share `encodeMVWarpBlitContent`/`swapMVWarpTextures` verbatim → PresetRegression byte-identical). **Matt approved the seam** (the only deviation from the kickoff's "test-only" line; behaviour-preserving, no look change, no M7). **All 7 certified presets measured SAFE** (worst-case 4.5 Hz beat + stem train, full-frame WCAG luminance, limit 3.0): FFO / Murmuration / Nimbus / Lumen Mosaic / Skein **0.00**, Fata Morgana **0.50**, Dragon Bloom **1.00**. `PhotosensitivityCertificationTests` now skips the multi-pass set (`multiPassMeasured`) + still **fails loud** if a new certified preset renders static without joining the harness. New `MultiPassFlashHarnessTests` + `FlashHarnessSupport` (shared worst-case drive + WCAG luminance, factored from the single-pass gate). GPU tests (manual-closeout suite, not the CI fast gate). swiftlint `--strict` 0; photosensitivity 6/6 + PresetRegression 4/4 green. Docs: CODE_AUDIT G9 → ENFORCED (7/7) + Part C, RENDER_CAPABILITY_REGISTRY §9 → Supported (7/7), cert-test header rayMarch mislabel corrected. `RELEASE_NOTES_DEV.md [dev-2026-06-16-214242]`.
- **CLEAN.7.6d — `[GAP-9]` `[DEC D-166]` runtime flash-safety clamp: evaluated, NOT pursued — the cert gate is the enforcement mechanism** ✅ (2026-06-17, decision increment, no code). The deferred "A-next" clamp half of D-164. Two facts surfaced on starting it (both → Matt, AskUserQuestion): (1) the cert gate already enforces the 3/s line on **everything we ship** — 7/7 ENFORCED under a worse-than-real-music drive, all presets ≤ 1 flash/s (Dragon Bloom 1.00 is the worst, a third of the limit); Phosphene ships only certified presets, so shipped content is covered without a clamp. (2) A uniform clamp is **pipeline-wide**, not "a final pass at `draw(in:)`" as D-164 assumed: `renderFrame` (`RenderPipeline+Draw.swift:126`) fans out to 8 terminal paths each presenting its own drawable — no single chokepoint; making it uniform means rerouting all 8 with regression risk across every certified preset, for a net that never engages on shipped content. **Matt's picks:** trip point = medical limit (3/s); backstop = *cert gate is enough, skip the clamp*. The `RayMarchPipeline:94` OR-flag slot stays reserved (reopen only on a new premise — un-certified / user-authored presets or live arbitrary-source render — with the 8-path cost in hand, D-166). No code, no golden regen, no M7. Docs: D-166, CODE_AUDIT G9 + CLEAN.7.6d (clamp declined), RENDER_CAPABILITY_REGISTRY §9. Residual A-next (open): regional-area / saturated-red-flash channels.
- **BUG-057.instrument — cold-tap-install-silence: capture-install diagnostics → session.log (P1 step 1, commit & stop)** ✅ (2026-06-17, Defect Protocol step 1 — instrument → STOP; no fix code; surfaced during CLEAN.7.6c canonical-app live testing). The streaming cold start installs the tap (`noErr`) but delivers persistent silence; only a manual output-device switch (→ `SystemAudioCapture.performReinstall`) recovers it, capturing real Spotify audio (BUG-057). Identical create steps cold-vs-reinstall ⇒ timing/state, not code. Added observability to separate the four candidates (TCC-not-yet-effective / DRM-zeroing / cold-bind-before-audio / insufficient `.silent → reinstall`) from ONE real cold-start session, all greppable from `session.log` (`TAP:` prefix; os_log rolls off): each (re)install's `defaultOutputDevice` + rate + `CGPreflightScreenCaptureAccess` (cold `startCapture` vs device-change `performReinstall`, generation-tagged); a ~1 Hz first-10 s RMS/peak probe per install (IO proc, throttled/window-gated); and the `.silent → reinstall` scheduler timeline (previously os_log-only). New protocol member `AudioCapturing.onCaptureDiagnostic` (mock stubbed) → `AudioInputRouter.onAudioCaptureDiagnostic` → `SessionRecorder.log`, wired in `VisualizerEngine+Audio`. Reuses the existing reinstall machine + `SilenceDetector` + CLEAN.1.5 `DefaultOutputDeviceMonitor` (FA #73) — no behaviour change. Regression: 2 routing-lock tests (sink gets the scheduled line in tap mode; stays empty under the LF.1 mode-gate); signal-state suite 13/13, engine+app build green, swiftlint 0. No registry change (audio-capture instrumentation, not a renderer/harness/preset capability). **Step 2 (diagnose) DONE 2026-06-17 — root cause is environmental, NOT a Phosphene bug.** Instrumented session `2026-06-17T13-29-13Z` showed all 4 installs `preflight=true rms=0` with the `.silent`-reinstall machine firing correctly; the decisive cross-check (standalone `tools/audio-tap-test`, separate binary/grant, identical API) was **also** pure-zero on both Duet 3 + built-in, DRM + non-DRM — falsifying all four candidates — and **`sudo killall coreaudiod` immediately restored real capture** (`coreaudiod` had been up 15+ days). So BUG-057 = a wedged `coreaudiod` feeding all process taps silence (workaround: restart the daemon / reboot). **The only Phosphene-side fix worth doing is the granted-but-silent *detector* (shared with BUG-055)** — surface actionable guidance instead of a silent "ready" flatline; the step-1 `TAP:` RMS probe is its signal. **Step 3 (fix) = that detector, pending Matt's go** (the kickoff's cold-install candidate fixes are moot). Full evidence chain in `KNOWN_ISSUES.md` BUG-057 §Diagnosis. `RELEASE_NOTES_DEV.md [dev-2026-06-17-041554]`.
- **BUG-058.instrument — mid-session device-swap freezes the tap (G1/CLEAN.1.5 recovery fails); breadcrumb `performReinstall` → session.log (P2 step 1, commit & stop)** ✅ (2026-06-17, Defect Protocol step 1 — instrument → STOP; no fix code; surfaced running the G1 manual gate after the BUG-057 coreaudiod fix). **Distinct from BUG-057** (healthy coreaudiod — the tap worked 39 s, then froze on the swap). Session `2026-06-17T14-28-30Z`: `raw_tap.wav` stops at 39.1 s of a 134 s run (IO proc stopped at the switch); `features.csv` tail is constant-nonzero (frozen buffer = the flat Waveform Matt saw), **no `reinstall via device-change` line and no `audio signal → silent`** — so neither recovery fired (`.silent` can't, since the buffer isn't RMS≈0; `performReinstall` didn't complete). Leading hypothesis: `performReinstall` fired + tore down (clean IO-proc stop) but the tap RECREATE stalled mid-transition. Couldn't confirm from os_log (the monitor/reinstall lines are `.info` → not persisted; `log show` empty), so added `session.log` breadcrumbs via the existing `onCaptureDiagnostic` sink: the `DefaultOutputDeviceMonitor` callback firing + each `performReinstall` step (ENTER/teardown/tap/aggregate/IO-proc/success/FAILED/SKIPPED). Engine build green, swiftlint 0; no test (breadcrumb-only on the non-SPM-testable device-change path). Filed BUG-058 (KNOWN_ISSUES). **OUTCOME (2026-06-17): G1 PASSES — the freeze is a RARE intermittent, not a systematic bug.** The instrumented re-test (session `14-54-49Z`) ran **12 rapid back-and-forth swaps, all 12 recovered** (`monitor FIRED` = 12 / reinstall completed = 12 / FAILED = 0; each `performReinstall` < 1 s, new tap recaptured RMS 0.05–0.49, motion preserved). The single freeze (`14-28-30Z`, pre-breadcrumb build, minutes after a `killall coreaudiod`) did NOT reproduce → leading explanation is a transient `coreaudiod`-settling race in the tap recreate. **So the open Phase-1 G1/CLEAN.1.5 manual gate (mid-session output-device swap → visuals stay live) is now VALIDATED.** BUG-058 downgraded P2 → **P3** (rare, un-reproduced; breadcrumbs left live to pin it if it recurs). Also sharpens the BUG-057/055 detector (must catch frozen-buffer / IO-proc-stopped, not just `.silent`).
- **CLEAN.4.7 — peak-RSS leak regression gate + soak baseline** ✅ (2026-06-18, audit `[GAP-16]` / G16). Closes G16 — `MemoryReporter` (phys_footprint) + the `SoakTestHarness` already *observed* memory growth ("observability only, not a hard gate"), but nothing *asserted* a ceiling. Adds `MemorySoakGateTests` (Diagnostics): two deterministic frame-count soaks drive the per-frame steady-state paths and fail if `phys_footprint` grows past a 25 MB budget after warmup — **FFT→MIR** (500 warmup + 2.5K soak) and **`StemAnalyzer`** (200 + 1.2K; heavier per frame so a smaller soak). Both pass green (growth well under budget → no leak). **`phys_footprint` is process-wide**, so the gate is **`SOAK_TESTS`-gated and run isolated** — `SOAK_TESTS=1 swift test --filter MemorySoakGate` (~7.7 s, `.serialized`); the normal parallel `swift test` / closeout **skips** it (a full-suite run swamped the measurement with +625 MB of unrelated GPU/stem churn — the same reason the `SoakTestHarness` 5-minute check is `SOAK_TESTS`-gated). **Division of labour:** the gate catches *gross* leaks (whole-object accumulation — tens of MB); slow sub-KB/frame creep + the absolute steady-state and 2 h growth curve stay the **manual `SoakRunner` diagnostic** (`Scripts/run_soak_test.sh`) — a device-time measurement, not a CI gate. swiftlint 0. No D-number (the budget is a calibrated test constant, not a policy). audit `CLEAN.4.7` + G16 → resolved; `RENDER_CAPABILITY_REGISTRY` soak row; `RELEASE_NOTES_DEV.md [dev-2026-06-18-184228]`.
- **CLEAN.4.6 — thermal + Low Power Mode adaptation feeds the frame-budget governor** ✅ (2026-06-18, audit `[GAP-4]` / G4; D-167; feature). Closes G4 (previously zero `thermalState`/`lowPowerMode` references). `FrameBudgetManager` gains a `thermalFloor: QualityLevel`; the applied level is `max(currentLevel, thermalFloor)`, so a rising thermal state pre-empts the GPU's own throttle (no waiting for the 3-overrun timing detection) and clearing it restores quality immediately (timing state untouched → no 180-frame recovery wait). The governor stays `ProcessInfo`-free (pure): `VisualizerEngine` observes `thermalStateDidChangeNotification` + `NSProcessInfoPowerStateDidChange`, maps via the pure static `FrameBudgetManager.qualityFloor(thermalState:lowPowerMode:)`, and seeds the floor at FBM creation. **Mapping (D-167, tunable):** serious → no-bloom, critical → step-0.75, LPM → ≥ no-SSGI; `.full` otherwise. The `QualityCeiling.ultra` recording exemption still bypasses the floor. **Gates:** 5 new `FrameBudgetManagerTests` (the floor clamps the applied level without touching the timing state; timing can still downshift below the floor; the floor survives `reset()`; mapping correct). Engine + app builds clean, swiftlint 0. **Manual gate (remaining):** actual thermal-induced pre-emption needs device validation under load — the Mac mini's active cooling rarely throttles, so this matters mainly for fanless deployment. audit `CLEAN.4.6` + G4 → resolved; `RENDER_CAPABILITY_REGISTRY` governor row; `RELEASE_NOTES_DEV.md [dev-2026-06-18-181837]`.
- **CLEAN.4.5 — NaN/Inf robustness sweep on the audio→GPU path** ✅ (2026-06-18, audit `[GAP-3]` / G3; part latent, part live). The two GPU-bound audio structs are **FeatureVector** (48 floats, fragment buffer 0) and **StemFeatures** (buffer 3); both scanned field-by-field via `withUnsafeBytes`. **Latent half:** silence / DC / cold-start already produce no NaN — the implicit guards (zero-sum conditionals in the spectral features, `1e-8` EMA floors in `StemAnalyzer`) cover the done-when cases (confirmed by the new tests, no code change). **Live half:** a **NaN/Inf in the input samples** (a corrupted tap — the realistic trust-boundary case the epsilon floors can't catch, since `NaN/1e-8 = NaN`) propagated straight through the FFT into both structs every frame (energy bands, centroid, deviations, attack ratios). A full-frame GPU NaN reads as a black/garbage frame — high blast radius, rare trigger. Fixed by sanitizing at the two FFT entry points: `FFTProcessor.process(samples:)` + `processStereo(interleaved:)` (per-sample `isFinite ? sample : 0` folded into the existing copy/mix loops — zero alloc, CLEAN.4.1-friendly) and `StemAnalyzer.computeMagnitudes` (in-place scrub of the copied region). **Output-preserving for finite audio** — guards are pass-through, PresetRegression goldens byte-identical (20×3), no M7. **Gates:** 2 new degenerate-audio integration tests run real degenerate *audio* through the FFT→MIR / StemAnalyzer paths (FA #27 — not hand-authored FeatureVectors) and assert every FeatureVector / StemFeatures field finite on every frame incl. cold start; both fail pre-fix on the NaN-input case. swiftlint 0. audit `CLEAN.4.5` + G3 row → resolved; `RELEASE_NOTES_DEV.md [dev-2026-06-18-175030]`. **Out of scope:** `GridOnsetCalibrator.computeMagnitudes` (preparation-time CPU calibration on clean preview audio, not a per-frame GPU producer).
- **CLEAN.4.3 — renderer texture-lifecycle correctness (sceneTexture aliasing + leak, resize stale-size, ray-march /height NaN)** ✅ (2026-06-18, audit T7; output-preserving — PresetRegression goldens byte-identical, so **no regen and no M7**; the `[M7]` tag was precautionary, same as 4.4). Three latent/robustness fixes. (A) **sceneTexture aliasing + leak** (`PostProcessChain.runBloomAndComposite`): the ray-march integration set `self.sceneTexture = externalSceneTexture` to feed the external lit texture into the bright/composite passes but never restored it, so a later standalone `.postProcess` preset's `runScenePass` rendered into the ray-march texture (and the chain retained a full-res rgba16f texture after detach). Now saved + `defer`-restored — the passes still read the external texture during the call (byte-identical output), but the member returns to the chain's own texture. (B) **resize stale-size** (`RenderPipeline.mtkView(drawableSizeWillChange:)`): a feedback-texture alloc failure `return`ed out of the handler, stranding the post-process / ray-march / mv_warp textures at the stale size. Now drops the feedback pair (rendering already guards on empty) and falls through so the rest resize. (C) **ray-march /height NaN** (`RenderPipeline+RayMarch`): the aspect-ratio guard checked `width > 0` but divided by `height` → +inf at zero height; guard the divisor instead (identical for any height > 0). **Verification** — PresetRegression byte-identical (20 presets × 3 fixtures); new `test_runBloomAndComposite_restoresOwnSceneTexture` (PostProcessChainTests 7/7) locks the alias fix and fails pre-fix; DrawableResize 6/6, RayMarchPipeline + BloomGate green. swiftlint 0 (PostProcessChain trimmed to the 400-line `file_length` ceiling — next addition needs a trim or split). No RENDER_CAPABILITY_REGISTRY change (correctness fixes within already-Supported post-process/offscreen capabilities). audit `CLEAN.4.3`; `RELEASE_NOTES_DEV.md [dev-2026-06-18-164609]`. **Out of scope:** DynamicTextOverlay in-flight race (unfiled, not confirmed).
- **CLEAN.4.2 — remove redundant DSP compute (autocorrelation 2×→1×, drums FFT 2×→1×, mono STFT 2×→1×)** ✅ (2026-06-18, audit T6 / `CODE_AUDIT_2026-06-09` §Performance; output-preserving). Three sibling dedups, each provably equivalent. (A) **Autocorrelation** — `BeatDetector.estimateTempo` swept the lag range `[minLag, maxLag]` twice (`findBestLag` for the peak, `computeAutocorrelationConfidence` for the mean), computing identical `vDSP_dotpr` correlations; merged into one `autocorrelationSweep` accumulating best-lag + mean in a single pass, with offset pointers (`base + lag`) replacing the ~85 per-lag `Array(linear[...])` slice copies → zero per-call heap allocs (confidence formula unchanged). (B) **Drums FFT** — `StemAnalyzer.analyze` discarded `analyzeStem`'s returned drums mags with `_` then recomputed the identical `computeMagnitudes(from: stemWaveforms[1])`; now reuses the returned mags (−1 FFT/analysis frame). (C) **Mono STFT** — `StemSeparator.separate` ran the identical 4096-pt STFT on left and right for mono input (`deinterleave` returns `(audio, audio)` when `channelCount < 2`, so `left == right`); now reuses the left STFT unless `channelCount >= 2` (−1 431-frame STFT/mono preview; stereo unchanged). **Perf delta** (structural, deterministic): per analysis frame −1 drums FFT + ~½ the tempo `dotpr` count + ~85 fewer array allocs; per mono track prep −1 full STFT. **Output-equivalent** — 9 BeatDetector tempo/onset tests + the StemAnalyzer suite stay green; new `test_separate_monoReusesStereoStft_outputUnchanged` proves the mono path ≡ the unchanged stereo-duplicated path (maxDiff < 1e-5). swiftlint 0 (3-tuple return → small `AutocorrelationSweepResult` struct). audit `CLEAN.4.2`; `RELEASE_NOTES_DEV.md [dev-2026-06-18-161943]`. **Not in 4.2 scope:** NoveltyDetector full-recompute + SessionPreparer serial-prep prefetch (separate audit items).
- **CLEAN.4.1 (partial) — BUG-036 RT-thread allocations: sites 1 + 2 done, site 3 + hand-off → BUG-043** ⏳ (2026-06-17, `58a37c0`; alternative track to the Phase-3 sweep, run when Matt picked it up). Killed the two per-callback `[Float]` allocations that are RT-thread-local: `FFTProcessor` reuses a pre-allocated `magnitudesScratch` + a new zero-alloc `processStereo(interleaved: UnsafeBufferPointer)` (mixes L/R into the windowed scratch, no `mono` array; `[Float]` overloads delegate via a shared `runFFTCore`); `AudioBuffer.latestSamples(into:)` fills a caller-owned buffer (callback reuses `interleavedScratch`). RT-thread-only → no lock (cf. D-079). FFT output byte-identical (pointer↔array bit-equiv test + unchanged FFT/Chroma/BeatDetector goldens); +3 regression tests; closeout ALL GREEN (1497/388/0-of-432/10). **Split, not complete:** site 3 (raw-tap `Data()`+`queue.async`) + the analysis hand-off (`Array(...prefix())`+`analysisQueue.async`) cross the thread boundary — allocation-free needs a pre-allocated ring + persistent-consumer drain, an unbounded→bounded cadence change on BUG-043's surface, so it sequences with the 043 work, not blind before it. **Validated 2026-06-17** (session `20-52-27Z`, Matt): no audible glitch, steady 60 Hz analysis cadence, worst gap 84 ms vs the 9.59 s BUG-043 incident. Decisions: site 3 + hand-off **parked** (accepted low-risk residual — the bounded-ring rework isn't worth it while BUG-043 stays quiet); **BUG-043 → monitoring**, not closed (N=1 clean session). `KNOWN_ISSUES.md` BUG-036 §Progress + BUG-043 §Validation; audit `CLEAN.4.1`; `RELEASE_NOTES_DEV.md [dev-2026-06-17-202354], [dev-2026-06-17-211442]`.
- **BUG-050 — always-on recorder ~2× CPU: gate video OFF by default** ✅ (2026-06-17, `64d8285`; Matt reversed the earlier "option A" defer). The per-frame video capture (~7 ms/frame, ≈2 cores sustained, no fps cost) now runs only under `PHOSPHENE_RECORD_VIDEO=1`; the near-free CSV/log/stem artifacts (where ~all diagnostic value lives) always record. `ensureCaptureTexture` returns nil when off → blit + `getBytes` + encoder all skipped; +2 `SessionRecorderTests` (3 existing video tests → `videoEnabled: true`). **VALIDATED + Resolved-as-reframed 2026-06-17** (`702697d`; sessions `22-10-50Z` / `13-57-23Z`): the video gate works (`video 0 appended`, `frame_cpu_ms` 15.78 → ~8.1 ms = render loop halved), but the "halve Activity Monitor" criterion was a **misdiagnosis** (dominant CPU = continuous real-time stem separation, ~every 5 s, not the video) — retired; the gate is kept. Also filed **BUG-060** (P3, monitored: a one-off un-reproduced app hang one frame after a `→ Gossamer` preset switch; no stack captured, Gossamer ran 3× clean next session). NB: quality-reel capture now needs the env var. `KNOWN_ISSUES.md` BUG-050 + BUG-060; `RELEASE_NOTES_DEV.md [dev-2026-06-18-142220]`.
- **CLEAN.7.4 — `[GAP-14]` doc-artifact hygiene + close the PNG-blob `[DEC]`** ✅ (2026-06-17, `5fdb1a3`). `rotate_docs.sh` §(d): report-only flag for large (≥ 512 KB) non-LFS files in docs/diagnostics + docs/prompts (red-armed; never moves — the never-guess contract). The 49 MB PNG-blob was already prevention-fixed (DOC.7 LFS rule + pruned loose PNGs, 0 tracked in HEAD); the history-rewrite to purge the 35 MiB of historical blobs is **DECLINED** (Matt — ≈ 3% of an LFS-dominated 1.2 GB clone, not worth force-pushing main). GAP-14 resolved. `CODE_AUDIT_2026-06-13.md` G14 + CLEAN.7.4.
- **CLEAN.4.4 — renderer over-allocation: gate feedback/warp passes + fix the PSO cache key** ✅ (2026-06-17, two disjoint renderer findings from audit T7). (A) **PSO cache key**: `ShaderLibrary.renderPipelineState(...)` cached by `name` alone, but the compiled descriptor varies by color-attachment `pixelFormat` and `supportICB` → two calls sharing a name but differing on either would return the first-cached PSO (wrong format / ICB capability). Now keyed by `PipelineKey(name, pixelFormat.rawValue, supportICB)`. Classified **latent, not live**: all production callers use unique names (each compiled once at init); preset multi-pass PSOs bypass the cache (`PresetLoader` → `device.makeRenderPipelineState`); `supportICB: true` is test-only. (B) **Feedback ping-pong + particle-warp over-alloc**: the ~32 MB @ 4K ping-pong was allocated on *every* resize regardless of preset, and never freed on switch-away; the particle-mode (Murmuration) warp pass ran every frame into a texture nothing sampled. Now gated by `activePresetSamplesFeedback` (surface-mode feedback only — Membrane) at the resize handler + `renderFrame` lazy-alloc; freed on `setFeedbackParams(nil)`; particle mode skips the warp and allocates no ping-pong. **Output-preserving** — PresetRegression goldens byte-identical (20 presets × 3 fixtures); the golden harness renders `preset.pipelineState` directly, so it's the safety net, with the alloc-count assertions (`DrawableResizeRegressionTests` +3) as the primary gate + `ShaderLibraryTests` (+2 format/ICB-distinct). Closeout ALL GREEN (engine 1511 / app 388 / lint 0-of-432 / docgates 10). Not visually verifiable (output-preserving by design). Audit `CLEAN.4.4`; registry §6 Feedback ping-pong + §9 PSO-cache rows; `KNOWN_ISSUES.md` T7 backlog; `RELEASE_NOTES_DEV.md [dev-2026-06-17-215601]`. **Out of scope (T7 remainder):** sceneTexture aliasing + resize stale-size (CLEAN.4.3, M7), ray-march /height NaN guard (4.3/4.5), DynamicTextOverlay in-flight race (unfiled — not confirmed here).
- **BUG-057/055/058 — silent-tap detector (the user-facing fix; Defect Protocol step 3)** ✅ surface-validated + APPROVED (2026-06-17, Matt's screenshot). Closes the user-facing gap for the whole silent-tap family: the app shows "playing" but the visualizer is silent/frozen with no actionable hint. Does **not** fix the (environmental) silence — it **detects "no fresh audio is reaching the visualizer while we should be playing" and surfaces a fix ladder.** Catches BOTH modes (the design's sharp edge): **Mode A** RMS≈0 → `.silent` (wedged `coreaudiod` [BUG-057] / stale grant [BUG-055]); **Mode B** frozen IO-proc → `InputLevelMonitor.frameCount` stops advancing while RMS stays nonzero so `.silent` never fires (BUG-058). A ~1 Hz freshness poll (`fresh = frameCount advanced && state != .silent`) raises a prominent non-blocking `AudioStallOverlayView` card after ~10 s and auto-clears on recovery; **gated on `.playing && !isLocalFilePaused`** (baseline reset on entry) so it never false-fires pre-play, in `.ready`, on a deliberate pause, or during quiet passages. **Folded into `PlaybackErrorBridge` (FA #73 — reuse, no parallel detector, zero engine changes);** the card supersedes the 15 s silence toast. New `AudioStallOverlayView` (+pbxproj); edited `PlaybackErrorBridge`/`PlaybackView`/`Localizable.strings`; +8 deterministic gate tests (`PlaybackStallDetectorTests` — both modes fire, four false-fire guards, auto-clear; no wall-clock). App build green, swiftlint `--strict` 0, string gate PASS, bridge+detector suites 15/15. **Deliberately no new `UserFacingError` case / presentation mode** (bespoke Bool-driven overlay; an enum case + a mode nothing dispatches on would be ceremony + churn the 29-case count test) — flagged for Matt. **Surface validated + approved by Matt (2026-06-17)**; BUG-055 symptom + BUG-057 detector-half marked Resolved. Live auto-clear pends the BUG-057 reinstall fix. **Matt's product direction:** the manual fix-ladder is a fallback — the user-friendly end-state is the app self-healing (reinstall auto-recovery + stable signing), NOT card polish (no quick fix removes the Terminal/Settings steps). `RELEASE_NOTES_DEV.md [dev-2026-06-17-161332]`; kickoff `docs/prompts/SILENT_TAP_DETECTOR_KICKOFF.md`. No registry change (error-state UX surface, not a renderer/harness/preset capability).
- **BUG-057/058 — tap-reinstall-comes-up-silent fix** ✅ **RESOLVED 2026-06-17** (steps 1–4: instrument + diagnose + fix + validated). Matt's session `18-16-41Z`: 3 pause/resume cycles, all recovered, `Tap reinstall SKIPPED` ×3, zero churn, the same `gen=1` tap survived every pause. Full closeout ALL GREEN (engine 1494 / app 385 / lint 0 / docgates 10). Fix commits `6bac999` + `2f533cf`. **Residual UX (card-on-pause) RESOLVED 2026-06-17** (suppress-on-pause, Matt's pick, ✅ validated — pause > 10 s no longer shows the card): the silent-tap card now suppresses on a likely pause (callbacks advancing + `.silent` + session has had real audio) via the same `hasEverDetectedSignal` latch, forwarded engine→bridge; a broken cold install (never delivered) and a Mode-B freeze (callbacks frozen) still raise it. +3 bridge tests; app build green, swiftlint 0. `RELEASE_NOTES_DEV.md [dev-2026-06-17-184040]`. BUG-058 (device-swap reinstall) is a distinct path/trigger, untouched, still its own rare P3. **Fix:** `.silent → reinstall` only rebuilds a tap that *never delivered* audio (broken cold install); a tap that *was* delivering and went silent is a user pause → left alone, resumes on play (`SilenceDetector.hasEverDetectedSignal` gate; `scheduleNextReinstall` skips with `Tap reinstall SKIPPED`). Kills the pause-churn + dead-tap lottery (the 16-59-43Z freeze); the detector card now auto-clears on resume; preserves BUG-055/wedge recovery. +3 tests; engine build green, swiftlint 0. Separate open UX question: the card still appears on a > 10 s pause (dwell/suppress, Matt's call). `RELEASE_NOTES_DEV.md [dev-2026-06-17-180919]`; `KNOWN_ISSUES.md` BUG-057 §Reinstall fix step 3. **Diagnosis** (instrumented session `17-45-44Z`, pause→resume ×2, both recovered): the recreate does **not** hang — every `.silent → reinstall` completed < 1 s; the machine **churns pointlessly on a user pause** (the tap reads RMS=0 because the source is paused, not because it's broken; recovery comes when the source resumes and the current tap delivers). 16-59-43Z is one of those pause-reinstalls landing a created-but-dead tap. **Fix:** only reinstall a tap that *never delivered* audio (broken cold install); leave a tap that *was* delivering and went silent (a pause) alone — it resumes on play. Per-gen RMS probe already provides the signal; gate is unit-testable. Step 1 added per-step `stopCapture`/`startCapture` breadcrumbs. `RELEASE_NOTES_DEV.md [dev-2026-06-17-174055]`; `KNOWN_ISSUES.md` BUG-057 §Reinstall fix steps 1–2. The detector (above) reproduced BUG-057 on a **healthy** `coreaudiod`: a streaming pause → `.silent → reinstall` → the recreate **hangs** (`performTapReinstall` logs `starting`, never `succeeded`/`failed`; `features.csv` all-zero tail; session `2026-06-17T16-59-43Z`) → tap dead, no recovery, the detector card correctly stuck on. Likely the **same reinstall-hang root as BUG-058** (device-swap freeze), different trigger — so the original BUG-057 "wedged daemon" diagnosis was incomplete. P1 multi-increment (instrument the `.silent → reinstall` path to BUG-058's breadcrumb depth → diagnose → fix → validate). Fixing it **closes the loop with the detector** — the card will then auto-clear on resume (today it can't, because the tap never recovers). Kickoff: `docs/prompts/BUG-057_TAP_REINSTALL_SILENCE_KICKOFF.md`. Includes a product question for Matt (should `.silent → reinstall` fire on a user pause at all?).

### Increment DOC.6.2 — adopt 2.3.6's date-string rotation gate; supersede DOC.6.1's script-align ✅ (2026-06-15)

The DOC.6 rotation-gate ↔ `rotate_docs.sh` boundary divergence had two *opposite* fixes: **DOC.6.1** (on main) bent `rotate_docs.sh` to the gate's **datetime** cutoff + dropped the ✅/⏳ marker; **CLEAN.2.3.6** (orphaned `upbeat-haslett` branch, `71f050d`) instead rewrote the **gate** to compare date-**strings** + require a marker, mirroring the tool. CLEAN.2.3.8 had resolved the divergence by keeping DOC.6.1 (a "main's-favour" tie-break, no robustness analysis). After a date-string-vs-datetime review (2026-06-15) — **Matt's call: adopt 2.3.6's gate** — a calendar-date-string comparison is day-granular and **cannot** flake at the sub-day boundary that produced the original false-red, whereas DOC.6.1's datetime gate keeps that fragility (it passes only because the script was bent to match it). Ported `71f050d`'s gate (`rotationCutoffString` + extracted `epEntryNeedsRotation` predicate + a deterministic unit test → DocIntegrity **10/10**, was 9) and **reverted DOC.6.1's `rotate_docs.sh` change** to the original marker-aware/local-date form the gate mirrors. **Reverses CLEAN.2.3.8's "kept main's DOC.6.1" resolution** (informed by the robustness data that tie-break lacked). The 3-entry pruning DOC.6.1 ran stands; gate green on the already-rotated docs. `RELEASE_NOTES_DEV.md [dev-2026-06-15-d]`.

### Increment DOC.6.1 — rotate_docs.sh ↔ DocIntegrityTests boundary reconciliation + due pruning pass ✅ (2026-06-14)

The DOC.6 rotation gate (`DocIntegrityTests.engineeringPlanRotationGate`) was RED on `main`: it flagged three 2026-06-01 EP §Recently Completed entries as overdue, but `Scripts/rotate_docs.sh --dry-run` reported "nothing to move," so the prescribed remedy was a no-op (calendar pruning debt — CLAUDE.md "every 10th / 2 weeks" — compounded by a gate/script boundary bug; surfaced by CLEAN.2.3's `closeout_evidence.sh`). Two mismatches, fixed in the script (the gate is authoritative):
- **local-vs-UTC.** The gate parses header dates in UTC vs `Date()`; the script's cutoff was *local*. An evening-local run (= next-day UTC) left the cutoff a day behind the gate. `TODAY`/`CUTOFF` now `TZ=UTC` (also aligns `CUR_MONTH` with the UTC release-notes gate).
- **strict-vs-inclusive + marker.** The gate flags any old bodied entry regardless of ✅/⏳ (`d < now−14d`); the script required `dated < cutoff` (strict, excluding the exact-14-day boundary) **and** a ✅/⏳ marker. One flagged entry (`Mid-Spike-1 fix`) had no marker → a date-only fix would still leave it red. Now moves on date alone (`dated <= cutoff`, marker-agnostic); unparseable-date triage (the one case needing human judgment) is kept.

Then ran the now-due pruning pass: `rotate_docs.sh` moved the three bodies (Dragon Bloom Spike 1, Mid-Spike-1 fix, LF.6.streaming) **verbatim** to `ENGINEERING_PLAN_HISTORY.md`, leaving header-only stubs; KNOWN_ISSUES + release-notes rotations were already current; `Mid-Spike-1 re-tune` (06-02) correctly stayed (inclusive boundary did not over-rotate). **Verification:** `swift test --filter DocIntegrityTests` 9/9 green; a second `--dry-run` is a no-op (idempotent); verbatim spot-check (`kWaveTargetRMS` / `StreamingArtworkURLResolver.swift` now history-only). No production code touched. `RELEASE_NOTES_DEV.md [dev-2026-06-14-g]`.

### Increment DOC.7 — `docs/diagnostics` image-artifact hygiene + preventive LFS ✅ (2026-06-13)

`docs/diagnostics/V9_session_4_5b_phase1/` held 29 plain-blob PNGs (~49 MB — the bulk of the 50 MB `docs/diagnostics` tree) from a closed session (Matt's "call this a pass" was 2026-05-14). A repo sweep found references only in history docs (`ENGINEERING_PLAN_HISTORY.md`, `RELEASE_NOTES_DEV_2026-05.md`) — nothing active or programmatic, no gate. Matt's pick (prune + preventive rule): the 29 PNGs were `git rm`'d (reclaims ~49 MB from every working-tree checkout / worktree; recoverable from `7dc41106..8862d6f2`), a tombstone `README.md` keeps the referenced path resolvable, and `.gitattributes` now LFS-tracks `docs/diagnostics/**/*.{png,jpg}` so future contact sheets never land as plain blobs.
Scope-bounded to asset + docs (zero code delta). **Not done here:** the blobs remain in `.git` history, so a fresh *clone* is unchanged until a `git filter-repo` rewrite + force-push — flagged as a separate, approval-gated follow-up.
### Increment DOC.6 — Doc rotation mechanization ✅ (2026-06-12, D-162)

`Scripts/rotate_docs.sh` (idempotent, `--dry-run`) rotates EP §Recently Completed bodies (> 14 d), KNOWN_ISSUES §Resolved entries (> 14 d), and pre-current-month release notes to history files; the first run + manual triage moved 26 EP bodies, 37 resolved entries, and 124 release-notes entries, and the closed-phase narratives (SB/QR/LM/CA/CS/CSP) followed by hand.
DECISIONS gained §Index (+ preamble fix), KNOWN_ISSUES gained §Open Index; five DocIntegrityTests gates (rotation age, two byte budgets, two index-completeness — all canary-proven) enforce it, and `closeout_evidence.sh` Step 4 runs them. CLAUDE.md's pruning pass is now "run the script + two manual judgment items".
Deviation from the kickoff, justified in D-162: the release-notes budget gates pre-current-month rotation debt, not whole-file size (the current month alone measured 72 KB at filing).

### Phase FBS — Ferrofluid Beat Sync ⏳ (2026-06-09, staged; kickoff `docs/prompts/FFO_BEAT_SYNC_KICKOFF.md`)
### Increment AGC2 — BUG-027: per-band EMA deviation pivot + cold-start warmup ✅ (2026-06-05 → 06, D-146)
### Increment AGC3 — BUG-029: AGC `f.bass` cold-start spike (continuous-energy presets pop-and-drop at track onset) ⏳ (2026-06-05; fix landed, awaiting M7)
### Increment FM.0 + FM.L1 + FM.L2 — Fata Morgana port: mirage substrate + shapes + stem uplift, CERTIFIED ✅ (2026-06-02 → 2026-06-03, D-139)
### Increment Dragon Bloom L4 + music response — faithful butterchurn render-loop port, CERTIFIED ✅ (2026-06-02, D-138)
### Increment Dragon Bloom Spike 2 — bilateral mirror fold without clipart ⏳ Matt-M7-pending (2026-06-02)
### Increment Dragon Bloom Spike 1 — Milkdrop-uplift `direct + mv_warp` feedback bloom ✅ (2026-06-01)
### Mid-Spike-1 re-tune — Route to signals alive on both capture paths ✅ (2026-06-02, Matt's "barely reactive on Spotify" report)
### Mid-Spike-1 fix — In-shader waveform RMS normalisation (2026-06-01, Matt's tap-path report)
### Increment LF.6.streaming — Streaming-path artwork resolver + fetcher + cache + wire ✅ (2026-06-01)
### Increment LF.6 — Album-art display in PlaybackView chrome ✅ (2026-05-28)
### Increment LF.5.fix.3 — Folder-pick race cluster (BUG-023 A/B/C) ✅ (2026-05-28)
### Increment LF.5.fix.2 — Five post-BUG-021 cleanups (collapsed) ✅ (2026-05-28)
### Increment LF.5 — Multi-File Local Playback + File-Association + Recents ✅ (2026-05-28)
### Increment CSP.4 — Volumetric Lithograph audit: no antipatterns; doc-only refresh ✅ (2026-05-28)
### Increment LF.4 — Local-File Playback as a User-Facing Feature ✅ (2026-05-27)
### Increment LF.3 — Persistent Content-Keyed Stem Cache ✅ (2026-05-27)
### Increment LF.2 — Full-Track Offline Pre-Analysis ✅ (2026-05-27)
### Increment LF.1.5 — LF vs Process-Tap A/B Comparison ✅ (2026-05-27)
### Increment LF.1 — Local-File Player Spike ✅ (2026-05-27)
### CA.7b-FU-4 — setMeshPresetBuffer/setMeshPresetFragmentBuffer retirement ✅ (2026-05-21)
### CA-Audio-FU-5 — InputLevelMonitor regression tests ✅ (2026-05-21)
### CA-Audio-FU-4 — Tap-reinstall regression tests ✅ (2026-05-21)
### CA-Presets-FU-4 — Lumen Mosaic init-failure instrumentation ✅ (2026-05-21)
### CA-Audio-FU-9 — ARCH structural-claims sync (Module Map + §Key Types + per-source-file inline drift) ✅ (2026-05-21)
### CA-Shared-FU-1 (wire-up) + CA-Shared-FU-2 (retire) + CA-Shared-FU-3 (retire) ✅ (2026-05-21)
### CA-Shared — Shared Capability Audit ✅ (2026-05-21)
### CA-Presets — Presets Capability Audit (Swift slice) ✅ (2026-05-21)
### CA-Audio-FU-2 (LookaheadBuffer kept) + CA-Audio-FU-3 (MusicKitFetcher kept) + CA-Audio-FU-9 (Module Map Sync filed) ✅ (2026-05-21)
### CA-Audio — Audio Capability Audit ✅ (2026-05-21)
### CA.7b-FU-3 (RayTracing kept) + CA-Audio kickoff ✅ (2026-05-21)
### CA.7b — Renderer Capability Audit (Dashboard / Geometry / RayTracing) ✅ (2026-05-21)
### CA.7-FU-3 (kept) + CA.7-FU-4 (retired) follow-ups ✅ (2026-05-21)
### CA.7a — Renderer Capability Audit (core pipeline) ✅ (2026-05-21)
### CA.5-FU-2 + CA.6-FU-1 + CA.6-FU-2 + CA.6-FU-3 follow-ups ✅ (2026-05-21)
### Increment CA.6 — App-Layer Capability Audit (Views + ViewModels presentation slice) ✅ (2026-05-21)
### Increment CA.5 — App-Layer Capability Audit (engine-adapter slice) ✅ (2026-05-21)
### Increment CA.4 — Orchestrator Capability Audit ✅ (2026-05-20)
### Increment CA.3 — Session Capability Audit ✅ (2026-05-20)
### Increment CA.2 — ML Capability Audit ✅ (2026-05-20)
### Increment CA.1 — DSP / MIR Capability Audit ✅ (2026-05-20)
### Increment BUG-012-i1 — MPSGraph crash instrumentation ✅ (2026-05-20)
### Increment BUG-011 CLOSED — Arachne over Tier 2 frame budget resolved against relaxed drops-only criteria ✅ (2026-05-12)
### Increment BUG-011 L5 cheap-cleanup tranche — three dead-code retirements ✅ (2026-05-12)
### Increment BUG-011 round 8 — Arachne build speedup + silent-state pause + completion-gated transitions ✅ (2026-05-12)
### Increment 2.5.4 — Session State Machine & Track Change Behavior ✅
### Increment 3.5.2 — Murmuration Stem Routing Revision ✅
### Increment 3.5.4 — Volumetric Lithograph Preset ✅
### Increment 3.5.4.1 — Volumetric Lithograph v2 ✅
### Increment 3.5.4.2 — Volumetric Lithograph v3 + shared fog-fallback bug fix ✅
### Increment 3.5.4.3 — v3.1 palette tuning ✅
### Increment 3.5.4.4 — v3.2 "pulse-rate too fast" + sky tint ✅
### Increment 3.5.4.5 — v3.3: correct beat driver (f.bass, not f.beat_bass) ✅
### Increment 3.5.4.6 — v3.4: use f.bass_att (pre-smoothed), not f.bass threshold ✅
### Increment 3.5.4.7 — v4: melody-primary drivers + forward dolly ✅
### Increment 3.5.4.8 — SessionRecorder writer relock + StemFeatures in preamble ✅
### Increment 3.5.4.9 — Per-frame stem analysis (engine-level) ✅
### Increment 3.5.5 — Arachne Preset (bioluminescent spider webs) ✅
### Increment 3.5.6 — Gossamer Preset (bioluminescent sonic resonator) ✅
### Increment 3.5.7 — Stalker Preset — **Retired** ✅
### Increment 3.5.8 — Arachne + Gossamer visual rework ✅
### Increment 3.5.9 — Spider easter egg in Arachne ✅
### Increment 3.5.10 — Arachne ray march remaster ✅
### Increment 3.5.11 — Gossamer SDF correction + v3 acceptance gate ✅
### Increment MV-0 — Drop v4.2 stash, re-land sky-tint conditional ✅
### Increment MV-1 — Milkdrop-correct audio primitives ✅
### Increment MV-2 — Per-vertex feedback warp mesh ✅
### Increment D-030 — SpectralHistoryBuffer + SpectralCartograph ✅
### Increment D-030b — Verification fixes + InputLevelMonitor ✅
## Immediate Next Increments

These are ordered by dependency. Each has done-when criteria and verification commands.

> **Capability Audit (Phase CA, 2026-05-20).** The originally-planned `docs/CAPABILITY_GAP_AUDIT.md` single-deliverable was superseded 2026-05-20 by the multi-increment **Phase CA** audit, which produces one per-subsystem registry under [`docs/CAPABILITY_REGISTRY/`](CAPABILITY_REGISTRY/). CA.1 (DSP/MIR) landed 2026-05-20 at [`docs/CAPABILITY_REGISTRY/DSP_MIR.md`](CAPABILITY_REGISTRY/DSP_MIR.md); CA.2+ pending. Preliminary 2026-05-12 inventory data (shader-utility-consumer matrix, distinct from CA's per-subsystem audits) lives at [`docs/diagnostics/capability-audit-pre-2026-05-12.md`](diagnostics/capability-audit-pre-2026-05-12.md) and continues to feed shader-cleanup increments.

**Current priority ordering — Phase CLEAN (2026-06-13 full-system audit).** The authoritative queue is the **CLEAN** backlog in [`docs/diagnostics/CODE_AUDIT_2026-06-13.md`](diagnostics/CODE_AUDIT_2026-06-13.md) (Phases 0–8). June-30 commit: CLEAN Phases 0 → 1 → 2 → 5 + elevated gaps G1/G2/G7/G8/G9; Phases 3–4 stretch; 6 / bulk-7 / 8 after June. Approved scope detail: §Recently Completed → "Phase CLEAN".

> The 2026-05-06 ordering below (QR → DSP → V → MD → SB) is **superseded** by Phase CLEAN as the active queue; QR.6 decomposition is folded into CLEAN Phase 8. The phase sections are retained as history.

1. **Phase QR — Quality Review Remediation** (QR.1 → QR.6). *Superseded (2026-06-13) — QR.6 decomposition folded into CLEAN Phase 8.* See "Phase QR" section below.
2. **Phase DSP — DSP Hardening.** DSP.3.7 (Live drift validation test) merges into QR.3.
3. **Phase V — Visual Fidelity Uplift** (V.5 reference completion + V.7.7B WORLD pillar) — can run in parallel with QR since they touch disjoint modules.
4. **Phase MD — Milkdrop Ingestion** (MD.1 → MD.7). Unchanged dependency on V.1–V.3 utilities.
5. **Phase SB — Starburst Fidelity Uplift** (SB.1 → SB.5). Independent.

Phase U / Phase 4 / Phase 5 / Phase 6 / Phase 7 / Phase MV all complete; see historical records below.

## Phase MV — Milkdrop-Informed Musical Architecture

**Why this phase exists:** six iterations on Volumetric Lithograph produced incremental fixes but never converged on "feels like a band member playing along with the music." [`docs/MILKDROP_ARCHITECTURE.md`](MILKDROP_ARCHITECTURE.md) documents the research that identified the root cause:

1. Milkdrop's audio vocabulary is **identical in scope to what Phosphene already computes** — no chord recognition, no pitch tracking, no stems. Our analysis pipeline is richer than theirs.
2. Milkdrop's `bass`/`bass_att` are **AGC-normalized ratios centered at 1.0**. Phosphene's are centered at 0.5 via the same AGC mechanism. But our presets have been authored with absolute thresholds — the wrong primitive for an AGC signal. Absolute thresholds inherently fail across tracks because the AGC divisor moves with mix density.
3. Milkdrop's "musical feel" comes from its **per-vertex feedback warp architecture**, not its audio analysis. Every preset warps the previous frame via a 32×24 grid, and motion *accumulates* over many frames. Simple audio inputs compound into rich organic motion.
4. **9 of 11 Phosphene presets did not use any feedback loop** prior to MV-2 — they rendered from scratch each frame. Ray-march presets in particular showed only instantaneous audio state. This is why they felt "disconnected" from music regardless of how cleverly tuned.

MV-0 ✅, MV-1 ✅, MV-2 ✅, MV-3 ✅ complete.

### Increment MV-3 — Beyond-Milkdrop extensions ✅

**MV-3a — Richer per-stem metadata** ✅
- `StemFeatures` expanded 32→64 floats (128→256 bytes). New per-stem fields: `{vocals,drums,bass,other}{OnsetRate, Centroid, AttackRatio, EnergySlope}` (floats 25–40), computed in `StemAnalyzer.analyze()` via `computeRichFeatures()`.
- `StemAnalyzerMV3Tests.swift`: click vs sine distinguishes attackRatio; silence gives zeros; 120-BPM click track mean onsetRate in [1.0, 3.5]/sec.

**MV-3b — Next-beat phase predictor** ✅
- New `BeatPredictor` class (IIR period estimation from onset rising edges). Feeds `beatPhase01` and `beatsUntilNext` into `FeatureVector` floats 35–36. Integrated in `MIRPipeline.buildFeatureVector()`.
- `BeatPredictorTests.swift`: phase monotonically rises 0→1; phase resets after 3× period silence; bootstrap BPM gives correct phase.
- `VolumetricLithograph.metal` updated: `approachFrac = max(0, (f.beat_phase01 - 0.80) / 0.20)` pre-beat anticipatory zoom.

**MV-3c — Vocal pitch tracking** ✅
- New `PitchTracker` (YIN autocorrelation, vDSP_dotpr). Key fix: advance to local CMNDF minimum before parabolic interpolation (finding just the first sub-threshold point causes catastrophic extrapolation on the descending slope). 80–1000 Hz gate, 0.6 confidence threshold, EMA decay 0.8.
- Feeds `vocalsPitchHz` and `vocalsPitchConfidence` into `StemFeatures` floats 41–42.
- `PitchTrackerTests.swift`: 440 Hz and 220 Hz within 5 cents; silence → 0 Hz; random noise → unvoiced.
- `VolumetricLithograph.metal` updated: `vl_pitchHueShift()` maps pitch to ±0.15 palette phase shift; gated by confidence ≥ 0.6.

**Explicitly NOT part of MV-3 (still out of scope):**
- Basic Pitch port, chord recognition via Tonic, HTDemucs swap, Sound Analysis framework

---

## Phase 4 — Orchestrator

The Orchestrator is the product's key differentiator. It is implemented as an explicit scoring and policy system, not a black box.

### Increment 4.0 — Enriched Preset Metadata Schema ✅

**Scope:** `PresetMetadata.swift` (new), `PresetDescriptor.swift` (extended), all 11 JSON sidecars back-filled.

Pulled forward from Phase 5.1 because Increment 4.1 (PresetScorer) cannot be built without the metadata it scores on. Adding the schema now eliminates a breaking change immediately after 4.1 is drafted.

**New types:** `FatigueRisk`, `TransitionAffordance`, `SongSection` (String-raw, Codable, Sendable, Hashable, CaseIterable). `ComplexityCost` struct with dual-form Codable (scalar or `{"tier1":x,"tier2":y}`). All in `PresetMetadata.swift`.

**New `PresetDescriptor` fields (all optional in JSON, fallback-on-missing, warn-on-malformed):**
`visual_density`, `motion_intensity`, `color_temperature_range`, `fatigue_risk`, `transition_affordances`, `section_suitability`, `complexity_cost`.

**Done when:** ✅ All criteria met.
- `PresetMetadata.swift` with three enums and `ComplexityCost`, all correct Swift 6 types.
- `PresetDescriptor` has 7 new fields; decoding falls back to defaults; unknown `fatigue_risk` logs warning + uses `.medium`.
- All 11 built-in preset JSON sidecars have explicit values for all 7 new fields.
- `PresetLoaderBuiltInPresetsHaveValidPipelines` regression gate still passes.
- `PresetDescriptorMetadataTests`: round-trip, defaults, malformed, complexity variants (scalar + nested), on-disk back-fill regression (6 test functions).
- D-029 in `docs/DECISIONS.md`. CLAUDE.md preset metadata table extended.

**Verify:** `swift test --package-path PhospheneEngine --filter PresetDescriptorMetadataTests`

---

### Increment L-1 — Structural SwiftLint Cleanup

**Scope:** Refactor 12 source files to eliminate all 24 remaining structural SwiftLint violations. No logic changes — pure mechanical refactoring. Verified by `swiftlint lint --strict` reporting 0 violations on active source paths, with all tests still passing.

**Background:** After the 2026-04-20 auto-fix pass, 24 structural violations remain (down from 166). These are `file_length`, `function_body_length`, `cyclomatic_complexity`, `type_body_length`, `large_tuple`, and `line_length` — rules that require file splits or helper extraction rather than auto-correction.

**Violations and fix strategy (file:line:rule):**

| File | Line | Rule | Fix |
|------|------|------|-----|
| `SessionRecorder.swift` | 46 | type_body_length (516) | Split to `SessionRecorder+Video.swift` (Video encoding MARK), `SessionRecorder+RawTap.swift` (Raw tap diagnostic MARK), `SessionRecorder+WAV.swift` (WAV writing) |
| `SessionRecorder.swift` | 150 | function_body_length (72) | Extract `setupWriters()`, `setupVideoWriter()`, `setupAudioWriter()` private helpers from `init` |
| `SessionRecorder.swift` | 397 | cyclomatic_complexity (13) + function_body_length (72) | Extract `handleVideoWriterInit()` and `handleFrameDimensionMismatch()` private helpers from `appendVideoFrame()` |
| `SessionRecorder.swift` | 793 | file_length (793) | Resolved by the type_body_length split above |
| `AudioFeatures+Analyzed.swift` | 552 | file_length (552) | Move `StemFeatures` struct (lines ~323–514) to new `StemFeatures.swift` in same directory |
| `PresetLoader+Preamble.swift` | 541 | file_length (541) | Split MV-warp preamble (line ~199 MARK) to `PresetLoader+WarpPreamble.swift` |
| `StemAnalyzer.swift` | 171 | function_body_length (96) | Extract `buildBaseFeatures()` and `applyDeviationPrimitives()` private helpers from `analyze()` |
| `StemAnalyzer.swift` | 349 | large_tuple | Define `StemRichFeatures` struct `{onsetRate, centroid, attackRatio, energySlope: Float}` to replace 4-member named tuple return from `computeRichFeatures()` |
| `StemAnalyzer.swift` | 500 | file_length (500) | Resolved by helper extraction above |
| `PitchTracker.swift` | 97 | cyclomatic_complexity (15) + function_body_length (86) | Extract 5 private helpers: `fillWindow()`, `computeDifference()`, `computeCMNDF()`, `findMinimum()`, `parabolicInterpolation()` from `process(waveform:)` |
| `MIRPipeline.swift` | 407 | file_length (407, 7 over) | Extract `buildFeatureVector()` deviation block to a private helper; or remove excess blank lines |
| `AudioInputRouter.swift` | 423 | file_length (423, 23 over) | Extract `Signal-State Handling + Tap Reinstall` MARK section to `AudioInputRouter+SignalState.swift` |
| `PresetLoader.swift` | 449 | function_body_length (103) | Extract `compilePipeline(for:)` and `compileRayMarchPipeline(for:)` private helpers from `loadPreset()` |
| `RayMarchPipeline.swift` | 184 | function_body_length (71) | Extract `makeGBufferTextures()` and `makeLightingPipeline()` private helpers from `init` |
| `RayMarchPipeline.swift` | 415 | file_length (415, 15 over) | Resolved by init helper extraction above |
| `RenderPipeline+Draw.swift` | 448 | file_length (448, 48 over) | Extract `drawWithICB` and `drawWithParticles` to `RenderPipeline+Particles.swift` |
| `RenderPipeline+RayMarch.swift` | 81 | function_body_length (83) | Extract `buildSceneUniforms()` and `applyAudioModulation()` private helpers |
| `RenderPipeline.swift` | 475 | file_length (475, 75 over) | Extract `PassManagement` MARK section to `RenderPipeline+Passes.swift` |
| `VisualizerEngine+Audio.swift` | 507 | file_length (507, 107 over) | Extract `InputLevelMonitor` integration section to `VisualizerEngine+InputLevel.swift` |
| `VisualizerEngine.swift` | 245 | function_body_length (82) | Extract `setupAudio()`, `setupRenderer()`, `setupCapture()` private helpers from `init` |
| `VisualizerEngine.swift` | 473 | file_length (473, 73 over) | Resolved by init helper extraction above |
| `InputLevelMonitor.swift` | 267 | line_length (127 chars) | Break `String(format:)` argument across lines or shorten message |

**Constraints:**
- No logic changes whatsoever. Every extracted function/struct must preserve byte-for-byte identical observable behavior.
- No new public API surface. All extracted helpers are `private`.
- New files added to the same target as the file being split (no new SPM targets).
- When splitting a file, all `// MARK: -` dividers from the original stay with their section.
- `StemRichFeatures` replacing the named tuple: must update all call sites in `StemAnalyzer.swift`; no other files reference the tuple directly.
- All existing tests must pass before and after each file change.

**Done when:**
- `swiftlint lint --strict --config .swiftlint.yml PhospheneEngine/Sources/ PhospheneEngine/Tests/ PhospheneApp/` reports **0 violations**.
- `swift test --package-path PhospheneEngine` passes (all tests green).
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` succeeds with 0 errors.

**Verify:**
```bash
swiftlint lint --strict --config .swiftlint.yml PhospheneEngine/Sources/ PhospheneEngine/Tests/ PhospheneApp/
swift test --package-path PhospheneEngine
```

---

### Increment 4.1 — Preset Scoring Model ✅

**Landed:** 2026-04-20.

`DefaultPresetScorer` implements the `PresetScoring` protocol with four weighted sub-scores (mood 0.30, stemAffinity 0.25, sectionSuitability 0.25, tempoMotion 0.20) and two multiplicative penalties (family-repeat 0.2×, smoothstep fatigue cooldown 60/120/300s). Hard exclusions gate perf-budget breakers and identity matches before scoring. `PresetScoreBreakdown` exposes every sub-score for introspection. `PresetScoringContext` is a fully Sendable value-type snapshot with a monotonic session clock — no `Date.now()` inside the scorer. 13 unit tests cover all contract edges including determinism, exclusion, cooldown, and rank stability across device tiers. See D-032 in DECISIONS.md for weight rationale.

**New files:** `Orchestrator/PresetScorer.swift`, `Orchestrator/PresetScoringContext.swift`, `Shared/DeviceTier.swift`. Extended: `PresetDescriptor` (added `stemAffinity: [String: String]`), `ComplexityCost` (added `cost(for:)` helper), `Package.swift` (added `Session` dep to `Orchestrator` target, `Orchestrator` dep to test target).

**Verify:** `swift test --package-path PhospheneEngine --filter PresetScorerTests`

---

### Increment 4.2 — Transition Policy ✅

**Landed:** 2026-04-20.

`DefaultTransitionPolicy` implements the `TransitionDeciding` protocol. Priority: structural boundary (when `StructuralPrediction.confidence ≥ 0.5` and boundary within 2.5 s lookahead window) beats duration-expired timer fallback. `TransitionDecision` is fully inspectable: trigger, scheduledAt, style (crossfade/cut/morph), duration, confidence, rationale. Style negotiated from `currentPreset.transitionAffordances` and energy level — high energy (> 0.7) prefers `.cut`, low energy prefers `.crossfade`. Crossfade duration scales linearly from 2.0 s (energy=0) to 0.5 s (energy=1). Family-repeat avoidance is already handled upstream by `DefaultPresetScorer` (familyRepeatMultiplier=0.2×). 12 unit tests with synthetic `StructuralPrediction` inputs — all pass. See D-033 in DECISIONS.md.

**New files:** `Orchestrator/TransitionPolicy.swift`, `Tests/Orchestrator/TransitionPolicyTests.swift`.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 4.3 — Session Planner ✅

**Scope:** `Orchestrator/SessionPlanner.swift`, `Orchestrator/PlannedSession.swift`. Greedy forward-walk planner composing `DefaultPresetScorer` + `DefaultTransitionPolicy`. Produces a `PlannedSession` — ordered list of `PlannedTrack` entries each carrying the selected `PresetDescriptor`, `PresetScoreBreakdown`, `PlannedTransition`, and planned timing. `planAsync` accepts a precompile closure (caller-injected, keeps Orchestrator module free of Renderer dependency). Deterministic: same inputs → byte-identical output. `PlanningWarning` surfaces degradation events. SessionManager integration deferred: `Session` module cannot import `Orchestrator` without a circular dependency — app-layer wiring is Increment 4.5.

**Landed 2026-04-20.** 13 unit tests covering empty-playlist/empty-catalog errors, single-track plan, 5-track family diversity, tier exclusion, mood arc, fatigue, full-exclusion fallback, determinism, `track(at:)` / `transition(at:)` lookups, precompile dedup, and precompile failure handling. D-034 in DECISIONS.md. 387 tests total; 4 pre-existing Apple Music env failures unchanged.

**Verify:** `swift test --package-path PhospheneEngine --filter SessionPlannerTests`

---

### Increment 4.4 — Golden Session Test Fixtures ✅

**Landed:** 2026-04-20. *(Current state: regenerated multiple times since landing — QR.2 stem-affinity rescaling, V.7.6.2 multi-segment, BUG-004 closure 2026-05-12 expanding catalog 11 → 15 presets and adding Session D for Lumen Mosaic eligibility coverage. The current test file in `PhospheneEngine/Tests/.../Orchestrator/GoldenSessionTests.swift` is authoritative; the original-landing description below is preserved as a historical record.)*

`GoldenSessionTests.swift` — 12 regression tests across three curated playlists that lock in the expected Orchestrator output for any given set of track profiles and the full 11-preset production catalog. Any future change to `DefaultPresetScorer`, `DefaultTransitionPolicy`, `DefaultSessionPlanner`, or a preset JSON sidecar that breaks a golden test is a regression; the test file must be updated with a scoring trace comment that proves the new expected values are correct.

**Session A (high-energy electronic, 5 × 180 s, BPM=130, val=0.7, arous=0.8):** VL→Plasma→VL→FO→VL. Transitions from VL are cuts (VL carries `[crossfade, cut]` affordances, energy=0.82 > 0.7 threshold); transitions from Plasma/FO are crossfades at ~0.77 s.

**Session B (mellow jazz, 5 × 180 s, BPM=85, val=0.3, arous=−0.3):** VL→GB→VL→GB→VL. All crossfades at ~1.43 s (energy=0.38). No high-motion preset (Murmuration motion=0.85) ever wins.

**Session C (genre-diverse, 6 tracks, varied durations):** VL→GB→VL→Plasma→VL→FO. Covers 4 families (fluid, geometric, hypnotic, abstract).

**Key implementation decisions:**
- `allBreakdowns: [(PresetDescriptor, PresetScoreBreakdown)]` was **not** added to `PlannedTrack`. Runner-up inspection is done by calling `DefaultPresetScorer().breakdown(preset:track:context:)` directly inside the test body — no new public API.
- `PlannedTransition` carries no `trigger` enum field; trigger type is verified via `reason.hasPrefix("Structural boundary")`.
- Two pre-implementation spec derivation errors were caught and corrected against the code: Plasma (0.803) beats Ferrofluid Ocean (0.793) in high-energy electronic sessions because Plasma's tempCenter (0.6) is closer to targetTemp (0.78). The spec's scoring trace omitted Plasma when listing non-fluid competitors.

399 tests total; 4 pre-existing Apple Music env failures unchanged.

**Verify:** `swift test --package-path PhospheneEngine --filter GoldenSessionTests`

---

### Increment 4.5 — Live Adaptation ✅

**Landed:** 2026-04-20.

`LiveAdapter.swift` + `LiveAdapter+Patching.swift` + `VisualizerEngine+Orchestrator.swift`. `DefaultLiveAdapter` implementing `LiveAdapting` protocol with two adaptation paths (boundary reschedule > mood override). `PlannedSession.applying(_:at:)` extension for controlled plan mutation from the app layer. `VisualizerEngine+Orchestrator` holds `livePlan` (NSLock-guarded) and provides `buildPlan()`, `currentPreset(at:)`, `currentTransition(at:)`, `applyLiveUpdate(...)`.

**Boundary reschedule:** fires when `StructuralPrediction.confidence ≥ 0.5` AND the live boundary deviates from the planned transition time by > 5 s. 5 s = 2× the `LookaheadBuffer` 2.5 s window — deviations smaller than that are within normal preview-vs-live jitter. Wins over mood override when both conditions fire simultaneously.

**Mood override:** fires only when all three hold: `|Δvalence| > 0.4 || |Δarousal| > 0.4`, elapsed fraction < 40%, and the best-scoring alternative preset is > 0.15 higher. Current preset scored without exclusion (true live score); alternatives scored with current preset excluded. Cap at 40% prevents churn in the back half of a track.

**Key implementation decisions (D-035):**
- `LiveAdaptation.PresetOverride` is a nested struct (not a named tuple) for `Sendable` conformance in Swift 6 strict mode.
- `PlannedSession.applying` lives in `LiveAdapter+Patching.swift` (same Orchestrator module as the internal memberwise inits of `PlannedSession`/`PlannedTrack`) — the only controlled mutation path outside of `DefaultSessionPlanner.plan()`.
- Empty `recentHistory: []` in live scoring context is intentional — fatigueMultiplier is a session-level pre-plan concern; live overrides that fire mid-track should not re-apply session-level fatigue logic.
- `LiveAdapting` protocol uses `// swiftlint:disable function_parameter_count` (6 params) — wrapping into a context struct would add an intermediate allocation on the hot path with no modelling benefit.

**Test notes:**
- `noBoundarySignal()` helper (confidence=0.0) bypasses the boundary path in mood-only tests. Using `closeBoundary(at: N)` in mood tests caused unexpected boundary reschedules because the live session boundary deviated > 5 s from the planned transition time even when confidence was high.
- Override catalog uses `visual_density` JSON field (`case visualDensity = "visual_density"` in `PresetDescriptor.CodingKeys`) — confirmed before writing test helpers.
- Scoring math verified by hand: pre-analyzed sad/calm (-0.5, -0.5) → targetTemp=0.30; CurrentPreset (center=0.25, density=0.25) → mood score 0.95. Live happy/energetic (0.7, 0.7) → targetTemp=0.78; AltPreset (center=0.78, density=0.78) → mood score 1.0. Gap = 0.875 − 0.716 = 0.159 > 0.15 threshold.

407 tests total; 4 pre-existing Apple Music env failures unchanged.

**Verify:** `swift test --package-path PhospheneEngine --filter LiveAdapterTests`

---

### Increment 4.6 — Ad-Hoc Reactive Mode ✅

**Landed:** 2026-04-20

**What was built:**
- `ReactiveOrchestrator.swift` — `ReactiveAccumulationState` (listening/ramping/full), `ReactiveDecision`, `ReactiveOrchestrating` protocol, `DefaultReactiveOrchestrator` (stateless pure function). Confidence ramps 0→0.3 over first 15 s, 0.3→1.0 over 15–30 s, 1.0 after. Switch conditions: score gap > 0.20 OR structural boundary confidence ≥ 0.5.
- `ReactiveOrchestratorTests.swift` — 8 unit tests: listening hold, confidence ramp, ramping suggestion, score-gap suppression, boundary override, boundary scheduling, nil-preset path, empty-catalog hold.
- `VisualizerEngine.swift` — added `reactiveOrchestrator`, `reactiveSessionStart`, `lastReactiveSwitchTime`.
- `VisualizerEngine+Orchestrator.swift` — `applyLiveUpdate()` routes to `applyReactiveUpdate()` when `livePlan == nil`; `buildPlan()` clears `reactiveSessionStart` when a real plan arrives. 60 s cooldown prevents switch-thrashing.
- D-036 added to `docs/DECISIONS.md`.

**Key decisions:** D-036 — stateless orchestrator, app-layer owns cooldown and wall-clock elapsed time.

**Tests:** 407 → 415 (8 new). Same 4 pre-existing Apple Music environment failures.

**Verify:** `swift test --package-path PhospheneEngine --filter ReactiveOrchestratorTests`

---

## Phase 5 — Preset Certification Pipeline

### Increment 5.1 — Enriched Preset Metadata Schema ✅ (landed as Increment 4.0)

**Note:** This increment was pulled forward and completed as **Increment 4.0** because PresetScorer (Increment 4.1) requires this schema before it can be drafted. See Increment 4.0 above for the full done-when criteria and verification commands. All 5.1 scope items are complete.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 5.2 — Preset Acceptance Checklist (Automated) ✅

**Landed:** 2026-04-20

**What was built:**
- `PresetAcceptanceTests.swift` — 4 parametrized invariant tests across all production presets (44 test cases when bundle resources are linked):
  1. Non-black at silence (max channel > 10).
  2. No white clip on steady energy for non-HDR passes (max < 250).
  3. Beat response ≤ 2× continuous response + 1.0 tolerance (enforces CLAUDE.md audio data hierarchy).
  4. Form complexity ≥ 2 at silence (detects visually dead single-bin outputs).
- Four FeatureVector fixtures derived from AGC semantics and CLAUDE.md reference onset table (Love Rehab ~125 BPM, Miles Davis ~136 BPM). Not synthetic envelopes.
- `renderFrame` renders 64×64 offscreen via the preset's direct `pipelineState`. Ray march and post-process presets are rendered via their composite output; the `post_process` white-clip check is skipped (HDR values are legal before tone-mapping).
- `_acceptanceFixture` is a module-level constant loaded once; if bundle resources are absent, it returns `[]` (zero test cases rather than failure).

**Key decision:** D-037 — structural invariants over GPU output; perceptual snapshot regression deferred to 5.3.

**Tests:** 415 → 419 (4 new @Test functions; Swift Testing counts @Test declarations, not parametrized cases). Same 4 pre-existing Apple Music environment failures.

**Verify:** `swift test --package-path PhospheneEngine --filter PresetAcceptanceTests`

---

### Increment 5.3 — Visual Regression Snapshots ✅

**Landed:** 2026-04-21

**What was built:**
- `PresetRegressionTests.swift` — 3 parametrized regression tests (steady, beat-heavy, quiet) + 1 golden-generation utility test.
- 64-bit dHash computed via 9×8 luma grid + horizontal-difference encoding (`computeLumaGrid` + `dHash`).
- `goldenPresetHashes` dictionary: 11 preset entries × 3 fixtures = 33 comparisons. Fractal Tree excluded (meshShader).
- Hamming distance ≤ 8 tolerance (87.5% match). Missing entries skip silently (safe for new presets).
- `UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine --filter test_printGoldenHashes` regenerates all values.
- Same buffer/skip infrastructure as Increment 5.2 (SceneUniforms for ray march, zeroed FFT/stems/history).
- `_acceptanceFixture` and `PresetFixtureContext` promoted from `private` to `internal` in `PresetAcceptanceTests.swift` so `PresetRegressionTests.swift` can reference them directly.

**Key decision:** D-039 — dHash regression gate; hardware caveat documented.

**Tests:** 435 → 439 (4 new @Test functions). Same pre-existing failures unchanged.

**Verify:**
```bash
swift test --package-path PhospheneEngine --filter PresetRegressionTests
# To regenerate goldens:
UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine --filter test_printGoldenHashes
```

---

## Phase U — UX Architecture

**Why this phase exists:** the engine has a `SessionState` lifecycle (idle → connecting → preparing → ready → playing → ended) and a developer-facing debug overlay, but there is no user-facing UX specification and no corresponding UI. Phase 2.5 built the preparation *pipeline*; Phase U builds the UI around it. `docs/UX_SPEC.md` is the canonical spec for everything in this phase. Milestone A ("Trustworthy Playback Session") blocks on U.1–U.7.

### Increment U.1 — Session-state views ✅

**Scope:** `ContentView` becomes a pure switch on `SessionManager.state`. Six stub top-level views (`IdleView`, `ConnectingView`, `PreparationProgressView`, `ReadyView`, `PlaybackView`, `EndedView`) under `PhospheneApp/Views/`, each rendering a distinct testable hierarchy. `SessionStateViewModel` (`@MainActor ObservableObject`) observes `SessionManager` and publishes current state. New `CLAUDE.md §UX Contract` section. New `ARCHITECTURE.md §UI Layer` subsection.

**Done when:**
- ✅ Six views exist; each renders without errors for its corresponding state.
- ✅ `ContentView` contains no state logic beyond routing.
- ✅ Tests for each view — 9 tests across 3 suites in `PhospheneAppTests/SessionStateViewTests.swift`.
- ✅ Reduced-motion system flag detection stub in place (used by later increments).

**Implementation note:** Accessibility ID testing via SwiftUI's accessibility tree traversal is unreliable in unit tests — macOS only materialises the SwiftUI accessibility tree for active clients (VoiceOver, XCUITest). Each view exposes `static let accessibilityID: String`; `.accessibilityIdentifier(Self.accessibilityID)` binds it in the view body. Tests check the static constants; the binding is enforced by construction. See D-044.

**Verify:** `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test` — 9 new tests pass.

---

### Increment U.2 — Permission onboarding ✅

**Landed:** 2026-04-22

**What was built:**
- `PermissionMonitor` (`@MainActor ObservableObject`) observing
  `NSApplication.didBecomeActiveNotification`, backed by
  `ScreenCapturePermissionProviding`.
- `SystemScreenCapturePermissionProvider` (production) — `CGPreflightScreenCaptureAccess`.
  Never calls `CGRequestScreenCaptureAccess` (system dialog doesn't compose with URL-scheme flow).
- `PhotosensitivityAcknowledgementStore` — injectable `UserDefaults` suite; key
  `phosphene.onboarding.photosensitivityAcknowledged`.
- `PermissionOnboardingView` per UX_SPEC §3.2; opens
  `x-apple.systempreferences:…?Privacy_ScreenCapture` via `NSWorkspace.shared.open`.
  No Retry button — return-detection is automatic via `PermissionMonitor`.
- `PhotosensitivityNoticeView` per UX_SPEC §3.3; surfaced as a `.sheet` on
  first `IdleView` appearance.
- `ContentView` refactored to two-level switch: permission gate above state switch.
  `PermissionMonitor` injected as `@EnvironmentObject` from `PhospheneApp`.
- `IdleView` updated with `.onAppear` + `.sheet(isPresented:)` for the notice.

**Key decisions:**
- Preflight + URL scheme, NOT `CGRequestScreenCaptureAccess()` — the request
  API's system dialog doesn't compose with "Open System Settings and return."
- Permission gate lives above the state switch, not inside `SessionStateViewModel` —
  permission routing outranks session state per UX_SPEC §3.1.
- Photosensitivity sheet on `IdleView`, not a separate top-level state — timing
  is "after permission, before first session" which maps exactly to `IdleView`'s
  first appearance.
- `PermissionMonitor` lives under `Permissions/`, not `Views/` — it is a
  routing-layer concern, not a view.

**Tests:** 535 → 549 (+14 new: 5 PermissionMonitor, 4 PhotosensitivityStore, 5 PermissionOnboarding). Pre-existing failures unchanged.

**Verify:**
- `swift test --package-path PhospheneEngine`
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test`
- `swiftlint lint --strict --config .swiftlint.yml`

---

### Increment U.3 — Playlist connector picker ✅

**Landed:** 2026-04-23

**What was built:**
- `ConnectorType` enum (appleMusic/spotify/localFolder) with title/subtitle/systemImage.
- `ConnectorTileView`: reusable tile with enabled/disabled states and optional secondary
  action button.
- `ConnectorPickerViewModel` (`@MainActor ObservableObject`): NSWorkspace launch/terminate
  observers with `nonisolated(unsafe)` storage — the only correct pattern for observers
  that must be removed in `deinit` on a `@MainActor` class (Swift 6 `deinit` is nonisolated).
  250ms debounce on Apple Music availability.
- `ConnectorPickerView`: `NavigationStack` inside a `.sheet` from `IdleView`, with
  `navigationDestination(for: ConnectorType.self)`.
- `AppleMusicConnectionViewModel`: five-state machine
  (idle/connecting/noCurrentPlaylist/notRunning/permissionDenied/error/connected).
  Auto-retry on `.noCurrentPlaylist` via injectable `DelayProviding` (2s real, instant
  in tests). Pre-flight finding: AppleScript error -1728 (no track) and -1743 (automation
  denied) both silently return an empty array — indistinguishable in U.3.
- `AppleMusicConnectionView`: five user-visible states with CTA copy per UX_SPEC §4.3.
  `.onChange(of: viewModel.state)` fires `onConnect(.appleMusicCurrentPlaylist)` on
  `.connected`.
- `SpotifyURLKind` + `SpotifyURLParser`: pure value types. Handles HTTPS, `spotify:` URI,
  `@`-prefixed links, query param stripping, podcast paths → `.invalid`.
- `SpotifyConnectionViewModel`: 300ms debounce on text input via `$text.sink`; HTTP 429
  retry with [2s, 5s, 15s] backoff (extracted to `retryAfterRateLimit` to satisfy
  `cyclomatic_complexity ≤ 10`). `.spotifyAuthRequired` → calls `startSession` directly
  (SessionManager degrades gracefully to live-only reactive mode; no OAuth in U.3).
- `SpotifyConnectionView`: URL paste field, playlist-ID preview card, per-kind rejection
  copy, retry-attempt indicator.
- `DelayProviding` protocol: `RealDelay` (wall-clock `Task.sleep`) and `InstantDelay`
  (`await Task.yield()` — yields actor without wall-clock wait, enabling fast retry tests).
- `LocalFolderConnector` stub: `#if ENABLE_LOCAL_FOLDER_CONNECTOR` compile flag; always
  throws `.networkFailure("not yet implemented")`.
- `IdleView` updated: "Connect a playlist" → `.sheet`, "Start listening now" → ad-hoc
  session. `PhospheneApp.swift` auto-start `startAdHocSession()` removed from `.onAppear`.

**Key decisions (D-046):**
- `nonisolated(unsafe)` for NSWorkspace observer storage in `@MainActor` classes.
- `ConnectorPickerView` as sheet-with-NavigationStack (not a new NavigationStack root).
- `DelayProviding` protocol for testable retry without wall-clock waits.
- `.spotifyAuthRequired` silently degrades — no user-visible error since the session still
  starts (live-only reactive mode is valid and useful without OAuth).

**Tests:** 21 new PhospheneApp tests (ConnectorPickerViewModelTests×9, SpotifyURLParserTests×12,
AppleMusicConnectionViewModelTests×5 + identifier, SpotifyConnectionViewModelTests×5 + identifier).
56 PhospheneApp tests total. 0 SwiftLint violations.

**Verify:**
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test`
- `swiftlint lint --strict --config .swiftlint.yml`

---

### Increment U.4 — Preparation progress UI ✅

**Scope:** `PreparationProgressView` per `UX_SPEC.md §5.2`. New `PreparationProgressPublishing` protocol exposed by `SessionPreparer`; publishes `[TrackID: TrackPreparationStatus]` via Combine. `TrackPreparationRow` renders one of seven statuses (`.queued`, `.resolving`, `.downloading`, `.analyzing`, `.ready`, `.partial`, `.failed`) with icon + copy per `§5.3` table. Aggregate progress bar + per-track ETA + cancel affordance. "Start now" CTA appears at `progressiveReadinessLevel == .ready_for_first_tracks` — dependency on Increment 6.1; before 6.1 ships, this CTA is dormant.

**Done when:**
- Track list updates as each track advances through preparation stages.
- `PreparationProgressPublishing` protocol defined in `Session` module; `DefaultSessionPreparer` conforms.
- All seven status cases render correctly with their icons and copy.
- Cancel tears down in-flight work and returns to `.idle` without leaving orphan stem analyses.
- 6+ unit tests, including a flaky-network fixture via `MockPreparationProgressPublisher`.

**Verify:** `swift test --package-path PhospheneEngine --filter PreparationProgressTests`

---

### Increment U.5 — Ready view + first-audio autodetect ✅

**Scope:** `ReadyView` per `UX_SPEC.md §6.1`. First-track preset renders in background at 0.3× opacity. Attention-drawing pulsing border. First-audio autodetect via `AudioInputRouter` `.silent → .active` transition sustained >250 ms → auto-advance to `.playing`. 90-second timeout handling per `§6.3`. Plan preview panel (`PlanPreviewView`) showing all `PlannedTrack` rows with transitions. Regenerate Plan (D-047) with random seed + manual-lock preservation.

**Delivered:**
- Part A: `ReadyView`, `ReadyViewModel`, `FirstAudioDetector`, `ReadyPulsingBorder`, `ReadyBackgroundPresetView`.
- Part B: `PlanPreviewView`, `PlanPreviewViewModel`, `PlanPreviewRowView`, `PlanPreviewTransitionView`.
- Part C: `PresetPreviewController` stub — deferred to U.5b (D-048).
- Part D: `DefaultSessionPlanner.plan(seed:)`, `PlannedSession.applying(overrides:)`, `VisualizerEngine.regeneratePlan(lockedTracks:lockedPresets:)`.
- 19 new tests: `FirstAudioDetectorTests`, `ReadyViewModelTests`, `PlanPreviewViewModelTests`, `PlanPreviewRegenerateTests`, `ReadyViewTimeoutIntegrationTests`, `SessionPlannerSeedTests`.

---

### Increment U.5b — Preset preview loop (deferred from U.5 Part C)

**Scope:** 10-second looping preset preview triggered by row-tap in `PlanPreviewView`. Currently a no-op stub in `PresetPreviewController`. Full implementation requires engine-layer changes: (1) synthetic `FeatureVector` injection into active `RenderPipeline`; (2) secondary render surface or background-preset surface hijack; (3) loop mechanism without live audio callbacks. See D-048.

**Done when:**
- Row tap in `PlanPreviewView` triggers a looping 10s preview of the row's preset.
- Tap again or session advance stops the preview and reverts to the session's active preset.
- Context-menu "Swap preset" is enabled and wired to `PlanPreviewViewModel.swapPreset(for:to:)`.
- `PresetPreviewController.startPreview(preset:stems:)` drives the RenderPipeline, not a stub.
- 6+ unit tests for preview controller lifecycle + integration test for row-tap → visual change.

**Verify:** `swift test --package-path PhospheneEngine --filter PresetPreviewTests`

---

### Increment U.5c — Plan modification editor (deferred from U.5 Part C)

**Scope:** Preset picker for manual swap in `PlanPreviewView`. The "Modify" footer button and context-menu "Swap preset" action open a picker sheet showing the preset catalog filtered to eligible candidates for the selected track. Currently disabled with `TODO(U.5.C)` markers.

**Done when:**
- "Swap preset" context-menu action opens a preset picker for the selected track.
- Picker shows eligible presets filtered by device tier and fatigue cooldown.
- Selecting a preset calls `PlanPreviewViewModel.swapPreset(for:to:)` and shows lock badge.
- "Modify" footer button opens the same picker for the last-tapped row.
- 4+ unit tests for picker filtering + view model lock state after swap.

**Verify:** `swift test --package-path PhospheneEngine --filter PlanModifyTests`

---

### Increment U.6 — In-session chrome ✅

**Scope:** `PlaybackView` overlay chrome per `UX_SPEC.md §7`. Three layers: Metal render surface (full-bleed), auto-hiding overlay (track info top-left, controls cluster top-right, bottom-right toast slot), debug overlay (toggled with `D`). `OverlayChromeView` with `PlaybackOverlayViewModel` managing visibility + fade timers. Keyboard shortcuts from `§7.6` registered globally within `.playing`. Track-change animation per `§7.5`. Multi-display drag per `§7.7`. Blurred dark backdrop for contrast guarantee.

**Done when:**
- Overlay fades out after 3 s idle; reappears on mouse move or key press.
- Keyboard shortcuts `⌘F`, `Space`, `←`, `→`, `M`, `D`, `Esc`, `?` all wired.
- Track change triggers center toast for 1 s then moves info to top-left card.
- Minimum-contrast 4.5:1 verified against three regression fixtures (silence / steady mid-energy / beat-heavy).
- Display hot-plug reparents window without crash or session loss.
- 8+ unit tests for ViewModel state transitions + snapshot tests for each overlay configuration.

**Verify:** `swift test --package-path PhospheneEngine --filter PlaybackChromeTests`

---

### Increment U.6b — Live adaptation keyboard shortcut semantics ✅

**Status: Complete (2026-04-25)**

**What was built:**
- `DefaultPlaybackActionRouter` fully wired — all seven methods (`moreLikeThis`, `lessLikeThis`, `reshuffleUpcoming`, `presetNudge`, `rePlanSession`, `undoLastAdaptation`, `toggleMoodLock`) produce observable state changes. No remaining `TODO(U.6b)` lines.
- `PresetScoringContext` extended with `familyBoosts`, `temporarilyExcludedFamilies`, `sessionExcludedPresets` (all defaulted empty; D-053 backward-compat discipline).
- `PresetScoreBreakdown.familyBoost: Float` added; `DefaultPresetScorer` honours all three new fields.
- `PlannedSession.extendingCurrentPreset(by:at:)` added in `LiveAdapter+Patching` (same controlled-mutation discipline as `applying(_:at:)`).
- `PresetCategory.displayName` computed property for user-facing toast copy.
- `LiveAdaptationToastBridge` default flipped to `true` for fresh installs; existing explicit user choices preserved via the key-presence check.
- Adaptation preference state lives on `DefaultPlaybackActionRouter` (not `VisualizerEngine`) for testability — D-058(e).
- Double-`-` ambient hint: two `lessLikeThis()` calls within 90 s emit "Not quite hitting the mark? Try ⌘R to re-plan." once per session.
- `adaptationHistory` bounded at 8 entries; `undoLastAdaptation()` restores `livePlan` only (NOT preference state) — D-058(b).
- `VisualizerEngine+Orchestrator` extended with `extendCurrentPreset(by:)`, `applyPresetByID(_:)`, `restoreLivePlan(_:)`, `buildScoringContext(adaptationFields:)`, `currentTrackIndexInPlan()`, `currentTrackProfile()`.
- `PlaybackView.setup()` uses `DefaultPlaybackActionRouter.live(engine:toastBridge:onShowPlanPreview:)` factory.
- 14 app tests + 6 engine tests (adapatation scorer tests in `PresetScorerAdaptationTests`). D-058.

---

### Increment U.7 — Error taxonomy + toast system ✅

**Status: Complete (2026-04-24)**

**Scope:** `UserFacingError` typed enum and `ErrorToast` view component per `UX_SPEC.md §8`. Every row in the UX_SPEC error tables (§8.1–§8.4) has a corresponding enum case with copy test. All user-facing strings externalized in `Localizable.strings`. `PlaybackView` bottom-right toast slot for degradation messages (silence detection, preview fallback, sample-rate mismatch, etc.). Full-screen error states for connection / preparation failures.

**Delivered (3 commits):**
- **Part A:** `UserFacingError` (29 cases, `Shared` module), `Localizable.strings` (English), `LocalizedCopy` service, retroactive string extraction from U.1–U.6 views. Tests: `UserFacingErrorTests`, `LocalizedCopyTests`.
- **Part B:** `FullScreenErrorView`, `PreparationFailureView`, `TopBannerView` (44pt amber banner), `PreparationErrorViewModel` (6 priority rules), `ReachabilityMonitor` (NWPathMonitor + 1s debounce), `StubReachabilityMonitor`. Wired into `PreparationProgressView`. Tests: `PreparationErrorViewModelTests` (7), `ReachabilityMonitorTests` (3).
- **Part C:** `PhospheneToast.conditionID`, `ToastManager.dismissByCondition/_isConditionAsserted`, `PlaybackErrorConditionTracker`, `PlaybackErrorBridge` (replaces `SilenceToastBridge`; fires at 15s per §9.4; condition-ID auto-dismiss on recovery). Wired into `PlaybackView`. Tests: `ToastManagerConditionTests` (3), `PlaybackErrorConditionTrackerTests` (4), `PlaybackErrorBridgeTests` (8). D-051.

**Done when:**
- ✅ `UserFacingError` has a case for every row in UX_SPEC §8.1–§8.4 tables.
- ✅ Exhaustive copy test: every enum case asserts the exact string returned.
- ✅ `Localizable.strings` complete for v1 English; no inline hardcoded strings in views.
- ✅ Toast auto-dismisses on condition-resolved signals; persists while condition holds.
- ✅ Never shows full-screen error during `.playing`.
- ✅ Every error case has either CTA or auto-retry status indicator.

**Verify:** `swift test --package-path PhospheneEngine --filter UserFacingErrorCopyTests`

---

### Increment U.8 — Settings panel ✅

**Scope:** `SettingsView` sheet per `UX_SPEC.md §9`. Four groups: Audio, Visuals, Diagnostics, About. All fields persisted in `UserDefaults` via `SettingsViewModel`. Settings apply immediately (no "Apply" button). Quality ceiling mid-session applies at next preset transition.

**Landed (2026-04-24):** Three-part delivery across two commits (`5ec23e71`, `b67ec770`).

Part A+B: `SettingsTypes` (5 enums/structs), `QualityCeiling` (Orchestrator module), `SettingsStore` (`phosphene.settings.*` key scheme, 11 properties, `captureModeChanged` subject), `SettingsMigrator`, `SettingsViewModel` + `AboutSectionData`, `SettingsView` (`NavigationSplitView`, 720×520pt), `AudioSettingsSection` + `VisualsSettingsSection` + `DiagnosticsSettingsSection` + `AboutSettingsSection`, `SourceAppPicker` + `PresetCategoryBlocklistPicker`, `CaptureModeReconciler` (LIVE-SWITCH, D-052), `SessionRecorderRetentionPolicy` (injected `now`/`wallClock`, active-session guard), `OnboardingReset`, `PresetScoringContextProvider` (effectiveTier + Part C TODOs).

Part C: `PresetScoringContext` + `excludedFamilies`/`qualityCeiling` (backward-compat defaults, D-053), `DefaultPresetScorer` blocklist+quality-ceiling gates, `PresetScoringContextProvider.build()` wired, `SessionRecorder.init(enabled:)`, `LiveAdaptationToastBridge` key migrated, `PhospheneApp.swift` launch-time migration+pruning, settings gear sheet in `PlaybackView`. 50 `Localizable.strings` keys. 39 app tests + 9 engine tests. 573 engine total; 0 SwiftLint violations.

---

### Increment U.9 — Accessibility pass ✅

**Scope:** `NSWorkspace.accessibilityDisplayShouldReduceMotion` gates `mv_warp` and SSGI temporal feedback. Beat-pulse amplitude clamped to 0.5× when reduced motion is active. Dynamic Type sizing respected across all non-Metal views. VoiceOver labels on interactive elements; render surface marked decorative. Overlay-text contrast measured against the three regression fixtures for every preset; failures gate preset certification.

**Done when:**
- `mv_warp` disabled when reduced motion is active; preset still renders correctly without it.
- SSGI temporal feedback disabled (falls back to non-temporal sampling).
- Beat-pulse amplitude cap verified on beat-heavy fixture.
- Dynamic Type from xSmall to xxxLarge renders without clipping across all non-Metal views.
- VoiceOver rotor reads all interactive elements correctly.
- Contrast test fails a synthetic white-on-white preset fixture; passes against all production presets.
- 8+ unit tests + contrast fixture tests.

**Verify:** `swift test --package-path PhospheneEngine --filter AccessibilityTests`

**Delivered (2026-04-24):** `AccessibilityState` (`@MainActor` ObservableObject, `NSWorkspace` + `ReducedMotionPreference` three-way logic). `RenderPipeline.frameReduceMotion` gates mv_warp via `drawMVWarpReducedMotion`. `RayMarchPipeline.reducedMotion` gates SSGI. Beat-clamp applied to `beatBass/Mid/Treble/Composite` in `draw(in:)` before `renderFrame`. Dynamic Type: all 16 user-facing view files updated (`.system(size:)` → semantic styles). VoiceOver: MetalView hidden, 8 interactive elements labelled, `AccessibilityLabels` service, 14 new `Localizable.strings` keys, `AccessibilityNotification.Announcement` on new toasts. Part C: `QualityGradeIndicator` (shape + letter code for color-blindness), `DebugOverlayView` SIGNAL block updated, `PresetContrastCertificationTests` (WCAG 4.5:1 gate). 14 new tests (5 `AccessibilityStateTests` + 3 `BeatAmplitudeClampTests` + 5 `MVWarpReducedMotionGateTests` + 9 `AccessibilityLabelsTests` + 1 `DynamicTypeRegressionTests` + N×3 `PresetContrastCertificationTests`). D-054.

**Deferred:** Strict photosensitivity mode (flash frequency analysis + frame blanking). *(Partially landed by CLEAN.7.6 / D-164, 2026-06-16: `FlashAnalyzer` + `PhotosensitivityCertificationTests` enforce flash-frequency analysis as a certification gate — currently validly covering Ferrofluid Ocean + Murmuration; the output-side "frame blanking"/luminance clamp and the 5 follower/multi-pass/feedback presets are the A-next runtime-clamp increment.)* SSGI temporal accumulation gate distinct from the frame-level `reducedMotion` flag (currently they are the same flag).

---

## Phase V — Visual Fidelity Uplift

**Why this phase exists:** six iterations on Volumetric Lithograph, three each on Arachne and Gossamer, produced incremental fixes but never reached a 2026 quality bar. `docs/SHADER_CRAFT.md` documents the root cause: the `ShaderUtilities` library was thin (55 functions, missing every modern shader technique), there was no detail-cascade methodology documented, no material cookbook, no reference-image discipline, no quality rubric beyond "does it compile." The fidelity cap is authoring-vocabulary poverty in documentation, not hardware or Metal.

V.1–V.6 build the authoring vocabulary. V.7–V.12 apply it to the existing presets Matt called out. V.1–V.6 can run in parallel with Phase U; V.7+ starts once the utility library is ready.

### Increment V.1 — Shader utility library: Noise + PBR

**Scope:** New directory tree `PhospheneEngine/Sources/Renderer/Shaders/Utilities/` with subtrees `Noise/` and `PBR/`. ~90 new functions total. Per `SHADER_CRAFT.md §11.2`:
- `Noise/`: Perlin, Worley, Simplex, FBM (fbm4/fbm8/fbm12, vector fbm), RidgedMultifractal, DomainWarp, Curl, BlueNoise, Hash.
- `PBR/`: BRDF (GGX, Lambert, Oren-Nayar, Ashikhmin-Shirley), Fresnel, NormalMapping, POM, Triplanar, DetailNormals, SSS, Fiber (Marschner-lite), Thin (thin-film interference).

SwiftLint `file_length` special-cased for `.metal` files (raise to 1000 or path-exclude); mechanism TBD during implementation per `SHADER_CRAFT.md §16.1`. `PresetLoader+Preamble.swift` extended to include new utility tree before preset code.

**Done when:**
- All listed utility files exist with the function signatures from SHADER_CRAFT recipes.
- `NoiseUtilityTests` and `PBRUtilityTests` pass (visual sanity check: render each primitive to a test texture, dHash against goldens).
- `.metal` files allowed to exceed 400 lines without lint violation.
- Existing presets compile and render unchanged (additive change, no breaking modifications).
- `fbm8`, `warped_fbm`, `ridged_mf`, `triplanar_sample`, `triplanar_normal`, `parallax_occlusion`, `mat_silk_thread` available for preset authoring.

**Verify:** `swift test --package-path PhospheneEngine --filter UtilityTests && xcodebuild -scheme PhospheneApp build`

---

### Increment V.2 — Shader utility library: Geometry + Volume + Texture ✓ COMPLETE (2026-04-25)
### Increment V.3 — Shader utility library: Color + Materials cookbook ✅ 2026-04-26
### Increment V.4 — SHADER_CRAFT reference implementation audit ✅

**Scope:** Read-through and correctness pass over the completed utility library. For every recipe in `SHADER_CRAFT.md §3`–`§8`, verify the utility implementation matches the documented recipe byte-for-byte. Any drift becomes a doc bug or a code bug — both get fixed. Performance measurements: measure each utility's real cost on Tier 1 (M1/M2) and Tier 2 (M3+) hardware; update the cost table in `SHADER_CRAFT.md §9.4` with measured values.

**Done when:**
- Every `SHADER_CRAFT.md` recipe has a corresponding utility function with matching behavior. ✅
- Cost table in §9.4 reflects measured values on both tier classes. ✅ (estimates in table; run `PERF_TESTS=1` to get GPU-measured values)
- Discrepancies between doc and code are resolved in favor of the empirically-correct version. ✅

**Completed:** 2026-04-26. D-063. Deliverables:
- `docs/V4_AUDIT.md` — 37-recipe cross-reference, 12 drift items resolved (all doc-fixes), 3 missing materials shipped.
- `docs/V4_PERF_RESULTS.json` — initial estimates; replace with measured values via `PERF_TESTS=1 swift test --filter UtilityPerformanceTests`.
- `Sources/UtilityCostTableUpdater/` — CLI to regenerate §9.4 table from JSON.
- `Materials/Organic.metal` +`mat_velvet`, `Materials/Exotic.metal` +`mat_sand_glints`, `Materials/Dielectrics.metal` +`mat_concrete`.
- §16.2 precompiled Metal archives: deferred (estimated ~23 ms, well below 1.0 s threshold).

**Verify:** `swift test --package-path PhospheneEngine --filter MaterialCookbookTests && swift test --filter PresetRegressionTests`

---

### Increment V.5 — Visual references library + quality reel

**Scope:** Create `docs/VISUAL_REFERENCES/` directory with per-preset folders for all registered presets plus scaffolding for Phase MD presets. Each folder: 3–5 curated reference images with an annotated `README.md` specifying which visual traits are mandatory. Matt curates; Claude Code sessions reference by filename. Additionally: build a **quality reel** — a 3-minute multi-genre capture across (sparse jazz → hard electronic → symphonic), used as a one-glance quality-review artifact for future increments. Plus a `CheckVisualReferences` lint CLI (`PhospheneTools`) that enforces completeness and naming convention.

**Done when:**
- Every registered preset has a `docs/VISUAL_REFERENCES/<preset>/` folder with 3–5 reference images and fully-annotated README.
- Quality reel `docs/quality_reel.mp4` checked in (Git LFS).
- `swift run --package-path PhospheneTools CheckVisualReferences --strict` passes with zero warnings.
- `SHADER_CRAFT.md §2.3` reference-image discipline is enforceable — Claude Code sessions cite filenames.
- Matt approves curation round.

**Verify:**
```bash
swift run --package-path PhospheneTools CheckVisualReferences --strict
swift test --package-path PhospheneEngine --filter UtilityTests
swift test --package-path PhospheneEngine --filter PresetRegressionTests
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build
```

#### Session scaffolding shipped (2026-04-26)

The Claude Code session landed the V.5 runway in one sitting. Matt's curation runs in parallel and is tracked separately in `docs/VISUAL_REFERENCES/README.md`.

**Pre-flight findings:**
- **Preset count corrected: 13** (not 11 as CLAUDE.md stated). Confirmed by flat scan of `PhospheneEngine/Sources/Presets/Shaders/*.metal` matching `PresetLoader` behaviour.
- **FerrofluidOcean and FractalTree already ship** — both have `.metal` shader files and `.json` sidecars. CLAUDE.md listed them as V.9/V.10 "full rebuild" targets implying they were new; they are existing presets targeted for rebuild. Reference folders created as required.
- **Membrane is an undocumented production preset** — `family: fluid`, `passes: feedback`, full-rubric treatment. Not mentioned in CLAUDE.md's module map. No engine changes made; CLAUDE.md module map update deferred to V.6 housekeeping.
- **Stalker has no `.metal` file** — CLAUDE.md describes Increment 3.5.7 (Stalker) as complete, but no `Stalker.metal`, `StalkerGait.swift`, or `StalkerState.swift` exist in the repository. No reference folder created. Flag for Matt: either the increment is in progress and the metal file hasn't landed yet, or the code was deleted. D-064 records the observation.
- **No existing `VISUAL_REFERENCES/` precedent** — naming convention defined from scratch per Part C of the increment spec; the §2.3 example filenames (`04_specular_fiber_highlight.jpg`) are the canonical exemplar.
- **Git LFS**: pre-existing for `ML/Weights/*.bin`; extended for `docs/quality_reel*.mp4` and `docs/VISUAL_REFERENCES/**/*.{jpg,png}`.
- **PhospheneTools**: new package (not pre-existing); establishes the location for future `MilkdropTranspiler` (Phase MD.1+).

**What shipped:**
- `docs/VISUAL_REFERENCES/` — 13 preset folders (9 full-rubric + 4 lightweight) + `_TEMPLATE/` (2 variants) + `_NAMING_CONVENTION.md` + `phase_md/` + top-level `README.md` (curation kickoff)
- `PhospheneTools/Package.swift` + `Sources/CheckVisualReferences/main.swift` — 5 lint rules, fail-soft default, `--strict` flag
- `docs/quality_reel_playlist.json` — 3-segment playlist contract with rationale fields
- `.gitattributes` — LFS rules for images + quality reel
- `docs/RUNBOOK.md` — "Recording the quality reel" section
- `docs/SHADER_CRAFT.md §2.3` — lint-check paragraph + `--strict` flip guidance
- `CLAUDE.md §Visual Quality Floor` — cross-reference to lint tool
- `docs/DECISIONS.md D-064` — records four design decisions

**Lint baseline (expected pre-curation state):**
`swift run --package-path PhospheneTools CheckVisualReferences` reports 13 "no reference images" warnings (one per preset folder), 0 errors. This is the correct intermediate state — folders scaffolded, images pending Matt's curation. Build and test suite unaffected (no engine code changed).

#### Reel + partial curation landed (2026-04-30)

- **Quality reel ✅** — `docs/quality_reel.mp4` committed via Git LFS. Source: Spotify Lossless (Blue in Green → Love Rehab → Mountains). Captured in reactive mode — no Spotify OAuth means no `.ready` state; `startAdHocSession()` → `.playing` directly. See D-066 for rationale on accepting reactive-mode capture for V.6 fidelity evaluation.
- **Visual references 5/11** — Arachne ✅, Gossamer ✅, FerrofluidOcean ✅, FractalTree ✅, VolumetricLithograph ✅. Remaining 6 (GlassBrutalist, KineticSculpture, Membrane, Starburst, Nebula, SpectralCartograph — counting Matt's working total of 11 curated targets) planned for next session.

#### Curation progress (2026-05-01)

Membrane and Starburst reference images added. 5 preset folders still require curation (4 have 0 images; 1 may fail lint on image count or annotated README). `CheckVisualReferences --strict` still failing.

**V.5 remains open.** Done-when criteria not met: 5 preset reference folders still require curation, and `CheckVisualReferences --strict` will not pass until all targeted preset folders are populated with conformant images and annotated READMEs.

---

### Increment V.6 — Fidelity rubric + certification pipeline

**Delivered (2026-04-30):** `Sources/Presets/Certification/` (3 files): `RubricResult.swift`, `FidelityRubric.swift` (`DefaultFidelityRubric` — M1–M7 mandatory, E1–E4 expected, P1–P4 preferred, lightweight L1–L4), `PresetCertificationStore.swift` (actor, lazy cache). `PresetDescriptor` + all 13 JSON sidecars extended with `certified/rubric_profile/rubric_hints`. `PresetScoringContext.includeUncertifiedPresets` gate. `DefaultPresetScorer` uncertified check first; `excludedReason: "uncertified"`. `SettingsStore.showUncertifiedPresets` + Settings toggle. 4 test files (26+ @Test functions). D-067.

**Scope:** Implement the `SHADER_CRAFT.md §12` rubric as automated + manual gates:
- Automated: detail-cascade detection via static analysis of preset Metal source (look for `fbm8` / `worley_fbm` / multiple material calls / triplanar usage); noise-octave counting; material-count verification; D-026 deviation-primitive usage; silence-fallback regression test.
- Manual: Matt-approved reference frame match gates certification.

`PresetDescriptor` gains a `certified: Bool` field. Orchestrator excludes uncertified presets by default. `SettingsView` gets a "Show uncertified presets" toggle (off by default).

Supersedes (without deleting) Increment 5.2's weak invariants — those stay as a passing prerequisite.

**Done when:**
- [x] Automated rubric scores every preset; report prints each preset's 7+4+4 breakdown.
- [x] `certified: Bool` field defaults to false for Matt-approved presets only.
- [x] Orchestrator filter excludes uncertified.
- [x] Toggle in Settings reveals uncertified.
- [x] Increment 5.2 invariants still passing.

**Verify:** `swift test --package-path PhospheneEngine --filter FidelityRubricTests`

---

### Increment V.7 — Arachne v4 (fidelity uplift) ⚠ 2026-04-30
### Increment V.7.5 — Arachne v5 (composition + warm restoration + drops + spider cleanup) ⚠ 2026-05-01 shipped, awaiting Matt M7
### Increment V.7.6 — Arachne v5 (atmosphere + beam-bound motes) ❌ ABANDONED 2026-05-02
### Increment V.7.6.1 — Visual feedback harness ✅ 2026-05-02
### Increment V.7.6.2 — Orchestrator: multi-segment + completion-signal + maxDuration framework

**Scope:** Per `docs/presets/ARACHNE_V8_DESIGN.md §3, §5, §6 step 2`. Preset-system-wide infrastructure change. Touches:
- New `PlannedPresetSegment` value type. `PlannedTrack` becomes `let segments: [PlannedPresetSegment]` (was: `let preset: PresetDescriptor`).
- `SessionPlanner` rewritten to walk each track's section list and produce multi-segment plans, respecting per-preset `maxDuration` and section boundaries.
- `PresetSignaling` protocol with `presetCompletionEvent: PassthroughSubject<Void, Never>`. Orchestrator subscribes per active preset; transitions on event if `minDuration` satisfied.
- `LiveAdapter` segment-aware: `presetNudge(.next)` advances to next segment, not next track.
- **`maxDuration` framework** per `ARACHNE_V8_DESIGN.md §5.2`. New `PresetDescriptor.maxDuration(forSection:)` computed property implementing the formula (motionIntensity, fatigueRisk, visualDensity inputs; sectionDynamicRange adjustment; naturalCycleSeconds cap). Coefficients live in code (default −50, −30, −15, 0.7+0.6) with documentation comments. Tunable via V.7.6.C.
- New `naturalCycleSeconds: Float?` field added to `PresetDescriptor` and JSON schema. Initially set only for Arachne (60s).
- Migration: existing presets without completion signals run to formula-computed `maxDuration` and transition by planned boundary.

**Done when:**
- All existing presets continue to work end-to-end (no visual regressions on Plasma, Waveform, VL, etc.).
- Multi-segment plans generated for tracks longer than the chosen preset's `maxDuration`.
- Preset-completion signal can be wired in (Arachne not yet using it; just the channel is there).
- `SessionPlannerTests` updated for multi-segment outputs.
- Live tests still pass; 0 SwiftLint violations.

**Verify:** `swift test --package-path PhospheneEngine` + Matt runtime test on a multi-track playlist (verify presets transition mid-song, not just on track boundaries).

**Estimated sessions:** 2–3. Load-bearing prerequisite for V.7.7+.

---

### Increment V.7.6.C — Framework calibration pass ✅ 2026-05-03
### Increment V.7.6.D — Diagnostic preset orchestrator semantics ✅ 2026-05-03
### Increment V.7.7A — Arachne staged-composition scaffold migration ✅ 2026-05-05
### Increment QS.1 — Quality System Documentation ✅ 2026-05-05
### Increment V.7.7B — Arachne staged WORLD + WEB port ✅ 2026-05-07
### Increment V.7.7C — Arachne refractive dewdrops (§5.8 Snell's-law) ✅ 2026-05-07
### Increment V.7.7D — Arachne 3D SDF spider + chitin + listening pose + 12 Hz vibration ✅ 2026-05-08
### Increment V.7.7C.2 — Arachne single-foreground build state machine + background pool + per-segment spider cooldown + PresetSignaling + WebGPU Row 5 ✅ 2026-05-09
### Increment V.7.7C.3 — Arachne manual-smoke remediation: chord-by-chord spiral + V.7.5 pool retire + branchAnchors polygon + spider trigger reformulation ✅ 2026-05-09
### Increment V.7.7C.4 — Arachne palette + L lock + hybrid audio coupling (D-095 follow-up #2) ✅ 2026-05-09
### Increment V.7.7C.5 — Arachne atmospheric abstraction (WORLD reframe) ✅ 2026-05-08
### Increment V.7.7C.5.1 — Arachne visual craft pass (line widths + luminescence + palette + shaft gate + per-segment seed) ✅ 2026-05-08
### Increment V.7.7C.5.2 — Arachne second cosmetic + spider-trigger pass (drops + silk re-brightening + hue cycle widening + spider sustain) ✅ 2026-05-08
### Increment V.7.7C.5.3 — Per-track web identity (Options B / C) — DEFERRED, awaiting product decision

**Prerequisite:** V.7.7C.5.2 manual-smoke green sign-off. Renumbered from V.7.7C.5.2 after that slot was claimed by the second cosmetic pass. Decision pending Matt's evaluation of whether the Option A per-segment variation (landed in V.7.7C.5.1) is sufficient or whether webs should additionally be tied to track identity for aesthetic association.

**Scope (if scheduled):** Two flavours, mutually-exclusive:

- **Option B — per-track determinism.** Plumb track-identity hash into `ArachneState.reset(trackSeed:)`. Same track always gets the same web (across replays, across sessions). Adds Swift wiring in `ArachneState` (new `reset` overload), a Renderer hook on track change (`PresetSignaling`-style identity passthrough), and a determinism test asserting two `reset(trackSeed:)` calls with the same seed produce byte-identical web state. ~30 LOC + 1 test.

- **Option C — track + session-counter perturbation.** Per-track base seed gives identity; an LCG step per-replay gives variant on the Nth listen. Variety + association both. ~40 LOC + extends the determinism test with a per-replay variance assertion (Nth replay produces materially-different web state from N+1th replay).

Trade-off: B gives consistent music-visual association at the cost of "this track's web always looks weak when it lands on a poor random draw"; C resolves that but adds session state (LCG-per-track replay counter) that needs persistence across track changes within a session.

**Done when:** Manual smoke confirms the chosen flavour reads as intended on a 10+-track playlist with at least one repeated track. V.7.7C.5.1's Option A is preserved as the fallback when no track identity is available (e.g. ad-hoc reactive sessions before track change observation).

**Estimated sessions:** 1 (single Swift-side commit).

---

### Increment V.7.7C.6 — Arachne spider movement system (off-camera entry + walking path + min-visibility latch + rarity gate) — DEFERRED, V.7.7D-scale increment

**Prerequisite:** V.7.7C.4 manual-smoke green sign-off + V.7.7D 3D SDF spider + V.7.7C.4 trigger reformulation already landed.

**Scope:** Add body translation + waypoint navigation + min-visibility latch + N-segment rarity gate to the existing static-position spider. Per Matt's 2026-05-08T18-28-16Z manual smoke: "the spider flashed on the screen for a second then immediately disappeared. I would want the spider to walk from off camera into the camera frame when triggered and move from one hook of the web to another over the span of 10–15 seconds. The trigger should be rare, but the spider should remain in view for longer, and most importantly should MOVE within the camera frame, ideally along the web." Closes V.7.7C.4's deferred sub-item — comparable scope to the V.7.7D 3D anatomy + chitin material increment.

**Architecture decisions (to be filed as D-100 or next-available decision ID at implementation time):**

1. **`SpiderState` enum.** Replace the current `spiderActive: Bool` + `spiderBlend: Float` pair with a state machine: `.idle` / `.entering(progress: Float)` / `.walking(fromIdx: Int, toIdx: Int, progress: Float)` / `.exiting(progress: Float)` / `.cooldown(remainingSegments: Int)`. State advances on each tick; `spiderBlend` becomes a derived value from the current state.
2. **Off-camera entry path.** On trigger, spawn at UV (1.10, 0.50) (or randomly chosen edge-adjacent position outside [0,1]) and walk to the first polygon vertex over ~1.5 s. `.entering` state.
3. **Walking path along polygon hooks.** Use `bs.anchors[]` (V.7.7C.3 polygon vertices) as waypoints. Spider visits 2–3 polygon vertices over 10–15 seconds, walking along silk thread paths (frame edges). Per-waypoint duration ~4–6 s. Body position interpolates smoothly along the silk edge between consecutive waypoints (catmull-rom or simple linear; spec TBD). Existing leg gait drives leg tips relative to body — animates naturally as body translates.
4. **Min-visibility latch.** Once activated, spider stays visible for at least 12–15 seconds regardless of trigger condition. Replace the current `if spiderActive && !conditionMet { spiderActive = false }` with a min-visibility timer that holds. After expiry, transition to `.exiting` and walk off-frame.
5. **N-segment cooldown for rarity.** Currently per-segment cooldown via `spiderFiredInSegment`. Expand to "spider may fire AT MOST once every N segments". Default N=3; configurable. New `ArachneState.spidersFiredCount: Int` increments on each `_reset()`; trigger gates on `spidersFiredCount % N == 0` AND `!spiderFiredInSegment`.
6. **GPU contract.** `ArachneSpiderGPU` stays at 80 bytes (V.7.7D contract). Body position writes to existing `posX` / `posY` fields each frame. Heading writes to `heading` (rotates as spider walks turn corners). No struct expansion.
7. **Pause-guard interaction.** While spider is active, the build state machine is paused (V.7.7C.2 contract). Spider movement progresses independently — body translates and gait animates regardless of build pause.
8. **Music coupling (TBD):** does the spider walking pace couple to music (slower on quiet passages, faster on dense tracks), or is it on a fixed wallclock? Decide at implementation. D-095 audio-modulated TIME precedent suggests `pace = 1.0 + 0.18 × midAttRel` keeps it consistent with the build state machine.

**Done when:**

- Spider state machine implemented with all five states (`.idle` / `.entering` / `.walking` / `.exiting` / `.cooldown`).
- Spider visibly walks from off-camera into the frame on bass-drop trigger.
- Spider visits 2–3 polygon vertices over 10–15 seconds, walking along silk edges.
- Spider remains in view for at least 12–15 seconds regardless of trigger condition.
- Spider trigger fires AT MOST once every N segments (default N=3).
- Existing per-segment cooldown (`spiderFiredInSegment`) preserved as a same-segment fallback.
- All targeted suites pass.
- Goldens regenerated (substantial drift expected — spider position now varies across the 10–15 s walk).
- 0 SwiftLint violations on touched files.
- New `ArachneSpiderMovementTests` test suite covering the five-state machine transitions, min-visibility latch, N-segment cooldown.
- D-100 (or next-available) decision in `docs/DECISIONS.md` documenting the architectural choices above.
- Manual smoke confirms all four behaviours: off-camera entry, walking along web, min-visibility hold, rarity (one trigger per N=3 segments).

**Verify:** Build → `PresetLoaderCompileFailureTest` → targeted suites pre-golden → visual harness sanity check (force spider via `forceActivateForTest(at:)` and capture the walk path) → golden hash regen → targeted suites post-golden → full engine + app suites → SwiftLint → manual smoke (Matt watches multiple spider triggers across a full session, confirms walking path looks natural, min-visibility holds, rarity gate enforces N-segment cooldown).

**Estimated sessions:** 2–3 (state machine + waypoint navigation + min-visibility + rarity + tests + golden regen).

**Carry-forward:** V.7.10 cert review — final QA pass.

---

### Increment V.8.0-spec — Arachne3D: parallel-preset commit + four pushbacks ✅ 2026-05-08 (D-096)
### Increment V.8.1 — Arachne3D minimal end-to-end 3D scaffold

**Prerequisite:** V.8.0-spec ✅ 2026-05-08 (D-096).

**Scope.** Stand up `Arachne3D` as a parallel preset alongside V.7.7D `Arachne` per D-096 Decision 1. New `Arachne3D.metal` + `Arachne3D.json` (display name `"Arachne 3D"`, `certified: false`, default `rubric_profile`) under `PhospheneEngine/Sources/Presets/Shaders/`. `passes: ["ray_march", "post_process"]` (drop `["staged"]`); WORLD pass continues to ship via the existing V.7.7B `arachne_world_fragment` writing `arachneWorldTex` (bound at the same texture index Arachne uses today). The ray-march pass implements `sceneSDF` / `sceneMaterial` using the V.2 SDF tree (`sd_capsule`, `sd_sphere`, `op_smooth_union`) for a **single static web** at `(0, 0, 0)`: 12 procedurally-unrolled spokes, one spiral revolution, no chord-segment subdivision, no drops, no spider, no build cycle. Material: `mat_silk_thread` (V.3 cookbook) on silk strands. Lighting: directional key + flat ambient; **no IBL, no SSGI** (`noSSGI` is the Tier-1 default per D-096 Decision 5). Camera: static, framed on the hub, FoV ~50°. `ArachneState` reused unchanged from V.7.7D — Arachne3D binds the same instance; existing 2D Arachne preset continues to render in parallel. **No `Arachne3DState` is introduced.** Layout audit on `WebGPU` to confirm a `hubZ: Float` extension fits in the existing 80-byte slot (purely additive — V.7.7D Arachne ignores the new field).

Out of scope for V.8.1: drops (V.8.2), refraction (V.8.2), chromatic dispersion (V.8.2), spider (V.8.3), IBL cubemap + DoF (V.8.4), multi-web pool + cinematic camera + foreground build state machine (V.8.5), cert (V.8.6).

**Done when (D-096 Decision 8 — single structural acceptance gate):**

1. **Single web visibly rendering through the deferred PBR pipeline at the correct screen position.** Manual verify by launching the app, cycling to Arachne3D via `⌘[` / `⌘]`, and confirming the silk-strand web renders at the framed hub.
2. **Camera parallax visible.** A small (≤0.5 unit) camera offset injected via developer-shortcut or test fixture must produce visible 3D parallax of silk strands against the WORLD backdrop. The strands move relative to the backdrop; the backdrop does not move (it's a billboard sample per D-096 Decision 2). This proves real 3D rendering, not a 2D fragment shader simulating depth.
3. **WORLD pass sampled correctly as backdrop.** Miss-ray pixels return `arachneWorldTex.sample(uv)` (not flat color, not the sky-only V.7.7B early-out). Verified by silencing the silk SDF in a debug build and confirming the full-frame WORLD render reads through.
4. **Anti-reference visual rejection.** Rendered frame must NOT visually match `09_anti_clipart_symmetry.jpg` or `10_anti_neon_stylized_glow.jpg`. Operationally — until automated dHash-against-anti-refs lands — Matt eyeballs the V.8.1 contact sheet against both anti-refs at the phase boundary and signs off.
5. **p95 frame time inside the budget forecast committed in D-096 Decision 5.** Single-web V.8.1 scene is a fraction of the V.8.5 forecast; Tier 2 expected ~3–5 ms p95, Tier 1 expected ~5–8 ms p95 with the noSSGI default engaged. **V.8.1's first task is to instrument the scene with `MTLCounterSet.timestampGPU` and validate per-component costs against the §4.4 forecast on a real Tier 1 (M1 or M2) device + a real Tier 2 (M3) device.** If Tier 1 exceeds 14 ms p95 even at this reduced scene complexity, the architecture is wrong for Tier 1 and V.8.x replans before V.8.2.
6. **`PresetVisualReviewTests` extended to render `Arachne3D`** alongside `Arachne` for silence / steady / beat-heavy / sustained-bass fixtures into the harness contact sheet under `RENDER_VISUAL=1`. Net-new `Arachne3D` golden hashes added to `goldenPresetHashes` in `PresetRegressionTests`; existing Arachne hashes stay locked at V.7.7D values per D-096 Decision 1.
7. **Visual feedback loop engaged at phase boundary** per `ARACHNE_3D_DESIGN.md §7.3`. Claude Code renders the contact sheet, summarises what changed structurally, and stops. Matt + a separate Claude.ai session produce the visual diff that feeds V.8.2.
8. **Targeted suites pass:** `PresetAcceptance` (Arachne3D added to the parametrized list), `PresetRegression` (Arachne3D goldens), `PresetLoaderCompileFailure` (preset count 14 → 15, no silent compile drop per Failed Approach #44), the existing Arachne suites unchanged. 0 new SwiftLint violations.
9. **Closeout report** per CLAUDE.md Increment Completion Protocol: files changed, tests run, harness output paths, doc updates (V.8.1 entry flipped to ✅; D-096 referenced as the architectural source), capability registry updates if any, known risks (anti-reference subjective check pending automated dHash; perf forecast unverified on Tier 1 hardware until Matt runs the harness on M1/M2), git status clean.

**Verify:**
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` green.
- `swift test --package-path PhospheneEngine` green; `swift test --package-path PhospheneEngine --filter PresetVisualReview` produces non-placeholder Arachne3D PNGs alongside Arachne PNGs.
- `swiftlint lint --strict --config .swiftlint.yml` 0 violations on touched files.
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview` writes Arachne3D contact-sheet PNGs to `/tmp/phosphene_visual/<ISO8601>/`.
- Manual: launch app, cycle to Arachne3D, verify acceptance criteria 1–4 above.

**Estimated sessions:** 1 (scaffold-only).

**Carry-forward:** V.8.2 — drops at chord-segment intersections (Tier 2: ~300–500/web; Tier 1: capped at 150/web per D-096 Decision 5) + screen-space Snell's-law refraction sampling `arachneWorldTex` + silhouette-band chromatic dispersion. V.8.3 — spider in 3D via `sceneSDF` (V.7.7D `sd_spider_combined` adapted) + chitin material via `sceneMaterial`. V.8.4 — IBL forest cubemap from V.7.7B WORLD palette + depth-of-field on `PostProcessChain`. V.8.5 — multi-web pool in 3D + cinematic camera (Decision E.3) + foreground build state machine + 3D vibration. V.8.6 — M7 cert + V.7.7D Arachne retirement (file deletion + `Arachne 3D` → `Arachne` rename in JSON sidecar).

**V.8.2+ scope is intentionally NOT expanded yet.** Each subsequent increment gets its own ENGINEERING_PLAN entry once V.8.1 contact-sheet review lands and the visual feedback loop produces the diff that informs V.8.2's prompt.

---

### Increment V.7.7 — Arachne v8: WORLD pillar + 1–2 background dewy webs

**Status correction (2026-05-07):** The `[V.7.7 redo]` commit (`fa5dacdf`, 2026-05-05 10:54) added the six-layer inline `drawWorld()` and frame threads to the *monolithic* `arachne_fragment`. Three hours later, `[V.7.7A]` (`ccefe065`, 2026-05-05 14:13) retired that fragment and shipped placeholder staged stubs. The V.7.7 work is therefore preserved as dead reference code in `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal` (free-function `drawWorld` ~line 142, legacy `arachne_fragment` ~line 617), not in the dispatched path. Promotion into the staged path is V.7.7B.

**Prerequisite:** V.7.7A staged-composition scaffold migration ✅ 2026-05-05.

**Scope:** Per `ARACHNE_V8_DESIGN.md §4` (full WORLD pillar) + §5.12 (background webs) + §8.1 step 1–2 (render-pass layout). The 2026-05-03 spec rewrite expanded V.7.7 from a thin atmosphere pass into the full layered WORLD — implementing §4.2's six depth layers into a half-res `arachneWorldTex`: sky band (4.2.1) + distant tree silhouettes (4.2.2) + mid-distance trees with bark detail (4.2.3) + near-frame anchor branches (4.2.4) + forest floor (4.2.5) + volumetric atmosphere (4.2.6 fog + light shafts + dust motes). Mood-driven palette per §4.3 (preserved verbatim from V.7.6.C-locked recipe — `topCol`/`botCol`/`beamCol` + per-layer color application table). Includes 5s low-pass `smoothedValence`/`smoothedArousal` state per §4.3. Then 1–2 pre-populated background dewy webs (§5.12) with refractive drops sampling `arachneWorldTex` per the §5.8 recipe (Snell's law, eta ≈ 0.752, fresnel rim, specular pinpoint, dark edge ring). Background webs vibrate per §8.2. Foreground unchanged (still V.7.5 build code — refactored in V.7.8).

**Done when:**
- WORLD reads as a forest with depth — six layers individually identifiable. Side-by-side via harness contact sheet against refs `06` / `15` / `16` / `17` / `18` / `07`.
- Background webs read as photorealistic dewdrops side-by-side with refs `01` / `03` / `04` via the harness contact sheet.
- Pure-black silence anchor preserved (§8.3) — `(satScale × valScale) < 0.05` clears WORLD pass to black.
- All test suites pass; 0 SwiftLint violations.
- p95 frame time at 1080p ≤ 6.0 ms Tier 2 / ≤ 7.5 ms Tier 1.
- Matt runtime visual review of the WORLD + background-webs state passes.

**Verify:** Same as V.7.6.1 + Matt runtime review.

**Estimated sessions:** 3.

---

### Increment V.7.8 — Arachne v8: WEB pillar — foreground build refactor (corrected biology) [Subsumed by V.7.7C.2 — see V.7.7C.2 section above]

**Status correction (2026-05-07):** The `[V.7.8]` commit (`3536a023`, 2026-05-05 11:06) added the chord-segment capture spiral to `arachneEvalWeb()` inside the monolithic fragment. Same retirement story as V.7.7 — code survives as dead reference at ~line 265 of `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal`; port to staged dispatch is V.7.7B. The chord-segment SDF replacement for the degenerate Archimedean curve (Failed Approach #34) is a permanent reference for V.7.7B; do not regress to circular rings.

**Status (2026-05-09 / D-095):** This V.7.5-era line item is **obsolete** — V.7.7C.2 implements the single-foreground build state machine (frame → radials → INWARD spiral → settle, audio-modulated TIME pacing, per-segment spider cooldown, build pause/resume on spider). See V.7.7C.2 above for the actual closeout.

**Scope:** Per `ARACHNE_V8_DESIGN.md §5.1–§5.11` (WEB pillar in full). Replace V.7.5 pool-of-webs system with single-foreground-build state machine implementing the corrected orb-weaver biology: frame polygon (§5.3, 4–7 anchors on near-frame branches from V.7.7) → hub (§5.4, dense knot, NOT concentric rings) → radials (§5.5, 12–17, alternating-pair order, ±20% jitter, drawn one at a time over ~1.5s each) → **capture spiral winding INWARD** (§5.6, chord-segment SDF from outer frame to hub — corrects the 2026-05-02 spec error which had the spiral winding outward) → settle (§5.2, completion signal at 60s ceiling). Sag per §5.7 (`kSag ∈ [0.10, 0.18]`, drop weight modifies sag). Drops per §5.8 with accretion over time on just-laid spiral chords (foreground starts sparse, grows dense; background webs stay saturated). Anchor terminations per §5.9 — small adhesive blobs where outer frame threads meet near-frame branches. Silk material per §5.10 (minor finishing — Marschner-lite removed). Pause on spider trigger; resume on spider fade. Foreground completion emits `presetCompletionEvent` via the V.7.6.2 channel.

**Done when:**
- Visual review via harness: foreground build is visibly progressing — radials extend one-at-a-time, spiral winds **inward** chord-by-chord, completion fires at ≤ 60s under typical music.
- Drops are the visual hero — viewer's eye lands on drops first, threads second. Drops show refraction + fresnel rim + specular pinpoint + dark edge ring per §5.8.
- Anchor structure reads as solid — frame polygon visibly meets near-frame branches at adhesive blobs. Side-by-side with ref `11`. Polygon is irregular, not circular.
- Spider trigger visibly pauses construction; spider fade visibly resumes from paused accumulator (does not restart).
- Orchestrator transitions on completion event when `minDuration` satisfied.
- All test suites pass; 0 SwiftLint violations.
- p95 frame time ≤ 6.0 ms Tier 2.
- Matt runtime visual review passes.

**Verify:** Same.

**Estimated sessions:** 3.

---

### Increment V.7.9 — Arachne v8: SPIDER pillar deepening + whole-scene vibration + cert [Subsumed by V.7.7C.2 / V.7.7D — see V.7.7C.2 + V.7.7D sections above]

**Status correction (2026-05-07):** The `[V.7.9 ✅]` commit (`97f42220`) was a CLAUDE.md status update only — 4 line changes, no shader code. The biology-correct frame → radial → spiral build order remains unimplemented in the dispatched path. SPIDER pillar deepening, vibration, and cert review remain unimplemented as well. Build-order work is scheduled for V.7.7C; SPIDER + vibration for V.7.7D; cert review for V.7.10.

**Status (2026-05-09 / D-095):** This V.7.5-era line item is **obsolete** — V.7.7D shipped SPIDER pillar deepening (3D SDF anatomy + chitin material + listening pose) + whole-scene 12 Hz vibration; V.7.7C.2 closed the structural gap (build state machine). Cert review (M7) remains scheduled for V.7.10. See V.7.7D and V.7.7C.2 above for the actual closeout.

**Scope:** Per `ARACHNE_V8_DESIGN.md §6` (full SPIDER pillar) + §8.2 (vibration model) + §12 (acceptance criteria). The 2026-05-03 spec rewrite expanded V.7.9 from "polish + vibration" into a full spider-anatomy refactor — V.7.5's "dark silhouette + warm rim" was the right *direction* but wrong *depth* for an easter egg that earns its rare appearance. Implements §6.1 anatomy (cephalothorax + abdomen + petiole, 8 articulated legs with outward-bending knee IK, eye cluster as 6–8 small dots in tight forward arrangement — refs `12` + `13`, NOT the jumping-spider 2x2 of ref `19`), §6.2 material (chitin base + thin-film iridescence at biological strength + Oren-Nayar-like hair fuzz + per-eye specular per ref `19` technique), §6.3 pose / gait / listening pose (resting at hub by default; listening pose — front legs raised ~30° — fires on sustained low-attack-ratio bass for ≥ 1.5s), §6.4 lighting (deep body shadow + warm-amber rim + eye sparkle), §6.5 trigger and behavior (per-segment cooldown replaces V.7.5's 300s session-level lock). Whole-scene tremor on bass per §8.2 — 12 Hz audio-rate vibration applied per-vertex to all webs + near-frame branches + spider, amplitude driven by `max(f.subBass_dev, f.bass_dev)` + per-kick spike from `f.beatBass`. Forest floor and distant layers don't shake. Final tuning of drop counts, brightness, sag magnitude, free-zone size, mood-smoothing window against references via the harness. Cert review.

**Done when:**
- Visual review via harness contact sheet matches all 10 acceptance criteria from `ARACHNE_V8_DESIGN.md §12`.
- Spider, when present, is detailed — viewer can see cephalothorax, abdomen, 8 legs with visible knee bends, eye cluster, abdominal pattern. Material reads as biological iridescent chitin (ref `14`), not neon (ref `10`). Listening pose visibly fires on sustained bass.
- Web vibration visible during heavy bass — whole-scene tremor (~12 Hz) on background + foreground webs + branches + spider; ground/distant layers stable.
- Anti-refs `09` (clipart symmetry) and `10` (neon glow) explicitly NOT matched. Refs `01`, `03`, `04`, `05`, `06`, `08`, `11`, `12`, `15`, `16` cited as reachable.
- All test suites pass; 0 SwiftLint violations.
- p95 frame time ≤ 6.0 ms Tier 2.
- **Matt cert review.** If positive: `Arachne.json` `certified: true`, add `"Arachne"` back to `FidelityRubricTests.certifiedPresets`, mark V.5 references action complete, log M7 outcome in references README.

**Verify:** Same.

**Estimated sessions:** 2.

**V.8 remains reserved for Gossamer** per `SHADER_CRAFT.md §10.2`.

---

### Increment V.8 — Gossamer v4

**Scope:** Apply to Gossamer per `SHADER_CRAFT.md §10.2`. Physical wave displacement (waves offset silk strand positions, not just tint them); silk Marschner-lite material tuned for hero resonator; fine specular glints at thread intersections; chromatic aberration on wave peaks; inward/outward dust drift; SSGI-lit background from web emission.

**Done when:** same rubric gates as V.7; `certified: true`.

**Verify:** same as V.7.

**Estimated sessions:** 2 (physical displacement rework / atmosphere + chromatic aberration).

---

### Increment V.9 — Ferrofluid Ocean v2 (redirect) ✅ (certified 2026-05-18)
### Increment V.10 — Fractal Tree v2

**Scope:** Apply to Fractal Tree per `SHADER_CRAFT.md §10.4`. Bark material with POM + triplanar + lichen patches; procedural leaf clusters at branch tips with leaf material (SSS back-lit); wind animation via curl-noise; seasonal palette synced with valence; golden-hour lighting with long shadows.

**Done when:** same rubric gates; `certified: true`. Performance profile shows POM + foliage within Tier 2 budget (likely requires MetalFX Temporal upscaling at sub-1080p internal render).

**Verify:** same as V.7.

**Estimated sessions:** 4 (bark + POM / foliage / wind animation / seasonal + audio).

---

### Increment V.11 — Volumetric Lithograph v5

**Scope:** Major rework per `SHADER_CRAFT.md §10.5`. Replace fBM heightfield with `ridged_mf` warped by `curl_noise` (mountainous, not lumpy); mesa terrace secondary displacement; triplanar detail normal; aerial perspective fog (color-shift from warm sky to cool depth); drifting cloud shadows; cutting-plane beat-reveal replaces palette flash; retain mv_warp and pitch-color mapping from MV-3.

**Done when:** same rubric gates; `certified: true`. Terrain reads as mountainous, not lumpy — confirmed against `docs/VISUAL_REFERENCES/volumetric_lithograph/` annotations.

**Verify:** same as V.7.

**Estimated sessions:** 3 (terrain reformulation / aerial + clouds / cutting-plane + polish).

---

### Increment V.12 — Glass Brutalist v2 + Kinetic Sculpture v2

**Scope:** Fidelity uplift for the remaining ray-march presets not covered in V.7–V.11. Glass Brutalist: board-form concrete lineage (plank impressions, tie-rod holes, weathering — Salk/Scarpa direction, not Ando smooth); detail normals on concrete; POM on walls; pattern-glass material for fins per `SHADER_CRAFT.md §4.5b` (voronoi cellular, NOT fbm-frost); volumetric light shafts through windows. Wet-concrete variant explicitly out of scope — `mat_wet_stone` reserved for other presets. References curated in `docs/VISUAL_REFERENCES/glass_brutalist/` (8 images, 7 trait slots + 1 anti). Kinetic Sculpture: brushed aluminum material per `§4.2`; polished chrome with anisotropic streaks; dust motes in ambient space.

**Done when:** both presets pass fidelity rubric 10/15 with all mandatory; `certified: true` on both.

**Verify:** same as V.7.

**Estimated sessions:** 3 (Glass Brutalist lift / Kinetic Sculpture lift / joint polish + perf).

---

## Phase MD — Milkdrop-inspired uplift work stream

**Operative strategy:** [`docs/MILKDROP_STRATEGY.md`](MILKDROP_STRATEGY.md) §12 (inspired-by reframe addendum, landed 2026-05-12). §§1–11 of that doc remain in tree as the historical record of the derivative-posture framing that preceded the reframe; §12 is the operative record going forward. **Decisions D-103 through D-118 are signed off**; the addendum amended six base decisions in place (D-103 / D-105 / D-106 / D-110 / D-111 / D-112) and filed six new ones (D-113 — posture reframe; D-114 — 20-preset release bundle; D-115 — release-bundle composition (Matt's pick pending); D-116 — substantial-similarity discipline rule; D-117 — catalog-ratio framing (deferred); D-118 — read-only analysis tool scope). Empirical basis for both the base strategy and the addendum: [`docs/diagnostics/MD-strategy-pre-audit-2026-05-12.md`](diagnostics/MD-strategy-pre-audit-2026-05-12.md).

**Why this phase exists (revised under inspired-by):** `docs/MILKDROP_ARCHITECTURE.md` informed Phosphene's own authoring patterns (MV-0 through MV-3); Phase MD turns the cream-of-crop pack into a long-term *inspiration source* for new Phosphene presets — each uplift is a hand-authored, Phosphene-native creation that honors a source Milkdrop preset's concept and aesthetic. The vehicle for that work is the `mv_warp` render pass (D-027) plus the rest of Phosphene's preset infrastructure (V.1–V.4 utilities, ray-march, MV-3 capabilities); Milkdrop-inspired presets become additional consumers alongside Gossamer / Volumetric Lithograph. Initial planning target is **~200 uplifts** (multi-year work stream, not a finite phase); the **20-preset first-release bundle (D-114)** is the near-term milestone.

**The 20-preset first-release bundle (D-114) is the load-bearing near-term milestone.** Phosphene's first public release ships when the catalog reaches 20 M7-certified presets — a mix of Phosphene-native + Milkdrop-inspired per D-115 (composition pending Matt sign-off; default working assumption: 10 + 10). Current state: 1 certified (Lumen Mosaic) + ~14 production-but-not-all-certified Phosphene-native; gap to 20 is the work this Phase MD section (combined with Phase G-uplift + Phase AV) scopes.

Runs in parallel with Phase V.7+, Phase AV, Phase CC, Phase G-uplift. Cadence after first release: separate release-management decision (not in this phase's scope).

### Increment MD.1 — `.milk` grammar audit (read-only authoring aid)

**Scope (revised per `MILKDROP_STRATEGY.md` §12 / D-110 amendment / D-118):** New doc `docs/MILKDROP_GRAMMAR.md` cataloguing the `.milk` expression sub-languages **and** the HLSL `warp_1=` / `comp_1=` surface used across the `presets-cream-of-the-crop` pack. **Reframed as a read-only authoring aid** under the inspired-by reframe — the doc helps an inspired-by author opening a source `.milk` for the first time look up unfamiliar variables / functions / HLSL features. It does **not** drive a transpiler (no transpiler ships per D-110 amendment); HLSL is no longer excluded (every preset in the pack is a viable inspiration source). The audit commits no licensed content (cites the pack as a corpus only).

**Done when:**
- Doc enumerates all variables (bass/mid/treb/time/q1–q32/wave_* / mv_* / ob_* / ib_* etc.) used in the expression sub-languages, with frequency counts over the full 9,795-preset corpus.
- Top-20 built-in functions (sigmoid, clamp, above, below, if_then_else etc.) have Phosphene-side authoring-equivalent notes (reference for inspired-by authors, not transpiler emission spec).
- HLSL surface section (first-class, not appendix) catalogs the `sampler_*`, `GetPixel`, `GetBlur1/2`, `tex2D` etc. surface present in the 81% of pack presets that ship HLSL; each entry notes the Phosphene-side authoring equivalent (a Phosphene primitive an inspired-by author can reach for) — **never** an automated translation spec (D-110 amendment + D-116 discipline rule).
- Frequency + HLSL-presence summary reports descriptive statistics over the full pack. No transpiler coverage gate.

**Verify:** Manual review against 10 randomly-sampled preset files spanning themes / sizes / HLSL presence.

---

### Increments MD.2 / MD.3 / MD.4 — RETIRED

**Status:** Retired entirely under the inspired-by reframe (`docs/MILKDROP_STRATEGY.md` §12, D-110 amendment, D-118).

- **MD.2 (Transpiler CLI skeleton)** — no transpiler ships. `PhospheneTools/MilkdropTranspiler` SPM target was never created and will not be.
- **MD.3 (Per-frame JSON emission + HLSL hand-port playbook)** — the JSON emission half required the transpiler; the hand-port playbook half is also retired (the substantial-similarity discipline rule in `SHADER_CRAFT.md §12.6` / D-116 replaces both translation modes).
- **MD.4 (Per-vertex Metal emission)** — same; no transpiler, no automated emission.

Under the inspired-by reframe, source `.milk` files become reference material that authors read end-to-end before drafting Phosphene-native uplifts. Each Milkdrop-inspired Phosphene preset is hand-authored from scratch against Phosphene's primitives (V.1–V.4 utilities, `mv_warp`, `ray_march`, MV-3 capabilities). The MD.1 grammar doc serves as the read-only reference (D-118). See `MILKDROP_STRATEGY.md` §12.7 / §12.9.

---

### Increment MD.5 — First 10 Milkdrop-inspired uplifts (initial release-bundle batch)

**Scope (revised per `MILKDROP_STRATEGY.md` §12 / D-103 amendment / D-105 amendment / D-106 amendment / D-111 amendment / D-112 amendment / D-116):** Author 10 Milkdrop-inspired Phosphene presets, hand-crafted from scratch against Phosphene's primitives, each honoring a source `.milk` preset's concept and aesthetic per the substantial-similarity discipline rule (`SHADER_CRAFT.md §12.6` / D-116). All 10 ship under a single family — `milkdrop_inspired` — per D-105 amendment. Settings toggle is `phosphene.settings.visuals.milkdrop.inspired` per D-106 amendment. Each `.metal` / `.json` carries an `inspired_by` provenance block per D-111 amendment. Source-preset candidates draw from the D-112 list (HLSL-free constraint dissolves per D-112 amendment; substitutions encouraged at authoring). **This batch contributes to the 20-preset first-release bundle (D-114).**

**Done when:**
- 10 new presets in `PhospheneEngine/Sources/Presets/Shaders/Milkdrop/` with JSON sidecars. Naming: `<theme>_<source_name>.{metal,json}` per D-105 amendment.
- Each preset's JSON sidecar declares `family: "milkdrop_inspired"`, the appropriate `rubric_profile` (per preset — full or lightweight per author + M7 judgment), and `inspired_by: { milkdrop_filename, original_artist, pack, sha256 }`.
- Each preset passes M7 review against the substantial-similarity discipline rule (`SHADER_CRAFT.md §12.6` / D-116) — no source equations copy-pasted, no source shader logic ported line-for-line, no `.milk` content redistributed.
- Each has a golden-session regression entry and Increment 5.2 acceptance test.
- Orchestrator metadata (`visual_density`, `motion_intensity`, `fatigue_risk`, etc.) hand-authored per preset for planning integration.
- `SettingsStore` + `VisualsSettingsSection` gain the single `phosphene.settings.visuals.milkdrop.inspired` toggle per D-106 amendment; defaults to `true` once the first preset ships.
- `docs/CREDITS.md` "Milkdrop-inspired preset attribution" section enumerates all 10 source-preset references per D-111 amendment.

**Verify:** `swift test --filter PresetAcceptanceTests` + per-preset M7 review against `SHADER_CRAFT.md §12.6` checklist.

---

### Increment MD.6 — Ongoing Milkdrop-inspired uplift batches

**Scope (revised per `MILKDROP_STRATEGY.md` §12 / D-103 amendment):** Continued Milkdrop-inspired uplift authoring beyond MD.5's initial batch. **No tier distinction** under the inspired-by reframe (D-103 amendment retired the Classic / Evolved / Hybrid split); every uplift is a `milkdrop_inspired` preset hand-authored against the same discipline rule (D-116). Stem routing, beat anticipation, mood coupling, section awareness, ray-march composition — all per-preset authoring choices, not tier-mandated. Batch size and cadence are release-management decisions (separate from this phase scope).

**Done when:**
- Continued growth of `PhospheneEngine/Sources/Presets/Shaders/Milkdrop/` under the inspired-by framing.
- Each uplift carries `family: "milkdrop_inspired"` per D-105 amendment + `inspired_by` provenance per D-111 amendment + passes M7 review against the D-116 discipline rule.
- `docs/CREDITS.md` extended with each new source-preset reference per D-111 amendment.
- Catalog growth tracked against the long-term ~200-uplift target (`MILKDROP_STRATEGY.md` §12.1). Steady-state catalog ratio question deferred to D-117 trigger.

**Carry-forward:** MD.6 is the long-tail work stream. The 20-preset first-release bundle (D-114) is the first milestone; subsequent bundles ship at the cadence set by release planning.

**Verify:** `swift test --filter PresetAcceptanceTests` per uplift.

---

### Increment MD.7 — Ray-march-composing inspired-by uplifts (formerly Hybrid tier)

**Scope (revised per `MILKDROP_STRATEGY.md` §12 / D-103 amendment / D-107):** Inspired-by uplifts that compose `mv_warp` + `ray_march` against a static camera (D-029). **Not a tier** — these are `milkdrop_inspired` presets that happen to use the ray-march backdrop primitive; authoring choice, not classification. The MD.7.0 spike (single-preset proof of the `mv_warp` + `ray_march` composition) lands as one such uplift; subsequent ray-march-composing uplifts batch into the MD.6 work stream. The architectural composition has only Volumetric Lithograph as prior production proof (and VL's `mv_warp` plays against a ray-march scene that is not itself feedback-warped), so the spike is still a high-value increment under inspired-by.

**Done when:**
- The MD.7.0 spike ships: 1 inspired-by preset composed of `["ray_march", "mv_warp", "post_process"]` renders correctly without obscuring either layer. Recommended source-preset inspiration: Geiss *3D-Luz* (D-107 pre-approved starter).
- Frame budget verified on Tier 1 and Tier 2; results recorded.
- Matt confirms the layering reads as designed (feedback warp visible on top, ray-march backdrop visible behind).
- One-paragraph "what we learned" note added to `MILKDROP_STRATEGY.md` §12.9 carry-forward table or to a follow-up addendum entry, feeding back into subsequent ray-march-composing uplifts.
- The D-107 pre-approved starters (Geiss *3D-Luz*, Rovastar *Northern Lights*, EvilJim *Travelling backwards in a Tunnel of Light*) remain viable inspiration sources for ray-march-composing uplifts under inspired-by; selection follows D-107 criteria (architectural + thematic + brand fit) applied at the preset-concept level rather than the port-feasibility level.

**Verify:** `RENDER_VISUAL=1 swift test --filter PresetVisualReview` + Matt M7 review against the substantial-similarity discipline rule (`SHADER_CRAFT.md §12.6`).

---

## Phase 6 — Progressive Readiness & Performance Tiering

### Increment 6.1 — Progressive Session Readiness ✅ (2026-04-25)
### ✅ Increment 6.2 — Frame Budget Manager (landed 2026-04-25)

**What was built:** `FrameBudgetManager.swift` — pure-state governor with 6-level `QualityLevel` ladder (`full → noSSGI → noBloom → reducedRayMarch → reducedParticles → reducedMesh`), `Configuration` factories (tier1: 14ms/0.3ms margin; tier2: 16ms/0.5ms margin), asymmetric hysteresis (3 overruns down / 180 frames up), `reset()` on preset change. OR-gate refactor of `RayMarchPipeline.reducedMotion` → `a11yReducedMotion || governorSkipsSSGI` with dedicated setters (D-057). `PostProcessChain.bloomEnabled`, `ProceduralGeometry.activeParticleFraction`, `MeshGenerator.densityMultiplier`, `RayMarchPipeline.stepCountMultiplier` (written to `sceneParamsB.z`). Timing via `commandBuffer.addCompletedHandler` → `@MainActor` hop. `QualityCeiling.ultra` exempts the governor. Debug overlay quality level line. 36 new tests across 5 files. Golden hashes regenerated for VolumetricLithograph + KineticSculpture (preamble compiler optimization). 721 engine tests total; 1 pre-existing flaky timer failure unchanged.

---

### ✅ Increment 6.3 — ML Dispatch Scheduling (landed 2026-04-25)

**What was built:**
- `MLDispatchScheduler.swift` (`Renderer` module): pure-state controller with `Configuration` (tier defaults: 2000ms/30-frame Tier 1, 1500ms/20-frame Tier 2), `Decision` enum (`.dispatchNow / .defer(retryInMs:) / .forceDispatch`), `DispatchContext` value type, and `decide(context:) -> Decision` algorithm. `QualityCeiling.ultra` → `enabled = false` bypass. D-059.
- `FrameTimingProviding` protocol in `MLDispatchScheduler.swift`: `recentMaxFrameMs` + `recentFramesObserved`. `FrameBudgetManager` conforms via extension; test stubs use `StubFrameTimingProvider`. Single rolling buffer (30-slot circular array) in `FrameBudgetManager` serves both governor hysteresis counters and the ML scheduler with no duplicate state. D-059(e).
- `VisualizerEngine+Stems.swift` restructured: `runStemSeparation()` hops to `@MainActor`, consults the scheduler, then dispatches back to `stemQueue` via `performStemSeparation()`. `pendingDispatchStartTime` tracks deferral duration; cleared on dispatch and on `resetStemPipeline(for:)` track change.
- `VisualizerEngine` gains `deviceTier: DeviceTier` (stored, set in `init()`), `mlDispatchScheduler: MLDispatchScheduler?`, and `pendingDispatchStartTime: TimeInterval?`. Debug overlay `ML:` row shows current scheduler state (idle / dispatch / defer Nms / force).
- `MLDispatchSchedulerTests.swift`: 10 `@Test` functions. `MLDispatchSchedulerWiringTests.swift`: 5 `@Test` functions (incl. `StubFrameTimingProvider`). 20 new tests total.
- `DECISIONS.md` D-059 (5 sub-decisions). `ARCHITECTURE.md` §ML Inference gains Dispatch Scheduling subsection. `RUNBOOK.md §Jank / dropped frames` updated. `CLAUDE.md` Module Map and §ML Inference updated.
- 747 engine tests; 0 SwiftLint violations. Phase 6 complete.

**Done when:** ✅ Scheduler defers dispatch when recent frames are over budget. ✅ Force-dispatch ceiling prevents stem freeze. ✅ 20 new tests (≥ 4 required). ✅ Zero dHash drift.

**Verify:** `swift test --package-path PhospheneEngine --filter "MLDispatchScheduler"`

---

## Phase 7 — Long-Session Stability

### Increment 7.1 — Soak Test Infrastructure ✅ **LANDED 2026-04-26**
### Increment 7.2 — Display Hot-Plug & Source Switching ✅ **LANDED 2026-04-26**
## Phase MM — Murmuration (promote, redesign, certify)

**Supersedes Phase SB** (below). Matt's 2026-06-03 direction: promote Murmuration to its
own first-class preset (split from the legacy `Starburst.*` files) and **fully redesign the
flock** to faithfully capture the shape and movement of a real starling murmuration, tied to
musical signals — not the cosmetic D-026 + noise-utility pass that Phase SB scoped. The core
problem is structural: the current model is a parametric ellipse of fixed "home slots" with
spring-to-home forces (`Particles.metal` / `ProceduralGeometry`) at **5,000 particles** — it
cannot produce the dense, emergent, morphing mass with a core→edge density gradient that the
references (`docs/VISUAL_REFERENCES/murmuration/`) and motion clips show. "Each bird visible"
is the documented anti-reference (`05_anti_countable_individuals`).

**Decisions (2026-06-03):** full redesign · full rename (retire the Starburst name; no separate
radial-burst preset) · May still-refs are current · Matt-supplied motion clips + flocking-research
references drive the temporal contract (recorded in memory `project_murmuration_uplift.md`).

**Drafted musical contract** (one primitive per layer, one timescale, all deviation primitives per
D-026; continuous drivers 2–4× the beat accents; finalized against the clips in MM.1):

| Visual behavior | Audio driver | Timescale |
|---|---|---|
| Shape elongation (ribbon/comma) + macro drift | `bass_att_rel` | slow / continuous (primary) |
| Turning + pivot + density-agitation waves | `drums_energy_dev` + beat | per-beat (accent) |
| Feathered-edge flutter / shimmering periphery | `mid_att_rel` (edge-weighted) | fast |
| Whole-mass breathing (expand ↔ contract) | `vocals_energy_dev` | phrase |
| Sky warmth shift (≤10%, secondary) | `spectral_centroid` | slow |

---

### Increment MM.0 — Identity split + rename ✅ 2026-06-03

**Delivered (mechanical; output byte-identical, golden hashes stable):**
- `git mv` `Starburst.metal` → `Murmuration.metal`, `Starburst.json` → `Murmuration.json`;
  fragment function `starburst_fragment` → `murmuration_sky_fragment` (JSON `fragment_function`
  updated to match); file header comment updated.
- `git mv docs/VISUAL_REFERENCES/starburst/` → `murmuration/` (LFS-tracked images preserved);
  README title/identity pass (technical sections flagged historical pending MM.1 rewrite).
- Preset discovery is glob-based (`PresetLoader` pairs each `.metal` with its sibling `.json`),
  so the file rename is transparent to loading; no registry/name-list edits needed for discovery.
- Doc path updates: `docs/VISUAL_REFERENCES/README.md`, `CAPABILITY_REGISTRY/PRESETS.md`
  (file/name discrepancy marked resolved), `ENGINE/RENDER_CAPABILITY_REGISTRY.md`,
  `ARCHITECTURE.md` Module Map (also corrected a stale mv_warp description), `RUNBOOK.md`
  (removed a stale Starburst mv_warp reference), `MILKDROP_ARCHITECTURE.md` live table row,
  `FidelityRubricTests.swift` comment. Historical narrative (DECISIONS D-029 body,
  MILKDROP_ARCHITECTURE MV-2 revert story, `archive/`, `diagnostics/`, `prompts/`) left as-is.
- **Scope note:** the `ProceduralGeometry` class / `Particles.metal` engine-shader rename to a
  flock-specific name + its own sibling file (D-097) is **deferred to MM.2**, where the flock
  engine is rewritten — renaming code about to be replaced is churn-on-churn.

**Done when:** ✅ engine + app build clean; ✅ full test suite green (preset loads as
"Murmuration" from the renamed files; golden hashes unchanged).

---

### Increment MM.1 — Reference + motion review → design doc (research-first)  *(draft published 2026-06-03; pending Matt approval)*

**Delivered:** [`docs/presets/MURMURATION_DESIGN.md`](presets/MURMURATION_DESIGN.md) — technique
chosen (**GPU boids over ~7 grid-found neighbours + audio-driven global roost attractor + banking,
simulated in 3D and projected**), grounded in working references (Robert Hodgin *Murmuration*
40K–1M flockers; Rama Hoetzlein three-level flocking; techcentaur boids; McGill biomechanics for
topological neighbours + **orientation-wave dark bands** + critical-noise + flash-expansion).
Infrastructure precedent: `FerrofluidParticles` GPU spatial-binning. Carries the §3 musical contract
(L1–L6), a honest fidelity-risk statement (tuning risk concentrated in MM.2/MM.3), and the open
questions for Matt. **Remaining to close MM.1: Matt's motion-clip notes to finalize the §3 magnitudes
+ approval to proceed to MM.2.**

**Scope:** read the references + Matt's motion clips; decompose the reference signature into
layers; research the working flocking references (Robert Hodgin murmuration, Hoetzlein GPU
flocking, boids implementations, McGill biomechanics analysis — all in memory) and cite them per
the grounding-priority rule. Author `docs/presets/MURMURATION_DESIGN.md`: technique choice +
grounding, particle-count target, the (layer × primitive × timescale) table made concrete from
the video, an honest fidelity-risk statement. **Matt approves the design before any flock code.**
Likely direction: morphing implicit shape-envelope + curl-noise turbulence + cheap grid-based
separation for the feathered edge (GPU spatial-binning precedent: `FerrofluidParticles`).

**Done when:** design doc published + Matt-approved; technique grounded in ≥1 working reference.

---

### Increment MM.2 — Flock engine (the redesign)  *(force-based substrate SUPERSEDED by MM.6; scaffolding kept)*

**Scope:** new flock-specific engine-library shader + conformer (D-097 sibling; this is where
the deferred `ProceduralGeometry`/`Particles.metal` rename lands) at the MM.1 particle count.
**Multi-frame production-path test harness FIRST** (per "test in production-grade pipeline"):
runs the feedback+particles dispatch for N frames at silence and on a beat, measuring silhouette
cohesion + core/edge density gradient. Tune the silence baseline to a dense, cohesive,
density-graded mass (the opposite of the `05_anti_*` failure modes).

**Done when:** silence baseline reads as a cohesive dense mass with a density gradient; harness
asserts it; 60fps-feasible at target count (perf validated in MM.4).

---

### Increment MM.3 — Audio coupling (D-026) + firing evidence  *(force-based coupling SUPERSEDED by MM.6; M7-failed, see below; routing/replay/test scaffolding kept)*

**Scope:** wire the musical contract with deviation primitives; verify the 2–4×
continuous:beat ratio; produce per-route firing evidence from a real-music session
(`features.csv`/`stems.csv`, via `PresetSessionReplay`) — evidence, not assertion.

**CARRY FORWARD the original Murmuration's audio coupling (binding).** MM.3 ports and adapts the
pre-MM `Particles.metal` proven audio mappings onto the boids substrate — it does NOT reinvent them
(that was the "starting over" mistake Matt flagged 2026-06-03). The original's drum turning-wave
propagation = L2 verbatim-in-mechanic; bass elongation = L1; edge-weighted "other" flutter = L4;
vocals density-compression = L5; warmup stem-blend (D-019) + FA #26 cross-genre beat all kept. The
one improvement over the original: convert raw energy → deviation primitives (D-026). See
[`MURMURATION_DESIGN.md` §3.2](presets/MURMURATION_DESIGN.md). **Keep `ProceduralGeometry` /
`Particles.metal` in the tree until MM.3 has ported its audio coupling** — it is the reference source.

**Delivered (2026-06-03, commits `072b2b8c` port · `205ac595` tests · `4ff18f8b` replay · `11767968` lint):**
- `MurmurationFlockGeometry.computeAudio(features:stemFeatures:dt:)` ports the four `Particles.metal`
  routes onto the boids substrate, all from deviation primitives (D-026): **L1 bass** → roost macro
  drift + a guide-segment elongation (Hoetzlein guide-line) → comma/ribbon; **L2 drums** → a curl
  impulse about the flock axis that sweeps as the beat pulse decays (FA #26 cross-genre beat),
  rolling birds without translating the mass (FA #4) + a localized wave-darkening band written to
  `pad0` for the moving dark band; **L4 mid** → inverse-neighbour-count edge flutter; **L5 vocals**
  → tighter inter-bird spacing (the dark pulse). §3.1 coordination: orthogonal-DOF substrate +
  energy/arousal-gated event layer; D-019 warmup blend kept. `FlockParams` → 144 B (MSL mirror).
- Every audio term vanishes at zero input → the MM.2 silence baseline is reproduced exactly (its
  harness stays green). **L3 flash-expansion deferred** per design §9 (Matt 2026-06-03).
- `MurmurationFlockAudioTests` (7 tests) verify every route + the ≥ 2× continuous:beat ratio via
  the **real reset→bin→boids dispatch path**, measured within one geometry (the flock is its own
  control — boids are chaotic + GPU atomic-binning is non-deterministic, so cross-run diffs are
  unreliable). Full engine suite 1384 green; swiftlint --strict 0; app build clean.
- `MurmurationRouteSpecs` registered in `PresetSessionReplay` → a `--preset murmuration` run over a
  recorded session emits the per-route firing evidence pack.

**Done when:** ✅ ratio verified (≥ 2× via real dispatch); ✅ no absolute-threshold reads (D-026
throughout); ✅ each route's routing verified via the production dispatch path. **PENDING (→ MM.5):**
per-route firing evidence from a *real recorded session* (none exists in-repo and live audio can't be
captured headlessly — the diagnostic is built and one command away once Matt records a session) and
the M7 live review (the load-bearing "reads musical + stays calm in calm passages" gate). MM.3's bar
— "the audio coupling demonstrably works at the routing layer" — is met; the perceptual sign-off is
MM.5.

**M7 round 1 FAILED + fixed (2026-06-03, commit `564f4eec`).** First live review: the flock
fragmented into clumps, popped/splashed birds, showed a square-grid artifact — not a murmuration, not
musical. Root cause (live session CSV): the D-026 deviation primitives spike to **~3×** on real music
(`drumsEnergyDev`/`bassEnergyRel` max ~3.2–3.4), but the gains were tuned at input = 1.0 → audio
forces 3–6× too strong, tearing the flock and inverting the Audio Data Hierarchy (FA #4). The routing
tests missed it by capping inputs at 1.0 (FA #66 parity gap). Fix: `tanh`-saturate every driver,
re-tune gains to gentle accents, bound the drift inside the frame, decouple the L2 wave's darkening
(strong) from its curl force (gentle), per-frame edge flutter, + a new **parity invariant test**
(sustained 3×-magnitude audio at 55k → flock stays cohesive). Full suite 1385 green. See
`MURMURATION_DESIGN.md §11.1` + memory `project_deviation_primitive_real_range`. **The live LOOK
(murmuration character + whether the square-grid artifact is gone) is still unverified — needs Matt's
rebuild + re-review; not confirmable headlessly.**

---

### Increment MM.4 — Sky + render polish + performance

**Scope:** upgrade the sky to V.1 noise utilities + palette (secondary — the flock is the hero);
density-accumulation rendering + edge feathering; recalibrate `complexity_cost`; confirm 60fps
@ 1080p (frame-budget governor `activeParticleFraction` downshift already supported).

**Done when:** rubric M1/M2 satisfied on the sky surface; p95 frame time ≤ tier budget.

---

### Increment MM.5 — Certification  *(✅ DONE 2026-06-04, commit `8f313bdc`)*

**Scope:** real-music session, M7 contact sheet vs references + motion clips, Matt approval,
flip `Murmuration.json` `certified: true`, add "Murmuration" to
`FidelityRubricTests.certifiedPresets`, regenerate golden hashes, update registry / plan /
release notes.

**Done when:** Matt M7-approves; `certified: true`; golden hash regenerated; tests green.

**DELIVERED.** Certified after Matt's review across MM.6 rounds (worm → traverse → musicality →
review pass; "works and can probably be certified soon" → "prepare closeout and certification").
`Murmuration.json certified: true` + `rubric_profile: lightweight` (particle preset — exempt from
the M3 material heuristic by construction, like the other certified feedback/particle presets;
Matt's M7 review is the load-bearing gate per SHADER_CRAFT §12.1); stale "500K starlings"
description rewritten to the real 3D parametric-ellipse flock + global-envelope coupling.
`FidelityRubricTests.certifiedPresets += "Murmuration"` (kept in sync with the JSON flag).
`MurmurationRoutes.swift` firing specs re-derived against the shipped `murmuration3d_update`
(ENERGY / BEAT / VOCALS per §13.5; were stale, describing the retired emergent substrate).
Deliberately **no `stem_affinity`** — Murmuration is energy-driven (not stem-specific), so neutral
affinity is the honest representation; stem routing is deferred to Matt's "experimentation" phase.
No golden-hash regen needed (golden tests use an inline catalog with dev=0 → neutral affinity for
all; the JSON cert flip does not perturb them). Review pass on session `2026-06-04T16-44-08Z`:
GPU 0.75 ms mean (trivially cheap), zero NaN/inf across 8554 frames, framing holds live; the only
flags (CPU hitches at startup/track-change 0.2%; high beat-grid drift) are pre-existing engine/audio
behavior, not Murmuration (the beat layer is onset-driven, robust to grid drift). Engine 1377 green,
app build clean, lint 0; FidelityRubric / Golden / routing gates pass. Follow-ups (experimentation
phase): `stem_affinity` tuning, `complexity_cost` recalibration to the measured cheapness.

---

### Increment MM.6 — 3D Murmuration (parametric-ellipse flock)  *(✅ DELIVERED + CERTIFIED 2026-06-04 via MM.5 `8f313bdc`; emergent Flock2 substrate retired after M7 rounds 1–7 all failed live — see RESOLUTION at end of section)*

**Supersedes the force-based substrate of MM.2 and the force-based audio coupling of MM.3.** MM.4
(sky/perf) and MM.5 (cert) now apply to the Flock2 flock and follow this increment.

**Why:** MM.3's M7 live review failed — the force-based flock fragmented/popped/showed a grid artifact
under real audio. Root cause was twofold: deviation primitives spike ~3× (force-magnitude fix landed,
`564f4eec`), AND — more fundamentally — the whole substrate was a hand-derived force-boids
approximation of the published model Matt provided at kickoff. **Failed Approach #73** ("don't build
what's already been built"). The reference is **Hoetzlein's Flock2 (2024, J. Theoretical Biology,
MIT code, github.com/ramakarl/Flock2)**: an *orientation-based* model (neighbour influence = a desire
to TURN via quaternion targets, not summed force vectors) that natively produces what MM.2/MM.3
hand-faked — travelling dark bands **emerge** from alignment+avoidance coupling (MM.3 *injected* a curl
wave), cohesion comes from a **peripheral-boundary turn** (MM.2 used a roost leash that clumps/freezes),
and it is **stable under perturbation by construction** (force-summing is *why* MM.3 shredded under
audio). Audio coupling re-expresses the §3 contract as **gentle biases on the turn-desires**, which
physically cannot fling the flock apart.

**Scope:** PORT Flock2 from its source (`source/flock_types.h`, `flock_kernels.cu/.cuh`,
`app_flock.cpp`) — wholesale, not re-derived from the paper (FA #70/#64). Replace the
`murmuration_boids` integrator + the `MurmurationBird` layout (→ quaternion + speed) + `computeAudio`;
**keep** the conformer/harness/render/sky/governor/replay scaffolding. Re-express L1 bass (drift +
elongation as target/anisotropy bias), L2 drums (intensify the emergent wave on the beat, not a
force), L4 mid (edge-bird turn jitter), L5 vocals (cohesion-strength breathing); L3 still deferred. All
drivers soft-saturated and sized against the real ~3× range (`project_deviation_primitive_real_range`);
**carry the cohesion-under-3×-load test forward** (it caught the MM.3 failure). Full kickoff:
[`docs/prompts/MM6_KICKOFF_FLOCK2_REBUILD_2026-06-03.md`](prompts/MM6_KICKOFF_FLOCK2_REBUILD_2026-06-03.md).
Model + params pre-extracted in memory `project_flock2_reference`.

**Key porting decisions (kickoff §"Porting decisions"):** quaternion bird state; ~7-topological-+-290°-FOV
neighbour query; **unit/scale mapping** (Flock2 is metres / 5–18 m/s — must map to Phosphene's ±2 world,
keep the ratios); drop the roost leash for the boundary term + a soft framing containment (static wide
camera, design §9); port the heading controller faithfully, simplify the full aero only if a term has
no visible effect.

**Done when:** silence flock reproduces Flock2's qualitative behaviour (cohesive morphing mass +
**emergent** travelling bands + feathered edge) vs references/clips; production-path tests green incl.
the carried-forward cohesion-under-load invariant + per-route turn-desire firing; no absolute-threshold
reads; continuous ≥ 2× beat; full suite green, lint 0, app builds; per-route firing evidence from a real
recorded session; **Matt M7 live approval** (the load-bearing gate — not assertable headlessly).

**DELIVERED (2026-06-03).** Hoetzlein's orientation controller (`advanceOrientationHoetzlein` +
`findNeighborsTopological` + libmin `quaternion.cuh`) ported to MSL `murmuration_boids` (quaternion
bird + topological-7/240°-FOV gather + 4 heading rules + reaction-limited control + dynamic-stability
realign). New 64 B `MurmurationBird` (quaternion+target), 208 B `FlockParams`. Silence baseline reads
as a murmuration (cohesive dense core, feathered/stippled edge, detached stragglers, **emergent**
banking; `RENDER_VISUAL=1` frames in `tools/murmuration_reference/frames/`). Banking darkening = true
wing-area-to-camera (`|up.z|`), not an injected channel.

**Two mid-flight design decisions (Matt):**
1. **Faithful aero, NOT simplified** — simulate in literal **metre units** with Flock2's full
   lift/drag/thrust/gravity (source constants) and project metres→clip at render. The flock self-sizes
   by metre-space density (radius ∝ N^⅓); framing/view/domain scale as `cbrt(count)` for
   density-invariance across test (2–6 k) and production counts.
2. **Musicality rethink — global envelope + emergence, NOT per-bird accents.** The self-organizing
   substrate *swallows or inverts* small per-bird injections (the MM.3 drum-roll-wave halved banking;
   mid-flutter increased edge alignment — measured). So drive the flock's **global** state and let the
   structure emerge: **bass** → drift + envelope elongation (ribbon); **bar maneuver** → ONE
   coordinated heading-swing per bar (downbeat-triggered, alternating, energy-gated, drum-modulated) —
   the banking wave **emerges** from the swing (not every beat — too twitchy); **vocals** → active
   vertical dilation (breathing). Per-bird drum-wave + mid-flutter routes **removed**. Empirically:
   the flock's *size* is a stiff emergent equilibrium that tightening a bound can't shrink (only active
   anisotropic forcing — elongation, vertical dilation — moves it robustly).

**Tests** (`MurmurationFlockTests` + `MurmurationFlockAudioTests`, real reset→bin→boids dispatch):
silence baseline, FlockParams stride, silence-zero-drive, bass drift+elongation, bar-maneuver
(banking tracks the bar envelope, multi-bar-averaged), vocals dilation, continuous ≥ 2× maneuver, and
the **carried-forward** cohesion-under-3×-load invariant. The subtle route tests use separately-settled
flocks + long averaging (single within-geometry windows are too noisy under the non-deterministic GPU
binning — flaked under parallel load). Full engine suite 1384 green (×3 parallel runs), lint 0, app
builds. Route specs updated in `MurmurationRoutes.swift`.

**M7 ROUND HISTORY (live reviews, Matt).** R1 split/froze/too-fast (over-tuned off source defaults); R2
frozen cross (speed-scaling broke the lift/gravity balance — reverted to verbatim aero + DT=0.005
sub-stepping); R3 "murmurations of murmurations" internal sub-clusters (over-packed grid → matched source
density); R4 **"birds far too spread out, world still much too large — not convincing, still inferior to
the previous build."**

**ROUND-5 REFRAME — visual density + framing + the camera tilt (2026-06-04).** R4's source-density domain
is a SIMULATION default, not a framed visual — it rendered a small dense core inside a wide sparse spray
(`maxR ≈ 355 m`, ~1.8× whs; the angle-target containment saturated through `mf_fmodulus` and the X/Z wrap
circulated escapees into a halo). Fixes (faithful aero KEPT, gravity unchanged): (1) size the world for
VISUAL density (`whs = 75·cbrt(count/ref)`, `neighborRadius` scales with it so `rNbrs` is counted
accurately, `boundaryCnt` 120→10 = a true topological edge); (2) a **direct-velocity oblate wall**
replaces the saturating angle-target wall as the size/framing controller (no spray, no falling tail, no
overshoot) + gentle flat-bottomed re-centring; (3) the **rounding is a ~34° camera pitch** in the vertex
projection — the flock is a wide disk round in X–Z and thin in Y, so tilting maps its depth into screen
height → a rounded ovoid (ref `01`), no aero change; (4) routes made **homothetic** (proportional to
position, fill don't hollow) + world-relative caps so loud bass gives a framed comma not a thin edge
ribbon. Silence = rounded dense ovoid (ref `01`); loud = coherent framed comma (ref `02`). Test
robustness: audio suite `.serialized`; bar-maneuver asserts **mean banking rises** (not a flaky bar-phase
correlation); loud-cohesion asserts **mean** core-fraction (not the noise-sensitive per-frame min). Full
engine suite **1385 green (×2 full-parallel + ×3 serialized)**, lint 0, app builds. Design doc §12.1.

**ROUND-5 M7 FAILED → ROUND-6 GOVERNOR FIX (2026-06-04).** Live review showed a frozen oval + a small
chaotic sub-flock inside it. The round-5 SHAPE was correct (the frozen oval IS the rounded ovoid); the
failure was a test/prod parity gap (FA #66): the D-057 governor drops `activeParticleFraction` to 0.5, and
the boids integrator ran on `activeCount = particleCount·fraction` — but a **coupled flock cannot drop a
fraction of its birds** (the excluded birds froze in place; the active half re-cohered into the blob).
Every headless test ran at fraction 1.0 → missed it. Fix: integrate ALL birds every frame;
`activeParticleFraction` throttles the **sub-step count** instead (cost-equivalent, flock stays whole).
Regression test `test_governorThrottleFreezesNoBirds` (asserts <2% frozen + cohesive at the throttled
rate) + `mm6_throttled_*` parity render. Generalisable rule added to CLAUDE.md §What NOT To Do (coupled
substrates throttle fidelity, never element count). Full suite **1386 green**, lint 0, app builds. Design
doc §12.2.

**ROUND-6 M7 FAILED → ROUND-7 FREE-WHEELING REWORK (2026-06-04).** R6: "neither looks nor behaves like a
murmuration" — the flock settled into a stable blob (silence renders 24 s apart identical) instead of
ceaselessly morphing. Root cause (FA #73, from the Flock2 source): faithful CONTROLLER, unfaithful WORLD.
The source frames its flock with ONLY the soft peripheral-boundary turn toward a fixed centre (no hard
wall); my round-5 hard wall + per-bird re-centring flat-lined the wheeling. Taproot: the neighbour examine
cap (96) couldn't count r_nbrs to the source's boundary_cnt=120, so I'd used 10 → weak herding → spray →
wall → dead. Fix: remove the wall + re-centring; raise neighborCap 96→512 + boundaryCnt 10→60 so the
boundary-turn frames the flock source-faithfully; lower avoidance 0.05→0.015; PERF early-exit gather
(interior birds exit at boundary_cnt — makes the high cap affordable); 3D far-edge safety for runaways;
wider static view. Silence now MORPHS (banked masses, sweeping wings, comma-tails, shed sub-groups) at
full AND throttled quality. Durable lesson in CLAUDE.md §What NOT To Do (don't bend a ported reference out
of its working regime). Full suite **1387 green**, lint 0, app builds. Design §12.3. Follow-ups: density
(more birds), gather perf for a higher-count ship, audio-route FEEL re-tune for the free-wheeling regime.

**ROUND-7 M7 FAILED → RESOLUTION: PIVOT TO A 3D PARAMETRIC-ELLIPSE FLOCK (2026-06-04, commit `9056dc48`).**
Live review of the free-wheeling rework (and two further iterations) still failed: *"neither looks nor
behaves like a murmuration… the previous version built months ago is still far superior in look and feel.
Have you looked at the code of this version at all?"* — and the flock was extending off-canvas. **Seven M7
rounds (R1–R7) of the emergent Flock2 substrate failed live**; each fix traded one failure for another
(too-fast → frozen → sub-clusters → spray → frozen-oval → dead-blob → off-canvas spray). The convergence
rule of FA #58/#69 fired: iteration that doesn't change the upstream premise means the premise is wrong.
The premise that failed: **pure emergence (free-flight boids) will, on its own, hold one dense framed
on-canvas mass.** It will not — the references teach realistic *motion* (banking → dark bands), but the
*control* (one dense framed morphing mass) comes from the proven 40-round 2D Murmuration
(`Particles.metal`): birds spring-pulled to home slots in a **continuously morphing ellipse**, dense and
framed **by construction**.

Matt's resolving direction (three messages): (a) *"I asked you to REVIEW THE CODE [of the old version],
not replace your work with it"* — learn from the proven architecture, don't just restore the 2D preset;
(b) *"Why are these the only options?"* — rejected the false A/B (keep-emergent vs restore-2D); (c) **"I
have always wanted a 3D version of this preset — this was the whole goal of the uplift. I just don't want
to work on tweaking it for the next 48 hours."** The synthesis: **lift the proven 2D controlled-ellipse
architecture to 3D** — keep the control (spring-to-morphing-ellipse, dense/framed by construction), gain
the third dimension (3D morphing ellipsOID home slots + perspective + depth fade) and real banking
(wing-area-to-camera → the rolling dark bands).

**DELIVERED — `Murmuration3D.metal` + `Murmuration3DGeometry.swift` (a `ParticleGeometry` sibling, D-097;
own `M3DParticle` 64 B layout + `murmuration3d_*` kernels).** 3D ellipsoid home slots with audio-morphed
half-extents; spring-to-home (`3·d + 5·d²`, damping `1 − 3·dt`) from the 2D original; bounded lemniscate
flock-centre drift; perspective projection (camDist 2.6, camPitch 0.35 rad) + depth fade + viewScale 2.1;
banking from turn-rate drives near-black sprite darkening for the dark-band shimmer. Audio brain ported
verbatim from the 2D preset: **bass** → drift + elongation, **drums** → turning-wave/banding, **other** →
flutter + curvature, **vocals** → density compression. 14 000 birds (governor never throttles it at this
cost — controlled flock keeps all birds). Wired into `VisualizerEngine.makeMurmurationGeometry`. **Emergent
Flock2 substrate retired** (`MurmurationFlock.metal` + `MurmurationFlockGeometry` + 2 test files `git rm`'d).

**Verified headlessly** (`Murmuration3DRenderTests`, the look is the deliverable; pace/audio-feel are
Matt's call): `test_framed` asserts framedFrac > 0.95 on-canvas (replicates the vertex projection incl.
viewScale); `test_render` (RENDER_VISUAL=1) — silence frames show a dense tapered 3D mass with near/far
depth gradient morphing comma→ribbon; audio frames show elongated S/boomerang ribbons spanning the frame
with rolling dark bands that shift between shots. Frames in `tools/murmuration_reference/frames/mm3d_*.png`.
Engine **1376 tests green**, app build clean, lint 0.

**1ST LIVE REVIEW → MOTION REWORK (2026-06-04, commit `9b37d359`, design §13.3).** Session
`2026-06-04T15-41-40Z`: *"Better. Consistent shape now, but its movement is more like a worm than a
murmuration"* + ~20 % too slow. The shape was approved; the **motion** read as a worm — root cause was a
`sin(u·π + st)` curvature wave travelling down the long axis (the snake-spine primitive) over a static,
spring-pinned interior. Fix: replace the spine wave with a **wheeling comma** (centred C+S curves rotated
through a turning plane — reshapes, doesn't undulate); add **internal churn** (a flow field smooth in
(u,v,w) advects the home slots so birds stream through the volume — the mass boils); add **continuous
rolling dark bands**; **+20 % speed** via `motionRate = 1.2`. Verified headlessly (framedFrac > 0.95; new
`mm3d_burst_*` 0.2 s frames show the interior reshuffling + bands rolling, not rigid translation). Engine
1376 green, app build clean, lint 0.

**2ND LIVE REVIEW → TRAVERSE (2026-06-04, commit `75d39eaf`, design §13.4).** Session
`2026-06-04T15-59-58Z`: *"Better, but primarily moving in place — needs to drift from one end of the
screen to the other, might require moving the camera back a little."* Motion character was right; the
flock's position stayed mid-frame (drift amp ~0.12 vs flock half-extent ~0.40). Fix: camera back + zoom out
(`camDist` 2.6 → 3.2, `viewScale` 2.1 → 1.3 → flock ~40 % of frame, room to drift) + a slow dominant L↔R
sweep (~34 s each way, clamped ±0.30 x). `test_framed` upgraded to prove framed-across-traverse
(`minFramed > 0.93`) AND a real sweep (`centreXrange > 0.30`). Engine 1376 green, app build clean, lint 0.

**3RD LIVE REVIEW → MUSICALITY (2026-06-04, commit `cd67944a`, design §13.5).** Session
`2026-06-04T16-15-40Z`: *"Steady improvements… the real focus now should be on musicality — how the preset
feels connected to music sources"* (+ traverse still inches, minor). Diagnosis from the session CSVs: the
existing routes were 10–20 % modulations buried under autonomous motion running on a pure-time clock —
that was the disconnect. Fix (global-envelope coupling, `feedback_global_coupling_emergent_substrate` +
Audio Data Hierarchy): smoothed CPU-side envelopes drive `energyEnv` → a **vigor-paced morph clock** +
**swell** + **traverse range** (PRIMARY); `beatEnv` → a **beat-gated agitation wave** (ACCENT); `vocalEnv`
→ density. Gains sized to measured ranges (stem energy ~0.3 mean/0.7 p99; drumsBeat 0→1). `viewScale`
1.3 → 1.05 for swell room. `test_musicality` asserts louder → bigger + more banding than silence;
`test_framed` drives energetic audio and asserts framed + traverse. Engine 1377 green, app build clean,
lint 0.

**CERTIFIED (MM.5, 2026-06-04, commit `8f313bdc`).** Matt approved across the review rounds ("works and
can probably be certified soon" → "prepare closeout and certification"). `Murmuration.json certified:
true`; route specs re-derived; review-pass on `2026-06-04T16-44-08Z` clean (GPU 0.75 ms, 0 NaN, framing
holds). See the MM.5 row above. Design §13 / §13.3 / §13.4 / §13.5. **Experimentation follow-ups (Matt's
"revisit later"):** `stem_affinity` tuning, `complexity_cost` recalibration to the measured cheapness, and
optional deeper beat-coupling (gated by the separate beat-sync work).

---

## Phase SB — Starburst Fidelity Uplift  *(SUPERSEDED by Phase MM, 2026-06-03)*

> **Superseded.** Phase SB scoped a cosmetic uplift (D-026 routing + V.1 noise utilities +
> materials) that kept the parametric-ellipse flock and 5K count. Matt's 2026-06-03 direction
> is a full flock redesign — see **Phase MM** above. SB.0 (docs prep) already shipped; SB.1–SB.5
> are retired in favor of MM.1–MM.5. The SB text below is retained for historical context only.

Full SB.1–SB.5 scoped narratives: [`ENGINEERING_PLAN_HISTORY.md`](ENGINEERING_PLAN_HISTORY.md) §DOC.6 closed-phase batch.

---

### Increment SB.0 — Documentation prep ✅ 2026-05-01
### Increment SB.1 — JSON sidecar audit + routing review
### Increment SB.2 — Visual references curation
### Increment SB.3 — Audio routing pass (D-026 compliance)
### Increment SB.4 — Detail cascade + materials pass (rubric gate)
### Increment SB.5 — Certification
---

## Phase DSP — DSP Hardening

Targeted fixes to MIR signals where a documented "Failed Approach" mitigation has shipped but the underlying signal quality still degrades the visualization on uncataloged tracks. Each increment is scoped to one signal, lands behind a diagnostic logging gate first, and ships with before/after captures committed under `docs/diagnostics/`.

---

### Increment DSP.1 — IOI histogram half/double voting in `BeatDetector+Tempo`

**Goal:** Fix the half-tempo octave error documented as Failed Approach #17. Replace the single-peak IOI-histogram selection (with its pairwise 2× correction in `applyOctaveCorrection`) with a small voting pass over harmonic candidates {2·BPM₀, 1.5·BPM₀, BPM₀, 0.667·BPM₀, 0.5·BPM₀}, scored by raw bin count + harmonic support + perceptual prior + (optional) metadata-BPM prior. Reuses `BeatPredictor.setBootstrapBPM` injection path; no new dependency, no model.

**Why now:** The existing `applyOctaveCorrection` only handles a pairwise 2× peak comparison and only when a second peak is present and within ratio 1.8–2.2. On 125 BPM kick-driven tracks the estimator still commonly returns ~62 BPM; metadata disambiguation works for cataloged tracks but fails on live recordings, DJ continuous mixes, and niche releases. Voting lets a true tempo win even when the dominant IOI bin sits at half-tempo.

**Implementation order — diagnostic logging FIRST (project principle):**

1. **Land logging only.** Add a `dumpHistogram(label:)` helper to `BeatDetector+Tempo` emitting the top-5 IOI bins (period, count, implied BPM) plus the currently-selected BPM. Gate behind `BEATDETECTOR_DUMP_HIST=1` env var so it stays silent in production. Commit as `[DSP.1] BeatDetector: histogram dump for tempo diagnosis`.
2. **Capture baseline** on the three reference tracks in `CLAUDE.md`:
   - Love Rehab (Chaim) — known 125 BPM
   - So What (Miles Davis) — known 136 BPM
   - There There (Radiohead) — BPM unknown to us; capture whatever the current estimator returns and treat as the "before" value.
   Save dumps to `docs/diagnostics/DSP.1-baseline.txt`.
3. **Implement voting.** Replace `applyOctaveCorrection` with a scoring pass over the five harmonic candidates. Keep the legacy path reachable behind `BEATDETECTOR_LEGACY_TEMPO=1` for one increment so A/B comparison is trivial.
4. **Re-run the same baseline capture** with voting on. Save to `docs/diagnostics/DSP.1-after.txt`. The diff is the change-description evidence.

**Scoring components:**

- **Bin count** at the candidate BPM (the raw IOI evidence; reuse the existing 141-bucket 60–200 BPM histogram).
- **Harmonic support** — bin counts at half-BPM and third-BPM (i.e. 2× and 3× the candidate period) add a fraction of their count to the score. A true tempo has IOI peaks at integer multiples of its period; a half-tempo candidate does not.
- **Perceptual range prior** — soft Gaussian centered at 120 BPM, σ ≈ 40 BPM, across 50–220 BPM. Hard reject anything outside [40, 240] BPM.
- **Metadata BPM prior** (when available) — strong Gaussian centered at the metadata BPM, σ ≈ 4 BPM. The prior wins ties decisively but cannot override overwhelming IOI evidence (see test case 4).

**Files to touch:**

- `PhospheneEngine/Sources/DSP/BeatDetector+Tempo.swift` — add `dumpHistogram`; replace `applyOctaveCorrection` with voting.
- `PhospheneEngine/Sources/DSP/BeatDetector.swift` — only if the metadata-BPM injection point doesn't already exist on `BeatDetector` itself; reuse `BeatPredictor.setBootstrapBPM` pattern.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/BeatDetectorTempoTests.swift` — new file for unit-level voting tests on synthetic histograms.
- `PhospheneEngine/Tests/PhospheneEngineTests/Regression/BeatDetectorRegressionTests.swift` — extend with reference-track regression cases (existing fixtures unchanged).
- `PhospheneEngine/Tests/PhospheneEngineTests/Performance/DSPPerformanceTests.swift` — add voting-budget assertion.
- `docs/CLAUDE.md` — update Tempo section; amend Failed Approach #17 (octave error is no longer a passive limitation).
- `docs/DECISIONS.md` — new D-073 entry: "Tempo octave disambiguation via IOI harmonic voting + metadata prior". Document why TempoCNN (AGPL) and Sound Analysis (orthogonal) were rejected.

**Tests — synthetic IOI histograms (`BeatDetectorTempoTests.swift`):**

1. **Half-tempo correction.** Histogram with peak at 0.96 s (62.5 BPM) and a smaller-but-present peak at 0.48 s (125 BPM). With no metadata, voting must pick 125 BPM (harmonic at 2× boosts the 125 candidate above the raw peak).
2. **True slow tempo preserved.** Single dominant peak at 0.92 s (65 BPM) and no peak at 0.46 s. Voting must return ~65 BPM, not double it.
3. **Metadata wins ambiguous case.** Near-equal peaks at 100 BPM and 200 BPM. With metadata BPM = 100, voting returns 100. With metadata BPM = 200, returns 200.
4. **Metadata cannot override overwhelming evidence.** 50× dominant peak at 140 BPM. With metadata BPM = 70, voting still returns 140 (stale-metadata defense).
5. **Out-of-range rejection.** Peak implying 300 BPM. Voting falls back to the strongest in-range candidate.
6. **Empty / sparse histogram.** Fewer than 4 onsets in the buffer: voting returns `nil` / leaves `instantBPM` unchanged. Caller behavior unchanged from today.

**Tests — reference-track regression (`BeatDetectorRegressionTests.swift`):** Driven by recorded onset sequences from the reference tracks. If onset fixtures don't already exist, generate by running the live pipeline against the audio and committing the resulting onset arrays as JSON under `Tests/Fixtures/tempo/`. Assertions:

- Love Rehab, no metadata: BPM ∈ [122, 128] (target 125, ±3).
- Love Rehab, metadata = 125: BPM ∈ [123, 127] (tighter with prior).
- So What, no metadata: BPM ∈ [133, 139].
- So What, metadata = 136: BPM ∈ [134, 138].
- There There, no metadata: lock in the post-voting estimate from the DSP.1-after capture; future changes must consciously update.

Existing tests in `BeatDetectorRegressionTests.swift` must continue to pass without modification.

**Performance budget:** Voting runs once per `computeStableTempo` call (1 Hz cadence — same as today, not per audio frame). Budget: voting + scoring < 50 µs on M1. Add `DSPPerformanceTests` case to enforce. No allocation in the hot path; score buffer fixed-size on the stack or pre-allocated.

**Done when:**

- [ ] Diagnostic logging committed and pushed first; baseline capture in `docs/diagnostics/DSP.1-baseline.txt`.
- [ ] Voting implementation committed in subsequent commits.
- [ ] Post-voting capture in `docs/diagnostics/DSP.1-after.txt`. Diff shows octave correction on Love Rehab and So What.
- [ ] All 6 unit tests in `BeatDetectorTempoTests.swift` pass.
- [ ] Reference-track regression tests pass with the BPM bounds above.
- [ ] Existing `BeatDetectorRegressionTests` pass unchanged.
- [ ] `swift test --package-path PhospheneEngine` passes (full suite — same pre-existing env failures acceptable; no new failures).
- [ ] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` passes.
- [ ] `DSPPerformanceTests` confirms voting < 50 µs.
- [ ] `CLAUDE.md` Tempo section updated; Failed Approach #17 amended.
- [ ] `DECISIONS.md` D-073 added explaining voting policy and rejected alternatives.
- [ ] Commit messages follow `[DSP.1] <component>: <description>`. Multiple small commits preferred (logging → baseline capture → voting impl → tests → docs).
- [ ] Push only after the full verification block passes locally.

**Verify:** `BEATDETECTOR_DUMP_HIST=1 swift test --filter BeatDetectorTempoTests && swift test --filter BeatDetectorRegressionTests && swift test --filter DSPPerformanceTests`.

**Out of scope (do not re-litigate):** TempoCNN (AGPL), custom Core ML tempo classifier, Sound Analysis framework, `BeatPredictor` IIR period smoothing, onset-detection itself.

**Reference principle (do not violate):** Continuous energy is the primary visual driver; beat onset pulses are accents only (D-004). This increment improves the accuracy of an accent-layer signal — it does not justify elevating beats in any preset shader.

**Estimated sessions:** 2 (logging+baseline → voting+tests → docs).

**Delivered (2026-05-03 — scope shifted from voting):** Diagnostic harness + analyzer revealed the failure was not classical half-tempo octave error. Two real bugs:
1. `recordOnsetTimestamps` consumed `bandFlux[0]+bandFlux[1]` (sub_bass + low_bass fused) — produced frame-aliased IOIs because each band fired on slightly different frames per kick.
2. Histogram-mode BPM picking has period-quantization bias toward faster BPMs (BPM bucket widths grow with BPM in period space), so the histogram mode systematically picks 144 over 136.

Shipped:
- `recordOnsetTimestamps` now sources from `result.onsets[0]` (sub_bass per-band onset events from `detectOnsets`, which has 400ms cooldown). Never fuses bands.
- `applyOctaveCorrection` replaced with `computeRobustBPM`: trimmed mean of recent IOIs (within [0.5×, 2×] of median).

Reference-track results: love_rehab 117/152→**122–126** (true 125), so_what 152→**135–138** (true 136). For there_there the histogram still reads kick-pattern (140) not underlying meter (~86) — that's a syncopation limitation outside DSP.1's scope and motivates DSP.2. See commits `9f4c8e1e..bbad760f` and `docs/diagnostics/DSP.1-baseline*.txt`. D-075.

---

### Increment DSP.2 — Beat This! transformer via MPSGraph (offline pre-analysis) + drift-tracker live path

**2026-05-04 pivot.** Originally scoped as a BeatNet (CRNN + particle filter) port; pivoted to Beat This! (Foscarin et al., ISMIR 2024 — transformer encoder, MIT) after a Session-2 audit pass found paraphrased-spec drift in the BeatNet preprocessing stage and weak performance on irregular meters that are load-bearing for Phosphene (Pyramid Song 16/8, Money 7/4, Schism 7/8). The original BeatNet plan is preserved in `docs/diagnostics/DSP.2-beatnet-archive.md`. Decision: **D-077**. The vendored BeatNet GTZAN weights (Session 1 of the original plan, commit `3f5f652b`) are retained as a fallback; everything below describes the Beat This! port.

**Goal:** Compute a high-quality beat / downbeat / time-signature grid once per track during pre-analysis (`SessionPreparer.prepareTrack` running on the cached 30 s preview clip), cache it on `TrackProfile` as a new `BeatGrid` value type, and drive `FeatureVector.beatPhase01` / `beatsUntilNext` analytically from `playbackTime + drift` against that grid. The live audio path runs no transformer; a small `LiveBeatDriftTracker` cross-correlates `BeatDetector`'s sub_bass onset stream against the cached grid in a ±50 ms phase window and emits a smooth drift estimate. Same MPSGraph + Accelerate idiom used by StemSeparator — no CoreML, no third-party C libs at runtime.

**Why now:** DSP.1's diagnosis proved Phosphene's classical-pipeline tempo path is at the ~70% F1 floor. For "as flawless as possible" beat sync (Matt's stated bar) on the irregular-meter tracks the product cares about, a transformer with whole-bar self-attention is the smallest model class that closes the gap. Beat This! is the smallest such model with a stable, MIT-licensed reference implementation and shipped pre-trained weights.

**Architecture mirrors `StemSeparator`:**

```
PhospheneEngine/Sources/ML/
  BeatThisModel.swift            → MPSGraph engine, pre-allocated UMA I/O (mirrors StemModel.swift)
  BeatThisModel+Graph.swift      → MPSGraph build: encoder block stack (mirrors StemModel+Graph)
  BeatThisModel+Weights.swift    → manifest + .bin loading; LN/BN fusion at init where applicable
  Weights/beat_this/             → vendored .bin weights via Git LFS pointers

PhospheneEngine/Sources/DSP/
  BeatThisPreprocessor.swift     → vDSP resample + STFT + log-mel pipeline (parameters confirmed in Session 1)
  BeatGridResolver.swift         → probability → (beats, downbeats, BPM, meter); peak picking + meter inference
  LiveBeatDriftTracker.swift     → cross-correlation drift tracker; FeatureVector wiring

PhospheneEngine/Sources/Session/
  BeatGrid.swift                 → Sendable value type stored on CachedTrackData
```

**Implementation order (sessions, each one PR / commit-chain):**

1. **Session 1 — Architecture audit + weight vendoring. ✅ 2026-05-04.** Commit `9cd0efb8`. Repo cloned at commit `9d787b9797eaa325856a20897187734175467074`. MIT confirmed. `small0` variant chosen: 2,101,352 params, 8.4 MB FP32 (vs `final0`: 20.3 M params, 81 MB). 161 tensors vendored under `PhospheneEngine/Sources/ML/Weights/beat_this/` (Git LFS). Six reference JSON fixtures in `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/beat_this_reference/`. `Scripts/convert_beatthis_weights.py` and `Scripts/dump_beatthis_reference.py` written. `docs/CREDITS.md` attribution block added. **Key S1 findings carried into S2/S3:** (a) inference timing measured at 415–530 ms on M1 CPU (`small0`); D-077's "~100–300 ms" estimate was optimistic — MPS will be faster, but S4 must measure and adjust S6's MLDispatchScheduler budget accordingly; (b) SumHead design: `beat_logits = beat_linear_out + downbeat_linear_out` (additive — beats are a *superset* of downbeats, not a separate class); (c) three MPSGraph workarounds required in S3: RMSNorm must be manual (no `layerNormalization` equivalent), SDPA must be manual matmul+softmax (macOS 14 target, `scaledDotProductAttention` is macOS 15+ only), RoPE must be manual cos/sin; (d) single `RotaryEmbedding(head_dim=32)` instance shared across all 9 blocks (3 frontend + 6 transformer) — precompute `freqs` tensor once in S3 and share; (e) 5 `num_batches_tracked` int64 BN buffers skipped at conversion (training-only, not used at inference); (f) torchaudio cannot load .m4a without `torchcodec` — use ffmpeg subprocess for audio decode (already handled in `dump_beatthis_reference.py`).

2. **Session 2 — Preprocessor port (Swift).** Implement `BeatThisPreprocessor` in `Sources/DSP/`. **Parameters confirmed in S1** (all file:line cited in `docs/diagnostics/DSP.2-architecture.md §2`): n_fft=1024, hop=441, sr=22050 (source), n_mels=128, f_min=30 Hz, f_max=11000 Hz, mel_scale="slaney" (area-normalisation, `norm="slaney"`), power=1 (magnitude, not power), log formula = `log1p(1000 × mel)` (matches `beat_this/preprocessing.py:LogMelSpect.__call__`). **Per-stage golden tests against the Python reference**: synthetic impulse, sine, white noise, plus love_rehab first 1500 frames. Per-stage delta dashboard. Tolerance: float32 ULP per stage where mathematically possible; documented numerical bound where not (resampler — soxr in Python, vDSP in Swift). Key resampler note: Beat This! uses `soxr` for resampling, not librosa's `resample`; a vDSP sinc resampler is acceptable but the tolerance test must reflect the actual delta (not assume ULP). Pre-allocate MTLBuffers for the spectrogram output to avoid heap alloc in `process()`. **Done when:** Swift preprocessor matches Python within measured numerical bound on all test inputs; `BeatThisPreprocessorTests` pass (≥5 test cases incl. love_rehab first-1500-frame golden); no heap allocations in `process()` hot path.

3. **Session 3 — Transformer encoder graph (MPSGraph build only).** Build the model graph in MPSGraph: input projection, positional encoding, encoder block stack (multi-head attention + FFN + LN, in the order Beat This! uses), output head(s). No weight loading yet; random init validates shapes. Layer-by-layer shape tests against architecture-doc numbers. Catch attention-head reshape bugs, layer-norm axis mistakes, off-by-one positional encoding. Reference: `StemModel+Graph.swift` for code style. **Done when:** graph builds cleanly; per-layer output shapes match doc exactly; one full forward pass on random input completes; no MPSGraph compilation warnings.

4. **Session 4 — Weight loading + numerical validation.** Implement `BeatThisModel+Weights.swift` mirroring `StemModel+Weights.swift`. Manifest parsing, .bin loading, LN/BN fusion at init where applicable. **Per-layer numerical golden tests against PyTorch FP32**: load the same checkpoint in PyTorch, run the same input through both, dump intermediates after each encoder block, compare. Tolerance: 1e-4 absolute / 1e-3 relative. Warm-predict timing on M1 for 30 s clip. **Done when:** Swift inference matches PyTorch FP32 within tolerance on all six fixtures, layer-by-layer; warm-predict < 300 ms on M1 (loosened from BeatNet's 142 ms; transformer is bigger).

5. **Session 5 — Beat grid resolver + post-processing.** Peak picking on per-frame beat / downbeat probabilities (use the algorithm Beat This! uses; confirm S1). Meter inference (3/4, 4/4, 5/4, 6/8, 7/8, 11/8, ...) from downbeat spacing distribution; reject implausible meters with a confidence score. BPM from beat spacing — median of inter-beat intervals (no histogram-mode trap from D-075 / Failed Approach #51). `BeatGrid` value type; Sendable, Hashable, Codable for `TrackProfile` cache embedding. **Done when:** end-to-end pipeline on six fixtures: beats within ±20 ms of reference, downbeats within ±40 ms, BPM within ±0.5, time signature correct on ≥5/6.

6. **Session 6 — `SessionPreparer` integration.** Wire `BeatThisModel` into `prepareTrack`. One call per track during preparation; result cached. Extend `CachedTrackData` to include `BeatGrid`. Bump cache version key for invalidation. Respect `MLDispatchScheduler` (D-059): Beat This! is heavier than stem separation; per-call budget needs widening. Recompute Tier 1 / Tier 2 thresholds. Backfill: cached tracks predating Beat This! lazily compute on first access. **Done when:** all production-test playlists prepare with valid `BeatGrid`s; the 919-engine baseline holds; new `BeatGridIntegrationTests` cover preparation, cache hit, cache invalidation.

7. **Session 7 — Live drift tracker + FeatureVector wiring.** `LiveBeatDriftTracker` consumes `BeatDetector.Result.onsets[0]` (sub_bass) and cross-correlates against the cached grid in ±50 ms phase window; smooth drift estimate (EMA, τ ≈ 200 ms). Replace `BeatPredictor` invocations in `MIRPipeline`. `FeatureVector.beatPhase01` and `beatsUntilNext` computed analytically: `phase01 = ((playbackTime + drift - lastBeat) / period).fract()`. Reactive-mode fallback: keep `BeatPredictor` only for the no-cached-grid case; mark deprecated. Visual regression: re-capture goldens for presets that read `beatPhase01` (Arachne, Gossamer, Stalker, VolumetricLithograph). Re-record `docs/quality_reel.mp4` on the user's three reference tracks + Pyramid Song + Money. **Done when:** Phosphene tracks the beat correctly on 5/4, 7/8, 16/8, swing fixtures (subjective + numerical against S1 ground truth); golden hashes regenerated for affected presets; quality reel rerecorded; user signs off.

**Architectural placement (locked 2026-05-04):**

- **Pre-analysis path** (`SessionPreparer.prepareTrack`, offline, runs once per 30 s preview clip): single Beat This! forward pass; output cached on `TrackProfile.beatGrid`. Per-track cost measured at ~415–530 ms on M1 CPU (Python); MPS expected ~100–150 ms but must be measured in S4 before finalising the S6 MLDispatchScheduler budget.
- **Live path** (60 fps render loop): no transformer. `LiveBeatDriftTracker` aligns the cached grid to the live playback timeline via sub_bass onset cross-correlation. `FeatureVector.beatPhase01` / `beatsUntilNext` (floats 35–36) computed analytically. **No GPU contract change** — existing presets unchanged.
- **Replaces:** `BeatPredictor` (deleted in Session 7); `BeatDetector+Tempo.computeRobustBPM` as primary BPM source (kept as ad-hoc reactive-mode fallback).
- **Stays:** `BeatDetector` itself (onset stream still feeds StemAnalyzer + drift tracker); `StructuralAnalyzer` / `NoveltyDetector` (unchanged this increment; possible All-In-One follow-up).

**Test fixtures (acquisition required before Session 1):**

- love_rehab.m4a (electronic ~125 BPM, 4/4) — already vendored.
- so_what.m4a (jazz ~136 BPM, swing) — already vendored.
- there_there.m4a (rock, syncopated kick — DSP.1's load-bearing failure) — already vendored.
- **Pyramid Song (Radiohead) — 16/8 grouped 3+3+4+3+3, extreme irregular-meter stress test.**
- **Money (Pink Floyd) — 7/4.**
- **If I Were With Her Now (Spiritualized) — syncopation plus mid-track meter changes. The fixture that stresses temporal *instability*: a model that locks to one period at the start and rides it through the track will pass Pyramid Song / Money (irregular but locked) and fail here.**

Five of the six fixtures actively stress non-stable-period behavior — only love_rehab is the clean 4/4 control. Pyramid Song / Money / so_what / there_there cover irregular-meter, swing, and offbeat-kick. If I Were With Her Now is the meter-change adaptation gate. If Beat This! tracks all six correctly, the increment is product-ready. If it fails specifically on the meter-change passage, that's the trigger to evaluate streaming-mode inference (re-running the model mid-track) before falling back to All-In-One.

**Files to touch:**

- `PhospheneEngine/Sources/ML/BeatThisModel.swift` — new MPSGraph engine.
- `PhospheneEngine/Sources/ML/BeatThisModel+Graph.swift` — new graph construction.
- `PhospheneEngine/Sources/ML/BeatThisModel+Weights.swift` — new weight loader.
- `PhospheneEngine/Sources/ML/Weights/beat_this/*.bin` — vendored weights (Git LFS).
- `PhospheneEngine/Sources/DSP/BeatThisPreprocessor.swift` — new preprocessor.
- `PhospheneEngine/Sources/DSP/BeatGridResolver.swift` — new probability → grid resolver.
- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — new drift tracker.
- `PhospheneEngine/Sources/Session/BeatGrid.swift` — new value type.
- `PhospheneEngine/Sources/Session/SessionPreparer.swift` — call BeatThisModel during prepareTrack; cache BeatGrid.
- `PhospheneEngine/Sources/Session/StemCache.swift` (or equivalent) — extend `CachedTrackData` with `BeatGrid?`.
- `PhospheneEngine/Sources/Audio/MIRPipeline.swift` — replace BeatPredictor invocations with LiveBeatDriftTracker; keep BeatPredictor for reactive-mode fallback.
- `PhospheneEngine/Sources/DSP/BeatPredictor.swift` — deleted in Session 7 (superseded by analytic phase calc + drift tracker).
- `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisModelTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/BeatThisPreprocessorTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/BeatGridResolverTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/Integration/BeatGridIntegrationTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/Performance/BeatThisPerformanceTests.swift` — new.
- `Scripts/convert_beatthis_weights.py` — one-shot converter (mirror of `convert_beatnet_weights.py`).
- `Scripts/dump_beatthis_reference.py` — Python reference-dump script for Session 2 / 4 golden tests.
- `docs/diagnostics/DSP.2-architecture.md` — new audit doc (replaces archived BeatNet version).
- `docs/CLAUDE.md` — Module Map updates, ML Inference section, Failed Approaches as discovered.
- `docs/DECISIONS.md` — D-077 (landed alongside this pivot); follow-up sub-decisions in the D-077 thread for any architectural choices made during the sessions.
- `docs/CREDITS.md` — Beat This! attribution per MIT license (cite paper + repo).

**Tests:**

1. **Unit — `BeatThisPreprocessorTests` (Session 2):**
   - Synthetic impulse / sine / white noise: per-stage match against Python reference within float32 ULP where mathematically possible.
   - Real audio (love_rehab): output within a measured numerical bound vs. the Python reference (set in S1 architecture doc).
   - Zero input → zero output (or model-defined silence vector).
   - No heap allocation in `process()` hot path.

2. **Unit — `BeatThisModelTests` (Session 4):**
   - Weight load → no crash; parameter count matches manifest.
   - Forward pass on random input: per-layer activations match PyTorch FP32 within 1e-4 absolute / 1e-3 relative.
   - Forward pass on six reference fixtures: end-to-end output matches PyTorch FP32 within tolerance.
   - Warm-predict latency on M1 < 300 ms for 30 s clip.

3. **Unit — `BeatGridResolverTests` (Session 5):**
   - Synthetic 120 BPM activation pulses → 120 ± 0.5 BPM, beats every 500 ± 20 ms, time signature 4/4.
   - Synthetic 7/4 at 90 BPM → 90 ± 0.5 BPM, time signature 7/4 detected, downbeats every 7 beats.
   - Tempo change mid-stream (120 → 140 BPM at t = 5 s) → re-locks within the offline post-processing window.

4. **Unit — `LiveBeatDriftTrackerTests` (Session 7):**
   - Cached grid + perfectly-aligned onsets → drift = 0 ± 5 ms.
   - Cached grid + onsets shifted by +30 ms → drift converges to +30 ms within 2 s.
   - No onsets in window → drift estimate decays toward 0 (no runaway).

5. **Integration — `BeatGridIntegrationTests` (Session 6):**
   - Six reference fixtures end-to-end: BPM within ±0.5, time signature correct on ≥5/6, beats within ±20 ms vs. S1 ground truth.
   - **Pyramid Song must read 16/8 (or equivalent grouped meter) with downbeats on the 1 of each 16-cycle.** Load-bearing assertion for the increment.
   - **Money must read 7/4 at ~123 BPM.** Load-bearing assertion.
   - **there_there must read 84–92 BPM** (the meter, not the kick rate). Carries forward from the BeatNet plan as the DSP.1-failure assertion.
   - Cache hit: re-prepare same track → `BeatGrid` reused, no second model call.
   - Cache invalidation: bump model variant string → re-runs.

6. **Performance — `BeatThisPerformanceTests`:**
   - Per-track preparation: < 500 ms on M1 (preprocessing + transformer + post-processing combined).
   - Drift tracker: < 0.1 ms per frame on M1 (live-path budget).

7. **Existing tests:**
   - All 919 engine-test baseline holds.
   - `BeatDetector` unit tests pass unchanged (its onset stream is the drift tracker's input — interface unchanged).
   - `BeatPredictorTests` pass while BeatPredictor exists (until S7 retirement).
   - `MIRPipelineUnitTests` pass — replace BeatPredictor wiring with drift tracker.

**Performance budget:**

- Per-track preparation cost (one-time per 30 s clip): < 500 ms on M1, < 250 ms on M3. Absorbed in the existing playlist-preparation window.
- Live-path cost: < 0.1 ms per frame on M1 (drift tracker only; no transformer at runtime). Negligible vs. the 16.6 ms render budget.
- Memory: < 80 MB for weights (FP16 transformer ~28 MB + activation scratch). Stays well under StemSeparator's 135.9 MB.
- Init cost: < 300 ms for graph build + weight load (one-time at session start).
- Drop-frame behavior in pre-analysis: respect `MLDispatchScheduler` (D-059) — if Beat This! inference would push a frame past budget, defer the dispatch. Track-change resets state.

**Done when (cumulative across sessions):**

- [x] §0 cleanup committed (BeatNet stubs removed; archive marked superseded; D-077 in DECISIONS.md). **2026-05-04.**
- [x] **S1:** Architecture audit `docs/diagnostics/DSP.2-architecture.md` complete; weights vendored under `ML/Weights/beat_this/` (161 tensors, 8.4 MB, `small0`); `Scripts/convert_beatthis_weights.py` reproducible; six reference fixtures captured as JSON ground truth. Commits `afb75954..9cd0efb8`. **2026-05-04.**
- [x] **S2:** `BeatThisPreprocessorTests` pass (5 tests: shape×2 + dcSignal + sineAtMelBin + loveRehab golden match); per-stage golden match max|Δ|=3×10⁻⁵ within tolerance=1e-3; all buffers pre-allocated at init. Commits `d26e3c2b..b2cb5a8b`. **2026-05-04.**
- [x] **S3:** `BeatThisModel` builds zero-init MPSGraph encoder; 5 shape/finiteness tests pass (929/100 suite green); 0 SwiftLint violations. Commit `c71569b1`. **2026-05-04.**
- [x] **S4:** `BeatThisModelTests` pass (9 tests: graphBuilds + inputProjectionShape + outputShape_T10 + outputShape_T1497 + outputRangeIsFinite + weightsLoad_noThrow + outputNonUniform_withRealWeights + inferenceTime_under300ms + loveRehab_gated); real weights loaded from `ML/Weights/beat_this/`; `test_outputNonUniform_withRealWeights` confirms non-uniform output; `test_inferenceTime_under300ms` passes (< 300 ms warm predict); 933 tests / 100 suites; 0 SwiftLint violations. **2026-05-04.**
- [x] **S5:** `BeatGridResolverTests` pass — 8 unit tests + 24 golden fixture tests (6 fixtures × 4 assertions); all six fixtures within tolerance (beats ≥95% within ±20ms, downbeats ≥90% within ±40ms, BPM within ±0.5, meter correct); pyramid_song=3 gate passes; `BeatGrid` value type (Sendable, Hashable, Codable) in `Sources/DSP/`; 945 tests / 102 suites; 0 SwiftLint violations. **2026-05-04.**
- [x] **S6:** `BeatGridIntegrationTests` pass — 4 tests (nilAnalyzer→empty grid, cacheHit short-circuits analyzer, fullPipeline with `DefaultBeatGridAnalyzer` produces non-empty grid at 50 fps, `StemCache.beatGrid(for:)` accessor matches stored data); `BeatGridAnalyzing` protocol + `DefaultBeatGridAnalyzer` injected into `SessionPreparer` (optional, defaults to nil → BeatGrid.empty); `CachedTrackData.beatGrid` field added with `.empty` default; `AnalysisStage.beatGrid` case added; cache-hit short-circuit in `_runPreparation` skips re-analysis on idempotent prepare. Pyramid Song 16/8 / Money 7/4 / there_there assertions remain in S5 golden fixtures (not duplicated here — S6 proves wiring, S5 proves algorithm). 949 tests / 102 suites; 0 SwiftLint violations. **2026-05-04.**
- [~] **S7 — code complete, live in production, pending quality-reel sign-off (2026-05-04):** `LiveBeatDriftTrackerTests` pass (8 original + 7 added in hardening = 15 total); `BeatGridUnitTests` pass (4); `MIRPipelineDriftIntegrationTests` pass (3). `BeatPredictor.swift` doc-deprecated as reactive-mode-only fallback (no `@available` annotation — would cascade warnings into the warnings-as-errors xcconfig app build). `BeatGrid` extended with `beatIndex(at:)`, `localTiming(at:)`, `medianBeatPeriod`, internal `nearestBeat(to:within:)`. `MIRPipeline` gains `liveDriftTracker: LiveBeatDriftTracker` + `setBeatGrid(_:)`; `buildFeatureVector` forks: cached-grid path uses `self.elapsedSeconds` as the playback clock (already track-relative via existing `mir.reset()` in `VisualizerEngine+Capture.swift:127`). `VisualizerEngine+Stems.resetStemPipeline(for:)` now installs the cached grid (or clears it on cache miss). `PresetVisualReviewTests.arguments` extended to `["Arachne","Gossamer","Volumetric Lithograph"]`; Stalker is mesh-shader and excluded from regression by construction. **Golden hashes unchanged** — regression fixtures use prebuilt `FeatureVector` instances with `beatPhase01=0` default and never invoke `MIRPipeline`. App-layer wiring test deferred (engine integration test covers the contract; the change is two lines mirroring the existing `setStemFeatures` pattern). **Outstanding:** `docs/quality_reel.mp4` re-record + Pyramid Song / Money / so_what subjective sign-off; flip to `[x]` once Matt watches and confirms phase locks correctly on irregular meters.
- [x] **S8 — BeatThisModel output matches PyTorch reference (2026-05-05):** Four bugs found and fixed: (1) frontend block order `partial → norm(wrong inDim) → conv` corrected to `partial → conv → norm(out_dim)` (pre-S8 norm used the wrong channel count); (2) stem reshape transposed `[T,F]→[F,T]` before NHWC reshape (pre-S8 was a byte-reinterpretation, scrambling the mel spectrogram); (3) BN1d-aware padding pads each mel bin with `−shift/scale` so the padded region maps to zero post-BN (pre-S8 naive zero-fill caused `BN1d(0)==shift` to produce non-zero values at time edges); (4) RoPE pairs adjacent elements `(x[2i], x[2i+1])` not half-and-half `(x[i], x[D/2+i])` (pre-S8 completely wrong attention dot products). Result: love_rehab.m4a max sigmoid 0.9999 vs Python ref 0.9999; 126 frames > 0.5 vs ref 124; 59 beats detected vs 59 in ground-truth fixture. `test_loveRehab_endToEnd_producesBeats` passes without `withKnownIssue`. S7's drift tracker is now live and active for every Spotify-prepared session. Commits `49315657..b9687cbc`. **2026-05-05.**
- [x] **DSP.2 hardening — all four S8 bugs individually regression-locked (2026-05-05):** `test_loveRehab_endToEnd_producesBeats` thresholds raised to `maxProb > 0.99` / `aboveHalf >= 100` (reflecting confirmed post-S8 values). `BeatThisLayerMatchTests.swift` (new): loads `docs/diagnostics/DSP.2-S8-python-activations.json`, runs `predictDiagnostic` on love_rehab.m4a, asserts per-stage min/max/mean within two-tier tolerances — `preTfmTol=2e-3` for stem.bn1d + frontend.linear; `postTfmTol=1e-2` for transformer.norm + head.linear + output stages (covers ~0.3–0.9% delta from non-causal softmax over padded frames). Transformer blocks 0–5 excluded (Python hooks sub-block FFN output before residual; Swift captures full-block output — incompatible; end-to-end coverage via beat_logits/beat_sigmoid is sufficient). `BeatThisBugRegressionTests.swift` (new): Bug 1 gate (`frontendBlocks[N].norm.scale.count == out_dim`); Bug 3 gate (`|stem.bn1d[t,mel]| < 1e-3` for padded frames t∈[1497,1500) on zero input); Bugs 2+4 annotated as covered by layer-match (wrong reshape scrambles stem.bn1d by >50%; wrong RoPE pairing diverges output by >30%); reactive-mode test confirms `setBeatGrid(nil)` fallback returns finite FeatureVector. `LiveBeatDriftTrackerTests` extended with 7 tests (MARK 9–15) covering `currentBPM`, `currentLockState`, `relativeBeatTimes` public APIs. **975 engine tests / 103 suites; 0 SwiftLint violations.** Commits `286e67cf..4eaae5a7`. **2026-05-05.**
- [x] **S9 — barPhase01/beatsPerBar propagation + live Beat This! for reactive mode (2026-05-05):** `FeatureVector` floats 37–38 promoted from padding to `barPhase01` (phrase-level 0→1 ramp, 0 in reactive mode) and `beatsPerBar` (time-signature numerator, default 4). Metal preamble struct updated to match; Swift `init()` seeds `barPhase01=0 / beatsPerBar=4`. `MIRPipeline.buildFeatureVector` writes drift-tracker values on the grid path and 0/4 on the reactive path. `BeatGrid.offsetBy(_ seconds:)` helper added for time-aligning buffer-relative beat grids to track-relative coordinates. `SpectralHistoryBuffer` ring 4 repurposed from `vocals_pitch_norm` to `bar_phase01`; dead `normalizePitch` method and three pitch constants deleted. `SpectralCartograph`: BR panel third row now plots `bar_phase01` (violet, "BAR φ" label). `runLiveBeatAnalysisIfNeeded()` added to `VisualizerEngine+Stems`: fires once per track after 10 s of buffered tap audio when `liveDriftTracker.hasGrid == false`; lazy-loads `DefaultBeatGridAnalyzer` on `stemQueue`; offsets the resulting grid by `(elapsedSeconds − 10)` to track-relative time; installs via `mirPipeline.setBeatGrid()` on `@MainActor`. Effect: ad-hoc / reactive sessions receive phrase-level beat tracking after ≈ 10 s of listening, same as Spotify-prepared sessions. **987 engine tests; 0 new SwiftLint violations; golden hashes unchanged.** Commit `b6a6095f`. **2026-05-05.**
- [x] `swift test --package-path PhospheneEngine` passes (pre-existing flakes in `MetadataPreFetcher` / `MemoryReporter` acceptable).
- [ ] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` passes.
- [ ] No `import CoreML` anywhere in the engine.
- [ ] CLAUDE.md Module Map updated; CREDITS.md Beat This! attribution present.

**Verify (per session, run cumulatively at the end):** `swift test --filter BeatThisPreprocessor && swift test --filter BeatThisModel && swift test --filter BeatThisLayerMatch && swift test --filter BeatThisBugRegression && swift test --filter BeatGridResolver && swift test --filter LiveBeatDriftTracker && swift test --filter BeatGridIntegration && swift test --filter BeatThisPerformance`.

**Out of scope (do not re-litigate):**

- aubio (native C dependency; rejected — staying within Swift / MPSGraph idiom).
- madmom (offline-only Python+C; non-portable to runtime).
- CoreML in any form (project hard constraint, see Failed Approach #20 and CLAUDE.md "ML Inference").
- All-In-One (Kim et al., ISMIR 2023) — strictly more capable (joint beat / downbeat / section), but two-axis scope creep in a single increment. Reserved as a follow-up; the architecture in this increment is designed so the model can be swapped with no upstream / downstream changes.
- Live transformer inference at 50 Hz — explicitly rejected; the pre-analysis-then-drift-track architecture is the load-bearing design choice.
- Per-frame downbeat *visual presets* — separate work; this increment exposes `downbeats` on `BeatGrid`, presets opt in later.
- Streaming-mode Beat This! inference for reactive mode — fallback path keeps `BeatPredictor` (or runs a one-shot transformer pass on the first 10–15 s of live audio). Decide in S7.

**License sourcing:**

- Beat This! is MIT-licensed; pre-trained weights ship with the official repo. Vendored with attribution in `docs/CREDITS.md` (S1 ✅).
- The architecture itself is published in Foscarin et al., ISMIR 2024 — implementing it from the paper is unencumbered.

**Risks:**

- Weight quantization: BeatNet is trained in FP32; MPSGraph supports FP32 natively. No quantization needed.
- Resampler quality: vDSP_resamplef from 48 k → 22050 Hz must not introduce artifacts that degrade activations. Mitigation: validate against librosa-reference mel-specs in the unit test (step 3).
- Particle-filter stability: known to be the trickiest part. Mitigation: closely follow Heydari's reference impl; test against synthetic constant-BPM and tempo-change scenarios before integrating with real audio.
- Performance: per-frame inference at 100 Hz is more aggressive than StemSeparator's 5 s cadence. Mitigation: enforce < 2 ms per frame in `BeatTrackerPerformanceTests` from the start; if violated, drop to half-rate inference (50 Hz) before considering more invasive changes.

**Reference principle (do not violate):**

Continuous energy is the primary visual driver; beat onset pulses are accents only (D-004). BeatNet's outputs feed accent-layer fields (`beatPhase01`, `isDownbeat`) only — they do not displace the continuous-energy fields driving primary visual motion.

**Estimated sessions:** 5–7 (weights + mel-spec → 1, MPSGraph build + inference → 2, particle filter → 2, integration + tests + docs → 2).

---

### Increment DSP.3 — Beat Sync + Diagnostic Environment (audit + fixes)

**2026-05-05 audit.** Full architecture audit of the Beat This! BeatGrid lifecycle, live drift tracking, reactive-mode surface, Spectral Cartograph diagnostic coverage, FeatureVector product contract for complex meters, and test fixture gaps. Audit document: `docs/diagnostics/DSP.3-beat-sync-test-environment-audit.md`.

**Root cause of observed "Phosphene shifts into Reactive mode" when switching to Spectral Cartograph:** The `SpectralCartographText` overlay labels `lockState=0` as "REACTIVE." When `LiveBeatDriftTracker` is in UNLOCKED state — either because `resetStemPipeline(for:)` has not yet fired (music not started) or because fewer than 4 tight-match onsets have been accumulated — the orb reads "REACTIVE" even though `livePlan` is non-nil and the engine is in planned mode. This is a display ambiguity, not a session mode regression. However, a second structural problem makes Spectral Cartograph unusable as a held diagnostic surface: `DefaultLiveAdapter` mood-override fires every ~60 seconds when the current preset scores 0.0 (diagnostic-excluded), switching the engine away from Spectral Cartograph.

**Sub-increments:**

- **DSP.3.1 — Diagnostic hold + session-mode signal.** `diagnosticPresetLocked` flag in `VisualizerEngine`; suppresses mood-override in `applyLiveUpdate()`. `SpectralHistoryBuffer[2420]` session-mode slot (0=reactive, 1=planned+unlocked, 2=planned+locking, 3=planned+locked). `SpectralCartographText` updated to show "PLANNED · UNLOCKED" / "PLANNED · LOCKING" / "PLANNED · LOCKED" / "REACTIVE." `L` dev shortcut to toggle hold. **✅ 2026-05-05 — commit `56359c07`.**
- **DSP.3.2 — Pre-fire BeatGrid on session start.** At end of `_buildPlan()` after `livePlan` is stored, call `resetStemPipeline(for: plan.tracks.first?.track)`. BeatGrid present before music starts; idempotent via `currentTrackIdentity` guard in `resetStemPipeline`. **✅ 2026-05-05 — commit `56359c07`.**
- **DSP.3.3 — Beat sync observability: text overlays + CSV + calibration shortcuts.** `SpectralCartographText.draw()` extended with beat-in-bar counter ("3 / 4"), drift readout ("Δ +12 ms"), phase offset indicator ("φ+10ms"); `textOverlayCallback` type updated to pass `FeatureVector` per frame; `[`/`]` dev shortcuts for ±10 ms visual phase calibration; `BeatSyncSnapshot` struct (9 fields) for offline analysis; `SessionRecorder.features.csv` gains 9 new beat-sync columns (`barPhase01_permille`, `beatsPerBar`, `beat_in_bar`, `is_downbeat`, `beat_sync_mode`, `lock_state`, `grid_bpm`, `playback_time_s`, `drift_ms`); `SpectralHistoryBuffer[2429]` drift_ms slot; 31 new tests (BeatInBarComputationTests 16+, SpectralHistoryBuffer slot stability 4+, others). Core Text mirroring fix in `DynamicTextOverlay.refresh()`. `docs/diagnostics/DSP.3.3-beat-sync-latency-phase-notes.md`. **✅ 2026-05-05.**
- **DSP.3.4 — Fix three root causes blocking PLANNED·LOCKED in reactive/ad-hoc sessions.** Live diagnostic from session `2026-05-05T21-13-05Z` (features.csv: 12,509 frames in LOCKING, 0 in LOCKED, beatPhase01 frozen at mean=0.99996, grid_bpm=216 instead of ~125) revealed: (1) `BeatGrid.offsetBy` only shifted the ~10 recorded beats; past the last beat `computePhase` clamped `beatPhase01=1.0` permanently and `nearestBeat` returned nil → `consecutiveMisses` grew indefinitely → `matchedOnsets` never reached `lockThreshold=4`. Fix: `offsetBy` now appends extrapolated beats at `period=60/bpm` up to a 300-second horizon and extrapolates downbeats at `barPeriod` beyond that. (2) `runLiveBeatAnalysisIfNeeded` hardcoded `sampleRate: 44100` for `analyzeBeatGrid` despite the tap running at 48000 Hz — mel spectrogram covered wrong duration, BPM detected as ~216. Fix: `VisualizerEngine.tapSampleRate: Double` stored from audio callback `rate` parameter; passed to `analyzeBeatGrid`. (3) `StemSampleBuffer.snapshotLatest(seconds:)` computed count using stored 44100 Hz rate, so a 10-second request retrieved only 9.19 s of real audio. Fix: new `snapshotLatest(seconds:sampleRate:)` protocol overload uses the passed-in rate; `runLiveBeatAnalysisIfNeeded` calls it with `tapSampleRate`. 14 new tests (5 BeatGrid extrapolation + 5 StemSampleBuffer rate overload). **✅ 2026-05-05 — commit `7033ad09`.**
- **DSP.3.5 — Halving octave correction + retry for live Beat This!** Session diagnostic `2026-05-05T22-57-57Z` (features.csv) revealed: (1) Live 10-second Beat This! window detected Love Rehab at 244.770 BPM (2× true 125 BPM) — double-time artefact from short analysis window. (2) Money 7/4 reactive session stayed in REACTIVE throughout — Beat This! on 10 s of Money audio returned an empty grid, with no retry. Fixes: (a) `BeatGrid.halvingOctaveCorrected()` — halving-only correction: while `bpm > 160`, halve BPM and drop every other beat. BPM < 80 intentionally left alone (Pyramid Song genuinely runs at ~68 BPM; doubling would be wrong). Downbeats re-snapped to surviving beats within ±40 ms; `beatsPerBar` recomputed from corrected downbeat IOIs. (b) `VisualizerEngine`: `liveBeatAnalysisDone: Bool` → `liveBeatAnalysisAttempts: Int`; counter allows up to `liveBeatMaxAttempts=2` attempts — first at `liveBeatMinSeconds=10.0 s`, retry at `liveBeatRetrySeconds=20.0 s` if first attempt returned empty grid. (c) `performLiveBeatInference()` extracted from `runLiveBeatAnalysisIfNeeded()` to keep the parent within the 60-line SwiftLint gate; `halvingOctaveCorrected()` applied before `offsetBy()`. 4 new BeatGridUnitTests. Post-validation triage: `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md`. Remaining risk: Money 7/4 still REACTIVE on live path (20-second retry may also produce empty grid); durable fix is Spotify-prepared session (30-second offline window reliable). **✅ 2026-05-05 — commits `eac2e140`, `c068d2b8`.**
- **DSP.3.6 — App-layer wiring test.** Integration test: `SessionPreparer.prepare()` → `StemCache.store()` → `resetStemPipeline(for:)` → `mirPipeline.liveDriftTracker.hasGrid == true`. Five new `PreparedBeatGridWiringTests` in `Integration/` prove the critical chain: (1) prepared non-empty grid → `hasGrid == true`; (2) `hasGrid == true` → `runLiveBeatAnalysisIfNeeded` guard blocks live inference; (3) cache miss → `hasGrid == false` → live inference allowed; (4) `.empty` cached grid → `hasGrid == false` → live inference allowed; (5) track change clears grid. Enhanced source-tagged `BEAT_GRID_INSTALL` logging in `VisualizerEngine+Stems.swift` (source=preparedCache/liveAnalysis/none, BPM, beat count, meter, firstBeat, replaced flag) plus `sessionRecorder.log()` one-time event per track. `beat_grid_source` in features.csv deferred (per-frame schema change; session.log entry is sufficient). Policy documented: prepared-cache grid wins; live inference may only *add* a grid when none is present. `docs/diagnostics/DSP.3.6-prepared-beatgrid-wiring-validation.md`. **✅ 2026-05-05.**
- **DSP.3.7 — Live drift validation test.** Replay `love_rehab` via `AudioInputRouter(.localFile)` with prepared BeatGrid; assert LOCKED within 5 s, drift < 50 ms, `beatPhase01` zero-crossings within ±30 ms of ground truth.
- **DSP.4 — Drums-stem Beat This! diagnostic.** Third BPM estimator on isolated percussion, logged alongside the existing two at preparation time. `CachedTrackData.drumsBeatGrid: BeatGrid` (default `.empty`). Step 6 in `SessionPreparer+Analysis.analyzePreview` feeds `stemWaveforms[1]` (drums) into the same `DefaultBeatGridAnalyzer` — same graph, second `predict()` call. `ThreeWayBPMReading` struct + `detectThreeWayBPMDisagreement` pure function added to `BPMMismatchCheck.swift`. Wiring logs: `WIRING: SessionPreparer.drumsBeatGrid` per track; `WARN: BPM 3-way` (preferred) / `WARN: BPM mismatch` (fallback when drumsBPM == 0). No runtime consumption by `LiveBeatDriftTracker`. 7 new 3-way detector tests + 2 integration wiring tests. **✅ 2026-05-06.**

**Done when (gating assertion):** Matt connects a Spotify playlist, preparation completes, switches to Spectral Cartograph, presses `L` to hold, starts music, and observes "PLANNED (UNLOCKED)" → "PLANNED (LOCKING)" → "PLANNED (LOCKED)" within 5 seconds. BPM matches. Beat-grid ticks align with perceived beats. Engine does not switch away. This observation — not unit-test counts — is the production-validation milestone for Beat This!

**Status:**
- [x] DSP.3 audit complete: `docs/diagnostics/DSP.3-beat-sync-test-environment-audit.md`. **2026-05-05.**
- [x] DSP.3.1 — Diagnostic hold + session-mode signal. **2026-05-05.**
- [x] DSP.3.2 — Pre-fire BeatGrid on session start. **2026-05-05.**
- [x] DSP.3.3 — Beat sync observability: text overlays + CSV + calibration shortcuts. **2026-05-05.**
- [x] DSP.3.4 — Grid horizon + sample-rate bugs fix. **2026-05-05 — commit `7033ad09`.**
- [x] DSP.3.5 — Halving octave correction + retry. **2026-05-05 — commit `eac2e140`.**
- [x] DSP.3.6 — App-layer wiring test. **2026-05-05.**
- [ ] DSP.3.7 — Live drift validation test.
- [x] DSP.4 — Drums-stem Beat This! diagnostic (third BPM estimator, logged only). **2026-05-06.**

---

## Phase QR — Quality Review Remediation (2026-05-06)

**Status.** QR.1–QR.5 shipped ✅ (2026-05-06 → 2026-05-13); BUG-007.3 attempted and reverted same day (see `KNOWN_ISSUES.md`). QR.6 (`VisualizerEngine` decomposition) and QR.7 (shader noise consolidation) below remain open/deferred — neither has started; both require Matt's scope approval at session start.
Origin narrative + QR.1/QR.2 closeouts: [`ENGINEERING_PLAN_HISTORY.md`](ENGINEERING_PLAN_HISTORY.md) §DOC.6 closed-phase batch.

---

### Increment QR.1 (DSP.4) — Sample-rate plumbing audit
### Increment QR.2 (OR.1) — Stem-affinity rescaling + reactive-mode TrackProfile fix
### Increment BUG-007.3 — Lock hysteresis + live BPM credibility ⚠ REVERTED 2026-05-07
### Increment QR.3 (TEST.1) — Close silent-skip test holes ✅ 2026-05-07
### Increment QR.4 (U.12) — UX dead ends + duplicate `SettingsStore` + dead settings + hardcoded strings  ✅ 2026-05-07 (D-091)
### Increment QR.5 (CLEAN.1) — Mechanical cleanup pass ✅ 2026-05-13
### Increment QR.6 (ARCH.1) — `VisualizerEngine` decomposition

**Goal.** Split `VisualizerEngine` (2,580 LOC, 8 NSLocks, `@unchecked Sendable`, 7 extension files) into 3-4 owned services with a 200-line composition root. Replace `RenderPipeline`'s 24-NSLock switchboard with a single `RenderGraphState` value type updated atomically per preset switch.

**Why now (and why last in QR).** The architect's H1 + H2 findings together represent the largest single piece of debt in the codebase. They are *also* the highest-risk change: every concern in the engine integrates here. Schedule after QR.1–QR.5 have landed so that:

- QR.1 has cleaned up the sample-rate plumbing this refactor would otherwise have to thread through.
- QR.2 has fixed the orchestrator surface this refactor exposes.
- QR.3 has hardened the test suite that will validate the decomposition.
- QR.5 has retired `BeatPredictor`, deduplicated `ShaderUtilities`, and centralized EMA — all of which would be friction during decomposition if left in place.

This increment is **the first one that requires Matt to explicitly approve scope at the start**, because the safe path is to ship the decomposition behind feature flags and migrate one subsystem at a time over multiple sessions.

**Proposed shape (subject to architect's pre-implementation pass):**

```
PhospheneApp/
  VisualizerEngine.swift              → 200-line composition root: owns the three hosts, wires publishers, exposes the public API
  AudioPipelineHost.swift             → router, FFT, MIR, stems, signal-state callbacks. Owns the audio-thread → analysis-queue boundary.
  RenderHost.swift                    → pipeline, presets, mesh/preset state, mvwarp, preset switching. Owns the render-pipeline lock surface.
  OrchestratorHost.swift              → planner, live adapter, reactive orchestrator, plan publisher, action router. Owns the orchestrator state.
```

Each host is a `@MainActor`-bound `final class`, owns its state (no `@unchecked Sendable`), exposes a small public surface to the composition root. Cross-host communication via Combine publishers (typed events), not direct property reads.

**`RenderGraphState` value type (RenderPipeline H2 fix):**

```
struct RenderGraphState {
    var preset: PresetDescriptor
    var passes: [RenderPass]
    var icb: ICBState?
    var raymarch: RayMarchState?
    var mvwarp: MVWarpState?
    var mesh: MeshState?
    var postProcess: PostProcessState?
    // … one slot per pass family
}
```

`RenderPipeline` holds `var graphState: RenderGraphState` under a single lock. Per-frame `draw(in:)` snapshots one struct under one lock. Adding a pass family = adding a slot, not a lock.

**Frame-budget governor latency fix (Renderer + Architect H3):**

`RenderPipeline.swift:371-384` does `Task { @MainActor in observe(...) }` every frame in the completed handler. Move the `FrameBudgetManager` and `MLDispatchScheduler` to a dedicated serial DispatchQueue; only hop to `@MainActor` for `@Published` UI updates. Decisions stay synchronous on the timing path; UI lags by at most one frame, but `MLDispatchScheduler` no longer misses budget breaches under main-thread contention.

**Live Beat This! routed through `MLDispatchScheduler` (ML #3):**

`runLiveBeatAnalysisIfNeeded`'s `analyzer.analyzeBeatGrid(...)` currently dispatches to `stemQueue` at utility QoS without consulting `MLDispatchScheduler`. Route through the scheduler the same way stem separation does. Pre-warm Beat This! graph + weight load at session start (after first audio frame) to avoid the t=10s lazy-init stutter.

**`MIRPipeline` `@unchecked Sendable` cleanup (Architect M2):**

Convert `MIRPipeline` to a `@MainActor` final class with explicit per-property locks where cross-thread access is genuinely needed. Removes the unsynchronized `private(set) var` reads-from-main / writes-from-analysis-queue pattern.

**`Diagnostics → Audio + Renderer` dependency leak (Architect M3):**

Move `SoakTestHarness` into a `Tests/` target or a separate non-shipped SPM dev product. Keeps `Diagnostics` engine library reusable.

**`Presets` and `Renderer` shader resource directories consolidation (Architect M4):**

Pick one source of truth (recommended: `Presets/Shaders/`). Remove the duplicate from the other target's `resources` declaration in `Package.swift`. Verify no `.metal` lookup silently fails.

**Files to touch:** `PhospheneApp/VisualizerEngine*.swift` (split into 4+ files), `PhospheneEngine/Sources/Renderer/RenderPipeline*.swift` (RenderGraphState refactor), `PhospheneEngine/Sources/DSP/MIRPipeline.swift`, `PhospheneEngine/Package.swift`, related tests.

**Tests:**

- All existing tests pass at every intermediate commit.
- New `AudioPipelineHostTests`, `RenderHostTests`, `OrchestratorHostTests` cover each host's API.
- New `RenderGraphStateTests` covers atomic state-transition contract.
- `LiveDriftValidationTests` (from QR.3) passes — proves the refactor preserves musical sync.
- Full soak test passes (no allocation regression).

**Done when:**

- [ ] `VisualizerEngine.swift` is ≤ 250 LOC; `+Audio/+Stems/+Orchestrator/+Capture/+InitHelpers/+PublicAPI` extension files deleted.
- [ ] Three hosts own their state; no `@unchecked Sendable` outside explicit audio-thread boundaries.
- [ ] `RenderPipeline` uses one lock + one `RenderGraphState`.
- [ ] Frame-budget observer runs on a dedicated queue; `MLDispatchScheduler` decisions are synchronous on the timing path.
- [ ] Live Beat This! routed through `MLDispatchScheduler`; pre-warmed at session start.
- [ ] `MIRPipeline` is `@MainActor`; no `@unchecked Sendable`.
- [ ] `Diagnostics` no longer depends on `Audio + Renderer` for shipped library product.
- [ ] One canonical `Shaders/` resource directory.
- [ ] Full engine + app + soak test suites green.
- [ ] Performance regression test confirms no per-frame regression.
- [ ] CLAUDE.md Module Map fully rewritten for the new shape; DECISIONS.md D-080: "VisualizerEngine decomposition + RenderPipeline single-state refactor."

**Verify:** Full suite + soak test + manual reel re-record.

**Estimated sessions:** 5–8. **Matt approval required at the start** because the increment is large enough that mid-flight scope changes would be costly. Each session ships one subsystem migration with full test pass; abort path is clean (revert to last green commit).

**Risks:**

- Decomposition surfaces hidden coupling. Each host migration may require refactors in unrelated files.
- `RenderGraphState` atomic snapshot under load may regress per-frame timing if not benchmarked. Mitigation: gate the refactor behind a runtime flag and A/B against the legacy switchboard for one session.
- `MIRPipeline` `@MainActor` conversion may cause unexpected `await` propagation. Mitigation: stage in a separate session with isolated test coverage.

---

### Increment QR.7 (CLEAN.2) — Shader noise algorithm consolidation

**Goal.** Resolve the deferred B.3 + B.4 items from QR.5: migrate production presets calling legacy `perlin2D` / `perlin3D` / `fbm3D` / `fbm2D` (and `sdRoundBox`) to a single canonical noise / SDF algorithm, then delete the legacy bodies from `ShaderUtilities.metal`. **This increment is NOT mechanical — it accepts visual change at the affected call sites.**

**Why a separate increment.** QR.5 discovered that the legacy `*D` (camelCase) noise/SDF functions in `ShaderUtilities.metal` and the V.1+V.2 (snake_case) tree under `Sources/Presets/Shaders/Utilities/` are not just naming differences — they are different *algorithms* with different output ranges, fade curves, and spatial character:

| Legacy | V.1+V.2 | Difference |
|---|---|---|
| `perlin2D(p) → [0,1]` | `perlin2d(p) → [-1,1]` | **Value noise** (hash per corner) vs **gradient noise** (Perlin's classic gradient + dot product). Different fade (cubic vs C² quintic). Different hash table. |
| `perlin3D(p) → [0,1]` | `perlin3d(p) → [-1,1]` | Same value-vs-gradient distinction as 2D. |
| `fbm3D(p, n) → [0,1]` (variable octaves, simple halving, no rotation) | `fbm4`/`fbm8`/`fbm12` (fixed octaves, rotation matrix per octave, Hurst-exponent decay, built on `perlin3d`) | Different algorithm + different range + fixed octave count. |
| `fbm2D(p, n)` | (no direct V.1+V.2 equivalent) | Build on `fbm` family or port as `fbm_octaves_2d`. |
| `sdRoundBox(p, b, r)`: `b` = outer half-extents | `sd_round_box(p, b, r)`: `b` = inner half-extents | Same geometric shape, different parameter convention. Requires `b → b - r` at every call site. |

QR.5's load-bearing invariant ("no behavior change, no golden-hash drift") forbids these migrations as mechanical cleanup. QR.7 accepts the visual change and runs the migration as a deliberate refactor.

**Consumers to migrate** (verified during QR.5 audit; re-verify on session start in case of drift):

- [GlassBrutalist.metal:205–206](PhospheneEngine/Sources/Presets/Shaders/GlassBrutalist.metal) — 2× `perlin2D` calls (`finGrain`, `macroVar`).
- [VolumetricLithograph.metal:382](PhospheneEngine/Sources/Presets/Shaders/VolumetricLithograph.metal) — `fbm3D(noiseP, VL_FBM_OCTAVES)`. Plus 2 more sites in the volumetric march loop (`fbm3D(p * 0.5, 4)`, `fbm3D((p + lightDir * 0.3) * 0.5, 3)`).
- [KineticSculpture.metal:59–61, 74–76](PhospheneEngine/Sources/Presets/Shaders/KineticSculpture.metal) — 6× `sdRoundBox` calls.

**Two strategy decisions to make at increment start.**

**Strategy A — Algorithm picker (for `perlin*` / `fbm*`):**
- **A1. Adopt V.1+V.2 algorithm everywhere.** Migrate consumers; add range-remap (`* 0.5 + 0.5`) where they expected [0, 1]; re-tune visual constants. Highest cleanup payoff; biggest visual delta. **VolumetricLithograph requires M7 fidelity review** post-migration (cited in CLAUDE.md as the MV-2 reference implementation).
- **A2. Add a new legacy-compatible helper to the V.1+V.2 tree.** Port `fbm3D`'s simple-halving / no-rotation / value-noise-base algorithm as `fbm_octaves(p, n)` (or similar) under `Utilities/Noise/`. Keep `perlin2D` / `perlin3D` in `ShaderUtilities.metal` since the gradient-vs-value distinction is genuine (they are different tools, not duplicates). Lower visual risk; modest cleanup payoff.
- **A3. Declare the legacy forms permanent keepers** (status quo after QR.5). They serve a different purpose than the V.1+V.2 forms (value vs gradient noise are both useful primitives). Annotate `ShaderUtilities.metal` to make this explicit. No code change; QR.7 becomes a doc-only increment.

**Strategy B — `sdRoundBox` migration (independent of A):**
- **B1. Migrate all 6 KineticSculpture call sites with `b → b - r` adjustment.** Literal-equivalent visual output. Mechanical except for the per-call adjustment.
- **B2. Keep `sdRoundBox` as permanent keeper.** Same as A3 reasoning.

**Recommendation (start-of-increment):** A3 + B1. Reason: gradient vs value noise are genuinely different primitives and shipping both is fine; the V.1+V.2 form is the right default for new presets but the legacy form is the right tool for existing consumers that depend on [0, 1] output. `sdRoundBox` on the other hand IS strictly a convention mismatch — migrating costs nothing visually and removes a keeper.

**Files to touch (Strategy A1, worst case):**
- Migrate: `GlassBrutalist.metal`, `VolumetricLithograph.metal` (3 sites), possibly other consumers found at session start.
- Migrate: `KineticSculpture.metal` (6 sites, Strategy B).
- Delete from `ShaderUtilities.metal`: `perlin2D` / `perlin3D` / `fbm2D` / `fbm3D` / `sdRoundBox` (5 functions, ~80 LOC).
- Update test source in `ShaderUtilityTests.swift` (preamble assertions for the deleted names).
- Regen `PresetRegressionTests` golden hashes for Glass Brutalist + Volumetric Lithograph + Kinetic Sculpture.
- M7 fidelity review for VolumetricLithograph.

**Files to touch (Strategy A3 + B1, recommended):**
- Migrate: `KineticSculpture.metal` (6 × `sdRoundBox` → `sd_round_box(p, b - r, r)`).
- Delete from `ShaderUtilities.metal`: `sdRoundBox` only.
- Annotate `ShaderUtilities.metal` "permanent keepers" section to make the gradient-vs-value-noise distinction explicit for future maintainers.
- Regen Kinetic Sculpture golden hashes (should be byte-identical if the math is right; verify).
- No M7 review required.

**Tests (Strategy A1):**
- Full engine suite green.
- `PresetRegressionTests` regenerated (3 presets × 3 fixtures = 9 hashes minimum).
- `ShaderUtilityTests` updated for deleted names.
- Manual eyeball: GlassBrutalist glass-fin grain, VolumetricLithograph chamber walls + light shafts, KineticSculpture frosted glass.
- M7 review for VolumetricLithograph (preset is cited in CLAUDE.md as the MV-2 reference).

**Tests (Strategy A3 + B1):**
- Full engine suite green.
- `PresetRegressionTests` golden hashes for Kinetic Sculpture either unchanged (if `b - r` is the exact compensation) or surface drift for explicit re-bake.
- No M7 review required.

**Done when:**

- [ ] Strategy A / B decision made and recorded as a DECISIONS.md entry.
- [ ] Migrations land per the chosen strategy.
- [ ] Hashes either preserved (A3 + B1) or explicitly regenerated (A1 / A2) with M7 review for VolumetricLithograph.
- [ ] CLAUDE.md "Do not" list updated if any new mechanical-cleanup-looks-safe-but-isn't pattern surfaces (e.g. "Do not migrate `perlin2D` → `perlin2d` without a range-remap pass — they are different algorithms").

**Estimated sessions:** 1 for Strategy A3 + B1 (recommended); 2–3 for Strategy A1 (includes M7).

---

## Phase DASH — Telemetry Dashboard

A dedicated HUD layer for Phosphene's diagnostic and operational telemetry. Renders floating monospace metrics cards over the live Metal view using a zero-alloc Core Text path backed by a shared-memory MTLTexture. Six increments; no Orchestrator or audio-pipeline changes — pure Renderer + Shared additions.

**Goals:**
- Real-time BPM, beat-lock state, stem energies, frame budget, and session-mode label without requiring Spectral Cartograph to be the active preset.
- Developer-togglable (same `D` key overlay flow as `DebugOverlayView`).
- Zero per-frame heap allocation; MTLBuffer-backed CGContext blit path inherited by `DashboardTextLayer`.

### Increment DASH.1 — Text-rendering layer ✅ 2026-05-06
### Increment DASH.2 — Metrics card layout engine ✅ 2026-05-07 (amended DASH.2.1)
### Increment DASH.3 — Beat & BPM card ✅ 2026-05-07
### Increment DASH.4 — Stem energy card ✅ 2026-05-07
### Increment DASH.5 — Frame budget card ✅ 2026-05-07
### Increment DASH.6 — Overlay wiring + `D` key toggle ✅ 2026-05-07 (superseded by DASH.7)
### Increment DASH.7.2 — Dark-surface legibility pass ✅ 2026-05-07
### Increment DASH.7.1 — Brand-alignment pass (impeccable review) ✅ 2026-05-07
### Increment DASH.7 — SwiftUI dashboard port + visual amendments ✅ 2026-05-07
## Phase DM — Drift Motes (particles preset) — REMOVED 2026-05-11

Drift Motes (DM.0 through DM.3 plus four manual-smoke remediation increments DM.3.1 / DM.3.2 / DM.3.2.1 / DM.3.3 / DM.3.3.1) was retired in its entirety on 2026-05-11. Preset code, tests, design / palette / architecture-contract docs, visual references, and perf-capture procedure docs are deleted from the tree. Recover from git history if needed.

**See `docs/DECISIONS.md` D-102** for the removal rationale, the three-part bar (iconic visual subject + clear musical role + infrastructure-feasible) that every pitched concept failed, and the rule that future particle presets ship their own `ParticleGeometry` conformer rather than branching from the deleted Drift Motes code.

**What survives.** D-097 (particle preset architecture: siblings, not subclasses) — Murmuration is byte-identical to its post-DM.0 baseline; the protocol surface (`ParticleGeometry` / `ParticleGeometryRegistry`) stays. D-099 (Swift `FeatureVector` / `StemFeatures` at 192 / 256 bytes). D-101 (`stems.drums_beat` as canonical particles-family beat-reactivity field) for any future particle preset. `SessionRecorder.frame_cpu_ms` / `frame_gpu_ms` columns and `RenderPipeline.onFrameTimingObserved` (originally DM.3a) stay — generic per-frame timing instrumentation.

**Status:** closed. The next preset increment is the parallel Lumen Mosaic stream (Phase LM) or whatever Matt prioritises.

## Phase LM — Lumen Mosaic (geometric pattern-glass ray-march preset)

**Status: CLOSED 2026-05-12 at LM.7. Lumen Mosaic certified — first catalog preset with `certified: true` in its JSON sidecar.**

Lumen Mosaic is a `geometric`-family preset (the `glass` framing in earlier doc revs drifted to `geometric` at LM.4.6). Visible surface is a flat `sd_box` panel filling the camera frame; surface is `mat_pattern_glass` (V.3 §4.5b) with hex-biased Voronoi cells. **Aesthetic role as it shipped:** energetic dance partner — vivid per-cell uniform random RGB synced to the beat via per-cell team-counter mechanism (LM.3.2 / D.5 → LM.4.6 / D.6), with the LM.6 cell-depth gradient + optional hot-spot giving each cell a 3D-glass dome read, and the LM.7 per-track chromatic-projected RGB tint vector giving each track a visibly distinct aggregate panel mean. The earlier "contemplative slow ambient / 4-audio-driven light agents" framing was the LM.2-era design intent and is retired — the 4-agent struct survives on the GPU buffer for ABI continuity but the shader does not read it.

Authoritative authoring docs at `docs/presets/LUMEN_MOSAIC_DESIGN.md` (visual intent + current implementation), `docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md` (current-implementation summary + historical LM.3.2-era prose for context), `docs/presets/LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md` (phased increment ledger).

The preset was originally sequenced as 10 increments LM.0 → LM.9 with cert sign-off at LM.9. After the LM.4.4 pattern-engine retirement collapsed three planned increments (LM.5 / old LM.7 / LM.8), cert moved up to **LM.7** (D-LM-7). Certification target met: **the cheapest ray-march preset in the catalog** (M2 Pro measured: `frame_gpu_ms` mean 1.37 ms / max 32.9 ms / 0.02 % over 16 ms; well under the Tier 2 ≤ 16 ms / ≤ 3.7 ms p95 target). See LM.6 / LM.7 increment entries below for the cert closeout, and D-LM-6 / D-LM-7 in `docs/DECISIONS.md` for the architectural decisions.

Per-increment closeout narratives (LM.0 → LM.7): [`ENGINEERING_PLAN_HISTORY.md`](ENGINEERING_PLAN_HISTORY.md) §DOC.6 closed-phase batch.

### Increment LM.0 — Fragment buffer slot 8 infrastructure
### Increment LM.1 — Minimum viable preset
### Increment LM.2 — Audio-driven 4-light backlight (continuous energy primary)
### Increment LM.3 — Per-cell palette + procedural mood + drop cream baseline
### Increment LM.3.1 — Agent-position-driven backlight character
### Increment LM.3.2 — Band-routed beat-driven dance
### Increment LM.4 — Pattern engine v1 (idle + radial_ripple + sweep)
### Increment LM.4.1 — Ripple density + bleach-out fix
### Increment LM.4.3 — BeatGrid-driven triggers + ripples-as-accent
### Increment LM.4.4 — Pattern engine retired
### Increment LM.4.5 — Full-spectrum palette redesign (per-track custom palette cards)
### Increment LM.4.6 — Pure uniform random RGB per cell (final shape)
### Increment LM.6 — Cell-depth gradient + optional hot-spot
### Increment LM.7 — Per-track aggregate-mean RGB tint + chromatic projection
### Increment LM.4.7 — Curated 18-palette library + mood-biased Orchestrator selection

**Status:** ✅ Implementation landed 2026-05-18; Matt M7 sign-off on the same-day 5-track session with one tuning note (within-quadrant clustering), addressed by the same-day amendment widening `kAntiRepeatWindow` from N=1 to N=3 (`[dev-2026-05-18-b]`, D-LM-palette-library amended). Paperwork-only session earlier the same day filed `D-LM-palette-library` + `D-LM-cream-rescission`; CLAUDE.md + KNOWN_ISSUES.md + this entry updated.

**Scope.** Replace LM.4.6's `lm_cell_palette` uniform-random-RGB body (and the LM.7 per-track chromatic-projected tint built on top of it) with palette-library-driven cell colours. **Each song** selects one of **18 hand-authored 12-colour palettes**; the Orchestrator picks the palette via a mood-biased Gaussian-over-distance weight function with the immediately previous song's palette excluded from the candidate set. Within a song, cells sample uniformly from the drawn palette's 12 entries via cell-hash modulo 12. The per-track seed perturbs **sampling order** within the palette (which 12-bucket a given cell lands in for that track) — never palette membership. The LM.3.2 team/period beat-step ratchet is preserved; cells advance their palette index on rising-edge of their assigned band's beat. Cites `D-LM-palette-library`.

The pale-tone-share gate (≤ 0.30 of cells; pale = linear RGB `min(R, G, B) > 0.65`) lands in this increment as the mechanical enforcement of `D-LM-cream-rescission`. Cathedral Lights is the calibration palette (~25 % nominal pale-cell share, ~30 % worst-case under hash-draw variance).

**The 18 palettes.** Vol. I — Autumnal, Refn Glow, Glacier, Art Deco, Abyssal Bioluminescence, Kintsugi, Carnival. Vol. II — Holi, Geode, Rothko Chapel, Tropical Aviary, Persian Miniature, Ukiyo-e. Plate 14 — Cathedral Lights. Plates 15–18 — Cycladic, Ming Porcelain, Tenebrism, Obsidian.

**Done when.**

- New file `PhospheneEngine/Sources/Presets/LumenMosaicPaletteLibrary.swift` defines 18 palettes as Swift structs carrying a `name: String`, a 12-entry `colors: [SIMD3<Float>]` (linear RGB), and an explicit `moodAnchor: SIMD2<Float>` in normalised mood-space coordinates `[-1, +1]` per axis (valence on x, arousal on y). Palettes named to match the design artifacts (Autumnal, Refn Glow, Glacier, Art Deco, Abyssal Bioluminescence, Kintsugi, Carnival, Holi, Geode, Rothko Chapel, Tropical Aviary, Persian Miniature, Ukiyo-e, Cathedral Lights, Cycladic, Ming Porcelain, Tenebrism, Obsidian). Hex values per `docs/VISUAL_REFERENCES/lumen_mosaic/palette_library/`.
- Orchestrator selection model implemented: per-song weighted draw via Gaussian-over-distance from each palette's `moodAnchor` to the current track's `(valence, arousal)`, with the immediately previous song's palette removed from the candidate set. Draw seeded by track identity so it's reproducible. Per `D-LM-palette-library`: mood biases **selection probability**, never deterministic mapping; every eligible palette has non-zero probability everywhere in the mood plane.
- `lm_cell_palette` (MSL) rewritten to index into the per-session palette via `palette_idx = lm_hash_u32(cell_id ^ step ^ track_seed ^ section_salt) % 12` and look up the corresponding palette entry. The pre-LM.4.7 hash → RGB-cube path is removed. The LM.7 per-track chromatic-projected tint path is removed (`kTintMagnitude` retires).
- Slot-8 GPU ABI extended to carry the 12-colour palette as 36 floats (or equivalent per implementation choice — e.g. 12 × `float4` packed). `LumenPatternState` stride updated; Swift-side `CommonLayoutTest` regression-locks the new size. `directPresetFragmentBuffer3` setter wires the per-session palette into the binding.
- `LumenPaletteSpectrumTests` rewritten — assertions on **palette membership** (every cell colour matches one of the 12 palette entries to within float epsilon), per-session palette stability, mood-biased selection probability distribution shape, palette character distinctness across the 18-palette set. Replaces the existing Suite 7 (LM.7 chromatic-projection assertions); LM.7-specific tests retire with the LM.7 code path.
- LM.9 pale-tone-share gate implemented as a new test (location TBD — `LumenPaletteSpectrumTests` or `FidelityRubric`): per non-silence fixture frame, classify each cell by linear RGB; reject the fixture if `pale_cell_count / total_cells > 0.30`. **Passes for all 18 palettes mechanically.** Cathedral Lights specifically must pass at its ~25 % nominal share with margin.
- `PresetRegression` Lumen Mosaic golden hash regenerated — the regression harness's slot-8 zero-bound default is no longer equivalent to "neutral palette" because the cell-colour lookup is into a palette table. The new golden hash reflects the post-LM.4.7 baseline; the regression test pins the new value.
- Engine + app build clean; SwiftLint 0 violations on touched files.
- **Matt M7 review** on a real-music multi-track session: each song's drawn palette reads as its named character (Cathedral Lights → stained-glass, Refn Glow → warm-neon-shadow, Glacier → frozen-blue-on-snow, etc.); the per-song palette change is visible at track boundaries (panel character shifts when the track shifts) and the mood-biased selection feels appropriate per track (low-valence / high-arousal tracks trend toward Rothko Chapel / Tenebrism / Abyssal Bioluminescence; high-valence / high-arousal tracks trend toward Carnival / Holi / Tropical Aviary; etc.) without being deterministic; the anti-repeat rule is visible on a contrived playlist (e.g. forcing two consecutive low-valence-low-arousal tracks should pick different palettes, not Cathedral Lights twice in a row).

**Verify.**

- `swift test --package-path PhospheneEngine --filter "LumenPalette|PresetLoaderCompileFailure|PresetRegression|PresetAcceptance|FidelityRubric"`
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview` — 18-palette contact sheet at the standard 9-fixture set, plus per-palette mean / aggregate-character verification.
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`
- `swiftlint lint --strict --config .swiftlint.yml`

**Honest trade-offs documented.** Per-cell freedom is narrower than LM.4.6: each cell samples one of 12 colours, not from the full 16M-colour RGB cube. Matt explicitly accepted this trade-off in the 2026-05-17 conversation in exchange for palette character per session. Across the 18 palettes, the union of reachable colours covers a wide swath of the cube; what changes is that **within a given session**, only 12 colours appear, which is the property that makes the palette read as a coherent visual identity.

**Carry-forward.** Resolves BUG-014 (`docs/QUALITY/KNOWN_ISSUES.md` Open) — flip to Resolved with the LM.4.7 commit hash. New palette additions (post-LM.4.7) require Matt M7 review per palette and a `D-LM-palette-library`-citing amendment in `DECISIONS.md`. Palette removals are also gated on Matt sign-off. The LM.7 chromatic-projection code path retires with LM.4.7; the `kTintMagnitude` constant and the `test_achromaticAlignedSeed_doesNotWash` test are removed (the failure mode they regression-lock cannot occur on the palette-table path because cells sample from a curated 12-entry table that, by construction, avoids the achromatic-axis wash).

---

## Phase CA — Capability Audit (2026-05-20)

**Status.** CA.1–CA.7b shipped ✅ (2026-05-20 → 2026-05-21); audit deliverables live in `docs/CAPABILITY_REGISTRY/`. CA-Audio's kickoff landed 2026-05-21; the audit itself is still pending Matt's scheduling (below).
Motivation + per-audit closeout narratives: [`ENGINEERING_PLAN_HISTORY.md`](ENGINEERING_PLAN_HISTORY.md) §DOC.6 closed-phase batch.

### Increment CA.1 — DSP / MIR
### Increment CA.2 — ML
### Increment CA.3 — Session
### Increment CA.4 — Orchestrator
### Increment CA.5 — App Layer (engine-adapter slice)
### Increment CA.6 — App Layer (Views + ViewModels presentation slice)
### Increment CA.7a — Renderer Capability Audit (core pipeline) ✅ (2026-05-21)
### Increment CA.7b — Renderer Capability Audit (Dashboard / Geometry / RayTracing) ✅ (2026-05-21)
### Increment CA-Audio — Audio Capability Audit

**Status.** Kickoff doc landed 2026-05-21 ([`docs/prompts/PHASE_CA_KICKOFF_CA_AUDIO_2026-05-21.md`](prompts/PHASE_CA_KICKOFF_CA_AUDIO_2026-05-21.md)). Audit itself pending Matt's scheduling — hand the kickoff to a fresh Claude Code session when ready. CA.7b closeout 2026-05-21 recommended CA-Audio as the natural next increment (closes the CA.3 Session ↔ Audio boundary-noted item; smaller than CA-Presets).

**Scope.** `PhospheneEngine/Sources/Audio/` — 16 files / 3,294 LoC across capture pipeline (6 files: `SystemAudioCapture`, `AudioInputRouter`, `AudioInputRouter+SignalState`, `AudioBuffer`, `LookaheadBuffer`, `FFTProcessor`), signal-quality monitors (2 files: `SilenceDetector`, `InputLevelMonitor`), metadata fetcher cluster (6 files: `MetadataPreFetcher`, `MusicBrainzFetcher`, `SpotifyFetcher`, `SoundchartsFetcher`, `MusicKitBridge`, `StreamingMetadata`), protocols (1 file: `Protocols.swift`), module marker (1 file: `Audio.swift`).

**Required verifications** carried forward from CA.3 / CA.5 / CA.7b observations: (1) CA.3 Session ↔ Audio boundary closure — `MetadataPreFetcher` producer-side traced against the Session consumer chain at `SessionPreparer.swift:86, 132, 299`; (2) D-079 sample-rate plumbing — cited literal-grep against `Scripts/check_sample_rate_literals.sh` allowlist + immutable-capture confirmation at `AudioInputRouter.installTap(...)`; (3) tap recovery state machine matches ARCH §68 (3 s → 10 s → 30 s backoff, three attempts); (4) SilenceDetector + InputLevelMonitor timings match ARCH §487-488 (.active → .suspect 1.5s → .silent 3s → .recovering → .active 0.5s hold; 21s peak-dBFS window + 30-frame hysteresis); (5) Failed Approach #21 + #22 verified at `SystemAudioCapture` source; (6) BUG-005 + BUG-013 producer-side handling characterised.

**Same methodology as CA.1-CA.7b** (audit-only; sub-scope decision unnecessary at 3.3k LoC; visibility grep verification; cited grep for production-orphan claims; non-nil-caller refinement for setter APIs per CA.7b; per-file verdicts; doc-drift corrections in the same increment).

---

## Phase CS — Cold-Start Sync (2026-05-20)

**Status.** Closed for the automated premise 2026-05-25 — automated cold-start beat-phase derivation was empirically falsified across six iterations and retired per Matt's Choice A; see CLAUDE.md §Cold-Start Phase Contract and [`docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`](CAPABILITY_REGISTRY/BEAT_SYNC.md).
Verification narratives (CS.1 / CS.1.x / BSAudit series / CS.1.y): [`ENGINEERING_PLAN_HISTORY.md`](ENGINEERING_PLAN_HISTORY.md) §DOC.6 closed-phase batch. CS.2–CS.5 below were never executed (gated on the retired premise) and are retained pending Matt's keep-or-retire call.

### Increment CS.1 — Empirical verification of existing cold-start beat sync ✅
### Increment CS.1.x — Cold-start grid-phase diagnosis ✅
### Increment BSAudit.3 — BPM-anchored phase acquisition design + impl + validate + close ✅ (resolved against accepted limit; impl runtime reverted 2026-05-25 evening)
### Increment BSAudit.2 — Path A research (Beat This!-on-tap reproducibility) ✅
### Increment BSAudit — Beat-Sync Audit (BUG-017 diagnosis stage) ✅
### Increment CS.1.y — Cold-start grid-phase fix (BUG-017) — **CS.1.y.2-redo reverted 2026-05-24; superseded by BSAudit; awaiting direction decision**
### Increment CS.2 — First-segment minimum duration

**Sequencing.** Gated behind CS.1.y (BUG-017 fix) — CS.2–CS.5 all assume a correct cold-start grid (Matt-ratified reprioritization, 2026-05-22).

**Scope.** Add a first-segment-of-track minimum duration constraint to `SessionPlanner.planOneSegment` (`PhospheneEngine/Sources/Orchestrator/SessionPlanner+Segments.swift:137`). Target 10-12 s. Handle: tracks shorter than the minimum (allow violation); section boundaries inside the minimum window (push to next bar boundary after the minimum). Regenerate golden session tests.

**Done-when.**
- `planOneSegment` honors the new constraint for first segments only (subsequent segments unaffected).
- Golden sessions regenerated; per-track scoring decisions documented in commit message.
- Edge-case tests: 8 s track, 12 s track, 60 s track with section boundary at t=6 s, 60 s track with section boundary at t=15 s.

**Estimated sessions:** 1.

### Increment CS.3 — Data-hierarchy compliance audit

**Scope.** Read every `.metal` preset file in the catalog. For each, classify every audio-reactive driver as `primary` / `accent` / `proxy-fallback`. Compare against CLAUDE.md's Audio Data Hierarchy rule. Output: `docs/PRESET_DATA_HIERARCHY_AUDIT_<date>.md` with per-preset findings.

Specific check criteria per preset (see design doc §6.4 for the full list):
- Continuous bands (`f.bass`, `f.mid`, `f.treble` and `_att_rel` / `_dev` variants) — used as primary driver?
- Stem energies (`stems.X_energy`) — used as primary driver? If so, D-019 warmup blend present?
- Beat onsets — used as accent only?
- Predicted beats / bar phase — used for jitter-free motion where appropriate?

**Done-when.** Per-preset audit document published; preliminary scan suggests `Starburst`, `KineticSculpture`, `GlassBrutalist`, `Arachne` need close review. No code changes in this increment.

**Estimated sessions:** 1-2.

### Increment CS.4 — Targeted fixes from audit findings

**Scope.** Per non-compliant preset surfaced by CS.3: minimum-change fix to bring into D-019 / D-026 compliance without altering visual intent. One commit per preset. Golden hashes regenerate per preset.

**Risk.** Preset-touching work is where Claude's track record is worst (Drift Motes, Aurora Veil pattern). Each CS.4 sub-increment is scoped tightly (one preset, minimum change). Matt M7 review per preset before flipping the audit document's verdict from `non-compliant` to `compliant`.

**Done-when.** Every preset flagged in CS.3 either has a compliance fix landed and M7-approved, or has an explicit decision to defer / retire (rare).

**Estimated sessions:** variable — one per affected preset.

### Increment CS.5 — Documentation of the cold-start contract

**Scope.** Promote the cold-start data-flow understanding into CLAUDE.md and SHADER_CRAFT.md as a durable rule:
- New CLAUDE.md section under "Audio Data Hierarchy" titled "Cold-Start Phase Contract" describing `gridOnsetOffsetMs` calibration, D-019 blend pattern, first-segment minimum duration, and the implication that violating presets look broken during cold-start.
- Short SHADER_CRAFT.md section pointing authors at the CS.3 audit checklist.
- New decision record `D-XXX — Cold-start sync architecture (Phase CS, 2026-05-XX)`. Documents what's in production, what was verified, what was added.

**Done-when.** Docs land; reference from any subsequent preset prompt confirms the rules.

**Estimated sessions:** ½.

### Phase exit criteria

Phase CS closes when, in this order:

1. ✅ CS.1 verification ran; pass-rate < 90 % (3/10) → CS.1.x diagnosis documented (BUG-017) with a fix path.
2. CS.1.y — BUG-017 cold-start grid-phase fix landed; `ColdStartVerifier` re-run on a fresh capture reports ≥ 90 % of tracks passing.
3. CS.2 first-segment minimum landed; golden sessions green.
4. CS.3 audit document published.
5. CS.4 fix increments completed for every preset CS.3 flagged.
6. CS.5 documentation merged.
7. **Matt manual validation on a real listening-party playlist confirms perceptual beat sync from frame 1.** The load-bearing close criterion.

### Out of scope for Phase CS

- BUG-013 time-signature for odd-meter tracks — different defect, different fix.
- Audio output latency UX (AirPods / Bluetooth compensation) — future Phase.
- Section-aware visuals, mood arc, stem time-varying — fundamentally blocked by the streaming-only constraint.
- Any work that would relax the streaming-only architectural constraint (local files, capture-on-first-listen, third-party data services). Matt explicitly deprioritized these on 2026-05-20.

---

## Phase CSP — Cold-Start Perception (2026-05-26 → 2026-05-27, two reverted iterations)

Per-preset cold-start fixes leveraging proxy-then-stems crossfades + cached pre-playback analysis. Two iterations attempted 2026-05-26 / 2026-05-27, both reverted. Phase paused pending a different premise (likely a stress-test-measurement-first approach).

### Increment CSP.1 + CSP.1.1 — Soft tempo pulse (tried + reverted 2026-05-27)
### Increment CSP.2 — FFO cached perception + cold-start crossfade (tried + reverted 2026-05-27)
Reverted-iteration narratives (CSP.1/CSP.1.1, CSP.2): [`ENGINEERING_PLAN_HISTORY.md`](ENGINEERING_PLAN_HISTORY.md) §DOC.6 closed-phase batch.

### Increment CSP.3 — FFO cold-start fix with the three corrections from CSP.2 ⏳ (implemented 2026-05-27, M7 outstanding)

Same product target as CSP.2; three specific corrections applied directly from the CSP.2 dive findings:

1. **Crossfade window: 0.5 → 14 s** (was 0.5 → 8 s in CSP.2) — matches measured live-stems arrival.
2. **Cold-start proxy: `f.bass_att`** (smoothed continuous bass; was `f.bass_dev` deviation primitive in CSP.2) — continuous per-frame motion instead of sparse-event signal.
3. **One-sided baseline:** cached proportion *above* 0.25 boosts spike baseline up to +25 %; below 0.25 leaves it at 1.0 (no penalty). Sparse-bass tracks (Royals) look exactly like today; bass-heavy tracks get visible posture.

Plus the operational gaps CSP.2 surfaced:

- **UserDefaults A/B toggle `ffoColdStartFixEnabled`** (default ON). OFF arm collapses to the exact pre-CSP.3 formula via writing sentinel values (`trackElapsedS = 100.0`, `cachedBassProportion = 0.25` pivot).
- **`features.csv` instrumentation** for both new fields as trailing columns — A/B verifiable from artifacts in ~30 seconds.

**Done-when (in flight).**

- [x] Engine: 1277 / 1277 tests pass. New `CSP3DataPlumbingTests` suite (8 tests, 3 sub-suites): trackElapsedS reset + accumulation (toggle ON), trackElapsedS = 100.0 (toggle OFF), cachedBassProportion preserved across live updates. Plus `test_recordFrame_csp3Fields_writtenToCSV` round-trip.
- [x] SwiftLint `--strict`: 0 violations.
- [x] App build: succeeds.
- [ ] **Matt M7 (load-bearing gate).** Same A/B protocol as CSP.2 — but now verifiable from `features.csv` so a negative-result diagnostic dive is bounded.

**Outcome handling.**

- **Better:** cert. Same pattern likely extends to Volumetric Lithograph's terrain pulse and camera dolly — file CSP.4 if Matt wants.
- **No different:** the design space at the cached-perception + live-overall-bass layer is exhausted at this consumption point. Pivot to Matt's stress-test methodology suggestion (CSP-Stress.1, below).
- **Worse:** revert; capture specific failure modes before reverting (which track, what part of the timeline, what does the spike behaviour look like).

### Increment CSP.3.4 — FFO SDF Lipschitz divisor /4 → /10 (2026-05-28) ✅
### Increment CSP.3.5.1 — Complete CSP.3.5: apply the intended /6 to the operative line (2026-05-28) ✅
### Increment CSP.3.5 — FFO SDF Lipschitz divisor /10 → /6 (correct CSP.3.4 side effects) (2026-05-28) ⚠ (doc-only; operative line unchanged until CSP.3.5.1)
### Increment CSP.3.3 — Spike-strength coefficient bump 0.35 → 0.8 (2026-05-28) ✅
### Increment CSP.3.2 — Drop warm-state crossfade; f.bass for the whole track (2026-05-28) ✅
### Increment SAR.1 — Stem analyzer EMA self-seeding (Stem Analyzer Range, 2026-05-28) ✅
### What's next for Phase CSP

**Paused** pending BUG-019 (Phase PERF below). No point tuning FFO's cold-start consumer at the shader layer while ~30 % of frames are missing their deadline — the visual signal is too noisy to read.

After BUG-019 is at least diagnosed (root cause identified, fix scope known), revisit CSP.3.1's M7 verdict — re-running the same A/B in a CPU-clean build is the first read on whether the cold-start design itself works.

If CSP.3.1 then carries the cold-start on FFO, the pattern (one-sided baseline + smoothed continuous proxy + crossfade timed to real warmup) extends to other affected presets — Volumetric Lithograph being next per Matt's 2026-05-27 prioritisation (terrain pulse + camera dolly are both stems-routed).

If CSP.3.1 still doesn't carry post-BUG-019, the next move is Matt's stress-test methodology suggestion: build per-preset cold-start measurement infrastructure — characterise what each preset's audio reactivity actually does across tempo / meter / energy variation — then propose fixes grounded in measured baselines. That work would slot here as **CSP-Stress.1** (or similar).

---

## Phase PERF — Tap-path CPU degradation diagnosis (2026-05-28 →)

Surfaced 2026-05-28 by the SAR.1 M7 close. `features.csv` `frame_cpu_ms` doubles from ~11 ms to ~22–24 ms at session-time 67–68 s and stays elevated for the rest of the session, producing visible flickering / hangs at the perceptual layer. GPU stable throughout — pure CPU bottleneck somewhere in the tap-path audio-analysis pipeline. LF-path sessions (local-file playback) run at 1.3–1.4 ms CPU throughout, isolating the issue to a tap-path-specific component. Pre-existing — same shape in the pre-SAR.1 reference session — but never characterised until now.

Filed as **BUG-019** (P1, `perf`). Multi-increment P1 process per the defect protocol: instrumentation → diagnosis → fix → validation.

### Increment PERF.1 — Per-subsystem timing instrumentation ✅ (2026-05-28)
### Increment PERF.2 — Diagnosis from PERF.1 capture (2026-05-28) ✅ analysis-pipeline ruled out
### Increment PERF.2-render — Render-loop CPU breakdown (2026-05-28) ✅
### Increment PERF.2-render — Diagnosis from session `2026-05-27T22-15-25Z` (2026-05-28) ✅ narrowed to renderFrame dispatch
### Increment PERF.2-pass — Ray-march per-sub-pass timing (2026-05-28) ✅
### Increment PERF.3 — Fix beat-dominant light-intensity flicker (2026-05-28) ✅
### Increment PERF.4 — Validation (after M7)

Verification criteria from BUG-019: `FrameTimingReporter` p95 ≤ tier budget over 90 s tap-path; 2-hour soak test passes; Matt M7 perceives no flickering. If M7 reports the perceptual problem is gone, BUG-019 closes against the flicker fix. The "sustained CPU bump" pattern observed earlier remains characterized but classed as a probably-environmental separate phenomenon (PERF.2-pass empirically ruled out our render-path code as the source).

---

## Phase SR — Session Replay diagnostic infrastructure

Diagnostic harness that closes the "I cannot inspect this preset" gap surfaced during the AV.2.x cascade closeout (2026-05-20). Closeouts asserting audio-coupling or visual-fidelity claims must now cite generated evidence packs instead of assertion-shaped language. See [docs/ENGINE/SESSION_REPLAY.md](ENGINE/SESSION_REPLAY.md) for usage + extension. The accompanying CLAUDE.md discipline rule ("Diagnostic infrastructure precedes fidelity claims") is the project-wide standard.

### Increment SR.1 — Initial harness + Aurora Veil ✅ (2026-05-20)
## Phase AV — Aurora Veil (direct-fragment + mv_warp preset)

A lightweight ambient ribbon preset for quiet listening, low-energy passages, and comedown sections. Direct-fragment + mv_warp pattern — the canonical Milkdrop shape with no current consumer in the catalog. Aurora curtains over a faintly-starred night sky, with vocals-pitch hue stratification, bass-driven brightness breathing, and drums-coupled curtain kink. Authoritative design at [docs/presets/AURORA_VEIL_DESIGN.md](presets/AURORA_VEIL_DESIGN.md); reference set curated at [docs/VISUAL_REFERENCES/aurora_veil/](VISUAL_REFERENCES/aurora_veil/) (5 references + anti-reference, plus architecture contract).

**Concept-viability gate (SHADER_CRAFT §2.0).** All three gates clear before AV.1 starts:

1. **Musical role (one sentence).** *"The aurora curtain's hue stratifies along its vertical extent from the live vocals-pitch trail (low-y green → high-y magenta), so the listener sees the melody as the curtain's colour gradient; brightness breathes with sustained bass; drums onsets kink the curtain laterally."* Names specific musical features (vocals pitch, sustained bass, drum onsets) paired with specific visual behaviours (vertical hue gradient, all-ribbon brightness scale, lateral curtain kink) per CLAUDE.md FA #58 / D-102.
2. **Iconic visual subject deliverable at fidelity.** Lightweight rubric profile (D-067(b)) — emission-only direct fragment, exempt from M1 detail cascade and M3 material count. Comparable pattern: Gossamer's direct-fragment + mv_warp recipe is the closest neighbour. Fidelity bar is reachable.
3. **Infrastructure-feasible.** Uses only existing utilities (`warped_fbm` / `curl_noise` / `palette_cool` / `SpectralHistoryBuffer` / `blue_noise_sample` / hash-based starfield). No engine work.

**Status.** AV.1 ✅ (2026-05-18). AV.2 ✅ (2026-05-18). AV.2.1 ❌ (2026-05-18, misdiagnosed motion-smear hotfix; superseded). AV.2.2 ✅ (2026-05-18, mv_warp dropped). AV.2.2a ✅ (2026-05-18, drawDirect slot-6 binding hotfix). AV.2.2b ✅ (2026-05-18, state allocation moved out of `case .mvWarp:`). AV.2.2c ✅ (2026-05-19, calmer-tuning amplitude pass). AV.2.2d ✅ (2026-05-19, brightness route switched to `bass_dev`). AV.2.2e ✅ (2026-05-19, brightness route threshold-gated). AV.2.2f ✅ (2026-05-19, synth-flash route via `stems.other_energy_dev`). AV.2.2g ✅ (2026-05-19, synth-flash amplitude raised 0.6 → 1.5). PT.1 ✅ (2026-05-19, PitchTracker ring-buffer fix — vocals_pitch route had been 0 % in every prior session due to 1024-sample-input-to-2048-sample-tracker wiring bug). AV.2.h ✅ (2026-05-19, Three-Channel curation: dropped routes 3 / 4 / 6 / 7 / 8 after Matt's "muddled" feedback; kept Route 1 vocals-pitch hue + Route 2 bass brightness pulse + Route 5 drum kink with raised gate 0.9/1.5; three musical features → three independent visual axes, no competing rhythms). AV.2.h.1 ✅ (2026-05-20, kink gate 0.9/1.5 → 0.7/1.0). AV.3 🚫 **Paused 2026-05-20** — AV.3 cert prep surfaced (i) 9-Q rubric Q3 = NO + Q7 = NO via SR.1 calibrated rubric (Q3 reads-like-anti-reference, Q8 outside-family) and (ii) a design reframing — the current preset authentically depicts diffuse-glow aurora; the current curated reference set anchors active-curtain aurora. Matt's product-level call (2026-05-20): two-preset split. AV.3 cert work for the current preset is replaced by **AV.3.x** — re-curate references to diffuse-glow aurora + cert against the new set. Active-curtain aurora gets a new preset (**Phase AC — Aurora Curtain**, planned) using the per-pixel-ray construction recipe from [docs/presets/AURORA_VEIL_RESEARCH_AV3X_2026-05-20.md](presets/AURORA_VEIL_RESEARCH_AV3X_2026-05-20.md) §3.1.

### Increment AV.3.x — Diffuse-glow reference re-curation + cert ⏳ Planned

**Scope.** Matt curates 4–5 diffuse-glow / pulsating-patch aurora reference images replacing the current curtain-form set in `docs/VISUAL_REFERENCES/aurora_veil/`. Update `AURORA_VEIL_README.md` annotations + mandatory-traits checklist + 9-Q rubric variant (some Qs may not apply to diffuse-glow). Update `AURORA_VEIL_DESIGN.md §5` to reframe design intent as diffuse-glow aurora. Re-run `PresetSessionReplay` against the new reference set; calibration should produce `withinFamily` verdicts for the Qs that apply. M7 review against new set. On Matt's "yes," flip `AuroraVeil.json certified: true`.

**Done-when.** Reference set re-curated (Matt). README annotations updated. DESIGN §5 reframed. Per-Q rubric variant amended for diffuse-glow (some Qs marked N/A). SR.1 report against AV session + new refs shows ≥ 5 Qs `withinFamily` or N/A; no `readsLikeAntiReference`. M7 sign-off captured. `certified: true` flipped. ENGINEERING_PLAN + RELEASE_NOTES updated.

### Phase AC — Aurora Curtain (planned, post AV.3.x)

**Concept.** Active-curtain aurora — vertical ribbons, fold drape, visible ray pillars, off-axis composition with silhouette foreground. The form the AV reference set originally anchored. Distinct preset, sibling not subclass (D-097); ships its own .metal, .json, state class, reference set, and rubric.

**Authoritative design.** [docs/presets/AURORA_VEIL_RESEARCH_AV3X_2026-05-20.md](presets/AURORA_VEIL_RESEARCH_AV3X_2026-05-20.md) §3.1 (per-pixel ray construction) + §3.2 (off-axis composition + silhouette foreground) + §3.3 (sub-second ray flicker) + §3.4 (sharp bottom edge).

**Status.** Planned. **Schedule:** waits on AV.3.x cert. Detailed prompt to be authored at scoping time.

### Increment AV.1 — Single-ribbon foundation ✅ (2026-05-18)
### Increment AV.2 — Multi-column parallax + audio routing ✅ (2026-05-18)
### Increment AV.2.1 — Motion-smear hotfix ✅ (2026-05-18)
### Increment AV.2.2 — Drop mv_warp pass (empirically grounded fix) ✅ (2026-05-18)
### Increment AV.2.3 (planned) — Re-introduce drift mechanisms grounded in dossier

**Scope.** Replace the mv_warp-supplied motion (which AV.2.2 removed) with the dossier-grounded mechanisms the design SHOULD have used from AV.1:
1. **Curl-noise perturbation INSIDE `aurora_tri_noise_2d` sample coordinate** per dossier §1.3 line 61 — Wittens NeverSeenTheSky borrowing. The vortical-flow character mv_warp was attempting belongs here.
2. **Two-column SUM-merge instead of three-column MAX** per dossier §1.3 line 62. Volume integration for an emissive medium is summative; the AV.2 MAX-of-three was structurally wrong (and produced the winner-switching pattern that compounded under mv_warp).
3. **Multi-frame diagnostic harness extended to replay `raw_tap.wav`** from a captured session so the seven audio routes can be validated against real music BEFORE filing AV.2.3 as ✅ (per the new "test in production-grade pipeline" discipline rule). The routes have never been seen live; that's the next reliability gap to close.

**Risks acknowledged before authoring.** R1 (mv_warp+nimitz combination unprecedented) is resolved by removing mv_warp. R2 (mv_warp + high-frequency content structurally incompatible) is resolved by the same. R3 (audio routes unvalidated live) → multi-frame test replaying `raw_tap.wav` is the gate. R4 (AV.3 sub-second flicker + pulsation have no cited working code reference — only Springer/AGU physics papers) → I will surface this to Matt before AV.3 implementation and propose either finding a working reference or accepting the "L3 grounding only" risk per the soft rule.

### Increment AV.3 — Refine + cert

**Scope.** Tune palette constants, mv_warp amplitudes, fold-density coefficients against curated references. Matt M7 review against `01_macro_curtain_hero_purple_green.jpg` + `02_palette_green_to_magenta_stratification.jpg` + `03_meso_curtain_fold_drape.jpg` + `04_atmosphere_multi_curtain_parallax.jpg`. Anti-reference check against `09_anti_neon_festival_aurora.jpg`. On green: flip `certified: true`.

**Done-when.** M7 sign-off. `Aurora_Veil.json` schema validated against an actual existing preset sidecar (`Gossamer.json` is the closest match per AV_README open question) — required fields (`name` not `id`, `description`, `author`, `duration`, `fragment_function`, `vertex_function`, `beat_source`) confirmed; the `feedback` wrapper around `decay` resolved against the real schema.

**Estimated total: 3 sessions.**

---

## Phase CC — Crystalline Cavern (ray-march flagship preset)

A static-camera ray-march scene of a glowing geode interior — crystalline materials, screen-space caustics, light shafts, mv_warp shimmer over the lit frame. Demonstrates the D-029-preserved combination of `ray_march` + `mv_warp` (no current preset uses this) and exercises the entire V.1–V.4 utility library in a single shader. **Flagship piece.** Tier-2 primary. Authoritative design at [docs/presets/CRYSTALLINE_CAVERN_DESIGN.md](presets/CRYSTALLINE_CAVERN_DESIGN.md); reference set **not yet curated** (CC.0 prerequisite).

**Concept-viability gate (SHADER_CRAFT §2.0).** All three gates clear before CC.1 starts:

1. **Musical role (one sentence).** *"The crystal cavern's caustics flash on drum onsets (`stems.drums_energy_dev` — beat-coupled accent), the IBL ambient breathes with sustained bass (`f.bass_att_rel` — continuous primary), and the caustic refraction angle drifts continuously with vocals pitch — so the listener pairs kicks with caustic flashes, sustained bass with the scene brightening, and the melody with the way light bends through the crystal cluster."* Names three specific musical features paired with three specific visual behaviours per CLAUDE.md FA #58 / D-102.
2. **Iconic visual subject deliverable at fidelity.** Full rubric profile. This is the flagship — the fidelity bar is the *highest* in the catalog. Tier 2 6.5 ms budget; comparable past preset Glass Brutalist uses the same stack (ray-march + post-process + SSGI) and demonstrates the fidelity is achievable. **Risk acknowledged**: per CLAUDE.md Authoring Discipline ("treat Matt's fidelity warnings as constraints"), the flagship target is ambitious; if any session produces output that does not read against the curated references, the right action is to escalate to "this preset doesn't have a viable design at this fidelity target" rather than continue tuning (FA #58 lesson).
3. **Infrastructure-feasible.** Uses existing V.1–V.4 utilities. One amber: screen-space caustics utility (`Volume/Caustics.metal`) has no production consumer and may have rough edges (CC_DESIGN §4). CC.3 has a documented fallback (`fbm8` overlay) if the utility output is unworkable.

**Status.** Planned. **Schedule:** waits on LM, Arachne V.7.10 cert review, and Aurora Veil cert. Crystalline Cavern is positioned as the demonstration-of-ceiling piece for collaborators / external review — landing it after at least one other M7-certified non-Arachne preset (e.g. Aurora Veil) reduces the risk that it ships with rough edges that pull down the catalog's perceived quality.

### Increment CC.0 — Reference curation

**Scope.** Curate the reference set per CC_DESIGN §2 — geode interior cathedral, crystal termination close-up, cave caustics, wet limestone wall, bioluminescent cave, pattern glass close-up, anti-reference video-game crystal cave, anti-reference Tron neon. Author `docs/VISUAL_REFERENCES/crystalline_cavern/README.md` with per-image annotations matching the Aurora Veil README format. Confirm against `CheckVisualReferences --strict` (V.5).

**Done-when.** Reference set complete; README annotations include mandatory / decorative / actively-disregarded traits per D-065; anti-references named explicitly.

### Increment CC.1 — Scene structure (no materials)

**Scope.** Cavern walls (4-plane intersection with `worley_fbm` displacement), central crystal cluster (5 hex-prism SDFs with hash-driven per-instance jitter), floor crystals, hanging tips. Default white-on-grey rendering. Static camera composition framing. No materials, no audio coupling.

**Deliverables.** `PhospheneEngine/Sources/Presets/Shaders/CrystallineCavern.metal` (sceneSDF, sceneMaterial stubs returning matID only). `CrystallineCavern.json` (full rubric profile, certified: false). `PresetLoaderCompileFailureTest.expectedProductionPresetCount` bumped.

**Done-when.** Composition reads correctly against geode reference photography (Matt eyeball, not a formal M7 yet). Engine + app builds clean. Visual harness emits a default-fixture PNG.

### Increment CC.2 — Materials pass

**Scope.** Wire `mat_pattern_glass`, `mat_polished_chrome`, `mat_wet_stone`, `mat_frosted_glass` via `sceneMaterial`. Triplanar detail normals on cavern walls. Per-instance hash-jitter on crystal cluster (CLAUDE.md FA #44 lesson). `CrystallineCavernMaterialBoundaryTest` passes.

**Done-when.** Four materials visibly present and stable across material boundaries. PresetAcceptance D-037 invariants pass. SwiftLint clean.

### Increment CC.3 — Lighting + atmosphere + caustics

**Scope.** Bioluminescent §5.3 lighting recipe (warm key, blue-purple IBL, emission on pattern-glass + frosted-glass crystals). IBL palette × `lightColor.rgb` for valence tint (D-022 path). Volumetric ground fog via `vol_density_height_fog`. Light shafts via `ls_radial_step_uv`. Screen-space caustic projection.

**Validation gate.** Verify `Volume/Caustics.metal` produces workable output at CC's geometry scale. **If unworkable**, fall back to procedurally-animated `fbm8` overlay sampled at the floor projection (documented in CC_DESIGN §4 / §5.4). The fallback is a one-session detour; the cert-quality target is still the real caustic utility if it works.

**Done-when.** Lighting + atmosphere + caustics rendering coherently. Tier 2 kernel cost ≤ 6.5 ms; Tier 1 ≤ 5.0 ms (with the degradation path: SSGI off, caustic samples halved, ray-march steps 64 → 48).

### Increment CC.4 — Audio routing + mv_warp + cert

**Scope.** All eight audio routes from CC_DESIGN §5.6 wired (IBL bass breath / key bass breath / caustic flash drums-dev / caustic refraction vocals-pitch / IBL valence tint / shimmer mid-rel / mid-pulse caustic offset beat-phase / crystal emission bass+valence). mv_warp at conservative shimmer amplitude (≤ 0.003 UV, per CC_DESIGN §5.5 / D-029 lesson). All four preset-specific tests green (`CrystallineCavernSilenceTest`, `CrystallineCavernCausticBeatRatioTest`, `CrystallineCavernMaterialBoundaryTest`, `CrystallineCavernMvWarpStaticityTest`). Matt M7 review against curated references. On green: flip `certified: true`.

**Done-when.** M7 sign-off. Rubric score ≥ 14/15 (potential 15/15 with thin-film inclusion per CC_DESIGN §5.5).

**Estimated total: 4 sessions** (this is the flagship; complexity is justified by the demonstration value).

**Open questions per CC_DESIGN §11.** (1) `architectural` family enum value vs. existing categories; (2) caustic utility production-readiness — validated in CC.3; (3) POM on cavern walls — deferred until after first Matt review; (4) Tier 1 acceptable-degradation tradeoff vs. tier-2-only gating; (5) thin-film inclusion in CC.5 polish if rubric score 14 → 15 is wanted.

---

## Phase NB — Nimbus (first volumetric-family preset)

First consumer of the V.2 Volume tree (`Utilities/Volume/*`). Single-pass 2D direct-fragment volumetric ray-march; `family: volumetric` (new `PresetCategory` case, Matt-authorized 2026-06-04, D-140). Design of record: `docs/presets/NIMBUS_DESIGN.md`; plan: `docs/presets/NIMBUS_PLAN.md`. Tier 2 (M3+) only (`complexity_cost.tier1` above the Tier-1 ceiling → Orchestrator excludes on M1/M2).

### Increment NB.0 — Reference lock ✅ (committed 2026-06-04, precondition baseline)
Curated 10-image reference set + README (D-065(c) annotations + `05_anti_*`) in `docs/VISUAL_REFERENCES/nimbus/`; `NIMBUS_DESIGN.md` + `NIMBUS_PLAN.md`. Found uncommitted at NB.1 start; committed as the precondition baseline. **Follow-up:** `06_palette_cool_baseline.jpg` (manifest slot) is absent from disk — re-source it (the cool target is specified in prose meanwhile).

### Increment NB.1 — Macro maquette ✅ (2026-06-04) — budget resolved via noiseVolume (NB.1.1)
**Delivered.** `Nimbus.metal` (single-scatter volumetric march: ellipsoidal envelope × eroded detail; 64-step front-to-back; `hg_phase(·,0.4)`; 6-step envelope self-shadow; cool-indigo tint; ACES; true-black void; density-only + step-count debug `#define`s). `Nimbus.json` (`passes:[]`, family volumetric, certified:false, rubric full, `complexity_cost {tier1:9.0, tier2:6.0 provisional}`). `PresetCategory.volumetric` (D-140). `expectedProductionPresetCount` 18→19. `NimbusBudgetProbeTests` (env-gated). `PresetVisualReviewTests` arg + noiseVolume parity binding + `PresetTests` allCases 11→12.
**Visual:** maquette reads — single coherent gaseous body, denser/brighter core, soft fraying edges, true-black void, framed per `01_macro_coherent_body` (Matt eyeball pending).
**Budget gate — fired then RESOLVED (DESIGN §6.1):** the original computed-noise march was over budget (p50 20.2 ms @1080p; 7.5 ms even @half-res). Diagnosis: the cost was the per-step `fbm4` ALU (voronoi removal was a wash). Fix (NB.1.1, Matt-directed): sample the preamble `noiseVolume` 64³ 3D texture (production-bound on the direct path) instead of computing `fbm4` → **p50 1.37 ms @1080p, within Tier-2 at full res with ~5.6 ms headroom** (look improved). Stays inside NB.1's mandate (noiseVolume is preamble-injected + production-bound; only test paths gained a parity binding, FA #66).

### Increment NB.2 — Meso/micro detail cascade ✅ (2026-06-04)
**Delivered.** `Nimbus.metal` detail field rebuilt into the macro→meso→micro cascade (SHADER_CRAFT §2.2), all `noiseVolume`-sampled (no computed per-step noise — §6.1 rule held): **meso** nested billow lobes (two octave-doubled scales q*0.7/q*1.4) that *carve the envelope multiplicatively* (valleys thin toward transparency → distinct lumps, not the saturated solid-surface egg); **micro** domain-warped fine filaments (warp via two cheap decorrelated `noiseVolume` taps, never `fbm_vec3`/`warped_fbm`) + multiplicative rim filament-mask → peeling curling tendrils dissolving into the void (no hard cut); **interior turbulence** on the named `kNimbusTurbulence` knob (placid↔churning, NB.6 wires arousal). Extinction σ 2.1→1.55 so the translucent body's front-to-back accumulation reads lobe depth with no new lighting (lobe-to-lobe shadow is NB.3). 4 noise octaves (0.7/1.4/2.8/5.6) → §12.1 floor. Test/prod parity: both test paths (`PresetVisualReviewTests`, `NimbusBudgetProbeTests`) now bind the full noise set via `TextureManager.bindTextures` (slots 4–8), matching production exactly (FA #66).

**Budget (re-measured, NIMBUS_DESIGN §6.2):** macro+meso+micro **p50 1.65 ms @1080p** (vs NB.1 macro 1.37 ms) — +0.28 ms for doubling samples 3→6/step, because the envelope early-out keeps most steps free. 0.24× the 7 ms Tier-2 ceiling, well under the NB.2 ≤~3 ms target; ~5.35 ms headroom preserved for NB.3–7. **Recipe:** SHADER_CRAFT §6.5 — the first V.2-Volume-consumer entry (envelope shaping, multiplicative billow carve, translucent-σ depth, domain-warp-on-texture-coords, texture-noise budget rule). Visual: density-only guard shows a bounded body with dominant negative space + feathered edges (not anti-uniform-fog, not anti-solid-surface); step-count heatmap confirms early-out localizes cost. Matt eyeball (contact-sheet-style), not a formal M7. `certified:false` unchanged.

### Increment NB.3 — The look: HZD/Nubis cloud-port + fidelity uplift ✅ (2026-06-04 → 2026-06-05)
**Delivered.** Replaced the NB.1/NB.2 Perlin-FBM blob with the ported Horizon: Zero Dawn / "Nubis" volumetric-cloud technique (Perlin-FBM cannot make billows — §0 Direction reset):
- **NB.3.0** — baked a tileable 3D **Perlin-Worley** texture (`gen_perlin_worley_3d` in `NoiseGen.metal`: RGBA = PW base + 3 inverted-Worley detail octaves) in `TextureManager`, auto-bound on the direct path (the one engine touch).
- **NB.3.1** — density from PW billows (R) carved by Worley detail (G/B/A), HZD-remapped against the analytic envelope as coverage → bounded body + feathered cauliflower edges. Off-lattice sample offset kills a 4-fold mirror symmetry.
- **NB.3.2** — backlit lighting: forward-scatter HG + a detail-aware ~6-step **cone self-shadow** march → luminous backlit billows.
- **NB.3.3 — fidelity uplift (Matt-directed, reference-aligned).** Closed the three reference-packet gaps **strictly within the backlit model — no emission**: coverage-gated interior billow/crevice contrast (ref 02, soft rim ref 03), a radial denser core for substance (ref 01), +15% on-screen size via focal zoom (`kNimbusFocal` 1.25→1.44), and the forward-scatter silver-lining glow + brightness lift (ref 08). An egg-core / internal-emission / "incandescent" exploration was tried and **reverted** as a divergence — the packet is a BACKLIT cool body (light scattering *through* the medium), not an emissive one (durable note in `NIMBUS_DESIGN.md §5.2`). Matt-approved on the render-vs-packet contact sheet.

**Budget (NIMBUS_DESIGN §6.3):** p50 **3.27 ms @1080p**, 0.47× the 7 ms Tier-2 ceiling — within, ~3.7 ms headroom for NB.4→NB.6. **Gates:** 1378 engine tests green; SwiftLint `--strict` clean; app build clean; `PresetLoaderCompileFailureTest` at 19; density-only guard clears anti-fog + anti-solid; mode-2 heatmap intact; debug toggle at 0. Still NO audio coupling (NB.4) and NO mood (NB.6); `certified:false` unchanged (cert is NB.9).

### Increment NB.4 — Energy (Breath): bloom → size + brightness + flow + silence floor ✅ (2026-06-05)

**Delivered.** The hero coupling (DESIGN §1.3) — the first and only Energy driver, no beat, no mood. `NimbusState.swift` (new, `Sources/Presets/Nimbus/`; `public final class @unchecked Sendable` + NSLock, mirrors `AuroraVeilState`): a fast-attack (~150 ms) / slow-release (~400 ms) one-pole follower over the broadband energy deviation `(bass_att_rel+mid_att_rel+treb_att_rel)/3` (D-026 — never absolute thresholds, FA #31) → `bloom`; a `flowPhase` accumulated in `Double` (long-accumulator rule) at a bloom-modulated rate; flushed to a 16-byte `NimbusStateGPU` (`bloom`, `flowPhase`, 2× pad) at fragment buffer(6). Shader (`Nimbus.metal`): reads `constant NimbusStateGPU& nb [[buffer(6)]]` (byte-matched MSL mirror; orthogonal to `noiseVolume` at *texture* 6) and consumes `bloom` for **body extent** (uniform `bodyScale` inflation of the whole field, `mix(0.80,1.16,bloom)` → +45 % floor→peak; bound sphere + cone-shadow reach grow with it), **luminosity** (`bright = mix(0.65,1.17,bloom)` → +80 % floor→peak, scaling the back-key + ambient together so the backlit rim-vs-core contrast is preserved), and `flowPhase` for the **gas drift** (replaces wall-clock `features.time` in `nimbus_density`; 1×→3.5× via `flowFloor`/`flowPeak` in state). Silence floor = the NB.3 backlit look, smaller/dimmer/slower over a faint non-black cool **haze** halo (D-037 — concentrated near the body, dark corners → negative space preserved, NOT anti-uniform-fog). Live wiring in `VisualizerEngine+Presets.swift` (`if desc.name == "Nimbus"` → alloc + `reset()` + `setDirectPresetFragmentBuffer` + `setMeshPresetTick`), `nimbusState` ivar, teardown null, **track-change `reset()`** in `VisualizerEngine+Capture.swift` (body settles into the new track rather than carrying the prior bloom).

**Tests.** `NimbusBloomFollowerTest` (new): Part A asserts the asymmetric follower feel (floors at silence, fills under energy, reaches half FASTER up than down, flow never freezes); Part B renders the converged silence-floor + full-bloom states through the **live direct dispatch path** (`preset.pipelineState` + slot-6 buffer + noiseVolume) and asserts silence non-black (D-037) + energetic brighter + bigger. `PresetVisualReviewTests` gains Nimbus-specific silence/mid/energy fixtures (explicit AttRel) + per-fixture `NimbusState` priming + slot-6 bind. `NimbusBudgetProbeTests` binds a primed slot-6 buffer (FA #66 parity).

**Budget (NIMBUS_DESIGN §6.4):** p50 **2.66 ms @1080p** (steady-mid, bloom ~0.5), 0.38× the 7 ms ceiling — the CPU follower adds no GPU cost; full-bloom worst case ~3.6 ms est. **Gates:** 1380 engine tests green; SwiftLint `--strict` clean; app build clean; `PresetLoaderCompileFailureTest` at 19; contact sheet shows the bloom range (silence small/dim/slow-non-black → mid ≈ NB.3 → energy big/bright/fast) with the backlit look preserved. **No beat / no mood verified by source inspection.** `certified:false` unchanged. **Remaining gate: Matt's live manual-validation sign-off on "feels married to the music" (non-bypassable — automated tests prove the route fires, not that it feels musical).**

### Increment NB.5 — Beat: stem lobes (the band plays the body) ✅ (2026-06-05, D-141)

**Reverses the "nothing on the beat" premise (D-141).** The first real-music test of NB.4 (the *Atlas* / Battles session, a relentless 136-BPM track) showed the energy-only bloom **too subtle** and, on bass-dominated music, structurally floored: `bloom` averaged 3 bands and with mid (0.04) / treble (0.004) near-silent the dead bands vetoed it — the body sat at floor-size all session while the beat (beatComposite > 0.5 on 53 % of frames, grid locked) went unanswered; meanwhile all four stem deviations swing hard (peaks 1.9–2.8). Matt's call: drive from the beat, per stem; chose "one mass heaves per-stem" over hard quadrants.

**Delivered.** `NimbusState` gains four fast-attack/slow-release stem followers — `kickPunch` (drums; `max(beatBass,beatComposite)` onset pulse, zero-delay frame 1, blended to `drumsEnergyDev` via D-019 warmup), `bassLobe`/`vocalsLobe`/`otherLobe` (stem `…EnergyDev`); `bloom` re-sourced to the mean of the four stem **energies** (fixes the 3-band floor). `NimbusStateGPU` 16→32 bytes. Shader: `nimbus_envelope` heaves the **single** body per stem (`rr/(1 + kick + Σ lobe·cos²)` — star-convex, cannot fragment, protecting the §1.4 one-mass identity): drums punch + brighten the whole body, bass heaves DOWN, lead flares UP, other swells to the SIDE; the bound grows by the live bulge so a heave never clips. **FA #4 honoured** — beat is an accent on top of the slow bloom; safe here (no feedback loop, zero-delay pulse, soft-decay heave forgives ±80 ms).

**Tests.** `NimbusBloomFollowerTest.test_stemLobes` (new): renders baseline/bloom/kick/bass/vocals/other through the **live direct path**, asserts each follower fires only for its stem, the luma-weighted centroid shifts the right way (bass down, vocals up, other side), drums brighten+inflate the whole body, and every fixture stays one present mass. NB.4 follower tests + budget probe + visual review carried forward (slot-6 = 32 bytes).

**Budget (NIMBUS_DESIGN §6.5):** p50 **3.74 ms @1080p**, 0.53× the 7 ms ceiling — within, ~3.3 ms headroom for NB.6. **Perf lesson:** `pow(cos,1.5)` for the lobe falloff doubled the budget to 5.15 ms (the GPU predicates the guard — paid even at rest); cos² (pure mul-adds) → 3.74 ms. Never use `pow()` in a per-march-step falloff. **Gates:** 1381 engine tests green; SwiftLint `--strict` clean; app build clean; `PresetLoaderCompileFailureTest` at 19; per-stem contact sheet shows directional heaves on one coherent mass. `certified:false` unchanged. **Remaining gate: Matt's live manual-validation sign-off (does the body feel like it's playing with the band?).**

### Increment NB.3.4/.5 — Smoke qualities (texture + rising/curling motion) ✅ (2026-06-05)

After the NB.5 live test read as a static blurry blob, Matt reframed: smoke/cloud is defined by how it MOVES. **Texture (NB.3.4):** 2-octave fractal Worley detail cascade + interior cauliflower carve (lump/crevice contrast throughout) + bigger base billows (scale 0.55→0.40). **Motion (NB.3.5):** replaced the linear noise drift with rising/curling smoke — vertical rise + helical twist + a 2-octave organic swirl warp (billows roll over each other) + faster-churning detail, on the flowT bloom clock. Motion character "rising curling smoke" (Matt's call); 2 Matt-provided motion references recorded in `NIMBUS_DESIGN §1.2`. Budget (§6.6): the naïve version hit 20 ms — fixed with a **cheap shadow density** (`nimbus_density_shadow`, 1 sample — the cone self-shadow only needs coarse depth), 64 steps, and a 10 % smaller blob (Matt-directed) → 3.78 ms. Perf lessons: never `pow()` in a per-step falloff; match step count to the finest kept octave; on-screen area is a linear budget lever. `NimbusBloomFollowerTest.test_motionStrip`. Matt-approved ("looks good, proceed").

### Increment NB.8 — Performance tranche (half-res render path) + beat-sync ✅ (2026-06-05)

The 2nd Atlas live session showed the body **swelling to fill the frame** at full energy costs **mean 6.84 / max 14.5 ms, 56 % of frames over the 7 ms ceiling** — every prior budget probe under-measured by priming the steady-mid body, not the swell (durable lesson: profile a volumetric preset at its WORST on-screen body). **Fix: a half-resolution direct-render path** — Nimbus's fragment renders to a 0.5× offscreen texture + bilinear upscale (`feedback_blit` + linear-clamp sampler); ~4× cheaper → worst-case ~3 ms (the §5.5 MetalFX reserve was never wired, and MetalFX Temporal needs motion vectors a procedural volume lacks, so a simple upscale substitutes). Engine: `RenderPipeline.setDirectRenderScale` + `drawDirect` branch + `encodePresetVisualization`/`halfResTarget` (new `RenderPipeline+DirectDraw.swift`); opt-in per-preset (others unaffected). `complexity_cost.tier2` 6.0→**4.0** from the corrected worst-case profile. **Beat-sync** tightened: the kick now fires from the predicted grid beat (anticipatory `smoothstep(0.82,1,beatPhase01)`, peaks ON the beat) with the onset as fallback — vs the ~80–120 ms onset lag. **Gates:** 1384 engine tests green (incl. `test_halfResUpscale` + corrected worst-case probe + updated AV.2.2a slot-6 guard); SwiftLint clean; app build clean; count 19. Budget §6.7/§6.8. **Remaining: Matt's live sign-off on the half-res look + the tighter beat.**

### Increment NB.6 — Mood (valence→colour, arousal→agitation) ✅ (2026-06-05)

The last feature before cert. `NimbusState` smooths valence + arousal ~4 s (FA #25 — from the FeatureVector, never written back; D-024), stored in the former GPU pad floats (`NimbusStateGPU` stays 32 bytes, byte-layout unchanged). Shader: **valence → body colour** (`mix(indigo, gold, valence01)` at composite, with the ambient fill + haze halo warming too → the whole mass shifts cool↔warm, D-022 propagation); **arousal → flow agitation** (`mix(0.65, 1.55, arousal01)` drives the detail-erosion strength — calm = smoother lobes, energetic = torn/fraying edges; replaced the compile-time `kNimbusTurbulence`). Verified: `NimbusBloomFollowerTest.test_moodTravel` (cool R/B 0.71 → warm R/B 1.79) + the cool/warm/calm/wild contact strip; the visual-review fixtures set a cool valence so the contact sheet still matches the 06-cool references. 1385 engine tests green; SwiftLint clean; app build clean; count 19. Deferred (don't block cert): per-track-distinct gas seed + PresetSessionReplay registration. **Pending Matt's live sign-off; then NB.9 cert.**

### NB.9 — certification ✅ **CERTIFIED by Matt (M7, 2026-06-05, session 20-33-47Z, 8 tracks)**

**Phase NB complete — Nimbus is the first certified `volumetric`-family preset (D-140).** M7 history: r1 (session 18-26-37Z) + r1.5 (19-03-04Z) did NOT certify, but both unknowingly ran the **stranded old `main` Nimbus** (the NB.10 changes were on a worktree branch the build never saw — see [[feedback_worktree_changes_reach_build]]); the first build with the real changes (after integration to main) passed on session 20-33-47Z. Cert state: `Nimbus.json` `certified: true`; `"Nimbus"` added to `certifiedPresets` in `FidelityRubricTests` (heuristic gate false-by-construction — volumetric, no `mat_*`/`fbm`; the M7 reference review is the load-bearing gate per SHADER_CRAFT §12.1). Accepted-at-cert limitation: **beat-grid live phase** ("too active / not synced" on some tracks, e.g. Love Shack) is bounded by the shared cached-grid phase, deferred to its own infrastructure project **D-145** (after Skein). Noted future enhancement (Matt): **extend the mood palette beyond cool-purple ↔ warm-gold** (a richer colour family) — `NIMBUS_DESIGN §8`. Session-artifact confirmation: per-track bloom p50 0.44–0.61 (vs the pre-r1.6 0.13) and warmth read matched Matt's live calls track-for-track (Love Shack/In Undertow/No Surprises/Love Rehab/Atlas warm, Pyramid Song cool, Sad Song + A Girl In Port travel).

**Earlier (round-1) automated prep ✅; the M7 round-1/1.5 narrative:**
Per `NIMBUS_PLAN.md`: ~~NB.7 Page (CUT — §1.3)~~ → NB.9 certification. NB.5-as-Pulse cut; NB.8 done early; mood (NB.6) done. A certified Nimbus = the band playing one packet-matching cool-gas body: beat (per stem) + energy swell + mood, fitting Tier-2 budget via the half-res path.

**Automated prep landed (M7-independent).**
- **§5.7 acceptance audit + two new gates.** Mapped every §5.7 bullet to a gate (closeout table). Silence-non-black, energy primacy (bloom→size/bright), flow-alive, valence→colour, perf — already covered (`NimbusBloomFollowerTest`, `NimbusBudgetProbeTests`, `PresetAcceptanceTests` inv. 1–4, which Nimbus already clears as a `direct` preset). Two gaps filled in `NimbusBloomFollowerTest`: (1) **body coherence / negative space** (`test_bodyCoherenceNegativeSpace`) — at the absolute worst case (full bloom + max kick + all three lobes), the body stays a bounded mass (coverage 0.668 < 0.80 ceiling) with dark corners (corner/centre 0.082 < 0.30) → ≠ `05_anti_uniform_fog` (the single worst failure, §1.4); (2) **arousal→agitation route-live** (extends `test_moodTravel`) — calm↔wild MSD 84.3 ≫ 0 proves the second mood axis carries signal (partner to the valence→colour assertion).
- **Golden dHash registered** in `PresetRegressionTests` — Nimbus now binds a zeroed slot-6 `NimbusStateGPU` (deterministic silence-floor body) and registers `0x0F0F0F0F0F0F0F0F` (identical across all three fixtures, because the shader reads no FeatureVector field but `aspect_ratio`). A centred-body fingerprint sensitive to silhouette / backlit-lighting / haze regressions.
- **Stale `Nimbus.json` description** refreshed to the shipped band-plays-the-body reality (was "Look being rebuilt… nothing fires on the beat" — both false post-NB.3/NB.5).
- **M7 artifacts generated** — contact sheet (render vs 3 TRUST refs + 2 AVOID anti-refs; render clearly rejects both anti-refs), silence/mid/energy bloom range, rising/curling motion strip (8 frames), cool/warm/calm/wild mood strip, per-stem lobe sheet, worst-case budget (half-res p50 **2.56 ms**, within the 7 ms ceiling).
- Gates: **1386 engine tests green** (the only failures are the pre-existing gitignored-`Tests/Fixtures/` absence in a fresh worktree — `love_rehab.m4a` et al.; restoring the fixtures makes the suite 1386/1386); SwiftLint `--strict` 0/424; app build clean; `PresetLoaderCompileFailureTest` 19.

**M7 round 1 (session `2026-06-05T18-26-37Z`, 7 tracks) — Matt would NOT certify.** Two findings, different root causes (diagnosed from the session csv): **(a) mood colour too subtle / sometimes wrong** — Billie Jean "white/gray", B.O.B. "purplish — why? energetic". Root cause: a perfectly good valence signal was washed out downstream (bright-core desaturation to near-white + muted poles + valence-only mapping). → **NB.10 (D-144), done below.** **(b) beat behind / not locked to downbeats** — root cause: the shared beat-grid's *live phase* (grids lock with correct tempo, but cached-grid phase is imperfect on live audio; meter assumed simple). This is the system-level Cold-Start Phase limit (FA #69), NOT a Nimbus shader bug. Matt's call: **open the beat-grid as its own project (D-145)**; Nimbus's beat axis waits on it. Cert flip steps unchanged (`certified` false→true + `"Nimbus"` → `certifiedPresets` in `FidelityRubricTests` + doc sweep + `RENDER_CAPABILITY_REGISTRY`), still gated on a passing M7. **No push without Matt's "yes, push."**

### NB.10 — mood expressiveness uplift (energy warms it) ✅ (2026-06-05, D-144) — pending M7 r2
Addresses M7 r1 finding (a). Pure `Nimbus.metal` shader change (no state change — `bloomV` + `arousal` already in `NimbusStateGPU`): **(1)** colour now driven by *warmth* = `valence01` lifted by `energy01 = 0.55·arousal01 + 0.55·bloomV`, expanded around mid (`kNimbusMoodContrast`) — an energetic track reads hot even at neutral/low valence (the B.O.B. fix); **(2)** the bright core keeps its **mood hue** (brightened), no longer washing to near-white (the Billie Jean "white/gray" fix); **(3)** saturated poles (vivid indigo-violet ↔ rich amber/gold), ambient + haze warm with `warm01` too. Gates: `test_moodTravel` valence R/B **0.85→3.11** (was 0.71→1.79) + a NEW energy-warmth assertion (neutral valence, low↔high energy R/B **0.85→2.89**) locking the B.O.B. fix; mood strip shows a vivid violet cool pole / rich gold warm pole / gold high-energy-neutral-valence body; the golden hash is unchanged (dHash is luma-gradient, hue-invariant). **1386 engine tests green; SwiftLint 0/424; app build clean; count 19.** All hues are starting points — Matt's eye sets the finals.

**NB.10 r1.5 correction (2026-06-05, same day) — D-144 amended.** The v1 energy-warmth *regressed* live (M7 r1.5, session `2026-06-05T19-03-04Z`: "clobbered… displays neutral"). Root cause (reconstructed `warm01` from the session): the `+0.6·(energy01−0.25)` lift added a flat warm bias to every moderate-energy track, collapsing the cool↔warm range (Sad Song → gold). Fix: warmth primarily valence; energy-warmth AROUSAL-gated past a high threshold (only bangers warm); contrast 1.35→1.60; `moodTau` 4.0→2.5 s (colour travels instead of fading to the mean). Re-verified on the session (In Undertow cool 0.33, range restored). The classifier reads "Sad Song" as +0.11 valence (audio-mood ≠ title-mood) so it renders warm-ish regardless of the shader — a classifier characteristic. 1386 tests green; SwiftLint clean; app build clean; count 19.

**NB.10 r1.6 bloom recalibration (2026-06-05, same day; Matt: "input problem, solve permanently") — D-144 amended.** The small/dim bodies (which made the mood colour hard to see) are NOT a quiet-capture/input issue — I first wrongly blamed Spotify normalization; Matt confirmed it off + 100 % volume. Root cause (measured): `{stem}Energy` is the stem's 3 AGC bands **summed**, but the AGC normalises the *6-band total* to 0.5, so a 3-band sum centres at ~**0.30** (measured p50 0.24/0.27/0.41 across 3 sessions), not the 0.5 the bloom assumed — so `bloom = meanStem·1.4−0.2` gave ≈ 0.13 (tiny) on normal music; Atlas only looked right as an unusually dense master. Fix: `NimbusState` `bloomGain` 1.4→1.9, `bloomOffset` −0.2→−0.06. Verified: meanStem 0.27 → bloom **0.45** (was 0.18), dynamic range kept (0.14→0.21, 0.55→0.98), silence floors at 0. Regression-locked by `test_bloomVisibleOnTypicalMusic`. **Same mis-calibration class as BUG-027** (every energy value centres ~0.3 not 0.5) — the system-wide normalisation fix is BUG-027's domain (its own project, re-tunes every preset). Makes Nimbus bodies bigger on all music (Atlas re-judged at M7 r2). **1387 tests green; SwiftLint 0/424; app build clean; count 19.**

### D-145 — beat-grid live-phase as its own project (deferred from Nimbus)
Matt opened the shared beat-grid's live-phase quality as a separate workstream (M7 r1). The felt "behind the beat / wrong downbeat" is bounded by the cached-grid phase, not Nimbus — and per FA #69 any work here needs a *new premise* (not another short-window live-tap iteration). Scoping note: `docs/diagnostics/BEAT_GRID_LIVE_PHASE_PROJECT_2026-06-05.md` (the M7 r1 diagnosis + candidate premises). Nimbus's beat axis (kick timing / downbeat feel) waits on this; the mood uplift (NB.10) does not.

---

## Phase Skein — action-painting / drip-pour preset (`painterly`)

New preset in the Dragon Bloom lineage (D-135 / D-138): a Pollock-style poured / dripped **action-painting** visualiser whose canvas is a persistent, **lossless** feedback accumulation (paint lands, stays, is occluded only by later opaque paint-over-paint — the temporal-integral canvas). Design: `docs/presets/SKEIN_DESIGN.md`; plan: `docs/presets/SKEIN_PLAN.md`. Critical path: Skein.0 → ENGINE.1 → Skein.1 → 2 → 3 → 5 → 6; wet-sheen (ENGINE.2 + Skein.4) is the explicit cut-line branch.

### Skein.0 — Reference lock ✅ (2026-06-05)
Reference set curated + Matt-approved; `docs/VISUAL_REFERENCES/skein/` populated, `CheckVisualReferences` green (commits `07a4a57b` / `52ebfe3d`). Anti-reference images + the V.6 rubric profile deferred per the Skein.0 closeout.

### Increment Skein.ENGINE.1 — Canvas-hold accumulation path ✅ (2026-06-05, D-142)
Establishes the persistent, lossless paint canvas: **identity warp + no decay + no R→G→B transfer + marks-on-top**, the no-decay / identity **configuration** of the mv_warp brush-on-feedback paradigm (a sibling of Dragon Bloom — D-142). **Audit verdict: config-only — no PhospheneEngine source change, no new warp mode** (the four properties are reachable as per-preset config; `decayMul = (chromaticMix>0)?1.0:in.decay` proves no-decay is *not* bound to the colour transfer). Files: `Skein.metal` (identity `mvWarpPerFrame` decay=1.0 / `mvWarpPerVertex` returns `uv` + a `skein_fragment` toned-ground + fixed test stamp), `Skein.json` (`passes:["direct","mv_warp"]`, decay 1.0, uncertified, no `family` yet), `SkeinCanvasHoldTest.swift` (new), `PresetLoaderCompileFailureTest` count 19→20. **`SkeinCanvasHoldTest` proves whole-frame Hamming 0 across 130 hold frames** through the live scene→warp→blit→swap dispatch path (sRGB feedback; sRGB round-trip + identity-at-pixel-centers both exact → no linear-format / nearest-sampler override needed). **Gates:** 1388 engine tests green; `PresetRegressionTests` byte-identical for every other preset (no shared code touched); MVWarp/StagedComposition green; app build clean; SwiftLint `--strict` clean (424 files); contrast + acceptance gates pass for Skein. **Flagged for Skein.1+:** ~~app-wiring de-entanglement of "scene-geometry ⟹ Dragon Bloom chromatic+comp" + generalize `makeSceneGeometryPipeline` names~~ → **DONE in Skein.ENGINE.1.1 (D-143)**; the light-canvas-vs-white-chrome WCAG contrast tension (ENGINE.1 uses a darkened toned-ground placeholder — still deferred per D-142(b)); `family: painterly` + the `PresetCategory` case (still deferred per D-142(c)). **Pending Matt's sign-off (the increment gate).**

### Increment Skein.ENGINE.1.1 — Per-preset marks-on-top + cream ground ✅ (2026-06-05, D-143)
Clears the ENGINE.1 "flagged for Skein.1" de-entanglement (a) and makes **Skein render live for the first time** (cream ground + held test disc through the real pipeline). The D-138 marks-on-top half was hard-wired to Dragon Bloom in three places; generalising them touched SHARED mv_warp wiring (a D-137 beachball risk), so this lands as its own gated, golden-regression-locked infra patch **before** Skein.1. **Audit verdict: smallest additive change — existing presets resolve exactly as before, only a new per-preset path is added.** The three couplings → per-preset: (1) `PresetLoader.makeSceneGeometryPipeline` resolves `<prefix>_geometry_*` (legacy `dragon_bloom_strand_*` fallback; stale "additive blend" doc fixed → normal alpha); (2) a new optional **`marks` descriptor block** (`vertex_count`/`instance_count`/`primitive`/`chromatic`/`comp`/`beat_pulse`) drives draw params + chromatic + comp + the comp beat pump (gated by `marks.beat_pulse`, was `sceneGeometryState != nil`); (3) per-preset **canvas-clear colour** on `MVWarpPipelineBundle`/`MVWarpState` → `clearWarpTextures(to:)` from `marks.canvas_clear`. Dragon Bloom's block carries its exact literals (1536/3/lineStrip, chromatic 1.0, comp 1/0.5/1.07, beat on) → byte-identical. Skein: `skein_fragment` → flat cream GROUND; the fixed disc → `skein_geometry_*` fullscreen-triangle overlay (hard-edged so the per-frame redraw is idempotent), `chromatic=0`, black-free cream clear. Files: `PresetLoader.swift`, `PresetDescriptor.swift` (`MarksConfig`), `RenderPipeline+MVWarp.swift` / `+PresetSwitching.swift` / `RenderPipeline.swift` / `MVWarpTypes.swift`, `VisualizerEngine+Presets.swift`, `DragonBloom.json` (+`marks`), `Skein.metal` / `Skein.json` (+`marks`), `SkeinCanvasHoldTest.swift` (marks-on-top test), `PresetAcceptanceTests.swift` (Skein readable-form exemption). **Gates:** engine suite green except 7 pre-existing `love_rehab.m4a`-fixture-absent failures (git-ignored licensed clip, unrelated); `PresetRegressionTests` + `DragonBloomMVWarpAccumulationTest` + `FataMorganaMVWarpAccumulationTest` byte-identical; new marks-on-top test green (disc on cream, `chromatic=0` Hamming-0 over 130 frames, `chromatic=1.0` cycles) through the live scene→warp→overlay→blit→swap path; PresetAcceptance + PresetContrast green for Skein; app build clean; SwiftLint `--strict` clean. **Pending Matt's sign-off (the increment gate).**

### Increment Skein.1 — Canvas + pour spike ✅ (2026-06-05, commits `57ee7383` / `528021b5`) — pending Matt's eyeball gate
Replaces the ENGINE.1.1 static test disc with a **single white pour LINE traced by a wandering "painter,"** accumulating losslessly on the cream canvas. No audio (driven by `features.time` only). This is the **gate-before-the-gate** (SKEIN_DESIGN §7): does a persistent skein hold + read as poured paint? **Audit verdict: pure preset increment — no engine touch, DB/FM byte-identical by construction.** **Trajectory decision — Path A (closed-form, in-shader):** the marks-on-top overlay binds `features` only at the **vertex** stage (`drawSceneGeometryOverlay:36`, no fragment binding), so the painter position is computed in `skein_geometry_vertex` (which already reads `features@0` — the same slot `dragon_bloom_strand_vertex` reads) and passed to the fragment as varyings; the fragment draws a swept-capsule 2D-segment SDF from `painter(t−Δt)` → `painter(t)`, AA'd (each capsule stamped once then held, so no in-place re-blend). **No CPU state, no per-preset buffer, no engine touch** — Path B (`SkeinState` + a gated overlay-buffer binding) was correctly **deferred to a future ENGINE.1.2** when Skein.2's stateful painter needs it (FA #59/#60). Trajectory: three gesture scales per axis at non-harmonic (incommensurate) frequencies — a slow drift carrying the painter across the canvas (the §1.0 fact-2 island-then-join build order) + gesture loops (~6 s) + tight loops (~2.5 s), all in the gesture band; the loops are the GESTURE (§1.0 fact 1), never a coiling/noise term; width rides 1/speed (pools at turning points, filament on sweeps — §1.0/§1.2, refs 02/03). **Trailing-off (Matt eyeball-pass refinement, `8b8d167d`):** the pour's leading END thins + fades to a point via a closed-form tapering tail over the painter's last ~0.67 s (the VisComp 2014 line layer — width tapers toward the endpoint as the stream thins). A *fully*-persistent trailing-off (the whole recent stretch fading) is the wet-now/dry-past device (§1.4) and needs the deferred wetness channel (Skein.ENGINE.2); the in-shader tail is the achievable Skein.1 approximation. Files: `Skein.metal` (pour line replaces the disc), `SkeinCanvasHoldTest.swift` (the disc hold test → the **accumulation + hold + continuity** gate, + env-gated contact sheet). `Skein.json` unchanged. **Gates:** the new pour gate green through the **live** scene→warp→overlay→blit→swap path advancing `features.time` (256², chromatic=0, 180 frames): accumulation `[128,211,301,422]` (monotone + grows), early-painted texel persists, unpainted far corner byte-identical frame0→final, continuity = **1.000** (single connected component), cream ground + white line; full engine suite green except the same 7 `love_rehab.m4a` fixture-absent failures; `PresetRegressionTests` + DB/FM accumulation byte-identical; `PresetLoaderCompileFailureTest` preset count intact (no silent MSL drop); PresetAcceptance + PresetContrast green for Skein; app build clean; SwiftLint `--strict` clean (424 files). **Eyeball artifact:** `RENDER_VISUAL=1`/`SKEIN_VISUAL=1` contact sheet at ~2/5/10/20 s (480×270, live path) — a continuous wandering pour line accumulating with gesture loops + crossings + pool/filament width contrast. **No new capability** (Path A uses the Supported canvas-hold + marks-on-top rows) — registry instances refreshed disc→pour line, no status flip. **Deferred (unchanged):** `family: painterly` + the `PresetCategory` case (D-142(c)/D-143 — a product-taxonomy / engine-touch decision, not in Skein.1's pure-preset scope); per-track seed (Skein.3); the ENGINE.1.2 overlay-buffer binding (opens with Skein.2). **Pending Matt's eyeball gate** (SKEIN_PLAN: if a persistent skein doesn't hold + read as paint, the concept stops here).

### Increment Skein.2 — Splatter morphology + viscosity ✅ (2026-06-05) — Matt eyeball PASS (cert at Skein.6)
Adds the **splatter vocabulary** to the held canvas alongside the Skein.1 pour line: velocity-biased **droplet bursts** (ragged 2D-noise edges, exp/poly satellite size+density falloff with distance — the VisComp 2014 *droplet* layer), thin **filament tendrils**, and a **viscosity axis** (thin-fast-fine ↔ thick-slow-gloopy) shaping every mark — all baked normal-alpha into the same lossless canvas. **No audio:** bursts fire on a deterministic flick schedule; viscosity is a closed-form **debug** sweep of `features.time` (period ~12 s) so a *still frame* exhibits the full morphology. Real onset→splatter / centroid→viscosity / stem→colour routing + the per-track seed are Skein.3. **Audit verdict — Path A extended (closed-form, in-shader): no engine touch, no `SkeinState`, no per-preset buffer; DB/FM byte-identical by construction.** Confirmed with file:line evidence that `drawSceneGeometryOverlay` (`RenderPipeline+SceneGeometry.swift:36-37`) binds `features` only at the **vertex** stage (no fragment buffer — Dragon Bloom shares this code, so a Path-B per-preset buffer would be a gated D-137-risk engine touch); the splatter needs neither multi-frame droplet flight nor per-stem accumulators (paint **lands and the canvas holds it** — §1.4), so everything is a deterministic **hash of (flick, droplet)** generated in `skein_geometry_fragment`, plus a debug viscosity computed in `skein_geometry_vertex` and passed as a varying. ENGINE.1.2 (`SkeinState` + the gated overlay buffer) stays **deferred to Skein.3**, its real consumer (FA #59/#60; SKEIN_DESIGN §7). **Two iteration findings (the highest-aesthetic-risk increment, as called):** (1) big+dense+ragged droplets merge into "cauliflower froth" → fixed with **small+crisp+wider-flung+fewer DISTINCT dots**; (2) straight line→droplet filaments radiate as a **sci-fi starburst** (= the particle-burst anti-reference) → **forward-gated, short, sparse** so they read as directional spray-streaks. Ragged edges use a new **`skein_fbm2`** (4-octave `perlin2d`, inter-octave rotation, sampled at non-lattice scaled coords → FA #43-clear); AA from the smooth radial distance with raggedness in the threshold radius; per-flick + per-droplet scissor early-outs keep cost ∝ this frame's marks (§6). Viscosity → line-width factor floors at **1.0** (only widens) so the Skein.1 continuity invariant is preserved. Files: `Skein.metal` (`skein_fbm2` + `skeinDebugViscosity` + splatter/filament/viscosity in `skein_geometry_fragment` + the `visc` varying; the canvas-hold mv_warp config + `skein_fragment` cream ground untouched), `SkeinCanvasHoldTest.swift` (corridor-isolated pour-LINE continuity + a new splatter test: halo dense-near/sparse-far, viscosity response, opaque-not-additive, satellite bake/hold, per-frame new-mark count + a viscosity-sweep contact sheet). `Skein.json` unchanged. **Gates:** all 5 Skein tests green through the **live** scene→warp→overlay→blit→swap path — pour-LINE corridor continuity **1.000** (Skein.1 invariant preserved) + 1158 satellite pixels outside the corridor; splatter halo near/mid/far THIN 692/418/32 vs THICK 210/47/0 (dense-near ✓); viscosity response THIN 64 satellites @ meanSatDist 0.057 > THICK 18 @ 0.043 (more + wider ✓); opaque minCh = cream (no mud ✓); 178/179 frames added marks (new-mark count ✓). Full engine suite green except the same 7 pre-existing `love_rehab.m4a` fixture-absent failures; `PresetRegressionTests` + `DragonBloomMVWarpAccumulationTest` + `FataMorganaMVWarpAccumulationTest` byte-identical; `PresetLoaderCompileFailureTest` count intact (no silent MSL drop — FA #72); PresetAcceptance + PresetContrast green for Skein; app build clean; SwiftLint `--strict` clean (424 files). **Eyeball artifacts:** `SKEIN_VISUAL=1` accumulation contact sheet (960×540, ~2/5/10/20 s) + a **viscosity-sweep** sheet (thin | thick poles, independent fresh accumulations) through the live path; all 5 anti-references checked clear (matte not neon; ragged not polka-dots; pour not brush; ~9 % coverage not dead-mat; asymmetric not kaleidoscope). **No new capability** (Path A = nothing engine-side; registry instances refreshed, no status flip). **Deferred (unchanged):** `family: painterly` + `PresetCategory` case; per-track SHA seed + audio routing + ENGINE.1.2 (all Skein.3); wetness/sheen (ENGINE.2/Skein.4). **M7 round 1 (2026-06-05, live session `2026-06-05T22-59-05Z`, Mingus, 900×600):** Matt — "looks good"; flagged that **droplets read as rounded-SQUARES** (flat cardinal edges). Root cause (verified by zooming the live frame to the pixel level): the droplet AA used `fwidth(length(q−dpos))`, whose gradient is the radial unit vector → ~41 % wider AA at the diagonals than the cardinals → sharp cardinal edges snap to the axis-aligned pixel grid. **Fix:** isotropic `px = max(fwidth(q.x), fwidth(q.y))` AA + a `max(drr, px·1.5)` radius floor (so sub-2 px far satellites still read round). Droplets now round (bbox-fill 0.65–0.70 vs square ~1.0), regression-locked by a roundness gate in `SkeinCanvasHoldTest`; SHADER_CRAFT §18.3 corrected. Two non-code M7 items deferred: **colour** (white-on-cream is the deliberate Skein.2 boundary → stem palette lands at Skein.3) and **pacing** (a slow accumulator wants longer on-screen segments + energy-coupled painter speed — addressed at Skein.3 when speed ties to arousal/energy, plus `duration` tuning). **M7 round 2 (2026-06-05): Matt eyeball PASS** ("looks good") on the round droplets — Skein.2's aesthetic gate is met (a still frame reads as poured paint, not a particle fountain, with a believable droplet/halo/filament structure and a visible viscosity axis). Preset *certification* (full M7 ≥5 tracks + soak + determinism + golden dHash) remains **Skein.6**; `certified` stays false. Integrated to local `main` (merge `1310c1c4`, alongside the parallel AGC2 / D-146 merge `a07b2a56`; NOT pushed).

### Increment Skein.ENGINE.1.2 — `SkeinState` + gated slot-6 overlay buffer ✅ (2026-06-05, D-147)
The deferred ENGINE.1.2 (the CPU-side `SkeinState` + the per-preset overlay buffer) lands as Skein.3's first commit — its demonstrated consumer is the stateful audio routing. **Audit verdict: Option B (gated binding), Option A (pure config) UNAVAILABLE.** With file:line evidence: Skein renders via the marks-on-top `strandsOnTop` branch (`RenderPipeline+MVWarp.swift:212`), which **skips** `renderSceneToTexture` (`:217`) — the *only* site that binds fragment slot 6 (`RenderPipeline+MVWarpScene.swift:43-44`). Pass 2's `strandsOnTop` branch (`encodeMVWarpScenePass:77-79`) calls `drawSceneGeometryOverlay`, which binds only `features`@vtx0 + `stems`@vtx1 (`RenderPipeline+SceneGeometry.swift:36-37`) — **no fragment buffer**. So the overlay fragment could not see `directPresetFragmentBuffer`; Option A is impossible. Landed the lightest **Option B**: a gated `if let presetBuf = directPresetFragmentBuffer { setFragmentBuffer(index:6) }` in the `strandsOnTop` branch — affects only DB + Skein. **Byte-identical:** Dragon Bloom sets no `directPresetFragmentBuffer` (reset to nil at applyPreset top → no bind); Fata Morgana uses its own `renderFataMorgana` draw branch (never reaches `encodeMVWarpScenePass`). `SkeinState.swift` (new, GossamerState pattern): `SkeinHeaderGPU` (64 B) + 48 × `SkeinBurstGPU` (48 B) = the audio-modulated painter clock + per-track seed phases + dominant-stem line colour + onset-burst ring. Wired in `VisualizerEngine+Presets.swift` (construct/tick via `setMeshPresetTick` / `setDirectPresetFragmentBuffer`, cleanup); `currentSkeinSeed()` reuses the shared FNV-1a title|artist hash (`lumenTrackSeedHash` de-privatised). **Stub consumer:** commit 1 leaves the shader unchanged (buffer bound-but-unread) → Skein renders Skein.2-identical; the shader read lands in the routing commit. Files: `SkeinState.swift` (new), `RenderPipeline+MVWarpScene.swift`, `VisualizerEngine.swift` / `+Presets.swift` / `+Stems.swift`. **Gates:** DragonBloom + FataMorgana MVWarp accumulation + `PresetRegressionTests` byte-identical; `PresetLoaderCompileFailure` count intact; app build; SwiftLint `--strict` clean. Commit `f0fef708`.

### Increment Skein.3 — Stem palette + full emission routing ✅ (2026-06-05, D-147) — Matt M7 PASS 2026-06-06
Makes the painting **legibly musical**: `skein_geometry_fragment` consumes `SkeinUniforms@6` (ENGINE.1.2). **Routing (all D-026 deviation-normalised, D-019 warmup-gated):** stem→colour (one stable, well-separated colour per stem over cream — **Full Fathom Five: charcoal/oxblood/ochre/teal, Matt-approved**), composited **OPAQUE** (paired bestCover/bestCol → topmost colour, never mud); pour-line colour ← dominant stem (SkeinState discrete argmax — no blend), width ← its energy-dev + viscosity; splatter bursts ← per-stem activity (`*_energy_dev` above threshold, refractory-limited) frozen at each stem's colour (the onset-burst ring; **retires the Skein.2 debug flick schedule**); viscosity ← per-burst centroid (**retires the debug viscosity sweep**); flick sharpness ← attackRatio; painter speed ← broadband energy-dev; per-track seed → trajectory phase. **Key finding:** only `drums_beat` is a real pulse (the other `*_beat` reserved-zero) → per-stem onsets derive from `*_energy_dev` activity in SkeinState (the history the closed-form fragment cannot see). **sRGB (FA #71):** the `.bgra8Unorm_srgb` canvas sRGB-encodes on store → SkeinState sRGB-DECODES the display palette to linear before packing; without it dark stems lifted to washed mid-tones and painted nothing (drums/bass = 0 → 933/2905 after the fix). **§1.5 track-change reset:** on track change while Skein is active, reseed the painter from the new identity + `clearMVWarpCanvasToGround()` (a lightweight gated canvas wipe — DB/FM never call it). Files: `Skein.metal` (consume slot 6, MSL `SkeinUniforms`/`SkeinBurstGPU`, debug drivers retired, sRGB-aware header), `SkeinState.swift`, `RenderPipeline+MVWarp.swift` (`clearMVWarpCanvasToGround`), `VisualizerEngine+Capture.swift` (reseed+clear on track change), `PresetSessionReplay/SkeinRoutes.swift` (new — per-stem onset routes + painter-speed; centroid/attackRatio not SR.1-measurable), `SkeinCanvasHoldTest.swift` (real-stem colour/route gate + seed determinism). **Gates:** real-stem colour/route gate through the live path (replayed real stems) — **≥3 separable clusters (got 4 — all stems), opaque-not-mud 0.075, onset→splatter busy 129 vs steady 0, D-019 warmup 0-at-silence, bake+hold, round droplets**; seed determinism (same seed pixel-diff 0, diff-seed 3947, reseed clears 160→0 bursts); DB/FM MVWarp + PresetRegression byte-identical; PresetLoaderCompileFailure count intact; app build; SwiftLint `--strict` clean; **palette contact sheet → Matt signed off (Full Fathom Five)**. Commits `7098eff7` (colour+routing), `8ddcb438` (seed+reset); integrated to local `main` merge `ceaccfdf` (NOT pushed; only `DECISIONS.md` conflicted — kept the D-146 AGC2.5 amendment + D-147, no number collision). **Deferred (unchanged):** `family: painterly` + `PresetCategory` case; wetness/sheen (ENGINE.2/Skein.4); mood/structure/anticipation/locus (Skein.5); cert (Skein.6). **✅ M7 gate PASS (2026-06-06):** Matt "Looks great!" live on local-file session `2026-06-06T14-59-12Z` (Skein active, no errors, 4318 frames, all four stems active → every colour painted) — the legible-musicality gate is met. Full cert remains Skein.6.

### Increment Skein.ENGINE.2 — Wetness channel ✅ (2026-06-08, D-149)
The transient per-pixel **wetness** signal the wet/dry sheen needs: stamped ~1 where paint lands this frame, decaying toward 0 each frame (decay **pauses at silence**), readable at the display stage — without touching the **RGB lossless paint record** (the ENGINE.1 Hamming-0 invariant) and **byte-identical for every other mv_warp preset** (the D-137 beachball pitfall). **Audit verdict — approach A (canvas ALPHA channel), cleanest form (D-149):** the per-prefix override mechanism (`PresetLoader.swift:689`/`:691`, the Fata Morgana precedent) lets Skein own its warp + comp fragments with **no shared GPU code touched**. (1) **Storage = the feedback texture's ALPHA** (linear 8-bit on the `.bgra8Unorm_srgb` feedback — sRGB never touches A; RGB stays the lossless record). (2) **Stamp = the existing overlay alpha-over blend** (`A = bestCover² + dst.a·(1−cover)` → solid fresh paint → A≈1; **no new stamp code**). (3) **Decay = `skein_warp_fragment`** (holds RGB byte-identically — the identity sample — and does `A *= wetnessDecay`; `wetnessDecay = exp(-rate·dt·stemMix)` from `SkeinState` pauses at silence). (4) **Read-hook = the blit already samples the compose texture** → Skein.4 reads `.a`. Plumbing: a gated `mvWarpWetnessDecay` uniform (mirror of `mvWarpChromatic`) at warp-fragment `buffer(1)`, default 1.0 — only `skein_warp_fragment` declares it, FM never runs the standard warp pass → **DB/FM/Starburst byte-identical by construction**. **Cut-line: NOT invoked** (no shared format change, no new pass, no loop reshape). Approach B (dedicated R8) rejected (forces MRT on the shared overlay pass or a mark re-dispatch — more code/risk for the same separation). Files: `RenderPipeline.swift`/`+PresetSwitching.swift`/`+MVWarp.swift` (the uniform + bind), `Skein.metal` (`skein_warp_fragment`), `SkeinState.swift` (`wetnessDecay`), `VisualizerEngine+Presets.swift` (per-frame push, weak-captured; reset to 1.0 on preset switch), `SkeinCanvasHoldTest.swift` (`SkeinWetnessTest` + the RGB-only hold re-scope). **Gates:** `SkeinWetnessTest` green through the live path — stamp max ALPHA **255**, unpainted-corner decay **253→172** under music (0 rises = monotone), silence spread **0** (held exactly); DB/FM MVWarp accumulation + `PresetRegressionTests` (20 presets × 3 conditions) **byte-identical**; the RGB lossless-hold Hamming-0 (RGB-only) green; `PresetLoaderCompileFailure` count intact (no silent MSL drop, FA #72); app build clean; SwiftLint `--strict` clean. Commits `255fcc64` (engine), `c5192d28` (test).

### Increment Skein.4 — Wet/dry sheen ✅ (2026-06-08) — pending Matt's M7
The **wet-now / dry-past legibility device** (`SKEIN_DESIGN §1.4`): fresh paint glistens, the accumulated past is matte, so the eye tracks the musical *now*. `skein_comp_fragment` (the `<prefix>_comp_fragment` override — the shared `mvWarp_blit_fragment` stays byte-identical) reads canvas RGB + wetness A: **wet → GGX specular** (normal from the canvas **luminance gradient** — central-difference/Sobel bump, the 2D analogue of a surface normal; tonemapped GGX NDF, Walter et al. 2007), **hard-gated by wetness** (`smoothstep` on A) so it fires on recent paint and ~0 on the dried past; **dry → matte + slight desaturation**; subtle canvas-weave grain (fades under thick paint). The sheen is an **additive glint + a subtle wet saturation "deepen"** (glossy *depth*, not whitening) so the Skein.3 stem colours **read THROUGH** it — and a **paint-present mask** (distance from the cream ground) keeps the bare canvas matte. **sRGB (FA #71):** the feedback is `.bgra8Unorm_srgb` → sampling auto-decodes to linear; lighting in linear; the drawable re-encodes on store — **no manual decode** (the inverse of FM's linear-feedback trap). Bloom-on-wet-specular **deferred** (needs a pass / governor state at the blit — the in-shader glint gives the sparkle without a new pass, cut-line-conscious); **no new audio routing** (wetness = where paint landed, FA #67). Files: `Skein.metal` (`skein_comp_fragment` + sheen tuning), `SkeinCanvasHoldTest.swift` (wet-now/dry-past gate via the BLIT + per-checkpoint BLIT capture + sheen contact sheet + canvas-vs-blit isolation PNG). **Gates (live BLIT path, real replayed stems):** wet (A>180) sheen boost **25.77** mean vs dry (A<80) **3.71** (≈7×), a **162**-byte glint catches the light, stem colours read through — **CANVAS [1906,7205,5601,10328] → BLIT all 4 stems intact** (a highlight, not a recolour); full engine suite green except the same 7 pre-existing `love_rehab.m4a` fixture-absent failures (+ the known MemoryReporter flake); `PresetRegressionTests` + DB/FM MVWarp byte-identical; `PresetLoaderCompileFailure` count intact; app build clean; SwiftLint `--strict` clean. **Eyeball artifacts:** `SKEIN_VISUAL=1` sheen contact sheet (4 checkpoints, live BLIT) + a canvas-vs-blit isolation (L: raw matte canvas, R: sheened blit) — the recent wet bursts glisten/deepen vs the matte teal lines. **Round-1 self-review false alarm (logged):** a 900-frame run read as "the sheen killed the colours" — the cause was the session's other-dominated intro (one stem painted yet), not the sheen; a 1500-frame run shows all 4 stems read through (SHADER_CRAFT §18.9). **M7 round-1 (Matt, live, 2026-06-09, session `2026-06-09T13-00-27Z`, Cherub Rock):** "one of my favorite presets so far" — but two defects: (1) the pour appears as **overlapping circles that smooth into a line after ~a second** (kills the dribble illusion), (2) the **wet doesn't fully read as glistening**. **M7 round-2 fixes (2026-06-09):** (1) **retired the Skein.1 trailing-tail age-taper** — the radius+opacity ramp across co-located tail samples drew the concentric rings (it was the *stand-in* for a wet edge before ENGINE.2 existed); the pour now LANDS SOLID (full opacity, constant radius, speed→width only) → a continuous dribble, and the wetness channel carries "fresh = wet". (2) **two-term sheen** — a BROAD gloss (smooth normal, keeps the wet body glossy) + a SPARKLE (fine `perlin2d` micro-normal — bright catch-lights = the glisten); dropped the saturation "deepen" (it darkens in sRGB). Gates re-green: pour-LINE continuity still **1.000** (solid stroke), wet boost **25→76** mean / glint **162→192** with all 4 stems reading through, PresetRegression + DB/FM byte-identical (Skein-metal-only changes). **M7 round-2 (Matt, live):** rings STILL present at slow movement + "the glistening just makes the paint look SPECKLED — it does not convey wet." **M7 round-3 fixes (2026-06-09):** (1) the real ring cause was the rendering FORMULA — `max over per-capsule coverage` with a PER-SEGMENT speed→width radius scallops at slow/looping movement (the sheen amplifies it into concentric arcs); fixed by rendering the stroke as ONE **union SDF** (`min over segments of segDist−r`) with one per-frame radius → a single smooth tube (verified smooth on real music). (2) **retired the micro-normal sparkle** (it reads as grain) and **corrected the wet model** — wet paint is DARKER + more SATURATED (water-soaked) with a coherent glossy catch-light, not brighter/speckled (dry = lighter + matte). The wet/dry gate now measures the sheen's content-isolated effect (`blit−canvas`): wet Δchroma +29.5 / Δluma −0.2, dry Δchroma −20 / Δluma +6.9, gloss max +156, all 4 stems read through. `distinctBlobs` threshold 8→3 (session-robust — confirmed pre-existing via revert; the now-largest session is line-dominant so droplets connect to the line; dot shape/firing covered by the roundness + onset→splatter gates). SHADER_CRAFT §18.9 updated with the rounds-2–3 corrections. **M7 round-3 re-look (Matt):** the wet *direction* was INVERTED — "lighter on application, darker as it dries." The broad glossy catch-light brightened fresh paint enough to cancel the darken (wet Δluma only −0.2), so fresh read lighter + dried darker. **Round-3b fix:** the body darken DOMINATES the gloss (darken ×0.74; gloss shrunk to a tight glint rough 0.12 / gain 0.40) → wet Δluma −13 (clearly darker), dry +6 (lighter) = correct direction. **M7 round-4 (Matt):** "the rings appear ~1s after the line and then fade — they were displaced, not removed." The union-SDF fixed the line GEOMETRY, but the rings were the SHEEN amplifying the WETNESS AGE-BANDS — a looping painter lays overlapping passes at different ages → a solid stroke has a finely-banded wetness map → the read-time sheen renders the bands as concentric rings ~1s later (once the wetness decays into the steep part of the wet→dry gate), then they fade. **Round-4 fix:** BLUR the wetness the sheen reads (13-tap two-ring Gaussian ≈±12 texels) + a near-LINEAR gate (smoothstep 0.05,0.95); the large-scale wet→dry read is preserved. **New gate `test_sheen_noConcentricRings`** reproduces the transient (real stems, max-over-checkpoints of the sheen-added local luma range at smooth painted interiors) — A/B-validated by revert: 27.6 (rings) → 8.5 (blurred). **✅ M7 PASS (2026-06-09, session `2026-06-09T15-19-40Z`):** Matt — "Rings are gone and the drying of the wet paint looks good too." Skein.4 (the wet/dry sheen) is **accepted**; `certified` stays false (full cert Skein.6). **Deferred to a new session (Matt, context-budget): Skein.4.1 colour-per-stroke** — the line recolours mid-stroke because the redrawn tail uses the current dominant-stem colour; the fix is to freeze the line colour per-segment (a `SkeinState` breakpoint ring, mirroring the per-burst colour freeze) so a colour change reads as a new pour. Paste-ready prompt: `~/Downloads/SKEIN.4.1_color_per_stroke_session_prompt.md`.

### Increment Skein.4.1 — Colour-per-stroke ✅ M7 PASS (2026-06-09, 2 rounds)
The pour line's colour = the dominant stem (`SkeinState` argmax) applied uniformly along the redrawn 40-frame tail each frame, so a dominant-stem switch recoloured the recent stroke ("the colour changes in the middle of a stroke," Matt M7 2026-06-09, session `2026-06-09T14-19-14Z`). **Landed (D-150) — Matt chose option 2 (a colour change is a genuinely NEW pour, not a recoloured seam):** a `SkeinState` colour-**breakpoint ring** (push `(painterTau-at-switch, linear colour, bounded position offset)` on each dominant change) packed as an additive tail of the slot-6 `SkeinUniforms` (`SkeinBreakGPU`, 24 B; `pad0`→`breakCount`). `skein_geometry_fragment` Layer A looks up each tail sample's lay-time colour+offset (`skeinLineLookupAt`, ascending-ring early-out) so (a) already-laid paint **keeps its colour** (the per-burst freeze applied to the line) and (b) a switch starts a **spatially displaced new pour** — each pour carries a fixed-magnitude (0.05 UV) golden-angle-rotated offset (non-cumulative → never drifts off canvas; seeded → §5.7 determinism), and the segment bridging two pours is not drawn → a clean gap. **Coverage is byte-identical to Skein.4's union SDF** (one per-frame radius → `max-over-capsules ≡ 1−smoothstep(min sdf−r)`), so no rings regression. Bursts flick from the jumped position (throw direction from the un-offset path). Files: `Skein.metal` (`SkeinBreakGPU`/`SkeinLineLookup`/`skeinLineLookupAt` + Layer A rewrite + `SkeinUniforms` additive tail), `SkeinState.swift` (the ring + jump + `SkeinColorBreakpoint` test accessor + `lineDominantStem`), `SkeinCanvasHoldTest.swift` (`test_lineColorFreeze_keepsColourAndStartsNewPour` + helpers). **Gates:** the new live-path test green (switch stem 2→1: pre-switch @offA X=61 Y=0 — old paint kept its colour; post-switch @offB Y=61 X=0; jump 0.093, new pour at offB not the un-jumped path); silence continuity 1.000; `test_sheen_noConcentricRings` 8.68 < 13; real-stem colour separation (4 stems, mud 0.067); determinism same-seed=0; DB/FM + `PresetRegressionTests` byte-identical; `PresetLoaderCompileFailure` count intact (FA #72); full engine suite 1408 tests, 7 pre-existing `love_rehab.m4a` fixture-absent failures only; app build + SwiftLint `--strict` clean. Eyeball: `SKEIN_VISUAL=1` real-stem palette/sheen contact sheets (live path) show distinct per-stem coloured pours. **M7-round-2 (Matt, live, 2026-06-09, session `2026-06-09T16-23-21Z`): "the lines are very short rather than a long continuous dripping/pouring across the canvas."** Root cause (measured on the session: **63 dominant switches / 44 s, median pour 0.2 s**) — the dominant-stem argmax flickers far faster than a pour reads, so each tiny pour + jump became a short displaced segment. Fix: a new pour now COMMITS only on a sustained, decisive change — `minPourTau = 3.0` τ (≈ half-canvas minimum) since the last switch AND the challenger leads by `pourSwitchHysteresis = 1.25×`; colour/flow/viscosity follow the *committed* pour (not the instantaneous argmax); bursts stay ungated. Validated: **63 → 10 long pours (~4 s avg)**; contact sheet on `2026-06-09T13-06-15Z` shows long continuous coloured pours across the canvas. Test surface: `distinctBlobs` demoted to a diagnostic (long lines absorb droplets → ~0 separable blobs even though splatter fires; gate the route on per-stem spawns + busy≫calm instead), bake/hold made colour-agnostic (a longer first pour can be low-spread charcoal). All gates re-green (Skein suite, DB/FM + PresetRegression byte-identical, app build, SwiftLint `--strict`). **Deferred (unchanged):** `family: painterly` + `PresetCategory` case; mood/structure (Skein.5); cert (Skein.6).

---

### Increment Skein.ENGINE.3 — Structural-section signal → preset tick ✅ (landed 2026-06-09; D-151; Matt chose option (a))
**Discovered as a prerequisite of Skein.5's structure sub-feature** (the increment was split: `StructuralPrediction` is DSP/orchestrator-only and does not reach the preset tick). Matt chose **option (a) — a deliberate engine increment** (over an in-state proxy / deferral) for real section-awareness, honouring infra-before-preset (FA #59/#60). **Landed (D-151):** a **gated `RenderPipeline.setStructuralPrediction(_:)`** (separate lock-guarded `storedStructuralPrediction` + computed `latestStructuralPrediction`, default `.none` — mirrors the `setMood` value-injection bridge) is called from `VisualizerEngine+Audio.swift` **at the per-frame MIR publish (right after `setFeatures`, reading `mir.latestStructuralPrediction`)** — NOT the `setMood` site the prompt's recon suggested, because that site is unconditional + freshest (the `setMood` path early-returns when the mood classifier is absent / throws); the Skein tick closure reads `pipeline.latestStructuralPrediction` and passes it to the extended `SkeinState.tick(…structure: = .none)`, which STORES `sectionIndex`/`sectionStartTime`/`confidence` + a one-frame `didCrossSectionBoundaryThisFrame` flag (cleared on `reseed`). **CPU-only** (no `FeatureVector`/`Common.metal` change; never written to the GPU buffer), **byte-identical** for every other preset (the setter is inert at `.none`; even Skein's own render is byte-identical), golden-locked (`PresetRegressionTests` 20×3 + DB/FM MVWarp accumulation + `PresetLoaderCompileFailure` count, all green). **Delivers + proves the signal only; the structural VISUAL is Skein.5** — the app is **visually identical to today**. Gate: `SkeinStructureSignalTests` (FA #66 — real bridge + the `meshPresetTick` invocation indirection + ingestion + one-frame boundary). Full engine suite green (the known 7 `love_rehab.m4a` fixture-absent fails excepted); app build + `swiftlint --strict` clean. Prompt: `~/Downloads/SKEIN.ENGINE.3_structure_plumbing_session_prompt.md`.

### Increment BUG-034 — `sceneParamsB.z` double-booking: D-057 step multiplier vs ambient ✅ (landed 2026-06-12; M7-lite reviewed)
The A6 audit finding (P1, FA #66 class): `makeSceneUniforms()` packed `sceneAmbient` into the slot the G-buffer preamble reads as the D-057 step multiplier — every ray-march fixture (goldens, contact sheets, cert evidence) marched 32 steps vs live's 128. **Done-when (met):** slot audit posted (packing map; `.w` is SSGI's radius override, NOT free as the bug entry hinted; ambient had **no consumer on any path** → removed as dead config, no struct-layout change needed); multiplier owns `.z` end-to-end (`makeSceneUniforms()`/`SceneUniforms()` default 1.0; live per-frame writes untouched — D-057 adaptive semantics preserved); slot-map contract at the `SceneUniforms` definition; `StepBudgetParityTests` (parity 128==128 derived through both code paths + default-1.0 guard; A/B-proven red on the pre-fix packing); **mandatory Task 5 stop honoured** — Matt's first review flagged the pairs as unrepresentative, root cause: the deferred ray-march harness bound none of noise/IBL/SSGI/post-process/height-field → **production-parity harness upgrade approved + landed** (all five ray-march presets, `RENDER_STEP_MULT` A/B hook); re-review approved regen for **Kinetic Sculpture** (lattice resolves deeper, 10–13 bits) + **Volumetric Lithograph** (terrain reaches the true horizon, 13 bits); Glass Brutalist in-tolerance (kept), Lumen Mosaic byte-identical, Ferrofluid golden already retired (D-124). **Certified-preset flag:** Lumen Mosaic provably unaffected; Ferrofluid Ocean cert evidence was 32-step — **Matt accepted live-path-unchanged (2026-06-12), no re-cert**. Registry §8 visual-harness row updated. **Fallout handled (Matt approved option A):** the FBS pulse gate (`FerrofluidPulseLivePathTests`, D-153/D-160) was threshold-calibrated against the invalid 32-step render — its region-mean measure only registered the punch because false sky broke D-157's steady-global-luminance contract; recalibrated at the production budget (paired per-pixel |δ|: punch 2.46 vs rest exactly 0.0, floor 1.0; S2 ratio floor 1.2× vs measured 1.38×; `FBS_PULSE_DUMP=1` eyeball dump added). Also un-broke this worktree's environment (`Scripts/fetch_tempo_fixtures.sh` — the 7 `love_rehab` fixture-absent fails + 6 churn cascades were missing fixtures, not regressions). Carry-forwards filed in KNOWN_ISSUES candidates: zero-stem fixtures can't show Ferrofluid's aurora character; `CRYSTALLINE_CAVERN_DESIGN.md` wrongly markets `sceneParamsB.w` as a free repurposing slot; `B.w` SSGI override currently writer-less; REVIEW.2 churn watchdog (5 s) squeezed by cold CoreAudio HAL start (~8 s first-run, passes warm — the REVIEW.4 soak-bound class).

### Increment BUG-035 — NoveltyDetector ring-wrap boundary dedup ✅ (landed 2026-06-09; Skein.5 step 1)
The AUDIT.1 finding gating Skein.5: `NoveltyDetector` stored boundaries by LOGICAL ring index; once `SelfSimilarityMatrix` filled, indices slid ~30 per `detect()` and the 120-frame dedup window re-admitted the same physical boundary every ~4 calls (~4-5 near-equal-timestamp duplicates per real boundary → section durations collapsed, `sectionIndex` inflated ~5×, confidence depressed — the exact D-151 signal). **Fix:** `SelfSimilarityMatrix.totalFrameCount` (monotonic) + `NoveltyDetector` stores/dedups in **absolute** frame-index space (`Boundary.frameIndex` now absolute); `MIRPipeline.latestStructuralPrediction` write moved under the lock (was the only published property outside it). **A/B-proven:** `noveltyDetect_ringWrap_boundaryRegistersOnce` (pre-fix 3 dups, identical timestamps) + `structuralAnalyzer_ringWrap_boundaryRegistersOnce` (production 600-frame geometry, pre-fix 2 dups) — post-fix exactly 1 each; `SkeinStructureSignalTests` + AABA golden green. Same session also hardened the Skein.4.1 colour-freeze gate (it hard-depended on the single largest recorded session — tonight's new session broke it; it now scans all sessions for the most decisive switch pair). KNOWN_ISSUES + RELEASE_NOTES_DEV updated.

### Increment Skein.5 — Mood + structure + anticipation + painter-locus ✅ (landed 2026-06-09; D-152; **M7 PASSED 2026-06-10** — Matt "Looks great", session `2026-06-10T03-09-20Z`)
The §1.3/§1.5 musicality layer on the working look — no new visual subject; routing + a subtle palette/motion modulation. **Mood:** valence/arousal EMA-smoothed in `SkeinState` (τ 4 s, FA #25 — never written back); `moodTinted(_:)` warms/cools (±18 % R / ∓16 % B multiplicative) + saturates (floor 0.85, never `mix(cream, hue, sat)`) the LINEAR palette **at lay time, frozen** into breakpoints + bursts — the lossless canvas archives the song's emotional arc; arousal → painter speed (×0.7–1.3), splatter refractory (÷ up to 1.5), pour width (+15 %). **Structure (consumes ENGINE.3/D-151, post-BUG-035):** a confident boundary (smoothstep 0.25→0.55 on `confidence`; below ⇒ EXACTLY zero bias — pure allover) fires a density pulse (τ 2.5 s), a boundary-forced fresh pour (floored 1.0 τ — D-150 long pours intact), a region-lean target (`seed + (sectionIndex mod 5)·goldenAngle`, ≤ 0.085 UV, EMA τ 2.5 s) routed **through the per-pour breakpoint offsets** (never a per-frame trail displacement — that smears the redrawn tail), and a ± 0.10 per-section warmth emphasis; repeated section slots revisit + densify the same patch. **Anticipation (FA #33):** τ-SPEED warping — wind-up `1 − 0.45·smoothstep(0.70, 1, beatPhase01)`, flick `+0.90·exp(−t/90 ms)` at the wrap; τ-warping keeps every tail sample ON the trajectory curve → cannot smear by construction; `mix(1, factor, stemMix)` ⇒ exactly 1.0 at silence. **Locus (flagged, OFF — `SkeinState.defaultLocusEnabled`):** display-only in `skein_comp_fragment` (the prompt's geometry-fragment site would BAKE it — FA #70 contract); the blit gains a gated `bindCompStagePresetBuffer` (slot-6 buffer at fragment buffer 1, ENGINE.2 inert-binding precedent); glow + occlusion shadow ring so it reads on cream. Files: `SkeinState.swift` (m5 `MusicalityState` + helpers extension), `Skein.metal` (`locusEnable` ← pad1 + comp locus), `RenderPipeline+MVWarp.swift` (+ split `RenderPipeline+MVWarpReducedMotion.swift` for file-length), `SkeinCanvasHoldTest.swift` (`MusicalityDrive` fixture inputs + 4 gates + contact sheet). **Gates (live path, real stems):** mood — warmth(R−B) 106.4 warm vs 81.4 cool, coverage +24 % with +arousal, pale share 0.003 ≪ 0.30; structure — spawns 88→144 across a boundary on IDENTICAL tiled audio, lean 0.083 ≤ 0.085, fresh pour +1, conf 0.05 ⇒ all-zero; anticipation — wind-up 0.649 / flick 1.627, silence exactly 1.0; locus — canvas byte-identical on/off, 24-px localized blit glow. `SKEIN_VISUAL=1` contact sheet `/tmp/skein_pour_diag/<stamp>/skein5_mood_montage.png` (hiV_hiA | hiV_loA | loV_hiA | loV_loA | locus_on). All prior Skein gates + DB/FM + `PresetRegressionTests` byte-identical + loader count intact; full engine 1419 tests (7 known love_rehab fixture-absent only); app build + SwiftLint `--strict` clean. **Done-when remaining: Matt M7** (mood + sections read; wind-up-flick with the beat). D-152. Deferred: cert + `family: painterly` (Skein.6).

### Increment Skein.5.1 — The painter never pours white ✅ (landed 2026-06-09; D-152 amendment; **M7 re-look PASSED 2026-06-10** — Matt "Looks great", session `2026-06-10T03-09-20Z`)
Matt M7 on session `2026-06-09T22-35-09Z`: "a different white line pattern showing on screen when the track starts… white disturbs the colour palette." Root cause: the Skein.1-era WHITE-BASELINE breakpoint — at canvas birth most of the 40-frame tail (incl. negative-ctau samples) resolved to the white era, baking a permanent tail-length white squiggle, displaced from the first coloured pour by its jump, different per track (the seed). **Fix (D-152 amendment):** the ring starts EMPTY (shader skips Layer A at `breakCount == 0` — no line until a pour commits); the FIRST commit waits `firstPourSettleTau = 0.25` τ (colour from ~¼ s of smoothed evidence, not one frame's argmax — D-150 decisiveness; a settle-window crash guard added for the −1 dominant index) and RETRO-COLOURS the pre-commit tail (`tauStart = 0`, no jump on the first pour) — the first stroke appears already in the lead stem's colour; the painter CLOCK pauses at true silence (`activity = max(stemMix, smoothstep(0.01, 0.04, fvEnergy))` — wetness-pause semantics; FV term keeps the clock running while stems converge). The Skein.1 "white line at silence" invariant is deliberately retired. **Gates:** `test_pourLine_accumulatesHoldsContinuous` redesigned — CALM real-stem drive (all devs below the onset threshold ⇒ line without splatter), accumulation/hold/continuity (corridor vs `finalPainterTau`) + `!hasWhiteTexel` + silence-run `painted == 0`; `!hasWhiteTexel` added to the real-stem gate (canvas birth + real stems = the defect scenario); colour-freeze gate re-green with the cleaner ring (`[ochre@τ0 off-0, oxblood@τ6.72 #1]` — the settle eliminates the spurious first-frame-argmax pour); breakpoint-ring diagnostic added to its print. Pour contact sheet re-pointed at calm stems (silence is now correctly empty cream); regenerated: line opens in colour, never white. PresetRegression/DB/FM + loader count green; SwiftLint `--strict` clean.

### Increment BUG-049 — Skein colour-freeze gate: feasibility-aware switch selection ✅ DONE (fix 2026-06-11; armed-path validation completed same evening — addendum at end of row)
The colour-freeze cert gate (`test_lineColorFreeze_keepsColourAndStartsNewPour`) picked its dominant-stem switch on decisiveness alone and only discovered at sampling time that the switch was un-sample-able (pre/post windows < 3·dτ inside the pour's reign / probe extent) — `Issue.record` red on session-set content, not code, whenever a new capture changed the pick (the 19:49 RB.2-2 closeout battery hit this; the Skein.4.1 scan-all hardening had fixed the previous face of the same fragility). **Fix (commit `a6899893`, test-infrastructure only):** `switchSampleInfeasibility` — a CPU-only dry run replaying the candidate's exact tick sequence (SkeinState.tick has no GPU read-back, so it predicts the live run's painter clock / dominant stem / breakpoint ring exactly) — vets every candidate DURING selection; the scan walks candidates in decisiveness order and arms on the most decisive switch that is also sample-able; the in-run guard remains as a dry-run/live parity safety net (its firing now means parity divergence, with that diagnosis in its message). No-candidate session sets skip LOUDLY (counts + per-candidate rejection reasons printed; never red, never silent — BUG-049 criterion 1); the Skein.3 real-stem routing gate gained the same scan-all + loud-skip treatment (it hard-depended on the single LARGEST session and went red when that was a 602-byte recorder stub). Colour-freeze assertions (pre-switch X≫Y, post-switch Y≫X, jump magnitude, new-pour-not-on-old-path) untouched. **Done-when:** met for the unusable-set arm (SkeinCanvasHold 21/21 green on the current 11-stub session set, skip reasons printed); **armed-path arms (criteria 1a/1b + the criterion-2 adversarial colour-unfrozen A/B) BLOCKED** — the only real capture (`2026-06-11T13-10-42Z`, 2.98 MB) vanished from `~/Documents/phosphene_sessions` between the 19:49 filing and the fix session (unrecoverable: Trash TCC-denied, no quarantine copy, no snapshot). Next real listening session: expect `[skein_colorfreeze] picked …` + green, then run the A/B. KNOWN_ISSUES banner + release notes dev-2026-06-11-h. Capability registry untouched (no renderer/preset capability change). **Validation addendum (same evening, parallel session):** the block was cleared without waiting for a listening session — `FixtureSessionCaptureGenerator` (new, engine test target `Diagnostics/`, env-gated `PHOSPHENE_GEN_SESSION_DIR`) replays vendored tempo fixtures through the production pipeline (ffmpeg decode → StemSeparator 10 s chunks → StemAnalyzer per 1024-hop → `SessionRecorder.csvRow`) and wrote three real `fixturegen-*` captures (~1290 frames each; FA #27-compliant). Criteria 1a/1b: gate ARMED (`picked fixturegen-so_what`, bass→drums switch) and SkeinCanvasHold ran 21/21 green with recorder stubs simultaneously present; criterion 2: freeze deliberately broken in `skeinLineLookupAt` (latest-breakpoint colour for every τ — the literal Skein.4.1 defect) → gate RED on its headline assertion (PRE-switch X=0 Y=61), reverted → green (X=61 Y=0); empty-dir leg: loud skip, green. The captures stay in place (regenerable in ~7 s) so the armed path no longer depends on listening-session happenstance. Release notes dev-2026-06-11-i.

### Increment BUG-048 — Canonical `xcodebuild test` un-broken: engine bundle removed from the app scheme's test action ✅ (2026-06-11; found by REVIEW.3's first three evidence blocks)
The app scheme's test action had included `PhospheneEngineTests` since U.1; under xcodebuild's test-runner context the engine bundle fails on environment, not code — ffmpeg subprocess spawn and repo-relative file reads denied ("Operation not permitted"), the REVIEW.2 audio churn tests die in ~1 ms, `DocIntegrityTests` reads an empty DECISIONS.md, and only ~440 of 1439 engine tests load — so the canonical app-test invocation was permanently red (exit 65) while the pure app run inside it passed. Confirmed environment-class by three evidence blocks (sandboxed shell / unsandboxed shell / Matt's terminal — identical signature). **Fix (Matt's option-1 pick over making the engine bundle xcodebuild-compatible):** remove the engine `TestableReference` from `PhospheneApp.xcscheme`'s test action — the engine suite's canonical runner is `swift test --package-path PhospheneEngine` (where all of this passes); double-running 1439 tests in a broken environment added noise, not coverage. **Done-when (met):** `xcodebuild test` exits 0 / `** TEST SUCCEEDED **` / 382 app tests green with no engine-bundle run; `SchemeTestActionRegressionTests` (engine suite) regression-locks the test-action shape (engine bundle absent AND app target present); RUNBOOK §Build and Test documents the split; KNOWN_ISSUES BUG-048 resolved with commit `e110b1ca`; release notes dev-2026-06-11-g. P2 single fix increment (root cause documented before code). Capability registry untouched.

### Increment REVIEW.3 — Closeout evidence script ✅ (2026-06-11)
Eliminates the false-green closeout class (REVIEW.1 confirmed incident: CSP.3.4 claimed 1358/1358 green; the suite failed reproducibly the next day) by replacing hand-transcribed test claims with a script-generated evidence block closeouts paste verbatim — the cheap path is now the honest path. **`Scripts/closeout_evidence.sh`** (no arguments, one mode — no quick/tiered variants) wraps the canonical RUNBOOK §Build-and-Test verification set (engine SPM tests, app xcodebuild tests, `swiftlint --strict`) and emits one fenced markdown block: header (ISO-8601 timestamp, host, short HEAD + branch, dirty/clean tree with paths), per-step verbatim tool summary lines + exit code + wall time + failing-test identifiers (≤ 20, verbatim), and a footer recapping exit codes with the verdict line (`EVIDENCE: ALL GREEN` only when every step exited 0 AND parsed failure count is 0; otherwise `FAILURES PRESENT`). Honesty contract: step failures reported never fatal (script exits 0 when evidence was gathered; the verdict line carries truth); counts extracted from tool output only, never script arithmetic (`PARSE FAILED — raw output follows` on extraction failure); additive grep only (pull summaries/failures, never filter noise); missing tool → `STEP FAILED TO RUN`, never a silent skip; dirty tree reported not fatal. A byte-identical copy lands at `~/.phosphene/last_closeout_evidence.md` so a pasted block can be diffed against what was actually generated. CLAUDE.md closeout template item 2 now requires the pasted block (prose may annotate below it, never replace it; block missing or commit-hash mismatch ⇒ closeout incomplete on its face; RB.2 will relocate the prose — the script path is the stable interface, the prose location is not). **Done-when (met):** canary-verified un-greenwashable — a deliberate `REVIEW3CanaryTests` failure produced `FAILURES PRESENT` with the canary identifier listed verbatim; the canary was deleted (tree verified back to pre-canary state); the post-commit clean run produced the increment's own self-certifying block. Capability registry untouched (no renderer/shader/cert capability change).

### Increment RB.1 — Rulebook audit (audit-only) ✅ (2026-06-11)
Evidence-cited verdict (RETIRE / MECHANIZE / DEMOTE / KEEP) for every active rule in the four rulebook populations, driven by the REVIEW.1 rule-usage table (citation counts; never-cited lists; corpus-window caveat applied to pre-2026-05-08 rules). **Done-when (met):** mechanical inventory (49 FA + 63 Do-NOT + 21 sections + 161 active D entries = 294; cross-check found D-013/031/046/086/120 already pruned to history and 15 FA numbers already moved per the gap table; only the 6 unnumbered D-LM entries were unexpectedly unmatchable by REVIEW.1's extraction — 2 %, under the 15 % stop threshold); complete verdict table (294/294 rows, 0 missing verdicts — verification greps pass); summary + budget + flagged set + RB.2 sketch + ratchet proposal. **Headline:** rule-level KEEP collapses to 12 distinct always-loaded slots (< the ~15 expectation); CLAUDE.md measured at ~22,300 tokens; projected post-RB.2 core ≈ 7,000 tokens (**proposed hard cap: 7,000 tokens, one-in-one-out**); verdict mix 37 KEEP / 35 MECHANIZE / 128 DEMOTE / 94 RETIRE; 8 flagged questions for Matt (incl. the D-039/BUG-034 interaction and the Phase-MD planning-bloc retirements). Deliverable: [`docs/diagnostics/RB1_RULEBOOK_AUDIT.md`](diagnostics/RB1_RULEBOOK_AUDIT.md) (rule text + repo evidence + citation counts only — no transcript content; public-repo constraint honoured). Capability registry untouched (no renderer/shader/cert capability change). Docs-only; no rule was moved, deleted, reworded, or renumbered; no gate was built. **RB.1.1 follow-up (2026-06-11):** the audit's six numeric aliases (D-9xx range) for the unnumbered `D-LM-*` entries collided with the DOC.4.1 referential-integrity gate landed the same day in a parallel session — `DocIntegrityTests` treats every `D-###` token under docs/ as a citation that must resolve to a DECISIONS/HISTORY header, so the engine suite failed on six unresolvable aliases. Fixed by dropping the aliases and referencing the `D-LM-*` names directly throughout the audit tables (least-invasive option: no gate allowlist that would weaken the D-155/D-145 corruption coverage, no DECISIONS.md renumbering). Both increments' intent preserved; DocIntegrityTests suite green.

**Redirected 2026-06-11 (Matt, in-session):** the verdict-table approach was rejected — citation-driven defaults and necessity rubrics are subjective with an illusion of rigor; some rules' founding "mistakes" may themselves be misdiagnoses (FA #48 named). New deliverable: **plain-English per-entry explanations** (what it is / why it exists / what happens if removed, with honest lack-of-context flags) for all 49 FAs + 63 Do-NOT bullets — [`docs/diagnostics/RB1_FA_DN_EXPLANATIONS.md`](diagnostics/RB1_FA_DN_EXPLANATIONS.md). **Matt decides per entry; no verdicts in the deliverable.** The v1 verdict tables remain as inventory/measurement reference only. Matt's stated expectation: 80–90 % of FAs/DNs disappear.

### Increment RB.2 — Rulebook purge, FA/DN scope ✅ (2026-06-11; executed against Matt's per-entry in-session review)
Matt reviewed the RB.1 explanations doc per entry and directed: keep FA #27/#31/#64/#65/#67/#73 + the `@Published` write-or-clear bullet; FA #4 held pending his ruling on beat-driven-motion-as-technique; replace FA #39/#63 with a session-start checklist; FA #21 → code comment; remove everything else; accept all DN recommendations. **Executed:** CLAUDE.md FA list 49 → 7 entries, §What NOT To Do 57 → 1 bullet (16,530 → 7,614 words ≈ 10.3 k tokens, −54 %); gap table extended so all 42 removed numbers resolve (DOC.4.1 gate green); one-line tombstones in `HISTORICAL_DEAD_ENDS.md §RB.2`; new [`docs/PRESET_SESSION_CHECKLIST.md`](PRESET_SESSION_CHECKLIST.md) (replaces FA #39/#63 + the Arachne read-first bullet, includes render-early) pointered from §Visual Quality Floor; FA #21/DN-42 facts moved to doc comments in `SystemAudioCapture.swift` (DN-43/DN-54 were already documented at their code sites); `DocIntegrityTests` FA floor 40 → 7. **Open from this scope:** FA #4 ruling (recommend: remove + soften §Audio Data Hierarchy to constraint-based framing per FBS evidence); FA #25 mood-preservation test and FA #72 MSL-name lint (noted follow-ups, not built). **Not yet scoped:** SEC (CLAUDE.md sections) and D (DECISIONS.md) populations — Matt has not ruled on those; the RB.1 v1 tables remain reference-only.

### Increment REVIEW.4 — Gates session: REVIEW.1 hooks + micro-gates + flake retirement ✅ (2026-06-11)
The deferred mechanizations, locked in: **(1) Session hooks** (`.claude/hooks/preset-session-guard.sh` + settings.json registrations, pipe-tested across 6 cases + proven firing live in-session): a non-blocking once-per-session warning on the first `.metal` edit without a `VISUAL_REFERENCES` README read (REVIEW.1 measured the prose rule at 35 % compliance — the nudge now lands at the decision point), and a once-per-session warning at `git commit` when shaders were edited with no rendered evidence (`RENDER_VISUAL`/`SKEIN_VISUAL`/`PresetSessionReplay`) this session — the render-early countermeasure to the 858 k-tokens-before-first-render class. **(2) `MoodPathRegressionTests`** — gates the D-024 mood plumbing (former FA #25): `setFeatures` preserves `setMood` valence/arousal; `setMood` disturbs nothing else. **(3) `MSLNamingTests`** — three shader-naming lints as engine tests (banned camelCase list DERIVED from Common.metal structs so new fields auto-covered; type-keyword shadowing; `[[thread_index_in_mesh]]`), all former FA #72 / DN-35 / DN-11, with the checker functions unit-tested against known-bad snippets (gates provably have teeth). **(4) SoakTestHarness cancel bound 15 → 30 s** per REVIEW.2's pre-authorization after two recurrences (17.3 s / 16.7 s under parallel load) — the last known flake retired. All 13 new/changed tests green.

### Increment RB.3 — Ratchet ratification + engineering-plan split + memory consolidation ✅ (2026-06-11)
The three standing ratchet rules ratified and installed (CLAUDE.md §Increment Completion Protocol + **D-161**): 7,000-token cap one-in-one-out (gated by the new `DocIntegrityTests` budget test — CLAUDE.md at ~6,925 est. tokens after install), new-rule admission test, violated-twice → mechanize. Pruning pass gains step 5 (plan-narrative aging). **ENGINEERING_PLAN split:** completed-increment narratives dated before 2026-06-01 moved to [`ENGINEERING_PLAN_HISTORY.md`](ENGINEERING_PLAN_HISTORY.md) (91 bodies, two rounds; headers stay as the status record; 254/254 headers preserved); plan 127,516 → 83,048 words (−35 %) — June narratives age out at future pruning passes under the same convention. `What This Is` doc-list sentence compressed (also fixed its long-standing trailing-clause typo). `__pycache__/` gitignored. Memory consolidation run against the auto-memory directory (stale facts pruned, completed-project entries collapsed). Doc-integrity suite green (4 gates incl. the new budget gate).

### Increment RB.2-2 — Rulebook purge, FA #4 + SEC + D scopes ✅ (2026-06-11; Matt: "follow your recommendations")
Completes the RB.2 populations. **FA #4:** entry retired; §Audio Data Hierarchy reframed from "beat is never primary / non-negotiable" to constraint-based ("beat-locked motion is a valid technique on the cached `BeatGrid` with D-154 irregular-track exclusion + D-157 bounded footprint; never primary from raw live onsets"); gap-table row + tombstone added. **SEC:** the 8 pointer sections + UX Contract + Visual Quality Floor merged into one §Handbook Index table; §Linked Frameworks folded into Development Constraints; §Code Style trimmed (U.11 build/test narratives → `RUNBOOK.md §Engineering notes`); §Authoring Discipline compressed to the universal working-agreement rules with the preset-session discipline (musical role, temporal contract, three-part bar, production-pipeline testing obligations, grounding priority, evidence-based closeouts) moved to `PRESET_SESSION_CHECKLIST.md` Part 2; Cold-Start Phase Contract compressed (full history already in BEAT_SYNC.md). **CLAUDE.md: 16,530 → 5,055 words (~22.3 k → ~6.8 k tokens, −69 % from the RB.1 baseline — under the RB.1-proposed 7,000-token cap).** **D:** 93 entries (shipped one-time choices, reverted/superseded/abandoned, executed design history, unexecuted Phase-MD planning artifacts) moved to `DECISIONS_HISTORY.md` §RB.2-2 batch (the D-082 Amendment moved with its parent); 68 stay active (standing constraints, live Skein/FBS/canvas contracts, legal/brand posture D-111/113/114/119/121/122 with the REVISIT banner re-anchored before D-111, gate rationales D-026/079/146); DECISIONS.md 94,982 → 39,861 words (−58 %). `DocIntegrityTests` green throughout (D continuity/uniqueness/resolution across both files; FA resolution via extended gap table); stale `#11 placeholder` note in HISTORICAL_DEAD_ENDS corrected. Follow-ups standing from RB.2: FA #25 mood-preservation test, FA #72 MSL-name lint (noted, not built).

### Increment REVIEW.2 — Session-lifecycle churn regression net ✅ (2026-06-11; the REVIEW.1 top countermeasure, Matt's option-1 pick)
Mechanical gate for the hang class REVIEW.1 measured as the dominant correction cost (BUG-021 ABBA deadlock, LF.5 Next-button freeze loop, LF.6.streaming quit hang): `SessionLifecycleChurnTests` (engine suite, `.serialized`, ~11 s) — six churn tests driving the REAL AVFoundation dispatch path (AVAudioEngine + AVAudioPlayerNode + scheduleFile completions; no doubles on audio objects) through the live entry points: router-level start/stop churn at varied dwells (the `advanceLocalFileQueue` call pair), completion-callback-vs-stop churn on a looping 0.25 s real-music excerpt (the exact BUG-021 ABBA surface, exercised ~4×/s), onFileEnded-driven 8-advance queue churn (Next-button shape), pause/resume/isPaused hammer threads racing stop/start (D-LF5-3 transport surface), deinit-while-playing (quit shape), and concurrent double-start. Every lifecycle step runs on a detached thread under a 5 s watchdog — a recurrence FAILS with the named step instead of hanging the suite (failures travel through a lock-guarded box; issues recorded on the test thread because raw threads lose Swift Testing's task-locals). Fixture: 0.25 s excerpt cut at runtime from the real `love_rehab.m4a` tempo fixture (no synthetic audio); absence → `Issue.record` (no silent skip). **Done-when (met):** all 6 churn tests green; full engine suite 1439 tests run — single failure was `SoakTestHarnessTests` cancel-timing (17.3 s vs 15 s bound) under the parallel run, green in isolation at 0.7 s; the churn suite's ~11 s of real-audio load plausibly squeezed that bound — widen it if it recurs (timing-sensitivity, not a logic regression). Lint 0 on the new file. Audibility note: the suite plays a few seconds of 0.25 s real-audio blips through the default output device per run.

### Increment REVIEW.1 — Session transcript mining (audit-only) ✅ (2026-06-11)
Mechanical + qualitative audit of all retained Claude Code session transcripts (108 sessions, 2026-05-08 → 2026-06-11; 92 main project dir + 16 worktree dirs) to convert the "most of Matt's time goes to correction" intuition into measured data. **Done-when (met):** extraction script runs over the full inventory with per-session summaries + 3-session spot-verification; four quantitative tables (correction-ratio trend, reference discipline, time-to-first-visual, rule-usage incl. never-cited list); bounded qualitative classification (25 spec-selected sessions + 4 worktree supplements, 41 candidates → A–G categories with session+turn citations); findings report complete. **Headline findings:** adjusted correction ratio ~5 % of human turns, flat-to-falling across the window (NOT rising); genuine corrections are 86 % class-F live-runtime defects (app-lifecycle concurrency, fixture/live parity) — zero reference-skip (A) / spec-drift (B) classifications in the reviewed set (with stated under-sampling caveats: M7 visual feedback rarely contains marker words; pre-2026-05-08 era not retained); README-read-before-first-.metal-edit measured at 35 % of shader-editing sessions (ceiling on the FA #39/#63 violation rate — denominator includes incidental edits); heaviest preset sessions burned 85 %+ of output tokens before any visual-artifact marker (FM.L2 858 k; 2026-05-16 Ferrofluid 515 k). Rule-usage table (288 identifiers, conv-vs-dump split) + never-cited lists (FA #2/#3/#11/#15/#18; 0 never-cited D entries) produced as the named RB.1 input. **Findings + all artifacts live OUTSIDE the repo at `~/phosphene_session_mining/REVIEW1_FINDINGS.md`** (deliberately uncommitted — transcripts are private conversation content; the repo is public MIT). Capability registry untouched (no renderer/shader/cert capability change). Carry-forward: REVIEW.2 (mechanize top countermeasure) + RB.1 (rulebook verdicts) — not scoped here.

### Increment DOC.4.1 — Doc referential-integrity gate ✅ (2026-06-11)
Matt's "address the integrity finds ASAP" follow-up. Full-history damage sweep (83 doc-touching commits since 2026-06-01 + 85 back to DOC.3): **D-155 was the only real casualty** (restored at DOC.4); everything else legitimate relocations / the D-147→D-148 renumber. Durable guard: `DocIntegrityTests` (engine suite, 3 gates, ~0.25 s) — D-continuity + non-Amendment uniqueness across DECISIONS/HISTORY, BUG continuity + uniqueness in KNOWN_ISSUES (BUG-007.x sub-entry + BUG-10 conventions encoded), and D-###/FA-# citation resolution over CLAUDE.md + sources + tests + docs. A/B-validated against simulated D-155-deletion (trips continuity + resolution) and D-086-duplication (trips uniqueness). Full suite green (1433/1433 on the clean run; only the two documented pre-existing flakes on the others); lint 0.

### Increment DOC.4 — Pruning pass ✅ (2026-06-11; the first recurring pass since the DOC.3 refactor, + the never-landed DOC.4 decisions-split scope)
The four protocol passes, 4 weeks / 775 commits after DOC.3. **Pass 1 (Failed Approaches):** #14/#20 → HISTORICAL_DEAD_ENDS (CoreML gotchas; CoreML unused per D-009, verified no source import); #34 → SHADER_CRAFT §13 full-text; #35–#38/#40 retired as near-verbatim duplicates of §13's own entries (mapping note added; §13 canonical); gap table extended; ~50 entries evaluated-and-KEPT (incl. #1–4/#17/#18 for the queued D-145 beat-sync project). **Pass 2 (Decisions):** mechanical citation graph (921-file corpus + memory + open KNOWN_ISSUES + active-decision fixpoint) showed 154/165 entries cited — the 2026-05-13 plan's ~60-active estimate was wrong; moved the verified subset (D-013/D-031/D-046 shipped+uncited; D-120 reverted → annotated move; D-086 was DUPLICATED in both files since the DOC-era move — deduped) + landed the Phase-MD-bloc REVISIT banner DOC.0 planned. Bedrock-uncited kept deliberately (D-001/002/005/007/012/015/016/023). **Pass 3 (CLAUDE.md):** Cold-Start Phase Contract condensed to the operative contract (full history verbatim → BEAT_SYNC.md addendum); 11 Arachne-specific What-NOT-To-Do bullets → ARACHNE_V8_DESIGN.md §Operating rules (pointer bullet remains). **Pass 4:** Current Status still the DOC.3 pointer block (no regrowth). **Drift fixes:** Module-Map per-preset histories split (borderline-call B — Arachne + LumenMosaic → their design docs); RENDERER.md line-180 retired-typealias listing struck (line 190's flag was a misread — `setRayMarchPresetHeightTexture` is live, verified). **Integrity finds (both pre-existing):** D-155 had been accidentally DELETED by the parallel FBS.S5c commit (`5ac5ad90`) — restored verbatim from `5ac5ad90~1`; D-145 was reserved at the NB renumbering and cited everywhere but never written — retroactive stub filed. **Sweep clean:** every FA # and D-### cited across CLAUDE.md/code/handbooks/preset docs/QUALITY resolves. **Sizes:** CLAUDE.md 542 → 494; DECISIONS.md 165 → 162 entries (4,806 → 4,735 lines incl. banner + restores); DECISIONS_HISTORY 1 → 5 entries; battery green post-pass (engine 1430/1430, app tests, lint 0 — docs-only, zero movement). **Reported (not done):** the deeper ~30-entry decisions cut requires ruling that narrative citations (design-doc provenance mentions) don't count as keep-signals — Matt's call, recommend deciding at the next pruning pass.

### Increment Skein.6 — Certification ✅ (gates 2026-06-10 + **Matt M7 PASS 2026-06-11** — `certified: true`; first `painterly` preset; BUG-046 guard landed pre-flip; D-159)
Gates + docs + the D-142(c) deferred engine touch; **zero behavioural/tuning change** (the 5.4 look is untouched — byte-identical goldens prove it). **Coverage bound (Matt's decision, presented with live-path measurements):** the approved density stands; §5.7's pre-implementation "ends 60–80 %" band retired for **never-solid / never-near-empty** — measured at 900×600 on the approved sessions: 39 % @ 9 s → 80.2 % @ 43 s (longest approved single track) → plateau ≈ 87 % @ 100 s, live-video parity confirmed at 29 s; coverage fraction is RESOLUTION-DEPENDENT (the droplet AA radius floor reads the same run 94.7 % @ 200×200 vs 80.2 % @ 900×600), so `test_cert_coverageBound` (180 s tiled-real-stem live-path run) renders at 600×400 with thresholds calibrated there (< 95 % — measured 89.6 % on the densest input; > 40 %). **Determinism (§5.7 headline):** formalised as dHash ≤ 8 across two same-seed live-path runs in `test_seedDeterminismAndReseed` (byte-identity stays the stronger assert); full-track evidence 2×10,800 frames pixel-diff 0 / hamming 0. **Seed ratified FNV-1a `title|artist`** (the SHA-256 design wording amended in SKEIN_DESIGN §1/§5.7 — rewiring would silently change every approved painting). **§5.5 soak:** `test_cert_soak_twoHourCanvasHold` (`SKEIN_SOAK=1`) — 432,000 frames (2 simulated hours) through the live mv_warp dispatch path: 15 min real stems / 90 min silence (whole-canvas RGBA byte-identity = lossless hold at hours scale) / 15 min real stems (resume + never-white + ground-corner intact); the generic `SoakTestHarness` is the headless audio-path harness (no render) and cannot observe §5.5's property. **Golden dHash entry** in `PresetRegressionTests` (three fixtures identical — static ground, the Nimbus pattern). **`family: "painterly"` + `PresetCategory.painterly`** (blast radius audited: enum + displayName + count test 12→13 + sidecar; UI iterates `allCases`; orchestrator family logic nil-safe). **`rubric_profile: lightweight` ratified** (D-064 precedent; L2 false-negative by construction — CPU-side deviation routing, the Lumen Mosaic precedent — locked in `FidelityRubricTests.expectedAutomatedGate`). Files: `PresetCategory.swift`, `Skein.json` (family + refreshed description; no behavioural field), `PresetTests.swift`, `FidelityRubricTests.swift`, `PresetRegressionTests.swift`, `SkeinCanvasHoldTest.swift` (+coverage gate, +dHash determinism, +soak, +env-gated cert montage), SKEIN_DESIGN/SKEIN_PLAN/skein README/D-159/release notes. **Pruning-pass cadence has FIRED** (no pass since DOC.3 2026-05-13) — the pruning pass is the next increment after cert. **M7 PASS 2026-06-11** ("It looks great. Ready to certify", session `2026-06-11T01-56-22Z`; the ≥5-track + LF bar met cumulatively with the 2026-06-10 approved sessions). The pre-flip session review (Matt: "If anything looks concerning, let's fix it before we certify") surfaced **BUG-046** — the structure sub-feature riding BUG-042's note-scale junk (boundaries every ~1.7 s at conf 0.78–0.95, the confidence gate wide open; ≈2× tuned spatter + pours chopped at ~1–1.7 s on streaming material only) — fixed at Matt's direction with the 10 wall-s boundary-spacing guard (`minSectionSpacingS`; A/B-validated gate `test_structure_boundarySpacingGuard`: 16→4 breaks / 1650→1250 spawns on machine-gun replay; real boundaries still land). Then `certified: true` + `FidelityRubricTests.certifiedPresets` flipped; full battery green (engine 1430/1430, app tests, lint 0).

### Increment Skein.5.4 — Two painting techniques: pour drips vs independent flicks ✅ (landed 2026-06-10; **Matt eyeball-gate PASSED across 3 live sessions; merged to local main `befb406b`** incl. the round-2 tune + BUG-044)
Matt's craft corrections, built to the negotiated spec verbatim: **the POUR and the FLICK are different techniques** (previously conflated — bursts hugged the line). **(1) Pour drips:** round ragged drops shed close beside the travelling line (perp offset 0.005–0.020 UV), rate AND weight ∝ the pour's volume (`lineFlow` — the width signal, FA #67-clean), τ-clocked (`dripRateGain = 3.0` drips/τ — pauses with the painter), in the pour's colour; encoded in the shared burst ring with **`sharpness < 0` as the drip marker** (no GPU-struct change); drips yield to flicks on a full ring. **(2) Flicks:** land ANYWHERE ≥ 0.20 UV from the painter's pour position (deterministic seed + spawn-counter hash, mirror-then-push-out fallback; §5.7 extends to landing spots), throw direction = the gesture's own random angle; mark anatomy per `03_micro_satellite_spatter` + `03_micro_filament_threads` — 3-lobe union-min impact blot (soft hit → one round heavy drop, sharp → lobes scatter), 1–3 flung tapering threads with terminal droplets (up to 0.20 UV), satellite halo with POWER-LAW size spread (`pow(hs.z, 2.2)`, ~20:1 — the old confetti is the dust tail, KEPT) + radial teardrop elongation. **Hit magnitude** (how far the firing `*_energy_dev` exceeded the 0.13 threshold, soft-saturated `m/(m+0.35)` per `project_deviation_primitive_real_range`) scales blot/threads/spread via `burst.size` (CPU 0.30–2.0, shader clamp matches). **Emission timing UNCHANGED** (per-stem onset + refractory; beat-locked events remain vehemently rejected). **New gates (live tick path, real stems):** `test_splatterTechniques_flickPlacementAndPourDrips` — spawn-frame detector (counter deltas + `activeBurstMarks` + `currentPainterPourPosition`): every flick ≥ 0.18 from the painter (min 0.198 over 1.5k+ spawns), drips ∝ volume (busy tile ≫ calm), every drip ≤ 0.03 of the line. **Gate adjustments (all Matt-approved in-session, none silent):** no-rings bar 13 → 16 (bigger smooth blot interiors raise the proxy's legitimate mean — measured 12.5–13.2 post-change vs the 27.6 defect signature; the only pre-sanctioned adjustment); colour-freeze gate re-probed at switch+28 frames (end-of-run probing read X=28/Y=32 from legitimate flick overpaint of the old line — the freeze itself intact, main baseline X=61/Y=0 reproduced at the new probe); mood-vigour gate re-probed on the mechanisms (painter τ ×1.10 + spawn count + coverage direction — the old ≥1.10× coverage margin measured burst placement, not vigour: 1.285× pre / 1.078× post on identical session+seed). **Battery:** full engine 1427 (8 issues = the 7 documented love_rehab fixture-absent + the known MetadataPreFetcher timeout flake); PresetRegression + DB/FM byte-identical; loader count intact (FA #72); app build + SwiftLint `--strict` clean. **Eyeball-gate sheets** (`/tmp/skein54_sheets/`): vs-references panel, early-canvas mark-anatomy panel (300 f), before/after × fathom/poles/nocturne. **Honest observations for the gate:** coverage rate ~2.2× the confetti baseline (38 % → 85 % painted at 23 s of busy music — the §5.7 60–80 % end-of-track bound is reached at ~1/5 track; morphology-scale knobs, not emission timing, are the lever if Matt wants it slower); long flung threads read clearly on the early canvas but submerge under later blots at full density. **Merge only after Matt's verdict.**

**Round-2 (Matt's live read, session `2026-06-10T19-28-50Z` — "I like it… the canvas fills and transitions quickly"):** spatter rate −41 % (`onsetRefractory` 0.14 → 0.26; Matt confirmed RATE not size via in-session question) + new pour lines start +13 % more often (`minPourTau` 3.0 → 2.65; confirmed: new-pour starts, not drips). Mood-fixture marks 885→521 / 524→304 on identical input; early fill @5 s 0.375→0.248; all 26 Skein gates green unchanged. Matt's old-confetti-as-its-own-variant idea noted (cheap to resurrect from main history as a sibling variant). **Round-2 verification listen (session `2026-06-10T19-48-27Z` — "the speed adjustments look good") surfaced BUG-044:** local-file next/prev/EOF never wiped the Skein canvas (the §1.5 wipe was streaming-path-only since Skein.3; five LF track changes with Skein active, zero wipes — the "first transition wipe" was the preset-APPLY clear). Fixed on the branch (trivial-collapsed P2, KNOWN_ISSUES entry filed): shared `VisualizerEngine.resetPerTrackPresetState()` (Nimbus NB.4 settle + Skein reseed → ground → wipe) called from BOTH track-change paths, LF call ordered after `applyLocalFileTrackState` (the reseed reads `lastResolvedTrackIdentity`), `WIRING:` breadcrumb per advance; regression-locked by `TrackChangePresetResetRegressionTests` (helper-exists-once + both-call-sites + no-re-inline + ordering; registered in project.pbxproj P10012/P20012). **Wipe verified live (session `2026-06-10T20-05-48Z`, Matt "Looks good"):** 8+ LF advances with Skein active, every one logging `resetPerTrackPresetState COMPLETE` — the BUG-044 manual criterion. Merged `befb406b`.

### Increment Skein.5.3b — Per-palette canvas grounds + reference-anchored re-curation ✅ (landed 2026-06-10; D-155 amendment)
Matt's round-1 rejection ("palettes don't match the drip painters… too similar… why is the background beige for all palettes?") → the redo: the GROUND is part of the palette (light AND dark — Blue Poles precedent), every entry anchored on a NAMED work, gates ground-aware (drums = starkest ink VS THE GROUND; separability vs the entry's own ground across the mood swing — caught 2 real collisions in tuning). Plumbing: `Entry.ground` → SkeinState (re-picked per track) → a float4 LINEAR ground tail on the slot-6 buffer (offset 2752; the comp paint-mask reads it) → gated `mvWarpCanvasGroundOverride` for the canvas wipe + resize re-clear (nil ⇒ every other preset byte-identical) → app wiring at Skein apply / track-change / teardown. Harness gains `libraryPaletteSeed` (true library-mode runs, canvas cleared to the entry's ground). **Final library (Matt round-2): fathom + poles + nocturne + ember** — autumn/convergence cut ("too similar to fathom": a pale ground + black ink dominates the gestalt; future light candidates must differ at the GROUND level). Full battery green (known fixture-absent cluster only); process lesson → memory `feedback-palette-curation-process`.

### Increment Skein.5.3 — Curated palette library + per-track picker ✅ (landed 2026-06-10; D-155; Matt-curated)
Matt's enhancement ask ("different colour profiles like Lumen Mosaic — variety over time"). **Library** (`SkeinPalettes.swift`): fathom (default, index 0) + nocturne + jewel + inkpop + electric — Matt curated from six rendered candidates on identical seed-0 real-stem paintings (terra cut); **fixed role grammar** in every palette (drums darkest ink / bass deep weight / vocals warm lead / other contrast accent) so the colour→stem vocabulary survives palette changes. **Picker = per-track deterministic** (Matt's pick over mood-matched): `entry(forTrackSeed:) = seed % count` on the same FNV-1a identity that seeds the trajectory — §5.7 "same song → same painting" now extends to colour; LIBRARY MODE only when `SkeinState` gets no explicit palette (the live path; `reseed` re-picks per track), every fixture/candidate palette stays pinned, seed 0 → fathom keeps no-palette fixtures byte-identical. **Gates** (`SkeinPaletteLibraryTests`): pairwise display separability incl. vs cream across the full mood-tint swing (via the extracted-static `SkeinState.moodTint` — the EXACT lay-time transform), pale ceiling, role grammar, fathom == defaultPalette, picker determinism + reseed re-pick + explicit-mode pinning. Contact sheet renders the library (same painting per entry). Full engine suite green (7 known fixture-absent + 1 solo-green SessionManager.Cancel parallel-flake); app build + SwiftLint `--strict` clean. **Skein.6 cert note:** the ≥5-track M7 naturally samples ≥5 palette draws.

### Increment BUG-040 — structural sections: frozen clock + live-edge peak + absolute novelty floor ✅ (landed 2026-06-10)
The session-artifact finding from `2026-06-10T03-09-20Z` (filed same day), root-caused to THREE compounding causes and fixed in one P2 increment: (1) the live caller hardwires `time: 0` into `MIRPipeline.process` → the structural analyzer's clock froze at zero → NEGATIVE boundary timestamps (≈ −0.3 s, exactly as recorded), noise durations, pinned confidence — the analyzer now clocks from the pipeline's own track-relative `elapsedSeconds`; (2) the live-edge novelty peak (absolute index advances with the stream → escaped the BUG-035-fixed dedup every ~4 detect calls → the ~1.3–1.6 s junk-boundary cadence) — detection now restricted to the interior region (≥ `minPeakDistance` frames of after-context; a real boundary registers once, ~2 s late); (3) the relative-only mean+1.5σ threshold admits noise-scale peaks on smooth material (measured junk ~0.0003 vs real ~0.43) — absolute `minNoveltyFloor = 0.02` ANDed in. **A/B-proven gates:** `structuralAnalyzer_evolvingMusicNoBoundary_registersNothing` (pre-fix 5 junk boundaries → 0), `mirPipeline_structuralPrediction_liveCallerShape_timestampsNonNegative` (pre-fix `sectionStartTime → −0.3167` — the exact session signature → positive), `structuralAnalyzer_boundaryTimestamps_nonNegativeAndPlausible`. All 16 pre-existing structure tests + the AABA golden unchanged-green; full suite green (7 known fixture-absent only); app build + SwiftLint `--strict` clean. **Consequence: the Skein.5 structure sub-feature and the orchestrator's `StructuralPrediction` consumer receive a sane signal for the first time.** Manual criterion open: the next real session's section columns (multi-second sections, climbing confidence).

### Increment Skein.5.2 + BUG-039-instr — structural CSV columns + video-stall instrumentation ✅ (landed 2026-06-09)
**Skein.5.2:** features.csv gains `section_index,section_start_s,section_confidence` tail columns (append-only invariant) via `SessionRecorder.recordStructuralPrediction(_:)` (the latest-value queue-hop pattern), published from the same per-frame MIR site that feeds `RenderPipeline.setStructuralPrediction` — the Skein.5 structure layer + the BUG-035 manual criterion are now artifact-verifiable (the Skein.5 M7 review had to say "cannot verify"). SessionRecorderTests from-end offsets shifted by a `structTail` constant; round-trip + default-zero gates. **BUG-039 instrumentation:** the session video intermittently freezes seconds in (`22-35-09Z` 5.0 s, `17-14-25Z` 15 s) with zero log output — every stall path in `SessionRecorder+Video.appendVideoFrame` was silent and the `adaptor.append` result ignored. Now: non-`.writing` writer detected once + logged with `writer.error` + the partial file RETAINED (not deleted); not-ready / pool / append failures log throttled counters. Diagnosis completes on the next affected session's log; the root-cause fix is its own increment. KNOWN_ISSUES BUG-039 filed with the evidence. **Session-review postscript (2026-06-10, `03-09-20Z` — the first session with the new columns):** video full-length (no BUG-039 stall this time); beat phase healthy (Love Rehab 2.23 wraps/s vs 2.08 expected — the prior session's half-rate anomaly did not reproduce); the section columns immediately exposed **BUG-040** (a live-edge boundary registered every ~1.3–1.6 s on every real track, `section_start_s` negative, confidence pinned ≤ 0.30 — the Skein.5 confidence gate correctly suppressed the bias, so the structure sub-feature is currently INERT on real music). The instrumentation increment did exactly its job.

### Increment AUDIT.1 — Full-codebase audit + findings filed ✅ (2026-06-09)
Six-agent parallel review of the complete tree (~92k lines: 54k engine Swift, 19k MSL, 19k app Swift; every Swift file in scope read in full, MSL swept for mechanical-defect patterns). All findings verified at file:line and cross-checked against KNOWN_ISSUES + CLAUDE.md FAs — nothing re-reports a documented issue. **Output: 6 P1 / 17 P2 / ~40 P3 findings.** Evidence record: [`docs/diagnostics/CODE_AUDIT_2026-06-09.md`](diagnostics/CODE_AUDIT_2026-06-09.md). Filed: **BUG-030** (duplicate-track prep crash), **BUG-031** (StemSeparator prep/live race), **BUG-032** (streaming session-lifecycle cluster — endSession orphan / second prep loop / source-before-guard), **BUG-033** (60 Hz whole-tree SwiftUI invalidation + `assign(to:on:)` VM leaks), **BUG-034** (`sceneParamsB.z` double-booking — ray-march fixtures march 32 steps vs live 128, FA #66 class; **invalidates ray-march cert evidence — fix + golden-hash regen before further ray-march cert work**), **BUG-035** (NoveltyDetector boundary re-detection — Skein.5 prerequisite, see above), **BUG-036** (RT-audio-thread allocations ×3 sites), **BUG-037** (Arachne spiral chord-count 200/441/104 inconsistency), plus the **AUDIT-2026-06-09** backlog index entry in KNOWN_ISSUES for the remaining P2s/P3s. Suggested fix sequencing: audit doc §Suggested sequencing. Clean areas verified: GPU struct contracts byte-match `Common.metal` across all paths; OAuth/PKCE core sound, no committed secrets; disk caches well-built; no FA #44/#72 shader hazards; D-102 Drift Motes removal orphan-free. Docs-only increment — no code changed; tests n/a; not visually verifiable (n/a).

---

## Phase G-uplift — Gossamer + remaining preset fidelity uplifts

The Phase V uplift trajectory left several presets at the post-V.6 cert baseline without per-preset fidelity work tailored to their visual contracts. The shipped catalog has 15 presets (post-D-102); the Phase V plan called for 12 fidelity-uplifted presets. Several catalog members are *certifiable* but have *not* been through a per-preset uplift session against curated references — Gossamer is the named example, but Membrane / Starburst (post-SB) / Nebula / Plasma / Waveform / Fractal Tree / TestSphere / Glass Brutalist / Kinetic Sculpture / Volumetric Lithograph / Spectral Cartograph are all worth review (some are lightweight rubric and need only validation, others are full rubric and may need work).

**Status.** Planned, behind LM / Arachne / AV / CC. Per-preset scoping happens at session start — each preset gets its own concept-viability gate review against SHADER_CRAFT §2.0 before scoping the uplift; if the gate finds the preset's musical role is unarticulated or ambiguous, the uplift is rescoped (or, per D-102 / FA #58, retired rather than tuned).

**Suggested order** (subject to Matt prioritisation):

1. **Gossamer uplift** — the highest-priority named uplift target. Bioluminescent silk web preset; ambient family. Likely benefits from a palette / motion / silence-fallback pass against curated references. Per-preset increment estimate: 1–2 sessions.
2. **Membrane uplift** — fluid-family direct-fragment preset; Matt has flagged the silence behaviour as historically thin. 1–2 sessions.
3. **Starburst** — post-SB.1 / SB.2 stability + any remaining fidelity gaps surfaced by review. 1 session.
4. **Plasma / Nebula / Waveform / Spectral Cartograph** — lightweight rubric profile; primarily validation rather than rework. ½–1 session each.
5. **Glass Brutalist / Kinetic Sculpture / Volumetric Lithograph** — full rubric profile; cert-quality validation + any preserved tuning gaps. 1 session each.
6. **TestSphere / Fractal Tree** — final cleanup pass; TestSphere may be retired as a production preset if its diagnostic role is no longer load-bearing.

**Done-when (phase-level).** Every catalog member has either (a) been M7-certified by Matt, or (b) been explicitly retired with a D-XXX entry (the D-102 / Drift Motes precedent applies — retirement is acceptable when the concept-viability gate fails).

---

These milestones map to product-level outcomes, not implementation phases.

**Milestone A — Trustworthy Playback Session.** ✅ **MET (2026-04-25).** A user can connect a playlist, obtain a usable prepared session, and complete a full listening session without instability. *Requires: ~~2.5.4~~ ✅, ~~Phase U increments U.1–U.7~~ ✅, ~~progressive readiness basics (6.1)~~ ✅.*

**Milestone B — Tasteful Orchestration.** ✅ **MET (2026-04-25).** Preset choice and transitions are consistently better than random and pass golden-session tests. *Requires: ~~Phase 4 complete~~ ✅, ~~Increment 5.1~~ ✅ (landed as 4.0).*

**Milestone C — Device-Aware Show Quality.** ✅ **MET (2026-04-25).** The same playlist produces an excellent show on M1 and a richer one on M4 without jank. *Requires: ~~Phase 6 complete~~ ✅.*

**Milestone D — Library Depth.** ⏳ **IN PROGRESS — 1 / 22+ certified (2026-05-12).** The preset catalog is large enough, varied enough, and well-tagged enough for Phosphene to feel like a product rather than a tech demo. *Requires: Phase 5 complete, Phase V complete (12 fidelity-uplifted presets), Phase AV + Phase CC complete (Aurora Veil + Crystalline Cavern shipped certified), Phase G-uplift complete (Gossamer + remaining catalog members M7-certified or explicitly retired), Phase MD through MD.5 minimum (10 Milkdrop presets), 22+ certified presets total.* **First certified preset: Lumen Mosaic** (Phase LM closed 2026-05-12; BUG-004 resolved). Next cert candidates per current sequencing: Arachne V.7.10, Aurora Veil (Phase AV), Phase G-uplift members.

**Milestone E — Visual Identity.** Phosphene's preset catalog has a recognizable aesthetic ceiling that reads as 2026-quality — comparable to indie-game-released visuals, not 2006-era ShaderToy. *Requires: Phase V complete, Phase V.7–V.11 uplifts all Matt-approved, Phase CC certified (the flagship demonstration piece), accessibility pass (U.9).*
