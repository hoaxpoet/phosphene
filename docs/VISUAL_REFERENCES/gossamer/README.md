# Gossamer — Visual References

Bioluminescent hero-web acting as a sonic resonator. A single irregular
orb-weaver web (17 explicit spoke angles per D-042, off-center hub at
UV (0.465, 0.32), Archimedean capture spiral) drawn against a near-black
scene. Vocal-pitch-keyed color waves propagate outward from the hub,
physically displacing silk strands as they pass; `mv_warp` accumulates
decaying echoes (decay 0.955).

**V.8 target (`SHADER_CRAFT.md §10.2`):**

- **Macro** — 17 irregular spokes (D-042); off-center hub clipping upper rings
  into arcs; high spiral turn count so the web reads as an instrument body,
  not a geometry study.
- **Meso** — physical wave displacement: each active wave offsets silk strand
  positions *perpendicular to the local tangent*. No pure palette shifts.
- **Micro** — silk Marschner-lite material
  (`azimuthal_r = 0.08, azimuthal_tt = 0.5, absorption = 0.3`).
- **Specular** — fine glints at thread intersections; chromatic aberration on
  the highest-amplitude wave peaks (RGB sampled at offset positions).
- **Atmosphere** — bioluminescent ambient haze in a ~0.5-radius halo around
  the web; dust motes drawn inward at high vocal energy, outward at silence.
- **Lighting** — nearly-black scene; web emission is the primary light source;
  SSGI projects soft fill onto the background.
- **Temporal** — `mv_warp` accumulates outward-propagating wave fronts as
  decaying echoes (decay 0.955); the hub-centered ring signature is a
  defining trait, not a side effect.
- **Audio** — waves vocal-pitch-keyed (current);
  propagation velocity = `2.0 + stems.vocals_energy_dev × 5.0`;
  wave amplitude drives displacement magnitude;
  dust drift velocity from `stems.vocals_energy_att`.

---

## Mandatory traits

### `01_macro_orb_geometry.jpg` — silver filament on near-black backdrop

> *Reference for: macro web geometry reading against a dim scene
> (`SHADER_CRAFT.md §10.2.1`).*

- Asymmetric orb structure with visibly irregular angular spacing between
  spokes — matches D-042 (never a uniform-grid-with-noise look).
- Hub sits off-center toward the top of frame; upper spiral rings are
  truncated into arcs by the frame boundary. Replicates the geometric
  consequence of UV (0.465, 0.32) hub placement.
- Silk reads as silvery-bright filament against the dark backdrop. Thread
  width ≈ 1 px at 1080p — fine, not chunky.
- **Caveat:** dewdrops on the spiral are an *Arachne* trait
  (`SHADER_CRAFT.md §10.1.3`), explicitly not Gossamer's. Cite this image
  for geometry and silver-on-black filament reading only; ignore the beading.

### `02_macro_thread_fineness.jpg` — concentric thread spacing

> *Reference for: spiral fineness and turn density
> (`SHADER_CRAFT.md §10.2.1`).*

- Each thread of the spiral is individually resolvable — no aliased blobs.
- Spacing increment is small relative to thread width; the spiral reads as
  a continuous instrument body, not a coarse skeleton.
- Backlight reveals every thread as a hairline highlight.
- **Caveat:** the photographed web is sheet/ladder geometry, not orb. Cite
  this image for thread fineness and turn density only. Spoke geometry is
  governed by D-042's explicit angle array, not by this image.

### `03_lighting_emission_filament_strands.jpg` — fanned fiber-optic strands with bright endpoints

> *Reference for: silk emission as the primary light source against
> near-zero ambient (`SHADER_CRAFT.md §10.2.6`); also doubles as endpoint
> specular glint reference (`§10.2.4`).*

- Fan of fine fiber-optic strands emitting teal light against a near-black
  field. Each strand is individually resolvable; the radial spread evokes
  spoke-field topology.
- **Endpoint specular signature**: each strand body is teal (the silk
  base color), and each tip is a small yellow-white pinpoint — the
  endpoint specular highlight is a *different color and brighter* than
  the underlying strand emission. This is the visual character V.8 needs
  for fine specular glints at high-energy points along a strand
  (`§10.2.4`).
- Frame edges fall to near-zero; halo is tight, visible only in immediate
  proximity to the strands.
- **Caveat:** photographed strands are roughly parallel (fanned from a
  single base), not radial-from-hub. Cite for the emission *regime* (zero
  ambient, fiber-fine emissive lines, body-vs-tip color separation)
  rather than spoke-field layout. D-042 governs spoke geometry.

