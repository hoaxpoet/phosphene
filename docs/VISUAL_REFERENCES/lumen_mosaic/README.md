# Lumen Mosaic — Visual References

**Family**: `geometric` (pattern-glass sub-class; the `glass` framing in the original reference set drifted toward the final `geometric` classification in `LumenMosaic.json`).
**Role**: energetic dance partner — vibrant per-cell colour field synced to the beat. The original "meditative co-performer / still-and-shift" framing in this README was aspirational; the preset as it certified at LM.7 (2026-05-12) reads as a kinetic dance register (see Decision A.1 / aesthetic role section of `LUMEN_MOSAIC_DESIGN.md` §1). Quiet moments preserve the still-and-shift character (silence fallback holds the static `(cellHash, 0, trackSeed, 0)` colour).
**Status**: **CERTIFIED 2026-05-12** at LM.7. `LumenMosaic.json` `certified: true`. First catalog preset to land cert.
**Authoring docs**: `LUMEN_MOSAIC_DESIGN.md` (design intent + current implementation), `Lumen_Mosaic_Rendering_Architecture_Contract.md` (current-implementation summary + historical LM.3.2 prose), `LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md` (phased increments). All three live at `docs/presets/`, not in this folder.

This README is the visual contract Claude Code sessions read before authoring the preset. It is rubric-bearing per D-064 (full-rubric variant). The design doc and contract are the authoritative source for everything beyond visual fidelity.

**Drift correction note (2026-05-12).** Several anti-reference notes below describe stale architecture (LM.2-era "4-light agent system"; LM.3-era "stem-driven colours from 4 light agent positions"). The actual landed architecture at cert (LM.7) is per-cell uniform random RGB (LM.4.6) + LM.6 cell-depth gradient and hot-spot (albedo modulations driven by Voronoi `f1/f2`) + LM.7 per-track chromatic-projected tint vector (`trackPaletteSeed{A,B,C}`-derived). The 4-light agent struct stays on the GPU buffer for ABI continuity but the shader does not read it. Per-track palette identity comes from the `trackPaletteSeed` plumbing, not stem energies. The trait matrix and anti-reference text below should be read with this context in mind.

---

## Provenance

| File | Source | Date | Notes |
|---|---|---|---|
| `04_specular_pattern_glass_closeup.jpg` | User-uploaded by Matt (Unsplash) | 2026-05-08 | Hero composite. External photo of architectural hammered pattern glass under multi-source colored backlight. Carries macro / meso / micro / specular / lighting traits simultaneously. |
| `02_meso_pebbled_glass_directional.jpg` | Annie Spratt (Unsplash) | 2026-05-08 | Meso/micro reference. Monochrome pebbled pattern glass under raking directional light. Cell relief unambiguous; isolates dome+ridge trait without color confusion. |
| `05_lighting_pattern_glass_dual_color.jpg` | Jason Leung (Unsplash) | 2026-05-08 | Lighting reference. Hex-biased pattern glass with two distinct backlit color zones (warm orange-amber + cool teal/white) simultaneously visible. Reinforces hero's multi-source-backlight target trait. |
| `09_anti_stained_glass_cliche.jpg` | Mr. Great-Heart (Unsplash) | 2026-05-08 | Anti-reference. Tiffany-style decorative floral stained glass. Failure mode #4 (cathedral/iconographic cliché). |

No AI-generated images present.

---

## Reference annotations

### `04_specular_pattern_glass_closeup.jpg` — hero composite

The user-supplied photograph of hammered pattern glass with multi-color backlight. Carries the macro / meso / micro / specular trait stack simultaneously; the supplemental references below isolate individual traits but this image is the canonical visual contract. Filed in slot 04 per Arachne's convention (slot 04 = specular trait, where this image's defining property — colored backlight emission through cellular dimples — most strongly lives).

