# Drift Motes — Session 1 (DM.1) Claude Code Prompt

You are implementing **Phase DM, Increment DM.1** for Phosphene: the foundation pass for a new preset called **Drift Motes**.

This is **Session 1 of 3**. Scope is strictly limited (see *Out-of-scope* below). Stop at the milestone gate; do not run ahead.

---

## Context — what you're building

Phosphene is a native macOS Apple-Silicon music visualizer. The catalog has 14 presets across families (waveform, fractal, geometric, particles, organic, etc.). Murmuration is the only existing **particles**-family preset, and it's a flocking simulation — particles seeking each other.

**Drift Motes inverts that.** Particles do **NOT** seek. They drift in a directional force field through a single dramatic god-ray light shaft. Wind blows. Sun catches them as they cross the beam. The aesthetic is cinematographic — Roger Deakins interior dust shaft; late-afternoon beam through pine canopy; morning shaft through cathedral window.

The compute kernel is intentionally short. The compositing is well-defined. The audio routing is conventional. This is a **lightweight-rubric** preset (D-067(b) — particle systems are exempt from the §12.1 detail-cascade and §12.3 PBR-oriented traits) and a **2–3 session** build.

**Session 1 produces a flocking-free particle field with a warm-amber sky backdrop, no audio coupling beyond the D-019 stem-warmup blend.** The light shaft, floor fog, per-particle hue baking, and audio routes all come in Session 2 and Session 3.

---

## Read first — canonical truth (read in this order)

1. **`docs/presets/DRIFT_MOTES_DESIGN.md`** — visual intent. Authoritative for what the preset *should look like*.
2. **`docs/presets/Drift_Motes_Rendering_Architecture_Contract.md`** — implementation contract. Authoritative for pass structure, blockers, certification fixtures, stop conditions, and per-session acceptance gates. **Section "Acceptance gates per phase → Session 1" is the gate this session must pass.**
3. **`docs/VISUAL_REFERENCES/drift_motes/README.md`** — annotated reference set. The single reference image `01_atmosphere_dust_motes_light_shaft.jpg` is the M7 frame-match anchor (visible only in Session 3 review, but worth opening now to internalize the target).
4. **`CLAUDE.md`** — implementation facts (buffer layouts, struct definitions, fragment buffer bindings, preamble compilation order). Pay specific attention to:
   - the `Particle` struct (64 bytes)
   - fragment buffer binding contract (buffer(0)..buffer(7))
   - `passes` field and the `["feedback", "particles"]` pipeline used by Murmuration
   - **D-019 (stem warmup blend), D-020 (architecture stays solid), D-026 (deviation primitives only)**
5. **`SHADER_CRAFT.md` §11 (file-length policy) and §14 (authoring cheat sheet).** Note that the cheat sheet's "minimum 3 distinct materials / triplanar projection" items are **waived** for lightweight-rubric particle presets per D-067(b); the relevant items for DM.1 are the noise-octave floor (≥4 in hero surface) and the no-`sin(time)` rule.
6. **`DECISIONS.md` D-029** — particle systems are incompatible with mv_warp; the only valid pass set is `["feedback", "particles"]`. Do not add mv_warp under any circumstance.

If any of these files are missing or contradict each other, **stop and ask**. The design doc may have an open question (§11) that Session 1 needs to resolve before code lands; flag it rather than guessing.

---

## Out-of-scope for this session — DO NOT IMPLEMENT

The contract is explicit about Session 1 boundaries. Do **not** implement these in DM.1:

- ❌ Light shaft (`ls_shadow_march` or `ls_radial_step_uv`) — Session 2
- ❌ Floor fog (`vol_density_height_fog`) — Session 2
- ❌ Per-particle hue baking from `vocalsPitchNorm` — Session 2
- ❌ Wind force scaling by `f.bass_att_rel` — Session 3 (Session 1 uses *base* wind only)
- ❌ Emission rate scaling by `f.mid_att_rel` — Session 3 (Session 1 uses *fixed* emission rate)
- ❌ Backdrop palette tinting by `f.valence` — Session 3 (Session 1 uses *fixed* warm gradient)
- ❌ Drum dispersion shock from `stems.drums_energy_dev` — Session 3
- ❌ Anticipatory shaft pulse on `f.beat_phase01` — Session 3
- ❌ `mv_warp` pass — never (D-029)

The **only** audio coupling permitted in DM.1 is the **D-019 stem-warmup blend itself** — code that reads `stems.*` must guard with `smoothstep(0.02, 0.06, totalStemEnergy)` so Session 2 can wire the per-particle hue path without restructuring. Beyond that, the particle field is fully audio-independent at DM.1.

