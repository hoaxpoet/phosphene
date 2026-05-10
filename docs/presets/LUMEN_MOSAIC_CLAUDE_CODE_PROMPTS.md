# Lumen Mosaic — Claude Code Session Prompts

This document contains structured Claude Code session prompts for each increment in Phase LM. Each prompt is self-contained: it provides context, explicit file lists, numbered tasks, done-when criteria, and shell verification commands. Paste each prompt into a Claude Code session as the starting message; do not include this file's surrounding meta-text.

**Decisions in force (post-2026-05-09 design rewrite — see `LUMEN_MOSAIC_DESIGN.md §11 Revision History`):**

- A.1 Lumen Mosaic
- B.1 analytical agent contributions
- C.2 ~50 cells across
- **D.4 per-cell colour identity from `palette()` keyed on cell hash + audio time + mood** (replaces retired D.1)
- **E.3 procedural palette via V.3 IQ cosine; mood shifts `(a, b, c, d)` continuously; no authored palette banks** (replaces retired E.1 + E.2)
- F.1 slot 8 fragment buffer
- G.1 fixed camera (panel oversize 1.50×)
- H.1 standalone preset

**Status of these prompts (2026-05-09):**

- LM.0 / LM.1 / LM.2 / LM.3 have all shipped. Their prompts below are kept as **historical reference** — they describe the actual session prompts used at the time of execution. The LM.2 + LM.3 prompts pre-date the design rewrite, so they cite retired decisions (D.1 / E.1 / E.2) and produce code that has since been replaced.
- LM.4+ prompts below reflect the post-pivot architecture (per-cell palette + procedural mood, no authored banks). When pasting, double-check the "Decisions in force" list above is still accurate at the time of execution.

**Convention notes:**

