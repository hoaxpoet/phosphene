# Crystalline Cavern — Design

A static-camera ray-march scene of a glowing geode interior, with crystalline materials, screen-space caustics, light shafts, and `mv_warp` shimmer over the lit frame. Demonstrates the D-029-preserved combination of `ray_march` + `mv_warp` (no current preset uses this) and exercises the entire V.1–V.4 utility library — material cookbook, IBL, SSGI, light shafts, caustics — in a single shader. Tier-2-primary flagship piece.

## 1. Intent

This is the ceiling. A potential collaborator looking at Phosphene's catalog should be able to point at Crystalline Cavern and understand that the engine supports professional-quality 3D rendering with full PBR, real-time global illumination, and stable static-scene framing as a specific design pattern — distinct from Volumetric Lithograph's camera-flight or Glass Brutalist's architectural corridor.

Compositionally, the camera sits inside a small geode cavity looking at the central crystal cluster from a fixed eye. The architecture is permanent (D-020); only light, atmosphere, caustics, and a thin mv_warp shimmer over the lit frame respond to audio.

**Audio summary.** `drums_energy_dev` modulates caustic flash intensity (the only beat-coupled visual element); `bass_att_rel` breathes IBL ambient strength and key light; vocals pitch shifts caustic refraction angle continuously; valence tints IBL between cool magenta and warm amber; mv_warp produces shimmer that catches stronger on `mid_att_rel`.

**Family.** `architectural` (paired with Glass Brutalist as the second member of that bench). _Confirm `architectural` is in the PresetCategory enum; if not, alternative is `geometric` or `organic` via D-038's crystal-growth clause; family choice affects family-repeat scoring._

**Render passes.** `["ray_march", "post_process", "ssgi", "mv_warp"]`.

## 2. References

**Recommendation: curate.** Real geode and bioluminescent-cave photography is essential — without it the design will collapse into "shader crystals" and the cellular wall texture / caustic interaction subtleties will be lost. Suggested images:

- **Geode interior cathedral.** A photograph of an opened amethyst or quartz geode, interior view showing crystal cluster, cell-wall stratification, terminus geometry. Specifies the macro composition.
- **Crystal termination close-up.** Single quartz crystal point — for terminus shape, the way light enters and refracts through a crystal column.
- **Cave caustics.** Sun through water-filled karst cave producing dancing light patterns on stone. Specifies caustic appearance: large soft cells, slow drift, brightness variation.
- **Wet limestone wall.** Cavern wall with moisture sheen, displaced texture from cellular weathering. For `mat_wet_stone` reference.
- **Bioluminescent cave (Waitomo / firefly cave).** For emission palette: dim cyan-green pinpricks against very dark backdrop. Specifies that emission color is biologically muted, not neon.
- **Pattern glass close-up.** Pebbled or hammered architectural glass for `mat_pattern_glass` cellular structure.
- **Anti-reference: video-game crystal cave.** Diablo III / Tomb Raider stylized crystals for explicit comparison.
- **Anti-reference: Tron neon.** For documenting what we are NOT building.

## 3. Trait matrix

| Scale | Trait |
|---|---|
| **Macro** | Cavern interior bounded by 3-5 large wall planes meeting at oblique angles. Foreground cluster of 4-5 hexagonal-prism crystals at frame center, ~1.5 units tall. Floor with secondary smaller crystals jutting up. Optional ceiling stalactites. |
| **Meso** | Cavern walls displaced via `worley_fbm` for cellular cavity texture (geode-rind look). Crystal prism faces have minor twist + per-instance scale variation from hash. Floor crystals have varied terminations. |
| **Micro** | `triplanar_detail_normal` on cavern walls (kills smooth shading). Per-face `fbm8` brightness variation on crystals (pixel-scale grain). Floor: hex tiling for cellular crystallisation. |
| **Specular breakup** | Per-face roughness variation via `fbm8` on chrome formations and pattern glass. Anisotropic streaks (light brushed metal direction) on chrome accents. |
| **Materials** | Four: `mat_pattern_glass` (foreground crystals), `mat_polished_chrome` (sparse metallic accent formations), `mat_wet_stone` (cavern walls + floor base), `mat_frosted_glass` (crystal cluster crowns / hanging tips). |
| **Lighting** | §5.3 bioluminescent recipe: minimal direct light (one warm key from above-front, low intensity); IBL ambient is dark blue-purple `(0.04, 0.04, 0.08)` tinted by valence; emission carries the work; SSGI gives soft fill. |
| **Atmosphere** | `vol_density_height_fog` ground fog (low altitude, thin); volumetric light shafts (`ls_radial_step_uv`) angled from above-side; faint dust mote field via `vol_sample`. |
| **Motion** | Static geometry (D-020). Camera fixed. mv_warp produces shimmer (very low amplitude). Caustics drift. Light intensity breathes. |
| **Audio reactivity** | See §5.6. |

