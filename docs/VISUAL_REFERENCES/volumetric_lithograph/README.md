# Visual References — Volumetric Lithograph

**Family:** geometric *(matches the JSON sidecar; the old README header said `fluid` — that drift is fixed here)*
**Render pipeline:** `ray_march + post_process` — geometry-space folds only. **No mv_warp** (D-029: its UV-space accumulator fights the moving camera and smears; the documented VL revert).
**Rubric:** full
**Last curated:** 2026-07-23 by Claude Code, approved by Matt (VL.1)

> **This set replaces the naturalistic / linocut set**, which was archived to
> `_superseded_naturalistic/` at VL.1. That direction (drainage relief, Hokusai, aerial
> perspective) is now an **anti-reference** — see below. Concept of record:
> `docs/presets/VOLUMETRIC_LITHOGRAPH_DESIGN.md`.

---

## Hero reference — **link-only** (Matt's call, VL.1)

The identity — *an endless forward flight through a landscape whose geometry folds and
kaleidoscopes* — is a demoscene/Shadertoy genre. Those frames are copyrighted, so they are
**cited, not committed**. Load them before judging whether a VL render is on-concept:

| Anchor | URL | What to take from it |
|---|---|---|
| **KIFS Flythrough** — Shane | https://www.shadertoy.com/view/XsKXzc | The hero. A camera *travelling through* a kaleidoscopic IFS structure — folded geometry that stays legible as a place you move through, not a texture. This is the motion identity. |
| **Fractal Land** — Kali | https://www.shadertoy.com/user/Kali | Flight *over* a folding fractal landscape — the "terrain, not solid" half of the identity. *(Exact view-ID unverified — Shadertoy blocks automated fetch; find it on Kali's author page.)* |
| **Playing with Kaleidoscopic IFS** | https://www.shadertoy.com/view/M3fXWl | How fold depth and symmetry order change the *character* of a folded field — the vocabulary the swell→fold-depth route is modulating. |

**These are LOOK anchors, not port targets.** The fold math is ported from canonical
`hg_sdf.glsl` (`pModPolar` / `pModMirror2` / `pReflect`), per the design doc §Open-decisions #1.
Do not derive geometry from these shaders — that is the FA #65 failure.

---

## Committed reference images

Numbered in priority order. **Each carries a trait-trustability annotation — take only the
named trait from each image.** Both were assessed by looking at the actual file, not the
stock-site description (the descriptions were wrong on both counts).

| File | Take this | **Disregard this** |
|---|---|---|
| `01_macro_kaleidoscope_symmetry.jpg` | **Radial-symmetry structure.** ~12-fold repeat with *crisp, legible seams* and a clear centre — petals read as distinct shapes, not symmetric mush. This is the target for what `pModPolar` should produce, and for the per-downbeat symmetry snap: the order must be *readable* at a glance. | ⚠️ **The palette. This image is pale** — a chalky off-white ground with teal/orange accents. VL's brief is the opposite (§6: mind-altering, saturated, flowing hue). Grading VL's colour against this image would drive it straight into the pale-tone failure the quality floor caps at 30 %. |
| `02_meso_domain_warp_flow.jpg` | **Domain-warp character.** Nested contour banding, smooth folded flow, structure that reads as *one continuously distorted field* rather than separate blobs — exactly what `warped_fbm` should do to the heightfield under the swell. | ⚠️ **The hue range.** It is two-tone (acid green + black). VL needs hue that *flows* across the frame and over time. Saturation level: yes. Hue vocabulary: no. |
| `03_palette_iridescent_hue_flow.jpg` **← palette hero** | **Continuous saturated hue flow.** The full spectrum sweeps across the frame — magenta → peach → cyan → violet → blue — and critically the **colour joins stay clean**: neighbouring hues meet without going muddy. Dark regions keep it from washing out. This is §6's "mind-altering" target: not more colours, but hue that *travels* and stays saturated where it transitions. | ⚠️ **The tar.** The black bituminous blobs are grungy surface texture, not a palette instruction. Take the iridescent film. |
| `04_palette_radial_colour_delaunay.jpg` | **Hue organised by angle.** Colour segmented around a disc by both angle and radius — structurally what an IQ cosine palette does when driven through a `pModPolar` fold. Teaches the palette and the symmetry together: this is what "colour washing across the folded landscape" should look like laid flat. | ⚠️ **The outer field goes chalky** (pale pink/lilac). Take the central disc's vividness, not the periphery's tone. Also: a 1913 oil painting has brushwork and a canvas ground — neither is a VL surface instruction. |

---

## ⚠️ Curation holes (state honestly, do not paper over)

- **`palette` slot — CLOSED at VL.1** by `03` (continuous hue flow) + `04` (angular colour
  organisation). They cover different halves; neither substitutes for the other.
- **`lighting` / `specular` slots — NOT CURATED.** How a folded surface should catch light
  without going muddy has no committed anchor. Judgments there rest on the design doc's prose
  and the link-only anchors until this is filled.

