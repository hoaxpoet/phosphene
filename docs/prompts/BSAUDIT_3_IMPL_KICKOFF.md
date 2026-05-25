# BSAudit.3.impl Kickoff — BPM-Anchored Phase Acquisition (2026-05-24)

Hand this to a new Claude Code session verbatim. Do not summarise it.

## Read these first, before doing anything else

1. **[`docs/BPM_ANCHORED_PHASE_ACQUISITION_DESIGN_2026-05-24.md`](../BPM_ANCHORED_PHASE_ACQUISITION_DESIGN_2026-05-24.md)** — the load-bearing design document for this increment. Read it end-to-end. The three open decisions in §14 are **resolved** (soft ramp, default `phaseAcquisitionDifficulty` formula, dual-candidate octave-risk). Do not re-litigate them.
2. **[`docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`](../CAPABILITY_REGISTRY/BEAT_SYNC.md)** — the BSAudit deliverable + BSAudit.2 Path A falsification addendum. The empirical basis for why the design is what it is.
3. **[`docs/QUALITY/KNOWN_ISSUES.md`](../QUALITY/KNOWN_ISSUES.md)** → **BUG-017** with every addendum through 2026-05-24. Read in order. This is the historical chain of failed approaches the design is responding to.
4. **[`docs/RELEASE_NOTES_DEV.md`](../RELEASE_NOTES_DEV.md)** → `[dev-2026-05-24-a]`, `[dev-2026-05-24-b]`, `[dev-2026-05-24-c]` — the chronological narrative of CS.1 → CS.1.y.2-redo → revert → BSAudit → BSAudit.2.
5. **[`docs/ENGINEERING_PLAN.md`](../ENGINEERING_PLAN.md)** → Phase CS / CS.1.y entry (now superseded by BSAudit + BSAudit.2 + BSAudit.3) for context on the broader phase.
6. **[`CLAUDE.md`](../../CLAUDE.md)** — the whole file. Particularly:
   - **Defect Handling Protocol** — this increment is the Fix stage of P1 BUG-017, with design already done.
   - **Authoring Discipline** — "design is upstream" (already cleared), "diagnostic infrastructure precedes fidelity claims", "stop and report."
   - **Failed Approach #68** — sub-bass onsets are not a beat-phase reference. The design uses broadband flux specifically to avoid this. Do not regress.
   - **Failed Approach #58** — Drift Motes pattern (five failed iterations on the same defect at infrastructure scope). This increment must integrate feedback from the design into the model. If the impl deviates from the design or surfaces a structural concern, **stop and report** — do not just push through.
