# Capability Gap Audit

**Status:** Awaiting Matt verdict confirmation. Doc-only artifact; no code or test changes land in this session.
**Authored:** 2026-05-12.
**Inventory evidence:** `docs/diagnostics/capability-audit-pre-2026-05-12.md` (raw symbol matrix, pass × preset table, test-fixture coupling).

---

## §1 — Why this audit exists

Phosphene has accumulated substantial preset-rendering capability across the V.1 → V.4 utility increments, MV-1/MV-2/MV-3 audio-primitive extensions, and per-preset bespoke infrastructure (LM's slot-8 `LumenPatternState`, SpectralCartograph's slot-5 `SpectralHistoryBuffer`, Arachne's slot-6/7 web + spider buffers). Some of this surface is exercised heavily; some has zero production consumers; some was built for presets that were later retired (Drift Motes, D-102) or restructured.

There is no single artifact mapping the capability surface to its consumers, identifying orphaned infrastructure, or articulating which capabilities the unscheduled backlog (Phase G-uplift, V.12, Phase AV, Phase CC, Phase MD) implicitly requires.

This audit produces:

1. **§3** — Inventory of capabilities in active use (RETAIN baseline).
2. **§4** — Verdicts on underused capability (RESERVE / OPPORTUNISTIC / RETIRE).
3. **§5** — Backlog-implied capability needs per planned preset.
4. **§6** — Proposed new capabilities (PROPOSED / CONSIDERED / DEFERRED).
5. **§7** — Verdict summary table.

The output is a Matt-approves-the-verdicts queue, not a code-landing artifact. Confirmed verdicts feed into `docs/ENGINEERING_PLAN.md` as scoped follow-up sessions (RETIRE → cleanup increments; PROPOSED → new build increments; RESERVE → forward-pointer in the consuming preset's design doc).

## §2 — Methodology

**Data collection** (Step 0 of the audit prompt). Symbol matrix built by `grep -l <symbol> PhospheneEngine/Sources/Presets/Shaders/*.metal` excluding `Utilities/` and `ShaderUtilities.metal` — counts only production preset consumers. Pass adoption from per-preset JSON sidecars. Buffer/texture slot occupancy from `[[buffer(N)]]` / `[[texture(N)]]` declarations. Design-doc capability requirements extracted from AV / CC / Arachne V.8 / V.12 / Phase G-uplift / Phase MD strategy.

**Verdict definitions:**
- **RETAIN** — ≥1 production consumer AND no obvious removal upside. Default for any capability with ≥2 consumers; also the default for single-consumer capabilities that are load-bearing for that consumer (e.g. `voronoi_f1f2` for Lumen Mosaic).
- **RESERVE** — 0 or 1 production consumer, but a planned preset in the design backlog references it. Requires naming the planned consumer.
- **OPPORTUNISTIC** — 0 production consumers, no current planned consumer, but the option value is real (capability fits a plausible future aesthetic register or is cheap to maintain). Keep but don't invest.
- **RETIRE** — 0 production consumers, no planned consumer, and the maintenance cost (test fixtures, preamble compile time, LOC drift surface) exceeds option value. Proposes deletion in a follow-up cleanup increment.
- **PROPOSED** — new capability not in the current tree, with a named first adopter from the backlog or near-term roadmap.
- **CONSIDERED** — design surface evaluated; not building now. Records the decision rationale so the option doesn't have to be re-evaluated cold next time.
- **DEFERRED** — build after a specific gating condition (e.g. concrete preset demand surfaces, or a prior phase completes).

**Architectural caveats** (load-bearing for verdict accuracy):

- **V.4 PBR is engine-internal for ray-march presets.** Cook-Torrance + Fresnel + IBL math runs in `Renderer/Shaders/RayMarch.metal` (private `rm_fresnel` at `:123, :137, :386`), not in preset code. Presets define `sceneSDF` + `sceneMaterial` (out-params: albedo / roughness / metallic / matID) and the engine's `raymarch_lighting_fragment` does the actual shading. The V.4 PBR utility tree IS loaded into the preset preamble and is theoretically callable, but its intended consumer is direct-fragment presets needing lighting math without the ray-march pipeline OR custom shading inside `sceneMaterial`. "Zero preset consumers" on `cook_torrance` does NOT mean PBR is unused — it means the V.4 utility-tree adapter has no caller.
- **mv_warp has one consumer.** Gossamer (`passes: ["mv_warp"]`) defines `mvWarpPerFrame` + `mvWarpPerVertex`. The audit prompt's "zero consumers since the April reverts" framing is outdated post-Gossamer.
- **Materials cookbook is rubric-coupled.** `FidelityRubric.swift:61-79` hardcodes all 19 material symbols for the M3 (≥3 materials) automated check. RETIRE verdicts on any `mat_*` recipe require coupled rubric edits.
- **Doc drift exists.** CLAUDE.md's "MV-3" section claims VolumetricLithograph uses `vocals_pitch_hz` / `vl_pitchHueShift()`. Grep confirms VL does not actually consume these — Arachne is the sole consumer. Treat the symbol matrix as authoritative; flag CLAUDE.md drift as a follow-up edit.

## §3 — Inventory: capabilities in active use (RETAIN baseline)

Capabilities with ≥2 production consumers are RETAIN by default; not enumerated in §4. Top-level summary (full per-symbol counts in `docs/diagnostics/capability-audit-pre-2026-05-12.md`):

### Render passes (RETAIN where indicated)

| Pass | Consumers | Verdict |
|---|---|---|
| `direct` | 4 (Nebula, Plasma, SpectralCartograph, Waveform) | RETAIN |
| `post_process` | 5 (FerrofluidOcean + 4 ray-march presets) | RETAIN |
| `ray_march` | 4 (GlassBrutalist, KineticSculpture, LumenMosaic, VolumetricLithograph) | RETAIN |
| `feedback` | 2 (Membrane, Starburst) | RETAIN |
| `staged` | 2 (Arachne, StagedSandbox) | RETAIN |
| `mv_warp` | 1 (Gossamer) | RESERVE — see §4 |
| `mesh_shader` | 1 (FractalTree) | RESERVE — see §4 |
| `particles` | 1 (Starburst) | RESERVE — see §4 |
| `ssgi` | 1 (GlassBrutalist) | RESERVE — see §4 (CC adopts) |

### Audio primitives — FeatureVector (RETAIN where ≥2 consumers)

`bass` (11), `mid` (10), `beat_bass` (9), `treble` (5), `valence` (5), `arousal` (5), `accumulated_audio_time` (5), `bass_att` (4), `bass_att_rel` (4), `mid_att_rel` (4), `beat_composite` (3), `beat_phase01` (3), `spectral_centroid` (3), `mid_att` (2), `treb_att` (2), `bass_dev` (2), `mid_dev` (2), `treb_dev` (2), `beat_mid` (2), `bar_phase01` (2), `spectral_flux` (2). All RETAIN.

Single-consumer FV fields (`treb_att_rel`, `beat_treble`, `beats_per_bar` — all SpectralCartograph-only) — see §4.

### Audio primitives — StemFeatures (RETAIN where ≥2)

`vocals_energy` (6), `bass_energy` (5), `drums_beat` (4), `drums_energy` (3), `other_energy` (2). All RETAIN.

### Color (RETAIN)

`hsv2rgb` (7), `palette` (3). All RETAIN.

### V.1 Noise (RETAIN)

`fbm8` (2 — Arachne, LumenMosaic). RETAIN.

### Materials (RETAIN single-consumer load-bearing)

`mat_frosted_glass` (1, Arachne), `mat_pattern_glass` (1, LumenMosaic), `mat_silk_thread` (1, Arachne), `mat_chitin` (1, Arachne). All RETAIN — load-bearing for Arachne / LM identity.

### GPU buffer slots in active use

| Slot | Contract | Consumers | Verdict |
|---|---|---|---|
| 0 | FeatureVector (universal) | 11 (all direct/feedback/mv_warp/staged presets; ray-march presets bind via engine path) | RETAIN |
| 1 | FFT magnitudes | 8 | RETAIN |
| 2 | Waveform samples | 8 | RETAIN |
| 3 | StemFeatures | 5 + ray-march presets via engine path | RETAIN |
| 4 | SceneUniforms | ray-march presets via engine path | RETAIN |
| 5 | SpectralHistoryBuffer | 1 (SpectralCartograph) + AV planned | RESERVE — see §4 |
| 6 | Per-preset state #1 | 2 (Arachne web pool, Gossamer wave pool) | RETAIN |
| 7 | Per-preset state #2 | 1 (Arachne spider) | RESERVE — see §4 |
| 8 | LumenPatternState | 1 (LumenMosaic) | RESERVE — see §4 |
| 13 | WORLD texture (staged) | 2 (Arachne, StagedSandbox composite samples) | RETAIN |

## §4 — Underused capability verdicts

Verdicts are listed by category. RETIRE verdicts identify deletion targets but do NOT execute deletion — that's a follow-up cleanup increment after Matt's confirmation.

### §4.1 Render passes

#### `mv_warp` pass
**Current state:** 1 production consumer (Gossamer).
**Verdict:** RESERVE.
**Rationale:** Aurora Veil (Phase AV) specs `mv_warp` as its only render pass; Crystalline Cavern (Phase CC) specs `ray_march` + `mv_warp` shimmer; Phase MD's MD.5 / MD.6 / MD.7 ports adopt `mv_warp` (D-027/D-029 — required for Milkdrop-faithful per-pixel warp). The pass has the most planned consumers of any underused capability. Three near-term adopters; gap is execution timing, not value.
**Forward-pointer:** AV.1, CC.4, MD.5+ (per `docs/MILKDROP_STRATEGY.md`).

#### `mesh_shader` pass
**Current state:** 1 production consumer (FractalTree).
**Verdict:** OPPORTUNISTIC.
**Rationale:** FractalTree is the sole consumer; no Phase G-uplift / AV / CC / V.12 / Phase MD design references the path. The pass has architectural value (GPU-side primitive emission, mesh-shader fallback for M1/M2 covered by `MeshGenerator`), but no concrete future demand. Cost to maintain is low — the engine-side dispatch + fallback already exists and is exercised by FractalTree's tests. If FractalTree gets retired in a future Phase G-uplift session per a Failed-Approach-58 evaluation, the pass becomes RETIRE.

#### `particles` pass
**Current state:** 1 production consumer (Starburst — Murmuration `ProceduralGeometry`).
**Verdict:** OPPORTUNISTIC.
**Rationale:** Starburst is the sole consumer post-Drift Motes retirement. D-097 documents the "siblings, not subclasses" surface — future particle presets ship their own `ParticleGeometry` conformer + their own `Particles*.metal` engine-library shader, not parameterizations of `ProceduralGeometry`. No backlog particle preset is currently scheduled. Maintenance cost is moderate (compute + render pipeline, frame-budget gating); option value is real (particles are a distinct visual register with proven musical coupling on Starburst). Re-classify to RESERVE the moment a backlog particle preset is named.

#### `ssgi` pass
**Current state:** 1 production consumer (GlassBrutalist).
**Verdict:** RESERVE.
**Rationale:** Crystalline Cavern (Phase CC) explicitly specs `ssgi` per `CRYSTALLINE_CAVERN_DESIGN.md §4`. Phase G-uplift on GlassBrutalist preserves the consumer. Two adopters (existing + planned).

#### `staged` pass
**Current state:** 2 production consumers (Arachne, StagedSandbox).
**Verdict:** RETAIN.
**Rationale:** Already RETAIN-eligible by ≥2 consumers, but called out because the contract is young (V.7.7A 2026-05-05). Future multi-stage presets (Arachne3D / V.8.x deferred per Matt 2026-05-08) will adopt. No verdict change.

### §4.2 V.1 Noise utility tree

#### `fbm4`
**Current state:** 1 production consumer (Arachne).
**Verdict:** RESERVE.
**Rationale:** AV.1 design specs `fbm4` as a noise driver. Arachne + AV = two adopters once AV ships.

#### `warped_fbm`, `curl_noise`, `blue_noise_sample`
**Current state:** 0 production consumers each.
**Verdict:** RESERVE.
**Rationale:** AV.1 explicitly names all three (`AURORA_VEIL_DESIGN.md` §4 architecture: `warped_fbm` for fluid noise field, `curl_noise` for divergence-free vector field, `blue_noise_sample` for starfield). AV is the named adopter; verdict reverts to OPPORTUNISTIC if AV gets re-scoped to use only `fbm4`.

#### `hash_f01_2`, `hash_u32`, `hash_f01`
**Current state:** `hash_f01_2` 1 consumer (Arachne); `hash_u32` and `hash_f01` 0 consumers.
**Verdict:** RETAIN (hash_f01_2), OPPORTUNISTIC (hash_u32, hash_f01).
**Rationale:** Hash primitives are foundational (used implicitly by `palette`, fbm-class noise, etc.). Even with zero direct preset consumers, the symbols underpin other utilities. Maintenance cost ~zero (single-line functions). Don't retire.

#### `fbm12`, `fbm_vec3`, `perlin2d`, `perlin3d`, `perlin4d`, `simplex3d`, `simplex4d`, `ridged_mf`, `worley2d`, `worley3d`, `worley_fbm`, `warped_fbm_vec`, `ign`, `ign_temporal`
**Current state:** 0 production consumers.
**Verdict:** OPPORTUNISTIC for `ridged_mf`, `worley_fbm`, `simplex3d` (all named by CC design and likely Phase G-uplift candidates); RETIRE-CANDIDATE for `fbm12`, `fbm_vec3`, `perlin2d/3d/4d` (raw Perlin primitives — fbm-class wraps these, no preset is going to call raw Perlin), `simplex4d`, `worley2d`, `worley3d`, `warped_fbm_vec`, `ign`, `ign_temporal`.
**Soft posture:** None of the V.1 noise primitives are individually expensive to maintain — they're small functions in `Noise/*.metal` files. The deletion upside is preamble compile time + LOC clarity. Recommend marking the named-by-CC items as RESERVE; downgrade the raw-Perlin / Worley / IGN items to OPPORTUNISTIC for now (cheap to retain, real albeit small option value). Defer aggressive RETIRE on V.1 noise to a future cleanup pass once Phase G-uplift surfaces what's actually needed.

### §4.3 V.2 Geometry SDF tree

#### `sd_sphere`, `sd_box`, `sd_capsule`, `sd_segment_2d`
**Current state:** `sd_sphere` 1 (Arachne), `sd_box` 1 (LumenMosaic), `sd_capsule` 1 (Arachne), `sd_segment_2d` 0 (CLAUDE.md says Arachne uses it for chord segments per Failed Approach #34 lock — verify — likely actually used post-V.7.7C.3 polygon flush).
**Verdict:** RETAIN — load-bearing primitives for the existing SDF presets.

#### `sd_gyroid`, `sd_schwarz_p`, `sd_schwarz_d`, `sd_helix`, `sd_mandelbulb_iterate`
**Current state:** 0 consumers.
**Verdict:** OPPORTUNISTIC.
**Rationale:** Exotic SDF primitives (TPMS surfaces, fractal iteration) are aesthetically distinct and could be the seed of a future ambient-class preset. No current adopter named. Cost to maintain: low (each is ~10-30 LOC). Hold as option value.

#### `sd_torus`, `sd_cylinder`, `sd_round_box`, `sd_ellipsoid`, `sd_plane`, `sd_cone`, `sd_hexagon`, `sd_octahedron`, `sd_pyramid`
**Current state:** 0 consumers.
**Verdict:** OPPORTUNISTIC.
**Rationale:** Bread-and-butter SDF primitives. Any future SDF preset will likely use ≥1 of these. No current adopter, but the deletion case is weak — they're foundational shapes whose presence in the cookbook is part of "Phosphene supports SDF authoring."

#### SDF operations: `op_smooth_union`, `op_smooth_subtract`, `op_blend` — RETAIN (Arachne)
#### SDF operations: `op_chamfer`, `op_intersect`, `op_smooth_intersect`, `op_subtract`, `op_union`
**Verdict:** OPPORTUNISTIC. Same posture as primitive shapes — foundational, tiny, future SDF presets need them.

#### SDF modifiers (all 9: `mod_*`)
**Current state:** 0 consumers across `mod_repeat / mirror / twist / bend / scale / round / onion / extrude / revolve`.
**Verdict:** OPPORTUNISTIC for `mod_repeat` / `mod_mirror` / `mod_twist` (the three most commonly-used SDF modifiers in ambient-class presets); RETIRE-CANDIDATE for `mod_extrude` / `mod_revolve` (sweep operations — niche, no plausible future adopter).
**Soft posture:** Hold the cluster as OPPORTUNISTIC pending Phase G-uplift / future SDF preset surveys. The deletion case is weak per-symbol; the cluster's existence is what makes V.2 a "complete" SDF cookbook.

#### Displacement utilities (all 5: `displace_*`)
**Current state:** 0 consumers.
**Verdict:** OPPORTUNISTIC for `displace_lipschitz_safe` / `displace_fbm` / `displace_beat_anticipation` / `displace_energy_breath`; RETIRE-CANDIDATE for `displace_perlin` (raw Perlin variant — `displace_fbm` is the higher-quality form preset authors will reach for).
**Rationale:** Audio-driven displacement is exactly the kind of capability future ambient/organic presets will need. Zero consumers today; high-plausibility adopters tomorrow.

#### Ray-march utilities: `ray_march_adaptive` (1, Arachne), `ao` (1, FerrofluidOcean), `normal_tetra`, `soft_shadow`, `hex_tile_uv`, `hex_tile_weights`
**Current state:** First two: 1 each (RESERVE — see below); rest: 0.
**Verdict:** RESERVE for `ray_march_adaptive` (any future presets that ray-march outside the engine's main pipeline — Arachne's spider patch is the precedent); RESERVE for `ao` (Phase G-uplift may extend); OPPORTUNISTIC for `hex_tile_uv` / `hex_tile_weights` (Mikkelsen hex-tiling is a known good technique for tile-free texturing — plausible future adopter); OPPORTUNISTIC for `normal_tetra` and `soft_shadow` (engine has its own `RayMarch.metal` equivalents, but a preset doing in-fragment ray-marching needs these).

### §4.4 V.2 Volume utility tree

#### Caustics (`caust_wave`, `caust_fbm`, `caust_animated`, `caust_audio`)
**Current state:** 0 consumers.
**Verdict:** RESERVE.
**Rationale:** Crystalline Cavern (CC.3) is the named adopter. Per `CRYSTALLINE_CAVERN_DESIGN.md` §5, CC.3 has a documented `fbm8` fallback if the caustic utility output is unworkable in production. CC.3 is the validation gate; if CC.3 falls back, the verdict reopens (likely toward RETIRE or RESERVE-with-known-limitations).

#### Henyey-Greenstein (`hg_phase`, `hg_schlick`, `hg_dual_lobe`, `hg_mie`, `transmittance`, `phase_audio`)
**Current state:** 0 consumers.
**Verdict:** RESERVE for `hg_phase` (CC adopts per design); OPPORTUNISTIC for the other phase-function variants (they're additive — alternative scattering models).

#### Participating media (`vol_sample_zero`, `vol_density_height_fog`, `vol_density_cumulus`, `vol_accumulate`, `vol_composite`, `vol_inscatter`)
**Current state:** 0 consumers.
**Verdict:** RESERVE for `vol_density_height_fog` and `vol_sample_zero` (CC adopts); OPPORTUNISTIC for the rest (cloud-class presets are a plausible future register; current backlog doesn't name them).

#### Clouds (`cloud_density_cumulus`, `cloud_density_stratus`, `cloud_density_cirrus`, `cloud_march`, `cloud_lighting`)
**Current state:** 0 consumers.
**Verdict:** OPPORTUNISTIC.
**Rationale:** No backlog preset uses cloud rendering. The utility set is comprehensive and demo-quality, but Phase MD's hybrid tier (which could plausibly adopt) hasn't named cloud-coupled candidates. Hold as option value — cost to maintain is moderate (5 files, ~600 LOC) but the utility set is internally consistent and removal would erase a coherent feature.

#### Light shafts (`ls_radial_step_uv`, `ls_shadow_march`, `ls_sun_disk`, `ls_intensity_audio`)
**Current state:** 0 consumers.
**Verdict:** RESERVE.
**Rationale:** V.12 (Glass Brutalist v2) ENGINEERING_PLAN entry names "volumetric light shafts" as a required capability. CC also implicitly uses (`vol_density_height_fog` + light shaft for caustic god-rays). Two near-term adopters.

### §4.5 V.2 Texture utility tree

#### `voronoi_f1f2`
**Current state:** 1 production consumer (LumenMosaic — the entire LM identity rests on this).
**Verdict:** RETAIN (load-bearing for sole consumer).

#### `voronoi_3d_f1`, `voronoi_cracks`, `voronoi_leather`, `voronoi_cells`
**Current state:** 0 consumers each.
**Verdict:** OPPORTUNISTIC. Voronoi-class textures are aesthetically distinct (cellular, organic, biological); plausible adopters for Phase G-uplift surveys or new-preset designs.

#### Reaction-diffusion (`rd_pattern_approx`, `rd_animated`, `rd_spots`, `rd_stripes`, `rd_worms`, `rd_step`, `rd_colorize_tri`)
**Current state:** 0 consumers across all 7.
**Verdict:** RETIRE-CANDIDATE.
**Rationale:** Speculative authoring at V.2 time; no production preset has adopted; no backlog preset names RD. The aesthetic register (Turing patterns, Gray-Scott, biological textures) is distinctive but Phosphene's catalog hasn't pulled toward it. **Cleanup-increment scope** if Matt confirms RETIRE: delete `Texture/ReactionDiffusion.metal` (~150 LOC) + `ReactionDiffusionTests.swift`. Reversible from git history.

#### Flow maps (`flow_sample_offset`, `flow_blend_weight`, `flow_curl_advect`, `flow_noise_velocity`, `flow_audio`, `flow_layered`)
**Current state:** 0 consumers across all 6.
**Verdict:** RETIRE-CANDIDATE.
**Rationale:** Same posture as RD. No adopter named. **Cleanup-increment scope:** delete `Texture/FlowMaps.metal` + `FlowMapsTests.swift`. Reversible.

#### Procedural patterns (`proc_stripes`, `proc_checker`, `proc_grid`, `proc_hex_grid`, `proc_dots`, `proc_weave`, `proc_brick`, `proc_fish_scale`, `proc_wood`)
**Current state:** 0 consumers across all 9.
**Verdict:** **Pending Phase MD strategy decision.** Decision E in `docs/MILKDROP_STRATEGY.md` covers procedural-pattern adoption in evolved-tier ports. If MD picks E.1 / E.2 (preserve procedural patterns as core capability), verdict = RESERVE. If MD picks E-equivalent that excludes procedural patterns, verdict = RETIRE-CANDIDATE. Hold pending.

#### Grunge utilities (`grunge_scratches`, `grunge_rust`, `grunge_edge_wear`, `grunge_fingerprint`, `grunge_dust`, `grunge_dirt_mask`, `grunge_crack`, `grunge_composite`)
**Current state:** 0 consumers, but `mat_concrete` is documented to call `grunge_dirt_mask` indirectly (the cookbook recipe). Since `mat_concrete` itself has 0 consumers, the indirect path is dead.
**Verdict:** OPPORTUNISTIC for `grunge_dirt_mask` / `grunge_dust` (V.12 surface-aging pass for Glass Brutalist v2 plausibly adopts); RETIRE-CANDIDATE for `grunge_scratches` / `grunge_rust` / `grunge_edge_wear` / `grunge_fingerprint` / `grunge_crack` / `grunge_composite` (no plausible adopter named).
**Soft posture:** Cluster decision — either keep all 8 (the cookbook is internally consistent) or RETIRE the cluster en bloc. Recommend OPPORTUNISTIC for the cluster pending V.12 design.

### §4.6 V.3 Color tree

#### `palette_warm`, `palette_cool`, `palette_neon`, `palette_pastel`
**Current state:** 0 consumers (the base `palette` function has 3).
**Verdict:** RESERVE for `palette_cool` (AV.1 design specs it); OPPORTUNISTIC for `palette_warm` / `palette_neon` / `palette_pastel`.

#### `gradient_2`, `gradient_3`, `gradient_5`, `lut_sample`
**Current state:** 0 consumers.
**Verdict:** OPPORTUNISTIC. Generic interpolation primitives; small cost; future palette-driven presets may adopt.

#### `rgb_to_hsv`, `hsv_to_rgb`
**Current state:** 0 consumers (`hsv2rgb` is the consumed name; the snake_case variant is a separate symbol).
**Verdict:** RETIRE-CANDIDATE.
**Rationale:** Naming inconsistency between `hsv2rgb` (used) and `hsv_to_rgb` (unused snake_case alias). Either consolidate to one name or delete the unused alias. Same for `rgb_to_hsv`. **Cleanup scope:** ~6 LOC deletion + verify no doc references the snake_case form.

#### `rgb_to_lab`, `lab_to_rgb`, `rgb_to_oklab`, `oklab_to_rgb`
**Current state:** 0 consumers.
**Verdict:** OPPORTUNISTIC.
**Rationale:** Oklab is the perceptually-correct palette interpolation space. No current adopter, but multiple plausible (Phase MD evolved tier could swap palette interpolation into Oklab; Phase G-uplift could adopt for color polish). Cost to maintain low (~30 LOC each).

#### `chromatic_aberration_radial`, `chromatic_aberration_directional`
**Current state:** 0 consumers.
**Verdict:** OPPORTUNISTIC.
**Rationale:** V.6 cert rubric Preferred item P4 explicitly references chromatic aberration. Multiple presets could adopt for the +1/4 Preferred slot. No named first adopter, but the rubric incentivizes it.

#### `tone_map_aces` (and `aces_full`), `tone_map_reinhard` (and `extended`), `tone_map_filmic_uncharted`
**Current state:** 0 consumers.
**Verdict:** OPPORTUNISTIC.
**Rationale:** The engine's `PostProcessChain` runs ACES tone-mapping in the composite pipeline; preset code doesn't typically need to tone-map output. The utility variants are alternates. Hold as option value (small cost) but downgrade to RETIRE-CANDIDATE if future cleanup wants to consolidate to one canonical tone-mapping path.

### §4.7 V.3 Materials cookbook (high verdict density)

The 16 unused cookbook materials are a natural cluster. Verdict per material reflects backlog alignment:

| Material | Consumers | Verdict | Backlog adopter |
|---|---|---|---|
| `mat_polished_chrome` | 0 | RESERVE | V.12 (Kinetic Sculpture v2 anisotropic streak variant) |
| `mat_brushed_aluminum` | 0 | RESERVE | V.12 (Kinetic Sculpture v2) |
| `mat_gold` | 0 | OPPORTUNISTIC | none named; metal alternate |
| `mat_copper` | 0 | OPPORTUNISTIC | none named; metal alternate |
| `mat_ferrofluid` | 0 | RESERVE | FerrofluidOcean (Phase G-uplift) — preset has the name but doesn't yet call the recipe |
| `mat_ceramic` | 0 | OPPORTUNISTIC | none named; surface alternate |
| `mat_wet_stone` | 0 | RESERVE | CC (Crystalline Cavern §5 names it explicitly) |
| `mat_bark` | 0 | OPPORTUNISTIC | Arachne WORLD pre-V.7.7C.5 used inline forest material; future organic-class adopter possible |
| `mat_leaf` | 0 | OPPORTUNISTIC | as `mat_bark` |
| `mat_ocean` | 0 | OPPORTUNISTIC | FerrofluidOcean potential; not currently called |
| `mat_ink` | 0 | OPPORTUNISTIC | distinctive 2D register |
| `mat_marble` | 0 | OPPORTUNISTIC | none named |
| `mat_granite` | 0 | OPPORTUNISTIC | none named |
| `mat_velvet` | 0 | OPPORTUNISTIC | distinctive register (Oren-Nayar fuzz); no adopter |
| `mat_sand_glints` | 0 | OPPORTUNISTIC | none named |
| `mat_concrete` | 0 | RESERVE | V.12 (Glass Brutalist v2 — needs board-form variant; either parametric extension or `mat_concrete_board_form` PROPOSED — see §6) |

**Material RETIRE-CANDIDATES:** None individually. The cookbook is internally consistent and the M3 (≥3 materials) rubric check makes the cookbook's existence load-bearing for any future preset's certification. Material maintenance cost is moderate (~40 LOC per recipe + rubric symbol-list coupling at `FidelityRubric.swift:61-79`).

**Recommendation:** Hold the cookbook intact through Phase MD strategy decisions. Re-evaluate after Phase G-uplift surfaces actual adoption patterns (likely 6-12 months from now). The OPPORTUNISTIC verdicts above are weak holds; they shift to RESERVE the moment any preset names the material in its design.

### §4.8 V.4 PBR utility tree

#### `cook_torrance`, `fresnel_schlick`, `fresnel_schlick_roughness`, `fresnel_dielectric`, `ggx_d`, `g_smith`, `brdf_ggx`, `brdf_lambert`, `brdf_oren_nayar`, `brdf_ashikhmin_shirley`
**Current state:** 0 preset consumers; engine RayMarch.metal has private Cook-Torrance + Fresnel implementations.
**Verdict:** OPPORTUNISTIC.
**Rationale:** Architectural — these utilities are loaded into the preamble and theoretically callable from preset code (direct-fragment presets needing lighting math, or `sceneMaterial` doing custom shading). Today no preset takes that path; the engine's lighting fragment handles all PBR for ray-march. The utility tree is the option value for direct-fragment lighting (e.g. a future FerrofluidOcean rewrite that wants per-pixel reflective shading). Hold cluster intact; RETIRE only en bloc if a future architectural decision moves PBR off the utility surface entirely.

#### `decode_normal_map`, `ts_to_ws`, `ws_to_ts`, `tbn_from_derivatives`, `combine_normals_udn`, `combine_normals_whiteout`
**Current state:** 0 consumers.
**Verdict:** OPPORTUNISTIC. Normal-mapping infrastructure for any future preset adopting normal maps. Cost low (~15-25 LOC each).

#### `triplanar_blend_weights`, `triplanar_sample`, `triplanar_normal`
**Current state:** 0 consumers.
**Verdict:** RESERVE (V.6 rubric Expected E1 — triplanar texturing). CC.4 design implies adoption (`triplanar_detail_normal` named). Multiple presets could adopt for the rubric.

#### `parallax_occlusion`, `parallax_shadowed`
**Current state:** 0 consumers.
**Verdict:** RESERVE.
**Rationale:** V.12 (Glass Brutalist v2) names POM on walls. V.6 rubric Preferred P2.

#### `sss_backlit`
**Current state:** 1 consumer (Arachne).
**Verdict:** RETAIN (load-bearing for Arachne organic surfaces).

#### `wrap_lighting`, `fiber_marschner_lite`, `trt_lobe`, `thinfilm_rgb`, `hue_rotate`
**Current state:** 0 consumers (Arachne inlines its own thin-film at biological strength per §6.2 lock — does NOT call `thinfilm_rgb`).
**Verdict:** OPPORTUNISTIC for `thinfilm_rgb` (Arachne could re-adopt if §6.2 inlining ever loosens; future iridescent-surface preset plausible); OPPORTUNISTIC for `wrap_lighting` (cheap shading model, plausible adoption); RETIRE-CANDIDATE for `fiber_marschner_lite` and `trt_lobe` (these were demoted in Arachne V.7.9 per CLAUDE.md "Marschner BRDF removed §5.10" — no adopter, no plausible re-adoption); OPPORTUNISTIC for `hue_rotate` (small utility, plausible adoption).

### §4.9 Audio primitives — single-consumer fields

#### MV-3a per-stem rich metadata (`vocals_onset_rate`, `drums_onset_rate`, `bass_onset_rate`, `other_onset_rate`, `drums_attack_ratio`)
**Current state:** 1 consumer each (VolumetricLithograph).
**Verdict:** RESERVE.
**Rationale:** Phase MD strategy (D-108) makes per-stem affinity opt-in for evolved-tier presets — likely adopters for these primitives. CC.4 also names `vocalsPitchHz` × `vocalsPitchConfidence` gating which implicitly uses the metadata surface. The MV-3 work is the foundation for the next generation of stem-coupled presets.

#### `vocals_pitch_hz`, `vocals_pitch_confidence`
**Current state:** 1 consumer each (Arachne — verified by grep; CLAUDE.md's claim about VolumetricLithograph using these is doc drift).
**Verdict:** RESERVE.
**Rationale:** AV.2 specs vocals-pitch hue stratification; CC.4 specs caustic-refraction-angle pitch coupling. Two named adopters.

#### MV-3a metadata not yet adopted (`*_centroid`, `*_attack_ratio` except drums, `*_energy_slope`, `*_energy_dev` except drums)
**Current state:** 0 consumers each (~19 fields).
**Verdict:** OPPORTUNISTIC.
**Rationale:** The MV-3a infrastructure shipped per D-028 with the explicit goal of making these primitives available; adopters arrive over time as preset designs surface needs. Maintenance cost is in the analyzer pipeline, not per-field — once the analyzer computes the values, adding a preset consumer is one line. Hold cluster intact.

#### `bass_rel`, `mid_rel`, `treb_rel`, `beats_until_next`
**Current state:** 0 consumers each.
**Verdict:** OPPORTUNISTIC for `bass_rel` / `mid_rel` / `treb_rel` (the symmetric `*Dev` versions ARE used; the `*Rel` (signed) versions are an alternative interface most authors won't reach for, but the cost is zero — they're already on the FeatureVector struct and computed in `MIRPipeline.buildFeatureVector`). RESERVE for `beats_until_next` (BeatPredictor field — Phase MD's evolved tier could plausibly adopt for anticipatory animation; D-028 documents the field's purpose).

#### `treb_att_rel`, `beat_treble`, `beats_per_bar` (SpectralCartograph-only)
**Current state:** 1 consumer (SpectralCartograph diagnostic).
**Verdict:** RETAIN (load-bearing for diagnostic identity).

### §4.10 GPU buffer slots

#### Slot 5 — SpectralHistoryBuffer
**Current state:** 1 consumer (SpectralCartograph) + AV planned.
**Verdict:** RESERVE.
**Rationale:** AV.2 reads `vocalsPitchNorm` from `SpectralHistoryBuffer[1920..2399]`. SpectralCartograph + AV = two adopters. The contract (16 KB UMA buffer at fragment slot 5 in direct-pass encoders) is preserved; ray-march presets continue to skip.

#### Slot 7 — Per-preset state #2
**Current state:** 1 consumer (Arachne `ArachneSpiderGPU` — 80 bytes).
**Verdict:** RESERVE.
**Rationale:** Slot 7 is the second per-preset namespace; Arachne's spider state is its sole resident. Future second-state-buffer needs (e.g. Stalker if it returns, or a future trilogy preset) reuse this slot. Contract is "per-preset uniform binding contract, same as slot 6" — well-documented in CLAUDE.md GPU Contract.

#### Slot 8 — LumenPatternState
**Current state:** 1 consumer (LumenMosaic — 376 bytes after LM.3.2).
**Verdict:** RESERVE — but with the caveat that "future LM-pattern consumers" is unlikely; this slot is effectively LM-namespaced for the indefinite future.
**Recommendation:** Document the slot's contract as "LumenMosaic-specific until a deliberate re-allocation decision lands." Today's `lumenPlaceholderBuffer` (zero-filled 376-byte buffer bound for non-LM ray-march presets per LM.2 architecture, D-LM-buffer-slot-8) is the engine's compatibility shim. The slot's RESERVE verdict mostly amounts to "don't hand this to a different preset without filing a D-### entry."

## §5 — Backlog-implied capability needs

For each unscheduled-preset design or in-flight phase, what does it require? This section maps the §4 verdicts to specific consuming designs.

### Phase AV — Aurora Veil

**Design state:** Complete (`docs/presets/AURORA_VEIL_DESIGN.md`); references curated; concept-viability gate passed.
**Capabilities required:**
- `mv_warp` pass — RESERVE adopter ✓
- `warped_fbm`, `curl_noise`, `fbm4`, `blue_noise_sample` — RESERVE adopters (V.1 noise) ✓
- `palette_cool` — RESERVE adopter (V.3 color) ✓
- `hash_f01_2` — RETAIN (already used by Arachne)
- SpectralHistoryBuffer (slot 5, `vocalsPitchNorm` ring) — RESERVE adopter ✓
- Audio: `f.bass_att_rel`, `f.mid_att_rel`, `stems.drums_energy_dev`, `f.valence`, `f.beat_phase01` — all RETAIN
**New infrastructure required:** None. AV is the lightest-weight new preset on the bench; entire spec uses existing capability.
**Audit verdict implications:** AV "claims" mv_warp + 4 V.1 noise utilities + `palette_cool` + slot 5 SpectralHistory consumer count from the RESERVE column.

### Phase CC — Crystalline Cavern

**Design state:** Complete (`docs/presets/CRYSTALLINE_CAVERN_DESIGN.md`); references **not yet curated** (CC.0 is the prerequisite); concept-viability gate passed.
**Capabilities required:**
- Passes: `ray_march`, `post_process`, `ssgi`, `mv_warp` — all RETAIN/RESERVE ✓
- V.1 noise: `worley_fbm`, `fbm8`, `ridged_mf` — first two have plausible OPPORTUNISTIC adopters; `ridged_mf` becomes RESERVE
- V.2 SDF: custom `sd_cavern_walls`, `sd_crystal_cluster`, `sd_floor_crystals`, `sd_hanging_tips` (preset-internal, not utility) + likely `sd_box`, `op_smooth_union`, `mod_repeat` from utility tree
- V.2 volume: `vol_density_height_fog`, `hg_phase`, `vol_sample`, `ls_radial_step_uv`, caustic utility — RESERVE adopters ✓
- V.3 materials: `mat_pattern_glass`, `mat_polished_chrome`, `mat_wet_stone`, `mat_frosted_glass` — first/fourth RETAIN, second/third RESERVE ✓
- V.4 PBR: `triplanar_detail_normal` — RESERVE adopter ✓
- Audio: `f.bass_att_rel`, `stems.drums_energy_dev`, `stems.vocalsPitchNorm`, `f.valence`, `f.mid_att_rel`, `f.beat_phase01`, `vocalsPitchConfidence` — RETAIN/RESERVE
**New infrastructure flagged amber:** Caustics utility validation gate (CC.3). Documented `fbm8` fallback if caustic output is unworkable.
**Audit verdict implications:** CC is the highest-density consumer of currently-RESERVE capability. CC's success closes RESERVE → RETAIN on caustics, light shafts, `vol_density_height_fog`, `mat_polished_chrome`, `mat_wet_stone`, `triplanar_normal`.

### Increment V.12 — Glass Brutalist v2 + Kinetic Sculpture v2

**Design state:** Strategic in `docs/ENGINEERING_PLAN.md`; per-preset design docs not yet authored.
**Capabilities required (Glass Brutalist v2):**
- `mat_concrete` board-form variant — see §6 PROPOSED
- Anisotropic streak `mat_polished_chrome` — current recipe has streaking; verify sufficiency or polish pass
- `parallax_occlusion` (POM on walls) — RESERVE adopter ✓
- Volumetric light shafts — RESERVE adopter ✓
- Dust motes — engine `RayMarch.metal` doesn't have dust-mote utility; preset-internal `fbm4` lattice (Arachne pattern) is the precedent
**Capabilities required (Kinetic Sculpture v2):**
- `mat_brushed_aluminum`, `mat_polished_chrome` — RESERVE adopters ✓
- Likely `mat_ferrofluid` or `mat_frosted_glass` for accent surface — already in cookbook
**New infrastructure required:** `mat_concrete_board_form` (or parametric extension to `mat_concrete`) — see §6.

### Phase G-uplift — 12 catalog members

**Design state:** Per-preset scoping deferred to session start. Capabilities implied are existing presets' continued use; no novel infrastructure expected. Failed Approach #58 / D-102 precedent: presets failing the concept-viability gate get retired rather than tuned.

Per-preset capability impact:
- **Gossamer** (named primary target) — palette / motion / silence-fallback tuning; existing `mv_warp` consumer ✓; potential `mat_silk_thread` re-adoption (currently inlines)
- **Membrane** — fluid family, feedback pass; silence-fallback uplift may need additional FV deviation primitives (`*_dev` family already RETAIN)
- **Starburst** — particles pass RESERVE adopter ✓
- **Plasma / Nebula / Waveform / Spectral Cartograph** — lightweight rubric; validation-only expected
- **Glass Brutalist / Kinetic Sculpture / Volumetric Lithograph** — full rubric; preserved tuning expected; subsumed into V.12 for the first two
- **TestSphere** — diagnostic; likely retire candidate per Failed Approach #58 evaluation
- **Fractal Tree** — full rubric; mesh_shader RESERVE adopter ✓

**Audit verdict implications:** G-uplift surveys may surface additional capability needs not in the inventory. Audit's verdicts should be revisited per-preset at G-uplift session start.

### Phase MD — Milkdrop ingestion (per `docs/MILKDROP_STRATEGY.md`)

**Design state:** Strategy doc landed; Decisions A–J signed off (D-103 through D-112). Implementation not started.
**Three tiers, each with capability implications:**

**MD.5 — Classic Ports (10 presets per Decision J):**
- `mv_warp` mandatory — RESERVE adopters ✓ (10 named ports per D-112)
- Lightweight rubric (D-067(b)) — passes existing checks
- Procedural patterns (`proc_*`) — verdict pending Decision E resolution

**MD.6 — Evolved (~20 presets, opt-in stem affinity per D-108):**
- `mv_warp` mandatory
- ≥1 stem-driven routing — RESERVE adopters for stem deviation primitives
- Per-stem hue affinity (per D-108) — `palette_*` color variants potentially RESERVE adopters
- Section-awareness opt-in (per D-109) — see §6 PROPOSED (StructuralAnalyzer exposure)

**MD.7 — Hybrid (~5 presets, ray_march + mv_warp combination):**
- `ray_march` + `mv_warp` together — first proof of D-029-preserved combination since the April reverts; this is a non-trivial validation gate
- ≥2 stems
- Optional SSGI / PBR / MV-3a rich metadata
- Three named starters per D-107: Geiss *3D-Luz*, Rovastar *Northern Lights*, EvilJim *Travelling backwards in a Tunnel of Light*

**New infrastructure required:**
- **MilkdropTranspiler CLI** (`PhospheneTools/MilkdropTranspiler`) — does not yet exist; H.1 scope per D-110 (expression language only, no HLSL). PROPOSED — see §6.
- `mv3_features_used` JSON schema field — verify whether already in `PresetDescriptor` per D-031; add if not.
- Provenance metadata (`milkdrop_source` field) per D-111.

**Audit verdict implications:** Phase MD is the highest-volume RESERVE adopter for `mv_warp`, and the lift that turns several OPPORTUNISTIC verdicts (procedural patterns, palette variants, color spaces) into RESERVE if MD evolved-tier designs name them.

## §6 — Proposed new capabilities

### `mat_concrete_board_form` (or parametric `mat_concrete` extension)
**Description:** Board-form concrete with plank impressions, tie-rod holes, weathering — the brutalist surface vernacular V.12 (Glass Brutalist v2) requires.
**Backlog alignment:** V.12 Glass Brutalist v2.
**Cost estimate:** 1 session (design + recipe authoring + V.6 rubric M3 list update).
**Verdict:** PROPOSED.
**Rationale:** Named adopter exists. Either a new symbol (cleanest — V.12 calls `mat_concrete_board_form`, the existing `mat_concrete` stays as the generic plate-cast variant) or a parametric extension (`mat_concrete(formType: int)`). Recommend new symbol — V.6 rubric M3 already counts `mat_*` distinct symbols, the surface stays uncluttered.

### 2D SDF antialiasing pipeline
**Description:** `fwidth`-based 2D antialiasing primitives (`sdf_aa_fill`, `sdf_aa_stroke`, `sdf_aa_outline`) for direct-fragment presets that want crisp 2D shapes without reaching for textures.
**Backlog alignment:** Plasma + Nebula + Waveform fidelity uplift (Phase G-uplift). Currently these presets are pure-fragment with rough antialiasing; a clean 2D SDF pipeline would lift their visual ceiling significantly.
**Cost estimate:** 1-2 sessions (utility authoring + reference adoption in one preset to prove the surface).
**Verdict:** PROPOSED.
**Rationale:** Phase G-uplift's most ambiguous tier (lightweight presets) lacks a clear path to higher fidelity without changing the family. 2D SDF AA is the cleanest enabler. Probably ships as `Utilities/SDF/SDF2D.metal`.

### `MilkdropTranspiler` CLI tool
**Description:** Per `docs/MILKDROP_STRATEGY.md` H.1 scope (D-110): expression-language transpiler from Milkdrop's per-frame / per-pixel / per-shape / per-wave grammar to Metal/MSL. No HLSL handling in MD.5; revisit for MD.6/MD.7.
**Backlog alignment:** Phase MD — gating dependency for MD.5 / MD.6 / MD.7.
**Cost estimate:** 4-8 sessions (grammar audit MD.1 + parser + AST + emitter + integration tests). Single-preset proof in MD.4.
**Verdict:** PROPOSED.
**Rationale:** Already filed in MILKDROP_STRATEGY decisions; this audit just records it as an inventory-implied PROPOSED capability. Lives in a new `PhospheneTools/` directory (Swift Package Manager target separate from PhospheneEngine).

### ChromaExtractor exposed to FeatureVector
**Description:** `ChromaExtractor` runs in MIRPipeline (key estimation via Krumhansl-Schmuckler). Output is currently orchestrator-internal — not exposed to preset shaders via `FeatureVector` or `StemFeatures`. Add 2-4 floats: `f.key_class` (0-11 chromatic position), `f.key_confidence` (0-1), optionally `f.major_correlation` and `f.minor_correlation`.
**Backlog alignment:** Phase MD evolved tier could plausibly use key-coupled palette shifts. CC could plausibly use for hue derivation. Hypothetical adopters.
**Cost estimate:** 1 session (FV struct extension + MIRPipeline wiring + Metal preamble update + 1-preset demo).
**Verdict:** PROPOSED-LIGHT (lower-confidence than the other PROPOSED items — no current named adopter, but the analyzer output is wasted today and the cost is small).

### StructuralAnalyzer events exposed to shaders
**Description:** Section-boundary events fired into a per-preset slot or as `FeatureVector.section_change_pulse` (decaying float, peaks at boundary). Enables intra-preset reconfiguration at chorus/bridge transitions instead of relying on the orchestrator to switch presets.
**Backlog alignment:** Phase MD Decision G picked G.2 (StructuralAnalyzer opt-in per D-109). This makes the analyzer a callable surface; exposing to shaders is the natural extension.
**Cost estimate:** 1-2 sessions (FV extension + analyzer wiring + 1-preset demo).
**Verdict:** PROPOSED.
**Rationale:** D-109 already commits to StructuralAnalyzer becoming usable surface for MD.6+. Exposing to shaders is the load-bearing implementation step. LM's `bassCounter / 64` salt is a homegrown approximation today; a real section-boundary pulse would supersede it.

### Heat shimmer / refraction utility
**Description:** Screen-space refraction primitive (sample current frame buffer with normal-map perturbation) for heat-shimmer or transparent-overlay effects. Distinct from CC's caustic refraction (which is geometric).
**Backlog alignment:** No current named adopter.
**Cost estimate:** 1 session.
**Verdict:** CONSIDERED.
**Rationale:** Useful capability; no current consumer demand. Re-evaluate when a future preset wants the effect.

### Audio-driven mesh deformation
**Description:** Mesh-shader extension that displaces emitted vertices based on FeatureVector / StemFeatures values. FractalTree's mesh shader is procedural at the GPU; adding audio-driven deformation requires plumbing FV/stems into the mesh shader pipeline.
**Backlog alignment:** No current named adopter.
**Cost estimate:** 2-3 sessions.
**Verdict:** CONSIDERED.
**Rationale:** Plausible enabler for a future mesh-shader preset; FractalTree alone doesn't justify the work.

### Text rendering subsystem
**Description:** Font atlas + SDF font shader; or core-text rasterization to texture. SpectralCartograph's diagnostic labels currently use baked-in 3×5 bitmap font + dynamic Core Text overlay path.
**Backlog alignment:** No current named adopter.
**Cost estimate:** 3-5 sessions.
**Verdict:** CONSIDERED.
**Rationale:** No preset in the backlog needs legible text. Revisit if a future "lyric-aware" preset gets designed.

### Real chord recognition (Tonic)
**Description:** Chord recognition from FFT + chroma; expose harmonic context (chord root, chord quality, harmonic function) to FeatureVector.
**Backlog alignment:** D-028 deferred this pending MV-3c proof-out; MV-3c shipped.
**Cost estimate:** 5-8 sessions (model selection + integration + accuracy validation).
**Verdict:** DEFERRED.
**Gating condition:** Concrete preset demand. No current preset's design calls for chord-level coupling.

### Shadow mapping
**Description:** Real shadow maps (single-light or directional cascade) replacing the soft-shadow ray-march approximations.
**Backlog alignment:** None named.
**Cost estimate:** 4-6 sessions.
**Verdict:** DEFERRED.
**Gating condition:** A flagship preset (e.g. CC.5 polish) requesting it. Significant memory + perf cost; not justified by current backlog.

### Higher-order procedural texture (gabor, anisotropic noise)
**Description:** Gabor noise, anisotropic noise variants (current `worley_fbm` is isotropic).
**Backlog alignment:** None named.
**Cost estimate:** 1-2 sessions.
**Verdict:** CONSIDERED.

### Audio-reactive particle physics beyond Murmuration
**Description:** SPH fluid, flocking variants, attractor systems beyond Murmuration's curl-noise + audio-coupled drag.
**Backlog alignment:** None named (no backlog particle preset since Drift Motes retirement).
**Cost estimate:** 2-4 sessions per variant.
**Verdict:** CONSIDERED.
**Rationale:** D-097 says particle presets are siblings; adding particle-engine variants is plausible but no demand.

## §7 — Verdict summary table

Counts:
- **RETAIN:** ~30 capabilities (full §3 inventory, plus single-consumer load-bearing items called out in §4)
- **RESERVE:** ~25 capabilities (mv_warp + AV/CC/MD-named utilities + planned material adopters + per-preset GPU slots)
- **OPPORTUNISTIC:** ~70 capabilities (most of the V.2/V.3/V.4 cookbook with cluster-level option value but no individual adopter)
- **RETIRE-CANDIDATE:** ~25 capabilities (reaction-diffusion cluster, flow maps cluster, snake_case color aliases, demoted Marschner BRDF, several raw-noise primitives)
- **PROPOSED:** 5 capabilities (`mat_concrete_board_form`, 2D SDF AA pipeline, MilkdropTranspiler, ChromaExtractor exposure, StructuralAnalyzer exposure)
- **PROPOSED-LIGHT:** included in PROPOSED count
- **CONSIDERED:** 5 (heat shimmer, audio-driven mesh deformation, text rendering, gabor noise, particle physics variants)
- **DEFERRED:** 2 (Tonic chord recognition, shadow mapping)

Headline RETIRE-CANDIDATE clusters by LOC saved (estimated):
1. **Reaction-diffusion cluster** — 7 symbols, ~150 LOC + 1 test file. Largest single deletion.
2. **Flow maps cluster** — 6 symbols, ~120 LOC + 1 test file.
3. **Demoted Marschner BRDF** (`fiber_marschner_lite` + `trt_lobe`) — ~80 LOC + portion of `PBRUtilityTests`.
4. **`hsv_to_rgb` / `rgb_to_hsv` snake_case aliases** — ~10 LOC; alias-collapse rather than feature delete.
5. **`displace_perlin` raw variant** — ~15 LOC; redundant with `displace_fbm`.

Highest-leverage PROPOSED items:
1. **MilkdropTranspiler** — gates Phase MD entirely (~30 candidate ports across MD.5+MD.6+MD.7).
2. **2D SDF antialiasing pipeline** — single enabler for Phase G-uplift's lightweight-rubric tier (Plasma + Nebula + Waveform).
3. **`mat_concrete_board_form`** — gates V.12 Glass Brutalist v2.

Pending Phase MD strategy resolution:
- Procedural patterns (`proc_*` cluster) verdict = RESERVE if MD picks evolved-tier procedural-pattern adoption; RETIRE-CANDIDATE if not.

## §8 — Risks and open questions

- **RETIRE verdicts are not free.** Each cluster deletion involves: (a) symbol removal from the utility `.metal` file, (b) test fixture deletion (one suite per RD/FlowMaps/etc.), (c) verification that no other utility or preset transitively calls the symbol via inclusion order, (d) FidelityRubric symbol-list edits if any `mat_*` is involved. Estimate ~0.5-1 session per cluster.

- **OPPORTUNISTIC is the largest verdict cluster.** This reflects honest uncertainty — most V.2/V.3/V.4 utilities are speculatively useful but lack named adopters. The cluster-level argument for retention (the cookbook's coherence is part of the offering) keeps them present. Audit's value here is documenting that OPPORTUNISTIC is where the preview-and-defer decisions live; don't expect aggressive RETIRE on OPPORTUNISTIC items without specific cleanup pressure.

- **The "in active use" definition (≥1 consumer) is a low bar.** Some single-consumer capabilities (`vocals_pitch_hz`, `sss_backlit`, `voronoi_f1f2`) carry real per-frame cost. Per-tier perf attribution is out of scope for this audit; would surface as a separate "perf inventory" pass.

- **Phase MD strategy decisions affect verdicts.** Several "Pending Phase MD strategy" verdicts will resolve once MD.1 grammar audit completes and MD.5 candidate set proves out. Re-visit this audit after MD.5 lands.

- **Backlog evolves.** Verdicts that depend on backlog-named adopters (RESERVE) shift if a design gets re-scoped. Aurora Veil is design-complete and high-confidence; CC is design-complete but reference-curation pending; V.12 has no per-preset design doc yet. RESERVE confidence varies accordingly.

- **Architectural scope creep risk.** PROPOSED items like ChromaExtractor exposure / StructuralAnalyzer exposure modify `FeatureVector` (load-bearing engine struct, byte-layout regression-locked by `CommonLayoutTest`). Each requires the D-099 / D-101-class extension protocol — additive, golden-hash regen across all presets, layout test update. Not free.

- **Doc drift surfaced during audit.** CLAUDE.md's MV-3 section claims VolumetricLithograph uses `vocals_pitch_hz`; grep confirms it does not (Arachne is sole consumer). Other doc drift likely exists. Out of scope here; flag for a follow-up doc-audit pass.

## §9 — Acceptance / what "approved" means

Matt confirms each verdict in §11 (per-row signoff). Approved verdicts feed into ENGINEERING_PLAN.md:

- **RETIRE verdicts** → file as "Phase QR-cleanup" follow-up increment(s) scoping the deletions. Rule: file D-### entry per cluster RETIRE (the architectural decision to remove a capability is load-bearing). Rubric symbol-list edits are coupled.
- **RESERVE verdicts** → the design doc for the consuming preset cites this audit's RESERVE rationale. No immediate action; the increment naturally arrives.
- **OPPORTUNISTIC verdicts** → no immediate action; documented option value. Re-visit on next audit cycle (~6-12 months).
- **PROPOSED verdicts** → new engineering plan increment per item. Each gets its own design doc + Claude Code prompt.
- **PROPOSED-LIGHT verdicts** → new engineering plan increment, lower priority sequencing.
- **CONSIDERED / DEFERRED verdicts** → no action; revisit gate documented.

## §10 — Citations

- `docs/SHADER_CRAFT.md` — utility cookbook + materials reference + cert rubric authoring handbook
- `CLAUDE.md` — Module Map, GPU Contract, Visual Quality Floor, Failed Approaches
- `docs/ARCHITECTURE.md` — render pass surface, GPU contract overview
- `docs/ENGINEERING_PLAN.md` — Phase V, Phase AV, Phase CC, Phase G-uplift, Phase MD scoping
- `docs/DECISIONS.md` — D-026 (deviation primitives), D-027 (mv_warp opt-in), D-028 (MV-3), D-029 (motion paradigms not composable), D-030 (SpectralHistoryBuffer), D-045/D-055/D-062/D-063 (utility tree organization), D-067 (cert pipeline), D-097 (particle siblings not subclasses), D-099 (engine MSL struct extension), D-102 (Drift Motes retirement), D-107 through D-112 (Phase MD decisions)
- `docs/presets/AURORA_VEIL_DESIGN.md`, `docs/presets/CRYSTALLINE_CAVERN_DESIGN.md`, `docs/presets/ARACHNE_V8_DESIGN.md`
- `docs/MILKDROP_STRATEGY.md` — Phase MD strategic framework + Decisions A–J
- `docs/MILKDROP_ARCHITECTURE.md` — Phosphene render-pass breakdown per preset
- `docs/diagnostics/capability-audit-pre-2026-05-12.md` — raw inventory data + architectural caveats

## §11 — Sign-off

Format: one line per confirmed verdict. Append `(Matt YYYY-MM-DD)` and any modification rationale.

### Render passes
- [ ] `mv_warp` pass: RESERVE (AV + CC + Phase MD adopters)
- [ ] `mesh_shader` pass: OPPORTUNISTIC (FractalTree only)
- [ ] `particles` pass: OPPORTUNISTIC (Starburst only post-Drift Motes)
- [ ] `ssgi` pass: RESERVE (CC adopter)

### V.1 Noise
- [ ] `fbm4`, `warped_fbm`, `curl_noise`, `blue_noise_sample`: RESERVE (AV adopters)
- [ ] `ridged_mf`, `worley_fbm`, `simplex3d`: OPPORTUNISTIC (CC plausible adopter)
- [ ] `fbm12`, `fbm_vec3`, raw `perlin*`, `simplex4d`, `worley2d/3d`, `warped_fbm_vec`, `ign`, `ign_temporal`: OPPORTUNISTIC (cluster hold)

### V.2 Geometry
- [ ] SDF primitives + operations + modifiers (the unused majority): OPPORTUNISTIC cluster hold
- [ ] `displace_perlin`: RETIRE-CANDIDATE
- [ ] `displace_lipschitz_safe` / `_fbm` / `_beat_anticipation` / `_energy_breath`: OPPORTUNISTIC

### V.2 Volume
- [ ] Caustics cluster: RESERVE (CC.3 adopter, with `fbm8` fallback)
- [ ] HG phase functions + participating media: RESERVE for `hg_phase` + `vol_density_height_fog`; OPPORTUNISTIC otherwise
- [ ] Clouds cluster: OPPORTUNISTIC
- [ ] Light shafts: RESERVE (V.12 + CC adopters)

### V.2 Texture
- [ ] Voronoi unused variants: OPPORTUNISTIC
- [ ] Reaction-diffusion cluster: RETIRE-CANDIDATE (proposed deletion)
- [ ] Flow maps cluster: RETIRE-CANDIDATE (proposed deletion)
- [ ] Procedural patterns cluster: **PENDING Phase MD Decision E**
- [ ] Grunge cluster: OPPORTUNISTIC for `_dirt_mask` / `_dust`; RETIRE-CANDIDATE for the rest (cluster decision)

### V.3 Color
- [ ] `palette_*` variants: RESERVE for `palette_cool` (AV); OPPORTUNISTIC for others
- [ ] `gradient_*`, `lut_sample`: OPPORTUNISTIC
- [ ] `hsv_to_rgb` / `rgb_to_hsv` snake_case aliases: RETIRE-CANDIDATE (alias collapse)
- [ ] Lab + Oklab: OPPORTUNISTIC
- [ ] Chromatic aberration: OPPORTUNISTIC (V.6 P4 incentive)
- [ ] Tone mapping variants: OPPORTUNISTIC

### V.3 Materials cookbook
- [ ] All RETIRE-CANDIDATE verdicts blocked by FidelityRubric.swift coupling — cluster decision recommended
- [ ] `mat_polished_chrome`, `mat_brushed_aluminum`, `mat_ferrofluid`, `mat_wet_stone`, `mat_concrete`: RESERVE
- [ ] `mat_gold` through `mat_sand_glints` (the rest): OPPORTUNISTIC cluster hold

### V.4 PBR
- [ ] PBR utility tree (cook_torrance, fresnel, ggx, brdf, etc.): OPPORTUNISTIC cluster hold (architectural — engine has private impl)
- [ ] `triplanar_*`: RESERVE (V.6 E1 + CC.4 adopter)
- [ ] `parallax_occlusion`, `parallax_shadowed`: RESERVE (V.12 adopter, V.6 P2)
- [ ] `sss_backlit`: RETAIN (Arachne)
- [ ] `fiber_marschner_lite`, `trt_lobe`: RETIRE-CANDIDATE (demoted in Arachne V.7.9)
- [ ] `wrap_lighting`, `thinfilm_rgb`, `hue_rotate`: OPPORTUNISTIC

### Audio primitives
- [ ] MV-3a per-stem rich metadata (single-consumer fields): RESERVE (Phase MD evolved + CC adopters)
- [ ] `vocals_pitch_hz` / `vocals_pitch_confidence`: RESERVE (AV.2 + CC.4)
- [ ] `bass_rel` / `mid_rel` / `treb_rel`: OPPORTUNISTIC
- [ ] `beats_until_next`: RESERVE (Phase MD evolved)

### GPU buffer slots
- [ ] Slot 5 SpectralHistory: RESERVE (AV adopter)
- [ ] Slot 7 (Arachne spider): RESERVE
- [ ] Slot 8 (LumenPatternState): RESERVE — LM-namespaced

### PROPOSED capabilities
- [ ] `mat_concrete_board_form`: PROPOSED (V.12 adopter)
- [ ] 2D SDF antialiasing pipeline: PROPOSED (Phase G-uplift lightweight tier)
- [ ] MilkdropTranspiler CLI: PROPOSED (Phase MD gating dependency)
- [ ] ChromaExtractor exposure to FeatureVector: PROPOSED-LIGHT
- [ ] StructuralAnalyzer exposure to shaders: PROPOSED (D-109 implementation)

### CONSIDERED / DEFERRED
- [ ] Heat shimmer / refraction utility: CONSIDERED
- [ ] Audio-driven mesh deformation: CONSIDERED
- [ ] Text rendering subsystem: CONSIDERED
- [ ] Higher-order procedural texture (gabor): CONSIDERED
- [ ] Audio-reactive particle physics variants: CONSIDERED
- [ ] Tonic chord recognition: DEFERRED (gating: concrete preset demand)
- [ ] Shadow mapping: DEFERRED (gating: flagship preset request)

## §12 — Revision history

- **2026-05-12** — Initial audit authored. Inventory data captured at `docs/diagnostics/capability-audit-pre-2026-05-12.md`. Verdicts proposed; awaiting Matt sign-off.
