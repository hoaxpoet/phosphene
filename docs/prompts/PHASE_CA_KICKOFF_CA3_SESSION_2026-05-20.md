# Phase CA Kickoff — Capability Audit — Increment CA.3 (Session)

**Hand this to a new Claude Code session verbatim. Do not summarise.**

---

## What this phase is

**Phase CA — Capability Audit** is a multi-increment archaeology of Phosphene's codebase. Each increment audits one subsystem: reads the actual source, traces consumers and producers, cross-references against `CLAUDE.md` / `docs/ARCHITECTURE.md` / `docs/QUALITY/KNOWN_ISSUES.md` / `docs/DECISIONS.md`, and assigns a health verdict to every capability the subsystem exposes.

CA.1 (DSP / MIR) closed 2026-05-20 at [`docs/CAPABILITY_REGISTRY/DSP_MIR.md`](../CAPABILITY_REGISTRY/DSP_MIR.md). It validated the audit format, surfaced one runtime `production-orphan` cluster (per-frame `StructuralAnalyzer` chain), surfaced one minor field-level orphan, and applied doc-drift corrections to `ARCHITECTURE.md` (DSP/ module-map drift, MIR-pipeline-component list, Chroma 65→500 Hz tuning value, Session-Recording manual-`R`-path note) plus ENGINEERING_PLAN.md pointer correction. CA.1 also identified `BeatGridAnalyzer.swift` and `GridOnsetCalibrator.swift` as `boundary-deferred` to a Session subsystem audit.

CA.2 (ML) closed 2026-05-20 at [`docs/CAPABILITY_REGISTRY/ML.md`](../CAPABILITY_REGISTRY/ML.md). It audited all 16 ML files (4,507 LoC), surfaced four cluster-level `production-orphan` findings (`StemFFTEngineProtocol`, `StemSeparator.stft/.istft` wrappers, five `BeatThisModel` model-dimension constants, `MoodClassifier.featureCount/.emaAlpha` + three error-type public exposures), two large `built-but-undocumented` gaps (Beat This! transformer absent from `ARCHITECTURE.md §ML Inference`; `ML/` module-map missing 9 of 16 files), and one `documented-but-missing` (Mood Classifier flux normalization claim was stale). All drift corrected in the same increment. The audit did not edit any BUG-012-i1 instrumented file per Hard Rules. CA.2 also produced a centralised §BUG-012 instrumentation map cross-linked from `KNOWN_ISSUES.md`. CA.2's approach-validation section surfaced one methodology refinement: Explore agents over-asserted `public` on internal types in 3 of 4 CA.2 cases, so CA.3 adds an explicit pre-grep visibility-verification step (see §Methodology below).

**This kickoff is for Increment CA.3: the Session subsystem.** It is the third audit pass.

## Why Session next