If you find yourself reaching for `f.bass_att_rel` or `f.mid_att_rel` outside the warmup guard, **stop**. That's Session 3.

---

## Reference infrastructure to study (read, don't modify)

Before writing any new code, read these existing files to understand the precedents:

- **`PhospheneEngine/Sources/Presets/Shaders/Particles.metal`** — Murmuration's particle compute kernel + sprite render. The `Particle` struct definition lives here or in a shared header; verify before writing the DM kernel. The DM compute kernel is a *simpler* version of the same pattern (no flocking, no neighbor query, no boid forces).
- **`PhospheneEngine/Sources/Presets/Shaders/Starburst.metal`** — adjacent reference for a feedback-pass preset; useful for understanding how `["feedback", "particles"]` composes.
- **`PhospheneEngine/Sources/Presets/Shaders/Utilities/Noise/`** (V.1) — `curl_noise.metal` is the turbulence source. Understand its API: `float3 curl_noise(float3 p)` returns a divergence-free vector field at point `p`.
- **`PhospheneEngine/Sources/Presets/Shaders/Utilities/Materials/`** — DO NOT use any cookbook material recipes in DM.1. Particle preset is emission-only; cookbook is irrelevant.
- **`PhospheneEngine/Sources/Presets/PresetCategory.swift`** — verify `particles` is a member of the enum. The Crystalline Cavern review found this enum to be:
  ```
  waveform, fractal, geometric, particles, hypnotic, supernova, reaction,
  drawing, dancer, transition, abstract, fluid, instrument, organic
  ```
  `particles` should be present (Murmuration uses it). If absent, **stop** and report — that's a separate increment.
- **`PhospheneEngine/Sources/Presets/PresetLoader.swift`** — preset loader entry point. Understand how it discovers `.metal` + `.json` pairs in the `Shaders/` directory.
- **An existing preset's `.json` sidecar** — read **`Gossamer.json`** specifically (not the JSON template in the design doc). The design-doc JSON in `DRIFT_MOTES_DESIGN.md §10` was drafted before the real schema was confirmed and uses `id`/`feedback` wrapper fields that may not match the actual schema. The real schema has top-level `name`, `description`, `author`, `duration`, `fragment_function`, `vertex_function`, `beat_source`, top-level `decay`. **Use `Gossamer.json` as the schema source of truth, not the design doc.**

---

## Files to create / modify

**Create:**

1. `PhospheneEngine/Sources/Presets/Shaders/DriftMotes.metal` — vertex/fragment shaders for sky backdrop and sprite render + compute kernel.
2. `PhospheneEngine/Sources/Presets/Shaders/DriftMotes.json` — preset sidecar matching `Gossamer.json` schema (NOT the design-doc template).
3. `PhospheneEngine/Tests/PhospheneEngineTests/DriftMotesTests.swift` — Swift test file with `DriftMotesNonFlockTest`.

**Modify:**

4. `CLAUDE.md` — add DM.1 row to the preset table; document any new struct fields or buffer bindings introduced (only if the existing `Particle.color` slot is insufficient — see Task 2 below).

**Do NOT modify in DM.1:**

- `PhospheneEngine/Sources/Presets/Shaders/Particles.metal` (unless extending `Particle` is unavoidable — see Task 2 stop-condition).
- `ENGINEERING_PLAN.md` — increment landing notes are added at increment *completion*, not during. Add an `Increment DM.1` section at the very end of the session (Task 9), following the format of an existing completed increment (e.g. `Increment SB.0`).
- `DECISIONS.md` — only update if a decision needs recording (e.g. struct extension). Default expectation for DM.1 is no decisions land.

---

## Tasks

### Task 1 — Verify family enum and JSON schema

1.1 Open `PhospheneEngine/Sources/Presets/PresetCategory.swift`. Confirm `particles` is a member.
- **Done when:** `grep '"particles"' PhospheneEngine/Sources/Presets/PresetCategory.swift` returns a match. If not, stop and ask.

1.2 Open `PhospheneEngine/Sources/Presets/Shaders/Gossamer.json`. Note the top-level field names exactly as they appear.
- **Done when:** you have a list of required top-level fields. The design doc's `DRIFT_MOTES_DESIGN.md §10` template will be **rewritten** in Task 7 to match this real schema; do not copy the design-doc template verbatim.

### Task 2 — Verify `Particle` struct capacity

