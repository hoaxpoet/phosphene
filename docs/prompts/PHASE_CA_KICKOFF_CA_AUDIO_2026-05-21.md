# Phase CA Kickoff — Capability Audit — Increment CA-Audio (Audio module)

Hand this to a new Claude Code session verbatim. Do not summarise.

## What this phase is

Phase CA — Capability Audit is a multi-increment archaeology of Phosphene's codebase. Each increment audits one subsystem: reads the actual source, traces consumers and producers, cross-references against `CLAUDE.md` / `docs/ARCHITECTURE.md` / `docs/QUALITY/KNOWN_ISSUES.md` / `docs/DECISIONS.md`, and assigns a health verdict to every capability the subsystem exposes.

Prior increments (all closed; deliverables live in `docs/CAPABILITY_REGISTRY/`):

- **CA.1** (DSP / MIR) closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/DSP_MIR.md`. 22 files. Surfaced one runtime production-orphan cluster (later superseded by BUG-015 fix).
- **CA.2** (ML) closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/ML.md`. 16 files / 4,507 LoC. Methodology refinement: pre-grep visibility verification.
- **CA.3** (Session) closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/SESSION.md`. 22 files / ~3,425 LoC. Methodology refinement: cross-check kickoff prompt against `KNOWN_ISSUES.md` as Pass 0. **Surfaced the Session ↔ Audio boundary-noted item that CA-Audio resolves** (`MetadataPreFetcher` consumed by Session at `SessionPreparer.swift:86, 132, 299`; producer side is `Sources/Audio/MetadataPreFetcher.swift`).
- **CA.4** (Orchestrator) closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md`. 14 files / ~2,950 LoC. Surfaced load-bearing broken-but-claimed BUG-015 — `applyLiveUpdate(...)` had zero production call sites; the entire Phase 4.5/4.6 live-adaptation pipeline was dead in production. BUG-015 fixed 2026-05-21.
- **CA.5** (App-layer engine-adapter slice) closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/APP.md`. 49 files / 7,975 LoC.
- **CA.6** (App-layer Views + ViewModels presentation slice) closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/APP_VIEWS.md`. 59 files / 8,285 LoC.
- **CA.7a** (Renderer — core pipeline) closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/RENDERER.md`. 23 files / 5,413 LoC. Two follow-ups resolved same-day: CA.7-FU-3 (keep ICB) + CA.7-FU-4 (retire `setRayMarchPresetComputeDispatch`).
- **CA.7b** (Renderer — supporting modules) closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/RENDERER_SUPPORTING.md`. 15 files / 2,241 LoC. RayTracing cluster filed as production-orphan + boundary-noted; CA.7b-FU-3 resolved 2026-05-21 (keep — Matt product call: *"it will be used eventually by presets we haven't created yet"*).

