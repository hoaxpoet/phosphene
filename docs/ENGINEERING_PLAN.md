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

### Increment 3.5.4.7 — v4: melody-primary drivers + forward dolly ✅

Matt tested v3.4 on Tea Lights (Lower Dens — acoustic/electric guitar, no kick drum). Result: total failure. v3's bass-only drivers had nothing to track. Also asked about forward camera motion.

Session `2026-04-16T20-09-44Z` data showed:
- `f.mid_att × 15` tracks melodic phrasing at 72 BPM on Tea Lights (matches song tempo).
- `f.spectral_flux` fires at ~190 BPM on *any* timbral attack — kicks, guitar strums, vocal onsets, piano chord changes.
- Stem data (`stems.vocalsEnergy` 0.30 mean, `stems.otherEnergy` 0.26 mean) is the true melody carrier but isn't in `sceneSDF`/`sceneMaterial` preamble scope.

Changes:
- `sceneSDF audioAmp`: melody-primary blend — `0.75 × clamp(f.mid_att × 15, 0, 1.5) + 0.35 × clamp(f.bass_att × 1.2, 0, 1)`.
- `sceneMaterial accentFB`: `smoothstep(0.35, 0.70, f.spectral_flux)` replaces bass-keyed driver. Flare multipliers reduced (× 1.5 → × 0.8 peak, × 2.0 → × 1.0 ridge, 0.03 → 0.02 coverage shift) for softer ambient match.
- Palette phase adds `f.mid_att × 3.0` — colour rotates with melodic phrasing.
- Amplitude reduced 1.8 → 1.4 to pair with dolly.
- Camera lifted Y 6.5 → 7.2, FOV narrowed 60 → 55, **forward dolly at 1.8 u/s** via new switch in `VisualizerEngine+Presets.swift` (replaces ternary; pattern extensible for future presets).

### Increment 3.5.4.8 — SessionRecorder writer relock + StemFeatures in preamble ✅

Two follow-ups from v4, both explicitly requested by Matt. Bundled because both surfaced in the same diagnostic loop and both are prerequisites for clean next-iteration work.

**A. SessionRecorder writer relock.** Session `2026-04-16T20-09-44Z` lost 1,861 frames (~31s) because the writer locked to transient Retina-native drawable dimensions (1802×1202) observed for the first 30 frames, then rejected every subsequent frame at the steady-state logical-point size (901×601). The old guard was correct in spirit (avoid locking to transient launch-time dimensions) but couldn't recover when the "stable" size itself was the transient.

Fix: if the drawable arrives consistently at a different size for `writerRelockThreshold` (90) frames after initial lock, tear down the current writer, remove the partial `video.mp4`, and recreate at the new size. Conservative enough that it doesn't trigger on normal mid-session resizes (which should still be rare). Test `test_recordFrame_relocksWhenDrawableStabilisesAtDifferentSize` simulates the exact Tea Lights scenario.

**B. `StemFeatures` in `sceneSDF`/`sceneMaterial` preamble.** Opens per-preset stem routing (Milkdrop-style) to the entire ray-march preset pipeline. The preamble forward-declarations, G-buffer fragment call sites, and all 4 existing presets gain a `constant StemFeatures& stems` parameter:

- `TestSphere`, `GlassBrutalist`, `KineticSculpture`: parameter added for signature conformance, unused internally — existing visual behaviour preserved (GB still ships its Option-A design, KS still uses its validated FeatureVector routing as commented in the header).
- `VolumetricLithograph`: upgraded to true stem reads with D-019 warmup fallback. Terrain amp melody now reads `stems.other_energy + stems.vocals_energy` (with `f.mid_att × 15` fallback); accent now reads `stems.drums_beat` (with `f.spectral_flux` fallback); peak polish reads `stems.other_energy` (with `sqrt(f.mid) × 1.6` fallback). All blended via `smoothstep(0.02, 0.06, totalStemEnergy)` so the first few seconds before stem separation completes fall back gracefully to FeatureVector routing.
- Test fixtures in `RayMarchPipelineTests.swift` and `SSGITests.swift` updated to match the new signature — this actually repairs `RayMarchPipelineTests` which was failing before v4 with undefined-symbol errors because the fixture was stale for the earlier sceneMaterial signature change.