**Mandatory** (the preset must reproduce these properties — every contact sheet must read as the same kind of surface):
- Hex-biased Voronoi cell pattern filling the entire visible frame, ≈50 cells across at the authoring aspect ratio.
- Sharp inter-cell ridges with thin dark seams between cell faces; ridges read as creases, not soft transitions.
- Each cell appears as a raised dimple. **Implementation note (LM.6 / D-LM-6):** the reference image's per-cell normal perturbation is approximated in Lumen Mosaic by albedo-only modulation — the LM.6 cell-depth gradient `cell_hue *= mix(0.55, 1.0, depth01(f1, f2))` produces a centre-bright / edge-dark gradient that reads as a domed cell without normal-driven shading. The SDF normal stays flat (`kReliefAmplitude = 0`) per the LM.3.2 round-7 / Failed Approach lock that retired normal-driven specular paths after per-pixel dot artifacts. The PANEL itself is flat (`sd_box`); the cell relief is albedo-shading-only.
- In-cell frosted micro-texture producing visible centre-brightness ("specular-like") sparkle. **Implementation note (LM.6 / D-LM-6):** the reference image's specular sparkle is approximated by the LM.6 optional hot-spot — a per-pixel `pow^4` brightness boost (`cell_hue += pow(1-smoothstep(0, 0.15×f2, f1), 4.0) × 0.30 × cell_hue`) additive on the cell's own hue (not toward white). The matID==1 lighting path does NOT invoke Cook-Torrance; LM.6 is per-pixel albedo shading, not a normal-driven specular pass.
- Multiple distinct backlit color zones simultaneously visible across the panel face.
- Glass reads as **emission-dominated** when backlit — bright cells "glow" rather than merely reflect (matID == 1 emission-dominated path; contract §sceneSDF/sceneMaterial).

**Decorative** (welcome to match but not required, no rubric weight):
- The exact cell count, orientation, or aspect ratio shown in this particular photo.
- The specific cool-blue / warm-orange / red palette of the visible backlights.
- Overall photographic contrast and tonal balance of the reference.
- The specific positions and intensities of the visible specular hot spots.

**Actively disregard** (D-064 (c) — these are properties of the photograph that the preset MUST NOT inherit):
- **The static dark vertical occluder visible center-frame.** Deferred to LM.5 / Decision B.2 per design doc §3. Do not implement it as a fixed structural element of the panel during LM.1–LM.4. If LM.5 reintroduces silhouettes, they will be audio-coupled or animated, never frozen as in this still photo.
- **The specific colors and positions of the visible backlights.** Lumen Mosaic's lights are an audio-driven 4-agent system that move continuously and shift color with mood (contract §P.2 + §P.4). The reference's static color geometry is incidental to the moment of capture.
- **The fixed composition.** Lumen Mosaic is a moving visualization in which lights dance behind the glass in sync with the beat (contract §P.4). This reference is a still photograph; nothing about its stillness is a directive.
- **The particular cell rotation / orientation / aspect ratio of cells.** The Voronoi seed lattice is preset-internal (constructed by `voronoi_f1f2` on a uv grid) and is not constrained by this image.
- **Visible dust, micro-scratches, fingerprints, or photographic artifacts** on the actual glass surface in the reference.
- **Specific contrast / exposure / film grain.** The preset's tonal range is determined by ACES tonemapping + bloom + IBL ambient floor, not by matching this photo's exposure.
- **Any inference of panel curvature.** The hero is photographed of a flat sheet of glass; if any subtle curvature reads in the photo (e.g. lens distortion, parallax across cells), it's photographic, not a directive. The Lumen Mosaic panel SDF is a flat `sd_box`.

---

### `02_meso_pebbled_glass_directional.jpg` — meso/micro isolation

Pebbled pattern glass under raking directional light from upper-left. Higher cell density than the hero. The directional lighting makes the per-cell dome+ridge relief unambiguous in a way the hero (lit straight-on) only implies. Monochrome — no color confusion at this slot.

**Mandatory** (this reference is the primary anchor for these traits):
- Per-cell raised dimple structure: each cell catches light on its upper edge and shadows on its lower edge under directional illumination. This is the dome+ridge topology that the V.3 height-gradient recipe produces.
- Sharp, narrow ridges between cells — bright specular catches at ridge crests, not soft transitions.
- Cellular pattern is **coherent** (recognizable per-cell) at multiple zoom levels. Even at this image's higher density (smaller cells per frame), the per-cell character is preserved, not washed out into noise.
- In-cell micro-texture (frost) is visible at the sub-cell scale: each cell face has fine bumpy character, not a smooth surface.

**Decorative**:
- The exact gradient direction (upper-left → lower-right). The hero is lit differently and that's fine.
- The specific cell density. Lumen Mosaic targets ≈50 cells across at scale=30 (Decision C.2); this reference is at higher density.
- The desaturated / monochrome palette. This reference is intentionally colorless to isolate the relief trait; Lumen Mosaic is fully colored.
- The slight vignetting at the corners.

