# Drift Motes — Session 2 (DM.2) Claude Code Prompt

You are implementing **Phase DM, Increment DM.2** for Phosphene: the audio-coupling pass for the **Drift Motes** preset.

This is **Session 2 of 3**. Scope is strictly limited (see *Out-of-scope* below). Stop at the milestone gate; do not run ahead.

---

## Context — what you're building and why

DM.1 landed a flocking-free particle field with a warm-amber sky backdrop and a Murmuration-bit-identical `PresetRegressionTests` baseline. The kernel had no audio coupling — no FV reads beyond the engine's normal binding, no stem reads at all, no D-019 warmup blend (the prompt-level `(void)totalStemEnergy;` placeholder was removed in the post-DM.1 cleanup pass).

**DM.2 makes the field musical.** Three things land together because they share a single coherent visual story:

1. **Light shaft** — one dramatic god-ray entering from upper-left at ≈30° from vertical, rendered in screen-space via `ls_radial_step_uv`. Defines where motes catch and what the field is *of*.
2. **Floor fog** — `vol_density_height_fog` providing ambient haze that the shaft cuts through.
3. **Per-particle hue baked at emission** — each mote carries the vocal pitch of its emission moment, mapped to hue. The field's chromatic texture *is* the recent vocal melody, drifting through the beam.

This is the first session where Drift Motes reads stems. **The D-019 warmup blend is mandatory** — the kernel must work in the cold-stems window (~10 s after track change in any session, every track in ad-hoc mode) by falling back to FeatureVector proxies. Get this wrong and the first ten seconds of every track render as flat amber.

**DM.2 is also the right place to take the first performance measurement.** DM.3 only adds emission-rate audio coupling (cheap); the volumetric work landing here is what consumes the budget. Measure now, not after the fact.

DM.3 will add emission-rate scaling from `f.mid_att_rel` and a drum-driven dispersion shock. **Not in this session.**

---

## Read first — canonical truth (read in this order)

1. **The DM.1 review** (this conversation, the message preceding this prompt). Don't replay DM.1 issues; build on the corrected baseline.
2. **`docs/presets/Drift_Motes_Rendering_Architecture_Contract.md`** — Section "Acceptance gates per phase → Session 2" is the gate this session must pass.
3. **`docs/presets/DRIFT_MOTES_DESIGN.md`** — trait matrix rows for shaft, fog, per-particle hue.
4. **`docs/DECISIONS.md` D-019** — warmup blend pattern (canonical).
5. **`docs/DECISIONS.md` D-026** — deviation primitives, not absolute energy.
6. **`docs/DECISIONS.md` D-029** — paradigm rule: pass set stays `["feedback", "particles"]`.
7. **`PhospheneEngine/Sources/Presets/Shaders/ParticlesDriftMotes.metal`** — the file you're extending. Note the established filename (`Particles…` prefix, not `DriftMotes…`); do not rename.
8. **`PhospheneEngine/Sources/Renderer/Geometry/DriftMotesGeometry.swift`** — the conformer.
9. **`PhospheneEngine/Sources/Renderer/Geometry/DriftMotesGeometry.swift`** — also the location of the `DriftMotesKernelConstants` enum and the `DriftMotesConfig` struct (16 floats / 64 bytes) bound at compute buffer(4). All wind/damping/turbulence/bounds/life-range tuning lives in Swift; the kernel reads from the config buffer. Any DM.2 retuning of these values happens on the Swift side, not in the kernel.
10. **`PhospheneEngine/Sources/Renderer/Geometry/ParticleGeometryRegistry.swift`** — the new dispatch surface. `knownPresetNames` lists every particle preset; `VisualizerEngine.resolveParticleGeometry(forPresetName:)` is the single call site that maps name → conformer. DM.2 doesn't need to register anything new (Drift Motes was registered in the post-DM.1 cleanup).
11. **`PhospheneEngine/Sources/Renderer/Geometry/Particle.swift`** — the struct. Task 0b verifies whether it has a usable hue slot.
12. **`PhospheneEngine/Sources/Presets/Shaders/Utilities/Volume/LightShafts.metal`** — `ls_radial_step_uv` declarations and helpers.
13. **`PhospheneEngine/Sources/Presets/Shaders/Utilities/Volume/ParticipatingMedia.metal`** — `vol_density_height_fog` declaration.
14. **`PhospheneEngine/Sources/Presets/Shaders/VolumetricLithograph.metal`** — canonical D-019 implementation. Read the melody-primary blend line and the drum-strobe FV-fallback line for the pattern.
15. **`docs/SHADER_CRAFT.md` §V.2 light shafts** — `ls_radial_step_uv` parameter contract, sun-anchor convention.
16. **`PhospheneEngine/Sources/Presets/Shaders/Common.metal`** — `hsv2rgb` is here, used for color conversion.

