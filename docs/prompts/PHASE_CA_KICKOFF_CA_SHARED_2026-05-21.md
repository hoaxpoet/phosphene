# Phase CA Kickoff — Capability Audit — Increment CA-Shared (Shared module — Swift)

Hand this to a new Claude Code session verbatim. Do not summarise.

## What this phase is

Phase CA — Capability Audit is a multi-increment archaeology of Phosphene's codebase. Each increment audits one subsystem: reads the actual source, traces consumers and producers, cross-references against CLAUDE.md / docs/ARCHITECTURE.md / docs/QUALITY/KNOWN_ISSUES.md / docs/DECISIONS.md, and assigns a health verdict to every capability the subsystem exposes.

Prior increments (all closed; deliverables live in `docs/CAPABILITY_REGISTRY/`):

- **CA.1 (DSP / MIR)** closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/DSP_MIR.md`. 22 files. Surfaced one runtime production-orphan cluster (later superseded by BUG-015 fix).
- **CA.2 (ML)** closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/ML.md`. 16 files / 4,507 LoC. Methodology refinement: pre-grep visibility verification.
- **CA.3 (Session)** closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/SESSION.md`. 22 files / ~3,425 LoC. Methodology refinement: cross-check kickoff prompt against KNOWN_ISSUES.md as Pass 0. Surfaced the Session ↔ Audio boundary-noted item that CA-Audio resolved.
- **CA.4 (Orchestrator)** closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md`. 14 files / ~2,950 LoC. Surfaced load-bearing broken-but-claimed BUG-015 — `applyLiveUpdate(...)` had zero production call sites; the entire Phase 4.5/4.6 live-adaptation pipeline was dead in production. BUG-015 fixed 2026-05-21.
- **CA.5 (App-layer engine-adapter slice)** closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/APP.md`. 49 files / 7,975 LoC.
- **CA.6 (App-layer Views + ViewModels presentation slice)** closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/APP_VIEWS.md`. 59 files / 8,285 LoC.
- **CA.7a (Renderer — core pipeline)** closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/RENDERER.md`. 23 files / 5,413 LoC. Two follow-ups resolved same-day: CA.7-FU-3 (keep ICB) + CA.7-FU-4 (retire `setRayMarchPresetComputeDispatch`).
- **CA.7b (Renderer — supporting modules)** closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/RENDERER_SUPPORTING.md`. 15 files / 2,241 LoC. RayTracing cluster filed as production-orphan + boundary-noted; CA.7b-FU-3 resolved 2026-05-21 (keep — Matt product call).
- **CA-Audio (Audio module)** closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/AUDIO.md`. 16 files / 3,294 LoC. Three follow-ups resolved same-day: CA-Audio-FU-2 (keep `LookaheadBuffer`) + CA-Audio-FU-3 (keep `MusicKitFetcher`) + CA-Audio-FU-9 (file Module Map Sync as a separate planned increment). CA-Audio-FU-1 resolved in-audit (kickoff staleness on BUG-005 attribution corrected).
- **CA-Presets (Presets module — Swift slice)** closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/PRESETS.md`. 30 Swift files / 9,175 LoC (kickoff said 3,129 — counted only the infrastructure cluster) + 16 JSON sidecars. All seven required invariants verified clean (D-094 / D-095 / BUG-011 round 8 / D-097 / D-099 / D-102 / FidelityRubric). BUG-016 producer-side characterised; filed as addendum (`LumenPatternEngine.init?` returns nil silently on `device.makeBuffer` failure; logging upgrade filed as CA-Presets-FU-4). LumenPatternState stride drift 376 → 568 fixed in ARCH. Five follow-ups filed (FU-1 through FU-5).

The DSP / ML / Session / Orchestrator / App / Renderer / Audio / Presets modules are now fully closed. **`Sources/Shared/` is the last remaining unaudited engine surface.** The `.metal` shader slice (`Sources/Presets/Shaders/`) was deliberately deferred from CA-Presets per its sub-scope decision; that audit remains future work, methodology-distinct from this Shared sweep.

This kickoff is for **Increment CA-Shared**: the cross-cutting Swift types under `PhospheneEngine/Sources/Shared/` that flow through every other module's audit findings — `FeatureVector`, `StemFeatures`, `SceneUniforms`, `AnalyzedFrame`, `TrackMetadata`, `BeatSyncSnapshot`, `SessionRecorder`, `UMABuffer`, `UserFacingError`, `Logging`, `DeviceTier`, `Smoother`, `RenderPass`, `SpectralHistoryBuffer`, `StemSampleBuffer`, `DashboardTokens`, `BUG012Probe`.

## Why CA-Shared next

Four reasons, in priority order:

1. **Last unaudited engine surface.** Presets closed yesterday; the only remaining unaudited `Sources/` tree is `Shared/`. Closing it means Phase CA has covered every Swift surface in the engine module. The only future audit is `Sources/Presets/Shaders/*.metal` (deferred, methodology-distinct).

2. **Cross-cuts every other audit's findings.** Every sibling audit (DSP/ML/Session/Orchestrator/App/Renderer/Audio/Presets) traces consumers and producers that flow through Shared. The `FeatureVector` (192-byte GPU contract per D-099 / DM.2) + `StemFeatures` (256-byte GPU contract) types are the load-bearing producer/consumer hinge between the DSP / ML / Audio pipeline producers and the Renderer / Presets shader consumers. CA-Presets's "D-099 / DM.2 Common.metal struct extension byte-identity" verification asserted these types stay byte-identical with the MSL declarations in `PresetLoader+Preamble.swift`; **CA-Shared is the producer-side authority on those struct layouts**. `TrackMetadata` + `PreFetchedTrackProfile` + `MetadataSource` live here per the CA-Audio correction to CA.3's `SESSION.md` line 145.

3. **BUG-012 instrumentation lives here.** `BUG012Probe.swift` (320 LoC) is the BUG-012-i1 instrumentation harness. Per the standing "BUG-012-i1 instrumentation files remain read-only" rule, the audit reads but does not modify. The audit should verify the instrumentation is wired correctly and document the production-orphan / production-active status of its surface.