**Actively disregard**:
- **The photographic gradient lighting.** This is a key-light from one direction; the preset's lighting comes from 4 audio-driven agents behind the panel. The disjoint between "raking from upper-left" in this image and "multiple sources behind" in the preset must NOT confuse Claude Code into placing fixed directional lights above the panel.
- **The visible dust speck near mid-frame.** Photographic artifact, not a feature.
- **Slight banding from JPEG compression** in the smoothest tonal regions. Procedural rendering produces no such artifact; do not attempt to simulate it.
- **The specific cell size in absolute pixels.** Cell density in Lumen Mosaic is JSON-tunable via `lumen_mosaic.cell_density`; this reference is one example point, not a target.
- **The lower-right shadow region's tonal dropoff to dark.** Lumen Mosaic's panel is fully emission-dominated everywhere — no truly dark regions of panel are permissible at any moment.

---

### `05_lighting_pattern_glass_dual_color.jpg` — multi-source backlight target

Hex-biased pattern glass with two distinct backlit color zones (warm orange-amber on the left, cool teal/white on the right). Reinforces the hero's "multiple color zones simultaneously visible" trait with a clearer two-color split.

**Mandatory**:
- Two (or more) distinct color zones can occupy the same panel face simultaneously, with cells in each zone reading as that zone's color quantized through the cell pattern.
- Color transitions between zones are gradual at the cell scale — adjacent cells take on intermediate colors where light from two sources mix, but each individual cell is still color-coherent (not dithered).
- Hex-biased Voronoi-like cellular structure remains visible across both color zones.

**Decorative**:
- The specific orange-vs-teal palette split. Lumen Mosaic's colors are mood-driven and stem-driven; this image is one example of a two-color state, not the canonical palette.
- The vertical orientation of the color split. Lumen Mosaic's color geometry is determined by 4 light agent positions (drums upper-left, bass center-low, vocals center-mid, other upper-right per contract §P.2).
- The desaturation of the right side (light cool teal verging on neutral white). Lumen Mosaic's silence fallback is a desaturated mood-tinted ambient (D-019); active states have more saturated cell colors.
- The specific cell density.

**Actively disregard**:
- **The visible wooden window frame at the bottom of the image.** Per Decision G.1 the Lumen Mosaic panel extends 50% beyond the visible frame on every side; no panel boundary or frame is ever visible in any preset frame at any aspect ratio. The horizontal frame here is exactly what the preset must NOT show. **This image doubles as a Mandatory rubric anchor for "panel-edge invariant" — it shows the failure case.**
- **The specific positions of the colors (orange-left, teal-right).** Light agent positions in Lumen Mosaic move continuously per contract §P.4 (drift + beat-locked dance + bar pattern offset).
- **Any apparent imagery visible through the glass at the top center** (landscape, sky, etc.). Lumen Mosaic's panel is opaque emission-dominated dielectric; nothing is "visible through" the panel — there is no scene behind the glass, just an analytical light field.
- **The hard split between color zones.** Light agent intensity falloff in the preset is smooth (1/r² with tunable falloff_k per agent, contract §P.3); transitions between agent zones blend through cell-quantized intermediate colors.
- **The fixed composition.** Static state in a still image, not a directive about preset behaviour.

---

### `09_anti_stained_glass_cliche.jpg` — anti-reference (failure mode #4)

Tiffany-style decorative floral stained glass. **Every trait of this image is anti.** This is what failure mode #4 (design doc §5.1: "stained-glass cathedral cliché — saturated primaries in fixed iconographic arrangement") looks like. If a contact sheet starts to resemble this image, the preset has failed.

**No mandatory list, no decorative list — every trait is anti:**
- Decorative iconography (recognizable flowers, leaves, branches) — Lumen Mosaic must be abstract; no recognizable forms ever emerge from cell color patterns.
- Hand-cut piecewise glass shapes locked into a fixed composition — Lumen Mosaic's cells are procedural Voronoi, regular in scale, irregular in shape, with no privileged composition.
- Heavy, continuous lead caming visible as bold black outlines around every shape — Lumen Mosaic's cell ridges are thin sharp seams (sub-pixel-to-1px wide), not heavy outlines.
- Saturated primary palette (saturated reds, greens, yellows, white-cream) — Lumen Mosaic's palette is mood-driven; saturated primaries occur only at peak HV-HA moods, never as the default character.
- Fixed visual composition that does not change — Lumen Mosaic is animated; the visual identity is *the dance*, not the still pattern.
- Multiple distinct curved organic shapes (leaves, petals, branches) at large scale — Lumen Mosaic's only structural element is the cell pattern; there are no superimposed shapes.
- Flat shading within each glass piece — Lumen Mosaic's cells have per-cell shading relief (dome+ridge); each cell catches light differently across its face.