Three reasons (carried forward from CA.2's approach-validation recommendation):

1. **Three CA.1/CA.2 boundary-deferred items resolve here.** CA.1 flagged `BeatGridAnalyzer.swift` and `GridOnsetCalibrator.swift` as functionally-DSP-but-file-located-in-Session. CA.2 flagged `MoodClassifier.currentState` being read at end-of-prep in `SessionPreparer+Analysis.swift:295` as worth re-evaluating in a Session audit. All three resolve in this increment.
2. **CA.1 surfaced one runtime `production-orphan` whose only live consumer lives in Session.** `MIRPipeline.latestStructuralPrediction` is read at preparation time only by `SessionPreparer+Analysis.swift:289`. The CA.1 follow-up `CA.1-FU-1` asked whether to gate the per-frame StructuralAnalyzer chain to prep time or wire it to runtime. That follow-up's planning depends on understanding what Session does with it today — CA.3 answers that.
3. **The Spotify connector cluster is recent, dense, and has active learnings.** `SpotifyTokenProvider` (D-068, Increment U.10), `SpotifyWebAPIConnector` (D-070, U.11 follow-up), and `SpotifyOAuthTokenProvider` (D-069, U.11; lives in PhospheneApp by design — outside our scope but the protocol lives in Session) all landed in the last ~3 weeks. Failed Approaches #45 (response schema), #46 (`fields` parameter), #47 (preview_url discard) and the U.10/U.11 code-style learnings (URLProtocol `@Suite(.serialized)`, `@MainActor` debounce timing, app-layer vs engine-layer logger placement) all cluster here. Active BUGs in scope: **BUG-005** (Spotify preview_url null), **BUG-006** (Spotify-prepared session doesn't install prepared BeatGrid — falls through to liveAnalysis).

## Read these first, before doing anything else

1. **`CLAUDE.md`** — the entire file. Note especially: the Session Preparation Pipeline pointer, the Audio Data Hierarchy (layer 5 — pre-analyzed stems available from first frame, replaced by real-time stems after ~10 s), the UX Contract pointer (`SessionState` → view mapping), Failed Approaches #45 / #46 / #47 (Spotify connector edge cases), the QR.3 silent-skip-test discipline rule, and the Defect Handling Protocol's domain-tag taxonomy.
2. **`docs/CAPABILITY_REGISTRY/DSP_MIR.md`** — the CA.1 audit. Read the §boundary-deferred section verbatim: the two `Sources/Session/*.swift` files CA.1 deferred to here are `GridOnsetCalibrator.swift` and `BeatGridAnalyzer.swift`. CA.1's read of their *DSP-side* function is correct; CA.3 audits their *Session-side* function (where they live, what their protocol pattern serves, whether the relocation recommendation should ship).
3. **`docs/CAPABILITY_REGISTRY/ML.md`** — the CA.2 audit. Read §Cross-references and the §BUG-012 instrumentation map. CA.3 audits `SessionPreparer+Analysis.swift` (which composes `BeatGridAnalyzer` + `StemSeparator` + `MoodClassifier`) — the ML-side reads CA.2 produced for these calls are CA.3's starting context. Particular attention: the `production-active` row for `MoodClassifier.currentState` in CA.2's per-file index — that's the read-at-end-of-prep pattern CA.3 should evaluate.
4. **`docs/ARCHITECTURE.md`** — sections "Session Lifecycle", "Session Preparation", "Session Recording (Diagnostics)" (auto-recording path; the `R`-shortcut manual MIR path is a CA.1 finding), "Long-Session Resilience (Increment 7.2)" (`DisplayChangeCoordinator` / `CaptureModeSwitchCoordinator` / `NetworkRecoveryCoordinator` — these are App-layer concerns but they observe and call into `SessionManager`, so the boundary surfaces here), and the "Session/" module-map block at lines 544–554. CA.1+CA.2 each found their respective module-map block missing files; verify the Session/ block against actual files as part of this audit.
5. **`docs/DECISIONS.md`** — grep for D-008 (Playlist-first session preparation), D-017 (SessionState/SessionPlan in Session module not Shared), D-018 (SessionManager degrades to ready on any preparation failure), D-019 (Stem routing warmup fallback pattern), D-046 (Connector picker architecture), D-052 (CaptureModeReconciler), D-056 (Progressive readiness architecture), D-061 (Long-session resilience), D-068 (Spotify client-credentials connector — superseded), D-069 (Spotify OAuth + PKCE), D-070 (Spotify /items response schema + preview_url capture), D-079 (Sample-rate plumbing — touches SessionPreparer indirectly), D-080 (Stem-affinity scoring — touches TrackProfile), D-091 (QR.4 dead-end views + SettingsStore collapse — touched Session via state propagation).
6. **`docs/QUALITY/KNOWN_ISSUES.md`** — every entry tagged `dsp.beat` or `dsp.audio` or `orchestrator` that references `SessionManager` / `SessionPreparer` / `PreviewResolver` / `PreviewDownloader` / `StemCache` / `TrackProfile` / `PreFetchedTrackProfile` / `MetadataPreFetcher` / Spotify connectors. Both Open and Resolved. **Especially:**
   - **BUG-005** (Open, P2) — Spotify `preview_url` returns null for some tracks.
   - **BUG-006** (Open, P1) — Spotify-prepared session does not install prepared BeatGrid (falls through to liveAnalysis). The audit reads BUG-006's reproduction notes and verifies whether the install path described in `SessionPreparer+Analysis.swift` matches the documented contract.
   - **QR.2 / D-080** (Resolved) — Stem-affinity scoring used `TrackProfile.empty.stemEnergyBalance`; the fix is now installed but the reactive-mode `TrackProfile.empty` path still exists. Audit confirms whether the QR.2 fix is fully wired or whether vestigial state remains.
   - The BUG-R001…R010 retroactive-Resolved entries that touch Session (BUG-R002 hardcoded 44100 in Beat This! call, BUG-R003 StemSampleBuffer undersized, BUG-R004 live Beat This! double-time on short window) — primarily DSP/ML, but Session was the call-site originator for several.
7. **`docs/ENGINEERING_PLAN.md`** — search for "Phase 2.5" (Session State Machine), "Phase 4" (Orchestrator — consumes Session output), "U.3" (Playlist connector picker, D-046), "U.5" (Ready view + first-audio autodetect, D-056), "U.10" (Spotify client-credentials, D-068), "U.11" (Spotify OAuth + PKCE, D-069 / D-070), "6.1" (Progressive readiness, D-056), "QR.2" (Stem-affinity scoring), "QR.3" (silent-skip discipline including `SpotifyItemsSchemaTests`), "QR.4" (SettingsStore collapse + chrome-binding fixes).

If any of these files do not exist (still a possibility — CA.1 found one such case), record the missing reference as a finding and continue with what does exist.

## Hard rules for this phase

- **No code changes during the audit.** Findings are documented; fixes are separate increments scheduled after the audit publishes. The only file modifications allowed in CA.3 are the new audit document(s) and minor corrections to load-bearing docs (`ARCHITECTURE.md` / `ENGINEERING_PLAN.md` / `KNOWN_ISSUES.md` / `CLAUDE.md`) that the audit surfaces as drift.

- **BUG-012-i1 instrumentation files remain off-limits to any edit** (carried forward from CA.2). The Session-side BUG-012-i1 surface is `PhospheneApp/VisualizerEngine.swift` and `PhospheneApp/VisualizerEngine+Stems.swift` (lifecycle markers, `runStemSeparation` log lines) — these are App-layer files and out of CA.3 scope anyway, but reaffirm here: read freely, do not modify. The Session module itself has no BUG-012-i1 instrumented file, but `SessionPreparer+Analysis.swift` calls `separator.separate(...)` which goes through the instrumented dispatch chain. Reading the call site is fine; editing it is not.

- **Evidence-based: every claim cites a file and line.** "X exists at `path/file.swift:NNN`" or "X is referenced but file does not exist." No claims unverified by inspection of the actual source.

- **`production-orphan` verdicts require a cited grep** (carried forward from CA.2). "X has zero consumers" must be backed by the exact `grep` command run and a summary of its results. The grep should cover `PhospheneApp/`, `PhospheneEngine/Sources/`, and `PhospheneEngine/Tests/`. Production-orphan claims without a cited grep will be rejected at closeout.

- **Pre-grep visibility verification (new in CA.3, per CA.2 approach-validation recommendation).** When parallelising file reads via Explore agents, do not trust an agent's "this type is public" / "this method is public" reports without cross-checking. After receiving each agent's report, run a single visibility grep against the file:
  ```
  grep -nE "^public|^[[:space:]]+public" PhospheneEngine/Sources/Session/<file>.swift
  ```
  Reconcile each agent-claimed `public` against the grep. CA.2 had three of four agents over-assert publicness (often confusing extension-internal helpers with `public static func` exposure); the 30-second cross-check catches this before verdicts are assigned.

- **Exhaustive within scope.** Every public type, every public method, every documented capability in the Session subsystem gets a verdict. Coverage is binary, not best-effort.

- **Stop-and-report criteria** (in addition to the standard CLAUDE.md set):
  - Found a `broken-but-claimed` finding that affects production behavior right now (file as BUG entry; surface immediately).
  - The audit's reading of a Session code path reveals a plausible BUG-006 root cause (Spotify-prepared session not installing prepared BeatGrid). **Do not fix.** Document the finding in the audit + cross-link from BUG-006's section. The next BUG-006 reproduction / diagnosis is the load-bearing step, not the audit's read.
  - Audit scope is growing beyond Session — capability traces lead into Orchestrator (`SessionPlanner` consumes `TrackProfile`; `DefaultPresetScorer` consumes `PreFetchedTrackProfile`), Audio (`PreviewAudio` value type), App (`SessionManager` is `@MainActor` and consumed by `VisualizerEngine` + view models), or back into DSP / ML. Note the boundary crossing; continue within scope; flag as `boundary-noted` (out-of-scope, no re-audit needed) or `boundary-deferred` (re-audit required when the other subsystem lands) — these are different verdicts; CA.3 should use them precisely.
  - Discovered an architectural inconsistency that's too large to document inline. Surface for Matt.
  - The audit format is producing low-value output. Pause, redesign before continuing.

- **Closeout report cites the audit document, not the audit's findings.** The audit document IS the deliverable.

## Scope of CA.3

### Files in scope (`PhospheneEngine/Sources/Session/`)

20 Swift files in the top-level directory + 2 in `Connectors/` = 22 files total, ~3,000 LoC. Grouped by capability family:

**Lifecycle + state machine:**
```
Session.swift                          —    5 lines — Module marker.
SessionTypes.swift                     —  124 lines — SessionState enum, SessionPlan stub, defaults.
SessionManager.swift                   —  354 lines — Top-level @MainActor ObservableObject; state machine.
SessionManager+Readiness.swift         —   82 lines — Progressive readiness level transitions (D-056).
PreparationProgressPublishing.swift    —   35 lines — Protocol seam for progress observation.
TrackPreparationStatus.swift           —   75 lines — Per-track preparation state value type.
```

**Preparation pipeline:**
```
SessionPreparer.swift                  —  383 lines — Per-track preparation orchestrator.
SessionPreparer+Analysis.swift         —  353 lines — Composes StemSeparator + StemAnalyzer + MoodClassifier + BeatGridAnalyzer; section-count derivation from MIRPipeline.
SessionPreparer+WiringLogs.swift       —  118 lines — Diagnostic logs for the preparation pipeline.
PreviewResolver.swift                  —  171 lines — TrackIdentity → preview URL (Spotify inline → iTunes Search fallback).
PreviewDownloader.swift                —  202 lines — Batch download + AVAudioFile decode to mono Float32.
StemCache.swift                        —  132 lines — Per-track waveform + StemFeatures + TrackProfile cache (NSLock-guarded).
```

**Track / Playlist value types:**
```
TrackIdentity.swift                    —  143 lines — Stable cache key (title/artist/album/duration/catalog IDs).
TrackProfile.swift                     —   65 lines — BPM/key/mood/stem-energy-balance/section-count value type.
PlaylistConnector.swift                —  254 lines — Apple Music + Spotify + URL parsing; PlaylistConnector protocol.
LocalFolderConnector.swift             —   25 lines — Local audio folder enumeration.
```

**Boundary-deferred from CA.1 (now in CA.3 scope):**
```
GridOnsetCalibrator.swift              —  198 lines — Median per-track grid-vs-onset offset calibration (BUG-007.8 / D-079).
BeatGridAnalyzer.swift                 —   81 lines — Composes BeatThisPreprocessor + BeatThisModel + BeatGridResolver into BeatGridAnalyzing protocol.
```

**Quality gates:**
```
BPMMismatchCheck.swift                 —  181 lines — Verifies metadata BPM vs ML-detected BPM; warns on disagreement (BUG-008 surface).
```

**Connectors/ subdirectory:**
```
SpotifyTokenProvider.swift             — Spotify client-credentials token provider (deprecated by D-069; protocol seam retained for OAuth).
SpotifyWebAPIConnector.swift           — Spotify Web API /v1/playlists endpoint integration (D-070, /items schema).
```

### Boundary surfaces (in scope, with annotation)

- **Session ↔ DSP** — `SessionPreparer+Analysis.analyzePreview` calls into DSP via the `analyzer: any StemAnalyzing` parameter (production conformer: `StemAnalyzer` in DSP). `BeatGridAnalyzer` composes `BeatThisPreprocessor` + `BeatGridResolver` (DSP-side, both audited in CA.1). `GridOnsetCalibrator` constructs a live `BeatDetector` and replays preview audio offline through it. Verify the Session-side coordination is consistent with CA.1's DSP-side findings.
- **Session ↔ ML** — `SessionPreparer+Analysis` calls `separator.separate(...)` (ML, CA.2-audited), reads `separator.stemBuffers` for the mono waveforms, calls `classifier.currentState` at end-of-prep (CA.2 finding — re-evaluate the architectural shape: is it correct that `currentState` is read at end-of-prep rather than the per-frame `classify(features:)` result being aggregated?). `BeatGridAnalyzer` calls `model.predict(spectrogram:frameCount:)` (ML, CA.2-audited).
- **Session ↔ Audio** — `PreviewDownloader` produces `PreviewAudio` (pcmSamples, sampleRate). `SessionPreparer` consumes via the per-track preparation pipeline. The `PreviewAudio` type lives in Audio module; the consumption shape is Session's.
- **Session ↔ Orchestrator** — `TrackProfile` (CachedTrackData → DefaultPresetScorer); `PreFetchedTrackProfile` (MetadataPreFetcher → DefaultPresetScorer / SessionPlanner); `CachedTrackData` exposed from `StemCache`. Note the producer-shape from Session without re-auditing Orchestrator (deferred to CA.4+).
- **Session ↔ App** — `SessionManager` is `@MainActor ObservableObject`; observed by `SessionStateViewModel` and `VisualizerEngine`. `progressiveReadinessLevel` published separately. `PreparationProgressPublishing` protocol consumed by `PreparationProgressView`. Note the consumption shape; do not audit App layer internals.

### Explicit exclusions (will be audited in later CA increments)

- `PhospheneEngine/Sources/Orchestrator/` (SessionPlanner, PresetScorer, etc.) — defer to future CA-Orchestrator increment.
- `PhospheneEngine/Sources/Renderer/` — defer to future CA-Renderer increment. `MLDispatchScheduler` deferred from CA.2 stays deferred.
- `PhospheneApp/` (SessionStateViewModel, SpotifyConnectionViewModel, SpotifyOAuthTokenProvider, SpotifyKeychainStore, VisualizerEngine, view models) — App layer. Defer to future CA-App increment. The `SpotifyOAuthTokenProvider` lives in PhospheneApp by design (D-069); audit the engine-side `SpotifyTokenProviding` protocol it conforms to.
- `PhospheneEngine/Sources/Audio/` — defer to future CA-Audio increment. `PreviewAudio` (Audio module) is consumed by Session; CA.3 reads but does not audit Audio internals.
- `PhospheneEngine/Sources/Shared/` — broader cross-module value-type module; defer.

If something in the boundary surfaces seems important enough that the audit's value is reduced without it, note the gap and continue. Do not expand scope.

## Methodology

The methodology is the same as CA.2 with one refinement (the pre-grep visibility verification from CA.2's approach-validation section).

### Pass 1 — Inventory + verdict assignment

For each file in scope, produce:

- **File summary** — one paragraph: what this file owns, who its primary consumers are.
- **Public surface** — every `public` type and every `public` (or `package`) method, with brief signatures. Include `internal` types that are consumed across module boundaries.
- **Documented features** — comment headers, MARK sections, doc-comments describing intended behavior. Quote doc comments verbatim where the claim matters.
- **Notable internal types** if load-bearing (e.g. `SessionPreparer`'s per-track Task graph, `StemCache`'s NSLock-guarded storage).
- **File-level constants / tuning values** with names and values.
- **Any code-level TODOs / FIXMEs / placeholder branches**.

Use the Explore agent for breadth (parallelise reads); synthesise per-file findings yourself. **Then run a visibility-verification grep against every file the agent claimed publicness for, before assigning verdicts.** Three of four CA.2 Explore agents over-asserted publicness; trust-but-verify.

Then for each capability, trace consumers via grep:

- `grep -rn "TypeName" PhospheneEngine/Sources PhospheneApp` — direct references.
- For functions: `grep -rn "\.functionName(" …` — call sites.
- For protocols: also find conformances via `grep -rn ": ProtocolName" …`.
- For types referenced only in tests: note as `test-only` (different verdict than production consumers).

Record per capability: production consumers, test consumers, no consumers. **For any `production-orphan` candidate, the cited grep command + result count is mandatory.**

Cross-reference each capability against the load-bearing docs (`CLAUDE.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `ENGINEERING_PLAN.md`, `KNOWN_ISSUES.md` — both Open and Resolved). Record: **claimed in docs** (yes/no, citations), **doc claim aligned with code** (yes/no, divergence noted), **documented as planned-but-not-built** (yes/no).

Behaviour validation: read evidence that exists. Is there a test? A diagnostic? A session-log narrative? **Session has a substantial test surface** — `SessionManagerTests`, `SessionPreparerTests`, `SessionPreparerProgressTests`, `ProgressiveReadinessTests`, `SessionManagerCancelTests`, `PreviewResolverTests`, `PreviewDownloaderTests`, `PlaylistConnectorTests`, `BPMMismatchCheckTests`, `GridOnsetCalibratorTests`, `SpotifyWebAPIConnectorTests`, `SpotifyTokenProviderTests`, `SpotifyItemsSchemaTests`, `TrackPreparationStatusTests`. Use them as the discriminators they are. **Particular attention:** the QR.3 silent-skip-test discipline rule (D-090) — verify `BeatThisFixturePresenceGate`-style precondition tests are in place for Session integration fixtures.

Assign verdict per capability:

| Verdict | Meaning |
|---|---|
| `production-active` | Consumed by production code; doc claims match code behavior; behavior validated. |
| `production-orphan` | Consumed nowhere in production code (test consumers only OR no consumers). **Requires cited grep.** |
| `dead` | Confirmed dead — no consumers anywhere; safe to delete (but deletion is a separate increment). |
| `stub` | Exists as a type/function signature but body is empty / returns default / throws unimplemented. |
| `documented-but-missing` | Docs claim it exists; code does not have it (or has been retired). |
| `built-but-undocumented` | Code has it; no doc references it. |
| `broken-but-claimed` | Docs claim it works; runtime behavior contradicts. File a BUG entry immediately. |
| `unverified-claim` | Consumed; docs claim correctness; no evidence of correctness. |
| `boundary-noted` | Lives at a subsystem boundary; the audit notes the consumption shape but the verdict is complete (no future re-audit obligation). |
| `boundary-deferred` | Lives at a subsystem boundary; **full verdict requires the other subsystem's audit** (re-audit obligation logged for that increment). |

**`boundary-noted` vs `boundary-deferred` is new in CA.3.** CA.1 used "boundary-deferred" for both shapes loosely; CA.2 noted the conflation. Use precisely: `boundary-noted` = "I'm not the right subsystem to audit this, but the verdict is final"; `boundary-deferred` = "the verdict depends on what the other subsystem's audit finds." Two of CA.1's boundary-deferred items (`GridOnsetCalibrator`, `BeatGridAnalyzer`) are now in CA.3 scope and get a real verdict — confirming they were correctly classified `boundary-deferred` (not `boundary-noted`).

### Pass 2 — Doc-drift triangulation

Once verdicts are assigned, scan the load-bearing docs for *additional* drift that the per-capability cross-referencing didn't catch:

- Does `ARCHITECTURE.md`'s `Session/` module-map block list every file? (CA.1 found `DSP/` was missing 6 of 20; CA.2 found `ML/` was missing 9 of 16.)
- Are tuning constants quoted in docs identical to the code's values?
- Does any architectural claim describe a code path that no longer exists? Was retired? Was renamed?
- Do any decisions in `DECISIONS.md` reference symbols that have moved or been renamed? (D-068 was superseded by D-069 — verify the connector-architecture text still aligns with current code.)
- Does the `UX_SPEC.md` state-to-view mapping reference `SessionState` values that still exist as the docs claim?

Record drift findings as a separate cross-reference section in the audit doc. Pass 2 typically takes 25–40% of Pass 1's effort; budget accordingly.

## Output structure (template — same as CA.2)

Output file: `docs/CAPABILITY_REGISTRY/SESSION.md`.

```markdown
# Capability Registry — Session

**Audit increment:** CA.3
**Date:** 2026-05-XX
**Auditor:** Claude (session-driven, read-only)
**Scope:** PhospheneEngine/Sources/Session/ (22 files, ~3.0k LoC) + boundary annotations.
**Methodology:** Phase CA scoping document (CA.3 kickoff).
**Reads relied on:** [list of docs read]

## Summary

[One paragraph: capability counts per verdict, the highest-priority findings, follow-up count.]

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
[As CA.1/CA.2 template, with the new `boundary-noted` vs `boundary-deferred` distinction.]

### production-active
[Counts only — no per-finding detail unless something is noteworthy. The default verdict.]

## Per-file capability index

[One section per file. Per capability within a file: brief signature, verdict, consumer count, doc citation, evidence summary.]

[**Consolidation allowed (carried forward from CA.2):** if the verdict distribution is heavily concentrated in `production-active` — e.g., > 80 % of file-level entities — the Findings-by-verdict and Per-file-index sections may be merged into a single annotated index, with non-`production-active` rows visually marked. Use discretion. Keep them split when at least one non-`production-active` bucket has ≥ 3 findings.]

## Resolution of CA.1 / CA.2 boundary-deferred items

[Required section in CA.3 — CA.1 deferred two Session files (`GridOnsetCalibrator`, `BeatGridAnalyzer`) and one architectural pattern (`MoodClassifier.currentState` end-of-prep read). State the verdict for each and whether the relocation/restructure recommendations should ship as a follow-up.]

## Cross-references

### Updates needed in CLAUDE.md
### Updates needed in ARCHITECTURE.md
### Updates needed in ENGINEERING_PLAN.md
### Updates needed in DECISIONS.md
### New BUG entries
### KNOWN_ISSUES.md sweep

[Each section as CA.1/CA.2 template. Empty sections may be deleted — say so explicitly rather than leave headers with no content. ("No drift found in DECISIONS.md" is sufficient as a one-line note.)]

## Follow-up Backlog

[**MANDATORY in CA.2 onwards** — this is the gap CA.1 surfaced. Every finding that is not corrected in this audit increment is registered here as a candidate follow-up increment.]

| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA.3-FU-1** | [one-line scope, enough to act on cold] | [verifiable done-when] | [1, 1-2, <1] | [Ready now / Blocked on X] |
| **CA.3-FU-2** | … | … | … | … |

[After the table: a one-paragraph **Bundling recommendation** + a one-line **Priority order if Matt picks just one this week** suggestion.]

[The Follow-up Backlog and the Findings-by-verdict sections should correlate: every non-`production-active` finding either ships a doc-fix in this increment OR registers as a CA.3-FU-N entry. Findings without a follow-up are stating "this is fine as-is and requires no action" — say so explicitly.]

## Approach validation

[A few paragraphs: what worked in CA.3's methodology? What didn't? Recommended changes for CA.4.]
```

## File the artifact + cross-references

Per CLAUDE.md increment closeout protocol:

- The audit document is the primary deliverable.
- Any `broken-but-claimed` findings get BUG-XXX entries in `KNOWN_ISSUES.md` immediately.
- ENGINEERING_PLAN.md gets an entry in Recently Completed (`CA.3 ✅`) plus the CA.3 row in the Phase CA section flipped from "Pending" to "✅ Landed".
- CLAUDE.md / ARCHITECTURE.md drift findings are corrected in this same increment.

Commit shape (matches CA.1/CA.2):

1. `[CA.3] Session audit: capability registry + findings`
2. `[CA.3] KNOWN_ISSUES: BUG-XXX entries from Session audit findings` (if any)
3. `[CA.3] ARCHITECTURE.md / ENGINEERING_PLAN.md / DECISIONS.md / CLAUDE.md: doc-drift corrections`

## Done-when

CA.3 closes when:

- [ ] `docs/CAPABILITY_REGISTRY/SESSION.md` published.
- [ ] Every public capability in scope has a verdict.
- [ ] Every `production-orphan` verdict cites the grep command used.
- [ ] Every Explore-agent-claimed `public` symbol was cross-checked against a visibility grep before its verdict was assigned (CA.3 new rule).
- [ ] Every non-`production-active` finding either ships a doc-fix in this increment OR is registered as a `CA.3-FU-N` follow-up.
- [ ] All `broken-but-claimed` findings have BUG entries in `KNOWN_ISSUES.md`.
- [ ] CA.1's two `boundary-deferred` Session files (`GridOnsetCalibrator`, `BeatGridAnalyzer`) have a final verdict + a relocation recommendation in the §Resolution-of-CA.1/CA.2-boundary-deferred-items section.
- [ ] CA.2's `MoodClassifier.currentState` end-of-prep architectural pattern has been re-evaluated and a verdict assigned.
- [ ] Drift corrections to load-bearing docs landed.
- [ ] "Approach validation" section produces an honest critique of whether this format should continue into CA.4.
- [ ] All commits land on `main` (local). Push only on Matt's explicit approval.
- [ ] No edits to BUG-012-i1 instrumented files (carried forward from CA.2).

## After CA.3 lands

Surface to Matt:

- The audit summary (broken-but-claimed count, documented-but-missing count, production-orphan count, follow-up count).
- The verdict on the three CA.1/CA.2 boundary-deferred items + relocation recommendations if any.
- The recommended approach changes for CA.4 (if any).
- The recommended next subsystem for CA.4 — audit-driven, may not be the originally-anticipated next subsystem if findings suggest a different priority. **Candidates after CA.3:** Orchestrator (consumes Session output), Audio (Session consumes PreviewAudio from here), Renderer (still has MLDispatchScheduler deferred from CA.2), App (the largest unaudited surface; SessionStateViewModel + SpotifyConnectionViewModel + SpotifyOAuthTokenProvider + VisualizerEngine cluster).
- Any BUG-006-adjacent findings that future diagnosis should weigh.

Do not start CA.4 in the same session.

## Failure modes to watch for

Specifically for Session-shaped audit work:

- **Treating `SessionPreparer+Analysis.swift` as a black box.** It composes three subsystems (DSP via `StemAnalyzer`, ML via `StemSeparator` + `MoodClassifier` + `BeatGridAnalyzer`, Audio via `PreviewAudio`). The audit's job is to verify the *Session-side composition shape* — what protocols are accepted, what value types flow, when `nil` is permitted, when failure short-circuits, when `degrades-to-ready` per D-018 — without re-auditing the subsystem internals (CA.1 + CA.2 already did that). The temptation to re-read the DSP/ML internals because the call site lives in Session is real and wrong.
- **Spotify connector sprawl.** D-068 → D-069 → D-070 + U.10 → U.11 + Failed Approaches #45 / #46 / #47 + `SpotifyOAuthTokenProvider` (App layer) + `SpotifyKeychainStore` (App layer) + `SpotifyTokenProviding` (Session protocol) + `SpotifyWebAPIConnector` (Session) is a deeply layered cluster. Stay in scope: audit the engine-side `Connectors/SpotifyTokenProvider.swift` + `SpotifyWebAPIConnector.swift` + the `SpotifyTokenProviding` protocol. The App-layer concrete OAuth provider is a `boundary-noted` consumer; the audit reads but does not exhaustively check it.
- **`@MainActor ObservableObject` testing complexity.** `SessionManager` is `@MainActor`. Test code under `Tests/Session/` uses careful awaits and `MainActor.run` for state observation. The CLAUDE.md timing-margin learning (U.11 widened debounce-wait from 400ms → 700ms under parallel test execution) is the load-bearing context. Do not regress this in any recommendation.
- **`PreFetchedTrackProfile` (Audio module) vs `TrackProfile` (Session module).** Different value types; different lifecycles. PreFetched comes from `MetadataPreFetcher` and feeds metadata-derived BPM/key/etc. into preparation. TrackProfile is the post-analysis output, written into `CachedTrackData`. The Orchestrator consumes both. Confusing them in the audit narrative will produce wrong findings.
- **BUG-006 (Spotify-prepared session doesn't install prepared BeatGrid).** Open P1, lives at the Session↔ML composition seam. The audit's read of `SessionPreparer+Analysis.swift` may surface a plausible root cause. **Do not fix.** Document the finding; cross-link from BUG-006's section. The next diagnosis increment owns the fix.
- **Progressive readiness state propagation.** `progressiveReadinessLevel` is orthogonal to `SessionState` per D-056. Verify the doc claim aligns with the code: the level transitions while the state stays `.preparing`, then continues advancing through `.ready` and `.playing`. The `.partial` threshold rule (BPM + at least one genre tag) is in `SessionTypes.defaultProgressiveReadinessThreshold`. Audit verifies the rule, not the threshold tuning.
- **`SessionState.idle` vs `SessionState.connecting` vs `.preparing` vs `.ready` vs `.playing` vs `.ended` transitions.** D-018 specifies the degrade-on-failure rules. The audit verifies that every transition the docs claim is implemented + tested + non-trivial-to-bypass. Failed Approach #41 (deleted UI test surface — see UX_SPEC.md §15) is the cautionary tale for "tests removed because they were flaky" → behaviour silently changes.
- **Citing without verifying.** Same as CA.1/CA.2's rule. Every claim is evidence-backed with a file:line or a doc:line.
- **Producing structure as a substitute for substance.** Headers must be backed by content. Empty buckets should be said-empty, not pretended-incomplete.
- **Trivial-finding inflation.** 22 files; many will be `production-active`. The depth target is `SessionPreparer+Analysis.swift` (353 lines, composes three subsystems, BUG-006 surface, the carry-forward CA.1/CA.2 findings), `SessionManager.swift` (354 lines, state machine, degrades-to-ready discipline), the `SpotifyWebAPIConnector` + `SpotifyTokenProvider` pair (recent code with active Failed-Approaches), and the boundary-deferred `BeatGridAnalyzer` + `GridOnsetCalibrator`. Surface-level `production-active` rows on the smaller files are fine; depth on the load-bearing files is the audit's value.

## Status on entry

- Branch: `main`. CA.2 has landed in 2 commits on `main`, pushed to `origin/main` 2026-05-20. The most recent commits are `[CA.2] ARCHITECTURE.md / KNOWN_ISSUES.md / ENGINEERING_PLAN.md: doc-drift corrections from ML audit` and `[CA.2] ML audit: capability registry + findings`.
- Local + remote `main` includes CA.0 + CA.1 + CA.2 + BUG-012-i1 instrumentation + Phase CS scoping.
- Working tree clean (`default.profraw` is a documented build artifact).
- BUG-012 is **Open**. BUG-012-i1 instrumentation in place. Step 2 (diagnosis) waits on a reproduction. CA.3 does not interfere — the Session-side BUG-012 surface is the `SessionPreparer+Analysis.swift:76` `separator.separate(...)` call site, which is in scope to read but not to modify.
- BUG-006 is **Open**. The audit may surface findings relevant to its diagnosis; document them, do not fix.
- No CA.3 code or audit has landed. This is the kickoff.

## Sign-off

This prompt is the canonical entry point for Increment CA.3. The Phase CA wider scoping (what subsystem comes next, the master `docs/CAPABILITY_REGISTRY.md` index file) continues to be one-increment-at-a-time per the CA.0 scoping decision.

If you find the prompt is wrong or stale during the audit, **update the prompt** before continuing — do not work against a brief you know to be incorrect.

— Matt + Claude (2026-05-20 design session, post-CA.2 closeout)