4. **SessionRecorder cluster touches every diagnostic artifact.** `SessionRecorder.swift` + four extension files (`+CSV` / `+RawTap` / `+Stems` / `+Video`) own the per-session `features.csv` / `stems.csv` / `session.log` / `video.mp4` / `raw_tap.wav` writers. CA.3 audited the Session-side consumer chain; CA.5 audited the App-side construction + lifecycle. CA-Shared is the producer-side audit — it verifies the writers' invariants (atomic write semantics, lock-guarded mutation, CSV header rows, video AVAssetWriter drawable-size lock per Failed Approach #28).

## Read these first, before doing anything else

- **CLAUDE.md** — the entire file. Especially:
  - §Key Types (Shared Module) — the pointer to ARCH; CA-Shared is the implementation side.
  - §GPU Contract — texture / buffer binding layout; CA-Shared owns the Swift-side struct layouts that match.
  - §Audio Data Hierarchy — `FeatureVector` field semantics (continuous energy bands, spectrum, spectral features, onset pulses).
  - §Audio Analysis Tuning — calibrated values that flow through `FeatureVector` and `StemFeatures`.
  - §Code Style — `@frozen`, `Sendable`, NSLock semantics; CA-Shared types embody these rules.
  - Failed Approaches #21 / #22 / #28 / #29 / #44 / #52 / D-099 / DM.2.
- **`docs/CAPABILITY_REGISTRY/PRESETS.md`** — most-recent CA closeout. Read especially:
  - §Verification of D-099 / DM.2 Common.metal struct extension invariant — Swift-side `FeatureVector` (48 floats / 192 bytes) + `StemFeatures` (64 floats / 256 bytes) byte-identical to the MSL preamble. CA-Shared verifies the producer side.
  - §Per-file capability index → infrastructure cluster `PresetLoader+Preamble.swift` block (the MSL struct declarations).
- **`docs/CAPABILITY_REGISTRY/AUDIO.md`** — read especially:
  - §Verification of CA.3 Session ↔ Audio boundary closure → carry-forward correction: `TrackMetadata`, `PreFetchedTrackProfile`, `MetadataSource` live in `PhospheneEngine/Sources/Shared/AudioFeatures+Metadata.swift` (lines 30, 69, 10). CA-Shared is the producer-side audit for these.
  - §Verification of D-079 sample-rate plumbing — the `(rate: Float)` callback semantics flowing through `AnalyzedFrame` (if any).
- **`docs/CAPABILITY_REGISTRY/RENDERER_SUPPORTING.md`** (CA.7b) — read especially:
  - §Dashboard section — CA.7b Dashboard producer-side surfaces. CA-Shared owns `DashboardTokens` (the Dashboard subdir under Shared). Cross-check whether `DashboardTokens` belongs in Shared (cross-module type) or should move to Renderer (single-consumer type).
- **`docs/CAPABILITY_REGISTRY/RENDERER.md`** (CA.7a) — read especially:
  - §Verification of GPU contract slot bindings — the Swift-side struct types CA-Shared owns must match the slot layouts CA.7a verified.
- **`docs/CAPABILITY_REGISTRY/APP.md`** (CA.5) — read especially:
  - SessionRecorder construction + lifecycle on the App side. CA-Shared audits the type/method surface; CA.5 audited the construction.
  - UserFacingError consumer chain in the App layer.
- **`docs/CAPABILITY_REGISTRY/APP_VIEWS.md`** (CA.6) — read especially:
  - UserFacingError + UserFacingError+Presentation consumer surfaces in the view layer.
  - Dashboard card builders consuming `DashboardTokens`.
- **`docs/QUALITY/KNOWN_ISSUES.md`** — every Open entry. Especially:
  - **BUG-012** (Open; MPSGraph EXC_BAD_ACCESS in StemFFTEngine during sustained force-dispatch) — `BUG012Probe.swift` is the instrumentation surface, IN scope for CA-Shared **read-only**. Per the standing rule: instrumentation files remain read-only.
  - **BUG-016** (Open; Lumen Mosaic "not working") — out of CA-Shared scope per the CA-Presets addendum.
  - Other Opens (BUG-001 / BUG-005 / BUG-013) — out of CA-Shared scope.
- **`docs/ARCHITECTURE.md`** — sections to read:
  - §Module Map Shared/ block (verify all 25 Swift files are listed; expect drift per the 6-in-a-row pattern).
  - §Key Types (Shared Module) — the Swift struct contracts.
  - §GPU Contract Details — slot bindings + buffer layouts; CA-Shared owns the Swift side.
- **`docs/DECISIONS.md`** — grep for D-018 (per-track preparation lifecycle), D-019 (warmup blend), D-026 (deviation primitives), D-027 (mv_warp pass), D-028 (MV-3 beat phase + StemFeatures rich metadata), D-070 (preview-URL primary), D-079 (sample-rate plumbing), D-091 (PlaybackChromeViewModel index binding), D-099 (DM.2 Common.metal extension byte-layout invariant), D-102 (Drift Motes retirement), D-126 (V.9 Session 4.5c drums_energy_dev_smoothed addition), D-127 (Ferrofluid aurora sky function).
- **`docs/ENGINEERING_PLAN.md`** — search for "Shared" + "AudioFeatures" + "SessionRecorder" + "FeatureVector" in Recently Completed for the last 60 days.
- **`docs/RUNBOOK.md`** — §Logging + §Session recording; UserFacingError surface.
- **`docs/UX_SPEC.md`** — §8 error taxonomy → `UserFacingError` is the canonical type. CA-Shared verifies the producer side matches the UX_SPEC §8 contract.

If any of these files do not exist, record the missing reference as a finding and continue with what does exist.

## Hard rules for this phase

