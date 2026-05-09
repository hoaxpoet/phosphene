# Lumen Mosaic Design Doc

**Status:** Active. Revised 2026-05-09 after the LM.2 production review found the original "meditative co-performer" framing wrong and the LM.1–LM.2 visual output too muted. Changes in this revision (see §11 Revision History): aesthetic role flipped from meditative to **energetic**; Decision D promoted from D.1 (cell-quantized agent sample) to **D.4 (per-cell color identity from `palette()` keyed on cell hash + audio time + mood)**; Decision E promoted from E.1 / E.2 (cream-baseline tint / authored palette banks) to **E.3 (procedural palette via IQ cosine, no authored banks)**; cream baseline retired. The original LM.1 / LM.2 implementations stand as scaffolding that proved the slot-8 binding works; the **substantive look ships at LM.3** under the new architecture.

**Companion docs:**
- [`Lumen_Mosaic_Rendering_Architecture_Contract.md`](Lumen_Mosaic_Rendering_Architecture_Contract.md) — pass structure, buffer layouts, stop conditions, certification fixtures. Authoritative for implementation.
- [`LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md`](LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md) — phased Claude Code session prompts (LM.1 → LM.9).
- [`SHADER_CRAFT.md`](SHADER_CRAFT.md) §4.5b — `mat_pattern_glass` recipe; the foundation this preset extends.
- [`ENGINEERING_PLAN.md`](ENGINEERING_PLAN.md) — increment ledger; Phase LM increments below land here once approved.

---

## 1. Why this preset exists

The reference images (`04_specular_pattern_glass_closeup.jpg` for the cell + frost macro / micro detail, `05_lighting_pattern_glass_dual_color.jpg` for the saturated multi-color backlight character) show hammered pattern glass — irregular hex-biased cells, each a raised dimple separated by sharp inter-cell ridges, every cell carrying a fine bumpy frost that catches light at sub-pixel scale, and behind the glass strong colored light. **Each cell carries its own color**, vivid, often differing markedly from its neighbors. The visual subject is the cellular pattern itself; the colors arrive per cell.

Phosphene's catalog has the *material* for this — `mat_pattern_glass` (V.3 Materials cookbook §4.5b) was authored for Glass Brutalist v2 fins. What it doesn't have is a preset that uses pattern glass as the **entire** visual surface, with vivid per-cell color driven by music. This preset is that.

**Aesthetic role: an energetic dance partner.** Lumen Mosaic is the preset that makes people want to get up and dance. Cells change constantly — every cell carries its own evolving color, the panel as a whole shifts palette character with mood, and on a kick-driven track the field of cells reads as a vibrant honeycomb that pulses and cycles in time with the music. Where Arachne renders the build of a web and Volumetric Lithograph renders psychedelic terrain, Lumen Mosaic renders **a panel of stained glass alive with color, dancing to the music behind it**.

Phosphene-wide invariant (CLAUDE.md): **muted palettes have no place in the catalog.** Quiet *moments* exist (silence, breakdowns, intros) but the active visual register is always vivid, saturated, alive. Lumen Mosaic is one of the strongest expressions of this invariant — the cellular structure is a substrate for color, and the color is the point.

This is **not** Glass Brutalist v3. Glass Brutalist depicts brutalist concrete corridor architecture with pattern glass as one element in a bigger spatial composition; Lumen Mosaic has no architectural depicted scene — the glass *is* the scene, and color through the glass is the music.

**The product question this preset answers:** what does Phosphene look like when the visual response is "the music makes a stained-glass window come alive"? Energetic electronic, kick-driven dance, danceable hip-hop, vocal-led pop, anything where the right reaction is "look at all the colors." None of the certified ray-march presets sit in that pocket — Volumetric Lithograph is gestural terrain, Glass Brutalist depicts moving architecture, Kinetic Sculpture is geometric motion. Lumen Mosaic owns the **vibrant-cell-field-dancing-with-the-music** register.

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

### Decision D — Cell color sourcing — RESOLVED 2026-05-09: D.4

> **Original options D.1 / D.2 / D.3 are retired.** D.1 was implemented in LM.2 and the production review proved it doesn't paint visible cells: a smoothly-varying analytical light field, sampled at the cell-centre uv, produces values that vary too little between adjacent cells to read as discrete cells. The math was right; the model was wrong.

**Adopted: D.4 — Per-cell color identity from `palette()` keyed on cell hash + audio time + mood.**

