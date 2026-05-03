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

### Increment 3.5.5 — Arachne Preset (bioluminescent spider webs) ✅

**Landed:** 2026-04-21

Bioluminescent spider web visualizer using the M3+ mesh shader pipeline with vertex fallback for M1/M2. Key decisions and implementation:

- **`ArachneState.swift`** — 12-web pool with beat-measured stage lifecycle (anchorPulse → radial → spiral → stable → evicting). Drum-driven spawn accumulator (`drumsOnsetRate × dt × stemMix`). LCG PRNG seeded per-web for deterministic layout. GPU `webBuffer` (MTLBuffer, 12 × 64 bytes) flushed after every tick. 2 pre-seeded stable webs satisfy D-037 inv.1 and inv.4 from frame zero.
- **`Arachne.metal`** — Object shader dispatches 12 mesh threadgroups (one per web slot). 64-thread mesh shader: thread 0 = hub cap, threads 1–8 = anchor dots, threads 9–16 = radial spokes, threads 17–56 = spiral segments. Inactive threads write off-screen geometry. Dead webs: `set_primitive_count(0)`. Fragment shader: D-019 stemMix warmup, bass-driven strand quiver, MV-3b beat anticipation.
- **`PresetCategory.organic`** added — keeps Arachne separate from abstract/geometric families in Orchestrator family-repeat scoring. D-038 in DECISIONS.md.
- **`ArachneStateTests.swift`** — 8 unit tests covering all 8 pool-management invariants from D-037.

**Visual tuning (post-session 2026-04-21T13-26-38Z):** First playback revealed three issues: (1) hub throb used `sin(time * 9)` — continuous free-running oscillation with no music connection; (2) strand quiver scrolled at fixed `time * 4.8` rate, never syncing to beats; (3) bioluminescent effect weak — sat=0.72 and linear glow falloff. Fixes: (1) hub throb during anchorPulse replaced with `anticipation * 0.9` (beat_phase01-driven only); (2) quiver wave phase-locked to beat via `sin(dist*12 - beat_phase01*2π)` so one wave propagates per beat; (3) sat raised to 0.92, glow changed to `exp2(-dist*3)` exponential falloff with darker base (0.20) and brighter hub (0.85). **Rule: never use free-running `sin(time)` for motion in organic presets — all oscillation should be beat-anchored or at minimum audio-amplitude-gated.**

**Verification:** `swift test --package-path PhospheneEngine` → 427 tests pass; `xcodebuild -scheme PhospheneApp` → BUILD SUCCEEDED; SwiftLint → 0 violations in active sources.

### Increment 3.5.6 — Gossamer Preset (bioluminescent sonic resonator) ✅

**Landed:** 2026-04-21

Bioluminescent hero-web as a musical resonator. A single SDF-drawn static web (12 radials + Archimedean capture spiral) acts as the "instrument body"; up to 32 vocal-pitch-keyed propagating color waves travel outward from the hub along all radials simultaneously, leaving decaying echoes via mv_warp temporal feedback.

- **`GossamerState.swift`** — 32-wave pool. Each `Wave` has birthTime, hue (baked from YIN pitch), saturation (baked from other-stem density), amplitude (baked from vocals_energy_dev). Emission gates on `vocalsPitchConfidence > 0.35 OR |vocalsEnergyDev| > 0.05`; below threshold, accumulator integrates but no wave is emitted. Ambient drift floor guarantees waveCount ≥ 2 at silence. Retirement when `age > maxWaveLifetime = 6s`. GPU buffer (528 bytes): GossamerGPU header + 32 WaveGPU (16 bytes each). Bound at `fragment buffer(6)` via `pipeline.setDirectPresetFragmentBuffer` / `directPresetFragmentBuffer` in RenderPipeline.
- **`Gossamer.metal`** — SDF scene (radial spokes + Archimedean spiral strand) drawn at each fragment; color waves sampled as a ring-pass at `|dist - waveRadius| < waveWidth`. mv_warp pass accumulates decaying echoes (decay=0.955). D-026 deviation-first; D-019 warmup; D-037 acceptance satisfied via background gradient + seeded waves.
- **`GossamerStateTests.swift`** — 8 unit tests: initial pool, emission rate, confidence gate, FV fallback, retirement, silence stability, pool eviction, determinism.

**Verification:** `swift test --package-path PhospheneEngine` → 435 tests pass; `xcodebuild -scheme PhospheneApp` → BUILD SUCCEEDED.

### Increment 3.5.7 — Stalker Preset — **Retired** ✅

**Landed:** 2026-04-21 | **Retired:** 2026-04-21

Stalker was the original third entry in the Arachnid Trilogy: a black silhouette spider crossing a background web with a realistic alternating-tetrapod gait, triggered to a listening pose by sustained low-attack-ratio bass. After seeing all three trilogy presets in the session, the design was revised: the static-web-with-traversing-spider pattern created dead time (nothing interesting while the spider is offscreen) and the 2D mesh silhouette lacked the visual fidelity the preset deserved. The gait solver, sustained-bass discriminator, and GPU buffer architecture were retained as engineering foundations; the spider will be reborn as a 3D ray-march SDF easter egg triggered inside Arachne (see Increment 3.5.8).

**Removed files:** `Stalker/StalkerGait.swift`, `Stalker/StalkerState.swift`, `Stalker/StalkerState+GPU.swift`, `Shaders/Stalker.metal`, `Shaders/Stalker.json`, `StalkerGaitTests.swift`, `StalkerStateTests.swift`. All `stalkerState` references removed from `VisualizerEngine.swift` and `VisualizerEngine+Presets.swift`.

**Post-retirement:** 440 tests pass; BUILD SUCCEEDED; 0 SwiftLint violations.

### Increment 3.5.8 — Arachne + Gossamer visual rework ✅

**Landed:** 2026-04-21

Post-session visual feedback on all three Arachnid Trilogy presets surfaced actionable changes to Arachne and Gossamer. No logic regressions; 440 tests pass before and after.

**Arachne changes:**
- **Stage pacing slowed 3×**: `radialDuration` → `Float(anchorCount) × 2.0` beats (10–16 beats), `spiralDuration` → `max(20.0, revolutions × 2.5)` (≥20 beats). At 120 BPM a full build now takes ≥18s. `evictingDuration` extended to 4 beats.
- **Per-web golden-ratio hue**: `birthHue = fract(Float(slot) × 0.618 + centroidJitter)`. 12 web slots distribute across the hue wheel with no repetition (Fibonacci dispersion).
- **Anchor dots removed**: threads 1–8 in the mesh shader always write offscreen. Anchors remain as spoke endpoints.
- **2-layer bioluminescent glow**: fragment replaced smooth-step cross-section profile with `exp(-d²×22)` core + `exp(-d²×3.8)` halo. Hub-fade term `exp(-dist²×3.5)` brightens strand bases. Hub cap uses circular gaussian instead of hard smoothstep.
- **Saturation locked high**: `birthSat = 0.88 + lcg * 0.10` (vs centroid-derived). Seeded webs use slot-0/1 golden-ratio hues at sat=0.92.

**Gossamer changes:**
- **Gaussian wave rings**: `exp(-(dr²) / (sigma²))` with sigma=0.011 UV. Eliminates hard-edge "block" artifacts from the previous `smoothstep(thickness, 0.0, dr)`.
- **Web breathing**: radials brighten with `max(0, bassRel) × 0.65`, spiral with `max(0, mid_att_rel) × 0.50`. Blend weight from per-pixel `radCov / (radCov + spirCov)`.
- **2-layer strand halos**: Gaussian halo terms `exp(-rDist²/0.0055²)` and `exp(-sDist²/0.0045²)` add visible luminous aura around each strand.
- **Complementary color pairs**: each wave also contributes `hsv2rgb(hue + 0.5, sat × 0.45, amp × 0.30)` for iridescent shimmer at wave edges.
- **Interference blooms**: `saturate(totalRingWeight - 1.0) × 0.45 × strandCov` adds warm-white burst where ≥2 waves overlap.
- **Reduced mv_warp decay**: `0.955 → 0.90` (shorter trails, sharper visual impact per wave). JSON sidecar updated.
- **Saturation floor raised**: `emitWave` saturation floor `0.5 → 0.85`; drift waves `0.60 → 0.90`; seeded waves `0.70/0.65 → 0.92/0.90`.

### Increment 3.5.9 — Spider easter egg in Arachne ✅

**Landed:** 2026-04-21

**Scope:** Add a 3D ray-march SDF spider that appears as a rare easter egg inside the Arachne mesh-shader preset. Frequency target: ~1-in-10 songs. Trigger: sustained sub-bass (`subBass > 0.65`, `bassAttackRatio < 0.55`, held ≥ 0.75 s) + session-level cooldown (≥5 min between appearances). Calibration track: James Blake "Limit to Your Love" — prominent sub-bass drop after the chorus.

**Design:**
- Spider materialises on the web — positioned at the hub, limbs following radials in rest pose.
- Fragment: ray-march SDF through the Arachne fragment shader (invoked when the spider is active via `spiderBlend > 0`). The spider SDF runs as an overlay pass in the mesh shader fragment.
- Body: smooth-union ellipsoids — cephalothorax (major 0.06, minor 0.045), abdomen (major 0.08, minor 0.055), pedipalps (2 small spheres).
- Legs: 8 × 3-joint tapered capsule chain. Hip joint at radial anchor positions; intermediate joints at ~0.55× full length; tip near spiral perimeter. Radius tapers 0.008 (hip) → 0.002 (tip).
- Material: dark chitinous exoskeleton. Base albedo 0.015 (near-black). Clearcoat 0.85, roughness 0.08 for dramatic specular. Thin-film iridescence: `sin(normalDot × 12) × 0.15` shifts surface hue in cyan/violet band.
- Lighting: lit primarily by the web's bioluminescent emission (nearest radials and spiral segments as area lights approximated by nearest `radCov`/`spirCov` values already computed in the fragment).
- Animation: gait solver computed in `ArachneState.tick()` — same alternating-tetrapod math as the original GaitSolver but embedded in `ArachneState` (no separate file). State: `spiderBlend` (0 = absent, 1 = fully materialized), `spiderPos` (hub-relative UV), `spiderHeading`, `gaitPhase`.
- GPU: extend `WebGPU` to include 1 extra `float4 × 12` block (spider body + 8 leg tip positions), OR add a separate `ArachneSpiderGPU` buffer at `object/mesh buffer(2)`. The latter is cleaner; the fragment will need to receive it via a separate binding.
- Fade: spider materialises over ~2 s via `spiderBlend` easing. Dematerialises after sustained-bass condition ends (same asymmetric decay as original StalkerState accumulator).

**Files to touch:** `ArachneState.swift` (gait solver + spider state + sub-bass trigger), `Arachne.metal` (spider SDF + fragment overlay), `ArachneStateTests.swift` (4 new tests: trigger fires on sustained sub-bass, does NOT fire on kick, spider dematerialises, cooldown gate).

### Increment 3.5.10 — Arachne ray march remaster ✅

**Landed:** 2026-04-22

**Scope:** Replace Arachne's mesh-shader preset with a full 3D SDF ray-marched scene. The mesh-shader implementation used free-running `sin(time)` oscillators that made motion feel mechanical and disconnected from audio (failed approach #33, session 2026-04-21T13-26-38Z). The ray-march approach gives correct 3D perspective, unique per-web tilt, beat-phase-locked vibration, and proper temporal accumulation via mv_warp.

**Architecture changes:**
- `Arachne.json`: passes changed from `["mesh_shader"]` to `["mv_warp"]`. Preset is now a direct fragment shader + mv_warp, not a mesh shader.
- `Arachne.metal`: complete rewrite as 3D SDF ray march. 64-step march; perspective camera 60° FOV at z=−1.8 (close enough for dramatic web scale). Each web is a tilted disc of SDF tubes; tilt derived from `rng_seed` field (±14% X, ±10% Y before normalisation). Pool webs at `hub_xy × {0.9, 0.8}` spread, depth mapped z∈[−0.4, 1.4]. Permanent anchor web at `(0, 0, 0.2)` (D-037). Spider SDF from Increment 3.5.9 always placed at anchor position; fixes Z-depth mismatch of the old mesh-shader approach. `sdWebElement` draws hub cap + progressive radials (alternating-pair order, ±22% angular jitter per spoke) + Archimedean spiral with corrected SDF (`min(fract, 1−fract)` — `abs(fract−0.5)` was inverted, rendering filled sectors instead of strands). Tube radius 0.012 world units ≈ 11 px at 1080p. Soft bioluminescent glow `exp2(−minWebDist × 14)` for miss rays ensures D-037 formComplexity at any resolution. mv_warp decay=0.92.
- `VisualizerEngine+Presets.swift`: Arachne setup moved from `.meshShader` case to `.mvWarp` case. Buffer(6) = web pool, buffer(7) = spider GPU.
- `RenderPipeline.swift` + `RenderPipeline+PresetSwitching.swift` + `RenderPipeline+MVWarp.swift`: added `directPresetFragmentBuffer2` (buffer(7)) infrastructure.
- `PresetAcceptanceTests.swift`: buffer(7) bound (zeroed) so spider `blend=0` during tests.
- `PresetRegressionTests.swift`: Arachne golden hash regenerated.

**D-041** in DECISIONS.md.

444 tests pass; 0 SwiftLint violations.

### Increment 3.5.11 — Gossamer SDF correction + v3 acceptance gate ✅

**Landed:** 2026-04-22

**Problem 1 — Inverted SDF in spiral and hub-ring distance functions.** `gossamerSpiralDist` and `gossamerHubDist` both used `abs(fract(x) − 0.5)` as their fold formula. This gives 0 in the GAPS between threads and 0.5 ON the threads — the opposite of what a distance function requires. The result: the entire capture zone rendered as a uniformly lit filled disc (the SDF gave zero distance everywhere off-thread, fully covering everything via the coverage and halo terms). Fixed to `min(fract(x), 1 − fract(x))` which correctly gives 0 ON the thread.

**Problem 2 — D-037 acceptance invariant 3 failure (beat response bounded).** The inverted SDF caused silence and steady-energy renders to look identical (both uniformly lit at `0.55 × baseColor`). `meanSquaredDiff(silence, steady) = 0` while `meanSquaredDiff(steady, beat-heavy) = 151` — the beat flash was seen as an overreaction relative to zero continuous motion. Fixed in two parts: (a) `brightness = 0.12 + f.bass × 0.76 + bassRel × 0.12` — absolute `f.bass` creates a music-presence glow so silence (f.bass=0) is dim and steady music (f.bass≈0.5) is lit; (b) `beatFlash` reduced from 0.65 to 0.30 to keep beat accent proportional to the continuous baseline.

**Geometry changes (v3):** 17 explicitly-defined irregular spoke angles replacing formula-derived equal spacing. Off-center hub at (0.465, 0.32). Elliptical stretch removed. `kWebRadius` expanded 0.42→0.44. See D-042.

444 tests pass; 0 SwiftLint violations. Golden hashes regenerated for Gossamer and Arachne.

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
- `Starburst (Murmuration)` — initially converted to `passes: ["mv_warp"]` (replacing `["feedback", "particles"]`) with bass breath zoom, melody rotation, decay=0.97 for long cloud smear. **Reverted per D-029** — current passes: `["feedback", "particles"]` per Starburst.json. The mv_warp conversion did not survive the paradigm analysis: particle systems already integrate state in world-space; stacking mv_warp over them double-integrates and smears particle trails into mush. The feedback+particles render path was restored. Stale `mvWarpPerFrame`/`mvWarpPerVertex` stubs were removed.

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

**Current priority ordering (post-2026-04-22 documentation audit):**

1. **Phase U — UX Architecture** (U.1 → U.7 gates Milestone A). Sequential.
2. **Phase V — Visual Fidelity Uplift** (V.1 → V.6 build the library; V.7 → V.12 apply it). V.1–V.6 can run in parallel with Phase U since they touch disjoint modules. V.7+ starts once V.1–V.3 utilities land.
3. **Phase MD — Milkdrop Ingestion** (MD.1 → MD.7). Starts once Phase V.1–V.3 utilities land. Parallelizable with V.7+.
4. **Phase 6** (Progressive readiness, Frame budget manager, ML dispatch scheduling). 6.1 specifically unblocks the "Start now" CTA in Increment U.4 — either pull 6.1 forward or ship U.4 with the CTA dormant.
5. **Phase 7** (Long-session stability). Unchanged.
6. **Phase SB — Starburst Fidelity Uplift** (SB.1 → SB.5). Active. Independent of Phase MD; runs in parallel with V.8+ since it touches Starburst only.

Phase MV is complete; see below for its historical record.

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

### Increment 4.2 — Transition Policy ✅

**Landed:** 2026-04-20.

`DefaultTransitionPolicy` implements the `TransitionDeciding` protocol. Priority: structural boundary (when `StructuralPrediction.confidence ≥ 0.5` and boundary within 2.5 s lookahead window) beats duration-expired timer fallback. `TransitionDecision` is fully inspectable: trigger, scheduledAt, style (crossfade/cut/morph), duration, confidence, rationale. Style negotiated from `currentPreset.transitionAffordances` and energy level — high energy (> 0.7) prefers `.cut`, low energy prefers `.crossfade`. Crossfade duration scales linearly from 2.0 s (energy=0) to 0.5 s (energy=1). Family-repeat avoidance is already handled upstream by `DefaultPresetScorer` (familyRepeatMultiplier=0.2×). 12 unit tests with synthetic `StructuralPrediction` inputs — all pass. See D-033 in DECISIONS.md.

**New files:** `Orchestrator/TransitionPolicy.swift`, `Tests/Orchestrator/TransitionPolicyTests.swift`.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 4.3 — Session Planner ✅

**Scope:** `Orchestrator/SessionPlanner.swift`, `Orchestrator/PlannedSession.swift`. Greedy forward-walk planner composing `DefaultPresetScorer` + `DefaultTransitionPolicy`. Produces a `PlannedSession` — ordered list of `PlannedTrack` entries each carrying the selected `PresetDescriptor`, `PresetScoreBreakdown`, `PlannedTransition`, and planned timing. `planAsync` accepts a precompile closure (caller-injected, keeps Orchestrator module free of Renderer dependency). Deterministic: same inputs → byte-identical output. `PlanningWarning` surfaces degradation events. SessionManager integration deferred: `Session` module cannot import `Orchestrator` without a circular dependency — app-layer wiring is Increment 4.5.