- **No code changes during the audit.** Findings are documented; fixes are separate increments scheduled after the audit publishes. The only file modifications allowed in CA-Shared are the new audit document and minor corrections to load-bearing docs (ARCHITECTURE.md / ENGINEERING_PLAN.md / KNOWN_ISSUES.md / CLAUDE.md / UX_SPEC.md) that the audit surfaces as drift.
- **BUG-012-i1 instrumentation files remain read-only.** `BUG012Probe.swift` is in scope for capability-registry reads but never edited.
- **GPU-contract struct layouts must NOT be modified.** `FeatureVector` + `StemFeatures` carry the D-099 / DM.2 byte-identity invariant. Any change risks silent GPU-side regressions invisible to the test suite. CA-Shared reads only; struct-extension changes are filed as follow-ups.
- **Evidence-based:** every claim cites a file and line. `X exists at path/file.swift:NNN` or `X is referenced but file does not exist`. No claims unverified by inspection of the actual source.
- **production-orphan verdicts require a cited grep** (carried forward from CA.2). `X has zero consumers` must be backed by the exact grep command run and a summary of its results. The grep should cover `PhospheneApp/`, `PhospheneEngine/Sources/`, `PhospheneEngine/Tests/`, and `PhospheneAppTests/`. Production-orphan claims without a cited grep will be rejected at closeout.
- **Pre-grep visibility verification** (carried forward from CA.3 + CA.5 + CA.6 + CA.7a + CA.7b + CA-Audio + CA-Presets). When parallelising file reads via Explore agents, do not trust an agent's "this type is public" / "this method is internal" reports without cross-checking. After receiving each agent's report, run a single visibility grep per file and reconcile each agent-claimed public against the grep.
- **Non-nil-caller production-orphan check** (CA.7b refinement, confirmed-useful by CA-Audio + CA-Presets). For any setter / mutator API, grep for non-nil callers, not just `setX\(` callers. A setter with only nil-reset callers is a production-orphan API surface even if it appears production-active at the file level.
- **Cross-check the kickoff prompt against KNOWN_ISSUES.md as Pass 0** (carried forward). Verify every BUG cited in this kickoff against actual status:
  - **BUG-012** — should still be Open (instrumentation in place; CA-Shared does not touch instrumented files).
  - **BUG-001 / BUG-005 / BUG-013 / BUG-016** — should still be Open (none Shared-affecting except for `UserFacingError`-mediated reporting paths).
  - **BUG-011 / BUG-015 / BUG-R002 / BUG-R003** — should be Resolved.
  - If any kickoff claim disagrees with KNOWN_ISSUES.md, the audit's first finding is the kickoff staleness.
- **No sub-scope decision needed.** The Shared module is ~3,515 LoC across ~25 files — comparable to CA-Audio (16 files / 3,294 LoC) and well below CA.7a (23 files / 5,413 LoC). Single-pass audit. State the choice explicitly in Pass 0 nonetheless, for closeout-template uniformity.
- **Exhaustive within scope.** Every public / internal type, every public / internal method in scope gets a verdict. Coverage is binary for the scope you commit to, not best-effort.
- **Stop-and-report criteria** (in addition to the standard CLAUDE.md set):
  - Found a `broken-but-claimed` finding that affects production behaviour right now (file as BUG-XXX entry; surface immediately — BUG-015 in CA.4 is the load-bearing precedent).
  - The audit's reading of `FeatureVector` or `StemFeatures` reveals a byte-layout regression breaking the D-099 / DM.2 invariant — drop everything and surface to Matt.
  - The audit's reading of `SessionRecorder` reveals a regression of the AVAssetWriter drawable-size-lock invariant (Failed Approach #28).
  - The audit's reading of `UserFacingError` reveals an error case missing from `UX_SPEC.md §8` (or a UX_SPEC case missing from the type — bidirectional check).
  - The audit's reading of `BUG012Probe.swift` reveals a candidate diagnostic explanation for the BUG-012 EXC_BAD_ACCESS — file as addendum to KNOWN_ISSUES.md BUG-012.
  - The audit format is producing low-value output. Pause, redesign before continuing.

## Scope of CA-Shared

### Files in scope — Swift only (25 files, ~3,515 LoC)

`PhospheneEngine/Sources/Shared/`:

**GPU-contract value types (8 files, ~1,278 LoC):**
- `Shared.swift` (4) — Module marker.
- `AudioFeatures.swift` (10) — Public umbrella for the AudioFeatures+ extensions.
- `AudioFeatures+Analyzed.swift` (372) — The load-bearing FeatureVector + supporting types. Carries the 48-float / 192-byte GPU contract per D-099 / DM.2.
- `AudioFeatures+Frame.swift` (93) — Per-frame audio sample frame value type.
- `AudioFeatures+Metadata.swift` (121) — `TrackMetadata`, `PreFetchedTrackProfile`, `MetadataSource` (per CA-Audio correction).
- `AudioFeatures+SceneUniforms.swift` (149) — SceneUniforms GPU struct (used by Presets/Renderer).
- `StemFeatures.swift` (189) — 64-float / 256-byte stem features per D-099 / DM.2 / D-126 V.9 Session 4.5c addition.
- `AnalyzedFrame.swift` (64) — Per-frame fused FeatureVector + StemFeatures snapshot.
- `BeatSyncSnapshot.swift` (60) — Beat-sync diagnostic snapshot for `BeatSyncSnapshot` artifact per CLAUDE.md §Defect Handling.

