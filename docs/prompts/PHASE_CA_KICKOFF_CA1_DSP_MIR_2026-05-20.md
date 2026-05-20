# Phase CA Kickoff — Capability Audit — Increment CA.1 (DSP / MIR)

**Hand this to a new Claude Code session verbatim. Do not summarise.**

---

## What this phase is

**Phase CA — Capability Audit** is a multi-increment archaeology of Phosphene's codebase. Each increment audits one subsystem: reads the actual source, traces consumers and producers, cross-references against `CLAUDE.md` / `docs/ENGINEERING_PLAN.md` / `docs/QUALITY/KNOWN_ISSUES.md` / `docs/DECISIONS.md`, and assigns a health verdict to every capability the subsystem exposes.

Motivation (from the 2026-05-20 design conversation): a Cold-Start design session in this same conversation proposed building "C2 + first-onset anchoring" infrastructure that turned out to **already exist in production**, built incrementally across the BUG-007.x series — and Claude had no prior knowledge of it. That session also surfaced that `docs/CAPABILITY_GAP_AUDIT.md` is referenced from `ENGINEERING_PLAN.md` but does not exist as a file. The drift between docs and code is real, not hypothetical, and has cost real session time.

Phase CA addresses this systematically. The output is `docs/CAPABILITY_REGISTRY/<subsystem>.md` per subsystem plus a top-level `docs/CAPABILITY_REGISTRY.md` index. Future sessions consult the registry before proposing infrastructure — answering "does this already exist?" before designing.

**This kickoff is for Increment CA.1: the DSP / MIR subsystem.** It is the first audit pass and validates the approach for the wider phase.

## Why DSP / MIR first

Three reasons:

1. **Highest likelihood of finding the kind of blind-spot this phase exists to surface.** The cold-start session blind spot was in DSP. The BUG-007.x series produced significant incremental infrastructure (LiveBeatDriftTracker, GridOnsetCalibrator, beat-grid extrapolation, hybrid runtime recalibration) that may not be reflected in current docs.
2. **Load-bearing for the next phase.** Phase CS (Cold-Start Sync) depends on understanding what DSP capabilities are actually in production. The audit feeds directly into CS.1's verification work.
3. **Medium-large size validates the approach without becoming its own multi-session adventure.** 20 files in `PhospheneEngine/Sources/DSP/`. Substantive but bounded.

## Read these first, before doing anything else

1. **`CLAUDE.md`** — the entire file. Note especially: Audio Data Hierarchy section, Audio Analysis Tuning pointer (links into `docs/ARCHITECTURE.md`), Key Types pointer, the Failed Approaches list (many relate to DSP), the "What NOT To Do" list.
2. **`docs/ARCHITECTURE.md`** — sections "Audio Analysis Tuning", "Key Types", "Module Map" (especially DSP entries), "ML Inference".
3. **`docs/DECISIONS.md`** — grep for D-026, D-027, D-058, D-059, D-075, D-077, D-079, BUG-007.x — these are the load-bearing DSP decisions.
4. **`docs/QUALITY/KNOWN_ISSUES.md`** — every entry tagged `dsp.beat`, `dsp.tempo`, `dsp.stem`. Both Open and Resolved (resolved entries document what infrastructure was built).
5. **`docs/diagnostics/capability-audit-pre-2026-05-12.md`** — the preliminary capability audit from May 2026 (preliminary inventory data; this audit revisits and completes that work).
6. **`docs/ENGINEERING_PLAN.md`** — search for "Phase DSP" + "DSP.x" + any BUG-007.x increment narrative.

If any of these files do not exist (a possibility — that's part of what we're auditing), record the missing reference as the **first finding** of the audit and continue with what does exist.

## Hard rules for this phase

- **No code changes during the audit.** Findings are documented; fixes are separate increments scheduled after the audit publishes. The only file modifications allowed in CA.1 are the new audit document(s) and minor corrections to `ENGINEERING_PLAN.md` / `KNOWN_ISSUES.md` / `CLAUDE.md` that the audit surfaces as drift (e.g., the missing `docs/CAPABILITY_GAP_AUDIT.md` reference can be removed or corrected; new BUG entries can be filed for "broken-but-claimed" findings).
- **Evidence-based: every claim cites a file and line.** "X exists at `path/file.swift:NNN`" or "X is referenced but file does not exist." No claims unverified by inspection of the actual source.
- **Exhaustive within scope.** Every public type, every public function, every documented capability in the DSP subsystem gets a verdict. Coverage is binary, not best-effort.
- **Stop-and-report criteria** (in addition to the standard CLAUDE.md set):
  - Found a `broken-but-claimed` finding that affects production behavior right now (file as BUG entry; surface immediately).
  - Audit scope is growing beyond DSP — capability traces lead into Audio, ML, Session, or App layers. Note the boundary crossing; continue within scope; flag for the next subsystem pass.
  - Discovered an architectural inconsistency that's too large to document inline. Surface for Matt.
  - The audit format is producing low-value output (sprawl, unactionable verdicts). Pause, redesign before continuing.