---

## Prerequisites — verify before starting (Task 0)

The post-DM.1 review produced an in-flight cleanup pass. **Do not start DM.2 work until you confirm the following are in the tree.** If any are missing, STOP and report.

```bash
# Wind/damping single source of truth — DriftMotesKernelConstants enum + DriftMotesConfig at buffer(4)
grep -nE "DriftMotesKernelConstants|DriftMotesConfig" \
  PhospheneEngine/Sources/Renderer/Geometry/DriftMotesGeometry.swift
# Both names should appear; the enum holds the Swift-side constants and
# DriftMotesConfig is the GPU struct bound at compute buffer(4).

grep -nE "buffer\(4\)|setBuffer.*index:[ ]*4" \
  PhospheneEngine/Sources/Renderer/Geometry/DriftMotesGeometry.swift \
  PhospheneEngine/Sources/Presets/Shaders/ParticlesDriftMotes.metal
# The config buffer must be bound on the Swift side and read in the kernel.

# Confirm the hardcoded steady-state-velocity literal from DM.1's init is gone
grep -nE "SIMD3.*-1.*-0\.2.*0.*1\.0198" \
  PhospheneEngine/Sources/Renderer/Geometry/DriftMotesGeometry.swift
# Empty.

# Magic-string preset name — single SSOT on the conformer
grep -nE 'presetName.*=.*"Drift Motes"' \
  PhospheneEngine/Sources/Renderer/Geometry/DriftMotesGeometry.swift
# Exactly one hit.

grep -nrE '"Drift Motes"' PhospheneEngine/Sources/ PhospheneApp/ \
  --include='*.swift'
# At most 2 hits total: the SSOT declaration and (if present) the registry's
# knownPresetNames entry. Any other occurrence is a regression.

# Dispatch registry + test landed
test -f PhospheneEngine/Sources/Renderer/Geometry/ParticleGeometryRegistry.swift \
  && echo "registry present" || echo "MISSING"
test -f PhospheneEngine/Tests/PhospheneEngineTests/Renderer/Presets/ParticleDispatchRegistryTests.swift \
  && echo "dispatch test present" || echo "MISSING"

grep -nE "resolveParticleGeometry\(forPresetName:" \
  PhospheneApp/VisualizerEngine.swift PhospheneApp/VisualizerEngine+Presets.swift
# Single dispatch site. Should appear in exactly one applyPreset .particles branch.

# `(void)totalStemEnergy;` removed (and replaced with `(void)stems;` per cleanup)
grep -nE "\(void\)totalStemEnergy" \
  PhospheneEngine/Sources/Presets/Shaders/ParticlesDriftMotes.metal
# Empty.

# Tier-aware particle count via factory `tier:` parameter
grep -nE "tier1ParticleCount|tier2ParticleCount" \
  PhospheneEngine/Sources/Renderer/Geometry/DriftMotesGeometry.swift
# Both constants present (400 and 800 respectively).

grep -nE "makeDriftMotesGeometry\(tier:" \
  PhospheneApp/VisualizerEngine.swift PhospheneApp/VisualizerEngine+Presets.swift
# Factory called with explicit tier: argument at the dispatch site.

# DriftMotesNonFlockTest threshold either tightened (spawn-distribution
# tuned) or D-098 filed in DECISIONS.md
grep -nE "D-098" docs/DECISIONS.md
# Either D-098 is in DECISIONS.md, or the test thresholds are at 0.95.
```

If any check fails, **STOP**. Report which prerequisite is missing and exit. DM.2 cannot land on a dirty DM.1 baseline.

