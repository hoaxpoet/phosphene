Increment DSP.4 — Drums-stem Beat This! diagnostic: a third BPM
estimator on isolated percussion, logged alongside the existing two.

Authoritative bug record: none — this is an enhancement, not a defect
fix. Tracked in the forward plan as the highest-leverage move toward
"better beat-locking on dense mixes" (BUG-008/BUG-007 conversation,
2026-05-06).
Predecessor commits relevant for context: BUG-008.1 diagnosis
(d1a86f91 + 9c0e561c) and BUG-008.2 fix (9704eefc).

This is a diagnostic-first increment in the spirit of the BUG-006.1
WIRING: instrumentation: do not change runtime behaviour, just add a
third number to the per-track preparation log so future captures
contain the data needed to design fusion logic later. There is no
"fix" being shipped here — just better visibility into what the
estimators are doing.

────────────────────────────────────────
WHY
────────────────────────────────────────
Today, two BPM estimators run on the **full mix** of every prepared
track:

  - TrackProfile.bpm — DSP.1 trimmed-mean IOI on sub_bass (kick rate).
  - CachedTrackData.beatGrid.bpm — Beat This! transformer on full mix.

These disagree on tracks like Love Rehab (125 vs 118 — see BUG-008.1
diagnosis). Neither is mechanically "right"; they're locking to
different layers of the mix's accent structure (kick interval vs.
perceptual beat across the whole texture).

Phosphene already runs Open-Unmix HQ during preparation, producing
a clean drums stem. **Running Beat This! on the drums stem in
addition to the full mix gives a third BPM estimate on isolated
percussion** — a different audio source, not just a different
estimator. On a dense mix where the full-mix Beat This! locks to
melodic accents, the drums-stem Beat This! should lock to kicks/
snares and produce a number closer to the kick-rate IOI estimator.
On a kick-driven track where both already agree, the drums-stem
output should agree too — confirming the disagreement isn't model
noise.

This data lets a future fusion-logic increment design something
load-bearing (when the three numbers cluster, accept the cluster;
when they fan out, that's a "this track is genuinely ambiguous"
signal and we surface it differently). **Designing the fusion logic
without first knowing how the numbers fan out across genres is
premature; this increment collects the evidence.**

────────────────────────────────────────
SCOPE
────────────────────────────────────────
What you build:

1. **Drums-only BeatGrid analysis at preparation time.** During
   `SessionPreparer.analyzePreview`, after stem separation produces
   `stemWaveforms[1]` (drums — index documented in StemSeparator),
   feed that mono Float32 buffer into the existing
   `DefaultBeatGridAnalyzer` to produce a second `BeatGrid`. Store
   it on `CachedTrackData` as a new optional field
   `drumsBeatGrid: BeatGrid?` (nil when `beatGridAnalyzer == nil`,
   matching the existing offline-grid contract).

2. **Per-track WIRING / WARN logging.** Extend
   `SessionPreparer+WiringLogs.logWiringDoneSummary` to emit a third
   per-track line alongside the existing `WIRING:
   SessionPreparer.beatGrid` and BUG-008.2 `WARN: BPM mismatch`
   entries:

     WIRING: SessionPreparer.drumsBeatGrid track='<title>'
       bpm=<X.X> beats=<N> isEmpty=false

   And extend `BPMMismatchCheck` to do a 3-way comparison.
   Suggestion: keep the existing 2-way detector for backward
   compatibility, add a separate `detectThreeWayBPMDisagreement(...)`
   pure function that returns a richer struct with all three values
   plus per-pair deltas. When any pair exceeds 3 % relative delta,
   emit a single combined log line:

     WARN: BPM 3-way track='<title>' mir_bpm=<a> grid_bpm=<b>
       drums_bpm=<c> mir-grid=<d>% mir-drums=<e>% grid-drums=<f>%
       (DSP.4: estimators on full-mix vs drums-stem vs kick-rate IOI)

   The existing 2-way `WARN: BPM mismatch` line is preserved
   verbatim — we want backward grep-ability for any tooling
   already cued to the BUG-008.2 line.

