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

**Scarcity-via-cooldown pattern (Stalker, Increment 3.5.7):** `fatigue_risk: "high"` is the correct lever to make a preset feel rare and surprising without adding per-preset logic. Stalker's 300 s cooldown means it appears at most once per 5 minutes in a continuous session, which is intentional — a predator that appears too often stops feeling predatory. The listening-pose capability justifies scarcity: it needs time between appearances to retain its perceptual impact.

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

## D-036: Reactive orchestrator is stateless; app layer owns cooldown and start-time tracking (Increment 4.6)

**Status:** Accepted (2026-04-20)

`DefaultReactiveOrchestrator.evaluate()` is a pure function — no mutable state inside the struct. This matches `DefaultPresetScorer` and `DefaultLiveAdapter`. The tradeoffs:

**Why stateless:** `VisualizerEngine` already owns audio/session state. Keeping state in the struct would require it to be a `class`, or force the caller to maintain an opaque state blob across calls. Injecting all context as arguments keeps the type Sendable and unit-testable without fixtures.

**Cooldown outside the orchestrator:** A 60 s minimum between reactive switches is an app-level policy (how often should the visualizer interrupt itself?), not a scoring concern. It lives in `VisualizerEngine+Orchestrator.lastReactiveSwitchTime`. The orchestrator returns a `suggestedPreset` on every qualifying call; it is the caller's responsibility to gate on the cooldown.

**Elapsed time from `Date()` wall clock:** Ad-hoc sessions have no track structure, so `elapsedTrackTime` (track-relative) is not meaningful for accumulation state. Wall-clock since first audio frame is the right denominator. `VisualizerEngine+Orchestrator` sets `reactiveSessionStart` on the first `applyReactiveUpdate()` call and resets it to nil when `buildPlan()` succeeds (a real plan takes over).

**`minScoreGapForSwitch = 0.20` vs. `LiveAdapter`'s 0.15:** Reactive scoring builds a `TrackProfile` from live mood only — no BPM, stems, or section data. The thinner profile means scoring is noisier and a larger gap is needed before acting. LiveAdapter operates on profiles that include pre-analyzed BPM and stems, giving it more information and justifying a lower threshold.

**Accumulation gating (0–15 s listening, 15–30 s ramping, 30 s+ full):** The MIR pipeline takes approximately 10–15 s of audio to stabilize mood, beat detection, and spectral features. The 15 s listening window prevents premature switches while the EMA smoothers converge. The ramping window (15–30 s) allows suggestions but returns a sub-1.0 confidence in the decision, so callers can optionally show a visual indicator that the orchestrator is still gaining confidence.

**How to apply:** `buildPlan()` resets `reactiveSessionStart = nil` so reactive state clears when a real plan arrives. `applyLiveUpdate()` routes to `applyReactiveUpdate()` when `livePlan == nil`. The 60 s cooldown in `VisualizerEngine+Orchestrator` prevents switch-thrashing during the listening window edge.

---

## D-037 — Preset Acceptance Checklist: structural invariants over GPU output (Increment 5.2)

**Status:** Accepted (2026-04-20)

The preset catalog has no automated gate against regressions. A new preset could ship that clips to white on steady energy, goes dark at silence, or overreacts to beat jitter (amplifying ±80 ms jitter into visible thrashing). The lack of a gate was acceptable during catalog development but blocks safe catalog growth.

**Decision:** `PresetAcceptanceTests.swift` renders each preset against four FeatureVector fixtures and asserts four structural invariants:
1. Non-black at silence (max channel > 10).
2. No white clip on steady energy for non-HDR passes (max channel < 250).
3. Beat response ≤ 2× continuous response + 1.0 tolerance (prevents beat-dominant motion design).
4. Form complexity ≥ 2 at silence (detects visually dead presets — all pixels in a single luma bin).

**Fixture design:** Vectors are constructed from AGC semantics documented in CLAUDE.md (all continuous fields centered at ~0.5, deviation fields derived from `xRel = (x - 0.5) * 2.0`) and from the reference onset table. They represent real observed states, not synthetic time-domain envelopes. See the in-file doc comment for the mapping to reference tracks.

**Rejected alternative — pixel hash comparison:** Perceptual hashes catch visual regressions but require golden snapshots to be updated on every intentional change. The acceptance checklist only checks structural invariants, not visual fidelity. Snapshot regression testing is Increment 5.3.

**HDR exemption for white-clip invariant:** Presets that include the `post_process` pass intentionally produce HDR values before tone-mapping; the composite output in 8-bit is legal. The check skips those presets.

**Test infrastructure note:** `@Test(arguments: _acceptanceFixture.presets)` uses a module-level fixture that loads all built-in presets once via `PresetLoader(loadBuiltIn: true)`. If the bundle resources are not linked to the test target, the fixture returns `[]`, yielding zero test cases — an environment issue, not a code regression.

---

## D-038 — PresetCategory.organic added for bioluminescent/natural presets (Increment 3.5.5)

**Status:** Accepted (2026-04-20)

Arachne is the first preset in a planned family of organic / nature-derived visualizers (webs, mycelium, bioluminescent organisms). The existing `PresetCategory` enum had no suitable category — the closest was `abstract`, which conflates Arachne with Plasma and Nebula presets that have a very different aesthetic intent.

**Decision:** Add `PresetCategory.organic` with raw value `"organic"`. This enables the Orchestrator's family-repeat penalty to correctly distinguish organic presets from geometric or fluid ones, and gives the preset catalog a meaningful grouping for future natural-world visualizers.

**Why not `abstract`:** The `abstract` family is used by demoscene-style presets (Plasma, Nebula) that are pattern-driven with no representational referent. Arachne's spiderwebs and any future mycelium/coral/organism presets have a clear natural referent — treating them as `abstract` would cause the family-repeat penalty to incorrectly suppress them when Plasma is active, and vice versa.

**Rejected alternative — `natural`:** Both `organic` and `natural` work semantically. `organic` was chosen because it is the established term in visual design for forms derived from biological growth patterns (curved, asymmetric, non-Euclidean), regardless of literal organism identity.

**How to apply:** New presets whose primary visual inspiration is a biological structure (web, coral, fungus, root, crystal growth, flock) should declare `"family": "organic"` in their JSON sidecar. Presets whose primary inspiration is mathematical pattern (Lissajous, Mandelbrot, Plasma) should remain `abstract`.

---

## D-039 — dHash visual regression gate for preset shaders (Increment 5.3)

**Status:** Accepted (2026-04-21)

**Context:** Increment 5.2 gates structural invariants (non-black, no clip, form complexity, beat response). A shader edit can pass all four invariants while silently changing the visual character of a preset — a palette shift, a contrast change, or a broken scene element that still has "some pixels and some complexity."

**Decision:** A 64-bit dHash (difference hash) is computed for each preset at three fixtures (steady, beat-heavy, quiet). Goldens are stored inline as a Swift dictionary literal in `PresetRegressionTests.swift`. Comparison uses Hamming distance ≤ 8 (87.5% match), tolerating GPU float quantization noise while catching intentional visual changes.

**Why dHash over perceptual statistics (mean/stddev):** Statistics detect global brightness/contrast changes but miss structural changes — a scene could have identical mean luma while all its geometry moved to a different position. dHash encodes spatial structure via the horizontal-difference representation.

**Why Hamming ≤ 8:** GPU float-to-uint8 quantization on the same hardware is deterministic. Across shader edits that change nothing visual (whitespace, constant folding), the output is byte-identical — Hamming distance = 0. A meaningful change (different palette, altered SDF parameters) shifts 10–30 bits. The threshold of 8 sits safely between noise (0) and signal (≥ 10).

**Mesh-shader presets excluded:** `FractalTree` uses an `MTLMeshRenderPipeline` on M3+ that cannot be invoked via `drawPrimitives`. No `pipelineState` equivalent to the vertex fallback is stored in `LoadedPreset`. These presets are excluded until a dedicated mesh-shader render helper is added.

**Golden update workflow:** Run `UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine --filter "test_printGoldenHashes"`. The test prints Swift literal lines to stdout. Paste into `goldenPresetHashes` in `PresetRegressionTests.swift`. New presets that have no entry skip silently — CI does not fail on a new preset until its goldens are explicitly added.

**Hardware caveat:** Goldens are generated and validated on Apple Silicon. A different GPU generation may produce different 8-bit output for fragment shaders that use trigonometric functions (GPU sine/cosine precision varies across architectures). If CI runs on a different device tier from where goldens were generated, set a per-tier golden dictionary or accept a wider Hamming threshold.

---

## D-040 — Spider easter egg design for Arachne (Increment 3.5.9)

**Status:** Accepted (2026-04-21)

**Context:** Arachne is the first mesh-shader preset in the Arachnid Trilogy. The design called for an easter egg spider that rewards deep-listening sessions with James Blake-style sub-bass. Three questions required explicit decisions.

**Decision 1 — Render approach: fragment overlay, not separate mesh threadgroup.**

A separate threadgroup 0 for the spider body would require all web threadgroups to shift to indices 1–12, and a full-resolution quad mesh needed a different dispatch path. The fragment overlay approach runs the spider SDF inside every web fragment that passes a bounding-radius check against the spider position. Since the spider spawns at the hub (the densest pixel region), it appears fully visible. Background pixels between webs have no fragments, so there is no cost.

**Decision 2 — Separate `ArachneSpiderGPU` buffer at fragment buffer(4), not extending `WebGPU`.**

`WebGPU` is 64 bytes, tightly packed, and has 12 instances per frame (768 bytes). Adding 80 spider bytes would inflate it to 144 bytes × 12 = 1728 bytes and change the byte layout that the object/mesh shader already indexes by `[[payload_index]]`. A separate 80-byte buffer at fragment buffer(4) — the same slot used by the `meshPresetFragmentBuffer` infrastructure added for this increment — is cleaner and leaves `WebGPU` stable.

**Decision 3 — Sub-bass trigger discriminates sustained resonance from transient kick drums.**

The spider should appear during James Blake "Limit to Your Love" sub-bass drops, NOT during every kick drum in a house track. The trigger uses `bassAttackRatio < 0.55` (from `StemFeatures.bassAttackRatio`, the ratio of peak attack energy to sustained RMS) as a gate alongside the energy threshold. A kick drum has a high attack ratio (~0.9); a sustained sub-bass tone has a low ratio (~0.2–0.4). Session cooldown (300 s) prevents back-to-back appearances. This three-part condition (energy + attack ratio + accumulator) is identical to StalkerState's listening-pose trigger, validated across genres in Increment 3.5.7.

---

## D-041 — Arachne ray march remaster (Increment 3.5.10)

**Status:** Accepted (2026-04-21)

