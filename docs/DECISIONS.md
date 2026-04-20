# Phosphene — Decision Log

Append-only. Each decision records the what, why, and any relevant context that would prevent a future contributor from re-litigating it. Decisions are numbered sequentially and never removed — superseded decisions are marked as such with a pointer to the replacement.

---

## D-001: Native macOS / Apple Silicon only

**Status:** Accepted

Phosphene is a native macOS app built with Swift and Metal, targeting Apple Silicon (M1+) exclusively.

**Reason:** The product depends on UMA zero-copy memory, Metal mesh shaders, MPSGraph inference, and Core Audio taps. Intel-era constraints would dilute every performance budget. No iOS, no Catalyst, no Electron, no cross-platform.

---

## D-002: Core Audio taps as default capture path

**Status:** Accepted

Default capture uses `AudioHardwareCreateProcessTap` (macOS 14.2+). ScreenCaptureKit was explored and abandoned.

**Reason:** ScreenCaptureKit (`SCStream` with `capturesAudio = true`) delivers video frames but zero audio callbacks on macOS 15+. Root cause unknown. Core Audio taps work reliably and are purpose-built for audio tapping.

**Note:** The capture architecture remains provider-oriented (`AudioInputRouter` abstracts `.systemAudio`, `.application`, `.localFile`). The provider model is preserved for future fallback paths and testability.

---

## D-003: Local-only processing

**Status:** Accepted

Audio analysis, stem separation, preference learning, and all adaptation remain on-device.

**Reason:** Privacy, latency, product simplicity. No cloud, no telemetry, no data leaves the machine.

---

## D-004: Continuous energy is the primary visual driver

**Status:** Accepted

Continuous band energy drives visual motion. Beat onsets are accent-only.

**Reason:** Beat-dominant visuals have ±80ms jitter from threshold-crossing detection. The feedback loop amplifies this jitter, making beat-dominant designs feel out of sync. Continuous energy values are perfectly synchronized by definition. This lesson required multiple failed approaches in the Electron prototype to learn. Non-negotiable.

---

## D-005: Protocol-oriented cross-module design

**Status:** Accepted

Major dependencies are injected through protocols. No singletons.

**Reason:** Testability and modularity. Every subsystem has test doubles in `Tests/TestDoubles/`.

---

## D-006: UMA shared buffers

**Status:** Accepted

All shared render/analysis buffers use `.storageModeShared`.

**Reason:** Avoid implicit copies. Preserve Apple Silicon UMA zero-copy between CPU, GPU, and ML.

---

## D-007: Runtime preset discovery

**Status:** Accepted

Presets are discovered automatically by scanning the presets directory and compiled at runtime via `device.makeLibrary(source:options:)`.

**Reason:** Eliminates manual registration. Supports hot-reload for development iteration.

---

## D-008: Playlist-first session preparation

**Status:** Accepted

When a playlist is known, Phosphene prepares a full visual session before playback starts.

**Reason:** The product's differentiator is premeditated sequencing. Preview clips are analyzed via stem separation + MIR, results cached in StemCache, and the Orchestrator plans preset selection and transition timing for the entire playlist.

---

## D-009: No CoreML dependency (MPSGraph + Accelerate)

**Status:** Accepted (replaced D-008a: CoreML for ML inference)

All ML inference uses MPSGraph (GPU, Float32) for stem separation and Accelerate/vDSP for mood classification. The CoreML framework was removed entirely in Phase 3.7.

**Reason:** CoreML's ANE path outputs Float16 requiring ~420ms conversion overhead. MPSGraph runs Float32 throughout, eliminates the conversion bottleneck, and achieves 142ms warm predict (4.4× faster than CoreML's ~620ms). CoreML also could not convert HTDemucs or Open-Unmix's full pipeline due to complex tensor ops.

---

## D-010: Open-Unmix HQ as stem separation model

**Status:** Accepted

Open-Unmix HQ (umxhq) is the stem separation model, reconstructed entirely in MPSGraph.

**Reason:** HTDemucs was first choice but fails CoreML/MPSGraph conversion due to complex tensor ops (`view_as_complex`, dynamic shape calculations). Open-Unmix's LSTM architecture converts cleanly. 172 weight tensors (135.9 MB Float32), stored as raw `.bin` files, tracked via Git LFS.

---

## D-011: iTunes Search API for preview resolution

**Status:** Accepted

Preview clip URLs are resolved via the iTunes Search API (`previewUrl` field).

**Reason:** Universal, free, no auth required, works for any track in the Apple Music catalog regardless of the user's streaming source. Rate limited at 20 req/min (handled by sliding-window limiter in PreviewResolver).

---

## D-012: MusicBrainz as free metadata backbone

**Status:** Accepted

MusicBrainz recording search provides genre tags and duration as a free, always-available metadata source.

**Reason:** No API key required. Sufficient for genre classification. Soundcharts is available as an optional commercial supplement for BPM/key/energy features.

---

## D-013: Spotify Audio Features endpoint dropped

**Status:** Accepted

Spotify is search-only for track matching. The Audio Features endpoint was deprecated for new apps (Nov 2024, returns 403).

**Reason:** External constraint. Soundcharts is the commercial replacement for audio feature data. Self-computed MIR is the authoritative source.

---

## D-014: Orchestrator as explicit scoring/policy system

**Status:** Proposed

The Orchestrator will be a scored decision model with explicit inputs (energy trajectory, section confidence, stem salience, visual fatigue, preset novelty, transition compatibility, performance cost) and testable golden-session fixtures.

**Reason:** The Orchestrator is the product's key differentiator. It cannot remain a black box or a stub. Explicit policy with curated test fixtures is the only way to catch regressions in show quality.

---

## D-015: Render graph replaces boolean capability flags