### Task 0b — Verify `Particle` struct extension question. STOP-CONDITION.

Read `PhospheneEngine/Sources/Renderer/Geometry/Particle.swift`. The struct is 64 bytes per the design doc.

**You must decide one of two paths before writing any DM.2 code:**

**Path A — Existing slot is reusable.** The struct has an existing `color` / `hue` / equivalent field that Murmuration's path tolerates being written to (Murmuration ignores it on read, OR Murmuration writes it on emit and Drift Motes can match the layout). Confirm by:
- Reading the field's usage in `Particles.metal` (Murmuration's kernel) — must not be a load-bearing read that Drift Motes' write semantics would corrupt.
- Reading the field's initialization in `ProceduralGeometry.swift` — must not assume a value Drift Motes cannot honor.

If Path A: document the field name and its agreed semantics in a comment on `Particle.swift`, then proceed.

**Path B — Extension required.** Adding a hue field requires growing the struct or repurposing a field whose Murmuration semantics conflict.

If Path B: **STOP**. This is a cross-cutting change touching `Particle.swift`, `Particles.metal`, `ParticlesDriftMotes.metal`, the Swift conformers, and (likely) the engine's compute encode bindings. It must ship as a separate increment (call it DM.1.5) gated by a Murmuration `PresetRegressionTests` bit-identical pass, before DM.2 resumes. Write the increment plan in `docs/ENGINEERING_PLAN.md` and exit.

**Do not start the audio routing or shaft work without resolving Task 0b.**

---

## Tasks

### Task 1 — Per-particle hue baking with D-019 warmup blend

**File:** `PhospheneEngine/Sources/Presets/Shaders/ParticlesDriftMotes.metal` (compute kernel, particle-respawn branch).

The hue is baked at emission time and stored in the slot identified in Task 0b. It does NOT change frame-to-frame — once a particle is born it carries its emission-moment hue for life.

**Two sources, one D-019 blend:**

```metal
// Stem-warm hue source: vocals pitch in Hz → hue ∈ [0, 1].
// Map: A2 (110 Hz) → red (0.0); A6 (1760 Hz) → red again (1.0, full octave wrap).
// Use log2(pitchHz / 110.0) / 4.0, fract'd, with a small confidence gate.
float pitchHueWarm = ...;  // see implementation note below

// FV-proxy hue source for the cold-stems window. Use a deterministic
// per-particle hash to give the field intrinsic chromatic texture even
// when stems are zero, modulated lightly by a continuous FV driver so
// the field still moves with the music.
//   baseAmberHue = 0.08    // warm amber, matches DM.1 sky
//   perMoteJitter = (hash_f01(particleIndex * 17u + frameSeed) - 0.5) * 0.10
//   musicShift = f.mid_att_rel * 0.04
// Total fallback hue = baseAmberHue + perMoteJitter + musicShift, clamped.
float pitchHueCold = ...;

// D-019 blend at emission time, evaluated once per born particle.
float blend = smoothstep(0.02, 0.06, totalStemEnergy);
float bakedHue = mix(pitchHueCold, pitchHueWarm, blend);

// Saturation/value for the warm-amber palette (DM.1 baseline).
particle.colorRGB = hsv2rgb(float3(bakedHue, 0.55, 0.85));
```

**Implementation note on `pitchHueWarm`:**
- `vl_pitchHueShift` was retired (see DECISIONS.md line 368). DM.2 establishes the new canonical pitch→hue function for the project. Place it in the kernel file as a `static inline` helper named `dm_pitch_hue(float pitchHz, float confidence)` so future presets can adopt the pattern by name.
- Returns `0.08` (the cold-stem amber) when `confidence < 0.3` so noisy pitch readings don't pollute the field.
- Otherwise returns `fract(log2(max(pitchHz, 80.0) / 110.0) / 4.0)`.