```
cell_t  = float(cell.id & 0xFFFF) / 65535.0       // [0, 1) per cell, deterministic
phase   = cell_t + accumulated_audio_time × kCellHueRate + mood_drift
hue_rgb = palette(phase, a, b, c, d)              // V.3 IQ cosine palette
                                                   // a, b, c, d shifted by mood
cell_intensity = sum over agents of (intensity / (1 + r² × k))   // unchanged
albedo  = hue_rgb × cell_intensity
```

**Why this works:**

- **Cell identity is per-cell, not per-position.** Each cell has its own deterministic phase from `cell.id`, so cells on opposite sides of the panel can carry wildly different colors simultaneously — the stained-glass character. Adjacent cells get adjacent palette samples (small phase difference) → smooth-but-discrete neighbors. Distant cells can be on opposite sides of the palette wheel.
- **Cells change constantly because `accumulated_audio_time` advances with energy.** At silence `accumulated_audio_time` stops advancing → cells hold their hue (rest, per Matt 2026-05-09). At loud music it advances fast → cells visibly cycle through the palette. The user-facing tuning knob is `kCellHueRate`; first-pass default 0.05 cycles/audio-time-unit, M7-tuned in LM.3 review against a known-BPM track.
- **Stems drive intensity, not hue.** A drum hit lights the cells overlapped by the drums-agent's lobe — the cells' *color* is whatever the palette gave them, the agent's contribution is brightness. This is the "simpler-first" stem mapping per Matt 2026-05-09; per-stem hue affinity (cells brighten preferentially for "their" stem based on hue similarity) is reserved for LM.5+ if review says the unified-palette feel is too undifferentiated.
- **Mood shifts the palette character, not individual cell colors.** Valence rotates `d` (palette phase offset); arousal scales `b` (chroma amplitude). Same track at HV-HA gets a different palette than at LV-LA, but every cell within a frame sees the same `(a, b, c, d)` — they only differ in their per-cell `phase`. This keeps the panel coherent.

**The cream baseline is retired.** The previous mood-tint formula `mix(cream, hue, sat)` always pulled toward `(1.0, 0.95, 0.85)` and produced pastel output regardless of input. D.4 has no cream baseline; cells are drawn directly from the palette and saturation is whatever the palette equation produces (typically `b ≈ 0.4–0.6` per channel → saturated by construction).

**What's lost vs the original D.1 plan:** the "lights with positions and colors behind the glass" mental model. Agents are now intensity sources, not colored lights. The light-positions metaphor was coherent but the model didn't paint visibly, so it goes.

**Reference-image fidelity:** `05_lighting_pattern_glass_dual_color.jpg` shows distinct vivid color zones across the panel. D.4 produces the same character via per-cell palette sampling — adjacent cells with similar phase form short color "runs", the panel as a whole spans the palette range.

---

### Decision E — Mood-driven palette — RESOLVED 2026-05-09: E.3

> **Original options E.1 (cream-baseline mood tint) and E.2 (4 authored palette banks) are retired.** E.1 produced the muted output that the LM.2 production review flagged. E.2 was rejected on monotony grounds — 4 hand-picked palettes mean every track in a given mood quadrant looks identical, defeating the "the panel reflects the music" intent. Per Matt 2026-05-09: "Why are there four hand-picked palettes — this will lead to a very monotonous preset?"

**Adopted: E.3 — Procedural palette via IQ cosine.** The V.3 `palette()` utility (`Sources/Presets/Shaders/Utilities/Color/Palettes.metal`) is the canonical Inigo Quilez form `a + b × cos(2π × (c × t + d))`. Lumen Mosaic parameterizes it directly:

| Parameter | Mood mapping | Effect |
|---|---|---|
| `a` (offset) | `mix(a_cool, a_warm, warmAxis)` | Mid-grey baseline shifts warm/cool with valence |
| `b` (amplitude) | `mix(b_subdued, b_vivid, arousalAxis)` | Chroma amplitude — saturated at high arousal |
| `c` (frequency) | constant `(1.0, 1.0, 1.0)` | Per-cell phase covers full hue range across the palette |
| `d` (phase offset) | `mix(d_warm_palette, d_cool_palette, warmAxis)` | Palette character (warm orange→pink vs cool teal→violet) shifts with valence |

