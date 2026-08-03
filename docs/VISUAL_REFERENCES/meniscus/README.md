# Visual references — Meniscus

**Preset:** Meniscus (`milkdrop_inspired`)
**Inspiration source:** `Martin - QBikal - Surface Turbulence IIb` (cream-of-the-crop pack; butterchurn JSON)
**Curated:** 2026-08-03, prep seat (Matt + Claude), from `~/mdrender/gallery/`
**Design doc:** [`docs/presets/MENISCUS_PLAN.md`](../../presets/MENISCUS_PLAN.md)

---

## Read this first — what kind of reference set this is

**Every image in this folder is a render of the source preset, not an aspirational
target.** That makes this set unusual, and it changes how you must use it.

These frames are the **concept oracle**: they show what the source preset *is*, so
you can decide what Meniscus keeps and what it deliberately does differently. They
are **not** the fidelity bar — under D-116 / D-121, Meniscus's rendered output is
*required* to diverge measurably from these frames on at least one named axis. The
divergence axis for Meniscus is the **primary feature stack** (see `MENISCUS_PLAN.md`
§5). Matching these frames pixel-for-pixel would be a certification *failure*, not a
success.

So: trust these images for **structure, motion vocabulary, and shading logic**.
Do not treat their palette or their audio coupling as a target.

The source oracle also has real defects (silence renders black; the drop placement
is inaudible). Those are called out per-image below and collected in §Anti-references.

**No `.milk` / `.json` source content is redistributed** (D-116 bullet 4). The source
lives at `~/mdrender/builtins/` on the dev machine only; its decode lives in
`MENISCUS_PLAN.md` §3 as prose, not as copied equations.

---

## Mandatory traits checklist

A Meniscus render is failing if any of these is absent:

- [ ] **T1 — The surface is drawn as separated contour lines, not a shaded solid.**
      A single continuous polyline snaking back and forth across the grid (serpentine
      / boustrophedon row order), so alternate rows are traversed in opposite
      directions and joined by a turnaround at each edge. The rounded turnaround caps
      at the left and right margins are a signature, not an artifact — see `07`.
- [ ] **T2 — Perspective, from a low oblique angle.** The plate recedes; near rows are
      widely spaced, far rows compress toward a vanishing band. A top-down or
      orthographic view destroys the register.
- [ ] **T3 — Brightness comes from local slope, not from height alone.** Crests read
      near-white, troughs read near-black, and the transition is *sharp* — that
      slope-derived specular is what makes a field of lines read as a liquid surface.
- [ ] **T4 — Localized disturbance on an otherwise calm field.** At any moment most of
      the surface is quiet and one or two regions are actively rippling. A uniformly
      agitated surface reads as noise.
      *Not assessable before MEN.2b* — this trait depends on drop impacts, and MEN.2a
      ships with no audio coupling at all. Mark it `deferred — MEN.2b` in any MEN.2a
      closeout rather than guessing. At MEN.2b it is judged against the source render;
      at MEN.3 it is judged against the MEN.2b faithful base, since the stem-region
      scheme changes the drop distribution that produces it.
- [ ] **T5 — The plate floats in a dark void over a separate textured ground.** Two
      distinct spatial layers: the line surface, and a grainy dark plane far below it.
      The gap between them is what gives the composition its depth.
- [ ] **T6 — A single cool light source off to one side.** One directional glow
      (teal/cyan in the source) grazing the surface, everything else falling to near
      black. Not ambient, not multi-light.

---

## Per-image annotations

### `01_wide_hero_scanline_raster.png` — **the primary reference**
640×480 still from the mdrender gallery. This is the frame the whole preset is
organized around.

- **Trust:** T1 (the serpentine polyline is unambiguous here — count the turnarounds
  on the left edge), T2, T3, T4 (one central vortex-like disturbance, rest calm), T6.
- **Trust: line weight and separation.** Lines are ~1px core with a horizontal smear;
  spacing is wide enough that the black between them is a real part of the image.
  This is the "open raster" register Matt selected as the hero look.
- **Do NOT trust: the palette.** Near-monochrome white-on-teal is the source's
  choice. Meniscus's palette is an open authoring decision (`MENISCUS_PLAN.md` §6).
- **Do NOT trust: the flat, plateau-like plate profile.** The surface here is almost
  entirely flat with one dent. Meniscus's silence state is a slow standing swell
  (Matt's call), so the calm baseline should have gentle long-wavelength motion in it.
- **Note:** the warm amber in the deep trough is not a second light — it is the
  source's height→hue term reading low. Worth keeping as a *concept* (deep = warm,
  crest = cool); the specific colours are ours to choose.

### `02_wide_open_raster_teal_sky.png` — hero look, in motion
GIF frame 57, upscaled. Same register as `01` at a shallower camera angle.

- **Trust:** T1, T2, T6, and the **one-dimensional glow smear** on the lines — the
  source spreads each line along screen-space X only, never vertically, which is why
  the lines stay crisply separated in Y while reading soft in X. That asymmetry is
  load-bearing; an isotropic bloom will close the gaps and collapse the raster into a
  solid sheet. (Whether Phosphene spreads along screen X or along the line's own
  tangent is open — see anti-reference 5.)
- **Trust: the sky gradient.** A single soft gradient wash from the light side,
  falling to black. Not a skybox, not stars, not clouds.
- **Do NOT trust: the resolution.** Upscaled from 420×315; the stair-stepping on the
  lines is a scaling artifact, not a target.

### `03_wide_dense_chrome_sheet.png` — the excursion, not the hero
GIF frame 24. Camera has dollied in; line spacing has collapsed and the surface reads
as a solid rippling chrome plate.

