# Cold-Start Sync — Design + Adversarial Review

**Date:** 2026-05-20
**Phase:** CS (Cold Start) — new
**Status:** Pre-implementation design. No code changes have landed.

## 1. Problem statement

Phosphene's product contract — restated by Matt 2026-05-20:

> The product should be at least beat-synced from frame 1, having 1s of wonky performance while the transition occurs is acceptable but this should be the only session wonkiness. The standard is pretty high.

This document audits whether Phosphene's current implementation can meet that bar, identifies the gaps that prevent it from doing so today, and proposes a bounded sequence of increments that close those gaps inside the streaming-only architectural constraint.

The bar is not aspirational. It is the minimum behavior for the load-bearing use case (a collaborative listening party where most tracks are novel to the listeners). If we cannot meet it, the product is not commercially viable as conceived.

## 2. Hard constraints

These are not engineering choices. They are externally imposed limits:

- **Spotify Web API and Apple Music API expose only a 30-second preview clip per track.** No full-track audio.
- **Spotify `/audio-analysis` and `/audio-features` endpoints were deprecated for new third-party apps in November 2024.** Grandfathered access existed for apps that filed Extended Quota Mode applications before the cutoff. Phosphene's credentials almost certainly do not have grandfathered access (Phosphene is recent and Spotify integration shipped well after the cutoff in increment U.11). This is testable with a single curl against `/v1/audio-analysis/{track_id}` but the prior is strongly against access.
- **No viable third-party service provides what Spotify's `/audio-analysis` did at frame resolution.** Cyanite, ACRCloud, AudD, AcousticBrainz (defunct), Soundcharts (already integrated): none provide stem-separated time-series at the resolution Phosphene's preset pipeline reads. Section boundaries and coarse energy curves are partially available from some; none would solve the stem-driven cold-start case.
- **Phosphene does not control playback.** The user starts the music in their streaming app; Phosphene captures via the Core Audio system tap.
- **The architectural shifts that would lift the constraint** (local-file support; cache-on-first-listen via tap replay; user-network-effect catalog) have been explicitly deprioritized by Matt for product / strategic reasons. Phosphene must work against Spotify and Apple Music as configured today.

## 3. Bar to clear

Restated as quantitative criteria a verification test can pass or fail:

| Criterion | Threshold | Notes |
|---|---|---|
| Visual beat phase aligns with audible beat | ±50 ms by frame 1, ±30 ms after 1 s | "Frame 1" = first rendered frame after playback starts. ±50 ms is the audio-visual sync tolerance for non-trained listeners; ±30 ms is the working tolerance for tap-trained listeners. |
| Wonkiness window | ≤ 1 s | Period during which beat-driven visuals are visibly mis-aligned to audible beats. After this window, full performance is expected. |
| Stem-driven motion | Acceptable to "warm in" over ≤ 10 s | Cached stem aggregate must drive a usable visual at t=0; live stem analyzer warms via existing D-019 blend. Not a frame-1 requirement. |
| Mood-driven palette | Single scalar acceptable for cold-start | Time-varying mood is desirable but not in scope for this phase. |
| Section-aware visuals | Out of scope | Requires full-track audio data which we do not have. |

The bar is strictly about beat sync from frame 1. Stem, mood, section ambitions exist but are explicitly secondary to the bar.

## 4. What is already in production (verified by code reading)

This is the surprise from the research pass. **Most of the C2 + first-onset-anchor proposal sketched earlier in this session already exists, built incrementally across the BUG-007.x series.** Specifically:

### 4.1 Full-track beat grid extrapolation

[`BeatGrid.offsetBy(_:horizon:)`](PhospheneEngine/Sources/DSP/BeatGrid.swift:120) extrapolates beats and downbeats forward by `horizon` seconds (default 300 s) using the cached BPM. The cache loader calls `cached.beatGrid.offsetBy(0)` which leaves the beat phase intact and extends the grid 300 s into the future — enough for any track in a typical playlist.

**Implication:** Beat-locked visuals can compute against a grid that covers the entire track from frame 1. There is no "preview-window cutoff" beyond which the predicted grid runs out.

### 4.2 Per-track grid-vs-onset offset calibration

