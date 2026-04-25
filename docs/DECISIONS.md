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

**Decision 4: `.spotifyAuthRequired` silently degrades to `startSession`.**

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

## D-053 — PresetScoringContext extended with excludedFamilies + qualityCeiling; defaults preserve backward compat (Increment U.8)

**Status:** Accepted (2026-04-24)

**Context:** U.8 Settings adds two user-configurable gates that must influence preset selection: a family blocklist and a quality ceiling. These gates belong in `PresetScoringContext` (the immutable snapshot passed to `DefaultPresetScorer`) rather than in the scorer's internal logic, so the context remains the single source of truth for session state at scoring time.

**Decision:** Add `excludedFamilies: Set<PresetCategory> = []` and `qualityCeiling: QualityCeiling = .auto` to `PresetScoringContext`, both with defaults. All existing callers that omit the new params continue to compile and behave identically (empty blocklist, auto ceiling). `DefaultPresetScorer.exclusionReason` checks `excludedFamilies` first, then applies `qualityCeiling.complexityThresholdMs(for:)` as the budget cap (`.ultra` returns nil → no complexity gate; `.performance` returns 12 ms → stricter than the frame budget).

**`QualityCeiling` placement:** New enum in `Orchestrator` module (not `Presets`). It maps to scoring logic (complexity thresholds) rather than to visual/preset metadata. `PresetScoringContext` already imports `Orchestrator`-local types, so no new cross-module dependencies are introduced.

**`PresetScoringContextProvider` (Part C):** Reads `settingsStore.excludedPresetCategories` and `settingsStore.qualityCeiling` and propagates them through `build()`. This is the only call site that needs updating — all other `PresetScoringContext` constructions (engine tests, golden session tests) use the defaults.