7. The code, end to end (per the design's §5 + §8):
   - `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — substantial rework (the focal point of this increment).
   - `PhospheneEngine/Sources/DSP/BeatDetector.swift` — broadband peak detector addition.
   - `PhospheneEngine/Sources/DSP/MIRPipeline.swift` — accent confidence gating in `buildFeatureVector`.
   - `PhospheneEngine/Sources/Session/CachedTrackData.swift` + `SessionPreparer+Analysis.swift` — `RhythmCharacter` metadata.
   - `PhospheneEngine/Sources/Session/GridOnsetCalibrator.swift` — **delete this file** per design §5.2.
   - `PhospheneApp/VisualizerEngine+Stems.swift:484` (cold-start install) — switch from `setBeatGrid(_:initialDriftMs:)` to `installBPMPrior(bpm:character:)`.
   - `PhospheneEngine/Sources/Shared/` (wherever `FeatureVector` lives) — add `accentConfidence` field.
   - `PhospheneEngine/Sources/ColdStartVerifier/` — add `--accent-window-pass-rate` mode at the validate step.

## What's settled on entry (2026-05-24)

- **The design is approved.** Don't redesign. If implementation surfaces a structural issue, stop and report — don't silently improvise.
- **Three open decisions are resolved** (design §14 final table): soft ramp; default `phaseAcquisitionDifficulty` formula; dual-candidate octave-risk handling.
- **`GridOnsetCalibrator` is being retired.** Delete the file. Update consumers in `SessionPreparer+Analysis.swift` (prep-time `gridOnsetOffsetMs` computation) and `VisualizerEngine+Stems.swift` (install-time consumption). Verify no other consumers remain via grep.
- **BUG-007.x lock-state API surface stays.** Three external states (`.unlocked` / `.locking` / `.locked`) remain; the new internal state machine (`coldStart` / `acquiring` / `locked` / `degraded`) maps onto them per design §6.2.
- **`Shift+B` (bar-phase rotation) stays as a user override.** Auto-rotate (BUG-007.4b/c) continues to work — it now operates on confidence-locked phase instead of cached grid phase, same intent.
- **Preset shaders do not change.** The `accentConfidence` gate is applied at the FeatureVector layer in `MIRPipeline.buildFeatureVector` (design §5.8 + §6.5).
- **BUG-013 (odd-meter / time-signature) is out of scope.** Money's bar-phase confusion stays a known limitation; BSAudit.3 handles BEAT phase only (design §13).

## The task — BSAudit.3.impl

This is the Fix stage of P1 BUG-017 per CLAUDE.md's Defect Handling Protocol. Multi-increment process, design already done. **The impl ships in three sub-commits per design §11**, with engine + lint + tests green at each step:

### Sub-commit 1 — Foundation layer (BSAudit.3.impl.1)

**Goal:** add new building blocks. No behavior change yet (no consumer of the new fields).

- New `BroadbandPeakDetector` in DSP (sibling to `BeatDetector`, or as an extension — your choice; document the call site). Reads `SpectralAnalyzer.smoothedFlux` per frame; emits peak events. Adaptive median over the last 1 s; threshold = `1.8 × median`; refractory period `0.4 × (60 / cachedBPM)` seconds. See design §6.3.
- New `RhythmCharacter` struct in `Shared` (Sendable, Codable, Hashable). Five fields per design §7: `beatStrengthProfile`, `onsetsPerBeat`, `octaveRisk`, `phaseAcquisitionDifficulty`, `syncopationIndex`.
- Extend `CachedTrackData` with `rhythmCharacter: RhythmCharacter?` (Optional for backward compat with older cache entries).
- Extend `SessionPreparer+Analysis.swift` to compute `RhythmCharacter` at prep time. All five fields are derivable from the 30 s preview + Beat This! output + `BeatDetector` per-band onsets — no new ML inference.
- New tests covering the peak detector + the `RhythmCharacter` computation.

**Done-when:** engine suite at 1265+N pass (N = new tests added); `swiftlint --strict` 0 violations; build clean. No runtime behavior change.

**Commit:** `[BSAudit.3.impl.1] DSP/Session: broadband peak detector + RhythmCharacter metadata (no behavior change)`

### Sub-commit 2 — `LiveBeatDriftTracker` rework (BSAudit.3.impl.2)

**Goal:** implement the new state machine + phase acquisition algorithm, tested in isolation. Existing call sites still call `setGrid(_:initialDriftMs:)` (which now becomes a thin shim that delegates to the new entry point or is marked deprecated — your call).

- Implement the §6.2 state machine (`coldStart` / `acquiring` / `locked` / `degraded` internally; `.unlocked` / `.locking` / `.locked` externally per the mapping).
- Implement the §6.4 BPM prior + phase EMA + confidence accumulator. Initial tunables from the design (window ±60 ms, EMA alpha 0.3, gain 0.25, decay 0.10, lockThreshold 0.7, dropThreshold 0.3). Per-track scaling by `phaseAcquisitionDifficulty` per §6.4. Dual-candidate octave-risk handling per §6.4 + §9.2.
- New entry point: `installBPMPrior(bpm: Double, character: RhythmCharacter?)`. Old `setGrid(_:initialDriftMs:)` either deprecated-with-shim (preserves regression coverage for one increment) or removed entirely (less code, more pressure for one-commit clean transition). Design's preference is the latter — `GridOnsetCalibrator` is being deleted, so the seed path goes with it.
- New output: `accentConfidence: Float` (0-1).
- Heavy test rework. The existing `LiveBeatDriftTrackerColdStartPhaseTests.swift` and related test files cover behavior that's being replaced. New tests cover the §6.2 state machine, §6.3 peak detector integration, §6.4 acquisition under various input streams, §9.x edge cases (first peak isn't a beat, quiet intro, cross-fade, octave-risk dual-candidate). At least 10 new tests.
- BUG-007.x preservation: BUG-007.4 (`Shift+B`), BUG-007.4b/c (auto-rotate), BUG-007.6 (`audioOutputLatencyMs`) all preserved per design §5.7. Verify with explicit regression tests.

**Done-when:** engine suite green (1265-N+M where N = retired tests, M = new tests; document the delta in the commit message); `swiftlint --strict` clean; existing app suite still passes (call sites haven't switched yet, so no app-layer behavior change).

**Commit:** `[BSAudit.3.impl.2] LiveBeatDriftTracker: BPM-prior + broadband-peak phase acquisition + confidence-gated accents`

### Sub-commit 3 — Integration + retirement (BSAudit.3.impl.3)

**Goal:** switch the production install path to the new entry point. Retire `GridOnsetCalibrator`. Gate accent fields by `accentConfidence`. End state: the production beat-sync wiring uses the new architecture end-to-end.

- `MIRPipeline.buildFeatureVector` multiplies `beatBass`, `beatMid`, `beatTreble`, `beatComposite` by `liveDriftTracker.accentConfidence` (design §6.5). `beatPhase01` / `barPhase01` are **not** gated (design §6.5 explanation).
- `VisualizerEngine+Stems.swift:484` (`resetStemPipeline`) switches from `mirPipeline.setBeatGrid(cached.beatGrid.offsetBy(0), initialDriftMs: cached.gridOnsetOffsetMs)` to `mirPipeline.installBPMPrior(bpm: cached.beatGrid.bpm, character: cached.rhythmCharacter)`.
- **Delete `PhospheneEngine/Sources/Session/GridOnsetCalibrator.swift`** + its test file + its consumers (`SessionPreparer+Analysis.swift` no longer computes `gridOnsetOffsetMs` — the field on `CachedTrackData` either stays (for backward compat with older caches loading) or is dropped (more invasive). Design's recommendation: leave the `gridOnsetOffsetMs` field on `CachedTrackData` for one release for cache backward-compat, but no code reads it. Verify with grep — no consumers.
- Per-preset audit (design §9.9): grep every preset's `.metal` file for `beatPhase01`, `barPhase01` reliance. Are any presets using `beatPhase01` to drive non-pulse motion that would look weird while accent pulses are gated? Document findings in the commit. Likely zero changes needed; flag any anomalies as follow-up.
- Engine + app suites green. Project-wide `swiftlint --strict` 0 violations across all files.

**Done-when:** engine suite green; app build clean; `swiftlint --strict` 0 violations project-wide; `ColdStartVerifier --self-test` PASS (7/7); per-preset audit documented in the commit message.

**Commit:** `[BSAudit.3.impl.3] Integration: install BPM prior, gate accents by confidence, retire GridOnsetCalibrator`

## After BSAudit.3.impl lands

Then comes **BSAudit.3.validate** (separate increment, not in this kickoff). Surface to Matt for a fresh capture + M7 review. Sub-tasks:

- Extend `ColdStartVerifier` with `--accent-window-pass-rate` mode (design §8). Per-track: % of audible beats where a visual accent fired within ±60 ms.
- Run against the 4 reference captures + a fresh capture from Matt.
- M7 listening review on Matt's hardware. **M7 is the load-bearing close criterion** per CLAUDE.md "Defect Handling Protocol" + design §12.
- Closeout: BUG-017 → Resolved, commit hash, RELEASE_NOTES `[dev-2026-05-XX]`, ENGINEERING_PLAN BSAudit.3 to ✅.

## Verification criteria (write before the fix — already specified in design §12)

- [ ] **Automated:** Engine suite passes (1265 baseline + new tests; document delta).
- [ ] **Automated:** Project-wide `swiftlint --strict` 0 violations.
- [ ] **Automated:** App build clean.
- [ ] **Automated:** `ColdStartVerifier --self-test` PASS (7/7).
- [ ] **Regression:** BUG-007.x lock-state API surface preserved (`SpectralCartograph` diagnostic display unchanged; existing tests pass).
- [ ] **Regression:** No preset shader regresses (per-preset golden hashes preserved where applicable).
- [ ] **Manual (deferred to BSAudit.3.validate):** Matt M7 listening review confirms perceptually credible sync from frame 1 with the soft-ramp warmup.

## Stop-and-report criteria

Per CLAUDE.md "stop and report" — stop and surface to Matt before pushing through if any of these fire:

- The design's claim in §5 about "what's already in production" doesn't match the current code (something changed since 2026-05-24, or I misread).
- The §6 algorithm has an edge case not covered by §9 that you discover during impl.
- A preset's `beatPhase01` use case (per §9.9 audit) would look perceptually wrong while accent pulses are gated.
- The `RhythmCharacter` computation in `SessionPreparer+Analysis.swift` adds > 500 ms per track to prep time.
- Removing `GridOnsetCalibrator` surfaces an unexpected consumer (e.g., a diagnostic path nobody flagged).
- The new tracker state machine doesn't cleanly map onto the existing public `LockState` API for existing consumers.
- Lock-state transition timing fails any of the BUG-007.5 BPM-aware lock-release contracts (HUMBLE-class sparse-onset tracks dropping lock prematurely).
- Engine tests fail in unexpected ways post-rework — surface the test failures + their root cause before fixing.

The cost of pausing is small. The cost of an unauthorized scope expansion or a five-iteration failure pattern is high. Failed Approach #58.

## Hard rules

- **Follow the design.** Deviations require Matt sign-off, not improvisation.
- **No code that the design doesn't justify.** New mechanisms surface to Matt before landing.
- **Three sub-commits, in order.** Sub-commit 1 (foundation) → sub-commit 2 (tracker rework) → sub-commit 3 (integration). Engine + lint + tests green at each step.
- **Per CLAUDE.md commit format:** `[BSAudit.3.impl.N] <component>: <description>` where N ∈ {1, 2, 3}. Small commits within each sub-increment also allowed.
- **Do not push without Matt's explicit "yes, push."** Local-only.
- **Do not bundle BUG-013 / odd-meter work.** Design §13. Money stays known-limited.
- **Do not touch the pre-existing out-of-scope tree state** (the `PhospheneApp.xcscheme` modification, the `docs/CS_1_Y_KICKOFF.md` → `docs/prompts/` move that's still pending, `default.profraw`). Matt's call when those land.

## Status on entry

- **Branch `main`.** Currently 26 commits ahead of `origin/main` post-push (or ahead by however many — check `git status`).
- **Engine suite green:** 1265 / 1265 (BSAudit.2 baseline).
- **`swiftlint --strict`:** 0 violations across 386 files.
- **BUG-017:** Open. Design approved. This increment is the fix.
- **BSAudit + BSAudit.2:** ✅. Findings in [`BEAT_SYNC.md`](../CAPABILITY_REGISTRY/BEAT_SYNC.md).
- **Pre-existing uncommitted out-of-scope items** in the tree (leave alone): `PhospheneApp.xcscheme`, `default.profraw`, `docs/CS_1_Y_KICKOFF.md` → `docs/prompts/` move pending.
- **Reference captures available** for testing (in `~/Documents/phosphene_sessions/`):
  - `2026-05-22T16-57-36Z/` — CS.1 baseline.
  - `2026-05-22T19-03-59Z/` — CS.1.y.2 onset-fix attempt.
  - `2026-05-23T02-39-54Z/` — CS.1.y.2-redo round 2.
  - `2026-05-24T15-07-31Z/` — M7 capture.
- **`ColdStartVerifier` binary:** at `PhospheneEngine/.build/arm64-apple-macosx/release/ColdStartVerifier`. Rebuild with `swift build --package-path PhospheneEngine --product ColdStartVerifier -c release`.

If you find this prompt is wrong or stale, update it before working against it.

— Matt + Claude (2026-05-24, design sign-off received)