2.1 Locate the `Particle` struct definition (likely in `PhospheneEngine/Sources/Presets/Shaders/Particles.metal` or a shared header). Count its size and identify the `color` field.
- **Done when:** you can answer:
  - Total struct size in bytes (must be 64 per `CLAUDE.md`).
  - Type and width of the `color` field.

2.2 Determine whether the existing `color` field can carry baked hue + saturation + value separately, or if Session 2 will need to extend the struct.

This is **open question §11.1 in `DRIFT_MOTES_DESIGN.md`**. Session 1 does NOT bake hue, but Session 2 will, so the answer affects whether Session 1 should reserve any field bits.

- **Done when:** one of these outcomes is recorded as a comment in `DriftMotes.metal` header:
  - **(a) Existing `color` field is sufficient** — record the pixel format (e.g. "packed RGBA8 — Session 2 will pack hue×saturation into RG and value×alpha into BA").
  - **(b) Existing field is insufficient** — STOP. Do not extend `Particle` in Session 1. File the extension as a Session 2 prerequisite, document the constraint, and proceed with `default_warm_hue()` only for Session 1. Note the blocker explicitly in `DriftMotes.metal` header.

**Stop condition:** if extending `Particle` would break Murmuration (the shared particle path), do NOT extend in Session 1 or Session 2 inline. File a separate increment first (`DM.0` retroactively, or pivot Session 2 scope) and proceed with single-color `default_warm_hue()` for the entire Session 1 path.

### Task 3 — Compute kernel: force-field motion, NOT flocking

Implement the per-particle, per-frame compute kernel in `DriftMotes.metal`. The kernel must:

3.1 Take inputs: `device Particle*`, `constant FeatureVector&`, `constant StemFeatures&`, `constant Uniforms&` (with `dt` and `time`), and `[[thread_position_in_grid]]`.

3.2 For each particle:
- Advance age by `dt`.
- If `age > life` OR `any(abs(position) > BOUNDS)`, **recycle**: respawn at `sample_emission_position(id, u.time)` (a deterministic position near the top of the shaft volume), reset velocity to a slow downward drift `float3(-0.05, -0.4, 0.0)`, set color to `default_warm_hue()` (NO pitch baking in Session 1), reset age, randomize life via `5.0 + 4.0 * hash_f01(id)`.
- Compute wind force: `float3 wind = normalize(float3(-1.0, -0.2, 0.0)) * 0.3` — **base wind only, no `f.bass_att_rel` scaling in Session 1**.
- Compute turbulence: `float3 turb = curl_noise(p.position * 0.6 + u.time * 0.1) * 0.15`.
- Integrate: `p.velocity = p.velocity * 0.97 + (wind + turb) * dt; p.position += p.velocity * dt;`
- **NO neighbor query. NO inter-particle force. NO drum shock.** Particles are independent.

3.3 Particle count: 800 (Tier 2) / 400 (Tier 1) per design §5.7. For Session 1, allocate the 800-particle buffer; tier scaling lives in the orchestrator and `complexity_cost` field, not the kernel.

3.4 `BOUNDS = float3(8.0, 8.0, 4.0)` is a starting guess; tune in Task 6 against visual harness output.

- **Done when:**
  - `DriftMotes.metal` compute kernel compiles cleanly under the existing preamble (V.1 noise tree includes `curl_noise`).
  - Particles spawn, drift, and recycle without flocking.
  - **No reads of `f.bass_att_rel`, `f.mid_att_rel`, `stems.drums_energy_dev`, or `stems.vocalsPitchHz` outside the warmup guard.**
  - Code review confirms zero neighbor-query loops, zero `for (j ...)` over particles, zero shared-memory boid forces.

### Task 4 — Sky backdrop fragment shader

Implement a fragment shader in `DriftMotes.metal` that draws the warm-amber vertical gradient:

```metal
fragment float4 sky_backdrop(VertexOut in [[stage_in]],
                              constant FeatureVector& f [[buffer(0)]]) {
    float t = in.uv.y;
    float3 top    = float3(0.05, 0.03, 0.02);
    float3 bottom = float3(0.10, 0.07, 0.04);
    float3 col = mix(top, bottom, t);
    return float4(col, 1.0);
}
```