`warmAxis = (smoothedValence + 1) / 2` and `arousalAxis = (smoothedArousal + 1) / 2`, both in `[0, 1]`. Mood smoothing stays at 5 s low-pass (ARACHNE §11 pattern). The palette parameters interpolate continuously across mood — no quadrant boundaries, no abrupt switches.

**Vividness is non-negotiable.** Even at `arousalAxis = 0` (LV-LA quadrant), `b_subdued` is set so the palette stays saturated. "Subdued" means narrower hue range / cooler character, not desaturated. Specifically: `b_subdued = (0.35, 0.40, 0.45)` (still vivid blues / teals); `b_vivid = (0.50, 0.50, 0.50)` (full saturation neon range). At silence the panel rests by holding still — `accumulated_audio_time` stops advancing — but cells stay vibrant.

**Per-cell hue cycling.** Time evolution comes through `phase = cell_t + accumulated_audio_time × kCellHueRate + mood_drift`. `kCellHueRate` is the master tuning knob for "how fast cells change":

- `0.0` — cells static, hue determined by `cell_t` and mood only.
- `0.05` (first-pass default) — full hue cycle takes ~20 seconds of energetic music. Visible cycling without strobing.
- `0.20` — full cycle every ~5 seconds. Restless, possibly too busy.
- `1.0` — full cycle per beat. Discotheque.

LM.3 ships at 0.05; M7 review against a 120 BPM calibration track is the trigger to retune. Matt explicitly noted he can't pre-specify the right value without seeing it (2026-05-09); this constant is the obvious M7 tuning surface.

**Why not authored palette banks (E.2)?** Two reasons. (1) Monotony: four palettes split the entire valence-arousal plane into four boxes; every HV-HA track plays back in the same palette, every LV-HA track plays back in the same other palette, etc. The procedural form has *infinite* palette characters because `(a, b, c, d)` interpolates smoothly through 4-D space. (2) Authoring cost: hand-picked palettes drift out of step with the rest of the catalog and require periodic retuning; the procedural form has one tuning surface (the four endpoint palette characters) shared with every preset that uses `palette()`.

**Why not Decision D's per-cell hash + a *single* palette?** It would work, but the result wouldn't read differently between tracks of different mood. The mood-driven palette parameter shift is what makes "this song looks different from that song." E.3 keeps that property without authored palettes.

---

### Decision E.b (sub-decision) — Per-stem hue affinity? — DEFERRED to LM.5 review

Open question: should each stem's intensity contribution to a cell be weighted by hue similarity, so a "warm-red" cell brightens preferentially when drums fire and a "cool-cyan" cell when "other" content plays? This would give the panel a "different stems own different cell zones" character emerging from hue proximity, without quadrant-locking.

**LM.3 v1 ships without this** — stems drive intensity uniformly across all cells overlapped by their lobe. Per Matt 2026-05-09: "I like the hue family suggestion better. What do you think will yield the best outcome?" Answer: simpler-first; if LM.3 review says the panel feels undifferentiated stem-wise, we add hue affinity in LM.5. Don't pay the complexity cost until we know it earns its keep.

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

`sceneSDF` is unchanged from LM.1: single planar glass panel, half-extents `cameraTangents.xy × 1.50` so the panel bleeds past the frame on every side, with Voronoi domed-cell relief + `fbm8` frost baked in as Lipschitz-safe SDF displacements (D-020 architecture-stays-solid; G-buffer central-differences normal picks up the relief). LM.3 doesn't touch it.

```metal
float sceneSDF(float3 p, constant FeatureVector& f, constant SceneUniforms& s, constant StemFeatures& stems) {
    constexpr float kPanelOversize = 1.50;
    float3 panel_size = float3(s.cameraTangents.xy * kPanelOversize, 0.02);
    float box_dist = sd_box(p, panel_size);
    // Band-limited relief + frost displacement (LM.1 contract §P.1):
    if (box_dist > kReliefBandRadius) return box_dist;
    float2 panel_uv = p.xy / s.cameraTangents.xy;
    float relief = lm_cell_relief(panel_uv);
    float frost  = lm_frost(p) - 0.5;
    return box_dist - relief * kReliefAmplitude - frost * kFrostAmplitude;
}
```

### 4.3 sceneMaterial — D.4 per-cell color identity

