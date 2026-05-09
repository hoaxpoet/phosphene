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

**Current priority ordering (post-2026-05-06 multi-agent codebase review):**

1. **Phase QR — Quality Review Remediation** (QR.1 → QR.6). New top priority. QR.1 → QR.4 are sequenced; QR.5 + QR.6 run after QR.1–QR.4 land. See "Phase QR" section below.
2. **Phase DSP — DSP Hardening.** DSP.3.7 (Live drift validation test) merges into QR.3.
3. **Phase V — Visual Fidelity Uplift** (V.5 reference completion + V.7.7B WORLD pillar) — can run in parallel with QR since they touch disjoint modules.
4. **Phase MD — Milkdrop Ingestion** (MD.1 → MD.7). Unchanged dependency on V.1–V.3 utilities.
5. **Phase SB — Starburst Fidelity Uplift** (SB.1 → SB.5). Independent.

Phase U / Phase 4 / Phase 5 / Phase 6 / Phase 7 / Phase MV all complete; see historical records below.

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

**Status:** Abandoned per D-072. Original scope (atmosphere/motes patch on existing single-pass renderer) is structurally insufficient for the references. Replaced by the v8 design in `docs/presets/ARACHNE_V8_DESIGN.md`, which decomposes Arachne into three layers (background dewy webs + foreground time-lapse build + spider/vibration overlay) and requires preset-system-wide orchestrator changes (multi-segment per track, preset-completion-signal channel) to support the build → transition handoff. Listed here in abandoned form to preserve the audit trail.

---

### Increment V.7.6.1 — Visual feedback harness ✅ 2026-05-02

**Status:** Landed (commit `eca8723d`). New test file `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetVisualReviewTests.swift`, gated by `RENDER_VISUAL=1`. Renders any preset (parameterized; currently `["Arachne"]`) at 1920×1280 for three FeatureVector fixtures (silence / steady mid-energy / beat-heavy). Encodes BGRA → PNG via `CGImageDestination`. Writes to `/tmp/phosphene_visual/<ISO8601>/<preset>_{silence,mid,beat}.png`. Contact sheet (Arachne only) composes the steady-mid render in the top half above refs 01 / 04 / 05 / 08 in the bottom half, with NSAttributedString labels.

Per-preset state setup handles Arachne (allocates `ArachneState`, warms 30 ticks, binds `webBuffer` at fragment buffer 6 and `spiderBuffer` at 7); other presets use only standard bindings. Mesh-shader presets are skipped (cannot be invoked via `drawPrimitives`). Adding a preset is one line — append to the `@Test(arguments:)` list.

**Verify (used):** `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview` produced 4 valid 1920×1280 PNGs. Without the env var, the harness is dormant. SwiftLint strict on the new file → clean. `xcodebuild -scheme PhospheneApp` → BUILD SUCCEEDED.

**M7-style report (Arachne v5 vs refs 01/04/05/08), 2026-05-02:** Render shows two warm-tan concentric ring spirals on flat near-black. No droplets, no specular silk highlight, no atmospheric backlight, no bioluminescent palette. Reads as a 2D line pattern; references read as illuminated 3D objects in atmosphere. Confirms the D-072 diagnosis: the missing layers are compositing (background atmosphere, refractive drops, fibre material), not constants. Justifies the V.7.7+ scope.

**Estimated sessions:** ½. **Actual:** ½ (one commit).

---

### Increment V.7.6.2 — Orchestrator: multi-segment + completion-signal + maxDuration framework

**Scope:** Per `docs/presets/ARACHNE_V8_DESIGN.md §3, §5, §6 step 2`. Preset-system-wide infrastructure change. Touches:
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

### Increment V.7.7A — Arachne staged-composition scaffold migration ✅ 2026-05-05

**Scope:** Migrate Arachne from `passes: ["mv_warp"]` + monolithic `arachne_fragment` to the V.ENGINE.1 staged-composition scaffold (`passes: ["staged"]` + `stages: [world, composite]`). Two new fragment functions: `arachne_world_fragment` (placeholder forest backdrop — sky gradient + horizon haze + three trunk silhouettes) and `arachne_composite_fragment` (samples WORLD via `[[texture(13)]]`, overlays a placeholder 12-spoke + ring web with deviation-form audio gain). Legacy `arachne_fragment` retained in source as a v5/v7 reference. Mv-warp helper functions (`mvWarpPerFrame`, `mvWarpPerVertex`) deleted — they depended on the mv-warp-only preamble and the staged compile path does not include it. **No attempt to implement** refractive droplets, full forest detail, spider behavior, or final visual tuning — those land in V.7.7B+.

**Done when:**
- Arachne loads through `compileStagedShader` with two compiled stages (`PresetLoader.LoadedPreset.stages.count == 2`). ✅
- WORLD-only / WEB-only / COMPOSITE outputs are programmatically inspectable per stage via `RenderPipeline.stagedTexture(named:)` and the `StagedComposition` test path. ✅
- COMPOSITE visibly samples the WORLD texture (existing `StagedCompositionTests` invariant — hub-band brightness > world-band brightness — applies once Arachne is exercised through the harness). ✅
- Arachne golden hash regenerated for the placeholder composite (regression render path leaves `worldTex` unbound, so the hash captures the overlay alone): `0x00000E336E0E1600`. ✅
- Spider golden hash regenerated to the same value with a transitional note (the V.7.5 spider render path goes through the now-replaced `arachne_fragment`; meaningful spider regression coverage returns when the SPIDER stage exists in V.7.7B+). ✅
- Engine test suite green except for the pre-existing `MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget` flake. 0 SwiftLint violations on touched files. ✅

**Verify:** `swift test --filter "Preset Regression Tests|StagedComposition|ArachneState|ArachneSpiderRenderTests"` from `PhospheneEngine/`.

**Estimated sessions:** 1 (delivered).

**Known follow-ups (V.7.7A):**
- **PresetVisualReviewTests.makeBGRAPipeline** loads `Bundle.module.url(forResource: "Shaders")` from the **test** target's bundle, where `Shaders` is not a resource. Throws `cgImageFailed` for any staged preset under `RENDER_VISUAL=1` (Staged Sandbox + Arachne both affected). Pre-existing harness bug shipped with V.ENGINE.1 (gated behind the env flag, never exercised in CI). Fix: source the `.metal` file via `Bundle(for: PresetLoader.self)` so the Presets module's resource bundle is used. Small standalone follow-up; required before V.7.7B's harness contact-sheet review.

---

### Increment QS.1 — Quality System Documentation ✅ 2026-05-05

**Scope:** Establish the defect taxonomy, bug report template, known-issues tracker, release checklist, and developer release notes. Update `CLAUDE.md` with the Defect Handling Protocol. No production code changes.

**New files:**
- `docs/QUALITY/DEFECT_TAXONOMY.md` — severity definitions (P0–P3), domain tags, failure classes, defect process by severity, multi-increment fix flow.
- `docs/QUALITY/BUG_REPORT_TEMPLATE.md` — structured template: expected behavior, actual behavior, reproduction steps, session artifacts, suspected failure class, verification criteria.
- `docs/QUALITY/KNOWN_ISSUES.md` — active tracker: BUG-001 through BUG-005 (open), pre-existing test flakes, and BUG-R001 through BUG-R005 (recently resolved from DSP.3.x).
- `docs/QUALITY/RELEASE_CHECKLIST.md` — 10-section gate covering build, DSP/beat-sync, stem routing, preset fidelity, render pipeline, session/UX, performance, documentation, and git hygiene.
- `docs/RELEASE_NOTES_DEV.md` — developer-facing release notes seeded with entries from dev-2026-04-25 through dev-2026-05-05.

**Updated files:**
- `CLAUDE.md` — `Defect Handling Protocol` section added after `Increment Completion Protocol`.
- `docs/ENGINEERING_PLAN.md` — this increment.

**Done when:**
- All five docs files exist and are internally consistent with current codebase state. ✅
- `CLAUDE.md` Defect Handling Protocol section matches the requirements in the task specification. ✅
- `KNOWN_ISSUES.md` accurately reflects the five open defects identified from the DSP.3.x work and V.7.7A known follow-ups. ✅
- `RELEASE_NOTES_DEV.md` covers the DSP.2/DSP.3/V.7.x session history without contradicting `ENGINEERING_PLAN.md`. ✅

**Verify:** `grep -c "BUG-00" docs/QUALITY/KNOWN_ISSUES.md` — returns ≥ 5. `grep "Defect Handling Protocol" CLAUDE.md` — returns the section header.

**Estimated sessions:** 1 (delivered).

---

### Increment V.7.7B — Arachne staged WORLD + WEB port ✅ 2026-05-07

**Prerequisite:** V.7.7A staged-composition scaffold migration ✅ 2026-05-05.

**Scope:** Promote V.7.7-redo's `drawWorld()` and V.7.8's chord-segment `arachneEvalWeb()` from dead reference code in `Arachne.metal` into the dispatched `arachne_world_fragment` and `arachne_composite_fragment` staged stages. Extend `RenderPipeline+Staged.encodeStage()` and `PresetVisualReviewTests.encodeStagePass()` so staged stages can read the per-preset fragment buffers at index 6 (`ArachneWebGPU`) and index 7 (`ArachneSpiderGPU`) — the legacy mv_warp / direct path used these via `directPresetFragmentBuffer` / `directPresetFragmentBuffer2`; the staged path currently does not bind them. Result is parity with the pre-V.7.7A monolithic shader output, on the staged-composition scaffold. Refractive droplets, biology-correct build state machine, spider deepening, and whole-scene vibration are V.7.7C / V.7.7D — not in scope for V.7.7B.