Verified: `swift test --package-path PhospheneEngine --filter PresetLoaderTests` 12/12 passing (including the full-pipeline render gate), `RayMarchPipelineTests` 10/10 passing, `SSGITests` 7/7 passing, `SessionRecorderTests` 7/7 passing (including the new relock test).

### Increment 3.5.4.9 — Per-frame stem analysis (engine-level) ✅

Session `2026-04-16T20-56-46Z` diagnostic on Tea Lights revealed the architectural root cause of repeated "terrain stops moving but colours keep changing" failures: **`StemFeatures` values in GPU buffer(3) update only once per 5-second stem separation cycle**. The uploaded `stems.csv` showed only 25 unique `drumsBeat` values across 8,987 rows (0.3% uniqueness); identical vocals/drums/bass/other energies held for 300+ consecutive frames then stepped to a new set. Any preset reading stems directly got a piecewise-constant driver with 5-second freeze-then-jump dynamics — no matter how careful the shader design.

**Root cause** (`VisualizerEngine+Stems.runStemSeparation`): after each 5s `StemSeparator.separate()` call, the engine ran a 600-frame AGC warmup loop on `stemQueue` and uploaded ONLY the final frame's features via `pipeline.setStemFeatures(features)`. The intermediate frames — which DO produce continuously-varying output when fed sliding windows of the same waveform — were discarded.

**Fix** (preserves 5s separation cadence, adds per-frame analysis):
- `runStemSeparation` now stores the separated waveforms + wall-clock timestamp under a new `stemsStateLock`, then returns. No analyzer calls or GPU uploads from `stemQueue` any more.
- `processAnalysisFrame` (called on `analysisQueue` at audio-callback rate, ~94 Hz) reads the latest stored waveforms under lock, slides a 1024-sample window through them at real-time rate (starting 5s into the 10s chunk, advancing by `elapsed × 44100` samples), runs `StemAnalyzer.analyze` on the window, and uploads the result via `pipeline.setStemFeatures`. AGC warms up naturally over the first ~60 frames of each new chunk.
- `resetStemPipeline` clears the stored waveforms on track change so stems don't leak across tracks.

**Cadence improvement**: 1 stem upload every 5000 ms → 1 upload every ~10 ms. **500× more frequent**.

**Latency**: stem features lag real audio by ~5-10s (separator works on past audio and we scan the last 5s of each chunk). Acceptable because musical sections persist longer than that. A future enhancement could shorten the chunk or overlap separations.

**Side benefit**: `stems.csv` in future SessionRecorder dumps now shows continuously-varying per-frame values instead of 5s-flat blocks, making preset diagnostics far cleaner.

**Tests**: new `StemAnalyzerTests.swift` pins the sliding-window contract so future refactors can't silently regress:
- `stemAnalyzer_slidingWindows_produceVaryingFeatures` — feeds sliding 1024-sample windows through a ramped waveform, asserts non-zero spread + smooth per-frame deltas.
- `stemAnalyzer_sameWindow_producesStableFeatures` — convergence on repeated identical input.
- `stemAnalyzer_zeroLengthWindow_returnsZeroFeatures` — safety under empty input.

Verified: 3/3 new tests pass; full suite 308/314 with only pre-existing environmental failures (Apple Music not running × 4, perf flake, network timeout).

### Increment MV-0 — Drop v4.2 stash, re-land sky-tint conditional ✅

**Landed:** 2026-04-16, commit `91f698d5`

Dropped the v4.2 git stash. Re-applied the `RayMarch.metal:208` sky-tint conditional: miss/sky pixels now multiply by `scene.lightColor.rgb` only when `sceneParamsB.y > 1e5` (fog-disabled sentinel). This restores cool-sky/warm-light contrast on Glass Brutalist and Kinetic Sculpture while preserving VolumetricLithograph's warm sky tint when `scene_fog: 0`.

All preset-pipeline regression tests passing.

### Increment MV-1 — Milkdrop-correct audio primitives ✅

**Landed:** 2026-04-16, commit `a05fd753`

