# Lumen Mosaic Rendering Architecture Contract

**Status:** Active. Revised 2026-05-09 alongside the LM.3.2 design pivot — the second pivot in 24 hours. The LM.3 continuous-cycling form of D.4 was rejected in production (cells did not visibly cycle on real Spotify-normalised audio because mid + treble bands under-read; `accumulated_audio_time` advanced ~10× too slowly to register as motion — BUG-012). The LM.3.1 agent-position-driven backlight character was rejected by Matt 2026-05-09 ("the bright pools dominated the visual story"). LM.3.2 adopts Decision D.5 — band-routed beat-driven dance — instead: cells advance their palette index *discretely on each FFT-band beat*, with a per-cell team assignment + period sampled from `hash(cell_id ^ track_seed)`. Brightness is uniform with hash jitter; the visual story is colour change synced to the beat, not brightness modulation. This revision updates the `sceneMaterial` pseudocode (band-routed step + uniform-brightness intensity), the `LumenPatternState` layout (adds four band counters: bassCounter / midCounter / trebleCounter / barCounter, growing the struct 360 → 376 B), and the certification fixtures (per-track-seed-driven palette identity + bass-team step on rising-edge of `f.beatBass` are observable). All other contract sections (panel sizing §P.1, agent bounds §P.2, the dance §P.4, slot 8 binding) carry forward unchanged. See §Revision History.

## Purpose

This contract defines the required rendering architecture for Lumen Mosaic. It translates the design spec into implementation constraints, pass responsibilities, debug outputs, acceptance gates, and sequencing rules.

This file is authoritative for implementation. `LUMEN_MOSAIC_DESIGN.md` remains authoritative for visual intent and creative decisions.