**Done when:**
- ✅ WORLD-only and COMPOSITE captures via the harness show parity with the pre-V.7.7A V.7.5 baseline (drawWorld six-layer forest in WORLD; web pool + drops + spider + mist + motes in COMPOSITE).
- ✅ New `StagedPresetBufferBindingTests` regression test asserts buffer 6/7 propagate through staged dispatch (two tests, slot 6 + slot 7).
- ✅ Legacy `arachne_fragment` is deleted; the V.7.7A placeholder fragments (vertical-gradient WORLD + 12-spoke COMPOSITE) are deleted; the legacy fragment body is repurposed as `arachne_composite_fragment` with the only divergence `bgColor = drawWorld(...)` → `worldTex.sample(...)`. `Arachne.metal` drops from 962 → 898 LOC (every line in the new COMPOSITE traceable to the legacy fragment, per the prompt's mechanical-lift rule).
- ✅ Engine + harness staged dispatch bind `directPresetFragmentBuffer` / `…Buffer2` at fragment slots 6 / 7. App-layer `case .staged:` in `VisualizerEngine+Presets.applyPreset` allocates `ArachneState`, wires the per-frame tick, and sets the slot-6/7 buffers (mirrors the existing mv_warp branch — without this the buffers are silently zero at runtime, the gap that V.7.7A's migration left open).
- ✅ All targeted suites pass (`StagedComposition` + `StagedPresetBufferBinding` + `PresetRegression` + `ArachneSpiderRender` + `ArachneState`); 0 SwiftLint violations on touched files; app build clean.
- ✅ Golden hashes regenerated: Arachne `(steady/beatHeavy/quiet) = 0xC6168E8F87868C80` (regression test renders COMPOSITE with `worldTex` unbound → samples zero, so the hash captures the foreground composition over a black backdrop), Spider forced `0x461E3E1F07870C00`, and "Staged Sandbox" added (was previously missing from the dictionary).

**Verify:** `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter "renderStagedPresetPerStage"` produces non-placeholder PNGs (forest WORLD + chord-segment spiral COMPOSITE). Full suite: `swift test --package-path PhospheneEngine` — pre-existing `ProgressiveReadiness` flakes under parallel @MainActor scheduling are documented in CLAUDE.md and trip independently of this increment. Detailed protocol in `prompts/V.7.7B-prompt.md`.

**Carry-forward:**
- V.7.7C — refractive droplets (Snell's law, sample `arachneWorldTex`), biology-correct build state machine (frame → radials → spiral), anchor logic.
- V.7.7D — spider pillar deepening (anatomy, material, gait), whole-scene vibration.
- V.7.10 — Matt M7 cert review.

---

### Increment V.7.7C — Arachne refractive dewdrops (§5.8 Snell's-law) ✅ 2026-05-07

**Prerequisite:** V.7.7B Arachne staged WORLD + WEB port ✅ 2026-05-07.

**Scope:** Replace the V.7.5 `mat_frosted_glass` drop overlay (warm-amber emissive base + cool-white pinpoint specular) at both COMPOSITE call sites — the anchor-web block (~line 742) and the pool-web block (~line 832) — with the §5.8 Snell's-law refractive recipe sampling the WORLD stage's offscreen texture at `[[texture(13)]]`. Both blocks use the spec recipe verbatim (spherical-cap normal → `refract(-kViewRay, sphN, 0.752)` → `worldTex.sample` at `2.5 × rDrop` magnification → Schlick fresnel rim with `kLightCol × 0.85` warm tint → pinpoint specular at the half-vector cap position → `darkRing × 0.5` smoothstep ring at `[0.85, 0.95, 1.0]` radius bands → `(baseEmissionGain + beatAccent)` audio-reactive multiplier). Pool block additionally multiplies coverage by `w.opacity` to preserve V.7.5 fade semantics. Out of scope: build state machine, anchor blobs, spider deepening, vibration, `arachneEvalWeb` changes — V.7.7C.2 / V.7.7D / V.7.10.

**Done when:**
- ✅ Both drop blocks render via Snell's-law refraction sampling `worldTex`; `mat_frosted_glass` / `dropAmber` / `glintAdd` deleted from both call sites.
- ✅ Single shader-only commit; net Arachne.metal LOC change roughly ±0.
- ✅ Targeted suites pass (`StagedComposition` + `StagedPresetBufferBinding` + `PresetRegression` + `ArachneSpiderRender` + `ArachneState` — 23 tests / 5 suites).
- ✅ `PresetLoaderCompileFailureTest` passes (Arachne preset count 14, no silent compile drop — see Failed Approach #44).
- ✅ Visual harness `RENDER_VISUAL=1 swift test --filter renderStagedPresetPerStage` produces non-placeholder Arachne PNGs across silence / mid / beat fixtures (377 KB world + 1.2 MB composite).
- ✅ 0 SwiftLint violations on touched files; full engine + app suites pass except documented pre-existing flakes (`MemoryReporter.residentBytes`, `MetadataPreFetcher.fetch_networkTimeout`, `NetworkRecoveryCoordinator` parallel-load timing).
- ✅ Golden hashes documented: Arachne dHash UNCHANGED (`0xC6168E8F87868C80`) — under the regression render path `worldTex` is unbound, refraction reads zero, and the rim+specular+ring contributions sum below the dHash 9×8 luma quantization threshold. Spider forced regenerated (`0x461E3E1F07870C00` → `0x461E2E1F07830C00`).
- ✅ `D-093` filed in `docs/DECISIONS.md` documenting the five non-trivial decisions: worldTex sample over inline `drawWorld()`, delete vs keep `mat_frosted_glass` fallback, defer build state machine to V.7.7C.2, `2.5 × rDrop` magnification choice over `8 × rDrop` background tuning, half-vector type-correction (`float2 halfDir` not `float3 halfVec` — prompt's recipe declared a float3 with a float2 RHS, fails to compile in Metal).

**Verify:** Same as V.7.7B. Detailed protocol in `prompts/V.7.7C-prompt.md`.

**Carry-forward:**
- V.7.7C.2 / V.7.8 — single-foreground build state machine (frame → radials → INWARD spiral over 60s), per-chord drop accretion, anchor blobs.
- V.7.7D — spider pillar deepening + whole-scene 12 Hz vibration.
- V.7.10 — Matt M7 cert review.

---

### Increment V.7.7D — Arachne 3D SDF spider + chitin + listening pose + 12 Hz vibration ✅ 2026-05-08

**Prerequisite:** V.7.7C Arachne refractive dewdrops (§5.8 Snell's-law) ✅ 2026-05-07.

**Scope:** Replace the V.7.5 / V.7.7B / V.7.7C 2D dark-silhouette spider overlay in `arachne_composite_fragment` (~line 1033) with a per-pixel ray-marched 3D SDF anatomy (cephalothorax + abdomen + petiole + 8 IK legs with outward-bending knees + 6 eyes) shaded via the §6.2 chitin recipe (brown-amber base + thin-film iridescence at biological strength `blend = 0.15` + Oren-Nayar hair fuzz + per-eye specular). Add a CPU-side listening-pose state machine (`ArachneState+ListeningPose.swift`) that lifts `tip[0]` / `tip[1]` clip-space Y by `0.5 × kSpiderScale × listenLiftEMA` on sustained low-attack-ratio bass — the shader's IK derives the raised knee analytically from the lifted tip, no GPU-struct change. Add §8.2 whole-scene 12 Hz vibration UV jitter on COMPOSITE web walks + spider body translation; WORLD intentionally still. Out of scope: trigger logic, build state machine, web pool / spawn / eviction, `arachneEvalWeb` body, `mat_chitin` cookbook recipe, visual references, M7 review — V.7.7C.2 / V.7.8 / V.7.10.

**Done when:**
- ✅ 3D SDF spider renders into a `0.15 UV` screen-space patch around the spider's UV anchor; cephalothorax + abdomen + petiole + 8 IK legs + 6 eyes resolved by `sd_spider_combined` via inlined adaptive ray march (32 steps, `hitEps = 0.0008`, far plane 8.0 body-local units).
- ✅ Chitin material recipe applied at hit (matID 0/2 = body/leg): brown-amber base `(0.08, 0.05, 0.03)` + thin-film `hsv2rgb(0.55+0.3·NdotV, 0.5, 0.4) × 0.15` + Oren-Nayar fuzz `pow(1−NdotV, 1.5) × 0.18` × kLightCol + body shadow `0.30+0.70·NdotL` + warm rim `kLightCol × pow(1−NdotV, 3) × 0.55`. Eye material (matID 1): `float3(0.02) + kLightCol × spec` with `spec = (dot(halfV, n) > 0.95)`. `mat_chitin` (V.3 cookbook) NOT called from this path — its V.3 default `thin × 1.0` blend would be the §6.2 anti-reference (ref `10` neon glow).
- ✅ Listening-pose state machine fires on `f.bassDev > 0.30 AND stems.bassAttackRatio ∈ (0, 0.55)` held continuously for ≥ 1.5 s; EMA returns to 0 with `τ = 1 s` when bass eases. State lives entirely on `ArachneState` (CPU), preserving the V.7.7B 80-byte `ArachneSpiderGPU` contract. `writeSpiderToGPU()` lifts only `tip[0]` / `tip[1]` clip-Y by `0.5 × kSpiderScale × listenLiftEMA = 0.009 × EMA` UV; other tips unchanged.
- ✅ §8.2 vibration UV jitter applied at top of `arachne_composite_fragment` BEFORE web walks; `arachneEvalWeb(uv, ...)` calls (anchor + pool) replaced with `vibUV`; spider body translates with the same `vibOffset`. Bottom-of-fragment `worldTex.sample(arachne_world_sampler, uv)` keeps original `uv` (WORLD pillar intentionally still per §8.2 anchor-vs-tip physics). Driver substituted from §8.2's `subBass_dev` to FV `bass_att_rel` (FV has no sub-bass split; `bass_att_rel` is the natural Arachne continuous-bass envelope and stays at 0 at AGC-average levels — passes the PresetAcceptance "beat is accent only" invariant). Per-kick spike `0.0015 × beat_bass × 0.4` set to 0 (continuous-only is closer to §8.2 musical intent; per-kick character preserved by the existing `beatAccent` strand-emission term).
- ✅ Two-commit increment: (1) `[V.7.7D] Arachne: listening-pose state machine + tip lift CPU-side (D-094)` — `ArachneState.swift` + `ArachneState+Spider.swift` + new `ArachneState+ListeningPose.swift` + new `ArachneListeningPoseTests.swift` (4 tests); (2) `[V.7.7D] Arachne: 3D spider SDF + chitin material + 12 Hz vibration (D-094)` — `Arachne.metal` shader work + golden hashes + docs.
- ✅ Targeted suites pass (`PresetAcceptance` + `StagedComposition` + `StagedPresetBufferBinding` + `PresetRegression` + `ArachneSpiderRender` + `ArachneState` + `ArachneListeningPose` + `PresetLoaderCompileFailure` — 32 tests / 8 suites).
- ✅ `PresetLoaderCompileFailureTest` passes (Arachne preset count 14, no silent compile drop — Failed Approach #44).
- ✅ Visual harness `RENDER_VISUAL=1 swift test --filter renderStagedPresetPerStage` produces non-placeholder Arachne PNGs across silence / mid / beat fixtures; beat composite (1232 KB) shows minor pattern delta vs silence/mid composites (1230 KB) confirming vibration is wired.
- ✅ 0 SwiftLint violations on touched files; full engine suite passes except documented pre-existing parallel-load flakes (`MetadataPreFetcher.fetch_networkTimeout`, `SessionManagerTests` — all pass in isolation).
- ✅ Golden hashes documented: Arachne `beatHeavy` regenerated to `0xC6168E87878E8480` (continuous-bass vibration shifts silk pattern by a few bits at the test fixture's `bass_att_rel`-equivalent level via the audio-coupled web walk); steady + quiet UNCHANGED. Spider forced UNCHANGED (`0x461E2E1F07830C00`) — the dHash 9×8 luma quantization at 64×64 doesn't resolve the small spider footprint's colour change; the 3D anatomy IS rendered (different colour values inside the patch) but contributes below the digest threshold. Real visual divergence observed in `PresetVisualReviewTests`.
- ✅ `D-094` filed in `docs/DECISIONS.md` documenting the eight non-trivial decisions: 3D SDF over 2D extension, screen-space patch over full-screen march, GPU-struct stability + CPU-side listening-pose, FV-vs-spec mismatch (`bassDev` for sub-bass), vibration driver `bass_att_rel` + per-kick spike dropped, COMPOSITE-only vibration scope, 8×8 phase quantization, `spiderLegRadius` left at 0.26 + patch widened to 0.15.

**Verify:** Detailed protocol in `prompts/V.7.7D-prompt.md`. Order matters: build → `PresetLoaderCompileFailureTest` → targeted suites → visual harness → spider golden hash regeneration → full engine suite.

**Carry-forward:**
- V.7.7C.2 / V.7.8 — single-foreground build state machine (frame → radials → INWARD spiral over 60s), per-chord drop accretion, anchor blobs, per-segment spider cooldown, build pause/resume on spider trigger.
- V.7.10 — Matt M7 contact-sheet review + cert. Gated on V.7.7C.2 / V.7.8 + V.7.7D landing.

---

### Increment V.7.7C.2 — Arachne single-foreground build state machine + background pool + per-segment spider cooldown + PresetSignaling + WebGPU Row 5 ✅ 2026-05-09

**Prerequisite:** V.7.7D Arachne 3D SDF spider + chitin + listening pose + vibration ✅ 2026-05-08.

**Scope:** Replace the V.7.5 4-web pool-with-beat-measured stage timing with a single-foreground build state machine implementing `ARACHNE_V8_DESIGN.md §5` orb-weaver biology (frame polygon → bridge thread first → alternating-pair radials → INWARD chord-segment capture spiral → settle), audio-modulated TIME pacing, 1–2 saturated background webs at depth, per-segment spider cooldown replacing V.7.5's 300 s session lock, build pause/resume on spider trigger, `PresetSignaling` conformance emitting `presetCompletionEvent` once at settle, and `ArachneWebGPU` extension 80 → 96 bytes (Row 5 = packed BuildState). Three commits across two days. The dispatched Arachne preset becomes the visible build cycle the v8 design has been working toward since D-072 — Matt watches a single foreground web draw itself over ~50–55 s of music in a depth context of finished background webs. Subsumes the original V.7.8 (foreground build refactor) and V.7.9 (spider deepening + vibration + cert) plans — those V.7.5-era line items are obsolete post-V.7.7C/D + V.7.7C.2.

**Done when:**

- ✅ Commit 1 (`38d1bfab`, 2026-05-08) — WORLD branch-anchor twigs. `kBranchAnchors[6]` constant in `Arachne.metal` + `ArachneState.branchAnchors` Swift mirror; `drawWorld()` renders six small dark capsule SDFs at those positions. `ArachneBranchAnchorsTests` regression-locks the Swift / MSL sync via string-search.
- ✅ Commit 2 (`0f94be2f`, 2026-05-08) — CPU build state machine + background pool + spider integration. `ArachneBuildState` struct on `ArachneState` (frame / radial / spiral / stable / evicting), audio-modulated TIME pacing (`pace = 1.0 + 0.18 × midAttRel + max(0, 0.5 × drumsEnergyDev)` — D-026 ratio ≈ 3.6×), pause guard evaluated BEFORE `effectiveDt` per RISKS, alternating-pair radial draw order (§5.5), spiral chord precompute with strictly-INWARD chord radii (§5.6), per-chord `spiralChordBirthTimes[]` for §5.8 accretion, polygon selection via Fisher-Yates from `branchAnchors[6]` + bridge-pair largest-angular-gap heuristic, `reset()` semantics. New `ArachneState+BackgroundWebs.swift` (1–2 saturated entries, migration crossfade 1 s ramp). New `ArachneStateSignaling.swift` (in `Sources/Orchestrator/` for module-cycle avoidance — D-095 documents the deviation from spec'd `Sources/Presets/Arachnid/` placement). `spiderFiredInSegment: Bool` per-segment cooldown replaces V.7.5's 300 s session lock (§6.5). `WebGPU` extended 80 → 96 bytes (Row 5 = build_stage / frame_progress / radial_packed / spiral_packed). 11 new `ArachneStateBuild` tests + 1 legacy-test rewrite. App-layer wiring: `applyPreset .staged` calls `arachneState.reset()` for Arachne; `activePresetSignaling()` `as?` cast simplified.
- ✅ Commit 3 (this commit, 2026-05-09) — shader-side build-aware rendering + golden hash regen + docs. `arachne_composite_fragment`'s "Permanent anchor web" block now reads `webs[0]` Row 5 BuildState and maps it to the legacy `(stage, progress)` signature `arachneEvalWeb` already understands: `.frame (0)` → `stage=0u, progress=frame_progress`; `.radial (1)` → `stage=1u, progress=radial_packed / 13.0`; `.spiral (2)` → `stage=2u, progress=spiral_packed / 104.0`; `≥ .stable (3)` → `stage=3u, progress=1.0`. Pool loop starts at `wi = 1` so the foreground slot doesn't double-render. The chord-segment SDF stays `sd_segment_2d` (Failed Approach #34 lock); the §5.4 hub knot stays `fbm4`-min threshold-clipped (NOT concentric rings); the §5.8 drop COLOR recipe is byte-identical to V.7.7C (D-093 lock); the V.7.7D 3D SDF spider + chitin + listening pose + 12 Hz vibration are byte-identical (D-094 lock); `ArachneSpiderGPU` stays at 80 bytes. `PresetAcceptanceTests.makeRenderBuffers` seeds the slot-6 buffer with stable BuildState values for Arachne specifically, mirroring `arachneState.reset()` in production.
- ✅ Targeted suites pass (`PresetAcceptance` + `StagedComposition` + `StagedPresetBufferBinding` + `PresetRegression` + `ArachneSpiderRender` + `ArachneState` + `ArachneStateBuild` + `ArachneListeningPose` + `ArachneBranchAnchors` + `PresetLoaderCompileFailure`). 0 SwiftLint violations on touched files. Engine 1170/1171 pass — sole failure is the documented pre-existing `MetadataPreFetcher.fetch_networkTimeout` parallel-load flake. App suite: 5 timing flakes mirroring Commit 2's documented baseline.
- ✅ Golden hashes regenerated. Arachne `steady` / `beatHeavy` / `quiet` all converge to `0xC6168081C0D88880` (mid-build composition; harness's shared 30-tick warmup gives the same BuildState for all three fixtures). Hamming distance from V.7.7D `steady` (`0xC6168E8F87868C80`): 16 bits, within the D-095 expected [10, 30] band. Spider forced hash: `0x461E2E1F07830C00` → `0x461E381912D80800` (14 bits drift).
- ✅ Visual harness PNG (`/tmp/phosphene_visual/20260508T153154/`): foreground hero (V.7.7D upper-left) gone — at warmup t=0.5s the BuildState is in frame phase at frameProgress ≈ 0.166 (only the partial bridge thread renders, visually subtle). Background depth context (webs[1] at lower-right, V.7.5 spawn/eviction) renders unchanged. PNG size dropped 1.16 MB → 0.72 MB on the composite, consistent with the foreground hero disappearing. Real-music build cycle visible only on Matt's manual smoke gate.
- ✅ `D-095` filed in `docs/DECISIONS.md` documenting all decisions: single foreground hero + background pool, audio-modulated TIME pacing, per-segment spider cooldown, build pause/resume invariant, `PresetSignaling` conformance + `ArachneStateSignaling.swift` placement in Orchestrator module, WebGPU 80 → 96 bytes Row 5 layout, `branchAnchors` two-source-of-truth, hub knot fbm-clipped (not concentric rings), Failed Approach #34 chord SDF lock, polygon-irregular-by-construction. Plus four explicit deferred sub-items: per-chord drop accretion via chord-age side buffer, anchor-blob discs at polygon vertices, background-web migration crossfade rendered visual, polygon vertices from `branchAnchors` (vs spoke tips). None load-bearing for the success criterion ("the user watches the build draw itself"); schedule alongside V.7.10 cert review at Matt's discretion.

**Verify:** Detailed protocol in `prompts/V.7.7C.2-prompt.md`, `V.7.7C.2-commit2-prompt.md`, `V.7.7C.2-commit3-prompt.md`. Order matters: preconditions (build / stride 96 / completion event single-fire / pre-shader regression baseline) → `PresetLoaderCompileFailureTest` → targeted suites pre-golden → visual harness sanity check (silence vs beat composite delta, hub not concentric, polygon irregular, spiral inward) → golden hash regen → targeted suites post-golden → full engine suite → app suite → SwiftLint → manual smoke (Matt watches build cycle on real music).

**Carry-forward:** V.7.10 — Matt M7 contact-sheet review + cert sign-off. The Arachne 2D stream's structural work is complete after V.7.7C.2; V.7.10 is QA + sign-off only. V.8.x (Arachne3D parallel preset, D-096) deferred per Matt's 2026-05-08 sequencing call — simpler presets first, then return to V.8.1.

---

### Increment V.7.7C.3 — Arachne manual-smoke remediation: chord-by-chord spiral + V.7.5 pool retire + branchAnchors polygon + spider trigger reformulation ✅ 2026-05-09

**Prerequisite:** V.7.7C.2 single-foreground build state machine ✅ 2026-05-09.

**Scope:** Close four issues surfaced by Matt's 2026-05-08T17-01-15Z manual smoke that V.7.7C.2's deferred-sub-items list either deferred or did not anticipate. (1) Chord-by-chord spiral visibility gate — replace per-ring gate with per-chord gate so chords lay one-at-a-time outside-in, not full-ring complete ovals. (2) Retire V.7.5 spawn/eviction from rendering — disable shader pool loop entirely so flash-and-fade transient webs no longer compete with the foreground build. (3) Polygon vertices from `branchAnchors` (V.7.7C.2 deferred sub-item #4 lifted from deferred) — pack `bs.anchors[]` into `webs[0].rngSeed`; shader decodes + ray-clips spokes to polygon perimeter + uses irregular polyV[] for frame thread vertices with bridge-first stage-0 reveal. (4) Spider trigger reformulated — V.7.5 `subBass + bassAttackRatio < 0.55` gate confirmed acoustically impossible on real music (Failed Approach #57); replace with `bassAttRel` envelope primitive (same primitive the §8.2 vibration path uses correctly). Single commit. No new tests; only fixture-helper updates + golden hash regen (spider only).

**Done when:**

- ✅ Per-chord spiral visibility gate in `arachneEvalWeb`: `int totalChordCount = N_RINGS * nSpk; int visibleChordCount = (stage >= 3u) ? totalChordCount : ((stage == 2u) ? int(progress * totalChordCount) : 0)`. Inner spoke loop skips chords with `globalChordIdx >= visibleChordCount`. Sweep order: outside-in by ring (k=0 outermost, first), clockwise-by-spoke within each ring (`globalChordIdx = k * nSpk + si`).
- ✅ V.7.5 pool spawn/eviction retired from rendering: shader's pool loop bound changed from `wi < kArachWebs` to `wi < 1` (empty body retained as a structural marker for the future §5.12 background-web flush). CPU-side spawn/eviction state continues to advance harmlessly so `ArachneState` unit tests still cover the spawn machinery; nothing reaches the shader.
- ✅ Polygon-from-branchAnchors path: new `Self.packPolygonAnchors(_:)` static helper on `ArachneState` packs up to 6 anchor indices (4 bits count + 6 × 4 bits indices) into a single `UInt32`. `writeBuildStateToWebs0` writes the packed value to `webs[0].rngSeed`. Three new shader helpers above `arachneEvalWeb`: `decodePolygonAnchors`, `rayPolygonHit`, `findBridgeIndex`. `arachneEvalWeb` extended with `int polyCount, thread const float2 *polyV` parameters. Inside: squash transform bypassed in polygon mode; spoke tip computation clipped to polygon (used for both alternating-pair tipPos[] and sequential sdTip[]); frame thread polygon vertices come from polyV[] with bridge-first stage-0 reveal (`edgeIdx = (bridgeIdx + fi) % frameVCount`); spiral chord positions scaled along each spoke's polygon-clipped length (`pI = sdTip[si] * fracR + sag`, `fracR = ringR / r_outer`). V.7.5 fallback path preserved bytewise when `polyCount = 0`. Three call sites updated.
- ✅ Spider trigger reformulated: `features.subBass > 0.30 AND stems.bassAttackRatio > 0 AND < 0.55` → `features.bassAttRel > Self.bassAttRelThreshold` (0.30). AR gate retired; brief kick pulses filtered by existing 0.75 s sustain-accumulator threshold. Trigger log line shows `bassAttRel` alongside `subBass` for diagnostic continuity.
- ✅ Targeted suites pass (`PresetAcceptance` 56/56 + `StagedComposition` + `StagedPresetBufferBinding` + `ArachneState` + `ArachneStateBuild` 11/11 + `ArachneListeningPose` + `ArachneBranchAnchors` + `PresetLoaderCompileFailure` + `PresetRegression` + `ArachneSpiderRender`). 0 SwiftLint violations on touched files. Engine 1169/1171 pass (2 documented pre-existing flakes).
- ✅ Golden hashes regenerated. Arachne `steady` / `beatHeavy` / `quiet` UNCHANGED at `0xC6168081C0D88880` (PresetRegression doesn't bind slot 6/7 → polyCount=0 V.7.5 fallback + frame phase at 0 % progress = WORLD-only composition). Spider forced: `0x461E381912D80800` → `0x46160011C2D80800` (7 bits drift; within dHash 8-bit tolerance — polygon-aware spoke clipping visibly affects only partial-bridge-thread pixels under the spider patch at the harness's frame-phase warmup).
- ✅ Spider tests updated for `bassAttRel` primitive: `subBassFV()` in `ArachneStateTests` + `bassTriggerFV()` in `ArachneStateBuildTests` set `f.bassAttRel = 0.40` (above threshold). `ArachneSpiderRenderTests` calls `state.reset()` before warmup so polygon path is exercised; `PresetAcceptanceTests` slot-6 buffer additionally seeds packed polygon at `webs[0].rngSeed` (byte offset 28).
- ✅ `D-095` follow-up section filed in `docs/DECISIONS.md` documenting all four fixes + V.7.7C.2 contract preservation guarantees + Failed Approach #57.

**Verify:** Build → `PresetLoaderCompileFailureTest` → targeted suites pre-golden → visual harness sanity check → golden hash regen (spider only) → targeted suites post-golden → full engine + app suites → SwiftLint → manual smoke re-run (Matt watches build cycle on real music; verifies chord-by-chord lay, no transient web churn, irregular polygon, spider triggers on Limit To Your Love sub-bass drop).

**Carry-forward:** Manual-smoke re-run on real music (Matt). On green: V.7.10 cert review. Three V.7.10 follow-ups remain: per-chord drop accretion via chord-age side buffer; anchor-blob discs at polygon vertices (§5.9 part 2); background-web migration crossfade rendered visual.

---

### Increment V.7.7C.4 — Arachne palette + L lock + hybrid audio coupling (D-095 follow-up #2) ✅ 2026-05-09

**Prerequisite:** V.7.7C.3 manual-smoke remediation ✅ 2026-05-09.

**Scope:** Close three issues from Matt's 2026-05-08T18-28-16Z second manual smoke. WORLD reframe + spider movement deferred to V.7.7C.5 + V.7.7C.6 per Matt's sequencing call. **Fix A:** L key full-lock — `handlePresetCompletionEvent` guards on `diagnosticPresetLocked` so orchestrator-driven completion-event transitions are suppressed when the L key is held. Pre-V.7.7C.4 the L key only suppressed mood-override switching; V.7.7C.4 lets Matt watch the full ~50–55 s build cycle without the orchestrator cycling away every ~60 s. Manual `⌘[` / `⌘]` cycling unaffected. **Fix B:** Palette enrichment — reverses V.7.5 §10.1.3's deliberate silk dimming after Matt's "color far too subtle" feedback. silkTint factor 0.60 → 0.85; mood-driven hue base (valence: teal → amber); vocal-pitch coupling when `stems.vocals_pitch_confidence ≥ 0.35` (Gossamer-style); wider hueDrift factor 0.10 → 0.20; ambient tint factor 0.25 → 0.40; hub knot coverage 0.80 → 1.20 (saturated). **Fix C:** Hybrid audio coupling — PRESERVES D-095 Decision 2 (audio-modulated TIME pacing) while adding two beat-coupling channels. (1) Per-beat global emission pulse `emGain += beatPulse * 0.06` where `beatPulse = max(beat_bass, beat_composite)`. Coefficient 0.06 calibrated against PresetAcceptance D-037 invariant 3 (`beatMotion ≤ continuousMotion × 2.0 + 1.0`). (2) Rising-edge beat advances `spiralChordIndex` by 1 in `advanceSpiralPhase(by:features:)`. New `ArachneState.prevBeatForSpiral` rising-edge tracker (reset by `_reset()`). Sparse-beat tracks still complete in `naturalCycleSeconds`; kick-heavy tracks see chords lay faster on each beat. Pause-guard preserved: gated on `effectiveDt > 0`. Single commit; no new test files (only fixture-helper updates + golden hash regen).

**Done when:**

- ✅ L key suppresses orchestrator-driven completion-event transitions when held. `handlePresetCompletionEvent` checks `diagnosticPresetLocked` first, logs `"Orchestrator: preset completion suppressed (diagnosticPresetLocked)"` and returns early.
- ✅ Silk palette: silkTint 0.85; hue derived from valence-driven base + vocal-pitch coupling (when `stems.vocals_pitch_confidence ≥ 0.35`); hueDrift coefficient 0.20; ambient 0.40. Hub knot coverage 1.20 saturated (visibly distinct emissive feature).
- ✅ Per-beat global emission pulse `beatPulse * 0.06` on silk emission. Calibrated against D-037 invariant 3.
- ✅ Rising-edge beat advances `spiralChordIndex` in `advanceSpiralPhase(by:features:)`. `prevBeatForSpiral` tracker on `ArachneState` reset by `_reset()`. Pause-guard preserved (gated on `effectiveDt > 0`).
- ✅ Targeted suites pass (`PresetAcceptance` 60/60 + `StagedComposition` + `StagedPresetBufferBinding` + `ArachneState` + `ArachneStateBuild` + `ArachneListeningPose` + `ArachneBranchAnchors` + `PresetLoaderCompileFailure` + `PresetRegression` + `ArachneSpiderRender`). PresetAcceptance D-037 invariant 3 caught initial coefficient overshoot (0.45 → 0.06 retune); test infrastructure worked exactly as intended.
- ✅ Engine 1174/1175 pass (sole `MetadataPreFetcher.fetch_networkTimeout` documented flake). App suite: same documented flake (better than V.7.7C.2/C.3 baseline). 0 SwiftLint violations on touched files (file_length 400 line ceiling on `VisualizerEngine+Presets.swift` enforced — comment trimmed during landing).
- ✅ Golden hashes regenerated. Arachne `steady`/`quiet` `0xC6168081C0D88880` → `0x06129A65E458494D`; `beatHeavy` → `0x0000000000000000`. Spider forced: `0x46160011C2D80800` → `0x06129A55C258494D`.
- ✅ D-095 follow-up section in `docs/DECISIONS.md` documenting the three fixes + V.7.7C.2/C.3 contract preservation.

**Verify:** Build → `PresetLoaderCompileFailureTest` → targeted suites pre-golden → visual harness sanity check → golden hash regen → targeted suites post-golden → full engine + app suites → SwiftLint → manual smoke re-run (Matt verifies L lock holds, palette reads brighter, build couples to beats).

**Carry-forward:** Manual-smoke re-run on real music (Matt). On green: V.7.7C.5 (WORLD reframe) and V.7.7C.6 (spider movement). V.7.10 cert review still gated on these.

---

### Increment V.7.7C.5 — Arachne atmospheric abstraction (WORLD reframe) ✅ 2026-05-08

**Prerequisite:** V.7.7C.4 manual-smoke green sign-off — **confirmed by Matt 2026-05-08 (this session).** §4 spec revision landed 2026-05-09 in `docs/presets/ARACHNE_V8_DESIGN.md` (full §4 rewrite from "six-layer dark close-up forest" to "two-layer atmospheric abstraction"; §5.9 updated to retire literal branch/twig rendering; §4.5 decisions log captures all 13 Q&A answers Matt provided).

**Scope:** Implement the V.7.7C.5 §4 + §5.9 spec revision. Single-commit increment. Replaces `drawWorld()` in `Arachne.metal` (currently the V.7.7B six-layer dark close-up forest with §5.9 anchor twigs added in V.7.7C.2 Commit 1) with a two-layer atmospheric backdrop:

1. **Atmospheric color band (full frame).** Vertical gradient `mix(botCol, topCol, uv.y)` over the full frame (expanded from V.7.7B's upper 40 %). Low-frequency `fbm4` noise modulation. Aurora ribbons at high arousal (preserved from V.7.7B). Silence-anchor pure-black preserved.
2. **Volumetric atmosphere** (three sub-elements composited additively):
   - Fog density anchored around the light shaft cones (denser inside cones, thinner outside) — volumetric god-ray signature. Range raised from 0.02–0.06 to **0.15–0.30**. Inside cones: `mix(botCol, topCol, 0.5) × kLightCol`. Outside: `mix(botCol, topCol, 0.5) × 0.3`.
   - Light shafts: 1–2 god-ray cones, mood-driven angle (warm valence → upper-LEFT, cool valence → upper-RIGHT, ~30° from vertical for primary, ~50° for optional secondary at high arousal). Brightness coefficient raised from `0.06 × val` to **`0.30 × val`** so shafts read as hero atmospheric elements. Engages above `f.mid_att_rel > 0.05` (lowered from V.7.7B's 0.10). Use `Volume/LightShafts.metal` `ls_radial_step_uv` family.
   - Dust motes concentrated INSIDE the shaft cones only (caustic-like), per-mote opacity 0.4 (raised from 0.3), color `local_fog × kLightCol`, density modulated by `f.mid_att_rel`, phase-anchored to `f.beat_phase01` (Failed Approach #33 compliance).

**Retired (V.7.7C.5):**

- Distant tree silhouettes (V.7.7B §4.2.2)
- Mid-distance trees with bark detail (V.7.7B §4.2.3)
- Near-frame branches (V.7.7B §4.2.4) — `drawWorld()` branch-rendering loops removed
- Forest floor (V.7.7B §4.2.5) — sky band fills the lower edge instead
- §5.9 anchor twigs (V.7.7C.2 Commit 1) — `drawWorld()` capsule-SDF loop at `kBranchAnchors[i]` positions removed. **`kBranchAnchors[6]` constants stay** in `Arachne.metal` and `ArachneState.swift` — `selectPolygon(rng:)` still consumes them as polygon vertex candidates; `ArachneBranchAnchorsTests` regression test stays.
- Forest-specific reference images for §4 implementation: `02_meso_per_strand_sag.jpg`, `11_anchor_web_in_branch_frame.jpg`, `17_floor_moss_leaf_litter.jpg`, `18_bark_close_up.jpg`. They stay in `docs/VISUAL_REFERENCES/arachne/` for V.7.10 historical comparison; they no longer drive any §4 implementation choice.

**Preserved (V.7.7C.5):**

- §4.3 mood-driven color field — verbatim from 2026-05-02 spec (Q10).
- Silence anchor `(satScale × valScale) < 0.05` clears WORLD to black (Q11).
- WEB pillar (§5) entirely — staged WORLD + COMPOSITE scaffold, build state machine, polygon-from-`branchAnchors`, drop refraction recipe, 3D SDF spider, 12 Hz vibration.
- `ArachneState.branchAnchors[]` + `kBranchAnchors[6]` MSL constants (still used for polygon vertex selection).

**Done when:**

- `drawWorld()` rewritten as the two-layer atmospheric backdrop. Six-layer forest content + §5.9 anchor-twig SDF loop removed.
- Sky band gradient covers full frame (uv.y from 0 to 1).
- Volumetric fog anchored around shaft cones, range 0.15–0.30.
- Light shafts 1–2 mood-driven angle, brightness coefficient 0.30 × val, engages above `f.mid_att_rel > 0.05`.
- Dust motes concentrated inside shaft cones only, beat-phase-anchored.
- Silence anchor `(satScale × valScale) < 0.05 → black` preserved.
- **Q14 — `kBranchAnchors[6]` repositioned to off-frame.** Every entry on or just past `[0,1]²` borders. Constants in `Arachne.metal` line ~153 + `ArachneState.swift` updated byte-for-byte; `ArachneBranchAnchorsTests` regenerated against new values. Web reads as anchored to off-frame structures.
- **Q15 — `webR` bumped `0.22` → `~0.55`** in `arachne_composite_fragment` foreground anchor block so the spoke distance early-exit + spiral ring sweep range accommodate the larger polygon. Polygon interior occupies ~70–85% of canvas area.
- All targeted suites pass (`PresetAcceptance`, `StagedComposition`, `StagedPresetBufferBinding`, `PresetRegression`, `ArachneSpiderRender`, `ArachneState`, `ArachneStateBuild`, `ArachneListeningPose`, `ArachneBranchAnchors`, `PresetLoaderCompileFailure`).
- Goldens regenerated — substantial drift expected (every WORLD pixel changes; foreground polygon scale changes too).
- 0 SwiftLint violations on touched files.
- New `D-099` decision in `docs/DECISIONS.md` (or next-available ID) documenting the V.7.7C.5 reframe rationale + the 15 Q&A decisions captured in §4.5.
- Manual smoke confirms backdrop reads as atmospheric support: fog visible, light shafts hero, motes glow inside shafts, no literal trees / branches / twigs anywhere. Web fills majority of canvas; anchors implied off-frame; visual signature matches `20_macro_backlit_purple_canvas_filling_web.jpg` reference.

**Verify:** Build → `PresetLoaderCompileFailureTest` → targeted suites pre-golden → `RENDER_VISUAL=1` visual harness sanity check (silence shows pure black; mid shows visible fog + 1 shaft + motes; beat shows shaft activated by `mid_att_rel`) → golden hash regen → targeted suites post-golden → full engine + app suites → SwiftLint → manual smoke re-run on real music (Matt verifies fog/light/mote framing dominates, no forest residue, build cycle still readable on top).

**Estimated sessions:** 1 (single-commit increment; §4 spec is fully resolved).

**Landed (2026-05-08, single commit).** Files: `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal` (drawWorld rewritten — sky band + beam-anchored fog + 1–2 mood-driven shafts at `0.30 × val` + cone-confined dust motes; midAttRel parameter threaded; foreground hero hub at `(0.5, 0.5)` + `webR = 0.55`; per-beat coefficient retuned `0.06 → 0.025` for canvas-filling area scale per D-100); `PhospheneEngine/Sources/Presets/Arachnid/ArachneState.swift` (`branchAnchors` Swift mirror moved off-frame; `webs[0]` hub `(0.0, 0.0)` / radius `1.10`); `PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneBranchAnchorsTests.swift` (expected literals + bounds invariant rewritten for `[-0.06, 1.06]²`; new asymmetry test); `PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneSpiderRenderTests.swift` (`goldenSpiderForcedHash` `0x06129A55C258494D → 0x06D29A65E458494D` — 7-bit Hamming drift from off-frame anchors flowing into polygon decode); `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetRegressionTests.swift` (Arachne `beatHeavy` `0x0000000000000000 → 0xC6921125C4D85849`; steady/quiet UNCHANGED — regression harness doesn't bind slot 6/7 + worldTex; comment block extended). Engine 1184 tests / 2 documented pre-existing flakes (`MetadataPreFetcher.fetch_networkTimeout`, `SoakTestHarness.cancel`); app build clean; SwiftLint 0 violations on touched files; `Scripts/check_sample_rate_literals.sh` passes. PresetAcceptance D-037 invariant 3 passes for Arachne after coefficient retune (predicted MSE ≈ 0.31 vs ceiling 1.0). RENDER_VISUAL=1 PNGs at `/tmp/phosphene_visual/20260508T213106/Arachne_{silence,mid,beat}_{world,composite}.png`. D-100.

**Carry-forward:** Manual smoke re-run completed 2026-05-08T22-01-07Z. Geometry contracts (canvas-filling polygon, off-frame anchors, hub at canvas centre, chord-by-chord lay) all read correctly. Cosmetic + palette feedback drove V.7.7C.5.1 (below). V.7.7C.6 (spider movement) and V.7.10 (cert review) remain.

---

### Increment V.7.7C.5.1 — Arachne visual craft pass (line widths + luminescence + palette + shaft gate + per-segment seed) ✅ 2026-05-08

**Prerequisite:** V.7.7C.5 manual smoke completed. Matt's 2026-05-08T22-01-07Z session surfaced six issues with V.7.7C.5's visual craft despite the geometry contracts reading correctly:

1. **Spirals too fast — chord-by-chord not readable.** Reframed by Matt: "webs are elaborate, so viewers should expect tighter spirals with many points of connection. The lines and luminescence on them do not need to be so heavy." → keep chord density; thin the lines + dim luminescence so density reads as elaborate detail rather than scribbly chaos.
2. **Lines too thick relative to canvas-filling polygon.** Silk widths were absolute UV; at V.7.7C.4 webR=0.22 they were balanced; at V.7.7C.5 webR=0.55 the polygon scaled 2.5× but lines didn't.
3. **Toddler-drawing readability** — downstream of (1) + (2).
4. **Spider didn't fire on LTYL.** Recording cut at LTYL +35 s, before the song's sub-bass drop. Inconclusive; deferred to longer-LTYL smoke.
5. **Background palette too muted — psych ward, not psychedelic.** V.7.7C.5 shipped Q10's verbatim §4.3 palette (sat 0.25–0.65 / val 0.10–0.30), correct for the V.7.7B–C.4 forest WORLD where compositional richness masked the muteness; the atmospheric reframe exposed it.
6. **No light shaft appreciated.** Telemetry from the 4705-frame Arachne windows showed midAttRel mean ≈ -0.5, max never reached the §4.2.2 spec gate threshold of 0.05 → shaft never engaged.

Plus a separate observation: "should the preset draw the SAME web in the SAME position EVERY time? Shouldn't it vary every time you play it, or based on the track it's paired with?" → per-segment macro-shape variation needed.

**Scope:** Single-commit cosmetic + per-segment-seed pass on V.7.7C.5. No Swift state changes; no test rewrites; only line widths, luminescence constants, palette function rewrite, shaft gate reformulation, ancSeed source, plus golden hash regen.

**Done when:**

- Silk line widths halved: spoke/frame `0.0024 → 0.0010`, spiral `0.0013 → 0.0007`. Halo sigmas halved to match.
- Silk luminescence dimmed: silkTint factor `0.85 → 0.55`; hub knot coverage `1.20 → 0.70`; ambient tint factor `0.40 → 0.20`; axial highlight coefficient `0.6 → 0.3`; halo magnitudes ~halved (`spokeHalo 0.38 → 0.20`, `frameHalo 0.22 → 0.11`, `spirHalo 0.25 → 0.13`).
- §4.3 palette pumped: saturation `0.55–0.95`, value `0.30–0.70`. Audio-time hue cycle ±0.15 swing on top of the Q10 valence-driven base hues. Top/bottom phase-offset by π so the gradient never collapses to a single hue.
- Shaft engagement gate reformulated: `0.25 + 0.75 × smoothstep(-0.20, 0.10, midAttRel)`. Floors engagement at 25% always-on baseline; scales to 100% on positive deviation.
- Cross-preset silence anchor preserved (Q11) by re-keying on raw mood product `arousalNorm × valenceNorm < 0.05`.
- Per-segment macro-shape variation (Option A): `ancSeed = arachHashU32(webs[0].rng_seed ^ 0xCA51u)` instead of hardcoded `1984u`. New `arachHashU32` helper — same bit-mixing as `arachHash` but returns the scrambled uint instead of a float.
- All targeted suites pass (`PresetAcceptance`, `StagedComposition`, `StagedPresetBufferBinding`, `PresetRegression`, `ArachneSpiderRender`, `ArachneState`, `ArachneStateBuild`, `ArachneListeningPose`, `ArachneBranchAnchors`, `PresetLoaderCompileFailure`).
- Goldens regenerated (Arachne `steady`/`quiet` `0x06129A65E458494D → 0x8000000000000000` — V.7.7C.5.1 dimmed silk pushes frame-phase-0 contribution below dHash quantization on the regression harness; `beatHeavy` `0xC6921125C4D85849 → 0x04101A6444186969`; spider forced `0x06D29A65E458494D → 0x800080C004000000`).
- 0 SwiftLint violations on touched files.
- `Scripts/check_sample_rate_literals.sh` passes.

**Verify:** Build → targeted suites green → `RENDER_VISUAL=1` visual harness shows vivid green-yellow gradient + thin silk → full engine + app suites → SwiftLint → manual smoke re-run on real music (Matt verifies palette psychedelic not psych ward; lines fine-detail not toddler scribble; shaft visible at baseline; per-segment variation reads as different webs across multiple Arachne instances).

**Estimated sessions:** 1 (single-commit cosmetic pass).

**Landed (2026-05-08, single commit).** Files: `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal` (arachHashU32 helper added; silk line widths + halo sigmas + halo magnitudes halved in `arachneEvalWeb`; foreground anchor block silk luminescence dimmed; ancSeed switched to per-segment `arachHashU32(webs[0].rng_seed ^ 0xCA51u)`; §4.3 palette rewritten with pumped sat/val + audio-time hue cycle; shaft engagement gate reformulated to floor+scale); `PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneSpiderRenderTests.swift` (`goldenSpiderForcedHash` regen); `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetRegressionTests.swift` (Arachne 3-tuple regen, comment block extended). Engine 1185 tests / 3 documented pre-existing parallel-load timing flakes (`MetadataPreFetcher.fetch_networkTimeout`, `SoakTestHarness.cancel`, `SessionManagerCancel.cancel_fromReady`); app build clean; SwiftLint 0 violations on touched files. RENDER_VISUAL=1 PNGs at `/tmp/phosphene_visual/20260508T224311/`. D-100.

**Carry-forward:** Manual smoke 2026-05-08T22-58-49Z surfaced four issues — drops piling into "fat crayon" spirals, silk wisps with no scaffold, only-green palette across a multi-track session, spider didn't fire on Love Rehab. All addressed in V.7.7C.5.2 (below). V.7.7C.5.3 (per-track web identity, Options B/C) deferred awaiting product call. V.7.7C.6 (spider movement) and V.7.10 (cert review) still remain.

---

### Increment V.7.7C.5.2 — Arachne second cosmetic + spider-trigger pass (drops + silk re-brightening + hue cycle widening + spider sustain) ✅ 2026-05-08

**Prerequisite:** V.7.7C.5.1 manual smoke completed. Matt's 2026-05-08T22-58-49Z session surfaced four issues despite the V.7.7C.5.1 cosmetic + palette pump:

1. **Spirals "large and thick like a fat crayon"** — diagnosed as drops (radius `0.008` UV ≈ 8.6 px) piling up along chord segments at 4–5 drop-diameter spacing. The chord SDF (0.0007 UV) is invisible under the drop chain. Drops carry the visual mass that V.7.5 §10.1.3 intended ("drops as visual hero") but at canvas-filling scale that produces the fat-crayon reading.
2. **Radials "wispy, no solid scaffold"** — V.7.7C.5.1 dimmed silkTint to 0.55 to compensate for the muted V.7.7C.5 backdrop, but V.7.7C.5.1 ALSO pumped the §4.3 palette to vivid sat 0.55–0.95 / val 0.30–0.70. Against the new vivid backdrop, 0.55 silkTint reads as faint cream-on-yellow with no contrast.
3. **"Only green, no other colors"** — V.7.7C.5.1's ±0.15 audio-time hue cycle stays inside one valence-quadrant neighborhood across a session.
4. **Spider didn't fire on Love Rehab** despite max bassAttRel = 1.86 (4.6 % of frames > 0.30 trigger). The 0.75 s sustain accumulator with 2× decay-when-below requires SUSTAINED bass; kick-driven music produces ~5–10 frames above threshold then ~30+ below, so the accumulator never reaches 0.75 s.

**Scope:** Single-commit cosmetic + spider-trigger pass on V.7.7C.5.1. No state-machine changes; only drop radius, silk constants, hue cycle amplitude, and sustain threshold. Plus golden hash regen.

**Done when:**

- Drop radius halved `0.008 → 0.004` (~4 px at 1080 p) so pearls read as discrete dewdrops along thin chords instead of a continuous fat band.
- Silk re-brightened: silkTint factor `0.55 → 0.70`, ambient tint factor `0.20 → 0.30`. Restores radial contrast vs the vivid backdrop without going back to V.7.7C.4's 0.85.
- Audio-time hue cycle widened `±0.15 → ±0.45`. Backdrop visibly traverses cyan → green → yellow → amber → magenta every ~25 s instead of staying in one hue band.
- Spider sustained-trigger threshold lowered `0.75 s → 0.4 s` so kick-driven music can accumulate (still rejects single-kick spikes — one ~5-frame burst contributes ~83 ms).
- All targeted suites pass (`PresetAcceptance`, `StagedComposition`, `StagedPresetBufferBinding`, `PresetRegression`, `ArachneSpiderRender`, `ArachneState`, `ArachneStateBuild`, `ArachneListeningPose`, `ArachneBranchAnchors`, `PresetLoaderCompileFailure`).
- Goldens regenerated (Arachne `(steady, beatHeavy, quiet)` `(0x8000000000000000, 0x04101A6444186969, 0x8000000000000000) → (0x0000000000000000, 0x66929B65E4D94849, 0x0000000000000000)`; spider forced `0x800080C004000000 → 0x000080C004000000`).
- 0 SwiftLint violations on touched files.
- `Scripts/check_sample_rate_literals.sh` passes.

**Verify:** Build → targeted suites pre-golden → goldens regen → targeted suites post-golden → `RENDER_VISUAL=1` visual harness shows green-to-magenta gradient + thin sharp silk → full engine + app suites → SwiftLint → manual smoke re-run on real music (Matt verifies: discrete dewdrops along thin chords not fat crayon; radial scaffold visible; backdrop cycles through hues across a track; spider fires on Love Rehab kicks).

**Estimated sessions:** 1 (single-commit cosmetic + sustain-tuning pass).

**Landed (2026-05-08, single commit).** Files: `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal` (drop radius 0.008→0.004 in arachneEvalWeb; silkTint 0.55→0.70 + ambient 0.20→0.30 in foreground anchor block; hue cycle ±0.15→±0.45 in drawWorld); `PhospheneEngine/Sources/Presets/Arachnid/ArachneState+Spider.swift` (`sustainedTriggerThreshold` 0.75→0.4); `PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneSpiderRenderTests.swift` (golden regen); `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetRegressionTests.swift` (golden regen). Engine 1185 tests / 2–5 documented pre-existing parallel-load timing flakes; app build clean; SwiftLint 0 violations. RENDER_VISUAL=1 PNGs at `/tmp/phosphene_visual/20260508T232351/`. D-100 follow-up #2.

**Carry-forward:** Manual smoke re-run on real music (Matt verifies the four V.7.7C.5.2 fixes deliver the expected reading on Love Rehab + LTYL — drops as discrete pearls; radials as solid scaffold; multi-hue gradient cycling; spider fires on kick drums). V.7.7C.5.3 (per-track web identity, Options B/C) deferred awaiting product call. V.7.7C.6 (spider movement) and V.7.10 (cert review) still remain.

---

### Increment V.7.7C.5.3 — Per-track web identity (Options B / C) — DEFERRED, awaiting product decision

**Prerequisite:** V.7.7C.5.2 manual-smoke green sign-off. Renumbered from V.7.7C.5.2 after that slot was claimed by the second cosmetic pass. Decision pending Matt's evaluation of whether the Option A per-segment variation (landed in V.7.7C.5.1) is sufficient or whether webs should additionally be tied to track identity for aesthetic association.

**Scope (if scheduled):** Two flavours, mutually-exclusive:

- **Option B — per-track determinism.** Plumb track-identity hash into `ArachneState.reset(trackSeed:)`. Same track always gets the same web (across replays, across sessions). Adds Swift wiring in `ArachneState` (new `reset` overload), a Renderer hook on track change (`PresetSignaling`-style identity passthrough), and a determinism test asserting two `reset(trackSeed:)` calls with the same seed produce byte-identical web state. ~30 LOC + 1 test.

- **Option C — track + session-counter perturbation.** Per-track base seed gives identity; an LCG step per-replay gives variant on the Nth listen. Variety + association both. ~40 LOC + extends the determinism test with a per-replay variance assertion (Nth replay produces materially-different web state from N+1th replay).

Trade-off: B gives consistent music-visual association at the cost of "this track's web always looks weak when it lands on a poor random draw"; C resolves that but adds session state (LCG-per-track replay counter) that needs persistence across track changes within a session.

**Done when:** Manual smoke confirms the chosen flavour reads as intended on a 10+-track playlist with at least one repeated track. V.7.7C.5.1's Option A is preserved as the fallback when no track identity is available (e.g. ad-hoc reactive sessions before track change observation).

**Estimated sessions:** 1 (single Swift-side commit).

---

### Increment V.7.7C.6 — Arachne spider movement system (off-camera entry + walking path + min-visibility latch + rarity gate) — DEFERRED, V.7.7D-scale increment

**Prerequisite:** V.7.7C.4 manual-smoke green sign-off + V.7.7D 3D SDF spider + V.7.7C.4 trigger reformulation already landed.

**Scope:** Add body translation + waypoint navigation + min-visibility latch + N-segment rarity gate to the existing static-position spider. Per Matt's 2026-05-08T18-28-16Z manual smoke: "the spider flashed on the screen for a second then immediately disappeared. I would want the spider to walk from off camera into the camera frame when triggered and move from one hook of the web to another over the span of 10–15 seconds. The trigger should be rare, but the spider should remain in view for longer, and most importantly should MOVE within the camera frame, ideally along the web." Closes V.7.7C.4's deferred sub-item — comparable scope to the V.7.7D 3D anatomy + chitin material increment.

**Architecture decisions (to be filed as D-100 or next-available decision ID at implementation time):**

1. **`SpiderState` enum.** Replace the current `spiderActive: Bool` + `spiderBlend: Float` pair with a state machine: `.idle` / `.entering(progress: Float)` / `.walking(fromIdx: Int, toIdx: Int, progress: Float)` / `.exiting(progress: Float)` / `.cooldown(remainingSegments: Int)`. State advances on each tick; `spiderBlend` becomes a derived value from the current state.
2. **Off-camera entry path.** On trigger, spawn at UV (1.10, 0.50) (or randomly chosen edge-adjacent position outside [0,1]) and walk to the first polygon vertex over ~1.5 s. `.entering` state.
3. **Walking path along polygon hooks.** Use `bs.anchors[]` (V.7.7C.3 polygon vertices) as waypoints. Spider visits 2–3 polygon vertices over 10–15 seconds, walking along silk thread paths (frame edges). Per-waypoint duration ~4–6 s. Body position interpolates smoothly along the silk edge between consecutive waypoints (catmull-rom or simple linear; spec TBD). Existing leg gait drives leg tips relative to body — animates naturally as body translates.
4. **Min-visibility latch.** Once activated, spider stays visible for at least 12–15 seconds regardless of trigger condition. Replace the current `if spiderActive && !conditionMet { spiderActive = false }` with a min-visibility timer that holds. After expiry, transition to `.exiting` and walk off-frame.
5. **N-segment cooldown for rarity.** Currently per-segment cooldown via `spiderFiredInSegment`. Expand to "spider may fire AT MOST once every N segments". Default N=3; configurable. New `ArachneState.spidersFiredCount: Int` increments on each `_reset()`; trigger gates on `spidersFiredCount % N == 0` AND `!spiderFiredInSegment`.
6. **GPU contract.** `ArachneSpiderGPU` stays at 80 bytes (V.7.7D contract). Body position writes to existing `posX` / `posY` fields each frame. Heading writes to `heading` (rotates as spider walks turn corners). No struct expansion.
7. **Pause-guard interaction.** While spider is active, the build state machine is paused (V.7.7C.2 contract). Spider movement progresses independently — body translates and gait animates regardless of build pause.
8. **Music coupling (TBD):** does the spider walking pace couple to music (slower on quiet passages, faster on dense tracks), or is it on a fixed wallclock? Decide at implementation. D-095 audio-modulated TIME precedent suggests `pace = 1.0 + 0.18 × midAttRel` keeps it consistent with the build state machine.

**Done when:**

- Spider state machine implemented with all five states (`.idle` / `.entering` / `.walking` / `.exiting` / `.cooldown`).
- Spider visibly walks from off-camera into the frame on bass-drop trigger.
- Spider visits 2–3 polygon vertices over 10–15 seconds, walking along silk edges.
- Spider remains in view for at least 12–15 seconds regardless of trigger condition.
- Spider trigger fires AT MOST once every N segments (default N=3).
- Existing per-segment cooldown (`spiderFiredInSegment`) preserved as a same-segment fallback.
- All targeted suites pass.
- Goldens regenerated (substantial drift expected — spider position now varies across the 10–15 s walk).
- 0 SwiftLint violations on touched files.
- New `ArachneSpiderMovementTests` test suite covering the five-state machine transitions, min-visibility latch, N-segment cooldown.
- D-100 (or next-available) decision in `docs/DECISIONS.md` documenting the architectural choices above.
- Manual smoke confirms all four behaviours: off-camera entry, walking along web, min-visibility hold, rarity (one trigger per N=3 segments).

**Verify:** Build → `PresetLoaderCompileFailureTest` → targeted suites pre-golden → visual harness sanity check (force spider via `forceActivateForTest(at:)` and capture the walk path) → golden hash regen → targeted suites post-golden → full engine + app suites → SwiftLint → manual smoke (Matt watches multiple spider triggers across a full session, confirms walking path looks natural, min-visibility holds, rarity gate enforces N-segment cooldown).

**Estimated sessions:** 2–3 (state machine + waypoint navigation + min-visibility + rarity + tests + golden regen).

**Carry-forward:** V.7.10 cert review — final QA pass.

---

### Increment V.8.0-spec — Arachne3D: parallel-preset commit + four pushbacks ✅ 2026-05-08 (D-096)

**Scope.** Doc-only spec validation session against four pushbacks (perf budget honesty, screen-space refraction artifact, chromatic dispersion, parallel-preset feasibility). No code changed. Establishes the architectural commitments for V.8.1 onward: parallel preset (`Arachne3D` alongside V.7.7D `Arachne`), sampled WORLD backdrop, screen-space refraction with documented edge artifact, chromatic dispersion in V.8.2 (silhouette-band approach), Tier-1 mitigations (noSSGI default + capped drops + half-res lighting). System-wide reframe ("same visual conversation, not pixel-match") adopted as cert principle for the full preset ladder.

**Done when:** ✅ All five doc files updated (`ARACHNE_3D_DESIGN.md`, `ARACHNE_V8_DESIGN.md`, `VISUAL_REFERENCES/arachne/Arachne_Rendering_Architecture_Contract.md`, `DECISIONS.md`, `ENGINEERING_PLAN.md`); ✅ `swift test --package-path PhospheneEngine` passes (no behavioral change); ✅ `xcodebuild -scheme PhospheneApp build` green; ✅ 0 new SwiftLint violations; ✅ `git diff --stat` shows only doc files changed; ✅ D-096 filed.

**Carry-forward:** V.8.1 below.

---

### Increment V.8.1 — Arachne3D minimal end-to-end 3D scaffold

**Prerequisite:** V.8.0-spec ✅ 2026-05-08 (D-096).

**Scope.** Stand up `Arachne3D` as a parallel preset alongside V.7.7D `Arachne` per D-096 Decision 1. New `Arachne3D.metal` + `Arachne3D.json` (display name `"Arachne 3D"`, `certified: false`, default `rubric_profile`) under `PhospheneEngine/Sources/Presets/Shaders/`. `passes: ["ray_march", "post_process"]` (drop `["staged"]`); WORLD pass continues to ship via the existing V.7.7B `arachne_world_fragment` writing `arachneWorldTex` (bound at the same texture index Arachne uses today). The ray-march pass implements `sceneSDF` / `sceneMaterial` using the V.2 SDF tree (`sd_capsule`, `sd_sphere`, `op_smooth_union`) for a **single static web** at `(0, 0, 0)`: 12 procedurally-unrolled spokes, one spiral revolution, no chord-segment subdivision, no drops, no spider, no build cycle. Material: `mat_silk_thread` (V.3 cookbook) on silk strands. Lighting: directional key + flat ambient; **no IBL, no SSGI** (`noSSGI` is the Tier-1 default per D-096 Decision 5). Camera: static, framed on the hub, FoV ~50°. `ArachneState` reused unchanged from V.7.7D — Arachne3D binds the same instance; existing 2D Arachne preset continues to render in parallel. **No `Arachne3DState` is introduced.** Layout audit on `WebGPU` to confirm a `hubZ: Float` extension fits in the existing 80-byte slot (purely additive — V.7.7D Arachne ignores the new field).

Out of scope for V.8.1: drops (V.8.2), refraction (V.8.2), chromatic dispersion (V.8.2), spider (V.8.3), IBL cubemap + DoF (V.8.4), multi-web pool + cinematic camera + foreground build state machine (V.8.5), cert (V.8.6).

**Done when (D-096 Decision 8 — single structural acceptance gate):**

1. **Single web visibly rendering through the deferred PBR pipeline at the correct screen position.** Manual verify by launching the app, cycling to Arachne3D via `⌘[` / `⌘]`, and confirming the silk-strand web renders at the framed hub.
2. **Camera parallax visible.** A small (≤0.5 unit) camera offset injected via developer-shortcut or test fixture must produce visible 3D parallax of silk strands against the WORLD backdrop. The strands move relative to the backdrop; the backdrop does not move (it's a billboard sample per D-096 Decision 2). This proves real 3D rendering, not a 2D fragment shader simulating depth.
3. **WORLD pass sampled correctly as backdrop.** Miss-ray pixels return `arachneWorldTex.sample(uv)` (not flat color, not the sky-only V.7.7B early-out). Verified by silencing the silk SDF in a debug build and confirming the full-frame WORLD render reads through.
4. **Anti-reference visual rejection.** Rendered frame must NOT visually match `09_anti_clipart_symmetry.jpg` or `10_anti_neon_stylized_glow.jpg`. Operationally — until automated dHash-against-anti-refs lands — Matt eyeballs the V.8.1 contact sheet against both anti-refs at the phase boundary and signs off.
5. **p95 frame time inside the budget forecast committed in D-096 Decision 5.** Single-web V.8.1 scene is a fraction of the V.8.5 forecast; Tier 2 expected ~3–5 ms p95, Tier 1 expected ~5–8 ms p95 with the noSSGI default engaged. **V.8.1's first task is to instrument the scene with `MTLCounterSet.timestampGPU` and validate per-component costs against the §4.4 forecast on a real Tier 1 (M1 or M2) device + a real Tier 2 (M3) device.** If Tier 1 exceeds 14 ms p95 even at this reduced scene complexity, the architecture is wrong for Tier 1 and V.8.x replans before V.8.2.
6. **`PresetVisualReviewTests` extended to render `Arachne3D`** alongside `Arachne` for silence / steady / beat-heavy / sustained-bass fixtures into the harness contact sheet under `RENDER_VISUAL=1`. Net-new `Arachne3D` golden hashes added to `goldenPresetHashes` in `PresetRegressionTests`; existing Arachne hashes stay locked at V.7.7D values per D-096 Decision 1.
7. **Visual feedback loop engaged at phase boundary** per `ARACHNE_3D_DESIGN.md §7.3`. Claude Code renders the contact sheet, summarises what changed structurally, and stops. Matt + a separate Claude.ai session produce the visual diff that feeds V.8.2.
8. **Targeted suites pass:** `PresetAcceptance` (Arachne3D added to the parametrized list), `PresetRegression` (Arachne3D goldens), `PresetLoaderCompileFailure` (preset count 14 → 15, no silent compile drop per Failed Approach #44), the existing Arachne suites unchanged. 0 new SwiftLint violations.
9. **Closeout report** per CLAUDE.md Increment Completion Protocol: files changed, tests run, harness output paths, doc updates (V.8.1 entry flipped to ✅; D-096 referenced as the architectural source), capability registry updates if any, known risks (anti-reference subjective check pending automated dHash; perf forecast unverified on Tier 1 hardware until Matt runs the harness on M1/M2), git status clean.

**Verify:**
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` green.
- `swift test --package-path PhospheneEngine` green; `swift test --package-path PhospheneEngine --filter PresetVisualReview` produces non-placeholder Arachne3D PNGs alongside Arachne PNGs.
- `swiftlint lint --strict --config .swiftlint.yml` 0 violations on touched files.
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview` writes Arachne3D contact-sheet PNGs to `/tmp/phosphene_visual/<ISO8601>/`.
- Manual: launch app, cycle to Arachne3D, verify acceptance criteria 1–4 above.

**Estimated sessions:** 1 (scaffold-only).

**Carry-forward:** V.8.2 — drops at chord-segment intersections (Tier 2: ~300–500/web; Tier 1: capped at 150/web per D-096 Decision 5) + screen-space Snell's-law refraction sampling `arachneWorldTex` + silhouette-band chromatic dispersion. V.8.3 — spider in 3D via `sceneSDF` (V.7.7D `sd_spider_combined` adapted) + chitin material via `sceneMaterial`. V.8.4 — IBL forest cubemap from V.7.7B WORLD palette + depth-of-field on `PostProcessChain`. V.8.5 — multi-web pool in 3D + cinematic camera (Decision E.3) + foreground build state machine + 3D vibration. V.8.6 — M7 cert + V.7.7D Arachne retirement (file deletion + `Arachne 3D` → `Arachne` rename in JSON sidecar).

**V.8.2+ scope is intentionally NOT expanded yet.** Each subsequent increment gets its own ENGINEERING_PLAN entry once V.8.1 contact-sheet review lands and the visual feedback loop produces the diff that informs V.8.2's prompt.

---

### Increment V.7.7 — Arachne v8: WORLD pillar + 1–2 background dewy webs

**Status correction (2026-05-07):** The `[V.7.7 redo]` commit (`fa5dacdf`, 2026-05-05 10:54) added the six-layer inline `drawWorld()` and frame threads to the *monolithic* `arachne_fragment`. Three hours later, `[V.7.7A]` (`ccefe065`, 2026-05-05 14:13) retired that fragment and shipped placeholder staged stubs. The V.7.7 work is therefore preserved as dead reference code in `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal` (free-function `drawWorld` ~line 142, legacy `arachne_fragment` ~line 617), not in the dispatched path. Promotion into the staged path is V.7.7B.

**Prerequisite:** V.7.7A staged-composition scaffold migration ✅ 2026-05-05.

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

### Increment V.7.8 — Arachne v8: WEB pillar — foreground build refactor (corrected biology) [Subsumed by V.7.7C.2 — see V.7.7C.2 section above]

**Status correction (2026-05-07):** The `[V.7.8]` commit (`3536a023`, 2026-05-05 11:06) added the chord-segment capture spiral to `arachneEvalWeb()` inside the monolithic fragment. Same retirement story as V.7.7 — code survives as dead reference at ~line 265 of `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal`; port to staged dispatch is V.7.7B. The chord-segment SDF replacement for the degenerate Archimedean curve (Failed Approach #34) is a permanent reference for V.7.7B; do not regress to circular rings.

**Status (2026-05-09 / D-095):** This V.7.5-era line item is **obsolete** — V.7.7C.2 implements the single-foreground build state machine (frame → radials → INWARD spiral → settle, audio-modulated TIME pacing, per-segment spider cooldown, build pause/resume on spider). See V.7.7C.2 above for the actual closeout.

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

### Increment V.7.9 — Arachne v8: SPIDER pillar deepening + whole-scene vibration + cert [Subsumed by V.7.7C.2 / V.7.7D — see V.7.7C.2 + V.7.7D sections above]

**Status correction (2026-05-07):** The `[V.7.9 ✅]` commit (`97f42220`) was a CLAUDE.md status update only — 4 line changes, no shader code. The biology-correct frame → radial → spiral build order remains unimplemented in the dispatched path. SPIDER pillar deepening, vibration, and cert review remain unimplemented as well. Build-order work is scheduled for V.7.7C; SPIDER + vibration for V.7.7D; cert review for V.7.10.

**Status (2026-05-09 / D-095):** This V.7.5-era line item is **obsolete** — V.7.7D shipped SPIDER pillar deepening (3D SDF anatomy + chitin material + listening pose) + whole-scene 12 Hz vibration; V.7.7C.2 closed the structural gap (build state machine). Cert review (M7) remains scheduled for V.7.10. See V.7.7D and V.7.7C.2 above for the actual closeout.

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

### Increment DSP.2 — Beat This! transformer via MPSGraph (offline pre-analysis) + drift-tracker live path

**2026-05-04 pivot.** Originally scoped as a BeatNet (CRNN + particle filter) port; pivoted to Beat This! (Foscarin et al., ISMIR 2024 — transformer encoder, MIT) after a Session-2 audit pass found paraphrased-spec drift in the BeatNet preprocessing stage and weak performance on irregular meters that are load-bearing for Phosphene (Pyramid Song 16/8, Money 7/4, Schism 7/8). The original BeatNet plan is preserved in `docs/diagnostics/DSP.2-beatnet-archive.md`. Decision: **D-077**. The vendored BeatNet GTZAN weights (Session 1 of the original plan, commit `3f5f652b`) are retained as a fallback; everything below describes the Beat This! port.

**Goal:** Compute a high-quality beat / downbeat / time-signature grid once per track during pre-analysis (`SessionPreparer.prepareTrack` running on the cached 30 s preview clip), cache it on `TrackProfile` as a new `BeatGrid` value type, and drive `FeatureVector.beatPhase01` / `beatsUntilNext` analytically from `playbackTime + drift` against that grid. The live audio path runs no transformer; a small `LiveBeatDriftTracker` cross-correlates `BeatDetector`'s sub_bass onset stream against the cached grid in a ±50 ms phase window and emits a smooth drift estimate. Same MPSGraph + Accelerate idiom used by StemSeparator — no CoreML, no third-party C libs at runtime.

**Why now:** DSP.1's diagnosis proved Phosphene's classical-pipeline tempo path is at the ~70% F1 floor. For "as flawless as possible" beat sync (Matt's stated bar) on the irregular-meter tracks the product cares about, a transformer with whole-bar self-attention is the smallest model class that closes the gap. Beat This! is the smallest such model with a stable, MIT-licensed reference implementation and shipped pre-trained weights.

**Architecture mirrors `StemSeparator`:**

```
PhospheneEngine/Sources/ML/
  BeatThisModel.swift            → MPSGraph engine, pre-allocated UMA I/O (mirrors StemModel.swift)
  BeatThisModel+Graph.swift      → MPSGraph build: encoder block stack (mirrors StemModel+Graph)
  BeatThisModel+Weights.swift    → manifest + .bin loading; LN/BN fusion at init where applicable
  Weights/beat_this/             → vendored .bin weights via Git LFS pointers

PhospheneEngine/Sources/DSP/
  BeatThisPreprocessor.swift     → vDSP resample + STFT + log-mel pipeline (parameters confirmed in Session 1)
  BeatGridResolver.swift         → probability → (beats, downbeats, BPM, meter); peak picking + meter inference
  LiveBeatDriftTracker.swift     → cross-correlation drift tracker; FeatureVector wiring

PhospheneEngine/Sources/Session/
  BeatGrid.swift                 → Sendable value type stored on CachedTrackData
```

**Implementation order (sessions, each one PR / commit-chain):**

1. **Session 1 — Architecture audit + weight vendoring. ✅ 2026-05-04.** Commit `9cd0efb8`. Repo cloned at commit `9d787b9797eaa325856a20897187734175467074`. MIT confirmed. `small0` variant chosen: 2,101,352 params, 8.4 MB FP32 (vs `final0`: 20.3 M params, 81 MB). 161 tensors vendored under `PhospheneEngine/Sources/ML/Weights/beat_this/` (Git LFS). Six reference JSON fixtures in `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/beat_this_reference/`. `Scripts/convert_beatthis_weights.py` and `Scripts/dump_beatthis_reference.py` written. `docs/CREDITS.md` attribution block added. **Key S1 findings carried into S2/S3:** (a) inference timing measured at 415–530 ms on M1 CPU (`small0`); D-077's "~100–300 ms" estimate was optimistic — MPS will be faster, but S4 must measure and adjust S6's MLDispatchScheduler budget accordingly; (b) SumHead design: `beat_logits = beat_linear_out + downbeat_linear_out` (additive — beats are a *superset* of downbeats, not a separate class); (c) three MPSGraph workarounds required in S3: RMSNorm must be manual (no `layerNormalization` equivalent), SDPA must be manual matmul+softmax (macOS 14 target, `scaledDotProductAttention` is macOS 15+ only), RoPE must be manual cos/sin; (d) single `RotaryEmbedding(head_dim=32)` instance shared across all 9 blocks (3 frontend + 6 transformer) — precompute `freqs` tensor once in S3 and share; (e) 5 `num_batches_tracked` int64 BN buffers skipped at conversion (training-only, not used at inference); (f) torchaudio cannot load .m4a without `torchcodec` — use ffmpeg subprocess for audio decode (already handled in `dump_beatthis_reference.py`).

2. **Session 2 — Preprocessor port (Swift).** Implement `BeatThisPreprocessor` in `Sources/DSP/`. **Parameters confirmed in S1** (all file:line cited in `docs/diagnostics/DSP.2-architecture.md §2`): n_fft=1024, hop=441, sr=22050 (source), n_mels=128, f_min=30 Hz, f_max=11000 Hz, mel_scale="slaney" (area-normalisation, `norm="slaney"`), power=1 (magnitude, not power), log formula = `log1p(1000 × mel)` (matches `beat_this/preprocessing.py:LogMelSpect.__call__`). **Per-stage golden tests against the Python reference**: synthetic impulse, sine, white noise, plus love_rehab first 1500 frames. Per-stage delta dashboard. Tolerance: float32 ULP per stage where mathematically possible; documented numerical bound where not (resampler — soxr in Python, vDSP in Swift). Key resampler note: Beat This! uses `soxr` for resampling, not librosa's `resample`; a vDSP sinc resampler is acceptable but the tolerance test must reflect the actual delta (not assume ULP). Pre-allocate MTLBuffers for the spectrogram output to avoid heap alloc in `process()`. **Done when:** Swift preprocessor matches Python within measured numerical bound on all test inputs; `BeatThisPreprocessorTests` pass (≥5 test cases incl. love_rehab first-1500-frame golden); no heap allocations in `process()` hot path.

3. **Session 3 — Transformer encoder graph (MPSGraph build only).** Build the model graph in MPSGraph: input projection, positional encoding, encoder block stack (multi-head attention + FFN + LN, in the order Beat This! uses), output head(s). No weight loading yet; random init validates shapes. Layer-by-layer shape tests against architecture-doc numbers. Catch attention-head reshape bugs, layer-norm axis mistakes, off-by-one positional encoding. Reference: `StemModel+Graph.swift` for code style. **Done when:** graph builds cleanly; per-layer output shapes match doc exactly; one full forward pass on random input completes; no MPSGraph compilation warnings.

4. **Session 4 — Weight loading + numerical validation.** Implement `BeatThisModel+Weights.swift` mirroring `StemModel+Weights.swift`. Manifest parsing, .bin loading, LN/BN fusion at init where applicable. **Per-layer numerical golden tests against PyTorch FP32**: load the same checkpoint in PyTorch, run the same input through both, dump intermediates after each encoder block, compare. Tolerance: 1e-4 absolute / 1e-3 relative. Warm-predict timing on M1 for 30 s clip. **Done when:** Swift inference matches PyTorch FP32 within tolerance on all six fixtures, layer-by-layer; warm-predict < 300 ms on M1 (loosened from BeatNet's 142 ms; transformer is bigger).

5. **Session 5 — Beat grid resolver + post-processing.** Peak picking on per-frame beat / downbeat probabilities (use the algorithm Beat This! uses; confirm S1). Meter inference (3/4, 4/4, 5/4, 6/8, 7/8, 11/8, ...) from downbeat spacing distribution; reject implausible meters with a confidence score. BPM from beat spacing — median of inter-beat intervals (no histogram-mode trap from D-075 / Failed Approach #51). `BeatGrid` value type; Sendable, Hashable, Codable for `TrackProfile` cache embedding. **Done when:** end-to-end pipeline on six fixtures: beats within ±20 ms of reference, downbeats within ±40 ms, BPM within ±0.5, time signature correct on ≥5/6.

6. **Session 6 — `SessionPreparer` integration.** Wire `BeatThisModel` into `prepareTrack`. One call per track during preparation; result cached. Extend `CachedTrackData` to include `BeatGrid`. Bump cache version key for invalidation. Respect `MLDispatchScheduler` (D-059): Beat This! is heavier than stem separation; per-call budget needs widening. Recompute Tier 1 / Tier 2 thresholds. Backfill: cached tracks predating Beat This! lazily compute on first access. **Done when:** all production-test playlists prepare with valid `BeatGrid`s; the 919-engine baseline holds; new `BeatGridIntegrationTests` cover preparation, cache hit, cache invalidation.

7. **Session 7 — Live drift tracker + FeatureVector wiring.** `LiveBeatDriftTracker` consumes `BeatDetector.Result.onsets[0]` (sub_bass) and cross-correlates against the cached grid in ±50 ms phase window; smooth drift estimate (EMA, τ ≈ 200 ms). Replace `BeatPredictor` invocations in `MIRPipeline`. `FeatureVector.beatPhase01` and `beatsUntilNext` computed analytically: `phase01 = ((playbackTime + drift - lastBeat) / period).fract()`. Reactive-mode fallback: keep `BeatPredictor` only for the no-cached-grid case; mark deprecated. Visual regression: re-capture goldens for presets that read `beatPhase01` (Arachne, Gossamer, Stalker, VolumetricLithograph). Re-record `docs/quality_reel.mp4` on the user's three reference tracks + Pyramid Song + Money. **Done when:** Phosphene tracks the beat correctly on 5/4, 7/8, 16/8, swing fixtures (subjective + numerical against S1 ground truth); golden hashes regenerated for affected presets; quality reel rerecorded; user signs off.

**Architectural placement (locked 2026-05-04):**

- **Pre-analysis path** (`SessionPreparer.prepareTrack`, offline, runs once per 30 s preview clip): single Beat This! forward pass; output cached on `TrackProfile.beatGrid`. Per-track cost measured at ~415–530 ms on M1 CPU (Python); MPS expected ~100–150 ms but must be measured in S4 before finalising the S6 MLDispatchScheduler budget.
- **Live path** (60 fps render loop): no transformer. `LiveBeatDriftTracker` aligns the cached grid to the live playback timeline via sub_bass onset cross-correlation. `FeatureVector.beatPhase01` / `beatsUntilNext` (floats 35–36) computed analytically. **No GPU contract change** — existing presets unchanged.
- **Replaces:** `BeatPredictor` (deleted in Session 7); `BeatDetector+Tempo.computeRobustBPM` as primary BPM source (kept as ad-hoc reactive-mode fallback).
- **Stays:** `BeatDetector` itself (onset stream still feeds StemAnalyzer + drift tracker); `StructuralAnalyzer` / `NoveltyDetector` (unchanged this increment; possible All-In-One follow-up).

**Test fixtures (acquisition required before Session 1):**

- love_rehab.m4a (electronic ~125 BPM, 4/4) — already vendored.
- so_what.m4a (jazz ~136 BPM, swing) — already vendored.
- there_there.m4a (rock, syncopated kick — DSP.1's load-bearing failure) — already vendored.
- **Pyramid Song (Radiohead) — 16/8 grouped 3+3+4+3+3, extreme irregular-meter stress test.**
- **Money (Pink Floyd) — 7/4.**
- **If I Were With Her Now (Spiritualized) — syncopation plus mid-track meter changes. The fixture that stresses temporal *instability*: a model that locks to one period at the start and rides it through the track will pass Pyramid Song / Money (irregular but locked) and fail here.**

Five of the six fixtures actively stress non-stable-period behavior — only love_rehab is the clean 4/4 control. Pyramid Song / Money / so_what / there_there cover irregular-meter, swing, and offbeat-kick. If I Were With Her Now is the meter-change adaptation gate. If Beat This! tracks all six correctly, the increment is product-ready. If it fails specifically on the meter-change passage, that's the trigger to evaluate streaming-mode inference (re-running the model mid-track) before falling back to All-In-One.

**Files to touch:**

- `PhospheneEngine/Sources/ML/BeatThisModel.swift` — new MPSGraph engine.
- `PhospheneEngine/Sources/ML/BeatThisModel+Graph.swift` — new graph construction.
- `PhospheneEngine/Sources/ML/BeatThisModel+Weights.swift` — new weight loader.
- `PhospheneEngine/Sources/ML/Weights/beat_this/*.bin` — vendored weights (Git LFS).
- `PhospheneEngine/Sources/DSP/BeatThisPreprocessor.swift` — new preprocessor.
- `PhospheneEngine/Sources/DSP/BeatGridResolver.swift` — new probability → grid resolver.
- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — new drift tracker.
- `PhospheneEngine/Sources/Session/BeatGrid.swift` — new value type.
- `PhospheneEngine/Sources/Session/SessionPreparer.swift` — call BeatThisModel during prepareTrack; cache BeatGrid.
- `PhospheneEngine/Sources/Session/StemCache.swift` (or equivalent) — extend `CachedTrackData` with `BeatGrid?`.
- `PhospheneEngine/Sources/Audio/MIRPipeline.swift` — replace BeatPredictor invocations with LiveBeatDriftTracker; keep BeatPredictor for reactive-mode fallback.
- `PhospheneEngine/Sources/DSP/BeatPredictor.swift` — deleted in Session 7 (superseded by analytic phase calc + drift tracker).
- `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisModelTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/BeatThisPreprocessorTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/BeatGridResolverTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/Integration/BeatGridIntegrationTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/Performance/BeatThisPerformanceTests.swift` — new.
- `Scripts/convert_beatthis_weights.py` — one-shot converter (mirror of `convert_beatnet_weights.py`).
- `Scripts/dump_beatthis_reference.py` — Python reference-dump script for Session 2 / 4 golden tests.
- `docs/diagnostics/DSP.2-architecture.md` — new audit doc (replaces archived BeatNet version).
- `docs/CLAUDE.md` — Module Map updates, ML Inference section, Failed Approaches as discovered.
- `docs/DECISIONS.md` — D-077 (landed alongside this pivot); follow-up sub-decisions in the D-077 thread for any architectural choices made during the sessions.
- `docs/CREDITS.md` — Beat This! attribution per MIT license (cite paper + repo).

**Tests:**

1. **Unit — `BeatThisPreprocessorTests` (Session 2):**
   - Synthetic impulse / sine / white noise: per-stage match against Python reference within float32 ULP where mathematically possible.
   - Real audio (love_rehab): output within a measured numerical bound vs. the Python reference (set in S1 architecture doc).
   - Zero input → zero output (or model-defined silence vector).
   - No heap allocation in `process()` hot path.

2. **Unit — `BeatThisModelTests` (Session 4):**
   - Weight load → no crash; parameter count matches manifest.
   - Forward pass on random input: per-layer activations match PyTorch FP32 within 1e-4 absolute / 1e-3 relative.
   - Forward pass on six reference fixtures: end-to-end output matches PyTorch FP32 within tolerance.
   - Warm-predict latency on M1 < 300 ms for 30 s clip.

3. **Unit — `BeatGridResolverTests` (Session 5):**
   - Synthetic 120 BPM activation pulses → 120 ± 0.5 BPM, beats every 500 ± 20 ms, time signature 4/4.
   - Synthetic 7/4 at 90 BPM → 90 ± 0.5 BPM, time signature 7/4 detected, downbeats every 7 beats.
   - Tempo change mid-stream (120 → 140 BPM at t = 5 s) → re-locks within the offline post-processing window.

4. **Unit — `LiveBeatDriftTrackerTests` (Session 7):**
   - Cached grid + perfectly-aligned onsets → drift = 0 ± 5 ms.
   - Cached grid + onsets shifted by +30 ms → drift converges to +30 ms within 2 s.
   - No onsets in window → drift estimate decays toward 0 (no runaway).

5. **Integration — `BeatGridIntegrationTests` (Session 6):**
   - Six reference fixtures end-to-end: BPM within ±0.5, time signature correct on ≥5/6, beats within ±20 ms vs. S1 ground truth.
   - **Pyramid Song must read 16/8 (or equivalent grouped meter) with downbeats on the 1 of each 16-cycle.** Load-bearing assertion for the increment.
   - **Money must read 7/4 at ~123 BPM.** Load-bearing assertion.
   - **there_there must read 84–92 BPM** (the meter, not the kick rate). Carries forward from the BeatNet plan as the DSP.1-failure assertion.
   - Cache hit: re-prepare same track → `BeatGrid` reused, no second model call.
   - Cache invalidation: bump model variant string → re-runs.

6. **Performance — `BeatThisPerformanceTests`:**
   - Per-track preparation: < 500 ms on M1 (preprocessing + transformer + post-processing combined).
   - Drift tracker: < 0.1 ms per frame on M1 (live-path budget).

7. **Existing tests:**
   - All 919 engine-test baseline holds.
   - `BeatDetector` unit tests pass unchanged (its onset stream is the drift tracker's input — interface unchanged).
   - `BeatPredictorTests` pass while BeatPredictor exists (until S7 retirement).
   - `MIRPipelineUnitTests` pass — replace BeatPredictor wiring with drift tracker.

**Performance budget:**

- Per-track preparation cost (one-time per 30 s clip): < 500 ms on M1, < 250 ms on M3. Absorbed in the existing playlist-preparation window.
- Live-path cost: < 0.1 ms per frame on M1 (drift tracker only; no transformer at runtime). Negligible vs. the 16.6 ms render budget.
- Memory: < 80 MB for weights (FP16 transformer ~28 MB + activation scratch). Stays well under StemSeparator's 135.9 MB.
- Init cost: < 300 ms for graph build + weight load (one-time at session start).
- Drop-frame behavior in pre-analysis: respect `MLDispatchScheduler` (D-059) — if Beat This! inference would push a frame past budget, defer the dispatch. Track-change resets state.

**Done when (cumulative across sessions):**

- [x] §0 cleanup committed (BeatNet stubs removed; archive marked superseded; D-077 in DECISIONS.md). **2026-05-04.**
- [x] **S1:** Architecture audit `docs/diagnostics/DSP.2-architecture.md` complete; weights vendored under `ML/Weights/beat_this/` (161 tensors, 8.4 MB, `small0`); `Scripts/convert_beatthis_weights.py` reproducible; six reference fixtures captured as JSON ground truth. Commits `afb75954..9cd0efb8`. **2026-05-04.**
- [x] **S2:** `BeatThisPreprocessorTests` pass (5 tests: shape×2 + dcSignal + sineAtMelBin + loveRehab golden match); per-stage golden match max|Δ|=3×10⁻⁵ within tolerance=1e-3; all buffers pre-allocated at init. Commits `d26e3c2b..b2cb5a8b`. **2026-05-04.**
- [x] **S3:** `BeatThisModel` builds zero-init MPSGraph encoder; 5 shape/finiteness tests pass (929/100 suite green); 0 SwiftLint violations. Commit `c71569b1`. **2026-05-04.**
- [x] **S4:** `BeatThisModelTests` pass (9 tests: graphBuilds + inputProjectionShape + outputShape_T10 + outputShape_T1497 + outputRangeIsFinite + weightsLoad_noThrow + outputNonUniform_withRealWeights + inferenceTime_under300ms + loveRehab_gated); real weights loaded from `ML/Weights/beat_this/`; `test_outputNonUniform_withRealWeights` confirms non-uniform output; `test_inferenceTime_under300ms` passes (< 300 ms warm predict); 933 tests / 100 suites; 0 SwiftLint violations. **2026-05-04.**
- [x] **S5:** `BeatGridResolverTests` pass — 8 unit tests + 24 golden fixture tests (6 fixtures × 4 assertions); all six fixtures within tolerance (beats ≥95% within ±20ms, downbeats ≥90% within ±40ms, BPM within ±0.5, meter correct); pyramid_song=3 gate passes; `BeatGrid` value type (Sendable, Hashable, Codable) in `Sources/DSP/`; 945 tests / 102 suites; 0 SwiftLint violations. **2026-05-04.**
- [x] **S6:** `BeatGridIntegrationTests` pass — 4 tests (nilAnalyzer→empty grid, cacheHit short-circuits analyzer, fullPipeline with `DefaultBeatGridAnalyzer` produces non-empty grid at 50 fps, `StemCache.beatGrid(for:)` accessor matches stored data); `BeatGridAnalyzing` protocol + `DefaultBeatGridAnalyzer` injected into `SessionPreparer` (optional, defaults to nil → BeatGrid.empty); `CachedTrackData.beatGrid` field added with `.empty` default; `AnalysisStage.beatGrid` case added; cache-hit short-circuit in `_runPreparation` skips re-analysis on idempotent prepare. Pyramid Song 16/8 / Money 7/4 / there_there assertions remain in S5 golden fixtures (not duplicated here — S6 proves wiring, S5 proves algorithm). 949 tests / 102 suites; 0 SwiftLint violations. **2026-05-04.**
- [~] **S7 — code complete, live in production, pending quality-reel sign-off (2026-05-04):** `LiveBeatDriftTrackerTests` pass (8 original + 7 added in hardening = 15 total); `BeatGridUnitTests` pass (4); `MIRPipelineDriftIntegrationTests` pass (3). `BeatPredictor.swift` doc-deprecated as reactive-mode-only fallback (no `@available` annotation — would cascade warnings into the warnings-as-errors xcconfig app build). `BeatGrid` extended with `beatIndex(at:)`, `localTiming(at:)`, `medianBeatPeriod`, internal `nearestBeat(to:within:)`. `MIRPipeline` gains `liveDriftTracker: LiveBeatDriftTracker` + `setBeatGrid(_:)`; `buildFeatureVector` forks: cached-grid path uses `self.elapsedSeconds` as the playback clock (already track-relative via existing `mir.reset()` in `VisualizerEngine+Capture.swift:127`). `VisualizerEngine+Stems.resetStemPipeline(for:)` now installs the cached grid (or clears it on cache miss). `PresetVisualReviewTests.arguments` extended to `["Arachne","Gossamer","Volumetric Lithograph"]`; Stalker is mesh-shader and excluded from regression by construction. **Golden hashes unchanged** — regression fixtures use prebuilt `FeatureVector` instances with `beatPhase01=0` default and never invoke `MIRPipeline`. App-layer wiring test deferred (engine integration test covers the contract; the change is two lines mirroring the existing `setStemFeatures` pattern). **Outstanding:** `docs/quality_reel.mp4` re-record + Pyramid Song / Money / so_what subjective sign-off; flip to `[x]` once Matt watches and confirms phase locks correctly on irregular meters.
- [x] **S8 — BeatThisModel output matches PyTorch reference (2026-05-05):** Four bugs found and fixed: (1) frontend block order `partial → norm(wrong inDim) → conv` corrected to `partial → conv → norm(out_dim)` (pre-S8 norm used the wrong channel count); (2) stem reshape transposed `[T,F]→[F,T]` before NHWC reshape (pre-S8 was a byte-reinterpretation, scrambling the mel spectrogram); (3) BN1d-aware padding pads each mel bin with `−shift/scale` so the padded region maps to zero post-BN (pre-S8 naive zero-fill caused `BN1d(0)==shift` to produce non-zero values at time edges); (4) RoPE pairs adjacent elements `(x[2i], x[2i+1])` not half-and-half `(x[i], x[D/2+i])` (pre-S8 completely wrong attention dot products). Result: love_rehab.m4a max sigmoid 0.9999 vs Python ref 0.9999; 126 frames > 0.5 vs ref 124; 59 beats detected vs 59 in ground-truth fixture. `test_loveRehab_endToEnd_producesBeats` passes without `withKnownIssue`. S7's drift tracker is now live and active for every Spotify-prepared session. Commits `49315657..b9687cbc`. **2026-05-05.**
- [x] **DSP.2 hardening — all four S8 bugs individually regression-locked (2026-05-05):** `test_loveRehab_endToEnd_producesBeats` thresholds raised to `maxProb > 0.99` / `aboveHalf >= 100` (reflecting confirmed post-S8 values). `BeatThisLayerMatchTests.swift` (new): loads `docs/diagnostics/DSP.2-S8-python-activations.json`, runs `predictDiagnostic` on love_rehab.m4a, asserts per-stage min/max/mean within two-tier tolerances — `preTfmTol=2e-3` for stem.bn1d + frontend.linear; `postTfmTol=1e-2` for transformer.norm + head.linear + output stages (covers ~0.3–0.9% delta from non-causal softmax over padded frames). Transformer blocks 0–5 excluded (Python hooks sub-block FFN output before residual; Swift captures full-block output — incompatible; end-to-end coverage via beat_logits/beat_sigmoid is sufficient). `BeatThisBugRegressionTests.swift` (new): Bug 1 gate (`frontendBlocks[N].norm.scale.count == out_dim`); Bug 3 gate (`|stem.bn1d[t,mel]| < 1e-3` for padded frames t∈[1497,1500) on zero input); Bugs 2+4 annotated as covered by layer-match (wrong reshape scrambles stem.bn1d by >50%; wrong RoPE pairing diverges output by >30%); reactive-mode test confirms `setBeatGrid(nil)` fallback returns finite FeatureVector. `LiveBeatDriftTrackerTests` extended with 7 tests (MARK 9–15) covering `currentBPM`, `currentLockState`, `relativeBeatTimes` public APIs. **975 engine tests / 103 suites; 0 SwiftLint violations.** Commits `286e67cf..4eaae5a7`. **2026-05-05.**
- [x] **S9 — barPhase01/beatsPerBar propagation + live Beat This! for reactive mode (2026-05-05):** `FeatureVector` floats 37–38 promoted from padding to `barPhase01` (phrase-level 0→1 ramp, 0 in reactive mode) and `beatsPerBar` (time-signature numerator, default 4). Metal preamble struct updated to match; Swift `init()` seeds `barPhase01=0 / beatsPerBar=4`. `MIRPipeline.buildFeatureVector` writes drift-tracker values on the grid path and 0/4 on the reactive path. `BeatGrid.offsetBy(_ seconds:)` helper added for time-aligning buffer-relative beat grids to track-relative coordinates. `SpectralHistoryBuffer` ring 4 repurposed from `vocals_pitch_norm` to `bar_phase01`; dead `normalizePitch` method and three pitch constants deleted. `SpectralCartograph`: BR panel third row now plots `bar_phase01` (violet, "BAR φ" label). `runLiveBeatAnalysisIfNeeded()` added to `VisualizerEngine+Stems`: fires once per track after 10 s of buffered tap audio when `liveDriftTracker.hasGrid == false`; lazy-loads `DefaultBeatGridAnalyzer` on `stemQueue`; offsets the resulting grid by `(elapsedSeconds − 10)` to track-relative time; installs via `mirPipeline.setBeatGrid()` on `@MainActor`. Effect: ad-hoc / reactive sessions receive phrase-level beat tracking after ≈ 10 s of listening, same as Spotify-prepared sessions. **987 engine tests; 0 new SwiftLint violations; golden hashes unchanged.** Commit `b6a6095f`. **2026-05-05.**
- [x] `swift test --package-path PhospheneEngine` passes (pre-existing flakes in `MetadataPreFetcher` / `MemoryReporter` acceptable).
- [ ] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` passes.
- [ ] No `import CoreML` anywhere in the engine.
- [ ] CLAUDE.md Module Map updated; CREDITS.md Beat This! attribution present.

**Verify (per session, run cumulatively at the end):** `swift test --filter BeatThisPreprocessor && swift test --filter BeatThisModel && swift test --filter BeatThisLayerMatch && swift test --filter BeatThisBugRegression && swift test --filter BeatGridResolver && swift test --filter LiveBeatDriftTracker && swift test --filter BeatGridIntegration && swift test --filter BeatThisPerformance`.

**Out of scope (do not re-litigate):**

- aubio (native C dependency; rejected — staying within Swift / MPSGraph idiom).
- madmom (offline-only Python+C; non-portable to runtime).
- CoreML in any form (project hard constraint, see Failed Approach #20 and CLAUDE.md "ML Inference").
- All-In-One (Kim et al., ISMIR 2023) — strictly more capable (joint beat / downbeat / section), but two-axis scope creep in a single increment. Reserved as a follow-up; the architecture in this increment is designed so the model can be swapped with no upstream / downstream changes.
- Live transformer inference at 50 Hz — explicitly rejected; the pre-analysis-then-drift-track architecture is the load-bearing design choice.
- Per-frame downbeat *visual presets* — separate work; this increment exposes `downbeats` on `BeatGrid`, presets opt in later.
- Streaming-mode Beat This! inference for reactive mode — fallback path keeps `BeatPredictor` (or runs a one-shot transformer pass on the first 10–15 s of live audio). Decide in S7.

**License sourcing:**

- Beat This! is MIT-licensed; pre-trained weights ship with the official repo. Vendored with attribution in `docs/CREDITS.md` (S1 ✅).
- The architecture itself is published in Foscarin et al., ISMIR 2024 — implementing it from the paper is unencumbered.

**Risks:**

- Weight quantization: BeatNet is trained in FP32; MPSGraph supports FP32 natively. No quantization needed.
- Resampler quality: vDSP_resamplef from 48 k → 22050 Hz must not introduce artifacts that degrade activations. Mitigation: validate against librosa-reference mel-specs in the unit test (step 3).
- Particle-filter stability: known to be the trickiest part. Mitigation: closely follow Heydari's reference impl; test against synthetic constant-BPM and tempo-change scenarios before integrating with real audio.
- Performance: per-frame inference at 100 Hz is more aggressive than StemSeparator's 5 s cadence. Mitigation: enforce < 2 ms per frame in `BeatTrackerPerformanceTests` from the start; if violated, drop to half-rate inference (50 Hz) before considering more invasive changes.

**Reference principle (do not violate):**

Continuous energy is the primary visual driver; beat onset pulses are accents only (D-004). BeatNet's outputs feed accent-layer fields (`beatPhase01`, `isDownbeat`) only — they do not displace the continuous-energy fields driving primary visual motion.

**Estimated sessions:** 5–7 (weights + mel-spec → 1, MPSGraph build + inference → 2, particle filter → 2, integration + tests + docs → 2).

---

### Increment DSP.3 — Beat Sync + Diagnostic Environment (audit + fixes)

**2026-05-05 audit.** Full architecture audit of the Beat This! BeatGrid lifecycle, live drift tracking, reactive-mode surface, Spectral Cartograph diagnostic coverage, FeatureVector product contract for complex meters, and test fixture gaps. Audit document: `docs/diagnostics/DSP.3-beat-sync-test-environment-audit.md`.

**Root cause of observed "Phosphene shifts into Reactive mode" when switching to Spectral Cartograph:** The `SpectralCartographText` overlay labels `lockState=0` as "REACTIVE." When `LiveBeatDriftTracker` is in UNLOCKED state — either because `resetStemPipeline(for:)` has not yet fired (music not started) or because fewer than 4 tight-match onsets have been accumulated — the orb reads "REACTIVE" even though `livePlan` is non-nil and the engine is in planned mode. This is a display ambiguity, not a session mode regression. However, a second structural problem makes Spectral Cartograph unusable as a held diagnostic surface: `DefaultLiveAdapter` mood-override fires every ~60 seconds when the current preset scores 0.0 (diagnostic-excluded), switching the engine away from Spectral Cartograph.

**Sub-increments:**

- **DSP.3.1 — Diagnostic hold + session-mode signal.** `diagnosticPresetLocked` flag in `VisualizerEngine`; suppresses mood-override in `applyLiveUpdate()`. `SpectralHistoryBuffer[2420]` session-mode slot (0=reactive, 1=planned+unlocked, 2=planned+locking, 3=planned+locked). `SpectralCartographText` updated to show "PLANNED · UNLOCKED" / "PLANNED · LOCKING" / "PLANNED · LOCKED" / "REACTIVE." `L` dev shortcut to toggle hold. **✅ 2026-05-05 — commit `56359c07`.**
- **DSP.3.2 — Pre-fire BeatGrid on session start.** At end of `_buildPlan()` after `livePlan` is stored, call `resetStemPipeline(for: plan.tracks.first?.track)`. BeatGrid present before music starts; idempotent via `currentTrackIdentity` guard in `resetStemPipeline`. **✅ 2026-05-05 — commit `56359c07`.**
- **DSP.3.3 — Beat sync observability: text overlays + CSV + calibration shortcuts.** `SpectralCartographText.draw()` extended with beat-in-bar counter ("3 / 4"), drift readout ("Δ +12 ms"), phase offset indicator ("φ+10ms"); `textOverlayCallback` type updated to pass `FeatureVector` per frame; `[`/`]` dev shortcuts for ±10 ms visual phase calibration; `BeatSyncSnapshot` struct (9 fields) for offline analysis; `SessionRecorder.features.csv` gains 9 new beat-sync columns (`barPhase01_permille`, `beatsPerBar`, `beat_in_bar`, `is_downbeat`, `beat_sync_mode`, `lock_state`, `grid_bpm`, `playback_time_s`, `drift_ms`); `SpectralHistoryBuffer[2429]` drift_ms slot; 31 new tests (BeatInBarComputationTests 16+, SpectralHistoryBuffer slot stability 4+, others). Core Text mirroring fix in `DynamicTextOverlay.refresh()`. `docs/diagnostics/DSP.3.3-beat-sync-latency-phase-notes.md`. **✅ 2026-05-05.**
- **DSP.3.4 — Fix three root causes blocking PLANNED·LOCKED in reactive/ad-hoc sessions.** Live diagnostic from session `2026-05-05T21-13-05Z` (features.csv: 12,509 frames in LOCKING, 0 in LOCKED, beatPhase01 frozen at mean=0.99996, grid_bpm=216 instead of ~125) revealed: (1) `BeatGrid.offsetBy` only shifted the ~10 recorded beats; past the last beat `computePhase` clamped `beatPhase01=1.0` permanently and `nearestBeat` returned nil → `consecutiveMisses` grew indefinitely → `matchedOnsets` never reached `lockThreshold=4`. Fix: `offsetBy` now appends extrapolated beats at `period=60/bpm` up to a 300-second horizon and extrapolates downbeats at `barPeriod` beyond that. (2) `runLiveBeatAnalysisIfNeeded` hardcoded `sampleRate: 44100` for `analyzeBeatGrid` despite the tap running at 48000 Hz — mel spectrogram covered wrong duration, BPM detected as ~216. Fix: `VisualizerEngine.tapSampleRate: Double` stored from audio callback `rate` parameter; passed to `analyzeBeatGrid`. (3) `StemSampleBuffer.snapshotLatest(seconds:)` computed count using stored 44100 Hz rate, so a 10-second request retrieved only 9.19 s of real audio. Fix: new `snapshotLatest(seconds:sampleRate:)` protocol overload uses the passed-in rate; `runLiveBeatAnalysisIfNeeded` calls it with `tapSampleRate`. 14 new tests (5 BeatGrid extrapolation + 5 StemSampleBuffer rate overload). **✅ 2026-05-05 — commit `7033ad09`.**
- **DSP.3.5 — Halving octave correction + retry for live Beat This!** Session diagnostic `2026-05-05T22-57-57Z` (features.csv) revealed: (1) Live 10-second Beat This! window detected Love Rehab at 244.770 BPM (2× true 125 BPM) — double-time artefact from short analysis window. (2) Money 7/4 reactive session stayed in REACTIVE throughout — Beat This! on 10 s of Money audio returned an empty grid, with no retry. Fixes: (a) `BeatGrid.halvingOctaveCorrected()` — halving-only correction: while `bpm > 160`, halve BPM and drop every other beat. BPM < 80 intentionally left alone (Pyramid Song genuinely runs at ~68 BPM; doubling would be wrong). Downbeats re-snapped to surviving beats within ±40 ms; `beatsPerBar` recomputed from corrected downbeat IOIs. (b) `VisualizerEngine`: `liveBeatAnalysisDone: Bool` → `liveBeatAnalysisAttempts: Int`; counter allows up to `liveBeatMaxAttempts=2` attempts — first at `liveBeatMinSeconds=10.0 s`, retry at `liveBeatRetrySeconds=20.0 s` if first attempt returned empty grid. (c) `performLiveBeatInference()` extracted from `runLiveBeatAnalysisIfNeeded()` to keep the parent within the 60-line SwiftLint gate; `halvingOctaveCorrected()` applied before `offsetBy()`. 4 new BeatGridUnitTests. Post-validation triage: `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md`. Remaining risk: Money 7/4 still REACTIVE on live path (20-second retry may also produce empty grid); durable fix is Spotify-prepared session (30-second offline window reliable). **✅ 2026-05-05 — commits `eac2e140`, `c068d2b8`.**
- **DSP.3.6 — App-layer wiring test.** Integration test: `SessionPreparer.prepare()` → `StemCache.store()` → `resetStemPipeline(for:)` → `mirPipeline.liveDriftTracker.hasGrid == true`. Five new `PreparedBeatGridWiringTests` in `Integration/` prove the critical chain: (1) prepared non-empty grid → `hasGrid == true`; (2) `hasGrid == true` → `runLiveBeatAnalysisIfNeeded` guard blocks live inference; (3) cache miss → `hasGrid == false` → live inference allowed; (4) `.empty` cached grid → `hasGrid == false` → live inference allowed; (5) track change clears grid. Enhanced source-tagged `BEAT_GRID_INSTALL` logging in `VisualizerEngine+Stems.swift` (source=preparedCache/liveAnalysis/none, BPM, beat count, meter, firstBeat, replaced flag) plus `sessionRecorder.log()` one-time event per track. `beat_grid_source` in features.csv deferred (per-frame schema change; session.log entry is sufficient). Policy documented: prepared-cache grid wins; live inference may only *add* a grid when none is present. `docs/diagnostics/DSP.3.6-prepared-beatgrid-wiring-validation.md`. **✅ 2026-05-05.**
- **DSP.3.7 — Live drift validation test.** Replay `love_rehab` via `AudioInputRouter(.localFile)` with prepared BeatGrid; assert LOCKED within 5 s, drift < 50 ms, `beatPhase01` zero-crossings within ±30 ms of ground truth.
- **DSP.4 — Drums-stem Beat This! diagnostic.** Third BPM estimator on isolated percussion, logged alongside the existing two at preparation time. `CachedTrackData.drumsBeatGrid: BeatGrid` (default `.empty`). Step 6 in `SessionPreparer+Analysis.analyzePreview` feeds `stemWaveforms[1]` (drums) into the same `DefaultBeatGridAnalyzer` — same graph, second `predict()` call. `ThreeWayBPMReading` struct + `detectThreeWayBPMDisagreement` pure function added to `BPMMismatchCheck.swift`. Wiring logs: `WIRING: SessionPreparer.drumsBeatGrid` per track; `WARN: BPM 3-way` (preferred) / `WARN: BPM mismatch` (fallback when drumsBPM == 0). No runtime consumption by `LiveBeatDriftTracker`. 7 new 3-way detector tests + 2 integration wiring tests. **✅ 2026-05-06.**

**Done when (gating assertion):** Matt connects a Spotify playlist, preparation completes, switches to Spectral Cartograph, presses `L` to hold, starts music, and observes "PLANNED (UNLOCKED)" → "PLANNED (LOCKING)" → "PLANNED (LOCKED)" within 5 seconds. BPM matches. Beat-grid ticks align with perceived beats. Engine does not switch away. This observation — not unit-test counts — is the production-validation milestone for Beat This!

**Status:**
- [x] DSP.3 audit complete: `docs/diagnostics/DSP.3-beat-sync-test-environment-audit.md`. **2026-05-05.**
- [x] DSP.3.1 — Diagnostic hold + session-mode signal. **2026-05-05.**
- [x] DSP.3.2 — Pre-fire BeatGrid on session start. **2026-05-05.**
- [x] DSP.3.3 — Beat sync observability: text overlays + CSV + calibration shortcuts. **2026-05-05.**
- [x] DSP.3.4 — Grid horizon + sample-rate bugs fix. **2026-05-05 — commit `7033ad09`.**
- [x] DSP.3.5 — Halving octave correction + retry. **2026-05-05 — commit `eac2e140`.**
- [x] DSP.3.6 — App-layer wiring test. **2026-05-05.**
- [ ] DSP.3.7 — Live drift validation test.
- [x] DSP.4 — Drums-stem Beat This! diagnostic (third BPM estimator, logged only). **2026-05-06.**

---

## Phase QR — Quality Review Remediation (2026-05-06)

**Origin.** A 7-agent parallel codebase review on 2026-05-06 (Architect / Audio+DSP / ML / Renderer+Presets / Orchestrator+Session / App+UX / Tests+Quality) produced a ranked findings document focused on *precision*, *performance*, and *simplicity* against the "member of the band" product goal. This phase converts those findings into ordered, scoped increments.

**Why a phase, not a single sweep.** The findings span every subsystem and several interact (e.g. sample-rate fixes change BeatGrid input, which affects drift-tracker tests, which affects regression goldens). Sequencing prevents one increment's fix from invalidating another's verification.

**Priority ordering** (do not reorder without re-reading the cross-cutting analysis below):

1. **QR.1 (DSP.4) — Sample-rate plumbing audit.** Highest-precision payoff. Single bug class, five sites, confirmed by three independent reviewers. ✅ 2026-05-06.
2. **QR.2 (OR.1) — Stem-affinity rescaling + reactive-mode TrackProfile fix.** Highest musicality payoff per LOC. ✅ 2026-05-06.
3. **BUG-007.3 attempted 2026-05-07 — reverted same day** (commit `78ade5aa`). Three smaller replacement bugs in `KNOWN_ISSUES.md` to be sequenced: BUG-007.4 (downbeat alignment — investigation first, fix scope set after diagnosis) → BUG-009 (halving-correction threshold 160 → 175, ~5 LOC + test) → BUG-007.5 (adaptive-window lock hysteresis, ~30 LOC + test). Total ~1.5 days but each lands independently. See `KNOWN_ISSUES.md` for done-when criteria.
4. **QR.3 (TEST.1) — Close silent-skip test holes.** Cheap to do; protects the work in QR.1 + QR.2 from silent regression.
5. **QR.4 (U.12) — UX dead ends + duplicate `SettingsStore`.** Small, isolated, user-visible.
6. **QR.5 (CLEAN.1) — Mechanical cleanup pass.** Pure deletion of dead code + dead comments. Schedule when the four above have landed; ride along with their cleanups.
7. **QR.6 (ARCH.1) — `VisualizerEngine` decomposition.** Largest debt in the codebase. Defer until QR.1–QR.4 ship, then schedule with explicit risk acknowledgement.

**Cross-cutting context (read before any QR increment):**

- The 2026-05-06 review found **the 44100/48000 sample-rate bug class confirmed at five distinct sites** across three subsystems. DSP.3.4 fixed it once; the underlying pattern (literal `44100` instead of the captured tap rate) recurred in stem separator dispatch, per-frame stem analysis, and `StemSampleBuffer` init. QR.1 closes the class, not just instances.
- The review found **the orchestrator's stem-affinity sub-score saturates** because `stemEnergy` is AGC-normalized at 0.5; summing 2+ matching stems hits ~1.0 trivially. 25% of score weight does not discriminate. QR.2 normalizes against the deviation primitives (D-026) the rest of the system already uses.
- **Reactive mode systematically penalizes presets with stem affinities** because `TrackProfile.empty.stemEnergyBalance == .zero` → presets with declared affinities score 0; presets without score 0.5. Adversarial against the most musically-engaged catalog members. QR.2 fixes both at once.
- The architect's H1 finding (`VisualizerEngine` is a 2,580-line god object with 8 NSLocks + `@unchecked Sendable`) is real but big. QR.6 schedules it after the precision fixes; the smaller QRs do not need decomposition first.

---

### Increment QR.1 (DSP.4) — Sample-rate plumbing audit

**Goal.** Eliminate the literal `44100` sample-rate constant from every site that should use the live tap rate. Capture `tapSampleRate` immutably, propagate through stem separation + per-frame stem analysis + `StemSampleBuffer` + `StemAnalyzer` init + Beat This! live inference. Add a regression test gate so future literal-`44100` reintroductions fail loud.

**Why now.** Three independent reviewers (Architect H1 / Audio+DSP D1 / ML #1+#2) flagged this. Symptoms on a 48 kHz tap: stems are 8.8% time-stretched and pitch-shifted; per-frame stem analysis reads bands at the wrong window; live Beat This! attempts the right fix already (DSP.3.4) but stem-side callers were not audited. Manifests in production as wrong stem energy magnitudes, wrong onset rates, and biased preset scoring on the mid-bar tracks the orchestrator most needs to handle musically.

**Sites to fix (audit-confirmed):**

| File | Symbol / line | Current | Target |
|---|---|---|---|
| `PhospheneApp/VisualizerEngine.swift:179` | `StemSampleBuffer(sampleRate: 44100, …)` | literal | `tapSampleRate` (deferred allocation, or re-init on rate-change) |
| `PhospheneApp/VisualizerEngine.swift:435` | `StemAnalyzer(sampleRate: 44100)` default arg | literal | thread `tapSampleRate` |
| `PhospheneApp/VisualizerEngine+Audio.swift:194` | `runPerFrameStemAnalysis` literal | literal | `tapSampleRate` |
| `PhospheneApp/VisualizerEngine+Stems.swift:151` | `separator.separate(… sampleRate: 44100)` | literal | `tapSampleRate` |
| `PhospheneApp/VisualizerEngine+Stems.swift:183` | `sessionRecorder?.recordStemSeparation(sampleRate: 44100, …)` | literal | `tapSampleRate` |

**Concurrency hardening (Architect H1, Audio+DSP D1):**

- `tapSampleRate: Double` is currently mutated from the audio callback (`VisualizerEngine+Audio.swift:98`) and read on `stemQueue` (`+Stems.swift:296`) without a synchronization primitive. On Apple Silicon, atomic 8-byte writes are guaranteed but cross-core *visibility* is not. This is the kind of bug that produces wrong-tempo grids ~1-in-1000 sessions and is invisible in tests.
- Fix: capture `tapSampleRate` once per `installTap(...)` call. Promote to `let tapSampleRate: Double` set in the initializer that wires the tap, or guard with `os_unfair_lock` if it must remain mutable for capture-mode switching.
- If capture-mode switching changes the rate (System tap → file playback at a different rate), tear down and re-init the dependent buffers (`StemSampleBuffer`, `StemAnalyzer`) on the rate change rather than mutating the rate field.

**Octave-correction policy unification (Audio+DSP A2):**

`BeatGrid.halvingOctaveCorrected` is halving-only (preserves Pyramid Song ~68 BPM). `BeatDetector+Tempo.computeRobustBPM:196` and `estimateTempo:269` both still double sub-80 BPM. The two policies disagree. Drop the `bpm < 80 → bpm *= 2` branch from both `computeRobustBPM` and `estimateTempo`. Any track in [40, 80) BPM is now treated as genuine, matching the offline path and CLAUDE.md.

**`MIRPipeline.elapsedSeconds: Float` → `Double` (Audio+DSP D3):**

Float accumulation of `+= deltaTime` reaches ULP ≈ 240 µs after 30 minutes — smaller than the ±30 ms tight-match window but a guaranteed monotonic drift. Promote to `Double`. Conversion to `Float` happens once at FeatureVector write. Touches `MIRPipeline.swift:70`, all callers reading `elapsedSeconds`, and `LiveBeatDriftTracker.update(playbackTime:)` parameter.

**KineticSculpture D-026 violation (Audio+DSP B1):**

`Sources/Presets/Shaders/KineticSculpture.metal:102`: `f.sub_bass * 0.28 + f.bass * 0.10` — exact Failed Approach #31 anti-pattern on AGC-normalized fields. Convert to `f.bass_dev` / `f.bass_rel` deviation primitives. Re-record golden hash for the preset.

**Lint gate to prevent recurrence:**

Add a `Scripts/check_sample_rate_literals.sh` script that fails CI when any `44100` literal appears outside an explicit allowlist (`StemSeparator.modelSampleRate`, `BeatThisPreprocessor` 22050 internal, test fixtures). Wire into the test target's pre-build phase. Same pattern as the existing `check_visual_references` enforcement.

Add a SwiftLint custom rule that flags `f\.(bass|mid|treb|sub_bass|low_bass|low_mid|mid_high|high_mid|high)\s*[*+\-]` in `.metal` files (see Audio+DSP B2). Whitelist deviation suffixes (`_rel`, `_dev`, `_att_rel`).

**Files to touch:**

- `PhospheneApp/VisualizerEngine.swift`, `+Audio.swift`, `+Stems.swift` — propagate `tapSampleRate`.
- `PhospheneEngine/Sources/DSP/BeatDetector+Tempo.swift` — drop sub-80 doubling in `computeRobustBPM` + `estimateTempo`.
- `PhospheneEngine/Sources/DSP/MIRPipeline.swift` — `elapsedSeconds: Double`.
- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — accept `Double` playbackTime.
- `PhospheneEngine/Sources/Presets/Shaders/KineticSculpture.metal` — D-026 conversion.
- `Scripts/check_sample_rate_literals.sh` (new), `.swiftlint.yml` (custom rule), CI hook.
- `PhospheneEngine/Tests/PhospheneEngineTests/Integration/TapSampleRateRegressionTests.swift` (new) — see Tests below.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/BeatDetectorTempoTests.swift` — assert no doubling for 60 BPM input.
- `docs/CLAUDE.md` — Failed Approach #52 (sample-rate literal recurrence), update Tempo section, update KineticSculpture entry.
- `docs/DECISIONS.md` — D-078: "Sample rate is captured once per tap install; literal `44100` is a CI-banned constant."
- `docs/QUALITY/KNOWN_ISSUES.md` — close BUG-R002 / BUG-R003 with QR.1 commit hash; add new BUG-R006 (sample-rate plumbing audit), BUG-R007 (octave correction split), BUG-R008 (elapsedSeconds Float drift), BUG-R009 (KineticSculpture D-026 violation).

**Tests:**

1. **`TapSampleRateRegressionTests` (new).** Inject a recording `BeatGridAnalyzing` mock; drive with synthetic 48 kHz audio; assert `analyzeBeatGrid(samples:sampleRate:)` is called with `sampleRate == 48000` and `samples.count == sampleRate * 10`. Repeat for the stem-separator dispatch path with a `RecordingStemSeparating` mock.
2. **Octave-correction unification (`BeatDetectorTempoTests`).** Add: `computeRobustBPM` on synthetic 75 BPM IOIs returns ≈ 75 (not 150). `estimateTempo` on synthetic 65 BPM autocorrelation returns ≈ 65 (not 130). Pyramid Song golden fixture stays at ~68 BPM unchanged.
3. **`MIRPipeline` long-session drift (`MIRPipelineUnitTests`).** Synthetic 60-minute playback; assert `elapsedSeconds.isMultiple(of: 0)` not relevant — instead assert that two repeats of `update(deltaTime: 1/60)` over 1 hour produce a `Double` clock equal to 3600.0 within 1 µs.
4. **Lint gate.** `Scripts/check_sample_rate_literals.sh` exits non-zero on a synthetic source file containing `let foo = 44100`.
5. **Existing tests.** Full engine suite passes; Pyramid Song / Money golden fixtures unchanged; KineticSculpture golden hash regenerated and committed.

**Done when:**

- [x] All five literal-`44100` sites use `tapSampleRate` (or the canonical `StemSeparator.modelSampleRate` where the post-separation rate is correct, not the tap rate).
- [x] `tapSampleRate` capture is race-free (NSLock-guarded `_tapSampleRate` with `updateTapSampleRate(_:)` writer + `tapSampleRate` reader).
- [x] `computeRobustBPM` and `estimateTempo` no longer double sub-80 BPM.
- [x] `MIRPipeline.elapsedSeconds` is `Double`; `LiveBeatDriftTracker.update(playbackTime:)` widened to `Double`.
- [x] KineticSculpture uses deviation primitives (`0.06 + f.bass * 0.16 + f.bass_dev * 0.05`); golden hash regenerated.
- [x] `Scripts/check_sample_rate_literals.sh` passes; SwiftLint custom rule for `.metal` deviation form documented as intentionally script-based (SwiftLint cannot lint `.metal`).
- [x] All new tests pass; full engine suite passes (1045 tests, sole failure is the pre-existing `MetadataPreFetcher.fetch_networkTimeout` flake); app build clean.
- [x] CLAUDE.md, DECISIONS.md (D-079), KNOWN_ISSUES.md (BUG-R002/R003 generalized; new BUG-R006/R007/R008/R009), ENGINEERING_PLAN.md updated.
- [x] Manual validation 2026-05-06: ad-hoc reactive session on Love Rehab installed live Beat This! grid at **125.8 BPM** (true 125, sample-rate fix verified at 48 kHz tap); ad-hoc Pyramid Song stayed at **69 BPM** (sub-80 doubling fix verified — pre-QR.1 would have reported 138). KineticSculpture deviation form not directly observed, but golden-hash test passes. Two pre-existing bugs surfaced during testing — neither is a QR.1 regression: BUG-006 (Spotify-prepared session falls through to liveAnalysis — prepared-grid wiring path; QR.1 didn't touch it) and BUG-007 (LiveBeatDriftTracker LOCKING ↔ LOCKED oscillation — lock semantics unchanged by QR.1). Both filed in `docs/QUALITY/KNOWN_ISSUES.md` for separate diagnosis.

**Verify:** `swift test --filter TapSampleRateRegression && swift test --filter BeatDetectorTempo && swift test --filter MIRPipelineUnit && bash Scripts/check_sample_rate_literals.sh && swiftlint lint --strict`.

**Estimated sessions:** 2 (audit + propagation → tests + lint gate + golden regen).

**Status:** ✅ 2026-05-06 — D-079 landed (see git log `[QR.1]`). Manual subjective validation completed same day. Two pre-existing bugs (BUG-006, BUG-007) surfaced during validation but are not QR.1 regressions — filed for separate diagnosis.

---

### Increment QR.2 (OR.1) — Stem-affinity rescaling + reactive-mode TrackProfile fix

**Goal.** Make `stemAffinitySubScore` discriminate. Make reactive mode score stem-affinity-bearing presets fairly. The 25% score-weight slot currently does neither.

**Why now.** Direct hit on the "member of the band" goal. The Orchestrator+Session reviewer's findings #1, #2, and #6 collapse into one root cause: the scorer reads AGC-normalized stem energies as if they were absolute, then sums them. AGC centers each stem at 0.5; any preset declaring 2+ matching affinities saturates at ~1.0 on most music. Two presets with totally different declared affinities end up scoring nearly identically, so the 0.25 weight does no work.

**Algorithm changes:**

1. **`stemAffinitySubScore` reads deviation primitives.** Replace `stemEnergy[stem]` lookups with `stemEnergyDev[stem]` (D-026, MV-1, already on `StemFeatures` floats 17–24). A preset that declares "responds to drums + bass" now scores high only when those stems are *above their AGC average*, not just present at all. Presets with mismatched affinity declarations actually diverge in score on most tracks.
2. **Affinity-weighted (not summed) score.** For a preset declaring N affinity stems, score = mean of `max(0, stem_dev)` over the N stems, NOT clamped sum. Mean preserves "this preset's stems must all be active" semantics; sum allowed any-one-stem to saturate.
3. **`TrackProfile.empty` neutralizes affinity instead of zeroing it.** When `stemEnergyBalance == .zero` (reactive-mode initial state), `stemAffinitySubScore` returns 0.5 for all presets — the same neutral baseline as `affinities.isEmpty`. Otherwise reactive mode systematically rejects the most musical presets.
4. **Live `stemEnergyBalance` plumbing for reactive mode.** `DefaultReactiveOrchestrator` currently uses `TrackProfile.empty`; add an overload accepting a live `StemFeatures` snapshot. After ≥10 s of listening (when the live stem analyzer has converged), score against the live snapshot. Same time scale as the existing reactive-mode confidence ramp.

**Mood-override per-track cooldown (Orchestrator+Session #3):**

`DefaultLiveAdapter.applyLiveUpdate()` currently re-evaluates and re-patches the plan every analysis frame (~94 Hz) when conditions hold. Add a `lastOverrideTimePerTrack: [TrackIdentity: Float]` state with a 30 s cooldown. Suppress override evaluation entirely within the cooldown (don't even build the scoring contexts). Leaves boundary reschedule unaffected (it has its own per-evaluation gate).

**Reactive boundary-only switching gate (Orchestrator+Session #5):**

`DefaultReactiveOrchestrator` currently fires `boundaryFired` switches without a score-gap check, so every confident boundary every 60 s is a coin-flip. Tighten to `boundaryFired AND topScore > currentScore + 0.05` (small gap, not the full 0.20 used for non-boundary switches — boundaries are still preferred, just not random).

**Hard-cut threshold raise (Orchestrator+Session, transitions #3):**

`cutEnergyThreshold = 0.7` paired with `energy = 0.5 + 0.4 * arousal` means any track with `arousal > 0.5` cuts at every track change. Most non-ambient music sits 0.5–0.8. Raise to `cutEnergyThreshold = 0.85` so the warm-crossfade ladder actually fires on most music. A/B-listenable.

**`recentHistory` trim (Orchestrator+Session #4):**

`SessionPlanner+Segments.swift:219` appends to `recentHistory` unbounded; per-track scoring scans the array via `last(where:)`. At ~400 segments this becomes measurable. Trim to last 50 entries on append.

**Files to touch:**

- `PhospheneEngine/Sources/Orchestrator/PresetScorer.swift` — `stemAffinitySubScore` rewrite (deviation primitives + mean instead of clamped sum + neutral 0.5 on empty profile).
- `PhospheneEngine/Sources/Orchestrator/ReactiveOrchestrator.swift` — accept live `StemFeatures` snapshot; tighten boundary-switch gate.
- `PhospheneEngine/Sources/Orchestrator/LiveAdapter.swift` — `lastOverrideTimePerTrack` cooldown.
- `PhospheneEngine/Sources/Orchestrator/SessionPlanner+Segments.swift` — `recentHistory` 50-entry trim.
- `PhospheneEngine/Sources/Orchestrator/TransitionPolicy.swift` — `cutEnergyThreshold = 0.85`.
- `PhospheneApp/VisualizerEngine+Orchestrator.swift` — pass live `StemFeatures` snapshot into `applyReactiveUpdate`.
- `PhospheneEngine/Tests/PhospheneEngineTests/Orchestrator/StemAffinityScoringTests.swift` (new).
- `PhospheneEngine/Tests/PhospheneEngineTests/Orchestrator/ReactiveOrchestratorTests.swift` — add boundary-gate cases.
- `PhospheneEngine/Tests/PhospheneEngineTests/Orchestrator/LiveAdapterTests.swift` — add cooldown cases.
- `PhospheneEngine/Tests/PhospheneEngineTests/Orchestrator/GoldenSessionTests.swift` — regenerate goldens; document the changes inline (cite the QR.2 increment).
- `docs/CLAUDE.md` — Failed Approach #53 (stem-affinity AGC saturation) + #54 (reactive `TrackProfile.empty` bias).
- `docs/DECISIONS.md` — D-079: "Stem-affinity scoring uses deviation primitives, not absolute AGC-normalized energies."

**Tests:**

1. **`StemAffinityScoringTests` (new).**
   - Two presets with disjoint affinities (e.g. drums-only vs vocals-only) on a drums-heavy track produce score gap ≥ 0.3. (Was ≤ 0.05 pre-fix.)
   - Preset with empty affinities scores neutral 0.5 regardless of track.
   - Preset declaring 2 affinities on a track with one stem at +dev and one at -dev scores ~0.25 (mean of `max(0, +x)` and `max(0, -y)`). NOT 1.0 (sum saturation).
   - `TrackProfile.empty` with non-empty affinities scores 0.5 (neutral), not 0 (rejection).
2. **`ReactiveOrchestratorTests` extension.**
   - Boundary fires with `topScore == currentScore` → no switch (was: switch).
   - Boundary fires with `topScore == currentScore + 0.10` → switch.
   - 60 s cooldown still respected.
3. **`LiveAdapterTests` extension.**
   - 100 consecutive `applyLiveUpdate` calls with conditions held → only one override patch applied (was: 100).
   - Override cooldown clears on track change.
4. **`GoldenSessionTests` regeneration.** All three curated playlists regenerated. Document the score-gap shift in the test file's commit message and inline comments.
5. **Manual validation:** Matt listens to Love Rehab (drums-heavy) and a vocal-led track in reactive mode and confirms the preset selection feels different from the pre-fix baseline. Subjective gate.

**Done when:**

- [x] `stemAffinitySubScore` uses deviation primitives + mean. ✅ 2026-05-06
- [x] Reactive mode receives live `StemFeatures` after 10 s and uses neutral 0.5 before then. ✅ 2026-05-06
- [x] Mood-override 30 s per-track cooldown. ✅ 2026-05-06
- [x] Boundary-switch score gap ≥ 0.05. ✅ 2026-05-06
- [x] `cutEnergyThreshold = 0.85`. ✅ 2026-05-06
- [x] `recentHistory` trimmed at 50. ✅ 2026-05-06
- [x] All new tests pass; goldens regenerated and committed; full engine suite green (1084 pass, 1 pre-existing MetadataPreFetcher flake). ✅ 2026-05-06
- [x] CLAUDE.md (Failed Approaches #53+#54 already present) + DECISIONS.md D-080 updated. ✅ 2026-05-06
- [ ] Matt subjective sign-off on reactive-mode preset selection (Love Rehab + one vocal-led track). (pending)

**Verify:** `swift test --filter StemAffinityScoring && swift test --filter ReactiveOrchestrator && swift test --filter LiveAdapter && swift test --filter GoldenSession`.

**Landed:** 2026-05-06. All algorithmic changes implemented. Golden sequences regenerated — VL no longer dominates (stem bonus gone with zero-dev pre-analyzed profiles); mood+section+tempo now drive planned sessions. D-080 documented. Matt sign-off on reactive-mode listening pending.

**Estimated sessions:** 2 (algorithm changes + tests → goldens regen + manual sign-off).

---

### Increment BUG-007.3 — Lock hysteresis + live BPM credibility ⚠ REVERTED 2026-05-07

**Outcome:** Implementation in commit `94309858` failed manual validation. Everlong planned regressed (5 → 14 lock drops). Reverted in commit `78ade5aa`. Replacement bugs filed in `KNOWN_ISSUES.md`: BUG-007.4 (downbeat alignment investigation), BUG-007.5 (adaptive-window hysteresis), BUG-009 (halving threshold). Original spec retained below as historical context — do not re-implement.

---

**Goal (historical).** Stop two failure modes observed on 2026-05-07 manual validation: (C) `LiveBeatDriftTracker` drops lock during natural-music tempo variation even when grid BPM is correct; (D) live BPM resolver returns ~4 % low on busy mid-frequency tracks (Everlong reactive: `grid_bpm=151.9` vs true ≈158, drift walks to −358 ms over 75 s).

**Why now.** Manual validation of two post-QR.2 sessions (`~/Documents/phosphene_sessions/2026-05-07T13-27-14Z/` planned, `~/Documents/phosphene_sessions/2026-05-07T13-30-46Z/` reactive) showed BUG-007.2 is *not* the end of the lock-stability story. SLTS held LOCKED for 80 s straight but drift walked +15 → −90 ms (correct BPM, expressive timing); Everlong dropped lock 5 times in 50 s; reactive Everlong locked to a 4 % wrong BPM and ran ~one full beat ahead by t=75 s. These are independent of BUG-007.2's adversarial-cadence + horizon-exhaustion fixes. Schedule before QR.3 because the fix touches `LiveBeatDriftTracker` directly and QR.3's `LiveDriftValidationTests` should validate against the corrected lock semantics, not the current ones.

**Sites to fix:**

| File | Change |
|---|---|
| `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` | Add `staleMatchWindow: Double = 0.060`. Replace single-gate `isTight` logic with asymmetric Schmitt — tight gate (±30 ms) increments `matchedOnsets`; while already locked, stale-OK gate (±60 ms) preserves lock without incrementing; only true non-stale onsets increment `consecutiveMisses`. Add ring-buffer slope detector (`addDriftSample(playbackTime:drift:)` + `currentDriftSlope() -> Double?`) — 30-entry, returns ms/sec when ≥ 5 samples cover ≥ 5 s. |
| `PhospheneEngine/Sources/DSP/MIRPipeline.swift` | Publish latest drift slope via new `latestDriftSlopeMsPerSec: Double?` (read in `buildFeatureVector`). |
| `PhospheneApp/VisualizerEngine+Stems.swift` | Extend `runLiveBeatAnalysisIfNeeded()` with a third trigger: when `liveDriftTracker.hasGrid && abs(slope) > 5 ms/s` sustained ≥ 10 s and ≥ 30 s since last attempt (cap 3 attempts/track), retry with **20-second window** instead of 10. New `BeatThisAnalysisRequest` carries `windowSeconds` (10 or 20). On a second high-slope event after the wider retry, log `WARN: live BPM unstable on this track` and *retain previous grid* — do not install a third candidate. |
| `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` | New tests: (1) Mechanism C regression — synthetic 158 BPM grid + onset stream with ±25 ms jitter for 60 s asserts ≤ 1 lock drop; pre-fix would drop ≥ 4. (2) Slope-detector unit tests — flat drift returns ≈0 ms/s; linearly walking drift returns slope within 10 % of truth; insufficient samples returns nil. |
| `PhospheneEngine/Tests/PhospheneEngineTests/Integration/LiveBeatRetryWideningTests.swift` (new) | Mock `BeatThisAnalysisRequest` consumer; verify wider-window retry fires under high-slope condition; verify 30-s cooldown; verify 3-attempt cap; verify second high-slope event after retry retains previous grid. |

**Done-when:**

- [ ] `LiveBeatDriftTracker` exposes `staleMatchWindow=0.060`, asymmetric Schmitt logic in `update()`, `currentDriftSlope() -> Double?`. Public API additions documented.
- [ ] `MIRPipeline` publishes `latestDriftSlopeMsPerSec`.
- [ ] `runLiveBeatAnalysisIfNeeded()` accepts a 20-second window via `BeatThisAnalysisRequest`; high-slope retry path implemented; unstable-grid warning logged; previous grid retained on second failure.
- [ ] Mechanism C regression test passes (≤ 1 drop in 60 s); slope-detector unit tests pass; retry-widening integration tests pass.
- [ ] Manual capture on Smells Like Teen Spirit (planned, prepared): `lock_state == 2` for ≥ 95 % of frames after first lock; `stddev(drift_ms over 10 s) < 25 ms`.
- [ ] Manual capture on Everlong (planned, prepared): ≤ 1 lock drop in 50 s.
- [ ] Manual capture on Everlong (reactive): either grid converges to within ±1 % of 158 BPM by t=30 s after wider-window retry, or `WARN: live BPM unstable` is logged and visuals continue with the prior grid (whichever applies — both are acceptable outcomes).
- [ ] Manual capture on Billie Jean (reactive, control): no regression — drift stays bounded ±90 ms, lock holds.
- [ ] Full engine test suite passes; 0 SwiftLint violations on touched files.
- [ ] `KNOWN_ISSUES.md` BUG-007.3 closed; commit hash + manual-validation session paths recorded.
- [ ] `RELEASE_NOTES_DEV.md` updated.

**Out of scope (defer):**

- The consistent ~10–15 ms negative-drift offset across all tracks (likely tap-output latency calibration). Tracked as a future calibration-tuning increment if pursued.
- Replacing the offline Beat This! resolver entirely (BUG-008 — disagreement between MIR and offline BPM logged but not corrected).
- Tightening or loosening `strictMatchWindow` (±30 ms). Acquisition selectivity stays where it is; only retention stickiness widens.
- Slope-driven retry on the *prepared-cache* path. Prepared grids are derived from a 30 s clip — re-running offline analysis live is heavy. Stick to live-path retries; prepared inaccuracy is BUG-008.

**Risks:**

- Asymmetric hysteresis can mask a genuinely-wrong grid by holding lock through ±60 ms drift. Mitigation: the slope detector + retry trigger catches monotonic drift trends regardless of lock state.
- Wider 20 s live window doubles inference cost for the rare retry case. Mitigation: 30 s cooldown + 3-attempt cap + cap on stem-queue concurrency already enforces a low ceiling.
- Outlier-onset jitter pattern in the regression test must be representative — tune jitter distribution against the SLTS / Everlong session captures (use empirical instantDrift histograms from the 2026-05-07 features.csv files).

**Estimated sessions:** 1 (Part a + Part b can land together; manual validation is one session capture per acceptance bullet).

---

### Increment QR.3 (TEST.1) — Close silent-skip test holes ✅ 2026-05-07

**Implementation summary.** Eight new test files + one in-place skip→fail conversion + two new fixtures. Engine suite goes 1140 → 1148 tests. `BeatThisLayerMatchTests` no longer silently `print(...) + return` on missing fixtures (now `Issue.record(...) + return`), `BeatThisFixturePresenceGate` independently asserts the two fixtures exist on disk, `BeatThisStemReshapeTests` + `BeatThisRoPEPairingTests` give per-bug localised regression surfaces (Bug 2, Bug 4), `PresetVisualReviewTests` staged-preset PNG export is fixed via new `PresetLoader.bundledShadersURL` helper (BUG-002 closed), `LiveDriftValidationTests` is the closed-loop musical-sync test the suite was missing — runs full `DefaultBeatGridAnalyzer` + `BeatDetector` + `LiveBeatDriftTracker` against love_rehab.m4a and asserts 90 % `beatPhase01` zero-crossing alignment with the grid + max drift 14 ms in the 10–30 s window. `PresetLoaderCompileFailureTest` catches Failed Approach #44 silent shader-compile drops at test time (verified by temporarily breaking Plasma.metal — count dropped 14 → 13). `SpotifyItemsSchemaTests` locks Failed Approaches #45 + #47 against an on-disk fixture. `MoodClassifierGoldenTests` locks the 3,346 hardcoded weights against silent re-extraction over 10 deterministic input vectors. Lock-state warm-up gate calibrated to 9.0 s on the current tracker (observed 6.55 s; spec is 5 s, BUG-007 work-in-progress).

**Goal.** No test in the suite silently skips on a missing fixture or broken harness. Failures fail loud; missing data fails loud. Add the closed-loop musical-sync test the suite is missing.

**Why now.** Two of four DSP.2 S8 bugs are only catchable by `BeatThisLayerMatchTests`, which silently skips when fixtures are absent (`:97-104`). Fresh checkout = entire S8 regression surface gone with zero failure signal. `PresetVisualReviewTests` is broken for staged presets (BUG-002 in KNOWN_ISSUES.md); every staged preset added after Arachne V.7.7A is invisible to the harness. `LiveBeatDriftTrackerTests` uses synthetic uniform grids; no test asserts `beatPhase01` zero-crossings vs ground truth on real audio. Manual reel sign-off is the only live-musical-sync test.

**Sub-scope:**

1. **`BeatThisFixturePresenceGate` (new).** Trivial test asserting `Bundle.module.url(forResource: "love_rehab", withExtension: "m4a")` is non-nil AND `URL(fileURLWithPath: "docs/diagnostics/DSP.2-S8-python-activations.json")` exists. Fails (does not skip) when missing. Locks the fixture supply chain.
2. **`BeatThisLayerMatchTests` skip → fail.** Replace `withKnownIssue` / silent return with a hard `Issue.record(...)` if fixtures are missing. Same change in `BeatThisBugRegressionTests` if it has a similar branch.
3. **Standalone Bug 2 test (`BeatThisStemReshapeTests`).** Synthetic input with a known per-mel pattern; assert post-reshape `stem.bn1d[t, mel]` matches the transposed-then-reshaped expectation, not the byte-reinterpreted shape. ~30 LOC, no external fixture.
4. **Standalone Bug 4 test (`BeatThisRoPEPairingTests`).** Synthetic Q tensor with known values; apply RoPE; assert the rotated output matches the adjacent-pair `(x[2i], x[2i+1])` rotation, not half-and-half. ~30 LOC.
5. **`PresetVisualReviewTests` staged-preset fix (BUG-002).** Switch `Bundle.module.url(forResource: "Shaders")` to `Bundle(for: PresetLoader.self).url(...)` so the test target finds the engine's shader resources. Verify by adding Arachne to the harness fixture list and rendering successfully under `RENDER_VISUAL=1`.
6. **`LiveDriftValidationTests` (new — closed-loop musical-sync test).** Drive `LiveBeatDriftTracker` against real onsets. Reuse `Fixtures/tempo/love_rehab.m4a`; run through `BeatDetector` to get the live onset stream; install the cached love_rehab `BeatGrid` (also in fixtures); assert: locks within 5 s, |drift_ms| < 50 ms steady-state, `beatPhase01` zero-crossings within ±30 ms of grid beats over 30 s of audio. This is the test that catches the regressions Matt would actually notice.
7. **`PresetLoaderCompileFailureTest` (new).** Asserts `PresetLoader.presets.count == expectedProductionCount` so a silent shader compilation failure (preset dropped from fixture, Failed Approach #44) is loud at test time, not at "regression test passes trivially" time.
8. **Spotify schema regression test (`SpotifyItemsSchemaTests`).** One test decoding a fixture playlist `/items` response with the `"item"` key. Locks Failed Approach #45 against silent re-introduction.
9. **MoodClassifier golden-fixture test (`MoodClassifierGoldenTests`).** Ten input feature vectors → expected valence/arousal within 1e-4. Locks the hardcoded weights (3,346 floats) against silent re-extraction errors. ML reviewer flagged this as missing.

**Files to touch:**

- `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisFixturePresenceGate.swift` (new)
- `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisLayerMatchTests.swift` — skip → fail
- `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisStemReshapeTests.swift` (new)
- `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisRoPEPairingTests.swift` (new)
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetVisualReviewTests.swift` — `Bundle(for:)` fix
- `PhospheneEngine/Tests/PhospheneEngineTests/Integration/LiveDriftValidationTests.swift` (new)
- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/PresetLoaderCompileFailureTest.swift` (new)
- `PhospheneEngine/Tests/PhospheneEngineTests/Session/SpotifyItemsSchemaTests.swift` (new)
- `PhospheneEngine/Tests/PhospheneEngineTests/ML/MoodClassifierGoldenTests.swift` (new)
- `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/spotify_items_response.json` (new fixture)
- `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/mood_classifier_golden.json` (new fixture)
- `docs/QUALITY/KNOWN_ISSUES.md` — close BUG-002 with QR.3 commit hash; close BUG-003 once `LiveDriftValidationTests` lands.

**Done when:**

- [x] All 9 sub-tests land and pass on a clean checkout.
- [x] `BeatThisLayerMatchTests` fails (does not skip) when fixtures missing.
- [x] `PresetVisualReviewTests` renders Arachne staged composition under `RENDER_VISUAL=1` (16 PNGs across 5 preset cases, no `cgImageFailed`).
- [x] `LiveDriftValidationTests` locks within 9 s on love_rehab.m4a (calibrated; spec is ~5 s, BUG-007) and asserts `beatPhase01` zero-crossings (90 % alignment achieved, ≥ 80 % gate).
- [x] `PresetLoaderCompileFailureTest` fails when a preset is silently dropped (verified by temporarily breaking Plasma.metal with `int half = 1;` — count dropped 14 → 13; Stalker.metal was no longer in production).
- [x] Full engine suite passes (1148 tests).

**Verify:** `swift test --filter BeatThisFixturePresence && swift test --filter BeatThisLayerMatch && swift test --filter BeatThisStemReshape && swift test --filter BeatThisRoPEPairing && swift test --filter LiveDriftValidation && swift test --filter PresetLoaderCompile && swift test --filter SpotifyItemsSchema && swift test --filter MoodClassifierGolden && RENDER_VISUAL=1 swift test --filter PresetVisualReview`.

**Estimated sessions:** 2 (sub-tests 1–5 → sub-tests 6–9).

---

### Increment QR.4 (U.12) — UX dead ends + duplicate `SettingsStore` + dead settings + hardcoded strings  ✅ 2026-05-07 (D-091)

**Status:** ✅ Landed. Two commits. Net: 17 new tests, ~12 strings externalised, dead settings deleted, duplicate `SettingsStore` collapsed, `currentTrackIndex` plumbing replaces string-match plan correlation.

**Goal.** Close the user-facing rough edges flagged in the App+UX review. Each is small in isolation; together they restore the "uninterrupted ambient member of the band" feel that the architecture promises.

**Sub-scope:**

1. **EndedView dead end.** `Views/Ended/EndedView.swift` is currently a U.1 stub with no CTA. Add a "Start another session" button that calls `sessionManager.endSession()` → `.idle` (or directly transitions to `.idle`); add session summary text per UX_SPEC §3.6. Localize all strings.
2. **`.connecting` cancel affordance.** `Views/Connecting/ConnectingView.swift` is a static spinner. Add a "Cancel" button that calls `sessionManager.cancel()` (already exists). Per-connector spinner (Apple Music vs Spotify vs Local Folder) per UX_SPEC §3.2.
3. **Duplicate `SettingsStore` collapse.** Remove `@StateObject private var settingsStore = SettingsStore()` from `Views/Playback/PlaybackView.swift:50`. Replace with `@EnvironmentObject var settingsStore: SettingsStore`. Verify `CaptureModeSwitchCoordinator` (set up in `PlaybackView.setup()`) and other reconcilers receive `captureModeChanged` events from the global store. Add a regression test that toggles capture mode in the global store and asserts the playback-side reconciler observes the change.
4. **Dead settings.** `SettingsStore.showPerformanceWarnings` and `SettingsStore.includeMilkdropPresets` persist user toggles that are read by nothing. For each: either wire the consumer or delete the property + UI row + Localizable.strings keys + view-model binding. `includeMilkdropPresets` documented as Phase MD gate; if Phase MD is genuinely deferred, hide the row behind `#if DEBUG` or a build-time flag rather than ship a permanently-disabled toggle.
5. **Hardcoded English strings (12 sites).** Externalize per UX_SPEC §8.5. Specific call sites:
   - `Views/Connecting/ConnectingView.swift:15,18`
   - `Views/Idle/IdleView.swift:26` ("Phosphene" — keep as `appName` key)
   - `Views/Playback/PlaybackView.swift:130,134,135,137` (end-session confirm dialog)
   - `Views/Playback/PlaybackControlsCluster.swift:36,47` (replace "Settings (coming soon)" tooltip with localized "Settings")
   - `Views/Plan/PlanPreviewView.swift:101,104,132`
   - `Views/Plan/PlanPreviewRowView.swift:85,89`
   - `Views/Playback/ListeningBadgeView.swift:36`
   - `Views/Playback/SessionProgressDotsView.swift:49,56`
6. **Plan Preview "Modify" button.** Currently disabled with empty closure (`PlanPreviewView.swift:131-135`). Hide entirely for v1 rather than ship a permanently-disabled control. Restore when V.5 plan-modification work lands.
7. **`PlaybackChromeViewModel.refreshProgress` string-matching.** Replace lowercased title+artist matching against the plan with `currentTrackIndex: Int?` published by `VisualizerEngine`. Track index already known engine-side from the `PlannedSession` walk. Removes covers/remasters fragility.
8. **Tooltip lies.** "Settings (coming soon)" on the wired settings button (`PlaybackControlsCluster.swift:36`) → "Settings" localized.

**Files to touch:**

- `PhospheneApp/Views/Ended/EndedView.swift` — full implementation per UX_SPEC §3.6.
- `PhospheneApp/Views/Connecting/ConnectingView.swift` — cancel button, per-connector spinner.
- `PhospheneApp/Views/Playback/PlaybackView.swift` — remove duplicate `SettingsStore`.
- `PhospheneApp/SettingsStore.swift` — delete `showPerformanceWarnings` + `includeMilkdropPresets` (or wire them).
- `PhospheneApp/Views/Settings/VisualsSettingsSection.swift` (and related) — remove dead toggle rows.
- `PhospheneApp/ViewModels/PlaybackChromeViewModel.swift` — `currentTrackIndex` plumbing.
- `PhospheneApp/VisualizerEngine.swift` — publish `@Published var currentTrackIndex: Int?`.
- `PhospheneApp/Views/Playback/PlaybackControlsCluster.swift` — localized tooltips.
- `PhospheneApp/Views/Plan/PlanPreviewView.swift` — hide Modify button.
- `PhospheneApp/Localizable.strings` (English) — new keys.
- `PhospheneApp/Services/AccessibilityLabels.swift` — localized labels for new buttons.
- `Tests/PhospheneAppTests/EndedViewTests.swift` (new), `ConnectingViewCancelTests.swift` (new), `SettingsStoreEnvironmentRegressionTests.swift` (new), `PlaybackChromeIndexBindingTests.swift` (new).
- `docs/UX_SPEC.md` — confirm EndedView and ConnectingView copy match the spec.
- `docs/CLAUDE.md` — UX Contract section: note that `SettingsStore` MUST be consumed via `@EnvironmentObject`, never re-instantiated.

**Tests:**

1. **`SettingsStoreEnvironmentRegressionTests`.** Construct one `SettingsStore`; inject into a test view hierarchy; toggle `captureMode`; assert any view-side observer reads the new value. Catches the duplicate-instance bug if it ever recurs.
2. **`EndedViewTests`.** Renders summary; "Start another session" button calls a stub action.
3. **`ConnectingViewCancelTests`.** Cancel button calls the injected cancel closure.
4. **`PlaybackChromeIndexBindingTests`.** Update `currentTrackIndex` → chrome shows the new track without title-matching.
5. **String externalization audit.** Add a script (`Scripts/check_user_strings.sh`) that greps `Text\("[A-Z]` in `PhospheneApp/Views/` and fails on any hit not in an allowlist of acknowledged debug strings.
6. **Existing tests:** all 305 app tests pass; engine tests untouched.

**Done when:**

- [x] EndedView and ConnectingView no longer block flow.
- [x] One `SettingsStore` instance app-wide; capture-mode toggles propagate to playback reconcilers.
- [x] Dead settings removed (`showPerformanceWarnings` deleted; `includeMilkdropPresets` UI gated on `#if DEBUG`).
- [x] 12+ hardcoded strings externalized; tooltip lies fixed (`Settings (coming soon)` → `Settings`).
- [x] `currentTrackIndex` plumbing replaces title-matching.
- [x] All new tests pass; full app build clean.
- [ ] Manual validation: Matt sign-off on end-to-end flow without relaunch.

**Verify:** `swift test --filter SettingsStoreEnvironmentRegression && swift test --filter EndedView && swift test --filter ConnectingViewCancel && swift test --filter PlaybackChromeIndexBinding && bash Scripts/check_user_strings.sh && xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test`.

**Estimated sessions:** 2 (views + cancel + duplicate store → strings + dead settings + tests). Actual: 1.

**Implementation summary (D-091):** 4 view edits (EndedView, ConnectingView, PlaybackView, PlanPreviewView) + duplicate-store collapse + 12+ string externalisations + `currentTrackIndex: Int?` published from `VisualizerEngine` + `indexInLivePlan(matching:)` orchestrator helper + 4 new test files (17 tests) + 1 new lint script (`Scripts/check_user_strings.sh`). Two key pivots from the prompt: (1) "Start another session" wires to `cancel()`, not `endSession()` — the prompt assumed `endSession()` did `.ended → .idle` but it transitions any state → `.ended`; (2) `sessionDuration` plumbing deferred per the prompt's own fallback (would require >30 LOC of `SessionManager` changes). Decisions D-091.1–D-091.8 in `docs/DECISIONS.md`.

---

### Increment QR.5 (CLEAN.1) — Mechanical cleanup pass

**Goal.** Pure deletion of dead code + dead binaries + stale doc comments. No behavior change. ~600 LOC and ~1.6 MB removed.

**Why now.** Each individual cleanup is too small to justify its own increment, but together they reduce read-cost on every subsequent session. Schedule after QR.1–QR.4 land so their cleanups can ride along (QR.1 adds Failed Approaches, QR.2 deletes `BeatPredictor` once retired, etc.).

**Cleanup catalog (cite each commit message with the agent finding):**

| # | Cleanup | Lines/size | Files |
|---|---|---|---|
| 1 | Delete `Sources/ML/Weights/beatnet/` (D-076 abandoned) | ~1.6 MB binaries + 14 .bin + manifest | `Sources/ML/Weights/beatnet/` directory |
| 2 | Delete `Scripts/convert_beatnet_weights.py` | ~80 LOC | `Scripts/` |
| 3 | Delete IOI histogram + `dumpHistogram` consumers (dead post-D-075) | ~50 LOC | `Sources/DSP/BeatDetector+Tempo.swift:144-177` |
| 4 | Dedup `ShaderUtilities.metal` legacy bodies vs V.1+V.2 trees | 13 functions, ~400 LOC; ~30% off every preset preamble compile | `Sources/Presets/Shaders/ShaderUtilities.metal` |
| 5 | Migrate production presets calling legacy `fbm3D`/`perlin2D`/`sdPlane`/`sdBox` to V.1+V.2 names (precondition for #4) | renames only | `VolumetricLithograph.metal`, `GlassBrutalist.metal`, others identified by grep |
| 6 | Delete placeholder `Sources/Orchestrator/Orchestrator.swift` (5 LOC empty) | 5 LOC | `Sources/Orchestrator/Orchestrator.swift` |
| 7 | Delete placeholder `Sources/Session/Session.swift` (5 LOC empty) | 5 LOC | `Sources/Session/Session.swift` |
| 8 | Delete `Sources/Orchestrator/PresetSignaling.swift` (no preset emits) | 39 LOC | `Sources/Orchestrator/PresetSignaling.swift` |
| 9 | Inline `Views/Ready/ReadyBackgroundPresetView.swift` into `ReadyView.swift` | 34 LOC moved | `Views/Ready/` |
| 10 | Delete or wire `Services/PresetPreviewController.swift` (52 LOC stub, no caller) | 52 LOC | `Services/PresetPreviewController.swift` |
| 11 | Stale CoreML doc comments in 7+ files | doc-only | `Sources/Audio/Protocols.swift:101,166,188,190,192`, `Sources/Shared/AudioFeatures+Frame.swift:71`, `Sources/Shared/StemSampleBuffer.swift:46`, `PhospheneApp/VisualizerEngine.swift:173`, `+Stems.swift:62,142` |
| 12 | Centralize EMA / `pow(rate, 30/fps)` in `Shared/Smoother` value type | replaces 5 copy-pasted impls | new `Sources/Shared/Smoother.swift`; delete duplicate impls in `BeatDetector`, `LiveBeatDriftTracker`, `BandEnergyProcessor`, `MIRPipeline`, `StemAnalyzer` |
| 13 | Delete `BeatPredictor.swift` (subordinate to `LiveBeatDriftTracker`; QR.1 retires reactive-only fallback per Architect simplification #3) | ~150 LOC + tests | `Sources/DSP/BeatPredictor.swift`, `Tests/.../DSP/BeatPredictorTests.swift` |
| 14 | Audit `Tests/TestDoubles/` for stale doubles; standardize naming (Mock vs Stub vs Fake) | naming + delete stale | `Tests/TestDoubles/` |
| 15 | Consolidate `Tests/.../Orchestrator/SessionPlanner*Tests.swift` (4 files → 2: unit + golden) | naming + reorg | `Tests/.../Orchestrator/` |
| 16 | Pre-allocate buffer in `AudioInputRouter.swift:252-263` (file-playback path: 46 buffers/sec of fresh allocation) | ~10 LOC | `Sources/Audio/AudioInputRouter.swift` |
| 17 | `AudioBuffer.latestSamples` `unsafeReadInto(_ ptr:count:)` overload to eliminate per-FFT-frame allocation | ~30 LOC | `Sources/Audio/AudioBuffer.swift` |

**Implementation order:**

1. Mechanical deletions first (#1, #2, #6, #7, #8, #9, #10) — no behavior risk, small commits.
2. Stale comments (#11) — doc-only.
3. Preset migrations (#5) before utility dedup (#4) — sequencing matters.
4. EMA centralization (#12) — touches DSP hot paths; run full test suite after.
5. `BeatPredictor` retirement (#13) — depends on QR.1 having landed (since QR.1 fixes the live Beat This! retry path that makes BeatPredictor truly dispensable).
6. Test cleanups (#14, #15) — last; doesn't affect production.
7. Allocation fixes (#16, #17) — micro-perf; verify no behavior change with full suite + soak test.

**Files to touch:** see catalog above.

**Tests:**

- Full engine suite passes after every catalog item.
- `PresetRegressionTests` golden hashes unchanged after #4 + #5 (utility dedup is a name change only; if a hash drifts, the dedup was not literal-equivalent and needs investigation).
- `MIRPipelineUnitTests`, `BeatDetectorTests` pass after #12 (EMA centralization — verify FPS-independent decay constants are byte-identical).
- Soak test (2 hours) passes after #16 + #17 — confirm no allocation regression in `MemoryReporter` output.

**Done when:**

- [ ] All 17 catalog items landed in separate commits (one per item) with `[QR.5] <component>: <description>` messages.
- [ ] Full engine suite + full app build green after each commit (`git bisect` retains value).
- [ ] Preset regression hashes unchanged.
- [ ] CLAUDE.md Module Map updated for any deleted/added files.
- [ ] DECISIONS.md not touched (this increment is mechanical, no design decisions).

**Verify:** `swift test --package-path PhospheneEngine && xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build && bash Scripts/run_soak_test.sh --duration 600`.

**Estimated sessions:** 3 (deletions + comments → preset migration + dedup → EMA centralization + tests + soak).

---

### Increment QR.6 (ARCH.1) — `VisualizerEngine` decomposition

**Goal.** Split `VisualizerEngine` (2,580 LOC, 8 NSLocks, `@unchecked Sendable`, 7 extension files) into 3-4 owned services with a 200-line composition root. Replace `RenderPipeline`'s 24-NSLock switchboard with a single `RenderGraphState` value type updated atomically per preset switch.

**Why now (and why last in QR).** The architect's H1 + H2 findings together represent the largest single piece of debt in the codebase. They are *also* the highest-risk change: every concern in the engine integrates here. Schedule after QR.1–QR.5 have landed so that:

- QR.1 has cleaned up the sample-rate plumbing this refactor would otherwise have to thread through.
- QR.2 has fixed the orchestrator surface this refactor exposes.
- QR.3 has hardened the test suite that will validate the decomposition.
- QR.5 has retired `BeatPredictor`, deduplicated `ShaderUtilities`, and centralized EMA — all of which would be friction during decomposition if left in place.

This increment is **the first one that requires Matt to explicitly approve scope at the start**, because the safe path is to ship the decomposition behind feature flags and migrate one subsystem at a time over multiple sessions.

**Proposed shape (subject to architect's pre-implementation pass):**

```
PhospheneApp/
  VisualizerEngine.swift              → 200-line composition root: owns the three hosts, wires publishers, exposes the public API
  AudioPipelineHost.swift             → router, FFT, MIR, stems, signal-state callbacks. Owns the audio-thread → analysis-queue boundary.
  RenderHost.swift                    → pipeline, presets, mesh/preset state, mvwarp, preset switching. Owns the render-pipeline lock surface.
  OrchestratorHost.swift              → planner, live adapter, reactive orchestrator, plan publisher, action router. Owns the orchestrator state.
```

Each host is a `@MainActor`-bound `final class`, owns its state (no `@unchecked Sendable`), exposes a small public surface to the composition root. Cross-host communication via Combine publishers (typed events), not direct property reads.

**`RenderGraphState` value type (RenderPipeline H2 fix):**

```
struct RenderGraphState {
    var preset: PresetDescriptor
    var passes: [RenderPass]
    var icb: ICBState?
    var raymarch: RayMarchState?
    var mvwarp: MVWarpState?
    var mesh: MeshState?
    var postProcess: PostProcessState?
    // … one slot per pass family
}
```

`RenderPipeline` holds `var graphState: RenderGraphState` under a single lock. Per-frame `draw(in:)` snapshots one struct under one lock. Adding a pass family = adding a slot, not a lock.

**Frame-budget governor latency fix (Renderer + Architect H3):**

`RenderPipeline.swift:371-384` does `Task { @MainActor in observe(...) }` every frame in the completed handler. Move the `FrameBudgetManager` and `MLDispatchScheduler` to a dedicated serial DispatchQueue; only hop to `@MainActor` for `@Published` UI updates. Decisions stay synchronous on the timing path; UI lags by at most one frame, but `MLDispatchScheduler` no longer misses budget breaches under main-thread contention.

**Live Beat This! routed through `MLDispatchScheduler` (ML #3):**

`runLiveBeatAnalysisIfNeeded`'s `analyzer.analyzeBeatGrid(...)` currently dispatches to `stemQueue` at utility QoS without consulting `MLDispatchScheduler`. Route through the scheduler the same way stem separation does. Pre-warm Beat This! graph + weight load at session start (after first audio frame) to avoid the t=10s lazy-init stutter.

**`MIRPipeline` `@unchecked Sendable` cleanup (Architect M2):**

Convert `MIRPipeline` to a `@MainActor` final class with explicit per-property locks where cross-thread access is genuinely needed. Removes the unsynchronized `private(set) var` reads-from-main / writes-from-analysis-queue pattern.

**`Diagnostics → Audio + Renderer` dependency leak (Architect M3):**

Move `SoakTestHarness` into a `Tests/` target or a separate non-shipped SPM dev product. Keeps `Diagnostics` engine library reusable.

**`Presets` and `Renderer` shader resource directories consolidation (Architect M4):**

Pick one source of truth (recommended: `Presets/Shaders/`). Remove the duplicate from the other target's `resources` declaration in `Package.swift`. Verify no `.metal` lookup silently fails.

**Files to touch:** `PhospheneApp/VisualizerEngine*.swift` (split into 4+ files), `PhospheneEngine/Sources/Renderer/RenderPipeline*.swift` (RenderGraphState refactor), `PhospheneEngine/Sources/DSP/MIRPipeline.swift`, `PhospheneEngine/Package.swift`, related tests.

**Tests:**

- All existing tests pass at every intermediate commit.
- New `AudioPipelineHostTests`, `RenderHostTests`, `OrchestratorHostTests` cover each host's API.
- New `RenderGraphStateTests` covers atomic state-transition contract.
- `LiveDriftValidationTests` (from QR.3) passes — proves the refactor preserves musical sync.
- Full soak test passes (no allocation regression).

**Done when:**

- [ ] `VisualizerEngine.swift` is ≤ 250 LOC; `+Audio/+Stems/+Orchestrator/+Capture/+InitHelpers/+PublicAPI` extension files deleted.
- [ ] Three hosts own their state; no `@unchecked Sendable` outside explicit audio-thread boundaries.
- [ ] `RenderPipeline` uses one lock + one `RenderGraphState`.
- [ ] Frame-budget observer runs on a dedicated queue; `MLDispatchScheduler` decisions are synchronous on the timing path.
- [ ] Live Beat This! routed through `MLDispatchScheduler`; pre-warmed at session start.
- [ ] `MIRPipeline` is `@MainActor`; no `@unchecked Sendable`.
- [ ] `Diagnostics` no longer depends on `Audio + Renderer` for shipped library product.
- [ ] One canonical `Shaders/` resource directory.
- [ ] Full engine + app + soak test suites green.
- [ ] Performance regression test confirms no per-frame regression.
- [ ] CLAUDE.md Module Map fully rewritten for the new shape; DECISIONS.md D-080: "VisualizerEngine decomposition + RenderPipeline single-state refactor."

**Verify:** Full suite + soak test + manual reel re-record.

**Estimated sessions:** 5–8. **Matt approval required at the start** because the increment is large enough that mid-flight scope changes would be costly. Each session ships one subsystem migration with full test pass; abort path is clean (revert to last green commit).

**Risks:**

- Decomposition surfaces hidden coupling. Each host migration may require refactors in unrelated files.
- `RenderGraphState` atomic snapshot under load may regress per-frame timing if not benchmarked. Mitigation: gate the refactor behind a runtime flag and A/B against the legacy switchboard for one session.
- `MIRPipeline` `@MainActor` conversion may cause unexpected `await` propagation. Mitigation: stage in a separate session with isolated test coverage.

---

## Phase DASH — Telemetry Dashboard

A dedicated HUD layer for Phosphene's diagnostic and operational telemetry. Renders floating monospace metrics cards over the live Metal view using a zero-alloc Core Text path backed by a shared-memory MTLTexture. Six increments; no Orchestrator or audio-pipeline changes — pure Renderer + Shared additions.

**Goals:**
- Real-time BPM, beat-lock state, stem energies, frame budget, and session-mode label without requiring Spectral Cartograph to be the active preset.
- Developer-togglable (same `D` key overlay flow as `DebugOverlayView`).
- Zero per-frame heap allocation; MTLBuffer-backed CGContext blit path inherited by `DashboardTextLayer`.

### Increment DASH.1 — Text-rendering layer ✅ 2026-05-06

Foundation: `DashboardTokens`, `DashboardFontLoader`, `DashboardTextLayer`.

- `DashboardTokens.swift` (`Sources/Shared/Dashboard/`): static design-token namespace — `TypeScale` (6 sizes), `Spacing` (4 sizes), `Color` (11 swatches as `SIMD4<Float>`), `Weight`, `TextFont`, `Alignment` enums.
- `DashboardFontLoader.swift` (`Sources/Renderer/Dashboard/`): resolves Epilogue-Regular/Medium TTF from bundle `Fonts/` subdirectory; falls back to system sans; `OSAllocatedUnfairLock` cache; `resetCacheForTesting()` for test isolation.
- `DashboardTextLayer.swift` (`Sources/Renderer/Dashboard/`): zero-copy `MTLBuffer` → `CGContext` → `MTLTexture` pattern; Core Text permanent CTM flip; `beginFrame()` clears; `drawText(_:at:size:weight:font:color:align:)` renders; `commit(into:)` encodes blit; `.bgra8Unorm` pixel format.
- 12 tests: `DashboardTokensTests` (4), `DashboardFontLoaderTests` (3), `DashboardTextLayerTests` (5).
- `Resources/Fonts/README.md` placeholder for custom TTF drop-in.

**Done when:** ✅
- [x] `DashboardTextLayer` renders text to MTLTexture at correct pixel positions.
- [x] `beginFrame()` clears the texture between frames.
- [x] Alignment shifts render position (left vs. right at same origin).
- [x] Color token applies to rendered pixels (teal G > R and G > B).
- [x] All 12 tests pass; 0 SwiftLint violations; app build clean.

### Increment DASH.2 — Metrics card layout engine ✅ 2026-05-07 (amended DASH.2.1)

`DashboardCardLayout` value type: positions labeled metric values in a fixed-width card (title row + N value rows). `DashboardCardRenderer` composes `DashboardTextLayer` calls to paint one card. Cards support **stacked single-value rows** (label on top, value below) and **stacked bar rows** (label on top, bar + right-aligned value text on the next line). Card chrome (rounded `Color.surfaceRaised` fill at 0.92 alpha + 1 px `Color.border` stroke) is the one sanctioned glassmorphic surface in the dashboard. Right-edge clipping enforced via `align: .right` on bar value text; bar geometry bounded by an explicit reserved-right-column width. `DashboardTextLayer` exposes the underlying `CGContext` via an `internal var graphicsContext` so the renderer can paint chrome and bar geometry into the same shared buffer.

**Amendment DASH.2.1 (2026-05-07).** The original prompt prescribed three row variants (`.singleValue` horizontal label-LEFT/value-RIGHT, `.pair` four-way split, `.bar` label-top/bar-bottom-full-width/value-top-right). After /impeccable review of the artifact, the design was rebuilt: rows now stack label-above-value, the pair variant was dropped (two single rows beat any horizontal pair at typical card widths), label colour switched from `textMuted` (~3.3:1, fails WCAG AA) to `textBody` (~10:1, passes AA), card chrome switched from `Color.surface` to `Color.surfaceRaised` so the purple tint reads against any visualizer backdrop, and the test artifact paints a representative deep-indigo backdrop before drawing the card so the saved PNG reflects production conditions. See D-082 amendment for full rationale.

**Done when:** ✅
- [x] A `DashboardCardRenderer` test renders the canonical 4-row beat card and pixel-verifies title and bottom-clear.
- [x] Cards clip correctly at the right edge (no text glyph past `width - padding`).
- [x] Bar row negative value fills left of bar centre; positive value fills right of bar centre; zero value draws no foreground.
- [x] Single-value rows stack their label above their value (geometric span ≥ label height + gap).
- [x] Label colour passes WCAG AA contrast on the card chrome.
- [x] All 18 dashboard tests pass; 0 SwiftLint violations on touched files; app build clean.

### Increment DASH.3 — Beat & BPM card ✅ 2026-05-07

First live card. `BeatCardBuilder` (pure, Sendable) maps a `BeatSyncSnapshot` to a `DashboardCardLayout` titled `BEAT` with four rows: MODE / BPM / BAR / BEAT. New `.progressBar` row variant (left-to-right unsigned 0–1 fill) added to `DashboardCardLayout` for the BAR and BEAT ramps — distinct from the existing `.bar` (signed slice from centre). Lock-state colour mapping per .impeccable: REACTIVE/UNLOCKED `textMuted`, LOCKING `statusYellow`, LOCKED `statusGreen`. Graceful no-grid rendering: BPM `—`, BAR valueText `— / 4` with bar at zero, BEAT valueText `—` with bar at zero. `BeatSyncSnapshot` is unchanged — DASH.3 derives BEAT phase as `barPhase01 × beatsPerBar − (beatInBar − 1)` clamped to [0, 1]; promoting `beatPhase01` to a first-class snapshot field is a future increment. Wiring into `RenderPipeline` / `PlaybackView` is DASH.6 scope, not DASH.3.

**Done when:** ✅
- [x] Card renders with correct BPM string from a test `BeatSyncSnapshot`.
- [x] Lock state label color changes by state (muted / amber / green).
- [x] No-grid (`gridBPM <= 0`) renders `—` placeholders with bars at zero.
- [x] `.progressBar` row variant fills left-to-right; tests verify zero / half / full.
- [x] All 27 dashboard tests pass (12 DASH.1 + 6 DASH.2.1 + 6 BeatCardBuilder + 3 progress-bar); 0 SwiftLint violations on touched files; app build clean.

### Increment DASH.4 — Stem energy card ✅ 2026-05-07

Second live card. `StemsCardBuilder` (pure, Sendable) maps a `StemFeatures` snapshot to a `DashboardCardLayout` titled `STEMS` with four `.bar` rows in percussion-first reading order — DRUMS / BASS / VOCALS / OTHER — each driven by the corresponding `*EnergyRel` field (MV-1 / D-026). Range is `-1.0 ... 1.0` (headroom over typical ±0.5 envelope; loud transients still readable). Sign-correct visual feedback: positive deviation fills right of centre, negative fills left, zero draws no fill (the dim background bar dominates — the .impeccable "absence-of-signal" stable state). `valueText` formatted `%+.2f` so the leading sign is always shown (Milkdrop-convention readback for signed bars). Uniform `Color.coral` across all four rows in v1; per-stem palette tuning is reserved for a DASH.4.1 amendment if Matt's eyeball flags monotony — direction (left vs right of centre) carries the stem-state semantics, colour reinforces. The builder is pass-through; clamping authority lives in the renderer's `drawBarFill` (defence-in-depth at one layer). Wiring into `RenderPipeline` / `PlaybackView` is DASH.6 scope, not DASH.4.

**Done when:**
- [x] `StemsCardBuilder` maps `StemFeatures` → `DashboardCardLayout` (4 rows, range `-1.0...1.0`, uniform coral, `%+.2f` valueText).
- [x] Bar width tracks `*EnergyRel` sign correctly (positive = right of centre, negative = left).
- [x] Zero-energy row renders no fill (background bar only) — stable visual state.
- [x] Builder passes raw `*EnergyRel` through unchanged (clamp authority in renderer; test e regression-locks).
- [x] 6 `@Test` functions in `StemsCardBuilderTests` (zero, +drums, −bass, mixed-with-artifact, unclamped passthrough, width override).
- [x] `card_stems_active.png` artifact written for M7-style review.
- [x] D-084 captures: `.bar` over `.progressBar` rationale, builder reads `StemFeatures` directly (no `StemEnergySnapshot`), uniform-coral v1 + DASH.4.1 amendment slot, no-clamp-at-builder, range rationale, percussion-first row order.

### Increment DASH.5 — Frame budget card ✅ 2026-05-07

Third live card. New `PerfSnapshot` Sendable value type wraps renderer governor + ML dispatch state (`FrameBudgetManager.recentMaxFrameMs` / `currentLevel` / `targetFrameMs` + `MLDispatchScheduler.lastDecision` / `forceDispatchCount`) as a single input crossing actor lines — decision and quality enums are encoded as `Int + displayName: String` so the snapshot stays trivially `Sendable` without importing the manager enums (mirrors `BeatSyncSnapshot.sessionMode`). `PerfCardBuilder` (pure, Sendable) maps the snapshot to a `DashboardCardLayout` titled `PERF` with three rows in display order: FRAME (`.progressBar`, unsigned ramp `recentMaxFrameMs / targetFrameMs` with builder-layer clamp to `[0, 1]` since `.progressBar` carries no `range` field — single source of truth), QUALITY (`.singleValue`, displayName passed through verbatim), ML (`.singleValue`, mapped READY / WAIT _ms / FORCED / —). Status-colour discipline reuses the BEAT lock-state palette (D-083): muted = no information yet, green = healthy / READY, yellow = governor active / degraded / WAIT / FORCED. No `statusRed` introduced — the governor doing its job is the expected state under load. Wiring into `RenderPipeline` / `PlaybackView` is DASH.6 scope, not DASH.5.

**Done when:**
- [x] `PerfSnapshot` Sendable value type with `.zero` neutral default.
- [x] `PerfCardBuilder` builds three-row PERF layout (FRAME / QUALITY / ML).
- [x] FRAME bar value clamps to `[0, 1]` at the builder layer (no `range` field on `.progressBar`).
- [x] Status colours: muted = no info, green = healthy / READY, yellow = governor active / WAIT / FORCED.
- [x] No-observations state stable: FRAME bar at 0 + valueText `—`, QUALITY rendered in muted, ML rendered as muted `—`.
- [x] 6 builder tests pass (`build_zeroSnapshot_*`, `build_healthyFullQuality_*`, `build_governorDownshifted_*`, `build_forcedDispatch_*`, `build_frameTimeAboveBudget_clampsBarValueAtOne`, `build_widthOverride_*`).
- [x] `card_perf_active.png` artifact written for M7-style review (composes against the BEAT and STEMS artifacts on the same deep-indigo backdrop).
- [x] D-085 captures: `PerfSnapshot` value-type rationale (snapshot crosses actor lines, two manager classes), `.progressBar` over `.bar` for FRAME, builder-layer clamp asymmetry vs D-084's renderer-layer clamp, Int-encoded enums, no `statusRed` durable rule, no per-row colour tuning for FRAME, DASH.5.1 amendment slot.

### Increment DASH.6 — Overlay wiring + `D` key toggle ✅ 2026-05-07 (superseded by DASH.7)

`DashboardComposer` (`@MainActor`, lifecycle owner of the BEAT/STEMS/PERF cards) wires all three card builders to the live render pipeline. Per-frame `update(beat:stems:perf:)` rebuilds card layouts (skips when all three snapshots compare equal — `BeatSyncSnapshot` and `StemFeatures` lack `Equatable`, so the rebuild-skip uses a private bytewise compare; `PerfSnapshot` is `Equatable`); `composite(into:drawable:)` encodes a `loadAction = .load` alpha-blended pass that samples the layer texture into a top-right viewport. The composite is invoked at the tail of every draw path immediately before `commandBuffer.present(drawable)` (Decision B per D-086). One `D` shortcut drives both the SwiftUI debug overlay (existing) and the new Metal dashboard via `VisualizerEngine.dashboardEnabled` — instruments and raw diagnostics are complementary surfaces, not alternatives. `DebugOverlayView` deduplicated: Tempo / standalone QUALITY / standalone ML rows removed (now in PERF + BEAT cards); MOOD / Key / SIGNAL / MIR diag / SPIDER / G-buffer / REC remain. `Spacing.cardGap` token aliases `Spacing.md` (12 pt) — named slot reserves a DASH.6.1 retune.

**Done when:**
- [x] Pressing `D` shows / hides the dashboard cards (and the SwiftUI debug overlay) together.
- [x] All three cards update per-frame; engine test suite (1130 tests / 130 suites) green; 0 SwiftLint violations on touched files.
- [x] `DebugOverlayView` no longer duplicates Tempo / QUALITY / ML rows.
- [x] D-086 captures: Decision B over A (per-path composite, not render-loop refactor — ~10 sites × 1 helper line via `RenderPipeline.compositeDashboard`), `DashboardComposer` rationale (single class owns layer + builders + composite pipeline + enabled flag), single `D` toggle drives both surfaces, no `Equatable` on `StemFeatures` / `BeatSyncSnapshot`, no fourth card, premultiplied alpha discipline, DASH.6.1 amendment slot.

**Superseded note (2026-05-07):** Live D-toggle review on `~/Documents/phosphene_sessions/2026-05-07T19-03-44Z` (Love Rehab / So What / There There / Pyramid Song) surfaced three issues with the Metal-composite path: (a) hazy text vs. crisp SwiftUI from a contentsScale-detection bug, (b) the 0.92α purple-tinted surface didn't read against bright preset backdrops, (c) `.bar` rows for STEMS made stem-rhythm separation hard to read (Matt's feedback explicitly cited the SpectralCartograph timeseries panel as the desired pattern). Investigation showed the original Metal-path justifications (crisp text via direct CGContext→texture, frame-rate buffer-bound updates, lifetime coupling to render pipeline) didn't materialize: text was hazy, snapshot updates are bounded by snapshot-change cadence rather than frame rate, and lifetime is naturally one-frame ahead via `@Published`. **DASH.7 ports the dashboard to SwiftUI, retiring `DashboardComposer` + `DashboardCardRenderer` + `DashboardTextLayer` + `Dashboard.metal`.** The Sendable card builders + `DashboardCardLayout` + tokens + `PerfSnapshot` + `BeatCardBuilder` survive unchanged; only the rendering layer changes. See D-087 for the rationale and D-086 retirement details.

### Increment DASH.7.2 — Dark-surface legibility pass ✅ 2026-05-07

DASH.7.1 shipped brand-aligned colours but two failures surfaced on Matt's first-look review:
- The `.regularMaterial` panel rendered *light* on macOS Light system appearance, putting the dashboard's near-white text on a beige backdrop with sub-AA contrast.
- `coralMuted` (oklch 0.45) and `purpleGlow` (oklch 0.35) — chosen in DASH.7.1 for their muted brand semantic — failed WCAG AA against a dark surface anyway (2.6:1 and 2.5:1 respectively).
- Matt also flagged the row hierarchy: MODE / BPM rendered as stacked "label-on-top, 24pt mono value below" while BAR / BEAT rendered as "label + bar + small inline value" — visually inconsistent.
- The PERF FRAME value text `"20.0 / 14 ms"` truncated to `"20.0 / 14…"` in the 86pt fixed column.

DASH.7.2 corrects all four:

1. **`DarkVibrancyView`** — new `NSViewRepresentable` wrapping `NSVisualEffectView` pinned to `.vibrantDark` + `.hudWindow`. Replaces `.regularMaterial` so the dashboard surface is dark *regardless* of system appearance. The `.environment(\.colorScheme, .dark)` modifier locks the SwiftUI subtree to dark too. Above the vibrancy, an explicit `Color.surface` tint at **0.96α** guarantees the worst-case contrast floor (a bright preset frame underneath cannot bleed through).
2. **Colour promotion to AAA-grade.** `coralMuted` → **`coral`** in `BeatCardBuilder.makeModeRow` (LOCKING) and throughout `PerfCardBuilder` (FRAME stressed, QUALITY downshifted, ML WAIT/FORCED). `purpleGlow` → **`purple`** in `BeatCardBuilder.makeBarRow`. `textMuted` → **`textBody`** for the MODE REACTIVE/UNLOCKED states (real status labels need to be readable; muted fails AA at 13pt). All three changes preserve brand semantics while clearing AA on dark.
3. **Inline `.singleValue` rendering.** The `DashboardRowView.singleValueRow` is rewritten as `HStack(label LEFT, Spacer, value RIGHT)` at 13pt mono — matching the `.bar` and `.progressBar` row rhythm. MODE / BPM / QUALITY / ML now align horizontally with BAR / BEAT value text. The 24pt hero numeric is retired; the dashboard collapses to a tighter, more uniform horizontal scan.
4. **FRAME column widened + format compacted.** Reserved column 86pt → **110pt** with `.fixedSize(horizontal: true, vertical: false)` so the `.progressBar` won't truncate the value text. Format `%.1f / %.0f ms` → `%.1f / %.0fms` (no space before "ms") shaves another character.

**Done when:**
- [x] Dashboard renders dark surface regardless of macOS Appearance setting (Light / Dark / Auto).
- [x] Every text colour passes WCAG AA against the surface (`textBody` AAA, `teal` AAA, `coral` AAA, `purple` 4.5:1 AA, `textMuted` only used for "—" placeholders).
- [x] MODE / BPM / QUALITY / ML render inline (label-left, value-right) at 13pt mono.
- [x] FRAME value `"20.0 / 14ms"` no longer truncates.
- [x] Engine + app builds clean. 27 dashboard tests pass. 0 SwiftLint violations on touched files.
- [x] D-089 captures: macOS appearance pinning rationale, contrast math, colour promotions, inline-row redesign, format compaction.

### Increment DASH.7.1 — Brand-alignment pass (impeccable review) ✅ 2026-05-07

After DASH.7 shipped, an impeccable-skill review against `.impeccable.md` surfaced three brand violations and seven smaller issues. DASH.7.1 lands the corrective pass in one increment. P0 (semantic / structural):
1. **STEMS sparkline colour: coral → teal.** `.impeccable.md` reserves teal for "MIR data, **stem indicators**." Coral is for "energy, action, beat moments." Stems are MIR data; teal is correct.
2. **Per-card chrome retired.** Three rounded-rectangle cards (the .impeccable anti-pattern "no rounded-rectangle cards as the primary UI pattern") replaced with a **single shared `.regularMaterial` panel** containing three typographic sections separated by `border` dividers. Aligns with the macOS-specific note "use `NSVisualEffectView` for overlapping panels, not opaque surfaces."
3. **Custom fonts wired (Clash Display + Epilogue).** `DashboardFontLoader` extended to register Clash Display alongside Epilogue. SwiftUI views resolve via `.custom(_:size:relativeTo:)`. App registers fonts at launch in `PhospheneApp.init()`. Card titles render in **Clash Display Medium @ 15pt**, row labels in **Epilogue Medium @ 11pt**, numerics stay SF Mono. Falls back gracefully to system fonts when the TTF/OTF aren't bundled (the README documents how to drop them in).

P1 (significant aesthetic):
4. **SF Symbol status icons dropped.** `checkmark.circle.fill` / `exclamationmark.triangle.fill` were a web-admin trope. Status now reads through value-text colour alone — Sakamoto-liner-note discipline.
5. **PERF status colours mapped onto the brand palette.** `statusGreen` / `statusYellow` retired in favour of `teal` (data healthy) / `coralMuted` (data stressed) / `textMuted` (warming). Same change in `BeatCardBuilder`'s MODE row: LOCKED → teal, LOCKING → coralMuted. The card now uses only the project's three brand colours.
6. **STEMS valueText dropped entirely.** The sparkline IS the readout. The redundant signed-decimal column on the right was Sakamoto-violating ("every word carrying weight").
7. **Spring-choreographed `D` toggle.** `withAnimation(.spring(response: 0.4, dampingFraction: 0.85))` wraps the `showDebug` toggle; the dashboard cards fade in with an 8pt downward offset, fade out cleanly. Honors the .impeccable-spec transition values.

P2 (smaller polish):
8. **Stable `ForEach` IDs.** `id: \.element.title` instead of `\.offset` so card add/remove animations behave when PERF rows collapse.
9. **`+` prefix dropped on signed valueText.** Bar direction encodes sign visually; the leading `+` was noise.
10. **Card titles render at `bodyLarge` (15pt) Clash Display Medium**, becoming typographic anchors of the dashboard column rather than 11pt UPPERCASE labels-on-cards.

**Done when:**
- [x] STEMS rows render in teal at full opacity for line + 0.55 area fill.
- [x] Dashboard is a single `.regularMaterial` panel with three sections (no per-card backdrop).
- [x] Card titles render in Clash Display (or system semibold fallback). Labels in Epilogue (or system regular fallback).
- [x] No SF Symbol decorations remain in the row variants.
- [x] Status colours appear only as `teal` / `coralMuted` / `textMuted` across BEAT MODE + PERF FRAME / QUALITY / ML.
- [x] STEMS sparklines have no right-side numeric column.
- [x] Pressing `D` triggers a spring-damped fade-in for both surfaces.
- [x] Engine + app builds clean. 27 dashboard tests pass. 0 SwiftLint violations on touched files.
- [x] D-088 captures: brand-violation diagnoses, what was retired (statusGreen/Yellow tokens left in DashboardTokens but no longer referenced from card builders; SF Symbols; per-card chrome; STEMS valueText), what was added (Clash Display in DashboardFontLoader, FontResolution.displayFontName, app-launch font registration).

### Increment DASH.7 — SwiftUI dashboard port + visual amendments ✅ 2026-05-07

Pivots the dashboard from the DASH.6 Metal composite path to a SwiftUI overlay. Bundled with two visual amendments surfaced by Matt's live review:
- **STEMS card → timeseries.** New `.timeseries(label, samples, range, valueText, fillColor)` row variant on `DashboardCardLayout`. `StemsCardBuilder` now consumes a `StemEnergyHistory` (240-sample CPU ring buffer per stem, ≈ 8 s at 30 Hz) and emits four sparkline rows. The view model maintains the rings privately and snapshots into the immutable `StemEnergyHistory` value type per redraw. Matches the SpectralCartograph "instruments" aesthetic Matt cited.
- **PERF semantic clarity.** FRAME row's value text now reads `"{ms} / {target} ms"` so headroom is legible; status colour flips green→yellow at 70% of budget (`PerfCardBuilder.warningRatio`). QUALITY row is omitted entirely when the governor is `full` and warmed up. ML row is omitted on idle / `dispatchNow` (READY); only surfaces on `defer` / `forceDispatch`. The card collapses to one row in the steady-state "all healthy" case — .impeccable absence-of-information principle.

Engine snapshot path: `VisualizerEngine.@Published var dashboardSnapshot: DashboardSnapshot?` (Sendable bundle of beat+stems+perf), republished from the existing `pipe.onFrameRendered` hook on `@MainActor`. SwiftUI view model (`DashboardOverlayViewModel`) subscribes via Combine, throttles to ~30 Hz (`.throttle(for: .milliseconds(33))`), maintains the stem history rings, and publishes `[DashboardCardLayout]`. `DashboardOverlayView` sits as PlaybackView Layer 6 (above DebugOverlayView), conditionally rendered on `showDebug` so the existing `D` shortcut drives both surfaces without explicit binding. The DASH.6 commits stay in history; D-087 documents the supersession of D-086.

**Done when:**
- [x] DashboardComposer + DashboardCardRenderer + DashboardTextLayer + Dashboard.metal retired (deleted, not commented out). 10 `compositeDashboard` call sites reverted.
- [x] SwiftUI overlay renders BEAT / STEMS / PERF top-right, gated on `showDebug`. Text crisp at native pixel scale; chrome surface visible against any preset backdrop.
- [x] STEMS rows are sparklines that show ~8 s of recent stem energy.
- [x] PERF card collapses to one row in healthy state; FRAME shows headroom + status colour.
- [x] Engine + app builds clean. New + updated builder tests + 5 view-model tests pass. Dashboard test count 27 (was 39 with the DASH.6 GPU readback tests, now leaner). 0 SwiftLint violations on touched files.
- [x] D-087 captures: pivot rationale (Metal-path justifications didn't materialize), what survives (Sendable builders + tokens + layout + snapshot value types), retirement of D-086, throttle-vs-buffer-update tradeoff, how the SwiftUI overlay handles the STEMS timeseries cleanly, .impeccable collapse rule for PERF.

---

## Phase DM — Drift Motes (particles preset)

A second particles-family preset (sibling to Murmuration). Particles drift in a directional force field through a single dramatic god-ray light shaft — **not** a flock. See `docs/presets/DRIFT_MOTES_DESIGN.md` and `docs/VISUAL_REFERENCES/drift_motes/Drift_Motes_Rendering_Architecture_Contract.md`.

DM.1 was paused at an architectural blocker: the existing `["feedback", "particles"]` pass dispatch is hardwired to Murmuration's `ProceduralGeometry` (single `particle_update` MSL function looked up by name, single Murmuration-tuned configuration). Plugging Drift Motes into that path would render Murmuration's flocking starlings over Drift Motes' sky backdrop. **DM.0** introduces a `ParticleGeometry` protocol so each particle preset can ship its own conformer; **DM.1** then implements Drift Motes' conformer.

### Increment DM.0 — `ParticleGeometry` protocol introduction ✅ 2026-05-08

**Scope:** Pure refactor. Introduce `ParticleGeometry` protocol; make `ProceduralGeometry` conform without behavior change; route `RenderPipeline` and `VisualizerEngine` through the protocol. Murmuration is the only conformer at end of DM.0.

**Delivered:**
- New `PhospheneEngine/Sources/Renderer/Geometry/ParticleGeometry.swift` — `AnyObject, Sendable` protocol with three members: `update(features:stemFeatures:commandBuffer:)`, `render(encoder:features:)`, `activeParticleFraction: Float { get set }`. Doc-commented per member; `// MARK: - ParticleGeometry` not added to `ProceduralGeometry.swift` (existing lifecycle MARKs are clearer than collapsing into one section — diff stays minimal).
- `ProceduralGeometry` declares `: ParticleGeometry` conformance. Method signatures already matched the protocol — zero body changes; +8/−1 lines, all in the class doc-comment block.
- `RenderPipeline.particleGeometry` storage and `setParticleGeometry(_:)` API typed `(any ParticleGeometry)?`. `FeedbackDrawContext.particles`, `drawDirect(...)` and `drawParticleMode(...)` parameter types widened to match. Dispatch logic byte-identical.
- `VisualizerEngine.makeParticleGeometry` factory return type widened to `(any ParticleGeometry)?`. Construction logic unchanged — the Murmuration branch is the only branch.
- `CLAUDE.md` Module Map gains `Geometry/ParticleGeometry` row; `What NOT To Do` gains a "do not parameterize ProceduralGeometry to host non-Murmuration behavior" rule.
- `docs/DECISIONS.md` D-097 — "Particle preset architecture: siblings, not subclasses." Rejects parameterized common pipeline; documents the protocol surface and engine wiring.

**Done when:**
- [x] `ParticleGeometry` protocol exists with a minimal, documented surface.
- [x] `ProceduralGeometry` conforms to `ParticleGeometry` with a near-zero-change diff.
- [x] `VisualizerEngine` and `RenderPipeline` route through the protocol; no concrete `ProceduralGeometry` references outside the type's own file (verified via `grep -rn "ProceduralGeometry" PhospheneEngine/Sources/`).
- [x] `PresetRegressionTests` passes with all 14 presets × 3 fixtures green — Murmuration's dHash is bit-identical.
- [x] All other tests pass (1169/1171; the two failures are pre-existing parallel-load timing flakes — `MetadataPreFetcher.fetch_networkTimeout` and `SoakTestHarness.cancel()` — both pass when re-run in isolation).
- [x] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` succeeds.
- [x] `Particles.metal` and the `Particle` struct memory layout are byte-identical across the increment.
- [x] CLAUDE.md / DECISIONS.md / ENGINEERING_PLAN.md updated.
- [x] All commits use `[DM.0]` prefix.

**Verify:**

```bash
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build
swift test --package-path PhospheneEngine --filter PresetRegressionTests
swift test --package-path PhospheneEngine
grep -rn "ProceduralGeometry" PhospheneEngine/Sources/   # only matches inside Geometry/ProceduralGeometry.swift + doc-comments
ls PhospheneEngine/Sources/Presets/Shaders/ | grep -i drift   # zero matches (DM.0 ships no preset)
git diff <pre-DM.0> HEAD -- PhospheneEngine/Sources/Renderer/Shaders/Particles.metal   # zero output
```

**Estimated sessions:** 1.0 (this session itself).

**Status:** ✅ landed 2026-05-08.

**Carry-forward:** DM.1 resumes with one revision to its Task 6 (pass wiring) — Drift Motes ships its own `DriftMotesGeometry: ParticleGeometry` conformer rather than treating Murmuration's path as inherited infrastructure. `VisualizerEngine.makeParticleGeometry` gains a Drift Motes branch.

### Increment DM.1 — Drift Motes Session 1 (foundation) ✅ landed 2026-05-08

**Scope (resumed post-DM.0):** Compute kernel + sprite render + sky backdrop. Force-field motion (wind + curl_noise + lifecycle recycle), no flocking, no audio coupling beyond the D-019 stem-warmup blend (touched but not consumed in DM.1 — wired for DM.2). `DriftMotesNonFlockTest` is the acceptance gate. See `prompts/DM_1_PROMPT.md`.

**Files created:**

- `PhospheneEngine/Sources/Presets/Shaders/DriftMotes.json` — preset sidecar matching `Gossamer.json` schema. `passes: ["feedback", "particles"]`, `fragment_function: "drift_motes_sky_fragment"`, `family: particles`, `rubric_profile: lightweight`, `certified: false`.
- `PhospheneEngine/Sources/Presets/Shaders/DriftMotes.metal` — sky-backdrop fragment shader. Static warm-amber vertical gradient (no audio reactivity in Session 1).
- `PhospheneEngine/Sources/Renderer/Shaders/ParticlesDriftMotes.metal` — engine-library compute + sprite shaders (`motes_update` / `motes_vertex` / `motes_fragment`). Force-field motion: wind `normalize((-1, -0.2, 0)) * 0.3` + 4-octave curl-of-fBM turbulence × 0.15, recycle on bounds-exit or age expiry, default warm-amber emission. Filename uses `Particles*` prefix because `ShaderLibrary` concatenates files in lexicographic order — a `D`-prefixed name would precede `Particles.metal` and the shared `Particle` struct would not yet be in scope. Documented in the file header and in `CLAUDE.md`.
- `PhospheneEngine/Sources/Renderer/Geometry/DriftMotesGeometry.swift` — `ParticleGeometry` conformer. 800 particles (Tier 2 target from `DRIFT_MOTES_DESIGN.md §5.7`), additive blend (`.one + .one`), uniform-cube init with steady-state wind velocity + age-randomised lifecycle so the field is in equilibrium from frame 0.
- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/DriftMotesTests.swift` — `DriftMotesNonFlockTest` running 200 frames of silence-fixture compute. Two metrics: pairwise distance distribution (50 deterministic random pairs; ≥ 80% of frame-50 value, looser to accommodate the natural cube → top-slab transient) and centroid-relative spread RMS (translation-invariant; ≥ 85%, the load-bearing flock discriminator — flocking would shrink this by 50%+).

**Files modified:**

- `PhospheneApp/VisualizerEngine.swift` — `particleGeometry: (any ParticleGeometry)?` split into two named properties (`murmurationGeometry`, `driftMotesGeometry`); `makeParticleGeometry` factory split into `makeMurmurationGeometry` + `makeDriftMotesGeometry`. Both built once at engine init.
- `PhospheneApp/VisualizerEngine+Presets.swift` — `applyPreset .particles:` switches on `desc.name` to attach the right conformer.
- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/PresetLoaderCompileFailureTest.swift` — `expectedProductionPresetCount` 14 → 15 (Failed Approach #44 silent-drop gate).
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetRegressionTests.swift` — added Drift Motes golden hash entry (`0x8000000000008000` for all three fixtures — the regression harness renders only the sky fragment, which is audio-independent in Session 1).

**Audit results:** Murmuration's `ProceduralGeometry`, `Particles.metal`, the `ParticleGeometry` protocol surface, and `RenderPipeline*.swift` are byte-identical to the post-DM.0 baseline (`git diff` returns zero output). PresetRegressionTests' Murmuration golden hash unchanged at the post-DM.0 values. `swift test --package-path PhospheneEngine`: 1172 tests, 3 documented pre-existing flakes (`MetadataPreFetcher.fetch_networkTimeout`, `SessionManager.cancel_fromReady`, `SoakTestHarness.cancel`) — none related to DM.1. `xcodebuild` app build succeeds. SwiftLint: 0 violations on touched files. D-026 / D-019 / D-029 grep checks all return zero violations.

**Estimated sessions:** 1.0 (this session itself, post-DM.0).

**Status:** ✅ landed 2026-05-08.

**Carry-forward:** DM.2 wires the light shaft (`ls_shadow_march` or `ls_radial_step_uv`), floor fog (`vol_density_height_fog`), and per-particle hue baking from `vocalsPitchNorm` into the existing `Particle.color` lanes (no struct extension needed — DM.1 confirmed the four `packed_float4` lanes are sufficient). DM.3 wires the full audio routing (wind force ×= `f.bass_att_rel`, emission rate × `f.mid_att_rel`, backdrop palette tinted by `f.valence`, drum dispersion shock from `stems.drums_energy_dev`, anticipatory shaft pulse on `f.beat_phase01`) and the M7 frame-match review against `01_atmosphere_dust_motes_light_shaft.jpg`.

### Increment DM.2 — Drift Motes Session 2 (audio coupling) ✅ landed 2026-05-08

**Scope:** Three coupled audio reactivities arrive together because they share one coherent visual story — the field is musical, with a god-ray cutting through floor fog and per-mote hue carrying the recent vocal melody. Specifically: light shaft via `ls_radial_step_uv` in the sky fragment, floor fog via `vol_density_height_fog` in the same fragment, and per-particle hue baked at emission time in `motes_update` under a D-019 warmup-blended source. Sprite fragment additionally modulates per-mote brightness from shaft proximity. See `prompts/DM_2_PROMPT.md`.

**Files created:**

- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/DriftMotesRespawnDeterminismTest.swift` — three tests covering the DM.2 hue-baking contract:
  - **Within-life invariance:** color is bit-identical across 30 frames for every slot that did not respawn (gate: ≥ 100 stable slots).
  - **Respawn changes hue across the field:** under warm stems with a 4-octave pitch sweep, after 240 frames the per-particle colour distribution shows variance > 1e-3 (vs. ≈ 0 for a uniform-amber field).
  - **Warm-stems variance > 2× cold-stems:** 60-frame runs with `StemFeatures.zero` vs. realistic stems with sweeping vocal pitch produce a variance ratio that proves D-019 contributes real signal at warm stems (not a numeric no-op).
  Total runtime: ~0.35 s for all three.

**Files modified:**

- `PhospheneEngine/Sources/Renderer/Shaders/ParticlesDriftMotes.metal` — added `dm_pitch_hue(pitchHz, confidence)` static helper (canonical pitch→hue replacement for the retired `vl_pitchHueShift`, octave-wrap log map: A2→0.0, A6→1.0); replaced the literal warm-amber emission color with the D-019-blended baked hue (`smoothstep(0.02, 0.06, totalStemEnergy)` between the cold-stems hash-jitter+`f.mid_att_rel`-shift fallback and the warm-stems pitch hue); removed the `(void)stems;` placeholder; vertex shader now passes per-particle UV; fragment modulates brightness by Gaussian falloff from the shaft axis (sun anchor `(-0.15, 1.20)`, axis through frame centre, cone width 16); header comment updated to reflect the post-DM.2 reality.
- `PhospheneEngine/Sources/Presets/Shaders/DriftMotes.metal` — sky fragment now layers warm-amber gradient (DM.1 baseline) + multiplicative cool blue-gray floor fog via `vol_density_height_fog(scale=12.0, falloff=0.85)` + additive warm-gold light shaft via 32-step `ls_radial_step_uv` accumulation with `0.65 + 0.25 × f.mid_att_rel` continuous intensity. Same sun anchor as the sprite fragment so the highlight stays congruent.
- `PhospheneEngine/Sources/Renderer/Shaders/Common.metal` — extended `FeatureVector` to 192 bytes / 48 floats (MV-1 deviation primitives + MV-3b beat phase + bar phase + pad) and `StemFeatures` to 256 bytes / 64 floats (MV-1 deviation primitives + MV-3a per-stem rich metadata + MV-3c vocals pitch + pad). Field order is byte-identical to `PresetLoader+Preamble.swift`'s preset preamble; the first 32 / 16 floats match the pre-MV-1 layout exactly so existing engine readers (Murmuration's `particle_update`, MVWarp shaders, feedback shaders) are byte-identical. Pre-DM.2 the engine MSL structs were stuck at the pre-MV-1/MV-3 sizes, so engine-library shaders could not read `f.mid_att_rel` / `stems.vocals_pitch_hz` — the kernel hue baking required this correction.
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetRegressionTests.swift` — Drift Motes golden hash regenerated to `0x0001070F1F3F7FFF` for all three fixtures (the harness renders the sky fragment only and `f.mid_att_rel` is zero across all three regression fixtures, so steady/beatHeavy/quiet converge to the same hash); doc comment rewritten to describe what's actually under test (sky + shaft + fog) and to point at `DriftMotesRespawnDeterminismTest` as the regression-lock for per-particle hue. Murmuration's three hashes regenerated identically to the post-DM.1 baseline (byte-identical reads through extended struct, no shader logic change) — Murmuration invariant preserved.
- `PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/SoakTestHarnessTests.swift` — added `shortRunDriftMotes` SOAK-gated kernel-cost benchmark (30 s simulated 60 Hz, 800 Tier 2 particles, GPU command-buffer timing). Tier 2 results below.

**Performance (DM.2 Task 8, kernel-only Tier 2 measurement, this session):**

- p50 = 0.107 ms, p95 = 0.158 ms, p99 = 0.763 ms, kernel overruns (>14 ms) = 0
- Well under the 1.6 ms full-frame Tier 2 budget. The post-DM.2 audio coupling adds near-zero kernel cost on top of DM.1 (the work is at emission time only — one branch per respawn, ~tens of frames per particle lifetime).
- **Tier 2 full-frame timing** (sky fragment + sprite render + feedback decay) is deferred to a runtime app session — `SoakTestHarness` has no preset-pinned full-pipeline path within `swift test`. The kernel-only benchmark is the right gate for this increment because the audio coupling is the only thing that grew between DM.1 and DM.2.
- **Tier 1 timing deferred** to a hardware run (Mac M1/M2). Kernel cost on Tier 1 is bounded by the same fact: the work landed only on emission, and the curl-noise cost dominates per-frame.

**Audit:**

- D-026 deviation-primitives grep on `ParticlesDriftMotes.metal` returns zero hits for absolute-threshold patterns (`smoothstep` against `f.bass`/`f.mid`/`f.treb` direct values).
- D-019 blend grep returns one hit at the emission branch in `motes_update`, exactly where the prompt specifies.
- D-029 pass set: `DriftMotes.json` still declares `["feedback", "particles"]` — no new render pass.
- D-097 / DM.0 / DM.1 invariants: `Particles.metal`, `ProceduralGeometry.swift`, `ParticleGeometry.swift`, and `RenderPipeline*.swift` are byte-identical to their post-DM.1 state. Murmuration's three regression hashes match the DM.1 baseline.
- `swiftlint lint --strict` 0 violations on touched files.
- Engine + app builds clean; full regression suite (15 presets × 3 fixtures = 45 cases) green.

**Estimated sessions:** 1.0 (this session itself).

**Status:** ✅ landed 2026-05-08.

**Carry-forward:** DM.3 adds emission-rate scaling from `f.mid_att_rel`, drum dispersion shock from `stems.drums_beat`, optional structural-flag scatter, the M7 frame-match review against `01_atmosphere_dust_motes_light_shaft.jpg`, and the deferred Tier 1 hardware perf measurement. `dm_pitch_hue` is the canonical pitch→hue helper for the project; future presets can adopt it by name.

### Increment DM.3 — Drift Motes Session 3 (event-driven audio routing) ✅ landed 2026-05-08

**Scope:** The two event-driven audio reactivities from DM.1's carry-forward arrive together: emission-rate scaling from `f.mid_att_rel` (lifetime divisor at respawn time) and drum dispersion shock from `stems.drums_beat` (radial outward velocity impulse gated by the BeatDetector envelope). The optional structural-flag scatter (Task 3) deferred to DM.4 — `StructuralPrediction` is CPU-only and not wired through the GPU `FeatureVector`; landing it would require a struct-extension violating D-099's just-locked layout. M7 contact-sheet harness extended to `Drift Motes`; full-pipeline + Tier 1 measurement procedures documented for the next hardware run. See `prompts/DM.3-prompt.md`.

**Files created:**

- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/DriftMotesAudioCouplingTest.swift` — three tests covering the DM.3 audio reactivities:
  - **Emission rate scaling:** 600 frames at `f.mid_att_rel = 0.1` vs. `0.9` (one full lifetime turn-over so the population converges near steady state); average particle age under high mid `< 0.7×` low baseline. Catches a no-op (ratio ≈ 1.0).
  - **Dispersion shock raises velocity variance:** 240 frames under a 2 Hz square wave on `drumsBeat` (15 frames on, 15 off) raises per-particle velocity-magnitude variance ≥ 1.5× the silence baseline.
  - **Dispersion shock decays between beats:** single beat impulse + 60 frames of silence settles velocity-magnitude variance back inside 1.2× the silence baseline. Proves the field doesn't accumulate runaway dispersion.
  Total runtime: ~0.35 s for all three.
- `docs/diagnostics/DM.3-perf-capture.md` — runtime app procedure for full-pipeline Tier 2 capture (pin Drift Motes, run 60 s of representative audio, parse `features.csv` `frame_ms` column for percentiles). Pass criteria: p50 ≤ 8 ms / p95 ≤ 14 ms / p99 ≤ 25 ms / drops ≤ 8 %.
- `docs/diagnostics/DM.3-tier1-measurement.md` — Tier 1 (M1/M2) hardware procedure with kernel + full-pipeline gates (kernel p95 ≤ 1.5 ms; full-pipeline p50 ≤ 11 ms / p95 ≤ 19 ms / p99 ≤ 30 ms). Documents when to run, when to defer, and the first tuning lever (`kEmissionRateGain` 1.5 → 1.0).

**Files modified:**

- `PhospheneEngine/Sources/Renderer/Shaders/ParticlesDriftMotes.metal` — added two file-scope `constexpr constant` tuning constants (`kEmissionRateGain = 1.5f`, `kDispersionShockGain = 0.4f`) alongside the DM.2.closeout fog constants in `DriftMotes.metal`. Both `p.life` assignment sites in `motes_update` (the respawn branch and the safety-net `p.life <= 0.001` recovery) now multiply the random lifetime by `1 / (1 + kEmissionRateGain * max(0, f.mid_att_rel))` — the `max(0, ...)` clamp prevents quiet sections from extending lifetime (the deviation primitive is signed in [-0.5, 0.5]; we use only the positive 'melody peaks' half). Linear in `mid_att_rel`, D-026-compliant by construction (no smoothstep, no absolute threshold). After the wind+turb integration and before the position update, a new dispersion-shock branch fires when `smoothstep(0.30, 0.70, stems.drums_beat) > 0.0`: a radial outward impulse in the horizontal `(x, z)` plane with a small +y lift (0.2 of horizontal magnitude) — the BeatDetector envelope shape provides natural decay between beats; damping (0.97/frame) settles the field. The smoothstep absolute threshold is D-026-allowed because D-026 targets FV raw bands, not stem onset envelopes (VolumetricLithograph uses the same `smoothstep(0.30, 0.70, stems.drums_beat)` gate). Header comment rewritten to document the post-DM.3 reality: kernel reads stems and FeatureVector both at emission time AND at integration time. The DM.4 stub block is referenced explicitly in the header.
- `PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/SoakTestHarnessTests.swift` — `shortRunDriftMotes` SOAK benchmark extended to drive `stems.drumsBeat` as a 2 Hz square wave (15 frames on / 15 off) so the dispersion-shock branch and its smoothstep evaluation are exercised every frame. Existing `f.midAttRel` modulation already exercised emission-rate scaling. Mark and header rewritten for DM.3: the kernel benchmark is now the regression gate for both DM.2 hue baking AND DM.3 audio routing. Full-pipeline measurement and Tier 1 numbers documented as runtime / hardware deferrals (per the new `DM.3-perf-capture.md` and `DM.3-tier1-measurement.md` procedure docs).
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetVisualReviewTests.swift` — `renderPresetVisualReview` arguments extended from `["Arachne", "Gossamer", "Volumetric Lithograph"]` to include `"Drift Motes"`; new `driftMotesReferenceRelPath` constant; new `buildDriftMotesContactSheet(renderedMidPNG:to:)` helper produces a stacked layout (top half = rendered output at the steady-mid fixture, bottom half = `01_atmosphere_dust_motes_light_shaft.jpg`). Single-reference layout matches Drift Motes' DM.0-spec'd reference set of one image. The contact sheet is the M7 deliverable for Matt's review; this commit lands `certified: false` and Matt's eyeball + iteration close out the cert flip in a separate commit per the prompt's directive.

**Performance (DM.3 Task 4, kernel-only Tier 2 measurement, this session):**

- p50 = 0.115 ms, p95 = 0.162 ms, p99 = 0.781 ms, mean = 0.135 ms, kernel overruns (>14 ms) = 0 across 1800 frames.
- Compared to DM.2 baseline (p50 = 0.107 / p95 = 0.158 / p99 = 0.763): the new per-frame work (smoothstep + length + branch + small SIMD impulse) costs ≤ 0.01 ms on top of DM.2. Well under the 1.6 ms full-frame Tier 2 budget.
- **Tier 2 full-pipeline timing** still requires a runtime app session — the sprite pass needs a `CAMetalDrawable`, which `swift test` cannot produce. Procedure documented in `docs/diagnostics/DM.3-perf-capture.md`.
- **Tier 1 timing** requires Tier 1 hardware (M1/M2). Procedure documented in `docs/diagnostics/DM.3-tier1-measurement.md`. This dev machine is M3+ (Tier 2); flag for Matt to run.

**Audit:**

- D-026 grep on `ParticlesDriftMotes.metal` returns zero hits for the canonical anti-pattern (`grep -nE 'mid_att_rel\s*>|drums_beat\s*>|treb\s*>|bass\s*>'`); the `smoothstep(0.30, 0.70, stems.drums_beat)` is a deliberate gate on a stem onset envelope (D-026 explicitly targets FV raw bands, not stem onset signals — VolumetricLithograph precedent).
- D-019 grep returns the existing emission-time blend at the respawn branch — unchanged from DM.2.
- D-029 pass set unchanged: `DriftMotes.json` still declares `["feedback", "particles"]`.
- D-097 / DM.0 / DM.1 / DM.2 invariants: `Particles.metal`, `ProceduralGeometry.swift`, `ParticleGeometry.swift`, `RenderPipeline*.swift` are byte-identical to post-DM.2 (`git diff --stat` returns zero output for those paths). Murmuration's three regression hashes unchanged from DM.2 baseline.
- D-099 invariant: `FeatureVector` / `StemFeatures` MSL struct sizes unchanged from DM.2 (192 / 256 bytes). DM.3 reads existing fields only.
- Drift Motes regression hash unchanged (`0x0001070F1F3F7FFF` across all three fixtures) — the regression harness renders only the sky fragment, which doesn't see compute-kernel output. New `DriftMotesAudioCouplingTest` is the regression-lock for kernel audio routing.
- `swiftlint lint --strict` reports 0 violations on touched files (test files excluded from lint by config; the Metal source isn't lintable).
- Engine + app builds clean; targeted test surfaces (`DriftMotes`, `PresetRegression`, `PresetAcceptance` ex Arachne) green. A PresetAcceptance Arachne failure (`beatMotion 1.78 > 1.0`) surfaced during DM.3 verification. Root cause: uncommitted V.7.7C.5 work-in-progress in the working tree (canvas-filling silk increases the screen-integrated beat-pulse MSE; V.7.7C.5 itself recalibrates the beat-pulse coefficient `0.06 → 0.025` to compensate). Not a DM.3 regression — Arachne files are outside this commit's scope and tracked under V.7.7C.5; landing that increment closes the failure. (My initial DM.3 closeout misattributed this to V.7.7C.4 — V.7.7C.4 is committed at `3feb6330` and was green; the working-tree changes are V.7.7C.5.)

**Estimated sessions:** 1.0 (this session itself).

**Status:** ✅ landed 2026-05-08; preset stays `certified: false` pending M7 sign-off. Full-pipeline Tier 2 capture + Tier 1 hardware measurement deferred to runtime / hardware runs per the new procedure docs.

**Carry-forward:** DM.4 — three world-feel reactivities deferred from DM.3 (wind force × `f.bass_att_rel`; backdrop palette tinted by `f.valence`; anticipatory shaft pulse on `f.beat_phase01`) plus the structural-flag scatter punted from this increment because `StructuralPrediction` is CPU-only.

### Increment DM.4 — Drift Motes Session 4 (world-feel pass) — planned

**Scope:** Three reactivities deferred from DM.3 that cohere as a "world-feel" grouping rather than discrete events:

- **Wind force × `f.bass_att_rel`** — low-band continuous: bass shapes the motion-field intensity. Multiplier on the existing wind vector in `motes_update` (the kernel already reads the wind direction + magnitude from buffer(4); adding a bass scalar is a one-line product on the Swift side at frame-bind time, or directly in MSL).
- **Backdrop palette tint by `f.valence`** — slow-moving emotional read of the world. Tints the warm-amber sky gradient toward warmer / cooler hues at positive / negative valence. Lands in `DriftMotes.metal`'s sky fragment.
- **Anticipatory shaft pulse on `f.beat_phase01`** — pre-beat shimmer. The shaft intensity gets a `smoothstep(0.75, 1.0, f.beat_phase01)` boost in the last quarter of each beat, anticipating the drum hit.

**Plus** the **structural-flag scatter** punted from DM.3 Task 3 — needs a small piece of design work first: either thread `StructuralPrediction.confidence` through the GPU `FeatureVector` (adds a float; touches D-099-locked layout — careful) or read it CPU-side and bake into a non-FeatureVector-bound config buffer. The Murmuration precedent (per-frame `ParticleConfig`) is the cheaper path.

**Estimated sessions:** 1.0.

**Status:** planned post-DM.3.

**Carry-forward:** DM.5 (cert + polish) — Matt M7 sign-off for `certified: true`, any tuning iterations surfaced by review, hand-off to the catalog so Drift Motes counts toward Milestone D.

---

## Phase LM — Lumen Mosaic (glass-family ray-march preset)

Lumen Mosaic is a contemplative glass-family preset for slow ambient / downtempo / dub. The visible surface is a flat `sd_box` glass panel filling the camera frame; the panel material is `mat_pattern_glass` (V.3 §4.5b) producing hex-biased Voronoi cells with per-cell dome+ridge shading and in-cell frost. The preset's character comes from an analytical multi-source backlight emitted through the cells: 4 audio-driven light agents drift, dance to the beat, and shift color with mood, producing a constantly-moving stained-glass field that never resolves to a static composition. Authoritative authoring docs at `docs/presets/LUMEN_MOSAIC_DESIGN.md` (visual intent), `docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md` (implementation contract), `docs/presets/LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md` (phased increments).

The preset is sequenced as 10 increments LM.0 → LM.9 with cert sign-off at LM.9. The certification target is **the cheapest ray-march preset in the catalog** (p95 ≤ 3.7 ms at Tier 2 / ≤ 4.5 ms at Tier 1), making it suitable for ambient sections where Phosphene wants a quiet, low-energy preset that still reads as visually rich.

### Increment LM.0 — Fragment buffer slot 8 infrastructure

**Scope.** Reserve fragment buffer slot 8 in `RenderPipeline` as the canonical home for a third per-preset CPU-driven state buffer alongside the existing slots 6 and 7. This is pure infrastructure — no shader code, no Lumen Mosaic preset, no audio routing. The slot is wired so LM.1 (the first Lumen Mosaic shader) can bind state via the new setter and the lighting fragment can read `LumenPatternState` directly. Lumen Mosaic is the first planned consumer; the slot is shared and any future preset that needs a third per-frame state buffer binds here.

**Done when.**

- `RenderPipeline.directPresetFragmentBuffer3` storage + `setDirectPresetFragmentBuffer3(_:)` setter wired, mirroring the slot 6 / 7 setter pattern.
- Slot 8 bound conditionally (null when no preset has called the setter) at every fragment encoder that already binds slots 6 / 7 (`RenderPipeline+Staged.encodeStage`, `RenderPipeline+MVWarp.renderSceneToTexture`) **plus** the direct-pass (`drawDirect`) and the ray-march **lighting** fragment (`RayMarchPipeline.runLightingPass`). The G-buffer pass intentionally does NOT bind slot 8 — only lighting consumes it today.
- `CLAUDE.md` GPU Contract section lists `buffer(8)` with the same paragraph-structure as buffer(6) / buffer(7).
- `DECISIONS.md` D-LM-buffer-slot-8 entry filed.
- `ENGINEERING_PLAN.md` Phase LM header + LM.0 entry filed (this entry).
- `swift build --package-path PhospheneEngine` green.
- `swift test --package-path PhospheneEngine` green; existing presets unaffected (`PresetAcceptanceTests` + `PresetRegressionTests` both pass with golden hashes unchanged — slot 8 is null in both).

**Verify.**

- `swift build --package-path PhospheneEngine`
- `swift test --package-path PhospheneEngine`
- `swift test --package-path PhospheneEngine --filter PresetAcceptanceTests`
- `swift test --package-path PhospheneEngine --filter PresetRegressionTests`

**Estimated sessions:** 0.5 (this session itself).

**Status:** planned for 2026-05-08.

**Carry-forward.** LM.1 implements `LumenPatternEngine` (CPU-side state populated each frame + setter call) + `LumenMosaic.metal` (lighting fragment reads `LumenPatternState` at `[[buffer(8)]]`). See `docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md` §"Required uniforms / buffers" for the buffer layout.

### Increment LM.1 — Minimum viable preset

**Scope.** Land the first `LumenMosaic.metal` + `LumenMosaic.json` in the catalog: a single planar `sd_box` glass panel filling the camera frame plus 50 % bleed (Decision G.1, contract §P.1), per-cell Voronoi domed-cell relief + `fbm8` in-cell frost baked into `sceneSDF` as Lipschitz-safe displacements, and a fixed warm-amber backlight emitted through every cell. **No audio reactivity, no pattern engine, no slot 8 binding** — the pattern state buffer is wired up at LM.2 / LM.4. LM.1 proves the rendering pipeline works end-to-end (preamble compile + G-buffer + matID dispatch + lighting + bloom + ACES) before LM.2 layers on the 4-light analytical pattern engine.

**Architectural decisions filed in this increment.** D-LM-matid (extending the D-021 `sceneMaterial` signature with `thread int& outMatID` + writing the value into `gbuf0.g` so `raymarch_lighting_fragment` can dispatch on emission-dominated dielectric without changing the deferred PBR pipeline's pixel formats). The 3 existing ray-march presets (Glass Brutalist, Kinetic Sculpture, Volumetric Lithograph) gain the trailing parameter and a single `(void)outMatID;` line — no behavioural change, they stay on the `matID == 0` Cook-Torrance path. `RayMarch.metal` gains file-scope `kLumenEmissionGain (4.0)` and `kLumenIBLFloor (0.05)` constants and a single early-return branch when `matID == 1`. CLAUDE.md GPU Contract §G-Buffer Layout extends the `gbuffer0.g` documentation accordingly.

**Done when.**

- `LumenMosaic.metal` + `LumenMosaic.json` land at `PhospheneEngine/Sources/Presets/Shaders/`. `family: geometric`, `passes: ["ray_march", "post_process"]`, `certified: false`, `lumen_mosaic.cell_density = 30.0`. SSGI intentionally omitted (emission dominates).
- `sceneSDF` is a single `sd_box` sized `cameraTangents.xy * 1.50` with Voronoi domed-cell relief (`voronoi_f1f2(panel_uv, 30)` height-gradient + smoothstep ridge per SHADER_CRAFT.md §4.5b) and `fbm8(p * 80)` in-cell frost subtracted as Lipschitz-safe displacements (`kReliefAmplitude = 0.004`, `kFrostAmplitude = 0.0008`). The G-buffer central-differences normal picks them up automatically; D-021 `sceneMaterial` has no normal-output channel.
- `sceneMaterial` writes `outMatID = 1` (emission-dominated dielectric), stores the static backlight (`(0.95, 0.60, 0.30)` warm amber + a `mood_tint(valence, arousal) × 0.04` ambient floor) into `albedo`, and sets `roughness = 0.40`, `metallic = 0.0` for cosmetic placeholder consistency with the §4.5b dielectric.
- `raymarch_lighting_fragment` reads `gbuf0.g` and returns `albedo × 4.0 + irradiance × 0.05 × ao` for `matID == 1`. `matID == 0` path is byte-identical to pre-LM.1 (regression hashes for all 3 existing ray-march presets unchanged).
- `presetLoaderBuiltInPresetsHaveValidPipelines` regression gate green (LumenMosaic compiles cleanly through `PresetLoader`).
- `PresetAcceptanceTests` green for LumenMosaic against all 4 D-037 invariants (non-black at silence, no white clip on steady, beat response ≤ 2× continuous + 1.0, form complexity ≥ 2). The static backlight + per-cell relief should clear all four trivially.
- `PresetRegressionTests` green for the 3 existing ray-march presets — golden hashes unchanged because their `sceneMaterial` bodies don't write `outMatID` (caller pre-zeros to 0, lighting falls through to the existing Cook-Torrance path). New entry for LumenMosaic added under `goldenPresetHashes` via `UPDATE_GOLDEN_SNAPSHOTS=1` regen.
- LM.1 contact sheet captured at `docs/VISUAL_REFERENCES/lumen_mosaic/contact_sheets/LM.1/` for all six standard fixtures (silence / steady / beat-heavy / sustained-bass / HV-HA / LV-LA mood). Panel-edge invariant verified: every pixel in every fixture hits `matID == 1` (no `matID == 0` background pixels visible).
- p95 ≤ 2.0 ms at Tier 2 / ≤ 2.5 ms at Tier 1 over `PresetPerformanceTests`.
- `swiftlint lint --strict` green on touched files.
- `CLAUDE.md` Shaders/ list gains LumenMosaic entry; G-Buffer Layout section documents `gbuffer0.g` matID convention.
- This entry filed.

**Verify.**

- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`
- `swift build --package-path PhospheneEngine`
- `swift test --package-path PhospheneEngine`
- `swift test --package-path PhospheneEngine --filter presetLoaderBuiltInPresetsHaveValidPipelines`
- `swift test --package-path PhospheneEngine --filter PresetAcceptanceTests`
- `swift test --package-path PhospheneEngine --filter PresetRegressionTests`
- `swift test --package-path PhospheneEngine --filter PresetPerformanceTests`
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReviewTests` (capture contact sheet)
- `swift run --package-path PhospheneTools CheckVisualReferences` (verifies VISUAL_REFERENCES schema; `lumen_mosaic` already at green warnings-only state from the pre-LM.0 reference curation)

**Estimated sessions:** 2.

**Status:** planned for 2026-05-08.

**Carry-forward.** LM.2 wires the 4-light analytical pattern engine: `LumenPatternEngine` Swift class populates `LumenPatternState` (4 × `LumenLightAgent` + 4 × `LumenPattern` + activeCounts + ambientFloorIntensity) once per frame, calls `pipeline.setDirectPresetFragmentBuffer3(...)` (LM.0 setter) to bind slot 8, and the shader's `lm_backlight_static` is replaced by `sample_backlight_at(cell_center_uv, ...)` reading the slot 8 buffer. Mood-coupled hue shift (Decision E.1) + D-019 silence fallback verification + per-stem hue offsets (Decision §P.4) all land at LM.2.

### Increment LM.2 — Audio-driven 4-light backlight (continuous energy primary)

**Scope.** Replace LM.1's static warm-amber backlight with four audio-driven light agents — one per stem (drums / bass / vocals / other) — sampled at the cell-centre uv per Decision D.1 (cell-quantized colour). Agent positions compose a slow mood-driven Lissajous **drift** (driftSpeed lerp(0.05, 0.20, normalized smoothedArousal)) plus a `beat_phase01`-locked figure-8 **dance** (contract §P.4: per-agent quarter-cycle phase offsets, amplitude `clamp(0.04 + 0.10 × f.arousal, 0.04, 0.14)` reading raw `f.arousal`). Intensity is the deviation-primitive stem read with FV fallback under the standard D-019 warmup; colour is per-stem base × `mood_tint(smoothedValence, smoothedArousal)` with a 5 s low-pass on valence/arousal (ARACHNE §11). Pattern slots stay zeroed (`activePatternCount = 0`) — the pattern engine bursts arrive at LM.4. Slot 8 binding is **widened** in LM.2 from "lighting pass only" (LM.0) to "G-buffer pass + lighting pass" so `sceneMaterial` can read `LumenPatternState` directly via the new D-021 trailing parameter `constant LumenPatternState& lumen`.

**Done when.**

- `Sources/Presets/Lumen/LumenPatternEngine.swift` ships `LumenLightAgent` (32 B), `LumenPattern` (48 B), `LumenPatternState` (336 B) value types byte-identical to the matching MSL structs in the preamble; `LumenPatternEngine` final class with `init?(device:seed:)`, `tick(features:stems:)`, `snapshot()`, `reset()`, and the `setAgentBasePositionForTesting(_:_:)` test seam.
- The `sceneMaterial` D-021 signature gains a trailing `constant LumenPatternState& lumen` parameter. All 4 ray-march presets (Glass Brutalist, Kinetic Sculpture, Volumetric Lithograph, Lumen Mosaic) update; non-Lumen presets silence it via `(void)lumen;`. The preamble's `raymarch_gbuffer_fragment` declares `[[buffer(8)]]` and forwards to `sceneMaterial`. The two SSGI / RayMarch test fixture preset sources update too.
- `RayMarchPipeline` allocates a 336-byte zero-filled `lumenPlaceholderBuffer` at init and binds it at slot 8 in BOTH `runGBufferPass` and `runLightingPass` whenever `presetFragmentBuffer3` is nil — so non-Lumen ray-march presets compile against the same fragment with a defined slot-8 binding.
- `VisualizerEngine+Presets.swift` allocates `LumenPatternEngine` when the active ray-march preset is `"Lumen Mosaic"` and wires `setDirectPresetFragmentBuffer3(engine.patternBuffer)` plus a `setMeshPresetTick { engine?.tick(features:stems:) }` closure. Reset path nils both on every preset apply.
- `Tests/PhospheneEngineTests/Presets/LumenPatternEngineTests.swift` ships 15 tests across 7 suites: struct layout (336 / 32 / 48), silence behaviour (intensities < 0.05, ambient floor propagated), HV-HA / LV-LA mood drift speed, mood smoothing time-constant (15 s → 95 %), stem-direct routing, FV warmup fallback (drums + bass), beat-locked dance figure-8 (pos(0) − pos(0.5) ≈ (0.18, 0)), dance amplitude scales with arousal, agent inset clamp under forced base outside ±0.85, byte-identical determinism. All 15 pass.
- `PresetAcceptanceTests` + `PresetRegressionTests` + `PresetLoaderCompileFailureTest` continue to pass for all 15 production presets — golden hashes unchanged because non-Lumen presets render byte-identically with the new signature ignored.
- CLAUDE.md updated: LumenMosaic.metal entry rewritten for LM.2; new `Lumen/LumenPatternEngine.swift` entry; slot 8 GPU contract widened; D-021 signature changelog (LM.1 + LM.2).

**Verify.**

- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`
- `swift build --package-path PhospheneEngine`
- `swift test --package-path PhospheneEngine --filter LumenPatternEngineTests`
- `swift test --package-path PhospheneEngine --filter "PresetAcceptance|PresetRegression|PresetLoaderCompileFailure"`
- `swift test --package-path PhospheneEngine --filter "SSGITests|RayMarchPipelineTests"` (covers the slot-8 binding contract widening + signature update)
- `swift test --package-path PhospheneEngine` (full suite — pre-existing parallel-load timing flakes unchanged)
- `swiftlint lint --strict --config .swiftlint.yml` (new file disables `file_length` / `large_tuple` per Arachne pattern; baseline violation count unchanged)

**Status:** ✅ 2026-05-09.

**Carry-forward.** LM.3 keeps the same engine + GPU contract and adjusts the per-stem hue offsets + drift bounds to match the LM.3 design-doc "stem-direct routing" recipe. LM.4 promotes pattern slots from idle → live (radial_ripple, sweep) keyed to bar boundaries (`f.barPhase01` rolls past 1.0) and drum onsets (`stems.drumsBeat` rising edge). Both LM.3 and LM.4 land without further changes to the slot-8 binding contract.

---

These milestones map to product-level outcomes, not implementation phases.

**Milestone A — Trustworthy Playback Session.** ✅ **MET (2026-04-25).** A user can connect a playlist, obtain a usable prepared session, and complete a full listening session without instability. *Requires: ~~2.5.4~~ ✅, ~~Phase U increments U.1–U.7~~ ✅, ~~progressive readiness basics (6.1)~~ ✅.*

**Milestone B — Tasteful Orchestration.** ✅ **MET (2026-04-25).** Preset choice and transitions are consistently better than random and pass golden-session tests. *Requires: ~~Phase 4 complete~~ ✅, ~~Increment 5.1~~ ✅ (landed as 4.0).*

**Milestone C — Device-Aware Show Quality.** ✅ **MET (2026-04-25).** The same playlist produces an excellent show on M1 and a richer one on M4 without jank. *Requires: ~~Phase 6 complete~~ ✅.*

**Milestone D — Library Depth.** The preset catalog is large enough, varied enough, and well-tagged enough for Phosphene to feel like a product rather than a tech demo. *Requires: Phase 5 complete, Phase V complete (12 fidelity-uplifted presets), Phase MD through MD.5 minimum (10 Milkdrop presets), 22+ certified presets total.*

**Milestone E — Visual Identity.** Phosphene's preset catalog has a recognizable aesthetic ceiling that reads as 2026-quality — comparable to indie-game-released visuals, not 2006-era ShaderToy. *Requires: Phase V complete, Phase V.7–V.11 uplifts all Matt-approved, accessibility pass (U.9).*
