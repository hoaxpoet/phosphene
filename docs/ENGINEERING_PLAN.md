# Phosphene — Engineering Plan

## Planning Principles

- One increment = one reviewable outcome that fits a Claude Code session.
- Product quality and show quality are both first-class.
- No new subsystem lands without tests appropriate to its risk.
- Documentation follows implementation truth, not aspiration.
- Infrastructure increments and preset increments are never bundled.

## Current State

The foundation is implemented and tested:

- Native Metal render loop with data-driven render graph
- Core Audio tap capture with provider abstraction and DRM silence detection
- FFT (vDSP 1024-point → 512 bins) and full MIR pipeline (BPM, key, mood, spectral features, structural analysis)
- MPSGraph stem separation (Open-Unmix HQ, 142ms warm predict) and Accelerate mood classifier
- Session lifecycle: `SessionManager` drives `idle → connecting → preparing → ready → playing → ended`
- Playlist connection (Apple Music AppleScript, Spotify Web API)
- Preview resolver (iTunes Search API) and batch downloader
- Batch pre-analysis with StemCache; cache-aware track-change loading (no warmup gap in session mode)
- Metadata pre-fetching (MusicBrainz, Soundcharts, Spotify search, MusicKit)
- Feedback textures, mesh shaders (M3+ with M1/M2 fallback), hardware ray tracing, ICBs
- Ray march pipeline with deferred G-buffer, PBR lighting, IBL, SSGI
- HDR post-process chain (bloom + ACES tone mapping)
- Noise texture manager (5 textures via Metal compute)
- Shader utility library (55 functions across 7 domains)
- Preset library: Waveform, Plasma, Nebula, Murmuration, Glass Brutalist

Test infrastructure: swift-testing + XCTest across unit, integration, regression, and performance categories. SwiftLint enforced. Protocol-first DI with test doubles.

## Recently Completed

### Increment 2.5.4 — Session State Machine & Track Change Behavior ✅

`SessionManager` (`@MainActor ObservableObject`, `Session` module) owns the lifecycle. `startSession(source:)` drives `idle → connecting → preparing → ready`. Graceful degradation: connector failure → `ready` with empty plan; partial preparation failure → `ready` with partial plan. `startAdHocSession()` → `playing` directly (reactive mode). `beginPlayback()` advances `ready → playing`. `endSession()` from any state → `ended`.

Key implementation decisions: `SessionState`/`SessionPlan` live in `Session/SessionTypes.swift` (not `Shared`) because `Shared` cannot depend on `Session`. Cache-aware track-change loading already existed in `resetStemPipeline(for:)` from Increment 2.5.3 — no changes required there. `VisualizerEngine` gained a `sessionManager: SessionManager?` property; the app layer wires `cache → stemCache` on state transition to `.ready`.

11 tests.

### Increment 3.5.2 — Murmuration Stem Routing Revision ✅

Replaced the 6-band full-mix frequency workaround with real stem-driven routing via `StemFeatures` at GPU `buffer(3)`.

`Particles.metal` compute kernel gains `constant StemFeatures& stems [[buffer(3)]]`. Routing: **drums** (`drums_beat` decay drives wave front position) → turning wave that sweeps across the flock over ~200ms, not instantaneously; direction alternates per beat epoch; **bass** (`bass_energy`) → macro drift velocity and shape elongation; **other** (`other_energy`) → surface flutter weighted by `distFromCenter` (periphery 1.0×, core 0.25×); **vocals** (`vocals_energy`) → density compression via `densityScale = 1 - vocals * 0.22` applied to `halfLength` and `halfWidth`.

Warmup fallback: `smoothstep(0.02, 0.06, totalStemEnergy)` crossfades from FeatureVector 6-band routing to stem routing. Zero stems → identical behavior to previous implementation.

`ProceduralGeometry.update()` gains `stemFeatures: StemFeatures = .zero` parameter. `Starburst.metal` gains `StemFeatures` param; `vocals_energy` shifts sky gradient ≤10% warmer.

8 new tests in `MurmurationStemRoutingTests.swift`. 288 swift-testing + 91 XCTest = 379 tests total.

### Increment 3.5.4 — Volumetric Lithograph Preset ✅