**Decisions in force (LM.3.2+):** A.1 (Lumen Mosaic), B.1 (analytical agent contributions), C.2 (~50 cells across), **D.5 (band-routed beat-driven dance — cells hashed into bass / mid / treble / static teams, advance palette index on rising-edge of their team's FFT-band beat; periods Pareto-shaped from hash)**, **E.3 (procedural palette via V.3 IQ cosine `palette()`; mood shifts `(a, b, c, d)` continuously; per-track seed perturbations bumped to ±0.20 / 0.20 / 0.30 / 0.50; no authored palette banks)**, F.1 (slot 8 fragment buffer), G.1 (fixed camera, panel oversize 1.50×), H.1 (standalone preset). LM.0 / LM.1 / LM.2 shipped under D.1 / E.1; LM.3 / LM.3.1 shipped under D.4 (continuous palette cycling on `accumulated_audio_time`) / D.4 + agent-position backlight; both replaced at LM.3.2 by D.5.

## Required passes

| Pass | Name | Required output | Depends on | Debug view required |
|---|---|---|---|---|
| 1 | RAY_MARCH G-buffer | depth, normal, materialID, albedo for the glass panel | sceneSDF / sceneMaterial | Yes |
| 2 | RAY_MARCH lighting | lit RGB (HDR) — emission-dominated | G-buffer, IBL, pattern state | Yes |
| 3 | RAY_MARCH composite | tone-mapped RGB to drawable | lit RGB | Yes |
| 4 | POST_PROCESS bloom | bright-pass + Gaussian blur + composite | composited RGB | Yes |
| 5 | POST_PROCESS ACES | final tone-map | bloom-composited RGB | Yes |

**SSGI is intentionally not in `passes`.** The glass panel is emission-dominated; SSGI's contribution is invisible against bright emissive cells, and the saved budget keeps Tier 2 headroom for the pattern engine. `LumenMosaic.json` `passes` field: `["ray_march", "post_process"]`.

## Minimum viable preset milestone (LM.1 acceptance)

Before any audio reactivity is wired, the implementation must support:

- A `LumenMosaic.metal` file compiling cleanly through `PresetLoader`.
- A `LumenMosaic.json` file with the standard fields plus the new fields documented in §6.
- The G-buffer pass renders a planar glass panel filling the camera frame.
- The lighting pass produces visibly cellular output: voronoi cells with sharp inter-cell ridges, in-cell frost normal perturbation, and a single static backlight color (e.g., warm peach) emitted through every cell.
- The composite pass produces a clean tone-mapped image.
- `PresetAcceptanceTests` passes against the existing four invariants (non-black, no-clip, beat response, form complexity) — even with no audio reactivity, the static backlight should clear all four.
- The visual harness produces a contact-sheet image at the standard fixture set.
- `presetLoaderBuiltInPresetsHaveValidPipelines` regression gate passes (covers the new preset automatically).

## Blockers

Lumen Mosaic cannot be certified if any of the following are missing or non-functional:

- `mat_pattern_glass` (V.3 §4.5b) is not available in the preamble. **Mitigation: V.3 Materials cookbook is already shipped (Increment V.3, 2026-04-26). Verify presence; if absent, halt and escalate.**
- The cell `id` field in `VoronoiResult` is not exposed. **Mitigation: confirmed exposed per `mat_ferrofluid` reference (SHADER_CRAFT.md §4.6).**
- `RenderPipeline` lacks a fragment buffer slot at index 8. **Required infrastructure work in LM.0 (see §5).**
- The `sceneMaterial` signature does not match D-021. **Required to match: `void sceneMaterial(float3 p, int matID, constant FeatureVector& f, constant SceneUniforms& s, thread float3& albedo, thread float& roughness, thread float& metallic)`.**
- `IBLManager` does not produce a usable IBL irradiance/prefiltered/BRDF-LUT set for the panel. **Mitigation: IBLManager is shared infrastructure; verify presence.**
- `PostProcessChain` bloom path is unreachable. **Mitigation: verify against Glass Brutalist's bloom usage.**
- The panel's screen-space coverage exceeds `cameraTangents` projection (panel does not fill frame). **Mitigation: panel sized from `s.cameraTangents.xy * 1.50` per Decision G.1 — panel must extend 50% beyond frame on all sides so panel edges are never visible.**

## sceneSDF / sceneMaterial signatures

Per D-021 + LM.1 + LM.2 extensions (DECISIONS.md). The current full signature, shared across every ray-march preset:

```metal
float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems);

void  sceneMaterial(float3 p, int matID,
                    constant FeatureVector& f,
                    constant SceneUniforms& s,
                    constant StemFeatures& stems,
                    thread float3& albedo,
                    thread float& roughness,
                    thread float& metallic,
                    thread int& outMatID,                        // LM.1 / D-LM-matid
                    constant LumenPatternState& lumen);          // LM.2 / D-LM-buffer-slot-8
```

The shader **also** must define an emission-output path. The deferred PBR pipeline writes albedo to G-buffer and computes lit color from albedo + lights + IBL. Lumen Mosaic's color is emission-dominated:

- **matID == 1 (chosen at LM.1, kept at LM.3)** — write the backlight value to the G-buffer's albedo channel; the lighting pass multiplies by `kLumenEmissionGain (4.0)` and skips Cook-Torrance + screen-space shadows (`raymarch_lighting_fragment` matID == 1 branch). LM.3 keeps the same dispatch — what changes is *what value is written to albedo*.

**LM.3.2 sceneMaterial responsibilities (D.5):**

1. Compute `panel_uv = p.xy / s.cameraTangents.xy` (panel-face normalised coordinate).
2. Run `voronoi_f1f2(panel_uv, kCellDensity)` to obtain the cell's `id` (deterministic hash). The cell-centre `pos` is *not* used at LM.3.2 — the new uniform-with-jitter intensity model has no per-cell spatial dependency.
3. Derive a single 32-bit hash from the cell + per-track seed:
   ```
   trackHash = lm_track_seed_hash(lumen)         // mixes the four trackPaletteSeed{A,B,C,D} ∈ [-1, +1]
   cellHash  = lm_hash_u32(uint(v.id) ^ trackHash)
   ```
4. Assign the cell to a team (bucket = `cellHash % 100`):
   - `[0, 30)`  → bass team   (counter = `lumen.bassCounter`)
   - `[30, 65)` → mid team    (counter = `lumen.midCounter`)
   - `[65, 90)` → treble team (counter = `lumen.trebleCounter`)
   - `[90, 100)` → static team (counter = 0; cell never advances)
5. Pick a period from another hash bucket (`(cellHash >> 8) & 0x7`):
   - `< 3` → period = 1
   - `[3, 5)` → period = 2
   - `[5, 7)` → period = 4
   - `≥ 7` → period = 8

   Pareto distribution: ≈ 37.5 % period 1 / 25 % period 2 / 25 % period 4 / 12.5 % period 8.
6. Compute `step = floor(team_counter / period)`. The cell advances exactly `step × kPaletteStepSize` worth of palette phase past its base.
7. Compute palette phase: `phase = cell_t + step × kPaletteStepSize + lumen.smoothedValence × kPaletteMoodPhaseShift` where `cell_t = float(cellHash & 0xFFFF) / 65535`.
8. Compute palette parameters by interpolating between `kPaletteACool` / `kPaletteAWarm` etc. via `lumen.smoothedValence` and `lumen.smoothedArousal`, perturbed by the four `lumen.trackPaletteSeed{A,B,C,D}` per `kSeedMagnitude{A,B,C,D}` magnitudes. **Calibration round 3 (2026-05-09): per-channel hue-shift perturbation** — `a` perturbation uses the basis `(sA, sB, -(sA+sB)/2) × kSeedMagnitudeA` so different tracks land on different hue dominances (not just brightness shifts of the same colour set); `d` perturbation uses the same basis on `(sC, sD)`. `b` (chroma) and `c` (rate) get small uniform perturbations from a mean-of-seeds (so seedB can never pull `b` into pastel territory). Magnitudes 0.20 / 0.05 / 0.20 / 0.50.
9. Sample the palette: `cell_hue = palette(phase, a, b, c, d)` (V.3 `Sources/Presets/Shaders/Utilities/Color/Palettes.metal`).
10. Compute cell intensity uniformly with hash jitter and bar pulse:
    ```
    jitter      = float((cellHash >> 16) & 0xFF) / 255         // [0, 1]
    base        = kCellIntensityBase + kCellIntensityJitter × jitter   // [0.85, 1.0]
    barShape    = pow(saturate(f.bar_phase01), kBarPulseShape)         // 8.0 → only end-of-bar lights up
    intensity   = base × (1 + kBarPulseMagnitude × barShape)           // [0.85, 1.30]
    ```
11. Write `albedo = clamp(cell_hue × intensity, 0.0, 1.0)`, `outMatID = 1`.

The `lumen.bassCounter / midCounter / trebleCounter / barCounter` fields are **new in LM.3.2** (see §Required uniforms); the engine maintains them via rising-edge detection on `f.beatBass / beatMid / beatTreble / barPhase01-wrap`, debounced 80 ms, scaled by `beatStrength`. The agent `intensity` and `colorR/G/B` fields stay on the GPU struct for ABI continuity but are **unused by LM.3.2 sceneMaterial** (LM.4 may revisit pattern bursts that read agent positions). The cell-centre uv is unused at LM.3.2 (intensity is now per-cell, derived from the hash, not from the agent loop).

## Panel sizing, light agent bounds, and the dance

This section is normative for Decision G.1 (camera/framing) and the audio-coupling table in design doc §4.5. Implementations of LM.1, LM.2, and LM.4 must conform.

### §P.1 Panel SDF sizing — panel must bleed past frame

The glass panel is a single `sd_box` at `z = 0`. Its half-extents are derived from `cameraTangents` with a fixed oversize factor:

```metal
// In sceneSDF:
constexpr float kPanelOversize = 1.50;       // 50% beyond frame on every side
constexpr float kPanelThickness = 0.02;      // half-thickness in z
float3 panel_half = float3(s.cameraTangents.xy * kPanelOversize, kPanelThickness);
return sd_box(p, panel_half);
```

**Frame-edge invariant.** At every pixel inside the rendered frame, the primary ray from the camera must hit the panel face (matID == 1), not miss into the void. Verification: LM.1 contact sheet must show no background pixels at any of the six fixtures. LM.6 contact sheet must verify at three aspect ratios (16:9, 4:3, 21:9) — the panel must still cover the frame at the widest aspect ratio.

**Rationale.** Per Matt 2026-05-08, the viewer must see only the field of cells filled with light — never a panel boundary, never the empty void around the panel. The 1.50× factor (vs. a tighter 1.05–1.10×) is a margin for: (a) future camera-jitter additions if Decision G.3 is ever revisited; (b) corner safety when aspect ratio differs from the authoring aspect; (c) prevention of grazing-angle artifacts at the panel edge silhouette.

**Cell coordinate stability.** The cell pattern in `sceneMaterial` uses `panel_uv = p.xy / s.cameraTangents.xy` (note: divided by `cameraTangents`, NOT by `cameraTangents * kPanelOversize`). This means cell uv is `[-1, +1]` exactly at the visible frame edges, and `[-1.5, +1.5]` at the panel SDF edges. The cell pattern fills the frame with the same per-pixel cell density regardless of `kPanelOversize`. **Future authors who change `kPanelOversize` must NOT change the `panel_uv` divisor, or cell density will scale with the oversize factor.**

### §P.2 Light agent visible-area bounds

Per design doc §4.5, light agents have stem-specific base positions and dance within bounding regions. To avoid wasting illumination on invisible panel area (panel extends to uv = ±1.5; viewer sees uv = ±1.0), agent positions are clamped to a **visible-area region with a small inset** so the agent's emission lobe (which spreads with distance) is not partially clipped by the frame edge.

```metal
// LumenLightAgent.position is in panel-face uv (so [-1, +1] is the visible frame).
constexpr float kAgentInset = 0.85;           // agent center confined to [-0.85, +0.85] uv
agent.position.xy = clamp(agent.position.xy, float2(-kAgentInset), float2(kAgentInset));
```

**Per-stem base positions** (uv in panel-face coordinates):
| Agent | Stem | Base position |
|---|---|---|
| 0 | drums | `(-0.45, +0.35)` (upper-left) |
| 1 | bass | `( 0.00, -0.40)` (center-low) |
| 2 | vocals | `( 0.00, +0.05)` (center-mid) |
| 3 | other | `(+0.45, +0.30)` (upper-right) |

These are derived from the reference image's perceived light source positions and are deliberately offset from the frame center to give the panel a sense of multiple distinct light sources rather than one diffuse glow.

### §P.3 Light agent intensity sampling (LM.3 reframed)

Under D.4, the agents drive **per-cell intensity**, not per-cell colour. Per-cell colour comes from the procedural `palette()` sample keyed on cell hash + audio time + mood (sceneMaterial step 4–6). The agent loop produces a scalar brightness per cell:

```metal
float2 cell_center_uv = voronoi.pos;   // cell center in panel-face uv (V.3 Voronoi.metal contract)

float cell_intensity = 0.0;
int agentCount = min(lumen.activeLightCount, 4);
for (int i = 0; i < agentCount; ++i) {
    LumenLightAgent a = lumen.lights[i];
    float2 d = cell_center_uv - float2(a.positionX, a.positionY);
    float r2 = dot(d, d) + a.positionZ * a.positionZ + 1.0e-4;
    cell_intensity += a.intensity / (1.0 + r2 * a.attenuationRadius);
}
cell_intensity = max(cell_intensity, kSilenceIntensity);   // D-019 silence floor
```

The intensity is computed once per cell (cell-coherent) and multiplies the per-cell `cell_hue` from `palette()`. This preserves the cell-quantized character (every pixel in a cell shares one colour) while delivering visible cell identity (every cell has its own hue from the palette). Adjacent cells with similar `cell_t` get adjacent palette samples; distant cells can land on opposite sides of the palette wheel.

**Why agents drive intensity, not colour (LM.3 reframe).** The LM.2 implementation summed `a.color × falloff` per agent and got a smoothly-varying RGB field — quantizing it per cell technically worked but produced visually identical cells (production review 2026-05-09). Driving per-cell colour from a deterministic per-cell hash sidesteps the smooth-field problem: cells differ because their hashes differ, not because they sample different points on a smooth field.

### §P.4 The dance — `beat_phase01`-locked agent oscillation

Per design doc §4.5 ("The dance"), each agent's position has a beat-phase oscillation term that is co-primary with the slow drift term. The composition, computed each frame in `LumenPatternEngine.update`:

```swift
// Per-agent position update (Swift, runs on CPU once per frame):
let driftPhase = time * driftSpeed(arousal: f.arousal, agentIndex: i)
let drift = SIMD2<Float>(
    cos(driftPhase * driftFreq.x) * driftRadius(stemEnergy: stemEnergy[i]),
    sin(driftPhase * driftFreq.y) * driftRadius(stemEnergy: stemEnergy[i])
)

// Beat-locked oscillation. beat_phase01 ∈ [0, 1) is the continuous BPM-tracked beat clock.
let beatPhaseRad = f.beat_phase01 * 2 * .pi
let danceAmplitude = 0.04 + 0.10 * f.arousal     // [0.04, 0.14] uv units
let beatLockedOffset = SIMD2<Float>(
    cos(beatPhaseRad + agentBeatPhaseOffset[i]) * danceAmplitude,
    sin(beatPhaseRad * 2 + agentBeatPhaseOffset[i]) * danceAmplitude * 0.5  // figure-8
)

// Per-stem hue offset is composed into agent.color elsewhere (see LumenPatternEngine).
agent.position = clamp(
    basePosition[i] + drift + beatLockedOffset + barPatternOffset[i],
    SIMD2<Float>(repeating: -kAgentInset),
    SIMD2<Float>(repeating: +kAgentInset)
)
```

**Why this reads as "the dance":**
- `beat_phase01` is a *continuous* phase variable (linear ramp from 0 → 1 over each beat, then wraps), not a jittery onset. The eye reads its peak as "the beat" because peaks land on beats by construction, but there is no detection lag.
- The figure-8 (1× horizontal, 2× vertical frequency relative to beat) gives each agent a small Lissajous trajectory locked to the beat. Four agents at different `agentBeatPhaseOffset` values produce a complex-but-coherent ensemble pattern rather than four lights moving in unison.
- Amplitude scales with `arousal`: at `arousal = 0` (calm ambient) the dance is barely perceptible (0.04 uv units ≈ 2% of frame width); at `arousal = 1` (frantic) it spans 14% of frame width. This makes the visual energy match the music.
- `barPatternOffset` (LM.4+) is added on top, allowing pattern engine to push agents along radial / sweep / cluster trajectories during pattern bursts without disrupting the underlying beat-locked rhythm.

**Per-agent beat-phase offsets** (LumenPatternEngine constant):
| Agent | `agentBeatPhaseOffset` |
|---|---|
| 0 (drums) | `0.0` |
| 1 (bass) | `π / 2` |
| 2 (vocals) | `π` |
| 3 (other) | `3π / 2` |

Drums lead the beat, bass, vocals, and other follow at quarter-cycle phase increments — the ensemble traces a rolling wave across the panel. Tunable; defaults documented here for reproducibility.

**Verification (LM.4 review):** play a track with known BPM (e.g., a 120 BPM electronic track from the calibration set), record a 16 s capture, verify by eye that the visual peaks of the agent dance occur on the beat (or at consistent sub-divisions thereof). If the dance reads as random, this is a defect — escalate before LM.5.

## Required uniforms / buffers

### Existing (no changes required)

| Slot | Buffer | Notes |
|---|---|---|
| 0 | `FeatureVector` (192 B) | Standard. Read by sceneMaterial and pattern eval. |
| 3 | `StemFeatures` (256 B) | Standard. Read for stem-direct routing per D-019. |
| 4 | `SceneUniforms` (128 B) | Standard. Provides camera basis, light, fog/ambient. `cameraTangents` used to size the panel SDF. |

### New

| Slot | Buffer | Size | Notes |
|---|---|---|---|
| 8 | `LumenPatternState` | ≤ 1 KB | Bound by `setDirectPresetFragmentBuffer3` (new method on `RenderPipeline`). Populated CPU-side per frame by `LumenPatternEngine`. |

`LumenPatternState` Swift / Metal layout (must be byte-identical, SIMD-aligned):

```swift
// PatternKind: must match shader enum exactly.
public enum LumenPatternKind: Int32 {
    case idle           = 0
    case radialRipple   = 1
    case sweep          = 2
    case clusterBurst   = 3   // LM.5
    case breathing      = 4   // LM.5
    case noiseDrift     = 5   // LM.5
}

// SIMD-aligned to 16 bytes per element. Padded floats are zeroed.
public struct LumenLightAgent {
    public var position: SIMD3<Float>      // 12 B; xy in panel uv (-1..1), z = depth-spread
    public var attenuationRadius: Float    // 4 B
    public var color: SIMD3<Float>         // 12 B
    public var intensity: Float            // 4 B
    // Total: 32 B.
}

public struct LumenPattern {
    public var origin: SIMD2<Float>        // 8 B; panel uv
    public var direction: SIMD2<Float>     // 8 B; for sweep
    public var color: SIMD3<Float>         // 12 B
    public var phase: Float                // 4 B
    public var intensity: Float            // 4 B
    public var startTime: Float            // 4 B
    public var duration: Float             // 4 B
    public var kindRaw: Int32              // 4 B; LumenPatternKind raw
    public var pad0: Float = 0             // 4 B; pad to 48 B (3×SIMD4)
    // Total: 48 B.
}

public struct LumenPatternState {
    public var lights: (LumenLightAgent, LumenLightAgent, LumenLightAgent, LumenLightAgent)  // 4 × 32 = 128 B
    public var patterns: (LumenPattern, LumenPattern, LumenPattern, LumenPattern)            // 4 × 48 = 192 B
    public var activeLightCount: Int32      // 4 B
    public var activePatternCount: Int32    // 4 B
    public var ambientFloorIntensity: Float // 4 B  (LM.2 D-019 floor; unused at LM.3+ — silence handled by uniform-cell-intensity baseline)
    public var smoothedValence: Float       // 4 B  (LM.3 — 5 s low-pass for palette `(a, d)` interpolation)
    public var smoothedArousal: Float       // 4 B  (LM.3 — 5 s low-pass for palette `(b, c)` interpolation)
    public var pad0: Float = 0              // 4 B
    public var trackPaletteSeedA: Float     // 4 B  (LM.3 — per-track palette perturbation seed component A; LM.3.2 calibration round 3: drives X-channel of `a` perturbation, magnitude 0.20)
    public var trackPaletteSeedB: Float     // 4 B  (LM.3 — per-track palette perturbation seed component B; LM.3.2 calibration round 3: drives Y-channel of `a` perturbation + uniform `b` shift; combined magnitudes 0.20 + 0.05)
    public var trackPaletteSeedC: Float     // 4 B  (LM.3 — per-track palette perturbation seed component C; LM.3.2 calibration round 3: drives X-channel of `d` perturbation + uniform `c` shift; combined magnitudes 0.50 + 0.20)
    public var trackPaletteSeedD: Float     // 4 B  (LM.3 — per-track palette perturbation seed component D; LM.3.2 calibration round 3: drives Y-channel of `d` perturbation, magnitude 0.50)
    public var bassCounter: Float           // 4 B  (LM.3.2 — rising-edge of f.beatBass, scaled by beatStrength, debounced 80 ms)
    public var midCounter: Float            // 4 B  (LM.3.2 — rising-edge of f.beatMid)
    public var trebleCounter: Float         // 4 B  (LM.3.2 — rising-edge of f.beatTreble)
    public var barCounter: Float            // 4 B  (LM.3.2 — f.barPhase01 wrap; fallback every 4 bass beats)
    // Total: 376 B.  (LM.3.2 grew by 16 B: four band counters. LM.3 had grown by 24 B from LM.2's 336 B.)
}
```

Total buffer size: **376 B** at LM.3.2 (was 360 B at LM.3, 336 B at LM.2). Use `.storageModeShared` per UMA convention (D-006). The struct stride is asserted to match the matching MSL struct (`PresetLoader+Preamble.swift`) byte-for-byte — `LumenPatternStateLayoutTests.test_lumenPatternState_strideIs376` is the regression-lock; the placeholder buffer in `RayMarchPipeline.lumenPlaceholderBuffer` resized to 376 B at LM.3.2 to match.

**Migration notes.**

- The `ambientFloorIntensity` field stays on the struct for ABI continuity but is unused by LM.3.2 sceneMaterial. The silence-rest behaviour is now structural: counters stay at 0 → step stays at 0 → cells display their base palette colour at uniform 0.85–1.00 brightness with no bar pulse. Future increments may reuse the field for a different purpose; the engine keeps it zero-initialised.
- The four `trackPaletteSeed{A,B,C,D}` fields are written by `LumenPatternEngine.setTrackSeed(_:)` or `setTrackSeed(fromHash:)` once per track change. **At LM.3.2, `setTrackSeed(_:)` also zeroes the four band counters** — without this, an old track's accumulated counter values would carry into the new track's first beat and the new track's cells would jump straight to a far-off palette index. `_tick(...)` does **not** clear seeds or counters. App-layer wiring lives in `VisualizerEngine+Stems.resetStemPipeline(for:)`, which derives an FNV-1a 64-bit hash from `title + artist` and forwards it to the engine.
- The four band counters are floats (not ints) so the `beatStrength` scaling factor `clamp(0.3 + 1.4 × max(f.bass, f.mid, f.treble), 0.3, 1.0)` flows directly into the increment. The shader does `floor(counter / period)` to recover the integer step; counters can grow indefinitely over a session (a fresh-cache 4-minute track at 120 BPM with all-bass kicks accumulates ≤ 480 ticks × 1.0 ≈ 480 — well within Float32's exact-integer range up to 16,777,216).

### `RenderPipeline` extension

Add to `RenderPipeline.swift`:

```swift
private var directPresetFragmentBuffer3: MTLBuffer?

func setDirectPresetFragmentBuffer3(_ data: UnsafeRawPointer, length: Int) {
    // Same pattern as setDirectPresetFragmentBuffer / setDirectPresetFragmentBuffer2.
    // Buffer slot index: 8.
}
```

Bind at slot 8 in the same per-frame uniform contract as slots 6 and 7 (CLAUDE.md). Bound for ray-march presets that opt in via JSON; null otherwise.

**Documentation update required (LM.0):** CLAUDE.md GPU Contract section must add slot 8 to the per-preset fragment buffer documentation. Pattern: same paragraph structure as slots 6 and 7.

## Performance budget per increment

p95 frame time at 1080p Tier 2 (M3+):

| Increment | Budget | Rationale |
|---|---|---|
| LM.1 | ≤ 2.0 ms | Glass panel + 3 voronoi calls + Cook-Torrance + bloom + ACES. No pattern eval. |
| LM.2 | ≤ 2.5 ms | + 4-light analytical sample (~0.1 ms) + mood color modulation. |
| LM.3 | ≤ 2.7 ms | + stem-direct routing (no extra GPU work; CPU-side only). |
| LM.4 | ≤ 3.0 ms | + pattern engine eval (≤ 4 patterns × ≤ 5 ops per cell). |
| LM.5 | ≤ 3.5 ms | + silhouette occluder masks (1–3 SDF evaluations per cell) if Decision B.2 is adopted. |
| LM.6 | ≤ 3.5 ms | Polish only; no new GPU work. |
| LM.7 | ≤ 3.7 ms | + beat-accent ripple wavefront eval (cheap; piggybacks on radial_ripple pattern). |
| LM.8 | ≤ 3.7 ms | + mood-quadrant palette banks (lookup, no compute). |
| LM.9 | ≤ 3.7 ms | Certification target. |

**Final certified budget: p95 ≤ 3.7 ms at Tier 2; p95 ≤ 4.5 ms at Tier 1.** Well below the 16 ms / 14 ms ceilings. Lumen Mosaic should be the cheapest ray-march preset in the catalog.

If any increment exceeds its budget by > 25%, halt and report — do not press on with optimization until the cause is identified. The most likely culprits in advance: per-pixel pattern eval (mitigation: cell-quantize the eval to once per cell, not once per pixel — this requires care because Voronoi is a per-pixel function, but the cell ID is deterministic so we can hash to per-cell precomputed values).

## Certification fixtures

Each phase must be rendered against:

- **Silence** — `totalStemEnergy == 0`, all FeatureVector bands at AGC center (0.5). Verifies D-019 silence fallback **and the "cells stay coloured at silence (held, not faded)" rule** (Matt 2026-05-09).
- **Steady moderate energy** — bands at AGC center + 0.15. Verifies the preset is active but not frantic.
- **Beat-heavy** — `f.beat_bass = 0.7` periodic onsets at 120 BPM with 80 ms decay. Verifies pattern accents fire (LM.4+) and beat response invariant (≤ 2× continuous + 1.0).
- **Sustained bass** — `f.bass_dev = 0.4` constant. Verifies bass-agent intensity ramps without overdriving.
- **HV-HA mood** — `valence = 0.6, arousal = 0.6`. Verifies warm-character vivid palette (saturated reds / oranges / golds dominating).
- **LV-LA mood** — `valence = -0.5, arousal = -0.4`. Verifies cool-character **but still vivid** palette (saturated teals / blues / violets dominating). **Not desaturated, not pastel.**

Per Preset_Development_Protocol.md Gate 6.

**Vividness gate (LM.3+, hard requirement).** Every fixture except silence must produce per-cell colour values where the dominant cells have at least one channel `< 0.30` AND another channel `> 0.70` in linear space pre-tone-map (i.e. the palette must be saturated, not greyscale). The silence fixture has the same requirement applied to the held cell colours (cells frozen but still saturated). This gate exists because the LM.1 / LM.2 implementations failed it — both produced cream-haze output that visually clipped to the same channel ratio across the entire panel.

**LM.3 contact-sheet review additions** (alongside the above):
1. **Time-evolution check** — capture two frames 3 s apart at the same fixture; cell colours must visibly differ in the energetic fixtures (verifies `kCellHueRate` is producing cycling).
2. **Distinct-neighbour check** — sample 50 random cell-centre uvs in any non-silence frame; the colour distribution must span at least 1/3 of the palette range (verifies per-cell hash + palette is producing distinct hues, not a smooth field).
3. **No-cream check** — no fixture frame should have a dominant pixel value within ε of `(0.95, 0.85, 0.75)` (the retired LM.2 cream-haze region). Catches accidental retain of the old formula.

Each contact sheet (six fixtures) is a deliverable at LM.1, LM.2, LM.3, LM.4, LM.7, LM.9. Stored in `docs/VISUAL_REFERENCES/lumen_mosaic/contact_sheets/<increment>/` per Increment V.5 convention.

## Stop conditions

Stop implementation and report a blocker if:

- The engine cannot bind a fragment buffer at slot 8 because of an unforeseen RenderPipeline constraint. Likely root cause: existing slot 6/7 binding contract assumes uniform binding across all stages of staged presets; slot 8 may need to follow the same contract or be ray-march-only. If ray-march-only, document it as such in CLAUDE.md.
- `mat_pattern_glass` materially differs from the V.3 cookbook recipe (e.g., it was modified post-V.3 for Glass Brutalist v2 in a way that breaks our usage). Verify by reading `Materials/Dielectrics.metal` before LM.1.
- The deferred PBR pipeline cannot pass an emission-dominated material's color through to composite (Option α from §sceneSDF/sceneMaterial fails). Fall back to Option β with a documented decision.
- Performance at LM.1 (no audio, static backlight) exceeds 4 ms p95 at Tier 2. This would indicate something is wrong with the glass panel SDF or with the voronoi eval cost; investigate before adding any audio reactivity.
- The Voronoi cell `id` field is not stable across small `voronoi_f1f2` argument perturbations. Cells must have a single canonical ID per location; if the id flickers near cell edges, the per-cell pattern accent will jitter.
- The harness contact sheet cannot be captured for the preset's offscreen render path. Lumen Mosaic uses the standard ray-march path so this should not be an issue, but verify at LM.1.

## Debug requirements

Every preset increment must produce one or more of these debug captures, accessible via the existing `--preset-debug` harness flag:

- **`lumen_cells`** — render with cell IDs visualized (one color per cell hash). Sanity check that cells are stable, hex-biased, and at correct density.
- **`lumen_backlight`** — render the backlight field directly without cell quantization. Sanity check that light agents are at expected positions and intensities.
- **`lumen_patterns`** — render the active pattern fields as luminance, no backlight. Sanity check that patterns are active, have correct origins, and decay correctly.
- **`lumen_normal`** — render the perturbed normal as RGB. Sanity check that frost + height-gradient normal is producing the expected per-cell variation.
- **`lumen_emission`** — render the final emission term before tone-mapping. Sanity check that emission is in expected HDR range (typically 0–4).

These debug modes are gated behind the same `#ifdef DEBUG_LUMEN_MOSAIC` pattern used by Arachne for pass-separated debug output.

## Documentation updates required (per increment)

| Increment | Files to update |
|---|---|
| LM.0 | `CLAUDE.md` (slot 8 fragment buffer documentation), `DECISIONS.md` (new D-LM-buffer-slot-8 entry), `ENGINEERING_PLAN.md` (Phase LM header + LM.0 entry). |
| LM.1 | `CLAUDE.md` (Lumen Mosaic preset entry in Shaders/ list, JSON schema notes for `cell_density`, `cell_scale`, etc.), `ENGINEERING_PLAN.md` (LM.1 done-when results). |
| LM.2 | `CLAUDE.md` (light-agent layout + audio routing), `ENGINEERING_PLAN.md`. |
| LM.3 | `DECISIONS.md` (new D-LM-d4 entry for per-cell colour identity, new D-LM-e3 for procedural palette, retire D-LM-e2 authored banks), `CLAUDE.md` (Lumen Mosaic ledger updated for D.4 / E.3 + smoothedValence/Arousal in slot-8 struct + `kCellHueRate` tuning constant), `ENGINEERING_PLAN.md` (LM.3 done-when), `RELEASE_NOTES_DEV.md` (visible behaviour change). |
| LM.4 | `CLAUDE.md` (`LumenPatternEngine` pattern slots ledger), `ENGINEERING_PLAN.md`, `KNOWN_ISSUES.md` if any pattern bugs surface. |
| LM.5 | If per-stem hue affinity adopted: `DECISIONS.md` (D-LM-hue-affinity), `CLAUDE.md`. If silhouettes adopted: `DECISIONS.md` (D-LM-silhouettes). |
| LM.6 | `SHADER_CRAFT.md` if any tuning learnings warrant a cookbook update. |
| ~~LM.8~~ | **Retired 2026-05-09**: E.2 authored palette banks rejected, E.3 procedural palette ships at LM.3. |
| LM.9 | `RELEASE_NOTES_DEV.md`, `KNOWN_ISSUES.md` (close any tracked items), set `certified: true` in `LumenMosaic.json`, register golden hashes via `UPDATE_GOLDEN_SNAPSHOTS=1`. |

## JSON sidecar fields

Required in `LumenMosaic.json` (in addition to the standard fields):

```json
{
  "name": "Lumen Mosaic",
  "family": "geometric",
  "duration": 60,
  "passes": ["ray_march", "post_process"],
  "scene_camera": { "position": [0, 0, -3], "target": [0, 0, 0], "fov": 30 },
  "scene_lights": [{ "position": [0, 0, -1], "color": [0.9, 0.9, 0.9], "intensity": 0.5 }],
  "scene_fog": 0.0,
  "scene_ambient": 0.05,
  "visual_density": 0.65,
  "motion_intensity": 0.25,
  "color_temperature_range": [2700, 6500],
  "fatigue_risk": "low",
  "transition_affordances": ["fade_through_black", "crossfade"],
  "section_suitability": ["ambient", "comedown", "bridge"],
  "complexity_cost": { "tier1": 4.5, "tier2": 3.7 },
  "stem_affinity": {
    "drums": "ripple_origin",
    "bass": "agent_drift_speed",
    "vocals": "vocal_hotspot",
    "other": "ambient_palette_drift"
  },
  "lumen_mosaic": {
    "cell_density": 30.0,
    "cell_jitter": 0.85,
    "frost_amplitude": 0.10,
    "frost_scale": 80.0,
    "ambient_floor_intensity": 0.04,
    "light_agent_count": 4,
    "max_active_patterns": 4,
    "mood_smoothing_seconds": 5.0,
    "back_plane_depth": 1.5
  },
  "certified": false
}
```

The `lumen_mosaic` namespace is for preset-specific tunables read into `LumenPatternEngine` and forwarded to the shader via `LumenPatternState.ambientFloorIntensity` (other fields drive CPU-side state only).

## Shader file structure

`PhospheneEngine/Sources/Presets/Shaders/LumenMosaic.metal`:

```
// 1. Header: includes (preamble forward declarations are handled by PresetLoader+Preamble).
// 2. Constants: cell_density, frost_scale, etc., as #define or constexpr (with JSON override path).
// 3. struct LumenPatternState (must mirror Swift exactly).
// 4. helper functions:
//      mood_tint(valence, arousal) -> float3
//      sample_backlight_at(uv, ps, f, s) -> float3
//      evaluate_pattern_idle(uv, p, t) -> float
//      evaluate_pattern_radial_ripple(uv, p, t) -> float
//      evaluate_pattern_sweep(uv, p, t) -> float
//      evaluate_active_patterns(uv, cell_phase, ps, time) -> float
//      pattern_color_at(uv, cell_phase, ps) -> float3
// 5. sceneSDF
// 6. sceneMaterial
// 7. (optional) emission_output for matID == LUMEN_GLASS path (Option α from §sceneSDF section)
// 8. Debug fragment outputs (gated by #ifdef DEBUG_LUMEN_MOSAIC).
```

Target file length: 600–900 lines. Within SHADER_CRAFT.md §11.1's relaxed file_length lint for `.metal` files.

## Done-when summary table

| Increment | Done when |
|---|---|
| LM.0 | `directPresetFragmentBuffer3` slot 8 wired in `RenderPipeline`. CLAUDE.md GPU Contract section updated. DECISIONS.md D-LM-buffer-slot-8 entry. New build green; existing tests untouched. ✅ |
| LM.1 | Static-backlight glass panel renders. Contact sheet present. PresetAcceptanceTests passes. p95 ≤ 2.0 ms. ✅ |
| LM.2 | Mood-coupled 4-light backlight. Continuous-energy primary drivers. D-019 silence fallback verified. Slot-8 binding wired. p95 ≤ 2.5 ms. ⚠ Engine + GPU contract verified; visual rejected at production review (output muted, cells invisible). LM.3 ships the substantive look. |
| LM.3 | **Per-cell colour identity from `palette()` keyed on cell hash + `accumulated_audio_time × kCellHueRate` + mood** (D.4). Procedural palette via V.3 IQ cosine (E.3). `LumenPatternState` extended +24 B with `smoothedValence` / `smoothedArousal` + 4 × per-track palette seed fields (struct grew to 360 B). **⚠ Result rejected in production**: cells did not visibly cycle on real Spotify-normalised audio. BUG-012 — Spotify volume normalisation pulls mid + treble bands toward zero; `accumulated_audio_time` advanced ~0.045 / sec instead of ~0.5 / sec, so the time-driven cycle was effectively static for entire songs. Procedural-palette + per-cell-hash + mood-coupled-parameters infrastructure proven correct; the *time-driven cycling* mechanism is what failed. |
| LM.3.1 | Agent-position-driven static-light field as backlight character on top of LM.3 (`kAgentStaticIntensity = 0.50`, `kCellMinIntensity = 0.05`, sharper `attenuationRadius = 12`). **⚠ Result rejected by Matt 2026-05-09**: "fixed-color cells with brightness modulation; the bright pools dominated the visual story." The four agent positions painted four bright lobes that read as the visual subject; cells underneath felt static. |
| LM.3.2 | **Substantive look ships here.** Decision D.5 — band-routed beat-driven dance: cells hashed (`cell_id ^ trackSeedHash`) into bass / mid / treble / static teams (30 / 35 / 25 / 10 percent), advance palette index discretely on rising-edge of `f.beatBass / beatMid / beatTreble` (debounced 80 ms, scaled by `beatStrength`). Per-cell `period ∈ {1, 2, 4, 8}` Pareto-distributed from hash. Brightness uniform with hash jitter `[0.85, 1.0]`; bar pulse `+30 % × bar_phase01^8`. `LumenPatternState` extended +16 B with four band counters (`bassCounter / midCounter / trebleCounter / barCounter`; struct grows to 376 B). Per-track palette seed magnitudes bumped (was 0.05/0.05/0.10/0.20 → 0.20/0.20/0.30/0.50). LM.3.1 agent-position static field retired; agent `intensity / colorR/G/B` fields kept on struct for ABI but unused by shader. M7-tunable surface: `kPaletteStepSize` (0.137), `kBarPulseMagnitude` (0.30), `kBarPulseShape` (8.0), `kBassTeamCutoff` / `kMidTeamCutoff` / `kTrebleTeamCutoff` (30 / 65 / 90), `beatTriggerHigh` / `beatDebounceSeconds` (0.5 / 0.08 s), `kSeedMagnitude{A,B,C,D}` (0.20 / 0.20 / 0.30 / 0.50), `kCellIntensityBase / Jitter` (0.85 / 0.15). Vividness gate met across all five contact-sheet fixtures. p95 ≤ 2.8 ms. **⏳ awaiting M7 review on real session** (commits TBD 2026-05-09). |
| LM.4 | Pattern engine v1 active (idle / radial_ripple / sweep). Bar-boundary triggers. Drum-onset ripples take per-cell palette colour (don't override with their own). p95 ≤ 3.0 ms. |
| LM.5 | Pattern engine v2 (cluster_burst / breathing / noise_drift). **Optional**: per-stem hue affinity (Decision E.b) if LM.3 / LM.4 review judges unified-palette feel undifferentiated stem-wise. p95 ≤ 3.5 ms. |
| LM.6 | Fidelity polish: micro-frost + specular tuning + cell density A/B vs ref `04`, palette parameter A/B vs ref `05`. p95 ≤ 3.5 ms. |
| LM.7 | Beat accent layer complete: bar-line shimmer + vocal hotspot (drum ripples land at LM.4). p95 ≤ 3.7 ms. |
| ~~LM.8~~ | **Retired 2026-05-09**: E.2 authored palette banks rejected on monotony grounds; E.3 procedural palette ships at LM.3. |
| LM.9 | Certification: rubric 10/15 mandatory met; perf verified across silence/steady/beat-heavy/HV-HA/LV-LA; golden hashes registered; **vividness gate green at all six fixtures**; `certified: true`. |

---

## Revision history

- **2026-05-09 (LM.3.2)** — second pivot in 24 hours. **Decision D.4 (continuous palette cycling on `accumulated_audio_time × kCellHueRate`) retired**: cells did not visibly cycle on Spotify-normalised audio (BUG-012). **Decision D.4 + LM.3.1 (agent-position static-light field as backlight) retired** by Matt 2026-05-09 ("the bright pools dominated the visual story"). Decision D.5 — band-routed beat-driven dance — adopted: cells advance palette index discretely on rising-edge of their team's FFT-band beat; team + period sampled per-cell from `hash(cell_id ^ track_seed)`. `LumenPatternState` extended +16 B with four band counters (struct now 376 B). Per-track palette seed magnitudes bumped (was 0.05/0.05/0.10/0.20 → 0.20/0.20/0.30/0.50). `kCellHueRate` retired (no continuous cycle). `kAgentStaticIntensity` / `kCellMinIntensity` retired (uniform brightness with hash jitter). Agent `intensity / colorR/G/B` fields kept on struct for ABI continuity but unused by sceneMaterial. New shader constants: `kPaletteStepSize`, `kBarPulseMagnitude`, `kBarPulseShape`, `kBassTeamCutoff` / `kMidTeamCutoff` / `kTrebleTeamCutoff`, `kCellIntensityBase` / `Jitter`. Engine: `LumenPatternEngine.tick(...)` now extracts an `updateBandCounters(features:)` helper for SwiftLint compliance; `setTrackSeed(_:)` zeroes the four band counters in addition to writing the seed (so the new track's first beat starts cells at step 0, not at the previous track's accumulated count).
- **2026-05-09 (LM.3 / first pivot)** — major pivot after LM.2 production review. Aesthetic role flipped from meditative to energetic (Matt 2026-05-09). **Decision D.1 (cell-quantized agent sample) retired**: produced gradient blob in production, no visible cells; D.4 (per-cell colour identity from `palette()` keyed on cell hash) adopted. **Decision E.1 (cream-baseline mood tint) and E.2 (4 authored palette banks) retired**: muted output and monotony respectively; E.3 (procedural V.3 IQ cosine palette, mood shifts `(a, b, c, d)` continuously) adopted. `LumenPatternState` extended +24 B (smoothedValence + smoothedArousal + 4 × per-track palette seed scalars; struct grew to 360 B). LM.8 retired; substantive look ships at LM.3. New "vividness gate" added to certification fixtures. New `kCellHueRate` constant introduced as the master tuning knob for per-cell hue cycling speed. `mat_pattern_glass` material recipe and `sceneSDF` glass panel layout (panel oversize 1.50×, Voronoi relief, fbm8 frost) all unchanged. Slot-8 binding contract widened in LM.2 (G-buffer + lighting both bind) is retained.
- **2026-05-08 (LM.0 era)** — original document, supporting Decisions A.1 / B.1 / C.2 / D.1 / E.1 / F.1 / G.1 / H.1. LM.0–LM.2 implemented under this version.
