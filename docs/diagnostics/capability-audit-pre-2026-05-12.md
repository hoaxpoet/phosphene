# Phosphene Shader Capability Consumer Matrix — Pre-Audit Data Gather

**Generated 2026-05-12 for 15 production preset shaders.** Inventory data feeds `docs/CAPABILITY_GAP_AUDIT.md`. This file is the raw evidence base; the audit doc applies verdicts.

**Analysis excludes:** `Utilities/` subtree and `ShaderUtilities.metal` — those are utility implementations, not consumers; only counts production preset consumers.

**Architectural caveat — V.4 PBR.** The "zero consumers" verdict on `cook_torrance` / `fresnel_schlick` / `ggx_d` etc. reflects only what preset shaders call directly. The engine's `Renderer/Shaders/RayMarch.metal` runs its own Cook-Torrance + Fresnel via private `rm_fresnel` (`RayMarch.metal:123, 137, 386`) for ray-march presets — preset code defines `sceneSDF` + `sceneMaterial` (out-params: albedo / roughness / metallic / matID) and the engine's lighting fragment does the actual PBR math. The V.4 PBR utility tree IS loaded into the preset preamble (`PresetLoader+Preamble.swift:193`) and is theoretically callable from preset code, but its intended consumer is direct-fragment presets that need lighting math without the ray-march pipeline OR custom shading inside ray-march `sceneMaterial`. Verdict assignment must reflect this distinction.

**Architectural caveat — `mv_warp`.** Gossamer is the one production consumer (`mvWarpPerFrame` + `mvWarpPerVertex` defined). The audit prompt's framing of "zero consumers since the April reverts" is outdated post-Gossamer.

**Architectural caveat — passes vs symbols.** The pass × preset table below complements the symbol matrix. A preset's `passes` array determines which engine-level render-pipeline branches run; the symbol matrix shows which utility functions the preset's fragment code calls. They are independent gates.

## Pass × Preset Table (15 production presets, post-Drift Motes retirement)

| Preset | Family | Passes | Certified |
|---|---|---|---|
| Arachne | organic | `["staged"]` | false |
| FerrofluidOcean | abstract | `["post_process"]` | false |
| FractalTree | fractal | `["mesh_shader"]` | false |
| GlassBrutalist | geometric | `["ray_march", "ssgi", "post_process"]` | false |
| Gossamer | organic | `["mv_warp"]` | false |
| KineticSculpture | abstract | `["ray_march", "post_process"]` | false |
| LumenMosaic | geometric | `["ray_march", "post_process"]` | **true** |
| Membrane | fluid | `["feedback"]` | false |
| Nebula | particles | `["direct"]` | false |
| Plasma | hypnotic | `["direct"]` | false |
| SpectralCartograph | instrument | `["direct"]` | false |
| StagedSandbox | instrument | `["staged"]` | false |
| Starburst | abstract | `["feedback", "particles"]` | false |
| VolumetricLithograph | fluid | `["ray_march", "post_process"]` | false |
| Waveform | waveform | `["direct"]` | false |

Pass adoption summary:
- `direct`: 4 (Nebula, Plasma, SpectralCartograph, Waveform)
- `ray_march`: 4 (GlassBrutalist, KineticSculpture, LumenMosaic, VolumetricLithograph)
- `post_process`: 5 (FerrofluidOcean + 4 ray-march presets)
- `feedback`: 2 (Membrane, Starburst)
- `staged`: 2 (Arachne, StagedSandbox)
- `mv_warp`: 1 (Gossamer)
- `mesh_shader`: 1 (FractalTree)
- `particles`: 1 (Starburst)
- `ssgi`: 1 (GlassBrutalist)

## Test fixture references (RETIRE-blocking gates)

The following utility files have dedicated test fixtures (`PhospheneEngine/Tests/PhospheneEngineTests/Utilities/*.swift`). RETIRE verdicts on any of these utilities require coupled test-file deletion as part of the cleanup increment:

`NoiseTestHarness.swift` (V.1 noise — high coverage), `PBRUtilityTests.swift` (V.4 PBR — ~45 tests), `VoronoiTests.swift`, `CausticsTests.swift`, `CloudsTests.swift`, `ColorUtilityTests.swift`, `FlowMapsTests.swift`, `GrungeTests.swift`, `HenyeyGreensteinTests.swift`, `LightShaftsTests.swift`, `ProceduralTests.swift`, `RayMarchAdaptiveTests.swift`, `ReactionDiffusionTests.swift`. (V.2 SDF primitives + Materials cookbook covered by `SDFPrimitivesTests`, `SDFBooleanTests`, `SDFModifiersTests`, `SDFDisplacementTests`, `HexTileTests`, `ParticipatingMediaTests`.)

## FidelityRubric symbol coupling

`PhospheneEngine/Sources/Presets/Certification/FidelityRubric.swift:61-79` contains a hardcoded list of all 19 V.3 cookbook materials (`mat_polished_chrome` through `mat_concrete`) used by the M3 (≥3 materials) automated check. RETIRE verdicts on any V.3 material require corresponding edits to this list, otherwise the rubric will look for symbols that no longer exist (likely silent passes — the substring grep returns no matches, M3 fails for all presets, no false positives but a noisy gate).

## Symbol Matrix

## Summary Statistics

- Total capabilities analyzed: 260
- Capabilities with ≥1 consumer: 58
- Capabilities with zero consumers: 202
- Coverage: 22.3%

## V.1 Noise

| Capability | Consumer Count | Presets |
|---|---|---|
| `fbm8` | 2 | Arachne, LumenMosaic |
| `fbm4` | 1 | Arachne |
| `hash_f01_2` | 1 | Arachne |

### ZERO CONSUMERS (19 symbols)

blue_noise_sample, curl_noise, fbm12, fbm_vec3, hash_f01, hash_u32, ign, ign_temporal, perlin2d, perlin3d, perlin4d, ridged_mf, simplex3d, simplex4d, warped_fbm, warped_fbm_vec, worley2d, worley3d, worley_fbm

## V.2 Geometry SDF primitives

| Capability | Consumer Count | Presets |
|---|---|---|
| `sd_sphere` | 1 | Arachne |
| `sd_box` | 1 | LumenMosaic |
| `sd_capsule` | 1 | Arachne |

### ZERO CONSUMERS (15 symbols)

sd_cone, sd_cylinder, sd_ellipsoid, sd_gyroid, sd_helix, sd_hexagon, sd_mandelbulb_iterate, sd_octahedron, sd_plane, sd_pyramid, sd_round_box, sd_schwarz_d, sd_schwarz_p, sd_segment_2d, sd_torus

## V.2 SDF operations

| Capability | Consumer Count | Presets |
|---|---|---|
| `op_smooth_union` | 1 | Arachne |
| `op_smooth_subtract` | 1 | Arachne |
| `op_blend` | 1 | Arachne |

### ZERO CONSUMERS (5 symbols)

op_chamfer, op_intersect, op_smooth_intersect, op_subtract, op_union

## V.2 SDF modifiers

### ZERO CONSUMERS (9 symbols)

mod_bend, mod_extrude, mod_mirror, mod_onion, mod_repeat, mod_revolve, mod_round, mod_scale, mod_twist

## V.2 Displacement

### ZERO CONSUMERS (5 symbols)

displace_beat_anticipation, displace_energy_breath, displace_fbm, displace_lipschitz_safe, displace_perlin

## V.2 Ray-march

| Capability | Consumer Count | Presets |
|---|---|---|
| `ray_march_adaptive` | 1 | Arachne |
| `ao` | 1 | FerrofluidOcean |

### ZERO CONSUMERS (4 symbols)

hex_tile_uv, hex_tile_weights, normal_tetra, soft_shadow

## V.2 Volume

### ZERO CONSUMERS (25 symbols)

caust_animated, caust_audio, caust_fbm, caust_wave, cloud_density_cirrus, cloud_density_cumulus, cloud_density_stratus, cloud_lighting, cloud_march, hg_dual_lobe, hg_mie, hg_phase, hg_schlick, ls_intensity_audio, ls_radial_step_uv, ls_shadow_march, ls_sun_disk, phase_audio, transmittance, vol_accumulate, vol_composite, vol_density_cumulus, vol_density_height_fog, vol_inscatter, vol_sample_zero

## V.2 Texture

| Capability | Consumer Count | Presets |
|---|---|---|
| `voronoi_f1f2` | 1 | LumenMosaic |

### ZERO CONSUMERS (34 symbols)

