# Lumen Mosaic Design Doc

**Status:** Draft. Pending Matt sign-off on the open decisions in §3 before any code lands.

**Working name:** Lumen Mosaic. Alternates: **Fenestra** (Latin "window", clean and architectural), **Backlit Pane** (descriptive). Pick one in Decision A.

**Companion docs:**
- [`Lumen_Mosaic_Rendering_Architecture_Contract.md`](Lumen_Mosaic_Rendering_Architecture_Contract.md) — pass structure, buffer layouts, stop conditions, certification fixtures. Authoritative for implementation.
- [`LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md`](LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md) — phased Claude Code session prompts (LM.1 → LM.9).
- [`SHADER_CRAFT.md`](SHADER_CRAFT.md) §4.5b — `mat_pattern_glass` recipe; the foundation this preset extends.
- [`ENGINEERING_PLAN.md`](ENGINEERING_PLAN.md) — increment ledger; Phase LM increments below land here once approved.

---

## 1. Why this preset exists

The reference image (`04_specular_pattern_glass_closeup.jpg`) is a close-up of hammered pattern glass — irregular hex-biased cells, each a raised dimple (cell-scale shading relief, not panel-level curvature; the panel itself is flat) separated by sharp inter-cell ridges, every cell carrying a fine bumpy frost that catches light at sub-pixel scale, and behind the glass a tangible scene of strong colored light and dark silhouette. The visual subject is the cellular pattern itself; the colors come from whatever sits behind.

Phosphene's catalog already has the *material* for this — `mat_pattern_glass` (V.3 Materials cookbook §4.5b) was authored for Glass Brutalist v2 fins. What it doesn't have is a preset that uses pattern glass as the **entire** visual surface, with an audio-driven backlight scene as the source of color. This preset is that.

Aesthetic role: a meditative co-performer. Where Arachne renders the build of a web and Volumetric Lithograph renders psychedelic terrain, Lumen Mosaic renders a fixed window onto a moving room of light. The cells are the band. The lights moving behind them are the music. The viewer's gaze rests on the panel and watches color and pattern emerge through cell-quantization rather than on continuous geometry.

This is **not** Glass Brutalist v3. Glass Brutalist depicts brutalist concrete corridor architecture; pattern glass is one element in a bigger spatial composition. Lumen Mosaic has no architectural depicted scene — the glass *is* the scene, and the world behind exists only to backlight it.

**The product question this preset answers:** what does Phosphene look like for tracks where the right visual response is *holding still and shifting color*, not *generating motion*? Slow ambient, downtempo, dub, contemplative jazz, sparse vocal-led ballads. None of the certified ray-march presets sit in that pocket — Volumetric Lithograph is too gestural, Glass Brutalist depicts a moving camera through a static space, Kinetic Sculpture is geometric motion. Lumen Mosaic owns the still-and-shift register.

---

## 2. Constraints (non-negotiable)

These constraints frame every open decision in §3. They are inherited from CLAUDE.md and DECISIONS.md and are not relitigated here.

1. **Performance ceiling — Tier 1: 14 ms / Tier 2: 16 ms** (FrameBudgetManager). Lumen Mosaic should target **≤ 4 ms p95 at Tier 2** — the per-pixel cost is dominated by 3 `voronoi_f1f2` calls (~0.33 ms total at 1080p) plus N-light analytical sampling per cell plus standard PBR composite. There is no SDF complexity here (one planar glass panel) and no SSGI need (the panel is emissive-dominated). This preset should be the *cheapest* ray-march preset in the catalog.

2. **D-020 architecture-stays-solid.** The glass panel is fixed structure. Audio reactivity routes to lights, color, fog, and per-cell emission accent — never to panel geometry, never to cell shape, never to cell positions. The Voronoi seed lattice is constant for the lifetime of the preset.

3. **D-026 deviation primitives only.** All audio drivers use `_rel`/`_dev`/`_att_rel` fields, never raw `f.bass`/`f.mid`/`f.treble` values. AGC is centered at 0.5; visual drivers center at 0.

4. **D-019 silence fallback.** At `totalStemEnergy == 0`, blend via `smoothstep(0.02, 0.06, totalStemEnergy)` from stem-driven backlight to FeatureVector-driven backlight. The preset must have a non-black, visually coherent silence state.

5. **D-021 sceneMaterial signature.** `void sceneMaterial(float3 p, int matID, constant FeatureVector& f, constant SceneUniforms& s, thread float3& albedo, thread float& roughness, thread float& metallic)`. StemFeatures are not in scope for `sceneSDF`/`sceneMaterial` — this preset uses `f` directly with the D-019 fallback pattern (KineticSculpture / Volumetric Lithograph reference implementations).

6. **D-037 acceptance invariants.** Non-black at silence, no white clip on steady, beat response ≤ 2× continuous response + 1.0, form complexity ≥ 2 at silence. The cell-quantized output should naturally satisfy form complexity (cells alone produce > 2 luma bins).

7. **Continuous energy primary, beats accent.** D-004. Backlight movement and color are driven by `bass_att_rel` / `mid_att_rel` / `treb_att_rel` (continuous, zero-jitter). Beat onsets only trigger pattern accents (ripple wavefronts, brief shimmers).

8. **Detail cascade mandate** (CLAUDE.md, SHADER_CRAFT.md §2.2). Four scales of variation are required:
   - Macro: cell layout (Voronoi at scale ≈ 30)
   - Meso: per-cell dome height variation (`v.f1` / `v.f2` distance fields)
   - Micro: in-cell frost noise (high-octave fbm on cell surface for normal perturbation)
   - Specular breakup: sub-pixel sparkle from the micro-frost normal hitting Cook-Torrance specular
   
   Skipping the micro layer collapses the preset back to flat-cell stained-glass. This is the primary fidelity carrier.