The App layer + DSP / ML / Session / Orchestrator + Renderer are now fully closed. **Audio is the last remaining unaudited engine module that has a clean producer boundary** (presets per-preset state classes under `Sources/Presets/` is the only other unaudited surface; that's CA-Presets, later).

This kickoff is for Increment **CA-Audio**: the Audio module under `PhospheneEngine/Sources/Audio/`.

## Why CA-Audio next

Four reasons, in priority order:

1. **CA.3 boundary-noted item closes here.** CA.3's audit of `SessionPreparer` noted that `MetadataPreFetcher` is consumed by Session at `SessionPreparer.swift:86, 132, 299` but lives in the Audio module (`Sources/Audio/MetadataPreFetcher.swift`). The Session ↔ Audio boundary is one of the load-bearing system seams (every prepared track flows through this surface) and the CA-Audio audit closes it with full producer-side context. **Same shape as CA.3 closed the CA.1/CA.2 Session-boundary deferrals.**
2. **CA.5 / CA.6 / CA.7a / CA.7b cite Audio types as consumers without auditing the producer.** `VisualizerEngine` per CA.5 owns `AudioInputRouter` + `MetadataPreFetcher`; the CA.7a / CA.7b dispatch path consumes tap-sample-rate via `AudioInputRouter`'s installation. CA-Audio is the unique producer-side audit for the entire audio capture + metadata pipeline.
3. **Load-bearing sample-rate plumbing (D-079 / QR.1, Failed Approach #29 + #52, BUG-R002 / BUG-R003) lives here.** The literal `44100` ban + immutable-tap-capture invariant + `Scripts/check_sample_rate_literals.sh` CI gate are all Audio-module rules. The audit verifies the production code matches the spec — if a regression is anywhere, it's the kind of regression CA-Audio is uniquely positioned to find.
4. **Metadata fetcher cluster (`MetadataPreFetcher` / `MusicBrainzFetcher` / `SpotifyFetcher` / `SoundchartsFetcher` / `MusicKitBridge` / `StreamingMetadata`) hosts multiple known bugs and Failed Approaches.** BUG-005 (Spotify `preview_url` returns null for some tracks — Open), BUG-013 (Soundcharts no `time_signature` — Open), Failed Approaches #45 / #46 / #47 (Spotify API quirks; promoted to RUNBOOK §Spotify connector setup per DOC.3 doc-refactor). The audit's job is to verify the producer-side error handling and fallback paths match the documented behaviour.

## Read these first, before doing anything else

- **`CLAUDE.md` — the entire file.** Especially: §What NOT To Do (sample-rate rules from D-079 + Failed Approach #29 + #52); Failed Approach #21 (`CATapDescription(stereoMixdownOfProcesses: [])` = silence — use `stereoGlobalTapButExcludeProcesses: []`); Failed Approach #22 (screen capture permission required — `CGRequestScreenCaptureAccess()` before tap creation); Failed Approach #29 (hardcoded 44100 sample rate); Failed Approach #45 / #46 / #47 (Spotify API quirks — promoted to RUNBOOK); Failed Approach #52 (44100 literal in code paths that should consume tap rate — D-079 fix); §Code Style §URLProtocol stub tests `@Suite(.serialized)` (the U.10 learning fired in Audio-adjacent tests).
- **`docs/CAPABILITY_REGISTRY/SESSION.md` — CA.3 audit.** Read especially:
  - §Cross-references "Session ↔ Audio" — the boundary-noted item this audit closes.
  - The `MetadataPreFetcher.swift` consumer line cites (`SessionPreparer.swift:86, 132, 299`).
- **`docs/CAPABILITY_REGISTRY/APP.md` — CA.5 audit.** Read especially:
  - The `VisualizerEngine+Audio.swift` analysis — App-side consumer of `AudioInputRouter` per-frame `processAnalysisFrame` callbacks + BUG-015 wire `runOrchestratorLiveUpdate(mir:)` cadence gate.
  - `CaptureModeReconciler.swift` — Routes `SettingsStore.captureMode` changes to `AudioInputRouter.switchMode(_:)` per D-052 live-switch path.
  - `MetadataPreFetcher` ownership-on-VisualizerEngine notes.
- **`docs/CAPABILITY_REGISTRY/RENDERER.md` — CA.7a audit.** Read especially:
  - §Verification of Failed Approach #66 test/prod parity — the render-path Audio-rate consumers (relevant for tap-sample-rate-derived constants flowing into renderer).
- **`docs/QUALITY/KNOWN_ISSUES.md` — every Open entry.** Especially:
  - **BUG-005** (Open; Spotify `preview_url` returns null — Audio-module-internal; SpotifyFetcher producer-side).
  - **BUG-013** (Open; Soundcharts no `time_signature` — Audio-module-internal; SoundchartsFetcher producer-side).
  - **BUG-012** (Open; MPSGraph EXC_BAD_ACCESS in StemFFTEngine — ML-side instrumentation; Audio module not affected, BUG-012-i1 instrumentation files NOT in CA-Audio scope).
  - **BUG-R002 / BUG-R003** (Resolved; load-bearing context for sample-rate plumbing audit — D-079 / QR.1).
  - **Pre-existing Flakes section** — `MetadataPreFetcher.fetch_networkTimeout` is the load-bearing one for CA-Audio (per memory baseline `project_test_baseline.md`); document its scope but don't try to fix.
- **`docs/ARCHITECTURE.md`** — sections §Audio Capture (lines 38-72), §Module Map Audio/ block (lines 480-495). The Module Map currently lists 13 of 16 files (missing entries: `Audio.swift` module marker, `AudioInputRouter+SignalState.swift` extension, plus one more — verify during audit).
- **`docs/DECISIONS.md`** — grep for **D-052** (capture-mode live switch), **D-070** (preview-URL primary path — Spotify inline + iTunes Search fallback), **D-079** (sample-rate plumbing audit / QR.1), **D-052** + related (capture-mode reconciler), **D-018** (graceful degradation on metadata-fetcher failure).
- **`docs/ENGINEERING_PLAN.md`** — search for **D-079**, **QR.1**, **U.6** (capture-mode settings UI), **CS.x** (Cold-Start Sync — Audio-adjacent), and the Recently Completed entries that touched Audio (any in the last 30 days).
- **`docs/RUNBOOK.md`** — §Spotify connector setup carries Failed Approaches #45 / #46 / #47 (promoted from CLAUDE.md per DOC.3 doc-refactor). Read for the Spotify-API quirk handling expectations.

If any of these files do not exist, record the missing reference as a finding and continue with what does exist.

## Hard rules for this phase

- **No code changes during the audit.** Findings are documented; fixes are separate increments scheduled after the audit publishes. The only file modifications allowed in CA-Audio are the new audit document and minor corrections to load-bearing docs (`ARCHITECTURE.md` / `ENGINEERING_PLAN.md` / `KNOWN_ISSUES.md` / `CLAUDE.md`) that the audit surfaces as drift.
- **BUG-012-i1 instrumentation files remain read-only.** None are in CA-Audio scope by current accounting (all are in `Sources/Shared/` + `Sources/ML/` + `Sources/Renderer/` + `PhospheneApp/`), but verify before editing.
- **Evidence-based:** every claim cites a file and line. `X exists at path/file.swift:NNN` or `X is referenced but file does not exist`. No claims unverified by inspection of the actual source.
- **`production-orphan` verdicts require a cited grep** (carried forward from CA.2). `X has zero consumers` must be backed by the exact grep command run and a summary of its results. The grep should cover `PhospheneApp/`, `PhospheneEngine/Sources/`, `PhospheneEngine/Tests/`, and `PhospheneAppTests/`. Production-orphan claims without a cited grep will be rejected at closeout.
- **Pre-grep visibility verification** (carried forward from CA.3 + CA.5 + CA.6 + CA.7a + CA.7b). When parallelising file reads via Explore agents, do not trust an agent's "this type is public" / "this method is internal" reports without cross-checking. After receiving each agent's report, run a single visibility grep per file and reconcile each agent-claimed public against the grep.
- **Non-nil-caller production-orphan check (CA.7b refinement).** For any setter / mutator API, grep for non-nil callers, not just `setX\(` callers. A setter with only nil-reset callers is a production-orphan API surface even if it appears `production-active` at the file level. CA.7b discovered the `setMeshPresetBuffer` zero-non-nil-caller finding this way. Apply the same lens to Audio-module setter / mutator APIs.
- **Cross-check the kickoff prompt against `KNOWN_ISSUES.md` as Pass 0** (carried forward). Verify every BUG cited in this kickoff against actual status:
  - BUG-005 — should still be Open (Spotify `preview_url`).
  - BUG-013 — should still be Open (Soundcharts `time_signature`).
  - BUG-012 — should still be Open (instrumentation in place; CA-Audio does not touch instrumented files).
  - BUG-R002 — should be Resolved.
  - BUG-R003 — should be Resolved.
  - BUG-001 / BUG-011 / BUG-015 / BUG-016 — out of CA-Audio scope; verify status only.
  - If any kickoff claim disagrees with `KNOWN_ISSUES.md`, the audit's first finding is the kickoff staleness.
- **Sub-scope decision NOT mandatory at this size.** 16 files / 3,294 LoC sits between CA.7b (15 files / 2,241 LoC, single pass) and CA.7a (23 files / 5,413 LoC, deliberately split). Default: single increment. State the choice explicitly in the audit doc's §Scope section before Pass 1 begins. If the audit's depth requires a split (e.g. capture pipeline vs. metadata-fetcher cluster), state it.
- **Exhaustive within scope.** Every public / internal type, every public / internal method in the chosen scope gets a verdict. Coverage is binary for the scope you commit to, not best-effort.
- **Stop-and-report criteria** (in addition to the standard CLAUDE.md set):
  - Found a `broken-but-claimed` finding that affects production behaviour right now (file as `BUG-XXX` entry; surface immediately — BUG-015 in CA.4 is the load-bearing precedent).
  - The audit's reading of `SystemAudioCapture` or `AudioInputRouter` reveals a sample-rate plumbing regression (D-079 / Failed Approach #52) — drop everything and surface to Matt before continuing.
  - The audit's reading of `AudioInputRouter` reveals the tap recovery state machine (3 s → 10 s → 30 s backoff, three attempts per ARCH §68) drifts from the spec.
  - The audit's reading of `SilenceDetector` reveals the state machine timings (.active → .suspect 1.5s → .silent 3s → .recovering → .active 0.5s hold per ARCH §487) drift from the spec.
  - The audit's reading of `InputLevelMonitor` reveals the 21s peak-dBFS window or 30-frame hysteresis (per ARCH §488) drifts from the spec.
  - The audit reveals a flake-class regression beyond the documented `MetadataPreFetcher.fetch_networkTimeout` pre-existing flake.
  - The audit format is producing low-value output. Pause, redesign before continuing.

## Scope of CA-Audio

### Files in scope (16 files, 3,294 LoC)

`PhospheneEngine/Sources/Audio/`:

**Module marker (1 file, 11 LoC):**
- `Audio.swift` (11) — Module-marker file. May contain top-level imports / module-level documentation only.

**Audio capture pipeline (6 files, 1,514 LoC):**
- `SystemAudioCapture.swift` (322) — Core Audio tap: system-wide or per-app. `AudioHardwareCreateProcessTap` (macOS 14.2+). The producer of raw audio frames. Failed Approach #21 (CATapDescription must use `stereoGlobalTapButExcludeProcesses: []`) + Failed Approach #22 (screen capture permission required) live here.
- `AudioInputRouter.swift` (313) — Unified source: `.systemAudio` / `.application(bundleIdentifier:)` / `.localFile` → callbacks + dual analysis/render frames. **The load-bearing sample-rate-capture site** (D-079 / QR.1 — `tapSampleRate` immutably captured on `installTap(...)`). Tap recovery state machine (3 s → 10 s → 30 s backoff, three attempts) per ARCH §68. D-052 live-switch path consumer.
- `AudioInputRouter+SignalState.swift` (112) — Extension carrying the signal-state machine (`.silent` → `.suspect` → `.active` transitions). Wire to `SilenceDetector` outputs.
- `AudioBuffer.swift` (187) — IO proc → `UMARingBuffer<Float>` bridge for GPU. Receives PCM samples from the Core Audio IO proc; must not allocate per CLAUDE.md §What NOT To Do ("Do not allocate in the Core Audio IO proc callback").
- `LookaheadBuffer.swift` (168) — Timestamped ring buffer with dual read heads (analysis + render), configurable 2.5s delay. Decouples the analysis path (immediate) from the render path (lookahead-delayed for ML inference latency hiding).
- `FFTProcessor.swift` (249) — vDSP 1024-pt FFT → 512 magnitude bins in `UMABuffer`. The FFT producer. Consumed by `MIRPipeline` and the per-band energy chain. Hop = 256 samples (75 % overlap per D-???; verify).

**Signal-quality monitors (2 files, 538 LoC):**
- `SilenceDetector.swift` (216) — DRM silence state machine: .active → .suspect (1.5s) → .silent (3s) → .recovering → .active (0.5s hold). Producer of the `.silent` signal that triggers `AudioInputRouter`'s tap reinstall sequence.
- `InputLevelMonitor.swift` (322) — Continuous tap-quality assessment: rolling peak dBFS (21s window) + 3-band spectral EMAs → `SignalQuality` (green/yellow/red) with reason string. Peak-only classification after session 2026-04-17T21-05-47Z. 30-frame hysteresis. Logs to `session.log` on transitions via `VisualizerEngine+Audio`.

**Metadata fetcher cluster (6 files, 943 LoC):**
- `MetadataPreFetcher.swift` (212) — Parallel async queries, LRU cache, merge partial results, 3s per-fetcher timeouts. **CA.3 boundary-noted item — Session-side consumer at `SessionPreparer.swift:86, 132, 299` is the load-bearing call site.** Producer side: this file.
- `MusicBrainzFetcher.swift` (119) — Free API, genre tags + duration.
- `SpotifyFetcher.swift` (180) — Client credentials, search-only track matching. **BUG-005 surface** (preview_url null for some tracks).
- `SoundchartsFetcher.swift` (193) — Optional commercial API (`SOUNDCHARTS_APP_ID` + `SOUNDCHARTS_API_KEY` env vars). **BUG-013 surface** (no `time_signature` field).
- `MusicKitBridge.swift` (149) — Optional MusicKit catalog enrichment, graceful no-op.
- `StreamingMetadata.swift` (269) — AppleScript polling of Apple Music / Spotify, track change detection.

**Protocols (1 file, 272 LoC):**
- `Protocols.swift` (272) — `AudioCapturing`, `AudioBuffering`, `FFTProcessing`, `MoodClassifying` (re-exported from ML), `MetadataProviding`, `MetadataFetching`. The protocol-first DI surface for the entire Audio module.

### Boundary surfaces (in scope, with annotation)

- **Audio ↔ Session.** `MetadataPreFetcher` is the load-bearing producer (CA.3 boundary-noted item). Verify the `MetadataPreFetcher.fetch(...)` signature matches the Session consumer's call sites (`SessionPreparer.swift:86, 132, 299`). Note any divergence as a finding.
- **Audio ↔ App.** `AudioInputRouter` is consumed by `VisualizerEngine` (CA.5-audited consumer). The tap-sample-rate plumbing (D-079 / QR.1) flows from `AudioInputRouter.installTap(...)` immutable capture through `VisualizerEngine` storage (`tapSampleRateLock`-guarded per CLAUDE.md) into the downstream chain. Verify the producer side matches the CA.5-audited consumer expectations.
- **Audio ↔ DSP.** `FFTProcessor` is consumed by `MIRPipeline` (CA.1-audited) via the `FFTProcessing` protocol from `Protocols.swift`. Verify the protocol surface matches the CA.1 consumer expectations.
- **Audio ↔ ML.** `MoodClassifying` protocol is re-exported from `Audio/Protocols.swift` (the type is declared in `Sources/ML/`). Verify the re-export contract matches the ML producer.
- **Audio ↔ DSP / ML (StemSeparating, StemAnalyzing).** Per CA.3's note at `SESSION.md §Cross-references`, `StemSeparating` + `StemAnalyzing` protocols are declared in `Audio/Protocols.swift`. Verify the conformers (in `Sources/ML/`) match the declarations.

### Explicit exclusions (out of CA-Audio scope)

- `PhospheneEngine/Sources/DSP/` — CA.1 (closed).
- `PhospheneEngine/Sources/ML/` — CA.2 (closed). BUG-012-i1 instrumented files (8 total across `Sources/Shared/`, `Sources/ML/`, `Sources/Renderer/`, `PhospheneApp/`) remain read-only.
- `PhospheneEngine/Sources/Session/` — CA.3 (closed).
- `PhospheneEngine/Sources/Orchestrator/` — CA.4 (closed).
- `PhospheneEngine/Sources/Renderer/` — CA.7a + CA.7b (closed).
- `PhospheneEngine/Sources/Shared/` — deferred (CA-Shared eventually).
- `PhospheneEngine/Sources/Presets/` per-preset state classes — CA-Presets (later).
- `PhospheneApp/` — CA.5 + CA.6 (closed). The CA.5 audit of `VisualizerEngine+Audio.swift` (App-side consumer of Audio module callbacks) and `CaptureModeReconciler.swift` (App-side consumer of `AudioInputRouter.switchMode(_:)`) is the boundary; this audit reads them as consumer-side references but does not re-audit them.
- `PhospheneEngine/Tests/` — read freely for test discriminators, but audit verdicts apply to production code, not tests.

If something in the boundary surfaces seems important enough that the audit's value is reduced without it, note the gap and continue. Do not expand scope.

## Methodology

The methodology is the same as CA.1–CA.7b with no new additions — the format is stable.

### Pass 0 — Kickoff cross-check

Before reading any source file:

1. **BUG cross-check.** Verify every BUG cited in this kickoff against `docs/QUALITY/KNOWN_ISSUES.md` (BUG-005, BUG-013, BUG-012, BUG-R002, BUG-R003). If any kickoff claim disagrees, file the disagreement as Finding #1.
2. **Verify CA.3 boundary-noted MetadataPreFetcher item is still valid.** Read `docs/CAPABILITY_REGISTRY/SESSION.md` §Cross-references "Session ↔ Audio" — confirm `MetadataPreFetcher` is still the load-bearing producer and the citation `SessionPreparer.swift:86, 132, 299` still resolves to the current code.
3. **Verify pre-existing follow-ups.** CA.7-FU-1 + CA.7-FU-2 + CA.7b-FU-4 stay open (outside CA-Audio scope; do not address). CA.7-FU-3 + CA.7-FU-4 + CA.7b-FU-3 closed; nothing to carry forward. If anything regressed, surface it.
4. **State whether CA-Audio is single-pass or splits.** Default: single increment at 3.3k LoC.

### Pass 1 — Inventory + verdict assignment

For each file in scope, produce:

- **File summary** — one paragraph: what this file owns; the kind of work it does.
- **Public / internal surface** — every public / internal type and every public / internal method, with brief signatures.
- **Documented features** — comment headers, MARK sections, doc-comments. Quote verbatim where the claim matters.
- **Notable internal types / private members** if load-bearing (e.g., `@Published` properties, NSLock-guarded state, dispatch-queue ownership, callback closures into the IO proc).
- **File-level constants / tuning values** with names and values.
- **Any code-level TODOs / FIXMEs / placeholder branches.**

**Read strategy:** At ~3,294 LoC for CA-Audio, direct-read every file > 200 lines (8 files: AudioInputRouter 313, InputLevelMonitor 322, SystemAudioCapture 322, Protocols 272, StreamingMetadata 269, FFTProcessor 249, SilenceDetector 216, MetadataPreFetcher 212) and batch the rest across 1-2 parallel Explore agents.

After each agent's report, run the visibility verification grep per file. Reconcile each agent-claimed public against the grep.

Then for each capability, trace consumers via grep:

```bash
grep -rn "TypeName" PhospheneApp PhospheneAppTests PhospheneEngine/Sources PhospheneEngine/Tests   # type usage
grep -rn "\.functionName(" …                                                                       # call sites
grep -rn ": ProtocolName" …                                                                        # conformances
```

For types referenced only in tests: note as test-only (different verdict than production).

Record per capability: production consumers, test consumers, no consumers. For any production-orphan candidate, the cited grep command + result count is mandatory. **Apply the CA.7b non-nil-caller refinement to setter / mutator APIs** — a setter with only nil-reset callers is a production-orphan API surface.

Cross-reference each capability against the load-bearing docs. Record: claimed in docs (yes/no, citations), doc claim aligned with code (yes/no, divergence noted), documented as planned-but-not-built (yes/no).

**Behaviour validation — key test discriminators by domain:**

- **Audio capture:** `AudioInputRouterTests` (signal-state machine + tap-recovery backoff); `SystemAudioCaptureTests` (if present — verify); `AudioBufferTests` (UMA ring buffer producer/consumer invariants).
- **Signal-quality monitors:** `SilenceDetectorTests` (state machine timings); `InputLevelMonitorTests` (peak-dBFS window + hysteresis).
- **FFT:** `FFTProcessorTests` (1024-pt vDSP correctness + UMABuffer bridge).
- **Metadata cluster:** `MetadataPreFetcherTests` (LRU cache + parallel-async + 3s timeouts; **note the pre-existing flake `MetadataPreFetcher.fetch_networkTimeout`**); `StreamingMetadataTests` (AppleScript polling); per-fetcher tests for `MusicBrainzFetcher` / `SpotifyFetcher` / `SoundchartsFetcher` / `MusicKitBridge` if present (note absence as a gap).
- **LookaheadBuffer:** `LookaheadBufferTests` (dual-read-head timing + UMA correctness).

Use them as the discriminators they are.

**Assign verdict per capability** (definitions carried forward from CA.7b):

| Verdict | Meaning |
|---|---|
| `production-active` | Consumed by production code; doc claims match code behavior; behavior validated. |
| `production-orphan` | Consumed nowhere in production code (test consumers only OR no consumers). Requires cited grep. Also applies to setter APIs with only nil-reset callers (CA.7b refinement). |
| `dead` | Confirmed dead — no consumers anywhere; safe to delete. |
| `stub` | Exists as signature; body empty / default / unimplemented. |
| `documented-but-missing` | Docs claim it exists; code does not. |
| `built-but-undocumented` | Code has it; no doc references it. |
| `broken-but-claimed` | Docs claim it works; runtime behavior contradicts. File a `BUG-XXX` entry immediately. |
| `unverified-claim` | Consumed; docs claim correctness; no evidence of correctness. |
| `boundary-noted` | Lives at a subsystem boundary; verdict is complete (no future re-audit obligation). |
| `boundary-deferred` | Lives at a subsystem boundary; full verdict requires the other subsystem's audit. |

### Pass 2 — Doc-drift triangulation

Once verdicts are assigned, scan load-bearing docs for additional drift:

- Does `ARCHITECTURE.md` §Audio Capture (lines 38-72) accurately describe the current capture-mode set, tap-recovery state machine, and sample-rate plumbing?
- Does `ARCHITECTURE.md` §Module Map Audio/ block (lines 480-495) include all 16 files? (Currently 13 listed; 3 missing: `Audio.swift` module marker + `AudioInputRouter+SignalState.swift` extension + one more.)
- Are tuning constants quoted in docs identical to the code's values? (SilenceDetector 1.5s / 3s / 0.5s; InputLevelMonitor 21s peak window + 30-frame hysteresis; tap recovery 3s / 10s / 30s backoff; MetadataPreFetcher 3s per-fetcher timeout; LookaheadBuffer 2.5s default delay.)
- Does any architectural claim describe a path that no longer exists? Was retired? Was renamed?
- Do any decisions in `DECISIONS.md` reference type names that have moved or been renamed?
- Does `CLAUDE.md` §What NOT To Do (sample-rate rules, Failed Approach #21 / #22 / #29 / #52) still match the current Audio-module code?
- Does `Scripts/check_sample_rate_literals.sh` allowlist match the current `44100` allowlist sites? (The script gates Failed Approach #52 in CI; CA-Audio should verify the allowlist is current.)

Record drift findings as a separate cross-reference section in the audit doc.

## Output structure (template — extends CA.7b)

Output file: `docs/CAPABILITY_REGISTRY/AUDIO.md`.

```markdown
# Capability Registry — Audio Subsystem

**Audit increment:** CA-Audio
**Date:** 2026-05-XX
**Auditor:** Claude (session-driven, read-only)
**Scope:** `PhospheneEngine/Sources/Audio/` — 16 files / 3,294 LoC.
**Methodology:** Phase CA scoping document (CA-Audio kickoff).
**Reads relied on:** [list]
**Sibling audits:** docs/CAPABILITY_REGISTRY/SESSION.md (CA.3 — Session ↔ Audio boundary), docs/CAPABILITY_REGISTRY/APP.md (CA.5 — App-layer Audio consumers), docs/CAPABILITY_REGISTRY/DSP_MIR.md (CA.1 — FFTProcessing protocol consumer), docs/CAPABILITY_REGISTRY/ML.md (CA.2 — protocol re-export consumers).

## Summary

[One paragraph: capability counts per verdict, top findings, follow-up count, kickoff-vs-KNOWN_ISSUES cross-check result.]

[Markdown table of verdict counts.]

## Sub-scope decision

[State the scope chosen at Pass 0 explicitly. Justify the choice. At 3.3k LoC the default is single-pass; commit to it or explain why a split is needed.]

## Findings by verdict

[Per-finding citations as CA.5 / CA.6 / CA.7a / CA.7b template.]

## Per-file capability index

[One section per file or per cluster. Consolidation allowed if verdicts heavily concentrate in production-active.]

## Verification of CA.3 Session ↔ Audio boundary closure (CA-Audio-specific)

[Required section. Verify the `MetadataPreFetcher` producer-side matches the Session consumer expectations at `SessionPreparer.swift:86, 132, 299`. Verify `TrackMetadata` lives in Audio (per CA.3 note); verify `PreviewAudio` lives in Session (per CA.3 correction). Boundary-noted closure per CA-Audio.]

## Verification of D-079 sample-rate plumbing (CA-Audio-specific)

[Required section. Verify `AudioInputRouter.installTap(...)` captures `tapSampleRate` immutably (Failed Approach #29 + #52 + D-079). Verify no `44100` literal exists in CA-Audio-scope production code outside the documented allowlist (`Scripts/check_sample_rate_literals.sh`). Cite the literal-grep command + result. Verify `tapSampleRateLock` (per CLAUDE.md §What NOT To Do) is honoured at the producer side.]

## Verification of tap recovery state machine (CA-Audio-specific)

[Required section. Verify `AudioInputRouter`'s tap-recovery sequence matches ARCH §68: persistent `.silent` triggers reinstall on backoff (3s → 10s → 30s, three attempts); each attempt destroys + recreates the tap; resumption cancels the sequence; three exhausted attempts stop reinstall until next active → silent transition. Cite line numbers.]

## Verification of SilenceDetector + InputLevelMonitor state machines (CA-Audio-specific)

[Required section. Verify SilenceDetector .active → .suspect (1.5s) → .silent (3s) → .recovering → .active (0.5s hold) per ARCH §487. Verify InputLevelMonitor 21s peak-dBFS window + 30-frame hysteresis + peak-only post-2026-04-17T21-05-47Z classification per ARCH §488. Cite line numbers for each timing constant.]

## Verification of Failed Approach #21 / #22 (CA-Audio-specific)

[Required section. Verify `SystemAudioCapture` constructs `CATapDescription` with `stereoGlobalTapButExcludeProcesses: []` (NOT `stereoMixdownOfProcesses: []`). Verify `CGRequestScreenCaptureAccess()` is invoked before tap creation (Failed Approach #22 — without permission the tap delivers silent zeros). Cite line numbers for both.]

## Verification of metadata-fetcher BUG surfaces (CA-Audio-specific)

[Required section. BUG-005 (Spotify preview_url null) — verify SpotifyFetcher's handling of null preview_url; reproduce or describe the gap. BUG-013 (Soundcharts no time_signature) — verify SoundchartsFetcher's parsing falls through gracefully. Failed Approaches #45 / #46 / #47 (Spotify API quirks promoted to RUNBOOK) — verify the production code matches the RUNBOOK's documented handling. Document any divergence.]

## Cross-references

### Updates needed in CLAUDE.md
### Updates needed in ARCHITECTURE.md
### Updates needed in ENGINEERING_PLAN.md
### Updates needed in DECISIONS.md
### Updates needed in RUNBOOK.md
### New BUG entries
### KNOWN_ISSUES.md sweep

## Follow-up Backlog

| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA-Audio-FU-1** | … | … | … | … |
| **CA-Audio-FU-2** | … | … | … | … |

## Approach validation

[Critique of methodology. What worked? What didn't? Recommended changes for CA-Presets / CA-Shared.]
```

## File the artifact + cross-references

Per CLAUDE.md increment closeout protocol:

- The audit document is the primary deliverable.
- Any `broken-but-claimed` findings get `BUG-XXX` entries in `KNOWN_ISSUES.md` immediately. The next available BUG number is **BUG-017** (no new BUG entries filed since BUG-016 on 2026-05-21, including across CA.7a / CA.7-FU / CA.7b which produced zero new BUG entries).
- `ENGINEERING_PLAN.md` gets an entry in Recently Completed (CA-Audio ✅) plus the CA-Audio row added (no row exists yet — write one).
- `CLAUDE.md` / `ARCHITECTURE.md` / `RUNBOOK.md` drift findings are corrected in this same increment.

Commit shape (matches CA.1 / CA.2 / CA.3 / CA.4 / CA.5 / CA.6 / CA.7a / CA.7b — two commits, doc-only):

```
[CA-Audio] Audio capability audit: registry + findings
[CA-Audio] ARCHITECTURE.md / ENGINEERING_PLAN.md / CLAUDE.md / RUNBOOK.md: doc-drift corrections from Audio audit (if any)
```

## Done-when

CA-Audio closes when:

- [ ] `docs/CAPABILITY_REGISTRY/AUDIO.md` published.
- [ ] Sub-scope decision documented explicitly (default: single increment).
- [ ] Every public / internal capability in the chosen scope has a verdict.
- [ ] Every `production-orphan` verdict cites the grep command used.
- [ ] Every Explore-agent-claimed public / internal symbol was cross-checked against a visibility grep.
- [ ] Non-nil-caller production-orphan check (CA.7b refinement) applied to every setter / mutator API in scope.
- [ ] Kickoff-vs-`KNOWN_ISSUES.md` cross-check ran as Pass 0 step 1.
- [ ] Every non-`production-active` finding either ships a doc-fix in this increment OR is registered as a `CA-Audio-FU-N` follow-up.
- [ ] All `broken-but-claimed` findings have BUG entries in `KNOWN_ISSUES.md`.
- [ ] CA.3 Session ↔ Audio boundary-noted item closed (MetadataPreFetcher producer-side traced).
- [ ] D-079 sample-rate plumbing verification produced a cited literal-grep + immutable-capture confirmation.
- [ ] Tap recovery state machine verification matches ARCH §68 spec.
- [ ] SilenceDetector + InputLevelMonitor state machine timings match ARCH §487-488.
- [ ] Failed Approach #21 + #22 verified at the `SystemAudioCapture` source.
- [ ] BUG-005 + BUG-013 producer-side handling characterised.
- [ ] Drift corrections to load-bearing docs landed.
- [ ] "Approach validation" section produces an honest critique of whether this format should continue into CA-Presets / CA-Shared.
- [ ] All commits land on `main` (local). Push only on Matt's explicit approval.

## After CA-Audio lands

Surface to Matt:

- The audit summary (broken-but-claimed count, documented-but-missing count, production-orphan count, follow-up count).
- The verdict on CA.3 Session ↔ Audio boundary closure (clean against `SessionPreparer.swift:86, 132, 299` consumer chain, or drift found).
- The verdict on D-079 sample-rate plumbing (clean against `Scripts/check_sample_rate_literals.sh` allowlist, or drift found).
- The verdict on tap recovery state machine (clean against ARCH §68, or drift found).
- The verdict on SilenceDetector + InputLevelMonitor timings (clean against ARCH §487-488, or drift found).
- The verdict on Failed Approach #21 + #22 (clean at `SystemAudioCapture` source, or drift found).
- The verdict on BUG-005 + BUG-013 (producer-side handling described; if regression-class observation surfaces, file as `BUG-017+`).
- Any new `CA-Audio-FU` items registered.
- The recommended next subsystem — **CA-Presets** (per-preset state classes under `Sources/Presets/` — last remaining unaudited engine module) OR **CA-Shared** (`Sources/Shared/` deferred indefinitely; smallest natural next pass after CA-Presets).

**Do not start CA-Presets or CA-Shared in the same session.**

## Failure modes to watch for

Specifically for Audio-shaped audit work:

- **Treating SystemAudioCapture as a black box.** The Core Audio tap setup is the most platform-coupled code in the engine. Failed Approaches #21 + #22 fired here; if a regression is anywhere in CA-Audio scope, it's at the tap-construction site. Read the file directly; do not let an Explore agent abstract the `CATapDescription` constructor call away.
- **Misreading the tap recovery backoff as "always three attempts."** The spec (ARCH §68) says three attempts THEN reinstall stops until next `active → silent` transition. Verify the resumption logic carefully — a "stuck in silence" bug would manifest as `AudioInputRouter` permanently silent after three attempts even if the source resumes.
- **Sample-rate plumbing depth.** D-079 / Failed Approach #52 is one of the project's most-cited Failed Approaches. The literal `44100` allowlist (`StemSeparator.modelSampleRate`, `BeatThisPreprocessor.sourceSampleRate`, test fixtures) is enforced in CI via `Scripts/check_sample_rate_literals.sh`. If CA-Audio finds a `44100` literal in a non-allowlisted code path, that's a real regression — drop everything and surface to Matt.
- **Metadata fetcher cluster trivial-finding inflation.** Most of the per-fetcher code is async/await + URLSession + JSONDecoder. Don't enumerate every JSON field as a finding; focus the depth on the BUG-005 / BUG-013 surfaces and the LRU cache eviction logic in `MetadataPreFetcher`.
- **Citing without verifying.** Same as CA.1–CA.7b's rule. Every claim is evidence-backed with a `file:line` or a `doc:line`.
- **Producing structure as a substitute for substance.** Headers must be backed by content. Empty buckets should be said-empty, not pretended-incomplete.
- **Scope creep into CA.5 / CA.7a territory.** `VisualizerEngine+Audio.swift` (App-side consumer of Audio callbacks) is CA.5-audited; `CaptureModeReconciler.swift` is CA.5-audited; `MIRPipeline` (DSP-side consumer of FFTProcessor) is CA.1-audited. Read them as consumer references; do not re-audit.

## Status on entry

**Branch:** `main`. CA.0 + CA.1 + CA.2 + CA.3 + CA.4 + CA.5 + CA.6 + CA.7a + CA.7b + their follow-ups (CA.7-FU-3 keep + CA.7-FU-4 retire + CA.7b-FU-3 keep) all landed on `main` as of 2026-05-21. Recent commits (most-recent first, post-CA.7b-FU-3 resolution):

```
<CA-Audio kickoff commit (this doc)>
<CA.7b-FU-3 keep — resolution commit>
56da19cd  [CA.7b] ARCHITECTURE.md + ENGINEERING_PLAN.md: doc-drift corrections from supporting-modules audit
19022515  [CA.7b] Renderer supporting audit: capability registry + findings
5851f3f4  [CA.7b] Scoping: kickoff doc for Renderer supporting-modules capability audit
d48a6778  [CA.7-FU-3 + CA.7-FU-4] RENDERER.md + ENGINEERING_PLAN.md: mark FU-3 (keep ICB) + FU-4 (retired) Resolved
8ac45e73  [CA.7-FU-4] Renderer: retire setRayMarchPresetComputeDispatch
c62584ec  [CA.7a] ARCHITECTURE.md + ENGINEERING_PLAN.md: doc-drift corrections from Renderer audit
b9612d22  [CA.7a] Renderer audit: capability registry + findings
…
```

**Local + remote:** local main matches origin/main as of CA.7b push 2026-05-21. Working tree clean apart from the documented `default.profraw` build artifact.

**SwiftLint baseline:** 0 violations across 371 files. Any violation in active source paths is a regression per `project_swiftlint_baseline.md` memory note. CA-Audio should remain at 0.

**Test counts:** Engine 1,248 tests / 162 suites all passing as of CA.7-FU-4 close. App 328 tests / 60 suites all passing.

**Pre-existing flakes** continue per the `[dev-2026-05-21-c/d/e]` chip baselines:
- **Engine-side:** `MetadataPreFetcher.fetch_networkTimeout` (env-dependent — load-bearing for CA-Audio; document its scope but don't try to fix; CA-Audio-internal flake), `SoakTestHarness.cancel`, `MemoryReporter.residentBytes` (env-dependent, `isIntermittent: true`).
- **App-side:** timing margins widened per U.10 / U.11.
- None except the MetadataPreFetcher flake are Audio-internal; CA-Audio should not encounter the others.

**Open follow-ups carried in (out of CA-Audio scope; do not address):**

- **CA.7-FU-1** — Tighten `AuroraVeilMVWarpAccumulationTest` to call `RenderPipeline.drawWithMVWarp(...)` directly. Marginal; low-priority.
- **CA.7-FU-2** — Remove dead `RayMarchPipeline.depthDebugEnabled` / `runDepthDebugPass` / `depthDebugPipeline` cluster. Mechanical cleanup; small.
- **CA.7b-FU-4** — `setMeshPresetBuffer` / `setMeshPresetFragmentBuffer` zero-non-nil-caller cleanup (latent slot-1 collision). Low-priority; CA.7a-scope.

**BUG-012 is Open.** BUG-012-i1 instrumentation in place across 8 files; none in CA-Audio scope.

**BUG-011 is Closed against drops-only criteria.** Not Audio-affecting.

**BUG-016 is Open.** Lumen Mosaic symptom uncharacterised; not Audio-affecting.

**BUG-005 is Open.** Spotify `preview_url` returns null for some tracks — **Audio-module-internal**; SpotifyFetcher producer-side. CA-Audio surfaces the handling characterisation.

**BUG-013 is Open.** Soundcharts no `time_signature` — **Audio-module-internal**; SoundchartsFetcher producer-side. CA-Audio surfaces the handling characterisation.

**BUG-001 is Open.** DSP defect; not Audio-affecting.

**No CA-Audio code or audit has landed.** This is the kickoff.

## Sign-off

This prompt is the canonical entry point for Increment CA-Audio. The Phase CA wider scoping (what subsystem comes next after CA-Audio — likely CA-Presets per the CA.7b closeout recommendation, or CA-Shared if the Presets cluster is too large for the next session window) continues to be one-increment-at-a-time per the CA.0 scoping decision.

If you find the prompt is wrong or stale during the audit, update the prompt before continuing — do not work against a brief you know to be incorrect.

— Matt + Claude (2026-05-21 design session, post-CA.7b closeout + CA.7b-FU-3 keep resolution)
