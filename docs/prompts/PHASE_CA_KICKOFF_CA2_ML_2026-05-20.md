# Phase CA Kickoff — Capability Audit — Increment CA.2 (ML)

**Hand this to a new Claude Code session verbatim. Do not summarise.**

---

## What this phase is

**Phase CA — Capability Audit** is a multi-increment archaeology of Phosphene's codebase. Each increment audits one subsystem: reads the actual source, traces consumers and producers, cross-references against `CLAUDE.md` / `docs/ARCHITECTURE.md` / `docs/QUALITY/KNOWN_ISSUES.md` / `docs/DECISIONS.md`, and assigns a health verdict to every capability the subsystem exposes.

CA.1 (DSP / MIR) closed 2026-05-20 at [`docs/CAPABILITY_REGISTRY/DSP_MIR.md`](../CAPABILITY_REGISTRY/DSP_MIR.md). It validated the audit format and produced real, actionable findings (one runtime `production-orphan` cluster on the audio-callback hot path; one retroactive BUG entry filed for PT.1; doc-drift corrections across ARCHITECTURE.md and ENGINEERING_PLAN.md). CA.1 also surfaced a gap in the kickoff template itself: there was no formal mechanism for tracking findings that didn't ship as part of the audit. That gap is closed in CA.2's template — see §Output structure below.

**This kickoff is for Increment CA.2: the ML subsystem.** It is the second audit pass.

## Why ML next