New ray-march preset: tactile, audio-reactive infinite terrain rendered with a stark linocut/printmaking aesthetic. Uses the existing deferred ray-march pipeline; no engine changes required.

`PhospheneEngine/Sources/Presets/Shaders/VolumetricLithograph.metal` defines only `sceneSDF` and `sceneMaterial`; the marching loop and lighting pass come from `rayMarchGBufferPreamble`.

- **Geometry:** `fbm3D` heightfield over an infinite XZ plane. The noise's third axis is swept by `s.sceneParamsA.x` (accumulated audio time) so topography continuously morphs rather than scrolls. Vertical amplitude scaled by `clamp(f.bass + f.mid, 0, 2.5)`. SDF return scaled by 0.6 to keep the marcher Lipschitz-safe on steep ridges.
- **Bimodal materials:** Valleys → `albedo=0, roughness=1, metallic=0` (ultra-matte black). Peaks → `albedo=1, roughness∈[0.06, 0.18], metallic=1` (mirror-bright). Pinched smoothstep edges (0.55→0.72) read as printed lines.
- **Beat accent:** Drum onset shifts the smoothstep window down (`lo -= drumsBeat × 0.18`) so the bright peak region *expands* across the topography on transients. The deferred G-buffer has no emissive channel, so coverage expansion is the contrast-pulse story.
- **D-019 stem fallback:** `StemFeatures` is not in scope for `sceneSDF`/`sceneMaterial` (preamble forward-declarations omit it — same as KineticSculpture). Uses `f` directly: `max(f.beat_bass, f.beat_mid, f.beat_composite)` for the drum-beat fallback (CLAUDE.md failed-approach #26 — single-band keying misses snare-driven tracks); `f.treble * 1.4` for the "other" stem fallback (closest single-band proxy for the 250 Hz–4 kHz range).
- **Pipeline:** `["ray_march", "post_process"]` — SSGI intentionally skipped to preserve harsh, high-contrast shadows.
- **JSON:** `family: "fluid"`, low-angle directional light from above-side, elevated camera looking down at terrain, far-plane 60u, `stem_affinity` documented (drums→contrast_pulse, bass→terrain_height, other→metallic_sheen).

Verified by the existing `presetLoaderBuiltInPresetsHaveValidPipelines` regression gate, which compiles and renders every built-in preset through the actual G-buffer pipeline. No new test files required — the gate covers the new preset automatically.

### Increment 3.5.4.1 — Volumetric Lithograph v2 ✅

Session recording (`~/Documents/phosphene_sessions/2026-04-16T16-44-51Z/`, 2,633 frames against Love Rehab — Chaim) revealed four problems with v1: beat fallback `max(beat_bass, beat_mid, beat_composite)` was saturated 86% of the time (median 0.62, p90 1.0) so the peak/valley boundary flickered every frame; pure-grayscale palette read as sepia, not psychedelic; `f.treble × 1.4` polish driver was effectively zero (treble mean 0.0006); and `scene_fog: 0.025` produced an unwanted hazy band across the upper third because the camera was looking down past the fogFar = 40u line.

v2 changes:
- **Calmer motion**: terrain amplitude switched to attenuated bands `f.bass_att + 0.4 × f.mid_att`; `VL_DISP_AUDIO_AMP` 3.4 → 1.8; noise time scale 0.15 → 0.06; noise frequency 0.18 → 0.12 (larger features, slower morph).
- **Selective beat**: `pow(f.beat_bass, 1.5) × 0.7` replaces the saturated `max(...)` — only strong kicks register.
- **Beat as palette flare, not coverage shift**: peak/valley smoothstep window stays geometrically stable; transients push peak palette into HDR bloom instead of flickering the boundary.
- **Sharper edges**: smoothstep window tightened (0.55, 0.72) → (0.50, 0.55); added a thin ridge-line seam (0.495 → 0.51) as a third low-metallic stratum that reads as a luminous "cut paper" highlight.
- **Psychedelic palette**: `palette()` from `ShaderUtilities.metal:576` (IQ cosine palette — first preset to use it) drives peak albedo from `noise × 0.45 + audioTime × 0.04 + valence × 0.25`. Cyan-magenta-yellow rotation via `(0, 0.33, 0.67)` phase shift. Albedo IS F0 for metals (RayMarch.metal:239) so saturated colors produce saturated reflections.
- **Stem-proxy correctness**: `sqrt(f.mid) × 1.6` replaces `f.treble × 1.4` for the polish driver — `f.mid` (250 Hz–4 kHz) overlaps the actual "other" stem range, and `sqrt` boost handles AGC-compressed real-music values.
- **Atmosphere**: `scene_fog` 0.025 → 0; `scene_far_plane` 60 → 80; `scene_ambient` 0.04 → 0.06; camera lowered to `[0, 6.5, -8.5] → [0, 0, 7]` so fewer sky pixels, more terrain.

Same regression gate covers compilation/render. No new tests.

### Increment 3.5.4.2 — Volumetric Lithograph v3 + shared fog-fallback bug fix ✅

Two issues surfaced during v2 visual review on Love Rehab:

**Bug 1 (shared infra):** `PresetDescriptor+SceneUniforms.makeSceneUniforms()` line 85 had a broken `scene_fog == 0` fallback: it reused `uniforms.sceneParamsB.y` which starts at SIMD4 default 0. The shader formula `fogFactor = clamp((t - 0) / max(0 - 0, 0.001), 0, 1)` then saturates to 1.0 for any terrain hit — so "no fog" actually produced **maximum fog everywhere**. Fixed: fallback now returns `1_000_000` (effectively infinite fogFar), matching the intuitive "0 means no fog" semantic. No test impact — no existing preset set `scene_fog: 0`.

**Rebalance (v3):** v2 over-corrected. `pow(f.beat_bass, 1.5) × 0.7` with `× 0.6` palette brightness multiplier produced visually inert beat response on energetic music — ACES squashed the boost back into SDR before post-process bloom could amplify it. v3 changes:
- Drum-beat fallback: `pow(f.beat_bass, 1.2) × 1.5` (saturates at beat_bass ≈ 0.7 rather than never).
- Palette flare: × 1.5 (was × 0.6) — peaks push to 2.5× albedo on strong kicks, bloom-visible.
- Ridge seam strobe: `× (1.4 + beat × 2.0)` — the cut-line itself strobes at up to 3.4× brightness.
- Coverage expansion on beat: 0.03 smoothstep shift (v1 had 0.18 which flickered every frame; v2 had 0 which was dead).
- Transient terrain kick in `sceneSDF`: `f.beat_bass × 0.35` added to attenuated baseline amp — landscape breathes on kicks without replacing the slow-flowing base.

Same regression gate covers both changes.

---

## Immediate Next Increments

These are ordered by dependency. Each has done-when criteria and verification commands.

## Phase 4 — Orchestrator

The Orchestrator is the product's key differentiator. It is implemented as an explicit scoring and policy system, not a black box.

### Increment 4.1 — Preset Scoring Model

**Scope:** `Orchestrator/PresetScorer.swift`. Given a `TrackProfile` and the current session context, score every preset in the catalog for suitability. Inputs: energy trajectory, mood quadrant, stem salience, tempo range, key mode. Per-preset: stem affinity match, mood compatibility, fatigue risk (time since last use of this preset's family), transition compatibility with the current preset, performance cost (render pass complexity vs device tier).

**Done when:**
- `PresetScorer.score(preset:track:context:) -> Float` returns a normalized 0–1 score.
- Scores are deterministic for the same inputs.
- 10+ unit tests covering: high-energy track → high-energy preset ranked first, mood mismatch penalized, same-family repeat penalized, Tier 1 device excludes expensive presets, stem affinity match boosts score.
- Protocol `PresetScoring` for test injection.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 4.2 — Transition Policy

**Scope:** `Orchestrator/TransitionPolicy.swift`. Decides *when* and *how* to transition between presets. Inputs: structural analysis (section boundaries from StructuralAnalyzer), lookahead buffer state, current preset elapsed time vs declared duration, energy trajectory. Outputs: `TransitionDecision` (timing, type: crossfade/cut/morph, duration).

**Done when:**
- Transitions land on section boundaries when confidence > threshold (prefer structural analysis over timer).
- Timer-based fallback when no boundaries detected.
- No preset repeats its family twice in succession.
- Crossfade duration scales with energy (faster transitions during high-energy passages).
- 8+ unit tests with synthetic StructuralPrediction inputs.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 4.3 — Session Planner

**Scope:** `Orchestrator/SessionPlanner.swift`. Before playback starts, produces a `SessionPlan`: ordered list of (TrackIdentity, PresetDescriptor, TransitionTiming) for the entire playlist. Uses PresetScorer and TransitionPolicy.

**Done when:**
- Given a list of TrackProfiles, produces a complete session plan.
- Plan respects: no consecutive same-family, mood arc across the playlist, performance budget per device tier.
- Pipeline states for all planned presets are pre-compiled (eliminates runtime compilation hitches during transitions).
- 6+ unit tests with curated 5-track playlists covering mood variety, family diversity, and tier constraints.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 4.4 — Golden Session Test Fixtures

**Scope:** `Tests/PhospheneEngineTests/Orchestrator/GoldenSessionTests.swift`. Curated playlists with expected preset sequences, expected transition windows, and forbidden choices.

**Done when:**
- 3 golden sessions defined: one high-energy electronic, one mellow jazz, one genre-diverse mix.
- Each fixture specifies: acceptable preset families per track, forbidden families, transition window tolerance.
- Tests pass against the current PresetScorer + TransitionPolicy + SessionPlanner.
- Any future Orchestrator change that breaks a golden session test is a regression.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 4.5 — Live Adaptation

**Scope:** `Orchestrator/LiveAdapter.swift`. During playback, the Orchestrator adapts its session plan based on real-time MIR data. When live structural analysis reveals boundaries the 30s preview missed, adjust transition timing. When live mood diverges from pre-analyzed mood, consider mid-track preset adjustment.

**Done when:**
- Plan adapts when live section boundaries arrive that differ from preview estimates by >5s.
- Adaptation is conservative: mid-track preset changes are rare and only triggered by significant mood divergence.
- Adaptation decisions are logged.
- 6+ unit tests with synthetic live MIR data that diverges from pre-analyzed profiles.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 4.6 — Ad-Hoc Reactive Mode

**Scope:** Wire the Orchestrator's reactive mode (no playlist, live MIR only). States: `idle` → `listening` → `ramping` → `full`. Heuristic preset selection from live energy, mood, and structural data as they accumulate.

**Done when:**
- Orchestrator produces reasonable preset selections with zero pre-analyzed data.
- After ~30s of listening, preset choices reflect the music's character.
- Transitions still land on detected section boundaries.
- 6+ unit tests with synthetic progressive MIR accumulation.

**Verify:** `swift test --package-path PhospheneEngine`

---

## Phase 5 — Preset Certification Pipeline

### Increment 5.1 — Enriched Preset Metadata Schema

**Scope:** Extend `PresetDescriptor` JSON schema with fields the Orchestrator needs for intelligent selection: `visual_density` (0–1), `motion_intensity` (0–1), `color_temperature_range` ([cool, warm]), `fatigue_risk` (low/medium/high), `transition_affordances` ([crossfade, cut]), `section_suitability` ([ambient, buildup, peak, bridge, comedown]), `complexity_cost` (estimated ms at 1080p on Tier 1 / Tier 2). Back-fill all existing preset JSON files.

**Done when:**
- Schema documented. All existing presets have complete metadata.
- `PresetDescriptor` parses all new fields with sensible defaults for missing keys.
- `PresetScorer` (Increment 4.1) uses the new metadata.
- 4+ unit tests for parsing, defaults, and round-trip.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 5.2 — Preset Acceptance Checklist (Automated)

**Scope:** A test suite that runs against every preset in the catalog. Presets fail if they: overreact to onset jitter (beat response > 2× continuous response), clip into white (any pixel > 1.0 pre-tonemap for non-HDR paths), produce repetitive motion at low energy, or lack readable form at zero energy.

**Done when:**
- Test harness renders each preset with synthetic audio fixtures (silence, steady energy, beat-heavy, quiet passage).
- Frame statistics collected: max pixel value, motion variance, form complexity metric.
- All current presets pass the checklist.
- New presets cannot land without passing.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 5.3 — Visual Regression Snapshots

**Scope:** Render each preset with fixed audio fixtures at deterministic frame numbers. Compare frame statistics or perceptual hashes against golden references. Detects when a shader change makes a preset muddy, overexposed, banded, or visually dead.

**Done when:**
- Golden snapshots generated for all presets at 3 fixture configurations.
- Perceptual hash comparison with configurable tolerance.
- Regression test fails when a preset's visual output changes beyond tolerance.
- Snapshot update script for intentional changes.

**Verify:** `swift test --package-path PhospheneEngine`

---

## Phase 6 — Progressive Readiness & Performance Tiering

### Increment 6.1 — Progressive Session Readiness

**Scope:** Replace the binary preparation model with graduated readiness. States: `preparing`, `ready_for_first_tracks` (first N tracks analyzed), `partially_planned` (visual arc provisional), `fully_prepared` (all tracks analyzed, full plan), `reactive_fallback` (no preparation possible).

**Done when:**
- User can start playback when the first 3 tracks are prepared (don't block on full playlist).
- SessionManager exposes readiness level.
- Orchestrator operates in partial-plan mode with confidence flags.
- 6+ unit tests covering each readiness state and transitions.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 6.2 — Frame Budget Manager

**Scope:** `Renderer/FrameBudgetManager.swift`. Monitors frame timing and dynamically downshifts preset complexity when budget is exceeded. Quality governor can disable: SSGI, bloom, ray march step count reduction, particle count reduction, mesh density reduction.

**Done when:**
- Frame budget target configurable (default 16.6ms for 60fps).
- When 3 consecutive frames exceed budget, governor activates lowest-impact reduction first.
- When frames recover, governor restores quality after sustained recovery (hysteresis).
- Per-device tier budgets (Tier 1 stricter than Tier 2).
- 6+ unit tests with synthetic frame timing sequences.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 6.3 — ML Dispatch Scheduling

**Scope:** Coordinate MPSGraph stem separation with heavy render passes. Stem separation runs on GPU — it should avoid dispatching during expensive render frames (ray march + SSGI). Use frame timing feedback to window ML dispatches into lighter render moments.

**Done when:**
- Stem separation dispatch is aware of current render pass complexity.
- During heavy render frames, ML dispatch is deferred (not dropped).
- No observable frame drops during concurrent stem separation + ray march rendering.
- 4+ unit tests with synthetic timing scenarios.

**Verify:** `swift test --package-path PhospheneEngine`

---

## Phase 7 — Long-Session Stability

### Increment 7.1 — Soak Test Infrastructure

**Scope:** Automated 2+ hour test sessions with synthetic audio. Monitor: memory growth, frame timing drift, dropped frames, state machine integrity, permission handling.

**Done when:**
- Test harness can run headless for configurable duration.
- Memory snapshots at intervals detect leaks.
- Frame timing statistics collected (p50, p95, p99, max).
- Session state machine remains valid throughout.

**Verify:** `swift test --package-path PhospheneEngine` (soak tests tagged, run separately)

---

### Increment 7.2 — Display Hot-Plug & Source Switching

**Scope:** Handle external display connect/disconnect during a session. Handle switching between capture modes (system → app → system). Handle playlist reconnection after network interruption.

**Done when:**
- Display change triggers drawable resize without crash.
- Capture mode switch preserves session state.
- Preparation resumes after network recovery.
- 6+ unit tests for each scenario.

**Verify:** `swift test --package-path PhospheneEngine`

---

## Milestones

These milestones map to product-level outcomes, not implementation phases.

**Milestone A — Trustworthy Playback Session.** A user can connect a playlist, obtain a usable prepared session, and complete a full listening session without instability. *Requires: ~~2.5.4~~ ✅, progressive readiness basics (6.1).*

**Milestone B — Tasteful Orchestration.** Preset choice and transitions are consistently better than random and pass golden-session tests. *Requires: Phase 4 complete, Increment 5.1.*

**Milestone C — Device-Aware Show Quality.** The same playlist produces an excellent show on M1 and a richer one on M4 without jank. *Requires: Phase 6 complete.*

**Milestone D — Library Depth.** The preset catalog is large enough, varied enough, and well-tagged enough for Phosphene to feel like a product rather than a tech demo. *Requires: Phase 5 complete, 10+ certified presets.*