`FeatureVector` expanded 32→48 floats (128→192 bytes). Nine new deviation fields derived each frame in `MIRPipeline.buildFeatureVector()`:
- `bassRel/Dev`, `midRel/Dev`, `trebRel/Dev` — centered deviation from AGC midpoint.
- `bassAttRel`, `midAttRel`, `trebAttRel` — smoothed deviation for continuous motion drivers.

`StemFeatures` expanded 16→32 floats (64→128 bytes). Eight new stem deviation fields derived in `StemAnalyzer.analyze()` via per-stem EMA (decay 0.995):
- `{vocals,drums,bass,other}EnergyRel/Dev`.

Metal preamble structs in `PresetLoader+Preamble.swift` updated to match. `VolumetricLithograph.metal` converted to deviation-based drivers as reference implementation. All other presets grandfathered. `RelDevTests.swift` (4 contract tests) gates the invariants. CLAUDE.md documents the authoring convention.

**CHECKPOINT outcome:** deviation primitives alone did not converge VL on "feels musical" — confirmed the architectural gap (missing per-vertex feedback warp) is the critical path. MV-2 proceeded as planned.

### Increment MV-2 — Per-vertex feedback warp mesh ✅

**Landed:** 2026-04-17, commit `c8cd558f`

New `mv_warp` render pass implementing Milkdrop-style 32×24 per-vertex feedback warp. Any preset opts in via `"mv_warp"` in its `passes` JSON array.

**Architecture:** Three passes per frame:
1. **Warp pass** — 32×24 vertex grid (4278 vertices). Each vertex calls preset-authored `mvWarpPerFrame()` + `mvWarpPerVertex()`. Fragment samples `warpTexture` (previous frame) at displaced UV × `pf.decay` → `composeTexture`.
2. **Compose pass** — fullscreen quad. Alpha-blends `sceneTexture` (current scene) onto `composeTexture` with `alpha = (1 - decay)`.
3. **Blit pass** — `composeTexture` → drawable. Swap warp ↔ compose for next frame.

**Key implementation details:**
- `MVWarpPipelineBundle` (public struct) holds 3 `MTLRenderPipelineState` + `pixelFormat`. Created in `applyPreset` from `PresetLoader`-compiled states.
- `MVWarpState` marked `@unchecked Sendable` because `MTLTexture` protocol is not `Sendable` in Swift 6.0.
- `SceneUniforms` is forward-declared in `mvWarpPreamble` behind `#ifndef SCENE_UNIFORMS_DEFINED` so direct (non-ray-march) presets compile without the ray-march preamble. Ray-march preamble wraps its own definition in the same guard to prevent redefinition.
- Ray-march + mv_warp handoff: `.rayMarch` renders to offscreen `warpState.sceneTexture` when `.mvWarp` is also in `activePasses`; `.mvWarp` handles drawable presentation.
- Initial texture allocation uses 1920×1080; `reallocateMVWarpTextures` fires from `drawableSizeWillChange` with actual drawable size before first frame.

**Presets converted:**
- `VolumetricLithograph` — `passes: ["ray_march", "post_process", "mv_warp"]`. Melody-driven zoom breath (`mid_att_rel × 0.003`), valence rotation, decay=0.96, terrain-coherent UV ripple from bass (horizontal) and melody (vertical) at 0.004 UV amplitude.
- `Starburst (Murmuration)` — `passes: ["mv_warp"]` (replaced `["feedback", "particles"]`). Bass breath zoom, melody rotation, decay=0.97 for long cloud smear.

**Tests:** `MVWarpPipelineTests.swift` — identity warp test (seed red, assert output stays red) and accumulation test (10 frames with blue scene, assert red decays measurably).

---

### Increment D-030 — SpectralHistoryBuffer + SpectralCartograph ✅

New `SpectralHistoryBuffer` class (Shared module): 16 KB UMA MTLBuffer at fragment buffer index 5, bound unconditionally in all direct-pass fragment encoders. Maintains 5 ring buffers of 480 samples (≈8s at 60fps): valence, arousal, beat_phase01, bass_dev, and log-normalized vocal pitch. Updated once per frame in `RenderPipeline.draw(in:)`; reset on track change via `VisualizerEngine.resetStemPipeline(for:)`.