**Status:** Accepted

`RenderPass` enum and `PresetDescriptor.passes: [RenderPass]` replaced scattered boolean flags (`useFeedback`, `useMeshShader`, etc.).

**Reason:** Data-driven render loop. Extensible without adding more booleans. Backward-compatible JSON decoding via `synthesizePasses(from:)`.

---

## D-016: Warnings-as-errors via xcconfig, not command line

**Status:** Accepted

`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` is set in `PhospheneApp/Phosphene.xcconfig`, never on the `xcodebuild` command line.

**Reason:** Command-line flag propagates to SPM dependencies that compile with `-suppress-warnings`, causing driver-level conflicts.

---

## D-017: SessionState and SessionPlan live in the Session module, not Shared

**Status:** Accepted

`SessionState` (the lifecycle enum) and `SessionPlan` (the pre-session track sequence stub) are defined in `Session/SessionTypes.swift`, not in `Shared`.

**Reason:** `Shared` sits at the bottom of the dependency graph and cannot import `Session`. `TrackIdentity` — which `SessionPlan` contains — is already in `Session`. Placing `SessionState` in `Shared` would have gained nothing (only `Session` and the app layer reference it) and created a false impression that it is a general-purpose type.

**Corollary:** `SessionPlan` is deliberately minimal for now (holds `[TrackIdentity]`). The Orchestrator (Phase 4) will extend it with preset assignments and transition timing, but that extension belongs in the `Orchestrator` module, not `Session`.

---

## D-019: Stem routing warmup fallback pattern for compute presets

**Status:** Accepted

Compute kernels that route `StemFeatures` to visual parameters must handle the ~10s warmup window before live stems are available. The accepted pattern: detect zero stems via `smoothstep(0.02, 0.06, totalStemEnergy)` and mix between FeatureVector 6-band fallback values and true stem values. When total stem energy is below the lower threshold, pure FeatureVector routing applies (identical behavior to the pre-stem implementation). When above the upper threshold, full stem routing applies.

**Reason:** In ad-hoc mode and at the start of each track in session mode, `StemFeatures` is `.zero` for up to 10–15 seconds. A kernel that reads zero stems without fallback produces flat, unresponsive visuals during this window. The smoothstep crossfade makes the transition invisible — the kernel degrades gracefully to full-mix frequency analysis rather than going dark.

**Implication for new particle/compute presets:** Any preset that uses `buffer(3)` for stem routing should implement this pattern or an equivalent. The crossfade range (0.02–0.06) is intentionally narrow so the transition completes within the first few update cycles once stems arrive.

---

## D-018: SessionManager degrades to ready on any preparation failure

**Status:** Accepted

If `PlaylistConnector.connect()` throws, `SessionManager` transitions to `ready` with an empty plan. If `SessionPreparer.prepare()` completes with some failed tracks, `SessionManager` transitions to `ready` with a partial plan. The manager never becomes stuck in `connecting` or `preparing`.

**Reason:** Metadata degradation principle: Phosphene must be functional at every tier. An empty or partial session plan means the engine runs in reactive mode for uncached tracks — a worse experience than a full session, but a valid one. Surfacing a hard failure from the session lifecycle would force the UI to handle an error state that has no natural recovery path short of starting over.

**Implication for tests:** Tests that verify degradation behavior must cover both failure modes (connector failure → empty plan, resolver failure → partial plan) independently.

---

## D-020: Architecture-stays-solid for ray-march scene presets (Glass Brutalist Option A)

**Status:** Accepted

