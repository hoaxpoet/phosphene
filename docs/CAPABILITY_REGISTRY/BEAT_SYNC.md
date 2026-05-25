# Capability Registry — Beat-Sync Wiring (BUG-017 audit)

**Audit increment:** BSAudit
**Date:** 2026-05-24
**Auditor:** Claude (session-driven, read-only)
**Scope:** the cold-start beat-sync wiring in dependency order — prep-time grid + onset-offset seeding (`BeatGridResolver`, `GridOnsetCalibrator`), cold-start grid install (`VisualizerEngine+Stems.resetStemPipeline`), live drift EMA (`LiveBeatDriftTracker.update`), live drift behaviour under wrong-phase grids, verifier clock-offset estimation (`ColdStartAnalysis.resolveAudibleBeats` + `ClockOffset.estimate`), and the `BeatDetector` sub-bass onset feed shared by all three.
**Methodology:** [`docs/prompts/BEAT_SYNC_AUDIT_KICKOFF.md`](../prompts/BEAT_SYNC_AUDIT_KICKOFF.md). Phase CA pattern (read code end-to-end; verdict-per-capability; empirical grounding per verdict; ranked root-cause hypotheses; per-component fix scopes). **Audit only — no fix code in this increment.**
**Reads relied on:** [`CLAUDE.md`](../../CLAUDE.md) (Defect Handling Protocol; Authoring Discipline; Failed Approaches #58, #66, #67, #68); [`docs/QUALITY/KNOWN_ISSUES.md`](../QUALITY/KNOWN_ISSUES.md) BUG-017 + every addendum through the 2026-05-24 revert; [`docs/RELEASE_NOTES_DEV.md`](../RELEASE_NOTES_DEV.md) `[dev-2026-05-22-a]` through `[dev-2026-05-24-a]`; [`docs/COLD_START_SYNC_DESIGN_2026-05-20.md`](../COLD_START_SYNC_DESIGN_2026-05-20.md); [`docs/ENGINEERING_PLAN.md`](../ENGINEERING_PLAN.md) Phase CS / CS.1.y + Phase CA pattern; [`docs/CAPABILITY_REGISTRY/DSP_MIR.md`](DSP_MIR.md) for the existing audit pattern and `BeatGrid` / `LiveBeatDriftTracker` notes.
**Captures consulted:** `~/Documents/phosphene_sessions/2026-05-22T16-57-36Z/` (CS.1 baseline, "cap1"); `2026-05-22T19-03-59Z/` (CS.1.y.2 onset-fix, "cap2"); `2026-05-23T02-39-54Z/` (CS.1.y.2-redo round 2, "cap3"); `2026-05-24T15-07-31Z/` (M7, "cap4"). All four captures play the same 10-track playlist with identical Spotify previews.

---

## Summary

| Component | File / locus | Verdict |
|---|---|---|
| 1a. Prep-time Beat This! grid (preview) | `BeatGridResolver.swift` + `SessionPreparer+Analysis.swift` | `production-active-but-broken` (for cold-start *phase*: preview-time grid treated as track-time) |
| 1b. Prep-time `gridOnsetOffsetMs` seed | `GridOnsetCalibrator.swift` (sub-bass onsets vs preview grid) | `documented-but-broken` — onset-based at prep time; Failed Approach #68's root cause is still live in production at prep time |
| 2. Cold-start grid install path | `VisualizerEngine+Stems.swift:484` (`cached.beatGrid.offsetBy(0)`) | `documented-but-broken` — preview-clip timeline as track timeline; BUG-017 root cause |
| 3. Live drift EMA (steady-state) | `LiveBeatDriftTracker.update` + `setGrid(_:initialDriftMs:)` | `production-active` for its designed purpose (small continuous drift); **structurally cannot make gross phase corrections** (±50 ms hard match window) |
| 4. EMA behaviour under wrong-phase grid | `LiveBeatDriftTracker.driftSearchWindow = 0.05` | `characterized` — bimodal failure: < 50 ms wrong → biases to off-beat onsets; > 50 ms wrong → rejects all onsets, drift parks near seed |
| 5a. Verifier clock-offset estimate | `ColdStartAnalysis.resolveAudibleBeats` + `ClockOffset.estimate` | `unverified-claim` — sync-independent in principle, but per-capture sub-bass-onset variability could refine within ±150 ms; needs instrumentation against `wallclockS - rawStart - playbackTime` |
| 5b. Verifier ground-truth Beat This! on raw-tap | `BeatThisGrid.beats` (25 s slice) | `production-active-but-broken` as a per-capture *stable* reference — same-track / same-Spotify-preview / different-capture produces different beat positions on a subset of tracks (Beat This! is sensitive to per-capture acoustic context) |
| 6. `BeatDetector` sub-bass onset feed | `BeatDetector.detectOnsets` (band 0: 20-80 Hz) | `production-active-but-broken` as a beat-phase reference — fires on sub-bass *events*, not beats; same FA #68 limitation across all three consumers (live EMA, prep-time calibrator, verifier clock offset) |

**The highest-priority finding** is that the *same defect class* (off-beat sub-bass onsets) appears in three independent places (Component 1b prep, Component 3 runtime, Component 5a verifier) and the *same defect class* (Beat This! non-reproducibility across captures) appears in two more (Component 5b verifier ground truth, the retired CS.1.y.2-redo at 15 s). The CS.1.y.2-redo cycle moved Failed Approach #68 from runtime to verifier-and-prep without retiring it from either, and added Component 5b non-reproducibility on top.

**No `production-orphan`, `dead`, `stub`, or `documented-but-missing` findings in this scope.** Every component in the wiring has live consumers and live code paths.

---

## Methodology notes

- **`production-active`** — capability runs in production, doc-aligned, no broken claim.
- **`production-active-but-broken`** — runs in production AND a public claim about its correctness fails empirically. Calls out which claim and which evidence.
- **`documented-but-broken`** — doc-comment / design-doc claims correctness; code does not deliver it.
- **`unverified-claim`** — runs in production AND the claim is not empirically confirmable from existing artifacts; instrumentation-and-recapture step surfaced as a gap.
- **`characterized`** — not a binary verdict but a *behavioural finding* about how the component acts under a specific input regime (used for Component 4 below).

When a measurement is not available from existing artifacts, the gap is named explicitly per the kickoff's stop-and-report rule (no claim without evidence). New captures or new instrumentation are listed as such; they are not produced inside this audit.

---

## Findings

### Component 1a — Prep-time Beat This! grid (BeatGridResolver + Beat This! on the 30 s preview)

**Code locus.** `PhospheneEngine/Sources/Session/SessionPreparer+Analysis.swift:116-122` (full-mix preview path) → `DefaultBeatGridAnalyzer.analyzeBeatGrid(samples:sampleRate:)` → `BeatThisPreprocessor` → `BeatThisModel` → `BeatGridResolver.resolve(beatProbs:downbeatProbs:frameRate:)` → `BeatGrid(beats:downbeats:bpm:beatsPerBar:barConfidence:frameRate:frameCount:)`.

**What it actually does.**
- Runs Beat This! on the 30 s Spotify preview clip and returns a `BeatGrid` in *preview-time*: beat 0 is at preview-time 0, beat N is at preview-time `~60/bpm × N`. The preview is **typically excerpted from somewhere around track-time 60-90 s** (Spotify's CDN convention); the preview's clock has no defined relationship to the full track's clock.
- `BeatGridResolver` (181 lines, pure stateless) takes per-frame sigmoid-applied beat/downbeat probabilities and resolves them via a 7-frame max-pool peak-pick + adjacent-peak dedup + trimmed-mean IOI BPM + downbeat snap. The implementation matches the Beat This! Python postprocessor and was validated at DSP.2 S2.

**What the surrounding code assumes.** `VisualizerEngine+Stems.swift:484` calls `cached.beatGrid.offsetBy(0)` before passing to `MIRPipeline.setBeatGrid` — `offsetBy(0)` extrapolates the grid 300 s forward but does **not** shift the existing beats. The install equates preview-time 0 with track-time 0.

**Empirical grounding — reproducibility of the grid.** Inspecting `BeatGrid installed:` log lines across cap1/cap2/cap3/cap4 for the 10-track reference playlist:

| Track | BPM (all 4 caps) | Beats (all 4 caps) | Meter |
|---|---|---|---|
| Billie Jean | 117.0 | 58 | 4/X |
| Around the World | 121.3 | 61 | 4/X |
| Seven Nation Army | 120.6 | 61 | 4/X |
| Get Lucky | 116.1 | 58 | 4/X |
| Superstition | 100.3 | 51 | 4/X |
| Everlong | 157.8 | 79 | 4/X |
| Royals | 84.9 | 42 | 4/X |
| HUMBLE. | 76.0 | 39 | 4/X |
| B.O.B. | 153.7 | 77 | 4/X |
| Money | 123.2 | 62 | 2/X |

**Across-capture reproducibility: BPM / beat count / meter are byte-identical for every track in every capture.** Beat This! on the preview clip is deterministic at this aggregate scale on the dev machine (the four captures span 2 days and include the build flip-flops of CS.1.y.2 / CS.1.y.2-redo / revert — the prep code path was unchanged across them).

**Verdict — what's broken.** The grid is structurally a *preview-time* artifact treated as a *track-time* artifact at install. The aggregate determinism above does NOT close the BUG-017 gap; it just rules out "Beat This! grid varies across runs" as a candidate cause for the cross-capture median-Δ variability documented in §Q2 below.

The specific failure mode the install path commits to: any track whose Spotify preview happens to be excerpted away from a song bar boundary (i.e., almost every track) carries a per-track *bar phase offset* between preview and track that the install does not correct. The HUMBLE +338 ms cold-start median Δ in cap1 is exactly this — HUMBLE at 76 BPM has a 790 ms beat period; +338 ms = 0.43 beat off — a half-beat-magnitude bar-phase mismatch between the preview clip and the start of the track.

**`production-active-but-broken` for cold-start phase purposes.** Doc-aligned for the prep step it claims to do. Mis-used at the install step (Component 2). Not the prep step's bug to fix, but a contributor to the BUG-017 chain.

---

### Component 1b — Prep-time `gridOnsetOffsetMs` seed (`GridOnsetCalibrator`)

**Code locus.** `PhospheneEngine/Sources/Session/GridOnsetCalibrator.swift` (199 lines). Consumed at prep time by `SessionPreparer+Analysis.swift:179` (writes to `CachedTrackData.gridOnsetOffsetMs`) and at install time by `VisualizerEngine+Stems.swift:486` (passed as `initialDriftMs` to `MIRPipeline.setBeatGrid(_:initialDriftMs:)`).

**What it actually does.**
1. Spawns a fresh `BeatDetector(binCount: 512, sampleRate: Float(sampleRate), fftSize: 1024)` and creates an FFT setup.
2. Replays the preview audio through the detector frame-by-frame at non-overlapping 1024-sample hops, producing per-frame `result.onsets[0]` (sub-bass onset boolean) and accumulating onset *timestamps* (frame index × hop / sampleRate).
3. For each onset, finds the nearest beat in the cached grid; if `|nearest − onset| ≤ 0.200 s` (`maxMatchWindow = 0.200`), keeps `(nearest − onset)` as a candidate offset.
4. Returns the *median* of all candidate offsets in ms (or 0 if no matched candidates).

**What the doc-comment says.** Lines 1-22 describe the goal as "median time offset between the resulting onsets and the grid's beat times" and the use as `initialDriftMs` so the EMA "starts at the right value rather than chasing it at runtime over the first ~4 s of playback." Lines 20-22 explicitly state sign convention: `offset > 0 → grid beats are LATER than detected onsets`.

**What the doc-comment does NOT acknowledge.** The same Failed Approach #68 root cause that retired the *runtime* onset-based fix (CS.1.y.2) is still live here at *prep time*. The sub-bass onset detector fires on sub-bass *events* (bass notes, 808s, synth bass) — not beats. On a syncopated preview clip, the median (gridBeat − onsetTime) reflects bassline-vs-grid alignment, not on-beat alignment. The 200 ms match window is wider than the live tracker's ±50 ms — so the prep-time calibrator accepts a broader population of off-beat onsets than runtime would.

**Empirical grounding — reproducibility across captures.** The frame-1 `drift_ms` column in features.csv reflects `gridOnsetOffsetMs` at install (before any EMA update). Comparing the first frame's drift per track per capture:

| Track | cap1 | cap2 | cap3 | cap4 | Stable? |
|---|---|---|---|---|---|
| Billie Jean | +10.9 | +10.9 | **+0.0** | +10.9 | 3/4 captures identical; cap3 differs by 11 ms |
| Around the World | +60.3 | +60.3 | +60.3 | +60.3 | identical |
| Seven Nation Army | -8.2 | -8.2 | -8.2 | -8.2 | identical |
| Get Lucky | +14.0 | +14.0 | +14.0 | **+0.0** | 3/4 captures identical; cap4 differs by 14 ms |
| Superstition | +6.4 | +6.4 | +6.4 | +6.4 | identical |
| Everlong | -21.5 | -21.5 | -21.5 | -21.5 | identical |
| Royals | +8.8 | +8.8 | +8.8 | +8.8 | identical |
| HUMBLE. | +0.4 | +0.4 | +0.4 | +0.4 | identical |
| B.O.B. | -4.4 | -4.4 | -4.4 | -4.4 | identical |
| Money | **+0.0** | +29.8 | +29.8 | +29.8 | cap1 differs by 30 ms |

**Finding.** `gridOnsetOffsetMs` is *mostly* deterministic across captures (7/10 tracks identical, 3/10 vary by 11-30 ms when prep re-fires). Where it varies, the magnitude is ≤30 ms — i.e., NOT the dominant cause of the BUG-017 cross-capture median-Δ shifts of 100s of ms. Given the calibrator is pure stateless given input (deterministic FFT setup, deterministic BeatDetector), the 3 cases of variation must come from upstream changes in the prep input — most likely a re-prep with different preview audio bytes (different CDN response on a different day) or a re-run of Beat This! on a slightly different decoded waveform. The audit cannot distinguish these from existing artifacts.

**Empirical grounding — magnitude vs the BUG-017 errors it's supposed to seed.** All 10 seed values are within ±60.3 ms. BUG-017's median-Δ errors range from −329 to +338 ms (cap1 HUMBLE = +338 ms). The seed magnitude is small relative to the error magnitude. Even if the seed were perfectly on-beat (which it isn't — see below), it could not correct the BUG-017 gap. The seed magnitude is bounded by `maxMatchWindow = 0.200` (±200 ms) but the actual values across the catalog are much smaller — most ≤30 ms.

**Empirical grounding — on-beat-ness of the seed.** When the cached preview grid is ½-beat off the track's audible beat (e.g., HUMBLE +338 ms in cap1), the prep-time `GridOnsetCalibrator` runs against the preview's *own* sub-bass events vs the preview's *own* beat grid — both in preview-time. Whether the median offset (in preview-time) corresponds to on-beat or off-beat in the *track* clock is undefined: the calibrator never sees track audio. The HUMBLE seed (+0.4 ms) says nothing about how the cached grid aligns to the actual song. The empirical observation that all 10 seeds are small (and most ≈ 0) means the calibrator is "succeeding" at the preview-vs-preview-grid alignment task — i.e., the preview onsets sit on the preview grid (Beat This! is doing its job). It does not measure preview-vs-track alignment.

**`documented-but-broken`.** The doc-comment describes what the code does, accurately. What the prep+install architecture *claims* the seed achieves (visual that "fires correctly from frame 1" — line 405 of `LiveBeatDriftTracker.swift` and design-doc §4.3) is not what the seed provides. The seed solves the preview-vs-preview-onset latency problem (a small per-track calibration); it does not solve the preview-vs-track phase problem (BUG-017). Both problems were conflated in the BUG-007.8 → CS.1.y.2 → CS.1.y.2-redo sequence; the audit's finding is that they need to be separated.

---

### Component 2 — Cold-start grid install path

**Code locus.** `PhospheneApp/VisualizerEngine+Stems.swift:480-503`:

```swift
if let identity, let cached = stemCache?.loadForPlayback(track: identity) {
    let replacedExisting = mirPipeline.liveDriftTracker.hasGrid
    pipeline.setStemFeatures(cached.stemFeatures)
    // BUG-007.8: pass per-track grid-vs-onset offset as initial drift bias.
    mirPipeline.setBeatGrid(
        cached.beatGrid.offsetBy(0),
        initialDriftMs: cached.gridOnsetOffsetMs
    )
    ...
}
```

**What it actually does.** Installs the prep-time Beat This! grid verbatim (`.offsetBy(0)` shifts by 0 and extrapolates 300 s forward), and seeds the EMA with `gridOnsetOffsetMs` (Component 1b). The visual's `beatPhase01` computation at frame 1 then evaluates `(playbackTime + drift − beats[idx]) / period`, where `playbackTime = 0` at track start, `drift = initialDriftMs / 1000` (clamped ±500 ms), and `beats[idx]` is the nearest preview-time beat at or before `0 + drift`.

**Doc claim under audit.** Design-doc §4.3 (`COLD_START_SYNC_DESIGN_2026-05-20.md:55-61`) states: *"the predicted beat grid's absolute phase is calibrated to where the live onset detector will fire on the actual song's beats — before playback starts. The cold-start phase problem (preview-vs-track offset, BeatThis-vs-sub-bass onset latency, preview-not-on-bar-boundary) is addressed by this calibration."* This claim is what BUG-017 falsifies: `gridOnsetOffsetMs` cannot address the preview-not-on-bar-boundary case because it measures preview-vs-preview-onset latency, not preview-vs-track-bar-phase.

**Empirical grounding.** Cap1's CS.1 baseline shows the per-track median Δ ranges from −128 ms (Money) to +338 ms (HUMBLE), all *track-relative* phase offsets. The frame-1 install grid for HUMBLE was `bpm=76.0, beats=39, initialDrift=+0.4 ms` — the install equates preview-time t=0 with track-time t=0, and the +0.4 ms initial drift is insufficient to correct the +338 ms actual phase error. The visual fires 338 ms ahead of the audible beat from frame 1.

The "3 passing" tracks in cap1 (Around the World +28 ms, Get Lucky +17 ms, Royals +8 ms) are tracks whose preview clip happened to be excerpted from near a bar boundary. The "7 failing" tracks (B.O.B. +10 ms borderline, Billie Jean +69, Superstition −28, Seven Nation Army +93, Everlong −66, Money −128, HUMBLE +338) are off by amounts ≤ ½-beat at the track's tempo — consistent with a uniform distribution over preview-clip bar phases.

**`documented-but-broken`.** The install path's promise (frame-1 beat-phase alignment) is not what the code can deliver under the constraints (preview clip excerpt of unknown track-position). This is BUG-017's original framing and has not been altered by any subsequent fix attempt — every CS.1.y / CS.1.y.2 / CS.1.y.2-redo cycle tried to *correct* this at runtime (post-install) rather than fix the install path itself, because the streaming-only constraint genuinely prevents prep-time correction (the prep input is the preview, full track is not available).

The audit's finding: the install path is structurally incapable of frame-1 phase accuracy on tracks where the preview is not aligned to a bar boundary. The product claim "beat-synced from frame 1 of every track" requires *runtime* correction; runtime correction has been the load-bearing problem for the entire BUG-017 cycle.

---

### Component 3 — Live drift EMA (`LiveBeatDriftTracker.update`)

**Code locus.** `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift:484-584`. Called per-frame from `MIRPipeline.process` (line 319-323): `liveDriftTracker.update(subBassOnset: ctx.beat.onsets[0], playbackTime: elapsedSeconds, deltaTime: ctx.deltaTime)`.

**What it actually does.**

1. On each sub-bass onset (`onsets[0]==true`): find nearest beat to `playbackTime + drift` within `driftSearchWindow = 0.05` (±50 ms). If matched, compute `instantDrift = nearest - pt`, then `drift = (1 - 0.4) × drift + 0.4 × instantDrift` (40% blend toward the instant measurement).
2. If `|instantDrift − drift| < adaptive_window` (acquisition: 30 ms floor; retention: clamp(2σ, 30 ms, 80 ms) of last 16 deviations): increment `matchedOnsets`, accumulate per-slot kick-density histogram for BUG-007.4b auto-rotate.
3. If no onset within window for > 2× medianBeatPeriod: decay drift toward 0 with τ=1 s.
4. Lock state: `unlocked` → `locking` (after first match attempt) → `locked` after 4 tight matches; `locked` → `locking` after the BPM-aware lock-release window of non-tight events (BUG-007.5).
5. Output `beatPhase01` / `barPhase01` from `(playbackTime + drift + displayShift)`.

**Doc claim.** The header comment (lines 1-27) states: *"this tracker only follows playback clock drift and dropped-frame jitter so the live `beatPhase01` stays aligned with the beats the user actually hears."* Read carefully: the EMA follows *drift* between an installed grid and observed onsets, with a ±50 ms search window. The header is honest: it does not claim phase recovery from a wrong grid.

**Empirical grounding — steady-state behaviour under a correct grid.** Cap1 baseline drift ranges over the 10-30 s window per track (this is the "settled" steady-state — outside the cold-start measurement window):

| Track | Cap1 steady drift range | Read |
|---|---|---|
| Money | +24..+56 ms (32 ms range) | tightest — Money has few onsets, EMA barely fires |
| Get Lucky | -12..+12 ms (24 ms) | passing track; EMA tight |
| Royals | -41..-5 ms (36 ms) | passing track; EMA tight |
| Around the World | +8..+46 ms (38 ms) | passing track; small bias toward grid-late |
| Seven Nation Army | -62..-2 ms (60 ms) | failing track; EMA wider |
| Everlong | -66..+9 ms (75 ms) | failing track; EMA pulled by off-beat onsets |
| HUMBLE | -48..+36 ms (84 ms) | failing track at +338 ms median Δ; EMA stays near 0 — onsets at +338 ms are OUTSIDE the ±50 ms match window and rejected |
| Superstition | -53..+34 ms (87 ms) | failing track; EMA wide |
| B.O.B. | -119..-28 ms (91 ms) | passing track at 73% — EMA pulled to a small negative bias |
| Billie Jean | -41..+25 ms (66 ms) | failing track at +69 ms median Δ; EMA bouncing in ±50 ms band |

**Finding.** In the unperturbed CS.1 baseline (no runtime correction code), the EMA's steady-state drift range is 24-91 ms across the catalog. On tracks where the cached grid is ½-beat off (HUMBLE), the EMA cannot bridge the gap because the onsets it would need to match are outside the ±50 ms window — so drift stays near the +0.4 ms seed and the visual stays +338 ms off the audible beat. On tracks where the cached grid is sub-50ms off, the EMA biases drift toward off-beat-but-within-window sub-bass onsets, producing a 30-90 ms wobble.

The doc-comment is honest about what the EMA does. The CS.1.y.2 fix attempt (a runtime gross drift override based on the same off-beat sub-bass onsets) tried to extend the EMA beyond its design envelope and failed for exactly that reason (FA #68).

**Empirical grounding — steady-state behaviour with the CS.1.y.2-redo fix landed (cap3, cap4).** The same column re-computed against the post-fix captures shows the EMA range balloons after the +15 s snap:

| Track | Cap1 (no fix) | Cap3 (round-2 fix) | Cap4 (M7 fix) |
|---|---|---|---|
| Billie Jean | 66 ms | 34 ms | **161 ms** |
| Around the World | 38 ms | **163 ms** | 62 ms |
| Seven Nation Army | 60 ms | **111 ms** | **195 ms** |
| Get Lucky | 24 ms | **180 ms** | 35 ms |
| Superstition | 87 ms | **202 ms** | **130 ms** |
| Everlong | 75 ms | **131 ms** | **119 ms** |
| Royals | 36 ms | **249 ms** | **199 ms** |
| HUMBLE | 84 ms | 21 ms | **300 ms** |
| B.O.B. | 91 ms | **115 ms** | **137 ms** |
| Money | 32 ms | 20 ms | 38 ms |

The snap re-seeds drift to a Beat This!@15s-derived value (sometimes itself wrong by 100s of ms — see Component 5b), and the EMA then attempts to refine. Where the snap landed off-beat, subsequent onsets re-pull drift, producing the 100-300 ms ranges Matt's M7 read as "drift very much real across tracks." The behaviour confirms the audit framing: the EMA + ±50 ms window + post-snap re-seeding is structurally a bad fit for "land at the right phase from any starting condition." It is well-suited to "stay near a known-correct grid."

**`production-active`.** The EMA does what its doc-comment says it does. Its scope (small continuous drift; not gross phase correction) was knowingly extended by CS.1.y.2 and CS.1.y.2-redo and broke in both cases. Component 3 is not the defect; the *use* of Component 3 as a phase-recovery primitive is.

---

### Component 4 — EMA behaviour under a wrong-phase grid (bimodal characterization)

This component is not a separate code locus; it is the *behavioural finding* about Component 3 + Components 1a/1b/2 together. The kickoff's §Scope item 4 asked the audit to characterise it explicitly.

**Regime A: cached grid wrong by < ±50 ms** (sub-window — most "passing" + borderline tracks in cap1).

- The EMA's match window admits sub-bass onsets within ±50 ms of the cached grid's beats.
- On syncopated tracks, those onsets are off-beat sub-bass events (e.g., bassline notes ahead of the kick by ~30-80 ms).
- `instantDrift = nearestBeat − onsetTime` is itself a measurement of where the sub-bass event sits relative to the grid; the EMA pulls `drift` toward that off-beat measurement at 40% blend.
- Steady-state behaviour: drift bounces inside a 30-90 ms band centred on a small bias toward the bassline phase, NOT the beat phase.
- Visual reading: "near-locked but persistently wobbling and biased."
- Examples: cap1 B.O.B. (drift -119..-28 ms, 73% within ±50 ms — borderline pass that feels persistently early); cap1 Billie Jean (drift -41..+25 ms while audible-Δ is +69 ms — wobble around an off-beat bias).

**Regime B: cached grid wrong by > ±50 ms** (super-window — most "failing" tracks in cap1).

- Sub-bass onsets are > 50 ms from any cached grid beat — `nearestBeat(to:within:0.05)` returns nil for every onset.
- The EMA never updates from onsets. `consecutiveMisses` increments; `firstNonTightMatchTime` is set; lock degrades.
- Drift decays toward 0 (no-onset decay) only if there are no onsets for > 2× medianBeatPeriod — which is rare on dense tracks, so drift stays at the seed value.
- Steady-state behaviour: drift parked at the seed (within ±60 ms of zero for all observed tracks); visual stays at preview-grid phase the whole window.
- Visual reading: "stuck off-beat the entire 10 s window."
- Examples: cap1 HUMBLE (+338 ms median Δ, drift -48..+36 ms — drift stays near 0, visual stays +338 ms ahead); cap1 Royals when shifted (+316 ms in cap2 with the onset-fix, but the canonical CS.1 Royals at +8 ms is Regime-A).

**Why both regimes are problematic for BUG-017.** Both produce a visual perceived as out of sync. Regime A produces a smaller phase error but with visible jitter; Regime B produces a larger phase error with no visible recovery. Matt's M7 read of cap4 ("drift very much real across tracks") covers both regimes — the broader the catalog, the more both regimes appear simultaneously.

**`characterized`.** Not a verdict against the code; a behavioural model of what the steady-state tracker does when handed an input it was not designed for. This characterization is *the basis* for understanding why no runtime-only fix to the EMA family can close BUG-017 without a separate primitive that handles gross-phase recovery.

---

### Component 5a — Verifier clock-offset estimation

**Code locus.** `PhospheneEngine/Sources/ColdStartVerifier/ColdStartAnalysis.swift:127-146` (`resolveAudibleBeats`) + `ClockOffset.swift:29-53` (`ClockOffset.estimate`).

**What it actually does.**

1. For each track, compute `coarseS = (first.wallclockS - rawStart) - first.playbackTimeS` — the deterministic per-track raw-tap-vs-playback clock offset derived from the precise CS.1 raw-tap-start CFAbsoluteTime + the first frame's wallclock + the first frame's playback time. Per the CS.1 SessionRecorder change this should be ms-accurate.
2. Replay raw_tap.wav offline through `BeatDetector` to produce `rawOnsets[]` (sub-bass onset timestamps in raw-tap time).
3. Read `beatBass` rising-edges from features.csv (threshold 0.6) to produce `beatBassOnsets[]` (sub-bass onset timestamps in playback time).
4. Pair: for each `beatBass` onset, find all `rawOnsets` within `searchRadiusS = 0.15` of `bass + coarseS`; add `(raw - bass)` to candidate list.
5. Histogram the candidates into 20 ms bins; take the densest bin; return the mean of candidates within that bin (or `coarseS` if no candidates).

**What it assumes.** The pairing is sync-independent: both onset streams come from the same `BeatDetector` algorithm applied to the same physical audio at two clocks. So `raw - bass` for a *correctly matched pair* is purely the clock-origin difference plus algorithmic latency (which cancels between live and offline runs). Mismatched pairs spread across ±beat-period and contribute noise; the histogram mode separates signal from noise.

**Empirical grounding — clock offsets reported per capture.** The verifier reports per-track `clockOffsetS` (refined `offsetS`) — these grow monotonically across the session (each track has more session pre-roll than the last). Cross-capture comparison is moot (different sessions, different pre-rolls). What WOULD be comparable is `(offsetS - coarseS)` — the refinement the histogram applied. The audit cannot extract `coarseS` from the existing artifacts without re-running the verifier with extra logging.

**Gap.** The audit cannot confirm or refute "verifier clock-offset estimate is per-capture noisy" from existing artifacts. Direct test: extend `ColdStartVerifier` to log `coarseS` and `offsetS - coarseS` per track, re-run on the four captures, and check whether the refinement is consistent (low variance) or noisy (variance > 50 ms). One small instrumentation increment.

**Indirect evidence that it is NOT the dominant cause.** The histogram search radius is `searchRadiusS = 0.15` — the refinement is bounded at ±150 ms. Cross-capture median-Δ shifts in BUG-017 are routinely 100s of ms; for the verifier clock-offset to account for them, the histogram would need to shift by >150 ms across captures, which is structurally not possible (the algorithm clamps within ±150 ms of the precise CFAbsoluteTime anchor).

**`unverified-claim`.** Sync-independent in principle; the per-capture stability is not directly measured from existing artifacts. Likely a contributor to cross-capture noise at the ±50-150 ms scale, but cannot explain the dominant cross-capture variability documented in §Q2 below.

---

### Component 5b — Verifier ground-truth Beat This! on raw-tap

**Code locus.** `PhospheneEngine/Sources/ColdStartVerifier/BeatThisGrid.swift:22-34` (`BeatThisGrid.beats(samples:sampleRate:sliceStartS:durationS:analyzer:)`) — runs `DefaultBeatGridAnalyzer.analyzeBeatGrid(samples:sampleRate:)` (= same Beat This! pipeline as production prep) on a 25 s slice of raw_tap.wav starting at `offsetS - 3 s` (3 s lead-in, 25 s total — keeps the spectrogram under Beat This!'s 1500-frame `tMax` at 50 fps).

**What it claims.** `ColdStartAnalysis.swift:5-13`: *"audible beat = a Beat This! beat. Beat This! is re-run offline on a per-track slice of raw_tap.wav (BeatThisGrid) — a genuine beat tracker, one beat per beat."* The verifier treats Beat This! on raw-tap as the audible-beat ground truth.

**Empirical grounding — cross-capture beat-count and BPM reproducibility.** From the cap1 / cap2 redo.1 measurement tables (`cold_start_rediagnosis_10-15-20.md`), the *reference* 25-s Beat This! on raw-tap for the same track produced:

| Track | cap1 ref beats | cap1 ref BPM | cap2 ref beats | cap2 ref BPM |
|---|---|---|---|---|
| Billie Jean | 49 | 115.4 | 49 | 115.4 |
| Around the World | 50 | 120.0 | **47** | 120.0 |
| Seven Nation Army | 50 | 120.0 | 50 | 120.0 |
| Get Lucky | 49 | 115.4 | 49 | 115.4 |
| Superstition | 42 | 100.0 | **43** | 100.0 |
| Everlong | 68 | 157.9 | **66** | 157.9 |
| Royals | 37 | 85.7 | **35** | 85.7 |
| HUMBLE. | 31 | 75.0 | 31 | 75.0 |
| B.O.B. | 68 | 157.9 | **65** | 157.9 |
| Money | 40 | 120.0 | **36** | 120.0 |

**6 of 10 tracks have a different beat count between cap1 and cap2 references.** BPM is stable to one decimal place across captures. Beat *positions* (not just counts) shifted enough to cross the rediag's R-gate in cap2 vs cap1 for several tracks (Seven Nation Army viable at 10 s in cap1, not viable in cap2; HUMBLE viable at 10 s in both captures but the 15 s window dropped to R 0.89 in both).

**Empirical grounding — cross-capture phase reproducibility of the CS.1.y.2-redo runtime snap.** The same fix code installed in cap3 and cap4 (same playlist, same Spotify previews, same builds — just different sessions) produced these `applyColdStartPhaseCorrection` drift values from session.log:

| Track | cap3 snap drift | cap4 snap drift | |Δ| |
|---|---|---|---|
| Billie Jean | -6.0 ms | +79.4 ms | 85 ms |
| Around the World | +209.6 ms | **skipped — live BPM 198.6 vs cached 121.3** | (BPM detection tempo-doubled in cap4) |
| Seven Nation Army | +88.3 ms | -159.9 ms | 248 ms |
| Get Lucky | -109.2 ms | -6.9 ms | 102 ms |
| Superstition | -181.4 ms | +63.4 ms | 245 ms |
| Everlong | +44.3 ms | -116.4 ms | 161 ms |
| Royals | +257.8 ms | +250.1 ms | 8 ms |
| HUMBLE | **skipped — live BPM 88.1** | -248.1 ms | (BPM detection mid-half-time in cap3) |
| B.O.B. | +10.6 ms | -60.8 ms | 71 ms |
| Money | **skipped — R=0.05** | **skipped — R=0.19** | (SFX intro, both fail) |

**Six of ten tracks** have snap drift values differing by ≥85 ms across the two captures. Two tracks have Beat This! detecting different BPMs across captures (Around the World tempo-doubled in cap4; HUMBLE between-half-time in cap3). Only Royals is reproducible to ≤10 ms.

**Why this is the dominant cause of cross-capture median-Δ variability.** Beat This! on a 15 s or 25 s slice of live tap audio depends on per-capture acoustic context (system mixer state, codec timing, tap-driver buffering, ambient noise floor differences). The transformer's beat-activation outputs shift slightly between captures, and the resolver's peak-pick + downbeat snap can output a grid shifted by a fraction of a beat. For tracks with ambiguous metric structure (syncopated bass, half-time perception, polyrhythmic accents), the shift can be a half-beat or a tempo octave.

**This contradicts the redo.1 measurement's "10/10 viable at 15 s" finding** in the production case. Redo.1 measured `BeatThis!@15s_capA vs BeatThis!@25s_capA` (same slice, two slice lengths) — that is reproducible to ≤8 ms because the transformer is fed nearly-overlapping inputs. The production case is `BeatThis!@15s_capA vs BeatThis!@15s_capB` (same slice length, two captures) — which is the comparison the redo.1 measurement did NOT make. This is the measurement-design gap called out in the `[dev-2026-05-24-a]` durable-learning note.

**`production-active-but-broken`** as a *cross-capture stable* reference. The Beat This! grid on raw-tap is fine *within one session* (it IS the ground truth available to the verifier in that session) but is not a stable *physical* reference across captures of the same physical audio. Any closeout that uses Beat This!-on-tap to verify a fix's correctness inherits this instability.

The verifier circularity caveat (the CS.1.y.2-redo fix and the verifier use the same detector for comparison) compounds this — a closeout passing the verifier post-fix is *expected by construction* (the snap aligns the cached grid to the same Beat This! output the verifier scores against), so verifier PASS is necessary but not sufficient. M7 is the load-bearing close gate. Matt's M7 verdict on cap4 confirmed this: verifier could not separate "fix works" from "fix made Beat This!-vs-cached agree on a wrong phase."

---

### Component 6 — `BeatDetector` sub-bass onset feed

**Code locus.** `PhospheneEngine/Sources/DSP/BeatDetector.swift:200-257` (`process` returns `Result.onsets[0]` for the sub-bass band) + `:309-331` (`detectOnsets`) + `:362-391` (`recordOnsetTimestamps`). Band 0 is 20-80 Hz; 400 ms per-band cooldown; spectral flux > 1.5× median over 50-frame buffer + cooldown gate.

**Consumers.**
1. `LiveBeatDriftTracker.update(subBassOnset:)` at `MIRPipeline.process` line 320 — the live drift EMA's per-onset input.
2. `GridOnsetCalibrator.computeSubBassOnsets(samples:sampleRate:)` at `GridOnsetCalibrator.swift:73-107` — prep-time onset stream on preview audio.
3. `RawTapAnalysis.analyze(url:)` at `RawTapAnalysis.swift:34-71` — verifier offline onset stream on raw-tap audio.

**What it actually does.** Detects sub-bass *events*: any 20-80 Hz spectral flux peak above adaptive threshold + cooldown gate. On a kick-heavy track with kick on every beat, the events are co-located with beats. On a syncopated track (bass on 1+3, kick on 2+4; or 808 sub on off-beats; or sustained sub-bass with melodic variation), the events are NOT co-located with beats. This is the structural limitation Failed Approach #68 names.

**Empirical grounding — on-beat reliability on syncopated tracks.** The CS.1.y.2 onset-fix attempt (cap2) measured the per-track sub-bass-onset-vs-Beat-This!-beat cluster directly. From the BUG-017 CS.1.y.2 addendum: "Billie Jean's syncopated bassline → onsets −226 ms off the beat; Royals → +316 ms; Get Lucky → +198 ms." These are *tight* clusters (MAD ~10 ms) on per-track *systematic off-beat* offsets — the detector reliably finds sub-bass events at consistent phase offsets from beats.

**Empirical grounding — same defect at runtime in CS.1 baseline.** Per the cap1 HUMBLE failure dive: the EMA stays parked at drift ~0 (within ±50 ms of seed), but the visual-vs-audible Δ is +338 ms. This means the sub-bass onsets that the EMA does match are themselves +338 ms off the audible beat (they sit on the cached grid's beats, which are +338 ms early). The detector is *correctly* finding sub-bass events; those events just aren't beats.

**`production-active-but-broken` as a beat-phase reference.** The detector itself is doing what it claims. The architectural mistake (shared across Components 1b, 3, 5a) is using it as a beat-phase reference rather than a sub-bass-energy proxy. CLAUDE.md's Audio Data Hierarchy is explicit that onsets are Layer 4 (accent only — never primary); the beat-sync wiring routinely treats onsets as a phase primitive.

The detector's other downstream use (driving `beatBass` / `beatComposite` *pulses* — the visualizer's accent layer) is correct and uncontroversial; this audit's finding is scoped to its use as a *phase* reference.

---

## §Q: Six specific empirical questions

The kickoff lists six questions the audit must address or surface as a gap.

### Q1 — `gridOnsetOffsetMs` reproducibility across preps

**Answered (Component 1b).** Mostly deterministic across four captures (7/10 tracks identical; 3/10 vary by 11-30 ms when prep re-ran). Magnitude is ≤30 ms — not the dominant cause of BUG-017's 100s-of-ms median-Δ variability. The deeper finding is that even when reproducible, the seed is *not* a beat-phase measurement — it's a sub-bass-event vs preview-grid latency measurement, susceptible to Failed Approach #68 at prep time.

**What would change the answer.** Direct cross-capture re-running of `GridOnsetCalibrator` on the recovered preview audio per track (the preview audio bytes are not currently archived in the session directory; the cache is). Not blocking the audit; flagged as a one-line instrumentation step for a future fix increment if needed.

### Q2 — Why did the approx-now baseline drift from CS.1's 3/10 PASS to cap-4's 1/10 PASS?

**Answered, compound.** The pre-snap "approx now" measurement window (0-10 s) uses the cached grid + `gridOnsetOffsetMs` seed only (the runtime snap fires at +15 s and lands at +20 s; the M7 capture cap4 had the fix in tree but the snap did not affect the 0-10 s window in the approx-now report).

Components:
1. **`gridOnsetOffsetMs` non-determinism** contributes ≤30 ms shift on 3 of 10 tracks (Component 1b).
2. **Verifier ground-truth Beat This!-on-raw-tap non-reproducibility** (Component 5b) contributes 100s-of-ms shifts on 5-6 of 10 tracks — this is the dominant cause.
3. **Verifier clock-offset estimate per-capture variability** (Component 5a) is structurally bounded at ±150 ms and is not directly measured here, but is at most a secondary contributor.

The 3/10 → 1/10 drop is mostly the verifier itself moving across captures, not the system-under-test moving. The "approximately within ±130 ms" baseline claim CS.1 made was using cap1 as a single sample — across multiple captures, the same cached grids produce different verifier verdicts because the verifier's reference is not stable. This is the durable-learning point in `[dev-2026-05-24-a]` empirically grounded.

### Q3 — EMA behaviour under a wrong-phase grid

**Answered (Component 4).** Bimodal:
- Regime A (wrong by < ±50 ms): EMA biases toward off-beat sub-bass onsets near the wrong-phase grid; 30-90 ms steady-state drift wobble around an off-beat bias.
- Regime B (wrong by > ±50 ms): EMA cannot match any onsets; drift parks near seed; visual stays at preview-grid phase across the whole window.

Both regimes are visible in cap1 baseline data without any synthetic injection — HUMBLE is Regime B (+338 ms median Δ, drift parked at +0.4 ms); Billie Jean is Regime A (+69 ms median Δ, drift bouncing in -41..+25 ms). The kickoff's proposed synthetic-injection experiment would confirm the same conclusion empirically; the natural-data evidence is sufficient for the verdict.

### Q4 — Cross-capture Beat This!@15s reproducibility on a single track

**Answered (Component 5b).** Beat This! on a 15 s slice of live tap audio is **not** cross-capture reproducible on a substantial subset of the catalog. Six of ten tracks have snap-drift differences ≥85 ms between cap3 and cap4 (same fix, same Spotify previews, same builds). Two tracks have Beat This! detecting a different metric grid (Around the World tempo-doubled in cap4; HUMBLE between-half-time in cap3). Only Royals reproduces to ≤10 ms.

Tracks with stable cross-capture phase: Royals (kick-on-the-beat, simple meter), Money (also stable but only because both captures fail Beat This! confidence due to the SFX intro). Tracks with unstable phase: tracks with syncopated bass, half-time perception ambiguity, or polyrhythmic accents — exactly the catalog members the cold-start fix was supposed to help.

The redo.1 measurement validated within-capture / within-slice reproducibility (≤8 ms at 15 s), but did NOT test the production case (cross-capture / different-slice variability). This is the measurement-design gap.

### Q5 — Verifier clock-offset sensitivity

**Surfaced as a gap (Component 5a).** Cannot directly test from existing artifacts. Indirect bound: histogram refinement is clamped at ±150 ms of the precise CFAbsoluteTime anchor, so this is at most a ±150 ms contributor and cannot account for the dominant cross-capture variability. Instrumentation step: log `coarseS` + `offsetS - coarseS` per track in `ColdStartVerifier` and re-run on the four captures. One-line addition; not part of this audit.

### Q6 — `BeatDetector.onsets[0]` (sub-bass) reliability per track

**Answered indirectly (Component 6).** Per-track on-beat reliability cannot be measured from the natural-data captures without comparing the detector's output to a ground-truth beat reference *that is itself stable* — which Component 5b shows is not currently available. But the CS.1.y.2 onset-fix telemetry already produced per-track sub-bass-vs-Beat-This!-beat clusters (Billie Jean −226 ms; Royals +316 ms; Get Lucky +198 ms; full set in BUG-017 CS.1.y.2 addendum). Those data are sufficient evidence that the detector fires on systematic off-beat sub-bass events on syncopated tracks.

A direct per-track distance distribution against full-window Beat This! ground truth (rather than the 10-s window the CS.1.y.2 fix used) would be a 1-2 hour offline analysis; out of audit scope.

---

## Ranked root-cause hypotheses

Given the three empirical observations (cross-capture non-reproducibility, EMA drift bouncing 200-300 ms in cap3/cap4, baseline degradation 3/10 → 1/10), the audit ranks candidate causes by evidence weight.

### Hypothesis 1 — Beat This!-on-tap is not a stable cross-capture reference (Component 5b)

**Supporting evidence (strongest).**
- Cap3 vs cap4 snap-drift differences ≥85 ms on 6 of 10 tracks (same code, same fix, same songs).
- Cap1 vs cap2 reference beat-counts differ on 6 of 10 tracks (same songs, same Spotify previews).
- The CS.1.y.2-redo fix's verifier-passing cap3 result was followed by an M7-failing cap4 — the verifier and M7 disagreed *because the verifier's reference was different across captures*.
- The CS.1.y.2-redo design assumed Beat This!@15s was reproducible (basis: redo.1 measurement). That measurement did not test the production case.

**Contradicting evidence.** Beat This! BPM is stable across captures (one-decimal-place agreement on every track). Beat *positions* (not aggregate properties) are what shift.

**Verdict.** Strongest evidence. This is the dominant root cause of the BUG-017 cycle's non-convergence: every measurement that defined "correct" depended on a reference that was moving.

### Hypothesis 2 — Sub-bass onset detector is used as a beat-phase reference in three places, all of which fail FA #68 (Component 6)

**Supporting evidence.**
- Prep-time `GridOnsetCalibrator` uses sub-bass onsets vs preview grid (Component 1b). Even when reproducible, the seed is off-beat on syncopated previews.
- Runtime `LiveBeatDriftTracker` matches sub-bass onsets within ±50 ms of cached grid (Component 3). On wrong-phase grids, biases drift to off-beat onsets (Regime A) or rejects everything (Regime B).
- Verifier `ClockOffset.estimate` pairs sub-bass onsets across clocks (Component 5a). Sync-independent in principle but per-capture noise-sensitive within ±150 ms.
- CLAUDE.md Failed Approach #68 (added 2026-05-22) explicitly names this for the runtime fix that was reverted. The audit's finding is that the *same root cause* is still alive at prep time and present (more weakly) in the verifier.

**Contradicting evidence.** None — the three uses are independently confirmed by code reading and the runtime use was demonstrably broken in cap2.

**Verdict.** Robust. Contributing cause to the structural problem; less load-bearing than Hypothesis 1 for the cross-capture variability but the dominant cause of the *systematic offset* on syncopated tracks.

### Hypothesis 3 — The cold-start grid install path equates preview-time with track-time (Components 1a/2)

**Supporting evidence.**
- CS.1 cap1 baseline: 7 of 10 tracks fail by amounts ≤ ½-beat at the track's tempo — consistent with a uniform random preview-clip bar phase.
- HUMBLE +338 ms / Royals +8 ms / Around the World +28 ms — the spread *is* the preview-clip-bar-phase distribution.
- Code: `cached.beatGrid.offsetBy(0)` at `VisualizerEngine+Stems.swift:485` does no track-time shift.
- Architectural: streaming-only constraint genuinely prevents prep-time correction (no full-track audio).

**Contradicting evidence.** None — this is BUG-017's original framing and is well-established.

**Verdict.** Robust. The *static* defect that no fix has addressed (every fix attempted has been a runtime correction post-install). The structural reason every cold-start fix has tried to apply a one-shot drift override.

### Hypothesis 4 — Verifier clock-offset estimate per-capture noisy (Component 5a)

**Supporting evidence.** Algorithmic — histogram refinement uses noisy sub-bass onsets (FA #68 territory).

**Contradicting evidence.** Bounded at ±150 ms by `searchRadiusS`. Likely a ±50-150 ms noise contributor, not a 100s-of-ms cause.

**Verdict.** Likely contributor at small scale. Cannot account for the dominant cross-capture variability. Needs a one-line instrumentation step to quantify.

### Hypothesis 5 — `gridOnsetOffsetMs` non-determinism (Component 1b)

**Supporting evidence.** 3 of 10 tracks have prep-time seed values that vary across captures by 11-30 ms.

**Contradicting evidence.** Magnitude is small; the affected tracks (Billie Jean, Get Lucky, Money) don't have the largest cross-capture median-Δ shifts.

**Verdict.** Real but minor contributor. The source of the non-determinism (preview audio bytes? prep re-fired with different input?) is itself a gap.

### Hypothesis 6 — Some compound interaction not characterised above

**Supporting evidence.** The five fix increments without convergence (CLAUDE.md Failed Approach #58 pattern at infrastructure scope) suggest the system is more brittle than any single fix has assumed. The redo.2 snap interacts with the EMA's continued operation; the EMA interacts with the BUG-007.5 tight gate; the verifier reference interacts with the snap output. Each interaction has been individually understood but the *system* has not been characterised end-to-end on a stable input.

**Verdict.** Plausible. The audit's finding is that the five fix increments each addressed ONE component without retiring the upstream limitations from the other components. Hypothesis 6 is what's left over after Hypotheses 1-3 explain most of the variability — likely small but not zero.

### Summary ranking

| Rank | Hypothesis | Contribution to cross-capture variability | Contribution to systematic-on-syncopated-tracks offset |
|---|---|---|---|
| 1 | Beat This!-on-tap not cross-capture reproducible (5b) | **Dominant** (100s of ms on 6/10 tracks) | Small |
| 2 | Sub-bass onsets as beat-phase reference (6, 1b, 3, 5a) | Small (per-capture <50 ms noise) | **Dominant** (per-track systematic 100s of ms) |
| 3 | Cold-start install: preview-time as track-time (1a/2) | None (static) | **Dominant** (BUG-017's original static defect) |
| 4 | Verifier clock-offset noise (5a) | Small (±50-150 ms) | Small |
| 5 | `gridOnsetOffsetMs` non-determinism (1b) | Small (≤30 ms on 3/10) | None |
| 6 | Compound interactions | Residual after 1-5 | Residual after 1-5 |

The structural insight: **two distinct defect classes are at play simultaneously.** The systematic-on-syncopated-tracks offset (Hypothesis 3 + 2) is what BUG-017 originally named. The cross-capture variability (Hypothesis 1) is what surfaced during the CS.1.y.2-redo cycle when multiple captures were taken and compared. The fix attempts to date have implicitly assumed Hypothesis 3 was the only defect and that Hypothesis 1's reference was stable — both assumptions fail.

---

## Per-component fix scope sketches

These are sketches per the kickoff's done-when item — not commitments, not next-increment scopes. **No fix code in this audit increment.** Matt's sign-off on which (if any) of these to pursue is the next step.

### Component 1b — Retire `GridOnsetCalibrator` from prep time, or reframe its output

**Sketch.** The calibrator is the only remaining production use of sub-bass-onset-vs-grid alignment as a phase reference (Failed Approach #68 still live). Three options:

1. **Delete** `GridOnsetCalibrator` from prep; pass `initialDriftMs = 0` to every install. The seed is small (≤30 ms typical) and only marginally useful even when reproducible; on syncopated tracks it pulls the EMA in the wrong direction. Smallest code change; removes one source of FA #68 contamination.
2. **Reframe** the calibrator's output as a *detection-latency* measurement (BeatDetector tap-vs-output bias) rather than a track-start phase measurement. The header doc-comment already lists "Beat This!'s intrinsic detection latency vs our onset detector's latency" as one of the offset components; that one IS legitimately measurable from preview alone (it's an algorithmic latency, not a phase). The other listed components (clip-not-on-bar-boundary, kick attack envelope variance, sub-bass leakage) are the off-beat-event contamination. Cleaning this up means producing a per-track detection-latency value that's smaller and less varied.
3. **Replace** with a different signal entirely (e.g., onset-strength envelope cross-correlation against Beat This! beat probabilities, in the band Beat This! uses for its broadband perceptual detection — see Hypothesis 2's analysis). Larger scope; unproven; would need its own design increment.

**Risk.** Low for option 1 (deletion); the seed is small and the EMA converges from drift=0 in ~4 onsets per the existing design. Medium for options 2-3.

### Component 2 — Cold-start install: stop pretending preview-time is track-time

**Sketch.** The streaming-only constraint genuinely prevents prep-time phase correction. The install path's options are:

1. **Document the limitation honestly** in CLAUDE.md and product copy: "approximately beat-synced from frame 1; exact phase recovered within ~20 s." The 2026-05-22 decision (`[dev-2026-05-22-b]`) already adopted this framing; the audit confirms it as the correct product-level position given the structural constraint.
2. **Lower the install's confidence claim** for the cold-start window by setting `lockState` to `.unlocked` (or a new `.coldStart` state) for the first 1-2 s, so presets that gate on lock-state don't accent-pulse on a known-suspect grid. Decouples "grid installed" from "grid trusted." Small touch in `LiveBeatDriftTracker`; preserves the existing API.
3. **Some future architecture** (not in this audit's scope) — local-file caching, full-track audio acquisition path, etc. Matt has explicitly deprioritized these per `COLD_START_SYNC_DESIGN_2026-05-20.md §2`.

**Risk.** Low. The fundamental architectural constraint is real and non-negotiable for the foreseeable future; documenting it correctly is most of what option 1 needs.

### Component 3 — `LiveBeatDriftTracker`: keep narrow, do not extend

**Sketch.** The EMA does its designed job correctly. The audit's recommendation is to *stop* trying to extend it for gross phase correction (which CS.1.y.2 and CS.1.y.2-redo both did) and instead keep it as a steady-state drift tracker.

**Risk.** None — this is "do not change Component 3."

**Implication for any future fix.** Any new mechanism that wants to make a gross phase correction at runtime needs its own primitive, distinct from the EMA, with its own evaluation criteria and its own diagnostic instrumentation (per CLAUDE.md "diagnostic infrastructure precedes fidelity claims"). The retired `applyColdStartPhaseCorrection` was such a primitive; its failure mode was using the same FA #68-prone sources (Beat This!-on-tap with the verifier-circularity caveat).

### Component 5a — Verifier clock-offset: instrument and characterise

**Sketch.** One-line addition to `ColdStartAnalysis.makeContext` to log `coarseS` and `offsetS - coarseS` per track. Re-run the verifier on the four captures. If the refinement is consistent (low variance), the verifier clock-offset is not a contributing factor and Hypothesis 4 is closed. If noisy, escalate. ≤1 hour instrumentation increment.

**Risk.** None (read-only instrumentation).

### Component 5b — Find or build a cross-capture-stable reference

**Sketch.** The biggest open question. The audit's strongest finding is that Beat This!-on-tap is not stable across captures on the catalog Matt actually listens to. Without a stable reference, no verifier-based closeout is trustworthy and no fix can claim convergence.

Three exploratory directions (any of which is a *separate research increment*, not a fix):

1. **Bigger Beat This! window.** Does Beat This! on the *entire* tap (not a 25 s slice — the full length of the recorded session for that track) produce cross-capture-stable beat positions? If yes, the slice length and acoustic-context sensitivity are the cause and a 60-90 s post-onset window might be a stable reference for after-the-fact verification (not for live phase recovery, which has a budget). Bounded measurement.
2. **Human-tap reference.** Build a small tap-tempo tool to let Matt produce a per-track ground truth by tapping along to playback. 1-track ≈ 20 s of work; 10-track catalog ≈ 4 min. Closes the cross-capture problem by construction (the human is the stable reference) but is a finite, manual artifact.
3. **External reference.** Spotify's `/audio-analysis` is deprecated; other services (Cyanite, ACRCloud, etc.) don't provide per-beat times at the required precision. Off the table per `COLD_START_SYNC_DESIGN_2026-05-20.md §2`.

**Risk.** Low for options 1-2 (research / data-collection). Both are pre-requisites for any future BUG-017 fix that wants to claim convergence.

### Component 6 — `BeatDetector` sub-bass: do not use as beat-phase reference

**Sketch.** The detector itself does not need to change; what changes is *what it's used for*. Components 1b, 3, 5a all use sub-bass onsets as a beat-phase reference (Failed Approach #68 territory). Component 6's fix is to retire those uses (per the sketches above for 1b, 3, 5a), not to alter the detector.

**Risk.** None — Component 6 stays exactly as it is.

---

## Follow-up backlog

These are candidate increments arising from the audit. **None are scoped for the audit increment itself.** All require Matt's sign-off on direction before scheduling.

| ID | Subject | Trigger | Risk |
|---|---|---|---|
| BSAudit-FU-1 | Refine BUG-017 symptom statement against the audit findings | This audit | None — doc-only |
| BSAudit-FU-2 | Decision on Component 1b retirement (delete / reframe / replace) | Hypothesis 2 ranking | Low if delete; Medium if replace |
| BSAudit-FU-3 | Add a "cold-start window" lock-state distinction (Component 2 sketch option 2) | Honesty about preview-grid limitation | Low |
| BSAudit-FU-4 | Instrument verifier clock-offset `coarseS` / refinement (Component 5a) | Close Hypothesis 4 | None (read-only) |
| BSAudit-FU-5 | Research increment: cross-capture-stable reference (Component 5b sketches 1 or 2) | Hypothesis 1 — load-bearing for any future BUG-017 closeout | Low (research-only) |
| BSAudit-FU-6 | Update CLAUDE.md Audio Data Hierarchy with "onsets are not even a reliable phase reference" extension to FA #68 | Make the same rule general so future code doesn't re-introduce | None — doc-only |

The Phase CS-scope decision Matt made on 2026-05-22 ("approximately synced immediately, locked within ~20 s") remains the right product-level position; the audit confirms that the streaming-only constraint structurally enforces it. The next-increment question is therefore *not* "fix BUG-017 to ≤50 ms by frame 1" but: which of FU-2 / FU-3 / FU-4 / FU-5 / FU-6 are worth scoping, in what order, given that no fix to date has produced perceptual convergence and the audit's strongest finding is that the *verification infrastructure itself* is not currently capable of judging convergence reliably.

---

## Hard rules followed

- **No fix code in this audit increment.** Confirmed: zero code changes proposed inside this document; every recommendation is a sketch under §Fix scope sketches and requires sign-off.
- **Empirical grounding per verdict.** Every verdict above cites session-level evidence (features.csv frame-1 drift, session.log BeatGrid install lines, verifier reports `cold_start_report*.md`, rediag tables, log lines for `applyColdStartPhaseCorrection`).
- **No verdict on broken proxies.** Where evidence is insufficient (Component 5a, the synthetic-injection experiment for Component 4), the audit reports the gap rather than claiming a verdict.
- **Stop and report when scope expands.** The six components scoped in the kickoff §Scope are the boundary; the audit did not expand to other parts of the wiring (e.g., the BUG-007.x lock state machine details, the BUG-013 odd-meter detection, the BUG-007.9 hybrid recalibration — all of these would be in scope for a fuller follow-up but are not here).
- **Verify Matt's current intent before trusting "what stays unchanged" claims.** The CS.1.y.2-redo redo.1 measurement's "10/10 viable at 15 s" claim is explicitly tested in §Q4 and falsified by the cap3/cap4 cross-capture comparison. The audit does not carry forward any of the CS.1.y.2-redo's structural assumptions into the verdicts.

---

— Claude (2026-05-24, audit-only)

---

## Addendum — BSAudit.2 (Path A) findings (2026-05-24)

The BSAudit deliverable above identified BSAudit-FU-5 (cross-capture-stable reference research) as the critical follow-up gate. Path A — "is Beat This!-on-tap reproducible across captures at *some* slice configuration?" — was scoped as the cheaper of two options (Path B being human-tap ground truth). BSAudit.2 implements two measurement modes in `ColdStartVerifier` (`--position-sweep` for within-capture, `--cross-capture` for across captures) and runs them on the four reference captures. **Findings are decisive: no slice configuration salvages Beat This!-on-tap as a stable reference.**

### Code (research-only — no production code touched)

| File | Purpose |
|---|---|
| [`BeatPhaseStats.swift`](../../PhospheneEngine/Sources/ColdStartVerifier/BeatPhaseStats.swift) | Shared circular-mean phase math + median-IOI. ReDiagnosis factored to use it. |
| [`PositionSweep.swift`](../../PhospheneEngine/Sources/ColdStartVerifier/PositionSweep.swift) + [`PositionSweepReport.swift`](../../PhospheneEngine/Sources/ColdStartVerifier/PositionSweepReport.swift) | Path A.1: for each track, Beat This! at sliding 25 s slices (default 10 s stride). |
| [`CrossCapture.swift`](../../PhospheneEngine/Sources/ColdStartVerifier/CrossCapture.swift) + [`CrossCaptureReport.swift`](../../PhospheneEngine/Sources/ColdStartVerifier/CrossCaptureReport.swift) | Path A.2: across multiple sessions of the same playlist, compare same-position-25s-slice grids vs first-session reference. |
| [`ColdStartVerifierCommand+PathA.swift`](../../PhospheneEngine/Sources/ColdStartVerifier/ColdStartVerifierCommand+PathA.swift) | CLI runners; flag wiring in the main command file. |

Engine suite: **1265 / 1265 pass** (baseline preserved). `--self-test`: PASS (7/7). Project-wide `swiftlint --strict`: 0 violations across 386 files.

### Path A.1 — Within-capture position sensitivity

For each track, Beat This! is run on the first 25 s slice (reference) and at sliding 10 s strides up to 6 positions. Per-position phase residual vs position-0 reference, signed ms.

| Track | cap1 spread | cap2 spread | cap3 spread | cap4 spread | Reading |
|---|---|---|---|---|---|
| Billie Jean | **384 ⚠** | **389 ⚠** | **382 ⚠** | **410 ⚠** | persistent: always position-unstable, always spans ~400 ms |
| Around the World | **397 ⚠** | **388 ⚠** | **393 ⚠** | 45 (short slice) | persistent on full-length captures |
| Seven Nation Army | 34 | 35 | 43 | 19 | always stable |
| Get Lucky | **218 ⚠** | **83 ⚠** | **180 ⚠** | 45 (short slice) | usually unstable |
| Superstition | **344 ⚠** | **244 ⚠** | **108 ⚠** | **96 ⚠** | always unstable, magnitudes shrinking over captures |
| Everlong | 39 | 46 | 44 | 21 | always stable |
| Royals | **310 ⚠** | **183 ⚠** | **264 ⚠** | 40 (short slice) | usually unstable; monotonic drift signature |
| HUMBLE | 25 | 12 | 1 | 4 | always stable |
| B.O.B. | **286 ⚠** | **161 ⚠** | **195 ⚠** | **113 ⚠** | always unstable |
| Money | **116 ⚠** | **120 ⚠** | **145 ⚠** | **108 ⚠** | always unstable |

**Position-unstable count per capture:** cap1: 7/10. cap2: 7/10. cap3: 7/10. cap4: 4/10 (3 tracks ran with too few positions to flag).

**Pattern.** The same 7 tracks (Billie Jean, Around the World, Get Lucky, Superstition, Royals, B.O.B., Money) are persistently position-unstable across every capture. The same 3 tracks (Seven Nation Army, Everlong, HUMBLE) are persistently position-stable.

**Two qualitative behaviours seen.**

1. **Monotonic phase drift.** Get Lucky (cap1: 0/-14/-50/-106/-161/-218 ms) and Royals (cap1: 0/+14/+68/+143/+224/+310 ms) show a near-linear march in phase residual as the slice moves further from track start. This means Beat This! is detecting a slightly *different tempo* at each position — the residual accumulates with the inter-position distance. Beat This! on a 25 s slice is not just shifting phase, it's misestimating period.
2. **Erratic large jumps.** Billie Jean (cap1: 0/-29/-114/-247/+137/-12 ms — the +137 ms is a half-period flip) and Around the World show wild swings including sign flips. Beat This! is locking onto fundamentally different metric interpretations at different positions, jumping between (e.g.) on-beat and off-beat downbeats.

Either behaviour is fatal for using Beat This!-on-tap as a stable verification reference.

### Path A.2 — Cross-capture reproducibility

Same-position (slice starting at playback-time 0) 25 s Beat This! across all 4 captures, with cap1 as the reference. Per-session phase residual vs cap1 reference.

| Track | cap2 vs cap1 | cap3 vs cap1 | cap4 vs cap1 | max \|Δ\| | viable? |
|---|---|---|---|---|---|
| Billie Jean | -221 | +94 | +86 | 221 | ✗ |
| Around the World | -123 | -120 | +100 | 123 | ✗ |
| Seven Nation Army | +101 | -163 | -204 | 204 | ✗ (was within-capture stable!) |
| Get Lucky | -183 | -18 ✓ | +85 | 183 | ✗ |
| Superstition | +120 | +19 ✓ | +189 | 189 | ✗ |
| Everlong | -89 | -113 | +95 | 113 | ✗ (was within-capture stable!) |
| Royals | -294 | -255 | +288 | 294 | ✗ |
| HUMBLE | +68 | +8 ✓ | -322 | 322 | ✗ (was within-capture stable, cap4 breaks it) |
| B.O.B. | -112 | +2 ✓ | +135 | 135 | ✗ |
| Money | +153 | +103 | +193 | 193 | ✗ |

**Result: 10 of 10 tracks cross-capture-unstable.** Even Seven Nation Army, Everlong, and HUMBLE — the within-capture-stable tracks — are cross-capture unstable. HUMBLE especially: stable to within 1-25 ms within every capture, but cap4 reads -322 ms different from cap1 at the same playback-time.

### What this means

**Path A is empirically falsified.** No 25 s slice configuration of Beat This!-on-tap is reproducible:

- *Across positions within one capture:* 7 of 10 tracks fail by 100-400 ms.
- *Across captures at the same position:* 10 of 10 tracks fail by 100-322 ms.
- *No subset of tracks survives both:* HUMBLE is within-capture-stable but cross-capture-fails. Get Lucky is partially cross-capture stable (cap3 only) but always position-unstable.

A stable longer/stitched window is highly unlikely to rescue this — Beat This! detects different metric interpretations of the same physical audio depending on (a) where the 25 s window starts within the track and (b) which capture's tap audio is fed in. A longer window stitched from multiple 25 s passes would have to RECONCILE conflicting interpretations Beat This! itself produces; that reconciliation is not a feature of the model.

This *empirically confirms* BSAudit's Hypothesis 1 at maximum strength: Beat This!-on-tap is structurally not a cross-capture-stable beat-phase reference for the catalog Matt actually listens to. Within the streaming-only architectural constraint, the verification infrastructure required to judge fix-claim trustworthiness for BUG-017 does not currently exist.

### Implication for the BSAudit follow-up backlog

| Item | Status after BSAudit.2 |
|---|---|
| BSAudit-FU-5 Path A | **Closed (empirically falsified)**. Beat This!-on-tap is not a viable cross-capture reference at any 25 s slice configuration; longer-window stitching cannot reconcile conflicting Beat This! outputs. |
| BSAudit-FU-5 Path B | **Promoted to load-bearing.** Human-tap reference is now the only remaining route to a cross-capture-stable verification ground truth. |
| BSAudit-FU-1 (refine BUG-017 symptom) | Already done in 2026-05-24 addendum; nothing to add. |
| BSAudit-FU-2 (retire `GridOnsetCalibrator` from prep) | Still pending Matt sign-off. Independent of FU-5. |
| BSAudit-FU-3 (cold-start lock-state distinction) | Still pending Matt sign-off. Independent of FU-5. |
| BSAudit-FU-4 (verifier clock-offset instrumentation) | Still cheap (≤1 hour). Independent of FU-5. |
| BSAudit-FU-6 (CLAUDE.md FA #68 generalisation) | Still cheap (doc-only). Independent of FU-5. |

**The fork in the road.** Two product-level positions are now distinguishable:

1. **Build the human-tap reference** (Path B). Unblocks any future BUG-017 fix-claim because it gives the verifier a stable ground truth. Cost: a small CLI tool + Matt taps along to the 10-track catalog during playback (~4 min of taps + ~1 session of tooling).
2. **Accept the structural limit and document.** Adopt the 2026-05-22 product-direction ("approximately synced immediately, locked within ~20 s") as the canonical position; recast the verifier as "useful for relative comparisons within one capture, not as an absolute judge across builds." Cost: documentation only.

The audit does not pick between (1) and (2); that is a product-strategy decision for Matt. Either is consistent with the empirical findings.

### Capture reports

Generated per-capture (in each session directory):
- `cold_start_position_sweep.md` — per-capture per-track per-position phase residual table.
- `cold_start_cross_capture.md` (in cap1 directory) — pairwise cross-capture table for all 4 captures.

### Hard rules followed

- **No fix code.** All four new modules + the CLI runner are sibling to production code; the production beat-sync wiring is untouched.
- **Engine suite green:** 1265 / 1265 (pre-BSAudit.2 baseline preserved).
- **Lint:** 0 violations across 386 files.
- **Empirical grounding:** every claim in this addendum cites the capture reports + per-track numeric evidence.

— Claude (2026-05-24, BSAudit.2, research-only)


---

## Addendum — BSAudit.3 closeout (Matt's Choice A decision, 2026-05-25)

This audit's load-bearing follow-up (BSAudit-FU-5) was resolved via a different path than the two it framed. Rather than Path A (Beat This!-on-tap as cross-capture-stable reference — empirically falsified in [BSAudit.2](#addendum--bsaudit2-path-a-findings-2026-05-24)) or Path B (human-tap ground truth — not built), Matt chose a third path 2026-05-24: a design-first re-architecture of the cold-start contract itself. **BSAudit.3** = design + impl + validate + diag + close, 2026-05-24 → 2026-05-25.

**BSAudit.3.impl** ([`docs/BPM_ANCHORED_PHASE_ACQUISITION_DESIGN_2026-05-24.md`](../BPM_ANCHORED_PHASE_ACQUISITION_DESIGN_2026-05-24.md), commits `efaf8cb4..30d032ea`) replaced the "trust cached grid phase" + "snap to live Beat This!" approaches with **BPM-prior + broadband-peak phase acquisition + confidence-gated accents**:

- `GridOnsetCalibrator` retired entirely — this audit's Component 1b finding (Failed Approach #68 still live at prep) was resolved.
- `cached.beatGrid.bpm` consumed via `MIRPipeline.installBPMPrior(bpm:character:beatsPerBar:)`; the cached beat *positions* are no longer used (this audit's Component 1a + Component 2 mis-use retired).
- `LiveBeatDriftTracker` reworked to anchor phase on the first broadband-flux peak (`SpectralAnalyzer.smoothedFlux`, not sub-bass — this audit's Component 6 finding addressed), accumulate confidence via an EMA, and emit `accentConfidence ∈ [0, 1]`. `MIRPipeline.buildFeatureVector` multiplies the beat-rate accent fields by this scalar (design §6.5).
- `RhythmCharacter` pre-analysis metadata extends `CachedTrackData` for per-track tunable scaling.

**BSAudit.3.validate** ([`BSAUDIT_3_HISTORICAL_BASELINE_2026-05-25`](../diagnostics/BSAUDIT_3_HISTORICAL_BASELINE_2026-05-25.md), commits `515f9b89`, `cf83037c`) added a new verifier mode `--accent-window-pass-rate` per the architecture's design §8: scores "did a `beatComposite` rising-edge fire within ±60 ms of each audible beat?" with PASS-firing | PASS-degraded | FAIL verdicts. Historical baseline against pre-impl captures: all 30 track samples PASS-firing at ≥ 95 %.

**BSAudit.3.diag.1** ([`BSAUDIT_3_VALIDATE_3_DIAG_2026-05-25`](../diagnostics/BSAUDIT_3_VALIDATE_3_DIAG_2026-05-25.md), commit `346f7487`) ran the verifier against a fresh post-impl capture `2026-05-25T15-20-49Z`. **Aggregate FAIL — 4 of 10 tracks pass.** The verifier was extended with a per-track diagnostic block (first broadband peak time + residual, first accent fire + residual, confidence/lock-state timings, per-fire residual distribution) and produced three structurally-grounded findings:

1. **Broadband-flux-as-phase-anchor is unsound.** 5 of 10 tracks anchored > 100 ms off the nearest audible beat (Billie Jean −212 ms, ATW −231 ms, SNA −291 ms, Royals −516 ms, B.O.B. −309 ms). Consistently negative residuals indicate broadband flux fires on *pre-beat* content (pad swells, vocal entries, hi-hat lead-ins) — the same architectural shape as Failed Approach #68 at the broadband layer.
2. **Confidence accumulator does NOT back-pressure off-anchor lock.** Design §9.1's mitigation falsified: HUMBLE (anchor −68 ms) reached confidence 0.9; Billie Jean (anchor −212 ms) reached 1.0. Periodic broadband content at quarter-note rates reinforces *any* phase that matches the period prior, not just the on-beat one.
3. **`--accent-window-pass-rate` metric is gameable by accent over-firing.** Billie Jean: 25+ accent fires in 10 s vs 19 audible beats; per-fire median |residual| = 109 ms; metric reads 95 % PASS-firing. "Any accent within ±60 ms of each beat" is trivially satisfied by accent over-firing.

The fresh capture demonstrated this audit's worst case: **six iterations on the same defect (CS.1 → CS.1.y.2 → CS.1.y re-diag → CS.1.y.2-redo r1+r2 → BSAudit.3.impl), each using a different mechanism, none converging on > 70 % of catalog.** This is the project-scope twin of Failed Approach #58 (Drift Motes at preset scope), now codified as **Failed Approach #69**. The premise the six iterations did not change — "some automated signal in the first ~3 s of tap audio reliably gives audible beat phase of a novel track" — is empirically falsified.

### Resolution

**Matt's Choice A decision (2026-05-25):** retain BSAudit.3.impl as the production cold-start architecture (gated accents + graceful degradation is a real improvement); accept the ±60 ms / 3 s perceptual sync sub-goal as structurally unachievable; document the contract honestly.

- Production architecture stays at `30d032ea` (BSAudit.3.impl.3).
- `ColdStartVerifier --accent-window-pass-rate` mode + per-track diagnostic block stays as diagnostic infrastructure.
- CLAUDE.md §Cold-Start Phase Contract documents the achievable contract (continuous-energy from frame 1; BPM-prior + confidence-gated accents; graceful degradation on hard tracks).
- CLAUDE.md Failed Approach #69 retires further automated short-window cold-start beat-phase derivation.
- BUG-017 status: **Resolved against accepted structural limit.**
- BSAudit-FU-5 Path B (human-tap reference) remains a viable future direction if perceptual-sync requirements ever change; not currently scoped.

### What this audit's per-component verdicts now read like post-closeout

| Component | Pre-closeout verdict | Post-closeout state |
|---|---|---|
| 1a. Prep-time Beat This! grid | `production-active-but-broken` (for phase) | **Resolved** — `installBPMPrior` consumes BPM only; cached beat positions no longer used for phase. |
| 1b. Prep-time `gridOnsetOffsetMs` | `documented-but-broken` | **Resolved** — `GridOnsetCalibrator` retired entirely. |
| 2. Cold-start grid install | `documented-but-broken` | **Resolved against accepted limit** — install path now BPM-only; per-track phase offset accepted as residual limit per CLAUDE.md §Cold-Start Phase Contract. |
| 3. Live drift EMA | `production-active` | Unchanged at the API; semantics now driven by the BSAudit.3 confidence accumulator rather than the legacy ±50 ms hard match. |
| 4. EMA under wrong-phase grid | `characterized` (bimodal) | Superseded — BSAudit.3.impl no longer installs a wrong-phase grid; the wrong-anchor problem now lives at the broadband-peak phase acquisition layer, characterized in `BSAUDIT_3_VALIDATE_3_DIAG_2026-05-25.md`. |
| 5a. Verifier clock-offset | `unverified-claim` | Unchanged — instrumentation step never executed; not load-bearing for the closeout. |
| 5b. Beat This!-on-tap reference stability | `production-active-but-broken` (cross-capture) | **Accepted as known limit** — the `ColdStartVerifier --accent-window-pass-rate` mode is within-capture-only by design per Path A falsification. Cross-capture comparisons remain out of scope for any future verifier use. |
| 6. `BeatDetector` sub-bass onset | `production-active-but-broken` (as phase reference) | **Resolved** — no remaining production code uses sub-bass onsets as a phase reference. The detector's onset-stream use for beat-pulse fields (Layer 4 accents) remains correct and uncontroversial. |

— Claude (2026-05-25, BSAudit.3.close)