**On constant placement (read this before writing magic numbers).** The post-DM.1 cleanup landed `DriftMotesConfig` at compute buffer(4) as the Swift-owned source of truth for kernel tuning. Inline magic numbers in the Metal kernel now regress that pattern unless the value is genuinely shader-local. For the hue work, the split is:
- **Inline (visual identity, not tuning knobs):** `baseAmberHue = 0.08`, the pitch curve constants `80.0` / `110.0` / `4.0`, the HSV saturation `0.55` and value `0.85`. These define what Drift Motes *is* — change them and the preset's identity changes. They belong in the kernel.
- **Inline for DM.2, hoist to `DriftMotesConfig` in a follow-up if you want to tune them:** the `perMoteJitter` amplitude (`0.10`) and the `musicShift` gain (`0.04`). These are real tuning knobs. Adding two `Float` fields to a 16-float / 64-byte config buffer is a layout change that ripples through the Swift struct + Metal struct + binding alignment + any size-asserting tests; doing it mid-DM.2 is more invasive than the value warrants. Land DM.2 with them inline; if Matt wants to tune them post-landing without recompiling the shader, hoist as a small follow-up increment.

**Done when:**
- `dm_pitch_hue` defined, takes `vocalsPitchHz` and `vocalsPitchConfidence` from `StemFeatures`.
- Cold-stem fallback uses per-particle hash + `f.mid_att_rel` proxy, no absolute thresholds (D-026).
- D-019 blend is `smoothstep(0.02, 0.06, totalStemEnergy)` and evaluated at emission only.
- Hue is written to the Task 0b-identified slot at emission and never modified afterward.
- The `(void)stems;` placeholder line from the post-DM.1 cleanup is removed — the kernel now reads stems for real, so the placeholder is no longer needed (and would be a SwiftLint-style smell on the Metal side). The header comment that explained it ("DM.1: no stem reads. DM.2 introduces the D-019 warmup-guarded blend.") should also be updated to describe the post-DM.2 reality.

### Task 2 — Light shaft via `ls_radial_step_uv`

**Files:** the sky/scene fragment shader in `ParticlesDriftMotes.metal` (the function that DM.1 wrote the warm-amber gradient into).

Light shaft is screen-space, layered into the existing sky fragment. **Do not add a new render pass.** D-029: pass set stays `["feedback", "particles"]`.

- **Sun anchor.** UV `(−0.15, 1.20)` — off-screen upper-left, gives the ≈30° from-vertical shaft direction the design specifies.
- **Steps.** 32 (default). 64 if profiling shows it's needed and budget allows.
- **Intensity.** `0.65 + 0.25 × f.mid_att_rel` — continuous (not beat-driven). `mid_att_rel` is the smoothed melody envelope; the shaft "breathes" with vocal energy. D-026-compliant.
- **Color.** Warm gold `(1.00, 0.78, 0.45)`, multiplied by intensity.
- **Composite.** Additive on top of the existing sky gradient.

**Done when:**
- `ls_radial_step_uv` invoked from the sky fragment with the parameters above.
- Shaft visible in static render (zero audio); becomes brighter under melody-rich content.
- No new render pass added; pass set still `["feedback", "particles"]`.

### Task 3 — Floor fog via `vol_density_height_fog`

**Files:** same fragment as Task 2.

- **Scale.** `12.0` (controls the fog layer thickness in world units; tune against design-doc reference image `07_atmosphere_dust_motes_light_shaft.jpg`).
- **Falloff.** `0.85` (exponential falloff).
- **Color.** Cool desaturated blue-gray `(0.18, 0.20, 0.24)` — pulls the lower frame toward shadow so the shaft has something to cut through. DM.1's warm-amber sky stays in the upper frame.
- **Composite.** Multiplied into the sky-gradient lower band before the shaft is added on top, so the shaft visually "punches through" the fog layer.

**Done when:**
- Fog layer rendered, visible in lower portion of frame.
- Shaft + fog read as coherent atmosphere — the beam should look like it's *cutting through haze*, not floating in vacuum.

### Task 4 — Per-mote brightness modulation from shaft intersection

**File:** `ParticlesDriftMotes.metal` sprite fragment.

Each particle's screen-space distance from the shaft axis modulates its brightness. Motes inside the shaft glow brightly; motes outside dim toward the floor-fog luminance.