- Repo root in prompts is `~/code/phosphene` (Matt's working directory). Adjust if local path differs.
- Commits follow `[<increment-id>] <component>: <description>` — `<increment-id>` is `LM.X` for these prompts.
- All performance numbers are measured at 1080p Tier 2 unless otherwise stated.

---

## Pre-LM.0 setup (Matt's manual prerequisite, NOT a Claude Code session)

Per `Preset_Development_Protocol.md` Gate 0 and `SHADER_CRAFT.md §2.3`, the VISUAL_REFERENCES folder must exist before any session prompt is written. Since the prompts below cite reference images by filename, this setup must complete before LM.0.

Matt's responsibility, before pasting LM.0:

1. Create `docs/VISUAL_REFERENCES/lumen_mosaic/` in the repo.
2. Drop `04_specular_pattern_glass_closeup.jpg` into the folder (Git LFS; matches the `.gitattributes` rule for `docs/VISUAL_REFERENCES/**/*.{jpg,png}` from Increment V.5).
3. Drop the authored README from `VISUAL_REFERENCES_lumen_mosaic_README.md` (renamed to `README.md`) into the folder.
4. Verify the lint passes:
   ```
   swift run --package-path PhospheneTools CheckVisualReferences --strict
   ```
   For the Lumen Mosaic folder specifically, expect at most a "needs more references" warning until additional slots (01–05, 09 anti) are curated. No errors are acceptable.
5. Commit: `[LM.pre] LumenMosaic: VISUAL_REFERENCES scaffold + hero image`.
6. Curate additional references at any point during Phase LM execution. The README's "Curation slots" section lists the suggested slots; sourcing them is parallel to the LM.X session work, not a blocker.

The first Claude Code session (LM.0) verifies this setup is in place before starting (see LM.0 task list).

---

## LM.0 — Infrastructure: fragment buffer slot 8 + Phase LM scaffolding

> **Status: ✅ EXECUTED 2026-05-08 (commit `6388e881`).** Slot 8 binding wired in `RenderPipeline` (later widened in LM.2 to bind on both G-buffer and lighting passes — see [`docs/CLAUDE.md`](../CLAUDE.md) GPU Contract). The prompt below is kept as historical reference; the actual on-disk slot-8 binding contract has evolved past it.

```
Context: I'm starting Phase LM (Lumen Mosaic), a new ray-march preset that uses pattern_glass on a full-screen panel as its primary visual surface, with audio-driven backlight behind. The design is in docs/presets/LUMEN_MOSAIC_DESIGN.md and the rendering contract is in docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md. Read both before starting.

This is LM.0 — pure infrastructure. We add a new fragment buffer slot at index 8 to RenderPipeline (per Decision F.1) so future preset-uniform CPU-driven state has a home. Lumen Mosaic is the first consumer; later presets can share the slot.

No shader code in this increment. No Lumen Mosaic preset yet. Just the slot.

Files to read first:
- docs/presets/LUMEN_MOSAIC_DESIGN.md
- docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md
- docs/CLAUDE.md (GPU Contract section, Buffer slot 6/7 paragraphs as the template)
- docs/DECISIONS.md (read recent entries D-085+ to understand decision-entry conventions)
- PhospheneEngine/Sources/Renderer/RenderPipeline.swift (existing setDirectPresetFragmentBuffer / setDirectPresetFragmentBuffer2 are the templates)
- PhospheneEngine/Sources/Renderer/RenderPipeline+Staged.swift (per-frame uniform binding contract; slot 6/7 are bound in every staged pass — slot 8 follows the same contract)
- PhospheneEngine/Sources/Renderer/RenderPipeline+MVWarp.swift (slot 6/7 are bound in the mv_warp path)

Files to create/edit:

CREATE:
1. None.

EDIT:
1. PhospheneEngine/Sources/Renderer/RenderPipeline.swift
   - Add private var directPresetFragmentBuffer3: MTLBuffer?
   - Add public func setDirectPresetFragmentBuffer3(_ data: UnsafeRawPointer, length: Int)
   - Mirror the implementation pattern of setDirectPresetFragmentBuffer2.
2. PhospheneEngine/Sources/Renderer/RenderPipeline+Staged.swift
   - In every fragment encoder that currently binds slot 6 and 7 uniformly, also bind slot 8 if directPresetFragmentBuffer3 is non-nil. Keep the binding null-safe (skip the bind, do not bind a default).
3. PhospheneEngine/Sources/Renderer/RenderPipeline+MVWarp.swift
   - Same: bind slot 8 conditionally alongside slot 6 / 7 in the per-frame uniform contract.
4. PhospheneEngine/Sources/Renderer/RenderPipeline+Direct.swift (or wherever the direct-pass fragment encoder lives)
   - Same binding addition.
5. PhospheneEngine/Sources/Renderer/RayMarchPipeline.swift
   - Bind slot 8 conditionally on the lighting fragment encoder. The G-buffer encoder does NOT need slot 8 (only lighting / composite consumers).
6. docs/CLAUDE.md (GPU Contract section)
   - Add a paragraph for buffer(8) following the buffer(6) / buffer(7) template. Note: "per-preset fragment buffer #3 — bound by setDirectPresetFragmentBuffer3. Reserved for future preset-uniform CPU-driven state. Currently unused; first consumer planned: Lumen Mosaic (Phase LM)."
7. docs/DECISIONS.md
   - Append D-LM-buffer-slot-8 entry. Status: Accepted (date). Same justification structure as existing decisions: what, why, alternatives considered, rule.
8. docs/ENGINEERING_PLAN.md
   - Add new section "## Phase LM — Lumen Mosaic" with rationale paragraph.
   - Add "### Increment LM.0 — Fragment buffer slot 8 infrastructure" with scope, done-when, verify.

Numbered tasks:
1. **Gate 0 prerequisite check.** Verify Matt's pre-LM.0 setup landed: `docs/VISUAL_REFERENCES/lumen_mosaic/README.md` and `docs/VISUAL_REFERENCES/lumen_mosaic/04_specular_pattern_glass_closeup.jpg` both exist; `swift run --package-path PhospheneTools CheckVisualReferences --strict` against the lumen_mosaic folder reports no errors (warnings about needing more references are acceptable). If any prerequisite is missing, halt and escalate — do not attempt to author the README or copy the image inside this session; that is Matt's curation work.
2. Read all the files in "Files to read first" above. Do not skip any. The slot 6/7 binding contract has subtleties; understand them before editing. Read `docs/VISUAL_REFERENCES/lumen_mosaic/README.md` — even though LM.0 is purely infrastructure, the README's "actively disregard" list informs the buffer naming and comments.
3. Edit RenderPipeline.swift to add directPresetFragmentBuffer3 + setDirectPresetFragmentBuffer3.
4. Add the binding in every per-frame uniform binding site (RenderPipeline+Staged, +MVWarp, +Direct, RayMarchPipeline lighting).
5. Update docs/CLAUDE.md GPU Contract.
6. Add D-LM-buffer-slot-8 to docs/DECISIONS.md.
7. Update docs/ENGINEERING_PLAN.md with Phase LM header and LM.0 entry.
8. Run `swift build --package-path PhospheneEngine` and confirm green.
9. Run `swift test --package-path PhospheneEngine` and confirm green.
10. Commit with `[LM.0] RenderPipeline: add fragment buffer slot 8 infrastructure`.

Done when:
- RenderPipeline exposes setDirectPresetFragmentBuffer3.
- All fragment encoders that bind slot 6/7 also conditionally bind slot 8.
- CLAUDE.md, DECISIONS.md, ENGINEERING_PLAN.md updated.
- Full test suite green; no behavior change for existing presets (slot 8 is null when no preset binds it).

Verify:
- swift build --package-path PhospheneEngine
- swift test --package-path PhospheneEngine
- swift test --package-path PhospheneEngine --filter PresetAcceptanceTests   # all 11 presets still pass
- swift test --package-path PhospheneEngine --filter PresetRegressionTests   # golden hashes unchanged

Anti-patterns to avoid:
- Do not modify the slot 6/7 binding contract. Slot 8 is additive.
- Do not bind a default zero buffer at slot 8. Null when not set.
- Do not document slot 8 as "Lumen Mosaic only". The slot is a shared resource; Lumen Mosaic is the first consumer.

If you hit a blocker (e.g., the binding contract assumes uniform binding across pass stages and slot 8 cannot be ray-march-only), stop and report. Do not work around it without escalation.
```

---

## LM.1 — Minimum viable preset: panel + pattern_glass + static backlight

> **Status: ✅ EXECUTED 2026-05-08 (commit `d1c9c7ba`; remediations `93521485` + `7efe1932`).** Glass panel + Voronoi cell relief + fbm8 frost + static warm-amber backlight all shipped to the catalog. The matID == 1 emission-dominated dispatch in `RayMarch.metal` is still the load-bearing lighting path used by LM.2 / LM.3. Prompt below is historical — the actual implementation is on disk.

```
Context: LM.0 wired the fragment buffer slot 8. This increment lands the first version of Lumen Mosaic. No audio reactivity yet, no pattern engine. Just: a glass panel filling the camera frame, rendered with mat_pattern_glass, with a single static warm-amber backlight emitted through every cell.

This proves the rendering pipeline works end-to-end before we add complexity.

Read first:
- docs/presets/LUMEN_MOSAIC_DESIGN.md (sections 4 and 5)
- docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md (entire document)
- docs/SHADER_CRAFT.md §4.5b (mat_pattern_glass recipe)
- docs/SHADER_CRAFT.md §2.2 (coarse-to-fine 9-pass authoring workflow)
- docs/CLAUDE.md (Preset Metadata Format section, G-Buffer Layout section)
- PhospheneEngine/Sources/Presets/Shaders/GlassBrutalist.metal (reference for ray-march sceneSDF / sceneMaterial pattern)
- PhospheneEngine/Sources/Presets/Shaders/KineticSculpture.metal (reference for multi-material sceneMaterial dispatch)
- PhospheneEngine/Sources/Presets/Shaders/Utilities/Materials/Dielectrics.metal (read mat_pattern_glass; confirm signature)
- PhospheneEngine/Sources/Presets/Shaders/Utilities/Texture/Voronoi.metal (confirm VoronoiResult layout, especially the .id field)

Files to create:

1. PhospheneEngine/Sources/Presets/Shaders/LumenMosaic.metal
   - sceneSDF: returns sd_box for the glass panel sized from s.cameraTangents. **CRITICAL: panel half-extents = `s.cameraTangents.xy * 1.50` (50% oversize) so panel edges are NEVER visible in frame. See contract §P.1 and design doc §4.2 for the exact skeleton.** Note that `panel_uv` in `sceneMaterial` divides by `cameraTangents` (NOT by the oversized half-extents) so cell density is decoupled from the oversize factor — this is intentional per contract §P.1.
   - sceneMaterial: implements the pattern_glass body per §4.2. matID == LUMEN_GLASS (= 1).
   - Helper functions:
     * mood_tint(valence, arousal) -> float3 (returns warm/cool ambient color; valence/arousal both at zero -> neutral cream)
     * sample_backlight_static() -> float3 (returns a fixed warm-amber float3, e.g., float3(0.95, 0.6, 0.3); will be replaced in LM.2)
   - Emission output: implement Option α from the rendering contract — write the backlight value to the G-buffer's albedo channel and use a unique matID (= 1) to flag emission-dominated dielectric. The lighting fragment will need a small adjustment to handle this.

2. PhospheneEngine/Sources/Presets/Shaders/LumenMosaic.json
   - Standard fields per the JSON template in the rendering contract §JSON sidecar fields.
   - certified: false at this stage.
   - lumen_mosaic.cell_density = 30.0 (Decision C.2).

(The `docs/VISUAL_REFERENCES/lumen_mosaic/` folder, README.md, and `04_specular_pattern_glass_closeup.jpg` are pre-LM.0 deliverables Matt commits before this session begins. Per `Preset_Development_Protocol.md` Gate 0 + `SHADER_CRAFT.md §2.3`, they must exist before this prompt runs. **Verify their presence as task #2 below; halt and escalate if missing.**)

Files to edit:

3. PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal
   - In the lighting fragment, add a matID == 1 dispatch (or equivalent) that handles the emission-dominated path: instead of full Cook-Torrance dielectric, multiply albedo by a high gain (start with 4.0) and add an IBL ambient floor at low intensity (0.05). Keep the existing matID dispatch behaviour unchanged for matID == 0 and others.
   - Document the new behaviour in the comment block above the fragment.

4. docs/CLAUDE.md
   - Add LumenMosaic to the Shaders/ list following the pattern of GlassBrutalist / KineticSculpture entries.
   - Document the new matID == 1 emission-dominated convention briefly.

5. docs/ENGINEERING_PLAN.md
   - Append "### Increment LM.1 — Minimum viable preset" with done-when bullets.

Numbered tasks:
1. Read all "Read first" files. Do not skip the SHADER_CRAFT §2.2 9-pass workflow. Also read `docs/VISUAL_REFERENCES/lumen_mosaic/README.md` — this README is the visual contract for the preset (mandatory / decorative / actively-disregard traits, plus the rubric). Treat its "actively disregard" list as a list of things NOT to implement.
2. Verify Gate 0 prerequisites: `docs/VISUAL_REFERENCES/lumen_mosaic/README.md` exists; `docs/VISUAL_REFERENCES/lumen_mosaic/04_specular_pattern_glass_closeup.jpg` exists (Git LFS); `swift run --package-path PhospheneTools CheckVisualReferences --strict` against the lumen_mosaic folder reports either zero warnings or only "needs more references" warnings (never errors). Halt and escalate if any prerequisite missing.
3. Author LumenMosaic.metal:
   - First: macro geometry only. Just sd_box(p, panel_size) + matID = 1 for hits, matID = 0 for misses. Confirm the panel renders as a solid color rectangle.
   - Then: add Voronoi cells (mat_pattern_glass body, no frost yet, no backlight modulation yet — height-gradient relief only). Confirm per-cell shading shows raised dimple character.
   - Then: add the in-cell frost normal perturbation. Confirm specular sparkle appears under IBL.
   - Then: route a static warm-amber backlight to every cell's emission. Confirm the panel reads as warm-glowing pebbled glass.
4. Author LumenMosaic.json with the recommended sidecar fields. Set certified: false.
5. Edit RayMarch.metal lighting fragment to handle matID == 1 emission-dominated path. Test that GlassBrutalist still renders correctly (matID == 0 path should be unchanged).
6. Update CLAUDE.md and ENGINEERING_PLAN.md.
7. Run the full build and test suite. Confirm green. Specifically:
   - swift test --package-path PhospheneEngine --filter presetLoaderBuiltInPresetsHaveValidPipelines  # verifies LumenMosaic compiles and renders
   - swift test --package-path PhospheneEngine --filter PresetAcceptanceTests  # verifies LumenMosaic passes all 4 invariants (non-black, no-clip, beat response, form complexity)
8. Capture a contact sheet for LumenMosaic at the standard fixture set (silence, steady, beat-heavy, HV-HA, LV-LA mood). Save to docs/VISUAL_REFERENCES/lumen_mosaic/contact_sheets/LM.1/.
9. Performance check: run PresetPerformanceTests and confirm p95 ≤ 2.0 ms at Tier 2 / ≤ 2.5 ms at Tier 1.
10. Commit with `[LM.1] LumenMosaic: minimum viable preset (static backlight, no audio)`.

Done when:
- LumenMosaic.metal + LumenMosaic.json land in the catalog.
- Preset compiles and renders cleanly through PresetLoader.
- presetLoaderBuiltInPresetsHaveValidPipelines passes.
- PresetAcceptanceTests passes against all 4 invariants for LumenMosaic.
- Contact sheet at LM.1/ produced with all six fixtures.
- **Panel-edge invariant: every pixel in every contact-sheet frame hits the panel (matID == 1). No background / void pixels visible. Verify by inspecting the matID debug capture (matID == 0 should be empty across the whole frame). Per Decision G.1 + contract §P.1.**
- p95 ≤ 2.0 ms at Tier 2.
- GlassBrutalist and other ray-march presets unchanged (no regression in PresetRegressionTests against existing presets).
- Reference image is in VISUAL_REFERENCES with README.

Verify:
- swift build --package-path PhospheneEngine
- swift test --package-path PhospheneEngine
- swift test --package-path PhospheneEngine --filter PresetAcceptanceTests
- swift test --package-path PhospheneEngine --filter PresetRegressionTests
- swift test --package-path PhospheneEngine --filter PresetPerformanceTests
- swift run --package-path PhospheneTools CheckVisualReferences  # verifies VISUAL_REFERENCES schema

Matt review:
- Contact sheet from LM.1/ side-by-side with 04_specular_pattern_glass_closeup.jpg. Question to answer: does this read as the same kind of surface? The colors will differ (we have static warm-amber; the reference has multiple colors); the cellular character should match.
- If review fails on "reads as flat" or "frost too subtle", note in the commit message and queue a tuning iteration before LM.2.

Anti-patterns to avoid:
- Do not write the full final shader in one pass. Coarse-to-fine per SHADER_CRAFT.md §2.2.
- Do not skip the in-cell frost. The detail cascade is mandatory; without micro-frost, the preset reads as flat stained glass and fails the rubric.
- Do not modify mat_pattern_glass in Materials/Dielectrics.metal. The recipe is shared infrastructure (Glass Brutalist v2 will use it). All Lumen-Mosaic-specific extensions live in LumenMosaic.metal helper functions.
- Do not bind slot 8 yet. The pattern state buffer is wired up in LM.2/LM.4. LM.1 is static-backlight only.
```

---

## LM.2 — Audio-driven 4-light backlight (continuous energy primary)

> **Status: ⚠ EXECUTED 2026-05-09 (commits `66999ff4` + `71e3d72a`); VISUAL SCOPE REJECTED AT PRODUCTION REVIEW.** The 4-light cell-quantized backlight model + cream-baseline mood tint produced muted, gradient-blob output with no visible cells. Engine + GPU contract scaffolding (slot-8 binding wired into both G-buffer and lighting passes; agent dance math; mood smoothing via 5 s low-pass; `LumenPatternEngine` lifecycle on preset apply / track change) verified correct and reused at LM.3. **Substantive look re-targeted to LM.3** under the design rewrite (commit `7bf96319 [LM-DESIGN]`). The prompt below is historical — it cites the now-retired Decisions D.1 (cell-quantized backlight sample) and E.1 (cream-baseline mood tint), and instructs the implementer to write `lm_mood_tint` / `lm_sample_backlight_at` helpers that LM.3 deleted.

```
Context: LM.1 produced a static warm-amber glass panel. This increment replaces the static backlight with 4 audio-driven light agents that move and shift color according to continuous-energy bands and mood. Pattern engine still not introduced — LM.4 will do that.

This is the first increment that uses slot 8. It introduces LumenPatternState (CPU-side struct + uniform buffer + shader binding).

Read first:
- docs/presets/LUMEN_MOSAIC_DESIGN.md §4.3, §4.5
- docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md (Required uniforms / buffers section)
- docs/CLAUDE.md (D-019 silence fallback, D-026 deviation primitives)
- docs/DECISIONS.md (D-019, D-026, D-020)
- docs/ARACHNE_V8_DESIGN.md §11 (5-second mood smoothing pattern; we follow this)
- PhospheneEngine/Sources/Presets/Shaders/VolumetricLithograph.metal (D-019 silence fallback reference implementation)
- PhospheneEngine/Sources/Presets/LumenMosaic.metal (from LM.1)

Files to create:

1. PhospheneEngine/Sources/Presets/LumenPatternEngine.swift
   - Public class LumenPatternEngine.
   - State: 4 LumenLightAgent instances + LumenPatternState struct (no patterns yet — just lights).
   - Public methods:
     * init(seed: UInt64) — sets light agents to base positions per contract §P.2.
     * update(deltaTime: TimeInterval, features: FeatureVector, stems: StemFeatures) — advances light agents per frame.
     * snapshot() -> LumenPatternState — returns Sendable snapshot for upload to slot 8.
   - Light agent update logic per contract §P.4 ("The dance"). For each agent, position is composed as:
     ```
     position = basePosition[i]
              + driftTerm                    // slow mood-driven Lissajous
              + beatLockedOscillation        // CO-PRIMARY, beat_phase01-locked
              + barPatternOffset[i]          // stays zero until LM.4
     position = clamp(position, ±kAgentInset)  // kAgentInset = 0.85
     ```
   - **Drift term** (slow, mood-driven):
     * Speed: lerp(0.05, 0.20, (arousal+1)/2) u/s — slow at low arousal.
     * Direction: per-agent Lissajous frequency (distinct per agent so they don't move in sync).
     * Radius: stem-specific bound (drums 0.25, bass 0.20, vocals 0.30, other 0.30 — from contract §P.4 / LM.3).
   - **Beat-locked oscillation** (the dance — contract §P.4, MANDATORY):
     * `beatPhaseRad = f.beat_phase01 * 2 * π`
     * `danceAmplitude = 0.04 + 0.10 * f.arousal` (in uv units; clamped to [0.04, 0.14] for arousal ∈ [0, 1])
     * `agentBeatPhaseOffset = [0, π/2, π, 3π/2]` for [drums, bass, vocals, other]
     * `offset_x = cos(beatPhaseRad + agentBeatPhaseOffset[i]) * danceAmplitude`
     * `offset_y = sin(beatPhaseRad * 2 + agentBeatPhaseOffset[i]) * danceAmplitude * 0.5` (figure-8)
   - **Base positions** per contract §P.2:
     ```
     drums:   (-0.45, +0.35)   bass:    (0.00, -0.40)
     vocals:  ( 0.00, +0.05)   other:   (0.45, +0.30)
     ```
   - Color is base-color × mood_tint(valence, arousal). Base colors per stem: drums = warm orange-red float3(1.0, 0.4, 0.2), bass = deep red float3(0.8, 0.2, 0.1), vocals = peach float3(1.0, 0.7, 0.5), other = cool teal float3(0.3, 0.7, 0.9).
   - Intensity per stem: drums driven by stems.drums_energy_rel with D-019 fallback to f.beat_bass*0.6 + f.beat_mid*0.4; bass driven by stems.bass_energy_rel with fallback to f.bass_dev*0.6; vocals by stems.vocals_energy_dev with fallback to 0.0; other by stems.other_energy_rel with fallback to f.treble*1.4.
   - Mood smoothing: 5s low-pass on f.valence and f.arousal (per ARACHNE pattern).
   - Buffer management: maintains an MTLBuffer for LumenPatternState; updates it per frame; provides a method to bind it to RenderPipeline at slot 8.

2. PhospheneEngine/Tests/PhospheneEngineTests/LumenPatternEngineTests.swift
   - Test at silence: all light intensities < 0.05 (silence floor). Ambient floor still active.
   - Test at HV-HA mood: light colors warm-shifted, arousal-driven drift speed > 0.15 u/s.
   - Test at LV-LA mood: light colors cool-shifted, drift speed < 0.10 u/s.
   - Test stem direct routing: with stems.drums_energy_rel = 0.5, light[0].intensity should be ≈ 0.5 (within 5%). With stems empty (warmup), fallback path should fire; light[0].intensity should be ≈ 0.5 * (f.beat_bass * 0.6 + f.beat_mid * 0.4).
   - Test mood smoothing: feed valence step from -1 to +1; intensity should reach 95% of new value at ~15s (3 time constants of 5s low-pass).
   - **Test beat-lock (the dance, contract §P.4):** sweep f.beat_phase01 from 0 to 1 over a single frame budget; verify that each agent's position offset from base traces a closed Lissajous curve (figure-8) with the expected amplitude. Specifically: at arousal = 0.5 with beat_phase01 = 0.0, agent[0] (drums, phase offset 0) should be at base + (0.09, 0). At beat_phase01 = 0.25, agent[0] should be at base + (0, 0.045) (cos(π/2)=0, sin(π)*0.5=0). Within ±5% tolerance.
   - **Test agent inset clamp (contract §P.2):** force base position to (0.95, 0) (outside kAgentInset = 0.85) and verify clamped position never exceeds ±0.85 in any axis even with full drift + dance + (future) pattern offset.

Files to edit:

3. PhospheneEngine/Sources/Presets/Shaders/LumenMosaic.metal
   - Replace sample_backlight_static() with sample_backlight_at(uv) that reads LumenPatternState at buffer(8) and computes the 4-light analytical sum per design doc §4.3.
   - Add the LumenPatternState struct definition matching Swift exactly. Layout per rendering contract.
   - Use the cell-center uv (v0.pos / scale) as the sample point, not the per-pixel uv (Decision D.1).

4. PhospheneEngine/Sources/Renderer/RenderPipeline.swift (or wherever VisualizerEngine drives presets)
   - Wire LumenPatternEngine into the per-frame render path: when the active preset is LumenMosaic, call engine.update(...) and engine.snapshot() each frame, then bind via setDirectPresetFragmentBuffer3.

5. PhospheneEngine/Sources/Presets/PresetLoader.swift (or wherever preset-specific Swift state is wired)
   - When LumenMosaic preset becomes active, instantiate LumenPatternEngine. When deactivated, tear it down.

6. docs/CLAUDE.md
   - Add LumenPatternEngine to the Sources/ list and document its public API contract.
   - Document the LumenPatternState layout (must match shader struct byte-for-byte).

7. docs/ENGINEERING_PLAN.md
   - Append "### Increment LM.2 — Audio-driven 4-light backlight" with done-when.

Numbered tasks:
1. Read all "Read first" files.
2. Author LumenPatternEngine.swift with the 4-light update logic.
3. Author LumenPatternEngineTests.swift covering silence, mood quadrants, stem routing, mood smoothing.
4. Update LumenMosaic.metal: define LumenPatternState struct (byte-identical to Swift); replace sample_backlight_static() with sample_backlight_at() reading from buffer(8); use cell-center uv for sampling.
5. Wire LumenPatternEngine into the render path: instantiate on preset apply; update + snapshot + bind per frame.
6. Run swift test --filter LumenPatternEngineTests; confirm green.
7. Run swift test --filter PresetAcceptanceTests; confirm LumenMosaic still passes all 4 invariants.
8. Capture LM.2 contact sheet at the six standard fixtures.
9. Performance verify: p95 ≤ 2.5 ms at Tier 2.
10. Update CLAUDE.md (LumenPatternEngine API + struct layout).
11. Commit with `[LM.2] LumenMosaic: 4-light audio-driven backlight (continuous energy + mood)`.

Done when:
- LumenPatternEngine produces a Sendable LumenPatternState every frame.
- Slot 8 is bound when LumenMosaic is the active preset; null otherwise.
- LumenMosaic.metal reads buffer(8) and computes per-cell backlight from 4 lights.
- D-019 silence fallback verified (test fixture + visual contact sheet at silence shows mood-tinted ambient, not black).
- Mood-coupled palette shift verifiable in the HV-HA vs LV-LA contact sheet pair.
- **Beat-locked dance (contract §P.4) verified by test fixture: agent positions trace the expected figure-8 over a beat. With a 120 BPM track, a 16 s capture must show visible peak-on-beat agent motion (verified by Matt at LM.2 review).**
- p95 ≤ 2.5 ms at Tier 2.
- All existing PresetAcceptanceTests + PresetRegressionTests still pass for non-LumenMosaic presets.

Verify:
- swift build --package-path PhospheneEngine
- swift test --package-path PhospheneEngine
- swift test --package-path PhospheneEngine --filter LumenPatternEngineTests
- swift test --package-path PhospheneEngine --filter PresetAcceptanceTests
- swift test --package-path PhospheneEngine --filter PresetPerformanceTests

Matt review:
- LM.2 contact sheet at HV-HA + LV-LA + steady. The two mood-quadrant frames must visibly differ in palette. The steady frame should show 4 distinct colored "regions" of the panel.
- Silence frame: must not be black; must read as a quiet, unified mood-tint.
- **The dance test (NEW): play a known-BPM track (the 120 BPM calibration reference) and watch a 16 s capture. Agent motion peaks must visibly land on the beat. If the dance reads as random or jittery, escalate before LM.3 — the beat-lock math is wrong.**
- Beat-heavy fixture: drum onsets at this stage have no special visual effect — that's correct; pattern engine arrives in LM.4. The continuous beat-lock dance is the only beat-coupled motion at LM.2.

Anti-patterns to avoid:
- Do not drive light intensities directly from raw f.bass / f.mid / f.treble. Use _att_rel / _dev / _rel per D-026.
- Do not modify the LumenPatternState layout once committed. The shader struct must mirror Swift byte-for-byte; layout drift is silent corruption.
- Do not use the per-pixel uv for backlight sampling. Cell-center quantization (Decision D.1) is the visual identity.
- Do not skip the D-019 silence fallback. The PresetAcceptanceTests "non-black at silence" invariant will fail if the fallback isn't wired.
- Do not skip the beat-locked oscillation (contract §P.4). Without it, lights wander but don't dance — failing Matt's framing intent. This is co-primary with stem energy, NOT a deferred enhancement.
- Do not implement patterns yet. Pattern engine is LM.4. This increment is just the 4 lights.
```

---

## LM.3 — Per-cell palette + procedural mood + drop cream baseline

> **Status: ⚠ REJECTED IN PRODUCTION 2026-05-09 (commit `d17dcf4f` [LM.3]).** Cells did not visibly cycle on real Spotify-normalised audio. Spotify volume normalisation pulls mid + treble bands toward zero (BUG-012); `accumulated_audio_time = (bass + mid + treble) / 3 × dt` advanced ~0.045 / sec instead of the design-target ~0.5 / sec. Procedural palette + per-cell hash + mood-coupled parameters + per-track seed all working as specified — the *time-driven cycling* mechanism is what failed against real audio. Superseded by **LM.3.2 (D.5 band-routed beat-driven dance)**.

## LM.3.1 — Agent-position-driven backlight character

> **Status: ⚠ REJECTED 2026-05-09 (commit `d8a31aee` [LM.3.1]).** Matt 2026-05-09: "fixed-color cells with brightness modulation; the bright pools dominated the visual story." `lm_cell_intensity` rewritten with a position-based static field (max-of-falloffs over agent positions × `kAgentStaticIntensity = 0.50`) plus audio-driven sum, floored at `kCellMinIntensity = 0.05`; `defaultAttenuationRadius` sharpened from 6 → 12 for spotlit lobes. The four agent positions painted four bright lobes that read as the visual subject; cells underneath felt static. Brightness modulation is not the visual register the preset is meant to occupy. Superseded by **LM.3.2**.

## LM.3.2 — Band-routed beat-driven dance (Decision D.5)

> **Status: ⏳ EXECUTED 2026-05-09 (commit pending); awaiting M7 review on real session.** Replaces both LM.3 and LM.3.1.
>
> - **Cells dance synchronised to FFT-band beats.** Each cell hashes (`cell_id ^ lm_track_seed_hash(lumen)`) and lands in one of four teams (30 % bass / 35 % mid / 25 % treble / 10 % static). The cell's palette index advances *discretely on rising-edge of its team's `f.beatBass / beatMid / beatTreble`*, debounced 80 ms, scaled by `beatStrength = clamp(0.3 + 1.4 × max(f.bass, f.mid, f.treble), 0.3, 1.0)`. Energy metric uses `max()` not avg — Spotify-normalised tracks under-read mid + treble (BUG-012) and a max keeps quiet sections animated as long as bass is firing.
> - **Per-cell `period ∈ {1, 2, 4, 8}` from another hash bucket.** Pareto-distributed (≈37.5 % / 25 % / 25 % / 12.5 %). Fast cells advance every team beat; slow cells hold their step for many beats. Aggregate target ~50–60 % cells changing per second of energetic music ("bubbling cauldron" register, Matt 2026-05-09).
> - **Static cells, rotated per track.** The 10 % of cells in the static team change identity from track to track (XOR with per-track seed scrambles team membership).
> - **Brightness uniform with hash jitter.** `0.85 + 0.15 × jitter` (jitter from another hash bucket). Plus a global bar pulse `1.0 + 0.30 × pow(saturate(f.bar_phase01), 8.0)` — brief +30 % flash in the last ~8 % of each bar. LM.3.1's agent-position static field retired; agent `intensity / colorR/G/B` fields stay on the GPU contract for ABI continuity but are unused by the LM.3.2 shader.
> - **Per-track palette seed magnitudes bumped.** LM.3 → LM.3.2: `kSeedMagnitude{A,B,C,D}` 0.05/0.05/0.10/0.20 → 0.20/0.20/0.30/0.50. Different tracks at the same mood now produce visibly different palette character.
> - **`LumenPatternState` extended 360 → 376 B.** Added `bassCounter`, `midCounter`, `trebleCounter`, `barCounter` fields. Engine maintains rising-edge state on `LumenPatternEngine` (private `prevBeatBass / prevBeatMid / prevBeatTreble / prevBarPhase01`, debounce timestamps, `bassBeatsSinceBarFallback` for the no-grid fallback). New private `updateBandCounters(features:)` extracted from `_tick` for SwiftLint compliance. **`reset()` and `setTrackSeed(_:)` both call a new `resetBeatTrackingState()` helper** that zeroes counters + rising-edge state — the `setTrackSeed` reset is load-bearing (without it, an old track's accumulated counter values would carry over and the new track's cells would jump straight to a far-off palette index on the new track's first beat).
> - **New shader helpers and constants.** `lm_hash_u32(uint) → uint` (Murmur-style xor-shift mixer), `lm_track_seed_hash(constant LumenPatternState&) → uint`. Constants: `kPaletteStepSize = 0.137 ≈ 1/φ²`, `kBarPulseMagnitude = 0.30`, `kBarPulseShape = 8.0`, `kBassTeamCutoff / kMidTeamCutoff / kTrebleTeamCutoff = 30 / 65 / 90`, `kCellIntensityBase = 0.85`, `kCellIntensityJitter = 0.15`. **Retired**: `kCellHueRate`, `kAgentStaticIntensity`, `kCellMinIntensity`.
>
> See [`docs/presets/LUMEN_MOSAIC_DESIGN.md`](LUMEN_MOSAIC_DESIGN.md) §3 Decision D (D.5) and §11 Revision History; the [`docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md`](Lumen_Mosaic_Rendering_Architecture_Contract.md) `sceneMaterial` pseudocode (§50–87) for the full shader algorithm; [`docs/DECISIONS.md`](../DECISIONS.md) D-LM-d5 for the rationale; the LM.3.2 contact sheet at [`docs/VISUAL_REFERENCES/lumen_mosaic/contact_sheets/LM.3.2/`](../VISUAL_REFERENCES/lumen_mosaic/contact_sheets/LM.3.2/).
>
> **M7 review pending: real-session capture against the test playlist.** The harness contact sheet shows team assignment + one-step advance correctly (the `beat` fixture differs from `mid` by ~30 % of cells advancing one palette step on the bass-team rising-edge). The load-bearing checks are *time-evolution* (cells advancing on each successive beat at ~50–60 % cells / sec target on a 120 BPM track) and *per-track palette identity* (different palette character across tracks). Both need a 30+ second real-music capture. **Increment status stays ⏳ until that review approves the visual** — this is the recurring process error: LM.2, LM.3, and LM.3.1 were all prematurely ✅'d on commit landing and all three were subsequently rejected. Phase LM increment status stays ⏳ until visually approved on real music.

---

## LM.4 — Pattern engine v1 (idle + radial_ripple + sweep)

> **PRECONDITION: LM.3 must be M7-approved on a real session before this prompt runs.** Tests passing and harness contact sheets rendering are not sufficient. If LM.3 is still ⏳ in the engineering plan, do not paste this prompt.

```
Context: LM.3 shipped per-cell colour identity from the procedural palette (each Voronoi cell carries its own deterministic hue; cells visibly cycle through palette during energetic playback; per-track seed gives different tracks distinct palette character). LM.3.1 added position-based backlight character (cells under an agent are brighter than cells in the gaps). What's missing: PATTERN BURSTS — transient brightness spikes that fire on bar boundaries and drum onsets, painting moving accents across the panel.

LM.4 ships three pattern types: idle (no-op), radial_ripple (expanding ring of brightness from an origin), sweep (linear wavefront crossing the panel).

CRITICAL ARCHITECTURAL NOTE — PATTERNS INJECT INTENSITY, NOT COLOUR (post-LM.3 redesign):
- Each Voronoi cell already has its own colour from `lm_cell_palette()`. Patterns do NOT override that colour.
- Patterns add to `cell_intensity` — i.e. they BRIGHTEN cells they cross. A radial_ripple firing on a "warm-red" cell flashes warm-red brighter; on a "cool-cyan" cell, it flashes cool-cyan brighter. The pattern colour comes for free from the cell's own palette identity.
- This is a deliberate departure from the pre-pivot design (which had patterns inject their own colour and `mix(backlight, pattern_color, pattern_value)`). The pre-pivot architecture was retired with the cream baseline.

Read first:
- docs/presets/LUMEN_MOSAIC_DESIGN.md §4.4 (pattern engine)
- docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md (Required uniforms section — `LumenPattern` struct layout is already on the GPU buffer at LM.2; LM.4 just promotes its `kindRaw` field from idle → live)
- docs/CLAUDE.md (FeatureVector.barPhase01 — added in DSP.2 S9; this is what bar-boundary detection should use, NOT beat_phase01)
- PhospheneEngine/Sources/Presets/Lumen/LumenPatternEngine.swift (the engine + struct + setTrackSeed APIs are all in place — LM.4 fills in the patterns slot)
- PhospheneEngine/Sources/Presets/Shaders/LumenMosaic.metal (lm_cell_intensity is the integration point — patterns add to its sum)

Files to create:

1. PhospheneEngine/Sources/Presets/Lumen/LumenPatterns.swift
   - struct IdlePattern, RadialRipplePattern, SweepPattern producing `LumenPattern` snapshots.
   - Each pattern type's CPU side knows how to seed itself from a beat/bar event (origin from drum-onset uv, direction for sweep). Color fields stay zero (LM.3 architecture: patterns don't carry colour).
   - The `LumenPatternKind` enum is already declared on `LumenPatternEngine` (idle = 0, radialRipple = 1, sweep = 2, …); LM.4 just promotes radialRipple + sweep from "reserved values" to "live evaluators".

2. PhospheneEngine/Tests/PhospheneEngineTests/Presets/LumenPatternsTests.swift
   - Verify pattern lifecycle: spawn → active → retire after duration.
   - Verify radialRipple expansion: at t=0, radius=0; at t=duration, radius reaches panel edge.
   - Verify sweep direction: direction is unit-length; direction is stable across the pattern's lifetime.

Files to edit:

3. PhospheneEngine/Sources/Presets/Lumen/LumenPatternEngine.swift
   - Promote `state.activePatternCount` from 0 (LM.3 placeholder) to ≥ 0 live patterns.
   - Update logic:
     * **Bar-boundary detection (use barPhase01, NOT beat_phase01):** `f.barPhase01` wraps from > 0.9 to < 0.1 each downbeat. Retire oldest pattern; spawn a new one (random selection from {radialRipple, sweep}, mood-weighted). Per-bar deterministic hash so the same track is reproducible. **If `f.beatsPerBar` reports 0 or barPhase01 stays at 0 (reactive mode without an installed BeatGrid), fall back to beat-onset-edge bar inference: count rising-edge beats and treat every Nth beat as the bar boundary, where N = 4.** This keeps LM.4 useful for tracks that haven't been Spotify-prepared.
     * **Drum onset detection:** `stems.drumsBeat` rising edge > 0.3 with 100 ms debounce. Spawn a `radialRipple` regardless of active pattern count (push out the oldest if at capacity). Origin uv = drums-agent's current position (seeded from where the drums lobe is brightest at onset time).
     * Update active patterns: advance phase; auto-retire patterns whose phase > 1.0.
   - Snapshot all 4 patterns (active + idle padding) into `LumenPatternState.patterns`.

4. PhospheneEngine/Sources/Presets/Shaders/LumenMosaic.metal
   - Add pattern evaluator helpers (per-pattern returns a scalar intensity contribution at the cell's centre uv):
     * `lm_pattern_radial_ripple(cell_center_uv, p)` — Gaussian peak at radius = `p.phase × kPanelOversize`; σ proportional to `1 − p.phase` (ring narrows as it expands). Returns intensity in `[0, 1]`.
     * `lm_pattern_sweep(cell_center_uv, p)` — narrow band centred at `sweep_position = p.phase × 2 − 1` along the sweep direction; intensity = `exp(−distance² / σ²)`. Returns intensity in `[0, 1]`.
     * `lm_pattern_idle(p)` — returns 0.
     * `lm_evaluate_active_patterns(cell_center_uv, lumen)` — sums up to `lumen.activePatternCount` per-pattern intensities, scaled by each pattern's `intensity` field, clamped to a documented ceiling so D-037 beat-response invariant holds.
   - **Integration**: in `lm_cell_intensity`, after computing `total = static_max × kAgentStaticIntensity + audio_acc`, ADD `lm_evaluate_active_patterns(cell_center_uv, lumen) × kPatternBoost`. The cell's colour is unchanged (still from `lm_cell_palette()`); patterns just brighten their cells.
   - **kPatternBoost** is a new file-scope constant — start at 1.0 (a peak ripple roughly doubles a cell's brightness) and tune in M7 review.

5. docs/CLAUDE.md — document the pattern engine API + `kPatternBoost` tuning constant.
6. docs/ENGINEERING_PLAN.md — append LM.4 entry.

Numbered tasks:
1. Read all "Read first" docs.
2. Author `LumenPatterns.swift` with the three pattern types.
3. Author `LumenPatternsTests.swift` with lifecycle + expansion + direction tests.
4. Edit `LumenPatternEngine.swift` to manage the active patterns array and implement bar-boundary (via `barPhase01`) + drum-onset triggers.
5. Edit `LumenMosaic.metal` with the per-pattern evaluators and the integration into `lm_cell_intensity`.
6. Run tests; confirm green.
7. Capture LM.4 contact sheet at six fixtures + a beat-heavy 30-second sequence (key frames at 0 / 2 / 5 / 10 / 20s) to verify pattern emergence and decay across time.
8. Performance: p95 ≤ 3.0 ms at Tier 2. If exceeded, profile pattern eval cost.
9. Commit `[LM.4] LumenMosaic: pattern engine v1 (idle + radial_ripple + sweep)`.

Done when:
- Pattern engine spawns and retires patterns on bar / drum-onset events.
- Patterns visibly emerge in real-session captures at beat-heavy moments — cells they cross flash brighter while keeping their per-cell palette colour.
- Patterns at silence are inactive (panel reads as the LM.3.1 backlit cell field with no transient bursts).
- D-037 beat response invariant holds (`kPatternBoost` chosen so peak pattern brightness ≤ 2× continuous + 1.0 — automated test).
- p95 ≤ 3.0 ms at Tier 2.
- **Increment status stays ⏳ until Matt reviews on a real session.** Same discipline as LM.3 — tests passing + harness frames rendering ≠ done.

Verify:
- swift test --package-path PhospheneEngine --filter LumenPatterns
- swift test --package-path PhospheneEngine --filter LumenPatternEngine
- swift test --package-path PhospheneEngine --filter PresetAcceptance
- swift test --package-path PhospheneEngine --filter PresetPerformance

Matt review:
- Beat-heavy real-session capture: do drum onsets visibly produce ripples expanding from coherent origins? If origins look random, the stem-driven origin logic needs work.
- Bar-boundary patterns: does the pattern noticeably "change" at bar boundaries on a Spotify-prepared track? Does the fallback (Nth-beat inference) feel coherent on a reactive-mode track?
- D-037 beat response invariant: contact sheet at beat-heavy must satisfy "beat response ≤ 2× continuous response + 1.0". If it fails, `kPatternBoost` is too high; halve it and re-evaluate.

Anti-patterns to avoid:
- **Do NOT make patterns inject their own colour.** Cells take their colour from `lm_cell_palette()`; patterns brighten cells they cross, full stop. Re-introducing a `pattern_color_at()` would resurrect the pre-pivot architecture that was retired.
- Do not let patterns become the primary motion driver (D-004). The continuous backlight + per-cell palette cycling is primary; patterns are accent only.
- Do not implement clusterBurst / breathing / noiseDrift in this increment. LM.5.
- **Do not use beat_phase01 for bar-boundary detection.** `f.barPhase01` (DSP.2 S9) is the authority. Beat-phase wraps every beat (4× per bar in 4/4); bar-phase wraps every bar. Confusing the two will produce 4× too many bar events.
- Do not let bar-boundary detection use absolute time thresholds. Smoothstep on the sawtooth wrap is the right pattern; reading raw `barPhase01 < 0.1` fails on irregular meters.
```

---

## LM.5 through LM.9 — outline only

The first four increments above are the path to a working audio-reactive Lumen Mosaic. The remaining increments are described at outline detail; expand each into a full prompt when its predecessor is reviewed and Matt has confirmed the trajectory.

### LM.5 — Pattern engine v2 + (optional) per-stem hue affinity / silhouette occluders

**Scope.** Add `clusterBurst`, `breathing`, `noiseDrift` patterns (still injecting **intensity**, not colour — same architecture as LM.4). Allow up to 2 patterns to be simultaneously active when bar boundaries and drum onsets coincide.

**Optional sub-decisions** (adopt only if LM.3 / LM.4 review identifies a need):

- **Per-stem hue affinity (Decision E.b).** Each agent's intensity contribution to a cell could be weighted by the cell's hue similarity to the agent's "preferred" hue family (drums → warm reds, bass → deep reds, vocals → peach, other → cool teal). This would give the panel a "different stems own different cell zones" character without quadrant-locking. Adopt only if LM.3 / LM.4 review judges the unified-palette feel undifferentiated stem-wise. If adopted, file a `D-LM-hue-affinity` decision entry.
- **Silhouette occluder masks (Decision B.2).** If the panel still reads flat / "blob-y" after pattern engine v2 lands, add 1–3 simple silhouette shapes (rectangles, ellipses, organic blobs from `worley_fbm`) at notional mid-depth that attenuate light contribution to cells whose projected centre falls behind the silhouette. Adopt only if LM.4 review judges the panel reads flat without silhouettes. If adopted, file a `D-LM-silhouettes` decision entry.

**Estimated sessions:** 2.

**Prerequisites for prompt expansion:** Matt's LM.4 review notes (does the preset feel sparse at idle? do bar-boundary changes feel meaningful? are stems differentiated enough? is silhouette work justified?).

### LM.6 — Fidelity polish (micro-frost, specular, cell density, palette tuning, aspect-ratio invariant)

**Scope.** A/B test cell density (scale 24 vs 30 vs 36) against ref `04`. Tune frost amplitude (current `kFrostAmplitude = 0.0008f`) and frost scale (current `kFrostScale = 80.0f`) for specular sparkle that matches the reference's micro-character. **Tune palette parameters** against real-track session recording — adjust the cool/warm × subdued/vivid × unison/offset × complementary/analogous endpoint vectors so each mood quadrant produces a distinctive palette character. **Tune `kCellHueRate`** (the master cycle-speed knob — LM.3 default 0.15) based on what feels right at 90 / 120 / 140 BPM. **Tune backlight contrast knobs** (`kAgentStaticIntensity`, `kCellMinIntensity`, `defaultAttenuationRadius`) if LM.3.1 review showed the bright/dim contrast wrong. Optionally add chromatic aberration on cell-edge ridges (rubric "strongly preferred 4 — chromatic aberration"). **Aspect-ratio invariant: produce contact sheets at 16:9, 4:3, and 21:9 — verify the panel edge is never visible in any frame at any aspect ratio. If 21:9 reveals panel edges at corners, increase `kPanelOversize` in LumenMosaic.metal (note: this changes panel SDF only; cell density stays the same per contract §P.1).**

**Estimated sessions:** 1–2.

**Prerequisites for prompt expansion:** LM.5 contact sheets + a recorded session against ≥ 3 real tracks Matt nominates (one ambient / downtempo, one mid-energy, one beat-heavy / dance).

### LM.7 — Beat accent layer + vocal hotspot

**Scope.** Promote drum-onset ripples (LM.4 baseline) to a polished accent: rise time, peak amplitude, trail decay tuned for cross-genre legibility. Add bar-line shimmer (a low-amplitude `sweep` across the panel at bar boundaries — uses the existing pattern system). Add vocal hotspot: when `stems.vocals_energy_dev > threshold`, a small bright cluster emerges near the vocals agent's current position — distinct from the radial ripple.

**Estimated sessions:** 1.

### ~~LM.8 — Mood-quadrant palette banks (Decision E.2)~~

**Status: RETIRED 2026-05-09.** Decision E.2 (4 hand-authored palette banks crossfaded by mood quadrant) was rejected during the LM.3 design pivot on monotony grounds (Matt 2026-05-09: "*Why are there four hand-picked palettes — this will lead to a very monotonous preset?*"). The procedural palette via V.3 IQ cosine `palette()` (Decision E.3) shipped at LM.3 instead and provides infinite palette character variation through (a) continuous mood interpolation across the `(a, b, c, d)` parameter space and (b) per-track seed perturbation. There is no LM.8 increment.

### LM.9 — Certification

**Scope.** Final pass: rubric verification (mandatory 7/7, expected ≥ 2/4, strongly preferred ≥ 1/4); `PresetAcceptanceTests` regression; `PresetRegressionTests` golden hash registration via `UPDATE_GOLDEN_SNAPSHOTS=1`; `PresetPerformanceTests` p95 + p99 + max; soak harness 60-second captures across all fixtures; `KNOWN_ISSUES.md` sweep. Set `certified: true`. Update `RELEASE_NOTES_DEV.md`.

**LM.9-specific gates added at the design rewrite:**

- **Vividness gate** (rendering contract §Certification fixtures, LM.3+): every fixture except silence must produce per-cell colour values where the dominant cells have at least one channel `< 0.30` AND another channel `> 0.70` in linear space pre-tone-map. The silence fixture has the same requirement applied to held cell colours. Catches accidental retain of any pastel / cream-haze formula. Automated check, runs against LM.9 contact sheets.
- **Distinct-neighbour gate**: sample 50 random cell-centre uvs in any non-silence frame; the colour distribution must span at least 1/3 of the palette range. Verifies per-cell hash + palette is producing distinct hues, not a smooth field. Catches regressions to the LM.2-style smooth-blob failure mode.
- **No-cream gate**: no fixture frame should have a dominant pixel value within ε of `(0.95, 0.85, 0.75)` (the retired LM.2 cream-haze region). Catches accidental retain of the old `mix(cream, hue, sat)` pattern.
- **Time-evolution gate**: capture two frames 3 s apart at the same fixture under simulated `accumulated_audio_time` advance; cell colours must visibly differ in non-silence fixtures. Verifies `kCellHueRate` is producing the expected cycling.
- **Per-track distinctiveness**: capture the same fixture with two different `setTrackSeed` perturbations; the resulting palette character must visibly differ.

**Estimated sessions:** 1.

**Prerequisites for prompt expansion:** All preceding increments green; Matt's M9 review against ref `04` (cell + frost detail) + ref `05` (palette character) + the curated track set is positive.

---

## Cross-increment notes

### Performance regression discipline

Every increment from LM.1 onward must run `PresetPerformanceTests` and record p50 / p95 / p99 / max. If p95 exceeds the budget by more than 25%, halt and profile before continuing. Do not adopt a "ship now, optimize later" pattern — the budget table in the rendering contract is calibrated to keep Lumen Mosaic the cheapest ray-march preset, which preserves headroom for future presets.

### D-026 / D-019 enforcement

Every audio-routing edit must be reviewed by `grep -n 'f\.bass[^_]\|f\.mid[^_]\|f\.treble[^_]' PhospheneEngine/Sources/Presets/Shaders/LumenMosaic.metal`. The grep must return zero matches; raw band reads are an anti-pattern (D-026). The same grep against `LumenPatternEngine.swift` should also be empty (CPU side uses the same deviation primitives via FeatureVector accessors). Note: at LM.3 the only remaining `f.treble` read is the FV fallback path for the "other" agent's intensity — a documented exception that lives in `computeIntensity` and is consumed during the brief stem-warmup window only.

### Matt-review boundaries — increment status discipline

Every increment from LM.1 onward must produce contact sheets at the documented certification fixtures (silence / steady / beat-heavy / sustained-bass / HV-HA / LV-LA) before the increment can be considered for completion. **An increment is ⏳ until Matt approves it on a real-music session — not when tests pass and harness frames render.** Recurring process error noted at LM.2 + LM.3: marking ✅ on commit landing, then watching the visual scope get rejected at production review. Going forward, the engineering plan's status field stays ⏳ until Matt's real-session sign-off.

### Documentation keep-up

CLAUDE.md, DECISIONS.md, and ENGINEERING_PLAN.md are updated incrementally — every increment adds at least one paragraph somewhere. The accumulated diff at LM.9 should be a complete, self-contained snapshot of the preset's API contracts, decision history, and increment ledger. Documentation drift is silent regression; do not let it accumulate. **This includes this prompts document** — when an increment ships under a different design from what the prompt describes, revise the prompt to match (or mark it historical with a clear pointer to the actual implementation).

### Anti-pattern audit

Before LM.9, run a final audit:

- **No raw `f.bass` / `f.mid` / `f.treble` reads in LumenMosaic.metal or LumenPatternEngine.swift.** Use deviation primitives. The single LM.3 exception (`f.treble × 1.4` as the other-agent FV fallback during stem warmup) must be documented inline; no other raw reads.
- **No `smoothstep(0.22, 0.32, f.bass)` style absolute-threshold gates.** Use D-026 deviation patterns.
- **No hardcoded BPM assumptions.** Use `f.beat_phase01` / `f.barPhase01` / `stems.drumsBeat` as authority.
- **No camera motion.** Camera position is JSON-fixed (Decision G.1).
- **No SDF deformation from audio.** `sceneSDF` is audio-independent (D-020).
- **No second-bounce ray tracing.** Backlight is analytical (Decision B.1; B.2 if adopted at LM.5).
- No reproducing the reference image's content (the references are for guidance; the preset is original work).
- **Panel edges never visible.** Sweep all certification contact sheets (LM.9 fixtures × 16:9 / 4:3 / 21:9 aspect ratios). The `matID == 0` (background / void) channel must be empty in every frame. Per Decision G.1 + contract §P.1.
- **Beat-locked dance is co-primary, not deferred.** `LumenPatternEngine._tick` must include the `beat_phase01`-locked oscillation term in agent position composition (contract §P.4). Verify by inspecting the position update path in `LumenPatternEngine.swift` and matching against §P.4 pseudocode.
- **No cream baseline / pastel pull.** No `mix(cream, hue, sat)` formula anywhere in `LumenMosaic.metal` or `LumenPatternEngine.swift` (the LM.1/LM.2 anti-pattern that produced muted output, retired at LM.3 — `lm_mood_tint`, `lm_sample_backlight_at`, and `lm_backlight_static` were deleted, do not re-introduce).
- **Per-cell colour identity stays.** `sceneMaterial` must call `lm_cell_palette(cell_id, accumulated_audio_time, lumen)` keyed on the per-cell hash. Replacing this with a per-pixel sample (LM.2-era D.1) would resurrect the smooth-gradient-blob failure mode.
- **Patterns inject intensity, not colour (LM.4+).** `lm_evaluate_active_patterns` must return a scalar `[0, 1]` intensity contribution; cells take their colour from `lm_cell_palette()`, not from any per-pattern colour field. Re-introducing `pattern_color_at()` and `mix(backlight, pattern_color, ...)` would resurrect the pre-pivot architecture.
- **Vividness gate at certification.** Every non-silence fixture must produce dominant cell colours with at least one channel `< 0.30` AND another channel `> 0.70` in linear space. Catches any accidental retreat to muted output.

Pass: file `LM-9-audit-passed.txt` in `docs/VISUAL_REFERENCES/lumen_mosaic/` listing each check, the grep / inspection used, and the result.