- **Closeout report cites the audit document, not the audit's findings.** The audit document IS the deliverable; the closeout points to it and summarises in one paragraph what was found.

## Scope of CA.1

### Files in scope (`PhospheneEngine/Sources/DSP/`)

```
BandEnergyProcessor.swift         — 6-band AGC + smoothing + deviation primitives
BeatDetector+Tempo.swift          — tempo estimation; computeRobustBPM
BeatDetector+TempoDiagnostics.swift — diagnostic instrumentation for tempo
BeatDetector.swift                — per-band onset detector
BeatGrid.swift                    — offline beat grid struct + extrapolation + octave correction
BeatGridResolver.swift            — produces BeatGrid from Beat This! model output
BeatPredictor.swift               — reactive-mode beat predictor (when no grid available)
BeatThisPreprocessor.swift        — Beat This! model input preparation
ChromaExtractor.swift             — 12-bin chroma derivation
DSP.swift                         — module entry point / shared types
LiveBeatDriftTracker.swift        — drift-tracking against cached BeatGrid; the BUG-007.x focal point
MIRPipeline+Recording.swift       — session recording integration
MIRPipeline.swift                 — top-level DSP coordinator
NoveltyDetector.swift             — novelty curve for structural analysis
PitchTracker.swift                — YIN-style vocal pitch tracking; subject of PT.1 fix 2026-05-19
SelfSimilarityMatrix.swift        — SSM for structural section detection
SpectralAnalyzer.swift            — spectral centroid / rolloff / flux
StemAnalyzer+RichMetadata.swift   — stem-level beat/onset analysis
StemAnalyzer.swift                — per-stem energy / spectral analysis
StructuralAnalyzer.swift          — section-boundary detection
```

### Boundary surfaces (in scope, with annotation)

- **DSP ↔ Audio** — `FFTProcessor` (Audio module) feeds DSP. Note the boundary; record what DSP consumes from Audio without auditing Audio's internals.
- **DSP ↔ ML** — `Beat This!` model output is consumed by `BeatGridResolver`; `StemAnalyzer` consumes `StemSeparator` output. Note the boundary.
- **DSP ↔ Session** — `BeatGridResolver` outputs `BeatGrid`; `Session/GridOnsetCalibrator.swift` lives in Session but is a DSP-adjacent capability — include it in the audit with a note that its file location may be wrong.
- **DSP ↔ App** — `VisualizerEngine.mirPipeline` is the app-level consumer. Note primary consumers without auditing App layer internals.

### Explicit exclusions (will be audited in later CA increments)

- Audio capture, FFT setup, AudioBuffer (Audio module pass)
- ML model implementations (Beat This! model code, MoodClassifier, StemSeparator/StemFFT internals)
- Session preparation pipeline (track caching, preview download)
- App layer (`VisualizerEngine` etc.)
- Renderer / preset shaders

If something in the boundary surfaces seems important enough that the audit's value is reduced without it, note the gap and continue. Do not expand scope.

## Methodology

### Step 1 — Inventory pass (read-only)

For each file in scope, produce:

- **File summary** — one paragraph: what this file owns, who its primary consumers are, when it was added (commit log if helpful).
- **Public surface** — every `public` type and every `public` method, with brief signatures. Include `internal` types that are consumed across module boundaries via `@testable` / package-internal access.
- **Documented features** — comment headers, MARK sections, doc-comments describing intended behavior.

Use the Explore agent for breadth (parallelize reads); synthesize per-file findings yourself. Do not paraphrase doc comments — quote them verbatim where the claim matters.

### Step 2 — Consumer trace

For each public capability inventoried in Step 1, find consumers:

- `grep -rn "TypeName" PhospheneEngine/Sources PhospheneApp` — direct references.
- For functions: `grep -rn "\.functionName(" PhospheneEngine/Sources PhospheneApp` — call sites.
- For protocols: also find conformances via `grep -rn ": ProtocolName" PhospheneEngine/Sources`.
- For types referenced only in tests: note as `test-only` (different verdict than production consumers).

Record per capability: production consumers, test consumers, no consumers. A capability with zero production consumers is a `production-orphan` candidate (subject to closer inspection — maybe consumed via reflection, dispatch tables, or KVC).