```metal
// Compute screen-space distance from particle to shaft axis.
// Sun anchor: UV (-0.15, 1.20). Shaft axis: vector from sun anchor through
// frame center (0.5, 0.5). Use perpendicular distance.
float2 sunUV = float2(-0.15, 1.20);
float2 shaftDir = normalize(float2(0.5, 0.5) - sunUV);
float2 toMote = particleUV - sunUV;
float alongShaft = dot(toMote, shaftDir);
float perpDist = length(toMote - alongShaft * shaftDir);

// Inside-shaft falloff: full brightness at perpDist=0, dim at perpDist=0.25.
float shaftLit = exp(-perpDist * perpDist * 16.0);

// Final brightness: baseline + shaft-lit boost.
float brightness = 0.45 + shaftLit * 0.85;
```

**Done when:**
- Sprite fragment reads its UV position and computes perpendicular distance to the shaft axis.
- Brightness modulated by shaft proximity — inside the shaft, motes are 1.3× brighter than outside.
- The visual reading is "the beam picks out individual motes as they cross it."

### Task 5 — Respawn-determinism test

**File (new):** `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/Presets/DriftMotesRespawnDeterminismTest.swift`

Hue is baked at emission and persists for the particle's lifetime. The test verifies:

1. **Within-life invariance.** Capture `colorRGB` of a specific particle slot at frame N. Step the kernel forward without triggering a respawn. At frame N+30, `colorRGB` for that slot must be bit-identical.
2. **Respawn does change hue.** Same particle slot, but force respawn between captures (drive lifetime to zero). At frame N+respawn, `colorRGB` for that slot must differ (or, with non-zero probability, equal — but the *distribution* over many respawns must show variation).
3. **Cold-stems vs warm-stems variance.** Run the kernel for 60 frames with `StemFeatures.zero` and capture all particle hues. Run again with realistic stems (vocals pitch sweeping). Hue variance in the warm case must exceed cold-case variance by a factor of at least 2× — proves the D-019 blend is contributing real signal.

Use the existing `DriftMotesNonFlockTest` as a structural template for kernel invocation.

**Done when:**
- Three test cases pass.
- Test runs in `swift test --filter DriftMotesRespawnDeterminism` in under 5 seconds.

### Task 6 — Update `DriftMotesNonFlockTest` if spawn distribution was tuned

The DM.1 review noted the 80%/85% threshold loosening came from a cube → top-slab transient that's resolved if Matt picked spawn-distribution tuning over filing D-098.

- If `D-098` exists in `docs/DECISIONS.md`: the test threshold stays at 0.80/0.85; verify the test still asserts the right thing and the comment cites `D-098`.
- If `D-098` does NOT exist (Matt picked spawn tuning): tighten the centroid-spread RMS threshold back to 0.95 and the pairwise-distance threshold to 0.95. The seeded distribution should now match steady-state, so the transient is gone.

**Done when:**
- The test's threshold matches the prerequisite outcome from Task 0.
- Test still passes.

### Task 7 — Regenerate Drift Motes golden hash + rewrite the doc comment

The post-DM.2 hash will not be `0x8000000000008000`. The "single bit set in a structured location" doc comment from DM.1 was a baseline-specific artifact and must not be carried forward.

- Regenerate the three Drift Motes fixtures (steady, beatHeavy, quiet) by running `swift test --filter PresetRegressionTests` once, capturing the new hashes from the failure output, and pasting them in.
- Rewrite the doc comment to describe the new visible behavior: "Drift Motes regression fixtures capture the warm-amber sky + light-shaft + floor-fog backdrop with motes from a deterministic-seeded particle field. Per-mote hue varies in the beat-heavy fixture due to non-zero stems energy crossing the D-019 blend threshold; the steady and quiet fixtures fall in the cold-stems regime so per-mote hue is hash-jittered amber only."

**Done when:**
- New hashes committed.
- Doc comment rewritten.
- `PresetRegressionTests` passes for all three Drift Motes fixtures.
- **Critical: Murmuration's three regression hashes are bit-identical to the DM.1 baseline.** This is the same invariant DM.0 and DM.1 enforced. If Murmuration's hash drifts, you accidentally modified `Particles.metal` or `ProceduralGeometry.swift` — revert and re-approach.

### Task 8 — Performance measurement