[`GridOnsetCalibrator`](PhospheneEngine/Sources/Session/GridOnsetCalibrator.swift:1) runs at preparation time. It replays the 30 s preview audio through Phosphene's live `BeatDetector` and computes the median (gridBeat − onsetTime) offset. This offset is stored on `CachedTrackData.gridOnsetOffsetMs`.

**Implication:** the predicted beat grid's absolute phase is calibrated to where the live onset detector will fire on the actual song's beats — before playback starts. The cold-start phase problem (preview-vs-track offset, BeatThis-vs-sub-bass onset latency, preview-not-on-bar-boundary) is addressed by this calibration.

### 4.3 Drift EMA seeded at calibrated value

[`LiveBeatDriftTracker.setGrid(_:initialDriftMs:)`](PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift:408) accepts the calibrated offset and seeds the drift EMA. The first frame after track install sees the tracker with `drift = gridOnsetOffsetMs/1000` rather than `drift = 0`. `beatPhase01` and `barPhase01` are computed from the seeded drift immediately.

**Implication:** the visual gets a beat phase that is phase-aligned (modulo the beat period) from frame 1. The historical "wait for 4 onset matches to stabilize drift" warmup is partially compressed into the prep-time calibration.

### 4.4 Hybrid runtime re-calibration

[`BUG-007.9`](PhospheneApp/VisualizerEngine+Stems.swift:217) re-runs `GridOnsetCalibrator` on the actual tap audio after ~15 s of buffered playback. The runtime-derived offset replaces the prep-time bias via `LiveBeatDriftTracker.applyCalibration(driftMs:)`. This closes the preview-vs-tap encoding-mismatch loop.

**Implication:** the calibration is not only available from frame 1 but is also refined to playback-accurate values within ~15 s — well inside the typical track length.

### 4.5 D-019 stem warmup blend (where it's been applied)

Several presets implement the [`smoothstep(0.02, 0.06, totalStemEnergy)`](PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.metal:46) crossfade pattern: when stems are still warming (`totalStemEnergy ≈ 0`), the preset uses the cached/proxy fallback; when stems converge to representative values, the preset shifts to live stem routing. Documented in CLAUDE.md as the D-019 convention; honored explicitly in FerrofluidOcean, Gossamer, VolumetricLithograph, and AuroraVeil.

**Implication:** the stem-warmup cold start case is *handled* in compliant presets. Non-compliant presets are the audit risk (see §6).

### 4.6 Lock state vs phase availability

The tracker's `LockState` is documented to require 4 matched onsets to reach `.locked`, but the per-frame `Result.beatPhase01` is computed from the seeded drift from frame 1 regardless of lock state. Presets consume `beatPhase01`, not `lockState` (except `SpectralCartograph`, which displays it diagnostically).

**Implication:** the "1-2 second multi-onset evidence" window I described earlier is the time to *full lock confidence*, not the time to *usable phase*. Usable phase is frame 1 for tracks with a non-zero `gridOnsetOffsetMs`.

## 5. What is unverified

The infrastructure above suggests the bar is met by existing code. That is a claim, not a measurement. The honest answer is: I do not know whether the production behavior actually delivers ±50 ms phase from frame 1 on a representative sample of tracks. The discipline rule from CLAUDE.md ("Diagnostic infrastructure precedes fidelity claims") applies — without measurement, the claim is assertion-shaped.

What we'd need to measure:

- **Frame-1 phase accuracy on real tracks across the listening-party use case.** Spotify-prepared session, multi-track playlist, capture session, post-mortem grep of session.log + features.csv to extract observed beat phase against an external ground-truth (a metronome tap, or careful listening with `[`/`]` phase-offset tuning).
- **Calibration accuracy distribution.** For each track in a sample, what is `gridOnsetOffsetMs`? What is the post-runtime-recalibration value? How large is the prep-vs-runtime delta? Are there tracks where the calibration is wildly wrong?
- **Robustness across the failure surfaces** — odd-meter tracks (Money 7/4 — BUG-013), tempo-unstable tracks (jazz, rubato), tracks with quiet intros (no audible onsets in the first 2-3 seconds), short-duration tracks (< 10 s body after first segment).