If asked "is this what Lumen Mosaic should look like?" the answer is always **no, never, this is what it must avoid.** No partial-trust read of any visual property.

---

## Curation slots — open (TBD by Matt)

The 4 references above (1 hero composite + 2 trait isolators + 1 anti) cover D-066's "3–5 typical" range and exercise all rubric mandatory items. Additional references are welcome but not required:

| Slot | Purpose | Notes |
|---|---|---|
| `01_macro_*` | (open) Wider shot showing macro composition at lower density-per-frame. | Optional; the hero (slot 04) already carries macro trait. |
| `03_micro_*` | (open) Extreme close-up of frosted / dimpled glass micro-texture (sub-cell scale). | Optional; would help LM.6 frost amplitude/scale tuning. |
| `06–08`, `10+` | (open) In-engine v1+ frame captures once LM.4 lands, used as forward-progression references. | Add post-LM.4 if useful. |

Slots can be skipped — they don't need to be contiguous. CheckVisualReferences --strict will pass against the current 4-image set.

---

## Anti-reference policy

This folder currently has 1 anti (`09_*`). Per D-065:
- AI-generated anti-references would carry the `_AIGEN` suffix in the filename and require Provenance + replacement-plan annotation. None present.
- Real-photograph anti-references (such as `09_*` here) require no special suffix.

Additional antis welcome if a different failure mode benefits from visual representation:
- Failure mode #1 (flat stained glass without specular variation) — could be illustrated by a flat tinted glass photo.
- Failure mode #2 (TV-static / per-pixel noise without cell coherence) — non-photographable; would require `_AIGEN` per D-065 carve-out.
- Failure mode #3 (photo-of-glass — no audio reactivity visible) — by definition not expressible as a single image; addressed by motion in contact sheets, not a static reference.

---

## Rubric (mirrors `SHADER_CRAFT.md §12`, instantiated for Lumen Mosaic)

Refer to `SHADER_CRAFT.md §12` for the global rubric definition. The items below are the Lumen-Mosaic-specific instantiation. Numbers in parentheses cross-reference design doc §6 acceptance criteria.

### Mandatory (7/7 — Lumen Mosaic certified 2026-05-12 at LM.7; criteria met)

