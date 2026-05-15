# V.9 Session 4.5c Phase 2 — SPH motion + ZOOM coupling + Leitl finishing touches

**Increment:** Continuation of V.9 Session 4.5c Phase 1 (commits prefixed `[V.9-session-4.5c-phase1-*]` ending with `[V.9-session-4.5c-phase1-round14]`). Phase 1 ported the mesh+vertex-displacement geometry pipeline + Leitl's four-layer material + procedural studio env. Phase 2 picks up the remaining components of Leitl's full architecture.

## Recent calibration round (round 15, 2026-05-15)

Phase 1 ended with a calibration defect that was found and fixed before Phase 2:

The `2026-05-15T14-10-12Z` capture (Love Rehab + Money, 97s) revealed that round-14's spike-strength constants assumed `stems.bass_energy` peaks at ~1.0, but real-music peaks reach 2.58 (Money). Round-14's BaseCoef 4.0 + Modulation 1.5 produced peak spike heights of 2.64 wu (aspect 22:1 — wire-thin needles at bass-heavy moments).

**Round 15 fix (committed):** BaseCoef 4.0 → 1.5, Modulation 1.5 → 0.5. Peak spike now ~0.95 wu (aspect ~8:1, proper needle). Mean at calm music is small (~0.08 wu) — visible but quiet. If the calm baseline reads as too low when Phase 2 starts, three follow-up options:

- Bump BaseCoef back toward 2.0 (peak ~1.14 wu, more visible at calm music)
- sqrt-scale the input (`sqrt(bass_energy) × 3.0` — compresses dynamic range)
- Per-frame ZOOM coupling (Phase 2 item 2 below) supersedes this constant entirely

Recapture pending against `2026-05-15T14-10-12Z`'s playlist before Phase 2 begins. If round 15 calibration looks right at peaks and not-too-quiet at calm passages, Phase 2 starts from a clean baseline.

## Where we are (Phase 1 end state)

`Ferrofluid Ocean` is the only preset in the catalog that renders through a **tessellated mesh + vertex displacement** path (everything else is SDF ray-march). The substrate reads as ferrofluid material — dark base with discrete pointed pyramidal spikes, specular highlights on spike ridges, subtle iridescence at the patch centre on tilted normals only. The substrate is near pitch-black between spikes per references. Audio coupling: `stems.bass_energy × 4.0 + bass_energy_dev × 1.5` (or `f.bass_dev × 5.0` during the stem-pipeline warmup window) drives spike height. Camera at (0, 2.5, -4.0) looking at (0, 0.3, 3.0) — ~18° down — ocean framing with horizon visible.

**Last visual review** (Matt, on `2026-05-15T13:56:20Z` capture preceding round 14):
- "Works best for regular beat, didn't look great for There There and Money." Round 14 added raw-`bass_energy`-amplitude baseline to address steady-bass-amplitude irregular-meter tracks.
- "Still 8-10 s before scene moves." Round 14 bumped warmup proxy gain so bass hits during the pre-stem window are more dramatic — but the substrate stays flat between hits in that window because no AGC-safe music-presence primitive exists in FeatureVector. The real fix is structural (this prompt).

**Files involved (current state, post-round-14):**

