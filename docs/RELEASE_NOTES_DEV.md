# Phosphene — Developer Release Notes

Internal release notes for the `main` branch. Audience: Matt and Claude Code. Each entry covers one session or a logical batch of increments. These notes complement `docs/ENGINEERING_PLAN.md` (authoritative for what's planned) and `docs/QUALITY/KNOWN_ISSUES.md` (authoritative for open defects).

User-visible release notes are not yet in scope (no public build).

---

## [dev-2026-05-06-b] BUG-006.2 — Prepared-BeatGrid wiring fix

**Increments:** BUG-006.1 (instrumentation, prior commit), BUG-006.2 (fix)
**Type:** P1 defect fix (`dsp.beat` / `pipeline-wiring`)

**Fixed:**
- **Cause 1 — engine.stemCache never assigned.** `VisualizerEngine.swift:171` declared `var stemCache: StemCache?` but no code in the codebase ever assigned to it. Every `resetStemPipeline(for:)` call therefore took the cache-miss branch and the prepared `BeatGrid` never installed. Now wired in `init` to `sessionManager.cache` (the same `StemCache` instance `SessionPreparer` populates) — entries become visible by reference as preparation completes.
- **Cause 2 — Track-change handler built a partial `TrackIdentity`.** `VisualizerEngine+Capture.swift:129` constructed `TrackIdentity(title:, artist:)` only — duration, catalog IDs, and `spotifyPreviewURL` left nil. `Hashable` therefore mismatched the keys `SessionPreparer` stored from full Spotify-API identities. Now resolves the canonical identity from `livePlan` via the new `PlannedSession.canonicalIdentity(matchingTitle:artist:)` helper. Falls back to the partial identity for ad-hoc/reactive sessions and ambiguous matches.

**New tests:**
- `Tests/Integration/PreparedBeatGridAppLayerWiringTests.swift` (6 cases) — closes the BUG-003 coverage gap that allowed BUG-006 to ship. Tests cover `engineStemCache_isWiredAfterSessionPrepare`, `trackChangeIdentity_matchesPlannedIdentity`, `ambiguousMatch_returnsNil_partialFallback`, `noMatch_returnsNil`, `endToEndProduces_preparedCacheInstall`, `partialIdentity_withoutCanonicalResolution_missesCache` (negative control pinning the regression direction).

**Files added:**
- `PhospheneApp/VisualizerEngine+TrackIdentityResolution.swift` — `canonicalTrackIdentity(matching:)` instance method delegating to the Orchestrator-module pure helper.
- `PhospheneEngine/Tests/PhospheneEngineTests/Integration/PreparedBeatGridAppLayerWiringTests.swift`.

**Files changed:**
- `PhospheneApp/VisualizerEngine.swift` — assigns `self.stemCache = self.sessionManager.cache` after `makeSessionManager`.
- `PhospheneApp/VisualizerEngine+Capture.swift` — track-change handler resolves canonical identity before `resetStemPipeline`.
- `PhospheneApp/VisualizerEngine+WiringLogs.swift` — `logTrackChangeObserved` now reports `resolution=fromLivePlan|partialFallback`.
- `PhospheneEngine/Sources/Orchestrator/PlannedSession.swift` — `canonicalIdentity(matchingTitle:artist:)` pure-function helper added.
- `PhospheneApp.xcodeproj/project.pbxproj` — registered `VisualizerEngine+TrackIdentityResolution.swift` (N10007 / N20007).

**Tests:** 1051 engine tests / 116 suites. Pass except the two documented baseline flakes (`MetadataPreFetcher.fetch_networkTimeout`, `MemoryReporter.residentBytes growth`). App build clean. SwiftLint baseline preserved on touched files (zero new violations).

**Manual validation:** Pending the next live Spotify capture. The BUG-006.1 `WIRING:` instrumentation logs will surface end-to-end behaviour in `session.log`. Verification criteria from the BUG-006 entry remain unchecked until a live session is captured (SpectralCartograph mode label, drift readout settling, `grid_bpm` column in `features.csv`).

**Known issues introduced:** None.
**Known issues resolved:** BUG-006 (code-only — manual sign-off pending). BUG-003's first verification criterion checked off (`PreparedBeatGridAppLayerWiringTests`); LiveDriftValidationTests still pending.

**Related:** BUG-006, BUG-003, BUG-006.1, DSP.3.6, D-070 (`TrackIdentity.spotifyPreviewURL` excluded from `Hashable`).

---

## [dev-2026-05-06-a] BUG-006.1 — Wiring instrumentation

**Increments:** BUG-006.1
**Type:** Instrumentation (no behaviour change)

Source-tagged `WIRING:` log entries added across the prepared-BeatGrid path so a live session capture surfaces the failure mode end-to-end. Optional `SessionRecorder` threaded through `SessionPreparer` and `SessionManager` so logs land in `session.log`. New file `PhospheneApp/VisualizerEngine+WiringLogs.swift` consolidates helpers; `SessionManager+Readiness.swift` extracted to keep `SessionManager.swift` under the SwiftLint 400-line gate. New `caller:` parameter on `resetStemPipeline(for:caller:)` discriminates pre-fire (planner) from track-change paths. Commits `7f95cec0` + `807d3b8c`.

---

## [dev-2026-05-05-c] Quality System Documentation

**Increments:** QS.1
**Type:** Infrastructure / documentation

**New:**
- `docs/QUALITY/DEFECT_TAXONOMY.md` — severity definitions (P0–P3), domain tags, failure classes, and defect process.
- `docs/QUALITY/BUG_REPORT_TEMPLATE.md` — structured template for filing defects with required fields.
- `docs/QUALITY/KNOWN_ISSUES.md` — active issue tracker: 5 open defects (BUG-001 through BUG-005), 5 pre-existing flakes, and 5 recently-resolved P1 defects from DSP.3.x work.
- `docs/QUALITY/RELEASE_CHECKLIST.md` — 10-section pre-release gate covering build, DSP/beat-sync, stem routing, preset fidelity, render pipeline, session/UX, performance, documentation, and git hygiene.
- `docs/RELEASE_NOTES_DEV.md` — this file.

**Changed:**
- `CLAUDE.md` — new `Defect Handling Protocol` section added after `Increment Completion Protocol`.
- `docs/ENGINEERING_PLAN.md` — QS.1 increment added and marked complete.

**Known issues introduced:** None.
**Known issues resolved:** None (documentation only).

---

## [dev-2026-05-05-b] DSP.3.5 + V.7.7A

**Increments:** DSP.3.5, V.7.7A
**Type:** DSP fix + preset architecture

**DSP.3.5 — Halving octave correction + retry:**
- `BeatGrid.halvingOctaveCorrected()` added: halves BPM > 160 recursively, drops every other beat, re-snaps downbeats, recomputes `beatsPerBar`. BPM < 80 unchanged (Pyramid Song guard).
- Live Beat This! retry gate: `liveBeatAnalysisAttempts: Int` (was Bool), max 2 attempts — first at 10 s, retry at 20 s on empty grid.
- `performLiveBeatInference()` extracted for SwiftLint compliance.
- 4 new `BeatGridUnitTests`. **1032 engine tests.**
- Post-validation triage: `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md`.

**V.7.7A — Arachne staged-composition scaffold migration:**
- Arachne migrated from `passes: ["mv_warp"]` to V.ENGINE.1 staged scaffold.
- New fragment functions: `arachne_world_fragment` (placeholder forest backdrop) + `arachne_composite_fragment` (placeholder 12-spoke web overlay).
- Mv-warp helpers removed (incompatible with staged preamble).
- Legacy `arachne_fragment` retained as v5/v7/v9 reference.
- `Arachne.json` updated: `passes: ["staged"]` with two stage definitions.

**Known issues introduced:**
- BUG-002 (PresetVisualReviewTests PNG export broken for staged presets) — pre-existing harness bug exposed by V.7.7A.

**Known issues resolved:**
- BUG-R004 (double-time BPM on 10-second window) — resolved by DSP.3.5 octave correction.

---

## [dev-2026-05-05-a] DSP.3.1–3.4 + V.7.7

**Increments:** DSP.3.1, DSP.3.2, DSP.3.3, DSP.3.4, V.7.7
**Type:** DSP fixes + preset content

**DSP.3.1+3.2 — Diagnostic hold + session-mode signal + pre-fire BeatGrid:**
- `diagnosticPresetLocked` flag, `L` shortcut.
- `SpectralHistoryBuffer[2420]` session-mode slot (0–3).
- SpectralCartograph mode labels: ○ REACTIVE / ◐ PLANNED·UNLOCKED / ◑ PLANNED·LOCKING / ● PLANNED·LOCKED.
- `_buildPlan()` pre-fires BeatGrid.

**DSP.3.3 — Beat sync observability:**
- `SpectralCartographText.draw()` extended with beat-in-bar, drift, phase-offset readouts.
- `textOverlayCallback` now passes `FeatureVector` per frame.
- `[`/`]` developer shortcuts for ±10 ms visual phase calibration.
- `BeatSyncSnapshot` struct (9-field).
- `SessionRecorder.features.csv` gains 9 beat-sync columns.
- `SpectralHistoryBuffer[2421..2429]` downbeat_times + drift_ms slots.
- 31 new tests. **1018 engine tests.**

**DSP.3.4 — Three root causes fixed blocking PLANNED·LOCKED:**
- Bug 1: `BeatGrid.offsetBy` now extrapolates to 300-second horizon.
- Bug 2: `VisualizerEngine.tapSampleRate` stored from audio callback; passed to Beat This!.
- Bug 3: `StemSampleBuffer.snapshotLatest(seconds:sampleRate:)` overload uses actual tap rate.
- 14 new tests. **1028 engine tests.**

**V.7.7 — Arachne WORLD pillar + background dewy webs:**
- Six-layer `drawWorld()` Metal function: sky gradient, distant + near trees, forest floor, atmosphere.
- Snell's-law refractive drops on two background hub webs.
- `ArachneState._tick()` gains `smoothedValence`/`smoothedArousal` (5s low-pass) for mood palette.
- `WebGPU` struct extended with Row 4 `moodData: SIMD4<Float>` (64 → 80 bytes).
- Golden hashes regenerated.

**Known issues resolved:**
- BUG-R001 (BeatGrid finite horizon) — resolved by DSP.3.4.
- BUG-R002 (hardcoded 44100 Hz sample rate) — resolved by DSP.3.4.
- BUG-R003 (StemSampleBuffer undersized at 48000 Hz) — resolved by DSP.3.4.

---

## [dev-2026-05-05] DSP.2 Complete + DSP.3 Audit

**Increments:** DSP.2 S3–S9, DSP.2 hardening, DSP.3 audit
**Type:** DSP — Beat This! transformer + drift tracker

**Summary:** Full Beat This! small0 transformer implemented in Swift/MPSGraph. BeatGrid pipeline end-to-end from Spotify-prepared sessions. Live reactive mode gets Beat This! inference after 10 s of playback. `barPhase01`/`beatsPerBar` propagated to FeatureVector and GPU.

**Bug fixes landed:**
- Four S8 bugs: norm-after-conv shape, transpose-before-reshape, BN1d zero-padding semantics, paired-adjacent RoPE. All individually regression-locked in `BeatThisBugRegressionTests`.
- DSP.3 audit revealed three root causes blocking LOCKED state (fixed in DSP.3.4, see above entry).

**Test suite:** 1028 engine tests / 106 suites at DSP.3.4.

**Known issues introduced:**
- BUG-001 (Money 7/4 stays REACTIVE on live path) — identified during DSP.3.5 post-validation.

---

## [dev-2026-05-04] DSP.2 S1–S2 + DSP.1

**Increments:** DSP.1, DSP.2 S1, DSP.2 S2
**Type:** DSP — tempo estimation rewrite + Beat This! vendoring

**DSP.1 — Sub_bass-only IOI + trimmed-mean BPM:**
- Eliminated band-fusion IOI bias (Failed Approach #50) and histogram-mode bias (Failed Approach #51).
- BPM error dropped from 10–20% to <2% on kick-on-the-beat tracks.
- Reference results: love_rehab 122–126 (true 125), so_what 135–138 (true 136).
- `TempoDumpRunner` CLI + `Scripts/dump_tempo_baselines.sh` + `Scripts/analyze_tempo_baselines.py` shipped as permanent regression infrastructure.

**DSP.2 S1 — Beat This! architecture audit + weight vendoring:**
- `small0` model selected: 2,101,352 params, 8.4 MB FP32, MIT license confirmed.
- 161 weight tensors vendored under Git LFS.
- Six JSON reference fixtures (love_rehab, so_what, there_there, pyramid_song, money, if_i_were_with_her_now).

**DSP.2 S2 — BeatThisPreprocessor Swift port:**
- Mono Float32 → log-mel spectrogram matching Beat This! Python `LogMelSpect` exactly.
- Critical: Slaney mel filterbank with continuous Hz interpolation (integer-bin approach underestimates ~12%).
- Golden match on love_rehab first 10 frames: max|Δ| = 2.9×10⁻⁵.

---

## [dev-2026-05-02] V.7.5, V.7.6.C, V.7.6.D, V.7.6.1, V.7.6.2

**Increments:** V.7.5, V.7.6.C, V.7.6.D, V.7.6.1, V.7.6.2

**V.7.5 — Arachne v5 (composition + warm restoration + drops + spider cleanup):**
- Pool capped 12→4, drops as visual hero (radius 8 px), Marschner TRT-lobe warm rim restored, warm key / cool ambient.
- Spider: dark silhouette, AR gate restored, `subBassThreshold` 0.65→0.30.
- M7 review result: output matches `10_anti_neon_stylized_glow.jpg` anti-reference. `certified` rolled back to false. V.7.6 (atmosphere-as-mist patch) abandoned in favour of compositing-anchored V.7.7+.

**V.7.6.1 — Visual feedback harness:**
- `PresetVisualReviewTests` renders presets at 1920×1280 for three FeatureVector fixtures.
- Contact sheet: render in top half, refs 01/04/05/08 in bottom half.
- Gated behind `RENDER_VISUAL=1`.

**V.7.6.C — maxDuration calibration + diagnostic class:**
- Per-section linger factors inverted to Option B.
- `is_diagnostic` JSON field (→ `maxDuration = .infinity`); SpectralCartograph flagged.

**V.7.6.D — Diagnostic preset orchestrator exclusion:**
- `DefaultPresetScorer` excludes `is_diagnostic` presets categorically.
- `DefaultLiveAdapter` no-ops mood override for diagnostic presets.
- `DefaultReactiveOrchestrator` skips diagnostic presets in ranking.

**Known issues introduced:**
- BUG-004 (all presets `certified: false`) — documented; V.7.10 is the planned resolution path.

---

## [dev-2026-04-25] Milestones A, B, C

**Increments:** U.1–U.11, 4.0–4.6, 5.2–5.3, 6.1–6.3, 7.1–7.2, V.1–V.6, MV-0–MV-3
**Type:** Multi-phase milestone delivery

Milestones A (Trustworthy Playback), B (Tasteful Orchestration), and C (Device-Aware Show Quality) all met on 2026-04-25.

**Highlights:**
- Full session lifecycle (idle → connecting → preparing → ready → playing → ended).
- Apple Music + Spotify OAuth connectors.
- Progressive session readiness (partial-ready CTA).
- Orchestrator: PresetScorer, TransitionPolicy, SessionPlanner, LiveAdapter, ReactiveOrchestrator.
- Frame budget governor + ML dispatch scheduler.
- V.1–V.3 shader utility library (Noise, PBR, Geometry, Volume, Texture, Color, Materials).
- V.6 fidelity rubric + certification pipeline.
- Phase U: permission onboarding, connector picker, preparation UI, playback chrome, settings panel, error taxonomy, toast system, accessibility.
- Beat This! architecture committed (DSP.2 scope).

**Known issues at milestone:**
- All presets uncertified (BUG-004).
- Spotify preview_url null for some tracks (BUG-005).
- Test suite: 4 pre-existing Apple Music environment failures (unchanged).