- **NO `f.valence` tinting in Session 1** (that's Session 3).
- **NO stars, no shaft cone, no fog gradient** in this shader. Backdrop is the gradient only.

- **Done when:** sky backdrop renders as a clean warm-amber gradient with no other features. Verify visually via the harness.

### Task 5 — Sprite render path

Implement the per-particle sprite render in `DriftMotes.metal`:

5.1 Vertex shader: read particle position from buffer, transform to clip space, output a 6-px-equivalent quad (point sprite or instanced quad — match Murmuration's pattern).

5.2 Fragment shader: render a soft Gaussian falloff. Tint by `default_warm_hue()` (a fixed warm amber, e.g. `float3(1.0, 0.7, 0.4)`). **No shaft-density modulation in Session 1** (that's Session 2). Brightness is a fixed scalar.

5.3 Additive blend over the sky backdrop.

- **Done when:**
  - Particle field is visible against the sky backdrop as soft warm-amber motes.
  - No banding, no hard edges on sprites (Gaussian falloff is smooth).
  - Frame rate is comfortably above 60 fps at 800 particles (Session 3 will profile properly; Session 1 just confirms no obvious performance cliff).

### Task 6 — Pass wiring

Connect the pieces into the `["feedback", "particles"]` pipeline:

6.1 In `DriftMotes.json`, declare `passes: ["feedback", "particles"]` and the standard top-level fields (per Task 1.2 — using the **real schema from `Gossamer.json`**, not the design-doc template).

6.2 Set `decay: 0.92` (top-level per real schema, not nested under `feedback`). `base_zoom: 0.0`, `base_rot: 0.0`.

6.3 `family: "particles"`. `complexity_cost: { tier1: 1.6, tier2: 2.1 }`. `certified: false`.

6.4 `rubric_profile: "lightweight"`.

6.5 Confirm `PresetLoader` picks up the new preset on app launch (no code change needed in PresetLoader; it scans the directory).

- **Done when:**
  - Drift Motes appears in the preset list at app launch.
  - Selecting Drift Motes renders the warm sky backdrop with drifting motes.
  - Feedback pass is producing faint trails (decay 0.92 — short trails, faint streaks during fast wind).

### Task 7 — Test: DriftMotesNonFlockTest

Implement the first preset-specific test in `DriftMotesTests.swift`.

7.1 Test setup: render the Drift Motes preset for 200 frames at the silence fixture (zero audio).

7.2 Sample 50 random particle pairs at frame 50 and at frame 200. For each pair, record the pairwise distance.

7.3 Assert: the *distribution* of pairwise distances does NOT contract from frame 50 to frame 200. Specifically — the median, mean, and 25th-percentile distance must each be ≥ 95% of their frame-50 values. Cohesion would manifest as all three contracting; the 5% tolerance allows for natural variance from recycle dynamics.

7.4 Test must pass deterministically — fixed RNG seed, fixed initial particle positions, fixed hash seeds.

- **Done when:**
  - `swift test --package-path PhospheneEngine --filter DriftMotesNonFlockTest` returns success.
  - Test failure mode is informative: prints frame-50 vs frame-200 distance distribution if the assertion fails (so a regression diagnoses cleanly).

### Task 8 — Visual harness contact sheet

Capture pass-separated contact sheets per the contract's "Minimum viable milestone" requirement:

8.1 Sky backdrop only (sprite render disabled).
8.2 Sprite render only (sky backdrop replaced with solid black).
8.3 Full composite (both).

These sheets are required for diagnostic review at the session boundary. Save under `tools/visual_harness/output/DM.1/`.

- **Done when:** all three sheets exist and are visually distinct. Sky-only is a clean gradient; sprite-only is dots on black; composite reads as the design intent.

### Task 9 — Engineering plan landing note

Add an `Increment DM.1` section at the end of `ENGINEERING_PLAN.md`'s active increments list, following the format of an existing completed increment (e.g. `Increment SB.0`):

- **Scope** — as defined in this prompt.
- **Done when** — concrete acceptance from the contract's Session 1 gate.
- **Verify** — the shell commands from the *Verification* section below.
- **Estimated sessions** — 1.0 (this session itself).
- **Status: ✅ landed YYYY-MM-DD** with the actual date.

---

## Verification (run before declaring complete)

```bash
# 1. Compile cleanly
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build

# 2. Existing tests still pass
swift test --package-path PhospheneEngine

# 3. The new test passes
swift test --package-path PhospheneEngine --filter DriftMotesNonFlockTest

# 4. PresetRegressionTests dHash table is unchanged for all OTHER presets
#    (Drift Motes adds a new entry; existing rows must be bit-identical)
swift test --package-path PhospheneEngine --filter PresetRegressionTests

# 5. Visual references lint passes
swift run --package-path PhospheneTools CheckVisualReferences --strict

# 6. Confirm zero D-026 violations and zero free-running sin(time)
grep -n "smoothstep([0-9.]*[, ][0-9.]*[, ]f\." \
  PhospheneEngine/Sources/Presets/Shaders/DriftMotes.metal
# (should return ZERO matches — no absolute thresholds against FeatureVector fields)

grep -n "sin\s*(\s*time\|sin\s*(\s*u\.time\|sin\s*(\s*f\.time" \
  PhospheneEngine/Sources/Presets/Shaders/DriftMotes.metal
# (should return ZERO matches — sin(time) is forbidden per Arachne tuning rule)

grep -n "for\s*(\s*uint\s*j\|for\s*(\s*int\s*j\|particles\[j" \
  PhospheneEngine/Sources/Presets/Shaders/DriftMotes.metal
# (should return ZERO matches — no neighbor queries; this would indicate flocking)
```

If **any** of these fail, do not commit. Fix the failure first.

---

## Anti-patterns — explicit failures to avoid

These are drawn from the design doc §6, the contract's "Stop conditions", and CLAUDE.md's failed-approaches log:

1. **Flocking behavior of any kind.** The non-flock property is the preset's identity. If the compute kernel contains a neighbor query, alignment force, cohesion force, or separation force, you are building Murmuration v2, not Drift Motes. Stop and re-read the contract.

2. **`sin(time)` motion.** Free-running `sin(u.time)` is forbidden across the catalog (CLAUDE.md Arachne tuning rule). All oscillation must be audio-anchored or `curl_noise(p, time)`-driven (where `time` is a phase advance into the noise field, not a visible oscillation).

3. **Reading `f.bass_att_rel`, `f.mid_att_rel`, `stems.drums_energy_dev`, `stems.vocalsPitchHz` outside the warmup guard.** Session 1 is audio-independent. Session 2/3 wires the audio routes. If you reach for these fields, you're running ahead.

4. **Constant emission rate that "looks lifeless".** This is a Session 3 concern (emission rate scales with `f.mid_att_rel`). For Session 1, the fixed rate is correct — the lifelessness is acceptable because Session 1 is a foundation milestone, not a final render.

5. **Beat-pulsing per-mote brightness.** Drum coupling is dispersion shock only (Session 3). Per-mote brightness must not flash on drums.

6. **Extending `Particle` if it breaks Murmuration.** See Task 2 stop-condition. If extension is needed and breaks the shared path, file a separate increment.

7. **Modifying `Particles.metal` (Murmuration's file) for "convenience".** D-020 architecture discipline: shared paths are not modified for single-preset convenience. If `Particles.metal` needs a change, the change must benefit *all* particle presets and ship as a separate increment.

8. **Adding mv_warp.** D-029 explicit incompatibility. The pass set is `["feedback", "particles"]`. Period.

---

## Commit cadence

Per the project convention (`CLAUDE.md` commit format): `[<increment-id>] <component>: <description>`.

Prefer **multiple small commits per increment** over one large commit. Suggested cadence for DM.1:

```
[DM.1] DriftMotes: scaffolding (.metal + .json + test stubs)
[DM.1] DriftMotes: compute kernel — force-field motion, no flocking
[DM.1] DriftMotes: sky backdrop fragment shader
[DM.1] DriftMotes: sprite render path with default warm hue
[DM.1] DriftMotes: pass wiring + PresetLoader integration
[DM.1] DriftMotes: DriftMotesNonFlockTest passes
[DM.1] Docs: ENGINEERING_PLAN landing note for DM.1
```

After each commit, push. Do not batch.

---

## Done-when (overall session gate)

DM.1 is complete when **all** of the following are true:

- [ ] All tasks 1–9 are complete with their individual done-when satisfied.
- [ ] All verification commands pass (build, all tests, lint, grep checks).
- [ ] Visual harness contact sheets exist under `tools/visual_harness/output/DM.1/`.
- [ ] Drift Motes is selectable from the app's preset list and renders without crashing.
- [ ] Particles drift, recycle, and **do not flock** (verified by automated test, not just visual review).
- [ ] All commits use `[DM.1]` prefix.
- [ ] Engineering plan has the `Increment DM.1 ✅ landed <date>` block at the end of active increments.

If you hit a stop-condition (Task 2 struct extension, Task 1.1 missing enum value, design-doc/code contradiction), **stop the session and report**. Do not work around it.

---

## After DM.1 lands

Session 2 (DM.2) wires the light shaft, floor fog, and per-particle hue baking from `vocalsPitchNorm`. Session 3 (DM.3) wires the full audio routing, the drum dispersion shock, the anticipatory shaft pulse, and the M7 frame-match review against `01_atmosphere_dust_motes_light_shaft.jpg`. Each subsequent session has its own prompt with its own scope and verification.

DM.1 is the foundation. Get the motion model right; everything downstream depends on it.