| Path | Role |
|---|---|
| `PhospheneEngine/Sources/Renderer/Shaders/FerrofluidMesh.metal` | Mesh vertex + G-buffer fragment (Phase 1 Step B). Vertex stage: samples height texture, displaces vertex Y, computes normal via finite-difference cross product. |
| `PhospheneEngine/Sources/Renderer/Shaders/FerrofluidParticles.metal` | Bake + SPH-LITE compute kernels. `ferrofluid_height_bake` is in use. `ferrofluid_particle_update` + `ferrofluid_bin_particles` + `ferrofluid_reset_cell_counts` EXIST but are NOT dispatched per frame in the current pipeline (particles are pinned). |
| `PhospheneEngine/Sources/Presets/FerrofluidOcean/FerrofluidParticles.swift` | Owns particle buffer (1520 particles, 40×38 grid), cell-count + cell-slot buffers (spatial hash), 4096² height texture, bake compute pipelines. `encodePerFrameUpdate` method exists but is not currently called from the per-frame compute dispatch hook. |
| `PhospheneEngine/Sources/Presets/FerrofluidOcean/FerrofluidMesh.swift` | Mesh buffer (257² vertices) + index buffer + G-buffer pipeline state + depth-stencil state. `encodeGBufferPass` is dispatched per frame via `RayMarchPipeline.meshGBufferEncoder`. |
| `PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal` | Lighting fragment + `fluid_shading` (Leitl four-layer material) + `fluid_studio_env` (procedural studio env). matID==2 branch routes to Leitl. |
| `PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.metal` | `fo_spike_strength` + `fo_swell_scale` + `sceneSDF`. The SDF path is no longer used for ferrofluid_ocean (mesh path replaces it) but the file still defines spike-strength routing that the mesh path's vertex shader mirrors. |
| `PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.json` | Preset descriptor. Scene camera + thin-film params. |
| `PhospheneApp/VisualizerEngine+Presets.swift` | Wires `FerrofluidParticles` + `FerrofluidMesh` at preset apply; sets `meshGBufferEncoder` closure. |

## What's still missing from Leitl

Phase 2 targets, in approximate order of impact:

### 1. SPH particle motion (biggest gap)

Leitl's particles MOVE based on full Smoothed Particle Hydrodynamics. Heightmap re-bakes every frame from moving particle positions → spikes ripple, cluster, and shift across the substrate. That's what makes his demo look ALIVE — not just spike-height modulation, but spikes that drift and bunch.

**Six compute kernels in Leitl's pipeline** (read these directly — they're all small, ~100-150 lines each):

