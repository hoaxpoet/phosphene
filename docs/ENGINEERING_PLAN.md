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

### Increment 3.5.4.3 — v3.1 palette tuning ✅

Data analysis of the v2 diagnostic session (`2026-04-16T17-33-10Z`, 3,749 active frames on Love Rehab) surfaced three palette-level issues that the v3 fix alone did not address:

1. **Palette rotation too slow**: `accumulatedAudioTime × 0.04` only advanced 0.20 over 64 seconds of playback (20% of one color cycle). All sampled frames read as the same teal because the palette barely rotated. Bumped to × 0.15 — one full cyan→magenta→yellow cycle every ~7 seconds of active audio.
2. **Spatial hue spread too narrow**: peak pixels exist where noise n ∈ [0.55, 1.0], so `n × 0.45` capped the peak contribution at 0.20 — all peaks in a single frame looked the same hue. Bumped to × 0.9 — doubles per-peak variation so different ridges show different colors.
3. **Valley brightness too low**: `palette(phase + 0.5) × 0.08` was drowned out by the valence-tinted IBL ambient; valleys read as uniform dark brown rather than complementary palette color. Bumped × 0.08 → × 0.15.

Same regression gate. Landed alongside v3 fixes.

### Increment 3.5.4.4 — v3.2 "pulse-rate too fast" + sky tint ✅

Matt's visual review of v3.1 (session `2026-04-16T18-24-43Z` on Love Rehab):
1. **"Pulsing faster than the beat"** — v3.1 had ~35% of the terrain classified as peaks (smoothstep lo=0.50 sat right at the fbm mean), noise shimmer at `audioTime × 0.06` drifting high-octave detail fast, and palette rotation at 0.15 — all continuous, non-beat-locked motion. Beat-aligned flares (flare, strobe, kick) existed but drowned in the background activity.
2. **"Neutral gray backdrop"** — v3's fog fix exposed the raw `rm_skyColor` sky, which skipped the `scene.lightColor` multiplier that fog already used. On a preset with a warm `[1, 0.94, 0.84]` light, the sky stayed blue-gray.

Fixes:
- Peak coverage: smoothstep window `(0.50, 0.55) → (0.56, 0.60)` — peaks now ~15% of scene (linocut "highlights on paper"), ridge band `(0.495, 0.51) → (0.555, 0.565)`.
- Noise time scale `0.06 → 0.015` (4× slower high-octave drift).
- Palette rotation `0.15 → 0.08` (~1 cycle per preset duration).
- **Shared fix** (RayMarch.metal:208): miss/sky pixels now multiplied by `scene.lightColor.rgb`, matching the fog-colour treatment. Benefits every ray-march preset with a non-white light colour (Glass Brutalist, Kinetic Sculpture, VL).

Same regression gate.

### Increment 3.5.4.5 — v3.3: correct beat driver (f.bass, not f.beat_bass) ✅

Matt flagged that v3.2 pulses still didn't sync with the driving kick on Love Rehab. Session `2026-04-16T18-44-45Z` diagnostic:

**Rising-edge analysis of `f.beat_bass` in a 4-second window** revealed intervals of **410/403/421/397/435/418/431/399/488 ms** → mean **420ms = 143 BPM**. Love Rehab is 125 BPM (480ms intervals). **Local-maxima analysis of the continuous `f.bass`** revealed intervals of **499/526/495/504/531/452/549 ms** → mean **508ms = 118 BPM**, within normal variation of the real 125 BPM kick.

**Root cause**: `f.beat_bass` has a 400ms cooldown (CLAUDE.md "Onset Detection"). On tracks with dense off-kick bass content (syncopated basslines, double-time sub-bass), the cooldown causes beat_bass to phase-lock to the 400ms window itself rather than the real kick — producing a consistent phantom tempo that's faster than the music. This is a music-dependent failure mode of the onset detector, not a VL bug, but it affects any preset that reads `f.beat_bass` directly.

**Fix (VL-local)**: Switched all beat-aligned drivers from `f.beat_bass` to `smoothstep(0.22, 0.32, f.bass)`. `f.bass` is the continuous 3-band bass energy with no cooldown gating — its peaks naturally align with real kicks. Smoothstep shape gives clean 0→1 transitions matching the kick rhythm. Also removed the `0.4 × f.mid_att` contribution from `slowAmp` — mid band has ~4.6 onsets/sec (hi-hat/clap) on Love Rehab, which was leaking a non-kick rhythm into the terrain amplitude.

**Out of scope for this increment**: `f.beat_bass` cooldown-phase-lock affects other presets (Kinetic Sculpture, Glass Brutalist via shared Swift path, Ferrofluid Ocean). Worth following up on at the engine level — either shorten cooldown, or prefer a stem-separated kick onset (when `stems.drumsBeat` is fixed — session data also showed it firing only 2 times in 90s, which is a separate engine bug).

Same regression gate.

### Increment 3.5.4.6 — v3.4: use f.bass_att (pre-smoothed), not f.bass threshold ✅

Matt flagged v3.3 beat sync was still wrong AND motion was too sharp. Session `2026-04-16T18-56-59Z` diagnostic revealed:

**v3.3's `smoothstep(0.22, 0.32, f.bass)` fires at 65 BPM on a 125 BPM track** — half tempo. Root cause: Love Rehab's f.bass peaks in this session range 0.20–0.31. Kicks at the low end (0.20–0.23) never cleanly cross the 0.22 threshold, so only LOUDER kicks trigger a rise. Result: phantom half-tempo rhythm.

**Smoothstep with narrow range (0.22, 0.32) produces near-binary 0→1 output.** That's the "sharp, less smooth" character — visible motion was a 2-frame transition rather than a gradual envelope.

Cross-driver analysis tested five alternatives against the 125 BPM target:
- `smoothstep(0.22, 0.32, f.bass)` — 65 BPM (current v3.3, half-tempo)
- `smoothstep(0.13, 0.32, f.subBass)` — 111 BPM (better)
- `smoothstep(0.10, 0.25, f.bass_att)` — 121 BPM ✓
- `smoothstep(0.08, 0.22, f.bass_att)` — **127 BPM** ✓✓
- `f.bass_att × 4 clamped` — 126 BPM ✓

**Fix (v3.4)**: drive everything from `f.bass_att` (the 0.95-smoothed bass band). It catches every kick via smoothing (no threshold-miss), is inherently smooth (no sharpening artefacts), and tracks at 127 BPM on a 125 BPM track. Single driver replaces the two-stage design:
- `sceneSDF`: `audioAmp = clamp(f.bass_att × 3.5, 0, 2.0)` (was slow `f.bass_att` + sharp `smoothstep(f.bass) × 0.40`)
- `sceneMaterial`: `drumsBeatFB = smoothstep(0.06, 0.25, f.bass_att)` (was `smoothstep(0.22, 0.32, f.bass)`)

Same regression gate.

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