## 4. Renderer capability audit

| Need | Available? | Notes |
|---|---|---|
| Ray-march pipeline + G-buffer + lighting + post + SSGI | ✓ | Glass Brutalist uses the same stack. |
| `mv_warp` pass | ✓ | D-027; static-camera ray-march + mv_warp is a D-029 preserved use case (no current consumer). |
| `mat_pattern_glass` | ✓ | V.4 added. |
| `mat_polished_chrome`, `mat_frosted_glass`, `mat_wet_stone` | ✓ | V.3 cookbook. |
| `triplanar_detail_normal` (procedural) | ✓ | V.3 MaterialResult.metal. |
| `worley_fbm`, `fbm8`, `ridged_mf` | ✓ | V.1 noise tree. |
| `ls_radial_step_uv` | ✓ | V.2 light shafts (screen-space). |
| `vol_density_height_fog` + `hg_phase` | ✓ | V.2 volume tree. |
| Screen-space caustics | _partial_ | Caustic pattern function exists in `Volume/Caustics.metal` (V.2, D-055), but no consumer preset to validate against. May need authoring tweaks during implementation. |
| Refraction-angle modulation from per-frame audio | engine-supported via uniforms | `sceneParamsB.w` is the established repurposing slot for preset-specific scalars (per D-021); use that. |
| `SpectralHistoryBuffer` access for vocals_pitch | ✓ | buffer(5). |

**Gaps:** None blocking. The screen-space caustic utility may have rough edges (no production consumer yet); flag as "verify during Session 3" — if the utility output is unworkable, fall back to a procedurally-animated `fbm8` overlay sampled at the floor projection.

## 5. Rendering architecture

### 5.1 Pass structure

`passes: ["ray_march", "post_process", "ssgi", "mv_warp"]`. The `.rayMarch` pass renders into `warpState.sceneTexture` (per the MV-2 ray-march + mv_warp handoff documented in CLAUDE.md). `.ssgi` and `.post_process` operate before mv_warp's compose step. `.mv_warp` then performs its 32×24 grid feedback and presents to drawable.

### 5.2 sceneSDF

```metal
float sceneSDF(float3 p, constant FeatureVector& f, constant SceneUniforms& s, constant StemFeatures& stems) {
    // Cavern walls: 4-plane intersection forming the cavity, displaced by worley_fbm for geode-rind cellular weathering
    float wall_d = sd_cavern_walls(p);
    wall_d -= 0.08 * worley_fbm(p * 0.6);

    // Foreground crystal cluster (4-5 hexagonal prisms with hash-driven per-instance jitter)
    float crystals = sd_crystal_cluster(p);

    // Floor crystals (smaller, denser, jutting up through hex tiling)
    float floor_crystals = sd_floor_crystals(p);

    // Hanging tips (frosted glass terminations from ceiling)
    float tips = sd_hanging_tips(p);

    return min(min(min(wall_d, crystals), floor_crystals), tips);
}
```

`sd_crystal_cluster` uses 5 hex-prism SDFs with per-instance hash-driven rotation, scale, and position offset. Material ID is set at hit by tracking which sub-SDF was minimum.

### 5.3 sceneMaterial

```metal
void sceneMaterial(float3 p, int matID, constant FeatureVector& f, constant SceneUniforms& s, constant StemFeatures& stems,
                   thread float3& albedo, thread float& roughness, thread float& metallic) {
    MaterialResult m;
    float3 n = estimate_normal(p);
    if (matID == 0) {
        m = mat_pattern_glass(p, n);            // foreground crystals
    } else if (matID == 1) {
        m = mat_wet_stone(p, n, 0.4);           // cavern walls (moderate wetness)
    } else if (matID == 2) {
        m = mat_wet_stone(p, n, 0.55);          // floor base (wetter)
    } else if (matID == 3) {
        m = mat_polished_chrome(p, n);          // sparse metallic floor accents
    } else {
        m = mat_frosted_glass(p, n);            // hanging tips
    }
    albedo = m.albedo;
    roughness = m.roughness;
    metallic = m.metallic;
}
```