## 6. Adversarial review

This is where I previously skipped over the work. Each item below is a risk, edge case, or failure mode that could break the "beat-synced from frame 1" bar. Some are honest unknowns; some are likely; some are bounded.

### 6.1 The cached BPM might be wrong for some tracks

Beat This! has known failure modes per `CLAUDE.md` and `KNOWN_ISSUES.md`:

- **Octave errors** on tracks with syncopated drums (kick on 1+3 vs 1+2+3+4) — Beat This! sometimes reports half-time on these.
- **Odd-meter tracks** (Money 7/4 = BUG-013; Pyramid Song 16/8 = BUG-001) — meter detector mis-classifies, ML BPM can also be wrong.
- **Tracks with quiet intros that fall in the preview window** — Beat This! on a 30 s window with substantial silence has degraded accuracy.

If the cached BPM is wrong by half or double, every predicted beat past frame 1 is off; the drift tracker fights a beat-period correction continuously, never converging. The visual is visibly out of sync until the live tracker can override with enough matched live onsets, which on a wrong-BPM track might not happen because the matching gate has only ±50 ms tolerance.

**Mitigation:** existing — `halvingOctaveCorrected` runs on the live-Beat-This! path but NOT on the offline-prep path (see [`BeatGrid.swift:185`](PhospheneEngine/Sources/DSP/BeatGrid.swift:185)). Prep relies on the longer 30 s window giving Beat This! enough context. **Open question:** how often does the offline prep produce a wrong BPM on the target use case? Empirical only.

### 6.2 The calibration runs on low-bitrate preview audio

`GridOnsetCalibrator` calibrates against the 96 kbps mp3 Spotify preview. The user's actual playback is higher quality (160-320 kbps depending on subscription tier). Spectral content in the preview is degraded — particularly in the sub-bass band Phosphene's onset detector relies on most heavily. The calibration could be biased by the encoding artifact rather than the song's actual onset profile.

**Mitigation:** existing — BUG-007.9 hybrid runtime re-calibration uses the actual tap audio to refine after ~15 s. But the first 15 s of playback uses the preview-derived calibration. **Open question:** how large is the typical prep-vs-runtime delta? If it's < ±20 ms, we're fine. If it's ±100 ms on some tracks, the first 15 s of those tracks is visibly off.

### 6.3 The preview is not from track t=0

Spotify previews are typically from around t=60-90 s in the track (somewhere near the chorus). The preview's beats are NOT in track-time; they are in preview-time. The cached `beatGrid.beats` array contains preview-time timestamps. `offsetBy(0)` does no shifting — so the cached beat at preview-time 0.4 s is treated as a beat at track-time 0.4 s.

If the preview is from a verse and the actual song starts with an intro of different character, the cached `gridOnsetOffsetMs` reflects the verse's onset alignment, not the intro's. For tempo-stable tracks this is fine modulo the beat period — the phase repeats. For tracks where the intro is unmetered or has a different downbeat phase, the alignment could be wrong.

**Open question:** how common is this in the target use case? Pop / dance / hip-hop tracks generally have stable structure across sections. Edge case is more likely on indie / prog / orchestral material.

### 6.4 Some presets may violate the data hierarchy rule

CLAUDE.md is explicit: continuous energy primary, stems accent. Reading the catalog:

- **`FerrofluidOcean`** — D-019 compliant with explicit `fo_stem_warmup_blend`. ✓
- **`Gossamer`** — D-019 compliant per inline comment at line 128. ✓
- **`AuroraVeil`** — D-019 compliant per inline comment at line 381. ✓
- **`VolumetricLithograph`** — D-019 compliant per inline comment + visible in shader. ✓
- **`Starburst`** — uses `stems.vocals_energy * 0.10` directly at line 54. No visible warmup blend. *Potential violation.*
- **`KineticSculpture`** — uses `f.bass * 0.16 + f.bass_dev * 0.05` (hybrid raw + deviation). The deviation share is small relative to the raw share. *Potential D-026 violation* — though QR.1's BUG-R009 noted this site and applied a partial fix.
- **`GlassBrutalist`** — uses `f.beat_bass`, raw bands. Comments document D-026 awareness. *Audit required.*
- **`Arachne`** — staged composition; complex routing. Audit required.

