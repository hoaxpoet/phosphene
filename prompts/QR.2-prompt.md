Execute Increment QR.2 (OR.1) — Stem-affinity rescaling + reactive-mode
TrackProfile fix.

Authoritative spec: docs/ENGINEERING_PLAN.md §Phase QR §Increment QR.2.
Read it in full before writing any code.

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. QR.1 must have landed. Verify with
   `git log --oneline | grep '\[QR\.1\]'` — expect 7 commits in the
   range `783f75c6..70073050` (or later if QR.1 follow-ups have
   landed).

2. QR.1 manual subjective validation must be complete OR explicitly
   waived in chat. The validation is: Matt connects a Spotify
   playlist with Love Rehab, observes the session reaches
   PLANNED·LOCKED, and confirms stem energies on the debug overlay
   look sane (no obvious magnitude shift vs his pre-QR.1 mental
   model). QR.2 plumbs live `StemFeatures` into reactive scoring —
   if QR.1's plumbing has a real-world bug Matt's ear catches,
   QR.2 will amplify it instead of revealing it. **Do NOT merge
   QR.2 commits to local `main` until this sign-off is captured.**
   You may begin the implementation work in parallel; just gate
   the merge.

3. Decision-ID numbering: D-079 was claimed by QR.1. The next
   available number is **D-080**. Verify with
   `grep '^## D-0' docs/DECISIONS.md | tail -3` before writing the
   QR.2 decision entry.

────────────────────────────────────────
GOAL
────────────────────────────────────────

Make `stemAffinitySubScore` actually discriminate. Make reactive mode
score stem-affinity-bearing presets fairly. The 25% score-weight slot
currently does neither — preset selection is being carried entirely by
the mood (0.30) and section (0.25) weights.

This is the highest musicality payoff per LOC in the plan. Direct hit
on the "member of the band" goal: today, two presets with totally
different declared affinities score nearly identically because AGC
saturation hides the difference; reactive mode systematically rejects
the most musically-engaged catalog members.

────────────────────────────────────────
SCOPE
────────────────────────────────────────