### `04_lighting_ssgi_environmental_fill.jpg` — fungi lighting forest floor

> *Reference for: SSGI fill onto the background (`SHADER_CRAFT.md §10.2.6`).*

- Glowing fungi project soft green-cyan fill onto surrounding grass with
  falloff that reads bright at source, near-black at frame edges.
- Foliage detail is *visible* but only because of the emission — there is
  no environmental light. Background pixels gain perceptible color tint
  only within the source's proximity radius. This is the exact behavior
  Gossamer needs from SSGI sampling the silk emission.
- **Caveat:** in-frame foliage is not present in Gossamer; cite for the
  fill-falloff curve only, not for scene content.

### `05_meso_wave_propagation.jpg` — long-exposure standing waves

> *Reference for: wave propagation visible as transverse curve along a
> strand axis (`SHADER_CRAFT.md §10.2.2`).*

- Multiple overlapping sinusoidal traces against pure black. Demonstrates
  what a strand following a propagating transverse wave looks like when
  captured over time.
- Smaller secondary peaks visible at the trace tips suggest higher-frequency
  components — exactly the visual character we want when multiple
  vocal-pitch-keyed waves stack along a single radial.
- **Caveat:** photographed traces are unconstrained (free waves); silk in
  Gossamer is constrained at both endpoints (hub and outer attachment).
  The waveform character carries; the boundary conditions do not.

### `06_specular_chromatic_aberration.jpg` — striated field with CA fringes and amplitude peak

> *Reference for: chromatic aberration on wave peaks
> (`SHADER_CRAFT.md §10.2.4`); secondary reference for amplitude-peak
> rendering.*

- Vertical strand-like bands show CA fringes at their edges (cyan→purple
  shifts visible along band boundaries). Treat each vertical band as one
  Gossamer radial viewed at one moment; the band-edge fringes are the
  desired RGB-channel offset target.
- Central heat-map peak (red core → orange → yellow → green → blue
  periphery) renders a high-amplitude wave region with energy-mapped color
  falloff. Useful as a secondary reference for what a single wave's peak
  should LOOK like as it traverses the strand field, including the smearing
  character around the peak.
- **Caveat:** photographed color mapping is amplitude→hue (heat-map);
  Gossamer's wave color is YIN-pitch→hue with amplitude driving emission
  intensity, not color. Cite for the *visual signature* of CA fringes and
  for the energy-peak compositional character — not for the hue mapping.

### `07_temporal_mv_warp_echo.jpg` — concentric ring accumulation

> *Reference for: `mv_warp` temporal feedback decay (decay=0.955) and
> hub-centered wave-ring signature.*

- Concentric rings of color emanating outward from a central bright point,
  each progressively dimmer. Equivalent to a single long-exposure capture
  of what Gossamer should produce when wave rings retire and their
  luminance accumulates in the feedback texture.
- Central bright point reads as the hub; rings read as wave fronts at
  successive ages. This is essentially what one frame of accumulated
  `mv_warp` output should look like in Gossamer under steady vocal input.
- Ring spacing reads as roughly geometric (each successive ring slightly
  larger and dimmer than its predecessor) — the visual signature of
  exponential decay.
- **Caveat:** photo shows full-ring closure; in Gossamer waves propagate
  outward and are clipped by the screen edge. The decay character carries;
  the closure does not.

### `08_micro_silk_material.jpg` — folded gold satin

> *Reference for: silk Marschner-lite material — anisotropic axial
> highlight + transmission warmth (`SHADER_CRAFT.md §4.3, §10.2.3`).*

- Satin is woven silk; the broad band of axial sheen running across each
  fold is the Marschner R-lobe signature — a sharp specular line oriented
  along the fiber direction, perpendicular to surface curvature.
- Soft warm falloff at the edges of each fold shows the TT (transmission)
  lobe character: light entering the silk and re-emerging at a shifted
  angle with subtle warmth gain. This is what `azimuthal_tt = 0.5,
  absorption = 0.3` is reproducing.
- Smooth gradient between the bright sheen band and the shadowed regions
  — no sharp dielectric specular cut. Silk is glossy but not mirror-like.
- **Caveat:** gold palette is incidental — V.8 silk is keyed to vocal
  pitch hue, not gold. Cite for the *material reflectance signature*
  (axial sheen, soft TT falloff, gradient transition) rather than color.
  Also: Gossamer silk is filament-thin, not sheet-woven. The R-lobe
  character is what carries forward, not the surface area.