`SpectralCartograph` preset: first `instrument`-family preset. Four-panel real-time MIR diagnostic — TL=FFT spectrum (log-frequency, centroid-driven colour), TR=3-band deviation meters (D-026 compliant: reads only `*_att_rel` and `*_dev`), BL=valence/arousal phase plot with 8-second fading trail, BR=scrolling line graphs for `beat_phase01`, `bass_dev`, and `vocals_pitch_norm`. Direct pass only.

CLAUDE.md GPU Contract corrected: buffer(0)=FeatureVector (not FFT as previously documented). buffer(4)=SceneUniforms (ray march only, not future use). buffer(5)=SpectralHistory.

New `PresetCategory.instrument` case added.

15+ new tests across `SpectralHistoryBufferTests.swift`, `SpectralCartographTests.swift`, and additions to `RenderPipelineTests.swift`.

---

### Increment D-030b — Verification fixes + InputLevelMonitor ✅

Post-D-030 live-session verification (2026-04-20) found and fixed four issues:

**BeatPredictor timing bug (critical).** `beatPhase01` was always 0 in production. Root cause: `MIRPipeline.processAnalysisFrame` calls `mir.process(... time: 0 ...)` on every frame; `BeatPredictor.update()` accumulated timing via the `time` parameter, so `now = 0` always. First onset set `lastBeatTime = 0`; the subsequent `if lastBeatTime > 0` guard was false for `0.0`, so `hasPeriod` never became true. Fixed by internal `elapsedTime` accumulation from `deltaTime` (independent of `time`); guards changed `> 0` → `>= 0`. The `BeatPredictorTests.swift` bootstrap test was also updated to advance time frame-by-frame rather than via a single `time` jump (single calls only advance by one `dt` with the new accumulator).

**SpectralCartograph silent load.** The preset JSON was missing `"fragment_function": "spectral_cartograph_fragment"`. `PresetLoader` defaulted to `"preset_fragment"` which doesn't exist in the library, causing the preset to be silently skipped at load time.

**Swift 6 @MainActor warnings.** `MTKView.currentDrawable`, `currentRenderPassDescriptor`, and `drawableSize` are `@MainActor`-isolated; accessing them from nonisolated `draw(in:)` and helper methods produced ~18 Xcode IDE warnings. Fixed by annotating `draw(in:)`, `renderFrame`, `drawDirect`, `drawWithFeedback`, `drawParticleMode`, `drawSurfaceMode`, `drawWithICB`, `drawWithMeshShader`, `drawWithMVWarp`, `drawWithPostProcess`, `drawWithRayMarch` as `@MainActor`. The `@preconcurrency import MetalKit` already in each file suppresses any conformance mismatch for the protocol requirement.

**InputLevelMonitor** (new component). A live session (2026-04-17T19-31-46Z) routed through a Multi-Output Device (BlackHole + Mac mini Speakers) produced peaks at −20 dBFS with treble fraction at 0.1% — undetectable by the existing `SilenceDetector` (which only distinguishes silent/non-silent) or by post-AGC feature values (which normalise away absolute level). `InputLevelMonitor` measures peak dBFS (21s rolling window via `vDSP_maxmgv`) and 3-band spectral balance (EMAs on squared FFT magnitudes). Classification is peak-only after session 2026-04-17T21-05-47Z showed treble-ratio thresholds produced false positives on bass-heavy tracks (Oxytocin: 0.2% treble, clean chain). 30-frame hysteresis prevents log flapping. Quality transitions logged to session.log via `VisualizerEngine+Audio`; displayed in DebugOverlay.

Also: `MusicKitBridge` unused `artistLower` removed; `SessionRecorder` `_ = try? fh.seekToEnd()` to suppress unused `UInt64?` result.

343 tests, 5 pre-existing Apple Music failures. All 3 `BeatPredictorTests` now pass with correct phase tracking.

---

## Immediate Next Increments

These are ordered by dependency. Each has done-when criteria and verification commands.

## Phase MV — Milkdrop-Informed Musical Architecture

**Why this phase exists:** six iterations on Volumetric Lithograph produced incremental fixes but never converged on "feels like a band member playing along with the music." [`docs/MILKDROP_ARCHITECTURE.md`](MILKDROP_ARCHITECTURE.md) documents the research that identified the root cause:

1. Milkdrop's audio vocabulary is **identical in scope to what Phosphene already computes** — no chord recognition, no pitch tracking, no stems. Our analysis pipeline is richer than theirs.
2. Milkdrop's `bass`/`bass_att` are **AGC-normalized ratios centered at 1.0**. Phosphene's are centered at 0.5 via the same AGC mechanism. But our presets have been authored with absolute thresholds — the wrong primitive for an AGC signal. Absolute thresholds inherently fail across tracks because the AGC divisor moves with mix density.
3. Milkdrop's "musical feel" comes from its **per-vertex feedback warp architecture**, not its audio analysis. Every preset warps the previous frame via a 32×24 grid, and motion *accumulates* over many frames. Simple audio inputs compound into rich organic motion.
4. **9 of 11 Phosphene presets did not use any feedback loop** prior to MV-2 — they rendered from scratch each frame. Ray-march presets in particular showed only instantaneous audio state. This is why they felt "disconnected" from music regardless of how cleverly tuned.

MV-0 ✅, MV-1 ✅, MV-2 ✅, MV-3 ✅ complete.

### Increment MV-3 — Beyond-Milkdrop extensions ✅

**MV-3a — Richer per-stem metadata** ✅
- `StemFeatures` expanded 32→64 floats (128→256 bytes). New per-stem fields: `{vocals,drums,bass,other}{OnsetRate, Centroid, AttackRatio, EnergySlope}` (floats 25–40), computed in `StemAnalyzer.analyze()` via `computeRichFeatures()`.
- `StemAnalyzerMV3Tests.swift`: click vs sine distinguishes attackRatio; silence gives zeros; 120-BPM click track mean onsetRate in [1.0, 3.5]/sec.

**MV-3b — Next-beat phase predictor** ✅
- New `BeatPredictor` class (IIR period estimation from onset rising edges). Feeds `beatPhase01` and `beatsUntilNext` into `FeatureVector` floats 35–36. Integrated in `MIRPipeline.buildFeatureVector()`.
- `BeatPredictorTests.swift`: phase monotonically rises 0→1; phase resets after 3× period silence; bootstrap BPM gives correct phase.
- `VolumetricLithograph.metal` updated: `approachFrac = max(0, (f.beat_phase01 - 0.80) / 0.20)` pre-beat anticipatory zoom.

**MV-3c — Vocal pitch tracking** ✅
- New `PitchTracker` (YIN autocorrelation, vDSP_dotpr). Key fix: advance to local CMNDF minimum before parabolic interpolation (finding just the first sub-threshold point causes catastrophic extrapolation on the descending slope). 80–1000 Hz gate, 0.6 confidence threshold, EMA decay 0.8.
- Feeds `vocalsPitchHz` and `vocalsPitchConfidence` into `StemFeatures` floats 41–42.
- `PitchTrackerTests.swift`: 440 Hz and 220 Hz within 5 cents; silence → 0 Hz; random noise → unvoiced.
- `VolumetricLithograph.metal` updated: `vl_pitchHueShift()` maps pitch to ±0.15 palette phase shift; gated by confidence ≥ 0.6.

**Explicitly NOT part of MV-3 (still out of scope):**
- Basic Pitch port, chord recognition via Tonic, HTDemucs swap, Sound Analysis framework

---

## Phase 4 — Orchestrator

The Orchestrator is the product's key differentiator. It is implemented as an explicit scoring and policy system, not a black box.

### Increment 4.0 — Enriched Preset Metadata Schema ✅

**Scope:** `PresetMetadata.swift` (new), `PresetDescriptor.swift` (extended), all 11 JSON sidecars back-filled.

Pulled forward from Phase 5.1 because Increment 4.1 (PresetScorer) cannot be built without the metadata it scores on. Adding the schema now eliminates a breaking change immediately after 4.1 is drafted.

**New types:** `FatigueRisk`, `TransitionAffordance`, `SongSection` (String-raw, Codable, Sendable, Hashable, CaseIterable). `ComplexityCost` struct with dual-form Codable (scalar or `{"tier1":x,"tier2":y}`). All in `PresetMetadata.swift`.

