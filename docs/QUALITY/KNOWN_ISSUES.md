# Phosphene — Known Issues

Open and recently-resolved defects. Filed using `BUG_REPORT_TEMPLATE.md`. See `DEFECT_TAXONOMY.md` for severity definitions and process.

---

## Open

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

### BUG-002 — PresetVisualReviewTests PNG export broken for staged presets

**Severity:** P2
**Domain tag:** preset.fidelity
**Status:** Open
**Introduced:** V.7.7A (staged-composition scaffold)
**Resolved:** —

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
- [ ] `RENDER_VISUAL=1 swift test --filter PresetVisualReviewTests` produces at least one PNG per stage for Arachne without `cgImageFailed`.
- [ ] Contact sheet shows WORLD stage and COMPOSITE stage as separate tiles.

**Fix scope:** Change `Bundle.module` → `Bundle(for: PresetLoader.self)` in `makeBGRAPipeline`. Small, contained change. Required before V.7.7B's harness contact-sheet review.

**Related:** V.7.7A, D-072

---

### BUG-003 — DSP.3.6 / DSP.3.7 tests not yet implemented

**Severity:** P3
**Domain tag:** dsp.beat
**Status:** Open
**Introduced:** DSP.3 planning (gap in coverage)
**Resolved:** —

**Expected behavior:** App-layer wiring integration test verifies the full chain `SessionPreparer.prepare() → StemCache.store() → resetStemPipeline(for:) → mirPipeline.liveDriftTracker.hasGrid == true`. Live drift validation replay test verifies LOCKED within 5 s, drift < 50 ms, and beat phase zero-crossings within ±30 ms on Love Rehab.

**Actual behavior:** These tests do not exist. The wiring is tested indirectly via DSP.2 S6 integration tests, but the app-layer chain from session preparation through to drift tracker activation is not explicitly asserted.

**Minimum reproducer:** Review `docs/ENGINEERING_PLAN.md` DSP.3.6 and DSP.3.7 status.

**Session artifacts:** n/a

**Suspected failure class:** documentation-drift (gap in test coverage, not a behavioral bug)

**Verification criteria:**
- [x] DSP.3.6 test file exists and passes: `swift test --filter BeatGridAppLayerWiringTests` — landed as `PreparedBeatGridAppLayerWiringTests` (BUG-006.2, 2026-05-06). Six cases, all pass.
- [ ] DSP.3.7 test file exists and passes: `swift test --filter LiveDriftValidationTests`

**Fix scope:** Two new test files in `Tests/Integration/`. No production code changes anticipated.

**Related:** DSP.3.6, DSP.3.7

---

### BUG-004 — All production presets have `certified: false`

**Severity:** P3
**Domain tag:** preset.fidelity
**Status:** Open
**Introduced:** V.6 (certification pipeline introduced; no presets have passed M7 yet)
**Resolved:** —

**Expected behavior:** At least one production preset has `certified: true` in its JSON sidecar following Matt's M7 visual review.

**Actual behavior:** All 13 production presets have `certified: false`. The Orchestrator excludes uncertified presets by default; users must enable "Show uncertified presets" in Settings to see any auto-selection behavior.

**Minimum reproducer:** `grep -r '"certified"' PhospheneEngine/Sources/Presets/Shaders/*.json`

**Session artifacts:** n/a

**Suspected failure class:** calibration (quality bar not yet met, not a code bug)

**Verification criteria:**
- [ ] Manual: Matt performs M7 review on at least one preset and approves `certified: true`.
- [ ] Automated: `GoldenSessionTests` passes with at least one certified preset producing non-zero orchestrator selections.

**Fix scope:** Preset authoring work (V.7.7B+, V.7.10). Not a code defect.

**Related:** V.6, V.7.10, D-071

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
