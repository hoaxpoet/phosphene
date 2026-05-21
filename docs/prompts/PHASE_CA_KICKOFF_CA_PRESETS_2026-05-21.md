# Phase CA Kickoff — Capability Audit — Increment CA-Presets (Presets module — Swift slice)

Hand this to a new Claude Code session verbatim. Do not summarise.

## What this phase is

Phase CA — Capability Audit is a multi-increment archaeology of Phosphene's codebase. Each increment audits one subsystem: reads the actual source, traces consumers and producers, cross-references against `CLAUDE.md` / `docs/ARCHITECTURE.md` / `docs/QUALITY/KNOWN_ISSUES.md` / `docs/DECISIONS.md`, and assigns a health verdict to every capability the subsystem exposes.

Prior increments (all closed; deliverables live in `docs/CAPABILITY_REGISTRY/`):

- **CA.1** (DSP / MIR) closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/DSP_MIR.md`. 22 files. Surfaced one runtime production-orphan cluster (later superseded by BUG-015 fix).
- **CA.2** (ML) closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/ML.md`. 16 files / 4,507 LoC. Methodology refinement: pre-grep visibility verification.
- **CA.3** (Session) closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/SESSION.md`. 22 files / ~3,425 LoC. Methodology refinement: cross-check kickoff prompt against `KNOWN_ISSUES.md` as Pass 0. Surfaced the Session ↔ Audio boundary-noted item that CA-Audio resolved.
- **CA.4** (Orchestrator) closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md`. 14 files / ~2,950 LoC. Surfaced load-bearing broken-but-claimed BUG-015 — `applyLiveUpdate(...)` had zero production call sites; the entire Phase 4.5/4.6 live-adaptation pipeline was dead in production. BUG-015 fixed 2026-05-21.
- **CA.5** (App-layer engine-adapter slice) closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/APP.md`. 49 files / 7,975 LoC.
- **CA.6** (App-layer Views + ViewModels presentation slice) closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/APP_VIEWS.md`. 59 files / 8,285 LoC.
- **CA.7a** (Renderer — core pipeline) closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/RENDERER.md`. 23 files / 5,413 LoC. Two follow-ups resolved same-day: CA.7-FU-3 (keep ICB) + CA.7-FU-4 (retire setRayMarchPresetComputeDispatch).
- **CA.7b** (Renderer — supporting modules) closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/RENDERER_SUPPORTING.md`. 15 files / 2,241 LoC. RayTracing cluster filed as production-orphan + boundary-noted; CA.7b-FU-3 resolved 2026-05-21 (keep — Matt product call).
- **CA-Audio** (Audio module) closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/AUDIO.md`. 16 files / 3,294 LoC. Three follow-ups resolved same-day: CA-Audio-FU-2 (keep LookaheadBuffer) + CA-Audio-FU-3 (keep MusicKitFetcher) + CA-Audio-FU-9 (file Module Map Sync as a separate planned increment). CA-Audio-FU-1 resolved in-audit (kickoff staleness on BUG-005 attribution corrected).

The DSP / ML / Session / Orchestrator / App / Renderer / Audio modules are now fully closed. **Presets is the last remaining unaudited engine module.** `Sources/Shared/` remains deferred (see "After CA-Presets lands" below).

This kickoff is for **Increment CA-Presets**: the per-preset infrastructure under `PhospheneEngine/Sources/Presets/` — Swift slice only. The `.metal` shader slice is deferred to a follow-up increment per the sub-scope decision below.

## Why CA-Presets next

Four reasons, in priority order:

1. **Last unaudited engine module.** Audio closed yesterday; the only remaining unaudited Sources/ tree is Presets/. Closing Presets means Phase CA has covered every engine module that has shipped code. Shared/ is the natural next-after pass (smaller, more cross-cutting).

2. **BUG-016 (Lumen Mosaic) producer-side investigation lives here.** [KNOWN_ISSUES.md BUG-016](../QUALITY/KNOWN_ISSUES.md) is Open with "reproduction incomplete." The candidate failure modes (5 listed in the BUG body) include slot-8 fragment-buffer regression, palette-library drift from LM.4.7, and silent shader failure. All three live in `Sources/Presets/Lumen/` + `Shaders/LumenMosaic.metal` + `Shaders/LumenMosaic.json`. The audit is uniquely positioned to surface a structural diagnosis even before manual reproduction.

3. **Load-bearing CLAUDE.md rules concentrate here.** The preset-authoring rules (Failed Approaches #23, #24, #28, #31–#34, #39–#48, #57, #58, #61–#67), the visual quality floor (`SHADER_CRAFT.md §12.1`), the GPU-contract slot reservations (slots 6/7/8 per D-LM-buffer-slot-8 + D-092/D-093/D-094), the per-preset state contracts (D-094 80-byte spider, D-095 V.7.7C foreground-hero, D-097 particle siblings, D-099 / DM.2 Common.metal extension) all live in this module's Swift code (the per-preset state classes) or its shader files (deferred).

4. **The Drift Motes / D-102 retirement aftermath.** D-102 retired Drift Motes; the closeout noted "future revival starts from a new preset spec, not by undoing the deletion." The audit verifies the retirement was clean: no DriftMotes-related code remnants in Presets/, ParticleGeometryRegistry only knows "Murmuration" (per CA.7b), no JSON sidecar references DriftMotes. Failed Approach #58 (visual subject without load-bearing musical role) is the bedrock learning — its enforcement lives in the `PresetDescriptor` schema + the certification rubric.

## Read these first, before doing anything else

- **`CLAUDE.md`** — the entire file. Especially:
  - §Authoring Discipline (every rule applies at preset scope)
  - §Visual Quality Floor (pale-tone-share ≤ 0.30 per D-LM-cream-rescission)
  - §What NOT To Do (the long list of preset-author rules)
  - Failed Approaches #23 (architecture deformation), #24 (light vs IBL ambient), #25 (mood overlay), #26 (beat-band coverage), #28 (drawable-size locking), #31–#34 (AGC primitive selection + warp pass + sin(time) oscillation + SDF folds), #39–#48 (reference-driven authoring + material count + grey fog + §10.1-faithful vs reference-divergent + structural-vs-tunable + structural-gap escalation), #57 (Arachne sub_bass + AR gate), #58 (Drift Motes failure record), #61 (mirror-reflects-sky vs point lights), #62 (decoration layers without musical role), #63 (read README before authoring), #64 (desk research before iterative first-principles fixing), #65 (don't argue away working reference components), #66 (test/prod parity for G-buffer branch), #67 (one audio primitive per visual layer).
- **`docs/CAPABILITY_REGISTRY/AUDIO.md`** — most-recent CA closeout. Read especially:
  - §Verification of D-079 sample-rate plumbing (the literal-grep methodology reused below for the `44100` allowlist + the D-026 `f.bass * X` `.metal` warning the gate emits).
  - §Approach validation (the non-nil-caller production-orphan refinement; the 5-in-a-row Module Map drift finding — CA-Presets will likely add a 6th).
  - §Cross-references (kept-by-design annotation pattern from CA-Audio-FU-2 + FU-3 — same pattern likely applies to any retired-but-preserved preset infrastructure).
- **`docs/CAPABILITY_REGISTRY/RENDERER.md`** (CA.7a) + **`docs/CAPABILITY_REGISTRY/RENDERER_SUPPORTING.md`** (CA.7b). Read especially:
  - CA.7a §Verification of Failed Approach #66 test/prod parity — the render-path dispatch chosen per preset (mv_warp / staged / ray_march / direct fragment / particles / mesh) is the same chosen-by-JSON-passes-list logic CA-Presets needs to verify for every preset JSON.
  - CA.7b §D-097 particle-geometry siblings — `ParticleGeometryRegistry.knownPresetNames = ["Murmuration"]` post-Drift Motes; CA-Presets verifies the matching `MurmurationState`/conformer location (likely lives in App per CA.5, but the JSON + Particles*.metal engine-library shader file would live in Presets if present — verify).
- **`docs/CAPABILITY_REGISTRY/APP.md`** (CA.5). Read especially:
  - The per-preset state class ownership trace at `VisualizerEngine.swift:364` — App owns and constructs the per-preset state classes; the state classes themselves live in `PhospheneEngine/Sources/Presets/` (the App holds references; the types live in the engine module). CA-Presets audits the type side; CA.5 already audited the App-side construction + lifecycle.
  - The BUG-016 App-layer surface inventory: Lumen Mosaic apply path at `VisualizerEngine+Presets.swift:166-178`; LumenPatternEngine init can return nil and the failure logs to `os.Logger` only (not `session.log`); recommend adding `sessionRecorder?.log()` on the failure branch. CA-Presets should verify the LumenPatternEngine init failure paths and propose the diagnostic enhancement explicitly.
- **`docs/QUALITY/KNOWN_ISSUES.md`** — every Open entry. Especially:
  - **BUG-016** (Open; Lumen Mosaic "not working" in 2026-05-21 reactive-mode sessions). The Presets-side surface CA-Presets is uniquely positioned to audit. Pass 0 step: cross-check that BUG-016 is still Open; if Matt characterised the symptom further since the audit's draft, incorporate.
  - **BUG-001** (Open; Money 7/4 stays REACTIVE on live path) — DSP defect, not Presets-affecting, but the preset that surfaces it (SpectralCartograph) lives here.
  - **BUG-005** (Open; Spotify preview_url null) — out of CA-Presets scope per CA-Audio-FU-1.
  - **BUG-012** (Open; MPSGraph EXC_BAD_ACCESS in StemFFTEngine) — ML-side instrumentation; not Presets-affecting; BUG-012-i1 instrumentation files NOT in CA-Presets scope.
  - **BUG-013** (Open; Soundcharts no time_signature) — Audio-module-internal (closed in CA-Audio); the consumer of the overridden meter is Ferrofluid Ocean's wave-cycle math (lives in `FerrofluidMesh.swift` per CA-Presets scope) — verify the consumer side handles the meter override correctly per Round 26.
  - **Pre-existing flakes** — none are Presets-specific; document baseline only.
- **`docs/ARCHITECTURE.md`** — sections to read:
  - §Module Map Presets/ block (verify all 30 Swift files are listed; CA-Audio surfaced 2 missing files in Audio/, expect a similar drift here).
  - §GPU Contract Details — the slot-6/7/8 reservations the per-preset state classes flush state to (D-LM-buffer-slot-8, D-092/D-093/D-094 Arachne reserved slots).
  - §Preset Metadata Format — the JSON sidecar schema each preset must conform to (matches `PresetMetadata.swift`).
- **`docs/SHADER_CRAFT.md`** — the preset-author handbook. Especially:
  - §11.1 (`.metal` file_length relaxation past SwiftLint 400-line limit).
  - §12.1 (mandatory quality-floor cert gates: 4+ octaves on hero surfaces, 3+ distinct materials, pale-tone-share ≤ 0.30, reference-image-first authoring).
  - §13 (concept-viability gate — Failed Approach #58 enforcement).
  - §17 (preset metadata format — JSON sidecar schema).
- **`docs/DECISIONS.md`** — grep for D-094 (ArachneSpiderGPU 80-byte), D-095 (V.7.7C foreground-hero), D-096 (Arachne3D toolkit citation for V.8.x), D-097 (particle siblings, not subclasses), D-099 (DM.2 Common.metal extension), D-102 (Drift Motes retirement), D-LM-buffer-slot-8, D-LM-palette-library, D-LM-cream-rescission, D-026 (deviation primitives), D-027 (mv_warp pass), D-051 (mesh shader path for Fractal Tree), D-052 (capture-mode reconciler; not Presets-relevant but for context), D-067/D-068 (preset rotation), D-070 (preview-URL primary), D-071 (M7 contact sheet step), D-072 (V.8 compositing pivot), D-073/D-075/D-077 (Beat This! + BeatGrid), D-079 (sample-rate plumbing; not Presets-relevant but the literal-grep methodology applies for `44100` in `.metal` if shaders ever come into scope).
- **`docs/ENGINEERING_PLAN.md`** — search for V.x (per-preset increments — V.5 reference set, V.7.x Arachne, V.8.x deferred, V.9 Ferrofluid Ocean, V.10 Aurora Veil), AV.x (Aurora Veil iteration), LM.x (Lumen Mosaic), DM.x (Drift Motes retired per D-102), and the Recently Completed entries that touched Presets in the last 60 days.
- **`docs/RUNBOOK.md`** — §Spotify connector setup carries FAs #45 / #46 / #47; not Presets-relevant directly but cross-referenced via the BUG-013 chain.

If any of these files do not exist, record the missing reference as a finding and continue with what does exist.

## Hard rules for this phase

- **No code changes during the audit.** Findings are documented; fixes are separate increments scheduled after the audit publishes. The only file modifications allowed in CA-Presets are the new audit document and minor corrections to load-bearing docs (`ARCHITECTURE.md` / `ENGINEERING_PLAN.md` / `KNOWN_ISSUES.md` / `CLAUDE.md` / `SHADER_CRAFT.md`) that the audit surfaces as drift.
- **BUG-012-i1 instrumentation files remain read-only.** None are in CA-Presets scope by current accounting (all are in `Sources/Shared/` + `Sources/ML/` + `Sources/Renderer/` + `PhospheneApp/`), but verify before editing.
- **Per-preset state classes must NOT be modified.** The Arachnid/AuroraVeil/FerrofluidOcean/Gossamer/Lumen subdirectories carry months of iterative-tuning history; any change risks a preset-fidelity regression invisible to the test suite. CA-Presets reads only.
- **JSON sidecars must NOT be modified.** Same reasoning — sidecar fields encode rubric profiles, complexity costs, scene cameras, stem affinities; tuning the wrong field shifts orchestrator scoring or rubric verdicts.
- **Evidence-based:** every claim cites a file and line. `X exists at path/file.swift:NNN` or `X is referenced but file does not exist`. No claims unverified by inspection of the actual source.
- **`production-orphan` verdicts require a cited grep** (carried forward from CA.2). `X has zero consumers` must be backed by the exact grep command run and a summary of its results. The grep should cover `PhospheneApp/`, `PhospheneEngine/Sources/`, `PhospheneEngine/Tests/`, and `PhospheneAppTests/`. Production-orphan claims without a cited grep will be rejected at closeout.
- **Pre-grep visibility verification** (carried forward from CA.3 + CA.5 + CA.6 + CA.7a + CA.7b + CA-Audio). When parallelising file reads via Explore agents, do not trust an agent's "this type is public" / "this method is internal" reports without cross-checking. After receiving each agent's report, run a single visibility grep per file and reconcile each agent-claimed `public` against the grep.
- **Non-nil-caller production-orphan check** (CA.7b refinement, confirmed-useful by CA-Audio's `onAnalysisFrame`/`onRenderFrame` finding). For any setter / mutator API on per-preset state classes (e.g., `setX(_:)` callbacks that App-side `VisualizerEngine+Presets` wires), grep for non-nil callers, not just `setX\(` callers. A setter with only nil-reset callers is a production-orphan API surface even if it appears production-active at the file level.
- **Cross-check the kickoff prompt against `KNOWN_ISSUES.md` as Pass 0** (carried forward). Verify every BUG cited in this kickoff against actual status:
  - **BUG-016** — should still be Open (Lumen Mosaic reproduction incomplete).
  - **BUG-001** — should still be Open (Money 7/4 REACTIVE; DSP-side fix path).
  - **BUG-005** — should still be Open (Session-side preview_url; not Presets-scope per CA-Audio-FU-1).
  - **BUG-012** — should still be Open (instrumentation in place; CA-Presets does not touch instrumented files).
  - **BUG-013** — should still be Open (Soundcharts no time_signature; FerrofluidMesh meter-override consumer side is in scope).
  - **BUG-011 / BUG-015 / BUG-R002 / BUG-R003** — should be Resolved.

  If any kickoff claim disagrees with KNOWN_ISSUES.md, the audit's first finding is the kickoff staleness.
- **Sub-scope decision is MANDATORY.** Total Presets/ scope is **15.2k LoC across ~46 files** (30 Swift + 17 `.metal` + 16 JSON sidecars + `.DS_Store` noise). The Swift slice alone is 3,129 LoC. The `.metal` slice alone is 12,065 LoC.

  **Recommended scope for this increment: Swift only (3,129 LoC / 30 files) + JSON sidecars as boundary-noted schema-verification reads (lightweight, 16 small files).** The `.metal` shaders are deferred to a separate increment (or to the existing per-preset M7 cert review process, which audits shader-level fidelity differently from a capability-registry sweep). Reasons:
  - Capability-registry methodology (verdicts per type/method) does not map cleanly to shader files (shaders are a single fragment function; the per-pixel work is the unit, not the function).
  - The shader-fidelity rules (4+ octaves, 3+ materials, pale-tone-share, reference-image-first) are the M7 cert rubric, which already audits each shader per-preset at a different cadence.
  - Including shaders would inflate the audit to 15k+ LoC — comparable to CA.7a + CA.7b combined.
  - The Swift slice is uniformly capability-registry-shaped (PresetLoader + PresetDescriptor + per-preset state classes + Certification cluster).

  **State the choice explicitly in the audit doc's §Scope section at Pass 0.** If the audit's depth-of-coverage requires a further split within the Swift slice (e.g., infrastructure vs per-preset state), state it; otherwise default to single increment for the Swift slice.

- **Exhaustive within scope.** Every public / internal type, every public / internal method in the chosen scope gets a verdict. Coverage is binary for the scope you commit to, not best-effort.
- **Stop-and-report criteria** (in addition to the standard `CLAUDE.md` set):
  - Found a `broken-but-claimed` finding that affects production behaviour right now (file as BUG-XXX entry; surface immediately — BUG-015 in CA.4 is the load-bearing precedent).
  - The audit's reading of `PresetLoader` or `PresetDescriptor` reveals a slot-binding regression on slot 6 / 7 / 8 (D-LM-buffer-slot-8, D-092/D-093/D-094) — drop everything and surface to Matt.
  - The audit's reading of `LumenPatternEngine` reveals a candidate explanation for BUG-016 — file an addendum to KNOWN_ISSUES.md BUG-016 with the candidate root cause and stop.
  - The audit's reading of `ArachneState`'s build pause guards reveals a regression of the spider-pause OR silent-state-pause invariants (Failed Approach #57 + BUG-011 round 8).
  - The audit's reading of `FidelityRubric` reveals the M7 cert criteria drift from `SHADER_CRAFT.md §12.1` enforcement.
  - The audit format is producing low-value output. Pause, redesign before continuing.

## Scope of CA-Presets

### Files in scope — Swift slice only (30 files, 3,129 LoC)

`PhospheneEngine/Sources/Presets/`:

**Top-level infrastructure (13 files, ~3,129 LoC):**

- `Presets.swift` (4) — Module marker.
- `PresetCategory.swift` (54) — Preset category enum (likely Energy / Mood / Ambient / etc. — verify).
- `PresetStage.swift` (56) — Build / cycle / stable / etc. stage enum (Arachne build state; verify generality).
- `PresetMaxDuration.swift` (121) — Per-section max-duration logic (the `.infinity` path for `waitForCompletionEvent: true` presets — BUG-011 round 8; the `naturalCycleSeconds` cap path for others).
- `PresetMetadata.swift` (156) — JSON sidecar schema (matches `SHADER_CRAFT.md §17`).
- `PresetDescriptor.swift` (556) — The load-bearing preset descriptor type. Carries name, family, passes, scene camera/lights, stem affinity, complexity_cost, certified, rubric_profile, waitForCompletionEvent flag (BUG-011 round 8), per CLAUDE.md §Preset Metadata Format.
- `PresetDescriptor+SceneUniforms.swift` (103) — Scene-uniform construction.
- `PresetLoader.swift` (786) — JSON + .metal compilation pipeline. Reads the sidecar, validates schema, compiles the shader against the preamble, returns a ready-to-bind pipeline state. Largest single file in scope.
- `PresetLoader+Mesh.swift` (149) — Mesh-shader path compilation (Fractal Tree, D-051).
- `PresetLoader+Preamble.swift` (478) — Common.metal preamble injection (D-099 / DM.2 byte-layout contract).
- `PresetLoader+Utilities.swift` (123) — Shared loader utilities.
- `PresetLoader+WarpPreamble.swift` (177) — mv_warp preamble injection (D-027).
- `SpectralCartographText.swift` (366) — Dedicated text-rendering state for SpectralCartograph diagnostic preset.

**Per-preset state cluster (12 files, ~1,500 LoC counting all Arachnid extensions):**

- `Arachnid/` (5 files): `ArachneState.swift` + `ArachneState+BackgroundWebs.swift` + `ArachneState+ListeningPose.swift` + `ArachneState+M7Diag.swift` + `ArachneState+Spider.swift`. Carries the BuildState machine (D-095 V.7.7C foreground-hero), the ArachneSpiderGPU 80-byte struct (D-094), the silent-state pause + spider-pause guards (BUG-011 round 8, Failed Approach #57), the listening-pose IK (CLAUDE.md `tip[8]` only contract), and the M7 diagnostic capture.
- `AuroraVeil/` (1 file): `AuroraVeilState.swift`. mv_warp accumulator pre-state, AV.1/AV.2 / AV.2.x iteration history.
- `FerrofluidOcean/` (3 files): `FerrofluidMesh.swift` + `FerrofluidParticles.swift` + `FerrofluidParticles+InitialPositions.swift`. Round 25-26 metadata-meter override consumer (BUG-013); Cassie-Baxter substrate physics; D-097 particle sibling conformer.
- `Gossamer/` (1 file): `GossamerState.swift`. Direct-fragment wave pool (slot 6 per D-092).
- `Lumen/` (2 files): `LumenPatternEngine.swift` + `LumenMosaicPaletteLibrary.swift`. LM.4.7 curated palette library (BUG-014 resolution; D-LM-palette-library); slot-8 fragment buffer (D-LM-buffer-slot-8). **BUG-016 surface lives here.**

**Certification cluster (5 files, ~300 LoC):**

- `Certification/FidelityRubric.swift` — M7 visual cert rubric primary.
- `Certification/FidelityRubric+Mandatory.swift` — `SHADER_CRAFT.md §12.1` mandatory gates (4+ octaves, 3+ materials, pale-tone-share, etc.).
- `Certification/FidelityRubric+Optional.swift` — Optional rubric extensions.
- `Certification/PresetCertificationStore.swift` — Cert-status persistence per preset.
- `Certification/RubricResult.swift` — Rubric evaluation result type.

**JSON sidecars in scope (16 files, schema-verification reads only):**

- `Shaders/{Arachne,AuroraVeil,FerrofluidOcean,FractalTree,GlassBrutalist,Gossamer,KineticSculpture,LumenMosaic,Membrane,Nebula,Plasma,SpectralCartograph,StagedSandbox,Starburst,VolumetricLithograph,Waveform}.json` — verify each sidecar parses against `PresetMetadata.swift` schema and that the declared `passes` list matches the rendered preset's actual dispatch path (cross-check with CA.7a render-pipeline branch chosen by passes-list).

### Boundary surfaces (in scope, with annotation)

- **Presets ↔ App.** Per-preset state classes are instantiated and owned by `VisualizerEngine` (per CA.5 line 364): `ArachneState`, `GossamerState`, `AuroraVeilState`, `LumenPatternEngine`, `FerrofluidParticles`, `FerrofluidMesh`. CA-Presets audits the type side; CA.5 audited the App-side construction + lifecycle. Verify the type API consumed by App matches the producer side (init signatures, public mutator methods, slot-bind closures).
- **Presets ↔ Renderer.** `PresetDescriptor.passes: [String]` selects the render-pipeline branch (`["ray_march"]` / `["staged"]` / `["mv_warp", "feedback_warp"]` / `["particles"]` / `["mesh"]`) per CA.7a. Verify the descriptor side declares passes that the renderer side can dispatch.
- **Presets ↔ Orchestrator.** `PresetDescriptor.stemAffinity`, `complexity_cost`, `family`, `rubric_profile`, `waitForCompletionEvent` are consumed by `DefaultPresetScorer` (Orchestrator, per CA.4) for scoring + plan construction. Verify producer side matches CA.4 consumer expectations.
- **Presets ↔ Shared.** `PresetDescriptor.SceneUniforms` (the GPU-bound scene camera/lights) flows through `Sources/Shared/AudioFeatures+SceneUniforms.swift`. Verify boundary.
- **Presets ↔ DSP.** No direct dependency expected; `PresetDescriptor` declares stem-affinity strings consumed by Orchestrator, not by DSP directly.

### Explicit exclusions (out of CA-Presets scope)

- **`PhospheneEngine/Sources/Presets/Shaders/*.metal` (17 files, 12,065 LoC).** Deferred to a separate increment. The shader-level capability check has different methodology (per-preset visual-fidelity rubric, not capability registry) and is already covered by the M7 cert review process per preset.
- **`PhospheneEngine/Sources/Presets/Shaders/ShaderUtilities.metal` (638 LoC).** Shared shader-utility file; same deferral as the per-preset .metal files. CA-Presets may note its presence but does not audit content.
- **`PhospheneEngine/Sources/Shared/`** — deferred (CA-Shared, recommended after CA-Presets).
- **All other engine modules** (`DSP/`, `ML/`, `Audio/`, `Session/`, `Orchestrator/`, `Renderer/`) — already audited.
- **`PhospheneApp/`** — already audited (CA.5 + CA.6).
- **`PhospheneEngine/Tests/`** — read freely for test discriminators, but audit verdicts apply to production code, not tests.

If something in the boundary surfaces seems important enough that the audit's value is reduced without it, note the gap and continue. Do not expand scope.

## Methodology

The methodology is the same as CA.1–CA-Audio with no new additions — the format is stable. One small refinement: the per-preset state classes are heavily extension-split (Arachnid has 5 files for one logical type), so consumer traces must enumerate the type's full surface across all extension files.

### Pass 0 — Kickoff cross-check

Before reading any source file:

- **BUG cross-check.** Verify every BUG cited in this kickoff against `docs/QUALITY/KNOWN_ISSUES.md`:
  - BUG-016 — should still be Open. **If Matt characterised the symptom further since the kickoff's draft, incorporate into Pass 1 LumenPatternEngine read.**
  - BUG-001 / BUG-005 / BUG-012 / BUG-013 — should still be Open (none Presets-affecting except BUG-013's FerrofluidMesh consumer + BUG-016's LumenPatternEngine producer).
  - BUG-011 / BUG-015 / BUG-R002 / BUG-R003 — should be Resolved.

  If any kickoff claim disagrees with KNOWN_ISSUES.md, the audit's first finding is the kickoff staleness.

- **Verify CA-Audio-FU-9 (Module Map Sync) status.** Filed 2026-05-21 as a planned increment. If CA-Presets discovers further Module Map drift in the Presets/ block (which is likely — 5-in-a-row pattern), bundle the Presets-block fixes into CA-Audio-FU-9's scope at landing time rather than fixing piecemeal in CA-Presets.

- **Verify pre-existing follow-ups.** CA-Audio-FU-1 resolved; FU-2 + FU-3 resolved 2026-05-21 (LookaheadBuffer + MusicKitFetcher kept by Matt's product call); FU-4 (tap-reinstall tests) + FU-5 (InputLevelMonitor tests) + FU-6 (printHistogram retirement) + FU-7 (MoodClassifying docstring tightening) + FU-8 (RUNBOOK Spotify disambiguation) stay open (outside CA-Presets scope; do not address). CA.7-FU-1 + CA.7-FU-2 + CA.7b-FU-4 stay open (outside CA-Presets scope). If anything regressed, surface it.

- **State the sub-scope decision explicitly.** Default: Swift slice + JSON sidecar schema verification only (3,129 LoC / 30 + 16 = 46 files). Justify the choice. If the audit's depth requires a within-Swift-slice split (e.g., infrastructure vs per-preset state), state it.

### Pass 1 — Inventory + verdict assignment

For each file in scope, produce:

- **File summary** — one paragraph: what this file owns; the kind of work it does.
- **Public / internal surface** — every public / internal type and every public / internal method, with brief signatures.
- **Documented features** — comment headers, MARK sections, doc-comments. Quote verbatim where the claim matters.
- **Notable internal types / private members if load-bearing** (e.g., `@Published` properties, NSLock-guarded state, per-segment counters, build-state machine fields).
- **File-level constants / tuning values** with names and values.
- **Any code-level TODOs / FIXMEs / placeholder branches.**

**Read strategy:** At 3,129 LoC for the Swift slice, direct-read every file > 200 LoC (5 files: PresetLoader 786, PresetDescriptor 556, PresetLoader+Preamble 478, SpectralCartographText 366, PresetLoader+WarpPreamble 177 — actually 5 files at ≥ 176 LoC) and batch the rest across 1-2 parallel Explore agents. Per-preset state classes (Arachnid/AuroraVeil/FerrofluidOcean/Gossamer/Lumen) are best direct-read because the extension-split makes consumer-trace tricky for agents.

After each agent's report, run the visibility verification grep per file. Reconcile each agent-claimed `public` against the grep.

Then for each capability, trace consumers via grep:

```bash
grep -rn "TypeName" PhospheneApp PhospheneAppTests PhospheneEngine/Sources PhospheneEngine/Tests   # type usage
grep -rn "\.functionName(" …                                                                       # call sites
grep -rn ": ProtocolName" …                                                                        # conformances
```

For types referenced only in tests: note as test-only (different verdict than production).

Record per capability: production consumers, test consumers, no consumers. For any production-orphan candidate, the cited grep command + result count is mandatory. Apply the CA.7b non-nil-caller refinement to setter / mutator APIs.

**Cross-reference each capability against the load-bearing docs.** Record: claimed in docs (yes/no, citations), doc claim aligned with code (yes/no, divergence noted), documented as planned-but-not-built (yes/no).

**Behaviour validation — key test discriminators by domain:**

- Preset loader: `PresetLoaderTests` (compilation pipeline + sidecar parsing); `PresetMetadataTests` (schema invariants); `PresetDescriptorTests` (descriptor invariants).
- Per-preset state: per-preset test files (`ArachneState*Tests`, `GossamerStateTests`, `AuroraVeil*Tests`, `LumenPatternEngineTests`, `FerrofluidParticlesTests`, `FerrofluidMeshTests` — verify presence). The Arachne cluster especially has many M7-diag + build-pause + spider-pause regression tests.
- Certification: `FidelityRubricTests`, `PresetCertificationStoreTests`, `RubricResultTests` (verify presence).
- Cross-preset: `PresetRegressionTests` (golden-hash regression per preset — load-bearing for D-099 / DM.2 Common.metal extension byte-layout invariant); `PresetAcceptanceTests` (per-preset beat ≤ 2× continuous rule per CLAUDE.md Audio Data Hierarchy); `PresetVisualReviewTests` (env-gated visual harness output, `RENDER_VISUAL=1`).

Use them as the discriminators they are.

**Assign verdict per capability** (definitions carried forward from CA.7b + CA-Audio):

| Verdict | Meaning |
|---|---|
| `production-active` | Consumed by production code; doc claims match code behavior; behavior validated. |
| `production-orphan` | Consumed nowhere in production code (test consumers only OR no consumers). Requires cited grep. Also applies to setter APIs with only nil-reset callers (CA.7b refinement). |
| `production-orphan` + `planned-consumer` (kept-by-design) | As above, but Matt's product call has been made to keep for a specific future planned consumer. Pattern from CA.7-FU-3 (ICB) + CA.7b-FU-3 (RayTracing) + CA-Audio-FU-2/FU-3 (LookaheadBuffer + MusicKitFetcher). |
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

- Does `ARCHITECTURE.md §Module Map Presets/` block (verify line range) accurately list all 30 Swift files in scope? (CA-Audio confirmed the 5-in-a-row pattern; expect drift here too.)
- Does `ARCHITECTURE.md §Preset Metadata Format` describe the same JSON schema fields `PresetMetadata.swift` declares?
- Does `ARCHITECTURE.md §GPU Contract Details` correctly reserve slots 6/7/8 per D-LM-buffer-slot-8 + D-092/D-093/D-094 and match the per-preset state classes' flush-state buffer-bind calls?
- Are tuning constants quoted in docs identical to the code's values? (Arachne `spiralChordsPerBeat = 3.24` per BUG-011 round 8; `frameDurationSeconds = 2.775`; `radialDurationSeconds = 1.389`; Lumen LM.4.7 palette names; Ferrofluid `wave_period_s = 6 × 60 × beatsPerBar / bpm` Round 25-26.)
- Does any architectural claim describe a path that no longer exists? Was retired? Was renamed?
- Do any decisions in `DECISIONS.md` reference type names that have moved or been renamed?
- Does `CLAUDE.md §What NOT To Do` (the preset-author rules — many Failed Approaches map to specific per-preset state-class invariants) still match the current code?
- Does `SHADER_CRAFT.md §17` JSON sidecar schema match `PresetMetadata.swift`?

Record drift findings as a separate cross-reference section in the audit doc.

## Output structure (template — extends CA-Audio)

Output file: `docs/CAPABILITY_REGISTRY/PRESETS.md`.

```markdown
# Capability Registry — Presets Subsystem (Swift slice)

**Audit increment:** CA-Presets
**Date:** 2026-05-XX
**Auditor:** Claude (session-driven, read-only)
**Scope:** `PhospheneEngine/Sources/Presets/` Swift slice — 30 Swift files + 16 JSON sidecars (schema-verification reads). 3,129 Swift LoC.
**Methodology:** Phase CA scoping document (CA-Presets kickoff).
**Reads relied on:** [list]
**Sibling audits:** docs/CAPABILITY_REGISTRY/RENDERER.md (CA.7a — render-pipeline branch selection by passes list), docs/CAPABILITY_REGISTRY/RENDERER_SUPPORTING.md (CA.7b — D-097 particle-geometry siblings + ParticleGeometryRegistry), docs/CAPABILITY_REGISTRY/APP.md (CA.5 — per-preset state class App-side ownership), docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md (CA.4 — PresetDescriptor scoring consumption), docs/CAPABILITY_REGISTRY/AUDIO.md (CA-Audio — most-recent methodology + kept-by-design annotation pattern).

## Summary
[One paragraph: capability counts per verdict, top findings, follow-up count, kickoff-vs-KNOWN_ISSUES cross-check result.]
[Markdown table of verdict counts.]

## Sub-scope decision
[State the scope chosen at Pass 0 explicitly. Justify the choice. Default: Swift slice + JSON sidecar schema verification only; .metal shaders deferred.]

## Findings by verdict
[Per-finding citations as CA-Audio template.]

## Per-file capability index
[One section per file or per cluster. Consolidation allowed if verdicts heavily concentrate in production-active.]

## Verification of BUG-016 producer-side surface (CA-Presets-specific)
[Required section. Read LumenPatternEngine.swift + LumenMosaicPaletteLibrary.swift end-to-end. Trace init failure paths (LumenPatternEngine init can return nil per CA.5; verify why). Cross-reference against the 5 candidate failure modes in BUG-016 body. If a structural candidate root cause surfaces, file as addendum to KNOWN_ISSUES.md BUG-016 and STOP (per "Stop-and-report criteria"). Otherwise: characterise what the file does, what slot-8 binding looks like, and what would diagnostically distinguish each candidate.]

## Verification of D-094 ArachneSpiderGPU 80-byte invariant (CA-Presets-specific)
[Required section. Verify `ArachneSpiderGPU` struct definition in ArachneState+Spider.swift (or wherever it lives) is 80 bytes; verify the listening-pose path (CLAUDE.md §What NOT To Do: "tip[8] only" contract) does not add fields; verify the slot-7 buffer allocation in ArachneState.swift matches `MemoryLayout<ArachneSpiderGPU>.stride`.]

## Verification of D-095 V.7.7C foreground-hero architecture (CA-Presets-specific)
[Required section. Verify `webs[0]` Row 5 BuildState is the foreground-hero driver (CLAUDE.md §What NOT To Do: "If you find yourself making the foreground anchor block read webs[0].stage / webs[0].progress (Row 2) instead of Row 5 fields, stop — that's V.7.5 thinking"); verify V.7.5 pool render loop is bounded at `wi < 1` (empty body) for the foreground; verify per-chord gate `globalChordIdx < int(progress × N_RINGS × nSpk)` is in place (NOT per-ring `kVis = (k / N_RINGS) <= progress` which was Matt's 2026-05-08 smoke flag); verify spider trigger is `features.bassAttRel > 0.30` (NOT the retired `subBass + bassAttackRatio < 0.55`, Failed Approach #57).]

## Verification of BUG-011 round 8 build-pause + completion-gate invariants (CA-Presets-specific)
[Required section. Verify `ArachneState`'s `spiderEnergySilenceThreshold = 0.02` silent-state pause path is intact; verify `pausedBySpider` from `spiderBlend > 0.01` is evaluated BEFORE silence-gate evaluation (CLAUDE.md §What NOT To Do: "set pausedBySpider from spiderBlend > 0.01 BEFORE evaluating the silence gate, otherwise the spider-pause regression test will trip on the silence gate without latching pausedBySpider"); verify `PresetDescriptor.waitForCompletionEvent: Bool` field exists + Arachne.json sets it true; verify `PresetMaxDuration.maxDuration(forSection:)` returns .infinity for flagged presets.]

## Verification of D-097 particle-geometry siblings invariant (CA-Presets-specific)
[Required section. Verify no per-preset state class instantiates or extends `ProceduralGeometry` outside the Murmuration sibling; verify Drift Motes-related files are absent post-D-102 (no DriftMotesState, no `motes_update` kernel, no DriftMotes.json/.metal); verify `ParticleGeometryRegistry.knownPresetNames = ["Murmuration"]` (per CA.7b).]

## Verification of D-099 / DM.2 Common.metal struct extension invariant (CA-Presets-specific)
[Required section. Verify `PresetLoader+Preamble.swift` injects Common.metal preamble in the same order it has always done; verify FeatureVector first 32 floats + StemFeatures first 16 floats are byte-identical (the engine-library kernels Murmuration's particle_update + MVWarp's vertex/fragment + feedback_warp_fragment read fields in this original tail). If any field is reordered, that's a regression — STOP and surface.]

## Verification of Drift Motes / D-102 retirement cleanliness (CA-Presets-specific)
[Required section. Verify no DriftMotes-related files exist in Sources/Presets/; verify no Drift Motes JSON sidecar; verify no Drift Motes references in PresetCategory / PresetMetadata; verify the FeatureVector / StemFeatures DM.2 extension fields (MV-1 / MV-3 per D-099) are still in place but currently unconsumed (kept for future engine-library kernels per D-099).]

## Verification of FidelityRubric ↔ SHADER_CRAFT.md §12.1 alignment (CA-Presets-specific)
[Required section. Verify FidelityRubric+Mandatory.swift enforces the §12.1 mandatory gates (4+ octaves on hero surfaces, 3+ distinct materials, pale-tone-share ≤ 0.30 per panel per D-LM-cream-rescission, no architecture deformation per Failed Approach #23). If §12.1 has gates the rubric does not enforce OR the rubric has gates not in §12.1, document the drift.]

## Verification of JSON sidecar schema (CA-Presets-specific)
[Required section. For each of 16 .json sidecars: confirm it parses against PresetMetadata.swift; confirm declared passes list matches a valid render-pipeline branch per CA.7a; confirm declared stemAffinity values match the orchestrator scorer's expected primitive set per CA.4. Brief table of (preset, parse-OK, passes-OK, stemAffinity-OK).]

## Verification of FerrofluidMesh meter-override consumer (BUG-013) (CA-Presets-specific)
[Required section. Verify the Round 25-26 meter-override consumer path in FerrofluidMesh.swift correctly consumes BeatGrid.beatsPerBar after the override (per CA.3 SessionPreparer side) and computes wave_period_s = 6 × 60 × beatsPerBar / bpm. If consumer wires correctly but BUG-013 still fires only because Soundcharts returns nil time_signature (the API limitation; not the parser, not the consumer), document this clearly so a future reader doesn't try to "fix" the consumer.]

## Cross-references
### Updates needed in CLAUDE.md
### Updates needed in ARCHITECTURE.md
### Updates needed in ENGINEERING_PLAN.md
### Updates needed in DECISIONS.md
### Updates needed in SHADER_CRAFT.md
### Updates needed in KNOWN_ISSUES.md (BUG-016 addendum if structural root cause surfaces)
### Updates needed across sibling audits (carry-forward corrections like CA.3 → CA-Audio TrackMetadata correction)

### New BUG entries
### KNOWN_ISSUES.md sweep

## Follow-up Backlog
| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA-Presets-FU-1** | … | … | … | … |
| **CA-Presets-FU-2** | … | … | … | … |
| **CA-Presets-FU-N** (if Module Map drift surfaces in Presets/ block, fold into CA-Audio-FU-9 rather than filing separately) | … | … | … | … |

## Approach validation
[Critique of methodology. What worked? What didn't? Recommended changes for CA-Shared (last remaining unaudited engine surface).]
```

## File the artifact + cross-references

Per `CLAUDE.md` increment closeout protocol:

- The audit document is the primary deliverable.
- Any `broken-but-claimed` findings get **BUG-XXX entries in KNOWN_ISSUES.md immediately**. The next available BUG number is **BUG-017** (no new BUG entries filed since BUG-016 on 2026-05-21, including across CA-Audio which produced zero new BUG entries).
- **BUG-016 addendum: if CA-Presets's LumenPatternEngine read surfaces a structural candidate root cause for the "not working" symptom**, file it as an addendum to BUG-016's existing body (not a new BUG number) — same shape as CA.4's BUG-015 discovery (which added detail to an existing-Open BUG body).
- `ENGINEERING_PLAN.md` gets an entry in Recently Completed (CA-Presets ✅) plus the CA-Presets row added (no row exists yet — write one).
- `CLAUDE.md` / `ARCHITECTURE.md` / `SHADER_CRAFT.md` drift findings are corrected in this same increment, **UNLESS the Module Map drift discovered is large enough to bundle into CA-Audio-FU-9** (the standalone Module Map sync increment filed 2026-05-21). If the Presets/ Module Map block is missing > 3 files, defer the Module Map fix to FU-9; if it's just a handful, fix in CA-Presets and note in FU-9 that Presets/ is now clean.

Commit shape (matches CA.1 / CA.2 / CA.3 / CA.4 / CA.5 / CA.6 / CA.7a / CA.7b / CA-Audio — two commits, doc-only):

- `[CA-Presets] Presets capability audit: registry + findings`
- `[CA-Presets] ARCHITECTURE.md / ENGINEERING_PLAN.md / CLAUDE.md / SHADER_CRAFT.md / KNOWN_ISSUES.md: doc-drift corrections from Presets audit (if any)`

## Done-when

CA-Presets closes when:

- [ ] `docs/CAPABILITY_REGISTRY/PRESETS.md` published.
- [ ] Sub-scope decision documented explicitly (default: Swift slice + JSON sidecar schema verification; `.metal` shaders deferred).
- [ ] Every public / internal capability in the chosen scope has a verdict.
- [ ] Every production-orphan verdict cites the grep command used.
- [ ] Every Explore-agent-claimed public / internal symbol was cross-checked against a visibility grep.
- [ ] Non-nil-caller production-orphan check (CA.7b refinement) applied to every setter / mutator API on per-preset state classes in scope.
- [ ] Kickoff-vs-KNOWN_ISSUES.md cross-check ran as Pass 0 step 1.
- [ ] Every non-production-active finding either ships a doc-fix in this increment OR is registered as a CA-Presets-FU-N follow-up.
- [ ] All `broken-but-claimed` findings have BUG entries in KNOWN_ISSUES.md (or BUG-016 addenda).
- [ ] BUG-016 producer-side characterised (LumenPatternEngine init failure paths traced; candidate failure modes mapped to code; if a structural candidate surfaced, BUG-016 body extended).
- [ ] D-094 ArachneSpiderGPU 80-byte invariant verified.
- [ ] D-095 V.7.7C foreground-hero invariants verified (webs[0] Row 5 fields; spider trigger primitive; per-chord gate; V.7.5 pool retirement).
- [ ] BUG-011 round 8 build-pause + completion-gate invariants verified.
- [ ] D-097 particle-geometry siblings invariant verified (no ProceduralGeometry parameterisation; Drift Motes absent).
- [ ] D-099 / DM.2 Common.metal struct extension invariant verified (first 32 + 16 floats byte-identical).
- [ ] FidelityRubric ↔ SHADER_CRAFT.md §12.1 alignment verified.
- [ ] JSON sidecar schema verified for all 16 sidecars.
- [ ] FerrofluidMesh BUG-013 meter-override consumer characterised.
- [ ] Drift corrections to load-bearing docs landed (OR Module Map drift folded into CA-Audio-FU-9).
- [ ] "Approach validation" section produces an honest critique of whether this format should continue into CA-Shared.
- [ ] All commits land on `main` (local). Push only on Matt's explicit approval.

## After CA-Presets lands

Surface to Matt:

- The audit summary (broken-but-claimed count, documented-but-missing count, production-orphan count, follow-up count).
- The verdict on BUG-016 producer-side surface (structural candidate root cause if any; characterised candidates if not).
- The verdict on the 7 invariants verified (D-094 / D-095 / BUG-011 round 8 / D-097 / D-099 / FidelityRubric / FerrofluidMesh).
- Any new CA-Presets-FU items registered.
- Whether the Presets/ Module Map block drift was bundled into CA-Audio-FU-9 or fixed in CA-Presets.
- The recommended next subsystem — **CA-Shared** (`Sources/Shared/` — the last remaining unaudited engine surface; smallest natural next pass; expected smaller than CA-Audio's 16 files based on the existing module structure). OR: **CA-Audio-FU-9 (Module Map Sync)** if the cumulative drift across all 9 closed audits warrants prioritisation. OR: a `.metal` shader audit increment (formally `CA-Preset-Shaders` or aligned to the existing M7 cert review process).

Do not start CA-Shared or the shader audit in the same session.

## Failure modes to watch for

Specifically for Presets-shaped audit work:

- **Treating per-preset state classes as a uniform set.** They aren't. Arachne (5 files, build-state machine, spider GPU struct, listening pose, M7 diag) is fundamentally different from Gossamer (1 file, wave pool) which is fundamentally different from LumenPatternEngine (palette library + pattern engine). The audit must respect the per-preset specificity — don't apply Arachne-shaped reasoning to AuroraVeil and vice versa.
- **Forgetting that the per-preset state classes are owned by App, not by Presets.** Per-preset state classes live in `PhospheneEngine/Sources/Presets/` (engine module = the types) but are instantiated + owned by `VisualizerEngine` (App = the lifecycle). CA-Presets audits the TYPE side; CA.5 already audited the App-side ownership. Don't re-audit App ownership — read CA.5's APP.md and cite.
- **Reading Arachne.metal to verify ArachneState invariants.** The shader is out of scope. ArachneState invariants live in the Swift state class + the GPU struct definitions. The shader CONSUMES the state at the GPU side — verifying that consumption is the cross-boundary check, not the Swift state-class audit.
- **Missing the JSON sidecar consumer chain.** Each `.json` is read at runtime by `PresetLoader` → parsed against `PresetMetadata.swift` → consumed downstream by Orchestrator (`PresetDescriptor` scoring per CA.4) + Renderer (passes-list dispatch per CA.7a). The audit must verify the consumer chain end-to-end for at least one preset of each type (ray_march / staged / mv_warp / particles / mesh / direct_fragment).
- **BUG-016 fishing.** The audit's purpose is to verify the LumenPatternEngine PRODUCER side and characterise candidate failure modes. It is NOT to diagnose BUG-016 — diagnosis requires Matt's reproduction. If a structural candidate root cause surfaces from reading the code, file as addendum to BUG-016. If not, surface the candidate failure modes mapped to code locations so the next diagnosis session has a clear starting point.
- **Citing without verifying.** Same as CA.1–CA-Audio's rule. Every claim is evidence-backed with a `file:line` or a `doc:line`.
- **Producing structure as a substitute for substance.** Headers must be backed by content. Empty buckets should be said-empty, not pretended-incomplete.
- **Scope creep into the `.metal` shaders.** `Sources/Presets/Shaders/*.metal` is out of scope. If a finding seems to require reading the shader, instead note "verifying X requires reading the shader; deferred to CA-Preset-Shaders / M7 cert review."
- **Scope creep into App ownership.** CA.5 audited per-preset state class App-side construction + lifecycle. CA-Presets reads those references but does not re-audit.

## Status on entry

Branch: `main`. CA.0 + CA.1 + CA.2 + CA.3 + CA.4 + CA.5 + CA.6 + CA.7a + CA.7b + CA-Audio + their follow-ups (CA.7-FU-3 keep + CA.7-FU-4 retire + CA.7b-FU-3 keep + CA-Audio-FU-1 resolved-in-audit + CA-Audio-FU-2 keep + CA-Audio-FU-3 keep + CA-Audio-FU-9 filed) all landed on `main` as of 2026-05-21. Recent commits (most-recent first):

```
<CA-Presets kickoff commit (this doc)>
<CA-Audio-FU-2 + CA-Audio-FU-3 keep + CA-Audio-FU-9 file resolution commit>
e81d8968  [CA-Audio] ARCHITECTURE.md + SESSION.md + ENGINEERING_PLAN.md: doc-drift corrections from Audio audit
0d66eecf  [CA-Audio] Audio capability audit: registry + findings
096e5ec0  [CA.7b-FU-3 + CA-Audio] mark RayTracing kept + Audio audit kickoff
56da19cd  [CA.7b] ARCHITECTURE.md + ENGINEERING_PLAN.md: doc-drift corrections from supporting-modules audit
19022515  [CA.7b] Renderer supporting audit: capability registry + findings
…
```

Local + remote: local `main` ahead of `origin/main` by the 2 CA-Audio commits + this kickoff's commits as of session start. Working tree clean apart from the documented `default.profraw` build artifact.

SwiftLint baseline: 0 violations across 371 files. Any violation in active source paths is a regression per `project_swiftlint_baseline.md` memory note. CA-Presets should remain at 0.

Test counts: Engine 1,248 tests / 162 suites all passing as of CA.7-FU-4 close. App 328 tests / 60 suites all passing. CA-Audio did not change either count.

Pre-existing flakes continue per the [dev-2026-05-21-c/d/e] chip baselines:
- Engine-side: `MetadataPreFetcher.fetch_networkTimeout` (env-dependent — CA-Audio-internal flake), `SoakTestHarness.cancel`, `MemoryReporter.residentBytes` (env-dependent, isIntermittent: true).
- App-side: timing margins widened per U.10 / U.11.

None are Presets-internal; CA-Presets should not encounter them.

Open follow-ups carried in (out of CA-Presets scope; do not address):
- CA.7-FU-1 — Tighten AuroraVeilMVWarpAccumulationTest to call RenderPipeline.drawWithMVWarp(...) directly. Marginal; low-priority.
- CA.7-FU-2 — Remove dead RayMarchPipeline.depthDebugEnabled / runDepthDebugPass / depthDebugPipeline cluster. Mechanical cleanup; small.
- CA.7b-FU-4 — setMeshPresetBuffer / setMeshPresetFragmentBuffer zero-non-nil-caller cleanup (latent slot-1 collision). Low-priority; CA.7a-scope.
- CA-Audio-FU-4 — Add AudioInputRouter+SignalState tap-reinstall tests.
- CA-Audio-FU-5 — Add InputLevelMonitor tests.
- CA-Audio-FU-6 — Retire FFTProcessor.printHistogram.
- CA-Audio-FU-7 — Tighten MoodClassifying docstring.
- CA-Audio-FU-8 — RUNBOOK Spotify connector disambiguation.
- CA-Audio-FU-9 — **Module Map Sync (cross-cutting)**. If CA-Presets discovers further Module Map drift in the Presets/ block, bundle into FU-9's scope at landing time.

BUG-012 is Open. BUG-012-i1 instrumentation in place across 8 files; none in CA-Presets scope.
BUG-011 is Closed against drops-only criteria. Round 8 build-pause + completion-gate invariants ARE in CA-Presets scope (verification, not fix).
BUG-016 is Open. Lumen Mosaic symptom uncharacterised. **CA-Presets is the producer-side audit; characterisation expected from this increment.**
BUG-005 / BUG-013 carried over from CA-Audio — BUG-005 out of scope (Session); BUG-013 consumer side (FerrofluidMesh meter override) in scope.
BUG-001 is Open. DSP defect; not Presets-affecting.

No CA-Presets code or audit has landed. This is the kickoff.

## Sign-off

This prompt is the canonical entry point for **Increment CA-Presets**. The Phase CA wider scoping (what subsystem comes next after CA-Presets — `CA-Shared` for the smallest natural next pass, or `CA-Audio-FU-9` Module Map Sync if cumulative drift warrants prioritisation, or a `.metal` shader audit) continues to be one-increment-at-a-time per the CA.0 scoping decision.

If you find the prompt is wrong or stale during the audit, update the prompt before continuing — do not work against a brief you know to be incorrect.

— Matt + Claude (2026-05-21 design session, post-CA-Audio closeout + CA-Audio-FU-2/FU-3/FU-9 resolutions)