**Risk:** any preset that drives PRIMARY visual motion from stems-or-raw-bands without a D-019 blend will look wrong during cold-start because the cached stem aggregate is a *single point*, not a time-varying signal. The visual will appear "stuck" for the warmup window.

**Mitigation:** audit. Per-preset compliance check + targeted fix where violation is found.

### 6.5 SessionPlanner has no first-segment minimum duration

[`SessionPlanner+Segments.swift:171-174`](PhospheneEngine/Sources/Orchestrator/SessionPlanner+Segments.swift:171) computes `segLen = max(1.0, min(remainingInSection, maxByPreset))`. The floor is 1 second, not 10. A short first section could produce a segment that ends before the stem warmup window completes. The transition to segment 2 would then occur mid-warmup; segment 2 also gets a cold-start window of its own from frame 1 of its tenure.

**Risk:** if first segment is, say, 8 s, the user perceives: 8 s of cold-start visual → transition → another ~2 s of cold-start in segment 2 → full performance. The wonkiness window is effectively 10+ seconds instead of the bar's 1 s, with a preset transition in the middle that looks arbitrary.

**Mitigation:** add a first-segment minimum duration constraint (target 10-12 s) to `planOneSegment`. Trivial change. Must also handle: tracks shorter than 12 s (rare; can be allowed to violate the floor for those); section boundaries between 1 and 12 s (push to the next bar boundary instead).

### 6.6 First-onset anchor is not currently implemented

I previously proposed a "first-onset hard re-anchor" — snap the drift to the first matched live onset rather than letting EMA refine it. This is NOT in production. The existing EMA-with-`onsetAlpha=0.4` means each onset moves the drift 40% of the way toward the instant measurement; after 4 matched onsets, drift is within ~13% of equilibrium.

For tracks where `gridOnsetOffsetMs` is accurate (most tracks under the existing infrastructure), the EMA refinement is small and invisible. For tracks where `gridOnsetOffsetMs` is wildly wrong (calibration noise, encoding mismatch, BPM error), the EMA takes 4-8 onsets to converge — and during that window the visual is visibly off.

**Open question:** does this happen often enough on the target use case to require a fix? Could be addressed by either (a) hard-snap on the first matched onset if `|instantDrift − drift| > some_threshold`, or (b) trusting the BUG-007.9 hybrid runtime recalibration (which runs at ~15 s) to correct accumulated errors. Empirical.

### 6.7 Rhythmless / quiet-intro material

If the first 1-3 seconds of playback contain no audible percussive onset (sustained pad, vocal-only intro, soft piano), the live onset detector does not fire. The drift EMA stays at its seeded value (which may or may not be accurate). If the seeded value is wrong, the visual is visibly off until the first audible onset fires.

**Mitigation:** for the listening-party use case, this is rare. Party playlists are percussion-heavy. For other use cases (acoustic / folk / ambient mixed playlists), the wonkiness window could be longer than 1 s.

**Honest scope:** accept the limitation; document it; do not engineer for it.

### 6.8 Section boundaries inside the first-segment minimum window

If the orchestrator wants to schedule a preset transition at, say, t=8 s (a detected section boundary in the preview), the first-segment minimum (10 s) would conflict. Push to the next bar boundary after t=10? Or accept the early transition because section-boundary transitions are higher-value than the cold-start protection? This is a design choice; needs explicit decision.

### 6.9 Track-change rapid skipping

A user skipping aggressively between tracks. Each new track resets `LiveBeatDriftTracker`, re-seeds drift, re-warms the stem analyzer. If the user skips faster than the warmup completes, the visual might never lock. Acceptable — rapid skipping is an unusual mode and the user is presumably not paying close attention to visual sync during it.

### 6.10 The audit itself has scope risk

Auditing the catalog for data-hierarchy compliance could reveal a small number of violations (likely) or many (possible). If many, the work to fix is large and might motivate revisiting the architectural assumption. The audit needs to be done before we commit to the scope of the fix work.

### 6.11 Beat phase needs `beatsPerBar` correct for bar-locked presets

