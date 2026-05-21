# Phase CA Kickoff — Capability Audit — Increment CA.7b (Renderer — supporting modules)

Hand this to a new Claude Code session verbatim. Do not summarise.

## What this phase is

Phase CA — Capability Audit is a multi-increment archaeology of Phosphene's codebase. Each increment audits one subsystem: reads the actual source, traces consumers and producers, cross-references against CLAUDE.md / docs/ARCHITECTURE.md / docs/QUALITY/KNOWN_ISSUES.md / docs/DECISIONS.md, and assigns a health verdict to every capability the subsystem exposes.

Prior increments (all closed; deliverables live in `docs/CAPABILITY_REGISTRY/`):

- **CA.1 (DSP / MIR)** closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/DSP_MIR.md`. 22 files. Surfaced one runtime production-orphan cluster (later superseded by BUG-015 fix).
- **CA.2 (ML)** closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/ML.md`. 16 files / 4,507 LoC. Methodology refinement: pre-grep visibility verification.
- **CA.3 (Session)** closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/SESSION.md`. 22 files / ~3,425 LoC. Methodology refinement: cross-check kickoff prompt against KNOWN_ISSUES.md as Pass 0.
- **CA.4 (Orchestrator)** closed 2026-05-20 at `docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md`. 14 files / ~2,950 LoC. Surfaced load-bearing broken-but-claimed BUG-015 — `applyLiveUpdate(...)` had zero production call sites; the entire Phase 4.5/4.6 live-adaptation pipeline was dead in production. BUG-015 fixed 2026-05-21.
- **CA.5 (App-layer engine-adapter slice)** closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/APP.md`. 49 files / 7,975 LoC. Verified BUG-015 wire shape clean (10 byte-level confirmations); BUG-012-i1 instrumentation intact.
- **CA.6 (App-layer Views + ViewModels presentation slice)** closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/APP_VIEWS.md`. 59 files / 8,285 LoC. Verified PlaybackChromeViewModel BUG-015 / D-091 consumer chain clean; DASH.7 view-side surface clean against D-088 / D-089.
- **CA.7a (Renderer — core pipeline)** closed 2026-05-21 at `docs/CAPABILITY_REGISTRY/RENDERER.md`. 23 files / 5,413 LoC. All five required verifications clean (GPU contract slots, D-059 algorithm, FrameBudgetManager governor, mv_warp dispatch path, Failed Approach #66 test/prod parity). Two follow-ups resolved same-day under Matt's product call: CA.7-FU-3 (keep ICB — registry-only) + CA.7-FU-4 (retire `setRayMarchPresetComputeDispatch` — code removed across 4 files). Two follow-ups remain open: CA.7-FU-1 (mv_warp test reachability tightening — marginal); CA.7-FU-2 (depth-debug pass dead-code removal — mechanical).

The App layer + DSP / ML / Session / Orchestrator are now fully closed. The Renderer is half-closed: CA.7a covered the core dispatch path; **CA.7b** closes the supporting modules (Dashboard / Geometry / RayTracing). After CA.7b, the only remaining unaudited engine modules are `Sources/Audio/` (CA-Audio later) and `Sources/Presets/` per-preset state classes (CA-Presets later).

This kickoff is for **Increment CA.7b**: the Renderer supporting modules under `PhospheneEngine/Sources/Renderer/`.

## Why CA.7b next

Four reasons, in priority order:

1. **CA.7 split commitment.** CA.7a closed by writing CA.7b as the natural next increment. The Renderer subsystem is the load-bearing engine module; leaving it half-audited makes "which Renderer file is canonical" ambiguous. CA.7b finishes the job. Closing CA.7 fully unblocks the audit's framing in ENGINEERING_PLAN.md to advance the "engine fully audited modulo Audio + Presets" state.
2. **CA.7b closes the DASH.7 producer side, which CA.6 only audited from the consumer side.** CA.6 verified the View-side (DashboardOverlayView + DashboardCardView + DashboardRowView + DashboardOverlayViewModel) against D-088 / D-089 with 16 line-anchored confirmations. The producer-side (`BeatCardBuilder`, `StemsCardBuilder`, `PerfCardBuilder`, `DashboardCardLayout`, `DashboardSnapshot`, `DashboardFontLoader`, `StemEnergyHistory`, `PerfSnapshot`) — every per-frame card layout the View consumes — lives in `Renderer/Dashboard/`. CA.6 noted DASH.7 as "view-side clean against D-088 / D-089"; CA.7b closes the producer-side.
3. **Geometry/ is the home of the D-097 particle-geometry siblings-not-subclasses architecture.** `ParticleGeometry` protocol + `ParticleGeometryRegistry` catalog + `ProceduralGeometry` (Murmuration's sole conformer post-Drift Motes retirement at D-102) + `MeshGenerator` (vertex vs hardware-mesh-shader fallback on the Apple silicon family gate per D-051 + the slot-4 mesh-shader path reuse CA.7a flagged). The renderer's compute-particle + mesh-shader subsystem is here. Any future particle preset (Drift Motes was retired; nothing is in flight today) ships a new `ParticleGeometry` conformer here. The audit verifies the protocol surface matches D-097 + tracks whether the current `ProceduralGeometry` implementation still cleanly conforms.
4. **RayTracing/ is the renderer's hardware ray-tracing surface that the catalog may not be exercising.** `BVHBuilder` + `RayIntersector` + `RayIntersector+Internal` total 748 LoC and CLAUDE.md does not mention them. ARCHITECTURE.md §Renderer doesn't reference them either. The audit's job is to determine: (a) which preset(s) consume them; (b) whether they're test-active or production-active; (c) whether they represent dead-code candidates similar to CA.7a's `depthDebugEnabled` finding, or whether they're a planned-but-not-yet-shipped surface like the ICB cluster. **This is the most likely place to surface a new finding.**

## Read these first, before doing anything else

1. **`CLAUDE.md`** — the entire file. Especially: §GPU Contract Details (slot 4 mesh-shader path reuse note added by CA.7a), §What NOT To Do (the rule about not parameterising `ProceduralGeometry` to host a non-Murmuration particle preset — D-097), Failed Approach #58 (Drift Motes retirement — the original consumer of `ProceduralGeometry`'s sibling conformer slot).
2. **`docs/CAPABILITY_REGISTRY/RENDERER.md`** — CA.7a audit (the load-bearing context for CA.7b). Read especially:
   - §Per-file capability index — the row references to `MeshGenerator`, `ProceduralGeometry`, `ParticleGeometry` are scoped to "CA.7b will close this"; CA.7b verifies the current state.
   - §Verification of GPU Contract slot reservations — slot 4 mesh-shader path reuse note added; CA.7b verifies the mesh-shader binding code in `Geometry/MeshGenerator.swift`.
   - §Follow-up Backlog — CA.7-FU-1 (mv_warp test reachability) + CA.7-FU-2 (depth-debug dead-code removal) are open and outside CA.7b scope; do not address.
3. **`docs/CAPABILITY_REGISTRY/APP_VIEWS.md`** — CA.6 audit. Read §DASH.7 dashboard surface verification — the 16 line-anchored confirmations against D-088 / D-089. CA.7b closes the producer-side counterparts: each card type the View renders has a Builder in `Renderer/Dashboard/`.
4. **`docs/CAPABILITY_REGISTRY/APP.md`** — CA.5 audit. Read §Boundary-noted "App ↔ Renderer" — the producer side of every Renderer attach API. `VisualizerEngine+Dashboard.swift` (the per-frame `publishDashboardSnapshot(stems:)` pump) is the App-side consumer of `Renderer/Dashboard/`'s output.
5. **`docs/QUALITY/KNOWN_ISSUES.md`** — every Open entry. Especially:
   - BUG-016 (Lumen Mosaic — Open; CA.7a noted slot-8 binding contract is clean from the renderer side; CA.7b may add observations on the dashboard-render side if any of the BeatCard / StemsCard / PerfCard builders touch Lumen state — unlikely but worth checking).
   - Pre-existing Flakes section — none should be CA.7b-internal.
6. **`docs/ARCHITECTURE.md`** — sections §Renderer (extended in CA.7a; lines 134-184), §Module Map Renderer/ block (extended in CA.7a with the 7 missing core-pipeline files; CA.7b verifies the Dashboard/ + Geometry/ + RayTracing/ subdirectories are still listed correctly), §GPU Contract Details (CA.7a-extended; verify Geometry/MeshGenerator binds the documented slots).
7. **`docs/DECISIONS.md`** — grep for D-051 (mesh shader architecture — vertex fallback on M1/M2), D-097 (particle geometry siblings-not-subclasses), D-099 (DM.2 engine MSL struct extension pattern — Common.metal additive struct extensions; verify any ParticleGeometry storage layout aligns), D-087 (DASH.7 producer types — read this section thoroughly; it's the load-bearing decision for the Dashboard/ subdirectory).
8. **`docs/ENGINEERING_PLAN.md`** — search for "DASH.7" (the dashboard increments), "Increment 3.18 mesh shader" or similar (MeshGenerator history), "D-097" / "Drift Motes" / "DM." (particle geometry context).
9. **`docs/RUNBOOK.md`** — search for "G-buffer" / "debug overlay" — anything mentioning RayTracing's `BVHBuilder` would be a red flag pointing to a runtime path; expected to be absent.

If any of these files do not exist, record the missing reference as a finding and continue with what does exist.

## Hard rules for this phase

- **No code changes during the audit.** Findings are documented; fixes are separate increments scheduled after the audit publishes. The only file modifications allowed in CA.7b are the new audit document and minor corrections to load-bearing docs (ARCHITECTURE.md / ENGINEERING_PLAN.md / KNOWN_ISSUES.md / CLAUDE.md) that the audit surfaces as drift.
- **BUG-012-i1 instrumentation files remain read-only.** The instrumented file in scope of the Renderer module (`MLDispatchScheduler.swift`) is in CA.7a, not CA.7b. CA.7b's scope does not intersect any instrumented file by current accounting, but verify before editing.
- **Evidence-based: every claim cites a file and line.** "X exists at path/file.swift:NNN" or "X is referenced but file does not exist." No claims unverified by inspection of the actual source.
- **`production-orphan` verdicts require a cited grep** (carried forward from CA.2). "X has zero consumers" must be backed by the exact grep command run and a summary of its results. The grep should cover `PhospheneApp/`, `PhospheneEngine/Sources/`, `PhospheneEngine/Tests/`, and `PhospheneAppTests/`. Production-orphan claims without a cited grep will be rejected at closeout.
- **Pre-grep visibility verification** (carried forward from CA.3 + CA.5 + CA.6 + CA.7a). When parallelising file reads via Explore agents, do not trust an agent's "this type is public" / "this method is internal" reports without cross-checking. After receiving each agent's report, run a single visibility grep per file:
  ```
  grep -nE "^public|^[[:space:]]+public|^internal|^[[:space:]]+internal" PhospheneEngine/Sources/Renderer/<subdir>/<file>.swift
  ```
  Reconcile each agent-claimed `public` against the grep.
- **Cross-check the kickoff prompt against KNOWN_ISSUES.md as Pass 0** (carried forward). Verify every BUG cited in this kickoff against actual status:
  - **BUG-001** — should still be Open (DSP defect; not Renderer-affecting).
  - **BUG-011** — should still be Closed against drops-only criteria.
  - **BUG-012** — should still be Open (instrumentation in place; CA.7b does not touch instrumented files).
  - **BUG-013** — should still be Open.
  - **BUG-016** — should still be Open (Lumen Mosaic; CA.7b may add Dashboard-side observations).
  If any kickoff claim disagrees with KNOWN_ISSUES.md, the audit's first finding is the kickoff staleness.
- **Sub-scope decision is NOT mandatory at this size.** 15 files / 2,241 LoC fits a single increment comfortably. CA.7a went into option (b) split because it was 5,400 LoC; CA.7b doesn't need the same split. State the choice explicitly in the audit doc's §Scope section before Pass 1 begins.
- **Exhaustive within scope.** Every `public` / `internal` type, every `public` / `internal` method in the chosen scope gets a verdict. Coverage is binary for the scope you commit to, not best-effort.
- **Stop-and-report criteria** (in addition to the standard CLAUDE.md set):
  - Found a `broken-but-claimed` finding that affects production behaviour right now (file as `BUG-XXX` entry; surface immediately — BUG-015 in CA.4 is the load-bearing precedent).
  - The audit's reading of `Geometry/MeshGenerator` reveals a vertex-vs-mesh-shader dispatch that drifts from the D-051 spec (M1/M2 vertex fallback; M3+ hardware mesh).
  - The audit's reading of `Geometry/ProceduralGeometry` reveals it has been parameterised to host a non-Murmuration particle preset (CLAUDE.md §What NOT To Do explicitly bans this per D-097).
  - The audit's reading of `Geometry/ParticleGeometry` or `Geometry/ParticleGeometryRegistry` reveals a stub conformer for a retired preset still wired in production.
  - The audit's reading of `RayTracing/` reveals it has a production consumer none of the docs mention.
  - The audit reveals a flake-class regression beyond the U.10 / U.11 pre-existing set.
  - The audit format is producing low-value output. Pause, redesign before continuing.

## Scope of CA.7b

### Files in scope (15 files, 2,241 LoC)

**`Renderer/Dashboard/` (8 files, 766 LoC) — DASH.7 producer side:**
- `BeatCardBuilder.swift` (156) — Builds the BEAT card's typographic rows from the per-frame BeatGrid / SpectralCartograph mode label / FFT-bin energy. Consumed by `DashboardOverlayViewModel` (CA.6 view-side audit).
- `StemsCardBuilder.swift` (57) — Builds the STEMS card (vocals / drums / bass / other timeseries sparklines). Consumed by `DashboardOverlayViewModel`.
- `PerfCardBuilder.swift` (131) — Builds the PERF card (FRAME / GPU / ML / QUALITY rows). Consumed by `DashboardOverlayViewModel`. Reads `PerfSnapshot` produced by `VisualizerEngine+Dashboard.assemblePerfSnapshot` per CA.5's audit.
- `DashboardCardLayout.swift` (116) — Value type with the row variants (`.singleValue` / `.bar` / `.progressBar` / `.timeseries`). The contract between Builder (writes) and View (reads).
- `DashboardSnapshot.swift` (39) — Value type with the three card layouts (BEAT / STEMS / PERF). The per-frame contract between Renderer (writes) and App (reads via `@Published dashboardSnapshot`).
- `DashboardFontLoader.swift` (151) — One-shot Clash Display Medium + Epilogue Medium custom-font resolution at app launch (per D-088). Returns the resolved fonts as a value-type to the App layer for binding to SwiftUI.
- `StemEnergyHistory.swift` (38) — Tiny value type wrapping a fixed-length ring buffer of stem-energy samples; consumed by `StemsCardBuilder`.
- `PerfSnapshot.swift` (78) — Value type carrying the per-frame perf data (frameMs / gpuMs / activeQualityLevel / mlPendingMs / etc.) from `VisualizerEngine+Dashboard.assemblePerfSnapshot` to `PerfCardBuilder`.

**`Renderer/Geometry/` (4 files, 727 LoC) — particle-geometry + mesh-shader subsystem:**
- `MeshGenerator.swift` (283) — Vertex-vs-mesh dispatcher. On Apple silicon family 8+ (M3+), uses `drawMeshThreadgroups` with `MTLMeshRenderPipelineDescriptor`. On M1/M2, falls back to `drawPrimitives` over a pre-generated vertex/index pair. D-051. Slot-4 mesh-shader path reuse per CA.7a finding (mutually exclusive with ray-march's SceneUniforms).
- `ParticleGeometry.swift` (79) — Protocol for per-preset particle compute+render pipelines (D-097). Three required members: `update(features:stemFeatures:commandBuffer:)`, `render(encoder:features:)`, `activeParticleFraction`. `AnyObject + Sendable`. Storage on `RenderPipeline.particleGeometry` typed as `(any ParticleGeometry)?`.
- `ParticleGeometryRegistry.swift` (32) — Catalog mapping `PresetDescriptor.name` → particle conformer factory. Mirrors the `VisualizerEngine.resolveParticleGeometry(forPresetName:)` resolution table. `ParticleDispatchRegistryTests` gates the catalog match.
- `ProceduralGeometry.swift` (333) — GPU compute particle system for Murmuration. UMA particle-state buffer + compute pipeline (update kernel) + render pipeline (point-sprite). `activeParticleFraction` scales the compute dispatch count for governor-level particle reduction. Conforms to `ParticleGeometry`. **Must NOT be parameterised to host a non-Murmuration preset** (D-097, CLAUDE.md §What NOT To Do). The only existing sibling conformer was Drift Motes (retired in D-102, 2026-05-11; code preserved in git history).

**`Renderer/RayTracing/` (3 files, 748 LoC) — hardware ray-tracing scaffold:**
- `BVHBuilder.swift` (269) — Bounding-volume hierarchy constructor over input geometry.
- `RayIntersector.swift` (378) — Ray-intersection dispatch via `MTLAccelerationStructure` / `MTLIntersectionFunctionTable`.
- `RayIntersector+Internal.swift` (101) — Internal-helper extension.

### Boundary surfaces (in scope, with annotation)

- **Dashboard ↔ App.** `DashboardSnapshot` is the per-frame contract between Renderer (writes via `BeatCardBuilder` / `StemsCardBuilder` / `PerfCardBuilder` orchestrated by `VisualizerEngine+Dashboard.publishDashboardSnapshot`) and App (reads via `@Published dashboardSnapshot` consumed by `DashboardOverlayViewModel`). CA.5 + CA.6 audited the App-side; CA.7b audits the producer side.
- **Geometry ↔ RenderPipeline.** `MeshGenerator` is consumed via `RenderPipeline.setMeshGenerator(_:)` (CA.7a-audited setter). `ParticleGeometry` conformers (just `ProceduralGeometry` today) are consumed via `RenderPipeline.setParticleGeometry(_:)` (CA.7a-audited).
- **Geometry ↔ App.** `ProceduralGeometry` is constructed inside `VisualizerEngine.resolveParticleGeometry(forPresetName:)` per CA.5. The `ParticleGeometryRegistry` catalog mirrors that resolution.
- **RayTracing ↔ ???.** This is the question CA.7b answers. If no production consumer exists, the audit reports it as production-orphan + boundary-noted.

### Explicit exclusions (out of CA.7b scope)

- CA.7a core-pipeline subdirectories (`RenderPipeline.*`, `RayMarchPipeline.*`, `FrameBudgetManager.swift`, `MLDispatchScheduler.swift`, `MetalContext.swift`, `IBLManager.swift`, `TextureManager.swift`, `PostProcessChain.swift`, `ShaderLibrary.swift`, `DynamicTextOverlay.swift`, `Protocols.swift`).
- `PhospheneEngine/Sources/Audio/` — CA-Audio (later).
- `PhospheneEngine/Sources/Presets/` per-preset Metal shaders + state classes — CA-Presets (later).
- `PhospheneEngine/Sources/Shared/` — deferred (CA-Shared eventually).
- `PhospheneEngine/Tests/` — read freely for test discriminators, but audit verdicts apply to production code, not tests.

If something in the boundary surfaces seems important enough that the audit's value is reduced without it, note the gap and continue. Do not expand scope.

## Methodology

The methodology is the same as CA.1-CA.7a with no new additions — the format is stable.

### Pass 0 — Kickoff cross-check

Before reading any source file:

1. **BUG cross-check.** Verify every BUG cited in this kickoff against `docs/QUALITY/KNOWN_ISSUES.md` (BUG-001, BUG-011, BUG-012, BUG-013, BUG-016). If any kickoff claim disagrees, file the disagreement as Finding #1.
2. **Verify pre-existing follow-ups.** CA.7-FU-1 + CA.7-FU-2 stay open (outside CA.7b scope; do not address). CA.7-FU-3 + CA.7-FU-4 closed 2026-05-21; nothing to carry forward. If anything regressed, surface it.
3. **State whether CA.7b is single-pass or splits.** Default: single increment. At 15 files / 2,241 LoC the methodology supports it cleanly.

### Pass 1 — Inventory + verdict assignment

For each file in scope, produce:

- **File summary** — one paragraph: what this file owns; the kind of work it does.
- **Public / internal surface** — every `public` / `internal` type and every `public` / `internal` method, with brief signatures.
- **Documented features** — comment headers, MARK sections, doc-comments. Quote verbatim where the claim matters.
- **Notable internal types / private members** if load-bearing (e.g., `@Published` properties, NSLock-guarded state, dispatch-queue ownership).
- **File-level constants / tuning values** with names and values.
- **Any code-level TODOs / FIXMEs / placeholder branches.**

**Read strategy:** At ~2,200 LoC for CA.7b, direct-read every file > 200 lines (3 files: `RayIntersector.swift` 378, `ProceduralGeometry.swift` 333, `MeshGenerator.swift` 283, `BVHBuilder.swift` 269) and batch the rest across 1-2 parallel Explore agents.

After each agent's report, run the visibility verification grep per file. Reconcile each agent-claimed public against the grep.

**Then for each capability, trace consumers via grep:**
- `grep -rn "TypeName" PhospheneApp PhospheneAppTests PhospheneEngine/Sources PhospheneEngine/Tests` — type usage.
- `grep -rn "\.functionName(" …` — call sites.
- `grep -rn ": ProtocolName" …` — conformances.

For types referenced only in tests: note as test-only (different verdict than production).

Record per capability: production consumers, test consumers, no consumers. For any production-orphan candidate, the cited grep command + result count is mandatory.

**Cross-reference each capability against the load-bearing docs.** Record: claimed in docs (yes/no, citations), doc claim aligned with code (yes/no, divergence noted), documented as planned-but-not-built (yes/no).

**Behaviour validation — key test discriminators by domain:**
- Dashboard: `PhospheneEngineTests/Renderer/Dashboard*Tests.swift` if any exist; `PhospheneAppTests/DashboardOverlayViewModelTests.swift` exercises the App-side consumer.
- Geometry: `MeshGeneratorTests.swift`, `ProceduralGeometryTests.swift`, `ParticleDispatchRegistryTests.swift` — the load-bearing D-097 catalog gate.
- RayTracing: any `BVHBuilder*Tests.swift` or `RayIntersector*Tests.swift` — likely the only consumer if there's no preset consumer.

Use them as the discriminators they are.

**Assign verdict per capability** (definitions carried forward from CA.7a):

| Verdict | Meaning |
|---|---|
| `production-active` | Consumed by production code; doc claims match code behavior; behavior validated. |
| `production-orphan` | Consumed nowhere in production code (test consumers only OR no consumers). Requires cited grep. |
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

- Does ARCHITECTURE.md §Module Map Renderer/ block (extended in CA.7a) accurately describe the current Dashboard/ / Geometry/ / RayTracing/ subdirectories?
- Are tuning constants quoted in docs identical to the code's values? (DashboardFontLoader font names + sizes; MeshGenerator threadgroup sizes; ProceduralGeometry particle count + drag coefficient; BVHBuilder leaf threshold; RayIntersector intersection-function-table layout.)
- Does any architectural claim describe a path that no longer exists? Was retired? Was renamed?
- Do any decisions in DECISIONS.md reference type names that have moved or been renamed?
- Does CLAUDE.md §What NOT To Do (D-097 ProceduralGeometry parameterisation ban) still match the current ProceduralGeometry code?

Record drift findings as a separate cross-reference section in the audit doc.

## Output structure (template — extends CA.7a)

**Output file:** `docs/CAPABILITY_REGISTRY/RENDERER_SUPPORTING.md` (separate file, NOT an extension of `RENDERER.md`). Rationale: keeping the two halves as separate files makes them mergeable later if Matt wants the unified Renderer audit doc; appending into `RENDERER.md` makes the doc the largest in the registry and harder to navigate.

```markdown
# Capability Registry — Renderer Subsystem (Supporting Modules)