```metal
void sceneMaterial(float3 p, int matID,
                   constant FeatureVector& f, constant SceneUniforms& s,
                   constant StemFeatures& stems,
                   thread float3& albedo, thread float& roughness,
                   thread float& metallic, thread int& outMatID,
                   constant LumenPatternState& lumen) {
    // Project hit position into panel-face uv (D-LM-buffer-slot-8 contract):
    float2 panel_uv = p.xy / s.cameraTangents.xy;

    // Voronoi cell membership. v.id is the deterministic per-cell hash;
    // v.pos is the cell-centre uv in panel space. (V.3 Voronoi.metal contract.)
    VoronoiResult v = voronoi_f1f2(panel_uv, kCellDensity);
    float cell_t   = float(v.id & 0xFFFF) * (1.0 / 65535.0);   // [0, 1) per cell
    float2 cell_center_uv = v.pos;

    // Per-cell hue from procedural palette. Phase composes:
    //   - cell_t        : per-cell deterministic offset (each cell has its own colour)
    //   - audio_phase   : f.accumulated_audio_time × kCellHueRate
    //                     (cells cycle through palette during energetic music; rest at silence)
    //   - mood_drift    : slow drift driven by 5 s smoothed valence
    float audio_phase = f.accumulated_audio_time * kCellHueRate;
    float mood_drift  = lumen.smoothedValence * 0.10;
    float phase = cell_t + audio_phase + mood_drift;

    // Palette parameters interpolate continuously across mood (E.3 — no quadrant
    // boundaries). Vivid even at low arousal (no cream baseline).
    float warmAxis    = saturate(lumen.smoothedValence * 0.5 + 0.5);
    float arousalAxis = saturate(lumen.smoothedArousal * 0.5 + 0.5);
    float3 a = mix(kPaletteACool, kPaletteAWarm, warmAxis);
    float3 b = mix(kPaletteBSubdued, kPaletteBVivid, arousalAxis);
    float3 c = float3(1.0, 1.0, 1.0);
    float3 d = mix(kPaletteDCoolPalette, kPaletteDWarmPalette, warmAxis);
    float3 cell_hue = palette(phase, a, b, c, d);   // V.3 IQ cosine palette

    // Cell intensity: analytical agent falloff at the cell centre (unchanged
    // from LM.2). Stems drive intensity, not hue. The agent's stored `colorR/G/B`
    // is unused at LM.3 — kept for future per-stem hue affinity (LM.5+).
    float cell_intensity = 0.0;
    int agentCount = min(lumen.activeLightCount, 4);
    for (int i = 0; i < agentCount; ++i) {
        LumenLightAgent ag = lumen.lights[i];
        float2 d_uv = cell_center_uv - float2(ag.positionX, ag.positionY);
        float  r2   = dot(d_uv, d_uv) + ag.positionZ * ag.positionZ + 1.0e-4f;
        cell_intensity += ag.intensity / (1.0 + r2 * ag.attenuationRadius);
    }

    // Vibrant baseline so silence stays vivid (just held — accumulated_audio_time
    // stops advancing → cells hold their hue, but the baseline brightness keeps
    // them lit). D-019 silence fallback: cell_intensity floors at kSilenceIntensity.
    cell_intensity = max(cell_intensity, kSilenceIntensity);

    // Albedo carries the per-cell colour signal (matID == 1 contract). Lighting
    // fragment multiplies by kLumenEmissionGain (4.0) so the saturated palette
    // values (b ≈ 0.4–0.6 per channel) clear PostProcessChain bloom threshold.
    albedo = clamp(cell_hue * cell_intensity, 0.0, 1.0);
    roughness = 0.40;
    metallic  = 0.0;
    outMatID  = 1;
}
```

### 4.4 Pattern engine

CPU-side `LumenPatternEngine` (Swift) maintains the four light agents (still per-stem, unchanged from LM.2: drums / bass / vocals / other) plus the smoothed mood values used by sceneMaterial. **The agents now drive cell intensity only** — their `colorR/G/B` fields are present for ABI continuity but unused by D.4.

LM.4 will add the pattern slot machinery (≤ 4 active patterns: idle / radial_ripple / sweep). Patterns inject *additional* per-cell intensity bursts at chosen origins; their colour comes from the same per-cell palette (so a radial ripple on a "warm-red" cell flashes warm-red, on a "cool-cyan" cell flashes cool-cyan). This preserves the unified-panel aesthetic — pattern bursts amplify the existing palette rather than overlaying their own colours.