9. **No external dependencies.** Stays on Metal + the V.1–V.3 utility library. No new utility modules required by this preset (modulo Decision F — see §3).

10. **I (Claude) cannot see rendered output.** Every visual judgment in implementation comes from Matt. Phase boundaries require Matt-driven contact-sheet review against the reference image and against the silence/steady/beat-heavy/mood-quadrant fixtures.

---

## 3. Open decisions — these need answers before any code

Each decision below has my recommendation, but **Matt picks**. Decisions are independent unless flagged.

### Decision A — Preset name

**Option A.1 — Lumen Mosaic.** "Lumen" reads as light-quantity (lux, lumen, illumination); "Mosaic" reads as cellular-tessellation. Two-word evocative, follows the catalog convention (Volumetric Lithograph, Kinetic Sculpture, Glass Brutalist, Spectral Cartograph). On the nose for what it does.

**Option A.2 — Fenestra.** Latin for window. Single-word, classic, architectural without the religious freight of "stained glass" or "cathedral". Reads as severe and clean. Risk: less obvious what it depicts before you've seen it.

**Option A.3 — Backlit Pane.** Maximally descriptive. Very plain, no poetic pretense. Risk: feels like a working name, not a final name.

**Recommendation: A.1 (Lumen Mosaic).** Matches the catalog naming idiom and is unambiguous about the visual role. Fenestra is more elegant in isolation but less informative alongside Glass Brutalist (which is also a window/glass-themed name); the catalog reads more cohesively when names trade in their own register rather than competing for the same signifier.

---

### Decision B — Backlight scene complexity

**Option B.1 — N audio-driven point lights, no behind-glass geometry.** The "world behind" is purely a multi-light field, sampled analytically per cell. Each cell projects its center to a notional back-plane at fixed depth, sums N lights' falloff-attenuated contributions at that point, and emits the result through the glass material. No silhouettes, no occluders, no back-wall geometry.

**Option B.2 — N lights + analytical 2D occluder masks.** Adds 1–3 simple silhouette shapes (rectangles, ellipses, organic blobs from `worley_fbm`) at notional mid-depth that attenuate light contribution to cells whose projected center falls behind the silhouette. Still no real 3D geometry; the silhouettes are screen-space SDFs evaluated per cell.

**Option B.3 — Real 3D back geometry.** Add SDFs for a back-wall plane and 1–3 silhouette pillars/forms in `sceneSDF`. Trace through the glass to those surfaces; light them with conventional Cook-Torrance.

**Trade-off:** B.1 ships fastest and is a clean read against the reference image's brighter regions, but loses the dark-silhouette-spine character of the reference (the vertical occluding form in the middle). B.2 recovers the silhouette character cheaply (~0.05 ms per occluder) and stays in the analytical regime. B.3 is the most physically faithful but requires per-fragment second-bounce trace through the glass — a meaningful infrastructure addition for a marginal fidelity gain.

**Recommendation: B.1 for LM.1–LM.4, B.2 for LM.5+ if Matt's review judges the panel reads as flat without silhouettes.** B.1 gets us to a working preset fastest and proves the cell-color-from-backlight pipeline works end-to-end. The silhouettes from the reference are valuable but deferring them costs nothing — the architecture in B.1 extends to B.2 without rework. Skip B.3; if Phosphene ever gains preset-level second-bounce ray tracing it'll come from a pipeline-level decision, not a single preset's needs.

---

### Decision C — Cell density

**Option C.1 — ~30 cells across (large cells).** `voronoi_f1f2` scale ≈ 18. Each cell is ~64 px at 1080p. Reads as bold, painterly, architectural. Closer to traditional architectural pattern glass.

**Option C.2 — ~50 cells across (medium cells).** Scale ≈ 30. Each cell ~38 px at 1080p. Closest to the reference image. Reads as honeycomb-dense.