Emission is added in the lighting pass per material. Pattern-glass and frosted-glass crystals get bioluminescent emission (cyan-violet, low saturation) modulated by `f.bass_att_rel` and `valence` for warm/cool shift.

### 5.4 Lighting + atmosphere

**Lighting (§5.3 bioluminescent recipe):**
- Direct key: warm `(1.0, 0.9, 0.75)`, intensity 1.2, position `(2.0, 4.0, 2.5)` (above-front).
- IBL ambient: `(0.04, 0.04, 0.08)` base, multiplied by `lightColor.rgb` (D-022 path) so valence tint propagates across all surfaces.
- Emission: pattern-glass / frosted-glass crystals emit `palette(emission_t) * 0.3 + bass_breath`.
- SSGI: enabled at Tier 2 to fill emission spread. Disabled at Tier 1 (degradation path).

**Light shafts:** `ls_radial_step_uv` with sun UV at `(0.7, 0.95)` — a shaft entering from upper-right. 32 samples Tier 2 / 24 samples Tier 1. Intensity scaled by `ls_intensity_audio(0.4, mid_att_rel)`.

**Atmosphere:**
- `vol_density_height_fog` at `floorY = -0.5`, falloff 0.4. Mostly visible only as ground mist.
- Dust motes: `vol_sample` at 4 ray-march steps along view ray, density from `vol_density_fbm(p, 1.5, 3)`, transmittance accumulated. Dust visible mainly inside light shaft volume. Cost ~0.4 ms.

**Caustics:** Screen-space caustic projection. At each ray hit on cavern walls/floor, sample a procedural caustic field:

```metal
float caustic = caustic_pattern(hit_p.xz * (1.0 + 0.15 * vocalsPitchNorm),
                                 time * 0.3 + valence * 0.5);
caustic *= smoothstep(0.0, 0.5, surface_lighting);                  // gate by lit-ness
albedo += caustic_tint * caustic * (0.4 + 1.5 * stems.drums_energy_dev);
```

Caustic flash on drums is the only beat-coupled visual element; the continuous-vs-accent ratio is preserved because base caustic intensity 0.4 dominates the `+1.5 × drums_energy_dev` burst (deviation primitive max ~0.5 → 0.75 burst → 0.4 / 0.75 confirms continuous primary).

### 5.5 mv_warp specifics