1. **Detail cascade present.** All four detail scales visible in the steady-fixture contact sheet: macro Voronoi composition + meso LM.6 cell-depth gradient (centre→edge brightness from `mix(0.55, 1.0, depth01(f1, f2))`) + micro frost (Voronoi-distance diffusion) + LM.6 hot-spot (centre 30 % brightness pinpoint additive on cell's own hue). Reference anchors: `04_*` (composite); `02_*` (dome/ridge under raking light). Implementation cascade is albedo-only — no normal-driven specular pass invoked on matID==1.
2. **≥4 octaves of noise in hero surface.** `fbm8(p * 80)` for in-cell frost provides 8 octaves; documented in `LumenMosaic.metal` `sceneMaterial`.
3. **Audio reactivity via deviation primitives only.** `f.*_att_rel`, `f.*_dev`, `stems.*_rel`, `stems.*_dev`. **Zero raw `f.bass` / `f.mid` / `f.treble` reads** (D-026). Verified by `grep -n 'f\.bass[^_]\|f\.mid[^_]\|f\.treble[^_]' LumenMosaic.metal LumenPatternEngine.swift` returning empty.
4. **D-019 silence fallback present and tested.** At silence, the panel reads as a quiet mood-tinted ambient (non-black, visually coherent). Verified in silence-fixture contact sheet and `LumenPatternEngineTests` warmup test.
5. **D-020 architecture-stays-solid.** Panel SDF is audio-independent. No raw audio values reach `sceneSDF`. Only light positions / colors / intensities, atmosphere, and per-cell emission change with audio. Per-cell shading relief (dome+ridge) is also fixed — only emission color and intensity vary per cell, never the cell shape or position.
6. **Panel-edge invariant.** No panel boundary visible in any frame at any aspect ratio (16:9, 4:3, 21:9). matID == 0 channel empty across full frame. Per Decision G.1 and contract §P.1. **Anti-anchor: `05_*` shows exactly the failure of this invariant (visible window frame at bottom).**
7. **Performance budget met.** p95 ≤ 3.7 ms at Tier 2 over a 30 s capture against a beat-heavy fixture. Target: cheapest ray-march preset in the catalog.

### Expected (≥ 2 / 4 — Lumen Mosaic certified at LM.7; criteria met as actually landed)

The original Expected items below were authored against the LM.2-era 4-agent-system architecture (since retired); they are preserved for the increment history with corrected actual-landed-shape notes.

1. **Beat-locked dance verifiable by eye.** ✅ **As shipped (LM.3.2+):** per-cell *colour change* (not agent position) advances on each band-team's beat counter. Bass-team cells step on kicks; mid-team on melody; treble-team on hats. Verified by Matt at LM.3.2 sign-off (2026-05-10) and re-verified at LM.7 cert sign-off (2026-05-12).
2. **Mood-quadrant palette differentiation.** ⚠ **Retired by LM.4.6 / LM.7.** Mood-coupled palette parameters were retired in LM.4.6 (`f.valence` / `f.arousal` are unused). LM.7 added per-*track* palette differentiation via the chromatic-projected RGB tint vector — different tracks have visibly different aggregate panel means. Cross-mood differentiation within a single track is no longer a gate.
3. **Pattern variety over time.** ⚠ **Retired by LM.4.4.** The pattern engine (ripples, sweeps, etc.) was retired entirely after Matt's third M7 review found the wavefronts invisible against the simultaneous bar pulse. Time-evolution variety comes from the LM.3.2 team-counter dance + the LM.4.6 section-salt mutation (`bassCounter / 64`) + the LM.7 per-track tint vector.
4. **Cross-genre legibility.** ✅ Verified at LM.7 cert against the canonical 5-track playlist (Love Rehab / So What / There There / Pyramid Song / Money — electronic / jazz / rock / experimental 16/8 / progressive rock).

### Strongly preferred (≥ 1 / 4 — Lumen Mosaic certified at LM.7)

The original Strongly Preferred items below were authored against the LM.2-era architecture; preserved for history with actual-landed-shape notes.

1. **Per-stem hue separability.** ⚠ **Retired by LM.3.2+.** Stem-driven per-cell hues were retired with the agent-driven backlight character. Stem coupling now routes via the LM.3.2 band-counter mechanism (each cell belongs to a bass / mid / treble / static team and advances on its team's beat) and the LM.7 per-track tint (FNV-1a hash of "title | artist" drives the chromatic shift, not stem energies).
2. **Chromatic aberration on cell-edge ridges.** ⊘ Not in current implementation. LM.6 hot-spot covers the centre-highlight character; cell-edge ridges are styled via frost diffusion (white-mixing at small `f2-f1` distances), not CA.
3. **Aspect-ratio robustness verified.** ✅ Panel-edge invariant verified at LM.7 cert. The panel `sd_box` half-extents stay at `cameraTangents.xy × kPanelOversize (1.50)` — bleeds 50 % past visible frame on every side per Decision G.1.
4. **Silhouette occluder depth.** ⊘ Decision B.2 retired with the rest of the 4-agent / behind-glass architecture. The panel is fully emission-dominated everywhere; no behind-glass scene was added.

---

## Notes for Claude Code sessions

1. **The panel itself is flat geometry** (`sd_box` per `sceneSDF`, no curvature, no audio-driven deformation). All raised-cell character comes from per-cell normal perturbation in `sceneMaterial`. References in this folder show pattern glass surfaces; "raised dimple" terminology refers to per-cell shading relief, NOT panel-level curvature.
2. **Mandatory traits are non-negotiable.** The rubric Mandatory items derive from them. Failing any mandatory trait blocked certification at LM.7 sign-off (the preset has since certified — see Status header).
3. **"Actively disregard" is not interpretive.** Each item is a property of the reference photograph that must NOT be ported to the preset. If Claude Code finds itself reasoning "but the reference clearly shows X, so the preset should also have X," and X is in the Disregard list, the right action is to not implement X and document the disregard in the increment commit message.
4. **When the README and the design doc / contract conflict, the design doc / contract win.** This README is a visual quick-reference; `LUMEN_MOSAIC_DESIGN.md` and `Lumen_Mosaic_Rendering_Architecture_Contract.md` are the authoritative source. Conflicts indicate this README needs a corrective edit.
5. **Contact sheets land here.** Per-increment review evidence at `contact_sheets/LM.X/`. Do not delete prior LM folders — they form the visual changelog and are referenced by Matt's review at later increments.
6. **`CheckVisualReferences --strict` must pass.** Run `swift run --package-path PhospheneTools CheckVisualReferences --strict` after any change to this folder. The 5 lint rules per D-064 are non-negotiable.