Pattern triggering (LM.4):
- **Bar boundaries** (`f.barPhase01` rolls past 1.0): retire oldest pattern, start a new one. Deterministic per-bar hash for reproducibility.
- **Drum onsets** (`stems.drumsBeat` rising edge with debounce): fire `radial_ripple` from a stem-driven origin, regardless of active patterns. Auto-retires when wavefront passes panel edge.
- **Section transitions** (future): force palette parameter reset.

### 4.5 Audio coupling — D-026 deviation primitives, D-019 silence fallback

Per the project rules. All audio drivers use `_rel`/`_dev`/`_att_rel` fields.

| Audio source | Visual target | Notes |
|---|---|---|
| `stems.drumsEnergyRel` (D-019 fallback `f.beatBass × 0.6 + f.beatMid × 0.4`) | Drums-agent intensity (1 of 4 light lobes) | Continuous; primary kick driver. |
| `stems.bassEnergyRel` (D-019 fallback `f.bassDev × 0.6`) | Bass-agent intensity | Continuous; sustained-bass driver. |
| `stems.vocalsEnergyDev` (D-019 fallback `0`) | Vocals-agent intensity | Vocals "speak" through their lobe. |
| `stems.otherEnergyRel` (D-019 fallback `f.trebAttRel × 1.4`) | Other-agent intensity | Synths / pads / leads. |
| `f.accumulated_audio_time` | Per-cell hue cycling phase | Cells cycle through palette during energetic music; rest at silence. **The "cells change constantly" mechanism** (Matt 2026-05-09). |
| `f.valence` | Palette `a` + `d` shift (warm/cool axis) | 5 s low-pass; same track in different moods plays back in different palette character. |
| `f.arousal` | Palette `b` shift (chroma amplitude) | 5 s low-pass; high arousal → more saturated palette. |
| `f.beatPhase01` | Light-agent figure-8 dance position | Per LM.2 contract §P.4. The agents *move* (subtly) on the beat — their lobes drift across the cell field, lighting different cells in time. |
| `stems.drumsBeat` (D-019 fallback `max(f.beatBass, f.beatMid, f.beatComposite)`) | Pattern-engine `radial_ripple` trigger (LM.4+) | Beat accent layer. |

**The dance.** Two layers, both active:

1. **Per-cell palette cycling (the new primary).** `accumulated_audio_time` advances faster during loud passages, so cells visibly cycle through the palette during energetic music. This is what reads as "the panel dancing." Tuning constant: `kCellHueRate` (LM.3 default 0.05; M7 retune in LM.3 review).
2. **Light-agent motion (LM.2 contract §P.4 dance).** Each agent traces a small `beat_phase01`-locked figure-8 around its base position. As the lobe moves, different cells brighten, giving the panel a "wave of light moving through the cell field." Amplitude scales with arousal; survives unchanged from LM.2.

**Silence.** `accumulated_audio_time` stops advancing → cells hold their current hue. `cell_intensity` floors at `kSilenceIntensity` so cells remain coloured (not black, not cream — *coloured*, just held). The floor is the D-019 silence fallback. Per Matt 2026-05-09: silence is a moment of rest, not a separate aesthetic register; the panel stays neutral by holding the palette still, not by retreating to grey.

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

**Light agents (LM.3 revised):**
- 4 lights, one per stem (drums / bass / vocals / other).
- Each light has a base position and a `beat_phase01`-locked figure-8 dance within a stem-specific bounding region clamped to the visible frame area (uv ∈ [-1, +1]). Geometry unchanged from LM.2 contract §P.4.
- Drift speed and dance amplitude are functions of `f.arousal` (small at low arousal, wider at high).
- **Agents drive cell *intensity*, not cell *colour*** (D.4). The agent's RGB colour fields stay on the GPU struct for ABI continuity with future LM.5 per-stem hue affinity work, but are not consumed by the LM.3 sceneMaterial.

This produces the new D.4 character: every cell carries its own colour from the procedural palette, the four agents brighten cells overlapped by their lobes, and the whole field of cells reads as a unified panel of colour responding to the music — not four separate per-stem zones.

---

## 5. Reference and anti-reference

### 5.1 Hero references

- **`04_specular_pattern_glass_closeup.jpg`** — close-up of hammered pattern glass; carries the cell + frost detail cascade (macro / meso / micro).
- **`05_lighting_pattern_glass_dual_color.jpg`** — pattern glass with strong saturated multi-colour backlight; carries the **vivid per-cell colour identity** that is the LM.3+ visual goal. **This is the dominant fidelity reference for the energetic-dance design intent.**