### Step 3 — Documentation cross-reference

For each capability, search the load-bearing docs for mentions:

- `CLAUDE.md` — full-text search for type name + key terms.
- `docs/ARCHITECTURE.md` — same.
- `docs/DECISIONS.md` — search by topic, not just name.
- `docs/ENGINEERING_PLAN.md` — search for increment narrative.
- `docs/QUALITY/KNOWN_ISSUES.md` — both Open and Resolved.

Record per capability:
- **Claimed in docs** (yes/no, citations)
- **Doc claim aligned with code** (yes/no, divergence noted)
- **Documented as planned-but-not-built** (yes/no — e.g., increment listed as "to do")

### Step 4 — Behavior validation (lightweight)

For capabilities with non-trivial runtime behavior (LiveBeatDriftTracker drift EMA, BandEnergyProcessor AGC, GridOnsetCalibrator computation, etc.), look for evidence that the behavior actually works:

- Is there a test that exercises the behavior end-to-end?
- Is there a SR.1-style diagnostic that measures it in real sessions?
- Has a session-log or features.csv ever shown the behavior firing?

Note: this is NOT running tests or writing new tests. It is reading evidence that exists. Capabilities with no behavior evidence are flagged as `unverified-claim` (different from `production-orphan` — they ARE consumed, but there is no evidence the consumption is producing correct output).

The PT.1 case is the canonical `unverified-claim → broken` transition: `PitchTracker.vocalsPitchConfidence` was claimed to work, was consumed by Aurora Veil's pitch route, and was 0 % across every session for five months. The 2026-05-19 fix landed a multi-frame ring-buffer correction. The audit must look for this pattern explicitly.

### Step 5 — Assign verdict

Verdicts (one per capability):