Bar-locked presets (Ferrofluid Ocean wave cycling, anything driving from `barPhase01`) require `beatsPerBar` to be accurate. BUG-013 documents that Soundcharts does not provide time signature; the ML detector mis-classifies odd-meter tracks. For Money (actual 7/4 detected as 2/X), `barPhase01` cycles 3.5× too fast. Visible artifact on bar-locked presets, independent of beat-phase correctness.

**Status:** known limitation. Out of scope for Phase CS (this is BUG-013's territory).

### 6.12 The visual transition between first and second presets

If the orchestrator picks two visually-distinct presets back-to-back, the transition at the first-segment boundary is a hard character shift. Phosphene has a transition policy (warm crossfade vs cut based on energy) that handles this, but the cold-start case is a specifically tight window where the user is already paying attention to whether the visualizer "works." A jarring transition at t=10-12 s could read as another defect on top of the cold-start being already imperfect.

**Mitigation:** verify the transition policy produces clean transitions in the cold-start-to-body case. This is a verification item, not a code change.

### 6.13 Latency between tap audio and rendered visual

`LiveBeatDriftTracker.audioOutputLatencyMs` exists (BUG-007.6) to compensate for tap-vs-output latency. The default is 0; production wiring sets it to 50 ms for internal Mac speakers. AirPods / Bluetooth would be higher (Bluetooth latency is typically 150-300 ms depending on codec and device). If the user is on AirPods and the latency value is wrong, the visual fires before the audio reaches the listener. The cold-start bar is then violated for a structural reason that has nothing to do with this phase's work.

**Mitigation:** out of scope for Phase CS, but worth flagging as a UX concern. A future increment could expose the latency value to the user (currently dev-only via `,`/`.` shortcuts) so they can tune it for their headphones.

## 7. Proposed work — Phase CS increments

Sequenced by dependency and risk:

### CS.1 — Empirical verification of existing cold-start beat sync

Build a verification harness or extend an existing one (`PresetSessionReplay` from SR.1 is a strong candidate base) to measure observed beat phase from frame 1 against the cached beat grid for a representative playlist. Output: per-track distribution of `(visual_beat_time − audible_beat_time)` for the first 10 seconds of playback.

**Bar to clear:** ≥ 90 % of tracks in a 10-track party playlist meet ±50 ms phase from frame 1.

**If passes:** the infrastructure works; proceed to CS.2-3 to harden the orchestrator and audit the catalog.

**If fails:** the calibration or extrapolation has bugs; the next increment is diagnosis. Don't proceed past CS.1 without resolution.

### CS.2 — First-segment minimum duration

Add a first-segment-of-track minimum duration to `SessionPlanner.planOneSegment`. Target 10-12 s. Handle edge cases: tracks shorter than the minimum; section boundaries inside the minimum window. New scoring context fields if needed; new test suite covering the constraint.

**Scope:** small (~1 session). Risk: low. Touches deterministic planner code path; existing golden session tests will catch regressions.

### CS.3 — Data-hierarchy compliance audit

For each preset in the catalog: read the .metal file, classify every audio-reactive driver as `primary` vs `accent` vs `proxy-fallback`. Compare against CLAUDE.md's data hierarchy rule. Produce a per-preset findings document.

Specific check criteria per preset:

- Continuous energy bands (`f.bass`, `f.mid`, `f.treble` and their `_att_rel` / `_dev` variants) — used as primary driver?
- Stem energies (`stems.X_energy`) — used as primary driver? If so, is there a D-019 warmup blend (`smoothstep(0.02, 0.06, totalStemEnergy)`)?
- Beat onsets (`f.beat_bass`, `f.beat_composite`, `stems.drums_beat`) — used as accent only?
- Predicted beats (`beat_phase01`, `bar_phase01`) — used for jitter-free motion?

**Output:** `docs/PRESET_DATA_HIERARCHY_AUDIT_2026-05-XX.md` with per-preset findings. No code changes in this increment.

**Scope:** medium (~1-2 sessions). Risk: low.

### CS.4 — Targeted fixes from audit findings

Based on CS.3 output: for each non-compliant preset, scope a fix increment. Likely candidates from preliminary scan:

- `Starburst` — `stems.vocals_energy` reading without D-019 blend at line 54
- `KineticSculpture` — raw `f.bass` share in `sminK` (BUG-R009 partial fix; may want to convert fully to deviation)
- `GlassBrutalist` — raw bands in some routes; needs verification

For each: minimum change to bring into D-019 / D-026 compliance without changing the visual intent. Regenerate golden hashes; update preset-specific test gates.

**Scope:** variable (one session per preset, ideally). Risk: medium per preset — preset-touching work is where my track record is worst.

### CS.5 — Documentation of the cold-start contract

Promote the cold-start data-flow understanding into CLAUDE.md and SHADER_CRAFT.md as a durable rule. Specifically:

- A new section in CLAUDE.md (under "Audio Data Hierarchy") titled "Cold-Start Phase Contract" describing:
  - `gridOnsetOffsetMs` calibration provides frame-1 beat phase
  - D-019 blend pattern provides frame-1 stem fallback
  - `first-segment minimum 10 s` provides the warmup window for live primitives
  - Presets violating these contracts will look broken during cold-start
- A short SHADER_CRAFT.md section pointing authors at the cold-start audit checklist used in CS.3

**Scope:** small (~½ session). Risk: low.

### Out of scope for Phase CS

- BUG-013 time-signature for odd-meter tracks — different defect, different fix.
- Audio output latency UX (AirPods / Bluetooth compensation) — future Phase.
- Section-aware visuals, mood arc, stem time-varying — fundamentally blocked by the streaming-only constraint per §2.

## 8. Open empirical questions

Each of these would change the design if answered differently. None of them can be answered from code reading alone.

1. **Does `gridOnsetOffsetMs` actually deliver ±50 ms phase from frame 1 across a representative sample of tracks?** (CS.1 answers this.)
2. **What is the typical magnitude of the prep-vs-runtime recalibration delta?** (CS.1 answers this as a side product.)
3. **How many presets actually violate the data hierarchy rule?** (CS.3 answers this.)
4. **What is the cost of the audit? Of the fix work that follows?** (CS.3 + CS.4 reveal.)
5. **Does Phosphene's Spotify app have grandfathered `/audio-analysis` access?** (One curl test — not within Phase CS but worth doing while we're scoped to this surface.)