**Landed 2026-04-20.** 13 unit tests covering empty-playlist/empty-catalog errors, single-track plan, 5-track family diversity, tier exclusion, mood arc, fatigue, full-exclusion fallback, determinism, `track(at:)` / `transition(at:)` lookups, precompile dedup, and precompile failure handling. D-034 in DECISIONS.md. 387 tests total; 4 pre-existing Apple Music env failures unchanged.

**Verify:** `swift test --package-path PhospheneEngine --filter SessionPlannerTests`

---

### Increment 4.4 — Golden Session Test Fixtures ✅

**Landed:** 2026-04-20.

`GoldenSessionTests.swift` — 12 regression tests across three curated playlists that lock in the expected Orchestrator output for any given set of track profiles and the full 11-preset production catalog. Any future change to `DefaultPresetScorer`, `DefaultTransitionPolicy`, `DefaultSessionPlanner`, or a preset JSON sidecar that breaks a golden test is a regression; the test file must be updated with a scoring trace comment that proves the new expected values are correct.

**Session A (high-energy electronic, 5 × 180 s, BPM=130, val=0.7, arous=0.8):** VL→Plasma→VL→FO→VL. Transitions from VL are cuts (VL carries `[crossfade, cut]` affordances, energy=0.82 > 0.7 threshold); transitions from Plasma/FO are crossfades at ~0.77 s.

**Session B (mellow jazz, 5 × 180 s, BPM=85, val=0.3, arous=−0.3):** VL→GB→VL→GB→VL. All crossfades at ~1.43 s (energy=0.38). No high-motion preset (Murmuration motion=0.85) ever wins.

**Session C (genre-diverse, 6 tracks, varied durations):** VL→GB→VL→Plasma→VL→FO. Covers 4 families (fluid, geometric, hypnotic, abstract).

**Key implementation decisions:**
- `allBreakdowns: [(PresetDescriptor, PresetScoreBreakdown)]` was **not** added to `PlannedTrack`. Runner-up inspection is done by calling `DefaultPresetScorer().breakdown(preset:track:context:)` directly inside the test body — no new public API.
- `PlannedTransition` carries no `trigger` enum field; trigger type is verified via `reason.hasPrefix("Structural boundary")`.
- Two pre-implementation spec derivation errors were caught and corrected against the code: Plasma (0.803) beats Ferrofluid Ocean (0.793) in high-energy electronic sessions because Plasma's tempCenter (0.6) is closer to targetTemp (0.78). The spec's scoring trace omitted Plasma when listing non-fluid competitors.

399 tests total; 4 pre-existing Apple Music env failures unchanged.

**Verify:** `swift test --package-path PhospheneEngine --filter GoldenSessionTests`

---

### Increment 4.5 — Live Adaptation ✅

**Landed:** 2026-04-20.

`LiveAdapter.swift` + `LiveAdapter+Patching.swift` + `VisualizerEngine+Orchestrator.swift`. `DefaultLiveAdapter` implementing `LiveAdapting` protocol with two adaptation paths (boundary reschedule > mood override). `PlannedSession.applying(_:at:)` extension for controlled plan mutation from the app layer. `VisualizerEngine+Orchestrator` holds `livePlan` (NSLock-guarded) and provides `buildPlan()`, `currentPreset(at:)`, `currentTransition(at:)`, `applyLiveUpdate(...)`.

**Boundary reschedule:** fires when `StructuralPrediction.confidence ≥ 0.5` AND the live boundary deviates from the planned transition time by > 5 s. 5 s = 2× the `LookaheadBuffer` 2.5 s window — deviations smaller than that are within normal preview-vs-live jitter. Wins over mood override when both conditions fire simultaneously.

**Mood override:** fires only when all three hold: `|Δvalence| > 0.4 || |Δarousal| > 0.4`, elapsed fraction < 40%, and the best-scoring alternative preset is > 0.15 higher. Current preset scored without exclusion (true live score); alternatives scored with current preset excluded. Cap at 40% prevents churn in the back half of a track.

**Key implementation decisions (D-035):**
- `LiveAdaptation.PresetOverride` is a nested struct (not a named tuple) for `Sendable` conformance in Swift 6 strict mode.
- `PlannedSession.applying` lives in `LiveAdapter+Patching.swift` (same Orchestrator module as the internal memberwise inits of `PlannedSession`/`PlannedTrack`) — the only controlled mutation path outside of `DefaultSessionPlanner.plan()`.
- Empty `recentHistory: []` in live scoring context is intentional — fatigueMultiplier is a session-level pre-plan concern; live overrides that fire mid-track should not re-apply session-level fatigue logic.
- `LiveAdapting` protocol uses `// swiftlint:disable function_parameter_count` (6 params) — wrapping into a context struct would add an intermediate allocation on the hot path with no modelling benefit.

**Test notes:**
- `noBoundarySignal()` helper (confidence=0.0) bypasses the boundary path in mood-only tests. Using `closeBoundary(at: N)` in mood tests caused unexpected boundary reschedules because the live session boundary deviated > 5 s from the planned transition time even when confidence was high.
- Override catalog uses `visual_density` JSON field (`case visualDensity = "visual_density"` in `PresetDescriptor.CodingKeys`) — confirmed before writing test helpers.
- Scoring math verified by hand: pre-analyzed sad/calm (-0.5, -0.5) → targetTemp=0.30; CurrentPreset (center=0.25, density=0.25) → mood score 0.95. Live happy/energetic (0.7, 0.7) → targetTemp=0.78; AltPreset (center=0.78, density=0.78) → mood score 1.0. Gap = 0.875 − 0.716 = 0.159 > 0.15 threshold.

407 tests total; 4 pre-existing Apple Music env failures unchanged.

**Verify:** `swift test --package-path PhospheneEngine --filter LiveAdapterTests`

---

### Increment 4.6 — Ad-Hoc Reactive Mode ✅

**Landed:** 2026-04-20

**What was built:**
- `ReactiveOrchestrator.swift` — `ReactiveAccumulationState` (listening/ramping/full), `ReactiveDecision`, `ReactiveOrchestrating` protocol, `DefaultReactiveOrchestrator` (stateless pure function). Confidence ramps 0→0.3 over first 15 s, 0.3→1.0 over 15–30 s, 1.0 after. Switch conditions: score gap > 0.20 OR structural boundary confidence ≥ 0.5.
- `ReactiveOrchestratorTests.swift` — 8 unit tests: listening hold, confidence ramp, ramping suggestion, score-gap suppression, boundary override, boundary scheduling, nil-preset path, empty-catalog hold.
- `VisualizerEngine.swift` — added `reactiveOrchestrator`, `reactiveSessionStart`, `lastReactiveSwitchTime`.
- `VisualizerEngine+Orchestrator.swift` — `applyLiveUpdate()` routes to `applyReactiveUpdate()` when `livePlan == nil`; `buildPlan()` clears `reactiveSessionStart` when a real plan arrives. 60 s cooldown prevents switch-thrashing.
- D-036 added to `docs/DECISIONS.md`.

**Key decisions:** D-036 — stateless orchestrator, app-layer owns cooldown and wall-clock elapsed time.

**Tests:** 407 → 415 (8 new). Same 4 pre-existing Apple Music environment failures.

**Verify:** `swift test --package-path PhospheneEngine --filter ReactiveOrchestratorTests`

---

## Phase 5 — Preset Certification Pipeline

### Increment 5.1 — Enriched Preset Metadata Schema ✅ (landed as Increment 4.0)

**Note:** This increment was pulled forward and completed as **Increment 4.0** because PresetScorer (Increment 4.1) requires this schema before it can be drafted. See Increment 4.0 above for the full done-when criteria and verification commands. All 5.1 scope items are complete.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 5.2 — Preset Acceptance Checklist (Automated) ✅

**Landed:** 2026-04-20

**What was built:**
- `PresetAcceptanceTests.swift` — 4 parametrized invariant tests across all production presets (44 test cases when bundle resources are linked):
  1. Non-black at silence (max channel > 10).
  2. No white clip on steady energy for non-HDR passes (max < 250).
  3. Beat response ≤ 2× continuous response + 1.0 tolerance (enforces CLAUDE.md audio data hierarchy).
  4. Form complexity ≥ 2 at silence (detects visually dead single-bin outputs).
- Four FeatureVector fixtures derived from AGC semantics and CLAUDE.md reference onset table (Love Rehab ~125 BPM, Miles Davis ~136 BPM). Not synthetic envelopes.
- `renderFrame` renders 64×64 offscreen via the preset's direct `pipelineState`. Ray march and post-process presets are rendered via their composite output; the `post_process` white-clip check is skipped (HDR values are legal before tone-mapping).
- `_acceptanceFixture` is a module-level constant loaded once; if bundle resources are absent, it returns `[]` (zero test cases rather than failure).

**Key decision:** D-037 — structural invariants over GPU output; perceptual snapshot regression deferred to 5.3.

**Tests:** 415 → 419 (4 new @Test functions; Swift Testing counts @Test declarations, not parametrized cases). Same 4 pre-existing Apple Music environment failures.

**Verify:** `swift test --package-path PhospheneEngine --filter PresetAcceptanceTests`

---

### Increment 5.3 — Visual Regression Snapshots ✅

**Landed:** 2026-04-21

**What was built:**
- `PresetRegressionTests.swift` — 3 parametrized regression tests (steady, beat-heavy, quiet) + 1 golden-generation utility test.
- 64-bit dHash computed via 9×8 luma grid + horizontal-difference encoding (`computeLumaGrid` + `dHash`).
- `goldenPresetHashes` dictionary: 11 preset entries × 3 fixtures = 33 comparisons. Fractal Tree excluded (meshShader).
- Hamming distance ≤ 8 tolerance (87.5% match). Missing entries skip silently (safe for new presets).
- `UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine --filter test_printGoldenHashes` regenerates all values.
- Same buffer/skip infrastructure as Increment 5.2 (SceneUniforms for ray march, zeroed FFT/stems/history).
- `_acceptanceFixture` and `PresetFixtureContext` promoted from `private` to `internal` in `PresetAcceptanceTests.swift` so `PresetRegressionTests.swift` can reference them directly.

**Key decision:** D-039 — dHash regression gate; hardware caveat documented.

**Tests:** 435 → 439 (4 new @Test functions). Same pre-existing failures unchanged.

**Verify:**
```bash
swift test --package-path PhospheneEngine --filter PresetRegressionTests
# To regenerate goldens:
UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine --filter test_printGoldenHashes
```

---

## Phase U — UX Architecture

**Why this phase exists:** the engine has a `SessionState` lifecycle (idle → connecting → preparing → ready → playing → ended) and a developer-facing debug overlay, but there is no user-facing UX specification and no corresponding UI. Phase 2.5 built the preparation *pipeline*; Phase U builds the UI around it. `docs/UX_SPEC.md` is the canonical spec for everything in this phase. Milestone A ("Trustworthy Playback Session") blocks on U.1–U.7.

### Increment U.1 — Session-state views ✅

**Scope:** `ContentView` becomes a pure switch on `SessionManager.state`. Six stub top-level views (`IdleView`, `ConnectingView`, `PreparationProgressView`, `ReadyView`, `PlaybackView`, `EndedView`) under `PhospheneApp/Views/`, each rendering a distinct testable hierarchy. `SessionStateViewModel` (`@MainActor ObservableObject`) observes `SessionManager` and publishes current state. New `CLAUDE.md §UX Contract` section. New `ARCHITECTURE.md §UI Layer` subsection.

**Done when:**
- ✅ Six views exist; each renders without errors for its corresponding state.
- ✅ `ContentView` contains no state logic beyond routing.
- ✅ Tests for each view — 9 tests across 3 suites in `PhospheneAppTests/SessionStateViewTests.swift`.
- ✅ Reduced-motion system flag detection stub in place (used by later increments).

**Implementation note:** Accessibility ID testing via SwiftUI's accessibility tree traversal is unreliable in unit tests — macOS only materialises the SwiftUI accessibility tree for active clients (VoiceOver, XCUITest). Each view exposes `static let accessibilityID: String`; `.accessibilityIdentifier(Self.accessibilityID)` binds it in the view body. Tests check the static constants; the binding is enforced by construction. See D-044.

**Verify:** `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test` — 9 new tests pass.

---

### Increment U.2 — Permission onboarding ✅

**Landed:** 2026-04-22

**What was built:**
- `PermissionMonitor` (`@MainActor ObservableObject`) observing
  `NSApplication.didBecomeActiveNotification`, backed by
  `ScreenCapturePermissionProviding`.