Three reasons (carried forward from CA.1's approach-validation recommendation):

1. **The DSP↔ML boundary closes cleanly.** CA.1 fully covered `BeatThisPreprocessor` (DSP-side input to the Beat This! model) and `BeatGridResolver` (DSP-side postprocessor of the model's output). CA.2 picks up the ML side of that pipeline (the model implementation, the MPSGraph wiring, the weights loader) without re-litigating the boundary.
2. **The test surface is already partly authored.** `Tests/ML/` has 12 test files — `BeatThisFixturePresenceGate`, `BeatThisLayerMatchTests`, `BeatThisBugRegressionTests`, `BeatThisStemReshapeTests`, `BeatThisRoPEPairingTests`, `BeatThisModelTests`, `StemSeparatorTests`, `StemModelTests`, `StemFFTTests`, `MoodClassifierTests`, `MoodClassifierGoldenTests`, plus `BUG012ConcurrencyTest`. Python-reference fixtures exist for the Beat This! pipeline. Behaviour validation in CA.2 should be substantially easier than CA.1's qualitative inference.
3. **BUG-012 is active in this subsystem.** `StemFFTEngine` MPSGraph EXC_BAD_ACCESS during sustained force-dispatch (P1, Open). BUG-012-i1 instrumentation landed 2026-05-20 (commit `94a55a29` → `a57c79fa` → `23bbb825`). Step 2 (diagnosis from instrumented reproduction) waits on the next crash. The audit can (and should) read every BUG-012-adjacent code path freely — inventory and consumer tracing don't touch behaviour. But **the audit must NOT modify any file or test that BUG-012-i1 instrumented**, because doing so would muddy whatever signal the next reproduction produces. The instrumented files are listed below under §Hard rules.

## Read these first, before doing anything else

1. **`CLAUDE.md`** — the entire file. Note especially: the ML Inference pointer, the No-CoreML decision (D-009 referenced from CLAUDE.md), the Audio Data Hierarchy section (layer 5 — Stems), the Failed Approaches relating to ML (#11 MediaRemote, #14 ANE Float16 strides, #20 CoreML ANE outputs with `bindMemory(to: Float.self)`).
2. **`docs/CAPABILITY_REGISTRY/DSP_MIR.md`** — the CA.1 audit. The DSP↔ML boundary references in CA.1's per-file index are CA.2's starting context. Particular attention: the `BeatGridResolver`, `BeatThisPreprocessor`, and `StemAnalyzer` rows — they describe what ML feeds into and what ML consumes from. Also read CA.1's §Approach validation and §Follow-up Backlog — the methodology improvements there are baked into CA.2's rules below.
3. **`docs/ARCHITECTURE.md`** — sections "ML Inference", "Dispatch Scheduling (Increment 6.3)", "Audio Analysis Hierarchy" (layer 5 — Stems), and the "ML/" module-map block. CA.1's drift-correction commit updated the DSP block but did not touch the ML block — verify the ML block against actual files as part of this audit.
4. **`docs/DECISIONS.md`** — grep for D-009 (No-CoreML), D-059 (ML Dispatch Scheduling), D-077 (Phase DSP.2 pivot to Beat This!), D-098/D-099 (DM.x engine MSL struct extension — touched ML by way of `StemFeatures`), and any decision tagged with the `dsp.stem` domain.
5. **`docs/QUALITY/KNOWN_ISSUES.md`** — every entry tagged `dsp.stem` or `dsp.mood` or referencing `StemFFTEngine` / `StemSeparator` / `MoodClassifier` / `BeatThisModel`. Both Open and Resolved. **Especially:**
   - **BUG-012** (Open, P1) — MPSGraph EXC_BAD_ACCESS in StemFFTEngine. The audit reads BUG-012's race-surface analysis section as the most current understanding of the StemSeparator+StemFFT teardown path.
   - **BUG-013** (Open) — Soundcharts time_signature absent; ML meter detection wrong on some odd-meter tracks.
   - The BUG-R001…R009 retroactive-Resolved entries that touch ML (BUG-R002 hardcoded 44100, BUG-R003 StemSampleBuffer undersized at 48 kHz, BUG-R004 Live Beat This! double-time on short window).
6. **`docs/ENGINEERING_PLAN.md`** — search for "Phase 6" / "6.1" / "6.2" / "6.3" (ML dispatch scheduling); "DSP.2" / "DSP.2 S" (the Beat This! port sessions); "BUG-010" (stem-separation audit); "DM.0…DM.3.3.1" (the Drift Motes work that exercised the StemFeatures pipeline).
7. **`docs/diagnostics/DSP.2-architecture.md` or `DSP.2-beatnet-archive.md`** — the Beat This! port's architecture audit (the predecessor BeatNet path was archived; DSP.2 shipped Beat This!). Background on why the ML model code looks the way it does.

If any of these files do not exist (still a possibility — the CA.1 audit found one such case), record the missing reference as a finding and continue with what does exist.

## Hard rules for this phase

- **No code changes during the audit.** Findings are documented; fixes are separate increments scheduled after the audit publishes. The only file modifications allowed in CA.2 are the new audit document(s) and minor corrections to load-bearing docs (`ARCHITECTURE.md` / `ENGINEERING_PLAN.md` / `KNOWN_ISSUES.md` / `CLAUDE.md`) that the audit surfaces as drift.

- **BUG-012-i1 instrumentation files are off-limits to any edit.** The instrumented files are: `PhospheneEngine/Sources/ML/StemFFT.swift`, `PhospheneEngine/Sources/ML/StemFFT+CPU.swift`, `PhospheneEngine/Sources/ML/StemFFT+GPU.swift`, `PhospheneEngine/Sources/ML/StemSeparator.swift`, `PhospheneEngine/Sources/Shared/BUG012Probe.swift`, `PhospheneApp/VisualizerEngine.swift`, `PhospheneApp/VisualizerEngine+Stems.swift`, `PhospheneEngine/Tests/PhospheneEngineTests/ML/BUG012ConcurrencyTest.swift`. **Read freely; do not modify.** If the audit surfaces drift that would require editing one of these files, file it as a follow-up (see §Output structure) instead of editing in place.

- **Evidence-based: every claim cites a file and line.** "X exists at `path/file.swift:NNN`" or "X is referenced but file does not exist." No claims unverified by inspection of the actual source.

- **`production-orphan` verdicts require a cited grep (new in CA.2, per CA.1 approach-validation recommendation).** "X has zero consumers" must be backed by the exact `grep` command run and a summary of its results. The grep should cover `PhospheneApp/`, `PhospheneEngine/Sources/`, and `PhospheneEngine/Tests/`. Production-orphan claims without a cited grep will be rejected at closeout.

- **Exhaustive within scope.** Every public type, every public method, every documented capability in the ML subsystem gets a verdict. Coverage is binary, not best-effort.

- **Stop-and-report criteria** (in addition to the standard CLAUDE.md set):
  - Found a `broken-but-claimed` finding that affects production behavior right now (file as BUG entry; surface immediately).
  - The audit's reading of an ML code path reveals a plausible BUG-012 cause. **Do not fix.** Document the finding in the audit + cross-link from BUG-012's race-surface analysis section. The next BUG-012 reproduction is the load-bearing diagnostic step, not the audit's read.
  - Audit scope is growing beyond ML — capability traces lead into Renderer (MLDispatchScheduler, FrameBudgetManager), Session (BeatGridAnalyzer composes ML), App (VisualizerEngine+Stems / +Audio / +Capture mood-injection path). Note the boundary crossing; continue within scope; flag as `boundary-deferred` to a later CA increment.
  - Discovered an architectural inconsistency that's too large to document inline. Surface for Matt.
  - The audit format is producing low-value output. Pause, redesign before continuing.

- **Closeout report cites the audit document, not the audit's findings.** The audit document IS the deliverable.

## Scope of CA.2

### Files in scope (`PhospheneEngine/Sources/ML/`)

16 Swift files, ~4,557 LoC total. Grouped by capability family:

**Beat This! model (offline beat / downbeat transformer; D-077):**
```
BeatThisModel.swift                  — 258 lines — Top-level model wrapper + public API.
BeatThisModel+Frontend.swift         — 647 lines — Audio-frontend graph construction (input projection, positional embedding, frontend transformer blocks).
BeatThisModel+Graph.swift            — 444 lines — MPSGraph construction for the partial-temporal transformer backbone (RoPE attention, FFN).
BeatThisModel+Ops.swift              — 119 lines — Custom MPSGraph operation helpers (RoPE pairing, layernorm shapes).
BeatThisModel+Weights.swift          — 280 lines — Weight loading from vendored MIT-licensed checkpoint.
```

**Stem separator (Open-Unmix HQ port; D-009):**
```
StemSeparator.swift                  — 399 lines — Top-level stem-separation API (STFT → model → iSTFT pipeline) + StemSeparating protocol.
StemSeparator+Reconstruct.swift      — 70 lines  — Magnitude+phase reconstruction helpers.
StemModel.swift                      — 246 lines — Open-Unmix HQ model wrapper.
StemModel+Graph.swift                — 317 lines — MPSGraph construction for the four-stem model (BLSTM + dense layers).
StemModel+Weights.swift              — 296 lines — Weight loading from vendored Open-Unmix HQ checkpoint.
StemFFT.swift                        — 386 lines — STFT/iSTFT engine entry points + NSLock-guarded dispatch (BUG-012 surface).
StemFFT+CPU.swift                    — 157 lines — CPU (vDSP) STFT path.
StemFFT+GPU.swift                    — 353 lines — MPSGraph STFT path (the BUG-012 crash site at `runForwardGraph`).
```

**Mood classifier (DEAM-trained MLP; D-009):**
```
MoodClassifier.swift                 — 150 lines — Top-level inference wrapper (10-input MLP via vDSP_mmul).
MoodClassifier+Weights.swift         — 381 lines — Hardcoded 3,346 Float32 params from DEAM training.
```

**Module marker:**
```
ML.swift                             — 4 lines   — Module entry point.
```

### Boundary surfaces (in scope, with annotation)

- **ML ↔ DSP** — partially closed by CA.1. `BeatThisPreprocessor` (DSP-side, audited in CA.1) produces the log-mel spectrogram that `BeatThisModel.run(...)` consumes. `BeatGridResolver` (DSP-side, audited in CA.1) consumes the model's per-frame probability output. `StemAnalyzer` (DSP-side) consumes the four-stem waveforms `StemSeparator.separate(...)` produces. Verify the ML side of all three integrations.
- **ML ↔ Session** — `BeatGridAnalyzer` (Session module, `boundary-deferred` in CA.1) composes `BeatThisPreprocessor` + `BeatThisModel` + `BeatGridResolver`. **Do not re-audit `BeatGridAnalyzer` itself in CA.2** — that's still deferred to the Session subsystem audit. But: verify what `BeatThisModel`'s public API exposes is what `BeatGridAnalyzer` actually consumes, so the Session audit has clean inputs.
- **ML ↔ Renderer** — `MLDispatchScheduler` (Renderer module) gates `StemSeparator.separate` dispatch on `FrameBudgetManager.recentMaxFrameMs` (D-059). The scheduler lives in Renderer; the dispatch decisions affect ML behaviour. Note the boundary; record what ML consumes from / cooperates with the scheduler without auditing Renderer's internals.
- **ML ↔ App** — `VisualizerEngine+Stems.swift` orchestrates stem-separation dispatch on `stemQueue`; `VisualizerEngine+Audio.swift` pushes mood classifier output via `RenderPipeline.setMood`. Note the app-side consumption shape without auditing App layer internals.

### Explicit exclusions (will be audited in later CA increments)

- `PhospheneEngine/Sources/ML/Weights/` directory (176 entries — vendored model weights). These are data files, not code; the weight-loading *code* is in scope but the weight files themselves are not.
- `BeatGridAnalyzer.swift` and `GridOnsetCalibrator.swift` (Session module — deferred to CA-Session per CA.1 §Follow-up Backlog FU-5).
- `MLDispatchScheduler.swift` (Renderer module — defer to a future Renderer audit).
- `VisualizerEngine+Stems.swift` / `VisualizerEngine+Audio.swift` (App layer — defer to a future App audit).

If something in the boundary surfaces seems important enough that the audit's value is reduced without it, note the gap and continue. Do not expand scope.

## Methodology

The methodology has been refined post-CA.1. Two changes from CA.1's kickoff:

**(1)** Pass 2 (doc-drift triangulation) is now explicit, not implicit. Time-budget for it accordingly.
**(2)** `production-orphan` verdicts require a cited grep. Document the grep used.

### Pass 1 — Inventory + verdict assignment

For each file in scope, produce:

- **File summary** — one paragraph: what this file owns, who its primary consumers are, when it was added (commit log if helpful).
- **Public surface** — every `public` type and every `public` (or `package`) method, with brief signatures. Include `internal` types that are consumed across module boundaries.
- **Documented features** — comment headers, MARK sections, doc-comments describing intended behavior. Quote doc comments verbatim where the claim matters.
- **Notable internal types** if load-bearing (e.g. `StemFFTEngine`'s `MPSGraph` and command-queue holders).
- **File-level constants / tuning values** with names and values.
- **Any code-level TODOs / FIXMEs / placeholder branches**.

Use the Explore agent for breadth (parallelise reads); synthesise per-file findings yourself.

Then for each capability, trace consumers via grep:

- `grep -rn "TypeName" PhospheneEngine/Sources PhospheneApp` — direct references.
- For functions: `grep -rn "\.functionName(" …` — call sites.
- For protocols: also find conformances via `grep -rn ": ProtocolName" …`.
- For types referenced only in tests: note as `test-only` (different verdict than production consumers).

Record per capability: production consumers, test consumers, no consumers. **For any `production-orphan` candidate, the cited grep command + result count is mandatory.**

Cross-reference each capability against the load-bearing docs (`CLAUDE.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `ENGINEERING_PLAN.md`, `KNOWN_ISSUES.md` — both Open and Resolved). Record: **claimed in docs** (yes/no, citations), **doc claim aligned with code** (yes/no, divergence noted), **documented as planned-but-not-built** (yes/no).

Behaviour validation: read evidence that exists. Is there a test? A diagnostic? A session-log narrative? **Especially for ML, golden-test status is load-bearing** — `BeatThisLayerMatchTests` and `MoodClassifierGoldenTests` are the discriminators. If a model file has no golden test, that itself is a finding (the BeatNet → Beat This! pivot was triggered by paraphrased-from-prose spec drift in exactly this category — see D-077 spec-drift discipline).

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
| `boundary-deferred` | Lives at a subsystem boundary; full verdict requires the other subsystem's audit. |

### Pass 2 — Doc-drift triangulation

Once verdicts are assigned, scan the load-bearing docs for *additional* drift that the per-capability cross-referencing didn't catch:

- Does `ARCHITECTURE.md`'s `ML/` module-map block list every file? (CA.1 found `DSP/` was missing 6 of 20.)
- Are tuning constants quoted in docs identical to the code's values? (CA.1 found `ChromaExtractor` 65 Hz vs 500 Hz.)
- Does any architectural claim describe a code path that no longer exists? Was retired? Was renamed?
- Do any decisions in `DECISIONS.md` reference symbols that have moved or been renamed?

Record drift findings as a separate cross-reference section in the audit doc. Pass 2 typically takes 25-40% of Pass 1's effort; budget accordingly.

## Output structure (template — updated post-CA.1)

Output file: `docs/CAPABILITY_REGISTRY/ML.md`.

```markdown
# Capability Registry — ML

**Audit increment:** CA.2
**Date:** 2026-05-XX
**Auditor:** Claude (session-driven, read-only)
**Scope:** PhospheneEngine/Sources/ML/ (16 files, ~4.5k LoC) + boundary annotations.
**Methodology:** Phase CA scoping document (CA.2 kickoff).
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
[Per finding: capability; **cited grep command + result summary** (mandatory per CA.2 rules); suggested next step.]

### dead, stub, built-but-undocumented, boundary-deferred
[As CA.1 template.]

### production-active
[Counts only — no per-finding detail unless something is noteworthy. The default verdict.]

## Per-file capability index

[One section per file. Per capability within a file: brief signature, verdict, consumer count, doc citation, evidence summary.]

[**Consolidation allowed (new in CA.2):** if the verdict distribution is heavily concentrated in `production-active` — e.g., > 80 % of file-level entities — the Findings-by-verdict and Per-file-index sections may be merged into a single annotated index, with non-`production-active` rows visually marked. Use discretion. Keep them split when at least one non-`production-active` bucket has ≥ 3 findings.]

## Cross-references

### Updates needed in CLAUDE.md
### Updates needed in ARCHITECTURE.md
### Updates needed in ENGINEERING_PLAN.md
### Updates needed in DECISIONS.md
### New BUG entries
### KNOWN_ISSUES.md sweep

[Each section as CA.1 template. Empty sections may be deleted — say so explicitly rather than leave headers with no content. ("No drift found in DECISIONS.md" is sufficient as a one-line note.)]

## Follow-up Backlog

[**MANDATORY in CA.2 onwards** — this is the gap CA.1 surfaced. Every finding that is not corrected in this audit increment is registered here as a candidate follow-up increment.]

| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA.2-FU-1** | [one-line scope, enough to act on cold] | [verifiable done-when] | [1, 1-2, <1] | [Ready now / Blocked on X] |
| **CA.2-FU-2** | … | … | … | … |

[After the table: a one-paragraph **Bundling recommendation** + a one-line **Priority order if Matt picks just one this week** suggestion.]

[The Follow-up Backlog and the Findings-by-verdict sections should correlate: every non-`production-active` finding either ships a doc-fix in this increment OR registers as a CA.2-FU-N entry. Findings without a follow-up are stating "this is fine as-is and requires no action" — say so explicitly.]

## Approach validation

[A few paragraphs: what worked in CA.2's methodology? What didn't? Recommended changes for CA.3.]
```

## File the artifact + cross-references

Per CLAUDE.md increment closeout protocol:

- The audit document is the primary deliverable.
- Any `broken-but-claimed` findings get BUG-XXX entries in `KNOWN_ISSUES.md` immediately.
- ENGINEERING_PLAN.md gets an entry in Recently Completed (`CA.2 ✅`) plus the CA.2 row in the Phase CA section flipped from "Pending" to "✅ Landed".
- CLAUDE.md / ARCHITECTURE.md drift findings are corrected in this same increment.

Commit shape:

1. `[CA.2] ML audit: capability registry + findings`
2. `[CA.2] KNOWN_ISSUES: BUG-XXX entries from ML audit findings` (if any)
3. `[CA.2] ARCHITECTURE.md / ENGINEERING_PLAN.md / DECISIONS.md / CLAUDE.md: doc-drift corrections`

## Done-when

CA.2 closes when:

- [ ] `docs/CAPABILITY_REGISTRY/ML.md` published.
- [ ] Every public capability in scope has a verdict.
- [ ] Every `production-orphan` verdict cites the grep command used.
- [ ] Every non-`production-active` finding either ships a doc-fix in this increment OR is registered as a `CA.2-FU-N` follow-up.
- [ ] All `broken-but-claimed` findings have BUG entries in `KNOWN_ISSUES.md`.
- [ ] Drift corrections to load-bearing docs landed.
- [ ] "Approach validation" section produces an honest critique of whether this format should continue into CA.3.
- [ ] All commits land on `main` (local). Not pushed.
- [ ] No edits to BUG-012-i1 instrumented files.

## After CA.2 lands

Surface to Matt:

- The audit summary (broken-but-claimed count, documented-but-missing count, production-orphan count, follow-up count).
- The recommended approach changes for CA.3 (if any).
- The recommended next subsystem for CA.3 — audit-driven, may not be the originally-planned "Session" if findings suggest a different priority.
- Any BUG-012-adjacent findings that the next reproduction's diagnosis should weigh.

Do not start CA.3 in the same session.

## Failure modes to watch for

Specifically for ML-shaped audit work:

- **Reading the model implementation as "verifying it's correct"**. It's not. CA.2 audits whether the code exists, whether it's consumed, whether docs match. A line-by-line read of `BeatThisModel+Graph.swift`'s RoPE math is out of scope — golden tests are the discriminator for ML correctness, not your read.
- **Touching BUG-012 surfaces.** The instrumentation is in place and waiting for a reproduction. Modifying *any* instrumented file (the list is in §Hard rules) burns the in-flight diagnostic. Read freely, but if drift surfaces on those files, file as a follow-up and move on.
- **Vendored-weights rabbit hole.** Weights/ has 176 entries. They are data, not code. The audit reads the *loading code*, not the weights. If the loading code is right, the weights are right (or the BeatNet→Beat This! pivot would have happened differently).
- **Scope creep into Renderer / Session / App.** MLDispatchScheduler is in Renderer. BeatGridAnalyzer is in Session. VisualizerEngine+Stems is in App. None are in scope. Note their consumption of ML; do not audit them.
- **Sprawl into per-layer mathematical correctness.** RoPE pairing, layernorm shapes, BLSTM gating — these are correctness questions, not capability-audit questions. If they were wrong, the golden tests would fail. The audit's job is to verify the golden tests exist and are wired into CI, not to re-derive the math.
- **Trivial-finding inflation.** 16 files; most are likely `production-active`. If 95%+ are `production-active` with no nuance, the audit may be skating along the surface — re-read the brief and ensure the methodology is going deep on the non-trivial cases (the StemFFT dispatch path is the obvious depth target given BUG-012).
- **Citing without verifying.** Same as CA.1's rule. Every claim is evidence-backed with a file:line or a doc:line.
- **Producing structure as a substitute for substance.** Headers must be backed by content. Empty buckets should be said-empty, not pretended-incomplete.

## Status on entry

- Branch: `main`. CA.1 has landed in 4 commits on `main`, not pushed. The most recent commit is `[CA.1] Capability Registry: add Follow-up Backlog section`.
- Local `main` includes CA.0 + CA.1 + BUG-012-i1 instrumentation + Phase CS scoping.
- Working tree clean (`default.profraw` is a documented build artifact).
- BUG-012 is **Open**. BUG-012-i1 instrumentation is in place. Step 2 (diagnosis) waits on a reproduction. The audit does not interfere with this.
- No CA.2 code or audit has landed. This is the kickoff.

## Sign-off

This prompt is the canonical entry point for Increment CA.2. The Phase CA wider scoping (what subsystem comes next, the master `docs/CAPABILITY_REGISTRY.md` index file) continues to be one-increment-at-a-time per the CA.0 scoping decision.

If you find the prompt is wrong or stale during the audit, **update the prompt** before continuing — do not work against a brief you know to be incorrect.

— Matt + Claude (2026-05-20 design session, post-CA.1 closeout)
