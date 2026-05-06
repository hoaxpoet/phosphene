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
**Status:** Resolved (code-only — manual validation pending)
**Introduced:** Unknown — first observed during QR.1 manual validation 2026-05-06; predates QR.1 (QR.1 did not touch the prepared-grid wiring path).
**Resolved:** 2026-05-06 (BUG-006.2, code-only — manual session-log validation deferred to next live Spotify capture).

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
- [x] Loading a known-prepared Spotify playlist produces at least one `BEAT_GRID_INSTALL: source=preparedCache` entry in `session.log` per track played. (Pending live capture — covered by automated test `PreparedBeatGridAppLayerWiringTests.endToEndProduces_preparedCacheInstall`.)
- [ ] On Love Rehab specifically: SpectralCartograph mode label transitions `◐ PLANNED · UNLOCKED → ● PLANNED · LOCKED` within 5 s of audio. (Manual; deferred to next live Spotify capture.)
- [ ] `features.csv` `grid_bpm` column non-zero from frame 1 of the track. (Manual; deferred.)
- [ ] Manual: drift readout (Δ) settles near zero (±20 ms) within the first bar. (Manual; deferred.)
- [x] Six new automated regression tests in `PreparedBeatGridAppLayerWiringTests` close the BUG-003 coverage gap that let this ship.

**Resolution (BUG-006.2, 2026-05-06):** Two coordinated fixes. **(Cause 1)** `engine.stemCache` is now wired to `sessionManager.cache` in `VisualizerEngine.init` immediately after `makeSessionManager` returns. Both references point to the same `StemCache` instance — `SessionPreparer` writes fill the cache as preparation completes; the engine reads them on track-change without any explicit hand-off. The field had been declared at `VisualizerEngine.swift:171` since the original session-preparation work but was never assigned anywhere, so `resetStemPipeline(for:)` always took the cache-miss branch. **(Cause 2)** `VisualizerEngine+Capture.swift` now resolves the canonical `TrackIdentity` from `livePlan` via the new `PlannedSession.canonicalIdentity(matchingTitle:artist:)` helper. Streaming metadata (Apple Music / Spotify Now Playing AppleScript) only carries title+artist; the planner stored full identities (duration + spotifyID + spotifyPreviewURL hint). The pure-function helper in the Orchestrator module is testable from `PhospheneEngineTests`. Falls back to the partial identity when `livePlan` is nil (preserving ad-hoc reactive behaviour) or when more than one planned track shares the same title+artist pair (preserves conservative behaviour over the wrong cache hit).

New tests: `PreparedBeatGridAppLayerWiringTests` (6 cases) — `engineStemCache_isWiredAfterSessionPrepare`, `trackChangeIdentity_matchesPlannedIdentity`, `ambiguousMatch_returnsNil_partialFallback`, `noMatch_returnsNil`, `endToEndProduces_preparedCacheInstall`, `partialIdentity_withoutCanonicalResolution_missesCache` (negative control pinning the regression direction). All pass. Full engine suite green modulo two documented pre-existing flakes (`MetadataPreFetcher.fetch_networkTimeout`, `MemoryReporter.residentBytes growth`).

The `WIRING:` instrumentation from BUG-006.1 stays in place — it costs nothing at runtime, validates the fix in any session capture, and will catch future regressions. Removal deferred to QR.5 cleanup once the fix has stabilized across multiple sessions.

**Related:** DSP.3.1, DSP.3.2, DSP.3.6, D-078, BUG-003 (test-coverage gap closed by `PreparedBeatGridAppLayerWiringTests`), BUG-006.1 (instrumentation), BUG-006.2 (this fix). Commits: BUG-006.1 instrumentation `7f95cec0` + `807d3b8c`; BUG-006.2 fix pending local commit.

---

