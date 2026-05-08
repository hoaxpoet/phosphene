# Arachne 3D Rendering Design Doc

**Status:** Draft. Pending Matt sign-off on the open decisions in §3 before any code lands.

**Companion docs:**
- [`ARACHNE_V8_DESIGN.md`](ARACHNE_V8_DESIGN.md) — authoritative aesthetic and behavioural spec (three pillars, build cycle, audio coupling). **Stays canonical.** This doc only changes the *implementation strategy*.
- [`SHADER_CRAFT.md`](SHADER_CRAFT.md) — preset authoring handbook, fidelity rubric, material cookbook.
- [`ENGINEERING_PLAN.md`](ENGINEERING_PLAN.md) — increment ledger; the V.8.x increments below land here once approved.

---

## 1. Why this doc exists

The V.7.7B → V.7.7D increments executed cleanly: WORLD pillar offscreen texture (V.7.7B), §5.8 Snell's-law refractive dewdrops (V.7.7C), 3D SDF spider + chitin + listening pose + 12 Hz vibration (V.7.7D). Every increment passed its rubric. None visibly closed the gap to the macro-photograph reference set (refs 01, 03, 04, 05, 06, 07, 08, 11, 12, 13).

The diagnosis is structural, not tactical:

- **Failed Approach #49** — tuning constants on a renderer that is structurally missing the references' compositing layers. We added some compositing layers in V.7.7B/C/D but still render in a 2D fragment shader simulating 3D in spots, not a 3D scene with real depth, lighting, and refraction.
- **The references are macro photographs.** Their visual signature involves real depth-of-field, real refraction with chromatic dispersion, real subsurface scattering on silk fibers, real volumetric atmosphere with light shafts hitting actual particulate. None of these are reachable via clever fragment-shader composition; they require a 3D scene representation the renderer can sample with a camera.
- **No visual feedback loop on the LLM side.** Tactical increments under that constraint converge on local-optima — they each close a small named gap while the gap-to-reference stays large. The way to break out is structural: change the rendering tech, not the recipes.

This doc proposes moving Arachne onto Phosphene's existing **`ray_march` render path** (used by VolumetricLithograph, KineticSculpture, GlassBrutalist) — a 3-pass deferred Cook-Torrance PBR pipeline with G-buffer, lighting, IBL, SSGI, and a real 3D camera. The infrastructure exists; this is a port, not a build-out.

### 1.1 Visual target reframe (canonical)

> The references define the aesthetic family — backlit macro nature photography, dewy webs, atmospheric forest, biological asymmetry, droplets as primary visual carrier. They are NOT pixel-match targets. The bar is: a frame from Arachne3D should look like it belongs in the same visual conversation as ref 01, not look identical to ref 01. A viewer seeing both side by side should classify them as 'same world, different rendering' — not 'photograph next to clipart.' Real-time constraints (Tier 1 14ms / Tier 2 16ms p95) are inviolable. If a fidelity feature cannot be achieved in budget, document the gap and pick the nearest achievable approximation.

This reframe replaces any prior implicit "match the photographs" contract throughout the doc set, including earlier drafts of `ARACHNE_V8_DESIGN.md` and `docs/VISUAL_REFERENCES/arachne/Arachne_Rendering_Architecture_Contract.md`. It is **preset-system-wide**, not Arachne-specific — the same principle governs V.9 FerrofluidOcean, V.10 FractalTree, V.11 VolumetricLithograph, and V.12 GlassBrutalist + KineticSculpture. The reference set is the aesthetic family the rendering must join; pixel-fidelity is an explicit non-goal.

The cert rubric still requires Matt's eyeball on a contact sheet against references (M7). The reframe shifts what M7 *means* — "does this frame belong in the same visual conversation?" not "does this frame match the photograph?".

---

## 2. Constraints (non-negotiable)

These constraints frame every open decision in §3.

1. **Performance ceiling — Tier 1: 14 ms / Tier 2: 16 ms** (CLAUDE.md, FrameBudgetManager). For reference: VolumetricLithograph runs ~2 ms at Tier 2; KineticSculpture ~5.5 ms; GlassBrutalist not measured recently. A complex Arachne scene (4 webs × ~17 spokes × ~5 spiral revolutions = 340+ silk strand SDFs per pixel + drops + spider + forest geometry + DoF) is *not* automatically inside that budget. The QualityLevel ladder (full → noSSGI → noBloom → reducedRayMarch → reducedParticles → reducedMesh) gives us four step-downs, but Arachne shouldn't *require* a step-down to hit budget on Tier 2.

2. **The V8 design spec is canonical.** Three pillars (WORLD / WEB / SPIDER), 60-second compressed build cycle (frame → radials → INWARD chord-segment spiral), §5.8 refractive drops, §6 spider anatomy, §8.2 vibration. The 3D rewrite changes *how* these render, not *what* they look like. References stay the target.

3. **Audio data hierarchy stays.** D-026 deviation primitives drive everything. Continuous bass/mid envelope is the primary visual driver; beat onsets are accent only. The PresetAcceptance "beat is accent only" invariant must continue to pass.

4. **`ArachneSpiderGPU` stays at 80 bytes.** V.7.7B GPU contract — slot-7 buffer allocation. The CPU-side listening-pose lift mechanism (V.7.7D) carries over unchanged.

