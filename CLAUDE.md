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

Every increment — engine, preset, UX, docs, infrastructure — ends by invoking the **`closeout` skill** (`.claude/skills/closeout/`; auto-applies when you finish an increment or are about to commit/push). It is the canonical home of the 8-part closeout report, the mandatory `docs/ENGINEERING_PLAN.md` + `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` updates, the durable-learnings-stay-in-docs rule, the `[<increment-id>] <component>: <description>` commit format (prefer small commits), and the stop-and-report triggers.

**Do not push to the remote without Matt's explicit approval.** Local `main` commits stay local. `git push` requires "yes, push" in the chat — even when the work is clearly green and clearly Matt's request. Pushing remains a separate decision. (Safety-critical: stays always-loaded.)

## Documentation Pruning & Token Budget

The pruning pass (every tenth increment or every two weeks) and the D-161 rulebook ratchet (token budget, admission test, violated-twice-→-mechanize) are the canonical content of the **`doc-pruning` skill** (`.claude/skills/doc-pruning/`; auto-applies on a pruning pass, when CLAUDE.md nears its cap, or when adding an always-loaded rule).

**Token cap (governs this file):** CLAUDE.md stays ≤ 7,000 estimated tokens (`wc -w` × 1.35), gated by `DocIntegrityTests`. Adding above the cap requires demoting or retiring equal mass in the same commit (one-in-one-out).

---

## Defect Handling Protocol

Any defect — a `BUG-*` ID, a P0/P1/P2 report, a regression, a user-reported failure — is worked under the **`defect-handling` skill** (`.claude/skills/defect-handling/`; auto-applies when you pick up a defect). It is the canonical home of the evidence-before-implementation gate, the instrument → diagnose → fix → validate → release-notes process for P0/P1, the fix-increment doc obligations (`docs/QUALITY/KNOWN_ISSUES.md` + `docs/RELEASE_NOTES_DEV.md`), the domain-specific artifact table (beat-sync / stem-routing / preset-fidelity / renderer), and the manual-validation requirements (musical feel, visual fidelity, UX flow). Reference docs: `docs/QUALITY/DEFECT_TAXONOMY.md`, `docs/QUALITY/BUG_REPORT_TEMPLATE.md`, `docs/QUALITY/KNOWN_ISSUES.md`.

---

## Audio Data Hierarchy — The Most Important Design Rule

**Learned in the Electron prototype and validated across every preset since: visuals driven primarily by continuous energy feel locked to the music; visuals driven primarily by raw live beat detections feel out of sync.** Continuous energy (`bass`/`mid`/`treble` bands, driven from the deviation primitives `bassRel`/`bassDev` per D-026 — never absolute thresholds on AGC-normalized values, FA #31) is the DEFAULT PRIMARY DRIVER. Beat-locked motion is valid only on the cached `BeatGrid`, not raw live onsets (±80 ms jitter), and only under the Layer-4 constraints (beat-irregular tracks excluded D-154; bounded per-beat footprint + steady luminance D-157).

The full five-layer hierarchy (spectrum/waveform textures, spectral features, beat events, pre-analyzed vs. real-time stems) and the **Cold-Start Phase Contract** are the canonical content of the **`preset-session` skill** (`.claude/skills/preset-session/`; auto-applies for any preset increment). Cold-start headline: automated beat-phase derivation was empirically falsified and retired (Matt's Choice A, 2026-05-25) — **do not iterate**; ungated beat accents fire wrong-phase at track start, so presets that need suppression implement it themselves. Full history: [`docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`](docs/CAPABILITY_REGISTRY/BEAT_SYNC.md) §Cold-Start Phase Contract.

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
| #27, #31, #67 | `.claude/skills/preset-session/` (full text; DOC.9 — fire only during preset work, exactly when that skill loads) |
| #64, #65, #73 | `.claude/skills/shader-authoring/` (full text; DOC.9 — reference/desk-research discipline, loads for shader work) |

---

## Authoring Discipline — Process Failures to Not Repeat

Operational rules for *how to work*, distilled from past failure cycles (Drift Motes / D-102, Ferrofluid, Aurora Veil, Phase MD). They apply at every scope, including strategy/product-commitment scope: a strategy decision is a forecast until evidence converts it — commit decisions when the work has produced evidence, not before. When a strategic commitment is being drafted without empirical input from the work it governs, stop and bring the gap to Matt.

**Preset-session discipline lives in [docs/PRESET_SESSION_CHECKLIST.md](docs/PRESET_SESSION_CHECKLIST.md)** — musical-role-first, temporal contract, the three-part concept bar, production-pipeline testing obligations, design grounding priority, and evidence-based closeout rules. Mandatory reading at the start of any preset increment (moved there from this section at RB.2-2).

**The next response to pushback must change the answer, not justify it.** The failure mode is producing structured analysis — pros/cons lists, three-part frames — as a substitute for thinking. If a reply has more structure than substance, delete the structure. Real thinking changes the answer; decorating the existing answer with more framework is cope.

**"Reusable infrastructure" is not a defense for a failed concept.** Deleted-concept code does not earn preservation as "kernel waiting for the right concept" (D-097: siblings, not subclasses). If "infrastructure" appears in a defense of keeping deleted-concept code, the defense is wrong.

**Verify against the artifact before asserting facts about it.** The verification cost (one grep, one `git log`, one file read) is always less than the cost of being corrected. Default to verification when the claim is checkable.

**Treat Matt's fidelity warnings as constraints, not discussion points.** If Matt says, from observed past sessions, that a fidelity target is out of reach — that is data, not a debate prompt. Pitch only within the achievable bar, or say "I cannot deliver this" upfront.

**Decisions presented to Matt: product-level language, benefits and trade-offs, a recommendation with a default.** Matt is product/design lead, not a peer engineer. Frame options in user-visible terms ("how dense are the spikes," not "particle count 256/512/1024"); name what the user sees or feels under each option; include a recommendation he can accept without doing engineering math. Only bring decisions with product-level consequences (visual character, motion feel, audible behaviour, UX flow) — engineering implementation choices are Claude's responsibility. If answering would require Matt to know implementation details, the question is wrong: reframe at the product level or decide yourself.

**Escalation thresholds** — the preset-scoped stop-and-bring-to-Matt triggers (unarticulable M7 root cause, concept pitch fails the three-part bar, structure-as-substitute, "reusable infrastructure" defense forming, the unchanged preset-failure sentence between rounds) are canonical in the **`preset-session` skill**. The cost of pausing is small; another day of mechanical iteration on a broken concept is high.

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
