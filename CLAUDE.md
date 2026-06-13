# CLAUDE.md — Phosphene

## What This Is

Phosphene is a native macOS music visualization engine for Apple Silicon. Before the music starts, Phosphene connects to a playlist, downloads 30-second preview clips for every track, and runs full ML-powered stem separation and MIR analysis on each. By the time the user presses play, the AI Orchestrator has planned the entire visual session — which visualizer for each track, where transitions land, and what the emotional arc looks like across the playlist. During playback, real-time audio analysis via Core Audio taps (`AudioHardwareCreateProcessTap`) refines the pre-analyzed data, and the Orchestrator adapts its plan as the music unfolds.

Phosphene does not control playback — the user starts the music in their streaming app when Phosphene signals it is ready.

See `docs/PRODUCT_SPEC.md` for the full product definition and the **Handbook Index** below for the per-topic references (architecture, decisions, runbook, UX, shader craft).

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

**Durable learnings stay in docs.** Anything a future session will need to know — a non-obvious tuning constant, a renderer convention, a preset-author rule — goes into `CLAUDE.md`, `docs/DECISIONS.md`, `docs/SHADER_CRAFT.md`, the relevant docs/ subtree, or memory. **Do not leave durable learnings only in chat.** If the only record of "we learned X" is a paragraph in this conversation, future Claude will not have it.

**`docs/ENGINEERING_PLAN.md` is mandatory to update.** Update it whenever an increment is **completed, split, renamed, deferred, or discovered to require prerequisite work**. Each increment ID should map to a row that says what done-when looks like and whether it's done. Plans drift fast — if the plan and the code disagree, treat that as a bug in the plan.

**`docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` is mandatory to update** whenever **renderer, visual harness, certification pipeline, shader infrastructure, or preset architecture capabilities change**. New capability → new row. Capability promoted Missing → Partial → Supported → flip the status and cite the files. New blocker discovered → add it. Preset implications section gets the same treatment: what's now buildable, what's still blocked. The registry is the load-bearing document for "can preset family X be built today" — let it drift and audit work doubles in cost.

**Commit locally to `main` after tests and docs are complete.** Use the standard commit message format (`[<increment-id>] <component>: <description>`). Prefer multiple small commits within an increment over one large commit — it makes `git bisect` useful.

**Do not push to the remote without Matt's explicit approval.** Local `main` commits stay local. `git push` requires "yes, push" in the chat. This applies even when the work is clearly green and clearly Matt's request — pushing remains a separate decision.

**Pruning pass — every tenth increment.** Every tenth increment (or every two weeks, whichever fires first): run `Scripts/rotate_docs.sh` (D-162 — deterministically rotates ENGINEERING_PLAN §Recently Completed narratives, resolved KNOWN_ISSUES entries, and pre-current-month release notes to their history files; `DocIntegrityTests` gates the budgets). Then handle by hand: whatever the script reports as unparseable, the CLAUDE.md section-demotion review ("did the last 10 increments need this?" — if no, demote to a handbook), and the DECISIONS shipped+uncited rotation to `DECISIONS_HISTORY.md` using its §Index. Borderline calls go through the standard "stop and report" rule below.

Pruning is the counterweight to "durable learnings stay in docs" — skip it and the doc-mass problem the 2026-05-13 refactor fixed returns. The ratchet below is the hard stop.

**Rulebook ratchet (D-161).** (1) **Token budget:** CLAUDE.md stays ≤ 7,000 estimated tokens (`wc -w` × 1.35 ≈ ≤ 5,185 words), gated by `DocIntegrityTests`; adding above the cap requires demoting or retiring equal mass in the same commit — one-in-one-out. (2) **Admission test:** a new always-loaded rule must name the specific mistake it prevents and why no deterministic gate can express it; failing either, it goes to a handbook, a session checklist, or a gate. (3) **Violated twice → mechanize:** the second documented violation of a prose rule converts it — the fix increment ships the gate and demotes the prose to a pointer.

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
- Update `docs/RELEASE_NOTES_DEV.md` — add or extend the current release entry. The file is prepend-only; read the preamble + first entry only. Older months live in `RELEASE_NOTES_DEV_YYYY-MM.md`.
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

---

## Audio Data Hierarchy — The Most Important Design Rule

**Learned in the Electron prototype and validated across every preset since: visuals driven primarily by continuous energy feel locked to the music; visuals driven primarily by raw live beat detections feel out of sync.** Continuous energy is the default primary driver. Beat-driven motion is a valid technique under the constraints noted at Layer 4.