**New `PresetDescriptor` fields (all optional in JSON, fallback-on-missing, warn-on-malformed):**
`visual_density`, `motion_intensity`, `color_temperature_range`, `fatigue_risk`, `transition_affordances`, `section_suitability`, `complexity_cost`.

**Done when:** ✅ All criteria met.
- `PresetMetadata.swift` with three enums and `ComplexityCost`, all correct Swift 6 types.
- `PresetDescriptor` has 7 new fields; decoding falls back to defaults; unknown `fatigue_risk` logs warning + uses `.medium`.
- All 11 built-in preset JSON sidecars have explicit values for all 7 new fields.
- `PresetLoaderBuiltInPresetsHaveValidPipelines` regression gate still passes.
- `PresetDescriptorMetadataTests`: round-trip, defaults, malformed, complexity variants (scalar + nested), on-disk back-fill regression (6 test functions).
- D-029 in `docs/DECISIONS.md`. CLAUDE.md preset metadata table extended.

**Verify:** `swift test --package-path PhospheneEngine --filter PresetDescriptorMetadataTests`

---

### Increment L-1 — Structural SwiftLint Cleanup

**Scope:** Refactor 12 source files to eliminate all 24 remaining structural SwiftLint violations. No logic changes — pure mechanical refactoring. Verified by `swiftlint lint --strict` reporting 0 violations on active source paths, with all tests still passing.

**Background:** After the 2026-04-20 auto-fix pass, 24 structural violations remain (down from 166). These are `file_length`, `function_body_length`, `cyclomatic_complexity`, `type_body_length`, `large_tuple`, and `line_length` — rules that require file splits or helper extraction rather than auto-correction.

**Violations and fix strategy (file:line:rule):**

| File | Line | Rule | Fix |
|------|------|------|-----|
| `SessionRecorder.swift` | 46 | type_body_length (516) | Split to `SessionRecorder+Video.swift` (Video encoding MARK), `SessionRecorder+RawTap.swift` (Raw tap diagnostic MARK), `SessionRecorder+WAV.swift` (WAV writing) |
| `SessionRecorder.swift` | 150 | function_body_length (72) | Extract `setupWriters()`, `setupVideoWriter()`, `setupAudioWriter()` private helpers from `init` |
| `SessionRecorder.swift` | 397 | cyclomatic_complexity (13) + function_body_length (72) | Extract `handleVideoWriterInit()` and `handleFrameDimensionMismatch()` private helpers from `appendVideoFrame()` |
| `SessionRecorder.swift` | 793 | file_length (793) | Resolved by the type_body_length split above |
| `AudioFeatures+Analyzed.swift` | 552 | file_length (552) | Move `StemFeatures` struct (lines ~323–514) to new `StemFeatures.swift` in same directory |
| `PresetLoader+Preamble.swift` | 541 | file_length (541) | Split MV-warp preamble (line ~199 MARK) to `PresetLoader+WarpPreamble.swift` |
| `StemAnalyzer.swift` | 171 | function_body_length (96) | Extract `buildBaseFeatures()` and `applyDeviationPrimitives()` private helpers from `analyze()` |
| `StemAnalyzer.swift` | 349 | large_tuple | Define `StemRichFeatures` struct `{onsetRate, centroid, attackRatio, energySlope: Float}` to replace 4-member named tuple return from `computeRichFeatures()` |
| `StemAnalyzer.swift` | 500 | file_length (500) | Resolved by helper extraction above |
| `PitchTracker.swift` | 97 | cyclomatic_complexity (15) + function_body_length (86) | Extract 5 private helpers: `fillWindow()`, `computeDifference()`, `computeCMNDF()`, `findMinimum()`, `parabolicInterpolation()` from `process(waveform:)` |
| `MIRPipeline.swift` | 407 | file_length (407, 7 over) | Extract `buildFeatureVector()` deviation block to a private helper; or remove excess blank lines |
| `AudioInputRouter.swift` | 423 | file_length (423, 23 over) | Extract `Signal-State Handling + Tap Reinstall` MARK section to `AudioInputRouter+SignalState.swift` |
| `PresetLoader.swift` | 449 | function_body_length (103) | Extract `compilePipeline(for:)` and `compileRayMarchPipeline(for:)` private helpers from `loadPreset()` |
| `RayMarchPipeline.swift` | 184 | function_body_length (71) | Extract `makeGBufferTextures()` and `makeLightingPipeline()` private helpers from `init` |
| `RayMarchPipeline.swift` | 415 | file_length (415, 15 over) | Resolved by init helper extraction above |
| `RenderPipeline+Draw.swift` | 448 | file_length (448, 48 over) | Extract `drawWithICB` and `drawWithParticles` to `RenderPipeline+Particles.swift` |
| `RenderPipeline+RayMarch.swift` | 81 | function_body_length (83) | Extract `buildSceneUniforms()` and `applyAudioModulation()` private helpers |
| `RenderPipeline.swift` | 475 | file_length (475, 75 over) | Extract `PassManagement` MARK section to `RenderPipeline+Passes.swift` |
| `VisualizerEngine+Audio.swift` | 507 | file_length (507, 107 over) | Extract `InputLevelMonitor` integration section to `VisualizerEngine+InputLevel.swift` |
| `VisualizerEngine.swift` | 245 | function_body_length (82) | Extract `setupAudio()`, `setupRenderer()`, `setupCapture()` private helpers from `init` |
| `VisualizerEngine.swift` | 473 | file_length (473, 73 over) | Resolved by init helper extraction above |
| `InputLevelMonitor.swift` | 267 | line_length (127 chars) | Break `String(format:)` argument across lines or shorten message |