For ray-march scenes that depict identifiable architecture (corridors, rooms, structures with implied permanence), audio reactivity must NOT deform the architecture itself. Walls, pillars, beams, floors, and ceilings stay static. Music drives only the *light* in the scene (intensity, colour), the *atmosphere* (fog density), the *camera* (constant-speed dolly), and at most a single secondary deformation that reads as spatial rather than structural (Glass Brutalist's glass-fin position, which widens/narrows the open path between fins).

**Reason:** Three iterations of bass-driven beam dipping, pillar squeezing, and fin Y-stretching all produced the same complaint: the scene reads as broken or rubber. Architecture has implied permanence; visibly warping a concrete cross-beam on every kick drum collapses the spatial illusion. Real-world music reactivity in spaces (clubs, cathedrals, light shows) modulates lighting and mist, never the building. Phosphene's deferred PBR pipeline already gives us the mechanism — modulate `lightColor`, `lightIntensity`, `fogFar`, and IBL ambient, leave geometry alone.

**Implication for ray-march preset authors:** `sceneSDF` should be audio-independent or limited to a single, intentionally subtle non-architectural element. Modulation of lighting/atmosphere happens in the shared Swift render path (`drawWithRayMarch`) reading from `RayMarchPipeline.BaseSceneSnapshot` so per-frame modulation is additive on the JSON baseline. If a preset needs SDF-side modulation that material classification must agree with (e.g. Glass Brutalist's fin X-position), pass it via a free `SceneUniforms` lane that both `sceneSDF` and `sceneMaterial` read from — never re-evaluate sub-SDFs at a different shape in `sceneMaterial` than in `sceneSDF`, or material boundaries will flip at deformed edges.

---

## D-021: `sceneMaterial` receives `FeatureVector` and `SceneUniforms`

**Status:** Accepted

The shader preamble's `sceneMaterial` forward declaration is `void sceneMaterial(float3 p, int matID, constant FeatureVector& f, constant SceneUniforms& s, thread float3& albedo, thread float& roughness, thread float& metallic)`. All ray-march presets implement this signature.

**Reason:** Audio-reactive SDF deformation that only `sceneSDF` could see produced material-classification mismatches at deformed boundaries — pixels classified as glass would re-classify as concrete (and vice versa) when the per-fragment hit position fell outside the rest-shape sub-SDF that `sceneMaterial` was checking against. Passing the same `FeatureVector` and `SceneUniforms` to `sceneMaterial` lets it apply the same deformation `sceneSDF` did, eliminating boundary flips. This is a one-time preamble update; the cost is requiring all ray-march presets to declare the wider signature even if they don't use it.

---

## D-022: IBL ambient is tinted by `lightColor` so mood shifts are visible

**Status:** Accepted

`raymarch_lighting_fragment` multiplies its computed IBL ambient term by `scene.lightColor.rgb` before adding it to direct light. The same tint is applied to fog colour.

**Reason:** Indoor ray-march scenes are dominated by IBL ambient — the direct scene light only catches surfaces facing it (often a small fraction of the visible frame). Modulating only the direct light's `lightColor` (e.g. by `valence`) leaves most of the rendered pixels colour-unchanged. Multiplying the ambient by `lightColor.rgb` makes the mood-driven palette shift visible across every concrete surface, not just light-facing ones. At rest `lightColor ≈ (1, 0.95, 0.88)` so the multiply is near-identity; under modulation it propagates through the whole scene.

---

## D-023: Core Audio tap reinstall on prolonged silence

**Status:** Accepted

`AudioInputRouter` watches the `SilenceDetector` state machine. On entry to `.silent`, it schedules a tap-reinstall on a `tap-mgmt` utility queue with backoff `[3s, 10s, 30s]`. Each attempt destroys the existing tap + aggregate device and creates fresh ones for the active capture mode. Backoff resets on transition to `.active`.

**Reason:** `AudioHardwareCreateProcessTap` does not gracefully handle the source process tearing down its audio session — most commonly observed when the user scrubs to a new position in a streaming app. The tap stays alive but delivers permanent zeros. The silence detector correctly identifies this as silence (no fade, hard cut), but its native recovery path requires fresh non-silent samples on the existing tap, which never arrive when the tap is broken. Reinstalling the tap re-establishes the path to the source process. The backoff prevents thrash when silence is a real pause rather than a broken tap.

**Implication for new audio capture providers:** any provider that can fall into a "stuck silent but technically alive" state needs an analogous recovery mechanism. File playback (`InputMode.localFile`) is exempt because file playback can't get stuck this way.

---

## D-024: Mood is injected into the renderer through a dedicated path

**Status:** Accepted

`RenderPipeline.setMood(valence:arousal:)` is the only path that updates `latestFeatures.valence` / `arousal`. `RenderPipeline.setFeatures(_:)` (called from the MIR analysis pipeline at every analysis frame) explicitly preserves the most recent mood values across the overwrite.

**Reason:** Mood classification runs at a slower cadence than MIR feature extraction. Without the preserve+inject pair, MIR's per-frame `setFeatures` would zero out mood on every call. The visible symptom in earlier sessions: `features.csv` showed `valence=0` and `arousal=0` always, even though the mood classifier was running and producing real values that reached the SwiftUI overlay. Dedicated injection separates the producer cadences cleanly.

**Implication for new GPU-bound features:** any classifier output that lives on the `FeatureVector` but is produced at a different cadence than MIR needs the same pattern — a setter on `RenderPipeline` that updates only its own fields, plus preservation in `setFeatures`.

---

## D-025: SessionRecorder runs continuously from app launch

**Status:** Accepted

`SessionRecorder` (in the `Shared` module, public) is created during `VisualizerEngine.init` and writes diagnostic capture continuously to `~/Documents/phosphene_sessions/<ISO-timestamp>/` for every running session. There is no "start recording" button. The recorder is finalized via an `NSApplication.willTerminateNotification` observer so the MP4 `moov` atom is written before the process exits.

**Reason:** Phosphene problems are typically observable but not reproducible — a beat lands wrong on one passage of one track, a colour looks off during a specific moment, audio cuts out after a scrub. Asking the user to retroactively reproduce these requires guessing at conditions. Continuous recording means the data already exists when the user reports an issue. The recorder is small (~60 MB per minute, mostly video), runs on a utility-QoS queue off the realtime audio thread, and survives unit tests against known-input round-trip (CSV columns, WAV PCM samples, MP4 readability).

**Trade-off:** Disk usage. A long listening session can accumulate hundreds of MB. Acceptable for a dev/diagnostic build; if/when Phosphene ships, this should become an opt-in toggle with a configurable retention policy.

---

## D-026: Preset shaders drive from audio deviation, not absolute energy

**Status:** Accepted (Phase MV-1)

Preset shader code must drive visual parameters from deviation-from-AGC-center (`f.bassRel`, `f.bassDev`, `stems.vocalsEnergyDev`, etc.) rather than from absolute energy values (`f.bass`, `f.bassAtt`, `stems.vocalsEnergy`). Absolute thresholds like `smoothstep(0.22, 0.32, f.bass)` are explicitly disallowed in new preset code.

**Reason:** `BandEnergyProcessor` implements Milkdrop-style AGC: output = raw / runningAverage × 0.5. This inherently means raw output magnitudes depend on recent loudness history, not acoustic loudness. A kick that peaks at `bass = 0.35` during a sparse section will peak at `bass = 0.22` during a busy section because the running-average divisor rose — the kick is equally loud acoustically but AGC scaled it down. Preset v3.3 of Volumetric Lithograph hit this exact failure mode: `smoothstep(0.22, 0.32, f.bass)` missed every other kick on Love Rehab (session 2026-04-16T18-56-59Z), producing a phantom 65 BPM rhythm on a 125 BPM track. Deviation (`bass - 0.5`, or `bassRel` in the new convention) is stable across mix density because both numerator and denominator track together.

Milkdrop documents this convention in its preset authoring guide: "1 is normal, below 0.7 quiet, above 1.3 loud" — authors universally write `zoom = zoom + 0.1 * (bass - 1.0)`, never `if (bass > 0.22)`. We adopt the same convention scaled to our 0.5-centered AGC.

**Implication:** existing presets written with absolute thresholds are grandfathered but should be migrated. New preset code review must reject absolute-threshold patterns. CLAUDE.md's "Proven Audio Analysis Tuning" section documents the primitive vocabulary authors should use.

---

## D-027: Milkdrop-style per-vertex feedback warp as an opt-in render pass

**Status:** Accepted (Phase MV-2)

A new `mv_warp` render pass implements Milkdrop's per-vertex warp mesh — 32×24 grid, per-vertex UV displacement computed from preset-authored `mvWarpPerFrame()` + `mvWarpPerVertex()` functions, sampled against a persistent feedback texture. Any preset can opt in by adding `"mv_warp"` to its `passes` array.

**Reason:** Research documented in [MILKDROP_ARCHITECTURE.md](MILKDROP_ARCHITECTURE.md) established that Milkdrop's "musical feel" comes from feedback-based motion accumulation, not from rich audio analysis (Milkdrop's audio vocabulary is a strict subset of ours). 9 of 11 Phosphene presets prior to MV-2 do not use any feedback loop; ray-march presets render from scratch each frame and show only instantaneous audio state. Six iterations of Volumetric Lithograph (v3 → v4.2) attempted to make a ray-march preset feel musical via increasingly elaborate audio drivers and failed every time. The gap is mechanical: without feedback, simple audio cannot compound into organic motion.

The existing `feedback` pass is kept for Starburst/Membrane but is semantically narrower (single global zoom+rot per frame, not per-vertex spatial modulation). `mv_warp` is a new pass with a different contract, not a replacement.

**Authoring approach:** MV-2a (per-preset Metal warp functions, same pattern as `sceneSDF`/`sceneMaterial`). Faster to ship than an equation-language parser (MV-2b). An equation-language importer for real Milkdrop `.milk` presets is tracked as a potential future increment only if Metal-function authoring becomes the demonstrated blocker.

**Implication:** ray-march preset authoring pattern shifts. A scene's 3D geometry becomes static (not deformed with audio); all audio-driven motion goes through the mv_warp pass. Audio reacts to the *image* of the scene rather than its geometry. This matches Milkdrop's architecture exactly and preserves our 3D-rendering advantage.

**Scope correction (2026-04-17, see D-029):** The "ray-march preset authoring pattern shifts" framing above was over-broad. mv_warp is one of several *alternative* motion-source paradigms, not a universal requirement for ray-march presets. It does not compose with a moving world-space camera (see D-029 for the incompatibility diagnosis and the VL revert).

**Implementation notes (landed 2026-04-17, commit `c8cd558f`):**
- `MVWarpState` uses `@unchecked Sendable` because `MTLTexture` protocol has no `Sendable` conformance in Swift 6.0. The struct is only mutated under `mvWarpLock`.
- `SceneUniforms` is defined in `mvWarpPreamble` behind `#ifndef SCENE_UNIFORMS_DEFINED` so direct (non-ray-march) presets compile; the ray-march preamble wraps its own definition in the same guard to prevent redefinition for ray-march + mv_warp combos.
- `mvWarpPerFrame()` + `mvWarpPerVertex()` must be implemented in every preset that includes `mv_warp` in its passes — the engine does not provide a default (see `Shaders/MVWarp.metal` for the engine-library default implementations that `PresetLoader` falls back to via the default engine library).
- Ray-march + mv_warp handoff: `drawWithRayMarch` detects `.mvWarp` in `activePasses` and renders to `warpState.sceneTexture` instead of the drawable; `drawWithMVWarp` is called next and handles drawable presentation. `sceneAlreadyRendered: true` is passed in this case.

---

## D-028: Apple-Silicon-specific audio capabilities layer on top of MV-2, not instead of it

**Status:** Accepted and implemented (Phase MV-3, commit `329fe451`, 2026-04-17)

Richer stem metadata (per-stem onset rate, spectral centroid, attack/sustain ratio, energy slope), next-beat phase prediction, and vocal pitch tracking are implemented as additive extensions to the MV-1 + MV-2 foundation.

**Reason:** The temptation on reading Matt's research doc ("Architectural Framework for Phosphene") was to jump to neural pitch tracking (Basic Pitch / SwiftF0), chord recognition (Tonic), and HTDemucs swap. These are the high-leverage Apple-Silicon capabilities Milkdrop couldn't have in 2001. But layering them on top of a still-broken feedback architecture would produce richer data fed into the same mechanism that had failed six times. MV-1 + MV-2 establish the foundation Milkdrop proved worked; MV-3 then adds the capabilities Milkdrop can't.

Order matters because the visual checkpoints after MV-1 and MV-2 distinguish root causes. If MV-1 alone produces a noticeable improvement, the authoring-convention gap was dominant and we should audit all existing presets. If only MV-2 produces improvement, the architectural gap was dominant. If neither, we have a clearly-scoped remaining problem instead of a diffuse one.

**Implementation notes (landed 2026-04-17):**

- **StemFeatures** expanded 32→64 floats (128→256 bytes). Per-stem `{onsetRate, centroid, attackRatio, energySlope}` computed in `StemAnalyzer.computeRichFeatures()` each frame via RMS EMAs (fast τ=50ms / slow τ=500ms) and a leaky-integrator onset accumulator (τ=0.5s).

- **BeatPredictor** (`DSP` module): IIR period smoother on onset rising edges. Writes `beatPhase01` (0→1 per inter-beat interval) and `beatsUntilNext` to `FeatureVector` floats 35–36. `setBootstrapBPM()` seeds the period from metadata BPM before the first real onset. Integrated in `MIRPipeline.buildFeatureVector()`.

- **PitchTracker** (`DSP` module): YIN autocorrelation via `vDSP_dotpr` on 2048-sample windows. Critical implementation fix: the naive "find first τ below threshold" algorithm stops on the *descending slope* of the CMNDF — the correct minimum is farther right. Without the local-minimum descent step, parabolic interpolation at the crossing point extrapolates catastrophically (e.g. refinedTau → 171 for a 440 Hz input, yielding 258 Hz instead of 440 Hz). The fix: after the first sub-threshold τ, advance forward while CMNDF keeps decreasing before interpolating. This reduced pitch error from ~35 cents to <5 cents for clean tones. Writes `vocalsPitchHz`/`vocalsPitchConfidence` to `StemFeatures` floats 41–42.

- **VolumetricLithograph** updated with both signals: `beat_phase01 > 0.80` triggers an anticipatory pre-beat zoom ramp (`approachFrac × 0.004`); `vocalsPitchHz` modulates the IQ cosine palette hue ±0.15 (gated by confidence ≥ 0.6).

**Explicitly excluded from MV-3:** Basic Pitch port (unverified native availability), HTDemucs swap (Open-Unmix HQ works), Sound Analysis framework (applause detection — orthogonal to "band member" feel), chord recognition via Tonic (deferred pending MV-3c pitch tracking).

**Implication:** any future increment that adds a new audio-analysis capability should explicitly state whether it layers on the mv_warp architecture or requires architectural changes. Purely additive classifier features (new `FeatureVector` fields) are preferred over pipeline-changing ones.


---

## D-029: Preset motion sources are alternative paradigms, not composable layers

**Status:** Accepted (2026-04-17)

Each preset picks exactly one motion-source paradigm from the following catalogue. The engine supports all of them via the `passes` array, but mixing them within a single preset is either incoherent or actively broken.

| Paradigm | Motion comes from | Example presets | Passes |
|----------|-------------------|-----------------|--------|
| **Milkdrop mv_warp** | Per-vertex UV feedback accumulator — "the warp mesh is the camera" | *(future direct-fragment presets; optionally static-camera ray march)* | `mv_warp` (± `direct` / `ray_march` without camera motion) |
| **Particle system** | Compute-kernel sprite integration in world space | Starburst (Murmuration) | `feedback` + `particles` |
| **Feedback composite** | Single global zoom/rotation per frame + persistent texture | Membrane | `feedback` |
| **Ray-march camera flight** | Translating/rotating a 3D camera through an SDF scene; motion compounds via spatial traversal | VolumetricLithograph, KineticSculpture, GlassBrutalist (static variant) | `ray_march` + `post_process` (+ `ssgi`) |
| **Mesh shader animation** | GPU-authored procedural geometry evolution | FractalTree | `mesh_shader` |
| **Direct-fragment modulation** | Time + audio into a single fragment shader; no persistence | Waveform, Plasma, Nebula | `direct` |

**Reason:** The MV-2 rollout (D-027) attempted to add mv_warp on top of VolumetricLithograph's forward camera dolly. The result was severe vertical smearing at rest: mv_warp's feedback accumulator pins previous-frame pixels to UV coordinates, but the moving world-space camera re-projects those same world points to different UV coordinates each frame, so `0.96 × previous + 0.04 × current` bleeds camera-motion history across the screen. See CLAUDE.md Failed Approaches #32.

The same bug applies — more subtly — to any ray-march preset that translates or rotates its camera. It applies partially to particle systems (particles already integrate state, so stacking mv_warp over them double-integrates and smears trails into mush).

**Rule:** Paradigms may not be stacked. The only legitimate compositions are:
- `mv_warp` + static-camera `ray_march` — a 3D SDF backdrop receives Milkdrop-style 2D warp on top. Narrow use case; none implemented as of 2026-04-17.
- `ray_march` + `post_process` + `ssgi` — standard ray-march compositing (not a motion-source mix).
- `feedback` + `particles` — Starburst's original and current pattern; feedback here is a trail decay for the particle render, not an independent motion source.

**Implication for PresetLoader:** the current mutual-exclusion routing in `compileShader()` (meshShader → mvWarp → rayMarch → standard) enforces the rule by construction and should be kept. A future static-camera `ray_march + mv_warp` preset remains supported by the existing `compileMVWarpShader` branch (it already handles the ray-march variant).

**Implication for preset authors:** do not reach for `mv_warp` as a universal "add musicality" switch. Ask first what the preset's motion source is. If it's a moving camera or a particle system, mv_warp will fight it. If it's a static 2D or static-camera 3D scene with no inherent compounding, mv_warp is one valid choice (feedback and mesh-shader animation are others).

**Reverts and documentation changes:**
- Starburst.json: `["mv_warp"]` → `["feedback", "particles"]`. Stale `mvWarpPerFrame`/`mvWarpPerVertex` removed.
- VolumetricLithograph.json: `["ray_march", "post_process", "mv_warp"]` → `["ray_march", "post_process"]`. `mvWarpPerFrame`/`mvWarpPerVertex` and the unused `vl_pitchHueShift` helper removed.
- CLAUDE.md Failed Approaches #32 rewritten to describe the camera/feedback incompatibility rather than the old "ray march needs feedback" claim.
- CLAUDE.md "Do not" rule reframed from "always implement mv_warp" to "do not stack mv_warp on a moving camera."
- D-027 scope-corrected with a forward pointer to this entry.


---

## D-030: SpectralHistoryBuffer as unconditional GPU contract at buffer(5)

**Status:** Accepted (2026-04-19)

A pre-allocated `.storageModeShared` MTLBuffer (16 KB, 4096 Float32) carrying per-frame MIR history is bound unconditionally at fragment buffer index 5 in all direct-pass encoders (`drawDirect`, `drawParticleMode`, `drawSurfaceMode`). The class is `SpectralHistoryBuffer` in the Shared module; it conforms to `SpectralHistoryPublishing` for test injection.

**Layout:**
```
[0..479]    valence trail         (-1..1, raw)
[480..959]  arousal trail         (-1..1, raw)
[960..1439] beat_phase01 history  (0..1, sawtooth)
[1440..1919] bass_dev history     (0..1)
[1920..2399] vocals_pitch_norm    (0..1, log2(hz/80)/log2(10), 0=unvoiced/low confidence)
[2400]      write_head            (integer as Float, 0..479)
[2401]      samples_valid         (integer as Float, capped at 480)
[2402..4095] reserved             (zeroed; future consumers)
```

**Why:** Phosphene's MV-3 extensions (D-028) added ~26 new per-frame primitives with no real-time observability. `SessionRecorder` (D-025) captures them offline to CSV but there's no live view during preset authoring. An always-bound history ring at buffer(5) lets `instrument`-family presets render recent MIR state trivially and creates the foundation for any future preset that wants short-term history without new plumbing. 16 KB on UMA is negligible.

**Why buffer(5) and not buffer(4):** buffer(4) is already occupied by `SceneUniforms` in ray march G-buffer, lighting, and SSGI passes. Buffer(5) is the first truly unused slot across all pass types. CLAUDE.md GPU Contract documentation was wrong (listed buffer(0)=FFT, buffer(4–7)=future) — corrected in this increment.

**First consumer:** `SpectralCartograph` preset — four-panel diagnostic instrument showing FFT spectrum, deviation meters, V/A plot, and scrolling feature graphs.

**Implication:** future additions to the history layout (e.g., per-stem onset rate history) can consume slots [2402..4095] without breaking existing consumers. Ray march presets currently skip buffer(5); it is available to them if needed.


---

## D-031: Preset metadata schema extended for Orchestrator scoring (Increment 4.0)

**Status:** Accepted (2026-04-20)

Seven new fields were added to `PresetDescriptor` to give the Orchestrator (Increment 4.1) the signal it needs to make tasteful preset-selection decisions without hard-coding per-preset logic in scoring rules.

**New fields:** `visual_density`, `motion_intensity`, `color_temperature_range`, `fatigue_risk`, `transition_affordances`, `section_suitability`, `complexity_cost`.

**Why pulled forward from Phase 5.1:** The original engineering plan placed the enriched metadata schema in Phase 5.1 (Orchestrator polish) on the assumption that PresetScorer (Increment 4.1) could be prototyped against a minimal schema and extended later. In practice, building PresetScorer without the fields it scores on forces either placeholder logic or a breaking schema change immediately after. Pulling the schema forward costs a small amount of effort (back-filling 11 JSON sidecars) and eliminates the breaking change.

**Decoding contract:** Missing field → default. Malformed `fatigue_risk` string → log warning via `Logging.renderer`, use `.medium`, do not throw. This matches the existing `synthesizePasses` fallback philosophy. `complexity_cost` accepts both scalar (applied to both tiers) and nested `{"tier1": x, "tier2": y}` forms.

**Why these specific fields:**
- `visual_density` + `motion_intensity`: direct proxies for the two axes of arousal that the MoodClassifier already tracks. The Orchestrator can intersect descriptor ranges with mood targets.
- `color_temperature_range`: bridges mood-derived valence (warm/cool palette bias) to preset capability. Allows scoring without inspecting shader source.
- `fatigue_risk`: encodes the subjective reviewer observation that some presets (high-contrast, strobing) become uncomfortable over extended viewing. A cooldown penalty enforces variety.
- `transition_affordances`: hard cuts work beautifully for GlassBrutalist (stark) and VolumetricLithograph (linocut) but would feel jarring on particle or plasma presets. Encoding this prevents the Orchestrator from scheduling inappropriate transitions.
- `section_suitability`: structural section matching (ambient/buildup/peak/bridge/comedown) is the highest-leverage hook for making visual choices feel intentional rather than random.
- `complexity_cost`: tier1/tier2 device tiers reflect the M1/M2 vs M3+ performance gap for ray march presets. Excludes frame-budget breakers at scoring time rather than at runtime.

**New types:** `FatigueRisk`, `TransitionAffordance`, `SongSection` (all `String`-raw, `Codable`, `Sendable`, `Hashable`, `CaseIterable`), `ComplexityCost` (struct with custom dual-form Codable). Defined in `PresetMetadata.swift`.

**Back-fill note:** 11 JSON sidecars were back-filled. KineticSculpture's `color_temperature_range` was adjusted from spec `[0.3, 0.7]` (identical to the default) to `[0.3, 0.65]` to make the back-fill detectable by the regression test and to better reflect the slightly cooler warm-end of its metallic/glass palette.

---

## D-032: Preset scoring weights and penalty structure (Increment 4.1)

**Status:** Accepted (2026-04-20)

`DefaultPresetScorer` combines four sub-scores into a final [0, 1] total using fixed weights and two multiplicative penalties.

**Sub-score weights:** `mood = 0.30`, `tempoMotion = 0.20`, `stemAffinity = 0.25`, `sectionSuitability = 0.25`. Sum = 1.0, so `raw` is already in [0, 1] without normalisation — any sub-score is directly readable as a fraction of the total budget.

**Why mood gets the highest weight (0.30):** Mood is the single axis with the most perceptual surface area. A wrong emotional tone undermines the entire visual experience even when tempo and stem affinity are well-matched. Valence → colour temperature and arousal → visual density are the two most directly observable mismatches; together they justify the extra 5 points over the other dimensions.

**Why tempoMotion gets the lowest weight (0.20):** BPM metadata is often missing (nil in `TrackProfile`) and the scorer maps nil to neutral 0.5 to avoid penalising presets on missing data. A nil-safe neutral degrades information, so this dimension earns less influence. When BPM is available it is valuable; when absent, the other three dimensions carry the decision.

**Why stemAffinity and sectionSuitability share 0.25 each:** Both are equally important for the product's stated purpose (intentional visual sequencing). Stem affinity makes the preset feel musically responsive; section suitability makes timing feel deliberate. Equal weighting avoids one outweighing the other given the uncertainty in both.

**Multiplicative penalties:** `familyRepeatMultiplier` (0.2× for consecutive same-family) and `fatigueMultiplier` (smoothstep over 60/120/300s cooldown) are multiplicative, not additive, so they compose cleanly. A 0.2× family-repeat penalty on a 0.9 raw score gives 0.18, not 0.7 (which additive would). This ensures highly-penalised presets lose to even mediocre competitors — the intended behaviour.

**Exclusions are separate from penalties:** `excluded = true` always produces `total = 0` and populates `exclusionReason`. This keeps "why is this at zero" answerable from the breakdown: "excluded for cost" vs "penalised to near-zero by fatigue and repeat" are different problems with different remedies.

**Fatigue cooldown windows:** `.low = 60s`, `.medium = 120s`, `.high = 300s`. These are the smallest values that created observable variety in internal playlist test sessions without causing visually jarring avoidance patterns (every session felt different, no preset disappeared for so long that its return felt jarring). `smoothstep` rather than a linear ramp avoids an abrupt "fully available" cliff.

**How to apply:** The `internal static let` constants (`weightMood`, `weightTempoMotion`, `weightStemAffinity`, `weightSectionSuitability`, `familyRepeatPenalty`, `fatigueCooldown`) are the only place these values are defined — adjust there to tune globally. The `PresetScoreBreakdown` struct surfaces all sub-scores for introspection and future calibration tooling.

---

## D-033: Transition policy design — structural boundary priority and energy-scaled crossfades (Increment 4.2)

**Status:** Accepted (2026-04-20)

`DefaultTransitionPolicy` answers the "when + how" question. Two trigger paths, strict priority order.

**Structural boundary (preferred):** Fires when `StructuralPrediction.confidence ≥ 0.5` and the predicted next boundary is within 2.5 s (the `LookaheadBuffer` window). `scheduledAt` is offset before the boundary so a crossfade or morph completes exactly at it; a cut is scheduled at the boundary itself. Confidence threshold 0.5 was chosen as the midpoint of the [0, 1] range — the analyzer produces values above this for tracks with detectable periodic structure (ABAB or verse/chorus patterns), and values below for ambient or through-composed material.

**Duration-expired fallback:** Fires when `elapsedPresetTime ≥ preset.duration`. `scheduledAt = captureTime` (transition now). Confidence reports 1.0 because the trigger is deterministic, not a probabilistic prediction.

**Why structural boundary beats the timer:** Section boundaries are the musically correct moment to switch visuals. The timer fires regardless of where we are in the track structure. When both conditions are true simultaneously (preset is overdue AND a boundary is imminent), the structural path produces a less jarring result — it aligns with what the listener hears.

**Style selection:** The current preset's `transitionAffordances` constrain the palette. Within that palette, energy drives preference: above `cutEnergyThreshold = 0.7` the policy prefers `.cut` (fast, punchy — appropriate at peaks), below it prefers `.crossfade` (slow blend — appropriate for relaxed passages). Default fallback when no affordances are declared: `.crossfade`.

**Crossfade duration scaling:** Linear interpolation between `baseCrossfadeDuration = 2.0s` (energy=0) and `minCrossfadeDuration = 0.5s` (energy=1). This gives the visually desired behaviour — slow, deliberate fades during quiet passages; quick, energetic ones during peaks.

**Family-repeat avoidance is NOT in TransitionPolicy:** The `DefaultPresetScorer` already applies a 0.2× family-repeat penalty during ranking (D-032). TransitionPolicy receives a ranked list and picks from the top — no duplicate logic needed.

**`TransitionDecision` is a pure value type:** trigger, scheduledAt, style, duration, confidence, rationale. No callbacks, no side effects. Callers schedule the transition externally from the returned struct.

**How to apply:** Tune the four `static let` constants in `DefaultTransitionPolicy` (`structuralConfidenceThreshold`, `lookaheadWindow`, `baseCrossfadeDuration`, `minCrossfadeDuration`, `cutEnergyThreshold`) to adjust timing behaviour globally. The `TransitionDeciding` protocol allows injection of test doubles or alternative implementations without changing callers.


---

## D-034: Session planning as greedy forward walk (Increment 4.3)

**Status:** Accepted (2026-04-20)

`DefaultSessionPlanner` answers the pre-session question: given an ordered playlist and the full preset catalog, produce a `PlannedSession` — a sequence of (track, preset, transition) entries — before playback begins.

**Why greedy forward walk (not global optimization):** A greedy walk is O(N × catalog) and deterministic. Each position scores the full catalog given accumulated history, picks the top eligible preset, then advances. This is sufficient for the Orchestrator's core goal: variety, mood-matching, and fatigue avoidance. A global optimizer (e.g., dynamic programming over all permutations) would find occasionally better plans in edge cases but costs O(N! × catalog) and makes the plan opaque to inspection. The greedy result is already "good enough" because `DefaultPresetScorer`'s family-repeat and fatigue penalties naturally push toward variety when a diverse catalog is provided. Global optimization is a possible future enhancement — document it here so no one re-litigates it without cause.

**Why planning never blocks `ready` (extends D-018):** Session preparation already has a degradation budget — partial preparation still yields `.ready`. The planner follows the same principle: if `plan()` throws (impossible given a non-empty catalog, but defensive), `SessionManager` catches it, logs it, and leaves `plannedSession == nil`. The render loop and engine are unaffected. The plan is advisory, not required for playback.

**The synthetic-boundary trick at track changes:** Track changes are by definition section boundaries. Rather than adding a special "plan-time" code path in `DefaultTransitionPolicy`, `DefaultSessionPlanner.buildTransition` passes a `StructuralPrediction` with `predictedNextBoundary == captureTime` and `confidence == 1.0`. This causes `DefaultTransitionPolicy.evaluate()` to fire `structuralBoundary` immediately, exactly as it would during live playback at a detected section boundary. No code duplication; the real policy is exercised in both planning and playback.

**Estimated energy mapping:** `energy = clamp(0.5 + 0.4 × arousal, 0, 1)` where `arousal ∈ [-1, 1]`. Maps neutral (0) → 0.5, fully calm (-1) → 0.1, fully energetic (1) → 0.9. This drives `TransitionContext.energy` to select crossfade style and duration during planning. Live playback can override with real audio-derived energy.

**Fallback ladder:** (1) Top eligible preset (not excluded, total > 0) — normal path. (2) All excluded: cheapest-cost preset that is not the current one, plus `.noEligiblePresets` warning — covers budget-constrained situations. (3) No non-current alternative: cheapest preset regardless of identity, plus `.budgetExceeded` warning — covers degenerate single-preset catalogs. Plans are always producible given a non-empty catalog.

**The precompile closure pattern:** `DefaultSessionPlanner` does not depend on `Renderer` or `RenderPipeline`. The precompile side effect is injected as a `(@Sendable (PresetDescriptor) async throws -> Void)?` closure. This keeps the Orchestrator module free of Renderer dependencies, allowing it to be tested without a GPU context. The app layer (or `VisualizerEngine`) wires the closure to `RenderPipeline`'s JIT compilation path.

**`PlannedSession` lives in Orchestrator, not Session (D-017 corollary):** The `Session` module cannot depend on `Orchestrator` (would create a circular dependency — `Orchestrator` depends on `Session`). The `SessionManager` cannot therefore carry a `@Published var plannedSession: PlannedSession?` field directly. The integration pattern is: the app layer observes `SessionManager.state == .ready`, then calls `sessionPlanner.plan(...)` using the `StemCache` data, and stores the resulting `PlannedSession` in its own state. This is the correct layering: SessionManager owns lifecycle, the app layer owns the plan. Full wiring is Increment 4.5.

**How to apply:** `DefaultSessionPlanner.plan(tracks:catalog:deviceTier:)` is the synchronous entry point (deterministic, no async needed). `planAsync(tracks:catalog:deviceTier:)` adds preset precompilation via the injected closure. Inspect `PlannedSession.warnings` to understand any soft failures. `PlannedSession.track(at:)` and `.transition(at:)` provide O(N) playback-time lookups by session time.

## D-035: Live adaptation is a pure function over the session plan (Increment 4.5)

**Status:** Accepted (2026-04-20)

`DefaultLiveAdapter` takes the current `PlannedSession`, a live `StructuralPrediction`, and a live `EmotionalState`, and returns a `LiveAdaptation` value — a pure function with no internal state and no external reads. All mutable session state lives in `VisualizerEngine+Orchestrator`, which applies adaptations via `PlannedSession.applying(_:at:)`.

**Why conservative (at most one adaptation per call, boundary wins):** Two competing adaptations in one call would require merging transitions and overrides — a combinatorial problem that doesn't arise in practice because structural boundaries and mood divergences rarely fire simultaneously. Boundary reschedule is the safer, lower-risk operation (it moves a time, not a preset); mood override is irreversible mid-track. Separating them with a priority rule keeps each path predictable and individually testable.

**Why the boundary threshold is 5 s:** The `LookaheadBuffer` delay is 2.5 s. A deviation of 5 s (2× the buffer depth) means the live boundary is outside the range of normal jitter from the structural analyzer. Below 5 s the planner's original estimate is probably still correct; above it the live signal is clearly diverging.

**Why the override fraction cap is 40 %:** Overriding a preset after 40 % of the track has played delivers diminishing returns: fewer seconds of the new preset remain, and the visual disruption of a mid-track cut is harder to justify. 40 % is a conservative threshold — a full-track override (0 %) would be ideal, but some latency in mood convergence means 40 % gives the classifier time to stabilize before firing. This matches the "30-second preview analysis may not represent the full track" rationale from D-034.

**Why `PlannedSession.applying(_:at:)` is a public extension in `LiveAdapter.swift`:** `PlannedSession` and `PlannedTrack` have internal memberwise inits (D-034: "always build via `DefaultSessionPlanner.plan()`"). The mutation path must live in the `Orchestrator` module where internal inits are accessible. Exposing it as a `public extension PlannedSession` method keeps the controlled mutation visible, self-documenting, and callable from the app layer without leaking the underlying constructors.

**The scoring context for override candidates uses empty history:** In `evaluateMoodOverride`, both the current-preset score and the alternative scores are computed with `recentHistory: []`. This avoids re-applying session-level fatigue penalties that were already baked into the original plan, and keeps the comparison to a single "which preset fits this live mood better" question. Family-repeat and fatigue penalties are session-level concerns; live adaptation is a track-level correction.

**How to apply:** Call `VisualizerEngine.buildPlan()` when `SessionManager.state == .ready` to build and store the initial plan. During playback, call `applyLiveUpdate(trackIndex:elapsedTrackTime:boundary:mood:)` periodically from the audio analysis path (the `analysisQueue`). `currentPreset(at:)` and `currentTransition(at:)` provide thread-safe lookups for the render loop.