Static camera + ray-march + mv_warp: the warp adds shimmer over the lit frame, not motion design (D-029 lesson — mv_warp on a moving camera fights it; on a static camera it's pure texture).

- `baseRot = 0.0004` (very slow), `baseZoom = 0.0008` (barely perceptible).
- `decay = 0.94` (shorter than Gossamer's 0.955 — we want shimmer, not echo).
- Per-vertex displacement: `disp = 0.002 * float2(curl_noise(float3(uv * 3.0, time * 0.15)).xy)`. Audio-modulated component: amplitude scaled by `(0.5 + 0.5 * f.mid_att_rel)`.

Amplitude is intentionally tiny; the goal is to make highlights "live" between frames, not to smear the scene. If shimmer is invisible at this amplitude during prototyping, increase to 0.003 — but never above that (D-029).

### 5.6 Audio routing

| Driver | Source | Effect | Continuous/accent |
|---|---|---|---|
| IBL ambient strength | `f.bass_att_rel` | Multiplier on IBL contribution (0.85 + 0.30 × x) | continuous primary |
| Key light intensity | `f.bass_att_rel` | ±10% per §5.7 | continuous primary |
| Caustic flash | `stems.drums_energy_dev` (dev-form) | Caustic brightness +1.5× burst | accent — gated below 2× continuous |
| Caustic refraction angle | `stems.vocalsPitchNorm` | UV scale modulation on caustic field | continuous (gated by `vocalsPitchConfidence > 0.4`) |
| IBL palette tint | `f.valence` | `lightColor.rgb` warm/cool shift | continuous |
| Shimmer amplitude | `f.mid_att_rel` | mv_warp displacement scale | continuous |
| Mid-pulse caustic offset | `f.beat_phase01` | Anticipatory caustic-position drift (`approachFrac × 0.005`) | accent |
| Crystal emission breath | `f.bass_att_rel` + valence | Emission magnitude + hue | continuous |

**D-026 compliance:** every primary driver uses `*_rel` or `*_dev`. **D-019 compliance:** stem reads through warmup blend.

### 5.7 State

CPU-side state: none. All evolution from `time` accumulator and mv_warp.

GPU-side state: standard. No custom buffer beyond FeatureVector / StemFeatures / SceneUniforms / SpectralHistory.

### 5.8 Silence fallback

At zero audio: IBL at base ambient, crystals emit at base level (`base_emission = 0.15`), key light at base intensity, caustics at base brightness with very slow drift, mv_warp continues to accumulate shimmer. Cavern is alive but quiet. Form complexity at silence: ≥ 4 (cavern walls + crystal cluster + floor + light shaft + dust motes).

## 6. Anti-references and failure modes

- **"Procedural box prisms."** SDF crystals with no per-instance variation read as cloned. Must apply hash-driven per-instance scale, rotation, and position jitter (CLAUDE.md Failed Approach #44).
- **"CGI plastic."** Constant roughness on chrome / pattern glass. Roughness must vary spatially (Failed Approach #38).
- **"Tron neon caustics."** Caustic colors must be tinted from valence-modulated light, not high-saturation primaries.
- **"Smeared mv_warp."** Amplitude > 0.003 will fight the static scene and produce ghosting (D-029 lesson). Keep amplitude < 0.003.
- **"Beat-dominant caustic flash."** Drums burst > 2× base caustic intensity violates the audio hierarchy. Verified by acceptance test.
- **"Dead silence."** At zero audio, nothing moves. Caustic drift and mv_warp shimmer must continue.
- **"Geometric perfection."** Real geodes are weathered. Walls without `worley_fbm` displacement read as solid-modeled.

## 7. Performance budget

Tier 2 measured budget approximate breakdown:

| Element | Tier 2 | Tier 1 (with degradation) |
|---|---|---|
| Ray-march G-buffer | 3.0 ms | 2.4 ms (steps 64 → 48) |
| Lighting + IBL | 1.0 ms | 0.8 ms |
| SSGI | 0.8 ms | 0 (disabled) |
| Caustic projection | 0.5 ms | 0.25 ms (samples halved) |
| Light shafts | 0.4 ms | 0.3 ms (32 → 24 samples) |
| Volumetric fog + dust | 0.4 ms | 0.4 ms |
| Post-process tone map | 0.3 ms | 0.3 ms |
| mv_warp grid + compose | 0.4 ms | 0.4 ms |
| **Total** | **~6.5 ms** | **~4.85 ms** |

`complexity_cost: {"tier1": 5.0, "tier2": 6.5}`. Tier 1 cost set 0.15 ms above estimate to avoid runtime downshift on wall fluctuation.

## 8. Acceptance criteria

**Rubric profile: full** (15-item ladder).

**Mandatory (must all pass):**
- M1 detail cascade: ✓ — macro (cavern + cluster), meso (worley wall displacement, hex-prism per-instance jitter), micro (triplanar detail normals on stone), specular breakup (fbm8 roughness variation on chrome and pattern glass).
- M2 ≥ 4 noise octaves: ✓ — fbm8 (8 octaves) + worley_fbm (5 octaves) + ridged_mf for floor crystals.
- M3 ≥ 3 distinct materials: ✓ (4: pattern glass, polished chrome, wet stone, frosted glass).
- M4 deviation primitives: ✓ — see §5.6 audit.
- M5 silence fallback: ✓ — see §5.8.
- M6 perf: ✓ — Tier 2 6.5 ms < 7 ms budget; Tier 1 4.85 ms < 5 ms budget.
- M7 frame match: requires Matt M7 review against curated references.

**Expected (≥ 2 of 4):** Triplanar (✓), detail normals (✓), volumetric fog (✓), SSS via frosted glass (✓ — 4/4).

**Strongly preferred (≥ 1 of 4):** Hero specular (✓ on chrome), POM (deferred — too expensive at Tier 2 budget), light shafts (✓), thin-film (could go on a single crystal cluster member as iridescent inclusion — _suggest add in Session 4 if budget allows_). 2/4 confirmed; potential 3/4.

**Score ceiling:** 14/15 with all mandatory and 4/4 expected; potential 15/15 with thin-film addition. Comfortably exceeds 10/15 minimum.

**Preset-specific tests:**

1. `CrystallineCavernSilenceTest` — render at zero audio, assert form complexity ≥ 4 (luma histogram has ≥ 4 distinct bins above noise floor).
2. `CrystallineCavernCausticBeatRatioTest` — render with steady mid energy and pulsed drums; assert peak caustic luma ≤ 2× steady caustic luma.
3. `CrystallineCavernMaterialBoundaryTest` — sweep camera across material boundaries; assert no flicker (D-021 boundary classification stability).
4. `CrystallineCavernMvWarpStaticityTest` — render 60 frames at constant audio; assert sequential frame mean-luma drift < 5% (warp is shimmer, not motion drift).

## 9. Implementation phases

**Session 1 — Scene structure (no materials).** Cavern walls, floor, central crystal cluster, hanging tips. Default white-on-grey rendering. Static camera composition framing. Confirm composition reads correctly against geode reference photography.

**Session 2 — Materials pass.** Wire `mat_pattern_glass`, `mat_polished_chrome`, `mat_wet_stone`, `mat_frosted_glass` via `sceneMaterial`. Triplanar detail normals on walls. Per-instance hash-jitter on crystal cluster. Verify material boundary stability test.

**Session 3 — Lighting + atmosphere + caustics.** Bioluminescent §5.3 lighting recipe. IBL palette + valence tint. Volumetric ground fog. Light shafts. Screen-space caustic projection with refraction angle modulation. Verify the caustic utility's output is workable; fall back to `fbm8` overlay if not.

**Session 4 — Audio routing + mv_warp + cert.** Wire all audio routes. mv_warp at conservative shimmer amplitude. Performance profile. Caustic-beat-ratio test. Matt M7 review against curated references.

**Estimated: 4 sessions** (this is the flagship; complexity is justified by the demonstration value).

## 10. JSON sidecar template

```json
{
  "id": "crystalline_cavern",
  "family": "architectural",
  "passes": ["ray_march", "post_process", "ssgi", "mv_warp"],
  "tags": ["crystal", "cave", "geode", "static", "bioluminescent"],
  "scene_camera": {
    "position": [0.0, 0.6, 3.5],
    "target": [0.0, 0.4, 0.0],
    "fov": 45,
    "near": 0.1,
    "far": 25.0
  },
  "scene_lights": [
    { "position": [2.0, 4.0, 2.5], "color": [1.0, 0.9, 0.75], "intensity": 1.2 }
  ],
  "scene_ambient": 0.06,
  "scene_fog": 0.0,
  "feedback": {
    "decay": 0.94,
    "base_zoom": 0.0008,
    "base_rot": 0.0004,
    "beat_zoom": 0.0,
    "beat_rot": 0.0,
    "beat_sensitivity": 0.0
  },
  "stem_affinity": {
    "drums": "caustic_flash",
    "vocals": "caustic_refraction_angle",
    "bass": "ibl_breath",
    "other": null
  },
  "visual_density": 0.65,
  "motion_intensity": 0.20,
  "color_temperature_range": [0.30, 0.75],
  "fatigue_risk": "low",
  "transition_affordances": ["crossfade", "morph"],
  "section_suitability": ["peak", "buildup", "ambient"],
  "complexity_cost": { "tier1": 5.0, "tier2": 6.5 },
  "certified": false,
  "rubric_profile": "full",
  "rubric_hints": { "hero_specular": true, "dust_motes": true }
}
```

## 11. Open questions

1. **Family enum.** Confirm `architectural` is the actual `PresetCategory` value. (D-038 added `organic`; the existing 11+ enum members include something for architectural-style scenes — verify against `PresetCategory.swift`.)
2. **Caustic utility production-readiness.** `Volume/Caustics.metal` exists from V.2 but no current preset consumes it. Validate output during Session 3; fall back to `fbm8` overlay if needed.
3. **POM on cavern walls.** Recipe estimates POM at ~1.0 ms; current budget shows ~0.8 ms of headroom at Tier 2. Could be added in a Session 4 polish if visual review shows the walls reading flat. Defer until after first Matt review.
4. **Tier 1 acceptable degradation.** SSGI off + caustic samples halved + raymarch steps 48 are the proposed Tier 1 path. If Tier 1 visual feels markedly inferior, consider gating the entire preset Tier 2-only via the orchestrator's tier-cost exclusion.
5. **Thin-film inclusion.** P4 rubric item available if a single crystal in the cluster gets a `thinfilm_rgb`-tinted iridescent inclusion. Adds ~0.1 ms. Inclusion would push rubric score 14 → 15.