**Audit increment:** CA.7b
**Date:** 2026-05-XX
**Auditor:** Claude (session-driven, read-only)
**Scope:** PhospheneEngine/Sources/Renderer/Dashboard/ + Geometry/ + RayTracing/ — 15 files / 2,241 LoC.
**Methodology:** Phase CA scoping document (CA.7b kickoff).
**Reads relied on:** [list]
**Sibling audit:** docs/CAPABILITY_REGISTRY/RENDERER.md (CA.7a core pipeline).

## Summary
[One paragraph: capability counts per verdict, top findings, follow-up count, kickoff-vs-KNOWN_ISSUES cross-check result.]

[Markdown table of verdict counts.]

## Sub-scope decision
[State the scope chosen at Pass 0 explicitly. Justify the choice. At 2.2k LoC the default is single-pass; commit to it or explain why a split is needed.]

## Findings by verdict
[Per-finding citations as CA.5 / CA.6 / CA.7a template.]

## Per-file capability index
[One section per file or per family. Consolidation allowed if verdicts heavily concentrate in production-active.]

## Verification of DASH.7 producer side (CA.7b-specific)
[Required section. Each BEAT / STEMS / PERF card type the View renders (CA.6 audited) has a Builder in Renderer/Dashboard/. Verify the Builder → DashboardCardLayout → DashboardSnapshot → @Published dashboardSnapshot → DashboardOverlayViewModel → DashboardOverlayView consumer chain is byte-identical to D-088 / D-089 + CA.6's 16 line-anchored confirmations. Per-builder verdict.]

## Verification of D-097 particle-geometry siblings-not-subclasses (CA.7b-specific)
[Required section. Verify ParticleGeometry protocol surface matches D-097 (three required members; AnyObject + Sendable; storage on RenderPipeline typed as `(any ParticleGeometry)?`). Verify ProceduralGeometry conforms cleanly and is NOT parameterised to host a non-Murmuration preset (CLAUDE.md §What NOT To Do). Verify ParticleGeometryRegistry catalog has Murmuration only (post-Drift Motes retirement at D-102). Verify ParticleDispatchRegistryTests is the catalog gate. Cite line-by-line.]

## Verification of MeshGenerator D-051 dispatch (CA.7b-specific)
[Required section. Verify the M3+ vs M1/M2 dispatch branch matches D-051 + ARCH §GPU Contract Details §Mesh Shader Architecture. Verify the slot-4 binding reuse documented by CA.7a (RenderPipeline+MeshDraw.swift:73 binds meshPresetFragmentBuffer at slot 4; ray-march's SceneUniforms at slot 4 is mutually exclusive). Verify densityMultiplier propagates correctly for governor-driven reduction (D-057).]

## Verification of RayTracing/ consumer surface (CA.7b-specific)
[Required section. The single most important verification of CA.7b. Determine: which preset (if any) in PhospheneEngine/Sources/Presets/ consumes BVHBuilder + RayIntersector; whether the consumers are production-active, test-only, or zero. Cite the grep commands + result counts. If zero production consumers, file as production-orphan + boundary-noted (analogous to CA.7a's ICB cluster); if dead, file as dead-code cleanup candidate. Either way: document the architectural intent (planned-but-not-built vs retired-but-not-removed).]

## Cross-references
### Updates needed in CLAUDE.md
### Updates needed in ARCHITECTURE.md
### Updates needed in ENGINEERING_PLAN.md
### Updates needed in DECISIONS.md
### New BUG entries
### KNOWN_ISSUES.md sweep

## Follow-up Backlog
| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA.7b-FU-1** | … | … | … | … |
| **CA.7b-FU-2** | … | … | … | … |

## Approach validation
[Critique of methodology. What worked? What didn't? Recommended changes for CA-Audio / CA-Presets.]
```

## File the artifact + cross-references

Per CLAUDE.md increment closeout protocol:

- The audit document is the primary deliverable.
- Any `broken-but-claimed` findings get `BUG-XXX` entries in `KNOWN_ISSUES.md` immediately. The next available BUG number is **BUG-017** (BUG-016 was filed 2026-05-21; nothing filed since, including across CA.7a closeout which produced zero new BUG entries).
- `ENGINEERING_PLAN.md` gets an entry in Recently Completed (CA.7b ✅) plus the CA.7b row flipped from "open" to "✅ landed".
- `CLAUDE.md` / `ARCHITECTURE.md` drift findings are corrected in this same increment.

**Commit shape** (matches CA.1 / CA.2 / CA.3 / CA.4 / CA.5 / CA.6 / CA.7a — two commits, doc-only):
- `[CA.7b] Renderer supporting audit: capability registry + findings`
- `[CA.7b] ARCHITECTURE.md / ENGINEERING_PLAN.md / CLAUDE.md: doc-drift corrections from supporting-modules audit (if any)`

## Done-when

CA.7b closes when:

- [ ] `docs/CAPABILITY_REGISTRY/RENDERER_SUPPORTING.md` published.
- [ ] Sub-scope decision documented explicitly (default: single increment).
- [ ] Every `public` / `internal` capability in the chosen scope has a verdict.
- [ ] Every `production-orphan` verdict cites the grep command used.
- [ ] Every Explore-agent-claimed `public` / `internal` symbol was cross-checked against a visibility grep.
- [ ] Kickoff-vs-KNOWN_ISSUES.md cross-check ran as Pass 0 step 1.
- [ ] Every non-`production-active` finding either ships a doc-fix in this increment OR is registered as a `CA.7b-FU-N` follow-up.
- [ ] All `broken-but-claimed` findings have BUG entries in `KNOWN_ISSUES.md`.
- [ ] DASH.7 producer-side verification produced byte-level confirmations matching D-088 / D-089 (and CA.6's view-side 16 line-anchored confirmations).
- [ ] D-097 particle-geometry siblings-not-subclasses verification produced confirmations against `ProceduralGeometry` + `ParticleGeometry` + `ParticleGeometryRegistry`.
- [ ] MeshGenerator D-051 dispatch verification produced confirmation against ARCH §GPU Contract Details §Mesh Shader Architecture.
- [ ] RayTracing consumer-surface verification answered the keep-or-retire question with cited evidence.
- [ ] Drift corrections to load-bearing docs landed.
- [ ] "Approach validation" section produces an honest critique of whether this format should continue into CA-Audio / CA-Presets.
- [ ] All commits land on `main` (local). Push only on Matt's explicit approval.

## After CA.7b lands

Surface to Matt:

- The audit summary (broken-but-claimed count, documented-but-missing count, production-orphan count, follow-up count).
- The verdict on the DASH.7 producer side — clean against D-088 / D-089 + CA.6 line-anchored confirmations, or drift found.
- The verdict on D-097 particle-geometry siblings — clean against the ProceduralGeometry parameterisation ban, or drift found.
- The verdict on MeshGenerator D-051 dispatch — match against ARCH §Mesh Shader Architecture, or drift found.
- The verdict on RayTracing — keep (planned consumer; analogous to CA.7-FU-3's ICB resolution) or retire.
- Any new `CA.7b-FU` items registered.
- The recommended next subsystem — **CA-Audio** (`PhospheneEngine/Sources/Audio/` — closes the CA.3 boundary-noted item) OR **CA-Presets** (per-preset state classes under `Sources/Presets/`).

Do not start CA-Audio or CA-Presets in the same session.

## Failure modes to watch for

Specifically for Renderer-supporting-shaped audit work:

- **Treating `BVHBuilder` / `RayIntersector` as a black box.** RayTracing is the most likely to surface a finding. The audit's job is to determine the actual consumer state, not to skip on "this looks like research scaffolding." If the grep confirms zero production consumers, that's a real finding worth filing (not a null result).
- **DASH.7 producer-side trivial-finding inflation.** Most of `Renderer/Dashboard/` will be `production-active` with little drama. The depth targets are: the Builder → CardLayout → Snapshot contract; the `DashboardFontLoader` font-name + size constants against D-088; the per-builder reads of `DashboardSnapshot` field accessors. Smaller files (`PerfSnapshot`, `StemEnergyHistory`, `DashboardSnapshot`) get surface-level `production-active` rows.
- **ProceduralGeometry D-097 verification.** The CLAUDE.md ban on parameterising `ProceduralGeometry` to host a non-Murmuration preset is one of the load-bearing architectural rules. Verify the current code respects it — no `presetName` / `presetKind` / `kernelNameOverride` / etc. fields. If you find one, that's a real finding (file as `broken-but-claimed` and / or `BUG-017`).
- **MeshGenerator + slot-4 mesh-shader path reuse.** CA.7a flagged the slot-4 reuse (meshPresetFragmentBuffer vs SceneUniforms) and added a note to ARCH §GPU Contract Details. Verify the MeshGenerator code respects the contract — specifically, that the mesh-shader path never tries to bind SceneUniforms at slot 4.
- **Citing without verifying.** Same as CA.1-CA.7a's rule. Every claim is evidence-backed with a `file:line` or a `doc:line`.
- **Producing structure as a substitute for substance.** Headers must be backed by content. Empty buckets should be said-empty, not pretended-incomplete.
- **Scope creep into CA-Audio / CA-Presets / CA.7a territory.** Geometry's `ProceduralGeometry` reads `FeatureVector` + `StemFeatures` from the analysis queue, but the producer side is Audio + DSP + ML (already audited). The per-preset state classes (`ArachneState`, etc.) live in `Sources/Presets/` — out of CA.7b scope; flag as `boundary-deferred` to CA-Presets.

## Status on entry

**Branch:** `main`. CA.0 + CA.1 + CA.2 + CA.3 + CA.4 + CA.5 + CA.6 + CA.7a + four CA.7a follow-ups (CA.7-FU-3 keep + CA.7-FU-4 retire + the two doc commits for both) all landed on `main` as of 2026-05-21. Recent commits (most-recent first, post-CA.7a closeout):

```
<CA.7b kickoff commit (this doc)>
d48a6778  [CA.7-FU-3 + CA.7-FU-4] RENDERER.md + ENGINEERING_PLAN.md: mark FU-3 (keep ICB) + FU-4 (retired) Resolved
8ac45e73  [CA.7-FU-4] Renderer: retire setRayMarchPresetComputeDispatch
c62584ec  [CA.7a] ARCHITECTURE.md + ENGINEERING_PLAN.md: doc-drift corrections from Renderer audit
b9612d22  [CA.7a] Renderer audit: capability registry + findings
93f2bc40  [CA.6-FU + CA.7] docs: close CA.5-FU-4 + update CA.7 row + ENGINEERING_PLAN CA.7 status to reflect kickoff doc landed
bf5dc4ac  [CA.7] Scoping: kickoff doc for Renderer capability audit
…
```

**Local + remote:** local `main` matches `origin/main` as of CA.7a + follow-up push 2026-05-21. Working tree clean apart from the documented `default.profraw` build artifact.

**SwiftLint baseline:** 0 violations across 371 files. Any violation in active source paths is a regression per `project_swiftlint_baseline.md` memory note. CA.7b should remain at 0.

**Test counts:** Engine 1,248 tests / 162 suites all passing as of CA.7-FU-4 close. App 328 tests / 60 suites all passing.

**Pre-existing flakes** continue per the `[dev-2026-05-21-c/d/e]` chip baselines: engine-side `MetadataPreFetcher.fetch_networkTimeout`, `SoakTestHarness.cancel`, `MemoryReporter` (env-dependent, isIntermittent: true); app-side timing margins widened per U.10 / U.11. None are Renderer-internal; CA.7b should not encounter them.

**Open follow-ups carried in from CA.7a** (out of CA.7b scope; do not address):

- **CA.7-FU-1** — Tighten `AuroraVeilMVWarpAccumulationTest` to call `RenderPipeline.drawWithMVWarp(...)` directly. Marginal; low-priority.
- **CA.7-FU-2** — Remove dead `RayMarchPipeline.depthDebugEnabled` / `runDepthDebugPass` / `depthDebugPipeline` cluster. Mechanical cleanup; small.

**BUG-012** is Open. BUG-012-i1 instrumentation in place across 8 files; none in CA.7b scope.

**BUG-011** is Closed against drops-only criteria. CA.7a's FrameBudgetManager governor verification confirmed the algorithm matches what the closure decision depended on; CA.7b does not re-litigate.

**BUG-016** is Open. Lumen Mosaic symptom uncharacterised. CA.7a verified the slot-8 binding contract is clean from the renderer side; CA.7b may add Dashboard-side observations if any of the BeatCard / StemsCard / PerfCard builders surface Lumen state.

**BUG-001** is Open. DSP defect; Renderer-side may have ancillary observations.

**BUG-013** is Open. Audio-side defect; not Renderer-affecting.

No CA.7b code or audit has landed. This is the kickoff.

## Sign-off

This prompt is the canonical entry point for **Increment CA.7b** (Renderer — supporting modules). The Phase CA wider scoping (what subsystem comes next after CA.7b — likely CA-Audio per the CA.7a closeout recommendation) continues to be one-increment-at-a-time per the CA.0 scoping decision.

If you find the prompt is wrong or stale during the audit, update the prompt before continuing — do not work against a brief you know to be incorrect.

— Matt + Claude (2026-05-21 design session, post-CA.7a closeout + CA.7-FU-3/4 sweep)