| Verdict | Meaning |
|---|---|
| `production-active` | Consumed by production code; doc claims match code behavior; behavior validated (tests / diagnostics / observed). |
| `production-orphan` | Consumed nowhere in production code (test consumers only OR no consumers). May be dead code; may be a reflection/dispatch target — verify before declaring dead. |
| `dead` | Confirmed dead — no consumers anywhere; safe to delete (but deletion is a separate increment). |
| `stub` | Exists as a type/function signature but body is empty / returns default / throws unimplemented. |
| `documented-but-missing` | Docs claim it exists; code does not have it (or has been retired). |
| `built-but-undocumented` | Code has it; no doc references it (so future sessions won't know to use it). |
| `broken-but-claimed` | Docs claim it works; runtime behavior contradicts (PT.1 pattern). File a BUG entry immediately. |
| `unverified-claim` | Consumed; docs claim correctness; no evidence of correctness. Lower priority than `broken-but-claimed` but worth flagging. |
| `boundary-deferred` | Lives at a subsystem boundary (DSP↔Audio, DSP↔ML, DSP↔Session); its full verdict requires the other subsystem's audit. Record as `boundary-deferred` and revisit in the relevant later CA increment. |

### Step 6 — Write the audit document

Output file: `docs/CAPABILITY_REGISTRY/DSP_MIR.md` (create the `CAPABILITY_REGISTRY` directory).

Structure:

```markdown
# Capability Registry — DSP / MIR

**Audit increment:** CA.1
**Date:** 2026-05-XX
**Scope:** PhospheneEngine/Sources/DSP/ (20 files) + DSP-adjacent capabilities at subsystem boundaries.
**Methodology:** Phase CA scoping document (this file).

## Summary

[One paragraph: how many capabilities, how many of each verdict, the highest-priority findings.]

## Findings by verdict

### broken-but-claimed (BUG entries filed)
[Per finding: capability name; what's claimed; what's actually happening; BUG entry reference; evidence citations.]

### documented-but-missing
[Per finding: capability name; where docs claim it exists; what's actually there.]

### unverified-claim
[Per finding: capability; consumer trace; lack-of-evidence note; suggested verification path.]

### production-orphan
[Per finding: capability; absence-of-consumers evidence; suggested next step (delete / wire up / investigate).]

### dead
[Per finding: capability; commit-log context if known; deletion increment scope.]

### stub
[Per finding: capability; comment from author if any; intended replacement / removal.]

### built-but-undocumented
[Per finding: capability; suggested doc location; one-sentence proposed entry.]

### boundary-deferred
[Per finding: capability; which other subsystem owns the verdict; what's needed to resolve.]

### production-active
[Counts only — no per-finding detail unless something is noteworthy. The default verdict.]

## Per-file capability index

[One section per file. Per capability within a file: brief signature, verdict, consumer count, doc citation, evidence summary.]

## Cross-references

### Updates needed in CLAUDE.md
[List of stale claims, undocumented capabilities to add, retired-but-referenced items.]

### Updates needed in ENGINEERING_PLAN.md
[Same shape.]

### Updates needed in DECISIONS.md
[Same shape.]

### New BUG entries
[Filed for each broken-but-claimed.]

### KNOWN_ISSUES.md sweep
[Resolved entries that haven't been retired; Open entries that no longer reproduce; entries whose code surface no longer exists.]

## Approach validation

[A few paragraphs: did the audit format produce real, actionable value? What worked? What didn't? Recommended changes for CA.2 (the next subsystem pass).]
```

### Step 7 — File the artifact + cross-references

Per CLAUDE.md increment closeout protocol:

- The audit document is the primary deliverable.
- Any `broken-but-claimed` findings get BUG-XXX entries in `KNOWN_ISSUES.md` immediately. Do not wait for a fix increment to file the bug.
- ENGINEERING_PLAN.md gets an entry in Recently Completed (`CA.1 ✅`) plus a Phase CA section if one doesn't exist.
- CLAUDE.md drift findings are corrected in this same increment (small, doc-only edits — explicitly bounded as "the audit produced doc-only corrections to align the document with the existing code").

Commit shape:

1. `[CA.1] DSP/MIR audit: capability registry + findings`
2. `[CA.1] KNOWN_ISSUES: BUG-XXX entries from DSP/MIR audit findings` (if any)
3. `[CA.1] CLAUDE.md / ENGINEERING_PLAN.md / DECISIONS.md: doc-drift corrections`

## Done-when

CA.1 closes when:

- [ ] `docs/CAPABILITY_REGISTRY/DSP_MIR.md` published.
- [ ] Every public capability in scope has a verdict.
- [ ] All `broken-but-claimed` findings have BUG entries in `KNOWN_ISSUES.md`.
- [ ] Drift corrections to load-bearing docs landed (CLAUDE.md / ENGINEERING_PLAN.md / DECISIONS.md).
- [ ] "Approach validation" section produces an honest critique of whether this format should continue into CA.2.
- [ ] All commits land on `main` (local). Not pushed.

## After CA.1 lands

Surface to Matt:

- The audit summary (broken-but-claimed count, documented-but-missing count, production-orphan count, etc.).
- The recommended approach changes for CA.2 (if any).
- The recommended next subsystem for CA.2 (audit-driven — may not be the originally-planned "Audio" if findings suggest a different priority).

Do not start CA.2 in the same session. Each audit increment is its own pass.

## Failure modes to watch for

Specifically in audit-shaped work:

- **Becoming a fix increment.** When the audit surfaces a bug, the temptation is to fix it. Don't. File the BUG entry; move on. CA.1 must remain audit-only.
- **Sprawl into adjacent subsystems.** The DSP/Audio boundary is fuzzy; the DSP/ML boundary is fuzzy. Stay in the DSP scope; flag boundary cases as `boundary-deferred`; let later CA increments resolve them.
- **Trivial-finding inflation.** Listing every `public` symbol in a verdict table is fine, but the substantive value is in the non-`production-active` verdicts. If 95 % of findings are `production-active` with no flag, the audit is producing low-value output. Re-read the brief to ensure the methodology is going deep where it matters.
- **Citing without verifying.** "CLAUDE.md says X" must come with a quoted excerpt + line citation, not a vague paraphrase. Same for code claims. The discipline rule "diagnostic infrastructure precedes fidelity claims" (CLAUDE.md, 2026-05-20) applies to audit findings: every claim is evidence-backed.
- **Producing structure as a substitute for substance.** The audit document's headers must be backed by content. An empty "broken-but-claimed" section with zero findings means there were no findings — say so explicitly; don't pretend the section is incomplete.

## Status on entry

- Branch: `main`. 6 commits ahead of `origin/main`.
- Local `main` includes the BUG-012-i1 instrumentation increment and the Phase CS scoping commit.
- Working tree clean (Aurora Veil carry-over stashed; `default.profraw` is a build artifact).
- No CA-phase code or audits have landed. This is the kickoff.

## Sign-off

This prompt is the canonical entry point for Increment CA.1. The Phase CA wider scoping (what subsystem comes next, the master `docs/CAPABILITY_REGISTRY.md` index file) is a follow-up after CA.1's approach-validation step confirms the format works.

If you find the prompt is wrong or stale during the audit, **update the prompt** before continuing — do not work against a brief you know to be incorrect.

— Matt + Claude (2026-05-20 design session)
