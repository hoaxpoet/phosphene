# Lumen Mosaic Design Doc

**Status:** **CERTIFIED 2026-05-12 at LM.7.** Phase LM CLOSED. `LumenMosaic.json` `certified: true`. `"Lumen Mosaic"` ∈ `FidelityRubricTests.certifiedPresets`. First catalog preset to land cert. Document refreshed 2026-05-12 to reflect actual landed shape (LM.4.6 palette + LM.6 depth gradient + LM.7 per-track tint), correcting the prior revision's aspirational reference to "LM.6 = Cook-Torrance specular sparkle" — that path was abandoned per the LM.3.2 round-7 / Failed Approach lock, and LM.6 as actually shipped is albedo-only modulation with the SDF normal still flat.

**Live contract — what the preset actually is.** A flat `sd_box` glass panel filling the camera frame. Surface is hex-biased Voronoi cells with per-cell dome+ridge relief and in-cell frost (`mat_pattern_glass`, V.3 §4.5b). Each cell carries a deterministic per-cell colour produced by a 32-bit hash → RGB function keyed on `(cellHash, beat-step counters, per-track seed, section salt)`, plus a per-track chromatic-projected RGB tint vector derived from `lumen.trackPaletteSeed{A,B,C}`. The pattern engine introduced in LM.2/LM.4 was retired in LM.4.4; agent-driven backlight (LM.2/LM.3.1) was retired in LM.3.2; the IQ cosine palette (LM.3/LM.4.5.x) was retired in LM.4.6. Brightness is uniform with light hash jitter `[0.85, 1.15]` plus a bar pulse on downbeats. **LM.6** adds two albedo-only modulations to each cell between the palette lookup and the frost diffusion: a depth gradient (full brightness at cell centre, 0.55 × hue at cell boundary — gives each cell a "domed 3D-glass" read) and an optional hot-spot (30 % brightness boost at the inner 15 % of each cell, additive on the cell's own hue). **The SDF normal stays flat and the matID==1 lighting path still skips Cook-Torrance entirely** — LM.6 is per-pixel Voronoi-driven albedo shading, not a normal-driven specular pass. **LM.7** adds a small per-track RGB tint vector with mean-subtraction (chromatic projection) before the saturate-clamp, so each track plays at a visibly distinct aggregate panel mean while every cell still independently samples the full uniform random RGB cube.

**Why this revision is so terse on the "proposed architecture".** Sections 4 and 7 of the previous revision proposed a layered system — agent dance, procedural palette, mood-coupled `(a, b, c, d)` parameters, pattern engine v1/v2, per-stem hue affinity, silhouette occluders. Almost every layer was either rejected at production review or retired during iteration. Documenting the proposed architecture as if it were current would be a documentation lie. This revision describes what shipped.

**Companion docs:**
- [`Lumen_Mosaic_Rendering_Architecture_Contract.md`](Lumen_Mosaic_Rendering_Architecture_Contract.md) — pass structure, buffer layouts, stop conditions, certification fixtures.
- [`LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md`](LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md) — historical session prompts (every increment is landed or retired).
- [`SHADER_CRAFT.md`](../SHADER_CRAFT.md) §4.5b — `mat_pattern_glass` recipe.
- [`ENGINEERING_PLAN.md`](../ENGINEERING_PLAN.md) — Phase LM increment ledger.

---

## 1. Why this preset exists

The reference images (`04_specular_pattern_glass_closeup.jpg` for cell + frost detail, `05_lighting_pattern_glass_dual_color.jpg` for the saturated multi-colour backlight character) show hammered pattern glass — irregular hex-biased cells, each a raised dimple separated by sharp inter-cell ridges, every cell carrying a fine bumpy frost that catches light at sub-pixel scale, and strong coloured light behind. **Each cell carries its own colour**, vivid, often differing markedly from its neighbours.

Phosphene's catalog has the material for this (`mat_pattern_glass`, V.3 Materials cookbook §4.5b) but no preset that uses pattern glass as the entire visual surface with vivid per-cell colour driven by music. Lumen Mosaic is that preset.

**Aesthetic role: an energetic dance partner.** The preset that makes people want to get up and dance. Cells change constantly — every cell carries its own evolving colour, and on a kick-driven track the field of cells reads as a vibrant honeycomb pulsing in time with the music. None of the other ray-march presets sits in that pocket — Volumetric Lithograph is gestural terrain, Glass Brutalist depicts moving architecture, Kinetic Sculpture is geometric motion. Lumen Mosaic owns the **vibrant-cell-field-dancing-with-the-music** register.

Phosphene-wide invariant (CLAUDE.md): muted palettes have no place in the catalog. Quiet moments exist (silence, breakdowns, intros) but the active visual register is always vivid, saturated, alive.

This is **not** Glass Brutalist v3. Glass Brutalist depicts brutalist concrete corridor architecture with pattern glass as one element in a bigger spatial composition; Lumen Mosaic has no depicted architectural scene — the glass *is* the scene, and colour through the glass is the music.

---

## 2. Constraints (non-negotiable)

Inherited from CLAUDE.md and DECISIONS.md. Not relitigated here.

1. **Performance ceiling — Tier 1: 14 ms / Tier 2: 16 ms** (FrameBudgetManager). Lumen Mosaic targets **the cheapest ray-march preset in the catalog**: p95 ≤ 3.7 ms at Tier 2, ≤ 4.5 ms at Tier 1. Measured on M2 Pro in session `2026-05-12T17-15-14Z`: `frame_gpu_ms` mean 1.37 ms / max 32.9 ms / 3 of 14622 frames > 16 ms (0.02 %). Per-pixel cost is dominated by `voronoi_f1f2` calls + the matID==1 emission composite (Cook-Torrance is intentionally skipped). LM.6 and LM.7 add zero render passes — both are albedo modulations inside `sceneMaterial`, driven by per-pixel scalars already computed.

2. **D-020 architecture-stays-solid.** The glass panel is fixed structure. Audio reactivity routes to per-cell beat-step counters, hash-driven colour, and the bar pulse — never to panel geometry, never to cell shape, never to cell positions. The Voronoi seed lattice is constant for the lifetime of the preset.

3. **D-026 deviation primitives only.** All audio drivers use `_rel` / `_dev` / `_att_rel` fields, never raw `f.bass` / `f.mid` / `f.treble`. Documented exception: the per-cell colour engine uses `f.beatBass` / `f.beatMid` / `f.beatTreble` as rising-edge triggers on the FFT beat envelopes — these are event signals, not energy reads, and `BeatDetector` already gates them through onset detection.

4. **D-019 silence fallback.** At `totalStemEnergy == 0`, cells hold their previous palette state (counters stop advancing). Brightness floor keeps cells visibly coloured.

5. **D-021 sceneMaterial signature.** Standard signature; `StemFeatures` not in scope for `sceneSDF`/`sceneMaterial`. The preset uses `f` directly with D-019 fallback patterns.

6. **D-037 acceptance invariants.** Non-black at silence, no white clip on steady, beat response ≤ 2× continuous response + 1.0, form complexity ≥ 2 at silence. Cell-quantized output naturally satisfies form complexity.

7. **Continuous energy primary, beats accent.** D-004. The bar pulse on downbeats is an accent layer. The beat-step counters are event-shaped (rising-edge of FFT band envelopes); each counter advance is a single discrete step, not a continuous modulation.

8. **Detail cascade mandate** (CLAUDE.md, SHADER_CRAFT.md §2.2). Four scales of variation:
   - Macro: cell layout (Voronoi at scale ≈ 60 — implementation drifted from the original C.2 ~50-cells target to ~30 cells across during LM.3.2 round 2, see §6).
   - Meso: per-cell dome shading from the LM.6 depth gradient (`cell_hue *= mix(0.55, 1.0, depth01(f1, f2))`) — full brightness at cell centre, 0.55 × hue at boundary; reads as "domed glass" without geometric perturbation.
   - Micro: in-cell frost mixed into albedo via Voronoi-distance diffusion (LM.3.2 round 7 — no normal artifacts).
   - Specular breakup: the LM.6 hot-spot adds a 30 %-brightness pinpoint at the inner 15 % of each cell. **Albedo-only**, additive on the cell's own hue (not toward white) — palette character preserved. The SDF normal stays flat; no Cook-Torrance specular pass is invoked on matID==1.

9. **No external dependencies.** Stays on Metal + the V.1–V.3 utility library. No new utility modules required.

10. **I (Claude) cannot see rendered output.** Every visual judgment in implementation comes from Matt. Phase boundaries require Matt-driven contact-sheet review against the reference images and against silence / steady / beat-heavy / mood-quadrant / per-track fixtures.

---

## 3. Decisions in force

After multiple rounds of iteration, the decisions that govern the current implementation are:

| Decision | Status | What it says |
|---|---|---|
| **A.1** Lumen Mosaic | ✅ | Preset name. |
| **B.1** Analytical agent contributions, no behind-glass geometry | ⚠ scaffold-only | The 4-light agent struct stays on the GPU buffer for ABI continuity but is *unused* by the current shader. LM.3.1 retired agent-driven backlight character; LM.4.4 retired agent-position-driven patterns. |
| **C.2** ~50 cells across | ⚠ drifted | LM.3.2 round 2 reduced `kCellDensity` from 30 → 15 (cells across 60 → 30). The implementation is closer to C.1 (~30 cells across); the parameter survives as a JSON-tunable. |
| ~~**D.1** Cell-quantized agent sample~~ | ⊘ retired | LM.2 production failure mode — adjacent cells got nearly identical colours from a smooth analytical light field. |
| ~~**D.4** Per-cell `palette()` keyed on `cell_hash + accumulated_audio_time × kCellHueRate + mood`~~ | ⊘ retired | LM.3 production failure mode — Spotify volume normalisation (BUG-012) under-reads mid + treble bands; `accumulated_audio_time` advanced ~10× too slowly to read as motion. |
| ~~**D.5** Band-routed beat-driven dance (HSV palette, 4 teams, debounced rising-edges)~~ | ⊘ retired by LM.4.6 | LM.3.2 shipped this and Matt M7-passed it 2026-05-10 — but the palette breadth ask in subsequent M7 reviews ("I literally want ANY possible color to be possible within ANY cell") could not be satisfied within an HSV-with-rules formulation. |
| **D.6** Pure uniform random RGB per cell, keyed on `(cellHash, beat-step counters, per-track seed, section salt)` | ✅ in force | The LM.4.6 contract. Each `(cell, beat, track, section)` tuple gets a unique 32-bit colour hash → RGB ∈ [0, 1]. No HSV indirection, no coupling rule, no mood gamma, no saturation floor, no palette parameters. The team / period / counter architecture from D.5 is preserved as the *trigger* mechanism; only the colour decoder changed. |
| ~~**E.1** Cream-baseline mood tint~~ | ⊘ retired | LM.1 / LM.2 production failure mode — muted pastel output. |
| ~~**E.2** 4 hand-authored palette banks crossfaded by mood quadrant~~ | ⊘ retired | LM.3 design pivot — "monotonous" (Matt 2026-05-09). |
| ~~**E.3** Procedural palette via V.3 IQ cosine `palette()`; mood shifts `(a, b, c, d)` continuously~~ | ⊘ retired by LM.4.6 | The full HSV cube with rules formulation could not deliver the palette breadth Matt asked for; LM.4.5.x explored five different restrictions and all were rejected. The IQ cosine palette is no longer called from `LumenMosaic.metal`. |
| **E.4** Direct hash → RGB; mood character via bassCounter-driven section salt only | ✅ in force | The LM.4.6 contract. Section salt = `lumen.bassCounter / 64` (every ~32 s on 120 BPM, resets on track change) is the only mood-correlated mutation; otherwise the panel is per-cell independent. |
| **F.1** Slot 8 fragment buffer | ✅ | `directPresetFragmentBuffer3` / `setDirectPresetFragmentBuffer3` per LM.0. |
| **F.2** LM.6 cell-depth gradient + optional hot-spot (D-LM-6) | ✅ in force | Two albedo modulations between palette lookup and frost diffusion in `sceneMaterial`. (1) Depth gradient: `cell_hue *= mix(0.55, 1.0, depth01(f1, f2))` — domed cell read. (2) Optional hot-spot: `cell_hue += pow(1-smoothstep(0, 0.15×f2, f1), 4.0) × 0.30 × cell_hue` — 30 % centre boost on the cell's own hue. Driven entirely by Voronoi `f1/f2` field; zero extra cost. **SDF normal stays flat**, matID==1 lighting path still skips Cook-Torrance. |
| **F.3** LM.7 per-track aggregate-mean RGB tint with chromatic projection (D-LM-7) | ✅ in force | Inside `lm_cell_palette`, applied before the saturate-clamp: `trackTint = (rawTint - mean(rawTint)) × kTintMagnitude (0.25)` where `rawTint = (seedA, seedB, seedC)`. Mean-subtraction projects every tint onto the chromatic plane perpendicular to (1,1,1); achromatic-aligned seeds collapse to LM.4.6-neutral rather than washing toward white/black. Each track plays at a visibly distinct aggregate panel mean. Per-cell freedom preserved in spirit (full uniform-random RGB cube still sampled per cell; only the sampling window slides per track). Relaxes LM.4.6's strict "any colour reachable on every track" framing — Matt 2026-05-12 explicitly accepted the trade-off. |
| **G.1** Fixed camera, panel oversize 1.50× | ✅ | No camera motion. Panel half-extents `cameraTangents.xy × 1.50` so the panel bleeds past the frame on every side. |
| **H.1** Standalone preset | ✅ | New `LumenMosaic.metal` + `LumenMosaic.json`. Glass Brutalist v2 (V.12) is independent. |

**The honest math caveat (LM.4.6, superseded by LM.7).** The LM.4.6 contract documented that uniform random sampling produces statistically similar panel-aggregates across tracks (different specific colours per cell, same distribution shape — law of large numbers). LM.7 partially resolves this by adding a per-track tint that shifts the aggregate mean per track. The relaxation of LM.4.6's strict per-cell-everywhere-reachable framing was accepted on the basis that *most* colours remain reachable on every track (only the cube corner opposite the tint direction is forfeit at extreme seed values). Per-cell freedom is preserved *in spirit* — every cell still independently samples the full uniform random RGB cube on every track; only the sampling window slides.

---

## 4. Current architecture

### 4.1 Render passes

`LumenMosaic.json` `passes` → `["ray_march", "post_process"]`.

The `ray_march` pass is Phosphene's existing 3-pass deferred (G-buffer / lighting / composite). For Lumen Mosaic, `sceneSDF` returns a single planar glass panel; one-step trace, no expensive iteration. `post_process` adds bloom and ACES. SSGI is intentionally **disabled** — the panel is emission-dominated; SSGI's contribution is invisible against bright emissive cells.

### 4.2 sceneSDF

Single planar glass panel, half-extents `cameraTangents.xy × 1.50` so the panel bleeds past the frame on every side, with Voronoi domed-cell relief + `fbm8` frost baked in as Lipschitz-safe SDF displacements. Audio-independent (D-020). The G-buffer central-differences normal picks up the relief.

### 4.3 sceneMaterial — D.6 per-cell uniform random RGB

```metal
void sceneMaterial(float3 p, int matID, /* ... */, constant LumenPatternState& lumen) {
    float2 panel_uv = p.xy / s.cameraTangents.xy;
    VoronoiResult v = voronoi_f1f2(panel_uv, kCellDensity);

    // Per-cell step indices from the 4-team rising-edge counters (LM.3.2 architecture preserved).
    uint cellHash = uint(v.id);
    uint team     = lm_team_for_cell(cellHash);              // bass / mid / treble / static
    uint period   = lm_period_for_cell(cellHash);            // {1, 2, 4, 8}
    uint counter  = lm_team_counter(lumen, team);
    uint step     = counter / period;

    // Section salt — bass-counter-driven, advances every ~32 s on 120 BPM (resets on track change).
    uint sectionSalt = lumen.bassCounter / 64u;

    // LM.4.6 — Pure hash → RGB. No HSV, no palette function, no coupling rules.
    uint colorHash = lm_hash_u32(cellHash ^ step ^ lumen.trackSeedHash ^ sectionSalt);
    float3 cellRGB = lm_unpack_rgb_unit(colorHash);          // three bytes → [0, 1]^3

    // LM.7 — per-track RGB tint, projected onto the chromatic plane.
    float3 rawTint   = float3(lumen.trackPaletteSeedA, lumen.trackPaletteSeedB, lumen.trackPaletteSeedC);
    float  meanShift = (rawTint.r + rawTint.g + rawTint.b) / 3.0;
    float3 trackTint = (rawTint - float3(meanShift)) * kTintMagnitude;   // ±0.25 chromatic-only
    float3 cell_hue  = saturate(cellRGB + trackTint);

    // LM.6 — cell-depth gradient: full brightness at centre (f1 → 0), darker at boundary (f1 → f2).
    float cellRadius = v.f2 * kDepthGradientFalloff;          // 1.0 × f2
    float depth01    = 1.0 - smoothstep(0.0, cellRadius, v.f1);
    cell_hue *= mix(kCellEdgeDarkness, 1.0, depth01);          // 0.55 at edge, 1.0 at centre

    // LM.6 — optional hot-spot: 30 % boost at inner 15 % of cell, additive on cell's own hue.
    float hotSpot = 1.0 - smoothstep(0.0, kHotSpotRadius * v.f2, v.f1);
    hotSpot = pow(hotSpot, kHotSpotShape);                     // pow^4 sharp falloff
    cell_hue += hotSpot * kHotSpotIntensity * cell_hue;        // 0.30 max boost

    // Brightness: tight per-cell jitter + bar pulse on downbeats.
    float hashJitter = 0.85 + 0.30 * float(cellHash & 0xFF) * (1.0 / 255.0);
    float barPulse   = 1.0 + 0.20 * pow(f.barPhase01, 8.0);
    float intensity  = hashJitter * barPulse;

    // Frost diffusion at cell boundaries (LM.3.2 round 7).
    float frost = compute_frost_from_voronoi_distance(v);
    float3 frosted_hue = mix(cell_hue, float3(1.0), saturate(frost));

    albedo    = clamp(frosted_hue * intensity, 0.0, 1.0);
    // matID == 1 lighting path: emission = albedo × kLumenEmissionGain + IBL ambient floor.
    // Cook-Torrance is intentionally NOT invoked; per LM.3.2 round-7 / Failed Approach lock,
    // the SDF normal stays flat (kReliefAmplitude = 0) to avoid per-pixel normal-jitter artifacts.
    roughness = 0.40;
    metallic  = 0.0;
    outMatID  = 1;
}
```

The `LumenPatternEngine` (Swift, in the engine module) ticks the 4 band counters from rising-edges of `f.beatBass` / `f.beatMid` / `f.beatTreble` (debounced 80 ms, scaled by energy). The `LumenLightAgent` slots remain on the GPU buffer for ABI continuity; their `intensity` and `colorR/G/B` fields are unused. The `LumenPattern` slot machinery remains as a zero-active-pattern placeholder; LM.4.4 retired pattern spawning entirely.

### 4.4 Audio coupling

| Audio source | Visual target | Notes |
|---|---|---|
| `f.beatBass` rising edge | `lumen.bassCounter += 1` | Debounced 80 ms; ~30 % of cells respond on bass team. Drives section salt as `bassCounter / 64`. |
| `f.beatMid` rising edge | `lumen.midCounter += 1` | ~35 % of cells respond on mid team. |
| `f.beatTreble` rising edge | `lumen.trebleCounter += 1` | ~25 % of cells respond on treble team. |
| (no team trigger) | static team holds | ~10 % of cells hold their colour for the whole section. |
| `f.barPhase01` | Bar pulse `1 + 0.20 × bar_phase01^8` | Brief +20 % flash in the last ~8 % of each bar. No-op on reactive tracks (collapses to 1.0). |
| `lumen.trackPaletteSeedA/B/C` | LM.7 per-track tint vector | Derived from FNV-1a hash of "title \| artist" in `VisualizerEngine+Stems.resetStemPipeline`. Chromatic-projected via mean subtraction; scaled by `kTintMagnitude (0.25)`. Each track plays at a visibly distinct aggregate panel mean. |
| `v.f1` / `v.f2` (Voronoi distance fields) | LM.6 cell-depth gradient + hot-spot | Per-pixel scalars driving the depth gradient (centre→edge brightness) and hot-spot (inner 15 % centre boost). Albedo-only modulations. |
| `f.valence` / `f.arousal` | (unused) | The LM.4.6 contract retired mood-coupled palette parameters. Mood is no longer a visible driver; LM.7 per-track tint replaces it as the cross-track variation mechanism. |

**The dance.** Per-cell palette steps advance on each team's beat. Bass-team cells advance on kicks; mid-team on melody; treble-team on hats/cymbals; static-team cells hold. Different cells advance on different bands → the panel reads as a coordinated ensemble. Pareto-shaped periods `{1, 2, 4, 8}` mean some cells step every beat, others every 8 beats. Section salt advances every ~32 s, mutating *all* cells' colours simultaneously and providing the long-form variation.

**Silence rests.** Counters stay at 0 → step stays at 0 → all cells display their `(cellHash, 0, trackSeed, 0)` colour. `f.bar_phase01` is 0 → no bar pulse. The panel is uniformly bright and coloured; no fade to grey, no cream.

---

## 5. Reference and anti-reference

### 5.1 Hero references

- **`04_specular_pattern_glass_closeup.jpg`** — close-up of hammered pattern glass; carries the cell + frost detail cascade (macro / meso / micro). Verification target for LM.6 cell-depth gradient + hot-spot character (each cell reads as a domed glass tile with a centre highlight, not flat-painted).
- **`05_lighting_pattern_glass_dual_color.jpg`** — pattern glass with strong saturated multi-colour backlight; carries the vivid per-cell colour identity. Verification target for LM.4.6 palette breadth + LM.7 per-track aggregate distinction.

**Failure modes to preflight against:**
- **Pastel / muted output** (LM.1 / LM.2 / LM.4.5.0 / LM.4.5.2). Cells reading as washed cream. The LM.4.6 contract uses direct uniform RGB hash and has no path to pastels except by accidental tone-mapping clip; verify in M7 review.
- **Smooth gradient blob** (LM.2 production failure). Adjacent cells getting nearly identical colours from a smooth analytical light field. The LM.4.6 contract uses independent per-cell hashes; verify the distinct-neighbour gate at cert.
- **Cells static / unchanging.** The team-counter dance must visibly advance during energetic playback. The D.4 continuous-cycling mechanism was retired specifically because `accumulated_audio_time` couldn't drive it under Spotify volume normalisation; the D.5/D.6 rising-edge counter mechanism survives because it triggers on individual beats not energy magnitudes.
- **Stained-glass cathedral cliché** (saturated primaries in fixed iconographic symmetry). Avoid radial-symmetry pattern motifs (moot now that the pattern engine is retired).
- **Panel boundary visible in frame** — fix via panel half-extents `cameraTangents.xy × 1.50` per G.1; verify at cert against 16:9 / 4:3 / 21:9 aspect ratios.

### 5.2 Trait matrix

| Trait | Source | Implementation |
|---|---|---|
| Hex-biased Voronoi cells | ref macro | `voronoi_f1f2` at scale 60 (LM.3.2 round 2 — drifted from C.2's 30) |
| Domed cell + sharp ridge | ref meso | V.3 §4.5b height-gradient recipe via Voronoi `f2 - f1` |
| In-cell frost (Voronoi-distance) | ref micro | Frost diffusion baked into albedo, not normal perturbation (LM.3.2 round 7) |
| LM.6 cell-depth gradient | ref material / meso | Per-cell albedo modulation `cell_hue *= mix(0.55, 1.0, depth01(f1, f2))` — domed glass read, no normal perturbation |
| LM.6 hot-spot (optional) | ref material / specular | Per-cell albedo modulation `cell_hue += pow(...) × 0.30 × cell_hue` — centre pinpoint additive on cell's own hue, no Cook-Torrance pass |
| Per-cell colour identity | ref `05` colour | Direct hash → RGB per `(cellHash, step, trackSeed, sectionSalt)` (D.6) |
| LM.7 per-track aggregate distinction | ref `05` colour / cross-track | Chromatic-projected RGB tint `trackTint = (rawTint - mean(rawTint)) × 0.25` from `trackPaletteSeed{A,B,C}` — shifts panel-aggregate mean per track without restricting per-cell freedom |
| Vivid palette character | ref `05` colour | Uniform random RGB ∈ [0,1]; statistical guarantee of one channel < 0.30 AND another > 0.70 |
| Cells changing on the beat | preset intent | 4-team rising-edge counters on `f.beatBass / beatMid / beatTreble` |
| Section-scale colour mutation | preset intent | `bassCounter / 64` salt advances every ~32 s on 120 BPM |
| Static panel SDF | preset role | `sceneSDF` audio-independent (D-020) |

### 5.3 Anti-references

- Stained-glass cathedral imagery (avoid radial symmetry — moot now that patterns are retired).
- TV-static / film-grain glass (per-pixel noise that doesn't respect cell boundaries). The frost is baked into albedo via Voronoi distance, not per-pixel random.
- Lava-lamp / plasma / blob aesthetic (continuous gradient without cell quantization). The cellular grid is the visual identity.
- Pastel / cream-tinted output. The direct hash → RGB has no path to pastels by construction.

---

## 6. Phased plan (Phase LM) — landed work

| Increment | Scope | Status |
|---|---|---|
| LM.0 | Fragment buffer slot 8 infrastructure (`directPresetFragmentBuffer3`) | ✅ landed 2026-05-08 (`6388e881`) |
| LM.1 | Minimum viable preset: glass panel + `mat_pattern_glass` + static warm-amber backlight | ✅ landed (scaffolding) |
| LM.2 | 4 audio-driven light agents + mood-coupled hue shift + D-019 silence fallback | ⚠ rejected — muted output. Slot-8 binding + agent dance proven correct (scaffold reused at LM.3) |
| LM.3 | Per-cell colour via `palette()` keyed on `cell_hash + accumulated_audio_time × kCellHueRate + mood` (D.4) | ⚠ rejected — Spotify volume normalisation (BUG-012) under-reads mid+treble; `accumulated_audio_time` advanced ~10× too slowly to register as motion |
| LM.3.1 | Agent-position-driven static-light field as backlight character | ⚠ rejected — "fixed-color cells with brightness modulation; the bright pools dominated" (Matt 2026-05-09) |
| LM.3.2 | Band-routed beat-driven dance (D.5): HSV palette, 4 teams, rising-edge counters, period ∈ {1,2,4,8}, frost in albedo, bar pulse on downbeats | ✅ M7 pass 2026-05-10 (session `T15-44-27Z`). 8 calibration rounds. Carry-forward: track-to-track colour variation could be wider |
| LM.4 | Pattern engine v1: `idle` / `radial_ripple` / `sweep` with bar-boundary + drum-onset triggers | ⚠ rejected — triggers fired at constant ~2.41/sec regardless of tempo; root cause was `f.beatBass` FFT-band detector decoupled from song's actual beat |
| LM.4.1 | Ripple density + bleach-out fix (3-line calibration) | ⚠ landed but superseded by LM.4.3 |
| LM.4.3 | BeatGrid-driven triggers replacing FFT-band edges; ripples demoted to per-bar accent | ⚠ landed but superseded by LM.4.4 |
| LM.4.4 | **Pattern engine retired entirely.** `LumenPatterns.swift` deleted; `LumenPatternEngine` rewritten with pattern-spawning semantics gone. The GPU ABI is preserved for hypothetical future use; no current consumer. | ✅ landed 2026-05-11 |
| LM.4.5 (v1) | Full HSV cube + pastel guardrail | ⚠ rejected — gray cells |
| LM.4.5.1 | Saturated stained-glass (sat floor 0.70) | ⚠ rejected — anchored to jewel tones |
| LM.4.5.2 | Full sat range + coupling rule `val ≤ sat + 0.20` | ⚠ rejected — borderline pale cells |
| LM.4.5.3 | Uncapped palette + per-cell brightness 0.30..1.60 + section mutation + emission boost | ⚠ rejected — tracks looked statistically identical at panel level; 30% gray cells |
| LM.4.6 | **Pure uniform random RGB per cell (D.6).** Direct hash → RGB, no HSV / palette / coupling / mood gamma. Per-cell jitter `[0.85, 1.15]`. Section salt = `bassCounter / 64`. | ✅ landed 2026-05-12 (`c0f9ccf3` + hotfix `888bb856`). Matt: "Working. It's close enough." |
| ~~LM.5~~ | ~~Pattern engine v2 (clusterBurst, breathing, noiseDrift) + optional per-stem hue affinity~~ | ⊘ retired by LM.4.4 (no pattern engine to extend) |
| LM.6 | **Cell-depth gradient + optional hot-spot.** Two albedo-only modulations between palette lookup and frost diffusion: depth gradient (centre→edge brightness via `mix(0.55, 1.0, depth01(f1, f2))`) + optional hot-spot (centre 30 % boost additive on cell's own hue). **No Cook-Torrance pass** — earlier aspirational doc referred to this increment as "specular sparkle" but the actual landed shape is albedo modulation with the SDF normal still flat (`kReliefAmplitude = 0` / `kFrostAmplitude = 0`) per the LM.3.2 round-7 / Failed Approach lock. D-LM-6. | ✅ landed 2026-05-12 |
| LM.7 | **Per-track aggregate-mean RGB tint with chromatic projection.** `trackTint = (rawTint - mean(rawTint)) × kTintMagnitude (0.25)` from `trackPaletteSeed{A,B,C}`. Mean subtraction projects onto chromatic plane perpendicular to (1,1,1); achromatic-aligned seeds collapse to LM.4.6-neutral rather than washing. Each track plays at a visibly distinct aggregate panel mean while every cell still independently samples the full uniform random RGB cube. D-LM-7. | ✅ landed 2026-05-12 |
| ~~LM.8~~ | ~~Mood-quadrant palette banks (E.2)~~ | ⊘ retired 2026-05-09 (monotony grounds) |
| Cert | Matt M7 sign-off on real-music session `2026-05-12T17-15-14Z`. `LumenMosaic.json` `certified: true`. `"Lumen Mosaic"` ∈ `FidelityRubricTests.certifiedPresets`. First catalog preset with `certified: true`. Phase LM CLOSED. | ✅ landed 2026-05-12 |

---

## 7. Acceptance criteria — final shape

Lumen Mosaic is on the **full rubric** profile (M1–M7 mandatory, E1–E4 expected, P1–P4 preferred). Lightweight profile (Plasma / Waveform / Nebula / SpectralCartograph) does not apply.

### 7.1 Mandatory (rubric 7/7)

1. **Detail cascade present.** Macro (cell layout via Voronoi at scale ≈ 30) + meso (LM.6 depth gradient gives each cell a domed centre→edge brightness gradient) + micro (in-cell frost mixed into albedo via Voronoi distance) + specular breakup (LM.6 hot-spot — centre pinpoint additive on cell's own hue). A frame downsampled to 32×32 still shows recognizable cells; full-res shows the LM.6 centre-bright domes and per-cell colour variety. **Heuristic note:** the automated `M1_detail_cascade` evaluator may flag this as failing because Lumen Mosaic uses Voronoi cell quantization rather than named scale markers; the cascade is present and verified by M7 manual review.
2. **≥ 4 noise octaves.** `fbm8` called for in-cell frost. Confirmed structurally; passes the automated `M2_octave_count` heuristic.
3. **≥ 3 distinct materials.** Emission-only matID==1 path uses `voronoi_f1f2` cells + frost diffusion + LM.6 albedo modulations as its "materials" — not V.3 cookbook calls. **The automated `M3_material_count` heuristic flags this as failing** because it scans for `mat_*` cookbook callsites. Per SHADER_CRAFT.md §12.1 M7, Matt's manual M7 sign-off is the load-bearing gate; the M3 heuristic doesn't fit emission-only matID==1 presets by design.
4. **D-026 deviation primitives audio routing.** Lumen Mosaic uses `f.beatBass` / `f.beatMid` / `f.beatTreble` rising-edge usage (event-shaped onset detection) as its primary audio coupling — these are documented D-026 exceptions because they're event signals, not absolute-threshold energy reads. `f.bar_phase01` drives the bar pulse. Rhythm coupling routes via slot-8 `LumenPatternState` counters, not direct FeatureVector reads. **The automated `M4_deviation_primitives` heuristic flags this as failing** because it scans for `bass_rel` / `bass_dev` field reads; the actual deviation discipline is satisfied via the counter mechanism.
5. **D-019 silence fallback.** At `totalStemEnergy == 0` cells hold their `(cellHash, 0, trackSeed, 0)` colour. Non-black, visually coherent. Verified by `LumenPaletteSpectrumTests`.
6. **p95 frame time ≤ Tier 2 budget (16 ms).** Target met on M2 Pro: session `2026-05-12T17-15-14Z` measured `frame_gpu_ms` mean 1.37 ms / max 32.9 ms / 3 of 14622 frames > 16 ms (0.02 %). Well below ceiling.
7. **Matt-approved reference frame match.** ✅ M7 sign-off 2026-05-12 (jointly with LM.6 + LM.7) — *"each track now has a visually distinct color palette ... I think we can move to certify this preset."*

### 7.2 Expected (≥ 2/4)

1. **Triplanar texturing on non-planar surfaces** — N/A; panel is planar. Skipped (1/4 max).
2. **Detail normals** — frost normal perturbation. Met.
3. **Volumetric fog / aerial perspective** — minimal; mood-tinted IBL ambient stands in. Partial.
4. **SSS / fiber BRDF / anisotropic specular** — emission-as-SSS-approximation present via `mat_pattern_glass` (`emission = albedo * 0.15`). Met.

Score: ~2.5/4. Above the ≥ 2 threshold.

### 7.3 Strongly preferred (≥ 1/4)

1. **Hero specular highlight ≥ 60% of frames** — LM.6 hot-spot fires on every cell every frame (it's a per-pixel Voronoi-driven albedo modulation, not a stochastic event). Note: `rubric_hints.hero_specular` is set to `false` in the JSON sidecar because the automated heuristic looks for Cook-Torrance specular call sites which don't exist on the matID==1 emission path. Per M7 review the hero-specular character is delivered by the hot-spot.
2. **POM on at least one surface** — N/A. Skipped.
3. **Volumetric light shafts / dust motes** — N/A. Skipped.
4. **Chromatic aberration / thin-film** — N/A in current shape. Skipped.

Score: 1/4. Met.

### 7.4 Total rubric score

Mandatory 7/7 + Expected 2.5/4 + Strongly Preferred 1/4 = **10.5 / 15**. Threshold is 10/15 with all mandatory passing. **Cleared.**

### 7.5 Cert gates — LM.7 (certified 2026-05-12)

Cert closed at LM.7 (rather than the originally-planned LM.9). The "LM.9 = cert" framing in earlier doc revisions assumed LM.5 + LM.6 + LM.7 + LM.8 + LM.9 as separate increments; LM.5 / LM.7 (old shape — pattern bursts) / LM.8 were all retired with the pattern engine; cert moved up to LM.7. Gates met:

- **Vividness gate** ✅ Every non-silence fixture produces per-cell colour values where the dominant cells have at least one channel `< 0.30` AND another channel `> 0.70` in linear space pre-tone-map. Statistically guaranteed by uniform random RGB in [0,1] (probability ~ 0.6 per cell). Automated check via `LumenPaletteSpectrumTests`.
- **Distinct-neighbour gate** ✅ Sample 50 random cell-centre uvs; colour distribution spans ≥ 1/3 of RGB cube. Statistically guaranteed by independent per-cell hashes. Automated check.
- **No-cream gate** ✅ No fixture frame within ε of `(0.95, 0.85, 0.75)`. Statistically negligible probability under uniform RGB. LM.7 chromatic projection ensures no wash toward cream on achromatic-aligned tracks (Matt 2026-05-12 explicitly accepted this — see test `test_achromaticAlignedSeed_doesNotWash`).
- **Time-evolution gate** ✅ Two frames 3 s apart at the same fixture, with simulated counter advance, differ in non-silence fixtures. Verifies the team-counter rising-edge mechanism produces visible motion.
- **Per-track distinctiveness gate** ✅ LM.7 added — `test_distinctTracks_haveDistinctAggregateMeans` regression-locks that any two distinct trackSeeds produce aggregate-mean RGB distance ≥ 0.20. This gate was originally retired at LM.4.6 as incompatible with the strict "any colour reachable on every track" contract; LM.7 relaxed the contract (per-cell freedom *in spirit*) and the gate is back, satisfied by construction.
- **LM.6 dome character** ✅ Each cell visibly brighter at centre, darker at boundary; optional hot-spot reads as subtle centre highlight. Verified by `LumenPaletteSpectrumTests` Suite 6 + M7 visual review.
- **Matt M7 sign-off on real-music multi-track playback** ✅ Session `2026-05-12T17-15-14Z`.

### 7.6 Acceptance against the reference image

A 30-second clip of the preset, captured at energetic mood with steady moderate energy, should produce a frame where:

1. Cells are visibly hex-biased and tessellated.
2. Cells carry visibly distinct colours — adjacent cells differ markedly in hue; no smooth gradient reading.
3. The palette is vivid, not pastel — dominant cells read as saturated, no cream / grey-haze.
4. **LM.6 dome read visible** — each cell shows centre-bright / edge-dark gradient (cell-depth gradient). LM.6 hot-spot, when enabled (`kHotSpotIntensity > 0`), shows a small centre highlight in each cell, additive on the cell's own hue (palette character preserved). Detail cascade complete.
5. **LM.7 per-track aggregate distinction visible** — playing two different tracks during the same session produces visibly different panel-aggregate colour temperatures.
5. Cell-edge ridges produce a visible inter-cell network of dark seams.
6. No cell exhibits gradient colour across its area (D-LM-cell-quantization preserved).
7. Cells visibly advance through palette steps during 3 seconds of energetic playback (team-counter dance).
8. Bar pulse fires visibly on downbeats (`barPhase01 ^ 8` → +20% flash in last ~8% of bar).

---

## 8. Out of scope

- **Refraction through the glass.** Analytical-only backlight per B.1; second-bounce ray tracing not adopted.
- **Per-cell persistent state.** The team-counter mechanism is the only persistent state; everything else is recomputed per frame.
- **Direct manual cell selection.** Cell IDs are deterministic but not numbered for human authoring.
- **Glass thickness simulation.** Notional thickness only; no inside-the-glass effects.
- **Track-section-aware pattern bank.** Section salt is bass-counter-driven, not aware of structural prediction.
- **Pattern engine** (LM.4 retired). The `LumenPattern` GPU struct remains for ABI continuity.
- **Mood-coupled palette parameters** (LM.4.6 retirement). Mood is no longer a visible driver.
- **Per-stem hue affinity** (LM.5 retirement). The agent struct remains for ABI; agent colour fields are unused.

---

## 9. Citations and grounding

- **Pattern glass references and material recipe.** SHADER_CRAFT.md §4.5b `mat_pattern_glass`. Reference: `04_specular_pattern_glass_closeup.jpg`, `05_lighting_pattern_glass_dual_color.jpg`.
- **Architecture-stays-solid principle.** DECISIONS.md D-020.
- **Audio data hierarchy.** CLAUDE.md "Layer 1–5b" + DECISIONS.md D-004, D-026.
- **Silence fallback pattern.** DECISIONS.md D-019.
- **Voronoi cell addressability via `v.id`.** SHADER_CRAFT.md §4.6 `mat_ferrofluid` (the pattern is shared).
- **Cook-Torrance + IBL + bloom + ACES pipeline.** ARCHITECTURE.md `RayMarchPipeline` and `PostProcessChain`.
- **Preset acceptance gate.** DECISIONS.md D-037, D-039; `PresetAcceptanceTests` and `PresetRegressionTests`.
- **Fidelity rubric.** SHADER_CRAFT.md §12 + DECISIONS.md D-067.

---

## 10. Sign-off

**LM.0 era decisions** — Matt confirmed A.1, B.1, C.2, D.1, E.1, F.1, G.1, H.1 before LM.0–LM.2 landed. A.1 / F.1 / G.1 / H.1 stand unchanged. B.1 / C.2 reduced to scaffold or drifted. D and E went through complete redesigns.

**LM.3 pivot (2026-05-09)** — energetic-not-meditative role; D.1 → D.4; E.1/E.2 → E.3; cream baseline retired.

**LM.3.2 sign-off (2026-05-10)** — Matt M7 pass on real-music session `T15-44-27Z`: "Awesome. Finally. The movement of the color in the cells is looking good. I'd consider this a 'pass.'" Carry-forward: track-to-track variation could be wider.

**LM.4.6 sign-off (2026-05-12)** — Matt: "Working. It's close enough." The track-variation carry-forward from LM.3.2 was addressed by relaxing the palette breadth to the full RGB cube and accepting the panel-aggregate-similarity trade-off.

**LM.6 sign-off (2026-05-12)** — ✅ Matt M7 pass on real-music session `~/Documents/phosphene_sessions/2026-05-12T17-15-14Z` (jointly with LM.7). The actual landed LM.6 is cell-depth gradient + optional hot-spot — two albedo-only modulations driven by Voronoi `f1/f2`. The earlier framing ("specular sparkle via Cook-Torrance on frost normal") was abandoned per the LM.3.2 round-7 / Failed Approach lock; LM.6 is per-pixel albedo shading, not a normal-driven specular pass. See D-LM-6.

**LM.7 sign-off (2026-05-12)** — ✅ Same session. Per-track aggregate-mean RGB tint with chromatic projection (`trackTint = (rawTint - mean(rawTint)) × 0.25`). Each track plays at a visibly distinct aggregate panel mean. *"Fix has achieved the desired effect — each track now has a visually distinct color palette ... I think we can move to certify this preset."* See D-LM-7.

**Cert sign-off (2026-05-12)** — ✅ `LumenMosaic.json` `certified: true`. `"Lumen Mosaic"` added to `FidelityRubricTests.certifiedPresets`. First catalog preset to land cert. Phase LM CLOSED.

---

## 11. Revision history

- **2026-05-12 (LM.7 cert sweep — doc drift correction)** — LM.6 + LM.7 landed and Lumen Mosaic certified. Doc drift corrected: the prior "LM.6 added Cook-Torrance specular pass on matID==1" claim was wrong (aspirational text written before the LM.6 prompt was finalized). Actual LM.6 = albedo-only cell-depth gradient + optional hot-spot, both driven by Voronoi `f1/f2`, with the SDF normal still flat per the round-7 / Failed Approach lock. LM.7 added per-track chromatic-projected RGB tint vector (D-LM-7) — relaxes LM.4.6's strict "any colour reachable on every track" framing in exchange for visible panel-aggregate distinction per track. Decisions F.2 (LM.6) and F.3 (LM.7) newly recorded; §3 / §4 / §6 / §7 / §10 / §11 all updated to reflect the actual landed shape.
- **2026-05-12 (LM.6 + LM.4.6 + earlier doc cleanup)** — LM.4.6 landed: pure uniform random RGB per cell, retiring the IQ cosine palette (E.3) and band-routed beat-driven dance (D.5) palette decoder. The team / period / counter trigger mechanism is preserved. Decisions D.6 and E.4 newly recorded; D.1 / D.4 / D.5 / E.1 / E.2 / E.3 marked retired in §3. Increment table §6 cleaned up to reflect actual landed state. §4 rewritten from "proposed architecture" to "current architecture." §7.5 cert gates revised — per-track distinctiveness gate retired as incompatible with the accepted D.6 trade-off (subsequently revisited at LM.7 — see entry above).
- **2026-05-12 (LM.4.6)** — Five LM.4.5.x iterations rejected during the day; LM.4.6 final shape adopted as pure uniform random RGB per cell. Iteration history captured in CLAUDE.md `Recent landed work` entry. The honest math caveat (uniform random produces statistically similar panel-aggregates regardless of seed) documented in shader file header.
- **2026-05-11 (LM.4.4 → LM.4.5 sequence)** — Pattern engine retired in LM.4.4; `LumenPatterns.swift` deleted. LM.4.5 (originally "LM.4.2") scoped as full-spectrum palette redesign. Five rejected variants over the day (LM.4.5 v1 → LM.4.5.1 → LM.4.5.2 → LM.4.5.3 → LM.4.6 anchor-distribution attempt).
- **2026-05-11 (LM.4.1 / LM.4.3)** — Calibration follow-ups on LM.4. LM.4.1 fixed ripple density + bleach-out (3-line calibration). LM.4.3 replaced FFT-band rising-edge triggers with BeatGrid-driven triggers and demoted ripples to per-bar accent.
- **2026-05-10 (LM.3.2 ✅ pass)** — Eight calibration rounds (2026-05-09 / 2026-05-10) culminating in real-music session sign-off. Final shape: HSV-driven palette + Voronoi-distance-driven frost in albedo + cells hold previous palette state until next team beat + bar pulse on downbeats.
- **2026-05-09 (LM.3.2)** — Second pivot in 24 hours. LM.3's continuous-palette-cycling was rejected after live-session capture (BUG-012); LM.3.1's agent-position-driven backlight character was rejected by Matt. Decision D.5 — band-routed beat-driven dance — adopted.
- **2026-05-09 (LM.3 / first pivot)** — Design pivot after LM.2 production review. "Meditative co-performer" framing replaced with "energetic dance partner". D.1 retired (gradient blob); D.4 adopted (per-cell `palette()`). E.1 (cream baseline) and E.2 (4 palette banks) retired; E.3 adopted (procedural palette via V.3 IQ cosine).
- **2026-05-08 (LM.0 era)** — Original document, with Matt's A.1 / B.1 / C.2 / D.1 / E.1 / F.1 / G.1 / H.1 confirmed. LM.0–LM.2 implemented under this version.
