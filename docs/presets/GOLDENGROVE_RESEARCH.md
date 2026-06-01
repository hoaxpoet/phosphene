# Goldengrove — Research Record (2026-06-01)

Source material behind `GOLDENGROVE_PLAN.md`. Two parallel research passes.

## A. Engine-internal feasibility (file:line findings)

- **§4.7 Bark / §4.8 Leaf are PROSE recipes**, not ready-to-call functions (`SHADER_CRAFT.md:587–655`). Utilities that exist: `worley3d` (`Utilities/Texture/Worley.metal`), `fbm8` (`Utilities/Noise/FBM.metal`), `triplanar_detail_normal` (`Utilities/PBR/Triplanar.metal`). Bark ~0.9 ms/hit, Leaf ~0.4 ms/hit (estimates).
- **§4.8 leaf SSS requires per-pixel view (V) + light (L) directions** — NOT available in the direct mesh-shader fragment path; requires the deferred G-buffer path. Recipe: `sss = saturate(dot(V,-L))^3; emission = (0.6,0.8,0.2)*sss*0.8`.
- **§8.3 POM is a ready utility** (`Utilities/PBR/POM.metal:1410–1460`: `parallax_occlusion`, `parallax_occlusion_shadowed`) but needs **tangent frames** the current `MeshVertex` lacks. ~1.0 ms basic / ~2.0 ms shadowed.
- **§5.6 golden hour is a scene-config recipe** (light pos/color/intensity + IBL tint + fog), not a shader function (`SHADER_CRAFT.md:1021–1026`).
- **Existing FractalTree** (`FractalTree.metal:1–276`): `passes: ["mesh_shader"]`, binary L-system (63 branches / 6 levels, iterative ancestry traversal), screen-aligned quads, flat HSV fragment color (no lighting), growth = `branch_count 3..63 ← bass_att` (`:48–53`). **Mesh vertex budget MAXED at 252 verts** (`:72–82`). M1/M2 fallback = fullscreen gradient.
- **Mesh-preset lighting:** only via `passes: ["ray_march"]` + `setMeshGBufferEncoder` closure (`RenderPipeline+PresetSwitching.swift:167–177`); consumer = `FerrofluidMesh`. Direct `mesh_shader` path cannot do PBR materials/lighting.
- **ArachneState pattern** (`ArachneState.swift`): per-frame `tick(features:stems:)` via `setMeshPresetTick`; audio-modulated pace `1.0 + 0.18*midAttRel + max(0, 0.5*drumsEnergyDev)` (`:840–843`); pause guards before `effectiveDt` (`:823–845`); flushes state array to MTLBuffer. Template for `GoldengroveState`.
- **Foliage:** `ParticleGeometry` path (Murmuration/FFO) handles 5k–20k sprites at 2–3 ms; separate render pass. Mesh-shader leaf emission possible but budget-constrained.
- **FeatureVector** (`Common.metal:9–46`): continuous energy (bass/mid/treble + att + 6-band + deviation primitives), beats (beat_*/beat_phase01/bar_phase01/beats_per_bar), spectral (centroid/flux), valence/arousal, time/delta_time/accumulated_audio_time/track_elapsed_s. **CONFIRMED: no section/boundary/build/peak/structural field.**

## B. External technique grounding (cited sources)

**Geometry (L-system on GPU):**
- jysandy, "Procedural Foliage with L-systems + Instancing" — https://jysandy.github.io/posts/procedural-trees/ (single tree ~3.65 ms; overdraw is dominant cost)
- tree-gen (space colonization impl) — https://github.com/dsforza96/tree-gen
- IQ SDF trees (background-only, not hero) — https://iquilezles.org/articles/distfunctions/

**Growth animation:**
- Runions et al. 2007, Space Colonization — https://algorithmicbotany.org/papers/colonization.egwnp2007.large.pdf (believable asymmetric growth, inherently temporal)
- L-system lerp growth — https://www.youtube.com/watch?v=TOPxa1xIG5Q
- **forest-env (key finding: bake growth stages offline + swap/morph beats live regeneration)** — https://arxiv.org/pdf/2208.01471

**Foliage back-lit SSS (best-grounded):**
- Frostbite / Barré-Brisebois translucency, GDC 2011 — https://www.ea.com/frostbite/news/approximating-translucency-for-a-fast-cheap-and-convincing-subsurface-scattering-look (~6 ALU ops; `pow(saturate(dot(V,-(L+N*distortion))),p)*scale*thickness`)
- GPU Gems Ch.16 wrap lighting — https://developer.nvidia.com/gpugems/gpugems/part-iii-materials/chapter-16-real-time-approximations-subsurface-scattering
- GPU Gems 3 Ch.16 Crysis vegetation (thickness texture) — https://www.oreilly.com/library/view/gpu-gems-3/9780321545428/ch16.html

**Painterly NPR (cost-sensitive):**
- Maxime Heckel, painterly shaders / anisotropic Kuwahara — https://blog.maximeheckel.com/posts/on-crafting-painterly-shaders/
- pmndrs Kuwahara pass — https://post-processing.tresjs.org/guide/pmndrs/kuwahara
- Brushstroke-as-particle painterly (foliage-by-construction) — ResearchGate 220978900

**Golden-hour atmosphere (cheap/proven):**
- God rays: GPU Gems 3 Ch.13 (volumetric light scattering post-process); Shadertoy https://www.shadertoy.com/view/XlVXDw ; Cyanilux https://www.cyanilux.com/tutorials/god-rays-shader-breakdown/
- Dust motes: point sprites / scrolling Worley; altitude fog `exp(-height*density)` tinted (FA #38)

**Audio-reactive growth:**
- **NO PRECEDENT FOUND.** Plant bio-sonification is plant→sound (opposite). No citable reference for music→tree-growth. Risk flag #1 — Spike 1.

## C. Risk flags (external research)

1. Audio-driven growth: no prior art → empirical spike, surface as grounding-level-3.
2. Live growth + dense foliage + wide painterly post unproven *together* in 16 ms → bake growth offline, brushstroke-billboard foliage, moderate/half-res Kuwahara.
3. Single hero tree with thousands of *distinct* leaves heavier than any cited example → leaf count = measured product decision.
4. Anisotropic Kuwahara is the only budget-blowing mechanism → prototype + measure first (Spike 2).