3. **No runtime consumption.** `LiveBeatDriftTracker` continues to
   consume `cache.beatGrid(for:)` (full-mix offline grid) exactly as
   today. The drums-stem grid is logged-only. If a future increment
   wants to fuse the three estimates, that's separate scope.

4. **A small deferred-cost guard.** The drums-stem analysis adds one
   extra Beat This! pass per prepared track — ~415 ms on M-class
   silicon (per the DSP.2 performance baselines). For a 20-track
   playlist that's ~8 s of extra preparation time. Acceptable for
   now; if it ever shows up as a regression in the
   `SessionPreparationIntegrationTests` performance budget, gate
   the second analysis pass behind a `phosphene.diagnostics.drumsBeatGrid`
   default-true setting in `SettingsStore` (the toggle is
   diagnostic, not user-facing — keep it in the developer/diagnostics
   section). Defer the toggle until/unless it's needed.

What you do NOT build:

  - Fusion logic. The three numbers are logged separately; no
    voting, no confidence weighting, no consumer code that picks
    one over another. That's a separate increment scoped after the
    evidence collected here.
  - Drums-stem feeding into LiveBeatDriftTracker.
  - UI changes (no new SpectralCartograph readout, no debug overlay
    row). The log line is sufficient.
  - Re-running drums-stem analysis on the live tap (this is offline
    only, drums stem isn't available live until the live separator
    has converged ~10 s in — a different conversation).
  - Vendoring a different model checkpoint or re-tuning Beat This!.
  - Any change to the existing 2-way BPMMismatchCheck behaviour
    (pure-function tests must continue to pass unchanged).

────────────────────────────────────────
WHAT TO BUILD
────────────────────────────────────────

**1. Schema change to CachedTrackData.**
   In `PhospheneEngine/Sources/Session/StemCache.swift`, add
   `public let drumsBeatGrid: BeatGrid` to `CachedTrackData`,
   defaulted to `.empty` in the `init` so all existing call sites
   keep compiling. Mirrors how `beatGrid: BeatGrid` was added in
   DSP.2 S6 (commit history shows the pattern).

   Add `public func drumsBeatGrid(for identity: TrackIdentity)
   -> BeatGrid?` accessor on `StemCache`.

**2. Drums-stem analysis in SessionPreparer+Analysis.**
   In `analyzePreview`, after Step 5 (full-mix beat grid) but
   inside the same detached Task, add Step 6: feed
   `stemWaveforms[drumsIndex]` through the same `gridAnalyzer`.
   Confirm `drumsIndex` from `StemSeparator.stemLabels` (should be
   `["vocals", "drums", "bass", "other"]` in that order — index 1).
   The drums waveform is at `Float(preview.sampleRate)` Hz (same as
   the full mix — Open-Unmix preserves input sample rate), so
   `gridAnalyzer.analyzeBeatGrid(samples: stemWaveforms[drumsIndex],
   sampleRate: Double(preview.sampleRate))` is the call.

   Wrap in nil-check on `beatGridAnalyzer` so the existing
   nil-analyzer path keeps producing `.empty` for drumsBeatGrid.