**Option C.3 — ~80 cells across (small cells).** Scale ≈ 48. Each cell ~24 px at 1080p. Reads as fine-grained, more like jewelry or stained-glass mosaic. Most expensive (more cells means more pattern evaluations per frame, but Voronoi cost is per-pixel not per-cell so this doesn't actually move performance — what it costs is cell-pattern legibility, since a single cell becomes too small to carry a recognizable per-cell color).

**Recommendation: C.2 (~50 cells across, scale ≈ 30).** Closest to the reference's apparent density; large enough that per-cell color reads legibly; small enough that the cellular tessellation is the dominant visual texture rather than a coarse stain. Expose `cell_density` as a JSON-tunable uniform so the parameter survives certification and can be re-tuned without code edits.

**Constraint that affects this decision:** the V.3 cookbook recipe (§4.5b) at scale=18 was authored for an architectural fin viewed from ~3 m. A full-screen panel viewed straight-on has different pixel-per-unit math; we'll re-anchor scale against pixels-per-cell rather than world-units. Document the transformation in `CLAUDE.md` so future authors understand what "scale" means in this preset's coordinate system.

---

### Decision D — Cell color sourcing

**Option D.1 — Per-cell uniform color from cell-center backlight sample.** Each cell takes its color from the backlight-field value sampled at the cell's *center*. Within the cell, the value is constant. The frosted micro-noise modulates the *normal* (so the specular highlight breaks up) but the diffuse base color is uniform across the cell.

**Option D.2 — Per-pixel backlight sample, cell-quantized.** Each pixel samples backlight at its own position, and the cell-quantization happens at the cell-edge ridge (the inter-cell line). This produces gradient tints within a single cell (a cell straddling a light-source edge is half-lit / half-shadow). More natural-looking, less graphic.

**Option D.3 — Hybrid: cell-center for diffuse, per-pixel for emission.** Diffuse base color is cell-quantized (D.1); but a per-pixel emission term reads the backlight at the pixel position, so bright lights bloom across cells where they sit.

**Trade-off:** The reference image shows mostly per-cell uniform color (the orange stripe is whole orange cells, not gradient cells). D.1 most directly matches. D.2 is more photographically natural but loses the graphic stained-glass character. D.3 is a compromise that gets cell-quantization for the dominant tone but keeps highlight bleed for visual punch.

**Recommendation: D.1 for LM.1–LM.3; reassess at LM.4.** The cell-quantization is the visual identity. Per-pixel sampling can come later if the preset reads as too flat — but my read of the reference is that flatness IS the look. Phosphene already has continuous-color presets (Volumetric Lithograph, Murmuration); Lumen Mosaic earns its place by being graphically discrete. If LM.4 review says cells feel inert, D.3 is the upgrade path.

---

### Decision E — Mood-driven palette

**Option E.1 — Valence/arousal → light color shift.** Each backlight uses a base color modulated by `f.valence` (warm/cool axis: orange-amber positive valence, blue-teal negative) and `f.arousal` (saturation/brightness: low arousal desaturated, high arousal punchy). Lights stay individually colored but the whole palette shifts.

**Option E.2 — Mood-quadrant palette switching.** Four authored palette sets (HV-HA, HV-LA, LV-HA, LV-LA), one active per current mood quadrant, smoothly crossfaded with a 5 s low-pass on mood. Each palette is 4–6 distinct colors that the lights pick from.

**Option E.3 — IQ cosine palette + mood phase.** Use the V.3 `palette()` function with an IQ cosine palette parameterized so that valence rotates the palette phase and arousal scales chroma. One palette equation, full mood coverage.

**Trade-off:** E.1 is simplest but gets monotonous on long valence-stable tracks. E.2 has the strongest "this song looks different from that song" identity but requires explicit palette authoring per quadrant. E.3 is mathematically elegant but harder to art-direct.

**Recommendation: E.1 for LM.1–LM.4, E.2 for LM.5+.** Land the basic mood-color coupling first, then invest in the per-quadrant authored palettes when the preset is otherwise complete. Per-quadrant palettes are the kind of thing that benefits from session-recording iteration on real tracks across the mood plane (Arachne 5-second mood smoothing pattern from ARACHNE_V8_DESIGN.md is the template).

---

### Decision F — Pattern state buffer slot

**Option F.1 — New fragment buffer at slot 8.** Extend `RenderPipeline` with `directPresetFragmentBuffer3` (per CLAUDE.md, "Other presets that need additional buffers must use slots ≥ 8"). Bind a `LumenPatternState` struct (size ~256 bytes: 4 active patterns × ~16 floats each + globals). Updated CPU-side per frame from `LumenPatternEngine.swift`.

**Option F.2 — Pack into SceneUniforms free lanes.** Use `cameraForward.w` and any other unused lanes (currently exhausted-or-near-exhausted by Glass Brutalist's fin-X repurposing). At most ~4–8 free floats. Insufficient for 4 patterns.

**Option F.3 — Compute pattern state in shader from a smaller input.** Pass only the pattern *seed* / pattern-bank *index* per active pattern, then evaluate analytically in the shader. Saves bytes but constrains pattern complexity (no arbitrary origins or directions per pattern instance).

**Trade-off:** F.1 is the cleanest and the most extensible — every future Lumen-style preset that needs preset-uniform CPU-driven state benefits. F.2 is hacky and runs out of room fast. F.3 limits expression in a way that hurts pattern composability.

**Recommendation: F.1.** Add the `directPresetFragmentBuffer3` slot to `RenderPipeline` once; this preset is the first consumer; later presets can share it. Document in CLAUDE.md alongside the slot 6/7 documentation. The new slot does not collide with anything (slot 8 is currently unused). One increment of infrastructure work (LM.1) for one decade of headroom.

---

### Decision G — Camera

**Option G.1 — Fixed camera, panel oversized to bleed past the frame.** Camera at z = -3, looking at z = 0. FOV ≈ 30° (narrow, near-orthographic). Panel at z = 0 sized at **`cameraTangents.xy * 1.50`** so panel edges are well outside the frame at all four sides. The viewer sees only the field of cells filled with light — never a panel boundary, never the empty void around the panel. No camera movement.

**Option G.2 — Slow constant-speed dolly (Glass Brutalist pattern).** Camera dollies forward at e.g. 0.5 u/s. The glass panel grows slowly in the frame; cells appear to scale up over a 30 s arc; preset transition resets camera. Familiar feel; matches D-020's "camera moves, architecture doesn't" idiom.

**Option G.3 — Subtle parallax sway.** Camera sways ±0.05 u in x/y on a slow Lissajous-like pattern (40 s period). Adds life without disrupting the contemplative still-and-shift role.

**Recommendation: G.1 (fixed camera, panel bleeds past frame).** Per Matt 2026-05-08: the glass panel must fill the frame *and extend outside it*, so the only thing visible is the pattern of light against glass — no panel edges, no negative space. Panel half-extents = `cameraTangents.xy * 1.50` (50% margin on every side; survives any future camera-jitter additions and prevents corner artifacts). Lumen Mosaic's role is the still-and-shift register; camera motion fights that. The reference image is a still photograph; the visual identity is the stillness of the glass while light dances behind it. G.2 belongs to Glass Brutalist; importing it here muddies the differentiation. G.3 is a defensive add-on against the preset feeling boring, but if it feels boring with a static camera the fix is more pattern variety, not camera jitter.

**Implication for light agents.** Because the panel extends 50% past the frame on all sides, naively allowing light agents to drift across the full panel face would waste illumination on invisible area. Light-agent positions are clamped to the **visible cell area** (`uv ∈ [-1, +1]` in panel-face uv where the frame edges are; panel SDF goes to ±1.5). See contract §P.2 for clamp math.

**Implication for "the dance".** Matt's intent: light should *dance* behind the glass *in sync with the beat*. This is consistent with Phosphene's continuous-energy-primary / beat-onset-accent rule (memory: "Beat onset pulses have inherent timing jitter and should be accent-layer only"), but it elevates `beat_phase01` (the *continuous* beat-clock phase from BPM tracking — not the jittery onset) from "pattern transition trigger" to **co-primary visual driver alongside stem energy**. See Decision § audio coupling update below and contract §P.4.

---

### Decision H — Standalone preset, or extend Glass Brutalist?

**Option H.1 — New standalone preset.** New `LumenMosaic.metal` + `LumenMosaic.json`. Glass Brutalist v2 (V.12) is independent; both ship in the catalog.

**Option H.2 — Glass Brutalist v3 with a "panel mode" toggle.** Add a JSON field `lumen_panel_mode: true` that swaps Glass Brutalist's brutalist scene for a single front-facing pattern glass panel.

**Recommendation: H.1.** The aesthetic role is fundamentally different (meditative co-performer vs. brutalist-architecture-with-light). Forcing them into one preset damages both. Glass Brutalist's identity is the corridor and the moving camera. Lumen Mosaic's identity is the still panel and the moving light behind. They share `mat_pattern_glass` and the deferred PBR pipeline, but their `sceneSDF` / camera / lighting paradigms are distinct. Two presets, one shared material recipe.

---

## 4. Proposed architecture (assumes Decisions A.1, B.1, C.2, D.1, E.1, F.1, G.1, H.1)

If Matt picks differently, §4 needs revision before §5 (the rendering contract) is final. The contract document is structured to track these decisions explicitly.

### 4.1 Render passes

`LumenMosaic.json` `passes` → `["ray_march", "post_process"]`.

The `ray_march` pass is Phosphene's existing 3-pass deferred:
1. **G-buffer** — depth, normal, material ID, albedo. Per-pixel ray march into `sceneSDF`. For Lumen Mosaic, `sceneSDF` returns the glass panel SDF (a single `sd_box` at z = 0 with thickness ≈ 0.04). One-step trace; no expensive ray-march iteration needed.
2. **Lighting** — Cook-Torrance BRDF + IBL ambient + (optional) SSGI. Reads G-buffer, writes lit RGB. Lumen Mosaic's emission term carries most of the visible color; specular sells the wet/glossy frosted look; albedo is near-white dielectric.
3. **Composite** — tone-map + final color.

`post_process` adds bloom (the cell emission needs to bleed across cell-edge ridges to feel lit-from-behind rather than printed) and ACES.

**SSGI:** intentionally **disabled** for this preset. The glass panel is emission-dominated; SSGI's contribution is invisible against bright emissive cells, and the ~0.5 ms saved keeps headroom for the pattern engine. JSON: omit `ssgi` from `passes`.

### 4.2 sceneSDF skeleton

```metal
float sceneSDF(float3 p, constant FeatureVector& f, constant SceneUniforms& s, constant StemFeatures& stems) {
    // Single planar glass panel. Fixed structure per D-020.
    // Panel face at z = 0, thickness 0.04 (front face z = -0.02, back face z = +0.02).
    // Panel half-extents = cameraTangents.xy * 1.50: panel must extend 50% beyond frame
    // on every side so panel edges are NEVER visible (Decision G.1, contract §P.1).
    constexpr float kPanelOversize = 1.50;
    float3 panel_size = float3(s.cameraTangents.xy * kPanelOversize, 0.02);
    return sd_box(p, panel_size);
}

void sceneMaterial(float3 p, int matID, constant FeatureVector& f, constant SceneUniforms& s,
                   thread float3& albedo, thread float& roughness, thread float& metallic) {
    // matID 0 = glass (only material in this preset)
    
    // Cell pattern: voronoi_f1f2 in panel-face uv space.
    // NOTE: panel_uv divides by cameraTangents (NOT by cameraTangents * kPanelOversize).
    // This makes uv ∈ [-1, +1] at the visible frame edges and ∈ [-1.5, +1.5] at panel SDF
    // edges, so cell density is independent of the oversize factor (contract §P.1).
    float2 panel_uv = p.xy / s.cameraTangents.xy;  // normalized -1..1 across visible frame
    const float scale = 30.0;  // ≈ 50 cells across (Decision C.2)
    
    float2 q  =  panel_uv                       * scale;
    float2 qx = (panel_uv + float2(0.005, 0.0)) * scale;
    float2 qy = (panel_uv + float2(0.0, 0.005)) * scale;
    
    VoronoiResult v0 = voronoi_f1f2(q,  4.0);
    VoronoiResult vx = voronoi_f1f2(qx, 4.0);
    VoronoiResult vy = voronoi_f1f2(qy, 4.0);
    
    // Cell ID for addressability and per-cell hash:
    uint cell_id = v0.id;
    float cell_phase = float(cell_id & 0xFFFF) * (1.0 / 65535.0);
    float2 cell_center_uv = v0.pos / scale;  // cell center in -1..1 panel-face uv
    
    // Domed cell + sharp ridge (V.3 §4.5b recipe):
    float h0 = (1.0 - saturate(v0.f1 * scale)) * smoothstep(0.0, 0.04, v0.f2 - v0.f1);
    float hx = (1.0 - saturate(vx.f1 * scale)) * smoothstep(0.0, 0.04, vx.f2 - vx.f1);
    float hy = (1.0 - saturate(vy.f1 * scale)) * smoothstep(0.0, 0.04, vy.f2 - vy.f1);
    float3 height_grad = float3(h0 - hx, h0 - hy, 0.001) * (1.0 / 0.005);
    
    // Micro-frost normal perturbation (the "hammered" feel — required per detail cascade §2.8):
    float3 frost = float3(
        fbm8(p * 80.0),
        fbm8(p * 80.0 + float3(13.1, 0.0, 0.0)),
        fbm8(p * 80.0 + float3(0.0, 17.3, 0.0))
    );
    float3 frost_n = (frost - 0.5) * 0.10;  // tighter than mat_frosted_glass (0.15) — ridges already strong
    
    float3 base_n = float3(0.0, 0.0, -1.0);  // panel face normal (camera looks down +z)
    float3 perturbed_n = normalize(base_n + height_grad * 0.04 + frost_n);
    
    // Sample backlight at cell center (Decision D.1):
    float3 backlight = sample_backlight_at(cell_center_uv, f, s, stems);
    
    // Apply per-cell pattern accent:
    float pattern_value = evaluate_active_patterns(cell_center_uv, cell_phase, s);
    float3 pattern_color = pattern_color_at(cell_center_uv, cell_phase, f, s);
    backlight = mix(backlight, pattern_color, pattern_value);
    
    // Final material — pattern glass with emission carrying the backlight signal:
    albedo    = float3(0.85, 0.88, 0.90);
    roughness = 0.40;
    metallic  = 0.0;
    // emission set on a separate path (G-buffer's emission lane); see §4.3
}
```

The emission term is the carrier of nearly all visible color. The albedo/roughness/metallic exist mostly to give the specular a clean dielectric character against IBL ambient (so the cells read as glass, not as flat colored cards).

### 4.3 Backlight sampling (Decision B.1)

Implemented as `sample_backlight_at(uv, f, s, stems)` in the shader. Reads the `LumenPatternState` buffer at slot 8 for light agent positions/colors/intensities. Pure function of cell position — no ray tracing.

```metal
float3 sample_backlight_at(float2 cell_center_uv, FeatureVector f, SceneUniforms s, StemFeatures stems) {
    LumenPatternState ps = pattern_state_at_buffer(8);  // bound at slot 8 (Decision F.1)
    
    float3 acc = float3(0);
    for (int i = 0; i < ps.active_light_count; i++) {
        LightAgent L = ps.lights[i];
        // L.position is in panel-face uv coords (-1..1 plus a notional depth axis).
        float2 dxy = cell_center_uv - L.position.xy;
        float r2 = dot(dxy, dxy) + L.position.z * L.position.z;  // z is "depth into panel" — affects spread, not geometric occlusion (B.1)
        float att = L.intensity / (1.0 + L.attenuation_radius * r2);
        acc += L.color * att;
    }
    
    // Ambient floor: mood-tinted, prevents black at silence (D-019/D-037).
    float3 ambient_floor = mood_tint(f.valence, f.arousal) * 0.04;
    return acc + ambient_floor;
}
```

### 4.4 Pattern engine

CPU-side `LumenPatternEngine` (Swift, in the engine module) maintains a stable list of ≤ 4 active patterns. Each pattern has:

- **type** — enum: `idle`, `radial_ripple`, `sweep`, `cluster_burst`, `breathing`, `noise_drift`. (LM.4 ships idle + radial_ripple + sweep; LM.5 adds cluster_burst + breathing + noise_drift.)
- **origin** — 2D point in panel-face uv (-1..1)
- **direction** — for sweep: unit vector
- **phase** — float, advanced per frame
- **intensity** — float, scales the per-cell value the pattern produces
- **color** — float3, the color the pattern injects when active
- **start_time** / **duration** — for time-bounded patterns

Pattern selection logic:
- **Bar boundaries** (`f.beat_phase01` rolls past 1.0 OR a future bar-phase predictor): retire the oldest pattern and start a new one. The new pattern's parameters are seeded from the current mood quadrant + a deterministic per-bar hash so the same track is reproducible.
- **Drum onsets** (`stems.drums_beat` rising edge with debounce): trigger a `radial_ripple` from a stem-driven origin, regardless of active patterns. Fire-and-forget; the pattern auto-retires when its expanding wavefront passes the panel edge.
- **Section transitions** (`SpectralCartograph` or future bar-phase predictor): force a clean palette + pattern reset.

### 4.5 Audio coupling

Per D-026 / D-019. All drivers use deviation primitives. Stem-direct reads with FeatureVector fallback.

**The dance.** Per Matt's framing intent (Decision G addendum), the lights should *dance* behind the glass in visible sync with the beat. The dance has two layers, in priority order:

1. **Beat-locked oscillation (co-primary).** Each light agent's position is composed from a slow drift (mood-driven) + a **`beat_phase01`-locked oscillation** scaled by `arousal` and stem energy. Because `beat_phase01` is the continuous BPM-tracked beat clock (not the jittery onset signal), this oscillation is smooth and zero-lag — but the eye reads it as beat-synchronous because peaks land on beats. This is what the viewer perceives as "the dance."
2. **Stem energy modulation (co-primary).** Light intensities still respond continuously to `*_att_rel` energy bands per Phosphene's continuous-energy-primary rule. Energy provides amplitude; beat phase provides rhythm.
3. **Onset accents (accent-only).** `stems.drums_beat` triggers radial ripple wavefronts (LM.4) and per-cell shimmer (LM.7). Onsets are jittery so they're never trusted as primary motion.

| Audio source | Visual target | Notes |
|---|---|---|
| `f.bass_att_rel` | Lights[0] (bass agent) intensity | Continuous; primary energy carrier |
| `f.mid_att_rel` | Lights[1] (mid agent) intensity | Continuous |
| `f.treb_att_rel` | Lights[2] (treble agent) intensity | Continuous |
| `f.beat_phase01` | **All light positions: co-primary oscillation phase** | Continuous beat-clock; smooth, zero-lag. Drives the dance. See contract §P.4 |
| `f.valence` | Light color temperature (warm/cool axis) | 5 s low-pass per ARACHNE pattern |
| `f.arousal` | (a) Drift speed (b) **`beat_phase01` oscillation amplitude** | Calm = small dance, frantic = wider dance |
| `stems.drums_beat` (D-019 fallback `max(f.beat_bass, f.beat_mid, f.beat_composite)`) | Ripple wavefront trigger | Beat accent layer; not primary motion |
| `stems.bass_energy_rel` (D-019 fallback `f.bass_dev * 0.6`) | Bass-light position drift bound | Bass agent dances harder when bass is loud |
| `stems.vocals_energy_dev` (D-019 fallback 0.0) | Vocal hotspot intensity (sub-pattern) | Vocals "speak" through individual cells |
| `stems.other_energy_rel` (D-019 fallback `f.treble * 1.4`) | Ambient color field intensity | Slow palette wash |

**Light agent position composition (per agent, per frame):**
```
position = base_position
         + drift_term(arousal, time)                              // slow mood-driven wander
         + beat_dance_term(beat_phase01, arousal, stem_energy)    // co-primary, beat-locked
         + (bar_pattern_offset if pattern_active)                 // LM.4+ patterns
position = clamp_to_visible_uv(position)                          // stay within frame
```
Detailed math, amplitudes, and clamp regions: contract §P.4.

**Light agents:**
- 4 lights, one per stem (drums / bass / vocals / other).
- Each light has a base position (drums upper-left, bass center-low, vocals center-mid, other upper-right) and dances within a stem-specific bounding region clamped to the visible frame area (uv ∈ [-1, +1]).
- Drift speed and dance amplitude are both functions of `f.arousal` (slow + small at low arousal, faster + wider at high).
- Color is a function of `f.valence` shifted by per-stem hue offset (drums = warm, bass = deep red, vocals = cream/peach, other = cool-blue).

This produces the reference image's character: each region of the panel "belongs" to a stem, and the colors arrive in that region when that stem is active — and the whole field of light pulses with the beat.

---

## 5. Reference and anti-reference

### 5.1 Hero reference

`04_specular_pattern_glass_closeup.jpg` — the user-uploaded close-up of hammered pattern glass.

**Traits to extract** (per Gate 1 of Preset_Development_Protocol.md):

- **Macro:** ~50 hex-biased Voronoi cells across, irregular hexagons not perfect hexagons.
- **Meso:** each cell appears as a raised dimple (per-cell shading relief; the panel SDF stays flat — the dimpled appearance comes from `mat_pattern_glass` V.3's height-gradient normal perturbation, not from SDF deformation); sharp ridge between cells; thin dark seam between cell edges.
- **Micro:** in-cell frosted bumpy texture; sub-cell-scale specular sparkle from random oriented micro-facets.
- **Material:** dielectric, near-white albedo, moderate roughness, high transmissive emission character (bright cells glow, not just reflect).
- **Lighting:** evidently strong colored backlights at multiple positions producing the orange / blue / red regions; dark central vertical occluder.
- **Motion:** N/A in the reference (still photo). For the preset: cell layout is static; light agents drift; colors shift; per-cell accents emerge and fade.
- **Audio-reactive (this preset):** colors of cells change with mood and bands; cell-pattern accents emerge on beats; everything else stays still.
- **Failure modes to preflight against:**
  - Reading as flat stained glass (cell-quantization without specular variation) — fix: micro-frost normal mandate (§2.8).
  - Reading as TV static (per-pixel noise without cell coherence) — fix: cell-quantize the dominant tone (Decision D.1).
  - Reading as a photo of glass (no audio reactivity visible) — fix: light agents move with continuous energy AND beat-locked oscillation; pattern accents fire on beats.
  - Reading as a stained-glass cathedral cliché (saturated primaries in fixed iconographic arrangement) — fix: light-agent positions drift; mood-driven palette; no ecclesiastical symmetries.
  - **Panel boundary visible in frame** (sizing math wrong, or future camera-jitter pushes corners off panel) — fix: panel half-extents `cameraTangents.xy * 1.50` per Decision G.1; LM.6 contact sheet must verify zero panel edge artifacts at 16:9 + 4:3 + 21:9 aspect ratios.
  - **Dance reads as random / not beat-locked** (lights wander but don't pulse with the beat) — fix: `beat_phase01`-locked oscillation amplitude is co-primary, not a small accent; LM.4 review must confirm peak-on-beat readability against a known-BPM track.

### 5.2 Trait matrix

| Trait | Source | Implementation |
|---|---|---|
| Hex-biased Voronoi cells | ref macro | `voronoi_f1f2` at scale 30 (Decision C.2) |
| Domed cell + sharp ridge | ref meso | V.3 §4.5b height-gradient recipe |
| In-cell frost | ref micro | `fbm8(p * 80)` × 3 normal channels at amplitude 0.10 |
| Specular sparkle | ref material | Cook-Torrance with frost-perturbed normal vs. IBL |
| Backlit color zones | ref lighting | 4 audio-driven point lights, analytical sample (Decision B.1) |
| Dark silhouette spine | ref lighting | **Deferred to LM.5 / Decision B.2** if Matt judges flat |
| Cell-quantized tone | ref material | Sample backlight at cell center, not per-pixel (Decision D.1) |
| Static panel | preset role | `sceneSDF` returns same shape every frame (D-020) |
| Mood-driven palette | preset role | Light hue / sat / val mod by valence/arousal (Decision E.1) |
| Beat-triggered ripples | preset role | `LumenPatternEngine` ripples on `stems.drums_beat` |
| Bar-boundary palette shift | preset role | Pattern engine retires/spawns on bar |

### 5.3 Anti-references

- **Stained-glass cathedral imagery** (saturated primary RGB, religious-iconographic symmetry). Avoid all cross / mandala / radial-symmetry pattern presets. The pattern engine is explicitly biased toward asymmetric, off-center, drifting motifs.
- **TV-static / film-grain glass** (per-pixel high-frequency noise that doesn't respect cell boundaries). The micro-frost is *normal-perturbing*, not *color-perturbing*. Frost adds specular sparkle; it does not modulate the cell's diffuse color.
- **Lava lamp / plasma / blob aesthetic** (continuous gradient blobs without cell quantization). Lumen Mosaic's identity is the discrete cellular grid; if it ever reads as a continuous color field, the preset has failed.
- **Reference-rejection check at LM review boundaries:** Matt must explicitly confirm "no stained-glass cathedral cliché" and "no continuous-blob aesthetic" at every contact-sheet review.

---

## 6. Phased plan (Phase LM)

Each increment lands in `ENGINEERING_PLAN.md` once approved. Done-when criteria and verify commands per increment are in `LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md`.

| Increment | Scope | Sessions (est.) |
|---|---|---|
| LM.0 | Gate audit; verify protocol intake completeness; extend `RenderPipeline` with `directPresetFragmentBuffer3` (Decision F.1) | 1 |
| LM.1 | Minimum viable preset: glass panel + pattern_glass material + 1 static backlight color. Proves the rendering works. No audio. | 2 |
| LM.2 | 4 audio-driven light agents (continuous energy primary). Mood-coupled hue shift. D-019 silence fallback. | 2 |
| LM.3 | Stem-direct routing for the 4 light agents. Stem-driven base positions and per-stem hue offsets. | 1 |
| LM.4 | Pattern engine v1: `idle`, `radial_ripple`, `sweep`. Bar-boundary triggering via `f.beat_phase01`. Drum-onset ripple. | 2 |
| LM.5 | (Optional, Decision B.2) Silhouette occluder masks if Matt judges the panel reads flat without them. Pattern engine v2: `cluster_burst`, `breathing`, `noise_drift`. | 2 |
| LM.6 | Fidelity polish: micro-frost tuning, specular sparkle calibration, cell-density A/B against reference. | 1 |
| LM.7 | Beat accent layer: `stems.drums_beat` ripples, bar-line shimmer, vocal-hotspot sub-pattern. | 1 |
| LM.8 | Mood-quadrant palette authoring (Decision E.2 promotion). Session-recording iteration on real tracks across the mood plane. | 2 |
| LM.9 | Certification: rubric 10/15 pass, performance verification, golden hash registration, `certified: true`. | 1 |

**Total estimate: 13 sessions.** Comparable to V.7 (Arachne) in the V phase.

---

## 7. Acceptance criteria

The preset is certified when **all** of the following hold against the standard fixture set (silence / steady / beat-heavy / sustained bass / HV-HA / LV-LA mood) AND against three real tracks Matt nominates:

### 7.1 Mandatory (rubric 7/7 per CLAUDE.md fidelity rubric)

1. **Detail cascade present.** Macro (cell layout) + meso (dome+ridge) + micro (in-cell frost) + specular breakup all visible in zoomed contact-sheet inspection. A frame downsampled to 32×32 still shows recognizable cells; a frame at full res shows specular sparkle within cells.
2. **≥ 4 noise octaves.** `fbm8` is called for the in-cell frost. Confirmed structurally.
3. **≥ 3 distinct materials.** Plasma-family exemption does not apply to this preset; we need three. Materials present: pattern glass cell body, cell-edge ridge highlight (effectively a sub-material via height-gradient roughness mod), backlight emission. Documented in JSON `materials_used`.
4. **D-026 deviation primitives audio routing.** No `f.bass`/`f.mid`/`f.treble` raw reads. CI-checkable via grep.
5. **D-019 silence fallback.** At total stem energy zero, preset shows mood-tinted ambient backlight at the cell-quantized character. Non-black, visually coherent. Tested fixture.
6. **p95 frame time ≤ Tier 2 budget (16 ms).** Target: ≤ 4 ms p95 at 1080p Tier 2; reach: ≤ 2.5 ms. Measured via `PresetPerformanceTests`.
7. **Matt-approved reference frame match.** Side-by-side with `04_specular_pattern_glass_closeup.jpg` via the harness contact sheet, reads as "the same kind of surface". Not exact (live preset has different colors than the still photo) but unambiguously the same material family.

### 7.2 Expected (≥ 2/4)

1. **Triplanar texturing on non-planar surfaces** — N/A; the panel is planar. **Skipped (1/4 max).**
2. **Detail normals** — present (the in-cell frost normal perturbation). **Met.**
3. **Volumetric fog or aerial perspective** — minimal; the scene has effectively no depth so aerial perspective doesn't apply. A mood-tinted IBL ambient stands in. **Partial (0.5/1).**
4. **SSS / fiber BRDF / anisotropic specular** — emission-as-SSS-approximation present (mat_pattern_glass `emission = albedo * 0.15`). **Met (counts as SSS-lite).**

Score: ~2.5/4. Above the ≥ 2 threshold.

### 7.3 Strongly preferred (≥ 1/4)

1. **Hero specular highlight in ≥ 60% of frames** — the cell-edge ridges plus IBL produce constant specular variation. **Met.**
2. **POM on at least one surface** — N/A. **Skipped.**
3. **Volumetric light shafts or dust motes** — N/A. **Skipped.**
4. **Chromatic aberration / thin-film interference** — could add chromatic aberration on cell-edge ridges as a polish item (LM.6). **Optional.**

Score: 1/4 mandatory met; 1 optional in LM.6.

### 7.4 Total rubric score

Mandatory 7/7 + Expected 2.5/4 + Strongly Preferred 1/4 = **10.5 / 15**. Threshold is 10/15 with all mandatory passing. **Cleared.**

### 7.5 Acceptance against the reference image

A 30-second clip of the preset, captured at HV-HA mood with steady moderate energy, should produce a frame where:

1. Cells are visibly hex-biased and tessellated, with consistent cell density.
2. At least 3 distinct color regions are present (one per active stem-light + ambient).
3. Specular sparkle is visible within at least 30% of cells in the bright regions.
4. The cell-edge ridges produce a visible inter-cell network of dark seams.
5. No cell exhibits gradient color across its area (Decision D.1 quantization is preserved).
6. No two consecutive frames are visually identical (light agents are drifting).
7. Beat hits produce a visible rippling change in cell brightness from a coherent origin point.

**Matt M7 review** at LM.6 + LM.9 against this list and against the reference image side-by-side via harness contact sheet.

---

## 8. Out of scope

- **Refraction through the glass** (real second-bounce trace through the cell to a backing scene). The preset uses analytical backlight per Decision B.1; refraction would require pipeline-level second-bounce ray tracing infrastructure that no current preset uses. If Phosphene later adds that, a `LumenMosaic v2` could opt in.
- **Per-cell persistent state** (e.g., "this cell was lit by the last beat and is fading"). All pattern evaluation is stateless per frame, derived from `cell_center_uv + cell_phase + time + audio`. Persistent per-cell state would require a feedback texture or a CPU-side per-cell state buffer; defer until a future increment if a particular pattern needs it.
- **Direct manual cell selection** (user picks specific cells to glow). The pattern engine produces patterns; individual cells are not addressable from the JSON sidecar. Cell IDs are deterministic but not numbered for human authoring.
- **Glass thickness simulation / depth refraction.** The panel has a notional thickness in `sceneSDF` (0.04 units) but no inside-the-glass effects (caustics, dispersion). Pattern glass in real life has these; matching them requires the second-bounce trace above.
- **Track-section-aware pattern bank.** Pattern selection is bar-driven and mood-driven, not section-driven (intro/verse/chorus/bridge). Section awareness lands when `StructuralPrediction` is reliable enough that other presets adopt it.

---

## 9. Citations and grounding

- **Pattern glass references and material recipe.** SHADER_CRAFT.md §4.5b `mat_pattern_glass`. Reference texture: user-uploaded `04_specular_pattern_glass_closeup.jpg`.
- **Architecture-stays-solid principle.** DECISIONS.md D-020 (Glass Brutalist Option A).
- **Audio data hierarchy.** CLAUDE.md "Layer 1–5b" + DECISIONS.md D-004, D-026.
- **Silence fallback pattern.** DECISIONS.md D-019; reference implementation in `VolumetricLithograph.metal`.
- **Voronoi cell addressability via `v.id`.** SHADER_CRAFT.md §4.6 `mat_ferrofluid` (`cellPhase = float(v.id & 0xFFFF) * (6.283185 / float(0xFFFF))`).
- **Cook-Torrance + IBL + bloom + ACES pipeline.** ARCHITECTURE.md `RayMarchPipeline` and `PostProcessChain`.
- **Mood smoothing pattern (5 s low-pass on valence/arousal).** ARACHNE_V8_DESIGN.md §11 palette mapping.
- **Preset acceptance gate.** DECISIONS.md D-037, D-039; `PresetAcceptanceTests` and `PresetRegressionTests`.

---

## 10. Sign-off

This document is ready to take to Claude Code as soon as Matt has answered Decisions A through H in §3. The companion rendering contract (`Lumen_Mosaic_Rendering_Architecture_Contract.md`) and the session prompts (`LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md`) assume the recommended decisions; adjust both if Matt picks differently.

**For Matt's review:**

- Confirm preset name (Decision A).
- Confirm backlight scene structure (Decision B).
- Confirm cell density (Decision C).
- Confirm cell color sourcing (Decision D).
- Confirm mood-palette plan (Decision E).
- Confirm fragment buffer slot 8 addition (Decision F).
- Confirm camera (Decision G).
- Confirm standalone preset, not a Glass Brutalist variant (Decision H).
- Confirm Phase LM as the increment-ledger phase tag.
- Confirm out-of-scope items in §8 (none of these become quietly in-scope without a decision).