**SessionRecorder cluster (5 files, ~803 LoC):**
- `SessionRecorder.swift` (375) — Main recorder. Atomic write semantics, NSLock-guarded.
- `SessionRecorder+CSV.swift` (78) — features.csv + stems.csv writers.
- `SessionRecorder+RawTap.swift` (162) — raw_tap.wav writer.
- `SessionRecorder+Stems.swift` (37) — stem-separation diagnostic writer.
- `SessionRecorder+Video.swift` (151) — AVAssetWriter video.mp4 capture (Failed Approach #28 drawable-size-lock guard).

**UMA / buffer primitives (3 files, ~626 LoC):**
- `UMABuffer.swift` (181) — Generic UMA buffer wrapper for GPU consumption.
- `SpectralHistoryBuffer.swift` (237) — Ring buffer for SpectralCartograph diagnostic (carries the BeatGrid tick marks at `[2402..2417]` + session-mode label at `[2420]` per ARCH).
- `StemSampleBuffer.swift` (208) — Stem audio sample ring buffer.

**Utility infrastructure (6 files, ~487 LoC):**
- `Logging.swift` (37) — `Logging.session` os.Logger surface for the engine module.
- `DeviceTier.swift` (26) — `.tier1` / `.tier2` enum + frame-budget computed properties.
- `Smoother.swift` (52) — EMA smoothing helper.
- `RenderPass.swift` (85) — `RenderPass` enum (direct / feedback / particles / mesh_shader / post_process / ray_march / ssgi / staged / mv_warp / icb).
- `UserFacingError.swift` (183) — Canonical error taxonomy per UX_SPEC §8.
- `UserFacingError+Presentation.swift` (191) — UI presentation extensions for UserFacingError.

**Diagnostic / instrumentation (1 file, ~320 LoC):**
- `BUG012Probe.swift` (320) — BUG-012-i1 instrumentation harness. **Read-only.**

**Dashboard tokens (1 file, ~130 LoC, in subdirectory):**
- `Dashboard/DashboardTokens.swift` (130) — Shared design tokens (font sizes, color hex, spacing). Consumed by CA.7b Renderer Supporting Dashboard cluster + CA.6 view-side cards.

### Boundary surfaces (in scope, with annotation)

- **Shared ↔ Audio.** `TrackMetadata` + `PreFetchedTrackProfile` + `MetadataSource` are produced by `MetadataPreFetcher.merge(_:)` (Audio) but the type definitions live here. CA-Audio verified the producer-side; CA-Shared owns the type-definition side.
- **Shared ↔ DSP.** `FeatureVector` is the canonical output type of the MIR pipeline (CA.1); CA-Shared verifies the Swift-side declaration matches the documented contract.
- **Shared ↔ ML.** `StemFeatures` is the canonical output type of the stem analysis pipeline (CA.2); CA-Shared verifies the Swift-side declaration matches the MV-3 / D-028 contract.
- **Shared ↔ Renderer.** `SceneUniforms` + `RenderPass` enum + `UMABuffer` are consumed at every render-pipeline branch (CA.7a + CA.7b). Verify Swift-side declarations match the GPU-slot bindings the renderer expects.
- **Shared ↔ Presets.** `FeatureVector` + `StemFeatures` + `SceneUniforms` MSL struct declarations in `PresetLoader+Preamble.swift` must be byte-identical to the Swift sides. CA-Presets verified the preamble; CA-Shared verifies the producer side.
- **Shared ↔ Session.** `BeatSyncSnapshot` is the diagnostic artifact for `dsp.beat` defects per CLAUDE.md §Defect Handling. CA.3 audited the session-side capture; CA-Shared owns the type definition.
- **Shared ↔ App.** `SessionRecorder` is constructed and owned by the App layer (CA.5); CA-Shared audits the type/method surface. `Logging.session` is the App-side error path. `UserFacingError` is the App-side toast/error-view consumer (CA.6).
- **Shared ↔ Orchestrator.** `DeviceTier` is consumed by the orchestrator's complexity-cost gate (per CA.4). `RenderPass` is consumed by the orchestrator's transition policy.

### Explicit exclusions (out of CA-Shared scope)

- **`PhospheneEngine/Sources/Presets/Shaders/*.metal`** (17 files, 12,065 LoC). Deferred to a separate increment per CA-Presets.
- **All other engine modules** (DSP/ML/Audio/Session/Orchestrator/Renderer/Presets) — already audited.
- **PhospheneApp/** — already audited (CA.5 + CA.6).
- **PhospheneEngine/Tests/** — read freely for test discriminators, but audit verdicts apply to production code, not tests.

If something in the boundary surfaces seems important enough that the audit's value is reduced without it, note the gap and continue. Do not expand scope.

## Methodology

The methodology is the same as CA.1–CA-Presets with no new additions — the format is stable. One small refinement worth carrying forward from CA-Presets: when a single file's claimed responsibility cross-cuts multiple consumers (e.g., `FeatureVector` is consumed by DSP + ML + Audio + Renderer + Presets + App), enumerate the consumer chain per consumer-module in the file's verdict block. CA-Presets's BUG-016 producer-side characterisation showed this fine-grained mapping pays off when a future BUG investigation needs to know which module's read path is implicated.

### Pass 0 — Kickoff cross-check

Before reading any source file:

1. **BUG cross-check.** Verify every BUG cited in this kickoff against `docs/QUALITY/KNOWN_ISSUES.md`:
   - **BUG-012** — should still be Open. If Matt characterised the symptom further since the kickoff's draft, incorporate into Pass 1 BUG012Probe read.
   - **BUG-001 / BUG-005 / BUG-013 / BUG-016** — should still be Open (none Shared-affecting at the producer-side).
   - **BUG-011 / BUG-015 / BUG-R002 / BUG-R003** — should be Resolved.
   - If any kickoff claim disagrees with KNOWN_ISSUES.md, the audit's first finding is the kickoff staleness.
2. **Verify CA-Audio-FU-9 (Module Map Sync) status.** Filed 2026-05-21 as a planned increment. If CA-Shared discovers further Module Map drift in the Shared/ block (which is likely — 6-in-a-row pattern across CA.5/6/7a/7b/CA-Audio/CA-Presets), bundle the Shared-block fixes into CA-Audio-FU-9's scope at landing time rather than fixing piecemeal in CA-Shared.
3. **Verify pre-existing follow-ups.** CA-Audio-FU-4 + FU-5 + FU-6 + FU-7 + FU-8 (open, outside CA-Shared scope). CA-Presets-FU-1 through FU-5 (open, outside CA-Shared scope — but FU-4 cross-references Shared `Logging.session` if a Logging API extension is needed). If anything regressed, surface it.
4. **State the sub-scope decision explicitly.** Default: single-pass Swift audit; no methodology split needed.

### Pass 1 — Inventory + verdict assignment

For each file in scope, produce:

- **File summary** — one paragraph: what this file owns; the kind of work it does.
- **Public / internal surface** — every public / internal type and every public / internal method, with brief signatures.
- **Documented features** — comment headers, MARK sections, doc-comments. Quote verbatim where the claim matters.
- **Notable internal types / private members** if load-bearing (e.g., `@Published` properties, NSLock-guarded state, `@frozen` annotations, struct field offsets).
- **File-level constants / tuning values** with names and values.
- **Any code-level TODOs / FIXMEs / placeholder branches.**

**Read strategy.** At ~3,515 LoC across 25 files, direct-read every file > 150 LoC (8 files: AudioFeatures+Analyzed 372, SessionRecorder 375, BUG012Probe 320, SpectralHistoryBuffer 237, StemSampleBuffer 208, UserFacingError 183, UserFacingError+Presentation 191, UMABuffer 181, StemFeatures 189, SessionRecorder+RawTap 162, SessionRecorder+Video 151, AudioFeatures+SceneUniforms 149) and batch the rest across 1 parallel Explore agent. The cluster has no extension-split type-fragmentation issue like ArachneState (Presets) — each file is generally a single coherent type, so single-shot reads suffice.

After each agent's report, run the visibility verification grep per file. Reconcile each agent-claimed public against the grep.

Then for each capability, trace consumers via grep:

```
grep -rn "TypeName" PhospheneApp PhospheneAppTests PhospheneEngine/Sources PhospheneEngine/Tests   # type usage
grep -rn "\.functionName(" …                                                                       # call sites
grep -rn ": ProtocolName" …                                                                        # conformances
```

For types referenced only in tests: note as test-only (different verdict than production).

Record per capability: production consumers, test consumers, no consumers. For any production-orphan candidate, the cited grep command + result count is mandatory. Apply the CA.7b non-nil-caller refinement to setter / mutator APIs.

Cross-reference each capability against the load-bearing docs. Record: claimed in docs (yes/no, citations), doc claim aligned with code (yes/no, divergence noted), documented as planned-but-not-built (yes/no).

**Behaviour validation — key test discriminators by domain:**

- **AudioFeatures + StemFeatures**: `AudioFeaturesByteLayoutTests` / `CommonLayoutTest` (D-099 byte-identity); `FeatureVectorTests` (field semantics); `StemFeaturesTests`. Verify struct stride + first-32 / first-16 floats byte-identical to original DM.0 layout.
- **SessionRecorder**: `SessionRecorderTests` / `SessionRecorderRawTapTests` / `SessionRecorderVideoTests` (drawable-size lock per Failed Approach #28); `BeatSyncSnapshotRecordingTests`. Verify lock-guarded writes, atomic file moves, video drawable-size deferred-lock.
- **UMABuffer**: `UMABufferTests`. Verify storage-mode-shared allocation + stride invariants.
- **UserFacingError**: `UserFacingErrorTests`. Verify every UX_SPEC §8 error case has a matching enum case.
- **BeatSyncSnapshot**: snapshot capture invariants per CLAUDE.md §Defect Handling.
- **SpectralHistoryBuffer**: `SpectralHistoryBufferTests`. Verify ring-buffer wraparound + BeatGrid tick mark slot mapping (`[2402..2417]` per ARCH) + session-mode label slot (`[2420]`).
- **BUG012Probe**: read-only. Document existence + integration points without modification.

Use them as the discriminators they are.

**Assign verdict per capability** (definitions carried forward from CA.7b + CA-Audio + CA-Presets):

| Verdict | Meaning |
|---|---|
| `production-active` | Consumed by production code; doc claims match code behavior; behavior validated. |
| `production-orphan` | Consumed nowhere in production code (test consumers only OR no consumers). Requires cited grep. Also applies to setter APIs with only nil-reset callers (CA.7b refinement). |
| `production-orphan + planned-consumer (kept-by-design)` | As above, but Matt's product call has been made to keep for a specific future planned consumer. Pattern from CA.7-FU-3 / CA.7b-FU-3 / CA-Audio-FU-2 / FU-3. |
| `dead` | Confirmed dead — no consumers anywhere; safe to delete. |
| `stub` | Exists as signature; body empty / default / unimplemented. |
| `documented-but-missing` | Docs claim it exists; code does not. |
| `built-but-undocumented` | Code has it; no doc references it. |
| `broken-but-claimed` | Docs claim it works; runtime behavior contradicts. File a BUG-XXX entry immediately. |
| `unverified-claim` | Consumed; docs claim correctness; no evidence of correctness. |
| `boundary-noted` | Lives at a subsystem boundary; verdict is complete (no future re-audit obligation). |
| `boundary-deferred` | Lives at a subsystem boundary; full verdict requires the other subsystem's audit. |

### Pass 2 — Doc-drift triangulation

Once verdicts are assigned, scan load-bearing docs for additional drift:

- Does ARCHITECTURE.md §Module Map Shared/ block (verify line range) accurately list all 25 Swift files in scope? (CA-Presets confirmed the 6-in-a-row pattern; expect drift here too.)
- Does ARCHITECTURE.md §Key Types describe the same struct layouts (FeatureVector 48 floats / 192 bytes; StemFeatures 64 floats / 256 bytes; SceneUniforms; AnalyzedFrame; TrackMetadata) the code declares?
- Does ARCHITECTURE.md §GPU Contract Details slot/binding tables match the Swift-side `RenderPass` enum cases + `UMABuffer` consumers?
- Are tuning constants quoted in docs identical to the code's values? (`Smoother` EMA alpha; `SpectralHistoryBuffer` slot indices; `SessionRecorder` ring sizes.)
- Does UX_SPEC.md §8 error taxonomy match every case in `UserFacingError`? (Bidirectional check.)
- Does any architectural claim describe a path that no longer exists? Was retired? Was renamed?
- Do any decisions in DECISIONS.md reference type names that have moved or been renamed?
- Does CLAUDE.md §Key Types still match the current code?

Record drift findings as a separate cross-reference section in the audit doc.

## Output structure (template — extends CA-Presets)

Output file: `docs/CAPABILITY_REGISTRY/SHARED.md`.

```
# Capability Registry — Shared Subsystem
**Audit increment:** CA-Shared
**Date:** 2026-05-XX
**Auditor:** Claude (session-driven, read-only)
**Scope:** `PhospheneEngine/Sources/Shared/` — 25 Swift files / ~3,515 LoC.
**Methodology:** Phase CA scoping document (CA-Shared kickoff).
**Reads relied on:** [list]
**Sibling audits:** docs/CAPABILITY_REGISTRY/PRESETS.md (CA-Presets — D-099 / DM.2 consumer side), docs/CAPABILITY_REGISTRY/RENDERER.md (CA.7a — RenderPass enum consumer; GPU contract slot bindings), docs/CAPABILITY_REGISTRY/RENDERER_SUPPORTING.md (CA.7b — DashboardTokens consumer), docs/CAPABILITY_REGISTRY/APP.md (CA.5 — SessionRecorder construction + lifecycle; UserFacingError App-layer consumer), docs/CAPABILITY_REGISTRY/APP_VIEWS.md (CA.6 — UserFacingError view-side consumer + Dashboard card consumers), docs/CAPABILITY_REGISTRY/AUDIO.md (CA-Audio — TrackMetadata producer side correction).

## Summary
[One paragraph: capability counts per verdict, top findings, follow-up count, kickoff-vs-KNOWN_ISSUES cross-check result.]
[Markdown table of verdict counts.]

## Sub-scope decision
[State the scope chosen at Pass 0 explicitly. Default: single-pass.]

## Findings by verdict
[Per-finding citations as CA-Presets template.]

## Per-file capability index
[One section per file or per cluster. Consolidation allowed if verdicts heavily concentrate in production-active.]

## Verification of D-099 / DM.2 Common.metal struct extension invariant (Swift producer side) (CA-Shared-specific)
[Required section. Verify Swift-side `FeatureVector` is `@frozen public struct` with 48 floats / 192 bytes; verify first 32 floats are byte-identical to original DM.0 layout (bass through accumulated_audio_time). Verify Swift-side `StemFeatures` is `@frozen` (if declared so) with 64 floats / 256 bytes; first 16 floats byte-identical. Cross-check against the MSL declarations in `PresetLoader+Preamble.swift:34-128` verified by CA-Presets. Cite the test sites (`AudioFeaturesByteLayoutTests` / `CommonLayoutTest` / equivalents) that lock the stride.]

## Verification of UserFacingError ↔ UX_SPEC.md §8 alignment (CA-Shared-specific)
[Required section. Enumerate every case in `UserFacingError`. Cross-reference against UX_SPEC.md §8 error taxonomy. Note any UX_SPEC case missing from the enum, or any enum case not documented in UX_SPEC.]

## Verification of SessionRecorder drawable-size-lock invariant (CA-Shared-specific, Failed Approach #28)
[Required section. Verify `SessionRecorder+Video.swift` defers AVAssetWriter init until N consecutive same-size frames per Failed Approach #28; verify mismatched-size frames are skipped, not blit-into-wrong-geometry. Document the lock semantics + the deferred-init logic. Cross-reference `SessionRecorderVideoTests`.]

## Verification of TrackMetadata + PreFetchedTrackProfile + MetadataSource (CA.3 / CA-Audio carry-forward) (CA-Shared-specific)
[Required section. Verify the three types live in `AudioFeatures+Metadata.swift` (lines 10, 30, 69 per CA-Audio); enumerate their public surface; trace consumers across Audio + Session + App via grep. Close the CA-Audio carry-forward correction to CA.3 SESSION.md line 145.]

## Verification of BUG-012 instrumentation surface (BUG012Probe.swift) (CA-Shared-specific, read-only)
[Required section. Read BUG012Probe.swift end-to-end. Document the instrumentation API surface (function signatures, what it captures, what it logs). Trace its production consumers (where is it wired into the StemFFTEngine MPSGraph path?). Verify the probe is read-only per the standing rule. Do not modify. If a candidate diagnostic explanation for the EXC_BAD_ACCESS surfaces from reading the code (e.g., a missing memory barrier, a wrong MPSGraph dispose order), file as addendum to KNOWN_ISSUES.md BUG-012.]

## Verification of SpectralHistoryBuffer slot mapping (CA-Shared-specific)
[Required section. Verify the BeatGrid tick mark slot range `[2402..2417]` per ARCH; verify the session-mode label slot `[2420]`. Cross-reference against `SpectralCartograph.metal` shader consumers (out of CA-Shared scope, but the slot mapping must match). Document any drift.]

## Verification of DashboardTokens placement (Shared vs Renderer) (CA-Shared-specific)
[Required section. The Dashboard cluster lives partly in Renderer (CA.7b) and partly in Shared (Dashboard/DashboardTokens.swift). Verify whether DashboardTokens is consumed by both Renderer + App-views (justifies Shared placement) OR exclusively by Renderer (suggests it should move to Renderer). Recommend keep / move based on consumer trace.]

## Cross-references
### Updates needed in CLAUDE.md
### Updates needed in ARCHITECTURE.md
### Updates needed in ENGINEERING_PLAN.md
### Updates needed in DECISIONS.md
### Updates needed in UX_SPEC.md
### Updates needed in KNOWN_ISSUES.md (BUG-012 addendum if candidate root cause surfaces)
### Updates needed across sibling audits (carry-forward corrections)
### New BUG entries
### KNOWN_ISSUES.md sweep

## Follow-up Backlog
| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA-Shared-FU-1** | … | … | … | … |
| **CA-Shared-FU-2** | … | … | … | … |
| **CA-Shared-FU-N** (if Module Map drift surfaces in Shared/ block, fold into CA-Audio-FU-9 rather than filing separately) | … | … | … | … |

## Approach validation
[Critique of methodology. What worked? What didn't? Recommended changes for the next CA increment — Module Map sync (CA-Audio-FU-9), shader audit (CA-Preset-Shaders), or close Phase CA.]
```

## File the artifact + cross-references

Per CLAUDE.md increment closeout protocol:

- The audit document is the primary deliverable.
- Any `broken-but-claimed` findings get BUG-XXX entries in KNOWN_ISSUES.md immediately. The next available BUG number is **BUG-017** (no new BUG entries filed in CA-Presets — the BUG-016 addendum extended an existing-Open BUG body, not a new number).
- **BUG-012 addendum:** if CA-Shared's `BUG012Probe.swift` read surfaces a structural candidate root cause for the EXC_BAD_ACCESS symptom, file it as an addendum to BUG-012's existing body (not a new BUG number) — same shape as CA-Presets's BUG-016 addendum + CA.4's BUG-015 discovery.
- ENGINEERING_PLAN.md gets an entry in Recently Completed (CA-Shared ✅) plus the CA-Shared row added (no row exists yet — write one).
- CLAUDE.md / ARCHITECTURE.md / UX_SPEC.md drift findings are corrected in this same increment, UNLESS the Module Map drift discovered is large enough to bundle into CA-Audio-FU-9 (the standalone Module Map sync increment filed 2026-05-21). If the Shared/ Module Map block is missing > 3 files, defer the Module Map fix to FU-9; if it's just a handful, fix in CA-Shared and note in FU-9 that Shared/ is now clean.

Commit shape (matches CA.1 / CA.2 / CA.3 / CA.4 / CA.5 / CA.6 / CA.7a / CA.7b / CA-Audio / CA-Presets — two commits, doc-only):

- `[CA-Shared] Shared capability audit: registry + findings`
- `[CA-Shared] ARCHITECTURE.md / ENGINEERING_PLAN.md / KNOWN_ISSUES.md / UX_SPEC.md: doc-drift corrections from Shared audit` (if any)

## Done-when

CA-Shared closes when:

- [ ] `docs/CAPABILITY_REGISTRY/SHARED.md` published.
- [ ] Sub-scope decision documented explicitly (default: single-pass, no split).
- [ ] Every public / internal capability in scope has a verdict.
- [ ] Every production-orphan verdict cites the grep command used.
- [ ] Every Explore-agent-claimed public / internal symbol was cross-checked against a visibility grep.
- [ ] Non-nil-caller production-orphan check (CA.7b refinement) applied to every setter / mutator API on producer types in scope.
- [ ] Kickoff-vs-KNOWN_ISSUES.md cross-check ran as Pass 0 step 1.
- [ ] Every non-production-active finding either ships a doc-fix in this increment OR is registered as a CA-Shared-FU-N follow-up.
- [ ] All `broken-but-claimed` findings have BUG entries in KNOWN_ISSUES.md (or BUG-012 addenda).
- [ ] D-099 / DM.2 byte-layout invariant verified (Swift producer side).
- [ ] UserFacingError ↔ UX_SPEC.md §8 alignment verified.
- [ ] SessionRecorder drawable-size-lock invariant verified (Failed Approach #28).
- [ ] TrackMetadata + PreFetchedTrackProfile + MetadataSource boundary closed (CA.3 / CA-Audio carry-forward).
- [ ] BUG012Probe.swift instrumentation surface characterised (read-only).
- [ ] SpectralHistoryBuffer slot mapping verified.
- [ ] DashboardTokens placement (Shared vs Renderer) verdict recorded.
- [ ] Drift corrections to load-bearing docs landed (OR Module Map drift folded into CA-Audio-FU-9).
- [ ] "Approach validation" section produces an honest critique of whether Phase CA is ready to close OR what the next increment (Module Map sync / shader audit) should look like.
- [ ] All commits land on main (local). Push only on Matt's explicit approval.

## After CA-Shared lands

Surface to Matt:

- The audit summary (broken-but-claimed count, documented-but-missing count, production-orphan count, follow-up count).
- The verdict on BUG-012 producer-side surface (structural candidate root cause if any; characterised instrumentation if not).
- The verdict on the 6 invariants verified (D-099 / DM.2 / UserFacingError ↔ UX_SPEC / Failed Approach #28 / TrackMetadata boundary / BUG012Probe / SpectralHistoryBuffer / DashboardTokens placement).
- Any new CA-Shared-FU items registered.
- Whether the Shared/ Module Map block drift was bundled into CA-Audio-FU-9 or fixed in CA-Shared.
- **Phase CA closure status.** With Shared closed, every Swift engine surface is audited. The only remaining audit work is (a) CA-Audio-FU-9 Module Map Sync (cross-cutting registry+doc sync), and (b) a deferred `.metal` shader audit (CA-Preset-Shaders or aligned to the existing M7 cert review process). Recommend Matt's product call on whether to ship CA-Audio-FU-9 next (closes the 6-in-a-row systemic finding) OR to start the shader audit OR to declare Phase CA complete with FU-9 + shaders deferred.

Do not start CA-Audio-FU-9 or the shader audit in the same session.

## Failure modes to watch for

Specifically for Shared-shaped audit work:

- **Treating Shared as a grab-bag.** It isn't. The module has a clear architectural role: cross-cutting types and primitives that every other module consumes. Each file's verdict block should clearly identify which sibling modules consume the type/method — `FeatureVector` is consumed by 5 modules (DSP/ML/Audio/Renderer/Presets); `UserFacingError` by 2 (App engine-adapter + view layer); `DashboardTokens` by 2 (Renderer + App views). Document the consumer fan-out.
- **Forgetting that GPU-contract types embody their byte layout.** `FeatureVector` + `StemFeatures` + `SceneUniforms` are not ordinary Swift structs — they are GPU contract surfaces. Changes to field order or size break preset rendering invisibly. The audit verifies byte identity against the MSL preamble; structural changes are filed as follow-ups, never landed in the audit increment.
- **Missing the producer/consumer asymmetry.** Most Shared types are **consumed everywhere but produced in one place** — `FeatureVector` is produced by `MIRPipeline` (DSP) and consumed by everything. The audit's verdict for the producer-side responsibility lives in the DSP audit (CA.1); CA-Shared's verdict is for the type definition + declaration + invariants. Don't re-audit producer logic.
- **Citing without verifying.** Same as CA.1–CA-Presets's rule. Every claim is evidence-backed with a file:line or a doc:line.
- **Producing structure as a substitute for substance.** Headers must be backed by content. Empty buckets should be said-empty, not pretended-incomplete.
- **Scope creep into BUG-012 fix work.** `BUG012Probe.swift` is read-only. The audit may surface a candidate diagnostic root cause as a BUG-012 addendum; it never modifies the probe.
- **Scope creep into AVFoundation rabbit-holes.** `SessionRecorder+Video.swift` touches AVAssetWriter; verifying Failed Approach #28's drawable-size-lock invariant does not require reading the entire AVFoundation surface. Stay narrow: does the code defer init until N consecutive same-size frames? Yes / No / Why.

## Status on entry

- **Branch: main.** CA.0 + CA.1 + CA.2 + CA.3 + CA.4 + CA.5 + CA.6 + CA.7a + CA.7b + CA-Audio + CA-Presets + their follow-ups all landed on main as of 2026-05-21. Recent commits (most-recent first):
  ```
  <CA-Shared kickoff commit (this doc)>
  1a10d257  [CA-Presets] ARCHITECTURE.md / ENGINEERING_PLAN.md / KNOWN_ISSUES.md: doc-drift corrections from Presets audit
  d6615dd5  [CA-Presets] Presets capability audit: registry + findings
  afd040a4  [CA-Presets] Scoping: kickoff doc for Presets-Swift-slice capability audit
  519feb96  [CA-Audio-FU-2 + CA-Audio-FU-3 + CA-Audio-FU-9] mark LookaheadBuffer + MusicKitFetcher kept; file Module Map Sync
  e81d8968  [CA-Audio] ARCHITECTURE.md + SESSION.md + ENGINEERING_PLAN.md: doc-drift corrections from Audio audit
  0d66eecf  [CA-Audio] Audio capability audit: registry + findings
  …
  ```
- **Local + remote:** local main matches origin/main as of session start (CA-Presets commits pushed 2026-05-21 with Matt's explicit approval). Working tree clean apart from the documented `default.profraw` build artifact.
- **SwiftLint baseline: 0 violations** across 371 files. Any violation in active source paths is a regression per `project_swiftlint_baseline.md` memory note. CA-Shared should remain at 0.
- **Test counts:** Engine 1,248 tests / 162 suites all passing as of CA.7-FU-4 close. App 328 tests / 60 suites all passing. Neither CA-Audio nor CA-Presets changed either count.
- **Pre-existing flakes** continue per the existing chip baselines:
  - **Engine-side:** `MetadataPreFetcher.fetch_networkTimeout` (env-dependent — CA-Audio-internal flake), `SoakTestHarness.cancel`, `MemoryReporter.residentBytes` (env-dependent, isIntermittent: true).
  - **App-side:** timing margins widened per U.10 / U.11.
  - None are Shared-internal; CA-Shared should not encounter them.
- **Open follow-ups carried in** (out of CA-Shared scope; do not address):
  - CA.7-FU-1 — Tighten `AuroraVeilMVWarpAccumulationTest`. Marginal; low-priority.
  - CA.7-FU-2 — Remove dead `RayMarchPipeline.depthDebugEnabled` cluster. Mechanical cleanup.
  - CA.7b-FU-4 — `setMeshPresetBuffer` / `setMeshPresetFragmentBuffer` zero-non-nil-caller cleanup (latent slot-1 collision). Low-priority.
  - CA-Audio-FU-4 — Add `AudioInputRouter+SignalState` tap-reinstall tests.
  - CA-Audio-FU-5 — Add `InputLevelMonitor` tests.
  - CA-Audio-FU-6 — Retire `FFTProcessor.printHistogram`.
  - CA-Audio-FU-7 — Tighten `MoodClassifying` docstring.
  - CA-Audio-FU-8 — RUNBOOK Spotify connector disambiguation.
  - **CA-Audio-FU-9 — Module Map Sync (cross-cutting).** If CA-Shared discovers further Module Map drift in the Shared/ block, bundle into FU-9's scope at landing time.
  - CA-Presets-FU-1 — AuroraVeil.json `"passes": []` clarity (cosmetic).
  - CA-Presets-FU-2 — LumenMosaic.json dead `"lumen_mosaic": {...}` config block.
  - CA-Presets-FU-3 — Retire `GossamerState.lcg(_:)` dead helper.
  - CA-Presets-FU-4 — `Logging.session?.log(...)` instrumentation on `LumenPatternEngine` init-failure (depends on Matt's BUG-016 reproduction). **Cross-references `Logging.session` API from this audit's `Logging.swift` read.**
  - CA-Presets-FU-5 — `FidelityRubric+Mandatory.swift` pale-share-as-M7-manual comment.
- **BUG-012 is Open.** BUG-012-i1 instrumentation in place across 8 files; **`BUG012Probe.swift` IS in CA-Shared scope (read-only)**. BUG-016 is Open with CA-Presets addendum + CA-Presets-FU-4 pending Matt's reproduction. BUG-005 / BUG-013 / BUG-001 all Open, none Shared-affecting at the producer side.
- **No CA-Shared code or audit has landed.** This is the kickoff.

## Sign-off

This prompt is the canonical entry point for **Increment CA-Shared**. With Shared closed, Phase CA will have covered every Swift engine surface — the only remaining audit work is the cross-cutting CA-Audio-FU-9 Module Map Sync and the deferred `.metal` shader audit. Matt's product call on Phase CA closure status comes after CA-Shared lands.

If you find the prompt is wrong or stale during the audit, update the prompt before continuing — do not work against a brief you know to be incorrect.

— Matt + Claude (2026-05-21 design session, post-CA-Presets closeout + push)