1. STEM-AFFINITY SUB-SCORE REWRITE (Orchestrator+Session #1):
   PhospheneEngine/Sources/Orchestrator/PresetScorer.swift:281-299

   Current:
     - Reads `stemEnergy[stem]` (AGC-normalized, centered at 0.5).
     - Sums across declared affinity stems.
     - Clamps to [0, 1].
     Result: any preset declaring 2+ matching affinities saturates at
     ~1.0 on most music. Two presets with disjoint affinities score
     identically. 25% of total weight does no work.

   Replace with:
     - Read `stemEnergyDev[stem]` (deviation primitive, D-026/MV-1,
       already on StemFeatures floats 17–24 — `vocalsEnergyDev`,
       `drumsEnergyDev`, `bassEnergyDev`, `otherEnergyDev`).
     - Take the MEAN of `max(0, stem_dev)` across declared affinities,
       NOT the clamped sum. Mean preserves "this preset's stems must
       all be active" semantics; sum allowed any-one-stem to saturate.
     - When `stemEnergyBalance == StemFeatures.zero` (reactive-mode
       initial state, before live analyzer converges), return neutral
       0.5 for ALL presets — same as the `affinities.isEmpty` baseline.
       Otherwise reactive mode systematically rejects affinity-bearing
       presets.

   Implementation note: `StemFeatures.zero` detection — compare against
   a sentinel (e.g. `stemEnergyBalance.vocalsEnergy == 0 &&
   .drumsEnergy == 0 && .bassEnergy == 0 && .otherEnergy == 0`).
   Don't use floating-point equality if there's any chance of
   near-zero noise; threshold at < 1e-6 per stem.

2. LIVE STEMFEATURES PLUMBING FOR REACTIVE MODE
   (Orchestrator+Session #6):
   PhospheneEngine/Sources/Orchestrator/ReactiveOrchestrator.swift:177-178

   Current: `TrackProfile.empty.stemEnergyBalance == .zero` for every
   reactive-mode scoring call. Combined with the new (1) above, this
   correctly returns 0.5 — but reactive mode has no visibility into
   what the music actually sounds like.

   Add: `func update(elapsedSeconds: TimeInterval, liveStemFeatures:
   StemFeatures?, ...)` overload (or extend the existing context type)
   that accepts an optional live snapshot. When provided, build the
   scoring context's `stemEnergyBalance` from the snapshot. When nil
   (first ~10 s, before analyzer convergence), fall through to .empty
   path with neutral scoring.

   Convergence gate: 10 s wall-clock from reactive-session start, same
   scale as the existing reactive confidence ramp (0→0.3 over 0–15 s).
   Don't try to detect convergence dynamically — the time gate is
   simpler and matches the documented behavior.

   App-layer wiring: PhospheneApp/VisualizerEngine+Orchestrator.swift —
   pass `pipeline.latestStemFeatures` into `applyReactiveUpdate` once
   `reactiveSessionElapsed >= 10.0`.

   App-target coverage strategy (mirror QR.1's pattern):
   `VisualizerEngine` cannot be instantiated under SPM (Metal +
   audio tap). QR.1 hit the same gap and shipped engine-level
   integration tests covering the structural contract; app-target
   coverage is acknowledged as a follow-up and the lint gate is the
   standing defence. For QR.2, write the engine-level test against
   `ReactiveOrchestrator` accepting a live `StemFeatures` snapshot
   and routing to the new scoring path. App-layer wiring (the
   `+Orchestrator.swift` change) is verified by inspection and by
   Matt's manual subjective sign-off. Do NOT block on instantiating
   `VisualizerEngine` in SPM — that's a longstanding limitation,
   not a QR.2 problem to solve.

3. MOOD-OVERRIDE PER-TRACK COOLDOWN (Orchestrator+Session #3):
   PhospheneEngine/Sources/Orchestrator/LiveAdapter.swift

   `applyLiveUpdate()` runs at ~94 Hz on the analysis queue. Today it
   re-patches `livePlan` on every frame the conditions hold (`|Δmood|
   > 0.4` and `elapsed < 40%`). The plan-patching is idempotent but the
   work is wasted, AND it can ping-pong on oscillating mood readings.

   Add:
     - `var lastOverrideTimePerTrack: [TrackIdentity: TimeInterval]`
       on `DefaultLiveAdapter`.
     - Inside `evaluateMoodOverride` (or its caller), suppress override
       evaluation entirely when `(now - lastOverrideTime) < 30.0` for
       the current track. Don't even build the scoring contexts.
     - Boundary reschedule path is UNAFFECTED — it has its own per-eval
       gate. Cooldown applies only to mood-override.
     - Clear cooldown entry on track change (or just let it accumulate
       — the dictionary stays bounded by playlist length).

4. REACTIVE BOUNDARY-SWITCH GATE TIGHTENING (Orchestrator+Session #5):
   PhospheneEngine/Sources/Orchestrator/ReactiveOrchestrator.swift

   Current: `scoreGapMet OR boundaryFired` triggers a switch. Boundary
   alone (with confidence ≥ 0.5) flips presets without checking score
   gap, so every confident boundary every 60 s is a coin flip.

   Tighten to: `boundaryFired AND topScore > currentScore + 0.05`
   (small gap, not the full 0.20 used for non-boundary switches —
   boundaries are still preferred, just not random). The 60 s cooldown
   stays.

5. HARD-CUT THRESHOLD RAISE (Orchestrator+Session, transitions #3):
   PhospheneEngine/Sources/Orchestrator/TransitionPolicy.swift

   `cutEnergyThreshold = 0.7` paired with `energy = 0.5 + 0.4 * arousal`
   means any track with `arousal > 0.5` cuts at every track change. Most
   non-ambient music sits at 0.5–0.8 arousal, so the warm-crossfade
   ladder almost never fires.

   Raise to `cutEnergyThreshold = 0.85`. A/B-listenable: the warm
   crossfade should now feel like the default for most tracks, with
   hard cuts reserved for genuine peak-energy moments.

6. RECENTHISTORY TRIM (Orchestrator+Session #4):
   PhospheneEngine/Sources/Orchestrator/SessionPlanner+Segments.swift:219

   `recentHistory` appends unbounded; per-track scoring scans via
   `last(where:)` (PresetScorer.swift:323). At ~400 segments this
   becomes measurable. Trim to last 50 entries on append — same
   semantics (most-recent-first family-repeat detection works on
   any window ≥ catalog size).

────────────────────────────────────────
TESTS
────────────────────────────────────────

NEW Tests/PhospheneEngineTests/Orchestrator/StemAffinityScoringTests.swift:
  - test_disjointAffinities_produceScoreGap: two presets with disjoint
    affinity sets (e.g. drums-only vs vocals-only) on a drums-heavy
    track produce score gap ≥ 0.3. (Pre-fix: ≤ 0.05.)
  - test_emptyAffinities_scoresNeutral: preset with empty affinities
    scores 0.5 regardless of track.
  - test_meanNotSum: preset declaring 2 affinities, one stem at +0.4
    dev and one at -0.4 dev → score ≈ 0.20 (mean of [0.4, 0]). NOT 1.0
    (sum saturation pre-fix).
  - test_zeroProfileNeutral: TrackProfile.empty (stemEnergyBalance ==
    .zero) with non-empty affinities scores 0.5 (neutral), not 0
    (rejection pre-fix).
  - test_singleAffinityActive: preset with one declared affinity,
    matching stem at +0.5 dev → score 0.5 (not 1.0; not 0).

EXTEND Tests/PhospheneEngineTests/Orchestrator/ReactiveOrchestratorTests.swift:
  - test_boundaryWithEqualScores_doesNotSwitch: boundary fires with
    `topScore == currentScore` → no switch (was: switch).
  - test_boundaryWithSmallGap_doesSwitch: boundary fires with
    `topScore == currentScore + 0.10` → switch.
  - test_60sCooldownStillRespected: pre-existing assertion holds.
  - test_liveStemFeatures_changesScoring: pre-10s reactive scoring
    returns neutral; post-10s with a drums-heavy live snapshot returns
    a different ranking.

EXTEND Tests/PhospheneEngineTests/Orchestrator/LiveAdapterTests.swift:
  - test_consecutiveCalls_onlyOneOverride: 100 consecutive
    `applyLiveUpdate` calls with override conditions held → only one
    plan patch applied (was: 100).
  - test_overrideCooldownClears_onTrackChange.
  - test_boundaryReschedule_notAffectedByCooldown: with mood-override
    in cooldown, a structural boundary still triggers reschedule.

REGENERATE Tests/PhospheneEngineTests/Orchestrator/GoldenSessionTests.swift:
  - All three curated playlists. The score-gap shift will change preset
    selection on at least some tracks; that is the expected behavior of
    this increment, not a regression.
  - Document each delta inline with a comment citing QR.2 and the
    finding number that justifies it (e.g. "Track 3: was Plasma (sum
    saturation gave it 1.0 stem-affinity score against drums-led
    track despite vocals-only affinity); now FractalTree (drums-only
    affinity, +0.32 score gap on this track)").
  - Commit message must call out that goldens were regenerated and why.

EXISTING TESTS:
  - Full engine suite passes after each commit.
  - PresetRegressionTests goldens unchanged (this increment touches
    Orchestrator only, not preset rendering).
  - PresetAcceptanceTests unchanged.

PRE-EXISTING FLAKES (acceptable — do not fix as part of QR.2):
  - `MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget`
  - `MemoryReporter` residentBytes growth (env-dependent)
  - `PreviewResolver` timing
  - `AppleMusicConnectionViewModel` (4 cases, env-dependent)
  - `SoakTestHarnessTests.cancel()` (timing-sensitive flake under
    parallel load — passes in isolation; surfaced in QR.1 closeout
    2026-05-06)
  Every other failure must be resolved or reported.

MANUAL VALIDATION (gating — Matt's listening sign-off):
  - Connect to Spotify; play Love Rehab in reactive mode (no playlist).
    Confirm preset selection feels different from the pre-fix baseline
    — drums-affinity presets should now appear more often on this track.
  - Connect to Spotify; play one vocal-led track (Matt's choice) in
    reactive mode. Confirm vocals-affinity presets now appear instead
    of being rejected.
  - This is a SUBJECTIVE gate. Automated tests prove the math; only
    listening proves the musicality. Don't mark the increment ✅
    without Matt's explicit "yes, this feels right" in chat.

────────────────────────────────────────
DOCUMENTATION
────────────────────────────────────────

- docs/CLAUDE.md
  - Failed Approaches #53 + #54 already exist from QR.0 — verify the
    descriptions match what you actually fixed; tighten if needed.
  - "What NOT To Do" entries about summing AGC energies, scoring
    against empty TrackProfile, applyLiveUpdate without cooldown —
    already added in QR.0. Verify they are consistent with the
    implementation.
  - Module Map: update PresetScorer / ReactiveOrchestrator / LiveAdapter
    entries if the public API changes.

- docs/DECISIONS.md
  - NEW **D-080**: "Stem-affinity scoring uses deviation primitives,
    not absolute AGC-normalized energies; reactive mode receives a
    live StemFeatures snapshot after 10s convergence." Cite Failed
    Approaches #53 + #54, the call sites, and Orchestrator+Session
    findings #1 / #2 / #6 as the source.
  - Verify D-080 is the next available number (`grep '^## D-0'
    docs/DECISIONS.md | tail -3`). QR.1 took D-079; do not collide.

- docs/QUALITY/KNOWN_ISSUES.md
  - If any open issue tracks "stem affinity scoring is broken" or
    "reactive mode preset choice feels random," close with QR.2
    commit hashes and Resolved date.
  - If no such issue exists, add a Resolved entry documenting the
    pre-fix behavior so future bisect debugging has the artifact.

- docs/ENGINEERING_PLAN.md
  - Phase QR section: flip QR.2 done-when boxes to [x] as items land.
  - Mark increment ✅ at the end with date + commit range + manual
    sign-off note.

────────────────────────────────────────
PROTOCOL — closeout requirements
────────────────────────────────────────

Follow the Increment Completion Protocol from CLAUDE.md.

Commit format: `[QR.2] <component>: <description>` per commit. Prefer
multiple small commits (sub-score rewrite, reactive plumbing, cooldown,
boundary gate, cut threshold, recentHistory trim, tests, golden regen,
docs). Goldens regen MUST be its own commit so `git bisect` on
musicality can isolate the algorithm change from the golden update.

DO NOT push to remote. Local main commits only.

DO NOT include files outside QR.2 scope. If git status shows unrelated
changes (e.g. default.profraw, IDE artifacts), back them out or surface
them.

PAUSE AND REPORT instead of forging ahead when:
  - Tests fail (engine or app), even pre-existing flakes the increment
    touched.
  - GoldenSessionTests delta is larger than expected (e.g. every track
    in every playlist changes preset). That suggests the algorithm
    change is more aggressive than intended; verify the mean-vs-sum
    semantics before regenerating goldens.
  - The implementation as written would require broader architectural
    changes — e.g. if `latestStemFeatures` is not accessible from the
    app-layer reactive path without a refactor, surface that scope.
  - Matt's manual validation says "this feels worse, not better."
    Don't tune around the subjective signal — surface and discuss.

CLOSEOUT REPORT must cover:
  1. Files changed (grouped new vs edited).
  2. Tests run, pass/fail counts. Pre-existing flakes called out
     (per the list in TESTS above).
  3. Documentation updates (CLAUDE.md, DECISIONS.md, KNOWN_ISSUES.md,
     ENGINEERING_PLAN.md).
  4. Engineering plan updates: confirm QR.2 done-when boxes ticked.
  5. Capability registry updates if any (likely none — Orchestrator
     change, no renderer impact).
  6. GoldenSessionTests delta summary: which tracks changed preset
     selection, by how much, and why (cite the algorithm change).
  7. Known risks and follow-ups.
  8. Git status: branch, commit hashes, clean tree.
  9. Manual validation status: Matt's subjective sign-off captured
     in chat (paste the confirmation). If sign-off is pending, mark
     QR.2 as [~] (in-progress) NOT [x] (done) in ENGINEERING_PLAN.md.

────────────────────────────────────────
VERIFY (run cumulatively at the end)
────────────────────────────────────────

swift test --filter StemAffinityScoring
swift test --filter ReactiveOrchestrator
swift test --filter LiveAdapter
swift test --filter GoldenSession
swift test --package-path PhospheneEngine
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test
swiftlint lint --strict --config .swiftlint.yml

All must pass before the closeout report. Pre-existing flakes
(see TESTS section) acceptable.

────────────────────────────────────────
OUT OF SCOPE
────────────────────────────────────────

- Sample-rate plumbing fixes (QR.1 — must already be landed; see
  PRECONDITIONS).
- Test silent-skip closure (QR.3).
- UX changes (QR.4).
- Mechanical cleanup (QR.5) — including the Gossamer.metal:189 D-026
  violation surfaced by QR.1's lint script (`f.bass * 0.76 + bassRel
  * 0.12`). QR.1 closeout already tracked it as a follow-up; do NOT
  fix it as part of QR.2.
- VisualizerEngine decomposition (QR.6).
- Re-tuning the four sub-score weights (mood 0.30, stemAffinity 0.25,
  sectionSuitability 0.25, tempoMotion 0.20). The point of QR.2 is to
  make the existing 0.25 stemAffinity weight do its intended work —
  not to redistribute weights. If after manual validation Matt feels
  the balance is off, that's a follow-up increment, not QR.2.
- TempoMotion sub-score fix (Orchestrator+Session #2 noted that
  `TrackProfile.empty` + `bpm == nil` produces 0.5 for every preset
  — uninformative but not actively wrong). Defer to a future increment
  if it surfaces as a real product issue.
- Family-repeat penalty scope expansion (Orchestrator+Session
  musicality #6 — A→B→A streaks). Subjective-tuning territory; defer.

If you discover a finding outside this scope while working, write it
into the closeout report under "Known risks and follow-ups" — do not
expand scope mid-increment.