**Constraints:**
- No logic changes whatsoever. Every extracted function/struct must preserve byte-for-byte identical observable behavior.
- No new public API surface. All extracted helpers are `private`.
- New files added to the same target as the file being split (no new SPM targets).
- When splitting a file, all `// MARK: -` dividers from the original stay with their section.
- `StemRichFeatures` replacing the named tuple: must update all call sites in `StemAnalyzer.swift`; no other files reference the tuple directly.
- All existing tests must pass before and after each file change.

**Done when:**
- `swiftlint lint --strict --config .swiftlint.yml PhospheneEngine/Sources/ PhospheneEngine/Tests/ PhospheneApp/` reports **0 violations**.
- `swift test --package-path PhospheneEngine` passes (all tests green).
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` succeeds with 0 errors.

**Verify:**
```bash
swiftlint lint --strict --config .swiftlint.yml PhospheneEngine/Sources/ PhospheneEngine/Tests/ PhospheneApp/
swift test --package-path PhospheneEngine
```

---

### Increment 4.1 — Preset Scoring Model ✅

**Landed:** 2026-04-20.

`DefaultPresetScorer` implements the `PresetScoring` protocol with four weighted sub-scores (mood 0.30, stemAffinity 0.25, sectionSuitability 0.25, tempoMotion 0.20) and two multiplicative penalties (family-repeat 0.2×, smoothstep fatigue cooldown 60/120/300s). Hard exclusions gate perf-budget breakers and identity matches before scoring. `PresetScoreBreakdown` exposes every sub-score for introspection. `PresetScoringContext` is a fully Sendable value-type snapshot with a monotonic session clock — no `Date.now()` inside the scorer. 13 unit tests cover all contract edges including determinism, exclusion, cooldown, and rank stability across device tiers. See D-032 in DECISIONS.md for weight rationale.

**New files:** `Orchestrator/PresetScorer.swift`, `Orchestrator/PresetScoringContext.swift`, `Shared/DeviceTier.swift`. Extended: `PresetDescriptor` (added `stemAffinity: [String: String]`), `ComplexityCost` (added `cost(for:)` helper), `Package.swift` (added `Session` dep to `Orchestrator` target, `Orchestrator` dep to test target).

**Verify:** `swift test --package-path PhospheneEngine --filter PresetScorerTests`

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

### Increment 5.1 — Enriched Preset Metadata Schema ✅ (landed as Increment 4.0)

**Note:** This increment was pulled forward and completed as **Increment 4.0** because PresetScorer (Increment 4.1) requires this schema before it can be drafted. See Increment 4.0 above for the full done-when criteria and verification commands. All 5.1 scope items are complete.

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
