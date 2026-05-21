# Phase CA Kickoff — Capability Audit — Increment CA.4 (Orchestrator)

Hand this to a new Claude Code session verbatim. Do not summarise.

## What this phase is

Phase CA — Capability Audit is a multi-increment archaeology of Phosphene's codebase. Each increment audits one subsystem: reads the actual source, traces consumers and producers, cross-references against `CLAUDE.md` / `docs/ARCHITECTURE.md` / `docs/QUALITY/KNOWN_ISSUES.md` / `docs/DECISIONS.md`, and assigns a health verdict to every capability the subsystem exposes.

CA.1 (DSP / MIR) closed 2026-05-20 at [`docs/CAPABILITY_REGISTRY/DSP_MIR.md`](../CAPABILITY_REGISTRY/DSP_MIR.md). It validated the audit format, surfaced one runtime production-orphan cluster (per-frame `StructuralAnalyzer` chain), surfaced one minor field-level orphan, and boundary-deferred two Sources/Session/*.swift files (`GridOnsetCalibrator`, `BeatGridAnalyzer`).

CA.2 (ML) closed 2026-05-20 at [`docs/CAPABILITY_REGISTRY/ML.md`](../CAPABILITY_REGISTRY/ML.md). It audited 16 ML files (4,507 LoC), surfaced four cluster-level production-orphan findings, two large built-but-undocumented gaps, and produced a centralised §BUG-012 instrumentation map. CA.2's approach-validation surfaced one methodology refinement: Explore agents over-asserted `public` on internal types in 3 of 4 CA.2 cases, so CA.3 added an explicit pre-grep visibility-verification step.

CA.3 (Session) closed 2026-05-20 at [`docs/CAPABILITY_REGISTRY/SESSION.md`](../CAPABILITY_REGISTRY/SESSION.md). It audited 22 Session files (~3,425 LoC), resolved all three CA.1/CA.2 boundary-deferred items (`GridOnsetCalibrator` → relocate to DSP/ as `CA.3-FU-1`; `BeatGridAnalyzer` stays in Session/; `MoodClassifier.currentState` end-of-prep read is intentional EMA-smoothed-state architecture). Found 1 `stub` (`LocalFolderConnector.swift` is `#if`-gated and never compiles in v1), 0 `broken-but-claimed`, 0 `production-orphan`, and 2 documented-but-missing / 2 built-but-undocumented in `ARCHITECTURE.md`. **The audit also flagged a kickoff-prompt staleness**: BUG-006 was cited as Open/P1 by the prompt but `KNOWN_ISSUES.md` already showed `Status: Resolved` (BUG-006.2 fix, 2026-05-06). CA.3's approach-validation produced one new methodology refinement: cross-check the kickoff prompt against `KNOWN_ISSUES.md` as a routine second step — see §Methodology below.

This kickoff is for **Increment CA.4: the Orchestrator subsystem**. It is the fourth audit pass.

## Why Orchestrator next

Four reasons (carried forward from CA.3's approach-validation recommendation):

1. **Multiple Session ↔ Orchestrator boundary touchpoints surfaced in CA.3.** `TrackProfile` is consumed by `DefaultPresetScorer` (via `PresetScoringContext`) at preparation time and at runtime via `VisualizerEngine+Orchestrator`. `SessionPlan` is the deliberately-minimal Session-side stub (D-017) lifted to `PlannedSession` / `PlannedTrack` / `PlannedTransition` (D-034) in the Orchestrator module. `PlannedSession.canonicalIdentity(matchingTitle:artist:)` is the load-bearing helper consumed during BUG-006.2 prepared-cache wiring at `VisualizerEngine+Capture.swift:131`. CA.4 closes that boundary cleanly.

2. **CA.1's runtime production-orphan cluster has its Orchestrator-side counterpart here.** CA.1 surfaced that `MIRPipeline.latestStructuralPrediction` runs the per-frame `StructuralAnalyzer` chain on the audio-callback hot path but has only one consumer (`SessionPreparer+Analysis.swift:289` at prep time). The Orchestrator's runtime `StructuralPrediction` consumers (`TransitionPolicy.swift:165`, `LiveAdapter.swift:250`, `ReactiveOrchestrator.swift:316`) get their predictions from `SessionPlanner.swift:317` constructed *synthetically*. CA.4 should audit the synthetic-construction site and surface whether the architecture is right or whether `CA.1-FU-1` (gate the per-frame chain or wire the orchestrator to consume real predictions) needs a re-scoping with full Orchestrator context.

3. **Recent strategic decisions are dense and have active learnings.** D-080 (QR.2 stem-affinity scoring uses deviation primitives + mean formula) is the Failed Approach #53 + #54 fix; verify the implementation is faithful. D-095 (V.7.7C.2 Arachne single-foreground build state machine + `PresetSignaling` conformance) introduces the completion-event channel. D-097 (particle presets are siblings, not subclasses) shapes how the Orchestrator handles preset families. D-115 / D-120 / D-122 (Phase MD strategy bloc) — D-120 was reverted per Failed Approach #59; verify the reversion is clean and no `concept_tags` / `motion_paradigm` residue remains in `PresetDescriptor` or `DefaultPresetScorer`.

4. **Active BUGs in scope.** BUG-001 (Money 7/4 stays REACTIVE on live path; Open). BUG-011 (Arachne over Tier 2 frame budget at the median; Resolved with relaxed criteria — verify the completion-gated transition path and `wait_for_completion_event` flag handling). BUG-014 (Lumen Mosaic panel aggregate uniform — Resolved via LM.4.7 palette library; cross-check that no Orchestrator-side scoring assumption was carried).

## Read these first, before doing anything else

1. **`CLAUDE.md`** — the entire file. Note especially: the Audio Data Hierarchy (the Orchestrator must respect it when scoring), the Session Preparation Pipeline pointer, the GPU Contract (the Orchestrator does not touch GPU directly but consumes `PresetDescriptor` metadata that does), Failed Approaches #53 / #54 (D-080 stem-affinity AGC fix), #57 (Arachne trigger gated on `bassAttRel`), #58 (Drift Motes retirement; affected the orchestrator's catalog), #59 (D-120 concept-tags revert), #60 (Phase MD bloc — ten same-day amendments / one 24-hour revert), and the QR.3 silent-skip-test discipline rule.

2. **`docs/CAPABILITY_REGISTRY/DSP_MIR.md`** — the CA.1 audit. Read §Findings-by-verdict §production-orphan verbatim: the `StructuralAnalyzer` cluster's *Orchestrator-side* path (synthetic construction at `SessionPlanner.swift:317`) is where CA.1's recommendation can be implemented or refuted with full context.

3. **`docs/CAPABILITY_REGISTRY/ML.md`** — the CA.2 audit. Read §Cross-references and the §BUG-012 instrumentation map. CA.4's ML-side touchpoint is mood input (`MoodClassifier.classify(features:)` consumed at runtime in `VisualizerEngine+Audio.swift:289` for `mood injection`, but the Orchestrator side reads `TrackProfile.mood` cached at end-of-prep — the latter is the CA.4 surface).

4. **`docs/CAPABILITY_REGISTRY/SESSION.md`** — the CA.3 audit. Read §Boundary-noted, §Resolution-of-CA.1/CA.2-boundary-deferred-items, and §Follow-up Backlog. CA.4's Session-side touchpoints are: `TrackProfile` consumption shape (CA.3 identified `DefaultPresetScorer` + `DefaultSessionPlanner` + `VisualizerEngine+Orchestrator.swift:83 / :326 / :449`); the canonical-identity matcher used by BUG-006.2; `PreFetchedTrackProfile` (Audio module, not Session) consumed by both `DefaultPresetScorer` and `SessionPlanner`. Verify CA.3's read against the Orchestrator-side reality.

5. **`docs/ARCHITECTURE.md`** — sections "Orchestrator" (lines 188+), "Module Map Orchestrator/" (lines 525–543), "Audio Data Hierarchy" (the Orchestrator must respect it in scoring weights), and the recent CA.3 §Session Preparation rewrite (verify the Orchestrator-side handoff at step 7 matches `DefaultSessionPlanner` reality). Particular attention: the `§Orchestrator forthcoming` list at lines 206–211 — verify which items have actually shipped vs. which are still pending.

6. **`docs/DECISIONS.md`** — grep for D-032 (PresetScorer 4-weight + family + fatigue penalty structure), D-033 (TransitionPolicy structural-boundary priority), D-034 (SessionPlanner greedy forward walk), D-047 (Seeded tie-breaking for Regenerate Plan, Increment U.5), D-050 (PlaybackActionRouter in Orchestrator module), D-058 (U.6b live-adaptation keyboard semantics), D-072 update (V.7.5 fidelity ceiling + multi-segment-per-track design + `presetCompletionEvent` channel + `wait_for_completion_event` flag), D-077 (DSP.2 Beat This! — orchestrator-side reaches via `TrackProfile`), D-078 (Diagnostic hold semantics + prepared-BeatGrid authority — `DiagnosticHoldTests` is the test surface), D-080 (QR.2 stem-affinity scoring deviation primitives + mean formula), D-091 (QR.4 — `PlannedSession.canonicalIdentity(matchingTitle:artist:)` is the load-bearing addition), D-095 (V.7.7C.2 Arachne build state + `PresetSignaling` conformance), D-097 (Particle presets are siblings, not subclasses — `ParticleGeometry` protocol scope), D-099 (engine MSL struct extension — orchestrator-side: verify no scoring path reads fields beyond the original 32/16 floats), D-115 / D-120 / D-122 (Phase MD strategy bloc — verify the D-120 revert is clean).

7. **`docs/QUALITY/KNOWN_ISSUES.md`** — every entry tagged `orchestrator`, `dsp.beat`, or `preset.fidelity` that references `SessionPlanner`, `DefaultPresetScorer`, `TransitionPolicy`, `LiveAdapter`, `ReactiveOrchestrator`, `PlannedSession`, `PresetSignaling`, `PlaybackActionRouter`, or `QualityCeiling`. Both Open and Resolved. Especially:
   - **BUG-001** (Open, P2/P3) — Money 7/4 stays REACTIVE on live path. Where does the orchestrator's reactive-vs-planned routing decision live?
   - **BUG-011** (Resolved against relaxed criteria) — Arachne frame budget; verify the `wait_for_completion_event: true` path is reachable end-to-end and that `maxDuration(forSection:)` returns `.infinity` for completion-gated presets per the in-file comment at `SessionPlanner+Segments.swift`.
   - **BUG-014** (Resolved via LM.4.7) — Lumen Mosaic palette library; verify nothing orchestrator-side encodes the deprecated panel-aggregate assumption.
   - **BUG-R009** (Resolved) — KineticSculpture sminK violated D-026 (raw AGC-energy thresholding); cross-check no orchestrator path scores against `f.bass`-style raw AGC values rather than deviation primitives.

8. **`docs/ENGINEERING_PLAN.md`** — search for "Phase 4" (Orchestrator — increments 4.1 through 4.6), "U.5" (Regenerate Plan + seeded tie-breaking), "U.6" (PlaybackActionRouter wiring), "U.6b" (live-adaptation keyboard semantics), "QR.2" (Stem-affinity scoring), and the "Recently Completed" CA.1 / CA.2 / CA.3 entries. The Phase 4 forthcoming items list (4.4 / 4.5 / 4.6) at `ARCHITECTURE.md:206-211` should be cross-referenced against actual ship state — what's still pending, what shipped, and what's now stale.

If any of these files do not exist (still a possibility — CA.1 found one such case), record the missing reference as a finding and continue with what does exist.

## Hard rules for this phase

1. **No code changes during the audit.** Findings are documented; fixes are separate increments scheduled after the audit publishes. The only file modifications allowed in CA.4 are the new audit document(s) and minor corrections to load-bearing docs (`ARCHITECTURE.md` / `ENGINEERING_PLAN.md` / `KNOWN_ISSUES.md` / `CLAUDE.md`) that the audit surfaces as drift.

2. **BUG-012-i1 instrumentation files remain off-limits to any edit (carried forward from CA.2).** The Orchestrator module has no BUG-012-i1 instrumented file. But `MLDispatchScheduler` (Renderer module — outside CA.4 scope) is consumed at the Orchestrator ↔ Renderer boundary via the `Decision` value type; reading the call site is fine, editing is not. The eight instrumented files (`StemFFT*.swift`, `StemSeparator.swift`, `Shared/BUG012Probe.swift`, `VisualizerEngine.swift`, `VisualizerEngine+Stems.swift`, `Tests/.../BUG012ConcurrencyTest.swift`) are read-only.

3. **Evidence-based:** every claim cites a file and line. "X exists at `path/file.swift:NNN`" or "X is referenced but file does not exist." No claims unverified by inspection of the actual source.

4. **`production-orphan` verdicts require a cited grep (carried forward from CA.2).** "X has zero consumers" must be backed by the exact grep command run and a summary of its results. The grep should cover `PhospheneApp/`, `PhospheneEngine/Sources/`, and `PhospheneEngine/Tests/`. Production-orphan claims without a cited grep will be rejected at closeout.

5. **Pre-grep visibility verification (carried forward from CA.3).** When parallelising file reads via Explore agents, do not trust an agent's "this type is public" / "this method is public" reports without cross-checking. After receiving each agent's report, run a single visibility grep against the file:
   ```sh
   grep -nE "^public|^[[:space:]]+public" PhospheneEngine/Sources/Orchestrator/<file>.swift
   ```
   Reconcile each agent-claimed public against the grep. **For tractable subsystems (≤ 5k LoC), CA.3 found that direct file reads eliminate this failure mode entirely** — Orchestrator at ~2,950 LoC is in that range. Default to direct reads; agents remain right for larger modules.

6. **Cross-check the kickoff prompt against `KNOWN_ISSUES.md` (new in CA.4, per CA.3 approach-validation recommendation).** As the audit's second step (right after reading the prior audit summaries), verify every "Active BUG in scope" entry the kickoff cites against the actual `KNOWN_ISSUES.md` status. CA.3 found BUG-006 was prompt-claimed Open but file-confirmed Resolved; the 30-second cross-check saved hours of false-positive diagnosis. Apply the same discipline here: BUG-001, BUG-011, BUG-014 are all named below; verify their status before reading the implementation.

7. **Exhaustive within scope.** Every `public` type, every `public` method, every documented capability in the Orchestrator subsystem gets a verdict. Coverage is binary, not best-effort.

8. **Stop-and-report criteria** (in addition to the standard `CLAUDE.md` set):
   - Found a `broken-but-claimed` finding that affects production behavior right now (file as `BUG-` entry; surface immediately).
   - The audit's reading of an Orchestrator code path reveals a plausible BUG-001 root cause (Money 7/4 stays REACTIVE). Do not fix. Document the finding in the audit + cross-link from BUG-001's section. The next BUG-001 reproduction / diagnosis is the load-bearing step, not the audit's read.
   - The synthetic-`StructuralPrediction` audit at `SessionPlanner.swift:317` reveals an architectural decision worth re-evaluating (not just CA.1-FU-1 housekeeping). Surface for Matt.
   - Audit scope is growing beyond Orchestrator — capability traces lead into Renderer (`PresetCatalog`, `MLDispatchScheduler`, `FrameBudgetManager.recentMaxFrameMs`), App (`PlaybackActionRouter` concrete in `PhospheneApp/Services/`, `VisualizerEngine+Orchestrator`), Audio (`PreFetchedTrackProfile`), or back into DSP / ML / Session. Note the boundary crossing; continue within scope; flag as `boundary-noted` (out-of-scope, no re-audit needed) or `boundary-deferred` (re-audit required when the other subsystem lands) — these are different verdicts; CA.4 should use them precisely per the CA.3 convention.
   - Discovered an architectural inconsistency that's too large to document inline. Surface for Matt.
   - The audit format is producing low-value output. Pause, redesign before continuing.

Closeout report cites the audit document, not the audit's findings. The audit document IS the deliverable.

## Scope of CA.4

### Files in scope (`PhospheneEngine/Sources/Orchestrator/`)

14 Swift files, ~2,950 LoC. Grouped by capability family:

**Scoring + policy core (3 files, ~900 LoC):**
```
PresetScorer.swift                      —  ~460 lines — DefaultPresetScorer: stateless, deterministic 4-weight scorer (mood 30 / stemAffinity 25 / sectionSuitability 25 / tempoMotion 20) + family/fatigue penalties + hard exclusions (currently-playing + complexity-cost) per D-032. QR.2 D-080 stem-affinity deviation primitives + mean formula.
PresetScoringContext.swift              —  ~200 lines — Immutable Sendable snapshot (deviceTier, frameBudgetMs, recentHistory, currentPreset, elapsedSessionTime, currentSection, familyBoosts, temporaryFamilyExclusions). PresetHistoryEntry for session history.
TransitionPolicy.swift                  —  ~250 lines — DefaultTransitionPolicy: structural boundary (confidence≥0.5, 2.5s window) beats duration-expired timer per D-033. TransitionDecision: trigger/scheduledAt/style/duration/confidence/rationale. Style from transitionAffordances + energy. Crossfade duration scales 2.0s→0.5s with energy. TransitionDeciding protocol.
```

**Planning (3 files, ~750 LoC):**
```
SessionPlanner.swift                    —  ~360 lines — DefaultSessionPlanner: greedy forward-walk per D-034. plan() / planAsync() with precompile closure. SessionPlanningError. Synthetic StructuralPrediction at line 317 (CA.1 boundary touchpoint). D-091 PlannedSession.canonicalIdentity(matchingTitle:artist:) declared here.
SessionPlanner+Segments.swift           —  ~230 lines — D-072 multi-segment-per-track planning: maxDuration(forSection:), wait_for_completion_event flag handling, presetCompletionEvent integration.
PlannedSession.swift                    —  ~420 lines — Output types: PlannedSession, PlannedTrack, PlannedTransition (D-034), PlanningWarning. PlannedSession.track(at:)/transition(at:) for playback-time O(N) lookups. PlannedSession.canonicalIdentity(matchingTitle:artist:) (D-091).
```

**Live adaptation (3 files, ~850 LoC):**
```
LiveAdapter.swift                       —  ~420 lines — DefaultLiveAdapter: subscribes to MIR features + StructuralPrediction; emits LiveAdaptationEvent (presetOverride / updatedTransition). Mood-override cooldown (30s per-track minimum per CLAUDE.md). U.6b semantics per D-058.
LiveAdapter+Patching.swift              —  ~310 lines — PlannedSession in-place patching: applyLivePatch(...), patch undo stack (capacity 8 per D-058(d)), boost/exclusion state preserved across undo (D-058(b)).
LiveAdapter+MoodOverride.swift          —  ~90 lines — Preset-substitution logic for mood-derived overrides; extracted from LiveAdapter.swift for file-length compliance.
```

**Reactive mode (1 file, ~410 LoC):**
```
ReactiveOrchestrator.swift              —  ~410 lines — DefaultReactiveOrchestrator: ad-hoc preset selection without pre-analysis (Phase 4.6). TrackProfile.empty handling (QR.2 / D-080 — verify the neutral-0.5 stem-affinity gate is in place for the empty-stem case).
```

**Signaling (2 files, ~100 LoC):**
```
PresetSignaling.swift                   —   ~45 lines — Protocol: presetCompletionEvent: PassthroughSubject<Void, Never>. Conformance: ArachneState (currently the only conformer). Lower-bound segment time-on-screen constant.
ArachneStateSignaling.swift             —   ~40 lines — ArachneState conformance to PresetSignaling via PassthroughSubject exposure. D-095.
```

**Router + settings (2 files, ~140 LoC):**
```
PlaybackActionRouter.swift              —  ~100 lines — Protocol for keyboard shortcut actions per D-050. All methods @MainActor. Concrete DefaultPlaybackActionRouter lives in PhospheneApp/Services/.
QualityCeiling.swift                    —   ~40 lines — Enum: .balanced / .ultra / (potentially more). Read by FrameBudgetManager + MLDispatchScheduler.
```

### Boundary surfaces (in scope, with annotation)

- **Orchestrator ↔ Session.** `TrackProfile` (Session module, CA.3-audited) is consumed by `DefaultPresetScorer` and `DefaultSessionPlanner.plan(...)`. `SessionPlan` (Session module, deliberately minimal stub per D-017) is lifted to `PlannedSession` here. `PlannedSession.canonicalIdentity(matchingTitle:artist:)` is consumed by `PhospheneApp/VisualizerEngine+Capture.swift:131` (BUG-006.2 fix). CA.3 already audited the Session side; CA.4 verifies the Orchestrator-side consumption shape.

- **Orchestrator ↔ DSP / MIR.** `StructuralPrediction` (DSP module, CA.1-audited) is consumed at runtime via `TransitionPolicy.swift:165` + `LiveAdapter.swift:250` + `ReactiveOrchestrator.swift:316` from a *synthetic* construction at `SessionPlanner.swift:317`. **This is the CA.1 runtime production-orphan touchpoint**: CA.1 found the real per-frame `MIRPipeline.latestStructuralPrediction` has only a prep-time consumer; the runtime path feeds from synthetic. CA.4 verifies the architecture and decides whether `CA.1-FU-1` should ship as (a) gate the per-frame chain to prep time only, or (b) wire the orchestrator to consume real per-frame predictions.

- **Orchestrator ↔ ML.** `TrackProfile.mood` (cached at end-of-prep via `MoodClassifier.currentState`) is consumed by `DefaultPresetScorer.moodMatchSubScore`. `TrackProfile.bpm` is consumed by `DefaultPresetScorer.tempoMotionSubScore`. CA.2 already audited the ML side; CA.4 verifies the Orchestrator-side consumption matches the doc claim ("Mood goes through `RenderPipeline.setMood`; `setFeatures` preserves mood across overwrites" — that's the runtime path; the Orchestrator-side reads `TrackProfile.mood`).

- **Orchestrator ↔ Audio.** `PreFetchedTrackProfile` (Audio module — `MetadataPreFetcher` output) is consumed by `DefaultPresetScorer` (via `PresetScoringContext.preFetchedProfile` field, if it exists at the time of writing) and threaded through `SessionPlanner.plan(...)`. CA.3 flagged this as the CA.3 boundary-noted item; CA.4 verifies the Orchestrator-side consumption.

- **Orchestrator ↔ Renderer.** `MLDispatchScheduler.Decision` (Renderer module) flows into `VisualizerEngine+Stems.runStemSeparation` (App layer), not directly into Orchestrator. `FrameBudgetManager.recentMaxFrameMs` is read by `MLDispatchScheduler`, not Orchestrator. **The Orchestrator-side scheduling-coupling surface is `QualityCeiling`** — exposed via the Orchestrator module for App + Renderer consumers. Boundary-noted; not deferred.

- **Orchestrator ↔ App.** `DefaultPlaybackActionRouter` (concrete) lives in `PhospheneApp/Services/`; conforms to the engine-side `PlaybackActionRouter` protocol per D-050. `VisualizerEngine+Orchestrator.swift` is the App-layer adapter that calls into `DefaultSessionPlanner` + `DefaultLiveAdapter` + `DefaultReactiveOrchestrator`. CA-App (likely CA.5 or later) audits the App-side internals; CA.4 reads the consumption shape only.

### Explicit exclusions (will be audited in later CA increments)

- `PhospheneApp/` (`VisualizerEngine+Orchestrator`, `DefaultPlaybackActionRouter`, `SessionStateViewModel`, all view models) — App layer. Defer to a future CA-App increment.
- `PhospheneEngine/Sources/Renderer/` (`MLDispatchScheduler`, `FrameBudgetManager`, `PresetCatalog`, `RenderPipeline`, etc.) — defer to a future CA-Renderer increment. CA.2's `MLDispatchScheduler` deferral stays deferred.
- `PhospheneEngine/Sources/Audio/` (`MetadataPreFetcher`, `PreFetchedTrackProfile`, `AudioInputRouter`, etc.) — defer to a future CA-Audio increment.
- `PhospheneEngine/Sources/Shared/` — broader cross-module value-type module; defer.
- `PhospheneEngine/Sources/Presets/` (per-preset state types — `ArachneState`, `MurmurationParticleConformer`, etc.) — defer to a future CA-Presets increment. **Exception:** `ArachneStateSignaling.swift` lives in `Sources/Orchestrator/` (not `Presets/`); audit that file in scope.

If something in the boundary surfaces seems important enough that the audit's value is reduced without it, note the gap and continue. Do not expand scope.

## Methodology

The methodology is the same as CA.3 with one refinement (the kickoff-vs-KNOWN_ISSUES cross-check, new in CA.4).

### Pass 0 — Kickoff cross-check (new in CA.4)

Before reading any source file, verify every BUG cited in this kickoff's "Active BUGs in scope" list against `docs/QUALITY/KNOWN_ISSUES.md`:
- BUG-001 — confirm Status, severity, last-update date.
- BUG-011 — confirm Status (kickoff claims Resolved against relaxed criteria; verify).
- BUG-014 — confirm Status (kickoff claims Resolved via LM.4.7; verify).
- Any other BUG the kickoff references in context.

If any kickoff claim disagrees with `KNOWN_ISSUES.md`, the audit's first finding is the kickoff staleness. CA.3 found BUG-006 was prompt-claimed Open but file-confirmed Resolved; the 30-second cross-check saved hours of false-positive work.

### Pass 1 — Inventory + verdict assignment

For each file in scope, produce:
- **File summary** — one paragraph: what this file owns, who its primary consumers are.
- **Public surface** — every `public` type and every `public` (or `package`) method, with brief signatures. Include `internal` types that are consumed across module boundaries.
- **Documented features** — comment headers, MARK sections, doc-comments describing intended behavior. Quote doc comments verbatim where the claim matters.
- **Notable internal types** if load-bearing (e.g. `LiveAdapter`'s `adaptationHistory` ring buffer, `SessionPlanner`'s synthetic-prediction site).
- **File-level constants / tuning values** with names and values (especially: `D-032` weight constants `0.30 / 0.25 / 0.25 / 0.20`, `D-033` `crossfadeMaxDuration: 2.0`, `crossfadeMinDuration: 0.5`, `D-058(d)` `adaptationHistoryCapacity: 8`, `presetCompletionMinSegmentSeconds`).
- **Any code-level TODOs / FIXMEs / placeholder branches.**

CA.4 defaults to **direct file reads** per CA.3's approach validation — ~2,950 LoC across 14 files is well within the tractable range (the largest file is `PresetScorer.swift` at ~460 lines). If you choose to parallelise with Explore agents, run the visibility-verification grep on every agent-claimed-public after.

Then for each capability, trace consumers via grep:
```sh
grep -rn "TypeName" PhospheneEngine/Sources PhospheneApp PhospheneEngine/Tests
```
- For functions: `grep -rn "\.functionName(" …` — call sites.
- For protocols: also find conformances via `grep -rn ": ProtocolName" …`.
- For types referenced only in tests: note as test-only (different verdict than production consumers).

Record per capability: production consumers, test consumers, no consumers. For any `production-orphan` candidate, the cited grep command + result count is mandatory.

Cross-reference each capability against the load-bearing docs (`CLAUDE.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `ENGINEERING_PLAN.md`, `KNOWN_ISSUES.md` — both Open and Resolved). Record: claimed in docs (yes/no, citations), doc claim aligned with code (yes/no, divergence noted), documented as planned-but-not-built (yes/no).

**Behaviour validation:** read evidence that exists. Is there a test? A diagnostic? A session-log narrative? Orchestrator has a substantial test surface — 16 test files under `Tests/PhospheneEngineTests/Orchestrator/`: `DiagnosticHoldTests`, `GoldenSessionTests`, `LiveAdapterTests`, `MaxDurationFrameworkTests`, `MultiSegmentSmokeTest`, `OrchestratorCertifiedFilterTests`, `OrchestratorDiagnosticExclusionTests`, `PartialPlanTests`, `PresetScorerAdaptationTests`, `PresetScorerTests`, `PresetScoringContextExtensionTests`, `PresetSignalingTests`, `ReactiveOrchestratorTests`, `SessionPlannerTests`, `StemAffinityScoringTests`, `TransitionPolicyTests`. Use them as the discriminators they are. Particular attention: `StemAffinityScoringTests` is the regression gate for D-080 (Failed Approach #53 + #54); verify it covers the `TrackProfile.empty` neutral-0.5 path.

Assign verdict per capability (definitions carried forward from CA.3):

| Verdict | Meaning |
|---|---|
| `production-active` | Consumed by production code; doc claims match code behavior; behavior validated. |
| `production-orphan` | Consumed nowhere in production code (test consumers only OR no consumers). **Requires cited grep.** |
| `dead` | Confirmed dead — no consumers anywhere; safe to delete (but deletion is a separate increment). |
| `stub` | Exists as a type/function signature but body is empty / returns default / throws unimplemented. |
| `documented-but-missing` | Docs claim it exists; code does not have it (or has been retired). |
| `built-but-undocumented` | Code has it; no doc references it. |
| `broken-but-claimed` | Docs claim it works; runtime behavior contradicts. File a `BUG-` entry immediately. |
| `unverified-claim` | Consumed; docs claim correctness; no evidence of correctness. |
| `boundary-noted` | Lives at a subsystem boundary; the audit notes the consumption shape but the verdict is complete (no future re-audit obligation). |
| `boundary-deferred` | Lives at a subsystem boundary; full verdict requires the other subsystem's audit (re-audit obligation logged for that increment). |

`boundary-noted` vs `boundary-deferred` precision matters — see CA.3's resolution of CA.1's two boundary-deferred Session files. Reserve `boundary-deferred` for cases where the other-subsystem audit will materially change the verdict; default to `boundary-noted` when the verdict is final at this audit's scope.

### Pass 2 — Doc-drift triangulation

Once verdicts are assigned, scan the load-bearing docs for additional drift that the per-capability cross-referencing didn't catch:
1. Does `ARCHITECTURE.md`'s `Orchestrator/` module-map block list every file? (CA.1 found DSP/ missing 6 of 20; CA.2 found ML/ missing 9 of 16; CA.3 found Session/ missing 13 of 22 — the systemic pattern is likely to repeat here.)
2. Are tuning constants quoted in docs identical to the code's values? (D-032 weights, D-033 crossfade durations, D-058 history capacity, D-095 completion-event minimum-segment threshold.)
3. Does any architectural claim describe a code path that no longer exists? Was retired? Was renamed?
4. Do any decisions in `DECISIONS.md` reference symbols that have moved or been renamed? (Especially D-120 — verify the revert removed all `concept_tags` / `motion_paradigm` references from `PresetDescriptor` / `DefaultPresetScorer` / `Tests/`; if any residue remains, that's a real finding.)
5. Does the `§Phase 4` forthcoming-work list at `ARCHITECTURE.md:206-211` accurately reflect what's pending vs. shipped?

Record drift findings as a separate cross-reference section in the audit doc. Pass 2 typically takes 25–40% of Pass 1's effort; budget accordingly.

### Output structure (template — same as CA.3)

Output file: `docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md`.

```markdown
# Capability Registry — Orchestrator

**Audit increment:** CA.4
**Date:** 2026-05-XX
**Auditor:** Claude (session-driven, read-only)
**Scope:** PhospheneEngine/Sources/Orchestrator/ (14 files, ~2.95k LoC) + boundary annotations.
**Methodology:** Phase CA scoping document (CA.4 kickoff).
**Reads relied on:** [list of docs read]

## Summary

[One paragraph: capability counts per verdict, the highest-priority findings, follow-up count, kickoff-vs-KNOWN_ISSUES cross-check result.]

[Drop in a Markdown table of verdict counts.]

## Findings by verdict

### broken-but-claimed (BUG entries filed)

[Per finding: capability name; what's claimed; what's actually happening; BUG entry reference; evidence citations.]

### documented-but-missing

[Per finding: capability name; where docs claim it exists; what's actually there.]

### unverified-claim

[Per finding: capability; consumer trace; lack-of-evidence note; suggested verification path.]

### production-orphan

[Per finding: capability; **cited grep command + result summary** (mandatory per CA.2+ rules); suggested next step.]

### dead, stub, built-but-undocumented, boundary-noted, boundary-deferred

[As CA.1/CA.2/CA.3 template, with the `boundary-noted` vs `boundary-deferred` distinction used precisely.]

### production-active

[Counts only — no per-finding detail unless something is noteworthy. The default verdict.]

## Per-file capability index

[One section per file. Per capability within a file: brief signature, verdict, consumer count, doc citation, evidence summary.]

[**Consolidation allowed (carried forward from CA.2/CA.3):** if the verdict distribution is heavily concentrated in `production-active` — e.g., > 80% of file-level entities — the Findings-by-verdict and Per-file-index sections may be merged into a single annotated index, with non-`production-active` rows visually marked.]

## Resolution of CA.1 runtime production-orphan re-evaluation

[Required section in CA.4 — CA.1 identified the synthetic `StructuralPrediction` construction at `SessionPlanner.swift:317` as the runtime-consumer counterpart of the per-frame `StructuralAnalyzer` chain orphan. State whether the architecture is right as-is, or whether `CA.1-FU-1` should ship as (a) gate the per-frame chain to prep time only, or (b) wire the orchestrator to consume real per-frame predictions. The choice is the audit's load-bearing CA.4-specific contribution.]

## Cross-references

### Updates needed in CLAUDE.md
### Updates needed in ARCHITECTURE.md
### Updates needed in ENGINEERING_PLAN.md
### Updates needed in DECISIONS.md
### New BUG entries
### KNOWN_ISSUES.md sweep

[Each section as CA.1/CA.2/CA.3 template. Empty sections may be deleted — say so explicitly rather than leave headers with no content.]

## Follow-up Backlog

[Every finding that is not corrected in this audit increment is registered here as a candidate follow-up increment.]

| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA.4-FU-1** | … | … | … | … |
| **CA.4-FU-2** | … | … | … | … |

[Bundling recommendation + priority-order-if-pick-one suggestion.]

[CA.4-specific note: the resolution of the CA.1 synthetic-prediction re-evaluation either closes `CA.1-FU-1` or re-scopes it as a CA.4-FU-N. State explicitly which.]

## Approach validation

[A few paragraphs: what worked in CA.4's methodology? What didn't? Recommended changes for CA.5.]
```

## File the artifact + cross-references

Per `CLAUDE.md` increment closeout protocol:
1. The audit document is the primary deliverable.
2. Any `broken-but-claimed` findings get `BUG-XXX` entries in `KNOWN_ISSUES.md` immediately.
3. `ENGINEERING_PLAN.md` gets an entry in Recently Completed (CA.4 ✅) plus the CA.4 row in the Phase CA section added with the kickoff/audit/scope/done-when narratives matching CA.1 / CA.2 / CA.3 shape.
4. `CLAUDE.md` / `ARCHITECTURE.md` drift findings are corrected in this same increment.

**Commit shape (matches CA.1 / CA.2 / CA.3 — two commits, doc-only):**
```
[CA.4] Orchestrator audit: capability registry + findings
[CA.4] ARCHITECTURE.md / ENGINEERING_PLAN.md / KNOWN_ISSUES.md / CLAUDE.md: doc-drift corrections (if any)
```

## Done-when

CA.4 closes when:

- [ ] `docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md` published.
- [ ] Every `public` capability in scope has a verdict.
- [ ] Every `production-orphan` verdict cites the grep command used.
- [ ] Every Explore-agent-claimed `public` symbol was cross-checked against a visibility grep (or direct reads were used and the verification grep ran as a final pass).
- [ ] Kickoff-vs-`KNOWN_ISSUES.md` cross-check ran as Pass 0 (CA.4 new rule). Any staleness is the audit's first finding.
- [ ] Every non-`production-active` finding either ships a doc-fix in this increment OR is registered as a `CA.4-FU-N` follow-up.
- [ ] All `broken-but-claimed` findings have BUG entries in `KNOWN_ISSUES.md`.
- [ ] **CA.1's synthetic-`StructuralPrediction` re-evaluation has a final verdict + a recommended path for `CA.1-FU-1`** in the §Resolution-of-CA.1-runtime-production-orphan-re-evaluation section.
- [ ] D-120 revert verified clean (no `concept_tags` / `motion_paradigm` residue in `PresetDescriptor` / `DefaultPresetScorer` / `Tests/`).
- [ ] Drift corrections to load-bearing docs landed.
- [ ] "Approach validation" section produces an honest critique of whether this format should continue into CA.5.
- [ ] All commits land on `main` (local). Push only on Matt's explicit approval.
- [ ] No edits to BUG-012-i1 instrumented files (carried forward from CA.2).

## After CA.4 lands

Surface to Matt:
- The audit summary (broken-but-claimed count, documented-but-missing count, production-orphan count, follow-up count).
- The verdict on CA.1's synthetic-`StructuralPrediction` re-evaluation + the recommended path for `CA.1-FU-1`.
- The recommended approach changes for CA.5 (if any).
- The recommended next subsystem for CA.5 — audit-driven, may not be the originally-anticipated next subsystem if findings suggest a different priority. Candidates after CA.4: **Audio** (Session + Orchestrator both consume `PreFetchedTrackProfile` from here; `MetadataPreFetcher` boundary already touched by CA.3); **Renderer** (still has `MLDispatchScheduler` + `PresetCatalog` deferred; the largest unaudited engine surface); **Presets** (per-preset state types; deepest leaf; could wait); **App** (the largest unaudited surface overall; `VisualizerEngine+*` + `DefaultPlaybackActionRouter` + view models).
- Any BUG-001-adjacent findings (Money 7/4 stays REACTIVE) that future diagnosis should weigh.

Do not start CA.5 in the same session.

## Failure modes to watch for

Specifically for Orchestrator-shaped audit work:

1. **Treating `DefaultPresetScorer` as a black box.** The 4-weight + family + fatigue + hard-exclusion structure is per-line traceable; the QR.2 / D-080 stem-affinity fix is per-line traceable. The audit's job is to verify the implementation matches D-032 / D-080 / Failed Approach #53–#54 verbatim. If the implementation drifts from D-032 (e.g. weights changed, penalty structure altered), that's a real finding.

2. **Synthetic-vs-real `StructuralPrediction` confusion.** The Orchestrator's runtime consumers read predictions from a synthetic construction at `SessionPlanner.swift:317`. The real per-frame predictions exist in `MIRPipeline.latestStructuralPrediction` but are read only at prep time. CA.4 must verify both paths and produce a recommendation for `CA.1-FU-1`. Do not file a fix; document the architecture.

3. **`LiveAdapter` mood-override cooldown.** Per CLAUDE.md: "Do not call `applyLiveUpdate` (mood-override path) without a per-track cooldown. The path runs at ~94 Hz on the analysis queue; without rate-limiting it re-patches `livePlan` on every frame the conditions hold. 30 s per-track cooldown is the documented minimum." Verify the cooldown is in place at `LiveAdapter+MoodOverride.swift` and that the regression test (`LiveAdapterTests` or similar) covers it.

4. **D-120 revert verification.** Per Failed Approach #59, D-120 added `concept_tags` and `motion_paradigm` fields to `PresetDescriptor` and was reverted within 24 hours. Verify the revert is clean: no `concept_tags` / `motion_paradigm` references in `PresetDescriptor`, `DefaultPresetScorer`, `PresetScoringContext`, or `Tests/PresetScorer*.swift`. If any residue remains, that's a real finding.

5. **Multi-segment-per-track planning (D-072 update + D-095).** `SessionPlanner+Segments.swift` is where the multi-segment logic lives. Verify:
   - `maxDuration(forSection:)` returns `.infinity` for `wait_for_completion_event: true` presets (matches the CLAUDE.md in-file comment).
   - The `remainingInSection` cap is still active for completion-gated segments (intentional per `CLAUDE.md`).
   - `presetCompletionEvent` subscription is wired through to the segment-transition trigger.
   - `applyLiveUpdate` strips mood-derived `presetOverride` for completion-gated active segments.

6. **`PlannedSession.canonicalIdentity(matchingTitle:artist:)` is load-bearing for BUG-006.2.** Per CLAUDE.md Failed Approach #56: this is the fix for "match plan entries against live track via lowercased title+artist string." Verify the helper is pure (no `Date.now()`, no `MainActor` isolation) and that `PreparedBeatGridAppLayerWiringTests.ambiguousMatch_returnsNil_partialFallback` regression-locks the conservative-fallback case.

7. **`ReactiveOrchestrator` `TrackProfile.empty` interaction (Failed Approach #54).** Per D-080: `stemAffinitySubScore` returns neutral 0.5 when `TrackProfile.empty.stemEnergyBalance == .zero`; reactive mode receives a live `StemFeatures` snapshot once the live stem analyzer has converged (~10 s). Verify the implementation and the regression test (`StemAffinityScoringTests` or `ReactiveOrchestratorTests`).

8. **`PresetSignaling` protocol scope.** Currently only `ArachneState` conforms (`ArachneStateSignaling.swift`). Verify no other preset state type wants to conform (Murmuration's flock-completion event was discussed in D-097 but not shipped — confirm). The protocol is intentionally narrow per D-095.

9. **D-099 engine MSL struct extension implications for the Orchestrator.** Per CLAUDE.md: "after the DM.2 / D-099 extension, the engine no longer reads past the original 32 / 16 floats, but the extended layout is preserved so a future engine kernel can read MV-1 / MV-3 fields." Verify no Orchestrator-side scoring path reads `StemFeatures` fields past index 15 (the original layout).

10. **BUG-001 (Money 7/4 stays REACTIVE on live path).** The bug is Open at last check. The orchestrator's reactive-vs-planned routing decision lives somewhere in the `SessionPlanner` / `LiveAdapter` / `ReactiveOrchestrator` cluster — verify which path Money 7/4 takes and document the finding without attempting a fix. The next BUG-001 reproduction is the load-bearing diagnosis step.

11. **Trivial-finding inflation.** 14 files; many will be `production-active`. The depth target is `PresetScorer.swift` (the 4-weight scoring core), `SessionPlanner.swift` (the synthetic-prediction site + canonical-identity helper + multi-segment logic), `LiveAdapter.swift` (the live-adaptation cooldown + undo stack), and `ReactiveOrchestrator.swift` (the TrackProfile.empty + D-080 interaction). Smaller files (`QualityCeiling`, `PresetSignaling`, `ArachneStateSignaling`, `PlaybackActionRouter`) get surface-level `production-active` rows.

12. **Citing without verifying.** Same as CA.1/CA.2/CA.3's rule. Every claim is evidence-backed with a `file:line` or a `doc:line`.

13. **Producing structure as a substitute for substance.** Headers must be backed by content. Empty buckets should be said-empty, not pretended-incomplete.

## Status on entry

- **Branch:** `main`. CA.3 has landed in 2 commits on `main`, pushed to `origin/main` 2026-05-20. The most recent commits are `f969aa72` [CA.3] ARCHITECTURE.md / ENGINEERING_PLAN.md: doc-drift corrections from Session audit and `b7b02ff4` [CA.3] Session audit: capability registry + findings.
- Local + remote `main` includes CA.0 + CA.1 + CA.2 + CA.3 + BUG-012-i1 instrumentation + Phase CS scoping.
- Working tree clean (`default.profraw` is a documented build artifact).
- **BUG-012 is Open.** BUG-012-i1 instrumentation in place. Step 2 (diagnosis) waits on a reproduction. CA.4 does not interfere — Orchestrator has no BUG-012-instrumented files in scope.
- **BUG-001 is Open.** The audit may surface findings relevant to its diagnosis; document them, do not fix.
- **No CA.4 code or audit has landed.** This is the kickoff.

## Sign-off

This prompt is the canonical entry point for Increment CA.4. The Phase CA wider scoping (what subsystem comes next, the master `docs/CAPABILITY_REGISTRY.md` index file) continues to be one-increment-at-a-time per the CA.0 scoping decision.

If you find the prompt is wrong or stale during the audit, update the prompt before continuing — do not work against a brief you know to be incorrect.

— Matt + Claude (2026-05-20 design session, post-CA.3 closeout)