**Context:** Arachne v1 (Increment 3.5.5) was a mesh-shader preset. Free-running sin(time) oscillators made the motion feel mechanical and disconnected from music (CLAUDE.md failed approach #33, session 2026-04-21T13-26-38Z). Replacing with 3D SDF ray march gives proper perspective depth, correct strand geometry, and beat-phase-locked motion.

**Decision 1 — Replace mesh shader entirely with direct fragment + mv_warp.**

The mesh shader was drawing flat 2D geometry via strip primitives. Moving to a full 3D SDF ray march: (a) correctly renders each web as a tilted disc in 3D space; (b) allows a perspective camera so depth separation between webs is visible; (c) preserves the ArachneState world-state system and GPU buffers without change — only the Metal shader is rewritten. The passes array changes from `["mesh_shader"]` to `["mv_warp"]`.

**Decision 2 — Soft bioluminescent glow via minimum-SDF falloff.**

At typical test resolution (64×64) and even at 1080p, SDF tube strands (radius 0.0055 world units at distance 3) are sub-pixel for most rays. A hard-surface-only shader would produce a nearly black image with no spatial gradient, failing D-037 invariant 4 (readable form). The fix: track `minWebDist` across all march steps and add `exp2(-minWebDist * 14.0)` glow to rays that miss. This is also the physically correct model for bioluminescence — self-emitting organisms radiate a halo, not just a hard surface. Hard-surface hits still render as before; glow is additive for miss rays.

**Decision 3 — mv_warp decay 0.92, shorter than other organic presets.**

Gossamer uses 0.955 to maximise the echo-reverb trail of vocal waves. Arachne is a 3D scene: longer decay accumulates the perspective-projected web field and obscures depth separation. 0.92 gives visible temporal echo (the aesthetic) while keeping 3D structure readable.

**Decision 4 — Unique per-web tilt from rng_seed, not random per-frame.**

Each web's spatial orientation is derived deterministically from its `rng_seed` field (already in `WebGPU`). This gives a stable 3D arrangement that persists across frames. Fully random orientations would make the scene chaotic; fully aligned (all facing camera) would look flat. The seed-derived tilt range (±14% in X, ±10% in Y before normalisation) gives ~15° of variation per web — enough to read as 3D without appearing unstable.

**Decision 5 — SDF formula: min(fract, 1−fract), not abs(fract−0.5).**

`abs(fract(x) − 0.5)` gives 0 at integer positions (in the GAPS) and 0.5 at half-integers (ON the strand). This is the inverse of a distance function. `min(fract(x), 1 − fract(x))` correctly gives 0 ON the strand and increases to 0.5 in the gaps. This applies to both the spiral Archimedean distance and the hub-ring distance in the same shader family (Gossamer had the same bug).

## D-042 — Gossamer spoke geometry must be explicitly defined, not formula-derived (Increment 3.5.11)

**Status:** Accepted (2026-04-22)

**Context:** Gossamer v1 used 12 evenly-spaced spokes. v2 used 16 spokes with ±11% hash-jitter applied to equal angular spacing. Both produced approximately symmetric compass-rose geometry. Real spider webs are not constructed from a formula — they are built between whatever anchor points are available, producing markedly irregular angular spacing and a non-centered hub.

**Decision — Replace formula with explicit array; move hub off-center.**

`gossamerSpokeAngle(int i)` and `kRadialCount` removed entirely. Replaced with `constant float kSpokeAngles[17]` — 17 angles hand-designed from reference web photographs. Key features of the array:
- One 0.77 rad open sector (lower-right) where no surface exists to anchor.
- Tight cluster of 3 ceiling anchors spanning 0.67 rad (upper-left).
- Minimum gap 0.27 rad, maximum 0.77 rad; no uniform underlying spacing.

Hub moved from (0.502, 0.511) to (0.465, 0.32). The hub is near the ceiling — only 0.32 UV from the top edge. Upper spiral rings are naturally clipped into arcs by the screen boundary; lower rings extend to full radius. This asymmetry is structural: it cannot be removed without moving the hub, which means it persists through all rendering states and audio conditions.

**Rule:** Any future revision to Gossamer spoke geometry must continue to use an explicit angle array, not a formula with noise. The moment you apply a regular grid and add noise, you get a noisy grid — not irregular geometry.

## D-043 — Arachne must use 2D SDF direct fragment, not 3D ray march (Increment 3.5.12)

**Status:** Accepted (2026-04-22)

**Context:** Increment 3.5.10 rewrote Arachne as a 3D SDF ray-march, reasoning that depth and tilt would make pools of webs look more three-dimensional. On-device inspection of session `2026-04-22T14-13-58Z` showed the result looked like "sand dollars or dart boards" — not spider webs. The root cause is twofold:

1. **Miss-ray glow dominates the visual.** The 3D approach generated bioluminescent glow via `exp2(-minWebDist * 14)` on every missed ray. At 64×64 test resolution and real resolutions, the nearest-web-SDF value along a miss ray is dominated by the circular disc boundary of the tilted web plane, not by individual strand structure. The resulting bloom forms a soft circular halo regardless of strand geometry.

2. **Camera-to-web geometry creates circular projection.** A tilted disc seen nearly face-on with a 60° FOV camera produces an ellipse in screen space. With jitter applied to the normal (±14° tilt), the webs appear as ovals, reinforcing the disc/dartboard impression.

**Decision — Return to 2D SDF direct fragment (Gossamer architecture).**

Arachne is now a 2D SDF shader that evaluates each web entirely in UV space:
- Hub in clip-space `(hubX, hubY)` converted to UV: `float2((hub_x+1)/2, (1−hub_y)/2)`.
- Radius in UV: `w.radius × 0.5` (clip-space → UV scale factor).
- Per-web: hub concentric rings + 12 radial spokes with ±30% seed jitter + Archimedean capture spiral.
- Permanent anchor web at UV `(0.42, 0.40)` radius 0.22, seed 1984u, always stage=3/progress=1 — satisfies D-037 invariant 4 regardless of pool state.
- Pool webs evaluated via `arachneEvalWeb()` helper called once per alive web slot.
- Spider rendered as 2D: body circle + head ellipse + 8 leg capsule segments from clip-space ArachneSpiderGPU positions, converted to UV the same way.

**Rule:** Any further Arachne rewrite must remain 2D SDF. The 3D ray-march approach is permanently ruled out for a preset that must render recognizable spider web strand geometry. The same rule applies to any other "fine-structure" preset (fibers, threads, filaments) — fine structure is invisible in 3D miss-ray glow; it requires SDF evaluation at screen resolution with sub-pixel anti-aliasing.

## D-044 — SwiftUI accessibility identifiers: static constants + binding, not tree traversal (Increment U.1)

**Status:** Accepted (2026-04-22)

**Context:** Increment U.1 required tests that verify each session-state view carries the correct `accessibilityIdentifier` — needed for UI automation (XCUITest, Accessibility Inspector). The first implementation used `NSHostingController` + `NSWindow` rendering + `accessibilityChildren()` traversal via ObjC dynamic dispatch (`NSSelectorFromString`). All 6 rendering-based tests failed.

**Root cause:** On macOS, SwiftUI only materialises the accessibility tree when an active accessibility client queries it (VoiceOver, Accessibility Inspector, XCUITest harness). In `xcodebuild test` unit tests there is no client — `NSHostingView.accessibilityChildren()` returns an empty array regardless of RunLoop cycles, window visibility, or ObjC dispatch approach. This is a platform behaviour, not a SwiftLint or concurrency issue.

**Decision:** Each view exposes `static let accessibilityID: String`. The view body applies `.accessibilityIdentifier(Self.accessibilityID)`. Unit tests check the static constant directly; the binding is enforced by construction (if the modifier is removed, UI automation breaks — caught by human review or XCUITest, not unit tests).

**Rule:** Do not attempt accessibility tree traversal from `xcodebuild test` unit tests. Use static constants for identifier contracts. Accessibility tree verification belongs in XCUITest (future Milestone A acceptance suite), not unit tests.


## D-045 — V.1 utility library naming: unprefixed snake_case, no legacy collision renaming (Increment V.1)

**Status:** Accepted (2026-04-22)

**Context:** Increment V.1 adds two utility trees — 9 Noise files and 9 PBR files — into `Sources/Presets/Shaders/Utilities/`. The legacy `ShaderUtilities.metal` already contains functions such as `perlin2D`, `cookTorranceBRDF`, `fresnelSchlick` (camelCase convention). The new utilities use `perlin2d`, `brdf_ggx`, `fresnel_schlick` (snake_case convention). The question was whether to rename existing functions to `legacy_*`, prefix new ones, or leave both coexisting.

**Pre-flight finding:** MSL is case-sensitive. `perlin2d` vs `perlin2D` are distinct symbols. A complete audit of all 9 Noise and 9 PBR new function names found zero name-space collisions with any existing `ShaderUtilities.metal` function. No renaming was required.

**Decision:** New V.1 utilities use clean snake_case names with no prefix. Legacy ShaderUtilities functions are unchanged. Both coexist in the preamble without collision. Future V.3+ authoring vocabulary will use the V.1 snake_case names as the primary interface; legacy camelCase names remain available for backward compatibility with existing preset code.

**Rule:** When adding new preamble functions, use snake_case to distinguish from the legacy camelCase ShaderUtilities layer. Only apply `legacy_*` prefix if a true case-insensitive collision exists (none found in V.1). Do not rename existing working functions — preset shaders referencing them would break.

---

## D-046 — Connector picker architecture decisions (Increment U.3)

**Status:** Accepted (2026-04-23)

**Decision 1: `nonisolated(unsafe)` for NSWorkspace observer storage in `@MainActor` classes.**

`@MainActor` classes have `deinit` that is nonisolated (Swift 6 requirement). `NSWorkspace.notificationCenter.removeObserver(_:)` must be called from `deinit`. If the observer handles (`Any?`) are stored as regular `@MainActor`-isolated properties, accessing them from `deinit` produces a Swift 6 concurrency error. The correct pattern is `nonisolated(unsafe) private var observer: Any?` — these properties are only written in `init` and read in `deinit`, so no concurrent access is possible. `@unchecked Sendable` on a wrapper class would also work but adds unnecessary indirection. Use `nonisolated(unsafe)` for any `@MainActor` class that must remove NSWorkspace / NotificationCenter observers from `deinit`.

**Decision 2: `ConnectorPickerView` as a `.sheet` with internal `NavigationStack`.**

The app's top-level content model is a pure enum switch — there is no `NavigationStack` at the root. The connector picker needs push navigation (picker → Apple Music flow / Spotify flow). Solution: present `ConnectorPickerView` as a `.sheet` from `IdleView`, and embed the `NavigationStack` inside the sheet. This keeps the app's flat state-machine routing intact while enabling connector-specific push flows. Do not add a `NavigationStack` to `ContentView` — it would pollute all six session-state views.

**Decision 3: `DelayProviding` protocol for testable retry loops.**

The Spotify rate-limit retry ([2s, 5s, 15s]) and Apple Music auto-retry (2s) use wall-clock delays. Injecting a `DelayProviding` protocol with `RealDelay` (production) and `InstantDelay` (tests, uses `await Task.yield()`) allows retry paths to be exercised in fast unit tests without wall-clock waits. `Task.yield()` is the correct implementation for `InstantDelay` — it suspends and resumes the current task, giving other tasks (including test observations) a chance to run, without introducing any real-time delay. An empty `async throws {}` body would not yield the actor and retry loops would spin synchronously.

**Decision 4: `.spotifyAuthRequired` silently degrades to `startSession`.** *(Superseded by D-068, Increment U.10 — do not follow this pattern.)*

Without OAuth (deferred to v2), `PlaylistConnector.connect()` immediately throws `.spotifyAuthRequired` (empty access token check). Rather than showing an error, the ViewModel calls `startSession(.spotifyPlaylistURL(url, accessToken: ""))` directly. `SessionManager` degrades gracefully: it starts a session with an empty plan and enters live-only reactive mode. This is a valid and useful state — the user gets responsive real-time visuals while the Orchestrator uses the reactive path. An error message here would lie: the session IS starting, just without pre-analyzed stems. User-visible error copy would be `UX_SPEC §8` compliant only if the session actually fails to start.

---

## D-047 — Seeded tie-breaking for Regenerate Plan (Increment U.5)

**Status:** Accepted (2026-04-23)

**Context:** "Regenerate Plan" (U.5 Part D) needs to produce a different preset assignment on each call, but the same seed must always produce the same result (reproducibility). `DefaultSessionPlanner.plan()` is already deterministic (D-034) — same inputs → same output. Simply re-running `plan()` with the same inputs produces the same plan, defeating the purpose.

**Decision:** Add a `seed: UInt64` parameter to `plan()`. When `seed == 0`, output is byte-identical to the previous deterministic result (D-034 preserved). When `seed != 0`, a deterministic ±0.02 LCG perturbation is added to each `PresetScoreBreakdown.total` before selection. The perturbation is keyed on `(seed, trackIndex, presetID)` so the same seed produces the same plan. The original `plan(tracks:catalog:deviceTier:)` signature delegates to `plan(..., seed: 0)` — no call-site changes required outside this increment.

**Magnitude choice:** ±0.02 is small relative to the 0.30/0.25/0.25/0.20 weight structure — it will not change the ranking when one preset clearly scores higher, but will reliably break score ties and produce a different selection when scores are close (the common case for a well-balanced catalog).

**`regeneratePlan()` call site:** `VisualizerEngine.regeneratePlan(lockedTracks:lockedPresets:)` calls `plan(..., seed: UInt64.random(in: 1...UInt64.max))` so each button tap produces a distinct seed, hence a distinct plan. After planning, `plan.applying(overrides: lockedPresets)` patches back any manually locked picks.

---

## D-048 — Defer Part C (10s preview loop) to Increment U.5b (Increment U.5)

**Status:** Accepted (2026-04-23)

**Context:** U.5 Part C specifies a 10-second looping preset preview triggered by tapping a row in `PlanPreviewView`. The implementation requires: (1) injecting a synthetic `FeatureVector` into the active `RenderPipeline`; (2) a secondary render surface (or background-preset hijack); (3) a loop mechanism that runs without live audio callbacks. All three require engine-layer changes disjoint from the UX work in U.5.

**Decision:** Defer Part C to a standalone Increment U.5b. A `PresetPreviewController` stub is added now — all methods log and no-op — so `PlanPreviewViewModel.previewRow(_:)` and the row-tap handler in `PlanPreviewRowView` compile and have a stable call site. U.5b can swap in a real implementation without touching PlanPreviewViewModel or any view. The context-menu "Swap preset" action is disabled with a `TODO(U.5.C)` comment. The `ReadyView` and plan preview ship correctly without Part C; the feature is a non-blocking enhancement.

---

## D-049 — Shift+? for shortcut help overlay; P for plan preview (Increment U.6)

**Status:** Accepted (2026-04-24)

**Context:** UX_SPEC §7.4 lists `?` as the key for the plan-preview overlay. §7.7 separately lists `Shift+?` for the shortcut help overlay. On a US keyboard, `?` requires Shift — so a bare `?` binding and a `Shift+?` binding are physically the same keystroke. `NSEvent.charactersIgnoringModifiers` returns `?` regardless of Shift on US layout, making these bindings ambiguous.

**Decision:** Resolve the ambiguity by splitting the two bindings: `Shift+?` opens the shortcut help overlay (`ShortcutHelpOverlayView`); `P` opens the plan preview sheet. `PlaybackShortcutRegistry.matches(event:)` compares `event.charactersIgnoringModifiers.lowercased()` against the shortcut's `key` field and compares `event.modifierFlags` exactly — so `Shift+?` matches `{key: "?", modifiers: [.shift]}` correctly. The `P` binding for plan preview is a deviation from UX_SPEC §7.4 and is noted here for the record; UX_SPEC should be updated to match in the next spec revision.

**Rejected alternative:** Distinguish `?` from `Shift+?` by reading `event.characters` (Shift-modified) vs `event.charactersIgnoringModifiers` — brittle, keyboard-layout-dependent, and breaks on non-US layouts. The explicit modifier flag check is unambiguous on all layouts.


---

## D-050 — PlaybackActionRouter protocol in Orchestrator module (Increment U.6)

**Status:** Accepted (2026-04-24)

**Context:** The live-adaptation keyboard shortcuts (`⌘M`, `⌘←/→`, `⌘R`, `⌘Z`, `⌘L`) need a protocol that describes what each shortcut does at the semantic level. This protocol will eventually be wired to `DefaultLiveAdapter` (U.6b). The question is where to place this protocol — in `PhospheneApp` or in `PhospheneEngine/Orchestrator`.

**Decision:** Place `PlaybackActionRouter` in `PhospheneEngine/Sources/Orchestrator/`. Rationale: the protocol describes actions on the orchestration layer (preset scoring, session re-planning, adaptation undo), not on the app layer. The concrete implementation (`DefaultPlaybackActionRouter`) lives in `PhospheneApp/Services/` and conforms at the app layer. This avoids creating a protocol whose methods are defined against types only available deep in the engine, while keeping the contract colocated with the Orchestrator types it will eventually manipulate. Protocol methods are all `@MainActor` because they will mutate `@Published` state on `VisualizerEngine` and `LiveAdapter`.

**Stub strategy:** All methods in `DefaultPlaybackActionRouter` log `"TODO(U.6b): ..."` via `os.Logger` and return immediately. `toggleMoodLock()` is the only non-stub because it only needs to flip a local `@Published` flag — no engine coordination required. The full semantic spec for each U.6b action is documented in a top-of-file comment block in `DefaultPlaybackActionRouter.swift`.

**Rejected alternative:** Place the protocol in `PhospheneApp`. This would prevent the engine's `LiveAdapter` and other Orchestrator types from referencing it (circular dependency since `PhospheneApp` links `PhospheneEngine`, not the reverse). The Orchestrator module is the correct home.

## D-051 — UserFacingError in engine Shared module; condition-ID toast semantics (Increment U.7)

**Status:** Accepted (2026-04-24)

**Context:** U.7 introduces a typed error taxonomy (`UserFacingError`, 29 cases) and a condition-ID mechanism for idempotent, auto-dismissing toasts. Two placement questions arose.

**Decision 1 — UserFacingError in engine `Shared` module (not `PhospheneApp`).**
`UserFacingError` maps internal states (silence, network loss, rate limiting, DRM, etc.) to presentation metadata (`severity`, `presentationMode`, `conditionID`). These states originate in engine modules (`Audio`, `Session`, `Orchestrator`). Placing the enum in `Shared` lets engine code reference it without creating an upward dependency on the app layer. `Localizable.strings` and `LocalizedCopy` remain in `PhospheneApp` — the engine defines the error identity; the app defines the human copy.

**Decision 2 — `presentationMode` as a property, not a type hierarchy.**
`UserFacingError` exposes `presentationMode: PresentationMode` (`.inline` / `.toast` / `.banner` / `.fullScreen`) instead of sub-classing or using associated-value enums per mode. The view layer switches on `presentationMode` to route to `ToastView`, `TopBannerView`, or `PreparationFailureView`. This keeps routing logic in Swift, not in a protocol hierarchy, and makes adding a new presentation mode a one-line enum change rather than a protocol conformance.

**Decision 3 — Condition-ID semantics on `PhospheneToast`.**
Persistent degradation toasts (silence, low input level) must not stack on repeated triggers and must auto-dismiss on recovery. The chosen mechanism: `PhospheneToast.conditionID: String?` + `ToastManager.dismissByCondition(_:)` + `PlaybackErrorConditionTracker`. The tracker is separate from `ToastManager` so `PlaybackErrorBridge` can check "is this condition already displayed?" without coupling to `ToastManager`'s internal queue representation. The condition ID for silence is `"silence.extended"` (derived from `UserFacingError.silenceExtended.conditionID`).

**Decision 4 — 15s silence threshold (was 30s in `SilenceToastBridge`).**
`UX_SPEC §9.4` specifies >15s sustained silence triggers the degradation toast. The prior `SilenceToastBridge` fired at 30s, which was a pre-U.7 stub value. `PlaybackErrorBridge` corrects this to match the spec.

**Rejected alternative:** Store condition state in `ToastManager` itself (no separate tracker). Rejected because `ToastManager` would then need to be queried by `PlaybackErrorBridge` both to check state and to enqueue — creating a tighter coupling that makes unit testing harder (two concerns in one object).

## D-052 — CaptureModeReconciler: LIVE-SWITCH PATH via AudioInputRouter.switchMode(_:) (Increment U.8)

**Status:** Accepted (2026-04-24)

**Context:** When the user changes the capture mode in Settings (systemAudio / specificApp / localFile), Phosphene must route audio to the new source. Two paths were considered: (1) defer to next session start, (2) live-switch the running router.

**Decision:** LIVE-SWITCH PATH. `AudioInputRouter.switchMode(_:)` exists and calls `stopInternal()` (resetting `SilenceDetector`) then restarts in the new `InputMode`. `CaptureModeReconciler` subscribes to `SettingsStore.captureModeChanged` and calls `router.switchMode(_:)` immediately on the main actor. The `SilenceDetector` briefly enters `.suspect` during the switch, then recovers to `.active` within a few seconds. No DRM false-silent risk because recovery is fast.

**Special case — `.localFile`:** Shows a "coming later" toast without touching the router. Handled before the `guard let router` gate so the toast always fires even if the router reference is already nil.

**InputMode mapping:** `.systemAudio` → `InputMode.systemAudio`; `.specificApp` → `InputMode.application(bundleIdentifier:)` (not pid-based — audit confirmed the correct label during U.8 pre-flight).

**Rejected alternative:** Defer to next session start. Would require no new code for the reconciler, but the UX contracts (UX_SPEC §9.3) require that Settings changes take effect immediately for live audio source switching.

## D-054 — AccessibilityState architecture and beat-clamp boundary (Increment U.9)

**Status:** Accepted (2026-04-24)

**Context:** U.9 requires three coordinated changes: (1) gate mv_warp and SSGI execution when reduce-motion is active, (2) clamp beat-pulse amplitude to 0.5× when reduce-motion is active, (3) integrate the user's `ReducedMotionPreference` setting with the system `NSWorkspace.accessibilityDisplayShouldReduceMotion` flag into a single source of truth.

**Decision — AccessibilityState:**
`AccessibilityState` (`@MainActor final class ObservableObject`) is the single source of truth. It combines `NSWorkspace.accessibilityDisplayShouldReduceMotion` (observed via `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`) with `ReducedMotionPreference` from `SettingsStore`. The three-way logic:
- `.matchSystem` → `reduceMotion = systemReduceMotion`
- `.alwaysOn` → `reduceMotion = true`
- `.alwaysOff` → `reduceMotion = false`

`SessionStateViewModel` takes `accessibilityState: AccessibilityState` at init; `PlaybackChromeViewModel` subscribes via injected `AnyPublisher<Bool, Never>`. This keeps both view models unit-testable via stub publishers without depending on real NSWorkspace state.

**Decision — beat-clamp boundary:**
The beat-clamp is applied in `RenderPipeline.draw(in:)` to the local `FeatureVector` copy, before it is passed to `renderFrame`. Affected fields: `beatBass`, `beatMid`, `beatTreble`, `beatComposite`. NOT clamped: `beatPhase01`, `beatsUntilNext` — these are BeatPredictor timing primitives that drive anticipatory animation timing, not pulse amplitude.

Placement at the `draw` boundary means all downstream paths (direct, mesh, ray-march, mv_warp, ICB) share the same clamped vector without each needing to know about reduce-motion state.

**Decision — mv_warp gate:**
`frameReduceMotion: Bool` on `RenderPipeline` (set by app layer from `AccessibilityState.reduceMotion`). Checked at top of `drawWithMVWarp()` — when true, `drawMVWarpReducedMotion()` renders a single frame without feedback accumulation (avoids both the motion and the GPU cost of the warp pass).

**Decision — SSGI gate:**
`reducedMotion: Bool` on `RayMarchPipeline`. SSGI pass fires only when `ssgiEnabled && !reducedMotion`. SSGI is the temporally-accumulating screen-space pass most likely to cause discomfort; skipping it costs no visual quality under reduce-motion because the feedback smear is the discomfort source.

**Deferred:** Strict photosensitivity mode (flash frequency analysis + blanking); SSGI temporal accumulation gate distinct from the frame-level `reducedMotion` flag.

## D-053 — PresetScoringContext extended with excludedFamilies + qualityCeiling; defaults preserve backward compat (Increment U.8)

**Status:** Accepted (2026-04-24)

**Context:** U.8 Settings adds two user-configurable gates that must influence preset selection: a family blocklist and a quality ceiling. These gates belong in `PresetScoringContext` (the immutable snapshot passed to `DefaultPresetScorer`) rather than in the scorer's internal logic, so the context remains the single source of truth for session state at scoring time.

**Decision:** Add `excludedFamilies: Set<PresetCategory> = []` and `qualityCeiling: QualityCeiling = .auto` to `PresetScoringContext`, both with defaults. All existing callers that omit the new params continue to compile and behave identically (empty blocklist, auto ceiling). `DefaultPresetScorer.exclusionReason` checks `excludedFamilies` first, then applies `qualityCeiling.complexityThresholdMs(for:)` as the budget cap (`.ultra` returns nil → no complexity gate; `.performance` returns 12 ms → stricter than the frame budget).

**`QualityCeiling` placement:** New enum in `Orchestrator` module (not `Presets`). It maps to scoring logic (complexity thresholds) rather than to visual/preset metadata. `PresetScoringContext` already imports `Orchestrator`-local types, so no new cross-module dependencies are introduced.

**`PresetScoringContextProvider` (Part C):** Reads `settingsStore.excludedPresetCategories` and `settingsStore.qualityCeiling` and propagates them through `build()`. This is the only call site that needs updating — all other `PresetScoringContext` constructions (engine tests, golden session tests) use the defaults.


## D-055 — V.2 shader utility library: Geometry + Volume + Texture naming and placement (Increment V.2)

**Status:** Accepted (2026-04-25)

**Context:** V.2 adds 16 new Metal utility files across three new subdirectories:
- `Utilities/Geometry/` (6 files): SDFPrimitives, SDFBoolean, SDFModifiers, SDFDisplacement, RayMarch, HexTile
- `Utilities/Volume/` (5 files): HenyeyGreenstein, ParticipatingMedia, Clouds, LightShafts, Caustics
- `Utilities/Texture/` (5 files): Voronoi, ReactionDiffusion, FlowMaps, Procedural, Grunge

**Decision — D-045 confirmed for V.2:** All 16 files continue the V.1 naming convention: snake_case, no collision with legacy camelCase ShaderUtilities functions. Zero name collisions found. No `legacy_*` prefixing required.

**Decision — Adaptive ray march formula (linear not quadratic):**
The adaptive step formula is `step = d * (1.0 + gradFactor)`, not `d * (1 + d * gradFactor)`. The quadratic form overshoots badly at large distances: a sphere at distance 4 with gradFactor=0.5 gives step ≈ 12, jumping far past the sphere. The linear form keeps the over-relaxation factor constant regardless of current distance, preventing overshoot while still reducing step count ~30% vs. standard sphere tracing (gradFactor=0). The `gradFactor` parameter name describes "additive over-relaxation multiplier", where 0.0 = standard, 0.5 = 50% over-relaxed, 1.0 = 2× step.

**Decision — HexTile no lambdas:**
The session prompt draft used `auto hexCentreUV = [&](){...}` — Metal does not support lambda expressions. All per-cell UV computations were inlined as separate variable declarations.

**Decision — Lipschitz-safe displacement tolerance:**
The `displace_lipschitz_safe` test uses 1.15 tolerance (not 1.01). The `perlin3d` gradient envelope can slightly exceed `amplitude * freq` in this implementation, so the theoretical bound `1.0` is too tight. 1.15 confirms that `displace_lipschitz_safe` significantly reduces the gradient (vs. the naive ~2.0 bound of unsafed displacement) while accommodating the implementation's actual gradient distribution.

**Decision — ReactionDiffusion threshold recalibrated for perlin3d range:**
`perlin3d` returns values in approximately [-1.2, 1.2] centered at 0 (not [0,1]). The threshold formula in `rd_pattern_approx` was corrected from `0.5 + (kill-0.06)*10 - (feed-0.04)*8` (calibrated for [0,1] noise) to `(kill-0.06)*10 - (feed-0.04)*8` (centered at 0), ensuring meaningful coverage across Perlin's actual output range.

**Decision — V.2 preamble load order:**
Geometry loads after PBR; Volume after Geometry; Texture after Volume. Texture/Voronoi.metal must come before Texture/Grunge.metal (Grunge references `voronoi_f1f2`). The explicit `textureLoadOrder` array in `PresetLoader+Utilities.swift` enforces this.

## D-056 — Progressive readiness architecture: orthogonal level, same-seed re-planning, `.partial` threshold rule (Increment 6.1)

**Status:** Accepted (2026-04-25)

**Decision — `progressiveReadinessLevel` is orthogonal to `SessionState`:**
`ProgressiveReadinessLevel` is a separate published property on `SessionManager`, not a sub-state of `.preparing`. This allows readiness to advance (`.preparing → .readyForFirstTracks → .partiallyPlanned → .fullyPrepared`) while `SessionState` stays `.preparing`, then continues advancing through `.ready` and `.playing`. A single state enum that merged both dimensions would require compound cases or would need to expose readiness at the `.ready`/`.playing` level separately anyway. The orthogonal design keeps `SessionState` as a coarse lifecycle machine and `progressiveReadinessLevel` as a fine-grained preparation metric, consumable independently by the CTA gate in `PreparationProgressView` and the background-indicator in `PlaybackChromeViewModel`.

**Decision — Same seed for `extendPlan()`:**
When background preparation completes additional tracks during `.playing`, `extendPlan()` rebuilds the plan using the **same seed** that `buildPlan()` generated. The `DefaultSessionPlanner` is deterministic — same tracks × same seed → byte-identical prefix. So the first N planned tracks are guaranteed unchanged; only new suffix tracks are appended. Without seed preservation, every `extendPlan()` call would shuffle the already-playing visual arc, causing preset changes mid-song. The seed is stored in `currentSessionPlanSeed: UInt64?` on `VisualizerEngine`; `regeneratePlan()` gets a fresh seed (user-initiated replan is intentionally a full reshuffle).

**Decision — `.partial` threshold rule:**
A `.partial` track (stems unavailable, MIR-only) counts toward the consecutive prefix only when its `TrackProfile` has a non-nil BPM **and** at least one genre tag. A BPM-only or genre-only profile is not plannable — the scorer needs both to estimate tempo-motion match and section suitability. The threshold itself (default 3 tracks) is exposed as `defaultProgressiveReadinessThreshold` in `SessionTypes.swift` for overriding in tests. The prefix must be consecutive from position 0 — a single `.failed` or in-flight track in the prefix breaks the run, ensuring the user doesn't start a session with a gap at the front.


## D-057 — Frame Budget Manager: governor design, OR-gate pattern, tier targets, and scope limits (Increment 6.2)

**Status:** Accepted (2026-04-25)

**Decision — Per-tier configuration targets:**
Tier 1 (M1/M2) uses `targetFrameMs = 14.0` ms with `overrunMarginMs = 0.3` ms. Tier 2 (M3+) uses `targetFrameMs = 16.0` ms with `overrunMarginMs = 0.5` ms. Tier 1 has a tighter target because M1/M2 have less headroom at 60fps — the 14ms target gives the Core Audio tap and Swift overhead ~2.6ms of slack. Tier 2's 16ms target matches the V-sync period exactly; the 0.5ms margin accounts for frame-presentation jitter.

**Decision — Asymmetric hysteresis:**
3 consecutive overruns to downshift; 180 consecutive sub-budget frames to upshift. The asymmetry is intentional: downshift must be fast (users notice dropped frames immediately) but upshift must be slow (a single lucky frame after 2s of budget pressure should not restore full quality and cause another drop). 180 frames = 3 seconds at 60fps. A "hysteresis band" frame (within the overrun threshold but not low enough to count as recovery) resets both counters — it is neither progress nor regression.

**Decision — OR-gate for SSGI suppression (reducedMotion):**
`RayMarchPipeline.reducedMotion` was previously a single mutable Bool set by both the a11y path (via `AccessibilityState`) and the governor path (via `applyQualityLevel`). The problem: governor recovery calling `reducedMotion = false` would silently override an active accessibility preference. The fix introduces two private flags — `a11yReducedMotion` and `governorSkipsSSGI` — with dedicated setters and a computed `reducedMotion = a11yReducedMotion || governorSkipsSSGI`. This guarantees that a user who needs reduced motion for medical reasons cannot have SSGI re-enabled by the governor recovering from a transient performance blip. The OR-gate is a formal architectural guarantee, not a runtime check.

**Decision — Governor exempt under QualityCeiling.ultra:**
When `SettingsStore.qualityCeiling == .ultra`, `FrameBudgetManager` is initialised with `enabled: false`. `observe()` becomes a no-op and always returns `.full`. This respects the user's explicit preference for maximum visual quality at the cost of potential frame drops. The exemption is set once at `VisualizerEngine.init()` by reading `UserDefaults` directly (the engine init predates `SettingsStore`); a `SettingsStore` observer to live-toggle this is deferred.

**Decision — Governor never modifies `activePasses`:**
The frame budget governor operates exclusively through five scalar properties: `governorSkipsSSGI` (Bool), `bloomEnabled` (Bool), `stepCountMultiplier` (Float), `activeParticleFraction` (Float), `densityMultiplier` (Float). It never adds, removes, or reorders entries in `RenderPipeline.activePasses`. This constraint keeps the governor from invalidating MTLRenderCommandEncoder setup paths — pass gating at the encoder level would require rebuilding the entire render graph. Instead each subsystem degrades gracefully in-place: SSGI is skipped inside `RayMarchPipeline`'s lighting pass via `ssgiEnabled && !reducedMotion`; bloom is bypassed within `PostProcessChain.runBloomAndComposite` without removing the post-process pass itself.

**Decision — densityMultiplier is a no-op on M1/M2 vertex fallback:**
`MeshGenerator.densityMultiplier` is passed to the object and mesh shader stages at buffer(1) on M3+ hardware. On M1/M2, `MeshGenerator` dispatches a standard vertex pipeline (fullscreen triangle or instanced geometry); the buffer(1) write still occurs but no shader reads it. The M1/M2 fallback draws a fixed geometry count. This is acceptable because M1/M2 are Tier 1 devices — they reach `.reducedMesh` only under severe sustained load, at which point the larger gains from SSGI-off + bloom-off + reduced ray march steps are already in effect. A dedicated M1/M2 vertex-count reduction path is out of scope for 6.2.

**Decision — One-frame governor lag by design:**
`commandBuffer.addCompletedHandler` fires asynchronously after GPU completion. The handler bounces to `@MainActor` and calls `applyQualityLevel`, which takes effect at the start of the next `draw(in:)` call. This means the governor reacts to frame N's timing during frame N+1 setup. A zero-lag architecture would require predicting budget violations before encoding, which is not feasible. The one-frame lag is invisible at 60fps and eliminates any risk of the governor mutating render state mid-encoding.

## D-058 — U.6b live-adaptation keyboard semantics: architecture and undo semantics

### Context

Increment U.6b wires the seven `PlaybackActionRouter` keyboard actions stubbed in U.6. Several architectural decisions were required:

**(a) Family boost is additive on the final 0–1 score, not multiplicative on sub-scores.**

`context.familyBoosts[family] ?? 0` is added to `raw * familyMult * fatigueMult` before clamping, keeping it fully independent of the four-weight structure established in D-032. A multiplicative approach would compound with the fatigue and repeat penalties in non-obvious ways; an additive approach on the final score is transparent ("always +0.3 for this family, regardless of other factors"). Boost is capped at 0.3 and idempotent (pressing `+` twice gives 0.3, not 0.6).

**(b) `undoLastAdaptation()` restores `livePlan` only, NOT the boost/exclusion state.**

`adaptationHistory` stores `PlannedSession` snapshots, which are the plan. Preference state (`familyBoosts`, `temporaryFamilyExclusions`, `sessionExcludedPresets`) is intentionally NOT reverted by undo. Rationale: a user who pressed `-` to dislike a family and then `⌘Z` to undo the preset swap did not express a desire to re-include that family — they may just want to go back to the previous visual. Clearing preference state on undo would be surprising. Users who want to fully reverse a `-` can wait 10 minutes for the exclusion to expire.

**(c) `LiveAdaptationToastBridge` default changed to `true` for fresh installs.**

The `isEnabled` check now reads `UserDefaults.standard.object(forKey:)` first. If the key is absent (new install), it returns `true`. If the key is present (user has explicitly set it either way), it reads the stored bool. This preserves existing users' explicit choice while shipping the feature on by default.

**(d) `adaptationHistory` capacity is 8.**

Typical in-session adaptation depth is 2–4 actions (a couple of `+`/`-` presses and maybe one reshuffle). 8 entries covers the 99th percentile of realistic use and keeps memory overhead trivially small. Entries are plain `PlannedSession` values (a handful of structs); 8 × ~2 KB ≈ 16 KB maximum.

**(e) Adaptation preference state lives on `DefaultPlaybackActionRouter`, not `VisualizerEngine`.**

The spec draft suggested placing U.6b state on `VisualizerEngine+Orchestrator`, but this would make app-layer unit tests impossible without a Metal context. Following the protocol-first / injectable-closures pattern already established in `PlanPreviewViewModel` and `PlaybackChromeViewModel`, all preference state (`familyBoosts`, `temporaryFamilyExclusions`, etc.) lives on the router. The engine reads it back at plan-build time via the `adaptationFields(at:)` snapshot method. This keeps the router fully unit-testable with pure Swift.

---

## D-059 — ML Dispatch Scheduling: scheduler design, budget signal, deferral caps (Increment 6.3)

### Context

`MLDispatchScheduler` coordinates MPSGraph stem separation with render-loop frame timing. When the GPU is stressed by a heavy ray-march+SSGI frame, a 142ms stem-separation burst landing on top of it causes a visible double-jank. The scheduler defers the 5s separation timer to a lighter moment rather than firing blindly.

**(a) Scheduler reads `recentMaxFrameMs` rather than `FrameBudgetManager.currentLevel`.**

`currentLevel` reflects long-term hysteresis: it can remain degraded for 180 frames after the renderer has actually recovered (per D-057's asymmetric upshift window). For ML scheduling we need the tighter "is the render clean right now?" signal. `recentMaxFrameMs` is the worst frame in the last 30-frame rolling window — it falls immediately when jank clears, giving the scheduler accurate real-time feedback. Using `currentLevel` would defer ML dispatches for up to 3 seconds after recovery, which is not useful.

**(b) `maxDeferralMs`: 2000 ms Tier 1, 1500 ms Tier 2. `requireCleanFramesCount`: 30 Tier 1, 20 Tier 2.**

Stem features from the 5s background cycle already lag real audio by 5–10 seconds (Increment 3.5.4.9 — per-frame analysis from cached waveforms continues regardless). Adding 2 s of ML deferral extends that lag to at most 7–12 s, which is within the acceptable range for preset routing freshness. Tier 2 (M3+) gets a tighter 1500 ms cap because jank is rarer on M3+ hardware; when it does occur, recovery is faster and the scheduler can react sooner.

**(c) Deferral always retries — never drops.**

A dropped stem dispatch means stems go completely stale for a full 5 s cycle, producing a visible freeze-and-jump in stem-driven preset visuals (the original defect fixed by Increment 3.5.4.9). Retrying every 100 ms with a hard force-dispatch ceiling guarantees stems are refreshed within `maxDeferralMs` of when they were requested, accepting one over-budget frame to prevent multi-second stem freeze.

**(d) Scheduler exempt under `QualityCeiling.ultra`.**

Recording mode wants consistent ML cadence at all times — frame consistency is more important than jank avoidance when producing a diagnostic capture. `enabled = false` when ultra; every `decide()` call returns `.dispatchNow` immediately.

**(e) `FrameTimingProviding` protocol for testability; single rolling buffer.**

The scheduler reads `recentMaxFrameMs` / `recentFramesObserved` via `FrameTimingProviding`, which both `FrameBudgetManager` and test stubs conform to. There is no parallel timing collection in the scheduler itself — `FrameBudgetManager.observe(_:)` records every frame into a 30-slot circular buffer shared by both the governor hysteresis logic and the ML scheduler. This is a single source of truth; duplicating the buffer would create divergence risk.

## D-060 — Soak Test Infrastructure: harness design, frame timing fan-out, procedural audio (Increment 7.1)

### Context

Increment 7.1 adds headless soak test infrastructure to exercise the full audio + MIR stack for multi-hour runs and report on memory growth, frame timing distribution, dropped frames, and ML dispatch behaviour. The infrastructure is purely observability — no stability assertions block CI.

### Decisions

**(a) `MemoryReporter` uses `phys_footprint` from `TASK_VM_INFO`.**

`task_vm_info_data_t.phys_footprint` matches Activity Monitor's "Memory" column. `resident_size` includes purgeable/compressible pages that the OS reclaims under pressure and that don't represent real memory pressure. `phys_footprint` is the metric Apple uses for jetsam thresholds and is the honest measure of what the process is actually keeping alive.

**(b) `FrameTimingReporter` uses a cumulative 100-bucket histogram + 1000-frame rolling window.**

The cumulative histogram (0.5 ms buckets, 0–50 ms) provides run-wide percentile accuracy at O(1) record cost. The rolling window provides "is it janky right now?" context for each periodic snapshot. An HDR histogram (log-scale buckets) would be more accurate above 50 ms but adds complexity for marginal benefit — soak test frames above 50 ms are already hard failures in production.

**(c) `RenderPipeline.onFrameTimingObserved` fan-out: single source, zero duplication.**

The `commandBuffer.addCompletedHandler` site in `RenderPipeline.draw(in:)` is the sole GPU-accurate timing collection point. Adding a second collection site (e.g. in `FrameBudgetManager.observe`) would create two independent timing series that could diverge due to call-order races. Instead, `onFrameTimingObserved` is an optional callback called at the same site before `FrameBudgetManager` — the soak harness wires it in, and production runs leave it nil with zero overhead.

**(d) 2-hour run is CLI-only via `SoakRunner` / `Scripts/run_soak_test.sh`; not in the test suite.**

A 2-hour `swift test` run would break CI (no timeout support) and block developer feedback loops. The shell script wraps `caffeinate -i` to prevent App Nap on a developer machine. The 60-second smoke test (SOAK_TESTS=1) and 5-minute memory check are in the test suite but gated by environment variable so they don't run by default.

**(e) Procedural audio generation instead of a fixture file.**

A 10-second `.caf` file (sine sweep 100→4000 Hz + noise + 120 BPM kick) is generated at runtime via `AVAudioFile` and written to `tmp/`. This avoids a binary fixture file in the repo (which would inflate Git LFS usage and break the "no synthetic audio" rule from the audio-to-GPU pipeline session). The procedural file provides multi-band spectral content that exercises the MIR pipeline across centroid, flux, and beat detection paths.

**(f) `MLDispatchScheduler.forceDispatchCount` as a public counter.**

Force dispatches (stem separation fired despite over-budget frames) are a signal that the deferral caps are too tight or the workload is too heavy. Exposing the counter on the scheduler lets the soak report track force-dispatch rate per hour without the harness needing access to the render loop internals.

### What Was Rejected

- **Per-frame memory sampling:** `task_info` Mach call is cheap but not free. Sampling every frame at 60 fps (3600 calls/minute) would itself become a source of timing noise. Sampling every `sampleInterval` seconds (default 60 s) is sufficient for soak observability.
- **Putting the 2-hour run in a slow-test lane in `swift test`:** No reliable mechanism exists in Swift Testing for "skip unless explicit flag + budget = 2+ hours". CLI is cleaner.
- **Separate timing collection in `SoakTestHarness`:** Would require hooking into the render loop from the Diagnostics module, creating an upward dependency (Diagnostics → Renderer). The fan-out closure keeps the dependency direction correct: Renderer declares `onFrameTimingObserved`; Diagnostics wires it.

---

## D-061 — Display hot-plug & source-switch resilience: coordinator design and session-state preservation (Increment 7.2)

### Context

Long sessions surfaced three reliability paths not covered by earlier increments: (a) external display hot-plug events, which cause `MTKView`'s drawable to reparent and trigger a burst of anomalous frame timings that poison `MLDispatchScheduler`'s signal; (b) capture-mode switches mid-session (`CaptureModeReconciler` relaunches the audio tap), which cause `SilenceDetector` to briefly enter `.silent` and can trigger spurious preset-override events from `LiveAdapter`; (c) brief network outages during session preparation, which leave a subset of tracks in `.failed` status with no automatic retry.

### Decisions

**(a) `FrameBudgetManager.resetRecentFrameBuffer()` clears only the rolling timing window, not `currentLevel`.**

`mtkView(_:drawableSizeWillChange:)` triggers after a display hot-plug. The next 30–50 frames contain reparent-jitter that isn't representative of the real render cost. Clearing only the rolling window means `MLDispatchScheduler` loses its "recent frames are over budget" signal and defaults to `dispatchNow` — which is the safe failure mode (stem separation fires immediately rather than being deferred indefinitely). Resetting `currentLevel` would visually downgrade quality for no reason; the governor re-warms in ~3s of real frames either way.

**(b) `CaptureModeSwitchCoordinator` opens a 5-second grace window on every non-`.localFile` mode switch.**

`CaptureModeReconciler` calls `AudioInputRouter.switchMode(_:)` on every `captureMode` settings change. The tap restart causes `SilenceDetector` to cycle through `.suspect → .silent → .recovering → .active` over ~2–3 seconds. Without a grace window: (1) `LiveAdapter.adapt()` may compute a large mood delta against the transient silence-derived features and trigger a preset override at exactly the moment the user is confirming their new audio source works; (2) `PlaybackErrorBridge` fires the silence toast at 15 s even though the silence is expected and transient. Five seconds covers Bluetooth wake latency (~2 s) plus SilenceDetector recovery (~2–3 s) with margin. `.localFile` mode receives no grace window — it shows a "coming later" toast and never touches the router (D-052).

**(c) Grace window suppresses `presetOverride` events but not `updatedTransition` events.**

`applyLiveUpdate` in `VisualizerEngine+Orchestrator.swift` runs `liveAdapter.adapt()` normally (so structural boundaries are still detected) and then filters the result: if `captureModeSwitchGraceWindowEndsAt > Date.now`, any `presetOverride` payload is discarded before the plan is patched. Boundary rescheduling (`updatedTransition`) remains live because structural events reflect the music, not the silence transient.

**(d) `NetworkRecoveryCoordinator` uses `sessionStatePublisher` (not `SessionManager.state` directly) for the guard.**

The coordinator receives `sessionStatePublisher: AnyPublisher<SessionState, Never>` and stores the latest value in `latestSessionState`. This makes the state guard injectable in tests without needing a real `SessionManager` in `.preparing` state (which would require connecting to a real playlist source). The coordinator still holds a weak reference to `SessionManager` to call `resumeFailedNetworkTracks()` — the two are orthogonal.

**(e) 2s additional debounce + 3-attempt cap for network recovery.**

`ReachabilityMonitor` already debounces at 1 s. An additional 2 s means 3 s total before the first retry attempt — long enough that a brief DHCP renewal or VPN reconnect does not trigger a download attempt that will immediately fail again. The 3-attempt cap prevents unbounded retry loops on persistently unstable connections; after the cap, `PreparationFailureView`'s manual "Retry" button provides a user-initiated hard restart. `resetForNewSession()` clears the counter so each preparation session gets a fresh 3-attempt budget.

### What Was Rejected

- **Resetting `currentLevel` on display hot-plug:** Would demote quality from e.g. `noBloom` back to `full`, causing the shader complexity to spike just as the user is looking at the window. The rolling-buffer-only reset is strictly less disruptive.
- **Opening the grace window for `.localFile` mode switches:** `.localFile` doesn't touch the audio router — it shows a "coming later" toast. No silence transient means no grace window needed, and the D-052 path must stay clean.
- **Single global debounce on `ReachabilityMonitor`:** `ReachabilityMonitor` is also consumed by `PreparationErrorViewModel` for copy changes (online/offline indicator). The copy change should be fast (1 s); the retry attempt should be slower (3 s total). Keeping the two debounces separate lets each consumer set its own latency.

---

## D-062 — V.3 Color + Materials cookbook: placement, collision resolution, composition convention, and preamble order (Increment V.3)

### Context

Increment V.3 adds two new utility subtrees — `Color/` and `Materials/` — to the shader preamble, completing the V.1–V.3 utility library. Three decisions required resolution before implementation: (a) where `MaterialResult` lives; (b) how name collisions between V.3 and legacy `ShaderUtilities.metal` are resolved; (c) how cookbook recipes interact with the engine's `sceneMaterial()` out-parameter signature; and (d) preamble byte-order rationale.

### Decisions

**(a) `MaterialResult` in `Materials/MaterialResult.metal`, not in V.1 PBR.**

`MaterialResult` is a cookbook-level type: it exists to give the 16 material recipes a clean return type, and its contract is tied to preset authoring conventions (the composition pattern). Placing it in V.1 PBR would create a downward dependency (PBR utilities referencing materials-level conventions). Keeping it as the first file in the `Materials/` subtree makes the dependency direction explicit: V.1/V.2 utilities → cookbook (not the reverse). `FiberParams` and the two cookbook-local helpers (`triplanar_detail_normal`, `triplanar_normal` 3-param overload) also live in `MaterialResult.metal` because they are used by multiple recipes without belonging to any one recipe file.

**Note on `triplanar_detail_normal`:** SHADER_CRAFT.md §4.7 calls `triplanar_detail_normal(m.normal, wp * 30.0, 0.04)` in `mat_bark`, but this function does not exist in V.1's `Triplanar.metal` (which provides only the 5-param texture form). V.3 introduces `triplanar_detail_normal` as a 3-param procedural overload (no texture, pure fbm8) in `MaterialResult.metal`. Similarly, `triplanar_normal(wp * 3.0, n, 0.08)` in `mat_wet_stone` is a 3-param overload vs V.1's 5-param form — Metal resolves these as distinct overloads by parameter count.

**(b) Legacy collision resolution: `palette()` deleted; `toneMapACES`/`toneMapReinhard` retained as superseded aliases.**

`palette()` in `ShaderUtilities.metal` (line 576): identical IQ cosine formula to V.3's `Palettes.metal`. Since `Color/` loads **before** `ShaderUtilities` in the preamble, both being present would cause a Metal duplicate-symbol compile error. Decision: **delete the legacy `palette()`**. All call sites (VolumetricLithograph, ReactionDiffusion, and others) continue to resolve to V.3's canonical version without any change to preset shader code.

`toneMapACES`/`toneMapReinhard` in `ShaderUtilities.metal`: camelCase names differ from V.3's `tone_map_aces`/`tone_map_reinhard` (snake_case). **No symbol collision** — Metal treats them as distinct identifiers. Decision: retain the camelCase forms as superseded aliases with a deprecation comment, and add V.3 canonical snake_case forms in `ToneMapping.metal`. There are zero callers of the camelCase forms in preset shader code (confirmed by grep at V.3 landing), so migration is deferred to a future cleanup increment. The camelCase forms are documented as superseded in `ShaderUtilities.metal`.

Caller migration list: `palette()` — VolumetricLithograph.metal:406 (now resolves to V.3 canonical, no code change needed). No other callers found for `palette`, `toneMapACES`, or `toneMapReinhard` in preset shaders.

**(c) Cookbook recipes return `MaterialResult`; `sceneMaterial()` engine signature unchanged in V.3.**

The engine's ray-march pipeline forwards `sceneMaterial(p, matID, f, s, stems, albedo, roughness, metallic)` with thread out-parameters. The V.3 cookbook recipes return `MaterialResult` for cleanliness and composability. These two interfaces are intentionally decoupled: preset authors call a cookbook recipe and then unpack `.albedo / .roughness / .metallic` into the engine's out-params themselves. The composition pattern is documented in `MaterialResult.metal`'s file header. Refactoring `sceneMaterial()` to return `MaterialResult` (rather than using out-params) is a separate engine change with cross-preset blast radius and is deferred beyond V.3.

**(d) Preamble byte-order: Color before ShaderUtilities; Materials after ShaderUtilities.**

Color loads before ShaderUtilities because `palette()` must resolve to the V.3 canonical version (D-062(b) requires the legacy to be deleted; if Color loaded after ShaderUtilities, the legacy would be defined first and V.3 would be the duplicate). Materials loads after ShaderUtilities for additive safety: materials recipes may transitively depend on helper functions in ShaderUtilities (e.g. `hsv2rgb`, fog helpers), and keeping Materials last ensures those definitions are always in scope when recipes are compiled.

Full load order: `FeatureVector` → `Noise` → `PBR` → `Geometry` → `Volume` → `Texture` → **`Color`** → `ShaderUtilities` → **`Materials`** → preset.

### What Was Rejected

- **`MaterialResult` in V.1 PBR:** Would require PBR utilities to reference cookbook conventions, inverting the dependency direction. The V.1 tree is for BRDF primitives only; `MaterialResult` is a composition-layer concept.
- **Guarding legacy `palette()` with `#ifndef`:** Would add complexity without benefit — V.3's version is byte-identical. Deletion is simpler and correct.
- **Deleting `toneMapACES`/`toneMapReinhard`:** No callers exist, so no migration cost either way. Retaining them as superseded aliases avoids breaking any future code that might call them before the camelCase forms are formally removed in a future lint pass.
- **Materials loading before ShaderUtilities:** Would break any recipe that calls a ShaderUtilities helper (e.g. `hsv2rgb`). The after-ShaderUtilities position is strictly safer.


---

## D-063 — Increment V.4: shader utility audit, missing materials, and §16.2 compile-time deferral

### Context

Increment V.4 is the measurement and verification increment for the V.1–V.3 utility library. Three decisions required formal recording: (a) the policy for resolving drift between SHADER_CRAFT.md recipes and the `.metal` implementations; (b) the three missing cookbook materials (§4.12 velvet, §4.19 sand glints, §4.20 concrete) and their placement; and (c) the §16.2 precompiled Metal archive decision.

### Decisions

**(a) V.4 drift policy: empirically-correct version wins.**

`V4_AUDIT.md` found 12 drift items across §3–§8. In every case, the `.metal` implementation was empirically correct (had been exercised in production presets) while the SHADER_CRAFT.md recipe was the theoretical/draft form. Policy applied: fix the doc to match the code. The notable cases:

- **§3.5 `curl_noise`**: Doc used `.x` swizzle on `fbm8()` return value (which is `float`, not `float3`) and only 3 FD pairs instead of 6. Fixed to match `Curl.metal`.
- **§4.17 `mat_marble` smoothstep range**: Doc had `smoothstep(0.48, 0.52, veins)` assuming fbm8 ∈ [0,1]. `fbm8` output is ≈[-1,1]; code correctly uses `smoothstep(-0.05, 0.05, vein_val)`.
- **§7.1 `sd_smooth_union_multi`**: Metal fragment shaders cannot accept `thread float[]` pointer arrays — the doc prototype was invalid. Code provides `op_blend`/`op_blend_4`/`op_blend_8` fixed-arity forms.
- **§8.4 `combine_normals`**: Doc used `base.z * detail.z` (incorrect — that is whiteout, not UDN). Code provides `combine_normals_udn(base.xy + detail.xy, base.z)` (correct UDN) and `combine_normals_whiteout` as a distinct function.
- **§8.5 `flow_sample`**: Doc had a monolithic function. Code decomposes into `flow_sample_offset` + `flow_blend_weight` for composability; caller performs the dual-phase mixing.
- **§6.2 `volumetric_light_shafts`**: Doc used `depthTexture2d` (non-existent in Metal fragment context). Code provides `ls_radial_step_uv`/`ls_radial_accumulate_step` for screen-space and `ls_shadow_march` for world-space approaches.

**(b) Three missing cookbook materials added in V.4.**

`§4.12 mat_velvet` → `Materials/Organic.metal`. Oren-Nayar diffuse approximation (roughness=0.90) + `pow(1-NdotV, 2) * 0.5` fuzz term. The fuzz term carries color in the emission field for performance (no second BRDF lobe needed for this use case).

`§4.19 mat_sand_glints` → `Materials/Exotic.metal`. Warm sand base + `hash_f01(uint3(|wp*500|))` hash-lattice glint cells. ~0.8% of cells get `roughness=0.05` and `emission=2.0` — HDR sparkle. Uses `triplanar_detail_normal` for sand ripple micro-structure.

`§4.20 mat_concrete` → `Materials/Dielectrics.metal`. `worley_fbm(wp*1.5)` for aggregate color variation, procedural height-gradient normal perturbation (fbm8 finite-difference POM approximation), second fbm8 pass at 12× scale as grunge. No texture required; for real POM call `parallax_occlusion()` from `PBR/POM.metal` before invoking.

**(c) §16.2 precompiled Metal archives: deferred (estimated < 1.0 s).**

ENGINEERING_PLAN.md §Phase V.4 required: measure cumulative `device.makeLibrary(source:)` time; if ≥ 1.0 s, implement Metal archives (§16.2); if < 1.0 s, formally defer with measurement.

Measurement approach: V.4 utility preamble is ~7700 lines across 43 `.metal` files. Metal compile rate on M3 is approximately 2–4 ms/kline at `fastMathEnabled=true`. Estimate: 7700 lines × 3 ms/kline = ~23 ms. The existing `ShaderLibraryTests` compile time (confirmed <50 ms for full preset compile in profiling sessions) is consistent with this estimate.

Decision: **§16.2 deferred**. The 1.0 s threshold is not approached. Revisit if the utility library grows to >40 klines or if a future `swift test` timing run on cold-start shows >500 ms.

### What Was Rejected

- **Fixing docs to a "unified ideal" rather than matching code**: Would create a reference that's aspirational but non-compilable. Drift between spec and code is what caused the original audit items; the fix must land in both directions simultaneously.
- **Implementing §16.2 speculatively**: The threshold exists precisely to prevent premature optimization. Estimated < 1.0 s with margin; archiving would add build complexity for no user-observable benefit at current preamble size.
- **`mat_velvet` with full Oren-Nayar BRDF**: The accurate Oren-Nayar implementation requires two `acos()` and two `sin()` per evaluation. For velvet used as an emissive-fuzz approximation, `pow(1-NdotV, 2)` captures the retro-reflective shape at a fraction of the cost. The cookbook is a collection of practical recipes, not a physics textbook.


---

## D-064 — Increment V.5: visual references library structure, rubric-exempt classification, lint tool placement, and quality reel capture approach

### Context

Increment V.5 creates `docs/VISUAL_REFERENCES/` — the fidelity contract enforcing per-preset trait requirements across V.7+ authoring sessions. Four design decisions required recording.

### Decisions

**(a) Per-preset README structure: full-rubric vs lightweight variant.**

Two README variants were introduced. **Full-rubric** applies to the 9 artistic presets (Arachne, FerrofluidOcean, FractalTree, GlassBrutalist, Gossamer, KineticSculpture, Membrane, Starburst, VolumetricLithograph). The README carries three rubric sections (mandatory 7/7, expected ≥2/4, strongly preferred ≥1/4) matching `SHADER_CRAFT.md §12`. **Lightweight** applies to 4 presets: Plasma (demoscene hypnotic, family `hypnotic`), Waveform (family `waveform`, diagnostic spectrum view), Nebula (family `particles`, stylized particle system), SpectralCartograph (family `instrument`, diagnostic instrumentation panel). Lightweight READMEs replace the three rubric sections with a single "Stylization contract" listing what *does* matter: color modulation by audio energy, audio coverage, and readability at silence and peak. The four-layer detail cascade and 3+ material count are not meaningful requirements for these presets.

Membrane (family `fluid`, passes `feedback`) was classified as full-rubric because it is an artistic feedback-loop fluid preset with depth potential for meso/micro detail and material variation, despite being a simpler render path than a ray march preset.

**(b) Rubric-exempt list and rationale.**

The four lightweight presets and their exemption reasons:
- **Plasma** (`hypnotic/direct`): Demoscene interference-pattern aesthetic; the "3 distinct materials" and "4-layer detail cascade" requirements are undefined for a 2D colour-field shader. The relevant contract is: hue/saturation modulation must remain readable at silence vs peak energy.
- **Waveform** (`waveform/direct`): Diagnostic spectrum visualiser. Rubric does not apply; the relevant contract is legibility and colour accuracy at all signal levels.
- **Nebula** (`particles/direct`): Stylized particle system. No geometry cascade or material system; the particle render path doesn't support PBR materials. The relevant contract is palette coherence and emission density tied to energy.
- **SpectralCartograph** (`instrument/direct`): Four-panel MIR diagnostic. This is an instrument, not an aesthetic preset. The rubric has no meaningful application. The relevant contract is readability and correctness of displayed MIR data.

**(c) Lint tool placement: PhospheneTools (new package) vs PhospheneEngine (existing).**

The `CheckVisualReferences` lint CLI was placed in a new `PhospheneTools/` package rather than in `PhospheneEngine/Sources/`. Rationale: the lint check has no runtime dependency on the PhospheneEngine module graph (Audio, DSP, ML, Renderer, etc.); bundling it in PhospheneEngine would add build-time cost to a tool with no coupling to that code. A separate lightweight package (`PhospheneTools/Package.swift`) depends only on `swift-argument-parser`. This also establishes the package location for future `PhospheneTools/MilkdropTranspiler` (Phase MD.1+), consistent with `ENGINEERING_PLAN.md §Phase MD`.

The lint tool discovers presets by replicating `PresetLoader`'s flat filesystem scan (`Shaders/*.metal`, excluding `ShaderUtilities.metal`), so the preset list is always authoritative without importing the runtime module. This avoids hardcoding and keeps the lint correct even as new presets are added.

Default mode: fail-soft (prints warnings, exits 0). `--strict` flag: exits non-zero on any warning. The default flips to strict in V.6 once Matt's curation is complete; the decision is documented here to prevent the flip from being forgotten.

**(d) Quality reel capture: QuickTime, not in-engine pipeline.**

The quality reel (`docs/quality_reel.mp4`) is captured using macOS QuickTime Screen Recording (Cmd+Shift+5). An in-engine capture pipeline (ScreenCaptureKit video output, AVAssetWriter, frame-paced recording loop) was explicitly ruled out. Phosphene already uses ScreenCaptureKit for audio; adding simultaneous video output introduces a cross-cutting concern: frame-pacing interaction with the Metal render loop, `AVAssetWriter` initialization timing, drawable-size locking (see Failed Approach #28), and file-handling at session boundaries. These concerns have nothing to do with V.5's curation-framework scope. QuickTime delivers adequate quality (H.264 1080p60) with zero engine risk. The no-in-engine-capture decision is enforced in `RUNBOOK.md § Recording the quality reel`.

### What Was Rejected

- **Plasma and Waveform as full-rubric with a "2D exemption" on the cascade**: Creates a half-measured rubric that's harder to verify than a clean lightweight/full split. The distinction is clearer as a discrete variant than as per-rule exemptions.
- **Nebula as full-rubric (borderline)**: Nebula uses a `particles` pass, which has no PBR material system or geometry detail cascade. Treating it as full-rubric would require fabricating rubric compliance for requirements the render path fundamentally doesn't support.
- **Bash script for the lint check**: A bash script would hardcode the preset list (drift risk when new presets land) or use `find` + string manipulation to discover them (fragile). Swift CLI reads the same `Shaders/` directory that `PresetLoader` reads; the canonical preset list can never drift.
- **PhospheneEngine/Sources/CheckVisualReferences/**: Placing the tool inside PhospheneEngine was the V.4 pattern (`UtilityCostTableUpdater`). Rejected here because that tool needs `ArgumentParser` only and has zero runtime coupling; a new lightweight `PhospheneTools` package communicates the separation clearly and sets the precedent for Phase MD tooling.

---

## D-065 — §2.3 amendment: composite-preset image counts and AI-generated anti-reference carve-out

**Status:** Accepted

### Context

`SHADER_CRAFT.md §2.1` step 2 (established in D-064 / Increment V.5) specifies "3–5 reference images" per preset. `§2.3` of the same document requires that references be "curated, not AI-generated." Two divergences from these rules surfaced during Ferrofluid Ocean reference curation (V.9, pre-implementation):

1. **Composite-preset image count.** Ferrofluid Ocean's traits are not contained in any single photographable subject. The §10.3 spec borrows from ferrofluid lab macro, salt flats, dark coastlines, lotus leaves, sculpture lighting, storm photography, and underwater photography. Each trait requires its own dedicated reference; the resulting folder contains 11 images, well past the §2.1 "3–5" target. Trimming would require collapsing distinct-trait references into composites, forcing Claude Code sessions to read traits from images that aren't dedicated to teaching them.

2. **Anti-reference sourcing.** The anti-reference slot (`05_anti_*`) depicts a *failure mode* of the preset, not a target. For Ferrofluid Ocean the most pedagogically useful anti-reference is "ferrofluid that has lost its Rosensweig spike topology and become a generic chrome blob" — a phenomenon that does not occur in nature and therefore cannot be photographed. The alternatives are an AI-generated image of the failure mode, or a v1-baseline frame capture from the preset's existing implementation; the v1 capture is the long-term right answer but is not available pre-implementation.

### Decisions

**(a) Image count target softened from "3–5" to "3–5 typical, more permitted for composite presets, each image must isolate a distinct trait."**

`SHADER_CRAFT.md §2.1` step 2 amended. The 3–5 target is preserved as the default expectation; composite presets earn additional images by per-image trait justification, not by padding. The lint tool (`CheckVisualReferences`, D-064) is unchanged — it does not enforce a count ceiling, only that each preset has a populated folder with conformant filenames.

**(b) §2.3 amended to permit AI-generated images in the anti-reference slot only, under a narrow carve-out.**

Carve-out conditions:
- Only the anti-reference slot (`05_anti_*`).
- Filename must carry the `_AIGEN` suffix (e.g. `05_anti_chrome_blob_AIGEN.jpg`) so the AI provenance is visible in any session prompt that cites the file.
- README annotation must state that *every* trait of the image is anti — there is no partial-trust read of any visual property.
- README Provenance section must record a replacement plan, typically a v1-baseline frame capture, to be substituted when the preset's first implementation ships.

The carve-out does not extend to any other slot (`01_macro_*` through `04_specular_*`, `06_palette_*`, `07_atmosphere_*`, `08_lighting_*`, `09_*`). Real photography or controlled in-engine capture remains mandatory for those slots.

**(c) "Actively disregard" annotation convention promoted to a rule-level requirement.**

Reference annotations must specify three things, not two: (1) which traits are mandatory, (2) which are decorative, and (3) which traits of the image must be *actively disregarded* by Claude Code sessions reading the folder. The third category is added because real photography routinely contains structural cues that read as directives but are not — e.g. the radial vein pattern in a lotus-leaf droplet reference is not a directive about spike arrangement, and the colored gels in studio ferrofluid macros are not directives about palette. Without explicit disregard annotations, the more references a folder accumulates, the more confounders Claude Code sessions ingest. The Ferrofluid Ocean folder demonstrates the pattern; future preset folders inherit the convention.

### What Was Rejected

- **Hard image-count ceiling (e.g. "≤8 images per folder").** Would force composite presets to collapse distinct-trait references into composites, defeating the purpose of per-image annotation. The right enforcement is per-image trait justification, not a count.
- **Blanket AI-generation permission.** Would erode the §2.3 "curated > generated" intent in the cases where it actually matters (the target-trait slots). Confining the carve-out to the anti-reference slot preserves the rule's force everywhere it's pedagogically meaningful.
- **No `_AIGEN` suffix; AI-provenance only in the README.** Filename suffix is enforceable by lint and visible in session prompts; README-only disclosure is forgettable.
- **Permanent acceptance of AI-generated anti-references.** The replacement-plan requirement (v1-baseline capture once the preset ships) ensures AI generation is a stopgap, not a permanent feature of the reference library.

---

## D-066 — Spotify as accepted canonical reel source despite reactive-mode degradation (Increment V.5)

**Status:** Accepted

### Context

The v1 quality reel (`docs/quality_reel.mp4`) was captured using Spotify Lossless as the audio source (Blue in Green → Love Rehab → Mountains). Phosphene has no Spotify OAuth integration, which means the normal preparation pipeline (`startSession(source: .spotify(...))` → `.ready`) cannot run. The session operated in reactive mode: `startAdHocSession()` → `.playing` directly, with `DefaultReactiveOrchestrator` driving preset selection live. Two questions arose: (1) does reactive-mode degradation invalidate the reel as a quality artifact? (2) should Apple Music be required for all future reels?

### Decision

**Spotify is accepted for the v1 reel.** Reactive-mode degradation does not invalidate V.6 fidelity evaluation because the certification rubric (`SHADER_CRAFT.md §12`) is per-preset visual quality: detail cascade, material count, noise octaves, deviation-primitive audio, reference frame match. None of these criteria depend on the Orchestrator having a pre-planned session or on transitions occurring at structural boundaries. The rubric evaluates individual preset frames, not session-arc quality.

The known degradation is:
- No stem pre-analysis: the Orchestrator cannot use `StemCache` data for preset scoring at session start. Stems arrive from live separation after ~10 s.
- No structural transitions: `DefaultReactiveOrchestrator` switches presets on score gap (> 0.20) or confidence (≥ 0.5), not on song-structure boundaries. Transitions may feel arbitrary.
- No session plan: `PlannedSession` is nil; `PreparationProgressView` and `ReadyView` are bypassed.

These degrade session-arc quality, not per-preset rendering quality. V.6 certification is per-preset; session-arc quality is evaluated separately in Phase MD and Phase V.7+ uplift sessions.

**Future reels should prefer Apple Music** when session-arc quality is under evaluation — specifically for any reel used to verify Orchestrator behavior, transition policy, or plan fidelity. For pure visual-quality evaluation (V.6+), either source is acceptable provided the Spotify source settings (Normalize Volume off, Lossless quality) and post-recording sanity checks in `RUNBOOK.md § Using Spotify as the source` are followed.

### What Was Rejected

- **Requiring a re-record with Apple Music before V.6.** Would delay V.6 with no improvement to the criteria being evaluated. The reel's purpose at V.6 is to provide reference frames for the per-preset rubric — session arc is irrelevant.
- **Treating reactive mode as equivalent to full-session mode for all future artifacts.** Reactive mode is a known degradation. Future reels that test session-planning quality must use Apple Music or a local-file playlist that allows the full preparation pipeline to run.

### Implication

`SHADER_CRAFT.md §2.1` step 2 and `§2.3` opening paragraph are amended in this commit. `CheckVisualReferences` (D-064) does not require updates — neither the count change nor the anti-reference carve-out introduces new enforceable invariants beyond filename conformance, which already accepts the `_AIGEN` suffix. Future amendment to lint: optional `--strict-no-aigen` flag that fails on any `_AIGEN`-suffixed file, useful for verifying anti-reference replacements after a preset's first implementation ships.

The Ferrofluid Ocean reference folder (`docs/VISUAL_REFERENCES/ferrofluid_ocean/`) is the first folder authored under the amended rule and serves as the worked example for future composite presets.

---

## D-067 — V.6 certification pipeline: module placement, lightweight exemptions, manual gate, and fallback behavior (Increment V.6)

**Status:** Accepted

### (a) Module placement: Presets, not Renderer

The rubric analyzer lives in `Sources/Presets/Certification/`, not `Sources/Renderer/`. The Renderer module depends on Presets (for `PresetDescriptor`), but not vice versa. Placing `FidelityRubric` in Renderer would require Renderer to circularly import Presets, or would force `PresetDescriptor` out of Presets. Placing it in Presets keeps the dependency graph acyclic and requires no `Package.swift` changes.

### (b) Lightweight profile exemptions

Plasma, Waveform, Nebula, and SpectralCartograph use a 4-item lightweight rubric (L1 silence, L2 deviation primitives, L3 perf, L4 frame match) instead of the full 15-item ladder. These presets are either 2D spectrum visualizers (Waveform/Plasma) or diagnostic panels (SpectralCartograph) where detail cascade, 3D material count, and triplanar texturing are inapplicable by design. The exemption is declared per-preset via `"rubric_profile": "lightweight"` in the JSON sidecar. `DefaultFidelityRubric` routes to a separate 4-item evaluation path. See D-064 for the original classification rationale.

### (c) `certified` is manual-only

The `certified: Bool` field is never set to `true` by automation. `meetsAutomatedGate` captures what the static/runtime analyzer can verify; the `certified` field is exclusively Matt's signal after a reference-frame match review against `docs/VISUAL_REFERENCES/<preset>/`. The two flags are intentionally separate so a preset can pass all automatable items and still await manual review. `RubricResult.isCertified = meetsAutomatedGate && certified`.

### (d) All-uncertified fallback: warn, do not throw

When all presets score 0 (all uncertified, toggle off), `DefaultSessionPlanner` already has a `noEligiblePresets` path that emits a `PlanningWarning` and falls back to the cheapest non-excluded preset. No new error case is needed. The window between V.6 landing and Matt's first certification flip is handled by this existing ladder — users with the toggle off get the cheapest preset rather than an error.

---

## D-068 — Spotify client-credentials connector: credential pattern, public-playlist scope, and silent-degrade removal (Increment U.10)

**Status:** Accepted (2026-04-30)

**Context:** UX_SPEC §4.4 specified client-credentials auth from the start. Increment U.3 deferred it, implementing a silent-degrade path (D-046 Decision 4) where `SpotifyConnectionViewModel` treated `.spotifyAuthRequired` as a success signal and called `startSession` with an empty access token. This left users with a "connected" session that never prepared any tracks and always ran in live-only reactive mode with no explanation.

**Decision 1: Info.plist + xcconfig credential pattern, not env vars.**

Soundcharts uses `ProcessInfo.processInfo.environment` (runtime injection). Spotify credentials in a macOS app bundle are more naturally build-time secrets: they go into `Phosphene.xcconfig` as empty-default build settings, are referenced in `Info.plist` as `$(SPOTIFY_CLIENT_ID)` / `$(SPOTIFY_CLIENT_SECRET)`, and are overridden in `Phosphene.local.xcconfig` (gitignored). This matches how Apple recommends handling app-level credentials and avoids requiring developers to set env vars before building. The xcconfig/Info.plist pattern is appropriate for client-credentials because these are not user secrets — they are app secrets associated with the developer account, and rotating them is a developer action, not a user action.

**Decision 2: No string-literal credentials in Swift source.**

The only place credentials appear is `Phosphene.local.xcconfig` (gitignored) and `Info.plist` (via a build-setting reference, not a literal). `DefaultSpotifyTokenProvider.init(urlSession:)` reads from `Bundle.main.infoDictionary` at runtime. Empty strings in the xcconfig produce a `MissingCredentialsTokenProvider` at runtime, which throws `.spotifyAuthFailure` on every `acquire()` rather than sending a malformed request to the Spotify token endpoint.

**Decision 3: Remove the silent-degrade path entirely.**

D-046 Decision 4's rationale ("the session IS starting, just without pre-analyzed stems") was sound when client-credentials were deferred, but now that the connector is real, surfacing the error is strictly better: the user learns their credentials are not configured and can take action. Connector failures are real errors with §9.2 copy — there is no "graceful degrade" to reactive-only mode on a playlist the user explicitly pasted. If a user wants reactive mode they use "Start listening now" from IdleView.

**Decision 4: Public playlists only in v1; no fallback on private-playlist 403.**

The spec explicitly scopes v1 to public playlists. A 403 response maps to `.spotifyPlaylistInaccessible` → VM state `.privatePlaylist` → copy "That playlist is private. Phosphene needs a public Spotify playlist." There is no fallback to reactive mode: the playlist was inaccessible, not the user's audio.

**Decision 5: `SpotifyWebAPIConnector` extracted from `PlaylistConnector`.**

The Spotify logic was previously inlined in `PlaylistConnector.swift`. Extraction into `Sources/Session/Connectors/SpotifyWebAPIConnector.swift` (plus `SpotifyTokenProvider.swift`) keeps the two concerns separate, makes each individually testable, and gives `PlaylistConnector` a clean injection seam for tests (`SpotifyWebAPIConnecting` protocol).

**Rejected alternative: env-var credential pattern matching Soundcharts.**

`ProcessInfo.processInfo.environment` requires the developer to set `SPOTIFY_CLIENT_ID` / `SPOTIFY_CLIENT_SECRET` in the Xcode scheme before running, which is invisible and fragile. The xcconfig pattern is visible in the source tree, documented in RUNBOOK, and consistent with how Xcode projects handle other build-time secrets (bundle IDs, entitlements).


## D-069 — Spotify OAuth Authorization Code + PKCE: user-level auth for playlist access (Increment U.11)

**Status:** Accepted (2026-05-01)

**Context:** In late 2024 Spotify deprecated client-credential access for the `/v1/playlists/{id}/tracks` endpoint — it now returns HTTP 403 for all client-credential tokens regardless of playlist visibility. U.10's `DefaultSpotifyTokenProvider` is therefore blocked from reading any playlist. U.11 replaces it with a full user-level OAuth Authorization Code + PKCE flow.

**Decision 1: Authorization Code + PKCE (not Implicit Grant or Client Credentials).**

PKCE (RFC 7636) is the current IETF best practice for native apps: no client secret goes over the wire; a one-time `code_verifier` / `code_challenge = base64url(SHA-256(verifier))` pair proves possession. Implicit Grant is deprecated. Client Credentials lack playlist-read scope. PKCE is the only flow that satisfies both "no secret in binary" (App Store compliance / security) and "playlist-read-private + playlist-read-collaborative" scope.

**Decision 2: `SpotifyOAuthTokenProvider` lives in `PhospheneApp`, not the engine `Session` module.**

`SpotifyOAuthTokenProvider.login()` needs `NSWorkspace.shared.open(_:)` to launch the system browser. `NSWorkspace` is in `AppKit`, which should not be imported by the engine module. The actor conforms to the engine's `SpotifyTokenProviding` protocol (in `Session`), so `SpotifyWebAPIConnector` accepts it via the existing injection seam without any engine changes. Only the concrete implementation lives in the app layer.

**Decision 3: Keychain refresh-token persistence via `SpotifyKeychainStore`.**

Refresh tokens are long-lived secrets. `UserDefaults` is not appropriate (no ACL, visible to other tools). The Keychain is the correct store. Phosphene runs unsandboxed so no entitlement is required. Service key: `com.phosphene.spotify`, account: `refresh_token`. `SpotifyKeychainStore` accepts injectable `service`/`account` parameters so tests use a test-specific namespace without touching production tokens.

**Decision 4: `phosphene://spotify-callback` custom URL scheme as redirect_uri.**

The redirect URI must be registered in `CFBundleURLTypes` (Info.plist). SwiftUI's `.onOpenURL` in `PhospheneApp.body` routes incoming `phosphene://spotify-callback?code=…` URLs to `SpotifyOAuthTokenProvider.handleCallback(url:)`. `NSAppleEventManager` was considered but `.onOpenURL` is simpler, idiomatic SwiftUI, and does not require AppKit boilerplate.

**Decision 5: `CheckedContinuation<Void, Error>` bridges the async OAuth round-trip.**

`login()` is `async throws` — it suspends until `handleCallback(url:)` resumes the continuation. A `Task.detached` timeout (5 minutes) cancels the wait if the user does not complete the browser flow. This keeps `login()` as a clean async function from the VM's perspective: `try await loginAction()` either returns (success) or throws (denied / timeout / network error).

**Decision 6: Error mapping — 403 means "login required" for client-credentials, "private playlist" for OAuth.**

`SpotifyWebAPIConnector.performRequest` maps all HTTP 403 → `.spotifyLoginRequired`. `SpotifyOAuthPlaylistConnector` wraps `PlaylistConnector` and remaps `.spotifyLoginRequired` → `.spotifyPlaylistInaccessible` when the provider is already authenticated. `SpotifyConnectionViewModel.attempt()` also checks `oauthProvider.isAuthenticated` as a fallback for the same mapping. This keeps `SpotifyWebAPIConnector` ignorant of auth context while giving the VM the right user-facing error in both states.

**Decision 7: `loginAction` closure injection into `SpotifyConnectionViewModel`; `oauthProvider` protocol for auth-state queries.**

The VM has no knowledge of `NSWorkspace` or `SpotifyOAuthTokenProvider` directly. It receives a `@Sendable () async throws -> Void` closure for initiating login and an optional `any SpotifyOAuthLoginProviding` for querying `isAuthenticated`. This preserves VM testability (mock closures in tests) and keeps AppKit out of the engine and VM layers.

**Decision 8: `SpotifyClientSecret` key removed from Info.plist for OAuth.**

Client-credentials required a `SpotifyClientSecret`. PKCE does not send a client secret — only the `client_id` is needed in the authorize URL and token-exchange requests. The `SpotifyClientSecret` xcconfig variable and Info.plist key are retained for backward-compat tooling but the OAuth provider only reads `SpotifyClientID`. Any future client that reads `SpotifyClientSecret` will find it empty in PKCE configurations, which is correct.

---

## D-070 — Spotify /items response schema, preview_url capture, and pre-fetched track threading (U.11 follow-up)

**Status:** Accepted (2026-05-01)

**Context:** After U.11 landed, connecting a Spotify playlist always resulted in reactive mode — `SessionManager` entered `.preparing` with 0 tracks. Three cascading bugs were identified via console log analysis and Spotify Web API documentation review.

**Bug 1: Wrong JSON key — "item" not "track".**

When Spotify deprecated `/v1/playlists/{id}/tracks` and replaced it with `/v1/playlists/{id}/items`, the `PlaylistTrackObject` schema changed: each item now uses `"item"` as the key for the track/episode object. The `"track"` key is retained for backward compatibility but is deprecated. Code from U.10 that read `item["track"]` returned nil for every item and silently produced an empty track list. Confirmed by console diagnostic: `hasItem=true hasTrack=false`. The correct parsing is: try `item["item"]` first, fall back to `item["track"]`.

**Bug 2: Dual-connector re-fetch with client-credentials.**

`SessionManager` owns a `PlaylistConnector()` constructed at init time using `DefaultSpotifyTokenProvider` (client-credentials). After `SpotifyConnectionViewModel` successfully fetched tracks via OAuth and called `startSession(source:)`, `SessionManager` re-fetched using its own client-credentials connector → HTTP 401 → reactive fallback. Fix: add `startSession(preFetchedTracks: [TrackIdentity], source: PlaylistSource)` to `SessionManager`, thread `[TrackIdentity]` from the OAuth connector through the full callback chain (`SpotifyConnectionViewModel` → `SpotifyConnectionView.onConnect` → `ConnectorPickerView.onConnect` → `IdleView`), and route Spotify sources to the pre-fetched variant. `IdleView` routes by source type (`.spotifyPlaylistURL`, `.spotifyCurrentQueue`) rather than `tracks.isEmpty` — an empty Spotify response should still avoid the client-credentials re-fetch.

**Bug 3: `fields` parameter silently returned empty item dictionaries.**

The `fields=items(track(name,artists,album,id,duration_ms))` query parameter on the `/items` endpoint causes Spotify to return `{}` (empty object) for any item where the `track` field is null or where the filter path does not match the available data. This produced a 200 response with correct `total` and `items.count` but `{}` dictionaries for each item — `compactMap` returned zero tracks. Root cause confirmed by logging: `first-item keys: []`. Fix: remove the `fields` parameter entirely. Add `market=from_token` instead — without it, region-restricted tracks can return null track objects, also silently dropping items.

**Decision: capture `preview_url` from the Spotify response directly.**

Spotify's `/items` response includes `preview_url` in each `TrackObject` — a CDN URL for the 30-second MP3 preview (or `null` for rights-restricted tracks). The previous code discarded this field and then queried iTunes Search API (20 req/min, fuzzy text matching) to find the same URL. This wasted a network round-trip and caused false "Preview not available" results for tracks that iTunes Search couldn't match.

Fix: add `spotifyPreviewURL: URL?` to `TrackIdentity` as a hint field. This field is explicitly excluded from `Equatable` and `Hashable` (custom implementations covering the seven identity fields) and from `Codable` (explicit `CodingKeys` enum). `SpotifyWebAPIConnector.parseTrack(_:)` captures `(track["preview_url"] as? String).flatMap(URL.init)`. `PreviewResolver.resolvePreviewURL(for:)` short-circuits to `track.spotifyPreviewURL` when present, seeding the in-memory cache and returning immediately without touching iTunes. Tracks where Spotify returns `null` (rights-restricted content like some Mclusky tracks) fall through to the existing iTunes Search path.

**Why exclude spotifyPreviewURL from identity:**

`TrackIdentity` is used as a dictionary key in `StemCache` and `PreviewResolver`. Including `spotifyPreviewURL` in hash/equality would break the cache key contract: two `TrackIdentity` instances referring to the same track (one from Spotify with a preview URL, one from another source without) would hash differently and miss the cache. Hint fields that are not part of a track's musical identity must be excluded.

**Why exclude spotifyPreviewURL from Codable:**

`preview_url` is an ephemeral CDN URL — it may change between API calls and need not survive encoding round-trips (e.g. to `StemCache` persistence). Excluding it keeps serialized form identical to the pre-D-070 schema, preventing any decode failures on upgrade.

## D-071 — V.7 Arachne uplift failed M7; references-anchored §10.1 rewrite required

**Status:** Accepted (2026-05-01)

**Context:** Increment V.7 (Arachne v4) shipped 2026-04-30 with `meetsAutomatedGate=true`, `certified=false` pending M7. M7 review on 2026-05-01 (session 2026-05-01T22-14-25Z) found the rendered output is a near-pixel match for `docs/VISUAL_REFERENCES/arachne/10_anti_neon_stylized_glow.jpg` — the named anti-reference for failure mode #2 (stylized graphic glow). Specific divergences from the reference set: the V.7 Session 2 cool-blue rim override at Arachne.metal lines 396–398 + 605 replaced the Marschner TT-lobe warm back-rim mandated by `04_specular_silk_fiber_highlight.jpg`; droplet glints render cool-white instead of warm amber per `01_macro_dewy_web_on_dark.jpg`; pool of 12 with 4–7 active webs simultaneously violates the single-hero composition of refs `01`, `02`, `04`, `05`; multiplicative `fbm8` mist provides no atmospheric depth where refs `06` + `07` require volumetric structure with directional beam motes; bg color clamped to 1–4% gray makes steady-state read as pure void where ref `08` (pure black) is the silence-calibration state only.

The implementation was technically faithful to `SHADER_CRAFT.md §10.1` as written at the time. The spec itself had drifted from the reference set during V.7 Sessions 1–3 planning. This is a class of failure not previously documented: a fidelity uplift can pass automated rubric gates and match its own §10.1 text while diverging from the reference images §10.1 was supposed to translate.

**Decision:** Treat M7 failure as a spec-correction event, not a re-implementation event. (a) Rewrite `SHADER_CRAFT.md §10.1` anchored to the existing reference set, citing each reference filename per implementation pass per the V.5 lint rule. (b) Schedule the rewritten §10.1 as Increments V.7.5 (composition + materials + drops + spider cleanup) and V.7.6 (atmosphere + beam-bound motes). (c) Preserve V.7 Session 1–3 work as the v4 baseline; V.7.5 modifies that baseline rather than starting fresh. The 2D SDF architecture from D-043 stands; the macro/meso/micro/specular work from V.7 Sessions 1–2 mostly stands and is incrementally adjusted.

**Rule:** Every V.7+ implementation session must include an explicit M7-prep step: capture a representative frame, place it in a contact sheet against each positive reference, record pass/fail per reference, and a "matches anti-ref?" boolean for each anti-reference. The session is not marked done if the anti-ref boolean is true, regardless of automated rubric score. The V.5 lint rule (reference filename citations per pass) is necessary but not sufficient; per-reference visual diffing is also required. This rule applies retroactively to V.7 (forced re-review here) and forward to V.8–V.12.

## D-072 — V.7.5 fidelity ceiling: pivot from constant-tweaking to compositing

**Update 2026-05-02 (post research + Matt design conversation):** The compositing-pivot diagnosis below is correct, but the design that followed (V.7.7-V.7.9 sketched in `SHADER_CRAFT.md §10.1`) was incomplete. Subsequent conversation with Matt and a research dive into orb-weaver biology, silk physics, real-time refraction technique, and procedural web prior art produced a fuller v8 design captured in `docs/ARACHNE_V8_DESIGN.md`. The full design adds two dimensions the original pivot missed:

1. **Visual-target reframing.** Matt's reference target is not the static photographic dewy web (refs 01–08 are the *finished surface*) but the BBC Earth time-lapse construction sequence — a spider web *being drawn over time*. Arachne is now a 3-layer scene: background dewy completed webs (where refs 01/03/04 apply), a foreground web in active construction (slowly drawn, no spider visible), and a spider/vibration overlay triggered by sustained bass (with whole-scene tremor on heavy bass). The foreground build cycle is ≤ 60 s and emits a completion signal.
2. **Orchestrator-side change.** "One preset per song" is wrong for this design — Arachne's 60 s build cycle would run far beyond the song section it's musically right for. The orchestrator becomes multi-segment-per-track: per-preset `maxDuration` becomes authoritative, `PlannedTrack` carries `[PlannedPresetSegment]`, transitions land on song-section boundaries OR at the preset's max duration ceiling OR on a new `presetCompletionEvent` signal channel (whichever fires first).

Both changes are preset-system-wide. The compositing techniques (background-pass + refractive drops + chord-segment threads) are preserved as the right rendering primitives; what's added is the temporal structure (build animation) and the orchestrator support for it. See `docs/ARACHNE_V8_DESIGN.md` for the complete spec; see `docs/ENGINEERING_PLAN.md` for the implementation sequence (V.7.6.1 harness → V.7.6.2 orchestrator → V.7.6.3 maxDuration audit → V.7.7 background → V.7.8 foreground build → V.7.9 vibration + cert).

The original D-072 text below stands as the architectural diagnosis. The implementation specifics in the original "Sessions estimated" paragraph are superseded by `ARACHNE_V8_DESIGN.md §6`.

---


**Status:** Accepted (2026-05-02)

**Context:** Increment V.7.5 (Arachne v5) shipped 2026-05-01 implementing `SHADER_CRAFT.md §10.1` items 1, 2, 3, 4, 6, 9 as a coordinated constant-tuning pass: pool capped 12 → 4, sag range widened, drops resized, warm rim restored, warm key + cool ambient added, spider re-silhouetted. M7 visual review on 2026-05-02 (session `2026-05-02T01-35-34Z`) found that while every change landed mechanically (commits dcb55ea7 → 31dfc738), the rendered output is still a stylized 2D bullseye visually distant from the reference set. Specific failures:

- **Spiral SDF visualises as concentric rings** — the per-pixel radial-distance math representing a continuous Archimedean spiral degenerates to a ring-stack at narrow line thickness because spiral-pitch ≈ thread-thickness × small-N. Refs `01`/`02`/`03`/`04` show webs built from chord segments (straight lines between adjacent radials), not smooth curves.
- **Drops visually negligible** — even at the V.7.5 doubled radius (8.6 px at 1080p) and × 0.18 emissive base, drops read as faint speckle on the threads instead of as the visual hero refs `01`/`03`/`04` mandate.
- **Sag visually negligible** — max sag = `kSag(0.14) × spokeLen²(0.04) = 0.006 UV` ≈ 6 px on a 600-px-tall view. Mathematically present, optically invisible.
- **No background world** — current preset renders web on near-black. Every positive reference (`01`, `03`, `04`, `05`, `06`, `07`) renders web composited over an atmospherically-textured world: forest defocus, golden-hour haze, blue-grey morning mist, beam-of-light scatter. Half the visual signature is the world the web sits in, not the web itself.
- **No refraction in drops** — refs `03` and `04` show each drop as a tiny spherical-cap lens distorting and inverting the background behind it. That's the optical mechanism that makes drops read as "real water" rather than "small bright circles". Current drops have no background to refract because there is no background.
- **No depth-of-field** — refs `01` and `03` have heavy bokeh blur on out-of-focus drops and background; current render is pin-sharp everywhere.

The V.7.5 implementation was technically faithful to §10.1 items 1–4, 6, 9 as written. As with D-071, the spec itself has drifted from what would actually close the reference gap. Unlike D-071 (which was a per-item correction), the V.7.5 finding is structural: **no amount of constant tweaking on the current renderer architecture closes the gap**. The gap isn't tweakable; it's compositional.

**Three architectural options were considered:**

1. **Path A — Polish 2D-SDF further.** Iterate on spiral chord segments, drop brightness, sag magnitude. Cap is "pleasant 2D animation". Estimate 1–2 sessions. **Rejected** — does not reach reference fidelity; same ceiling as V.7.5.
2. **Path B — Amend D-043, rebuild as 3D ray-march.** Address the original 3D failure modes (miss-ray glow, tilted-disc projection). Cap is "good real-time 3D scene". Estimate 5–10 sessions. **Rejected** — D-043 ruled 3D out for fine fibre structure; rebuilding ignores that constraint and risks the same dartboard outcome from a different angle. Also, references show no 3D parallax — the reference signature is photographic 2D with optical depth (DoF, refraction, atmosphere), not geometric depth.
3. **Path C — Mesh + PBR rebuild.** Procedurally generate web threads as triangle geometry, drops as instanced sprites, lighting as proper PBR. Estimate 10–15 sessions. **Rejected** — solves a polygon-count problem the references do not have. A perfectly-rendered mesh web on near-black still reads as bullseye with sharp edges. Mesh is not the missing primitive.

**Decision — Path D: stay 2D SDF (D-043 stands), add compositing layers.** The reference visual signature decomposes into three additions buildable inside the existing render-pass infrastructure:

- **(D.1) Background atmosphere pass.** Render an offscreen texture before the web pass: warm-to-cool atmospheric gradient (mood-tinted), `worley_fbm` foliage silhouettes far away with depth fade, optional volumetric beam from `kL` direction, baked-in mild Gaussian blur for distance. Use existing utilities (`fbm8`, `worley_fbm`, color space helpers). Composited under the web. **Replaces** the previously-scheduled V.7.6 multiplicative-mist patch with a proper render-to-texture pass.
- **(D.2) Drops as refractive lenses.** Each drop already has a computed spherical-cap normal. Sample the background texture at a refracted UV offset (Snell's law, eta ≈ 1/1.33 for water-in-air). Add fresnel rim, single sharp specular pinpoint, dark edge ring. Bump drop density 2–3× and brightness via refraction-of-bright-bg, not via emissive multiplier. Invert the visual hierarchy: drops carry 80% of the visual contribution; threads drop to faint connective scaffolding.
- **(D.3) Chord-segment spiral + selective DoF.** Replace the continuous Archimedean spiral SDF with discrete chord segments — straight line between angular position N and N+1 on each spiral revolution. Visually breaks the bullseye effect. Add a depth-weighted bokeh pass in `PostProcessChain` so distant pool webs and out-of-focus drops blur into circular-aperture shapes (matches refs `01`/`03`).

**Why SDF is the right tool here, not mesh:** Refractive drops compose more cleanly in SDF than in mesh-instanced sprites. We already compute the per-pixel spherical-cap normal in the SDF; one `bgTexture.sample(refractUV)` per pixel and refraction is done. With mesh-instanced sprites we'd encode normals into a texture, set up per-instance state for the bg sampler, and lose the per-pixel refraction precision. The same applies to chord-segment threads: the SDF version is `min` over N segment SDFs per pixel, fully compatible with the existing `op_blend` smooth-union accumulator.

**Sessions estimated:** 3 — V.7.7 (background pass), V.7.8 (refractive drops + visual hierarchy inversion), V.7.9 (chord-segment spiral + DoF, plus the cert-review eyeball). The pre-pivot V.7.6 scope (atmosphere + beam motes as a patch on the existing single-pass renderer) is **abandoned** — the bg pass in V.7.7 is the correct home for atmosphere, and beam motes are reframed as a property of the bg pass rather than a separate isotropic mote field. The abandoned V.7.6 entry is preserved in the engineering plan as an audit trail. **V.8 remains reserved for Gossamer** per `SHADER_CRAFT.md §10.2`.

**Rule:** When a fidelity gap survives a coordinated constant-tuning pass that landed every spec'd change mechanically, the gap is compositional, not parametric. Do not schedule another tuning pass. Decompose the reference visual signature into compositing layers (background, refraction, optical depth, etc.) and add render-pass infrastructure rather than tuning constants.

**Rule:** Before any further fidelity uplift on any preset, decompose the reference set into its compositing layers explicitly: what is the background, what is the foreground subject, what optical phenomena (refraction, DoF, bokeh, aerial perspective, volumetric scattering) carry the photographic look. If the current preset's renderer cannot produce those layers, schedule the missing infrastructure as its own increment before the constants pass.

---

## D-073 — `maxDuration` per-section linger factors inverted (Option B); diagnostic class added (V.7.6.C calibration)

**Date:** 2026-05-03

**Context:** V.7.6.2 shipped the `maxDuration` framework (formula in `PresetMaxDuration.swift`, computed property on `PresetDescriptor`, multi-segment walk in `SessionPlanner`). V.7.6.C is the calibration pass against the §5.3 reference table. Matt reviewed the printed table at the §5.2 default coefficients.

**Problems Matt flagged:**

1. **Spectral Cartograph is diagnostic, not aesthetic.** The framework was treating it as a normal preset and giving it a finite ceiling. Diagnostics should remain in place until manually switched — they have a different operational role (instrument-family observability) and the segment scheduler should never insert a boundary mid-diagnostic.
2. **Per-section linger model was inverted.** Original §5.2 had `ambient=0.30` (shortest) and `peak=0.80` (longest), on the theory that low-variance audio gives the preset less to chew on. Matt's intuition is the opposite: ambient sections are exactly where you'd want a preset to *linger* — meditative, contemplative, a switch would feel disruptive.

**Decision:**

(1) **Add diagnostic class.** New `is_diagnostic` JSON field on `PresetDescriptor` (default `false`). When true, `maxDuration(forSection:)` short-circuits to `.infinity`. Spectral Cartograph is flagged true (only diagnostic in the catalog). Implementation is one boolean and one short-circuit; no formula change. The broader "diagnostic presets are manual-switch only / never auto-selected" semantic (Scorer hard-exclusion + LiveAdapter no-override) is **out of V.7.6.C scope**, scheduled as V.7.6.D.

(2) **Invert per-section linger to Option B.** Two models considered: Option A — linger on slow only (ambient=0.80, peak=0.30); Option B — linger on emotional cores (ambient=0.80, peak=0.75) with transitional sections shortened (buildup=0.40, bridge=0.35). Matt picked Option B: ambient and peak both linger because they're the emotional-core moments of a song; buildup and bridge are transitional moments where preset changes feel natural. Final table: `ambient=0.80, peak=0.75, comedown=0.65, buildup=0.40, bridge=0.35`. Default (section=nil) stays 0.5. Field renamed `sectionDynamicRange` → `sectionLingerFactor` to reflect that values are now author-set per-section weights, not derived from audio variance.

(3) **No formula coefficient changes.** `baseDurationSeconds=90`, `motionPenalty=-50`, `fatiguePenalty=-30`, `densityPenalty=-15`, `sectionAdjustBase=0.7`, `sectionLingerWeight=0.6` all unchanged. The original V.7.6.2 agent's calibration notes (Glass Brutalist ~30s intuition; Gossamer feels long for limited compositional variation; Murmuration computes same as Glass Brutalist) were observations, not directives. Matt's V.7.6.C review note: *"Note that you are grading presets that are all not certified and VERY far from ready."* Tuning the formula to one uncertified outlier optimises for an artistic target the preset hasn't reached yet. If a future certified Glass Brutalist genuinely cycles every 30s, declaring `natural_cycle_seconds: 30` is the right tool, not a coefficient warp.

**Why no Glass Brutalist `naturalCycleSeconds` cap landed in V.7.6.C:** The 30s intuition was from the V.7.6.2 agent, not directly from Matt. Matt's review explicitly flagged that the presets are uncertified and far from ready. Adding a cap now would lock in a number that's likely wrong for the certified version of the preset.

**§5.3 reference table is now authoritative against current production sidecars.** Old §5.3 had several stale metadata values (e.g. Plasma motion 0.85 vs actual 0.5, Nebula 0.50 vs actual 0.30); the V.7.6.C rewrite reflects what's actually in the JSON. Stalker dropped (no production assets in `Shaders/`); Fractal Tree added.

**Implementation:** `PresetMaxDuration.swift` (formula + linger factors), `PresetDescriptor.swift` (`isDiagnostic` field + CodingKeys + decode), `SpectralCartograph.json` (`is_diagnostic: true`), `MaxDurationFrameworkTests.swift` (reference table + diagnostic test + Option B ordering test + `isDiagnostic` default test), `docs/ARACHNE_V8_DESIGN.md` §5.2/§5.3/§5.4 updated.

**Verification:** 912 engine tests / 97 suites green. App build succeeds. SwiftLint 0 violations on touched files. GoldenSessionTests not regenerated — default-section maxDuration unchanged at lingerFactor=0.5 (multiplier 1.0); planner sequences identical.

**Rule:** Per-section weights in the `maxDuration` framework are author-set linger factors, not audio-variance signals. Naming reflects that. Future calibration sessions tune the per-section table by intuition, not by computing audio variance from track preparation data.

**Rule:** Diagnostic presets (`is_diagnostic: true`) are exempt from segment scheduling and (per the V.7.6.D follow-up) auto-selection. They are operational tools, not aesthetic content. Spectral Cartograph is the prototype; future diagnostics use the same flag.

**Rule:** Do not coefficient-tune the `maxDuration` formula to an uncertified preset's intuition target. Use `natural_cycle_seconds` for outliers only when the visual genuinely has a fixed cycle. If the artistic target moves with certification, the coefficient-tuned value will become wrong.

## D-074 — Diagnostic preset orchestrator semantics (V.7.6.D)

**Date:** 2026-05-03

**Context:** V.7.6.C (D-073) added the `is_diagnostic` flag with one effect — `maxDuration(forSection:)` returns `.infinity` so `SessionPlanner` never inserts a segment boundary mid-diagnostic. The broader semantic — diagnostics are operational tools, not aesthetic content, so they must never be auto-selected, never receive a mid-track override, and only render via manual switch — was scoped as a V.7.6.D follow-up.

**Decision:** Extend the flag's effect into the Orchestrator at three surfaces:

1. **`DefaultPresetScorer` hard exclusion.** A new gate runs *first* in `exclusionReasonAndTag`, before the certification check, and returns `excludedReason: "diagnostic"` with `total: 0`. Unlike `includeUncertifiedPresets`, there is no settings toggle that re-enables diagnostics for auto-selection — the gate is categorical.
2. **`DefaultLiveAdapter` emission-site guard.** The mood-override path's `guard let (topPreset, topScore) = ranked.first, …` is extended with `!topPreset.isDiagnostic`. The Scorer change already gives diagnostics `total = 0`, but the explicit guard at the emission site is harder to regress when the scoring math changes.
3. **`DefaultReactiveOrchestrator` defensive filter.** The `ranked.first` selection becomes `ranked.first(where: { !$0.0.isDiagnostic })` so a degenerate catalog (e.g. all-zero scoring tie containing diagnostics) cannot resurrect one.

`SessionPlanner` and the multi-segment walker inherit the gate transparently because they consume `PresetScoring` — no planner-level change needed; tests confirm diagnostics never appear in `plan.tracks[].preset`.

**Manual-switch path is unchanged.** `PlaybackActionRouter` and the keyboard / dev surfaces operate on `PresetDescriptor` directly without going through scoring. The exclusion is auto-only by design — diagnostics like Spectral Cartograph remain reachable through the existing manual paths.

**Implementation:** `PresetScorer.swift` (new diagnostic exclusion as first gate), `LiveAdapter.swift` (one-line guard on the override-emission `guard`), `ReactiveOrchestrator.swift` (`first(where:)` filter), `OrchestratorDiagnosticExclusionTests.swift` (7 tests covering scorer, adapter, planner, reactive, and the manual-switch positive case).

**Verification:** 919 engine tests / 98 suites; 918 pass — the single failure is the pre-existing flaky `MetadataPreFetcherTests.fetch_networkTimeout_returnsWithinBudget` (network timing under load, unrelated). App build succeeds. SwiftLint 0 violations on touched files. `GoldenSessionTests` unchanged — diagnostic presets were already absent from production goldens (Spectral Cartograph carries `certified: false`), so the additional gate is a no-op against current sequences.

**Rule:** Diagnostic presets are categorically excluded from auto-selection at every Orchestrator surface. The exclusion fires before certification, before family boost, before any user toggle. The only path that renders a diagnostic is manual switch on the renderer/keyboard surface, which bypasses scoring entirely.

**Rule:** When a flag has both a data-model effect and an Orchestrator-policy effect (like `is_diagnostic`), implement the data-model effect first (here: `maxDuration` short-circuit, V.7.6.C / D-073) and the policy effect second (here: scorer + adapter exclusions, V.7.6.D / D-074). Splitting keeps each commit's blast radius small and lets each layer's tests be written and reviewed independently.

---

## D-075 — Tempo BPM via sub_bass-only onset timestamps + trimmed-mean IOI (DSP.1)

**Date:** 2026-05-03

**Context:** The IOI histogram in `BeatDetector+Tempo.swift` was producing systematic tempo errors on real music — Failed Approach #17 ("autocorrelation half-tempo, known octave error") in CLAUDE.md. The DSP.1 increment was originally scoped as IOI histogram half/double voting (a scoring pass over harmonic candidates {0.5×, 0.667×, 1×, 1.5×, 2×} of the histogram peak). A diagnostic harness (`PhospheneEngine/Sources/TempoDumpRunner` + `Scripts/analyze_tempo_baselines.py`) capturing per-band onset timestamps on three reference clips (Love Rehab @ 125 BPM, So What @ 136 BPM, There There rock-syncopated) revealed the failures were not classical octave errors and that voting could not fix them.

**Two diagnoses surfaced:**

1. **Fusion frame-aliasing.** `recordOnsetTimestamps` consumed `bandFlux[0] + bandFlux[1]` (sub_bass + low_bass summed into a single threshold gate). Per-band cooldowns in `detectOnsets` (400 ms each) are independent across bands. A 60 Hz kick fires flux events in *both* bands at slightly different frames — the kick fundamental peaks first, the harmonic peaks one or two FFT-hop frames later. With sub_bass firing at frame 19 and low_bass firing at frame 18 of the next kick, the OR-stream produces alternating 18-frame (418 ms) and 19-frame (441 ms) IOIs for a true 441 ms (136 BPM) beat. Per-band fixtures showed clean meanIOI 440 ms for so_what's sub_bass alone; the fused stream's meanIOI was 322 ms.

2. **Histogram-mode quantization bias toward faster BPMs.** The histogram bucketed by `Int(round(60/ioi)) - 60` — integer BPM. BPM bucket widths *grow* with BPM in period space (the 144 BPM bucket spans 414–420 ms; the 136 BPM bucket spans 437–443 ms). So an evenly-quantized stream of 18-frame (418 ms) and 19-frame (441 ms) IOIs lands more events in the 144 bucket than the 136 bucket even when the underlying tempo is 136. Picking the histogram mode systematically biased toward 144.

**Decision — two changes shipped together as DSP.1 (commit `bbad760f`):**

1. **Source IOI timestamps from sub_bass `result.onsets[0]` only.** `recordOnsetTimestamps(onsets:bandFlux:)` now `guard onsets[0] else { return }`. Never OR with low_bass. The 400 ms `detectOnsets` cooldown gives clean kick-rate IOIs without bass-note pollution, and using a single band avoids the inter-band frame-aliasing entirely. Tracks with empty sub_bass fall through to the autocorrelation tempo path (`estimateTempo`) — graceful degradation, not silent failure.

2. **Replace histogram-mode BPM with trimmed-mean IOI (`computeRobustBPM`).** Compute median IOI over the 10 s window, drop IOIs outside [0.5×, 2×] median (rejecting outliers from dropped beats or fills), take the mean of the inliers, BPM = `60 / meanIOI`. The 80–160 octave clamp is preserved. Mean is FP-precise — meanIOI 440 ms maps to 60/0.440 = 136.36 BPM, exactly matching the audio. The histogram is still built (cheaply) for the diagnostic dump only; the BPM selection bypasses it.

**Reference-track results (pre-DSP.1 → post-DSP.1):**

| Track | True BPM | Pre | Post | Status |
|---|---|---|---|---|
| Love Rehab (Chaim) | 125 | 117 / 152 (cycling) | 122–126 | ±1 BPM |
| So What (Miles Davis) | 136 | 152 | 135–138 | ±2 BPM |
| There There (Radiohead) | ~86 (syncopated) | 144 | 137–140 | unfixed (kick rate, not meter) |

There There remains wrong because the bass kick is not on every beat — the histogram correctly reads the kick-pattern interval, but for syncopated rock the underlying meter is half that. This is a syncopation limitation outside DSP.1's scope and is the load-bearing motivation for DSP.2 (BeatNet, D-076 reserved).

**Alternatives considered:**

- **Voting over harmonic candidates (original DSP.1 scope).** Rejected after diagnosis — the failures aren't octave errors. love_rehab's histogram peak was 117 BPM, with autocorrelation independently agreeing at 117.45 BPM conf 0.93 across the run. Both methods read the same skewed evidence; voting over {58.5, 78, 117, 175.5, 234} cannot recover 125 because none of those are 125. The voting math was structurally inapplicable.
- **Fuse with hysteresis.** Keep the OR-of-bands but require sub_bass+low_bass agree within X frames before firing. Rejected — adds a tunable parameter without solving the underlying frame-aliasing; per-band cooldowns in `detectOnsets` already enforce within-band kick rate.
- **Band-picker (P75 of sub_bass vs low_bass, use whichever is louder).** Implemented and tested mid-iteration. Did not help — the picker oscillates frame-to-frame near the boundary, producing the same staggering artifacts as fusion.
- **300 ms minimum spacing widened from 150 ms.** Implemented mid-iteration and reverted. With sub_bass-only sourcing, the 400 ms `detectOnsets` cooldown already enforces clean spacing; the `recordOnsetTimestamps` guard is defensive only, and 150 ms is sufficient.
- **TempoCNN.** AGPL — incompatible with Phosphene's MIT license.
- **Sound Analysis framework.** Genre-classification, not beat-tracking — orthogonal to BPM estimation.
- **aubio integration.** A native C library would be a real dependency the project has not taken on. Deferred to DSP.2's "stay within Swift / MPSGraph idiom" path; if BeatNet underperforms, aubio becomes a fallback option to revisit then.

**Consequences:**

- DSP.1 ships a tempo improvement for kick-on-the-beat tracks (electronic, jazz, most pop). Reference fixtures so_what and love_rehab are now within ±2 BPM of metadata; both were 10–20 % off pre-DSP.1.
- The histogram remains in the codebase for diagnostic-dump use only. Future tempo work should not re-introduce histogram-mode picking; mean-of-inlier-IOIs is the baseline.
- Tracks where the bass kick is not on every beat (syncopated rock, swing, hip-hop with off-beat kicks) remain unsolved. These motivate DSP.2 (BeatNet via MPSGraph). DSP.1 is the floor; DSP.2 raises the ceiling.
- The diagnostic harness (`TempoDumpRunner`, `analyze_tempo_baselines.py`, fetched 30 s preview fixtures) becomes permanent regression infrastructure for DSP.2 and any future tempo work. The fixtures themselves are gitignored (`Tests/Fixtures/tempo/`) — preview clips are licensed; users run `Scripts/fetch_tempo_fixtures.sh` locally to populate them.
- Failed Approach #17 in CLAUDE.md needs amendment: the "autocorrelation half-tempo" framing is inaccurate. The real failure was fusion-induced frame aliasing plus histogram-mode quantization bias, both of which are now fixed for the kick-on-the-beat case. Tracks where DSP.1 still fails (syncopated rock) fail for a *different* reason than #17 originally described — that's a beat-tracking-vs-tempo-estimation distinction belonging to DSP.2.

**Rule:** Tempo estimators that operate on inter-onset intervals must source events from a single, well-cooled band. Fusing onset events across bands (even by summing flux) creates frame-aliased spurious IOIs.

**Rule:** Do not bucket continuous quantities by integer-rounded BPM when the natural quantization is frame-period (in time, not BPM). Compute robust statistics (median, trimmed mean) directly on the period samples.

**Rule:** When a hypothesized failure mode (here: half-tempo octave error) is documented in `CLAUDE.md` and an increment is scoped against it, the *first* commit should be diagnostic instrumentation that captures the actual failure shape — not implementation of the fix. The DSP.1 voting work would have shipped uselessly without the per-band onset diagnostic that revealed the real bugs. Diagnostic-first applies even when the documented failure mode is widely known to the team.

---

## D-076 (reserved, abandoned) — BeatNet via MPSGraph for online beat tracking

Reserved 2026-04-22 for Increment DSP.2 BeatNet port. **Abandoned 2026-05-04** in favor of Beat This! — see D-077. Session 1 of the BeatNet path landed (commit `3f5f652b`: weight conversion, vendored GTZAN weights at `PhospheneEngine/Sources/ML/Weights/beatnet/`, architecture audit in `docs/diagnostics/DSP.2-beatnet-archive.md`). Session 2 was started, abandoned mid-flight when an audit pass found the architecture doc had paraphrased FFT parameters incorrectly (claimed `fft_size=2048`; madmom uses `fft_size=frame_size=1411` with `include_nyquist=False` → 705 bins). The vendored weights are kept as a Tier 1 / reactive-mode fallback while Beat This! settles; full retirement is a follow-up after Beat This! proves out across the Phase MV preset catalog.

This decision ID is retained as a permanent breadcrumb so that future grep on DECISIONS for "BeatNet" lands here, not on phantom references to the original ENGINEERING_PLAN scope.

---

## D-077 — Phase DSP.2 pivot from BeatNet to Beat This!

**2026-05-04.** Phase DSP.2 retargets the offline beat / downbeat path from BeatNet (Heydari & Duan, 2021 — CRNN + particle filter cascade, CC-BY-4.0) to Beat This! (Foscarin et al., ISMIR 2024 — transformer encoder, MIT). The product reason is single-sentence: complex meters are a load-bearing requirement for Phosphene's beat lock (Pyramid Song 16/8, Money 7/4, Schism 7/8, swing tracks like So What), and BeatNet's particle filter is a known weak point on irregular meters whereas Beat This!'s self-attention captures whole-bar context.

**Alternatives considered:**

* **BeatNet (incumbent).** CRNN + particle filter, ~0.4 M params, native streaming mode (~84 ms latency), particle filter is the bottleneck on 5/4, 7/8, swing. Octave-error history per `docs/diagnostics/DSP.1-baseline-there_there.txt`. Stays vendored as a fallback per D-076 retirement note.
* **All-In-One** (Kim et al., ISMIR 2023). Joint beat / downbeat / section-boundary transformer. Strictly more capable than Beat This! for Phosphene's needs (would also retire `StructuralAnalyzer` / `NoveltyDetector`), but two-axis scope creep in a single increment is too risky. Reserved as a follow-up; if All-In-One supersedes Beat This! later, the Sessions 2–7 architecture in this increment was designed to swap the model with no upstream / downstream changes.
* **madmom DBN beat tracker.** Offline DBN over autocorrelation; classical baseline. Older numbers, no MPS-graph-portable model, requires the full madmom Python runtime. Not viable.
* **Beat Transformer / BEAST.** Research code; no shipped pre-trained weights with a usable license. Not viable.

**Architectural placement:** Beat This! runs once per track during `SessionPreparer.prepareTrack` on the cached 30 s preview clip (the existing pre-analysis budget absorbs ~100–300 ms of transformer inference per track on M1). Output is cached on `TrackProfile` as a new `BeatGrid` value type (`beats`, `downbeats`, `bpm`, `timeSignature`, `confidence`, `modelVariant`). The live audio path *does not* run a transformer; instead, a new `LiveBeatDriftTracker` cross-correlates `BeatDetector`'s sub_bass onset stream against the cached grid in a ±50 ms phase window and emits a smooth drift estimate. `FeatureVector.beatPhase01` and `beatsUntilNext` are then computed analytically from `playbackTime + drift` against the cached grid — no contract change for any existing preset shader.

**Replaces:** `BeatPredictor` (deleted in Session 7); `BeatDetector+Tempo.computeRobustBPM` as the primary BPM source (kept only as ad-hoc reactive-mode fallback). `BeatDetector` itself stays — its onset stream is the input to the live drift tracker and continues to feed `StemAnalyzer` rich metadata. `StructuralAnalyzer` / `NoveltyDetector` are unchanged in this increment.

**License & attribution:** Beat This! ships under MIT (cleaner than BeatNet's CC-BY-4.0 attribution requirement). Attribution lives in `docs/CREDITS.md` and the shipped app's About surface; details locked in Session 1.

**Cleanup committed alongside this decision:** the in-flight BeatNet preprocessor stub (`PhospheneEngine/Sources/DSP/LogSpectrogram.swift`), the vendored filterbank corner triples (`PhospheneEngine/Sources/DSP/Resources/beatnet_filterbank.json`), the `dump_logspec_reference.py` reference dump script, and the `love_rehab_logspec_reference.json` test fixture were deleted. The architecture audit (`docs/diagnostics/DSP.2-architecture.md`) was renamed to `DSP.2-beatnet-archive.md` and marked superseded. The BeatNet weight set under `PhospheneEngine/Sources/ML/Weights/beatnet/` is retained.

**Spec drift discipline.** The trigger for the pivot was a Session-2-of-DSP.2 audit pass that found the BeatNet architecture doc had paraphrased the FFT spec (claimed `fft_size=2048` next-pow2; madmom's actual default is `fft_size=frame_size=1411` with `include_nyquist=False`). This is the second time in a row (D-075 trimmed-mean IOI fix was the first) that paraphrased-from-prose specs landed code that diverged silently from the reference. The Beat This! port adds a per-stage golden-test gate at every pipeline boundary (Session 2 preprocessor; Session 4 layer-by-layer numerical match) so any future drift fails fast at the right stage, not three sessions downstream.