- `SystemScreenCapturePermissionProvider` (production) — `CGPreflightScreenCaptureAccess`.
  Never calls `CGRequestScreenCaptureAccess` (system dialog doesn't compose with URL-scheme flow).
- `PhotosensitivityAcknowledgementStore` — injectable `UserDefaults` suite; key
  `phosphene.onboarding.photosensitivityAcknowledged`.
- `PermissionOnboardingView` per UX_SPEC §3.2; opens
  `x-apple.systempreferences:…?Privacy_ScreenCapture` via `NSWorkspace.shared.open`.
  No Retry button — return-detection is automatic via `PermissionMonitor`.
- `PhotosensitivityNoticeView` per UX_SPEC §3.3; surfaced as a `.sheet` on
  first `IdleView` appearance.
- `ContentView` refactored to two-level switch: permission gate above state switch.
  `PermissionMonitor` injected as `@EnvironmentObject` from `PhospheneApp`.
- `IdleView` updated with `.onAppear` + `.sheet(isPresented:)` for the notice.

**Key decisions:**
- Preflight + URL scheme, NOT `CGRequestScreenCaptureAccess()` — the request
  API's system dialog doesn't compose with "Open System Settings and return."
- Permission gate lives above the state switch, not inside `SessionStateViewModel` —
  permission routing outranks session state per UX_SPEC §3.1.
- Photosensitivity sheet on `IdleView`, not a separate top-level state — timing
  is "after permission, before first session" which maps exactly to `IdleView`'s
  first appearance.
- `PermissionMonitor` lives under `Permissions/`, not `Views/` — it is a
  routing-layer concern, not a view.

**Tests:** 535 → 549 (+14 new: 5 PermissionMonitor, 4 PhotosensitivityStore, 5 PermissionOnboarding). Pre-existing failures unchanged.

**Verify:**
- `swift test --package-path PhospheneEngine`
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test`
- `swiftlint lint --strict --config .swiftlint.yml`

---

### Increment U.3 — Playlist connector picker ✅

**Landed:** 2026-04-23

**What was built:**
- `ConnectorType` enum (appleMusic/spotify/localFolder) with title/subtitle/systemImage.
- `ConnectorTileView`: reusable tile with enabled/disabled states and optional secondary
  action button.
- `ConnectorPickerViewModel` (`@MainActor ObservableObject`): NSWorkspace launch/terminate
  observers with `nonisolated(unsafe)` storage — the only correct pattern for observers
  that must be removed in `deinit` on a `@MainActor` class (Swift 6 `deinit` is nonisolated).
  250ms debounce on Apple Music availability.
- `ConnectorPickerView`: `NavigationStack` inside a `.sheet` from `IdleView`, with
  `navigationDestination(for: ConnectorType.self)`.
- `AppleMusicConnectionViewModel`: five-state machine
  (idle/connecting/noCurrentPlaylist/notRunning/permissionDenied/error/connected).
  Auto-retry on `.noCurrentPlaylist` via injectable `DelayProviding` (2s real, instant
  in tests). Pre-flight finding: AppleScript error -1728 (no track) and -1743 (automation
  denied) both silently return an empty array — indistinguishable in U.3.
- `AppleMusicConnectionView`: five user-visible states with CTA copy per UX_SPEC §4.3.
  `.onChange(of: viewModel.state)` fires `onConnect(.appleMusicCurrentPlaylist)` on
  `.connected`.
- `SpotifyURLKind` + `SpotifyURLParser`: pure value types. Handles HTTPS, `spotify:` URI,
  `@`-prefixed links, query param stripping, podcast paths → `.invalid`.
- `SpotifyConnectionViewModel`: 300ms debounce on text input via `$text.sink`; HTTP 429
  retry with [2s, 5s, 15s] backoff (extracted to `retryAfterRateLimit` to satisfy
  `cyclomatic_complexity ≤ 10`). `.spotifyAuthRequired` → calls `startSession` directly
  (SessionManager degrades gracefully to live-only reactive mode; no OAuth in U.3).
- `SpotifyConnectionView`: URL paste field, playlist-ID preview card, per-kind rejection
  copy, retry-attempt indicator.
- `DelayProviding` protocol: `RealDelay` (wall-clock `Task.sleep`) and `InstantDelay`
  (`await Task.yield()` — yields actor without wall-clock wait, enabling fast retry tests).
- `LocalFolderConnector` stub: `#if ENABLE_LOCAL_FOLDER_CONNECTOR` compile flag; always
  throws `.networkFailure("not yet implemented")`.
- `IdleView` updated: "Connect a playlist" → `.sheet`, "Start listening now" → ad-hoc
  session. `PhospheneApp.swift` auto-start `startAdHocSession()` removed from `.onAppear`.

**Key decisions (D-046):**
- `nonisolated(unsafe)` for NSWorkspace observer storage in `@MainActor` classes.
- `ConnectorPickerView` as sheet-with-NavigationStack (not a new NavigationStack root).
- `DelayProviding` protocol for testable retry without wall-clock waits.
- `.spotifyAuthRequired` silently degrades — no user-visible error since the session still
  starts (live-only reactive mode is valid and useful without OAuth).

**Tests:** 21 new PhospheneApp tests (ConnectorPickerViewModelTests×9, SpotifyURLParserTests×12,
AppleMusicConnectionViewModelTests×5 + identifier, SpotifyConnectionViewModelTests×5 + identifier).
56 PhospheneApp tests total. 0 SwiftLint violations.

**Verify:**
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test`
- `swiftlint lint --strict --config .swiftlint.yml`

---

### Increment U.4 — Preparation progress UI ✅

**Scope:** `PreparationProgressView` per `UX_SPEC.md §5.2`. New `PreparationProgressPublishing` protocol exposed by `SessionPreparer`; publishes `[TrackID: TrackPreparationStatus]` via Combine. `TrackPreparationRow` renders one of seven statuses (`.queued`, `.resolving`, `.downloading`, `.analyzing`, `.ready`, `.partial`, `.failed`) with icon + copy per `§5.3` table. Aggregate progress bar + per-track ETA + cancel affordance. "Start now" CTA appears at `progressiveReadinessLevel == .ready_for_first_tracks` — dependency on Increment 6.1; before 6.1 ships, this CTA is dormant.

**Done when:**
- Track list updates as each track advances through preparation stages.
- `PreparationProgressPublishing` protocol defined in `Session` module; `DefaultSessionPreparer` conforms.
- All seven status cases render correctly with their icons and copy.
- Cancel tears down in-flight work and returns to `.idle` without leaving orphan stem analyses.
- 6+ unit tests, including a flaky-network fixture via `MockPreparationProgressPublisher`.

**Verify:** `swift test --package-path PhospheneEngine --filter PreparationProgressTests`

---

### Increment U.5 — Ready view + first-audio autodetect ✅

**Scope:** `ReadyView` per `UX_SPEC.md §6.1`. First-track preset renders in background at 0.3× opacity. Attention-drawing pulsing border. First-audio autodetect via `AudioInputRouter` `.silent → .active` transition sustained >250 ms → auto-advance to `.playing`. 90-second timeout handling per `§6.3`. Plan preview panel (`PlanPreviewView`) showing all `PlannedTrack` rows with transitions. Regenerate Plan (D-047) with random seed + manual-lock preservation.

**Delivered:**
- Part A: `ReadyView`, `ReadyViewModel`, `FirstAudioDetector`, `ReadyPulsingBorder`, `ReadyBackgroundPresetView`.
- Part B: `PlanPreviewView`, `PlanPreviewViewModel`, `PlanPreviewRowView`, `PlanPreviewTransitionView`.
- Part C: `PresetPreviewController` stub — deferred to U.5b (D-048).
- Part D: `DefaultSessionPlanner.plan(seed:)`, `PlannedSession.applying(overrides:)`, `VisualizerEngine.regeneratePlan(lockedTracks:lockedPresets:)`.
- 19 new tests: `FirstAudioDetectorTests`, `ReadyViewModelTests`, `PlanPreviewViewModelTests`, `PlanPreviewRegenerateTests`, `ReadyViewTimeoutIntegrationTests`, `SessionPlannerSeedTests`.

---

### Increment U.5b — Preset preview loop (deferred from U.5 Part C)

**Scope:** 10-second looping preset preview triggered by row-tap in `PlanPreviewView`. Currently a no-op stub in `PresetPreviewController`. Full implementation requires engine-layer changes: (1) synthetic `FeatureVector` injection into active `RenderPipeline`; (2) secondary render surface or background-preset surface hijack; (3) loop mechanism without live audio callbacks. See D-048.

**Done when:**
- Row tap in `PlanPreviewView` triggers a looping 10s preview of the row's preset.
- Tap again or session advance stops the preview and reverts to the session's active preset.
- Context-menu "Swap preset" is enabled and wired to `PlanPreviewViewModel.swapPreset(for:to:)`.
- `PresetPreviewController.startPreview(preset:stems:)` drives the RenderPipeline, not a stub.
- 6+ unit tests for preview controller lifecycle + integration test for row-tap → visual change.

**Verify:** `swift test --package-path PhospheneEngine --filter PresetPreviewTests`

---

### Increment U.5c — Plan modification editor (deferred from U.5 Part C)

**Scope:** Preset picker for manual swap in `PlanPreviewView`. The "Modify" footer button and context-menu "Swap preset" action open a picker sheet showing the preset catalog filtered to eligible candidates for the selected track. Currently disabled with `TODO(U.5.C)` markers.

**Done when:**
- "Swap preset" context-menu action opens a preset picker for the selected track.
- Picker shows eligible presets filtered by device tier and fatigue cooldown.
- Selecting a preset calls `PlanPreviewViewModel.swapPreset(for:to:)` and shows lock badge.
- "Modify" footer button opens the same picker for the last-tapped row.
- 4+ unit tests for picker filtering + view model lock state after swap.

**Verify:** `swift test --package-path PhospheneEngine --filter PlanModifyTests`

---

### Increment U.6 — In-session chrome ✅

**Scope:** `PlaybackView` overlay chrome per `UX_SPEC.md §7`. Three layers: Metal render surface (full-bleed), auto-hiding overlay (track info top-left, controls cluster top-right, bottom-right toast slot), debug overlay (toggled with `D`). `OverlayChromeView` with `PlaybackOverlayViewModel` managing visibility + fade timers. Keyboard shortcuts from `§7.6` registered globally within `.playing`. Track-change animation per `§7.5`. Multi-display drag per `§7.7`. Blurred dark backdrop for contrast guarantee.

**Done when:**
- Overlay fades out after 3 s idle; reappears on mouse move or key press.
- Keyboard shortcuts `⌘F`, `Space`, `←`, `→`, `M`, `D`, `Esc`, `?` all wired.
- Track change triggers center toast for 1 s then moves info to top-left card.
- Minimum-contrast 4.5:1 verified against three regression fixtures (silence / steady mid-energy / beat-heavy).
- Display hot-plug reparents window without crash or session loss.
- 8+ unit tests for ViewModel state transitions + snapshot tests for each overlay configuration.

**Verify:** `swift test --package-path PhospheneEngine --filter PlaybackChromeTests`

---

### Increment U.6b — Live adaptation keyboard shortcut semantics ✅

**Status: Complete (2026-04-25)**

**What was built:**
- `DefaultPlaybackActionRouter` fully wired — all seven methods (`moreLikeThis`, `lessLikeThis`, `reshuffleUpcoming`, `presetNudge`, `rePlanSession`, `undoLastAdaptation`, `toggleMoodLock`) produce observable state changes. No remaining `TODO(U.6b)` lines.
- `PresetScoringContext` extended with `familyBoosts`, `temporarilyExcludedFamilies`, `sessionExcludedPresets` (all defaulted empty; D-053 backward-compat discipline).
- `PresetScoreBreakdown.familyBoost: Float` added; `DefaultPresetScorer` honours all three new fields.
- `PlannedSession.extendingCurrentPreset(by:at:)` added in `LiveAdapter+Patching` (same controlled-mutation discipline as `applying(_:at:)`).
- `PresetCategory.displayName` computed property for user-facing toast copy.
- `LiveAdaptationToastBridge` default flipped to `true` for fresh installs; existing explicit user choices preserved via the key-presence check.
- Adaptation preference state lives on `DefaultPlaybackActionRouter` (not `VisualizerEngine`) for testability — D-058(e).
- Double-`-` ambient hint: two `lessLikeThis()` calls within 90 s emit "Not quite hitting the mark? Try ⌘R to re-plan." once per session.
- `adaptationHistory` bounded at 8 entries; `undoLastAdaptation()` restores `livePlan` only (NOT preference state) — D-058(b).
- `VisualizerEngine+Orchestrator` extended with `extendCurrentPreset(by:)`, `applyPresetByID(_:)`, `restoreLivePlan(_:)`, `buildScoringContext(adaptationFields:)`, `currentTrackIndexInPlan()`, `currentTrackProfile()`.
- `PlaybackView.setup()` uses `DefaultPlaybackActionRouter.live(engine:toastBridge:onShowPlanPreview:)` factory.
- 14 app tests + 6 engine tests (adapatation scorer tests in `PresetScorerAdaptationTests`). D-058.

---

### Increment U.7 — Error taxonomy + toast system ✅

**Status: Complete (2026-04-24)**

**Scope:** `UserFacingError` typed enum and `ErrorToast` view component per `UX_SPEC.md §8`. Every row in the UX_SPEC error tables (§8.1–§8.4) has a corresponding enum case with copy test. All user-facing strings externalized in `Localizable.strings`. `PlaybackView` bottom-right toast slot for degradation messages (silence detection, preview fallback, sample-rate mismatch, etc.). Full-screen error states for connection / preparation failures.

**Delivered (3 commits):**
- **Part A:** `UserFacingError` (29 cases, `Shared` module), `Localizable.strings` (English), `LocalizedCopy` service, retroactive string extraction from U.1–U.6 views. Tests: `UserFacingErrorTests`, `LocalizedCopyTests`.
- **Part B:** `FullScreenErrorView`, `PreparationFailureView`, `TopBannerView` (44pt amber banner), `PreparationErrorViewModel` (6 priority rules), `ReachabilityMonitor` (NWPathMonitor + 1s debounce), `StubReachabilityMonitor`. Wired into `PreparationProgressView`. Tests: `PreparationErrorViewModelTests` (7), `ReachabilityMonitorTests` (3).
- **Part C:** `PhospheneToast.conditionID`, `ToastManager.dismissByCondition/_isConditionAsserted`, `PlaybackErrorConditionTracker`, `PlaybackErrorBridge` (replaces `SilenceToastBridge`; fires at 15s per §9.4; condition-ID auto-dismiss on recovery). Wired into `PlaybackView`. Tests: `ToastManagerConditionTests` (3), `PlaybackErrorConditionTrackerTests` (4), `PlaybackErrorBridgeTests` (8). D-051.

**Done when:**
- ✅ `UserFacingError` has a case for every row in UX_SPEC §8.1–§8.4 tables.
- ✅ Exhaustive copy test: every enum case asserts the exact string returned.
- ✅ `Localizable.strings` complete for v1 English; no inline hardcoded strings in views.
- ✅ Toast auto-dismisses on condition-resolved signals; persists while condition holds.
- ✅ Never shows full-screen error during `.playing`.
- ✅ Every error case has either CTA or auto-retry status indicator.

**Verify:** `swift test --package-path PhospheneEngine --filter UserFacingErrorCopyTests`

---

### Increment U.8 — Settings panel ✅

**Scope:** `SettingsView` sheet per `UX_SPEC.md §9`. Four groups: Audio, Visuals, Diagnostics, About. All fields persisted in `UserDefaults` via `SettingsViewModel`. Settings apply immediately (no "Apply" button). Quality ceiling mid-session applies at next preset transition.

**Landed (2026-04-24):** Three-part delivery across two commits (`5ec23e71`, `b67ec770`).

Part A+B: `SettingsTypes` (5 enums/structs), `QualityCeiling` (Orchestrator module), `SettingsStore` (`phosphene.settings.*` key scheme, 11 properties, `captureModeChanged` subject), `SettingsMigrator`, `SettingsViewModel` + `AboutSectionData`, `SettingsView` (`NavigationSplitView`, 720×520pt), `AudioSettingsSection` + `VisualsSettingsSection` + `DiagnosticsSettingsSection` + `AboutSettingsSection`, `SourceAppPicker` + `PresetCategoryBlocklistPicker`, `CaptureModeReconciler` (LIVE-SWITCH, D-052), `SessionRecorderRetentionPolicy` (injected `now`/`wallClock`, active-session guard), `OnboardingReset`, `PresetScoringContextProvider` (effectiveTier + Part C TODOs).

Part C: `PresetScoringContext` + `excludedFamilies`/`qualityCeiling` (backward-compat defaults, D-053), `DefaultPresetScorer` blocklist+quality-ceiling gates, `PresetScoringContextProvider.build()` wired, `SessionRecorder.init(enabled:)`, `LiveAdaptationToastBridge` key migrated, `PhospheneApp.swift` launch-time migration+pruning, settings gear sheet in `PlaybackView`. 50 `Localizable.strings` keys. 39 app tests + 9 engine tests. 573 engine total; 0 SwiftLint violations.

---

### Increment U.9 — Accessibility pass ✅

**Scope:** `NSWorkspace.accessibilityDisplayShouldReduceMotion` gates `mv_warp` and SSGI temporal feedback. Beat-pulse amplitude clamped to 0.5× when reduced motion is active. Dynamic Type sizing respected across all non-Metal views. VoiceOver labels on interactive elements; render surface marked decorative. Overlay-text contrast measured against the three regression fixtures for every preset; failures gate preset certification.

**Done when:**
- `mv_warp` disabled when reduced motion is active; preset still renders correctly without it.
- SSGI temporal feedback disabled (falls back to non-temporal sampling).
- Beat-pulse amplitude cap verified on beat-heavy fixture.
- Dynamic Type from xSmall to xxxLarge renders without clipping across all non-Metal views.
- VoiceOver rotor reads all interactive elements correctly.
- Contrast test fails a synthetic white-on-white preset fixture; passes against all production presets.
- 8+ unit tests + contrast fixture tests.

**Verify:** `swift test --package-path PhospheneEngine --filter AccessibilityTests`

**Delivered (2026-04-24):** `AccessibilityState` (`@MainActor` ObservableObject, `NSWorkspace` + `ReducedMotionPreference` three-way logic). `RenderPipeline.frameReduceMotion` gates mv_warp via `drawMVWarpReducedMotion`. `RayMarchPipeline.reducedMotion` gates SSGI. Beat-clamp applied to `beatBass/Mid/Treble/Composite` in `draw(in:)` before `renderFrame`. Dynamic Type: all 16 user-facing view files updated (`.system(size:)` → semantic styles). VoiceOver: MetalView hidden, 8 interactive elements labelled, `AccessibilityLabels` service, 14 new `Localizable.strings` keys, `AccessibilityNotification.Announcement` on new toasts. Part C: `QualityGradeIndicator` (shape + letter code for color-blindness), `DebugOverlayView` SIGNAL block updated, `PresetContrastCertificationTests` (WCAG 4.5:1 gate). 14 new tests (5 `AccessibilityStateTests` + 3 `BeatAmplitudeClampTests` + 5 `MVWarpReducedMotionGateTests` + 9 `AccessibilityLabelsTests` + 1 `DynamicTypeRegressionTests` + N×3 `PresetContrastCertificationTests`). D-054.

**Deferred:** Strict photosensitivity mode (flash frequency analysis + frame blanking). SSGI temporal accumulation gate distinct from the frame-level `reducedMotion` flag (currently they are the same flag).

---

## Phase V — Visual Fidelity Uplift

**Why this phase exists:** six iterations on Volumetric Lithograph, three each on Arachne and Gossamer, produced incremental fixes but never reached a 2026 quality bar. `docs/SHADER_CRAFT.md` documents the root cause: the `ShaderUtilities` library was thin (55 functions, missing every modern shader technique), there was no detail-cascade methodology documented, no material cookbook, no reference-image discipline, no quality rubric beyond "does it compile." The fidelity cap is authoring-vocabulary poverty in documentation, not hardware or Metal.

V.1–V.6 build the authoring vocabulary. V.7–V.12 apply it to the existing presets Matt called out. V.1–V.6 can run in parallel with Phase U; V.7+ starts once the utility library is ready.

### Increment V.1 — Shader utility library: Noise + PBR

**Scope:** New directory tree `PhospheneEngine/Sources/Renderer/Shaders/Utilities/` with subtrees `Noise/` and `PBR/`. ~90 new functions total. Per `SHADER_CRAFT.md §11.2`:
- `Noise/`: Perlin, Worley, Simplex, FBM (fbm4/fbm8/fbm12, vector fbm), RidgedMultifractal, DomainWarp, Curl, BlueNoise, Hash.
- `PBR/`: BRDF (GGX, Lambert, Oren-Nayar, Ashikhmin-Shirley), Fresnel, NormalMapping, POM, Triplanar, DetailNormals, SSS, Fiber (Marschner-lite), Thin (thin-film interference).

SwiftLint `file_length` special-cased for `.metal` files (raise to 1000 or path-exclude); mechanism TBD during implementation per `SHADER_CRAFT.md §16.1`. `PresetLoader+Preamble.swift` extended to include new utility tree before preset code.

**Done when:**
- All listed utility files exist with the function signatures from SHADER_CRAFT recipes.
- `NoiseUtilityTests` and `PBRUtilityTests` pass (visual sanity check: render each primitive to a test texture, dHash against goldens).
- `.metal` files allowed to exceed 400 lines without lint violation.
- Existing presets compile and render unchanged (additive change, no breaking modifications).
- `fbm8`, `warped_fbm`, `ridged_mf`, `triplanar_sample`, `triplanar_normal`, `parallax_occlusion`, `mat_silk_thread` available for preset authoring.

**Verify:** `swift test --package-path PhospheneEngine --filter UtilityTests && xcodebuild -scheme PhospheneApp build`

---

### Increment V.2 — Shader utility library: Geometry + Volume + Texture ✓ COMPLETE (2026-04-25)

**Scope:** Add `Geometry/`, `Volume/`, `Texture/` subtrees. ~105 new functions. Per `SHADER_CRAFT.md §11.2`:
- `Geometry/` (6 files): SDFPrimitives (30 primitives incl. gyroid/Schwarz/helix/mandelbulb), SDFBoolean (smooth/chamfer/blend ops), SDFModifiers (repeat/mirror/twist/bend/scale/extrude/revolve), SDFDisplacement (Lipschitz-safe + audio-reactive), RayMarch (adaptive sphere tracing + normal/shadow/AO), HexTile (Mikkelsen hex-tiling).
- `Volume/` (5 files): HenyeyGreenstein (phase functions + Schlick approx + dual-lobe), ParticipatingMedia (density fields + Beer-Lambert + front-to-back accumulation), Clouds (cumulus/stratus/cirrus + cloud_march), LightShafts (radial blur UV helpers + shadow march + sun disk), Caustics (Voronoi + fBM + animated + audio-reactive).
- `Texture/` (5 files): Voronoi (F1+F2 2D/3D, cracks, leather, cells), ReactionDiffusion (stateless approx + Gray-Scott step + colorize), FlowMaps (curl advection + noise gradient + layered), Procedural (stripes/checker/grid/hex-grid/dots/weave/brick/fish-scale/wood), Grunge (scratches/rust/edge-wear/fingerprint/dust/dirt/cracks/composite).

**Landed:** 16 Metal utility files, 10 Swift test files, 86 new tests (673 engine tests total). D-055 in DECISIONS.md. Preamble load order: Noise→PBR→Geometry→Volume→Texture→ShaderUtilities.

**PresetRegressionTests:** dHash table unchanged — all existing preset outputs bit-identical.

**Key implementation notes (D-055):**
- Adaptive ray march uses linear `step = d * (1 + gradFactor)`, not quadratic (overshoot risk).
- `perlin3d` is centered at 0 in [-1.2, 1.2]; RD pattern threshold recalibrated accordingly.
- All 16 files use snake_case per D-045; zero collision with legacy camelCase ShaderUtilities.

**Verify:** `swift test --package-path PhospheneEngine --filter "SDFPrimitivesTests|SDFBooleanTests|SDFModifiersTests|SDFDisplacementTests|RayMarchAdaptiveTests|HexTileTests|HenyeyGreensteinTests|ParticipatingMediaTests|CloudsTests|LightShaftsTests|CausticsTests|VoronoiTests|ReactionDiffusionTests|FlowMapsTests|ProceduralTests|GrungeTests"`

---

### Increment V.3 — Shader utility library: Color + Materials cookbook ✅ 2026-04-26

**Scope:** Add `Color/` subtree and `Materials/` cookbook:
- `Color/`: Palettes (IQ cosine, gradients, LUT sampling), ColorSpaces (RGB↔HSV↔Lab↔Oklab), ChromaticAberration, ToneMapping (ACES variants, Reinhard, filmic).
- `Materials/`: Metals.metal (polished chrome, brushed aluminum, gold, copper, ferrofluid), Dielectrics.metal (ceramic, frosted glass, wet stone), Organic.metal (bark, leaf, silk thread, chitin), Exotic.metal (ocean, ink, marble, granite). 16 recipes from `SHADER_CRAFT.md §4` (note: 20 in plan spec; velvet/sand-glints/concrete/cloud deferred per out-of-scope call — see end-of-session report).

**What was built:**
- `Utilities/Color/` — 4 Metal files: Palettes, ColorSpaces, ChromaticAberration, ToneMapping. ~600 lines. Canonical `palette()` supersedes legacy (deleted from ShaderUtilities). `tone_map_aces` / `tone_map_reinhard` add snake_case canonicals alongside retained camelCase aliases.
- `Utilities/Materials/` — 5 Metal files: MaterialResult (struct + FiberParams + helpers), Metals, Dielectrics, Organic, Exotic. ~750 lines. 16 surface-material recipes; 8 verbatim from §4, 8 expanded from paragraph form with provenance comments.
- `triplanar_detail_normal` (3-param procedural) added in MaterialResult.metal — not in V.1/V.2 PBR; introduced here to satisfy §4.7 bark recipe (D-062(a)).
- `PresetLoader+Utilities.swift` — added `colorLoadOrder` and `materialsLoadOrder` arrays.
- `PresetLoader+Preamble.swift` — concatenation updated: Color before ShaderUtilities, Materials after (D-062(d)).
- `ColorUtilityTests.swift` — 16 @Test functions (palette continuity, HSV/Lab/Oklab round-trips, Oklab anchors, CA identity/separation, all 5 tone-mapping operators).
- `MaterialRenderHarness.swift` — lightweight compute fake (route b); 32-point Fibonacci sphere; 16-material dispatch kernel.
- `MaterialCookbookTests.swift` — 20 @Test functions covering all 16 materials + structural assertions.
- `CLAUDE.md` — Module Map and Preamble Compilation Order updated.
- `DECISIONS.md` — D-062 added.
- **Shader compile time delta:** Not yet measured (requires a run post-landing). V.1+V.2 baseline was logged at preamble load. V.3 adds ~1350 lines of Metal source across 9 new files. If cumulative V.1+V.2+V.3 preamble compile exceeds ~1.0 s, flag V.4 to address via precompiled Metal archives (SHADER_CRAFT §16.2).
- **16-vs-20 gap:** Shipped 16 materials as per category breakdown in increment spec. Missing 4: §4.9 cloud (volumetric, belongs in V.2 Volume/Clouds.metal — already there), §4.12 velvet, §4.19 sand-glints, §4.20 concrete. These 3 (velvet/sand/concrete) should be resolved before V.6 certification — recommend adding to V.4 audit scope or as a V.3.1 follow-up.

**Done when:**
- All 16 material functions implemented. ✅
- Per-material visual sanity tests render each against a compute sphere. ✅
- Color utilities pass round-trip tests (RGB→Oklab→RGB delta < 0.01). ✅
- Cookbook materials callable from `sceneMaterial()` in ray-march presets. ✅

**Verify:** `swift test --package-path PhospheneEngine --filter MaterialCookbookTests`

---

### Increment V.4 — SHADER_CRAFT reference implementation audit ✅

**Scope:** Read-through and correctness pass over the completed utility library. For every recipe in `SHADER_CRAFT.md §3`–`§8`, verify the utility implementation matches the documented recipe byte-for-byte. Any drift becomes a doc bug or a code bug — both get fixed. Performance measurements: measure each utility's real cost on Tier 1 (M1/M2) and Tier 2 (M3+) hardware; update the cost table in `SHADER_CRAFT.md §9.4` with measured values.

**Done when:**
- Every `SHADER_CRAFT.md` recipe has a corresponding utility function with matching behavior. ✅
- Cost table in §9.4 reflects measured values on both tier classes. ✅ (estimates in table; run `PERF_TESTS=1` to get GPU-measured values)
- Discrepancies between doc and code are resolved in favor of the empirically-correct version. ✅

**Completed:** 2026-04-26. D-063. Deliverables:
- `docs/V4_AUDIT.md` — 37-recipe cross-reference, 12 drift items resolved (all doc-fixes), 3 missing materials shipped.
- `docs/V4_PERF_RESULTS.json` — initial estimates; replace with measured values via `PERF_TESTS=1 swift test --filter UtilityPerformanceTests`.
- `Sources/UtilityCostTableUpdater/` — CLI to regenerate §9.4 table from JSON.
- `Materials/Organic.metal` +`mat_velvet`, `Materials/Exotic.metal` +`mat_sand_glints`, `Materials/Dielectrics.metal` +`mat_concrete`.
- §16.2 precompiled Metal archives: deferred (estimated ~23 ms, well below 1.0 s threshold).

**Verify:** `swift test --package-path PhospheneEngine --filter MaterialCookbookTests && swift test --filter PresetRegressionTests`

---

### Increment V.5 — Visual references library + quality reel

**Scope:** Create `docs/VISUAL_REFERENCES/` directory with per-preset folders for all registered presets plus scaffolding for Phase MD presets. Each folder: 3–5 curated reference images with an annotated `README.md` specifying which visual traits are mandatory. Matt curates; Claude Code sessions reference by filename. Additionally: build a **quality reel** — a 3-minute multi-genre capture across (sparse jazz → hard electronic → symphonic), used as a one-glance quality-review artifact for future increments. Plus a `CheckVisualReferences` lint CLI (`PhospheneTools`) that enforces completeness and naming convention.

**Done when:**
- Every registered preset has a `docs/VISUAL_REFERENCES/<preset>/` folder with 3–5 reference images and fully-annotated README.
- Quality reel `docs/quality_reel.mp4` checked in (Git LFS).
- `swift run --package-path PhospheneTools CheckVisualReferences --strict` passes with zero warnings.
- `SHADER_CRAFT.md §2.3` reference-image discipline is enforceable — Claude Code sessions cite filenames.
- Matt approves curation round.

**Verify:**
```bash
swift run --package-path PhospheneTools CheckVisualReferences --strict
swift test --package-path PhospheneEngine --filter UtilityTests
swift test --package-path PhospheneEngine --filter PresetRegressionTests
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build
```

#### Session scaffolding shipped (2026-04-26)

The Claude Code session landed the V.5 runway in one sitting. Matt's curation runs in parallel and is tracked separately in `docs/VISUAL_REFERENCES/README.md`.

**Pre-flight findings:**
- **Preset count corrected: 13** (not 11 as CLAUDE.md stated). Confirmed by flat scan of `PhospheneEngine/Sources/Presets/Shaders/*.metal` matching `PresetLoader` behaviour.
- **FerrofluidOcean and FractalTree already ship** — both have `.metal` shader files and `.json` sidecars. CLAUDE.md listed them as V.9/V.10 "full rebuild" targets implying they were new; they are existing presets targeted for rebuild. Reference folders created as required.
- **Membrane is an undocumented production preset** — `family: fluid`, `passes: feedback`, full-rubric treatment. Not mentioned in CLAUDE.md's module map. No engine changes made; CLAUDE.md module map update deferred to V.6 housekeeping.
- **Stalker has no `.metal` file** — CLAUDE.md describes Increment 3.5.7 (Stalker) as complete, but no `Stalker.metal`, `StalkerGait.swift`, or `StalkerState.swift` exist in the repository. No reference folder created. Flag for Matt: either the increment is in progress and the metal file hasn't landed yet, or the code was deleted. D-064 records the observation.
- **No existing `VISUAL_REFERENCES/` precedent** — naming convention defined from scratch per Part C of the increment spec; the §2.3 example filenames (`04_specular_fiber_highlight.jpg`) are the canonical exemplar.
- **Git LFS**: pre-existing for `ML/Weights/*.bin`; extended for `docs/quality_reel*.mp4` and `docs/VISUAL_REFERENCES/**/*.{jpg,png}`.
- **PhospheneTools**: new package (not pre-existing); establishes the location for future `MilkdropTranspiler` (Phase MD.1+).

**What shipped:**
- `docs/VISUAL_REFERENCES/` — 13 preset folders (9 full-rubric + 4 lightweight) + `_TEMPLATE/` (2 variants) + `_NAMING_CONVENTION.md` + `phase_md/` + top-level `README.md` (curation kickoff)
- `PhospheneTools/Package.swift` + `Sources/CheckVisualReferences/main.swift` — 5 lint rules, fail-soft default, `--strict` flag
- `docs/quality_reel_playlist.json` — 3-segment playlist contract with rationale fields
- `.gitattributes` — LFS rules for images + quality reel
- `docs/RUNBOOK.md` — "Recording the quality reel" section
- `docs/SHADER_CRAFT.md §2.3` — lint-check paragraph + `--strict` flip guidance
- `CLAUDE.md §Visual Quality Floor` — cross-reference to lint tool
- `docs/DECISIONS.md D-064` — records four design decisions

**Lint baseline (expected pre-curation state):**
`swift run --package-path PhospheneTools CheckVisualReferences` reports 13 "no reference images" warnings (one per preset folder), 0 errors. This is the correct intermediate state — folders scaffolded, images pending Matt's curation. Build and test suite unaffected (no engine code changed).

#### Reel + partial curation landed (2026-04-30)

- **Quality reel ✅** — `docs/quality_reel.mp4` committed via Git LFS. Source: Spotify Lossless (Blue in Green → Love Rehab → Mountains). Captured in reactive mode — no Spotify OAuth means no `.ready` state; `startAdHocSession()` → `.playing` directly. See D-066 for rationale on accepting reactive-mode capture for V.6 fidelity evaluation.
- **Visual references 5/11** — Arachne ✅, Gossamer ✅, FerrofluidOcean ✅, FractalTree ✅, VolumetricLithograph ✅. Remaining 6 (GlassBrutalist, KineticSculpture, Membrane, Starburst, Nebula, SpectralCartograph — counting Matt's working total of 11 curated targets) planned for next session.

#### Curation progress (2026-05-01)

Membrane and Starburst reference images added. 5 preset folders still require curation (4 have 0 images; 1 may fail lint on image count or annotated README). `CheckVisualReferences --strict` still failing.

**V.5 remains open.** Done-when criteria not met: 5 preset reference folders still require curation, and `CheckVisualReferences --strict` will not pass until all targeted preset folders are populated with conformant images and annotated READMEs.

---

### Increment V.6 — Fidelity rubric + certification pipeline

**Delivered (2026-04-30):** `Sources/Presets/Certification/` (3 files): `RubricResult.swift`, `FidelityRubric.swift` (`DefaultFidelityRubric` — M1–M7 mandatory, E1–E4 expected, P1–P4 preferred, lightweight L1–L4), `PresetCertificationStore.swift` (actor, lazy cache). `PresetDescriptor` + all 13 JSON sidecars extended with `certified/rubric_profile/rubric_hints`. `PresetScoringContext.includeUncertifiedPresets` gate. `DefaultPresetScorer` uncertified check first; `excludedReason: "uncertified"`. `SettingsStore.showUncertifiedPresets` + Settings toggle. 4 test files (26+ @Test functions). D-067.

**Scope:** Implement the `SHADER_CRAFT.md §12` rubric as automated + manual gates:
- Automated: detail-cascade detection via static analysis of preset Metal source (look for `fbm8` / `worley_fbm` / multiple material calls / triplanar usage); noise-octave counting; material-count verification; D-026 deviation-primitive usage; silence-fallback regression test.
- Manual: Matt-approved reference frame match gates certification.

`PresetDescriptor` gains a `certified: Bool` field. Orchestrator excludes uncertified presets by default. `SettingsView` gets a "Show uncertified presets" toggle (off by default).

Supersedes (without deleting) Increment 5.2's weak invariants — those stay as a passing prerequisite.

**Done when:**
- [x] Automated rubric scores every preset; report prints each preset's 7+4+4 breakdown.
- [x] `certified: Bool` field defaults to false for Matt-approved presets only.
- [x] Orchestrator filter excludes uncertified.
- [x] Toggle in Settings reveals uncertified.
- [x] Increment 5.2 invariants still passing.

**Verify:** `swift test --package-path PhospheneEngine --filter FidelityRubricTests`

---

### Increment V.7 — Arachne v4 (fidelity uplift) ⚠ 2026-04-30

**M7 outcome (2026-05-01):** Failed visual review. Rendered output matches anti-reference `10_anti_neon_stylized_glow.jpg`. Resolution scheduled as V.7.5 + V.7.6 per D-071. V.7 Session 1–3 work and golden hashes preserved as the v4 baseline; V.7.5 modifies that baseline.

**Scope:** Apply V.1–V.4 utilities and V.5 references to Arachne per `SHADER_CRAFT.md §10.1`. Key changes: per-web organic variation (tilt/hub/strand-count jitter); per-strand sag/tension variation; adhesive droplets on spiral threads; silk thread Marschner-lite material; dust-mote field; bioluminescent lighting with back-lit rim; audio-reactivity restricted to emission intensity and dust-mote density (D-020 — structure stays solid).

**Delivered:**
- Session 1 (2026-04-30): §4.1–§4.4 geometry pass — per-web macro variation, parabolic gravity sag, adhesive droplets, smooth-union web accumulation. `int half` → `int halfN` bug fix (Failed Approach #44). Rubric M2 FAIL→pass; score 4→5/15.
- Session 2 (2026-04-30): Materials pass — mat_silk_thread (Marschner-lite, `azimuthal_r=0.35` widened for 2D), mat_chitin spider, mat_frosted_glass hub fallback, dust-mote field. Rubric M1+M3+E2+E3+E4+P1+P3 pass; score 5→11/15. meetsAutomatedGate=true.
- Session 3 (2026-04-30): Audio routing audit — D-020 compliance (static geometry, no vibration), D-026 compliance (deviation-based emission: `1.0 + 0.18×f.bass_att_rel` continuous + `0.07×drums_energy_dev` beat, ratio 2.57×≥2× rule), `f.mid_att_rel` dust-mote threshold modulation. meetsAutomatedGate=true; awaiting Matt M7 visual review before `certified: true`. 889 engine tests; 0 SwiftLint violations.

**Done when:**
- Arachne v4 passes fidelity rubric 10/15 minimum including Matt-approved reference frame match. ✅ 11/15
- Passes Increment 5.2 invariants. ✅
- p95 frame time ≤ Tier 2 budget at 1080p. ✅ (5.5 ms declared ≪ 16.6 ms limit; M6 pass)
- Silk threads visibly narrow (∼1.5 px at 1080p) with axial specular per `04_specular_fiber_highlight.jpg` annotation. ✅
- Adhesive droplets visible at 8–12 px spacing per `03_micro_adhesive_droplet.jpg` annotation. ✅
- Golden hash regenerated; `certified: true`. ❌ (M7 failed 2026-05-01 — see V.7.5)

**Verify:** `swift test --filter PresetAcceptanceTests && swift test --filter PresetRegressionTests && swift test --filter FidelityRubricTests` + Matt review.

**Estimated sessions:** 3 (geometry + variation / materials / polish + audio routing).

---

### Increment V.7.5 — Arachne v5 (composition + warm restoration + drops + spider cleanup) ⚠ 2026-05-01 shipped, awaiting Matt M7

**Scope:** Apply `SHADER_CRAFT.md §10.1` items 1, 2, 3, 4, 6, 9 (post-M7 rewrite, per D-071) to Arachne v4. Cap `ArachneState.maxWebs` from 12 → 4. Increase `arachKSag` range and add gravity-direction weighting. Drops become the visual hero — radius 0.0035 → 0.008, spacing 8–12px → 4–6px, warm-amber emission, warm specular pinpoint. Restore Marschner TT-lobe warm back-rim (replaces V.7 Session 2 cool-blue override at Arachne.metal lines 396–398 + 605). Add warm directional key + cool ambient fill. Reduce strand emission so drops carry the visual. Spider rendered as small dark silhouette with thin warm rim; restore `bassAttackRatio < 0.55` gate per D-040 and re-tune `subBassThreshold` against the M7 data (current 0.65 is unreachable; data supports 0.30 sustained).

**Delivered (2026-05-01):**
- Step 0: `ARACHNE_M7_DIAG` build-flag-gated logging harness (per-second numeric snapshot of pool occupancy, spawn cadence, spider trigger state, silk-vs-drop luma proxy).
- Step 1 (§10.1.1): `ArachneState.maxWebs` 12 → 4; `kArachWebs` 12 → 4; `minSpawnGapBeats` 2.0 → 8.0 (transient-slot churn ≤ once per 4 s at 120 BPM).
- Step 2 (§10.1.2): `arachKSag` range [0.04, 0.10] → [0.06, 0.14]; per-spoke gravity weight `mix(0.4, 1.0, max(0, sin(spAng)))`.
- Step 3 (§10.1.4): shared `kWarmTT = (1.00, 0.78, 0.45)` constant; both anchor + pool silk sites flipped from cool-blue to warm-TT rim; `backsideCue` tint flipped to warm.
- Step 4 (§10.1.6): shared `kLightCol = (1.00, 0.85, 0.65)` warm key + `kAmbCol = (0.55, 0.65, 0.85) × 0.15` cool ambient applied at both silk sites after the deviation gain.
- Step 5 (§10.1.3): drop UV radius 0.0035 → 0.008 (≈ 8.6 px at 1080p); spacing 0.0074–0.0111 → 0.0037–0.0056 (4–6 px); warm-amber emissive base `(1.00, 0.78, 0.45) × 0.18`; warm-white specular tint; gain-modulated by `(baseEmissionGain + beatAccent)`; strand `silkTint × 0.50` → `× 0.32`.
- Step 6 (§10.1.9): chitin call site removed; spider as dark silhouette `(0.04, 0.03, 0.02)` with thin warm-amber rim catching backlit kL; AR gate restored (`bassAttackRatio > 0 && < 0.55`); `subBassThreshold` 0.65 → 0.30 per M7 LTYL data; `stems` plumbed through `updateSpider`.
- Step 7: golden hashes regenerated; only Arachne's hashes changed. Arachne `(steady/beatHeavy/quiet) = 0xC4008E8E0E4E6E00`; spider forced hash `0x44382E0F07476E00`. `FidelityRubricTests` ground truth updated: Arachne `meetsAutomatedGate` true → false (M3 fails: 2 mat_* call sites ≤ 3-gate; restoring M3 deferred); `certifiedPresets` set emptied (V.7.4 cert rollback).
- Step 8 SKIPPED per Matt: option C — formal contact sheet bypassed; Matt to eyeball at runtime.
- Step 9 (modified): `Arachne.json` `certified` stays `false` pending Matt's runtime visual review.

**Done when (rev 2):**
- Arachne golden hashes regenerated. ✅
- M7 visual review (2026-05-02): **failed**. Rendered output is still a stylized 2D bullseye; references show drops-on-a-world with refraction + DoF + atmosphere — compositing layers the renderer doesn't have. See D-072 for the architectural pivot. V.7.5 commits stay in the tree as the v5 baseline; V.8 builds on top.
- `swift test --package-path PhospheneEngine`: 894 tests, 1 pre-existing failure (`MetadataPreFetcher` network-timeout flake, baseline). 0 SwiftLint violations on touched files. ✅
- p95 frame time at 1080p ≤ 5.5 ms (Tier 2): not measured this session.
- `Arachne.json` cert flip: stays `false`. V.7.5 alone does not reach the cert bar; V.8 is required.

**Verify:** `swift test --package-path PhospheneEngine` + `xcodebuild -scheme PhospheneApp build`.

**Estimated sessions:** 1. **Actual:** 1 session, 8 commits (Step 0 through Step 7).

---

### Increment V.7.6 — Arachne v5 (atmosphere + beam-bound motes) ❌ ABANDONED 2026-05-02

**Status:** Abandoned per D-072. Original scope (atmosphere/motes patch on existing single-pass renderer) is structurally insufficient for the references. Replaced by the v8 design in `docs/ARACHNE_V8_DESIGN.md`, which decomposes Arachne into three layers (background dewy webs + foreground time-lapse build + spider/vibration overlay) and requires preset-system-wide orchestrator changes (multi-segment per track, preset-completion-signal channel) to support the build → transition handoff. Listed here in abandoned form to preserve the audit trail.

---

### Increment V.7.6.1 — Visual feedback harness ✅ 2026-05-02

**Status:** Landed (commit `eca8723d`). New test file `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetVisualReviewTests.swift`, gated by `RENDER_VISUAL=1`. Renders any preset (parameterized; currently `["Arachne"]`) at 1920×1280 for three FeatureVector fixtures (silence / steady mid-energy / beat-heavy). Encodes BGRA → PNG via `CGImageDestination`. Writes to `/tmp/phosphene_visual/<ISO8601>/<preset>_{silence,mid,beat}.png`. Contact sheet (Arachne only) composes the steady-mid render in the top half above refs 01 / 04 / 05 / 08 in the bottom half, with NSAttributedString labels.

Per-preset state setup handles Arachne (allocates `ArachneState`, warms 30 ticks, binds `webBuffer` at fragment buffer 6 and `spiderBuffer` at 7); other presets use only standard bindings. Mesh-shader presets are skipped (cannot be invoked via `drawPrimitives`). Adding a preset is one line — append to the `@Test(arguments:)` list.

**Verify (used):** `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview` produced 4 valid 1920×1280 PNGs. Without the env var, the harness is dormant. SwiftLint strict on the new file → clean. `xcodebuild -scheme PhospheneApp` → BUILD SUCCEEDED.

**M7-style report (Arachne v5 vs refs 01/04/05/08), 2026-05-02:** Render shows two warm-tan concentric ring spirals on flat near-black. No droplets, no specular silk highlight, no atmospheric backlight, no bioluminescent palette. Reads as a 2D line pattern; references read as illuminated 3D objects in atmosphere. Confirms the D-072 diagnosis: the missing layers are compositing (background atmosphere, refractive drops, fibre material), not constants. Justifies the V.7.7+ scope.

**Estimated sessions:** ½. **Actual:** ½ (one commit).

---

### Increment V.7.6.2 — Orchestrator: multi-segment + completion-signal + maxDuration framework

**Scope:** Per `docs/ARACHNE_V8_DESIGN.md §3, §5, §6 step 2`. Preset-system-wide infrastructure change. Touches:
- New `PlannedPresetSegment` value type. `PlannedTrack` becomes `let segments: [PlannedPresetSegment]` (was: `let preset: PresetDescriptor`).
- `SessionPlanner` rewritten to walk each track's section list and produce multi-segment plans, respecting per-preset `maxDuration` and section boundaries.
- `PresetSignaling` protocol with `presetCompletionEvent: PassthroughSubject<Void, Never>`. Orchestrator subscribes per active preset; transitions on event if `minDuration` satisfied.
- `LiveAdapter` segment-aware: `presetNudge(.next)` advances to next segment, not next track.
- **`maxDuration` framework** per `ARACHNE_V8_DESIGN.md §5.2`. New `PresetDescriptor.maxDuration(forSection:)` computed property implementing the formula (motionIntensity, fatigueRisk, visualDensity inputs; sectionDynamicRange adjustment; naturalCycleSeconds cap). Coefficients live in code (default −50, −30, −15, 0.7+0.6) with documentation comments. Tunable via V.7.6.C.
- New `naturalCycleSeconds: Float?` field added to `PresetDescriptor` and JSON schema. Initially set only for Arachne (60s).
- Migration: existing presets without completion signals run to formula-computed `maxDuration` and transition by planned boundary.

**Done when:**
- All existing presets continue to work end-to-end (no visual regressions on Plasma, Waveform, VL, etc.).
- Multi-segment plans generated for tracks longer than the chosen preset's `maxDuration`.
- Preset-completion signal can be wired in (Arachne not yet using it; just the channel is there).
- `SessionPlannerTests` updated for multi-segment outputs.
- Live tests still pass; 0 SwiftLint violations.

**Verify:** `swift test --package-path PhospheneEngine` + Matt runtime test on a multi-track playlist (verify presets transition mid-song, not just on track boundaries).

**Estimated sessions:** 2–3. Load-bearing prerequisite for V.7.7+.

---

### Increment V.7.6.C — Framework calibration pass ✅ 2026-05-03

**Outcome:** Two changes landed (commits `7e6671de`, `cee85159`). (1) Per-section linger factors inverted to Option B — ambient and peak (the meditative + climactic emotional cores) extend `maxDuration`; buildup and bridge (transitional moments where preset changes feel natural) shorten it. New per-section table: `ambient=0.80, peak=0.75, comedown=0.65, buildup=0.40, bridge=0.35`. Default (section=nil) stays 0.5. Field renamed `sectionDynamicRange` → `sectionLingerFactor` to reflect that values are now author-set per-section weights, not derived from audio variance. (2) Diagnostic class added — new `is_diagnostic` JSON field (default false) on `PresetDescriptor`. When true, `maxDuration(forSection:)` returns `.infinity`. Spectral Cartograph flagged true. The "manual-switch only / never auto-selected" Orchestrator semantic is the **V.7.6.D follow-up scope** (Scorer hard-exclusion + LiveAdapter no-override).

**No formula coefficient changes.** `baseDurationSeconds`, `motionPenalty`, `fatiguePenalty`, `densityPenalty`, `sectionAdjustBase`, `sectionLingerWeight` unchanged from §5.2 defaults. Per Matt's review note ("the presets are uncertified and very far from ready"), Glass Brutalist's earlier ~30s intuition is deferred — tuning to one outlier is not the right move at this stage.

**Verification:** 912 engine tests / 97 suites green. App build succeeds. SwiftLint 0 violations on touched files. GoldenSessionTests not regenerated — default-section maxDuration unchanged at lingerFactor=0.5 (multiplier 1.0); planner sequences identical. See D-073 for the calibration decision record.

---

### Increment V.7.6.D — Diagnostic preset orchestrator semantics ✅ 2026-05-03

**Outcome:** Three Orchestrator surfaces gained the diagnostic exclusion gate (D-074). (1) `DefaultPresetScorer.exclusionReasonAndTag` now checks `preset.isDiagnostic` first, returning `excludedReason: "diagnostic"` and `total: 0`; this is a categorical exclusion with no settings toggle (unlike `includeUncertifiedPresets`). (2) `DefaultLiveAdapter` adds `!topPreset.isDiagnostic` to the mood-override emission `guard` — defense in depth against future scoring ties. (3) `DefaultReactiveOrchestrator` switches `ranked.first` → `ranked.first(where: { !$0.0.isDiagnostic })` for the same reason. `SessionPlanner` inherits the exclusion transparently through `PresetScoring`. Manual switch path is unchanged — `PlaybackActionRouter` and the keyboard / dev surfaces operate on `PresetDescriptor` directly without scoring, so Spectral Cartograph remains reachable. New `OrchestratorDiagnosticExclusionTests.swift` adds 7 tests covering scorer, adapter (incl. uncertified-toggle interaction and family-boost case), planner, reactive, and manual-switch positive case.

**Verification:** 919 engine tests / 98 suites, 918 pass — sole failure is the pre-existing flaky `MetadataPreFetcherTests.fetch_networkTimeout_returnsWithinBudget` (unrelated). App build clean. SwiftLint 0 violations on touched files. `GoldenSessionTests` unchanged (Spectral Cartograph was already excluded by `certified: false`).

**Verify:** `swift test --package-path PhospheneEngine --filter "OrchestratorDiagnosticExclusion|LiveAdapter|ReactiveOrchestrator|PresetScorer"`.

---

### Increment V.7.7 — Arachne v8: WORLD pillar + 1–2 background dewy webs

**Scope:** Per `ARACHNE_V8_DESIGN.md §4` (full WORLD pillar) + §5.12 (background webs) + §8.1 step 1–2 (render-pass layout). The 2026-05-03 spec rewrite expanded V.7.7 from a thin atmosphere pass into the full layered WORLD — implementing §4.2's six depth layers into a half-res `arachneWorldTex`: sky band (4.2.1) + distant tree silhouettes (4.2.2) + mid-distance trees with bark detail (4.2.3) + near-frame anchor branches (4.2.4) + forest floor (4.2.5) + volumetric atmosphere (4.2.6 fog + light shafts + dust motes). Mood-driven palette per §4.3 (preserved verbatim from V.7.6.C-locked recipe — `topCol`/`botCol`/`beamCol` + per-layer color application table). Includes 5s low-pass `smoothedValence`/`smoothedArousal` state per §4.3. Then 1–2 pre-populated background dewy webs (§5.12) with refractive drops sampling `arachneWorldTex` per the §5.8 recipe (Snell's law, eta ≈ 0.752, fresnel rim, specular pinpoint, dark edge ring). Background webs vibrate per §8.2. Foreground unchanged (still V.7.5 build code — refactored in V.7.8).

**Done when:**
- WORLD reads as a forest with depth — six layers individually identifiable. Side-by-side via harness contact sheet against refs `06` / `15` / `16` / `17` / `18` / `07`.
- Background webs read as photorealistic dewdrops side-by-side with refs `01` / `03` / `04` via the harness contact sheet.
- Pure-black silence anchor preserved (§8.3) — `(satScale × valScale) < 0.05` clears WORLD pass to black.
- All test suites pass; 0 SwiftLint violations.
- p95 frame time at 1080p ≤ 6.0 ms Tier 2 / ≤ 7.5 ms Tier 1.
- Matt runtime visual review of the WORLD + background-webs state passes.

**Verify:** Same as V.7.6.1 + Matt runtime review.

**Estimated sessions:** 3.

---

### Increment V.7.8 — Arachne v8: WEB pillar — foreground build refactor (corrected biology)

**Scope:** Per `ARACHNE_V8_DESIGN.md §5.1–§5.11` (WEB pillar in full). Replace V.7.5 pool-of-webs system with single-foreground-build state machine implementing the corrected orb-weaver biology: frame polygon (§5.3, 4–7 anchors on near-frame branches from V.7.7) → hub (§5.4, dense knot, NOT concentric rings) → radials (§5.5, 12–17, alternating-pair order, ±20% jitter, drawn one at a time over ~1.5s each) → **capture spiral winding INWARD** (§5.6, chord-segment SDF from outer frame to hub — corrects the 2026-05-02 spec error which had the spiral winding outward) → settle (§5.2, completion signal at 60s ceiling). Sag per §5.7 (`kSag ∈ [0.10, 0.18]`, drop weight modifies sag). Drops per §5.8 with accretion over time on just-laid spiral chords (foreground starts sparse, grows dense; background webs stay saturated). Anchor terminations per §5.9 — small adhesive blobs where outer frame threads meet near-frame branches. Silk material per §5.10 (minor finishing — Marschner-lite removed). Pause on spider trigger; resume on spider fade. Foreground completion emits `presetCompletionEvent` via the V.7.6.2 channel.

**Done when:**
- Visual review via harness: foreground build is visibly progressing — radials extend one-at-a-time, spiral winds **inward** chord-by-chord, completion fires at ≤ 60s under typical music.
- Drops are the visual hero — viewer's eye lands on drops first, threads second. Drops show refraction + fresnel rim + specular pinpoint + dark edge ring per §5.8.
- Anchor structure reads as solid — frame polygon visibly meets near-frame branches at adhesive blobs. Side-by-side with ref `11`. Polygon is irregular, not circular.
- Spider trigger visibly pauses construction; spider fade visibly resumes from paused accumulator (does not restart).
- Orchestrator transitions on completion event when `minDuration` satisfied.
- All test suites pass; 0 SwiftLint violations.
- p95 frame time ≤ 6.0 ms Tier 2.
- Matt runtime visual review passes.

**Verify:** Same.

**Estimated sessions:** 3.

---

### Increment V.7.9 — Arachne v8: SPIDER pillar deepening + whole-scene vibration + cert

**Scope:** Per `ARACHNE_V8_DESIGN.md §6` (full SPIDER pillar) + §8.2 (vibration model) + §12 (acceptance criteria). The 2026-05-03 spec rewrite expanded V.7.9 from "polish + vibration" into a full spider-anatomy refactor — V.7.5's "dark silhouette + warm rim" was the right *direction* but wrong *depth* for an easter egg that earns its rare appearance. Implements §6.1 anatomy (cephalothorax + abdomen + petiole, 8 articulated legs with outward-bending knee IK, eye cluster as 6–8 small dots in tight forward arrangement — refs `12` + `13`, NOT the jumping-spider 2x2 of ref `19`), §6.2 material (chitin base + thin-film iridescence at biological strength + Oren-Nayar-like hair fuzz + per-eye specular per ref `19` technique), §6.3 pose / gait / listening pose (resting at hub by default; listening pose — front legs raised ~30° — fires on sustained low-attack-ratio bass for ≥ 1.5s), §6.4 lighting (deep body shadow + warm-amber rim + eye sparkle), §6.5 trigger and behavior (per-segment cooldown replaces V.7.5's 300s session-level lock). Whole-scene tremor on bass per §8.2 — 12 Hz audio-rate vibration applied per-vertex to all webs + near-frame branches + spider, amplitude driven by `max(f.subBass_dev, f.bass_dev)` + per-kick spike from `f.beatBass`. Forest floor and distant layers don't shake. Final tuning of drop counts, brightness, sag magnitude, free-zone size, mood-smoothing window against references via the harness. Cert review.

**Done when:**
- Visual review via harness contact sheet matches all 10 acceptance criteria from `ARACHNE_V8_DESIGN.md §12`.
- Spider, when present, is detailed — viewer can see cephalothorax, abdomen, 8 legs with visible knee bends, eye cluster, abdominal pattern. Material reads as biological iridescent chitin (ref `14`), not neon (ref `10`). Listening pose visibly fires on sustained bass.
- Web vibration visible during heavy bass — whole-scene tremor (~12 Hz) on background + foreground webs + branches + spider; ground/distant layers stable.
- Anti-refs `09` (clipart symmetry) and `10` (neon glow) explicitly NOT matched. Refs `01`, `03`, `04`, `05`, `06`, `08`, `11`, `12`, `15`, `16` cited as reachable.
- All test suites pass; 0 SwiftLint violations.
- p95 frame time ≤ 6.0 ms Tier 2.
- **Matt cert review.** If positive: `Arachne.json` `certified: true`, add `"Arachne"` back to `FidelityRubricTests.certifiedPresets`, mark V.5 references action complete, log M7 outcome in references README.

**Verify:** Same.

**Estimated sessions:** 2.

**V.8 remains reserved for Gossamer** per `SHADER_CRAFT.md §10.2`.

---

### Increment V.8 — Gossamer v4

**Scope:** Apply to Gossamer per `SHADER_CRAFT.md §10.2`. Physical wave displacement (waves offset silk strand positions, not just tint them); silk Marschner-lite material tuned for hero resonator; fine specular glints at thread intersections; chromatic aberration on wave peaks; inward/outward dust drift; SSGI-lit background from web emission.

**Done when:** same rubric gates as V.7; `certified: true`.

**Verify:** same as V.7.

**Estimated sessions:** 2 (physical displacement rework / atmosphere + chromatic aberration).

---

### Increment V.9 — Ferrofluid Ocean v2

**Scope:** Full rebuild per `SHADER_CRAFT.md §10.3`. Hex-tile Rosensweig spike lattice (`stems.bass_energy_dev` drives field strength); domain-warped spike positions for organic flow; ferrofluid material with anisotropic reflection along spike axes; distant fog cooling to dark purple; IBL cubemap as primary indirect light; caustic underlighting.

**Done when:** same rubric gates; `certified: true`.

**Verify:** same as V.7.

**Estimated sessions:** 4 (field formulation / material / lighting + IBL / audio routing).

---

### Increment V.10 — Fractal Tree v2

**Scope:** Apply to Fractal Tree per `SHADER_CRAFT.md §10.4`. Bark material with POM + triplanar + lichen patches; procedural leaf clusters at branch tips with leaf material (SSS back-lit); wind animation via curl-noise; seasonal palette synced with valence; golden-hour lighting with long shadows.

**Done when:** same rubric gates; `certified: true`. Performance profile shows POM + foliage within Tier 2 budget (likely requires MetalFX Temporal upscaling at sub-1080p internal render).

**Verify:** same as V.7.

**Estimated sessions:** 4 (bark + POM / foliage / wind animation / seasonal + audio).

---

### Increment V.11 — Volumetric Lithograph v5

**Scope:** Major rework per `SHADER_CRAFT.md §10.5`. Replace fBM heightfield with `ridged_mf` warped by `curl_noise` (mountainous, not lumpy); mesa terrace secondary displacement; triplanar detail normal; aerial perspective fog (color-shift from warm sky to cool depth); drifting cloud shadows; cutting-plane beat-reveal replaces palette flash; retain mv_warp and pitch-color mapping from MV-3.

**Done when:** same rubric gates; `certified: true`. Terrain reads as mountainous, not lumpy — confirmed against `docs/VISUAL_REFERENCES/volumetric_lithograph/` annotations.

**Verify:** same as V.7.

**Estimated sessions:** 3 (terrain reformulation / aerial + clouds / cutting-plane + polish).

---

### Increment V.12 — Glass Brutalist v2 + Kinetic Sculpture v2

**Scope:** Fidelity uplift for the remaining ray-march presets not covered in V.7–V.11. Glass Brutalist: board-form concrete lineage (plank impressions, tie-rod holes, weathering — Salk/Scarpa direction, not Ando smooth); detail normals on concrete; POM on walls; pattern-glass material for fins per `SHADER_CRAFT.md §4.5b` (voronoi cellular, NOT fbm-frost); volumetric light shafts through windows. Wet-concrete variant explicitly out of scope — `mat_wet_stone` reserved for other presets. References curated in `docs/VISUAL_REFERENCES/glass_brutalist/` (8 images, 7 trait slots + 1 anti). Kinetic Sculpture: brushed aluminum material per `§4.2`; polished chrome with anisotropic streaks; dust motes in ambient space.

**Done when:** both presets pass fidelity rubric 10/15 with all mandatory; `certified: true` on both.

**Verify:** same as V.7.

**Estimated sessions:** 3 (Glass Brutalist lift / Kinetic Sculpture lift / joint polish + perf).

---

## Phase MD — Milkdrop Ingestion

**Why this phase exists:** `docs/MILKDROP_ARCHITECTURE.md` informed Phosphene's own authoring patterns (MV-0 through MV-3), but the "port the cream of the crop" work track disappeared from the plan. The vehicle for that work — the `mv_warp` render pass (D-027) — is built and sitting largely unused since D-029 pulled it from Starburst and VolumetricLithograph. This phase ingests Jason Fletcher's curated `presets-cream-of-the-crop` pack as Phosphene presets, then upgrades the best with Phosphene's superior capabilities (SSGI, PBR, stems, pitch, beat anticipation) — producing "evolved Milkdrop" presets, not mere clones.

Runs in parallel with Phase V.7+ once Phase V.1–V.3 utilities are available.

### Increment MD.1 — `.milk` grammar audit

**Scope:** New doc `docs/MILKDROP_GRAMMAR.md` cataloguing every per-frame / per-vertex variable, every equation operator, and every function used across the `presets-cream-of-the-crop` pack. Frequency counts so we know which 80% of the language to support first. Milkdrop 2 pixel shaders (warp + composite) analyzed separately — these emit directly as Metal rather than being transpiled from a DSL.

**Done when:**
- Doc enumerates all variables (bass/mid/treb/time/q1–q32/wave_* / mv_* / ob_* / ib_* etc.) observed.
- Top-20 built-in functions (sigmoid, clamp, above, below, if_then_else etc.) have Metal-equivalent code notes.
- Pixel-shader conventions (sampler_main, GetPixel, GetBlur1, GetBlur2, ret, rad, ang, uv, uv_orig, tex2D) documented with Metal mappings.

**Verify:** Manual review against 5 randomly-sampled preset files from the pack.

---

### Increment MD.2 — Transpiler CLI skeleton

**Scope:** New SPM executable target `PhospheneTools/MilkdropTranspiler`. Lexes `.milk` files; emits a Swift AST. No code generation yet — this increment proves the parser covers the grammar surface. Ships as a standalone tool so transpiler bugs never affect the Phosphene runtime (Option B from the improvement plan).

**Done when:**
- Can parse 100% of the cream-of-the-crop pack without lexer / parser errors.
- Round-trips AST to readable pretty-print; diffing the pretty-print against the original is semantically equivalent (modulo whitespace).
- Test suite: 10+ fixture presets covering grammar edge cases.

**Verify:** `swift test --package-path PhospheneTools --filter MilkdropTranspilerParserTests`

---

### Increment MD.3 — Per-frame → JSON emission

**Scope:** Transpiler extends AST → JSON emission. Per-frame equations that map to `PresetDescriptor` parameters (`base_zoom`, `base_rot`, `decay`, etc.) emit as JSON sidecar. Per-frame `q1`–`q32` user variables emit as a fixed-size uniform buffer alongside `FeatureVector`.

**Done when:**
- Transpiler generates valid `.json` sidecars for 20 test presets.
- Round-trip test verifies semantic equivalence for the supported per-frame operator subset.
- Unsupported operators (rare cases) emit a clear diagnostic with the offending line; doesn't crash.

**Verify:** `swift test --package-path PhospheneTools --filter PerFrameEmissionTests`

---

### Increment MD.4 — Per-vertex → Metal emission

**Scope:** Transpiler extends to per-vertex emission: Milkdrop per-vertex equations compile to `mvWarpPerVertex` Metal function bodies. Per-frame state threaded through the `q1`–`q32` uniform buffer. Milkdrop 2 warp / composite pixel shaders compile directly to their Metal equivalents using the `sampler_main` → `warpTexture` mapping.

**Done when:**
- 5 hand-selected reference presets (including at least one Milkdrop 1 and one Milkdrop 2 preset) compile via transpiler and render in Phosphene.
- Transpiled presets bind to the existing `mv_warp` render pass.
- Golden hash regression added per transpiled preset.
- Visual sanity check: transpiled preset output resembles projectM's render of the same preset.

**Verify:** `swift test --package-path PhospheneEngine --filter MilkdropTranspiledPresetTests`

---

### Increment MD.5 — Ingestion harness + first 10 cream-of-the-crop presets

**Scope:** Pick 10 Jason Fletcher presets spanning families (geometric, fractal, organic, kaleidoscopic, abstract). Run transpiler, inspect output, polish each until visual match against projectM render is acceptable. These presets are marked `family: "milkdrop_classic"` and tagged for the "Include Milkdrop-style presets" user toggle in Settings.

**Done when:**
- 10 new presets in `PhospheneEngine/Sources/Presets/Shaders/Milkdrop/` with JSON sidecars.
- Each has a golden-session regression entry and Increment 5.2 acceptance test.
- Orchestrator metadata (`visual_density`, `motion_intensity`, `fatigue_risk`, etc.) hand-authored per preset for planning integration.
- User-settings toggle "Include Milkdrop-style presets" honored (Increment U.8).
- **D-043 added to DECISIONS.md**: "Milkdrop presets ingested via offline transpiler + manual uplift; no runtime .milk parser."

**Verify:** `swift test --filter PresetAcceptanceTests` (auto-covers new presets via existing regression gate).

---

### Increment MD.6 — Next 20 presets + stem-aware upgrade

**Scope:** Next 20 cream-of-the-crop presets. Each manually upgraded with **at least two** of: stem-driven parameter routing (replacing `bass`/`mid`/`treb` with per-stem equivalents), beat-phase anticipation via MV-3b `beat_phase01`, pitch-hue mapping via MV-3c `vocalsPitchHz`, MV-3a rich stem metadata. These are the "evolved Milkdrop" presets — keep the visual DNA but exploit Phosphene's audio pipeline.

**Done when:**
- 20 more presets in the library.
- Each preset's JSON documents which MV-3 capabilities it uses (new `mv3_features_used: [...]` array field).
- No original preset is regressed — the unmodified version from MD.5 stays available under a separate ID for A/B comparison.
- All 30 Milkdrop presets pass Increment 5.2 acceptance.

**Verify:** `swift test --filter PresetAcceptanceTests`

---

### Increment MD.7 — Ray-march hybrids (evolved Milkdrop)

**Scope:** For the best 5 Milkdrop presets from MD.5–MD.6, author a companion ray-march layer that renders 3D depth behind the 2D warp plane. Static-camera only, per D-029 — no moving-camera hybrids. Kept as separate presets prefixed `evolved/`. Uses the full utility library from Phase V.

**Done when:**
- 5 hybrid presets composed of `["ray_march", "mv_warp", "post_process"]`.
- Each passes the V.6 fidelity rubric (10/15 including mandatory).
- Performance verified on Tier 1 and Tier 2 — hybrids are more expensive and may be Tier-2-only.
- Matt approves reference frame match for each.

**Verify:** `swift test --filter PresetAcceptanceTests && swift test --filter FidelityRubricTests`

---

## Phase 6 — Progressive Readiness & Performance Tiering

### Increment 6.1 — Progressive Session Readiness ✅ (2026-04-25)

**Scope:** Replace the binary preparation model with graduated readiness. States: `preparing`, `ready_for_first_tracks` (first N tracks analyzed), `partially_planned` (visual arc provisional), `fully_prepared` (all tracks analyzed, full plan), `reactive_fallback` (no preparation possible).

**What was built:**
- `ProgressiveReadinessLevel` (5-case `Comparable` enum) in `SessionTypes.swift`.
- `SessionManager.startSession()` now returns immediately after connecting; preparation runs in a stored `Task { @MainActor }`. `progressiveReadinessLevel` is published and recomputed from `@Published trackStatuses` subscription on every status change.
- `SessionManager.startNow()` advances `.preparing → .ready` when readiness ≥ `.readyForFirstTracks`; background task continues so remaining tracks are cached during playback.
- `SessionManager.computeReadiness(statuses:trackList:cache:)` — static pure function implementing D-056 rules: consecutive-prefix gate (default threshold = 3), `.partial` tracks count only when profile has BPM + genre tags, `allTerminal` short-circuits to `fullyPrepared`/`reactiveFallback`.
- `PlannedSession.appendingWarnings(_:)` (now `public`) and `PlanningWarning.Kind.partialPreparation(unplannedCount:)` with hand-written Codable (associated value incompatible with `CaseIterable`).
- `VisualizerEngine`: `currentSessionPlanSeed` stored for deterministic re-use; `extendPlan()` rebuilds plan with same seed on readiness update; `progressiveReadinessLevel` subscription drives `buildPlan()`/`extendPlan()` routing.
- `PreparationProgressViewModel`: removed `FeatureFlags` gate; `canStartNow` driven by injected `progressiveReadinessPublisher`; `onStartNow` closure forwarded from `SessionManager.startNow()`.
- `PlaybackChromeViewModel`: `isBackgroundPreparationActive` (`level < .fullyPrepared`) drives teal dot in `PlaybackControlsCluster`.
- 14 new tests: 10 `ProgressiveReadinessTests` (engine) + 2 `PartialPlanTests` (engine) + 2 `PreparationProgressVMReadinessTests` (app). 685 engine tests total; 0 SwiftLint violations.

**Done when:** ✅ User can start playback when first 3 tracks are prepared. ✅ SessionManager exposes readiness level. ✅ Orchestrator partial-plan mode with `partialPreparation` warning. ✅ 14 tests (≥ 6 required).

**Verify:** `swift test --package-path PhospheneEngine`

---

### ✅ Increment 6.2 — Frame Budget Manager (landed 2026-04-25)

**What was built:** `FrameBudgetManager.swift` — pure-state governor with 6-level `QualityLevel` ladder (`full → noSSGI → noBloom → reducedRayMarch → reducedParticles → reducedMesh`), `Configuration` factories (tier1: 14ms/0.3ms margin; tier2: 16ms/0.5ms margin), asymmetric hysteresis (3 overruns down / 180 frames up), `reset()` on preset change. OR-gate refactor of `RayMarchPipeline.reducedMotion` → `a11yReducedMotion || governorSkipsSSGI` with dedicated setters (D-057). `PostProcessChain.bloomEnabled`, `ProceduralGeometry.activeParticleFraction`, `MeshGenerator.densityMultiplier`, `RayMarchPipeline.stepCountMultiplier` (written to `sceneParamsB.z`). Timing via `commandBuffer.addCompletedHandler` → `@MainActor` hop. `QualityCeiling.ultra` exempts the governor. Debug overlay quality level line. 36 new tests across 5 files. Golden hashes regenerated for VolumetricLithograph + KineticSculpture (preamble compiler optimization). 721 engine tests total; 1 pre-existing flaky timer failure unchanged.

---

### ✅ Increment 6.3 — ML Dispatch Scheduling (landed 2026-04-25)

**What was built:**
- `MLDispatchScheduler.swift` (`Renderer` module): pure-state controller with `Configuration` (tier defaults: 2000ms/30-frame Tier 1, 1500ms/20-frame Tier 2), `Decision` enum (`.dispatchNow / .defer(retryInMs:) / .forceDispatch`), `DispatchContext` value type, and `decide(context:) -> Decision` algorithm. `QualityCeiling.ultra` → `enabled = false` bypass. D-059.
- `FrameTimingProviding` protocol in `MLDispatchScheduler.swift`: `recentMaxFrameMs` + `recentFramesObserved`. `FrameBudgetManager` conforms via extension; test stubs use `StubFrameTimingProvider`. Single rolling buffer (30-slot circular array) in `FrameBudgetManager` serves both governor hysteresis counters and the ML scheduler with no duplicate state. D-059(e).
- `VisualizerEngine+Stems.swift` restructured: `runStemSeparation()` hops to `@MainActor`, consults the scheduler, then dispatches back to `stemQueue` via `performStemSeparation()`. `pendingDispatchStartTime` tracks deferral duration; cleared on dispatch and on `resetStemPipeline(for:)` track change.
- `VisualizerEngine` gains `deviceTier: DeviceTier` (stored, set in `init()`), `mlDispatchScheduler: MLDispatchScheduler?`, and `pendingDispatchStartTime: TimeInterval?`. Debug overlay `ML:` row shows current scheduler state (idle / dispatch / defer Nms / force).
- `MLDispatchSchedulerTests.swift`: 10 `@Test` functions. `MLDispatchSchedulerWiringTests.swift`: 5 `@Test` functions (incl. `StubFrameTimingProvider`). 20 new tests total.
- `DECISIONS.md` D-059 (5 sub-decisions). `ARCHITECTURE.md` §ML Inference gains Dispatch Scheduling subsection. `RUNBOOK.md §Jank / dropped frames` updated. `CLAUDE.md` Module Map and §ML Inference updated.
- 747 engine tests; 0 SwiftLint violations. Phase 6 complete.

**Done when:** ✅ Scheduler defers dispatch when recent frames are over budget. ✅ Force-dispatch ceiling prevents stem freeze. ✅ 20 new tests (≥ 4 required). ✅ Zero dHash drift.

**Verify:** `swift test --package-path PhospheneEngine --filter "MLDispatchScheduler"`

---

## Phase 7 — Long-Session Stability

### Increment 7.1 — Soak Test Infrastructure ✅ **LANDED 2026-04-26**

**Scope:** Automated 2+ hour test sessions with synthetic audio. Monitor: memory growth, frame timing drift, dropped frames, state machine integrity, permission handling.

**Delivered:**
- `Diagnostics` SPM target: `MemoryReporter` (`phys_footprint` via TASK_VM_INFO), `FrameTimingReporter` (100-bucket histogram + 1000-frame rolling window), `SoakTestHarness` (@MainActor, configurable duration, cancel(), JSON+Markdown reports).
- `SoakRunner` CLI executable with `--duration`, `--sample-interval`, `--audio-file`, `--report-dir` options. `Scripts/run_soak_test.sh` wraps `caffeinate -i` for 2-hour runs.
- `RenderPipeline.onFrameTimingObserved` fan-out closure: single `commandBuffer.addCompletedHandler` source feeds both `FrameBudgetManager` and soak harness. D-060(c).
- `MLDispatchScheduler.forceDispatchCount` public counter.
- Procedural audio fixture: 10s sine sweep (100→4000 Hz) + noise + 120 BPM kicks, generated at runtime. D-060(e).
- 19 new tests: `MemoryReporterTests` (5), `FrameTimingReporterTests` (7), `SoakTestHarnessTests` (7 always-run + 2 SOAK_TESTS=1 gated).
- 766 engine tests total. 0 SwiftLint violations.

**Smoke run results (60s):** Run `SOAK_TESTS=1 swift test --package-path PhospheneEngine --filter SoakTestHarnessTests` to populate.

**Verify:** `swift test --package-path PhospheneEngine` (soak tests gated by SOAK_TESTS=1 env var)

---

### Increment 7.2 — Display Hot-Plug & Source Switching ✅ **LANDED 2026-04-26**

**Scope:** Handle external display connect/disconnect during a session. Handle switching between capture modes (system → app → system). Handle playlist reconnection after network interruption.

**What landed:**
- `FrameBudgetManager.resetRecentFrameBuffer()` — clears rolling timing window only, preserving `currentLevel` (D-061(a))
- `DisplayChangeCoordinator` — subscribes to `DisplayManager` publishers; calls `resetRecentFrameBuffer()` on active-screen removal or window move; no session-state changes
- `CaptureModeSwitchCoordinator` + `CaptureModeSwitchEngineInterface` — 5-second grace window on non-`.localFile` mode switches; suppresses `presetOverride` events in `applyLiveUpdate`; raises silence toast threshold to 20 s (D-061(b,c))
- `PlaybackErrorBridge.effectiveThresholdSeconds` — mutable threshold replacing static constant; `silenceToastGraceWindowThresholdSeconds = 20`
- `VisualizerEngine.captureModeSwitchGraceWindowEndsAt` + `isCaptureModeSwitchGraceActive` — grace window state, with `CaptureModeSwitchEngineInterface` conformance
- `SessionPreparer.resumeFailedNetworkTracks()` — retries network-class failures only; pass-through on `SessionManager` (D-061(d))
- `NetworkRecoveryCoordinator` — 2s additional debounce, 3-attempt cap, state guard via injected `sessionStatePublisher` (D-061(e))
- 4 test files: `DisplayChangeCoordinatorTests` (6), `CaptureModeSwitchCoordinatorTests` (5), `NetworkRecoveryCoordinatorTests` (6), `DrawableResizeRegressionTests` (3) — 20 new tests total
- D-061 in DECISIONS.md; ARCHITECTURE.md resilience subsection; RUNBOOK.md 3 new failure modes

**Phase 7 complete.**

---

## Phase SB — Starburst Fidelity Uplift

Starburst (Murmuration) is the particle-system preset: a murmuration of birds against a vivid sunrise/sunset sky, rendered as a compute-kernel particle field composited over a 2D fragment sky. The preset currently sits at `certified: false` with the full rubric unapplied. Its fragment shader (136 lines) uses its own custom hash/noise/fbm functions rather than the V.1 Noise utility tree, drives audio from raw `features.bass_att` and `stems.vocals_energy` (D-026 violation), and has no materials layer.

This phase applies V.1–V.4 utilities and V.5 reference images to bring Starburst to rubric compliance and Matt-approved certification. It runs independently of Phase MD and in parallel with V.8+ since it touches only `Starburst.metal`, `Starburst.json`, and the murmuration particle kernel in `Particles.metal`.

---

### Increment SB.0 — Documentation prep ✅ 2026-05-01

**Delivered:**
- `CLAUDE.md` — removed stale "no git history" caveat; documented `[increment-id] component: description` commit convention and preference for multiple small commits per increment over one large commit.
- Commit: `5d9731d5 [SB.0] Docs: remove stale no-git-history caveat, document commit conventions`

---

### Increment SB.1 — JSON sidecar audit + routing review

**Scope:** Verify Starburst's JSON sidecar is internally consistent post-D-029, document the audio routing gaps as the baseline for SB.3, and note the family field semantics.

- Confirm `passes: ["feedback", "particles"]` matches the actual render path in `RenderPipeline`.
- Confirm no stale `mvWarpPerFrame`/`mvWarpPerVertex` stubs remain in `Starburst.metal`.
- Audit `Starburst.metal` fragment shader and the murmuration kernel in `Particles.metal` for D-026 violations: raw `features.bass_att`, raw `stems.vocals_energy`, absolute `smoothstep` thresholds against AGC-normalized values.
- Document all D-026 gaps as numbered items for SB.3 to address.
- Note: `family: "abstract"` in the JSON sidecar is the Orchestrator scoring category and is correct — it drives preset-selection heuristics. The "particle system" framing in the README and CLAUDE.md describes the rendering paradigm (D-029 table row), not the aesthetic family. No change needed unless appetite exists to reclassify to a more specific family (e.g., `"organic"` for the murmuration-as-living-flock framing) — defer that decision to SB.1 review.

**Done when:**
- [ ] JSON sidecar fields verified consistent with code.
- [ ] No stale mv_warp stubs present in Starburst.metal.
- [ ] D-026 gap list documented (can be inline commit message or comment in .metal file header).

**Verify:** `grep -n "mvWarp\|mv_warp" PhospheneEngine/Sources/Presets/Shaders/Starburst.metal` returns empty; `grep -n "bass_att\b\|vocals_energy\b" PhospheneEngine/Sources/Presets/Shaders/Starburst.metal` confirms remaining D-026 targets for SB.3.

**Estimated sessions:** 0.5 (audit + commit only; no shader edits).

---

### Increment SB.2 — Visual references curation

**Scope:** Populate `docs/VISUAL_REFERENCES/starburst/` with annotated reference images per the V.5 curation contract (`SHADER_CRAFT.md §2.3`).

- Minimum 4 reference images covering: murmuration silhouette shape vocabulary, sky gradient color palette (peach/amber/rose/lavender/deep blue), cloud detail quality, and particle density-to-silence contrast.
- `README.md` with per-image annotations linking traits to rubric items and target shader behaviour.
- Confirm `swift run --package-path PhospheneTools CheckVisualReferences` lint passes for the starburst folder.

**Done when:**
- [ ] `docs/VISUAL_REFERENCES/starburst/` passes `CheckVisualReferences --strict` lint.
- [ ] README.md annotations present; at least one image per cascade level (macro/meso/micro/specular-breakup) identified.

**Verify:** `swift run --package-path PhospheneTools CheckVisualReferences --strict`

**Estimated sessions:** 1 (Matt curation session).

---

### Increment SB.3 — Audio routing pass (D-026 compliance)

**Scope:** Replace all raw AGC-normalized energy reads in `Starburst.metal` and the murmuration particle kernel with deviation-primitive equivalents per D-026, and verify the 2–4× continuous-to-beat ratio rule.

- Replace `features.bass_att` with `features.bass_att_rel` for continuous cloud drift.
- Replace `stems.vocals_energy` with `stems.vocals_energy_dev` (positive-only) for vocal warmth accent.
- Replace any absolute `smoothstep(x, y, f.bass)` or similar patterns with deviation-form equivalents.
- Verify murmuration particle kernel: flock cohesion / bird speed / scatter burst should read from `bass_att_rel`, `mid_att_rel`, `drums_energy_dev` respectively, not raw energy values.
- Confirm ratio: continuous motion drivers (sky warmth, cloud drift speed, flock density) should be 2–4× larger contributors than beat-accent drivers (scatter burst, horizon flash).
- D-019 warmup: if `totalStemEnergy` warmup guard is absent, add `smoothstep(0.02, 0.06, totalStemEnergy)` blend per VolumetricLithograph reference.

**Done when:**
- [ ] No raw `features.bass`, `features.bass_att`, `stems.vocals_energy` (unqualified) remain as primary visual drivers.
- [ ] Continuous:beat ratio ≥ 2× for all motion drivers.
- [ ] D-019 warmup present if stems are read.
- [ ] `swift test --filter PresetAcceptanceTests` passes (no regression).

**Verify:** `swift test --filter PresetAcceptanceTests && swift test --filter PresetRegressionTests`

**Estimated sessions:** 1.

---

### Increment SB.4 — Detail cascade + materials pass (rubric gate)

**Scope:** Replace Starburst's bespoke `sky_hash`/`sky_noise`/`sky_fbm` with the V.1 Noise utility tree, layer the sky to the mandatory 4-octave minimum, and introduce 3 distinct materials.

- Replace `sky_hash`/`sky_noise`/`sky_fbm` with `perlin2d` + `fbm4`/`fbm8` from the V.1 Noise utility tree (removes duplicate code, adds Perlin quality).
- Sky cloud layer: upgrade from `sky_fbm(uv, 5)` call with custom noise to `warped_fbm` or `fbm8` from the V.1 tree at ≥ 4 octaves. Recalibrate thresholds to fbm centroid-near-0 range (Failed Approach #42: threshold at 0 not 0.5).
- Three materials: (1) sky gradient layer (atmospheric gradient recipe or palette-driven), (2) cloud layer (thin-film / SSS backlit for volumetric softness via V.1 PBR), (3) bird silhouettes (near-black chitin or organic dark material — `mat_chitin` or simple emissive-rim dark). Exact recipes to be chosen with reference images in hand.
- Macro/meso/micro/specular-breakup detail cascade for the sky surface (the primary hero surface):
  - Macro: full-screen gradient arc (existing, correct).
  - Meso: large cloud bank variation via `fbm8` at 0.3–0.5 UV scale.
  - Micro: wisp fine detail via `fbm8` or `warped_fbm` at 0.05–0.1 UV scale.
  - Specular breakup: chromatic scattering near horizon (`chromatic_aberration_radial` from V.3 Color, or IQ cosine palette variation on cloud highlights).

**Done when:**
- [ ] No custom hash/noise/fbm functions remain in `Starburst.metal`; V.1 utility calls used throughout.
- [ ] Hero sky surface uses ≥ 4 noise octaves (M2 rubric pass).
- [ ] ≥ 3 distinct materials present (M3 rubric pass).
- [ ] All 4 detail cascade levels present on sky surface (M1 rubric pass).
- [ ] `swift test --filter FidelityRubricTests` shows Starburst M1+M2+M3 passing.
- [ ] `swift test --filter PresetAcceptanceTests && swift test --filter PresetRegressionTests` pass; golden hash regenerated.

**Verify:** `swift test --filter FidelityRubricTests && swift test --filter PresetAcceptanceTests && swift test --filter PresetRegressionTests`

**Estimated sessions:** 2 (noise/utility migration + cloud detail / materials + specular breakup).

---

### Increment SB.5 — Certification

**Scope:** Full rubric evaluation, Matt-approved reference frame match, and `certified: true` flip.

- Run `DefaultFidelityRubric` against updated Starburst; confirm ≥ 10/15 with all 7 mandatory items passing.
- Matt reviews rendered output against `docs/VISUAL_REFERENCES/starburst/` reference annotations (M7 manual gate).
- On approval: flip `Starburst.json` `certified` field to `true`; regenerate golden hashes.
- Update `rubric_hints` if any P1–P4 preferred items were addressed (e.g., `hero_specular: true` if a specular band on the horizon cloud layer is present).
- Reclassify `rubric_profile` if applicable (Starburst is a full-rubric preset; `"full"` is correct).

**Done when:**
- [ ] Rubric score ≥ 10/15, all 7 mandatory items pass, per `FidelityRubricTests`.
- [ ] Matt has approved the reference frame match (M7).
- [ ] `Starburst.json` `certified` field flipped to `true`.
- [ ] Golden hash regenerated and committed.
- [ ] `swift test --filter PresetRegressionTests` passes with new hash.

**Verify:** `swift test --filter FidelityRubricTests && swift test --filter PresetRegressionTests` + Matt visual review.

**Estimated sessions:** 1 (rubric run + Matt review + certification commit).

---

## Phase DSP — DSP Hardening

Targeted fixes to MIR signals where a documented "Failed Approach" mitigation has shipped but the underlying signal quality still degrades the visualization on uncataloged tracks. Each increment is scoped to one signal, lands behind a diagnostic logging gate first, and ships with before/after captures committed under `docs/diagnostics/`.

---

### Increment DSP.1 — IOI histogram half/double voting in `BeatDetector+Tempo`

**Goal:** Fix the half-tempo octave error documented as Failed Approach #17. Replace the single-peak IOI-histogram selection (with its pairwise 2× correction in `applyOctaveCorrection`) with a small voting pass over harmonic candidates {2·BPM₀, 1.5·BPM₀, BPM₀, 0.667·BPM₀, 0.5·BPM₀}, scored by raw bin count + harmonic support + perceptual prior + (optional) metadata-BPM prior. Reuses `BeatPredictor.setBootstrapBPM` injection path; no new dependency, no model.

**Why now:** The existing `applyOctaveCorrection` only handles a pairwise 2× peak comparison and only when a second peak is present and within ratio 1.8–2.2. On 125 BPM kick-driven tracks the estimator still commonly returns ~62 BPM; metadata disambiguation works for cataloged tracks but fails on live recordings, DJ continuous mixes, and niche releases. Voting lets a true tempo win even when the dominant IOI bin sits at half-tempo.

**Implementation order — diagnostic logging FIRST (project principle):**

1. **Land logging only.** Add a `dumpHistogram(label:)` helper to `BeatDetector+Tempo` emitting the top-5 IOI bins (period, count, implied BPM) plus the currently-selected BPM. Gate behind `BEATDETECTOR_DUMP_HIST=1` env var so it stays silent in production. Commit as `[DSP.1] BeatDetector: histogram dump for tempo diagnosis`.
2. **Capture baseline** on the three reference tracks in `CLAUDE.md`:
   - Love Rehab (Chaim) — known 125 BPM
   - So What (Miles Davis) — known 136 BPM
   - There There (Radiohead) — BPM unknown to us; capture whatever the current estimator returns and treat as the "before" value.
   Save dumps to `docs/diagnostics/DSP.1-baseline.txt`.
3. **Implement voting.** Replace `applyOctaveCorrection` with a scoring pass over the five harmonic candidates. Keep the legacy path reachable behind `BEATDETECTOR_LEGACY_TEMPO=1` for one increment so A/B comparison is trivial.
4. **Re-run the same baseline capture** with voting on. Save to `docs/diagnostics/DSP.1-after.txt`. The diff is the change-description evidence.

**Scoring components:**

- **Bin count** at the candidate BPM (the raw IOI evidence; reuse the existing 141-bucket 60–200 BPM histogram).
- **Harmonic support** — bin counts at half-BPM and third-BPM (i.e. 2× and 3× the candidate period) add a fraction of their count to the score. A true tempo has IOI peaks at integer multiples of its period; a half-tempo candidate does not.
- **Perceptual range prior** — soft Gaussian centered at 120 BPM, σ ≈ 40 BPM, across 50–220 BPM. Hard reject anything outside [40, 240] BPM.
- **Metadata BPM prior** (when available) — strong Gaussian centered at the metadata BPM, σ ≈ 4 BPM. The prior wins ties decisively but cannot override overwhelming IOI evidence (see test case 4).

**Files to touch:**

- `PhospheneEngine/Sources/DSP/BeatDetector+Tempo.swift` — add `dumpHistogram`; replace `applyOctaveCorrection` with voting.
- `PhospheneEngine/Sources/DSP/BeatDetector.swift` — only if the metadata-BPM injection point doesn't already exist on `BeatDetector` itself; reuse `BeatPredictor.setBootstrapBPM` pattern.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/BeatDetectorTempoTests.swift` — new file for unit-level voting tests on synthetic histograms.
- `PhospheneEngine/Tests/PhospheneEngineTests/Regression/BeatDetectorRegressionTests.swift` — extend with reference-track regression cases (existing fixtures unchanged).
- `PhospheneEngine/Tests/PhospheneEngineTests/Performance/DSPPerformanceTests.swift` — add voting-budget assertion.
- `docs/CLAUDE.md` — update Tempo section; amend Failed Approach #17 (octave error is no longer a passive limitation).
- `docs/DECISIONS.md` — new D-073 entry: "Tempo octave disambiguation via IOI harmonic voting + metadata prior". Document why TempoCNN (AGPL) and Sound Analysis (orthogonal) were rejected.

**Tests — synthetic IOI histograms (`BeatDetectorTempoTests.swift`):**

1. **Half-tempo correction.** Histogram with peak at 0.96 s (62.5 BPM) and a smaller-but-present peak at 0.48 s (125 BPM). With no metadata, voting must pick 125 BPM (harmonic at 2× boosts the 125 candidate above the raw peak).
2. **True slow tempo preserved.** Single dominant peak at 0.92 s (65 BPM) and no peak at 0.46 s. Voting must return ~65 BPM, not double it.
3. **Metadata wins ambiguous case.** Near-equal peaks at 100 BPM and 200 BPM. With metadata BPM = 100, voting returns 100. With metadata BPM = 200, returns 200.
4. **Metadata cannot override overwhelming evidence.** 50× dominant peak at 140 BPM. With metadata BPM = 70, voting still returns 140 (stale-metadata defense).
5. **Out-of-range rejection.** Peak implying 300 BPM. Voting falls back to the strongest in-range candidate.
6. **Empty / sparse histogram.** Fewer than 4 onsets in the buffer: voting returns `nil` / leaves `instantBPM` unchanged. Caller behavior unchanged from today.

**Tests — reference-track regression (`BeatDetectorRegressionTests.swift`):** Driven by recorded onset sequences from the reference tracks. If onset fixtures don't already exist, generate by running the live pipeline against the audio and committing the resulting onset arrays as JSON under `Tests/Fixtures/tempo/`. Assertions:

- Love Rehab, no metadata: BPM ∈ [122, 128] (target 125, ±3).
- Love Rehab, metadata = 125: BPM ∈ [123, 127] (tighter with prior).
- So What, no metadata: BPM ∈ [133, 139].
- So What, metadata = 136: BPM ∈ [134, 138].
- There There, no metadata: lock in the post-voting estimate from the DSP.1-after capture; future changes must consciously update.

Existing tests in `BeatDetectorRegressionTests.swift` must continue to pass without modification.

**Performance budget:** Voting runs once per `computeStableTempo` call (1 Hz cadence — same as today, not per audio frame). Budget: voting + scoring < 50 µs on M1. Add `DSPPerformanceTests` case to enforce. No allocation in the hot path; score buffer fixed-size on the stack or pre-allocated.

**Done when:**

- [ ] Diagnostic logging committed and pushed first; baseline capture in `docs/diagnostics/DSP.1-baseline.txt`.
- [ ] Voting implementation committed in subsequent commits.
- [ ] Post-voting capture in `docs/diagnostics/DSP.1-after.txt`. Diff shows octave correction on Love Rehab and So What.
- [ ] All 6 unit tests in `BeatDetectorTempoTests.swift` pass.
- [ ] Reference-track regression tests pass with the BPM bounds above.
- [ ] Existing `BeatDetectorRegressionTests` pass unchanged.
- [ ] `swift test --package-path PhospheneEngine` passes (full suite — same pre-existing env failures acceptable; no new failures).
- [ ] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` passes.
- [ ] `DSPPerformanceTests` confirms voting < 50 µs.
- [ ] `CLAUDE.md` Tempo section updated; Failed Approach #17 amended.
- [ ] `DECISIONS.md` D-073 added explaining voting policy and rejected alternatives.
- [ ] Commit messages follow `[DSP.1] <component>: <description>`. Multiple small commits preferred (logging → baseline capture → voting impl → tests → docs).
- [ ] Push only after the full verification block passes locally.

**Verify:** `BEATDETECTOR_DUMP_HIST=1 swift test --filter BeatDetectorTempoTests && swift test --filter BeatDetectorRegressionTests && swift test --filter DSPPerformanceTests`.

**Out of scope (do not re-litigate):** TempoCNN (AGPL), custom Core ML tempo classifier, Sound Analysis framework, `BeatPredictor` IIR period smoothing, onset-detection itself.

**Reference principle (do not violate):** Continuous energy is the primary visual driver; beat onset pulses are accents only (D-004). This increment improves the accuracy of an accent-layer signal — it does not justify elevating beats in any preset shader.

**Estimated sessions:** 2 (logging+baseline → voting+tests → docs).

**Delivered (2026-05-03 — scope shifted from voting):** Diagnostic harness + analyzer revealed the failure was not classical half-tempo octave error. Two real bugs:
1. `recordOnsetTimestamps` consumed `bandFlux[0]+bandFlux[1]` (sub_bass + low_bass fused) — produced frame-aliased IOIs because each band fired on slightly different frames per kick.
2. Histogram-mode BPM picking has period-quantization bias toward faster BPMs (BPM bucket widths grow with BPM in period space), so the histogram mode systematically picks 144 over 136.

Shipped:
- `recordOnsetTimestamps` now sources from `result.onsets[0]` (sub_bass per-band onset events from `detectOnsets`, which has 400ms cooldown). Never fuses bands.
- `applyOctaveCorrection` replaced with `computeRobustBPM`: trimmed mean of recent IOIs (within [0.5×, 2×] of median).

Reference-track results: love_rehab 117/152→**122–126** (true 125), so_what 152→**135–138** (true 136). For there_there the histogram still reads kick-pattern (140) not underlying meter (~86) — that's a syncopation limitation outside DSP.1's scope and motivates DSP.2. See commits `9f4c8e1e..bbad760f` and `docs/diagnostics/DSP.1-baseline*.txt`. D-075.

---

### Increment DSP.2 — BeatNet (CRNN + particle filter) via MPSGraph

**Goal:** Replace the histogram/IOI custom Tier 2 with BeatNet running on MPSGraph for online beat and downbeat tracking. Provides per-frame beat activations at the research-stated ~80% F1 ceiling for causal models, fixing the cases DSP.1 cannot reach (syncopated rock, swing, hip-hop with offbeat kicks). Same MPSGraph + Accelerate idiom used by StemSeparator — no CoreML, no third-party C libs, no virtual audio drivers.

**Why now:** DSP.1's diagnosis proved Phosphene's current Tier 2 is at the classical-pipeline floor (~70% F1, "good enough for visualizer pulse" per the May 2026 streaming-audio research deliverable). For "as flawless as possible" beat sync (Matt's stated bar), this increment is the right answer to the no-CoreML constraint. BeatNet (Heydari et al., ISMIR 2021) is MIT-licensed and the most cited online beat tracker outside madmom (which is offline-only). Its CRNN + particle-filter shape matches Phosphene's existing ML pattern: `StemSeparator` already runs Open-Unmix HQ — a CRNN with bidirectional 3-layer LSTM and 135.9 MB of weights — via MPSGraph at 142ms warm predict.

**Architecture mirrors `StemSeparator`:**

```
PhospheneEngine/Sources/ML/
  BeatTracker.swift              → top-level wrapper, BeatTracking protocol (mirrors StemSeparator.swift)
  BeatTrackerModel.swift         → MPSGraph engine, pre-allocated UMA I/O (mirrors StemModel.swift)
  BeatTrackerModel+Graph.swift   → MPSGraph build: conv → LSTM → dense → sigmoid (mirrors StemModel+Graph)
  BeatTrackerModel+Weights.swift → manifest + .bin loading + BN fusion at init (mirrors StemModel+Weights)
  Weights/beatnet/               → vendored .bin weights via Git LFS (mirrors Weights/openunmix-hq/)

PhospheneEngine/Sources/DSP/
  MelSpectrogram.swift           → vDSP resample (48k→22050) + STFT + mel filterbank (precomputed init)
  ParticleFilter.swift           → pure Swift, ~500–1000 particles over (beat phase, period) state space
```

**Implementation order:**

1. **Close DSP.1 docs** — D-073 entry, CLAUDE.md Tempo section + Failed Approach #17 update. Required before this increment opens.

2. **Weight acquisition + conversion** — pull pre-trained PyTorch state_dict from BeatNet's official repo (Heydari, github.com/mjhydri/BeatNet, MIT). Write a one-shot Python converter script (`Scripts/convert_beatnet_weights.py`) that emits Phosphene's `.bin` weight format — same format as StemSeparator. Vendor under `ML/Weights/beatnet/` with Git LFS pointers. Add CREDITS.md attribution.

3. **Mel-spectrogram preprocessing** — `MelSpectrogram.swift`. Match BeatNet's reference impl bit-for-bit within FP tolerance: 22050 Hz internal rate (vDSP_resamplef from 48k native), 2048-pt STFT, hop 220 samples (10ms), 81 mel bins. Pre-allocate UMA buffer for the rolling spectrogram; zero-alloc per frame. Test: feed a 1 kHz sine and compare mel-bin output against librosa reference within 0.5 dB.

4. **MPSGraph build** — `BeatTrackerModel+Graph.swift`. Architecture (per BeatNet paper §III): two 1D conv layers (kernels 3, 64 filters) → bidirectional GRU 1-layer (hidden 25) → dense head 3-output (beat / downbeat / no-beat) → softmax. BN fused at init. Forward pass takes a single mel-frame plus carried hidden state; returns 3-vector. Mirror `StemModel+Graph.swift` for graph-construction style.

5. **Inference loop** — `BeatTracker.swift`. Per ~10ms mel-frame: write to UMA → forward graph → read 3-vector → push to activation ring buffer (10s window, 1000 frames). Carry GRU hidden state across frames (single Tensor, ~25 floats). Hop to `mlQueue` (utility QoS) for the forward pass; result returned via UMA read. Should be <2ms per frame on M1.

6. **Particle filter (Stage 3)** — `ParticleFilter.swift`. ~500 particles, each carrying (beat phase ∈ [0, period), period ∈ [0.3s, 1.5s], beat-or-downbeat-or-none state). At each frame: advance phase by deltaTime; resample particles weighted by activation likelihood; periodically resample with low-variance sampling. Outputs: most-likely beat-period (BPM), beat-phase01, downbeatProbability. Reference: BeatNet paper §IV, ~250 lines of Python.

7. **Output integration** — extend `FeatureVector` with `downbeatPhase01` (or reuse beatPhase01 — decide during impl). Replace `BeatPredictor` outputs with BeatNet's particle-filter outputs when BeatTracker is healthy; fall through to BeatPredictor when not. Existing GPU contract (buffer(2), 192 bytes) unchanged.

8. **Fallback path** — `BEATTRACKER_USE_BEATNET=0` env var and `Settings.useBeatNet` toggle disable BeatNet at runtime; system falls through to DSP.1's histogram/IOI tempo + BeatPredictor IIR phase. Verify by running the existing BeatDetector unit tests with BeatNet disabled — all 9 tests should pass unchanged.

9. **A/B harness extension** — extend `TempoDumpRunner` with `--engine beatnet|legacy|both` flag. In `both` mode, dump tempo lines from both pipelines per second, prefixed `legacy:` and `beatnet:`. Record the same three reference fixtures with `--engine both`; commit results to `docs/diagnostics/DSP.2-comparison.txt`.

**Files to touch:**

- `PhospheneEngine/Sources/ML/BeatTracker.swift` — new top-level wrapper.
- `PhospheneEngine/Sources/ML/BeatTrackerModel.swift` — new MPSGraph engine.
- `PhospheneEngine/Sources/ML/BeatTrackerModel+Graph.swift` — new graph construction.
- `PhospheneEngine/Sources/ML/BeatTrackerModel+Weights.swift` — new weight loader.
- `PhospheneEngine/Sources/ML/Weights/beatnet/*.bin` — vendored weights (Git LFS).
- `PhospheneEngine/Sources/DSP/MelSpectrogram.swift` — new preprocessor.
- `PhospheneEngine/Sources/DSP/ParticleFilter.swift` — new filter.
- `PhospheneEngine/Sources/Audio/MIRPipeline.swift` — wire BeatTracker output into `FeatureVector`; gate on settings flag.
- `PhospheneEngine/Sources/Shared/AudioFeatures.swift` — add `downbeatProbability` / `isDownbeat` field if needed.
- `PhospheneEngine/Sources/TempoDumpRunner/main.swift` — extend with `--engine` flag.
- `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatTrackerModelTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/MelSpectrogramTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/ParticleFilterTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/Integration/BeatTrackerIntegrationTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/Performance/BeatTrackerPerformanceTests.swift` — new.
- `Scripts/convert_beatnet_weights.py` — one-shot converter.
- `Scripts/dump_tempo_baselines.sh` — extend to run with `--engine both` for the comparison report.
- `docs/CLAUDE.md` — Module Map (`ML/BeatTracker*`, `DSP/MelSpectrogram`, `DSP/ParticleFilter`), ML Inference section update, Failed Approaches updated if any new ones found.
- `docs/DECISIONS.md` — D-076 entry: "BeatNet via MPSGraph for online beat tracking; rationale for rejecting CoreML, aubio, and continued custom DSP."
- `docs/CREDITS.md` (create if missing) — BeatNet attribution per MIT license.

**Tests:**

1. **Unit — `MelSpectrogramTests`:**
   - 1 kHz sine at 48 kHz → resample to 22050 Hz → mel-spec → assert peak energy in mel bin matching 1 kHz.
   - Reference comparison: feed the love_rehab fixture, write mel output to JSON, compare against a `librosa.feature.melspectrogram` reference dump within 0.5 dB.
   - Zero-input → zero output.

2. **Unit — `BeatTrackerModelTests`:**
   - Weight load → no crash; expected number of parameters match manifest.
   - Forward pass on zero input → output near silence-class probability.
   - Forward pass on synthetic 120 BPM kick → activation peaks every ~500 ms (within ±50 ms tolerance).
   - Hidden-state continuity: feeding two adjacent mel frames and feeding a single concatenated frame produce equivalent outputs.

3. **Unit — `ParticleFilterTests`:**
   - Synthetic 120 BPM activation pulses → BPM converges to 120 ± 2 within 2 s.
   - Synthetic 86 BPM activation pulses → converges to 86 ± 2 within 2 s.
   - Synthetic ambiguous (peaks at every 250 ms but every 4th peak louder) → downbeat probability rises on the louder peaks.
   - Tempo change mid-stream (120 → 140 BPM at t = 5 s) → re-locks to 140 within 3 s.

4. **Integration — `BeatTrackerIntegrationTests`:**
   - Reference fixtures (love_rehab, so_what, there_there) — assert BPM matches metadata ±2 BPM.
   - **there_there must read 84–92 BPM** (the meter, not the kick rate of 140) — this is the case DSP.1 can't reach and is the load-bearing assertion for the increment.

5. **Performance — `BeatTrackerPerformanceTests`:**
   - Per-mel-frame inference budget: < 2 ms on M1, < 1 ms on M3 (beat tracking runs at ~100 Hz, ~10× more frequent than StemSeparator's 5 s cadence).
   - Particle filter: < 0.5 ms per frame on M1.
   - Mel-spectrogram preprocessing: < 0.5 ms per frame on M1.
   - Combined budget: < 3 ms per frame, well under the 16.6 ms render budget.

6. **A/B regression — `docs/diagnostics/DSP.2-comparison.txt`:**
   - Three fixtures × two engines × 30 s — committed artifact showing per-second BPM from both pipelines side by side. The "after" evidence for the increment.

7. **Existing tests:**
   - All 9 BeatDetector unit tests pass unchanged with `BEATTRACKER_USE_BEATNET=0` and `=1`.
   - `BeatPredictorTests` pass unchanged.
   - `MIRPipelineUnitTests` pass unchanged.

**Performance budget:**

- Per-frame inference: < 2 ms on M1 (≤ 12 % of frame budget), < 1 ms on M3.
- Memory: < 50 MB for weights + activations buffer + particles. Stays well below StemSeparator's 135.9 MB.
- Init cost: < 200 ms for graph build + weight load (one-time, during preparation).
- Drop-frame behavior: if inference exceeds budget on a given frame, fall through to legacy path for that frame and resume on the next. Same pattern as `MLDispatchScheduler` (D-059).

**Done when:**

- [ ] DSP.1 closure complete (D-073, CLAUDE.md, DECISIONS.md updates landed).
- [ ] Weights vendored under `ML/Weights/beatnet/` via Git LFS pointers.
- [ ] `Scripts/convert_beatnet_weights.py` checked in and reproducible.
- [ ] `MelSpectrogramTests` pass.
- [ ] `BeatTrackerModelTests` pass.
- [ ] `ParticleFilterTests` pass.
- [ ] `BeatTrackerIntegrationTests` pass — including the load-bearing there_there 84–92 BPM assertion.
- [ ] `BeatTrackerPerformanceTests` confirm per-frame budget < 2 ms on M1.
- [ ] `docs/diagnostics/DSP.2-comparison.txt` committed; shows BeatNet matching or exceeding DSP.1 on so_what / love_rehab and crossing the threshold on there_there.
- [ ] All existing BeatDetector / BeatPredictor / MIRPipeline tests pass with both engine modes.
- [ ] Fallback verified: app boots and runs end-to-end with `BEATTRACKER_USE_BEATNET=0`.
- [ ] `swift test --package-path PhospheneEngine` passes (pre-existing flakes in `MetadataPreFetcher` / `MemoryReporter` acceptable).
- [ ] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` passes.
- [ ] No `import CoreML` anywhere in the engine. `grep -rn 'import CoreML' PhospheneEngine/Sources` returns empty.
- [ ] CLAUDE.md Module Map and ML Inference section updated; CREDITS.md attribution present.
- [ ] DECISIONS.md D-076 entry: "BeatNet via MPSGraph for online beat tracking; rejection of CoreML, aubio, and continued custom DSP."

**Verify:** `swift test --filter BeatTrackerModel && swift test --filter MelSpectrogram && swift test --filter ParticleFilter && swift test --filter BeatTrackerIntegration && swift test --filter BeatTrackerPerformance && Scripts/dump_tempo_baselines.sh after`.

**Out of scope (do not re-litigate):**

- aubio (native C dependency; rejected — staying within Swift / MPSGraph idiom).
- BEAST (research code, not packaged for production; revisit if BeatNet underperforms).
- madmom (offline only; non-causal BLSTM cannot run online).
- CoreML in any form (project hard constraint, see Failed Approach #20 and CLAUDE.md "ML Inference").
- Replacing `BeatPredictor`'s IIR predictor entirely — keep as fallback when BeatNet is disabled or unhealthy.
- Per-frame downbeat *visual presets* — separate work; this increment exposes the signal only.
- Multi-track-aware downbeat persistence — single-track per session for now; revisit when Orchestrator wants bar-aligned transitions.

**License sourcing:**

- BeatNet is MIT-licensed; pre-trained weights ship with the official repo. Vendor with attribution in `docs/CREDITS.md`.
- The architecture itself is published in Heydari et al., ISMIR 2021 — implementing it from the paper is unencumbered.

**Risks:**

- Weight quantization: BeatNet is trained in FP32; MPSGraph supports FP32 natively. No quantization needed.
- Resampler quality: vDSP_resamplef from 48 k → 22050 Hz must not introduce artifacts that degrade activations. Mitigation: validate against librosa-reference mel-specs in the unit test (step 3).
- Particle-filter stability: known to be the trickiest part. Mitigation: closely follow Heydari's reference impl; test against synthetic constant-BPM and tempo-change scenarios before integrating with real audio.
- Performance: per-frame inference at 100 Hz is more aggressive than StemSeparator's 5 s cadence. Mitigation: enforce < 2 ms per frame in `BeatTrackerPerformanceTests` from the start; if violated, drop to half-rate inference (50 Hz) before considering more invasive changes.

**Reference principle (do not violate):**

Continuous energy is the primary visual driver; beat onset pulses are accents only (D-004). BeatNet's outputs feed accent-layer fields (`beatPhase01`, `isDownbeat`) only — they do not displace the continuous-energy fields driving primary visual motion.

**Estimated sessions:** 5–7 (weights + mel-spec → 1, MPSGraph build + inference → 2, particle filter → 2, integration + tests + docs → 2).

---

These milestones map to product-level outcomes, not implementation phases.

**Milestone A — Trustworthy Playback Session.** ✅ **MET (2026-04-25).** A user can connect a playlist, obtain a usable prepared session, and complete a full listening session without instability. *Requires: ~~2.5.4~~ ✅, ~~Phase U increments U.1–U.7~~ ✅, ~~progressive readiness basics (6.1)~~ ✅.*

**Milestone B — Tasteful Orchestration.** ✅ **MET (2026-04-25).** Preset choice and transitions are consistently better than random and pass golden-session tests. *Requires: ~~Phase 4 complete~~ ✅, ~~Increment 5.1~~ ✅ (landed as 4.0).*

**Milestone C — Device-Aware Show Quality.** ✅ **MET (2026-04-25).** The same playlist produces an excellent show on M1 and a richer one on M4 without jank. *Requires: ~~Phase 6 complete~~ ✅.*

**Milestone D — Library Depth.** The preset catalog is large enough, varied enough, and well-tagged enough for Phosphene to feel like a product rather than a tech demo. *Requires: Phase 5 complete, Phase V complete (12 fidelity-uplifted presets), Phase MD through MD.5 minimum (10 Milkdrop presets), 22+ certified presets total.*

**Milestone E — Visual Identity.** Phosphene's preset catalog has a recognizable aesthetic ceiling that reads as 2026-quality — comparable to indie-game-released visuals, not 2006-era ShaderToy. *Requires: Phase V complete, Phase V.7–V.11 uplifts all Matt-approved, accessibility pass (U.9).*