5. **Spider remains rare.** The trigger logic (sustained low-attack-ratio sub-bass + 5-min cooldown) is unchanged. The 3D rewrite affects the spider's *rendering*, not its *spawning*.

6. **No new external dependencies.** Stays on Metal + Accelerate + MPSGraph. No CoreML, no third-party rendering libs.

7. **I (Claude) cannot see rendered output.** Every visual judgment must come from Matt. The 3D rewrite does NOT fix this — it just gives us a different fidelity tier to optimize against. Matt-driven contact-sheet review at each phase boundary is mandatory.

---

## 3. Open decisions — these need answers before any code

Each decision below has my recommendation, but **Matt picks**. Decisions are independent unless flagged.

### Decision A — Replace in place, or parallel preset?

**Option A.1 — Rewrite Arachne in place.** The existing `Arachne.metal` and `Arachne.json` get replaced. `passes` changes from `["staged"]` to `["ray_march", "post_process"]`. Every Arachne golden hash is regenerated wholesale. The CPU `ArachneState` keeps its public API (web pool, spider trigger, listening pose) but its internal state representation may change (3D positions instead of clip-space). Existing untracked work survives because it's in the V8 spec doc, not in the shader.

**Option A.2 — Build "Arachne 3D" as a new preset.** New `Arachne3D.metal` + `Arachne3D.json`. The current Arachne stays at the V.7.7D state. Both ship in the catalog during the build phase. When Arachne 3D reaches certification, the original Arachne is retired (deleted, not deprecated).

**Decision: A.2 (parallel preset).** Build `Arachne3D` as a new preset alongside the existing Arachne. New `Arachne3D.metal` + `Arachne3D.json`. Both ship in the catalog through V.8.5. At V.8.6 (cert pass) the original Arachne is retired in a single commit — file deletion, not deprecation, since the V8 design intent is replacement, not coexistence.

**Why A.2 over A.1.** The doubled-maintenance argument that motivated the A.1 recommendation only holds if both presets receive parallel changes during the build phase. They will not: the existing Arachne is frozen at V.7.7D and receives no further design work; Arachne3D is the active workstream. Maintenance during V.8.1–V.8.5 is therefore single-track, not doubled. The benefit is real: A.2 keeps a known-rendering reference visible in the catalog while V.8.x is in flight, makes A/B contact-sheet review trivial (render both presets against the same fixture), and gives a clean rollback if a V.8.x increment regresses without warning. The cleaner-ledger argument for A.1 is a wash — every Arachne3D increment cites both presets in its closeout regardless.

**Parallel-preset feasibility — what changes for V.8.1.** `PresetLoader` (`Sources/Presets/PresetLoader.swift`) auto-discovers `.metal` files in `Sources/Presets/Shaders/`; `Arachne3D.metal` lands alongside `Arachne.metal` with no loader change. The two JSON sidecars MUST use distinct display names through V.8.5 — `name: "Arachne"` and `name: "Arachne 3D"` — so the dashboard preset badge, debug overlay preset string, golden-hash dictionary keys, and Matt's "what am I looking at right now?" are unambiguous. At V.8.6 retirement, the V.8.6 commit deletes `Arachne.metal` + `Arachne.json` and renames `Arachne 3D` → `Arachne` in `Arachne3D.json` so the catalog returns to a single Arachne preset with the V.7.7D identity retired and the V.8.x identity adopting the canonical name. The file-level rename happens later (post-cert) only if it earns its line-noise.

**`ArachneState` reuse, not Arachne3DState.** The existing CPU state machinery (web pool stages + beat-driven spawn cadence + spider trigger + listening pose + 5-min cooldown) is rendering-agnostic — it computes what should exist in the scene and writes a GPU buffer; it does not care whether the shader interprets that buffer as 2D fragment composition or as 3D scene SDFs. Both presets bind the *same* `ArachneState` instance through their respective slot-6/7 fragment buffers. Arachne3D's only state-side delta is the 3D position extension to `WebGPU` (per Decision D — `hubZ` Float added; layout audit in §4.3 to confirm the 80-byte slot has room) and the 3D spider position (per Decision §4.3 — `spiderPos` becomes 3D). Both deltas are purely additive; the existing Arachne preset still reads the same buffer and ignores the new fields. **No `Arachne3DState` is required.** This avoids the parallel-state-world failure mode (Failed Approach #16, #55) by construction.

**Orchestrator behaviour.** `Arachne3D.json` ships with `certified: false` and the **default (full) `rubric_profile`**. `DefaultPresetScorer` already excludes uncertified presets from automatic scheduling (D-067 / V.6 — `excludedReason: "uncertified"`). No new flag is required. The preset is reachable only via the developer preset-cycle keyboard shortcut (`⌘[` / `⌘]`) and via debug forced-selection paths — exactly the path Spectral Cartograph uses today. Matt can A/B against the original Arachne by cycling between the two manually. At V.8.6 cert, `certified: true` flips, the original Arachne file is deleted, and Arachne3D enters automatic scheduling.