**3. Three-way detector in BPMMismatchCheck.**
   In `PhospheneEngine/Sources/Session/BPMMismatchCheck.swift`,
   add:

     public struct ThreeWayBPMReading: Equatable, Sendable {
         let mirBPM: Double
         let gridBPM: Double
         let drumsBPM: Double
         let mirGridDeltaPct: Double
         let mirDrumsDeltaPct: Double
         let gridDrumsDeltaPct: Double
         var maxDeltaPct: Double {
             max(mirGridDeltaPct, mirDrumsDeltaPct, gridDrumsDeltaPct)
         }
     }

     public func detectThreeWayBPMDisagreement(
         mirBPM: Double,
         gridBPM: Double,
         drumsBPM: Double,
         thresholdPct: Double = 0.03
     ) -> ThreeWayBPMReading?

   Returns nil when all three pairs are within threshold OR when
   any input is zero/non-finite. (Permissive on missing data —
   if drumsBPM is 0 we fall back to the 2-way path; do NOT emit
   a 3-way line that's effectively just the 2-way data.)

   Keep `detectBPMMismatch` (2-way) untouched. The wiring should
   prefer the 3-way line when all three are non-zero and at least
   one pair disagrees, and emit the 2-way line in the fall-through
   case (drumsBPM == 0 or 3-way agreement). Document the
   precedence in the function doc comments.

**4. Wiring in SessionPreparer+WiringLogs.**
   In `logWiringDoneSummary`'s per-track loop, after the existing
   `WIRING: SessionPreparer.beatGrid` line, emit a parallel
   `WIRING: SessionPreparer.drumsBeatGrid` line using
   `cache.drumsBeatGrid(for:)`. Then route the BPM-mismatch
   logging through the new precedence rule (3-way preferred,
   2-way fallback).

**5. Tests.**
   - `BPMMismatchCheckTests.swift`: add 5+ pure-function tests for
     `detectThreeWayBPMDisagreement` covering all-agree, all-disagree,
     pair-only disagree, zero-drumsBPM fallthrough, custom threshold.
   - `BeatGridIntegrationTests.swift`: extend the existing
     `bpmMismatch_wiring_doesNotCrash_andGridReachesCache` smoke
     test to verify a `cached.drumsBeatGrid` is populated when a
     stub analyzer is provided.
   - Add a new performance smoke (gated behind a sustained-budget
     env var if needed) asserting that
     `SessionPreparationIntegrationTests.fullPipeline_*` total wall
     time hasn't regressed by more than ~25 % per track. The
     existing perf tests already provide a baseline; just check
     new numbers stay within tolerance.

**6. Docs.**
   - Update `CLAUDE.md`'s Module Map and Buffer Binding sections
     are not needed (no GPU/buffer changes), but add a one-line
     note in the per-track preparation pipeline description that
     drumsBeatGrid is computed alongside beatGrid.
   - Add a `## DSP.4` entry to `docs/RELEASE_NOTES_DEV.md`
     summarizing what landed.
   - Update `docs/ENGINEERING_PLAN.md`: add DSP.4 row, mark
     complete, cite commit hash.

────────────────────────────────────────
FILES LIKELY TO TOUCH
────────────────────────────────────────
- PhospheneEngine/Sources/Session/StemCache.swift —
  `CachedTrackData.drumsBeatGrid` + accessor.
- PhospheneEngine/Sources/Session/SessionPreparer+Analysis.swift —
  Step 6 drums-stem analysis.
- PhospheneEngine/Sources/Session/BPMMismatchCheck.swift —
  add `ThreeWayBPMReading` + `detectThreeWayBPMDisagreement`.
- PhospheneEngine/Sources/Session/SessionPreparer+WiringLogs.swift —
  per-track drumsBeatGrid log line + 3-way mismatch precedence.
- PhospheneEngine/Tests/PhospheneEngineTests/Session/BPMMismatchCheckTests.swift —
  3-way detector tests.
- PhospheneEngine/Tests/PhospheneEngineTests/Integration/BeatGridIntegrationTests.swift —
  drumsBeatGrid wiring smoke test.
- docs/RELEASE_NOTES_DEV.md, docs/ENGINEERING_PLAN.md, CLAUDE.md.

DO NOT touch:
- LiveBeatDriftTracker. Drums-stem grid is logged-only.
- BeatThisModel, BeatThisPreprocessor, BeatGridResolver — no
  inference-side changes.
- VisualizerEngine wiring — drums-stem grid is preparation-only;
  the live engine continues consuming `cache.beatGrid(for:)`.
- BUG-007 lock-hysteresis logic — separate increment.

────────────────────────────────────────
DONE WHEN
────────────────────────────────────────
[ ] `CachedTrackData.drumsBeatGrid: BeatGrid` exists with `.empty`
    default; nil-analyzer path produces `.empty` exactly as
    `beatGrid` does today.
[ ] Drums-stem analysis runs once per prepared track inside the
    detached Task; preparation time per track increases by < 25 %
    vs. baseline (per `SessionPreparationIntegrationTests`).
[ ] `WIRING: SessionPreparer.drumsBeatGrid track='...' bpm=... beats=...
    isEmpty=...` line lands in `session.log` for every prepared
    track.
[ ] When all three estimators are non-zero and at least one pair
    disagrees, `WARN: BPM 3-way ...` line lands in `session.log`
    (preferred over the 2-way line). When drumsBPM is zero, the
    existing `WARN: BPM mismatch` 2-way line fires unchanged.
[ ] `detectThreeWayBPMDisagreement` has ≥ 5 pure-function tests.
[ ] Existing `BPMMismatchCheckTests` continue to pass byte-identical.
[ ] Engine test suite green (modulo documented baseline flakes).
[ ] xcodebuild build succeeds clean.
[ ] swiftlint --strict reports zero violations on touched files.
[ ] `docs/ENGINEERING_PLAN.md`, `docs/RELEASE_NOTES_DEV.md`,
    `CLAUDE.md` Module Map updated.
[ ] Local commits only; do not push without explicit Matt approval.

────────────────────────────────────────
SUCCESS CRITERIA (after the change lands)
────────────────────────────────────────
A fresh Spotify-prepared session capture should contain, for every
prepared track, three log lines per track:

  WIRING: SessionPreparer.beatGrid         (existing — full mix)
  WIRING: SessionPreparer.drumsBeatGrid    (new — drums stem)
  Plus one of:
    nothing                                (all three agree)
    WARN: BPM mismatch                     (drumsBPM == 0, 2-way only)
    WARN: BPM 3-way                        (all three present, ≥1 pair disagrees)

Specifically on the existing 2026-05-06T20-11-46Z capture's tracks,
re-running the pipeline should produce:

  - Love Rehab: drumsBPM expected ~125 (drums alone — kick rate
    should dominate). Three-way line should fire with
    `mir-grid=5.5%` and probably `grid-drums≈5.5%` and
    `mir-drums≈0%` — confirming the kick rate is what the IOI
    estimator and the drums-stem model both see.
  - Money 7/4: drumsBPM expected ~125 too (the 7/4 polyrhythm has
    a steady kick). Three-way line probably does not fire
    (current 2-way Money is 1.4 % — drums-stem likely agrees).
  - Pyramid Song: drumsBPM expected ~70 (kick on every dotted-8th
    in 16/8 typically reads as 70 BPM equivalent). Worth seeing
    what the model returns.

These specific numbers are predictions — the actual numbers ARE the
deliverable. Whatever they turn out to be becomes input to the
follow-up fusion-logic increment.

────────────────────────────────────────
NOTES FOR THE NEXT SESSION
────────────────────────────────────────
- The Open-Unmix drums stem on a 30-second preview is high-quality
  but not perfect — bleeding from bass kicks and snare rolls is
  common. If `drumsBPM` comes back wildly different from full-mix
  on most tracks (rather than just disputed ones like Love Rehab),
  that's a signal the stem quality is the bottleneck rather than
  full-mix-vs-drums being a useful axis. Document and route
  accordingly.
- Beat This!'s 415 ms inference is per call; running it twice per
  track is the expected cost. If we ever want to drop that, the
  MPSGraph `BeatThisModel` is reusable across calls (not single-shot)
  — same graph, same weights, just two `predict()` calls. No
  re-init needed. Verify `BeatThisModel` is shared across the two
  invocations within `analyzePreview`.
- Do NOT remove the BUG-006.1 WIRING: instrumentation in this
  increment — its cleanup is QR.5.
- Do NOT touch the BUG-008.2 2-way `WARN: BPM mismatch` line. The
  3-way line is additive; tooling cued to the 2-way grep should
  keep working.
- The diagnostic toggle (`phosphene.diagnostics.drumsBeatGrid`) is
  opt-in scope — only add it if the perf budget actually breaks.
  Likely it doesn't.
- After this lands, the natural next increment is OR.4 / DSP.5 —
  fusion logic that consumes the three estimators. Do NOT scope it
  preemptively. Wait for at least 2-3 fresh captures across genres
  so the fusion design is grounded in evidence.