## 9. Anti-patterns I'm explicitly avoiding

Lessons from CLAUDE.md Authoring Discipline and prior session failures (Drift Motes, Aurora Veil, Ferrofluid Ocean rounds 50-65):

- **Not pitching new architecture before measuring.** CS.1 measures before any code change beyond instrumentation.
- **Not committing to fix scope before audit.** CS.3 produces findings; CS.4 scope follows from findings.
- **Not claiming the bar is met without empirical evidence.** "The infrastructure exists" is a hypothesis; the test is the measurement.
- **Not engineering for cases the listening-party use case does not contain.** Rhythmless / acoustic / classical / odd-meter tracks are flagged as honest limitations; no engineering effort goes to making them work.
- **Not bundling unrelated work into the phase.** BUG-013, AirPods latency, section/mood ambitions are out of scope by name.

## 10. Phase exit criteria

Phase CS closes when, in this order:

1. CS.1 verification passes (≥ 90 % of representative tracks meet ±50 ms phase from frame 1), OR documented diagnosis of why it doesn't and a path to fix.
2. CS.2 first-segment minimum landed and golden sessions still pass.
3. CS.3 audit document published.
4. CS.4 fix increments completed for every preset CS.3 flagged.
5. CS.5 documentation merged.
6. Matt manual validation on a real listening-party playlist confirms perceptual beat sync from frame 1.

Step 6 is the load-bearing close criterion. The automated checks confirm the infrastructure works; only Matt's perceptual review confirms the *product* works.

---

**Sign-off:** this document represents the current best understanding of the cold-start problem and its solution path within Phosphene's streaming-only architecture. It is open to revision as CS.1 surfaces empirical data. The discipline rule "diagnostic infrastructure precedes fidelity claims" (CLAUDE.md, 2026-05-20) governs every claim above — anything not measured is a hypothesis.