**Test fixture impact.** Existing Arachne golden hashes in `PresetRegressionTests` stay locked at V.7.7D values (`steady`/`quiet` `0xC6168E8F87868C80`, `beatHeavy` `0xC6168E87878E8480`; spider `0x461E2E1F07830C00`). `Arachne3D` golden hashes are net-new — added per V.8.1 increment, regenerated as the rendering evolves through V.8.5. At V.8.6 retirement, the original Arachne hashes are removed alongside the file deletion; the Arachne3D hashes retain their values (no rebake required) but the `goldenPresetHashes` dictionary key is renamed to `"Arachne"` to match the JSON display-name rename.

**Carry-over for §3 Decisions B–G.** Decision A.2's flip to parallel preset does not invalidate the recommendations for B (sampled WORLD backdrop, see §3.B below for the screen-space-refraction artifact), C (screen-space refraction), D.3 (hybrid SDF), E.1 (static camera through V.8.3), F.3 (procedural directional + IBL), or G.1 (3D first, build cycle later). Those decisions describe *what Arachne3D renders*; A.2 describes *how it ships alongside Arachne during the build phase*.

---

### Decision B — Forest as real geometry, or sampled backdrop?

**Option B.1 — Forest as real geometry.** Distant tree silhouettes become 3D capsule/cylinder SDFs at 5–10 m depth. Mid-distance trees have bark detail. The forest atmosphere uses the existing `vol_*` (volumetric) and `ls_*` (light shafts) utility trees. Light shafts hit real geometry. Drop refraction picks up real distant geometry through the lens. Volumetric fog has real depth.

**Option B.2 — Sampled backdrop.** Keep V.7.7B's `arachne_world_fragment` rendering the WORLD pillar to an offscreen texture; the new ray-march pass samples that texture as the sky/distant pixel value. Foreground 3D web + drops + spider sit in front of it. Drops refracting through the forest read it from the texture (current behaviour).

**Trade-off:** B.1 is more flexible (parallax, real shafts, real refraction depth) and visually richer, but expensive — a forest with 20–40 trunk SDFs at far distance plus volumetric fog plus light shafts is 4–8 ms on its own at Tier 2. B.2 is cheap (~0 marginal cost beyond the existing WORLD pass) but loses parallax and real depth in drop refraction.

**Decision: B.2 (sampled WORLD backdrop) for V.8.1 through V.8.5.** Keep V.7.7B's `arachne_world_fragment` as the backdrop pass; port the foreground (silk + drops + spider) to ray-march; sample `arachneWorldTex` at miss-ray pixels and at drop-refraction sample points. The references' compositional weight is on the foreground, not the background — sampled backdrop is the right cost/fidelity ratio for the build phase. The cinematic camera (Decision E.3) still moves through the foreground 3D scene; the WORLD texture is a billboard-style backdrop that does not parallax with camera motion. This is an accepted limitation, not an oversight — see Decision C for the related drop-refraction artifact and the V.8.7 deferral.

**B.1 (forest as real geometry) is explicitly deferred past V.8.6.** Promotion to real 3D forest geometry is a future increment if (and only if) the sampled-backdrop fidelity floor proves insufficient at cert review. It is NOT scheduled into V.8.x.

---

### Decision C — Refraction strategy through drops

**Option C.1 — Screen-space refraction.** Drops compute their normal in 3D, refract the view ray, then sample the lit-scene texture (or WORLD texture) at an offset UV. Cheap (one texture sample per drop pixel). Loses detail at drop edges where the refracted ray would exit the screen.

**Option C.2 — BVH ray tracing.** Drops compute the refracted ray in 3D and trace it through the BVH (Phosphene's `RayIntersector` exists). The hit point's albedo/lighting is computed there. Expensive but accurate — real refraction through real geometry, including chromatic dispersion if we trace separate rays per RGB channel.

**Option C.3 — Hybrid: screen-space refraction with depth.** Use the G-buffer's depth + albedo. The refracted ray steps through the depth field looking for a hit. Cheaper than BVH, more accurate than screen-space at edges. Used by Unreal screen-space refraction.

**Decision: C.1 (screen-space) for V.8.1–V.8.5.** Drops compute their normal in 3D, refract the view ray, sample `arachneWorldTex` at the offset UV. Cheap and good enough for the foreground-foliage-context phase. C.3 (depth-aware screen-space) is on the table for a hypothetical V.8.7 polish-up only if cert review identifies drop refraction as the gating fidelity issue. C.2 (BVH refraction) is **explicitly deferred past V.8.7** — full BVH refraction is overkill at 60fps and would require BVH rebuilds every frame as drops move.

**Known artifact: screen-edge refraction divergence.** Screen-space refraction samples the WORLD texture at `uv + refractionOffset`, where `refractionOffset` is the 3D-refracted ray's screen-space projection. For drops near the visible web's edge, the refracted ray exits the screen-space WORLD texture's valid region — the sample lands in *what is screen-behind*, not *what is world-behind*. A drop on the left edge of the visible web refracts to whatever happens to be slightly outside the visible frame (or to the same pixel's WORLD sample if clamped), not to the geometrically correct distant forest fragment behind that drop in 3D. This artifact manifests reliably in the **outermost ~10 % of the frame** (drops within ~50 px of any screen edge at 1080p), where the refraction offset can push the sample UV outside [0, 1]. Drops in the central ~80 % of the frame refract correctly to within human-eye accuracy.