| Leitl shader | Role | Phosphene equivalent (if any) |
|---|---|---|
| `indices.frag.glsl` | Bin particles into cells (compute particle's cell ID, write to indices texture) | `ferrofluid_bin_particles` ~equivalent |
| `sort.frag.glsl` | Odd-even merge sort indices by cell ID | NOT IMPLEMENTED |
| `offset.frag.glsl` | Per-cell offset list (where each cell's particles start in the sorted indices) | NOT IMPLEMENTED |
| `pressure.frag.glsl` | SPH density + pressure (poly6 weight sum over neighbours in 3×3 cells) | NOT IMPLEMENTED |
| `force.frag.glsl` | Pressure + viscosity forces (spiky_grad + visc_lap weights) + boundary forces | Phase 2c `ferrofluid_particle_update` has a different force model — pressure/drums/rotation/arousal — REJECTED per D-127(d); needs to be REPLACED with Leitl's SPH math |
| `integrate.frag.glsl` | Semi-implicit Euler position+velocity update, plus: pointer force, idle force (constant wobble at `(0, -0.1)`), nervous wiggle (per-particle noise), edge damping | Phase 2c integrate has different semantics |

Constants Leitl uses (`sketch-04.js` lines 56-66):
```
simulationParams = {
    H: 1,             // kernel radius
    MASS: 1,          // particle mass
    REST_DENS: 1.8,   // rest density
    GAS_CONST: 40,    // gas constant
    VISC: 5.5,        // viscosity
    // derived:
    POLY6      = 315 / (64 * π * H^9)
    SPIKY_GRAD = -45 / (π * H^6)
    VISC_LAP   = 45  / (π * H^5)
}
NUM_PARTICLES = 500
DOMAIN_SCALE = vec2(8, 8)
cellSideCount = 11  → 11×11 = 121 cells
```

**Our current setup differs:** 1520 particles in a 20×20 wu world patch (4 wu per side equivalent → particle density ~0.4 wu spacing). Leitl: 500 particles, domain 16 wu wide, density ~0.7 wu spacing. We may want to halve our particle count or double our domain to match SPH dynamics expectations. The kernel radius `H` should be ~1.5-2× particle spacing.

**Existing Phosphene infrastructure to leverage:**
- Spatial-hash binning kernels already exist (`ferrofluid_bin_particles` + `ferrofluid_reset_cell_counts`).
- Cell buffers (`cellCountBuffer`, `cellSlotBuffer`) already allocated.
- Per-frame compute dispatch hook (`RenderPipeline.setRayMarchPresetComputeDispatch`) is in place but currently nil (was deliberately disabled for "pin particles" in round 4).
- `FerrofluidParticles.encodePerFrameUpdate` already exists with the Phase 2c kernel sequence. Replace its math.

**Migration path:**
1. Strip Phase 2c force model from `ferrofluid_particle_update` MSL kernel. Replace with Leitl's SPH math (pressure + viscosity from `pressure.frag.glsl` + `force.frag.glsl`, integrated semi-implicit Euler from `integrate.frag.glsl`).
2. Add Leitl's `sort` + `offset` kernels (we have `bin` but no sort/offset — Phase 2c skipped them).
3. Re-enable the per-frame compute dispatch in `VisualizerEngine+Presets.swift` for ferrofluid_ocean.
4. Verify that motion produces "spikes drift and cluster" not "spikes smudge sideways" — the mesh path renders from displaced vertices, so position shifts manifest as the spike actually moving in space (unlike the SDF path's normal-gradient-smearing).

**Risk:** Matt previously rejected Phase 2c motion as "smudge." That was rendered on the SDF path. The mesh path renders moving spikes as ACTUAL MOVEMENT (the vertex's UV stays fixed; the heightmap content shifts as particles move). Should look different. But if it still reads as smudge after Leitl's SPH math, the conversation moves to (a) sample the heightmap differently, or (b) animate vertex positions directly instead of via heightmap re-bake.

### 2. ZOOM-coupled bake parameters

Leitl couples **one audio scalar (`ZOOM`)** to **four heightmap bake parameters** via polynomial remaps (`sketch-04.js::#animate`):

```
heightFactor       = -0.36·z² - 0.02·z + 0.38   // peak height world-space scale
heightMapZoomScale = 2·z² + z + 1               // heightmap UV scale (more samples per particle at high zoom)
smoothFactor       = 0.3·z² - 0.07·z + 0.02     // smooth-min `w` weight
spikeFactor        = 12·z² - 36·z + 25          // sharpness gain on the smooth-min output
```

Where `z ∈ [0, 1]`:
- `z = 0` (high arousal) → tall (0.38), sharp (spike=25), tight smooth-min (0.02), small UV scale (1.0). DRAMATIC SPIKES.
- `z = 0.5` (mid) → ~0.27 height, ~8 sharp, ~0.085 smooth, ~2.0 scale. MEDIUM.
- `z = 1.0` (silence) → flat (0.0), gentle (spike=1), broad smooth (0.25), large scale (4.0). HIDDEN.

**Audio coupling:** Leitl reads `audioControl.getValue() ∈ [0, 1]` and converts to ZOOM with momentum + lerp wobble:
```
targetZoomLerp += (targetZoomOffset - targetZoomLerp) / 10
deltaZoomOffset = (zoomOffset - targetZoomLerp)
zoomOffsetMomentum -= deltaZoomOffset / 50
zoomOffsetMomentum *= 0.92
zoomOffset += zoomOffsetMomentum
ZOOM = 0.5 - zoomOffset / 2
```

That's a spring-momentum smoother on the audio value. Gives the visual a natural wobble around the audio target rather than snapping.

**Our current state:** bake params are static constants. `spikeBaseRadius = 0.12`, `smoothMinW = 0.005`, `heightFactor` baked into the linear cone formula. No audio coupling to bake params.

**To port:**
1. Choose an audio scalar. Options:
   - `stems.bass_energy + stems.drums_energy * 0.5` smoothed (steady path)
   - `f.bass_att` (warmup path)
   - Combine into a single `audioControl` scalar that crosses warmup→steady cleanly
2. Add spring-momentum smoothing on the CPU side (mirror Leitl's lerp + momentum math). Single Swift class `FerrofluidAudioControl` or similar.
3. Pass smoothed ZOOM to the bake kernel as a uniform.
4. Replace fixed bake constants with the four polynomial-remapped values.
5. The `height_factor` consumed at the vertex stage (currently `0.15` in `kFerrofluidMeshHeightFactor`) should also be ZOOM-driven, replacing my current `fo_spike_strength`-based amplitude routing.

This unifies the audio response: a single scalar drives ALL of (peak height, spike sharpness, smoothness, scale, vertex amplitude). Massive simplification + Leitl-faithful behaviour.

### 3. Entry animation

Leitl's `ZOOM` lerps from 1.0 (flat / hidden) to 0.5 (peaks visible) over 7 seconds at preset apply (`sketch-04.js::#animate` entry branch, lines ~615-645):

```
entryDelay = 120 frames (~2 s)
entryDuration = 420 frames (~7 s)
part1 = 0.7 * entryDuration (rise to peak via easeInOutExpo)
part2 = 0.3 * entryDuration (settle from peak via easeInOutCubic)
```

So the ferrofluid "wakes up" — substrate is flat for ~2s, then spikes rise dramatically and settle at the audio-driven mid-zoom level.

**Our equivalent:** we have the stem-warmup window (~10s) that naturally produces a similar gradual-rise effect, but it's not deliberate — it's a side effect of stems not being ready. With ZOOM coupling (Phase 2 item 2), we get explicit control: at preset apply, ZOOM = 1.0 (flat); ease ZOOM → 0.5 over 7 seconds. The audio coupling overrides after entry completes.

Implementation is in the same CPU class as #2 — adds an entry-progress state machine.

### 4. Audio control scalar (precursor to #2)

Leitl uses `audioControl.getValue() ∈ [0, 1]`. We have FeatureVector + StemFeatures with many primitives but no single "audio level" scalar designed for this purpose.

Decision: derive an `audioControl` scalar from existing primitives. Reasonable formula:

```
audioControl = clamp(stems.bass_energy * 0.5 + stems.drums_energy * 0.3 + arousal_normalized * 0.2, 0, 1)
```

Then feed THIS to the spring-momentum smoother in #2.

For warmup, fall back to FeatureVector-only:

```
audioControlWarmup = clamp(f.bass_att * 0.7 + smoothstep(-1, 1, f.arousal) * 0.3, 0, 1)
```

Crossfade as stems warm up.

### 5. Things Leitl has that we may NOT want to port

- **Pointer interaction.** Leitl uses mouse/touch to push particles. Phosphene is a music visualizer, not interactive. Skip.
- **Ground disc as a separate render pass.** Leitl renders a disc primitive underneath the spikes plane. Our mesh's flat-base areas already serve as substrate (confirmed visible in Phase 1 captures). Skip.
- **Close-camera framing.** Leitl is at (0, 0.5, 1) — 1 wu from origin. We deliberately use ocean-scale framing (camera 5 wu away from a 20 wu patch). Keep our framing; it serves the "ocean" identity.

## Suggested order of work

Each step is its own commit, separately verifiable.

1. **Re-baseline understanding.** Read this prompt + Phase 1 closeout (commits prefixed `[V.9-session-4.5c-phase1-*]` from `git log`) + current shader files end-to-end. Re-run the latest visual capture to confirm baseline. Don't start changing code until the baseline state is internalized.

2. **Audio control scalar (#4).** One new Swift class `FerrofluidAudioControl` or similar. Derives a single [0, 1] scalar from features + stems. No visual change yet — just plumbing. Commit.

3. **ZOOM-coupled bake (#2).** Pass smoothed audio control to bake kernel as a uniform. Replace the fixed `smoothMinW`/`spikeBaseRadius`/height-factor constants with polynomial-remapped ZOOM values matching Leitl's `#remap*` functions. Vertex shader's `kFerrofluidMeshHeightFactor` reads from the same ZOOM. Single audio scalar now drives ALL spike-character parameters. Visual change: spike height/sharpness modulates dramatically with audio, like Leitl's demo. Commit. **STOP and surface visual to Matt.**

4. **Entry animation (#3).** Add an entry-progress state machine in `FerrofluidAudioControl`. ZOOM starts at 1.0 at preset apply, eases to 0.5 over 7 seconds. Audio overrides after entry completes. Visual change: ferrofluid "rises" at preset apply instead of appearing at full height. Commit. **STOP and surface to Matt.**

5. **SPH motion (#1).** The big one. Multiple sub-commits probably:
   a. Port `pressure.frag.glsl` math to MSL — replace Phase 2c pressure with Leitl's `poly6` density.
   b. Port `force.frag.glsl` math — replace Phase 2c force with SPH pressure + viscosity + boundary forces.
   c. Port `integrate.frag.glsl` — semi-implicit Euler + idle force + nervous wiggle + edge damping.
   d. Add `sort` + `offset` kernels (we're missing these from Phase 2c).
   e. Re-enable the per-frame compute dispatch in `VisualizerEngine+Presets.swift`.
   f. Tune constants — H, MASS, REST_DENS, GAS_CONST, VISC may need adaptation to our larger patch + particle count.
   
   Visual change: spikes ripple, cluster, drift across the substrate as audio plays. **STOP and surface after each sub-commit.**

## Reference URLs

- Leitl repo: https://github.com/robert-leitl/ferrofluid
- Demo: https://robert-leitl.github.io/ferrofluid/dist/?debug=true
- Writeup: https://robert-leitl.medium.com/ferrofluid-7fd5cb55bc8d
- Shader files: https://github.com/robert-leitl/ferrofluid/tree/main/src/app/shader
- Orchestrator: https://github.com/robert-leitl/ferrofluid/blob/main/src/app/sketch-04.js (read sections: `#init`, `#simulate`, `#animate`, `#render`)

## Discipline reminders (from CLAUDE.md `Authoring Discipline`)

Re-read these before authoring anything in Phase 2:

- **Failed Approach #65 — Don't negotiate away components of a working reference implementation under unverified "redundancy" arguments.** This is what happened to me in Phase 1 (rounds 6-12 spent on tuning before I admitted I had only ported Leitl's fragment shader, not his geometry pipeline). The cost of starting from "match Leitl verbatim" and only adapting where context REQUIRES adaptation is much lower than starting from "Phosphene's version" and converging.
- **Failed Approach #64 — When iterative first-principles fixes aren't converging on a problem with known prior art in the field, stop guessing and do desk research.** Leitl's shaders are the prior art. Read them before writing MSL.
- **Limit variables.** One change per commit. Visual gate after each. Stop and surface to Matt if the pattern of "fix one thing, new failure appears" emerges.
- **Articulate the musical role before authoring any decoration layer.** What musical moment does ZOOM-coupled bake produce? "Audio-driven dramatic spike rise/fall." What does SPH motion produce? "Ferrofluid surface that ripples and shifts with the music, like real ferrofluid." Both have load-bearing musical roles → green light.
- **Decisions presented to Matt in product-level language, not engineering jargon.** "Should the entry animation be 7 seconds or shorter?" not "Should `entryDuration = 420` or `entryDuration = 240`?"

## What to ship at end of Phase 2

- One ferrofluid preset that, on real music, produces:
  - Audio-driven dramatic spike rise/fall (ZOOM coupling)
  - Spikes that ripple and cluster across the substrate (SPH motion)
  - 7-second fade-up at preset apply (entry animation)
  - Matches Leitl's demo character at ocean scale instead of dish scale
- All four Leitl components (mesh+vertex from Phase 1, plus SPH + ZOOM + entry from Phase 2) integrated
- ENGINEERING_PLAN.md + RELEASE_NOTES_DEV.md updated per CLAUDE.md Increment Completion Protocol
- Commits pushed only on Matt's explicit approval (CLAUDE.md push rule)

## Things to verify before declaring Phase 2 done

- Real-music captures across multiple track styles (regular-beat + irregular like Money / There There)
- The Phase 1 visual gates still pass (substrate pitch-black between spikes, no rainbow streaks, etc.)
- 60 fps at 1080p on M2 Pro maintained — six SPH compute kernels per frame plus mesh draw + lighting could push the budget
- No new audio-thread allocations introduced by the per-frame dispatch
- Engine + app builds clean, full test suite passes (except documented pre-existing flakes)