flow_audio, flow_blend_weight, flow_curl_advect, flow_layered, flow_noise_velocity, flow_sample_offset, grunge_composite, grunge_crack, grunge_dirt_mask, grunge_dust, grunge_edge_wear, grunge_fingerprint, grunge_rust, grunge_scratches, proc_brick, proc_checker, proc_dots, proc_fish_scale, proc_grid, proc_hex_grid, proc_stripes, proc_weave, proc_wood, rd_animated, rd_colorize_tri, rd_pattern_approx, rd_spots, rd_step, rd_stripes, rd_worms, voronoi_3d_f1, voronoi_cells, voronoi_cracks, voronoi_leather

## V.3 Color

| Capability | Consumer Count | Presets |
|---|---|---|
| `hsv2rgb` | 7 | Arachne, FractalTree, Gossamer, Membrane, Nebula, Plasma, Waveform |
| `palette` | 3 | Arachne, LumenMosaic, VolumetricLithograph |

### ZERO CONSUMERS (21 symbols)

chromatic_aberration_directional, chromatic_aberration_radial, gradient_2, gradient_3, gradient_5, hsv_to_rgb, lab_to_rgb, lut_sample, oklab_to_rgb, palette_cool, palette_neon, palette_pastel, palette_warm, rgb_to_hsv, rgb_to_lab, rgb_to_oklab, tone_map_aces, tone_map_aces_full, tone_map_filmic_uncharted, tone_map_reinhard, tone_map_reinhard_extended

## V.3 Materials cookbook

| Capability | Consumer Count | Presets |
|---|---|---|
| `mat_frosted_glass` | 1 | Arachne |
| `mat_pattern_glass` | 1 | LumenMosaic |
| `mat_silk_thread` | 1 | Arachne |
| `mat_chitin` | 1 | Arachne |

### ZERO CONSUMERS (16 symbols)

mat_bark, mat_brushed_aluminum, mat_ceramic, mat_concrete, mat_copper, mat_ferrofluid, mat_gold, mat_granite, mat_ink, mat_leaf, mat_marble, mat_ocean, mat_polished_chrome, mat_sand_glints, mat_velvet, mat_wet_stone

## V.4 PBR

| Capability | Consumer Count | Presets |
|---|---|---|
| `sss_backlit` | 1 | Arachne |

### ZERO CONSUMERS (26 symbols)

brdf_ashikhmin_shirley, brdf_ggx, brdf_lambert, brdf_oren_nayar, combine_normals_udn, combine_normals_whiteout, cook_torrance, decode_normal_map, fiber_marschner_lite, fresnel_dielectric, fresnel_schlick, fresnel_schlick_roughness, g_smith, ggx_d, hue_rotate, parallax_occlusion, parallax_shadowed, tbn_from_derivatives, thinfilm_rgb, triplanar_blend_weights, triplanar_normal, triplanar_sample, trt_lobe, ts_to_ws, wrap_lighting, ws_to_ts

## Audio primitives - FeatureVector fields

| Capability | Consumer Count | Presets |
|---|---|---|
| `bass` | 11 | Arachne, FerrofluidOcean, FractalTree, GlassBrutalist, Gossamer, KineticSculpture, LumenMosaic, Membrane, Nebula, Plasma, VolumetricLithograph |
| `mid` | 10 | Arachne, FerrofluidOcean, FractalTree, GlassBrutalist, Gossamer, KineticSculpture, LumenMosaic, Membrane, Plasma, VolumetricLithograph |
| `beat_bass` | 9 | Arachne, FerrofluidOcean, FractalTree, GlassBrutalist, Gossamer, KineticSculpture, Membrane, SpectralCartograph, VolumetricLithograph |
| `treble` | 5 | FerrofluidOcean, FractalTree, LumenMosaic, Membrane, VolumetricLithograph |
| `valence` | 5 | Arachne, Gossamer, Membrane, SpectralCartograph, VolumetricLithograph |
| `arousal` | 5 | Arachne, Gossamer, LumenMosaic, Membrane, SpectralCartograph |
| `accumulated_audio_time` | 5 | Arachne, GlassBrutalist, Gossamer, KineticSculpture, LumenMosaic |
| `bass_att` | 4 | FractalTree, Membrane, Starburst, VolumetricLithograph |
| `bass_att_rel` | 4 | Arachne, Gossamer, SpectralCartograph, VolumetricLithograph |
| `mid_att_rel` | 4 | Arachne, Gossamer, SpectralCartograph, VolumetricLithograph |
| `beat_composite` | 3 | Arachne, Gossamer, VolumetricLithograph |
| `beat_phase01` | 3 | Arachne, Gossamer, SpectralCartograph |
| `spectral_centroid` | 3 | FractalTree, SpectralCartograph, Starburst |
| `mid_att` | 2 | FractalTree, VolumetricLithograph |
| `treb_att` | 2 | FractalTree, Membrane |
| `bass_dev` | 2 | KineticSculpture, SpectralCartograph |
| `mid_dev` | 2 | SpectralCartograph, VolumetricLithograph |
| `treb_dev` | 2 | Gossamer, SpectralCartograph |
| `beat_mid` | 2 | Gossamer, SpectralCartograph |
| `bar_phase01` | 2 | LumenMosaic, SpectralCartograph |
| `spectral_flux` | 2 | FerrofluidOcean, VolumetricLithograph |
| `treb_att_rel` | 1 | SpectralCartograph |
| `beat_treble` | 1 | SpectralCartograph |
| `beats_per_bar` | 1 | SpectralCartograph |