### Layer 1: Continuous Energy Bands (DEFAULT PRIMARY DRIVER)
`bass`, `mid`, `treble` (3-band) and 6-band equivalents. Zero detection delay. Feedback zoom, rotation, color shifts, geometry deformation — all driven primarily by these. Drive from the deviation primitives (`bassRel`, `bassDev`, …, D-026), never from absolute thresholds on AGC-normalized values (Failed Approach #31).

### Layer 2: Spectrum and Waveform Textures (RICHEST DATA)
512 FFT magnitude bins + 1024 waveform samples → GPU as buffer data, not scalars. Modern GPUs process 512+ bins per fragment.

### Layer 3: Spectral Features (DERIVED CHARACTERISTICS)
Centroid, flux, rolloff, MFCCs, chroma. Modulate color temperature, complexity, scene behavior.

### Layer 4: Beat Events (ACCENTS BY DEFAULT; BEAT-LOCKED MOTION UNDER CONSTRAINTS)
Live onset detections jitter ±80 ms from threshold-crossing, and feedback amplifies jitter — never drive primary motion from raw live onsets. Beat-locked motion **is** a viable technique when built on the cached `BeatGrid` (Beat This! on the preview clip) rather than live onsets, with beat-irregular tracks excluded from beat-locked presets (D-154) and a bounded spatial footprint per beat with steady global luminance (D-157). The FFO beat-sync work (D-153 → D-158, Stage 2 validated 2026-06-11) is the proof and the pattern to follow. The cold-start caveat below applies: grid phase can be wrong at track start. Rule of thumb for onset-driven accents: `base_zoom`/`base_rot` (continuous energy) 2–4× larger than `beat_zoom`/`beat_rot`.

### Layer 5a: Pre-Analyzed Stems (AVAILABLE FROM FIRST FRAME)
From 30-second preview clips. Available instantly on track change via StemCache. Not time-aligned with live playback.

### Layer 5b: Real-Time Stems (REPLACES 5a AFTER ~10 SECONDS)
From live Core Audio tap via MPSGraph. Time-aligned with playback. Crossfades with 5a.

### Cold-Start Phase Contract

What the system can and cannot claim about beat synchronicity at the start of a new track. The premise "some automated signal in the first ~3 s of tap audio reliably gives the audible beat phase" was empirically falsified across six iterations and retired per Matt's Choice A decision (2026-05-25). **Do not iterate further on automated cold-start beat-phase derivation.** Any future work needs a fundamentally different premise (human-tap reference, full-track local-file analysis, manual per-track calibration UX) — surface the premise change to Matt before scoping.

At cold-start, production delivers: continuous-energy modulation + deviation primitives from frame 1; cached `BeatGrid` install at track start (reliable BPM + meter; the phase may be wrong on live audio); `LiveBeatDriftTracker` + `GridOnsetCalibrator` improving lock as their estimates converge; and **ungated** beat accents (`beatBass`/`beatMid`/`beatTreble`/`beatComposite`) from frame 1 — wrong-phase tracks fire wrong-phase accents. It does NOT deliver ±60 ms perceptual sync within 3 s on a novel track. Presets needing cold-start accent suppression implement it themselves (time-since-track-start envelope, deviation-primitive gating, or similar); `beatPhase01`/`barPhase01` are not gated — use them where small phase errors read as small offsets, not wrong-beat firings.

Full contract history — the six iterations, the revert narrative, the characterized failure modes — lives in [`docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`](docs/CAPABILITY_REGISTRY/BEAT_SYNC.md) §Cold-Start Phase Contract and `docs/HISTORICAL_DEAD_ENDS.md` §Cold-start.

---

## Handbook Index

One-line pointers to the load-bearing references (the former per-topic pointer sections, merged at RB.2). Read the relevant handbook section before working in its area.

**Doc-reading discipline:** for any doc over ~30 KB, locate sections with `grep -n "^## "` and read with view ranges — never read a large file end to end. Read-first lists cite sections (and D-numbers via the DECISIONS §Index), never whole large files.

| Topic | Where |
|---|---|
| Module map — per-file behavioural reference (every Swift file, Metal shader, test target) | [docs/ARCHITECTURE.md §Module Map](docs/ARCHITECTURE.md#module-map); per-preset design history split to `docs/presets/*_DESIGN.md §Module-Map history` (DOC.4) |
| Audio analysis tuning — AGC, band definitions, onset thresholds, tempo, chroma, LF-vs-tap deltas (LF.1.5) | [docs/ARCHITECTURE.md §Audio Analysis Tuning](docs/ARCHITECTURE.md#audio-analysis-tuning) |
| Key types — FeatureVector / FeedbackParams / StemFeatures / SceneUniforms layouts | [docs/ARCHITECTURE.md §Key Types](docs/ARCHITECTURE.md#key-types-shared-module) — layouts are part of the GPU contract; update pointer + reference together |
| GPU contract — texture slots 0–11, buffer slots 0–8, preamble order, G-buffer, SSGI, mesh/ICB | [docs/ARCHITECTURE.md §GPU Contract Details](docs/ARCHITECTURE.md#gpu-contract-details) — read before authoring any pass |
| Preset metadata — JSON sidecar schema (`name`, `family`, `passes`, `certified`, `rubric_profile`, …) | [docs/SHADER_CRAFT.md §17](docs/SHADER_CRAFT.md#17-preset-metadata-format-json-sidecar) — every preset ships a sidecar |
| Visual quality floor + fidelity rubric — detail cascade, ≥4 noise octaves, ≥3 materials, pale-tone ≤ 30 %, §12 rubric | [docs/SHADER_CRAFT.md](docs/SHADER_CRAFT.md) — `file_length: 400` is relaxed for `.metal` (§11.1); good ray-march shaders run 800–2000 lines, do not split for lint |
| **Preset session-start checklist — mandatory opener for every preset increment** | [docs/PRESET_SESSION_CHECKLIST.md](docs/PRESET_SESSION_CHECKLIST.md) |
| Session preparation pipeline — lifecycle states, progressive readiness, metadata-fetcher priority | [docs/ARCHITECTURE.md §Session Preparation](docs/ARCHITECTURE.md#session-preparation) |
| UX contract — state-to-view mapping, copy principles (§9.5), error taxonomy (§9), accessibility | [docs/UX_SPEC.md](docs/UX_SPEC.md) — SettingsStore + string-externalization invariants are gated (`SettingsStoreEnvironmentRegressionTests`, `Scripts/check_user_strings.sh`); the unmechanized rule: tooltips describe what a control does *now* — hide unwired controls behind a build flag |
| ML inference — no-CoreML decision (D-009), model shapes, dispatch scheduling (D-059) | [docs/ARCHITECTURE.md §ML Inference](docs/ARCHITECTURE.md#ml-inference) |
| Beat-sync capability + cold-start history | [docs/CAPABILITY_REGISTRY/BEAT_SYNC.md](docs/CAPABILITY_REGISTRY/BEAT_SYNC.md) |

---

## Code Style

- Swift 6.0, `SWIFT_STRICT_CONCURRENCY = complete`. `async`/`await` and actors. Avoid raw `DispatchQueue` except for Accelerate/vDSP.
- Shared types: `Sendable`. Audio frame types: `@frozen`, SIMD-aligned.
- `NSLock.withLock {}` from synchronous contexts only. For types mixing sync callbacks with async API, use `@unchecked Sendable` class with NSLock.
- No `print()`. Use `os.Logger` via `Shared/Logging.swift`. App-layer files instantiate their own `Logger(subsystem: "com.phosphene.app", category: ...)` — `Logging.session` is engine-internal.
- SwiftLint: `force_cast`/`force_try`/`force_unwrapping` → error. `file_length` warning at 400 (relaxed for `.metal`). `cyclomatic_complexity` warning at 10.
- All `public` API has `///` doc comments. Every file uses `// MARK: -` dividers.
- Protocol-first design. Every injectable dependency has a protocol. Tests use doubles from `TestDoubles/`.
- When adding enum cases to a VM's state type, update every `switch` in the corresponding view in the same commit — a missing `@ViewBuilder` arm fails only the app-target build, not the engine SPM suite.
- **Commit messages use `[<increment-id>] <component>: <description>` format.** Within an increment, prefer multiple small commits over one large commit — finer-grained history keeps `git bisect` useful. Pushing requires Matt's approval (see Increment Completion Protocol).
- Build/test mechanics — Xcode `project.pbxproj` four-section file registration, `URLProtocol` test serialization, parallel-execution timing margins: [docs/RUNBOOK.md §Engineering notes](docs/RUNBOOK.md).

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
| #4 | §Audio Data Hierarchy above (RB.2-2 — the absolutist "never primary" form retired for constraint-based framing; beat-locked motion on the cached grid is a valid technique per D-153 → D-158) |
| #23, #24, #25, #26, #28, #29, #30, #32, #33, #48, #49, #50, #51, #52, #53, #54, #55, #56, #57, #58, #59, #60, #61, #62, #66, #68, #69, #70, #71, #72 | removed at RB.2 (Matt per-entry review 2026-06-11) — tombstones in `docs/HISTORICAL_DEAD_ENDS.md` §RB.2; context in `docs/diagnostics/RB1_FA_DN_EXPLANATIONS.md` |

27. **Synthetic audio for visualizer diagnostics**: Hand-authored FeatureVector envelopes do not reproduce real-music pipeline noise/cross-band correlation/MIR-derived structure. Diagnostic harnesses must run the actual capture path on real audio.
31. **Absolute thresholds on AGC-normalized energy** (e.g. `smoothstep(0.22, 0.32, f.bass)`): AGC's denominator (running-average) moves with mix density, so the same acoustic kick reads different values across tracks or across sections of one track. Six VL iterations (v3→v4.2) hit this repeatedly. Drive from deviation instead — `f.bassRel`, `f.bassDev` (D-026, MV-1). See `docs/MILKDROP_ARCHITECTURE.md` for the full diagnosis.

64. **Iterating on shader fixes by first-principles guessing on a problem with known published solutions** (V.9 Session 4.5 Phase A Ferrofluid Ocean, 2026-05-13 → 2026-05-14): a per-cell "dot pattern" appeared in rendered output after the Session 4.5 lighting rebuild. I made six successive structural claims about the cause — bell-curve flat top reflects zenith → linear cone fixes it → no wait, linear cone normal-flips at cell edges → quadratic cone fixes both → still dots, must be a resolution artifact → bump test resolution → still dots → must be aurora coverage mismatch → sweep aurora band thickness 0.30 / 0.50 / 0.70 / 1.00 → still dots — each fix landed mechanically, none converged. Matt eventually pointed out (i) several of my "production won't show this" assertions were unverified, and (ii) ferrofluid rendering is a solved problem in the field and I should be doing desk research, not guessing from first principles. Desk research surfaced Robert Leitl's audio-reactive WebGL ferrofluid project (closest published reference to Phosphene's use case): the canonical technique is **smooth Voronoi** (Inigo Quilez's exponential-blend soft-min) for the height field — the C¹-continuous distance function eliminates cell-boundary normal-flip artifacts that were producing the dot pattern. One library function from a 2014 article fixed in 30 minutes what six iterations of first-principles cone-shape tuning failed to fix. **Rule:** when iterative first-principles fixes aren't converging on a problem that has known prior art in the field, *stop guessing and do desk research*. Symptoms that should trigger desk research: (a) ≥ 2 successive structural fixes failed to converge; (b) the failure mode has a recognizable name in graphics literature ("dot pattern," "shading artifact at cell boundaries," "ferrofluid rendering"); (c) other implementations of the same effect exist and are findable in 1–2 web searches. The cost of desk research is small. The cost of three more iterations of guess-test-fail is large.

65. **Negotiating away components of a working reference implementation under unverified "redundancy" arguments** (V.9 Session 4.5 Phase A Ferrofluid Ocean, 2026-05-14): after desk research surfaced Robert Leitl's four-layer lighting model (Phong specular + env map + fresnel rim + iridescence palette) as the technique producing his demo's "incredible" character, I proceeded to argue each component into the trash — iridescence is "redundant with aurora," fresnel rim is "redundant with thin-film F0," Phong specular contradicts "mirror-reflects-sky." Each redundancy claim was unverified hand-wave reasoning; Matt called it out: *"I had you review Leitl's demo to get ideas and now it appears that you have rejected all of the ideas you found within it."* The components were mathematically *different operations* on different geometric domains — Leitl's demo character comes from all four together, not from any single one. **Rule:** when adopting a working reference implementation, the default is to adopt the components that produce its visual character verbatim and adapt only what differs in *context* (scale, audio routing, scene type). "Redundancy" claims against components of a working reference require rendering proof of the claim, not first-principles math. The failure mode is: anchor on prior paradigm → find reasons to subtract from reference → end up with neither paradigm working. **Tell-tale phrasing of the failure:** "I think X is redundant with Y" without having tested removal. If you catch yourself writing that sentence, you are about to repeat this failure.

67. **Routing the same audio timescale to two different visual layers** (Ferrofluid Ocean rounds 56–65, 2026-05-17 → 2026-05-18). Round 50 established the constant-field premise (spike geometry not audio-coupled). Rounds 56/60 tried to layer "subtle music response" back onto the spike heights via `bass_dev` — at the SAME TIMESCALE the swell amplitude was already being beat-coupled via `0.3 × drums_dev`. The two layers responding to similar beat-rate audio at different visual scales produced a "competing rhythms" reading: per-beat spike pulse AND per-beat swell pump moving simultaneously, encoding the same musical information twice through two different visual channels. Round 61 tried gating the spike pulse to `bar_phase01` (downbeat-only) — produced a different defect because bar boundaries don't align with bass kicks. Round 63 reverted to constant spikes. Round 65 finally landed the right configuration: REMOVE the drums coupling from swell amplitude (swell becomes arousal-only, slow), THEN reactivate per-beat spike-height response. With only one layer carrying the per-beat signal, the spike pulse reads as intended response without competition. **Rule:** when adding audio reactivity to a new visual layer, audit which other layers are responding to primitives at similar timescales. Don't route per-beat audio into two layers; don't route slow-arousal audio into two layers either. Each visual layer should consume one primitive at one characteristic timescale. **Architectural test for a new preset's audio-reactivity routing:** make a small table of (visual layer × audio primitive × timescale). If two layers share a primitive (or two primitives at the same timescale), that's the bug — the music will overdrive the same information through two visual channels and read as "fighting itself." Same lesson independent of preset: the architecture is one-primitive-per-layer.

73. **Don't build what's already been built — rebuilding from first principles a system that already exists as a working, code-available reference, *especially one the user explicitly provided*** (Murmuration MM.1→MM.3, 2026-06-03). At the MM.1 kickoff Matt supplied the canonical flocking references (Robert Hodgin *Murmuration*, **Rama Hoetzlein flocking**, techcentaur boids, the McGill analysis). I *cited* them in the design doc and then built a **force-based** boids substrate (sep/align/cohesion as summed force vectors + a global roost-attractor leash) and hand-derived an **injected curl "turning wave"** for beats, then tuned it across many rounds — MM.2, MM.3, and a live **M7 failure** where the forces tore the flock apart (see `project_deviation_primitive_real_range`). Only when Matt asked "*how much have you used the reference codebases I provided?*" did I actually read them: the real reference — **Hoetzlein's Flock2 (2024, published in J. Theoretical Biology, MIT-licensed code)** — is a *structurally different and better* model that natively produces everything I was hand-deriving. Neighbor influence is a **desire to turn** (orientation targets, quaternion dynamics), not a force vector; the traveling **dark bands EMERGE** from alignment+avoidance coupling (I was *injecting* them); cohesion is a **peripheral-boundary turn** (I used a roost leash that clumps/freezes); and it is **stable under perturbation by construction** (force-summing is *why* mine shredded under audio). I built a worse version of a solved problem and burned an M7 round on it. **Discriminator:** if a reference (paper, repo, demo) for the *exact* system exists — doubly so if the user handed it to you — READ AND PORT IT before writing a line of your own derivation. "I cited it in the design doc" is **not** using it. The tell-tale is iterating on tuning rounds to coax behavior the reference already specifies (orientation waves, cohesion-without-clumping). This is the **parent rule** of FA #64 (do desk research once first-principles fixes stop converging) and the former FA #70 (port the reference's loop *wholesale*, don't approximate it piece-by-piece) — those govern *how* to use a reference; #73 governs *using it at all*. See `project_flock2_reference` for the model + parameters to port.

---

## Authoring Discipline — Process Failures to Not Repeat

Operational rules for *how to work*, distilled from past failure cycles (Drift Motes / D-102, Ferrofluid, Aurora Veil, Phase MD). They apply at every scope, including strategy/product-commitment scope: a strategy decision is a forecast until evidence converts it — commit decisions when the work has produced evidence, not before. When a strategic commitment is being drafted without empirical input from the work it governs, stop and bring the gap to Matt.

**Preset-session discipline lives in [docs/PRESET_SESSION_CHECKLIST.md](docs/PRESET_SESSION_CHECKLIST.md)** — musical-role-first, temporal contract, the three-part concept bar, production-pipeline testing obligations, design grounding priority, and evidence-based closeout rules. Mandatory reading at the start of any preset increment (moved there from this section at RB.2-2).

**The next response to pushback must change the answer, not justify it.** The failure mode is producing structured analysis — pros/cons lists, three-part frames — as a substitute for thinking. If a reply has more structure than substance, delete the structure. Real thinking changes the answer; decorating the existing answer with more framework is cope.

**"Reusable infrastructure" is not a defense for a failed concept.** Deleted-concept code does not earn preservation as "kernel waiting for the right concept" (D-097: siblings, not subclasses). If "infrastructure" appears in a defense of keeping deleted-concept code, the defense is wrong.

**Verify against the artifact before asserting facts about it.** The verification cost (one grep, one `git log`, one file read) is always less than the cost of being corrected. Default to verification when the claim is checkable.

**Treat Matt's fidelity warnings as constraints, not discussion points.** If Matt says, from observed past sessions, that a fidelity target is out of reach — that is data, not a debate prompt. Pitch only within the achievable bar, or say "I cannot deliver this" upfront.

**Decisions presented to Matt: product-level language, benefits and trade-offs, a recommendation with a default.** Matt is product/design lead, not a peer engineer. Frame options in user-visible terms ("how dense are the spikes," not "particle count 256/512/1024"); name what the user sees or feels under each option; include a recommendation he can accept without doing engineering math. Only bring decisions with product-level consequences (visual character, motion feel, audible behaviour, UX flow) — engineering implementation choices are Claude's responsibility. If answering would require Matt to know implementation details, the question is wrong: reframe at the product level or decide yourself.

**Escalation thresholds — stop and bring the gap to Matt, do not start the next increment, when:** two consecutive M7 reviews return negative feedback whose root cause you cannot articulate; a concept pitch fails the three-part bar; you catch yourself producing structure as a substitute for an answer; a "reusable infrastructure" argument is forming; the one-sentence "what I now believe about why this preset is failing" hasn't changed between rounds. The cost of pausing is small. The cost of another day of mechanical iteration on a broken concept is high.

---

## What NOT To Do

- Do not write a feature's `@Published` surface on one code path without clearing it on the complementary path. A publisher retains its last value indefinitely; if a feature populates it on path A (e.g. LF track-change) but a parallel mode (e.g. streaming track-change, or session-boundary) never writes it, the stale value leaks across the mode transition. LF.6's `currentTrackArtworkData` was written on the LF path but not the streaming path → the prior LF session's album art rendered against every streaming track (BUG-024). When you add a `@Published` that a feature writes, enumerate every path that changes the underlying context (every track-change callback, every `.connecting`/`.ended` session-boundary observer) and write-or-clear it on each. Pair the clear in the same MainActor tick as the sibling publisher (e.g. title + artwork together) so consumers never observe a half-updated surface.

---

## Current Status

The roadmap and increment status table live in [docs/ENGINEERING_PLAN.md](docs/ENGINEERING_PLAN.md). Recently-landed work is in `git log --oneline -30`. Known issues and active defects are in [docs/QUALITY/KNOWN_ISSUES.md](docs/QUALITY/KNOWN_ISSUES.md).

For a snapshot of what's currently in flight, what just shipped, and what's next: `git log --since="2 weeks ago" --oneline` plus `docs/ENGINEERING_PLAN.md` open the right surfaces in under thirty seconds.

The historical changelog formerly inline here grew to ~190 lines and became a doc-sync trap. Recent-increment narrative now lives in commit messages and `ENGINEERING_PLAN.md` entries; CLAUDE.md no longer mirrors it.

---

## Development Constraints

- **Team**: Matt (product/design direction) + Claude Code (implementation).
- **Platform**: macOS only. Mac mini primary dev/deploy target.
- **Performance target**: 60fps at 1080p on Apple Silicon.
- **Dependencies**: Minimize external. Prefer Apple frameworks. Linked: Metal, MetalKit, MetalPerformanceShadersGraph, AVFoundation, Accelerate, ScreenCaptureKit (Info.plist only), MusicKit.
- **Learning stays local**: On-device only. No cloud, no telemetry.
- **License**: MIT.
- **Git history is maintained on github.com/hoaxpoet/phosphene.** Each increment lands as one or more commits with the increment ID in the message (e.g., `[SB.1] Routing: convert drums to drumsEnergyDev (D-026)`). For change diagnosis, prefer `git log`, `git diff`, and `git bisect` over reconstructing from documentation. `ENGINEERING_PLAN.md` and `DECISIONS.md` remain authoritative for intent and rationale; git is authoritative for what changed.
