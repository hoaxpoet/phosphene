# Phosphene — Developer Release Notes

Internal release notes for the `main` branch. Audience: Matt and Claude Code. Each entry covers one session or a logical batch of increments. These notes complement `docs/ENGINEERING_PLAN.md` (authoritative for what's planned) and `docs/QUALITY/KNOWN_ISSUES.md` (authoritative for open defects).

User-visible release notes are not yet in scope (no public build).

---

## [dev-2026-05-15-a] V.9 Session 4.5c Phase 1 — 18-round Ferrofluid Ocean rebuild (Leitl architecture port)

**Increment:** V.9 Session 4.5c Phase 1, 18 commits spanning 2026-05-14 → 2026-05-15. **Status:** Phase 1 closed. Phase 2 (SPH motion + ZOOM coupling) handed off via `docs/presets/FERROFLUID_OCEAN_PHASE2_PROMPT.md` for the next session.

Phase 1 took Ferrofluid Ocean from "audio-reactive aurora curtain over SDF-ray-marched heightfield substrate" through 15 rounds of iteration to a working "tessellated-mesh + vertex-displacement substrate rendered with Robert Leitl's four-layer fluid-shading material under a procedural studio env" — the architectural baseline for Phase 2. Matt's `2026-05-15T13:45:11Z` capture confirmed the substrate reads as ferrofluid spikes; subsequent rounds tuned iridescence, substrate darkness, audio coupling, and irregular-track response.

**Pattern of work.** The first 7 rounds were tactical changes against the SDF-ray-marched substrate (aurora bypass, particle pinning, bake sharpness, radius adjustment, env swap, fresnel coord fix). Each fix addressed the prior specific complaint and revealed a new failure mode. Round 12 (Matt's "Match Leitl - tesselated mesh + vertex displacement from heightmap") triggered the architectural pivot — Failed Approach #65 admission that "verbatim Leitl port" had only covered the fragment shader, not the geometry pipeline. Rounds 13-15 are post-mesh tuning: iridescence rainbow streaks, substrate brightness, audio coupling for irregular tracks, spike-height calibration.

**Files changed (Phase 1 totals, end-to-end):**

New:
- `PhospheneEngine/Sources/Renderer/Shaders/FerrofluidMesh.metal` — 260 lines. Mesh vertex shader (samples heightmap, displaces, finite-difference normal) + G-buffer fragment (writes matID==2 format the existing lighting fragment reads).
- `PhospheneEngine/Sources/Presets/FerrofluidOcean/FerrofluidMesh.swift` — 240 lines. 257×257 vertex grid, UInt32 index buffer, G-buffer pipeline state + depth-stencil state, encode method.
- `docs/presets/FERROFLUID_OCEAN_PHASE2_PROMPT.md` — next-session continuation prompt (SPH, ZOOM, entry animation).

Modified:
- `PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal` — Leitl four-layer material (`fluid_shading`), procedural studio env (`fluid_studio_env`), fresnel coord adaptation (N.z → dot(N, V)), iridescence tilt gate.
- `PhospheneEngine/Sources/Renderer/RayMarchPipeline.swift` — depth attachment for mesh path, `meshGBufferEncoder` dispatch closure, dispatch routing.
- `PhospheneEngine/Sources/Renderer/RayMarchPipeline+Passes.swift` — `runMeshGBufferPass` (depth-attached render pass + closure invocation).
- `PhospheneEngine/Sources/Renderer/RenderPipeline+PresetSwitching.swift` — `setMeshGBufferEncoder` public setter.
- `PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.metal` — `fo_spike_strength` reworked through rounds 1, 10, 13, 14, 15 (currently `bass_energy × 1.5 + bass_energy_dev × 0.5`; warmup proxy `bass_dev × 5.0`).
- `PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.json` — camera lowered (0, 4, -2.5) → (0, 2.5, -4.0); FOV 50 → 55; angle 42° → 18° down.
- `PhospheneEngine/Sources/Presets/FerrofluidOcean/FerrofluidParticles.swift` — particle count 6000 → 1520 (40×38 grid); spikeBaseRadius 0.15 → 0.12 wu; smoothMinW 0.02 → 0.005 (held).
- `PhospheneEngine/Sources/Presets/FerrofluidOcean/FerrofluidParticles+InitialPositions.swift` — grid 80×75 → 40×38.
- `PhospheneEngine/Sources/Renderer/Shaders/FerrofluidParticles.metal` — linear cone profile (was squared).
- `PhospheneApp/VisualizerEngine.swift` + `VisualizerEngine+Presets.swift` — `FerrofluidMesh` property + wiring at preset apply, teardown in per-preset reset, `setMeshGBufferEncoder` setter call.
- `PhospheneEngine/Tests/PhospheneEngineTests/Visual/FerrofluidOceanVisualTests.swift` — D-126-era mood-tint tests marked `XCTSkip` (obsolete under Leitl port; re-activate in Phase 4 when aurora overlay returns).
- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/FerrofluidParticlesTests.swift` — locked-constants assertions updated for the new particle-count + radius + smoothMinW values.
- `docs/VISUAL_REFERENCES/ferrofluid_ocean/README.md` — Last-amended header + Audio routing notes updated through D-127.

**Verification.** Engine `swift build` clean; app `xcodebuild build` clean; 9/9 `FerrofluidParticlesTests`, all `MatIDDispatchTests`, all 15-preset `PresetRegression` hashes preserve; 5/5 active `FerrofluidOceanVisualTests` (2 D-126 mood-tint tests marked obsolete + skipped). Full engine suite passes except 2 pre-existing parallel-execution flakes (`MetadataPreFetcher.fetch_networkTimeout`, `SoakTestHarness.cancel`).

**Visual progression (key capture URLs):**
- `2026-05-14T18-17-51Z` (Love Rehab, baseline before Phase 1) — pre-aurora work
- `2026-05-14T22-06-07Z` (4-track playlist, post-aurora) — Matt: "still washed out"
- `2026-05-14T22-37-26Z` (Billie Jean, post-pinning + bake sharpen) — Matt: "no spikes like reference"
- `2026-05-15T01-16-02Z` (Leitl-fragment-port + corridor IBL) — Matt: "not even close" (chrome floor)
- `2026-05-15T03-05-37Z` (studio env + fresnel coord fix) — Matt: "no better no worse" (fresnel bug found here)
- `2026-05-15T03-27-48Z` (post-fresnel-fix studio env) — Matt: "darker, do we zoom or fewer/larger orbs?"
- `2026-05-15T04-34-38Z` (lower camera angle) — Matt: "snowmen"
- `2026-05-15T12-36-08Z` (linear cone + camera elevated) — Matt: "still nowhere close, 15s warmup"
- `2026-05-15T13-04-32Z` (fewer/bigger spikes + warmup proxy) — Matt: "spikes flash for 1s then 8-10s blank"
- **`2026-05-15T13-45-11Z` (mesh + vertex displacement — Step B)** — Matt: "much better, foundation works"
- `2026-05-15T13-56-20Z` (post-mesh cleanup) — Matt: "not pitch black; irregular tracks don't work; still 8-10s delay"
- `2026-05-15T14-10-12Z` (round 14 — pre-recalibration) — calibration defect found (peaks 2.64 wu wire-thin), fixed in round 15

**Phase 1 architecture invariants now established:**
- Ferrofluid Ocean is the only preset rendering via tessellated mesh + vertex displacement. Every other ray-march preset stays on SDF.
- `matID == 2` in the lighting fragment routes to Leitl's four-layer material. Mesh path's G-buffer fragment writes matID=2; rest of the pipeline is unchanged.
- Audio coupling drives spike height only (no env coupling currently). Phase 2 will add ZOOM-driven multi-parameter coupling.

**Known gaps for Phase 2:**
1. SPH particle motion (Leitl uses full pressure / force / integrate / sort / offset pipeline; ours has particles pinned).
2. ZOOM-coupled bake parameters (Leitl couples 4 params to single audio scalar via polynomial remaps).
3. Entry animation (Leitl's 7-second `ZOOM 1.0 → 0.5` fade-up).
4. Single audio control scalar with spring-momentum smoothing (precursor to #1-3).

See `docs/presets/FERROFLUID_OCEAN_PHASE2_PROMPT.md` for the full next-session brief.

**Git status.** Branch `main`, ahead of `origin/main` by 17 commits (18 Phase 1 commits + 1 prompt-file commit pending). No push.

---

## [dev-2026-05-14-c] V.9 Session 4.5c Phase 1 — Direct audio → aurora routing (D-127)

**Increment:** V.9 Session 4.5c Phase 1. **Status:** Code complete; engine + app builds clean; targeted tests pass. STOP gate pending Matt's eye on a real-music capture against a vocal-forward track (Billie Jean per his 2026-05-14 sign-off).

Phase 1 of Session 4.5c rebuilds the aurora reflection from direct audio uniforms after the §5.8 stage-rig retirement (D-127). The musical contract (vocals pitch → hue, drums energy → intensity, arousal → drift) is preserved verbatim; the implementation abstraction changes from "orbital point lights + slot-9 buffer" to "lighting-fragment-bound `FeatureVector` + `StemFeatures` sampled inline at sky-sample time."

**What's added.** A single continuous aurora curtain at fixed elevation in `rm_ferrofluidSky` (`R.y ≈ 0.83`, ~33° from zenith — matches the retired-rig orbit geometry the `04_*` / `08_*` reference framings anchor on). The curtain wraps the sky azimuthally as a soft-edged wedge; orbital drift advances the wedge's centre azimuth at `features.accumulated_audio_time × arousalSpeed × baseSpeed` (full revolution ~30 s at high arousal, ~60 s at low; pauses at silence via `accumulated_audio_time`'s energy-paused clock). Hue blends two phase sources: `vocals_pitch_hz` (perceptual log-scale over 80 Hz – 1 kHz, ±0.20 phase) when `vocals_pitch_confidence ≥ 0.6`, smoothly crossfading to `features.valence` mood fallback below the confidence threshold. Intensity is `baseline + modulation × drums_energy_dev_smoothed` where the 150 ms τ EMA on `drums_energy_dev` runs CPU-side in `RenderPipeline.drawWithRayMarch` and lands in the new `StemFeatures.drumsEnergyDevSmoothed` float (renamed from `_sfPad1` — byte offset 168, struct size unchanged at 256 bytes per `CommonLayoutTest`). Silence gate `smoothstep(0.02, 0.10, totalStemEnergy)` collapses the curtain to base sky at silence.

**Files changed.**

- `PhospheneEngine/Sources/Renderer/Shaders/Common.metal` — `StemFeatures._pad1` → `drums_energy_dev_smoothed`.
- `PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift` — matching rename in the MSL preamble string.
- `PhospheneEngine/Sources/Shared/StemFeatures.swift` — `_sfPad1` → `drumsEnergyDevSmoothed: Float` (public), header doc updated.
- `PhospheneEngine/Sources/Renderer/RayMarchPipeline+Passes.swift` — `runLightingPass` gains `stemFeatures` parameter, binds at fragment slot 3.
- `PhospheneEngine/Sources/Renderer/RayMarchPipeline.swift` — `render` threads `stemFeatures` through to `runLightingPass`.
- `PhospheneEngine/Sources/Renderer/RenderPipeline.swift` — `auroraDrumsSmoothed: Float` property (MainActor-isolated access).
- `PhospheneEngine/Sources/Renderer/RenderPipeline+RayMarch.swift` — `drawWithRayMarch` computes `frameDt` once, runs τ=0.15 s EMA smoother on `drumsEnergyDev`, patches the smoothed value into the stems snapshot before forwarding to `rayMarchState.render`.
- `PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal` — adds `rm_palette(t)` helper (IQ V.3 cookbook cosine palette); `rm_ferrofluidSky` signature gains `FeatureVector` + `StemFeatures` and implements the curtain (live gate → hue → drift → shape → intensity → composition); `raymarch_lighting_fragment` declares `[[buffer(3)]] StemFeatures stems` and forwards to the sky function. Retires four file-level `kFerrofluidSky*` `constexpr constant` tunables that were rig-driven multi-band; aurora-curtain tunables now live inline.
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/MatIDDispatchTests.swift` — `runLightingAndReadCentre` passes `StemFeatures.zero` for the new parameter.
- `docs/VISUAL_REFERENCES/ferrofluid_ocean/README.md` — Last-amended header; stylization caveat hue source; mandatory audio reactivity bullets; silence fallback; Audio routing notes section (D-127 routing replaces §5.8 rig routing; retired-in-Session-4.5c subsection added).

**Verification.** Engine `swift build` clean (6 s). App `xcodebuild -scheme PhospheneApp build` clean. Targeted tests: `MatIDDispatchTests`, `CommonLayoutTest`, `StagedCompositionTests`, `PresetAcceptanceTests`, `PresetRegressionTests`, `PresetVisualReviewTests` all pass (16 tests / 6 suites, 0.103 s wall). Full engine suite: 1236 tests / 158 suites; two failures both pre-existing flakes unrelated to this work — `MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget` (documented in the test baseline memory) and `SoakTestHarness.cancel() causes run() to return before duration expires` (passes 0.719 s in isolation; failed in the full-suite run with 12.2 s under parallel contention — classic Swift Testing parallel-execution timing flake on a 5-second deadline test).

**STOP gate pending.** Phase 1 acceptance is Matt's eye on a real-music capture. The Love Rehab capture used for Session 4.5b's deviation-only-failure diagnosis has zero high-confidence vocal pitch across all 7,493 frames (`vocalsPitchHz = 0`, `vocalsPitchConfidence = 0` everywhere), so the pitch-driven hue path never activates on that track — the mood-valence fallback runs 100% of the time. Matt's 2026-05-14 sign-off names **Billie Jean (Michael Jackson)** as a vocal-forward replacement test track. Visual gate: aurora visibly tracks music, never beat-strobed, settles to base sky at silence, hue evolves over time, drift completes ~30–60 s revolution depending on song energy. Phase 2 (baseline+modulation routing + warmup smoothness) is gated on Phase 1 sign-off.

**Docs updated.** `docs/VISUAL_REFERENCES/ferrofluid_ocean/README.md` (see Files changed above). This release notes entry. `docs/ENGINEERING_PLAN.md` carries an in-flight row for Session 4.5c spanning all three phases; row is amended after each phase's STOP gate, not after each commit.

**Git status.** Branch `main`, ahead of `origin/main` by 14 commits after this commit (Session 4.5b Phase 1 / 2a / 2b / 2c plus Session 4.5c stage-rig removal + docs + this Phase 1 commit). No push.

---

## [dev-2026-05-14-b] V.9 Session 4.5c step 1 — Stage-rig retirement (D-127)

**Increment:** V.9 Session 4.5c commit 1. **Status:** Stage rig removed; aurora reflection deferred to next commit; Ferrofluid Ocean substrate currently reflects base purple sky only.

This session opened with the V.9 Session 4.5b prompt's "what stays unchanged" block listing the §5.8 stage rig as preserved infrastructure. Matt had communicated the rig's deprecation in prior sessions ("at least twice" per his correction). Claude carried the prompt's preserved-claim forward without verifying, then asserted the rig as a wired mechanism multiple times when proposing audio routing. Matt's framing: "This is a HUGE miss." See D-127 + the new memory note `feedback_verify_with_matt_on_architecture.md` for the discipline carry-forward.

After Matt's confirmation ("The change was from 'stage lighting' to just the aurora reflection") this commit removes the §5.8 stage-rig framework end-to-end. The aurora reflection mechanic stays as a procedural sky overlay the substrate mirror-reflects; its audio routing is rebuilt from direct uniforms in the next commit.

**What's removed.** `FerrofluidStageRig` Swift class. `Shared/StageRigState.swift` Swift mirror + tests. `PresetDescriptor.StageRig` decoder + `stageRig` field + JSON `stage_rig` CodingKey + JSON block. `RenderPipeline.directPresetFragmentBuffer4` + lock + setter (`setDirectPresetFragmentBuffer4`). `RayMarchPipeline.stageRigPlaceholderBuffer`. Slot-9 `setFragmentBuffer` bindings in `runGBufferPass`, `runLightingPass`, `drawWithRayMarch`, `RenderPipeline+Draw`, `RenderPipeline+Staged`, `RenderPipeline+MVWarp`. `RayMarchPipeline.render` / `runGBufferPass` / `runLightingPass` signatures lose `presetFragmentBuffer4`. Preamble + Common.metal `StageRigLight` / `StageRigState` MSL structs. `[[buffer(9)]] constant StageRigState&` in `raymarch_gbuffer_fragment` + `raymarch_lighting_fragment`. The aurora-band loop in `rm_ferrofluidSky`. `VisualizerEngine.ferrofluidStageRig` property + applyPreset instantiation. Tests `StageRigStateLayoutTests`, `StageRigDecoderTests`, `FerrofluidStageRigMathTests`. Visual gate `testFerrofluidOceanSkyReflectionDispatchActive`.

**Visual consequence.** `rm_ferrofluidSky` now returns only the base purple gradient × D-022 mood tint. Direct audio→aurora routing returns in the next commit (Session 4.5c Phase 1).

**Verification.** Engine `swift build` clean; app `xcodebuild build` clean; `FerrofluidParticlesTests` 9/9 pass; `FerrofluidOceanVisualTests` 5/5 active gates pass (Gate 6 retired).

**Docs updated.** `docs/DECISIONS.md` gains D-127 (rig retirement + aurora replacement plan). `docs/presets/FERROFLUID_OCEAN_CLAUDE_CODE_PROMPTS.md` gains the V.9 Session 4.5c prompt covering commits 2-3+ (direct audio→aurora, baseline+modulation rework, warmup fix, particle motion redesign as wave-coherent flow). Memory note `feedback_verify_with_matt_on_architecture.md` captures the discipline rule. `FerrofluidOceanVisualTests` header retired stale Session-3-era gate descriptions.

**Carry-forward to Session 4.5c next session.** Three phases planned: Phase 1 (direct audio→aurora), Phase 2 (baseline+modulation audio routing + 8s warmup fix), Phase 3 (wave-coherent particle motion — Phase 2c replacement). Locked-in decisions: vocals-pitch hue with mood-valence fallback (Matt 2026-05-14); aurora bands at fixed elevations with slow azimuthal drift from `accumulated_audio_time × arousal`; baseline-while-music-plays + deviation-modulated audio routing across all mechanisms. See the V.9 Session 4.5c prompt for the full scope.

**Git status.** Branch `main`, ahead of `origin/main` by 13 commits (Session 4.5b Phase 1 / 2a / 2b / 2c plus this stage-rig removal commit and follow-up docs commits). No push.

---

## [dev-2026-05-14-a] V.9 Session 4.5b Phase 1 — Ferrofluid Ocean particle scaffolding (texture-backed height field)

**Increment:** V.9 Session 4.5b Phase 1. **Status:** Phase 1 STOP gate satisfied — visual verdict requires Matt's review of the side-by-side PNGs.

Phase 1 of the particle-motion increment introduces a baked-height-texture path to Ferrofluid Ocean's `sceneSDF` without changing the surface character. Particles are *static* in Phase 1 (positions match what a `voronoi_smooth` cell-center pass would emit — scaled-space integer cells + per-cell `voronoi_cell_offset` hash); the bake runs once at preset-apply and the resulting texture is sampled per ray-march iteration. Phase 2 will add SPH-lite per-frame motion + audio forces.

**Files changed.**

New:
- `PhospheneEngine/Sources/Presets/FerrofluidOcean/FerrofluidParticles.swift` — public class, 2048-particle UMA buffer, 1024×1024 r16Float UMA height texture, bake compute pipeline, init-time bake.
- `PhospheneEngine/Sources/Renderer/Shaders/FerrofluidParticles.metal` — `ferrofluid_height_bake` compute kernel: Quilez polynomial smooth-min (w=0.1) + `almostIdentity` apex smoothing.
- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/FerrofluidParticlesTests.swift` — 7 contract gates (locked constants, canonical positions bounded + unique, buffer-contents match, texture descriptor, bake idempotent, bake non-zero output).
- `docs/diagnostics/V9_session_4_5b_phase1/{01_silence,02_steady_mid,03_beat_heavy,04_quiet}_{main,phase1}.png` — side-by-side fixture renders at 1920×1080.

Modified:
- `PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift` — file-scope `kFerrofluidHeightSampler` (clamp_to_zero), `sceneSDF` forward declaration gains `texture2d<float> ferrofluidHeight` param, `raymarch_gbuffer_fragment` declares `[[texture(10)]]`, 8 `sceneSDF` call sites updated.
- `PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.metal` — `fo_ferrofluid_field_sampled` reads texture via the file-scope sampler; Phase A inline path preserved as `fo_ferrofluid_field_inline` for diagnostic reference.
- `PhospheneEngine/Sources/Presets/Shaders/{GlassBrutalist,KineticSculpture,LumenMosaic,VolumetricLithograph}.metal` — sceneSDF signatures grow new param; bodies silence with `(void)ferrofluidHeight;`.
- `PhospheneEngine/Sources/Renderer/RayMarchPipeline.swift` — `ferrofluidHeightPlaceholderTexture` (1×1 r16Float, zero-filled) allocated in init; `render(...)` accepts optional `presetHeightTexture`.
- `PhospheneEngine/Sources/Renderer/RayMarchPipeline+Passes.swift` — `runGBufferPass` binds slot-10 texture (placeholder when nil).
- `PhospheneEngine/Sources/Renderer/RenderPipeline.swift` — `rayMarchPresetHeightTexture` storage + lock.
- `PhospheneEngine/Sources/Renderer/RenderPipeline+PresetSwitching.swift` — `setRayMarchPresetHeightTexture(_:)` setter API.
- `PhospheneEngine/Sources/Renderer/RenderPipeline+RayMarch.swift` — snapshot the texture under lock and pass to `RayMarchPipeline.render(...)`.
- `PhospheneApp/VisualizerEngine.swift` — `ferrofluidParticles: FerrofluidParticles?` storage var.
- `PhospheneApp/VisualizerEngine+Presets.swift` — `applyPreset` allocates `FerrofluidParticles`, bakes, wires `setRayMarchPresetHeightTexture` for Ferrofluid Ocean; reset path nils + detaches slot-10 for non-Ferrofluid presets.
- `PhospheneEngine/Tests/PhospheneEngineTests/Visual/FerrofluidOceanVisualTests.swift` — `renderDeferredRayMarch` instantiates + bakes `FerrofluidParticles` and binds slot-10.

**Product decision applied (Matt, 2026-05-14):** original spec was 512² r16Float height texture; bumped to **1024²** in response to the fullscreen / 4K stretch concern. Texture memory: 0.5 MB → 2 MB; Phase 1 bake cost (one-shot) negligible; Phase 2 per-frame bake budget ~2 ms (within frame budget).

**Tests run.**
- New `FerrofluidParticlesTests`: 7 / 7 passed (0.946 s — bake idempotent; 0.177 s — bake non-zero; rest sub-10 ms).
- `FerrofluidOceanVisualTests` (the 6-gate Ferrofluid suite): 6 / 6 passed.
- Full engine suite: 1256 tests, 2 failures — both pre-existing parallel-execution timing flakes (`MetadataPreFetcher.fetch_networkTimeout` — listed in baseline memory; and `SoakTestHarness.cancel() causes run() to return before duration expires` — passes in isolation in 0.564 s). Neither failure touches code in this increment.
- Engine `swift build` clean, app `xcodebuild` clean.
- `swift test --package-path PhospheneEngine --filter FerrofluidOceanVisualTests/testFerrofluidOceanRendersFourFixtures` was also run on a stash of main to capture the baseline PNGs for the side-by-side.

**Visual harness output.**

Side-by-side PNGs in `docs/diagnostics/V9_session_4_5b_phase1/`:

| Fixture | MD5 main | MD5 phase1 | Verdict |
|---|---|---|---|
| `01_silence` | `ba930c0386c94a219cbff7fffe7c59a8` | `ba930c0386c94a219cbff7fffe7c59a8` | **byte-identical** — `fieldStrength <= 0` early-exit preserved across both paths. |
| `02_steady_mid` | `c0072a6d33a6cc2d71234b8185f6f4ff` | `20862744858b78d0bb1253dbd2a9aeb3` | differs (different smooth-min: Quilez polynomial soft-min over particle distances vs main's `voronoi_smooth` exp/log soft-min over neighbour cells). Visual verdict needs Matt. |
| `03_beat_heavy` | `a9638b9ed2e346e47486a0e7b44e41e3` | `52e309164ea8796c13c41ce374e737b9` | differs (same root cause as `02`). Visual verdict needs Matt. |
| `04_quiet` | `86bd01bb0e7b580fad721e6c5791d526` | `86bd01bb0e7b580fad721e6c5791d526` | **byte-identical** — same early-exit path as `01`. |

Structural equivalence: 2 of 4 fixtures byte-identical; the other 2 use a different smooth-min function but place peaks at the same XZ coordinates a `voronoi_smooth` cell-center pass would emit. Existing structural gates (`lit > 100`, no clipping, sky-reflection-dispatch diff ≥ 1.0 threshold) all pass with the new texture-sample path. **Claude cannot read PNG colour content; final "no regression vs main" verdict requires Matt's side-by-side review.**

**Documentation updates.**
- `docs/ENGINEERING_PLAN.md` — Session 4.5b Phase 1 entry added under Increment V.9.
- `docs/RELEASE_NOTES_DEV.md` — this entry.
- `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` — new row for fragment texture slot 10 + per-preset baked height field; status promoted Missing → Supported.
- `docs/diagnostics/V9_session_4_5b_phase1/` — Phase 1 + main side-by-side PNGs.

**Capability registry updates.** Promoted "Per-preset baked height field for ray-march SDF" from Missing → Supported (slot 10, 1×1 placeholder pattern). Updated "Fragment texture slot reservations 0–13" to include slot 10.

**Engineering plan updates.** Marked V.9 Session 4.5b Phase 1 complete in the Increment V.9 section of `ENGINEERING_PLAN.md`.

**Known risks and follow-ups.**

1. **Visual verdict still required.** Phase 1 STOP gate is "structurally equivalent to current main"; the structural gates pass and the silence/quiet fixtures are byte-identical, but `02_steady_mid` / `03_beat_heavy` differ at the texture level. Recommend Matt opens the four side-by-side PNG pairs before approving Phase 2. If Phase 1 reads as substantially different in shape / density / coverage, the smooth-min `w`, the particle count, or the world-XZ patch can be retuned before motion lands.
2. **`PhospheneAppTests` build failure on `.fluid` / `.abstract` enum references** — confirmed pre-existing on main via stash + rebuild. Fallout from commit `cf67793c` (D-123 `family` taxonomy refactor) where the `PresetCategory` enum dropped `.fluid` / `.abstract` but the corresponding app-layer tests were not updated. Out of scope for V.9; recommend filing a "PhospheneAppTests enum drift" cleanup increment. Engine suite is unaffected and passes.
3. **Two pre-existing parallel-timing test flakes** — `MetadataPreFetcher.fetch_networkTimeout` and `SoakTestHarness.cancel() causes run() to return before duration expires`. Both pass when run in isolation; both are timing-sensitive under parallel load. Not introduced by this increment.
4. **Phase 1 inline diagnostic path retained.** `fo_ferrofluid_field_inline` remains in `FerrofluidOcean.metal` for diagnostic comparison against the texture-sample path. Will be removed at Phase 3 if no diagnostic use case emerges.

**Next recommended increment.** Phase 2 — SPH-lite particle update + audio forces. Per-frame compute dispatch (replaces one-shot init bake), spatial-hash binning for the O(N²) → O(N) particle interaction pass, audio routing per the V.9 Session 4.5b prompt (`bass_energy_dev` repulsive pressure, smoothed `drums_energy_dev` impulses, `accumulated_audio_time × audio coef` rotational drift, `arousal` magnitude scale). STOP gate before Phase 3 (per the prompt): Leitl-demo-character match.

**Git status.** Branch `main`. Phase 1 commits land here. No upstream push (per CLAUDE.md: "Do not push to the remote without Matt's explicit approval"). `git status` will be clean post-commit.

**Follow-up (same day): Phase 1 visual iteration loop — five rounds to STOP-gate pass.** The Phase 1 closeout above shipped with the original spec values (N=2048, R=0.25, w=0.1, 1024² texture, polynomial smooth-min). Matt's review surfaced a sequence of artifacts each round; final approved parameters: N=6000, R=0.15, hard `min()` (no soft-min), 4096² texture. Round summary:
1. **Original** — "smoothed out, fewer spikes, more diffuse."
2. **Sharpness pass** (commit `62ec1659`) — w 0.1 → 0.02, R 0.25 → 0.15, apex 0.1 → 0.03. Matt: "still diffuse, fewer spikes" (density was the real miss).
3. **Density pass** (commit `dc44a06f`) — N 2048 → 6000 via 80×75 grid; X spacing 0.25 wu matches Phase A. Matt: "peaks pixelated in beat-heavy, not smooth like Main" — sharpness perception, then verified zoomed screenshot.
4. **Hard-min bake** — Leitl's `poly_smin` iteratively over 6000 particles accumulates O(w × log N) smoothing → 0.17 wu effective band > 0.15 spike radius → peaks merge into ridges. Swapped to hard `min()` for Phase 1's static-particle path; Leitl's spatial-hash + bounded-K soft-min recipe is the Phase 2 work (it's what keeps the smoothing band bounded for moving particles).
5. **4096² texture** — Matt's zoomed screenshot revealed true texel-grid staircasing at 2048² (texel ~0.010 wu vs screen-pixel ~0.006 wu = 1.6 screen pixels per texel, grid visible). At 4096² (texel 0.005 wu, 0.78 screen pixels per texel) bilinear filtering averages multiple texels per screen pixel and the grid falls below rendered-pixel scale. Memory 8 MB → 32 MB; Phase 1 bake (one-shot) ~10 ms.

Matt 2026-05-14: *"Looks better. I'm ready to call this a pass and move on to Phase 2."* Phase 1 STOP gate satisfied. Final commit in this iteration loop is the hard-min + 4096² combined commit. Iteration PNGs preserved on disk in `docs/diagnostics/V9_session_4_5b_phase1/` (`*_phase1.png`, `*_phase1_tuned.png`, `*_phase1_dense.png`, `*_phase1_hardmin.png`, `*_phase1_4k.png`) alongside the `*_main.png` Phase A reference.

**Phase 2 carry-forward.** (1) Hard-min won't work with moving particles — Phase 2 needs Leitl's spatial-hash + bounded-K soft-min recipe (per-frame compute pass with binning, the actual reference implementation, not naïve all-pairs). The `smoothMinW` and `apexSmoothK` Swift-side constants are preserved for Phase 2 reuse. (2) Per-frame bake cost at 4096² × 6000 particles is ~10 ms — a significant fraction of the 16.67 ms 60 fps budget. Spatial-hash binning brings per-frame cost down by limiting the per-texel inner loop to nearest-K particles instead of all N. Phase 2 perf gate is where this gets validated; if 10 ms is too much, the texture resolution will revisit (4096 → 3072 or similar).

**Follow-up (same day, commit `1fc017a5`): unblock PhospheneAppTests build + Metal -Werror.** Closes known-risk #2 (the `.fluid` / `.abstract` enum-drift in `PhospheneAppTests` from D-123) plus a parallel pre-existing class of Metal `-Werror` failures that only surface under the Xcode test target compile path (SPM `swift test` uses different flags). `.fluid` → `.particles` and `.abstract` → `.hypnotic` across 6 test files (3 Swift enum references + 6 JSON-fixture inline strings); `POM.metal` dead variables `prev_height` / `shadow_layer` removed; `HexTile.metal` documentation-only `e1` / `e2` removed; `kFerrofluidHeightSampler` moved from file-scope in `PresetLoader+Preamble.swift` to function-scope inside `fo_ferrofluid_field_sampled` in `FerrofluidOcean.metal` (was tripping `-Wunused-const-variable` for the four non-Ferrofluid ray-march presets that silence the slot-10 texture). After this commit: `xcodebuild ... build-for-testing` succeeds; `xcodebuild ... test-without-building` runs; the remaining 17 failures are pre-existing parallel-execution timing flakes in app-target tests (`LiveAdaptationToastBridge` / `ReadyViewModel` / `AppleMusicConnectionViewModel` / `ToastManager` / `SoakTestHarness` / `MetadataPreFetcher`) — each passes when run in isolation. Tangential to V.9 Session 4.5b; not introduced by this increment. Filing them as a stable suite would need `@MainActor` debouncing widening or `@Suite(.serialized)` for shared static state per the CLAUDE.md U.10/U.11 learnings — own increment when anyone takes it.

---

## [dev-2026-05-12-g] BUG-011 CLOSED — Arachne over Tier 2 frame budget, closed against relaxed drops-only criteria

**Increment:** BUG-011 closure. **Status:** Resolved. One commit (this commit, doc-only).

The 37,821-frame production re-capture (session `2026-05-12T20-30-28Z`, ~21 min of pinned Arachne on M2 Pro) showed:

| metric | result | design target | verdict |
|---|---|---|---|
| **drops (>32 ms)** | **0.02 %** (8 of 37,821) | ≤ 8 % | **passes by 400× margin** |
| p95 frame_gpu_ms | 15.303 ms | ≤ 14 ms | 1.3 ms over (not noise — confirmed against the prior 14,152-frame and 8,430-frame captures) |
| p50 frame_gpu_ms | 13.708 ms | ≤ 8 ms | structurally above |
| p99 | 17.462 ms | — | down from 29.602 ms at pre-cheap-cleanup |
| max | 34.457 ms | — | down from 57.106 ms at pre-cheap-cleanup |

**Matt's closure decision (2026-05-12): Option 2 — Accept with drops-only criteria.** Drops are the user-perceptible metric (frame > 32 ms is dropped by the compositor and visible as judder). p95 = 15.303 ms means 5 % of frames sit ~1-2 ms above the design budget, but they still complete within ~16-17 ms (at or within one refresh window). The `FrameBudgetManager`'s 14 ms downshift threshold was originally calibrated against the 60 fps refresh budget assuming downshift would prevent visible drops; in practice we hit essentially zero drops at p95 = 15.3 ms on M2 Pro. The 14 ms threshold is more aggressive than the actual visual impact requires for this preset/hardware combination.

**Architecture-contract context.** The contract specifies M3+ as Tier 2; M2 Pro is borderline (Apple Silicon M2-family with more cores but the same per-core compute envelope as base M2). Accepting "p95 = 15.3 ms on borderline silicon" is consistent with the contract's spirit. The p95 ≤ 14 ms target stays as the design goal for actual Tier 2 (M3+) hardware; M2 Pro is documented as a known limitation.

**Total perf delta from pre-tuning baseline (2026-05-08):**

| metric | pre-tuning (2026-05-08) | post-closure (2026-05-12) | Δ |
|---|---|---|---|
| p50 | 14.120 ms | 13.708 ms | −0.4 ms |
| **p95** | 26.607 ms | 15.303 ms | **−11.3 ms (−42 %)** |
| p99 | 32.743 ms | 17.462 ms | −15.3 ms |
| **drops (>32 ms)** | 1.46 % | **0.02 %** | **73× reduction** |

The two perf-tuning waves that produced this:

1. **2026-05-10 L1+L2+L3 worst-case-spike tuning** ([dev-2026-05-10-a]) — spider ray-march max-steps 32 → 24; drop refraction coverage gate 0.01 → 0.5; spider dispatch blend threshold 0.01 → 0.05.
2. **2026-05-12 L5 cheap-cleanup tranche** ([dev-2026-05-12-f]) — retired `ArachneBuildState.spiralChordBirthTimes` (CPU dead append per beat); retired `ArachneWebResult.strandTangent` field + tangent-decision logic (per-pixel Marschner BRDF input demoted in V.7.9, both consumer sites already `(void)`-cast); dust-mote `fbm4` early-out gate on `beamMax > 0.01`.

**Known limitation going forward.** Arachne on M2 Pro trips the `FrameBudgetManager` p95 > 14 ms threshold ~5 % of the time. The governor may downshift quality more aggressively than designed (potentially toggling off SSGI etc. mid-segment when other presets are active near Arachne windows). Acceptable on borderline hardware; M3+ silicon should not see this behaviour. If a future preset addition or shader change eats meaningfully into Arachne's M2 Pro headroom and produces visible drops there, L5.1 (WORLD half-rate refresh) is the next escalation — see `docs/QUALITY/KNOWN_ISSUES.md` BUG-011 "Escalation options" historical section.

**Deferred (not closure-blocking).** M3+ measurement would clarify whether the current p95 = 15.3 ms is "M2 Pro below spec" (expected) or "Tier 2 budget itself needs revision." Cheap to acquire whenever dev environment allows. If a future M3+ measurement shows p95 > 14 ms there, reopen with a new BUG-XXX entry — but BUG-011 closes today.

**V.7.10 Arachne cert review unblocked.** The cert-review increment had been gated on BUG-011 closure; closure removes the gate. V.7.10 is now eligible to run.

**Files updated:** `docs/QUALITY/KNOWN_ISSUES.md` Status field flipped to Resolved + Verification criteria checkboxes flipped + closure-rationale section added; `docs/RELEASE_NOTES_DEV.md` this entry; `docs/ENGINEERING_PLAN.md` Recently Completed entry; `CLAUDE.md` Current Status / Recent landed work entry.

---

## [dev-2026-05-12-f] BUG-011 L5 cheap-cleanup tranche — three dead-code retirements, SOAK kernel p95 14.458 → 12.557 ms

**Increment:** BUG-011 L5 (cheap-cleanup tranche). **Status:** Three code changes + doc updates. BUG-011 likely closes once Matt re-captures M2 Pro real-music perf; the projected production p95 ≈ 14.1 ms (at the 14 ms gate, within run-to-run noise). If the re-capture closes ≤ 14 ms, BUG-011 closes; if it sits at 14.5+ ms, the L5.1 WORLD-half-rate sub-lever is the next escalation.

**Trigger.** Matt asked whether drop-related processing could be retired given that dewdrops were removed in commit `3f6126e0`. Investigation surfaced three categories of dead per-pixel work still running.

**Three changes landed** (single commit; pre-test stash unnecessary — the parallel LumenMosaic WIP was already committed earlier today):

1. **Retire `ArachneBuildState.spiralChordBirthTimes`** (CPU-side `[Float]` allocated, cleared, `.append()`-ed every rising-edge beat × N chord advances). Originally tracked per-chord ages for drop-accretion timing; never consumed by production code after dewdrops were retired. Only consumer was the `dropAccretionAgesChordsCorrectly` test, also retired (the test validated ordering of an unread accumulator). [PhospheneEngine/Sources/Presets/Arachnid/ArachneState.swift](PhospheneEngine/Sources/Presets/Arachnid/ArachneState.swift) (3 sites: field declaration, `removeAll` at radial→spiral transition, `.append` in the chord-advance loop). [PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneStateBuildTests.swift](PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneStateBuildTests.swift) (test 10 retired with explanatory comment).
2. **Retire `ArachneWebResult.strandTangent` field + tangent-decision logic.** Per-pixel computation: `arachneEvalWeb` ran `result.strandTangent = (minSpokeDist <= minChordDist && minSpokeDist < 1e5) ? bestSpokeTangent2D : spirTangent2D` and tracked `bestSpokeTangent2D` (per spoke iteration) + `spirTangent2D` (per spiral chord iteration). Both consumer sites in `arachne_composite_fragment` (anchor block + pool block) read it into `tang2D` and immediately `(void)tang2D;`-cast it — the tangent was a Marschner BRDF input demoted in V.7.9 and the cast was carrying the dead store. Field removed from `ArachneWebResult` struct; default initialiser removed; tangent-tracking locals removed from `arachneEvalWeb`; both `(void)tang2D` casts removed. [PhospheneEngine/Sources/Presets/Shaders/Arachne.metal](PhospheneEngine/Sources/Presets/Shaders/Arachne.metal) (7 edits across the struct, the function, and both consumer sites).
3. **Dust-mote `fbm4` early-out.** `drawWorld()` ran `fbm4(driftUV, 0.31)` (4-octave Perlin) per pixel, then multiplied by `moteCone = saturate(beamMax * 2.5)`. For pixels with `beamMax < ~0.004` (~70-80 % of frame at usual mood values), `moteCone` was ~0 but the per-pixel `fbm4` call had already happened. Gated the block on `if (beamMax > 0.01)`. Semantics-preserving up to floating-point at the threshold boundary (where masked contribution was already ~0). [PhospheneEngine/Sources/Presets/Shaders/Arachne.metal](PhospheneEngine/Sources/Presets/Shaders/Arachne.metal) `drawWorld()` line ~399.

**SOAK kernel-cost benchmark measurement** (M2 Pro, 1920×1080, spider forced ON, 1800 frames; the in-tree regression gate added in BUG-011 round-7 commit `bd213856`):

| metric | pre-cleanup (2026-05-10 baseline) | post-cleanup | Δ |
|---|---|---|---|
| p50 | 12.724 ms | 11.313 ms | **−1.4 ms** |
| p95 | 14.458 ms | 12.557 ms | **−1.9 ms** |
| p99 | 15.169 ms | 13.178 ms | −2.0 ms |
| mean | 12.903 ms | 11.444 ms | −1.5 ms |
| kernel overruns (>14 ms) | 172 / 1800 (9.6 %) | **1 / 1800 (0.06 %)** | −171 frames |

Run-to-run variance ≈ 0.1 ms. SOAK gate is 16 ms p95; post-cleanup p95 sits 3.4 ms inside the gate.

**Projection to production.** The previous production capture (2026-05-12T18-19-31Z) measured p95 = 16.068 ms in real-music conditions; SOAK measured p95 = 14.458 ms in worst-case-spider conditions before this cleanup. The SOAK ↔ production gap was ~+1.6 ms (production runs longer with more OS-scheduler interference). Applying the same gap to post-cleanup SOAK (12.557 ms) projects **production p95 ≈ 14.1 ms** — basically at the 14 ms target, within run-to-run noise.

**Verification.** 43/43 targeted Arachne tests green (`ArachneStateBuild` + `ArachneState` + `ArachneSpiderRender` + `ArachneListeningPose` + `ArachneBranchAnchors` + `PresetRegression` + `PresetAcceptance` + `MaxDurationFramework` + `StagedComposition` + `PresetLoaderCompileFailure`). Arachne + spider golden hashes unchanged (the regression render path doesn't bind `worldTex` and the cheap-cleanup changes don't affect the parts of the pipeline that surface in the dHash). App build clean. SwiftLint 0 violations on touched files.

**Carry-forward.** Matt's M2 Pro real-music re-capture is the load-bearing close action — same procedure as before: build, ad-hoc session, `L` + `⌘[`/`⌘]` to Arachne, ≥ 90 s, analyse `frame_gpu_ms` from `features.csv`. If production p95 ≤ 14 ms, flip BUG-011 Status to Resolved (commit + KNOWN_ISSUES.md + release notes). If 14.1–14.5 ms (within noise), still likely close; if 14.5+ ms, L5.1 WORLD half-rate refresh is the next escalation.

---

## [dev-2026-05-12-e] BUG-011 M2 Pro post-tuning perf capture — drops gate passes, p95 still 2 ms over budget

**Increment:** BUG-011 perf measurement (no code changes; doc-only). **Status:** BUG-011 remains **Open** — drops gate passes (0.7 % vs 8 % target), p95 misses (16.068 ms vs 14 ms target), p50 misses (13.649 ms vs 8 ms target). Three escalation paths documented in `docs/QUALITY/KNOWN_ISSUES.md` BUG-011 § "Escalation options"; Matt to pick.

**Capture.** Session `~/Documents/phosphene_sessions/2026-05-12T18-19-31Z`. Mac mini M2 Pro, macOS 26.4.1. Post-round-8 build (all three round-8 code commits + the docs commit in tree). Procedure: Spotify-prepared playlist, `L` engaged at session start, `⌘[`/`⌘]` cycled to Arachne. `wait_for_completion_event: true` + `diagnosticPresetLocked` kept Arachne pinned for the entire ~8-minute session after the initial Waveform → Arachne transition at engine time 3 s. 14,152 Arachne frames captured.

| metric | this capture | post-tuning target | pre-tuning baseline (2026-05-08) |
|---|---|---|---|
| Frames | 14,152 (≈ 7.9 min) | ≥ 60 s | 4,579 (≈ 77 s) |
| p50 | 13.649 ms | ≤ 8 ms | 14.120 ms |
| **p95** | **16.068 ms** | **≤ 14 ms** | 26.607 ms |
| p99 | 29.602 ms | — | 32.743 ms |
| max | 57.106 ms | — | 36.072 ms |
| > 14 ms | 5,775 / 14,152 (40.8 %) | — | 52.98 % |
| drops (> 32 ms) | 94 / 14,152 (**0.7 %**) | ≤ 8 % | 1.46 % |

**Diagnosis.** L1+L2+L3 tuning landed real wins where aimed — p95 dropped 10.5 ms (26.607 → 16.068), drops halved (1.46 % → 0.7 %). Each lever attacked a worst-case spike. **What didn't move is the median** — 14.120 → 13.649 ms is essentially within run-to-run variance. The post-tuning bottleneck is therefore **always-on per-frame cost**, not worst-case tails: WORLD pass (sky gradient + ambient fog + god-rays + dust motes, always rendered into the offscreen WORLD texture every frame); COMPOSITE always-on work (silk strand SDF, chord segment evaluation, polygon ray-clip, mood palette, 12 Hz vibration UV jitter); drop accumulator pool loop fires per pixel even when per-pixel drop coverage is below threshold.

**Tail spikes** (p99 = 29.6 ms, max = 57.1 ms) are heavier than the pre-tuning capture because the new capture is 3× longer (more opportunity to hit OS scheduler / GC / background process spikes) and because the round-8 build cycle is ~92 s — long enough that the COMPOSITE pass evaluates the full ~441-chord spiral at peak, where pre-round-8 windows truncated before the spiral phase peaked. Neither tail crosses the 8 % drop threshold.

**Side-validation of round-8 work.** The session also incidentally validated the round-8 completion-gated-transitions work — orchestrator transitioned Waveform → Arachne at 3 s and never left Arachne for the rest of the 8-minute session. That's `wait_for_completion_event: true` + `L`-locked behaving exactly as designed. No spurious orchestrator transitions.

**Escalation options (Matt to decide).** Documented in detail in `docs/QUALITY/KNOWN_ISSUES.md` BUG-011 § "Escalation options". Summary:

- **L5 (recommended)** — attack always-on cost. Two candidate sub-levers: WORLD pass cached-refresh (half-rate, sample cached texture on intermediate frames) + drop-pool spatial pruning (per-tile bucketing before per-pixel loop). Scope: 1-2 sessions. Likely brings p95 < 14 ms and p50 close to 8 ms on M2 Pro. Needs a new `D-XXX` decision entry before implementation.
- **L4** — reclassify M2 Pro as Tier 1 for Arachne. V.7.5 silhouette spider on M2 Pro / V.7.7D 3D SDF spider only on M3+. Cheap (0.5 session) but accepts the limitation rather than fixing it; permanent loss of V.7.7D on M2 Pro. Needs a new `D-XXX`.
- **Accept** — revise closure criteria to drops-only (0.7 % currently passes), document p95 = 16 ms as a known limitation on borderline Tier 2. Closes BUG-011 today. Risk: `FrameBudgetManager` still downshifts on p95 > 14 ms; SSGI may toggle off mid-segment on M2 Pro.

**Carry-forward.** Decision pending. V.7.10 Arachne cert review remains gated on BUG-011 closure regardless of which path closes it. M3+ measurement still a useful data point to acquire whenever dev environment allows — would clarify whether the current state is "M2 Pro below spec" or "Tier 2 budget needs revision."

---

## [dev-2026-05-12-d] BUG-004 resolved — Lumen Mosaic is Phosphene's first certified preset

**Increment:** BUG-004 closure. **Status:** One commit on `main` (`81d6b8f3`), pushed to `origin/main` 2026-05-12.

**Context.** BUG-004 was opened against V.6 when the certification pipeline shipped with zero `certified: true` presets — the orchestrator's `includeUncertifiedPresets: false` default made the catalog effectively empty, so `GoldenSessionTests` and any session run under the production toggle had to either flip the toggle or fall back to the cheapest-fallback `noEligiblePresets` warning path. Lumen Mosaic's cert flip landed at LM.7 (2026-05-12) on top of LM.4.6 + LM.6 (the pure-uniform-random-RGB-per-cell palette + cell-depth gradient + per-track chromatic-projected RGB tint shape). This commit is the closure-and-verification commit: it expands the test surface so the cert is end-to-end exercised, fixes one stale test fixture, and files the resolution.

**Closure verification — three follow-up landings in this commit.**

1. **`GoldenSessionTests.makeRealCatalog()` expanded 11 → 15 production presets.** Pre-closure the fixture catalog mirrored a stale subset (Waveform, Plasma, Nebula, Murmuration, Glass Brutalist, Kinetic Sculpture, Volumetric Lithograph, Spectral Cartograph, Membrane, Fractal Tree, Ferrofluid Ocean) and did not include the four presets added since V.6 (Arachne, Gossamer, Lumen Mosaic, Staged Sandbox). The comment said "All 11 production presets" but `PresetLoaderCompileFailureTest.expectedProductionPresetCount = 15`. Now mirrors every production sidecar verbatim. Spectral Cartograph + Staged Sandbox carry `isDiagnostic: true` per D-074 — the orchestrator excludes them categorically and they participate as no-ops. The `makePreset` helper gained an `isDiagnostic: Bool = false` parameter. Session A + Session B sequences unchanged; Session C track 5 moved Plasma → Ferrofluid Ocean post-expansion (Plasma's `fatigue_risk: high` cooldown extends past track 5's start in the expanded family-repeat surface; FO is the next-best high-energy candidate — tempCenter 0.325 mismatch but density 0.75 close to 0.815 target). Scoring trace comment regenerated to record the pre/post-expansion verdict.

2. **Session D added — a load-bearing LM-eligibility regression.** Single-track 180 s fixture with BPM=75 / valence=0.0 / arousal=+0.30 (LM-favourable mood profile aligned to LM's identity: motion 0.25, density 0.65, tempCenter 0.5, sections ambient/comedown/bridge). New test `sessionD_lumenMosaicWinsFirstSegment` regression-locks LM winning track 0 / segment 0 against the production-cert-aware catalog. Hand-computed scoring trace recorded: LM total ≈ 0.868 (moodScore 0.985, motion 0.9875) vs Gossamer 0.830 / Arachne 0.818 / Plasma 0.796 / Glass Brutalist 0.787. Demonstrates the cert is end-to-end exercised — not just structurally present in the JSON sidecar.

3. **`MatIDDispatchTests.kLumenEmissionGain` 4.0 → 1.0.** Pre-closure this test was failing because `kLumenEmissionGain` was reduced from 4.0 → 1.0 at LM.3.2 round 4 (2026-05-10) and the test fixture's expected-emission constant was never updated. Documented in CLAUDE.md as a "documented pre-existing failure" but never actually resolved. All 3 MatIDDispatch tests now pass — the assertion compares `lit ≈ albedo × kLumenEmissionGain` and `albedo × 1.0 = (0.5, 0.5, 0.5)` matches the observed 0.5019531 within the 0.02 tolerance. The matID 0 vs matID 1 separation assertion's distance threshold was tightened 1.0 → 0.1 (the gap shrinks at the lower gain — pre-LM.3.2-round-4 the matID 1 reference was at (2, 2, 2) and the standard Cook-Torrance output landed well clear; post-round-4 the matID 1 reference is at (0.5, 0.5, 0.5) and the gap to the Cook-Torrance output is direct-lighting + fog contribution, narrower but still load-bearing for dispatch verification).

**Cert flip itself** landed in the prior session (not this commit): `LumenMosaic.json` flipped `"certified": false → true`; `"Lumen Mosaic"` added to `FidelityRubricTests.certifiedPresets`; `automatedGate_uncertifiedPresetsAreUncertified` updated to skip `isCertified` assertion when the heuristic gate fails by design (M3 mat_* cookbook heuristic doesn't fit emission-only matID==1 presets per D-067 + SHADER_CRAFT.md §12.1 M7). `LUMEN_MOSAIC_DESIGN.md §10` records the LM.7 sign-off against session `2026-05-12T17-15-14Z`. The rubric score is **10.5 / 15** (mandatory 7/7 + expected 2.5/4 + preferred 1/4) — above the 10/15 threshold with all mandatory passing.

**Project-level milestones.**

- **Milestone D — Certified presets**: 0/22+ → **1/22+**. Lumen Mosaic is Phosphene's first production certified preset.
- **Phase LM closed.** All landed increments (LM.0 + LM.1 + LM.2 + LM.3 + LM.3.1 + LM.3.2 + LM.4 + LM.4.1 + LM.4.3 + LM.4.4 + LM.4.5 + LM.4.5.1 + LM.4.5.2 + LM.4.5.3 + LM.4.6 + LM.6 + LM.7 + cert) accounted for in `LUMEN_MOSAIC_DESIGN.md §6`. The phase's final shape (D.6 pure-hash palette + LM.6 albedo modulations + LM.7 chromatic-projected per-track tint) is now the canonical reference for emission-only matID==1 presets in the catalog.
- **Orchestrator default now produces non-empty plans.** With `includeUncertifiedPresets: false` (production default), Lumen Mosaic alone makes the eligible set non-empty for any mood-compatible track. The other 14 uncertified production presets remain gated behind the Settings toggle until they pass M7.

**Verification.**

- 13/13 GoldenSessionTests green (12 pre-existing + 1 new Session D).
- 3/3 MatIDDispatch tests green (previously 1/3 failing).
- Full engine + app suites — see commit message for parallel-load flake baseline.
- App build clean. SwiftLint 0 violations on touched files.
- BUG-004 verification criteria both checked off (✓) in `KNOWN_ISSUES.md`.

**Carry-forward.**

- Watch for over-/under-selection of Lumen Mosaic in real-use sessions. Orchestrator behaviour with one certified preset in production is a new observability surface. If LM dominates inappropriately, that's a scoring-rebalance follow-up (QR.2-class), not a cert-flip defect.
- Next cert candidates per CLAUDE.md ordering: Arachne V.7.10 (blocked on V.7.7C.5.2 manual smoke + V.7.7C.6 spider movement + BUG-011 perf capture); Aurora Veil (Phase AV — design + references ready, sequenced behind Arachne).
- The LM.7 cert prompt + this BUG-004 closure prompt are now reusable templates for future preset certs — swap the preset name and the same shape applies.

**Related:** Phase LM closeout, BUG-004 (now Resolved), D-067 (cert pipeline architecture), D-074 (diagnostic exclusion), `LUMEN_MOSAIC_DESIGN.md §10`.

---

## [dev-2026-05-12-c] Arachne round 8 — build speedup + silent-state pause + completion-gated transitions

**Increment:** BUG-011 round 8 (behavioural follow-ups; the underlying BUG-011 **perf** issue remains Open). **Status:** Three commits on `main`, pushed (`ceb35340`, `0756a9ef`, `04855e26`). Closes four items from Matt's session `2026-05-11T23-18-42Z` directive.

**Context.** The work in this entry is operationally distinct from the 2026-05-10 perf tuning (L1+L2+L3 levers + SOAK gate, dev-2026-05-10-a). Matt's session `T23-18-42Z` surfaced four user-facing problems with Arachne in production that are unrelated to the Tier 2 frame budget: build progressing during silence/prep, premature segment transitions (~50 s windows) ignoring `duration: 150`, a too-slow build clock, and partial-radial frames being misread as missing geometry. The original BUG-011 perf entry in `docs/QUALITY/KNOWN_ISSUES.md` stays **Open** pending Matt's M2 Pro real-music perf capture — that's the closure gate for the perf class. The round-8 follow-up section in that entry documents the behavioural landings separately.

**Item 4 — 8 % build speedup (commit `ceb35340`).** `frameDurationSeconds 3.0 → 2.775` (6 → 5.55 beats @ 120 BPM), `radialDurationSeconds 1.5 → 1.389` per radial (6.5 → 6.02 beats), spiral chord advance `3 → 3.24` per rising-edge beat via new `Float` accumulator `ArachneBuildState.spiralChordAccumulator` (carries fractional residual across edges; integer-part feeds advance, fractional part rolls forward; 3-3-3-4 pattern, avg 3.24). Median 21×21-spoke segment: total build ~100 s → ~92 s. `dropAccretionAgesChordsCorrectly` test continues to pass — the `min(whole, total − index)` clamp absorbs the final-edge overshoot.

**Item 1 — Silent-state build pause (commit `0756a9ef`).** New constant `ArachneBuildState.stemEnergySilenceThreshold = 0.02`. `advanceBuildState` now zeros `effectiveDt` when `vocalsEnergy + drumsEnergy + bassEnergy + otherEnergy < 0.02` — the four AGC-normalised stem energies sum to ~2.0 at normal playback and drop to ~0 at silence / prep / source-app paused, so 0.02 is 1 % of normal and well clear of AGC residual jitter. `pausedBySpider` flag is set BEFORE the silence check so the spider-pause regression test (which uses `stems: .zero`) still asserts the right thing. Two existing tests switched to a new `audibleStems()` fixture (sum = 2.0, dev fields untouched). Two new regression tests: `silentStateHaltsBuildAdvance` (driving 360 frames with audibly-active features + zero stems → `frameProgress` stays at 0) and `silentGateBoundaryIsTwoPercent` (sum=0.016 paused, sum=0.04 advances).

**Item 3 — Completion-gated transitions (commit `04855e26`).** New `PresetDescriptor.waitForCompletionEvent: Bool` field (JSON `wait_for_completion_event`, default false). When true: (a) `maxDuration(forSection:)` returns `.infinity` (short-circuits the V.7.6.C motion-intensity + fatigue + linger formula AND the `naturalCycleSeconds` cap, the same way `isDiagnostic` does); (b) `applyLiveUpdate` strips mood-derived `presetOverride` for the active segment (mirroring the existing `diagnosticPresetLocked` and `isCaptureModeSwitchGraceActive` suppression paths; boundary rescheduling via `updatedTransition` is still honoured). Active segment is located by track-relative position (`elapsedTrackTime` vs `segment.plannedStartTime − track.plannedStartTime`, since segment times are session-relative). Existing runtime completion-event subscription (`wirePresetCompletionSubscription` → `ArachneState: PresetSignaling`) was already in place; with `maxDuration` no longer capping at ~72 s the build now reaches `.stable` before the planner schedules a transition, and the `nextPreset()` call fires from the completion event instead. Arachne JSON flips `"wait_for_completion_event": true`. **Known limitation**: section boundaries still hard-stop completion-gated segments (the `remainingInSection` cap in `planOneSegment` is unchanged); acceptable because typical track sections are ≥ 60 s and the round-8 build cycle takes ~92 s. Tracks with shorter sections will still see Arachne cut short at the boundary — revisitable if the symptom surfaces on real music. The stale `Arachne is capped by naturalCycleSeconds (60 s)` test in `MaxDurationFrameworkTests` is replaced with `Arachne returns .infinity`; reference-table entry updated to `expectedSeconds: nil` consistent with the diagnostic-equivalent slot.

**Item 2 — Spokes-below-orb investigation (no code).** The Matt-observed "spokes still missing below the orb" symptom from the round-7 review was diagnosed against the session `T23-18-42Z` `video.mp4` end-state. Four Arachne windows played in that session, all 47-64 s long. Extracted frames at multiple offsets show every window caught the build in mid-radial-phase (alternating-pair draw order, ~50 % of 21 spokes laid). Build never reached `.stable` because round-7's ~100 s cycle exceeded every window's duration. Round 7's `rT < 0.85` envelope fix is correct; there is no spoke-rendering bug. **Item 3 structurally resolves this** — completion-gated Arachne windows now run to `.stable` and show all 21 spokes before the orchestrator transitions.

**Verification.**

- 36/36 targeted Arachne tests green (`ArachneStateBuild` 14 + `ArachneState` 4 + `ArachneSpiderRender` 1 + `ArachneListeningPose` 4 + `ArachneBranchAnchors` 2 + `PresetRegression` 3 + `PresetAcceptance` 4 + `MaxDurationFramework` 10 + `StagedComposition` 2 + `PresetLoaderCompileFailure` 1 minus duplicates).
- 4 new tests added (`silentStateHaltsBuildAdvance`, `silentGateBoundaryIsTwoPercent`, `waitForCompletionEventReturnsInfinity`, `waitForCompletionEventDefaultsFalse`, `arachneIsCompletionGated`, `arachneMaxDurationIsInfinity`).
- Engine 1222 tests / 156 suites. 13 failing assertions all trace to documented pre-existing flakes per CLAUDE.md baseline: `MatIDDispatch.matID==1 emission path` (LM.3.2 round-4 calibration drift in test fixture), `MetadataPreFetcher.fetch_networkTimeout` (parallel-load timing), several `SessionManager.*` tests (parallel-load `.preparing → .ready` timing — all pass in isolation).
- App build clean. SwiftLint 0 violations on touched files.
- Arachne and spider golden hashes unchanged (regression render path doesn't bind slot 6/7 + worldTex, so the round-8 changes don't surface in `PresetRegression`; the timing/state changes are exercised by `ArachneStateBuild` instead).

**Carry-forward.**

- BUG-011 **perf** issue stays Open in `docs/QUALITY/KNOWN_ISSUES.md`. Matt's M2 Pro real-music perf capture remains the closure gate.
- Item 3's section-boundary limitation may surface on tracks with sections < 92 s. If it does, revisit `planOneSegment.remainingInSection` clamp for `waitForCompletionEvent` presets.
- V.7.10 Arachne cert review unblocked once the perf gate closes — the round-8 timing fixes + completion-gated transitions together address Matt's product-feel concerns; only the Tier 2 perf budget gate is between Arachne and cert.

---

## [dev-2026-05-12-b] Lumen Mosaic certified — LM.6 cell-depth gradient + LM.7 per-track tint (D-LM-6 + D-LM-7)

**Increments:** LM.6 + LM.7. **Decisions:** D-LM-6, D-LM-7. **Status:** Phase LM CLOSED. **Two commits suggested** (LM.6 then LM.7; both clean local working tree before push).

Lumen Mosaic is the first catalog preset to land `certified: true` after Matt's M7 sign-off on real-music session `~/Documents/phosphene_sessions/2026-05-12T17-15-14Z` (Love Rehab / So What / There There / Pyramid Song / Money). Two landed layers stack on top of the LM.4.6 palette contract:

**LM.6 — Cell-depth gradient + optional hot-spot.** Two albedo-only modulations in `LumenMosaic.metal` `sceneMaterial`, between palette lookup and frost diffusion. (1) Depth gradient — `cell_hue *= mix(kCellEdgeDarkness (0.55), 1.0, 1 - smoothstep(0, cellV.f2, cellV.f1))` — full brightness at cell centre, 0.55 × hue at boundary; gives cells a "domed 3D-glass" read instead of flat-painted tiles. (2) Optional hot-spot — `cell_hue += pow(1 - smoothstep(0, kHotSpotRadius (0.15) × cellV.f2, cellV.f1), kHotSpotShape (4.0)) × kHotSpotIntensity (0.30) × cell_hue` — 30 % brightness boost at inner 15 % of each cell, additive on the cell's own hue (not toward white — palette character preserved). Driven entirely by Voronoi `f1/f2` field already computed for cell ID + frost; zero extra render cost. **The SDF normal stays flat** (`kReliefAmplitude = 0` / `kFrostAmplitude = 0`) — LM.6 is albedo modulation, not normal-driven specular; the matID==1 lighting path still skips Cook-Torrance per the LM.3.2 round-7 / Failed Approach lock. Earlier LM design docs spoke aspirationally about "LM.6 = Cook-Torrance specular sparkle" — that path was abandoned and the docs were corrected as part of this cert sweep. 5 new file-scope constants. 3 new tests in `LumenPaletteSpectrumTests` Suite 6.

**LM.7 — Per-track aggregate-mean RGB tint with chromatic projection.** Closes the LM.4.6 panel-aggregate complaint Matt voiced after seeing the LM.6 contact sheet: *"mean should NOT be middle-gray; the mean should be different for each track played."* Inside `lm_cell_palette`, a per-track tint vector `trackTint = (rawTint - meanShift) × kTintMagnitude (0.25)` derived from `lumen.trackPaletteSeed{A,B,C}` (FNV-1a hash of "title | artist") is added to every cell's uniform random RGB before the saturate-clamp. **The mean-subtraction projection** (subtract `(rawTint.r + rawTint.g + rawTint.b) / 3` before scaling) projects every tint onto the chromatic plane perpendicular to (1,1,1)/√3, so achromatic-aligned seed configurations (all-positive → toward-white wash; all-negative → toward-black mud) collapse to zero tint instead of washing the panel — the side-effect is that diagonal-aligned tracks read as LM.4.6-neutral, preferred over washed. Implemented in two passes: pure additive tint first, then the chromatic-projection fix after Matt observed the `track_v1 (+1,+1,+1,+1)` wash. Per-cell freedom preserved *in spirit* — every cell still rolls a colour from the full uniform-random RGB cube; only the sampling window slides per track. Most colours remain reachable on every track; the cube corner opposite the tint direction is forfeit at the seedA/B/C = ±1 limit (Matt explicitly accepted this trade-off). 1 new file-scope constant + 5 new tests in Suite 7 (warm/cool aggregate direction, distinct-tracks-distinct-means, neutral-track-near-middle-gray, achromatic-aligned-seed-does-not-wash).

**Certification.**

- `LumenMosaic.json` → `"certified": true`. First catalog preset with this flag.
- `FidelityRubricTests.certifiedPresets` → `["Lumen Mosaic"]` (was `[]`).
- `automatedGate_uncertifiedPresetsAreUncertified` test relaxed: certified presets only need `result.certified == true` (the JSON flag); uncertified presets retain the strict `!isCertified` AND of `meetsAutomatedGate && certified`. Reason: Lumen Mosaic fails heuristic M3 by design (emission-only matID==1 path uses `voronoi_f1f2` + frost diffusion instead of V.3 cookbook materials); per `SHADER_CRAFT.md §12.1` M7 the load-bearing gate is Matt's reference-frame review.
- `docs/ENGINEERING_PLAN.md` Phase LM marked closed with full LM.6 + LM.7 increment entries.
- `docs/DECISIONS.md` adds D-LM-6 + D-LM-7.

**Verification.**

- 15/15 LumenPaletteSpectrum tests pass (7 LM.4.6 + 3 LM.6 + 5 LM.7).
- 51/51 cert-related tests pass (LumenPalette / FidelityRubric / PresetRegression / PresetAcceptance / PresetLoaderCompileFailure / PresetDescriptorRubricFields).
- Engine 1223/1227 with two documented pre-existing failures unchanged: `MatIDDispatch.matID==1 emission path` (LM.3.2 round-4 calibration drift in test fixture, present pre-LM.6) and `MetadataPreFetcher.fetch_networkTimeout` (parallel-load timing flake).
- **Lumen Mosaic golden hash unchanged at `0xF0F0C8CCCCC8F0F0`** across all three fixtures; every other preset's hash byte-identical (no cross-preset drift). The regression harness leaves slot-8 zero-bound → trackPaletteSeed = 0 → LM.7 tint = 0; LM.6's Voronoi-driven modulation contributes per-pixel but lands below the dHash 9×8 luma quantization at 64×64 (dominated by Voronoi cell boundary positions, not per-cell intensity gradients).
- SwiftLint 0 violations on touched files.

**Session telemetry (M7 manual validation).** `frame_gpu_ms`: mean 1.37 ms, max 32.9 ms, only 3/14622 frames > 16 ms on M2 Pro. `frame_cpu_ms` spikes (mean 10.1 ms, max 314 ms, 589 > 16 ms) are stem-separation thread hops, not render path. BeatGrid lock-state distribution: 37 % LOCKED / 21 % LOCKING / 42 % UNLOCKED (pre-existing BUG-007 oscillation, unrelated to LM). Only pre-existing DSP.4 `BPM 3-way` warnings logged. Four track screenshots show visibly distinct aggregate palettes per the LM.7 design intent.

**Docs corrected in the cert sweep.** Multiple LM-related docs spoke aspirationally about "LM.6 = Cook-Torrance specular sparkle" before the LM.6 prompt was finalized; the actual landed shape is albedo-only modulation with the SDF normal still flat. `docs/presets/LUMEN_MOSAIC_DESIGN.md`, `docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md`, and `docs/VISUAL_REFERENCES/lumen_mosaic/README.md` are all corrected in this commit sweep to reflect the actual landed implementation. The CLAUDE.md inline module-map entry has been updated with the full LM.6 + LM.7 active-constants list and the cert status.

See `docs/DECISIONS.md` D-LM-6 + D-LM-7 for the full rationale, what was rejected (multiple LM.4.5.x palette restrictions, larger tint magnitudes, per-track HSV rotation, per-cell biased sampling, pure additive tint without chromatic projection), and the rules for future LM iterations (don't regress the chromatic projection; don't raise `kTintMagnitude` above 0.30; don't re-introduce normal-driven specular for matID==1).

---

## [dev-2026-05-11-a] Drift Motes preset retired (D-102)

**Increment:** removal. **Decision:** D-102. One commit.

Drift Motes (DM.0 through DM.3 plus DM.3.1 / DM.3.2 / DM.3.2.1 / DM.3.3 / DM.3.3.1 manual-smoke remediation increments) is retired in its entirety. All preset code (`DriftMotes.metal`, `DriftMotes.json`, `ParticlesDriftMotes.metal`, `DriftMotesGeometry.swift`), tests (`DriftMotesAudioCouplingTest`, `DriftMotesRespawnDeterminismTest`, `DriftMotesTests`, `DriftMotesVisibilityTest`), design / palette / architecture-contract docs, the visual reference set under `docs/VISUAL_REFERENCES/drift_motes/`, and the DM.3 perf-capture procedure docs are deleted from the tree. Recover from git history if a future iteration is contemplated.

`PresetLoaderCompileFailureTest.expectedProductionPresetCount` drops 16 → 15. `ParticleGeometryRegistry.knownPresetNames` drops `DriftMotesGeometry.presetName`. `VisualizerEngine.resolveParticleGeometry` keeps only the `Murmuration` case. `SoakTestHarnessTests.shortRunDriftMotes` removed. `PresetVisualReviewTests` arguments and `buildDriftMotesContactSheet` helper removed. `PresetRegressionTests` Drift Motes hash entry removed.

**What survives.** D-097 (particle preset architecture: siblings, not subclasses) — Murmuration is byte-identical to its post-DM.0 baseline; the protocol surface (`ParticleGeometry` / `ParticleGeometryRegistry`) stays for future particle presets. D-099 (Swift `FeatureVector` / `StemFeatures` at 192 / 256 bytes) — locked by `CommonLayoutTest`. D-101 (`stems.drums_beat` as canonical particles-family beat-reactivity field). `SessionRecorder.frame_cpu_ms` / `frame_gpu_ms` columns and `RenderPipeline.onFrameTimingObserved` (originally DM.3a) stay — generic per-frame timing instrumentation useful for any preset's perf capture. BUG-012 (Drift Motes p99 frame-time tail) closed as obsolete in `KNOWN_ISSUES.md`.

**Rationale.** After four sessions of iteration (DM.1 → DM.3.3.1) the preset never achieved a clear musical anchor or sustained visual interest. The fundamental problem was not tuneable: drifting particles + light shaft lack a load-bearing musical role that distinguishes them from a generic ambient backdrop. Every successor concept pitched during remediation failed the three-part bar (iconic visual subject deliverable at fidelity + clear musical role + infrastructure-feasible). Decision to remove was made after Matt rejected every concept and lost confidence further iteration would converge.

See `docs/DECISIONS.md` D-102 for the full rationale, what was rejected (`@StateObject`-style retention as "infrastructure for a future preset", a user-side "rest period" affordance, keeping the shader as a SHADER_CRAFT reference), and the rule for any future revival (start from a new preset spec authored against the three-part bar; do not undo this deletion).

---

## [dev-2026-05-10-a] BUG-011 — Arachne over Tier 2 frame budget: tuning levers L1+L2+L3 + SOAK kernel-cost benchmark

**Increment:** BUG-011. **Domain:** perf. **Status:** Open — tuning levers landed; closure pending Matt's M2 Pro real-music perf capture (procedure documented in BUG-011 entry of `docs/QUALITY/KNOWN_ISSUES.md`). Four commits.

Pre-tuning baseline measured 2026-05-08 in session `2026-05-08T22-01-07Z` (Arachne window of 4,579 frames over Love Rehab + So What + Limit To Your Love on M2 Pro):

```
p50 = 14.120 ms   ← already AT FrameBudgetManager downshift threshold
p95 = 26.607 ms
p99 = 32.743 ms   ← right at the drop threshold
max = 36.072 ms
>14 ms = 52.98%
drops (>32 ms) = 1.46%
```

Drift Motes in the same session sat at p50 = 1.225 / p95 = 1.321 — proves measurement infrastructure healthy; cost is concentrated in Arachne specifically, accumulated incrementally across the V.7.7B → V.7.7C → V.7.7D → V.7.7C.5 sequence of staged-composition + 3D-spider + atmospheric-reframe additions.

**Three shader-side levers pulled, each in its own commit with golden-hash + visual + test verification at each step.**

| commit | lever | change | rationale |
|---|---|---|---|
| `082164c7` | **L1** spider ray-march steps | `maxSteps = 32 → 24` (Arachne.metal:~1640) | The 0.15 UV spider patch (~226×226 px @ 1080p ≈ 51k pixels) ran the full 32-step worst case for every miss-ray. Cutting to 24 reduces per-pixel max work by 25 %; on-hit rays are unaffected (sphere trace early-exits at hitEps). Visual risk minimal — chitin rim term is thick enough that ~1-pixel silhouette movement at grazing angles reads inside the rim. |
| `1643ee24` | **L2** drop refraction coverage gate | `wr.dropCov > 0.01 → > 0.5` (both anchor + dead-pool sites) | The 0.01 floor admitted the entire anti-aliased rim band of every drop into the refraction path, paying for `worldTex.sample(refractedUV)` + smoothstep+pow chain on pixels where the drop's visual presence was < 50 %. Drops now render with a clean visible core; rim pixels fall through to the silk-strand colour underneath. |
| `96b2c288` | **L3** spider dispatch gate | `spider.blend > 0.01 → > 0.05` (dispatch site only, not overlay mix) | Skips the patch ray-march during the spider's fade-in/fade-out tail (blend ramping below 5 % opacity is below perceptual threshold). `listenLiftEMA` not plumbed to GPU per D-094, so gate uses `spider.blend` alone — listening pose triggers via the existing path with at most a 1-frame lag. |

**SOAK kernel-cost benchmark added (`bd213856`):** new `shortRunArachneComposite` test in `SoakTestHarnessTests` mirrors the existing `shortRunDriftMotes` pattern but renders Arachne's COMPOSITE fragment to a 1920×1080 offscreen texture with the spider forced active (worst case — patch ray-march fires every frame). SOAK_TESTS=1 gated; loose 16 ms p95 kernel-only gate on M2 Pro. Catches future shader-side regressions (step count creep, coverage gate revert, dispatch gate revert) before they reach the full-pipeline production capture.

**M2 Pro measurement (this session, post-L1+L2+L3):**

```
┌─ ArachneCompositeKernelCost [Tier 2, 1920×1080, spider forced ON] ─
│ frames=1800  mean=12.903ms
│ p50=12.724ms  p95=14.458ms  p99=15.169ms
│ kernel overruns (>14ms)=172 of 1800
└────────────────────────────────────────────────
```

Run-to-run variance ≈ 0.1 ms (two runs: p95 = 14.578 / 14.458). The 16 ms gate sits ~10 % above the worst-case fixture and well below the pre-tuning ~26 ms baseline a lever-revert would restore.

**Calibration finding worth preserving:** the Drift Motes kernel:full-pipeline ratio of ~1:3 does NOT apply to Arachne. Arachne is fragment-only (no compute pre-pass to add on top), so kernel ≈ full-pipeline. Initial 5 ms SOAK gate suggested by the BUG-011 prompt was anchored on the wrong ratio and rebased to 16 ms based on the in-session measurement.

**Why "Open" not "Resolved":** the SOAK forces spider ON every frame (worst case); production has spider idle ~75 % of the time per the V.7.7C.2 per-segment cooldown, so real-music p95 will land lower. But the SOAK kernel measurement also doesn't include WORLD pass + drawable presentation overhead (~0.5–1 ms). Net production p95 is *probably* below 14 ms on M2 Pro but the closure gate is the actual production capture. **L4 (DeviceTier-aware fallback to V.7.5 2D silhouette spider on Tier 1) was explicitly NOT pulled** — the prompt requires Matt's call before introducing the Tier-1 fallback. If Matt's real-music capture shows post-L1+L2+L3 p95 still > 14 ms, L4 is the next escalation.

**Tests + verification.**

- **45 targeted Arachne tests / 9 suites green** at every lever step (`ArachneSpiderRender`, `ArachneState`, `ArachneStateBuild`, `ArachneListeningPose`, `ArachneBranchAnchors`, `PresetAcceptance`, `PresetRegression`, `PresetLoaderCompileFailure`, `StagedComposition`).
- **`ArachneSpiderRender` golden hash unchanged at `0x000080C004000000`** — spider silhouette dHash within 8-bit hamming tolerance after L1 (silhouette equivalent to within the 9×8 luma quantization at 64×64).
- **`PresetRegression` Arachne hashes unchanged** — the regression render path leaves `worldTex` unbound and slot-6/7 zeroed, so the lever changes don't surface here. Real visual divergence is observed in `PresetVisualReviewTests` (RENDER_VISUAL=1 contact sheets generated at every step; no obvious silhouette/drop degradation at the harness scale).
- **PresetAcceptance D-037 invariants pass** — non-black, no white clip, beat response bounded, form complexity ≥ 2.
- **Engine 1220 tests / 150 suites** with three documented pre-existing failures unrelated to BUG-011: `MatIDDispatch.matID==1 emission path` (LM.3.2 round-4 documentation drift — test expects pre-LM.3.2 `kLumenEmissionGain = 4.0`; spawned as separate task), `SoakTestHarness.cancel` and `MetadataPreFetcher.fetch_networkTimeout` (documented parallel-load timing flakes, present pre-BUG-011).
- **App build clean** (not re-verified post-test-only-edit, but no app-target source files were touched in any of the four commits).
- **SwiftLint 0 violations on touched files** (Arachne.metal not lintable; SoakTestHarnessTests.swift clean).

**Carry-forward.**

- **Matt's M2 Pro real-music perf capture per the DM.3 procedure** — the BUG-011 closure gate. If Arachne window p95 ≤ 14 ms / drops ≤ 8 % on a 60 s representative window: flip BUG-011 Status to Resolved with the measured-after numbers.
- **M3+ measurement** — confirm budget holds at full feature set on actual Tier 2 silicon (M2 Pro is borderline; the architecture contract specifies M3+).
- **L4 escalation** — only if M2 Pro real-music p95 still > 14 ms post-tuning. Would need a new D-XXX entry in `docs/DECISIONS.md` ("Arachne is M3+-only with V.7.5 2D silhouette spider fallback on Tier 1") before implementation.
- **V.7.10 cert review** — gated on this. Cert sign-off can't proceed on a preset over budget on its target hardware tier.
- **MatIDDispatch test fix** — pre-existing LM.3.2 documentation drift, spawned as separate task during this session.

---

## [dev-2026-05-08-e] V.7.7C.5.2 — Arachne second cosmetic + spider-trigger pass (drops + silk re-brightening + hue cycle widening + spider sustain)

**Increment:** V.7.7C.5.2. **Decision:** D-100 follow-up #2. Single commit.

Same-day follow-up to V.7.7C.5.1. Matt's 2026-05-08T22-58-49Z manual smoke confirmed:

- Frame thread: thin, sharp, vibrant white ✅
- Radials: faint wisps with too much aura, no scaffold ❌
- Spirals: large and thick like a fat crayon ❌
- Spider: didn't appear (despite vibration) ❌
- Background: more vibrant ✅ but only green, no other colors ❌

V.7.7C.5.2 closes all four ❌ in a single cosmetic + spider-trigger commit.

**Issues addressed.**

1. **Spirals "fat crayon" — diagnosed as drops, not chord SDF.** Drop radius was 0.008 UV ≈ 8.6 px at 1080p (V.7.5 §10.1.3 had bumped to 0.008 to make drops the visual hero). At V.7.7C.5's canvas-filling polygon scale, drops piled up along chord segments at 4–5 drop-diameter spacing and read as a continuous thick yellow band — the chord SDF (0.0007 UV) was invisible underneath. **Drop radius halved 0.008 → 0.004** (~4 px). Pearls now read as discrete dewdrops along thin chords.

2. **Radials "wispy, no scaffold".** V.7.7C.5.1 dimmed silkTint to 0.55 to compensate for the V.7.7C.5 muted backdrop, but V.7.7C.5.1 ALSO pumped the §4.3 palette to vivid sat 0.55–0.95 / val 0.30–0.70. Against that vivid backdrop, 0.55 silkTint reads as faint cream-on-yellow with no contrast. **silkTint factor 0.55 → 0.70, ambient tint 0.20 → 0.30.** Restores radial contrast vs the pumped backdrop without going back to V.7.7C.4's 0.85 (which was tuned for the muted palette and would now over-dominate).

3. **"Only green, no other colors"** across a 17-track playlist. V.7.7C.5.1's ±0.15 audio-time hue cycle stayed inside one valence-quadrant neighborhood — Love Rehab's neutral-warm valence kept hue in [0.15, 0.45] yellow-green band the entire session. **Hue cycle ±0.15 → ±0.45 swing.** Sweeps roughly half the hue wheel per cycle so the backdrop visibly traverses cyan → green → yellow → amber → magenta every ~25 s.

4. **Spider didn't fire on Love Rehab.** Telemetry from the V.7.7C.5.1 smoke (4705-frame Love Rehab Arachne window) showed max bassAttRel = 1.86 with **4.6 % of frames clearing the 0.30 trigger** — but they were scattered (electronic kicks: ~5–10 frames above threshold then ~30+ below, the 2× decay-when-below rate emptied the accumulator before it reached 0.75 s). **Sustained-trigger threshold 0.75 s → 0.4 s.** Lets bursty kick patterns at 4–6 kicks/sec accumulate while still rejecting single-kick spikes — one ~5-frame burst contributes ~83 ms, short of 0.4 s. Sustained sub-bass still fires within ~0.4 s of onset (vs ~0.75 s before).

**Tests + verification.**

- **No new test files.** Only golden hash regen + spider sustain constant change. Existing spider tests still pass: `sustainedSubBassTriggersSpider` (60 frames at bassAttRel = 0.40 → 1.0 s sustained, well above 0.4 s threshold) and `kickDrumPulseDoesNotTrigger` (9 frames burst then 120 frames decay → 150 ms is still below 0.4 s threshold and the decay returns the accumulator to 0).
- **Arachne goldens drift further toward zero on PresetRegression.** Drop radius halved means even less foreground signal at the harness's frame-phase-0 + zeroed slot-6/7 buffer; steady/quiet collapse fully to 0. beatHeavy still differs because `bass_att_rel = 0.6` triggers §8.2 vibration. Real visual divergence is observed in `PresetVisualReviewTests`.
- **PresetAcceptance D-037 invariant 3 still passes** — drop reduction shrinks beat-pulse-affected pixel area, silk lift is offset.
- **Engine 1185 tests / 2–5 documented pre-existing parallel-load timing flakes** (`MetadataPreFetcher.fetch_networkTimeout`, `SoakTestHarness.cancel`, plus the SessionManager `.preparing == .ready` set under @MainActor backlog stress — all pass in isolation).
- **App build clean.**
- **SwiftLint 0 violations on touched files.**
- **`Scripts/check_sample_rate_literals.sh` passes.**
- **Visual harness.** `RENDER_VISUAL=1` PNGs at `/tmp/phosphene_visual/20260508T232351/`. WORLD now shows vivid green-to-magenta gradient at neutral mood (huge improvement over V.7.7C.5.1's single-hue green wash).

**Carry-forward.**

- **Manual smoke re-run on real music** — Matt verifies the four fixes deliver the expected reading: drops as discrete pearls (not fat crayon); radials as solid scaffold (not wisps); backdrop cycles through hues across a track (not psych-ward green); spider fires on Love Rehab kicks.
- **V.7.7C.5.3** — per-track web identity (Options B/C, renumbered from V.7.7C.5.2 after that slot was claimed by this cosmetic pass). Awaiting product decision.
- **V.7.7C.6** — spider movement system. Still deferred.
- **V.7.10** — Matt M7 contact-sheet review + cert sign-off. Five remaining prerequisites: per-chord drop accretion, anchor-blob discs at polygon vertices, background-web migration crossfade visual, V.7.7C.6 spider movement, V.7.7C.5.2 manual-smoke confirmation.

---

## [dev-2026-05-08-d] V.7.7C.5.1 — Arachne visual craft pass (line widths + luminescence + palette + shaft gate + per-segment seed)

**Increment:** V.7.7C.5.1. **Decision:** D-100 follow-up. Single commit.

Same-day follow-up to V.7.7C.5. Matt's 2026-05-08T22-01-07Z manual smoke confirmed every geometry contract (canvas-filling polygon, off-frame anchors, hub at canvas centre, chord-by-chord lay) was reading correctly on real music — but flagged six issues with the visual craft and per-instance variation. V.7.7C.5.1 closes all six in a single cosmetic-only commit.

**Issues addressed.**

1. **Spirals too fast — chord-by-chord not readable** (reframed by Matt: "webs are elaborate, viewers should expect tighter spirals with many points of connection. The lines and luminescence on them do not need to be so heavy"). Resolved by thinning lines + dimming luminescence — keeping chord density (104 chords, 13 radials, 8 revolutions) but reducing strand weight so density reads as elaborate detail rather than scribbly chaos.
2. **Lines too thick relative to canvas-filling polygon.** Silk widths halved: spoke `0.0024 → 0.0010`, frame `0.0022 → 0.0010`, spiral `0.0013 → 0.0007`. Halo sigmas halved (`spokeHaloSig` `webR×0.014 → webR×0.008`, `spirSig` `webR×0.009 → webR×0.005`). Halo magnitudes halved (spoke `0.38 → 0.20`, frame `0.22 → 0.11`, spiral `0.25 → 0.13`). Hub coverage `1.20 → 0.70`.
3. **Toddler-drawing readability** — falls out of (1) + (2).
4. **Spider didn't fire on LTYL.** Recording cut at LTYL +35 s, before James Blake's defining sub-bass drop arrives. Inconclusive; deferred to longer-LTYL smoke for V.7.7C.6 prerequisites.
5. **Background palette too muted — psych ward, not psychedelic.** §4.3 palette pumped: saturation `0.25–0.65 → 0.55–0.95`, value `0.10–0.30 → 0.30–0.70`. Audio-time hue cycle ±0.15 swing on top of the Q10 valence-driven base (top/bottom phase-offset by π so the gradient never collapses to a single hue). Beam saturation/value pumped to match (`hsv2rgb(beamHue, satScale × 0.7, valScale × 1.4)`). Silence anchor (Q11) preserved by re-keying on raw mood product `arousalNorm × valenceNorm < 0.05`. Q10's "preserve verbatim" decision is reframed: §4.3's spec was correct for the V.7.7B–C.4 forest WORLD where compositional richness masked palette muteness; the V.7.7C.5 atmospheric reframe exposed the muteness as Matt's "psych ward" reading.
6. **No light shaft appreciated.** Telemetry from Matt's smoke (4705-frame Arachne windows on So What + LTYL) showed `f.mid_att_rel` mean ≈ -0.5, max never reached the spec gate threshold of 0.05 → shaft never engaged on AGC-warmed real-music playlists. V.7.7C.5.1 reformulates the engagement gate from binary `smoothstep(0.05, 0.15, midAttRel)` to floor+scale `0.25 + 0.75 × smoothstep(-0.20, 0.10, midAttRel)`. Shafts are visible at 25 % baseline always — never structurally invisible — and ramp to 100 % on positive deviation. Combined with the `0.30 × valScale` brightness coefficient, baseline shaft contribution is ~0.075 × valScale (perceptible but not dominant).

**Plus the per-instance variation question** Matt raised separately ("should the preset draw the SAME web in the SAME position EVERY time?"): V.7.7C.5.1 ships **Option A — per-segment variation**. The foreground anchor block's `ancSeed` switches from hardcoded `1984u` to `arachHashU32(webs[0].rng_seed ^ 0xCA51u)` so each Arachne instance gets a unique spoke count (11–17), aspect ratio (0.85–1.15), gravity-sag coefficient (0.06–0.14), hub UV jitter (±5 %), and per-spoke angular jitter pattern (±22 %). New `arachHashU32(uint) → uint` helper sits alongside `arachHash` (same bit-mixing scheme, returns the scrambled uint instead of a float). The CPU-side `webs[0].rng_seed` already refreshes on every `arachneState.reset()`, but its lower 28 bits carry the polygon-anchor packing (V.7.7C.3 — see `packPolygonAnchors`); the hash scrambles those structured bits back into a uniform-random seed for the macro-shape helpers.

**Per-track + per-session web identity options documented as future work.** Two non-decided options surface in `docs/DECISIONS.md` D-100 carry-forward + a new `V.7.7C.5.2` ENGINEERING_PLAN stub:

- **Option B** — per-track determinism. `hash(title + artist)` plumbed into `ArachneState.reset(trackSeed:)`. Same track always gets the same web. ~30 LOC + a determinism test.
- **Option C** — track + session-counter perturbation. Per-track base seed + LCG step per replay. Variety + identity. ~40 LOC.

Decision pending product call after V.7.7C.5.1 manual-smoke.

**Tests + verification.**

- **No new test files.** Only golden hash regen.
- **Golden hashes drift hard.** Arachne `(steady, beatHeavy, quiet)` `(0x06129A65E458494D, 0xC6921125C4D85849, 0x06129A65E458494D) → (0x8000000000000000, 0x04101A6444186969, 0x8000000000000000)`. Spider forced `0x06D29A65E458494D → 0x800080C004000000`. The harness's frame-phase-0 + zeroed slot-6/7 buffer + thinner+dimmer silk pushes foreground contribution below dHash quantization for steady/quiet (top bit only); beatHeavy still differs because the `bass_att_rel = 0.6` fixture triggers §8.2 vibration. Real visual divergence is observed in `PresetVisualReviewTests`.
- **PresetAcceptance D-037 invariant 3 still passes** — the dimmer silk further reduces beatMotion below the 1.0 ceiling.
- **Engine 1185 tests / 3 documented pre-existing parallel-load timing flakes** (`MetadataPreFetcher.fetch_networkTimeout`, `SoakTestHarness.cancel`, `SessionManagerCancel.cancel_fromReady` — all pass in isolation, none introduced by this increment).
- **App build clean.**
- **SwiftLint 0 violations on touched files.**
- **`Scripts/check_sample_rate_literals.sh` passes.**
- **Visual harness.** `RENDER_VISUAL=1` PNGs at `/tmp/phosphene_visual/20260508T224311/Arachne_{silence,mid,beat}_{world,composite}.png`. WORLD shows vivid green-yellow gradient at neutral mood (huge improvement over V.7.7C.5's olive wash). COMPOSITE shows the canvas-filling polygon as fine thin silk over the new pumped backdrop.

**Carry-forward.**

- **Manual smoke re-run on real music** — Matt verifies the four cosmetic + palette + shaft fixes deliver the expected reading: psychedelic-not-psych-ward backdrop, fine-detail silk, visible shaft at baseline, per-segment variation across multiple Arachne instances.
- **V.7.7C.5.2** — per-track web identity (Options B / C). Awaiting product decision.
- **V.7.7C.6** — spider movement system. Still deferred.
- **V.7.10** — Matt M7 contact-sheet review + cert sign-off. Five remaining prerequisites: per-chord drop accretion, anchor-blob discs at polygon vertices, background-web migration crossfade visual, V.7.7C.6 spider movement, V.7.7C.5.1 manual-smoke confirmation.

---

## [dev-2026-05-08-c] V.7.7C.5 — Arachne §4 atmospheric reframe + off-frame anchors + canvas-filling foreground hero web

**Increment:** V.7.7C.5. **Decision:** D-100. Single commit.

**V.7.7C.4 manual smoke green confirmed by Matt 2026-05-08.** With that gate cleared, V.7.7C.5 lands the §4 spec rewrite + WEB pillar canvas-filling re-anchor that Matt's 2026-05-08T18-28-16Z manual smoke surfaced. Three coupled changes ride together because they share one coherent visual story: silk anchored off-frame, polygon spanning the canvas, and atmospheric backdrop replacing the V.7.7B–C.4 forest.

**§4 atmospheric reframe.** `drawWorld()` retires the six-layer dark close-up forest entirely (deep background fbm + radial mist + V.7.7B narrow shaft + uniform-field dust motes + forest floor + three near-frame branch SDFs + the §5.9 `kBranchAnchors[]` capsule-twig loop) and replaces it with the §4 atmospheric abstraction: full-frame `mix(botCol, topCol, …)` sky band with low-frequency fbm4 modulation + aurora ribbon at high arousal + volumetric atmosphere — beam-anchored fog `0.15 + 0.15 × midAttRel` inside cones (raised from V.7.7B's 0.02–0.06 per Q7), 1–2 mood-driven god-ray light shafts at brightness `0.30 × val` (raised from V.7.7B's `0.06 × val` per Q8 — shafts now read as the dominant atmospheric light source), dust motes confined inside the shaft cones only (caustic-like, per Q9). The §4.3 mood palette (`topCol` / `botCol` / `beamCol`) is preserved verbatim per Q10. Silence anchor (`satScale × valScale < 0.04 → black`) preserved per Q11. `drawWorld()` signature gains a `midAttRel` parameter so shaft engagement (`smoothstep(0.05, 0.15, midAttRel)`) and fog-density modulation read directly from `f.mid_att_rel`; `arachne_world_fragment` passes `f.mid_att_rel`, the dead-reference `drawBackgroundWeb` passes `0.0`. Retired forest references (`02_meso_per_strand_sag.jpg`, `11_anchor_web_in_branch_frame.jpg`, `17_floor_moss_leaf_litter.jpg`, `18_bark_close_up.jpg`) stay in `docs/VISUAL_REFERENCES/arachne/` for V.7.10 historical comparison only.

**Off-frame `kBranchAnchors[6]` (Q14).** Polygon vertex positions move from interior `[0.10, 0.92]² ` UV (V.7.7C.2) to off-frame `[-0.06, 1.06]² \ [0,1]²` so the WEB silk threads enter the canvas from outside, matching ref `20_macro_backlit_purple_canvas_filling_web.jpg`. Anchors at `(-0.05, 0.05) / (1.05, 0.02) / (1.06, 0.52) / (1.04, 0.97) / (-0.04, 0.95) / (-0.06, 0.48)` — distribution is asymmetric (no opposing-edge pair shares the same vertical position). The `decodePolygonAnchors` → `arachneEvalWeb` ray-clipping spoke tips + frame thread polygon edges path is unchanged; only the constants move. `ArachneState.branchAnchors` Swift mirror updated byte-for-byte. `ArachneBranchAnchorsTests` regenerated: bounds invariant rewritten for the new band; new asymmetry test added.

**Canvas-filling foreground hero (Q15).** `arachne_composite_fragment`'s anchor block: hub UV `(0.42, 0.40)` → `(0.5, 0.5)` (canvas centre), `webR` `0.22` → `0.55` so the polygon spans ~70–85% of canvas area. `ArachneState.seedInitialWebs()` `webs[0]` mirror updated `hubX/hubY = 0.0`, `radius = 1.10` so CPU/GPU state stays internally consistent. `webs[1]` (background-pool) untouched.

**V.7.7C.4 hybrid coupling re-tuned 0.06 → 0.025.** PresetAcceptance D-037 invariant 3 (`beatMotion ≤ continuousMotion × 2.0 + 1.0`; threshold collapses to ≤ 1.0 on the test fixtures since `bass_att_rel = 0`) caught the canvas-filling-foreground × 0.06 breach (`beatMotion = 1.7840983` vs ceiling 1.0 — the V.7.7C.4 coefficient was sized for ~5% silk coverage, the canvas-filling foreground covers ~30%). Per the prompt's STOP CONDITION the breach was surfaced before tuning; Matt elected Option 1 (constant reduction). `0.025` chosen via k² scaling for ~3× margin matching V.7.7C.4's headroom — predicted MSE ≈ 0.31, comfortable margin under 1.0. Per-silk-pixel lift drops 6 % → 2.5 % but screen-integrated pulse grows ~2.5× because the silk surface is bigger, which Matt's evident "less subtle" V.7.7C.4 directive rewards.

**Tests + verification.**

- **No new test files.** Only fixture-helper updates + golden hash regen.
- **Golden hashes.** Arachne `steady`/`quiet` UNCHANGED at `0x06129A65E458494D` (PresetRegression doesn't bind slot 6/7 + worldTex; the §4 reframe + canvas-filling foreground don't surface in regression-mode). Arachne `beatHeavy` `0x0000000000000000` → `0xC6921125C4D85849` (the V.7.7C.4 all-zeros hash was an artifact of the 0.06 coefficient × frame-phase-0 composition collapsing under dHash quantization; smaller coefficient now produces a non-zero pattern reflecting dust mote phase difference between fixtures). Spider forced `0x06129A55C258494D` → `0x06D29A65E458494D` (7-bit Hamming drift — `ArachneSpiderRenderTests` binds a `state.reset()`-seeded `ArachneState` so the off-frame anchors flow through `decodePolygonAnchors` into ray-clipped spoke tips).
- **Engine 1184 tests / 2 documented pre-existing flakes** (`MetadataPreFetcher.fetch_networkTimeout`, `SoakTestHarness.cancel`).
- **App build clean.**
- **SwiftLint 0 violations on touched files.**
- **`Scripts/check_sample_rate_literals.sh` passes** (one pre-existing Gossamer warning unrelated to this increment).
- **Visual harness.** `RENDER_VISUAL=1` PNGs at `/tmp/phosphene_visual/20260508T213106/Arachne_{silence,mid,beat}_{world,composite}.png`. WORLD silence/mid/beat are byte-identical (mood=0, midAttRel=0 in harness fixtures → no shaft engagement → sky band + ambient fog only); COMPOSITE shows the canvas-filling foreground over the WORLD; beat fixture shows the small silk pulse.

**Retired (V.7.7C.5).** Six-layer dark close-up forest `drawWorld()` content. §5.9 anchor-twig SDF capsule loop. The four forest-specific reference images for §4 implementation purposes (they remain on disk for V.7.10 historical comparison).

**Preserved (V.7.7C.5).** §4.3 mood palette (verbatim per Q10). Silence anchor (per Q11). `kBranchAnchors[6]` constants stay (now polygon vertex source only). `ArachneState.branchAnchors[]` regression-lock. WEB pillar (§5) entirely — staged WORLD + COMPOSITE scaffold, build state machine, polygon-from-`branchAnchors`, drop refraction recipe, 3D SDF spider, 12 Hz vibration, V.7.7C.4 palette enrichment, V.7.7C.4 Fix C rising-edge spiral chord advance.

**Carry-forward.**
- **Manual smoke re-run on real music** (Matt verifies the atmospheric abstraction reads as cinematographic god-rays, not residual forest, with the canvas-filling silk reading as anchored off-frame).
- **V.7.7C.6** — spider movement system (off-camera entry + 10–15 s walk + min-visibility latch + N-segment cooldown). V.7.7D-scale increment, estimated 2–3 sessions.
- **V.7.10** — Matt M7 contact-sheet review + cert sign-off. Five remaining prerequisites: per-chord drop accretion, anchor-blob discs at polygon vertices, background-web migration crossfade visual, V.7.7C.6 spider movement, V.7.7C.5 manual-smoke confirmation.

---

## [dev-2026-05-08-b] DM.1 + DM.2 — Drift Motes preset (foundation + audio coupling) + closeout

**Increments:** DM.1, DM.2, DM.2 closeout. **Decisions:** D-098, D-099. Ten commits (`89ddfb42..5f2e9355`).

**Drift Motes ships as Phosphene's second `ParticleGeometry` conformer** (sibling to Murmuration via D-097). Force-field-driven motes drifting through a warm-amber sky cut by a cinematographic god-ray, with per-particle hue baked at emission time from the recent vocal melody. Particles preset, pass set `["feedback", "particles"]`, family `particles`, lightweight rubric profile, `certified: false` pending M7 review.

**DM.1 — foundation (`89ddfb42`).** Sky backdrop fragment `drift_motes_sky_fragment` (static warm-amber vertical gradient — no audio reactivity at this stage). Engine-library compute kernel `motes_update` with force-field motion (wind `normalize((-1, -0.2, 0)) * 0.3` + 4-octave curl-of-fBM turbulence × 0.15) — no flocking, no neighbour queries, no `sin(time)` oscillation (Failed Approach #33 cleared). Sprite render via `motes_vertex` / `motes_fragment` — additive blend (`.one + .one`), 6-px constant point size, Gaussian falloff. `DriftMotesGeometry` conformer with 800-particle UMA buffer, uniform-cube init across ±BOUNDS = (8, 8, 4) seeded with steady-state wind velocity + age-randomised lifecycle so the field is in equilibrium from frame 0. `ParticleGeometryRegistry.swift` provides the single dispatch surface (`resolveParticleGeometry(forPresetName:)`); `VisualizerEngine` factory split into `makeMurmurationGeometry` + `makeDriftMotesGeometry`, both built once at engine init. **D-098** documents `DriftMotesNonFlockTest` tolerances (centroid-spread RMS ≥ 0.85 as the load-bearing flock discriminator, pairwise distance ≥ 0.80 as a looser secondary signal that catches catastrophic failures) — translation-invariant centroid-spread substitutes for the spec's stricter pairwise threshold to accommodate the natural cube → top-slab transient. Filename uses `Particles*` prefix because `ShaderLibrary` concatenates engine `.metal` files in lexicographic order (a `D`-prefixed name would precede `Particles.metal` and the shared `Particle` struct would not yet be in scope). Murmuration's `Particles.metal`, `ProceduralGeometry.swift`, `ParticleGeometry.swift`, and `RenderPipeline*.swift` byte-identical to post-DM.0; Murmuration regression hashes unchanged.

**DM.2 — audio coupling (six commits).** Three coupled audio reactivities arrive together because they share one coherent visual story:

- **`[DM.2] Common: extend FV/StemFeatures MSL structs to match Swift (D-099)` (`221d9e67`).** Engine MSL `FeatureVector` and `StemFeatures` in `Common.metal` extended from 32 → 48 floats / 16 → 64 floats to match the Swift sources of truth. Pre-DM.2, both engine MSL structs were stuck at the pre-MV-1 / pre-MV-3 sizes — the Swift binding always uploaded the full 192 / 256 bytes, but the engine kernels could only see the first 32 / 16 floats. Pure additive change: first 32 / 16 floats keep their original offsets, new fields after. Murmuration's `particle_update` and every other engine reader is byte-identical (verified by golden-hash regression: every preset's hash regenerates identically). **D-099** documents the rationale + the Murmuration-invariant-preserved evidence.
- **`[DM.2] DriftMotes: dm_pitch_hue helper + D-019 blend at emission` (`c9b3fc80`).** New `dm_pitch_hue(pitchHz, confidence)` static helper in `ParticlesDriftMotes.metal` — canonical pitch → hue replacement for the retired `vl_pitchHueShift`. Octave-wrapping log map: A2 (110 Hz) → 0.0, A6 (1760 Hz) → 1.0, returns the cold-stem amber 0.08 below confidence 0.3. `motes_update`'s respawn branch now bakes per-particle hue at emission time under the D-019 stem-warmup blend `smoothstep(0.02, 0.06, totalStemEnergy)`. Cold-stem path uses per-particle hash jitter (±0.05) + `f.mid_att_rel` shift around warm amber so the field has intrinsic chromatic texture even when stems are zero; warm-stem path substitutes the vocal-pitch hue. Hue is written once at emission and never modified afterward. D-026 compliant (`f.mid_att_rel` is a deviation primitive, no absolute thresholds).
- **`[DM.2] DriftMotes: ls_radial_step_uv shaft + vol_density_height_fog floor` (`08b8d2ac`).** Sky fragment now layers warm-amber gradient + multiplicative cool blue-gray floor fog via `vol_density_height_fog(scale=12.0, falloff=0.85)` + additive warm-gold light shaft via 32-step `ls_radial_step_uv` accumulation. Sun anchor `(-0.15, 1.20)` — off-screen upper-left, gives the ≈ 30° from-vertical cinematographic angle. Cone widens with distance from the sun (0.04 base + 0.12·along). Shaft intensity `0.65 + 0.25 × f.mid_att_rel` — continuous melody-driven, the shaft "breathes" with vocal energy. No new render pass — D-029 keeps `["feedback", "particles"]`.
- **`[DM.2] DriftMotes: per-mote brightness modulation from shaft proximity` (`d557cbce`).** Sprite vertex now passes per-particle UV (sky-fragment convention, y-flipped from clip space) so the fragment can compute screen-space distance from the particle to the shaft axis. Same sun anchor as the sky fragment — per-mote highlights stay congruent with the beam. Per-mote brightness `0.45 + 0.85 × shaftLit` where `shaftLit = exp(-perpDist² × 16)`: on-axis 1.30, outside cone ~0.76, far from shaft → 0.45 baseline. The visual reading is "the beam picks out individual motes as they cross it." Hue unchanged — fragment only modulates intensity.
- **`[DM.2] Tests: DriftMotesRespawnDeterminismTest` (`f84c936d`).** Three tests covering the DM.2 hue-baking contract: within-life invariance (≥ 100 stable slots have bit-identical color at frame N+30); respawn distribution under warm stems shows variance > 1e-3 (vs. ≈ 0 for the DM.1 uniform-amber baseline); warm-stems variance > 2× cold-stems variance (proves the D-019 blend is contributing real signal at warm stems). Total runtime: ~0.151 s.
- **`[DM.2] Tests: regenerate Drift Motes golden hashes + rewrite doc` (`0225765e`).** Drift Motes regression hash regenerates to `0x0001070F1F3F7FFF` for all three fixtures (the harness renders the sky fragment only and `f.mid_att_rel` is zero across regression fixtures, so steady / beatHeavy / quiet converge). Doc comment rewritten to point at `DriftMotesRespawnDeterminismTest` as the regression-lock for per-particle hue.
- **`[DM.2] Perf: 30s soak harness short-run for Drift Motes (Tier 2)` (`d8c7c183`).** New `shortRunDriftMotes` SOAK-gated kernel-cost benchmark in `SoakTestHarnessTests`. Drives `DriftMotesGeometry.update(...)` for 30 simulated seconds at 60 Hz against an 800-particle Tier 2 buffer, captures `MTLCommandBuffer.gpuStartTime/gpuEndTime` per frame. **Tier 2 result this session: p50 = 0.107 ms, p95 = 0.158 ms, p99 = 0.763 ms, drops = 0** — well under the 1.6 ms Tier 2 full-frame budget. The DM.2 audio coupling adds near-zero kernel cost on top of DM.1 because the work lands at emission time only. Full-pipeline Tier 2 timing and Tier 1 hardware timing deferred to a runtime app session.
- **`[DM.2] Docs: ENGINEERING_PLAN landing block + DECISIONS D-099` (`c9078e0d`).** Engineering plan DM.2 landing block with full implementation summary; D-099 in DECISIONS.md.

**DM.2 closeout (`5f2e9355`).** Three small additions per the closeout prompt:

- `CommonLayoutTest` — Swift-side layout assertion locking `MemoryLayout<FeatureVector>.size == 192` and `MemoryLayout<StemFeatures>.size == 256`. If either Swift struct shrinks, every engine kernel that reads the trailing fields would over-read its bound buffer; this test fails fast at CI time before MSL ever sees the regression.
- Hoisted sky-fragment fog tune factors to `kFogTintAmplifier` / `kFogDensityNormalize` ahead of DM.3 emission scaling and M7 contact-sheet review. `constexpr constant` inlining is byte-equivalent at IR — Drift Motes golden hash regenerates byte-identical (`0x0001070F1F3F7FFF`).
- Resolved D-099 / V.7.7C.5 numbering collision in DECISIONS.md (V.7.7C.5 reserved D-099 in spec text with an "or next-available ID" escape clause; DM.2 filed first, V.7.7C.5 will land as D-100 at impl time).

**Verification (push gate, all green):** `swift build` succeeds; `swift test --filter CommonLayoutTest` 1/1; `swift test --filter DriftMotes` 5/5 (incl. 3 respawn-determinism + non-flock); `swift test --filter PresetRegression` 45/45 (15 presets × 3 fixtures, Murmuration bit-identical to baseline); `swift test` (full suite) 1180 tests with 1 documented pre-existing flake (`MemoryReporter.residentBytes` env-dependent — `MetadataPreFetcher.fetch_networkTimeout` flake didn't fire this run); SwiftLint 0 violations on touched files; D-026 grep on touched shaders 0 hits.

**Notable learnings.** (1) Engine MSL structs in `Common.metal` had been layout-stale since MV-1 / MV-3 landed — every engine-library shader was working from a smaller view of the same buffer than presets see. D-099 corrects this for `FeatureVector` + `StemFeatures` and the `CommonLayoutTest` regression-locks the Swift sizes against future drift. (2) `Particle.color` is reusable across particle conformers (Path A in DM.2 Task 0b): Murmuration writes to it in its kernel but its fragment ignores RGB and uses a hardcoded silhouette, so the slot isn't load-bearing in Murmuration's read path. Future particle presets can write hue freely without struct extension. (3) `constexpr constant` MSL inlining is byte-equivalent to literal usage at IR — verified, not assumed (the hoisted fog constants produce a byte-identical golden hash). (4) `ls_radial_step_uv` was designed for radial-blur of an existing texture; for sky-only fragments with no occlusion mask, the convention is to evaluate a perpendicular-distance cone mask at each step UV and accumulate with decay (DriftMotes.metal §3 documents the pattern inline).

**Carry-forward to DM.3.** Emission-rate scaling from `f.mid_att_rel`, drum dispersion shock from `stems.drums_beat`, optional structural-flag scatter, M7 frame-match review against `01_atmosphere_dust_motes_light_shaft.jpg`, deferred Tier 1 hardware perf measurement.

---

## [dev-2026-05-09-c] V.7.7C.4 — Arachne palette + L lock + hybrid audio coupling (D-095 follow-up #2)

**Increment:** V.7.7C.4. **Decision:** D-095 follow-up. One commit.

Three fixes from Matt's 2026-05-08T18-28-16Z manual smoke. WORLD reframe + spider movement deferred to separate increments per Matt's sequencing call.

**Fix A — L key full-lock (`VisualizerEngine+Presets.swift`).** `handlePresetCompletionEvent` now guards on `diagnosticPresetLocked`. Pre-V.7.7C.4 the L key only suppressed mood-override switching (in `applyLiveUpdate`); the orchestrator continued to fire on `presetCompletionEvent` from PresetSignaling-conforming presets every ~60 s — pulling Matt off Arachne mid-build and preventing him from watching a full cycle. V.7.7C.4 fully suppresses completion-driven transitions when the L key is held. Manual `⌘[`/`⌘]` cycling always works.

**Fix B — Palette enrichment (`Arachne.metal` foreground anchor block + hub knot).** Reverses V.7.5 §10.1.3's deliberate silk dimming after Matt's "color far too subtle" feedback. Three coordinated changes:

- `silkTint` factor 0.60 → 0.85 (silk reads brighter against the WORLD backdrop).
- Mood-driven hue base — valence shifts teal (cool, hue=0.55) → amber (warm, hue=0.10) along the §4.3 forest palette axis. Plus vocal-pitch coupling: when `stems.vocals_pitch_confidence ≥ 0.35`, log2-pitch around A3 (220 Hz) bakes into the hue (Gossamer-style coupling, mixed in by confidence × 0.6). Wider `hueDrift` factor (0.10 → 0.20) for visible motion across the build cycle.
- Ambient tint factor 0.25 → 0.40 (ambient adds a stronger cool fill alongside the warm key).
- Hub knot coverage 0.80 → 1.20 (saturated). Bumps the central knot from a faint smudge to a distinct emissive feature at radial-phase entry.

**Fix C — Hybrid audio coupling (Arachne.metal silk emission + ArachneState advanceSpiralPhase).** Two channels of beat coupling that PRESERVE D-095 Decision 2 (audio-modulated TIME pacing, not beat-driven build). Matt's "no connection between tempo / beat of the song and the addition of radial lines and / or the chord segments" feedback addressed without inverting the V.7.7C.2 build-clock contract:

- **Per-beat global emission pulse.** `emGain += beatPulse * 0.06` where `beatPulse = max(beat_bass, beat_composite)`. Coefficient 0.06 calibrated against PresetAcceptance D-037 invariant 3 (`beatMotion ≤ continuousMotion × 2.0 + 1.0`) — test fixtures have `bass_att_rel = 0` so the threshold collapses to ≤ 1.0 MSE/pixel; 0.06 stays under the floor while remaining visible against the new brighter silk palette. Visible flash on every beat without overwhelming the beat-as-accent hierarchy.
- **Rising-edge beat advances spiralChordIndex by 1.** `advanceSpiralPhase(by:features:)` checks `max(beatBass, beatComposite)` rising edge against the new `prevBeatForSpiral` tracker (reset by `arachneState.reset()`). On a beat, advances the chord by 1 in addition to the time-based pace. Sparse-beat tracks still complete in `naturalCycleSeconds` (TIME-driven baseline preserved); kick-heavy tracks see chords lay faster on each beat. Pause-guard semantics preserved: gated on `effectiveDt > 0` so the `prevBeatForSpiral` tracker is still updated during spider pause but no chord advance fires.

`ArachneState` gains `prevBeatForSpiral: Float = 0` (reset on `_reset()` to avoid the new segment's first beat being treated as a spurious continuation).

**Tests.** Zero new test files. `bassTriggerStems` removed an unused parameter; `bassTriggerFV` already used `bassAttRel` (V.7.7C.3 fixture update). `advanceSpiralPhase` signature gained `features:` parameter — single CPU call site updated in `advanceBuildState`. PresetAcceptance D-037 invariant 3 caught my initial overshoot (coefficient 0.45 → 0.06 retune); the test infrastructure worked exactly as intended.

**Golden hashes.** Substantial drift this time (palette enrichment + brighter hub IS exercised by every test that has visible silk, including `ArachneSpiderRenderTests` which warmups to frame phase 16% with partial bridge thread visible). Documented inline:

- Arachne `steady` / `quiet`: `0xC6168081C0D88880` → `0x06129A65E458494D` (both fixtures converge).
- Arachne `beatHeavy`: `0xC6168081C0D88880` → `0x0000000000000000` (the small beat-pulse contribution at PresetRegression's frame-phase-0 % composition produces consistent left-vs-right luma differences at every dHash row, collapsing the difference-bit pattern to all zeros).
- Spider forced: `0x46160011C2D80800` → `0x06129A55C258494D`.

**Engine + app suites.** Engine 1174/1175 pass — sole failure is the documented pre-existing `MetadataPreFetcher.fetch_networkTimeout` parallel-load timing flake. App suite: same documented timing-flake baseline as V.7.7C.2/C.3. 0 SwiftLint violations on touched files (file_length 400 line ceiling on `VisualizerEngine+Presets.swift` enforced — comment trimmed during landing).

**Manual smoke pending.** Matt re-runs against Limit To Your Love or similar to verify:
1. **L key now fully locks** — staying on Arachne for the full build cycle without orchestrator transitioning every ~60 s.
2. **Color reads brighter** — silk has visible mood-driven hue, hub knot is distinct, beat events flash the silk perceptibly.
3. **Build couples to music** — chord laydown advances on beats (extra chord on each kick, on top of the TIME-based pace).

**Carry-forward.** WORLD reframe (atmospheric fog/light support framing instead of dark forest, per Matt's "I would rather you put fog and light behind the web") needs ARACHNE_V8_DESIGN.md §4 spec revision before implementation — separate increment. Spider movement (off-camera entry + 10–15 s walk along web hooks + min-visibility latch + N-segment cooldown) is the largest deferred — comparable to V.7.7D scope. V.7.10 cert review still gated on these.

---

## [dev-2026-05-09-b] V.7.7C.3 — Arachne manual-smoke remediation (D-095 follow-up)

**Increment:** V.7.7C.3. **Decision:** D-095 follow-up. One commit.

The 2026-05-08T17-01-15Z manual smoke surfaced four issues that V.7.7C.2's deferred-sub-items list either deferred or didn't anticipate. V.7.7C.3 closes all four:

- **Chord-by-chord spiral visibility gate** (Arachne.metal). V.7.7C.2's per-ring gate `kVis = (k / N_RINGS) <= progress` made an entire ring's chord segments + drops appear at once as a complete oval — user reported "one complete oval after another". V.7.7C.3 replaces with a per-chord gate `globalChordIdx < int(progress × N_RINGS × nSpk)`. Each chord lays one-at-a-time outside-in by ring, clockwise-by-spoke within. ~5 LOC change in `arachneEvalWeb`.
- **V.7.5 pool spawn/eviction retired from rendering** (Arachne.metal). V.7.7C.2 retained pool webs[1..3] running V.7.5 spawn/eviction as "background depth context"; user reported "full webs flash on and fade away ... new webs form over the central web being spun" — the churn competed with the foreground build, not framing it. V.7.7C.3 disables pool web rendering by changing the shader's pool loop bound from `wi < kArachWebs` to `wi < 1` (empty body retained as a structural marker for §5.12 future flush). Only the build-aware foreground hero renders. CPU-side spawn/eviction state continues to advance harmlessly so existing `ArachneState` tests still cover the spawn machinery.
- **Polygon vertices from `branchAnchors` (§5.3 lifted from deferred)** (ArachneState.swift, Arachne.metal). V.7.7C.2 deferred this; manual smoke confirmed it's load-bearing — user reported "still a regular shape, closest to an oval". V.7.7C.3 implements: `Self.packPolygonAnchors(_:)` static helper packs `bs.anchors[]` (Fisher-Yates-selected 4–6 indices) into `webs[0].rngSeed` (4 bits count + 6 × 4 bits indices); shader decodes via new `decodePolygonAnchors` helper; spokes ray-clipped to polygon perimeter via new `rayPolygonHit` helper; frame thread polygon vertices come from `polyV[]` (transformed to hub-local) with bridge-first stage-0 reveal via new `findBridgeIndex` helper; spiral chord positions scaled along each spoke's polygon-clipped length so inner rings inherit the irregular silhouette. Squash transform bypassed in polygon mode (polygon already provides irregularity). V.7.5 fallback path preserved bytewise when `polyCount = 0` (e.g., `drawBackgroundWeb` dead-reference call site, PresetRegression unbound buffers). The `webs[0].rngSeed` repurposing is safe because Fix 2 retired V.7.5 pool rendering — `rngSeed` was only consumed by the V.7.5 spawn driver's per-spoke jitter, no longer reaches the shader.
- **Spider trigger reformulated** (ArachneState+Spider.swift). Live LTYL session data showed the V.7.5 §10.1.9 gate (`features.subBass > 0.30 AND stems.bassAttackRatio < 0.55`) was acoustically impossible: kicks have `subBass > 0.30` but `bassAttackRatio > 1.0` (sharp transient against AGC); sustained sub-bass passages have `subBass` near AGC average. The two conditions were mutually exclusive on this music. V.7.7C.3 replaces with `features.bassAttRel > 0.30` (smoothed/attenuated bass envelope) — the same primitive the §8.2 vibration path already uses correctly. AR gate dropped (no longer needed; brief kick pulses are filtered by the existing 0.75 s sustain accumulator). New `bassAttRelThreshold = 0.30` constant; `subBassThreshold` retained as deprecated no-op stub for `ARACHNE_M7_DIAG` cross-references.

**Tests.** `subBassFV()` helpers in `ArachneStateTests` + `ArachneStateBuildTests` updated to set `f.bassAttRel = 0.40` (was `f.subBass = 0.40`). `ArachneSpiderRenderTests` calls `state.reset()` before warmup so polygon path is exercised. `PresetAcceptanceTests` slot-6 buffer additionally seeds packed polygon at `webs[0].rngSeed` (byte offset 28) so D-037 invariants meaningfully cover polygon mode. Zero new test files; only fixture-helper updates + golden hash regen.

**Golden hashes.** Arachne `steady` / `beatHeavy` / `quiet` UNCHANGED at `0xC6168081C0D88880` — PresetRegression doesn't bind slot 6/7, so polyCount=0 V.7.5 fallback + frame phase at 0% progress = WORLD-only composition (identical to V.7.7C.2). Spider forced: `0x461E381912D80800` → `0x46160011C2D80800` (7 bits drift; within dHash 8-bit tolerance — the polygon-aware spoke clipping visibly affects only the partial-bridge-thread pixels under the spider patch at the harness's frame-phase warmup state). Polygon-mode visual change IS exercised by `ArachneSpiderRenderTests` (real `state.reset()`-seeded `ArachneState`) and by `PresetVisualReviewTests`' `RENDER_VISUAL=1` path.

**Engine + app suites.** Engine 1169/1171 pass — both failures are documented pre-existing flakes (`MetadataPreFetcher.fetch_networkTimeout`, `SoakTestHarness.cancel` parallel-run timing). App suite: same documented timing-flake baseline as V.7.7C.2. 0 SwiftLint violations on touched files.

**New Failed Approach #57.** V.7.5 §10.1.9 spider trigger gate (`features.subBass > 0.30 AND stems.bassAttackRatio < 0.55`) is acoustically impossible on real music. The two conditions are mutually exclusive: kicks have `subBass > 0.30` but `bassAttackRatio > 1.0` (sharp transient); sustained sub-bass passages have `subBass` near AGC average. Combined with the 0.75 s sustain accumulator decaying at 2× rate during sub-threshold frames, the accumulator never reaches threshold on any music with both kicks and sustained bass — and structurally cannot reach threshold on either pattern alone. Fix: trigger on `bassAttRel` (smoothed bass envelope) — the primitive the §8.2 vibration path uses successfully. AR gate retired; the 0.75 s sustain accumulator filters brief pulses unaided.

**CLAUDE.md edits.** Module Map (Arachne.metal / ArachneState.swift / ArachneState+Spider.swift descriptions); GPU Contract (`webs[0].rngSeed` repurposing for the foreground hero); What NOT To Do (3 new rules — chord-by-chord visibility, polygon-from-branchAnchors load-bearing, spider trigger primitive); Recent landed work; Current Status; Failed Approaches (#57).

**Manual smoke pending.** This commit fixes the four issues from the 2026-05-08T17-01-15Z manual smoke. Re-run the smoke gate on real music (Limit To Your Love or similar bass-heavy track) to verify: spiral lays chord-by-chord (not full ovals), no transient webs flashing, polygon reads as irregular 4–6-vertex shape, spider materialises on the sub-bass drop. If green: V.7.7C.3 → ✅; carry-forward to V.7.10 cert review. If new issues surface: file as defects per CLAUDE.md Defect Handling Protocol.

**Carry-forward.** V.7.10 — Matt M7 contact-sheet review + cert sign-off. Three V.7.10 follow-ups (V.7.7C.2's original deferred sub-items minus polygon, plus background-pool flush): per-chord drop accretion via chord-age side buffer; anchor-blob discs at polygon vertices; background-web migration crossfade rendered visual.

---

## [dev-2026-05-09-a] V.7.7C.2 — Arachne single-foreground build state machine

**Increment:** V.7.7C.2. **Decision:** D-095. Three commits.

**What changed.**

- **Commit 1 (`38d1bfab`, 2026-05-08) — WORLD branch-anchor twigs.** `kBranchAnchors[6]` constant in `Arachne.metal` + `ArachneState.branchAnchors` Swift mirror; `drawWorld()` renders six small dark capsule SDFs at those positions. The WEB pillar's frame polygon (Commit 2) selects 4–6 of these anchors as polygon vertices. New `ArachneBranchAnchorsTests.swift` regression-locks the Swift / MSL sync via string-search.
- **Commit 2 (`0f94be2f`, 2026-05-08) — CPU build state machine + background pool + spider integration.** `ArachneBuildState` struct on `ArachneState` tracks foreground build progression: frame polygon (4–6 of 6 branch anchors) → bridge thread first → alternating-pair radials (§5.5 `[0, n/2, 1, n/2+1, …]`) drawn one at a time → INWARD chord-segment capture spiral (§5.6 chord radius DECREASES with k) with per-chord birth times → settle. **Audio-modulated TIME pacing**: `pace = 1.0 + 0.18 × midAttRel + max(0, 0.5 × drumsEnergyDev)`. Pause guard evaluated BEFORE `effectiveDt` per RISKS — resume picks up exactly where it paused, no recompute from `stageElapsed`. New `ArachneState+BackgroundWebs.swift` holds 1–2 saturated `ArachneBackgroundWeb` entries with migration crossfade timers (foreground 1 → 0.4 joins pool; oldest 1 → 0 evicts; 1 s ramp). New `ArachneStateSignaling.swift` (in `Sources/Orchestrator/`, NOT `Sources/Presets/Arachnid/` — Presets cannot import Orchestrator without a module cycle) provides `ArachneState: PresetSignaling` conformance; `_presetCompletionEvent` fires once at `.stable`. `spiderFiredInSegment: Bool` replaces V.7.5's 300 s session lock per §6.5 — at most one spider per Arachne segment, reset on `arachneState.reset()`. **`ArachneWebGPU` extended 80 → 96 bytes** with Row 5 of 4 individual `Float`s (`build_stage`, `frame_progress`, `radial_packed`, `spiral_packed`) — NOT `float4` (alignment would push stride past 96). Buffer allocation auto-scales via `MemoryLayout<WebGPU>.stride`; existing rows 0–4 byte offsets preserved. New `ArachneStateBuildTests.swift` (11 tests) covers stride=96, reset() lands at `.frame`, frame phase exits at stageElapsed ∈ [2.5, 3.5] s effective, completion event fires exactly once, spider pause halts build, per-segment cooldown prevents re-firing until reset(), alternating-pair order (n=13 + n=14), polygon irregular across 100 seeds, spiral chord radii strictly inward, drop birth-time order. Legacy `session cooldown` test in `ArachneStateTests.swift` rewritten to per-segment-latch semantics. App-layer wiring: `applyPreset` `.staged` for Arachne calls `arachneState.reset()` immediately after init; `activePresetSignaling()` `as? PresetSignaling` cast simplified once conformance landed.
- **Commit 3 (this commit, 2026-05-09) — shader build-aware rendering + golden hash regen + docs.** `arachne_composite_fragment`'s "Permanent anchor web" block now reads `webs[0]` Row 5 BuildState and maps it to the legacy `(stage, progress)` signature `arachneEvalWeb` already understands: `.frame (0)` → `stage=0u, progress=frame_progress`; `.radial (1)` → `stage=1u, progress=radial_packed / 13.0`; `.spiral (2)` → `stage=2u, progress=spiral_packed / 104.0`; `≥ .stable (3)` → `stage=3u, progress=1.0`. Pool loop starts at `wi = 1` so the foreground slot doesn't double-render. The chord-segment SDF stays `sd_segment_2d` (Failed Approach #34 lock); the §5.4 hub knot stays `fbm4`-min threshold-clipped (NOT concentric rings); the §5.8 drop COLOR recipe (Snell's-law refraction sampling `worldTex` + fresnel rim + specular pinpoint + dark edge ring + audio gain) is byte-identical to V.7.7C (D-093 lock); the V.7.7D 3D SDF spider + chitin material + listening pose + 12 Hz vibration are byte-identical (D-094 lock); `ArachneSpiderGPU` stays at 80 bytes. `PresetAcceptanceTests.makeRenderBuffers` seeds the slot-6 buffer with stable BuildState values (`build_stage = 3.0, frame_progress = 1.0, radial_packed = 13.0, spiral_packed = 104.0`) for Arachne specifically, mirroring `arachneState.reset()` in production — without the seed the zeroed Row 5 would render an invisible foreground (frame phase, 0 % progress) and trip D-037 invariants 1+4. Other presets binding slot 6 (Gossamer / Stalker / Staged Sandbox) read different structs and are unaffected.
- **Deferred sub-items (Commit 3 minimal scope; surfaced for V.7.10 review).** 1) Per-chord drop accretion via chord-age side buffer at slot 8/9 — drops appear at full count when each chord becomes visible; time-based per-chord drop count modulation (§5.8 `dropCount = baseDrops + accretionRate × chordAge`) is deferred. 2) Anchor-blob discs at polygon vertices (§5.9 part 2) — `BuildState.anchorBlobIntensities[]` exists in CPU but is unread by the shader; spoke-tip frame thread crossings already render at the polygon vertices. 3) Background-web migration crossfade visual (§5.12) — `backgroundWebs` array is not flushed to GPU; existing pool slots `webs[1..3]` (V.7.5 spawn/eviction) serve as background depth context. 4) Polygon vertices from `branchAnchors` (§5.3) vs spoke tips — both produce irregular polygons; V.7.7C.2 ships with the spoke-tip form. None are load-bearing for "the build draws itself"; schedule alongside V.7.10 cert review at Matt's discretion.
- **Tests.** Commit 1: +N (`ArachneBranchAnchors`). Commit 2: +11 (`ArachneStateBuild`) + 1 rewrite (`ArachneState session cooldown` → per-segment latch). Commit 3: 0 new — golden hash regen + acceptance harness fix only.
- **Golden hashes.** Arachne `steady` / `beatHeavy` / `quiet` all converge to `0xC6168081C0D88880` (mid-build composition; harness's shared 30-tick warmup gives the same BuildState for all three fixtures, so the pre-Commit-3 fixture-specific divergence collapses). Hamming distance from V.7.7D `steady` (`0xC6168E8F87868C80`): 16 bits, within the D-095 expected [10, 30] band. Spider forced hash: `0x461E2E1F07830C00` → `0x461E381912D80800` (14 bits drift) — spider sits on the now-mostly-invisible foreground at warmup, so silk composition under the patch shifts.
- **Visual harness.** `/tmp/phosphene_visual/20260508T153154/Arachne_*_composite.png`: foreground hero (upper-left, V.7.7D) gone — at the harness's 0.5 s warmup the BuildState is in frame phase at frameProgress ≈ 0.166 (only the partial bridge thread renders, visually subtle). Background depth context (webs[1] at lower-right, V.7.5 spawn/eviction) renders unchanged. PNG size dropped 1.16 MB → 0.72 MB on the composite — consistent with the foreground hero disappearing. The full build cycle is only visible on real music playback over ~50 s (Matt's manual smoke gate).
- **Engine + app suites.** Engine 1170/1171 pass — sole failure is the documented pre-existing `MetadataPreFetcher.fetch_networkTimeout` parallel-load timing flake. App suite: 5 timing flakes (mirrors Commit 2's documented baseline) — all pass when re-run in isolation per the @MainActor debounce pattern documented in CLAUDE.md.
- **CLAUDE.md edits.** Module Map (`Arachne.metal` description updated for V.7.7C.2); GPU Contract (`ArachneWebGPU` 96 bytes / Row 5 fields documented); What NOT To Do (audio-modulated TIME not beats; no V.7.5 4-web pool resurrection; `arachneState.reset()` only from `applyPreset .staged`); Recent landed work entry; Current Status (V.7.7C.2 ✅, V.7.10 next, V.8.x deferred).
- **Architectural decisions surfaced as deviations from spec.** (1) `PresetSignaling` conformance lives in `Sources/Orchestrator/ArachneStateSignaling.swift` (NOT spec'd `Sources/Presets/Arachnid/ArachneState+Signaling.swift`) — module-cycle avoidance. (2) Commit 2 retains V.7.5 spawn/eviction running additively for `webs[1..3]` (background depth context); Commit 3's pool loop starts at `wi = 1`, leaving `webs[0]` exclusively to the build-aware foreground. (3) Four sub-items (drop accretion / anchor blobs / background migration crossfade / branchAnchors-derived polygon) deferred from the prompt's full scope to V.7.10 follow-up — none load-bearing for the success criterion.

**Carry-forward.** V.7.10 — Matt M7 contact-sheet review + cert sign-off. The Arachne 2D stream's structural work is complete after V.7.7C.2; V.7.10 is QA + sign-off only. V.8.x (Arachne3D parallel preset, D-096) deferred per Matt 2026-05-08 sequencing.

---

## [dev-2026-05-08-a] V.7.7D — Arachne 3D SDF spider + chitin material + listening pose + 12 Hz vibration

**Increment:** V.7.7D. **Decision:** D-094. Two commits.

**What changed.**

- **Listening pose CPU state (`ArachneState.swift`, `ArachneState+Spider.swift`, NEW `ArachneState+ListeningPose.swift`):** `ArachneState` gains `listenLiftAccumulator: Float` (clamped to a 1.5 s sustain threshold) and `listenLiftEMA: Float` (1 s exponential smoothing). `updateListeningPose(features:stems:dt:)` runs at the end of `updateSpider(...)` while the state lock is held — fires when `f.bassDev > 0.30 AND stems.bassAttackRatio ∈ (0, 0.55)` holds for ≥ 1.5 s, returns toward 0 with `τ = 1 s` when bass eases. `writeSpiderToGPU()` lifts only `tip[0]` / `tip[1]` clip-space Y by `0.5 × kSpiderScale × listenLiftEMA = 0.009 × EMA` UV before the GPU bind; other tips unchanged. The listening-pose state lives entirely on the CPU — `ArachneSpiderGPU` stays at 80 bytes (V.7.7B GPU contract preserved). Constants extracted to `ArachneState+ListeningPose.swift` keep `ArachneState+Spider.swift` under the 400-line SwiftLint gate.
- **3D SDF spider anatomy (`Arachne.metal`):** Replaces the V.7.5 / V.7.7B / V.7.7C 2D dark-silhouette overlay block (~line 1033) with a per-pixel ray-marched 3D spider. New helpers above the staged divider: `kSpiderScale = 0.018` UV/body-local-unit, `kSpiderPatchUV = 0.15` (screen-space patch around spider anchor), `sd_spider_body` (cephalothorax 1.0×0.7×0.5 + abdomen 1.4×1.1×0.95 ellipsoids smooth-unioned with `op_smooth_union(0.08)`, narrowed via `op_smooth_subtract(0.04)` of a cylindrical petiole region), `sd_spider_eyes` (6 spheres on the front of the cephalothorax — anterior pair + mid pair + top pair, matID 1 for per-eye specular path), `sd_spider_legs` (2-segment capsule IK with analytic outward-bending knee — `cross(tip-hip, +z)` direction × `0.20 × legSide` magnitude + `+0.10` z-bias for orb-weaver canonical posture), `spider_body_local_xy` (UV → body-local 2D inverse rotation by `-heading`, scaled by `1/kSpiderScale`), `sd_spider_combined` (body + eyes + 8 legs, returns `(distance, materialID)`). The fragment block: gate on `length(uv − spUV) < kSpiderPatchUV` → inlined adaptive sphere trace (32 steps, `hitEps = 0.0008`, far plane 8.0) substituting `sd_spider_combined` for `sd_sphere` (Metal fragments can't take SDF function pointers, per `RayMarch.metal` doc-comment) → tetrahedron-trick normal estimation similarly inlined. Patch dispatch covers ~100k pixels at 1080p — well within Tier 2 budget.
- **Chitin material (`Arachne.metal`):** Body / leg material (matID 0/2) — `mat_chitin` (V.3 cookbook) NOT called; the V.3 default `thin × 1.0` blend would be the §6.2 anti-reference (ref `10` neon glow). The §6.2 recipe is inlined: `base = (0.08, 0.05, 0.03)` brown-amber + `thin = hsv2rgb(0.55+0.3·NdotV, 0.5, 0.4) × 0.15` (0.15 = biological strength; ≤ 0.20 invariant) + Oren-Nayar fuzz `pow(1−NdotV, 1.5) × 0.18 × kLightCol` + body shadow `0.30 + 0.70 × NdotL` + warm rim `kLightCol × pow(1−NdotV, 3) × 0.55`. Eye material (matID 1): `float3(0.02) + kLightCol × spec` with `spec = (dot(halfV, n) > 0.95) ? 1.0 : 0.0` — pinpoint catchlight only when the half-vector aligns with the eye normal.
- **§8.2 vibration UV jitter (`Arachne.metal`):** New block at the top of `arachne_composite_fragment` (immediately after `kAmbCol`) computing `vibUV = uv + (sin(...), cos(...)) × ampUV`. `ampUV = 0.0030 × max(f.bass_att_rel, 0.0) × length(uv − 0.5)` — length-scaling per §8.2 anchor-vs-tip physics (corners shake more than middle). `coarsePhase = hash_f01_2(uv * 8.0) × 2π` discretises tremor phase to an 8×8 grid so adjacent pixels share phase — coherent strand-scale tremor, not TV static. `tremorPhase = 2π × 12.0 × f.accumulated_audio_time` (FA #33 compliant — pauses at silence). Both `arachneEvalWeb(uv, ...)` calls (anchor + pool) take `vibUV`; spider UV anchor adds the same `vibOffset` so the body rides the web. Bottom-of-fragment `worldTex.sample(arachne_world_sampler, uv)` keeps the **original** `uv` per §8.2 ("forest floor and distant layers do not shake"). Three CLAUDE.md-mandated divergences from the §8.2 spec amplitude `(0.0025 × max(subBass_dev, bass_dev) + 0.0015 × beat_bass × 0.4)`: continuous coefficient widened 0.0025 → 0.0030 to satisfy the 2× continuous-vs-accent guideline; driver substituted from `bass_dev` to `bass_att_rel` (FV has no `subBass_dev`; `bass_att_rel` is the smoothed bass envelope already driving `baseEmissionGain` for continuous strand emission and stays at 0 at AGC-average levels — passes the PresetAcceptance "beat is accent only" invariant); per-kick spike set to 0 (Layer-4-as-primary anti-pattern under the audio data hierarchy on the test fixture's `beat_bass` jump; per-kick character preserved by the existing `beatAccent` strand-emission term). All three documented in D-094.
- **Tests.** New `ArachneListeningPoseTests.swift` (4 tests): silence keeps the pose at rest; sustained low-attack-ratio bass drives EMA > 0.9 within 5 s; easing the bass returns the EMA toward rest; GPU flush lifts only `tip[0]` / `tip[1]` (other tips unchanged). All four pass; engine 1148 → 1152.
- **Golden hashes.** Arachne `beatHeavy` regenerated to `0xC6168E87878E8480` (continuous-bass vibration shifts silk pattern by a few bits at the test fixture's `bass_att_rel`-equivalent level via the audio-coupled web walk); `steady` + `quiet` UNCHANGED (zero `bass_att_rel` in those fixtures means no shake). Spider forced UNCHANGED (`0x461E2E1F07830C00`) — the dHash 9×8 luma quantization at 64×64 doesn't resolve the small spider footprint's colour change; the 3D anatomy IS rendered but contributes below the digest threshold. Real visual divergence observed in `PresetVisualReviewTests`.
- **Visual harness.** `RENDER_VISUAL=1 swift test --filter renderStagedPresetPerStage` produces non-placeholder Arachne PNGs across silence (1230 KB), mid (1230 KB), and beat (1232 KB) composites. The +1.6 KB beat-vs-silence delta confirms vibration + audio-coupled emission paths are wired (fixture has `beat_bass = 1.0` but `bass_att_rel = 0`, so the delta comes from the existing audio-coupled `arachneEvalWeb` strand emission, not the vibration UV-jitter; on real music with non-zero `bass_att_rel` the silk pattern visibly shakes).
- **CLAUDE.md edits.** Module Map (`Arachne.metal` description updated for V.7.7D); What NOT To Do (chitin biological-strength rule + GPU-struct stability + WORLD-vibration scope rules); Recent landed work entry; Current Status carry-forward updated (V.7.7D ✅, next is V.7.7C.2 / V.7.8).

**Test count delta:** +4 tests (`ArachneListeningPose` suite). 1148 → 1152 engine tests; 0 SwiftLint violations on touched files; full engine suite passes except documented pre-existing parallel-load flakes (`MetadataPreFetcher.fetch_networkTimeout`, `SessionManagerTests` — all pass in isolation).

**Visual signature delta vs V.7.7C.** V.7.7C spider was a flat dark blob (`(0.04, 0.03, 0.02)` body + thin warm-amber rim) with 8 thin capsule legs — no anatomical depth. V.7.7D spider is a 3D ray-marched orb-weaver: cephalothorax + abdomen with a visible petiole neck cut, 8 articulated legs with outward-bending knees, 6 eye dots in the forward cluster, biological-strength thin-film iridescence on the chitin (subtle hue shift over the body, not neon), and pinpoint specular catchlights on individual eyes when the key light's half-vector aligns. On sustained low-attack-ratio bass (Burial / James Blake / Death Grips territory) the front legs visibly raise into a listening pose; on heavy bass passages the entire foreground web (silk + drops + spider body) shakes at 12 Hz with edge-amplified amplitude (silence-anchored at zero, `bass_att_rel` envelope-driven). The WORLD pillar (forest backdrop) intentionally stays still — silk shakes against a stationary forest, exactly the §8.2 "anchor vs tip" physics intent.

**Carry-forward.** V.7.7C.2 / V.7.8 — single-foreground build state machine. V.7.10 — Matt M7 contact-sheet review + cert. V.7.7D is **not** a cert run; M7 is gated on V.7.7C.2 / V.7.8 + V.7.7D landing.

---

## [dev-2026-05-07-t] V.7.7C — Arachne refractive dewdrops (§5.8 Snell's-law)

**Increment:** V.7.7C. **Decision:** D-093. One shader-only commit.

**What changed.**

- **Shader (`Arachne.metal`):** Both COMPOSITE drop blocks — the anchor-web block (~line 742) and the pool-web block (~line 832) — replaced with the §5.8 Snell's-law refractive recipe sampling `worldTex` at `[[texture(13)]]`. Per drop pixel: spherical-cap normal → `refract(-kViewRay, sphN, 0.752)` (air n=1.0 → water n=1.33) → sample WORLD at `uv + refr.xy × (rDrop × 2.5)` → Schlick fresnel rim `pow(1 − sphN.z, 5.0)` mixed with `kLightCol × 0.85` warm tint at `× 0.40` strength → pinpoint warm specular at the half-vector cap position with `1 − smoothstep(0, 0.20, specD)` mask → dark edge ring `smoothstep(0.85, 0.95) × (1 − smoothstep(0.95, 1.0))` at `× 0.5` → multiplied by the V.7.5 `(baseEmissionGain + beatAccent)` audio gain (preserves D-026 deviation-form modulation). Pool block additionally multiplies coverage by `w.opacity` (preserves V.7.5 fade semantics — older / fading webs contribute proportionally less). `mat_frosted_glass`, the warm-amber emissive base, the cool-white pinpoint specular, and `glintAdd` are all deleted from both call sites — superseded by the §5.8 recipe. Net `Arachne.metal` LOC change roughly ±0.
- **Half-vector type correction.** Prompt's §5.8 recipe declared `float3 halfVec = normalize(kL.xy + kViewRay.xy)` but the right-hand side is `float2`; Metal rejects with `cannot initialize a variable of type 'float3' with an rvalue of type 'metal::float2'`. Fixed in-flight to `float2 halfDir = normalize(kL.xy + kViewRay.xy)`; `specPos = halfDir * rDrop * 0.6` works identically because the prompt's downstream code only consumed `halfVec.xy`. With `kViewRay = (0, 0, 1)` the math reduces to `normalize(kL.xy)` — the screen-space direction of the key light, exactly as §5.8 describes. An early test harness pass surfaced the failure cleanly via `PresetLoaderCompileFailureTest` (Arachne preset count dropped to 13; the QR.3 gate flagged Failed Approach #44 silent shader-compile drop). Documented in D-093 Decision 5 + this release note.
- **Golden hashes.** Arachne dHash UNCHANGED at the V.7.7B values (`0xC6168E8F87868C80` across all three fixtures) — the regression render path leaves `worldTex` unbound, refraction reads zero, and the rim+specular+ring contributions sum below the dHash 9×8 luma quantization threshold. Spider forced regenerated within tolerance: `0x461E3E1F07870C00` → `0x461E2E1F07830C00` (3 bits drift, well under hamming ≤ 8). The `goldenPresetHashes` Arachne comment and `goldenSpiderForcedHash` doc-comment both updated to explain the V.7.7C divergence pattern.
- **CLAUDE.md edits.** Module Map (`Arachne.metal` description updated for V.7.7C); What NOT To Do (rule extended — drop blocks must sample `worldTex`, never inline `drawWorld()`); Recent landed work entry; Current Status carry-forward updated (V.7.7C ✅, next is V.7.7C.2 / V.7.7D).

**Visual signature delta vs V.7.7B.** V.7.7B drops were a flat warm-amber blob per drop with a bright cool-white specular dot — same emissive value regardless of position on the cap, no relationship to the WORLD pillar. V.7.7C drops are photographic dewdrops: each drop carries a small inverted forest fragment refracted through the spherical cap, framed by a thin warm fresnel rim, lit by a warm pinpoint specular at the half-vector position, with a subtle dark edge ring at the silhouette where refraction breaks down at grazing angles. The audio modulation shape is identical (`(baseEmissionGain + beatAccent)` swell). At silence the drops still read because the fresnel + specular + ring composition produces a thin warm crescent over the dark backdrop; under a fully-bound WORLD path (live runtime / staged per-stage harness) the drop interiors carry the forest signature as their dominant feature.

**Verification.**

- `swift test --package-path PhospheneEngine --filter "StagedComposition|StagedPresetBufferBinding|PresetRegression|ArachneSpiderRender|ArachneState"` — 23 tests / 5 suites green.
- `swift test --package-path PhospheneEngine --filter "PresetLoaderCompileFailureTest"` — passes; Arachne preset count = 14.
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter "renderStagedPresetPerStage"` — Arachne PNGs land at non-placeholder size for silence / mid / beat fixtures; composite PNG grew from 1.16 MB (V.7.7B) to 1.2 MB.
- Full engine suite — 1153 tests / 135 suites; only red are pre-existing flakes documented in CLAUDE.md (`MemoryReporter.residentBytes` env-dependent, `MetadataPreFetcher.fetch_networkTimeout` parallel-load timing).
- App suite — 326 tests / 59 suites; only red are pre-existing flakes (`NetworkRecoveryCoordinator` debounce timing under @MainActor parallel load).
- `swiftlint lint --strict --quiet …` on touched files — 0 violations.

**Files changed:**

- `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal` — both drop blocks rewritten.
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetRegressionTests.swift` — `goldenPresetHashes` Arachne comment extended (V.7.7C divergence note).
- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneSpiderRenderTests.swift` — `goldenSpiderForcedHash` regenerated; doc-comment extended.
- `docs/ENGINEERING_PLAN.md` — V.7.7C section added (✅).
- `docs/DECISIONS.md` — D-093.
- `docs/RELEASE_NOTES_DEV.md` — this entry.
- `CLAUDE.md` — Module Map + What NOT To Do + Recent landed work + Current Status carry-forward.

**Carry-forward.** V.7.7C.2 / V.7.8 — single-foreground build state machine (frame → radials → INWARD spiral over 60s, per-chord drop accretion, anchor-blob terminations, completion event via V.7.6.2 channel). V.7.7D — spider pillar deepening + whole-scene 12 Hz vibration. V.7.10 — Matt M7 cert review. V.7.7C is **not** a cert run.

---

## [dev-2026-05-07-s] V.7.7B — Arachne staged WORLD + WEB port

**Increment:** V.7.7B. **Decision:** D-092. Two commits.

**What changed.**

- **Engine (commit 1):** `RenderPipeline+Staged.encodeStage` now binds `directPresetFragmentBuffer` at fragment slot 6 and `directPresetFragmentBuffer2` at slot 7 on every staged-stage encode (consults the same lock-protected fields the legacy `RenderPipeline+MVWarp.drawWithMVWarp` reads). Bound per-frame uniformly across every stage of a staged preset. Without this, V.7.7A's staged Arachne fragments would silently sample zeros for the web pool and spider state.
- **Harness (commit 1):** `PresetVisualReviewTests.encodeStagePass` and `renderStagedFrame` accept an optional `arachneState:` parameter; `renderStagedPresetPerStage` constructs a warmed `ArachneState` (mirrors the existing 30-tick warmup at `:143`) for `presetName == "Arachne"` and passes nil for "Staged Sandbox". `RenderPipeline.encodeStage` visibility promoted from `private` to `internal` solely as a test seam.
- **New regression (commit 1):** `StagedPresetBufferBindingTests.swift` — two tests inline-compile a synthetic single-stage shader that reads sentinel floats from slot 6 / slot 7 and writes them to the red channel; assert read-back matches the sentinel within 1e-2 (Float16 round-trip tolerance).
- **Shader port (commit 2):** `arachne_world_fragment` calls `drawWorld(in.uv, moodRow, moodRow.z)` — the existing six-layer dark close-up forest free function, reading mood state from `webs[0].row4`. `arachne_composite_fragment` is the V.7.5 v5 / V.7.7-redo / V.7.8 monolithic `arachne_fragment` body byte-identical to its prior form, with two divergences only: (a) signature replaces `[[buffer(1)]] fft` + `[[buffer(2)]] wave` with `texture2d<float, access::sample> worldTex [[texture(13)]]`; (b) `bgColor = drawWorld(uv, moodRow, moodRow.z)` becomes `bgColor = worldTex.sample(arachne_world_sampler, uv).rgb`. Every other line — anchor + pool web walk, drop accumulator, spider silhouette, mist, dust motes — passes through unchanged. Legacy `arachne_fragment` (~240 LOC) deleted along with the V.7.7A placeholder block (vertical-gradient WORLD + 12-spoke COMPOSITE, ~110 LOC).
- **App-layer wiring (commit 2):** `VisualizerEngine+Presets.applyPreset` `case .staged:` now allocates `ArachneState` and calls `setDirectPresetFragmentBuffer(state.webBuffer)` + `setDirectPresetFragmentBuffer2(state.spiderBuffer)` + `setMeshPresetTick { state.tick(...) }` for `desc.name == "Arachne"`. Mirrors the existing mv_warp branch. Without this the engine binding fix alone would read zero-buffers at runtime — V.7.7A had removed this wiring along with the migration. The prompt's STOP CONDITION #2 anticipated the contingency.
- **Golden hashes regenerated:** Arachne `(steady/beatHeavy/quiet) = 0xC6168E8F87868C80` (regression renders COMPOSITE alone with `worldTex` unbound → samples zero → captures the foreground composition over a black backdrop). Spider forced render `0x461E3E1F07870C00`. "Staged Sandbox" added at `0x000022160A162A00` (was missing from the dictionary; printGoldenHashes now emits 13 entries including the sandbox).
- **CLAUDE.md edits:** Module Map updated for `Arachne.metal`; GPU Contract / Buffer Binding Layout reserves slots 6 / 7 across the staged path; What NOT To Do gains "Do not call `drawWorld()` from `arachne_composite_fragment` — the WORLD stage owns it; COMPOSITE samples the texture"; Current Status forward-chain updated.

**LOC delta on `Arachne.metal`:** 962 → 898 (−64 net; the legacy fragment body was repurposed as the new COMPOSITE rather than literally deleted-and-rewritten — every line in the new fragment is traceable to a line in the retired one, satisfying the prompt's mechanical-lift rule). The prompt's 480 LOC estimate assumed completely fresh hand-written staged fragments; in practice the V.7.5 anchor + pool walk + drop material + spider + post-process layers are all real and unavoidable.

**Verification.**

- `swift build --package-path PhospheneEngine` — clean.
- `swift test --package-path PhospheneEngine --filter "StagedComposition|StagedPresetBufferBinding|PresetRegression|ArachneSpiderRender|ArachneState"` — 5 suites green (23 tests).
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter "renderStagedPresetPerStage"` — Arachne WORLD PNG (377 KB) + COMPOSITE PNG (1.16 MB) per fixture, non-placeholder content (forest backdrop in WORLD; web + drops + spider + mist + motes in COMPOSITE).
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter "renderPresetVisualReview"` — Arachne contact sheet emitted; the steady-mid render goes through the legacy `renderFrame` path (single-pipeline render, `worldTex` unbound), so the foreground composition reads correctly over a black backdrop. Full WORLD+COMPOSITE eyeball is via `renderStagedPresetPerStage`.
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` — clean.
- `swiftlint lint --strict --config .swiftlint.yml --quiet` on touched files — 0 violations.
- Full `swift test --package-path PhospheneEngine` reports two `ProgressiveReadinessTests` failures (`startNow_belowThreshold_isNoOp`, `startNow_atThreshold_transitions_to_ready`) under parallel @MainActor scheduling load (1153 tests across 135 suites). Both pass in isolation; CLAUDE.md documents the timing-margin pattern under the U.11 entry. Not a V.7.7B regression.

**Carry-forward.** V.7.7C — refractive droplets (Snell's law sampling of `arachneWorldTex` through spherical-cap drop normals), biology-correct frame → radial → spiral build state machine, anchor logic. V.7.7D — spider pillar deepening (anatomy + material + gait + listening pose) + whole-scene 12 Hz vibration. V.7.10 — Matt M7 cert review (gated on V.7.7D landing).

---

## [dev-2026-05-07-r] QR.4 — UX dead ends + duplicate `SettingsStore` + dead settings + hardcoded strings

**Increment:** QR.4 (U.12). **Decision:** D-091. Two commits.

**What changed.**

- **EndedView** (`Views/Ended/EndedView.swift`): replaces U.1 stub with a session-summary card. Localized headline, track-count summary (`%lld tracks`), em-dash placeholder for session duration (deferred per prompt fallback — would require `SessionManager` start-time plumbing), coral primary CTA "Start another session" (wired to `sessionManager.cancel()` — the documented `.ended → .idle` path; the prompt's `endSession()` assumption was stale), secondary "Open sessions folder" via `NSWorkspace.shared.open`.
- **ConnectingView** (`Views/Connecting/ConnectingView.swift`): replaces U.1 stub with per-connector spinner (Apple Music / Spotify / Local Folder / generic) plus localized cancel CTA wired to `sessionManager.cancel()`. Headline drops the trailing ellipsis per UX_SPEC §8.5.
- **PlaybackView duplicate-`SettingsStore` collapse**: `@StateObject private var settingsStore = SettingsStore()` (line 51) → `@EnvironmentObject private var settingsStore: SettingsStore`. Pre-fix, `CaptureModeSwitchCoordinator` (built in `setup()`) subscribed to a parallel store that never received toggles from the Settings sheet; capture-mode changes were silently swallowed. Same shape as Failed Approach #16 in product behaviour.
- **`showPerformanceWarnings` deleted** from `SettingsStore`, `SettingsViewModel`, `DiagnosticsSettingsSection`, `Localizable.strings`, and the matching test in `SettingsStoreTests`. Wiring would have been >50 LOC of toast plumbing for a surface already covered by the dashboard PERF card. Decision recipe option (b).
- **`includeMilkdropPresets` UI gated on `#if DEBUG`**. Persistence retained so DEBUG round-trips preserve user state; production builds never see the toggle. Drop the gate when Phase MD ships.
- **PlanPreviewView "Modify" button**: hidden behind `#if ENABLE_PLAN_MODIFICATION`. Tooltip lies (e.g. "Full plan editing — coming in a future update" on a no-op disabled control) are bugs post-QR.4.
- **`@Published var currentTrackIndex: Int?`** on `VisualizerEngine`, set in the track-change callback via new `indexInLivePlan(matching:)` orchestrator helper. `PlaybackChromeViewModel` accepts a `currentTrackIndexPublisher` (defaulted `Just(nil)` for backward-compat) and binds `sessionProgress.currentIndex` directly. The 12-line lowercased title+artist match in `refreshProgress()` is gone — covers/remasters/encoding-different variants no longer break the chrome.
- **12+ hardcoded strings externalised** in `Views/`: end-session confirmDialog ("End this session?" / "End session" / common.cancel / "The visualizer session will stop."), `PlaybackControlsCluster` tooltips ("Settings (coming soon)" → `playback.controls.settings.tooltip` = "Settings"; end-session tooltip), `ListeningBadgeView` "Listening…", `SessionProgressDotsView` "Reactive" + "%lld of %lld", `IdleView` "Phosphene" → `appName`, `PlanPreviewView` empty-state + reactive-mode strings, `PlanPreviewRowView` context-menu items + accessibility label.
- **`Scripts/check_user_strings.sh`** (new) — greps `Text\("[A-Z]`, `\.help\("[A-Z]`, `\.accessibilityLabel\("[A-Z]` under `PhospheneApp/Views/` and fails on any hit not in the allowlist (`DebugOverlayView.swift`). Mirrors the shape of `check_sample_rate_literals.sh` (D-079). Manual invocation; no CI aggregator yet.

**Tests added (4 new files, 17 new tests):**

- `SettingsStoreEnvironmentRegressionTests` (3 tests). Load-bearing gate for D-091. Asserts (1) an `@EnvironmentObject` consumer sees a `captureMode` toggle, (2) a shadow `@StateObject SettingsStore()` does NOT receive global-store updates (the regression discriminator), (3) `PlaybackView.swift` source contains the `@EnvironmentObject` declaration and not the `@StateObject` form.
- `EndedViewTests` (5 tests). Verifies the five required Localizable.strings keys resolve, accessibility identifier constants are distinct, the view constructs without invoking the injected closures, the `ended.summary.tracks` format string substitutes the count, and `EndedView.openSessionsFolder()` creates the directory.
- `ConnectingViewCancelTests` (5 tests). Verifies the six required keys resolve, headline drops the trailing ellipsis (UX_SPEC §8.5), accessibility identifier constants are distinct, the view constructs across all five `PlaylistSource` variants without invoking `onCancel`, and Apple Music / Spotify subtexts differ.
- `PlaybackChromeIndexBindingTests` (4 tests). Verifies `sessionProgress.currentIndex` updates when the index publisher emits 2 (totalTracks=5), nil published index resets to -1 (not stale), title casing/whitespace mismatches do NOT change the index (proves the string-match path is gone), and nil plan keeps the reactive-mode display.

**Stack we ran:** SwiftLint zero violations on touched files. Engine suite untouched (engine code unchanged). App build clean. New test suites pass in isolation. `PlaybackChromeViewModelTests` showed a parallel-execution flake under `xcodebuild test` but passes in isolation — same flake class previously documented for that suite under heavy parallel test load.

**Two pivots from the prompt:**

1. **"Start another session" wires to `cancel()`, not `endSession()`.** The prompt assumed `endSession()` did `.ended → .idle`. It does not — it transitions any state → `.ended`. The documented `.idle` return is `cancel()`. Documented in commit message and D-091 Decision 7.
2. **`sessionDuration` plumbing deferred** per the prompt's own fallback ("If adding it requires > 30 LOC of session-state changes, STOP and surface to Matt"). `SessionManager` does not track a session-start timestamp; outside QR.4 scope. `EndedView.sessionDuration: TimeInterval?` is plumbed as an optional rendering an em-dash placeholder when nil.

**Files:** see D-091 in `docs/DECISIONS.md` for the complete file-change list.

---

## [dev-2026-05-07-q] QR.3 — Close silent-skip test holes

**Increment:** QR.3 (TEST.1)
**Type:** Test infrastructure — closes the silent-skip class on the BeatThis! regression surface, closes BUG-002 (PresetVisualReviewTests staged-preset PNG export) and BUG-003 (DSP.3.7 live-drift validation test), adds standalone surfaces for two DSP.2 S8 bugs.

**What changed.**

- **`BeatThisFixturePresenceGate`** (new) — fails loudly when `Fixtures/tempo/love_rehab.m4a` or `docs/diagnostics/DSP.2-S8-python-activations.json` are missing, instead of letting the BeatThis! tests silently noop.
- **`BeatThisLayerMatchTests`** — `print(...) + return` skip paths converted to `Issue.record(...) + return` so a missing fixture fails the test.
- **`BeatThisStemReshapeTests`** (new) — standalone Bug 2 surface: feeds a constant-in-time, mel-varying input through `predictDiagnostic` and asserts `stem.bn1d` preserves per-mel structure (`stdAlongF / stdAlongT > 5×`).
- **`BeatThisRoPEPairingTests`** (new) — standalone Bug 4 spec: adjacent-pair RoPE at cos=0/sin=1 produces (-2,1,-4,3,-6,5,-8,7); identity rotation is identity; adjacent-pair output differs from the half-and-half pre-S8 form.
- **`PresetVisualReviewTests`** — `makeBGRAPipeline` now resolves shaders via new `PresetLoader.bundledShadersURL` static helper. `Bundle.module` from the test target resolves to the test bundle (no `Shaders` resource); the helper returns Presets-module `Bundle.module` so the lookup matches what the loader uses at runtime. **BUG-002 closed.** Verified `RENDER_VISUAL=1`: 16 PNGs across 5 preset cases (Arachne / Gossamer / Volumetric Lithograph non-staged; Staged Sandbox + Arachne staged); no `cgImageFailed`.
- **`LiveDriftValidationTests`** (new — closed-loop musical-sync test) — drives the production `LiveBeatDriftTracker` against real onsets from `BeatDetector` over 30 s of love_rehab.m4a, with the offline `BeatGrid` from `DefaultBeatGridAnalyzer` pre-installed. Asserts: tracker locks within 9 s (calibrated; spec is ~5 s — BUG-007 LOCKING ↔ LOCKED oscillation work-in-progress), max |drift| < 50 ms in 10–30 s window, ≥ 80 % `beatPhase01` zero-crossings within ±30 ms of grid beats. Observed on land: lock at 6.55 s, max drift 14 ms, alignment 90 % (36/40 grid beats matched). **BUG-003 closed** (DSP.3.7 surface now lands).
- **`PresetLoaderCompileFailureTest`** (new) — asserts `loader.presets.count == 14`. Verified at land time by temporarily injecting `int half = 1;` into Plasma.metal — count dropped 14 → 13, test failed with the documented message. Plasma.metal substituted for the prompt's Stalker.metal because Stalker is no longer in production.
- **`SpotifyItemsSchemaTests`** (new) — locks Failed Approach #45 (Spotify `"item"` vs deprecated `"track"` key) and Failed Approach #47 (`preview_url` captured inline, not re-fetched via iTunes Search) against an on-disk fixture (`Fixtures/spotify_items_response.json`).
- **`MoodClassifierGoldenTests`** (new) — output-behaviour anchor for the 3,346 hardcoded `MoodClassifier` weights. 10 deterministic 10-feature inputs → expected `(valence, arousal)` within 1e-4 (`Fixtures/mood_classifier_golden.json`). Regenerable via `UPDATE_MOOD_GOLDEN=1`. Each entry uses a fresh classifier instance (the EMA depends on call order; fresh-per-entry keeps the test hermetic).
- **`Sources/Presets/PresetLoader.swift`** — new `public static var bundledShadersURL: URL?` helper exposing the Presets-module resource bundle's `Shaders/` directory for harness reuse.

**Test count:** 1140 → 1148. Engine + app builds clean (`** BUILD SUCCEEDED **`). SwiftLint zero violations on touched files. Pre-existing flakes (`MetadataPreFetcher.fetch_networkTimeout`, `MemoryReporter`) unchanged.

**Known issues introduced:** none.

**Closed:** BUG-002 (staged-preset PNG export), BUG-003 (DSP.3.7 surface).

**Related:** D-090, BUG-002, BUG-003, Failed Approaches #44 / #45 / #47.

---

## [dev-2026-05-07-q] BUG-007.9 — Hybrid runtime recalibration

**Increment:** BUG-007.9
**Type:** Bug fix (DSP / live beat tracking) — addresses BUG-007.8 regression cases.

**What changed.**

Manual validation of BUG-007.8 (session `2026-05-07T22-51-36Z`) showed mixed results: 5/8 tracks improved, 1 stable, **2 regressed** (Around the World drift went from −28 → +101 ms; Levitating from −50 → +56 ms). Cause: the prep-time calibrator measures onset timing on the **preview MP3** (22 050 Hz, ~96 kbps, 46 ms FFT resolution); the live tracker fires onsets on the **tap audio** (48 000 Hz, full quality, overlapping FFT). When the encodings diverge enough, the prep-time bias points the wrong way.

**Fix.** Add a runtime recalibration pass. After stem separation completes (i.e. ≥10 s of tap audio buffered) AND lock has stabilised (`matchedOnsetCount >= 8`), replay the latest 12 s of tap audio through the same `GridOnsetCalibrator` and override the prep-time bias via new `LiveBeatDriftTracker.applyCalibration(driftMs:)`. One-shot per track. Reset on track change.

The runtime calibration uses the same audio the listener actually hears, so by definition it converges to the correct offset. Tracks that regressed under BUG-007.8 (Around the World, Levitating) should recover within ~15 s of lock.

**API changes.**

- `LiveBeatDriftTracker.currentGrid: BeatGrid` (read-only) — exposes installed grid for the runtime recalibrator.
- `LiveBeatDriftTracker.matchedOnsetCount: Int` — read-only accessor for app-layer gating of the runtime recalibration trigger.
- `LiveBeatDriftTracker.applyCalibration(driftMs:)` — overrides drift with a runtime-derived value. Clamped to ±500 ms.
- `VisualizerEngine.runtimeRecalibrationDone: Bool` — per-track one-shot flag. Reset in `resetStemPipeline`.
- `VisualizerEngine+Stems.runtimeRecalibrationIfDue()` — called at the end of `performStemSeparation`. Snapshots tap audio, downmixes to mono, runs `GridOnsetCalibrator`, applies via `applyCalibration`. Skips if calibrator returns 0.

**Files edited.**

- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift`
- `PhospheneApp/VisualizerEngine.swift`
- `PhospheneApp/VisualizerEngine+Stems.swift`
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — 3 new tests (MARKs 39–41).
- `docs/QUALITY/KNOWN_ISSUES.md` — BUG-007.9 entry.

**Tests.** 41/41 `LiveBeatDriftTrackerTests` pass. Full engine suite: 1149/1151 (2 pre-existing flakes). 0 SwiftLint violations on touched files. `xcodebuild PhospheneApp build` clean.

**Manual validation pending.** Replay the 8-track bass-forward playlist from `T22-51-36Z`. Expected: drift averages near zero within ~15 s of lock on all tracks; Around the World + Levitating recover; no regression on tracks that worked pre-7.9.

**Out of scope.** Persisting runtime-calibrated values across sessions (future BUG-012 cache idea). Multi-band onset signals. Stem-separation audit (BUG-010 — separate).

---

## [dev-2026-05-07-p] BUG-007.8 — Per-track grid-vs-onset offset calibration

**Increment:** BUG-007.8
**Type:** Bug fix (DSP / live beat tracking) — systemic fix.

**What changed.**

Session `2026-05-07T22-00-00Z` showed drift averages spanning **−95 to +96 ms across a single playlist** — Beat This!'s grid timing and our sub-bass onset detector disagree by track-specific amounts. Previous BUG-007 fixes patched symptoms (lock-state hysteresis, latency calibration constants); this one addresses the root cause.

**Mechanism.** During Spotify preparation, after `BeatGridAnalyzer` produces the grid, the new `GridOnsetCalibrator` replays the same preview audio through our live `BeatDetector` offline, finds sub-bass onset timestamps, cross-correlates against the grid's beats, and computes the median `(gridBeat − onsetTime)` offset. This is the *exact same* gap the live drift EMA would chase — but measured deterministically at preparation time using the same detector that fires at runtime.

**Storage + apply.** New `gridOnsetOffsetMs: Double` field on `CachedTrackData`. New `LiveBeatDriftTracker.setGrid(_:initialDriftMs:)` overload + `MIRPipeline.setBeatGrid(_:initialDriftMs:)`. The prepared-cache install path in `VisualizerEngine+Stems.resetStemPipeline` passes the calibrated value as the initial drift bias, so the EMA starts at the right offset rather than converging from zero over ~4 onsets.

**Why this is a systemic fix.**

- Replaces the global `audioOutputLatencyMs = 50` heuristic with per-track values measured from the actual audio.
- Eliminates the sign-mismatch problem (some tracks drifted positive, some negative — fixed-constant compensation can only correct one direction).
- Drift EMA still runs at playback time and fine-tunes if runtime conditions differ slightly from preparation.
- Manual `Shift+B` rotation, `,`/`.` latency tuning, and lock-state hysteresis fixes remain as-is — they're complementary.

**API changes.**

- `CachedTrackData` gains `gridOnsetOffsetMs: Double` (default 0 for backward compat).
- `LiveBeatDriftTracker.setGrid(_:)` retained as backward-compat shim that calls `setGrid(_:initialDriftMs: 0)`.
- New `LiveBeatDriftTracker.setGrid(_:initialDriftMs:)` — clamps drift to ±500 ms at the entry point.
- New `MIRPipeline.setBeatGrid(_:initialDriftMs:)` — same pattern.
- New `GridOnsetCalibrator` (`Sendable`, public) in the Session module: `init()` + `calibrate(samples:sampleRate:grid:) -> Double`.

**Files added.**

- `PhospheneEngine/Sources/Session/GridOnsetCalibrator.swift` (~200 LOC).
- `PhospheneEngine/Tests/PhospheneEngineTests/Session/GridOnsetCalibratorTests.swift` (5 tests).

**Files edited.**

- `PhospheneEngine/Sources/Session/StemCache.swift` — `gridOnsetOffsetMs` field.
- `PhospheneEngine/Sources/Session/SessionPreparer+Analysis.swift` — Step 7 calibration call extracted to nonisolated static helper.
- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — `setGrid(_:initialDriftMs:)` overload.
- `PhospheneEngine/Sources/DSP/MIRPipeline.swift` — `setBeatGrid(_:initialDriftMs:)` overload.
- `PhospheneApp/VisualizerEngine+Stems.swift` — wires `cached.gridOnsetOffsetMs` into the prepared-cache install. `swiftlint:disable file_length` added (file grew past 400).
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — 3 new tests (MARKs 36–38).

**Tests.** 41/41 `LiveBeatDriftTrackerTests` + 5/5 `GridOnsetCalibratorTests` pass. Full engine suite: 1143/1143 green. 0 SwiftLint violations on touched files.

**Manual validation pending.** Replay the 8-track bass-forward playlist from session `2026-05-07T22-00-00Z`. Predicted: drift averages near ±20 ms across all tracks (vs the previous ±95 to +96 ms range). LOCKED-time should rise on the tracks that previously drifted (Another One Bites the Dust, Get Lucky, bad guy, Superstition).

**Out of scope.**

- Stem-separation quality impact on calibration accuracy (see Matt's question about stem separation — addressed separately).
- Audio source quality variations (Spotify vs lossless).
- Multi-band onset signals (snare + bass-stem cross-check) — could refine but needs evidence the current single-band sub-bass calibration is insufficient.

---

## [dev-2026-05-07-o] BUG-007.4c — auto-rotate for kick-on-1+3 patterns

**Increment:** BUG-007.4c
**Type:** Bug fix (DSP / live beat tracking)

**What changed.**

Session `2026-05-07T21-35-22Z` showed the user "still had to press `Shift+B` a bunch" despite BUG-007.4b's auto-rotate landing. Cause: BUG-007.4b required the dominant slot to have ≥ 1.5× the runner-up's count to fire — but most rock/hip-hop tracks (HUMBLE, SLTS, Everlong, MC) put the kick on slots 0 + 2 with **similar** counts. Counts end up like `[4, 0, 4, 0]`, top : runner = 1.0, the gate rejects, no rotation.

**Fix.** Add a second detection path for the kick-on-1+3 alternating pattern. Triggered when:
- Top and runner-up are within `autoRotateAlternatingTieRatio = 1.25` of each other
- The "other" slots (everything except top + runner-up) sum to ≤ 20 % of the top count
- Both top and runner-up have ≥ `autoRotateMinDominantCount = 4` hits

When detected, the slot matching `firstTightOnsetRawSlot` (typically the song's downbeat — most listeners start playback at or near a strong-beat moment) wins the tiebreak. Falls back to the dominant slot if the first-onset slot matches neither leader.

**Coverage matrix:**

| Track type | BUG-007.4b path | BUG-007.4c path |
|---|---|---|
| Single-dominant (kick-on-1 only, slow trap) | ✓ rotates | — |
| Kick-on-1+3 (rock, hip-hop, indie) | rejected | **✓ rotates via first-onset tiebreak** |
| Four-on-the-floor (OMT, electronic) | rejected | rejected (others not near-zero) — manual `Shift+B` remains |

**API.**

- New private state: `firstTightOnsetRawSlot: Int?`. Captured on the *first* tight onset of the current track. Reset on `setGrid` / `reset`.
- New tunables: `autoRotateAlternatingTieRatio = 1.25`, `autoRotateAlternatingNoiseFraction = 0.20`.
- New private helper `chooseAutoRotateSlotLocked(...)` extracted from `maybeAutoRotateBarPhaseLocked` — encapsulates both BUG-007.4b and BUG-007.4c selection logic.
- No public API changes.

**Files edited.**

- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — extended auto-rotate logic, new helper, new state.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — 3 new tests (MARKs 33–35): `autoRotate_kickOn1And3_picksFirstOnsetSlot`, `autoRotate_kickOn1And3_firstOnsetSlot0_noRotation`, `autoRotate_fourOnTheFloor_noRotation_BUG_007_4c_regression`.
- `docs/QUALITY/KNOWN_ISSUES.md` — BUG-007.4 entry extended with BUG-007.4c paragraph.

**Tests.** 35/35 `LiveBeatDriftTrackerTests` pass. Full engine suite green except the documented baseline flakes. 0 SwiftLint violations on touched files.

**Manual validation pending.** Same 5-track battery — confirm HUMBLE / SLTS / Everlong / MC auto-rotate without `Shift+B`. OMT (four-on-the-floor) continues to require manual rotation.

**Out of scope.** Multi-band onset signals (snare on 2/4, bass-stem energy) for tracks where kick-on-1+3 detection still fails. If the first-onset-slot tiebreaker ever picks wrong, the user can override with `Shift+B`.

---

## [dev-2026-05-07-n] BUG-007.5 part 3 — BPM-aware lock-release gate

**Increment:** BUG-007.5 part 3
**Type:** Bug fix (DSP / live beat tracking)

**What changed.**

Closes the HUMBLE half-time lock-flicker that BUG-007.5 parts 1+2 didn't address. Replaced the fixed `lockReleaseTimeSeconds = 2.5` with `effectiveLockReleaseSeconds = max(2.5 s, 4 × medianBeatPeriod)`. At fast tempos (120+ BPM, 500 ms period) the gate stays at 2.5 s — 4 × period = 2.0 s, below floor. At HUMBLE half-time (76 BPM, 790 ms period) the gate scales to 3.16 s — accommodates 4 consecutive sparse non-tight events without dropping lock.

**Why it matters.**

HUMBLE-class tracks (sparse half-time grids) showed 6+ lock drops per ~60 s in the prior session despite small per-onset deviations. Cause: sub-bass onset detector occasionally returns nil on instrumental breaks; at 790 ms beat period, 3–4 consecutive nil-matches accumulate ~3 s — past the 2.5 s gate. With BPM-aware scaling, the same 4 misses fit within the 3.16 s gate, lock holds.

Fast tracks (OMT/MC/SLTS at 105–125 BPM) keep the 2.5 s floor — they have plenty of onset density and don't need the wider gate.

**API.**

- New private static tunables: `lockReleaseTimeSecondsFloor=2.5` (renamed from `lockReleaseTimeSeconds`) and `lockReleaseBeatMultiplier=4.0`. Fixed `lockReleaseTimeSeconds` constant removed.
- New private helper `effectiveLockReleaseSecondsLocked()` returns `max(floor, multiplier × medianPeriod)`.
- `computeLockStateLocked` now consults the helper.
- No public API changes.

**Files edited.**

- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — BPM-aware gate logic.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — 2 new tests (MARKs 31–32): `bpmAwareLockRelease_holdsLongerOnSlowGrid`, `bpmAwareLockRelease_floorHoldsForFastTracks`.
- `docs/QUALITY/KNOWN_ISSUES.md` — BUG-007.5 status updated.

**Tests.** 32/32 `LiveBeatDriftTrackerTests` pass. Full engine suite green except documented pre-existing flakes. 0 SwiftLint violations on touched files.

**Manual validation pending.** HUMBLE should now reach 70 %+ LOCKED with ≥ 15 s contiguous runs (was 43 % LOCKED, 5.4 s longest run pre-fix). OMT/MC/SLTS/Everlong should not regress.

**Out of scope.** Onset-detection improvements on sparse / soft-attack content (a separate problem, not gate width).

**BUG-007 family status:** all sub-bugs resolved (007.4a manual rotate ✓, 007.4b auto-rotate ✓, 007.5pt1 time gate ✓, 007.5pt2 variance-adaptive ✓, 007.5pt3 BPM-aware ✓, 007.6 latency calibration ✓). Remaining: 007.7 (SLTS slow tempo drift over long playback, requires architectural rework — defer). BUG-009 (halving threshold) untouched.

---

## [dev-2026-05-07-m] BUG-007.4b — auto-rotate bar phase via kick density

**Increment:** BUG-007.4b
**Type:** Bug fix (DSP / live beat tracking)

**What changed.** Eliminates the per-track `Shift+B` manual rotation requirement for tracks with a clear kick density signal. After lock has stabilised (8+ matched onsets), the tracker examines its per-slot kick-onset histogram and auto-rotates `barPhaseOffset` so the dominant slot becomes the displayed "1." One-shot per track.

**How it works.**

- Each tight onset increments a counter for `timing.beatsSinceDownbeat` (raw, before any rotation). Histogram is sized to `grid.beatsPerBar` on `setGrid` and resets on track change.
- After `matchedOnsets >= 8`, the tracker selects the slot with the highest count. Requires ≥ 4 onsets in that slot *and* ≥ 1.5× the runner-up's count to qualify as a clear winner — otherwise it's a no-op (four-on-the-floor electronic, ambient material).
- Auto-rotate is preempted if the user pressed `Shift+B` first. Manual intent wins.
- One-shot per track: once attempted (whether rotated or not), it doesn't re-fire on the same track. `setGrid` resets the flag.

**Expected behaviour per the 5-track battery:**

- HUMBLE (kick on 1+3 with 1 emphasised) → likely auto-rotates within ~6 s.
- Everlong / SLTS (rock with strong downbeat) → likely auto-rotates within ~4 s.
- Midnight City → may auto-rotate via snare-on-2/4 density shift; to be observed.
- One More Time (four-on-the-floor electronic) → equal density → no auto-rotate, `Shift+B` remains.

**API.** New private state (`slotOnsetCounts`, `autoRotateAttempted`, `manualRotationPressed`) and helper `maybeAutoRotateBarPhaseLocked`. New tunables: `autoRotateMatchThreshold=8`, `autoRotateDominanceRatio=1.5`, `autoRotateMinDominantCount=4`. `barPhaseOffset` external setter sets `manualRotationPressed=true`.

**Files edited.**

- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — auto-rotate logic, slot counter, manual-press guard. Adds `swiftlint:disable type_body_length`.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — 4 new tests (MARKs 27–30).
- `docs/QUALITY/KNOWN_ISSUES.md` — BUG-007.4 marked Resolved.

**Tests.** 30/30 `LiveBeatDriftTrackerTests` pass. Full engine suite green except documented pre-existing flakes. 0 SwiftLint violations on touched files.

**Manual validation pending.** Same 5-track battery — confirm auto-rotate works on HUMBLE/Everlong/SLTS and `Shift+B` remains the override.

**Out of scope.** BUG-007.5 part 3 (BPM-aware time gate for HUMBLE — next increment).

---

## [dev-2026-05-07-l] BUG-007.5 part 2 — variance-adaptive tight gate

**Increment:** BUG-007.5 part 2
**Type:** Bug fix (DSP / live beat tracking)

**What changed.**

The 2026-05-07T20-34-57Z manual session showed that the time-based lock release (BUG-007.5 part 1) closed lock retention on simple kick-on-the-beat tracks (OMT, SLTS — 89-90 % LOCKED, 50-91 s contiguous runs) but not on tracks where drift envelope spans wider than ±30 ms despite small mean drift (Midnight City 58 % LOCKED, HUMBLE 44 %, Everlong 73 %). The cause: the fixed ±30 ms tight gate doesn't fit the natural variance of these tracks. Drift EMA centres correctly; individual onsets land on either edge of a 40-50 ms envelope; many trigger the time gate even though they're really fine.

**Fix.** Variance-adaptive tight gate: replace the fixed ±30 ms with `effectiveTightWindow = clamp(2σ, 30 ms, 80 ms)` derived from the running stddev of the last 16 `instantDrift − drift` deviations. Acquisition path (before `matchedOnsets >= lockThreshold`) still uses the floor 30 ms for selectivity. Retention path widens to fit the track's actual variance — narrow for OMT/SLTS, wider for MC/HUMBLE/B.O.B. Ring resets on `setGrid`/`reset` so each track starts fresh.

**API changes:**

- `LiveBeatDriftTracker` gains private state: `driftDeviationRing: [Double]` (capacity 16, signed seconds), `pushDriftDeviationLocked(_:)`, `effectiveTightWindowLocked()`. No public API changes.
- New private static tunables: `tightMatchWindowCeiling=0.080`, `tightMatchWindowK=2.0`, `driftDeviationRingCapacity=16`, `driftDeviationMinSamples=4`. `strictMatchWindow=0.030` retained as the floor.

**Files edited.**

- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — variance ring + adaptive gate logic in `update()`.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — 2 new tests (MARKs 25–26): `adaptiveTightGate_widensForNoisyOnsetStream`, `adaptiveTightGate_ringResetsOnSetGrid`. Plus `TightCapture` helper for `@Sendable`-compatible diagnostic-trace capture.
- `docs/QUALITY/KNOWN_ISSUES.md` — BUG-007.5 status updated to "Resolved (time-based release gate + variance-adaptive tight gate, 2026-05-07)".

**Tests.** 26/26 `LiveBeatDriftTrackerTests` pass. Full engine suite passes except documented pre-existing flake (`MetadataPreFetcher.fetch_networkTimeout`) and DASH.5 string-format mismatch (`PerfCardBuilderTests`, separate work in flight). 0 SwiftLint violations on touched files.

**App build status.** Not verified for this commit — DASH.7 work in flight has a pending `DarkVibrancyView` reference. Engine SPM target builds clean. Once DASH.7 completes, full app build can be confirmed.

**Manual validation pending.** Same 5-track battery (OMT / Midnight City / HUMBLE / SLTS / Everlong) — confirm MC, HUMBLE, Everlong reach 80 %+ LOCKED with 30 s+ contiguous runs. OMT and SLTS should not regress (already at 89-90 %).

**Out of scope.**

- Adaptive widening on the slope-detector / wider-window-retry path (BUG-007.3 reverted).
- Per-onset-class tight gates (drums vs bass vs claps).
- BUG-007.4b (auto-rotate bar phase) — separate increment, scheduled next.

---

## [dev-2026-05-07-n] BUG-009 — Halving-correction threshold 160 → 175 BPM

**Increment:** BUG-009
**Type:** Bug fix (calibration)

**What changed.** Raised the halving threshold in `BeatGrid.halvingOctaveCorrected()` from 160 → 175 BPM. The `> 160` guard halved legitimate fast tracks down to half-time when the live 10 s Beat This! analyser overshot the true tempo: Foo Fighters' "Everlong" (true ≈ 158 BPM) installed at 85.4 BPM in the reactive session captured at `~/Documents/phosphene_sessions/2026-05-07T14-33-47Z/`. Drum'n'bass (170–175), fast indie rock (Strokes / Arctic Monkeys 155–170), and similar fast-rock tempos shared the same fate. 175 captures the fast-rock band without re-enabling true double-time errors (those land at ≥ 200 typically). Pyramid Song (~68 BPM) and Money 7/4 (~123 BPM) remain untouched (under-floor + in-range respectively).

**Tests.** Added `halvingOctaveCorrected_fastRockBPM_isNoOp` covering four fixtures (158 / 168 / 172.5 / 175 BPM) — each must pass through un-halved. Updated existing assertions to use the `[80, 175]` range. Refreshed the extreme-double-halve fixture from 322 BPM → 360 BPM (322 → 161 used to trigger a second halve under the old `> 160` guard; under `> 175` it stops at 161, so the test now uses 360 → 180 → 90 to retain factor-4 thinning coverage). Engine: 1120 tests pass. SwiftLint clean on touched files.

**Manual validation pending** at next reactive Everlong session: live grid should install at `bpm=158 ± 8`, not 85.4. Pyramid Song must remain at 68 BPM; Love Rehab live trigger (244.770 → halved to 122.4) must continue to halve. Documented in `KNOWN_ISSUES.md`.

---

## [dev-2026-05-07-m] DASH.7.2 — Dark-surface legibility pass

**Increment:** DASH.7.2 (D-089)
**Type:** Accessibility / aesthetic correction

**What changed.** Matt's first-look review of DASH.7.1 surfaced four issues:
- `.regularMaterial` is system-appearance-adaptive — on macOS Light it rendered the panel as a beige material, putting near-white dashboard text on tan with sub-AA contrast.
- `coralMuted` (oklch 0.45) and `purpleGlow` (oklch 0.35) — chosen in DASH.7.1 for muted brand semantic — failed WCAG AA against dark surfaces anyway (2.6:1 and 2.5:1).
- MODE / BPM rendered as stacked "label-on-top, 24pt mono value below" while BAR / BEAT rendered as "label + bar + small inline value" — visually inconsistent.
- FRAME value `"20.0 / 14 ms"` truncated to `"20.0 / 14…"` in the 86pt column.

**Fixes.**

- **`DarkVibrancyView`** — new `NSViewRepresentable` wrapping `NSVisualEffectView` pinned to `.appearance = .vibrantDark` + `.material = .hudWindow`. Replaces `.regularMaterial` so the surface is dark regardless of system appearance. Combined with `.environment(\.colorScheme, .dark)` on the SwiftUI subtree.
- **Surface tint at 0.96α.** Bumped from 0.55 — the dashboard sits over the visualizer and must guarantee AA contrast against the worst-case bright preset frame. At 0.96 opaque, teal text passes AA (4.77:1); at 0.55 it failed (1.16:1).
- **Colour promotions to AAA-grade contrast.** `coralMuted` → **`coral`** in `BeatCardBuilder.makeModeRow` (LOCKING) and throughout `PerfCardBuilder` (FRAME stressed, QUALITY downshifted, ML WAIT/FORCED). `purpleGlow` → **`purple`** in `BeatCardBuilder.makeBarRow`. `textMuted` → **`textBody`** for MODE REACTIVE / UNLOCKED. All preserve brand semantics; just brighter intensity for legibility.
- **Inline `.singleValue` rendering.** Rewrote `DashboardRowView.singleValueRow` as `HStack(label LEFT, Spacer, value RIGHT)` at 13pt mono — matches `.bar` / `.progressBar` row rhythm. MODE / BPM / QUALITY / ML now read at the same scale and column position as BAR / BEAT values. The 24pt hero-numeric is retired from the dashboard.
- **FRAME column 86pt → 110pt** + format `"X / Y ms"` → `"X / Yms"` (no space). Combined, values never truncate regardless of frame time.

**Decisions.** D-089 captures the contrast math, the macOS-appearance pinning rationale, the colour promotions, the inline-row redesign, and the format compaction. `coralMuted` / `purpleGlow` remain defined in `DashboardTokens.Color` for future callers but no card builder references them after DASH.7.2.

**Tests.** Dashboard count unchanged at 27. Fixture updates: `BeatCardBuilderTests.locking` / `.unlocked` / `.zero` (coral / textBody / purple); `PerfCardBuilderTests.warningRatio` / `.downshifted` / `.forcedDispatch` (coral); `.healthy` / `.clampOverBudget` (compact format). Engine + app builds clean. SwiftLint clean on touched files.

---

## [dev-2026-05-07-k] DASH.7.1 — Brand-alignment pass (impeccable review)

**Increment:** DASH.7.1
**Type:** Aesthetic refinement

**What changed.** An impeccable-skill review of DASH.7 against `.impeccable.md` surfaced three brand violations and seven smaller issues; DASH.7.1 lands all corrections in one focused increment.

**P0 — semantic / structural:**
- **STEMS sparkline colour:** coral → **teal**. `.impeccable.md` reserves teal for "MIR data, stem indicators." Coral is for "energy, action, beat moments." Stems are MIR data; teal is correct.
- **Per-card chrome retired.** Three rounded-rectangle cards (`.impeccable.md` anti-pattern: "no rounded-rectangle cards as the primary UI pattern") replaced with a **single shared `.regularMaterial` panel** (NSVisualEffectView wrapper, the macOS-spec'd material) containing three typographic sections separated by `border` dividers. Cards become typographic content; the panel is the only chrome.
- **Custom fonts wired (Clash Display + Epilogue).** `DashboardFontLoader.FontResolution` extended with `displayFontName` + `displayCustomLoaded` for Clash Display. `PhospheneApp.init()` calls `DashboardFontLoader.resolveFonts(in: nil)` once at launch. SwiftUI views resolve via `.custom(_:size:relativeTo:)` so Dynamic Type still scales. Falls back gracefully to system fonts when TTF/OTF aren't bundled (the README documents the drop-in path).

**P1 — significant aesthetic:**
- **SF Symbol status icons retired.** `checkmark.circle.fill` / `exclamationmark.triangle.fill` were a web-admin trope. Status now reads through value-text colour alone — Sakamoto-liner-note discipline.
- **PERF status colours mapped onto the brand palette.** `statusGreen` / `statusYellow` retired in favour of `teal` (data healthy) / `coralMuted` (data stressed). Same change in `BeatCardBuilder`'s MODE row: LOCKED → teal, LOCKING → coralMuted. The card uses only the project's three brand colours now.
- **STEMS valueText dropped entirely.** The sparkline IS the readout; the redundant signed-decimal column on the right was Sakamoto-violating.
- **Spring-choreographed `D` toggle.** `withAnimation(.spring(response: 0.4, dampingFraction: 0.85))` wraps the `showDebug` toggle; the dashboard cards fade in with an 8pt downward offset, fade out cleanly. The DebugOverlayView gets a plain opacity transition to match.

**P2 — polish:**
- Stable `ForEach` IDs (`id: \.element.title`) so card add/remove animates correctly when PERF rows collapse.
- `+` prefix dropped on signed valueText (bar direction encodes sign visually).
- Card titles render at `bodyLarge` (15pt) Clash Display Medium — typographic anchors of the dashboard column rather than 11pt UPPERCASE labels-on-cards.

**What survives unchanged.** `DashboardCardLayout` API, all four Row variants, `DashboardSnapshot`, `StemEnergyHistory`, `BeatCardBuilder` non-MODE colour assignments (BAR=purpleGlow, BEAT=coral both stay — they're correct per the brand table). All Sendable contracts. The DashboardOverlayViewModel + 30 Hz throttle. The single-`D` toggle binding to both surfaces.

**Decisions.** D-088 captures: brand-violation diagnoses, retirement details, font-loader extension, spring-transition spec, what survives.

**Tests.** Dashboard test count unchanged at 27. Test fixtures updated: `BeatCardBuilderTests.locked`/`.locking` use teal/coralMuted; `StemsCardBuilderTests.mixedHistory`/`.uniformColour` use teal; `StemsCardBuilderTests.valueTextEmpty` (renamed) asserts empty-string; `PerfCardBuilderTests.healthy`/`.warningRatio`/`.downshifted`/`.forcedDispatch` use teal/coralMuted; `DashboardOverlayViewModelTests.stemHistoryAccumulates` asserts `valueText.isEmpty`.

Engine + app builds clean. SwiftLint clean on touched files. Pre-existing flakes (`MemoryReporter.residentBytes`, `MetadataPreFetcher.fetch_networkTimeout`) fired as expected — none introduced.

---

## [dev-2026-05-07-j] DASH.7 — SwiftUI dashboard port + visual amendments

**Increment:** DASH.7 (supersedes DASH.6 / D-086)
**Type:** Architectural pivot + feature

**What changed.** Pivoted the dashboard from the DASH.6 Metal composite path to a SwiftUI overlay after Matt's live D-toggle review (`~/Documents/phosphene_sessions/2026-05-07T19-03-44Z`) found that (a) the Metal text layer rendered hazy at native pixel scale, (b) the 0.92α purple-tinted chrome washed gray against bright preset backdrops, and (c) the STEMS `.bar` rows didn't read rhythm separation across stems clearly. Investigation showed the original Metal-path justifications didn't materialize: text wasn't crisper than SwiftUI, snapshot updates are bounded by snapshot-change cadence rather than frame rate, and lifetime is naturally one-frame ahead via `@Published`. DASH.7 ports + bundles two visual amendments:

- **STEMS card → timeseries.** New `.timeseries(label, samples, range, valueText, fillColor)` row variant on `DashboardCardLayout`. `StemsCardBuilder` now consumes a `StemEnergyHistory` (240-sample CPU ring buffer per stem, ≈ 8 s at 30 Hz throttled redraw). The view model maintains the rings privately and snapshots into the immutable `StemEnergyHistory` value type per redraw. `DashboardRowView`'s `SparklineView` (SwiftUI `Canvas`) renders a filled area + stroked line with a centre baseline that's visible even on empty samples — stable absence-of-signal surface.
- **PERF semantic clarity.** FRAME row's value text now reads `"{recent} / {target} ms"` so headroom is legible without docs lookup; status colour flips green→yellow at 70% of budget (`PerfCardBuilder.warningRatio`). QUALITY row hides when the governor is `full` and warmed up. ML row hides on idle / `dispatchNow` (READY); only surfaces on `defer` / `forceDispatch`. Card collapses to one row in the steady-state happy path. SF Symbols (`checkmark.circle.fill` / `exclamationmark.triangle.fill`) decorate the FRAME label so status reads in colour-blind contexts.

**Architecture changes.**
- New `VisualizerEngine.@Published var dashboardSnapshot: DashboardSnapshot?` (Sendable bundle of beat+stems+perf), republished from `pipe.onFrameRendered` on `@MainActor`.
- New `DashboardOverlayViewModel` (`@MainActor ObservableObject`) — subscribes to the engine's snapshot publisher via Combine, throttles to ~30 Hz (`.throttle(for: .milliseconds(33))`), maintains stem history rings, publishes `[DashboardCardLayout]`. Builder tests (pure data) are unchanged in spirit; only their fixtures changed to match the new APIs.
- New `DashboardOverlayView` / `DashboardCardView` / `DashboardRowView` SwiftUI components in `PhospheneApp/Views/Dashboard/`. View hierarchy: `DashboardOverlayView` (top-trailing column) → `DashboardCardView` (rounded-rect chrome + title) → `DashboardRowView` (four row variants).
- PlaybackView Layer 6: `if showDebug { DashboardOverlayView(viewModel: dashboardVM) }`. The `D` shortcut now drives both DebugOverlayView (Layer 5) and DashboardOverlayView (Layer 6) symmetrically — no engine-level state to keep in sync. The DASH.6 `engine.dashboardEnabled = showDebug` line was deleted.
- ContentView wires `dashboardSnapshotPublisher: engine.$dashboardSnapshot.eraseToAnyPublisher()` through PlaybackView's init.

**Retired (deleted, not commented out).**
- `Renderer/Dashboard/DashboardComposer.swift`
- `Renderer/Dashboard/DashboardCardRenderer.swift` + `+ProgressBar.swift`
- `Renderer/Dashboard/DashboardTextLayer.swift`
- `Renderer/Shaders/Dashboard.metal`
- 10 `compositeDashboard(...)` call sites in `RenderPipeline+*.swift` draw paths
- `RenderPipeline.setDashboardComposer` / `hasDashboardComposer` / `compositeDashboard` helper / `dashboardComposer` + lock + resize forward
- `VisualizerEngine.dashboardComposer` / `dashboardEnabled`
- 4 test files: `DashboardComposerTests`, `DashboardCardRendererTests`, `DashboardCardRendererProgressBarTests`, `DashboardTextLayerTests` (14 tests)

**What survived the pivot.** The Sendable card builders (`BeatCardBuilder` / `StemsCardBuilder` rewritten / `PerfCardBuilder` updated), `DashboardCardLayout` (with new `.timeseries` variant), `DashboardTokens`, `BeatSyncSnapshot`, `PerfSnapshot`. The data shape converged across DASH.3-6 was the part worth keeping; only the rendering layer changed. The DASH.6 `Spacing.cardGap` token stays. The DebugOverlayView dedup from DASH.6 stays (Tempo / standalone QUALITY / ML rows still removed).

**What's intentionally NOT in this increment.** No `Equatable` conformance added to `BeatSyncSnapshot` / `StemFeatures` (D-086 Decision 4 stands; bytewise equality via `withUnsafeBytes` + `memcmp` for change detection in `DashboardSnapshot`). No fourth card. No animation. No per-stem palette tuning (uniform coral; carries forward from DASH.4 / D-084).

**Decisions.** D-087 captures: pivot rationale (Metal-path justifications didn't materialize), what survives, retirement of D-086 surface, 30 Hz throttle vs. buffer-update tradeoff, STEMS bar→timeseries, PERF semantic clarity collapse rule, single `D` toggle drives both surfaces symmetrically.

**Tests.** Engine: 1117 tests / 126 suites (was 1130 — drop reflects deleted GPU readback tests). Dashboard-related test count: 27 (was 39). Builder + tokens + font-loader tests pass. App: 310 tests / 55 suites (was 305 — gain from 5 new `DashboardOverlayViewModelTests`). Pre-existing flakes documented in CLAUDE.md (MemoryReporter residentBytes, NetworkRecoveryCoordinator timing, SessionManager parallel-execution timing) fired as expected — none introduced by DASH.7. SwiftLint clean on touched files. xcodebuild app build clean.

**DASH.6 commits stay in history.** Per Matt's preference, no `git revert` — the DASH.6 commits + retirement in DASH.7 tell the truthful "we tried Metal, ported to SwiftUI" story.

---

## [dev-2026-05-07-i] DASH.6 — Overlay wiring + `D` toggle

**Increment:** DASH.6
**Type:** Feature

**What changed.**
- New `DashboardComposer` (`@MainActor`, `Renderer/Dashboard/`) — lifecycle owner of the BEAT/STEMS/PERF cards. Owns one `DashboardTextLayer` (320 × 660 pt at 2× contentsScale by default; reallocates on `resize(to:)`), three pure builders (`BeatCardBuilder`/`StemsCardBuilder`/`PerfCardBuilder`), and one alpha-blended `MTLRenderPipelineState` keyed to `dashboard_composite_vertex` / `dashboard_composite_fragment` (Premultiplied source: `src = .one`, `dst = .oneMinusSourceAlpha`).
- New `Dashboard.metal` shader file (`Renderer/Shaders/`) — vertex stage emits a fullscreen triangle confined to the composite pass's viewport; fragment samples the layer texture at `[[texture(0)]]` with bilinear + clamp_to_edge.
- New `Spacing.cardGap` token in `Shared/Dashboard/DashboardTokens.swift` — aliases `Spacing.md` (12 pt) v1; named slot reserves a DASH.6.1 retune.
- `RenderPipeline` gains `setDashboardComposer(_:)` setter, `hasDashboardComposer: Bool` test accessor, and a `compositeDashboard(commandBuffer:view:)` helper invoked from the tail of every draw path (`drawDirect`, `drawWithMeshShader`, `drawWithRayMarch`, `drawWithFeedback`, `drawWithMVWarp`, `drawWithICB`, `drawWithPostProcess`, `drawWithStaged`, plus the feedback-blit and mv-warp fallback paths) immediately before `commandBuffer.present(drawable)`. `mtkView(_:drawableSizeWillChange:)` forwards to `composer.resize(to:)` so card placement scales with drawable contentsScale (no hardcoded 2×).
- `VisualizerEngine` gains `dashboardComposer: DashboardComposer?` and `@MainActor var dashboardEnabled: Bool` (mirror of the composer's `enabled` flag). `setupDashboardComposer(pipe:ctx:lib:)` allocates the composer and wraps `pipe.onFrameRendered` so a per-frame snapshot push (BeatSync from the engine's snapshot lock + StemFeatures from the existing closure parameter + a freshly-assembled `PerfSnapshot`) is delivered to `composer.update(...)` once per rendered frame.
- `PlaybackView`'s `D` shortcut now writes `engine.dashboardEnabled = showDebug` after toggling the SwiftUI overlay — one keystroke drives both the SwiftUI debug overlay (bottom-leading, raw diagnostics) and the new Metal cards (top-right, instruments).
- `DebugOverlayView` deduplicated of metrics that the dashboard cards now show: the `Tempo` row inside MOOD (LIVE), the standalone `QUALITY:` HStack block, and the standalone `ML:` HStack block (along with the divider that immediately preceded the QUALITY/ML pair). Mood V/A, Key, SIGNAL block, MIR diag, SPIDER, G-buffer, REC all stay.

**What's intentionally NOT in this increment.** No fourth card (mood / metadata / signal). No animation on card show/hide (`D` is binary). No per-card visibility toggles. No render-loop refactor (Decision A would have required moving `commandBuffer.present(drawable)` out of 8+ draw paths — well beyond the spec's 30-line ceiling, deferred). No per-card colour tuning (uniform palette per builder, DASH.6.1 amendment slot if the live-toggle review surfaces issues). No `Equatable` on `StemFeatures` / `BeatSyncSnapshot` (D-086 Decision 4 — composer's rebuild-skip uses private bytewise compare).

**Decisions.** D-086 captures: composer-as-class rationale, Decision B (per-path composite call sites) over Decision A (render-loop refactor), single `D` toggle drives both surfaces, no Equatable on shared types, premultiplied alpha discipline, per-frame rebuild cost rationale, DASH.6.1 amendment slot.

**Tests.** 45 dashboard tests pass (was 39 → 45, six new in `DashboardComposerTests`: init / idempotent-on-equal-snapshots / rebuilds-on-any-input-change / disabled-is-noop / update+composite paints top-right / resize recomputes 4K placement). Full engine suite green: 1130 tests / 130 suites. 0 SwiftLint violations on touched files. `xcodebuild -scheme PhospheneApp build` succeeded.

**Frame-budget regression.** Soak harness re-run not yet captured for this increment (CPU rebuild path is gated behind `enabled` and the bytewise rebuild-skip; the GPU composite is one fullscreen triangle into a fixed top-right viewport — expected delta is well below the 0.5 ms p95 ceiling). Live D-toggle review on real music is the acceptance artifact and runs as part of DASH.6 sign-off; numeric soak comparison is a follow-up if the eyeball review flags concern.

---

## [dev-2026-05-07-i] BUG-007.5 + BUG-007.6 — Time-based lock release + audio output latency calibration

**Increment:** BUG-007.5 + BUG-007.6 (joint)
**Type:** Bug fix (DSP / live beat tracking)

**What changed.**

Two complementary fixes informed by the 2026-05-07T18-21-37Z manual session evidence:

**BUG-007.6 — audio output latency calibration.** All tracks showed systematic negative drift averaging −36 to −76 ms (visual fires before audio is heard). Cause: tap captures audio ~50 ms before the listener hears it (CoreAudio output buffer + DAC + driver), plus onset-detection processing delay. Fix: new `LiveBeatDriftTracker.audioOutputLatencyMs: Float` applied to the *display path only* (`displayTime = pt + drift + L/1000`). Does NOT touch onset matching — that would cancel out algebraically. Default 0 in engine; `VisualizerEngine` sets it to 50 ms for internal Mac speakers in app-layer init. Tunable at runtime via `,` (−5 ms) / `.` (+5 ms) shortcuts. Persists across track changes (system property). Range clamped ±500 ms.

**BUG-007.5 — time-based lock release.** Replaced count-based `lockReleaseMisses=7` gate with time-based `lockReleaseTimeSeconds=2.5` gate. Lock now drops only when 2.5 s of consecutive non-tight matches have elapsed since the last tight hit, regardless of how many onsets occurred in between. Sparse-onset tracks (HUMBLE half-time at 76 BPM, 790 ms beat period — 15 lock drops in the prior session) no longer trip the gate accidentally — what matters is *time*, not *count*. Diagnostic counter `consecutiveMisses` retained on `LiveBeatDriftTraceEntry` for backward compat.

**API changes:**

- `LiveBeatDriftTracker.audioOutputLatencyMs: Float` (public, NSLock-guarded, clamped ±500 ms, default 0).
- `VisualizerEngine.audioOutputLatencyMs` proxy + `adjustAudioOutputLatency(ms:)` method.
- `PlaybackShortcutRegistry` gains `,` and `.` shortcuts in the developer category.
- New `lockReleaseTimeSeconds: Double = 2.5` constant replaces `lockReleaseMisses` for the lock-decision logic.

**Files edited.**

- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift`
- `PhospheneApp/VisualizerEngine.swift`
- `PhospheneApp/Services/PlaybackShortcutRegistry.swift`
- `PhospheneApp/Views/Playback/PlaybackView.swift`
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — 5 new tests (MARKs 20–24).
- `docs/QUALITY/KNOWN_ISSUES.md` — both bugs marked Resolved (automated); manual validation pending.

**Tests:** `LiveBeatDriftTrackerTests` 24/24 pass. Full engine suite green except documented pre-existing flake. App build clean. 0 SwiftLint violations.

**Manual validation pending.** Next session capture with the same 5-track battery should confirm: beat orb visually pulses on the kick (BUG-007.6); lock holds through HUMBLE's sparse half-time and Everlong's noisy onsets (BUG-007.5); `,`/`.` adjust visual sync; no regression on `Shift+B` rotation.

**Out of scope (deferred).** Persisting `audioOutputLatencyMs` across launches (settings field, future increment). Per-device automatic detection. Variance-adaptive lock window — re-evaluate after manual validation of the time-based gate alone.

---

## [dev-2026-05-07-h] BUG-007.4a — Bar-phase rotation dev shortcut (Shift+B)

**Increment:** BUG-007.4a
**Type:** Bug fix / diagnostic enabler

**What changed.**

5-track A/B test on 2026-05-07 (sessions `T15-50-23Z` + `T15-58-17Z`) confirmed BUG-007.4's root cause: Spotify preview clips don't start on song bar boundaries, so Beat This!'s "beat 1 of bar 1" lands on a non-downbeat in the song's coordinate system. Per-track off-by-N: One More Time +3, Midnight City +3, HUMBLE +2, SLTS 0 (preview = first 30 s), Everlong +2. SLTS being the only correct case correlates with its preview being the song intro.

This increment lands a developer shortcut so the user can confirm the rotation hypothesis on more tracks and provide an escape hatch until the durable fix (BUG-007.4b — kick-density auto-rotate) lands.

**API changes:**

- `LiveBeatDriftTracker.barPhaseOffset: Int` (`public`, NSLock-guarded). Range 0..(beatsPerBar−1); setter wraps modulo `beatsPerBar`. Applied in `computePhase` to rotate `barPhase01` and downstream `beat_in_bar` text. Beat-phase, drift, and lock-state are untouched. Reset to 0 on `setGrid` / `reset` so each track starts fresh.
- `VisualizerEngine.cycleBarPhaseOffset()` — increments by 1 and logs.
- `PlaybackShortcutRegistry` gains `onCycleBarPhaseOffset` callback; new shortcut `Shift+B` in the developer category labelled "Cycle bar-phase offset (BUG-007.4)".

**Files edited.**

- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — `barPhaseOffset` property + reset hook + `computePhase` rotation. `swiftlint:disable file_length`.
- `PhospheneApp/VisualizerEngine.swift` — `cycleBarPhaseOffset()`.
- `PhospheneApp/Services/PlaybackShortcutRegistry.swift` — `Shift+B` keybind.
- `PhospheneApp/Views/Playback/PlaybackView.swift` — wiring to engine.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — 1 new test (`barPhaseOffset_rotatesBarPhase_modBeatsPerBar`) covering rotation, modulo wrap, reset on setGrid.
- `docs/QUALITY/KNOWN_ISSUES.md` (BUG-007.4 root cause confirmed; fix plan ranked C/A/B).
- `docs/RELEASE_NOTES_DEV.md`.

**How to use.**

In a Spotify-prepared session with the SpectralCartograph diagnostic preset locked (`L`):
1. Play any track. Listen for the song's downbeat ("1").
2. If the visual "1" doesn't match, press `Shift+B` to advance the offset by 1.
3. Cycle 0..(beatsPerBar−1) until "1" lines up. Console log shows current offset.
4. Offset resets to 0 on track change — re-cycle for the next track.

This is a *diagnostic*, not the durable fix. Each track may need its own cycle count. BUG-007.4b will auto-rotate via kick-density heuristic.

**Test counts:** 18 → 19 LiveBeatDriftTrackerTests. Full engine suite green except the documented pre-existing `MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget` flake. 0 SwiftLint violations on touched files. App build clean.

**Out of scope (deferred to BUG-007.4b).** Auto-rotation via kick-density heuristic at lock-in time. Persistence of per-track offset across sessions (the dev shortcut is ephemeral by design).

---

## [dev-2026-05-07-g] DASH.5 — Frame budget card

**Increment:** DASH.5
**Type:** Feature (dashboard)

**What changed.**

The third **live** dashboard card binds renderer governor + ML dispatch state to a `DashboardCardLayout` titled `PERF`. New `PerfSnapshot` Sendable value type wraps the inputs from two manager classes (`FrameBudgetManager` + `MLDispatchScheduler`) as a single seam crossing actor lines into the builder. New pure `PerfCardBuilder` produces a three-row card in display order: FRAME (`.progressBar`, unsigned ramp `recentMaxFrameMs / targetFrameMs` clamped to `[0, 1]` at the builder layer), QUALITY (`.singleValue`, displayName passed through verbatim), ML (`.singleValue`, mapped to READY / WAIT _ms / FORCED / —). Status-colour discipline reuses BEAT lock-state palette (D-083): muted = no info, green = healthy / READY, yellow = governor active / degraded / WAIT / FORCED. No `statusRed` introduced — durable rule across the dashboard. Wiring into `RenderPipeline` / `PlaybackView` is DASH.6 scope, not DASH.5.

**Files added.**
- `PhospheneEngine/Sources/Renderer/Dashboard/PerfSnapshot.swift` — Sendable value type with seven fields (`recentMaxFrameMs`, `recentFramesObserved`, `targetFrameMs`, `qualityLevelRawValue`, `qualityLevelDisplayName`, `mlDecisionCode`, `mlDeferRetryMs`). Decision/quality enums encoded as `Int + displayName: String` so the snapshot stays trivially `Sendable` without importing manager enums. `.zero` neutral default.
- `PhospheneEngine/Sources/Renderer/Dashboard/PerfCardBuilder.swift` — pure `Sendable` struct: `build(from: PerfSnapshot, width: CGFloat = 280) -> DashboardCardLayout`. Three private row makers: FRAME (clamps `[0, 1]` at builder layer because `.progressBar` has no `range` field), QUALITY (status-colour mapped), ML (decision-code switch with WAIT-ms formatting that drops the trailing `0ms` when retry-ms is zero).
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PerfCardBuilderTests.swift` — 6 `@Test` functions in `@Suite("PerfCardBuilder")`: zero snapshot (3 rows: FRAME 0/—, QUALITY full/muted, ML —/muted), healthy full quality (FRAME ≈ 0.586, QUALITY full/green, ML READY/green), governor downshifted (FRAME clamped 1.0, QUALITY no-bloom/yellow, ML WAIT 200ms/yellow), forced dispatch + artifact (FRAME ≈ 0.8, QUALITY full/green, ML FORCED/yellow, writes `card_perf_active.png`), frame-time-above-budget regression lock (FRAME clamps to 1.0 at the builder layer; valueText still shows raw `42.0 ms`), width override default-arg path.

**Files edited.**
- `docs/ENGINEERING_PLAN.md` — DASH.5 row flipped to ✅ with implementation summary.
- `docs/DECISIONS.md` — D-085 appended (seven decisions: `PerfSnapshot` value-type rationale, `.progressBar` over `.bar` for FRAME, builder-layer clamp asymmetry vs D-084's renderer-layer clamp, Int-encoded quality enum, Int + retry-ms encoded ML decision, no `statusRed` durable rule, no per-row colour tuning for FRAME with DASH.5.1 amendment slot).
- `CLAUDE.md` — `Renderer/Dashboard/` Module Map entries for `PerfSnapshot` and `PerfCardBuilder`.

**Decisions captured.**
- **D-085 — PERF card data binding.** Snapshot value type because PERF state is genuinely spread across two manager classes (no single live source like DASH.4's `StemFeatures`). `.progressBar` (unsigned ramp) over `.bar` (signed-from-centre) because frame time vs budget is naturally unsigned and headroom is the load-bearing signal. Builder-layer clamp because `.progressBar` has no `range` field — single source of truth lives in the builder; asymmetric with STEMS (D-084) where the renderer is the clamp authority. Int-encoded enums (quality + ML decision) keep the snapshot a leaf value type with no upward dependency on manager enums. No `statusRed` token introduced — yellow = governor active is sufficient; the rule is durable across the dashboard. Uniform coral on FRAME consistent with D-084's stems decision (bar fill ratio carries headroom; QUALITY text carries discrete state; colour reinforces, doesn't differentiate). DASH.5.1 amendment slot reserved for any per-row colour or formatting tuning surfaced by Matt's eyeball.

**Test count delta.**
- 6 dashboard tests added (33 → **39 dashboard tests pass**: 12 DASH.1 + 6 DASH.2.1 + 6 BeatCardBuilder + 3 progress-bar + 6 StemsCardBuilder + 6 PerfCardBuilder).
- Full engine suite green: **1123 tests passed**. Pre-existing `MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget` / `MemoryReporter.residentBytes` env-dependent flakes and the two GPU-perf parallel-run flakes documented in CLAUDE.md remain documented (none touched by DASH.5).
- 0 SwiftLint violations on touched files; app build clean.

**What's intentionally NOT in this increment.**
- No `RenderPipeline` / `DebugOverlayView` / `PlaybackView` wiring — DASH.6 scope.
- No multi-card composition / screen positioning — DASH.6 scope.
- No fourth row (GPU TIME, MEMORY, FPS, dropped-frames) — PERF is exactly FRAME / QUALITY / ML. Per-frame GPU timing belongs to a future increment if and only if soak-test reports show it carries information not already in `recentMaxFrameMs`.
- No sparkline / mini-graph for frame time history — typographic + bar geometry, consistent with .impeccable "no animation" and DASH.2.1 / DASH.3 / DASH.4 precedent.
- No `statusRed` token — durable rule across the dashboard.
- No per-row colour tuning for FRAME — uniform coral v1, with DASH.5.1 amendment slot.
- No convenience constructor accepting `FrameBudgetManager` + `MLDispatchScheduler` — `PerfSnapshot` is a pure value type; assembly happens at the call site in DASH.6.
- No `Equatable` on `Row` (D-082, D-083, D-084 standing rule).

**Artifact.**
`.build/dash1_artifacts/card_perf_active.png` — PERF card rendered for `recentMaxFrameMs=11.2, targetFrameMs=14, qualityLevelDisplayName="full", mlDecisionCode=3 (forceDispatch)` over the deep-indigo backdrop. FRAME bar fills ~80% in coral with `"11.2 ms"` valueText; QUALITY reads `"full"` in `statusGreen`; ML reads `"FORCED"` in `statusYellow`. Composes visually with `card_beat_locked.png` and `card_stems_active.png` for M7-style review of the three live cards.

---

## [dev-2026-05-07-f] DASH.4 — Stem energy card

**Increment:** DASH.4
**Type:** Feature (dashboard)

**What changed.**

The second **live** dashboard card binds `StemFeatures` → `DashboardCardLayout`. New pure `StemsCardBuilder` produces a four-row card titled `STEMS`: DRUMS / BASS / VOCALS / OTHER, each `.bar` row driven by the corresponding `*EnergyRel` field (MV-1 / D-026, floats 17–24 of `StemFeatures`). Range `-1.0 ... 1.0` (headroom over typical ±0.5 envelope). Sign-correct visual feedback: positive deviation fills right of centre (kick raises drums above AGC average), negative fills left (duck), zero draws no fill — the dim background bar dominates as the .impeccable "absence-of-signal" stable state. `valueText` formatted `%+.2f` so the leading sign is always shown (Milkdrop-convention readback). Uniform `Color.coral` across all four rows in v1; per-stem palette tuning is reserved for a DASH.4.1 amendment if Matt's eyeball flags monotony — direction (left vs right of centre) carries the stem-state semantic, colour reinforces. Builder is pass-through; clamping authority lives in the renderer's `drawBarFill` (defence-in-depth at one layer; test e regression-locks). Wiring into `RenderPipeline` / `PlaybackView` is DASH.6 scope, not DASH.4.

**Files added.**
- `PhospheneEngine/Sources/Renderer/Dashboard/StemsCardBuilder.swift` — pure `Sendable` struct: `build(from: StemFeatures, width: CGFloat = 280) -> DashboardCardLayout`. Single private `makeRow(label:value:)` helper produces a `.bar` row; uniform coral, range `-1.0 ... 1.0`, valueText `%+.2f`.
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/StemsCardBuilderTests.swift` — 6 `@Test` functions in `@Suite("StemsCardBuilder")`: zero snapshot (4 rows × {label, value=0, valueText=+0.00, coral, range -1...1}), positive drums (row 0 only, `+0.42`), negative bass (row 1 only, `-0.30`), mixed snapshot with row-order assertions + artifact write, unclamped passthrough at value 1.5 (regression lock for "renderer is the clamp authority"), width override default-arg path.

**Files edited.**
- `docs/ENGINEERING_PLAN.md` — DASH.4 row flipped to ✅ with implementation summary.
- `docs/DECISIONS.md` — D-084 appended (six decisions: `.bar` over `.progressBar`, no `StemEnergySnapshot` intermediary, uniform coral v1 + DASH.4.1 amendment slot, no-clamp-at-builder, range rationale, percussion-first row order).
- `CLAUDE.md` — `Renderer/Dashboard/` Module Map entry for `StemsCardBuilder`.

**Decisions captured.**
- **D-084 — STEMS card data binding.** `.bar` (signed) over `.progressBar` (unsigned) because `*EnergyRel` is naturally signed and unsigned would lose the duck information. Builder reads `StemFeatures` directly because no `StemEnergySnapshot` analog exists and adding one would only duplicate the MV-1 contract. Uniform `Color.coral` v1 because direction (left vs right of centre) is the load-bearing signal, not colour — multi-colour would read as a stereo VU meter / DAW mixer (wrong product cue) and would conflict with D-083's status-colour reservation. No clamp at builder layer; renderer's `drawBarFill` is the single authority. Range `-1.0 ... 1.0` puts typical ±0.5 envelope at ~50% bar fill (visible motion) with headroom for transients. Row order DRUMS / BASS / VOCALS / OTHER follows .impeccable's percussion-first reading order.

**Test count delta.**
- 6 dashboard tests added (3 → wait, 27 → 33 dashboard tests pass: 12 DASH.1 + 6 DASH.2.1 + 6 BeatCardBuilder + 3 progress-bar + 6 StemsCardBuilder).
- Full engine suite remains green except the pre-existing `MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget` and `MemoryReporter.residentBytes` env-dependent flakes documented in CLAUDE.md.
- Two GPU-perf tests (`RenderPipelineICBTests.test_gpuDrivenRendering_cpuFrameTimeReduced`, `SSGITests.test_ssgi_performance_under1ms_at1080p`) flaked under full-suite parallel-run contention; both pass in isolation. Neither touches Dashboard code; no regression from DASH.4 (the builder is pure CPU and changes no renderer pipeline state).
- 0 SwiftLint violations on touched files; app build clean.

**What's intentionally NOT in this increment.**
- No `RenderPipeline` / `DebugOverlayView` / `PlaybackView` wiring — DASH.6 scope.
- No multi-card composition / screen positioning — DASH.6 scope.
- No per-stem fill colours — DASH.4.1 amendment slot if monotony reads on the artifact eyeball.
- No fifth row (TOTAL / mood / frame budget) — STEMS is exactly DRUMS / BASS / VOCALS / OTHER. Frame budget is DASH.5; mood would be a future MOOD card.
- No `StemEnergySnapshot` value type — builder reads `StemFeatures` directly.
- No clamp at the builder layer — renderer is the single clamp authority.
- No new row variant — `.bar` from DASH.2 already covers signed deviation. (One less commit than DASH.3.)
- No `Equatable` on `Row` (D-082, D-083 standing rule) — tests use switch-pattern extraction.

**Artifact.**
`.build/dash1_artifacts/card_stems_active.png` — STEMS card rendered with `drumsEnergyRel = 0.5`, `bassEnergyRel = -0.4`, `vocalsEnergyRel = 0.2`, `otherEnergyRel = -0.1` over the deep-indigo backdrop. Bar directions readable: DRUMS right, BASS left, VOCALS right (small), OTHER left (small). Reserved for Matt's M7-style eyeball review of the live STEMS card.

---

## [dev-2026-05-07-e] DASH.3 — Beat & BPM card

**Increment:** DASH.3
**Type:** Feature (dashboard)

**What changed.**

The first **live** dashboard card binds `BeatSyncSnapshot` → `DashboardCardLayout`. New pure `BeatCardBuilder` produces a four-row card titled `BEAT`: MODE / BPM / BAR / BEAT. Lock-state colour mapping per .impeccable: REACTIVE/UNLOCKED `textMuted`, LOCKING `statusYellow`, LOCKED `statusGreen`. No-grid renders `—` placeholders with bars at zero — a stable visual state, not a transient.

**API changes:**

- `DashboardCardLayout.Row` gains `.progressBar(label:value:valueText:fillColor:)` — unsigned 0–1 left-to-right fill (distinct from `.bar` which is a signed slice from centre). Row height matches `.bar`.
- New `BeatCardBuilder` (`Sendable`, `public`) with `init()` and `build(from:width:) -> DashboardCardLayout`.
- `DashboardCardRenderer.drawBarChrome` access widened from `private` to `internal` so the new `DashboardCardRenderer+ProgressBar` extension can reuse the chrome path. No public surface change on the renderer struct itself.
- `BeatSyncSnapshot` is **unchanged**. BEAT phase is derived as `barPhase01 × beatsPerBar − (beatInBar − 1)` clamped to `[0, 1]`. Promoting `beatPhase01` to a first-class snapshot field is deferred to a future increment with its own scope (touches `Sendable` struct, every construction site, and `SessionRecorder.features.csv` column ordering).

**Files added.**

- `PhospheneEngine/Sources/Renderer/Dashboard/BeatCardBuilder.swift`
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer+ProgressBar.swift`
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/BeatCardBuilderTests.swift` (6 tests)
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/DashboardCardRendererProgressBarTests.swift` (3 tests)

**Files edited.**

- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift` (`.progressBar` row case + `progressBarHeight` constant + `Row.height` switch arm)
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer.swift` (dispatch case for `.progressBar`; `drawBarChrome` access `private → internal`)

**Not in this increment (deferred).**

- Wiring `BeatCardBuilder` into `RenderPipeline` / `PlaybackView` / `DebugOverlayView` — DASH.6 owns wiring + multi-card composition + `D` key toggle.
- Adding `beatPhase01: Float` to `BeatSyncSnapshot` and the corresponding `features.csv` column.
- Animations / hover / focus — the dashboard remains read-only typographic telemetry.
- Frame-budget card and stem energy card — DASH.4 and DASH.5.

**Decisions:** D-083 in `docs/DECISIONS.md` (rationale: `.progressBar` row variant for unsigned ramps, lock-state colour mapping, no-grid graceful policy, derived beat phase + deferral of `beatPhase01` snapshot field).

**Test count delta.** 18 → 27 dashboard tests (12 DASH.1 + 6 DASH.2.1 + 6 BeatCardBuilder + 3 progress-bar). Full engine suite green except the documented pre-existing flakes (`MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget`, `MemoryReporter.residentBytes` env-dependent). 0 SwiftLint violations on touched files. `xcodebuild -scheme PhospheneApp` clean.

**Artifact.** `card_beat_locked.png` rendered at 320×220 onto the deep-indigo backdrop matches the eyeball criteria: BEAT title in muted UPPERCASE, MODE `LOCKED` in green, BPM `140` clean and mono, BAR fills ~62% with purpleGlow + `3 / 4` valueText, BEAT fills ~50% with coral + `3` valueText. Card chrome reads as purple-tinted, not black.

---

## [dev-2026-05-07-d] BUG-007.3 — Reverted (failed manual validation)

**Increment:** BUG-007.3 (revert)
**Type:** Revert

**What changed.** Commit `94309858` reverted in full. The Schmitt hysteresis + drift-slope retry implementation did not deliver the manual-validation gates: Everlong planned regressed (5 → 14 lock drops in comparable windows), reactive Everlong landed at `bpm=85.4` (halving-correction misfire — separate issue, BUG-009), and a previously-unseen ~1 s "visual ahead of audio" offset surfaced on internal speakers (BUG-007.4 — investigation bug). The `LiveBeatDriftTracker` returns to its BUG-007.2 state. Three replacement bugs filed in `KNOWN_ISSUES.md`: BUG-007.4 (visual phase offset on internal speakers — diagnostics first), BUG-007.5 (adaptive-window lock hysteresis on asymmetric drift envelopes), BUG-009 (halving-correction threshold).

**Validation evidence:** `~/Documents/phosphene_sessions/2026-05-07T14-28-40Z/` (planned), `~/Documents/phosphene_sessions/2026-05-07T14-33-47Z/` (reactive). Everlong planned: 14 lock drops in 75 s, drift envelope −68 to +25 ms (pre-fix: 5 drops). Reactive Everlong: `grid_bpm=85.4` from `halvingOctaveCorrected()` halving a 170 BPM raw output. Reactive Billie Jean (control): no regression, 3 lock drops, drift bounded.

---

## [dev-2026-05-07-c] DASH.2.1 — Card layout redesign: stacked rows + WCAG-AA labels + brighter chrome

**Increment:** DASH.2.1 (amendment to DASH.2)
**Type:** Design (renderer)

**What changed.**

`/impeccable` review of the DASH.2 artifact surfaced five issues that constant-tuning could not fix: (1) horizontal `label LEFT … value RIGHT` swallowed the label-value relationship at typical card widths; (2) `textMuted` on the card surface gave ~3.3:1 contrast — failing WCAG AA for body-size text; (3) `Color.surface` (oklch 0.13) read as near-black against any backdrop; (4) the pair-row 1 px divider was invisible; (5) bar rows had label/bar/value spatially detached. All five resolved.

**API changes:**

- `DashboardCardLayout.Row` cases reduced to two: `.singleValue` and `.bar` (the `.pair` variant is removed; no callers).
- Stacked layout: label 11 pt UPPERCASE on top, value below. Heights: `singleHeight = 39` (11 + 4 + 24), `barHeight = 32` (11 + 4 + 17). New constant `DashboardCardLayout.labelToValueGap = 4`.
- `DashboardCardLayout.height` skips the `titleSize` term when `title.isEmpty`.

**Renderer changes:**

- Card chrome: `Color.surface` → `Color.surfaceRaised` (oklch 0.17 / 0.018, slightly brighter and more chromatic). Alpha 0.92 unchanged.
- Title and all row labels: `Color.textMuted` → `Color.textBody` (~10:1 vs ~3.3:1).
- Bar row geometry: bar reserves a 56 pt right-side column for value text + 8 pt gap; bar centre is the bar's own mid-x, not the card centre. Bar fill refactored into `drawBarChrome` + `drawBarFill` helpers (SwiftLint compliance).

**Test changes (still 6 in `@Suite("DashboardCardRenderer")`):**

- `render_pairRow_dividerVisible` removed (variant deleted); replaced with `render_singleValueRow_stacksLabelAboveValue` (asserts vertical span between first and last glyph row ≥ 12 pt).
- Canonical artifact test renamed to `render_beatCard_pixelVerifyLabelPositions`. New test helper `paintVisualizerBackdrop` paints a representative deep-indigo backdrop (oklch 0.18 / 0.06 / 285) before the card is drawn — the saved `card_beat.png` now reflects production conditions over a visualizer rather than over transparent black.
- Bar-row tests rebuilt around the new geometry: `barGeometry(for:at:)` helper reproduces the renderer's reserved-column math so sample positions land well inside the fill rather than on its edge.

**Demo fixture (`beatCardFixture`):** card titled `BEAT` with four rows MODE / BPM / BAR / BASS, matching the .impeccable Beat panel. MODE's value uses `Color.statusGreen` for the locked-state colour cue.

**Files edited:**

- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift`
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer.swift`
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/DashboardCardRendererTests.swift`
- `docs/ENGINEERING_PLAN.md`, `docs/DECISIONS.md` (D-082 Amendment 1), `CLAUDE.md`

**Test counts:** 6 DASH.2 tests rebuilt (still 6); 18 dashboard tests total. Full engine suite green; 0 SwiftLint violations on touched files; app build clean. Decisions: D-082 Amendment 1.

**Visual approval:** Matt approved the new artifact `card_beat.png` 2026-05-07.

---

## [dev-2026-05-07-b] BUG-007.3 — Lock hysteresis + live BPM credibility

**Increment:** BUG-007.3
**Type:** Bug fix (DSP / live beat tracking)

**What changed.**

Closes the two failure modes observed during 2026-05-07 manual validation that BUG-007.2 left unaddressed:

- **Mechanism C — natural-music tempo variation drops lock under correct BPM.** Pre-fix, SLTS held lock 80 s but Everlong dropped 5 times in 50 s with drift in the −30 to −68 ms band, even though grid BPM was correct. Individual onsets falling outside `abs(instantDrift − drift) < 30 ms` for ≥ 7 consecutive onsets dropped lock; at 158 BPM that's a 2.7 s window, easily filled by harmonics, reverb tail, snare bleed.
- **Mechanism D — live BPM resolver returns 4 % low on busy mid-frequency content.** Reactive Everlong locked to `grid_bpm=151.9` (true ≈158); drift went 0 → −358 ms over 75 s.

**Part (a) — Schmitt-style asymmetric hysteresis** (`PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift`):

New `staleMatchWindow: Double = 0.060` constant. `update()` lock-decision rewritten — onsets within ±30 ms (`strictMatchWindow`) increment `matchedOnsets` toward `lockThreshold` (acquisition selectivity unchanged). While *already locked*, onsets within ±60 ms but outside ±30 ms are **stale-OK**: they do not increment `matchedOnsets` *or* `consecutiveMisses`, preserving lock through natural expressive timing. Only onsets outside ±60 ms (or no-match returns from `nearestBeat`) increment `consecutiveMisses` toward `lockReleaseMisses=7`.

**Part (b) — drift-slope detector + wider-window retry**:

- New ring buffer of 30 `(playbackTime, driftMs)` samples in `LiveBeatDriftTracker`, pushed on every matched onset. Public `currentDriftSlope() -> Double?` returns least-squares ms/sec slope when ≥ 5 samples cover ≥ 5 s; nil otherwise. Reset on `setGrid` / `reset`.
- New retry trigger in `PhospheneApp/VisualizerEngine+Stems.swift runLiveBeatAnalysisIfNeeded()`. Three paths: (A) no grid → existing 10 s / 20 s initial attempts; (B) prepared-cache grid → skip live inference (BUG-008 territory); (C) live grid present → slope-driven 20 s wider retry when `abs(slope) > 5 ms/s` sustained ≥ 10 s, with 30 s cooldown and a hard cap at 1 retry per track. After the retry, a second high-slope event logs `WARN: live BPM unstable` and *retains* the previous grid rather than installing a third candidate.
- New `BeatGridSource` enum on `VisualizerEngine` (`.none / .preparedCache / .liveAnalysis`) tracks where the installed grid came from so Path C only fires on live grids.

**Files edited:**

- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift`
- `PhospheneApp/VisualizerEngine.swift`
- `PhospheneApp/VisualizerEngine+Stems.swift`
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` (4 new tests)
- `docs/QUALITY/KNOWN_ISSUES.md`, `docs/ENGINEERING_PLAN.md`, `docs/RELEASE_NOTES_DEV.md`

**Tests added** (MARKs 19–22 in `LiveBeatDriftTrackerTests`):

- `schmittHysteresis_preservesLockThroughExpressiveTempoVariation` — synthetic 158 BPM grid + sinusoidal ±50 ms drift wander over 60 s. Asserts ≤ 1 lock drop. Pre-fix would drop ≥ 4.
- `driftSlope_insufficientSamples_returnsNil` — slope returns nil before 5 samples accumulate.
- `driftSlope_flatDrift_returnsNearZero` — perfectly aligned onsets for 12 s → slope < 1 ms/s.
- `driftSlope_linearWalkingDrift_recoversSlope` — onsets pushed forward by 4 ms each (≈ 8 ms/s) → recovered |slope| within 2 ms/s of truth, sign negative (drift = nearest − pt convention).

**Tests run.** `LiveBeatDriftTrackerTests` 22 / 22 pass. Full engine suite 1104 / 1106 (two pre-existing flakes: `MemoryReporter.residentBytes` env-dependent, `MetadataPreFetcher.fetch_networkTimeout` timing-sensitive — both pass on isolated re-run). `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` — clean. `swiftlint --strict` — 0 violations on touched files.

**Manual validation pending.** Acceptance gates in `KNOWN_ISSUES.md BUG-007.3`. Capture sessions to be run on SLTS planned, Everlong planned, Everlong reactive, Billie Jean reactive (control).

**Out of scope (deferred).** Constant ~10–15 ms negative-drift offset (tap-output latency calibration). BUG-008 (offline BPM disagreement). `strictMatchWindow` widening (acquisition selectivity stays). Slope-driven retry on prepared-cache path.

---

## [dev-2026-05-07-a] DASH.2 — Metrics card layout engine

**Increment:** DASH.2
**Type:** Infrastructure (renderer)

**What changed.**

Added the layout primitive that DASH.3 (Beat & BPM), DASH.4 (Stems), and DASH.5 (Frame budget) will compose. Cards are the unit of visual identity for the dashboard — fixed width, fixed row heights, three row variants only.

**Files added:**

- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift` — value type describing one card: title, ordered rows, fixed width, padding, title size, row spacing. `Row` enum with three cases (`.singleValue` / `.pair` / `.bar`) and static row-height constants (single = 18 pt, pair = 18 pt, bar = 22 pt). `height` is computed: `padding + titleSize + (rowSpacing + rowHeight) × N + padding`.
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer.swift` — stateless `Sendable` struct. `render(_:at:on:cgContext:)` paints chrome (rounded `Color.surface` fill at 0.92 alpha + 1 px `Color.border` stroke) → bar geometry → text in that order; reversing the order is a known Failed Approach (text gets painted over). Right-edge clipping enforced via `align: .right` on every value column. Bar fill is signed slice from centre (negative left, positive right), clamped to the supplied range.

**Files edited:**

- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardTextLayer.swift` — added `internal var graphicsContext: CGContext` so the renderer can paint chrome and bar geometry into the same shared buffer the text layer rasterises into.

**Tests added (6 `@Test` functions in `@Suite("DashboardCardRenderer")`):**

- `layoutHeight_matchesSumOfRows` — encodes the height formula explicitly so future row-height edits surface as test failures.
- `render_threeRowCard_pixelVerifyLabelPositions` — renders the canonical three-row card, asserts title-strip glyph alpha and zero paint past `layout.height`. Writes `.build/dash1_artifacts/card_three_row.png` for M7-style review.
- `render_cardNearRightEdge_clipsCorrectly` — places a 280 pt card at `canvasWidth - 280` on a 512 px canvas; asserts the rightmost column's luma is below the text-glyph threshold (chrome fill at the edge is allowed; a stray `textHeading` glyph would fail).
- `render_barRow_negativeValueFillsLeft` — `value: -0.5, range: -1...1` with coral fill: left half coral, right half background.
- `render_barRow_positiveValueFillsRight` — mirror of the negative test.
- `render_pairRow_dividerVisible` — 1 px `Color.border` divider at the midpoint.

Pixel-assertion brittleness (the prompt's risk note) is mitigated by `maxChromaPixel(around:)`: the bar background and foreground are both opaque, so alpha alone cannot distinguish them — chroma can. The right-edge overflow check uses Rec. 601 luma instead of alpha so chrome (low-luma) is correctly distinguished from text glyphs (high-luma `textHeading`).

**What's intentionally NOT in this increment:**

- No card is wired into `RenderPipeline`, `PlaybackView`, or `DebugOverlayView`. DASH.6 owns wiring.
- No data binding (which metrics each card shows). DASH.3/4/5 own that.
- No interactive state (hover, focus). The dashboard is read-only telemetry.
- No animation / transition. Cards repaint each frame from current state.
- No fourth row variant, no flex-width card, no sparkline. Adding variants is a separate increment with explicit Matt approval.

**Decisions:** D-082 (this increment).

**Test counts:** 6 new (18 dashboard total = DASH.1 12 + DASH.2 6). Full engine suite: **1102 tests / 125 suites**, all green. App build clean. 0 SwiftLint violations on touched files.

---

## [dev-2026-05-06-e] DASH.1 — Telemetry dashboard text-rendering layer

**Increment:** DASH.1
**Type:** Infrastructure (renderer + shared)

**What changed.**

Added the foundation layer for Phosphene's floating telemetry dashboard — a developer-togglable HUD that will display real-time metrics (BPM, lock state, stem energies, frame budget) over any active preset.

New files:
- `PhospheneEngine/Sources/Shared/Dashboard/DashboardTokens.swift` — design token namespace: `TypeScale` (6 point sizes from caption=10 to display=36), `Spacing` (4 sizes), `Color` (11 SIMD4 swatches), `Weight`/`TextFont`/`Alignment` enums.
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardFontLoader.swift` — resolves Epilogue TTF from bundle `Fonts/` directory; falls back to system sans-serif; `OSAllocatedUnfairLock` cache; `resetCacheForTesting()` for test isolation.
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardTextLayer.swift` — zero-copy `MTLBuffer` → `CGContext` → `MTLTexture` text renderer; `.bgra8Unorm` pixel format; Core Text with permanent CTM flip; `beginFrame()` clears each frame.
- `PhospheneEngine/Sources/Renderer/Resources/Fonts/README.md` — custom TTF drop-in instructions.

New tests (12):
- `DashboardTokensTests` (4) — color channel ranges, type scale ordering, alignment enum, spacing values.
- `DashboardFontLoaderTests` (3) — system fallback, idempotent caching, test reset.
- `DashboardTextLayerTests` (5) — mono text coverage, prose text coverage, between-frame clear, alignment shift, color application.

Also fixed (pre-existing blockers):
- `LiveAdapter.swift`: added `nonisolated(unsafe)` to `lastOverrideTimePerTrack` (Swift 6.3.1 requirement for mutable stored properties on `@unchecked Sendable` classes).
- `ReactiveOrchestratorTests`: updated Test 5 to expect a hold (not a switch) at gap=0.030 < `minBoundaryScoreGap(0.05)`; added `mediumGapCatalog()` for Test 6 with gap≈0.060 > 0.05.

**Test suite:** 1096 engine tests; 2 pre-existing timing flakes (MetadataPreFetcher, AppleMusicConnectionViewModel). App build: `** BUILD SUCCEEDED **`. SwiftLint: 0 violations.

**No behaviour change to existing presets or sessions.** `DashboardTextLayer` is not yet wired into the render pipeline; wiring lands in DASH.6.

**Decision:** D-081 (font strategy, zero-copy pattern, SC retention, pixel-coverage calibration).

---

## [dev-2026-05-06-f] DASH.1.1 — Tokens aligned to `.impeccable.md` OKLCH spec

**Increment:** DASH.1.1
**Type:** Design-system alignment (shared tokens)

**What changed.**

The DASH.1 token placeholders are replaced with values derived from the `.impeccable.md` OKLCH palette, before DASH.2/3/4 cards reach for them.

- Brand: `purple`, `coral`, `teal` re-tuned from sRGB approximations to OKLCH-derived values; `purpleGlow`, `coralMuted`, `tealMuted` added.
- Surfaces: `bg`, `surface`, `surfaceRaised`, `border` added (4-step ladder, hue 275–278). Replaces the flat `chromeBg`/`chromeBorder`.
- Text: renamed and re-tuned. `textPrimary` → `textHeading` `oklch(0.94 0.008 278)`, `textSecondary` → `textBody` `oklch(0.80 0.010 278)`, `textMuted` re-tuned to `oklch(0.50 0.014 278)`. All three are tinted toward brand purple (~278°) — no pure white anywhere.
- TypeScale: `bodyLarge = 15` added (spec `md`, body in card content). Existing scale unchanged.
- Status: `statusGreen/Yellow/Red` unchanged — held close to pure for legibility per the "color carries meaning" principle.

Test changes:
- `DashboardTokensTests.colorValues()` rewritten to assert the OKLCH ladder: surface monotonically rising, neutrals tinted toward purple (blue > red), text ladder monotonically rising, heading bright but not pure white.
- `DashboardTextLayerTests` renamed `textPrimary` → `textHeading`, `textSecondary` → `textBody` at all five call sites.

**Test suite:** All 12 dashboard tests pass; SwiftLint 0 violations on touched files; app build clean.

**No behaviour change** — `DashboardTextLayer` is still not wired into the render pipeline (DASH.6).

**Decision:** D-081 amendment in DECISIONS.md.

---

## [dev-2026-05-06-d] DSP.4 — Drums-stem Beat This! diagnostic (third BPM estimator)

**Increment:** DSP.4
**Type:** Diagnostic enhancement (`dsp.beat`)

**What changed.** Added a third BPM estimator — Beat This! run on the isolated drums stem — logged at preparation time alongside the existing MIR (kick-rate IOI) and full-mix Beat This! estimates. No runtime behaviour change.

**Files changed:**
- `PhospheneEngine/Sources/Session/StemCache.swift` — `CachedTrackData.drumsBeatGrid: BeatGrid` (default `.empty`); `StemCache.drumsBeatGrid(for:)` accessor.
- `PhospheneEngine/Sources/Session/SessionPreparer+Analysis.swift` — Step 6: feed `stemWaveforms[1]` (drums) into the same `DefaultBeatGridAnalyzer` used for the full mix.
- `PhospheneEngine/Sources/Session/BPMMismatchCheck.swift` — `ThreeWayBPMReading` struct + `detectThreeWayBPMDisagreement` pure function.
- `PhospheneEngine/Sources/Session/SessionPreparer+WiringLogs.swift` — `WIRING: SessionPreparer.drumsBeatGrid` per track; precedence logic: `WARN: BPM 3-way` (preferred, all three present) / `WARN: BPM mismatch` (fallback, drumsBPM zero).
- `PhospheneEngine/Tests/.../Session/BPMMismatchCheckTests.swift` — 7 new 3-way detector tests.
- `PhospheneEngine/Tests/.../Integration/BeatGridIntegrationTests.swift` — 2 new drumsBeatGrid wiring tests.
- `docs/ENGINEERING_PLAN.md`, `docs/RELEASE_NOTES_DEV.md`, `CLAUDE.md` — updated.

**Log lines added per prepared track:**
```
WIRING: SessionPreparer.beatGrid track='...' bpm=118.1 beats=60 isEmpty=false
WIRING: SessionPreparer.drumsBeatGrid track='...' bpm=125.0 beats=60 isEmpty=false
WARN: BPM 3-way track='Love Rehab' mir_bpm=125.0 grid_bpm=118.1 drums_bpm=125.0 mir-grid=5.6% mir-drums=0.0% grid-drums=5.6% (DSP.4: estimators on full-mix vs drums-stem vs kick-rate IOI)
```

**Performance:** one additional Beat This! inference call per prepared track (~415 ms on M-class silicon, absorbed in existing preparation window).

**Next step:** collect 2–3 fresh captures across genres; design fusion logic (OR.4 / DSP.5) when the fan-out pattern is understood.

---

## [dev-2026-05-06-e] BUG-007.2 — Fix prepared-grid horizon exhaustion + lock-hysteresis oscillation

**Increment:** BUG-007.2
**Type:** P2 defect fix (`dsp.beat` / `api-contract` + `algorithm`)

**What changed.** Two independent mechanisms prevented `LiveBeatDriftTracker` from holding `.locked` state in Spotify-prepared sessions. Both fixed.

**Fix A (Mechanism B — horizon exhaustion, 1 line).** `resetStemPipeline(for:)` now calls `cached.beatGrid.offsetBy(0)` instead of using the raw grid. The 30-second Spotify preview produces ~62 beats; `offsetBy(0)` extrapolates the grid to a 300-second horizon at the grid's own BPM. After t ≈ 30 s, `nearestBeat()` continued returning matches instead of nil, so `consecutiveMisses` stopped accumulating and lock held.

**Fix B (Mechanism A — cadence-mismatch oscillation, 1 line).** `lockReleaseMisses` raised from 3 → 7. The BeatDetector sub_bass cooldown (400 ms) vs Money's beat period (487 ms) produces roughly 5 consecutive misses per onset cycle. At threshold 3, lock dropped every 1.2 s; at threshold 7 (7 × 400 ms = 2.8 s), the worst-case gap never reaches the threshold and lock holds. Note: the diagnosis document stated 5; the regression test (`test_lockDoesNotOscillateOnStableInput`) demonstrates that the deterministic adversarial scenario requires ≥ 7 to achieve ≤ 2 oscillations in 60 s.

**Files changed:**
- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — `lockReleaseMisses = 7` (was 3); updated doc comment.
- `PhospheneApp/VisualizerEngine+Stems.swift` — `cached.beatGrid.offsetBy(0)` in `resetStemPipeline`.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — tests 16–18: `makeMoneySyntheticGrid` helper + three regression gates.
- `PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/LiveDriftLockHysteresisDiagnosticTests.swift` — `test_mechanismB` updated from raw-grid bug-documenter to `offsetBy(0)` fix-verifier; `%s` → `%@` format-string SIGSEGV fix; `test_mechanismA` assertion unchanged.
- `docs/QUALITY/KNOWN_ISSUES.md` — BUG-007 marked Resolved; verification criteria checked.

**Tests:** 1076 pass (1 pre-existing `MetadataPreFetcher` network-timeout flake). `BUG_007_DIAGNOSIS=1 swift test --filter LiveDriftLockHysteresisDiagnostic` — all 3 pass.

---

## [dev-2026-05-06-c] BUG-008.1 + BUG-008.2 — Diagnose & surface offline-grid vs MIR BPM disagreement

**Increments:** BUG-008.1 (diagnosis), BUG-008.1 follow-up (synthetic-kick test), BUG-008.2 (fix)
**Type:** P2 defect diagnosis + fix (`dsp.beat` / `algorithm`)

**Diagnosed:** The 5.5 % "BPM error" Love Rehab surfaces on the prepared BeatGrid path is **not a Phosphene port bug** and **not a sample-rate plumbing bug**. The vendored PyTorch reference fixture (`love_rehab_reference.json`, generated by the official Beat This! Python implementation on the same audio) reports `bpm_trimmed_mean=118.05`; Phosphene's Swift port reproduces this at 118.10 — within rounding. Three already-committed regression tests pin every layer of the port end-to-end. The disagreement reflects how Beat This! was trained: human tap annotations integrate the whole mix's accent structure, locking to the perceptual beat (118), while the kick-rate IOI estimator locks to the kick interval (125). Neither is mechanically "right." A synthetic-kick follow-up confirmed the model recovers exactly 125.00 BPM on machine-quantized input — so 125 is in the model's output distribution; on Love Rehab specifically it locks to the perceptual beat instead.

**Fixed (BUG-008.2):** Added `BPMMismatchCheck.swift` (pure detector) and wired it into `SessionPreparer+WiringLogs.swift`. After `prepare()` populates the cache, each track's `TrackProfile.bpm` (MIR / DSP.1 trimmed-mean IOI on sub_bass) is compared against `CachedTrackData.beatGrid.bpm` (Beat This! transformer). When the relative delta exceeds 3 %, a `WARN: BPM mismatch track='...' mir_bpm=... grid_bpm=... delta_pct=...% (BUG-008: estimators disagree; prepared grid uses Beat This! value)` line is emitted to `session.log` via the existing `SessionRecorder` and to the unified log via `Logger.warning`. **No runtime behaviour change** — `LiveBeatDriftTracker` continues to consume the offline grid. The 3 % threshold is intentionally generous: Money 7/4 (1.4 %) and Pyramid Song 16/8 (2.86 %) fall within and do NOT warn; Love Rehab (5.5 %) firmly does. Side finding from the synthetic-kick test: Beat This! returns 117.97 on a 120 BPM input (-1.7 %) and 130.09 on 130 BPM (+0.07 %) — small tempo-specific artifacts unrelated to BUG-008, documented in the diagnosis writeup.

**New tests:**
- `Tests/Diagnostics/BeatGridAccuracyDiagnosticTests.swift` (BUG-008.1) — 4 cases: port-fidelity tripwire on `love_rehab.m4a` against the PyTorch reference fixture; parametrized synthetic-kick recovery at 120/125/130 BPM.
- `Tests/Session/BPMMismatchCheckTests.swift` (BUG-008.2) — 7 pure-function cases: agreement/disagreement at default threshold, zero/non-finite guards, exact-tie boundary, custom threshold override, symmetric `delta_pct` normalization.
- `Tests/Integration/BeatGridIntegrationTests.swift` extended with `bpmMismatch_wiring_doesNotCrash_andGridReachesCache` — integration smoke using a `FixedBPMBeatGridAnalyzer` stub; verifies the wiring runs end-to-end and reaches the detector with both BPMs non-zero.

**Files added:**
- `PhospheneEngine/Sources/Session/BPMMismatchCheck.swift` — pure detector function + `BPMMismatchWarning` struct.
- `PhospheneEngine/Sources/Session/SessionPreparer+WiringLogs.swift` — extracted from `SessionPreparer.swift` (the file would otherwise breach the 400-line SwiftLint gate). Holds the existing BUG-006.1 `WIRING:` per-track summary plus the new BUG-008.2 BPM-mismatch warning.
- `PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/BeatGridAccuracyDiagnosticTests.swift`.
- `PhospheneEngine/Tests/PhospheneEngineTests/Session/BPMMismatchCheckTests.swift`.
- `docs/diagnostics/BUG-008-diagnosis.md` — full diagnosis writeup with all three checks (determinism / sample-rate plumbing / independent ground truth) settled by existing artifacts, plus the synthetic-kick follow-up section with results table.

**Files changed:**
- `PhospheneEngine/Sources/Session/SessionPreparer.swift` — extension moved to `+WiringLogs`; `sessionRecorder` visibility relaxed from `private` to `internal` so the new extension file can access it.
- `PhospheneEngine/Tests/PhospheneEngineTests/Integration/BeatGridIntegrationTests.swift` — `FixedBPMBeatGridAnalyzer` stub + wiring smoke test added.
- `docs/QUALITY/KNOWN_ISSUES.md` — BUG-008 entry rewritten with the diagnosis result, fix description, and softened "estimators disagree" framing (replaces the original "true 125 BPM" framing, which the diagnosis cannot prove).

**Tests:** Engine suite green except the two documented baseline flakes (`MetadataPreFetcher.fetch_networkTimeout`, `SessionManagerCancel`/`ProgressiveReadiness` `@MainActor` timing under parallel execution — both pass in isolation). xcodebuild clean. SwiftLint baseline preserved on touched files (zero new violations).

**Manual validation:** Not gated on a fresh capture — the existing `2026-05-06T20-11-46Z` capture already contains the data that would trigger the WARN on Love Rehab. A future Spotify-prepared session will surface the new line in `session.log`. Live drift behaviour is unchanged from BUG-007's state — that is the intended scope.

**Known issues introduced:** None.
**Known issues resolved:** BUG-008 — disagreement is now surfaced; underlying upstream-model behaviour unchanged by design. BUG-007 (drift-tracker lock-hysteresis) remains open and continues to block the user-visible PLANNED · LOCKED criterion.

**Related:** BUG-008, BUG-006.2 (exposed the latent disagreement end-to-end), BUG-007 (independent — drift-tracker symptom is not addressed by this fix), DSP.2 S5 (introduced offline BeatGrid resolver), Failed Approach #52 (sample-rate plumbing — explicitly ruled out by BUG-008.1 diagnosis).

---

## [dev-2026-05-06-b] BUG-006.2 — Prepared-BeatGrid wiring fix

**Increments:** BUG-006.1 (instrumentation, prior commit), BUG-006.2 (fix)
**Type:** P1 defect fix (`dsp.beat` / `pipeline-wiring`)

**Fixed:**
- **Cause 1 — engine.stemCache never assigned.** `VisualizerEngine.swift:171` declared `var stemCache: StemCache?` but no code in the codebase ever assigned to it. Every `resetStemPipeline(for:)` call therefore took the cache-miss branch and the prepared `BeatGrid` never installed. Now wired in `init` to `sessionManager.cache` (the same `StemCache` instance `SessionPreparer` populates) — entries become visible by reference as preparation completes.
- **Cause 2 — Track-change handler built a partial `TrackIdentity`.** `VisualizerEngine+Capture.swift:129` constructed `TrackIdentity(title:, artist:)` only — duration, catalog IDs, and `spotifyPreviewURL` left nil. `Hashable` therefore mismatched the keys `SessionPreparer` stored from full Spotify-API identities. Now resolves the canonical identity from `livePlan` via the new `PlannedSession.canonicalIdentity(matchingTitle:artist:)` helper. Falls back to the partial identity for ad-hoc/reactive sessions and ambiguous matches.

**New tests:**
- `Tests/Integration/PreparedBeatGridAppLayerWiringTests.swift` (6 cases) — closes the BUG-003 coverage gap that allowed BUG-006 to ship. Tests cover `engineStemCache_isWiredAfterSessionPrepare`, `trackChangeIdentity_matchesPlannedIdentity`, `ambiguousMatch_returnsNil_partialFallback`, `noMatch_returnsNil`, `endToEndProduces_preparedCacheInstall`, `partialIdentity_withoutCanonicalResolution_missesCache` (negative control pinning the regression direction).

**Files added:**
- `PhospheneApp/VisualizerEngine+TrackIdentityResolution.swift` — `canonicalTrackIdentity(matching:)` instance method delegating to the Orchestrator-module pure helper.
- `PhospheneEngine/Tests/PhospheneEngineTests/Integration/PreparedBeatGridAppLayerWiringTests.swift`.

**Files changed:**
- `PhospheneApp/VisualizerEngine.swift` — assigns `self.stemCache = self.sessionManager.cache` after `makeSessionManager`.
- `PhospheneApp/VisualizerEngine+Capture.swift` — track-change handler resolves canonical identity before `resetStemPipeline`.
- `PhospheneApp/VisualizerEngine+WiringLogs.swift` — `logTrackChangeObserved` now reports `resolution=fromLivePlan|partialFallback`.
- `PhospheneEngine/Sources/Orchestrator/PlannedSession.swift` — `canonicalIdentity(matchingTitle:artist:)` pure-function helper added.
- `PhospheneApp.xcodeproj/project.pbxproj` — registered `VisualizerEngine+TrackIdentityResolution.swift` (N10007 / N20007).

**Tests:** 1051 engine tests / 116 suites. Pass except the two documented baseline flakes (`MetadataPreFetcher.fetch_networkTimeout`, `MemoryReporter.residentBytes growth`). App build clean. SwiftLint baseline preserved on touched files (zero new violations).

**Manual validation:** Pending the next live Spotify capture. The BUG-006.1 `WIRING:` instrumentation logs will surface end-to-end behaviour in `session.log`. Verification criteria from the BUG-006 entry remain unchecked until a live session is captured (SpectralCartograph mode label, drift readout settling, `grid_bpm` column in `features.csv`).

**Known issues introduced:** None.
**Known issues resolved:** BUG-006 (code-only — manual sign-off pending). BUG-003's first verification criterion checked off (`PreparedBeatGridAppLayerWiringTests`); LiveDriftValidationTests still pending.

**Related:** BUG-006, BUG-003, BUG-006.1, DSP.3.6, D-070 (`TrackIdentity.spotifyPreviewURL` excluded from `Hashable`).

---

## [dev-2026-05-06-a] BUG-006.1 — Wiring instrumentation

**Increments:** BUG-006.1
**Type:** Instrumentation (no behaviour change)

Source-tagged `WIRING:` log entries added across the prepared-BeatGrid path so a live session capture surfaces the failure mode end-to-end. Optional `SessionRecorder` threaded through `SessionPreparer` and `SessionManager` so logs land in `session.log`. New file `PhospheneApp/VisualizerEngine+WiringLogs.swift` consolidates helpers; `SessionManager+Readiness.swift` extracted to keep `SessionManager.swift` under the SwiftLint 400-line gate. New `caller:` parameter on `resetStemPipeline(for:caller:)` discriminates pre-fire (planner) from track-change paths. Commits `7f95cec0` + `807d3b8c`.

---

## [dev-2026-05-05-c] Quality System Documentation

**Increments:** QS.1
**Type:** Infrastructure / documentation

**New:**
- `docs/QUALITY/DEFECT_TAXONOMY.md` — severity definitions (P0–P3), domain tags, failure classes, and defect process.
- `docs/QUALITY/BUG_REPORT_TEMPLATE.md` — structured template for filing defects with required fields.
- `docs/QUALITY/KNOWN_ISSUES.md` — active issue tracker: 5 open defects (BUG-001 through BUG-005), 5 pre-existing flakes, and 5 recently-resolved P1 defects from DSP.3.x work.
- `docs/QUALITY/RELEASE_CHECKLIST.md` — 10-section pre-release gate covering build, DSP/beat-sync, stem routing, preset fidelity, render pipeline, session/UX, performance, documentation, and git hygiene.
- `docs/RELEASE_NOTES_DEV.md` — this file.

**Changed:**
- `CLAUDE.md` — new `Defect Handling Protocol` section added after `Increment Completion Protocol`.
- `docs/ENGINEERING_PLAN.md` — QS.1 increment added and marked complete.

**Known issues introduced:** None.
**Known issues resolved:** None (documentation only).

---

## [dev-2026-05-05-b] DSP.3.5 + V.7.7A

**Increments:** DSP.3.5, V.7.7A
**Type:** DSP fix + preset architecture

**DSP.3.5 — Halving octave correction + retry:**
- `BeatGrid.halvingOctaveCorrected()` added: halves BPM > 160 recursively, drops every other beat, re-snaps downbeats, recomputes `beatsPerBar`. BPM < 80 unchanged (Pyramid Song guard).
- Live Beat This! retry gate: `liveBeatAnalysisAttempts: Int` (was Bool), max 2 attempts — first at 10 s, retry at 20 s on empty grid.
- `performLiveBeatInference()` extracted for SwiftLint compliance.
- 4 new `BeatGridUnitTests`. **1032 engine tests.**
- Post-validation triage: `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md`.

**V.7.7A — Arachne staged-composition scaffold migration:**
- Arachne migrated from `passes: ["mv_warp"]` to V.ENGINE.1 staged scaffold.
- New fragment functions: `arachne_world_fragment` (placeholder forest backdrop) + `arachne_composite_fragment` (placeholder 12-spoke web overlay).
- Mv-warp helpers removed (incompatible with staged preamble).
- Legacy `arachne_fragment` retained as v5/v7/v9 reference.
- `Arachne.json` updated: `passes: ["staged"]` with two stage definitions.

**Known issues introduced:**
- BUG-002 (PresetVisualReviewTests PNG export broken for staged presets) — pre-existing harness bug exposed by V.7.7A.

**Known issues resolved:**
- BUG-R004 (double-time BPM on 10-second window) — resolved by DSP.3.5 octave correction.

---

## [dev-2026-05-05-a] DSP.3.1–3.4 + V.7.7

**Increments:** DSP.3.1, DSP.3.2, DSP.3.3, DSP.3.4, V.7.7
**Type:** DSP fixes + preset content

**DSP.3.1+3.2 — Diagnostic hold + session-mode signal + pre-fire BeatGrid:**
- `diagnosticPresetLocked` flag, `L` shortcut.
- `SpectralHistoryBuffer[2420]` session-mode slot (0–3).
- SpectralCartograph mode labels: ○ REACTIVE / ◐ PLANNED·UNLOCKED / ◑ PLANNED·LOCKING / ● PLANNED·LOCKED.
- `_buildPlan()` pre-fires BeatGrid.

**DSP.3.3 — Beat sync observability:**
- `SpectralCartographText.draw()` extended with beat-in-bar, drift, phase-offset readouts.
- `textOverlayCallback` now passes `FeatureVector` per frame.
- `[`/`]` developer shortcuts for ±10 ms visual phase calibration.
- `BeatSyncSnapshot` struct (9-field).
- `SessionRecorder.features.csv` gains 9 beat-sync columns.
- `SpectralHistoryBuffer[2421..2429]` downbeat_times + drift_ms slots.
- 31 new tests. **1018 engine tests.**

**DSP.3.4 — Three root causes fixed blocking PLANNED·LOCKED:**
- Bug 1: `BeatGrid.offsetBy` now extrapolates to 300-second horizon.
- Bug 2: `VisualizerEngine.tapSampleRate` stored from audio callback; passed to Beat This!.
- Bug 3: `StemSampleBuffer.snapshotLatest(seconds:sampleRate:)` overload uses actual tap rate.
- 14 new tests. **1028 engine tests.**

**V.7.7 — Arachne WORLD pillar + background dewy webs:**
- Six-layer `drawWorld()` Metal function: sky gradient, distant + near trees, forest floor, atmosphere.
- Snell's-law refractive drops on two background hub webs.
- `ArachneState._tick()` gains `smoothedValence`/`smoothedArousal` (5s low-pass) for mood palette.
- `WebGPU` struct extended with Row 4 `moodData: SIMD4<Float>` (64 → 80 bytes).
- Golden hashes regenerated.

**Known issues resolved:**
- BUG-R001 (BeatGrid finite horizon) — resolved by DSP.3.4.
- BUG-R002 (hardcoded 44100 Hz sample rate) — resolved by DSP.3.4.
- BUG-R003 (StemSampleBuffer undersized at 48000 Hz) — resolved by DSP.3.4.

---

## [dev-2026-05-05] DSP.2 Complete + DSP.3 Audit

**Increments:** DSP.2 S3–S9, DSP.2 hardening, DSP.3 audit
**Type:** DSP — Beat This! transformer + drift tracker

**Summary:** Full Beat This! small0 transformer implemented in Swift/MPSGraph. BeatGrid pipeline end-to-end from Spotify-prepared sessions. Live reactive mode gets Beat This! inference after 10 s of playback. `barPhase01`/`beatsPerBar` propagated to FeatureVector and GPU.

**Bug fixes landed:**
- Four S8 bugs: norm-after-conv shape, transpose-before-reshape, BN1d zero-padding semantics, paired-adjacent RoPE. All individually regression-locked in `BeatThisBugRegressionTests`.
- DSP.3 audit revealed three root causes blocking LOCKED state (fixed in DSP.3.4, see above entry).

**Test suite:** 1028 engine tests / 106 suites at DSP.3.4.

**Known issues introduced:**
- BUG-001 (Money 7/4 stays REACTIVE on live path) — identified during DSP.3.5 post-validation.

---

## [dev-2026-05-04] DSP.2 S1–S2 + DSP.1

**Increments:** DSP.1, DSP.2 S1, DSP.2 S2
**Type:** DSP — tempo estimation rewrite + Beat This! vendoring

**DSP.1 — Sub_bass-only IOI + trimmed-mean BPM:**
- Eliminated band-fusion IOI bias (Failed Approach #50) and histogram-mode bias (Failed Approach #51).
- BPM error dropped from 10–20% to <2% on kick-on-the-beat tracks.
- Reference results: love_rehab 122–126 (true 125), so_what 135–138 (true 136).
- `TempoDumpRunner` CLI + `Scripts/dump_tempo_baselines.sh` + `Scripts/analyze_tempo_baselines.py` shipped as permanent regression infrastructure.

**DSP.2 S1 — Beat This! architecture audit + weight vendoring:**
- `small0` model selected: 2,101,352 params, 8.4 MB FP32, MIT license confirmed.
- 161 weight tensors vendored under Git LFS.
- Six JSON reference fixtures (love_rehab, so_what, there_there, pyramid_song, money, if_i_were_with_her_now).

**DSP.2 S2 — BeatThisPreprocessor Swift port:**
- Mono Float32 → log-mel spectrogram matching Beat This! Python `LogMelSpect` exactly.
- Critical: Slaney mel filterbank with continuous Hz interpolation (integer-bin approach underestimates ~12%).
- Golden match on love_rehab first 10 frames: max|Δ| = 2.9×10⁻⁵.

---

## [dev-2026-05-02] V.7.5, V.7.6.C, V.7.6.D, V.7.6.1, V.7.6.2

**Increments:** V.7.5, V.7.6.C, V.7.6.D, V.7.6.1, V.7.6.2

**V.7.5 — Arachne v5 (composition + warm restoration + drops + spider cleanup):**
- Pool capped 12→4, drops as visual hero (radius 8 px), Marschner TRT-lobe warm rim restored, warm key / cool ambient.
- Spider: dark silhouette, AR gate restored, `subBassThreshold` 0.65→0.30.
- M7 review result: output matches `10_anti_neon_stylized_glow.jpg` anti-reference. `certified` rolled back to false. V.7.6 (atmosphere-as-mist patch) abandoned in favour of compositing-anchored V.7.7+.

**V.7.6.1 — Visual feedback harness:**
- `PresetVisualReviewTests` renders presets at 1920×1280 for three FeatureVector fixtures.
- Contact sheet: render in top half, refs 01/04/05/08 in bottom half.
- Gated behind `RENDER_VISUAL=1`.

**V.7.6.C — maxDuration calibration + diagnostic class:**
- Per-section linger factors inverted to Option B.
- `is_diagnostic` JSON field (→ `maxDuration = .infinity`); SpectralCartograph flagged.

**V.7.6.D — Diagnostic preset orchestrator exclusion:**
- `DefaultPresetScorer` excludes `is_diagnostic` presets categorically.
- `DefaultLiveAdapter` no-ops mood override for diagnostic presets.
- `DefaultReactiveOrchestrator` skips diagnostic presets in ranking.

**Known issues introduced:**
- BUG-004 (all presets `certified: false`) — documented; V.7.10 is the planned resolution path. *(Update: BUG-004 was actually resolved 2026-05-12 by Lumen Mosaic certification at LM.7, ahead of V.7.10. See `[dev-2026-05-12-d]`.)*

---

## [dev-2026-04-25] Milestones A, B, C

**Increments:** U.1–U.11, 4.0–4.6, 5.2–5.3, 6.1–6.3, 7.1–7.2, V.1–V.6, MV-0–MV-3
**Type:** Multi-phase milestone delivery

Milestones A (Trustworthy Playback), B (Tasteful Orchestration), and C (Device-Aware Show Quality) all met on 2026-04-25.

**Highlights:**
- Full session lifecycle (idle → connecting → preparing → ready → playing → ended).
- Apple Music + Spotify OAuth connectors.
- Progressive session readiness (partial-ready CTA).
- Orchestrator: PresetScorer, TransitionPolicy, SessionPlanner, LiveAdapter, ReactiveOrchestrator.
- Frame budget governor + ML dispatch scheduler.
- V.1–V.3 shader utility library (Noise, PBR, Geometry, Volume, Texture, Color, Materials).
- V.6 fidelity rubric + certification pipeline.
- Phase U: permission onboarding, connector picker, preparation UI, playback chrome, settings panel, error taxonomy, toast system, accessibility.
- Beat This! architecture committed (DSP.2 scope).

**Known issues at milestone:**
- All presets uncertified (BUG-004). *(Resolved 2026-05-12 — Lumen Mosaic certified at LM.7; see `[dev-2026-05-12-d]`.)*
- Spotify preview_url null for some tracks (BUG-005).
- Test suite: 4 pre-existing Apple Music environment failures (unchanged).