**Traits to extract** (per Gate 1 of Preset_Development_Protocol.md):

- **Macro:** ~50 hex-biased Voronoi cells across, irregular hexagons not perfect hexagons.
- **Meso:** each cell appears as a raised dimple (per-cell shading relief; the panel SDF stays flat — the dimpled appearance comes from `mat_pattern_glass` V.3's height-gradient normal perturbation, not from SDF deformation); sharp ridge between cells; thin dark seam between cell edges.
- **Micro:** in-cell frosted bumpy texture; sub-cell-scale specular sparkle from random oriented micro-facets.
- **Colour:** **vivid per-cell hue, varying widely across the panel** (orange next to red next to blue next to teal); not a smooth gradient. Saturated channels — primaries and near-primaries, not pastels.
- **Material:** dielectric, near-white albedo, moderate roughness, high transmissive emission character (bright cells glow, not just reflect).
- **Motion:** N/A in the reference (still photos). For the preset: cell layout is static; cell *colour* cycles continuously through the procedural palette; agents move on the beat; pattern bursts at LM.4 add high-frequency colour bursts on drum onsets.
- **Audio-reactive (this preset):** every cell carries its own evolving colour driven by `accumulated_audio_time` + per-cell hash + mood; agents brighten cells in their lobes; pattern bursts (LM.4) inject extra brightness on beats. The panel is alive with colour at all times when music is playing.
- **Failure modes to preflight against:**
  - **Pastel / muted output** — *the LM.1 / LM.2 failure mode*. Fix: drop the cream baseline (D.4 / E.3), use procedural palette directly. **Muted has no place in Phosphene** (CLAUDE.md project-level rule).
  - **Smooth gradient blob** — *the LM.2 production failure mode*, where cells are technically quantized but adjacent cells get nearly identical colours. Fix: per-cell colour identity from `palette(cell_hash, ...)` (D.4) — adjacent cells can carry different palette positions.
  - **Cells static / unchanging** — fails the "cells change constantly" intent. Fix: per-cell hue cycling via `accumulated_audio_time × kCellHueRate` so cells visibly evolve during loud music.
  - **Stained-glass cathedral cliché** (saturated primaries in fixed iconographic symmetry). Avoid radial-symmetry pattern motifs (LM.4 patterns must be asymmetric / drifting).
  - **TV-static / film-grain glass** (per-pixel high-frequency noise that doesn't respect cell boundaries). Frost is *normal-perturbing*, not *colour-perturbing*. Frost adds specular sparkle; it does not modulate the cell's hue.
  - **Lava-lamp / plasma blob aesthetic** (continuous gradient without cell quantization). The cellular grid is the visual identity; if it ever reads as a continuous colour field, the preset has failed.
  - **Panel boundary visible in frame** (sizing math wrong, or future camera-jitter pushes corners off panel) — fix: panel half-extents `cameraTangents.xy * 1.50` per Decision G.1; LM.6 contact sheet must verify zero panel edge artifacts at 16:9 + 4:3 + 21:9 aspect ratios.
  - **Dance reads as random / not beat-locked** (cells cycle but don't pulse with the beat) — fix: agent `beat_phase01`-locked figure-8 stays co-primary; LM.4 pattern bursts on drum onsets add the visible per-beat punch.

### 5.2 Trait matrix

| Trait | Source | Implementation |
|---|---|---|
| Hex-biased Voronoi cells | ref macro | `voronoi_f1f2` at scale 30 (Decision C.2) |
| Domed cell + sharp ridge | ref meso | V.3 §4.5b height-gradient recipe |
| In-cell frost | ref micro | `fbm8(p × 80)` × 3 normal channels at amplitude 0.10 |
| Specular sparkle | ref material | Cook-Torrance with frost-perturbed normal vs. IBL |
| **Vivid per-cell colour** | **ref `05` colour** | **Per-cell `palette(cell_hash + audio_time × kCellHueRate + mood_drift)` (Decision D.4)** |
| **Saturated palette character** | **ref `05` colour** | **IQ cosine palette via V.3 `palette()`; mood shifts `(a, b, c, d)` continuously (Decision E.3)** |
| Cells changing constantly | preset intent | `accumulated_audio_time` advances faster during loud music → cell hue cycles visibly |
| Cell-quantized colour | preset role | Per-cell deterministic hash → discrete cells (Decision D.4) |
| Static panel SDF | preset role | `sceneSDF` returns same shape every frame (D-020) |
| Mood-driven palette character | preset role | Valence / arousal shift palette `(a, b, c, d)` smoothly (Decision E.3) |
| Beat-locked agent dance | preset role | `beat_phase01` figure-8 per agent (LM.2 contract §P.4) |
| Beat-triggered pattern bursts | preset role | Pattern engine `radial_ripple` on `stems.drumsBeat` (LM.4) |
| Bar-boundary pattern spawn | preset role | Pattern engine retires/spawns on `f.barPhase01` rollover (LM.4) |

### 5.3 Anti-references

- **Stained-glass cathedral imagery** (saturated primary RGB, religious-iconographic symmetry). Avoid all cross / mandala / radial-symmetry pattern presets. The pattern engine is explicitly biased toward asymmetric, off-center, drifting motifs.
- **TV-static / film-grain glass** (per-pixel high-frequency noise that doesn't respect cell boundaries). The micro-frost is *normal-perturbing*, not *colour-perturbing*. Frost adds specular sparkle; it does not modulate the cell's hue.
- **Lava lamp / plasma / blob aesthetic** (continuous gradient blobs without cell quantization). Lumen Mosaic's identity is the discrete cellular grid; if it ever reads as a continuous colour field, the preset has failed.
- **Pastel / cream-tinted output** (the LM.1 / LM.2 failure mode). The procedural palette has no cream baseline; saturation is whatever `palette()` produces (typically `b ≈ 0.4–0.6` per channel → vivid by construction). M7 review at every LM.3+ boundary must confirm "no pastel" + "no cream-haze".
- **Reference-rejection check at LM review boundaries:** Matt must explicitly confirm "no stained-glass cathedral cliché", "no continuous-blob aesthetic", and **"no pastel/muted palette"** at every contact-sheet review.

---

## 6. Phased plan (Phase LM)

Each increment lands in `ENGINEERING_PLAN.md` once approved. Done-when criteria and verify commands per increment are in `LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md`.

| Increment | Scope | Status |
|---|---|---|
| LM.0 | Gate audit; extend `RenderPipeline` with `directPresetFragmentBuffer3` (Decision F.1) | ✅ landed |
| LM.1 | Minimum viable preset: glass panel + pattern_glass material + static backlight color. No audio. | ✅ landed |
| LM.2 | 4 audio-driven light agents + mood-coupled hue shift + D-019 silence fallback. **Result rejected at LM.2 production review (2026-05-09): output too muted, cells invisible, design intent wrong.** Slot-8 binding + agent dance proven correct; visual ships at LM.3. | ⚠ scaffolding |
| LM.3 | **Substantive look ships here.** Per-cell colour identity from `palette()` keyed on cell hash + audio time + mood (D.4). Procedural palette via IQ cosine, no cream baseline (E.3). Mood-driven palette parameter shift. Cells visibly cycle through palette during energetic music; rest at silence. | ⏳ next |
| LM.4 | Pattern engine v1: `idle`, `radial_ripple`, `sweep`. Bar-boundary triggering via `f.barPhase01`. Drum-onset ripples — patterns inject extra per-cell brightness without overriding palette colour (so a ripple takes the colour of the cells it crosses). | ⏳ |
| LM.5 | Pattern engine v2: `cluster_burst`, `breathing`, `noise_drift`. **Optional**: per-stem hue affinity (cells brighten preferentially for "their" stem based on hue similarity). Add only if LM.3 / LM.4 review judges the unified-palette feel too undifferentiated stem-wise. | ⏳ |
| LM.6 | Fidelity polish: micro-frost tuning, specular sparkle calibration, cell-density A/B against ref `04`, palette parameter A/B against ref `05`. | ⏳ |
| LM.7 | Beat accent layer: bar-line shimmer, vocal-hotspot sub-pattern. (Drum-onset ripples land at LM.4; LM.7 adds the secondary accent layers.) | ⏳ |
| ~~LM.8~~ | ~~Mood-quadrant palette authoring (Decision E.2 promotion).~~ **Retired 2026-05-09**: E.2 rejected on monotony grounds (Matt 2026-05-09); procedural palette via E.3 ships at LM.3. | ⊘ retired |
| LM.9 | Certification: rubric 10/15 pass, performance verification, golden hash registration, `certified: true`. | ⏳ |

**Total estimate: 9 sessions** (down from 13: LM.8 retired; LM.3 absorbs the palette-bank work via the procedural path; LM.5 keeps the per-stem hue affinity as an optional sub-step that doesn't add a session of its own).

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

### 7.5 Acceptance against the reference image (LM.3 revised)

A 30-second clip of the preset, captured at HV-HA mood with steady moderate energy, should produce a frame where:

1. Cells are visibly hex-biased and tessellated, with consistent cell density (~50 cells across the visible frame).
2. **Cells carry visibly distinct colours.** Adjacent cells can differ markedly in hue; the panel as a whole spans the palette range. No "smooth gradient" reading.
3. **The palette is vivid, not pastel.** Dominant cells read as saturated primaries / near-primaries; no cream or grey-haze.
4. Specular sparkle is visible within at least 30% of cells in the bright regions.
5. The cell-edge ridges produce a visible inter-cell network of dark seams.
6. No cell exhibits gradient colour across its area (Decision D.4 cell quantization preserved).
7. **Cells visibly cycle through the palette during 3 seconds of energetic playback.** Stop the clip at 0 s and at 3 s; cell colours must visibly differ.
8. Light-agent dance is visible: bright regions of the panel (where agent lobes overlap cells) shift across the panel in time with the beat.
9. Beat hits produce visible per-cell brightness pulses (LM.4+; not required at LM.3).

**Matt M7 review** at LM.3 (first energetic-design check), LM.6 (polish gate), LM.9 (certification) against this list and against ref `04` (cell detail) + ref `05` (palette character) side-by-side via harness contact sheet.

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

**Original sign-off (LM.0 era).** Matt confirmed Decisions A.1, B.1, C.2, D.1, E.1, F.1, G.1, H.1 before LM.0 / LM.1 / LM.2 landed. Decisions A, B, C, F, G, H stand unchanged.

**LM.3 sign-off (this revision).** The following pivots require fresh confirmation before LM.3 lands:

- ✅ **Aesthetic role**: energetic, not meditative (Matt 2026-05-09).
- ✅ **Decision D rejected → D.4 adopted**: per-cell colour identity from `palette()` keyed on cell hash + audio time + mood. Stems drive intensity, not hue. (Matt 2026-05-09 + design rewrite recommendation.)
- ✅ **Decision E rejected (E.1 muted, E.2 monotonous) → E.3 adopted**: procedural palette via V.3 IQ cosine `palette()`; mood shifts `(a, b, c, d)` continuously; no authored palette banks. (Matt 2026-05-09.)
- ✅ **Cells change constantly**: tied to `accumulated_audio_time × kCellHueRate`; first-pass `kCellHueRate = 0.05`, M7-tuned in LM.3 review. (Matt 2026-05-09.)
- ✅ **Per-stem hue affinity**: deferred to LM.5 review — LM.3 ships with stems driving intensity uniformly. (Matt 2026-05-09.)
- ✅ **Silence**: cells hold their hue (rest), no cream / grey-haze fallback. (Matt 2026-05-09.)
- ✅ **CLAUDE.md project-level "muted has no place in Phosphene" rule** to be added.

**LM.3 implementation gates** (sequence after design sign-off):

1. **Companion contract revised** to match D.4 / E.3 / palette parameter slots in `LumenPatternState`.
2. **`[LM.3] Per-cell palette + procedural mood`** lands as the substantive rebuild.
3. **M7 review on real session** — `kCellHueRate` tuned, palette parameters verified vivid.
4. Iterate or move to LM.4.

---

## 11. Revision history

- **2026-05-09 (this revision)** — design pivot after LM.2 production review. "Meditative co-performer" framing replaced with "energetic dance partner". Decision D.1 retired (cell-quantized agent sample produced gradient blob, no visible cells); D.4 adopted (per-cell colour identity from `palette()` keyed on cell hash). Decision E.1 (cream-baseline mood tint) and E.2 (4 authored palette banks) retired; E.3 adopted (procedural palette via V.3 IQ cosine, mood shifts `(a, b, c, d)` continuously). Cream baseline retired across the board. LM.8 retired; the substantive look ships at LM.3. Acceptance criteria §7.5 rewritten around per-cell colour identity + vivid palette. Reference `05_lighting_pattern_glass_dual_color.jpg` promoted to dominant fidelity reference.
- **2026-05-08 (LM.0 era)** — original document, with Matt's Decision A.1 / B.1 / C.2 / D.1 / E.1 / F.1 / G.1 / H.1 confirmed. LM.0–LM.2 implemented under this version.