- **Trust: this as a temporary state only.** Matt's call: the open raster is the
  hero, the dense sheet is a brief peak-energy excursion. It should be reachable and
  it should feel like an event.
- **Do NOT trust this as a material target.** It looks like brushed metal because a
  hundred slope-shaded lines happen to be adjacent — it is *not* a PBR chrome
  material and must not be authored as one. Chasing this as a material is the
  Kinetic Sculpture / Ferrofluid failure path (see `MENISCUS_PLAN.md` §7 risk R2).
- **Note the blue accents** in the agitated centre — the height→hue term again,
  reading high this time.

### `04_mid_droplet_spike_column.png` — the drop impact, isolated
GIF frame 36. A single tall cyan column standing on an otherwise near-flat plate,
seen almost edge-on with the ground plane clearly separated below.

- **Trust: T4, T5 strongly.** This is the clearest single frame for the two-layer
  composition and for what a drop impact should look like — a narrow, tall, distinctly
  coloured spike, not a broad swell.
- **Trust: the spike's aspect ratio.** It is much taller than it is wide. Impacts read
  as punctuation; broad heaves read as mush.
- **Do NOT trust: the near-empty frame.** Most of this image is black. Meniscus must
  clear D-037 and cannot ship a frame this empty as a resting state.

### `05_mid_packed_plate_tilt.png` — dense agitation, steep camera
GIF frame 8. The plate near-vertical in frame, heavily agitated, blue-white.

- **Trust: nothing structural.** Included as a range marker only.
- **Do NOT trust: the camera angle.** This near-edge-on/near-vertical extreme reads as
  a glitch rather than a viewpoint. Meniscus should bound the camera's tumble so it
  never reaches this attitude (`MENISCUS_PLAN.md` §4, camera contract).
- **Do NOT trust: the uniform agitation.** Violates T4.

### `06_wide_ANTI_near_black_silence.png` — **anti-reference**
GIF frame 0. The source at silence: a single thin line on black.

- **This is what Meniscus must NOT do.** It is a direct D-037 violation and it is why
  the silence state is a named product decision rather than an inherited behaviour.
- Keep it in the set as the negative check: any Meniscus contact sheet whose silence
  frame resembles this one has failed before tuning starts.

### `07_detail_ripple_interference.png` — shading and topology, close up
Crop of `01` at the disturbance.

- **Trust: T1 at maximum clarity.** The rounded polyline turnarounds are visible along
  the left margin; you can trace the single continuous path.
- **Trust: T3 at maximum clarity.** Watch how a crest goes to blown white over ~2px
  while the adjacent trough goes to black. That contrast ratio is the whole material
  read. A soft, evenly-lit version of this looks like fabric, not water.
- **Trust: the interference pattern.** Two overlapping ripple systems producing the
  chevron/wishbone shape. This is what "the music's texture made into a wake" actually
  looks like on screen, and it only appears when multiple drops are live at once.
- **Do NOT trust: the dotted/dashed appearance** on some lines. That is the source's
  fixed 45×45 grid sampling showing through at this zoom, i.e. undersampling, not a
  stylistic dash pattern.

---

## Anti-references — what Meniscus must NOT look like

1. **Black or near-black at silence** (`06`). D-037. Non-negotiable.
2. **A shaded solid surface.** If the lines close up into an unbroken skin at the
   resting camera distance, T1 is gone and the preset becomes a generic water shader.
3. **A PBR chrome / liquid-metal material.** See `03`. The material read must be an
   emergent property of line density and slope shading, never a hero material. This
   is the single largest fidelity risk on this preset.
4. **Uniform, all-over agitation.** Violates T4; reads as noise and destroys the
   "something just landed there" legibility that carries the musical role.
5. **Isotropic bloom.** Closes the raster gaps (see `02`). Glow spreads **sideways
   only** — in the source, that means screen-space X, not the line's local tangent.
   Under a rotating camera those two are not the same thing, and which one Meniscus
   uses is an open MEN.2a question (`MENISCUS_PLAN.md` §7 R1); what is *not* open is
   that the spread must be one-dimensional.
6. **A tumbling camera that reaches vertical or passes through the plate.** See `05`.
7. **Top-down or orthographic framing.** Violates T2. (Note this is the *opposite* of
   the Cymatic Resonance CR.1.2 correction, which moved *to* top-down — different
   preset, different contract; do not carry that lesson across.)
8. **Drops that fire on every frame.** Impacts are punctuation. If the drop rate rises
   to where individual impacts stop being distinguishable, the musical role is dead
   regardless of how good the surface looks.

---

## What this set is missing

Deliberately noted rather than silently absent, per the checklist's curation rule:

- **No non-source references.** Everything here is the source oracle. Before the
  palette and lighting are locked (MEN.3), curate 3–5 genuine references for the
  *look* we want that the source does not provide — candidates: long-exposure rain on
  dark water, sonar / bathymetric contour plots, oscilloscope raster photography,
  Joy Division `Unknown Pleasures` style stacked-ridge plots. File them here with the
  `_AIGEN` suffix where applicable (D-065 / D-066).
- **No motion reference for the silence state.** The chosen slow-standing-swell
  behaviour has no image in this set because the source has no such state. It is
  specified in prose in `MENISCUS_PLAN.md` §4 and must be judged from a rendered
  contact sheet, not from these frames.
- **No reference for the stem-region layout.** The drop-placement scheme is a
  Phosphene invention (§5); its legibility can only be assessed in motion against
  real music at M7.
