# Drift Motes — Session 1 (DM.1, post-DM.0) Claude Code Prompt

You are implementing **Phase DM, Increment DM.1** for Phosphene: the foundation pass for a new particles-family preset called **Drift Motes**. This is **Session 1 of 3**.

DM.1 was paused once before — the original prompt assumed Murmuration's `["feedback", "particles"]` path was reusable infrastructure when it was a single-tenant Murmuration implementation. **DM.0 fixed that** by introducing a `ParticleGeometry` protocol; Murmuration's `ProceduralGeometry` is the first conformer. **DM.1 ships Drift Motes' own conformer** as a sibling. See D-097 in `docs/DECISIONS.md`.

Scope is strictly limited (see *Out-of-scope* below). Stop at the milestone gate; do not run ahead into Session 2 / 3 audio coupling.

---

## Context — what you're building

Phosphene's catalog has Murmuration as the only particles-family preset, a flocking simulation. **Drift Motes inverts that.** Particles do **NOT** seek. They drift in a directional force field through a single dramatic god-ray light shaft. Wind blows. Sun catches them as they cross the beam. The aesthetic is cinematographic — Roger Deakins interior dust shaft; late-afternoon beam through pine canopy; morning shaft through cathedral window.

The compute kernel is short. The compositing is well-defined. Audio routing is conventional. This is a **lightweight-rubric** preset (D-067(b) — particle systems are exempt from the §12.1 detail-cascade and §12.3 PBR-oriented traits) and a **2–3 session** build.

**Session 1 produces a flocking-free particle field with a warm-amber sky backdrop, no audio coupling beyond the D-019 stem-warmup blend.** The light shaft, floor fog, per-particle hue baking, and audio routes all come in Session 2 and Session 3.

---

## What changed at DM.0 (read first if you didn't run it)

DM.0 introduced [`ParticleGeometry`](PhospheneEngine/Sources/Renderer/Geometry/ParticleGeometry.swift) — an `AnyObject, Sendable` protocol with three members:

- `update(features:stemFeatures:commandBuffer:)` — per-frame compute dispatch
- `render(encoder:features:)` — per-frame render dispatch
- `activeParticleFraction: Float { get set }` — D-057 governor gate

Murmuration's `ProceduralGeometry` already conforms (the conformance was a one-line declaration; signatures matched). [`RenderPipeline.particleGeometry`](PhospheneEngine/Sources/Renderer/RenderPipeline.swift) is now `(any ParticleGeometry)?`; [`setParticleGeometry(_:)`](PhospheneEngine/Sources/Renderer/RenderPipeline+PresetSwitching.swift) accepts any conformer; [`VisualizerEngine.makeParticleGeometry`](PhospheneApp/VisualizerEngine.swift) returns `(any ParticleGeometry)?`.

**The factory has one branch today (Murmuration).** DM.1 adds the second branch and the second conformer.

---

## Read first — canonical truth (read in this order)