V.8.x accepts this artifact as the **fidelity floor for the foreground-foliage-context phase**. Real macro photography drops are physical lenses; screen-space refraction gets you ~80 % of the way there at <0.1 ms per drop pixel. The remaining 20 % requires either (a) BVH refraction with per-drop ray traces (V.8.7 territory at earliest, more likely never), or (b) accepting the artifact and counting on the human eye's tolerance for edge-of-frame imperfection. Macro photography itself blurs frame edges via shallow DoF — V.8.4's depth-of-field pass naturally hides the worst of this artifact at the cost of explicit acknowledgement.

**Cert review acknowledgement.** M7 contact-sheet review against refs explicitly notes screen-edge drops as out-of-scope-for-cert; visual-conversation matching (per the §1.1 reframe) does not require screen-edge drops to read as physically correct.

---

### Decision D — SDF representation of webs

**Option D.1 — Fully procedural.** The fragment shader unrolls all strands from the web's `rng_seed`. Spoke angles, spiral chord segments, drop positions all derived deterministically. CPU buffer is just the web pool state (hub, stage, opacity, seed) — same as V.7.7D. Cheap and fixed-cost regardless of web complexity.

**Option D.2 — CPU buffer of strand segments.** CPU keeps a list of strand segments (start, end, thickness) per web. Shader loops over the list. Flexible — biology-correct chord-segment spiral lands naturally. Cost grows with strand count.

**Option D.3 — Hybrid (current V.7.7D approach).** CPU buffer carries web *parameters* (hub 3D, radius, rotation, seed, stage); shader unrolls strands procedurally from those. Adds 3D position to the CPU state.

**Recommendation: D.3 (hybrid).** Matches V.7.7D's existing pattern — minimal disruption to `ArachneState`, predictable shader cost, biology preserved via the chord-segment math living in the shader. The CPU `ArachneState` web pool's clip-space hub coordinates extend to 3D (add a `hubZ: Float`); strand endpoints stay procedural.

---

### Decision E — Camera

**Option E.1 — Static camera.** Fixed position, fixed look-at, fixed FoV. Predictable. No motion sickness risk. Loses "spider in flight" cinematic feel.