These are real gaps, not formalities. The previous README shipped for months with a
never-sourced anti-reference it openly called "the hole in the curation set"; naming holes
explicitly is how that stops being invisible.

---

## Mandatory traits (per SHADER_CRAFT §12.1)

- [ ] **Detail cascade**
  - **macro** — kaleidoscopic / mirror folds (`pModPolar`, `pModMirror2`, `pReflect`) applied to
    the domain *before* the heightfield eval, over the fBM substrate. Read against `01` for
    symmetry legibility.
  - **meso** — organic domain warp (`warped_fbm` / `warped_fbm_vec`, Quilez) deforming the folded
    field. Read against `02`.
  - **micro** — fine surface variation churned by `spectral_flux`.
  - **specular** — ≥ 3 materials (SHADER_CRAFT floor). No committed anchor — see holes above.
- [ ] **Palette (§6):** hue **flows** continuously with melody + `accumulated_audio_time`; wide
      range; saturated *through the transitions*, not just at the stops. Read against `03` for the
      flow and `04` for how hue should map around a fold. Pale-tone coverage stays ≤ 30 %
      (SHADER_CRAFT floor) — `01` is the cautionary example, not the target.
- [ ] **Hero noise:** fBM heightfield substrate + `warped_fbm` domain warp; folds are hg_sdf
      operators, not noise.
- [ ] **The flight must stay load-bearing.** VL's identity is *a landscape you travel through*.
      If the dolly stops mattering, VL has collapsed into a static psychedelic geometry preset —
      see anti-references.
- [ ] **Audio reactivity** — one primitive per layer (FA #67), per the design doc §4 routing
      table: swell → fold depth + warp amount; `features.bass` → dolly speed **only**;
      downbeat (`bar_phase01`) → coordinated lurch + symmetry snap; `spectral_flux` → micro churn;
      melody + `accumulated_audio_time` → hue flow.
- [ ] **Silence (D-037):** non-black. A calm, slow-breathing low-order symmetric field with gentle
      hue drift. **Known gap:** VL is currently *frozen* at silence (0 bits frame-to-frame drift
      over 60 frames — `accumulatedAudioTime` is energy-gated). Measured at VL.1; unfixed.
- [ ] **Performance:** Tier-2 ceiling ~5.0 ms p95 @ 1080p. Folds add march cost and can hurt SDF
      Lipschitz continuity — watch `VL_SDF_STEP_SCALE` (currently 0.6).

---

## Anti-references — what VL must NOT look like

- **The old VL: naturalistic terrain with aerial haze.** Every image in
  `_superseded_naturalistic/` is now an anti-reference. `01_macro_drainage_relief.jpg` and
  `06_atmosphere_aerial_perspective.jpg` are the sharpest: if a VL render reads like either, it
  has reverted to the direction Matt rejected on 2026-07-23 ("a topographic map that adds and
  removes depth"). `scene_fog` stays 0; no aerial perspective, no `ridged_mf` drainage, no cloud
  shadows.
- **Mandelbox Cathedral / the retired Fractal Fly-By (D-201).** ⚠️ The nearest conceptual trap. It was a fractal
  **solid** the camera travelled through — and it was retired precisely because a fast fly-through of dense
  self-similar detail cannot render coherently in the real-time budget (the image boils frame-to-frame). VL
  is a **landscape** the camera flies over. If VL's ground stops reading as ground, it has become
  "Mandelbox Cathedral with a moving camera" — the collapse the design doc §1 names by name, and the failure mode that killed Fly-By.
- **Flat neon screensaver strobe.** Saturation without structure. `02` sits near this line —
  take its *flow*, not its flatness. Luminance must stay steady per beat (D-157).
- **Muddy over-blended smear.** The failure mode of stacking too many warps: everything folds into
  everything and no shape survives. If the symmetry order in `01` would be uncountable in a VL
  frame, the warp has gone too far.
- **mv_warp / screen-space feedback of any kind** (D-029). Not a taste call — a documented smear
  regression on this specific preset.

---

## Provenance

| File | Source | Licence |
|---|---|---|
| `01_macro_kaleidoscope_symmetry.jpg` | Unsplash — Marija Zaric (@simplicity), photo `ytTjSH9-MOE` | Unsplash License (free commercial use, attribution not required; credited for transparency) |
| `02_meso_domain_warp_flow.jpg` | Unsplash — Logan Voss (@loganvoss), photo `6bvTt1MM-3U` | Unsplash License (as above); recompressed to fit the ≤ 500 KB house limit |
| `03_palette_iridescent_hue_flow.jpg` | Unsplash — Yuriy Vertikov, photo `8xrEJe3tkuc` | Unsplash License (as above); recompressed |
| `04_palette_radial_colour_delaunay.jpg` | Robert Delaunay, *Circular Forms, Sun No. 1*, 1912–13, Wilhelm-Hack-Museum — via Wikimedia Commons | Public domain (published before 1930; Delaunay d. 1941); recompressed |
| `_superseded_naturalistic/*` | Unsplash + public-domain artworks — see git history of this file for the original per-image credits | Unsplash License / public domain |