1. **`docs/DECISIONS.md` D-097** — particle preset architecture: siblings, not subclasses. Read the full decision body. The protocol surface is final; **do not extend it in DM.1** without a separate decision (that would be a Drift-Motes-specific feature creeping into shared infrastructure — Anti-pattern #1 from DM.0).
2. **`docs/presets/DRIFT_MOTES_DESIGN.md`** — visual intent. Authoritative for what the preset *should look like*.
3. **`docs/VISUAL_REFERENCES/drift_motes/Drift_Motes_Rendering_Architecture_Contract.md`** — implementation contract. Authoritative for pass structure, blockers, certification fixtures, stop conditions, and per-session acceptance gates. **Section "Acceptance gates per phase → Session 1" is the gate this session must pass.**
4. **`docs/VISUAL_REFERENCES/drift_motes/DRIFT_MOTES_README.md`** — annotated reference set. The single hero image `01_atmosphere_dust_motes_light_shaft.jpg` is the M7 frame-match anchor for Session 3. Worth opening now to internalize the target.
5. **`PhospheneEngine/Sources/Renderer/Geometry/ParticleGeometry.swift`** — the protocol you're conforming to. Three members, no extensions; surface is what conformers need to provide and nothing more.
6. **`PhospheneEngine/Sources/Renderer/Geometry/ProceduralGeometry.swift`** — Murmuration's conformer. **Reference only — DO NOT MODIFY.** Read it to understand the conformance pattern: how the buffer is allocated, how compute is encoded, how render is dispatched, how `activeParticleFraction` gates dispatch count.
7. **`PhospheneEngine/Sources/Renderer/Shaders/Particles.metal`** — Murmuration's MSL: `particle_update` compute kernel, `particle_vertex` / `particle_fragment` sprite render, **and the `Particle` struct definition.** **DO NOT MODIFY.** Drift Motes uses the same `Particle` struct (D-097 commits all conformers to the shared 64-byte layout).
8. **`PhospheneEngine/Sources/Presets/Shaders/Starburst.metal`** — Murmuration's sky-backdrop fragment shader. The sky and the particle compute live in different files for Murmuration (sky in preset library, compute in engine library). **Drift Motes mirrors that split** (see *Files to create* below).
9. **`PhospheneEngine/Sources/Presets/Shaders/Gossamer.json`** — schema source of truth. The design doc's `DRIFT_MOTES_DESIGN.md §10` template was drafted before the real schema was confirmed; use `Gossamer.json` as the schema.
10. **`PhospheneApp/VisualizerEngine.swift`** + **`PhospheneApp/VisualizerEngine+Presets.swift`** — particle-geometry lifecycle. `makeParticleGeometry` factory at line ~638; `applyPreset` `.particles` case at line ~169. Both need a Drift Motes branch.
11. **`CLAUDE.md`** — buffer-binding contract (fragment buffer 0..7), Particle struct documentation, preset metadata format, **D-019 (stem warmup blend), D-020 (architecture stays solid), D-026 (deviation primitives only), D-029 (mv_warp incompatible with particles), D-097 (siblings not subclasses)**. The "What NOT To Do" entry added at end of DM.0 documents the rule against parameterizing `ProceduralGeometry`.
12. **`SHADER_CRAFT.md` §11 (file-length policy) and §14 (authoring cheat sheet).** Note the cheat sheet's "minimum 3 distinct materials / triplanar projection" items are **waived** for lightweight-rubric particle presets per D-067(b); the relevant items for DM.1 are the noise-octave floor (≥4 in any non-trivial noise field) and the no-`sin(time)` rule.

If any of these files are missing or contradict each other, **stop and ask.**

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
- ❌ **Extending the `ParticleGeometry` protocol surface.** It's three members. If Drift Motes needs a fourth, that's a protocol-extension decision filed separately (D-097 carry-forward), not a DM.1 amendment.
- ❌ **Modifying `ProceduralGeometry` or `Particles.metal`.** Murmuration's path stays byte-identical; D-020 forbids modifying shared engine code for single-preset convenience.

The **only** audio coupling permitted in DM.1 is the **D-019 stem-warmup blend itself** — code that reads `stems.*` must guard with `smoothstep(0.02, 0.06, totalStemEnergy)` so Session 2 can wire the per-particle hue path without restructuring. Beyond that, the particle field is fully audio-independent at DM.1.

If you find yourself reaching for `f.bass_att_rel` or `f.mid_att_rel` outside the warmup guard, **stop**. That's Session 3.

---

## Resolved-from-DM.1's-prior-attempt — do not re-discover

The original DM.1 prompt asked you to verify a few things. DM.0 and the prior aborted DM.1 already answered them:

- **Family enum.** `particles` is at [`PresetCategory.swift:16`](PhospheneEngine/Sources/Presets/PresetCategory.swift:16). Murmuration uses it. Drift Motes will too.
- **JSON schema.** [`Gossamer.json`](PhospheneEngine/Sources/Presets/Shaders/Gossamer.json) is the schema. Top-level fields: `name`, `family`, `duration`, `description`, `author`, `passes`, `fragment_function`, `vertex_function`, `beat_source`, `decay`, `stem_affinity`, `visual_density`, `motion_intensity`, `color_temperature_range`, `fatigue_risk`, `transition_affordances`, `section_suitability`, `complexity_cost`, `certified`. **NO nested `feedback` wrapper. NO `id` field.** The `DRIFT_MOTES_DESIGN.md §10` template predates this schema; ignore it.
- **`Particle` struct capacity.** 64 bytes, defined in [`Particles.metal:21`](PhospheneEngine/Sources/Renderer/Shaders/Particles.metal:21) and [`ProceduralGeometry.swift:18`](PhospheneEngine/Sources/Renderer/Geometry/ProceduralGeometry.swift:18). The `color` field is `packed_float4` (4× Float32 RGBA). **Sufficient for both Murmuration and Drift Motes (Session 2 packs hue/saturation/value into the four lanes at emission and reconstructs RGB in the sprite fragment).** No struct extension. Open question §11.1 in the design doc is **resolved** — record this resolution as a comment in `DriftMotesGeometry.swift`'s header.
- **Architectural blocker.** Closed by DM.0. The `["feedback", "particles"]` pass is now multi-tenant via `ParticleGeometry`.

---

## Reference infrastructure to study (read, don't modify)

- **`PhospheneEngine/Sources/Renderer/Shaders/Particles.metal`** — Murmuration's compute + sprite + Particle struct. Defines `Particle` (64 bytes), `ParticleConfig` (32 bytes), `particle_update` (compute), `particle_vertex`/`particle_fragment` (sprite render). The `Particle` struct definition is what Drift Motes' MSL shares.
- **`PhospheneEngine/Sources/Renderer/Geometry/ProceduralGeometry.swift`** — the conformer pattern: factory init, buffer allocation, compute dispatch, render dispatch, `activeParticleFraction` field. Drift Motes' conformer follows the same shape with a different particle count, different config, and references to its own MSL function names.
- **`PhospheneEngine/Sources/Presets/Shaders/Starburst.metal`** — Murmuration's sky backdrop. Uses `fullscreen_vertex` (engine library) + `starburst_fragment` (preset library). Drift Motes' sky uses `fullscreen_vertex` + a new `drift_motes_sky_fragment`.
- **`PhospheneEngine/Sources/Presets/Shaders/Utilities/Noise/Curl.metal`** (V.1) — `curl_noise(float3 p)` returns a divergence-free vector field. The turbulence source for Drift Motes' compute kernel. Available in the preset preamble; **NOT** automatically available in the engine library.
- **`PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift`** — preamble compilation order. The preset preamble has `curl_noise` and friends; the engine library does not.
- **`PhospheneEngine/Sources/Renderer/ShaderLibrary.swift`** — engine library construction. The compute kernel needs to be in this library (or a separate library Drift Motes builds itself); see Task 4 for the implementation choice.
- **`PhospheneApp/VisualizerEngine+Presets.swift:67, 169`** — particle-geometry attach/detach lifecycle. `setParticleGeometry(nil)` clears at preset switch start; `case .particles:` re-attaches.

---

## Files to create / modify

**Create — engine code (1):**

1. **`PhospheneEngine/Sources/Renderer/Geometry/DriftMotesGeometry.swift`** — Swift class conforming to `ParticleGeometry`. Owns its own particle buffer (800 particles), compute pipeline state, render pipeline state. Mirrors `ProceduralGeometry`'s shape with Drift-Motes-specific tuning (no flocking, slow downward drift, recycle on bounds-exit or age expiry).

**Create — engine MSL (1):**

2. **`PhospheneEngine/Sources/Renderer/Shaders/DriftMotesParticles.metal`** — three MSL functions added to the **engine** library (sibling to `Particles.metal`):
   - `motes_update` — compute kernel (force-field integration, NOT flocking)
   - `motes_vertex` — sprite vertex shader
   - `motes_fragment` — sprite fragment shader (soft Gaussian falloff, default warm hue)

   This file does NOT redeclare `Particle` — it `#include`s nothing and relies on the shared struct in `Particles.metal` being compiled into the same library. **Verify the engine library compilation includes both files in one MSL translation unit before relying on this.** If the engine library compiles each `.metal` file as a separate translation unit, declare `Particle` here too (matching the layout in `Particles.metal` exactly), and document the duplication as a known compromise pending a shared MSL header.

**Create — preset code (2):**

3. **`PhospheneEngine/Sources/Presets/Shaders/DriftMotes.metal`** — sky-backdrop fragment shader (`drift_motes_sky_fragment`). Reads `FeatureVector` at fragment buffer(0). Returns warm-amber vertical gradient. **No particle code in this file** — that's in the engine MSL above.
4. **`PhospheneEngine/Sources/Presets/Shaders/DriftMotes.json`** — preset sidecar matching `Gossamer.json` schema. `passes: ["feedback", "particles"]`. `fragment_function: "drift_motes_sky_fragment"`. `vertex_function: "fullscreen_vertex"`.

**Create — tests (1):**

5. **`PhospheneEngine/Tests/PhospheneEngineTests/Presets/DriftMotesTests.swift`** — Swift test file with `DriftMotesNonFlockTest` (Task 8).

**Modify (3):**

6. **`PhospheneApp/VisualizerEngine.swift`** — `makeParticleGeometry` factory gains a Drift Motes branch (Task 5). The store member becomes one of: a per-preset dictionary, two named properties, or a per-preset descriptor lookup. **Pick one and document the choice** (see Task 5).
7. **`PhospheneApp/VisualizerEngine+Presets.swift`** — `applyPreset` `case .particles:` selects the right conformer based on the active preset's name (or family, or descriptor).
8. **`CLAUDE.md`** — add DM.1 row to the preset table; document any new MSL function names that the engine library now exports (matters for future `grep` reference).

**Do NOT modify in DM.1:**

- `PhospheneEngine/Sources/Renderer/Shaders/Particles.metal` — Murmuration's MSL. Byte-identical post-DM.1.
- `PhospheneEngine/Sources/Renderer/Geometry/ProceduralGeometry.swift` — Murmuration's conformer.
- `PhospheneEngine/Sources/Renderer/Geometry/ParticleGeometry.swift` — DM.0's protocol. Three members, no extensions.
- `PhospheneEngine/Sources/Renderer/RenderPipeline*.swift` — engine routing. Already typed `(any ParticleGeometry)?`; no further changes needed.
- `ENGINEERING_PLAN.md` — landing notes are added at increment *completion*, not during. Add an `Increment DM.1` block at session end (Task 10).
- `DECISIONS.md` — DM.1 is implementation, not a new decision. Default expectation: no new decision. If you discover something that warrants one (e.g. the engine-vs-preset MSL placement question turns out non-trivial), file as D-098 with a short body.

---

## Tasks

### Task 1 — Family enum & schema confirmation (mostly already done)

1.1 Open [`PresetCategory.swift`](PhospheneEngine/Sources/Presets/PresetCategory.swift). Confirm `particles` is still present. (DM.0 didn't touch this file; should still be at line 16.)
- **Done when:** `grep '"particles"' PhospheneEngine/Sources/Presets/PresetCategory.swift` returns a match.

1.2 Open `Gossamer.json`. Note the top-level field names exactly as they appear. Drift Motes' sidecar uses the same shape.
- **Done when:** you have a list of required top-level fields and have decided which ones Drift Motes will set vs use defaults for.

### Task 2 — `Particle` struct and conformer-MSL placement

2.1 Confirm the `Particle` struct in [`Particles.metal:21`](PhospheneEngine/Sources/Renderer/Shaders/Particles.metal:21) is 64 bytes (3+1+3+1+4+1+1+2 floats = 64 bytes). Confirm `packed_float4 color` is the 16-byte color slot.
- **Done when:** you've verified the layout matches DM.0's documented 64-byte / `packed_float4 color` shape. **DO NOT MODIFY THE STRUCT.**

2.2 Decide where `motes_update` / `motes_vertex` / `motes_fragment` MSL functions live. Two options, both acceptable:
- **(a) Engine library, sibling to Particles.metal.** Add `Renderer/Shaders/DriftMotesParticles.metal`. Compiles into the same engine library as `Particles.metal`; the `Particle` struct is already in scope. Murmuration's pattern. **Default choice.**
- **(b) Preset library, alongside the sky fragment.** Add the three functions to `Presets/Shaders/DriftMotes.metal`. Requires either (i) declaring `Particle` again in that file (small duplication, document it), or (ii) hoisting the struct into the preset preamble (DM.1-out-of-scope; defer).

Pick (a) unless you find a concrete reason during implementation. Document the choice in `DriftMotesGeometry.swift`'s file header.

- **Done when:** the placement decision is recorded; the relevant `.metal` file is created (empty body OK at this step) and compiles cleanly.

### Task 3 — Compute kernel: force-field motion, NOT flocking

Implement the per-particle, per-frame compute kernel.

3.1 Take inputs: `device Particle*`, `constant FeatureVector&` (buffer 1), `constant ParticleConfig&` (buffer 2 — same layout as Murmuration's), `constant StemFeatures&` (buffer 3), `[[thread_position_in_grid]]`. Mirror Murmuration's bindings exactly so the conformer's compute encoder doesn't drift.

3.2 For each particle:
- Advance age by `features.delta_time`.
- If `age > life` OR `any(abs(position) > BOUNDS)`, **recycle**: respawn at `sample_emission_position(id, time)` (a deterministic position near the top of the shaft volume), reset velocity to a slow downward drift `float3(-0.05, -0.4, 0.0)`, set color to `default_warm_hue()` (NO pitch baking in Session 1), reset age, randomize life via `5.0 + 4.0 * hash_f01(id)`.
- Compute wind force: `float3 wind = normalize(float3(-1.0, -0.2, 0.0)) * 0.3` — **base wind only, no `f.bass_att_rel` scaling in Session 1**.
- Compute turbulence: `float3 turb = curl_noise(p.position * 0.6 + u.time * 0.1) * 0.15`. **Note**: if you placed the kernel in the engine library (Task 2 option a), `curl_noise` is in the preset preamble, not the engine library. You'll need to either (i) port `curl_noise` into a small helper inside `DriftMotesParticles.metal` (a 5-line snake-noise gradient pair — see V.1 utility tree for the recipe), or (ii) move the kernel to the preset library (Task 2 option b). **This is a real surfacing point** — pick one and document.
- Integrate: `p.velocity = p.velocity * 0.97 + (wind + turb) * dt; p.position += p.velocity * dt;`
- **NO neighbor query. NO inter-particle force. NO drum shock.** Particles are independent.

3.3 Particle count: 800 (Tier 2) / 400 (Tier 1) per design §5.7. For Session 1, allocate the 800-particle buffer; tier scaling lives in the orchestrator and `complexity_cost` field, not the kernel.

3.4 `BOUNDS = float3(8.0, 8.0, 4.0)` is a starting guess; tune in Task 7 against visual harness output.

- **Done when:**
  - `motes_update` compiles cleanly in whichever library it lives in.
  - Particles spawn, drift, and recycle without flocking.
  - **No reads of `f.bass_att_rel`, `f.mid_att_rel`, `stems.drums_energy_dev`, or `stems.vocalsPitchHz` outside the warmup guard.**
  - Code review confirms zero neighbor-query loops, zero `for (j ...)` over particles, zero shared-memory boid forces.

### Task 4 — Sky backdrop fragment shader

Implement `drift_motes_sky_fragment` in `Presets/Shaders/DriftMotes.metal`:

```metal
fragment float4 drift_motes_sky_fragment(VertexOut in [[stage_in]],
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

### Task 5 — `DriftMotesGeometry` conformer + factory wiring

This is the central new piece.

5.1 **Create `DriftMotesGeometry.swift`.** Follow `ProceduralGeometry`'s shape:
- `public final class DriftMotesGeometry: ParticleGeometry, @unchecked Sendable`
- `init(device:library:configuration:pixelFormat:)` builds the particle buffer (800 × `MemoryLayout<Particle>.stride` = 51,200 bytes), compiles the compute pipeline state from `motes_update`, compiles the render pipeline state from `motes_vertex` + `motes_fragment` with **additive blending** (`sourceRGBBlendFactor = .one`, `destinationRGBBlendFactor = .one`).
- `update(features:stemFeatures:commandBuffer:)` — encode the compute pass, mirror `ProceduralGeometry.update`'s structure but with Drift Motes' kernel name.
- `render(encoder:features:)` — set the sprite render pipeline, bind the particle buffer at vertex buffer 0, draw N point primitives.
- `activeParticleFraction: Float = 1.0` — same governor gate as Murmuration.

5.2 **Particle initial state.** At init, place all 800 particles at random positions inside `BOUNDS` with zero velocity, randomized `life` ∈ [5.0, 9.0] s, fixed warm-amber color. Random seed deterministic (use particle index). Mirror `ProceduralGeometry`'s init pattern but without the golden-spiral disk distribution.

5.3 **Factory branch in `VisualizerEngine`.** Pick one shape:

   **Option A — two named properties (recommended for two-conformer state).**
   ```swift
   var murmurationGeometry: (any ParticleGeometry)?
   var driftMotesGeometry: (any ParticleGeometry)?

   // applyPreset .particles:
   let geometry: (any ParticleGeometry)? = switch desc.name {
       case "Murmuration": murmurationGeometry
       case "Drift Motes": driftMotesGeometry
       default: nil
   }
   pipeline.setParticleGeometry(geometry)
   ```

   **Option B — dictionary keyed by preset name.**
   ```swift
   var particleGeometries: [String: any ParticleGeometry] = [:]
   ```

Either is fine. Option A is more direct ("siblings, not subclasses" expressed in the code shape). Option B scales with no edit when a third particle preset arrives. **Pick A.** If you find yourself adding a third in DM.1 (you won't — out of scope), revisit.

5.4 **Both geometries are built once at engine init**, before the first `applyPreset`. Building both costs ~50 KB + ~320 KB of GPU memory (negligible) + two Metal pipeline-state objects (sub-ms init). Don't lazy-build per-preset-switch — that introduces visible Metal pipeline-state creation latency on switch.

5.5 **`applyPreset` `.particles` case** (`VisualizerEngine+Presets.swift:169`) selects the right geometry by preset name. The preceding `setParticleGeometry(nil)` at line 67 still runs; the per-pass case re-attaches.

- **Done when:**
  - `DriftMotesGeometry` compiles cleanly and conforms to `ParticleGeometry`.
  - The factory builds both Murmuration and Drift Motes geometries at engine init.
  - `applyPreset` for "Drift Motes" attaches `driftMotesGeometry`; for "Murmuration", attaches `murmurationGeometry`.
  - Switching between the two presets at runtime works without crashes, leaks, or pipeline-state leaks.

### Task 6 — Sprite render path

Implement `motes_vertex` + `motes_fragment` in `DriftMotesParticles.metal`:

6.1 **Vertex shader.** Read particle position from buffer 0; transform `(p.x, p.y) * scale` to clip space (mirror Murmuration's scale = 2.2 unless the visual review surfaces a need to change it). Output a 6-px point size via `[[point_size]]`. Pass particle color through.

6.2 **Fragment shader.** Render a soft Gaussian falloff over `[[point_coord]]`. Tint by `default_warm_hue()` (a fixed warm amber, e.g. `float3(1.0, 0.7, 0.4)`), modulated by the per-particle `color` field (which is the same warm hue at this session, but Session 2 will diversify). Brightness is a fixed scalar; **no shaft-density modulation** (that's Session 2).

6.3 **Additive blend** baked into the render pipeline state (set in `DriftMotesGeometry.init`, not in the shader).

- **Done when:**
  - Particle field is visible against the sky backdrop as soft warm-amber motes.
  - No banding, no hard edges on sprites (Gaussian falloff is smooth).
  - Frame rate is comfortably above 60 fps at 800 particles (Session 3 will profile properly; Session 1 just confirms no obvious performance cliff).

### Task 7 — Pass wiring + JSON sidecar

7.1 In `DriftMotes.json`, declare:
```json
{
  "name": "Drift Motes",
  "family": "particles",
  "duration": 30,
  "description": "Pollen and dust drift in a warm directional force field. The cinematographic ambient floor.",
  "author": "Matt",
  "passes": ["feedback", "particles"],
  "fragment_function": "drift_motes_sky_fragment",
  "vertex_function": "fullscreen_vertex",
  "beat_source": "composite",
  "decay": 0.92,
  "base_zoom": 0.0,
  "base_rot": 0.0,
  "beat_zoom": 0.0,
  "beat_rot": 0.0,
  "beat_sensitivity": 0.0,
  "stem_affinity": {
    "vocals": "mote_hue",
    "bass": "wind_force",
    "drums": "dispersion_shock",
    "other": null
  },
  "visual_density": 0.35,
  "motion_intensity": 0.30,
  "color_temperature_range": [0.55, 0.85],
  "fatigue_risk": "low",
  "transition_affordances": ["crossfade", "morph"],
  "section_suitability": ["ambient", "comedown", "bridge"],
  "complexity_cost": { "tier1": 1.6, "tier2": 2.1 },
  "rubric_profile": "lightweight",
  "certified": false
}
```

The `stem_affinity` map declares the *intent* for Session 2/3 wiring; the values are descriptive strings the Orchestrator uses for scoring, not implementation hooks (Session 1's actual code reads no stems beyond the warmup guard).

7.2 Confirm `PresetLoader` picks up the new preset at app launch (no code change needed in `PresetLoader`; it scans the directory).

- **Done when:**
  - Drift Motes appears in the preset list at app launch.
  - Selecting Drift Motes renders the warm sky backdrop with drifting motes.
  - Feedback pass is producing faint trails (decay 0.92 — short trails, faint streaks during fast wind).

### Task 8 — Test: `DriftMotesNonFlockTest`

Implement the preset-specific test in `DriftMotesTests.swift`.

8.1 **Test setup.** Construct a `DriftMotesGeometry` directly (not through `VisualizerEngine`); seed deterministic initial state; encode 200 frames of `update(...)` with the silence fixture (zero `FeatureVector`, zero `StemFeatures`).

8.2 **Sample 50 random particle pairs at frame 50 and at frame 200.** For each pair, record the pairwise distance.

8.3 **Assert:** the *distribution* of pairwise distances does NOT contract from frame 50 to frame 200. Specifically — the median, mean, and 25th-percentile distance must each be ≥ 95% of their frame-50 values. Cohesion would manifest as all three contracting; the 5% tolerance allows for natural variance from recycle dynamics.

8.4 **Test must pass deterministically** — fixed RNG seed, fixed initial particle positions, fixed hash seeds.

- **Done when:**
  - `swift test --package-path PhospheneEngine --filter DriftMotesNonFlockTest` returns success.
  - Test failure mode is informative: prints frame-50 vs frame-200 distance distribution if the assertion fails (so a regression diagnoses cleanly).

### Task 9 — Visual harness contact sheet

Capture pass-separated contact sheets per the contract's "Minimum viable milestone" requirement:

9.1 Sky backdrop only (sprite render disabled — easiest: temporarily attach `nil` particle geometry).
9.2 Sprite render only (sky backdrop replaced with solid black — easiest: render with a stub fragment that returns `float4(0, 0, 0, 1)`).
9.3 Full composite (both).

These sheets are required for diagnostic review at the session boundary. Save under `tools/visual_harness/output/DM.1/` (or wherever `PresetVisualReviewTests` writes; mirror the location used by other `RENDER_VISUAL=1` paths).

- **Done when:** all three sheets exist and are visually distinct. Sky-only is a clean gradient; sprite-only is dots on black; composite reads as the design intent.

### Task 10 — Engineering plan landing note + Murmuration regression check

10.1 Add `Increment DM.1 ✅ landed YYYY-MM-DD` to `ENGINEERING_PLAN.md`'s Phase DM section (DM.0 created the section; append DM.1's block immediately after the DM.0 block).

10.2 **Run `PresetRegressionTests` and confirm Murmuration's dHash is unchanged.** This is the load-bearing gate for "DM.1 didn't regress Murmuration." If Murmuration's hash changes, the refactor introduced a behavior delta — diagnose before declaring complete. Most likely cause: the factory now builds both geometries at init, and if `ProceduralGeometry`'s init has any non-determinism (it shouldn't, but verify), the test fixture would shift. Less likely but possible: a Metal library compilation order change pushed a different optimization path. **Do not update the golden hash to match the new value.**

- **Done when:**
  - `ENGINEERING_PLAN.md` has the DM.1 landing block.
  - `swift test --package-path PhospheneEngine --filter PresetRegressionTests` passes with Murmuration's dHash bit-identical to the post-DM.0 value (`(steady, beatHeavy, quiet)` Murmuration row matches HEAD).
  - All other regression tests pass.

---

## Verification (run before declaring complete)

```bash
# 1. Compile cleanly
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build

# 2. Existing tests still pass
swift test --package-path PhospheneEngine

# 3. The new test passes
swift test --package-path PhospheneEngine --filter DriftMotesNonFlockTest

# 4. PresetRegressionTests — Murmuration dHash bit-identical; Drift Motes adds a new entry
swift test --package-path PhospheneEngine --filter PresetRegressionTests

# 5. Visual references lint passes
swift run --package-path PhospheneTools CheckVisualReferences --strict

# 6. Confirm zero D-026 violations and zero free-running sin(time)
grep -n "smoothstep([0-9.]*[, ][0-9.]*[, ]f\." \
  PhospheneEngine/Sources/Renderer/Shaders/DriftMotesParticles.metal \
  PhospheneEngine/Sources/Presets/Shaders/DriftMotes.metal
# (should return ZERO matches — no absolute thresholds against FeatureVector fields)

grep -n "sin\s*(\s*time\|sin\s*(\s*u\.time\|sin\s*(\s*f\.time" \
  PhospheneEngine/Sources/Renderer/Shaders/DriftMotesParticles.metal \
  PhospheneEngine/Sources/Presets/Shaders/DriftMotes.metal
# (should return ZERO matches — sin(time) is forbidden per Arachne tuning rule)

grep -n "for\s*(\s*uint\s*j\|for\s*(\s*int\s*j\|particles\[j" \
  PhospheneEngine/Sources/Renderer/Shaders/DriftMotesParticles.metal
# (should return ZERO matches — no neighbor queries; this would indicate flocking)

# 7. DM.0 invariants preserved: ParticleGeometry surface is unchanged
git diff <DM.0-tip> HEAD -- PhospheneEngine/Sources/Renderer/Geometry/ParticleGeometry.swift
# (should return ZERO output — the protocol surface is final)

# 8. DM.0 invariants preserved: Murmuration's path untouched
git diff <DM.0-tip> HEAD -- PhospheneEngine/Sources/Renderer/Shaders/Particles.metal \
                              PhospheneEngine/Sources/Renderer/Geometry/ProceduralGeometry.swift
# (should return ZERO output — Murmuration's MSL and conformer are byte-identical)
```

If **any** of these fail, do not commit. Fix the failure first.

---

## Anti-patterns — explicit failures to avoid

These are drawn from the design doc §6, the contract's "Stop conditions", D-097, and CLAUDE.md's failed-approaches log:

1. **Flocking behavior of any kind.** The non-flock property is the preset's identity. If the compute kernel contains a neighbor query, alignment force, cohesion force, or separation force, you are building Murmuration v2, not Drift Motes. Stop and re-read the contract. Failed Approach #1 in the original DM.1.

2. **`sin(time)` motion.** Free-running `sin(u.time)` is forbidden across the catalog (CLAUDE.md Arachne tuning rule). All oscillation must be audio-anchored or `curl_noise(p, time)`-driven (where `time` is a phase advance into the noise field, not a visible oscillation). Failed Approach #33.

3. **Reading `f.bass_att_rel`, `f.mid_att_rel`, `stems.drums_energy_dev`, `stems.vocalsPitchHz` outside the warmup guard.** Session 1 is audio-independent. Session 2/3 wires the audio routes. If you reach for these fields, you're running ahead.

4. **Constant emission rate that "looks lifeless".** This is a Session 3 concern (emission rate scales with `f.mid_att_rel`). For Session 1, the fixed rate is correct — the lifelessness is acceptable because Session 1 is a foundation milestone, not a final render.

5. **Beat-pulsing per-mote brightness.** Drum coupling is dispersion shock only (Session 3). Per-mote brightness must not flash on drums.

6. **Modifying `ProceduralGeometry` or `Particles.metal`.** D-020 + DM.0's "siblings, not subclasses" promise: shared paths and Murmuration's conformer stay byte-identical. If `Particles.metal` looks like it needs a change, the change either (a) belongs in `DriftMotesParticles.metal`, (b) belongs in a separate increment that benefits *all* particle presets and ships independently of DM.1.

7. **Extending the `ParticleGeometry` protocol.** Three members: `update`, `render`, `activeParticleFraction`. If Drift Motes needs a fourth, that's a separate decision (D-097 carry-forward). Do not amend the protocol "while we're in here."

8. **Generic protocol.** Same rule as DM.0 Anti-pattern #7. The `Particle` struct is fixed. Don't make `DriftMotesGeometry` generic over `<P: ParticleProtocol>` or similar.

9. **Adding mv_warp.** D-029 explicit incompatibility. The pass set is `["feedback", "particles"]`. Period.

10. **Using Metal built-in type names as variables.** `int half = ...` shadows the `half` float type and silently fails to compile (Failed Approach #44). `PresetLoaderCompileFailureTest` will catch a silent shader-compile drop, but don't ship the bug just because the test exists.

11. **Lazy-building the geometry on preset switch.** Both Murmuration and Drift Motes geometries are built at engine init. Lazy-building introduces visible Metal pipeline-state creation latency on switch and complicates the lifecycle. ~370 KB of GPU memory for two pre-built buffers is well under any tier's headroom.

---

## Commit cadence

Per project convention (`CLAUDE.md` commit format): `[<increment-id>] <component>: <description>`.

Suggested cadence for DM.1:

```
[DM.1] DriftMotes: scaffolding (.metal stubs + .json sidecar + DriftMotesGeometry shell)
[DM.1] DriftMotesParticles: motes_update compute kernel — force-field motion, no flocking
[DM.1] DriftMotesParticles: motes_vertex/motes_fragment sprite render with default warm hue
[DM.1] DriftMotes: sky backdrop fragment shader
[DM.1] DriftMotesGeometry: ParticleGeometry conformer + factory wiring
[DM.1] VisualizerEngine: applyPreset .particles dispatch by preset name
[DM.1] DriftMotesNonFlockTest passes
[DM.1] Docs: ENGINEERING_PLAN landing note for DM.1
```

After each commit, push **only when Matt explicitly approves**. Local commits are fine; `git push` requires "yes, push" in chat.

---

## Done-when (overall session gate)

DM.1 is complete when **all** of the following are true:

- [ ] All tasks 1–10 are complete with their individual done-when satisfied.
- [ ] All verification commands pass (build, all tests, lint, grep checks, DM.0-invariants diff).
- [ ] Visual harness contact sheets exist under `tools/visual_harness/output/DM.1/`.
- [ ] Drift Motes is selectable from the app's preset list and renders without crashing.
- [ ] Particles drift, recycle, and **do not flock** (verified by automated test, not just visual review).
- [ ] Switching between Murmuration and Drift Motes at runtime works correctly and the right conformer is attached for each.
- [ ] Murmuration's `PresetRegressionTests` dHash is bit-identical to the post-DM.0 value.
- [ ] All commits use `[DM.1]` prefix.
- [ ] `ENGINEERING_PLAN.md` has the `Increment DM.1 ✅ landed <date>` block.

If you hit a stop-condition (Particle struct extension turns out unavoidable, sky-fragment / particle-MSL placement decision blocks compilation, factory wiring requires changes outside DM.1's stated files, Murmuration's hash drifts and you can't diagnose), **stop the session and report**. Do not work around it. The DM.1 prior-attempt blocker report is the model — concise, file-and-line-cited, scope-aware.

---

## After DM.1 lands

Session 2 (DM.2) wires the light shaft, floor fog, and per-particle hue baking from `vocalsPitchNorm`. Session 3 (DM.3) wires the full audio routing, the drum dispersion shock, the anticipatory shaft pulse, and the M7 frame-match review against `01_atmosphere_dust_motes_light_shaft.jpg`. Each subsequent session has its own prompt with its own scope and verification.

DM.1 is the foundation. Get the motion model right and the conformer pattern clean; everything downstream depends on it.