**Option E.2 — Slow audio-coupled dolly.** Camera dollies forward at a constant slow rate (like VolumetricLithograph's 1.8 u/s) with audio-coupled hue/exposure shifts. The web stays roughly framed but parallax shifts as camera moves.

**Option E.3 — Cinematic build-cycle camera.** Camera frames the *currently-building web* per the V.7.6.2 / V.8 build cycle: pulls back as frame is laid down, pushes in as radials extend, dwells on hub during spiral wind-in, slow rotation around the finished web before evicting. Coupled to the foreground build state machine.

**Recommendation: E.1 (static) for V.8.1–V.8.3, E.3 (cinematic build-cycle) for V.8.5+.** Static camera de-risks the rendering pipeline ports. Once silk + drops + spider are landing visually, the cinematic camera is a polish pass that pairs with V.7.7C.2 / V.7.8's foreground build state machine. E.2 is a worse middle ground — no narrative hook.

---

### Decision F — Lighting environment

**Option F.1 — Procedural directional light + procedural IBL.** Hard-code the warm-key cool-fill convention (`kLightCol`, `kAmbCol`) from V.7.7D as a directional light. Skip IBL for Arachne — environment is dim forest, ambient is just `kAmbCol × 0.15`.

**Option F.2 — Forest-tinted IBL cubemap.** Generate a cubemap that captures the V.7.7B WORLD palette (mood-tinted forest atmosphere) into the 6 cube faces. The existing `IBLManager` can derive irradiance + prefiltered env maps from it. Real PBR with proper environment lighting on silk + chitin.

**Option F.3 — Both.** Directional key light for the warm punch (silk highlights, spider catchlights), IBL for the soft ambient.

**Recommendation: F.3 (both).** It's cheap — IBL is precomputed at preset load. The forest cubemap is generated once from the V.7.7B WORLD palette state. The directional light gives us the V.7.7D warm rim/spec character. Together they get us photographic-style lighting that no amount of fragment-shader hand-tuning will reach.

---

### Decision G — Build-state machine integration

**Option G.1 — Land 3D rendering first; integrate build cycle later.** V.8.1–V.8.5 cover the ray-march port assuming the existing V.7.5-style web pool (4 webs, beat-driven spawn, stage progression). The single-foreground build cycle (V.7.7C.2 / V.7.8) lands afterward as a separate workstream.

**Option G.2 — Land build cycle first, then 3D.** V.7.7C.2 / V.7.8 lands the foreground build state machine on the current 2D fragment shader. Then V.8.x ports to 3D.

**Option G.3 — Combined rewrite.** A single Phase replaces the rendering AND the build cycle simultaneously.

**Recommendation: G.1 (3D first).** The build cycle is a behaviour change; the 3D rewrite is a rendering change. Doing them sequentially gives us two clean cert boundaries instead of one massive one. The current 4-web pool gives V.8.x enough material to hit visual targets; the build cycle is the final cert pass before V.7.10. G.3 is the worst option — too much risk concentrated in one Phase.

---

## 4. Proposed architecture (assumes B.2, C.1, D.3, E.1, F.3, G.1)

### 4.1 Render passes

`Arachne.json` `passes` → `["ray_march", "post_process"]` (drop `["staged"]`).

The `ray_march` pass is Phosphene's existing 3-pass deferred:
1. **G-buffer** — depth, normal, material ID, albedo. Per-pixel ray march into `sceneSDF`.
2. **Lighting** — Cook-Torrance BRDF + IBL ambient + SSGI. Reads G-buffer, writes lit RGB.
3. **Composite** — tone-map + final color.

`post_process` adds bloom (warm fresnel highlights + drop catchlights bloom naturally) and ACES. **Future**: depth-of-field added to `PostProcessChain` as a new sub-pass (V.8.4 or later); not in the existing infrastructure today.

The V.7.7B staged WORLD pass stays — it writes `arachneWorldTex` as a sampled backdrop the ray-march scene reads at miss-ray pixels and at drop-refraction sample points. (Or: WORLD becomes Pass 0 of the new staged-3D layout. Implementation detail; same effect.)

### 4.2 sceneSDF skeleton

```
float sceneSDF(float3 p, FeatureVector& f, SceneUniforms& s, StemFeatures& stems) {
    // Read web pool from buffer(6); read spider from buffer(7).
    // Per web: hub 3D position, strand SDFs procedurally unrolled from seed,
    //          drop SDFs at chord-segment intersection points.
    // Spider: existing V.7.7D sd_spider_combined adapted for sceneSDF dispatch.
    // Forest: SAMPLED — handled at miss-ray time, not in sceneSDF.
    float silk     = sd_arachne_silk_pool(p, webs);
    float drops    = sd_arachne_drops_pool(p, webs);
    float spiderD  = sd_arachne_spider(p, spider);
    return min(min(silk, drops), spiderD);
}

void sceneMaterial(float3 p, int matID, ...,
                   thread float3& albedo, thread float& roughness, thread float& metallic) {
    // matID 0 = silk, 1 = drop, 2 = spider body, 3 = spider eye
    // Silk: mat_silk_thread (V.3 cookbook) — Marschner-lite fiber BRDF.
    // Drop: mat_frosted_glass adapted with refractive sample — or a new mat_dewdrop.
    // Spider: §6.2 chitin recipe (V.7.7D inline form, NOT mat_chitin V.3 default blend).
    // Eye: pinpoint specular (V.7.7D recipe).
}
```

The V.2 SDF tree (`sd_capsule`, `sd_sphere`, `op_smooth_union`, `op_smooth_subtract`) is the building block. The V.3 material cookbook provides `mat_silk_thread`, `mat_chitin`, `mat_frosted_glass` — though V.7.7D established that `mat_chitin` is bypassed for the spider in favour of the §6.2 inlined recipe.

### 4.3 ArachneState changes

Stays mostly as-is. Changes:
- `WebGPU.hubX/hubY` extends with a `hubZ` (currently implicit at 0, becomes per-web depth).
- Spider position becomes 3D — `spiderPosX/Y/Z`. Existing CPU place-on-best-hub logic adapts.
- Listening-pose tip lift (V.7.7D) — stays clip-space-Y-relative for now; revisit in V.8.5 if cinematic camera needs 3D handling.
- Web pool stages, spawn cadence, spider trigger, 5-min cooldown — unchanged.

### 4.4 Performance budget — honest re-estimate (Tier 1 + Tier 2)

The first version of this table estimated 8–11 ms at Tier 2 by assuming "drops" meant 50–100 spheres per web and ignoring chromatic dispersion and depth-of-field. That estimate is wrong against the references. Refs 01 / 03 / 04 / 13 show **300–500 drops per web at chord-segment intersections** at the visual density that makes drops read as the primary fidelity carrier. Each drop covers several pixels at 1080p; each drop pixel runs at minimum one refraction texture sample, plus a fresnel rim term, plus the §6.2 specular pinpoint. Chromatic dispersion (Pushback 3 / Decision §6 below — moved into V.8.2) adds a fresnel-edge band sample. DoF (V.8.4) adds a half-res blur prepass + composite. Honest forecast at reference drop density:

#### Tier 2 (M3+) — 16 ms ceiling, expected scene at V.8.5

| Component | Expected cost (ms) | Notes |
|---|---|---|
| WORLD staged pass (sampled backdrop) | 0.3 | V.7.7B existing, unchanged. |
| G-buffer ray march — silk strands | 2.5–3.5 | 4 webs × ~17 spokes × ~12 spiral chord segments via `sd_capsule` + `op_smooth_union`. Hub guard reduces strand count for distant pixels. |
| G-buffer ray march — drops at reference density (1200–2000 total) | 3.0–4.5 | Drops are SDF spheres unioned in. Per-pixel cost dominated by `sd_sphere` instances inside each drop's screen footprint. Most pixels see 0–2 drops in their march; clustered chord-segment regions see 4–8. |
| G-buffer ray march — spider patch | 0.4–0.6 | V.7.7D-equivalent, 0.15 UV patch, 32-step adaptive. Only when triggered. |
| Lighting (Cook-Torrance + IBL ambient) | 1.5–2.5 | Standard `ray_march` path. |
| Drop refraction screen-space sampling | 0.6–1.0 | One `arachneWorldTex` sample per drop pixel. ~10–15% of screen at reference drop coverage. |
| Drop chromatic dispersion (silhouette band) | 0.2–0.3 | Single additional sample at fresnel-band-only — see Decision §6 reframe. |
| SSGI | 1.5 | Skippable via QualityLevel.noSSGI. |
| Bloom (warm-rim accumulation) | 0.5 | Existing PostProcess. |
| Depth-of-field (V.8.4+) | 0.8–1.2 | Half-res Gaussian + composite, focal plane at hub. |
| ACES composite | 0.2 | Existing. |
| **Tier 2 forecast (V.8.5 full scene, SSGI on)** | **11.5–15.6 ms** | Tight against the 16 ms ceiling. p95 lands around the **13–14 ms** mark in the typical case; p99 lands at ~15 ms with all features active. Pre-V.8.4 (no DoF, no chromatic) the forecast is **9.5–13 ms** — comfortably inside. |

**Tier 2 forecast verdict:** inside the ceiling but not by margin. p99 will brush 15 ms. SSGI is the natural first step-down via the existing `QualityLevel.noSSGI` ladder; with SSGI off the p95 drops to ~10–12 ms.

#### Tier 1 (M1/M2) — 14 ms ceiling, mitigations REQUIRED

Tier 1's per-fragment throughput is roughly 0.55–0.7× of Tier 2 across the existing presets we have measured (KineticSculpture: 5.5 ms Tier 2, ~9 ms Tier 1; VolumetricLithograph: 2.0 ms Tier 2, ~3.2 ms Tier 1). Applying that ratio to Arachne3D's Tier 2 forecast:

| Configuration | Naive Tier 1 forecast (ms) | Status |
|---|---|---|
| V.8.5 full scene (no mitigation) | 17.5–24 | **EXCEEDS 14 ms ceiling.** |
| V.8.5 with noSSGI | 15–22 | **Still over.** |

Naive forecast exceeds the ceiling. Three mitigations are committed before V.8.1 starts:

**Tier 1 mitigation #1 — `noSSGI` is the Tier 1 default at preset init**, not a step-down via the QualityLevel ladder. The ladder is for scene-time degradation (frame budget overruns); Arachne3D's Tier 1 starts in `noSSGI` configuration as a baseline. Saves ~1.5 ms.

**Tier 1 mitigation #2 — capped drop population at 150 drops per web on Tier 1** (vs reference 300–500 on Tier 2). Drops are still the primary fidelity carrier; halving the count reduces G-buffer drop cost from 3.0–4.5 ms to ~1.5–2.3 ms, and drop refraction sampling from 0.6–1.0 ms to ~0.3–0.5 ms. Visually the result reads as "fewer drops" not "wrong drops" — the per-drop fidelity (refraction + fresnel + specular + chromatic) is preserved. The cap is set in `ArachneState` per device tier, not in the shader.

**Tier 1 mitigation #3 — half-res lighting pass on Tier 1 only.** G-buffer renders at full res; the Cook-Torrance lighting + IBL pass runs at half res into a `lit_half` texture; the composite upsamples bilinearly. Saves ~0.7–1.2 ms. The visual cost is a softening of micro-specular detail on silk strands — acceptable trade given the cinematic-camera distance and DoF blur at frame edges.

With all three mitigations, Tier 1 V.8.5 forecast is **~10.5–14 ms**, p95 at ~12 ms, p99 at ~13–14 ms. Inside the ceiling with thin margin. Arachne3D ships at Tier 1 with these mitigations engaged by default.

**BVH-accelerated strand culling (`RayIntersector` exists but unused by Arachne) is NOT committed at this stage.** It's the natural V.8.7+ headroom unlock if Tier 1 still pressures the ceiling after V.8.6 cert; until then, the three mitigations above are sufficient.

**Validation gate.** This forecast is back-of-envelope. **V.8.1's first task is to instrument the minimal-end-to-end scene with `MTLCounterSet.timestampGPU` and validate the per-component budget on a real Tier 1 (M1 or M2) device + a real Tier 2 (M3) device.** If Tier 1 exceeds 14 ms p95 at V.8.1's reduced scene complexity (single web, no drops, no spider), the architecture is wrong for Tier 1 and we replan before V.8.2.

---

## 5. Phased increment plan

Six increments over an estimated 6–8 weeks (calendar, not man-hours). Each lands as its own cert review boundary; no certs ship until V.8.6. Order is firm — earlier stages prove the rendering pipeline before later stages add layers.

### V.8.1 — Minimal end-to-end 3D Arachne (SCAFFOLD)

**Goal:** Prove the rendering pipeline works. Strip down to the simplest scene that exercises every layer.

- Single web (anchor only). One hub at `(0, 0, 0)`. 12 procedurally-unrolled spokes. One spiral revolution. No drops yet. No spider yet. No build cycle.
- Forest: V.7.7B WORLD pass stays untouched as the sampled backdrop.
- Camera: static, framed on the hub. FoV ~50°.
- Material: `mat_silk_thread` on silk strands. No fancy lighting yet — directional key + flat ambient.
- Acceptance: silk renders as 3D capsules with depth (parallax visible if camera moves), backdrop sampled correctly, no perf regression beyond budget.

### V.8.2 — Drops + refraction

- Drops at chord-segment intersections of the spiral. SDF spheres with `mat_frosted_glass`-style refraction sampling the WORLD texture (decision C.1 — screen-space).
- Spec recipe: §5.8 Snell's-law adapted for 3D normals (the existing sphericalcap math is already 3D-correct in V.7.7D).
- Acceptance: drops carry visible forest fragments; specular pinpoints fire at half-vector; fresnel rim catches the directional light.

### V.8.3 — Spider in 3D

- Spider's V.7.7D `sd_spider_combined` dispatches via `sceneSDF` (replaces the V.7.7D screen-space patch). Listening-pose lift mechanism unchanged.
- Spider's chitin material via the V.7.7D §6.2 inline recipe — applied through `sceneMaterial` via per-stem PBR rather than fragment-direct lighting. Eye specular path stays identical.
- Acceptance: spider at the hub when triggered; listening pose visible; eye catchlights fire.

### V.8.4 — IBL forest cubemap + DoF

- IBL cubemap generated from V.7.7B's WORLD palette (mood-tinted) at preset init. `IBLManager` handles irradiance + prefilter as it does today for VolumetricLithograph et al.
- Depth-of-field added to `PostProcessChain` — new sub-pass, focal plane at the web hub, bokeh circle sized for ~f/4-equivalent. Background trees (forest backdrop sampled as miss rays) blur naturally.
- Acceptance: real PBR ambient on silk + chitin (subtle hue shift across surface from environment); near-frame web in sharp focus, distant forest blurred to bokeh.

### V.8.5 — Multi-web pool + cinematic camera + foreground build state machine

- Web pool extends to 4 webs in 3D (hubs at varying depths). Existing pool stage state machine drives transitions.
- Cinematic camera (Decision E.3) — slow dolly + rotation framed by the currently-building web. Pairs with the V.7.7C.2 / V.7.8 build state machine.
- §8.2 12 Hz vibration adapts to 3D — currently the V.7.7D vibration is fragment-space UV jitter; in the ray-march world it becomes 3D position jitter on web hubs (with edge-amplified amplitude per §8.2 anchor-vs-tip physics).
- Acceptance: full V8 design behaviour reproduced in 3D — 60-second build cycle, vibration on bass, listening pose on sustained sub-bass, drop refraction reading the forest.

### V.8.6 — Polish + cert

- M7 contact-sheet review against refs 01, 03, 04, 05, 06, 07, 08, 11, 12, 13.
- Performance pass — Tier 1 budget validation, QualityLevel ladder validation.
- Anti-references checked (ref 10 neon glow — chitin blend ≤ 0.20; bullseye-degenerate spirals — chord-segment math validated; etc.).
- Per `SHADER_CRAFT.md §12`: rubric must score ≥ 10/15 with all mandatory items passing. `Arachne.json` `certified: true` flips ONLY when M7 passes Matt's eyeball.

---

## 6. What we're NOT doing — and what moved IN

### 6.1 Moved IN: chromatic dispersion lands in V.8.2 (not deferred)

The original draft of this section listed chromatic dispersion as deferred past V.8.6. That was wrong. Refs 03, 04, and 13 all show visible chromatic edges on dewdrops — it is part of how real water reads as photographed-not-rendered, and dropping it puts a visible ceiling on the drops-as-primary-fidelity-carrier promise the V8 design spec is built around.

**Cost analysis at V.8.5 reference drop coverage (~12% of frame as drop pixels at Tier 2):**

| Strategy | Cost (Tier 2, ms) | Visual quality |
|---|---|---|
| Three full-channel refraction samples at offset IORs (R: 1.31, G: 1.33, B: 1.35) | 1.5–2.0 | Physically-faithful chromatic separation across the entire drop. |
| Single full-channel sample + fresnel-edge band offset (G centred, R/B offset only at high `(1 − N·V)`) | 0.2–0.3 | Chromatic edge band visible at drop silhouettes only; centre of drop reads as flat refraction. Matches macro-photography appearance because real chromatic dispersion is most visible at the lens silhouette anyway. |

**Decision: silhouette-band approach in V.8.2.** Cost (~0.25 ms at Tier 2, ~0.4 ms at Tier 1) sits comfortably inside the §4.4 budget. Visually it reproduces the chromatic signature the references show without paying for triple-sampling the entire drop interior — the centre of a real macro-photo dewdrop does NOT show visible RGB separation; only the rim-band does. The cheaper path is also the more accurate path for the reference set.

V.8.2 (drops + refraction) ships chromatic dispersion as part of the same increment. The §4.4 forecast already accounts for it.

### 6.2 Still NOT doing

- **Not building new rendering tech.** No new pass types, no new SDF utilities (the V.2 tree is sufficient), no new material recipes (V.3 is sufficient + the V.7.7D §6.2 inline). What's new is *Arachne3D using existing tech that other presets already use.*
- **Not changing audio wiring.** D-026 deviation primitives, V.7.7D listening-pose state machine, spider trigger, vibration audio coupling — all preserved.
- **Not replacing the V.7.7B WORLD pass.** It stays as the sampled backdrop until/unless Decision B is revisited (B.1 — real geometry — is deferred past V.8.7 per Decision B above).
- **Not BVH-traced refraction (Decision C.2)** — explicitly deferred past V.8.7. The known screen-edge artifact (Decision C above) is the accepted fidelity floor.
- **Not real-time path tracing, not caustics through drops, not multiple-scattering volumetrics.** None of these are reachable inside the Tier 1 / Tier 2 budgets at the scene complexity V.8.x targets, and the references' visual signature does not require them — chromatic dispersion is the only "RTX-flavoured" feature that earns its way in, and only because the silhouette-band approximation is cheap.
- **Not retiring V.7.5/V.7.7-era assets first.** The V.7.7D listening-pose code stays, the spider trigger stays, the V.2 SDF helpers stay. The original Arachne preset stays in the catalog through V.8.5 (Decision A.2). We're rendering a *new preset* alongside; we are not rewriting the existing one in place.

---

## 7. Open risks

1. **Performance.** §4.4's 8–11 ms estimate is back-of-envelope. If the actual G-buffer pass blows the budget, mitigations are: BVH-accelerated strand culling (`RayIntersector` exists, just not used by Arachne today), tighter screen-space patch around web hubs, half-res lighting. Worst case: Tier 1 falls off the budget and Arachne becomes Tier-2-only (uncertified on M1/M2). Decide at V.8.1 profiling.
2. **Ray-march scenes have a recognizable look.** Soft edges, slightly plasticky surfaces, lighting that reads as synthetic. The references are real photographs of real water and silk. V.8.x narrows the gap; it won't close it. If the gap to references is still unacceptable after V.8.6, options are: (a) accept the 3D-rendered aesthetic as the achievable target and adjust the references, or (b) invest in offline-quality rendering tech (path tracing per drop, fiber-level silk via `mat_silk_thread` Marschner with anisotropic scattering, real volumetric atmosphere with multiple-scattering). (b) is a separate Phase, not part of V.8.
3. **The visual-feedback-loop problem persists.** I still can't see output. Every visual judgment must come from Matt. Each phase boundary needs a contact-sheet review session before the next phase starts. V.8.x will not converge if we fall back into "execute prompt → ✅ → next prompt" rhythm without contact-sheet review between phases.
4. **`ArachneState` 3D refactor risk.** Adding a `hubZ` field to `WebGPU` changes its size from 80 → 96 bytes (or carefully reserves padding). The existing `WebGPU.row4` mood data + `padding` slots may have room. Layout audit before V.8.1.
5. **Existing tests need wholesale regeneration.** Every Arachne golden hash, every visual harness baseline, every preset acceptance fixture will be invalidated by the rendering tech change. This is expected, not a regression — golden hashes regenerate as part of V.8.1.
6. **Spider mechanism collision.** The V.7.7D listening-pose lift writes clip-space tip Y deltas. In a 3D world that logic doesn't make sense — the lift wants to be in body-local +z. The mechanism translates cleanly (lift the body-local kneeL.z directly instead of hacking tip Y), but it's a real change; not a one-line port.

---

## 7.3 Visual feedback loop

Claude Code cannot see rendered output. Past Arachne increments converged on local-optima because perceptual judgments about output quality were made in the same session that produced the output — a no-op feedback loop that documented "✅ rubric pass" against work that visibly missed the references. The §1.1 reframe softens the bar to "same visual conversation" rather than pixel-match, but it does not remove the need for an out-of-band perceptual review.

The standing process for every V.8.x phase:

1. **Claude Code renders a contact sheet via the existing harness** (`PresetVisualReviewTests` with `RENDER_VISUAL=1`) into `/tmp/phosphene_visual/<ISO8601>/` at phase end. The contact sheet must include silence / steady / beat-heavy / sustained-bass fixtures at minimum, plus high-V/A and low-V/A mood states once IBL lands.
2. **Matt uploads the contact sheet plus relevant references** to a separate Claude.ai chat session — not Claude Code, not this design doc, a fresh conversation with no implementation context.
3. **Claude.ai produces a structured visual diff** in the language of the reference cascade: macro / meso / micro / specular / atmosphere / palette gaps, plus an explicit anti-reference check against `09_anti_clipart_symmetry.jpg` and `10_anti_neon_stylized_glow.jpg`.
4. **Matt pastes the diff into the next Claude Code session** as the gap to address. The diff is the input; Claude Code does not regenerate it.
5. **Claude Code does NOT make perceptual judgments about its own output** — Matt and the separate Claude.ai session own that loop. Claude Code's role at phase end is to produce the contact sheet, summarise what changed structurally, and stop.

This pattern is process-architecture, not Arachne-specific. It is the standing rule for any preset increment that requires reference-image review. M7 cert remains Matt-eyeball-on-contact-sheet; this loop is what fills the gap between phase-boundary closeouts and the eventual M7 review.

---

## 8. Sequence to act on this doc

If Matt approves direction:

1. **Decisions sign-off** — Matt picks A.1/2, B.1/2, C.1/2/3, D.1/2/3, E.1/2/3, F.1/2/3, G.1/2/3. My recommendations stand unless overridden.
2. **V.8.1 prompt drafted** — based on the decisions, scoped to scaffold-only.
3. **V.8.1 implementation lands** — first 3D Arachne renders.
4. **Contact-sheet review #1** — Matt eyeballs the V.8.1 output against refs. Course-correct before V.8.2.
5. **V.8.2 → V.8.6** in sequence, each with a contact-sheet review after.

If Matt does *not* approve direction (e.g. wants to hold the current 2D approach and find another path), this doc gets archived and we plan the alternative.

The cost of this doc is small. The cost of executing V.8.1–V.8.6 without it would be much larger and more easily wasted.