### `09_atmosphere_volumetric_halo_primary.jpg` — bioluminescent shoreline

> *Reference for: bioluminescent ambient haze around the web
> (`SHADER_CRAFT.md §10.2.5`); volumetric medium-luminance.*

- The blue glow exists *in the medium itself* (water + organisms), not on
  a surface. This is the trait V.8 needs: air around the web should be
  perceptibly luminous within ~0.5 UV of the hub, not just unlit black
  pixels with the web on top.
- Glow falloff is sharp at the medium's edge (rocks, distant horizon) and
  smooth within the medium — the exact gradient character a hub-centered
  haze halo should have.
- Sky above is near-black with stars; halo does not bleed into infinity.
  This bounds the halo radius — Gossamer's haze should not extend to the
  full frame.
- **Caveat:** photographed glow is horizontal-distributed (along a
  shoreline); Gossamer's halo is radial-from-hub. Cite for the volumetric
  character of the medium and for the falloff curve, not for the spatial
  distribution.

### `10_atmosphere_volumetric_halo_secondary.jpg` — aurora borealis

> *Reference for: hue-graded volumetric falloff at the halo perimeter
> (`SHADER_CRAFT.md §10.2.5`).*

- Aurora's green-to-purple hue shift across the volume demonstrates how
  emission color can shift across a luminous medium without breaking the
  illusion of a single light source. Useful for the halo perimeter where
  ambient haze color may shift slightly toward complementary hue.
- Smooth fade-to-black at the perimeter — no hard cutoff between glow and
  sky.
- Clean separation between the luminous medium and the dark surrounding
  void.
- **Caveat:** aurora has a directional sweep (curtain-like flow) that
  Gossamer's halo does not. Cite for the *gradient and fade character*
  only, not the directional flow.

### `11_meso_interference_bloom.jpg` — intersecting golden water ripples

> *Reference for: warm-white interference bloom where wave fronts overlap
> (`saturate(totalRingWeight - 1.0) × 0.45 × strandCov`).*

- Two distinct ripple sets visible: a primary set of concentric rings
  centered in frame, and a secondary set entering from upper right.
- Where the wave fronts intersect, the specular highlights brighten and
  warm — exactly the visual signature of two waves overlapping in
  Gossamer when their `totalRingWeight` exceeds 1.0.
- Specular glints at the crossing points are golden-warm against the
  surrounding cooler ripple field. This warm-shift on overlap is the
  effect to preserve.
- **Caveat:** photographed ripples are surface waves on water, not
  emission rings on strands. Cite for the *crossing-point brightening
  signature* (warmer, brighter where two wave sets overlap) rather than
  the water-surface specifics.

---

## Anti-references

### `99_anti_reference.jpg` — capture during V.8 kickoff

Frame-grab from current Gossamer v3 with annotation:

> NOT this — uniform palette-shift waves with no perpendicular strand
> displacement; silk reads as static grid; web is lit by ambient pixel
> color rather than projecting its own emission.

---

## Gaps still uncovered

**Inward/outward dust drift** (`SHADER_CRAFT.md §10.2.5`) — dust motes
drawn inward at high vocal energy, outward at silence — is still not
captured. Source as a short loop rather than a still: incense smoke under a
slowly oscillating fan is the canonical capture. Lowest priority of the
covered traits, since dust is a secondary atmospheric layer rather than a
defining characteristic.

**Node-intersection glints** (`SHADER_CRAFT.md §10.2.4` second clause) —
small specular highlights at points where strands cross. No real-world
photograph reliably captures this trait at the resolution and clarity
needed; slot 03's endpoint glints carry the related trait of
"point-intensified specular brighter than strand body," and the V.8
implementation will hit crossing-point glints from the §10.2.4 spec text
alone.

---

## Cross-references

- `SHADER_CRAFT.md §10.2` — Gossamer V.8 uplift plan
- `SHADER_CRAFT.md §4.3` — silk thread Marschner-lite recipe
- `SHADER_CRAFT.md §2.3` — reference-image discipline
- `DECISIONS.md D-042` — explicit spoke-angle array, off-center hub
- `DECISIONS.md D-026` — deviation-primitive audio routing
- `DECISIONS.md D-027` — `mv_warp` constraints
- `ENGINEERING_PLAN.md Increment V.8` — implementation scope
- `ENGINEERING_PLAN.md Increment MV-2` — `mv_warp` per-vertex feedback