### ZERO CONSUMERS (4 symbols)

bass_rel, beats_until_next, mid_rel, treb_rel

## Audio primitives - StemFeatures fields

| Capability | Consumer Count | Presets |
|---|---|---|
| `vocals_energy` | 6 | FerrofluidOcean, GlassBrutalist, Gossamer, KineticSculpture, Starburst, VolumetricLithograph |
| `bass_energy` | 5 | FerrofluidOcean, GlassBrutalist, Gossamer, KineticSculpture, VolumetricLithograph |
| `drums_beat` | 4 | FerrofluidOcean, GlassBrutalist, KineticSculpture, VolumetricLithograph |
| `drums_energy` | 3 | FerrofluidOcean, Gossamer, VolumetricLithograph |
| `other_energy` | 2 | Gossamer, VolumetricLithograph |
| `vocals_energy_rel` | 1 | Gossamer |
| `drums_energy_dev` | 1 | Arachne |
| `bass_energy_rel` | 1 | Gossamer |
| `vocals_onset_rate` | 1 | VolumetricLithograph |
| `drums_onset_rate` | 1 | VolumetricLithograph |
| `bass_onset_rate` | 1 | VolumetricLithograph |
| `other_onset_rate` | 1 | VolumetricLithograph |
| `drums_attack_ratio` | 1 | VolumetricLithograph |
| `vocals_pitch_hz` | 1 | Arachne |
| `vocals_pitch_confidence` | 1 | Arachne |

### ZERO CONSUMERS (19 symbols)

bass_attack_ratio, bass_beat, bass_centroid, bass_energy_dev, bass_energy_slope, drums_centroid, drums_energy_rel, drums_energy_slope, other_attack_ratio, other_beat, other_centroid, other_energy_dev, other_energy_rel, other_energy_slope, vocals_attack_ratio, vocals_beat, vocals_centroid, vocals_energy_dev, vocals_energy_slope

## Buffer Slot Occupancy

| Buffer Slot | Preset Count | Presets |
|---|---|---|
| `buffer(0)` | 11 | Arachne, FerrofluidOcean, FractalTree, Gossamer, Membrane, Nebula, Plasma, SpectralCartograph, StagedSandbox, Starburst, Waveform |
| `buffer(1)` | 8 | FerrofluidOcean, Gossamer, Membrane, Nebula, Plasma, SpectralCartograph, Starburst, Waveform |
| `buffer(2)` | 8 | FerrofluidOcean, Gossamer, Membrane, Nebula, Plasma, SpectralCartograph, Starburst, Waveform |
| `buffer(3)` | 5 | Arachne, FerrofluidOcean, Gossamer, SpectralCartograph, Starburst |
| `buffer(5)` | 1 | SpectralCartograph |
| `buffer(6)` | 2 | Arachne, Gossamer |
| `buffer(7)` | 1 | Arachne |

## Texture Slot Occupancy

| Texture Slot | Preset Count | Presets |
|---|---|---|
| `texture(12)` | 1 | SpectralCartograph |
| `texture(13)` | 2 | Arachne, StagedSandbox |