Run a 30-second capture against the procedural-audio fixture (the soak harness's sine sweep + 120 BPM kicks input — same fixture used in 7.1) with Drift Motes selected on Tier 2.

```bash
SOAK_TESTS=1 swift test --package-path PhospheneEngine \
  --filter SoakTestHarnessTests.shortRunDriftMotes
```

(You'll need to add a `shortRunDriftMotes` variant to `SoakTestHarnessTests` that runs a 30-second capture with Drift Motes as the active preset. Use the existing `shortRunSmoke` test as a template.)

Report in the commit message and in the engineering plan landing block:
- p50 frame time
- p95 frame time
- p99 frame time
- Drop count

Compare against the architecture-contract targets: **1.6 ms Tier 2, 2.1 ms Tier 1**. If p95 exceeds the target by more than 20%, file a follow-up issue. Do not block landing on it — DM.3 has a wider performance budget once emission-rate scaling is in.

If profiling on Tier 1 hardware isn't available in the session environment, report Tier 2 only and note the Tier 1 result as deferred to first hardware run.

**Done when:**
- Performance numbers reported in the landing block.
- If over budget, follow-up issue filed.

### Task 9 — Documentation

- **`docs/ENGINEERING_PLAN.md`**: add the `### Increment DM.2 ✅ landed <date>` block at the end of active increments. Include performance numbers, test count delta, list of touched files.
- **`docs/CLAUDE.md`**:
  - Add Drift Motes to the Module Map under Shaders, with one-paragraph behavioral summary mentioning shaft/fog/per-particle hue baking and D-019 fallback.
  - Note the new `dm_pitch_hue` helper as the canonical pitch→hue replacement for the retired `vl_pitchHueShift`.
- **`docs/DECISIONS.md`**: only if a sub-decision surfaces during the session. Likely candidates: pitch→hue mapping curve (octave wrap vs linear); shaft sun-anchor position. If you choose values different from this prompt's recipe, file a short decision (D-099+).

**Done when:**
- Landing block in engineering plan with full implementation summary.
- Module Map entry for Drift Motes complete.
- Any deviations from this prompt's recipe documented as a numbered decision.

---

## Verification (run all before declaring done)

```bash
# Build clean (engine + app)
swift build --package-path PhospheneEngine
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

# Full engine test suite — count must match prior baseline + DM.2 deltas
swift test --package-path PhospheneEngine

# Targeted Drift Motes coverage
swift test --filter DriftMotesNonFlockTest
swift test --filter DriftMotesRespawnDeterminism
swift test --filter PresetRegressionTests

# Murmuration invariant — bit-identical hashes preserved
swift test --filter PresetRegressionTests.murmuration

# Lint
swiftlint lint --strict --config .swiftlint.yml

# Required grep checks
# 1. No D-026 violations introduced
grep -nE "smoothstep\([0-9.]+,[ ]*[0-9.]+,[ ]*f\.bass[^_]|f\.mid[^_]|f\.treb[^_]" \
  PhospheneEngine/Sources/Presets/Shaders/ParticlesDriftMotes.metal
# Empty — must use _rel/_dev/_att_rel forms.

# 2. D-019 blend is present
grep -nE "smoothstep\(0\.02,[ ]*0\.06,[ ]*totalStemEnergy\)" \
  PhospheneEngine/Sources/Presets/Shaders/ParticlesDriftMotes.metal
# Non-empty — at least one match.

# 3. Pass set unchanged (D-029)
grep -nE "passes" PhospheneEngine/Sources/Presets/Library/DriftMotes.json
# Must show ["feedback", "particles"] only.

# 4. No new render pass introduced
grep -nE "RenderPass\.|case lightShaft|case fog" \
  PhospheneEngine/Sources/Renderer/RenderPipeline*.swift
# Should match the pre-DM.2 baseline. No new cases.

# 5. Murmuration source files untouched
git diff DM.1-baseline -- \
  PhospheneEngine/Sources/Presets/Shaders/Particles.metal \
  PhospheneEngine/Sources/Renderer/Geometry/ProceduralGeometry.swift \
  PhospheneEngine/Sources/Renderer/Geometry/ParticleGeometry.swift \
  PhospheneEngine/Sources/Renderer/RenderPipeline*.swift
# Empty diff for all four. If any line changed, you broke the DM.0 contract.
```

---

## Out-of-scope (defer to DM.3)

- Emission-rate audio coupling (`f.mid_att_rel` → spawn rate).
- Drum dispersion shock (`stems.drums_beat` → outward-radial impulse).
- Structural-flag scatter (section change → field reset / convergence).
- Adding `mv_warp` to the pass set (D-029 forbids it for particle systems).
- Migrating `Particles.metal` (Murmuration's path) for any reason — D-020 architecture discipline.
- Adding a new render pass for the shaft or fog (they layer into the existing sky fragment).
- Tier 1 performance tuning beyond the device-tier-aware particle count already in the prerequisite.

If you reach for any of these, you're running ahead. Stop and surface the question.

---

## Critical invariants — these break the build if violated

- **Murmuration's `PresetRegressionTests` dHash bit-identical to DM.1 baseline.** Same invariant DM.0 and DM.1 enforced. If Murmuration's hash drifts, you modified shared paths.
- **Pass set stays `["feedback", "particles"]`** (D-029).
- **D-026 deviation form** for any new audio reactivity. No `smoothstep(0.22, 0.32, f.bass)` or equivalent absolute-threshold patterns.
- **D-019 warmup blend** wherever stems are read. The kernel must work at `StemFeatures.zero` without going hue-flat.
- **No shared-path edits.** `Particles.metal`, `ProceduralGeometry.swift`, `ParticleGeometry.swift`, and `RenderPipeline*.swift` must be byte-identical to their DM.1 state for the engine source files (the only exception is the DM.1.5 escape hatch from Task 0b, which terminates DM.2).
- **Filename `ParticlesDriftMotes.metal`** stays as-is. The lexicographic-ordering forcing function from DM.1 is still in effect; renaming will break shader concatenation.

---

## Commit cadence

Per `CLAUDE.md` commit format: `[<increment-id>] <component>: <description>`. Multiple small commits over one large commit. Suggested cadence for DM.2:

```
[DM.2] DriftMotes: dm_pitch_hue helper + cold-stems fallback
[DM.2] DriftMotes: D-019 blend wired at emission, hue baked
[DM.2] DriftMotes: ls_radial_step_uv shaft in sky fragment
[DM.2] DriftMotes: vol_density_height_fog floor layer
[DM.2] DriftMotes: per-mote brightness modulation from shaft
[DM.2] Tests: DriftMotesRespawnDeterminismTest
[DM.2] Tests: regenerate Drift Motes golden hashes + rewrite doc
[DM.2] Tests: tighten DriftMotesNonFlockTest threshold (if applicable)
[DM.2] Perf: 30s soak harness short-run for Drift Motes
[DM.2] Docs: ENGINEERING_PLAN landing block; CLAUDE.md Module Map
```

After each commit, push. Do not batch.

---

## Done-when (overall session gate)

DM.2 is complete when **all** of the following are true:

- [ ] Task 0a prerequisites all verified present in tree.
- [ ] Task 0b resolved with documented Path A or terminated with Path B (DM.1.5 plan written).
- [ ] All tasks 1–9 complete with their individual done-when satisfied.
- [ ] All verification commands pass (build, all tests, lint, all 5 grep checks).
- [ ] Murmuration hash bit-identical to DM.1 baseline.
- [ ] Performance numbers reported (p50/p95/p99 + drops).
- [ ] Drift Motes is selectable from the app's preset list and renders the new look (shaft + fog + hue-varied motes).
- [ ] In a track with vocals, hue diversity grows visibly over the first ~10 seconds as the D-019 blend opens. Confirm by eye on at least one real-music capture.
- [ ] All commits use `[DM.2]` prefix.
- [ ] Engineering plan has the `Increment DM.2 ✅ landed <date>` block.

If you hit a stop-condition (missing prerequisite from Task 0a, Path B from Task 0b, design-doc/code contradiction, Murmuration regression), **stop the session and report**. Do not work around it.

---

## After DM.2 lands

DM.3 wires:
- `f.mid_att_rel` → particle emission rate (more melody → more motes).
- `stems.drums_beat` → dispersion shock (drum onsets push the field outward radially).
- Structural-flag scatter (optional; depends on Phase 4 orchestrator output being plumbed).

DM.3 also takes the Tier 1 hardware performance measurement deferred from this session, if applicable.
