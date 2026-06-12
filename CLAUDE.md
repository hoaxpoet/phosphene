# CLAUDE.md — Phosphene

## What This Is

Phosphene is a native macOS music visualization engine for Apple Silicon. Before the music starts, Phosphene connects to a playlist, downloads 30-second preview clips for every track, and runs full ML-powered stem separation and MIR analysis on each. By the time the user presses play, the AI Orchestrator has planned the entire visual session — which visualizer for each track, where transitions land, and what the emotional arc looks like across the playlist. During playback, real-time audio analysis via Core Audio taps (`AudioHardwareCreateProcessTap`) refines the pre-analyzed data, and the Orchestrator adapts its plan as the music unfolds.

Phosphene does not control playback — the user starts the music in their streaming app when Phosphene signals it is ready.

See `docs/PRODUCT_SPEC.md` for the full product definition, `docs/ARCHITECTURE.md` for system design, `docs/DECISIONS.md` for rationale behind key choices, `docs/RUNBOOK.md` for build/test/CI/troubleshooting, `docs/MILKDROP_ARCHITECTURE.md` for the research findings that drive the Phase MV (Musicality) work, `docs/UX_SPEC.md` for the user-facing product UX contract (state-to-view mapping, error taxonomy, onboarding), and `docs/SHADER_CRAFT.md` for the preset authoring handbook (detail cascade, material cookbook, per-preset uplift playbook) in `docs/ENGINEERING_PLAN.md`.

## Build & Test

```bash
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build
swift test --package-path PhospheneEngine
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test
swiftlint lint --strict --config .swiftlint.yml
```

Warnings-as-errors is enforced per-target via `PhospheneApp/Phosphene.xcconfig` — do NOT pass the flag on the command line (conflicts with SPM dependency `-suppress-warnings`).

Deployment target: macOS 14.0+ (Sonoma). Swift 6.0. Metal 3.1+.

All tests must pass before any new code is merged (regression gate).

## Increment Completion Protocol

Every increment — engine, preset, UX, docs, infrastructure — ends the same way. The protocol below is the standing rule. Skipping a step turns a finished increment into one that "looked finished in chat" and rots within a session or two.

**Closeout report.** At the end of every increment, produce a short report covering:

1. **Files changed** — concrete paths, grouped new vs. edited.
2. **Tests run** — run `Scripts/closeout_evidence.sh` and paste its evidence block verbatim. Prose may annotate anomalies below the block (e.g., known timing squeezes, parallel-session tree noise) but never replaces or summarizes it. A closeout without the block, or with a block whose commit hash does not match the closeout's commit, is incomplete.
3. **Visual harness output** — when the increment is preset-facing or otherwise visually observable, include the `RENDER_VISUAL=1` per-stage / contact-sheet output paths or attach key frames. State explicitly when a change is not visually verifiable.
4. **Documentation updates** — list every doc file touched.
5. **Capability registry updates** — see below; cite the rows changed.
6. **Engineering plan updates** — see below; cite the increment ID.
7. **Known risks and follow-ups** — bounded list of what could break, what was deferred, and what the next recommended increment is.
8. **Git status** — branch, commit hash(es), `git status` clean / dirty, files staged outside the increment's scope.

**Durable learnings stay in docs.** Anything a future session will need to know — a non-obvious tuning constant, a Failed Approach, a renderer convention, a preset-author rule — goes into `CLAUDE.md`, `docs/DECISIONS.md`, `docs/SHADER_CRAFT.md`, the relevant docs/ subtree, or memory. **Do not leave durable learnings only in chat.** If the only record of "we learned X" is a paragraph in this conversation, future Claude will not have it.

**`docs/ENGINEERING_PLAN.md` is mandatory to update.** Update it whenever an increment is **completed, split, renamed, deferred, or discovered to require prerequisite work**. Each increment ID should map to a row that says what done-when looks like and whether it's done. Plans drift fast — if the plan and the code disagree, treat that as a bug in the plan.

**`docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` is mandatory to update** whenever **renderer, visual harness, certification pipeline, shader infrastructure, or preset architecture capabilities change**. New capability → new row. Capability promoted Missing → Partial → Supported → flip the status and cite the files. New blocker discovered → add it. Preset implications section gets the same treatment: what's now buildable, what's still blocked. The registry is the load-bearing document for "can preset family X be built today" — let it drift and audit work doubles in cost.

**Commit locally to `main` after tests and docs are complete.** Use the standard commit message format (`[<increment-id>] <component>: <description>`). Prefer multiple small commits within an increment over one large commit — it makes `git bisect` useful.

**Do not push to the remote without Matt's explicit approval.** Local `main` commits stay local. `git push` requires "yes, push" in the chat. This applies even when the work is clearly green and clearly Matt's request — pushing remains a separate decision.

**Pruning pass — every tenth increment.** Every tenth increment (or every two weeks, whichever fires first), run a pruning pass against the doc set. The pass is its own increment with its own closeout report and does not require per-entry sign-off — borderline calls go through the standard "stop and report" rule below.

1. **Failed Approaches:** for each entry, ask "would this rule prevent a bug today?" If no, move to `docs/HISTORICAL_DEAD_ENDS.md`.
2. **Decisions:** for each entry whose increment has shipped and is no longer cited by another active decision, move to `docs/DECISIONS_HISTORY.md`.
3. **CLAUDE.md sections:** for each section, ask "did the last 10 increments need this?" If no, consider moving to a handbook (`docs/ARCHITECTURE.md`, `docs/SHADER_CRAFT.md`, `docs/UX_SPEC.md`, or `docs/RUNBOOK.md`).
4. **Current Status section:** trim to the last 10 increments; older entries are in `ENGINEERING_PLAN.md` and `git log` already.

Pruning has a counterweight role: the "Durable learnings stay in docs" rule above is the accumulation side; the pruning pass is the retirement side. Skipping the pruning side reproduces the doc-mass problem the 2026-05-13 refactor was set up to fix (see `docs/diagnostics/DOC-REFACTOR-PLAN-2026-05-13.md`).

**Stop and report instead of forging ahead** when:

- tests fail (engine or app), even pre-existing flakes that the increment touched;
- preset acceptance gates or rubric checks fail;
- implementing the increment as written would require broader architectural changes than were authorized — pause, surface the scope, get approval before expanding;
- documentation conflicts with code that just changed (e.g. CLAUDE.md describes an API that no longer exists) and resolving the conflict requires judgement calls outside the increment's scope;
- the commit would include unrelated files (`git status` shows changes outside the increment's stated scope) — back those changes out or surface them for approval before committing.

When in doubt, write a short status update and ask. The cost of pausing to confirm is low. The cost of an increment that silently expanded scope, partially landed, or quietly skipped a doc update is high.

---

## Defect Handling Protocol

See `docs/QUALITY/DEFECT_TAXONOMY.md` for full severity definitions, domain tags, and failure classes. See `docs/QUALITY/BUG_REPORT_TEMPLATE.md` for the required report structure. See `docs/QUALITY/KNOWN_ISSUES.md` for the active issue tracker.

**Evidence before implementation (P0/P1/P2).** Do not modify code in response to a reported P0, P1, or P2 defect until the following are documented:

1. **Expected behavior** — observable output described in concrete terms (values, units, state names). Not implementation internals.
2. **Actual behavior** — what actually happens, with observed values. Include frequency if intermittent.
3. **Reproduction steps** — minimum reproducer. A specific track or fixture if the defect is domain-specific.
4. **Session artifacts** — relevant `features.csv` columns, `session.log` lines, contact sheet screenshot, or diagnostic dump. For beat-sync and stem-routing defects, `features.csv` beat columns and a `BeatSyncSnapshot` are the primary artifacts. For render defects, a `RENDER_VISUAL=1` contact sheet is required where available.
5. **Suspected failure class** — one class from the taxonomy (`algorithm`, `concurrency`, `api-contract`, `calibration`, `pipeline-wiring`, `resource-management`, `sample-rate`, `precision`, `test-isolation`, `sdf-geometry`, `render-state`, `regression`, `documentation-drift`).
6. **Verification criteria** — written before the fix, not after. At minimum: one automated gate + one manual check for any defect affecting musical feel or visual fidelity.

**Fix increment obligations.** Every fix increment must:
- Update `docs/QUALITY/KNOWN_ISSUES.md` — fill in the `Resolved` field and commit hash.
- Update `docs/RELEASE_NOTES_DEV.md` — add or extend the current release entry.
- Not skip these updates under "it's obvious from the commit."

**Multi-increment process for P0/P1.** Unless a defect is trivial (< 5 lines of change, root cause obvious from existing artifacts, no architectural risk — requires Matt's explicit approval to collapse), the fix process uses separate increments:

1. **Instrumentation** — add logging, diagnostic capture, or test infrastructure to expose the failure. Commit and stop.
2. **Diagnosis** — reproduce from artifacts, identify root cause, document in `KNOWN_ISSUES.md`. Do not write fix code in this increment.
3. **Fix** — implement the fix, add or extend regression tests.
4. **Validation** — run full test suite, produce required domain artifacts, perform manual validation where mandated.
5. **Release notes** — update `RELEASE_NOTES_DEV.md`, mark resolved in `KNOWN_ISSUES.md`.

Trivial P1 defects may collapse steps 1–4 into one increment. State this explicitly in the commit message and in `KNOWN_ISSUES.md`.

**Domain-specific artifact requirements.** These domains require diagnostic artifacts before and after fix work:

- **Beat sync / tempo** (`dsp.beat`): `features.csv` beat-sync columns (`lock_state`, `grid_bpm`, `drift_ms`, `barPhase01_permille`), SpectralCartograph mode label capture, and `BeatSyncSnapshot` data from a real music session. Minimum: Love Rehab at 125 BPM.
- **Stem routing** (`dsp.stem`): `stems.csv` showing non-constant deviation-field values across 500+ frames, plus manual observation that visual response feels musically connected.
- **Preset fidelity** (`preset.fidelity`): contact sheet from `RENDER_VISUAL=1` compared against `docs/VISUAL_REFERENCES/<preset>/` reference images. Anti-references must be explicitly checked (see Failed Approach #48).
- **Render pipeline** (`renderer`): `PresetRegressionTests` golden hash before and after; Metal GPU trace if frame budget is affected.

**Manual validation is required for:**
- Musical feel: beat alignment, stem-visual coupling, tempo tracking. Automated tests prove pipeline correctness; they do not prove the result feels musical. These judgments require listening at normal volume.
- Visual fidelity: M7 review for any preset approaching certification. Matt's approval is required; no automated metric substitutes.
- UX flow: any change to the session lifecycle or playback chrome. Walk the affected flow end-to-end; do not rely solely on unit tests of view models.

## Module Map

The per-file behavioural reference (every Swift source file, every Metal shader, every test target) lives in [docs/ARCHITECTURE.md §Module Map](docs/ARCHITECTURE.md#module-map). Per-preset design history split out at DOC.4 (2026-06-11) per borderline-call B of the 2026-05-13 doc-refactor plan: Arachne V.7.x → `docs/presets/ARACHNE_V8_DESIGN.md §Module-Map history`, LumenMosaic LM.3 → LM.7 → `docs/presets/LUMEN_MOSAIC_DESIGN.md §Module-Map history`; the Module Map entries keep short architectural notes + pointers.

---

## Audio Data Hierarchy — The Most Important Design Rule

**Learned the hard way in the Electron prototype. Beat-dominant designs feel out of sync. Continuous-energy-dominant designs feel locked to the music. Non-negotiable.**

### Layer 1: Continuous Energy Bands (PRIMARY VISUAL DRIVER)
`bass`, `mid`, `treble` (3-band) and 6-band equivalents. Zero detection delay. Feedback zoom, rotation, color shifts, geometry deformation — all driven primarily by these.

### Layer 2: Spectrum and Waveform Textures (RICHEST DATA)
512 FFT magnitude bins + 1024 waveform samples → GPU as buffer data, not scalars. Modern GPUs process 512+ bins per fragment.

### Layer 3: Spectral Features (DERIVED CHARACTERISTICS)
Centroid, flux, rolloff, MFCCs, chroma. Modulate color temperature, complexity, scene behavior.

### Layer 4: Beat Onset Pulses (ACCENT ONLY — NEVER PRIMARY)
±80ms jitter from threshold-crossing. Feedback amplifies jitter. Must NEVER be the dominant motion driver.

### Layer 5a: Pre-Analyzed Stems (AVAILABLE FROM FIRST FRAME)
From 30-second preview clips. Available instantly on track change via StemCache. Not time-aligned with live playback.

### Layer 5b: Real-Time Stems (REPLACES 5a AFTER ~10 SECONDS)
From live Core Audio tap via MPSGraph. Time-aligned with playback. Crossfades with 5a.

**Rule of thumb:** `base_zoom` and `base_rot` (continuous energy) should be 2–4× larger than `beat_zoom` and `beat_rot` (onset pulses).

### Cold-Start Phase Contract

What the system can and cannot claim about beat synchronicity at the start of a new track. The original Phase CS bar (±50 ms / 90 % from frame 1) was empirically falsified across six iterations and retired per Matt's Choice A decision (2026-05-25); the premise "some automated signal in the first ~3 s of tap audio reliably gives the audible beat phase" is dead — see Failed Approach #69. Production is the pre-BSAudit.3.impl baseline (the impl was reverted same-day). **The full contract history — the six iterations, the revert narrative, the empirically-characterized failure modes (wrong-anchor lock, slow-anchor lock) — lives in [`docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`](docs/CAPABILITY_REGISTRY/BEAT_SYNC.md) §Cold-Start Phase Contract (moved there at DOC.4) and `docs/HISTORICAL_DEAD_ENDS.md` §Cold-start.**

**What production delivers at cold-start.**

- **Continuous-energy modulation from frame 1.** `bass`, `mid`, `treble`, and the deviation primitives (`bassRel`, `bassDev`, etc.) are active immediately. Layer-1-driven presets show full response from the first frame.
- **Cached `BeatGrid` install at track start** via `MIRPipeline.setBeatGrid(_:initialDriftMs:)` — Beat This! on the 30 s preview gives reliable BPM + meter, but the phase may be wrong on live audio (cross-capture-unstable on 5–6 of 10 audit-catalog tracks, BSAudit.2).
- **`LiveBeatDriftTracker`** (sub-bass-onset EMA over per-event residuals) + **`GridOnsetCalibrator`** (pre-track onset → grid alignment). Steady-state lock improves as the EMA converges.
- **Ungated beat accents.** `beatBass / beatMid / beatTreble / beatComposite` flow at full amplitude from frame 1 from the cached grid — there is no `accentConfidence` field; wrong-phase tracks fire wrong-phase accents during cold-start.

**What production does NOT deliver:** ±60 ms perceptual sync within 3 s on a novel track (structurally unachievable from live tap audio alone — the failure modes apply to ANY short-window signal source); cross-capture-stable verification anchored to Beat This!-on-tap (`ColdStartVerifier --accent-window-pass-rate` is a relative-comparison tool, not a perceptual close gate); automatic cold-start accent suppression at the `FeatureVector` layer.

**What this means for preset authoring.**

- **Drive primary motion from Layer 1** (unchanged — the Audio Data Hierarchy rule).
- **Beat-pulse fields are accents, not primary motion** (unchanged); they fire ungated from frame 1 — presets needing cold-start accent suppression implement it themselves (time-since-track-start envelope, deviation-primitive gating per D-026, or similar).
- **`beatPhase01` / `barPhase01` are not gated**; the cold-start phase may be off-beat — use them for continuous motion (colour cycles, contours) where small phase errors read as small offsets, not wrong-beat firings.
- **Do not iterate further on automated cold-start beat-phase derivation** (Failed Approach #69). Any future work needs a fundamentally different premise (human-tap reference, full-track local-file analysis, manual per-track calibration UX) — surface the premise change to Matt before scoping.

---

## Audio Analysis Tuning

See [docs/ARCHITECTURE.md §Audio Analysis Tuning](docs/ARCHITECTURE.md#audio-analysis-tuning) for AGC behaviour, frequency band definitions, onset detection thresholds, validated onset counts, tempo estimation, chroma normalization, and mood-classifier inputs. The bedrock rule of audio data hierarchy (above) is the operating principle; the tuning section is the calibrated values that implement it. The ARCHITECTURE subsection "LF playback vs process-tap path — empirical deltas (LF.1.5)" characterizes the cross-path numerical differences — BPM and beat-grid timing agree; `spectralCentroid` and `valence`/`arousal` shift with capture sample rate; AGC compresses but does not fully eliminate the LF-vs-tap volume delta on load-bearing per-band energies (17-24 % skew, all same direction). Authoring rule (unchanged): drive primary motion from deviation primitives (D-026), not absolute thresholds — that makes presets robust to source-path differences for the same reason it makes them robust across tracks.

---

## Key Types

See [docs/ARCHITECTURE.md §Key Types (Shared Module)](docs/ARCHITECTURE.md#key-types-shared-module) for the FeatureVector / FeedbackParams / StemFeatures / SceneUniforms struct layouts and the supporting Audio / Session / Orchestrator value types. Update both this pointer and the reference if a struct layout changes (the layouts are part of the GPU contract — see below).

---

## GPU Contract

See [docs/ARCHITECTURE.md §GPU Contract Details](docs/ARCHITECTURE.md#gpu-contract-details) for the texture binding layout (slots 0–11), buffer binding layout (slots 0–8), preamble compilation order, G-buffer format, SSGI knobs, accumulated-audio-time semantics, mesh-shader architecture, and ICB architecture. The contract is load-bearing for every preset shader — read it before authoring a new pass.

---

## Preset Metadata Format

See [docs/SHADER_CRAFT.md §17. Preset Metadata Format (JSON sidecar)](docs/SHADER_CRAFT.md#17-preset-metadata-format-json-sidecar) for the JSON sidecar schema — `name`, `family`, `passes`, scene camera/lights, stem affinity, `complexity_cost`, `certified`, `rubric_profile`, and the rest. Every new preset ships a `<PresetName>.json` next to its `.metal` file.

---

## Visual Quality Floor

See [docs/SHADER_CRAFT.md](docs/SHADER_CRAFT.md) — the full authoring handbook — for the detail cascade (4 mandatory scales), noise floor (≥4 octaves), material count (≥3 distinct), pale-tone-share rule (≤ 30 % per panel — supersedes the retired categorical anti-cream rule per D-LM-cream-rescission), coarse-to-fine 9-pass workflow, reference-image-first requirement, and the fidelity rubric (`§12`). SwiftLint `file_length: 400` is relaxed for `.metal` files (see `SHADER_CRAFT.md §11.1`). Good ray-march shaders run 800–2000 lines; do not truncate or split for lint conformance.

Preset-related increments open with the session-start checklist in [docs/PRESET_SESSION_CHECKLIST.md](docs/PRESET_SESSION_CHECKLIST.md) (RB.2 — replaces the former Failed Approaches #39/#63 reference-discipline entries).

---

## Session Preparation Pipeline

See [docs/ARCHITECTURE.md §Session Preparation](docs/ARCHITECTURE.md#session-preparation) for the lifecycle states, per-track preparation steps, progressive readiness levels (Increment 6.1), and metadata-fetcher priority. `SessionManager.startSession()` returns immediately; preparation runs in a background `Task { @MainActor }`.

---

## UX Contract

See [docs/UX_SPEC.md](docs/UX_SPEC.md) for the canonical product-UX contract — state-to-view mapping (six top-level views, one per `SessionState`), copy principles (§8.5), the error taxonomy (§8), accessibility requirements, progressive readiness, and the operating rules around playback chrome.

Three project-level invariants worth surfacing here so they catch session-start review:

- **One `SettingsStore` app-wide.** Constructed in `PhospheneApp.swift`; injected as `@EnvironmentObject` everywhere. Never `@StateObject SettingsStore()` inside a view — that's Failed Approach #55 (regression-locked by `SettingsStoreEnvironmentRegressionTests`).
- **All user-facing strings externalised.** Every `Text(...)` / `.help(...)` / `.accessibilityLabel(...)` under `PhospheneApp/Views/` resolves through `Localizable.strings` via `String(localized:)`. `Scripts/check_user_strings.sh` enforces.
- **Tooltips do not lie.** Tooltip text describes what the control does *now*, not what it *will* do. If a control is genuinely not yet wired, hide it behind a build flag.

---

## ML Inference

See [docs/ARCHITECTURE.md §ML Inference](docs/ARCHITECTURE.md#ml-inference) for the no-CoreML decision (D-009), stem-separator + mood-classifier shapes, dispatch-scheduling algorithm (D-059), and stem-analysis cadence.

---

## Code Style

- Swift 6.0, `SWIFT_STRICT_CONCURRENCY = complete`. `async`/`await` and actors. Avoid raw `DispatchQueue` except for Accelerate/vDSP.
- Shared types: `Sendable`. Audio frame types: `@frozen`, SIMD-aligned.
- `NSLock.withLock {}` from synchronous contexts only. For types mixing sync callbacks with async API, use `@unchecked Sendable` class with NSLock.
- No `print()`. Use `os.Logger` via `Shared/Logging.swift`.
- SwiftLint: `force_cast`/`force_try`/`force_unwrapping` → error. `file_length` warning at 400. `cyclomatic_complexity` warning at 10.
- All `public` API has `///` doc comments. Every file uses `// MARK: -` dividers.
- Protocol-first design. Every injectable dependency has a protocol. Tests use doubles from `TestDoubles/`.
- **URLProtocol stub tests require `@Suite(.serialized)`** (U.10 learning). Swift Testing runs suites in parallel by default. A suite that uses a global `nonisolated(unsafe) static var handler` on a `URLProtocol` subclass must be annotated `@Suite(.serialized)` — otherwise one test's handler bleeds into another test's in-flight URL session on a background thread. Discovered when 5 of 9 `SpotifyTokenProviderTests` returned `HTTP 400` instead of 200 during parallel execution.
- **When adding enum cases to a VM's state type, update every `switch` in the corresponding view simultaneously.** New cases that are `@ViewBuilder`-switch arms in a different file will silently fail to compile only when the app target builds (not the engine SPM target). Discovered when `.privatePlaylist` and `.authFailure` were added to `SpotifyConnectionState` but `SpotifyConnectionView`'s exhaustive switch was not updated — the engine test suite passed but the app build failed.
- **App-layer services use `Logger(subsystem:category:)` directly, not `Logging.session`.** The engine `Shared/Logging.swift` module's `Logging.session` logger is only available within `PhospheneEngine`. App-layer files in `PhospheneApp/` must `import os.log` and instantiate their own `Logger(subsystem: "com.phosphene.app", category: "...")`. Discovered during U.11 when `SpotifyKeychainStore` and `SpotifyOAuthTokenProvider` referenced `Logging.session` and failed to build. (U.11)
- **New app-layer source files must be registered in Xcode project.pbxproj across all four sections.** Files on disk that are not in the project file cause `cannot find type` build errors. Four sections must all be updated: `PBXBuildFile` (build file entry), `PBXFileReference` (file reference), `PBXGroup` (parent group membership), and `PBXSourcesBuildPhase` (target sources list). The project uses alphabetical UUID prefixes (N10xxx / N20xxx were the next-available block in U.11). Verify after adding files: `xcodebuild -scheme PhospheneApp build` will fail immediately if any section is missing. (U.11)
- **`@MainActor` debounce test timing margins under parallel execution.** Under 305-test parallel app test execution, `@MainActor` task scheduling has more contention than under smaller suites. 300ms debounce requires 700ms wait (2.3× headroom). Async actor-hop completions (connect, login) require 400ms wait. Baseline: U.11 widened from 400ms → 700ms for debounce, 100–200ms → 250–400ms for connect/login, matching the engine timing note in Increment U.11. (U.11)
- **Commit messages use `[<increment-id>] <component>: <description>` format**, e.g. `[SB.1] Routing: convert drums to drumsEnergyDev (D-026)`. Within an increment, prefer multiple small commits (one per logical step) over one large commit — finer-grained history makes `git bisect` useful for subjective quality regressions, not just test failures. Push after each increment's verification passes; intermediate commits stay local.

---

## Failed Approaches — Do Not Repeat

**Numbering convention.** Entries below preserve their original numbers from prior iterations. Some numbers are intentionally absent — those entries moved (DOC.3, 2026-05-13) to `docs/HISTORICAL_DEAD_ENDS.md` (dead APIs / superseded calibration) or to topical handbooks where the rule applies. The originals remain searchable under their old numbers in those files; cross-references like "Failed Approach #44" still resolve.

| Gap | Where it lives now |
|---|---|
| #5, #6, #7, #8, #9, #10, #12, #13, #19 | `docs/HISTORICAL_DEAD_ENDS.md` |
| #14, #20 | `docs/HISTORICAL_DEAD_ENDS.md` (DOC.4 — CoreML gotchas; CoreML unused per D-009) |
| #41 | `docs/UX_SPEC.md §15 Test Surface` |
| #34, #42, #43, #44 | `docs/SHADER_CRAFT.md §13` |
| #35, #36, #37, #38, #40 | `docs/SHADER_CRAFT.md §13` (DOC.4 — already restated there as §13 #35/#36/#38/#39/#42; see the §13 mapping note) |
| #45, #46, #47 | `docs/RUNBOOK.md §Spotify connector setup` |
| #1, #2, #3, #11, #15, #16, #17, #18 | `docs/HISTORICAL_DEAD_ENDS.md` §RB.2 rulebook purge (superseded DSP/API-era entries; Matt per-entry review 2026-06-11; context in `docs/diagnostics/RB1_FA_DN_EXPLANATIONS.md`) |
| #21, #22 | code comment at `SystemAudioCapture` tap install + `docs/RUNBOOK.md` troubleshooting (RB.2) |
| #39, #63 | `docs/PRESET_SESSION_CHECKLIST.md` (RB.2 — replaced by the preset session-start checklist) |
| #23, #24, #25, #26, #28, #29, #30, #32, #33, #48, #49, #50, #51, #52, #53, #54, #55, #56, #57, #58, #59, #60, #61, #62, #66, #68, #69, #70, #71, #72 | removed at RB.2 (Matt per-entry review 2026-06-11) — tombstones in `docs/HISTORICAL_DEAD_ENDS.md` §RB.2; context in `docs/diagnostics/RB1_FA_DN_EXPLANATIONS.md` |

4. **Beat-dominant visual design** (beat_zoom >> base_zoom): ±80ms jitter amplified by feedback. **Scope:** this prohibits beat as the *dominant motion driver* — continuous energy is always primary (see Audio Data Hierarchy). Beat-coupled accents are fine, even encouraged — Lumen Mosaic's per-beat cell-colour dance is beat-driven and works. The rule is "beat is accent, never primary," not "minimize beat coupling."
27. **Synthetic audio for visualizer diagnostics**: Hand-authored FeatureVector envelopes do not reproduce real-music pipeline noise/cross-band correlation/MIR-derived structure. Diagnostic harnesses must run the actual capture path on real audio.
31. **Absolute thresholds on AGC-normalized energy** (e.g. `smoothstep(0.22, 0.32, f.bass)`): AGC's denominator (running-average) moves with mix density, so the same acoustic kick reads different values across tracks or across sections of one track. Six VL iterations (v3→v4.2) hit this repeatedly. Drive from deviation instead — `f.bassRel`, `f.bassDev` (D-026, MV-1). See `docs/MILKDROP_ARCHITECTURE.md` for the full diagnosis.

64. **Iterating on shader fixes by first-principles guessing on a problem with known published solutions** (V.9 Session 4.5 Phase A Ferrofluid Ocean, 2026-05-13 → 2026-05-14): a per-cell "dot pattern" appeared in rendered output after the Session 4.5 lighting rebuild. I made six successive structural claims about the cause — bell-curve flat top reflects zenith → linear cone fixes it → no wait, linear cone normal-flips at cell edges → quadratic cone fixes both → still dots, must be a resolution artifact → bump test resolution → still dots → must be aurora coverage mismatch → sweep aurora band thickness 0.30 / 0.50 / 0.70 / 1.00 → still dots — each fix landed mechanically, none converged. Matt eventually pointed out (i) several of my "production won't show this" assertions were unverified, and (ii) ferrofluid rendering is a solved problem in the field and I should be doing desk research, not guessing from first principles. Desk research surfaced Robert Leitl's audio-reactive WebGL ferrofluid project (closest published reference to Phosphene's use case): the canonical technique is **smooth Voronoi** (Inigo Quilez's exponential-blend soft-min) for the height field — the C¹-continuous distance function eliminates cell-boundary normal-flip artifacts that were producing the dot pattern. One library function from a 2014 article fixed in 30 minutes what six iterations of first-principles cone-shape tuning failed to fix. **Rule:** when iterative first-principles fixes aren't converging on a problem that has known prior art in the field, *stop guessing and do desk research*. Failed Approach #49 is the structural-gap escalation; this is its discipline-rule counterpart at the implementation-technique level. Symptoms that should trigger desk research: (a) ≥ 2 successive structural fixes failed to converge; (b) the failure mode has a recognizable name in graphics literature ("dot pattern," "shading artifact at cell boundaries," "ferrofluid rendering"); (c) other implementations of the same effect exist and are findable in 1–2 web searches. The cost of desk research is small. The cost of three more iterations of guess-test-fail is large.

65. **Negotiating away components of a working reference implementation under unverified "redundancy" arguments** (V.9 Session 4.5 Phase A Ferrofluid Ocean, 2026-05-14): after desk research surfaced Robert Leitl's four-layer lighting model (Phong specular + env map + fresnel rim + iridescence palette) as the technique producing his demo's "incredible" character, I proceeded to argue each component into the trash — iridescence is "redundant with aurora," fresnel rim is "redundant with thin-film F0," Phong specular contradicts "mirror-reflects-sky." Each redundancy claim was unverified hand-wave reasoning; Matt called it out: *"I had you review Leitl's demo to get ideas and now it appears that you have rejected all of the ideas you found within it."* The components were mathematically *different operations* on different geometric domains — Leitl's demo character comes from all four together, not from any single one. **Rule:** when adopting a working reference implementation, the default is to adopt the components that produce its visual character verbatim and adapt only what differs in *context* (scale, audio routing, scene type). "Redundancy" claims against components of a working reference require rendering proof of the claim, not first-principles math. The failure mode is: anchor on prior paradigm → find reasons to subtract from reference → end up with neither paradigm working. **Tell-tale phrasing of the failure:** "I think X is redundant with Y" without having tested removal. If you catch yourself writing that sentence, you are about to repeat this failure.

67. **Routing the same audio timescale to two different visual layers** (Ferrofluid Ocean rounds 56–65, 2026-05-17 → 2026-05-18). Round 50 established the constant-field premise (spike geometry not audio-coupled). Rounds 56/60 tried to layer "subtle music response" back onto the spike heights via `bass_dev` — at the SAME TIMESCALE the swell amplitude was already being beat-coupled via `0.3 × drums_dev`. The two layers responding to similar beat-rate audio at different visual scales produced a "competing rhythms" reading: per-beat spike pulse AND per-beat swell pump moving simultaneously, encoding the same musical information twice through two different visual channels. Round 61 tried gating the spike pulse to `bar_phase01` (downbeat-only) — produced a different defect because bar boundaries don't align with bass kicks. Round 63 reverted to constant spikes. Round 65 finally landed the right configuration: REMOVE the drums coupling from swell amplitude (swell becomes arousal-only, slow), THEN reactivate per-beat spike-height response. With only one layer carrying the per-beat signal, the spike pulse reads as intended response without competition. **Rule:** when adding audio reactivity to a new visual layer, audit which other layers are responding to primitives at similar timescales. Don't route per-beat audio into two layers; don't route slow-arousal audio into two layers either. Each visual layer should consume one primitive at one characteristic timescale. **Architectural test for a new preset's audio-reactivity routing:** make a small table of (visual layer × audio primitive × timescale). If two layers share a primitive (or two primitives at the same timescale), that's the bug — the music will overdrive the same information through two visual channels and read as "fighting itself." Same lesson independent of preset: the architecture is one-primitive-per-layer.

73. **Don't build what's already been built — rebuilding from first principles a system that already exists as a working, code-available reference, *especially one the user explicitly provided*** (Murmuration MM.1→MM.3, 2026-06-03). At the MM.1 kickoff Matt supplied the canonical flocking references (Robert Hodgin *Murmuration*, **Rama Hoetzlein flocking**, techcentaur boids, the McGill analysis). I *cited* them in the design doc and then built a **force-based** boids substrate (sep/align/cohesion as summed force vectors + a global roost-attractor leash) and hand-derived an **injected curl "turning wave"** for beats, then tuned it across many rounds — MM.2, MM.3, and a live **M7 failure** where the forces tore the flock apart (FA #4 inverted; see `project_deviation_primitive_real_range`). Only when Matt asked "*how much have you used the reference codebases I provided?*" did I actually read them: the real reference — **Hoetzlein's Flock2 (2024, published in J. Theoretical Biology, MIT-licensed code)** — is a *structurally different and better* model that natively produces everything I was hand-deriving. Neighbor influence is a **desire to turn** (orientation targets, quaternion dynamics), not a force vector; the traveling **dark bands EMERGE** from alignment+avoidance coupling (I was *injecting* them); cohesion is a **peripheral-boundary turn** (I used a roost leash that clumps/freezes); and it is **stable under perturbation by construction** (force-summing is *why* mine shredded under audio). I built a worse version of a solved problem and burned an M7 round on it. **Discriminator:** if a reference (paper, repo, demo) for the *exact* system exists — doubly so if the user handed it to you — READ AND PORT IT before writing a line of your own derivation. "I cited it in the design doc" is **not** using it. The tell-tale is iterating on tuning rounds to coax behavior the reference already specifies (orientation waves, cohesion-without-clumping). This is the **parent rule** of FA #64 (do desk research once first-principles fixes stop converging) and FA #70 (port the reference's loop *wholesale*, don't approximate it piece-by-piece) — those govern *how* to use a reference; #73 governs *using it at all*. Cross-ref FA #39/#63 (don't author without reading the provided reference material). See `project_flock2_reference` for the model + parameters to port.

---

## Authoring Discipline — Process Failures to Not Repeat

These are operational rules distilled from the Drift Motes retirement (D-102, Failed Approach #58) and from prior preset iterations where Matt's feedback cycle was longer than necessary. They are *process* rules — how to work — not technical rules. Read them at the start of any preset session, before opening a `.metal` file.

**Strategy-scope clause (added DOC.3, 2026-05-13).** These rules apply at *strategy / product-commitment scope*, not just preset-authoring scope. Failed Approach #60 (Phase MD bloc) replayed the Drift Motes failure pattern (#58) at strategy scope — twenty decisions filed in one day, ten amended the same day, one reverted within 24 hours. When a strategic commitment is being drafted without empirical input from the work it governs, the same discipline rules fire: stop and bring the gap to Matt; do not produce structure as a substitute for an answer; do not treat "reusable infrastructure" as a defense for an unvalidated concept. A strategy decision is a forecast until evidence converts it; commit decisions when the work has produced evidence, not before.

**Articulate the musical role before authoring anything.** Before writing the JSON sidecar, before reading reference images, before opening a `.metal` file, write a one-sentence answer to: *"How is this preset's primary visual subject another instrument in the band?"* The sentence must name a specific musical feature (a beat, a downbeat, a sustained bass envelope, a vocal pitch contour, a structural boundary, a build-up) and a specific visual behaviour the listener will pair with it. "Vibe with the music" / "reactive to energy" / "feels like the song" are not answers. If you cannot produce the sentence, stop. Bring the gap to Matt before scoping the increment. The Drift Motes concept failed this gate and four days of iteration did not recover.

**Reference images are still moments; presets are behaviours over time.** A photograph in `docs/VISUAL_REFERENCES/<preset>/` shows what the *frame* should resemble. It does not encode the *temporal contract* — what changes when the bass drops, what fires on a downbeat, what carries the listener through a 30-second cycle. Failed Approach #39 (authoring without reference images) is the floor; meeting it is not enough. Pair every reference image with an explicit temporal contract before the first commit.

**Three-part bar for any new preset concept.** Every concept must clear all three:
1. **Iconic visual subject deliverable at fidelity** — you can demonstrate, from a comparable past preset, that the visual style is reachable. Honest self-assessment: if Matt has flagged a fidelity gap on a similar preset before, your default is "I cannot deliver this" until proven otherwise.
2. **Clear musical role** — see the previous rule.
3. **Infrastructure-feasible** — does not require render passes / engine surfaces / GPU contracts Phosphene lacks. If the answer is "we can add the infrastructure," check whether Matt agrees the infrastructure is worth the increment.

Pitches that pass two of three and require the user to spot the missing third are not acceptable. Surface concerns *before* the pitch, not when cornered.

**The next response to pushback must change the answer, not justify it.** When Matt flags a problem, the failure mode I fall into is producing structured analysis — "I can see X about the music," pros/cons lists, three-part frames — as a substitute for thinking. The user perceives this correctly as bullshit-generation: *"Everything you are telling me is bullshit"* / *"Stop pitching"* (2026-05-11). If a reply has more structure than substance, delete the structure. Real thinking changes the answer; decorating the existing answer with more framework is cope.

**"Reusable infrastructure" is not a defense for a failed concept.** When a preset's concept doesn't work, the implementation does not earn preservation as "kernel waiting for the right concept" or "scaffolding for a future preset." D-097 (siblings, not subclasses) means future particle presets ship their own conformer and shader file. The Drift Motes `motes_update` kernel was specific (force-field motion + age recycle + per-particle hue bake) — it could not host an unrelated concept without rewrite. If "infrastructure" appears in a defense of keeping deleted-concept code, the defense is wrong.

**Iteration converges only when each step integrates feedback into the model.** A remediation increment that ships green but doesn't update your understanding of why the preset is failing is not progress. After every M7 round, write one sentence: "what I now believe about why this preset is failing." If the sentence doesn't change between rounds, the iteration is mechanical and the next increment is wasted. Stop and re-scope.

**Treat Matt's fidelity warnings as constraints, not discussion points.** If Matt says, on the basis of observed past sessions, that you will not be able to deliver a particular fidelity target — treat that as a binding constraint. Pitch only within the achievable bar, or say "I cannot deliver this" upfront. *"B or C will be botched by you because you won't be able to achieve the level of visual fidelity needed. I have literally watched this happen for the last several preset designs"* (2026-05-11) is data, not a debate prompt.

**Verify against the artifact before asserting facts about it.** Several smaller failures in the Drift Motes timeline came from confident-but-wrong assertions: a perf-capture procedure that cited a non-existent CSV column, a misattribution of a test failure to V.7.7C.4 when working-tree state showed V.7.7C.5, a "what's next" pitch for BUG-011 work that `git log` would have shown the parallel session was actively doing. The verification cost (one grep, one `git log`, one file read) is always less than the cost of being corrected. Default to verification when the claim is checkable.

**Decisions presented to Matt must be framed in product-level language with explicit benefits and trade-offs.** Matt is product/design lead, not a peer engineer. Any decision presented to him for input must:

1. **Be framed in user-visible terms, not engineering jargon.** Use "how dense are the spikes" not "particle count = 256 / 512 / 1024." Use "how responsive is the motion" not "update tick frequency." Use "how sharp are the peaks" not "smooth-min `w` parameter."
2. **Call out benefits and trade-offs in plain English.** For each option, name what the user sees / feels — not what the code does. E.g. "Medium-dense (peaks touch base-to-base; surface reads as covered in ferrofluid)" vs "Densely-packed (individual peaks blur into continuous textured field; closest to references but more processing overhead)."
3. **Include a recommendation with reasoning.** Default value Matt can accept if he has no strong preference; he should not have to do engineering math to ratify your default.
4. **Limit the question to decisions that actually have product-level consequences** (visual character, motion feel, audible behaviour, UX flow). Engineering implementation choices (CPU vs GPU, buffer sizes, math precision, internal data structures) are Claude's responsibility — make them yourself, explain only the user-facing consequence if any.

If a question requires Matt to already know implementation details to answer it, the question is wrong — reframe at the product level or make the decision yourself.

**Tell-tale phrasing of the failure:** asking Matt "Option (a): 256×256, Option (b): 512×512, Option (c): 1024×1024" — three values that mean nothing without engineering context. Reframe as "How sharp should the peaks render? Adequate (1.5 cm per pixel) / sharp / very sharp" with what the user sees at each, recommendation, and a default.

**Discovered:** V.9 Session 4.5b draft prompt (2026-05-14) asked Matt to choose particle count, height-map resolution, smooth-min parameter, and update location — four engineering values requiring implementation context to evaluate. Matt called it out: *"you keep insisting on communicating with me like I'm a peer engineer."* The rule above was promoted to CLAUDE.md immediately as a binding discipline rule.

**Escalation thresholds.** Stop and bring the gap to Matt — do not start the next increment — when any of these fire:
- Two consecutive M7 reviews return negative feedback whose root cause you cannot articulate.
- A successor-concept pitch fails the three-part bar.
- You catch yourself producing structure as a substitute for an answer.
- A "reusable infrastructure" argument is forming in your response.
- The one-sentence "what I now believe about why this preset is failing" hasn't changed between rounds.

The cost of pausing is small. The cost of another day of mechanical iteration on a broken concept is high.

**Test in the production-grade rendering pipeline. No shortcuts.** Promoted to CLAUDE.md from Matt's instruction 2026-05-18 after AV.1 / AV.2 / AV.2.1 each shipped with green tests despite producing painterly smear in live playback — the Aurora Veil test harnesses rendered single frames through `preset.pipelineState` directly, bypassing the mv_warp accumulator the live app uses. Three increments wasted before the diagnostic test that exercises mv_warp was written.

**The rule:** every preset increment that depends on temporal behavior must include a test that runs the same dispatch path the live app uses — for ≥ N frames where N covers the relevant accumulator decay window — and inspects the multi-frame output. "Same dispatch path" means: if the preset uses `mv_warp`, the test runs scene → warp → compose → swap in a loop. If it uses `staged`, the test runs all stages. If it uses `ray_march`, the test runs G-buffer → lighting → composite. Tests that bypass to `preset.pipelineState` alone are sufficient ONLY for verifying the shader's instantaneous output; they do NOT prove the preset works under the live rendering pipeline.

**Concrete obligations:**
1. **Before authoring a preset that uses `mv_warp` / `staged` / `feedback` / `ray_march` + `post_process`** — write or extend the multi-frame test harness FIRST. Verify the live pipeline path is reachable from a test before shipping any shader work.
2. **For mv_warp-using presets specifically** — `AuroraVeilMVWarpAccumulationTest` is the reference pattern (env-gated, runs scene → warp → compose → swap for 60 frames at silence, captures the final accumulator + a quantitative star-count metric). Adapt for new presets; do not reinvent.
3. **For staged presets** — the harness must bind the same slot-6 / slot-7 buffers the production path binds (CLAUDE.md FA #66; same principle generalizes).
4. **Single-frame tests stay valuable** for shader-math gates (palette stratification, deviation primitives, brightness amplitude). They are NOT sufficient on their own.
5. **Closeout reports must state which dispatch path the tests exercised.** "Tests pass" alone is no longer evidence of correctness.

**Tell-tale phrasing of the failure:** "the silence test passes, so silence is stable" / "the visual review PNG looks clean" / "the regression hash is within Hamming threshold." None of these prove the preset works under the live pipeline if the test bypasses it. Surface this and write the missing harness BEFORE filing the increment as ✅.

**Design is upstream of testing — surface risks immediately.** A passing test of a flawed design just ships the flaw faster. When the design doc proposes a mechanism without empirical grounding (e.g., AV's "mv_warp on top of nimitz's procedural recipe" — no published aurora demo combines those), name that as a risk to Matt **before** writing any code, not after the rendering smears in live.

**Grounding priority (Matt-approved 2026-05-18, soft rule).** Required grounding for each mechanism, in descending order of preference:
1. **Working code reference in a comparable visual context.** Cite Shadertoy ID, GitHub repo, demo URL.
2. **Academic paper or physics derivation + clear math** that can be implemented from the description alone. Example: Lawlor's `H(z)` curve from the WSCG 2011 paper.
3. **No reference, just the design doc's assertion.** Highest risk. Surface explicitly as "no empirical grounding for X" before authoring; Matt decides whether to accept the risk or descope.

When combining two mechanisms (e.g., procedural recipe + feedback accumulator), the combination itself needs grounding — not just each piece individually. AV's failure was layering mv_warp on top of nimitz without any working aurora demo doing the same combination; neither piece alone was the problem, the combination was.

The threshold for "surface immediately" is when you reach grounding level 3 (no reference) on any non-trivial mechanism. Don't proceed silently on assertion alone.

**Diagnostic infrastructure precedes fidelity claims.** Promoted to CLAUDE.md from the AV.2.x cascade closeout 2026-05-20. A closeout that asserts an audio-coupled route works must cite per-route firing evidence from the session's `features.csv` / `stems.csv` — frame counts, threshold-crossing percentages, video-frame extracts at the audio events. A closeout that asserts the rendered output belongs in the same visual family as the references must cite the per-question rubric proxy scores + reference family centroid + σ-distance verdict. "Visually verified," "reads in the same visual conversation as references," and "the route works" are gate-bypass language unless backed by cited evidence.

**The tool that produces the evidence is `PresetSessionReplay` (SR.1, 2026-05-20).** See `docs/ENGINE/SESSION_REPLAY.md` for invocation + extension. Every preset closeout asserting audio-coupling or visual-fidelity claims runs the harness against the relevant session + reference set and embeds (or links) the generated `replay_report.md` in the closeout.

**When the diagnostic doesn't exist for a question, the closeout says "cannot verify X" instead of asserting it. Building the missing diagnostic is the next increment, not a future task.** PT.1 was the existence proof: `vocalsPitchConfidence` was 0 % across every Aurora Veil session for ~5 months while closeout after closeout I authored claimed the route worked. The 10-line script tallying `vocalsPitchConfidence ≥ 0.5` from features.csv that would have caught it before AV.1 shipped didn't exist; I filled the gap with assertion-shaped language instead of building it. That pattern is retired.

**Verdicts on broken proxies are forbidden.** SR.1's rubric calibration flags a proxy `uncalibrated` when its scores across the reference set are too scattered (σ > 50 % of |mean|) or constant (σ ≈ 0). "Uncalibrated" is an honest verdict — it means the proxy isn't reliable, NOT that the render is OK. A closeout that cites an uncalibrated proxy as evidence of cert-readiness is gate-bypass. Either refine the proxy (SR.1.x / SR.2) or say "cannot verify."

---

## What NOT To Do

- Do not write a feature's `@Published` surface on one code path without clearing it on the complementary path. A publisher retains its last value indefinitely; if a feature populates it on path A (e.g. LF track-change) but a parallel mode (e.g. streaming track-change, or session-boundary) never writes it, the stale value leaks across the mode transition. LF.6's `currentTrackArtworkData` was written on the LF path but not the streaming path → the prior LF session's album art rendered against every streaming track (BUG-024). When you add a `@Published` that a feature writes, enumerate every path that changes the underlying context (every track-change callback, every `.connecting`/`.ended` session-boundary observer) and write-or-clear it on each. Pair the clear in the same MainActor tick as the sibling publisher (e.g. title + artwork together) so consumers never observe a half-updated surface.

---

## Current Status

The roadmap and increment status table live in [docs/ENGINEERING_PLAN.md](docs/ENGINEERING_PLAN.md). Recently-landed work is in `git log --oneline -30`. Known issues and active defects are in [docs/QUALITY/KNOWN_ISSUES.md](docs/QUALITY/KNOWN_ISSUES.md).

For a snapshot of what's currently in flight, what just shipped, and what's next: `git log --since="2 weeks ago" --oneline` plus `docs/ENGINEERING_PLAN.md` open the right surfaces in under thirty seconds.

The historical changelog formerly inline here grew to ~190 lines and became a doc-sync trap. Recent-increment narrative now lives in commit messages and `ENGINEERING_PLAN.md` entries; CLAUDE.md no longer mirrors it.

---

## Linked Frameworks

Metal, MetalKit, MetalPerformanceShadersGraph, AVFoundation, Accelerate, ScreenCaptureKit (Info.plist only), MusicKit.

## Development Constraints

- **Team**: Matt (product/design direction) + Claude Code (implementation).
- **Platform**: macOS only. Mac mini primary dev/deploy target.
- **Performance target**: 60fps at 1080p on Apple Silicon.
- **Dependencies**: Minimize external. Prefer Apple frameworks.
- **Learning stays local**: On-device only. No cloud, no telemetry.
- **License**: MIT.
- **Git history is maintained on github.com/hoaxpoet/phosphene.** Each increment lands as one or more commits with the increment ID in the message (e.g., `[SB.1] Routing: convert drums to drumsEnergyDev (D-026)`). For change diagnosis, prefer `git log`, `git diff`, and `git bisect` over reconstructing from documentation. `ENGINEERING_PLAN.md` and `DECISIONS.md` remain authoritative for intent and rationale; git is authoritative for what changed.