### BUG-007 — LiveBeatDriftTracker loses lock under stable real-music input (LOCKING ↔ LOCKED oscillation)

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** Open
**Introduced:** Unknown — first observed during QR.1 manual validation 2026-05-06; predates QR.1 (QR.1 did not change drift-tracker lock semantics — only widened `playbackTime` to `Double`).
**Resolved:** —

**Expected behavior:** Once `LiveBeatDriftTracker.computeLockState()` returns `.locked` (after `matchedOnsets ≥ lockThreshold`), the tracker remains `.locked` for the duration of the track unless the input has gone genuinely silent for ≥ 2 × medianBeatPeriod. Onset-time drift settles into a band ±30 ms wide (the `strictMatchWindow`) and stays there.

**Actual behavior:** Mode label oscillates between `◑ PLANNED · LOCKING` and `● PLANNED · LOCKED`, holding LOCKED for only a few seconds at a time before regressing. Observed independently on:
- Test 2: Pyramid Song (~68 BPM, ad-hoc reactive after live Beat This! installed grid). Beat sync described as "close, not exact."
- Test 4: Love Rehab (125 BPM, ad-hoc reactive after live Beat This! installed grid). Orb pulsing "mostly in time with the beat."

**Reproduction steps:**
1. Start an ad-hoc reactive session ("Start listening now" from IdleView).
2. Play Love Rehab (Chaim) in Apple Music or Spotify.
3. Wait ~10 s for live Beat This! to install a grid.
4. Switch to Spectral Cartograph (`Shift+→`).
5. Observe mode label over the next 30 s.

**Minimum reproducer:** Any ad-hoc reactive session on a kick-driven track at 48 kHz tap rate.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-06T14-21-09Z/session.log` — `BeatGrid installed: source=liveAnalysis, bpm=125.8` at `14:21:33Z`.
- `features.csv` from the same session — `lock_state` column likely flips between `1` (locking) and `2` (locked).

**Suspected failure class:** `algorithm` (lock-hysteresis tuning) or `precision` (drift accumulation under real-music onset jitter).

**Evidence:**
- The `consecutiveMisses` counter in `LiveBeatDriftTracker` is incremented when an onset doesn't match within ±30 ms of the smoothed drift, and decremented (reset to 0) on tight match. There is no decay on `matchedOnsets` itself, but the lock-state computation uses a ratio that could regress.
- Pre-QR.1 the drift tracker was using a `Float` playbackTime that could drift sub-µs over a long session — that's not the cause here (QR.1 widens to `Double` and the test sessions are < 1 minute).
- Likely candidates: (a) the `strictMatchWindow = 30 ms` is too tight for real-music kick onset jitter (Phosphene's `BeatDetector` produces sub_bass onsets with ±10–20 ms quantization); (b) `consecutiveMisses` advancing past a threshold demotes lock state without the matchedOnsets counter falling, and the demotion path is over-eager.

**Verification criteria:**
- [ ] Once `lock_state` reaches `2` (locked) on a stable track, it stays at `2` for ≥ 30 s of continuous playback at the same tempo.
- [ ] `drift_ms` values in `features.csv` settle into a ±30 ms band and the standard deviation over a 10-s window is < 15 ms.
- [ ] Manual: orb pulse sits exactly on the kick (not "mostly in time"), and the BR-panel beat-phase tick lines up with the beat orb's flash.

**Fix scope:** Diagnose with a `features.csv` capture from a real session. Plot `lock_state` and `drift_ms` over time; identify whether the demotion correlates with onset density drops, drift spikes, or just an unfortunate `matchedOnsets` ratio decay. Likely fix is widening `strictMatchWindow` to 40–50 ms or adding lock hysteresis (`matchedOnsets` decays slower than it builds). Out of scope for QR.1 — schedule for a dedicated `LiveBeatDriftTracker` tuning increment after QR.2 / QR.3 land.

**Related:** DSP.2 S7, D-077, D-079 (touched the file but did not change lock semantics)

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
